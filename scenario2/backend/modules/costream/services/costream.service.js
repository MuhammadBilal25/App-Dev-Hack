'use strict';

const { notImplemented } = require('../../../shared/errors');

// POST /audit/v1/costream/session (spec 5.5): validate in order, then host-drop handoff.
function createSession(body) {
  // TODO: 400 -> 404 PLAYER_NOT_FOUND -> 409 COSTREAM_SESSION_FULL -> 400 UNSUPPORTED_LAYOUT -> handoff
  throw notImplemented('POST /audit/v1/costream/session');
}

module.exports = { createSession };
