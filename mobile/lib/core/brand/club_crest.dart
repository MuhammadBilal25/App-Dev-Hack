import 'package:flutter/material.dart';

import '../theme/tenant.dart';
import '../theme/typography.dart';

/// Auto-generated club crest (UI.md §0.4): shield in surface2 with a 2 px tenant-brand outline
/// and the club initials in Manrope 800. 24 dp in lists, 44 dp in match header, 76 dp on profile.
class ClubCrest extends StatelessWidget {
  const ClubCrest({super.key, required this.name, this.size = 24, this.decorative = true});

  final String name;
  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = initialsOf(name);
    final crest = SizedBox(
      width: size,
      height: size * 1.15,
      child: CustomPaint(
        painter: _ShieldPainter(fill: scheme.surfaceContainerHigh, outline: scheme.primary, stroke: size < 32 ? 1.5 : 2),
        child: Padding(
          padding: EdgeInsets.only(bottom: size * 0.12),
          child: Center(
            child: Text(
              initials,
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontWeight: FontWeight.w800,
                fontSize: size * (initials.length > 2 ? 0.28 : 0.36),
                color: scheme.onSurface,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
    if (decorative) return ExcludeSemantics(child: crest);
    return Semantics(label: '$name crest', image: true, excludeSemantics: true, child: crest);
  }
}

class _ShieldPainter extends CustomPainter {
  const _ShieldPainter({required this.fill, required this.outline, required this.stroke});

  final Color fill;
  final Color outline;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final i = stroke / 2;
    final path = Path()
      ..moveTo(w / 2, i)
      ..lineTo(w - i, h * 0.16)
      ..lineTo(w - i, h * 0.5)
      ..quadraticBezierTo(w - i, h * 0.82, w / 2, h - i)
      ..quadraticBezierTo(i, h * 0.82, i, h * 0.5)
      ..lineTo(i, h * 0.16)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.fill != fill || old.outline != outline || old.stroke != stroke;
}
