import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huddle/app.dart';
import 'package:huddle/core/api/api_client.dart';
import 'package:huddle/core/auth/token_store.dart';
import 'package:huddle/core/auth/user.dart';
import 'package:huddle/core/cache/api_cache.dart';
import 'package:huddle/core/cart/cart.dart';
import 'package:huddle/core/widgets/common.dart';
import 'package:huddle/core/widgets/image_upload.dart';
import 'package:huddle/features/match/match_screen.dart';
import 'package:huddle/core/connectivity/connectivity.dart';
import 'package:huddle/core/copy/error_messages.dart';
import 'package:huddle/core/settings/settings.dart';
import 'package:huddle/core/sync/sync_queue.dart';
import 'package:huddle/core/theme/app_theme.dart';
import 'package:huddle/core/theme/status_colors.dart';
import 'package:huddle/core/theme/tenant.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryTokenStore extends TokenStore {
  String? _t;
  AppUser? _u;

  @override
  String? get token => _t;

  @override
  Future<String?> load() async => _t;

  @override
  Future<AppUser?> loadUser() async => _u;

  @override
  Future<void> save(String token, AppUser user) async {
    _t = token;
    _u = user;
  }

  @override
  Future<void> saveUser(AppUser user) async => _u = user;

  @override
  Future<void> clear() async {
    _t = null;
    _u = null;
  }
}

Map<String, dynamic> userJson(String email, String role, String? tenantId, String tenantName) => {
      'user_id': 'user-$role',
      'email': email,
      'name': 'Demo $role',
      'role': role,
      'tenant_id': tenantId,
      'tenant': tenantId == null ? null : {'tenant_id': tenantId, 'name': tenantName, 'logo_url': null, 'colors': {'primary': '#1E5EFF'}},
      'league_ids': role == 'league_organizer' ? ['league-alpha-1'] : <String>[],
      'club_id': role == 'club_manager' || role == 'player' ? 'club-alpha-1' : null,
      'player_id': role == 'player' ? 'player-alpha-1' : null,
      'store_access': role == 'club_manager' || role == 'super_admin',
    };

/// Every request the fake backend received (method + path), for assertions.
final requests = <String>[];

Map<String, dynamic> _order(String id) => {
      'order_id': id,
      'status': 'paid',
      'payment': {'state': 'captured', 'authorization_id': 'auth_1', 'capture_id': 'cap_1', 'refund_id': null},
      'payment_status': 'captured',
      'lines': [
        {'variant_id': 'var-jersey-001-M', 'product_name': 'Alpha Falcons Home Jersey', 'label': 'M · blue', 'quantity': 1, 'unit_price_minor': 450000, 'line_total_minor': 450000},
      ],
      'subtotal_minor': 450000,
      'discount_minor': 0,
      'total_minor': 450000,
      'created_at': _now.toIso8601String(),
      'history': [
        {'to': 'pending', 'at': _now.toIso8601String()},
        {'to': 'paid', 'at': _now.toIso8601String()},
      ],
      'receipt': {'signature': 'a' * 64, 'payload': {'order_id': id}},
    };

