/// Typed views over the `/api/v1` responses. Parsing is lenient: missing optional fields become
/// null so a slightly different server never crashes a screen.
library;

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

class TeamScore {
  const TeamScore({required this.id, required this.name, required this.score, this.wickets, this.overs});

  final String id;
  final String name;
  final int score;
  final int? wickets;
  final String? overs;

  /// "2", or "145/6" for innings sports.
  String get display => wickets == null ? '$score' : '$score/$wickets';

  factory TeamScore.fromJson(Map<String, dynamic> j) => TeamScore(
        id: _str(j['team_id']),
        name: _str(j['name'], _str(j['team_id'])),
        score: _int(j['score']),
        wickets: j['wickets'] is num ? (j['wickets'] as num).toInt() : null,
        overs: j['overs'] as String?,
      );
}

enum MatchStatus { upcoming, live, completed, postponed }

MatchStatus _status(Object? s) => switch (s) {
      'in_progress' => MatchStatus.live,
      'completed' => MatchStatus.completed,
      'postponed' => MatchStatus.postponed,
      _ => MatchStatus.upcoming,
    };

class Fixture {
  const Fixture({
    required this.id,
    required this.leagueId,
    required this.leagueName,
    required this.sportId,
    required this.round,
    required this.kickoff,
    required this.venue,
    required this.status,
    required this.home,
    required this.away,
    this.minute,
    this.winnerId,
  });

  final String id;
  final String leagueId;
  final String leagueName;
  final String sportId;
  final int round;
  final DateTime kickoff;
  final String venue;
  final MatchStatus status;
  final TeamScore home;
  final TeamScore away;
  final int? minute;
  final String? winnerId;

  bool get hasScore => status == MatchStatus.live || status == MatchStatus.completed;

  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
        id: _str(j['match_id']),
        leagueId: _str(j['league_id']),
        leagueName: _str(j['league_name']),
        sportId: _str(j['sport_id']),
        round: _int(j['round']),
        kickoff: DateTime.tryParse(_str(j['kickoff_at']))?.toLocal() ?? DateTime.now(),
        venue: _str(j['venue']),
        status: _status(j['status']),
        home: TeamScore.fromJson(j['home'] as Map<String, dynamic>),
        away: TeamScore.fromJson(j['away'] as Map<String, dynamic>),
        minute: j['minute'] is num ? (j['minute'] as num).toInt() : null,
        winnerId: j['winner_team_id'] as String?,
      );
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.type,
    required this.label,
    required this.compensated,
    this.minute,
    this.teamName,
    this.reason,
  });

  final String id;
  final String type;
  final String label;
  final bool compensated;
  final int? minute;
  final String? teamName;
  final String? reason;

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
        id: _str(j['event_id']),
        type: _str(j['type']),
        label: _str(j['label'], _str(j['type'])),
        compensated: j['compensated'] == true,
        minute: j['minute'] is num ? (j['minute'] as num).toInt() : null,
        teamName: j['team_name'] as String?,
        reason: j['reason'] as String?,
      );
}

class Variant {
  const Variant({required this.id, required this.size, required this.color, required this.priceMinor, required this.stock});

  final String id;
  final String size;
  final String color;
  final int priceMinor;
  final int stock;

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(
        id: _str(j['variant_id']),
        size: _str(j['size'], '-'),
        color: _str(j['color']),
        priceMinor: _int(j['price_minor']),
        stock: _int(j['stock']),
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.clubName,
    required this.variants,
  });

  final String id;
  final String name;
  final String description;
  final String category;
  final String clubName;
  final List<Variant> variants;

  int get fromPriceMinor => variants.isEmpty ? 0 : variants.map((v) => v.priceMinor).reduce((a, b) => a < b ? a : b);
  bool get soldOut => variants.every((v) => v.stock <= 0);

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: _str(j['product_id']),
        name: _str(j['name']),
        description: _str(j['description']),
        category: _str(j['category']),
        clubName: _str(j['club_name']),
        variants: _list(j['variants']).map(Variant.fromJson).toList(),
      );
}

class MatchDetail {
  const MatchDetail({
    required this.fixture,
    required this.sportName,
    required this.timeline,
    required this.canScore,
    this.pinned,
  });

  final Fixture fixture;
  final String sportName;
  final List<TimelineEvent> timeline;
  final bool canScore;
  final Product? pinned;

  factory MatchDetail.fromJson(Map<String, dynamic> j) => MatchDetail(
        fixture: Fixture.fromJson(j),
        sportName: _str(j['sport_name']),
        timeline: _list(j['timeline']).map(TimelineEvent.fromJson).toList(),
        canScore: j['can_score'] == true,
        pinned: j['pinned_product'] is Map<String, dynamic> ? Product.fromJson(j['pinned_product'] as Map<String, dynamic>) : null,
      );
}

