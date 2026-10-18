'use strict';

const test = require('node:test');
const assert = require('node:assert');
const http = require('http');
const { WebSocket } = require('ws');
const { start, stop, call } = require('../../../tests/helpers');
const { signDay2 } = require('../shared/signature');
const { createApp } = require('../../../src/app');
const day2 = require('..');
const notify = require('../modules/moderation/services/notify.service');

test.before(start);
test.after(stop);
test.beforeEach(() => call('POST', '/audit/v1/reset', {}));

const ALL4 = ['player-alpha-1', 'player-alpha-2', 'player-beta-1', 'player-beta-2'];
const session = (over = {}) => ({ session_id: 'cs-session-101', host_player_id: 'player-alpha-1', participants: ALL4, layout: 'grid_4', simulate_host_drop: true, ...over });
const merge = (over = {}) => ({ guest_token: 'guest_anon_tok_7721', registered_user_id: 'player-alpha-1', guest_cart: [{ variant_id: 'var-jersey-001-L', quantity: 1 }], test_write_block: true, ...over });
const EXAMPLE_MESSAGES = [
  { message_id: 'msg-1', sender: 'user-guest-1', text: 'Clean sports commentary' },
  { message_id: 'msg-2', sender: 'user-spammer', text: 'Watch this illegal stream b@d_w0rd now!' },
  { message_id: 'msg-3', sender: 'user-flooder', text: 'GOAL! AAAA!!!' },
];

// ---------------- streaming ----------------
test('stream key: rotate with override, revoke, then 404 / 409 KEY_REVOKED', async () => {
  const r = await call('POST', '/audit/v1/stream/key', { action: 'rotate', player_id: 'player-alpha-1', label: 'OBS-Main-Desk', stream_key_override: 'sk_live_9f83a1b2c3d4e5f6' });
  assert.strictEqual(r.status, 200);
  assert.deepStrictEqual(r.body.ingest_endpoints, {
    rtmp: 'rtmp://localhost:1935/live/sk_live_9f83a1b2c3d4e5f6',
    webrtc: 'http://localhost:8889/live/sk_live_9f83a1b2c3d4e5f6/whip',
  });
  assert.strictEqual(r.body.playback_url, 'http://localhost:8888/live/sk_live_9f83a1b2c3d4e5f6/index.m3u8');
  assert.strictEqual(r.body.signature, signDay2('sk_live_9f83a1b2c3d4e5f6', { action: 'rotate', player_id: 'player-alpha-1', status: 'active', stream_key: 'sk_live_9f83a1b2c3d4e5f6' }));

  const rv = await call('POST', '/audit/v1/stream/key', { action: 'revoke', player_id: 'player-alpha-1' });
  assert.strictEqual(rv.status, 200);
  assert.strictEqual(rv.body.status, 'revoked');
  assert.strictEqual(rv.body.ingest_endpoints, null);
  assert.strictEqual(rv.body.playback_url, null);
  assert.strictEqual(rv.body.label, 'OBS-Main-Desk');

  const again = await call('POST', '/audit/v1/stream/key', { action: 'revoke', player_id: 'player-alpha-1' });
  assert.strictEqual(again.body.error.code, 'STREAM_NOT_FOUND');
  const pub = await call('POST', '/internal/media/auth', { action: 'publish', path: 'live/sk_live_9f83a1b2c3d4e5f6' });
  assert.strictEqual(pub.status, 409);
  assert.strictEqual(pub.body.error.code, 'KEY_REVOKED');
});

