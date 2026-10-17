# API needs: backend routes the mobile app is waiting for

**Status (Step 1 done):** these now exist and the app uses them: `GET /api/v1/tenants/me`,
`/leagues`, `/fixtures`, `/matches/{id}` (timeline + pinned product), `/standings/{league_id}`,
`/clubs`, `/clubs/{id}`, `/catalogue`. Demo data for `league-alpha-1` is seeded on every reset.
Checkout still goes through `POST /audit/v1/checkout`.

**Still missing:** authenticated score entry (`POST /api/v1/matches/{id}/events`), roster actions
(`POST /api/v1/roster/transfer`, seeded clubs set up as a roster league), authenticated offline sync
(`POST /api/v1/sync`), `POST /api/v1/checkout` with the customer taken from the token, and
`GET /api/v1/orders`. The original wish list follows for reference.

The app uses these routes today: `POST /api/v1/auth/login`, `GET /api/v1/me`, `GET /api/v1/ping`,
`GET /api/v1/stream` (SSE) and `POST /audit/v1/offline-sync` for the offline queue.

The routes below do not exist yet. Until they do, the Fixtures, Standings, Store and Club tabs show
their empty states. All of them belong under `/api/v1`, so they are rate limited (100 requests per
rolling 10 s per IP). The app never polls: it fetches when a screen opens, on pull-to-refresh, and
when an SSE event says something changed.

Unless noted, every route needs `Authorization: Bearer <jwt>`, returns only data from the caller's
tenant (the Super Admin sees every tenant), and uses the standard error body
`{ "error": { "code", "message", "details" } }`.

## 1. Tenant info (white-label, FR-2.1)

`GET /api/v1/tenants/{tenant_id}`, public (no token), so Login can show the tenant before sign-in.

```json
{ "tenant_id": "tenant-alpha", "name": "Alpha Sports", "logo_url": null,
  "colors": { "primary": "#1E5EFF", "secondary": "#0B1F4D" } }
```

Today the tenant only arrives inside `user.tenant` after login. Known tenants (alpha, beta) use the
contrast-checked brand from UI.md §3.3, so `colors` is only a fallback for new tenants.

## 2. Fixtures list (Fixtures tab, home for every role)

`GET /api/v1/fixtures?league_id=&status=upcoming|in_progress|completed`

```json
{ "fixtures": [ {
  "match_id": "m-001", "league_id": "league-alpha-1", "league_name": "Alpha Premier League",
  "sport_id": "football", "round": 1, "kickoff_at": "2026-10-18T15:00:00Z", "venue": "Falcon Ground",
  "status": "in_progress", "minute": 67,
  "home": { "team_id": "club-alpha-1", "name": "Alpha Falcons FC", "score": 2 },
  "away": { "team_id": "club-alpha-2", "name": "Alpha Lions FC", "score": 1 } } ] }
```

There is no route that lists matches. Seeded leagues have no fixtures either, so the backend also
needs demo fixtures for `league-alpha-1` (and one beta league) for the judges' tasks.

## 3. Match detail and score entry

- `GET /api/v1/matches/{match_id}`: the `GET /audit/v1/score/{match_id}` projection plus team
  names, league name, the sport's `scoring_events` (to build the score-entry buttons) and
  `pinned_product` (see 7).
- `POST /api/v1/matches/{match_id}/events`: same body as `POST /audit/v1/events`, with RBAC
  `match.score.write` (organizer on their own league, or Super Admin). 403 `FORBIDDEN` otherwise.
- SSE `match:{match_id}` already exists and is enough for live updates.

## 4. Leagues and standings

- `GET /api/v1/leagues`: the tenant's leagues (`league_id`, `name`, `sport_id`, `season`).
- `GET /api/v1/leagues/{league_id}/standings`: the `/audit/v1/standings` table and `h2h`, plus
  `team_name` per row. Today standings only exist for leagues registered through
  `POST /audit/v1/leagues`, not for the seeded production leagues.

## 5. Club profile (Club tab, FR-2.1)

- `GET /api/v1/clubs`: clubs in the tenant (`club_id`, `name`, `league_id`).
- `GET /api/v1/clubs/{club_id}`: `name`, `home_venue {name, lat, lng}`, `social`, `staff[]`,
  `stats` (played, won, drawn, lost, from the event logs), `roster[]` (`player_id`, `name`,
  `position`, `role`, `on_loan`, `version` for `base_version`) and `history[]` (transfer audit).

## 6. Roster actions (club manager, Task C)

`POST /api/v1/roster/transfer`: same body as `/audit/v1/roster/transfer`, with RBAC
`club.roster.write` on the `from` club. Seeded clubs and players also need to be set up as a
roster league (squads = clubs) on reset, so the manager has real players to move.

Offline writes currently replay through `POST /audit/v1/offline-sync`, which is unauthenticated
and skips RBAC. The app needs an authenticated twin, `POST /api/v1/sync` (same request and response
shape), that rejects actions the caller's role may not perform with `error_code: "FORBIDDEN"`.

## 7. Store catalogue and pinned product (Task B)

- `GET /api/v1/products?club_id=`: the catalogue (`store.catalogue()` exists but has no route),
  with live `stock` per variant so the UI can show "Last one!" and disable sold-out sizes.
- `GET /api/v1/matches/{match_id}/pinned-product`: the product pinned on a match page
  (`state.pinned` exists but nothing reads or writes it), plus SSE event `product_pinned` on
  `match:{match_id}`.
- `POST /api/v1/checkout`: same body as `/audit/v1/checkout`, with `customer_id` taken from the
  token instead of the body. Response as today (receipt `payload`, `signature`, `pdf_base64`).
- `GET /api/v1/orders`: the caller's orders, so a receipt can be opened again later.
