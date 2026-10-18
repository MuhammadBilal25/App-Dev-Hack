#!/usr/bin/env sh
# Runs the backend unit tests with line coverage and regenerates COVERAGE.json.
# Needs Node.js 20+. Without a local Node it runs the same thing inside node:20-alpine.
set -e
cd "$(dirname "$0")"

if ! command -v node >/dev/null 2>&1; then
  exec docker run --rm -v "$PWD":/app -w /app node:20-alpine sh run_tests.sh
fi

[ -d node_modules/c8 ] || npm ci --no-audit --no-fund

npx c8 --reporter=text --reporter=json-summary --reporter=html node --test tests/*.test.js scenario2/backend/tests/*.test.js
node scripts/coverage-areas.js
echo "HTML coverage report: coverage/index.html"
