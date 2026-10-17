# Traceability Matrix

Maps every requirement ID in the Part I specification to the code that implements it and the
automated tests that verify it. Run all tests with `./run_tests.sh`.

## Functional requirements

| ID | Requirement | Implementation | Automated tests |
|---|---|---|---|
| FR-1.1 | Multi-sport taxonomy as data; mystery sport via JSON | `src/services/sports.js` (`createSport`, `validateSport`), `src/seed.js` (`SPORTS`) | `tests/scoring.test.js`: *mystery sport is created from JSON and validated*; *innings model limits…* |
| FR-1.1 | Event-sourced scoring, compensating events, HMAC signatures | `src/services/scoring.js` (`appendEvent`, `checkEvent`, `commitEvent`, `project`), `src/lib/crypto.js` (`canonical`, `sign`), `src/db.js` (`match_events`, append-only) | `tests/scoring.test.js`: *signature matches Appendix A test vector 1*; *event lifecycle, idempotency, compensation and projection*; *match_init, draws, tie-break winner…* |
| FR-1.2 | Leagues / tournaments scoped to seasons | `src/services/leagues.js` (`registerLeague`), `src/seed.js` (`LEAGUES`) | `tests/scoring.test.js`: *envelope validation and league registration rules* |
| FR-1.3 | Round robin (circle method, byes, withdrawals) | `src/services/fixtures/roundRobin.js` | `tests/fixtures.test.js`: *round robin: circle-method properties…*; *round robin withdrawals…* |
| FR-1.3 | Swiss (score groups, no rematches, byes, Buchholz) | `src/services/fixtures/swiss.js` (`swiss`, `minCostMatching`) | `tests/fixtures.test.js`: *swiss round 1 exact…*; *swiss spec example…*; *swiss matching is optimal…*; *swiss full tournament…*; *NO_VALID_PAIRING surfaces as 409…* |
| FR-1.3 | Single elimination (byes, seeded placement, third place) | `src/services/fixtures/bracket.js` (`singleElim`, `seedOrder`, `Bracket`) | `tests/fixtures.test.js`: *single elimination: seeding, byes, propagation, third place* |
| FR-1.3 | Double elimination (WB, LB, grand final, bracket reset) | `src/services/fixtures/bracket.js` (`doubleElim`) | `tests/fixtures.test.js`: *double elimination: counts, routing graph and bracket reset* |
| FR-1.3 | Match status state machine | `src/services/scoring.js` (`checkEvent`: `ILLEGAL_TRANSITION`, `MATCH_NOT_IN_PROGRESS`) | `tests/scoring.test.js`: *event lifecycle…* |
| FR-1.3 | Real-time status broadcast | `src/realtime.js` (SSE hub), published from `scoring.commitEvent` | Manual: `GET /api/v1/stream?channels=match:m1` |
| FR-1.4 | Points table, configurable points | `src/services/standings.js` (`standings`, `aggregate`) | `tests/standings.test.js`: *configurable points, tie-break order…* |
| FR-1.4 | Tie-breakers incl. 3-way H2H mini-league, draw of lots | `src/services/standings.js` (`resolve`, `value`, `lots`) | `tests/standings.test.js`: *draw_lots matches Appendix A test vector 2*; *three-way tie resolved through H2H mini-league…* |
| FR-1.4 | Sport-specific differentials (goal, point, run rate, map) | `src/services/standings.js` (`playedMatches`, `aggregate`) | `tests/standings.test.js`: *cricket net run rate…*; *undecided matches stay remaining; round-model differential* |
| FR-1.4 | Clinched / eliminated / still possible | `src/services/standings.js` (`status`) | `tests/standings.test.js`: *three-way tie…*; *configurable points…* |
| FR-2.1 | Club profiles, white-label tenants, isolation | `src/seed.js` (`TENANTS`, `CLUBS`), `src/services/rbac.js` (tenant check in `can`) | `tests/rbac.test.js`: *five-role negative authorization matrix* |
| FR-2.2 | Transfer, loan (auto-return), release with rule checks | `src/services/roster.js` (`checkTransfer`, `applyTransfer`, `settleLoan`) | `tests/roster.test.js`: *rule checks run in the exact order…*; *loan, PLAYER_ON_LOAN, and automatic return…*; *edge case 6…* |
| FR-2.2 | Immutable audit trail | `src/services/roster.js` (`appendAudit`, `history`), `src/db.js` (`audit_log`) | `tests/roster.test.js`: *transfer effects, idempotency and audit trail* |
| FR-2.3 | Catalogue with variants, discount codes | `src/seed.js` (`PRODUCTS`, `DISCOUNTS`), `src/services/store.js` (`catalogue`) | `tests/store.test.js`: *discount, payment failures…*; *order lifecycle transitions and catalogue* |
| FR-2.3 | Mock payment gateway (authorize, capture, failure) | `src/services/store.js` (`gateway`, `processCheckout`) | `tests/store.test.js`: *discount, payment failures release stock…* |
| FR-2.3 | Order states emit domain events to the queue | `src/services/store.js` (`ORDER_TRANSITIONS`, `transitionOrder`), `src/queue.js` (outbox + Redis Stream) | `tests/store.test.js`: *order lifecycle transitions and catalogue* |
| FR-2.3 | Server-side PDF receipt | `src/lib/pdf.js` (`receiptPdf`) | `tests/store.test.js`: *successful checkout returns a signed receipt and a real PDF* |
| FR-5.1 | Five-tier RBAC, policy-as-code, negative tests | `src/services/rbac.js` (`POLICIES`, `can`, `guard`), `src/services/auth.js` | `tests/rbac.test.js`: *five-role negative authorization matrix*; *policy layer unit checks* |