/// Mimics the backend for the five demo accounts.
http.Client fakeBackend() => MockClient((req) async {
      requests.add('${req.method} ${req.url.path}');
      Map<String, dynamic> body() => req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
      http.Response json(Object o, [int status = 200]) => http.Response(jsonEncode(o), status, headers: {'content-type': 'application/json'});
      final path = req.url.path;
      if (path == '/api/v1/auth/login') {
        final b = body();
        const roles = {
          'admin@nascon.test': 'super_admin',
          'organizer@nascon.test': 'league_organizer',
          'manager@nascon.test': 'club_manager',
          'player@nascon.test': 'player',
          'viewer@nascon.test': 'viewer',
        };
        final role = roles[b['email']];
        if (role == null || b['password'] != 'Nascon@26') {
          return json({'error': {'code': 'UNAUTHENTICATED', 'message': 'Email or password is incorrect.', 'details': {}}}, 401);
        }
        final admin = role == 'super_admin';
        return json({'token': 'jwt-$role', 'expires_in': 7200, 'user': userJson(b['email'] as String, role, admin ? null : 'tenant-alpha', 'Alpha Sports')});
      }
      if (path == '/api/v1/ping') return json({'pong': true});
      if (path == '/api/v1/sync') {
        final b = body();
        final actions = (b['actions'] as List).cast<Map<String, dynamic>>();
        return json({
          'device_id': b['device_id'],
          'results': [for (final a in actions) {'action_id': a['action_id'], 'status': 'applied', 'resolution': 'appended', 'error_code': null}],
          'summary': {'applied': actions.length, 'rejected': 0, 'duplicate': 0},
        });
      }
      if (req.method == 'POST' && path == '/api/v1/clubs/club-alpha-1/players') {
        return json({'player': {'player_id': 'np'}, 'audit_entry': {'action': 'add'}}, 201);
      }
      if (req.method == 'POST' && path == '/api/v1/cart/quote') {
        final items = (body()['items'] as List).cast<Map<String, dynamic>>();
        final lines = [
          for (final i in items)
            {
              'variant_id': i['variant_id'],
              'product_id': 'prod-jersey-001',
              'product_name': 'Alpha Falcons Home Jersey',
              'club_name': 'Alpha Falcons FC',
              'label': 'M · blue',
              'quantity': i['quantity'],
              'unit_price_minor': 450000,
              'line_total_minor': 450000 * (i['quantity'] as int),
              'available_stock': 1,
              'status': 'ok',
            },
        ];
        final total = lines.fold<int>(0, (n, l) => n + (l['line_total_minor'] as int));
        return json({'lines': lines, 'subtotal_minor': total, 'discount_minor': 0, 'total_minor': total, 'can_checkout': true, 'discount_valid': null});
      }
      if (req.method == 'POST' && path == '/api/v1/checkout') {
        final b = body();
        if ((b['payment'] as Map)['token'] == 'tok_declined') {
          return json({'error': {'code': 'PAYMENT_DECLINED', 'message': 'declined', 'details': {}}}, 402);
        }
        return json({..._order(b['order_id'] as String), 'order': _order(b['order_id'] as String)}, 201);
      }
      if (path.startsWith('/api/v1/orders/') && path.endsWith('/receipt')) {
        return json({'order_id': path.split('/')[4], 'signature_valid': true, 'signature': 'a' * 64, 'payload': {}});
      }
      if (path.startsWith('/api/v1/orders/')) return json(_order(path.split('/')[4]));
      if (req.method == 'POST' && path == '/api/v1/products') {
        final b = body();
        return json({..._product('prod-new', b['name'] as String), 'can_manage': true}, 201);
      }
      if (path == '/api/v1/products/prod-new') return json({..._product('prod-new', 'Falcons Scarf'), 'can_manage': true});
      if (req.method == 'POST' && path == '/api/v1/products/prod-new/images') {
        expect(req.headers['Content-Type'], 'image/png');
        return json({..._product('prod-new', 'Falcons Scarf'), 'can_manage': true}, 201);
      }
      final canned = demoApi[path];
      if (canned != null) return json(canned);
      return json({'error': {'code': 'NOT_FOUND', 'message': 'x', 'details': {}}}, 404);
    });

final _now = DateTime.now().toUtc();
String _at(Duration d) => _now.add(d).toIso8601String();

Map<String, dynamic> _fixture(String id, String status, int hs, int as, Duration at, {String? winner, int? minute}) => {
      'match_id': id,
      'league_id': 'league-alpha-1',
      'league_name': 'Alpha Premier League',
      'sport_id': 'football',
      'sport_name': 'Football',
      'scoring_model': 'event',
      'round': 2,
      'stage': 'Round 2',
      'kickoff_at': _at(at),
      'venue': 'Falcon Ground',
      'status': status,
      'minute': minute,
      'winner_team_id': winner,
      'seeded': true,
      'home': {'team_id': 'club-alpha-1', 'name': 'Alpha Falcons FC', 'score': hs},
      'away': {'team_id': 'club-alpha-3', 'name': 'Alpha Rovers', 'score': as},
    };

