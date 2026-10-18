'use strict';

// Fixture management for production leagues (FR-1.3): generating a league's schedule with the
// same engines as POST /audit/v1/fixtures, rescheduling with conflict detection, the match status
// state machine (incl. postponed / cancelled / abandoned) and bracket / Swiss round advancement.
// Matches are created through the event pipeline (signed match_init), never written directly.
const { state, clone } = require('../state');
const { err, validation } = require('../lib/errors');
const { isObj, isInt, isStr, isBool, isDate, addDays, today } = require('../lib/validate');
const { sha256Hex } = require('../lib/crypto');
const scoring = require('./scoring');
const roster = require('./roster');
const { roundRobin } = require('./fixtures/roundRobin');
const { swiss } = require('./fixtures/swiss');
const { singleElim, doubleElim } = require('./fixtures/bracket');
const realtime = require('../realtime');
const { DEFAULT_VENUE_HOURS } = require('../platformSeed');
const { nextId } = require('../lib/activity');
const views = require('./views');

const FORMATS = ['round_robin', 'swiss', 'single_elim', 'double_elim'];
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
const TS_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

// Allowed scheduling transitions. Starting and finishing a match append match_start / match_end
// events, so the event log stays the single source of truth for play.
const STATUS_TRANSITIONS = {
  upcoming: ['postponed', 'cancelled', 'in_progress'],
  postponed: ['upcoming', 'cancelled'],
  in_progress: ['abandoned', 'completed'],
  completed: [],
  cancelled: [],
  abandoned: [],
};

const list = (league) => {
  if (!state.leagueFixtures.has(league.league_id)) state.leagueFixtures.set(league.league_id, []);
  return state.leagueFixtures.get(league.league_id);
};

// Match ids are `<league>-<suffix>`; long league ids fall back to a short hash (64-char limit).
function matchIdFor(league, suffix) {
  const id = `${league.league_id}-${suffix}`;
  return id.length <= 58 ? id : `m-${sha256Hex(id).slice(0, 12)}-${suffix}`.slice(0, 58);
}

const venueOf = (clubId) => {
  const c = state.clubs.get(clubId);
  return c && c.home_venue ? c.home_venue.name : 'TBC';
};

function kickoffFor(league, dayIndex) {
  const s = league.schedule || {};
  const start = s.start_date || addDays(today(), 1);
  const time = s.kickoff_time || '15:00';
  return `${addDays(start, (dayIndex - 1) * (s.interval_days || 7))}T${time}:00Z`;
}

function createFixture(league, f, { seeded = false } = {}) {
  if (state.matches.has(f.match_id)) throw err(409, 'MATCH_EXISTS', `Match ${f.match_id} already exists.`, { match_id: f.match_id });
  const b = {
    event_id: `${f.match_id}-init`,
    match_id: f.match_id,
    type: 'match_init',
    payload: { sport_id: league.sport_id, league_id: league.league_id, home_team_id: f.home, away_team_id: f.away },
  };
  scoring.commitEvent(b, scoring.checkEvent(b));
  const fixture = {
    match_id: f.match_id,
    league_id: league.league_id,
    round: f.round,
    stage: f.stage || `Round ${f.round}`,
    home: f.home,
    away: f.away,
    kickoff_at: f.kickoff_at,
    venue: f.venue || venueOf(f.home),
    schedule_status: null,
    status_reason: null,
    bracket_match_id: f.bracket_match_id || null,
    seeded,
  };
  list(league).push(fixture);
  const pl = state.prodLeagues.get(league.league_id);
  if (pl) pl.fixtures.push({ match_id: f.match_id, home: f.home, away: f.away });
  realtime.publish('fixtures', 'fixture_created', { match_id: f.match_id, league_id: league.league_id });
  return fixture;
}

// ---------------------------------------------------------------------------------------------
// Duration and conflict detection
// ---------------------------------------------------------------------------------------------

// Expected length of a match from the sport's period config (scoring model, never sport name).
function durationMinutes(sport) {
  const p = sport.periods;
  if (sport.scoring_model === 'event') return p.count * p.duration_minutes + 30;
  if (sport.scoring_model === 'innings') return p.innings_per_team * 2 * p.overs_per_innings * 4 + 30;
  return p.best_of * 45;
}

