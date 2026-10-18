import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_bar.dart';
import '../../core/widgets/sync_strip.dart';

class _Tab {
  const _Tab(this.id, this.label, this.icon, this.selectedIcon);

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _tabs = [
  _Tab('tab_home', 'Home', Icons.home_outlined, Icons.home),
  _Tab('tab_fixtures', 'Fixtures', Icons.calendar_today_outlined, Icons.calendar_today),
  _Tab('tab_standings', 'Standings', Icons.bar_chart_rounded, Icons.bar_chart_rounded),
  _Tab('tab_store', 'Store', Icons.shopping_bag_outlined, Icons.shopping_bag),
  _Tab('tab_profile', 'Profile', Icons.person_outline, Icons.person),
];

/// Five labelled tabs, the same for every role (UI.md §6.6). Role tools (organizer, club
/// manager, admin) open from the workspace card on Home and from Profile.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TenantAppBar(),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(child: shell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            Semantics(
              identifier: _tabs[i].id,
              selected: i == shell.currentIndex,
              child: NavigationDestination(
                icon: Icon(_tabs[i].icon),
                selectedIcon: Icon(_tabs[i].selectedIcon),
                label: _tabs[i].label,
                tooltip: '',
              ),
            ),
        ],
      ),
    );
  }
}
