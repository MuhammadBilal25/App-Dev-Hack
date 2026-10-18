'use strict';

const crypto = require('crypto');
const { state } = require('../../../../../src/state');
const { err, validation } = require('../../../../../src/lib/errors');
const { isObj, isStr } = require('../../../../../src/lib/validate');
const { signDay2 } = require('../../../shared/signature');
const { MEDIA_RTMP_URL, MEDIA_HLS_URL, MEDIA_WEBRTC_URL } = require('../../../config');

const ACTIONS = ['generate', 'rotate', 'revoke'];

const store = () => state.day2.streaming;
const newKey = () => `sk_live_${crypto.randomBytes(8).toString('hex')}`;

function validate(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!ACTIONS.includes(b.action)) bad.push('action');
  if (!isStr(b.player_id) || !b.player_id) bad.push('player_id');
  if (b.label !== undefined && b.label !== null && !(isStr(b.label) && b.label.length >= 1 && b.label.length <= 64)) bad.push('label');
  if (b.stream_key_override !== undefined && b.stream_key_override !== null && !(isStr(b.stream_key_override) && b.stream_key_override.length >= 1 && b.stream_key_override.length <= 128)) {
    bad.push('stream_key_override');
  }
  if (bad.length) throw validation(bad);
}

// Any earlier key of the player stops working at once (rotate / re-generate).
function revokeCurrent(playerId) {
  const current = store().keys.get(store().activeByPlayer.get(playerId));
  if (current && current.status === 'active') {
    current.status = 'revoked';
    current.revoked_at = new Date().toISOString();
  }
  store().activeByPlayer.delete(playerId);
  return current || null;
}

function view(action, rec) {
  const active = rec.status === 'active';
  const sigPayload = { action, player_id: rec.player_id, status: rec.status, stream_key: rec.stream_key };
  return {
    player_id: rec.player_id,
    label: rec.label,
    stream_key: rec.stream_key,
    status: rec.status,
    ingest_endpoints: active
      ? { rtmp: `${MEDIA_RTMP_URL}/live/${rec.stream_key}`, webrtc: `${MEDIA_WEBRTC_URL}/live/${rec.stream_key}/whip` }
      : null,
    playback_url: active ? `${MEDIA_HLS_URL}/live/${rec.stream_key}/index.m3u8` : null,
    signature: signDay2(rec.stream_key, sigPayload),
  };
}

// POST /audit/v1/stream/key (spec 5.4): generate (201) / rotate (200) / revoke (200).
function handleStreamKey(b) {
  validate(b);
  if (!state.players.has(b.player_id)) {
    throw err(404, 'PLAYER_NOT_FOUND', `Player ${b.player_id} does not exist.`, { player_id: b.player_id });
  }

  if (b.action === 'revoke') {
    const rec = store().keys.get(store().activeByPlayer.get(b.player_id));
    if (!rec || rec.status !== 'active') {
      throw err(404, 'STREAM_NOT_FOUND', `Player ${b.player_id} has no active stream key.`, { player_id: b.player_id });
    }
    revokeCurrent(b.player_id);
    return { status: 200, body: view('revoke', rec) };
  }

  const previous = revokeCurrent(b.player_id);
  const rec = {
    stream_key: b.stream_key_override || newKey(),
    player_id: b.player_id,
    label: b.label || (previous && b.action === 'rotate' ? previous.label : 'default'),
    status: 'active',
    created_at: new Date().toISOString(),
  };
  store().keys.set(rec.stream_key, rec);
  store().activeByPlayer.set(b.player_id, rec.stream_key);
  return { status: b.action === 'generate' ? 201 : 200, body: view(b.action, rec) };
}

// Media server publish/read hook: active keys pass, revoked keys get 409 KEY_REVOKED.
function checkKey(streamKey) {
  const rec = store().keys.get(streamKey);
  if (!rec) throw err(404, 'STREAM_NOT_FOUND', `Stream key ${streamKey} does not exist.`, { stream_key: streamKey });
  if (rec.status !== 'active') throw err(409, 'KEY_REVOKED', `Stream key ${streamKey} has been revoked.`, { stream_key: streamKey });
  return rec;
}

const activeKeyCount = () => [...store().keys.values()].filter((k) => k.status === 'active').length;

module.exports = { handleStreamKey, checkKey, activeKeyCount };
