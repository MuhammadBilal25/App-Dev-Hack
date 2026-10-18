/// Typed views over the `/api/v1` responses. Parsing is lenient: missing optional fields become
/// null so a slightly different server never crashes a screen.
library;

int _int(Object? v) => v is num ? v.toInt() : 0;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];
Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : const {};

class TeamScore {
  const TeamScore({required this.id, required this.name, required this.score, this.wickets, this.overs, this.logoUrl});

  final String id;
  final String name;
  final int score;
  final int? wickets;
  final String? overs;
  final String? logoUrl;

  /// "2", or "145/6" for innings sports.
  String get display => wickets == null ? '$score' : '$score/$wickets';

  factory TeamScore.fromJson(Map<String, dynamic> j) => TeamScore(
        id: _str(j['team_id']),
        name: _str(j['name'], _str(j['team_id'])),
        score: _int(j['score']),
        wickets: _intOrNull(j['wickets']),
        overs: j['overs'] as String?,
        logoUrl: _strOrNull(j['logo_url']),
      );
}

enum MatchStatus { upcoming, live, completed, postponed, cancelled, abandoned }

MatchStatus _status(Object? s) => switch (s) {
      'in_progress' => MatchStatus.live,
      'completed' => MatchStatus.completed,
      'postponed' => MatchStatus.postponed,
      'cancelled' => MatchStatus.cancelled,
      'abandoned' => MatchStatus.abandoned,
      _ => MatchStatus.upcoming,
    };

/// Wire name of a status for `POST /matches/{id}/status`.
String statusWire(MatchStatus s) => switch (s) {
      MatchStatus.live => 'in_progress',
      MatchStatus.upcoming => 'upcoming',
      MatchStatus.completed => 'completed',
      MatchStatus.postponed => 'postponed',
      MatchStatus.cancelled => 'cancelled',
      MatchStatus.abandoned => 'abandoned',
    };

String statusLabel(MatchStatus s) => switch (s) {
      MatchStatus.live => 'Live',
      MatchStatus.upcoming => 'Upcoming',
      MatchStatus.completed => 'Full time',
      MatchStatus.postponed => 'Postponed',
      MatchStatus.cancelled => 'Cancelled',
      MatchStatus.abandoned => 'Abandoned',
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
    this.version = 0,
    this.sportName = '',
    this.scoringModel = 'event',
    this.stage,
    this.statusReason,
    this.seeded = false,
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
  final String sportName;
  final String scoringModel;

  /// "Round 2", "Semi-finals", "Winners R1"...
  final String? stage;
  final String? statusReason;

  /// Created by the demo seed (shown with a "Demo data" note, never presented as real).
  final bool seeded;

  /// Length of the match event log: the `base_version` for offline score actions.
  final int version;

  bool get hasScore => status == MatchStatus.live || status == MatchStatus.completed || status == MatchStatus.abandoned;
  String get stageLabel => stage ?? 'Round $round';

  factory Fixture.fromJson(Map<String, dynamic> j) => Fixture(
        id: _str(j['match_id']),
        leagueId: _str(j['league_id']),
        leagueName: _str(j['league_name']),
        sportId: _str(j['sport_id']),
        round: _int(j['round']),
        kickoff: DateTime.tryParse(_str(j['kickoff_at']))?.toLocal() ?? DateTime.now(),
        venue: _str(j['venue']),
        status: _status(j['status']),
        home: TeamScore.fromJson(_map(j['home'])),
        away: TeamScore.fromJson(_map(j['away'])),
        minute: _intOrNull(j['minute']),
        winnerId: j['winner_team_id'] as String?,
        version: _int(j['version']),
        sportName: _str(j['sport_name']),
        scoringModel: _str(j['scoring_model'], 'event'),
        stage: _strOrNull(j['stage']),
        statusReason: _strOrNull(j['status_reason']),
        seeded: j['seeded'] == true,
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
    this.playerName,
    this.signature,
  });

  final String id;
  final String type;
  final String label;
  final bool compensated;
  final int? minute;
  final String? teamName;
  final String? reason;
  final String? playerName;
  final String? signature;

  /// Events a compensation may target (backend COMPENSABLE list).
  bool get correctable => !compensated && (type == 'score' || type == 'discipline' || type == 'tiebreak_winner');

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
        id: _str(j['event_id']),
        type: _str(j['type']),
        label: _str(j['label'], _str(j['type'])),
        compensated: j['compensated'] == true,
        minute: _intOrNull(j['minute']),
        teamName: j['team_name'] as String?,
        reason: j['reason'] as String?,
        playerName: _strOrNull(j['player_name']),
        signature: _strOrNull(j['signature']),
      );
}

