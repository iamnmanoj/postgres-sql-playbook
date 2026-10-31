#!/usr/bin/env bash
# Drop and rebuild a database from schema + seed data.
#   scripts/reset.sh              -> rebuilds "shopsphere"
#   scripts/reset.sh my_copy      -> rebuilds "my_copy"
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${1:-${DB:-shopsphere}}"

docker compose up -d --wait db >/dev/null 2>&1

run() { docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

echo "==> Recreating database $DB"
run -d postgres -c "DROP DATABASE IF EXISTS \"$DB\" WITH (FORCE);"
run -d postgres -c "CREATE DATABASE \"$DB\";"

echo "==> Building schema"
run -d "$DB" -f /playbook/chapters/01_ddl_schema/schema.sql

echo "==> Loading seed data (takes a few seconds)"
run -d "$DB" -f /playbook/chapters/02_seed_data/seed.sql

echo "==> Done. Connect with: scripts/psql.sh"
