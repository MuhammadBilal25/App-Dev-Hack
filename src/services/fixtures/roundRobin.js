'use strict';

const { validation } = require('../../lib/errors');
const { isObj, isInt } = require('../../lib/validate');

const BYE = null;

// Circle method: seat 0 is fixed, the others rotate one place per round. Home/away comes from a
// balanced orientation of the complete graph: with m odd (m = n, or n + 1 with a dummy vertex
// when n is even), team i hosts team j iff (j - i) mod m is in 1..(m-1)/2. Every team then has
// exactly (m-1)/2 home and away games, minus at most one dummy game, so |home - away| <= 1.
function circleRounds(teams) {
  const seats = teams.length % 2 === 1 ? [...teams, BYE] : [...teams];
  const n = seats.length;
  const idx = new Map(teams.map((t, i) => [t, i]));
  const m = teams.length % 2 === 1 ? teams.length : teams.length + 1;
  const hosts = (a, b) => {
    const d = (((idx.get(b) - idx.get(a)) % m) + m) % m;
    return d >= 1 && d <= (m - 1) / 2;
  };
  const rounds = [];
  let arr = seats;
  for (let r = 0; r < n - 1; r++) {
    const pairs = [];
    for (let i = 0; i < n / 2; i++) {
      const a = arr[i];
      const b = arr[n - 1 - i];
      pairs.push(a === BYE || b === BYE || hosts(a, b) ? [a, b] : [b, a]);
    }
    rounds.push(pairs);
    arr = [arr[0], arr[n - 1], ...arr.slice(1, n - 1)];
  }
  return rounds;
}

function validate(teams, params) {
  const bad = [];
  if (teams.length < 2 || teams.length > 40) bad.push('teams');
  const legs = params.legs === undefined ? 1 : params.legs;
  if (legs !== 1 && legs !== 2) bad.push('params.legs');
  const policy = params.withdrawal_policy === undefined ? 'forfeit_remaining' : params.withdrawal_policy;
  if (!['void_all', 'forfeit_remaining'].includes(policy)) bad.push('params.withdrawal_policy');
  const wd = params.withdrawals === undefined ? [] : params.withdrawals;
  if (!Array.isArray(wd) || !wd.every(isObj)) bad.push('params.withdrawals');
  if (bad.length) throw validation(bad);
  return { legs, policy, wd };
}

function roundRobin(teams, params) {
  const { legs, policy, wd } = validate(teams, params);
  const perLeg = teams.length % 2 === 0 ? teams.length - 1 : teams.length;
  const roundCount = perLeg * legs;

  const withdrawnAfter = new Map();
  for (const w of wd) {
    if (!teams.includes(w.team_id) || !isInt(w.after_round) || w.after_round < 0 || w.after_round > roundCount || withdrawnAfter.has(w.team_id)) {
      throw validation(['params.withdrawals']);
    }
    withdrawnAfter.set(w.team_id, w.after_round);
  }
  const gone = (team, round) => withdrawnAfter.has(team) && round > withdrawnAfter.get(team);

  const base = circleRounds(teams);
  const rounds = [];
  const summary = { total: 0, scheduled: 0, forfeit: 0, voided: 0 };

  for (let leg = 1; leg <= legs; leg++) {
    base.forEach((pairs, r) => {
      const round = (leg - 1) * perLeg + r + 1;
      const matches = [];
      const byes = [];
      for (const [h0, a0] of pairs) {
        const [home, away] = leg === 2 ? [a0, h0] : [h0, a0];
        if (home === BYE || away === BYE) {
          byes.push(home === BYE ? away : home);
          continue;
        }
        let status = 'scheduled';
        let awardedTo = null;
        if (policy === 'void_all') {
          if (withdrawnAfter.has(home) || withdrawnAfter.has(away)) status = 'voided';
        } else if (gone(home, round) && gone(away, round)) status = 'voided';
        else if (gone(home, round)) [status, awardedTo] = ['forfeit', away];
        else if (gone(away, round)) [status, awardedTo] = ['forfeit', home];
        if (withdrawnAfter.has(home) && withdrawnAfter.has(away) && status !== 'scheduled') [status, awardedTo] = ['voided', null];

        matches.push({ match_id: `RR-L${leg}-R${round}-M${matches.length + 1}`, leg, home, away, status, awarded_to: awardedTo });
        summary.total += 1;
        summary[status === 'scheduled' ? 'scheduled' : status === 'forfeit' ? 'forfeit' : 'voided'] += 1;
      }
      rounds.push({ round, matches, byes });
    });
  }

  return { format: 'round_robin', legs, team_count: teams.length, round_count: roundCount, rounds, summary };
}

module.exports = { roundRobin, circleRounds };
