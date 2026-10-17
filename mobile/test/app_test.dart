import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      'league_ids': <String>[],
      'club_id': null,
      'player_id': null,
    };

/// Mimics `POST /api/v1/auth/login` for the five demo accounts.
http.Client fakeBackend() => MockClient((req) async {
      if (req.url.path == '/api/v1/auth/login') {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        const roles = {
          'admin@nascon.test': 'super_admin',
          'organizer@nascon.test': 'league_organizer',
          'manager@nascon.test': 'club_manager',
          'player@nascon.test': 'player',
          'viewer@nascon.test': 'viewer',
        };
        final role = roles[b['email']];
        if (role == null || b['password'] != 'Nascon@26') {
          return http.Response(
            jsonEncode({'error': {'code': 'UNAUTHENTICATED', 'message': 'Email or password is incorrect.', 'details': {}}}),
            401,
          );
        }
        final admin = role == 'super_admin';
        return http.Response(
          jsonEncode({
            'token': 'jwt-$role',
            'expires_in': 7200,
            'user': userJson(b['email'] as String, role, admin ? null : 'tenant-alpha', 'Alpha Sports'),
          }),
          200,
        );
      }
      if (req.url.path == '/api/v1/ping') return http.Response('{"pong":true}', 200);
      if (req.url.path == '/audit/v1/offline-sync') {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        final actions = (b['actions'] as List).cast<Map<String, dynamic>>();
        return http.Response(
          jsonEncode({
            'device_id': b['device_id'],
            'results': [
              for (final a in actions)
                {'action_id': a['action_id'], 'status': 'applied', 'resolution': 'appended', 'error_code': null},
            ],
            'summary': {'applied': actions.length, 'rejected': 0, 'duplicate': 0},
          }),
          200,
        );
      }
      if (req.method == 'POST' && req.url.path == '/api/v1/clubs/club-alpha-1/players') {
        return http.Response(jsonEncode({'player': {'player_id': 'np'}, 'audit_entry': {'action': 'add'}}), 201);
      }
      final canned = demoApi[req.url.path];
      if (canned != null) return http.Response(jsonEncode(canned), 200);
      return http.Response(jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'x', 'details': {}}}), 404);
    });

final _now = DateTime.now().toUtc();
String _at(Duration d) => _now.add(d).toIso8601String();

Map<String, dynamic> _fixture(String id, String status, int hs, int as, Duration at, {String? winner, int? minute}) => {
      'match_id': id,
      'league_id': 'league-alpha-1',
      'league_name': 'Alpha Premier League',
      'sport_id': 'football',
      'round': 2,
      'kickoff_at': _at(at),
      'venue': 'Falcon Ground',
      'status': status,
      'minute': minute,
      'winner_team_id': winner,
      'home': {'team_id': 'club-alpha-1', 'name': 'Alpha Falcons FC', 'score': hs},
      'away': {'team_id': 'club-alpha-3', 'name': 'Alpha Rovers', 'score': as},
    };

final _jersey = {
  'product_id': 'prod-jersey-001',
  'name': 'Alpha Falcons Home Jersey',
  'category': 'apparel',
  'description': 'Official 2026 home jersey.',
  'club_name': 'Alpha Falcons FC',
  'variants': [
    {'variant_id': 'var-jersey-001-M', 'size': 'M', 'color': 'blue', 'price_minor': 450000, 'stock': 1},
    {'variant_id': 'var-jersey-001-L', 'size': 'L', 'color': 'blue', 'price_minor': 450000, 'stock': 5},
  ],
};

