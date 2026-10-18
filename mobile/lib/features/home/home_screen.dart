import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/user.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../fixtures/fixtures_screen.dart';
import '../shell/tab_page.dart';

/// Public home for every role: search, sports, live matches, upcoming fixtures, leagues,
/// clubs, latest results and merchandise. Staff roles get their workspace card at the top.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(homeProvider);
    final user = ref.watch(currentUserProvider);
    final text = Theme.of(context).textTheme;
    return TabPage(
      id: 'home_screen',
      title: user == null ? 'Home' : 'Hi, ${user.name.split(' ').first}',
      subtitle: 'Scores, fixtures, clubs and the club store.',
      onRefresh: () => ref.refresh(homeProvider.future),
      children: [
        Semantics(
          identifier: 'home_search',
          button: true,
          label: 'Search sports, leagues, clubs, players and products',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => context.push('/search'),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InputDecorator(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
              child: Text('Search clubs, players, shirts…', style: text.bodyLarge!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
        ),
        if (user != null) _Workspace(user: user),
        AsyncView<Cached<HomeFeed>>(
          id: 'home',
          value: value,
          onRetry: () => ref.invalidate(homeProvider),
          builder: (r) {
            final h = r.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r.fromCache) ...[const SizedBox(height: AppSpace.md), const CachedNotice()],
                SectionHeader('Sports', onAction: () => context.push('/sports'), id: 'home_sports_all'),
                HorizontalCards(children: [for (final sp in h.sports) _SportChip(sport: sp)]),
                SectionHeader('Live now', onAction: h.live.isEmpty ? null : () => context.go('/fixtures'), id: 'home_live_all'),
                if (h.live.isEmpty)
                  const _Quiet(message: 'No matches are live right now. Check upcoming fixtures below.')
                else
                  _Fixtures(fixtures: h.live),
                SectionHeader('Upcoming fixtures', onAction: () => context.go('/fixtures'), id: 'home_upcoming_all'),
                if (h.upcoming.isEmpty) const _Quiet(message: 'No fixtures scheduled yet.') else _Fixtures(fixtures: h.upcoming.take(4).toList()),
                SectionHeader('Leagues & tournaments', onAction: () => context.go('/standings'), actionLabel: 'Standings', id: 'home_leagues_all'),
                if (h.leagues.isEmpty)
                  const _Quiet(message: 'No leagues yet.')
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < h.leagues.length; i++) ...[
                          if (i > 0) const Divider(),
                          LeagueTile(league: h.leagues[i]),
                        ],
                      ],
                    ),
                  ),
                SectionHeader('Clubs', onAction: () => context.push('/clubs'), id: 'home_clubs_all'),
                HorizontalCards(height: 150, children: [for (final c in h.clubs) ClubTile(club: c)]),
                if (h.results.isNotEmpty) ...[
                  SectionHeader('Latest results', onAction: () => context.go('/fixtures'), id: 'home_results_all'),
                  _Fixtures(fixtures: h.results.take(4).toList()),
                ],
                SectionHeader('Featured merchandise', onAction: () => context.go('/store'), actionLabel: 'Shop', id: 'home_shop'),
                if (h.featured.isEmpty)
                  const _Quiet(message: 'The store is empty for now.')
                else
                  HorizontalCards(height: 290, children: [for (final p in h.featured) ProductTile(product: p, width: 170)]),
                if (h.fresh.isNotEmpty) ...[
                  SectionHeader('Just added', onAction: () => context.go('/store'), id: 'home_new'),
                  HorizontalCards(height: 290, children: [for (final p in h.fresh) ProductTile(product: p, width: 170)]),
                ],
                const SizedBox(height: AppSpace.lg),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The signed-in role's own tools, one tap from home.
class _Workspace extends StatelessWidget {
  const _Workspace({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, IconData, String)>[
      if (user.role == UserRole.superAdmin) ('home_admin', 'Platform admin', Icons.admin_panel_settings_outlined, '/admin'),
      if (user.role == UserRole.superAdmin || user.role == UserRole.leagueOrganizer)
        ('home_organizer', user.role == UserRole.superAdmin ? 'All leagues: fixtures and scoring' : 'My leagues: fixtures and scoring', Icons.sports_score_outlined, '/manage/organizer'),
      if (user.role == UserRole.clubManager) ('home_manager', 'My club: roster, store and orders', Icons.shield_outlined, '/manage/club'),
      if ((user.role == UserRole.player) && user.playerId != null) ('home_player', 'My player profile and stats', Icons.person_outline, '/player/${user.playerId}'),
      if ((user.role == UserRole.player) && user.clubId != null) ('home_my_club', 'My club', Icons.shield_outlined, '/club/${user.clubId}'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Card(
        color: scheme.primaryContainer,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (id, label, icon, route) in items)
              Semantics(
                identifier: id,
                button: true,
                child: ListTile(
                  minTileHeight: AppSize.rowMin,
                  leading: Icon(icon, color: scheme.onPrimaryContainer),
                  title: Text(label, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
                  trailing: Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
                  onTap: () => context.push(route),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SportChip extends StatelessWidget {
  const _SportChip({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'sport_${sport.id}',
      button: true,
      label: '${sport.name}${sport.liveCount > 0 ? ', ${sport.liveCount} live' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push('/sports/${Uri.encodeComponent(sport.id)}'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: 92,
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outlineVariant)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: sport.liveCount > 0,
                label: Text('${sport.liveCount}'),
                child: Icon(sportIcon(sport.icon), size: 32, color: scheme.primary),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(sport.name, style: text.labelMedium, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fixtures extends StatelessWidget {
  const _Fixtures({required this.fixtures});

  final List<Fixture> fixtures;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < fixtures.length; i++) ...[
            if (i > 0) const Divider(),
            FixtureRow(fixture: fixtures[i], showLeague: true),
          ],
        ],
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => EmptyState(id: 'home_quiet', icon: Icons.event_available_outlined, message: message);
}
