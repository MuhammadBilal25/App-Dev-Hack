'use strict';

const path = require('path');
const { send } = require('../../../shared/send');
const service = require('../services/guestWeb.service');

const WEB_DIR = path.join(__dirname, '..', '..', '..', '..', 'web');

const session = (req, res) => send(res, service.issueToken());
const match = (req, res) => send(res, service.matchView(req.params.matchId));
const costream = (req, res) => send(res, service.costreamView(req.params.sessionId));
const player = (req, res) => send(res, service.playerView(req.params.playerId));
const club = (req, res) => send(res, service.clubView(req.params.clubId));
const stageItem = (req, res) => send(res, service.stageItem(req));
const getCart = (req, res) => send(res, service.getCart(req));
const merge = async (req, res) => send(res, await service.mergeAfterLogin(req));
const memberCart = (req, res) => send(res, service.memberCart(req));
const memberAdd = (req, res) => send(res, service.memberAdd(req));
const memberSet = (req, res) => send(res, service.memberSet(req));
const memberClear = (req, res) => send(res, service.memberClear(req));

// Every /web/* route is the same single page; the browser script reads the path.
const page = (req, res) => res.set('Cache-Control', 'no-store').sendFile(path.join(WEB_DIR, 'index.html'));

module.exports = { session, match, costream, player, club, stageItem, getCart, merge, memberCart, memberAdd, memberSet, memberClear, page, WEB_DIR };
