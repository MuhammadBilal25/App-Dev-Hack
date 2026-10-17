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
import '../../core/widgets/empty_state.dart';
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
    final time = DateFormat.Hm();

    return Scaffold(
      appBar: const TenantAppBar(title: 'Sync queue'),
      body: Column(
        children: [
          const SyncStrip(showViewAction: false),
          Expanded(
            child: Semantics(
              identifier: 'sync_queue_screen',
              container: true,
              child: PageBody(
                children: [
                  if (q.lastError != null) ...[
                    ErrorBanner(id: 'sync_error', message: q.lastError!, onRetry: online ? notifier.flush : null),
                    const SizedBox(height: AppSpace.lg),
                  ],
                  if (q.items.isEmpty)
                    const EmptyState(
                      id: 'sync_queue_empty',
                      icon: Icons.cloud_done_outlined,
                      message: "Nothing waiting. You're all caught up.",
                    )
                  else ...[
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < q.items.length; i++) ...[
                            if (i > 0) const Divider(),
                            _QueueRow(action: q.items[i], time: time, syncing: q.syncing),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    if (q.pendingCount > 0)
                      AppButton(
                        id: 'sync_now',
                        label: online ? 'Sync now' : 'Sync now · waiting for connection',
                        icon: Icons.sync,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.action, required this.time, required this.syncing});

  final QueuedAction action;
  final DateFormat time;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rejected = action.status == QueuedStatus.rejected;
    final applied = action.status == QueuedStatus.applied;
    final queued = DateTime.tryParse(action.queuedAt)?.toLocal();
    return Semantics(
      identifier: 'sync_item_${action.actionId}',
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.rowMin),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(action.label, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: AppSpace.sm),
                  AnimatedSwitcher(
                    duration: AppMotion.of(context, AppMotion.medium),
                    child: applied
                        ? const StatusChip(key: ValueKey('applied'), kind: StatusKind.success, label: 'Applied', icon: Icons.check)
                        : rejected
                        ? const StatusChip(key: ValueKey('rejected'), kind: StatusKind.danger, label: 'Not applied', icon: Icons.close)
                        : syncing
                            ? const StatusChip(key: ValueKey('syncing'), kind: StatusKind.info, label: 'Syncing…', icon: Icons.sync)
                            : const StatusChip(key: ValueKey('pending'), kind: StatusKind.warning, label: 'Pending', icon: Icons.schedule),
                  ),
                ],
              ),
              if (queued != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text('Saved at ${time.format(queued)}', style: text.bodySmall!.copyWith(letterSpacing: 0)),
              ],
              if (rejected && action.errorMessage != null) ...[
                const SizedBox(height: AppSpace.sm),
                Text(action.errorMessage!, style: text.bodyMedium!.copyWith(color: context.status.danger.fg)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
