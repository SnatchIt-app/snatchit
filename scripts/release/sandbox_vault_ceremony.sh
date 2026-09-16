#!/usr/bin/env bash
# Sandbox Vault ceremony for the B2 application package (docs/release/SANDBOX_APPLICATION_PACKAGE_B2.md §2/§2a).
# SANDBOX ONLY (ofaidukbieeekqaboscm). Refuses the production ref twice. Never prints a secret value.
#
# Order is fixed by §2a condition 1:  check → url → verify-url → key → verify-key
#   check       read-only pre-checks (logging GUCs, role, vault.create_secret privilege, existing names)
#   url         insert Vault secret project_url = https://ofaidukbieeekqaboscm.supabase.co  (public-class value)
#   verify-url  name exists exactly once and the value has the sandbox host's exact shape (boolean only)
#   key         insert Vault secret service_role_key from the environment variable TEST_SERVICE_ROLE_KEY
#   verify-key  name exists exactly once and the value is non-empty with a JWT shape (boolean only)
#
# How the value stays out of every log (D's review points, 2026-09-16):
#   * The inserting statement is `select vault.create_secret($1, $2, $3)` sent with psql `\bind` (psql >= 16):
#     the value travels as an extended-protocol parameter, never inside the statement text. The sandbox has
#     log_statement=ddl and log_min_duration_statement=-1 (not logged on success) and
#     log_parameter_max_length_on_error=0 (parameters not logged on error). `check` re-reads these before any write.
#   * The value enters psql with `\getenv` (no subprocess, no argv). It is never echoed, RAISEd, `\set`-listed,
#     or written to a record. PSQL_HISTORY=/dev/null. No `set -x` anywhere.
#   * Pre-checks run as separate statements before the insert (name absent, privilege present, function present),
#     so the inserting statement runs against a state already proven; it should not be able to fail.
#   * Writes require CEREMONY_EXECUTE=1; without it, `url` and `key` print what they would do and stop.
#   * Known property (D): sourcing sandbox.env with `set -a` puts the key in this process's environment for the script's
#     lifetime, visible to same-user `ps eww`. Accepted; the alternatives (argv, a subprocess, a file) are worse.
#   * The DRY line prints the key's character length only: it catches a truncated env var, which would otherwise surface
#     as send-push refusing every dispatch.
set -euo pipefail
set +x 2>/dev/null || true
export PSQL_HISTORY=/dev/null
export PSQLRC=/dev/null

ENVF="${SANDBOX_ENV:-/Users/josetascon/snatchit-rc/scripts/sandbox/sandbox.env}"
set -a; . "$ENVF" >/dev/null 2>&1; set +a
case "${TEST_DB_URL:-}" in *hqycwntpfoztoinemqns*) echo "REFUSING: production ref in TEST_DB_URL"; exit 2;; esac
case "${TEST_DB_URL:-}" in *ofaidukbieeekqaboscm*) ;; *) echo "REFUSING: sandbox ref absent from TEST_DB_URL"; exit 2;; esac
[ "${TEST_REF:-}" = ofaidukbieeekqaboscm ] || { echo "REFUSING: TEST_REF is not the sandbox"; exit 2; }

SANDBOX_URL="https://ofaidukbieeekqaboscm.supabase.co"
MODE="${1:?mode: check|url|verify-url|key|verify-key}"
PSQL=(psql "$TEST_DB_URL" -X -q -v ON_ERROR_STOP=1)
echo "sandbox ofaidukbieeekqaboscm | $(date -u +%FT%TZ) | ceremony mode=$MODE | execute=${CEREMONY_EXECUTE:-0}"

# CS-1 (D): the env-file string matches above prove what the file says, not what the socket reached. The server must
# assert its own identity before any write: the sandbox has a ledger in the 130s, no `ops` schema (production has one)
# and the sandbox-only routine public.sandbox_gucs (production does not). All three, or STOP.
SERVER_IS_SANDBOX_SQL="select (select count(*) from supabase_migrations.schema_migrations) between 130 and 141 and to_regnamespace('ops') is null and to_regproc('public.sandbox_gucs') is not null"
require_server_is_sandbox() {
  local ok; ok=$("${PSQL[@]}" -tA -c "$SERVER_IS_SANDBOX_SQL")
  [ "$ok" = "t" ] || { echo "STOP: the connected server did not assert the sandbox identity (ledger 130..141, no ops schema, sandbox_gucs present) — got '$ok'"; exit 3; }
  echo "server asserts sandbox identity: ledger 130..141, ops schema absent, public.sandbox_gucs present"
}

precheck_common() {
  require_server_is_sandbox
  "${PSQL[@]}" -tA <<'SQL'
select 'connected role='||current_user||' | ledger='||(select count(*) from supabase_migrations.schema_migrations)||' | ops_schema='||(to_regnamespace('ops') is not null)::text||' | sandbox_gucs='||(to_regproc('public.sandbox_gucs') is not null)::text;
select 'log_statement='||current_setting('log_statement')||' log_min_duration_statement='||current_setting('log_min_duration_statement')||' log_min_error_statement='||current_setting('log_min_error_statement')||' log_parameter_max_length_on_error='||current_setting('log_parameter_max_length_on_error');
select 'pgaudit='||(exists(select 1 from pg_extension where extname='pgaudit'))::text;
select 'vault.create_secret present='||(exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='vault' and p.proname='create_secret'))::text||' executable='||has_function_privilege(current_user,'vault.create_secret(text,text,text,uuid)','EXECUTE')::text;
select 'vault names='||coalesce(string_agg(name, ',' order by name),'(none)')||' | count='||count(*) from vault.secrets;
SQL
}

