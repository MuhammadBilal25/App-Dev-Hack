# huddle (mobile)

Flutter Android app for the NaSCon '26 Multi-Sport League & Club Operations Platform. Design
source of truth: [`UI.md`](UI.md). Every screen talks to the real backend (`/api/v1`); see
[`API_NEEDS.md`](API_NEEDS.md) for the route each screen uses.

```bash
flutter pub get
flutter analyze
flutter test
flutter run                      # set the server address on the login screen ("Change server")
flutter build apk --release      # then copy to release/app-release.apk
```

The default server address is `http://localhost:8080`. On a phone, use the computer's Wi-Fi
address (for example `http://192.168.1.20:8080`), the emulator uses `http://10.0.2.2:8080`, or
`adb reverse tcp:8080 tcp:8080` keeps `localhost`. Demo accounts (password `Nascon@26`) are listed
under "Demo accounts" on the login screen.

## Navigation

Five tabs for every role: **Home, Fixtures, Standings, Store, Profile**. The cart is in the app
bar on every screen. Role tools open from the workspace card at the top of Home (and from
Profile): **Platform admin** (Super-Admin), **My leagues** (League Organizer), **My club** (Club
Manager), **My player profile** (Player). `/admin` and `/manage` routes redirect away for roles that
can't use them; the server enforces the same rules.

| Area | Screens |
|---|---|
| Public | Home, search, sports directory, sport detail, league detail (overview / fixtures / table or bracket), fixtures, match detail (live via SSE), standings, clubs, club profile, player profile |
| Store | Catalogue (search, category, filters, sort), product page (photos, size/colour, stock, quantity), cart (server re-pricing), mock checkout (test cards), orders, order detail, signed receipt + PDF |
| Organizer | My leagues dashboard, league management (generate fixtures for all 4 formats, Swiss next round, reschedule with conflict explanations, postpone / cancel / restore / start / abandon), sport-specific score entry, match control, product pinning |
| Club Manager | My club dashboard, roster management (add / transfer / loan / release, offline), roster history, edit club profile + logo upload, products list, product editor (photos with preview + progress, variants, stock), club orders |
| Super-Admin | Dashboard, sports (create from a form, switch on/off), leagues (create, assign organizers, enter clubs, status), clubs, users and roles, tenants and branding (colour + logo), store categories and discount codes, platform settings, activity log |
| Offline | Always-visible sync strip, Hive cache for fixtures, standings, clubs, home, leagues and players, durable action queue with per-action results (Sync screen) |

## Layout

```
lib/
  main.dart, app.dart        Hive + SharedPreferences init, MaterialApp.router, auto-sync on reconnect
  core/theme/                tokens, StatusColors, typography, buildTheme(brightness, tenant), tenants
  core/brand/                HuddleMark, TenantLogo (uploaded logo or initials), ClubCrest
  core/copy/                 plain-language messages for every backend error code (UI.md §8)
  core/widgets/              SyncStrip, StatusChip, EmptyState, ErrorBanner, ConfirmSheet, AppButton,
                             RemoteImage, ImageUploadPanel, common (sport icons, product/club tiles…)
  core/api/                  ApiClient (JWT, error mapping, sign-out on 401, uploads, PDF bytes)
  core/auth/                 session restore (works offline), login, sign out, secure token storage
  core/cart/                 persistent cart (Hive)
  core/sync/                 durable offline action queue (Hive), replay via POST /api/v1/sync
  core/router/               go_router: splash, login, 5-tab shell, role-guarded routes
  data/                      typed models and Riverpod providers (cached GETs fall back offline)
  features/                  screens (home, sports, club, players, match, store, manage, admin…)
```

Sport-specific behaviour comes only from each sport's config (`scoring.model` and its events), so
a new sport created by an admin gets correct score entry without an app update.
