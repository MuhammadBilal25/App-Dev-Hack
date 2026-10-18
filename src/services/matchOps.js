'use strict';

// Authenticated match operations for the app: score entry (and compensating corrections) through
// the event-sourced engine, the RBAC check applied to every queued offline action, and pinning a
// product to a match page.
const { state } = require('../state');
const { err, validation } = require('../lib/errors');
const { isObj, isStr } = require('../lib/validate');
const { can, forbid } = require('./rbac');
const scoring = require('./scoring');
const roster = require('./roster');
const schedule = require('./schedule');
const views = require('./views');
const merch = require('./merch');
const realtime = require('../realtime');
const { nextId } = require('../lib/activity');

function scoringLeague(user, matchId) {
  const f = views.fixtureOr404(matchId);
  const league = state.leagues.get(f.league_id);
  if (!can(user, 'match.score.write', league)) throw forbid('match.score.write');
  return { f, league };
}

// Appends one event. `event_id` may come from the app so retries are idempotent; matches are
// created by fixture generation, never by the app. An optional payload.player_id credits the
// event to a player who must currently be in that team's squad.
function appendEvent(user, matchId, b) {
  const { f, league } = scoringLeague(user, matchId);
  if (!isObj(b)) throw validation(['body']);
  if (b.type === 'match_init') throw validation(['type'], 'Matches are created by fixture generation.');
  const payload = isObj(b.payload) ? b.payload : b.payload === undefined ? {} : b.payload;
  if (isObj(payload) && payload.player_id !== undefined) {
    if (!isStr(payload.player_id) || roster.currentSquadOf(payload.player_id) !== payload.team_id) throw validation(['payload.player_id'], 'That player is not in this team.');
  }
  const ev = { event_id: b.event_id || nextId('evt'), match_id: matchId, type: b.type, payload };
  scoring.validateEnvelope(ev);
  if (!scoring.checkReplay(ev)) schedule.assertPlayable(f);
  const r = scoring.appendEvent(ev);
  if (r.status === 201 && ev.type === 'match_end') schedule.syncBracket(league);
  return { status: r.status, body: { ...r.body, fixture: views.fixtureView(f) } };
}

// Per-action authorization for POST /api/v1/sync: returns an error code to reject with, or null.
function syncAuthorizer(user) {
  return (a) => {
    const p = isObj(a.payload) ? a.payload : {};
    if (a.type === 'score_event') {
      const m = state.matches.get(p.match_id);
      if (!m) return null; // the engine rejects it as MATCH_NOT_FOUND
      const f = views.fixtureMeta(p.match_id);
      const league = state.leagues.get(m.league_id);
      if (p.type === 'match_init' || !league || !can(user, 'match.score.write', league)) return 'FORBIDDEN';
      if (f && f.schedule_status) return 'MATCH_NOT_PLAYABLE';
      return null;
    }
    if (a.type === 'roster_transfer') {
      const squad = state.rosterSquads.get(p.from_squad_id);
      if (!squad) return null; // rejected as SQUAD_NOT_FOUND
      const club = state.clubs.get(squad.club_id) || { club_id: squad.club_id, tenant_id: squad.tenant_id };
      if (!can(user, 'club.roster.write', club)) return 'FORBIDDEN';
      const to = state.rosterSquads.get(p.to_squad_id);
      return p.type !== 'release' && to && to.league_id !== p.league_id ? 'CROSS_LEAGUE_TRANSFER' : null;
    }
    return 'FORBIDDEN';
  };
}

async function pinProduct(user, matchId, b) {
  const { f } = scoringLeague(user, matchId);
  if (!isObj(b) || !(b.product_id === null || isStr(b.product_id))) throw validation(['product_id']);
  let view = null;
  if (b.product_id === null) state.pinned.delete(f.match_id);
  else {
    const p = merch.visibleProduct(user, b.product_id);
    const league = state.leagues.get(f.league_id);
    if (p.tenant_id !== league.tenant_id || p.active === false) {
      throw err(409, 'PRODUCT_UNAVAILABLE', 'Only active products of this league\'s tenant can be pinned.', { product_id: p.product_id });
    }
    state.pinned.set(f.match_id, p.product_id);
    view = await merch.productView(p);
  }
  realtime.publish(`match:${f.match_id}`, 'product_pinned', { match_id: f.match_id, product: view });
  return { match_id: f.match_id, pinned_product: view };
}

module.exports = { appendEvent, syncAuthorizer, pinProduct };
