# NaSCon '26 — Multi-Sport League & Club Operations Platform

Backend: Node.js 20 + Express 5, PostgreSQL 16, Redis 7 (cache, rate limiting and the domain-event stream).
Mobile: Flutter (Android), in `mobile/`.

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
| `DATABASE_URL` | set by compose | PostgreSQL connection string. |
| `REDIS_URL` | set by compose | Redis connection string. |
| `PORT` | set by compose | API port (8080). |

## Demo accounts

All passwords: `Nascon@26`

| Role | Email |
|---|---|
| Platform Super-Admin | admin@nascon.test |
| League Organizer (owns league-alpha-1) | organizer@nascon.test |
| Club Manager (owns club-alpha-1) | manager@nascon.test |
| Player (player-alpha-1) | player@nascon.test |
| General Viewer | viewer@nascon.test |

## Tests

```bash
./run_tests.sh
```
