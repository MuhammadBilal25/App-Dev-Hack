'use strict';

process.env.API_RATE_LIMIT = '100000';
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call, login } = require('./helpers');

before(start);
after(stop);
beforeEach(() => call('POST', '/audit/v1/reset'));

const day = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);

async function newLeague(admin, format, sport = 'football', clubs = 4) {
  const l = (await call('POST', '/api/v1/admin/leagues', { tenant_id: 'tenant-alpha', name: `${format} ${sport} ${Math.random().toString(36).slice(2, 7)}`, sport_id: sport, format }, admin)).body;
  for (let i = 1; i <= clubs; i++) {
    const r = await call('POST', '/api/v1/admin/clubs', { name: `${l.league_id} C${i}`, league_id: l.league_id, venue: { name: `${l.league_id} V${i}` } }, admin);
    assert.equal(r.status, 201);
  }
  await call('POST', `/api/v1/admin/leagues/${l.league_id}/organizers`, { user_id: 'user-organizer' }, admin);
  return l.league_id;
}

async function play(h, matchId, winner, loser, sport = 'football') {
  const ev = (type, payload = {}) => call('POST', `/api/v1/matches/${matchId}/events`, { type, payload }, h);
  assert.equal((await ev('match_start')).status, 201);
  const key = sport === 'volleyball' ? 'set_won' : 'goal';
  const wins = sport === 'volleyball' ? 3 : 1;
  for (let i = 0; i < wins; i++) assert.equal((await ev('score', { team_id: winner, event_type: key })).status, 201);
  if (loser && sport !== 'volleyball') assert.equal((await ev('score', { team_id: loser, event_type: key })).status, 201);
  if (sport !== 'volleyball') await ev('score', { team_id: winner, event_type: key });
  assert.equal((await ev('match_end')).status, 201);
}

test('round robin generation creates signed matches with dates, venues and a table', async () => {
  const admin = await login('admin@nascon.test');
  const org = await login('organizer@nascon.test');
  const id = await newLeague(admin, 'round_robin', 'football', 5);
  const r = await call('POST', `/api/v1/leagues/${id}/fixtures/generate`, { start_date: day(2), kickoff_time: '14:00', interval_days: 7, legs: 2 }, org);
  assert.equal(r.status, 201);
  assert.equal(r.body.fixtures.length, 20, '5 teams, double round robin: 20 matches');
  assert.ok(r.body.fixtures.every((f) => f.status === 'upcoming' && f.kickoff_at.endsWith('T14:00:00Z') && f.venue));
  assert.equal(r.body.fixtures[0].kickoff_at.slice(0, 10), day(2));
  const ev = (await call('GET', `/audit/v1/score/${r.body.fixtures[0].match_id}`)).body.events;
  assert.equal(ev[0].type, 'match_init');
  assert.match(ev[0].signature, /^[0-9a-f]{64}$/);
  assert.equal((await call('POST', `/api/v1/leagues/${id}/fixtures/generate`, {}, org)).body.error.code, 'FIXTURES_EXIST');
  assert.equal((await call('POST', `/api/v1/leagues/${id}/fixtures/generate`, { kickoff_time: '25:00' }, org)).status, 400);
  const detail = (await call('GET', `/api/v1/leagues/${id}`, undefined, org)).body;
  assert.equal(detail.fixtures.length, 20);
  assert.equal(detail.can_manage, true);
  assert.equal((await call('GET', `/api/v1/standings/${id}`, undefined, org)).body.table.length, 5);

  // Only the league's organizers (and the Super-Admin) may generate.
  const other = await newLeague(admin, 'round_robin');
  await call('DELETE', `/api/v1/admin/leagues/${other}/organizers/user-organizer`, undefined, admin);
  for (const email of ['organizer@nascon.test', 'manager@nascon.test', 'viewer@nascon.test', 'organizer.beta@nascon.test']) {
    const res = await call('POST', `/api/v1/leagues/${other}/fixtures/generate`, {}, await login(email));
    assert.equal(res.status, 403, email);
  }
  assert.equal((await call('POST', '/api/v1/leagues/nope/fixtures/generate', {}, org)).status, 404);
  const empty = (await call('POST', '/api/v1/admin/leagues', { tenant_id: 'tenant-alpha', name: 'Empty', sport_id: 'football' }, admin)).body;
  assert.equal((await call('POST', `/api/v1/leagues/${empty.league_id}/fixtures/generate`, {}, admin)).body.error.code, 'NOT_ENOUGH_TEAMS');
});

