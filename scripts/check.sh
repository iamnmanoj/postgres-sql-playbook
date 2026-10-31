#!/usr/bin/env bash
# Run one or more chapter SQL files twice (proves they are idempotent).
#   scripts/check.sh 05_aggregation/queries.sql 05_aggregation/solutions.sql
set -uo pipefail
cd "$(dirname "$0")/.."
DB="${DB:-shopsphere}"
status=0
for f in "$@"; do
  for pass in 1 2; do
    if out=$(docker compose exec -T db psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q -o /dev/null \
               -f "/playbook/chapters/$f" 2>&1); then
      echo "ok    pass $pass  $f"
    else
      echo "FAIL  pass $pass  $f"; echo "$out" | grep -v -E 'NOTICE|DETAIL|drop cascades' | head -20; status=1; break
    fi
  done
done
exit $status
