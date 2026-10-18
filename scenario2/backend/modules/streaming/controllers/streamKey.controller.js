'use strict';

const { send } = require('../../../shared/send');
const service = require('../services/streamKey.service');
const media = require('../services/media.service');

const streamKey = (req, res) => send(res, service.handleStreamKey(req.body));

// MediaMTX authHTTPAddress hook: { action, path: "live/<stream_key>", ... }. Non-2xx denies.
const mediaAuth = (req, res) => {
  const b = req.body || {};
  const m = /^live\/([^/]+)$/.exec(String(b.path || ''));
  if ((b.action === 'publish' || b.action === 'read') && m) service.checkKey(m[1]);
  res.status(200).json({ allowed: true });
};

const recorded = async (req, res) => send(res, await media.recorded(req.body));
const vods = (req, res) => send(res, media.listVods(req.query));

module.exports = { streamKey, mediaAuth, recorded, vods };
