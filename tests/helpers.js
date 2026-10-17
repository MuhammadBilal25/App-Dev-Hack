'use strict';

// Test harness: the API runs in-process on a random port; PostgreSQL is replaced by a tiny
// in-memory fake that understands the handful of statements the services issue.
process.env.DAY1_SALT = process.env.DAY1_SALT || 'demo-salt';
process.env.JWT_SECRET = 'test-secret';
delete process.env.REDIS_URL;

const db = require('../src/db');

const inventory = new Map();
// `journal` (per client) records reservations so ROLLBACK can undo them like PostgreSQL does.
function fakeQuery(sql, params = [], journal = null) {
  const s = sql.replace(/\s+/g, ' ').trim();
  if (s === 'BEGIN' && journal) journal.length = 0;
  else if (s === 'ROLLBACK' && journal) {
    for (const [id, q] of journal.splice(0)) {
      inventory.get(id).stock += q;
      inventory.get(id).reserved -= q;
    }
  } else if (s.startsWith('TRUNCATE')) inventory.clear();
  else if (s.startsWith('INSERT INTO inventory')) inventory.set(params[0], { stock: params[1], reserved: params[2] ?? 0 });
  else if (s.startsWith('UPDATE inventory SET stock = stock - $2')) {
    const row = inventory.get(params[0]);
    if (!row || row.stock < params[1]) return { rowCount: 0, rows: [] };
    row.stock -= params[1];
    row.reserved += params[1];
    if (journal) journal.push([params[0], params[1]]);
    return { rowCount: 1, rows: [] };
  } else if (s.startsWith('UPDATE inventory SET stock = stock + $2')) {
    const row = inventory.get(params[0]);
    row.stock += params[1];
    row.reserved -= params[1];
  } else if (s.startsWith('UPDATE inventory SET reserved = reserved - $2')) {
    inventory.get(params[0]).reserved -= params[1];
  } else if (s.startsWith('SELECT stock, reserved')) {
    const row = inventory.get(params[0]);
    return { rowCount: row ? 1 : 0, rows: row ? [{ ...row }] : [] };
  }
  return { rowCount: 1, rows: [] };
}
db.pool.query = async (sql, params) => fakeQuery(sql, params);
db.pool.connect = async () => {
  const journal = [];
  return { query: async (sql, params) => fakeQuery(sql, params, journal), release() {} };
};

const { createApp } = require('../src/app');
const { reset } = require('../src/services/reset');

let server;
let base;

async function start() {
  if (server) return;
  await reset({});
  await new Promise((resolve) => {
    server = createApp().listen(0, '127.0.0.1', () => {
      base = `http://127.0.0.1:${server.address().port}`;
      resolve();
    });
  });
}

async function stop() {
  if (server) await new Promise((r) => server.close(r));
  server = null;
}

async function call(method, path, body, headers = {}) {
  const r = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
  });
  const text = await r.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    json = text;
  }
  return { status: r.status, body: json, headers: r.headers };
}

let seq = 0;
const ev = (matchId, type, payload, eventId) => call('POST', '/audit/v1/events', { event_id: eventId || `ev-${++seq}`, match_id: matchId, type, payload });

async function playFootball(matchId, home, away, hg, ag, goalIds = []) {
  await ev(matchId, 'match_start', {});
  for (let i = 0; i < hg; i++) await ev(matchId, 'score', { team_id: home, event_type: 'goal' }, goalIds[i]);
  for (let i = 0; i < ag; i++) await ev(matchId, 'score', { team_id: away, event_type: 'goal' });
  return ev(matchId, 'match_end', {});
}

module.exports = { start, stop, call, ev, playFootball };
