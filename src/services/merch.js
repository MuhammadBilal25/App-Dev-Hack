'use strict';

// Production merchandise store (FR-2.3): catalogue with filters, product / variant / inventory
// management, product images in object storage, server-side cart quotes, checkout on top of the
// concurrency-safe engine in store.js, orders with status changes, refunds and signed receipts.
// Prices always come from the server; the app's numbers are only compared, never trusted.
const crypto = require('crypto');
const { state, clone } = require('../state');
const { err, validation } = require('../lib/errors');
const { isObj, isInt, isStr, isBool, isId, nowIso } = require('../lib/validate');
const { sign } = require('../lib/crypto');
const { receiptPdf } = require('../lib/pdf');
const storage = require('../lib/storage');
const { nextId } = require('../lib/activity');
const store = require('./store');
const { can } = require('./rbac');
const views = require('./views');
const realtime = require('../realtime');

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const MAX_IMAGES = 8;
const MOCK_TOKENS = ['tok_success', 'tok_declined', 'tok_capture_fail'];
const SIZE_RE = /^[A-Za-z0-9 ./-]{1,12}$/;
const SKU_RE = /^[A-Za-z0-9_.:-]{1,40}$/;
const TS_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const SOLD = ['paid', 'packed', 'shipped', 'delivered'];

const str = (v, max) => isStr(v) && v.trim().length >= 1 && v.length <= max;
const price = (v) => isInt(v) && v >= 100 && v <= 100000000;

// ---------------------------------------------------------------------------------------------
// Lookups and permissions
// ---------------------------------------------------------------------------------------------
function productOr404(id) {
  const p = state.products.get(id);
  if (!p) throw err(404, 'PRODUCT_NOT_FOUND', `Product ${id} does not exist.`, { product_id: id });
  return p;
}

function variantOr404(id) {
  const v = state.variants.get(id);
  if (!v) throw err(404, 'VARIANT_NOT_FOUND', `Variant ${id} does not exist.`, { variant_id: id });
  return v;
}

const clubOf = (p) => state.clubs.get(p.club_id) || { club_id: p.club_id, tenant_id: p.tenant_id };
const canManage = (user, p) => can(user, 'club.products.write', clubOf(p));

// Other tenants' products answer 404 so their existence is not disclosed; inactive products are
// visible only to the people who manage them.
function visibleProduct(user, id) {
  const p = productOr404(id);
  if (!views.inTenant(user, p) || (p.active === false && !canManage(user, p))) {
    throw err(404, 'PRODUCT_NOT_FOUND', `Product ${id} does not exist.`, { product_id: id });
  }
  return p;
}

function writableProduct(user, id) {
  const p = visibleProduct(user, id);
  if (!canManage(user, p)) throw err(403, 'FORBIDDEN', 'You are not allowed to perform this action.', { action: 'club.products.write' });
  return p;
}

// ---------------------------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------------------------
const variantLabel = (v) => [v.size, v.color].filter(Boolean).join(' · ') || 'Standard';

function soldUnits(productId) {
  let n = 0;
  for (const o of state.prodOrders.values()) {
    if (!SOLD.includes(statusOf(o))) continue;
    for (const l of o.lines) if (l.product_id === productId) n += l.quantity;
  }
  return n;
}

const primaryImage = (p) => (p.images || []).find((i) => i.primary) || (p.images || [])[0] || null;