test('stream key: generate is 201 with a fresh key; rotating kills the old key; validation', async () => {
  const g = await call('POST', '/audit/v1/stream/key', { action: 'generate', player_id: 'player-beta-1' });
  assert.strictEqual(g.status, 201);
  assert.match(g.body.stream_key, /^sk_live_[a-f0-9]{16}$/);
  assert.strictEqual(g.body.label, 'default');
  assert.strictEqual((await call('POST', '/internal/media/auth', { action: 'publish', path: `live/${g.body.stream_key}` })).status, 200);
  const rot = await call('POST', '/audit/v1/stream/key', { action: 'rotate', player_id: 'player-beta-1' });
  assert.notStrictEqual(rot.body.stream_key, g.body.stream_key);
  assert.strictEqual((await call('POST', '/internal/media/auth', { action: 'publish', path: `live/${g.body.stream_key}` })).status, 409);

  assert.deepStrictEqual((await call('POST', '/audit/v1/stream/key', { action: 'pause', player_id: 'player-beta-1' })).body.error.details.fields, ['action']);
  assert.strictEqual((await call('POST', '/audit/v1/stream/key', { action: 'generate', player_id: 'nobody' })).body.error.code, 'PLAYER_NOT_FOUND');
  assert.strictEqual((await call('POST', '/audit/v1/stream/key', { action: 'generate', player_id: 'player-beta-1', label: '' })).status, 400);
});

// ---------------- costream ----------------
test('costream: host drop hands over to the next participant; replay is 200', async () => {
  const r = await call('POST', '/audit/v1/costream/session', session());
  assert.strictEqual(r.status, 201);
  assert.strictEqual(r.body.active_host, 'player-alpha-2');
  assert.strictEqual(r.body.handoff_occurred, true);
  assert.strictEqual(r.body.participant_count, 3);
  assert.deepStrictEqual(r.body.active_participants, ['player-alpha-2', 'player-beta-1', 'player-beta-2']);
  assert.strictEqual(r.body.composite_playback_url, 'http://localhost:8888/costream/cs-session-101/index.m3u8');
  assert.strictEqual(r.body.chat_room_id, 'chat-cs-session-101');
  assert.strictEqual(r.body.signature, signDay2('cs-session-101', {
    active_host: 'player-alpha-2', handoff_occurred: true, layout: 'grid_4', participant_count: 3, session_id: 'cs-session-101', status: 'active',
  }));
  const replay = await call('POST', '/audit/v1/costream/session', session());
  assert.strictEqual(replay.status, 200);
  assert.deepStrictEqual(replay.body, r.body);
});

test('costream: no drop, sole host drop, and the validation order', async () => {
  const keep = await call('POST', '/audit/v1/costream/session', session({ session_id: 'cs-session-1', simulate_host_drop: false }));
  assert.strictEqual(keep.body.active_host, 'player-alpha-1');
  assert.strictEqual(keep.body.participant_count, 4);

  const solo = await call('POST', '/audit/v1/costream/session', session({ session_id: 'cs-session-2', participants: ['player-alpha-1'], layout: 'solo' }));
  assert.strictEqual(solo.body.status, 'terminated');
  assert.strictEqual(solo.body.active_host, null);
  assert.strictEqual(solo.body.participant_count, 0);

  const code = async (b) => (await call('POST', '/audit/v1/costream/session', b)).body.error.code;
  assert.strictEqual(await code(session({ participants: [] })), 'VALIDATION_ERROR');
  assert.strictEqual(await code(session({ participants: ['player-alpha-1', 'player-alpha-1'] })), 'VALIDATION_ERROR');
  assert.strictEqual(await code(session({ layout: 'grid_9' })), 'VALIDATION_ERROR');
  assert.strictEqual(await code(session({ participants: ['player-alpha-1', 'ghost'] })), 'PLAYER_NOT_FOUND');
  assert.strictEqual(await code(session({ host_player_id: 'player-beta-1', participants: ['player-alpha-1', 'player-alpha-2'] })), 'VALIDATION_ERROR');
  const { state } = require('../../../src/state');
  state.players.set('player-extra', { player_id: 'player-extra', club_id: 'club-beta-1', tenant_id: 'tenant-beta', name: 'X' });
  assert.strictEqual(await code(session({ participants: [...ALL4, 'player-extra'] })), 'COSTREAM_SESSION_FULL');
  assert.strictEqual(await code(session({ layout: 'grid_2' })), 'UNSUPPORTED_LAYOUT');
  const fits = await call('POST', '/audit/v1/costream/session', session({ session_id: 'cs-session-3', participants: ['player-alpha-1', 'player-alpha-2', 'player-beta-1'], layout: 'grid_2' }));
  assert.strictEqual(fits.status, 201, 'after the drop only 2 remain, so grid_2 fits');
});

