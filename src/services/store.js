'use strict';

const { pool } = require('../db');
const { state, clone } = require('../state');
const { ApiError, err, validation, errorBody } = require('../lib/errors');
const { canonical, sign } = require('../lib/crypto');
const { isObj, isInt, isStr, isId, nowIso } = require('../lib/validate');
const { receiptPdf } = require('../lib/pdf');
const queue = require('../queue');
const realtime = require('../realtime');

// Order lifecycle (FR-2.3). Every transition emits a domain event to the internal queue.
const ORDER_TRANSITIONS = {
  pending: ['paid', 'cancelled'],
  paid: ['packed', 'cancelled', 'refunded'],
  packed: ['shipped', 'cancelled', 'refunded'],
  shipped: ['delivered', 'refunded'],
  delivered: ['refunded'],
  cancelled: [],
  refunded: [],
};

function validateCheckout(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!isId(b.order_id)) bad.push('order_id');
  if (!isStr(b.customer_id) || b.customer_id.length < 1 || b.customer_id.length > 256) bad.push('customer_id');
  const items = b.items;
  if (!Array.isArray(items) || items.length < 1 || items.length > 10) bad.push('items');
  else {
    const ok = items.every((it) => isObj(it) && isStr(it.variant_id) && it.variant_id && isInt(it.quantity) && it.quantity >= 1 && it.quantity <= 10);
    if (!ok || new Set(items.map((it) => it && it.variant_id)).size !== items.length) bad.push('items');
  }
  if (b.discount_code !== undefined && b.discount_code !== null && !isStr(b.discount_code)) bad.push('discount_code');
  if (!isObj(b.payment) || !isStr(b.payment.token)) bad.push('payment');
  if (bad.length) throw validation(bad);
}

// Effective unit price of a variant right now: the latest scheduled price already in force (or the
// list price), lowered by a sale price when one is set. Baseline variants have neither.
function unitPrice(v) {
  let price = v.price_minor;
  const now = Date.now();
  let at = -Infinity;
  for (const s of v.price_schedule || []) {
    const t = Date.parse(s.effective_at);
    if (t <= now && t >= at) {
      at = t;
      price = s.price_minor;
    }
  }
  return Number.isInteger(v.sale_price_minor) && v.sale_price_minor < price ? v.sale_price_minor : price;
}

const activeDiscount = (code) => {
  const d = state.discounts.get(code);
  return d && d.active !== false ? d : null;
};

// Mock payment gateway: authorize then capture; refunds reverse a capture.
const gateway = {
  authorize(token) {
    if (token === 'tok_success' || token === 'tok_capture_fail') return { ok: true, authorization_id: `auth_${++state.paymentSeq}` };
    return { ok: false };
  },
  capture(token) {
    if (token === 'tok_success') return { ok: true, capture_id: `cap_${state.paymentSeq}` };
    return { ok: false };
  },
  refund(captureId) {
    return { ok: !!captureId, refund_id: `ref_${++state.paymentSeq}` };
  },
};

// Atomically reserve every line (all or nothing). The conditional UPDATE takes a row lock, so
// concurrent buyers serialize on the variant row and stock can never go negative.
async function reserve(items) {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const sorted = [...items].sort((a, b) => (a.variant_id < b.variant_id ? -1 : 1)); // fixed lock order: no deadlocks
    for (const it of sorted) {
      const r = await c.query(
        'UPDATE inventory SET stock = stock - $2, reserved = reserved + $2 WHERE variant_id = $1 AND stock >= $2',
        [it.variant_id, it.quantity],
      );
      if (r.rowCount === 0) {
        await c.query('ROLLBACK');
        throw err(409, 'OUT_OF_STOCK', `Variant ${it.variant_id} has no stock left.`, { variant_id: it.variant_id });
      }
    }
    await c.query('COMMIT');
  } catch (e) {
    if (!(e instanceof ApiError)) await c.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
}

async function release(items) {
  for (const it of items) {
    await pool.query('UPDATE inventory SET stock = stock + $2, reserved = reserved - $2 WHERE variant_id = $1', [it.variant_id, it.quantity]);
  }
}

async function commitReservation(items) {
  for (const it of items) {
    await pool.query('UPDATE inventory SET reserved = reserved - $2 WHERE variant_id = $1', [it.variant_id, it.quantity]);
  }
}

