import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/brand/club_crest.dart';
import '../../core/layout/page_body.dart';
import '../../core/settings/settings.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/live_dot.dart';
import '../../core/widgets/role_badge.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
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
          const SyncStrip(),
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
                        _Tabs(index: _tab, onChanged: (i) => setState(() => _tab = i)),
                        const SizedBox(height: AppSpace.md),
                        AnimatedSwitcher(
                          duration: AppMotion.of(context, AppMotion.medium),
                          child: _tab == 0
                              ? _Timeline(key: const ValueKey('timeline'), detail: r.data)
                              : _LineUps(key: const ValueKey('lineups'), detail: r.data),
                        ),
                        if (r.data.pinned != null) ...[
                          const SectionLabel('Match-day shop'),
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

class _Hero extends ConsumerWidget {
  const _Hero({required this.detail});

  final MatchDetail? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final on = scheme.onPrimary;
    final user = ref.watch(currentUserProvider);
    final f = detail?.fixture;
    return Material(
      color: scheme.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xs, AppSpace.lg, AppSpace.xl),
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
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => context.canPop() ? context.pop() : context.go('/fixtures'),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          f == null ? 'Match' : '${f.leagueName} · Round ${f.round}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium!.copyWith(color: on, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (user != null) RoleBadge(role: user.role),
                    ],
                  ),
                  if (f != null) ...[
                    const SizedBox(height: AppSpace.md),
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
    final on = Theme.of(context).colorScheme.onPrimary;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.xs),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: ClubCrest(name: team.name, size: 44),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          team.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium!.copyWith(color: on),
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
    final on = Theme.of(context).colorScheme.onPrimary;
    final style = Theme.of(context).textTheme.displayMedium!.copyWith(color: on);
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
          const SizedBox(height: AppSpace.sm),
          switch (f.status) {
            MatchStatus.live => LiveChip(minute: f.minute, onDark: true),
            MatchStatus.completed => _OnBrandChip(label: 'Full time'),
            MatchStatus.postponed => _OnBrandChip(label: 'Postponed'),
            MatchStatus.upcoming => _OnBrandChip(label: DateFormat('EEE d MMM').format(f.kickoff)),
          },
        ],
      ),
    );
  }
}

class _OnBrandChip extends StatelessWidget {
  const _OnBrandChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      decoration: BoxDecoration(color: scheme.onPrimary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: scheme.onPrimary)),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'match_tabs',
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Timeline'), icon: Icon(Icons.timeline)),
            ButtonSegment(value: 1, label: Text('Line-ups'), icon: Icon(Icons.groups_outlined)),
          ],
          selected: {index},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0) const Divider(),
            _TimelineRow(event: events[i]),
          ],
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final e = event;
    final minute = e.minute == null ? '' : "${e.minute}'";
    final what = e.teamName == null ? e.label : '${e.label} · ${e.teamName}';
    final strike = e.compensated ? TextDecoration.lineThrough : null;
    return Semantics(
      identifier: 'timeline_${e.id}',
      label: '$minute $what${e.compensated ? ', disallowed' : ''}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.rowMin),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(minute, style: text.titleMedium!.copyWith(fontFeatures: AppFonts.tabular, decoration: strike, color: e.compensated ? muted : null)),
              ),
              Icon(_icon(e.type), size: 20, color: e.compensated ? muted : Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  what,
                  style: text.bodyLarge!.copyWith(decoration: strike, color: e.compensated ? muted : null),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (e.compensated) const StatusChip(kind: StatusKind.neutral, label: 'Disallowed', icon: Icons.block),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icon(String type) => switch (type) {
        'score' => Icons.sports_soccer,
        'discipline' => Icons.style_outlined,
        'match_start' => Icons.play_arrow_rounded,
        'match_end' => Icons.flag_outlined,
        'tiebreak_winner' => Icons.emoji_events_outlined,
        _ => Icons.circle_outlined,
      };
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(Icons.checkroom, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(formatPrice(product.fromPriceMinor), style: text.bodyLarge!.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            AppButton(
              id: 'pinned_buy',
              label: product.soldOut ? 'Sold out' : 'Buy',
              icon: Icons.shopping_bag_outlined,
              variant: AppButtonVariant.cta,
              onPressed: product.soldOut ? null : () => showProductSheet(context, product),
            ),
          ],
        ),
      ),
    );
  }
}
