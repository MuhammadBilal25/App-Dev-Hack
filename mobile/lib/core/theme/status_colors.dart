import 'package:flutter/material.dart';

/// One background/foreground pair for a status (UI.md §3.2).
@immutable
class StatusPair {
  const StatusPair(this.bg, this.fg);

  final Color bg;
  final Color fg;

  StatusPair lerp(StatusPair other, double t) =>
      StatusPair(Color.lerp(bg, other.bg, t)!, Color.lerp(fg, other.fg, t)!);
}

enum StatusKind { success, warning, danger, neutral, info }

/// Status colours as a ThemeExtension, read with `context.status`. Colour is never the only
/// signal: every use pairs it with an icon and a word.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.neutral,
    required this.info,
    required this.live,
    required this.destructive,
    required this.snackBg,
    required this.snackText,
  });

  final StatusPair success;
  final StatusPair warning;
  final StatusPair danger;
  final StatusPair neutral;
  final StatusPair info;

  /// LIVE text colour (the CTA colour on surface).
  final Color live;

  /// Border and text of destructive buttons.
  final Color destructive;

  final Color snackBg;
  final Color snackText;

  factory StatusColors.light({required StatusPair info, required Color live, required Color snackBg, required Color snackText}) =>
      StatusColors(
        success: const StatusPair(Color(0xFFDCFCE7), Color(0xFF14532D)),
        warning: const StatusPair(Color(0xFFFEF3C7), Color(0xFF78350F)),
        danger: const StatusPair(Color(0xFFFEE2E2), Color(0xFF7F1D1D)),
        neutral: const StatusPair(Color(0xFFF1F5F9), Color(0xFF334155)),
        info: info,
        live: live,
        destructive: const Color(0xFF991B1B),
        snackBg: snackBg,
        snackText: snackText,
      );

  factory StatusColors.dark({required StatusPair info, required Color live, required Color snackBg, required Color snackText}) =>
      StatusColors(
        success: const StatusPair(Color(0xFF0F2E1D), Color(0xFF86EFAC)),
        warning: const StatusPair(Color(0xFF2E230B), Color(0xFFFCD34D)),
        danger: const StatusPair(Color(0xFF3A1414), Color(0xFFFCA5A5)),
        neutral: const StatusPair(Color(0xFF1A2536), Color(0xFFC9D3DC)),
        info: info,
        live: live,
        destructive: const Color(0xFFFCA5A5),
        snackBg: snackBg,
        snackText: snackText,
      );

  StatusPair of(StatusKind kind) => switch (kind) {
        StatusKind.success => success,
        StatusKind.warning => warning,
        StatusKind.danger => danger,
        StatusKind.neutral => neutral,
        StatusKind.info => info,
      };

  @override
  StatusColors copyWith({
    StatusPair? success,
    StatusPair? warning,
    StatusPair? danger,
    StatusPair? neutral,
    StatusPair? info,
    Color? live,
    Color? destructive,
    Color? snackBg,
    Color? snackText,
  }) =>
      StatusColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        neutral: neutral ?? this.neutral,
        info: info ?? this.info,
        live: live ?? this.live,
        destructive: destructive ?? this.destructive,
        snackBg: snackBg ?? this.snackBg,
        snackText: snackText ?? this.snackText,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      danger: danger.lerp(other.danger, t),
      neutral: neutral.lerp(other.neutral, t),
      info: info.lerp(other.info, t),
      live: Color.lerp(live, other.live, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      snackBg: Color.lerp(snackBg, other.snackBg, t)!,
      snackText: Color.lerp(snackText, other.snackText, t)!,
    );
  }
}

extension StatusContext on BuildContext {
  StatusColors get status => Theme.of(this).extension<StatusColors>()!;
}
