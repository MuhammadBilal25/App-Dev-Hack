'use strict';

const express = require('express');
const { state, clone } = require('../state');
const { authenticate } = require('../services/auth');
const { can, forbid } = require('../services/rbac');
const platform = require('../services/platform');
const feeds = require('../services/feeds');
const views = require('../services/views');
const merch = require('../services/merch');
const activity = require('../lib/activity');
const { raw } = require('./ops');

// Platform Super-Admin API. Each route names its policy action; the policy layer grants these to
// the Super-Admin only, so every other role gets 403 FORBIDDEN (enforced here, not in the app).

function adminRouter() {
  const r = express.Router();
  const admin = (action) => (req, res, next) => {
    req.user = authenticate(req);
    if (!can(req.user, action)) throw forbid(action);
    next();
  };
  const log = (req, action, target, details = {}) => activity.record(req.user, action, target, details);

  r.get('/dashboard', admin('platform.config.read'), async (req, res) => res.status(200).json(await feeds.adminDashboard()));

  // ---- Sports ----
  r.get('/sports', admin('sport.manage'), (req, res) => res.status(200).json({ sports: platform.listSports(req.user) }));
  r.post('/sports', admin('sport.manage'), (req, res) => {
    const out = platform.createSport(req.body);
    log(req, 'sport.create', out.sport_id, { name: out.name });
    res.status(201).json(out);
  });
  r.patch('/sports/:sportId', admin('sport.manage'), (req, res) => {
    const out = platform.updateSport(req.params.sportId, req.body);
    log(req, 'sport.update', out.sport_id, { fields: Object.keys(req.body || {}), active: out.active });
    res.status(200).json(out);
  });

  // ---- Tenants and branding ----
  r.get('/tenants', admin('tenant.manage'), (req, res) => res.status(200).json({ tenants: [...state.tenants.values()].map(platform.tenantView) }));
  r.post('/tenants', admin('tenant.manage'), (req, res) => {
    const out = platform.createTenant(req.body);
    log(req, 'tenant.create', out.tenant_id, { tenant_id: out.tenant_id });
    res.status(201).json(out);
  });
  r.patch('/tenants/:tenantId', admin('tenant.manage'), (req, res) => {
    const out = platform.updateTenant(req.params.tenantId, req.body);
    log(req, 'tenant.update', out.tenant_id, { tenant_id: out.tenant_id, fields: Object.keys(req.body || {}) });
    res.status(200).json(out);
  });
  r.post('/tenants/:tenantId/logo', admin('tenant.manage'), raw, async (req, res) => {
    const t = platform.tenantOr404(req.params.tenantId);
    const out = await merch.setLogo(t, `tenants/${t.tenant_id}`, req.body, req.headers['content-type']);
    log(req, 'tenant.logo', t.tenant_id, { tenant_id: t.tenant_id });
    res.status(201).json(out);
  });

  // ---- Leagues, organizers and participating clubs ----
  r.get('/leagues', admin('league.manage'), (req, res) => res.status(200).json({ leagues: [...state.leagues.values()].map(views.leagueView) }));
  r.post('/leagues', admin('league.manage'), (req, res) => {
    const out = platform.createLeague(req.body);
    log(req, 'league.create', out.league_id, { tenant_id: out.tenant_id, sport_id: out.sport_id, format: out.format });
    res.status(201).json(out);
  });
  r.patch('/leagues/:leagueId', admin('league.manage'), (req, res) => {
    const out = platform.updateLeague(req.params.leagueId, req.body);
    log(req, 'league.update', out.league_id, { tenant_id: out.tenant_id, fields: Object.keys(req.body || {}) });
    res.status(200).json(out);
  });
  r.post('/leagues/:leagueId/organizers', admin('league.manage'), (req, res) => {
    const out = platform.assignOrganizer(req.params.leagueId, req.body);
    log(req, 'league.organizer.assign', out.league_id, { tenant_id: out.tenant_id, user_id: req.body.user_id });
    res.status(200).json(out);
  });
  r.delete('/leagues/:leagueId/organizers/:userId', admin('league.manage'), (req, res) => {
    const out = platform.unassignOrganizer(req.params.leagueId, req.params.userId);
    log(req, 'league.organizer.unassign', out.league_id, { tenant_id: out.tenant_id, user_id: req.params.userId });
    res.status(200).json(out);
  });
  r.post('/leagues/:leagueId/clubs', admin('league.manage'), (req, res) => {
    const out = platform.addLeagueClub(req.params.leagueId, req.body);
    log(req, 'league.club.add', out.league_id, { tenant_id: out.tenant_id, club_id: req.body.club_id });
    res.status(200).json(out);
  });
  r.delete('/leagues/:leagueId/clubs/:clubId', admin('league.manage'), (req, res) => {
    const out = platform.removeLeagueClub(req.params.leagueId, req.params.clubId);
    log(req, 'league.club.remove', out.league_id, { tenant_id: out.tenant_id, club_id: req.params.clubId });
    res.status(200).json(out);
  });

  // ---- Clubs ----
  r.post('/clubs', admin('league.manage'), (req, res) => {
    const out = platform.createClub(req.body);
    log(req, 'club.create', out.club_id, { tenant_id: out.tenant_id, league_id: out.league_id, name: out.name });
    res.status(201).json(out);
  });

  // ---- Users and roles ----
  r.get('/users', admin('user.manage'), (req, res) => res.status(200).json({ users: platform.listUsers(req.query) }));
  r.post('/users', admin('user.manage'), (req, res) => {
    const out = platform.createUser(req.body);
    log(req, 'user.create', out.user_id, { tenant_id: out.tenant_id, role: out.role, email: out.email });
    res.status(201).json(out);
  });
  r.patch('/users/:userId', admin('user.manage'), (req, res) => {
    const out = platform.updateUser(req.user, req.params.userId, req.body);
    log(req, 'user.update', out.user_id, { tenant_id: out.tenant_id, role: out.role, fields: Object.keys(req.body || {}).filter((k) => k !== 'password') });
    res.status(200).json(out);
  });

  // ---- Settings, store categories, discount codes ----
  r.get('/settings', admin('settings.manage'), (req, res) => res.status(200).json(clone(state.settings)));
  r.patch('/settings', admin('settings.manage'), (req, res) => {
    const out = platform.updateSettings(req.body);
    log(req, 'settings.update', 'platform', { fields: Object.keys(req.body || {}) });
    res.status(200).json(out);
  });
  r.post('/categories', admin('store.config.manage'), (req, res) => {
    const out = platform.createCategory(req.body);
    log(req, 'store.category.create', out.category_id, {});
    res.status(201).json(out);
  });
  r.delete('/categories/:categoryId', admin('store.config.manage'), (req, res) => {
    platform.deleteCategory(req.params.categoryId);
    log(req, 'store.category.delete', req.params.categoryId, {});
    res.status(200).json({ deleted: req.params.categoryId });
  });
  r.get('/discounts', admin('store.config.manage'), (req, res) => res.status(200).json({ discounts: [...state.discounts.values()].map(clone) }));
  r.post('/discounts', admin('store.config.manage'), (req, res) => {
    const out = platform.upsertDiscount(req.body);
    log(req, 'store.discount.upsert', out.code, { percent: out.percent, active: out.active });
    res.status(200).json(out);
  });

  // ---- Activity / audit log ----
  r.get('/activity', admin('activity.read'), (req, res) => {
    const limit = Math.max(1, Math.min(500, Number.parseInt(req.query.limit, 10) || 100));
    const out = state.activity
      .filter((a) => (!req.query.action || a.action.startsWith(req.query.action)) && (!req.query.tenant_id || a.tenant_id === req.query.tenant_id))
      .slice(-limit)
      .reverse();
    res.status(200).json({ activity: clone(out) });
  });

  return r;
}

module.exports = { adminRouter };
