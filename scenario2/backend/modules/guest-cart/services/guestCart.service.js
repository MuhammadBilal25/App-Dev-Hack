'use strict';

const { state, clone } = require('../../../../../src/state');
const { pool } = require('../../../../../src/db');
const { ApiError, err, validation } = require('../../../../../src/lib/errors');
const { isObj, isStr, isInt, isBool } = require('../../../../../src/lib/validate');
const { canonical } = require('../../../../../src/lib/crypto');
const { signDay2 } = require('../../../shared/signature');
const { guestWriteGuard } = require('../../../shared/guestGuard');

const store = () => state.day2.guestCart;

function validate(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!(isStr(b.guest_token) && b.guest_token.startsWith('guest_') && b.guest_token.length > 'guest_'.length)) bad.push('guest_token');
  if (!isStr(b.registered_user_id) || !b.registered_user_id) bad.push('registered_user_id');
  if (!Array.isArray(b.guest_cart) || b.guest_cart.length < 1 || b.guest_cart.length > 10) bad.push('guest_cart');
  else {
    b.guest_cart.forEach((it, i) => {
      if (!isObj(it) || !isStr(it.variant_id) || !it.variant_id) bad.push(`guest_cart[${i}].variant_id`);
      if (!isObj(it) || !isInt(it.quantity) || it.quantity < 1) bad.push(`guest_cart[${i}].quantity`);
    });
  }
  if (b.test_write_block !== undefined && b.test_write_block !== null && !isBool(b.test_write_block)) bad.push('test_write_block');
  if (bad.length) throw validation(bad);
}

// Registered users are seeded players (spec 5.2) or platform accounts.
const userExists = (id) => state.players.has(id) || [...state.users.values()].some((u) => u.user_id === id);

// Simulates a guest write (a chat post) through the real guard and returns the status it got.
function probeWriteBlock(guestToken) {
  try {
    guestWriteGuard({ method: 'POST', path: '/api/v1/chat', headers: { authorization: `Bearer ${guestToken}` } }, null, () => {});
  } catch (e) {
    if (e instanceof ApiError) return e.status;
    throw e;
  }
  return 200;
}

async function availableStock(variantId) {
  const r = await pool.query('SELECT stock, reserved FROM inventory WHERE variant_id = $1', [variantId]);
  return r.rows[0] ? r.rows[0].stock : 0;
}

function cartView(userId) {
  const cart = store().carts.get(userId) || { user_id: userId, items: [] };
  const items = cart.items.map((it) => ({ variant_id: it.variant_id, quantity: it.quantity, unit_price_minor: it.unit_price_minor }));
  return {
    user_id: userId,
    currency: 'PKR',
    total_items: items.reduce((n, it) => n + it.quantity, 0),
    subtotal_minor: items.reduce((n, it) => n + it.quantity * it.unit_price_minor, 0),
    items,
  };
}

async function doMerge(b, key) {
  const userId = b.registered_user_id;
  const cart = store().carts.get(userId) || { user_id: userId, items: [] };

  // Quantity per variant after the merge (same variant_id: quantities are summed).
  const merged = new Map(cart.items.map((it) => [it.variant_id, it.quantity]));
  for (const it of b.guest_cart) merged.set(it.variant_id, (merged.get(it.variant_id) || 0) + it.quantity);
  for (const it of b.guest_cart) {
    const stock = await availableStock(it.variant_id);
    if (merged.get(it.variant_id) > stock) {
      throw err(409, 'OUT_OF_STOCK', `Only ${stock} of ${it.variant_id} available.`, { variant_id: it.variant_id, available: stock });
    }
  }

  const testBlock = b.test_write_block !== false;
  const rejection = testBlock ? probeWriteBlock(b.guest_token) : null;

  // Commit in one synchronous step so the cart is never half-merged.
  const items = [...cart.items];
  for (const it of b.guest_cart) {
    const line = items.find((x) => x.variant_id === it.variant_id);
    if (line) line.quantity += it.quantity;
    else items.push({ variant_id: it.variant_id, quantity: it.quantity, unit_price_minor: state.variants.get(it.variant_id).price_minor });
  }
  store().carts.set(userId, { user_id: userId, items });
  store().guestCarts.delete(b.guest_token);

  const active = cartView(userId);
  const body = {
    guest_token: b.guest_token,
    write_block_verified: testBlock && rejection === 403,
    write_rejection_code: rejection,
    cart_merged: true,
    active_cart: active,
    signature: signDay2(b.guest_token, {
      cart_merged: true,
      guest_token: b.guest_token,
      registered_user_id: userId,
      total_items: active.total_items,
      write_rejection_code: rejection,
    }),
  };
  const token = store().tokens.get(b.guest_token) || { guest_token: b.guest_token, role: 'guest' };
  Object.assign(token, { merged: true, merge_key: key, merged_into: userId, response: body });
  store().tokens.set(b.guest_token, token);
  return body;
}

// POST /audit/v1/guest/cart-merge (spec 5.7).
async function cartMerge(b) {
  validate(b);
  if (!userExists(b.registered_user_id)) {
    throw err(404, 'PLAYER_NOT_FOUND', `User ${b.registered_user_id} does not exist.`, { registered_user_id: b.registered_user_id });
  }
  for (const it of b.guest_cart) {
    if (!state.variants.has(it.variant_id)) throw err(404, 'VARIANT_NOT_FOUND', `Variant ${it.variant_id} does not exist.`, { variant_id: it.variant_id });
  }

  const key = canonical({ guest_token: b.guest_token, registered_user_id: b.registered_user_id, guest_cart: b.guest_cart });
  const token = store().tokens.get(b.guest_token);

  // Edge case 4: a replay of the same merge (network switch) returns the merged cart unchanged.
  if (token && token.merged) {
    if (token.merge_key !== key) {
      throw err(409, 'GUEST_TOKEN_ALREADY_MERGED', `Guest token ${b.guest_token} was already merged.`, { guest_token: b.guest_token });
    }
    return { status: 200, body: clone(token.response) };
  }
  if (token && token.pending) {
    if (token.pending.key !== key) {
      throw err(409, 'GUEST_TOKEN_ALREADY_MERGED', `Guest token ${b.guest_token} is being merged.`, { guest_token: b.guest_token });
    }
    return { status: 200, body: clone(await token.pending.promise) };
  }

  // Register the merge synchronously so a concurrent identical request waits for this one.
  const entry = token || { guest_token: b.guest_token, role: 'guest', merged: false };
  store().tokens.set(b.guest_token, entry);
  const promise = doMerge(b, key);
  entry.pending = { key, promise };
  try {
    return { status: 200, body: clone(await promise) };
  } finally {
    delete entry.pending;
  }
}

module.exports = { cartMerge, cartView };
