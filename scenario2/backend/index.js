'use strict';

// Day 2 (Scenario 2) entry point. The Day 1 app (src/app.js) calls these so both phases run in
// one API on port 8080, sharing the same database, Redis, players and store.
const { guestWriteGuard } = require('./shared/guestGuard');
const { resetDay2 } = require('./shared/seed');
const { streamingRouter } = require('./modules/streaming/routes/streaming.routes');
const { costreamRouter } = require('./modules/costream/routes/costream.routes');
const { qrRouter } = require('./modules/qr/routes/qr.routes');
const { guestCartRouter } = require('./modules/guest-cart/routes/guestCart.routes');
const { moderationRouter } = require('./modules/moderation/routes/moderation.routes');
const { observabilityRouter } = require('./modules/observability/routes/observability.routes');
const { realtimeRouter } = require('./modules/realtime/routes/realtime.routes');
const { guestWebRouter } = require('./modules/guest-web/routes/guestWeb.routes');
const ws = require('./modules/realtime/controllers/ws.controller');
const media = require('./modules/streaming/services/media.service');

// Runs before every Day 1 and Day 2 route: guest tokens can never write (FR-4.3).
function mountGuards(app) {
  app.use(guestWriteGuard);
}

function mountRoutes(app) {
  app.use(streamingRouter());
  app.use(costreamRouter());
  app.use(qrRouter());
  app.use(guestCartRouter());
  app.use(moderationRouter());
  app.use(observabilityRouter());
  app.use(realtimeRouter());
  app.use(guestWebRouter());
}

module.exports = { mountGuards, mountRoutes, resetDay2, attachRealtime: ws.attach, startMediaPolling: () => media.startPolling() };
