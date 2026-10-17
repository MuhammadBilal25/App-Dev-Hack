'use strict';

const { state, clone } = require('../state');
const { pool } = require('../db');
const { err, validation } = require('../lib/errors');
const { sign, canonical } = require('../lib/crypto');
const { isObj, isInt, isStr, isId } = require('../lib/validate');
const { getSport } = require('./sports');
const realtime = require('../realtime');

const EVENT_TYPES = ['match_init', 'match_start', 'score', 'discipline', 'tiebreak_winner', 'match_end', 'compensation'];
const COMPENSABLE = ['score', 'discipline', 'tiebreak_winner'];

function newMatch(matchId, sportId, leagueId, home, away) {
  return { match_id: matchId, sport_id: sportId, league_id: leagueId || null, home, away, events: [] };
}

function getMatch(matchId) {
  const m = state.matches.get(matchId);
  if (!m) throw err(404, 'MATCH_NOT_FOUND', `Match ${matchId} does not exist.`, { match_id: matchId });
  return m;
}

// ---------------------------------------------------------------------------------------------
// Projection: the score is always rebuilt from the append-only log, never stored as counters.
// ---------------------------------------------------------------------------------------------
function emptySide(teamId, model) {
  const innings = model === 'innings';
  return { team_id: teamId, score: 0, wickets: innings ? 0 : null, balls: innings ? 0 : null, overs: null, fair_play: 0 };
}

function project(match) {
  const sport = state.sports.get(match.sport_id);
  const model = sport.scoring_model;
  const compensatedBy = new Map();
  for (const e of match.events) if (e.type === 'compensation') compensatedBy.set(e.payload.compensates, e.event_id);

  const home = emptySide(match.home, model);
  const away = emptySide(match.away, model);
  const sideOf = (teamId) => (teamId === match.home ? home : away);
  let status = 'upcoming';
  let tiebreak = null;

  for (const e of match.events) {
    if (e.type === 'match_start') status = 'in_progress';
    else if (e.type === 'match_end') status = 'completed';
    if (compensatedBy.has(e.event_id) || e.type === 'compensation') continue;
    if (e.type === 'score') {
      const s = sideOf(e.payload.team_id);
      const def = sport.scoring_events[e.payload.event_type] || {};
      if (model === 'event') s.score += def.points || 0;
      else if (model === 'innings') {
        s.score += def.runs || 0;
        if (def.legal_ball) s.balls += 1;
        if (def.wicket) s.wickets += 1;
      } else s.score += def.rounds || 0;
    } else if (e.type === 'discipline') sideOf(e.payload.team_id).fair_play += e.payload.points;
    else if (e.type === 'tiebreak_winner') tiebreak = e.payload.team_id;
  }

  if (model === 'innings') {
    const bpo = sport.periods.balls_per_over;
    for (const s of [home, away]) s.overs = `${Math.floor(s.balls / bpo)}.${s.balls % bpo}`;
  }

  let winner = null;
  if (home.score > away.score) winner = home.team_id;
  else if (away.score > home.score) winner = away.team_id;
  else if (tiebreak) winner = tiebreak;

  let outcome = 'pending';
  if (status === 'completed') {
    if (winner) outcome = winner === home.team_id ? 'home_win' : 'away_win';
    else outcome = sport.draw_allowed ? 'draw' : 'undecided';
  }

  return {
    match_id: match.match_id,
    sport_id: match.sport_id,
    league_id: match.league_id,
    status,
    outcome,
    winner_team_id: winner,
    tiebreak_winner_team_id: tiebreak,
    home,
    away,
    version: match.events.length,
    events: match.events.map((e) => ({
      sequence: e.sequence,
      event_id: e.event_id,
      type: e.type,
      payload: clone(e.payload),
      signature: e.signature,
      compensated: compensatedBy.has(e.event_id),
      compensated_by: compensatedBy.get(e.event_id) || null,
    })),
  };
}

