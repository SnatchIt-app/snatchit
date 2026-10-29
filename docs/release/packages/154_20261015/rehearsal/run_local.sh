#!/bin/bash
# run_local.sh — the LOCALDB rehearsal of the 154/155/156 package (A, 2026-10-15). Every step's expected exit
# code is registered here BEFORE the run. DB: a154_pkg_rehears = clone of pkg151_rehears (ledger 164) + 152's
# executed apply request (sha256 ffc020a0…, ledger 165) + rehearsal/fixture_local.sql (the 113 preimage ids).
# Expected states: rehearsal/expected_local/ (pre154 = r0_pre_local.txt; the rest = rehearsal/predict.py,
# written before the first apply). Usage: bash rehearsal/run_local.sh > rehearsal/run_local_20261015.log 2>&1
set -u
cd "$(dirname "$0")/.."
export MODE=LOCALDB LOCALDB_NAME=a154_pkg_rehears PKG_EXPECTED=rehearsal/expected_local PGHOST=127.0.0.1 PGUSER=postgres
fails=0
step() {  # step <label> <expected rc> <pkg args...>
  local label=$1 want=$2; shift 2
  echo "== $label (expect rc $want)"
  python3 pkg.py "$@" 2>&1
  local rc=$?
  echo "rc=$rc"
  [ "$rc" = "$want" ] || { echo "!! UNEXPECTED rc for $label: got $rc, registered $want"; fails=$((fails+1)); }
}
step "R0 check pre154" 0 check rehearsal/expected_local/pre154.txt
step "R1 apply 154" 0 apply 154
step "R2 apply 154 again (negative)" 3 apply 154
step "R3 rollback 154 (table kept, empty)" 0 rollback 154
step "R4 rollback 154 again (negative)" 3 rollback 154
step "R5 re-apply 154 after its own rollback (alt_pre rb154)" 0 apply 154
step "R6 apply 155" 0 apply 155
step "R7 apply 156" 0 apply 156
echo "== R8 split: delete 156's ledger row (objects stay)"
psql -q -d "$LOCALDB_NAME" -v ON_ERROR_STOP=1 -c "DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261015000200'" && echo "split rc=0"
step "R8b apply 156 --ledger-only (resume)" 0 apply 156 --ledger-only
step "R8c apply 156 --ledger-only again (negative: row present)" 3 apply 156 --ledger-only
step "R9 step hide (113 rows)" 0 step hide
step "R10 step hide again (negative)" 3 step hide
step "R11 step unhide" 0 step unhide
step "R12 step hide (final data state)" 0 step hide
step "R13 check post_hide" 0 check rehearsal/expected_local/post_hide.txt
step "R14 rollback 156 with rows hidden (data keys ignored)" 0 rollback 156
step "R15 rollback 155" 0 rollback 155
step "R16 rollback 154 (113 rows KEPT, inert)" 0 rollback 154
echo "== R17 kept rows are inert: anon sees the listings again; the 113 visibility rows survive"
psql -d "$LOCALDB_NAME" -tA -c "select 'lv_rows=' || count(*) from public.listing_visibility"
step "R18 apply 154 with kept rows (negative: prestate STOP, nothing sent)" 3 apply 154
echo "== DONE: $fails unexpected exit code(s)"
exit $fails
