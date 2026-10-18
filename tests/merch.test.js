'use strict';

process.env.API_RATE_LIMIT = '100000';
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { start, stop, call, login } = require('./helpers');
const { canonical } = require('../src/lib/crypto');

before(start);
after(stop);
beforeEach(() => call('POST', '/audit/v1/reset'));

// A real 1x1 PNG.
const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082', 'hex');
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);
const upload = (id, buf, type, h) => call('POST', `/api/v1/products/${id}/images`, buf, { ...h, 'content-type': type });
let n = 0;
const oid = () => `app-ord-${++n}-${Date.now()}`;

const NEW_SHIRT = {
  club_id: 'club-alpha-1', name: 'Falcons Third Kit', description: 'Limited edition', category: 'apparel', price_minor: 500000,
  variants: [{ size: 'S', color: 'Black', stock: 2 }, { size: 'M', color: 'Black', stock: 1 }, { size: 'L', color: 'Black', stock: 0 }],
};

test('catalogue filters, sorting, facets and tenant isolation', async () => {
  const viewer = await login('viewer@nascon.test');
  const all = (await call('GET', '/api/v1/products', undefined, viewer)).body;
  assert.ok(all.products.length >= 7);
  assert.ok(all.products.every((p) => p.tenant_id === 'tenant-alpha'));
  assert.ok(all.facets.sizes.includes('M') && all.facets.colors.includes('Navy'));
  const caps = (await call('GET', '/api/v1/products?category=caps', undefined, viewer)).body.products;
  assert.deepEqual(caps.map((p) => p.product_id), ['prod-demo-cap']);
  assert.equal(caps[0].variants[0].size, null, 'caps have colours but no sizes');
  const asc = (await call('GET', '/api/v1/products?sort=price_asc', undefined, viewer)).body.products.map((p) => p.from_price_minor);
  assert.deepEqual(asc, [...asc].sort((a, b) => a - b));
  const sale = (await call('GET', '/api/v1/products/prod-demo-away', undefined, viewer)).body;
  assert.equal(sale.on_sale, true);
  assert.equal(sale.from_price_minor, 357000);
  assert.equal(sale.variants.find((v) => v.size === 'XL').stock, 0);
  assert.equal((await call('GET', '/api/v1/products?q=bottle', undefined, viewer)).body.products.length, 1);
  assert.equal((await call('GET', '/api/v1/products?club_id=club-alpha-5&size=M', undefined, viewer)).body.products.length, 1);
  assert.equal((await call('GET', '/api/v1/products?sport_id=basketball', undefined, viewer)).body.products[0].product_id, 'prod-demo-shorts');
  assert.equal((await call('GET', '/api/v1/products?max_price=100000', undefined, viewer)).body.products.length, 2);
  assert.equal((await call('GET', '/api/v1/products?sort=random', undefined, viewer)).status, 400);
  assert.equal((await call('GET', '/api/v1/products/prod-demo-beta-shirt', undefined, viewer)).status, 404, 'other tenant hidden');
});

