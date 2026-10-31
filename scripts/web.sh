#!/usr/bin/env bash
# Start the interactive web app (and the database) in Docker, then open http://localhost:3000
#   scripts/web.sh            build (if needed) and start
#   scripts/web.sh --rebuild  force a rebuild of the web image
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--rebuild" ]; then docker compose build web; fi
docker compose up -d --wait db >/dev/null 2>&1
# first run: build the database if it doesn't exist yet
if ! docker compose exec -T db psql -U postgres -lqt | cut -d'|' -f1 | grep -qw shopsphere \
   || ! docker compose exec -T db psql -U postgres -d shopsphere -tAc 'SELECT 1 FROM sales.orders LIMIT 1' >/dev/null 2>&1; then
  scripts/reset.sh
fi
docker compose up -d --build web
echo "==> ShopSphere SQL Playbook web app: http://localhost:${WEB_PORT:-3000}"
