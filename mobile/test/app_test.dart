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
      return http.Response(jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'x', 'details': {}}}), 404);
    });

void main() {
  late Box<String> box;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('huddle_test').path);
    box = await Hive.openBox<String>(syncBoxName);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          syncBoxProvider.overrideWithValue(box),
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
}
