'use strict';

const { send } = require('../../../shared/send');
const service = require('../services/observability.service');

const metrics = (req, res) => res.set('Content-Type', 'text/plain; version=0.0.4').status(200).send(service.metricsText());
const eraseUser = (req, res) => send(res, service.eraseUser(req.params.userId));

module.exports = { metrics, eraseUser };
