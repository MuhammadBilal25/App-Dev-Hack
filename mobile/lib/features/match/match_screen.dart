import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/brand/jersey_icon.dart';
import '../../core/layout/page_body.dart';
import '../../core/settings/settings.dart';
import '../../core/theme/tenant.dart';
import '../../core/sync/submit.dart';
import '../../core/widgets/confirm_sheet.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/live_dot.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../core/widgets/underline_tabs.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/connectivity/connectivity.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/remote_image.dart';

/// Creates the long-lived client for the SSE stream (overridden in tests).
final sseClientFactoryProvider = Provider<http.Client Function()>((ref) => http.Client.new);

/// Match detail: brand hero with the live score, Timeline / Line-ups tabs and the pinned product.
/// Live updates arrive over SSE (`/api/v1/stream?channels=match:<id>`); each event triggers one
/// refetch, so nothing polls.
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  http.Client? _sse;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _sub?.cancel();
    _sse?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    _sub?.cancel();
    _sse?.close();
    final client = ref.read(sseClientFactoryProvider)();
    _sse = client;
    final base = ref.read(settingsProvider).serverUrl;
    final uri = Uri.parse('$base/api/v1/stream?channels=${Uri.encodeQueryComponent('match:${widget.matchId}')}');
    try {
      final req = http.Request('GET', uri)..headers['Accept'] = 'text/event-stream';
      final res = await client.send(req);
      if (!mounted) return;
      _sub = res.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          if (line.startsWith('data:') && mounted) ref.invalidate(matchProvider(widget.matchId));
        },
        onDone: _scheduleReconnect,
        onError: (Object _) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } on Exception {
      _scheduleReconnect();
    }
  }

  /// Reconnects once after a dropped stream (a reconnect, not a poll).
  void _scheduleReconnect() {
    if (!mounted) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 10), () {
      if (mounted) _connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(matchProvider(widget.matchId));
    final detail = value.value?.data;
    return Scaffold(
      body: Column(
        children: [
          _Hero(detail: detail),
          const SyncStrip(onlineLabel: 'Online · score updates live'),
          UnderlineTabs(id: 'match_tab', labels: const ['Timeline', 'Line-ups'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          Expanded(
            child: Semantics(
              identifier: 'match_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(matchProvider(widget.matchId).future),
                children: [
                  AsyncView<Cached<MatchDetail>>(
                    id: 'match',
                    value: value,
                    onRetry: () => ref.invalidate(matchProvider(widget.matchId)),
                    builder: (r) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (r.fromCache) const CachedNotice(),
                        _MatchInfo(fixture: r.data.fixture),
                        const SizedBox(height: AppSpace.md),
                        if (r.data.canScore && r.data.fixture.status == MatchStatus.live) ...[
                          _ScorePanel(detail: r.data),
                          const SizedBox(height: AppSpace.lg),
                        ],
                        if (r.data.canScore && r.data.allowedStatus.isNotEmpty) ...[
                          _MatchControl(detail: r.data),
                          const SizedBox(height: AppSpace.lg),
                        ],
                        AnimatedSwitcher(
                          duration: AppMotion.of(context, AppMotion.medium),
                          child: _tab == 0
                              ? _Timeline(key: const ValueKey('timeline'), detail: r.data)
                              : _LineUps(key: const ValueKey('lineups'), detail: r.data),
                        ),
                        if (r.data.pinned != null) ...[
                          const SizedBox(height: AppSpace.xl),
                          _PinnedProduct(product: r.data.pinned!),
                        ],
                        if (r.data.canManage) ...[
                          const SizedBox(height: AppSpace.md),
                          _PinControl(detail: r.data),
                        ],
                      ],
                    ),
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

/// Brand header in light mode, surface header in dark mode (approved design).
class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final MatchDetail? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = dark ? scheme.onSurface : scheme.onPrimary;
    final f = detail?.fixture;
    return Material(
      color: dark ? scheme.surfaceContainerLowest : scheme.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xs, AppSpace.xs, AppSpace.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSize.maxContentWidth),
              child: Column(
                children: [
                  Row(
                    children: [
                      Semantics(
                        identifier: 'match_back',
                        button: true,
                        label: 'Back',
                        excludeSemantics: true,
                        child: IconButton(
                          tooltip: 'Back',
                          color: on,
                          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                          onPressed: () => context.canPop() ? context.pop() : context.go('/fixtures'),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          f == null ? 'Match' : '${f.leagueName} · ${f.stageLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium!.copyWith(color: dark ? scheme.onSurfaceVariant : on, fontWeight: FontWeight.w600),
                        ),
                      ),
                      // Balances the back button so the competition line stays centred.
                      const SizedBox(width: AppSize.touch),
                    ],
                  ),
                  if (f != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _HeroTeam(team: f.home)),
                        _HeroScore(fixture: f),
                        Expanded(child: _HeroTeam(team: f.away)),
                      ],
                    ),
                  ] else
                    const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroTeam extends StatelessWidget {
  const _HeroTeam({required this.team});

  final TeamScore team;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: dark ? scheme.surface : scheme.surfaceContainerLowest, shape: BoxShape.circle),
            child: Text(
              initialsOf(team.name),
              textScaler: TextScaler.noScaling,
              style: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w800, fontSize: 13, color: scheme.primary),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          team.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(color: dark ? scheme.onSurface : scheme.onPrimary),
        ),
      ],
    );
  }
}

class _HeroScore extends StatelessWidget {
  const _HeroScore({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = Theme.of(context).textTheme.displayMedium!.copyWith(color: dark ? scheme.onSurface : scheme.onPrimary);
    final score = f.hasScore ? '${f.home.display} : ${f.away.display}' : f.status == MatchStatus.upcoming ? DateFormat.Hm().format(f.kickoff) : '– : –';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      child: Column(
        children: [
          Semantics(
            identifier: 'match_score',
            liveRegion: true,
            label: f.hasScore ? '${f.home.name} ${f.home.display}, ${f.away.name} ${f.away.display}' : 'Kick-off $score',
            excludeSemantics: true,
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.medium),
              switchInCurve: AppMotion.mediumCurve,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(a), child: child),
              ),
              child: FittedBox(key: ValueKey(score), fit: BoxFit.scaleDown, child: Text(score, style: style, maxLines: 1)),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          switch (f.status) {
            MatchStatus.live => LiveChip(minute: f.minute, onHero: true),
            MatchStatus.completed => const _HeroChip(label: 'Full time'),
            MatchStatus.postponed => const _HeroChip(label: 'Postponed'),
            MatchStatus.cancelled => const _HeroChip(label: 'Cancelled'),
            MatchStatus.abandoned => const _HeroChip(label: 'Abandoned'),
            MatchStatus.upcoming => _HeroChip(label: DateFormat('EEE d MMM').format(f.kickoff)),
          },
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      decoration: BoxDecoration(
        color: dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: dark ? scheme.onSurface : scheme.primary)),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({super.key, required this.detail});

  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final events = detail.timeline.where((e) => e.type != 'match_init' && e.type != 'compensation').toList().reversed.toList();
    if (events.isEmpty) {
      return const EmptyState(id: 'timeline_empty', icon: Icons.sports_outlined, message: 'Nothing has happened yet. Events appear here live.');
    }
    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) const Divider(),
          _TimelineRow(event: events[i], detail: detail),
        ],
      ],
    );
  }
}

