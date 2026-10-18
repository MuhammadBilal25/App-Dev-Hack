'use strict';

const crypto = require('crypto');
const { state } = require('../../../../../src/state');
const { err } = require('../../../../../src/lib/errors');
const realtime = require('../../../../../src/realtime');
const ws = require('../../realtime/services/ws.service');
const streaming = require('../../streaming/services/streamKey.service');
const costream = require('../../costream/services/costream.service');

const METRICS = [
  ['nascon_active_ws_connections', 'gauge', 'Open realtime connections (WebSocket + SSE).'],
  ['nascon_active_streams_total', 'gauge', 'Active solo stream keys plus active co-stream sessions.'],
  ['nascon_stream_bitrate_kbps', 'gauge', 'Last reported ingest bitrate in kbps.'],
  ['nascon_dlq_depth', 'gauge', 'Notifications waiting in the Dead-Letter Queue.'],
  ['nascon_qr_scans_total', 'counter', 'Dynamic QR scans since the last reset.'],
];

function values() {
  const m = state.day2.metrics;
  return {
    nascon_active_ws_connections: ws.count() + realtime.sseCount(),
    nascon_active_streams_total: streaming.activeKeyCount() + costream.activeSessionCount(),
    nascon_stream_bitrate_kbps: m.nascon_stream_bitrate_kbps,
    nascon_dlq_depth: state.day2.moderation.dlq.length,
    nascon_qr_scans_total: m.nascon_qr_scans_total,
  };
}

// GET /metrics: Prometheus text exposition format 0.0.4.
function metricsText() {
  const v = values();
  return METRICS.map(([name, type, help]) => `# HELP ${name} ${help}\n# TYPE ${name} ${type}\n${name} ${v[name]}\n`).join('');
}

// DELETE /audit/v1/privacy/user/{user_id} (NFR-9): wipes PII and unlinks guest/viewer tokens.
function eraseUser(userId) {
  const player = state.players.get(userId);
  const accounts = [...state.users.values()].filter((u) => u.user_id === userId || (player && u.player_id === userId));
  if (!player && accounts.length === 0) {
    throw err(404, 'PLAYER_NOT_FOUND', `User ${userId} does not exist.`, { user_id: userId });
  }
  const anon = `anon-${crypto.createHash('sha256').update(userId).digest('hex').slice(0, 12)}`;
  if (player) Object.assign(player, { name: 'Anonymized Player', anonymized: true });
  for (const u of accounts) {
    state.users.delete(u.email);
    Object.assign(u, { name: 'Anonymized User', email: `${anon}@anonymized.invalid`, active: false, anonymized: true });
    state.users.set(u.email, u);
  }

  // Guest/viewer tokens merged into this account no longer point at it.
  const ids = new Set([userId, ...accounts.map((u) => u.user_id)]);
  for (const [token, t] of state.day2.guestCart.tokens) {
    if (t.merged_into && ids.has(t.merged_into)) state.day2.guestCart.tokens.set(token, { guest_token: token, role: 'guest', merged: true, wiped: true, merged_into: null, merge_key: null, response: null });
  }
  // QR telemetry never held personal data (device family + hour bucket only), so nothing to scrub.
  return { status: 200, body: { user_id: userId, status: 'anonymized', pii_retained: false, tokens_wiped: true } };
}

module.exports = { metricsText, eraseUser, values };
