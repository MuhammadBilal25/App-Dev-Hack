'use strict';

// Demo content for the mobile app, applied after every reset on top of the Section 5.5 baseline.
// It lives in its own maps and id space (`demo-*`, `club-alpha-3/4`) so no /audit/v1 contract
// changes. Scores are appended through the normal event pipeline, so they are signed, persisted
// and projected exactly like graded events. Nothing here branches on a sport: positions and
// scoring events come from the sport config.
const { state } = require('./state');
const scoring = require('./services/scoring');
const roster = require('./services/roster');
const { addDays, today } = require('./lib/validate');

const DEMO_LEAGUE = 'league-alpha-1';

const EXTRA_CLUBS = [
  {
    club_id: 'club-alpha-3', tenant_id: 'tenant-alpha', league_id: DEMO_LEAGUE, name: 'Alpha Rovers',
    home_venue: { name: 'Rovers Field', lat: 33.6518, lng: 73.0157 },
    social: { x: '@alpharovers', instagram: '@alpharovers' },
    staff: [],
  },
  {
    club_id: 'club-alpha-4', tenant_id: 'tenant-alpha', league_id: DEMO_LEAGUE, name: 'Alpha United',
    home_venue: { name: 'United Stadium', lat: 33.7215, lng: 73.0433 },
    social: { x: '@alphautd' },
    staff: [],
  },
];

const STAFF = {
  'club-alpha-1': null, // already has three in the seed
  'club-alpha-2': [{ name: 'Usman Tariq', role: 'coach' }, { name: 'Nadia Hussain', role: 'manager' }, { name: 'Dr. Faisal Mir', role: 'physio' }],
  'club-alpha-3': [{ name: 'Kamran Akmal', role: 'coach' }, { name: 'Hina Rauf', role: 'manager' }, { name: 'Dr. Saad Latif', role: 'physio' }],
  'club-alpha-4': [{ name: 'Junaid Iqbal', role: 'coach' }, { name: 'Maria Khan', role: 'manager' }, { name: 'Dr. Omar Sheikh', role: 'physio' }],
};

const FIRST = ['Ahmed', 'Zain', 'Hamza', 'Saad', 'Umer', 'Fahad', 'Asad', 'Talha', 'Haris', 'Danish', 'Rehan', 'Shoaib'];
const LAST = ['Khan', 'Malik', 'Butt', 'Chaudhry', 'Mirza', 'Qureshi', 'Siddiqui', 'Javed', 'Iqbal', 'Hashmi', 'Abbasi', 'Rana'];
// Football positions; a gk is required by the sport config's roster rules.
const POSITIONS = ['gk', 'df', 'df', 'df', 'mf', 'mf', 'mf', 'fw', 'fw', 'gk'];

function addPlayers(club, ci) {
  const existing = [...state.players.values()].filter((p) => p.club_id === club.club_id);
  const roles = ['captain', 'vice_captain', 'starter', 'starter', 'starter', 'starter', 'starter', 'starter', 'substitute', 'substitute'];
  const hasCaptain = existing.some((p) => p.role === 'captain');
  for (let i = 0; i < POSITIONS.length - existing.length; i++) {
    const n = ci * 10 + i;
    const id = `${club.club_id.replace('club', 'player')}-${String(i + 2).padStart(2, '0')}`;
    let role = roles[i + existing.length];
    if (role === 'captain' && hasCaptain) role = 'starter';
    state.players.set(id, {
      player_id: id,
      club_id: club.club_id,
      tenant_id: club.tenant_id,
      name: `${FIRST[n % FIRST.length]} ${LAST[(n * 7 + 3) % LAST.length]}`,
      position: POSITIONS[i + existing.length],
      role,
      shirt: i + existing.length + 1,
    });
  }
}

const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

let evSeq = 0;
function append(matchId, type, payload) {
  evSeq += 1;
  const b = { event_id: `demo-ev-${evSeq}`, match_id: matchId, type, payload };
  scoring.commitEvent(b, scoring.checkEvent(b));
  return b.event_id;
}