/// Canned `/api/v1` responses shaped like the backend's demo seed.
final Map<String, Object> demoApi = {
  '/api/v1/fixtures': {
    'fixtures': [
      _fixture('demo-done', 'completed', 2, 1, const Duration(days: -2), winner: 'club-alpha-1'),
      _fixture('demo-live', 'in_progress', 2, 1, const Duration(minutes: -67), minute: 67),
      _fixture('demo-next', 'upcoming', 0, 0, const Duration(days: 7)),
    ],
  },
  '/api/v1/matches/demo-live': {
    ..._fixture('demo-live', 'in_progress', 2, 1, const Duration(minutes: -67), minute: 67),
    'sport_name': 'Football',
    'can_score': true,
    'version': 7,
    'scoring_events': ['goal'],
    'timeline': [
      {'event_id': 'e1', 'type': 'match_start', 'label': 'Kick-off', 'compensated': false},
      {'event_id': 'e2', 'type': 'score', 'label': 'Goal', 'minute': 9, 'team_name': 'Alpha Falcons FC', 'compensated': false},
      {'event_id': 'e3', 'type': 'score', 'label': 'Goal', 'minute': 23, 'team_name': 'Alpha Rovers', 'compensated': true},
    ],
    'pinned_product': _jersey,
  },
  '/api/v1/leagues': {
    'leagues': [
      {'league_id': 'league-alpha-1', 'name': 'Alpha Premier League', 'sport_name': 'Football', 'fixture_count': 6},
    ],
  },
  '/api/v1/standings/league-alpha-1': {
    'league_id': 'league-alpha-1',
    'league_name': 'Alpha Premier League',
    'qualification_spots': 2,
    'table': [
      for (final (i, t) in ['Alpha Falcons FC', 'Alpha Rovers', 'Alpha United', 'Alpha Lions FC'].indexed)
        {'rank': i + 1, 'team_id': 'c$i', 'team_name': t, 'played': 1, 'diff': 1 - i, 'points': 3 - i, 'status': i == 3 ? 'eliminated' : 'still_possible'},
    ],
  },
  '/api/v1/clubs': {
    'clubs': [
      {'club_id': 'club-alpha-1', 'name': 'Alpha Falcons FC'},
    ],
  },
  '/api/v1/clubs/club-alpha-1': {
    'club_id': 'club-alpha-1',
    'name': 'Alpha Falcons FC',
    'sport_name': 'Football',
    'league_name': 'Alpha Premier League',
    'venue': {'name': 'Falcon Ground', 'lat': 33.6844, 'lng': 73.0479},
    'social': {'x': '@alphafalcons'},
    'staff': [
      {'name': 'Imran Qureshi', 'role': 'coach'},
    ],
    'roster': [
      {'player_id': 'p1', 'name': 'Ali Raza', 'position': 'gk', 'role': 'captain', 'shirt': 1},
      {'player_id': 'p2', 'name': 'Zain Khan', 'position': 'df', 'role': 'vice_captain', 'shirt': 2},
    ],
    'stats': {'rank': 1, 'played': 1, 'points': 3},
    'can_manage': true,
    'positions': ['gk'],
  },
  '/api/v1/catalogue': {
    'products': [_jersey],
  },
};

