'use strict';

const { state } = require('../state');
const { pool } = require('../db');
const { nowIso } = require('./validate');

// Platform activity log: every write made through the production API is recorded with who did
// it, what and to which resource. Append-only (persisted to activity_log; newest kept in memory).
const KEEP = 2000;

function record(user, action, target, details = {}) {
  state.idSeq += 1;
  const entry = {
    activity_id: `act-${String(state.idSeq).padStart(5, '0')}`,
    at: nowIso(),
    actor_id: user ? user.user_id : 'system',
    actor_email: user ? user.email : 'system',
    actor_role: user ? user.role : 'system',
    tenant_id: (details && details.tenant_id) || (user && user.tenant_id) || null,
    action,
    target,
    details,
  };
  state.activity.push(entry);
  if (state.activity.length > KEEP) state.activity.splice(0, state.activity.length - KEEP);
  pool.query('INSERT INTO activity_log (activity_id, entry) VALUES ($1, $2)', [entry.activity_id, entry]).catch(() => {});
  return entry;
}

// Next id for records the server names itself, e.g. nextId('prod') -> prod-00012.
function nextId(prefix) {
  state.idSeq += 1;
  return `${prefix}-${String(state.idSeq).padStart(5, '0')}`;
}

module.exports = { record, nextId };
