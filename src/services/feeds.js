'use strict';

// Read models for the app's landing screens: public home, search, player profiles, club roster
// history, and the role dashboards (Super-Admin, League Organizer, Club Manager). All derived
// on request from domain state, filtered to what the caller may see.
const { state, clone } = require('../state');
const { err, validation } = require('../lib/errors');
const { isStr } = require('../lib/validate');
const { can } = require('./rbac');
const scoring = require('./scoring');
const roster = require('./roster');
const { standingsFor } = require('./standings');
const views = require('./views');
const platform = require('./platform');
const merch = require('./merch');

const SOLD = ['paid', 'packed', 'shipped', 'delivered'];

function tenantFixtures(user) {
  return views.visibleLeagues(user)
    .filter((l) => l.status !== 'archived')
    .flatMap((l) => state.leagueFixtures.get(l.league_id) || [])
    .map(views.fixtureView)
    .sort(views.byKickoff);
}

function tableRow(clubId) {
  const club = state.clubs.get(clubId);
  const pl = club && state.prodLeagues.get(club.league_id);
  if (!pl) return null;
  const row = standingsFor(pl).table.find((t) => t.team_id === clubId);
  return row ? { rank: row.rank, played: row.played, won: row.won, drawn: row.drawn, lost: row.lost, points: row.points, diff: row.diff } : null;
}

function visibleClubs(user) {
  return [...state.clubs.values()].filter((c) => views.inTenant(user, c));
}

async function home(user) {
  const fixtures = tenantFixtures(user);
  const leagues = views.visibleLeagues(user).filter((l) => l.status !== 'archived').map(views.leagueView);
  const clubs = visibleClubs(user)
    .map((c) => ({ ...views.clubCard(c), stats: tableRow(c.club_id) }))
    .sort((a, b) => (b.stats ? b.stats.points : -1) - (a.stats ? a.stats.points : -1) || a.name.localeCompare(b.name));
  const shop = await merch.listProducts(user, { sort: 'popular', in_stock: '1' });
  const fresh = await merch.listProducts(user, { sort: 'newest' });
  return {
    sports: platform.listSports(user).filter((s) => s.active),
    live: fixtures.filter((f) => f.status === 'in_progress'),
    upcoming: fixtures.filter((f) => f.status === 'upcoming').slice(0, 8),
    results: fixtures.filter((f) => f.status === 'completed').reverse().slice(0, 6),
    leagues: leagues.sort((a, b) => b.live_count - a.live_count || b.fixture_count - a.fixture_count).slice(0, 8),
    clubs: clubs.slice(0, 10),
    featured_products: shop.products.slice(0, 6),
    new_products: fresh.products.slice(0, 6),
  };
}

async function search(user, q) {
  if (!isStr(q) || q.trim().length < 2 || q.length > 60) throw validation(['q'], 'Type at least two characters to search.');
  const needle = q.trim().toLowerCase();
  const has = (...xs) => xs.some((x) => (x || '').toLowerCase().includes(needle));
  const leagues = views.visibleLeagues(user);
  const clubs = visibleClubs(user);
  const clubIds = new Set(clubs.map((c) => c.club_id));
  const players = [];
  for (const p of state.players.values()) {
    const clubId = currentClub(p.player_id);
    if (clubIds.has(clubId) && has(p.name, p.position)) players.push({ player_id: p.player_id, name: p.name, position: p.position, club_id: clubId, club_name: views.clubName(clubId) });
  }
  const products = (await merch.listProducts(user, { q: needle })).products;
  return {
    query: q.trim(),
    sports: platform.listSports(user).filter((s) => s.active && has(s.name, s.description)).slice(0, 10),
    leagues: leagues.filter((l) => has(l.name, l.season)).map(views.leagueView).slice(0, 10),
    clubs: clubs.filter((c) => has(c.name, c.home_venue && c.home_venue.name)).map(views.clubCard).slice(0, 10),
    players: players.slice(0, 10),
    products: products.slice(0, 10),
  };
}

// ---------------------------------------------------------------------------------------------
// Players
// ---------------------------------------------------------------------------------------------
function currentClub(playerId) {
  const squad = roster.currentSquadOf(playerId);
  if (squad !== undefined) return squad;
  const p = state.players.get(playerId);
  return p ? p.club_id : null;
}

