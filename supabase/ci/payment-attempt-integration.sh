#!/bin/bash
# Payment-attempt integration — runs INSIDE the disposable fresh-stack database
# after `supabase start` has applied supabase/migrations/** (which must already
# contain the reviewed 198-205 tail). Fail-closed; no production, no Stripe, no
# outbound calls.
#
#   DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres bash supabase/ci/payment-attempt-integration.sh
#
# Offline modes (no DB, no DB_URL):
#   --verify-inputs      file presence + authoritative hash pinning
#   --tamper-proof       prove one-byte mutation of a named migration fails
#   --selfcheck-wiring   prove scenario isolation / exact-refusal wiring markers
#   --selfcheck-clone    prove idle-template clone + never live-postgres-as-template + fail-closed
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MIGDIR="$ROOT/supabase/migrations"
DOCS="$ROOT/docs/release/payment-attempt-coordination"
ATTEMPT_VERSION=20261108194055
ATTEMPT_MIGRATION=20261108194055_native_payment_attempt_coordination
FORWARD="$MIGDIR/$ATTEMPT_MIGRATION.sql"
ROLLBACK="$ROOT/supabase/rollbacks/${ATTEMPT_MIGRATION}_rollback.sql"
SEED="$HERE/payment_attempt_seed.sql"
PINS="$DOCS/tests/local-pg/migrations.pins"
SNAPSHOT="${RUNNER_TEMP:-/tmp}/oc-forward-snapshot.sql"
TEMPLATE_DB="oc_template"

CHAIN_198_205="20261102120000_primary_checkout_hold_binding
20261102130000_refund_ledger_post_success_failure_and_executor_exclusions
20261102140000_ops_report_et_day_boundaries
20261102150000_primary_checkout_sale_eligibility
20261102160000_primary_fee_read_alignment
20261102170000_event_lifecycle_guards
20261102180000_venue_command_key_replay
20261102181000_ops_current_aal_empty_claims"

ROLLBACK_MODES="success unresolved pending-order active-hold collision partial missing-rpc extra-overload"

psqlq() { psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qAt "$@"; }

# --- offline: verify file contents against authoritative hashes ---------------
release_inputs() {
  local m
  for m in $CHAIN_198_205; do
    printf '%s\n' "supabase/migrations/${m}.sql" "supabase/rollbacks/${m}_rollback.sql"
  done
  printf '%s\n' \
    "supabase/migrations/$ATTEMPT_MIGRATION.sql" "supabase/rollbacks/${ATTEMPT_MIGRATION}_rollback.sql" \
    supabase/functions/primary-checkout/{index,order-pis,payment-attempts}.ts \
    supabase/functions/primary-lapse-canceller/index.ts \
    supabase/functions/stripe-webhook/{index,native,payment-attempts,refund-failure,sibling-guard}.ts
}

verify_hashes() {
  local base="$1"
  local pins="$base/docs/release/payment-attempt-coordination/tests/local-pg/migrations.pins"
  local rel want got
  [ -f "$pins" ] || { echo "::error::migrations.pins missing at $pins" >&2; return 1; }
  while IFS= read -r rel; do
    [ -f "$base/$rel" ] || { echo "::error::pinned input missing: $rel" >&2; return 1; }
    want=$(awk -v r="$rel" '$2==r{print $1}' "$pins")
    [ -n "$want" ] || { echo "::error::no authoritative pin for $rel" >&2; return 1; }
    got=$(shasum -a 256 "$base/$rel" | awk '{print $1}')
    [ "$got" = "$want" ] || { echo "::error::hash drift in $rel (expected $want, got $got)" >&2; return 1; }
  done < <(release_inputs)
  echo "OK: migrations, rollbacks, payment-attempt SQL and changed payment Edge sources match their pins"
}

verify_inputs() {
  local m missing=""
  for m in $CHAIN_198_205; do
    [ -f "$MIGDIR/${m}.sql" ] || missing="$missing ${m}.sql"
  done
  [ -n "$missing" ] && { echo "::error::missing migration files:$missing" >&2; return 1; }
  [ -f "$FORWARD" ]  || { echo "::error::forward.sql missing" >&2; return 1; }
  [ -f "$ROLLBACK" ] || { echo "::error::rollback.sql missing" >&2; return 1; }
  [ -f "$DOCS/tests/two-connection-lock-test.sh" ] || { echo "::error::two-connection-lock-test.sh missing" >&2; return 1; }
  [ -f "$DOCS/tests/rollback-safety-test.sh" ]     || { echo "::error::rollback-safety-test.sh missing" >&2; return 1; }
  [ -f "$SEED" ] || { echo "::error::payment_attempt_seed.sql missing" >&2; return 1; }
  [ -f "$HERE/payment_attempt_seed_cancel.sql" ]      || { echo "::error::payment_attempt_seed_cancel.sql missing" >&2; return 1; }
  [ -f "$HERE/payment_attempt_seed_concurrency.sql" ] || { echo "::error::payment_attempt_seed_concurrency.sql missing" >&2; return 1; }
  [ -f "$HERE/payment_attempt_seed_rollback.sql" ]    || { echo "::error::payment_attempt_seed_rollback.sql missing" >&2; return 1; }
  [ -f "$HERE/payment_attempt_lifecycle.sql" ]        || { echo "::error::payment_attempt_lifecycle.sql missing" >&2; return 1; }
  bash -n "$DOCS/tests/two-connection-lock-test.sh" || return 1
  bash -n "$DOCS/tests/rollback-safety-test.sh"     || return 1
  verify_hashes "$ROOT" || return 1
  echo "OK: inputs present and hash-pinned"
}

