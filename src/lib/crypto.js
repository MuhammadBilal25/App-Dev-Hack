'use strict';

const crypto = require('crypto');

// Canonical JSON (Section 5.3): recursively sorted keys, no whitespace, UTF-8, no ASCII escaping.
function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  const keys = Object.keys(value).filter((k) => value[k] !== undefined).sort(compareCodePoints);
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
}

// Python's sort_keys orders by code point; JS default sort orders by UTF-16 unit.
function compareCodePoints(a, b) {
  const A = Array.from(a);
  const B = Array.from(b);
  for (let i = 0; i < Math.min(A.length, B.length); i++) {
    const d = A[i].codePointAt(0) - B[i].codePointAt(0);
    if (d !== 0) return d;
  }
  return A.length - B.length;
}

function salt() {
  return process.env.DAY1_SALT || '';
}

function sign(id, payload) {
  return crypto
    .createHmac('sha256', Buffer.from(salt(), 'utf8'))
    .update(Buffer.from(id + '|' + canonical(payload), 'utf8'))
    .digest('hex');
}

const sha256Hex = (s) => crypto.createHash('sha256').update(Buffer.from(s, 'utf8')).digest('hex');

module.exports = { canonical, sign, sha256Hex };
