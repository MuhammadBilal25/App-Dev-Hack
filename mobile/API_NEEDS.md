# API used by the mobile app

Every route below exists and is used by the app. All are under `/api/v1`, need
`Authorization: Bearer <jwt>` (except login and ping), are rate limited (100 requests / 10 s / IP),
are tenant-isolated (the Super-Admin sees every tenant), and return the standard error body
`{ "error": { "code", "message", "details" } }`. Images are served at `/media/{key}` (public, not
rate limited). Nothing polls: screens fetch on open, on pull-to-refresh and on SSE events.

| Screen | Routes |
|---|---|
| Login / session | `POST /auth/login`, `GET /me`, `GET /ping` |
| Branding | `GET /tenants/me` |
| Home, search | `GET /home`, `GET /search?q=` |
| Sports | `GET /sports`, `GET /sports/{id}` |
| Leagues | `GET /leagues`, `GET /leagues/{id}`, `GET /leagues/{id}/bracket`, `GET /standings/{id}` |
| Fixtures, match | `GET /fixtures?league_id=&status=&club_id=&sport_id=`, `GET /matches/{id}`, SSE `GET /stream?channels=match:{id}` |
| Scoring (organizer) | `POST /matches/{id}/events`, `POST /matches/{id}/status`, `POST /matches/{id}/reschedule`, `POST /matches/{id}/pin`, `POST /sync` (offline queue) |
| Fixture management | `POST /leagues/{id}/fixtures/generate`, `POST /leagues/{id}/swiss/next-round`, `GET /dashboard/organizer` |
| Clubs, players | `GET /clubs`, `GET /clubs/{id}`, `GET /clubs/{id}/roster-history`, `PATCH /clubs/{id}`, `POST /clubs/{id}/logo`, `POST /clubs/{id}/players`, `POST /roster/transfer`, `GET /players/{id}`, `GET /dashboard/manager` |
| Store | `GET /products`, `GET /products/{id}`, `GET /store/categories`, `POST /cart/quote`, `POST /checkout` |
| Store management | `POST /products`, `PATCH /products/{id}`, `POST /products/{id}/variants`, `PATCH /variants/{id}`, `POST /products/{id}/images` (raw image bytes), `PATCH`/`DELETE /products/{id}/images/{image_id}`, `GET /store/low-stock` |
| Orders | `GET /orders?scope=mine|managed`, `GET /orders/{id}`, `POST /orders/{id}/status`, `GET /orders/{id}/receipt`, `GET /orders/{id}/receipt.pdf` |
| Super-Admin | `GET /admin/dashboard`, `/admin/sports`, `/admin/tenants` (+ `/logo`), `/admin/leagues` (+ `/organizers`, `/clubs`), `/admin/clubs`, `/admin/users`, `/admin/settings`, `/admin/categories`, `/admin/discounts`, `/admin/activity` |