test('single elimination: bracket matches appear as earlier rounds finish', async () => {
  const admin = await login('admin@nascon.test');
  const org = await login('organizer@nascon.test');
  const id = await newLeague(admin, 'single_elim', 'football', 6);
  const gen = (await call('POST', `/api/v1/leagues/${id}/fixtures/generate`, { start_date: day(1) }, org)).body;
  assert.equal(gen.fixtures.length, 2, 'six teams: two byes, two playable first-round matches');
  let bracket = (await call('GET', `/api/v1/leagues/${id}/bracket`, undefined, org)).body;
  assert.equal(bracket.bracket_size, 8);
  assert.deepEqual(bracket.sections.map((s) => s.title), ['Quarter-finals', 'Semi-finals', 'Final']);
  assert.equal(bracket.sections[0].matches.filter((m) => m.bye).length, 2);

  for (const f of gen.fixtures) await play(org, f.match_id, f.home.team_id, f.away.team_id);
  bracket = (await call('GET', `/api/v1/leagues/${id}/bracket`, undefined, org)).body;
  const semis = bracket.sections[1].matches;
  assert.ok(semis.every((m) => m.match_id && m.status === 'upcoming'), 'both semi-finals created');
  for (const m of semis) await play(org, m.match_id, m.home.team_id, m.away.team_id);
  bracket = (await call('GET', `/api/v1/leagues/${id}/bracket`, undefined, org)).body;
  const final = bracket.sections[2].matches[0];
  assert.ok(final.match_id);
  assert.equal(final.home.team_id, semis[0].home.team_id);
  await play(org, final.match_id, final.away.team_id, null);
  bracket = (await call('GET', `/api/v1/leagues/${id}/bracket`, undefined, org)).body;
  assert.equal(bracket.sections[2].matches[0].winner_team_id, final.away.team_id);
  assert.equal((await call('GET', '/api/v1/leagues/league-alpha-1/bracket', undefined, org)).body.error.code, 'NOT_A_BRACKET');
});

