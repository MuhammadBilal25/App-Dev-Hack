'use strict';

const { validation } = require('../../lib/errors');
const { isObj, isStr } = require('../../lib/validate');

const ABSENT = Symbol('absent'); // a missing seed (bye) flowing through the bracket

// order(2) = [1, 2]; order(2k) = for each s in order(k): [s, 2k + 1 - s]
function seedOrder(size) {
  let order = [1, 2];
  while (order.length < size) {
    const k2 = order.length * 2;
    order = order.flatMap((s) => [s, k2 + 1 - s]);
  }
  return order;
}

const nextPow2 = (n) => {
  let b = 1;
  while (b < n) b *= 2;
  return b;
};

// A graph of matches. Slots hold undefined (unknown), ABSENT, or { team, seed }.
class Bracket {
  constructor() {
    this.matches = new Map();
  }

  add(id, bracket, round, index, extra = {}) {
    const m = { match_id: id, bracket, round, index, slots: { home: undefined, away: undefined }, winner: undefined, loser: undefined, winner_to: null, loser_to: null, bye: false, ...extra };
    this.matches.set(id, m);
    return m;
  }

  route(fromId, kind, toId, slot) {
    this.matches.get(fromId)[kind] = { match_id: toId, slot };
  }

  place(target, value) {
    if (!target) return;
    this.matches.get(target.match_id).slots[target.slot] = value;
  }

  decide(m, winner, loser) {
    m.winner = winner;
    m.loser = loser;
    this.place(m.winner_to, winner);
    this.place(m.loser_to, loser);
  }

  // Auto-advance matches with a missing participant until nothing changes.
  settle() {
    for (let changed = true; changed; ) {
      changed = false;
      for (const m of this.matches.values()) {
        if (m.winner !== undefined || m.manual) continue;
        const { home, away } = m.slots;
        if (home === undefined || away === undefined) continue;
        if (home === ABSENT && away === ABSENT) this.decide(m, ABSENT, ABSENT);
        else if (home === ABSENT || away === ABSENT) {
          m.bye = true;
          this.decide(m, home === ABSENT ? away : home, ABSENT);
        } else continue;
        changed = true;
      }
    }
  }

  // Applies {match_id, winner} results, in dependency order; any leftover is invalid.
  applyResults(results, onDecided) {
    if (!Array.isArray(results) || !results.every((r) => isObj(r) && isStr(r.match_id) && isStr(r.winner))) throw validation(['params.results']);
    for (const r of results) if (!this.matches.has(r.match_id)) throw validation(['params.results']);
    let pending = [...results];
    this.settle();
    while (pending.length) {
      const rest = [];
      for (const r of pending) {
        const m = this.matches.get(r.match_id);
        const { home, away } = m.slots;
        const ready = home !== undefined && away !== undefined;
        if (!ready) {
          rest.push(r);
          continue;
        }
        const teams = [home, away].filter((s) => s && s !== ABSENT).map((s) => s.team);
        if (!teams.includes(r.winner)) throw validation(['params.results']);
        if (m.winner !== undefined && m.winner !== ABSENT) {
          if (m.winner.team !== r.winner) throw validation(['params.results']);
          continue;
        }
        const w = home && home !== ABSENT && home.team === r.winner ? home : away;
        const l = w === home ? away : home;
        this.decide(m, w, l);
        if (onDecided) onDecided(m);
        this.settle();
      }
      if (rest.length === pending.length) throw validation(['params.results']);
      pending = rest;
    }
  }

  view(m, extra = {}) {
    const team = (s) => (s && s !== ABSENT ? s.team : null);
    const seed = (s) => (s && s !== ABSENT ? s.seed : null);
    return {
      match_id: m.match_id,
      bracket: m.bracket,
      round: m.round,
      index: m.index,
      home: team(m.slots.home),
      away: team(m.slots.away),
      home_seed: seed(m.slots.home),
      away_seed: seed(m.slots.away),
      bye: m.bye,
      winner: team(m.winner),
      loser: team(m.loser),
      winner_to: m.winner_to,
      loser_to: m.loser_to,
      ...extra,
    };
  }
}

function validateTeams(teams, min, max) {
  if (teams.length < min || teams.length > max) throw validation(['teams']);
}

// Round 1 of the main / winners bracket: identical for single and double elimination.
function seedFirstRound(br, teams, size, idOf, bracketName) {
  const order = seedOrder(size);
  const slot = (seed) => (seed <= teams.length ? { team: teams[seed - 1], seed } : ABSENT);
  for (let i = 1; i <= size / 2; i++) {
    const a = order[2 * i - 2];
    const b = order[2 * i - 1];
    const [hs, as] = a < b ? [a, b] : [b, a];
    const m = br.add(idOf(1, i), bracketName, 1, i);
    m.slots.home = slot(hs);
    m.slots.away = slot(as);
  }
}

