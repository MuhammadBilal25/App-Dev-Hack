'use strict';

// Demo content for the mobile app, applied after every reset on top of the Section 5.5 baseline.
// It lives in its own ids (`demo-*`, extra clubs, demo-only sports) so no /audit/v1 contract
// changes, and every fixture it creates is flagged `seeded` so the app can label it as demo data.
// Scores are appended through the normal event pipeline, so they are signed, persisted and
// projected exactly like graded events. Positions and scoring events come from sport configs.
const { state } = require('./state');
const scoring = require('./services/scoring');
const roster = require('./services/roster');
const sports = require('./services/sports');
const schedule = require('./services/schedule');
const { addDays, today } = require('./lib/validate');

const DEMO_LEAGUE = 'league-alpha-1';
const VOLLEY_LEAGUE = 'league-alpha-volley';

// Extra sports shown in the directory. Marked demo: creating a sport with one of these ids
// through POST /audit/v1/sports replaces it (and its demo leagues) instead of failing.
const DEMO_SPORTS = [
  {
    config: {
      sport_id: 'hockey', name: 'Hockey', scoring_model: 'event', periods: { count: 4, duration_minutes: 15 },
      scoring_events: { field_goal: { points: 1 }, penalty_stroke: { points: 1 } }, draw_allowed: true, overtime: { policy: 'shootout' },
      roster: { min_squad_size: 11, max_squad_size: 22, required_positions: { gk: 1 } },
    },
    meta: { description: 'Four 15-minute quarters. Field goals and penalty strokes; shoot-outs settle knockout ties.', icon: 'hockey' },
  },
  {
    config: {
      sport_id: 'volleyball', name: 'Volleyball', scoring_model: 'round', periods: { best_of: 5 },
      scoring_events: { set_won: { rounds: 1 } }, draw_allowed: false, overtime: { policy: 'none' },
      roster: { min_squad_size: 6, max_squad_size: 14, required_positions: { libero: 1 } },
    },
    meta: { description: 'Best of five sets. Each set won is recorded as it ends; first to three sets wins.', icon: 'volleyball' },
  },
  {
    config: {
      sport_id: 'tennis', name: 'Tennis', scoring_model: 'round', periods: { best_of: 3 },
      scoring_events: { set_won: { rounds: 1 } }, draw_allowed: false, overtime: { policy: 'none' },
      roster: { min_squad_size: 1, max_squad_size: 4, required_positions: {} },
    },
    meta: { description: 'Best of three sets, recorded set by set (tie-breaks decide a set at 6-6).', icon: 'tennis' },
  },
  {
    config: {
      sport_id: 'badminton', name: 'Badminton', scoring_model: 'round', periods: { best_of: 3 },
      scoring_events: { game_won: { rounds: 1 } }, draw_allowed: false, overtime: { policy: 'none' },
      roster: { min_squad_size: 1, max_squad_size: 4, required_positions: {} },
    },
    meta: { description: 'Best of three games to 21, recorded game by game.', icon: 'badminton' },
  },
  {
    config: {
      sport_id: 'table_tennis', name: 'Table Tennis', scoring_model: 'round', periods: { best_of: 5 },
      scoring_events: { game_won: { rounds: 1 } }, draw_allowed: false, overtime: { policy: 'none' },
      roster: { min_squad_size: 1, max_squad_size: 4, required_positions: {} },
    },
    meta: { description: 'Best of five games to 11, recorded game by game.', icon: 'table_tennis' },
  },
];

const LEAGUE_META = {
  'league-alpha-1': {
    season: '2026', format: 'round_robin',
    description: 'The Alpha Sports flagship football league: four clubs, home and away rounds.',
    rules: ['Win 3 points, draw 1, loss 0', 'Top two qualify for the Alpha Cup final', 'Transfer window open until the end of the season'],
  },
  'league-alpha-2': {
    season: '2026', format: 'round_robin',
    description: 'Indoor basketball league for Alpha Sports clubs.',
    rules: ['Win 3 points, loss 0 (no draws)', 'Overtime breaks level scores'],
  },
  'league-beta-1': {
    season: '2026', format: 'round_robin',
    description: 'Beta Athletics T20 cricket cup.',
    rules: ['20 overs per side', 'Net run rate breaks ties on points'],
  },
};

