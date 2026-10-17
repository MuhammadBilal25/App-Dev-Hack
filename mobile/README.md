# huddle (mobile)

Flutter Android app for NaSCon '26 Part I. Design source of truth: [`UI.md`](UI.md).
Backend routes still needed: [`API_NEEDS.md`](API_NEEDS.md).

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # set the server address on the login screen ("Change server")
```

The default server address is `http://localhost:8080`. On a phone, use the computer's Wi-Fi
address (for example `http://192.168.1.20:8080`), or `adb reverse tcp:8080 tcp:8080` to keep
`localhost`. Demo accounts (password `Nascon@26`) are listed under "Demo accounts" on the login
screen.

## Layout

```
lib/
  main.dart, app.dart        Hive + SharedPreferences init, MaterialApp.router, auto-sync on reconnect
  core/theme/                tokens, StatusColors, typography, buildTheme(brightness, tenant), tenants
  core/brand/                HuddleMark (CustomPainter), TenantLogo, ClubCrest
  core/copy/                 plain-language messages for every backend error code (UI.md §8)
  core/widgets/              SyncStrip, StatusChip, EmptyState, ErrorBanner, Skeleton, ConfirmSheet,
                             AppButton, AppTextField, RoleBadge, TenantAppBar
  core/api/                  ApiClient (JWT, error mapping, sign-out on 401, reachability)
  core/auth/                 session restore (works offline), login, sign out, secure token storage
  core/connectivity/         device network + server reachability (no polling)
  core/sync/                 durable offline action queue (Hive), replay via offline-sync
  core/router/               go_router: splash, login, 5-tab shell, sync queue
  features/                  screens
```
