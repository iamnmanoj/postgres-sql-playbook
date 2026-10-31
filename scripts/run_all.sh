#!/usr/bin/env bash
# Rebuild the database, then execute every chapter's queries.sql and solutions.sql.
# Stops at the first SQL error. Used to verify the whole playbook still works.
#   scripts/run_all.sh                 -> all chapters
#   scripts/run_all.sh 09 12           -> only chapters 09 and 12 (after a reset)
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${DB:-shopsphere}"

scripts/reset.sh "$DB"

run() { docker compose exec -T db psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q -o /dev/null "$@"; }

wanted=("$@")
for dir in chapters/*/; do
  ch="$(basename "$dir")"
  num="${ch%%_*}"
  if [ ${#wanted[@]} -gt 0 ] && [[ ! " ${wanted[*]} " =~ " ${num} " ]]; then continue; fi
  for f in queries.sql solutions.sql; do
    if [ -f "$dir$f" ]; then
      printf '%-45s' "$ch/$f"
      start=$(date +%s)
      run -f "/playbook/$dir$f" 2>/tmp/run_all_err.log || { echo "FAILED"; cat /tmp/run_all_err.log; exit 1; }
      echo "ok ($(( $(date +%s) - start ))s)"
    fi
  done
done
echo "All chapters executed successfully."
