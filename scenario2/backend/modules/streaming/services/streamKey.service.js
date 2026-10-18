'use strict';

const { notImplemented } = require('../../../shared/errors');

// POST /audit/v1/stream/key (spec 5.4): generate (201) / rotate (200) / revoke (200).
function handleStreamKey(body) {
  // TODO: 400 VALIDATION_ERROR -> 404 PLAYER_NOT_FOUND -> apply action -> signDay2(stream_key, ...)
  throw notImplemented('POST /audit/v1/stream/key');
}

module.exports = { handleStreamKey };
