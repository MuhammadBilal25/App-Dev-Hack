import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connectivity.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../fixtures/fixtures_screen.dart';

/// Plain-language list of the schedule conflicts the server found.
String describeConflicts(Map<String, dynamic> details) {
  final list = details['conflicts'] is List ? (details['conflicts'] as List).whereType<Map>() : const <Map>[];
  return list.map((c) {
    final window = c['window'] is Map ? c['window'] as Map : const {};
    return '• ${switch (c['type']) {
      'venue_double_booking' => 'The venue is already booked for another match at that time.',
      'team_overlap' => 'One of the teams is already playing at that time.',
      'min_rest_violation' => 'A team would get less than ${c['min_rest_hours']} hours of rest between matches.',
      'venue_unavailable' => 'The venue is closed then (open ${window['open'] ?? ''}–${window['close'] ?? ''} UTC).',
      'player_overlap' => 'A player is registered with both teams.',
      _ => 'It clashes with another fixture.',
    }}';
  }).toSet().join('\n');
}

List<Fixture> _fixtures(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().map(Fixture.fromJson).toList() : const [];

/// League Organizer workspace: the leagues they run (switch between them), matches live now to
/// score, upcoming and postponed fixtures.
class OrganizerDashboardScreen extends ConsumerWidget {
  const OrganizerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(organizerDashboardProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const TenantAppBar(title: 'My leagues'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'organizer_dashboard',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(organizerDashboardProvider.future),
                children: [
                  AsyncView<Cached<Map<String, dynamic>>>(
                    id: 'organizer',
                    value: value,
                    onRetry: () => ref.invalidate(organizerDashboardProvider),
                    builder: (r) {
                      final d = r.data;
                      final leagues = (d['leagues'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
                      final live = _fixtures(d['live']);
                      final upcoming = _fixtures(d['upcoming']);
                      final postponed = _fixtures(d['postponed']);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (r.fromCache) const CachedNotice(),
                          Text('Choose a league to manage its fixtures, or open a live match to enter scores.', style: text.bodyMedium),
                          const SectionLabel('Leagues you run'),
                          if (leagues.isEmpty)
                            const EmptyState(id: 'organizer_no_leagues', icon: Icons.emoji_events_outlined, message: 'No leagues are assigned to you yet. Ask the platform admin to assign one.')
                          else
                            for (final l in leagues) ...[
                              _LeagueCard(json: l),
                              const SizedBox(height: AppSpace.sm),
                            ],
                          SectionHeader('Live now: enter scores (${live.length})'),
                          if (live.isEmpty)
                            const EmptyState(id: 'organizer_no_live', icon: Icons.sensors_off_outlined, message: 'No matches are live in your leagues.')
                          else
                            _FixtureList(fixtures: live),
                          if (postponed.isNotEmpty) ...[
                            SectionHeader('Postponed (${postponed.length})'),
                            _FixtureList(fixtures: postponed),
                          ],
                          SectionHeader('Upcoming'),
                          if (upcoming.isEmpty) const EmptyState(id: 'organizer_no_upcoming', icon: Icons.event_busy, message: 'Nothing scheduled.') else _FixtureList(fixtures: upcoming),
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

class _LeagueCard extends StatelessWidget {
  const _LeagueCard({required this.json});

  final Map<String, dynamic> json;

  @override
  Widget build(BuildContext context) {
    final l = League.fromJson(json);
    final counts = (json['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'organizer_league_${l.id}',
      container: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/manage/league/${Uri.encodeComponent(l.id)}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(sportIcon(l.sportId), color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: Text(l.name, style: text.titleMedium)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                Text('${l.sportName} · ${formatLabel(l.format)} · ${l.teamCount} clubs', style: text.bodyMedium),
                const SizedBox(height: AppSpace.sm),
                Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
                  StatusChip(kind: StatusKind.danger, label: '${counts['in_progress'] ?? 0} live', icon: Icons.circle),
                  StatusChip(kind: StatusKind.info, label: '${counts['upcoming'] ?? 0} upcoming', icon: Icons.schedule),
                  StatusChip(kind: StatusKind.success, label: '${counts['completed'] ?? 0} played', icon: Icons.check),
                  if ((counts['postponed'] ?? 0) > 0) StatusChip(kind: StatusKind.warning, label: '${counts['postponed']} postponed', icon: Icons.pause_circle_outline),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FixtureList extends StatelessWidget {
  const _FixtureList({required this.fixtures});

  final List<Fixture> fixtures;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < fixtures.length; i++) ...[
            if (i > 0) const Divider(),
            FixtureRow(fixture: fixtures[i], showLeague: true),
          ],
        ]),
      );
}

/// Fixture management for one league: generate the schedule (round robin, Swiss, single or
/// double elimination), pair the next Swiss round, and per fixture: reschedule (with conflict
/// detection), postpone, cancel, restore, or open it to score.
class LeagueManageScreen extends ConsumerStatefulWidget {
  const LeagueManageScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  ConsumerState<LeagueManageScreen> createState() => _LeagueManageScreenState();
}

class _LeagueManageScreenState extends ConsumerState<LeagueManageScreen> {
  bool _busy = false;
  String? _error;

  void _refresh() {
    ref.invalidate(leagueProvider(widget.leagueId));
    ref.invalidate(organizerDashboardProvider);
    ref.invalidate(fixturesProvider);
    ref.invalidate(bracketProvider(widget.leagueId));
    ref.invalidate(standingsProvider(widget.leagueId));
  }

  Future<void> _run(Future<void> Function() task, String done) async {
    if (!ref.read(isOnlineProvider)) {
      setState(() => _error = "You're offline. Fixture changes need a connection; score entry still works offline.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await task();
      _refresh();
      messenger.showSnackBar(SnackBar(content: Text(done), duration: AppMotion.snackbar));
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'SCHEDULE_CONFLICT' ? '${e.message}\n${describeConflicts(e.details)}' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate(LeagueDetail d) async {
    final opts = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GenerateSheet(format: d.league.format, teams: d.clubs.length),
    );
    if (opts == null) return;
    await _run(() => ref.read(apiClientProvider).post('/api/v1/leagues/${Uri.encodeComponent(d.league.id)}/fixtures/generate', body: opts), 'Fixtures created.');
  }

  Future<void> _status(Fixture f, String to, String verb) async {
    final needsReason = to == 'postponed' || to == 'cancelled' || to == 'abandoned';
    final r = await ConfirmSheet.show(
      context,
      id: 'confirm_status_$to',
      title: '$verb this match?',
      message: '${f.home.name} v ${f.away.name}. Everyone following it sees the change live.',
      confirmLabel: verb,
      variant: to == 'cancelled' || to == 'abandoned' ? AppButtonVariant.destructive : AppButtonVariant.primary,
      reasonLabel: needsReason ? 'Reason' : null,
    );
    if (!r.confirmed) return;
    await _run(
      () => ref.read(apiClientProvider).post('/api/v1/matches/${Uri.encodeComponent(f.id)}/status', body: {'status': to, if (r.reason.isNotEmpty) 'reason': r.reason}),
      'Match ${statusLabel(switch (to) {
        'postponed' => MatchStatus.postponed,
        'cancelled' => MatchStatus.cancelled,
        'abandoned' => MatchStatus.abandoned,
        'in_progress' => MatchStatus.live,
        _ => MatchStatus.upcoming,
      }).toLowerCase()}.',
    );
  }

  Future<void> _reschedule(Fixture f) async {
    final res = await showModalBottomSheet<({DateTime at, String venue})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RescheduleSheet(fixture: f),
    );
    if (res == null) return;
    final iso = '${res.at.toUtc().toIso8601String().split('.').first}Z';
    await _run(
      () => ref.read(apiClientProvider).post('/api/v1/matches/${Uri.encodeComponent(f.id)}/reschedule', body: {'kickoff_at': iso, if (res.venue.isNotEmpty) 'venue': res.venue}),
      'Match moved to ${DateFormat('EEE d MMM, HH:mm').format(res.at)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(leagueProvider(widget.leagueId));
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: TenantAppBar(title: value.value?.data.league.name ?? 'Manage league'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'league_manage_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(leagueProvider(widget.leagueId).future),
                children: [
                  AsyncView<Cached<LeagueDetail>>(
                    id: 'league_manage',
                    value: value,
                    onRetry: () => ref.invalidate(leagueProvider(widget.leagueId)),
                    builder: (r) {
                      final d = r.data;
                      if (!d.canManage) {
                        return const EmptyState(id: 'league_manage_forbidden', icon: Icons.lock_outline, message: "You don't run this league, so you can view it but not change fixtures.");
                      }
                      final fixtures = [...d.fixtures]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${d.league.sportName} · ${formatLabel(d.league.format)} · ${d.clubs.length} clubs', style: text.bodyMedium),
                          const SizedBox(height: AppSpace.md),
                          if (_error != null) ...[ErrorBanner(id: 'league_manage_error', message: _error!), const SizedBox(height: AppSpace.md)],
                          if (fixtures.isEmpty)
                            AppButton(id: 'league_generate', label: 'Generate fixtures', icon: Icons.auto_awesome_outlined, loading: _busy, onPressed: () => _generate(d))
                          else ...[
                            if (d.hasSwiss)
                              AppButton(
                                id: 'league_swiss_next',
                                label: 'Pair next Swiss round',
                                icon: Icons.timeline,
                                loading: _busy,
                                onPressed: () => _run(() => ref.read(apiClientProvider).post('/api/v1/leagues/${Uri.encodeComponent(d.league.id)}/swiss/next-round'), 'Next round paired.'),
                              ),
                            if (d.hasBracket)
                              Padding(
                                padding: const EdgeInsets.only(top: AppSpace.sm),
                                child: Text('Knockout matches are created automatically as soon as both teams are known.', style: text.bodyMedium),
                              ),
                          ],
                          const SectionLabel('Fixtures'),
                          if (fixtures.isEmpty)
                            const EmptyState(id: 'league_manage_empty', icon: Icons.calendar_month_outlined, message: 'No fixtures yet. Generate them from the clubs in this league.')
                          else
                            for (final f in fixtures) ...[
                              Card(
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    FixtureRow(fixture: f, showLeague: false),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
                                      child: Row(
                                        children: [
                                          Expanded(child: Text('${f.stageLabel} · ${f.venue}${f.statusReason == null ? '' : ' · ${f.statusReason}'}', style: text.bodySmall!.copyWith(letterSpacing: 0))),
                                          _FixtureMenu(
                                            fixture: f,
                                            onAction: (a) => switch (a) {
                                              'reschedule' => _reschedule(f),
                                              'postpone' => _status(f, 'postponed', 'Postpone'),
                                              'cancel' => _status(f, 'cancelled', 'Cancel'),
                                              'restore' => _status(f, 'upcoming', 'Restore'),
                                              'start' => _status(f, 'in_progress', 'Start'),
                                              'abandon' => _status(f, 'abandoned', 'Abandon'),
                                              _ => context.push('/match/${Uri.encodeComponent(f.id)}'),
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpace.sm),
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

class _FixtureMenu extends StatelessWidget {
  const _FixtureMenu({required this.fixture, required this.onAction});

  final Fixture fixture;
  final void Function(String) onAction;

  @override
  Widget build(BuildContext context) {
    final s = fixture.status;
    final items = <(String, String, IconData)>[
      ('open', s == MatchStatus.live ? 'Open to score' : 'Open match', Icons.open_in_new),
      if (s == MatchStatus.upcoming || s == MatchStatus.postponed) ('reschedule', 'Reschedule', Icons.edit_calendar_outlined),
      if (s == MatchStatus.upcoming) ('start', 'Start match', Icons.play_arrow),
      if (s == MatchStatus.upcoming) ('postpone', 'Postpone', Icons.pause_circle_outline),
      if (s == MatchStatus.postponed) ('restore', 'Restore to schedule', Icons.restore),
      if (s == MatchStatus.upcoming || s == MatchStatus.postponed) ('cancel', 'Cancel', Icons.cancel_outlined),
      if (s == MatchStatus.live) ('abandon', 'Abandon', Icons.report_outlined),
    ];
    return Semantics(
      identifier: 'fixture_actions_${fixture.id}',
      button: true,
      label: 'Actions for ${fixture.home.name} v ${fixture.away.name}',
      child: PopupMenuButton<String>(
        tooltip: 'Match actions',
        onSelected: onAction,
        itemBuilder: (_) => [for (final (v, l, i) in items) PopupMenuItem(value: v, child: ListTile(leading: Icon(i), title: Text(l), contentPadding: EdgeInsets.zero))],
        child: const Padding(padding: EdgeInsets.all(AppSpace.sm), child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Actions'), Icon(Icons.arrow_drop_down)])),
      ),
    );
  }
}

class _GenerateSheet extends StatefulWidget {
  const _GenerateSheet({required this.format, required this.teams});

  final String format;
  final int teams;

  @override
  State<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends State<_GenerateSheet> {
  DateTime _start = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
  int _interval = 7;
  int _legs = 1;
  late int _rounds = widget.teams < 2 ? 1 : (widget.teams - 1).clamp(1, 3);
  bool _third = false;
  bool _reset = true;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String two(int n) => n.toString().padLeft(2, '0');
    return Semantics(
      identifier: 'generate_sheet',
      container: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Generate fixtures', style: text.titleLarge)),
            Text('${formatLabel(widget.format)} for ${widget.teams} clubs. Kick-off times are in UTC.', style: text.bodyMedium),
            const SizedBox(height: AppSpace.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('First match day'),
              subtitle: Text(DateFormat('EEE d MMM y').format(_start)),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _start = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Kick-off time (UTC)'),
              subtitle: Text('${two(_time.hour)}:${two(_time.minute)}'),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
            ),
            Row(children: [
              const Expanded(child: Text('Days between rounds')),
              DropdownButton<int>(value: _interval, items: [for (final n in [1, 2, 3, 7, 14]) DropdownMenuItem(value: n, child: Text('$n'))], onChanged: (v) => setState(() => _interval = v ?? 7)),
            ]),
            if (widget.format == 'round_robin')
              SegmentedButton<int>(
                segments: const [ButtonSegment(value: 1, label: Text('Single round')), ButtonSegment(value: 2, label: Text('Home and away'))],
                selected: {_legs},
                onSelectionChanged: (s) => setState(() => _legs = s.first),
              ),
            if (widget.format == 'swiss')
              Row(children: [
                const Expanded(child: Text('Number of rounds')),
                DropdownButton<int>(
                  value: _rounds,
                  items: [for (var n = 1; n < (widget.teams < 2 ? 2 : widget.teams); n++) DropdownMenuItem(value: n, child: Text('$n'))],
                  onChanged: (v) => setState(() => _rounds = v ?? _rounds),
                ),
              ]),
            if (widget.format == 'single_elim') SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Third-place match'), value: _third, onChanged: (v) => setState(() => _third = v)),
            if (widget.format == 'double_elim') SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Bracket reset in the grand final'), value: _reset, onChanged: (v) => setState(() => _reset = v)),
            const SizedBox(height: AppSpace.xl),
            AppButton(
              id: 'generate_confirm',
              label: 'Create fixtures',
              onPressed: widget.teams < 2
                  ? null
                  : () => Navigator.of(context).pop(<String, dynamic>{
                        'start_date': DateFormat('yyyy-MM-dd').format(_start),
                        'kickoff_time': '${two(_time.hour)}:${two(_time.minute)}',
                        'interval_days': _interval,
                        if (widget.format == 'round_robin') 'legs': _legs,
                        if (widget.format == 'swiss') 'total_rounds': _rounds,
                        if (widget.format == 'single_elim') 'third_place_match': _third,
                        if (widget.format == 'double_elim') 'bracket_reset': _reset,
                      }),
            ),
            if (widget.teams < 2) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text('Add at least two clubs first.', style: text.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({required this.fixture});

  final Fixture fixture;

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late DateTime _at = widget.fixture.kickoff;
  late final _venue = TextEditingController(text: widget.fixture.venue);

  @override
  void dispose() {
    _venue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Reschedule', style: text.titleLarge)),
            Text('${widget.fixture.home.name} v ${widget.fixture.away.name}', style: text.bodyMedium),
            const SizedBox(height: AppSpace.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Date'),
              subtitle: Text(DateFormat('EEE d MMM y').format(_at)),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Kick-off (your time)'),
              subtitle: Text(DateFormat.Hm().format(_at)),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
                if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
              },
            ),
            TextField(controller: _venue, decoration: const InputDecoration(labelText: 'Venue')),
            const SizedBox(height: AppSpace.sm),
            Text('The server checks venue double-booking, team overlaps, rest days and venue hours before saving.', style: text.bodySmall!.copyWith(letterSpacing: 0)),
            const SizedBox(height: AppSpace.xl),
            AppButton(id: 'reschedule_confirm', label: 'Save new time', onPressed: () => Navigator.of(context).pop((at: _at, venue: _venue.text.trim()))),
          ],
        ),
      ),
    );
  }
}
