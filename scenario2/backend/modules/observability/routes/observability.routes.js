'use strict';

const express = require('express');
const controller = require('../controllers/observability.controller');

function observabilityRouter() {
  const r = express.Router();
  r.get('/metrics', controller.metrics);
  r.delete('/audit/v1/privacy/user/:userId', controller.eraseUser);
  return r;
}

module.exports = { observabilityRouter };