const windowOf = (f) => {
  const league = state.leagues.get(f.league_id);
  const sport = state.sports.get(league.sport_id);
  const start = Date.parse(f.kickoff_at);
  return { start, end: start + durationMinutes(sport) * 60000 };
};

function venueHours(venueName, tenantId) {
  const club = [...state.clubs.values()].find((c) => c.tenant_id === tenantId && c.home_venue && c.home_venue.name === venueName);
  return (club && club.home_venue.hours) || DEFAULT_VENUE_HOURS;
}

const hhmm = (ms) => new Date(ms).toISOString().slice(11, 16);

// All conflicts a fixture would have at `kickoffAt` / `venue`, as structured objects naming the
// conflicting entities (venue, team ids, player ids) and the other match.
function conflictsFor(fixture, kickoffAt, venue) {
  const league = state.leagues.get(fixture.league_id);
  const me = windowOf({ ...fixture, kickoff_at: kickoffAt });
  const restMs = state.settings.min_rest_hours * 3600000;
  const out = [];
  const teams = [fixture.home, fixture.away];

  for (const other of views.allFixtures()) {
    if (other.match_id === fixture.match_id || ['cancelled', 'postponed'].includes(other.schedule_status)) continue;
    const otherLeague = state.leagues.get(other.league_id);
    if (!otherLeague || otherLeague.tenant_id !== league.tenant_id) continue;
    const o = windowOf(other);
    const overlap = me.start < o.end && o.start < me.end;
    if (overlap && other.venue === venue) {
      out.push({ type: 'venue_double_booking', match_id: other.match_id, entity_ids: [venue] });
    }
    const shared = teams.filter((t) => t === other.home || t === other.away);
    if (!shared.length) continue;
    if (overlap) out.push({ type: 'team_overlap', match_id: other.match_id, entity_ids: shared });
    else {
      const gap = me.start >= o.end ? me.start - o.end : o.start - me.end;
      if (gap < restMs) out.push({ type: 'min_rest_violation', match_id: other.match_id, entity_ids: shared, min_rest_hours: state.settings.min_rest_hours });
    }
  }

  // A player registered in both squads of the fixture.
  const ids = (squad) => new Set(roster.squadMembers(squad).map((p) => p.player_id));
  const home = ids(fixture.home);
  const both = [...ids(fixture.away)].filter((p) => home.has(p));
  if (both.length) out.push({ type: 'player_overlap', match_id: fixture.match_id, entity_ids: both });

  const hours = venueHours(venue, league.tenant_id);
  const sameDay = new Date(me.start).toISOString().slice(0, 10) === new Date(me.end - 1).toISOString().slice(0, 10);
  if (hhmm(me.start) < hours.open || !sameDay || hhmm(me.end) > hours.close) {
    out.push({ type: 'venue_unavailable', match_id: fixture.match_id, entity_ids: [venue], window: clone(hours) });
  }
  return out;
}

function throwConflicts(fixture, conflicts) {
  throw err(409, 'SCHEDULE_CONFLICT', 'The new time clashes with other fixtures or the venue hours.', { match_id: fixture.match_id, conflicts });
}

// ---------------------------------------------------------------------------------------------
// Generation
// ---------------------------------------------------------------------------------------------
function validateGenerate(b, league) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (b.start_date !== undefined && !isDate(b.start_date)) bad.push('start_date');
  if (b.kickoff_time !== undefined && !(isStr(b.kickoff_time) && TIME_RE.test(b.kickoff_time))) bad.push('kickoff_time');
  if (b.interval_days !== undefined && !(isInt(b.interval_days) && b.interval_days >= 1 && b.interval_days <= 60)) bad.push('interval_days');
  if (b.legs !== undefined && b.legs !== 1 && b.legs !== 2) bad.push('legs');
  if (b.total_rounds !== undefined && !(isInt(b.total_rounds) && b.total_rounds >= 1)) bad.push('total_rounds');
  if (b.third_place_match !== undefined && !isBool(b.third_place_match)) bad.push('third_place_match');
  if (b.bracket_reset !== undefined && !isBool(b.bracket_reset)) bad.push('bracket_reset');
  const all = views.leagueTeams(league.league_id);
  if (b.teams !== undefined && !(Array.isArray(b.teams) && b.teams.every((t) => all.includes(t)) && new Set(b.teams).size === b.teams.length)) bad.push('teams');
  if (bad.length) throw validation(bad);
}