async function productView(p) {
  const club = state.clubs.get(p.club_id);
  const league = club && state.leagues.get(club.league_id);
  const sportId = p.sport_id || (league ? league.sport_id : null);
  const category = state.categories.get(p.category);
  const threshold = state.settings.low_stock_threshold;
  const variants = [];
  for (const v of p.variants) {
    const inv = await store.inventory(v.variant_id);
    variants.push({
      variant_id: v.variant_id,
      sku: v.sku || v.variant_id,
      size: v.size || null,
      color: v.color || null,
      label: variantLabel(v),
      price_minor: v.price_minor,
      sale_price_minor: Number.isInteger(v.sale_price_minor) ? v.sale_price_minor : null,
      unit_price_minor: store.unitPrice(v),
      currency: 'PKR',
      active: v.active !== false,
      stock: inv.stock,
      reserved: inv.reserved,
    });
  }
  const sellable = variants.filter((v) => v.active);
  const prices = sellable.map((v) => v.unit_price_minor);
  const img = primaryImage(p);
  return {
    product_id: p.product_id,
    tenant_id: p.tenant_id,
    club_id: p.club_id,
    club_name: views.clubName(p.club_id),
    sport_id: sportId,
    sport_name: sportId && state.sports.get(sportId) ? state.sports.get(sportId).name : null,
    name: p.name,
    description: p.description || '',
    category: p.category,
    category_name: category ? category.name : p.category,
    currency: 'PKR',
    active: p.active !== false,
    images: (p.images || []).map((i) => ({ image_id: i.image_id, url: i.url, primary: !!i.primary, content_type: i.content_type, bytes: i.bytes })),
    image_url: img ? img.url : null,
    variants,
    from_price_minor: prices.length ? Math.min(...prices) : null,
    list_price_minor: sellable.length ? Math.min(...sellable.map((v) => v.price_minor)) : null,
    on_sale: sellable.some((v) => v.unit_price_minor < v.price_minor),
    in_stock: sellable.some((v) => v.stock > 0),
    low_stock: sellable.some((v) => v.stock > 0 && v.stock <= threshold),
    sold_units: soldUnits(p.product_id),
    price_schedule: clone(p.price_schedule || []),
    created_at: p.created_at || null,
    updated_at: p.updated_at || null,
  };
}

// ---------------------------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------------------------
const SORTS = ['newest', 'price_asc', 'price_desc', 'popular', 'name'];

async function listProducts(user, q = {}) {
  const bad = [];
  if (q.sort !== undefined && !SORTS.includes(q.sort)) bad.push('sort');
  for (const k of ['min_price', 'max_price']) if (q[k] !== undefined && !/^\d{1,10}$/.test(String(q[k]))) bad.push(k);
  if (bad.length) throw validation(bad);
  const needle = isStr(q.q) ? q.q.trim().toLowerCase() : '';
  const includeInactive = q.include_inactive === '1' || q.include_inactive === 'true';
  const out = [];
  for (const p of state.products.values()) {
    if (!views.inTenant(user, p)) continue;
    if (p.active === false && !(includeInactive && canManage(user, p))) continue;
    if (q.club_id && p.club_id !== q.club_id) continue;
    if (q.category && p.category !== q.category) continue;
    const v = await productView(p);
    if (q.sport_id && v.sport_id !== q.sport_id) continue;
    if (needle && ![v.name, v.description, v.club_name, v.category_name].some((s) => (s || '').toLowerCase().includes(needle))) continue;
    if (q.size && !v.variants.some((x) => x.active && (x.size || '').toLowerCase() === String(q.size).toLowerCase())) continue;
    if (q.color && !v.variants.some((x) => x.active && (x.color || '').toLowerCase() === String(q.color).toLowerCase())) continue;
    if (q.in_stock === '1' && !v.in_stock) continue;
    if (q.min_price !== undefined && (v.from_price_minor ?? 0) < Number(q.min_price)) continue;
    if (q.max_price !== undefined && (v.from_price_minor ?? 0) > Number(q.max_price)) continue;
    out.push(v);
  }
  const sort = q.sort || 'newest';
  const cmp = {
    newest: (a, b) => (b.created_at || '').localeCompare(a.created_at || '') || a.name.localeCompare(b.name),
    price_asc: (a, b) => (a.from_price_minor ?? 0) - (b.from_price_minor ?? 0),
    price_desc: (a, b) => (b.from_price_minor ?? 0) - (a.from_price_minor ?? 0),
    popular: (a, b) => b.sold_units - a.sold_units || a.name.localeCompare(b.name),
    name: (a, b) => a.name.localeCompare(b.name),
  }[sort];
  out.sort(cmp);
  // Facets for the filter sheet, from what this user can see.
  const facets = { sizes: new Set(), colors: new Set(), categories: new Set(), clubs: new Map(), sports: new Map() };
  for (const p of out) {
    facets.categories.add(p.category);
    facets.clubs.set(p.club_id, p.club_name);
    if (p.sport_id) facets.sports.set(p.sport_id, p.sport_name);
    for (const v of p.variants) {
      if (v.size) facets.sizes.add(v.size);
      if (v.color) facets.colors.add(v.color);
    }
  }
  return {
    products: out,
    facets: {
      sizes: [...facets.sizes],
      colors: [...facets.colors],
      categories: [...facets.categories].map((id) => ({ category_id: id, name: (state.categories.get(id) || { name: id }).name })),
      clubs: [...facets.clubs].map(([club_id, name]) => ({ club_id, name })),
      sports: [...facets.sports].map(([sport_id, name]) => ({ sport_id, name })),
    },
  };
}

