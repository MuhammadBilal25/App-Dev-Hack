// P0 flows from the official spec: the Section 8.4 offline desk check and the Section 8.2 cart.
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
import 'package:huddle/core/cache/api_cache.dart';
import 'package:huddle/core/connectivity/connectivity.dart';
import 'package:huddle/core/settings/settings.dart';
import 'package:huddle/core/sync/sync_queue.dart';
import 'package:huddle/data/models.dart';
import 'package:huddle/features/match/match_screen.dart';
import 'package:huddle/features/store/cart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart' show MemoryTokenStore, fakeBackend;

/// The canned backend of app_test.dart behind a switchable network, plus a recorded,
/// configurable offline-sync and checkout.
class Backend {
  bool online = true;
  String syncResult = 'applied';
  String? checkoutError;
  final syncBodies = <Map<String, dynamic>>[];
  final checkoutBodies = <Map<String, dynamic>>[];
  final paths = <String>[];
  final _inner = fakeBackend();

  http.Client client() => MockClient((req) async {
        if (!online) throw http.ClientException('Network is unreachable');
        paths.add(req.url.path);
        if (req.url.path == '/audit/v1/offline-sync') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          syncBodies.add(b);
          final rejected = syncResult == 'rejected';
          return http.Response(
            jsonEncode({
              'device_id': b['device_id'],
              'results': [
                for (final a in (b['actions'] as List).cast<Map<String, dynamic>>())
                  {
                    'action_id': a['action_id'],
                    'status': syncResult,
                    'resolution': rejected ? 'server_wins' : 'appended',
                    'error_code': rejected ? 'MATCH_NOT_IN_PROGRESS' : null,
                  },
              ],
            }),
            200,
          );
        }
        if (req.url.path == '/audit/v1/checkout') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          checkoutBodies.add(b);
          if (checkoutError != null) {
            return http.Response(jsonEncode({'error': {'code': checkoutError, 'message': 'x', 'details': {}}}), 409);
          }
          final items = [
            for (final it in (b['items'] as List).cast<Map<String, dynamic>>()) {...it, 'unit_price_minor': 450000},
          ];
          final subtotal = items.fold<int>(0, (n, it) => n + 450000 * (it['quantity'] as int));
          final payload = {
            'order_id': b['order_id'],
            'customer_id': b['customer_id'],
            'items': items,
            'subtotal_minor': subtotal,
            'discount_minor': 0,
            'total_minor': subtotal,
            'currency': 'PKR',
            'paid_at': '2026-10-17T10:00:00Z',
          };
          return http.Response(
            jsonEncode({
              'order_id': b['order_id'],
              'status': 'paid',
              'currency': 'PKR',
              'items': items,
              'subtotal_minor': subtotal,
              'discount_minor': 0,
              'total_minor': subtotal,
              'receipt': {'payload': payload, 'signature': 'sig', 'pdf_base64': base64Encode(utf8.encode('%PDF-1.4'))},
            }),
            201,
          );
        }
        final copy = http.Request(req.method, req.url)
          ..headers.addAll(req.headers)
          ..body = req.body;
        return http.Response.fromStream(await _inner.send(copy));
      });
}

