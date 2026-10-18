'use strict';

const { err } = require('../../../src/lib/errors');

// FR-4.3: a guest_anon_tok_* bearer may never mutate state. Enforced on the server for every
// write method, before any Day 1 or Day 2 route runs. Hiding buttons in the UI is not enough.
const WRITE_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

// Write routes a guest IS allowed to call (local guest cart staging). Exact paths.
const GUEST_ALLOWED = new Set([]);

function bearer(req) {
  const m = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization || '');
  return m ? m[1] : null;
}

const isGuestToken = (t) => typeof t === 'string' && t.startsWith('guest_');

function guestWriteGuard(req, res, next) {
  const token = bearer(req);
  if (WRITE_METHODS.has(req.method) && isGuestToken(token) && !GUEST_ALLOWED.has(req.path)) {
    throw err(403, 'GUEST_WRITE_FORBIDDEN', 'Anonymous guest tokens cannot perform write mutations.', { guest_token: token });
  }
  next();
}

module.exports = { guestWriteGuard, isGuestToken, bearer, GUEST_ALLOWED };