const EXTRA_LEAGUES = [
  {
    league_id: VOLLEY_LEAGUE, tenant_id: 'tenant-alpha', name: 'Alpha Volleyball Cup', sport_id: 'volleyball',
    season: '2026', format: 'single_elim', description: 'Knockout cup: semi-finals and a final, best of five sets.',
    rules: ['Single elimination, seeded bracket', 'Best of five sets'],
  },
];

const EXTRA_CLUBS = [
  { club_id: 'club-alpha-3', tenant_id: 'tenant-alpha', league_id: DEMO_LEAGUE, name: 'Alpha Rovers', venue: ['Rovers Field', 33.6518, 73.0157], social: { x: '@alpharovers', instagram: '@alpharovers' }, colors: { primary: '#B91C1C', secondary: '#FDE68A' } },
  { club_id: 'club-alpha-4', tenant_id: 'tenant-alpha', league_id: DEMO_LEAGUE, name: 'Alpha United', venue: ['United Stadium', 33.7215, 73.0433], social: { x: '@alphautd' }, colors: { primary: '#111827', secondary: '#F59E0B' } },
  { club_id: 'club-alpha-5', tenant_id: 'tenant-alpha', league_id: 'league-alpha-2', name: 'Alpha Hoopers', venue: ['Hoopers Arena', 33.69, 73.05], social: { x: '@alphahoopers' }, colors: { primary: '#EA580C', secondary: '#1F2937' } },
  { club_id: 'club-alpha-6', tenant_id: 'tenant-alpha', league_id: 'league-alpha-2', name: 'Alpha Dunkers', venue: ['Dunk Dome', 33.71, 73.08], social: {}, colors: { primary: '#7C3AED', secondary: '#F3F4F6' } },
  { club_id: 'club-alpha-7', tenant_id: 'tenant-alpha', league_id: 'league-alpha-2', name: 'Alpha Rockets', venue: ['Rocket Court', 33.66, 73.02], social: {}, colors: { primary: '#0E7490', secondary: '#ECFEFF' } },
  { club_id: 'club-alpha-8', tenant_id: 'tenant-alpha', league_id: VOLLEY_LEAGUE, name: 'Alpha Spikers', venue: ['Spike Hall', 33.68, 73.04], social: {}, colors: { primary: '#2563EB', secondary: '#FACC15' } },
  { club_id: 'club-alpha-9', tenant_id: 'tenant-alpha', league_id: VOLLEY_LEAGUE, name: 'Alpha Blockers', venue: ['Block Centre', 33.7, 73.01], social: {}, colors: { primary: '#047857', secondary: '#FFFFFF' } },
  { club_id: 'club-alpha-10', tenant_id: 'tenant-alpha', league_id: VOLLEY_LEAGUE, name: 'Alpha Aces', venue: ['Ace Pavilion', 33.67, 73.07], social: {}, colors: { primary: '#BE185D', secondary: '#FCE7F3' } },
  { club_id: 'club-alpha-11', tenant_id: 'tenant-alpha', league_id: VOLLEY_LEAGUE, name: 'Alpha Setters', venue: ['Setters Gym', 33.72, 73.03], social: {}, colors: { primary: '#4338CA', secondary: '#E0E7FF' } },
  { club_id: 'club-beta-2', tenant_id: 'tenant-beta', league_id: 'league-beta-1', name: 'Beta Titans', venue: ['Titan Ground', 31.55, 74.34], social: { x: '@betatitans' }, colors: { primary: '#9A3412', secondary: '#FFEDD5' } },
];

