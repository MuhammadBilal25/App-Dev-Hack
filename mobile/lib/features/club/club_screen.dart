import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/page_body.dart';
import '../../core/theme/tenant.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/sync_strip.dart';
import '../../core/widgets/underline_tabs.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../fixtures/fixtures_screen.dart';
import 'roster_manage_sheet.dart';

/// Directory of the clubs the user can see, with search.
class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(clubsProvider);
    return Scaffold(
      appBar: const TenantAppBar(title: 'Clubs'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'clubs_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(clubsProvider.future),
                children: [
                  Semantics(
                    identifier: 'clubs_search',
                    label: 'Search clubs',
                    textField: true,
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                      decoration: const InputDecoration(hintText: 'Search clubs or leagues', prefixIcon: Icon(Icons.search)),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  AsyncView<Cached<List<ClubCard>>>(
                    id: 'clubs',
                    value: value,
                    onRetry: () => ref.invalidate(clubsProvider),
                    builder: (r) {
                      final list = r.data.where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q) || (c.leagueName ?? '').toLowerCase().contains(_q)).toList();
                      if (list.isEmpty) {
                        return EmptyState(id: 'clubs_empty', icon: Icons.shield_outlined, message: r.data.isEmpty ? 'No clubs to show yet.' : 'No clubs match "$_q".');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (r.fromCache) const CachedNotice(),
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (var i = 0; i < list.length; i++) ...[
                                  if (i > 0) const Divider(),
                                  Semantics(
                                    identifier: 'club_row_${list[i].id}',
                                    button: true,
                                    child: ListTile(
                                      minTileHeight: AppSize.rowMin,
                                      leading: ClubBadge(name: list[i].name, logoUrl: list[i].logoUrl, size: 32),
                                      title: Text(list[i].name),
                                      subtitle: Text([list[i].sportName, list[i].leagueName].whereType<String>().join(' · ')),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => context.push('/club/${Uri.encodeComponent(list[i].id)}'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
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

/// Club profile: crest/logo, colours, description, league memberships, stats, fixtures and
/// results, merchandise, roster, staff, venue and social. Managers get Manage / Edit / History.
class ClubProfileScreen extends ConsumerWidget {
  const ClubProfileScreen({super.key, required this.clubId});

  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(clubProvider(clubId));
    return Scaffold(
      appBar: TenantAppBar(title: value.value?.data.name ?? 'Club'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'club_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(clubProvider(clubId).future),
                children: [ClubProfileView(clubId: clubId)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ClubProfileView extends ConsumerStatefulWidget {
  const ClubProfileView({super.key, required this.clubId});

  final String clubId;

  @override
  ConsumerState<ClubProfileView> createState() => _ClubProfileViewState();
}

class _ClubProfileViewState extends ConsumerState<ClubProfileView> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return AsyncView<Cached<ClubProfile>>(
      id: 'club',
      value: ref.watch(clubProvider(widget.clubId)),
      onRetry: () => ref.invalidate(clubProvider(widget.clubId)),
      builder: (r) {
        final c = r.data;
        final sub = [if (c.sportName.isNotEmpty) c.sportName, if (c.handle != null) c.handle!].join(' · ');
        final primary = parseHex(c.primaryColor);
        final secondary = parseHex(c.secondaryColor);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (r.fromCache) const CachedNotice(),
            if (primary != null)
              Semantics(
                label: 'Club colours',
                child: Container(
                  height: 8,
                  margin: const EdgeInsets.only(bottom: AppSpace.lg),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    gradient: LinearGradient(colors: [primary, secondary ?? primary]),
                  ),
                ),
              ),
            Row(
              children: [
                ClubBadge(name: c.name, logoUrl: c.logoUrl, size: 76, decorative: false),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text(c.name, style: text.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      if (sub.isNotEmpty) Text(sub, style: text.bodyMedium!.copyWith(color: muted)),
                      if (c.rank != null) Text('${c.leagueName} · #${c.rank} · ${c.points} pts', style: text.bodyMedium!.copyWith(color: muted)),
                    ],
                  ),
                ),
              ],
            ),
            if (c.description.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text(c.description, style: text.bodyLarge),
            ],
            if (c.canManage || c.canEdit || c.canViewHistory || c.canManageStore) ...[
              const SizedBox(height: AppSpace.lg),
              if (c.canManage)
                AppButton(id: 'club_manage', label: 'Manage roster', icon: Icons.manage_accounts_outlined, onPressed: () => showRosterManageSheet(context, c)),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  if (c.canEdit)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/club/${Uri.encodeComponent(c.id)}/edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit profile'),
                    ),
                  if (c.canViewHistory)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/club/${Uri.encodeComponent(c.id)}/history'),
                      icon: const Icon(Icons.history),
                      label: const Text('Roster history'),
                    ),
                  if (c.canManageStore)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/manage/products'),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Club store'),
                    ),
                ],
              ),
            ],
            if (c.played != null) ...[
              const SizedBox(height: AppSpace.lg),
              StatGrid(perRow: 4, tiles: [
                StatTile(label: 'Played', value: '${c.played}'),
                StatTile(label: 'Won', value: '${c.won ?? 0}'),
                StatTile(label: 'Drawn', value: '${c.drawn ?? 0}'),
                StatTile(label: 'Lost', value: '${c.lost ?? 0}'),
              ]),
            ],
            if (c.leagues.isNotEmpty) ...[
              const SectionLabel('Competitions'),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final l in c.leagues)
                    ActionChip(
                      avatar: const Icon(Icons.emoji_events_outlined, size: 18),
                      label: Text(l.season.isEmpty ? l.name : '${l.name} · ${l.season}'),
                      onPressed: () => context.push('/leagues/${Uri.encodeComponent(l.id)}'),
                    ),
                ],
              ),
            ],
            if (c.upcoming.isNotEmpty) ...[
              const SectionLabel('Next matches'),
              _FixtureCard(fixtures: c.upcoming),
            ],
            if (c.results.isNotEmpty) ...[
              const SectionLabel('Recent results'),
              _FixtureCard(fixtures: c.results),
            ],
            if (c.productCount > 0) ...[
              SectionHeader('Club merchandise', onAction: () => context.go('/store'), actionLabel: 'Shop', id: 'club_shop'),
              Text('${c.productCount} ${c.productCount == 1 ? 'item' : 'items'} in the store.', style: text.bodyMedium!.copyWith(color: muted)),
            ],
            const SizedBox(height: AppSpace.lg),
            UnderlineTabs(
              id: 'club_tab',
              labels: ['Roster (${c.roster.length})', 'Staff (${c.staff.length})'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: AppSpace.md),
            AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.medium),
              child: _tab == 0 ? _Roster(key: const ValueKey('roster'), club: c) : _Staff(key: const ValueKey('staff'), club: c),
            ),
            const SectionLabel('Home venue'),
            Card(
              child: ListTile(
                minTileHeight: AppSize.rowMin,
                leading: const Icon(Icons.stadium_outlined),
                title: Text(c.venueName.isEmpty ? 'Venue to be announced' : c.venueName),
                subtitle: c.lat == null ? null : Text('${c.lat!.toStringAsFixed(4)}, ${c.lng!.toStringAsFixed(4)}', style: text.bodyMedium!.copyWith(fontFeatures: AppFonts.tabular)),
              ),
            ),
            if (c.social.isNotEmpty) ...[
              const SectionLabel('Social'),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final e in c.social.entries)
                      ListTile(
                        minTileHeight: 48,
                        leading: Icon(e.key == 'instagram' ? Icons.camera_alt_outlined : Icons.alternate_email),
                        title: Text(e.value),
                        subtitle: Text(e.key == 'x' ? 'X' : e.key[0].toUpperCase() + e.key.substring(1)),
                      ),
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

class _FixtureCard extends StatelessWidget {
  const _FixtureCard({required this.fixtures});

  final List<Fixture> fixtures;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < fixtures.length; i++) ...[
            if (i > 0) const Divider(),
            FixtureRow(fixture: fixtures[i]),
          ],
        ],
      ),
    );
  }
}

