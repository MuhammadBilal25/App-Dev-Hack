# NaSCon '26 — Multi-Sport League & Club Operations Platform

## Quick start (backend + app)

**1. Backend** (Docker):

```bash
cp .env.example .env                      # put your team salt in DAY1_SALT
DAY1_SALT=<your-salt> docker compose up -d --build
curl http://localhost:8080/health         # {"status":"ok"} once seeded
curl -X POST http://localhost:8080/audit/v1/reset   # fresh demo data (do this just before judging)
```

**2. App** (Flutter 3.41.3 / Dart 3.11, Android):

```bash
cd mobile
flutter pub get
flutter run                               # or: flutter build apk --release
```

**3. Server address.** The app defaults to `http://localhost:8080`. On a real phone, open
**Change server** on the login screen (or **Profile → Server address**) and enter the laptop's
Wi-Fi address, e.g. `http://192.168.1.20:8080` (phone and laptop on the same network). With a USB
cable you can keep `localhost` by running `adb reverse tcp:8080 tcp:8080`. The address is saved on
the phone.

**4. Sign in** with any demo account below (password `Nascon@26` for all). The login screen also
has a **Demo accounts** list that fills them in. The installable app is
`mobile/release/app-release.apk` (Android 10+).

| Role | Email | What to try |
|---|---|---|
| Super Admin | `admin@nascon.test` | Home → **Platform admin**: sports, leagues, clubs, users, branding, store config, settings, activity log |
| League Organizer (league-alpha-1 + volleyball cup) | `organizer@nascon.test` | Home → **My leagues**: generate / reschedule fixtures; live match → sport-specific **Score entry**, **Correct**, **End match**, pin a product |
| Club Manager (club-alpha-1, store access) | `manager@nascon.test` | Home → **My club** → **Manage roster** (add / transfer / loan / release); Store → **Manage** → new product, photos, stock; club orders |
| Player (player-alpha-1) | `player@nascon.test` | Home → **My player profile and stats** |
| Viewer / fan | `viewer@nascon.test` | Browse sports, leagues, clubs; Store → product → cart → mock checkout → signed receipt + PDF |
| League Organizer, tenant-beta | `organizer.beta@nascon.test` | Cricket (innings) score entry; isolated from tenant-alpha |
| Club Manager without store access | `lions.manager@nascon.test` | Roster tools only; store routes answer 403 |

Demo content (extra sports, leagues, clubs, players, fixtures, products) is created by `src/demo.js`
on every reset and labelled **Demo data** in the app. All of it goes through the real engines.

Offline: score and roster changes are queued on the phone (they survive force-close), show as
**Pending** on the Sync screen, and sync automatically on reconnect or with **Sync now**; each
action then shows **Applied** or **Not applied** with the reason.

Backend: Node.js 20 + Express 5, PostgreSQL 16, Redis 7 (domain-event stream), MinIO (product photos
and logos; `bitnamilegacy/minio`, a pinned MinIO build, because the official `minio/minio` image is
no longer published on Docker Hub). Mobile: Flutter (Android), in `mobile/`.

## Run the backend

```bash
cp .env.example .env          # then put your team salt in DAY1_SALT
DAY1_SALT=<your-salt> docker compose up -d --build
curl http://localhost:8080/health   # {"status":"ok"} once seeded
```

The API listens on host port **8080**. On startup it creates the schema and seeds the baseline data;
`POST /audit/v1/reset` restores the same baseline at any time.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `DAY1_SALT` | yes | HMAC-SHA256 key for event and receipt signatures. Read from the environment only. |
| `JWT_SECRET` | no | JWT signing secret. Random per start if empty. |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | no | MinIO credentials (defaults `nascon` / `nascon-minio-secret`), passed to the API as `S3_ACCESS_KEY` / `S3_SECRET_KEY`. |
| `S3_ENDPOINT`, `S3_BUCKET` | set by compose | Object storage for uploads. Without `S3_ENDPOINT`, uploads stay in memory (unit tests). |
| `API_RATE_LIMIT` | no | Test-only override of the contract limit (100 requests / 10 s) on `/api/v1`. |
| `DATABASE_URL` | set by compose | PostgreSQL connection string. |
| `REDIS_URL` | set by compose | Redis connection string. |
| `PORT` | set by compose | API port (8080). |