// ---------------------------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------------------------
class Variant {
  const Variant({
    required this.id,
    required this.priceMinor,
    required this.stock,
    this.size,
    this.color,
    this.label = 'Standard',
    int? unitPriceMinor,
    this.salePriceMinor,
    this.sku = '',
    this.active = true,
  }) : unitPriceMinor = unitPriceMinor ?? priceMinor;

  final String id;
  final String? size;
  final String? color;
  final String label;

  /// List price.
  final int priceMinor;

  /// What a buyer pays now (sale or scheduled price applied by the server).
  final int unitPriceMinor;
  final int? salePriceMinor;
  final int stock;
  final String sku;
  final bool active;

  bool get onSale => unitPriceMinor < priceMinor;
  bool get available => active && stock > 0;

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(
        id: _str(j['variant_id']),
        size: _strOrNull(j['size']),
        color: _strOrNull(j['color']),
        label: _str(j['label'], 'Standard'),
        priceMinor: _int(j['price_minor']),
        unitPriceMinor: _intOrNull(j['unit_price_minor']),
        salePriceMinor: _intOrNull(j['sale_price_minor']),
        stock: _int(j['stock']),
        sku: _str(j['sku']),
        active: j['active'] != false,
      );
}

class ProductImage {
  const ProductImage({required this.id, required this.url, required this.primary});

  final String id;
  final String url;
  final bool primary;

  factory ProductImage.fromJson(Map<String, dynamic> j) => ProductImage(id: _str(j['image_id']), url: _str(j['url']), primary: j['primary'] == true);
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.clubName,
    required this.variants,
    this.clubId = '',
    this.categoryName = '',
    this.sportName,
    this.images = const [],
    this.imageUrl,
    this.active = true,
    this.canManage = false,
    this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final String category;
  final String categoryName;
  final String clubId;
  final String clubName;
  final String? sportName;
  final List<Variant> variants;
  final List<ProductImage> images;
  final String? imageUrl;
  final bool active;
  final bool canManage;
  final DateTime? createdAt;

  List<Variant> get sellable => variants.where((v) => v.active).toList();
  int get fromPriceMinor => sellable.isEmpty ? 0 : sellable.map((v) => v.unitPriceMinor).reduce((a, b) => a < b ? a : b);
  int get listPriceMinor => sellable.isEmpty ? 0 : sellable.map((v) => v.priceMinor).reduce((a, b) => a < b ? a : b);
  bool get onSale => sellable.any((v) => v.onSale);
  bool get soldOut => sellable.every((v) => v.stock <= 0);
  bool get lowStock => !soldOut && sellable.any((v) => v.stock > 0 && v.stock <= 3);
  bool get hasSizes => variants.any((v) => v.size != null);
  bool get hasColors => variants.any((v) => v.color != null);

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: _str(j['product_id']),
        name: _str(j['name']),
        description: _str(j['description']),
        category: _str(j['category']),
        categoryName: _str(j['category_name'], _str(j['category'])),
        clubId: _str(j['club_id']),
        clubName: _str(j['club_name']),
        sportName: _strOrNull(j['sport_name']),
        variants: _list(j['variants']).map(Variant.fromJson).toList(),
        images: _list(j['images']).map(ProductImage.fromJson).toList(),
        imageUrl: _strOrNull(j['image_url']),
        active: j['active'] != false,
        canManage: j['can_manage'] == true,
        createdAt: DateTime.tryParse(_str(j['created_at']))?.toLocal(),
      );
}

class Facet {
  const Facet(this.id, this.name);

  final String id;
  final String name;
}

class Catalogue {
  const Catalogue({required this.products, this.sizes = const [], this.colors = const [], this.categories = const [], this.clubs = const [], this.sports = const []});

  final List<Product> products;
  final List<String> sizes;
  final List<String> colors;
  final List<Facet> categories;
  final List<Facet> clubs;
  final List<Facet> sports;

  factory Catalogue.fromJson(Map<String, dynamic> j) {
    final f = _map(j['facets']);
    List<Facet> facets(String key, String idKey) => _list(f[key]).map((x) => Facet(_str(x[idKey]), _str(x['name']))).toList();
    return Catalogue(
      products: _list(j['products']).map(Product.fromJson).toList(),
      sizes: _strings(f['sizes']),
      colors: _strings(f['colors']),
      categories: facets('categories', 'category_id'),
      clubs: facets('clubs', 'club_id'),
      sports: facets('sports', 'sport_id'),
    );
  }
}

/// One server-priced cart line from `POST /cart/quote`.
class QuoteLine {
  const QuoteLine({
    required this.variantId,
    required this.quantity,
    required this.status,
    this.productId,
    this.productName = '',
    this.clubName = '',
    this.label = '',
    this.imageUrl,
    this.unitPriceMinor = 0,
    this.lineTotalMinor = 0,
    this.availableStock = 0,
    this.message,
  });

  final String variantId;
  final int quantity;