class _Roster extends StatelessWidget {
  const _Roster({super.key, required this.club});

  final ClubProfile club;

  @override
  Widget build(BuildContext context) {
    if (club.roster.isEmpty) {
      return const EmptyState(id: 'roster_empty', icon: Icons.groups_outlined, message: 'No players registered yet.');
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < club.roster.length; i++) ...[
            if (i > 0) const Divider(),
            Builder(builder: (context) {
              final p = club.roster[i];
              final badge = switch (p.role) {
                'captain' => 'C',
                'vice_captain' => 'VC',
                _ => null,
              };
              final roleWord = p.role.replaceAll('_', ' ');
              return Semantics(
                identifier: 'roster_${p.id}',
                button: true,
                label: '${p.name}, ${p.position.toUpperCase()}, $roleWord${p.onLoan ? ', on loan' : ''}',
                excludeSemantics: true,
                child: ListTile(
                  minTileHeight: AppSize.rowMin,
                  onTap: () => context.push('/player/${Uri.encodeComponent(p.id)}'),
                  leading: CircleAvatar(
                    backgroundColor: scheme.surfaceContainerHigh,
                    foregroundColor: scheme.onSurface,
                    child: Text(p.position.toUpperCase(), style: text.labelSmall),
                  ),
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${p.shirt == null ? '' : '#${p.shirt} · '}${roleWord[0].toUpperCase()}${roleWord.substring(1)}${p.onLoan ? ' · On loan' : ''}'),
                  trailing: badge == null
                      ? const Icon(Icons.chevron_right)
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
                          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.sm)),
                          child: Text(badge, style: text.labelSmall!.copyWith(color: scheme.onPrimaryContainer)),
                        ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _Staff extends StatelessWidget {
  const _Staff({super.key, required this.club});

  final ClubProfile club;

  @override
  Widget build(BuildContext context) {
    if (club.staff.isEmpty) {
      return const EmptyState(id: 'staff_empty', icon: Icons.badge_outlined, message: 'No staff listed yet.');
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < club.staff.length; i++) ...[
            if (i > 0) const Divider(),
            ListTile(
              minTileHeight: AppSize.rowMin,
              leading: PersonAvatar(name: club.staff[i].name),
              title: Text(club.staff[i].name),
              subtitle: Text(humanize(club.staff[i].role)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Immutable roster audit trail of a club: who changed what, when and why.
class RosterHistoryScreen extends ConsumerWidget {
  const RosterHistoryScreen({super.key, required this.clubId});

  final String clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(rosterHistoryProvider(clubId));
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: const TenantAppBar(title: 'Roster history'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'roster_history_screen',
              container: true,
              child: PageBody(
                onRefresh: () => ref.refresh(rosterHistoryProvider(clubId).future),
                children: [
                  Text('Every registration, transfer, loan and release. Entries are never edited or deleted.', style: text.bodyMedium!.copyWith(color: muted)),
                  const SizedBox(height: AppSpace.lg),
                  AsyncView<List<RosterChange>>(
                    id: 'roster_history',
                    value: value,
                    onRetry: () => ref.invalidate(rosterHistoryProvider(clubId)),
                    builder: (list) {
                      if (list.isEmpty) {
                        return const EmptyState(id: 'roster_history_empty', icon: Icons.history, message: 'No roster changes yet.');
                      }
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < list.length; i++) ...[
                              if (i > 0) const Divider(),
                              ListTile(
                                minTileHeight: 72,
                                leading: Icon(switch (list[i].action) {
                                  'add' => Icons.person_add_alt,
                                  'transfer' => Icons.swap_horiz,
                                  'loan' => Icons.schedule_send_outlined,
                                  'loan_return' => Icons.keyboard_return,
                                  'release' => Icons.person_remove_outlined,
                                  _ => Icons.edit_note,
                                }),
                                title: Text('${list[i].playerName}: ${list[i].summary}'),
                                subtitle: Text([
                                  'Effective ${list[i].effectiveDate}',
                                  'by ${list[i].who}',
                                  DateFormat('d MMM y, HH:mm').format(list[i].when),
                                  if (list[i].why.isNotEmpty) '"${list[i].why}"',
                                  if (list[i].state != 'active') humanize(list[i].state),
                                ].join(' · ')),
                                isThreeLine: true,
                              ),
                            ],
                          ],
                        ),
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