const CLUB_EXTRAS = {
  'club-alpha-1': { description: 'Founded in 1998, the Falcons play fast, attacking football at Falcon Ground.', colors: { primary: '#1D4ED8', secondary: '#FFFFFF' } },
  'club-alpha-2': { description: 'The Lions: a community club known for its academy.', colors: { primary: '#B45309', secondary: '#FEF3C7' } },
  'club-beta-1': { description: 'Beta Athletics\' oldest cricket club.', colors: { primary: '#0F766E', secondary: '#CCFBF1' } },
};

const STAFF = (seed) => [
  { name: `${FIRST[seed % 12]} ${LAST[(seed + 4) % 12]}`, role: 'coach' },
  { name: `${FIRST[(seed + 5) % 12]} ${LAST[(seed + 9) % 12]}`, role: 'manager' },
  { name: `Dr. ${FIRST[(seed + 2) % 12]} ${LAST[(seed + 7) % 12]}`, role: 'physio' },
];

const FIRST = ['Ahmed', 'Zain', 'Hamza', 'Saad', 'Umer', 'Fahad', 'Asad', 'Talha', 'Haris', 'Danish', 'Rehan', 'Shoaib'];
const LAST = ['Khan', 'Malik', 'Butt', 'Chaudhry', 'Mirza', 'Qureshi', 'Siddiqui', 'Javed', 'Iqbal', 'Hashmi', 'Abbasi', 'Rana'];

// Demo squad positions per sport (data only; required positions are always covered).
const POSITION_SETS = {
  football: ['gk', 'df', 'df', 'df', 'mf', 'mf', 'mf', 'fw', 'fw', 'gk'],
  basketball: ['pg', 'sg', 'sf', 'pf', 'c', 'pg', 'sf', 'c'],
  cricket: ['batter', 'batter', 'batter', 'allrounder', 'allrounder', 'wicketkeeper', 'bowler', 'bowler', 'bowler', 'bowler', 'batter'],
  volleyball: ['setter', 'libero', 'outside', 'outside', 'middle', 'middle', 'opposite', 'setter'],
};
const ROLES = ['captain', 'vice_captain', 'starter', 'starter', 'starter', 'starter', 'starter', 'starter', 'substitute', 'substitute', 'substitute'];

function addPlayers(club, ci) {
  const sportId = state.leagues.get(club.league_id).sport_id;
  const positions = POSITION_SETS[sportId] || ['player', 'player', 'player', 'player', 'player', 'player'];
  const existing = [...state.players.values()].filter((p) => p.club_id === club.club_id);
  const hasCaptain = existing.some((p) => p.role === 'captain');
  for (let i = 0; i < positions.length - existing.length; i++) {
    const n = ci * 10 + i;
    const id = `${club.club_id.replace('club', 'player')}-${String(i + 2).padStart(2, '0')}`;
    let role = ROLES[i + existing.length] || 'substitute';
    if (role === 'captain' && hasCaptain) role = 'starter';
    state.players.set(id, {
      player_id: id,
      club_id: club.club_id,
      tenant_id: club.tenant_id,
      name: `${FIRST[n % FIRST.length]} ${LAST[(n * 7 + 3) % LAST.length]}`,
      position: positions[i + existing.length],
      role,
      shirt: i + existing.length + 1,
    });
  }
}