Map<String, dynamic> _product(String id, String name) => {
      'product_id': id,
      'name': name,
      'category': 'accessories',
      'category_name': 'Accessories',
      'description': 'Warm.',
      'club_id': 'club-alpha-1',
      'club_name': 'Alpha Falcons FC',
      'active': true,
      'images': <Object>[],
      'image_url': null,
      'variants': [
        {'variant_id': 'var-new-std', 'label': 'Standard', 'price_minor': 150000, 'unit_price_minor': 150000, 'stock': 3, 'sku': 'VAR-NEW', 'active': true},
      ],
    };

final _jersey = {
  'product_id': 'prod-jersey-001',
  'name': 'Alpha Falcons Home Jersey',
  'category': 'apparel',
  'category_name': 'Jerseys & shirts',
  'description': 'Official 2026 home jersey.',
  'club_id': 'club-alpha-1',
  'club_name': 'Alpha Falcons FC',
  'sport_name': 'Football',
  'active': true,
  'images': <Object>[],
  'image_url': null,
  'variants': [
    {'variant_id': 'var-jersey-001-M', 'size': 'M', 'color': 'blue', 'label': 'M · blue', 'price_minor': 450000, 'unit_price_minor': 450000, 'stock': 1, 'sku': 'J-M', 'active': true},
    {'variant_id': 'var-jersey-001-L', 'size': 'L', 'color': 'blue', 'label': 'L · blue', 'price_minor': 450000, 'unit_price_minor': 450000, 'stock': 5, 'sku': 'J-L', 'active': true},
  ],
};

final _league = {
  'league_id': 'league-alpha-1',
  'name': 'Alpha Premier League',
  'sport_id': 'football',
  'sport_name': 'Football',
  'season': '2026',
  'format': 'round_robin',
  'fixture_count': 6,
  'team_count': 4,
  'live_count': 1,
};

