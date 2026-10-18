'use strict';

const { notImplemented } = require('../../../shared/errors');

// POST /audit/v1/moderation/test (spec 5.8): leetspeak masking, flood mute, DLQ inspection.
function moderate(body) {
  // TODO: normalise + mask profanity -> kick; flood -> drop + mute; DLQ depth -> signDay2
  throw notImplemented('POST /audit/v1/moderation/test');
}

// POST /api/v1/chat: members post to a room (guests are already stopped by guestWriteGuard).
function postChat(req) {
  // TODO: authenticate member, moderate, broadcast with the room sequence number
  throw notImplemented('POST /api/v1/chat');
}

module.exports = { moderate, postChat };
