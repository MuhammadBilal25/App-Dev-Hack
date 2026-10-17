import 'package:flutter/material.dart';

import 'status_colors.dart';
import 'tenant.dart';
import 'tokens.dart';
import 'typography.dart';

/// Builds the light or dark theme for a tenant (UI.md §11). The scheme starts from the tenant
/// brand as seed, then every role listed in UI.md §3.1 is overridden with its exact value.
ThemeData buildTheme(Brightness brightness, TenantBrand tenant) {
  final p = AppPalette.of(brightness);
  final dark = brightness == Brightness.dark;
  final brand = tenant.brand(brightness);
  final onBrand = tenant.onBrand(brightness);
  final soft = tenant.soft(brightness);
  final onSoft = tenant.onSoft(brightness);

  final status = dark
      ? StatusColors.dark(info: StatusPair(soft, onSoft), live: p.cta, snackBg: p.snackBg, snackText: p.snackText)
      : StatusColors.light(info: StatusPair(soft, onSoft), live: p.cta, snackBg: p.snackBg, snackText: p.snackText);

  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
    surface: p.bg,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surface2,
    surfaceContainerHighest: p.surface2,
    outline: p.inputBorder,
    outlineVariant: p.divider,
    primary: brand,
    onPrimary: onBrand,
    primaryContainer: soft,
    onPrimaryContainer: onSoft,
    tertiary: p.cta,
    onTertiary: p.onCta,
    error: status.destructive,
    onError: dark ? p.bg : p.surface,
    errorContainer: status.danger.bg,
    onErrorContainer: status.danger.fg,
    inverseSurface: p.snackBg,
    onInverseSurface: p.snackText,
    shadow: dark ? Colors.transparent : const Color(0x1F000000),
  );

  final text = buildTextTheme(text: p.text, muted: p.muted);
  final label = text.labelLarge!;

  RoundedRectangleBorder rounded(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  OutlineInputBorder inputBorder(Color c, double w) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: c, width: w));

  final disabledBg = p.surface2;
  final disabledFg = p.muted;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    fontFamily: AppFonts.body,
    textTheme: text,
    dividerColor: p.divider,
    extensions: [status],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: AppSize.appBar,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      shape: Border(bottom: BorderSide(color: p.divider)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: onBrand,
        disabledBackgroundColor: disabledBg,
        disabledForegroundColor: disabledFg,
        minimumSize: const Size(64, AppSize.buttonPrimary),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
        textStyle: label,
        shape: rounded(AppRadius.lg),
        animationDuration: AppMotion.fast,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, AppSize.buttonSecondary)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.lg)),
        textStyle: WidgetStatePropertyAll(label),
        shape: WidgetStatePropertyAll(rounded(AppRadius.md)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? disabledBg : p.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? disabledFg : p.text),
        side: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.focused)) return BorderSide(color: brand, width: AppSize.borderFocus);
          return BorderSide(color: s.contains(WidgetState.disabled) ? p.divider : p.inputBorder, width: AppSize.borderInput);
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brand,
        minimumSize: const Size(AppSize.touch, AppSize.touch),
        textStyle: label,
        shape: rounded(AppRadius.md),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(AppSize.touch, AppSize.touch), foregroundColor: p.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 14),
      hintStyle: text.bodyLarge!.copyWith(color: p.muted),
      errorStyle: text.bodyMedium!.copyWith(color: status.danger.fg),
      errorMaxLines: 3,
      border: inputBorder(p.inputBorder, AppSize.borderInput),
      enabledBorder: inputBorder(p.inputBorder, AppSize.borderInput),
      focusedBorder: inputBorder(brand, AppSize.borderFocus),
      errorBorder: inputBorder(status.danger.fg, AppSize.borderFocus),
      focusedErrorBorder: inputBorder(status.danger.fg, AppSize.borderFocus),
      disabledBorder: inputBorder(p.divider, AppSize.borderInput),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface2,
      selectedColor: soft,
      labelStyle: text.labelSmall,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      shape: rounded(AppRadius.sm),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: dark ? BorderSide.none : BorderSide(color: p.divider),
      ),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: AppSpace.md,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodyMedium!.copyWith(color: p.muted),
      iconColor: p.muted,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: AppSize.bottomNav,
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: soft,
      indicatorShape: rounded(AppRadius.full),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) {
        final selected = s.contains(WidgetState.selected);
        return text.labelSmall!.copyWith(color: selected ? brand : p.muted, fontWeight: selected ? FontWeight.w800 : FontWeight.w600);
      }),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? brand : p.muted)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.surface,
      elevation: dark ? 0 : 3,
      modalElevation: dark ? 0 : 3,
      showDragHandle: true,
      dragHandleColor: p.inputBorder,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 3,
      shape: rounded(AppRadius.lg),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.snackBg,
      contentTextStyle: text.bodyLarge!.copyWith(color: p.snackText),
      actionTextColor: dark ? tenant.brandLight : tenant.brandDark,
      behavior: SnackBarBehavior.floating,
      shape: rounded(AppRadius.md),
      elevation: dark ? 0 : 3,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(AppSize.touch, AppSize.touch)),
        textStyle: WidgetStatePropertyAll(text.bodyMedium!.copyWith(fontWeight: FontWeight.w700)),
        side: WidgetStatePropertyAll(BorderSide(color: p.inputBorder, width: AppSize.borderInput)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? soft : p.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onSoft : p.text),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: brand),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: ZoomPageTransitionsBuilder()},
    ),
  );
}
