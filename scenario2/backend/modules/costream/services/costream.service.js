'use strict';

const { state, clone } = require('../../../../../src/state');
const { err, validation } = require('../../../../../src/lib/errors');
const { isObj, isStr, isBool } = require('../../../../../src/lib/validate');
const { canonical } = require('../../../../../src/lib/crypto');
const realtime = require('../../../../../src/realtime');
const { signDay2 } = require('../../../shared/signature');
const { MEDIA_HLS_URL } = require('../../../config');

const LAYOUTS = ['solo', 'grid_2', 'grid_4', 'spotlight'];
const MAX_PARTICIPANTS = 4;
const LAYOUT_CAPACITY = { solo: 1, grid_2: 2 };

const sessions = () => state.day2.costream.sessions;

// Step 1 of spec 5.5: schema.
function validate(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!isStr(b.session_id) || !b.session_id) bad.push('session_id');
  if (!isStr(b.host_player_id) || !b.host_player_id) bad.push('host_player_id');
  const p = b.participants;
  if (!Array.isArray(p) || p.length === 0 || !p.every((x) => isStr(x) && x) || new Set(p).size !== p.length) bad.push('participants');
  if (b.simulate_host_drop !== undefined && b.simulate_host_drop !== null && !isBool(b.simulate_host_drop)) bad.push('simulate_host_drop');
  if (b.layout !== undefined && b.layout !== null && !LAYOUTS.includes(b.layout)) bad.push('layout');
  if (bad.length) throw validation(bad);
}

// Step 5: deterministic host-drop handoff.
function evaluate(b, layout) {
  const drop = b.simulate_host_drop === true;
  if (!drop) {
    return { status: 'active', active_host: b.host_player_id, handoff_occurred: false, active_participants: [...b.participants] };
  }
  const remaining = b.participants.filter((p) => p !== b.host_player_id);
  if (remaining.length === 0) return { status: 'terminated', active_host: null, handoff_occurred: false, active_participants: [] };
  return { status: 'active', active_host: remaining[0], handoff_occurred: true, active_participants: remaining };
}

// POST /audit/v1/costream/session (spec 5.5). 201 on create, 200 on an identical replay.
function createSession(b) {
  validate(b);
  const key = canonical(b);
  const prior = sessions().get(b.session_id);
  if (prior && prior.request_key === key) return { status: 200, body: clone(prior.response) };

  // Step 2: every player must exist, and the host must be one of the participants.
  for (const id of [b.host_player_id, ...b.participants]) {
    if (!state.players.has(id)) throw err(404, 'PLAYER_NOT_FOUND', `Player ${id} does not exist.`, { player_id: id });
  }
  if (!b.participants.includes(b.host_player_id)) {
    throw validation(['host_player_id'], 'host_player_id must be one of the participants.');
  }
  // Step 3: capacity.
  if (b.participants.length > MAX_PARTICIPANTS) {
    throw err(409, 'COSTREAM_SESSION_FULL', `A co-stream holds at most ${MAX_PARTICIPANTS} broadcasters.`, { max: MAX_PARTICIPANTS, requested: b.participants.length });
  }
  // Step 4: the layout must fit the participants who are still on air.
  const layout = b.layout || 'grid_4';
  const result = evaluate(b, layout);
  const count = result.active_participants.length;
  if (LAYOUT_CAPACITY[layout] !== undefined && count > LAYOUT_CAPACITY[layout]) {
    throw err(400, 'UNSUPPORTED_LAYOUT', `Layout ${layout} cannot show ${count} participants.`, { layout, participant_count: count });
  }

  const sigPayload = {
    active_host: result.active_host,
    handoff_occurred: result.handoff_occurred,
    layout,
    participant_count: count,
    session_id: b.session_id,
    status: result.status,
  };
  const response = {
    session_id: b.session_id,
    status: result.status,
    active_host: result.active_host,
    handoff_occurred: result.handoff_occurred,
    participant_count: count,
    active_participants: result.active_participants,
    layout,
    // Kept the same through a handoff so viewers never lose the stream or the chat.
    composite_playback_url: `${MEDIA_HLS_URL}/costream/${b.session_id}/index.m3u8`,
    chat_room_id: `chat-${b.session_id}`,
    signature: signDay2(b.session_id, sigPayload),
  };
  sessions().set(b.session_id, { request_key: key, response });
  realtime.publish(`costream:${b.session_id}`, 'costream_updated', response);
  return { status: prior ? 200 : 201, body: clone(response) };
}

const activeSessionCount = () => [...sessions().values()].filter((s) => s.response.status === 'active').length;

module.exports = { createSession, activeSessionCount };
