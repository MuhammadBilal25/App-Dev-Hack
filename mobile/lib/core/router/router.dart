import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_screens.dart';
import '../../features/auth/login_screen.dart';
import '../../features/club/club_edit_screen.dart';
import '../../features/club/club_screen.dart';
import '../../features/fixtures/fixtures_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/manage/club_manager_screens.dart';
import '../../features/manage/organizer_screens.dart';
import '../../features/match/match_screen.dart';
import '../../features/players/player_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/sports/sports_screens.dart';
import '../../features/standings/standings_screen.dart';
import '../../features/store/cart_screen.dart';
import '../../features/store/checkout_screen.dart';
import '../../features/store/orders_screen.dart';
import '../../features/store/product_screen.dart';
import '../../features/store/receipt_screen.dart';
import '../../features/store/store_screen.dart';
import '../../features/sync/sync_queue_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/user.dart';

class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/home';
  static const fixtures = '/fixtures';
  static const standings = '/standings';
  static const store = '/store';
  static const profile = '/profile';
  static const sync = '/sync';
}

String _id(GoRouterState s, [String key = 'id']) => s.pathParameters[key]!;

/// Login, then a 5-tab shell (Home, Fixtures, Standings, Store, Profile) with every other screen
/// pushed on top. Auth changes re-run the redirect, so a 401 anywhere lands on Login. Role
/// areas (/admin, /manage) redirect away for roles that can't use them; the server enforces
/// the same rules on every request.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider.select((s) => s.status), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      if (session.status == AuthStatus.unknown) return loc == Routes.splash ? null : Routes.splash;
      if (session.status == AuthStatus.signedOut) return loc == Routes.login ? null : Routes.login;
      if (loc == Routes.login || loc == Routes.splash) return Routes.home;
      final role = session.user?.role;
      if (loc.startsWith('/admin') && role != UserRole.superAdmin) return Routes.home;
      if (loc.startsWith('/manage/organizer') || loc.startsWith('/manage/league')) {
        if (role != UserRole.superAdmin && role != UserRole.leagueOrganizer) return Routes.home;
      }
      if (loc == '/manage/club' && role != UserRole.clubManager) return Routes.home;
      if (loc.startsWith('/manage/products') || loc == '/manage/orders') {
        final u = session.user;
        if (u == null || !(u.isSuperAdmin || (u.role == UserRole.clubManager && u.storeAccess))) return Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.sync, builder: (_, _) => const SyncQueueScreen()),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(path: '/sports', builder: (_, _) => const SportsScreen()),
      GoRoute(path: '/sports/:id', builder: (_, s) => SportDetailScreen(sportId: _id(s))),
      GoRoute(path: '/leagues/:id', builder: (_, s) => LeagueDetailScreen(leagueId: _id(s))),
      GoRoute(path: '/clubs', builder: (_, _) => const ClubsScreen()),
      GoRoute(path: '/club/:id', builder: (_, s) => ClubProfileScreen(clubId: _id(s))),
      GoRoute(path: '/club/:id/edit', builder: (_, s) => ClubEditScreen(clubId: _id(s))),
      GoRoute(path: '/club/:id/history', builder: (_, s) => RosterHistoryScreen(clubId: _id(s))),
      GoRoute(path: '/player/:id', builder: (_, s) => PlayerScreen(playerId: _id(s))),
      GoRoute(path: '/match/:id', builder: (_, s) => MatchScreen(matchId: _id(s))),
      GoRoute(path: '/product/:id', builder: (_, s) => ProductScreen(productId: _id(s))),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen()),
      GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
      GoRoute(path: '/orders/:id', builder: (_, s) => OrderDetailScreen(orderId: _id(s), managed: s.uri.queryParameters['managed'] == '1')),
      GoRoute(path: '/receipt/:id', builder: (_, s) => ReceiptScreen(orderId: _id(s))),
      // League Organizer
      GoRoute(path: '/manage/organizer', builder: (_, _) => const OrganizerDashboardScreen()),
      GoRoute(path: '/manage/league/:id', builder: (_, s) => LeagueManageScreen(leagueId: _id(s))),
      // Club Manager (store routes also for the Super-Admin)
      GoRoute(path: '/manage/club', builder: (_, _) => const ManagerDashboardScreen()),
      GoRoute(path: '/manage/products', builder: (_, _) => const ProductsManageScreen()),
      GoRoute(path: '/manage/products/new', builder: (_, _) => const ProductEditorScreen()),
      GoRoute(path: '/manage/products/:id', builder: (_, s) => ProductEditorScreen(productId: _id(s))),
      GoRoute(path: '/manage/orders', builder: (_, _) => const OrdersScreen(managed: true)),
      // Super-Admin
      GoRoute(path: '/admin', builder: (_, _) => const AdminDashboardScreen()),
      GoRoute(path: '/admin/sports', builder: (_, _) => const AdminSportsScreen()),
      GoRoute(path: '/admin/sports/new', builder: (_, _) => const AdminSportEditorScreen()),
      GoRoute(path: '/admin/leagues', builder: (_, _) => const AdminLeaguesScreen()),
      GoRoute(path: '/admin/leagues/new', builder: (_, _) => const AdminLeagueEditorScreen()),
      GoRoute(path: '/admin/clubs', builder: (_, _) => const AdminClubsScreen()),
      GoRoute(path: '/admin/users', builder: (_, _) => const AdminUsersScreen()),
      GoRoute(path: '/admin/users/new', builder: (_, _) => const AdminUserEditorScreen()),
      GoRoute(path: '/admin/tenants', builder: (_, _) => const AdminTenantsScreen()),
      GoRoute(path: '/admin/store', builder: (_, _) => const AdminStoreScreen()),
      GoRoute(path: '/admin/settings', builder: (_, _) => const AdminSettingsScreen()),
      GoRoute(path: '/admin/activity', builder: (_, _) => const AdminActivityScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.fixtures, builder: (_, _) => const FixturesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.standings, builder: (_, _) => const StandingsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.store, builder: (_, _) => const StoreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
