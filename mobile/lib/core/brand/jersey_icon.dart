import 'package:flutter/material.dart';

/// Filled T-shirt glyph used for jersey products (the design's product art). Material has no
/// T-shirt icon, so it is painted.
class JerseyIcon extends StatelessWidget {
  const JerseyIcon({super.key, this.size = 40, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _JerseyPainter(color ?? Theme.of(context).colorScheme.primary)),
      ),
    );
  }
}

class _JerseyPainter extends CustomPainter {
  const _JerseyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;
    final path = Path()
      ..moveTo(w * 0.36, h * 0.12)
      ..quadraticBezierTo(w * 0.5, h * 0.26, w * 0.64, h * 0.12)
      ..lineTo(w * 0.94, h * 0.26)
      ..lineTo(w * 0.84, h * 0.46)
      ..lineTo(w * 0.73, h * 0.41)
      ..lineTo(w * 0.73, h * 0.9)
      ..lineTo(w * 0.27, h * 0.9)
      ..lineTo(w * 0.27, h * 0.41)
      ..lineTo(w * 0.16, h * 0.46)
      ..lineTo(w * 0.06, h * 0.26)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_JerseyPainter old) => old.color != color;
}
