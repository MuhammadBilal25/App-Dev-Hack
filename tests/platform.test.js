'use strict';

process.env.API_RATE_LIMIT = '100000';
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call, login } = require('./helpers');

before(start);
after(stop);
beforeEach(() => call('POST', '/audit/v1/reset'));

const VOLLEY = {
  sport_id: 'netball', name: 'Netball', scoring_model: 'event', periods: { count: 4, duration_minutes: 15 },
  scoring_events: { goal: { points: 1 } }, draw_allowed: true, overtime: { policy: 'none' },
  roster: { min_squad_size: 7, max_squad_size: 12, required_positions: { gk: 1 } },
};

test('sports directory: active sports, generated rule summaries, counts and details', async () => {
  const viewer = await login('viewer@nascon.test');
  const { sports } = (await call('GET', '/api/v1/sports', undefined, viewer)).body;
  const ids = sports.map((s) => s.sport_id);
  for (const id of ['football', 'basketball', 'cricket', 'esports', 'hockey', 'volleyball', 'tennis', 'badminton', 'table_tennis']) assert.ok(ids.includes(id), id);
  const football = sports.find((s) => s.sport_id === 'football');
  assert.equal(football.league_count, 1);
  assert.equal(football.live_count, 1);
  assert.ok(football.rules_summary.some((l) => l.includes('2 periods of 45 minutes')));
  const cricket = sports.find((s) => s.sport_id === 'cricket');
  assert.equal(cricket.league_count, 0, 'beta league hidden from an alpha viewer');
  assert.ok(cricket.rules_summary.some((l) => l.includes('20 overs')));
  assert.ok(sports.find((s) => s.sport_id === 'volleyball').rules_summary[0].startsWith('Best of 5'));

  const d = (await call('GET', '/api/v1/sports/football', undefined, viewer)).body;
  assert.equal(d.sport.name, 'Football');
  assert.equal(d.live.length, 1);
  assert.equal(d.completed.length, 2);
  assert.equal(d.clubs.length, 4);
  assert.equal((await call('GET', '/api/v1/sports/nope', undefined, viewer)).status, 404);
});

test('super admin creates, updates and deactivates sports; others are forbidden', async () => {
  const admin = await login('admin@nascon.test');
  const r = await call('POST', '/api/v1/admin/sports', { ...VOLLEY, description: 'Seven a side', icon: 'netball' }, admin);
  assert.equal(r.status, 201);
  assert.equal(r.body.sport_id, 'netball');
  assert.equal(r.body.description, 'Seven a side');
  assert.equal((await call('POST', '/api/v1/admin/sports', VOLLEY, admin)).body.error.code, 'SPORT_EXISTS');
  assert.equal((await call('POST', '/api/v1/admin/sports', { ...VOLLEY, sport_id: 'x1', periods: {} }, admin)).body.error.code, 'VALIDATION_ERROR');

  // Rules may change while unused; afterwards only metadata may.
  const up = await call('PATCH', '/api/v1/admin/sports/netball', { rules: { scoring_events: { goal: { points: 2 } } }, name: 'Netball 7s' }, admin);
  assert.equal(up.status, 200);
  assert.equal(up.body.scoring_events.goal.points, 2);
  assert.equal(up.body.name, 'Netball 7s');
  assert.equal((await call('PATCH', '/api/v1/admin/sports/football', { rules: { draw_allowed: false } }, admin)).body.error.code, 'SPORT_IN_USE');
  assert.equal((await call('PATCH', '/api/v1/admin/sports/netball', { rules: { periods: { count: 0 } } }, admin)).status, 400);

  const off = await call('PATCH', '/api/v1/admin/sports/tennis', { active: false }, admin);
  assert.equal(off.body.active, false);
  const viewer = await login('viewer@nascon.test');
  assert.ok(!(await call('GET', '/api/v1/sports', undefined, viewer)).body.sports.some((s) => s.sport_id === 'tennis'));
  assert.equal((await call('GET', '/api/v1/sports/tennis', undefined, viewer)).status, 404);
  assert.equal((await call('GET', '/api/v1/sports/tennis', undefined, admin)).status, 200);

  for (const email of ['organizer@nascon.test', 'manager@nascon.test', 'player@nascon.test', 'viewer@nascon.test']) {
    const h = await login(email);
    for (const [m, p, b] of [['POST', '/api/v1/admin/sports', VOLLEY], ['PATCH', '/api/v1/admin/sports/football', { active: false }], ['GET', '/api/v1/admin/dashboard'], ['GET', '/api/v1/admin/users'], ['POST', '/api/v1/admin/leagues', {}], ['PATCH', '/api/v1/admin/settings', {}], ['GET', '/api/v1/admin/activity']]) {
      const res = await call(m, p, b, h);
      assert.equal(res.status, 403, `${email} ${m} ${p}`);
      assert.equal(res.body.error.code, 'FORBIDDEN');
    }
  }
  assert.equal((await call('GET', '/api/v1/admin/dashboard')).status, 401);
});

