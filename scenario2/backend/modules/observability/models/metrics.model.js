'use strict';

// Gauges/counters exported on GET /metrics (NFR-6).
function createStore() {
  return {
    nascon_active_ws_connections: 0,
    nascon_active_streams_total: 0,
    nascon_stream_bitrate_kbps: 0,
    nascon_dlq_depth: 0,
    nascon_qr_scans_total: 0,
  };
}

module.exports = { createStore };
