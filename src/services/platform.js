'use strict';

// Platform administration (Super-Admin, plus the scoped parts other roles may do): sports
// configuration and directory, tenants and branding, leagues and seasons, clubs and league
// membership, users and role assignments, platform settings, store categories and discount codes.
// Callers authorize first (routes); this module validates and applies.
const { state, clone } = require('../state');
const { err, validation } = require('../lib/errors');
const { isObj, isInt, isStr, isBool, isId, isDate, addDays, today } = require('../lib/validate');
const sports = require('./sports');
const roster = require('./roster');
const views = require('./views');
const schedule = require('./schedule');
const auth = require('./auth');
const { nextId } = require('../lib/activity');

const HEX_RE = /^#[0-9A-Fa-f]{6}$/;
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,}$/;
const ROLES = ['super_admin', 'league_organizer', 'club_manager', 'player', 'viewer'];
const LEAGUE_STATUSES = ['active', 'completed', 'archived'];

const label = (key) => key.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
const str = (v, max) => isStr(v) && v.trim().length >= 1 && v.length <= max;

function slug(name, prefix, taken) {
  const base = `${prefix}-${name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'item'}`;
  let id = base;
  for (let n = 2; taken(id); n++) id = `${base}-${n}`;
  return id;
}

// ---------------------------------------------------------------------------------------------
// Sports
// ---------------------------------------------------------------------------------------------

// Plain-language summary of a sport's rules, generated from its config (any sport, any model).
function describeRules(sport) {
  const p = sport.periods;
  const lines = [];
  if (sport.scoring_model === 'event') {
    lines.push(`${plural(p.count, 'period')} of ${p.duration_minutes} minutes`);
    for (const [k, v] of Object.entries(sport.scoring_events)) lines.push(`${label(k)}: ${plural(v.points, 'point')}`);
  } else if (sport.scoring_model === 'innings') {
    lines.push(`${plural(p.innings_per_team, 'innings')} per side, ${p.overs_per_innings} overs of ${p.balls_per_over} balls, ${plural(p.wickets_per_innings, 'wicket')}`);
    for (const [k, v] of Object.entries(sport.scoring_events)) {
      lines.push(`${label(k)}: ${plural(v.runs, 'run')}${v.legal_ball ? '' : ' (extra, ball re-bowled)'}${v.wicket ? ', wicket' : ''}`);
    }
  } else {
    lines.push(`Best of ${p.best_of}: first to ${(p.best_of + 1) / 2} wins`);
    for (const [k, v] of Object.entries(sport.scoring_events)) lines.push(`${label(k)}: counts ${v.rounds}`);
  }
  lines.push(sport.draw_allowed ? 'Draws are allowed' : 'No draws: a winner is required');
  if (sport.overtime && sport.overtime.policy !== 'none') {
    lines.push(`Level scores: ${label(sport.overtime.policy)}${sport.overtime.duration_minutes ? ` (${sport.overtime.duration_minutes} min)` : ''}`);
  }
  const r = sport.roster;
  const req = Object.entries(r.required_positions || {}).filter(([, n]) => n > 0).map(([pos, n]) => `${n} ${pos}`);
  lines.push(`Squad of ${r.min_squad_size}-${r.max_squad_size} players${req.length ? `, at least ${req.join(', ')}` : ''}`);
  return lines;
}

function sportView(sport, user) {
  const meta = state.sportMeta.get(sport.sport_id) || { active: true };
  const leagues = views.visibleLeagues(user).filter((l) => l.sport_id === sport.sport_id);
  const fixtures = leagues.flatMap((l) => state.leagueFixtures.get(l.league_id) || []);
  const status = fixtures.map((f) => views.effectiveStatus(f));
  const clubs = new Set(leagues.flatMap((l) => views.leagueTeams(l.league_id)));
  return {
    ...clone(sport),
    description: meta.description || '',
    icon: meta.icon || 'trophy',
    active: meta.active !== false,
    demo: !!meta.demo,
    rules_summary: describeRules(sport),
    league_count: leagues.length,
    club_count: clubs.size,
    live_count: status.filter((s) => s === 'in_progress').length,
    upcoming_count: status.filter((s) => s === 'upcoming').length,
    completed_count: status.filter((s) => s === 'completed').length,
  };
}

