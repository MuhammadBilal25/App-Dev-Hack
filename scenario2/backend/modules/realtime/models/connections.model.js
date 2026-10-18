'use strict';

// Live WebSocket clients per channel ("match:<id>", "chat:<room>", "costream:<id>") -> Set<socket>
function createStore() {
  return { byMatch: new Map() };
}

module.exports = { createStore };