test('double elimination with bracket reset and Swiss rounds advance from results', async () => {
  const admin = await login('admin@nascon.test');
  const org = await login('organizer@nascon.test');
  const de = await newLeague(admin, 'double_elim', 'football', 4);
  const g = (await call('POST', `/api/v1/leagues/${de}/fixtures/generate`, { bracket_reset: true }, org)).body;
  assert.equal(g.fixtures.length, 2);
  for (const f of g.fixtures) await play(org, f.match_id, f.home.team_id, null);
  let b = (await call('GET', `/api/v1/leagues/${de}/bracket`, undefined, org)).body;
  const playable = () => b.sections.flatMap((s) => s.matches).filter((m) => m.match_id && m.status === 'upcoming');
  // Keep playing (home side wins) until no match is waiting; the reset final only appears when
  // the losers-bracket champion wins GF1.
  for (let guard = 0; guard < 10 && playable().length; guard++) {
    for (const m of playable()) {
      const winner = m.stage === 'Grand final' ? m.away.team_id : m.home.team_id;
      await play(org, m.match_id, winner, null);
    }
    b = (await call('GET', `/api/v1/leagues/${de}/bracket`, undefined, org)).body;
  }
  const grand = b.sections.find((s) => s.title === 'Grand final').matches;
  assert.equal(grand.length, 2);
  assert.equal(grand[1].required, true);
  assert.ok(grand[1].winner_team_id, 'reset final played');

  const sw = await newLeague(admin, 'swiss', 'football', 5);
  const r1 = (await call('POST', `/api/v1/leagues/${sw}/fixtures/generate`, { total_rounds: 3 }, org)).body;
  assert.equal(r1.fixtures.length, 2, 'five teams: two pairings and a bye');
  assert.equal((await call('POST', `/api/v1/leagues/${sw}/swiss/next-round`, {}, org)).body.error.code, 'ROUND_NOT_COMPLETE');
  for (const f of r1.fixtures) await play(org, f.match_id, f.home.team_id, null);
  const r2 = (await call('POST', `/api/v1/leagues/${sw}/swiss/next-round`, {}, org));
  assert.equal(r2.status, 201);
  assert.equal(r2.body.round, 2);
  assert.equal(r2.body.fixtures.length, 2);
  const met = new Set(r1.fixtures.map((f) => [f.home.team_id, f.away.team_id].sort().join('|')));
  assert.ok(r2.body.fixtures.every((f) => !met.has([f.home.team_id, f.away.team_id].sort().join('|'))), 'no rematches');
  assert.equal((await call('POST', '/api/v1/leagues/league-alpha-1/swiss/next-round', {}, org)).body.error.code, 'NOT_SWISS');
});

test('reschedule detects venue, team, rest and venue-hour conflicts as structured errors', async () => {
  const org = await login('organizer@nascon.test');
  // demo-a1-r3-m1 (a4 v a1) and demo-a1-r3-m2 (a2 v a3) are a week away.
  const r3m2 = (await call('GET', '/api/v1/matches/demo-a1-r3-m2', undefined, org)).body;
  let r = await call('POST', '/api/v1/matches/demo-a1-r3-m1/reschedule', { kickoff_at: r3m2.kickoff_at, venue: r3m2.venue }, org);
  assert.equal(r.status, 409);
  assert.equal(r.body.error.code, 'SCHEDULE_CONFLICT');
  assert.deepEqual(r.body.error.details.conflicts.map((c) => c.type), ['venue_double_booking']);
  assert.equal(r.body.error.details.conflicts[0].match_id, 'demo-a1-r3-m2');

  const upcoming = (await call('GET', '/api/v1/matches/demo-a1-r2-m2', undefined, org)).body; // a2 v a4
  r = await call('POST', '/api/v1/matches/demo-a1-r3-m1/reschedule', { kickoff_at: upcoming.kickoff_at }, org);
  assert.ok(r.body.error.details.conflicts.some((c) => c.type === 'team_overlap' && c.entity_ids.includes('club-alpha-4')));

  const plus2h = new Date(Date.parse(upcoming.kickoff_at) + 3 * 3600000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  r = await call('POST', '/api/v1/matches/demo-a1-r3-m1/reschedule', { kickoff_at: plus2h }, org);
  assert.ok(r.body.error.details.conflicts.some((c) => c.type === 'min_rest_violation'));

  r = await call('POST', '/api/v1/matches/demo-a1-r3-m1/reschedule', { kickoff_at: `${day(10)}T03:00:00Z` }, org);
  assert.deepEqual(r.body.error.details.conflicts.map((c) => c.type), ['venue_unavailable']);

  const ok = await call('POST', '/api/v1/matches/demo-a1-r3-m1/reschedule', { kickoff_at: `${day(10)}T15:00:00Z`, venue: 'Neutral Ground' }, org);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.venue, 'Neutral Ground');
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r3-m1/reschedule', { kickoff_at: 'tomorrow' }, org)).status, 400);
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r1-m1/reschedule', { kickoff_at: `${day(12)}T15:00:00Z` }, org)).body.error.code, 'ILLEGAL_TRANSITION');
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r3-m1/reschedule', { kickoff_at: `${day(11)}T15:00:00Z` }, await login('manager@nascon.test'))).status, 403);
});