void main() {
  late Box<String> cache;
  var boxSeq = 0;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('huddle_p0').path);
    cache = await Hive.openBox<String>(cacheBoxName);
  });

  /// Opens (or reopens from disk) a queue box outside the fake clock.
  Future<Box<String>> openQueue(WidgetTester tester, String name) async => (await tester.runAsync(() => Hive.openBox<String>(name)))!;

  Future<void> pumpApp(
    WidgetTester tester, {
    required Backend backend,
    required Box<String> queue,
    required StreamController<bool> device,
    required TokenStore tokens,
    required SharedPreferences prefs,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          syncBoxProvider.overrideWithValue(queue),
          cacheBoxProvider.overrideWithValue(cache),
          sseClientFactoryProvider.overrideWithValue(
            () => MockClient.streaming((req, _) async => http.StreamedResponse(StreamController<List<int>>().stream, 200)),
          ),
          tokenStoreProvider.overrideWithValue(tokens),
          httpClientProvider.overrideWithValue(backend.client()),
          deviceOnlineProvider.overrideWith((ref) => device.stream),
        ],
        child: const HuddleApp(),
      ),
    );
    device.add(backend.online);
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), 'Nascon@26');
    await tester.ensureVisible(find.text('Sign in').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
  }

  /// Lets real time pass (Hive disk IO) between frames until [done] or a timeout.
  Future<void> settleReal(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> openSyncScreen(WidgetTester tester) async {
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync queue'));
    await tester.pumpAndSettle();
  }

  group('Section 8.4 offline desk check (organizer scoring)', () {
    for (final outcome in ['applied', 'rejected']) {
      testWidgets('prepare online, score offline, persist across restart, sync -> $outcome', (tester) async {
        final backend = Backend()..syncResult = outcome;
        final device = StreamController<bool>.broadcast();
        addTearDown(device.close);
        final tokens = MemoryTokenStore();
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final name = 'q_offline_${boxSeq++}';
        final queue = await openQueue(tester, name);

        // 1. Online: the judge opens Fixtures (and Standings, Club). Match detail is NOT opened.
        await pumpApp(tester, backend: backend, queue: queue, device: device, tokens: tokens, prefs: prefs);
        await signIn(tester, 'organizer@nascon.test');
        await tester.tap(find.text('Standings').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Club').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fixtures').last);
        await tester.pumpAndSettle();
        expect(backend.paths, contains('/api/v1/matches/demo-live'), reason: 'match detail warmed while online');
        expect(cache.get('/api/v1/matches/demo-live'), isNotNull);

        // 2. Airplane mode: requests fail and the device reports no network.
        backend.online = false;
        device.add(false);
        await tester.pumpAndSettle();
        expect(find.textContaining('Offline'), findsWidgets);

        // 3. Open the match from cache and score it.
        await tester.tap(find.text("67'"));
        await tester.pumpAndSettle();
        expect(find.text('2 : 1'), findsOneWidget);
        expect(find.text("You're offline. Showing the last saved copy."), findsOneWidget);
        await tester.tap(find.text('+ Goal'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add'));
        await settleReal(tester, () => find.textContaining('Saved offline').evaluate().isNotEmpty);
        expect(find.textContaining('Saved offline: Goal for Alpha Falcons FC'), findsOneWidget);

        // Wire format of Section 5.14, base_version = the match version the device saw (7).
        expect(queue.length, 1);
        final stored = jsonDecode(queue.values.single) as Map<String, dynamic>;
        expect(stored['type'], 'score_event');
        expect(stored['base_version'], 7);
        expect(stored['status'], 'pending');
        expect(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$').hasMatch(stored['queued_at'] as String), isTrue);
        expect(RegExp(r'^[A-Za-z0-9_.:-]{1,64}$').hasMatch(stored['action_id'] as String), isTrue);
        final event = stored['payload'] as Map<String, dynamic>;
        expect(event['match_id'], 'demo-live');
        expect(event['type'], 'score');
        expect(event['payload'], {'team_id': 'club-alpha-1', 'event_type': 'goal', 'minute': 67});
        expect(RegExp(r'^[A-Za-z0-9_.:-]{1,64}$').hasMatch(event['event_id'] as String), isTrue);
        expect(backend.syncBodies, isEmpty, reason: 'nothing is sent while offline');

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await openSyncScreen(tester);
        expect(find.text('1 waiting'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);

        // 4. Force-close and reopen, still offline. The action is in the box file on disk (what a
        // cold start reads back); then a brand-new app instance is started on that queue.
        final onDisk = (await tester.runAsync(() => File(queue.path!).readAsBytes()))!;
        expect(utf8.decode(onDisk, allowMalformed: true), contains(stored['action_id'] as String));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await pumpApp(tester, backend: backend, queue: queue, device: device, tokens: tokens, prefs: prefs);
        await openSyncScreen(tester);
        expect(find.text('1 waiting'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);

        // 5. Network back: sync runs on its own and reports the per-action result.
        backend.online = true;
        device.add(true);
        await settleReal(tester, () => backend.syncBodies.isNotEmpty && find.textContaining('pplied:').evaluate().isNotEmpty);
        expect(backend.syncBodies, hasLength(1));
        final sent = (backend.syncBodies.single['actions'] as List).single as Map<String, dynamic>;
        expect(sent.keys.toSet(), {'action_id', 'type', 'queued_at', 'base_version', 'payload'});
        expect(sent['payload'], event);

        if (outcome == 'applied') {
          expect(find.textContaining('Applied:'), findsOneWidget);
          expect(queue.length, 0, reason: 'applied actions leave the persistent queue');
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1700)));
          await tester.pumpAndSettle();
          expect(find.text('Nothing waiting'), findsOneWidget);
        } else {
          expect(find.textContaining('Not applied:'), findsOneWidget);
          expect(find.textContaining("This match isn't live, so scores can't be added."), findsOneWidget);
          expect(find.textContaining('MATCH_NOT_IN_PROGRESS'), findsNothing);
          await tester.tap(find.text('Dismiss actions not applied'));
          await settleReal(tester, () => find.text('Nothing waiting').evaluate().isNotEmpty);
          expect(find.text('Nothing waiting'), findsOneWidget);
        }
        await tester.pump(const Duration(seconds: 5));
      });
    }
  });

  group('Section 8.2 store cart', () {
    Product jersey({int m = 1, int l = 5}) => Product(
          id: 'prod-jersey-001',
          name: 'Alpha Falcons Home Jersey',
          description: '',
          category: 'apparel',
          clubName: '',
          variants: [
            Variant(id: 'var-jersey-001-M', size: 'M', color: 'blue', priceMinor: 450000, stock: m),
            Variant(id: 'var-jersey-001-L', size: 'L', color: 'blue', priceMinor: 450000, stock: l),
          ],
        );

    test('cart merges a variant, caps by stock and the per-line limit, removes at zero', () {
      final c = ProviderContainer(overrides: [tokenStoreProvider.overrideWithValue(MemoryTokenStore())]);
      addTearDown(c.dispose);
      final cart = c.read(cartProvider.notifier);
      final p = jersey();
      expect(cart.add(p, p.variants[0]), isTrue);
      expect(cart.add(p, p.variants[0]), isFalse, reason: 'only 1 M in stock');
      for (var i = 0; i < 5; i++) {
        expect(cart.add(p, p.variants[1]), isTrue);
      }
      expect(cart.add(p, p.variants[1]), isFalse, reason: 'only 5 L in stock');
      expect(c.read(cartProvider).map((l) => '${l.variant.size}x${l.quantity}'), ['Mx1', 'Lx5']);
      expect(cart.count, 6);
      cart.setQuantity('var-jersey-001-L', 99);
      expect(c.read(cartProvider).last.quantity, 5);
      cart.setQuantity('var-jersey-001-L', 0);
      expect(c.read(cartProvider).map((l) => l.variant.size), ['M']);
      final big = jersey(l: 50);
      for (var i = 0; i < maxLineQuantity; i++) {
        cart.add(big, big.variants[1]);
      }
      expect(cart.add(big, big.variants[1]), isFalse, reason: 'quantity is capped at 10 per variant');
    });

    Future<Backend> openStore(WidgetTester tester) async {
      // A tall phone (412×915 dp) so the whole size sheet fits on screen.
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(1081, 2402);
      addTearDown(tester.view.reset);
      final backend = Backend();
      final device = StreamController<bool>.broadcast();
      addTearDown(device.close);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await pumpApp(tester, backend: backend, queue: await openQueue(tester, 'q_store_${boxSeq++}'), device: device, tokens: MemoryTokenStore(), prefs: prefs);
      await signIn(tester, 'viewer@nascon.test');
      await tester.tap(find.text('Store').last);
      await tester.pumpAndSettle();
      return backend;
    }

    Future<void> addSize(WidgetTester tester, String size) async {
      await tester.ensureVisible(find.text('Alpha Falcons Home Jersey'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alpha Falcons Home Jersey'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(size).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add to cart'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();
    }

    testWidgets('variant -> add to cart -> real count -> cart -> checkout of the cart -> receipt', (tester) async {
      final backend = await openStore(tester);
      expect(find.text('Cart · 0'), findsOneWidget);

      await addSize(tester, 'L');
      expect(find.text('Added to cart: Alpha Falcons Home Jersey (L)'), findsOneWidget);
      expect(find.text('Cart · 1'), findsOneWidget);
      await addSize(tester, 'L');
      await addSize(tester, 'M');
      expect(find.text('Cart · 3'), findsOneWidget);

      await tester.tap(find.text('Cart · 3'));
      await tester.pumpAndSettle();
      expect(find.text('Subtotal · 3 items'), findsOneWidget);
      expect(find.text('PKR 13500.00'), findsWidgets);
      expect(find.text('Size L · PKR 4500.00 each'), findsOneWidget);
      // M has 1 in stock, so it can't go above 1; L can be lowered.
      await tester.tap(find.byTooltip('One fewer L'));
      await tester.pumpAndSettle();
      expect(find.text('Subtotal · 2 items'), findsOneWidget);
      expect(find.text('Only 1 in stock.'), findsOneWidget);

      await tester.tap(find.text('Pay with mock card'));
      await tester.pumpAndSettle();
      expect(find.text('Pay PKR 9000.00?'), findsOneWidget);
      await tester.tap(find.text('Pay').last);
      await tester.pumpAndSettle();

      final sent = backend.checkoutBodies.single;
      expect(sent['items'], [
        {'variant_id': 'var-jersey-001-L', 'quantity': 1},
        {'variant_id': 'var-jersey-001-M', 'quantity': 1},
      ]);
      expect(sent['payment'], {'token': 'tok_success'});
      expect(sent['customer_id'], 'user-viewer');
      expect(find.text('Thank you for your order'), findsOneWidget);
      expect(find.text('Alpha Falcons Home Jersey (L) × 1'), findsOneWidget);
      expect(find.text('Alpha Falcons Home Jersey (M) × 1'), findsOneWidget);
      expect(find.text('PKR 9000.00'), findsWidgets);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Cart · 0'), findsOneWidget, reason: 'a paid cart is emptied');
    });

    testWidgets('a failed checkout keeps the cart and explains the error in plain words', (tester) async {
      final backend = await openStore(tester);
      backend.checkoutError = 'OUT_OF_STOCK';
      await addSize(tester, 'M');
      await tester.tap(find.text('Cart · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay with mock card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay').last);
      await tester.pumpAndSettle();
      expect(find.text('Sorry, this size just sold out. Try another size.'), findsOneWidget);
      expect(find.textContaining('OUT_OF_STOCK'), findsNothing);
      expect(find.text('Subtotal · 1 item'), findsOneWidget);
    });

    testWidgets('an empty cart says so and leads back to the store', (tester) async {
      await openStore(tester);
      await tester.tap(find.text('Cart · 0'));
      await tester.pumpAndSettle();
      expect(find.text('Your cart is empty. Browse the club store.'), findsOneWidget);
      await tester.tap(find.text('Back to store'));
      await tester.pumpAndSettle();
      expect(find.text('Club Store'), findsOneWidget);
    });
  });
}