// ---------------------------------------------------------------------------------------------
// Product, variant and inventory management
// ---------------------------------------------------------------------------------------------
function validateVariantInput(v, bad, key) {
  if (!isObj(v)) return bad.push(key);
  if (v.size !== undefined && v.size !== null && !(isStr(v.size) && SIZE_RE.test(v.size))) bad.push(`${key}.size`);
  if (v.color !== undefined && v.color !== null && !str(v.color, 24)) bad.push(`${key}.color`);
  if (v.sku !== undefined && v.sku !== null && !(isStr(v.sku) && SKU_RE.test(v.sku))) bad.push(`${key}.sku`);
  if (v.stock !== undefined && !(isInt(v.stock) && v.stock >= 0 && v.stock <= 100000)) bad.push(`${key}.stock`);
  if (v.price_minor !== undefined && !price(v.price_minor)) bad.push(`${key}.price_minor`);
  if (v.sale_price_minor !== undefined && v.sale_price_minor !== null && !price(v.sale_price_minor)) bad.push(`${key}.sale_price_minor`);
  return null;
}

function validatePriceSchedule(s, bad) {
  if (s === undefined) return;
  if (!(Array.isArray(s) && s.length <= 10 && s.every((x) => isObj(x) && isStr(x.effective_at) && TS_RE.test(x.effective_at) && price(x.price_minor)))) {
    bad.push('price_schedule');
  }
}

const comboKey = (v) => `${(v.size || '').toLowerCase()}|${(v.color || '').toLowerCase()}`;

function validateProductFields(b, bad, creating) {
  if ((creating || b.name !== undefined) && !str(b.name, 80)) bad.push('name');
  if (b.description !== undefined && !(isStr(b.description) && b.description.length <= 2000)) bad.push('description');
  if ((creating || b.category !== undefined) && !(isStr(b.category) && state.categories.has(b.category))) bad.push('category');
  if ((creating || b.price_minor !== undefined) && !price(b.price_minor)) bad.push('price_minor');
  if (b.sale_price_minor !== undefined && b.sale_price_minor !== null && !price(b.sale_price_minor)) bad.push('sale_price_minor');
  if (isInt(b.price_minor) && isInt(b.sale_price_minor) && b.sale_price_minor >= b.price_minor) bad.push('sale_price_minor');
  if (b.active !== undefined && !isBool(b.active)) bad.push('active');
  if (b.sport_id !== undefined && b.sport_id !== null && !(isStr(b.sport_id) && state.sports.has(b.sport_id))) bad.push('sport_id');
  validatePriceSchedule(b.price_schedule, bad);
}

async function newVariant(p, v, defaults) {
  const variant = {
    variant_id: nextId('var'),
    product_id: p.product_id,
    tenant_id: p.tenant_id,
    sku: v.sku || null,
    size: v.size ? v.size.trim().toUpperCase() : null,
    color: v.color ? v.color.trim() : null,
    price_minor: v.price_minor || defaults.price_minor,
    sale_price_minor: v.sale_price_minor !== undefined ? v.sale_price_minor : defaults.sale_price_minor ?? null,
    price_schedule: clone(defaults.price_schedule || []),
    currency: 'PKR',
    active: true,
  };
  if (!variant.sku) variant.sku = variant.variant_id;
  state.variants.set(variant.variant_id, variant);
  p.variants.push(variant);
  await store.addInventory(variant.variant_id, v.stock || 0);
  return variant;
}