test('match status machine: postpone, restore, cancel, start, abandon; scoring blocked when off', async () => {
  const org = await login('organizer@nascon.test');
  const st = (id, status, reason) => call('POST', `/api/v1/matches/${id}/status`, { status, reason }, org);
  let r = await st('demo-a1-r2-m2', 'postponed', 'Waterlogged pitch');
  assert.equal(r.status, 200);
  assert.equal(r.body.fixture.status, 'postponed');
  assert.equal(r.body.fixture.status_reason, 'Waterlogged pitch');
  assert.equal((await st('demo-a1-r2-m2', 'in_progress')).body.error.code, 'ILLEGAL_TRANSITION');
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r2-m2/events', { type: 'match_start' }, org)).body.error.code, 'MATCH_NOT_PLAYABLE');
  assert.equal((await st('demo-a1-r2-m2', 'upcoming')).body.fixture.status, 'upcoming');
  r = await st('demo-a1-r2-m2', 'in_progress');
  assert.equal(r.body.fixture.status, 'in_progress');
  assert.equal((await st('demo-a1-r2-m2', 'abandoned', 'Floodlight failure')).body.fixture.status, 'abandoned');
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r2-m2/events', { type: 'score', payload: { team_id: 'club-alpha-2', event_type: 'goal' } }, org)).body.error.code, 'MATCH_NOT_PLAYABLE');
  assert.equal((await st('demo-a1-r3-m2', 'cancelled')).body.fixture.status, 'cancelled');
  assert.equal((await st('demo-a1-r3-m2', 'upcoming')).status, 409);
  assert.equal((await st('demo-a1-r3-m2', 'flying')).status, 400);
  assert.equal((await st('demo-a1-r1-m1', 'postponed')).body.error.code, 'ILLEGAL_TRANSITION');
  const fx = (await call('GET', '/api/v1/fixtures?league_id=league-alpha-1&status=cancelled', undefined, org)).body.fixtures;
  assert.deepEqual(fx.map((f) => f.match_id), ['demo-a1-r3-m2']);
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r2-m1/status', { status: 'completed' }, await login('viewer@nascon.test'))).status, 403);
});

