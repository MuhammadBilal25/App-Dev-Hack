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
const store = require('./services/store');
const roster = require('./services/roster');
const offlineSync = require('./services/offlineSync');
const auth = require('./services/auth');
const { guard, authorized } = require('./services/rbac');
const { rateLimit } = require('./middleware/rateLimit');

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

  app.post('/audit/v1/roster/setup', (req, res) => send(res, roster.setup(req.body)));
  app.post('/audit/v1/roster/transfer', (req, res) => send(res, roster.transfer(req.body)));
  app.get('/audit/v1/roster/history/:playerId', (req, res) => res.status(200).json(roster.history(req.params.playerId, req.query.as_of)));
  app.post('/audit/v1/offline-sync', (req, res) => send(res, offlineSync.sync(req.body)));

  app.post('/audit/v1/checkout', async (req, res) => send(res, await store.checkout(req.body)));
  app.get('/audit/v1/inventory/:variantId', async (req, res) => res.status(200).json(await store.inventory(req.params.variantId)));

  // RBAC matrix + probe routes (Section 5.13). Probes only authorize.
  app.post('/audit/v1/rbac-matrix', (req, res) => res.status(200).json(auth.rbacMatrix()));
  app.post('/audit/v1/rbac/tenants', guard('tenant.create'), authorized);
  app.post('/audit/v1/rbac/leagues/:leagueId/fixtures', guard('league.fixtures.write', 'league', 'leagueId'), authorized);
  app.post('/audit/v1/rbac/clubs/:clubId/roster', guard('club.roster.write', 'club', 'clubId'), authorized);
  app.post('/audit/v1/rbac/clubs/:clubId/products', guard('club.products.write', 'club', 'clubId'), authorized);
  app.patch('/audit/v1/rbac/players/:playerId', guard('player.update', 'player', 'playerId'), authorized);
  app.get('/audit/v1/rbac/clubs/:clubId', guard('club.read', 'club', 'clubId'), authorized);
  app.get('/audit/v1/rbac/platform/config', guard('platform.config.read'), authorized);

  // ---- Production API for the mobile app: rate limited (100 req / rolling 10 s / IP) ----
  app.use('/api/v1', rateLimit({ limit: 100, windowMs: 10000 }));
  app.get('/api/v1/ping', (req, res) => res.status(200).json({ pong: true }));
  app.post('/api/v1/auth/login', (req, res) => res.status(200).json(auth.login(req.body)));
  app.get('/api/v1/me', (req, res) => res.status(200).json(auth.publicUser(auth.authenticate(req))));

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
