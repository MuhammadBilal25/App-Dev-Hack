import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Loading skeleton (UI.md §6.7, §7): surface2 blocks pulsing 0.5↔1.0 opacity over 1 s.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.rows = 4, this.rowHeight = AppSize.rowMin});

  final int rows;
  final double rowHeight;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotion.skeleton, lowerBound: 0.5, upperBound: 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0.75;
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
    final block = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Semantics(
      identifier: 'loading_skeleton',
      label: 'Loading',
      excludeSemantics: true,
      child: FadeTransition(
        opacity: _c,
        child: Column(
          children: [
            for (var i = 0; i < widget.rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Container(
                  height: widget.rowHeight,
                  decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
