'use strict';

// NFR-1: ws://localhost:8080/ws/matches/{match_id}; score events must reach clients in < 500 ms.
// attach(server) is called from src/server.js once the HTTP server exists.
function attach(server) {
  // TODO: handle upgrades on /ws/matches/:id, track connections, forward match:{id} events
}

module.exports = { attach };
