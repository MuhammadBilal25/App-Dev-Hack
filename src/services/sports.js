'use strict';

const { state, clone } = require('../state');
const { FULL_TIE_BREAK } = require('../seed');
const { err, validation } = require('../lib/errors');
const { isObj, isInt, isStr, isBool } = require('../lib/validate');

const MODELS = ['event', 'innings', 'round'];
const OVERTIME_POLICIES = ['none', 'extra_time', 'shootout', 'golden_score', 'super_over'];
const SPORT_ID_RE = /^[a-z0-9_-]{2,40}$/;
const EVENT_KEY_RE = /^[a-z0-9_]{1,40}$/;

const posInt = (v, min = 1) => isInt(v) && v >= min;

function validPeriods(model, p) {
  if (!isObj(p)) return false;
  if (model === 'event') return posInt(p.count) && posInt(p.duration_minutes);
  if (model === 'innings') {
    return posInt(p.innings_per_team) && posInt(p.overs_per_innings) && posInt(p.balls_per_over) && posInt(p.wickets_per_innings);
  }
  if (model === 'round') return posInt(p.best_of) && p.best_of % 2 === 1;
  return true; // model itself is reported as invalid
}

function validScoringEvent(model, v) {
  if (!isObj(v)) return false;
  if (model === 'event') return posInt(v.points);
  if (model === 'innings') return posInt(v.runs, 0) && isBool(v.legal_ball) && isBool(v.wicket);
  if (model === 'round') return posInt(v.rounds);
  return true;
}

function validTieBreakOrder(t) {
  return Array.isArray(t) && t.every((x) => FULL_TIE_BREAK.includes(x)) && new Set(t).size === t.length;
}

function validateSport(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  const model = b.scoring_model;

  if (!isStr(b.sport_id) || !SPORT_ID_RE.test(b.sport_id)) bad.push('sport_id');
  if (!isStr(b.name) || b.name.length < 1 || b.name.length > 80) bad.push('name');
  if (!MODELS.includes(model)) bad.push('scoring_model');
  if (!validPeriods(model, b.periods)) bad.push('periods');

  const se = b.scoring_events;
  if (!isObj(se) || Object.keys(se).length < 1) bad.push('scoring_events');
  else if (!Object.entries(se).every(([k, v]) => EVENT_KEY_RE.test(k) && validScoringEvent(model, v))) bad.push('scoring_events');

  if (!isBool(b.draw_allowed)) bad.push('draw_allowed');

  const ot = b.overtime;
  if (!isObj(ot) || !OVERTIME_POLICIES.includes(ot.policy) || (ot.duration_minutes !== undefined && !posInt(ot.duration_minutes, 0))) {
    bad.push('overtime');
  }

  if (b.tie_break_order !== undefined && !validTieBreakOrder(b.tie_break_order)) bad.push('tie_break_order');

  const r = b.roster;
  if (
    !isObj(r) || !posInt(r.min_squad_size) || !posInt(r.max_squad_size) || r.min_squad_size > r.max_squad_size ||
    !isObj(r.required_positions) || !Object.values(r.required_positions).every((n) => posInt(n, 0))
  ) {
    bad.push('roster');
  }

  if (bad.length) throw validation(bad);
}

function createSport(b) {
  validateSport(b);
  if (state.sports.has(b.sport_id)) throw err(409, 'SPORT_EXISTS', `Sport ${b.sport_id} already exists.`, { sport_id: b.sport_id });
  const config = {
    sport_id: b.sport_id,
    name: b.name,
    scoring_model: b.scoring_model,
    periods: clone(b.periods),
    scoring_events: clone(b.scoring_events),
    draw_allowed: b.draw_allowed,
    overtime: clone(b.overtime),
    tie_break_order: b.tie_break_order ? [...b.tie_break_order] : [...FULL_TIE_BREAK],
    roster: clone(b.roster),
  };
  state.sports.set(config.sport_id, config);
  return { status: 201, body: { sport_id: config.sport_id, status: 'created', config: clone(config) } };
}

function getSport(sportId) {
  const s = isStr(sportId) ? state.sports.get(sportId) : undefined;
  if (!s) throw err(404, 'SPORT_NOT_FOUND', `Sport ${sportId} does not exist.`, { sport_id: sportId ?? null });
  return s;
}

module.exports = { createSport, getSport, validTieBreakOrder };