tamper_proof() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/oc-tamper.XXXXXX")
  trap 'rm -rf "$T"' EXIT
  local f
  while IFS= read -r f; do
    mkdir -p "$T/${f%/*}"
    cp "$ROOT/$f" "$T/$f"
  done < <(release_inputs)
  mkdir -p "$T/docs/release/payment-attempt-coordination/tests/local-pg"
  cp "$PINS" "$T/docs/release/payment-attempt-coordination/tests/local-pg/migrations.pins"
  verify_hashes "$T" || return 1
  for f in "supabase/migrations/$ATTEMPT_MIGRATION.sql" supabase/migrations/20261102140000_ops_report_et_day_boundaries.sql supabase/functions/primary-lapse-canceller/index.ts; do
    printf '\n' >> "$T/$f"
    if verify_hashes "$T"; then
      echo "::error::tamper-proof FAILED: mutated $f still passed the hash check" >&2
      return 1
    fi
    cp "$ROOT/$f" "$T/$f"
    echo "PASS tamper-proof: mutation of $f fails verification"
  done
}

# Offline wiring self-check: prove the scenario-isolation + exact-refusal markers
# are actually present in this script. Non-vacuous (asserts specific literals).
selfcheck_wiring() {
  local src="$0" want
  for want in \
    "precondition_failed: order has an unresolved payment attempt" \
    "sqlstate <> 'P0001'" \
    "order should remain pending after refusal" \
    "ci-cancel-positive" \
    "--maintenance-db=template1" \
    "oc_cancel" "oc_conc_main" "oc_conc_neg" \
    "assert_active_hold_preconditions" \
    "precondition_failed: active inventory holds exist; rollback refused" \
    "expected exactly 1 active hold" \
    "expected 0 unresolved attempts" \
    "expected 0 pending orders" \
    "is distinct from" \
    "exact disposable loopback database" ; do
    grep -qF -- "$want" "$src" || { echo "::error::wiring marker missing: $want" >&2; return 1; }
  done
  local mode
  for mode in success unresolved pending-order active-hold collision partial missing-rpc extra-overload; do
    grep -qF -- "$mode" "$src" || { echo "::error::rollback mode missing: $mode" >&2; return 1; }
  done
  echo "PASS wiring self-check: dedicated clones, exact cancel/active-hold refusals, 8 rollback modes"
}

# Offline clone-safety self-check: never clone from live `postgres` (busy), use
# the container's matching PostgreSQL tools, and snapshot/restore/clone/missing-
# container/version-mismatch failures must stop the job before any scenario/PASS.
selfcheck_clone() {
  local src="$0" want clone_body
  clone_body=$(sed -n '/^clone() {/,/^}/p' "$src")
  if printf '%s\n' "$clone_body" | grep -qF -- "-T postgres"; then
    echo "::error::clone still uses live postgres as a CREATE DATABASE template" >&2
    return 1
  fi
  for want in \
    "detect_db_container" \
    "verify_pg_version" \
    "verify_superuser_connection" \
    "compare_payment_rpc_acls" \
    "restore_template" \
    "supabase_db_" \
    "docker exec \"\$DB_CONTAINER\" pg_dump" \
    "docker exec \"\$DB_CONTAINER\" createdb" \
    "docker exec -i \"\$DB_CONTAINER\" psql -U supabase_admin" \
    "-f - < \"\$SNAPSHOT\"" \
    "PATH=\"\$HERE/bin:\$PATH\"" \
    "pg_dump -U postgres -d postgres --exclude-extension=pg_cron --exclude-schema=cron" \
    "-T \"\$TEMPLATE_DB\"" \
    "restore failed at snapshot line" \
    "::error::no Supabase database container" \
    "::error::pg_dump major" \
    "::error::cannot authenticate as supabase_admin" \
    "::error::snapshot of post-forward postgres failed" \
    "::error::template" \
    "::error::clone" ; do
    grep -qF -- "$want" "$src" || { echo "::error::clone-safety marker missing: $want" >&2; return 1; }
  done
  # Ownership is restored by the superuser restore: no --no-owner, no --no-privileges.
  local tmpl_body
  tmpl_body=$(sed -n '/^prepare_template() {/,/^}/p' "$src")
  if printf '%s\n' "$tmpl_body" | grep -qF -- "--no-owner"; then
    echo "::error::snapshot dump still uses --no-owner (ownership must be restored)" >&2
    return 1
  fi
  if printf '%s\n' "$tmpl_body" | grep -qF -- "--no-privileges"; then
    echo "::error::snapshot dump drops ACLs" >&2
    return 1
  fi
  # Only pg_cron is excluded (it is database-restricted); pg_net must stay.
  if printf '%s\n' "$tmpl_body" | grep -qF -- "exclude-extension=pg_net"; then
    echo "::error::snapshot dump excludes pg_net; keep pg_net unless it blocks restore" >&2
    return 1
  fi
  # Restore must stream stdin via `-f -` (psql line numbers), never `-b` echo-errors.
  local restore_body
  restore_body=$(sed -n '/^restore_template() {/,/^}/p' "$src")
  if printf '%s\n' "$restore_body" | grep -qF -- ' -b '; then
    echo "::error::restore still uses -b (echo-errors); use -f -" >&2
    return 1
  fi
  [ -x "$HERE/bin/pg_dump" ] || { echo "::error::pg_dump shim missing or not executable at $HERE/bin/pg_dump" >&2; return 1; }
  grep -qF -- 'docker exec "$DB_CONTAINER" pg_dump "${flags[@]}" -U postgres -d "$dbname"' "$HERE/bin/pg_dump" \
    || { echo "::error::pg_dump shim does not forward to the container tool" >&2; return 1; }
  echo "PASS clone self-check: container PG tools + supabase_admin superuser restore + pg_dump shim, idle template, never live postgres, failures stop"
}

