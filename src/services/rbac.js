'use strict';

const { state } = require('../state');
const { err } = require('../lib/errors');
const { authenticate } = require('./auth');

// Policy-as-code (FR-5.1). Each action maps to a predicate over (user, resource). Tenant
// isolation is checked first for every non-super-admin; nothing else is consulted on failure.
const ROLES = ['super_admin', 'league_organizer', 'club_manager', 'player', 'viewer'];

const sameTenant = (u, r) => !!r && u.tenant_id === r.tenant_id;

const POLICIES = {
  'tenant.create': () => false,
  'platform.config.read': () => false,
  'league.fixtures.write': (u, league) => u.role === 'league_organizer' && (u.league_ids || []).includes(league.league_id),
  'club.roster.write': (u, club) => u.role === 'club_manager' && u.club_id === club.club_id,
  // Store management is a separate permission the Super-Admin can withdraw per manager.
  'club.products.write': (u, club) => u.role === 'club_manager' && u.club_id === club.club_id && u.store_access !== false,
  'club.orders.read': (u, club) => u.role === 'club_manager' && u.club_id === club.club_id && u.store_access !== false,
  'club.update': (u, club) => u.role === 'club_manager' && u.club_id === club.club_id,
  'club.history.read': (u, club) => u.role === 'club_manager' && u.club_id === club.club_id,
  // Club creation inside a league follows the Super-Admin's platform setting.
  'club.create': (u, league) =>
    u.role === 'league_organizer' && state.settings.organizer_can_create_clubs === true && (u.league_ids || []).includes(league.league_id),
  // Platform-wide configuration: Super-Admin only (granted before any predicate runs).
  'sport.manage': () => false,
  'league.manage': () => false,
  'user.manage': () => false,
  'tenant.manage': () => false,
  'activity.read': () => false,
  'settings.manage': () => false,
  'store.config.manage': () => false,
  'player.private.read': (u, player) =>
    (u.role === 'club_manager' && u.club_id === player.club_id) || (u.role === 'player' && u.player_id === player.player_id),
  'club.read': () => true, // any role inside the club's tenant
  'player.update': (u, player) =>
    (u.role === 'club_manager' && u.club_id === player.club_id) || (u.role === 'player' && u.player_id === player.player_id),
  'league.read': () => true,
  'match.score.write': (u, league) => u.role === 'league_organizer' && (u.league_ids || []).includes(league.league_id),
  'store.checkout': () => true,
};

function can(user, action, resource) {
  if (user.role === 'super_admin') return true;
  if (resource !== undefined && !sameTenant(user, resource)) return false;
  const p = POLICIES[action];
  return !!p && p(user, resource);
}

function forbid(action) {
  return err(403, 'FORBIDDEN', 'You are not allowed to perform this action.', { action });
}

function lookup(kind, id) {
  const map = { league: state.leagues, club: state.clubs, player: state.players }[kind];
  const r = map.get(id);
  if (!r) throw err(404, `${kind.toUpperCase()}_NOT_FOUND`, `${kind} ${id} does not exist.`, { [`${kind}_id`]: id });
  return r;
}

// Express middleware factory: authenticate -> resolve resource -> authorize.
function guard(action, kind, param) {
  return (req, res, next) => {
    const user = authenticate(req);
    const resource = kind ? lookup(kind, req.params[param]) : undefined;
    if (!can(user, action, resource)) throw forbid(action);
    req.user = user;
    req.resource = resource;
    next();
  };
}

function authorized(req, res) {
  res.status(200).json({ authorized: true });
}

module.exports = { can, guard, authorized, forbid, ROLES, POLICIES };