function generate(league, b) {
  validateGenerate(b, league);
  if (list(league).length) {
    throw err(409, 'FIXTURES_EXIST', `League ${league.league_id} already has fixtures.`, { league_id: league.league_id, fixture_count: list(league).length });
  }
  const teams = b.teams || [...views.leagueTeams(league.league_id)];
  if (teams.length < 2) throw err(409, 'NOT_ENOUGH_TEAMS', 'A league needs at least two clubs before fixtures can be made.', { league_id: league.league_id, team_count: teams.length });
  league.schedule = {
    start_date: b.start_date || addDays(today(), 1),
    kickoff_time: b.kickoff_time || '15:00',
    interval_days: b.interval_days || 7,
  };
  const format = league.format || 'round_robin';
  if (format === 'round_robin') {
    const rr = roundRobin(teams, { legs: b.legs || 1 });
    for (const r of rr.rounds) {
      r.matches.filter((m) => m.status === 'scheduled').forEach((m) => {
        createFixture(league, { match_id: matchIdFor(league, m.match_id), round: r.round, home: m.home, away: m.away, kickoff_at: kickoffFor(league, r.round) });
      });
    }
  } else if (format === 'swiss') {
    const total = b.total_rounds || Math.max(1, Math.min(teams.length - 1, Math.ceil(Math.log2(teams.length))));
    if (total > teams.length - 1) throw validation(['total_rounds']);
    league.swiss = { seeds: teams, total_rounds: total, byes: {} };
    createSwissRound(league, 1, []);
  } else {
    league.bracket = {
      format,
      seeds: teams,
      params: format === 'single_elim' ? { third_place_match: !!b.third_place_match } : { bracket_reset: b.bracket_reset !== false },
    };
    if (format === 'double_elim' && teams.length < 3) throw err(409, 'NOT_ENOUGH_TEAMS', 'Double elimination needs at least three clubs.', { league_id: league.league_id });
    syncBracket(league);
  }
  return { league_id: league.league_id, format, fixtures: list(league).map(views.fixtureView).sort(views.byKickoff) };
}

// ---------------------------------------------------------------------------------------------
// Swiss rounds
// ---------------------------------------------------------------------------------------------
function createSwissRound(league, round, history) {
  const sw = league.swiss;
  const out = swiss(sw.seeds, { total_rounds: sw.total_rounds, round, history });
  out.pairings.forEach((p) => {
    createFixture(league, { match_id: matchIdFor(league, p.match_id), round, home: p.home, away: p.away, kickoff_at: kickoffFor(league, round) });
  });
  sw.byes[round] = out.bye || null;
  return out;
}

function swissHistory(league, upTo) {
  const history = [];
  const pending = [];
  for (let r = 1; r <= upTo; r++) {
    const matches = [];
    for (const f of list(league).filter((x) => x.round === r && x.schedule_status !== 'cancelled')) {
      const p = scoring.project(state.matches.get(f.match_id));
      if (p.status !== 'completed' || f.schedule_status) {
        pending.push(f.match_id);
        continue;
      }
      const result = p.outcome === 'home_win' ? 'home' : p.outcome === 'away_win' ? 'away' : 'draw';
      matches.push({ home: f.home, away: f.away, result });
    }
    history.push({ round: r, bye: league.swiss.byes[r] || null, matches });
  }
  return { history, pending };
}

