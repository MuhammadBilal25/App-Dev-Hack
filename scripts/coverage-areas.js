'use strict';

// Rolls c8's per-file line coverage up into the six graded backend areas and writes
// COVERAGE.json (Section 9.3). Run by ./run_tests.sh after the test suite.
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const summary = JSON.parse(fs.readFileSync(path.join(root, 'coverage', 'coverage-summary.json'), 'utf8'));

const AREAS = {
  fixtures: ['src/services/fixtures/', 'src/services/schedule.js'],
  scoring: ['src/services/scoring.js', 'src/services/sports.js', 'src/services/leagues.js', 'src/lib/crypto.js', 'src/services/matchOps.js'],
  standings: ['src/services/standings.js'],
  store: ['src/services/store.js', 'src/lib/pdf.js', 'src/services/merch.js', 'src/routes/shop.js'],
  roster: ['src/services/roster.js', 'src/services/offlineSync.js'],
  rbac: ['src/services/rbac.js', 'src/services/auth.js', 'src/middleware/rateLimit.js', 'src/services/platform.js', 'src/routes/admin.js'],
};

const out = {};
for (const [area, prefixes] of Object.entries(AREAS)) {
  let covered = 0;
  let total = 0;
  for (const [file, data] of Object.entries(summary)) {
    if (file === 'total') continue;
    const rel = path.relative(root, file).split(path.sep).join('/');
    if (!prefixes.some((p) => rel === p || (p.endsWith('/') && rel.startsWith(p)))) continue;
    covered += data.lines.covered;
    total += data.lines.total;
  }
  out[area] = total ? Math.floor((covered / total) * 1000) / 10 : 0;
}

fs.writeFileSync(path.join(root, 'COVERAGE.json'), JSON.stringify(out, null, 2) + '\n');
console.log('COVERAGE.json', JSON.stringify(out));
