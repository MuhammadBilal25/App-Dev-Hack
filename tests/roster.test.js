'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call, ev } = require('./helpers');

before(start);
after(stop);

const setup = (extra = {}) => ({
  league: { league_id: 'lg-r1', tenant_id: 'tenant-alpha', sport_id: 'football', transfer_window: { open: '2026-09-01', close: '2026-09-30' }, max_squad_size: 3, required_positions: { gk: 1 } },
  squads: [
    { squad_id: 'sq-a', club_id: 'club-a', tenant_id: 'tenant-alpha', name: 'A' },
    { squad_id: 'sq-b', club_id: 'club-b', tenant_id: 'tenant-alpha', name: 'B' },
    { squad_id: 'sq-x', club_id: 'club-x', tenant_id: 'tenant-beta', name: 'X' },
  ],
  players: [
    { player_id: 'p1', name: 'Ali', position: 'gk', squad_id: 'sq-a', role: 'captain' },
    { player_id: 'p2', name: 'Bilal', position: 'df', squad_id: 'sq-a', role: 'starter' },
    { player_id: 'p3', name: 'C', position: 'df', squad_id: 'sq-b', role: 'starter' },
    { player_id: 'p4', name: 'D', position: 'df', squad_id: 'sq-b' },
  ],
  matches_in_progress: [],
  ...extra,
});
const tr = (id, extra = {}) => ({
  request_id: id, league_id: 'lg-r1', player_id: 'p2', type: 'transfer', from_squad_id: 'sq-a', to_squad_id: 'sq-b',
  effective_date: '2026-09-15', loan_end_date: null, reason: 'Tactical move', requested_by: 'user-77', ...extra,
});
const post = (b) => call('POST', '/audit/v1/roster/transfer', b);
const code = async (b) => (await post(b)).body.error.code;

beforeEach(async () => {
  await call('POST', '/audit/v1/reset');
  await call('POST', '/audit/v1/roster/setup', setup());
});

test('setup returns squad counts and validates input', async () => {
  const r = await call('POST', '/audit/v1/roster/setup', setup());
  assert.deepEqual(r.body, { league_id: 'lg-r1', status: 'configured', squad_counts: { 'sq-a': 2, 'sq-b': 2, 'sq-x': 0 } });
  for (const bad of [{ league: null }, { squads: 'x' }, { players: [{ player_id: 'z', position: 'gk', squad_id: 'nope' }] }, { matches_in_progress: 'x' },
    { league: { ...setup().league, transfer_window: { open: '2026-10-01', close: '2026-09-01' } } }, { league: { ...setup().league, max_squad_size: 0 } },
    { league: { ...setup().league, required_positions: { gk: -1 } } }]) {
    assert.equal((await call('POST', '/audit/v1/roster/setup', setup(bad))).status, 400);
  }
  assert.equal((await call('POST', '/audit/v1/roster/setup', setup({ league: { ...setup().league, sport_id: 'nope' } }))).status, 404);
  const def = await call('POST', '/audit/v1/roster/setup', setup({ league: { league_id: 'lg-d', tenant_id: 'tenant-alpha', sport_id: 'football', transfer_window: { open: '2026-09-01', close: '2026-09-30' } }, squads: [], players: [] }));
  assert.equal(def.status, 201);
});

test('rule checks run in the exact order of Section 5.11', async () => {
  assert.equal(await code(tr('r', { type: 'loan' })), 'VALIDATION_ERROR');
  assert.equal(await code(tr('r', { effective_date: '2026-02-30' })), 'VALIDATION_ERROR');
  assert.equal(await code(tr('r', { to_squad_id: null })), 'VALIDATION_ERROR');
  assert.equal(await code(tr('r', { type: 'swap' })), 'VALIDATION_ERROR');
  assert.equal(await code(tr('r', { reason: 5, requested_by: 6 })), 'VALIDATION_ERROR');
  assert.equal(await code(tr('r', { league_id: 'nope' })), 'LEAGUE_NOT_FOUND');
  assert.equal(await code(tr('r', { player_id: 'nope' })), 'PLAYER_NOT_FOUND');
  assert.equal(await code(tr('r', { to_squad_id: 'nope' })), 'SQUAD_NOT_FOUND');
  assert.equal(await code(tr('r', { to_squad_id: 'sq-x', effective_date: '2026-12-01' })), 'CROSS_TENANT_TRANSFER');
  assert.equal(await code(tr('r', { player_id: 'p3', effective_date: '2026-12-01' })), 'NOT_IN_SQUAD');
  assert.equal(await code(tr('r', { effective_date: '2026-10-01' })), 'TRANSFER_WINDOW_CLOSED');
  assert.equal(await code(tr('r', { player_id: 'p1' })), 'MIN_POSITION_VIOLATION');
  assert.equal((await post(tr('ok1'))).status, 201);
  assert.equal(await code(tr('r', { player_id: 'p1', to_squad_id: 'sq-b' })), 'SQUAD_FULL');
  assert.equal(await code(tr('r', { player_id: 'p1', type: 'release', to_squad_id: null })), 'MIN_POSITION_VIOLATION');
  assert.equal((await post(tr('rel', { player_id: 'p3', type: 'release', from_squad_id: 'sq-b', to_squad_id: null, effective_date: '2027-03-01' }))).body.registration, null);
});

