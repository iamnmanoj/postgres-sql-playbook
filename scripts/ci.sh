#!/usr/bin/env bash
# Full verification pipeline — used by GitHub Actions and runnable locally.
#   1. web app unit tests + syntax check
#   2. KEYWORD_INDEX.md / GLOSSARY.md are up to date with the chapter files
#   3. every chapter (queries + solutions) runs against a freshly built database
#   4. the web app runs every cell and grades every exercise end-to-end
# Requires: Docker (Compose v2), Node >= 20 with `npm ci` done in webapp/, Python 3.
set -euo pipefail
cd "$(dirname "$0")/.."
CI_WEB_PORT="${CI_WEB_PORT:-3100}"

echo "==> [1/4] web app unit tests & syntax check"
(cd webapp && npm test --silent && npm run --silent check)

echo "==> [2/4] generated docs are up to date"
python3 scripts/build_index.py
if ! git diff --quiet -- KEYWORD_INDEX.md GLOSSARY.md; then
  echo "KEYWORD_INDEX.md / GLOSSARY.md are stale: run python3 scripts/build_index.py and commit the result." >&2
  git --no-pager diff --stat -- KEYWORD_INDEX.md GLOSSARY.md >&2
  exit 1
fi

echo "==> [3/4] playbook chapters"
scripts/run_all.sh

echo "==> [4/4] web app end-to-end"
(cd webapp && PORT="$CI_WEB_PORT" HOST=127.0.0.1 node server.js) > /tmp/playbook-web-ci.log 2>&1 &
WEB_PID=$!
trap 'kill "$WEB_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  curl -sf "http://127.0.0.1:$CI_WEB_PORT/api/health" >/dev/null && break
  sleep 1
done
(cd webapp && node test/e2e.mjs "http://127.0.0.1:$CI_WEB_PORT")

echo "==> CI passed"
