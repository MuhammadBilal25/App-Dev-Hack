'use strict';

// Co-stream sessions. sessions: session_id -> { request_key, response }
function createStore() {
  return { sessions: new Map() };
}

module.exports = { createStore };
