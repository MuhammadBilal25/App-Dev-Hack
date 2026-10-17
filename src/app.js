'use strict';

const express = require('express');
const { ApiError, errorBody } = require('./lib/errors');
const { state } = require('./state');
const db = require('./db');
const { reset } = require('./services/reset');
const sports = require('./services/sports');
const scoring = require('./services/scoring');
const leagues = require('./services/leagues');
const realtime = require('./realtime');

// Services return { status, body }; this sends it.
const send = (res, r) => res.status(r.status).json(r.body);

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

  app.post('/audit/v1/sports', (req, res) => send(res, sports.createSport(req.body)));
  app.post('/audit/v1/leagues', (req, res) => send(res, leagues.registerLeague(req.body)));
  app.post('/audit/v1/events', (req, res) => send(res, scoring.appendEvent(req.body)));
  app.get('/audit/v1/score/:matchId', (req, res) => res.status(200).json(scoring.getScore(req.params.matchId)));

  // Realtime stream for the mobile app (SSE): /api/v1/stream?channels=match:m1,league:lg-1
  app.get('/api/v1/stream', (req, res) => realtime.subscribe(req, res));

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