const sportActive = (id) => (state.sportMeta.get(id) || { active: true }).active !== false;

function listSports(user) {
  return [...state.sports.values()]
    .filter((s) => user.role === 'super_admin' || sportActive(s.sport_id))
    .map((s) => sportView(s, user));
}

function sportDetail(user, sportId) {
  const sport = state.sports.get(sportId);
  if (!sport || (user.role !== 'super_admin' && !sportActive(sportId))) {
    throw err(404, 'SPORT_NOT_FOUND', `Sport ${sportId} does not exist.`, { sport_id: sportId });
  }
  const leagues = views.visibleLeagues(user).filter((l) => l.sport_id === sportId);
  const fixtures = leagues.flatMap((l) => state.leagueFixtures.get(l.league_id) || []).map(views.fixtureView).sort(views.byKickoff);
  const clubs = [...new Set(leagues.flatMap((l) => views.leagueTeams(l.league_id)))].map((id) => state.clubs.get(id)).filter(Boolean);
  return {
    sport: sportView(sport, user),
    leagues: leagues.map(views.leagueView),
    live: fixtures.filter((f) => f.status === 'in_progress'),
    upcoming: fixtures.filter((f) => f.status === 'upcoming').slice(0, 20),
    completed: fixtures.filter((f) => f.status === 'completed').reverse().slice(0, 20),
    clubs: clubs.map(views.clubCard),
  };
}

function validateMeta(b, bad) {
  if (b.description !== undefined && !(isStr(b.description) && b.description.length <= 500)) bad.push('description');
  if (b.icon !== undefined && !(isStr(b.icon) && /^[a-z0-9_]{1,30}$/.test(b.icon))) bad.push('icon');
  if (b.active !== undefined && !isBool(b.active)) bad.push('active');
}

const RULE_FIELDS = ['sport_id', 'name', 'scoring_model', 'periods', 'scoring_events', 'draw_allowed', 'overtime', 'tie_break_order', 'roster'];
const pick = (b, fields) => Object.fromEntries(fields.filter((f) => b[f] !== undefined).map((f) => [f, b[f]]));

function createSport(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateMeta(b, bad);
  if (bad.length) throw validation(bad);
  const r = sports.createSport(pick(b, RULE_FIELDS));
  state.sportMeta.set(r.body.sport_id, { description: b.description || '', icon: b.icon || 'trophy', active: b.active !== false });
  return sportView(state.sports.get(r.body.sport_id), { role: 'super_admin' });
}

const sportInUse = (id) => [...state.leagues.values()].some((l) => l.sport_id === id) || [...state.matches.values()].some((m) => m.sport_id === id);

function updateSport(sportId, b) {
  const sport = sports.getSport(sportId);
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateMeta(b, bad);
  if (b.name !== undefined && !str(b.name, 80)) bad.push('name');
  if (b.rules !== undefined && !isObj(b.rules)) bad.push('rules');
  if (bad.length) throw validation(bad);
  if (b.rules) {
    if (sportInUse(sportId)) throw err(409, 'SPORT_IN_USE', `Sport ${sportId} has leagues or matches; its scoring rules can no longer change.`, { sport_id: sportId });
    const next = { ...clone(sport), ...pick(b.rules, RULE_FIELDS.filter((f) => f !== 'sport_id')), sport_id: sportId };
    sports.validateSport(next);
    state.sports.set(sportId, { ...next, tie_break_order: next.tie_break_order || clone(sport.tie_break_order) });
  }
  if (b.name !== undefined) state.sports.get(sportId).name = b.name.trim();
  const meta = state.sportMeta.get(sportId) || { active: true };
  for (const k of ['description', 'icon', 'active']) if (b[k] !== undefined) meta[k] = b[k];
  state.sportMeta.set(sportId, meta);
  return sportView(state.sports.get(sportId), { role: 'super_admin' });
}

// ---------------------------------------------------------------------------------------------
// Tenants and branding
// ---------------------------------------------------------------------------------------------
function tenantOr404(id) {
  const t = state.tenants.get(id);
  if (!t) throw err(404, 'TENANT_NOT_FOUND', `Tenant ${id} does not exist.`, { tenant_id: id });
  return t;
}

