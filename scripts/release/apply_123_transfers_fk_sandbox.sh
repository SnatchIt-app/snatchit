#!/usr/bin/env bash
# =============================================================================
# scripts/release/apply_123_transfers_fk_sandbox.sh
#
# SANDBOX-ONLY application of 123_transfers_profiles_fk_parity.sql.
# Refuses to run against anything but ofaidukbieeekqaboscm. Applies nothing to
# production. Idempotent: safe to re-run.
#
#   usage:  scripts/release/apply_123_transfers_fk_sandbox.sh preflight
#           scripts/release/apply_123_transfers_fk_sandbox.sh apply
#           scripts/release/apply_123_transfers_fk_sandbox.sh verify
#
# `preflight` and `verify` are READ-ONLY. Only `apply` writes, and it refuses
# unless preflight's conditions still hold at that moment.
# =============================================================================
set -uo pipefail
export LC_ALL=C
SANDBOX_REF='ofaidukbieeekqaboscm'
PROD_REF='hqycwntpfoztoinemqns'
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MIG="$ROOT/supabase/migrations/123_transfers_profiles_fk_parity.sql"
ENVF="${SANDBOX_ENV:-/Users/josetascon/snatchit-rc/scripts/sandbox/sandbox.env}"
MODE="${1:-preflight}"

[ -f "$MIG" ]  || { echo "FAIL: migration not found at $MIG"; exit 2; }
[ -f "$ENVF" ] || { echo "FAIL: sandbox env not found at $ENVF"; exit 2; }
set -a; . "$ENVF" >/dev/null 2>&1; set +a

# --- target assertions: twice, and never production ---------------------------
case "${TEST_DB_URL:-}" in *"$PROD_REF"*) echo "REFUSING: production ref present in the connection string"; exit 2;; esac
case "${TEST_DB_URL:-}" in *"$SANDBOX_REF"*) ;; *) echo "REFUSING: sandbox ref absent from the connection string"; exit 2;; esac
case "${TEST_REF:-}" in "$SANDBOX_REF") ;; *) echo "REFUSING: TEST_REF is '${TEST_REF:-unset}', expected $SANDBOX_REF"; exit 2;; esac
q() { psql "$TEST_DB_URL" -X -qtA -v ON_ERROR_STOP=1 -c "$1"; }
# The ledger stores "$(cat $MIG)", which is the file WITHOUT its single trailing
# newline (standard shell substitution). Hash the same transformation so the
# comparison is like-for-like rather than off by one byte.
stored_md5() { printf '%s' "$(cat "$MIG")" | { md5 -q 2>/dev/null || md5sum | cut -d" " -f1; }; }

echo "target: $SANDBOX_REF (asserted twice; production ref absent)"
echo "mode:   $MODE"
echo

# --- shared checks ------------------------------------------------------------
baselines() {
  q "select 'transfers='||(select count(*) from public.transfers)
        ||'  payments='||(select count(*) from public.payments)
        ||'  listings='||(select count(*) from public.listings)
        ||'  profiles='||(select count(*) from public.profiles)
        ||'  ledger='||(select count(*) from supabase_migrations.schema_migrations)"
}
fk_targets() {
  q "select string_agg(conname||' -> '||(select nspname from pg_namespace n join pg_class r on r.relnamespace=n.oid where r.oid=confrelid)||'.'||(select relname from pg_class where oid=confrelid), '  |  ' order by conname)
       from pg_constraint where conrelid='public.transfers'::regclass and conname in ('transfers_buyer_id_fkey','transfers_seller_id_fkey')"
}
orphans() {
  q "select (select count(*) from public.transfers t where t.buyer_id is not null and not exists (select 1 from public.profiles p where p.id=t.buyer_id))
          + (select count(*) from public.transfers t where t.seller_id is not null and not exists (select 1 from public.profiles p where p.id=t.seller_id))"
}
ledger_123() { q "select coalesce((select name from supabase_migrations.schema_migrations where version='123'),'')"; }

BASE_LINE="$(baselines)"
if [ -z "$BASE_LINE" ]; then echo "STOP: baseline query returned nothing — database unreachable."; exit 1; fi
echo "baselines:   $BASE_LINE"
echo "fk targets:  $(fk_targets)"
echo "orphans:     $(orphans)"
EXIST="$(ledger_123)"
echo "ledger 123:  ${EXIST:-(absent)}"
echo

ORPH="$(orphans)"
if [ -z "$ORPH" ]; then
  echo "STOP: the orphan check did not return a value — the database was unreachable or the query failed."
  echo "      This is NOT a statement about the data. Fix connectivity and re-run."; exit 1
