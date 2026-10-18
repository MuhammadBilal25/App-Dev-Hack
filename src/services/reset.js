'use strict';

const { pool } = require('../db');
const { state, resetMemory } = require('../state');
const seed = require('../seed');
const { validation } = require('../lib/errors');
const { isInt } = require('../lib/validate');
const { applyDemo, DEMO_STOCK } = require('../demo');
const { resetDay2 } = require('../../scenario2/backend/shared/seed');

function parseResetBody(body) {
  const b = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const bad = [];
  let seedValue = 42;
  if (b.seed !== undefined && b.seed !== null) {
    if (!isInt(b.seed)) bad.push('seed');
    else seedValue = b.seed;
  }
  const stock = { ...seed.DEFAULT_STOCK };
  if (b.stock !== undefined && b.stock !== null) {
    if (typeof b.stock !== 'object' || Array.isArray(b.stock)) bad.push('stock');
    else {
      for (const [k, v] of Object.entries(b.stock)) {
        if (!isInt(v) || v < 0) bad.push('stock');
        else if (k in stock) stock[k] = v;
      }
    }
  }
  if (bad.length) throw validation(bad);
  return { seedValue, stock };
}

let resetChain = Promise.resolve();

// Resets are serialized so two overlapping calls can never interleave.
function reset(body) {
  const { seedValue, stock } = parseResetBody(body);
  const run = resetChain.then(() => doReset(seedValue, stock));
  resetChain = run.catch(() => {});
  return run;
}

async function doReset(seedValue, stock) {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    await c.query('TRUNCATE inventory, orders, match_events, audit_log, domain_events, activity_log RESTART IDENTITY');
    for (const [variantId, qty] of Object.entries(stock)) {
      await c.query('INSERT INTO inventory (variant_id, stock, reserved) VALUES ($1, $2, 0)', [variantId, qty]);
    }
    // Demo store products (not part of the reset response).
    for (const [variantId, qty] of Object.entries(DEMO_STOCK)) {
      await c.query('INSERT INTO inventory (variant_id, stock, reserved) VALUES ($1, $2, 0)', [variantId, qty]);
    }
    await c.query('COMMIT');
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
  resetMemory(seedValue);
  applyDemo();
  resetDay2();
  state.ready = true;
  return {
    status: 'reset_complete',
    seed: seedValue,
    sports: seed.SPORTS.map((s) => s.sport_id),
    tenants: seed.TENANTS.map((t) => t.tenant_id),
    stock,
  };
}

module.exports = { reset };
