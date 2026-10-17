'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call } = require('./helpers');

before(start);
after(stop);
beforeEach(() => call('POST', '/audit/v1/reset'));

async function token(email) {
  const r = await call('POST', '/api/v1/auth/login', { email, password: 'Nascon@26' });
  return { authorization: `Bearer ${r.body.token}` };
}

test('mobile API requires a valid JWT', async () => {
  for (const path of ['/api/v1/tenants/me', '/api/v1/leagues', '/api/v1/fixtures', '/api/v1/catalogue', '/api/v1/clubs/club-alpha-1']) {
    const r = await call('GET', path);
    assert.equal(r.status, 401, path);
    assert.equal(r.body.error.code, 'UNAUTHENTICATED');
  }
  assert.equal((await call('GET', '/api/v1/nope', undefined, await token('viewer@nascon.test'))).status, 404);
});

test('tenant, leagues and fixtures come from the demo seed', async () => {
  const h = await token('viewer@nascon.test');
  const t = (await call('GET', '/api/v1/tenants/me', undefined, h)).body;
  assert.deepEqual(t, { tenant_id: 'tenant-alpha', name: 'Alpha Sports', colors: { light: '#1D4ED8', dark: '#8AB4FF' }, initials: 'AS', logo_url: null });

  const leagues = (await call('GET', '/api/v1/leagues', undefined, h)).body.leagues;
  assert.deepEqual(leagues.map((l) => l.league_id).sort(), ['league-alpha-1', 'league-alpha-2']);

  const fx = (await call('GET', '/api/v1/fixtures?league_id=league-alpha-1', undefined, h)).body.fixtures;
  assert.equal(fx.length, 6);
  const by = (s) => fx.filter((f) => f.status === s);
  assert.equal(by('completed').length, 2);
  assert.equal(by('in_progress').length, 1);
  assert.equal(by('upcoming').length, 3);
  const live = by('in_progress')[0];
  assert.equal(`${live.home.score}:${live.away.score}`, '2:1');
  assert.ok(live.minute >= 1 && live.minute <= 90);
  assert.equal(live.home.name, 'Alpha Falcons FC');
  assert.ok(fx.every((f) => f.venue && f.kickoff_at));

  const admin = await token('admin@nascon.test');
  assert.equal((await call('GET', '/api/v1/leagues', undefined, admin)).body.leagues.length, 3);
});

test('match detail has the timeline with a disallowed goal and a pinned product with stock', async () => {
  const h = await token('organizer@nascon.test');
  const m = (await call('GET', '/api/v1/matches/demo-a1-r2-m1', undefined, h)).body;
  assert.equal(m.status, 'in_progress');
  assert.equal(m.can_score, true);
  const goals = m.timeline.filter((e) => e.type === 'score');
  assert.equal(goals.length, 4);
  assert.equal(goals.filter((e) => e.compensated).length, 1);
  assert.equal(goals[0].minute, 9);
  assert.equal(m.pinned_product.product_id, 'prod-jersey-001');
  assert.deepEqual(m.pinned_product.variants.map((v) => v.stock), [1, 5]);
  const viewer = await token('viewer@nascon.test');
  assert.equal((await call('GET', '/api/v1/matches/demo-a1-r2-m1', undefined, viewer)).body.can_score, false);
  assert.equal((await call('GET', '/api/v1/matches/nope', undefined, viewer)).status, 404);
});

test('standings reuse the engine and react to new events', async () => {
  const h = await token('viewer@nascon.test');
  let s = (await call('GET', '/api/v1/standings/league-alpha-1', undefined, h)).body;
  assert.equal(s.table.length, 4);
  assert.equal(s.table[0].team_id, 'club-alpha-1');
  assert.equal(s.table[0].points, 3);
  assert.equal(s.table[0].team_name, 'Alpha Falcons FC');
  assert.equal(s.qualification_spots, 2);

  await call('POST', '/audit/v1/events', { event_id: 'x-end', match_id: 'demo-a1-r2-m1', type: 'match_end', payload: {} });
  s = (await call('GET', '/api/v1/standings/league-alpha-1', undefined, h)).body;
  assert.equal(s.table[0].points, 6);
});

