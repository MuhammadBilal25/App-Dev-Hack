'use strict';

const { state } = require('../state');
const { err } = require('../lib/errors');
const { sha256Hex } = require('../lib/crypto');
const { project } = require('./scoring');

const round3 = (x) => Math.round(x * 1000) / 1000;

// One completed, decided match reduced to what the table needs. Nothing is cached: standings are
// rebuilt from the event logs on every call.
function playedMatches(league, sport) {
  const out = [];
  for (const f of league.fixtures) {
    const match = state.matches.get(f.match_id);
    if (!match) continue;
    const p = project(match);
    if (p.status !== 'completed' || p.outcome === 'undecided') continue;
    const per = sport.periods;
    const oversFaced = (side) => {
      if (sport.scoring_model !== 'innings') return 0;
      if (side.wickets >= per.innings_per_team * per.wickets_per_innings) return per.innings_per_team * per.overs_per_innings;
      return side.balls / per.balls_per_over;
    };
    out.push({
      match_id: f.match_id,
      home: p.home.team_id,
      away: p.away.team_id,
      winner: p.winner_team_id,
      draw: p.outcome === 'draw',
      score: { [p.home.team_id]: p.home.score, [p.away.team_id]: p.away.score },
      overs: { [p.home.team_id]: oversFaced(p.home), [p.away.team_id]: oversFaced(p.away) },
      fair: { [p.home.team_id]: p.home.fair_play, [p.away.team_id]: p.away.fair_play },
    });
  }
  return out;
}

// Aggregates for `team` over `matches` (optionally only against teams in `among`).
function aggregate(team, matches, pts, model, among) {
  const a = { played: 0, won: 0, drawn: 0, lost: 0, scored: 0, conceded: 0, points: 0, fair_play: 0, oversFaced: 0, oversBowled: 0 };
  for (const m of matches) {
    if (m.home !== team && m.away !== team) continue;
    const opp = m.home === team ? m.away : m.home;
    if (among && !among.has(opp)) continue;
    a.played += 1;
    if (m.draw) {
      a.drawn += 1;
      a.points += pts.draw;
    } else if (m.winner === team) {
      a.won += 1;
      a.points += pts.win;
    } else {
      a.lost += 1;
      a.points += pts.loss;
    }
    a.scored += m.score[team];
    a.conceded += m.score[opp];
    a.fair_play += m.fair[team];
    a.oversFaced += m.overs[team];
    a.oversBowled += m.overs[opp];
  }
  a.diff = model === 'innings'
    ? round3((a.oversFaced ? a.scored / a.oversFaced : 0) - (a.oversBowled ? a.conceded / a.oversBowled : 0))
    : a.scored - a.conceded;
  return a;
}

function standings(leagueId) {
  const league = state.standingsLeagues.get(leagueId);
  if (!league) throw err(404, 'LEAGUE_NOT_FOUND', `League ${leagueId} does not exist.`, { league_id: leagueId });
  const sport = state.sports.get(league.sport_id);
  const model = sport.scoring_model;
  const pts = league.points;
  const matches = playedMatches(league, sport);
  const overall = new Map(league.teams.map((t) => [t, aggregate(t, matches, pts, model)]));

  const order = [...league.tie_break_order.filter((c) => c !== 'draw_lots'), 'draw_lots'];
  const lots = (t) => sha256Hex(`${league.lots_seed}|${league.league_id}|${t}`);

  // Criterion value, oriented so that larger is better.
  function value(criterion, team, group) {
    switch (criterion) {
      case 'h2h_points':
        return aggregate(team, matches, pts, model, group).points;
      case 'h2h_diff':
        return aggregate(team, matches, pts, model, group).diff;
      case 'overall_diff':
        return overall.get(team).diff;
      case 'scored':
        return overall.get(team).scored;
      case 'fair_play':
        return overall.get(team).fair_play;
      default:
        return null;
    }
  }

  // Returns { teams: ordered, sep: criterion that separated teams[i] from teams[i + 1] }.
  function resolve(group) {
    if (group.length === 1) return { teams: group, sep: [] };
    const set = new Set(group);
    for (const c of order) {
      let buckets;
      if (c === 'draw_lots') {
        buckets = [...group].sort((x, y) => (lots(x) < lots(y) ? -1 : 1)).map((t) => [t]);
      } else {
        const byVal = new Map();
        for (const t of group) {
          const v = value(c, t, set);
          if (!byVal.has(v)) byVal.set(v, []);
          byVal.get(v).push(t);
        }
        if (byVal.size === 1) continue;
        buckets = [...byVal.entries()].sort((x, y) => y[0] - x[0]).map(([, ts]) => ts);
      }
      const teams = [];
      const sep = [];
      buckets.forEach((b, i) => {
        const r = resolve(b);
        if (i > 0) sep.push(c);
        teams.push(...r.teams);
        sep.push(...r.sep);
      });
      return { teams, sep };
    }
    return { teams: group, sep: group.slice(1).map(() => 'draw_lots') };
  }

  const byPoints = new Map();
  for (const t of league.teams) {
    const p = overall.get(t).points;
    if (!byPoints.has(p)) byPoints.set(p, []);
    byPoints.get(p).push(t);
  }
  const ranked = [];
  for (const [, group] of [...byPoints.entries()].sort((x, y) => y[0] - x[0])) {
    const r = resolve(group);
    r.teams.forEach((t, i) => ranked.push({ team: t, resolved_by: i < r.sep.length ? r.sep[i] : null }));
  }

  // Qualification (points only).
  const playedIds = new Set(matches.map((m) => m.match_id));
  const remaining = new Map(league.teams.map((t) => [t, 0]));
  for (const f of league.fixtures) {
    if (playedIds.has(f.match_id)) continue;
    remaining.set(f.home, remaining.get(f.home) + 1);
    remaining.set(f.away, remaining.get(f.away) + 1);
  }
  const points = (t) => overall.get(t).points;
  const max = (t) => points(t) + pts.win * remaining.get(t);
  const k = league.qualification_spots;
  const status = (t) => {
    const others = league.teams.filter((x) => x !== t);
    if (others.filter((x) => max(x) >= points(t)).length < k) return 'clinched';
    if (others.filter((x) => points(x) > max(t)).length >= k) return 'eliminated';
    return 'still_possible';
  };

  const table = ranked.map(({ team, resolved_by: resolvedBy }, i) => {
    const a = overall.get(team);
    return {
      rank: i + 1,
      team_id: team,
      played: a.played,
      won: a.won,
      drawn: a.drawn,
      lost: a.lost,
      scored: a.scored,
      conceded: a.conceded,
      diff: a.diff,
      points: a.points,
      fair_play: a.fair_play,
      status: status(team),
      resolved_by: resolvedBy,
    };
  });

  const h2h = {};
  for (const a of league.teams) {
    h2h[a] = {};
    for (const b of league.teams) {
      if (a === b) continue;
      const g = aggregate(a, matches, pts, model, new Set([b]));
      h2h[a][b] = { played: g.played, points: g.points, scored: g.scored, conceded: g.conceded };
    }
  }

  return { league_id: league.league_id, sport_id: league.sport_id, qualification_spots: k, table, h2h };
}

module.exports = { standings };