class _TimelineRow extends ConsumerWidget {
  const _TimelineRow({required this.event, required this.detail});

  final TimelineEvent event;
  final MatchDetail detail;

  Future<void> _correct(BuildContext context, WidgetRef ref, String what) async {
    final r = await ConfirmSheet.show(
      context,
      id: 'confirm_correct',
      title: 'Correct this event?',
      message: '$what will be struck through and no longer count. The original stays in the record.',
      confirmLabel: 'Correct',
      variant: AppButtonVariant.destructive,
      reasonLabel: 'Reason',
    );
    if (!r.confirmed || !context.mounted) return;
    final f = detail.fixture;
    await submitAction(
      context,
      ref,
      type: 'score_event',
      baseVersion: f.version,
      label: 'Correct $what',
      payload: {
        'event_id': newClientId('ev'),
        'match_id': f.id,
        'type': 'compensation',
        'payload': {'compensates': event.id, 'reason': r.reason},
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final e = event;
    final minute = e.minute == null ? '' : "${e.minute}'";
    final what = e.teamName == null ? e.label : '${e.label} · ${e.teamName}';
    final strike = e.compensated ? TextDecoration.lineThrough : null;
    return Semantics(
      identifier: 'timeline_${e.id}',
      label: '$minute $what${e.compensated ? ', disallowed' : ''}',
      excludeSemantics: !(detail.canScore && e.correctable),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.rowMin),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  minute,
                  style: text.titleMedium!.copyWith(fontWeight: FontWeight.w800, fontFeatures: AppFonts.tabular, color: e.compensated ? muted : null),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: e.label),
                      if (e.teamName != null) ...[
                        const TextSpan(text: ' · '),
                        TextSpan(text: e.teamName, style: TextStyle(fontWeight: e.compensated ? FontWeight.w400 : FontWeight.w700)),
                      ],
                      if (e.playerName != null) TextSpan(text: ' (${e.playerName})'),
                    ],
                  ),
                  style: text.bodyLarge!.copyWith(decoration: strike, color: e.compensated ? muted : null),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (e.compensated) const StatusChip(kind: StatusKind.neutral, label: 'Disallowed'),
              if (detail.canScore && e.correctable)
                Semantics(
                  identifier: 'timeline_correct_${e.id}',
                  button: true,
                  label: 'Correct $what',
                  excludeSemantics: true,
                  child: TextButton(onPressed: () => _correct(context, ref, what), child: const Text('Correct')),
                ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Kick-off, venue and demo label under the hero.
class _MatchInfo extends StatelessWidget {
  const _MatchInfo({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${DateFormat('EEE d MMM, HH:mm').format(f.kickoff)} · ${f.venue}', style: text.bodyMedium),
        if (f.sportName.isNotEmpty) Text('· ${f.sportName}', style: text.bodyMedium),
        if (f.statusReason != null) StatusChip(kind: StatusKind.warning, label: f.statusReason!, icon: Icons.info_outline),
        if (f.seeded) const DemoNote(text: 'Demo match from the seed data'),
      ],
    );
  }
}

/// Score entry for the league organizer, built from the sport's scoring template: points per
/// event (goals, baskets), innings controls (runs, extras, wickets) or best-of series controls
/// (sets, games, maps). Every tap is confirmed, then queued as a `score_event` so it also works
/// offline (base_version = match version).
class _ScorePanel extends ConsumerStatefulWidget {
  const _ScorePanel({required this.detail});