// ---------------------------------------------------------------------------------------------
// Append
// ---------------------------------------------------------------------------------------------
function validatePayload(type, p) {
  const bad = [];
  switch (type) {
    case 'match_init':
      if (!isStr(p.sport_id) || !p.sport_id) bad.push('payload.sport_id');
      if (!isId(p.home_team_id)) bad.push('payload.home_team_id');
      if (!isId(p.away_team_id) || p.away_team_id === p.home_team_id) bad.push('payload.away_team_id');
      if (p.league_id !== undefined && p.league_id !== null && !isId(p.league_id)) bad.push('payload.league_id');
      break;
    case 'score':
      if (!isStr(p.team_id)) bad.push('payload.team_id');
      if (!isStr(p.event_type)) bad.push('payload.event_type');
      break;
    case 'discipline':
      if (!isStr(p.team_id)) bad.push('payload.team_id');
      if (!isInt(p.points)) bad.push('payload.points');
      break;
    case 'tiebreak_winner':
      if (!isStr(p.team_id)) bad.push('payload.team_id');
      break;
    case 'compensation':
      if (!isStr(p.compensates) || !p.compensates) bad.push('payload.compensates');
      if (p.reason !== undefined && p.reason !== null && !isStr(p.reason)) bad.push('payload.reason');
      break;
    default:
      break;
  }
  return bad;
}

function validateEnvelope(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!isId(b.event_id)) bad.push('event_id');
  if (!isId(b.match_id)) bad.push('match_id');
  if (!EVENT_TYPES.includes(b.type)) bad.push('type');
  if (!isObj(b.payload)) bad.push('payload');
  if (!bad.length) bad.push(...validatePayload(b.type, b.payload));
  if (bad.length) throw validation(bad);
}

function requireSide(match, teamId) {
  if (teamId !== match.home && teamId !== match.away) {
    throw err(400, 'VALIDATION_ERROR', `Team ${teamId} is not playing match ${match.match_id}.`, { fields: ['payload.team_id'] });
  }
}

function requireInProgress(proj) {
  if (proj.status !== 'in_progress') {
    throw err(409, 'MATCH_NOT_IN_PROGRESS', `Match ${proj.match_id} is ${proj.status}.`, { match_id: proj.match_id, status: proj.status });
  }
}

function checkScoringLimits(match, sport, proj, teamId) {
  if (sport.scoring_model === 'innings') {
    const p = sport.periods;
    const s = teamId === match.home ? proj.home : proj.away;
    if (s.balls >= p.innings_per_team * p.overs_per_innings * p.balls_per_over || s.wickets >= p.innings_per_team * p.wickets_per_innings) {
      throw err(409, 'INNINGS_COMPLETE', `Innings of ${teamId} is complete.`, { match_id: match.match_id, team_id: teamId });
    }
  } else if (sport.scoring_model === 'round') {
    const need = (sport.periods.best_of + 1) / 2;
    if (proj.home.score >= need || proj.away.score >= need) {
      throw err(409, 'SERIES_ALREADY_DECIDED', `Series in match ${match.match_id} is already decided.`, { match_id: match.match_id });
    }
  }
}

