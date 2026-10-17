import 'package:flutter/material.dart';

/// Type scale from UI.md §4. Sora for display and numbers, Manrope for body and UI.
class AppFonts {
  static const display = 'Sora';
  static const body = 'Manrope';

  /// Scores, prices and table numbers use tabular figures so digits don't jump.
  static const tabular = [FontFeature.tabularFigures()];
}

TextStyle _style(String family, double size, double line, FontWeight weight, Color color, {double spacing = 0}) => TextStyle(
      fontFamily: family,
      fontSize: size,
      height: line / size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
    );

TextTheme buildTextTheme({required Color text, required Color muted}) {
  return TextTheme(
    displayMedium: _style(AppFonts.display, 44, 48, FontWeight.w700, text).copyWith(fontFeatures: AppFonts.tabular),
    headlineSmall: _style(AppFonts.display, 24, 32, FontWeight.w700, text),
    titleLarge: _style(AppFonts.display, 18, 24, FontWeight.w700, text),
    titleMedium: _style(AppFonts.body, 16, 22, FontWeight.w700, text),
    bodyLarge: _style(AppFonts.body, 16, 24, FontWeight.w400, text),
    bodyMedium: _style(AppFonts.body, 14, 20, FontWeight.w500, text),
    labelLarge: _style(AppFonts.body, 15, 20, FontWeight.w800, text),
    // Section labels are UPPERCASE with +0.06em tracking (0.06 × 13 sp).
    bodySmall: _style(AppFonts.body, 13, 18, FontWeight.w600, muted, spacing: 0.78),
    labelSmall: _style(AppFonts.body, 12, 16, FontWeight.w800, text),
    // Not in the scale table; kept at body sizes so nothing falls below 12 sp.
    labelMedium: _style(AppFonts.body, 13, 18, FontWeight.w700, text),
    titleSmall: _style(AppFonts.body, 14, 20, FontWeight.w700, text),
    headlineMedium: _style(AppFonts.display, 24, 32, FontWeight.w700, text),
  );
}