  final MatchDetail detail;

  @override
  ConsumerState<_ScorePanel> createState() => _ScorePanelState();
}

class _ScorePanelState extends ConsumerState<_ScorePanel> {
  bool _home = true;
  String? _playerId;

  TeamScore get _team => _home ? widget.detail.fixture.home : widget.detail.fixture.away;
  List<SquadPlayer> get _squad => _home ? widget.detail.homeSquad : widget.detail.awaySquad;

  Future<void> _send(String type, Map<String, dynamic> payload, {required String what, required String title, String? note}) async {
    final f = widget.detail.fixture;
    final r = await ConfirmSheet.show(
      context,
      id: 'confirm_score',
      title: title,
      message: '$what${f.minute == null ? '' : " at ${f.minute}'"}.${note == null ? '' : ' $note'} You can correct it later from the timeline.',
      confirmLabel: 'Add',
    );
    if (!r.confirmed || !mounted) return;
    await submitAction(
      context,
      ref,
      type: 'score_event',
      baseVersion: f.version,
      label: what,
      payload: {'event_id': newClientId('ev'), 'match_id': f.id, 'type': type, 'payload': payload},
    );
  }

  void _score(ScoringEventDef e, {TeamScore? team}) {
    final t = team ?? _team;
    final player = team == null ? _squad.where((p) => p.id == _playerId).firstOrNull : null;
    _send(
      'score',
      {'team_id': t.id, 'event_type': e.key, 'minute': ?widget.detail.fixture.minute, 'player_id': ?player?.id},
      what: '${e.label} for ${t.name}${player == null ? '' : ' (${player.name})'}',
      title: 'Add ${e.label.toLowerCase()}?',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final f = d.fixture;
    final text = Theme.of(context).textTheme;
    final model = d.scoring.model;
    return Semantics(
      identifier: 'score_panel',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text('Score entry', style: text.titleMedium)),
              Text(
                switch (model) {
                  'innings' => 'Innings scoring: runs, extras and wickets for the batting side.',
                  'round' => 'Series scoring: record each ${d.scoring.events.first.label.toLowerCase()} as it ends.',
                  _ => 'Tap an event for the selected team.',
                },
                style: text.bodySmall!.copyWith(letterSpacing: 0),
              ),
              const SizedBox(height: AppSpace.md),
              if (model == 'round') _series(d) else ...[
                Semantics(
                  identifier: 'score_team',
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(f.home.name, overflow: TextOverflow.ellipsis)),
                      ButtonSegment(value: false, label: Text(f.away.name, overflow: TextOverflow.ellipsis)),
                    ],
                    selected: {_home},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() {
                      _home = s.first;
                      _playerId = null;
                    }),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                if (model == 'innings') _innings(d) else _events(d),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _events(MatchDetail d) {
    final f = d.fixture;
    final level = f.home.score == f.away.score;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_squad.isNotEmpty) ...[
          Semantics(
            identifier: 'score_player',
            label: 'Credit a player',
            child: DropdownButtonFormField<String?>(
              initialValue: _playerId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Credit a player (optional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('No player')),
                for (final p in _squad) DropdownMenuItem<String?>(value: p.id, child: Text('${p.shirt == null ? '' : '#${p.shirt} '}${p.name}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _playerId = v),
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final e in d.scoring.events)
              AppButton(id: 'score_add_${e.key}', label: '+ ${e.label}${e.value > 1 ? ' (${e.value})' : ''}', expand: false, onPressed: () => _score(e)),
            AppButton(
              id: 'score_discipline',
              label: 'Card / foul',
              icon: Icons.style_outlined,
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () => _send('discipline', {'team_id': _team.id, 'points': -1, 'minute': ?f.minute}, what: 'Card for ${_team.name}', title: 'Record a card?', note: 'It costs one fair-play point.'),
            ),
            if (!d.scoring.drawAllowed && level && d.tiebreakWinnerId == null)
              AppButton(
                id: 'score_tiebreak',
                label: 'Tie-break winner',
                icon: Icons.emoji_events_outlined,
                variant: AppButtonVariant.secondary,
                expand: false,
                onPressed: () => _send('tiebreak_winner', {'team_id': _team.id}, what: 'Tie-break won by ${_team.name}', title: 'Record tie-break winner?', note: 'This sport needs a winner.'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _innings(MatchDetail d) {
    final text = Theme.of(context).textTheme;
    final runs = d.scoring.events.where((e) => e.legalBall == true && e.wicket != true).toList()..sort((a, b) => a.value - b.value);
    final extras = d.scoring.events.where((e) => e.legalBall == false).toList();
    final wickets = d.scoring.events.where((e) => e.wicket == true).toList();
    final p = d.scoring.periods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${_team.name}: ${_team.display}${_team.overs == null ? '' : ' (${_team.overs} of ${p['overs_per_innings']} overs)'}', style: text.titleSmall),
        const SizedBox(height: AppSpace.sm),
        Text('Runs', style: text.labelMedium),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (final e in runs) AppButton(id: 'score_add_${e.key}', label: e.value == 0 ? 'Dot' : '+${e.value}', expand: false, onPressed: () => _score(e)),
        ]),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Text('Extras (ball re-bowled)', style: text.labelMedium),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            for (final e in extras) AppButton(id: 'score_add_${e.key}', label: '${e.label} +${e.value}', variant: AppButtonVariant.secondary, expand: false, onPressed: () => _score(e)),
          ]),
        ],
        if (wickets.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            for (final e in wickets)
              AppButton(id: 'score_add_${e.key}', label: e.label, icon: Icons.sports_cricket, variant: AppButtonVariant.destructive, expand: false, onPressed: () => _score(e)),
          ]),
        ],
      ],
    );
  }

  Widget _series(MatchDetail d) {
    final f = d.fixture;
    final text = Theme.of(context).textTheme;
    final bestOf = d.scoring.bestOf ?? 3;
    final need = (bestOf + 1) ~/ 2;
    final decided = f.home.score >= need || f.away.score >= need;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Best of $bestOf · first to $need · ${f.home.name} ${f.home.score} – ${f.away.score} ${f.away.name}', style: text.titleSmall),
        const SizedBox(height: AppSpace.sm),
        if (decided)
          const StatusChip(kind: StatusKind.success, label: 'Series decided: end the match below', icon: Icons.flag_outlined)
        else
          for (final e in d.scoring.events)
            for (final t in [f.home, f.away])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: AppButton(id: 'score_add_${e.key}_${t.id}', label: '${e.label}: ${t.name}', onPressed: () => _score(e, team: t)),
              ),
      ],
    );
  }
}

