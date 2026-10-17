import 'package:flutter/material.dart';

import '../theme/status_colors.dart';
import '../theme/tokens.dart';

/// Pulsing LIVE dot (UI.md §7): FadeTransition 1.0↔0.35 over 1200 ms; static when animations are off.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 8, this.color});

  final double size;
  final Color? color;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotion.liveDot, lowerBound: 0.35, upperBound: 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: _c,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color ?? context.status.live, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// "● LIVE 67'" chip used under the score.
class LiveChip extends StatelessWidget {
  const LiveChip({super.key, this.minute, this.onDark = false});

  final int? minute;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = onDark ? scheme.onTertiary : context.status.live;
    final bg = onDark ? scheme.tertiary : scheme.surfaceContainerLowest;
    final label = minute == null ? 'LIVE' : "LIVE $minute'";
    return Semantics(
      label: minute == null ? 'Live' : 'Live, minute $minute',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveDot(color: fg),
            const SizedBox(width: AppSpace.xs + 2),
            Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
