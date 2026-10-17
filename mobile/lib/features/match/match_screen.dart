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
import '../store/product_sheet.dart';

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
                        if (r.data.canScore && r.data.fixture.status == MatchStatus.live) ...[
                          _ScorePanel(detail: r.data),
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
                          f == null ? 'Match' : '${f.leagueName} · Round ${f.round}',
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
    final score = f.hasScore ? '${f.home.display} : ${f.away.display}' : DateFormat.Hm().format(f.kickoff);
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

/// Score entry for the league organizer: team toggle, then one button per scoring event in the
/// sport config. Each tap is confirmed, then queued as a `score_event` (base_version = match version).
class _ScorePanel extends ConsumerStatefulWidget {
  const _ScorePanel({required this.detail});

  final MatchDetail detail;

  @override
  ConsumerState<_ScorePanel> createState() => _ScorePanelState();
}

class _ScorePanelState extends ConsumerState<_ScorePanel> {
  bool _home = true;

  Future<void> _add(String eventType) async {
    final f = widget.detail.fixture;
    final team = _home ? f.home : f.away;
    final what = '${humanize(eventType)} for ${team.name}';
    final r = await ConfirmSheet.show(
      context,
      id: 'confirm_score',
      title: 'Add ${humanize(eventType).toLowerCase()}?',
      message: '$what${f.minute == null ? '' : " at ${f.minute}'"}. You can correct it later from the timeline.',
      confirmLabel: 'Add',
    );
    if (!r.confirmed || !mounted) return;
    await submitAction(
      context,
      ref,
      type: 'score_event',
      baseVersion: f.version,
      label: what,
      payload: {
        'event_id': newClientId('ev'),
        'match_id': f.id,
        'type': 'score',
        'payload': {'team_id': team.id, 'event_type': eventType, 'minute': ?f.minute},
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.detail.fixture;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Score entry', style: text.titleMedium)),
            const SizedBox(height: AppSpace.md),
            Semantics(
              identifier: 'score_team',
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(f.home.name, overflow: TextOverflow.ellipsis)),
                  ButtonSegment(value: false, label: Text(f.away.name, overflow: TextOverflow.ellipsis)),
                ],
                selected: {_home},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _home = s.first),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final e in widget.detail.scoringEvents)
                  AppButton(id: 'score_add_$e', label: '+ ${humanize(e)}', expand: false, onPressed: () => _add(e)),
              ],
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
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.md)),
              alignment: Alignment.center,
              child: JerseyIcon(size: 34, color: scheme.primary),
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
              onPressed: product.soldOut ? null : () => showProductSheet(context, product),
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