/// Start / end the match (queued, works offline) and postpone / cancel / abandon (online).
class _MatchControl extends ConsumerStatefulWidget {
  const _MatchControl({required this.detail});

  final MatchDetail detail;

  @override
  ConsumerState<_MatchControl> createState() => _MatchControlState();
}

class _MatchControlState extends ConsumerState<_MatchControl> {
  bool _busy = false;

  Future<void> _event(String type, String label, String message) async {
    final f = widget.detail.fixture;
    final r = await ConfirmSheet.show(context, id: 'confirm_$type', title: '$label?', message: message, confirmLabel: label);
    if (!r.confirmed || !mounted) return;
    await submitAction(
      context,
      ref,
      type: 'score_event',
      baseVersion: f.version,
      label: '$label: ${f.home.name} v ${f.away.name}',
      payload: {'event_id': newClientId('ev'), 'match_id': f.id, 'type': type, 'payload': <String, dynamic>{}},
    );
  }

  Future<void> _status(String to, String label) async {
    final f = widget.detail.fixture;
    final messenger = ScaffoldMessenger.of(context);
    if (!ref.read(isOnlineProvider)) {
      messenger.showSnackBar(SnackBar(content: Text("You're offline. $label needs a connection; scores can still be entered offline.")));
      return;
    }
    final r = await ConfirmSheet.show(
      context,
      id: 'confirm_status_$to',
      title: '$label this match?',
      message: 'Everyone following ${f.home.name} v ${f.away.name} sees this at once.',
      confirmLabel: label,
      variant: to == 'postponed' ? AppButtonVariant.primary : AppButtonVariant.destructive,
      reasonLabel: 'Reason',
    );
    if (!r.confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post('/api/v1/matches/${Uri.encodeComponent(f.id)}/status', body: {'status': to, 'reason': r.reason});
      ref.invalidate(matchProvider(f.id));
      ref.invalidate(fixturesProvider);
      messenger.showSnackBar(SnackBar(content: Text('Match ${label.toLowerCase()}ed.'.replaceAll('eed.', 'ed.')), duration: AppMotion.snackbar));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.detail.allowedStatus;
    final text = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'match_control',
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text('Match control', style: text.titleMedium)),
              const SizedBox(height: AppSpace.sm),
              if (allowed.contains('in_progress'))
                AppButton(id: 'match_start', label: 'Start match', icon: Icons.play_arrow, onPressed: () => _event('match_start', 'Start match', 'The match goes live and score entry opens.')),
              if (allowed.contains('completed'))
                AppButton(id: 'match_end', label: 'End match (full time)', icon: Icons.flag_outlined, onPressed: () => _event('match_end', 'End match', 'The result becomes final and the standings update.')),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  if (allowed.contains('postponed')) OutlinedButton.icon(onPressed: _busy ? null : () => _status('postponed', 'Postpone'), icon: const Icon(Icons.pause_circle_outline), label: const Text('Postpone')),
                  if (allowed.contains('upcoming')) OutlinedButton.icon(onPressed: _busy ? null : () => _status('upcoming', 'Restore'), icon: const Icon(Icons.restore), label: const Text('Restore')),
                  if (allowed.contains('cancelled')) OutlinedButton.icon(onPressed: _busy ? null : () => _status('cancelled', 'Cancel'), icon: const Icon(Icons.cancel_outlined), label: const Text('Cancel')),
                  if (allowed.contains('abandoned')) OutlinedButton.icon(onPressed: _busy ? null : () => _status('abandoned', 'Abandon'), icon: const Icon(Icons.report_outlined), label: const Text('Abandon')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Organizer pins a product to the match page; connected fans see it at once (SSE).
class _PinControl extends ConsumerWidget {
  const _PinControl({required this.detail});

  final MatchDetail detail;

  Future<void> _pin(BuildContext context, WidgetRef ref, String? productId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).post('/api/v1/matches/${Uri.encodeComponent(detail.fixture.id)}/pin', body: {'product_id': productId});
      ref.invalidate(matchProvider(detail.fixture.id));
      messenger.showSnackBar(SnackBar(content: Text(productId == null ? 'Product unpinned.' : 'Product pinned to this match.'), duration: AppMotion.snackbar));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final chosen = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const _PinPicker(),
              );
              if (chosen != null && context.mounted) await _pin(context, ref, chosen);
            },
            icon: const Icon(Icons.push_pin_outlined),
            label: Text(detail.pinned == null ? 'Pin a product' : 'Change pinned product'),
          ),
        ),
        if (detail.pinned != null) ...[
          const SizedBox(width: AppSpace.sm),
          TextButton(onPressed: () => _pin(context, ref, null), child: const Text('Unpin')),
        ],
      ],
    );
  }
}

