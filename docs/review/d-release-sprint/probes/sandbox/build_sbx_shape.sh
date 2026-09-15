#!/bin/bash
# D: replay the sandbox's exact ledger (versions in sandbox_ledger_132_versions.txt) from a frozen pin tree into a local
# loopback rehearsal DB. usage: build_sbx_shape.sh <scratch dir holding pin/ and ledger.txt> <db name>. Local only.
set -u; S="$1"; DB="$2"; P=$S/pin
export PGHOST=127.0.0.1 PGUSER=postgres LC_ALL=C
unset DATABASE_URL SUPABASE_DB_URL PGSERVICE
dropdb --if-exists $DB; createdb $DB
psql -X -q -d $DB -v ON_ERROR_STOP=1 -f $P/scripts/local/replay_shim.sql >/dev/null 2>$S/shim.err || { echo SHIMFAIL; exit 1; }
[ -f $P/scripts/local/replay_shim_supplements.sql ] && { psql -X -q -d $DB -v ON_ERROR_STOP=1 -f $P/scripts/local/replay_shim_supplements.sql >/dev/null 2>>$S/shim.err || { echo SUPPFAIL; exit 1; }; }
ap(){ b=$(basename $1); if [ "$b" = "014_frequent_cron_schedules.sql" ]; then grep -v '^create extension if not exists pg_' $1 | psql -X -q -d $DB -v ON_ERROR_STOP=1 -f - >/dev/null 2>>$S/apply.err || { echo "FAIL $b"; return 1; }; else psql -X -q -d $DB -v ON_ERROR_STOP=1 -f $1 >/dev/null 2>>$S/apply.err || { echo "FAIL $b"; return 1; }; fi; }
: > $S/apply.err; n=0
for f in $(ls $P/supabase/migrations/*.sql | LC_ALL=C sort); do
  v=$(basename $f); v=${v%%_*}
  grep -qx "$v" $S/ledger.txt || continue
  ap $f || exit 1; n=$((n+1))
done
echo "sandbox-shape applied=$n (ledger lines $(wc -l < $S/ledger.txt))"