async function processCheckout(b) {
  const lines = b.items.map((it) => ({
    variant_id: it.variant_id,
    quantity: it.quantity,
    unit_price_minor: unitPrice(state.variants.get(it.variant_id)),
  }));
  const subtotal = lines.reduce((s, l) => s + l.unit_price_minor * l.quantity, 0);
  const discount = b.discount_code ? Math.floor((subtotal * activeDiscount(b.discount_code).percent) / 100) : 0;

  await reserve(lines);

  const token = b.payment.token;
  const auth = gateway.authorize(token);
  if (!auth.ok) {
    await release(lines);
    throw err(402, 'PAYMENT_DECLINED', 'The payment was declined.', { order_id: b.order_id });
  }
  const cap = gateway.capture(token);
  if (!cap.ok) {
    await release(lines); // authorization voided
    throw err(402, 'PAYMENT_CAPTURE_FAILED', 'The payment could not be captured.', { order_id: b.order_id, authorization_id: auth.authorization_id });
  }
  await commitReservation(lines);

  const payload = {
    order_id: b.order_id,
    customer_id: b.customer_id,
    items: lines,
    subtotal_minor: subtotal,
    discount_minor: discount,
    total_minor: subtotal - discount,
    currency: 'PKR',
    paid_at: nowIso(),
  };
  const signature = sign(b.order_id, payload);
  const pdf = await receiptPdf(payload, { signature, lines: describeLines ? describeLines(lines) : null });
  const body = {
    order_id: b.order_id,
    status: 'paid',
    currency: 'PKR',
    items: clone(lines),
    subtotal_minor: subtotal,
    discount_minor: discount,
    total_minor: payload.total_minor,
    payment: { authorization_id: auth.authorization_id, capture_id: cap.capture_id, state: 'captured' },
    receipt: { payload, signature, pdf_base64: pdf.toString('base64') },
  };
  queue.emit('order.status_changed', { order_id: b.order_id, from: 'pending', to: 'paid', at: payload.paid_at });
  for (const l of lines) realtime.publish('store', 'inventory_changed', { variant_id: l.variant_id });
  return body;
}

async function checkout(b) {
  validateCheckout(b);
  const key = canonical(b);
  const prior = state.orders.get(b.order_id);
  if (prior) {
    if (prior.key !== key) throw err(409, 'DUPLICATE_ORDER_ID', `Order ${b.order_id} was already used with a different body.`, { order_id: b.order_id });
    const r = await prior.promise;
    return { status: r.status === 201 ? 200 : r.status, body: clone(r.body) };
  }
  for (const it of b.items) {
    if (!state.variants.has(it.variant_id)) throw err(404, 'VARIANT_NOT_FOUND', `Variant ${it.variant_id} does not exist.`, { variant_id: it.variant_id });
  }
  if (b.discount_code !== undefined && b.discount_code !== null && !activeDiscount(b.discount_code)) {
    throw err(400, 'INVALID_DISCOUNT_CODE', `Discount code ${b.discount_code} is not valid.`, { discount_code: b.discount_code });
  }

  // Register the order id synchronously so a concurrent identical replay waits for this result.
  const promise = processCheckout(b).then(
    (body) => ({ status: 201, body }),
    (e) => {
      if (e instanceof ApiError) return { status: e.status, body: errorBody(e) };
      throw e;
    },
  );
  const entry = { key, promise, status: 'pending' };
  state.orders.set(b.order_id, entry);
  const r = await promise;
  entry.status = r.status === 201 ? 'paid' : 'failed';
  entry.tenant_id = state.variants.get(b.items[0].variant_id).tenant_id;
  entry.customer_id = b.customer_id;
  pool
    .query('INSERT INTO orders (order_id, request, status, http_status, response) VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING', [
      b.order_id, b, entry.status, r.status, r.body,
    ])
    .catch(() => {});
  return r;
}

async function inventory(variantId) {
  if (!state.variants.has(variantId)) throw err(404, 'VARIANT_NOT_FOUND', `Variant ${variantId} does not exist.`, { variant_id: variantId });
  const r = await pool.query('SELECT stock, reserved FROM inventory WHERE variant_id = $1', [variantId]);
  const row = r.rows[0] || { stock: 0, reserved: 0 };
  return { variant_id: variantId, stock: row.stock, reserved: row.reserved };
}

// Moves a paid order along its lifecycle (production route, Club Manager / Super Admin).
function transitionOrder(orderId, to) {
  const o = state.orders.get(orderId);
  if (!o || o.status === 'failed') throw err(404, 'ORDER_NOT_FOUND', `Order ${orderId} does not exist.`, { order_id: orderId });
  if (!(ORDER_TRANSITIONS[o.status] || []).includes(to)) {
    throw err(409, 'ILLEGAL_TRANSITION', `Order cannot move from ${o.status} to ${to}.`, { order_id: orderId, from: o.status, to });
  }
  const from = o.status;
  o.status = to;
  queue.emit('order.status_changed', { order_id: orderId, from, to, at: nowIso() });
  return { order_id: orderId, status: to };
}

// Puts refunded or cancelled units back on sale.
async function restock(items) {
  for (const it of items) {
    await pool.query('UPDATE inventory SET stock = stock + $2 WHERE variant_id = $1', [it.variant_id, it.quantity]);
  }
}

// Sets the units available for sale (inventory management). Units held by in-flight checkouts
// stay in `reserved` and are unaffected.
async function setStock(variantId, stock) {
  await pool.query('UPDATE inventory SET stock = $2 WHERE variant_id = $1', [variantId, stock]);
}

async function addInventory(variantId, stock) {
  await pool.query('INSERT INTO inventory (variant_id, stock, reserved) VALUES ($1, $2, 0) ON CONFLICT (variant_id) DO NOTHING', [variantId, stock]);
}

// Optional human-readable line labels for the PDF (product name, size, colour), set by the
// production store. The signed payload is unaffected.
let describeLines = null;
const setLineDescriber = (fn) => { describeLines = fn; };

function catalogue(tenantId) {
  return [...state.products.values()].filter((p) => !tenantId || p.tenant_id === tenantId).map(clone);
}

module.exports = {
  checkout, inventory, transitionOrder, catalogue, ORDER_TRANSITIONS, unitPrice, activeDiscount, gateway, restock, setStock, addInventory,
  setLineDescriber,
};
