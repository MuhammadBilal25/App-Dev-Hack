'use strict';

const express = require('express');
const { state, clone } = require('../state');
const { err } = require('../lib/errors');
const { authenticate } = require('../services/auth');
const { can, forbid } = require('../services/rbac');
const scoring = require('../services/scoring');
const { standingsFor } = require('../services/standings');
const store = require('../services/store');

// Read API for the mobile app. Every route authenticates the JWT, then enforces tenant isolation
// through the RBAC policy layer: another tenant's league or club answers 403 FORBIDDEN.

// Contrast-checked white-label colours (mobile/UI.md §3.3). Unknown tenants fall back to their
// own primary colour.
const TENANT_COLORS = {
  'tenant-alpha': { light: '#1D4ED8', dark: '#8AB4FF' },
  'tenant-beta': { light: '#0F766E', dark: '#5EEAD4' },
};

const initials = (name, max) => name.trim().split(/\s+/).slice(0, max).map((w) => w[0].toUpperCase()).join('');

function lookup(map, kind, id) {
  const r = map.get(id);
  if (!r) throw err(404, `${kind.toUpperCase()}_NOT_FOUND`, `${kind} ${id} does not exist.`, { [`${kind}_id`]: id });
  return r;
}

function readable(user, action, resource) {
  if (!can(user, action, resource)) throw forbid(action);
  return resource;
}

const inTenant = (user, r) => user.role === 'super_admin' || r.tenant_id === user.tenant_id;

const clubName = (id) => (state.clubs.get(id) || { name: id }).name;

const teamRef = (side) => ({ team_id: side.team_id, name: clubName(side.team_id), score: side.score, wickets: side.wickets, overs: side.overs });

function fixtureMeta(matchId) {
  for (const list of state.leagueFixtures.values()) {
    const f = list.find((x) => x.match_id === matchId);
    if (f) return f;
  }
  return null;
}

// Minute of a live match from its kickoff, capped at the sport's regulation time.
function liveMinute(f, sport, status) {
  if (status !== 'in_progress' || !sport.periods.count) return null;
  const regulation = sport.periods.count * sport.periods.duration_minutes;
  const m = Math.floor((Date.now() - Date.parse(f.kickoff_at)) / 60000);
  return Math.max(1, Math.min(regulation, m));
}

function fixtureView(f) {
  const p = scoring.project(state.matches.get(f.match_id));
  const sport = state.sports.get(p.sport_id);
  const league = state.leagues.get(f.league_id);
  return {
    match_id: f.match_id,
    league_id: f.league_id,
    league_name: league ? league.name : f.league_id,
    sport_id: p.sport_id,
    round: f.round,
    kickoff_at: f.kickoff_at,
    venue: f.venue,
    status: p.status,
    outcome: p.outcome,
    minute: liveMinute(f, sport, p.status),
    winner_team_id: p.status === 'completed' ? p.winner_team_id : null,
    home: teamRef(p.home),
    away: teamRef(p.away),
    version: p.version,
  };
}

async function productView(productId) {
  const product = state.products.get(productId);
  if (!product) return null;
  const variants = [];
  for (const v of product.variants) {
    const inv = await store.inventory(v.variant_id);
    variants.push({ ...clone(v), stock: inv.stock });
  }
  return { ...clone(product), variants };
}

function eventLabel(e, sport) {
  const p = e.payload;
  if (e.type === 'score') return p.event_type.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
  if (e.type === 'discipline') return 'Discipline';
  if (e.type === 'match_start') return 'Kick-off';
  if (e.type === 'match_end') return 'Full time';
  if (e.type === 'tiebreak_winner') return 'Tie-break winner';
  if (e.type === 'compensation') return 'Correction';
  return sport.name;
}

