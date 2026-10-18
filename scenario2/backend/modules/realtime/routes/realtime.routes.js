'use strict';

const express = require('express');
const realtime = require('../../../../../src/realtime');

// SSE alternative for NFR-1: GET /api/v1/matches/{match_id}/stream (same events as the WebSocket).
function realtimeRouter() {
  const r = express.Router();
  r.get('/api/v1/matches/:matchId/stream', (req, res) => {
    realtime.subscribe({ query: { channels: `match:${req.params.matchId}` }, on: req.on.bind(req) }, res);
  });
  return r;
}

module.exports = { realtimeRouter };
