import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/club/club_screen.dart';
import '../../features/fixtures/fixtures_screen.dart';
import '../../features/match/match_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/standings/standings_screen.dart';
import '../../features/store/receipt_screen.dart';
import '../../features/store/store_screen.dart';
import '../../data/models.dart';
import '../../features/sync/sync_queue_screen.dart';
import '../auth/auth_controller.dart';

class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const fixtures = '/fixtures';
  static const standings = '/standings';
  static const store = '/store';
  static const club = '/club';
  static const profile = '/profile';
  static const sync = '/sync';
}

/// Login, then a 5-tab shell (UI.md §9). Auth changes re-run the redirect, so a 401 anywhere
/// lands on Login and a successful sign-in lands on Fixtures.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider.select((s) => s.status), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      final loc = state.matchedLocation;
      if (status == AuthStatus.unknown) return loc == Routes.splash ? null : Routes.splash;
      if (status == AuthStatus.signedOut) return loc == Routes.login ? null : Routes.login;
      if (loc == Routes.login || loc == Routes.splash) return Routes.fixtures;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.sync, builder: (_, _) => const SyncQueueScreen()),
      GoRoute(path: '/match/:id', builder: (_, state) => MatchScreen(matchId: state.pathParameters['id']!)),
      GoRoute(
        path: '/receipt',
        redirect: (_, state) => state.extra is Map ? null : Routes.store,
        builder: (_, state) {
          final extra = state.extra as Map;
          return ReceiptScreen(
            order: Map<String, dynamic>.from(extra['order'] as Map),
            product: extra['product'] as Product?,
            variant: extra['variant'] as Variant?,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.fixtures, builder: (_, _) => const FixturesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.standings, builder: (_, _) => const StandingsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.store, builder: (_, _) => const StoreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.club, builder: (_, _) => const ClubScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