function validateColors(c, bad) {
  if (c === undefined) return;
  if (!isObj(c) || ['primary', 'secondary', 'dark'].some((k) => c[k] !== undefined && c[k] !== null && !(isStr(c[k]) && HEX_RE.test(c[k])))) bad.push('colors');
}

function tenantView(t) {
  return {
    ...clone(t),
    league_count: [...state.leagues.values()].filter((l) => l.tenant_id === t.tenant_id).length,
    club_count: [...state.clubs.values()].filter((c) => c.tenant_id === t.tenant_id).length,
    user_count: [...state.users.values()].filter((u) => u.tenant_id === t.tenant_id).length,
  };
}

function createTenant(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!str(b.name, 80)) bad.push('name');
  if (b.tenant_id !== undefined && !isId(b.tenant_id)) bad.push('tenant_id');
  validateColors(b.colors, bad);
  if (bad.length) throw validation(bad);
  const id = b.tenant_id || slug(b.name, 'tenant', (x) => state.tenants.has(x));
  if (state.tenants.has(id)) throw err(409, 'TENANT_EXISTS', `Tenant ${id} already exists.`, { tenant_id: id });
  const t = { tenant_id: id, name: b.name.trim(), logo_url: null, colors: { primary: '#1D4ED8', secondary: '#0B1F4D', ...(b.colors || {}) }, brand_custom: true };
  state.tenants.set(id, t);
  return tenantView(t);
}

function updateTenant(id, b) {
  const t = tenantOr404(id);
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (b.name !== undefined && !str(b.name, 80)) bad.push('name');
  validateColors(b.colors, bad);
  if (bad.length) throw validation(bad);
  if (b.name !== undefined) t.name = b.name.trim();
  if (b.colors) {
    t.colors = { ...t.colors, ...b.colors };
    t.brand_custom = true;
  }
  return tenantView(t);
}

// ---------------------------------------------------------------------------------------------
// Leagues and seasons
// ---------------------------------------------------------------------------------------------
function leagueOr404(id) {
  const l = state.leagues.get(id);
  if (!l) throw err(404, 'LEAGUE_NOT_FOUND', `League ${id} does not exist.`, { league_id: id });
  return l;
}

function validateLeagueFields(b, bad, creating) {
  if ((creating || b.name !== undefined) && !str(b.name, 80)) bad.push('name');
  if (b.season !== undefined && !str(b.season, 20)) bad.push('season');
  if (b.description !== undefined && !(isStr(b.description) && b.description.length <= 1000)) bad.push('description');
  if (b.rules !== undefined && !(Array.isArray(b.rules) && b.rules.length <= 30 && b.rules.every((r) => str(r, 200)))) bad.push('rules');
  if (b.points !== undefined && !(isObj(b.points) && ['win', 'draw', 'loss'].every((k) => isInt(b.points[k]) && b.points[k] >= 0 && b.points[k] <= 10))) bad.push('points');
  if (b.qualification_spots !== undefined && !(isInt(b.qualification_spots) && b.qualification_spots >= 1 && b.qualification_spots <= 64)) bad.push('qualification_spots');
  const w = b.transfer_window;
  if (w !== undefined && !(isObj(w) && isDate(w.open) && isDate(w.close) && w.open <= w.close)) bad.push('transfer_window');
  if (b.max_squad_size !== undefined && !(isInt(b.max_squad_size) && b.max_squad_size >= 1 && b.max_squad_size <= 200)) bad.push('max_squad_size');
}