// Store products: [id, club, category, name, description, price, sale, variants [size, color, stock], age in days].
const DEMO_PRODUCTS = [
  ['prod-demo-away', 'club-alpha-1', 'apparel', 'Alpha Falcons Away Jersey', 'Official 2026 away shirt in white with blue trim. Breathable match fabric.', 420000, 357000,
    [['S', 'White', 4], ['M', 'White', 6], ['L', 'White', 2], ['XL', 'White', 0]], 1],
  ['prod-demo-cap', 'club-alpha-1', 'caps', 'Falcons Snapback Cap', 'Embroidered crest, adjustable snapback. One size.', 180000, null, [[null, 'Navy', 8], [null, 'White', 3]], 3],
  ['prod-demo-pass', 'club-alpha-1', 'digital', 'Season Highlights Pass', 'Digital pass: every Falcons match highlight of the 2026 season.', 50000, null, [[null, null, 999]], 6],
  ['prod-demo-lions-kit', 'club-alpha-2', 'training', 'Lions Training Kit', 'Training top and shorts set worn by the first team.', 300000, null, [['M', 'Gold', 5], ['L', 'Gold', 5]], 4],
  ['prod-demo-bottle', 'club-alpha-3', 'accessories', 'Rovers Water Bottle', 'Insulated 750 ml steel bottle with the Rovers crest.', 90000, null, [[null, null, 20]], 8],
  ['prod-demo-shorts', 'club-alpha-5', 'sportswear', 'Hoopers Game Shorts', 'Lightweight basketball shorts with side pockets.', 250000, null, [['S', 'Orange', 3], ['M', 'Orange', 7], ['L', 'Orange', 6]], 2],
  ['prod-demo-bag', 'club-alpha-8', 'bags', 'Spikers Kit Bag', 'Roomy duffel bag with a separate shoe compartment.', 350000, null, [[null, 'Blue', 2]], 5],
  ['prod-demo-beta-shirt', 'club-beta-1', 'apparel', 'Beta Strikers Cricket Shirt', 'Official T20 shirt of the Beta Strikers.', 400000, null, [['M', 'Teal', 6], ['L', 'Teal', 4]], 2],
];

const variantId = (pid, size, color) => `var-${pid.replace(/^prod-/, '')}-${[size, color].filter(Boolean).join('-') || 'std'}`.toLowerCase();

const DEMO_STOCK = Object.fromEntries(DEMO_PRODUCTS.flatMap(([pid, , , , , , , vs]) => vs.map(([s, c, n]) => [variantId(pid, s, c), n])));

const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

let evSeq = 0;
function append(matchId, type, payload) {
  evSeq += 1;
  const b = { event_id: `demo-ev-${evSeq}`, match_id: matchId, type, payload };
  scoring.commitEvent(b, scoring.checkEvent(b));
  return b.event_id;
}

function setupProducts() {
  const now = Date.now();
  // Baseline product: give it the production fields.
  const jersey = state.products.get('prod-jersey-001');
  Object.assign(jersey, { images: [], active: true, sport_id: null, price_schedule: [], created_at: iso(now - 10 * 86400000), updated_at: iso(now - 10 * 86400000) });
  for (const [pid, clubId, category, name, description, price, sale, vs, age] of DEMO_PRODUCTS) {
    const club = state.clubs.get(clubId);
    const at = iso(now - age * 86400000);
    const p = { product_id: pid, tenant_id: club.tenant_id, club_id: clubId, sport_id: null, name, description, category, images: [], price_schedule: [], active: true, created_at: at, updated_at: at, variants: [] };
    for (const [size, color] of vs) {
      const id = variantId(pid, size, color);
      p.variants.push({ variant_id: id, sku: id.toUpperCase(), size, color, price_minor: price, sale_price_minor: sale, price_schedule: [], currency: 'PKR', active: true });
    }
    state.products.set(pid, p);
    for (const v of p.variants) state.variants.set(v.variant_id, { ...v, product_id: pid, tenant_id: p.tenant_id });
  }
  // One variant object per id, shared by the product and the variant index.
  for (const p of state.products.values()) p.variants = p.variants.map((v) => state.variants.get(v.variant_id));
}

function setupSports() {
  for (const { config, meta } of DEMO_SPORTS) {
    state.sports.set(config.sport_id, { ...JSON.parse(JSON.stringify(config)), tie_break_order: ['h2h_points', 'h2h_diff', 'overall_diff', 'scored', 'fair_play', 'draw_lots'] });
    state.sportMeta.set(config.sport_id, { ...meta, active: true, demo: true });
  }
}

function setupLeagues() {
  for (const [id, meta] of Object.entries(LEAGUE_META)) Object.assign(state.leagues.get(id), meta, { status: 'active' });
  for (const l of EXTRA_LEAGUES) state.leagues.set(l.league_id, { ...l, status: 'active', demo: true });
  for (const l of state.leagues.values()) {
    l.transfer_window = { open: addDays(today(), -30), close: addDays(today(), 60) };
    l.max_squad_size = state.sports.get(l.sport_id).roster.max_squad_size;
  }
}

