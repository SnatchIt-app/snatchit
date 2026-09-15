#!/bin/bash
# =============================================================================
# scripts/review/d_candidate_rehearsal.sh — Claude D's integrated-chain rehearsal for a release candidate.
#
# A copy-and-extension of A's certified scripts/release/convergence_prod_order_rehearsal.sh (which stays
# untouched). Runs against the TREE UNDER TEST (a detached worktree of A's snapshot), LOCAL ONLY:
#
#   FRESH    whole tree in canonical LC_ALL=C order; Gate-2 census vs that tree's ci.yml EXPECT_*;
#            expected_grants.txt diff after parity_grants.sql; grant-decision manifest assertion
#   PGTAP    the certified rehearsal_reset.sh + rehearsal_test.sh on a separate database (TOTAL + RESULT)
#   PROD     production's real 135-row order, then the release chain in RELEASE_ORDER; census + function-hash
#            convergence with FRESH
#   ROLLBACK for each release migration that ships a rollback: apply it immediately after the migration on a
#            clone and diff catalog identity against the pre-migration clone (0 lines, or the rollback header's
#            declared exceptions — the reviewer classifies them, the script only reports)
#
#   usage: scripts/review/d_candidate_rehearsal.sh <tree-under-test> [out-dir]
#   env:   RELEASE_ORDER  space-separated migration basenames applied after production's 135, in order.
#                         Default: the four payment migrations, the tickets read, then every numbered
#                         migration > 120 ascending, then any other tree migration not yet applied (flagged).
#          REHEARSAL_PGHOST/PGPORT/PGUSER as the certified harness (loopback only).
# Applies NOTHING to any Supabase project. Exit 1 on any FAIL.
# =============================================================================
set -uo pipefail
export LC_ALL=C
unset SUPABASE_DB_URL SUPABASE_DB_PASSWORD SUPABASE_ACCESS_TOKEN DATABASE_URL POSTGRES_URL PGSERVICE PGSERVICEFILE PGPASSFILE PGDATABASE 2>/dev/null
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}" PGPORT="${REHEARSAL_PGPORT:-5432}" PGUSER="${REHEARSAL_PGUSER:-postgres}"
case "$PGHOST" in 127.0.0.1|localhost|::1|/*) ;; *) echo "refusing: PGHOST must be loopback"; exit 2;; esac
TREE="$(cd "${1:?usage: $0 <tree-under-test> [out-dir]}" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${2:-${TMPDIR:-/tmp}/d_candidate_rehearsal}"; mkdir -p "$OUT"; : > "$OUT/apply.err"
FRESH=d_cand_fresh_rehears; PROD=d_cand_prod_rehears; TAPDB=d_cand_tap_rehears
cd "$TREE" || exit 2
HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
FAILS=0; PASSES=0; WARNS=0
ok()   { PASSES=$((PASSES+1)); echo "PASS  $1"; }
bad()  { FAILS=$((FAILS+1));  echo "FAIL  $1  [$2]"; }
warn() { WARNS=$((WARNS+1));  echo "WARN  $1"; }
q()    { psql -X -qtA -d "$1" -v ON_ERROR_STOP=1 -c "$2" 2>&1; }
ident(){ # $1=db $2=outfile — refuses an empty or errored snapshot (a vacuous diff is a FAIL, not a PASS)
  if ! psql -X -qtA -d "$1" -v ON_ERROR_STOP=1 -f "$HERE/catalog_identity.sql" > "$2" 2> "$2.err"; then bad "identity snapshot of $1" "$(head -1 "$2.err")"; return 1; fi
  [ "$(wc -l < "$2" | tr -d ' ')" -gt 1000 ] || { bad "identity snapshot of $1 is implausibly small" "$(wc -l < "$2") lines"; return 1; }; }
check(){ local got; got=$(q "$1" "$3" | tr -d '[:space:]'); [ "$got" = "$4" ] && ok "$2" || bad "$2" "want=$4 got=$(printf '%s' "$got" | head -c 200)"; }
apply(){ local db="$1" f="$2" base; base=$(basename "$f")
  if [ "$base" = "014_frequent_cron_schedules.sql" ]; then
    grep -v '^create extension if not exists pg_' "$f" | psql -X -q -d "$db" -v ON_ERROR_STOP=1 -f - >/dev/null 2>>"$OUT/apply.err" || { echo "APPLY FAIL $base ($db)"; tail -3 "$OUT/apply.err"; exit 1; }
  else
    psql -X -q -d "$db" -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>>"$OUT/apply.err" || { echo "APPLY FAIL $base ($db)"; tail -3 "$OUT/apply.err"; exit 1; }
  fi; }
numeric_between(){ local lo="$1" hi="$2" f v
  for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do
    v=$(basename "$f"); v=${v%%_*}; [ ${#v} -le 4 ] || continue
    if [ -n "$lo" ]; then [[ "$v" > "$lo" ]] || continue; fi
    [[ ! "$v" > "$hi" ]] || continue; echo "$f"
  done; }
yml(){ grep -E "^[[:space:]]*$1:[[:space:]]*[0-9]+" .github/workflows/ci.yml | head -1 | grep -oE '[0-9]+$'; }
CENSUS="select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r')||'|'||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e'))||'|'||(select count(*) from pg_policies where schemaname='public')||'|'||(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)"
FNHASH="select md5(string_agg(pg_get_functiondef(p.oid), chr(10) order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','kernel','ops','notify','catalog','venue') and p.prokind='f' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')"
GRANTS="select grantee, table_name, string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants where table_schema='public' and grantee in ('anon','authenticated','service_role') group by grantee, table_name order by grantee, table_name"
EXPECT="$(yml EXPECT_TABLES)|$(yml EXPECT_FUNCS)|$(yml EXPECT_POLICIES)|$(yml EXPECT_TRIGGERS)"
TOTAL_FILES=$(ls supabase/migrations/*.sql | wc -l | tr -d ' ')
echo "tree $TREE @ $HEAD · $TOTAL_FILES migration files · ci.yml EXPECT_* = $EXPECT · out $OUT"

echo; echo "=== FRESH: canonical LC_ALL=C replay → $FRESH"
dropdb --if-exists "$FRESH" 2>/dev/null; createdb "$FRESH" || exit 1
psql -X -q -d "$FRESH" -v ON_ERROR_STOP=1 -f scripts/local/replay_shim.sql >/dev/null 2>&1 || { echo "SHIM FAIL"; exit 1; }
nf=0; for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do apply "$FRESH" "$f"; nf=$((nf+1)); done
check "$FRESH" "F1 every migration file applied ($TOTAL_FILES)" "select $nf" "$TOTAL_FILES"
psql -X -q -d "$FRESH" -v ON_ERROR_STOP=1 -f supabase/ci/parity_grants.sql >/dev/null 2>>"$OUT/apply.err" || bad "F2 parity_grants.sql applies" "see apply.err"
check "$FRESH" "F3 Gate-2 census = ci.yml EXPECT_* ($EXPECT)" "$CENSUS" "$EXPECT"
psql -X -qtA -F'|' -d "$FRESH" -c "$GRANTS" | sed 's/[[:space:]]*$//' | sort > "$OUT/actual_grants.txt"
if diff -u supabase/ci/expected_grants.txt "$OUT/actual_grants.txt" > "$OUT/grants.diff"; then ok "F4 grant matrix = expected_grants.txt ($(wc -l < supabase/ci/expected_grants.txt | tr -d ' ') rows)"
else warn "F4 grant matrix differs from expected_grants.txt ($(grep -cE '^[-+][a-z]' "$OUT/grants.diff") lines, $OUT/grants.diff) — local shim lacks Supabase default ACLs; CI is authoritative"; fi
if psql -X -q -d "$FRESH" -v ON_ERROR_STOP=1 -f supabase/ci/assert_public_table_grant_decisions.sql > "$OUT/manifest.out" 2>&1; then ok "F5 grant-decision manifest assertion"; else bad "F5 grant-decision manifest assertion" "$(tail -2 "$OUT/manifest.out" | tr '\n' ' ')"; fi
FRESH_FN=$(q "$FRESH" "$FNHASH")

echo; echo "=== PGTAP: certified harness → $TAPDB"
bash scripts/rehearsal_reset.sh "$TAPDB" > "$OUT/tap_reset.log" 2>&1 || bad "T0 rehearsal_reset" "$(tail -2 "$OUT/tap_reset.log" | tr '\n' ' ')"
bash scripts/rehearsal_test.sh "$TAPDB" > "$OUT/tap.log" 2>&1; trc=$?
TOT=$(grep -E '^TOTAL ' "$OUT/tap.log" | tail -1); RES=$(grep -E 'RESULT:' "$OUT/tap.log" | tail -1)
[ $trc -eq 0 ] && ok "T1 pgTAP $TOT · $RES" || bad "T1 pgTAP" "$TOT · $RES (per-file lines: $OUT/tap.log)"

echo; echo "=== PROD: production's 135 order, then the release chain → $PROD"
dropdb --if-exists "$PROD" 2>/dev/null; createdb "$PROD" || exit 1
psql -X -q -d "$PROD" -v ON_ERROR_STOP=1 -f scripts/local/replay_shim.sql >/dev/null 2>&1 || { echo "SHIM FAIL"; exit 1; }
APPLIED="$OUT/applied.txt"; : > "$APPLIED"
papply(){ apply "$PROD" "$1"; basename "$1" >> "$APPLIED"; }
for f in $(numeric_between "" "075"); do papply "$f"; done
for b in 20260714190445_investor_leads_website_form.sql 20260730212326_ambassador_applications_website_form.sql \
         20260730212406_ambassador_applications_fix_search_path.sql 20260731224653_venue_partnership_inquiries_website_form.sql; do papply "supabase/migrations/$b"; done
for f in $(numeric_between "075" "092"); do papply "$f"; done
papply supabase/migrations/20260902003623_admin_relist_listing_rpc.sql
for f in $(numeric_between "092" "109"); do papply "$f"; done
for f in $(numeric_between "114" "120"); do papply "$f"; done
for f in $(numeric_between "109" "114"); do papply "$f"; done
check "$PROD" "P1 production's 135-row line reproduced in production order" "select $(wc -l < "$APPLIED" | tr -d ' ')" "135"
psql -X -q -d "$PROD" -v ON_ERROR_STOP=1 -f supabase/ci/parity_grants.sql >/dev/null 2>>"$OUT/apply.err" || bad "P2 parity_grants.sql applies" "see apply.err"
if [ -z "${RELEASE_ORDER:-}" ]; then
  RELEASE_ORDER="20260906100000_checkout_reservation_authority.sql 20260906110000_settle_verified_payment.sql 20260906120000_payout_attempts_and_refund_monotonic.sql 20260906130000_deletion_sweep_live_rail_obligations.sql 20260909000000_kernel_my_tickets_read.sql"
  for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do b=$(basename "$f"); v=${b%%_*}; [ ${#v} -le 4 ] && [[ "$v" > "120" ]] && RELEASE_ORDER="$RELEASE_ORDER $b"; done
  for f in $(ls supabase/migrations/*.sql | LC_ALL=C sort); do b=$(basename "$f")
    grep -qxF "$b" "$APPLIED" && continue; case " $RELEASE_ORDER " in *" $b "*) continue;; esac
    warn "R0 $b is in the tree but in neither production's 135 nor the default release list — appended; confirm its production position with A"
    RELEASE_ORDER="$RELEASE_ORDER $b"
  done
fi
echo "      release order: $RELEASE_ORDER"
: > "$OUT/rollback.txt"
for b in $RELEASE_ORDER; do
  f="supabase/migrations/$b"; [ -f "$f" ] || { bad "R1 release migration present: $b" "missing from tree"; continue; }
  rb="supabase/rollbacks/${b%.sql}_rollback.sql"
  if [ -f "$rb" ]; then
    pre="d_cand_pre_rehears"; post="d_cand_rb_rehears"
    dropdb --if-exists "$pre" 2>/dev/null; createdb -T "$PROD" "$pre" || { bad "RB clone before $b" "createdb -T"; }
    papply "$f"
    dropdb --if-exists "$post" 2>/dev/null; createdb -T "$PROD" "$post"
    if psql -X -q -d "$post" -v ON_ERROR_STOP=1 -f "$rb" > "$OUT/rb_${b%.sql}.out" 2>&1; then
      ident "$pre" "$OUT/id_pre_${b%.sql}.txt" && ident "$post" "$OUT/id_post_${b%.sql}.txt" || { dropdb --if-exists "$pre" 2>/dev/null; dropdb --if-exists "$post" 2>/dev/null; continue; }
      n=$(diff "$OUT/id_pre_${b%.sql}.txt" "$OUT/id_post_${b%.sql}.txt" | grep -cE '^[<>]')
      diff "$OUT/id_pre_${b%.sql}.txt" "$OUT/id_post_${b%.sql}.txt" > "$OUT/rb_${b%.sql}.diff"
      echo "$b rollback identity diff lines=$n" >> "$OUT/rollback.txt"
      [ "$n" = "0" ] && ok "RB $b: rollback restores the pre-migration catalog exactly" \
                     || warn "RB $b: rollback leaves $n identity lines ($OUT/rb_${b%.sql}.diff) — classify against the rollback header"
    else
      bad "RB $b: rollback applies" "$(grep -m1 ERROR "$OUT/rb_${b%.sql}.out")"
    fi
    dropdb --if-exists "$pre" 2>/dev/null; dropdb --if-exists "$post" 2>/dev/null
  else
    papply "$f"; echo "$b no rollback file" >> "$OUT/rollback.txt"
  fi
done
check "$PROD" "P3 production order + release chain applied every tree migration ($TOTAL_FILES)" "select $(sort -u "$APPLIED" | wc -l | tr -d ' ')" "$TOTAL_FILES"
PROD_FN=$(q "$PROD" "$FNHASH")

echo; echo "=== SAME: the two orders converge"
[ -n "$FRESH_FN" ] && [ "$FRESH_FN" = "$PROD_FN" ] && ok "S1 function definitions identical across both orders" || bad "S1 function definitions identical" "fresh=$FRESH_FN prod=$PROD_FN"
FC=$(q "$FRESH" "$CENSUS"); PC=$(q "$PROD" "$CENSUS")
[ "$FC" = "$PC" ] && ok "S2 Gate-2 census identical across both orders ($FC)" || bad "S2 census identical" "fresh=$FC prod=$PC"
ident "$FRESH" "$OUT/id_fresh.txt"; ident "$PROD" "$OUT/id_prod.txt"
n=$(diff "$OUT/id_fresh.txt" "$OUT/id_prod.txt" | grep -cE '^[<>]'); diff "$OUT/id_fresh.txt" "$OUT/id_prod.txt" > "$OUT/same.diff"
[ "$n" = "0" ] && ok "S3 full catalog identity identical across both orders" || bad "S3 full catalog identity identical" "$n lines, $OUT/same.diff"

echo; echo "tree @ $HEAD  PASS=$PASSES FAIL=$FAILS WARN=$WARNS"
[ "$FAILS" -eq 0 ] || exit 1
