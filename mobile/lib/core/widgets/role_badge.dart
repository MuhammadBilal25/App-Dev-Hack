import 'package:flutter/material.dart';

import '../auth/user.dart';
import '../theme/tokens.dart';

/// Role badge shown in the app bar on every screen (UI.md §9).
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: 'role_badge',
      label: 'Signed in as ${role.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
        decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 14, color: scheme.onPrimaryContainer),
            const SizedBox(width: AppSpace.xs),
            Text(role.label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: scheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }
}
