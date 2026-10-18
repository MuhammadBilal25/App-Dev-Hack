'use strict';

// Stream keys. keys: stream_key -> { stream_key, player_id, label, status, created_at }
// activeByPlayer: player_id -> the player's current stream_key.
// vods: recorded segments uploaded to MinIO: { path, key, url, stored, recorded_at }
function createStore() {
  return { keys: new Map(), activeByPlayer: new Map(), vods: [] };
}

module.exports = { createStore };
