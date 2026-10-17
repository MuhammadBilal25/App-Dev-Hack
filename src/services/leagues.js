'use strict';

const { state } = require('../state');
const { err, validation } = require('../lib/errors');
const { isObj, isInt, isStr, isId } = require('../lib/validate');
const { getSport, validTieBreakOrder } = require('./sports');
const { newMatch } = require('./scoring');

function validateLeague(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!isId(b.league_id)) bad.push('league_id');
  if (!isStr(b.sport_id) || !b.sport_id) bad.push('sport_id');

  const teams = b.teams;
  const teamsOk = Array.isArray(teams) && teams.length >= 2 && teams.length <= 40 && teams.every(isId) && new Set(teams).size === teams.length;
  if (!teamsOk) bad.push('teams');

  if (!Array.isArray(b.fixtures)) bad.push('fixtures');
  else {
    const ok = b.fixtures.every(
      (f) => isObj(f) && isId(f.match_id) && isId(f.home) && isId(f.away) && f.home !== f.away &&
        (!teamsOk || (teams.includes(f.home) && teams.includes(f.away))),
    );
    if (!ok) bad.push('fixtures');
  }

  if (b.points !== undefined && b.points !== null) {
    const p = b.points;
    if (!isObj(p) || ['win', 'draw', 'loss'].some((k) => p[k] !== undefined && !isInt(p[k]))) bad.push('points');
  }
  if (b.tie_break_order !== undefined && b.tie_break_order !== null && !validTieBreakOrder(b.tie_break_order)) bad.push('tie_break_order');

  const q = b.qualification;
  if (!isObj(q) || !isInt(q.spots) || q.spots < 1 || (teamsOk && q.spots > teams.length)) bad.push('qualification');
  if (b.lots_seed !== undefined && b.lots_seed !== null && !isInt(b.lots_seed)) bad.push('lots_seed');

  if (bad.length) throw validation(bad);
}

function registerLeague(b) {
  validateLeague(b);
  const sport = getSport(b.sport_id);
  if (state.standingsLeagues.has(b.league_id)) {
    throw err(409, 'LEAGUE_EXISTS', `League ${b.league_id} already exists.`, { league_id: b.league_id });
  }
  const seen = new Set();
  for (const f of b.fixtures) {
    if (state.matches.has(f.match_id) || seen.has(f.match_id)) {
      throw err(409, 'MATCH_EXISTS', `Match ${f.match_id} already exists.`, { match_id: f.match_id });
    }
    seen.add(f.match_id);
  }

  const p = b.points || {};
  const league = {
    league_id: b.league_id,
    sport_id: sport.sport_id,
    teams: [...b.teams],
    fixtures: b.fixtures.map((f) => ({ match_id: f.match_id, home: f.home, away: f.away })),
    points: { win: p.win ?? 3, draw: p.draw ?? 1, loss: p.loss ?? 0 },
    tie_break_order: b.tie_break_order ? [...b.tie_break_order] : [...sport.tie_break_order],
    qualification_spots: b.qualification.spots,
    lots_seed: isInt(b.lots_seed) ? b.lots_seed : state.seed,
  };
  state.standingsLeagues.set(league.league_id, league);
  for (const f of league.fixtures) state.matches.set(f.match_id, newMatch(f.match_id, sport.sport_id, league.league_id, f.home, f.away));

  return {
    status: 201,
    body: { league_id: league.league_id, status: 'created', team_count: league.teams.length, fixture_count: league.fixtures.length },
  };
}

module.exports = { registerLeague };
