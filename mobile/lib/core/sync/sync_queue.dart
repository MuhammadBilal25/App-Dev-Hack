import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../data/providers.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../copy/error_messages.dart';
import '../connectivity/connectivity.dart';
import '../settings/settings.dart';

/// Overridden in `main()` with the box opened before `runApp`.
final syncBoxProvider = Provider<Box<String>>((ref) => throw UnimplementedError('syncBoxProvider not overridden'));

const syncBoxName = 'sync_queue';

enum QueuedStatus { pending, applied, rejected }

/// One offline action, shaped like an item of the offline-sync contract plus display fields.
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

  /// `score_event` or `roster_transfer` (sent through `POST /api/v1/sync`), or `player_add` (sent to
  /// `POST /api/v1/clubs/{club_id}/players`, idempotent through its request_id).
  final String type;
  final String queuedAt;
  final int baseVersion;
  final Map<String, dynamic> payload;

  /// What the user did, in words ("Goal for Alpha Falcons FC").
  final String label;
  final QueuedStatus status;
  final String? errorCode;

  String? get errorMessage => errorCode == null ? null : messageFor(errorCode, status: 409);

  QueuedAction withStatus(QueuedStatus s, [String? code]) => QueuedAction(
        actionId: actionId,
        type: type,
        queuedAt: queuedAt,
        baseVersion: baseVersion,
        payload: payload,
        label: label,
        status: s,
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
/// authenticated `POST /api/v1/sync` (offline-sync contract plus a per-action permission check);
/// each action gets its own applied / rejected result.
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

  /// Queues an action and, when online, sends it straight away. Returns true if it was sent now.
  Future<bool> submit({
    required String type,
    required int baseVersion,
    required Map<String, dynamic> payload,
    required String label,
  }) async {
    await enqueue(type: type, baseVersion: baseVersion, payload: payload, label: label);
    if (!ref.read(isOnlineProvider)) return false;
    await flush();
    return true;
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
    final all = state.items.where((a) => a.status == QueuedStatus.pending).toList();
    if (all.isEmpty || state.syncing) return;
    state = state.copyWith(syncing: true, clearError: true);
    final adds = all.where((a) => a.type == 'player_add').toList();
    final pending = all.where((a) => a.type != 'player_add').take(100).toList();
    try {
      for (final a in adds) {
        try {
          await ref.read(apiClientProvider).post(
                '/api/v1/clubs/${Uri.encodeComponent(a.payload['club_id'] as String)}/players',
                body: a.payload['body'],
              );
          await _box.delete(a.actionId);
          _replace(a.withStatus(QueuedStatus.applied));
          _clearLater([a.actionId]);
        } on ApiException catch (e) {
          if (e.isNetwork) rethrow;
          final updated = a.withStatus(QueuedStatus.rejected, e.code);
          await _box.put(a.actionId, jsonEncode(updated.toJson()));
          _replace(updated);
        }
        _refreshAffected([a]);
      }
      if (pending.isEmpty) {
        state = state.copyWith(syncing: false);
        return;
      }
      final res = await ref.read(apiClientProvider).post(
            '/api/v1/sync',
            body: {
              'device_id': ref.read(settingsProvider.notifier).deviceId(),
              'actions': pending.map((a) => a.toWire()).toList(),
            },
          ) as Map<String, dynamic>;
      final results = {
        for (final r in (res['results'] as List).cast<Map<String, dynamic>>()) r['action_id'] as String: r,
      };
      final next = <QueuedAction>[];
      final applied = <String>[];
      for (final a in state.items) {
        final r = results[a.actionId];
        if (r == null) {
          next.add(a);
        } else if (r['status'] == 'rejected') {
          final updated = a.withStatus(QueuedStatus.rejected, r['error_code'] as String?);
          await _box.put(a.actionId, jsonEncode(updated.toJson()));
          next.add(updated);
        } else {
          // Applied (or an already-applied duplicate): gone from disk now, shown as "Applied"
          // for a moment, then cleared.
          await _box.delete(a.actionId);
          next.add(a.withStatus(QueuedStatus.applied));
          applied.add(a.actionId);
        }
      }
      _refreshAffected(pending);
      _clearLater(applied);
      state = state.copyWith(items: next, syncing: false);
    } on ApiException catch (e) {
      state = state.copyWith(syncing: false, lastError: e.message);
    }
  }

  void _replace(QueuedAction a) =>
      state = state.copyWith(items: [for (final x in state.items) x.actionId == a.actionId ? a : x]);

  /// Applied actions show "Applied" for a moment, then leave the list.
  void _clearLater(List<String> ids) {
    if (ids.isEmpty) return;
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!ref.mounted) return;
      state = state.copyWith(items: state.items.where((a) => !ids.contains(a.actionId)).toList());
    });
  }

  /// Refetches the screens whose data the synced actions touched.
  void _refreshAffected(List<QueuedAction> sent) {
    for (final a in sent) {
      if (a.type == 'score_event') {
        final matchId = a.payload['match_id'];
        if (matchId is String) ref.invalidate(matchProvider(matchId));
        ref.invalidate(fixturesProvider);
        ref.invalidate(standingsProvider);
        ref.invalidate(homeProvider);
        ref.invalidate(leagueProvider);
        ref.invalidate(organizerDashboardProvider);
      } else {
        for (final k in ['from_squad_id', 'to_squad_id', 'club_id']) {
          final club = a.payload[k];
          if (club is String) ref.invalidate(clubProvider(club));
        }
        ref.invalidate(managerDashboardProvider);
        ref.invalidate(rosterHistoryProvider);
      }
    }
  }
}

final syncQueueProvider = NotifierProvider<SyncQueue, SyncQueueState>(SyncQueue.new);
