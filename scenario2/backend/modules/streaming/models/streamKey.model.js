'use strict';

// Stream keys. keys: stream_key -> { stream_key, player_id, label, status, created_at }
// activeByPlayer: player_id -> the player's current stream_key.
function createStore() {
  return { keys: new Map(), activeByPlayer: new Map() };
}

module.exports = { createStore };
