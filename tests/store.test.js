'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { start, stop, call } = require('./helpers');
const { sign } = require('../src/lib/crypto');
const store = require('../src/services/store');

before(start);
after(stop);
beforeEach(() => call('POST', '/audit/v1/reset', { stock: { 'var-jersey-001-M': 1, 'var-jersey-001-L': 5 } }));

const order = (id, extra = {}) => ({
  order_id: id, customer_id: 'cust-001', items: [{ variant_id: 'var-jersey-001-M', quantity: 1 }], discount_code: null, payment: { token: 'tok_success' }, ...extra,
});

test('NFR-3: 20 simultaneous buyers of the last unit -> exactly one order', async () => {
  const res = await Promise.all(Array.from({ length: 20 }, (_, i) => call('POST', '/audit/v1/checkout', order(`ord-${i}`))));
  assert.equal(res.filter((r) => r.status === 201).length, 1);
  assert.equal(res.filter((r) => r.status === 409 && r.body.error.code === 'OUT_OF_STOCK').length, 19);
  assert.deepEqual((await call('GET', '/audit/v1/inventory/var-jersey-001-M')).body, { variant_id: 'var-jersey-001-M', stock: 0, reserved: 0 });
});

test('successful checkout returns a signed receipt and a real PDF', async () => {
  const r = await call('POST', '/audit/v1/checkout', order('ord-1'));
  assert.equal(r.status, 201);
  assert.equal(r.body.total_minor, 450000);
  assert.deepEqual(r.body.payment.state, 'captured');
  assert.equal(r.body.receipt.signature, sign('ord-1', r.body.receipt.payload));
  const pdf = Buffer.from(r.body.receipt.pdf_base64, 'base64');
  assert.equal(pdf.subarray(0, 4).toString(), '%PDF');
  const replay = await call('POST', '/audit/v1/checkout', order('ord-1'));
  assert.equal(replay.status, 200);
  assert.equal(replay.body.receipt.signature, r.body.receipt.signature);
  assert.equal((await call('POST', '/audit/v1/checkout', order('ord-1', { customer_id: 'other' }))).body.error.code, 'DUPLICATE_ORDER_ID');
});

test('discount, payment failures release stock, validation order', async () => {
  const L = { items: [{ variant_id: 'var-jersey-001-L', quantity: 2 }] };
  const d = await call('POST', '/audit/v1/checkout', order('d1', { ...L, discount_code: 'WELCOME10' }));
  assert.equal(d.body.discount_minor, 90000);
  assert.equal(d.body.total_minor, 810000);
  assert.equal((await call('POST', '/audit/v1/checkout', order('d2', { ...L, payment: { token: 'tok_declined' } }))).body.error.code, 'PAYMENT_DECLINED');
  const cf = await call('POST', '/audit/v1/checkout', order('d3', { ...L, payment: { token: 'tok_capture_fail' } }));
  assert.equal(cf.status, 402);
  assert.equal(cf.body.error.code, 'PAYMENT_CAPTURE_FAILED');
  assert.equal((await call('GET', '/audit/v1/inventory/var-jersey-001-L')).body.stock, 3);
  assert.equal((await call('POST', '/audit/v1/checkout', order('d2', { ...L, payment: { token: 'tok_declined' } }))).status, 402);
  assert.equal((await call('POST', '/audit/v1/checkout', order('x1', { discount_code: 'FREE' }))).body.error.code, 'INVALID_DISCOUNT_CODE');
  assert.equal((await call('POST', '/audit/v1/checkout', order('x2', { items: [{ variant_id: 'nope', quantity: 1 }] }))).body.error.code, 'VARIANT_NOT_FOUND');
  assert.equal((await call('POST', '/audit/v1/checkout', order('x3', { items: [{ variant_id: 'nope', quantity: 0 }] }))).status, 400);
  assert.equal((await call('POST', '/audit/v1/checkout', order('x4', { items: [] }))).status, 400);
  assert.equal((await call('POST', '/audit/v1/checkout', order('x5', { payment: {} }))).status, 400);
  assert.equal((await call('POST', '/audit/v1/checkout', order('x6', { discount_code: 5 }))).status, 400);
  assert.equal((await call('POST', '/audit/v1/checkout', [])).status, 400);
  const multi = await call('POST', '/audit/v1/checkout', order('x7', { items: [{ variant_id: 'var-jersey-001-L', quantity: 1 }, { variant_id: 'var-jersey-001-M', quantity: 2 }] }));
  assert.equal(multi.body.error.code, 'OUT_OF_STOCK');
  assert.equal(multi.body.error.details.variant_id, 'var-jersey-001-M');
  assert.equal((await call('GET', '/audit/v1/inventory/var-jersey-001-L')).body.stock, 3);
  assert.equal((await call('GET', '/audit/v1/inventory/nope')).status, 404);
});

test('customer ids with markup are stored as plain data; 413 on huge body', async () => {
  const r = await call('POST', '/audit/v1/checkout', order('xss', { customer_id: '<script>"q"</script>' }));
  assert.equal(r.status, 201);
  assert.equal(r.body.receipt.payload.customer_id, '<script>"q"</script>');
  const big = await call('POST', '/audit/v1/checkout', { pad: 'x'.repeat(1100000) });
  assert.equal(big.status, 413);
  assert.equal(big.body.error.code, 'PAYLOAD_TOO_LARGE');
});

test('order lifecycle transitions and catalogue', async () => {
  await call('POST', '/audit/v1/checkout', order('life'));
  assert.equal(store.transitionOrder('life', 'packed').status, 'packed');
  assert.throws(() => store.transitionOrder('life', 'paid'));
  assert.throws(() => store.transitionOrder('ghost', 'packed'));
  assert.ok(store.catalogue('tenant-alpha').some((p) => p.product_id === 'prod-jersey-001'));
  assert.ok(store.catalogue('tenant-beta').every((p) => p.tenant_id === 'tenant-beta'));
});
