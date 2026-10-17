'use strict';

const { validation } = require('../../lib/errors');
const { isObj, isId } = require('../../lib/validate');
const { roundRobin } = require('./roundRobin');
const { swiss } = require('./swiss');
const { singleElim, doubleElim } = require('./bracket');

const FORMATS = { round_robin: roundRobin, swiss, single_elim: singleElim, double_elim: doubleElim };

// POST /audit/v1/fixtures -- pure computation, nothing is stored.
function generate(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!FORMATS[b.format]) bad.push('format');
  if (!Array.isArray(b.teams) || !b.teams.every(isId) || new Set(b.teams).size !== b.teams.length) bad.push('teams');
  if (b.params !== undefined && b.params !== null && !isObj(b.params)) bad.push('params');
  if (bad.length) throw validation(bad);
  return { status: 200, body: FORMATS[b.format](b.teams, b.params || {}) };
}

module.exports = { generate };
