'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call } = require('./helpers');
const { roundRobin } = require('../src/services/fixtures/roundRobin');
const { swiss, minCostMatching } = require('../src/services/fixtures/swiss');
const { singleElim, doubleElim, seedOrder } = require('../src/services/fixtures/bracket');

before(start);
after(stop);

const T = (n) => Array.from({ length: n }, (_, i) => `t${i + 1}`);

test('FR-1.3 round robin: circle-method properties for 2..40 teams, 1 and 2 legs', () => {
  for (let n = 2; n <= 40; n++) {
    for (const legs of [1, 2]) {
      const r = roundRobin(T(n), { legs });
      const perLeg = n % 2 ? n : n - 1;
      assert.equal(r.round_count, perLeg * legs);
      const pairs = new Map();
      const ordered = new Set();
      const bal = new Map();
      for (const rd of r.rounds) {
        const seen = new Set(rd.byes);
        assert.equal(rd.byes.length, n % 2);
        assert.equal(rd.matches.length, Math.floor(n / 2));
        for (const m of rd.matches) {
          assert.ok(!seen.has(m.home) && !seen.has(m.away));
          seen.add(m.home).add(m.away);
          const k = [m.home, m.away].sort().join();
          pairs.set(k, (pairs.get(k) || 0) + 1);
          ordered.add(`${m.home}>${m.away}`);
          const leg = m.leg;
          bal.set(`${leg}${m.home}`, (bal.get(`${leg}${m.home}`) || 0) + 1);
          bal.set(`${leg}${m.away}`, (bal.get(`${leg}${m.away}`) || 0) - 1);
          assert.match(m.match_id, new RegExp(`^RR-L${leg}-R${rd.round}-M\\d+$`));
        }
        assert.equal(seen.size, n);
      }
      assert.equal(pairs.size, (n * (n - 1)) / 2);
      for (const v of pairs.values()) assert.equal(v, legs);
      if (legs === 2) assert.equal(ordered.size, n * (n - 1));
      for (const v of bal.values()) assert.ok(Math.abs(v) <= 1);
    }
  }
});

test('round robin withdrawals: forfeit_remaining and void_all', () => {
  const f = roundRobin(T(5), { withdrawals: [{ team_id: 't3', after_round: 2 }] });
  assert.deepEqual(f.summary, { total: 10, scheduled: 8, forfeit: 2, voided: 0 });
  for (const rd of f.rounds) {
    for (const m of rd.matches) {
      if ((m.home === 't3' || m.away === 't3') && rd.round > 2) {
        assert.equal(m.status, 'forfeit');
        assert.equal(m.awarded_to, m.home === 't3' ? m.away : m.home);
      }
    }
  }
  const v = roundRobin(T(4), { withdrawal_policy: 'void_all', withdrawals: [{ team_id: 't1', after_round: 1 }] });
  assert.equal(v.summary.voided, 3);
  const both = roundRobin(T(4), { withdrawals: [{ team_id: 't1', after_round: 0 }, { team_id: 't2', after_round: 0 }] });
  assert.equal(both.summary.voided, 1);
  assert.equal(both.summary.forfeit, 4);
  assert.throws(() => roundRobin(T(4), { withdrawals: [{ team_id: 'zz', after_round: 1 }] }));
  assert.throws(() => roundRobin(T(4), { withdrawals: [{ team_id: 't1', after_round: 99 }] }));
  assert.throws(() => roundRobin(T(4), { legs: 3 }));
  assert.throws(() => roundRobin(T(4), { withdrawal_policy: 'x' }));
  assert.throws(() => roundRobin(T(4), { withdrawals: 'x' }));
  assert.throws(() => roundRobin(T(41), {}));
});

test('swiss round 1 exact pairing and odd bye', () => {
  const r = swiss(T(7), {});
  assert.deepEqual(r.pairings.map((p) => [p.home, p.away]), [['t1', 't4'], ['t2', 't5'], ['t3', 't6']]);
  assert.equal(r.bye, 't7');
  assert.equal(r.total_rounds, 3);
});

test('swiss spec example: scores, buchholz, bye and pairing', () => {
  const r = swiss(['t1', 't2', 't3', 't4', 't5'], {
    total_rounds: 3, round: 2,
    history: [{ round: 1, bye: 't5', matches: [{ home: 't1', away: 't3', result: 'home' }, { home: 't2', away: 't4', result: 'draw' }] }],
  });
  assert.equal(r.bye, 't3');
  assert.deepEqual(r.standings.slice(0, 3), [
    { rank: 1, team_id: 't1', score: 1, buchholz: 0 },
    { rank: 2, team_id: 't5', score: 1, buchholz: 0 },
    { rank: 3, team_id: 't2', score: 0.5, buchholz: 0.5 },
  ]);
  const cost = r.pairings.reduce((s, p) => s + Math.abs(r.standings.find((x) => x.team_id === p.home).score - r.standings.find((x) => x.team_id === p.away).score), 0);
  assert.equal(cost, 1);
});

