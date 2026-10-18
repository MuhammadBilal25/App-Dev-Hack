'use strict';

const { notImplemented } = require('../../../shared/errors');

// GET /metrics: Prometheus text exposition (text/plain; version=0.0.4).
function metricsText() {
  // TODO: # HELP / # TYPE / value lines for the five nascon_* metrics
  throw notImplemented('GET /metrics');
}

// DELETE /audit/v1/privacy/user/{user_id} (NFR-9).
function eraseUser(userId) {
  // TODO: 404 PLAYER_NOT_FOUND -> anonymise PII -> wipe linked guest/viewer tokens
  throw notImplemented('DELETE /audit/v1/privacy/user/{user_id}');
}

module.exports = { metricsText, eraseUser };
