'use strict';

// Live WebSocket clients per match: match_id -> Set<socket>
function createStore() {
  return { byMatch: new Map() };
}

module.exports = { createStore };
