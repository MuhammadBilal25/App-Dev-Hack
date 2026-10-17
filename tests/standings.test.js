'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call, ev, playFootball } = require('./helpers');

before(start);
after(stop);
beforeEach(() => call('POST', '/audit/v1/reset'));

const table = async (id) => (await call('GET', `/audit/v1/standings/${id}`)).body;

test('draw_lots matches Appendix A test vector 2', async () => {
  await call('POST', '/audit/v1/leagues', { league_id: 'lg-1', sport_id: 'football', teams: ['t1', 't2', 't3'], fixtures: [], qualification: { spots: 1 }, lots_seed: 42 });
  const s = await table('lg-1');
  assert.deepEqual(s.table.map((r) => r.team_id), ['t1', 't3', 't2']);
  assert.equal(s.table[0].resolved_by, 'draw_lots');
  assert.equal(s.table[2].resolved_by, null);
});

test('three-way tie resolved through H2H mini-league, then recomputed after compensation', async () => {
  const fx = [['m1', 'A', 'B'], ['m2', 'B', 'C'], ['m3', 'C', 'A'], ['m4', 'A', 'D'], ['m5', 'B', 'D'], ['m6', 'C', 'D']];
  await call('POST', '/audit/v1/leagues', { league_id: 'l3', sport_id: 'football', teams: ['A', 'B', 'C', 'D'], fixtures: fx.map(([match_id, home, away]) => ({ match_id, home, away })), qualification: { spots: 2 } });
  await playFootball('m1', 'A', 'B', 1, 0);
  await playFootball('m2', 'B', 'C', 1, 0);
  await playFootball('m3', 'C', 'A', 1, 0);
  await playFootball('m4', 'A', 'D', 3, 0);
  await playFootball('m5', 'B', 'D', 2, 0);
  await playFootball('m6', 'C', 'D', 1, 0, ['c-goal']);
  let s = await table('l3');
  assert.deepEqual(s.table.map((r) => r.team_id), ['A', 'B', 'C', 'D']);
  assert.deepEqual(s.table.map((r) => r.resolved_by), ['overall_diff', 'overall_diff', null, null]);
  assert.deepEqual(s.h2h.A.B, { played: 1, points: 3, scored: 1, conceded: 0 });
  assert.deepEqual(s.h2h.D.A, { played: 1, points: 0, scored: 0, conceded: 3 });
  assert.equal(s.table[3].status, 'eliminated');

  await ev('m6', 'compensation', { compensates: 'c-goal', reason: 'VAR' });
  s = await table('l3');
  assert.deepEqual(s.table.map((r) => r.team_id), ['A', 'B', 'C', 'D']);
  assert.equal(s.table[0].resolved_by, 'h2h_points');
  assert.equal(s.table[2].points, 4);
  assert.equal(s.table[3].drawn, 1);
  assert.deepEqual(s.table.map((r) => r.status), ['clinched', 'clinched', 'eliminated', 'eliminated']);
});

test('configurable points, tie-break order, fair play and qualification', async () => {
  await call('POST', '/audit/v1/leagues', {
    league_id: 'q', sport_id: 'football', teams: ['a', 'b', 'c'], points: { win: 2, draw: 1, loss: 0 },
    tie_break_order: ['fair_play', 'scored'],
    fixtures: [{ match_id: 'q1', home: 'a', away: 'b' }, { match_id: 'q2', home: 'a', away: 'c' }, { match_id: 'q3', home: 'b', away: 'c' }],
    qualification: { spots: 1 },
  });
  await ev('q1', 'match_start', {});
  await ev('q1', 'discipline', { team_id: 'a', points: -3 });
  await ev('q1', 'match_end', {});
  let s = await table('q');
  assert.equal(s.table[0].points, 1);
  assert.equal(s.table.find((r) => r.team_id === 'a').fair_play, -3);
  assert.ok(s.table.every((r) => r.status === 'still_possible'));
  assert.equal(s.table[0].resolved_by, 'fair_play');
  await playFootball('q2', 'a', 'c', 2, 0);
  await playFootball('q3', 'b', 'c', 1, 0);
  s = await table('q');
  assert.deepEqual(s.table.map((r) => [r.team_id, r.points]), [['b', 3], ['a', 3], ['c', 0]]); // fair_play ranks first in this league
  assert.equal(s.table[2].status, 'eliminated');
  assert.equal((await call('GET', '/audit/v1/standings/none')).body.error.code, 'LEAGUE_NOT_FOUND');
});

test('undecided matches stay remaining; round-model differential', async () => {
  await call('POST', '/audit/v1/leagues', { league_id: 'e', sport_id: 'esports', teams: ['x', 'y'], fixtures: [{ match_id: 'e1', home: 'x', away: 'y' }], qualification: { spots: 1 } });
  await ev('e1', 'match_start', {});
  await ev('e1', 'score', { team_id: 'x', event_type: 'round_win' });
  await ev('e1', 'score', { team_id: 'y', event_type: 'round_win' });
  await ev('e1', 'tiebreak_winner', { team_id: 'y' }, 'tbw');
  await ev('e1', 'match_end', {});
  let s = await table('e');
  assert.equal(s.table[0].team_id, 'y');
  assert.equal(s.table[0].won, 1);
  assert.equal(s.table[0].diff, 0);
  await ev('e1', 'compensation', { compensates: 'tbw' });
  s = await table('e');
  assert.ok(s.table.every((r) => r.played === 0));
});

test('cricket net run rate counts an all-out innings as full overs', async () => {
  await call('POST', '/audit/v1/sports', {
    sport_id: 't2', name: 'T2', scoring_model: 'innings',
    periods: { innings_per_team: 1, overs_per_innings: 2, balls_per_over: 6, wickets_per_innings: 2 },
    scoring_events: { four: { runs: 4, legal_ball: true, wicket: false }, out: { runs: 0, legal_ball: true, wicket: true } },
    draw_allowed: true, overtime: { policy: 'none' }, roster: { min_squad_size: 1, max_squad_size: 5, required_positions: {} },
  });
  await call('POST', '/audit/v1/leagues', { league_id: 'ck', sport_id: 't2', teams: ['X', 'Y'], fixtures: [{ match_id: 'c1', home: 'X', away: 'Y' }], qualification: { spots: 1 } });
  await ev('c1', 'match_start', {});
  for (let i = 0; i < 12; i++) await ev('c1', 'score', { team_id: 'X', event_type: 'four' }); // 48 off 2 overs
  await ev('c1', 'score', { team_id: 'Y', event_type: 'four' });
  await ev('c1', 'score', { team_id: 'Y', event_type: 'out' });
  await ev('c1', 'score', { team_id: 'Y', event_type: 'out' }); // all out after 3 balls -> 2 full overs
  await ev('c1', 'match_end', {});
  const s = await table('ck');
  assert.equal(s.table[0].team_id, 'X');
  assert.equal(s.table[0].diff, 22); // 48/2 - 4/2
  assert.equal(s.table[1].diff, -22);
  assert.equal(s.table[0].scored, 48);
});