function setupClubs() {
  for (const c of EXTRA_CLUBS) {
    const [name, lat, lng] = c.venue;
    state.clubs.set(c.club_id, {
      club_id: c.club_id, tenant_id: c.tenant_id, league_id: c.league_id, name: c.name, description: `${c.name}, competing in ${state.leagues.get(c.league_id).name}.`,
      colors: c.colors, logo_url: null, home_venue: { name, lat, lng }, social: c.social, staff: [],
    });
  }
  let i = 0;
  for (const c of state.clubs.values()) {
    Object.assign(c, { description: c.description || '', colors: c.colors || null, logo_url: null }, CLUB_EXTRAS[c.club_id] || {});
    if (!c.staff || c.staff.length < 3) c.staff = c.club_id === 'club-alpha-1' ? c.staff : STAFF(i * 3 + 1);
    i += 1;
  }
  [...state.clubs.values()].forEach(addPlayers);
}

function setupRosters() {
  // Squads = the clubs of each league, so transfers, loans and releases (and offline-sync roster
  // actions) work on the demo players. Squad size and required positions come from the sport.
  for (const l of state.leagues.values()) {
    const clubs = [...state.clubs.values()].filter((c) => c.league_id === l.league_id);
    if (!clubs.length) continue;
    roster.setup({
      league: { league_id: l.league_id, tenant_id: l.tenant_id, sport_id: l.sport_id, transfer_window: { ...l.transfer_window } },
      squads: clubs.map((c) => ({ squad_id: c.club_id, club_id: c.club_id, tenant_id: c.tenant_id })),
      players: [...state.players.values()]
        .filter((p) => clubs.some((c) => c.club_id === p.club_id))
        .map((p) => ({ player_id: p.player_id, name: p.name, position: p.position, role: p.role, squad_id: p.club_id })),
    });
  }
}

function setupStandingsLeagues() {
  state.leagueFixtures = new Map();
  state.prodLeagues = new Map();
  for (const l of state.leagues.values()) {
    const sport = state.sports.get(l.sport_id);
    state.leagueFixtures.set(l.league_id, []);
    state.prodLeagues.set(l.league_id, {
      league_id: l.league_id,
      sport_id: l.sport_id,
      teams: [...state.clubs.values()].filter((c) => c.league_id === l.league_id).map((c) => c.club_id),
      fixtures: [],
      points: sport.draw_allowed ? { win: 3, draw: 1, loss: 0 } : { win: 2, draw: 0, loss: 0 },
      tie_break_order: [...sport.tie_break_order],
      qualification_spots: 2,
      lots_seed: state.seed,
    });
  }
}

