import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/page_body.dart';
import '../../core/theme/status_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Player profile: club, position, role, loan status, statistics from the match event logs,
/// and the roster history when the viewer may see it (the player, their manager, organizer).
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(playerProvider(playerId));
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: TenantAppBar(title: value.value?.data.name ?? 'Player'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'player_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(playerProvider(playerId).future),
                children: [
                  AsyncView<Cached<PlayerProfile>>(
                    id: 'player',
                    value: value,
                    onRetry: () => ref.invalidate(playerProvider(playerId)),
                    builder: (r) {
                      final p = r.data;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (r.fromCache) const CachedNotice(),
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: Text(p.shirt == null ? p.position.toUpperCase() : '${p.shirt}', style: text.headlineSmall),
                              ),
                              const SizedBox(width: AppSpace.lg),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Semantics(header: true, child: Text(p.name, style: text.headlineSmall)),
                                    Text('${p.position.toUpperCase()} · ${humanize(p.role)}${p.sportName == null ? '' : ' · ${p.sportName}'}', style: text.bodyMedium!.copyWith(color: muted)),
                                    if (p.isMe) const Padding(padding: EdgeInsets.only(top: 4), child: StatusChip(kind: StatusKind.info, label: 'This is you', icon: Icons.person)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.lg),
                          if (p.club != null)
                            Card(
                              child: ListTile(
                                minTileHeight: AppSize.rowMin,
                                leading: ClubBadge(name: p.club!.name, logoUrl: p.club!.logoUrl, size: 32),
                                title: Text(p.club!.name),
                                subtitle: Text(p.leagueName ?? ''),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/club/${Uri.encodeComponent(p.club!.id)}'),
                              ),
                            )
                          else if (p.released)
                            const StatusChip(kind: StatusKind.neutral, label: 'Free agent (released)', icon: Icons.person_off_outlined),
                          if (p.onLoan) ...[
                            const SizedBox(height: AppSpace.sm),
                            StatusChip(kind: StatusKind.warning, label: 'On loan from ${p.loanFrom ?? 'another club'} until ${p.loanEnds ?? '?'}', icon: Icons.schedule_send_outlined),
                          ],
                          const SectionLabel('Statistics'),
                          StatGrid(tiles: [
                            StatTile(label: 'Club matches played', value: '${p.matchesPlayed}', icon: Icons.sports_outlined),
                            StatTile(label: 'Scoring total', value: '${p.totalValue}', icon: Icons.scoreboard_outlined),
                            StatTile(label: 'Discipline events', value: '${p.disciplineEvents}', icon: Icons.style_outlined),
                          ]),
                          if (p.stats.isNotEmpty) ...[
                            const SizedBox(height: AppSpace.md),
                            Card(
                              child: Column(children: [
                                for (final s in p.stats) ListTile(title: Text(s.label), trailing: Text('${s.count}', style: text.titleMedium)),
                              ]),
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpace.sm),
                              child: Text('No scoring events credited yet.', style: text.bodyMedium!.copyWith(color: muted)),
                            ),
                          if (p.history != null) ...[
                            const SectionLabel('Roster history'),
                            if (p.history!.isEmpty)
                              const EmptyState(id: 'player_history_empty', icon: Icons.history, message: 'No roster changes yet.')
                            else
                              Card(
                                child: Column(children: [
                                  for (final h in p.history!)
                                    ListTile(
                                      title: Text(h.summary),
                                      subtitle: Text('${h.effectiveDate} · by ${h.who} · ${DateFormat('d MMM y').format(h.when)}${h.why.isEmpty ? '' : ' · "${h.why}"'}'),
                                    ),
                                ]),
                              ),
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
