// Generates NaSCon.postman_collection.json. Run: node postman/build-collection.js
const fs = require('fs');
const path = require('path');

const req = (name, method, p, body, desc) => ({
  name,
  request: {
    method,
    header: body ? [{ key: 'Content-Type', value: 'application/json' }] : [],
    url: { raw: '{{baseUrl}}' + p, host: ['{{baseUrl}}'], path: p.replace(/^\//, '').split('/') },
    ...(body ? { body: { mode: 'raw', raw: JSON.stringify(body, null, 2) } } : {}),
    description: desc || '',
  },
});
const ev = (name, eventId, type, payload, desc, matchId = 'm1') =>
  req(name, 'POST', '/audit/v1/events', { event_id: eventId, match_id: matchId, type, payload }, desc);

const collection = {
  info: {
    name: 'NaSCon 26 - Backend',
    schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
    description: 'Run folders top to bottom. The expected status code is in each request name.',
  },
  variable: [{ key: 'baseUrl', value: 'http://localhost:8080' }],
  // Every request asserts the status code written in its name ("... -> 201") and, for errors,
  // the error code when the name contains one (e.g. "-> 409 OUT_OF_STOCK").
  event: [{
    listen: 'test',
    script: {
      type: 'text/javascript',
      exec: [
        'const m = pm.info.requestName.match(/->\\s*(\\d{3})(?:\\s+([A-Z_]{3,}))?/);',
        'if (m) {',
        '  pm.test(`status is ${m[1]}`, () => pm.response.to.have.status(Number(m[1])));',
        '  if (m[2]) pm.test(`error code is ${m[2]}`, () => pm.expect(pm.response.json().error.code).to.eql(m[2]));',
        '}',
      ],
    },
  }],
  item: [
    {
      name: '1. Setup',
      item: [
        req('Health -> 200', 'GET', '/health', null, 'Expect {"status":"ok"}'),
        req('Reset (default) -> 200', 'POST', '/audit/v1/reset', {}, 'Wipes and re-seeds. Stock M=1, L=5.'),
        req('Reset (custom seed/stock) -> 200', 'POST', '/audit/v1/reset', { seed: 7, stock: { 'var-jersey-001-M': 3 } }, 'Stock echo shows M=3.'),
        req('Reset (bad seed) -> 400', 'POST', '/audit/v1/reset', { seed: 'abc' }, 'VALIDATION_ERROR, fields [seed]'),
      ],
    },
    {
      name: '2. Sports',
      item: [
        req('Create mystery sport kabaddi -> 201', 'POST', '/audit/v1/sports', {
          sport_id: 'kabaddi', name: 'Kabaddi', scoring_model: 'event',
          periods: { count: 2, duration_minutes: 20 },
          scoring_events: { raid_point: { points: 1 }, tackle_point: { points: 1 }, all_out: { points: 2 } },
          draw_allowed: false, overtime: { policy: 'golden_score', duration_minutes: 5 },
          tie_break_order: ['h2h_points', 'h2h_diff', 'overall_diff', 'scored', 'fair_play', 'draw_lots'],
          roster: { min_squad_size: 7, max_squad_size: 12, required_positions: { raider: 2, defender: 3 } },
        }, 'Send twice: second time -> 409 SPORT_EXISTS'),
        req('SQL injection sport_id -> 400', 'POST', '/audit/v1/sports', { sport_id: "x'; DROP TABLE sports;--" }, 'Never 5xx.'),
      ],
    },
    {
      name: '3. League + football match',
      item: [
        req('Register league lg-1 -> 201', 'POST', '/audit/v1/leagues', {
          league_id: 'lg-1', sport_id: 'football', teams: ['t1', 't2', 't3', 't4'],
          fixtures: [{ match_id: 'm1', home: 't1', away: 't2' }, { match_id: 'm2', home: 't3', away: 't4' }],
          points: { win: 3, draw: 1, loss: 0 }, qualification: { spots: 2 }, lots_seed: 42,
        }, 'Second time -> 409 LEAGUE_EXISTS'),
        ev('Goal before start -> 409 MATCH_NOT_IN_PROGRESS', 'evt-0', 'score', { team_id: 't1', event_type: 'goal' }),
        ev('Start match -> 201', 'evt-1', 'match_start', {}),
        ev('Goal t1 -> 201', 'evt-2', 'score', { team_id: 't1', event_type: 'goal' }, 'Send again unchanged -> 200 (idempotent replay)'),
        ev('Same event_id, different body -> 409 DUPLICATE_EVENT_ID', 'evt-2', 'score', { team_id: 't2', event_type: 'goal' }),
        ev('Unknown event type -> 400 UNKNOWN_EVENT_TYPE', 'evt-x', 'score', { team_id: 't1', event_type: 'touchdown' }),
        ev('Goal t2 -> 201', 'evt-3', 'score', { team_id: 't2', event_type: 'goal' }),
        ev('Compensate (disallow) evt-3 -> 201', 'evt-4', 'compensation', { compensates: 'evt-3', reason: 'Offside' }, 'Again -> 409 INVALID_COMPENSATION'),
        ev('Yellow card t2 (fair play -1) -> 201', 'evt-5', 'discipline', { team_id: 't2', points: -1 }),
        ev('End match -> 201', 'evt-6', 'match_end', {}),
        req('Score m1 -> 200 (t1 1-0, evt-3 compensated)', 'GET', '/audit/v1/score/m1', null, 'status completed, outcome home_win, version 6'),
        req('Score unknown -> 404 MATCH_NOT_FOUND', 'GET', '/audit/v1/score/nope'),
      ],
    },
    {
      name: '4. Basketball tie rules',
      item: [
        ev('Init stand-alone match b1 -> 201', 'b-1', 'match_init', { sport_id: 'basketball', home_team_id: 'h1', away_team_id: 'a1' }, '', 'b1'),
        ev('Start b1 -> 201', 'b-2', 'match_start', {}, '', 'b1'),
        ev('End while level -> 409 TIE_NOT_ALLOWED', 'b-3', 'match_end', {}, '', 'b1'),
        ev('Three pointer h1 -> 201', 'b-4', 'score', { team_id: 'h1', event_type: 'three_pointer' }, '', 'b1'),
        ev('End b1 -> 201', 'b-5', 'match_end', {}, '', 'b1'),
        req('Score b1 -> 200 (3-0 home_win)', 'GET', '/audit/v1/score/b1'),
      ],
    },
    {
      name: '4b. Fixture generation',
      item: [
        req('Round robin 5 teams + withdrawal -> 200 (8 scheduled, 2 forfeit)', 'POST', '/audit/v1/fixtures', {
          format: 'round_robin', teams: ['t1', 't2', 't3', 't4', 't5'],
          params: { legs: 1, withdrawals: [{ team_id: 't3', after_round: 2 }], withdrawal_policy: 'forfeit_remaining' },
        }, 'Each round has one bye. Check summary.'),
        req('Double round robin 4 teams -> 200 (6 rounds)', 'POST', '/audit/v1/fixtures', { format: 'round_robin', teams: ['t1', 't2', 't3', 't4'], params: { legs: 2 } }),
        req('Round robin 1 team -> 400 VALIDATION_ERROR', 'POST', '/audit/v1/fixtures', { format: 'round_robin', teams: ['t1'] }),
        req('Swiss round 1, 7 teams -> 200 (t1-t4, t2-t5, t3-t6, bye t7)', 'POST', '/audit/v1/fixtures', { format: 'swiss', teams: ['t1', 't2', 't3', 't4', 't5', 't6', 't7'], params: { total_rounds: 3, round: 1 } }),
        req('Swiss spec example round 2 -> 200 (bye t3)', 'POST', '/audit/v1/fixtures', {
          format: 'swiss', teams: ['t1', 't2', 't3', 't4', 't5'],
          params: { total_rounds: 3, round: 2, history: [{ round: 1, bye: 't5', matches: [{ home: 't1', away: 't3', result: 'home' }, { home: 't2', away: 't4', result: 'draw' }] }] },
        }, 'Standings: t1 1.0, t5 1.0, t2 0.5 (buchholz 0.5)'),
        req('Swiss impossible pairing -> 409 NO_VALID_PAIRING', 'POST', '/audit/v1/fixtures', {
          format: 'swiss', teams: ['t1', 't2', 't3', 't4', 't5', 't6'],
          params: {
            total_rounds: 5, round: 4,
            history: [
              { round: 1, bye: null, matches: [{ home: 't1', away: 't4', result: 'draw' }, { home: 't2', away: 't5', result: 'draw' }, { home: 't3', away: 't6', result: 'draw' }] },
              { round: 2, bye: null, matches: [{ home: 't1', away: 't5', result: 'draw' }, { home: 't2', away: 't6', result: 'draw' }, { home: 't3', away: 't4', result: 'draw' }] },
              { round: 3, bye: null, matches: [{ home: 't1', away: 't6', result: 'draw' }, { home: 't2', away: 't4', result: 'draw' }, { home: 't3', away: 't5', result: 'draw' }] },
            ],
          },
        }),
        req('Single elim 6 teams + result -> 200 (byes for seeds 1 and 2)', 'POST', '/audit/v1/fixtures', { format: 'single_elim', teams: ['t1', 't2', 't3', 't4', 't5', 't6'], params: { third_place_match: true, results: [{ match_id: 'R1M2', winner: 't4' }] } }, 'R2M1 should be t1 vs t4'),
        req('Single elim bad winner -> 400 VALIDATION_ERROR', 'POST', '/audit/v1/fixtures', { format: 'single_elim', teams: ['t1', 't2', 't3', 't4'], params: { results: [{ match_id: 'R1M1', winner: 't3' }] } }),
        req('Double elim 8 teams with reset -> 200 (6 losers matches, GF1+GF2)', 'POST', '/audit/v1/fixtures', { format: 'double_elim', teams: ['t1', 't2', 't3', 't4', 't5', 't6', 't7', 't8'], params: { bracket_reset: true, results: [{ match_id: 'WR1M1', winner: 't1' }] } }),
        req('Unknown format -> 400 VALIDATION_ERROR', 'POST', '/audit/v1/fixtures', { format: 'knockout', teams: ['t1', 't2'] }),
      ],
    },
    {
      name: '4c. Standings',
      item: [
        req('Reset -> 200', 'POST', '/audit/v1/reset', {}),
        req('Register 3-team league -> 201', 'POST', '/audit/v1/leagues', {
          league_id: 'lg-st', sport_id: 'football', teams: ['A', 'B', 'C'],
          fixtures: [{ match_id: 's1', home: 'A', away: 'B' }, { match_id: 's2', home: 'B', away: 'C' }, { match_id: 's3', home: 'C', away: 'A' }],
          qualification: { spots: 1 }, lots_seed: 42,
        }),
        ...playMatch('s1', 'A', 'sg-a1'),
        ...playMatch('s2', 'B'),
        ...playMatch('s3', 'C'),
        req('Standings: 3-way tie on 3 pts -> 200 (resolved_by draw_lots)', 'GET', '/audit/v1/standings/lg-st', null, 'All on 3 points, H2H and diff equal, so the seeded draw of lots decides.'),
        req('Disallow A goal in s1 (compensation) -> 201', 'POST', '/audit/v1/events', { event_id: 'sg-comp', match_id: 's1', type: 'compensation', payload: { compensates: 'sg-a1', reason: 'VAR offside' } }),
        req('Standings recomputed -> 200 (B 4, C 3, A 1)', 'GET', '/audit/v1/standings/lg-st', null, 's1 is now 0-0: B first with 4 points.'),
        req('Standings unknown league -> 404 LEAGUE_NOT_FOUND', 'GET', '/audit/v1/standings/nope'),
      ],
    },
    {
      name: '5. Store checkout',
      item: [
        req('Reset with stock M=1 -> 200', 'POST', '/audit/v1/reset', { stock: { 'var-jersey-001-M': 1, 'var-jersey-001-L': 5 } }),
        req('Buy last M jersey -> 201 (receipt + pdf_base64)', 'POST', '/audit/v1/checkout', checkoutBody('ord-001', 'var-jersey-001-M', 'tok_success'), 'Send again unchanged -> 200 replay'),
        req('Second buyer, no stock -> 409 OUT_OF_STOCK', 'POST', '/audit/v1/checkout', checkoutBody('ord-002', 'var-jersey-001-M', 'tok_success')),
        req('Inventory M -> 200 stock 0 reserved 0', 'GET', '/audit/v1/inventory/var-jersey-001-M'),
        req('Declined card -> 402 PAYMENT_DECLINED', 'POST', '/audit/v1/checkout', checkoutBody('ord-003', 'var-jersey-001-L', 'tok_declined')),
        req('Capture fails -> 402 PAYMENT_CAPTURE_FAILED', 'POST', '/audit/v1/checkout', checkoutBody('ord-004', 'var-jersey-001-L', 'tok_capture_fail')),
        req('Inventory L -> 200 stock still 5', 'GET', '/audit/v1/inventory/var-jersey-001-L'),
        req('WELCOME10 discount -> 201 (discount 45000)', 'POST', '/audit/v1/checkout', { ...checkoutBody('ord-005', 'var-jersey-001-L', 'tok_success'), discount_code: 'WELCOME10' }),
        req('Bad discount -> 400 INVALID_DISCOUNT_CODE', 'POST', '/audit/v1/checkout', { ...checkoutBody('ord-006', 'var-jersey-001-L', 'tok_success'), discount_code: 'FREE' }),
        req('Unknown variant -> 404 VARIANT_NOT_FOUND', 'POST', '/audit/v1/checkout', checkoutBody('ord-007', 'nope', 'tok_success')),
      ],
    },
    {
      name: '6. RBAC + security',
      item: [
        {
          ...req('Get JWTs for 5 roles -> 200 (saves tokens)', 'POST', '/audit/v1/rbac-matrix'),
          event: [{
            listen: 'test',
            script: { type: 'text/javascript', exec: [
              'const t = pm.response.json().tokens;',
              'Object.keys(t).forEach(k => pm.collectionVariables.set(k, t[k]));',
            ] },
          }],
        },
        authed(req('P7 platform config as super_admin -> 200', 'GET', '/audit/v1/rbac/platform/config'), 'super_admin'),
        authed(req('P7 platform config as viewer -> 403', 'GET', '/audit/v1/rbac/platform/config'), 'viewer'),
        req('P7 with no token -> 401', 'GET', '/audit/v1/rbac/platform/config'),
        authed(req('P2 own league as organizer -> 200', 'POST', '/audit/v1/rbac/leagues/league-alpha-1/fixtures', {}), 'league_organizer'),
        authed(req('P2 other league as organizer -> 403', 'POST', '/audit/v1/rbac/leagues/league-alpha-2/fixtures', {}), 'league_organizer'),
        authed(req('P3 own club roster as manager -> 200', 'POST', '/audit/v1/rbac/clubs/club-alpha-1/roster', {}), 'club_manager'),
        authed(req('P6 foreign club as player -> 403', 'GET', '/audit/v1/rbac/clubs/club-beta-1'), 'player'),
        authed(req('P5 self as player -> 200', 'PATCH', '/audit/v1/rbac/players/player-alpha-1', {}), 'player'),
        req('Login as manager -> 200 token', 'POST', '/api/v1/auth/login', { email: 'manager@nascon.test', password: 'Nascon@26' }),
        req('Login wrong password -> 401', 'POST', '/api/v1/auth/login', { email: 'manager@nascon.test', password: 'nope' }),
        req('Ping (rate limited 100/10s) -> 200', 'GET', '/api/v1/ping', null, 'Use the Runner with 150 iterations to see 429 RATE_LIMITED'),
      ],
    },
    {
      name: '7. Roster + transfers',
      item: [
        req('Reset -> 200', 'POST', '/audit/v1/reset', {}),
        req('Setup roster scenario -> 201', 'POST', '/audit/v1/roster/setup', rosterSetup()),
        req('Transfer outside window -> 409 TRANSFER_WINDOW_CLOSED', 'POST', '/audit/v1/roster/transfer', transferBody('tr-001', { effective_date: '2026-10-05' })),
        req('Transfer only GK -> 409 MIN_POSITION_VIOLATION', 'POST', '/audit/v1/roster/transfer', transferBody('tr-002', { player_id: 'p1' })),
        req('Transfer p2 on last window day -> 201 deferred (live match)', 'POST', '/audit/v1/roster/transfer', transferBody('tr-003', { effective_date: '2026-09-30' }), 'Send again -> 200 replay'),
        req('Loan p3 to sq-a -> 201', 'POST', '/audit/v1/roster/transfer', transferBody('tr-004', { player_id: 'p3', type: 'loan', from_squad_id: 'sq-b', to_squad_id: 'sq-a', effective_date: '2026-09-10', loan_end_date: '2026-12-31' })),
        req('Release loaned p3 -> 409 PLAYER_ON_LOAN', 'POST', '/audit/v1/roster/transfer', transferBody('tr-005', { player_id: 'p3', type: 'release', from_squad_id: 'sq-a', to_squad_id: null })),
        req('History p3 during loan -> current sq-a', 'GET', '/audit/v1/roster/history/p3?as_of=2026-11-01'),
        req('History p3 after loan -> back to sq-b + loan_return', 'GET', '/audit/v1/roster/history/p3?as_of=2027-01-05'),
      ],
    },
    {
      name: '8. Offline sync',
      item: [
        req('Reset -> 200', 'POST', '/audit/v1/reset', {}),
        req('Setup roster scenario -> 201', 'POST', '/audit/v1/roster/setup', rosterSetup()),
        req('Init match m1 -> 201', 'POST', '/audit/v1/events', { event_id: 'i1', match_id: 'm1', type: 'match_init', payload: { sport_id: 'football', home_team_id: 't1', away_team_id: 't2' } }),
        req('Start m1 -> 201', 'POST', '/audit/v1/events', { event_id: 's1', match_id: 'm1', type: 'match_start', payload: {} }),
        req('Sync queued actions -> 200 (applied + rejected)', 'POST', '/audit/v1/offline-sync', {
          device_id: 'dev-1',
          actions: [
            { action_id: 'a1', type: 'score_event', queued_at: '2026-10-17T11:00:00Z', base_version: 2, payload: { event_id: 'evt-9', match_id: 'm1', type: 'score', payload: { team_id: 't1', event_type: 'goal' } } },
            { action_id: 'a2', type: 'roster_transfer', queued_at: '2026-10-17T11:01:00Z', base_version: 0, payload: transferBody('rq-1', { effective_date: '2026-09-15' }) },
            { action_id: 'a3', type: 'roster_transfer', queued_at: '2026-10-17T11:02:00Z', base_version: 0, payload: transferBody('rq-2', { player_id: 'p1', effective_date: '2026-09-15' }) },
          ],
        }, 'Send again -> every action is duplicate'),
      ],
    },
  ],
};

function rosterSetup() { return {
  league: { league_id: 'lg-r1', tenant_id: 'tenant-alpha', sport_id: 'football', transfer_window: { open: '2026-09-01', close: '2026-09-30' }, max_squad_size: 4, required_positions: { gk: 1 } },
  squads: [
    { squad_id: 'sq-a', club_id: 'club-a', tenant_id: 'tenant-alpha', name: 'A' },
    { squad_id: 'sq-b', club_id: 'club-b', tenant_id: 'tenant-alpha', name: 'B' },
  ],
  players: [
    { player_id: 'p1', name: 'Ali', position: 'gk', squad_id: 'sq-a', role: 'captain' },
    { player_id: 'p2', name: 'Bilal', position: 'df', squad_id: 'sq-a', role: 'starter' },
    { player_id: 'p3', name: 'Danish', position: 'fw', squad_id: 'sq-b', role: 'starter' },
  ],
  matches_in_progress: [{ match_id: 'm-live', home_squad_id: 'sq-a', away_squad_id: 'sq-b' }],
}; }

function transferBody(requestId, extra) {
  return { request_id: requestId, league_id: 'lg-r1', player_id: 'p2', type: 'transfer', from_squad_id: 'sq-a', to_squad_id: 'sq-b', effective_date: '2026-09-15', loan_end_date: null, reason: 'Tactical move', requested_by: 'user-77', ...extra };
}

// start, one goal for `scorer`, end -- for a league fixture.
function playMatch(matchId, scorer, goalId) {
  return [
    req(`${matchId}: start -> 201`, 'POST', '/audit/v1/events', { event_id: `${matchId}-start`, match_id: matchId, type: 'match_start', payload: {} }),
    req(`${matchId}: goal ${scorer} -> 201`, 'POST', '/audit/v1/events', { event_id: goalId || `${matchId}-goal`, match_id: matchId, type: 'score', payload: { team_id: scorer, event_type: 'goal' } }),
    req(`${matchId}: end -> 201`, 'POST', '/audit/v1/events', { event_id: `${matchId}-end`, match_id: matchId, type: 'match_end', payload: {} }),
  ];
}

function checkoutBody(orderId, variantId, token) {
  return { order_id: orderId, customer_id: 'cust-001', items: [{ variant_id: variantId, quantity: 1 }], discount_code: null, payment: { token } };
}

function authed(item, role) {
  item.request.header.push({ key: 'Authorization', value: `Bearer {{${role}}}` });
  return item;
}

fs.writeFileSync(path.join(__dirname, 'NaSCon.postman_collection.json'), JSON.stringify(collection, null, 2));
console.log('written');
