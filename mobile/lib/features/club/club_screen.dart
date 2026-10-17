import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/brand/club_crest.dart';
import '../../core/layout/page_body.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../shell/tab_page.dart';

/// Club tab: the user's own club by default, any club of the tenant via the chips.
class ClubScreen extends ConsumerStatefulWidget {
  const ClubScreen({super.key});

  @override
  ConsumerState<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends ConsumerState<ClubScreen> {
  String? _clubId;

  @override
  Widget build(BuildContext context) {
    final clubs = ref.watch(clubsProvider);
    final own = ref.watch(currentUserProvider)?.clubId;
    return TabPage(
      id: 'club_screen',
      title: 'Club',
      onRefresh: () async {
        ref.invalidate(clubsProvider);
        if (_clubId != null) ref.invalidate(clubProvider(_clubId!));
      },
      children: [
        AsyncView<Cached<List<ClubRef>>>(
          id: 'clubs',
          value: clubs,
          onRetry: () => ref.invalidate(clubsProvider),
          builder: (r) {
            if (r.data.isEmpty) {
              return const EmptyState(id: 'club_empty', icon: Icons.shield_outlined, message: 'No clubs to show yet. Clubs in your organisation appear here.');
            }
            final id = _clubId ?? (r.data.any((c) => c.id == own) ? own! : r.data.first.id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: AppSize.touch + AppSpace.sm,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in r.data)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpace.sm),
                          child: Semantics(
                            identifier: 'club_pick_${c.id}',
                            button: true,
                            selected: c.id == id,
                            child: ChoiceChip(
                              avatar: ClubCrest(name: c.name, size: 18),
                              label: Text(c.id == own ? '${c.name} (mine)' : c.name),
                              selected: c.id == id,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _clubId = c.id),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                _ClubProfileView(clubId: id),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ClubProfileView extends ConsumerStatefulWidget {
  const _ClubProfileView({required this.clubId});

  final String clubId;

  @override
  ConsumerState<_ClubProfileView> createState() => _ClubProfileViewState();
}

class _ClubProfileViewState extends ConsumerState<_ClubProfileView> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AsyncView<Cached<ClubProfile>>(
      id: 'club',
      value: ref.watch(clubProvider(widget.clubId)),
      onRetry: () => ref.invalidate(clubProvider(widget.clubId)),
      builder: (r) {
        final c = r.data;
        final sub = [if (c.sportName.isNotEmpty) c.sportName, if (c.handle != null) c.handle!].join(' · ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (r.fromCache) const CachedNotice(),
            Row(
              children: [
                ClubCrest(name: c.name, size: 76, decorative: false),
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
            if (c.canManage) ...[
              const SizedBox(height: AppSpace.lg),
              AppButton(id: 'club_manage', label: 'Manage', icon: Icons.manage_accounts_outlined, onPressed: () => _showManage(context, c)),
            ],
            const SizedBox(height: AppSpace.lg),
            Semantics(
              identifier: 'club_tabs',
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text('Roster (${c.roster.length})')),
                    ButtonSegment(value: 1, label: Text('Staff (${c.staff.length})')),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
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

  void _showManage(BuildContext context, ClubProfile c) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => Semantics(
        identifier: 'club_manage_sheet',
        container: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Manage ${c.name}', style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: AppSpace.sm),
              Text('Transfers, loans and releases are not available in this version yet.', style: Theme.of(sheet).textTheme.bodyLarge),
              const SizedBox(height: AppSpace.xl),
              AppButton(id: 'club_manage_close', label: 'Close', variant: AppButtonVariant.secondary, onPressed: () => Navigator.of(sheet).pop()),
            ],
          ),
        ),
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
                label: '${p.name}, ${p.position.toUpperCase()}, $roleWord',
                excludeSemantics: true,
                child: ListTile(
                  minTileHeight: AppSize.rowMin,
                  leading: CircleAvatar(
                    backgroundColor: scheme.surfaceContainerHigh,
                    foregroundColor: scheme.onSurface,
                    child: Text(p.position.toUpperCase(), style: text.labelSmall),
                  ),
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${p.shirt == null ? '' : '#${p.shirt} · '}${roleWord[0].toUpperCase()}${roleWord.substring(1)}'),
                  trailing: badge == null
                      ? null
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
              leading: const Icon(Icons.person_outline),
              title: Text(club.staff[i].name),
              subtitle: Text(club.staff[i].role[0].toUpperCase() + club.staff[i].role.substring(1)),
            ),
          ],
        ],
      ),
    );
  }
}
