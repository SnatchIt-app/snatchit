#!/usr/bin/env bash
# ============================================================================
# admin/scripts/local-stack.sh — TEST HARNESS ONLY. LOCAL. SYNTHETIC.
#
# Starts/stops a Docker-free, Supabase-shaped API for the admin console:
#
#   PostgREST 16   :3201  -> the local rehearsal Postgres (Homebrew PG17)
#   auth-stub.mjs  :3202  -> proxies /rest/v1/* to :3201, emulates /auth/v1/*
#
# The Next.js admin app (admin/, :3200) points NEXT_PUBLIC_SUPABASE_URL at
# http://localhost:3202. Read admin/scripts/README.md for fidelity limits.
#
#   usage: admin/scripts/local-stack.sh [start|stop|restart|reload|status|
#                                        fixtures|env|logs] [dbname]
#          (default: start; default dbname: snatchit_rehearsal_admin)
#   env:   REHEARSAL_PGHOST (127.0.0.1)  REHEARSAL_PGPORT (5432)
#          REHEARSAL_PGUSER (postgres)
#          LOCAL_STACK_SCHEMAS   override PostgREST db-schemas. Default is
#                                "public, kernel" plus "ops" when that schema
#                                exists in the database at start time
#                                (PostgREST 16 refuses to load with a missing
#                                schema — verified; run `reload` after a
#                                migration creates ops).
#          LOCAL_STACK_POSTGREST_PORT (3201) LOCAL_STACK_AUTH_PORT (3202)
#          LOCAL_STACK_JWT_SECRET (fixed dev secret, >=32 chars)
#          LOCAL_STACK_SKIP_FIXTURES=1  do not apply fixtures.sql on start
#
# SAFETY (mirrors scripts/rehearsal_reset.sh): only a loopback PostgreSQL, only
# a database whose name contains "rehears", never a server carrying Supabase
# platform roles. Remote connection variables are scrubbed before anything runs.
# Written for bash 3.2 (macOS system bash).
# ============================================================================
set -uo pipefail

# --- 1. Scrub anything that could point psql at a remote. --------------------
unset SUPABASE_DB_URL SUPABASE_DB_PASSWORD SUPABASE_ACCESS_TOKEN \
      SUPABASE_PROJECT_ID SUPABASE_PROJECT_REF SUPABASE_URL \
      DATABASE_URL POSTGRES_URL POSTGRES_URL_NON_POOLING POSTGRES_PRISMA_URL \
      PGSERVICE PGSERVICEFILE PGPASSFILE PGPASSWORD PGSSLMODE PGURL PGDATABASE 2>/dev/null

export LC_ALL=C
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}"
export PGPORT="${REHEARSAL_PGPORT:-5432}"
export PGUSER="${REHEARSAL_PGUSER:-postgres}"
export PGCONNECT_TIMEOUT=5
# Homebrew PG17 first so psql matches the server.
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

HERE="$(cd "$(dirname "$0")" && pwd)"            # admin/scripts
ADMIN="$(cd "$HERE/.." && pwd)"                   # admin
STATE="$HERE/local/state"                         # gitignored
CMD="${1:-start}"
DB="${2:-snatchit_rehearsal_admin}"

PGRST_BIN="${LOCAL_STACK_POSTGREST_BIN:-/opt/homebrew/bin/postgrest}"
PGRST_PORT="${LOCAL_STACK_POSTGREST_PORT:-3201}"
AUTH_PORT="${LOCAL_STACK_AUTH_PORT:-3202}"
JWT_SECRET="${LOCAL_STACK_JWT_SECRET:-snatchit-local-harness-jwt-secret-0000000000}"
AUTHENTICATOR_PW="harness-authenticator-local-only"

PGRST_CONF="$STATE/postgrest.conf"
PGRST_PID="$STATE/postgrest.pid";  PGRST_LOG="$STATE/postgrest.log"
AUTH_PID="$STATE/auth-stub.pid";   AUTH_LOG="$STATE/auth-stub.log"

die()  { printf '\n[local-stack] ABORT: %s\n' "$*" >&2; exit 1; }
note() { printf '[local-stack] %s\n' "$*"; }

