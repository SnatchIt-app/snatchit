#!/usr/bin/env bash
# ============================================================================
# scripts/rehearsal_reset.sh — LOCAL-ONLY migration rehearsal.
#
# Drops and recreates a local rehearsal database, applies the Supabase
# scaffolding bootstrap, then replays every supabase/migrations/*.sql in the
# repo's canonical order, stopping at the FIRST error. Idempotent: safe to run
# repeatedly; each run starts from an empty database.
#
# This is NOT the authoritative fresh replay — CI's `supabase start` on the real
# Supabase local stack is (see the `db` job in .github/workflows/ci.yml). This
# harness exists for machines without Docker. Read the fidelity ledger at the
# top of scripts/rehearsal_bootstrap.sql before trusting a result.
#
#   usage: scripts/rehearsal_reset.sh [dbname]        (default snatchit_rehearsal)
#   env:   REHEARSAL_PGHOST (default 127.0.0.1)
#          REHEARSAL_PGPORT (default 5432)
#          REHEARSAL_PGUSER (default postgres)
#          REHEARSAL_UPTO   optional: stop after this migration basename,
#                           e.g. REHEARSAL_UPTO=092_notify_reduced.sql
#
# SAFETY: this script can only ever touch a loopback PostgreSQL server. It
# scrubs every remote-connection variable from its own environment before it
# runs psql, so SUPABASE_DB_URL / DATABASE_URL / PGSERVICE cannot steer it.
# Written for bash 3.2 (macOS system bash).
# ============================================================================
set -uo pipefail

# --- 1. Scrub anything that could point psql at a remote. --------------------
# Done FIRST, before any psql invocation, and unconditionally: this harness
# must never be able to read a remote connection string, not even by accident.
unset SUPABASE_DB_URL SUPABASE_DB_PASSWORD SUPABASE_ACCESS_TOKEN \
      SUPABASE_PROJECT_ID SUPABASE_PROJECT_REF SUPABASE_URL \
      DATABASE_URL POSTGRES_URL POSTGRES_URL_NON_POOLING POSTGRES_PRISMA_URL \
      PGSERVICE PGSERVICEFILE PGPASSFILE PGPASSWORD PGSSLMODE PGURL PGDATABASE 2>/dev/null

export LC_ALL=C
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}"
export PGPORT="${REHEARSAL_PGPORT:-5432}"
export PGUSER="${REHEARSAL_PGUSER:-postgres}"
export PGCONNECT_TIMEOUT=5

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIG="$ROOT/supabase/migrations"
DB="${1:-snatchit_rehearsal}"
ERR="${REHEARSAL_ERR:-${TMPDIR:-/tmp}/${DB}_rehearsal.err}"
STRIPLOG="${TMPDIR:-/tmp}/${DB}_stripped.txt"

die() { printf '\n[rehearsal] ABORT: %s\n' "$*" >&2; exit 1; }

