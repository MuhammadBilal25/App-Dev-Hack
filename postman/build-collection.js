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
  ],
};

function checkoutBody(orderId, variantId, token) {
  return { order_id: orderId, customer_id: 'cust-001', items: [{ variant_id: variantId, quantity: 1 }], discount_code: null, payment: { token } };
}

function authed(item, role) {
  item.request.header.push({ key: 'Authorization', value: `Bearer {{${role}}}` });
  return item;
}

fs.writeFileSync(path.join(__dirname, 'NaSCon.postman_collection.json'), JSON.stringify(collection, null, 2));
console.log('written');
