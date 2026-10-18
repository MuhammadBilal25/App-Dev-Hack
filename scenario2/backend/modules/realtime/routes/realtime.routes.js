'use strict';

const express = require('express');

// SSE alternative for NFR-1: GET /api/v1/matches/{match_id}/stream (added with this module).
function realtimeRouter() {
  const r = express.Router();
  return r;
}

module.exports = { realtimeRouter };
