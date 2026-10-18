'use strict';

const express = require('express');
const { state, clone } = require('../state');
const { err, validation } = require('../lib/errors');
const { isObj, isStr } = require('../lib/validate');
const { authenticate } = require('../services/auth');
const { can, forbid } = require('../services/rbac');
const scoring = require('../services/scoring');
const { standingsFor } = require('../services/standings');
const roster = require('../services/roster');
const schedule = require('../services/schedule');
const views = require('../services/views');
const feeds = require('../services/feeds');
const platform = require('../services/platform');
const merch = require('../services/merch');
const activity = require('../lib/activity');

// Read API for the mobile app. Every route authenticates the JWT, then enforces tenant isolation
// through the RBAC policy layer: another tenant's league or club answers 403 FORBIDDEN.

// Contrast-checked white-label colours (mobile/UI.md §3.3). Tenants whose branding was changed
// through the admin API use their own colours.
const TENANT_COLORS = {
  'tenant-alpha': { light: '#1D4ED8', dark: '#8AB4FF' },
  'tenant-beta': { light: '#0F766E', dark: '#5EEAD4' },
};

const initials = (name, max) => name.trim().split(/\s+/).slice(0, max).map((w) => w[0].toUpperCase()).join('');

// A lighter tint of a brand colour for dark mode when the admin gave none.
function lighten(hex) {
  const n = parseInt(hex.slice(1), 16);
  const mix = (c) => Math.round(c + (255 - c) * 0.45);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(mix);
  return `#${((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1).toUpperCase()}`;
}

function tenantBrand(t) {
  const primary = (t.colors && t.colors.primary) || '#1D4ED8';
  if (!t.brand_custom && TENANT_COLORS[t.tenant_id]) return TENANT_COLORS[t.tenant_id];
  return { light: primary, dark: (t.colors && t.colors.dark) || lighten(primary) };
}

function lookup(map, kind, id) {
  const r = map.get(id);
  if (!r) throw err(404, `${kind.toUpperCase()}_NOT_FOUND`, `${kind} ${id} does not exist.`, { [`${kind}_id`]: id });
  return r;
}

function readable(user, action, resource) {
  if (!can(user, action, resource)) throw forbid(action);
  return resource;
}

const clubName = views.clubName;

function eventLabel(e) {
  const p = e.payload;
  if (e.type === 'score') return p.event_type.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
  if (e.type === 'discipline') return 'Discipline';
  if (e.type === 'match_start') return 'Kick-off';
  if (e.type === 'match_end') return 'Full time';
  if (e.type === 'tiebreak_winner') return 'Tie-break winner';
  if (e.type === 'compensation') return 'Correction';
  return e.type;
}

// Current squad from the roster engine when the club's league is set up there (so transfers show
// up at once), otherwise the static club players. `version` is the base_version for offline sync.
function clubRoster(club) {
  const league = state.rosterLeagues.get(club.league_id);
  if (league && league.squad_ids.includes(club.club_id)) {
    return roster.squadMembers(club.club_id).map((p) => {
      const base = state.players.get(p.player_id) || {};
      return {
        player_id: p.player_id,
        name: p.name,
        position: p.position,
        role: p.role,
        shirt: base.shirt || null,
        on_loan: !!(p.loan && !p.loan.returned),
        version: roster.playerVersion(p.player_id),
      };
    });
  }
  return [...state.players.values()]
    .filter((p) => p.club_id === club.club_id)
    .map((p) => ({ player_id: p.player_id, name: p.name, position: p.position, role: p.role, shirt: p.shirt || null, on_loan: false, version: 0 }));
}

// The sport's scoring template for the score-entry panel: one control per scoring event, with
// the values the engine will apply (points, runs / legal ball / wicket, or rounds).
function scoringTemplate(sport) {
  return {
    model: sport.scoring_model,
    periods: clone(sport.periods),
    draw_allowed: sport.draw_allowed,
    overtime: clone(sport.overtime),
    events: Object.entries(sport.scoring_events).map(([key, def]) => ({
      key,
      label: key.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase()),
      value: def.points ?? def.runs ?? def.rounds ?? 0,
      legal_ball: def.legal_ball ?? null,
      wicket: def.wicket ?? null,
    })),
  };
}

