'use strict';

const express = require('express');
const { ApiError, errorBody } = require('./lib/errors');
const { state } = require('./state');
const db = require('./db');
const { reset } = require('./services/reset');
const sports = require('./services/sports');
const scoring = require('./services/scoring');
const leagues = require('./services/leagues');
const fixtures = require('./services/fixtures');
const standingsSvc = require('./services/standings');
const realtime = require('./realtime');
const store = require('./services/store');
const roster = require('./services/roster');
const offlineSync = require('./services/offlineSync');
const auth = require('./services/auth');
const { guard, authorized } = require('./services/rbac');
const { rateLimit } = require('./middleware/rateLimit');
const { mobileRouter } = require('./routes/mobile');
const { opsRouter } = require('./routes/ops');
const { shopRouter } = require('./routes/shop');
const { adminRouter } = require('./routes/admin');
const merch = require('./services/merch');
const day2 = require('../scenario2/backend');
const day2Health = require('../scenario2/backend/shared/health');

// Image uploads arrive as raw bytes; every other body is parsed as JSON.
const isBinary = (req) => /^(image\/|application\/octet-stream)/i.test(req.headers['content-type'] || '');

// Services return { status, body }; this sends it.
const send = (res, r) => res.status(r.status).json(r.body);

function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', false);

  // Form bodies (MediaMTX recording callback) are parsed by their own route.
  app.use(express.json({ limit: '1mb', type: (req) => !isBinary(req) && !/urlencoded/i.test(req.headers['content-type'] || '') }));
  day2.mountGuards(app);

  // Uploaded images, streamed from object storage. Public (product photos and logos) and outside
  // /api/v1 so image-heavy screens do not eat into the rate limit.
  app.get(/^\/media\/(.+)$/, async (req, res) => {
    const obj = await merch.media(req.params[0]);
    if (!obj) return res.status(404).json(errorBody(new ApiError(404, 'NOT_FOUND', 'No such image.')));
    res.set({ 'Content-Type': obj.contentType, 'Cache-Control': 'public, max-age=86400', 'X-Content-Type-Options': 'nosniff' });
    return res.status(200).send(obj.buffer);
  });

  app.get('/health', async (req, res) => {
    const [dbOk, deps] = await Promise.all([db.ping(), day2Health.dependencies()]);
    // null = not configured (local runs without Redis / media server).
    const redisOk = deps.redis !== false;
    const mediaOk = deps.media !== false;
    if (dbOk && state.ready && redisOk && mediaOk) return res.status(200).json({ status: 'ok' });
    return res.status(503).json({ status: 'starting', database: dbOk, redis: deps.redis, media_server: deps.media, seeded: !!state.ready });
  });

  app.post('/audit/v1/reset', async (req, res) => {
    res.status(200).json(await reset(req.body));
  });

  app.post('/audit/v1/sports', (req, res) => send(res, sports.createSport(req.body)));
  app.post('/audit/v1/fixtures', (req, res) => send(res, fixtures.generate(req.body)));
  app.post('/audit/v1/leagues', (req, res) => send(res, leagues.registerLeague(req.body)));
  app.post('/audit/v1/events', (req, res) => send(res, scoring.appendEvent(req.body)));
  app.get('/audit/v1/standings/:leagueId', (req, res) => res.status(200).json(standingsSvc.standings(req.params.leagueId)));
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
  // 100 per rolling 10 s is the contract; API_RATE_LIMIT exists only so long test suites can raise it.
  app.use('/api/v1', rateLimit({ limit: Number(process.env.API_RATE_LIMIT) || 100, windowMs: 10000 }));
  app.get('/api/v1/ping', (req, res) => res.status(200).json({ pong: true }));
  app.post('/api/v1/auth/login', (req, res) => res.status(200).json(auth.login(req.body)));
  app.get('/api/v1/me', (req, res) => res.status(200).json(auth.publicUser(auth.authenticate(req))));

  // Realtime stream for the mobile app (SSE): /api/v1/stream?channels=match:m1,league:lg-1
  app.get('/api/v1/stream', (req, res) => realtime.subscribe(req, res));
  app.use('/api/v1', mobileRouter());
  app.use('/api/v1', opsRouter());
  app.use('/api/v1', shopRouter());
  app.use('/api/v1/admin', adminRouter());

  // ---- Day 2 (scenario2/backend): streaming, co-stream, QR, guest cart, moderation, metrics ----
  day2.mountRoutes(app);

  app.use((req, res) => {
    res.status(404).json(errorBody(new ApiError(404, 'NOT_FOUND', `No route for ${req.method} ${req.path}.`)));
  });

  // eslint-disable-next-line no-unused-vars
  app.use((e, req, res, next) => {
    if (e instanceof ApiError) return res.status(e.status).json(errorBody(e));
    if (e && e.type === 'entity.too.large') {
      return res.status(413).json(errorBody(new ApiError(413, 'PAYLOAD_TOO_LARGE', isBinary(req) ? 'Images must be 5 MB or smaller.' : 'Request body exceeds 1 MB.')));
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
