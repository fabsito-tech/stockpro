#!/usr/bin/env bash
# Local-only integration test. Needs psql, a disposable Supabase local DB URL, and applied local migration.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB_URL="${STOCKPRO_TEST_DATABASE_URL:-}"
if [[ -z "$DB_URL" ]]; then echo 'Set STOCKPRO_TEST_DATABASE_URL to a local disposable Supabase Postgres URL.' >&2; exit 2; fi
HOST="$(python3 - "$DB_URL" <<'PY'
import sys, urllib.parse
print(urllib.parse.urlparse(sys.argv[1]).hostname or '')
PY
)"
case "$HOST" in localhost|127.0.0.1|::1) ;; *) echo "Refusing non-local DB host: $HOST" >&2; exit 2;; esac
command -v psql >/dev/null || { echo 'psql is required.' >&2; exit 2; }
TMP="$(mktemp -d)"
cleanup() {
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/tests/concurrency_cleanup.sql" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT
psql "$DB_URL" -X -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/tests/concurrency_seed.sql"
run_sale() {
  local key="$1"
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -q -c "select set_config('request.jwt.claim.sub','d0000000-0000-4000-8000-000000000001',false); set role authenticated; select * from public.record_sale('30000000-0000-4000-8000-000000000003','$key','[{\"variant_id\":\"33330000-0000-4000-8000-000000000003\",\"quantity\":1}]'::jsonb,null);" >"$TMP/$key.out" 2>"$TMP/$key.err"
}
run_sale race-sale-key-0001 & PID_A=$!
run_sale race-sale-key-0002 & PID_B=$!
set +e
wait "$PID_A"; RC_A=$?
wait "$PID_B"; RC_B=$?
set -e
if ! { [[ $RC_A -eq 0 && $RC_B -ne 0 ]] || [[ $RC_B -eq 0 && $RC_A -ne 0 ]]; }; then
  echo "FAIL: expected exactly one successful concurrent sale (exit codes $RC_A, $RC_B)" >&2
  cat "$TMP"/*.err >&2 || true
  exit 1
fi
STOCK="$(psql "$DB_URL" -X -v ON_ERROR_STOP=1 -Atqc "select stock_quantity from public.product_variants where variant_id='33330000-0000-4000-8000-000000000003'")"
SALES="$(psql "$DB_URL" -X -v ON_ERROR_STOP=1 -Atqc "select count(*) from public.sales where store_id='30000000-0000-4000-8000-000000000003'")"
MOVES="$(psql "$DB_URL" -X -v ON_ERROR_STOP=1 -Atqc "select count(*) from public.stock_movements where store_id='30000000-0000-4000-8000-000000000003'")"
if [[ "$STOCK" != 0 || "$SALES" != 1 || "$MOVES" != 1 ]]; then
  echo "FAIL: expected stock=0, sales=1, movements=1; got $STOCK/$SALES/$MOVES" >&2; exit 1
fi
echo 'PASS: two overlapping sales for the final unit produced exactly one sale; stock=0, one sale, one movement.'
if [[ $RC_A -eq 0 ]]; then cat "$TMP/race-sale-key-0001.out"; else cat "$TMP/race-sale-key-0002.out"; fi
