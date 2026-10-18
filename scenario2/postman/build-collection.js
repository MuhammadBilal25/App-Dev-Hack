// Generates Day2.postman_collection.json. Run: node scenario2/postman/build-collection.js
// Run the folders top to bottom; folder 1 resets the server. Expected status is in each name.
const fs = require('fs');
const path = require('path');

const req = (name, method, p, body, desc, headers = []) => ({
  name,
  request: {
    method,
    header: [...(body ? [{ key: 'Content-Type', value: 'application/json' }] : []), ...headers],
    url: { raw: '{{baseUrl}}' + p, host: ['{{baseUrl}}'], path: p.replace(/^\//, '').split('?')[0].split('/'), ...(p.includes('?') ? { query: p.split('?')[1].split('&').map((kv) => ({ key: kv.split('=')[0], value: kv.split('=')[1] })) } : {}) },
    ...(body ? { body: { mode: 'raw', raw: JSON.stringify(body, null, 2) } } : {}),
    description: desc || '',
  },
});
const GUEST = [{ key: 'Authorization', value: 'Bearer {{guestToken}}' }];
const ALL4 = ['player-alpha-1', 'player-alpha-2', 'player-beta-1', 'player-beta-2'];
const session = (over = {}) => ({ session_id: 'cs-session-101', host_player_id: 'player-alpha-1', participants: ALL4, layout: 'grid_4', simulate_host_drop: true, ...over });
const merge = (over = {}) => ({ guest_token: 'guest_anon_tok_7721', registered_user_id: 'player-alpha-1', guest_cart: [{ variant_id: 'var-jersey-001-L', quantity: 1 }], test_write_block: true, ...over });
const moderation = (over = {}) => ({
  chat_room_id: 'chat-cs-session-101',
  incoming_messages: [
    { message_id: 'msg-1', sender: 'user-guest-1', text: 'Clean sports commentary' },
    { message_id: 'msg-2', sender: 'user-spammer', text: 'Watch this illegal stream b@d_w0rd now!' },
    { message_id: 'msg-3', sender: 'user-flooder', text: 'GOAL! AAAA!!!' },
  ],
  check_dlq: true,
  simulate_failed_notifications: 0,
  ...over,
});

const collection = {
  info: {
    name: 'NaSCon 26 - Day 2 (Scenario 2)',
    schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
    description: 'Day 2 endpoints. Run folders top to bottom (folder 1 resets). The expected status (and error code) is in each request name and is asserted automatically. Signatures use DAY2_SALT from the server .env.',
  },
  variable: [
    { key: 'baseUrl', value: 'http://localhost:8080' },
    { key: 'guestToken', value: 'guest_anon_tok_7721' },
  ],
  event: [{
    listen: 'test',
    script: {
      type: 'text/javascript',
      exec: [
        'const m = pm.info.requestName.match(/->\\s*(\\d{3})(?:\\s+([A-Z_]{3,}))?/);',
        'if (m) {',
        '  pm.test(`status is ${m[1]}`, () => pm.response.to.have.status(Number(m[1])));',
        '  if (m[2]) pm.test(`error code is ${m[2]}`, () => pm.expect(pm.response.json().error.code).to.eql(m[2]));',
        '}',
        'if (pm.response.code < 300 && (pm.response.headers.get("Content-Type") || "").includes("json")) {',
        '  const b = pm.response.json();',
        '  if (b.signature !== undefined) pm.test("signature is 64 lowercase hex", () => pm.expect(b.signature).to.match(/^[a-f0-9]{64}$/));',
        '}',
      ],
    },
  }],
  item: [
    {
      name: '1. Setup',
      item: [
        req('Health -> 200', 'GET', '/health'),
        req('Reset (Day 1 + Day 2 baseline) -> 200', 'POST', '/audit/v1/reset', {}, 'Seeds match-m1 (in_progress 1-0), player-beta-2, QR m1-live / p-alpha-1 / c-alpha-1, guest_anon_tok_7721 and an empty cart for player-alpha-1.'),
        req('Score of match-m1 (1 - 0) -> 200', 'GET', '/audit/v1/score/match-m1'),
      ],
    },
    {
      name: '2. Stream keys (5.4)',
      item: [
        req('Rotate with override -> 200', 'POST', '/audit/v1/stream/key', { action: 'rotate', player_id: 'player-alpha-1', label: 'OBS-Main-Desk', stream_key_override: 'sk_live_9f83a1b2c3d4e5f6' }, 'Use rtmp://localhost:1935/live/sk_live_9f83a1b2c3d4e5f6 in OBS.'),
        req('Media hook: active key may publish -> 200', 'POST', '/internal/media/auth', { action: 'publish', path: 'live/sk_live_9f83a1b2c3d4e5f6' }),
        req('Generate new key -> 201', 'POST', '/audit/v1/stream/key', { action: 'generate', player_id: 'player-alpha-2' }, 'Random sk_live_ + 16 hex.'),
        req('Revoke -> 200', 'POST', '/audit/v1/stream/key', { action: 'revoke', player_id: 'player-alpha-1' }, 'status revoked, ingest_endpoints and playback_url null.'),
        req('Media hook: revoked key -> 409 KEY_REVOKED', 'POST', '/internal/media/auth', { action: 'publish', path: 'live/sk_live_9f83a1b2c3d4e5f6' }),
        req('Revoke again (no key) -> 404 STREAM_NOT_FOUND', 'POST', '/audit/v1/stream/key', { action: 'revoke', player_id: 'player-alpha-1' }),
        req('Bad action -> 400 VALIDATION_ERROR', 'POST', '/audit/v1/stream/key', { action: 'pause', player_id: 'player-alpha-1' }),
        req('Unknown player -> 404 PLAYER_NOT_FOUND', 'POST', '/audit/v1/stream/key', { action: 'generate', player_id: 'player-ghost' }),
      ],
    },
    {
      name: '3. Co-stream (5.5)',
      item: [
        req('4-way, host drops -> 201', 'POST', '/audit/v1/costream/session', session(), 'active_host player-alpha-2, handoff_occurred true, participant_count 3.'),
        req('Same request again (idempotent) -> 200', 'POST', '/audit/v1/costream/session', session()),
        req('No drop -> 201', 'POST', '/audit/v1/costream/session', session({ session_id: 'cs-session-102', simulate_host_drop: false })),
        req('Sole host drops (terminated) -> 201', 'POST', '/audit/v1/costream/session', session({ session_id: 'cs-session-103', participants: ['player-alpha-1'], layout: 'solo' })),
        req('Host not in participants -> 400 VALIDATION_ERROR', 'POST', '/audit/v1/costream/session', session({ session_id: 'cs-x', host_player_id: 'player-beta-1', participants: ['player-alpha-1', 'player-alpha-2'] })),
        req('Unknown participant -> 404 PLAYER_NOT_FOUND', 'POST', '/audit/v1/costream/session', session({ session_id: 'cs-x', participants: ['player-alpha-1', 'player-ghost'] })),
        req('grid_2 with 3 left -> 400 UNSUPPORTED_LAYOUT', 'POST', '/audit/v1/costream/session', session({ session_id: 'cs-x', layout: 'grid_2' })),
        req('QR for the co-stream -> 200', 'GET', '/audit/v1/qr/cs-session-101?inspect=true', null, 'target_route /web/costream/cs-session-101'),
      ],
    },
    {
      name: '4. Dynamic QR (5.6)',
      item: [
        req('Resolve match-m1 (live) -> 200', 'GET', '/audit/v1/qr/match-m1', null, 'scan_count goes up by 1 each time.'),
        req('Inspect (no scan counted) -> 200', 'GET', '/audit/v1/qr/match-m1?inspect=true'),
        req('Short link redirect -> 302', 'GET', '/q/m1-live', null, 'Turn off "Automatically follow redirects" in Postman settings to see the 302 and Location header.'),
        req('Export SVG -> 200', 'GET', '/audit/v1/qr/match-m1/export.svg'),
        req('Export PNG -> 200', 'GET', '/audit/v1/qr/match-m1/export.png'),
        req('Export PDF poster -> 200', 'GET', '/audit/v1/qr/match-m1/export.pdf'),
        req('Export GIF -> 400 VALIDATION_ERROR', 'GET', '/audit/v1/qr/match-m1/export.gif'),
        req('Player QR -> 200', 'GET', '/audit/v1/qr/player-alpha-1?inspect=true'),
        req('Club QR -> 200', 'GET', '/audit/v1/qr/club-alpha-1?inspect=true'),
        req('Unknown entity -> 404 QR_NOT_FOUND', 'GET', '/audit/v1/qr/match-ghost'),
        req('Edge 2: end match-m1 -> 201', 'POST', '/audit/v1/events', { event_id: 'pm-end-m1', match_id: 'match-m1', type: 'match_end', payload: {} }),
        req('Edge 2: same short_url, route now /vod -> 200', 'GET', '/audit/v1/qr/match-m1?inspect=true'),
        req('Edge 2: postpone match-m1 (helper) -> 200', 'POST', '/audit/v1/matches/match-m1/status', { status: 'postponed' }),
        req('Edge 2: route now /notice?state=postponed -> 200', 'GET', '/audit/v1/qr/match-m1?inspect=true'),
        req('Clear the postponed helper -> 200', 'POST', '/audit/v1/matches/match-m1/status', { status: null }),
      ],
    },
    {
      name: '5. Guest boundary + cart merge (5.7)',
      item: [
        req('Reset -> 200', 'POST', '/audit/v1/reset', {}),
        req('Guest posts chat -> 403 GUEST_WRITE_FORBIDDEN', 'POST', '/api/v1/chat', { chat_room_id: 'chat-cs-session-101', text: 'hello' }, '', GUEST),
        req('Guest checkout -> 403 GUEST_WRITE_FORBIDDEN', 'POST', '/audit/v1/checkout', { order_id: 'o-guest' }, '', GUEST),
        req('Guest score event -> 403 GUEST_WRITE_FORBIDDEN', 'POST', '/audit/v1/events', { event_id: 'g1' }, '', GUEST),
        req('No token chat -> 403 GUEST_WRITE_FORBIDDEN', 'POST', '/api/v1/chat', { chat_room_id: 'chat-cs-session-101', text: 'hello' }),
        req('Guest can read -> 200', 'GET', '/audit/v1/score/match-m1', null, '', GUEST),
        req('Merge guest cart -> 200', 'POST', '/audit/v1/guest/cart-merge', merge(), 'total_items 1, write_rejection_code 403.'),
        req('Edge 4: replay same merge -> 200', 'POST', '/audit/v1/guest/cart-merge', merge(), 'Still total_items 1 (never 2).'),
        req('Same token, other user -> 409 GUEST_TOKEN_ALREADY_MERGED', 'POST', '/audit/v1/guest/cart-merge', merge({ registered_user_id: 'player-alpha-2' })),
        req('Too many M (stock 1) -> 409 OUT_OF_STOCK', 'POST', '/audit/v1/guest/cart-merge', merge({ guest_token: 'guest_pm_2', guest_cart: [{ variant_id: 'var-jersey-001-M', quantity: 2 }] })),
        req('Unknown variant -> 404 VARIANT_NOT_FOUND', 'POST', '/audit/v1/guest/cart-merge', merge({ guest_token: 'guest_pm_3', guest_cart: [{ variant_id: 'var-ghost', quantity: 1 }] })),
        req('Unknown user -> 404 PLAYER_NOT_FOUND', 'POST', '/audit/v1/guest/cart-merge', merge({ guest_token: 'guest_pm_4', registered_user_id: 'player-ghost' })),
        req('Token without guest_ prefix -> 400 VALIDATION_ERROR', 'POST', '/audit/v1/guest/cart-merge', merge({ guest_token: 'anon_1' })),
      ],
    },
    {
      name: '6. Moderation + DLQ (5.8)',
      item: [
        req('Spec example -> 200', 'POST', '/audit/v1/moderation/test', moderation(), 'msg-2 masked to ***, user-spammer kicked, user-flooder muted, msg-3 dropped.'),
        req('Leetspeak set -> 200', 'POST', '/audit/v1/moderation/test', moderation({
          chat_room_id: 'room-leet',
          incoming_messages: ['p.0.r.n', 's!c@m', 'f*u*c*k', 'a$$h0le', 'idiot_spam'].map((text, i) => ({ message_id: `pm-l-${i}`, sender: `user-${i}`, text })),
        })),
        req('Rate limit: 5 fast messages -> 200', 'POST', '/audit/v1/moderation/test', moderation({
          chat_room_id: 'room-rate',
          incoming_messages: [0, 1, 2, 3, 4].map((i) => ({ message_id: `pm-r-${i}`, sender: 'user-fast', text: `hello ${i}` })),
        }), 'Only 3 broadcast; user-fast muted.'),
        req('Simulate 2 failed notifications -> 200', 'POST', '/audit/v1/moderation/test', moderation({ chat_room_id: 'room-dlq', incoming_messages: [], simulate_failed_notifications: 2 }), 'dlq_status.queue_depth 2, attempts 3 each.'),
        req('Bad body -> 400 VALIDATION_ERROR', 'POST', '/audit/v1/moderation/test', { chat_room_id: 'x', incoming_messages: [{ message_id: 'a' }] }),
        req('Chat history (read) -> 200', 'GET', '/api/v1/chat/chat-cs-session-101'),
      ],
    },
    {
      name: '7. Observability + privacy (5.9)',
      item: [
        req('Prometheus metrics -> 200', 'GET', '/metrics'),
        req('Erase player-alpha-1 -> 200', 'DELETE', '/audit/v1/privacy/user/player-alpha-1'),
        req('Erase unknown -> 404 PLAYER_NOT_FOUND', 'DELETE', '/audit/v1/privacy/user/player-ghost'),
        req('Reset (restore player-alpha-1) -> 200', 'POST', '/audit/v1/reset', {}),
      ],
    },
  ],
};

const out = path.join(__dirname, 'Day2.postman_collection.json');
fs.writeFileSync(out, JSON.stringify(collection, null, 2) + '\n');
console.log(`wrote ${out}`);
