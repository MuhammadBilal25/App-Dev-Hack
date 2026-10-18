'use strict';

const express = require('express');
const { state } = require('../state');
const { err } = require('../lib/errors');
const { authenticate } = require('../services/auth');
const { can, forbid } = require('../services/rbac');
const roster = require('../services/roster');
const offlineSync = require('../services/offlineSync');
const schedule = require('../services/schedule');
const views = require('../services/views');
const feeds = require('../services/feeds');
const platform = require('../services/platform');
const merch = require('../services/merch');
const matchOps = require('../services/matchOps');
const activity = require('../lib/activity');

// Authenticated writes for League Organizers and Club Managers: scoring, match status and
// scheduling, fixture generation, roster moves, offline sync, club profile, and role dashboards.
// Every route authorizes against the RBAC policy layer before touching domain state.

const raw = express.raw({ type: () => true, limit: '6mb' });

function opsRouter() {
  const r = express.Router();
  const auth = (req, res, next) => {
    req.user = authenticate(req);
    next();
  };

  const league = (req, action) => {
    const l = state.leagues.get(req.params.leagueId);
    if (!l) throw err(404, 'LEAGUE_NOT_FOUND', `League ${req.params.leagueId} does not exist.`, { league_id: req.params.leagueId });
    if (!can(req.user, action, l)) throw forbid(action);
    return l;
  };

  const fixtureLeague = (req, action) => {
    const f = views.fixtureOr404(req.params.matchId);
    const l = state.leagues.get(f.league_id);
    if (!can(req.user, action, l)) throw forbid(action);
    return { f, l };
  };

  // ---- Scoring and match control ----
  r.post('/matches/:matchId/events', auth, (req, res) => {
    const out = matchOps.appendEvent(req.user, req.params.matchId, req.body);
    if (out.status === 201) {
      activity.record(req.user, `match.event.${out.body.type}`, req.params.matchId, { league_id: out.body.fixture.league_id, event_id: out.body.event_id });
    }
    res.status(out.status).json(out.body);
  });

  r.post('/matches/:matchId/status', auth, (req, res) => {
    const { f, l } = fixtureLeague(req, 'league.fixtures.write');
    const out = schedule.setStatus(f, req.body);
    activity.record(req.user, 'match.status', f.match_id, { league_id: l.league_id, tenant_id: l.tenant_id, from: out.from, to: out.to, reason: (req.body && req.body.reason) || null });
    res.status(200).json(out);
  });

  r.post('/matches/:matchId/reschedule', auth, (req, res) => {
    const { f, l } = fixtureLeague(req, 'league.fixtures.write');
    const out = schedule.reschedule(f, req.body);
    activity.record(req.user, 'match.reschedule', f.match_id, { league_id: l.league_id, tenant_id: l.tenant_id, before: out.before, kickoff_at: f.kickoff_at, venue: f.venue });
    res.status(200).json(out.fixture);
  });

  r.post('/matches/:matchId/pin', auth, async (req, res) => {
    const out = await matchOps.pinProduct(req.user, req.params.matchId, req.body);
    activity.record(req.user, 'match.pin_product', req.params.matchId, { product_id: out.pinned_product ? out.pinned_product.product_id : null });
    res.status(200).json(out);
  });

  // ---- Fixture generation ----
  r.post('/leagues/:leagueId/fixtures/generate', auth, (req, res) => {
    const l = league(req, 'league.fixtures.write');
    const out = schedule.generate(l, req.body || {});
    activity.record(req.user, 'league.fixtures.generate', l.league_id, { league_id: l.league_id, tenant_id: l.tenant_id, format: out.format, fixtures: out.fixtures.length });
    res.status(201).json(out);
  });

  r.post('/leagues/:leagueId/swiss/next-round', auth, (req, res) => {
    const l = league(req, 'league.fixtures.write');
    const out = schedule.nextSwissRound(l);
    activity.record(req.user, 'league.swiss.next_round', l.league_id, { league_id: l.league_id, tenant_id: l.tenant_id, round: out.round });
    res.status(201).json(out);
  });

  // Organizers may add clubs to their own leagues when the Super-Admin allows it.
  r.post('/leagues/:leagueId/clubs', auth, (req, res) => {
    const l = league(req, 'club.create');
    const out = platform.createClub({ ...(req.body || {}), league_id: l.league_id }, { tenantId: l.tenant_id });
    activity.record(req.user, 'club.create', out.club_id, { league_id: l.league_id, tenant_id: l.tenant_id, name: out.name });
    res.status(201).json(out);
  });

  // ---- Roster ----
  r.post('/roster/transfer', auth, (req, res) => {
    const b = req.body || {};
    const squad = state.rosterSquads.get(b.from_squad_id);
    const club = squad ? state.clubs.get(squad.club_id) || { club_id: squad.club_id, tenant_id: squad.tenant_id } : null;
    if (club && !can(req.user, 'club.roster.write', club)) throw forbid('club.roster.write');
    if (!club && req.user.role !== 'super_admin' && req.user.role !== 'club_manager') throw forbid('club.roster.write');
    const to = state.rosterSquads.get(b.to_squad_id);
    if (b.type !== 'release' && to && to.league_id !== b.league_id) {
      throw err(409, 'CROSS_LEAGUE_TRANSFER', 'Players can only move between clubs of the same league.', { to_squad_id: b.to_squad_id, league_id: b.league_id });
    }
    const out = roster.transfer({ ...b, requested_by: b.requested_by || req.user.email });
    if (out.status === 201) {
      activity.record(req.user, `roster.${b.type}`, b.player_id, { club_id: b.from_squad_id, to_club_id: b.to_squad_id || null, tenant_id: club ? club.tenant_id : null });
    }
    res.status(out.status).json(out.body);
  });

  r.post('/sync', auth, (req, res) => {
    const out = offlineSync.sync(req.body, { authorize: matchOps.syncAuthorizer(req.user) });
    if (out.body.summary.applied) activity.record(req.user, 'offline.sync', out.body.device_id, { ...out.body.summary });
    res.status(out.status).json(out.body);
  });

  // ---- Club profile ----
  const clubFor = (req, action) => {
    const c = state.clubs.get(req.params.clubId);
    if (!c) throw err(404, 'CLUB_NOT_FOUND', `Club ${req.params.clubId} does not exist.`, { club_id: req.params.clubId });
    if (!can(req.user, action, c)) throw forbid(action);
    return c;
  };

  r.patch('/clubs/:clubId', auth, (req, res) => {
    const c = clubFor(req, 'club.update');
    const out = platform.updateClub(c, req.body, { admin: req.user.role === 'super_admin' });
    activity.record(req.user, 'club.update', c.club_id, { tenant_id: c.tenant_id, fields: Object.keys(req.body || {}) });
    res.status(200).json(out);
  });

  r.post('/clubs/:clubId/logo', auth, raw, async (req, res) => {
    const c = clubFor(req, 'club.update');
    const out = await merch.setLogo(c, `clubs/${c.club_id}`, req.body, req.headers['content-type']);
    activity.record(req.user, 'club.logo', c.club_id, { tenant_id: c.tenant_id });
    res.status(201).json(out);
  });

  // ---- Dashboards ----
  r.get('/dashboard/organizer', auth, (req, res) => {
    if (!['league_organizer', 'super_admin'].includes(req.user.role)) throw forbid('dashboard.organizer');
    res.status(200).json(feeds.organizerDashboard(req.user));
  });

  r.get('/dashboard/manager', auth, async (req, res) => {
    if (req.user.role !== 'club_manager') throw forbid('dashboard.manager');
    res.status(200).json(await feeds.managerDashboard(req.user));
  });

  return r;
}

module.exports = { opsRouter, raw };
