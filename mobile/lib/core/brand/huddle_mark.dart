import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

enum HuddleMarkVariant { light, dark, mono, onBrand }

/// The huddle mark (UI.md §0.2): six club dots around one larger centre ball, drawn on a
/// 48×48 grid. Never recolour the dots individually, stretch, rotate or outline it.
class HuddleMark extends StatelessWidget {
  const HuddleMark({super.key, this.size = 48, this.variant, this.monoColor});

  final double size;

  /// Defaults to light or dark from the current theme.
  final HuddleMarkVariant? variant;

  /// Colour for [HuddleMarkVariant.mono]; defaults to the text colour.
  final Color? monoColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = variant ?? (theme.brightness == Brightness.dark ? HuddleMarkVariant.dark : HuddleMarkVariant.light);
    final mono = monoColor ?? theme.colorScheme.onSurface;
    final (ball, dots) = switch (v) {
      HuddleMarkVariant.light => (HuddleColors.ballLight, HuddleColors.dotsLight),
      HuddleMarkVariant.dark => (HuddleColors.ballDark, HuddleColors.dotsDark),
      HuddleMarkVariant.onBrand => (HuddleColors.ballOnBrand, HuddleColors.dotsOnBrand),
      HuddleMarkVariant.mono => (mono, mono),
    };
    return ExcludeSemantics(
      child: SizedBox.square(dimension: size, child: CustomPaint(painter: HuddleMarkPainter(ball: ball, dots: dots))),
    );
  }
}

class HuddleMarkPainter extends CustomPainter {
  const HuddleMarkPainter({required this.ball, required this.dots});

  final Color ball;
  final Color dots;

  static const _dots = [
    Offset(39, 24),
    Offset(31.5, 37),
    Offset(16.5, 37),
    Offset(9, 24),
    Offset(16.5, 11),
    Offset(31.5, 11),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 48;
    canvas.save();
    canvas.scale(s);
    final dotPaint = Paint()..color = dots;
    for (final o in _dots) {
      canvas.drawCircle(o, 4.5, dotPaint);
    }
    canvas.drawCircle(const Offset(24, 24), 7, Paint()..color = ball);
    canvas.restore();
  }

  @override
  bool shouldRepaint(HuddleMarkPainter old) => old.ball != ball || old.dots != dots;
}

/// "huddle" wordmark: always lowercase, Manrope 800, −0.02em tracking.
class HuddleWordmark extends StatelessWidget {
  const HuddleWordmark({super.key, this.fontSize = 22});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'huddle',
      style: TextStyle(
        fontFamily: AppFonts.body,
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
        height: 1.1,
        letterSpacing: -0.02 * fontSize,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// Mark + 12 px gap + wordmark; mark height is 1.3× the wordmark cap height (~0.72 em).
class HuddleLockup extends StatelessWidget {
  const HuddleLockup({super.key, this.fontSize = 22});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'huddle',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HuddleMark(size: fontSize * 0.72 * 1.3 * 1.4),
          const SizedBox(width: AppSpace.md),
          HuddleWordmark(fontSize: fontSize),
        ],
      ),
    );
  }
}