/// Canned `/api/v1` responses shaped like the backend's demo seed.
final Map<String, Object> demoApi = {
  '/api/v1/home': {
    'sports': [
      {'sport_id': 'football', 'name': 'Football', 'scoring_model': 'event', 'icon': 'soccer', 'active': true, 'live_count': 1, 'league_count': 1},
      {'sport_id': 'volleyball', 'name': 'Volleyball', 'scoring_model': 'round', 'icon': 'volleyball', 'active': true},
    ],
    'live': [_fixture('demo-live', 'in_progress', 2, 1, const Duration(minutes: -67), minute: 67)],
    'upcoming': [_fixture('demo-next', 'upcoming', 0, 0, const Duration(days: 7))],
    'results': [_fixture('demo-done', 'completed', 2, 1, const Duration(days: -2), winner: 'club-alpha-1')],
    'leagues': [_league],
    'clubs': [
      {'club_id': 'club-alpha-1', 'name': 'Alpha Falcons FC', 'league_name': 'Alpha Premier League', 'sport_name': 'Football', 'stats': {'rank': 1, 'points': 3}},
    ],
    'featured_products': [_jersey],
    'new_products': [_jersey],
  },
  '/api/v1/fixtures': {
    'fixtures': [
      _fixture('demo-done', 'completed', 2, 1, const Duration(days: -2), winner: 'club-alpha-1'),
      _fixture('demo-live', 'in_progress', 2, 1, const Duration(minutes: -67), minute: 67),
      _fixture('demo-next', 'upcoming', 0, 0, const Duration(days: 7)),
    ],
  },
  '/api/v1/matches/demo-live': {
    ..._fixture('demo-live', 'in_progress', 2, 1, const Duration(minutes: -67), minute: 67),
    'can_score': true,
    'can_manage': true,
    'version': 7,
    'scoring_events': ['goal'],
    'scoring': {
      'model': 'event',
      'periods': {'count': 2, 'duration_minutes': 45},
      'draw_allowed': true,
      'events': [
        {'key': 'goal', 'label': 'Goal', 'value': 1},
      ],
    },
    'allowed_status': ['abandoned', 'completed'],
    'squads': {'home': <Object>[], 'away': <Object>[]},
    'timeline': [
      {'event_id': 'e1', 'type': 'match_start', 'label': 'Kick-off', 'compensated': false},
      {'event_id': 'e2', 'type': 'score', 'label': 'Goal', 'minute': 9, 'team_name': 'Alpha Falcons FC', 'compensated': false},
      {'event_id': 'e3', 'type': 'score', 'label': 'Goal', 'minute': 23, 'team_name': 'Alpha Rovers', 'compensated': true},
    ],
    'pinned_product': _jersey,
  },
  '/api/v1/leagues': {
    'leagues': [_league],
  },
  '/api/v1/standings/league-alpha-1': {
    'league_id': 'league-alpha-1',
    'league_name': 'Alpha Premier League',
    'qualification_spots': 2,
    'format': 'round_robin',
    'table': [
      for (final (i, t) in ['Alpha Falcons FC', 'Alpha Rovers', 'Alpha United', 'Alpha Lions FC'].indexed)
        {'rank': i + 1, 'team_id': 'c$i', 'team_name': t, 'played': 1, 'diff': 1 - i, 'points': 3 - i, 'status': i == 3 ? 'eliminated' : 'still_possible'},
    ],
  },
  '/api/v1/clubs': {
    'clubs': [
      {'club_id': 'club-alpha-1', 'name': 'Alpha Falcons FC', 'league_id': 'league-alpha-1'},
      {'club_id': 'club-alpha-2', 'name': 'Alpha Lions FC', 'league_id': 'league-alpha-1'},
    ],
  },
  '/api/v1/clubs/club-alpha-1': {
    'club_id': 'club-alpha-1',
    'name': 'Alpha Falcons FC',
    'sport_name': 'Football',
    'league_id': 'league-alpha-1',
    'league_name': 'Alpha Premier League',
    'description': 'Founded in 1998.',
    'colors': {'primary': '#1D4ED8', 'secondary': '#FFFFFF'},
    'venue': {'name': 'Falcon Ground', 'lat': 33.6844, 'lng': 73.0479},
    'social': {'x': '@alphafalcons'},
    'staff': [
      {'name': 'Imran Qureshi', 'role': 'coach'},
    ],
    'roster': [
      {'player_id': 'p1', 'name': 'Ali Raza', 'position': 'gk', 'role': 'captain', 'shirt': 1},
      {'player_id': 'p2', 'name': 'Zain Khan', 'position': 'df', 'role': 'vice_captain', 'shirt': 2},
    ],
    'stats': {'rank': 1, 'played': 1, 'won': 1, 'drawn': 0, 'lost': 0, 'points': 3},
    'leagues': [
      {'league_id': 'league-alpha-1', 'name': 'Alpha Premier League', 'season': '2026'},
    ],
    'can_manage': true,
    'can_edit': true,
    'can_view_history': true,
    'positions': ['gk'],
  },
  '/api/v1/products': {
    'products': [_jersey],
    'facets': {
      'sizes': ['M', 'L'],
      'colors': ['blue'],
      'categories': [
        {'category_id': 'apparel', 'name': 'Jerseys & shirts'},
      ],
      'clubs': [
        {'club_id': 'club-alpha-1', 'name': 'Alpha Falcons FC'},
      ],
      'sports': <Object>[],
    },
  },
  '/api/v1/products/prod-jersey-001': _jersey,
  '/api/v1/store/categories': {
    'categories': [
      {'category_id': 'apparel', 'name': 'Jerseys & shirts'},
      {'category_id': 'accessories', 'name': 'Accessories'},
    ],
  },
  '/api/v1/orders': {
    'orders': <Object>[],
  },
  '/api/v1/dashboard/manager': {
    'club': {'club_id': 'club-alpha-1', 'name': 'Alpha Falcons FC', 'league_name': 'Alpha Premier League', 'stats': {'rank': 1, 'points': 3}},
    'squad': {
      'size': 10,
      'max': 25,
      'on_loan': 0,
      'positions': [
        {'position': 'gk', 'required': 1, 'have': 2},
      ],
      'transfer_window': {'open': '2026-09-01', 'close': '2026-12-31'},
    },
    'upcoming': <Object>[],
    'results': <Object>[],
    'live': <Object>[],
    'store_access': true,
    'store': {'products': 1, 'orders': 0, 'open_orders': 0, 'revenue_minor': 0, 'low_stock': <Object>[]},
    'roster_changes': <Object>[],
  },
  '/api/v1/admin/dashboard': {
    'tenants': 2,
    'sports': {'total': 9, 'active': 9},
    'leagues': 4,
    'clubs': 12,
    'players': 100,
    'fixtures': {'in_progress': 2},
    'orders': {'count': 0, 'revenue_minor': 0},
    'low_stock': 3,
    'recent_activity': <Object>[],
  },
};

