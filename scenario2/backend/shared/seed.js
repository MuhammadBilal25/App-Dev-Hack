'use strict';

const { state } = require('../../../src/state');
const scoring = require('../../../src/services/scoring');
const { PUBLIC_BASE_URL } = require('../config');
const streaming = require('../modules/streaming/models/streamKey.model');
const costream = require('../modules/costream/models/costream.model');
const qr = require('../modules/qr/models/qr.model');
const guestCart = require('../modules/guest-cart/models/guestCart.model');
const moderation = require('../modules/moderation/models/moderation.model');
const metrics = require('../modules/observability/models/metrics.model');

// Day 2 baseline (spec 5.2), applied by every POST /audit/v1/reset after the Day 1 seed.
const PLAYER_BETA_2 = {
  player_id: 'player-beta-2', club_id: 'club-beta-1', tenant_id: 'tenant-beta', name: 'Zain Malik', position: 'bowler', role: 'starter',
};

const MATCH_M1_EVENTS = [
  { event_id: 'd2-m1-init', type: 'match_init', payload: { sport_id: 'football', league_id: 'league-alpha-1', home_team_id: 'club-alpha-1', away_team_id: 'club-alpha-2' } },
  { event_id: 'd2-m1-start', type: 'match_start', payload: {} },
  { event_id: 'd2-m1-goal-1', type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal' } },
];

const QR_MAPPINGS = [
  ['match-m1', 'm1-live'],
  ['player-alpha-1', 'p-alpha-1'],
  ['club-alpha-1', 'c-alpha-1'],
];

const GUEST_TOKEN = 'guest_anon_tok_7721';

function resetDay2() {
  state.day2 = {
    streaming: streaming.createStore(),
    costream: costream.createStore(),
    qr: qr.createStore(),
    guestCart: guestCart.createStore(),
    moderation: moderation.createStore(),
    metrics: metrics.createStore(),
  };

  if (!state.players.has(PLAYER_BETA_2.player_id)) state.players.set(PLAYER_BETA_2.player_id, { ...PLAYER_BETA_2 });

  // match-m1: Football, in_progress, 1 - 0, built from the event log like every Day 1 match.
  for (const e of MATCH_M1_EVENTS) {
    const ev = { ...e, match_id: 'match-m1' };
    scoring.commitEvent(ev, scoring.checkEvent(ev));
  }

  for (const [entityId, code] of QR_MAPPINGS) qr.addMapping(state.day2.qr, entityId, code, PUBLIC_BASE_URL);

  state.day2.guestCart.tokens.set(GUEST_TOKEN, { guest_token: GUEST_TOKEN, role: 'guest', merged: false });
  state.day2.guestCart.carts.set('player-alpha-1', { user_id: 'player-alpha-1', items: [] });
}

module.exports = { resetDay2, GUEST_TOKEN };
