'use strict';

const { send } = require('../../../shared/send');
const service = require('../services/streamKey.service');

const streamKey = (req, res) => send(res, service.handleStreamKey(req.body));

module.exports = { streamKey };
