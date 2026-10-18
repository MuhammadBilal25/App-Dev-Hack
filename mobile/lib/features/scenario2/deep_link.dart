/// Day 2 deep links (spec 6.3 / FR-4.1). Maps the outside world to app routes:
///   nascon://entity/match-m1          -> /live/match/match-m1
///   nascon://stream/cs-session-101    -> /live/costream/cs-session-101
///   nascon://entity/player-alpha-1    -> /player/player-alpha-1
///   nascon://entity/club-alpha-1      -> /club/club-alpha-1
/// and Guest Web Player routes (what a scanned /q/{code} redirects to):
///   /web/matches/{id}/{live|preview|vod|notice}, /web/costream/{id}, /web/players/{id}, /web/clubs/{id}
library;

/// Route for an entity id, or null when the id is not one we know.
String? routeForEntity(String id) {
  if (id.startsWith('cs-session-')) return '/live/costream/$id';
  if (id.startsWith('match-')) return '/live/match/$id';
  if (id.startsWith('player-')) return '/player/$id';
  if (id.startsWith('club-')) return '/club/$id';
  return null;
}

/// App route for a nascon:// link. Android may hand the router the full URI, or only its path
/// (the host "entity" / "stream" dropped), so both shapes are accepted.
String? deepLinkTarget(Uri uri) {
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (uri.scheme == 'nascon') {
    final id = segs.isNotEmpty ? segs.last : null;
    return id == null ? null : routeForEntity(Uri.decodeComponent(id));
  }
  if (segs.length == 2 && (segs[0] == 'entity' || segs[0] == 'stream')) return routeForEntity(segs[1]);
  if (segs.length == 1) return routeForEntity(segs[0]);
  return null;
}

/// App route for a Guest Web Player path (after a /q/{code} redirect).
String? webRouteTarget(String path) {
  final segs = Uri.parse(path).pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.length < 3 || segs[0] != 'web') return null;
  final id = segs[2];
  switch (segs[1]) {
    case 'matches':
      return '/live/match/$id';
    case 'costream':
      return '/live/costream/$id';
    case 'players':
      return '/player/$id';
    case 'clubs':
      return '/club/$id';
  }
  return null;
}