enum QualStatus { clinched, stillPossible, eliminated }

class StandingRow {
  const StandingRow({
    required this.rank,
    required this.teamId,
    required this.teamName,
    required this.played,
    required this.diff,
    required this.points,
    required this.status,
  });

  final int rank;
  final String teamId;
  final String teamName;
  final int played;
  final num diff;
  final int points;
  final QualStatus status;

  factory StandingRow.fromJson(Map<String, dynamic> j) => StandingRow(
        rank: _int(j['rank']),
        teamId: _str(j['team_id']),
        teamName: _str(j['team_name'], _str(j['team_id'])),
        played: _int(j['played']),
        diff: j['diff'] is num ? j['diff'] as num : 0,
        points: _int(j['points']),
        status: switch (j['status']) {
          'clinched' => QualStatus.clinched,
          'eliminated' => QualStatus.eliminated,
          _ => QualStatus.stillPossible,
        },
      );
}

class Standings {
  const Standings({required this.leagueId, required this.leagueName, required this.spots, required this.rows});

  final String leagueId;
  final String leagueName;
  final int spots;
  final List<StandingRow> rows;

  factory Standings.fromJson(Map<String, dynamic> j) => Standings(
        leagueId: _str(j['league_id']),
        leagueName: _str(j['league_name']),
        spots: _int(j['qualification_spots']),
        rows: _list(j['table']).map(StandingRow.fromJson).toList(),
      );
}

class League {
  const League({required this.id, required this.name, required this.sportName, required this.fixtureCount});

  final String id;
  final String name;
  final String sportName;
  final int fixtureCount;

  factory League.fromJson(Map<String, dynamic> j) => League(
        id: _str(j['league_id']),
        name: _str(j['name']),
        sportName: _str(j['sport_name']),
        fixtureCount: _int(j['fixture_count']),
      );
}

class RosterPlayer {
  const RosterPlayer({required this.id, required this.name, required this.position, required this.role, this.shirt});

  final String id;
  final String name;
  final String position;
  final String role;
  final int? shirt;

  factory RosterPlayer.fromJson(Map<String, dynamic> j) => RosterPlayer(
        id: _str(j['player_id']),
        name: _str(j['name']),
        position: _str(j['position']),
        role: _str(j['role']),
        shirt: j['shirt'] is num ? (j['shirt'] as num).toInt() : null,
      );
}

class StaffMember {
  const StaffMember({required this.name, required this.role});

  final String name;
  final String role;
}

class ClubProfile {
  const ClubProfile({
    required this.id,
    required this.name,
    required this.sportName,
    required this.leagueName,
    required this.venueName,
    required this.lat,
    required this.lng,
    required this.social,
    required this.roster,
    required this.staff,
    required this.canManage,
    this.rank,
    this.played,
    this.points,
  });

  final String id;
  final String name;
  final String sportName;
  final String leagueName;
  final String venueName;
  final double? lat;
  final double? lng;
  final Map<String, String> social;
  final List<RosterPlayer> roster;
  final List<StaffMember> staff;
  final bool canManage;
  final int? rank;
  final int? played;
  final int? points;

  String? get handle => social['x'] ?? social['instagram'] ?? (social.isEmpty ? null : social.values.first);

  factory ClubProfile.fromJson(Map<String, dynamic> j) {
    final venue = j['venue'] is Map<String, dynamic> ? j['venue'] as Map<String, dynamic> : const <String, dynamic>{};
    final social = j['social'] is Map ? (j['social'] as Map).map((k, v) => MapEntry('$k', '$v')) : <String, String>{};
    final stats = j['stats'] is Map<String, dynamic> ? j['stats'] as Map<String, dynamic> : null;
    return ClubProfile(
      id: _str(j['club_id']),
      name: _str(j['name']),
      sportName: _str(j['sport_name']),
      leagueName: _str(j['league_name']),
      venueName: _str(venue['name']),
      lat: venue['lat'] is num ? (venue['lat'] as num).toDouble() : null,
      lng: venue['lng'] is num ? (venue['lng'] as num).toDouble() : null,
      social: social,
      roster: _list(j['roster']).map(RosterPlayer.fromJson).toList(),
      staff: _list(j['staff']).map((s) => StaffMember(name: _str(s['name']), role: _str(s['role']))).toList(),
      canManage: j['can_manage'] == true,
      rank: stats == null ? null : _int(stats['rank']),
      played: stats == null ? null : _int(stats['played']),
      points: stats == null ? null : _int(stats['points']),
    );
  }
}

class ClubRef {
  const ClubRef({required this.id, required this.name});

  final String id;
  final String name;
}

/// `PKR 4500.00`: minor units ÷ 100, two decimals, no thousands separator (UI.md §6.8).
String formatPrice(int minor, [String currency = 'PKR']) => '$currency ${(minor / 100).toStringAsFixed(2)}';
