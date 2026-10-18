'use strict';

const express = require('express');
const controller = require('../controllers/streamKey.controller');

function streamingRouter() {
  const r = express.Router();
  r.post('/audit/v1/stream/key', controller.streamKey);
  r.post('/internal/media/auth', controller.mediaAuth);
  // MediaMTX posts finished recording segments as a form body.
  r.post('/internal/media/recorded', express.urlencoded({ extended: false }), controller.recorded);
  r.get('/api/v1/vods', controller.vods);
  return r;
}

module.exports = { streamingRouter };