function createLeague(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateLeagueFields(b, bad, true);
  if (b.league_id !== undefined && !isId(b.league_id)) bad.push('league_id');
  if (!isId(b.tenant_id)) bad.push('tenant_id');
  if (!isStr(b.sport_id)) bad.push('sport_id');
  if (b.format !== undefined && !schedule.FORMATS.includes(b.format)) bad.push('format');
  if (bad.length) throw validation(bad);
  tenantOr404(b.tenant_id);
  const sport = sports.getSport(b.sport_id);
  if (!sportActive(sport.sport_id)) throw err(409, 'SPORT_INACTIVE', `Sport ${sport.sport_id} is deactivated.`, { sport_id: sport.sport_id });
  const id = b.league_id || slug(b.name, 'league', (x) => state.leagues.has(x));
  if (state.leagues.has(id)) throw err(409, 'LEAGUE_EXISTS', `League ${id} already exists.`, { league_id: id });

  const league = {
    league_id: id,
    tenant_id: b.tenant_id,
    name: b.name.trim(),
    sport_id: sport.sport_id,
    season: b.season || String(new Date().getUTCFullYear()),
    format: b.format || 'round_robin',
    status: 'active',
    description: b.description || '',
    rules: b.rules ? [...b.rules] : [],
    transfer_window: b.transfer_window ? clone(b.transfer_window) : { open: addDays(today(), -30), close: addDays(today(), 60) },
    max_squad_size: b.max_squad_size || sport.roster.max_squad_size,
  };
  state.leagues.set(id, league);
  state.leagueFixtures.set(id, []);
  state.prodLeagues.set(id, {
    league_id: id,
    sport_id: sport.sport_id,
    teams: [],
    fixtures: [],
    points: b.points ? clone(b.points) : { win: 3, draw: 1, loss: 0 },
    tie_break_order: [...sport.tie_break_order],
    qualification_spots: b.qualification_spots || 2,
    lots_seed: state.seed,
  });
  return views.leagueView(league);
}

function updateLeague(id, b) {
  const league = leagueOr404(id);
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateLeagueFields(b, bad, false);
  if (b.status !== undefined && !LEAGUE_STATUSES.includes(b.status)) bad.push('status');
  if (bad.length) throw validation(bad);
  const pl = state.prodLeagues.get(id);
  for (const k of ['season', 'status', 'description']) if (b[k] !== undefined) league[k] = b[k];
  if (b.name !== undefined) league.name = b.name.trim();
  if (b.rules !== undefined) league.rules = [...b.rules];
  if (b.points !== undefined) pl.points = clone(b.points);
  if (b.qualification_spots !== undefined) pl.qualification_spots = Math.min(b.qualification_spots, Math.max(1, pl.teams.length || b.qualification_spots));
  const rl = state.rosterLeagues.get(id);
  if (b.transfer_window !== undefined) {
    league.transfer_window = clone(b.transfer_window);
    if (rl) rl.transfer_window = clone(b.transfer_window);
  }
  if (b.max_squad_size !== undefined) {
    league.max_squad_size = b.max_squad_size;
    if (rl) rl.max_squad_size = b.max_squad_size;
  }
  return views.leagueView(league);
}

function userOr404(id) {
  const u = [...state.users.values()].find((x) => x.user_id === id);
  if (!u) throw err(404, 'USER_NOT_FOUND', `User ${id} does not exist.`, { user_id: id });
  return u;
}

function assignOrganizer(leagueId, b) {
  const league = leagueOr404(leagueId);
  if (!isObj(b) || !isStr(b.user_id)) throw validation(['user_id']);
  const u = userOr404(b.user_id);
  if (u.role !== 'league_organizer') throw err(409, 'ROLE_MISMATCH', `${u.email} is not a League Organizer.`, { user_id: u.user_id, role: u.role });
  if (u.tenant_id !== league.tenant_id) throw err(409, 'CROSS_TENANT_ASSIGNMENT', 'The organizer belongs to another tenant.', { user_id: u.user_id, league_id: leagueId });
  u.league_ids = [...new Set([...(u.league_ids || []), leagueId])];
  return views.leagueView(league);
}

function unassignOrganizer(leagueId, userId) {
  const league = leagueOr404(leagueId);
  const u = userOr404(userId);
  u.league_ids = (u.league_ids || []).filter((x) => x !== leagueId);
  return views.leagueView(league);
}

// Enters an existing club (same tenant, same sport) into another league or cup.
function addLeagueClub(leagueId, b) {
  const league = leagueOr404(leagueId);
  if (!isObj(b) || !isStr(b.club_id)) throw validation(['club_id']);
  const club = clubOr404(b.club_id);
  if (club.tenant_id !== league.tenant_id) throw err(409, 'CROSS_TENANT_ASSIGNMENT', 'The club belongs to another tenant.', { club_id: club.club_id });
  const home = state.leagues.get(club.league_id);
  if (home && home.sport_id !== league.sport_id) throw err(409, 'SPORT_MISMATCH', 'The club plays a different sport.', { club_id: club.club_id, sport_id: home.sport_id });
  const pl = state.prodLeagues.get(leagueId);
  if (!pl.teams.includes(club.club_id)) pl.teams.push(club.club_id);
  return views.leagueView(league);
}

