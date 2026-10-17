import 'package:flutter/material.dart';

/// Every colour, spacing, radius and duration in the app comes from this file (UI.md §3, §5, §7).
/// Widgets never use these colours directly: they read `Theme.of(context).colorScheme` or
/// `context.status`. Only the theme builder and brand painters touch [AppPalette].
class AppPalette {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.divider,
    required this.inputBorder,
    required this.text,
    required this.muted,
    required this.cta,
    required this.onCta,
    required this.snackBg,
    required this.snackText,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color divider;
  final Color inputBorder;
  final Color text;
  final Color muted;
  final Color cta;
  final Color onCta;
  final Color snackBg;
  final Color snackText;

  static const light = AppPalette(
    bg: Color(0xFFF4F6F8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F5F9),
    divider: Color(0xFFE2E7EC),
    inputBorder: Color(0xFF748297),
    text: Color(0xFF121A23),
    muted: Color(0xFF4B5866),
    cta: Color(0xFFC2410C),
    onCta: Color(0xFFFFFFFF),
    snackBg: Color(0xFF121A23),
    snackText: Color(0xFFE8EDF3),
  );

  static const dark = AppPalette(
    bg: Color(0xFF0B1220),
    surface: Color(0xFF131C2B),
    surface2: Color(0xFF1A2536),
    divider: Color(0xFF263247),
    inputBorder: Color(0xFF64748B),
    text: Color(0xFFE8EDF3),
    muted: Color(0xFFA3B0BF),
    cta: Color(0xFFFB923C),
    onCta: Color(0xFF1A0E05),
    snackBg: Color(0xFFE8EDF3),
    snackText: Color(0xFF121A23),
  );

  static AppPalette of(Brightness b) => b == Brightness.dark ? dark : light;
}

/// Brand colours of the huddle mark itself (UI.md §0.2). Used only by `HuddleMark`.
class HuddleColors {
  static const ballLight = Color(0xFFC2410C);
  static const dotsLight = Color(0xFF1D4ED8);
  static const ballDark = Color(0xFFFB923C);
  static const dotsDark = Color(0xFF8AB4FF);
  static const ballOnBrand = Color(0xFFFDBA74);
  static const dotsOnBrand = Color(0xFFFFFFFF);
  static const splashLight = Color(0xFFFFF7ED);
  static const splashDark = Color(0xFF0B1220);
}

class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 999;
}

class AppSize {
  static const double touch = 48;
  static const double buttonPrimary = 54;
  static const double buttonSecondary = 48;
  static const double buttonInline = 40;
  static const double appBar = 56;
  static const double syncStripOnline = 32;
  static const double syncStripOffline = 40;
  static const double bottomNav = 72;
  static const double inputHeight = 52;
  static const double rowMin = 56;
  static const double maxContentWidth = 600;
  static const double borderInput = 1.5;
  static const double borderFocus = 2;
}

class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 350);
  static const liveDot = Duration(milliseconds: 1200);
  static const skeleton = Duration(milliseconds: 1000);
  static const snackbar = Duration(seconds: 4);

  static const fastCurve = Curves.easeOut;
  static const mediumCurve = Curves.easeOutCubic;
  static const slowCurve = Curves.easeInOutCubicEmphasized;

  /// Returns [d], or zero when the user asked the system to remove animations (UI.md §7).
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}
