'use strict';

const { err, validation } = require('../../lib/errors');
const { isObj, isInt } = require('../../lib/validate');

const RESULTS = ['home', 'away', 'draw'];

function validate(teams, params) {
  const n = teams.length;
  const bad = [];
  if (n < 2 || n > 64) bad.push('teams');
  const total = params.total_rounds === undefined ? Math.max(1, Math.min(n - 1, Math.ceil(Math.log2(n)))) : params.total_rounds;
  if (!isInt(total) || total < 1 || total > n - 1) bad.push('params.total_rounds');
  const round = params.round === undefined ? 1 : params.round;
  if (!isInt(round) || round < 1 || (isInt(total) && round > total)) bad.push('params.round');
  const history = params.history === undefined ? [] : params.history;
  if (!Array.isArray(history)) bad.push('params.history');
  if (bad.length) throw validation(bad);

  const set = new Set(teams);
  const rounds = history.map((h) => h && h.round).sort((a, b) => a - b);
  const exact = rounds.length === round - 1 && rounds.every((r, i) => r === i + 1);
  const wellFormed = history.every((h) => isObj(h) && Array.isArray(h.matches) && (h.bye === undefined || h.bye === null || set.has(h.bye)) &&
    h.matches.every((m) => isObj(m) && set.has(m.home) && set.has(m.away) && m.home !== m.away && RESULTS.includes(m.result)));
  if (!exact || !wellFormed) throw validation(['params.history']);
  return { total, round, history };
}

// Scores and Buchholz from history only.
function standingsFrom(teams, history) {
  const score = new Map(teams.map((t) => [t, 0]));
  const opponents = new Map(teams.map((t) => [t, []]));
  const hadBye = new Set();
  const met = new Set();
  for (const h of history) {
    if (h.bye) {
      score.set(h.bye, score.get(h.bye) + 1);
      hadBye.add(h.bye);
    }
    for (const m of h.matches) {
      const pts = m.result === 'home' ? [1, 0] : m.result === 'away' ? [0, 1] : [0.5, 0.5];
      score.set(m.home, score.get(m.home) + pts[0]);
      score.set(m.away, score.get(m.away) + pts[1]);
      opponents.get(m.home).push(m.away);
      opponents.get(m.away).push(m.home);
      met.add(pairKey(m.home, m.away));
    }
  }
  const seed = new Map(teams.map((t, i) => [t, i]));
  const rows = teams.map((t) => ({
    team_id: t,
    score: score.get(t),
    buchholz: opponents.get(t).reduce((s, o) => s + score.get(o), 0),
  }));
  rows.sort((a, b) => b.score - a.score || b.buchholz - a.buchholz || seed.get(a.team_id) - seed.get(b.team_id));
  return { rows: rows.map((r, i) => ({ rank: i + 1, ...r })), score, hadBye, met, seed };
}

const pairKey = (a, b) => (a < b ? `${a}\u0000${b}` : `${b}\u0000${a}`);

// Exact minimum-cost rematch-free perfect matching (cost = sum of |score difference|) by
// branch and bound. Lower bound: pairing the remaining players consecutively in score order
// is optimal when rematches are ignored, so it never overestimates.
function minCostMatching(players, score, met, budget = 1e6) {
  const list = [...players].sort((a, b) => score.get(b) - score.get(a));
  const n = list.length;
  const s = list.map((t) => score.get(t));
  const can = list.map((a) => list.map((b) => a !== b && !met.has(pairKey(a, b))));
  const used = new Array(n).fill(false);
  let best = null;
  let bestCost = Infinity;
  let steps = 0;
  const cur = [];

  const lowerBound = () => {
    let lb = 0;
    let prev = -1;
    for (let i = 0; i < n; i++) {
      if (used[i]) continue;
      if (prev === -1) prev = i;
      else {
        lb += Math.abs(s[prev] - s[i]);
        prev = -1;
      }
    }
    return lb;
  };

  let floor = 0; // the unconstrained optimum: reaching it means no better pairing can exist
  function search(cost) {
    if (++steps > budget || bestCost <= floor) return;
    let i = 0;
    while (i < n && used[i]) i++;
    if (i === n) {
      if (cost < bestCost) {
        bestCost = cost;
        best = [...cur];
      }
      return;
    }
    used[i] = true;
    const cands = [];
    for (let j = i + 1; j < n; j++) if (!used[j] && can[i][j]) cands.push(j);
    cands.sort((x, y) => Math.abs(s[i] - s[x]) - Math.abs(s[i] - s[y]));
    for (const j of cands) {
      const c = cost + Math.abs(s[i] - s[j]);
      used[j] = true;
      if (c + lowerBound() < bestCost) {
        cur.push([list[i], list[j]]);
        search(c);
        cur.pop();
      }
      used[j] = false;
      if (bestCost <= floor) break;
    }
    used[i] = false;
  }

  floor = lowerBound();
  search(0);
  return best;
}

function swiss(teams, params) {
  const { total, round, history } = validate(teams, params);
  const n = teams.length;
  const st = standingsFrom(teams, history);
  let pairs = null;
  let bye = null;

  if (round === 1) {
    const m = Math.floor(n / 2);
    if (n % 2 === 1) bye = teams[n - 1];
    pairs = [];
    for (let i = 0; i < m; i++) pairs.push([teams[i], teams[i + m]]);
  } else if (n % 2 === 0) {
    pairs = minCostMatching(teams, st.score, st.met);
  } else {
    // Bye goes to the lowest-scoring team without a bye yet (ties: lowest seed = largest index).
    let candidates = teams.filter((t) => !st.hadBye.has(t));
    if (!candidates.length) candidates = [...teams];
    candidates.sort((a, b) => st.score.get(a) - st.score.get(b) || st.seed.get(b) - st.seed.get(a));
    for (const c of candidates) {
      const p = minCostMatching(teams.filter((t) => t !== c), st.score, st.met);
      if (p) {
        pairs = p;
        bye = c;
        break;
      }
    }
  }

  if (!pairs) throw err(409, 'NO_VALID_PAIRING', `No rematch-free pairing exists for round ${round}.`, { round });

  // Home = better-placed team (lower seed number in round 1).
  const rank = new Map(st.rows.map((r) => [r.team_id, r.rank]));
  const ordered = round === 1 ? pairs : pairs.map(([a, b]) => (rank.get(a) <= rank.get(b) ? [a, b] : [b, a]));
  ordered.sort((x, y) => Math.min(rank.get(x[0]), rank.get(x[1])) - Math.min(rank.get(y[0]), rank.get(y[1])));

  return {
    format: 'swiss',
    round,
    total_rounds: total,
    pairings: ordered.map(([home, away], i) => ({ match_id: `SW-R${round}-M${i + 1}`, home, away })),
    bye,
    standings: st.rows,
  };
}

module.exports = { swiss, minCostMatching };