async function createProduct(user, b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateProductFields(b, bad, true);
  if (!isStr(b.club_id)) bad.push('club_id');
  const variants = b.variants === undefined ? [{}] : b.variants;
  if (!(Array.isArray(variants) && variants.length >= 1 && variants.length <= 30)) bad.push('variants');
  else {
    variants.forEach((v, i) => validateVariantInput(v, bad, `variants[${i}]`));
    if (new Set(variants.map(comboKey)).size !== variants.length) bad.push('variants');
  }
  if (bad.length) throw validation(bad);
  const club = state.clubs.get(b.club_id);
  if (!club) throw err(404, 'CLUB_NOT_FOUND', `Club ${b.club_id} does not exist.`, { club_id: b.club_id });
  if (!can(user, 'club.products.write', club)) throw err(403, 'FORBIDDEN', 'You are not allowed to perform this action.', { action: 'club.products.write' });

  const now = nowIso();
  const p = {
    product_id: nextId('prod'),
    tenant_id: club.tenant_id,
    club_id: club.club_id,
    sport_id: b.sport_id || null,
    name: b.name.trim(),
    description: b.description || '',
    category: b.category,
    images: [],
    variants: [],
    price_schedule: clone(b.price_schedule || []),
    active: b.active !== false,
    created_at: now,
    updated_at: now,
  };
  state.products.set(p.product_id, p);
  for (const v of variants) await newVariant(p, v, { price_minor: b.price_minor, sale_price_minor: b.sale_price_minor ?? null, price_schedule: b.price_schedule });
  publishProduct(p);
  return productView(p);
}

async function updateProduct(user, id, b) {
  const p = writableProduct(user, id);
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateProductFields(b, bad, false);
  const base = isInt(b.price_minor) ? b.price_minor : Math.min(...p.variants.map((v) => v.price_minor));
  if (isInt(b.sale_price_minor) && b.sale_price_minor >= base) bad.push('sale_price_minor');
  if (bad.length) throw validation(bad);
  for (const k of ['description', 'category', 'active', 'sport_id']) if (b[k] !== undefined) p[k] = b[k];
  if (b.name !== undefined) p.name = b.name.trim();
  // Product-level prices apply to every variant.
  for (const v of p.variants) {
    if (b.price_minor !== undefined) v.price_minor = b.price_minor;
    if (b.sale_price_minor !== undefined) v.sale_price_minor = b.sale_price_minor;
    if (b.price_schedule !== undefined) v.price_schedule = clone(b.price_schedule);
  }
  if (b.price_schedule !== undefined) p.price_schedule = clone(b.price_schedule);
  p.updated_at = nowIso();
  publishProduct(p);
  return productView(p);
}

async function addVariant(user, id, b) {
  const p = writableProduct(user, id);
  const bad = [];
  validateVariantInput(b, bad, 'body');
  if (bad.length) throw validation(bad.map((f) => f.replace(/^body\./, '')));
  if (p.variants.some((v) => comboKey(v) === comboKey(b))) throw err(409, 'VARIANT_EXISTS', 'A variant with this size and colour already exists.', { product_id: p.product_id });
  if (p.variants.length >= 30) throw err(409, 'TOO_MANY_VARIANTS', 'A product can have at most 30 variants.', { product_id: p.product_id });
  const first = p.variants[0] || {};
  await newVariant(p, b, { price_minor: first.price_minor || 100, sale_price_minor: first.sale_price_minor ?? null, price_schedule: p.price_schedule });
  p.updated_at = nowIso();
  publishProduct(p);
  return productView(p);
}

