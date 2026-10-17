'use strict';

// Identifier rule (Section 5.2): 1-64 chars from A-Za-z0-9_.:-
const ID_RE = /^[A-Za-z0-9_.:-]{1,64}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isInt = (v) => typeof v === 'number' && Number.isInteger(v);
const isStr = (v) => typeof v === 'string';
const isId = (v) => isStr(v) && ID_RE.test(v);
const isBool = (v) => typeof v === 'boolean';

function isDate(v) {
  if (!isStr(v) || !DATE_RE.test(v)) return false;
  const d = new Date(v + 'T00:00:00Z');
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
}

// Adds days to a YYYY-MM-DD string.
function addDays(date, n) {
  const d = new Date(date + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

const today = () => new Date().toISOString().slice(0, 10);
const nowIso = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

module.exports = { isObj, isInt, isStr, isId, isBool, isDate, addDays, today, nowIso, ID_RE };
