'use strict';

// Local preview without Docker: runs the full API on :8080 with the in-memory test database.
// Usage: node scenario2/backend/dev-server.js   (data resets on restart; not for grading)
const http = require('http');
require('../../tests/helpers'); // swaps PostgreSQL for the in-memory fake
const { createApp } = require('../../src/app');
const { reset } = require('../../src/services/reset');
const day2 = require('.');

const PORT = Number(process.env.PORT || 8080);

reset({}).then(() => {
  const server = http.createServer(createApp());
  day2.attachRealtime(server);
  server.listen(PORT, () => console.log(`Dev API (in-memory DB) on http://localhost:${PORT}  ->  /q/m1-live`));
});