void main() {
  late Box<String> box;
  late Box<String> cache;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('huddle_test').path);
    box = await Hive.openBox<String>(syncBoxName);
    cache = await Hive.openBox<String>(cacheBoxName);
  });

  Future<void> pumpApp(WidgetTester tester, {Box<String>? queueBox}) async {
    // The LIVE dot pulses forever; with animations off it is static, so pumpAndSettle can settle.
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          syncBoxProvider.overrideWithValue(queueBox ?? box),
          cacheBoxProvider.overrideWithValue(cache),
          // SSE: a stream that stays open and silent.
          sseClientFactoryProvider.overrideWithValue(
            () => MockClient.streaming((req, _) async => http.StreamedResponse(StreamController<List<int>>().stream, 200)),
          ),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          httpClientProvider.overrideWithValue(fakeBackend()),
          deviceOnlineProvider.overrideWith((ref) => Stream.value(true)),
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

  test('every documented error code has a plain-language message', () {
    for (final code in ['UNAUTHENTICATED', 'FORBIDDEN', 'OUT_OF_STOCK', 'SQUAD_FULL', 'RATE_LIMITED']) {
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
  });

  testWidgets('login shows the powered-by footer and signs in a club manager', (tester) async {
    await pumpApp(tester);
    expect(find.text('powered by'), findsOneWidget);
    expect(find.text('Online · all changes synced'), findsOneWidget);

    await signIn(tester, 'manager@nascon.test', 'Nascon@26');
    expect(find.text('Fixtures'), findsWidgets);
    expect(find.text('Club manager'), findsOneWidget);
    expect(find.text('Alpha Sports'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
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

  testWidgets('every tab opens for the super admin and sign out returns to login', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'admin@nascon.test', 'Nascon@26');
    expect(find.text('Super admin'), findsOneWidget);
    for (final tab in ['Standings', 'Store', 'Club', 'Profile']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();
    expect(find.text('powered by'), findsOneWidget);
  });

  testWidgets('360x640 at 1.3x text and landscape: no overflow on login and profile', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final size in const [Size(1080, 1920), Size(1920, 1080)]) {
      tester.view.physicalSize = size;
      await pumpApp(tester);
      await signIn(tester, 'player@nascon.test', 'Nascon@26');
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('Player'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign out').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      expect(find.text('powered by'), findsOneWidget);
    }
  });

  testWidgets('fixtures, match detail, standings, club and store render the demo data', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'manager@nascon.test', 'Nascon@26');

    expect(find.textContaining('TODAY · '), findsOneWidget);
    expect(find.text('FT'), findsOneWidget);
    expect(find.text('LIVE'), findsWidgets);
    await tester.tap(find.text('Results'));
    await tester.pumpAndSettle();
    expect(find.text('FT'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text("67'"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("67'"));
    await tester.pumpAndSettle();
    expect(find.text('2 : 1'), findsOneWidget);
    expect(find.text("LIVE 67'"), findsOneWidget);
    expect(find.text('Disallowed'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Buy'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    expect(find.text('Pay with mock card · PKR 4500.00'), findsOneWidget);
    expect(find.text('Last one!'), findsOneWidget);
    Navigator.of(tester.element(find.text('Pay with mock card · PKR 4500.00'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standings').last);
    await tester.pumpAndSettle();
    expect(find.text('Top 2 qualify for the playoffs'), findsOneWidget);
    expect(find.text('Eliminated'), findsOneWidget);

    await tester.tap(find.text('Club').last);
    await tester.pumpAndSettle();
    expect(find.text('Football · @alphafalcons'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('VC'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);

    await tester.tap(find.text('Store').last);
    await tester.pumpAndSettle();
    expect(find.text('Alpha Falcons Home Jersey'), findsOneWidget);
    expect(find.text('PKR 4500.00'), findsOneWidget);
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
      await tester.scrollUntilVisible(find.text("67'"), 150, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text("67'"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("67'"));
      await tester.pumpAndSettle();
      expect(find.text('2 : 1'), findsOneWidget);
      await tester.tap(find.text('Line-ups'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      for (final tab in ['Standings', 'Club', 'Store']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Alpha Falcons Home Jersey'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha Falcons Home Jersey'));
      await tester.pumpAndSettle();
      expect(find.text('Pay with mock card · PKR 4500.00'), findsOneWidget);
      Navigator.of(tester.element(find.text('Pay with mock card · PKR 4500.00'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign out').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('organizer adds a goal from match detail and it syncs at once', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'organizer@nascon.test', 'Nascon@26');
    await tester.ensureVisible(find.text("67'"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("67'"));
    await tester.pumpAndSettle();
    expect(find.text('Score entry'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget); // only the goal that still counts
    await tester.tap(find.text('+ Goal'));
    await tester.pumpAndSettle();
    expect(find.text('Add goal?'), findsOneWidget);
    await tester.tap(find.text('Add'));
    // The queue writes to Hive (real disk IO), so let real time pass between frames.
    for (var i = 0; i < 40 && find.text('Applied: Goal for Alpha Falcons FC').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Applied: Goal for Alpha Falcons FC'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1700)));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('club manager adds a player from Manage', (tester) async {
    // A fresh queue box: writes left by earlier tests' fake clocks must not block this one.
    final fresh = (await tester.runAsync(() => Hive.openBox<String>('sync_queue_add_player')))!;
    await pumpApp(tester, queueBox: fresh);
    await signIn(tester, 'manager@nascon.test', 'Nascon@26');
    await tester.tap(find.text('Club').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add player'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'New Signing');
    await tester.tap(find.text('Other…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'fw');
    await tester.ensureVisible(find.text('Review new player'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review new player'));
    await tester.pumpAndSettle();
    expect(find.text('Add New Signing to Alpha Falcons FC?'), findsOneWidget);
    await tester.tap(find.text('Add player').last);
    for (var i = 0; i < 40 && find.text('Applied: Add New Signing to Alpha Falcons FC').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Applied: Add New Signing to Alpha Falcons FC'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1700)));
    await tester.pump(const Duration(seconds: 5));
  });
}
