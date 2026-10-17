'use strict';

const { state, clone } = require('../state');
const { pool } = require('../db');
const { err, validation } = require('../lib/errors');
const { canonical } = require('../lib/crypto');
const { isObj, isStr, isId, isDate, addDays, today, nowIso, isInt } = require('../lib/validate');
const { getSport } = require('./sports');

const ROLES = ['captain', 'vice_captain', 'starter', 'substitute'];
const TYPES = ['transfer', 'loan', 'release'];

// ---------------------------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------------------------
function validateSetup(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  const l = b.league;
  if (!isObj(l)) bad.push('league');
  else {
    if (!isId(l.league_id)) bad.push('league.league_id');
    if (!isId(l.tenant_id)) bad.push('league.tenant_id');
    if (!isStr(l.sport_id) || !l.sport_id) bad.push('league.sport_id');
    const w = l.transfer_window;
    if (!isObj(w) || !isDate(w.open) || !isDate(w.close) || w.open > w.close) bad.push('league.transfer_window');
    if (l.max_squad_size !== undefined && l.max_squad_size !== null && !(isInt(l.max_squad_size) && l.max_squad_size >= 1)) bad.push('league.max_squad_size');
    if (l.required_positions !== undefined && l.required_positions !== null &&
      (!isObj(l.required_positions) || !Object.values(l.required_positions).every((n) => isInt(n) && n >= 0))) bad.push('league.required_positions');
  }
  const squads = Array.isArray(b.squads) ? b.squads : null;
  if (!squads || !squads.every((s) => isObj(s) && isId(s.squad_id) && isId(s.club_id) && isId(s.tenant_id)) ||
    new Set(squads.map((s) => s.squad_id)).size !== squads.length) bad.push('squads');
  const ids = new Set((squads || []).map((s) => s && s.squad_id));
  const players = Array.isArray(b.players) ? b.players : null;
  if (!players || !players.every((p) => isObj(p) && isId(p.player_id) && isStr(p.position) && (p.squad_id === null || ids.has(p.squad_id)) &&
    (p.role === undefined || ROLES.includes(p.role))) || new Set(players.map((p) => p.player_id)).size !== players.length) bad.push('players');
  const mip = b.matches_in_progress;
  if (mip !== undefined && mip !== null &&
    (!Array.isArray(mip) || !mip.every((m) => isObj(m) && isId(m.match_id) && isStr(m.home_squad_id) && isStr(m.away_squad_id)))) bad.push('matches_in_progress');
  if (bad.length) throw validation(bad);
}

function dropLeague(leagueId) {
  const old = state.rosterLeagues.get(leagueId);
  if (!old) return;
  for (const sid of old.squad_ids) state.rosterSquads.delete(sid);
  for (const [pid, p] of state.rosterPlayers) if (p.league_id === leagueId) state.rosterPlayers.delete(pid);
  for (const [rid, r] of state.transferRequests) if (r.league_id === leagueId) state.transferRequests.delete(rid);
}

function setup(b) {
  validateSetup(b);
  const l = b.league;
  const sport = getSport(l.sport_id);
  dropLeague(l.league_id);

  const league = {
    league_id: l.league_id,
    tenant_id: l.tenant_id,
    sport_id: sport.sport_id,
    transfer_window: { open: l.transfer_window.open, close: l.transfer_window.close },
    max_squad_size: isInt(l.max_squad_size) ? l.max_squad_size : sport.roster.max_squad_size,
    required_positions: clone(isObj(l.required_positions) ? l.required_positions : sport.roster.required_positions),
    matches_in_progress: clone(b.matches_in_progress || []),
    squad_ids: b.squads.map((s) => s.squad_id),
  };
  state.rosterLeagues.set(league.league_id, league);
  for (const s of b.squads) state.rosterSquads.set(s.squad_id, { ...clone(s), league_id: league.league_id });
  for (const p of b.players) {
    state.rosterPlayers.set(p.player_id, {
      player_id: p.player_id,
      name: p.name || p.player_id,
      position: p.position,
      league_id: league.league_id,
      role: p.role || 'substitute',
      // Membership timeline: segments ordered by application; each starts on `from` (inclusive).
      segments: [{ from: '0000-01-01', squad_id: p.squad_id, parent_squad_id: null }],
      loan: null, // { lender, borrower, end, returned }
      audit: [],
    });
  }
  const counts = {};
  for (const s of b.squads) counts[s.squad_id] = squadMembers(s.squad_id).length;
  return { status: 201, body: { league_id: league.league_id, status: 'configured', squad_counts: counts } };
}

// ---------------------------------------------------------------------------------------------
// Membership helpers
// ---------------------------------------------------------------------------------------------
const latest = (p) => p.segments[p.segments.length - 1];

