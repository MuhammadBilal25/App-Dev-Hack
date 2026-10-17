import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../copy/error_messages.dart';
import '../settings/settings.dart';

/// Overridden in `main()` with the box opened before `runApp`.
final syncBoxProvider = Provider<Box<String>>((ref) => throw UnimplementedError('syncBoxProvider not overridden'));

const syncBoxName = 'sync_queue';

enum QueuedStatus { pending, rejected }

/// One offline action, shaped like an item of `POST /audit/v1/offline-sync` plus display fields.
/// Survives force-close because it is stored in Hive.
class QueuedAction {
  const QueuedAction({
    required this.actionId,
    required this.type,
    required this.queuedAt,
    required this.baseVersion,
    required this.payload,
    required this.label,
    this.status = QueuedStatus.pending,
    this.errorCode,
  });

  final String actionId;

  /// `score_event` or `roster_transfer`.
  final String type;
  final String queuedAt;
  final int baseVersion;
  final Map<String, dynamic> payload;

  /// What the user did, in words ("Goal for Alpha Falcons FC").
  final String label;
  final QueuedStatus status;
  final String? errorCode;

  String? get errorMessage => errorCode == null ? null : messageFor(errorCode, status: 409);

  QueuedAction rejected(String? code) => QueuedAction(
        actionId: actionId,
        type: type,
        queuedAt: queuedAt,
        baseVersion: baseVersion,
        payload: payload,
        label: label,
        status: QueuedStatus.rejected,
        errorCode: code,
      );

  Map<String, dynamic> toWire() => {
        'action_id': actionId,
        'type': type,
        'queued_at': queuedAt,
        'base_version': baseVersion,
        'payload': payload,
      };

  Map<String, dynamic> toJson() => {...toWire(), 'label': label, 'status': status.name, 'error_code': errorCode};

  factory QueuedAction.fromJson(Map<String, dynamic> j) => QueuedAction(
        actionId: j['action_id'] as String,
        type: j['type'] as String,
        queuedAt: j['queued_at'] as String,
        baseVersion: (j['base_version'] as num).toInt(),
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        label: (j['label'] as String?) ?? (j['type'] as String),
        status: QueuedStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => QueuedStatus.pending),
        errorCode: j['error_code'] as String?,
      );
}

class SyncQueueState {
  const SyncQueueState({this.items = const [], this.syncing = false, this.lastError});

  final List<QueuedAction> items;
  final bool syncing;

  /// Plain-language reason the last sync attempt failed as a whole (e.g. network).
  final String? lastError;

  int get pendingCount => items.where((a) => a.status == QueuedStatus.pending).length;
  int get rejectedCount => items.where((a) => a.status == QueuedStatus.rejected).length;

  SyncQueueState copyWith({List<QueuedAction>? items, bool? syncing, String? lastError, bool clearError = false}) => SyncQueueState(
        items: items ?? this.items,
        syncing: syncing ?? this.syncing,
        lastError: clearError ? null : lastError ?? this.lastError,
      );
}

/// Durable queue of writes made while offline. Writes are replayed in one batch through the
/// backend's offline-sync contract; each action gets its own applied / rejected result.
class SyncQueue extends Notifier<SyncQueueState> {
  Box<String> get _box => ref.read(syncBoxProvider);

  @override
  SyncQueueState build() {
    final box = ref.watch(syncBoxProvider);
    final items = box.values.map((s) => QueuedAction.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return SyncQueueState(items: items);
  }

  static String newActionId() {
    final r = Random.secure();
    return 'act-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  /// `YYYY-MM-DDTHH:MM:SSZ`, the format the backend validates.
  static String nowStamp() => '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';

  Future<QueuedAction> enqueue({
    required String type,
    required int baseVersion,
    required Map<String, dynamic> payload,
    required String label,
  }) async {
    final a = QueuedAction(
      actionId: newActionId(),
      type: type,
      queuedAt: nowStamp(),
      baseVersion: baseVersion,
      payload: payload,
      label: label,
    );
    await _box.put(a.actionId, jsonEncode(a.toJson()));
    state = state.copyWith(items: [...state.items, a]);
    return a;
  }

  Future<void> remove(String actionId) async {
    await _box.delete(actionId);
    state = state.copyWith(items: state.items.where((a) => a.actionId != actionId).toList());
  }

  Future<void> clearRejected() async {
    for (final a in state.items.where((a) => a.status == QueuedStatus.rejected)) {
      await _box.delete(a.actionId);
    }
    state = state.copyWith(items: state.items.where((a) => a.status != QueuedStatus.rejected).toList());
  }

  /// Sends every pending action. Applied and duplicate results leave the queue; rejected ones stay
  /// with their reason until the user dismisses them.
  Future<void> flush() async {
    final pending = state.items.where((a) => a.status == QueuedStatus.pending).take(100).toList();
    if (pending.isEmpty || state.syncing) return;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final res = await ref.read(apiClientProvider).post(
            '/audit/v1/offline-sync',
            body: {
              'device_id': ref.read(settingsProvider.notifier).deviceId(),
              'actions': pending.map((a) => a.toWire()).toList(),
            },
          ) as Map<String, dynamic>;
      final results = {
        for (final r in (res['results'] as List).cast<Map<String, dynamic>>()) r['action_id'] as String: r,
      };
      final next = <QueuedAction>[];
      for (final a in state.items) {
        final r = results[a.actionId];
        if (r == null) {
          next.add(a);
        } else if (r['status'] == 'rejected') {
          final updated = a.rejected(r['error_code'] as String?);
          await _box.put(a.actionId, jsonEncode(updated.toJson()));
          next.add(updated);
        } else {
          await _box.delete(a.actionId);
        }
      }
      state = state.copyWith(items: next, syncing: false);
    } on ApiException catch (e) {
      state = state.copyWith(syncing: false, lastError: e.message);
    }
  }
}

final syncQueueProvider = NotifierProvider<SyncQueue, SyncQueueState>(SyncQueue.new);