  /// ok, price_changed, insufficient_stock, out_of_stock or unavailable.
  final String status;
  final String? productId;
  final String productName;
  final String clubName;
  final String label;
  final String? imageUrl;
  final int unitPriceMinor;
  final int lineTotalMinor;
  final int availableStock;
  final String? message;

  bool get ok => status == 'ok';

  factory QuoteLine.fromJson(Map<String, dynamic> j) => QuoteLine(
        variantId: _str(j['variant_id']),
        quantity: _int(j['quantity']),
        status: _str(j['status'], 'unavailable'),
        productId: _strOrNull(j['product_id']),
        productName: _str(j['product_name']),
        clubName: _str(j['club_name']),
        label: _str(j['label']),
        imageUrl: _strOrNull(j['image_url']),
        unitPriceMinor: _int(j['unit_price_minor']),
        lineTotalMinor: _int(j['line_total_minor']),
        availableStock: _int(j['available_stock']),
        message: _strOrNull(j['message']),
      );
}

class Quote {
  const Quote({
    required this.lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.canCheckout,
    this.discountCode,
    this.discountValid,
    this.discountPercent = 0,
  });

  final List<QuoteLine> lines;
  final int subtotalMinor;
  final int discountMinor;
  final int totalMinor;
  final bool canCheckout;
  final String? discountCode;
  final bool? discountValid;
  final int discountPercent;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        lines: _list(j['lines']).map(QuoteLine.fromJson).toList(),
        subtotalMinor: _int(j['subtotal_minor']),
        discountMinor: _int(j['discount_minor']),
        totalMinor: _int(j['total_minor']),
        canCheckout: j['can_checkout'] == true,
        discountCode: _strOrNull(j['discount_code']),
        discountValid: j['discount_valid'] as bool?,
        discountPercent: _int(j['discount_percent']),
      );
}

class OrderLine {
  const OrderLine({required this.variantId, required this.productName, required this.label, required this.quantity, required this.unitPriceMinor, required this.lineTotalMinor, this.clubName = '', this.imageUrl});

  final String variantId;
  final String productName;
  final String label;
  final String clubName;
  final String? imageUrl;
  final int quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        variantId: _str(j['variant_id']),
        productName: _str(j['product_name'], _str(j['variant_id'])),
        label: _str(j['label']),
        clubName: _str(j['club_name']),
        imageUrl: _strOrNull(j['image_url']),
        quantity: _int(j['quantity']),
        unitPriceMinor: _int(j['unit_price_minor']),
        lineTotalMinor: _int(j['line_total_minor']),
      );
}

class OrderEvent {
  const OrderEvent({required this.to, required this.at, this.by, this.reason});

  final String to;
  final DateTime at;
  final String? by;
  final String? reason;

  factory OrderEvent.fromJson(Map<String, dynamic> j) =>
      OrderEvent(to: _str(j['to']), at: DateTime.tryParse(_str(j['at']))?.toLocal() ?? DateTime.now(), by: _strOrNull(j['by']), reason: _strOrNull(j['reason']));
}

class Order {
  const Order({
    required this.id,
    required this.status,
    required this.paymentStatus,
    required this.lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.createdAt,
    this.customerName = '',
    this.customerEmail = '',
    this.discountCode,
    this.history = const [],
    this.signature = '',
    this.refundId,
  });

  final String id;

  /// paid, packed, shipped, delivered, cancelled or refunded.
  final String status;
  final String paymentStatus;
  final List<OrderLine> lines;
  final int subtotalMinor;
  final int discountMinor;
  final int totalMinor;
  final DateTime createdAt;
  final String customerName;
  final String customerEmail;
  final String? discountCode;
  final List<OrderEvent> history;
  final String signature;
  final String? refundId;

  int get itemCount => lines.fold(0, (n, l) => n + l.quantity);

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: _str(j['order_id']),
        status: _str(j['status'], 'paid'),
        paymentStatus: _str(j['payment_status'], _str(_map(j['payment'])['state'], 'captured')),
        lines: _list(j['lines']).map(OrderLine.fromJson).toList(),
        subtotalMinor: _int(j['subtotal_minor']),
        discountMinor: _int(j['discount_minor']),
        totalMinor: _int(j['total_minor']),
        createdAt: DateTime.tryParse(_str(j['created_at']))?.toLocal() ?? DateTime.now(),
        customerName: _str(j['customer_name']),
        customerEmail: _str(j['customer_email']),
        discountCode: _strOrNull(j['discount_code']),
        history: _list(j['history']).map(OrderEvent.fromJson).toList(),
        signature: _str(_map(j['receipt'])['signature']),
        refundId: _strOrNull(_map(j['payment'])['refund_id']),
      );
}

String orderStatusLabel(String s) => switch (s) {
      'paid' => 'Paid',
      'packed' => 'Packed',
      'shipped' => 'Shipped',
      'delivered' => 'Delivered',
      'cancelled' => 'Cancelled',
      'refunded' => 'Refunded',
      'pending' => 'Pending',
      _ => humanize(s),
    };