test('a mystery sport may take the id of a demo-only sport; baseline ids still conflict', async () => {
  const r = await call('POST', '/audit/v1/sports', { ...VOLLEY, sport_id: 'volleyball', name: 'Mystery Volleyball', scoring_model: 'round', periods: { best_of: 3 }, scoring_events: { set_won: { rounds: 1 } }, draw_allowed: false });
  assert.equal(r.status, 201);
  assert.equal(r.body.config.name, 'Mystery Volleyball');
  const admin = await login('admin@nascon.test');
  assert.ok(!(await call('GET', '/api/v1/leagues', undefined, admin)).body.leagues.some((l) => l.league_id === 'league-alpha-volley'));
  const me = (await call('GET', '/api/v1/me', undefined, await login('organizer@nascon.test'))).body;
  assert.deepEqual(me.league_ids, ['league-alpha-1']);
  assert.equal((await call('POST', '/audit/v1/sports', { ...VOLLEY, sport_id: 'football' })).body.error.code, 'SPORT_EXISTS');
});

test('leagues: create with season and format, assign organizer and clubs, update', async () => {
  const admin = await login('admin@nascon.test');
  const r = await call('POST', '/api/v1/admin/leagues', {
    tenant_id: 'tenant-alpha', name: 'Alpha Winter Cup', sport_id: 'football', season: '2026-27', format: 'single_elim',
    points: { win: 3, draw: 1, loss: 0 }, qualification_spots: 2, rules: ['Knockout'],
  }, admin);
  assert.equal(r.status, 201);
  const id = r.body.league_id;
  assert.equal(id, 'league-alpha-winter-cup');
  assert.equal(r.body.season, '2026-27');
  assert.equal(r.body.format, 'single_elim');
  assert.equal((await call('POST', '/api/v1/admin/leagues', { tenant_id: 'tenant-alpha', name: 'X', sport_id: 'nope' }, admin)).status, 404);
  assert.equal((await call('POST', '/api/v1/admin/leagues', { tenant_id: 'tenant-zzz', name: 'X', sport_id: 'football' }, admin)).status, 404);
  assert.equal((await call('POST', '/api/v1/admin/leagues', { tenant_id: 'tenant-alpha', name: 'X', sport_id: 'football', format: 'ladder' }, admin)).status, 400);

  // Organizer assignment is tenant- and role-checked.
  assert.equal((await call('POST', `/api/v1/admin/leagues/${id}/organizers`, { user_id: 'user-viewer' }, admin)).body.error.code, 'ROLE_MISMATCH');
  assert.equal((await call('POST', `/api/v1/admin/leagues/${id}/organizers`, { user_id: 'user-organizer-beta' }, admin)).body.error.code, 'CROSS_TENANT_ASSIGNMENT');
  const assigned = await call('POST', `/api/v1/admin/leagues/${id}/organizers`, { user_id: 'user-organizer' }, admin);
  assert.deepEqual(assigned.body.organizers.map((o) => o.user_id), ['user-organizer']);
  const org = await login('organizer@nascon.test');
  assert.ok((await call('GET', '/api/v1/me', undefined, org)).body.league_ids.includes(id));

  // Clubs join the cup (same tenant and sport only).
  for (const c of ['club-alpha-1', 'club-alpha-2', 'club-alpha-3']) assert.equal((await call('POST', `/api/v1/admin/leagues/${id}/clubs`, { club_id: c }, admin)).status, 200);
  assert.equal((await call('POST', `/api/v1/admin/leagues/${id}/clubs`, { club_id: 'club-alpha-5' }, admin)).body.error.code, 'SPORT_MISMATCH');
  assert.equal((await call('POST', `/api/v1/admin/leagues/${id}/clubs`, { club_id: 'club-beta-1' }, admin)).body.error.code, 'CROSS_TENANT_ASSIGNMENT');
  assert.equal((await call('DELETE', `/api/v1/admin/leagues/${id}/clubs/club-alpha-3`, undefined, admin)).body.team_count, 2);
  assert.equal((await call('DELETE', '/api/v1/admin/leagues/league-alpha-1/clubs/club-alpha-1', undefined, admin)).body.error.code, 'HOME_LEAGUE');
  const club = (await call('GET', '/api/v1/clubs/club-alpha-1', undefined, admin)).body;
  assert.ok(club.leagues.some((l) => l.league_id === id));

  const up = await call('PATCH', `/api/v1/admin/leagues/${id}`, { status: 'archived', season: '2027', max_squad_size: 20 }, admin);
  assert.equal(up.body.status, 'archived');
  assert.equal((await call('PATCH', `/api/v1/admin/leagues/${id}`, { status: 'paused' }, admin)).status, 400);
  assert.equal((await call('DELETE', `/api/v1/admin/leagues/${id}/organizers/user-organizer`, undefined, admin)).body.organizers.length, 0);
});

