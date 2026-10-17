'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call, ev } = require('./helpers');
const { canonical, sign } = require('../src/lib/crypto');

before(start);
after(stop);
beforeEach(() => call('POST', '/audit/v1/reset'));

const kabaddi = {
  sport_id: 'kabaddi', name: 'Kabaddi', scoring_model: 'event', periods: { count: 2, duration_minutes: 20 },
  scoring_events: { raid_point: { points: 1 }, all_out: { points: 2 } }, draw_allowed: false,
  overtime: { policy: 'golden_score', duration_minutes: 5 },
  roster: { min_squad_size: 7, max_squad_size: 12, required_positions: { raider: 2 } },
};

test('FR-1.1 signature matches Appendix A test vector 1', () => {
  const prev = process.env.DAY1_SALT;
  process.env.DAY1_SALT = 'demo-salt';
  assert.equal(canonical({ team_id: 't1', event_type: 'goal' }), '{"event_type":"goal","team_id":"t1"}');
  assert.equal(sign('evt-1', { team_id: 't1', event_type: 'goal' }), '972a8b558690b19121cc5bea84978f85e8eb15a3735018db36616bab1d7ec501');
  process.env.DAY1_SALT = prev;
});

test('canonical JSON sorts nested keys, keeps arrays, no ASCII escaping', () => {
  assert.equal(canonical({ b: [3, { z: 1, a: null }], a: true, c: 'é' }), '{"a":true,"b":[3,{"a":null,"z":1}],"c":"é"}');
});

test('health is ok and reset seeds baseline', async () => {
  assert.deepEqual((await call('GET', '/health')).body, { status: 'ok' });
  const r = await call('POST', '/audit/v1/reset', { seed: 9, stock: { 'var-jersey-001-M': 4 } });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.sports, ['football', 'basketball', 'cricket', 'esports']);
  assert.deepEqual(r.body.stock, { 'var-jersey-001-M': 4, 'var-jersey-001-L': 5 });
  assert.equal((await call('POST', '/audit/v1/reset', { seed: 'x' })).status, 400);
  assert.equal((await call('POST', '/audit/v1/reset', { stock: { 'var-jersey-001-M': -1 } })).status, 400);
  assert.equal((await call('POST', '/audit/v1/reset', '{bad')).body.error.code, 'VALIDATION_ERROR');
  assert.equal((await call('GET', '/nope')).status, 404);
});

test('mystery sport is created from JSON and validated', async () => {
  const r = await call('POST', '/audit/v1/sports', kabaddi);
  assert.equal(r.status, 201);
  assert.equal(r.body.status, 'created');
  assert.deepEqual(r.body.config.tie_break_order, ['h2h_points', 'h2h_diff', 'overall_diff', 'scored', 'fair_play', 'draw_lots']);
  assert.equal((await call('POST', '/audit/v1/sports', kabaddi)).body.error.code, 'SPORT_EXISTS');
  const bad = await call('POST', '/audit/v1/sports', { sport_id: "x'; DROP TABLE sports;--" });
  assert.equal(bad.status, 400);
  assert.ok(bad.body.error.details.fields.includes('sport_id'));
  const badModels = [
    { ...kabaddi, sport_id: 'a1', scoring_model: 'innings', periods: { innings_per_team: 0 } },
    { ...kabaddi, sport_id: 'a2', scoring_model: 'round', periods: { best_of: 2 } },
    { ...kabaddi, sport_id: 'a3', scoring_events: { 'Bad Key': { points: 1 } } },
    { ...kabaddi, sport_id: 'a4', overtime: { policy: 'coin' } },
    { ...kabaddi, sport_id: 'a5', tie_break_order: ['scored', 'scored'] },
    { ...kabaddi, sport_id: 'a6', roster: { min_squad_size: 5, max_squad_size: 2, required_positions: {} } },
    { ...kabaddi, sport_id: 'a7', scoring_events: {} },
    { ...kabaddi, sport_id: 'a8', scoring_model: 'innings', periods: { innings_per_team: 1, overs_per_innings: 1, balls_per_over: 6, wickets_per_innings: 1 }, scoring_events: { x: { runs: -1, legal_ball: true, wicket: false } } },
  ];
  for (const b of badModels) assert.equal((await call('POST', '/audit/v1/sports', b)).status, 400, b.sport_id);
  assert.equal((await call('POST', '/audit/v1/sports', [])).status, 400);
});

