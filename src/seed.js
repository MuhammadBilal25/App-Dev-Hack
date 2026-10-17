'use strict';

// Baseline data re-created by every POST /audit/v1/reset (Section 5.5). Sports are plain data
// using the same schema as POST /audit/v1/sports -- the engines never branch on these ids.

const FULL_TIE_BREAK = ['h2h_points', 'h2h_diff', 'overall_diff', 'scored', 'fair_play', 'draw_lots'];

const SPORTS = [
  {
    sport_id: 'football',
    name: 'Football',
    scoring_model: 'event',
    periods: { count: 2, duration_minutes: 45 },
    scoring_events: { goal: { points: 1 } },
    draw_allowed: true,
    overtime: { policy: 'none' },
    tie_break_order: FULL_TIE_BREAK,
    roster: { min_squad_size: 11, max_squad_size: 25, required_positions: { gk: 1 } },
  },
  {
    sport_id: 'basketball',
    name: 'Basketball',
    scoring_model: 'event',
    periods: { count: 4, duration_minutes: 12 },
    scoring_events: {
      free_throw: { points: 1 },
      two_pointer: { points: 2 },
      three_pointer: { points: 3 },
    },
    draw_allowed: false,
    overtime: { policy: 'extra_time', duration_minutes: 5 },
    tie_break_order: FULL_TIE_BREAK,
    roster: { min_squad_size: 5, max_squad_size: 15, required_positions: {} },
  },
  {
    sport_id: 'cricket',
    name: 'Cricket',
    scoring_model: 'innings',
    periods: { innings_per_team: 1, overs_per_innings: 20, balls_per_over: 6, wickets_per_innings: 10 },
    scoring_events: {
      dot_ball: { runs: 0, legal_ball: true, wicket: false },
      single: { runs: 1, legal_ball: true, wicket: false },
      two: { runs: 2, legal_ball: true, wicket: false },
      four: { runs: 4, legal_ball: true, wicket: false },
      six: { runs: 6, legal_ball: true, wicket: false },
      wide: { runs: 1, legal_ball: false, wicket: false },
      no_ball: { runs: 1, legal_ball: false, wicket: false },
      wicket: { runs: 0, legal_ball: true, wicket: true },
    },
    draw_allowed: true,
    overtime: { policy: 'super_over' },
    tie_break_order: FULL_TIE_BREAK,
    roster: { min_squad_size: 11, max_squad_size: 18, required_positions: { wicketkeeper: 1 } },
  },
  {
    sport_id: 'esports',
    name: 'Esports',
    scoring_model: 'round',
    periods: { best_of: 3 },
    scoring_events: { round_win: { rounds: 1 } },
    draw_allowed: false,
    overtime: { policy: 'none' },
    tie_break_order: FULL_TIE_BREAK,
    roster: { min_squad_size: 5, max_squad_size: 8, required_positions: {} },
  },
];

const TENANTS = [
  { tenant_id: 'tenant-alpha', name: 'Alpha Sports', logo_url: null, colors: { primary: '#1E5EFF', secondary: '#0B1F4D' } },
  { tenant_id: 'tenant-beta', name: 'Beta Athletics', logo_url: null, colors: { primary: '#E4572E', secondary: '#3B1F0B' } },
];

const LEAGUES = [
  { league_id: 'league-alpha-1', tenant_id: 'tenant-alpha', name: 'Alpha Premier League', sport_id: 'football' },
  { league_id: 'league-alpha-2', tenant_id: 'tenant-alpha', name: 'Alpha Hoops League', sport_id: 'basketball' },
  { league_id: 'league-beta-1', tenant_id: 'tenant-beta', name: 'Beta Cricket Cup', sport_id: 'cricket' },
];

const CLUBS = [
  {
    club_id: 'club-alpha-1', tenant_id: 'tenant-alpha', league_id: 'league-alpha-1', name: 'Alpha Falcons FC',
    home_venue: { name: 'Falcon Ground', lat: 33.6844, lng: 73.0479 },
    social: { x: '@alphafalcons', instagram: '@alphafalcons' },
    staff: [
      { name: 'Imran Qureshi', role: 'coach' },
      { name: 'Sara Ahmed', role: 'manager' },
      { name: 'Dr. Hamza Ali', role: 'physio' },
    ],
  },
  {
    club_id: 'club-alpha-2', tenant_id: 'tenant-alpha', league_id: 'league-alpha-1', name: 'Alpha Lions FC',
    home_venue: { name: 'Lion Park', lat: 33.7, lng: 73.06 },
    social: { x: '@alphalions' },
    staff: [{ name: 'Usman Tariq', role: 'coach' }],
  },
  {
    club_id: 'club-beta-1', tenant_id: 'tenant-beta', league_id: 'league-beta-1', name: 'Beta Strikers',
    home_venue: { name: 'Beta Oval', lat: 31.52, lng: 74.35 },
    social: {},
    staff: [{ name: 'Ayesha Khan', role: 'coach' }],
  },
];

const PLAYERS = [
  { player_id: 'player-alpha-1', club_id: 'club-alpha-1', tenant_id: 'tenant-alpha', name: 'Ali Raza', position: 'gk', role: 'captain' },
  { player_id: 'player-alpha-2', club_id: 'club-alpha-2', tenant_id: 'tenant-alpha', name: 'Bilal Shah', position: 'fw', role: 'starter' },
  { player_id: 'player-beta-1', club_id: 'club-beta-1', tenant_id: 'tenant-beta', name: 'Hassan Javed', position: 'batter', role: 'starter' },
];

const DEMO_PASSWORD = 'Nascon@26';

const USERS = [
  { user_id: 'user-super-admin', email: 'admin@nascon.test', role: 'super_admin', name: 'Platform Admin', tenant_id: null },
  { user_id: 'user-organizer', email: 'organizer@nascon.test', role: 'league_organizer', name: 'League Organizer', tenant_id: 'tenant-alpha', league_ids: ['league-alpha-1'] },
  { user_id: 'user-manager', email: 'manager@nascon.test', role: 'club_manager', name: 'Club Manager', tenant_id: 'tenant-alpha', club_id: 'club-alpha-1' },
  { user_id: 'user-player', email: 'player@nascon.test', role: 'player', name: 'Ali Raza', tenant_id: 'tenant-alpha', player_id: 'player-alpha-1', club_id: 'club-alpha-1' },
  { user_id: 'user-viewer', email: 'viewer@nascon.test', role: 'viewer', name: 'Guest Viewer', tenant_id: 'tenant-alpha' },
];

const PRODUCTS = [
  {
    product_id: 'prod-jersey-001',
    tenant_id: 'tenant-alpha',
    club_id: 'club-alpha-1',
    name: 'Alpha Falcons Home Jersey',
    category: 'apparel',
    description: 'Official 2026 home jersey.',
    variants: [
      { variant_id: 'var-jersey-001-M', size: 'M', color: 'blue', price_minor: 450000, currency: 'PKR' },
      { variant_id: 'var-jersey-001-L', size: 'L', color: 'blue', price_minor: 450000, currency: 'PKR' },
    ],
  },
];

const DEFAULT_STOCK = { 'var-jersey-001-M': 1, 'var-jersey-001-L': 5 };

const DISCOUNTS = { WELCOME10: { percent: 10 } };

module.exports = {
  FULL_TIE_BREAK, SPORTS, TENANTS, LEAGUES, CLUBS, PLAYERS, USERS, DEMO_PASSWORD, PRODUCTS, DEFAULT_STOCK, DISCOUNTS,
};
