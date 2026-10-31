#!/usr/bin/env bash
# Open psql inside the container (interactive) or run a file / command.
#   scripts/psql.sh                          -> interactive shell on $DB (default: shopsphere)
#   scripts/psql.sh -f /playbook/chapters/03_select_filtering/queries.sql
#   DB=mydb scripts/psql.sh -c 'SELECT 1'
# Paths passed with -f are paths INSIDE the container: the repo is mounted at /playbook.
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${DB:-shopsphere}"
TTY_FLAG="-T"
if [ -t 0 ] && [ -t 1 ]; then TTY_FLAG=""; fi
exec docker compose exec $TTY_FLAG db psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 "$@"