test('clubs: admin creates and assigns; organizer only when allowed; manager edits own profile', async () => {
  const admin = await login('admin@nascon.test');
  const r = await call('POST', '/api/v1/admin/clubs', { name: 'Alpha Eagles', league_id: 'league-alpha-1', venue: { name: 'Eagle Park', lat: 33.6, lng: 73.1 }, colors: { primary: '#123456' } }, admin);
  assert.equal(r.status, 201);
  assert.equal(r.body.club_id, 'club-alpha-eagles');
  const table = (await call('GET', '/api/v1/standings/league-alpha-1', undefined, admin)).body.table;
  assert.ok(table.some((t) => t.team_id === 'club-alpha-eagles'));
  assert.equal((await call('POST', '/api/v1/admin/clubs', { name: 'Bad', league_id: 'league-alpha-1', venue: {} }, admin)).status, 400);

  // The new club is a roster squad: its manager-to-be can sign players into it.
  const mgr = await call('POST', '/api/v1/admin/users', { email: 'eagles@nascon.test', name: 'Eagles Boss', password: 'Secret123', role: 'club_manager', tenant_id: 'tenant-alpha', club_id: 'club-alpha-eagles' }, admin);
  assert.equal(mgr.status, 201);
  const eagles = { authorization: `Bearer ${(await call('POST', '/api/v1/auth/login', { email: 'eagles@nascon.test', password: 'Secret123' })).body.token}` };
  assert.equal((await call('POST', '/api/v1/clubs/club-alpha-eagles/players', { name: 'First Signing', position: 'gk', role: 'captain' }, eagles)).status, 201);

  const org = await login('organizer@nascon.test');
  const body = { name: 'Organizer FC', venue: { name: 'Org Field' } };
  assert.equal((await call('POST', '/api/v1/leagues/league-alpha-1/clubs', body, org)).status, 403);
  await call('PATCH', '/api/v1/admin/settings', { organizer_can_create_clubs: true }, admin);
  assert.equal((await call('POST', '/api/v1/leagues/league-alpha-1/clubs', body, org)).status, 201);
  assert.equal((await call('POST', '/api/v1/leagues/league-alpha-2/clubs', body, org)).status, 403, 'not their league');

  const manager = await login('manager@nascon.test');
  const edit = await call('PATCH', '/api/v1/clubs/club-alpha-1', { description: 'New story', colors: { primary: '#000000' }, staff: [{ name: 'New Coach', role: 'coach' }] }, manager);
  assert.equal(edit.status, 200);
  const prof = (await call('GET', '/api/v1/clubs/club-alpha-1', undefined, manager)).body;
  assert.equal(prof.description, 'New story');
  assert.equal(prof.staff[0].name, 'New Coach');
  assert.equal(prof.can_edit, true);
  assert.equal((await call('PATCH', '/api/v1/clubs/club-alpha-1', { name: 'Renamed' }, manager)).status, 400, 'only the admin renames');
  assert.equal((await call('PATCH', '/api/v1/clubs/club-alpha-2', { description: 'x' }, manager)).status, 403);
  assert.equal((await call('PATCH', '/api/v1/clubs/club-alpha-1', { description: 'x' }, await login('player@nascon.test'))).status, 403);
  assert.equal((await call('PATCH', '/api/v1/clubs/club-alpha-1', { name: 'Falcons' }, admin)).body.name, 'Falcons');
});

