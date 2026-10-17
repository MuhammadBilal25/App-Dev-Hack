import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/widgets/empty_state.dart';
import '../shell/tab_page.dart';

class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final hasClub = user?.clubId != null;
    return TabPage(
      id: 'club_screen',
      title: 'Club',
      children: [
        EmptyState(
          id: 'club_empty',
          icon: Icons.shield_outlined,
          message: hasClub
              ? 'Your club profile, roster and staff appear here once they are loaded from the league server.'
              : 'No clubs to show yet. Clubs in your organisation appear here.',
        ),
      ],
    );
  }
}
