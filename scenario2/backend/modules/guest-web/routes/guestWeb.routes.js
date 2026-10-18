'use strict';

const path = require('path');
const express = require('express');
const controller = require('../controllers/guestWeb.controller');

function guestWebRouter() {
  const r = express.Router();
  // Guest Web Player (FR-4.2): zero install, zero account.
  r.use('/web/assets', express.static(path.join(controller.WEB_DIR, 'assets'), { maxAge: 0 }));
  r.get(/^\/web(\/.*)?$/, controller.page);

  // Guest API (read-only, plus local cart staging).
  r.post('/api/v1/guest/session', controller.session);
  r.get('/api/v1/guest/matches/:matchId', controller.match);
  r.get('/api/v1/guest/costream/:sessionId', controller.costream);
  r.get('/api/v1/guest/players/:playerId', controller.player);
  r.get('/api/v1/guest/clubs/:clubId', controller.club);
  r.post('/api/v1/guest/cart', controller.stageItem);
  r.get('/api/v1/guest/cart', controller.getCart);
  r.post('/api/v1/guest/merge', controller.merge);

  // Signed-in member cart used by the web player (checkout goes through POST /api/v1/checkout).
  r.get('/api/v1/member-cart', controller.memberCart);
  r.post('/api/v1/member-cart', controller.memberAdd);
  r.post('/api/v1/member-cart/set', controller.memberSet);
  r.post('/api/v1/member-cart/clear', controller.memberClear);
  return r;
}

module.exports = { guestWebRouter };
