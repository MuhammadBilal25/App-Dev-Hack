import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_chip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../shell/tab_page.dart';

class StandingsScreen extends ConsumerStatefulWidget {
  const StandingsScreen({super.key});

  @override
  ConsumerState<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends ConsumerState<StandingsScreen> {
  String? _leagueId;

  @override
  Widget build(BuildContext context) {
    final leagues = ref.watch(leaguesProvider);
    return TabPage(
      id: 'standings_screen',
      title: 'Standings',
      onRefresh: () async {
        ref.invalidate(leaguesProvider);
        if (_leagueId != null) ref.invalidate(standingsProvider(_leagueId!));
      },
      children: [
        AsyncView<Cached<List<League>>>(
          id: 'leagues',
          value: leagues,
          onRetry: () => ref.invalidate(leaguesProvider),
          builder: (r) {
            if (r.data.isEmpty) {
              return const EmptyState(
                id: 'standings_empty',
                icon: Icons.leaderboard_outlined,
                message: 'No leagues yet. Standings appear here once your organisation runs a league.',
              );
            }
            final withGames = r.data.where((l) => l.fixtureCount > 0);
            final id = _leagueId ?? (withGames.isNotEmpty ? withGames.first.id : r.data.first.id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r.data.length > 1) ...[
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      for (final l in r.data)
                        Semantics(
                          identifier: 'standings_league_${l.id}',
                          button: true,
                          selected: l.id == id,
                          child: ChoiceChip(
                            label: Text(l.name),
                            selected: l.id == id,
                            showCheckmark: false,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: (_) => setState(() => _leagueId = l.id),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                ],
                _Table(leagueId: id),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Table extends ConsumerWidget {
  const _Table({required this.leagueId});

  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AsyncView<Cached<Standings>>(
      id: 'standings',
      value: ref.watch(standingsProvider(leagueId)),
      onRetry: () => ref.invalidate(standingsProvider(leagueId)),
      builder: (r) {
        final s = r.data;
        if (s.rows.isEmpty) {
          return const EmptyState(id: 'standings_table_empty', icon: Icons.leaderboard_outlined, message: 'No teams in this league yet.');
        }
        final header = text.bodySmall!.copyWith(fontWeight: FontWeight.w800);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (r.fromCache) const CachedNotice(),
            Text(s.leagueName, style: text.titleLarge),
            const SizedBox(height: AppSpace.md),
            if (s.spots > 0)
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_outlined, color: scheme.onPrimaryContainer, size: 20),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Top ${s.spots} qualify for the playoffs',
                        style: text.bodyMedium!.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpace.md),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    color: scheme.surfaceContainerHigh,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                    child: Row(
                      children: [
                        SizedBox(width: 28, child: Text('#', style: header)),
                        Expanded(child: Text('Team', style: header)),
                        _Num('P', style: header),
                        _Num('GD', style: header),
                        _Num('PTS', style: header),
                      ],
                    ),
                  ),
                  for (var i = 0; i < s.rows.length; i++) ...[
                    if (i > 0) i == s.spots ? const _DashedDivider() : const Divider(),
                    _Row(row: s.rows[i], qualifies: s.rows[i].rank <= s.spots),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'Dashed line = qualification cut-off. Ties use head-to-head first.',
              style: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class _Num extends StatelessWidget {
  const _Num(this.value, {this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        child: Text(value, textAlign: TextAlign.right, style: (style ?? Theme.of(context).textTheme.bodyMedium)!.copyWith(fontFeatures: AppFonts.tabular)),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.qualifies});

  final StandingRow row;
  final bool qualifies;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (StatusKind kind, String label, IconData icon) = switch (row.status) {
      QualStatus.clinched => (StatusKind.success, 'Clinched', Icons.check),
      QualStatus.eliminated => (StatusKind.danger, 'Eliminated', Icons.close),
      QualStatus.stillPossible => (StatusKind.neutral, 'Still possible', Icons.radio_button_unchecked),
    };
    final gd = row.diff > 0 ? '+${row.diff}' : '${row.diff}';
    return Semantics(
      identifier: 'standings_row_${row.teamId}',
      label: 'Rank ${row.rank}, ${row.teamName}, played ${row.played}, goal difference $gd, ${row.points} points, $label',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: qualifies ? scheme.primary : Colors.transparent, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(AppSpace.lg - 4, AppSpace.md, AppSpace.lg, AppSpace.md),
        child: Row(
          children: [
            SizedBox(width: 28, child: Text('${row.rank}', style: text.titleMedium!.copyWith(fontFeatures: AppFonts.tabular))),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.teamName,
                    style: qualifies ? text.titleMedium : text.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  StatusChip(kind: kind, label: label, icon: icon),
                ],
              ),
            ),
            _Num('${row.played}'),
            _Num(gd),
            _Num('${row.points}', style: text.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// Dashed line at the qualification cut-off (UI.md §6.8).
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Qualification cut-off',
      child: SizedBox(height: 2, width: double.infinity, child: CustomPaint(painter: _Dash(Theme.of(context).colorScheme.outline))),
    );
  }
}

class _Dash extends CustomPainter {
  const _Dash(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + 5, size.height / 2), p);
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}
