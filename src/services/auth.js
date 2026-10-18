'use strict';

const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { state } = require('../state');
const { DEMO_PASSWORD } = require('../seed');
const { err } = require('../lib/errors');
const { isObj, isStr } = require('../lib/validate');

const SECRET = process.env.JWT_SECRET || crypto.randomBytes(32).toString('hex');
const TTL_SECONDS = 2 * 60 * 60;

// Demo users share one password; its scrypt hash is computed once at startup.
const PW_SALT = crypto.randomBytes(16);
const DEMO_HASH = crypto.scryptSync(DEMO_PASSWORD, PW_SALT, 32);

function passwordMatches(pw) {
  const h = crypto.scryptSync(String(pw), PW_SALT, 32);
  return crypto.timingSafeEqual(h, DEMO_HASH);
}

// Accounts created through the admin API get their own salt and scrypt hash.
function hashPassword(pw) {
  const salt = crypto.randomBytes(16);
  return { salt: salt.toString('hex'), hash: crypto.scryptSync(String(pw), salt, 32).toString('hex') };
}

function userPasswordMatches(user, pw) {
  if (!user.password) return passwordMatches(pw);
  const h = crypto.scryptSync(String(pw), Buffer.from(user.password.salt, 'hex'), 32);
  return crypto.timingSafeEqual(h, Buffer.from(user.password.hash, 'hex'));
}

function issueToken(user) {
  return jwt.sign({ sub: user.user_id, email: user.email, role: user.role, tenant_id: user.tenant_id }, SECRET, {
    algorithm: 'HS256',
    expiresIn: TTL_SECONDS,
  });
}

const unauth = (msg) => err(401, 'UNAUTHENTICATED', msg);

// Verifies the signature with a pinned algorithm: alg:none, tampered and expired tokens fail.
function authenticate(req) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(\S+)$/i.exec(h);
  if (!m) throw unauth('Missing or malformed Authorization header.');
  let claims;
  try {
    claims = jwt.verify(m[1], SECRET, { algorithms: ['HS256'] });
  } catch {
    throw unauth('Invalid, tampered or expired token.');
  }
  const user = [...state.users.values()].find((u) => u.user_id === claims.sub);
  if (!user) throw unauth('Token subject no longer exists.');
  if (user.active === false) throw unauth('This account has been disabled.');
  return user;
}

function login(body) {
  if (!isObj(body) || !isStr(body.email) || !isStr(body.password)) {
    throw err(400, 'VALIDATION_ERROR', 'Email and password are required.', { fields: ['email', 'password'] });
  }
  const user = state.users.get(body.email.trim().toLowerCase());
  if (!user || !userPasswordMatches(user, body.password)) throw unauth('Email or password is incorrect.');
  if (user.active === false) throw unauth('This account has been disabled.');
  return { token: issueToken(user), expires_in: TTL_SECONDS, user: publicUser(user) };
}

function publicUser(u) {
  const tenant = u.tenant_id ? state.tenants.get(u.tenant_id) : null;
  return {
    user_id: u.user_id,
    email: u.email,
    name: u.name,
    role: u.role,
    tenant_id: u.tenant_id,
    tenant,
    league_ids: u.league_ids || [],
    club_id: u.club_id || null,
    player_id: u.player_id || null,
    store_access: u.role === 'super_admin' || (u.role === 'club_manager' && u.store_access !== false),
    active: u.active !== false,
  };
}

function rbacMatrix() {
  const byRole = (role) => [...state.users.values()].find((u) => u.role === role);
  const tokens = {};
  for (const role of ['super_admin', 'league_organizer', 'club_manager', 'player', 'viewer']) tokens[role] = issueToken(byRole(role));
  return {
    tokens,
    context: {
      tenant_id: 'tenant-alpha',
      foreign_tenant_id: 'tenant-beta',
      own_league_id: 'league-alpha-1',
      other_league_id: 'league-alpha-2',
      foreign_league_id: 'league-beta-1',
      own_club_id: 'club-alpha-1',
      other_club_id: 'club-alpha-2',
      foreign_club_id: 'club-beta-1',
      own_player_id: 'player-alpha-1',
      other_player_id: 'player-alpha-2',
      foreign_player_id: 'player-beta-1',
    },
  };
}

module.exports = { authenticate, login, rbacMatrix, issueToken, publicUser, hashPassword };