/// A real 1x1 PNG, returned by the fake photo picker.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x60, 0x00, 0x00, 0x00,
  0x02, 0x00, 0x01, 0x54, 0xa2, 0x4f, 0x5d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

void main() {
  late Box<String> box;
  late Box<String> cache;
  late Box<String> cart;
  var cartSeq = 0;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('huddle_test').path);
    box = await Hive.openBox<String>(syncBoxName);
    cache = await Hive.openBox<String>(cacheBoxName);
  });

  Future<void> pumpApp(WidgetTester tester, {Box<String>? queueBox, bool online = true}) async {
    // The LIVE dot pulses forever; with animations off it is static, so pumpAndSettle can settle.
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Unmount the previous app first: a new ProviderScope must not inherit the old container.
    await tester.pumpWidget(const SizedBox.shrink());
    // A fresh cart box per app start, so one test's pending disk writes never block the next.
    cart = (await tester.runAsync(() => Hive.openBox<String>('${cartBoxName}_${cartSeq++}')))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          syncBoxProvider.overrideWithValue(queueBox ?? box),
          cacheBoxProvider.overrideWithValue(cache),
          cartBoxProvider.overrideWithValue(cart),
          // SSE: a stream that stays open and silent.
          sseClientFactoryProvider.overrideWithValue(
            () => MockClient.streaming((req, _) async => http.StreamedResponse(StreamController<List<int>>().stream, 200)),
          ),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          httpClientProvider.overrideWithValue(fakeBackend()),
          deviceOnlineProvider.overrideWith((ref) => Stream.value(online)),
          imagePickerProvider.overrideWithValue(() async => PickedImage(_png, 'image/png', 'scarf.png')),
        ],
        child: const HuddleApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, String email, String password) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.ensureVisible(find.text('Sign in').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text, {bool last = false}) async {
    final f = last ? find.text(text).last : find.text(text);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> signOut(WidgetTester tester) async {
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(tester, 'Sign out');
    await tapText(tester, 'Sign out', last: true);
  }

  Future<void> waitForFinder(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(f, findsWidgets);
  }

  /// Lets queued Hive writes (real disk IO) finish between frames until [text] shows.
  Future<void> waitFor(WidgetTester tester, String text) async {
    for (var i = 0; i < 40 && find.text(text).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(text), findsOneWidget);
  }

  setUp(requests.clear);

  test('every documented error code has a plain-language message', () {
    for (final code in ['UNAUTHENTICATED', 'FORBIDDEN', 'OUT_OF_STOCK', 'SQUAD_FULL', 'RATE_LIMITED', 'SCHEDULE_CONFLICT', 'UNSUPPORTED_IMAGE_TYPE', 'MATCH_NOT_PLAYABLE']) {
      expect(messageFor(code, status: 409), errorMessages[code]);
    }
    expect(messageFor('SOMETHING_NEW', status: 503), networkErrorMessage);
    expect(messageFor(null), networkErrorMessage);
    expect(messageFor('PLAYER_NOT_FOUND', status: 404), isNot(contains('PLAYER_NOT_FOUND')));
  });

  test('themes build for both tenants in both modes, with exact brand overrides', () {
    for (final b in Brightness.values) {
      for (final t in [TenantBrand.alpha, TenantBrand.beta]) {
        final theme = buildTheme(b, t);
        expect(theme.colorScheme.primary, t.brand(b));
        expect(theme.extension<StatusColors>(), isNotNull);
      }
    }
    expect(TenantBrand.beta.brandLight, const Color(0xFF0F766E));
    expect(initialsOf('Alpha Falcons FC'), 'AFF');
    expect(initialsOf('Alpha Sports', max: 2), 'AS');
    // An admin-customised brand replaces the built-in one.
    final custom = TenantBrand.fromTenant(const Tenant(id: 'tenant-alpha', name: 'Alpha', primaryColor: '#B91C1C', custom: true));
    expect(custom.brandLight, isNot(TenantBrand.alpha.brandLight));
  });

  test('photos are checked before upload', () {
    expect(checkImage(PickedImage(_png, 'image/png', 'a.png')), isNull);
    expect(checkImage(PickedImage(Uint8List(10), 'image/gif', 'a.gif')), contains('JPEG'));
    expect(checkImage(PickedImage(Uint8List(maxImageBytes + 1), 'image/jpeg', 'big.jpg')), contains('under 5 MB'));
    expect(contentTypeFor('photo.JPG', null), 'image/jpeg');
  });

  testWidgets('login shows the powered-by footer and lands a club manager on Home', (tester) async {
    await pumpApp(tester);
    expect(find.text('powered by'), findsOneWidget);
    expect(find.text('Online · all changes synced'), findsOneWidget);

    await signIn(tester, 'manager@nascon.test', 'Nascon@26');
    expect(find.text('Hi, Demo'), findsOneWidget);
    for (final tab in ['Home', 'Fixtures', 'Standings', 'Store', 'Profile']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('Club manager'), findsOneWidget);
    expect(find.text('Alpha Sports'), findsOneWidget);
    expect(find.text('My club: roster, store and orders'), findsOneWidget);
    expect(find.text('Platform admin'), findsNothing);
  });

  testWidgets('wrong password shows a plain message, never the code', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'viewer@nascon.test', 'wrong');
    expect(find.text(badCredentialsMessage), findsOneWidget);
    expect(find.textContaining('UNAUTHENTICATED'), findsNothing);
  });

  testWidgets('empty fields are explained under the fields', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('every tab opens for the super admin, the admin dashboard works, sign out returns to login', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'admin@nascon.test', 'Nascon@26');
    expect(find.text('Super admin'), findsOneWidget);
    await tapText(tester, 'Platform admin');
    expect(find.text('Sports and scoring rules'), findsOneWidget);
    expect(find.text('Users and roles'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    for (final tab in ['Fixtures', 'Standings', 'Store', 'Profile']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    await signOut(tester);
    expect(find.text('powered by'), findsOneWidget);
  });

  testWidgets('viewers never see staff tools', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'viewer@nascon.test', 'Nascon@26');
    expect(find.text('Platform admin'), findsNothing);
    expect(find.text('My club: roster, store and orders'), findsNothing);
    await tester.tap(find.text('Store').last);
    await tester.pumpAndSettle();
    expect(find.text('Manage'), findsNothing);
  });

  testWidgets('360x640 at 1.3x text and landscape: no overflow on login, home and profile', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final size in const [Size(1080, 1920), Size(1920, 1080)]) {
      tester.view.physicalSize = size;
      await pumpApp(tester);
      await signIn(tester, 'player@nascon.test', 'Nascon@26');
      if (size.height > size.width) expect(find.text('My player profile and stats'), findsOneWidget);
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).first);
      await tapText(tester, 'Sign out');
      expect(find.text('Sign out?'), findsOneWidget);
      await tapText(tester, 'Sign out', last: true);
      expect(find.text('powered by'), findsOneWidget);
    }
  });

  testWidgets('fixtures, match detail, product page, standings and club render the demo data', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'manager@nascon.test', 'Nascon@26');
    await tester.tap(find.text('Fixtures').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('TODAY · '), findsOneWidget);
    expect(find.text('FT'), findsOneWidget);
    expect(find.text('LIVE'), findsWidgets);
    await tester.tap(find.text('Results'));
    await tester.pumpAndSettle();
    expect(find.text('FT'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    await tapText(tester, "67'");
    expect(find.text('2 : 1'), findsOneWidget);
    expect(find.text("LIVE 67'"), findsOneWidget);
    expect(find.text('Disallowed'), findsOneWidget);
    expect(find.text('Demo match from the seed data'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Buy'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(tester, 'Buy');
    expect(find.text('Last one!'), findsOneWidget);
    expect(find.text('Add to cart'), findsOneWidget);
    await tapText(tester, 'L');
    expect(find.text('5 in stock'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standings').last);
    await tester.pumpAndSettle();
    expect(find.text('Top 2 qualify for the playoffs'), findsOneWidget);
    expect(find.text('Eliminated'), findsOneWidget);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ClubTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ClubTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Football · @alphafalcons'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('VC'), findsOneWidget);
    expect(find.text('Manage roster'), findsOneWidget);
    expect(find.text('Roster history'), findsOneWidget);
  });

  testWidgets('buy a shirt: product page → cart → mock checkout → signed receipt', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'viewer@nascon.test', 'Nascon@26');
    await tester.tap(find.text('Store').last);
    await tester.pumpAndSettle();
    expect(find.text('PKR 4500.00'), findsOneWidget);
    await tapText(tester, 'Alpha Falcons Home Jersey');
    await tapText(tester, 'Add to cart');
    await waitForFinder(tester, find.textContaining('Added to cart'));
    await tester.tap(find.byTooltip('Cart'));
    await tester.pumpAndSettle();
    expect(find.text('Your cart'), findsOneWidget);
    expect(find.text('Checkout · PKR 4500.00'), findsOneWidget);
    await tapText(tester, 'Checkout · PKR 4500.00');
    expect(find.text('Mock Visa •••• 4242'), findsOneWidget);

    // A declined test card explains itself and keeps the cart.
    await tapText(tester, 'Mock card •••• 0002');
    await tapText(tester, 'Pay PKR 4500.00');
    await tapText(tester, 'Pay', last: true);
    expect(find.text(errorMessages['PAYMENT_DECLINED']!), findsOneWidget);

    await tapText(tester, 'Mock Visa •••• 4242');
    await tapText(tester, 'Pay PKR 4500.00');
    await tester.tap(find.text('Pay').last);
    await waitFor(tester, 'Thank you for your order');
    await tester.pumpAndSettle();
    expect(find.text('Signature verified by the server (HMAC-SHA256)'), findsOneWidget);
    expect(find.text('Open PDF receipt'), findsOneWidget);
    final checkouts = requests.where((r) => r == 'POST /api/v1/checkout').length;
    expect(checkouts, 2);
    expect(cart.isEmpty, isTrue);
  });

  testWidgets('every data screen fits 360x640 at 1.3x text and in landscape', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final size in const [Size(1080, 1920), Size(1920, 1080)]) {
      tester.view.physicalSize = size;
      await pumpApp(tester);
      await signIn(tester, 'manager@nascon.test', 'Nascon@26');
      await tester.tap(find.text('Fixtures').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text("67'"), 150, scrollable: find.byType(Scrollable).first);
      await tapText(tester, "67'");
      expect(find.text('2 : 1'), findsOneWidget);
      await tester.tap(find.text('Line-ups'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      for (final tab in ['Standings', 'Store']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(find.text('Alpha Falcons Home Jersey'), 150, scrollable: find.byType(Scrollable).first);
      await tapText(tester, 'Alpha Falcons Home Jersey');
      expect(find.text('Add to cart'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('My club: roster, store and orders'), 100, scrollable: find.byType(Scrollable).first);
      await tapText(tester, 'My club: roster, store and orders');
      expect(find.text('Manage roster: add, transfer, loan, release'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await signOut(tester);
    }
  });

  testWidgets('organizer adds a goal from match detail and it syncs at once', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'organizer@nascon.test', 'Nascon@26');
    await tapText(tester, "67'");
    expect(find.text('Score entry'), findsOneWidget);
    expect(find.text('Match control'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget); // only the goal that still counts
    await tapText(tester, '+ Goal');
    expect(find.text('Add goal?'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await waitFor(tester, 'Applied: Goal for Alpha Falcons FC');
    expect(requests, contains('POST /api/v1/sync'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1700)));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('offline score entry is saved on the phone and shown as waiting', (tester) async {
    final fresh = (await tester.runAsync(() => Hive.openBox<String>('sync_queue_offline')))!;
    await pumpApp(tester, queueBox: fresh, online: false);
    await signIn(tester, 'organizer@nascon.test', 'Nascon@26');
    await tapText(tester, "67'");
    await tapText(tester, '+ Goal');
    await tester.tap(find.text('Add'));
    await waitFor(tester, "Saved offline: Goal for Alpha Falcons FC. It will sync when you're back online.");
    expect(requests, isNot(contains('POST /api/v1/sync')));
    expect(fresh.length, 1, reason: 'the action survives a restart because it is in Hive');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('club manager adds a player from the club workspace', (tester) async {
    // A fresh queue box: writes left by earlier tests' fake clocks must not block this one.
    final fresh = (await tester.runAsync(() => Hive.openBox<String>('sync_queue_add_player')))!;
    await pumpApp(tester, queueBox: fresh);
    await signIn(tester, 'manager@nascon.test', 'Nascon@26');
    await tapText(tester, 'My club: roster, store and orders');
    await tapText(tester, 'Manage roster: add, transfer, loan, release');
    await tapText(tester, 'Add player');
    await tester.enterText(find.byType(TextField).first, 'New Signing');
    await tapText(tester, 'Other…');
    await tester.enterText(find.byType(TextField).last, 'fw');
    await tapText(tester, 'Review new player');
    expect(find.text('Add New Signing to Alpha Falcons FC?'), findsOneWidget);
    await tester.tap(find.text('Add player').last);
    await waitFor(tester, 'Applied: Add New Signing to Alpha Falcons FC');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1700)));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('club manager creates a product and uploads a photo', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'manager@nascon.test', 'Nascon@26');
    await tester.tap(find.text('Store').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Manage');
    await tapText(tester, 'New product');
    await tester.enterText(find.byType(TextField).at(0), 'Falcons Scarf');
    await tester.enterText(find.byType(TextField).at(2), '1500');
    await tapText(tester, 'Category');
    await tapText(tester, 'Accessories', last: true);
    await tapText(tester, 'Create product');
    expect(requests, contains('POST /api/v1/products'));
    expect(find.text('Edit product'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Add photo'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(tester, 'Add photo');
    expect(find.textContaining('scarf.png'), findsOneWidget);
    await tapText(tester, 'Upload');
    await waitFor(tester, 'Photo uploaded.');
    expect(requests, contains('POST /api/v1/products/prod-new/images'));
  });
}