// ---------------------------------------------------------------------------------------------
// Matches
// ---------------------------------------------------------------------------------------------

/// One scoring control from the sport config: points (event model), runs / legal ball / wicket
/// (innings model) or rounds (best-of model).
class ScoringEventDef {
  const ScoringEventDef({required this.key, required this.label, required this.value, this.legalBall, this.wicket});

  final String key;
  final String label;
  final int value;
  final bool? legalBall;
  final bool? wicket;

  factory ScoringEventDef.fromJson(Map<String, dynamic> j) => ScoringEventDef(
        key: _str(j['key']),
        label: _str(j['label'], humanize(_str(j['key']))),
        value: _int(j['value']),
        legalBall: j['legal_ball'] as bool?,
        wicket: j['wicket'] as bool?,
      );
}

class ScoringTemplate {
  const ScoringTemplate({required this.model, required this.events, this.periods = const {}, this.drawAllowed = true});

  /// event, innings or round.
  final String model;
  final List<ScoringEventDef> events;
  final Map<String, dynamic> periods;
  final bool drawAllowed;

  int? get bestOf => _intOrNull(periods['best_of']);

  factory ScoringTemplate.fromJson(Map<String, dynamic> j, List<String> fallbackKeys) {
    final events = _list(j['events']).map(ScoringEventDef.fromJson).toList();
    return ScoringTemplate(
      model: _str(j['model'], 'event'),
      events: events.isNotEmpty ? events : [for (final k in fallbackKeys) ScoringEventDef(key: k, label: humanize(k), value: 1)],
      periods: _map(j['periods']),
      drawAllowed: j['draw_allowed'] != false,
    );
  }
}

class SquadPlayer {
  const SquadPlayer({required this.id, required this.name, this.shirt, this.position = ''});

  final String id;
  final String name;
  final int? shirt;
  final String position;

  factory SquadPlayer.fromJson(Map<String, dynamic> j) =>
      SquadPlayer(id: _str(j['player_id']), name: _str(j['name']), shirt: _intOrNull(j['shirt']), position: _str(j['position']));
}

class MatchDetail {
  const MatchDetail({
    required this.fixture,
    required this.sportName,
    required this.timeline,
    required this.canScore,
    this.scoringEvents = const [],
    this.pinned,
    this.scoring = const ScoringTemplate(model: 'event', events: []),
    this.canManage = false,
    this.allowedStatus = const [],
    this.homeSquad = const [],
    this.awaySquad = const [],
    this.tiebreakWinnerId,
  });

  final Fixture fixture;
  final String sportName;
  final List<TimelineEvent> timeline;
  final bool canScore;
  final bool canManage;

  /// Event types from the sport config, e.g. goal, or two_pointer and three_pointer.
  final List<String> scoringEvents;
  final ScoringTemplate scoring;
  final Product? pinned;
  final List<String> allowedStatus;
  final List<SquadPlayer> homeSquad;
  final List<SquadPlayer> awaySquad;
  final String? tiebreakWinnerId;

  factory MatchDetail.fromJson(Map<String, dynamic> j) {
    final keys = _strings(j['scoring_events']);
    final squads = _map(j['squads']);
    return MatchDetail(
      fixture: Fixture.fromJson(j),
      sportName: _str(j['sport_name']),
      timeline: _list(j['timeline']).map(TimelineEvent.fromJson).toList(),
      canScore: j['can_score'] == true,
      canManage: j['can_manage'] == true,
      scoringEvents: keys,
      scoring: ScoringTemplate.fromJson(_map(j['scoring']), keys),
      pinned: j['pinned_product'] is Map<String, dynamic> ? Product.fromJson(j['pinned_product'] as Map<String, dynamic>) : null,
      allowedStatus: _strings(j['allowed_status']),
      homeSquad: _list(squads['home']).map(SquadPlayer.fromJson).toList(),
      awaySquad: _list(squads['away']).map(SquadPlayer.fromJson).toList(),
      tiebreakWinnerId: _strOrNull(j['tiebreak_winner_team_id']),
    );
  }
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
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
  });

  final int rank;
  final String teamId;
  final String teamName;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final num diff;
  final int points;
  final QualStatus status;

  factory StandingRow.fromJson(Map<String, dynamic> j) => StandingRow(
        rank: _int(j['rank']),
        teamId: _str(j['team_id']),
        teamName: _str(j['team_name'], _str(j['team_id'])),
        played: _int(j['played']),
        won: _int(j['won']),
        drawn: _int(j['drawn']),
        lost: _int(j['lost']),
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
  const Standings({required this.leagueId, required this.leagueName, required this.spots, required this.rows, this.format = 'round_robin'});

  final String leagueId;
  final String leagueName;
  final int spots;
  final List<StandingRow> rows;
  final String format;

  bool get isKnockout => format == 'single_elim' || format == 'double_elim';

  factory Standings.fromJson(Map<String, dynamic> j) => Standings(
        leagueId: _str(j['league_id']),
        leagueName: _str(j['league_name']),
        spots: _int(j['qualification_spots']),
        rows: _list(j['table']).map(StandingRow.fromJson).toList(),
        format: _str(j['format'], 'round_robin'),
      );
}