require_logging_safe() {
  local ls lmds lpmloe
  ls=$("${PSQL[@]}" -tA -c "select current_setting('log_statement')")
  lmds=$("${PSQL[@]}" -tA -c "select current_setting('log_min_duration_statement')")
  lpmloe=$("${PSQL[@]}" -tA -c "select current_setting('log_parameter_max_length_on_error')")
  case "$ls" in none|ddl) ;; *) echo "STOP: log_statement=$ls would log the insert on success"; exit 3;; esac
  [ "$lmds" = "-1" ] || { echo "STOP: log_min_duration_statement=$lmds could log the insert on success"; exit 3; }
  [ "$lpmloe" = "0" ] || { echo "STOP: log_parameter_max_length_on_error=$lpmloe would log parameters on error"; exit 3; }
}

require_name_absent() {  # $1 = name
  local n; n=$("${PSQL[@]}" -tA -c "select count(*) from vault.secrets where name = '$1'")
  [ "$n" = "0" ] || { echo "STOP: vault already holds $n row(s) named $1"; exit 3; }
}

case "$MODE" in
  check)
    precheck_common ;;

  url)
    precheck_common; require_server_is_sandbox; require_logging_safe; require_name_absent project_url
    if [ "${CEREMONY_EXECUTE:-0}" != "1" ]; then echo "DRY: would insert project_url=$SANDBOX_URL (set CEREMONY_EXECUTE=1)"; exit 0; fi
    "${PSQL[@]}" -tA <<SQL
select 'inserted project_url id='||left(vault.create_secret(\$1, \$2, \$3)::text, 8)||'…' \\bind '$SANDBOX_URL' 'project_url' 'B2 package §2: functions base URL for this sandbox (133); inserted $(date -u +%F) under the owner ruling of 2026-09-16' \\g
SQL
    ;;

  verify-url)
    "${PSQL[@]}" -tA <<'SQL'
select 'project_url rows='||count(*)||' | shape_is_sandbox_host='||bool_and(decrypted_secret = 'https://ofaidukbieeekqaboscm.supabase.co')::text||' | names_production='||bool_or(decrypted_secret like '%hqycwntpfoztoinemqns%')::text from vault.decrypted_secrets where name = 'project_url';
SQL
    ;;

  key)
    precheck_common; require_server_is_sandbox; require_logging_safe; require_name_absent service_role_key
    # project_url must already exist and name the sandbox host (§2a condition 1) — checked here, again, before any key write.
    urlok=$("${PSQL[@]}" -tA -c "select count(*) = 1 and bool_and(decrypted_secret = '$SANDBOX_URL') from vault.decrypted_secrets where name = 'project_url'")
    [ "$urlok" = "t" ] || { echo "STOP: project_url is absent or does not name the sandbox host; run url + verify-url first"; exit 3; }
    [ -n "${TEST_SERVICE_ROLE_KEY:-}" ] || { echo "STOP: TEST_SERVICE_ROLE_KEY is empty in the environment"; exit 3; }
    case "$TEST_SERVICE_ROLE_KEY" in eyJ*.*.*) ;; *) echo "STOP: TEST_SERVICE_ROLE_KEY does not have a JWT shape"; exit 3;; esac
    if [ "${CEREMONY_EXECUTE:-0}" != "1" ]; then echo "DRY: would insert service_role_key from TEST_SERVICE_ROLE_KEY (length ${#TEST_SERVICE_ROLE_KEY}; set CEREMONY_EXECUTE=1)"; exit 0; fi
    # \getenv reads the variable inside psql (no subprocess, no argv); \bind sends it as a protocol parameter.
    "${PSQL[@]}" -tA <<SQL
\\getenv srk TEST_SERVICE_ROLE_KEY
select 'inserted service_role_key id='||left(vault.create_secret(\$1, \$2, \$3)::text, 8)||'…' \\bind :'srk' 'service_role_key' 'B2 package §2a(a): sandbox service-role key for pg_net posts (133/135); inserted $(date -u +%F) under the owner ruling; second named exception' \\g
\\unset srk
SQL
    ;;

  verify-key)
    "${PSQL[@]}" -tA <<'SQL'
select 'service_role_key rows='||count(*)||' | nonempty='||bool_and(length(decrypted_secret) > 0)::text||' | jwt_shape='||bool_and(decrypted_secret ~ '^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')::text from vault.decrypted_secrets where name = 'service_role_key';
select 'vault names now='||coalesce(string_agg(name, ',' order by name),'(none)') from vault.secrets;
SQL
    ;;

  *) echo "unknown mode"; exit 2;;
esac
