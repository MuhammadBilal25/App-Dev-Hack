import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../connectivity/connectivity.dart';
import '../sync/sync_queue.dart';
import '../theme/status_colors.dart';
import '../theme/tokens.dart';

enum SyncStripState { online, offline, syncing, rejected }

/// Always-visible sync strip directly below the app bar (UI.md §6.5, NFR-4). A live region, so
/// screen readers announce every change.
class SyncStrip extends ConsumerStatefulWidget {
  const SyncStrip({super.key, this.showViewAction = true});

  /// False on the sync queue screen itself, where "View" would lead nowhere.
  final bool showViewAction;

  @override
  ConsumerState<SyncStrip> createState() => _SyncStripState();
}

class _SyncStripState extends ConsumerState<SyncStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final q = ref.watch(syncQueueProvider);
    final pending = q.pendingCount;

    final SyncStripState s;
    if (q.syncing || (online && pending > 0)) {
      s = SyncStripState.syncing;
    } else if (!online) {
      s = SyncStripState.offline;
    } else if (q.rejectedCount > 0) {
      s = SyncStripState.rejected;
    } else {
      s = SyncStripState.online;
    }

    final status = context.status;
    final actions = pending == 1 ? '1 action' : '$pending actions';
    final rejected = q.rejectedCount == 1 ? '1 action not applied' : '${q.rejectedCount} actions not applied';
    final (StatusPair c, IconData icon, String text, bool hasAction) = switch (s) {
      SyncStripState.online => (status.success, Icons.check_circle_outline, 'Online · all changes synced', false),
      SyncStripState.offline => (status.warning, Icons.wifi_off, 'Offline · $actions waiting', true),
      SyncStripState.syncing => (status.info, Icons.sync, 'Syncing $actions…', false),
      SyncStripState.rejected => (status.danger, Icons.cancel_outlined, rejected, true),
    };

    final animate = !MediaQuery.disableAnimationsOf(context);
    if (s == SyncStripState.syncing && animate) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }

    final showAction = hasAction && widget.showViewAction;
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(color: c.fg, fontWeight: FontWeight.w700);

    return Semantics(
      identifier: 'sync_strip',
      liveRegion: true,
      container: true,
      label: text,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.medium),
        curve: AppMotion.mediumCurve,
        constraints: BoxConstraints(minHeight: showAction ? AppSize.syncStripOffline : AppSize.syncStripOnline),
        color: c.bg,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: Row(
          children: [
            ExcludeSemantics(
              child: s == SyncStripState.syncing
                  ? RotationTransition(turns: _spin, child: Icon(icon, size: 16, color: c.fg))
                  : Icon(icon, size: 16, color: c.fg),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: ExcludeSemantics(child: Text(text, style: textStyle, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ),
            ),
            if (showAction)
              Semantics(
                identifier: 'sync_strip_view',
                button: true,
                label: 'View sync queue',
                excludeSemantics: true,
                child: TextButton(
                  onPressed: () => context.push('/sync'),
                  style: TextButton.styleFrom(
                    foregroundColor: c.fg,
                    minimumSize: const Size(AppSize.touch, AppSize.syncStripOffline),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('View', style: TextStyle(decoration: TextDecoration.underline)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
