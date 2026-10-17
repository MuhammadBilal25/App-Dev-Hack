'use strict';

const http = require('http');
const { createApp } = require('./app');
const db = require('./db');
const { reset } = require('./services/reset');

const PORT = Number(process.env.PORT || 8080);

async function main() {
  if (!process.env.DAY1_SALT) console.warn('WARNING: DAY1_SALT is not set; signatures will be wrong.');

  const app = createApp();
  const server = http.createServer(app);
  server.keepAliveTimeout = 65000;
  // Listen first so /health can answer 503 while the database warms up.
  server.listen(PORT, '0.0.0.0', () => console.log(`API listening on :${PORT}`));

  await db.waitForDb();
  await db.migrate();
  await reset({});
  console.log('Baseline data seeded; ready.');
}

main().catch((e) => {
  console.error('Fatal startup error', e);
  process.exit(1);
});
