import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/auth/auth_controller.dart';
import '../core/cache/api_cache.dart';
import 'models.dart';

export '../core/cache/api_cache.dart' show Cached;

/// Data for the screens. All of these fetch once per screen open or pull-to-refresh (never poll),
/// and the cached ones fall back to the last good response when offline.

final leaguesProvider = FutureProvider<Cached<List<League>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final r = await cachedGet(ref, '/api/v1/leagues');
  return Cached((r.data['leagues'] as List).cast<Map<String, dynamic>>().map(League.fromJson).toList(), fromCache: r.fromCache);
});

final fixturesProvider = FutureProvider<Cached<List<Fixture>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final r = await cachedGet(ref, '/api/v1/fixtures');
  final fixtures = (r.data['fixtures'] as List).cast<Map<String, dynamic>>().map(Fixture.fromJson).toList();
  if (!r.fromCache) {
    // Cache every listed match's detail in the background (live first), so a match can be opened
    // and scored offline without having been opened online. One request per match, no polling.
    final ordered = [...fixtures]..sort((a, b) => (a.status == MatchStatus.live ? 0 : 1).compareTo(b.status == MatchStatus.live ? 0 : 1));
    unawaited(warmCache(ref.read(apiClientProvider), ref.read(cacheBoxProvider), ordered.map((f) => matchPath(f.id))));
  }
  return Cached(fixtures, fromCache: r.fromCache);
});

String matchPath(String id) => '/api/v1/matches/${Uri.encodeComponent(id)}';

final matchProvider = FutureProvider.family<Cached<MatchDetail>, String>((ref, id) async {
  final r = await cachedGet(ref, matchPath(id));
  return Cached(MatchDetail.fromJson(r.data), fromCache: r.fromCache);
});

final standingsProvider = FutureProvider.family<Cached<Standings>, String>((ref, leagueId) async {
  final r = await cachedGet(ref, '/api/v1/standings/${Uri.encodeComponent(leagueId)}');
  return Cached(Standings.fromJson(r.data), fromCache: r.fromCache);
});

final clubsProvider = FutureProvider<Cached<List<ClubRef>>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final r = await cachedGet(ref, '/api/v1/clubs');
  final list = (r.data['clubs'] as List).cast<Map<String, dynamic>>();
  return Cached([for (final c in list) ClubRef(id: c['club_id'] as String, name: c['name'] as String)], fromCache: r.fromCache);
});

final clubProvider = FutureProvider.family<Cached<ClubProfile>, String>((ref, id) async {
  final r = await cachedGet(ref, '/api/v1/clubs/${Uri.encodeComponent(id)}');
  return Cached(ClubProfile.fromJson(r.data), fromCache: r.fromCache);
});

/// The store is not cached: stock must be live, and checkout needs the network anyway.
final catalogueProvider = FutureProvider<List<Product>>((ref) async {
  ref.watch(currentUserProvider.select((u) => u?.id));
  final body = await ref.read(apiClientProvider).get('/api/v1/catalogue') as Map<String, dynamic>;
  return (body['products'] as List).cast<Map<String, dynamic>>().map(Product.fromJson).toList();
});
