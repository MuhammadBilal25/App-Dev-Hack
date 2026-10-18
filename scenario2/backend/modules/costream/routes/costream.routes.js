'use strict';

const express = require('express');
const controller = require('../controllers/costream.controller');

function costreamRouter() {
  const r = express.Router();
  r.post('/audit/v1/costream/session', controller.createSession);
  return r;
}

module.exports = { costreamRouter };