test('swiss matching is optimal and rematch-free (brute force)', () => {
  const brute = (ps, score, met) => {
    let best = Infinity;
    const rec = (rest, c) => {
      if (!rest.length) return void (best = Math.min(best, c));
      const [a, ...o] = rest;
      o.forEach((b, j) => {
        if (!met.has(a < b ? `${a}\u0000${b}` : `${b}\u0000${a}`)) rec(o.filter((_, x) => x !== j), c + Math.abs(score.get(a) - score.get(b)));
      });
    };
    rec(ps, 0);
    return best;
  };
  let rng = 7;
  const rand = () => ((rng = (rng * 1103515245 + 12345) % 2147483648) / 2147483648);
  for (let t = 0; t < 400; t++) {
    const n = 2 * (2 + Math.floor(rand() * 3));
    const ps = T(n);
    const score = new Map(ps.map((p) => [p, Math.floor(rand() * 6) / 2]));
    const met = new Set();
    for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) if (rand() < 0.3) met.add(ps[i] < ps[j] ? `${ps[i]}\u0000${ps[j]}` : `${ps[j]}\u0000${ps[i]}`);
    const m = minCostMatching(ps, score, met);
    const c = m ? m.reduce((s, [a, b]) => s + Math.abs(score.get(a) - score.get(b)), 0) : Infinity;
    assert.equal(c, brute(ps, score, met));
  }
});

test('swiss full tournament never repeats pairings; 409 when impossible', () => {
  const teams = T(8);
  const history = [];
  const met = new Set();
  for (let r = 1; r <= 7; r++) {
    const p = swiss(teams, { total_rounds: 7, round: r, history });
    for (const m of p.pairings) {
      const k = [m.home, m.away].sort().join();
      assert.ok(!met.has(k));
      met.add(k);
    }
    history.push({ round: r, bye: null, matches: p.pairings.map((m) => ({ home: m.home, away: m.away, result: 'home' })) });
  }
  // 4 teams, everyone already met everyone: no rematch-free pairing for round 4.
  const h = [
    { round: 1, bye: null, matches: [{ home: 't1', away: 't2', result: 'home' }, { home: 't3', away: 't4', result: 'home' }] },
    { round: 2, bye: null, matches: [{ home: 't1', away: 't3', result: 'home' }, { home: 't2', away: 't4', result: 'home' }] },
    { round: 3, bye: null, matches: [{ home: 't1', away: 't4', result: 'home' }, { home: 't2', away: 't3', result: 'draw' }] },
  ];
  assert.throws(() => swiss(T(4), { total_rounds: 3, round: 4, history: h }));
  try {
    swiss(T(4), { total_rounds: 3, round: 3, history: [h[0], { ...h[1], matches: [{ home: 't1', away: 't4', result: 'home' }, { home: 't2', away: 't3', result: 'away' }] }] });
  } catch (e) {
    assert.fail(e.message);
  }
  const odd = swiss(T(5), { total_rounds: 4, round: 2, history: [{ round: 1, bye: 't5', matches: [{ home: 't1', away: 't3', result: 'away' }, { home: 't2', away: 't4', result: 'home' }] }] });
  assert.ok(odd.bye !== 't5');
  assert.throws(() => swiss(T(4), { round: 2, history: [] }));
  assert.throws(() => swiss(T(4), { total_rounds: 9 }));
  assert.throws(() => swiss(T(4), { round: 1, history: 'x' }));
  assert.throws(() => swiss(T(1), {}));
});

test('NO_VALID_PAIRING surfaces as 409 through the API', async () => {
  // After these three rounds only the triangles {t1,t2,t3} and {t4,t5,t6} are unplayed: no
  // perfect matching exists.
  const rd = (round, pairs) => ({ round, bye: null, matches: pairs.map(([home, away]) => ({ home, away, result: 'draw' })) });
  const history = [
    rd(1, [['t1', 't4'], ['t2', 't5'], ['t3', 't6']]),
    rd(2, [['t1', 't5'], ['t2', 't6'], ['t3', 't4']]),
    rd(3, [['t1', 't6'], ['t2', 't4'], ['t3', 't5']]),
  ];
  const r = await call('POST', '/audit/v1/fixtures', { format: 'swiss', teams: T(6), params: { total_rounds: 5, round: 4, history } });
  assert.equal(r.status, 409);
  assert.equal(r.body.error.code, 'NO_VALID_PAIRING');
  assert.equal(r.body.error.details.round, 4);
  const ok = await call('POST', '/audit/v1/fixtures', { format: 'swiss', teams: T(6), params: { total_rounds: 5, round: 3, history: history.slice(0, 2) } });
  assert.equal(ok.status, 200);
});