async function updateVariant(user, variantId, b) {
  const v = variantOr404(variantId);
  const p = writableProduct(user, v.product_id);
  const bad = [];
  validateVariantInput(b, bad, 'body');
  if (b.active !== undefined && !isBool(b.active)) bad.push('body.active');
  const base = isInt(b.price_minor) ? b.price_minor : v.price_minor;
  if (isInt(b.sale_price_minor) && b.sale_price_minor >= base) bad.push('body.sale_price_minor');
  if (bad.length) throw validation(bad.map((f) => f.replace(/^body\./, '')));
  const next = { size: b.size !== undefined ? b.size : v.size, color: b.color !== undefined ? b.color : v.color };
  if (p.variants.some((x) => x !== v && comboKey(x) === comboKey(next))) throw err(409, 'VARIANT_EXISTS', 'A variant with this size and colour already exists.', { variant_id: v.variant_id });
  if (b.size !== undefined) v.size = b.size ? b.size.trim().toUpperCase() : null;
  if (b.color !== undefined) v.color = b.color ? b.color.trim() : null;
  for (const k of ['sku', 'price_minor', 'sale_price_minor', 'active']) if (b[k] !== undefined) v[k] = b[k];
  if (b.stock !== undefined) await store.setStock(v.variant_id, b.stock);
  p.updated_at = nowIso();
  realtime.publish('store', 'inventory_changed', { variant_id: v.variant_id });
  publishProduct(p);
  return productView(p);
}

async function lowStock(user, clubId) {
  const threshold = state.settings.low_stock_threshold;
  const out = [];
  for (const p of state.products.values()) {
    if (!views.inTenant(user, p) || !canManage(user, p) || (clubId && p.club_id !== clubId) || p.active === false) continue;
    for (const v of p.variants) {
      if (v.active === false) continue;
      const inv = await store.inventory(v.variant_id);
      if (inv.stock <= threshold) {
        out.push({ product_id: p.product_id, product_name: p.name, club_id: p.club_id, variant_id: v.variant_id, label: variantLabel(v), stock: inv.stock, threshold });
      }
    }
  }
  return out.sort((a, b) => a.stock - b.stock);
}

const publishProduct = (p) => realtime.publish('store', 'product_changed', { product_id: p.product_id });

// ---------------------------------------------------------------------------------------------
// Images (object storage)
// ---------------------------------------------------------------------------------------------
function sniffImage(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length >= 12 && buf.subarray(0, 4).toString('ascii') === 'RIFF' && buf.subarray(8, 12).toString('ascii') === 'WEBP') return 'image/webp';
  return null;
}
const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

// Validates an uploaded image (size, then real type from its bytes) and stores it.
async function storeImage(prefix, buf, declaredType) {
  if (!storage.ready()) throw err(503, 'STORAGE_UNAVAILABLE', 'Image storage is starting up. Try again in a moment.');
  if (!Buffer.isBuffer(buf) || buf.length === 0) throw validation(['body'], 'Send the image bytes as the request body.');
  if (buf.length > MAX_IMAGE_BYTES) throw err(413, 'PAYLOAD_TOO_LARGE', 'Images must be 5 MB or smaller.', { max_bytes: MAX_IMAGE_BYTES });
  const type = sniffImage(buf);
  const declared = (declaredType || '').split(';')[0].trim().toLowerCase();
  if (!type || (declared && declared !== 'application/octet-stream' && declared !== type && !(declared === 'image/jpg' && type === 'image/jpeg'))) {
    throw err(415, 'UNSUPPORTED_IMAGE_TYPE', 'Only JPEG, PNG and WebP images are accepted.', { content_type: declared || null });
  }
  const key = `${prefix}/${crypto.randomUUID()}.${EXT[type]}`;
  await storage.put(key, buf, type);
  return { key, url: `/media/${key}`, content_type: type, bytes: buf.length };
}

async function addImage(user, id, buf, contentType) {
  const p = writableProduct(user, id);
  if ((p.images || []).length >= MAX_IMAGES) throw err(409, 'TOO_MANY_IMAGES', `A product can have at most ${MAX_IMAGES} images.`, { product_id: p.product_id });
  const stored = await storeImage(`products/${p.product_id}`, buf, contentType);
  p.images = p.images || [];
  const image = { image_id: nextId('img'), ...stored, primary: p.images.length === 0, uploaded_at: nowIso() };
  p.images.push(image);
  p.updated_at = nowIso();
  publishProduct(p);
  return productView(p);
}