// ---------------- qr ----------------
test('qr: resolve counts scans, inspect does not, signature covers the live route', async () => {
  const r = await call('GET', '/audit/v1/qr/match-m1');
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.body.target_route, '/web/matches/match-m1/live');
  assert.strictEqual(r.body.scan_count, 1);
  assert.strictEqual(r.body.deep_link_uri, 'nascon://entity/match-m1');
  assert.strictEqual(r.body.export_formats.pdf, 'http://localhost:8080/audit/v1/qr/match-m1/export.pdf');
  assert.strictEqual(r.body.signature, signDay2('match-m1', { entity_id: 'match-m1', short_url: 'http://localhost:8080/q/m1-live', target_route: '/web/matches/match-m1/live' }));
  assert.strictEqual((await call('GET', '/audit/v1/qr/match-m1?inspect=true')).body.scan_count, 1);
  assert.strictEqual((await call('GET', '/audit/v1/qr/nothing-here')).body.error.code, 'QR_NOT_FOUND');
  assert.strictEqual((await call('GET', '/audit/v1/qr/player-alpha-1')).body.target_route, '/web/players/player-alpha-1');
  assert.strictEqual((await call('GET', '/audit/v1/qr/club-alpha-1')).body.target_route, '/web/clubs/club-alpha-1');
});

test('qr edge case 2: the short URL stays, the route and signature follow the match state', async () => {
  const before = (await call('GET', '/audit/v1/qr/match-m1')).body;
  await call('POST', '/audit/v1/events', { event_id: 'end-m1', match_id: 'match-m1', type: 'match_end', payload: {} });
  const after = (await call('GET', '/audit/v1/qr/match-m1')).body;
  assert.strictEqual(after.short_url, before.short_url);
  assert.strictEqual(after.target_route, '/web/matches/match-m1/vod');
  assert.notStrictEqual(after.signature, before.signature);

  await call('POST', '/audit/v1/matches/match-m1/status', { status: 'postponed' });
  assert.strictEqual((await call('GET', '/audit/v1/qr/match-m1')).body.target_route, '/web/matches/match-m1/notice?state=postponed');
  assert.strictEqual((await call('POST', '/audit/v1/matches/match-m1/status', { status: 'finished' })).status, 400);
  assert.strictEqual((await call('POST', '/audit/v1/matches/ghost/status', { status: 'postponed' })).status, 404);
});