const squadList = (clubId) => {
  const club = state.clubs.get(clubId);
  return club ? clubRoster(club).map((p) => ({ player_id: p.player_id, name: p.name, shirt: p.shirt, position: p.position })) : [];
};

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
    res.status(200).json({ tenant_id: t.tenant_id, name: t.name, colors: tenantBrand(t), initials: initials(t.name, 2), logo_url: t.logo_url });
  });

  r.get('/home', auth, async (req, res) => res.status(200).json(await feeds.home(req.user)));
  r.get('/search', auth, async (req, res) => res.status(200).json(await feeds.search(req.user, req.query.q)));

  r.get('/sports', auth, (req, res) => res.status(200).json({ sports: platform.listSports(req.user) }));
  r.get('/sports/:sportId', auth, (req, res) => res.status(200).json(platform.sportDetail(req.user, req.params.sportId)));

  r.get('/leagues', auth, (req, res) => {
    const leagues = views.visibleLeagues(req.user)
      .filter((l) => !req.query.sport_id || l.sport_id === req.query.sport_id)
      .map(views.leagueView);
    res.status(200).json({ leagues });
  });

  r.get('/leagues/:leagueId', auth, (req, res) => {
    const league = readable(req.user, 'league.read', lookup(state.leagues, 'league', req.params.leagueId));
    const fixtures = (state.leagueFixtures.get(league.league_id) || []).map(views.fixtureView).sort(views.byKickoff);
    const sport = state.sports.get(league.sport_id);
    res.status(200).json({
      ...views.leagueView(league),
      clubs: views.leagueTeams(league.league_id).map((id) => state.clubs.get(id)).filter(Boolean).map(views.clubCard),
      fixtures,
      sport_rules: platform.describeRules(sport),
      has_bracket: !!league.bracket,
      has_swiss: !!league.swiss,
      swiss: league.swiss ? { total_rounds: league.swiss.total_rounds, current_round: Math.max(0, ...fixtures.map((f) => f.round)) } : null,
      can_manage: can(req.user, 'league.fixtures.write', league),
    });
  });

  r.get('/leagues/:leagueId/bracket', auth, (req, res) => {
    const league = readable(req.user, 'league.read', lookup(state.leagues, 'league', req.params.leagueId));
    res.status(200).json(schedule.bracketView(league));
  });

  r.get('/fixtures', auth, (req, res) => {
    let leagueIds;
    if (req.query.league_id) {
      readable(req.user, 'league.read', lookup(state.leagues, 'league', String(req.query.league_id)));
      leagueIds = [String(req.query.league_id)];
    } else {
      leagueIds = views.visibleLeagues(req.user).map((l) => l.league_id);
    }
    const { status, club_id: clubId, sport_id: sportId } = req.query;
    const fixtures = leagueIds
      .flatMap((id) => state.leagueFixtures.get(id) || [])
      .filter((f) => !clubId || f.home === clubId || f.away === clubId)
      .map(views.fixtureView)
      .filter((f) => (!status || f.status === status) && (!sportId || f.sport_id === sportId))
      .sort(views.byKickoff);
    res.status(200).json({ fixtures });
  });

  r.get('/matches/:matchId', auth, async (req, res) => {
    const f = views.fixtureOr404(req.params.matchId);
    const league = readable(req.user, 'league.read', state.leagues.get(f.league_id));
    const p = scoring.project(state.matches.get(f.match_id));
    const sport = state.sports.get(p.sport_id);
    const pinned = state.pinned.get(f.match_id);
    const view = views.fixtureView(f);
    const canScore = can(req.user, 'match.score.write', league);
    const pinnedProduct = pinned && state.products.get(pinned) && state.products.get(pinned).active !== false
      ? await merch.productView(state.products.get(pinned)) : null;
    res.status(200).json({
      ...view,
      scoring_events: Object.keys(sport.scoring_events),
      scoring: scoringTemplate(sport),
      can_score: canScore,
      can_manage: can(req.user, 'league.fixtures.write', league),
      allowed_status: canScore ? schedule.STATUS_TRANSITIONS[view.status] : [],
      squads: canScore ? { home: squadList(f.home), away: squadList(f.away) } : null,
      tiebreak_winner_team_id: p.tiebreak_winner_team_id,
      timeline: p.events.map((e) => ({
        sequence: e.sequence,
        event_id: e.event_id,
        type: e.type,
        label: eventLabel(e),
        event_type: e.payload.event_type || null,
        minute: typeof e.payload.minute === 'number' ? e.payload.minute : null,
        team_id: e.payload.team_id || null,
        team_name: e.payload.team_id ? clubName(e.payload.team_id) : null,
        player_id: e.payload.player_id || null,
        player_name: e.payload.player_id ? ((state.players.get(e.payload.player_id) || state.rosterPlayers.get(e.payload.player_id) || {}).name || null) : null,
        reason: e.payload.reason || null,
        compensates: e.payload.compensates || null,
        compensated: e.compensated,
        compensated_by: e.compensated_by,
        signature: e.signature,
      })),
      pinned_product: pinnedProduct,
    });
  });

  r.get('/standings/:leagueId', auth, (req, res) => {
    const league = readable(req.user, 'league.read', lookup(state.leagues, 'league', req.params.leagueId));
    const s = standingsFor(state.prodLeagues.get(league.league_id));
    res.status(200).json({
      ...s,
      league_name: league.name,
      sport_id: league.sport_id,
      format: league.format || 'round_robin',
      table: s.table.map((row) => ({ ...row, team_name: clubName(row.team_id) })),
    });
  });

  r.get('/clubs', auth, (req, res) => {
    const clubs = [...state.clubs.values()]
      .filter((c) => views.inTenant(req.user, c))
      .filter((c) => !req.query.league_id || views.clubLeagueIds(c.club_id).includes(req.query.league_id))
      .map(views.clubCard);
    res.status(200).json({ clubs });
  });

  r.get('/clubs/:clubId', auth, (req, res) => {
    const club = readable(req.user, 'club.read', lookup(state.clubs, 'club', req.params.clubId));
    const league = state.leagues.get(club.league_id);
    const fixtures = views.allFixtures().filter((f) => f.home === club.club_id || f.away === club.club_id).map(views.fixtureView).sort(views.byKickoff);
    res.status(200).json({
      club_id: club.club_id,
      tenant_id: club.tenant_id,
      name: club.name,
      description: club.description || '',
      colors: clone(club.colors || null),
      logo_url: club.logo_url || null,
      league_id: club.league_id,
      league_name: league ? league.name : null,
      sport_id: league ? league.sport_id : null,
      sport_name: league ? state.sports.get(league.sport_id).name : null,
      leagues: views.clubLeagueIds(club.club_id).map((id) => ({ league_id: id, name: state.leagues.get(id).name, season: state.leagues.get(id).season || null })),
      venue: clone(club.home_venue),
      social: clone(club.social || {}),
      staff: clone(club.staff || []),
      roster: clubRoster(club),
      positions: league ? Object.keys((state.rosterLeagues.get(league.league_id) || state.sports.get(league.sport_id).roster).required_positions || {}) : [],
      stats: feeds.tableRow(club.club_id),
      upcoming: fixtures.filter((f) => f.status === 'upcoming' || f.status === 'in_progress').slice(0, 5),
      results: fixtures.filter((f) => f.status === 'completed').reverse().slice(0, 5),
      product_count: [...state.products.values()].filter((p) => p.club_id === club.club_id && p.active !== false).length,
      can_manage: can(req.user, 'club.roster.write', club),
      can_edit: can(req.user, 'club.update', club),
      can_manage_store: can(req.user, 'club.products.write', club),
      can_view_history: can(req.user, 'club.history.read', club),
    });
  });

  r.get('/clubs/:clubId/roster-history', auth, (req, res) => {
    const club = lookup(state.clubs, 'club', req.params.clubId);
    readable(req.user, 'club.history.read', club);
    res.status(200).json({ club_id: club.club_id, history: feeds.clubRosterHistory(club.club_id) });
  });

  // Club Manager of this club only. `request_id` makes offline retries idempotent.
  const added = new Map();
  r.post('/clubs/:clubId/players', auth, (req, res) => {
    const club = lookup(state.clubs, 'club', req.params.clubId);
    if (!can(req.user, 'club.roster.write', club)) throw forbid('club.roster.write');
    const b = req.body;
    const bad = [];
    if (!isObj(b)) throw validation(['body']);
    if (!isStr(b.name) || !b.name.trim() || b.name.length > 80) bad.push('name');
    if (!isStr(b.position) || !/^[A-Za-z0-9_ -]{1,20}$/.test(b.position.trim())) bad.push('position');
    if (!roster.ROLES.includes(b.role)) bad.push('role');
    if (b.request_id !== undefined && !isStr(b.request_id)) bad.push('request_id');
    if (bad.length) throw validation(bad);
    const key = b.request_id ? `${club.club_id}|${b.request_id}` : null;
    if (key && added.has(key)) return res.status(200).json(added.get(key));
    const out = roster.addPlayer(club.league_id, club.club_id, { name: b.name.trim(), position: b.position.trim().toLowerCase(), role: b.role }, req.user.email);
    state.players.set(out.player.player_id, { ...out.player, club_id: club.club_id, tenant_id: club.tenant_id });
    if (key) added.set(key, out);
    activity.record(req.user, 'roster.add', out.player.player_id, { club_id: club.club_id, tenant_id: club.tenant_id, name: out.player.name });
    res.status(201).json(out);
  });

  r.get('/players/:playerId', auth, (req, res) => res.status(200).json(feeds.playerProfile(req.user, req.params.playerId)));

  r.get('/catalogue', auth, async (req, res) => {
    res.status(200).json({ products: (await merch.listProducts(req.user, {})).products });
  });

  return r;
}

module.exports = { mobileRouter };
