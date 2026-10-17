import 'package:flutter/material.dart';

import '../theme/status_colors.dart';
import '../theme/tokens.dart';

/// Status chip (UI.md §6.3): always an icon or symbol + a word, never colour alone.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.kind, required this.label, this.icon});

  final StatusKind kind;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.status.of(kind);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: c.fg), const SizedBox(width: AppSpace.xs)],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