function setupFixtures() {
  const now = Date.now();
  const H = 3600 * 1000;
  const D = 24 * H;
  const fixture = (leagueId, f) => schedule.createFixture(state.leagues.get(leagueId), f, { seeded: true });
  // Future fixtures sit at fixed clock times (UTC) inside venue hours; past and live ones are
  // relative to now so one match is always in progress.
  const at = (days, time) => `${addDays(today(), days)}T${time}:00Z`;

  // Football (league-alpha-1): two rounds played, one live, three upcoming.
  const [a1, a2, a3, a4] = ['club-alpha-1', 'club-alpha-2', 'club-alpha-3', 'club-alpha-4'];
  [
    { match_id: 'demo-a1-r1-m1', round: 1, home: a1, away: a2, kickoff_at: iso(now - 2 * D) },
    { match_id: 'demo-a1-r1-m2', round: 1, home: a3, away: a4, kickoff_at: iso(now - 2 * D + 3 * H) },
    { match_id: 'demo-a1-r2-m1', round: 2, home: a1, away: a3, kickoff_at: iso(now - 67 * 60 * 1000) },
    { match_id: 'demo-a1-r2-m2', round: 2, home: a2, away: a4, kickoff_at: at(1, '15:00') },
    { match_id: 'demo-a1-r3-m1', round: 3, home: a4, away: a1, kickoff_at: at(7, '15:00') },
    { match_id: 'demo-a1-r3-m2', round: 3, home: a2, away: a3, kickoff_at: at(7, '18:00') },
  ].forEach((f) => fixture(DEMO_LEAGUE, f));

  const football = state.sports.get('football');
  const goal = Object.keys(football.scoring_events)[0];
  let m = 'demo-a1-r1-m1';
  append(m, 'match_start', {});
  append(m, 'score', { team_id: a1, event_type: goal, minute: 12, player_id: 'player-alpha-1-08' });
  append(m, 'score', { team_id: a2, event_type: goal, minute: 38 });
  append(m, 'discipline', { team_id: a2, points: -1, minute: 55 });
  append(m, 'score', { team_id: a1, event_type: goal, minute: 81, player_id: 'player-alpha-1-09' });
  append(m, 'match_end', {});
  m = 'demo-a1-r1-m2';
  append(m, 'match_start', {});
  append(m, 'match_end', {});
  // Round 2, live: 2-1 at 67', with one disallowed goal.
  m = 'demo-a1-r2-m1';
  append(m, 'match_start', {});
  append(m, 'score', { team_id: a1, event_type: goal, minute: 9, player_id: 'player-alpha-1-08' });
  const offside = append(m, 'score', { team_id: a3, event_type: goal, minute: 23 });
  append(m, 'compensation', { compensates: offside, reason: 'Offside (VAR)', minute: 25 });
  append(m, 'score', { team_id: a3, event_type: goal, minute: 41, player_id: 'player-alpha-3-09' });
  append(m, 'score', { team_id: a1, event_type: goal, minute: 64 });
  state.pinned.set(m, 'prod-jersey-001');

  // Basketball (league-alpha-2): one result, one live, one upcoming.
  const [h5, h6, h7] = ['club-alpha-5', 'club-alpha-6', 'club-alpha-7'];
  fixture('league-alpha-2', { match_id: 'demo-a2-r1-m1', round: 1, home: h5, away: h6, kickoff_at: iso(now - 3 * D) });
  fixture('league-alpha-2', { match_id: 'demo-a2-r2-m1', round: 2, home: h6, away: h7, kickoff_at: iso(now - 30 * 60 * 1000) });
  fixture('league-alpha-2', { match_id: 'demo-a2-r3-m1', round: 3, home: h7, away: h5, kickoff_at: at(4, '16:00') });
  const bb = Object.entries(state.sports.get('basketball').scoring_events).sort((x, y) => x[1].points - y[1].points).map(([k]) => k);
  m = 'demo-a2-r1-m1';
  append(m, 'match_start', {});
  for (const [team, k] of [[h5, 2], [h6, 1], [h5, 0], [h6, 2], [h5, 2], [h5, 1], [h6, 1]]) append(m, 'score', { team_id: team, event_type: bb[k] });
  append(m, 'match_end', {});
  m = 'demo-a2-r2-m1';
  append(m, 'match_start', {});
  for (const [team, k] of [[h6, 1], [h7, 2], [h6, 0]]) append(m, 'score', { team_id: team, event_type: bb[k] });

  // Cricket (league-beta-1): one completed T20, one upcoming.
  const [b1, b2] = ['club-beta-1', 'club-beta-2'];
  fixture('league-beta-1', { match_id: 'demo-b1-r1-m1', round: 1, home: b1, away: b2, kickoff_at: iso(now - 4 * D) });
  fixture('league-beta-1', { match_id: 'demo-b1-r2-m1', round: 2, home: b2, away: b1, kickoff_at: at(5, '10:00') });
  const cr = state.sports.get('cricket').scoring_events;
  const byRuns = (runs, wicket = false) => Object.keys(cr).find((k) => cr[k].runs === runs && cr[k].legal_ball && cr[k].wicket === wicket);
  m = 'demo-b1-r1-m1';
  append(m, 'match_start', {});
  for (const r of [4, 1, 0, 6, 1, 2, 4, 0, 1, 1, 6, 0]) append(m, 'score', { team_id: b1, event_type: byRuns(r) });
  append(m, 'score', { team_id: b1, event_type: byRuns(0, true) });
  for (const r of [1, 4, 0, 2, 1, 1, 0, 4, 1, 0]) append(m, 'score', { team_id: b2, event_type: byRuns(r) });
  append(m, 'score', { team_id: b2, event_type: byRuns(0, true) });
  append(m, 'match_end', {});

  // Volleyball cup (single elimination): semi-final 1 played, semi-final 2 upcoming.
  const volley = state.leagues.get(VOLLEY_LEAGUE);
  schedule.generate(volley, { start_date: addDays(today(), -1), kickoff_time: '16:00', interval_days: 3 });
  for (const f of state.leagueFixtures.get(VOLLEY_LEAGUE)) f.seeded = true;
  const [semi, semi2] = state.leagueFixtures.get(VOLLEY_LEAGUE);
  semi2.kickoff_at = at(1, '17:00');
  const set = Object.keys(state.sports.get('volleyball').scoring_events)[0];
  append(semi.match_id, 'match_start', {});
  for (const team of [semi.home, semi.away, semi.home, semi.home]) append(semi.match_id, 'score', { team_id: team, event_type: set });
  append(semi.match_id, 'match_end', {});
  schedule.syncBracket(volley);
}