# --- DB-dependent helpers (DB_URL required) -----------------------------------
# Exact disposable loopback target only. Any other value is rejected WITHOUT being
# echoed, so a misconfigured CI secret can never leak into the log.
require_db() {
  [ "${DB_URL:-}" = "postgresql://postgres:postgres@127.0.0.1:54322/postgres" ] \
    || { echo "::error::DB_URL must be the exact disposable loopback database (refusing to continue)" >&2; exit 1; }
}

parse_db() {
  local u="${DB_URL#*://}"
  DB_USER="${u%%:*}"; local rest="${u#*:}"
  DB_PASS="${rest%%@*}"; local hp="${rest#*@}"
  DB_HOST="${hp%%:*}"; local rp="${hp#*:}"
  DB_PORT="${rp%%/*}"; DB_NAME="${rp#*/}"
}

# DB operations that need a PostgreSQL-17 client run inside the running disposable
# Supabase database container (the host's postgresql-client is 16, and pg_dump 16
# refuses to dump a 17 server). The host `psql` is still used for the TCP-based
# scenario operations (psql 16 connects to a 17 server fine).
DB_CONTAINER="${DB_CONTAINER:-}"

detect_db_container() {
  if [ -n "$DB_CONTAINER" ]; then
    docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER" \
      || { echo "::error::database container $DB_CONTAINER is not running" >&2; return 1; }
  else
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^supabase_db_' | head -1)
    [ -n "$DB_CONTAINER" ] || { echo "::error::no Supabase database container running (supabase_db_*)" >&2; return 1; }
  fi
  export DB_CONTAINER
  echo "OK: database container $DB_CONTAINER"
}