function imageOr404(p, imageId) {
  const img = (p.images || []).find((i) => i.image_id === imageId);
  if (!img) throw err(404, 'IMAGE_NOT_FOUND', `Image ${imageId} does not exist.`, { image_id: imageId });
  return img;
}

async function setPrimaryImage(user, id, imageId) {
  const p = writableProduct(user, id);
  const img = imageOr404(p, imageId);
  for (const i of p.images) i.primary = i === img;
  p.updated_at = nowIso();
  publishProduct(p);
  return productView(p);
}

async function removeImage(user, id, imageId) {
  const p = writableProduct(user, id);
  const img = imageOr404(p, imageId);
  p.images = p.images.filter((i) => i !== img);
  if (img.primary && p.images.length) p.images[0].primary = true;
  await storage.remove(img.key);
  p.updated_at = nowIso();
  publishProduct(p);
  return productView(p);
}

// Club and tenant logos use the same validation and storage.
async function setLogo(entity, prefix, buf, contentType) {
  const stored = await storeImage(prefix, buf, contentType);
  const old = entity.logo_key;
  entity.logo_key = stored.key;
  entity.logo_url = stored.url;
  if (old) await storage.remove(old);
  return { logo_url: stored.url };
}

const MEDIA_RE = /^(products|clubs|tenants)\/[A-Za-z0-9_.:-]{1,64}\/[0-9a-f-]{36}\.(jpg|png|webp)$/;

async function media(key) {
  if (!MEDIA_RE.test(key)) return null;
  return storage.get(key);
}

// ---------------------------------------------------------------------------------------------
// Cart quote and checkout
// ---------------------------------------------------------------------------------------------
function validateItems(items, bad, max) {
  if (!(Array.isArray(items) && items.length >= 1 && items.length <= max)) return bad.push('items');
  const ok = items.every((it) => isObj(it) && isStr(it.variant_id) && it.variant_id && isInt(it.quantity) && it.quantity >= 1 && it.quantity <= 10 &&
    (it.expected_unit_price_minor === undefined || isInt(it.expected_unit_price_minor)));
  if (!ok || new Set(items.map((it) => it && it.variant_id)).size !== items.length) bad.push('items');
  return null;
}

// Re-prices a cart from server data: current price, stock and availability per line, discount and
// totals. The app shows these numbers; it never computes a total itself.
async function quote(user, b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  validateItems(b.items, bad, 20);
  if (b.discount_code !== undefined && b.discount_code !== null && !isStr(b.discount_code)) bad.push('discount_code');
  if (bad.length) throw validation(bad);
  const lines = [];
  for (const it of b.items) {
    const v = state.variants.get(it.variant_id);
    const p = v && state.products.get(v.product_id);
    if (!v || !p || !views.inTenant(user, p)) {
      lines.push({ variant_id: it.variant_id, quantity: it.quantity, status: 'unavailable', message: 'This item is no longer sold.' });
      continue;
    }
    const inv = await store.inventory(v.variant_id);
    const unit = store.unitPrice(v);
    let status = 'ok';
    let message = null;
    if (p.active === false || v.active === false) {
      status = 'unavailable';
      message = 'This item is no longer sold.';
    } else if (inv.stock < it.quantity) {
      status = inv.stock === 0 ? 'out_of_stock' : 'insufficient_stock';
      message = inv.stock === 0 ? 'Sold out.' : `Only ${inv.stock} left.`;
    } else if (isInt(it.expected_unit_price_minor) && it.expected_unit_price_minor !== unit) {
      status = 'price_changed';
      message = 'The price has changed since you added this.';
    }
    const img = primaryImage(p);
    lines.push({
      variant_id: v.variant_id,
      product_id: p.product_id,
      product_name: p.name,
      club_id: p.club_id,
      club_name: views.clubName(p.club_id),
      size: v.size || null,
      color: v.color || null,
      label: variantLabel(v),
      image_url: img ? img.url : null,
      quantity: it.quantity,
      unit_price_minor: unit,
      list_price_minor: v.price_minor,
      line_total_minor: unit * it.quantity,
      available_stock: inv.stock,
      status,
      message,
    });
  }
  const billable = lines.filter((l) => l.status === 'ok' || l.status === 'price_changed');
  const subtotal = billable.reduce((s, l) => s + l.line_total_minor, 0);
  const code = isStr(b.discount_code) && b.discount_code.trim() ? b.discount_code.trim().toUpperCase() : null;
  const d = code ? store.activeDiscount(code) : null;
  const discount = d ? Math.floor((subtotal * d.percent) / 100) : 0;
  return {
    currency: 'PKR',
    lines,
    subtotal_minor: subtotal,
    discount_code: code,
    discount_valid: code ? !!d : null,
    discount_percent: d ? d.percent : 0,
    discount_minor: discount,
    total_minor: subtotal - discount,
    can_checkout: lines.length > 0 && lines.every((l) => l.status === 'ok'),
  };
}

