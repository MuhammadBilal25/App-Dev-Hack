'use strict';

const crypto = require('crypto');
const { canonical } = require('../../../src/lib/crypto');
const { day2Salt } = require('../config');

// Spec 5.3: HMAC-SHA256(DAY2_SALT, entity_id + "|" + canonical(sig_payload)), lowercase hex.
// canonical() is the same sorted-keys, no-whitespace JSON used for Day 1.
function signDay2(entityId, sigPayload) {
  return crypto
    .createHmac('sha256', Buffer.from(day2Salt(), 'utf8'))
    .update(Buffer.from(entityId + '|' + canonical(sigPayload), 'utf8'))
    .digest('hex');
}

module.exports = { signDay2 };