function removeLeagueClub(leagueId, clubId) {
  const league = leagueOr404(leagueId);
  const pl = state.prodLeagues.get(leagueId);
  if (!pl.teams.includes(clubId)) throw err(404, 'CLUB_NOT_FOUND', `Club ${clubId} is not in ${leagueId}.`, { club_id: clubId });
  if (club404(clubId) && club404(clubId).league_id === leagueId) throw err(409, 'HOME_LEAGUE', 'A club cannot leave its home league.', { club_id: clubId });
  if ((state.leagueFixtures.get(leagueId) || []).some((f) => f.home === clubId || f.away === clubId)) {
    throw err(409, 'CLUB_HAS_FIXTURES', 'The club already has fixtures in this league.', { club_id: clubId, league_id: leagueId });
  }
  pl.teams = pl.teams.filter((t) => t !== clubId);
  return views.leagueView(league);
}

// ---------------------------------------------------------------------------------------------
// Clubs
// ---------------------------------------------------------------------------------------------
const club404 = (id) => state.clubs.get(id);
function clubOr404(id) {
  const c = state.clubs.get(id);
  if (!c) throw err(404, 'CLUB_NOT_FOUND', `Club ${id} does not exist.`, { club_id: id });
  return c;
}

const STAFF_ROLES = ['coach', 'assistant_coach', 'manager', 'physio', 'analyst', 'kit_manager'];

function validateClubFields(b, bad, creating) {
  if ((creating || b.name !== undefined) && !str(b.name, 80)) bad.push('name');
  if (b.description !== undefined && !(isStr(b.description) && b.description.length <= 1000)) bad.push('description');
  validateColors(b.colors, bad);
  const v = b.venue;
  if ((creating || v !== undefined) && !(isObj(v) && str(v.name, 80) &&
    (v.lat === undefined || (typeof v.lat === 'number' && v.lat >= -90 && v.lat <= 90)) &&
    (v.lng === undefined || (typeof v.lng === 'number' && v.lng >= -180 && v.lng <= 180)))) bad.push('venue');
  if (b.social !== undefined && !(isObj(b.social) && Object.entries(b.social).every(([k, s]) => /^[a-z]{1,20}$/.test(k) && isStr(s) && s.length <= 60))) bad.push('social');
  if (b.staff !== undefined && !(Array.isArray(b.staff) && b.staff.length <= 30 && b.staff.every((s) => isObj(s) && str(s.name, 80) && STAFF_ROLES.includes(s.role)))) bad.push('staff');
}

function createClub(b, { tenantId } = {}) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateClubFields(b, bad, true);
  if (b.club_id !== undefined && !isId(b.club_id)) bad.push('club_id');
  if (!isStr(b.league_id)) bad.push('league_id');
  if (bad.length) throw validation(bad);
  const league = leagueOr404(b.league_id);
  if (tenantId && league.tenant_id !== tenantId) throw err(409, 'CROSS_TENANT_ASSIGNMENT', 'The league belongs to another tenant.', { league_id: league.league_id });
  const id = b.club_id || slug(b.name, 'club', (x) => state.clubs.has(x));
  if (state.clubs.has(id)) throw err(409, 'CLUB_EXISTS', `Club ${id} already exists.`, { club_id: id });
  const club = {
    club_id: id,
    tenant_id: league.tenant_id,
    league_id: league.league_id,
    name: b.name.trim(),
    description: b.description || '',
    colors: b.colors ? clone(b.colors) : null,
    logo_url: null,
    home_venue: { name: b.venue.name.trim(), lat: b.venue.lat ?? null, lng: b.venue.lng ?? null },
    social: clone(b.social || {}),
    staff: clone(b.staff || []),
    founded: null,
  };
  state.clubs.set(id, club);
  state.prodLeagues.get(league.league_id).teams.push(id);
  roster.registerSquad(league, { squad_id: id, club_id: id, tenant_id: league.tenant_id });
  return views.clubCard(club);
}