// Checks every rule for an event without changing anything. Returns the match to append to.
function checkEvent(b) {
  const p = b.payload;
  if (b.type === 'match_init') {
    getSport(p.sport_id);
    if (state.matches.has(b.match_id)) throw err(409, 'MATCH_EXISTS', `Match ${b.match_id} already exists.`, { match_id: b.match_id });
    return null;
  }

  const match = getMatch(b.match_id);
  const sport = state.sports.get(match.sport_id);
  const proj = project(match);

  switch (b.type) {
    case 'match_start':
      if (proj.status !== 'upcoming') {
        throw err(409, 'ILLEGAL_TRANSITION', `Cannot start a match that is ${proj.status}.`, { match_id: match.match_id, from: proj.status, to: 'in_progress' });
      }
      break;
    case 'score':
      requireSide(match, p.team_id);
      if (!Object.prototype.hasOwnProperty.call(sport.scoring_events, p.event_type)) {
        throw err(400, 'UNKNOWN_EVENT_TYPE', `Event type ${p.event_type} is not defined for ${sport.sport_id}.`, { event_type: p.event_type, sport_id: sport.sport_id });
      }
      requireInProgress(proj);
      checkScoringLimits(match, sport, proj, p.team_id);
      break;
    case 'discipline':
    case 'tiebreak_winner':
      requireSide(match, p.team_id);
      requireInProgress(proj);
      break;
    case 'match_end':
      if (proj.status !== 'in_progress') {
        throw err(409, 'ILLEGAL_TRANSITION', `Cannot end a match that is ${proj.status}.`, { match_id: match.match_id, from: proj.status, to: 'completed' });
      }
      if (proj.home.score === proj.away.score && !sport.draw_allowed && !proj.tiebreak_winner_team_id) {
        throw err(409, 'TIE_NOT_ALLOWED', 'Score is level and this sport does not allow draws.', { match_id: match.match_id });
      }
      break;
    case 'compensation': {
      const target = state.eventsById.get(p.compensates);
      if (!target) throw err(404, 'EVENT_NOT_FOUND', `Event ${p.compensates} does not exist.`, { event_id: p.compensates });
      const already = proj.events.find((e) => e.event_id === p.compensates);
      if (target.match_id !== match.match_id || !COMPENSABLE.includes(target.type) || (already && already.compensated)) {
        throw err(409, 'INVALID_COMPENSATION', `Event ${p.compensates} cannot be compensated.`, { event_id: p.compensates });
      }
      break;
    }
    default:
      break;
  }
  return match;
}

function commitEvent(b, matchArg) {
  let match = matchArg;
  if (b.type === 'match_init') {
    const p = b.payload;
    match = newMatch(b.match_id, p.sport_id, p.league_id, p.home_team_id, p.away_team_id);
    state.matches.set(match.match_id, match);
  }
  const signature = sign(b.event_id, b.payload);
  const record = { sequence: match.events.length + 1, event_id: b.event_id, type: b.type, payload: clone(b.payload), signature };
  match.events.push(record);
  const response = {
    event_id: b.event_id,
    match_id: match.match_id,
    type: b.type,
    sequence: record.sequence,
    match_version: match.events.length,
    signature,
  };
  state.eventsById.set(b.event_id, { requestKey: requestKey(b), response, match_id: match.match_id, type: b.type });

  pool
    .query('INSERT INTO match_events (event_id, match_id, sequence, type, payload, signature) VALUES ($1,$2,$3,$4,$5,$6)', [
      record.event_id, match.match_id, record.sequence, record.type, record.payload, signature,
    ])
    .catch((e) => console.error('event persist failed', e.message));

  realtime.publish(`match:${match.match_id}`, 'match_event', { event: response, score: project(match) });
  if (match.league_id) realtime.publish(`league:${match.league_id}`, 'standings_changed', { match_id: match.match_id });
  return response;
}

const requestKey = (b) => canonical({ event_id: b.event_id, match_id: b.match_id, type: b.type, payload: b.payload });

// Returns { replay: response } for an identical replay, throws 409 for a conflicting reuse.
function checkReplay(b) {
  const prior = state.eventsById.get(b.event_id);
  if (!prior) return null;
  if (prior.requestKey === requestKey(b)) return prior.response;
  throw err(409, 'DUPLICATE_EVENT_ID', `Event ${b.event_id} was already used with a different body.`, { event_id: b.event_id });
}

function appendEvent(b) {
  validateEnvelope(b);
  const replay = checkReplay(b);
  if (replay) return { status: 200, body: clone(replay) };
  const match = checkEvent(b);
  return { status: 201, body: clone(commitEvent(b, match)) };
}

function getScore(matchId) {
  return project(getMatch(matchId));
}

module.exports = { appendEvent, getScore, project, newMatch, getMatch, validateEnvelope, checkReplay, checkEvent, commitEvent };