test('club manager creates and edits products, variants and stock; validation and RBAC', async () => {
  const manager = await login('manager@nascon.test');
  const r = await call('POST', '/api/v1/products', NEW_SHIRT, manager);
  assert.equal(r.status, 201);
  const p = r.body;
  assert.equal(p.variants.length, 3);
  assert.deepEqual(p.variants.map((v) => v.stock), [2, 1, 0]);
  assert.equal(p.club_name, 'Alpha Falcons FC');
  assert.equal(p.sport_id, 'football');
  assert.ok(p.created_at && p.updated_at);

  const bad = await call('POST', '/api/v1/products', { ...NEW_SHIRT, price_minor: 5, category: 'nope', variants: [{ size: 'M' }, { size: 'm' }] }, manager);
  assert.deepEqual(bad.body.error.details.fields.sort(), ['category', 'price_minor', 'variants']);
  assert.equal((await call('POST', '/api/v1/products', { ...NEW_SHIRT, sale_price_minor: 600000 }, manager)).status, 400, 'sale must be below price');
  assert.equal((await call('POST', '/api/v1/products', { ...NEW_SHIRT, club_id: 'club-alpha-2' }, manager)).status, 403);
  for (const email of ['viewer@nascon.test', 'player@nascon.test', 'organizer@nascon.test', 'lions.manager@nascon.test']) {
    assert.equal((await call('POST', '/api/v1/products', { ...NEW_SHIRT, club_id: 'club-alpha-2' }, await login(email))).status, 403, email);
  }

  // A product with no sizes gets a single standard variant.
  const bottle = (await call('POST', '/api/v1/products', { club_id: 'club-alpha-1', name: 'Pin badge', category: 'accessories', price_minor: 20000 }, manager)).body;
  assert.equal(bottle.variants.length, 1);
  assert.equal(bottle.variants[0].label, 'Standard');

  let u = await call('PATCH', `/api/v1/products/${p.product_id}`, { price_minor: 450000, sale_price_minor: 400000, description: 'Now on sale' }, manager);
  assert.equal(u.body.from_price_minor, 400000);
  assert.ok(u.body.variants.every((v) => v.price_minor === 450000));
  assert.equal((await call('PATCH', `/api/v1/products/${p.product_id}`, { sale_price_minor: 450000 }, manager)).status, 400);
  u = await call('POST', `/api/v1/products/${p.product_id}/variants`, { size: 'XL', color: 'Black', stock: 4 }, manager);
  assert.equal(u.status, 201);
  assert.equal(u.body.variants.length, 4);
  assert.equal((await call('POST', `/api/v1/products/${p.product_id}/variants`, { size: 'XL', color: 'black' }, manager)).body.error.code, 'VARIANT_EXISTS');
  const xl = u.body.variants.find((v) => v.size === 'XL');
  u = await call('PATCH', `/api/v1/variants/${xl.variant_id}`, { stock: 9, price_minor: 520000 }, manager);
  assert.equal(u.body.variants.find((v) => v.size === 'XL').stock, 9);
  assert.equal((await call('GET', `/audit/v1/inventory/${xl.variant_id}`)).body.stock, 9);
  assert.equal((await call('PATCH', `/api/v1/variants/${xl.variant_id}`, { stock: -1 }, manager)).status, 400);
  assert.equal((await call('PATCH', '/api/v1/variants/var-demo-shorts-s-orange', { stock: 50 }, manager)).status, 403, 'other club');

  const low = (await call('GET', '/api/v1/store/low-stock', undefined, manager)).body.items;
  assert.ok(low.some((x) => x.product_id === p.product_id && x.stock === 0));
  assert.ok(low.every((x) => x.club_id === 'club-alpha-1'));
  assert.equal((await call('GET', '/api/v1/store/low-stock', undefined, await login('viewer@nascon.test'))).status, 403);

  // Deactivated products disappear for fans but stay visible to the manager.
  await call('PATCH', `/api/v1/products/${p.product_id}`, { active: false }, manager);
  const viewer = await login('viewer@nascon.test');
  assert.equal((await call('GET', `/api/v1/products/${p.product_id}`, undefined, viewer)).status, 404);
  assert.ok((await call('GET', '/api/v1/products?include_inactive=1', undefined, manager)).body.products.some((x) => x.product_id === p.product_id));
  assert.ok(!(await call('GET', '/api/v1/products?include_inactive=1', undefined, viewer)).body.products.some((x) => x.product_id === p.product_id));
});

