import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/auth/auth_controller.dart';
import '../core/cache/api_cache.dart';
import 'models.dart';

export '../core/cache/api_cache.dart' show Cached;

/// Data for the screens. All of these fetch once per screen open or pull-to-refresh (never poll),
/// and the cached ones fall back to the last good response when offline.

final homeProvider = FutureProvider<Cached<HomeFeed>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final r = await cachedGet(ref, '/api/v1/home');
  return Cached(HomeFeed.fromJson(r.data), fromCache: r.fromCache);
});

final sportsProvider = FutureProvider<Cached<List<Sport>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final r = await cachedGet(ref, '/api/v1/sports');
  return Cached((r.data['sports'] as List).cast<Map<String, dynamic>>().map(Sport.fromJson).toList(), fromCache: r.fromCache);
});

final sportProvider = FutureProvider.family<Cached<SportDetail>, String>((ref, id) async {
  final r = await cachedGet(ref, '/api/v1/sports/${Uri.encodeComponent(id)}');
  return Cached(SportDetail.fromJson(r.data), fromCache: r.fromCache);
});

final leaguesProvider = FutureProvider<Cached<List<League>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final r = await cachedGet(ref, '/api/v1/leagues');
  return Cached((r.data['leagues'] as List).cast<Map<String, dynamic>>().map(League.fromJson).toList(), fromCache: r.fromCache);
});

final leagueProvider = FutureProvider.family<Cached<LeagueDetail>, String>((ref, id) async {
  final r = await cachedGet(ref, '/api/v1/leagues/${Uri.encodeComponent(id)}');
  return Cached(LeagueDetail.fromJson(r.data), fromCache: r.fromCache);
});

final bracketProvider = FutureProvider.family<List<BracketSection>, String>((ref, id) async {
  final r = await cachedGet(ref, '/api/v1/leagues/${Uri.encodeComponent(id)}/bracket');
  return parseBracket(r.data);
});

final fixturesProvider = FutureProvider<Cached<List<Fixture>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final r = await cachedGet(ref, '/api/v1/fixtures');
  return Cached((r.data['fixtures'] as List).cast<Map<String, dynamic>>().map(Fixture.fromJson).toList(), fromCache: r.fromCache);
});

final matchProvider = FutureProvider.family<Cached<MatchDetail>, String>((ref, id) async {
  final r = await cachedGet(ref, '/api/v1/matches/${Uri.encodeComponent(id)}');
  return Cached(MatchDetail.fromJson(r.data), fromCache: r.fromCache);
});

final standingsProvider = FutureProvider.family<Cached<Standings>, String>((ref, leagueId) async {
  final r = await cachedGet(ref, '/api/v1/standings/${Uri.encodeComponent(leagueId)}');
  return Cached(Standings.fromJson(r.data), fromCache: r.fromCache);
});

final clubsProvider = FutureProvider<Cached<List<ClubCard>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final r = await cachedGet(ref, '/api/v1/clubs');
  return Cached((r.data['clubs'] as List).cast<Map<String, dynamic>>().map(ClubCard.fromJson).toList(), fromCache: r.fromCache);
});

final clubProvider = FutureProvider.family<Cached<ClubProfile>, String>((ref, id) async {
  final r = await cachedGet(ref, '/api/v1/clubs/${Uri.encodeComponent(id)}');
  return Cached(ClubProfile.fromJson(r.data), fromCache: r.fromCache);
});

final rosterHistoryProvider = FutureProvider.family<List<RosterChange>, String>((ref, id) async {
  final body = await ref.read(apiClientProvider).get('/api/v1/clubs/${Uri.encodeComponent(id)}/roster-history') as Map<String, dynamic>;
  return (body['history'] as List).cast<Map<String, dynamic>>().map(RosterChange.fromJson).toList();
});

final playerProvider = FutureProvider.family<Cached<PlayerProfile>, String>((ref, id) async {
  final r = await cachedGet(ref, '/api/v1/players/${Uri.encodeComponent(id)}');
  return Cached(PlayerProfile.fromJson(r.data), fromCache: r.fromCache);
});

final searchProvider = FutureProvider.family<SearchResults, String>((ref, q) async {
  final body = await ref.read(apiClientProvider).get('/api/v1/search?q=${Uri.encodeQueryComponent(q)}') as Map<String, dynamic>;
  return SearchResults.fromJson(body);
});

/// Catalogue query string (filters and sort), e.g. `category=caps&sort=price_asc`.
final catalogueQueryProvider = NotifierProvider<CatalogueQuery, Map<String, String>>(CatalogueQuery.new);

class CatalogueQuery extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {'sort': 'newest'};

  void set(String key, String? value) {
    final next = {...state};
    if (value == null || value.isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    state = next;
  }

  void clearFilters() => state = {'sort': state['sort'] ?? 'newest'};
}

/// The store is not cached: stock must be live, and checkout needs the network anyway.
final catalogueProvider = FutureProvider<Catalogue>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final q = ref.watch(catalogueQueryProvider);
  final query = q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  final body = await ref.read(apiClientProvider).get('/api/v1/products${query.isEmpty ? '' : '?$query'}') as Map<String, dynamic>;
  return Catalogue.fromJson(body);
});

final productProvider = FutureProvider.family<Product, String>((ref, id) async {
  final body = await ref.read(apiClientProvider).get('/api/v1/products/${Uri.encodeComponent(id)}') as Map<String, dynamic>;
  return Product.fromJson(body);
});

final categoriesProvider = FutureProvider<List<Facet>>((ref) async {
  final body = await ref.read(apiClientProvider).get('/api/v1/store/categories') as Map<String, dynamic>;
  return (body['categories'] as List).cast<Map<String, dynamic>>().map((c) => Facet(c['category_id'] as String, c['name'] as String)).toList();
});

/// `mine` (my purchases) or `managed` (orders for clubs I run the store of).
final ordersProvider = FutureProvider.family<List<Order>, String>((ref, scope) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final body = await ref.read(apiClientProvider).get('/api/v1/orders?scope=$scope') as Map<String, dynamic>;
  return (body['orders'] as List).cast<Map<String, dynamic>>().map(Order.fromJson).toList();
});

final orderProvider = FutureProvider.family<Order, String>((ref, id) async {
  final body = await ref.read(apiClientProvider).get('/api/v1/orders/${Uri.encodeComponent(id)}') as Map<String, dynamic>;
  return Order.fromJson(body);
});

final receiptProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return await ref.read(apiClientProvider).get('/api/v1/orders/${Uri.encodeComponent(id)}/receipt') as Map<String, dynamic>;
});

/// Role dashboards and admin lists: plain JSON maps, read by their screens.
final organizerDashboardProvider = FutureProvider<Cached<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return cachedGet(ref, '/api/v1/dashboard/organizer');
});

final managerDashboardProvider = FutureProvider<Cached<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return cachedGet(ref, '/api/v1/dashboard/manager');
});

final adminGetProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, path) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return await ref.read(apiClientProvider).get('/api/v1/admin/$path') as Map<String, dynamic>;
});
