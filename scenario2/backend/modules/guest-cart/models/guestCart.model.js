'use strict';

// tokens: guest_token -> { guest_token, role: 'guest', merged, merge_key, merged_into, response }
// carts: user_id -> { user_id, items: [{ variant_id, quantity, unit_price_minor }] }
// guestCarts: guest_token -> items staged before login
function createStore() {
  return { tokens: new Map(), carts: new Map(), guestCarts: new Map() };
}

module.exports = { createStore };