test('users: create, change roles and assignments, disable; JWT reflects changes at once', async () => {
  const admin = await login('admin@nascon.test');
  const bad = await call('POST', '/api/v1/admin/users', { email: 'nope', name: '', password: 'x', role: 'god' }, admin);
  assert.deepEqual(bad.body.error.details.fields.sort(), ['email', 'name', 'password', 'role']);
  assert.equal((await call('POST', '/api/v1/admin/users', { email: 'p2@nascon.test', name: 'P', password: 'Password1', role: 'club_manager', tenant_id: 'tenant-alpha', club_id: 'club-beta-1' }, admin)).body.error.details.fields[0], 'club_id');
  assert.equal((await call('POST', '/api/v1/admin/users', { email: 'viewer@nascon.test', name: 'Dup', password: 'Password1', role: 'viewer', tenant_id: 'tenant-alpha' }, admin)).body.error.code, 'EMAIL_TAKEN');

  const u = (await call('POST', '/api/v1/admin/users', { email: 'Fan@Example.com', name: 'Fan', password: 'Password1', role: 'viewer', tenant_id: 'tenant-alpha' }, admin)).body;
  assert.equal(u.email, 'fan@example.com');
  const fanLogin = await call('POST', '/api/v1/auth/login', { email: 'fan@example.com', password: 'Password1' });
  assert.equal(fanLogin.status, 200);
  assert.equal((await call('POST', '/api/v1/auth/login', { email: 'fan@example.com', password: 'Nascon@26' })).status, 401);
  const fan = { authorization: `Bearer ${fanLogin.body.token}` };

  // Promote to organizer of league-alpha-2: the same token now may manage that league.
  assert.equal((await call('POST', '/audit/v1/rbac/leagues/league-alpha-2/fixtures', {}, fan)).status, 403);
  const promoted = await call('PATCH', `/api/v1/admin/users/${u.user_id}`, { role: 'league_organizer', league_ids: ['league-alpha-2'] }, admin);
  assert.equal(promoted.body.role, 'league_organizer');
  assert.equal((await call('POST', '/audit/v1/rbac/leagues/league-alpha-2/fixtures', {}, fan)).status, 200);
  assert.equal((await call('PATCH', `/api/v1/admin/users/${u.user_id}`, { league_ids: ['league-beta-1'] }, admin)).status, 400);

  // Disabled accounts lose access immediately.
  await call('PATCH', `/api/v1/admin/users/${u.user_id}`, { active: false }, admin);
  assert.equal((await call('GET', '/api/v1/me', undefined, fan)).status, 401);
  assert.equal((await call('POST', '/api/v1/auth/login', { email: 'fan@example.com', password: 'Password1' })).status, 401);
  assert.equal((await call('PATCH', '/api/v1/admin/users/user-super-admin', { active: false }, admin)).body.error.code, 'SELF_LOCKOUT');
  assert.equal((await call('PATCH', '/api/v1/admin/users/user-nope', { active: false }, admin)).status, 404);

  const list = (await call('GET', '/api/v1/admin/users?role=club_manager', undefined, admin)).body.users;
  assert.ok(list.every((x) => x.role === 'club_manager') && list.length >= 2);
  assert.equal((await call('GET', '/api/v1/admin/users?q=fan', undefined, admin)).body.users.length, 1);
});

