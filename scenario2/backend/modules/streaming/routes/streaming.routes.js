'use strict';

const express = require('express');
const controller = require('../controllers/streamKey.controller');

function streamingRouter() {
  const r = express.Router();
  r.post('/audit/v1/stream/key', controller.streamKey);
  return r;
}

module.exports = { streamingRouter };
