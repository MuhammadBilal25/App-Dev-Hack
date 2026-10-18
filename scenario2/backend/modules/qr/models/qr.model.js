'use strict';

// Dynamic QR mappings. byEntity: entity_id -> { entity_id, short_code, short_url, scan_count }
// byCode: short_code -> entity_id. scans: privacy-safe telemetry (device family + UTC bucket only).
function createStore() {
  return { byEntity: new Map(), byCode: new Map(), scans: [] };
}

function addMapping(store, entityId, shortCode, baseUrl) {
  const m = { entity_id: entityId, short_code: shortCode, short_url: `${baseUrl}/q/${shortCode}`, scan_count: 0 };
  store.byEntity.set(entityId, m);
  store.byCode.set(shortCode, entityId);
  return m;
}

module.exports = { createStore, addMapping };
