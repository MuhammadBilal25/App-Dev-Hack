'use strict';

const express = require('express');
const controller = require('../controllers/streamKey.controller');

function streamingRouter() {
  const r = express.Router();
  r.post('/audit/v1/stream/key', controller.streamKey);
  r.post('/internal/media/auth', controller.mediaAuth);
  return r;
}

module.exports = { streamingRouter };
