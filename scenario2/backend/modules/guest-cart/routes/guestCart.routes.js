'use strict';

const express = require('express');
const controller = require('../controllers/guestCart.controller');

function guestCartRouter() {
  const r = express.Router();
  r.post('/audit/v1/guest/cart-merge', controller.cartMerge);
  return r;
}

module.exports = { guestCartRouter };