function describeLines(lines) {
  return lines.map((l) => {
    const v = state.variants.get(l.variant_id);
    const p = v && state.products.get(v.product_id);
    if (!p) return null;
    const lbl = variantLabel(v);
    return `${p.name}${lbl === 'Standard' ? '' : ` (${lbl})`}`;
  });
}
store.setLineDescriber(describeLines);

async function checkout(user, b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!isId(b.order_id)) bad.push('order_id');
  validateItems(b.items, bad, 10);
  if (b.discount_code !== undefined && b.discount_code !== null && !isStr(b.discount_code)) bad.push('discount_code');
  if (!(isObj(b.payment) && MOCK_TOKENS.includes(b.payment.token))) bad.push('payment');
  if (bad.length) throw validation(bad);

  const items = b.items.map((it) => ({ variant_id: it.variant_id, quantity: it.quantity }));
  const code = isStr(b.discount_code) && b.discount_code.trim() ? b.discount_code.trim().toUpperCase() : null;
  // Replays go straight to the engine, which returns the stored result (or DUPLICATE_ORDER_ID).
  if (!state.orders.has(b.order_id)) {
    for (const it of items) {
      const v = state.variants.get(it.variant_id);
      const p = v && state.products.get(v.product_id);
      if (!v || !p || !views.inTenant(user, p)) throw err(404, 'VARIANT_NOT_FOUND', `Variant ${it.variant_id} does not exist.`, { variant_id: it.variant_id });
      if (p.active === false || v.active === false) {
        throw err(409, 'PRODUCT_UNAVAILABLE', `${p.name} is no longer sold.`, { variant_id: it.variant_id, product_id: p.product_id });
      }
    }
  }
  const r = await store.checkout({ order_id: b.order_id, customer_id: user.user_id, items, discount_code: code, payment: { token: b.payment.token } });
  if (r.status !== 201 && r.status !== 200) return r;
  let order = state.prodOrders.get(b.order_id);
  if (!order) {
    order = buildOrder(user, r.body, code);
    state.prodOrders.set(order.order_id, order);
  }
  return { status: r.status, body: { ...r.body, order: orderView(order) } };
}

function buildOrder(user, body, code) {
  const lines = body.items.map((l) => {
    const v = state.variants.get(l.variant_id);
    const p = state.products.get(v.product_id);
    const img = primaryImage(p);
    return {
      variant_id: l.variant_id,
      product_id: p.product_id,
      product_name: p.name,
      club_id: p.club_id,
      club_name: views.clubName(p.club_id),
      size: v.size || null,
      color: v.color || null,
      label: variantLabel(v),
      image_url: img ? img.url : null,
      quantity: l.quantity,
      unit_price_minor: l.unit_price_minor,
      line_total_minor: l.unit_price_minor * l.quantity,
    };
  });
  const at = body.receipt.payload.paid_at;
  return {
    order_id: body.order_id,
    tenant_id: user.tenant_id || (state.products.get(lines[0].product_id) || {}).tenant_id || null,
    customer_id: user.user_id,
    customer_email: user.email,
    customer_name: user.name,
    club_ids: [...new Set(lines.map((l) => l.club_id))],
    lines,
    currency: 'PKR',
    subtotal_minor: body.subtotal_minor,
    discount_code: code,
    discount_minor: body.discount_minor,
    total_minor: body.total_minor,
    payment: { ...clone(body.payment), refund_id: null },
    created_at: at,
    history: [
      { from: null, to: 'pending', at, by: user.email, reason: 'Order placed' },
      { from: 'pending', to: 'paid', at, by: 'mock-gateway', reason: 'Payment captured' },
    ],
    receipt: { payload: clone(body.receipt.payload), signature: body.receipt.signature },
  };
}