test('club profile, catalogue and cross-tenant isolation', async () => {
  const manager = await token('manager@nascon.test');
  const c = (await call('GET', '/api/v1/clubs/club-alpha-1', undefined, manager)).body;
  assert.equal(c.name, 'Alpha Falcons FC');
  assert.ok(c.roster.length >= 8);
  assert.ok(c.roster.some((p) => p.role === 'captain') && c.roster.some((p) => p.role === 'vice_captain'));
  assert.equal(c.staff.length, 3);
  assert.equal(c.venue.lat, 33.6844);
  assert.equal(c.can_manage, true);
  assert.equal(c.sport_name, 'Football');
  for (const id of ['club-alpha-2', 'club-alpha-3', 'club-alpha-4']) {
    const o = (await call('GET', `/api/v1/clubs/${id}`, undefined, manager)).body;
    assert.ok(o.roster.length >= 8 && o.staff.length === 3, id);
    assert.equal(o.can_manage, false);
  }

  const cat = (await call('GET', '/api/v1/catalogue', undefined, manager)).body.products;
  assert.equal(cat[0].variants[0].price_minor, 450000);
  assert.equal(cat[0].variants[0].stock, 1);

  for (const path of ['/api/v1/clubs/club-beta-1', '/api/v1/standings/league-beta-1', '/api/v1/fixtures?league_id=league-beta-1']) {
    const r = await call('GET', path, undefined, manager);
    assert.equal(r.status, 403, path);
    assert.equal(r.body.error.code, 'FORBIDDEN');
  }
  assert.equal((await call('GET', '/api/v1/clubs/club-nope', undefined, manager)).status, 404);
  const beta = (await call('GET', '/api/v1/clubs', undefined, await token('admin@nascon.test'))).body.clubs;
  assert.ok(beta.some((x) => x.club_id === 'club-beta-1'));
});

test('demo roster league accepts offline-sync transfers and score events', async () => {
  const manager = await token('manager@nascon.test');
  const before = (await call('GET', '/api/v1/clubs/club-alpha-1', undefined, manager)).body;
  const mover = before.roster.find((p) => p.position === 'mf');
  assert.equal(mover.version, 0);
  const today = new Date().toISOString().slice(0, 10);
  const r = await call('POST', '/audit/v1/offline-sync', {
    device_id: 'dev-1',
    actions: [
      {
        action_id: 'a1', type: 'roster_transfer', queued_at: '2026-10-17T10:00:00Z', base_version: 0,
        payload: { request_id: 'rq-1', league_id: 'league-alpha-1', player_id: mover.player_id, type: 'transfer', from_squad_id: 'club-alpha-1', to_squad_id: 'club-alpha-2', effective_date: today, reason: 'Demo' },
      },
      {
        action_id: 'a2', type: 'score_event', queued_at: '2026-10-17T10:00:01Z', base_version: 0,
        payload: { event_id: 'sync-goal', match_id: 'demo-a1-r2-m1', type: 'score', payload: { team_id: 'club-alpha-3', event_type: 'goal', minute: 70 } },
      },
      {
        action_id: 'a3', type: 'score_event', queued_at: '2026-10-17T10:00:02Z', base_version: 0,
        payload: { event_id: 'sync-late', match_id: 'demo-a1-r1-m1', type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal' } },
      },
    ],
  });
  assert.deepEqual(r.body.results.map((x) => x.status), ['applied', 'applied', 'rejected']);
  assert.equal(r.body.results[2].error_code, 'MATCH_NOT_IN_PROGRESS');
  const after = (await call('GET', '/api/v1/clubs/club-alpha-2', undefined, manager)).body;
  assert.equal(after.roster.find((p) => p.player_id === mover.player_id).version, 1);
  assert.ok(!(await call('GET', '/api/v1/clubs/club-alpha-1', undefined, manager)).body.roster.some((p) => p.player_id === mover.player_id));
  const m = (await call('GET', '/api/v1/matches/demo-a1-r2-m1', undefined, manager)).body;
  assert.equal(`${m.home.score}:${m.away.score}`, '2:2');
});
