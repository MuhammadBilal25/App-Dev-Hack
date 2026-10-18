'use strict';

const { send } = require('../../../shared/send');
const service = require('../services/costream.service');

const createSession = (req, res) => send(res, service.createSession(req.body));

module.exports = { createSession };