// Scoring and discipline events credited to a player (payload.player_id), skipping compensated
// ones. Values come from the sport config, so any sport's stats work the same way.
function playerStats(playerId, clubId) {
  const scoringByType = new Map();
  let discipline = 0;
  const recent = [];
  for (const match of state.matches.values()) {
    const proj = scoring.project(match);
    const sport = state.sports.get(match.sport_id);
    for (const e of proj.events) {
      if (e.compensated || e.payload.player_id !== playerId) continue;
      if (e.type === 'score') {
        const def = sport.scoring_events[e.payload.event_type] || {};
        const value = def.points || def.runs || def.rounds || 0;
        const s = scoringByType.get(e.payload.event_type) || { event_type: e.payload.event_type, count: 0, value: 0 };
        s.count += 1;
        s.value += value;
        scoringByType.set(e.payload.event_type, s);
        recent.push({ match_id: match.match_id, event_type: e.payload.event_type, minute: e.payload.minute ?? null, sequence: e.sequence });
      } else if (e.type === 'discipline') discipline += 1;
    }
  }
  const played = clubId
    ? views.allFixtures().filter((f) => (f.home === clubId || f.away === clubId) && views.effectiveStatus(f) === 'completed').length
    : 0;
  const label = (k) => k.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
  const list = [...scoringByType.values()].map((s) => ({ ...s, label: label(s.event_type) }));
  return {
    club_matches_played: played,
    scoring: list,
    total_value: list.reduce((n, s) => n + s.value, 0),
    discipline_events: discipline,
    recent: recent.slice(-5).reverse(),
  };
}

function playerProfile(user, playerId) {
  const base = state.players.get(playerId);
  const rp = state.rosterPlayers.get(playerId);
  if (!base && !rp) throw err(404, 'PLAYER_NOT_FOUND', `Player ${playerId} does not exist.`, { player_id: playerId });
  const clubId = currentClub(playerId);
  const club = clubId ? state.clubs.get(clubId) : null;
  const tenantId = (base && base.tenant_id) || (club && club.tenant_id);
  if (user.role !== 'super_admin' && tenantId !== user.tenant_id) {
    throw err(403, 'FORBIDDEN', 'You are not allowed to perform this action.', { action: 'player.read' });
  }
  const league = club ? state.leagues.get(club.league_id) : null;
  const subject = { player_id: playerId, club_id: clubId, tenant_id: tenantId };
  const showPrivate = can(user, 'player.private.read', subject) || (user.role === 'league_organizer' && league && (user.league_ids || []).includes(league.league_id));
  return {
    player_id: playerId,
    name: (rp && rp.name) || base.name,
    position: (rp && rp.position) || base.position,
    role: (rp && rp.role) || base.role,
    shirt: base ? base.shirt || null : null,
    club: club ? views.clubCard(club) : null,
    league_id: league ? league.league_id : null,
    league_name: league ? league.name : null,
    sport_name: league ? state.sports.get(league.sport_id).name : null,
    on_loan: !!(rp && rp.loan && !rp.loan.returned),
    loan: rp && rp.loan && !rp.loan.returned ? { from_club_id: rp.loan.lender, from_club_name: views.clubName(rp.loan.lender), ends: rp.loan.end } : null,
    released: clubId === null,
    stats: playerStats(playerId, clubId),
    history: showPrivate && rp ? clone(rp.audit).reverse() : null,
    is_me: user.player_id === playerId,
  };
}

// Every roster change touching a club (in or out), newest first.
function clubRosterHistory(clubId) {
  const out = [];
  for (const p of state.rosterPlayers.values()) {
    for (const a of p.audit) {
      if (a.from_squad_id === clubId || a.to_squad_id === clubId) {
        out.push({ ...clone(a), player_name: p.name, from_club_name: a.from_squad_id ? views.clubName(a.from_squad_id) : null, to_club_name: a.to_squad_id ? views.clubName(a.to_squad_id) : null });
      }
    }
  }
  return out.sort((a, b) => b.when.localeCompare(a.when) || b.audit_id.localeCompare(a.audit_id));
}

// ---------------------------------------------------------------------------------------------
// Dashboards
// ---------------------------------------------------------------------------------------------
const recentActivity = (filter, n = 10) => state.activity.filter(filter).slice(-n).reverse();

function revenue(orders) {
  return orders.filter((o) => SOLD.includes(o.status)).reduce((s, o) => s + o.total_minor, 0);
}

