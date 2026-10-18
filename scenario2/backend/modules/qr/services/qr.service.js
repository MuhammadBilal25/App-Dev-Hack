'use strict';

const { notImplemented } = require('../../../shared/errors');

// GET /audit/v1/qr/{entity_id} (spec 5.6). ?inspect=true reads without counting a scan.
function resolve(entityId, query, userAgent) {
  // TODO: 404 QR_NOT_FOUND -> live target_route from entity state -> scan telemetry -> signDay2
  throw notImplemented('GET /audit/v1/qr/{entity_id}');
}

// GET /audit/v1/qr/{entity_id}/export.{svg|png|pdf} -> { contentType, buffer }
async function exportQr(entityId, fmt) {
  // TODO: render the short_url as SVG / PNG / PDF poster
  throw notImplemented('GET /audit/v1/qr/{entity_id}/export.{fmt}');
}

// GET /q/{short_code} -> the current Guest Web Player route (sent as 302).
function redirectTarget(shortCode, userAgent) {
  // TODO: look up entity, count the scan, return target_route
  throw notImplemented('GET /q/{short_code}');
}

module.exports = { resolve, exportQr, redirectTarget };
