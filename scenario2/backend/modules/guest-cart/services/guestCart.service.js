'use strict';

const { notImplemented } = require('../../../shared/errors');

// POST /audit/v1/guest/cart-merge (spec 5.7): 403 write-block probe + atomic, idempotent merge.
async function cartMerge(body) {
  // TODO: 400 -> 404 PLAYER_NOT_FOUND / VARIANT_NOT_FOUND -> 409 OUT_OF_STOCK -> write-block probe
  //       -> merge -> replay 200 / 409 GUEST_TOKEN_ALREADY_MERGED -> signDay2(guest_token, ...)
  throw notImplemented('POST /audit/v1/guest/cart-merge');
}

module.exports = { cartMerge };