# --- 2. Refuse anything that is not a local server / rehearsal database. -----
case "$PGHOST" in
  127.0.0.1|::1|localhost|/*) : ;;
  *) die "PGHOST='$PGHOST' is not loopback. This harness only runs against a local server." ;;
esac
case "$DB" in
  postgres|template0|template1) die "refusing to drop the '$DB' database." ;;
esac
case "$DB" in
  *rehears*) : ;;
  *) die "database name '$DB' must contain 'rehears' — this script DROPs it." ;;
esac
case "$DB" in
  *[!a-z0-9_]*) die "database name '$DB' must be [a-z0-9_] only." ;;
esac

command -v psql     >/dev/null || die "psql not on PATH (try: export PATH=/opt/homebrew/opt/postgresql@17/bin:\$PATH)"
command -v createdb >/dev/null || die "createdb not on PATH"

# Bootstrap the owner role via the maintenance database, connecting as whatever
# superuser this cluster actually has (Homebrew initdb names it after the OS
# user, not 'postgres'), so `createdb -O postgres` below can succeed.
BOOTUSER="$PGUSER"
if ! psql -d postgres -U "$PGUSER" -tAc 'select 1' >/dev/null 2>&1; then
  BOOTUSER="$(id -un)"
  psql -d postgres -U "$BOOTUSER" -tAc 'select 1' >/dev/null 2>&1 \
    || die "cannot connect to $PGHOST:$PGPORT as '$PGUSER' or '$BOOTUSER'. Is it running? (brew services start postgresql@17)"
fi

# Server-side local proof: a Unix socket has no server address; a TCP connection
# must be to loopback. Also refuse a real Supabase server outright.
guard="$(psql -d postgres -U "$BOOTUSER" -tAc "
  select coalesce(host(inet_server_addr()),'socket')
      || '|' || (select count(*) from pg_roles where rolname in ('supabase_admin','supabase_replication_admin'))
      || '|' || pg_is_in_recovery()::text" 2>/dev/null)" || die "connection probe failed"
srv_addr="${guard%%|*}"; rest="${guard#*|}"
supa_roles="${rest%%|*}"; in_recovery="${rest#*|}"
case "$srv_addr" in socket|127.0.0.1|::1) : ;; *) die "server address '$srv_addr' is not loopback." ;; esac
[ "$supa_roles" = "0" ] || die "this server has Supabase platform roles — it is NOT a scratch local cluster. Refusing."
[ "$in_recovery" = "false" ] || die "server is a replica (in recovery). Refusing."

psql -q -d postgres -U "$BOOTUSER" -v ON_ERROR_STOP=1 -c \
  "DO \$b\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='postgres') THEN CREATE ROLE postgres LOGIN SUPERUSER CREATEDB CREATEROLE; END IF; END \$b\$;" \
  >/dev/null || die "could not ensure the 'postgres' role exists"

# --- 3. Canonical order. -----------------------------------------------------
# This mirrors what CI does. CI applies the chain with `supabase start`, whose
# CLI (pinned 2.115.0) enumerates supabase/migrations via a directory read that
# returns entries sorted BY FILENAME, byte-wise. So the canonical order is a
# plain LC_ALL=C sort of the basenames — which is what makes the normalized
# "Scheme B" sub-numbering work: 022 < 0230 < 0231 < 024 byte-wise (it would be
# 022 < 024 < 0230 under a NUMERIC sort, which is NOT the order used). The
# timestamped 2026* files sort last, after 092, for the same byte-wise reason.
CHAIN="$(cd "$MIG" && ls -1 -- *.sql | LC_ALL=C sort)"
TOTAL="$(printf '%s\n' "$CHAIN" | grep -c . )"
[ "$TOTAL" -gt 0 ] || die "no migrations found in $MIG"

# Statements that cannot run on vanilla PostgreSQL, stripped LINE-WISE (the file
# itself is never modified). Each entry is <basename>|<grep -E pattern>|<why>.
# Everything stripped is printed loudly at the end of the run.
strip_pattern_for() {
  case "$1" in
    014_frequent_cron_schedules.sql) echo '^create extension if not exists pg_' ;;
    *) echo '' ;;
  esac
}
strip_reason_for() {
  case "$1" in
    014_frequent_cron_schedules.sql)
      echo 'pg_cron / pg_net binaries are not installed in Homebrew PostgreSQL 17; scripts/rehearsal_bootstrap.sql supplies cron.schedule/cron.unschedule/cron.job and net.http_post stand-ins instead' ;;
    *) echo '' ;;
  esac
}

printf '[rehearsal] server   : %s:%s (addr=%s) applying as postgres\n' "$PGHOST" "$PGPORT" "$srv_addr"
printf '[rehearsal] database : %s (will be DROPPED and recreated)\n' "$DB"
printf '[rehearsal] chain    : %s files, canonical order = LC_ALL=C filename sort\n' "$TOTAL"
printf '[rehearsal] stderr   : %s\n\n' "$ERR"

: > "$ERR"; : > "$STRIPLOG"
dropdb   --if-exists -U "$BOOTUSER" "$DB" 2>>"$ERR" || die "dropdb failed (see $ERR)"
createdb -O postgres -U "$BOOTUSER" "$DB" 2>>"$ERR" || die "createdb failed (see $ERR)"

run_sql() { psql -q -d "$DB" -U postgres -v ON_ERROR_STOP=1 "$@" >/dev/null 2>>"$ERR"; }

run_sql -f "$ROOT/scripts/rehearsal_bootstrap.sql" \
  || { echo "[rehearsal] BOOTSTRAP FAILED"; tail -20 "$ERR"; exit 1; }
echo "[rehearsal] bootstrap  OK  (scripts/rehearsal_bootstrap.sql)"

# --- 4. Replay, stopping at the first error. ---------------------------------
n=0
for base in $CHAIN; do
  f="$MIG/$base"
  pattern="$(strip_pattern_for "$base")"
  if [ -n "$pattern" ]; then
    hits="$(grep -cE "$pattern" "$f" || true)"
    echo "$base: $hits line(s) matching /$pattern/ -- $(strip_reason_for "$base")" >> "$STRIPLOG"
    grep -vE "$pattern" "$f" | run_sql -f - \
      || { echo "[rehearsal] FAILED: $base"; tail -20 "$ERR"; exit 1; }
  else
    run_sql -f "$f" || { echo "[rehearsal] FAILED: $base"; tail -20 "$ERR"; exit 1; }
  fi
  n=$((n+1))
  if [ "${REHEARSAL_UPTO:-}" = "$base" ]; then
    echo "[rehearsal] stopping after $base (REHEARSAL_UPTO)"; break
  fi
done

# CI applies this before the pgTAP suite: a fresh Supabase stack has no default
# table privileges, so without it "anon cannot read X" passes vacuously.
# It references tables created by the LAST migrations in the chain (e.g.
# public.ambassador_applications from 20260730212326_*), so it can only be
# applied after a COMPLETE replay.
PARITY=applied
if [ -n "${REHEARSAL_UPTO:-}" ]; then
  PARITY=skipped
else
  run_sql -f "$ROOT/supabase/ci/parity_grants.sql" \
    || { echo "[rehearsal] PARITY GRANTS FAILED"; tail -20 "$ERR"; exit 1; }
fi

# --- 5. Report. --------------------------------------------------------------
echo
echo "[rehearsal] REPLAY OK: $n/$TOTAL migrations applied to '$DB'"
if [ "$PARITY" = applied ]; then
  echo "[rehearsal] parity grants applied (supabase/ci/parity_grants.sql)"
else
  echo "[rehearsal] parity grants SKIPPED — partial replay (REHEARSAL_UPTO=$REHEARSAL_UPTO)."
  echo "[rehearsal] The pgTAP suite MUST NOT be trusted on this database: without"
  echo "[rehearsal] parity_grants.sql the anon/authenticated grants are missing and"
  echo "[rehearsal] 'anon cannot read X' passes vacuously. Partial replays are for"
  echo "[rehearsal] proving a single migration applies, not for running tests."
fi
echo
echo "=============================================================="
echo " NOT APPLIED AS WRITTEN -- statements stripped for vanilla PG"
echo "=============================================================="
if [ -s "$STRIPLOG" ]; then sed 's/^/  - /' "$STRIPLOG"; else echo "  (none)"; fi
echo "  NO migration file was skipped in full."
echo "=============================================================="
echo
psql -d "$DB" -U postgres -tAc "
  select 'GATE-2  tables=' || (select count(*) from pg_tables where schemaname='public')
      || ' functions='     || (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')
      || ' policies='      || (select count(*) from pg_policies where schemaname='public')
      || ' triggers='      || (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
                                 join pg_namespace n on n.oid=c.relnamespace
                                where n.nspname='public' and not t.tgisinternal)"
echo "        CI baseline: tables=27 functions=70 policies=37 triggers=24 (ci.yml EXPECT_*)"
