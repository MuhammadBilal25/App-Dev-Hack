# Scenario 2 (Day 2)

All Day 2 code lives here, kept apart from Day 1 so it is easy to read and test. It still runs
inside the same API on port 8080: `src/app.js` calls `scenario2/backend` to add the guest guard
and the Day 2 routes, and `POST /audit/v1/reset` calls `resetDay2()` after the Day 1 seed.

```
scenario2/
  backend/
    index.js        mountGuards / mountRoutes / resetDay2 / attachRealtime
    config.js       DAY2_SALT and media URLs, read from the environment only
    shared/         signDay2 (HMAC), guestWriteGuard (403), Day 2 seed, helpers
    modules/
      streaming/      POST /audit/v1/stream/key
      costream/       POST /audit/v1/costream/session
      qr/             GET /audit/v1/qr/{id}, /export.{svg,png,pdf}, GET /q/{code}
      guest-cart/     POST /audit/v1/guest/cart-merge
      moderation/     POST /audit/v1/moderation/test, POST /api/v1/chat
      observability/  GET /metrics, DELETE /audit/v1/privacy/user/{id}
      realtime/       ws://localhost:8080/ws/matches/{id}
      (each: routes/ -> controllers/ -> services/ -> models/)
    tests/          Day 2 unit tests (run with npm test)
  web/              Guest Web Player (served at /web/*)
  postman/          Day 2 Postman collection
```

Files the grader expects at the repository root stay there: `docker-compose.yml`,
`.github/workflows/autograde.yml`, `tests/selenium/`, `tests/appium/`, `tests/k6_load.js`,
`tests/reports/`, `COVERAGE_DAY2.json`, `TRACEABILITY.md`.

## Salt

Put the Day 2 salt in `.env` (git-ignored) as `DAY2_SALT=...`. Never write it in source files.
