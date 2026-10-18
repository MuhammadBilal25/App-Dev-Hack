'use strict';

const fs = require('fs');
const path = require('path');
const { state } = require('../../../../../src/state');
const { err, validation } = require('../../../../../src/lib/errors');
const storage = require('../../../../../src/lib/storage');
const { MEDIA_API_URL, RECORDINGS_DIR } = require('../../../config');

// Talks to the MediaMTX control API (only when MEDIA_API_URL is set, i.e. inside Docker).
async function mediaApi(method, p) {
  if (!MEDIA_API_URL) return null;
  const res = await fetch(`${MEDIA_API_URL}${p}`, { method, signal: AbortSignal.timeout(1500) });
  if (!res.ok) return null;
  const text = await res.text();
  return text ? JSON.parse(text) : {};
}

const KICK = { rtmpConn: 'rtmpconns', webRTCSession: 'webrtcsessions', rtspSession: 'rtspsessions', srtConn: 'srtconns' };

// FR-3.2: revoking/rotating a key cuts the live ingest at once (well inside the 2 s budget).
async function kickPublisher(streamKey) {
  try {
    const p = await mediaApi('GET', `/v3/paths/get/live/${encodeURIComponent(streamKey)}`);
    const src = p && p.source;
    if (src && KICK[src.type]) await mediaApi('POST', `/v3/${KICK[src.type]}/kick/${src.id}`);
  } catch {
    // Media server unreachable: the auth hook still refuses any new publish with this key.
  }
}

// Reads live paths every few seconds for /metrics (active streams, ingest bitrate).
let last = null;
async function pollOnce() {
  const list = await mediaApi('GET', '/v3/paths/list?itemsPerPage=1000');
  if (!list || !state.day2) return;
  const ready = (list.items || []).filter((p) => p.ready);
  const bytes = ready.reduce((n, p) => n + (p.bytesReceived || 0), 0);
  const now = Date.now();
  const kbps = last && bytes >= last.bytes ? Math.round(((bytes - last.bytes) * 8) / (now - last.at)) : 0;
  last = { bytes, at: now };
  state.day2.metrics.nascon_stream_bitrate_kbps = kbps;
  state.day2.metrics.media_live_paths = ready.length;
}

function startPolling(intervalMs = 5000) {
  if (!MEDIA_API_URL) return null;
  const t = setInterval(() => pollOnce().catch(() => {}), intervalMs);
  t.unref();
  return t;
}

// POST /internal/media/recorded (MediaMTX runOnRecordSegmentComplete): upload the finished
// segment to MinIO and add it to the VOD index of that stream.
async function recorded(b) {
  if (!b || typeof b.path !== 'string' || typeof b.segment !== 'string') throw validation(['path', 'segment']);
  const file = path.resolve(RECORDINGS_DIR, path.relative('/recordings', b.segment));
  if (!file.startsWith(path.resolve(RECORDINGS_DIR))) throw validation(['segment']);
  const key = `vod/${b.path}/${path.basename(file)}`;
  let stored = false;
  try {
    await storage.put(key, await fs.promises.readFile(file), 'video/mp4');
    stored = true;
  } catch {
    // MinIO or the shared volume is missing: keep the index entry so the VOD is still listed.
  }
  const entry = { path: b.path, key, url: `/media/${key}`, stored, recorded_at: new Date().toISOString() };
  state.day2.streaming.vods.push(entry);
  return { status: 201, body: entry };
}

// GET /api/v1/vods?path=live/<key>: indexed recordings (newest first).
function listVods(query) {
  const filter = query && typeof query.path === 'string' ? query.path : null;
  const items = state.day2.streaming.vods.filter((v) => !filter || v.path === filter).slice().reverse();
  return { status: 200, body: { items } };
}

function requireKnownStream(streamKey) {
  if (!state.day2.streaming.keys.has(streamKey)) throw err(404, 'STREAM_NOT_FOUND', `Stream key ${streamKey} does not exist.`, { stream_key: streamKey });
}

module.exports = { kickPublisher, pollOnce, startPolling, recorded, listVods, requireKnownStream };
