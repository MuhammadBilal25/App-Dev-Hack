'use strict';

const express = require('express');
const controller = require('../controllers/qr.controller');

function qrRouter() {
  const r = express.Router();
  r.get('/audit/v1/qr/:entityId/export.:fmt', controller.exportQr);
  r.get('/audit/v1/qr/:entityId', controller.resolve);
  r.get('/q/:shortCode', controller.redirect);
  r.post('/audit/v1/matches/:matchId/status', controller.setMatchStatus);
  return r;
}

module.exports = { qrRouter };