// Club Managers edit their club's profile; only the Super-Admin renames a club.
function updateClub(club, b, { admin }) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateClubFields(b, bad, false);
  if (b.name !== undefined && !admin) bad.push('name');
  if (bad.length) throw validation(bad);
  if (b.name !== undefined) club.name = b.name.trim();
  if (b.description !== undefined) club.description = b.description;
  if (b.colors !== undefined) club.colors = { ...(club.colors || {}), ...b.colors };
  if (b.venue !== undefined) club.home_venue = { ...club.home_venue, name: b.venue.name.trim(), lat: b.venue.lat ?? club.home_venue.lat, lng: b.venue.lng ?? club.home_venue.lng };
  if (b.social !== undefined) club.social = clone(b.social);
  if (b.staff !== undefined) club.staff = clone(b.staff);
  return views.clubCard(club);
}

// ---------------------------------------------------------------------------------------------
// Users and role assignments
// ---------------------------------------------------------------------------------------------
function validateAssignments(role, tenantId, b, bad) {
  if (role !== 'super_admin' && !(isStr(tenantId) && state.tenants.has(tenantId))) bad.push('tenant_id');
  const inTenant = (r) => r && r.tenant_id === tenantId;
  if (b.league_ids !== undefined && !(Array.isArray(b.league_ids) && b.league_ids.every((id) => inTenant(state.leagues.get(id))))) bad.push('league_ids');
  if (role === 'club_manager' && !inTenant(state.clubs.get(b.club_id))) bad.push('club_id');
  if (role === 'player' && !inTenant(state.players.get(b.player_id))) bad.push('player_id');
}

function userView(u) {
  return auth.publicUser(u);
}

function listUsers({ role, tenant_id: tenantId, q } = {}) {
  const needle = isStr(q) ? q.trim().toLowerCase() : '';
  return [...state.users.values()]
    .filter((u) => (!role || u.role === role) && (!tenantId || u.tenant_id === tenantId))
    .filter((u) => !needle || u.email.includes(needle) || (u.name || '').toLowerCase().includes(needle))
    .map(userView);
}

function shapeAssignments(role, b, prev = {}) {
  const pick2 = (k) => (b[k] !== undefined ? b[k] : prev[k]);
  return {
    league_ids: role === 'league_organizer' ? [...(pick2('league_ids') || [])] : [],
    club_id: role === 'club_manager' ? pick2('club_id') : role === 'player' ? (state.players.get(pick2('player_id')) || {}).club_id || null : null,
    player_id: role === 'player' ? pick2('player_id') : null,
  };
}

function createUser(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!(isStr(b.email) && EMAIL_RE.test(b.email.trim()))) bad.push('email');
  if (!str(b.name, 80)) bad.push('name');
  if (!(isStr(b.password) && b.password.length >= 8 && b.password.length <= 128)) bad.push('password');
  if (!ROLES.includes(b.role)) bad.push('role');
  if (b.store_access !== undefined && !isBool(b.store_access)) bad.push('store_access');
  if (!bad.length) validateAssignments(b.role, b.role === 'super_admin' ? null : b.tenant_id, b, bad);
  if (bad.length) throw validation(bad);
  const email = b.email.trim().toLowerCase();
  if (state.users.has(email)) throw err(409, 'EMAIL_TAKEN', `An account for ${email} already exists.`, { email });
  const u = {
    user_id: nextId('user'),
    email,
    name: b.name.trim(),
    role: b.role,
    tenant_id: b.role === 'super_admin' ? null : b.tenant_id,
    ...shapeAssignments(b.role, b),
    store_access: b.store_access !== false,
    active: true,
    password: auth.hashPassword(b.password),
  };
  state.users.set(email, u);
  return userView(u);
}

