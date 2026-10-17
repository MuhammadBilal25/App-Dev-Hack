'use strict';

const { ApiError, errorBody } = require('../lib/errors');

// Rolling-window limiter: at most `limit` accepted requests per `windowMs` per client IP.
// Rejected requests are not counted, so a client recovers exactly when its window drains.
function rateLimit({ limit = 100, windowMs = 10000 } = {}) {
  const hits = new Map();

  setInterval(() => {
    const cutoff = Date.now() - windowMs;
    for (const [ip, arr] of hits) {
      while (arr.length && arr[0] <= cutoff) arr.shift();
      if (!arr.length) hits.delete(ip);
    }
  }, windowMs).unref();

  return (req, res, next) => {
    const now = Date.now();
    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    let arr = hits.get(ip);
    if (!arr) hits.set(ip, (arr = []));
    while (arr.length && arr[0] <= now - windowMs) arr.shift();
    if (arr.length >= limit) {
      const retry = Math.max(1, Math.ceil((arr[0] + windowMs - now) / 1000));
      res.set('Retry-After', String(retry));
      return res.status(429).json(errorBody(new ApiError(429, 'RATE_LIMITED', 'Too many requests. Please slow down.', { retry_after_seconds: retry })));
    }
    arr.push(now);
    res.set('X-RateLimit-Limit', String(limit));
    res.set('X-RateLimit-Remaining', String(limit - arr.length));
    return next();
  };
}

module.exports = { rateLimit };
