#!/bin/bash
# LOCAL-ONLY fresh replay of the migration chain onto a plain PostgreSQL 17
# cluster: scaffolding shim first (scripts/local/replay_shim.sql — see its
# header for exactly why it exists), then every supabase/migrations/*.sql in
# version order, then the CI-only privilege bootstrap. CI does NOT use this:
# CI's `supabase start` on the real Supabase local stack is the authoritative
# fresh replay. Env: PGHOST/PGPORT/PGUSER as for psql. usage: replay.sh <dbname>
set -u
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MIG="$ROOT/supabase/migrations"; DB="$1"; ERR="${REPLAY_ERR:-/tmp/${DB}_replay.err}"; : > "$ERR"
dropdb --if-exists "$DB"; createdb "$DB"
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/scripts/local/replay_shim.sql" >/dev/null 2>>"$ERR" || { echo "SHIM FAILED"; tail -5 "$ERR"; exit 1; }
n=0
for f in $(ls "$MIG"/*.sql | LC_ALL=C sort); do
  base=$(basename "$f")
  if [ "$base" = "014_frequent_cron_schedules.sql" ]; then
    # the plain cluster has no pg_cron/pg_net extension: the shim provides cron.schedule/net.http_post stand-ins
    grep -v '^create extension if not exists pg_' "$f" | psql -q -d "$DB" -v ON_ERROR_STOP=1 -f - >/dev/null 2>>"$ERR" || { echo "FAILED: $base"; tail -8 "$ERR"; exit 1; }
  else
    psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>>"$ERR" || { echo "FAILED: $base"; tail -12 "$ERR"; exit 1; }
  fi
  n=$((n+1))
done
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$ROOT/supabase/ci/parity_grants.sql" >/dev/null 2>>"$ERR" || { echo "PARITY GRANTS FAILED"; tail -8 "$ERR"; exit 1; }
echo "REPLAY OK: $n migrations applied to $DB"
