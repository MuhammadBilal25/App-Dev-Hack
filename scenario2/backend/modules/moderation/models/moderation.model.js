'use strict';

// rooms: chat_room_id -> { seq, messages, kicked, muted, seen: message_id -> result, recent: sender -> [ms] }
// dlq: notifications that failed after 3 delivery attempts.
function createStore() {
  return { rooms: new Map(), dlq: [] };
}

module.exports = { createStore };
