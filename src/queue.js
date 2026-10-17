'use strict';

const Redis = require('ioredis');
const { pool } = require('./db');

// Internal job/event queue: domain events are written to a durable outbox table and published
// to a Redis Stream (`domain-events`) consumed by the worker. Publishing never blocks a request.
const STREAM = 'domain-events';
let redis = null;

function client() {
  if (!redis && process.env.REDIS_URL) {
    redis = new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: 1, lazyConnect: false, enableOfflineQueue: false });
    redis.on('error', () => {});
  }
  return redis;
}

function emit(topic, body) {
  const record = { topic, body, emitted_at: new Date().toISOString() };
  pool.query('INSERT INTO domain_events (topic, body) VALUES ($1, $2)', [topic, body]).catch(() => {});
  const r = client();
  if (r && r.status === 'ready') r.xadd(STREAM, 'MAXLEN', '~', 10000, '*', 'event', JSON.stringify(record)).catch(() => {});
  return record;
}

module.exports = { emit, client, STREAM };