test('product images: type and size validation, storage, primary, removal, public media', async () => {
  const manager = await login('manager@nascon.test');
  let r = await upload('prod-jersey-001', PNG, 'image/png', manager);
  assert.equal(r.status, 201);
  assert.equal(r.body.images.length, 1);
  assert.equal(r.body.images[0].primary, true);
  assert.match(r.body.image_url, /^\/media\/products\/prod-jersey-001\/[0-9a-f-]{36}\.png$/);
  const img = await call('GET', r.body.image_url);
  assert.equal(img.status, 200);
  assert.equal(img.headers.get('content-type'), 'image/png');

  r = await upload('prod-jersey-001', JPEG, 'image/jpeg', manager);
  assert.equal(r.body.images.length, 2);
  const second = r.body.images[1];
  assert.equal(second.primary, false);
  r = await call('PATCH', `/api/v1/products/prod-jersey-001/images/${second.image_id}`, {}, manager);
  assert.equal(r.body.image_url, second.url);

  assert.equal((await upload('prod-jersey-001', Buffer.from('GIF89a......'), 'image/gif', manager)).body.error.code, 'UNSUPPORTED_IMAGE_TYPE');
  assert.equal((await upload('prod-jersey-001', PNG, 'image/jpeg', manager)).status, 415, 'declared type must match the bytes');
  assert.equal((await upload('prod-jersey-001', Buffer.concat([JPEG, Buffer.alloc(5 * 1024 * 1024)]), 'image/jpeg', manager)).status, 413);
  assert.equal((await upload('prod-jersey-001', Buffer.alloc(0), 'image/png', manager)).status, 400);
  assert.equal((await upload('prod-demo-lions-kit', PNG, 'image/png', manager)).status, 403);
  assert.equal((await upload('prod-jersey-001', PNG, 'image/png', await login('viewer@nascon.test'))).status, 403);

  r = await call('DELETE', `/api/v1/products/prod-jersey-001/images/${second.image_id}`, undefined, manager);
  assert.equal(r.body.images.length, 1);
  assert.equal(r.body.images[0].primary, true);
  assert.equal((await call('GET', second.url)).status, 404, 'deleted from storage');
  assert.equal((await call('DELETE', `/api/v1/products/prod-jersey-001/images/${second.image_id}`, undefined, manager)).status, 404);
  assert.equal((await call('GET', '/media/../../etc/passwd')).status, 404);

  // Club logos use the same pipeline.
  const logo = await call('POST', '/api/v1/clubs/club-alpha-1/logo', PNG, { ...manager, 'content-type': 'image/png' });
  assert.equal(logo.status, 201);
  assert.equal((await call('GET', '/api/v1/clubs/club-alpha-1', undefined, manager)).body.logo_url, logo.body.logo_url);
  const admin = await login('admin@nascon.test');
  assert.equal((await call('POST', '/api/v1/admin/tenants/tenant-alpha/logo', PNG, { ...admin, 'content-type': 'image/png' })).status, 201);
  assert.match((await call('GET', '/api/v1/tenants/me', undefined, manager)).body.logo_url, /^\/media\/tenants\/tenant-alpha\//);
});

test('cart quote re-prices from the server and flags stock, price and availability problems', async () => {
  const viewer = await login('viewer@nascon.test');
  const q = (await call('POST', '/api/v1/cart/quote', {
    items: [
      { variant_id: 'var-demo-away-m-white', quantity: 2, expected_unit_price_minor: 1 },
      { variant_id: 'var-demo-away-xl-white', quantity: 1 },
      { variant_id: 'var-demo-cap-white', quantity: 5 },
      { variant_id: 'var-demo-beta-shirt-m-teal', quantity: 1 },
    ],
    discount_code: 'welcome10',
  }, viewer)).body;
  assert.deepEqual(q.lines.map((l) => l.status), ['price_changed', 'out_of_stock', 'insufficient_stock', 'unavailable']);
  assert.equal(q.lines[0].unit_price_minor, 357000, 'sale price applied, client price ignored');
  assert.equal(q.subtotal_minor, 714000);
  assert.equal(q.discount_minor, 71400);
  assert.equal(q.total_minor, 642600);
  assert.equal(q.can_checkout, false);
  const ok = (await call('POST', '/api/v1/cart/quote', { items: [{ variant_id: 'var-demo-cap-navy', quantity: 2, expected_unit_price_minor: 180000 }], discount_code: 'NOPE' }, viewer)).body;
  assert.equal(ok.can_checkout, true);
  assert.equal(ok.discount_valid, false);
  assert.equal(ok.total_minor, 360000);
  assert.equal((await call('POST', '/api/v1/cart/quote', { items: [] }, viewer)).status, 400);
});

test('checkout: server totals, receipt signature, PDF, order history and replay', async () => {
  const viewer = await login('viewer@nascon.test');
  const id = oid();
  const body = { order_id: id, items: [{ variant_id: 'var-demo-away-s-white', quantity: 2 }, { variant_id: 'var-demo-cap-navy', quantity: 1 }], discount_code: 'WELCOME10', payment: { token: 'tok_success' } };
  const r = await call('POST', '/api/v1/checkout', body, viewer);
  assert.equal(r.status, 201);
  assert.equal(r.body.subtotal_minor, 357000 * 2 + 180000);
  assert.equal(r.body.discount_minor, Math.floor((357000 * 2 + 180000) / 10));
  assert.equal(r.body.receipt.payload.customer_id, 'user-viewer');
  const expected = crypto.createHmac('sha256', 'demo-salt').update(`${id}|${canonical(r.body.receipt.payload)}`).digest('hex');
  assert.equal(r.body.receipt.signature, expected);
  assert.ok(Buffer.from(r.body.receipt.pdf_base64, 'base64').subarray(0, 4).toString() === '%PDF');
  assert.equal(r.body.order.lines[0].product_name, 'Alpha Falcons Away Jersey');
  assert.equal(r.body.order.status, 'paid');
  assert.equal((await call('GET', '/audit/v1/inventory/var-demo-away-s-white')).body.stock, 2);

  const replay = await call('POST', '/api/v1/checkout', body, viewer);
  assert.equal(replay.status, 200);
  assert.equal(replay.body.order.order_id, id);
  assert.equal((await call('GET', '/audit/v1/inventory/var-demo-away-s-white')).body.stock, 2, 'replay reserves nothing');
  assert.equal((await call('POST', '/api/v1/checkout', { ...body, discount_code: null }, viewer)).body.error.code, 'DUPLICATE_ORDER_ID');
  assert.equal((await call('POST', '/api/v1/checkout', body, await login('player@nascon.test'))).body.error.code, 'DUPLICATE_ORDER_ID');

  const rc = (await call('GET', `/api/v1/orders/${id}/receipt`, undefined, viewer)).body;
  assert.equal(rc.signature_valid, true);
  assert.equal(rc.algorithm, 'HMAC-SHA256');
  const pdf = await call('GET', `/api/v1/orders/${id}/receipt.pdf`, undefined, viewer);
  assert.equal(pdf.status, 200);
  assert.equal(pdf.headers.get('content-type'), 'application/pdf');
  const mine = (await call('GET', '/api/v1/orders', undefined, viewer)).body.orders;
  assert.deepEqual(mine.map((o) => o.order_id), [id]);
  assert.equal((await call('GET', '/api/v1/orders', undefined, await login('player@nascon.test'))).body.orders.length, 0);
  assert.equal((await call('GET', `/api/v1/orders/${id}`, undefined, await login('player@nascon.test'))).status, 404);
  const managed = (await call('GET', '/api/v1/orders?scope=managed', undefined, await login('manager@nascon.test'))).body.orders;
  assert.deepEqual(managed.map((o) => o.order_id), [id]);
  assert.equal((await call('GET', '/api/v1/orders?scope=everything', undefined, viewer)).status, 400);
});

test('checkout failures: declined and capture failure release stock; invalid input; inactive', async () => {
  const viewer = await login('viewer@nascon.test');
  const item = [{ variant_id: 'var-demo-bag-blue', quantity: 2 }];
  let r = await call('POST', '/api/v1/checkout', { order_id: oid(), items: item, payment: { token: 'tok_declined' } }, viewer);
  assert.equal(r.status, 402);
  assert.equal(r.body.error.code, 'PAYMENT_DECLINED');
  r = await call('POST', '/api/v1/checkout', { order_id: oid(), items: item, payment: { token: 'tok_capture_fail' } }, viewer);
  assert.equal(r.body.error.code, 'PAYMENT_CAPTURE_FAILED');
  assert.deepEqual((await call('GET', '/audit/v1/inventory/var-demo-bag-blue')).body, { variant_id: 'var-demo-bag-blue', stock: 2, reserved: 0 });
  assert.equal((await call('POST', '/api/v1/checkout', { order_id: oid(), items: [{ variant_id: 'var-demo-bag-blue', quantity: 3 }], payment: { token: 'tok_success' } }, viewer)).body.error.code, 'OUT_OF_STOCK');
  assert.equal((await call('POST', '/api/v1/checkout', { order_id: oid(), items: item, payment: { token: 'tok_real_card_4242' } }, viewer)).status, 400, 'only mock tokens');
  assert.equal((await call('POST', '/api/v1/checkout', { order_id: oid(), items: item, payment: { token: 'tok_success' }, total_minor: 1 }, viewer)).body.total_minor, 700000, 'client totals are ignored');
  assert.equal((await call('POST', '/api/v1/checkout', { order_id: oid(), items: [{ variant_id: 'var-demo-beta-shirt-m-teal', quantity: 1 }], payment: { token: 'tok_success' } }, viewer)).status, 404);
  const manager = await login('manager@nascon.test');
  await call('PATCH', '/api/v1/products/prod-demo-cap', { active: false }, manager);
  assert.equal((await call('POST', '/api/v1/checkout', { order_id: oid(), items: [{ variant_id: 'var-demo-cap-navy', quantity: 1 }], payment: { token: 'tok_success' } }, viewer)).body.error.code, 'PRODUCT_UNAVAILABLE');
  assert.equal((await call('POST', '/api/v1/checkout', { order_id: oid(), items: item, payment: { token: 'tok_success' } })).status, 401);
});

test('20 simultaneous app buyers of the last unit: exactly one order', async () => {
  const tokens = await Promise.all(['viewer@nascon.test', 'player@nascon.test', 'manager@nascon.test', 'organizer@nascon.test'].map(login));
  const results = await Promise.all(Array.from({ length: 20 }, (_, i) => call('POST', '/api/v1/checkout', {
    order_id: `burst-${i}`, items: [{ variant_id: 'var-jersey-001-M', quantity: 1 }], payment: { token: 'tok_success' },
  }, tokens[i % 4])));
  assert.equal(results.filter((r) => r.status === 201).length, 1);
  assert.equal(results.filter((r) => r.status === 409 && r.body.error.code === 'OUT_OF_STOCK').length, 19);
  assert.deepEqual((await call('GET', '/audit/v1/inventory/var-jersey-001-M')).body, { variant_id: 'var-jersey-001-M', stock: 0, reserved: 0 });
});

test('order lifecycle: customer cancel refunds and restocks; staff move and refund; bad moves rejected', async () => {
  const viewer = await login('viewer@nascon.test');
  const manager = await login('manager@nascon.test');
  const a = oid();
  await call('POST', '/api/v1/checkout', { order_id: a, items: [{ variant_id: 'var-demo-cap-white', quantity: 2 }], payment: { token: 'tok_success' } }, viewer);
  assert.equal((await call('GET', '/audit/v1/inventory/var-demo-cap-white')).body.stock, 1);
  let r = await call('POST', `/api/v1/orders/${a}/status`, { status: 'cancelled', reason: 'Changed my mind' }, viewer);
  assert.equal(r.status, 200);
  assert.equal(r.body.status, 'cancelled');
  assert.equal(r.body.payment.state, 'refunded');
  assert.match(r.body.payment.refund_id, /^ref_/);
  assert.equal((await call('GET', '/audit/v1/inventory/var-demo-cap-white')).body.stock, 3, 'restocked');
  assert.equal((await call('POST', `/api/v1/orders/${a}/status`, { status: 'packed' }, manager)).body.error.code, 'ILLEGAL_TRANSITION');

  const b = oid();
  await call('POST', '/api/v1/checkout', { order_id: b, items: [{ variant_id: 'var-demo-cap-navy', quantity: 1 }], payment: { token: 'tok_success' } }, viewer);
  assert.equal((await call('POST', `/api/v1/orders/${b}/status`, { status: 'shipped' }, viewer)).status, 403, 'customers only cancel');
  for (const s of ['packed', 'shipped', 'delivered']) assert.equal((await call('POST', `/api/v1/orders/${b}/status`, { status: s }, manager)).body.status, s);
  assert.equal((await call('POST', `/api/v1/orders/${b}/status`, { status: 'cancelled' }, viewer)).status, 403);
  r = await call('POST', `/api/v1/orders/${b}/status`, { status: 'refunded', reason: 'Damaged' }, manager);
  assert.equal(r.body.status, 'refunded');
  assert.deepEqual(r.body.history.map((h) => h.to), ['pending', 'paid', 'packed', 'shipped', 'delivered', 'refunded']);
  assert.equal((await call('POST', `/api/v1/orders/${b}/status`, { status: 'teleported' }, manager)).status, 400);
  assert.equal((await call('POST', `/api/v1/orders/${b}/status`, { status: 'packed' }, await login('lions.manager@nascon.test'))).status, 404, 'not their order');
  const dash = (await call('GET', '/api/v1/admin/dashboard', undefined, await login('admin@nascon.test'))).body;
  assert.equal(dash.orders.count, 2);
  assert.equal(dash.orders.refunded, 2);
});