function segmentAt(p, date) {
  let seg = p.segments[0];
  for (const s of p.segments) if (s.from <= date) seg = s;
  return seg;
}

function squadMembers(squadId) {
  return [...state.rosterPlayers.values()].filter((p) => latest(p).squad_id === squadId);
}

function nextAuditId() {
  state.auditSeq += 1;
  return `au-${String(state.auditSeq).padStart(4, '0')}`;
}

function appendAudit(p, entry) {
  p.audit.push(entry);
  pool.query('INSERT INTO audit_log (audit_id, player_id, entry) VALUES ($1,$2,$3)', [entry.audit_id, p.player_id, entry]).catch(() => {});
}

// Writes the automatic loan_return entry once, when `date` is past the loan end.
function settleLoan(p, date) {
  const loan = p.loan;
  if (!loan || loan.returned) return;
  const back = addDays(loan.end, 1);
  if (date < back) return;
  loan.returned = true;
  p.role = 'substitute';
  p.segments.push({ from: back, squad_id: loan.lender, parent_squad_id: null });
  appendAudit(p, {
    audit_id: nextAuditId(),
    action: 'loan_return',
    player_id: p.player_id,
    league_id: p.league_id,
    from_squad_id: loan.borrower,
    to_squad_id: loan.lender,
    effective_date: back,
    state: 'active',
    who: 'system',
    when: nowIso(),
    why: 'Loan period ended',
  });
}

const playerVersion = (playerId) => {
  const p = state.rosterPlayers.get(playerId);
  return p ? p.audit.length : 0;
};

// ---------------------------------------------------------------------------------------------
// Transfer / loan / release
// ---------------------------------------------------------------------------------------------
function validateTransfer(b) {
  if (!isObj(b)) throw validation(['body']);
  const bad = [];
  if (!isId(b.request_id)) bad.push('request_id');
  if (!isId(b.league_id)) bad.push('league_id');
  if (!isId(b.player_id)) bad.push('player_id');
  if (!TYPES.includes(b.type)) bad.push('type');
  if (!isId(b.from_squad_id)) bad.push('from_squad_id');
  if (b.type === 'release') {
    if (b.to_squad_id !== undefined && b.to_squad_id !== null && !isId(b.to_squad_id)) bad.push('to_squad_id');
  } else if (!isId(b.to_squad_id) || b.to_squad_id === b.from_squad_id) bad.push('to_squad_id');
  if (!isDate(b.effective_date)) bad.push('effective_date');
  if (b.type === 'loan') {
    if (!isDate(b.loan_end_date) || (isDate(b.effective_date) && b.loan_end_date <= b.effective_date)) bad.push('loan_end_date');
  } else if (b.loan_end_date !== undefined && b.loan_end_date !== null && !isDate(b.loan_end_date)) bad.push('loan_end_date');
  if (b.reason !== undefined && b.reason !== null && !isStr(b.reason)) bad.push('reason');
  if (b.requested_by !== undefined && b.requested_by !== null && !isStr(b.requested_by)) bad.push('requested_by');
  if (bad.length) throw validation(bad);
}

function squadOr404(id) {
  const s = state.rosterSquads.get(id);
  if (!s) throw err(404, 'SQUAD_NOT_FOUND', `Squad ${id} does not exist.`, { squad_id: id });
  return s;
}