String formatLabel(String f) => switch (f) {
      'round_robin' => 'Round robin',
      'swiss' => 'Swiss system',
      'single_elim' => 'Single elimination',
      'double_elim' => 'Double elimination',
      _ => humanize(f),
    };

class League {
  const League({
    required this.id,
    required this.name,
    required this.sportName,
    required this.fixtureCount,
    this.sportId = '',
    this.season = '',
    this.format = 'round_robin',
    this.status = 'active',
    this.teamCount = 0,
    this.liveCount = 0,
    this.tenantId = '',
    this.description = '',
    this.rules = const [],
    this.organizers = const [],
  });

  final String id;
  final String name;
  final String sportId;
  final String sportName;
  final String season;
  final String format;
  final String status;
  final int fixtureCount;
  final int teamCount;
  final int liveCount;
  final String tenantId;
  final String description;
  final List<String> rules;

  /// Display names of the organizers running it.
  final List<String> organizers;

  factory League.fromJson(Map<String, dynamic> j) => League(
        id: _str(j['league_id']),
        name: _str(j['name']),
        sportId: _str(j['sport_id']),
        sportName: _str(j['sport_name']),
        season: _str(j['season']),
        format: _str(j['format'], 'round_robin'),
        status: _str(j['status'], 'active'),
        fixtureCount: _int(j['fixture_count']),
        teamCount: _int(j['team_count']),
        liveCount: _int(j['live_count']),
        tenantId: _str(j['tenant_id']),
        description: _str(j['description']),
        rules: _strings(j['rules']),
        organizers: _list(j['organizers']).map((o) => _str(o['name'], _str(o['email']))).toList(),
      );
}

class ClubCard {
  const ClubCard({required this.id, required this.name, this.leagueId = '', this.leagueName, this.sportName, this.logoUrl, this.primaryColor, this.venueName, this.rank, this.points});

  final String id;
  final String name;
  final String leagueId;
  final String? leagueName;
  final String? sportName;
  final String? logoUrl;
  final String? primaryColor;
  final String? venueName;
  final int? rank;
  final int? points;

  factory ClubCard.fromJson(Map<String, dynamic> j) {
    final stats = _map(j['stats']);
    return ClubCard(
      id: _str(j['club_id']),
      name: _str(j['name']),
      leagueId: _str(j['league_id']),
      leagueName: _strOrNull(j['league_name']),
      sportName: _strOrNull(j['sport_name']),
      logoUrl: _strOrNull(j['logo_url']),
      primaryColor: _strOrNull(_map(j['colors'])['primary']),
      venueName: _strOrNull(j['venue_name']),
      rank: _intOrNull(stats['rank']),
      points: _intOrNull(stats['points']),
    );
  }
}

class LeagueDetail {
  const LeagueDetail({required this.league, required this.clubs, required this.fixtures, required this.sportRules, this.hasBracket = false, this.hasSwiss = false, this.canManage = false, this.swissRound, this.swissTotal});

  final League league;
  final List<ClubCard> clubs;
  final List<Fixture> fixtures;
  final List<String> sportRules;
  final bool hasBracket;
  final bool hasSwiss;
  final bool canManage;
  final int? swissRound;
  final int? swissTotal;

  factory LeagueDetail.fromJson(Map<String, dynamic> j) {
    final sw = _map(j['swiss']);
    return LeagueDetail(
      league: League.fromJson(j),
      clubs: _list(j['clubs']).map(ClubCard.fromJson).toList(),
      fixtures: _list(j['fixtures']).map(Fixture.fromJson).toList(),
      sportRules: _strings(j['sport_rules']),
      hasBracket: j['has_bracket'] == true,
      hasSwiss: j['has_swiss'] == true,
      canManage: j['can_manage'] == true,
      swissRound: _intOrNull(sw['current_round']),
      swissTotal: _intOrNull(sw['total_rounds']),
    );
  }
}

class BracketMatch {
  const BracketMatch({required this.bracketId, required this.stage, this.home, this.away, this.bye = false, this.winnerId, this.matchId, this.status, this.homeScore, this.awayScore});

  final String bracketId;
  final String stage;
  final String? home;
  final String? away;
  final bool bye;
  final String? winnerId;
  final String? matchId;
  final String? status;
  final int? homeScore;
  final int? awayScore;