test('single elimination: seeding, byes, propagation, third place', () => {
  assert.deepEqual(seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
  const se = singleElim(T(6), { results: [{ match_id: 'R1M2', winner: 't4' }] });
  assert.equal(se.bracket_size, 8);
  assert.equal(se.rounds.length, 3);
  const [m1, m2, m3, m4] = se.rounds[0].matches;
  assert.deepEqual([m1.home, m1.away, m1.bye, m1.winner], ['t1', null, true, 't1']);
  assert.deepEqual([m2.home, m2.away, m2.winner, m2.loser], ['t4', 't5', 't4', 't5']);
  assert.deepEqual(m2.winner_to, { match_id: 'R2M1', slot: 'away' });
  assert.equal(m3.bye, true);
  assert.equal(m4.home_seed, 3);
  const r2 = se.rounds[1].matches[0];
  assert.deepEqual([r2.home, r2.away, r2.home_seed, r2.away_seed], ['t1', 't4', 1, 4]);
  assert.equal(se.rounds[2].matches[0].winner_to, null);

  const tp = singleElim(T(4), { third_place_match: true, results: [{ match_id: 'R1M1', winner: 't1' }, { match_id: 'R1M2', winner: 't3' }, { match_id: 'TP', winner: 't4' }] });
  const third = tp.rounds[1].matches.find((m) => m.match_id === 'TP');
  assert.equal(third.bracket, 'third_place');
  assert.deepEqual([third.home, third.away, third.winner], ['t4', 't2', 't4']);
  assert.throws(() => singleElim(T(4), { results: [{ match_id: 'R9M9', winner: 't1' }] }));
  assert.throws(() => singleElim(T(4), { results: [{ match_id: 'R1M1', winner: 't2' }] }));
  assert.throws(() => singleElim(T(4), { results: [{ match_id: 'R2M1', winner: 't1' }] }));
  assert.throws(() => singleElim(T(4), { results: 'x' }));
  assert.throws(() => singleElim(T(4), { third_place_match: 'yes' }));
  assert.throws(() => singleElim(T(1), {}));
});

test('double elimination: counts, routing graph and bracket reset', () => {
  for (let n = 3; n <= 64; n++) {
    for (const reset of [true, false]) {
      const d = doubleElim(T(n), { bracket_reset: reset });
      const all = [...d.winners.flatMap((r) => r.matches), ...d.losers.flatMap((r) => r.matches), ...d.grand_final];
      assert.equal(d.losers.flatMap((r) => r.matches).length, d.bracket_size - 2);
      const feeds = new Map();
      for (const m of all) {
        for (const k of ['winner_to', 'loser_to']) if (m[k]) feeds.set(`${m[k].match_id}.${m[k].slot}`, (feeds.get(`${m[k].match_id}.${m[k].slot}`) || 0) + 1);
        if (m.bracket === 'winners') assert.ok(m.loser_to);
        if (m.bracket === 'losers') assert.equal(m.loser_to, null);
      }
      for (const m of all) if (!(m.bracket === 'winners' && m.round === 1)) for (const s of ['home', 'away']) assert.equal(feeds.get(`${m.match_id}.${s}`), 1);
    }
  }
  const play = (n, lbWins) => {
    let results = [];
    for (;;) {
      const d = doubleElim(T(n), { bracket_reset: true, results });
      const all = [...d.winners.flatMap((r) => r.matches), ...d.losers.flatMap((r) => r.matches), ...d.grand_final];
      const next = all.find((m) => m.home && m.away && !m.winner && !(m.match_id === 'GF2' && m.required !== true));
      if (!next) return d;
      let w = Number(next.home.slice(1)) < Number(next.away.slice(1)) ? next.home : next.away;
      if (next.match_id === 'GF1' && lbWins) w = next.away;
      results = [...results, { match_id: next.match_id, winner: w }];
    }
  };
  const a = play(8, true);
  assert.equal(a.grand_final[1].conditional, true);
  assert.equal(a.grand_final[1].required, true);
  assert.ok(a.grand_final[1].winner);
  const b = play(6, false);
  assert.equal(b.grand_final[1].required, false);
  assert.equal(doubleElim(T(4), { bracket_reset: true }).grand_final[1].required, null);
  assert.equal(doubleElim(T(4), {}).grand_final.length, 1);
  assert.throws(() => doubleElim(T(2), {}));
  assert.throws(() => doubleElim(T(4), { bracket_reset: 1 }));
});

test('fixtures endpoint validation', async () => {
  assert.equal((await call('POST', '/audit/v1/fixtures', { format: 'x', teams: T(2) })).status, 400);
  assert.equal((await call('POST', '/audit/v1/fixtures', { format: 'round_robin', teams: ['a', 'a'] })).status, 400);
  assert.equal((await call('POST', '/audit/v1/fixtures', { format: 'round_robin', teams: T(3), params: 5 })).status, 400);
  assert.equal((await call('POST', '/audit/v1/fixtures', [])).status, 400);
  const ok = await call('POST', '/audit/v1/fixtures', { format: 'double_elim', teams: T(5), params: { bracket_reset: true } });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.bracket_size, 8);
});