// Runs rule checks 2..8 of Section 5.11 in order. Mutates nothing except settling an expired loan.
function checkTransfer(b) {
  const league = state.rosterLeagues.get(b.league_id);
  if (!league) throw err(404, 'LEAGUE_NOT_FOUND', `League ${b.league_id} does not exist.`, { league_id: b.league_id });
  const p = state.rosterPlayers.get(b.player_id);
  if (!p) throw err(404, 'PLAYER_NOT_FOUND', `Player ${b.player_id} does not exist.`, { player_id: b.player_id });
  const from = squadOr404(b.from_squad_id);
  const to = b.type === 'release' ? null : squadOr404(b.to_squad_id);

  if (from.tenant_id !== league.tenant_id || (to && to.tenant_id !== league.tenant_id)) {
    throw err(409, 'CROSS_TENANT_TRANSFER', 'Both squads must belong to the league tenant.', {
      league_id: league.league_id, from_squad_id: from.squad_id, to_squad_id: to ? to.squad_id : null,
    });
  }

  settleLoan(p, b.effective_date);
  const current = p.league_id === league.league_id ? latest(p).squad_id : null;
  if (current !== from.squad_id || from.league_id !== league.league_id) {
    throw err(409, 'NOT_IN_SQUAD', `Player ${p.player_id} is not in squad ${from.squad_id}.`, { player_id: p.player_id, squad_id: from.squad_id, current_squad_id: current });
  }

  if (b.type !== 'release') {
    const w = league.transfer_window;
    if (b.effective_date < w.open || b.effective_date > w.close) {
      throw err(409, 'TRANSFER_WINDOW_CLOSED', 'The transfer window is closed on that date.', { effective_date: b.effective_date, window: w });
    }
  }

  if (p.loan && !p.loan.returned) {
    throw err(409, 'PLAYER_ON_LOAN', `Player ${p.player_id} is currently on loan.`, { player_id: p.player_id, parent_squad_id: p.loan.lender });
  }

  if (to && squadMembers(to.squad_id).length + 1 > league.max_squad_size) {
    throw err(409, 'SQUAD_FULL', `Squad ${to.squad_id} is full.`, { squad_id: to.squad_id, max_squad_size: league.max_squad_size });
  }

  const need = league.required_positions[p.position];
  if (isInt(need) && need > 0) {
    const remaining = squadMembers(from.squad_id).filter((x) => x.position === p.position && x.player_id !== p.player_id).length;
    if (remaining < need) {
      throw err(409, 'MIN_POSITION_VIOLATION', `Squad ${from.squad_id} needs at least ${need} ${p.position}.`, {
        squad_id: from.squad_id, position: p.position, required: need, remaining,
      });
    }
  }
  return { league, p, from, to };
}

function applyTransfer(b, { league, p, from, to }) {
  const blocking = league.matches_in_progress.find((m) => m.home_squad_id === from.squad_id || m.away_squad_id === from.squad_id);
  const st = blocking ? 'deferred_until_match_end' : 'active';

  p.role = 'substitute';
  if (b.type === 'transfer') p.segments.push({ from: b.effective_date, squad_id: to.squad_id, parent_squad_id: null });
  else if (b.type === 'loan') {
    p.segments.push({ from: b.effective_date, squad_id: to.squad_id, parent_squad_id: from.squad_id });
    p.loan = { lender: from.squad_id, borrower: to.squad_id, end: b.loan_end_date, returned: false };
  } else p.segments.push({ from: b.effective_date, squad_id: null, parent_squad_id: null });

  const entry = {
    audit_id: nextAuditId(),
    action: b.type,
    player_id: p.player_id,
    league_id: league.league_id,
    from_squad_id: from.squad_id,
    to_squad_id: to ? to.squad_id : null,
    effective_date: b.effective_date,
    state: st,
    who: b.requested_by || 'unknown',
    when: nowIso(),
    why: b.reason || '',
  };
  appendAudit(p, entry);

  const registration = b.type === 'release' ? null : {
    player_id: p.player_id,
    league_id: league.league_id,
    squad_id: to.squad_id,
    parent_squad_id: b.type === 'loan' ? from.squad_id : null,
    registration_type: b.type,
    start_date: b.effective_date,
    loan_end_date: b.type === 'loan' ? b.loan_end_date : null,
    role: 'substitute',
  };
  const body = {
    request_id: b.request_id,
    status: 'accepted',
    state: st,
    blocking_match_id: blocking ? blocking.match_id : null,
    registration,
    audit_entry: clone(entry),
  };
  state.transferRequests.set(b.request_id, { key: canonical(b), body, league_id: league.league_id });
  return body;
}

function checkTransferReplay(b) {
  const prior = state.transferRequests.get(b.request_id);
  if (!prior) return null;
  if (prior.key === canonical(b)) return prior.body;
  throw err(409, 'DUPLICATE_REQUEST_ID', `Request ${b.request_id} was already used with a different body.`, { request_id: b.request_id });
}

function transfer(b) {
  validateTransfer(b);
  const replay = checkTransferReplay(b);
  if (replay) return { status: 200, body: clone(replay) };
  return { status: 201, body: clone(applyTransfer(b, checkTransfer(b))) };
}

function history(playerId, asOf) {
  if (asOf !== undefined && !isDate(asOf)) throw validation(['as_of']);
  const date = asOf || today();
  const p = state.rosterPlayers.get(playerId);
  if (!p) throw err(404, 'PLAYER_NOT_FOUND', `Player ${playerId} does not exist.`, { player_id: playerId });
  settleLoan(p, date);
  const seg = segmentAt(p, date);
  return {
    player_id: p.player_id,
    as_of: date,
    league_id: p.league_id,
    current_squad_id: seg.squad_id,
    parent_squad_id: seg.parent_squad_id,
    history: clone(p.audit),
  };
}

module.exports = { setup, transfer, history, validateTransfer, checkTransfer, applyTransfer, checkTransferReplay, playerVersion, squadMembers };
