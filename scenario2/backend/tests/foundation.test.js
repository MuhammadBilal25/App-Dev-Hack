'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { start, stop, call } = require('../../../tests/helpers');
const { signDay2 } = require('../shared/signature');
const { state } = require('../../../src/state');

const GUEST = { authorization: 'Bearer guest_anon_tok_7721' };

test.before(start);
test.after(stop);

test('signDay2 matches the Appendix A reference vectors (salt T01D27ad7ffff12e)', () => {
  assert.strictEqual(
    signDay2('sk_live_9f83a1b2c3d4e5f6', { action: 'rotate', player_id: 'player-alpha-1', status: 'active', stream_key: 'sk_live_9f83a1b2c3d4e5f6' }),
    '9bd054eb746844b4701c6f158209c315ef2b16f392efd733bdf0715940610289',
  );
  assert.strictEqual(
    signDay2('sk_live_101', { action: 'rotate', player_id: 'player-alpha-1' }),
    '830b24eb2c795c02c54c17516b0e96870f5b65d98d28c2f0a15619ec3e076188',
  );
});

test('reset seeds the Day 2 baseline', async () => {
  const r = await call('POST', '/audit/v1/reset', {});
  assert.strictEqual(r.status, 200);
  assert.strictEqual(state.players.get('player-beta-2').club_id, 'club-beta-1');
  const score = await call('GET', '/audit/v1/score/match-m1');
  assert.strictEqual(score.body.status, 'in_progress');
  assert.deepStrictEqual([score.body.home.score, score.body.away.score], [1, 0]);
  assert.strictEqual(state.day2.qr.byEntity.get('match-m1').short_url, 'http://localhost:8080/q/m1-live');
  assert.strictEqual(state.day2.qr.byCode.get('p-alpha-1'), 'player-alpha-1');
  assert.strictEqual(state.day2.qr.byCode.get('c-alpha-1'), 'club-alpha-1');
  assert.strictEqual(state.day2.guestCart.tokens.get('guest_anon_tok_7721').merged, false);
  assert.deepStrictEqual(state.day2.guestCart.carts.get('player-alpha-1').items, []);
});

test('guest tokens get 403 GUEST_WRITE_FORBIDDEN on write endpoints', async () => {
  for (const path of ['/api/v1/chat', '/audit/v1/checkout', '/audit/v1/events']) {
    const r = await call('POST', path, { any: 'body' }, GUEST);
    assert.strictEqual(r.status, 403, path);
    assert.strictEqual(r.body.error.code, 'GUEST_WRITE_FORBIDDEN', path);
    assert.strictEqual(r.body.error.details.guest_token, 'guest_anon_tok_7721');
  }
});

test('guest tokens can still read', async () => {
  const r = await call('GET', '/audit/v1/score/match-m1', undefined, GUEST);
  assert.strictEqual(r.status, 200);
});