function nextSwissRound(league) {
  if (!league.swiss) throw err(409, 'NOT_SWISS', 'This league does not use the Swiss format.', { league_id: league.league_id });
  const current = Math.max(0, ...list(league).map((f) => f.round));
  if (current >= league.swiss.total_rounds) throw err(409, 'TOURNAMENT_COMPLETE', 'Every Swiss round has been paired.', { league_id: league.league_id });
  const { history, pending } = swissHistory(league, current);
  if (pending.length) throw err(409, 'ROUND_NOT_COMPLETE', `Round ${current} still has unfinished matches.`, { round: current, pending_match_ids: pending });
  const out = createSwissRound(league, current + 1, history);
  return { league_id: league.league_id, round: current + 1, bye: out.bye || null, standings: out.standings, fixtures: list(league).filter((f) => f.round === current + 1).map(views.fixtureView) };
}

// ---------------------------------------------------------------------------------------------
// Brackets: recomputed from the seeds and every finished bracket match; matches whose two teams
// are known are created as they become playable.
// ---------------------------------------------------------------------------------------------
function bracketResults(league) {
  const out = [];
  for (const f of list(league)) {
    if (!f.bracket_match_id || f.schedule_status) continue;
    const p = scoring.project(state.matches.get(f.match_id));
    if (p.status === 'completed' && p.winner_team_id) out.push({ match_id: f.bracket_match_id, winner: p.winner_team_id });
  }
  return out;
}

function computeBracket(league) {
  const b = league.bracket;
  const fn = b.format === 'single_elim' ? singleElim : doubleElim;
  return fn(b.seeds, { ...b.params, results: bracketResults(league) });
}

function bracketSections(out) {
  if (out.format === 'single_elim') {
    const n = out.rounds.length;
    const title = (r) => (r === n ? 'Final' : r === n - 1 ? 'Semi-finals' : r === n - 2 ? 'Quarter-finals' : `Round ${r}`);
    return out.rounds.map((r) => ({
      title: title(r.round),
      matches: r.matches.map((m) => ({ ...m, stage: m.bracket === 'third_place' ? 'Third place' : title(r.round), day: r.round })),
    }));
  }
  const k = out.winners.length;
  return [
    ...out.winners.map((r) => ({ title: `Winners round ${r.round}`, matches: r.matches.map((m) => ({ ...m, stage: `Winners R${r.round}`, day: 2 * r.round - 1 })) })),
    ...out.losers.map((r) => ({ title: `Losers round ${r.round}`, matches: r.matches.map((m) => ({ ...m, stage: `Losers R${r.round}`, day: r.round + 1 })) })),
    { title: 'Grand final', matches: out.grand_final.map((m, i) => ({ ...m, stage: i === 0 ? 'Grand final' : 'Grand final (reset)', day: 2 * k + i })) },
  ];
}

function syncBracket(league) {
  if (!league.bracket) return null;
  const out = computeBracket(league);
  const existing = new Set(list(league).map((f) => f.bracket_match_id));
  for (const section of bracketSections(out)) {
    for (const m of section.matches) {
      if (existing.has(m.match_id) || m.bye || !m.home || !m.away || m.winner) continue;
      if (m.conditional && m.required !== true) continue;
      createFixture(league, {
        match_id: matchIdFor(league, m.match_id), round: m.day, stage: m.stage, home: m.home, away: m.away,
        kickoff_at: kickoffFor(league, m.day), bracket_match_id: m.match_id,
      });
    }
  }
  return out;
}

function bracketView(league) {
  if (!league.bracket) throw err(409, 'NOT_A_BRACKET', 'This league is not a knockout bracket.', { league_id: league.league_id });
  syncBracket(league);
  const out = computeBracket(league);
  const byBracketId = new Map(list(league).filter((f) => f.bracket_match_id).map((f) => [f.bracket_match_id, f]));
  const team = (id) => (id ? { team_id: id, name: views.clubName(id) } : null);
  return {
    league_id: league.league_id,
    format: out.format,
    bracket_size: out.bracket_size,
    sections: bracketSections(out).map((s) => ({
      title: s.title,
      matches: s.matches.map((m) => {
        const f = byBracketId.get(m.match_id);
        const fv = f ? views.fixtureView(f) : null;
        return {
          bracket_match_id: m.match_id,
          stage: m.stage,
          home: team(m.home),
          away: team(m.away),
          bye: !!m.bye,
          winner_team_id: m.winner || null,
          conditional: !!m.conditional,
          required: m.required === undefined ? true : m.required,
          match_id: fv ? fv.match_id : null,
          status: fv ? fv.status : null,
          score: fv ? { home: fv.home.score, away: fv.away.score } : null,
        };
      }),
    })),
  };
}