verify_pg_version() {
  local server_major client_major
  server_major=$(docker exec "$DB_CONTAINER" psql -U postgres -d postgres -tAc "select current_setting('server_version_num')::int / 10000" 2>/dev/null | tr -d '[:space:]')
  client_major=$(docker exec "$DB_CONTAINER" pg_dump --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
  [ -n "$server_major" ] && [ -n "$client_major" ] || { echo "::error::could not read PostgreSQL version from container $DB_CONTAINER" >&2; return 1; }
  [ "$server_major" = "$client_major" ] || { echo "::error::pg_dump major $client_major != server major $server_major in $DB_CONTAINER (mismatched tools)" >&2; return 1; }
  echo "OK: PostgreSQL $server_major client matches server in $DB_CONTAINER"
}

# Verify the container's local connection can act as the superuser `supabase_admin`
# against the target template DB before restoring ownership-bearing objects.
verify_superuser_connection() {
  local target="$1" out role super db
  if ! out=$(docker exec "$DB_CONTAINER" psql -U supabase_admin -d "$target" -tAc \
        "select current_user || '|' || current_setting('is_superuser') || '|' || current_database()" 2>&1); then
    echo "::error::cannot authenticate as supabase_admin: $out" >&2
    return 1
  fi
  role=$(printf '%s\n' "$out" | cut -d'|' -f1)
  super=$(printf '%s\n' "$out" | cut -d'|' -f2)
  db=$(printf '%s\n' "$out" | cut -d'|' -f3)
  [ "$role" = "supabase_admin" ] || { echo "::error::connected role is $role, expected supabase_admin" >&2; return 1; }
  [ "$super" = "on" ] || { echo "::error::supabase_admin is_superuser=$super, expected on" >&2; return 1; }
  [ "$db" = "$target" ] || { echo "::error::target database is $db, expected $target" >&2; return 1; }
  echo "OK: supabase_admin (superuser=$super) connected to $db"
}

# After restore, the payment RPCs under test must keep their original owner and ACL.
compare_payment_rpc_acls() {
  local fn
  for fn in \
    'venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)' \
    'venue.cancel_pending_order(uuid,text,text)' \
    'venue.guard_order_cancel_attempts()'; do
    local o_src o_tpl a_src a_tpl
    o_src=$(docker exec "$DB_CONTAINER" psql -U supabase_admin -d postgres -tAc "select proowner::regrole::text from pg_proc where oid = to_regprocedure('$fn')")
    o_tpl=$(docker exec "$DB_CONTAINER" psql -U supabase_admin -d "$TEMPLATE_DB" -tAc "select proowner::regrole::text from pg_proc where oid = to_regprocedure('$fn')")
    a_src=$(docker exec "$DB_CONTAINER" psql -U supabase_admin -d postgres -tAc "select coalesce(proacl::text,'<null>') from pg_proc where oid = to_regprocedure('$fn')")
    a_tpl=$(docker exec "$DB_CONTAINER" psql -U supabase_admin -d "$TEMPLATE_DB" -tAc "select coalesce(proacl::text,'<null>') from pg_proc where oid = to_regprocedure('$fn')")
    [ "$o_src" = "$o_tpl" ] || { echo "::error::owner mismatch for $fn: postgres=$o_src $TEMPLATE_DB=$o_tpl" >&2; return 1; }
    [ "$a_src" = "$a_tpl" ] || { echo "::error::ACL mismatch for $fn: postgres=$a_src $TEMPLATE_DB=$a_tpl" >&2; return 1; }
  done
  echo "OK: payment RPC owners and grants match between postgres and $TEMPLATE_DB"
}

# Restore the snapshot into the template as the superuser. psql reads stdin as a
# script (`-f -`) so it reports the failing input line; stderr is captured privately
# and only the line number + sanitized ERROR summary are logged (no raw SQL, row
# data, DETAIL or CONTEXT).
restore_template() {
  local rc err errf line found
  errf="${SNAPSHOT}.restore-err"
  set +e
  docker exec -i "$DB_CONTAINER" psql -U supabase_admin -d "$TEMPLATE_DB" -X \
    -v ON_ERROR_STOP=1 -f - < "$SNAPSHOT" >/dev/null 2>"$errf"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    rm -f "$errf"
    return 0
  fi
  err="restore exited $rc"
  if found=$(grep -m1 -E '(ERROR|FATAL):' "$errf" 2>/dev/null); then
    err=$(printf '%s\n' "$found" | sed -E 's/^.*(ERROR|FATAL):[[:space:]]*//')
    [ -n "$err" ] || err="restore exited $rc"
  fi
  # psql reports the failing input line as  psql:<file>:<line>: ERROR ...
  line="unknown"
  if found=$(grep -m1 -oE ':[0-9]+: (ERROR|FATAL)' "$errf" 2>/dev/null); then
    line=$(printf '%s\n' "$found" | grep -oE '[0-9]+' | head -1)
  fi
  echo "::error::template $TEMPLATE_DB restore failed at snapshot line ${line:-unknown}: $err" >&2
  rm -f "$errf"
  return 1
}

# Take one consistent logical snapshot of the live post-forward `postgres` DB using
# the container's matching PostgreSQL tools, restore it (as the superuser
# `supabase_admin`, which alone can re-own objects and set superuser GUCs) into a
# dedicated IDLE template, then clone each scenario from that template. The live
# `postgres` DB is never used as a CREATE DATABASE template — it is busy.
prepare_template() {
  detect_db_container || return 1
  verify_pg_version || return 1

  docker exec "$DB_CONTAINER" pg_dump -U postgres -d postgres --exclude-extension=pg_cron --exclude-schema=cron > "$SNAPSHOT" \
    || { echo "::error::snapshot of post-forward postgres failed" >&2; return 1; }

  docker exec "$DB_CONTAINER" createdb -U postgres "$TEMPLATE_DB" \
    || { echo "::error::template $TEMPLATE_DB create failed" >&2; return 1; }

  verify_superuser_connection "$TEMPLATE_DB" || return 1
  restore_template || return 1
  compare_payment_rpc_acls || return 1

  echo "OK: post-forward snapshot restored into idle template $TEMPLATE_DB"
}

clone() { # name -> clone from the idle post-forward template (never live postgres)
  docker exec "$DB_CONTAINER" createdb -U postgres -T "$TEMPLATE_DB" "$1" \
    || { echo "::error::clone $1 failed" >&2; return 1; }
}
dburl() { echo "postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/$1"; }

assert_chain_applied() {
  local applied
  applied=$(psqlq -c "select count(*) from supabase_migrations.schema_migrations
                      where version in ('20261102120000','20261102130000','20261102140000','20261102150000',
                                        '20261102160000','20261102170000','20261102180000','20261102181000');")
  [ "$applied" = "8" ] || { echo "::error::198-205 chain not fully applied (applied=$applied, expected 8)"; exit 1; }
  echo "OK: all 8 reviewed 198-205 migrations applied"
}

assert_forward_preflight_refusal() {
  local fixture="$1" expected="$2" output rc
  shift 2
  # Seed and apply in the same session. ON_ERROR_STOP disconnects on the
  # expected refusal, rolling back the synthetic fixtures with the migration.
  if output=$(psql "$DB_URL" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q \
      -c 'begin' -f "$SEED" "$@" -f "$FORWARD" 2>&1); then
    echo "::error::forward accepted the $fixture fixture" >&2
    return 1
  else
    rc=$?
  fi
  if [ "$rc" -ne 3 ] || ! grep -qF "ERROR:  P0001: precondition_failed: payment-attempt preflight requires zero $expected; nothing changed" <<<"$output"; then
    printf '%s\n' "$output" >&2
    echo "::error::forward did not refuse $fixture for the expected reason" >&2
    return 1
  fi
  psqlq <<'SQL' || return 1
do $$
begin
  if exists (select 1 from auth.users where id = 'bbbbbbbb-0000-4000-8000-000000000001')
     or exists (select 1 from venue."order" where status = 'pending')
     or exists (select 1 from venue.inventory_hold where status = 'active')
     or to_regclass('venue.payment_attempt') is not null
     or to_regclass('venue.payment_attempt_event') is not null
     or to_regprocedure('venue.guard_order_cancel_attempts()') is not null then
    raise exception 'forward refusal left fixture data or coordination schema behind';
  end if;
end
$$;
SQL
  echo "OK: forward refused $fixture with no fixture or schema changes"
}

assert_cutover_refuses_live_writer() (
  local url="$1" file="$2" relation="$3" work pid='' output rc i lock_line
  lock_line=$(awk '/^lock table venue\./ { print NR }' "$file")
  [[ "$lock_line" =~ ^[0-9]+$ ]] || { echo "::error::expected one cutover lock statement in ${file##*/}" >&2; return 1; }
  work=$(mktemp -d)
  trap 'exec 3>&-; if [ -n "$pid" ]; then wait "$pid" || true; fi; rm -f "$work/input" "$work/writer.log"; rmdir "$work"' EXIT
  mkfifo "$work/input"
  psql "$url" -X -v ON_ERROR_STOP=1 -qAt <"$work/input" >"$work/writer.log" 2>&1 &
  pid=$!
  exec 3>"$work/input"
  printf 'begin;\nlock table %s in row exclusive mode;\nselect %s;\n' "$relation" "'writer-ready'" >&3
  for ((i=0; i<100; i++)); do
    if grep -qx 'writer-ready' "$work/writer.log"; then break; fi
    sleep 0.1
  done
  grep -qx 'writer-ready' "$work/writer.log" || { echo "::error::writer lock probe never became ready" >&2; return 1; }

  if output=$(psql "$url" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -q -f "$file" 2>&1); then
    echo "::error::${file##*/} ran while a writer held $relation" >&2
    return 1
  else
    rc=$?
  fi
  if [ "$rc" -ne 3 ] || ! grep -qF "psql:$file:$lock_line: ERROR:  55P03: canceling statement due to lock timeout" <<<"$output"; then
    printf '%s\n' "$output" >&2
    echo "::error::${file##*/} did not fail at the writer lock" >&2
    return 1
  fi
  echo "OK: ${file##*/} refused a live writer on $relation"
)

apply_forward() {
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -q -f "$FORWARD"
  echo "OK: registered migration applied in the isolated cutover rehearsal"
}

assert_legacy_payment_contract() {
  local url="$1" phase="$2"
  psql "$url" -X -v ON_ERROR_STOP=1 -q <<'SQL' || return 1
begin;
set local role service_role;
do $$
begin
  if to_regprocedure('venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)') is not null
     or to_regprocedure('venue.mark_payment_attempt_by_pi(text,text,text)') is not null then
    raise exception 'payment-attempt RPC unexpectedly available on legacy schema';
  end if;
  if md5(pg_get_functiondef(to_regprocedure('venue.cancel_pending_order(uuid,text,text)')))
       is distinct from '3d7fef64c44483586f46b568cb92c610'
     or not has_function_privilege(current_user, 'venue.cancel_pending_order(uuid,text,text)', 'EXECUTE') then
    raise exception 'legacy cancellation signature, body or grant changed';
  end if;
end
$$;
rollback;
SQL
  echo "OK: $phase exposes the legacy cancellation contract and no attempt begin/mark RPCs"
}

assert_legacy_cancel_after_rollback() {
  local url="$1"
  psql "$url" -X -v ON_ERROR_STOP=1 -q <<'SQL' || return 1
begin;
update venue."order" set status = 'pending' where order_id = 'aaaaaaaa-0000-4000-8000-000000000008';
set local role service_role;
select venue.cancel_pending_order('aaaaaaaa-0000-4000-8000-000000000008', 'payment_failed', 'ci-after-rollback');
reset role;
do $$
begin
  if (select status from venue."order" where order_id = 'aaaaaaaa-0000-4000-8000-000000000008')
       is distinct from 'cancelled' then
    raise exception 'legacy cancellation did not work after rollback';
  end if;
end
$$;
rollback;
SQL
  echo "OK: service_role can cancel through the legacy RPC after rollback"
}

assert_rpc_signatures() {
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qAt -c "
    do \$\$ begin
      if to_regprocedure('venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)') is null then raise exception 'missing begin_payment_attempt'; end if;
      if to_regprocedure('venue.store_payment_attempt_request(uuid,uuid,uuid,uuid,jsonb)') is null then raise exception 'missing store_payment_attempt_request'; end if;
      if to_regprocedure('venue.attach_payment_attempt(uuid,text,uuid,uuid,uuid,integer,integer,integer,text)') is null then raise exception 'missing attach_payment_attempt'; end if;
      if to_regprocedure('venue.mark_payment_attempt_by_pi(text,text,text)') is null then raise exception 'missing mark_payment_attempt_by_pi'; end if;
      if to_regprocedure('venue.read_payment_attempt_recovery(uuid,uuid,uuid)') is null then raise exception 'missing read_payment_attempt_recovery'; end if;
      if to_regprocedure('venue.read_payment_attempt_binding(uuid,text,uuid,uuid)') is null then raise exception 'missing read_payment_attempt_binding'; end if;
      if not coalesce(has_function_privilege('service_role', to_regprocedure('venue.read_lapse_payment_attempts(uuid,uuid,uuid)'), 'EXECUTE'), false) then raise exception 'lapse attempt read missing or not executable by service_role'; end if;
      if has_function_privilege('anon', 'venue.read_lapse_payment_attempts(uuid,uuid,uuid)', 'EXECUTE') or has_function_privilege('authenticated', 'venue.read_lapse_payment_attempts(uuid,uuid,uuid)', 'EXECUTE') then raise exception 'client roles must not read lapse attempts'; end if;
      if not coalesce(has_function_privilege('service_role', to_regprocedure('venue.is_settled_native_payment_replay(uuid,uuid,uuid,text,uuid,integer,text,boolean)'), 'EXECUTE'), false) then raise exception 'legacy replay proof missing or not executable by service_role'; end if;
      if has_function_privilege('anon', 'venue.is_settled_native_payment_replay(uuid,uuid,uuid,text,uuid,integer,text,boolean)', 'EXECUTE') or has_function_privilege('authenticated', 'venue.is_settled_native_payment_replay(uuid,uuid,uuid,text,uuid,integer,text,boolean)', 'EXECUTE') then raise exception 'client roles must not read legacy replay proof'; end if;
      if md5(pg_get_functiondef(to_regprocedure('venue.cancel_pending_order(uuid,text,text)'))) is distinct from '3d7fef64c44483586f46b568cb92c610' then raise exception 'cancel_pending_order pin mismatch or missing'; end if;
      if not has_function_privilege('service_role', 'venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)', 'EXECUTE') then raise exception 'begin grant missing for service_role'; end if;
      if not has_function_privilege('service_role', 'venue.cancel_pending_order(uuid,text,text)', 'EXECUTE') then raise exception 'cancel grant missing for service_role'; end if;
      if has_function_privilege('anon', 'venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)', 'EXECUTE') then raise exception 'anon must not execute begin'; end if;
    end \$\$;"
  echo "OK: RPC signatures and grants asserted"
}

# Cancellation refusal proves the NEW guard, in a dedicated clone, plus a positive control.
assert_cancellation_refusals() {
  local url; url=$(dburl oc_cancel)
  clone oc_cancel
  psql "$url" -X -v ON_ERROR_STOP=1 -q -f "$SEED"
  psql "$url" -X -v ON_ERROR_STOP=1 -q -f "$HERE/payment_attempt_seed_cancel.sql"
  psql "$url" -X -v ON_ERROR_STOP=1 -qAt <<'SQL'
do $$
declare
  v_order uuid := 'aaaaaaaa-0000-4000-8000-000000000005';
  v_pos   uuid := 'aaaaaaaa-0000-4000-8000-000000000006';
  v_state text;
begin
  insert into venue.payment_attempt
    (order_id, attempt_key, buyer_id, face_minor, buyer_fee_minor, amount_minor, currency, state)
  values (v_order, 'ci-guard-attempt', 'bbbbbbbb-0000-4000-8000-000000000001', 2500, 0, 2500, 'USD', 'creating');

  begin
    perform venue.cancel_pending_order(v_order, 'payment_failed', 'ci-cancel-guard');
    raise exception 'cancel did not refuse an unresolved attempt';
  exception when others then
    if sqlstate <> 'P0001' then raise exception 'wrong sqlstate: % (msg %)', sqlstate, sqlerrm; end if;
    if sqlerrm <> 'precondition_failed: order has an unresolved payment attempt' then
      raise exception 'wrong refusal message: %', sqlerrm;
    end if;
  end;

  select status into v_state from venue."order" where order_id = v_order;
  if v_state is distinct from 'pending' then raise exception 'order should remain pending after refusal (got %)', v_state; end if;

  update venue.payment_attempt
     set state = 'failed', pi_id = 'pi_ci_failed_binding',
         session_id = 'cccccccc-0000-4000-8000-000000000001'
   where order_id = v_order and attempt_key = 'ci-guard-attempt';
  if (venue.read_payment_attempt_binding(
        v_order, 'pi_ci_failed_binding', 'bbbbbbbb-0000-4000-8000-000000000001',
        'cccccccc-0000-4000-8000-000000000001'
      )->>'state') is distinct from 'failed' then
    raise exception 'failed attempt binding must be available for Stripe cancellation';
  end if;

  perform venue.cancel_pending_order(v_pos, 'payment_failed', 'ci-cancel-positive');
  select status into v_state from venue."order" where order_id = v_pos;
  if v_state is distinct from 'cancelled' then raise exception 'positive control did not cancel (got %)', v_state; end if;
end $$;
SQL
  echo "OK: cancellation refusal (P0001 + exact message + order stays pending) and positive control"
  echo "OK: failed attempt binding is available for Stripe cancellation"
}

assert_payment_attempt_lifecycle() {
  local url; url=$(dburl oc_lifecycle)
  clone oc_lifecycle
  psql "$url" -X -v ON_ERROR_STOP=1 -q \
    -f "$SEED" -f "$HERE/payment_attempt_seed_cancel.sql" -f "$HERE/payment_attempt_lifecycle.sql"
  echo "OK: service_role payment attempt lifecycle, lost-response recovery and forged cancellation refusal"
}

# Concurrency, two dedicated clones (never the mutated post-forward DB).
run_concurrency() {
  local main_url neg_url
  main_url=$(dburl oc_conc_main); neg_url=$(dburl oc_conc_neg)
  clone oc_conc_main; clone oc_conc_neg
  psql "$main_url" -X -v ON_ERROR_STOP=1 -q -f "$SEED"
  psql "$neg_url"  -X -v ON_ERROR_STOP=1 -q -f "$SEED"
  psql "$main_url" -X -v ON_ERROR_STOP=1 -q -f "$HERE/payment_attempt_seed_concurrency.sql"
  psql "$neg_url"  -X -v ON_ERROR_STOP=1 -q -f "$HERE/payment_attempt_seed_concurrency.sql"
  DB_URL="$main_url" NEGATIVE_DB_URL="$neg_url" \
    ORDER_BEGIN_FIRST='aaaaaaaa-0000-4000-8000-000000000001' \
    ORDER_CANCEL_FIRST='aaaaaaaa-0000-4000-8000-000000000002' \
    ORDER_NEGATIVE='aaaaaaaa-0000-4000-8000-000000000003' \
    bash "$DOCS/tests/two-connection-lock-test.sh"
  echo "OK: concurrency with separate negative-control clone"
}

# Active-hold precondition proof: exactly one active hold, no pending orders,
# no unresolved attempts, in that case's own clone.
assert_active_hold_preconditions() {
  local url="$1"
  psql "$url" -X -v ON_ERROR_STOP=1 -qAt <<'SQL'
do $$
declare n int;
begin
  insert into venue.payment_attempt
    (order_id, attempt_key, buyer_id, session_id, face_minor, buyer_fee_minor, amount_minor, currency, state, last_stripe_status)
  values ('aaaaaaaa-0000-4000-8000-000000000008','rollback-seed','bbbbbbbb-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001',5500,500,6000,'USD','canceled','canceled')
  on conflict (order_id, attempt_key) do update set state='canceled';

  update venue."order" set status='cancelled' where order_id = 'aaaaaaaa-0000-4000-8000-000000000008';
  update venue.inventory_hold set status='active' where hold_id = 'eeeeeeee-0000-4000-8000-000000000008';

  select count(*) into n from venue."order" where status = 'pending';
  if n <> 0 then raise exception 'active-hold precondition: expected 0 pending orders, got %', n; end if;
  select count(*) into n from venue.payment_attempt where state <> 'canceled';
  if n <> 0 then raise exception 'active-hold precondition: expected 0 unresolved attempts, got %', n; end if;
  select count(*) into n from venue.inventory_hold where status = 'active';
  if n <> 1 then raise exception 'active-hold precondition: expected exactly 1 active hold, got %', n; end if;
end $$;
SQL
  echo "OK: active-hold preconditions (0 pending, 0 unresolved, exactly 1 active hold)"
}

run_rollback_modes() {
  local mode db url
  for mode in $ROLLBACK_MODES; do
    db="oc_rb_${mode//-/_}"
    url=$(dburl "$db")
    clone "$db"
    psql "$url" -X -v ON_ERROR_STOP=1 -q -f "$SEED"
    psql "$url" -X -v ON_ERROR_STOP=1 -q -f "$HERE/payment_attempt_seed_rollback.sql"
    if [ "$mode" = "active-hold" ]; then
      assert_active_hold_preconditions "$url"
    fi
    PATH="$HERE/bin:$PATH" MODE="$mode" DB_URL="$url" \
      ORDER_ID='aaaaaaaa-0000-4000-8000-000000000008' \
      BUYER_ID='bbbbbbbb-0000-4000-8000-000000000001' \
      SESSION_ID='cccccccc-0000-4000-8000-000000000001' \
      HOLD_ID='eeeeeeee-0000-4000-8000-000000000008' \
      ATTEMPT_ROLLBACK_SQL="$ROLLBACK" bash "$DOCS/tests/rollback-safety-test.sh"
    if [ "$mode" = "success" ]; then
      assert_legacy_payment_contract "$url" post-rollback
      assert_legacy_cancel_after_rollback "$url"
    fi
    if [ "$mode" = "active-hold" ]; then
      grep -qF 'precondition_failed: active inventory holds exist; rollback refused' /tmp/oc-rollback-active-hold.log \
        || { echo "::error::active-hold refusal message not exact"; exit 1; }
    fi
    echo "OK: rollback mode $mode on fresh clone $db"
  done
}

run_migration_chain_rollback() {
  local url migration
  url=$(dburl oc_chain_rollback)
  clone oc_chain_rollback || return 1
  assert_cutover_refuses_live_writer "$url" "$ROLLBACK" venue.inventory_hold || return 1
  # The coordination schema is installed after 205, so retire it before
  # restoring the numbered migration predecessors on this isolated clone.
  psql "$url" -X -v ON_ERROR_STOP=1 -q -f "$ROLLBACK" || return 1
  assert_legacy_payment_contract "$url" before-numbered-rollbacks || return 1

  while IFS= read -r migration; do
    psql "$url" -X -v ON_ERROR_STOP=1 -q -f "$ROOT/supabase/rollbacks/${migration}_rollback.sql" \
      || { echo "::error::numbered rollback failed: $migration" >&2; return 1; }
    echo "OK: numbered rollback $migration passed its predecessor checks"
  done < <(printf '%s\n' "$CHAIN_198_205" | sort -r)

  psql "$url" -X -v ON_ERROR_STOP=1 -q <<'SQL' || return 1
do $$
begin
  if md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid,jsonb,uuid[],text)')))
       is distinct from '77004331198b9dad2e51e1ed2ceaef35'
     or exists (select 1 from pg_attribute
                where attrelid = 'venue.inventory_hold'::regclass
                  and attname = 'order_id' and not attisdropped) then
    raise exception 'numbered rollback chain did not restore the pre-198 checkout contract';
  end if;
end
$$;
SQL
  echo "OK: reverse migration chain restored the pre-198 checkout contract"
}

case "${1:-}" in
  --verify-inputs) verify_inputs; exit 0 ;;
  --tamper-proof)  verify_inputs; tamper_proof; exit 0 ;;
  --selfcheck-wiring) selfcheck_wiring; exit 0 ;;
  --selfcheck-clone) selfcheck_clone; exit 0 ;;
esac

require_db
parse_db
verify_inputs
assert_chain_applied
applied_tail=$(psqlq -c "select version from supabase_migrations.schema_migrations where version ~ '^[0-9]{14}$' and version >= '$ATTEMPT_VERSION' order by version")
if [ -n "$applied_tail" ]; then
  echo "::error::cutover rehearsal must start before migration $ATTEMPT_VERSION and all later migrations" >&2
  exit 1
fi
assert_legacy_payment_contract "$DB_URL" pre-forward
assert_cutover_refuses_live_writer "$DB_URL" "$FORWARD" 'venue."order"'
assert_cutover_refuses_live_writer "$DB_URL" "$FORWARD" venue.inventory_hold
assert_forward_preflight_refusal pending-order 'pending venue orders' \
  -f "$HERE/payment_attempt_seed_cancel.sql"
assert_forward_preflight_refusal active-hold 'active inventory holds' \
  -c "update venue.inventory_hold set status='active' where hold_id='eeeeeeee-0000-4000-8000-000000000008'"
apply_forward
assert_rpc_signatures
prepare_template
assert_cancellation_refusals
assert_payment_attempt_lifecycle
run_concurrency
run_rollback_modes
run_migration_chain_rollback
echo "PASS payment-attempt integration"
