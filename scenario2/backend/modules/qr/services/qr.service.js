'use strict';

const QRCode = require('qrcode');
const PDFDocument = require('pdfkit');
const { state } = require('../../../../../src/state');
const { err, validation } = require('../../../../../src/lib/errors');
const { isObj } = require('../../../../../src/lib/validate');
const scoring = require('../../../../../src/services/scoring');
const views = require('../../../../../src/services/views');
const realtime = require('../../../../../src/realtime');
const { signDay2 } = require('../../../shared/signature');
const { PUBLIC_BASE_URL } = require('../../../config');
const { addMapping } = require('../models/qr.model');

const FORMATS = { svg: 'image/svg+xml', png: 'image/png', pdf: 'application/pdf' };
const SCHEDULE_STATUSES = ['postponed', 'cancelled', 'abandoned'];

const store = () => state.day2.qr;

function entityType(id) {
  if (id.startsWith('cs-session-')) return 'costream';
  if (id.startsWith('match-')) return 'match';
  if (id.startsWith('player-')) return 'player';
  if (id.startsWith('club-')) return 'club';
  return null;
}

// Live status of a match at the moment of the scan.
function matchStatus(id) {
  const override = store().statusOverride.get(id);
  if (override) return override;
  const f = views.fixtureMeta(id);
  if (f && f.schedule_status) return f.schedule_status;
  return scoring.project(state.matches.get(id)).status;
}

function entityExists(type, id) {
  if (type === 'match') return state.matches.has(id);
  if (type === 'player') return state.players.has(id);
  if (type === 'club') return state.clubs.has(id);
  if (type === 'costream') return state.day2.costream.sessions.has(id);
  return false;
}

function entityStatus(type, id) {
  if (type === 'match') return matchStatus(id);
  if (type === 'costream') return state.day2.costream.sessions.get(id).response.status;
  return 'active';
}

// Spec 5.6 "Dynamic Target Mutation Rule": the route follows the entity's current state.
function targetRoute(type, id) {
  if (type === 'player') return `/web/players/${id}`;
  if (type === 'club') return `/web/clubs/${id}`;
  if (type === 'costream') return `/web/costream/${id}`;
  const s = matchStatus(id);
  if (s === 'upcoming') return `/web/matches/${id}/preview`;
  if (s === 'in_progress') return `/web/matches/${id}/live`;
  if (s === 'completed') return `/web/matches/${id}/vod`;
  return `/web/matches/${id}/notice?state=${s}`;
}

// The mapping for an entity; any existing match / club / player / co-stream gets one on demand.
function mappingFor(entityId) {
  const known = store().byEntity.get(entityId);
  const type = entityType(entityId);
  if (!type || !entityExists(type, entityId)) {
    throw err(404, 'QR_NOT_FOUND', `No dynamic QR code for ${entityId}.`, { entity_id: entityId });
  }
  return known || addMapping(store(), entityId, entityId, PUBLIC_BASE_URL);
}

const deviceFamily = (ua) => (/mobi|android|iphone|ipad|ipod/i.test(String(ua || '')) ? 'mobile' : 'desktop');

// NFR-9: only the device family and an hourly UTC bucket are kept.
function recordScan(m, userAgent) {
  m.scan_count += 1;
  store().scans.push({ entity_id: m.entity_id, device_family: deviceFamily(userAgent), bucket: new Date().toISOString().slice(0, 13) + ':00Z' });
  state.day2.metrics.nascon_qr_scans_total += 1;
}

// GET /audit/v1/qr/{entity_id}. ?inspect=true reads without counting a scan.
function resolve(entityId, query, userAgent) {
  const m = mappingFor(entityId);
  if (!(query && query.inspect === 'true')) recordScan(m, userAgent);
  const type = entityType(entityId);
  const route = targetRoute(type, entityId);
  const base = `${PUBLIC_BASE_URL}/audit/v1/qr/${entityId}/export`;
  return {
    status: 200,
    body: {
      entity_id: entityId,
      entity_type: type,
      entity_status: entityStatus(type, entityId),
      short_url: m.short_url,
      target_route: route,
      deep_link_uri: `nascon://entity/${entityId}`,
      scan_count: m.scan_count,
      export_formats: { svg: `${base}.svg`, png: `${base}.png`, pdf: `${base}.pdf` },
      signature: signDay2(entityId, { entity_id: entityId, short_url: m.short_url, target_route: route }),
    },
  };
}

function posterPdf(entityId, shortUrl, png) {
  return new Promise((done, fail) => {
    const doc = new PDFDocument({ size: 'A4', margin: 48, info: { Title: `QR ${entityId}` } });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => done(Buffer.concat(chunks)));
    doc.on('error', fail);
    doc.font('Helvetica-Bold').fontSize(24).text('NaSCon 26 - Scan to watch', { align: 'center' });
    doc.moveDown();
    doc.image(png, (doc.page.width - 360) / 2, doc.y, { width: 360 });
    doc.moveDown(20);
    doc.font('Helvetica').fontSize(14).text(entityId, { align: 'center' });
    doc.fontSize(11).text(shortUrl, { align: 'center' });
    doc.end();
  });
}

// GET /audit/v1/qr/{entity_id}/export.{svg|png|pdf} -> { contentType, buffer }
async function exportQr(entityId, fmt) {
  if (!FORMATS[fmt]) throw validation(['fmt'], 'Export format must be svg, png or pdf.');
  const m = mappingFor(entityId);
  let buffer;
  if (fmt === 'svg') buffer = Buffer.from(await QRCode.toString(m.short_url, { type: 'svg', margin: 2 }), 'utf8');
  else {
    const png = await QRCode.toBuffer(m.short_url, { type: 'png', width: 512, margin: 2 });
    buffer = fmt === 'png' ? png : await posterPdf(entityId, m.short_url, png);
  }
  return { contentType: FORMATS[fmt], buffer };
}

// GET /q/{short_code} -> the current Guest Web Player route (sent as 302). Counts a scan.
function redirectTarget(shortCode, userAgent) {
  const entityId = store().byCode.get(shortCode);
  if (!entityId) throw err(404, 'QR_NOT_FOUND', `No dynamic QR code for short code ${shortCode}.`, { short_code: shortCode });
  const m = mappingFor(entityId);
  recordScan(m, userAgent);
  return targetRoute(entityType(entityId), entityId);
}

// Day 2 test helper: POST /audit/v1/matches/{match_id}/status { status }. Lets testers move a
// match to postponed / cancelled / abandoned (completed comes from a match_end event).
function setMatchStatus(matchId, b) {
  if (!state.matches.has(matchId)) throw err(404, 'MATCH_NOT_FOUND', `Match ${matchId} does not exist.`, { match_id: matchId });
  if (!isObj(b) || !(SCHEDULE_STATUSES.includes(b.status) || b.status === null)) throw validation(['status']);
  if (b.status) store().statusOverride.set(matchId, b.status);
  else store().statusOverride.delete(matchId);
  const status = matchStatus(matchId);
  realtime.publish(`match:${matchId}`, 'match_status', { match_id: matchId, status });
  return { status: 200, body: { match_id: matchId, status } };
}

module.exports = { resolve, exportQr, redirectTarget, setMatchStatus, matchStatus, deviceFamily };