## Non-functional requirements

| ID | Requirement | Implementation | Automated tests |
|---|---|---|---|
| NFR-3 | Concurrency correctness: zero overselling | `src/services/store.js` (`reserve`: conditional `UPDATE … WHERE stock >= $2` in a transaction, fixed lock order; in-flight order map) | `tests/store.test.js`: *20 simultaneous buyers of the last unit…*; verified against real PostgreSQL in Docker (1×201, 19×409, stock 0, reserved 0) |
| NFR-4 | Offline tolerance, queued actions, conflict sync | `src/services/offlineSync.js` (`sync`, `processScore`, `processRoster`); mobile: `mobile/` local DB + queue | `tests/roster.test.js`: *offline sync: ordering, rebase, conflicts, duplicates* |
| NFR-5 | Security: JWT verification, rate limiting, validation, 413 | `src/services/auth.js` (`authenticate`, HS256 pinned), `src/middleware/rateLimit.js`, `src/lib/validate.js`, `src/app.js` (1 MB limit, error mapping) | `tests/rbac.test.js`: *token security…*; *login, /me and rate limiting…*; `tests/store.test.js`: *customer ids with markup…; 413…*; `tests/scoring.test.js`: SQL-injection sport id |
| NFR-7 | Reproducibility: one command, seeded baseline | `docker-compose.yml`, `Dockerfile`, `src/server.js` (migrate + seed on boot), `src/services/reset.js` | `tests/scoring.test.js`: *health is ok and reset seeds baseline*; clean-machine run `docker compose down -v && docker compose up -d --build` |

## Hidden complexity edge cases (Section 6)

| # | Edge case | Implementation | Test |
|---|---|---|---|
| 1 | Odd round robin + mid-season withdrawal | `roundRobin.js` | *round robin withdrawals…* |
| 2 | Swiss with no valid non-repeating pairing | `swiss.js` (branch and bound, bye fallback) | *NO_VALID_PAIRING surfaces as 409…* |
| 3 | Double elimination bracket reset | `bracket.js` (`GF2.conditional/required`) | *double elimination…* |
| 4 | Three-way tie, H2H mini-league | `standings.js` (`resolve` restart-on-split) | *three-way tie resolved…* |
| 5 | Compensation after qualification decided | `scoring.js` + `standings.js` (recomputed from log) | *three-way tie… then recomputed after compensation* |
| 6 | Last-day transfer during in-progress match | `roster.js` (`deferred_until_match_end`) | *edge case 6…* |
