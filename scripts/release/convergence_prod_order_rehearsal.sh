#!/bin/bash
# =============================================================================
# scripts/release/convergence_prod_order_rehearsal.sh
#
# CONVERGENCE REHEARSAL for release/convergence-135: the production-aligned
# 135-version line (admin/operating-console) with the payments RC's four
# migrations (20260906100000..130000) applied on top.
#
# Proves three things, LOCALLY, applying nothing anywhere else:
#
#   FRESH  a fresh database replayed in the CANONICAL order the Supabase CLI
#          uses (LC_ALL=C filename sort) — this is what CI's `supabase start`
#          and any fresh environment will do. Here 110..114 precede 115..120.
#
#   PROD   production's ACTUAL order, which is not the filename sort:
#            000..075 → the four 2026-07 website-form migrations → 076..092 →
#            20260902003623 → 093..109        (= the 124-version line)
#          then the admin/ops console        115..120  (deployed 2026-09-08)
#          then the signing/door ceremony    110..114  (applied  2026-09-09)
#          = the 135 rows the production ledger holds today. The four payment
#          migrations are then applied on top, exactly as the release would.
#
#   SAME   the two orders converge: identical Gate-2 census AND identical
#          function-definition hash. That is the order-independence proof —
#          without it, a fresh environment and production would diverge.
#
# LOCAL ONLY. Loopback Postgres, database name must contain 'rehears'.
# Applies NOTHING to any Supabase project. Exit 1 on any FAIL.
# =============================================================================
set -uo pipefail
export LC_ALL=C
unset SUPABASE_DB_URL SUPABASE_DB_PASSWORD SUPABASE_ACCESS_TOKEN DATABASE_URL \
      POSTGRES_URL PGSERVICE PGSERVICEFILE PGPASSFILE PGDATABASE 2>/dev/null
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}" PGPORT="${REHEARSAL_PGPORT:-5432}" PGUSER="${REHEARSAL_PGUSER:-postgres}"
case "$PGHOST" in 127.0.0.1|localhost|/*) ;; *) echo "refusing: PGHOST must be loopback"; exit 2;; esac
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
FRESH="${1:-snatchit_converge_fresh_rehears}"
PROD="${2:-snatchit_converge_prod_rehears}"
for d in "$FRESH" "$PROD"; do case "$d" in *rehears*) ;; *) echo "refusing: db name must contain 'rehears'"; exit 2;; esac; done
OUT="${CONV_OUT:-${TMPDIR:-/tmp}/convergence_rehearsal}"; mkdir -p "$OUT"; : > "$OUT/apply.err"
FAILS=0; PASSES=0
ok()  { PASSES=$((PASSES+1)); echo "PASS  $1"; }
bad() { FAILS=$((FAILS+1));  echo "FAIL  $1  [$2]"; }
q()   { psql -X -qtA -d "$1" -v ON_ERROR_STOP=1 -c "$2" 2>&1; }
check(){ local db="$1" name="$2" sql="$3" want="$4"; local got; got=$(q "$db" "$sql" | tr -d '[:space:]'); [ "$got" = "$want" ] && ok "$name" || bad "$name" "want=$want got=$(printf '%s' "$got" | head -c 200)"; }
apply(){ local db="$1" f="$2" base; base=$(basename "$f")
  if [ "$base" = "014_frequent_cron_schedules.sql" ]; then
    grep -v '^create extension if not exists pg_' "$f" | psql -X -q -d "$db" -v ON_ERROR_STOP=1 -f - >/dev/null 2>>"$OUT/apply.err" || { echo "APPLY FAIL $base ($db)"; tail -3 "$OUT/apply.err"; exit 1; }
  else
    psql -X -q -d "$db" -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>>"$OUT/apply.err" || { echo "APPLY FAIL $base ($db)"; tail -3 "$OUT/apply.err"; exit 1; }
  fi; }
numeric_between(){ # $1=lo-exclusive $2=hi-inclusive ; echoes matching migration paths in LC_ALL=C order
  local lo="$1" hi="$2" f v
  for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do
    v=$(basename "$f"); v=${v%%_*}
    [ ${#v} -le 4 ] || continue
    if [ -n "$lo" ]; then [[ "$v" > "$lo" ]] || continue; fi
    [[ ! "$v" > "$hi" ]] || continue
    echo "$f"
  done; }
CENSUS="select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r')||'|'||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e'))||'|'||(select count(*) from pg_policies where schemaname='public')||'|'||(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)"
FNHASH="select md5(string_agg(pg_get_functiondef(p.oid), chr(10) order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','kernel','ops') and p.prokind='f' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')"
PAY="supabase/migrations/20260906100000_checkout_reservation_authority.sql supabase/migrations/20260906110000_settle_verified_payment.sql supabase/migrations/20260906120000_payout_attempts_and_refund_monotonic.sql supabase/migrations/20260906130000_deletion_sweep_live_rail_obligations.sql"
TIX="supabase/migrations/20260909000000_kernel_my_tickets_read.sql"

echo "=== FRESH: canonical LC_ALL=C replay of the whole converged chain → $FRESH"
dropdb --if-exists "$FRESH" 2>/dev/null; createdb "$FRESH" || exit 1
psql -X -q -d "$FRESH" -v ON_ERROR_STOP=1 -f scripts/local/replay_shim.sql >/dev/null 2>&1 || { echo "SHIM FAIL"; exit 1; }
nf=0; for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do apply "$FRESH" "$f"; nf=$((nf+1)); done
psql -X -q -d "$FRESH" -v ON_ERROR_STOP=1 -f supabase/ci/parity_grants.sql >/dev/null 2>&1 || { echo "parity grants FAIL"; exit 1; }
check "$FRESH" "F1 every migration in the converged tree applied (140 = 135 production + 4 payments + 1 tickets)" "select $nf" "140"
check "$FRESH" "F2 Gate-2 census = 30|88|37|33 (converged EXPECT_*)" "$CENSUS" "30|88|37|33"
check "$FRESH" "F3 payments objects present (payout_attempts, payment_refunds, account_deletions)" "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname in ('payout_attempts','payment_refunds','account_deletions')" "3"
check "$FRESH" "F4 ops console present (115-120)" "select count(*)>=90 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops'" "t"
check "$FRESH" "F5 119 guard present (admin line)" "select count(*) from pg_proc where proname='guard_listing_seller_not_blocked'" "1"
check "$FRESH" "F6 settlement contract present (payments P2)" "select count(*) from pg_proc where proname='settle_verified_payment'" "1"
check "$FRESH" "F7 tickets read present, zero-argument, authenticated-only" "select count(*)=1 and bool_and(p.pronargs=0 and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='get_my_tickets'" "t"
FRESH_FN=$(q "$FRESH" "$FNHASH"); echo "      fresh function hash $FRESH_FN"

echo
echo "=== PROD: production's real order (135) then the payment migrations → $PROD"
dropdb --if-exists "$PROD" 2>/dev/null; createdb "$PROD" || exit 1
psql -X -q -d "$PROD" -v ON_ERROR_STOP=1 -f scripts/local/replay_shim.sql >/dev/null 2>&1 || { echo "SHIM FAIL"; exit 1; }
np=0
for f in $(numeric_between "" "075"); do apply "$PROD" "$f"; np=$((np+1)); done
for f in supabase/migrations/20260714190445_investor_leads_website_form.sql \
         supabase/migrations/20260730212326_ambassador_applications_website_form.sql \
         supabase/migrations/20260730212406_ambassador_applications_fix_search_path.sql \
         supabase/migrations/20260731224653_venue_partnership_inquiries_website_form.sql; do apply "$PROD" "$f"; np=$((np+1)); done
for f in $(numeric_between "075" "092"); do apply "$PROD" "$f"; np=$((np+1)); done
apply "$PROD" supabase/migrations/20260902003623_admin_relist_listing_rpc.sql; np=$((np+1))
for f in $(numeric_between "092" "109"); do apply "$PROD" "$f"; np=$((np+1)); done
check "$PROD" "P1 the 124-version production line reproduced in production order" "select $np" "124"
check "$PROD" "P2 census at 109 = 27|70|37|26 (production before the admin/native line)" "$CENSUS" "27|70|37|26"
# admin/ops console first (deployed 2026-09-08), then the signing/door ceremony (applied 2026-09-09)
for f in $(numeric_between "114" "120"); do apply "$PROD" "$f"; np=$((np+1)); done
check "$PROD" "P3 115-120 applied (ops console) → 130 versions" "select $np" "130"
for f in $(numeric_between "109" "114"); do apply "$PROD" "$f"; np=$((np+1)); done
check "$PROD" "P4 110-114 applied AFTER 115-120, as production did → 135 versions" "select $np" "135"
check "$PROD" "P5 census at the production tip = 27|71|37|27 (109 + 119's guard and trigger)" "$CENSUS" "27|71|37|27"
psql -X -q -d "$PROD" -v ON_ERROR_STOP=1 -f supabase/ci/parity_grants.sql >/dev/null 2>&1 || { echo "parity grants FAIL"; exit 1; }
for f in $PAY; do apply "$PROD" "$f"; np=$((np+1)); done
check "$PROD" "P6 the four payment migrations applied on the production tip → 139" "select $np" "139"
check "$PROD" "P6b census after the payment migrations = 30|87|37|33" "$CENSUS" "30|87|37|33"
for f in $TIX; do apply "$PROD" "$f"; np=$((np+1)); done
check "$PROD" "P7 the tickets migration applied last → 140" "select $np" "140"
check "$PROD" "P8 census after the release = 30|88|37|33" "$CENSUS" "30|88|37|33"
PROD_FN=$(q "$PROD" "$FNHASH"); echo "      prod-order function hash $PROD_FN"

echo
echo "=== SAME: the two orders converge"
[ -n "$FRESH_FN" ] && [ "$FRESH_FN" = "$PROD_FN" ] && ok "S1 function definitions identical across both orders (order-independent chain)" \
  || bad "S1 function definitions identical across both orders" "fresh=$FRESH_FN prod=$PROD_FN"
FC=$(q "$FRESH" "$CENSUS"); PC=$(q "$PROD" "$CENSUS")
[ "$FC" = "$PC" ] && ok "S2 Gate-2 census identical across both orders ($FC)" || bad "S2 census identical" "fresh=$FC prod=$PC"

echo
echo "PASS=$PASSES FAIL=$FAILS"
[ "$FAILS" -eq 0 ] || exit 1
