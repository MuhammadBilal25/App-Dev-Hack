'use strict';

const crypto = require('crypto');
const { state } = require('../../../../../src/state');
const { err, validation } = require('../../../../../src/lib/errors');
const { isObj, isStr, isInt, isBool } = require('../../../../../src/lib/validate');
const realtime = require('../../../../../src/realtime');
const auth = require('../../../../../src/services/auth');
const { signDay2 } = require('../../../shared/signature');
const { bearer } = require('../../../shared/guestGuard');
const { maskProfanity, isFlood } = require('./filter.service');
const notify = require('./notify.service');

const RATE_WINDOW_MS = 2000;
const RATE_MAX = 3;
const KEEP_MESSAGES = 500;

function room(id) {
  const rooms = state.day2.moderation.rooms;
  if (!rooms.has(id)) rooms.set(id, { seq: 0, messages: [], kicked: [], muted: [], seen: new Map(), recent: new Map() });
  return rooms.get(id);
}

const addOnce = (list, v) => {
  if (!list.includes(v)) list.push(v);
};

// More than 3 messages from one sender inside a sliding 2 s window.
function overRate(r, sender, now) {
  const times = (r.recent.get(sender) || []).filter((t) => now - t < RATE_WINDOW_MS);
  times.push(now);
  r.recent.set(sender, times);
  return times.length > RATE_MAX;
}

// Moderates one message. The result is remembered per message_id, so a replay (or 10 moderators
// sending the same message at once) always gets the same answer and never duplicates state.
function moderateOne(r, roomId, m, now) {
  if (r.seen.has(m.message_id)) return r.seen.get(m.message_id);
  let result;
  if (isFlood(m.text)) {
    result = { drop: true, mute: true, reason: 'flood_character_repeat' };
  } else if (overRate(r, m.sender, now)) {
    result = { drop: true, mute: true, reason: 'rate_limit_exceeded' };
  } else {
    const masked = maskProfanity(m.text);
    result = {
      drop: false,
      kick: masked.flagged,
      message: { message_id: m.message_id, sender: m.sender, text: masked.text, flagged: masked.flagged, reason: masked.flagged ? 'profanity_leetspeak' : null },
    };
  }
  if (result.mute) addOnce(r.muted, m.sender);
  if (result.kick) addOnce(r.kicked, m.sender);
  if (!result.drop) {
    r.seq += 1;
    result.sequence = r.seq;
    r.messages.push({ ...result.message, sequence: r.seq, sent_at: new Date(now).toISOString() });
    if (r.messages.length > KEEP_MESSAGES) r.messages.splice(0, r.messages.length - KEEP_MESSAGES);
    realtime.publish(`chat:${roomId}`, 'chat_message', { chat_room_id: roomId, sequence: r.seq, ...result.message });
  }
  r.seen.set(m.message_id, result);
  return result;
}

function validate(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!isStr(b.chat_room_id) || !b.chat_room_id) bad.push('chat_room_id');
  if (!Array.isArray(b.incoming_messages) || b.incoming_messages.length > 200) bad.push('incoming_messages');
  else {
    b.incoming_messages.forEach((m, i) => {
      if (!isObj(m) || !isStr(m.message_id) || !m.message_id) bad.push(`incoming_messages[${i}].message_id`);
      if (!isObj(m) || !isStr(m.sender) || !m.sender) bad.push(`incoming_messages[${i}].sender`);
      if (!isObj(m) || !isStr(m.text)) bad.push(`incoming_messages[${i}].text`);
    });
  }
  if (b.check_dlq !== undefined && b.check_dlq !== null && !isBool(b.check_dlq)) bad.push('check_dlq');
  const n = b.simulate_failed_notifications;
  if (n !== undefined && n !== null && !(isInt(n) && n >= 0 && n <= 1000)) bad.push('simulate_failed_notifications');
  if (bad.length) throw validation(bad);
}

// POST /audit/v1/moderation/test (spec 5.8).
function moderate(b) {
  validate(b);
  const r = room(b.chat_room_id);
  const now = Date.now();
  const filtered = [];
  const kicked = [];
  const muted = [];
  for (const m of b.incoming_messages) {
    const res = moderateOne(r, b.chat_room_id, m, now);
    if (res.mute) addOnce(muted, m.sender);
    if (res.kick) addOnce(kicked, m.sender);
    if (!res.drop) filtered.push({ ...res.message });
  }

  for (let i = 0; i < (b.simulate_failed_notifications || 0); i++) notify.simulateFailure('chat_notification');
  const dlq = notify.status();
  const flaggedCount = filtered.filter((m) => m.flagged).length;

  return {
    status: 200,
    body: {
      chat_room_id: b.chat_room_id,
      filtered_messages: filtered,
      kicked_users: kicked,
      muted_users: muted,
      dlq_status: dlq,
      signature: signDay2(b.chat_room_id, { chat_room_id: b.chat_room_id, flagged_count: flaggedCount, kicked_users: kicked, queue_depth: dlq.queue_depth }),
    },
  };
}

// POST /api/v1/chat { chat_room_id, text }: members only. Guests (guest_ token or no token at
// all) are refused with 403 GUEST_WRITE_FORBIDDEN (FR-4.3); the guard catches guest_ tokens.
function postChat(req) {
  if (!bearer(req)) {
    throw err(403, 'GUEST_WRITE_FORBIDDEN', 'Anonymous guests cannot post chat messages.', { guest_token: null });
  }
  const user = auth.authenticate(req);
  const b = req.body;
  const bad = [];
  if (!isObj(b) || !isStr(b.chat_room_id) || !b.chat_room_id) bad.push('chat_room_id');
  if (!isObj(b) || !isStr(b.text) || !b.text.trim() || b.text.length > 500) bad.push('text');
  if (bad.length) throw validation(bad);
  const r = room(b.chat_room_id);
  if (r.kicked.includes(user.user_id) || r.muted.includes(user.user_id)) {
    throw err(403, 'FORBIDDEN', 'You have been removed from this chat.', { chat_room_id: b.chat_room_id });
  }
  const messageId = isStr(b.message_id) && b.message_id ? b.message_id : `msg-${crypto.randomUUID()}`;
  const res = moderateOne(r, b.chat_room_id, { message_id: messageId, sender: user.user_id, text: b.text }, Date.now());
  if (res.drop && res.reason === 'rate_limit_exceeded') {
    throw err(429, 'RATE_LIMITED', 'Too many messages. Slow down.', { chat_room_id: b.chat_room_id });
  }
  return {
    status: 201,
    body: { accepted: !res.drop, reason: res.drop ? res.reason : (res.message.reason || null), sequence: res.sequence || null, message: res.drop ? null : res.message },
  };
}

// GET /api/v1/chat/{chat_room_id}: recent messages (read-only, guests allowed).
function history(roomId) {
  return { status: 200, body: { chat_room_id: roomId, messages: room(roomId).messages.slice(-100) } };
}

module.exports = { moderate, postChat, history };
