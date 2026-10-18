import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../core/widgets/underline_tabs.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../fixtures/fixtures_screen.dart';

/// Sports directory: every active sport with its icon, description, scoring style and counts.
class SportsScreen extends ConsumerStatefulWidget {
  const SportsScreen({super.key});

  @override
  ConsumerState<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends ConsumerState<SportsScreen> {
  String _q = '';
  bool _activeOnly = false;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(sportsProvider);
    return Scaffold(
      appBar: const TenantAppBar(title: 'Sports'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'sports_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(sportsProvider.future),
                children: [
                  Semantics(
                    identifier: 'sports_search',
                    label: 'Search sports',
                    textField: true,
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                      decoration: const InputDecoration(hintText: 'Search sports', prefixIcon: Icon(Icons.search)),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  FilterChip(
                    label: const Text('With competitions only'),
                    selected: _activeOnly,
                    onSelected: (v) => setState(() => _activeOnly = v),
                  ),
                  const SizedBox(height: AppSpace.md),
                  AsyncView<Cached<List<Sport>>>(
                    id: 'sports',
                    value: value,
                    onRetry: () => ref.invalidate(sportsProvider),
                    builder: (r) {
                      final list = r.data.where((s) => (_q.isEmpty || s.name.toLowerCase().contains(_q)) && (!_activeOnly || s.leagueCount > 0)).toList();
                      if (list.isEmpty) return const EmptyState(id: 'sports_empty', icon: Icons.sports_outlined, message: 'No sports match your search.');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (r.fromCache) const CachedNotice(),
                          LayoutBuilder(builder: (context, c) {
                            final cols = c.maxWidth > 480 ? 2 : 1;
                            final w = (c.maxWidth - AppSpace.md * (cols - 1)) / cols;
                            return Wrap(spacing: AppSpace.md, runSpacing: AppSpace.md, children: [for (final s in list) SizedBox(width: w, child: _SportCard(sport: s))]);
                          }),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({required this.sport});

  final Sport sport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final s = sport;
    return Semantics(
      identifier: 'sport_card_${s.id}',
      button: true,
      label: '${s.name}, ${s.leagueCount} competitions${s.liveCount > 0 ? ', ${s.liveCount} live' : ''}',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/sports/${Uri.encodeComponent(s.id)}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 26, backgroundColor: scheme.primaryContainer, child: Icon(sportIcon(s.icon), size: 28, color: scheme.primary)),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(s.name, style: text.titleMedium)),
                          if (s.liveCount > 0) StatusChip(kind: StatusKind.danger, label: '${s.liveCount} live', icon: Icons.circle),
                          if (!s.active) const StatusChip(kind: StatusKind.neutral, label: 'Off', icon: Icons.visibility_off_outlined),
                        ],
                      ),
                      if (s.description.isNotEmpty) Text(s.description, style: text.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: AppSpace.xs),
                      Text('${s.leagueCount} ${s.leagueCount == 1 ? 'competition' : 'competitions'} · ${s.clubCount} clubs · ${s.modelLabel}',
                          style: text.bodySmall!.copyWith(letterSpacing: 0)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One sport: description, scoring rules generated from its config, competitions, live,
/// upcoming and completed matches, and participating clubs.
class SportDetailScreen extends ConsumerStatefulWidget {
  const SportDetailScreen({super.key, required this.sportId});

  final String sportId;

  @override
  ConsumerState<SportDetailScreen> createState() => _SportDetailScreenState();
}

class _SportDetailScreenState extends ConsumerState<SportDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(sportProvider(widget.sportId));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: TenantAppBar(title: value.value?.data.sport.name ?? 'Sport'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'sport_detail_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(sportProvider(widget.sportId).future),
                children: [
                  AsyncView<Cached<SportDetail>>(
                    id: 'sport',
                    value: value,
                    onRetry: () => ref.invalidate(sportProvider(widget.sportId)),
                    builder: (r) {
                      final d = r.data;
                      final s = d.sport;
                      final matches = [d.live, d.upcoming, d.completed][_tab];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (r.fromCache) const CachedNotice(),
                          Row(
                            children: [
                              CircleAvatar(radius: 32, backgroundColor: scheme.primaryContainer, child: Icon(sportIcon(s.icon), size: 34, color: scheme.primary)),
                              const SizedBox(width: AppSpace.lg),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Semantics(header: true, child: Text(s.name, style: text.headlineSmall)),
                                    Text(s.modelLabel, style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (s.description.isNotEmpty) ...[const SizedBox(height: AppSpace.md), Text(s.description, style: text.bodyLarge)],
                          const SizedBox(height: AppSpace.lg),
                          StatGrid(tiles: [
                            StatTile(label: 'Competitions', value: '${s.leagueCount}', icon: Icons.emoji_events_outlined),
                            StatTile(label: 'Clubs', value: '${s.clubCount}', icon: Icons.shield_outlined),
                            StatTile(label: 'Live now', value: '${s.liveCount}', icon: Icons.sensors),
                          ]),
                          const SectionLabel('Scoring rules'),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpace.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final line in s.rules)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [const Text('•  '), Expanded(child: Text(line, style: text.bodyMedium))],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SectionLabel('Leagues and tournaments'),
                          if (d.leagues.isEmpty)
                            const EmptyState(id: 'sport_leagues_empty', icon: Icons.emoji_events_outlined, message: 'No competitions for this sport yet.')
                          else
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var i = 0; i < d.leagues.length; i++) ...[
                                    if (i > 0) const Divider(),
                                    LeagueTile(league: d.leagues[i]),
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: AppSpace.lg),
                          UnderlineTabs(
                            id: 'sport_matches_tab',
                            labels: ['Live (${d.live.length})', 'Upcoming (${d.upcoming.length})', 'Results (${d.completed.length})'],
                            index: _tab,
                            onChanged: (i) => setState(() => _tab = i),
                          ),
                          const SizedBox(height: AppSpace.md),
                          if (matches.isEmpty)
                            EmptyState(id: 'sport_matches_empty', icon: Icons.event_busy_outlined, message: ['No live matches right now.', 'No upcoming matches.', 'No results yet.'][_tab])
                          else
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var i = 0; i < matches.length; i++) ...[
                                    if (i > 0) const Divider(),
                                    FixtureRow(fixture: matches[i], showLeague: true),
                                  ],
                                ],
                              ),
                            ),
                          if (d.clubs.isNotEmpty) ...[
                            const SectionLabel('Clubs'),
                            HorizontalCards(height: 150, children: [for (final c in d.clubs) ClubTile(club: c)]),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// League / tournament page: overview (season, format, rules, clubs), fixtures, and the table
/// or the bracket for knockout formats.
class LeagueDetailScreen extends ConsumerStatefulWidget {
  const LeagueDetailScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  ConsumerState<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends ConsumerState<LeagueDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(leagueProvider(widget.leagueId));
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: TenantAppBar(title: value.value?.data.league.name ?? 'League'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'league_detail_screen',
              container: true,
              child: PageBody(
                onRefresh: () async {
                  ref.invalidate(standingsProvider(widget.leagueId));
                  ref.invalidate(bracketProvider(widget.leagueId));
                  final _ = await ref.refresh(leagueProvider(widget.leagueId).future);
                },
                children: [
                  AsyncView<Cached<LeagueDetail>>(
                    id: 'league',
                    value: value,
                    onRetry: () => ref.invalidate(leagueProvider(widget.leagueId)),
                    builder: (r) {
                      final d = r.data;
                      final l = d.league;
                      final knockout = d.hasBracket;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (r.fromCache) const CachedNotice(),
                          Semantics(header: true, child: Text(l.name, style: text.headlineSmall)),
                          Text([l.sportName, if (l.season.isNotEmpty) 'Season ${l.season}', formatLabel(l.format)].join(' · '), style: text.bodyMedium!.copyWith(color: muted)),
                          const SizedBox(height: AppSpace.sm),
                          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
                            StatusChip(kind: l.status == 'active' ? StatusKind.success : StatusKind.neutral, label: humanize(l.status), icon: l.status == 'active' ? Icons.play_circle_outline : Icons.archive_outlined),
                            if (l.liveCount > 0) StatusChip(kind: StatusKind.danger, label: '${l.liveCount} live', icon: Icons.circle),
                            if (d.hasSwiss && d.swissTotal != null) StatusChip(kind: StatusKind.info, label: 'Round ${d.swissRound} of ${d.swissTotal}', icon: Icons.timeline),
                          ]),
                          if (d.canManage) ...[
                            const SizedBox(height: AppSpace.md),
                            OutlinedButton.icon(
                              onPressed: () => context.push('/manage/league/${Uri.encodeComponent(l.id)}'),
                              icon: const Icon(Icons.edit_calendar_outlined),
                              label: const Text('Manage fixtures'),
                            ),
                          ],
                          const SizedBox(height: AppSpace.lg),
                          UnderlineTabs(
                            id: 'league_tab',
                            labels: ['Overview', 'Fixtures (${d.fixtures.length})', knockout ? 'Bracket' : 'Table'],
                            index: _tab,
                            onChanged: (i) => setState(() => _tab = i),
                          ),
                          const SizedBox(height: AppSpace.md),
                          switch (_tab) {
                            0 => _LeagueOverview(detail: d),
                            1 => d.fixtures.isEmpty
                                ? const EmptyState(id: 'league_fixtures_empty', icon: Icons.calendar_month_outlined, message: 'No fixtures yet. The organiser publishes them here.')
                                : Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(children: [
                                      for (var i = 0; i < d.fixtures.length; i++) ...[
                                        if (i > 0) const Divider(),
                                        FixtureRow(fixture: d.fixtures[i]),
                                      ],
                                    ]),
                                  ),
                            _ => knockout ? BracketView(leagueId: l.id) : MiniTable(leagueId: l.id),
                          },
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeagueOverview extends StatelessWidget {
  const _LeagueOverview({required this.detail});

  final LeagueDetail detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = detail.league;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (l.description.isNotEmpty) Text(l.description, style: text.bodyLarge),
        if (l.organizers.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text('Organised by ${l.organizers.join(', ')}', style: text.bodyMedium),
        ],
        if (l.rules.isNotEmpty || detail.sportRules.isNotEmpty) ...[
          const SectionLabel('Competition rules'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in [...l.rules, ...detail.sportRules])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(line, style: text.bodyMedium))]),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SectionLabel('Participating clubs'),
        if (detail.clubs.isEmpty)
          const EmptyState(id: 'league_clubs_empty', icon: Icons.shield_outlined, message: 'No clubs have joined yet.')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < detail.clubs.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    minTileHeight: AppSize.rowMin,
                    leading: ClubBadge(name: detail.clubs[i].name, logoUrl: detail.clubs[i].logoUrl, size: 28),
                    title: Text(detail.clubs[i].name),
                    subtitle: detail.clubs[i].venueName == null ? null : Text(detail.clubs[i].venueName!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/club/${Uri.encodeComponent(detail.clubs[i].id)}'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Compact points table with qualification status (shape and colour never alone).
class MiniTable extends ConsumerWidget {
  const MiniTable({super.key, required this.leagueId});

  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return AsyncView<Cached<Standings>>(
      id: 'league_table',
      value: ref.watch(standingsProvider(leagueId)),
      onRetry: () => ref.invalidate(standingsProvider(leagueId)),
      builder: (r) {
        final rows = r.data.rows;
        if (rows.isEmpty) return const EmptyState(id: 'league_table_empty', icon: Icons.table_rows_outlined, message: 'The table appears once clubs join.');
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text('Club', style: text.labelMedium),
                trailing: SizedBox(width: 132, child: Text('P    W    D    L    Pts', style: text.labelMedium, textAlign: TextAlign.right)),
              ),
              for (final row in rows)
                Semantics(
                  label: 'Position ${row.rank}, ${row.teamName}, ${row.points} points, ${switch (row.status) {
                    QualStatus.clinched => 'qualified',
                    QualStatus.eliminated => 'eliminated',
                    QualStatus.stillPossible => 'still in contention',
                  }}',
                  excludeSemantics: true,
                  child: ListTile(
                    minTileHeight: 48,
                    onTap: () => context.push('/club/${Uri.encodeComponent(row.teamId)}'),
                    leading: SizedBox(
                      width: 44,
                      child: Row(children: [
                        Text('${row.rank}', style: text.titleSmall),
                        const SizedBox(width: 4),
                        Icon(
                          switch (row.status) {
                            QualStatus.clinched => Icons.check_circle,
                            QualStatus.eliminated => Icons.remove_circle_outline,
                            QualStatus.stillPossible => Icons.radio_button_unchecked,
                          },
                          size: 16,
                          color: switch (row.status) {
                            QualStatus.clinched => context.status.success.fg,
                            QualStatus.eliminated => context.status.danger.fg,
                            QualStatus.stillPossible => Theme.of(context).colorScheme.onSurfaceVariant,
                          },
                        ),
                      ]),
                    ),
                    title: Text(row.teamName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: SizedBox(
                      width: 132,
                      child: Text('${row.played}    ${row.won}    ${row.drawn}    ${row.lost}    ${row.points}', textAlign: TextAlign.right, style: text.bodyMedium),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Text('✓ qualified · ○ still possible · − eliminated. Top ${r.data.spots} qualify.', style: text.bodySmall!.copyWith(letterSpacing: 0)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Knockout bracket by round; tapping a played or scheduled match opens it.
class BracketView extends ConsumerWidget {
  const BracketView({super.key, required this.leagueId});

  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AsyncView<List<BracketSection>>(
      id: 'bracket',
      value: ref.watch(bracketProvider(leagueId)),
      onRetry: () => ref.invalidate(bracketProvider(leagueId)),
      builder: (sections) {
        if (sections.isEmpty) return const EmptyState(id: 'bracket_empty', icon: Icons.account_tree_outlined, message: 'The bracket appears when fixtures are made.');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in sections) ...[
              SectionLabel(s.title),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < s.matches.length; i++) ...[
                      if (i > 0) const Divider(),
                      Builder(builder: (context) {
                        final m = s.matches[i];
                        final home = m.home ?? (m.bye ? 'Bye' : 'To be decided');
                        final away = m.away ?? (m.bye ? 'Bye' : 'To be decided');
                        final score = m.homeScore == null ? '' : '${m.homeScore} – ${m.awayScore}';
                        return Semantics(
                          identifier: 'bracket_${m.bracketId}',
                          button: m.matchId != null,
                          label: '${m.stage}: $home against $away${score.isEmpty ? '' : ', $score'}',
                          excludeSemantics: true,
                          child: ListTile(
                            minTileHeight: 56,
                            onTap: m.matchId == null ? null : () => context.push('/match/${Uri.encodeComponent(m.matchId!)}'),
                            title: Text('$home\n$away', style: text.bodyLarge),
                            subtitle: Text(m.bye ? 'Bye: advances automatically' : m.status == null ? 'Waiting for earlier results' : humanize(m.status == 'in_progress' ? 'live' : m.status!), style: text.bodySmall!.copyWith(color: muted, letterSpacing: 0)),
                            trailing: Text(score, style: text.titleMedium),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
