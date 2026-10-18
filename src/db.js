'use strict';

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://nascon:nascon@localhost:5432/nascon',
  max: 30,
});

// Append-only tables (events, audit_log, domain_events) are never UPDATEd by the domain code.
const SCHEMA = `
CREATE TABLE IF NOT EXISTS inventory (
  variant_id TEXT PRIMARY KEY,
  stock      INTEGER NOT NULL CHECK (stock >= 0),
  reserved   INTEGER NOT NULL DEFAULT 0 CHECK (reserved >= 0)
);
CREATE TABLE IF NOT EXISTS orders (
  order_id    TEXT PRIMARY KEY,
  request     JSONB NOT NULL,
  status      TEXT NOT NULL,
  http_status INTEGER NOT NULL,
  response    JSONB NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS match_events (
  event_id   TEXT PRIMARY KEY,
  match_id   TEXT NOT NULL,
  sequence   INTEGER NOT NULL,
  type       TEXT NOT NULL,
  payload    JSONB NOT NULL,
  signature  TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (match_id, sequence)
);
CREATE TABLE IF NOT EXISTS audit_log (
  audit_id   TEXT PRIMARY KEY,
  player_id  TEXT NOT NULL,
  entry      JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS activity_log (
  activity_id TEXT PRIMARY KEY,
  entry       JSONB NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS domain_events (
  id         BIGSERIAL PRIMARY KEY,
  topic      TEXT NOT NULL,
  body       JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
`;

async function waitForDb(retries = 60) {
  for (let i = 0; ; i++) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch (e) {
      if (i >= retries) throw e;
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
}

async function migrate() {
  await pool.query(SCHEMA);
}

async function ping() {
  try {
    await pool.query('SELECT 1');
    return true;
  } catch {
    return false;
  }
}

module.exports = { pool, waitForDb, migrate, ping };
