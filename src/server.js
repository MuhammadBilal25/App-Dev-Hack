'use strict';

const http = require('http');
const { createApp } = require('./app');
const db = require('./db');
const { reset } = require('./services/reset');
const storage = require('./lib/storage');
const day2 = require('../scenario2/backend');

const PORT = Number(process.env.PORT || 8080);

async function main() {
  if (!process.env.DAY1_SALT) console.warn('WARNING: DAY1_SALT is not set; signatures will be wrong.');
  if (!process.env.DAY2_SALT) console.warn('WARNING: DAY2_SALT is not set; Day 2 signatures will be wrong.');

  const app = createApp();
  const server = http.createServer(app);
  server.keepAliveTimeout = 65000;
  day2.attachRealtime(server);
  day2.startMediaPolling();
  // Listen first so /health can answer 503 while the database warms up.
  server.listen(PORT, '0.0.0.0', () => console.log(`API listening on :${PORT}`));

  storage.init(); // background: MinIO bucket, never blocks startup
  await db.waitForDb();
  await db.migrate();
  await reset({});
  console.log('Baseline data seeded; ready.');
}

main().catch((e) => {
  console.error('Fatal startup error', e);
  process.exit(1);
});