// ---------------------------------------------------------------------------------------------
// Reschedule and status
// ---------------------------------------------------------------------------------------------
function reschedule(fixture, b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!(isStr(b.kickoff_at) && TS_RE.test(b.kickoff_at) && !Number.isNaN(Date.parse(b.kickoff_at)))) bad.push('kickoff_at');
  if (b.venue !== undefined && !(isStr(b.venue) && b.venue.trim() && b.venue.length <= 80)) bad.push('venue');
  if (bad.length) throw validation(bad);
  const status = views.effectiveStatus(fixture);
  if (!['upcoming', 'postponed'].includes(status)) {
    throw err(409, 'ILLEGAL_TRANSITION', `A ${status} match cannot be rescheduled.`, { match_id: fixture.match_id, from: status });
  }
  const venue = b.venue ? b.venue.trim() : fixture.venue;
  const conflicts = conflictsFor(fixture, b.kickoff_at, venue);
  if (conflicts.length) throwConflicts(fixture, conflicts);
  const before = { kickoff_at: fixture.kickoff_at, venue: fixture.venue, status };
  fixture.kickoff_at = b.kickoff_at;
  fixture.venue = venue;
  fixture.schedule_status = null;
  fixture.status_reason = null;
  publishStatus(fixture);
  return { before, fixture: views.fixtureView(fixture) };
}

function setStatus(fixture, b) {
  if (!isObj(b)) throw validation(['body']);
  const to = b.status;
  const bad = [];
  if (!Object.keys(STATUS_TRANSITIONS).includes(to)) bad.push('status');
  if (b.reason !== undefined && b.reason !== null && !(isStr(b.reason) && b.reason.length <= 200)) bad.push('reason');
  if (bad.length) throw validation(bad);
  const from = views.effectiveStatus(fixture);
  if (!STATUS_TRANSITIONS[from].includes(to)) {
    throw err(409, 'ILLEGAL_TRANSITION', `A match cannot move from ${from} to ${to}.`, { match_id: fixture.match_id, from, to });
  }
  if (to === 'in_progress' || to === 'completed') {
    const ev = { event_id: nextId('evt'), match_id: fixture.match_id, type: to === 'in_progress' ? 'match_start' : 'match_end', payload: {} };
    scoring.commitEvent(ev, scoring.checkEvent(ev));
  } else if (to === 'upcoming') {
    // Back from postponed: the old slot must still be free.
    const conflicts = conflictsFor(fixture, fixture.kickoff_at, fixture.venue);
    if (conflicts.length) throwConflicts(fixture, conflicts);
    fixture.schedule_status = null;
    fixture.status_reason = null;
  } else {
    fixture.schedule_status = to;
    fixture.status_reason = b.reason || null;
  }
  const league = state.leagues.get(fixture.league_id);
  if (to === 'completed') syncBracket(league);
  publishStatus(fixture);
  return { from, to, fixture: views.fixtureView(fixture) };
}

function publishStatus(fixture) {
  const view = views.fixtureView(fixture);
  realtime.publish(`match:${fixture.match_id}`, 'match_status', view);
  realtime.publish('fixtures', 'fixture_updated', { match_id: fixture.match_id, status: view.status });
  realtime.publish(`league:${fixture.league_id}`, 'standings_changed', { match_id: fixture.match_id });
}

// A match accepts score events only while it is not postponed / cancelled / abandoned.
function assertPlayable(fixture) {
  if (fixture.schedule_status) {
    throw err(409, 'MATCH_NOT_PLAYABLE', `Match ${fixture.match_id} is ${fixture.schedule_status}.`, { match_id: fixture.match_id, status: fixture.schedule_status });
  }
}

module.exports = {
  FORMATS, STATUS_TRANSITIONS, createFixture, matchIdFor, generate, nextSwissRound, syncBracket, bracketView,
  reschedule, setStatus, conflictsFor, durationMinutes, assertPlayable, kickoffFor,
};
