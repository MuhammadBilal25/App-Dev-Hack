'use strict';

const { send } = require('../../../shared/send');
const service = require('../services/streamKey.service');

const streamKey = (req, res) => send(res, service.handleStreamKey(req.body));

// MediaMTX authHTTPAddress hook: { action, path: "live/<stream_key>", ... }. Non-2xx denies.
const mediaAuth = (req, res) => {
  const b = req.body || {};
  const m = /^live\/([^/]+)$/.exec(String(b.path || ''));
  if ((b.action === 'publish' || b.action === 'read') && m) service.checkKey(m[1]);
  res.status(200).json({ allowed: true });
};

module.exports = { streamKey, mediaAuth };