test('event lifecycle, idempotency, compensation and projection', async () => {
  await call('POST', '/audit/v1/leagues', { league_id: 'lg', sport_id: 'football', teams: ['t1', 't2'], fixtures: [{ match_id: 'm1', home: 't1', away: 't2' }], qualification: { spots: 1 } });
  assert.equal((await ev('m1', 'score', { team_id: 't1', event_type: 'goal' })).body.error.code, 'MATCH_NOT_IN_PROGRESS');
  assert.equal((await ev('m1', 'match_end', {})).body.error.code, 'ILLEGAL_TRANSITION');
  const st = await ev('m1', 'match_start', {}, 'start');
  assert.equal(st.status, 201);
  assert.equal(st.body.sequence, 1);
  assert.equal((await ev('m1', 'match_start', {})).body.error.code, 'ILLEGAL_TRANSITION');

  const g1 = await ev('m1', 'score', { team_id: 't1', event_type: 'goal' }, 'g1');
  assert.equal(g1.status, 201);
  assert.equal(g1.body.signature, sign('g1', { team_id: 't1', event_type: 'goal' }));
  const replay = await ev('m1', 'score', { team_id: 't1', event_type: 'goal' }, 'g1');
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, g1.body);
  assert.equal((await ev('m1', 'score', { team_id: 't2', event_type: 'goal' }, 'g1')).body.error.code, 'DUPLICATE_EVENT_ID');
  assert.equal((await ev('m1', 'score', { team_id: 't1', event_type: 'touchdown' })).body.error.code, 'UNKNOWN_EVENT_TYPE');
  assert.equal((await ev('m1', 'score', { team_id: 'zz', event_type: 'goal' })).status, 400);
  assert.equal((await ev('m1', 'discipline', { team_id: 'zz', points: 1 })).status, 400);

  await ev('m1', 'score', { team_id: 't2', event_type: 'goal' }, 'g2');
  await ev('m1', 'discipline', { team_id: 't2', points: -2 }, 'card');
  assert.equal((await ev('m1', 'compensation', { compensates: 'g2', reason: 'offside' }, 'c1')).status, 201);
  assert.equal((await ev('m1', 'compensation', { compensates: 'g2' })).body.error.code, 'INVALID_COMPENSATION');
  assert.equal((await ev('m1', 'compensation', { compensates: 'start' })).body.error.code, 'INVALID_COMPENSATION');
  assert.equal((await ev('m1', 'compensation', { compensates: 'c1' })).body.error.code, 'INVALID_COMPENSATION');
  assert.equal((await ev('m1', 'compensation', { compensates: 'ghost' })).body.error.code, 'EVENT_NOT_FOUND');
  assert.equal((await ev('m1', 'match_end', {}, 'end')).status, 201);

  const s = (await call('GET', '/audit/v1/score/m1')).body;
  assert.equal(s.status, 'completed');
  assert.equal(s.outcome, 'home_win');
  assert.equal(s.winner_team_id, 't1');
  assert.equal(s.home.score, 1);
  assert.equal(s.away.score, 0);
  assert.equal(s.away.fair_play, -2);
  assert.equal(s.home.wickets, null);
  assert.equal(s.league_id, 'lg');
  assert.equal(s.version, 6);
  const g2 = s.events.find((e) => e.event_id === 'g2');
  assert.equal(g2.compensated, true);
  assert.equal(g2.compensated_by, 'c1');
  assert.equal((await call('GET', '/audit/v1/score/none')).body.error.code, 'MATCH_NOT_FOUND');
  assert.equal((await ev('none', 'match_start', {})).body.error.code, 'MATCH_NOT_FOUND');
});

test('match_init, draws, tie-break winner and undecided outcome', async () => {
  assert.equal((await ev('x', 'match_init', { sport_id: 'nope', home_team_id: 'a', away_team_id: 'b' })).body.error.code, 'SPORT_NOT_FOUND');
  assert.equal((await ev('x', 'match_init', { sport_id: 'basketball', home_team_id: 'a', away_team_id: 'a' })).status, 400);
  assert.equal((await ev('b1', 'match_init', { sport_id: 'basketball', home_team_id: 'h', away_team_id: 'a', league_id: 'free' })).status, 201);
  assert.equal((await ev('b1', 'match_init', { sport_id: 'basketball', home_team_id: 'h', away_team_id: 'a' })).body.error.code, 'MATCH_EXISTS');
  assert.equal((await ev('b1', 'tiebreak_winner', { team_id: 'a' })).body.error.code, 'MATCH_NOT_IN_PROGRESS');
  await ev('b1', 'match_start', {});
  await ev('b1', 'score', { team_id: 'h', event_type: 'two_pointer' });
  await ev('b1', 'score', { team_id: 'a', event_type: 'free_throw' });
  await ev('b1', 'score', { team_id: 'a', event_type: 'free_throw' });
  assert.equal((await ev('b1', 'match_end', {})).body.error.code, 'TIE_NOT_ALLOWED');
  await ev('b1', 'tiebreak_winner', { team_id: 'a' }, 'tb');
  assert.equal((await ev('b1', 'match_end', {})).status, 201);
  let s = (await call('GET', '/audit/v1/score/b1')).body;
  assert.equal(s.outcome, 'away_win');
  assert.equal(s.tiebreak_winner_team_id, 'a');
  await ev('b1', 'compensation', { compensates: 'tb', reason: 'review' });
  s = (await call('GET', '/audit/v1/score/b1')).body;
  assert.equal(s.outcome, 'undecided');
  assert.equal(s.winner_team_id, null);

  await ev('f1', 'match_init', { sport_id: 'football', home_team_id: 'h', away_team_id: 'a' });
  await ev('f1', 'match_start', {});
  await ev('f1', 'match_end', {});
  assert.equal((await call('GET', '/audit/v1/score/f1')).body.outcome, 'draw');
});