function setupUsers() {
  state.users.get('organizer@nascon.test').league_ids = [DEMO_LEAGUE, VOLLEY_LEAGUE];
  const extra = [
    { user_id: 'user-organizer-beta', email: 'organizer.beta@nascon.test', role: 'league_organizer', name: 'Beta Organizer', tenant_id: 'tenant-beta', league_ids: ['league-beta-1'] },
    { user_id: 'user-manager-lions', email: 'lions.manager@nascon.test', role: 'club_manager', name: 'Lions Manager', tenant_id: 'tenant-alpha', club_id: 'club-alpha-2', store_access: false },
  ];
  for (const u of extra) state.users.set(u.email, { ...u, active: true });
}

// Removes a demo sport and everything the demo built on it, so a new sport can take its id.
function evictDemoSport(sportId) {
  for (const l of [...state.leagues.values()].filter((x) => x.sport_id === sportId && x.demo)) {
    const fixtures = state.leagueFixtures.get(l.league_id) || [];
    for (const f of fixtures) {
      const match = state.matches.get(f.match_id);
      if (match) for (const e of match.events) state.eventsById.delete(e.event_id);
      state.matches.delete(f.match_id);
      state.pinned.delete(f.match_id);
    }
    for (const c of [...state.clubs.values()].filter((x) => x.league_id === l.league_id)) {
      for (const p of [...state.players.values()].filter((x) => x.club_id === c.club_id)) state.players.delete(p.player_id);
      for (const p of [...state.products.values()].filter((x) => x.club_id === c.club_id)) p.active = false;
      state.clubs.delete(c.club_id);
    }
    state.rosterLeagues.delete(l.league_id);
    state.leagueFixtures.delete(l.league_id);
    state.prodLeagues.delete(l.league_id);
    state.leagues.delete(l.league_id);
    for (const u of state.users.values()) if (u.league_ids) u.league_ids = u.league_ids.filter((x) => x !== l.league_id);
  }
  state.sports.delete(sportId);
  state.sportMeta.delete(sportId);
}
sports.onDemoSportReplaced(evictDemoSport);

function applyDemo() {
  evSeq = 0;
  setupSports();
  setupLeagues();
  setupClubs();
  setupRosters();
  setupStandingsLeagues();
  setupProducts();
  setupFixtures();
  setupUsers();
}

module.exports = { applyDemo, DEMO_LEAGUE, DEMO_STOCK };