  factory BracketMatch.fromJson(Map<String, dynamic> j) {
    final h = _map(j['home']);
    final a = _map(j['away']);
    final s = _map(j['score']);
    return BracketMatch(
      bracketId: _str(j['bracket_match_id']),
      stage: _str(j['stage']),
      home: _strOrNull(h['name']),
      away: _strOrNull(a['name']),
      bye: j['bye'] == true,
      winnerId: _strOrNull(j['winner_team_id']),
      matchId: _strOrNull(j['match_id']),
      status: _strOrNull(j['status']),
      homeScore: _intOrNull(s['home']),
      awayScore: _intOrNull(s['away']),
    );
  }
}

class BracketSection {
  const BracketSection({required this.title, required this.matches});

  final String title;
  final List<BracketMatch> matches;
}

List<BracketSection> parseBracket(Map<String, dynamic> j) => _list(j['sections'])
    .map((s) => BracketSection(title: _str(s['title']), matches: _list(s['matches']).map(BracketMatch.fromJson).toList()))
    .toList();

// ---------------------------------------------------------------------------------------------
// Sports
// ---------------------------------------------------------------------------------------------
class Sport {
  const Sport({
    required this.id,
    required this.name,
    required this.model,
    this.description = '',
    this.icon = 'trophy',
    this.active = true,
    this.demo = false,
    this.rules = const [],
    this.leagueCount = 0,
    this.clubCount = 0,
    this.liveCount = 0,
    this.upcomingCount = 0,
    this.completedCount = 0,
    this.raw = const {},
  });

  final String id;
  final String name;
  final String model;
  final String description;
  final String icon;
  final bool active;
  final bool demo;
  final List<String> rules;
  final int leagueCount;
  final int clubCount;
  final int liveCount;
  final int upcomingCount;
  final int completedCount;

  /// The full config, for the admin editor.
  final Map<String, dynamic> raw;

  String get modelLabel => switch (model) {
        'event' => 'Points per event',
        'innings' => 'Innings (runs, wickets, overs)',
        'round' => 'Best-of series (sets, games, maps)',
        _ => humanize(model),
      };

  factory Sport.fromJson(Map<String, dynamic> j) => Sport(
        id: _str(j['sport_id']),
        name: _str(j['name']),
        model: _str(j['scoring_model']),
        description: _str(j['description']),
        icon: _str(j['icon'], 'trophy'),
        active: j['active'] != false,
        demo: j['demo'] == true,
        rules: _strings(j['rules_summary']),
        leagueCount: _int(j['league_count']),
        clubCount: _int(j['club_count']),
        liveCount: _int(j['live_count']),
        upcomingCount: _int(j['upcoming_count']),
        completedCount: _int(j['completed_count']),
        raw: j,
      );
}

class SportDetail {
  const SportDetail({required this.sport, required this.leagues, required this.live, required this.upcoming, required this.completed, required this.clubs});

  final Sport sport;
  final List<League> leagues;
  final List<Fixture> live;
  final List<Fixture> upcoming;
  final List<Fixture> completed;
  final List<ClubCard> clubs;

  factory SportDetail.fromJson(Map<String, dynamic> j) => SportDetail(
        sport: Sport.fromJson(_map(j['sport'])),
        leagues: _list(j['leagues']).map(League.fromJson).toList(),
        live: _list(j['live']).map(Fixture.fromJson).toList(),
        upcoming: _list(j['upcoming']).map(Fixture.fromJson).toList(),
        completed: _list(j['completed']).map(Fixture.fromJson).toList(),
        clubs: _list(j['clubs']).map(ClubCard.fromJson).toList(),
      );
}

class HomeFeed {
  const HomeFeed({required this.sports, required this.live, required this.upcoming, required this.results, required this.leagues, required this.clubs, required this.featured, required this.fresh});

  final List<Sport> sports;
  final List<Fixture> live;
  final List<Fixture> upcoming;
  final List<Fixture> results;
  final List<League> leagues;
  final List<ClubCard> clubs;
  final List<Product> featured;
  final List<Product> fresh;

  factory HomeFeed.fromJson(Map<String, dynamic> j) => HomeFeed(
        sports: _list(j['sports']).map(Sport.fromJson).toList(),
        live: _list(j['live']).map(Fixture.fromJson).toList(),
        upcoming: _list(j['upcoming']).map(Fixture.fromJson).toList(),
        results: _list(j['results']).map(Fixture.fromJson).toList(),
        leagues: _list(j['leagues']).map(League.fromJson).toList(),
        clubs: _list(j['clubs']).map(ClubCard.fromJson).toList(),
        featured: _list(j['featured_products']).map(Product.fromJson).toList(),
        fresh: _list(j['new_products']).map(Product.fromJson).toList(),
      );
}

class SearchResults {
  const SearchResults({required this.sports, required this.leagues, required this.clubs, required this.players, required this.products});

