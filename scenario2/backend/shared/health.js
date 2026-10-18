'use strict';

const queue = require('../../../src/queue');
const { MEDIA_API_URL } = require('../config');

// Spec 5.2: GET /health verifies DB, Redis, Media Server and the baseline seed. Redis and the
// media server are checked only when configured (always true inside docker-compose).
async function redisOk() {
  if (!process.env.REDIS_URL) return null;
  const r = queue.client();
  if (!r) return false;
  try {
    return (await Promise.race([r.ping(), new Promise((_, no) => setTimeout(() => no(new Error('timeout')), 1000))])) === 'PONG';
  } catch {
    return false;
  }
}

async function mediaOk() {
  if (!MEDIA_API_URL) return null;
  try {
    const res = await fetch(`${MEDIA_API_URL}/v3/config/global/get`, { signal: AbortSignal.timeout(1000) });
    return res.ok;
  } catch {
    return false;
  }
}

async function dependencies() {
  const [redis, media] = await Promise.all([redisOk(), mediaOk()]);
  return { redis, media };
}

module.exports = { dependencies };
