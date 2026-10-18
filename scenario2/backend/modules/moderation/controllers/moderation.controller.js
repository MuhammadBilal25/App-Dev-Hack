'use strict';

const { send } = require('../../../shared/send');
const service = require('../services/moderation.service');

const moderate = (req, res) => send(res, service.moderate(req.body));
const postChat = (req, res) => send(res, service.postChat(req));

module.exports = { moderate, postChat };