  final List<Sport> sports;
  final List<League> leagues;
  final List<ClubCard> clubs;
  final List<({String id, String name, String club})> players;
  final List<Product> products;

  bool get isEmpty => sports.isEmpty && leagues.isEmpty && clubs.isEmpty && players.isEmpty && products.isEmpty;

  factory SearchResults.fromJson(Map<String, dynamic> j) => SearchResults(
        sports: _list(j['sports']).map(Sport.fromJson).toList(),
        leagues: _list(j['leagues']).map(League.fromJson).toList(),
        clubs: _list(j['clubs']).map(ClubCard.fromJson).toList(),
        players: _list(j['players']).map((p) => (id: _str(p['player_id']), name: _str(p['name']), club: _str(p['club_name']))).toList(),
        products: _list(j['products']).map(Product.fromJson).toList(),
      );
}

// ---------------------------------------------------------------------------------------------
// Clubs and players
// ---------------------------------------------------------------------------------------------
class RosterPlayer {
  const RosterPlayer({
    required this.id,
    required this.name,
    required this.position,
    required this.role,
    this.shirt,
    this.onLoan = false,
    this.version = 0,
  });

  final String id;
  final String name;
  final String position;
  final String role;
  final int? shirt;
  final bool onLoan;

  /// Audit entry count: the `base_version` for offline roster actions.
  final int version;

  factory RosterPlayer.fromJson(Map<String, dynamic> j) => RosterPlayer(
        id: _str(j['player_id']),
        name: _str(j['name']),
        position: _str(j['position']),
        role: _str(j['role']),
        shirt: _intOrNull(j['shirt']),
        onLoan: j['on_loan'] == true,
        version: _int(j['version']),
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
    required this.leagueId,
    required this.sportName,
    required this.leagueName,
    required this.venueName,
    required this.lat,
    required this.lng,
    required this.social,
    required this.roster,
    required this.staff,
    required this.canManage,
    this.positions = const [],
    this.rank,
    this.played,
    this.points,
    this.won,
    this.drawn,
    this.lost,
    this.description = '',
    this.logoUrl,
    this.primaryColor,
    this.secondaryColor,
    this.leagues = const [],
    this.upcoming = const [],
    this.results = const [],
    this.productCount = 0,
    this.canEdit = false,
    this.canManageStore = false,
    this.canViewHistory = false,
  });

  final String id;
  final String name;
  final String leagueId;
  final String sportName;
  final String leagueName;
  final String venueName;
  final double? lat;
  final double? lng;
  final Map<String, String> social;
  final List<RosterPlayer> roster;
  final List<StaffMember> staff;
  final bool canManage;
  final String description;
  final String? logoUrl;
  final String? primaryColor;
  final String? secondaryColor;
  final List<({String id, String name, String season})> leagues;
  final List<Fixture> upcoming;
  final List<Fixture> results;
  final int productCount;
  final bool canEdit;
  final bool canManageStore;
  final bool canViewHistory;

  /// Required positions from the sport/league roster rules (e.g. gk).
  final List<String> positions;
  final int? rank;
  final int? played;
  final int? points;
  final int? won;
  final int? drawn;
  final int? lost;

  String? get handle => social['x'] ?? social['instagram'] ?? (social.isEmpty ? null : social.values.first);

  factory ClubProfile.fromJson(Map<String, dynamic> j) {
    final venue = _map(j['venue']);
    final social = j['social'] is Map ? (j['social'] as Map).map((k, v) => MapEntry('$k', '$v')) : <String, String>{};
    final stats = j['stats'] is Map<String, dynamic> ? j['stats'] as Map<String, dynamic> : null;
    final colors = _map(j['colors']);
    return ClubProfile(
      id: _str(j['club_id']),
      name: _str(j['name']),
      leagueId: _str(j['league_id']),
      sportName: _str(j['sport_name']),
      leagueName: _str(j['league_name']),
      venueName: _str(venue['name']),
      lat: venue['lat'] is num ? (venue['lat'] as num).toDouble() : null,
      lng: venue['lng'] is num ? (venue['lng'] as num).toDouble() : null,
      social: social,
      roster: _list(j['roster']).map(RosterPlayer.fromJson).toList(),
      staff: _list(j['staff']).map((s) => StaffMember(name: _str(s['name']), role: _str(s['role']))).toList(),
      canManage: j['can_manage'] == true,
      positions: _strings(j['positions']),
      rank: stats == null ? null : _int(stats['rank']),
      played: stats == null ? null : _int(stats['played']),
      points: stats == null ? null : _int(stats['points']),
      won: stats == null ? null : _int(stats['won']),
      drawn: stats == null ? null : _int(stats['drawn']),
      lost: stats == null ? null : _int(stats['lost']),
      description: _str(j['description']),
      logoUrl: _strOrNull(j['logo_url']),
      primaryColor: _strOrNull(colors['primary']),
      secondaryColor: _strOrNull(colors['secondary']),
      leagues: _list(j['leagues']).map((l) => (id: _str(l['league_id']), name: _str(l['name']), season: _str(l['season']))).toList(),
      upcoming: _list(j['upcoming']).map(Fixture.fromJson).toList(),
      results: _list(j['results']).map(Fixture.fromJson).toList(),
      productCount: _int(j['product_count']),
      canEdit: j['can_edit'] == true,
      canManageStore: j['can_manage_store'] == true,
      canViewHistory: j['can_view_history'] == true,
    );
  }
}

