import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';
import '../shell/tab_page.dart';

class StandingsScreen extends StatelessWidget {
  const StandingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabPage(
      id: 'standings_screen',
      title: 'Standings',
      children: [
        EmptyState(
          id: 'standings_empty',
          icon: Icons.leaderboard_outlined,
          message: 'No table yet. Standings appear here once the first match of the league is played.',
        ),
      ],
    );
  }
}