class _PinPicker extends ConsumerWidget {
  const _PinPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(catalogueProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
      child: AsyncView<Catalogue>(
        id: 'pin_picker',
        value: value,
        onRetry: () => ref.invalidate(catalogueProvider),
        builder: (c) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pin a product', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in c.products)
                    ListTile(
                      leading: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm), child: SizedBox.square(dimension: 44, child: ProductImageBox(imageUrl: p.imageUrl, category: p.category, iconSize: 24))),
                      title: Text(p.name),
                      subtitle: Text('${p.clubName} · ${formatPrice(p.fromPriceMinor)}'),
                      onTap: () => Navigator.of(context).pop(p.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _LineUps extends ConsumerWidget {
  const _LineUps({super.key, required this.detail});

  final MatchDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = detail.fixture;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final team in [f.home, f.away]) ...[
          SectionLabel(team.name),
          AsyncView<Cached<ClubProfile>>(
            id: 'lineup_${team.id}',
            value: ref.watch(clubProvider(team.id)),
            skeletonRows: 3,
            onRetry: () => ref.invalidate(clubProvider(team.id)),
            builder: (r) => Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < r.data.roster.length; i++) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      minTileHeight: 48,
                      leading: SizedBox(
                        width: 28,
                        child: Text('${r.data.roster[i].shirt ?? ''}', style: Theme.of(context).textTheme.titleMedium!.copyWith(fontFeatures: AppFonts.tabular)),
                      ),
                      title: Text(r.data.roster[i].name),
                      trailing: Text(r.data.roster[i].position.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PinnedProduct extends StatelessWidget {
  const _PinnedProduct({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 56,
                height: 56,
                child: RemoteImage(
                  path: product.imageUrl,
                  fallback: Container(color: scheme.primaryContainer, alignment: Alignment.center, child: JerseyIcon(size: 34, color: scheme.primary)),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FEATURED', style: text.bodySmall),
                Text(product.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(formatPrice(product.fromPriceMinor), style: text.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Semantics(
            identifier: 'pinned_buy',
            button: true,
            enabled: !product.soldOut,
            label: product.soldOut ? 'Sold out' : 'Buy ${product.name}',
            excludeSemantics: true,
            child: FilledButton(
              onPressed: product.soldOut ? null : () => context.push('/product/${Uri.encodeComponent(product.id)}'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.tertiary,
                foregroundColor: scheme.onTertiary,
                minimumSize: const Size(64, AppSize.buttonSecondary),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text(product.soldOut ? 'Sold out' : 'Buy'),
            ),
          ),
        ],
      ),
    );
  }
}
