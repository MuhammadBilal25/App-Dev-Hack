import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/page_body.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_bar.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/sync_strip.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// One search box over sports, leagues, clubs, players and products.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TenantAppBar(title: 'Search'),
      body: Column(
        children: [
          const SyncStrip(),
          Expanded(
            child: Semantics(
              identifier: 'search_screen',
              container: true,
              child: PageBody(
                children: [
                  Semantics(
                    identifier: 'search_field',
                    label: 'Search',
                    textField: true,
                    child: TextField(
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _q = v.trim()));
                      },
                      decoration: const InputDecoration(hintText: 'Clubs, players, leagues, shirts…', prefixIcon: Icon(Icons.search)),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  if (_q.length < 2)
                    const EmptyState(id: 'search_hint', icon: Icons.search, message: 'Type at least two letters to search.')
                  else
                    AsyncView<SearchResults>(
                      id: 'search',
                      value: ref.watch(searchProvider(_q)),
                      onRetry: () => ref.invalidate(searchProvider(_q)),
                      builder: (r) {
                        if (r.isEmpty) return EmptyState(id: 'search_empty', icon: Icons.search_off, message: 'Nothing found for "$_q".');
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (r.sports.isNotEmpty) ...[
                              const SectionLabel('Sports'),
                              Card(
                                child: Column(children: [
                                  for (final s in r.sports)
                                    ListTile(leading: Icon(sportIcon(s.icon)), title: Text(s.name), onTap: () => context.push('/sports/${Uri.encodeComponent(s.id)}')),
                                ]),
                              ),
                            ],
                            if (r.leagues.isNotEmpty) ...[
                              const SectionLabel('Leagues'),
                              Card(clipBehavior: Clip.antiAlias, child: Column(children: [for (final l in r.leagues) LeagueTile(league: l)])),
                            ],
                            if (r.clubs.isNotEmpty) ...[
                              const SectionLabel('Clubs'),
                              Card(
                                child: Column(children: [
                                  for (final c in r.clubs)
                                    ListTile(
                                      leading: ClubBadge(name: c.name, logoUrl: c.logoUrl, size: 28),
                                      title: Text(c.name),
                                      subtitle: Text(c.leagueName ?? ''),
                                      onTap: () => context.push('/club/${Uri.encodeComponent(c.id)}'),
                                    ),
                                ]),
                              ),
                            ],
                            if (r.players.isNotEmpty) ...[
                              const SectionLabel('Players'),
                              Card(
                                child: Column(children: [
                                  for (final p in r.players)
                                    ListTile(
                                      leading: PersonAvatar(name: p.name),
                                      title: Text(p.name),
                                      subtitle: Text(p.club),
                                      onTap: () => context.push('/player/${Uri.encodeComponent(p.id)}'),
                                    ),
                                ]),
                              ),
                            ],
                            if (r.products.isNotEmpty) ...[
                              const SectionLabel('Store'),
                              ProductGrid(products: r.products),
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
