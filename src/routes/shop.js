'use strict';

const express = require('express');
const { state, clone } = require('../state');
const { authenticate } = require('../services/auth');
const { can, forbid } = require('../services/rbac');
const merch = require('../services/merch');
const activity = require('../lib/activity');
const { raw } = require('./ops');

// Production store: catalogue, product management (Club Managers with store access, Super-Admin),
// image uploads, cart quotes, checkout with the mock gateway, orders and signed receipts.

function shopRouter() {
  const r = express.Router();
  const auth = (req, res, next) => {
    req.user = authenticate(req);
    next();
  };
  const log = (req, action, target, details = {}) => activity.record(req.user, action, target, details);

  // ---- Catalogue ----
  r.get('/products', auth, async (req, res) => res.status(200).json(await merch.listProducts(req.user, req.query)));
  r.get('/products/:productId', auth, async (req, res) => {
    const p = merch.visibleProduct(req.user, req.params.productId);
    res.status(200).json({ ...(await merch.productView(p)), can_manage: can(req.user, 'club.products.write', state.clubs.get(p.club_id) || p) });
  });
  r.get('/store/categories', auth, (req, res) => res.status(200).json({ categories: [...state.categories.values()].map(clone) }));
  r.get('/store/low-stock', auth, async (req, res) => {
    if (!(req.user.role === 'super_admin' || (req.user.role === 'club_manager' && req.user.store_access !== false))) throw forbid('club.products.write');
    res.status(200).json({ threshold: state.settings.low_stock_threshold, items: await merch.lowStock(req.user, req.query.club_id) });
  });

  // ---- Product management ----
  r.post('/products', auth, async (req, res) => {
    const out = await merch.createProduct(req.user, req.body);
    log(req, 'product.create', out.product_id, { club_id: out.club_id, tenant_id: out.tenant_id, name: out.name });
    res.status(201).json(out);
  });
  r.patch('/products/:productId', auth, async (req, res) => {
    const out = await merch.updateProduct(req.user, req.params.productId, req.body);
    log(req, 'product.update', out.product_id, { club_id: out.club_id, tenant_id: out.tenant_id, fields: Object.keys(req.body || {}) });
    res.status(200).json(out);
  });
  r.post('/products/:productId/variants', auth, async (req, res) => {
    const out = await merch.addVariant(req.user, req.params.productId, req.body);
    log(req, 'product.variant.create', out.product_id, { club_id: out.club_id, tenant_id: out.tenant_id });
    res.status(201).json(out);
  });
  r.patch('/variants/:variantId', auth, async (req, res) => {
    const out = await merch.updateVariant(req.user, req.params.variantId, req.body);
    log(req, 'product.variant.update', req.params.variantId, { product_id: out.product_id, tenant_id: out.tenant_id, fields: Object.keys(req.body || {}) });
    res.status(200).json(out);
  });

  // Raw image bytes (Content-Type image/jpeg | image/png | image/webp), max 5 MB.
  r.post('/products/:productId/images', auth, raw, async (req, res) => {
    const out = await merch.addImage(req.user, req.params.productId, req.body, req.headers['content-type']);
    log(req, 'product.image.upload', out.product_id, { tenant_id: out.tenant_id, images: out.images.length });
    res.status(201).json(out);
  });
  r.patch('/products/:productId/images/:imageId', auth, async (req, res) => {
    const out = await merch.setPrimaryImage(req.user, req.params.productId, req.params.imageId);
    log(req, 'product.image.primary', out.product_id, { tenant_id: out.tenant_id, image_id: req.params.imageId });
    res.status(200).json(out);
  });
  r.delete('/products/:productId/images/:imageId', auth, async (req, res) => {
    const out = await merch.removeImage(req.user, req.params.productId, req.params.imageId);
    log(req, 'product.image.remove', out.product_id, { tenant_id: out.tenant_id, image_id: req.params.imageId });
    res.status(200).json(out);
  });

  // ---- Cart and checkout ----
  r.post('/cart/quote', auth, async (req, res) => res.status(200).json(await merch.quote(req.user, req.body)));
  r.post('/checkout', auth, async (req, res) => {
    const out = await merch.checkout(req.user, req.body);
    if (out.status === 201) log(req, 'order.create', out.body.order_id, { tenant_id: req.user.tenant_id, total_minor: out.body.total_minor });
    res.status(out.status).json(out.body);
  });

  // ---- Orders ----
  r.get('/orders', auth, (req, res) => res.status(200).json({ orders: merch.listOrders(req.user, req.query) }));
  r.get('/orders/:orderId', auth, (req, res) => res.status(200).json(merch.orderView(merch.orderOr404(req.user, req.params.orderId))));
  r.post('/orders/:orderId/status', auth, async (req, res) => {
    const out = await merch.changeStatus(req.user, req.params.orderId, req.body);
    log(req, 'order.status', out.order_id, { tenant_id: out.tenant_id, to: out.status });
    res.status(200).json(out);
  });
  r.get('/orders/:orderId/receipt', auth, (req, res) => res.status(200).json(merch.receipt(req.user, req.params.orderId)));
  r.get('/orders/:orderId/receipt.pdf', auth, async (req, res) => {
    const pdf = await merch.receiptPdfFor(req.user, req.params.orderId);
    res.status(200).set({ 'Content-Type': 'application/pdf', 'Content-Disposition': `inline; filename="receipt-${req.params.orderId}.pdf"` }).send(pdf);
  });

  return r;
}

module.exports = { shopRouter };