async function adminDashboard() {
  const orders = [...state.prodOrders.values()].map(merch.orderView);
  const fixtures = views.allFixtures().map((f) => views.effectiveStatus(f));
  const count = (s) => fixtures.filter((x) => x === s).length;
  const users = [...state.users.values()];
  return {
    tenants: state.tenants.size,
    sports: { total: state.sports.size, active: [...state.sports.keys()].filter(platform.sportActive).length },
    leagues: state.leagues.size,
    clubs: state.clubs.size,
    players: state.players.size,
    users: Object.fromEntries(platform.ROLES.map((r) => [r, users.filter((u) => u.role === r).length])),
    fixtures: { upcoming: count('upcoming'), in_progress: count('in_progress'), completed: count('completed'), postponed: count('postponed'), cancelled: count('cancelled') },
    orders: { count: orders.length, revenue_minor: revenue(orders), refunded: orders.filter((o) => o.status === 'refunded' || o.status === 'cancelled').length },
    products: state.products.size,
    low_stock: (await merch.lowStock({ role: 'super_admin' })).length,
    recent_activity: recentActivity(() => true, 12),
  };
}

function organizerDashboard(user) {
  const ids = user.role === 'super_admin' ? [...state.leagues.keys()] : user.league_ids || [];
  const leagues = ids.map((id) => state.leagues.get(id)).filter(Boolean);
  const fixtures = leagues.flatMap((l) => state.leagueFixtures.get(l.league_id) || []).map(views.fixtureView).sort(views.byKickoff);
  const counts = (lid) => {
    const fx = fixtures.filter((f) => f.league_id === lid);
    const c = (s) => fx.filter((f) => f.status === s).length;
    return { upcoming: c('upcoming'), in_progress: c('in_progress'), completed: c('completed'), postponed: c('postponed') };
  };
  return {
    leagues: leagues.map((l) => ({ ...views.leagueView(l), counts: counts(l.league_id), has_bracket: !!l.bracket, has_swiss: !!l.swiss })),
    live: fixtures.filter((f) => f.status === 'in_progress'),
    upcoming: fixtures.filter((f) => f.status === 'upcoming').slice(0, 10),
    postponed: fixtures.filter((f) => f.status === 'postponed'),
    recent_results: fixtures.filter((f) => f.status === 'completed').reverse().slice(0, 6),
    recent_activity: recentActivity((a) => ids.some((id) => JSON.stringify(a.details || {}).includes(id) || a.target === id), 10),
  };
}

async function managerDashboard(user) {
  const club = state.clubs.get(user.club_id);
  if (!club) throw err(404, 'CLUB_NOT_FOUND', 'No club is assigned to this account.', { club_id: user.club_id || null });
  const rl = state.rosterLeagues.get(club.league_id);
  const squad = roster.squadMembers(club.club_id);
  const fixtures = views.allFixtures().filter((f) => f.home === club.club_id || f.away === club.club_id).map(views.fixtureView).sort(views.byKickoff);
  const storeAccess = can(user, 'club.products.write', club);
  const orders = storeAccess ? merch.listOrders(user, { scope: 'managed', club_id: club.club_id }) : [];
  const required = rl ? rl.required_positions : {};
  return {
    club: { ...views.clubCard(club), stats: tableRow(club.club_id) },
    squad: {
      size: squad.length,
      max: rl ? rl.max_squad_size : null,
      on_loan: squad.filter((p) => p.loan && !p.loan.returned).length,
      positions: Object.entries(required).map(([position, need]) => ({ position, required: need, have: squad.filter((p) => p.position === position).length })),
      transfer_window: rl ? clone(rl.transfer_window) : null,
    },
    upcoming: fixtures.filter((f) => f.status === 'upcoming').slice(0, 5),
    results: fixtures.filter((f) => f.status === 'completed').reverse().slice(0, 5),
    live: fixtures.filter((f) => f.status === 'in_progress'),
    store_access: storeAccess,
    store: storeAccess
      ? {
          products: [...state.products.values()].filter((p) => p.club_id === club.club_id).length,
          orders: orders.length,
          open_orders: orders.filter((o) => ['paid', 'packed', 'shipped'].includes(o.status)).length,
          revenue_minor: revenue(orders),
          low_stock: await merch.lowStock(user, club.club_id),
        }
      : null,
    roster_changes: clubRosterHistory(club.club_id).slice(0, 8),
  };
}

module.exports = { home, search, playerProfile, clubRosterHistory, adminDashboard, organizerDashboard, managerDashboard, currentClub, tableRow };
