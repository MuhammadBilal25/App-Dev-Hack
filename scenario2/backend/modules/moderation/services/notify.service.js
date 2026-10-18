'use strict';

const { state } = require('../../../../../src/state');

// FR-5.2 notification bus: each delivery is tried up to 3 times with exponential backoff
// (base, 2x base); after the third failure it goes to the persistent Dead-Letter Queue.
const MAX_ATTEMPTS = 3;

let seq = 0;
const dlq = () => state.day2.moderation.dlq;

function toDlq(event, attempts, error) {
  const entry = {
    event_id: event.event_id || `ntf-${++seq}`,
    type: event.type || 'notification',
    target: event.target || null,
    attempts,
    last_error: error,
    failed_at: new Date().toISOString(),
  };
  dlq().push(entry);
  state.day2.metrics.nascon_dlq_depth = dlq().length;
  return entry;
}

// deliverFn(event) resolves on success and throws on failure.
async function deliver(event, deliverFn, { baseDelayMs = 100 } = {}) {
  let lastError = null;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      await deliverFn(event);
      return { delivered: true, attempts: attempt };
    } catch (e) {
      lastError = e && e.message ? e.message : String(e);
      if (attempt < MAX_ATTEMPTS && baseDelayMs > 0) await new Promise((r) => setTimeout(r, baseDelayMs * 2 ** (attempt - 1)));
    }
  }
  return { delivered: false, attempts: MAX_ATTEMPTS, dlq: toDlq(event, MAX_ATTEMPTS, lastError) };
}

// simulate_dlq / simulate_failed_notifications: the retries are already used up, so the event
// lands in the DLQ synchronously with attempts = 3.
function simulateFailure(type = 'notification') {
  return toDlq({ type }, MAX_ATTEMPTS, 'simulated_delivery_failure');
}

const status = () => ({ queue_depth: dlq().length, undelivered_events: dlq().map((e) => ({ ...e })) });

module.exports = { deliver, simulateFailure, status, MAX_ATTEMPTS };
