#!/usr/bin/env bash
# =============================================================================
# scripts/release/apply_sandbox_migration.sh — SANDBOX-ONLY application of ONE
# numbered migration from the PINNED tree, recording the ledger row with the
# file's exact bytes (the 123 pattern, generalized for the 2026-09-18 window).
#
#   usage: apply_sandbox_migration.sh <version> preflight|apply|verify [tree]
#   e.g.   apply_sandbox_migration.sh 124 apply /tmp/wt-pin
#
# Refuses anything but ofaidukbieeekqaboscm (asserted twice; production ref
# refused). `preflight` and `verify` are READ-ONLY. `apply` refuses unless the
# version is absent from the ledger and every lower numbered migration file in
# the tree that is >120 is already recorded (order guard for the shared sandbox).
# =============================================================================
set -uo pipefail
export LC_ALL=C
SANDBOX_REF='ofaidukbieeekqaboscm'
PROD_REF='hqycwntpfoztoinemqns'
VER="${1:?version}"; MODE="${2:?mode}"; TREE="${3:-$(cd "$(dirname "$0")/../.." && pwd)}"
ENVF="${SANDBOX_ENV:-/Users/josetascon/snatchit-rc/scripts/sandbox/sandbox.env}"
MIG="$(ls "$TREE"/supabase/migrations/${VER}_*.sql 2>/dev/null | head -1)"
[ -n "$MIG" ] && [ -f "$MIG" ] || { echo "FAIL: no migration ${VER}_*.sql in $TREE"; exit 2; }
NAME="$(basename "$MIG" .sql | sed "s/^${VER}_//")"
[ -f "$ENVF" ] || { echo "FAIL: sandbox env not found"; exit 2; }
set -a; . "$ENVF" >/dev/null 2>&1; set +a
case "${TEST_DB_URL:-}" in *"$PROD_REF"*) echo "REFUSING: production ref present"; exit 2;; esac
case "${TEST_DB_URL:-}" in *"$SANDBOX_REF"*) ;; *) echo "REFUSING: sandbox ref absent"; exit 2;; esac
case "${TEST_REF:-}" in "$SANDBOX_REF") ;; *) echo "REFUSING: TEST_REF is not the sandbox"; exit 2;; esac
q() { psql "$TEST_DB_URL" -X -qtA -v ON_ERROR_STOP=1 -c "$1"; }
stored_md5() { printf '%s' "$(cat "$MIG")" | md5 -q; }
echo "target: $SANDBOX_REF | version: $VER ($NAME) | mode: $MODE | tree: $TREE"
EXIST="$(q "select coalesce((select name from supabase_migrations.schema_migrations where version='$VER'),'')")" || { echo "STOP: ledger unreachable"; exit 1; }
LEDGER="$(q "select count(*) from supabase_migrations.schema_migrations")"
echo "ledger rows: $LEDGER | $VER recorded as: '${EXIST:-<absent>}'"
# order guard: every numbered file in the tree between 121 and VER-1 must already be recorded
MISSING=""
for f in "$TREE"/supabase/migrations/1[2-9][0-9]_*.sql; do
  v="$(basename "$f" | cut -d_ -f1)"; [ "$v" -lt "$VER" ] && [ "$v" -gt 120 ] || continue
  r="$(q "select count(*) from supabase_migrations.schema_migrations where version='$v'")"; [ "$r" = "1" ] || MISSING="$MISSING $v"
done
[ -z "$MISSING" ] || { echo "STOP: lower-numbered migration(s) not recorded on the sandbox:$MISSING — apply in order"; exit 1; }
case "$MODE" in
  preflight) [ -z "$EXIST" ] && echo "PREFLIGHT OK — $VER absent, order guard satisfied, nothing written" || echo "PREFLIGHT: $VER already recorded"; exit 0;;
  verify)
    DB_MD5="$(q "select coalesce(md5(array_to_string(statements,'')),'') from supabase_migrations.schema_migrations where version='$VER'")"
    [ -n "$EXIST" ] || { echo "VERIFY: NO ledger row for $VER"; exit 1; }
    [ "$DB_MD5" = "$(stored_md5)" ] && echo "VERIFY OK: ledger md5 $DB_MD5 == pinned file" || { echo "VERIFY FAIL: ledger md5 $DB_MD5 != file $(stored_md5)"; exit 1; }
    exit 0;;
  apply) ;;
  *) echo "unknown mode"; exit 2;;
esac
[ -z "$EXIST" ] || { echo "STOP: $VER already recorded as '$EXIST' — refusing to reapply"; exit 1; }
echo "applying $(basename "$MIG") ..."
psql "$TEST_DB_URL" -X -v ON_ERROR_STOP=1 -f "$MIG" 2>&1 | grep -vE "^(SET|BEGIN|COMMIT|CREATE|ALTER|DROP|REVOKE|GRANT|COMMENT|INSERT|DO|NOTICE:.*)$" | head -20
[ "${PIPESTATUS[0]:-${pipestatus[1]:-0}}" = "0" ] || { echo "APPLY FAILED — nothing recorded in the ledger"; exit 1; }
echo "recording the ledger row (exact file bytes) ..."
psql "$TEST_DB_URL" -X -qtA -v ON_ERROR_STOP=1 -v ver="$VER" -v nm="$NAME" -v mig="$(cat "$MIG")" <<'SQL' || { echo "LEDGER INSERT FAILED — applied but unrecorded; investigate"; exit 1; }
do $l$ begin if exists (select 1 from supabase_migrations.schema_migrations where version = current_setting('app.ver', true)) then raise exception 'ledger REFUSED — already recorded'; end if; end $l$;
insert into supabase_migrations.schema_migrations (version, name, statements) values (:'ver', :'nm', array[ :'mig' ]);
select 'ledger recorded: version='||version||' name='||name||' md5='||md5(array_to_string(statements,'')) from supabase_migrations.schema_migrations where version=:'ver';
SQL
echo "expected md5 (file minus trailing newline): $(stored_md5)"
echo "APPLIED $VER. Run verify."
