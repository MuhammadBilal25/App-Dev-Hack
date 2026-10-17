import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Empty state (UI.md §6.7): icon + one sentence + an action. Never a blank screen.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.id,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  /// Semantics identifier, e.g. `fixtures_empty`.
  final String id;
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      identifier: id,
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, shape: BoxShape.circle),
                child: Icon(icon, size: 30, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.lg),
              Semantics(
                identifier: '${id}_action',
                button: true,
                child: OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