test('store access is a separate permission for club managers', async () => {
  const lions = await login('lions.manager@nascon.test');
  const me = (await call('GET', '/api/v1/me', undefined, lions)).body;
  assert.equal(me.store_access, false);
  assert.equal((await call('POST', '/audit/v1/rbac/clubs/club-alpha-2/products', {}, lions)).status, 403);
  assert.equal((await call('POST', '/audit/v1/rbac/clubs/club-alpha-2/roster', {}, lions)).status, 200);
  const admin = await login('admin@nascon.test');
  await call('PATCH', '/api/v1/admin/users/user-manager-lions', { store_access: true }, admin);
  assert.equal((await call('POST', '/audit/v1/rbac/clubs/club-alpha-2/products', {}, lions)).status, 200);
});

test('tenants, branding, settings, categories, discounts and the activity log', async () => {
  const admin = await login('admin@nascon.test');
  const t = await call('POST', '/api/v1/admin/tenants', { name: 'Gamma Club Network', colors: { primary: '#7C3AED' } }, admin);
  assert.equal(t.status, 201);
  assert.equal(t.body.tenant_id, 'tenant-gamma-club-network');
  assert.equal((await call('POST', '/api/v1/admin/tenants', { name: 'Bad', colors: { primary: 'purple' } }, admin)).status, 400);
  const up = await call('PATCH', '/api/v1/admin/tenants/tenant-alpha', { colors: { primary: '#B91C1C' } }, admin);
  assert.equal(up.body.colors.primary, '#B91C1C');
  const viewer = await login('viewer@nascon.test');
  const brand = (await call('GET', '/api/v1/tenants/me', undefined, viewer)).body;
  assert.equal(brand.colors.light, '#B91C1C');
  assert.match(brand.colors.dark, /^#[0-9A-F]{6}$/);
  assert.equal((await call('GET', '/api/v1/admin/tenants', undefined, admin)).body.tenants.length, 3);

  assert.equal((await call('PATCH', '/api/v1/admin/settings', { low_stock_threshold: -1 }, admin)).status, 400);
  assert.equal((await call('PATCH', '/api/v1/admin/settings', { low_stock_threshold: 5, min_rest_hours: 24 }, admin)).body.low_stock_threshold, 5);
  assert.equal((await call('GET', '/api/v1/admin/settings', undefined, admin)).body.min_rest_hours, 24);

  assert.equal((await call('POST', '/api/v1/admin/categories', { name: 'Scarves' }, admin)).body.category_id, 'cat-scarves');
  assert.equal((await call('POST', '/api/v1/admin/categories', { name: 'Scarves', category_id: 'cat-scarves' }, admin)).body.error.code, 'CATEGORY_EXISTS');
  assert.equal((await call('DELETE', '/api/v1/admin/categories/apparel', undefined, admin)).body.error.code, 'CATEGORY_IN_USE');
  assert.equal((await call('DELETE', '/api/v1/admin/categories/cat-scarves', undefined, admin)).status, 200);
  assert.equal((await call('DELETE', '/api/v1/admin/categories/cat-scarves', undefined, admin)).status, 404);
  assert.ok((await call('GET', '/api/v1/store/categories', undefined, viewer)).body.categories.some((c) => c.category_id === 'caps'));

  assert.equal((await call('POST', '/api/v1/admin/discounts', { code: 'FANS20', percent: 20 }, admin)).body.percent, 20);
  assert.equal((await call('POST', '/api/v1/admin/discounts', { code: 'lower', percent: 5 }, admin)).status, 400);
  assert.equal((await call('POST', '/api/v1/admin/discounts', { code: 'NEWCODE' }, admin)).status, 400);
  assert.equal((await call('POST', '/api/v1/admin/discounts', { code: 'FANS20', active: false }, admin)).body.active, false);
  assert.equal((await call('GET', '/api/v1/admin/discounts', undefined, admin)).body.discounts.length, 2);

  const log = (await call('GET', '/api/v1/admin/activity?limit=50', undefined, admin)).body.activity;
  assert.ok(log.length >= 6);
  assert.equal(log[0].action, 'store.discount.upsert');
  assert.ok(log.every((a) => a.actor_email === 'admin@nascon.test'));
  assert.ok((await call('GET', '/api/v1/admin/activity?action=tenant', undefined, admin)).body.activity.every((a) => a.action.startsWith('tenant')));

  const dash = (await call('GET', '/api/v1/admin/dashboard', undefined, admin)).body;
  assert.equal(dash.tenants, 3);
  assert.ok(dash.sports.total >= 9);
  assert.equal(dash.fixtures.in_progress, 2);
  assert.equal(dash.users.super_admin, 1);
});

test('home, search, player profile and role dashboards', async () => {
  const viewer = await login('viewer@nascon.test');
  const home = (await call('GET', '/api/v1/home', undefined, viewer)).body;
  assert.ok(home.sports.length >= 5);
  assert.equal(home.live.length, 2);
  assert.ok(home.live.every((f) => f.seeded));
  assert.ok(home.upcoming.length >= 3 && home.results.length >= 3);
  assert.ok(home.clubs.length >= 4 && home.leagues.length === 3);
  assert.ok(home.featured_products.every((p) => p.tenant_id === 'tenant-alpha' && p.in_stock));
  assert.ok(home.new_products.length >= 4);

  const s = (await call('GET', '/api/v1/search?q=alpha', undefined, viewer)).body;
  assert.ok(s.clubs.length >= 4 && s.leagues.length >= 2 && s.products.length >= 1);
  assert.ok(!s.clubs.some((c) => c.tenant_id === 'tenant-beta'));
  assert.equal((await call('GET', '/api/v1/search?q=a', undefined, viewer)).status, 400);
  assert.ok((await call('GET', '/api/v1/search?q=volley', undefined, viewer)).body.sports.some((x) => x.sport_id === 'volleyball'));

  const p = (await call('GET', '/api/v1/players/player-alpha-1-08', undefined, viewer)).body;
  assert.equal(p.club.club_id, 'club-alpha-1');
  assert.equal(p.stats.scoring[0].count, 2);
  assert.equal(p.stats.total_value, 2);
  assert.equal(p.history, null, 'roster history is private');
  const own = (await call('GET', '/api/v1/players/player-alpha-1', undefined, await login('player@nascon.test'))).body;
  assert.equal(own.is_me, true);
  assert.ok(Array.isArray(own.history));
  assert.equal((await call('GET', '/api/v1/players/player-beta-1', undefined, viewer)).status, 403);
  assert.equal((await call('GET', '/api/v1/players/nobody', undefined, viewer)).status, 404);

  const org = (await call('GET', '/api/v1/dashboard/organizer', undefined, await login('organizer@nascon.test'))).body;
  assert.deepEqual(org.leagues.map((l) => l.league_id), ['league-alpha-1', 'league-alpha-volley']);
  assert.equal(org.live.length, 1);
  assert.equal(org.leagues[1].has_bracket, true);
  assert.equal((await call('GET', '/api/v1/dashboard/organizer', undefined, viewer)).status, 403);

  const manager = await login('manager@nascon.test');
  const md = (await call('GET', '/api/v1/dashboard/manager', undefined, manager)).body;
  assert.equal(md.club.club_id, 'club-alpha-1');
  assert.equal(md.squad.max, 25);
  assert.deepEqual(md.squad.positions, [{ position: 'gk', required: 1, have: 2 }]);
  assert.equal(md.store_access, true);
  assert.ok(md.store.low_stock.length >= 1);
  assert.equal((await call('GET', '/api/v1/dashboard/manager', undefined, viewer)).status, 403);
  const lions = (await call('GET', '/api/v1/dashboard/manager', undefined, await login('lions.manager@nascon.test'))).body;
  assert.equal(lions.store_access, false);
  assert.equal(lions.store, null);

  const hist = await call('GET', '/api/v1/clubs/club-alpha-1/roster-history', undefined, manager);
  assert.equal(hist.status, 200);
  assert.equal((await call('GET', '/api/v1/clubs/club-alpha-2/roster-history', undefined, manager)).status, 403);
  assert.equal((await call('GET', '/api/v1/clubs/club-alpha-1/roster-history', undefined, viewer)).status, 403);
});