test('transfer effects, idempotency and audit trail', async () => {
  const r = await post(tr('tr-001', { effective_date: '2026-09-30' }));
  assert.equal(r.status, 201);
  assert.equal(r.body.state, 'active');
  assert.deepEqual(r.body.registration, { player_id: 'p2', league_id: 'lg-r1', squad_id: 'sq-b', parent_squad_id: null, registration_type: 'transfer', start_date: '2026-09-30', loan_end_date: null, role: 'substitute' });
  assert.equal(r.body.audit_entry.who, 'user-77');
  assert.equal(r.body.audit_entry.why, 'Tactical move');
  assert.match(r.body.audit_entry.when, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
  const again = await post(tr('tr-001', { effective_date: '2026-09-30' }));
  assert.equal(again.status, 200);
  assert.deepEqual(again.body, r.body);
  assert.equal(await code(tr('tr-001')), 'DUPLICATE_REQUEST_ID');
  const h = (await call('GET', '/audit/v1/roster/history/p2?as_of=2026-10-10')).body;
  assert.equal(h.current_squad_id, 'sq-b');
  assert.equal(h.history.length, 1);
  assert.equal((await call('GET', '/audit/v1/roster/history/p2?as_of=2026-09-01')).body.current_squad_id, 'sq-a');
  assert.equal((await call('GET', '/audit/v1/roster/history/nope')).status, 404);
  assert.equal((await call('GET', '/audit/v1/roster/history/p2?as_of=bad')).status, 400);
  assert.equal((await call('GET', '/audit/v1/roster/history/p1')).body.as_of.length, 10);
});

test('loan, PLAYER_ON_LOAN, and automatic return written exactly once', async () => {
  const loan = await post(tr('ln', { player_id: 'p3', type: 'loan', from_squad_id: 'sq-b', to_squad_id: 'sq-a', effective_date: '2026-09-10', loan_end_date: '2026-12-31' }));
  assert.equal(loan.body.registration.parent_squad_id, 'sq-b');
  assert.equal(loan.body.registration.loan_end_date, '2026-12-31');
  assert.equal(await code(tr('x', { player_id: 'p3', type: 'release', from_squad_id: 'sq-a', to_squad_id: null, effective_date: '2026-10-01' })), 'PLAYER_ON_LOAN');
  const during = (await call('GET', '/audit/v1/roster/history/p3?as_of=2026-11-01')).body;
  assert.deepEqual([during.current_squad_id, during.parent_squad_id], ['sq-a', 'sq-b']);
  const a = (await call('GET', '/audit/v1/roster/history/p3?as_of=2027-01-05')).body;
  const b = (await call('GET', '/audit/v1/roster/history/p3?as_of=2027-01-05')).body;
  assert.equal(a.current_squad_id, 'sq-b');
  assert.deepEqual(a.history.map((e) => e.action), ['loan', 'loan_return']);
  assert.equal(a.history[1].who, 'system');
  assert.equal(a.history[1].effective_date, '2027-01-01');
  assert.equal(b.history.length, 2);
});

test('edge case 6: last window day with an in-progress match is deferred', async () => {
  await call('POST', '/audit/v1/roster/setup', setup({ matches_in_progress: [{ match_id: 'm-live', home_squad_id: 'sq-a', away_squad_id: 'sq-b' }] }));
  const r = await post(tr('d', { effective_date: '2026-09-30' }));
  assert.equal(r.status, 201);
  assert.equal(r.body.state, 'deferred_until_match_end');
  assert.equal(r.body.blocking_match_id, 'm-live');
  assert.equal(r.body.audit_entry.state, 'deferred_until_match_end');
});

test('FR-NFR-4 offline sync: ordering, rebase, conflicts, duplicates', async () => {
  await ev('m1', 'match_init', { sport_id: 'football', home_team_id: 't1', away_team_id: 't2' });
  await ev('m1', 'match_start', {});
  await ev('m1', 'score', { team_id: 't1', event_type: 'goal' }, 'known');
  const body = {
    device_id: 'dev-1',
    actions: [
      { action_id: 'a2', type: 'roster_transfer', queued_at: '2026-10-17T11:01:00Z', base_version: 0, payload: tr('q1') },
      { action_id: 'a1', type: 'score_event', queued_at: '2026-10-17T11:00:00Z', base_version: 1, payload: { event_id: 'evt-9', match_id: 'm1', type: 'score', payload: { team_id: 't1', event_type: 'goal' } } },
      { action_id: 'a3', type: 'score_event', queued_at: '2026-10-17T11:02:00Z', base_version: 50, payload: { event_id: 'evt-10', match_id: 'm1', type: 'score', payload: { team_id: 't1', event_type: 'goal' } } },
      { action_id: 'a4', type: 'score_event', queued_at: '2026-10-17T11:03:00Z', base_version: 0, payload: { event_id: 'evt-11', match_id: 'ghost', type: 'score', payload: { team_id: 't1', event_type: 'goal' } } },
      { action_id: 'a5', type: 'roster_transfer', queued_at: '2026-10-17T11:04:00Z', base_version: 0, payload: tr('q2', { player_id: 'p1', to_squad_id: 'sq-b' }) },
      { action_id: 'a6', type: 'score_event', queued_at: '2026-10-17T11:05:00Z', base_version: 4, payload: { event_id: 'known', match_id: 'm1', type: 'score', payload: { team_id: 't1', event_type: 'goal' } } },
      { action_id: 'a7', type: 'score_event', queued_at: '2026-10-17T11:06:00Z', base_version: 4, payload: { event_id: 'known', match_id: 'm1', type: 'score', payload: { team_id: 't2', event_type: 'goal' } } },
      { action_id: 'a8', type: 'roster_transfer', queued_at: '2026-10-17T11:07:00Z', base_version: 0, payload: tr('q3', { player_id: 'ghost' }) },
      { action_id: 'a9', type: 'roster_transfer', queued_at: '2026-10-17T11:08:00Z', base_version: 7, payload: tr('q4', { player_id: 'p4', from_squad_id: 'sq-b', to_squad_id: 'sq-a' }) },
      { action_id: 'b1', type: 'score_event', queued_at: '2026-10-17T11:09:00Z', base_version: 0, payload: { event_id: 'bad', match_id: 'm1', type: 'nope', payload: {} } },
      { action_id: 'b2', type: 'roster_transfer', queued_at: '2026-10-17T11:10:00Z', base_version: 0, payload: { request_id: 'q5' } },
      { action_id: 'b3', type: 'roster_transfer', queued_at: '2026-10-17T11:11:00Z', base_version: 1, payload: tr('q1') },
      { action_id: 'b4', type: 'roster_transfer', queued_at: '2026-10-17T11:12:00Z', base_version: 0, payload: tr('q6', { league_id: 'ghost' }) },
      { action_id: 'b5', type: 'roster_transfer', queued_at: '2026-10-17T11:13:00Z', base_version: 0, payload: tr('q7', { to_squad_id: 'ghost' }) },
      { action_id: 'b6', type: 'roster_transfer', queued_at: '2026-10-17T11:14:00Z', base_version: 0, payload: tr('q1', { reason: 'other' }) },
    ],
  };
  const r = (await call('POST', '/audit/v1/offline-sync', body)).body;
  const by = Object.fromEntries(r.results.map((x) => [x.action_id, x]));
  assert.deepEqual(r.results.map((x) => x.action_id), body.actions.map((a) => a.action_id));
  assert.equal(by.a1.processed_order, 1);
  assert.deepEqual([by.a1.status, by.a1.resolution, by.a1.server_version], ['applied', 'rebased_append', 4]);
  assert.equal(by.a1.signature.length, 64);
  assert.deepEqual([by.a2.status, by.a2.resolution, by.a2.signature], ['applied', 'appended', null]);
  assert.equal(by.a3.error_code, 'INVALID_BASE_VERSION');
  assert.equal(by.a4.error_code, 'MATCH_NOT_FOUND');
  assert.equal(by.a5.error_code, 'SQUAD_FULL');
  assert.equal(by.a6.status, 'duplicate');
  assert.equal(by.a7.error_code, 'DUPLICATE_EVENT_ID');
  assert.equal(by.a8.error_code, 'PLAYER_NOT_FOUND');
  assert.equal(by.a9.error_code, 'INVALID_BASE_VERSION');
  assert.equal(by.b1.error_code, 'VALIDATION_ERROR');
  assert.equal(by.b2.error_code, 'VALIDATION_ERROR');
  assert.equal(by.b3.status, 'duplicate');
  assert.equal(by.b4.error_code, 'LEAGUE_NOT_FOUND');
  assert.equal(by.b5.error_code, 'SQUAD_NOT_FOUND');
  assert.equal(by.b6.error_code, 'DUPLICATE_REQUEST_ID');
  const again = (await call('POST', '/audit/v1/offline-sync', body)).body;
  assert.deepEqual(again.summary, { applied: 0, rejected: 0, duplicate: body.actions.length });
  assert.equal((await call('POST', '/audit/v1/offline-sync', { device_id: 'd', actions: [] })).status, 400);
  assert.equal((await call('POST', '/audit/v1/offline-sync', [])).status, 400);
  const init = await call('POST', '/audit/v1/offline-sync', { device_id: 'd2', actions: [{ action_id: 'i', type: 'score_event', queued_at: '2026-10-17T11:00:00Z', base_version: 0, payload: { event_id: 'ni', match_id: 'fresh', type: 'match_init', payload: { sport_id: 'football', home_team_id: 'a', away_team_id: 'b' } } }] });
  assert.equal(init.body.results[0].resolution, 'appended');
});
