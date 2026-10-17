import 'package:flutter/material.dart';

import '../theme/status_colors.dart';
import '../theme/tokens.dart';

enum AppButtonVariant { cta, primary, secondary, text, destructive }

/// The one button set (UI.md §6.1). While [loading], a spinner replaces the label, the button
/// keeps its width and ignores taps (prevents double checkout). A disabled button should say why
/// in its label.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.id,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String id;
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.status;
    final onTap = loading ? null : onPressed;

    Color spinnerColor() => switch (variant) {
          AppButtonVariant.cta => scheme.onTertiary,
          AppButtonVariant.primary => scheme.onPrimary,
          AppButtonVariant.destructive => status.destructive,
          _ => scheme.primary,
        };

    final child = loading
        ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: spinnerColor()))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: AppSpace.sm)],
              Flexible(child: Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
            ],
          );

    final Widget button = switch (variant) {
      AppButtonVariant.cta => FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.tertiary,
            foregroundColor: scheme.onTertiary,
            // Keep the CTA colour while loading so the button doesn't flash grey.
            disabledBackgroundColor: loading ? scheme.tertiary : null,
          ),
          child: child,
        ),
      AppButtonVariant.primary => FilledButton(
          onPressed: onTap,
          style: loading ? FilledButton.styleFrom(disabledBackgroundColor: scheme.primary) : null,
          child: child,
        ),
      AppButtonVariant.secondary => OutlinedButton(onPressed: onTap, child: child),
      AppButtonVariant.text => TextButton(onPressed: onTap, child: child),
      AppButtonVariant.destructive => OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: status.destructive,
            side: BorderSide(color: status.destructive, width: AppSize.borderInput),
          ),
          child: child,
        ),
    };

    return Semantics(
      identifier: id,
      button: true,
      enabled: onTap != null,
      label: loading ? '$label, working' : null,
      child: expand && variant != AppButtonVariant.text ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
