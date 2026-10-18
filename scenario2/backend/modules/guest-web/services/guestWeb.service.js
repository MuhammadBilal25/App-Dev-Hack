'use strict';

const crypto = require('crypto');
const { state } = require('../../../../../src/state');
const { err, validation } = require('../../../../../src/lib/errors');
const { isObj, isStr, isInt } = require('../../../../../src/lib/validate');
const scoring = require('../../../../../src/services/scoring');
const auth = require('../../../../../src/services/auth');
const { bearer, isGuestToken } = require('../../../shared/guestGuard');
const { MEDIA_HLS_URL } = require('../../../config');
const qr = require('../../qr/services/qr.service');
const guestCart = require('../../guest-cart/services/guestCart.service');

// FR-4.2: anonymous viewers get a short-lived guest_anon_tok_* scoped to read-only playback,
// live score subscription and local cart staging. Nothing here needs an account.
const GUEST_TTL_SECONDS = 2 * 60 * 60;
const DEFAULT_PINNED = 'prod-jersey-001';
const PINNED_VARIANT = 'var-jersey-001-L';

const tokens = () => state.day2.guestCart.tokens;
const staged = () => state.day2.guestCart.guestCarts;

// POST /api/v1/guest/session
function issueToken() {
  const token = `guest_anon_tok_${crypto.randomBytes(6).toString('hex')}`;
  tokens().set(token, { guest_token: token, role: 'guest', merged: false, issued_at: Date.now() });
  return {
    status: 201,
    body: { guest_token: token, role: 'guest', scope: ['stream.read', 'score.subscribe', 'cart.stage'], expires_in: GUEST_TTL_SECONDS },
  };
}

function guestFrom(req) {
  const token = bearer(req);
  if (!isGuestToken(token)) throw err(401, 'UNAUTHENTICATED', 'A guest token is required.');
  const t = tokens().get(token);
  if (!t) throw err(401, 'UNAUTHENTICATED', 'Unknown or expired guest token.');
  if (t.merged) throw err(409, 'GUEST_TOKEN_ALREADY_MERGED', 'This guest cart was already moved to an account.', { guest_token: token });
  return token;
}

function productView(productId) {
  const p = state.products.get(productId);
  if (!p) return null;
  return {
    product_id: p.product_id,
    name: p.name,
    variants: p.variants.map((v) => ({ variant_id: v.variant_id, size: v.size, price_minor: v.price_minor, currency: v.currency || 'PKR' })),
    pinned_variant_id: p.variants.some((v) => v.variant_id === PINNED_VARIANT) ? PINNED_VARIANT : p.variants[0].variant_id,
  };
}

const clubName = (id) => (state.clubs.get(id) || {}).name || id;

// The match plays the newest active stream key of a player from either club (keys are
// broadcast under /live/{stream_key}); null until someone from the match goes live.
function matchPlayback(m) {
  const keys = [...state.day2.streaming.keys.values()].filter((k) => {
    const p = state.players.get(k.player_id);
    return k.status === 'active' && p && (p.club_id === m.home || p.club_id === m.away);
  });
  const latest = keys.sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
  return latest ? `${MEDIA_HLS_URL}/live/${latest.stream_key}/index.m3u8` : null;
}

// GET /api/v1/guest/matches/{match_id}
function matchView(matchId) {
  const m = state.matches.get(matchId);
  if (!m) throw err(404, 'MATCH_NOT_FOUND', `Match ${matchId} does not exist.`, { match_id: matchId });
  const p = scoring.project(m);
  const status = qr.matchStatus(matchId);
  return {
    status: 200,
    body: {
      match_id: matchId,
      status,
      home: { team_id: m.home, name: clubName(m.home), score: p.home.score },
      away: { team_id: m.away, name: clubName(m.away), score: p.away.score },
      score_text: `${p.home.score} - ${p.away.score}`,
      playback_url: matchPlayback(m),
      vod_url: status === 'completed' ? `${MEDIA_HLS_URL}/vod/${matchId}/index.m3u8` : null,
      chat_room_id: `chat-${matchId}`,
      pinned_product: productView(state.pinned.get(matchId) || DEFAULT_PINNED),
    },
  };
}

