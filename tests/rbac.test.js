'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call } = require('./helpers');

before(start);
after(stop);

const ROLES = ['super_admin', 'league_organizer', 'club_manager', 'player', 'viewer'];

test('FR-5.1 five-role negative authorization matrix (Section 5.13)', async () => {
  const { tokens, context: c } = (await call('POST', '/audit/v1/rbac-matrix')).body;
  const probes = [
    ['POST', '/audit/v1/rbac/tenants', 'ADDDD'],
    ['POST', `/audit/v1/rbac/leagues/${c.own_league_id}/fixtures`, 'AADDD'],
    ['POST', `/audit/v1/rbac/leagues/${c.other_league_id}/fixtures`, 'ADDDD'],
    ['POST', `/audit/v1/rbac/leagues/${c.foreign_league_id}/fixtures`, 'ADDDD'],
    ['POST', `/audit/v1/rbac/clubs/${c.own_club_id}/roster`, 'ADADD'],
    ['POST', `/audit/v1/rbac/clubs/${c.other_club_id}/roster`, 'ADDDD'],
    ['POST', `/audit/v1/rbac/clubs/${c.foreign_club_id}/roster`, 'ADDDD'],
    ['POST', `/audit/v1/rbac/clubs/${c.own_club_id}/products`, 'ADADD'],
    ['POST', `/audit/v1/rbac/clubs/${c.other_club_id}/products`, 'ADDDD'],
    ['POST', `/audit/v1/rbac/clubs/${c.foreign_club_id}/products`, 'ADDDD'],
    ['PATCH', `/audit/v1/rbac/players/${c.own_player_id}`, 'ADAAD'],
    ['PATCH', `/audit/v1/rbac/players/${c.other_player_id}`, 'ADDDD'],
    ['PATCH', `/audit/v1/rbac/players/${c.foreign_player_id}`, 'ADDDD'],
    ['GET', `/audit/v1/rbac/clubs/${c.own_club_id}`, 'AAAAA'],
    ['GET', `/audit/v1/rbac/clubs/${c.other_club_id}`, 'AAAAA'],
    ['GET', `/audit/v1/rbac/clubs/${c.foreign_club_id}`, 'ADDDD'],
    ['GET', '/audit/v1/rbac/platform/config', 'ADDDD'],
  ];
  for (const [method, path, expected] of probes) {
    let got = '';
    for (const role of ROLES) {
      const r = await call(method, path, method === 'GET' ? undefined : {}, { authorization: `Bearer ${tokens[role]}` });
      got += r.status === 200 ? 'A' : r.status === 403 && r.body.error.code === 'FORBIDDEN' ? 'D' : '?';
    }
    assert.equal(got, expected, `${method} ${path}`);
  }
  const missing = await call('GET', '/audit/v1/rbac/clubs/club-nope', undefined, { authorization: `Bearer ${tokens.viewer}` });
  assert.equal(missing.status, 404);
});

test('NFR-5 token security: missing, tampered, alg:none, expired', async () => {
  const jwt = require('jsonwebtoken');
  const { tokens } = (await call('POST', '/audit/v1/rbac-matrix')).body;
  const P7 = '/audit/v1/rbac/platform/config';
  assert.equal((await call('GET', P7)).body.error.code, 'UNAUTHENTICATED');
  const [h, p, s] = tokens.super_admin.split('.');
  assert.equal((await call('GET', P7, undefined, { authorization: `Bearer ${h}.${p}.${s.slice(0, -3)}abc` })).status, 401);
  const none = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  assert.equal((await call('GET', P7, undefined, { authorization: `Bearer ${none}.${p}.` })).status, 401);
  const expired = jwt.sign({ sub: 'user-super-admin', exp: Math.floor(Date.now() / 1000) - 10 }, 'test-secret');
  assert.equal((await call('GET', P7, undefined, { authorization: `Bearer ${expired}` })).status, 401);
  const ghost = jwt.sign({ sub: 'user-ghost' }, 'test-secret');
  assert.equal((await call('GET', P7, undefined, { authorization: `Bearer ${ghost}` })).status, 401);
  assert.equal((await call('GET', P7, undefined, { authorization: `Bearer ${tokens.super_admin}` })).status, 200);
});

test('login, /me and rate limiting on /api/v1', async () => {
  const ok = await call('POST', '/api/v1/auth/login', { email: 'Manager@Nascon.test', password: 'Nascon@26' });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.user.role, 'club_manager');
  assert.equal(ok.body.user.club_id, 'club-alpha-1');
  const me = await call('GET', '/api/v1/me', undefined, { authorization: `Bearer ${ok.body.token}` });
  assert.equal(me.body.email, 'manager@nascon.test');
  assert.equal((await call('POST', '/api/v1/auth/login', { email: 'manager@nascon.test', password: 'x' })).status, 401);
  assert.equal((await call('POST', '/api/v1/auth/login', { email: 1 })).status, 400);

  const res = await Promise.all(Array.from({ length: 150 }, () => call('GET', '/api/v1/ping')));
  assert.deepEqual(res[0].body, { pong: true });
  const limited = res.filter((r) => r.status === 429);
  assert.ok(limited.length >= 40);
  assert.equal(limited[0].body.error.code, 'RATE_LIMITED');
  assert.ok(Number(limited[0].headers.get('retry-after')) >= 1);
  const audit = await Promise.all(Array.from({ length: 30 }, () => call('GET', '/health')));
  assert.ok(audit.every((r) => r.status === 200));
});

test('policy layer unit checks', () => {
  const { can } = require('../src/services/rbac');
  const org = { role: 'league_organizer', tenant_id: 't', league_ids: ['l1'] };
  assert.equal(can(org, 'league.fixtures.write', { league_id: 'l1', tenant_id: 't' }), true);
  assert.equal(can(org, 'league.fixtures.write', { league_id: 'l1', tenant_id: 'other' }), false);
  assert.equal(can(org, 'unknown.action', { tenant_id: 't' }), false);
  assert.equal(can(org, 'match.score.write', { league_id: 'l1', tenant_id: 't' }), true);
  assert.equal(can({ role: 'viewer', tenant_id: 't' }, 'league.read', { tenant_id: 't' }), true);
  assert.equal(can({ role: 'viewer', tenant_id: 't' }, 'store.checkout', { tenant_id: 't' }), true);
});