test('innings model limits, overs string and round model series limit', async () => {
  await call('POST', '/audit/v1/sports', {
    sport_id: 'mini', name: 'Mini', scoring_model: 'innings',
    periods: { innings_per_team: 1, overs_per_innings: 1, balls_per_over: 2, wickets_per_innings: 2 },
    scoring_events: { six: { runs: 6, legal_ball: true, wicket: false }, wd: { runs: 1, legal_ball: false, wicket: false }, out: { runs: 0, legal_ball: true, wicket: true } },
    draw_allowed: true, overtime: { policy: 'none' }, roster: { min_squad_size: 1, max_squad_size: 3, required_positions: {} },
  });
  await ev('c', 'match_init', { sport_id: 'mini', home_team_id: 'h', away_team_id: 'a' });
  await ev('c', 'match_start', {});
  await ev('c', 'score', { team_id: 'h', event_type: 'wd' });
  await ev('c', 'score', { team_id: 'h', event_type: 'six' });
  let s = (await call('GET', '/audit/v1/score/c')).body;
  assert.equal(s.home.overs, '0.1');
  assert.equal(s.home.balls, 1);
  await ev('c', 'score', { team_id: 'h', event_type: 'six' }, 'last');
  assert.equal((await ev('c', 'score', { team_id: 'h', event_type: 'six' })).body.error.code, 'INNINGS_COMPLETE');
  await ev('c', 'compensation', { compensates: 'last' });
  assert.equal((await ev('c', 'score', { team_id: 'h', event_type: 'six' })).status, 201);
  await ev('c', 'score', { team_id: 'a', event_type: 'out' });
  await ev('c', 'score', { team_id: 'a', event_type: 'out' });
  assert.equal((await ev('c', 'score', { team_id: 'a', event_type: 'six' })).body.error.code, 'INNINGS_COMPLETE');
  s = (await call('GET', '/audit/v1/score/c')).body;
  assert.equal(s.home.score, 13);
  assert.equal(s.away.wickets, 2);

  await ev('e', 'match_init', { sport_id: 'esports', home_team_id: 'h', away_team_id: 'a' });
  await ev('e', 'match_start', {});
  await ev('e', 'score', { team_id: 'h', event_type: 'round_win' });
  await ev('e', 'score', { team_id: 'h', event_type: 'round_win' });
  assert.equal((await ev('e', 'score', { team_id: 'a', event_type: 'round_win' })).body.error.code, 'SERIES_ALREADY_DECIDED');
});

test('envelope validation and league registration rules', async () => {
  assert.equal((await call('POST', '/audit/v1/events', { event_id: 'a|b', match_id: 'm', type: 'score', payload: {} })).status, 400);
  assert.equal((await call('POST', '/audit/v1/events', { event_id: 'a', match_id: 'm', type: 'party', payload: {} })).status, 400);
  assert.equal((await call('POST', '/audit/v1/events', 'null')).status, 400);
  for (const [type, payload] of [['score', {}], ['discipline', { team_id: 't', points: 'x' }], ['tiebreak_winner', {}], ['compensation', { compensates: 1 }], ['compensation', { compensates: 'x', reason: 5 }], ['match_init', { sport_id: '', home_team_id: '|', away_team_id: 'b', league_id: '|' }]]) {
    assert.equal((await ev('m', type, payload)).status, 400, type);
  }
  const lg = { league_id: 'l1', sport_id: 'football', teams: ['a', 'b'], fixtures: [{ match_id: 'f1', home: 'a', away: 'b' }], qualification: { spots: 1 } };
  assert.equal((await call('POST', '/audit/v1/leagues', { ...lg, sport_id: 'nope' })).body.error.code, 'SPORT_NOT_FOUND');
  assert.equal((await call('POST', '/audit/v1/leagues', lg)).status, 201);
  assert.equal((await call('POST', '/audit/v1/leagues', lg)).body.error.code, 'LEAGUE_EXISTS');
  assert.equal((await call('POST', '/audit/v1/leagues', { ...lg, league_id: 'l2' })).body.error.code, 'MATCH_EXISTS');
  for (const bad of [{ teams: ['a'] }, { fixtures: [{ match_id: 'z', home: 'a', away: 'a' }] }, { points: { win: 'x' } }, { qualification: { spots: 9 } }, { lots_seed: 'x' }, { tie_break_order: ['nope'] }, { fixtures: 'x' }]) {
    assert.equal((await call('POST', '/audit/v1/leagues', { ...lg, league_id: 'l3', ...bad })).status, 400, JSON.stringify(bad));
  }
  assert.equal((await call('POST', '/audit/v1/leagues', [])).status, 400);
});
