import 'package:flutter/material.dart';

import '../../core/brand/huddle_mark.dart';
import '../../core/theme/tokens.dart';

/// Shown for the moment the saved session is being restored (UI.md §0.3 splash).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? HuddleColors.splashDark : HuddleColors.splashLight,
      body: Semantics(
        identifier: 'splash',
        label: 'huddle. Loading your league',
        excludeSemantics: true,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HuddleMark(size: 96),
              const SizedBox(height: AppSpace.lg),
              const HuddleWordmark(fontSize: 28),
              const SizedBox(height: AppSpace.md),
              Text('Loading your league…', style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