test('authenticated scoring: sport validation, compensation, player credit, RBAC and replay', async () => {
  const org = await login('organizer@nascon.test');
  const post = (id, body, h = org) => call('POST', `/api/v1/matches/${id}/events`, body, h);
  const m = 'demo-a1-r2-m1';
  let r = await post(m, { event_id: 'app-goal-1', type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal', minute: 70, player_id: 'player-alpha-1-09' } });
  assert.equal(r.status, 201);
  assert.match(r.body.signature, /^[0-9a-f]{64}$/);
  assert.equal(r.body.fixture.home.score, 3);
  assert.equal((await post(m, { event_id: 'app-goal-1', type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal', minute: 70, player_id: 'player-alpha-1-09' } })).status, 200, 'idempotent replay');
  assert.equal((await post(m, { event_id: 'app-goal-1', type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal', minute: 71 } })).body.error.code, 'DUPLICATE_EVENT_ID');
  assert.equal((await post(m, { type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'three_pointer' } })).body.error.code, 'UNKNOWN_EVENT_TYPE');
  assert.equal((await post(m, { type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal', player_id: 'player-alpha-3-09' } })).status, 400, 'player not in that team');
  assert.equal((await post(m, { type: 'match_init', payload: {} })).status, 400);

  r = await post(m, { type: 'compensation', payload: { compensates: 'app-goal-1', reason: 'Handball' } });
  assert.equal(r.status, 201);
  assert.equal(r.body.fixture.home.score, 2);
  assert.equal((await post(m, { type: 'compensation', payload: { compensates: 'app-goal-1' } })).body.error.code, 'INVALID_COMPENSATION');
  const detail = (await call('GET', `/api/v1/matches/${m}`, undefined, org)).body;
  const goal = detail.timeline.find((e) => e.event_id === 'app-goal-1');
  assert.equal(goal.compensated, true);
  assert.equal(goal.player_name !== null, true);
  assert.equal(detail.scoring.model, 'event');
  assert.deepEqual(detail.allowed_status, ['abandoned', 'completed']);
  assert.ok(detail.squads.home.length >= 8);

  // Sport-specific templates come from config: innings and best-of sports.
  const volley = (await call('GET', '/api/v1/fixtures?league_id=league-alpha-volley', undefined, org)).body.fixtures;
  const semi2 = volley.find((f) => f.status === 'upcoming');
  const vd = (await call('GET', `/api/v1/matches/${semi2.match_id}`, undefined, org)).body;
  assert.equal(vd.scoring.model, 'round');
  assert.equal(vd.scoring.periods.best_of, 5);
  const beta = await login('organizer.beta@nascon.test');
  const cricket = (await call('GET', '/api/v1/matches/demo-b1-r1-m1', undefined, beta)).body;
  assert.equal(cricket.scoring.model, 'innings');
  assert.ok(cricket.scoring.events.some((e) => e.wicket === true));
  assert.equal(cricket.home.score, 26);
  assert.equal(cricket.home.overs, '2.1');

  for (const email of ['manager@nascon.test', 'player@nascon.test', 'viewer@nascon.test', 'organizer.beta@nascon.test']) {
    assert.equal((await post(m, { type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal' } }, await login(email))).status, 403, email);
  }
  assert.equal((await post('demo-a2-r2-m1', { type: 'score', payload: { team_id: 'club-alpha-6', event_type: 'free_throw' } })).status, 403, 'organizer does not run the basketball league');
  assert.equal((await post('nope', { type: 'match_start' })).status, 404);

  // Ending a knockout match creates the next bracket match.
  const before = volley.length;
  await call('POST', `/api/v1/matches/${semi2.match_id}/status`, { status: 'in_progress' }, org);
  for (const t of [semi2.home.team_id, semi2.home.team_id, semi2.home.team_id]) await post(semi2.match_id, { type: 'score', payload: { team_id: t, event_type: 'set_won' } });
  assert.equal((await post(semi2.match_id, { type: 'score', payload: { team_id: semi2.away.team_id, event_type: 'set_won' } })).body.error.code, 'SERIES_ALREADY_DECIDED');
  await post(semi2.match_id, { type: 'match_end' });
  const after = (await call('GET', '/api/v1/fixtures?league_id=league-alpha-volley', undefined, org)).body.fixtures;
  assert.equal(after.length, before + 1);
  assert.equal(after.find((f) => f.stage === 'Final').away.team_id, semi2.home.team_id);
});

test('authenticated offline sync rejects actions the caller may not perform', async () => {
  const manager = await login('manager@nascon.test');
  const org = await login('organizer@nascon.test');
  const club = (await call('GET', '/api/v1/clubs/club-alpha-1', undefined, manager)).body;
  const mover = club.roster.find((p) => p.position === 'mf');
  const today = new Date().toISOString().slice(0, 10);
  const actions = [
    { action_id: 's1', type: 'score_event', queued_at: '2026-10-17T10:00:00Z', base_version: 0, payload: { event_id: 'off-goal', match_id: 'demo-a1-r2-m1', type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal' } } },
    { action_id: 's2', type: 'roster_transfer', queued_at: '2026-10-17T10:00:01Z', base_version: 0, payload: { request_id: 'off-tr', league_id: 'league-alpha-1', player_id: mover.player_id, type: 'loan', from_squad_id: 'club-alpha-1', to_squad_id: 'club-alpha-2', effective_date: today, loan_end_date: day(30) } },
  ];
  let r = await call('POST', '/api/v1/sync', { device_id: 'phone-m', actions }, manager);
  assert.deepEqual(r.body.results.map((x) => [x.status, x.error_code]), [['rejected', 'FORBIDDEN'], ['applied', null]]);
  r = await call('POST', '/api/v1/sync', { device_id: 'phone-o', actions }, org);
  assert.deepEqual(r.body.results.map((x) => [x.status, x.error_code]), [['applied', null], ['rejected', 'FORBIDDEN']]);
  r = await call('POST', '/api/v1/sync', { device_id: 'phone-o', actions }, org);
  assert.deepEqual(r.body.results.map((x) => x.status), ['duplicate', 'duplicate']);
  assert.equal((await call('POST', '/api/v1/sync', { device_id: 'x', actions })).status, 401);

  // Direct roster route: own club only, rules enforced by the engine.
  const tr = { request_id: 'direct-1', league_id: 'league-alpha-1', player_id: mover.player_id, type: 'release', from_squad_id: 'club-alpha-2', effective_date: today };
  assert.equal((await call('POST', '/api/v1/roster/transfer', tr, manager)).status, 403);
  const own = club.roster.find((p) => p.position === 'df');
  const ok = await call('POST', '/api/v1/roster/transfer', { ...tr, player_id: own.player_id, from_squad_id: 'club-alpha-1' }, manager);
  assert.equal(ok.status, 201);
  assert.equal(ok.body.audit_entry.who, 'manager@nascon.test');
  const closed = await call('POST', '/api/v1/roster/transfer', { request_id: 'direct-2', league_id: 'league-alpha-1', player_id: club.roster.find((p) => p.position === 'fw').player_id, type: 'transfer', from_squad_id: 'club-alpha-1', to_squad_id: 'club-alpha-3', effective_date: day(200) }, manager);
  assert.equal(closed.body.error.code, 'TRANSFER_WINDOW_CLOSED');
  const cross = club.roster.find((p) => p.position === 'gk' && p.player_id !== 'player-alpha-1');
  const xl = { request_id: 'cross-1', league_id: 'league-alpha-1', player_id: cross.player_id, type: 'transfer', from_squad_id: 'club-alpha-1', to_squad_id: 'club-alpha-5', effective_date: today };
  assert.equal((await call('POST', '/api/v1/roster/transfer', xl, manager)).body.error.code, 'CROSS_LEAGUE_TRANSFER');
  const xs = await call('POST', '/api/v1/sync', { device_id: 'phone-x', actions: [{ action_id: 'x1', type: 'roster_transfer', queued_at: '2026-10-17T10:00:00Z', base_version: 0, payload: xl }] }, manager);
  assert.equal(xs.body.results[0].error_code, 'CROSS_LEAGUE_TRANSFER');
  const hist = (await call('GET', '/api/v1/clubs/club-alpha-1/roster-history', undefined, manager)).body.history;
  assert.deepEqual(hist.slice(0, 2).map((h) => h.action).sort(), ['loan', 'release']);
});

test('pinning a product to a match page', async () => {
  const org = await login('organizer@nascon.test');
  const r = await call('POST', '/api/v1/matches/demo-a1-r2-m2/pin', { product_id: 'prod-demo-cap' }, org);
  assert.equal(r.status, 200);
  assert.equal(r.body.pinned_product.name, 'Falcons Snapback Cap');
  assert.equal((await call('GET', '/api/v1/matches/demo-a1-r2-m2', undefined, org)).body.pinned_product.product_id, 'prod-demo-cap');
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r2-m2/pin', { product_id: 'prod-demo-beta-shirt' }, org)).status, 404, 'other tenant product is invisible');
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r2-m2/pin', { product_id: null }, org)).body.pinned_product, null);
  assert.equal((await call('POST', '/api/v1/matches/demo-a1-r2-m2/pin', { product_id: 'prod-demo-cap' }, await login('viewer@nascon.test'))).status, 403);
});
