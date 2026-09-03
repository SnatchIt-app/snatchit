#!/usr/bin/env bash
# ============================================================================
# scripts/rehearsal_test.sh — run the pgTAP suite against the local rehearsal DB.
#
# Runs supabase/tests/*.sql with plain psql (no Docker, no pg_prove, no Supabase
# CLI): 000_helpers.sql commits the `tap` helper schema, every other file is
# BEGIN…ROLLBACK, so the database is left pristine between runs. The TAP parser
# lives in scripts/local/runtests.sh; this wrapper adds the local-only safety
# guards and classifies the KNOWN local-only deltas so a real regression cannot
# hide behind them.
#
#   usage: scripts/rehearsal_test.sh [dbname] [test files...]
#   env:   REHEARSAL_PGHOST / REHEARSAL_PGPORT / REHEARSAL_PGUSER (as reset.sh)
#
# Exit 0 only when every file's assertions RUN == PLANNED, there are zero psql
# errors, and the only failing assertions are the four documented deltas below.
#
# SAFETY: scrubs every remote-connection variable before touching psql; refuses
# any server that is not loopback or that carries Supabase platform roles.
# Written for bash 3.2 (macOS system bash).
# ============================================================================
set -uo pipefail

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
DB="${1:-snatchit_rehearsal}"; [ $# -gt 0 ] && shift

die() { printf '\n[rehearsal-test] ABORT: %s\n' "$*" >&2; exit 1; }

case "$PGHOST" in
  127.0.0.1|::1|localhost|/*) : ;;
  *) die "PGHOST='$PGHOST' is not loopback. This harness only runs against a local server." ;;
esac
case "$DB" in
  postgres|template0|template1) die "'$DB' is not a rehearsal database." ;;
  *rehears*) : ;;
  *) die "database name '$DB' must contain 'rehears'." ;;
esac
command -v psql >/dev/null || die "psql not on PATH (try: export PATH=/opt/homebrew/opt/postgresql@17/bin:\$PATH)"

guard="$(psql -d "$DB" -tAc "
  select coalesce(host(inet_server_addr()),'socket')
      || '|' || (select count(*) from pg_roles where rolname in ('supabase_admin','supabase_replication_admin'))" 2>/dev/null)" \
  || die "cannot connect to database '$DB' on $PGHOST:$PGPORT — run scripts/rehearsal_reset.sh first."
srv_addr="${guard%%|*}"; supa_roles="${guard##*|}"
case "$srv_addr" in socket|127.0.0.1|::1) : ;; *) die "server address '$srv_addr' is not loopback." ;; esac
[ "$supa_roles" = "0" ] || die "this server has Supabase platform roles — it is NOT a scratch local cluster. Refusing."

psql -q -d "$DB" -v ON_ERROR_STOP=1 -c "create extension if not exists pgtap" >/dev/null \
  || die "could not install pgTAP (expected /opt/homebrew/share/postgresql@17/extension/pgtap.control)"
printf '[rehearsal-test] pgTAP %s on %s\n\n' \
  "$(psql -d "$DB" -tAc "select extversion from pg_extension where extname='pgtap'")" "$DB"

OUT="${TMPDIR:-/tmp}/${DB}_pgtap.out"
bash "$ROOT/scripts/local/runtests.sh" "$DB" "$@" 2>&1 | tee "$OUT"

# --- Classify. ---------------------------------------------------------------
# KNOWN local-only deltas. Anything else failing is a real finding.
#   060_payments_money.sql   not_ok=2  deliberate todo() markers (F-2 unique
#                            index on transfers.stripe_transfer_id, F-3 payments
#                            amount/status guard). These are expected-fail in CI
#                            too — they flip green when the fix ships.
#   132_replay_parity.sql    not_ok=2  D-5/8 and D-5/9 compare cron.job."database"
#                            to the literal 'postgres' (production ran the chain
#                            in the database named `postgres`). A rehearsal
#                            database cannot be named `postgres`, so it reports
#                            its own name. DB-NAME ARTIFACT, NOT SCHEMA DRIFT —
#                            the schedule, username, active flag and the exact
#                            command bytes/md5 all match.
known_notok() { case "$1" in 060_payments_money.sql) echo 2 ;; 132_replay_parity.sql) echo 2 ;; *) echo 0 ;; esac; }

echo
echo "=============================================================="
echo " LOCAL-ONLY DELTAS vs the CI (real Supabase stack) run"
echo "=============================================================="
rc=0
while read -r name plan ok notok perr status; do
  case "$name" in *.sql) : ;; *) continue ;; esac
  p="${plan#plan=}"; o="${ok#ok=}"; nk="${notok#not_ok=}"; pe="${perr#psql_err=}"
  exp="$(known_notok "$name")"
  if [ "$pe" != "0" ]; then
    echo "  REGRESSION $name: $pe psql error(s) — the file aborted; assertions did not all run."; rc=1
  elif [ "$p" != "$((o+nk))" ]; then
    echo "  REGRESSION $name: planned $p but ran $((o+nk)) assertions."; rc=1
  elif [ "$nk" != "$exp" ]; then
    echo "  REGRESSION $name: not_ok=$nk, expected $exp."; rc=1
  elif [ "$exp" != "0" ]; then
    echo "  expected   $name: $exp known local-only/TODO failure(s) — see header."
  fi
done < "$OUT"
echo "=============================================================="
if [ "$rc" = "0" ]; then
  echo " RESULT: pgTAP suite matches the expected local baseline."
else
  echo " RESULT: REGRESSION — a failure outside the documented delta set."
fi
echo " Reminder: nothing here exercises pg_cron firing, net.http_post delivery,"
echo " or vault secret decryption. Those are inert stand-ins (see"
echo " scripts/rehearsal_bootstrap.sql fidelity ledger)."
exit $rc