class ClubRef {
  const ClubRef({required this.id, required this.name});

  final String id;
  final String name;
}

class RosterChange {
  const RosterChange({required this.action, required this.playerName, required this.when, this.fromClub, this.toClub, this.who = '', this.why = '', this.effectiveDate = '', this.state = 'active'});

  final String action;
  final String playerName;
  final DateTime when;
  final String? fromClub;
  final String? toClub;
  final String who;
  final String why;
  final String effectiveDate;
  final String state;

  String get summary => switch (action) {
        'add' => 'Registered with ${toClub ?? 'the club'}',
        'transfer' => 'Transferred ${fromClub ?? ''} → ${toClub ?? ''}',
        'loan' => 'Loaned ${fromClub ?? ''} → ${toClub ?? ''}',
        'loan_return' => 'Returned from loan to ${toClub ?? ''}',
        'release' => 'Released by ${fromClub ?? 'the club'}',
        _ => humanize(action),
      };

  factory RosterChange.fromJson(Map<String, dynamic> j) => RosterChange(
        action: _str(j['action']),
        playerName: _str(j['player_name'], _str(j['player_id'])),
        when: DateTime.tryParse(_str(j['when']))?.toLocal() ?? DateTime.now(),
        fromClub: _strOrNull(j['from_club_name']) ?? _strOrNull(j['from_squad_id']),
        toClub: _strOrNull(j['to_club_name']) ?? _strOrNull(j['to_squad_id']),
        who: _str(j['who']),
        why: _str(j['why']),
        effectiveDate: _str(j['effective_date']),
        state: _str(j['state'], 'active'),
      );
}

class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.name,
    required this.position,
    required this.role,
    this.shirt,
    this.club,
    this.leagueName,
    this.sportName,
    this.onLoan = false,
    this.loanFrom,
    this.loanEnds,
    this.released = false,
    this.matchesPlayed = 0,
    this.stats = const [],
    this.totalValue = 0,
    this.disciplineEvents = 0,
    this.history,
    this.isMe = false,
  });

  final String id;
  final String name;
  final String position;
  final String role;
  final int? shirt;
  final ClubCard? club;
  final String? leagueName;
  final String? sportName;
  final bool onLoan;
  final String? loanFrom;
  final String? loanEnds;
  final bool released;
  final int matchesPlayed;
  final List<({String label, int count, int value})> stats;
  final int totalValue;
  final int disciplineEvents;

  /// Roster audit trail; null when the viewer may not see it.
  final List<RosterChange>? history;
  final bool isMe;

  factory PlayerProfile.fromJson(Map<String, dynamic> j) {
    final s = _map(j['stats']);
    final loan = _map(j['loan']);
    return PlayerProfile(
      id: _str(j['player_id']),
      name: _str(j['name']),
      position: _str(j['position']),
      role: _str(j['role']),
      shirt: _intOrNull(j['shirt']),
      club: j['club'] is Map<String, dynamic> ? ClubCard.fromJson(j['club'] as Map<String, dynamic>) : null,
      leagueName: _strOrNull(j['league_name']),
      sportName: _strOrNull(j['sport_name']),
      onLoan: j['on_loan'] == true,
      loanFrom: _strOrNull(loan['from_club_name']),
      loanEnds: _strOrNull(loan['ends']),
      released: j['released'] == true,
      matchesPlayed: _int(s['club_matches_played']),
      stats: _list(s['scoring']).map((x) => (label: _str(x['label']), count: _int(x['count']), value: _int(x['value']))).toList(),
      totalValue: _int(s['total_value']),
      disciplineEvents: _int(s['discipline_events']),
      history: j['history'] is List ? _list(j['history']).map(RosterChange.fromJson).toList() : null,
      isMe: j['is_me'] == true,
    );
  }
}

/// `PKR 4500.00`: minor units ÷ 100, two decimals, no thousands separator (UI.md §6.8).
String formatPrice(int minor, [String currency = 'PKR']) => '$currency ${(minor / 100).toStringAsFixed(2)}';

/// "two_pointer" -> "Two pointer": event names come from the sport config, never hard-coded.
String humanize(String key) {
  final s = key.replaceAll('_', ' ').trim();
  return s.isEmpty ? key : s[0].toUpperCase() + s.substring(1);
}