function applyDemo() {
  evSeq = 0;
  for (const c of EXTRA_CLUBS) state.clubs.set(c.club_id, JSON.parse(JSON.stringify(c)));
  for (const [id, staff] of Object.entries(STAFF)) if (staff) state.clubs.get(id).staff = staff.map((s) => ({ ...s }));
  const demoClubs = [...state.clubs.values()].filter((c) => c.league_id === DEMO_LEAGUE);
  demoClubs.forEach(addPlayers);

  // Squads = the demo clubs, so transfers, loans and releases (and offline-sync roster actions)
  // work on the demo players. Squad size and required positions come from the sport config.
  roster.setup({
    league: {
      league_id: DEMO_LEAGUE,
      tenant_id: 'tenant-alpha',
      sport_id: state.leagues.get(DEMO_LEAGUE).sport_id,
      transfer_window: { open: addDays(today(), -30), close: addDays(today(), 60) },
    },
    squads: demoClubs.map((c) => ({ squad_id: c.club_id, club_id: c.club_id, tenant_id: c.tenant_id })),
    players: [...state.players.values()]
      .filter((p) => demoClubs.some((c) => c.club_id === p.club_id))
      .map((p) => ({ player_id: p.player_id, name: p.name, position: p.position, role: p.role, squad_id: p.club_id })),
  });

  const now = Date.now();
  const H = 3600 * 1000;
  const D = 24 * H;
  const [a1, a2, a3, a4] = ['club-alpha-1', 'club-alpha-2', 'club-alpha-3', 'club-alpha-4'];
  const fx = [
    { match_id: 'demo-a1-r1-m1', round: 1, home: a1, away: a2, kickoff_at: iso(now - 2 * D) },
    { match_id: 'demo-a1-r1-m2', round: 1, home: a3, away: a4, kickoff_at: iso(now - 2 * D + 3 * H) },
    { match_id: 'demo-a1-r2-m1', round: 2, home: a1, away: a3, kickoff_at: iso(now - 67 * 60 * 1000) },
    { match_id: 'demo-a1-r2-m2', round: 2, home: a2, away: a4, kickoff_at: iso(now + 3 * H) },
    { match_id: 'demo-a1-r3-m1', round: 3, home: a4, away: a1, kickoff_at: iso(now + 7 * D) },
    { match_id: 'demo-a1-r3-m2', round: 3, home: a2, away: a3, kickoff_at: iso(now + 7 * D + 3 * H) },
  ].map((f) => ({ ...f, league_id: DEMO_LEAGUE, venue: state.clubs.get(f.home).home_venue.name }));

  state.leagueFixtures = new Map();
  state.prodLeagues = new Map();
  for (const l of state.leagues.values()) {
    const sport = state.sports.get(l.sport_id);
    const fixtures = l.league_id === DEMO_LEAGUE ? fx : [];
    state.leagueFixtures.set(l.league_id, fixtures);
    state.prodLeagues.set(l.league_id, {
      league_id: l.league_id,
      sport_id: l.sport_id,
      teams: [...state.clubs.values()].filter((c) => c.league_id === l.league_id).map((c) => c.club_id),
      fixtures: fixtures.map((f) => ({ match_id: f.match_id, home: f.home, away: f.away })),
      points: { win: 3, draw: 1, loss: 0 },
      tie_break_order: [...sport.tie_break_order],
      qualification_spots: 2,
      lots_seed: state.seed,
    });
  }

  const goal = Object.keys(state.sports.get('football').scoring_events)[0];
  for (const f of fx) {
    append(f.match_id, 'match_init', { sport_id: 'football', league_id: DEMO_LEAGUE, home_team_id: f.home, away_team_id: f.away });
  }
  // Round 1: 2-1 and a goalless draw.
  let m = 'demo-a1-r1-m1';
  append(m, 'match_start', {});
  append(m, 'score', { team_id: a1, event_type: goal, minute: 12 });
  append(m, 'score', { team_id: a2, event_type: goal, minute: 38 });
  append(m, 'discipline', { team_id: a2, points: -1, minute: 55 });
  append(m, 'score', { team_id: a1, event_type: goal, minute: 81 });
  append(m, 'match_end', {});
  m = 'demo-a1-r1-m2';
  append(m, 'match_start', {});
  append(m, 'match_end', {});
  // Round 2, live: 2-1 at 67', with one disallowed goal.
  m = 'demo-a1-r2-m1';
  append(m, 'match_start', {});
  append(m, 'score', { team_id: a1, event_type: goal, minute: 9 });
  const offside = append(m, 'score', { team_id: a3, event_type: goal, minute: 23 });
  append(m, 'compensation', { compensates: offside, reason: 'Offside (VAR)', minute: 25 });
  append(m, 'score', { team_id: a3, event_type: goal, minute: 41 });
  append(m, 'score', { team_id: a1, event_type: goal, minute: 64 });
  state.pinned.set(m, 'prod-jersey-001');
}

module.exports = { applyDemo, DEMO_LEAGUE };
