'use strict';

// Read models shared by the production API routes: fixtures with team names and live minute,
// leagues with counts, clubs. Everything is derived from domain state on each call.
const { state, clone } = require('../state');
const { err } = require('../lib/errors');
const scoring = require('./scoring');

const clubName = (id) => (state.clubs.get(id) || { name: id }).name;

const teamRef = (side) => ({
  team_id: side.team_id,
  name: clubName(side.team_id),
  logo_url: (state.clubs.get(side.team_id) || {}).logo_url || null,
  score: side.score,
  wickets: side.wickets,
  overs: side.overs,
});

const allFixtures = () => [...state.leagueFixtures.values()].flat();

function fixtureMeta(matchId) {
  for (const list of state.leagueFixtures.values()) {
    const f = list.find((x) => x.match_id === matchId);
    if (f) return f;
  }
  return null;
}

function fixtureOr404(matchId) {
  const f = fixtureMeta(matchId);
  if (!f) throw err(404, 'MATCH_NOT_FOUND', `Match ${matchId} does not exist.`, { match_id: matchId });
  return f;
}

// Scheduling status (postponed / cancelled / abandoned) overrides the status projected from
// the event log; otherwise the log decides (upcoming / in_progress / completed).
function effectiveStatus(f, projection) {
  return f.schedule_status || (projection || scoring.project(state.matches.get(f.match_id))).status;
}

// Minute of a live match from its kickoff, capped at the sport's regulation time.
function liveMinute(f, sport, status) {
  if (status !== 'in_progress' || !sport.periods.count) return null;
  const regulation = sport.periods.count * sport.periods.duration_minutes;
  const m = Math.floor((Date.now() - Date.parse(f.kickoff_at)) / 60000);
  return Math.max(1, Math.min(regulation, m));
}

function fixtureView(f) {
  const p = scoring.project(state.matches.get(f.match_id));
  const sport = state.sports.get(p.sport_id);
  const league = state.leagues.get(f.league_id);
  const status = effectiveStatus(f, p);
  return {
    match_id: f.match_id,
    league_id: f.league_id,
    league_name: league ? league.name : f.league_id,
    sport_id: p.sport_id,
    sport_name: sport.name,
    scoring_model: sport.scoring_model,
    round: f.round,
    stage: f.stage || `Round ${f.round}`,
    kickoff_at: f.kickoff_at,
    venue: f.venue,
    status,
    status_reason: f.status_reason || null,
    outcome: p.outcome,
    minute: liveMinute(f, sport, status),
    winner_team_id: p.status === 'completed' ? p.winner_team_id : null,
    home: teamRef(p.home),
    away: teamRef(p.away),
    version: p.version,
    seeded: !!f.seeded,
  };
}

const byKickoff = (a, b) => (a.kickoff_at < b.kickoff_at ? -1 : a.kickoff_at > b.kickoff_at ? 1 : 0);

const inTenant = (user, r) => user.role === 'super_admin' || r.tenant_id === user.tenant_id;

// Leagues the user may see; inactive leagues are hidden from everyone but their managers.
function visibleLeagues(user) {
  return [...state.leagues.values()].filter((l) => inTenant(user, l));
}

function leagueTeams(leagueId) {
  const pl = state.prodLeagues.get(leagueId);
  return pl ? pl.teams : [];
}

function leagueView(l) {
  const pl = state.prodLeagues.get(l.league_id);
  const sport = state.sports.get(l.sport_id);
  const fixtures = state.leagueFixtures.get(l.league_id) || [];
  const organizers = [...state.users.values()].filter((u) => u.role === 'league_organizer' && (u.league_ids || []).includes(l.league_id));
  return {
    ...clone(l),
    sport_name: sport ? sport.name : l.sport_id,
    scoring_model: sport ? sport.scoring_model : null,
    team_count: pl ? pl.teams.length : 0,
    fixture_count: fixtures.length,
    live_count: fixtures.filter((f) => effectiveStatus(f) === 'in_progress').length,
    qualification_spots: pl ? pl.qualification_spots : null,
    points: pl ? clone(pl.points) : null,
    tie_break_order: pl ? [...pl.tie_break_order] : [],
    organizers: organizers.map((u) => ({ user_id: u.user_id, name: u.name, email: u.email })),
  };
}

// Leagues a club plays in (its home league plus any cup it was entered into).
const clubLeagueIds = (clubId) => [...state.prodLeagues.values()].filter((pl) => pl.teams.includes(clubId)).map((pl) => pl.league_id);

function clubCard(c) {
  const league = state.leagues.get(c.league_id);
  return {
    club_id: c.club_id,
    name: c.name,
    tenant_id: c.tenant_id,
    league_id: c.league_id,
    league_name: league ? league.name : null,
    sport_id: league ? league.sport_id : null,
    sport_name: league && state.sports.get(league.sport_id) ? state.sports.get(league.sport_id).name : null,
    logo_url: c.logo_url || null,
    colors: clone(c.colors || null),
    venue_name: c.home_venue ? c.home_venue.name : null,
  };
}

module.exports = {
  clubName, teamRef, allFixtures, fixtureMeta, fixtureOr404, effectiveStatus, fixtureView, byKickoff, inTenant,
  visibleLeagues, leagueTeams, leagueView, clubLeagueIds, clubCard,
};
