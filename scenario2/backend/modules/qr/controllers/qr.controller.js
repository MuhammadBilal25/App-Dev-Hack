'use strict';

const { send } = require('../../../shared/send');
const service = require('../services/qr.service');

const resolve = (req, res) => send(res, service.resolve(req.params.entityId, req.query, req.headers['user-agent']));

const exportQr = async (req, res) => {
  const { contentType, buffer } = await service.exportQr(req.params.entityId, req.params.fmt);
  res.set('Content-Type', contentType).status(200).send(buffer);
};

const redirect = (req, res) => res.redirect(302, service.redirectTarget(req.params.shortCode, req.headers['user-agent']));

const setMatchStatus = (req, res) => send(res, service.setMatchStatus(req.params.matchId, req.body));

module.exports = { resolve, exportQr, redirect, setMatchStatus };
