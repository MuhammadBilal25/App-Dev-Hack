import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/connectivity/connectivity.dart';
import '../../core/layout/page_body.dart';
import '../../core/sync/sync_queue.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';

/// Every queued offline action with its own result in plain words (UI.md §9, Task C).
class SyncQueueScreen extends ConsumerWidget {
  const SyncQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(syncQueueProvider);
    final online = ref.watch(isOnlineProvider);
    final notifier = ref.read(syncQueueProvider.notifier);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final pending = q.items.where((a) => a.status == QueuedStatus.pending).toList();
    final done = q.items.where((a) => a.status != QueuedStatus.pending).toList();

    final headline = q.pendingCount == 0 ? 'Nothing waiting' : '${q.pendingCount} waiting';
    final explain = q.pendingCount == 0
        ? "You're all caught up."
        : online
            ? 'Sending to the server now.'
            : 'Saved on this phone. They will be sent automatically when the connection returns.';

    return Scaffold(
      appBar: const TenantAppBar(title: 'Sync'),
      body: Column(
        children: [
          const SyncStrip(showViewAction: false),
          Expanded(
            child: Semantics(
              identifier: 'sync_queue_screen',
              container: true,
              child: PageBody(
                children: [
                  Semantics(
                    identifier: 'sync_summary',
                    container: true,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(headline, style: text.headlineSmall!.copyWith(fontSize: 30, height: 1.2)),
                          const SizedBox(height: AppSpace.sm),
                          Text(explain, style: text.bodyLarge!.copyWith(color: muted)),
                        ],
                      ),
                    ),
                  ),
                  if (q.lastError != null) ...[
                    const SizedBox(height: AppSpace.lg),
                    ErrorBanner(id: 'sync_error', message: q.lastError!, onRetry: online ? notifier.flush : null),
                  ],
                  if (pending.isNotEmpty) ...[
                    const SectionLabel('Pending actions'),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < pending.length; i++) ...[
                            if (i > 0) const Divider(),
                            _PendingRow(action: pending[i], syncing: q.syncing),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (done.isNotEmpty) ...[
                    const SectionLabel('Last sync'),
                    for (final a in done) ...[_ResultBanner(action: a), const SizedBox(height: AppSpace.md)],
                  ],
                  const SizedBox(height: AppSpace.xl),
                  if (q.pendingCount > 0)
                    AppButton(
                      id: 'sync_now',
                      label: online ? 'Sync now' : 'Sync now · waiting for connection',
                      loading: q.syncing,
                      onPressed: online ? notifier.flush : null,
                    ),
                  if (q.rejectedCount > 0) ...[
                    const SizedBox(height: AppSpace.md),
                    AppButton(
                      id: 'sync_clear_rejected',
                      label: 'Dismiss actions not applied',
                      variant: AppButtonVariant.secondary,
                      onPressed: notifier.clearRejected,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _kind(QueuedAction a) => switch (a.type) {
      'score_event' => 'Score',
      _ => 'Roster',
    };

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.action, required this.syncing});

  final QueuedAction action;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final queued = DateTime.tryParse(action.queuedAt)?.toLocal();
    return Semantics(
      identifier: 'sync_item_${action.actionId}',
      container: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.schedule, size: 22, color: scheme.primary),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_kind(action)} · ${action.label}', style: text.titleMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                  if (queued != null) Text('Queued ${DateFormat.Hm().format(queued)}', style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.medium),
              child: syncing
                  ? const StatusChip(key: ValueKey('syncing'), kind: StatusKind.info, label: 'Syncing…', icon: Icons.sync)
                  : const StatusChip(key: ValueKey('pending'), kind: StatusKind.info, label: 'Pending', icon: Icons.timer_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

/// Applied (success) or not applied (danger, with the plain-language reason).
class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.action});

  final QueuedAction action;

  @override
  Widget build(BuildContext context) {
    final applied = action.status == QueuedStatus.applied;
    final c = applied ? context.status.success : context.status.danger;
    final text = Theme.of(context).textTheme;
    final what = action.label[0].toLowerCase() + action.label.substring(1);
    final reason = applied ? '' : ' ${action.errorMessage ?? ''}';
    return Semantics(
      identifier: 'sync_item_${action.actionId}',
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(applied ? Icons.check : Icons.close, size: 20, color: c.fg),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: applied ? 'Applied: ' : 'Not applied: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: '$what.$reason'),
                  ],
                ),
                style: text.bodyLarge!.copyWith(color: c.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
