import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'sync_queue.dart';

/// Queues a write and tells the user, in plain words, whether it was sent or saved for later.
/// The per-action result (applied / not applied, with the reason) shows on the Sync screen.
Future<void> submitAction(
  BuildContext context,
  WidgetRef ref, {
  required String type,
  required int baseVersion,
  required Map<String, dynamic> payload,
  required String label,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final sent = await ref.read(syncQueueProvider.notifier).submit(type: type, baseVersion: baseVersion, payload: payload, label: label);
  final q = ref.read(syncQueueProvider);
  final mine = q.items.where((a) => a.label == label).toList();
  final rejected = mine.isNotEmpty && mine.last.status == QueuedStatus.rejected;
  final String message;
  if (!sent) {
    message = "Saved offline: $label. It will sync when you're back online.";
  } else if (rejected) {
    message = 'Not applied: ${mine.last.errorMessage ?? 'the server refused this change.'}';
  } else if (q.lastError != null) {
    message = q.lastError!;
  } else {
    message = 'Applied: $label';
  }
  messenger.showSnackBar(SnackBar(content: Text(message), duration: AppMotion.snackbar));
}

String newClientId(String prefix) => '$prefix-${SyncQueue.newActionId().substring(4)}';