test('qr: /q redirects with 302 and exports are real SVG / PNG / PDF', async () => {
  const r = await call('GET', '/audit/v1/qr/match-m1?inspect=true');
  const base = r.body.export_formats.svg.replace('http://localhost:8080', '');
  const app = createApp().listen(0);
  const port = app.address().port;
  try {
    const q = await fetch(`http://127.0.0.1:${port}/q/m1-live`, { redirect: 'manual' });
    assert.strictEqual(q.status, 302);
    assert.strictEqual(q.headers.get('location'), '/web/matches/match-m1/live');
    assert.strictEqual((await fetch(`http://127.0.0.1:${port}/q/nope`, { redirect: 'manual' })).status, 404);

    const svg = await fetch(`http://127.0.0.1:${port}${base}`);
    assert.strictEqual(svg.headers.get('content-type'), 'image/svg+xml');
    assert.match(await svg.text(), /^(<svg|<\?xml)/);
    const png = Buffer.from(await (await fetch(`http://127.0.0.1:${port}${base.replace('.svg', '.png')}`)).arrayBuffer());
    assert.deepStrictEqual([...png.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const pdf = await fetch(`http://127.0.0.1:${port}${base.replace('.svg', '.pdf')}`);
    assert.strictEqual(pdf.headers.get('content-type'), 'application/pdf');
    assert.strictEqual(Buffer.from(await pdf.arrayBuffer()).subarray(0, 5).toString(), '%PDF-');
    assert.strictEqual((await fetch(`http://127.0.0.1:${port}${base.replace('.svg', '.gif')}`)).status, 400);
  } finally {
    app.close();
  }
  const scans = (await call('GET', '/audit/v1/qr/match-m1?inspect=true')).body.scan_count;
  assert.strictEqual(scans, 1, 'the /q scan was counted, exports were not');
});

// ---------------- guest cart ----------------
test('cart merge: write block verified, merged once, replay never doubles (edge case 4)', async () => {
  const r = await call('POST', '/audit/v1/guest/cart-merge', merge());
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.body.write_block_verified, true);
  assert.strictEqual(r.body.write_rejection_code, 403);
  assert.deepStrictEqual(r.body.active_cart, {
    user_id: 'player-alpha-1', currency: 'PKR', total_items: 1, subtotal_minor: 450000,
    items: [{ variant_id: 'var-jersey-001-L', quantity: 1, unit_price_minor: 450000 }],
  });
  assert.strictEqual(r.body.signature, signDay2('guest_anon_tok_7721', {
    cart_merged: true, guest_token: 'guest_anon_tok_7721', registered_user_id: 'player-alpha-1', total_items: 1, write_rejection_code: 403,
  }));
  const [a, b] = await Promise.all([call('POST', '/audit/v1/guest/cart-merge', merge()), call('POST', '/audit/v1/guest/cart-merge', merge())]);
  assert.strictEqual(a.body.active_cart.total_items, 1);
  assert.strictEqual(b.body.active_cart.total_items, 1);
  const other = await call('POST', '/audit/v1/guest/cart-merge', merge({ registered_user_id: 'player-alpha-2' }));
  assert.strictEqual(other.status, 409);
  assert.strictEqual(other.body.error.code, 'GUEST_TOKEN_ALREADY_MERGED');
});

test('cart merge: concurrent first merges add once; validation, 404s and stock', async () => {
  const both = await Promise.all([1, 2].map(() => call('POST', '/audit/v1/guest/cart-merge', merge({ guest_token: 'guest_tok_new' }))));
  assert.deepStrictEqual(both.map((r) => r.body.active_cart.total_items), [1, 1]);

  const code = async (b) => (await call('POST', '/audit/v1/guest/cart-merge', b)).body.error.code;
  assert.strictEqual(await code(merge({ guest_token: 'anon_1' })), 'VALIDATION_ERROR');
  assert.strictEqual(await code(merge({ guest_cart: [] })), 'VALIDATION_ERROR');
  assert.strictEqual(await code(merge({ guest_cart: [{ variant_id: 'var-jersey-001-L', quantity: 0 }] })), 'VALIDATION_ERROR');
  assert.strictEqual(await code(merge({ registered_user_id: 'ghost' })), 'PLAYER_NOT_FOUND');
  assert.strictEqual(await code(merge({ guest_token: 'guest_x', guest_cart: [{ variant_id: 'var-nope', quantity: 1 }] })), 'VARIANT_NOT_FOUND');
  const oos = await call('POST', '/audit/v1/guest/cart-merge', merge({ guest_token: 'guest_y', guest_cart: [{ variant_id: 'var-jersey-001-M', quantity: 2 }] }));
  assert.strictEqual(oos.status, 409);
  assert.strictEqual(oos.body.error.code, 'OUT_OF_STOCK');
  assert.strictEqual(oos.body.error.details.variant_id, 'var-jersey-001-M');
});

// ---------------- moderation ----------------
test('moderation: spec example (mask + kick, flood drop + mute, empty DLQ)', async () => {
  const r = await call('POST', '/audit/v1/moderation/test', { chat_room_id: 'chat-cs-session-101', incoming_messages: EXAMPLE_MESSAGES, check_dlq: true, simulate_failed_notifications: 0 });
  assert.strictEqual(r.status, 200);
  assert.deepStrictEqual(r.body.filtered_messages, [
    { message_id: 'msg-1', sender: 'user-guest-1', text: 'Clean sports commentary', flagged: false, reason: null },
    { message_id: 'msg-2', sender: 'user-spammer', text: 'Watch this illegal stream *** now!', flagged: true, reason: 'profanity_leetspeak' },
  ]);
  assert.deepStrictEqual(r.body.kicked_users, ['user-spammer']);
  assert.deepStrictEqual(r.body.muted_users, ['user-flooder']);
  assert.deepStrictEqual(r.body.dlq_status, { queue_depth: 0, undelivered_events: [] });
  assert.strictEqual(r.body.signature, signDay2('chat-cs-session-101', { chat_room_id: 'chat-cs-session-101', flagged_count: 1, kicked_users: ['user-spammer'], queue_depth: 0 }));
});

test('moderation edge case 3: 10 simultaneous moderators give one deduplicated kick', async () => {
  const body = { chat_room_id: 'chat-race', incoming_messages: [EXAMPLE_MESSAGES[1]], check_dlq: true };
  const all = await Promise.all(Array.from({ length: 10 }, () => call('POST', '/audit/v1/moderation/test', body)));
  for (const r of all) {
    assert.strictEqual(r.status, 200);
    assert.deepStrictEqual(r.body.kicked_users, ['user-spammer']);
    assert.strictEqual(r.body.dlq_status.queue_depth, 0);
  }
});

test('moderation: leetspeak dictionary, rate limit, DLQ simulation and validation', async () => {
  const msgs = ['p.0.r.n', 's!c@m', 'f*u*c*k', 'a$$h0le', 'idiot_spam'].map((text, i) => ({ message_id: `l-${i}`, sender: `u-${i}`, text }));
  const r = await call('POST', '/audit/v1/moderation/test', { chat_room_id: 'room-l', incoming_messages: msgs });
  assert.ok(r.body.filtered_messages.every((m) => m.text === '***' && m.flagged));

  const burst = Array.from({ length: 5 }, (_, i) => ({ message_id: `b-${i}`, sender: 'fast', text: `hello ${i}` }));
  const rl = await call('POST', '/audit/v1/moderation/test', { chat_room_id: 'room-r', incoming_messages: burst });
  assert.strictEqual(rl.body.filtered_messages.length, 3);
  assert.deepStrictEqual(rl.body.muted_users, ['fast']);

  const d = await call('POST', '/audit/v1/moderation/test', { chat_room_id: 'room-d', incoming_messages: [], check_dlq: true, simulate_failed_notifications: 2 });
  assert.strictEqual(d.body.dlq_status.queue_depth, 2);
  assert.strictEqual(d.body.dlq_status.undelivered_events[0].attempts, 3);
  assert.match(await (await call('GET', '/metrics')).body, /^nascon_dlq_depth 2$/m);

  assert.strictEqual((await call('POST', '/audit/v1/moderation/test', { chat_room_id: 'x', incoming_messages: [{ message_id: 'a' }] })).status, 400);
});

test('notification bus retries 3 times with backoff, then dead-letters', async () => {
  let tries = 0;
  const failing = await notify.deliver({ type: 'score_update' }, async () => {
    tries += 1;
    throw new Error('push gateway down');
  }, { baseDelayMs: 1 });
  assert.strictEqual(tries, 3);
  assert.strictEqual(failing.delivered, false);
  assert.strictEqual(failing.dlq.last_error, 'push gateway down');
  const ok = await notify.deliver({ type: 'x' }, async () => {}, { baseDelayMs: 1 });
  assert.deepStrictEqual(ok, { delivered: true, attempts: 1 });
});

test('chat API: guests and anonymous users get 403, members post through moderation', async () => {
  const anon = await call('POST', '/api/v1/chat', { chat_room_id: 'chat-cs-session-101', text: 'hi' });
  assert.strictEqual(anon.status, 403);
  assert.strictEqual(anon.body.error.code, 'GUEST_WRITE_FORBIDDEN');
  const { login } = require('../../../tests/helpers');
  const h = await login('viewer@nascon.test');
  const r = await call('POST', '/api/v1/chat', { chat_room_id: 'chat-cs-session-101', text: 'what a b@d_w0rd' }, h);
  assert.strictEqual(r.status, 201);
  assert.strictEqual(r.body.message.text, 'what a ***');
  const hist = await call('GET', '/api/v1/chat/chat-cs-session-101');
  assert.strictEqual(hist.body.messages.at(-1).sequence, 1);
});

// ---------------- observability ----------------
test('metrics: Prometheus text with all five metrics', async () => {
  await call('GET', '/audit/v1/qr/match-m1');
  await call('POST', '/audit/v1/stream/key', { action: 'generate', player_id: 'player-alpha-1' });
  const app = createApp().listen(0);
  try {
    const res = await fetch(`http://127.0.0.1:${app.address().port}/metrics`);
    assert.strictEqual(res.headers.get('content-type'), 'text/plain; version=0.0.4; charset=utf-8');
    const text = await res.text();
    for (const m of ['nascon_active_ws_connections', 'nascon_active_streams_total', 'nascon_stream_bitrate_kbps', 'nascon_dlq_depth', 'nascon_qr_scans_total']) {
      assert.match(text, new RegExp(`^# TYPE ${m} (gauge|counter)$`, 'm'));
      assert.match(text, new RegExp(`^${m} \\d+$`, 'm'));
    }
    assert.match(text, /^nascon_qr_scans_total 1$/m);
    assert.match(text, /^nascon_active_streams_total 1$/m);
  } finally {
    app.close();
  }
});

test('privacy erase anonymises the user and unlinks merged guest tokens', async () => {
  await call('POST', '/audit/v1/guest/cart-merge', merge());
  const r = await call('DELETE', '/audit/v1/privacy/user/player-alpha-1');
  assert.deepStrictEqual(r.body, { user_id: 'player-alpha-1', status: 'anonymized', pii_retained: false, tokens_wiped: true });
  const { state } = require('../../../src/state');
  assert.strictEqual(state.players.get('player-alpha-1').name, 'Anonymized Player');
  assert.strictEqual(state.day2.guestCart.tokens.get('guest_anon_tok_7721').merged_into, null);
  assert.ok(![...state.users.values()].some((u) => u.email === 'player@nascon.test'));
  assert.strictEqual((await call('DELETE', '/audit/v1/privacy/user/ghost')).body.error.code, 'PLAYER_NOT_FOUND');
});

// ---------------- realtime ----------------
test('NFR-1: a score event reaches 25 WebSocket clients fast; SSE alias streams', async () => {
  const server = http.createServer(createApp());
  day2.attachRealtime(server);
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;
  try {
    const clients = await Promise.all(Array.from({ length: 25 }, () => new Promise((resolve, reject) => {
      const ws = new WebSocket(`ws://127.0.0.1:${port}/ws/matches/match-m1`);
      ws.once('message', (m) => {
        assert.strictEqual(JSON.parse(m).score_text, '1 - 0');
        resolve(ws);
      });
      ws.once('error', reject);
    })));
    const t0 = Date.now();
    const got = Promise.all(clients.map((ws) => new Promise((resolve) => ws.once('message', (m) => resolve([JSON.parse(m), Date.now() - t0])))));
    await call('POST', '/audit/v1/events', { event_id: 'ws-goal', match_id: 'match-m1', type: 'score', payload: { team_id: 'club-alpha-1', event_type: 'goal' } });
    const frames = await got;
    for (const [f, ms] of frames) {
      assert.strictEqual(f.score_text, '2 - 0');
      assert.ok(ms < 500, `delivered in ${ms} ms`);
    }
    const metrics = await (await fetch(`http://127.0.0.1:${port}/metrics`)).text();
    assert.match(metrics, /^nascon_active_ws_connections 25$/m);
    clients.forEach((ws) => ws.close());

    const bad = new WebSocket(`ws://127.0.0.1:${port}/ws/nothing`);
    await new Promise((r) => bad.once('error', r));

    const ctrl = new AbortController();
    const sse = await fetch(`http://127.0.0.1:${port}/api/v1/matches/match-m1/stream`, { signal: ctrl.signal });
    assert.strictEqual(sse.headers.get('content-type'), 'text/event-stream');
    ctrl.abort();
  } finally {
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
  }
});
