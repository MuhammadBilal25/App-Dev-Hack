import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';
import '../shell/tab_page.dart';

/// Home tab for every role. The fixture list arrives with `GET /api/v1/fixtures` (see API_NEEDS.md).
class FixturesScreen extends StatelessWidget {
  const FixturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TabPage(
      id: 'fixtures_screen',
      title: 'Fixtures',
      children: [
        EmptyState(
          id: 'fixtures_empty',
          icon: Icons.calendar_month_outlined,
          message: 'No matches yet. Fixtures appear here when the league organiser publishes them.',
        ),
      ],
    );
  }
}
