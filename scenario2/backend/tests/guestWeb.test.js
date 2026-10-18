'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { start, stop, call, login } = require('../../../tests/helpers');

test.before(start);
test.after(stop);
test.beforeEach(() => call('POST', '/audit/v1/reset', {}));

const TESTIDS = [
  'guest-video-player', 'live-score-banner', 'pinned-merch-card', 'add-to-guest-cart-btn', 'guest-cart-count',
  'chat-message-list', 'chat-input-field', 'chat-send-btn', 'progressive-auth-modal',
];

test('every /web route serves the player page with all 9 data-testid hooks; modal hidden on load', async () => {
  for (const p of ['/web/matches/match-m1/live', '/web/costream/cs-session-101', '/web/matches/match-m1/vod']) {
    const r = await call('GET', p);
    assert.strictEqual(r.status, 200, p);
    for (const id of TESTIDS) assert.ok(r.body.includes(`data-testid="${id}"`), `${p} has ${id}`);
    assert.match(r.body, /data-testid="progressive-auth-modal"[^>]*hidden/);
  }
  const js = await call('GET', '/web/assets/app.js');
  assert.strictEqual(js.status, 200);
});

test('guest session -> read match -> stage cart; guest writes stay blocked', async () => {
  const s = await call('POST', '/api/v1/guest/session');
  assert.strictEqual(s.status, 201);
  assert.match(s.body.guest_token, /^guest_anon_tok_[a-f0-9]{12}$/);
  const g = { authorization: `Bearer ${s.body.guest_token}` };

  const m = await call('GET', '/api/v1/guest/matches/match-m1', undefined, g);
  assert.strictEqual(m.body.score_text, '1 - 0');
  assert.strictEqual(m.body.status, 'in_progress');
  assert.strictEqual(m.body.chat_room_id, 'chat-match-m1');
  assert.strictEqual(m.body.pinned_product.pinned_variant_id, 'var-jersey-001-L');
  assert.strictEqual(m.body.playback_url, null, 'nobody from the match is live yet');
  await call('POST', '/audit/v1/stream/key', { action: 'rotate', player_id: 'player-alpha-1', stream_key_override: 'sk_live_00000000000000aa' });
  assert.strictEqual((await call('GET', '/api/v1/guest/matches/match-m1')).body.playback_url, 'http://localhost:8888/live/sk_live_00000000000000aa/index.m3u8');
  assert.strictEqual((await call('GET', '/api/v1/guest/matches/ghost')).body.error.code, 'MATCH_NOT_FOUND');

  const add = await call('POST', '/api/v1/guest/cart', { variant_id: 'var-jersey-001-L' }, g);
  assert.strictEqual(add.status, 200);
  assert.strictEqual(add.body.count, 1);
  await call('POST', '/api/v1/guest/cart', { variant_id: 'var-jersey-001-L', quantity: 2 }, g);
  assert.strictEqual((await call('GET', '/api/v1/guest/cart', undefined, g)).body.count, 3);
  assert.strictEqual((await call('POST', '/api/v1/guest/cart', { variant_id: 'nope' }, g)).body.error.code, 'VARIANT_NOT_FOUND');
  assert.strictEqual((await call('POST', '/api/v1/guest/cart', { variant_id: 'var-jersey-001-L', quantity: 0 }, g)).status, 400);
  assert.strictEqual((await call('POST', '/api/v1/guest/cart', { variant_id: 'var-jersey-001-L' })).status, 401);

  const chat = await call('POST', '/api/v1/chat', { chat_room_id: 'chat-match-m1', text: 'hi' }, g);
  assert.strictEqual(chat.status, 403);
  assert.strictEqual(chat.body.error.code, 'GUEST_WRITE_FORBIDDEN');
});

test('progressive registration: login, then the staged guest cart merges once', async () => {
  const token = (await call('POST', '/api/v1/guest/session')).body.guest_token;
  const g = { authorization: `Bearer ${token}` };
  await call('POST', '/api/v1/guest/cart', { variant_id: 'var-jersey-001-L' }, g);
  const member = await login('viewer@nascon.test');

  const m = await call('POST', '/api/v1/guest/merge', { guest_token: token }, member);
  assert.strictEqual(m.status, 200);
  assert.strictEqual(m.body.cart_merged, true);
  assert.strictEqual(m.body.active_cart.user_id, 'user-viewer');
  assert.strictEqual(m.body.active_cart.total_items, 1);

  const again = await call('POST', '/api/v1/guest/merge', { guest_token: token }, member);
  assert.strictEqual(again.body.active_cart.total_items, 1, 'no double merge');
  assert.strictEqual((await call('POST', '/api/v1/guest/cart', { variant_id: 'var-jersey-001-L' }, g)).body.error.code, 'GUEST_TOKEN_ALREADY_MERGED');
  assert.strictEqual((await call('POST', '/api/v1/guest/merge', { guest_token: token })).status, 401);
});

test('costream, player and club views', async () => {
  await call('POST', '/audit/v1/costream/session', {
    session_id: 'cs-session-101', host_player_id: 'player-alpha-1', participants: ['player-alpha-1', 'player-alpha-2'], simulate_host_drop: true,
  });
  const c = await call('GET', '/api/v1/guest/costream/cs-session-101');
  assert.strictEqual(c.body.active_host, 'player-alpha-2');
  assert.strictEqual(c.body.chat_room_id, 'chat-cs-session-101');
  assert.strictEqual((await call('GET', '/api/v1/guest/costream/cs-x')).body.error.code, 'STREAM_NOT_FOUND');
  assert.strictEqual((await call('GET', '/api/v1/guest/players/player-alpha-1')).body.club.club_id, 'club-alpha-1');
  assert.strictEqual((await call('GET', '/api/v1/guest/players/x')).status, 404);
  assert.strictEqual((await call('GET', '/api/v1/guest/clubs/club-alpha-1')).body.name, 'Alpha Falcons FC');
  assert.strictEqual((await call('GET', '/api/v1/guest/clubs/x')).status, 404);
});
