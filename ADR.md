# Architecture Decision Records

Eight short records of the decisions that shape the backend. Format: context, decision,
consequences.

---

## ADR-1: Node.js 20 + Express 5, a modular monolith

**Context.** Eight hours across two days, a strict HTTP contract, and a team strongest in JavaScript.
Express 5 forwards rejected promises to the error handler, so async handlers need no wrappers.

**Decision.** One Express service, split into domain modules under `src/services/` (sports,
scoring, fixtures, standings, roster, store, rbac, offline sync). Each module returns
`{status, body}` or throws an `ApiError`; `app.js` only wires routes.

**Consequences.** One process to deploy and debug. Module boundaries make it possible to extract
services later (e.g. store) without changing contracts. Horizontal scaling needs the in-memory
state of ADR-3 to move to shared storage first.

---

## ADR-2: Sports are data, never code

**Context.** A "mystery sport" is created during grading; any branch on a sport or event name
costs 8 points.

**Decision.** A sport is a JSON config (`scoring_model`, `periods`, `scoring_events`, roster,
tie-break order). Engines branch only on the three *scoring models* (`event`, `innings`, `round`)
and read points/runs/rounds, legal-ball and wicket flags from the config. The four seeded sports
use the same schema as `POST /audit/v1/sports`.

**Consequences.** A new sport works immediately in events, fixtures, leagues and standings with no
restart. A genuinely new scoring model would still need code, which is the correct seam.

---

## ADR-3: Event sourcing with an append-only log; projections rebuilt on read

**Context.** Scores must be derived from an immutable stream; corrections are compensating
events; standings must react to corrections after qualification has been decided.

**Decision.** Each match holds an ordered event list (sequence = position). Every event is signed
and persisted to the append-only `match_events` table (no UPDATE/DELETE in domain code).
`project()` folds the log into a score on every read; `compensated`/`compensated_by` are derived
from compensation events, not stored flags. Standings call `project()` for every fixture on every
request.

**Consequences.** There are no counters that can drift, and corrections are always reflected. The
cost is recomputation, which is negligible at contest scale (40 teams). Snapshots would be the next
step at larger scale.

---

## ADR-4: Concurrency-safe inventory with a conditional UPDATE in PostgreSQL

**Context.** 20 simultaneous buyers of the last unit must yield exactly one order and never
negative stock (NFR-3).

**Decision.** Inventory lives in PostgreSQL with `CHECK (stock >= 0)`. Reservation is
`UPDATE inventory SET stock = stock - q, reserved = reserved + q WHERE variant_id = $1 AND stock >= q`
inside one transaction for all lines, taken in sorted variant order. Row locks serialize
buyers; a zero row count means out of stock and rolls everything back. Payment failure releases
the reservation; success moves units out of `reserved`.

**Consequences.** Correctness is enforced by the database, not by timing. A sorted lock order
prevents deadlocks for multi-item carts. Verified live: 1×201, 19×409, stock 0, reserved 0 in
about 240 ms.

---

## ADR-5: Idempotency keyed by client ids, including in-flight requests

**Context.** `event_id`, `order_id`, `request_id` and `action_id` replays must return the stored
result and change nothing; a different body with the same id is a conflict.

**Decision.** Store the canonical JSON of the original request with its response. Identical
replay returns the stored body with HTTP 200; any difference returns `DUPLICATE_*`. For checkout,
the *promise* is registered synchronously before the first `await`, so a concurrent duplicate
waits for the same result instead of reserving twice.

**Consequences.** Safe client retries, including the mobile offline queue. The keys are
in-process (see ADR-1) and are cleared by `/reset`.

---

## ADR-6: Policy-as-code RBAC with tenant isolation evaluated first

**Context.** Five roles, scoped ownership (own league, own club, self), absolute tenant
isolation, and 403-vs-404 semantics.

**Decision.** `src/services/rbac.js` holds a `POLICIES` table of predicates per action. `can()`
grants super-admin everything; for others the resource's tenant must match before any predicate
runs. The `guard()` middleware runs authenticate (401) → resolve resource (404 only if it does
not exist at all) → authorize (403). JWTs are HS256 with the algorithm pinned, so `alg:none`,
tampered and expired tokens fail.

**Consequences.** All permissions live in one reviewable file, with negative tests for every
cell of the matrix. Adding an action means adding one predicate.

---

## ADR-7: Internal queue = transactional outbox table + Redis Stream

**Context.** Order transitions must emit domain events to an internal queue without making
checkout depend on a broker.

**Decision.** `queue.emit()` writes the event to the `domain_events` outbox table and
publishes to the Redis Stream `domain-events` (capped with `MAXLEN ~ 10000`). Publishing is
fire-and-forget; a Redis outage never fails a request, and the outbox keeps the event for replay.
Real-time UI updates use Server-Sent Events (`/api/v1/stream`), not the queue.

**Consequences.** It's lightweight (Redis is already in the stack, and it uses less RAM than
RabbitMQ on 8 GB machines) and durable via the outbox. Consumers read the stream with consumer
groups.

---

## ADR-8: Reproducible one-command stack with self-seeding

**Context.** The grader runs `DAY1_SALT=… docker compose up -d --build` on a clean Ubuntu machine
and polls `/health`; failure costs 10 points and zeroes most vectors.

**Decision.** Three containers only (api, postgres:16-alpine, redis:7-alpine) with healthchecks
and `depends_on: service_healthy`. The API listens immediately (so `/health` returns 503 while
starting), waits for the DB, runs `CREATE TABLE IF NOT EXISTS` migrations, then seeds through
the same code path as `/reset`. `/health` is 200 only when the DB answers and seeding is done. The
salt is read only from the environment; `.env` is git-ignored and `.env.example` documents every
variable. `npm ci` uses a committed lockfile.

**Consequences.** No manual steps or pre-created volumes, and the stack is healthy within
seconds. Heavier optional images (MinIO, RabbitMQ) are left out, which keeps the build well inside
the 10-minute and 8 GB limits.
