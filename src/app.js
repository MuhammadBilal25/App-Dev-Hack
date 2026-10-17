'use strict';

const express = require('express');
const { ApiError, errorBody } = require('./lib/errors');
const { state } = require('./state');
const db = require('./db');
const { reset } = require('./services/reset');

function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', false);

  app.use(express.json({ limit: '1mb', type: () => true }));

  app.get('/health', async (req, res) => {
    const dbOk = await db.ping();
    if (dbOk && state.ready) return res.status(200).json({ status: 'ok' });
    return res.status(503).json({ status: 'starting', database: dbOk, seeded: !!state.ready });
  });

  app.post('/audit/v1/reset', async (req, res) => {
    res.status(200).json(await reset(req.body));
  });

  app.use((req, res) => {
    res.status(404).json(errorBody(new ApiError(404, 'NOT_FOUND', `No route for ${req.method} ${req.path}.`)));
  });

  // eslint-disable-next-line no-unused-vars
  app.use((e, req, res, next) => {
    if (e instanceof ApiError) return res.status(e.status).json(errorBody(e));
    if (e && e.type === 'entity.too.large') {
      return res.status(413).json(errorBody(new ApiError(413, 'PAYLOAD_TOO_LARGE', 'Request body exceeds 1 MB.')));
    }
    if (e && (e.type === 'entity.parse.failed' || e instanceof SyntaxError)) {
      return res.status(400).json(errorBody(new ApiError(400, 'VALIDATION_ERROR', 'Malformed JSON body.', { fields: ['body'] })));
    }
    if (e && e.type && e.status >= 400 && e.status < 500) {
      return res.status(400).json(errorBody(new ApiError(400, 'VALIDATION_ERROR', 'Unreadable request body.', { fields: ['body'] })));
    }
    console.error(e);
    return res.status(500).json(errorBody(new ApiError(500, 'INTERNAL_ERROR', 'Unexpected server error.')));
  });

  return app;
}

module.exports = { createApp };
