'use strict';

const service = require('../services/ws.service');

// WebSocket upgrades are not Express routes; the HTTP server hands them to the service.
const attach = (server) => service.attach(server);

module.exports = { attach };