function updateUser(actor, id, b) {
  const u = userOr404(id);
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (b.name !== undefined && !str(b.name, 80)) bad.push('name');
  if (b.role !== undefined && !ROLES.includes(b.role)) bad.push('role');
  if (b.active !== undefined && !isBool(b.active)) bad.push('active');
  if (b.store_access !== undefined && !isBool(b.store_access)) bad.push('store_access');
  if (b.password !== undefined && !(isStr(b.password) && b.password.length >= 8 && b.password.length <= 128)) bad.push('password');
  const role = b.role || u.role;
  const tenantId = role === 'super_admin' ? null : b.tenant_id !== undefined ? b.tenant_id : u.tenant_id;
  if (!bad.length) validateAssignments(role, tenantId, { ...shapeAssignments(role, {}, u), ...b }, bad);
  if (bad.length) throw validation(bad);
  if (actor.user_id === u.user_id && (b.active === false || (b.role && b.role !== u.role))) {
    throw err(409, 'SELF_LOCKOUT', 'You cannot disable your own account or change your own role.', { user_id: u.user_id });
  }
  Object.assign(u, { role, tenant_id: tenantId, ...shapeAssignments(role, b, u) });
  if (b.name !== undefined) u.name = b.name.trim();
  if (b.active !== undefined) u.active = b.active;
  if (b.store_access !== undefined) u.store_access = b.store_access;
  if (b.password !== undefined) u.password = auth.hashPassword(b.password);
  return userView(u);
}

// ---------------------------------------------------------------------------------------------
// Settings, categories, discount codes
// ---------------------------------------------------------------------------------------------
function updateSettings(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (b.organizer_can_create_clubs !== undefined && !isBool(b.organizer_can_create_clubs)) bad.push('organizer_can_create_clubs');
  if (b.low_stock_threshold !== undefined && !(isInt(b.low_stock_threshold) && b.low_stock_threshold >= 0 && b.low_stock_threshold <= 1000)) bad.push('low_stock_threshold');
  if (b.min_rest_hours !== undefined && !(isInt(b.min_rest_hours) && b.min_rest_hours >= 0 && b.min_rest_hours <= 168)) bad.push('min_rest_hours');
  if (bad.length) throw validation(bad);
  for (const k of ['organizer_can_create_clubs', 'low_stock_threshold', 'min_rest_hours']) if (b[k] !== undefined) state.settings[k] = b[k];
  return clone(state.settings);
}

function createCategory(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!str(b.name, 40)) bad.push('name');
  if (b.category_id !== undefined && !(isStr(b.category_id) && /^[a-z0-9_-]{2,30}$/.test(b.category_id))) bad.push('category_id');
  if (bad.length) throw validation(bad);
  const id = b.category_id || slug(b.name, 'cat', (x) => state.categories.has(x));
  if (state.categories.has(id)) throw err(409, 'CATEGORY_EXISTS', `Category ${id} already exists.`, { category_id: id });
  const c = { category_id: id, name: b.name.trim() };
  state.categories.set(id, c);
  return clone(c);
}

function deleteCategory(id) {
  if (!state.categories.has(id)) throw err(404, 'CATEGORY_NOT_FOUND', `Category ${id} does not exist.`, { category_id: id });
  if ([...state.products.values()].some((p) => p.category === id)) throw err(409, 'CATEGORY_IN_USE', 'Products still use this category.', { category_id: id });
  state.categories.delete(id);
}

function upsertDiscount(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!(isStr(b.code) && /^[A-Z0-9]{3,20}$/.test(b.code))) bad.push('code');
  if (b.percent !== undefined && !(isInt(b.percent) && b.percent >= 1 && b.percent <= 90)) bad.push('percent');
  if (b.active !== undefined && !isBool(b.active)) bad.push('active');
  if (!state.discounts.has(b.code) && b.percent === undefined) bad.push('percent');
  if (bad.length) throw validation(bad);
  const d = state.discounts.get(b.code) || { code: b.code, percent: b.percent, active: true };
  if (b.percent !== undefined) d.percent = b.percent;
  if (b.active !== undefined) d.active = b.active;
  state.discounts.set(b.code, d);
  return clone(d);
}

module.exports = {
  describeRules, sportView, listSports, sportDetail, createSport, updateSport, sportActive,
  tenantOr404, tenantView, createTenant, updateTenant,
  leagueOr404, createLeague, updateLeague, assignOrganizer, unassignOrganizer, addLeagueClub, removeLeagueClub,
  clubOr404, createClub, updateClub, STAFF_ROLES,
  userOr404, listUsers, createUser, updateUser, ROLES,
  updateSettings, createCategory, deleteCategory, upsertDiscount,
};