function mobileRouter() {
  const r = express.Router();

  // Per route (not router.use) so unknown /api/v1 paths still answer 404, not 401.
  const auth = (req, res, next) => {
    req.user = authenticate(req);
    next();
  };

  r.get('/tenants/me', auth, (req, res) => {
    const t = req.user.tenant_id ? state.tenants.get(req.user.tenant_id) : null;
    if (!t) {
      return res.status(200).json({ tenant_id: null, name: 'huddle', colors: { light: '#1D4ED8', dark: '#8AB4FF' }, initials: 'H', logo_url: null });
    }
    const primary = (t.colors && t.colors.primary) || '#1D4ED8';
    res.status(200).json({
      tenant_id: t.tenant_id,
      name: t.name,
      colors: TENANT_COLORS[t.tenant_id] || { light: primary, dark: primary },
      initials: initials(t.name, 2),
      logo_url: t.logo_url,
    });
  });

  r.get('/leagues', auth, (req, res) => {
    const leagues = [...state.leagues.values()].filter((l) => inTenant(req.user, l)).map((l) => {
      const pl = state.prodLeagues.get(l.league_id);
      return {
        ...clone(l),
        sport_name: state.sports.get(l.sport_id).name,
        team_count: pl ? pl.teams.length : 0,
        fixture_count: (state.leagueFixtures.get(l.league_id) || []).length,
        qualification_spots: pl ? pl.qualification_spots : null,
      };
    });
    res.status(200).json({ leagues });
  });

  r.get('/fixtures', auth, (req, res) => {
    let leagueIds;
    if (req.query.league_id) {
      readable(req.user, 'league.read', lookup(state.leagues, 'league', String(req.query.league_id)));
      leagueIds = [String(req.query.league_id)];
    } else {
      leagueIds = [...state.leagues.values()].filter((l) => inTenant(req.user, l)).map((l) => l.league_id);
    }
    const fixtures = leagueIds
      .flatMap((id) => state.leagueFixtures.get(id) || [])
      .map(fixtureView)
      .sort((a, b) => (a.kickoff_at < b.kickoff_at ? -1 : 1));
    res.status(200).json({ fixtures });
  });

  r.get('/matches/:matchId', auth, async (req, res) => {
    const f = fixtureMeta(req.params.matchId);
    if (!f) throw err(404, 'MATCH_NOT_FOUND', `Match ${req.params.matchId} does not exist.`, { match_id: req.params.matchId });
    const league = readable(req.user, 'league.read', state.leagues.get(f.league_id));
    const p = scoring.project(state.matches.get(f.match_id));
    const sport = state.sports.get(p.sport_id);
    const pinned = state.pinned.get(f.match_id);
    res.status(200).json({
      ...fixtureView(f),
      sport_name: sport.name,
      scoring_events: Object.keys(sport.scoring_events),
      can_score: can(req.user, 'match.score.write', league),
      timeline: p.events.map((e) => ({
        sequence: e.sequence,
        event_id: e.event_id,
        type: e.type,
        label: eventLabel(e, sport),
        minute: typeof e.payload.minute === 'number' ? e.payload.minute : null,
        team_id: e.payload.team_id || null,
        team_name: e.payload.team_id ? clubName(e.payload.team_id) : null,
        reason: e.payload.reason || null,
        compensates: e.payload.compensates || null,
        compensated: e.compensated,
        compensated_by: e.compensated_by,
      })),
      pinned_product: pinned ? await productView(pinned) : null,
    });
  });

  r.get('/standings/:leagueId', auth, (req, res) => {
    const league = readable(req.user, 'league.read', lookup(state.leagues, 'league', req.params.leagueId));
    const s = standingsFor(state.prodLeagues.get(league.league_id));
    res.status(200).json({
      ...s,
      league_name: league.name,
      table: s.table.map((row) => ({ ...row, team_name: clubName(row.team_id) })),
    });
  });

  r.get('/clubs', auth, (req, res) => {
    const clubs = [...state.clubs.values()].filter((c) => inTenant(req.user, c)).map((c) => ({
      club_id: c.club_id, name: c.name, league_id: c.league_id, tenant_id: c.tenant_id,
    }));
    res.status(200).json({ clubs });
  });

  r.get('/clubs/:clubId', auth, (req, res) => {
    const club = readable(req.user, 'club.read', lookup(state.clubs, 'club', req.params.clubId));
    const league = state.leagues.get(club.league_id);
    const pl = league && state.prodLeagues.get(league.league_id);
    const row = pl ? standingsFor(pl).table.find((t) => t.team_id === club.club_id) : null;
    res.status(200).json({
      club_id: club.club_id,
      tenant_id: club.tenant_id,
      name: club.name,
      league_id: club.league_id,
      league_name: league ? league.name : null,
      sport_id: league ? league.sport_id : null,
      sport_name: league ? state.sports.get(league.sport_id).name : null,
      venue: clone(club.home_venue),
      social: clone(club.social || {}),
      staff: clone(club.staff || []),
      roster: [...state.players.values()]
        .filter((p) => p.club_id === club.club_id)
        .map((p) => ({ player_id: p.player_id, name: p.name, position: p.position, role: p.role, shirt: p.shirt || null })),
      stats: row
        ? { rank: row.rank, played: row.played, won: row.won, drawn: row.drawn, lost: row.lost, points: row.points, diff: row.diff }
        : null,
      can_manage: can(req.user, 'club.roster.write', club),
    });
  });

  r.get('/catalogue', auth, async (req, res) => {
    const products = [];
    for (const p of store.catalogue(req.user.role === 'super_admin' ? null : req.user.tenant_id)) {
      const v = await productView(p.product_id);
      v.club_name = clubName(p.club_id);
      products.push(v);
    }
    res.status(200).json({ products });
  });

  return r;
}

module.exports = { mobileRouter };