## Demo accounts (detail)

All passwords: `Nascon@26`

| Role | Email |
|---|---|
| Platform Super-Admin | admin@nascon.test |
| League Organizer (owns league-alpha-1) | organizer@nascon.test |
| Club Manager (owns club-alpha-1) | manager@nascon.test |
| Player (player-alpha-1) | player@nascon.test |
| General Viewer | viewer@nascon.test |
| League Organizer (tenant-beta, league-beta-1) | organizer.beta@nascon.test |
| Club Manager without store access (club-alpha-2) | lions.manager@nascon.test |

## Tests

```bash
./run_tests.sh                   # backend: 70 tests with coverage, regenerates COVERAGE.json
cd mobile && flutter test        # app: 16 widget tests (roles, purchase, scoring online/offline, uploads, small screens)
```

## API overview

| Method & path | Purpose |
|---|---|
| `GET /health` | Readiness (DB reachable + seeded) |
| `POST /audit/v1/reset` | Wipe and re-seed baseline |
| `POST /audit/v1/sports` | Create a sport from JSON rules |
| `POST /audit/v1/fixtures` | Round robin / Swiss / single / double elimination |
| `POST /audit/v1/leagues` | Register a league for standings |
| `POST /audit/v1/events` / `GET /audit/v1/score/{match_id}` | Event-sourced scoring |
| `GET /audit/v1/standings/{league_id}` | Table, H2H, qualification |
| `POST /audit/v1/roster/setup` · `/roster/transfer` · `GET /roster/history/{player_id}` | Roster operations |
| `POST /audit/v1/checkout` · `GET /audit/v1/inventory/{variant_id}` | Store |
| `POST /audit/v1/rbac-matrix` · `/audit/v1/rbac/*` | RBAC tokens and probes |
| `POST /audit/v1/offline-sync` | Replay offline mobile actions |
| `POST /api/v1/auth/login` · `GET /api/v1/me` · `GET /api/v1/ping` · `GET /api/v1/stream` | Mobile API (rate limited) |
| `POST /api/v1/clubs/{id}/players` | Club Manager of that club adds a player (403 otherwise, 409 `SQUAD_FULL`, audit action `add`) |
| `GET /api/v1/tenants/me` · `/home` · `/search` · `/sports[/{id}]` · `/leagues[/{id}[/bracket]]` · `/fixtures` · `/matches/{id}` · `/standings/{id}` · `/clubs[/{id}]` · `/players/{id}` | Read API: JWT required, tenant-isolated (403 cross-tenant) |
| `POST /api/v1/matches/{id}/events` · `/status` · `/reschedule` · `/pin` · `POST /api/v1/leagues/{id}/fixtures/generate` · `/swiss/next-round` | Organizer of that league (or Super-Admin): scoring, status machine, conflict-checked rescheduling, fixture generation |
| `POST /api/v1/sync` · `POST /api/v1/roster/transfer` · `PATCH /api/v1/clubs/{id}` · `POST /api/v1/clubs/{id}/logo` | Authenticated offline sync (per-action RBAC), roster moves, club profile and logo |
| `/api/v1/products[...]` · `/variants/{id}` · `POST /api/v1/cart/quote` · `POST /api/v1/checkout` · `/api/v1/orders[...]` | Store: catalogue, product / variant / stock management, image uploads, server-priced cart, mock checkout, orders, refunds, signed receipts + PDF |
| `/api/v1/admin/*` | Super-Admin: dashboard, sports, tenants and branding, leagues and organizers, clubs, users and roles, settings, categories, discount codes, activity log |
| `GET /media/{key}` | Uploaded images streamed from MinIO (public, not rate limited) |

The route-by-screen list is in [`mobile/API_NEEDS.md`](mobile/API_NEEDS.md).

A ready-made Postman collection is in `postman/NaSCon.postman_collection.json`.

## Docs

- [`TRACEABILITY.md`](TRACEABILITY.md): requirement → code → test matrix
- [`ADR.md`](ADR.md): architecture decision records
- `COVERAGE.json`: per-area line coverage, regenerated by `./run_tests.sh`
