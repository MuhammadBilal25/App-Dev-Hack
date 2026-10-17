'use strict';

const seed = require('./seed');

// In-process domain state. The API runs as a single Node process, so synchronous sections are
// atomic. Durable append-only logs and inventory live in PostgreSQL (see db.js / ADR.md).
const state = { ready: false };

function clone(o) {
  return JSON.parse(JSON.stringify(o));
}

function resetMemory(seedValue) {
  state.seed = seedValue;
  state.sports = new Map(seed.SPORTS.map((s) => [s.sport_id, clone(s)]));
  state.tenants = new Map(seed.TENANTS.map((t) => [t.tenant_id, clone(t)]));
  state.leagues = new Map(seed.LEAGUES.map((l) => [l.league_id, clone(l)]));
  state.clubs = new Map(seed.CLUBS.map((c) => [c.club_id, clone(c)]));
  state.players = new Map(seed.PLAYERS.map((p) => [p.player_id, clone(p)]));
  state.users = new Map(seed.USERS.map((u) => [u.email, clone(u)]));
  state.products = new Map(seed.PRODUCTS.map((p) => [p.product_id, clone(p)]));
  state.variants = new Map();
  for (const p of seed.PRODUCTS) {
    for (const v of p.variants) state.variants.set(v.variant_id, { ...clone(v), product_id: p.product_id, tenant_id: p.tenant_id });
  }

  // Standings leagues registered through /audit/v1/leagues.
  state.standingsLeagues = new Map();
  // Match streams: match_id -> { match_id, sport_id, league_id, home, away, events: [] }
  state.matches = new Map();
  state.eventsById = new Map();
  // Roster scenarios.
  state.rosterLeagues = new Map();
  state.rosterSquads = new Map();
  state.rosterPlayers = new Map();
  state.transferRequests = new Map();
  state.auditSeq = 0;
  // Checkout idempotency (in-flight promises keyed by order_id).
  state.orders = new Map();
  state.paymentSeq = 0;
  // Offline sync: `${device_id}|${action_id}` -> result
  state.offlineProcessed = new Map();
  // Product pinned on a match page: match_id -> product_id
  state.pinned = new Map();
}

module.exports = { state, resetMemory, clone };
