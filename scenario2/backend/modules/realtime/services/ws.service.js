'use strict';

const { WebSocketServer } = require('ws');
const { state } = require('../../../../../src/state');
const realtime = require('../../../../../src/realtime');
const scoring = require('../../../../../src/services/scoring');
const { createStore } = require('../models/connections.model');

// NFR-1: ws://localhost:8080/ws/matches/{match_id}. Score events are pushed the moment
// /audit/v1/events commits them (same publish call that feeds SSE), so delivery is ~1 ms locally.
// Also: /ws/chat/{chat_room_id} and /ws/costream/{session_id}.
const ROUTES = [
  [/^\/ws\/matches\/([^/?#]+)\/?$/, (id) => `match:${id}`],
  [/^\/ws\/chat\/([^/?#]+)\/?$/, (id) => `chat:${id}`],
  [/^\/ws\/costream\/([^/?#]+)\/?$/, (id) => `costream:${id}`],
];

// Lives outside state.day2 so open sockets survive POST /audit/v1/reset.
const conns = createStore();
const wss = new WebSocketServer({ noServer: true });

function scoreFrame(matchId) {
  const m = state.matches.get(matchId);
  if (!m) return null;
  const p = scoring.project(m);
  return { type: 'score', match_id: matchId, status: p.status, home: p.home.score, away: p.away.score, score_text: `${p.home.score} - ${p.away.score}`, version: p.version };
}

function channelFor(pathname) {
  for (const [re, fn] of ROUTES) {
    const m = re.exec(pathname);
    if (m) return fn(decodeURIComponent(m[1]));
  }
  return null;
}

function count() {
  let n = 0;
  for (const set of conns.byMatch.values()) n += set.size;
  return n;
}

function send(ws, frame) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(frame));
}

function onConnection(ws, channel) {
  if (!conns.byMatch.has(channel)) conns.byMatch.set(channel, new Set());
  conns.byMatch.get(channel).add(ws);
  ws.on('close', () => conns.byMatch.get(channel).delete(ws));
  ws.on('error', () => {});
  if (channel.startsWith('match:')) {
    const snap = scoreFrame(channel.slice('match:'.length));
    if (snap) send(ws, { ...snap, type: 'score_snapshot' });
  }
}

// Every published event goes to the sockets on its channel; match events carry the new score.
function forward(channel, type, data) {
  const set = conns.byMatch.get(channel);
  if (!set || set.size === 0) return;
  let frame = { channel, type, data };
  if (channel.startsWith('match:')) {
    const snap = scoreFrame(channel.slice('match:'.length));
    if (snap) frame = { ...snap, channel, event_type: type, data };
  }
  const text = JSON.stringify(frame);
  for (const ws of set) if (ws.readyState === ws.OPEN) ws.send(text);
}

let attached = false;
function attach(server) {
  if (!attached) {
    realtime.onPublish(forward);
    attached = true;
  }
  server.on('upgrade', (req, socket, head) => {
    const channel = channelFor(new URL(req.url, 'http://localhost').pathname);
    if (!channel) {
      socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => onConnection(ws, channel));
  });
}

module.exports = { attach, count };
