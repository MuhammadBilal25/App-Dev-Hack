'use strict';

const { state, clone } = require('../state');
const { ApiError, validation } = require('../lib/errors');
const { isObj, isStr, isId, isInt } = require('../lib/validate');
const scoring = require('./scoring');
const roster = require('./roster');

const ACTION_TYPES = ['score_event', 'roster_transfer'];
const TS_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

function validateEnvelope(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!isStr(b.device_id) || !b.device_id) bad.push('device_id');
  const a = b.actions;
  if (!Array.isArray(a) || a.length < 1 || a.length > 100) bad.push('actions');
  else if (!a.every((x) => isObj(x) && isId(x.action_id) && ACTION_TYPES.includes(x.type) && isStr(x.queued_at) && TS_RE.test(x.queued_at) &&
    isInt(x.base_version) && x.base_version >= 0 && isObj(x.payload))) bad.push('actions');
  if (bad.length) throw validation(bad);
}

const result = (action, status, resolution, errorCode, serverVersion, signature = null) => ({
  action_id: action.action_id,
  status,
  resolution,
  error_code: errorCode,
  processed_order: 0,
  server_version: serverVersion,
  signature,
});

const rejected = (a, code, version) => result(a, 'rejected', 'server_wins', code, version);
const duplicate = (a, version) => result(a, 'duplicate', 'skipped_duplicate', null, version);

// Shared skeleton: not-found -> duplicate -> base_version -> domain rules -> apply.
function processScore(a) {
  const ev = a.payload;
  try {
    scoring.validateEnvelope(ev);
  } catch (e) {
    return rejected(a, e.code, 0);
  }
  const match = state.matches.get(ev.match_id);
  const version = () => (state.matches.get(ev.match_id) ? state.matches.get(ev.match_id).events.length : 0);
  if (!match && ev.type !== 'match_init') return rejected(a, 'MATCH_NOT_FOUND', 0);
  try {
    if (scoring.checkReplay(ev)) return duplicate(a, version());
  } catch (e) {
    return rejected(a, e.code, version());
  }
  const current = version();
  if (a.base_version > current) return rejected(a, 'INVALID_BASE_VERSION', current);
  try {
    const m = scoring.checkEvent(ev);
    const resp = scoring.commitEvent(ev, m);
    return result(a, 'applied', a.base_version === current ? 'appended' : 'rebased_append', null, resp.match_version, resp.signature);
  } catch (e) {
    if (e instanceof ApiError) return rejected(a, e.code, version());
    throw e;
  }
}

function processRoster(a) {
  const t = a.payload;
  try {
    roster.validateTransfer(t);
  } catch (e) {
    return rejected(a, e.code, 0);
  }
  if (!state.rosterLeagues.has(t.league_id)) return rejected(a, 'LEAGUE_NOT_FOUND', 0);
  if (!state.rosterPlayers.has(t.player_id)) return rejected(a, 'PLAYER_NOT_FOUND', 0);
  for (const sid of [t.from_squad_id, t.type === 'release' ? null : t.to_squad_id]) {
    if (sid && !state.rosterSquads.has(sid)) return rejected(a, 'SQUAD_NOT_FOUND', roster.playerVersion(t.player_id));
  }
  const current = roster.playerVersion(t.player_id);
  try {
    if (roster.checkTransferReplay(t)) return duplicate(a, current);
  } catch (e) {
    return rejected(a, e.code, current);
  }
  if (a.base_version > current) return rejected(a, 'INVALID_BASE_VERSION', current);
  try {
    const ctx = roster.checkTransfer(t);
    roster.applyTransfer(t, ctx);
    return result(a, 'applied', a.base_version === current ? 'appended' : 'rebased_append', null, roster.playerVersion(t.player_id));
  } catch (e) {
    if (e instanceof ApiError) return rejected(a, e.code, roster.playerVersion(t.player_id));
    throw e;
  }
}

// `authorize` (production route only) returns an error code for actions the caller may not
// perform; those are rejected without touching domain state.
function sync(b, { authorize = null } = {}) {
  validateEnvelope(b);
  const order = b.actions.map((a, i) => ({ a, i })).sort((x, y) => (x.a.queued_at < y.a.queued_at ? -1 : x.a.queued_at > y.a.queued_at ? 1 : x.i - y.i));
  const results = new Array(b.actions.length);

  order.forEach(({ a, i }, idx) => {
    const key = `${b.device_id}|${a.action_id}`;
    let r;
    const prior = state.offlineProcessed.get(key);
    if (prior) {
      const v = a.type === 'score_event'
        ? (state.matches.get(a.payload.match_id) || { events: [] }).events.length
        : roster.playerVersion(a.payload.player_id);
      r = duplicate(a, v);
    } else {
      const denied = authorize ? authorize(a) : null;
      if (denied) {
        const v = a.type === 'score_event'
          ? (state.matches.get(a.payload.match_id) || { events: [] }).events.length
          : roster.playerVersion(a.payload.player_id);
        r = rejected(a, denied, v);
      } else r = a.type === 'score_event' ? processScore(a) : processRoster(a);
      state.offlineProcessed.set(key, clone(r));
    }
    r.processed_order = idx + 1;
    results[i] = r;
  });

  const summary = { applied: 0, rejected: 0, duplicate: 0 };
  for (const r of results) summary[r.status] += 1;
  return { status: 200, body: { device_id: b.device_id, results, summary } };
}

module.exports = { sync };