elif [ "$ORPH" != "0" ]; then
  echo "STOP: $ORPH orphaned buyer/seller reference(s) present. Reconcile before applying."; exit 1
fi

case "$MODE" in
  preflight)
    echo "PREFLIGHT OK — nothing was written. Re-run with 'apply' once authorized."
    exit 0
    ;;
  verify)
    echo "--- verification (read-only) ---"
    q "select 'V1 '||conname||' -> '||(select relname from pg_class where oid=confrelid)
             ||'  upd='||confupdtype::text||' del='||confdeltype::text||' match='||confmatchtype::text
             ||' validated='||convalidated::text||' deferrable='||condeferrable::text
         from pg_constraint where conrelid='public.transfers'::regclass
          and conname in ('transfers_buyer_id_fkey','transfers_seller_id_fkey') order by conname"
    q "select 'V2 dispute_resolved_by -> '||(select (select nspname from pg_namespace n join pg_class r on r.relnamespace=n.oid where r.oid=confrelid) from pg_constraint where conrelid='public.transfers'::regclass and conname='transfers_dispute_resolved_by_fkey')"
    q "select 'V3 fk count on transfers: '||count(*) from pg_constraint where conrelid='public.transfers'::regclass and contype='f'"
    q "select 'V4 rls enabled: '||relrowsecurity||'  policies: '||(select count(*) from pg_policy where polrelid='public.transfers'::regclass) from pg_class where oid='public.transfers'::regclass"
    q "select 'V5 baselines: '||'transfers='||(select count(*) from public.transfers)||' payments='||(select count(*) from public.payments)||' listings='||(select count(*) from public.listings)"
    q "select 'V6 ledger rows: '||count(*)||'  123 recorded: '||(select count(*) from supabase_migrations.schema_migrations where version='123') from supabase_migrations.schema_migrations"
    LOCAL_MD5="$(stored_md5)"
    DB_MD5="$(q "select coalesce(md5(array_to_string(statements,'')),'') from supabase_migrations.schema_migrations where version='123'")"
    if [ -z "$DB_MD5" ]; then
      echo "V7 ledger content: NO ROW for version 123 — apply has not run"
    elif [ "$LOCAL_MD5" = "$DB_MD5" ]; then
      echo "V7 ledger content MATCHES the migration file (md5 $DB_MD5; file minus its single trailing newline)"
    else
      echo "V7 MISMATCH: file=$LOCAL_MD5 ledger=$DB_MD5 — the recorded statements are not this migration"
    fi
    echo "--- pgTAP 191 is deliberately NOT run here: pgtap is not installed on this project,"
    echo "    and installing it to run a read-only assertion would change the shared sandbox."
    echo "    191 runs in CI and the local replay, where the harness owns the extension."
    exit 0
    ;;
  apply) ;;
  *) echo "unknown mode '$MODE'"; exit 2;;
esac

# --- apply --------------------------------------------------------------------
if [ -n "$EXIST" ]; then
  echo "STOP: supabase_migrations.schema_migrations already has version 123 recorded as '$EXIST'."
  echo "      Investigate before proceeding. This script will not overwrite or silently skip it."
  exit 1
fi

echo "applying $MIG ..."
psql "$TEST_DB_URL" -X -v ON_ERROR_STOP=1 -f "$MIG" || { echo "APPLY FAILED — nothing recorded in the ledger"; exit 1; }

echo "recording the ledger row (exact file content) ..."
psql "$TEST_DB_URL" -X -v ON_ERROR_STOP=1 -v mig="$(cat "$MIG")" <<'SQL' || { echo "LEDGER INSERT FAILED — the migration is applied but unrecorded; re-run 'apply' after investigating"; exit 1; }
-- 1. Conflict check. A DO block, so no psql variable is needed here; psql does
--    NOT interpolate :'vars' inside dollar-quoted bodies.
do $ledger$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version = '123') then
    raise exception '123 ledger REFUSED — version 123 is already recorded. No ON CONFLICT, no silent pass; investigate before proceeding.';
  end if;
end
$ledger$;

-- 2. The row, with the file's exact bytes. Plain statement, so :'mig' interpolates.
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('123', 'transfers_profiles_fk_parity', array[ :'mig' ]);

-- 3. Record what actually landed.
select 'ledger recorded: version='||version||'  name='||name
     ||'  statements='||coalesce(array_length(statements,1),0)
     ||'  chars='||length(array_to_string(statements,''))
     ||'  md5='||md5(array_to_string(statements,''))
  from supabase_migrations.schema_migrations where version='123';
SQL

echo
echo "expected md5 (file without its trailing newline): $(stored_md5)"
echo "APPLIED. Now run: $0 verify"