// ---------------------------------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------------------------------
const statusOf = (o) => (state.orders.get(o.order_id) || { status: 'paid' }).status;

function orderView(o) {
  return { ...clone(o), status: statusOf(o), payment_status: o.payment.state };
}

const isCustomer = (user, o) => o.customer_id === user.user_id;
const managesOrder = (user, o) => o.club_ids.some((id) => state.clubs.get(id) && can(user, 'club.orders.read', state.clubs.get(id)));

function orderOr404(user, id) {
  const o = state.prodOrders.get(id);
  if (!o || !(isCustomer(user, o) || managesOrder(user, o))) throw err(404, 'ORDER_NOT_FOUND', `Order ${id} does not exist.`, { order_id: id });
  return o;
}

function listOrders(user, { scope = 'mine', club_id: clubId, status } = {}) {
  let out = [...state.prodOrders.values()];
  if (scope === 'mine') out = out.filter((o) => isCustomer(user, o));
  else if (scope === 'managed') out = out.filter((o) => managesOrder(user, o) && (!clubId || o.club_ids.includes(clubId)));
  else throw validation(['scope']);
  if (status) out = out.filter((o) => statusOf(o) === status);
  return out.sort((a, b) => b.created_at.localeCompare(a.created_at) || b.order_id.localeCompare(a.order_id)).map(orderView);
}

// Customers may cancel an order that has not been packed; store staff move it along and refund.
async function changeStatus(user, id, b) {
  const o = orderOr404(user, id);
  if (!isObj(b) || !isStr(b.status) || !Object.keys(store.ORDER_TRANSITIONS).includes(b.status)) throw validation(['status']);
  if (b.reason !== undefined && b.reason !== null && !(isStr(b.reason) && b.reason.length <= 200)) throw validation(['reason']);
  const to = b.status;
  const from = statusOf(o);
  const staff = managesOrder(user, o);
  if (!staff && !(isCustomer(user, o) && to === 'cancelled' && from === 'paid')) {
    throw err(403, 'FORBIDDEN', 'You are not allowed to change this order.', { action: 'order.status.write' });
  }
  store.transitionOrder(o.order_id, to);
  if (to === 'cancelled' || to === 'refunded') {
    const refund = store.gateway.refund(o.payment.capture_id);
    o.payment.state = 'refunded';
    o.payment.refund_id = refund.refund_id;
    await store.restock(o.lines);
    for (const l of o.lines) realtime.publish('store', 'inventory_changed', { variant_id: l.variant_id });
  }
  o.history.push({ from, to, at: nowIso(), by: user.email, reason: b.reason || null });
  return orderView(o);
}

function receipt(user, id) {
  const o = orderOr404(user, id);
  const expected = sign(o.order_id, o.receipt.payload);
  return {
    order_id: o.order_id,
    algorithm: 'HMAC-SHA256',
    message: 'order_id + "|" + canonical_json(payload)',
    payload: clone(o.receipt.payload),
    signature: o.receipt.signature,
    signature_valid: expected === o.receipt.signature,
  };
}

async function receiptPdfFor(user, id) {
  const o = orderOr404(user, id);
  return receiptPdf(o.receipt.payload, { signature: o.receipt.signature, lines: o.lines.map((l) => `${l.product_name}${l.label === 'Standard' ? '' : ` (${l.label})`}`) });
}

module.exports = {
  MAX_IMAGE_BYTES, MOCK_TOKENS, productView, listProducts, visibleProduct, writableProduct, createProduct, updateProduct,
  addVariant, updateVariant, lowStock, addImage, setPrimaryImage, removeImage, setLogo, media, quote, checkout,
  listOrders, orderOr404, orderView, changeStatus, receipt, receiptPdfFor, variantLabel, sniffImage,
};