function singleElim(teams, params) {
  validateTeams(teams, 2, 128);
  const third = params.third_place_match === undefined ? false : params.third_place_match;
  if (typeof third !== 'boolean') throw validation(['params.third_place_match']);

  const size = nextPow2(teams.length);
  const rounds = Math.log2(size);
  const id = (r, i) => `R${r}M${i}`;
  const br = new Bracket();
  seedFirstRound(br, teams, size, id, 'main');
  for (let r = 2; r <= rounds; r++) for (let i = 1; i <= size / 2 ** r; i++) br.add(id(r, i), 'main', r, i);
  for (let r = 1; r < rounds; r++) {
    for (let i = 1; i <= size / 2 ** r; i++) br.route(id(r, i), 'winner_to', id(r + 1, Math.ceil(i / 2)), i % 2 === 1 ? 'home' : 'away');
  }
  if (third && rounds >= 2) {
    br.add('TP', 'third_place', rounds, 2);
    br.route(id(rounds - 1, 1), 'loser_to', 'TP', 'home');
    br.route(id(rounds - 1, 2), 'loser_to', 'TP', 'away');
  }
  br.applyResults(params.results === undefined ? [] : params.results);

  const out = [];
  for (let r = 1; r <= rounds; r++) {
    const matches = [];
    for (let i = 1; i <= size / 2 ** r; i++) matches.push(br.view(br.matches.get(id(r, i))));
    if (r === rounds && br.matches.has('TP')) matches.push(br.view(br.matches.get('TP')));
    out.push({ round: r, matches });
  }
  return { format: 'single_elim', bracket_size: size, rounds: out };
}

function doubleElim(teams, params) {
  validateTeams(teams, 3, 128);
  const reset = params.bracket_reset === undefined ? false : params.bracket_reset;
  if (typeof reset !== 'boolean') throw validation(['params.bracket_reset']);

  const size = nextPow2(teams.length);
  const k = Math.log2(size);
  const W = (r, i) => `WR${r}M${i}`;
  const L = (r, i) => `LR${r}M${i}`;
  const br = new Bracket();

  seedFirstRound(br, teams, size, W, 'winners');
  for (let r = 2; r <= k; r++) for (let i = 1; i <= size / 2 ** r; i++) br.add(W(r, i), 'winners', r, i);
  const lrCount = (r) => size / 2 ** (Math.ceil(r / 2) + 1);
  for (let r = 1; r <= 2 * (k - 1); r++) for (let i = 1; i <= lrCount(r); i++) br.add(L(r, i), 'losers', r, i);
  br.add('GF1', 'grand_final', 1, 1);
  if (reset) br.add('GF2', 'grand_final', 2, 1, { manual: true });

  // Winners bracket.
  for (let r = 1; r < k; r++) {
    for (let i = 1; i <= size / 2 ** r; i++) br.route(W(r, i), 'winner_to', W(r + 1, Math.ceil(i / 2)), i % 2 === 1 ? 'home' : 'away');
  }
  br.route(W(k, 1), 'winner_to', 'GF1', 'home');
  // WR1 losers meet each other in LR1; WRr (r >= 2) losers drop into LR(2r-2) away slots.
  for (let i = 1; i <= size / 2; i++) br.route(W(1, i), 'loser_to', L(1, Math.ceil(i / 2)), i % 2 === 1 ? 'home' : 'away');
  for (let r = 2; r <= k; r++) for (let i = 1; i <= size / 2 ** r; i++) br.route(W(r, i), 'loser_to', L(2 * r - 2, i), 'away');

  // Losers bracket: odd rounds feed the next even round 1:1 (home); even rounds halve.
  for (let r = 1; r <= 2 * (k - 1); r++) {
    for (let i = 1; i <= lrCount(r); i++) {
      if (r === 2 * (k - 1)) br.route(L(r, i), 'winner_to', 'GF1', 'away');
      else if (r % 2 === 1) br.route(L(r, i), 'winner_to', L(r + 1, i), 'home');
      else br.route(L(r, i), 'winner_to', L(r + 1, Math.ceil(i / 2)), i % 2 === 1 ? 'home' : 'away');
    }
  }
  if (reset) {
    br.route('GF1', 'winner_to', 'GF2', 'home');
    br.route('GF1', 'loser_to', 'GF2', 'away');
  }

  br.applyResults(params.results === undefined ? [] : params.results);

  const gf1 = br.matches.get('GF1');
  const gf1Done = gf1.winner !== undefined && gf1.winner !== ABSENT;
  const lbChampWon = gf1Done && gf1.slots.away && gf1.slots.away !== ABSENT && gf1.winner.team === gf1.slots.away.team;
  const required = gf1Done ? reset && lbChampWon : null;

  const roundsOf = (prefix, count, per, fn) => {
    const out = [];
    for (let r = 1; r <= count; r++) {
      const matches = [];
      for (let i = 1; i <= per(r); i++) matches.push(fn(br.matches.get(prefix(r, i))));
      out.push({ round: r, matches });
    }
    return out;
  };
  const std = (m) => br.view(m, { conditional: false, required: true });
  const grand = [br.view(gf1, { conditional: false, required: true })];
  if (reset) grand.push(br.view(br.matches.get('GF2'), { conditional: true, required }));

  return {
    format: 'double_elim',
    bracket_size: size,
    bracket_reset: reset,
    winners: roundsOf(W, k, (r) => size / 2 ** r, std),
    losers: roundsOf(L, 2 * (k - 1), lrCount, std),
    grand_final: grand,
  };
}

module.exports = { singleElim, doubleElim, seedOrder, nextPow2 };
