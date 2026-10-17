import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/brand/club_crest.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/live_dot.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../shell/tab_page.dart';

enum FixtureFilter { all, live, upcoming, results }

extension on FixtureFilter {
  String get label => switch (this) {
        FixtureFilter.all => 'All',
        FixtureFilter.live => 'Live',
        FixtureFilter.upcoming => 'Upcoming',
        FixtureFilter.results => 'Results',
      };

  bool matches(Fixture f) => switch (this) {
        FixtureFilter.all => true,
        FixtureFilter.live => f.status == MatchStatus.live,
        FixtureFilter.upcoming => f.status == MatchStatus.upcoming || f.status == MatchStatus.postponed,
        FixtureFilter.results => f.status == MatchStatus.completed,
      };
}

/// "TODAY · SAT 17 OCT", "TOMORROW · SUN 18 OCT", or just "SAT 24 OCT".
String dateLabel(DateTime d, DateTime now) {
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  final date = DateFormat('EEE d MMM').format(d).toUpperCase();
  return switch (diff) {
    0 => 'TODAY · $date',
    1 => 'TOMORROW · $date',
    -1 => 'YESTERDAY · $date',
    _ => date,
  };
}

class FixturesScreen extends ConsumerStatefulWidget {
  const FixturesScreen({super.key});

  @override
  ConsumerState<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends ConsumerState<FixturesScreen> {
  FixtureFilter _filter = FixtureFilter.all;

  Future<void> _refresh() => ref.refresh(fixturesProvider.future);

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(fixturesProvider);
    return TabPage(
      id: 'fixtures_screen',
      title: 'Fixtures',
      onRefresh: _refresh,
      children: [
        _FilterChips(selected: _filter, onSelected: (f) => setState(() => _filter = f)),
        const SizedBox(height: AppSpace.sm),
        AsyncView<Cached<List<Fixture>>>(
          id: 'fixtures',
          value: value,
          onRetry: () => ref.invalidate(fixturesProvider),
          builder: (r) {
            final list = r.data.where(_filter.matches).toList();
            if (r.data.isEmpty) {
              return const EmptyState(
                id: 'fixtures_empty',
                icon: Icons.calendar_month_outlined,
                message: 'No matches yet. Fixtures appear here when the league organiser publishes them.',
              );
            }
            if (list.isEmpty) {
              return EmptyState(
                id: 'fixtures_filter_empty',
                icon: Icons.filter_alt_off_outlined,
                message: 'No ${_filter.label.toLowerCase()} matches right now.',
                actionLabel: 'Show all',
                onAction: () => setState(() => _filter = FixtureFilter.all),
              );
            }
            // Results newest first; everything else in kickoff order.
            if (_filter == FixtureFilter.results) list.sort((a, b) => b.kickoff.compareTo(a.kickoff));
            final groups = <String, List<Fixture>>{};
            final now = DateTime.now();
            for (final f in list) {
              groups.putIfAbsent(dateLabel(f.kickoff, now), () => []).add(f);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r.fromCache) const CachedNotice(),
                for (final e in groups.entries) ...[
                  SectionLabel(e.key),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < e.value.length; i++) ...[
                          if (i > 0) const Divider(),
                          FixtureRow(fixture: e.value[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final FixtureFilter selected;
  final ValueChanged<FixtureFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final f in FixtureFilter.values)
          Semantics(
            identifier: 'fixtures_filter_${f.name}',
            button: true,
            selected: f == selected,
            label: '${f.label} matches',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onSelected(f),
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: AnimatedContainer(
                duration: AppMotion.of(context, AppMotion.fast),
                curve: AppMotion.fastCurve,
                constraints: const BoxConstraints(minHeight: AppSize.touch, minWidth: AppSize.touch),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: f == selected ? scheme.inverseSurface : scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: f == selected ? scheme.inverseSurface : scheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f == FixtureFilter.live) ...[LiveDot(size: 7, color: f == selected ? scheme.onInverseSurface : null), const SizedBox(width: 6)],
                    Text(
                      f.label,
                      style: text.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: f == selected ? scheme.onInverseSurface : scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One fixture: status column on the left, two team rows with scores on the right.
class FixtureRow extends StatelessWidget {
  const FixtureRow({super.key, required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    final status = switch (f.status) {
      MatchStatus.live => 'live, minute ${f.minute ?? ''}',
      MatchStatus.completed => 'full time',
      MatchStatus.postponed => 'postponed',
      MatchStatus.upcoming => 'kick-off ${DateFormat.Hm().format(f.kickoff)}',
    };
    final score = f.hasScore ? ', ${f.home.display} to ${f.away.display}' : '';
    return Semantics(
      identifier: 'fixture_${f.id}',
      button: true,
      label: '${f.home.name} against ${f.away.name}$score, $status',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push('/match/${Uri.encodeComponent(f.id)}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
            child: Row(
              children: [
                SizedBox(width: 72, child: _StatusColumn(fixture: f)),
                Container(width: 1, height: 44, color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    children: [
                      _TeamLine(team: f.home, fixture: f),
                      const SizedBox(height: AppSpace.sm),
                      _TeamLine(team: f.away, fixture: f),
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

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final live = context.status.live;
    return switch (fixture.status) {
      MatchStatus.live => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(children: [LiveDot(color: live), const SizedBox(width: 5), Text('LIVE', style: text.labelSmall!.copyWith(color: live))]),
            ),
            const SizedBox(height: 2),
            Text("${fixture.minute ?? ''}'", style: text.bodyMedium!.copyWith(color: live, fontWeight: FontWeight.w800, fontFeatures: AppFonts.tabular)),
          ],
        ),
      MatchStatus.completed => Text('FT', style: text.labelLarge!.copyWith(color: muted)),
      MatchStatus.postponed => const Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(kind: StatusKind.warning, label: 'PPD', icon: Icons.event_busy),
        ),
      MatchStatus.upcoming => Text(
          DateFormat.Hm().format(fixture.kickoff),
          style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w700, fontFeatures: AppFonts.tabular),
        ),
    };
  }
}

class _TeamLine extends StatelessWidget {
  const _TeamLine({required this.team, required this.fixture});

  final TeamScore team;
  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final completed = fixture.status == MatchStatus.completed;
    final winner = completed && fixture.winnerId == team.id;
    final loser = completed && fixture.winnerId != null && !winner;
    final color = loser ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface;
    final weight = winner || fixture.status == MatchStatus.live ? FontWeight.w800 : FontWeight.w500;
    return Row(
      children: [
        ClubCrest(name: team.name, size: 24),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyLarge!.copyWith(color: color, fontWeight: weight)),
        ),
        if (fixture.hasScore)
          Text(team.display, style: text.titleMedium!.copyWith(color: color, fontWeight: weight, fontFeatures: AppFonts.tabular)),
      ],
    );
  }
}