# --- 2. Refuse anything that is not a local server / rehearsal database. -----
case "$PGHOST" in
  127.0.0.1|::1|localhost|/*) : ;;
  *) die "PGHOST='$PGHOST' is not loopback. This harness only runs against a local server." ;;
esac
case "$DB" in
  postgres|template0|template1) die "refusing to use the '$DB' database." ;;
esac
case "$DB" in
  *rehears*) : ;;
  *) die "database name '$DB' must contain 'rehears' — this harness seeds synthetic data into it." ;;
esac
case "$DB" in
  *[!a-z0-9_]*) die "database name '$DB' must be [a-z0-9_] only." ;;
esac
[ ${#JWT_SECRET} -ge 32 ] || die "LOCAL_STACK_JWT_SECRET must be >= 32 chars"

command -v psql >/dev/null || die "psql not on PATH"
command -v node >/dev/null || die "node not on PATH (>=22 required)"
command -v curl >/dev/null || die "curl not on PATH"

probe_db() {
  psql -d "$DB" -tAc 'select 1' >/dev/null 2>&1 \
    || die "cannot connect to $PGHOST:$PGPORT/$DB as '$PGUSER'. Create it first: scripts/rehearsal_reset.sh $DB"
  # Server-side local proof, identical to rehearsal_reset.sh.
  local guard srv_addr rest supa_roles in_recovery
  guard="$(psql -d "$DB" -tAc "
    select coalesce(host(inet_server_addr()),'socket')
        || '|' || (select count(*) from pg_roles where rolname in ('supabase_admin','supabase_replication_admin'))
        || '|' || pg_is_in_recovery()::text" 2>/dev/null)" || die "connection probe failed"
  srv_addr="${guard%%|*}"; rest="${guard#*|}"
  supa_roles="${rest%%|*}"; in_recovery="${rest#*|}"
  case "$srv_addr" in socket|127.0.0.1|::1) : ;; *) die "server address '$srv_addr' is not loopback." ;; esac
  [ "$supa_roles" = "0" ] || die "this server has Supabase platform roles — it is NOT a scratch local cluster. Refusing."
  [ "$in_recovery" = "false" ] || die "server is a replica (in recovery). Refusing."
}

# --- helpers -----------------------------------------------------------------
pid_alive() { [ -f "$1" ] && kill -0 "$(cat "$1" 2>/dev/null)" 2>/dev/null; }

stop_one() { # name pidfile
  if pid_alive "$2"; then
    local pid; pid="$(cat "$2")"
    kill "$pid" 2>/dev/null
    local i=0
    while kill -0 "$pid" 2>/dev/null && [ $i -lt 30 ]; do sleep 0.2; i=$((i+1)); done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    note "stopped $1 (pid $pid)"
  else
    note "$1 not running"
  fi
  rm -f "$2"
}

wait_http() { # url expected-substring-or-empty tries
  local i=0
  while [ $i -lt "${3:-50}" ]; do
    if out="$(curl -s -m 2 "$1" 2>/dev/null)" && [ -n "$out" ] && { [ -z "$2" ] || printf '%s' "$out" | grep -q "$2"; }; then return 0; fi
    sleep 0.2; i=$((i+1))
  done
  return 1
}

ensure_authenticator() {
  # authenticator exists per scripts/rehearsal_bootstrap.sql; give it a LOCAL
  # password when it has none (pg_hba is trust on loopback anyway).
  local haspw
  haspw="$(psql -d "$DB" -tAc "select rolpassword is not null from pg_authid where rolname='authenticator'")"
  case "$haspw" in
    t) : ;;
    f) psql -d "$DB" -qc "alter role authenticator with login password '$AUTHENTICATOR_PW'" >/dev/null || die "could not set authenticator password"
       note "set a local-only password on role authenticator" ;;
    *) psql -d "$DB" -qc "create role authenticator login noinherit password '$AUTHENTICATOR_PW'; grant anon, authenticated, service_role to authenticator" >/dev/null \
         || die "could not create role authenticator"
       note "created role authenticator" ;;
  esac
}

resolve_schemas() {
  if [ -n "${LOCAL_STACK_SCHEMAS:-}" ]; then
    SCHEMAS="$LOCAL_STACK_SCHEMAS"
    note "db-schemas from LOCAL_STACK_SCHEMAS: $SCHEMAS"
  else
    SCHEMAS="public, kernel"
    if [ "$(psql -d "$DB" -tAc "select count(*) from pg_namespace where nspname='ops'")" = "1" ]; then
      SCHEMAS="public, kernel, ops"
    else
      note "schema 'ops' does not exist yet in $DB -> exposing 'public, kernel' only. Run '$0 reload' once migration 115 creates it."
    fi
  fi
}

write_pgrst_conf() {
  mkdir -p "$STATE"
  cat > "$PGRST_CONF" <<EOF
# GENERATED by admin/scripts/local-stack.sh — TEST HARNESS ONLY. Do not commit.
db-uri = "postgres://authenticator:${AUTHENTICATOR_PW}@${PGHOST}:${PGPORT}/${DB}"
db-schemas = "${SCHEMAS}"
db-anon-role = "anon"
db-pool = 10
jwt-secret = "${JWT_SECRET}"
jwt-aud = "authenticated"
server-host = "127.0.0.1"
server-port = ${PGRST_PORT}
log-level = "info"
# db-pre-request deliberately unset (task spec).
EOF
}

anon_key() { node "$HERE/auth-stub.mjs" --mint anon; }

apply_fixtures() {
  note "applying synthetic fixtures (admin/scripts/fixtures.sql) to $DB"
  psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$HERE/fixtures.sql" || die "fixtures.sql failed"
  note "fixtures applied"
}

print_env() {
  local anon; anon="$(anon_key)"
  cat <<EOF

# ---- TEST HARNESS env for admin/.env.local (synthetic; see admin/.env.local.example-harness)
NEXT_PUBLIC_SUPABASE_URL=http://localhost:${AUTH_PORT}
NEXT_PUBLIC_SUPABASE_ANON_KEY=${anon}
# ---- synthetic logins (password for all: harness-pass-123; MFA code: 123456)
#   founder.a@example.test  platform_admin (admin_users), aal1 -> exercises MFA enrollment
#   founder.b@example.test  platform_admin (admin_users), aal2 pre-verified
#   support@example.test    NOT in admin_users (denied-path testing)
#   buyer1@example.test     plain user
EOF
}

# --- commands ----------------------------------------------------------------
do_start() {
  probe_db
  mkdir -p "$STATE"
  ensure_authenticator
  [ "${LOCAL_STACK_SKIP_FIXTURES:-0}" = "1" ] || apply_fixtures
  resolve_schemas
  write_pgrst_conf

  if pid_alive "$PGRST_PID"; then
    note "postgrest already running (pid $(cat "$PGRST_PID"))"
  else
    [ -x "$PGRST_BIN" ] || die "postgrest not found at $PGRST_BIN (brew install postgrest)"
    nohup "$PGRST_BIN" "$PGRST_CONF" >> "$PGRST_LOG" 2>&1 &
    echo $! > "$PGRST_PID"
    wait_http "http://127.0.0.1:${PGRST_PORT}/" '"swagger"\|"openapi"' 50 \
      || { tail -20 "$PGRST_LOG" >&2; die "postgrest did not become ready on :$PGRST_PORT (see $PGRST_LOG)"; }
    note "postgrest up on http://127.0.0.1:${PGRST_PORT} (pid $(cat "$PGRST_PID"), schemas: $SCHEMAS)"
  fi

  if pid_alive "$AUTH_PID"; then
    note "auth-stub already running (pid $(cat "$AUTH_PID"))"
  else
    HARNESS_PORT="$AUTH_PORT" HARNESS_POSTGREST_URL="http://127.0.0.1:${PGRST_PORT}" \
    HARNESS_PUBLIC_URL="http://localhost:${AUTH_PORT}" HARNESS_JWT_SECRET="$JWT_SECRET" \
    HARNESS_PGHOST="$PGHOST" HARNESS_PGPORT="$PGPORT" HARNESS_PGUSER="$PGUSER" HARNESS_PGDATABASE="$DB" \
    HARNESS_PSQL="$(command -v psql)" \
      nohup node "$HERE/auth-stub.mjs" >> "$AUTH_LOG" 2>&1 &
    echo $! > "$AUTH_PID"
    wait_http "http://127.0.0.1:${AUTH_PORT}/auth/v1/health" 'auth-stub' 50 \
      || { tail -20 "$AUTH_LOG" >&2; die "auth-stub did not become ready on :$AUTH_PORT (see $AUTH_LOG)"; }
    note "auth-stub up on http://127.0.0.1:${AUTH_PORT} (pid $(cat "$AUTH_PID"))"
  fi

  anon_key > "$STATE/anon.jwt"
  print_env
  note "logs: $PGRST_LOG  $AUTH_LOG   stop: $0 stop"
}

do_stop() {
  stop_one auth-stub "$AUTH_PID"
  stop_one postgrest "$PGRST_PID"
}

do_status() {
  for pair in "postgrest:$PGRST_PID:$PGRST_PORT" "auth-stub:$AUTH_PID:$AUTH_PORT"; do
    name="${pair%%:*}"; rest="${pair#*:}"; pidf="${rest%%:*}"; port="${rest##*:}"
    if pid_alive "$pidf"; then note "$name running (pid $(cat "$pidf")) on :$port"; else note "$name stopped"; fi
  done
  [ -f "$PGRST_CONF" ] && grep '^db-schemas' "$PGRST_CONF"
}

do_reload() {
  # Regenerate config (picks up a newly created `ops` schema) and ask PostgREST
  # to re-read it: SIGUSR2 = reload config, SIGUSR1 = reload schema cache.
  probe_db
  resolve_schemas
  write_pgrst_conf
  if pid_alive "$PGRST_PID"; then
    kill -USR2 "$(cat "$PGRST_PID")"; sleep 0.5; kill -USR1 "$(cat "$PGRST_PID")"
    note "postgrest reloaded config + schema cache (schemas: $SCHEMAS)"
  else
    note "postgrest not running; config regenerated only"
  fi
}

case "$CMD" in
  start)    do_start ;;
  stop)     do_stop ;;
  restart)  do_stop; do_start ;;
  reload)   do_reload ;;
  status)   do_status ;;
  fixtures) probe_db; apply_fixtures ;;
  env)      print_env ;;
  logs)     tail -n 40 "$PGRST_LOG" "$AUTH_LOG" 2>/dev/null ;;
  *) die "unknown command '$CMD' (start|stop|restart|reload|status|fixtures|env|logs)" ;;
esac