// GET /api/v1/guest/costream/{session_id}
function costreamView(sessionId) {
  const s = state.day2.costream.sessions.get(sessionId);
  if (!s) throw err(404, 'STREAM_NOT_FOUND', `Co-stream ${sessionId} does not exist.`, { session_id: sessionId });
  const r = s.response;
  return {
    status: 200,
    body: {
      session_id: r.session_id,
      status: r.status,
      active_host: r.active_host,
      active_participants: r.active_participants.map((id) => ({ player_id: id, name: (state.players.get(id) || {}).name || id })),
      layout: r.layout,
      playback_url: r.composite_playback_url,
      chat_room_id: r.chat_room_id,
      pinned_product: productView(DEFAULT_PINNED),
    },
  };
}

// GET /api/v1/guest/players/{id} and /clubs/{id}: public profile basics only.
function playerView(id) {
  const p = state.players.get(id);
  if (!p) throw err(404, 'PLAYER_NOT_FOUND', `Player ${id} does not exist.`, { player_id: id });
  return { status: 200, body: { player_id: id, name: p.name, position: p.position || null, club: { club_id: p.club_id, name: clubName(p.club_id) } } };
}

function clubView(id) {
  const c = state.clubs.get(id);
  if (!c) throw err(404, 'CLUB_NOT_FOUND', `Club ${id} does not exist.`, { club_id: id });
  const players = [...state.players.values()].filter((p) => p.club_id === id && !p.anonymized).map((p) => ({ player_id: p.player_id, name: p.name }));
  return { status: 200, body: { club_id: id, name: c.name, home_venue: c.home_venue ? c.home_venue.name : null, players } };
}

function cartBody(token) {
  const items = staged().get(token) || [];
  return { guest_token: token, items: items.map((it) => ({ ...it })), count: items.reduce((n, it) => n + it.quantity, 0) };
}

// POST /api/v1/guest/cart { variant_id, quantity }: the one write a guest may do (FR-4.4).
function stageItem(req) {
  const token = guestFrom(req);
  const b = req.body;
  const bad = [];
  if (!isObj(b) || !isStr(b.variant_id) || !b.variant_id) bad.push('variant_id');
  if (isObj(b) && b.quantity !== undefined && !(isInt(b.quantity) && b.quantity >= 1 && b.quantity <= 10)) bad.push('quantity');
  if (bad.length) throw validation(bad);
  if (!state.variants.has(b.variant_id)) throw err(404, 'VARIANT_NOT_FOUND', `Variant ${b.variant_id} does not exist.`, { variant_id: b.variant_id });
  const items = staged().get(token) || [];
  const line = items.find((it) => it.variant_id === b.variant_id);
  const qty = b.quantity || 1;
  if (line) line.quantity = Math.min(10, line.quantity + qty);
  else items.push({ variant_id: b.variant_id, quantity: qty });
  staged().set(token, items);
  return { status: 200, body: cartBody(token) };
}

// GET /api/v1/guest/cart
const getCart = (req) => ({ status: 200, body: cartBody(guestFrom(req)) });

// POST /api/v1/guest/merge { guest_token } with the member's JWT: progressive registration.
// Moves the staged guest cart into the member's cart (same atomic, idempotent merge).
async function mergeAfterLogin(req) {
  const user = auth.authenticate(req);
  const b = req.body;
  if (!isObj(b) || !isGuestToken(b.guest_token)) throw validation(['guest_token']);
  const items = staged().get(b.guest_token) || [];
  if (items.length === 0) {
    const t = tokens().get(b.guest_token);
    if (t && t.merged && t.response) return { status: 200, body: t.response };
    return { status: 200, body: { guest_token: b.guest_token, cart_merged: false, active_cart: guestCart.cartView(user.user_id) } };
  }
  return guestCart.cartMerge({ guest_token: b.guest_token, registered_user_id: user.user_id, guest_cart: items, test_write_block: false });
}

module.exports = { issueToken, matchView, costreamView, playerView, clubView, stageItem, getCart, mergeAfterLogin };
