import 'package:flutter/material.dart';

import '../theme/status_colors.dart';
import '../theme/tokens.dart';

/// Inline danger banner (UI.md §6.7): plain language, what to do, and Retry.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry, this.id = 'error_banner'});

  final String message;
  final VoidCallback? onRetry;
  final String id;

  @override
  Widget build(BuildContext context) {
    final c = context.status.danger;
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: id,
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.md),
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.warning_amber_rounded, size: 20, color: c.fg, semanticLabel: 'Error'),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(message, style: text.bodyMedium!.copyWith(color: c.fg))),
            if (onRetry != null)
              Semantics(
                identifier: '${id}_retry',
                button: true,
                child: TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: c.fg),
                  child: const Text('Retry'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
