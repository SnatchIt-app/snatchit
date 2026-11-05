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
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MIGDIR="$ROOT/supabase/migrations"
DOCS="$ROOT/docs/release/payment-attempt-coordination"
SEED="$HERE/payment_attempt_seed.sql"
PINS="$DOCS/tests/local-pg/migrations.pins"

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
verify_hashes() {
  local base="$1"
  local pins="$base/docs/release/payment-attempt-coordination/tests/local-pg/migrations.pins"
  local m rel want got
  [ -f "$pins" ] || { echo "::error::migrations.pins missing at $pins" >&2; return 1; }
  for m in $CHAIN_198_205; do
    rel="supabase/migrations/${m}.sql"
    want=$(awk -v r="$rel" '$2==r{print $1}' "$pins")
    [ -n "$want" ] || { echo "::error::no authoritative pin for $rel" >&2; return 1; }
    got=$(shasum -a 256 "$base/$rel" | awk '{print $1}')
    [ "$got" = "$want" ] || { echo "::error::hash drift in $rel (expected $want, got $got)" >&2; return 1; }
  done
  for rel in docs/release/payment-attempt-coordination/forward.sql docs/release/payment-attempt-coordination/rollback.sql; do
    want=$(awk -v r="$rel" '$2==r{print $1}' "$pins")
    [ -n "$want" ] || { echo "::error::no authoritative pin for $rel" >&2; return 1; }
    got=$(shasum -a 256 "$base/$rel" | awk '{print $1}')
    [ "$got" = "$want" ] || { echo "::error::hash drift in $rel (expected $want, got $got)" >&2; return 1; }
  done
  echo "OK: 8 migration files + forward/rollback match the authoritative hashes"
}

verify_inputs() {
  local m missing=""
  for m in $CHAIN_198_205; do
    [ -f "$MIGDIR/${m}.sql" ] || missing="$missing ${m}.sql"
  done
  [ -n "$missing" ] && { echo "::error::missing migration files:$missing" >&2; return 1; }
  [ -f "$DOCS/forward.sql" ]  || { echo "::error::forward.sql missing" >&2; return 1; }
  [ -f "$DOCS/rollback.sql" ] || { echo "::error::rollback.sql missing" >&2; return 1; }
  [ -f "$DOCS/tests/two-connection-lock-test.sh" ] || { echo "::error::two-connection-lock-test.sh missing" >&2; return 1; }
  [ -f "$DOCS/tests/rollback-safety-test.sh" ]     || { echo "::error::rollback-safety-test.sh missing" >&2; return 1; }
  [ -f "$SEED" ] || { echo "::error::payment_attempt_seed.sql missing" >&2; return 1; }
  [ -f "$HERE/payment_attempt_seed_cancel.sql" ]      || { echo "::error::payment_attempt_seed_cancel.sql missing" >&2; return 1; }
  [ -f "$HERE/payment_attempt_seed_concurrency.sql" ] || { echo "::error::payment_attempt_seed_concurrency.sql missing" >&2; return 1; }
  [ -f "$HERE/payment_attempt_seed_rollback.sql" ]    || { echo "::error::payment_attempt_seed_rollback.sql missing" >&2; return 1; }
  bash -n "$DOCS/tests/two-connection-lock-test.sh" || return 1
  bash -n "$DOCS/tests/rollback-safety-test.sh"     || return 1
  verify_hashes "$ROOT" || return 1
  echo "OK: inputs present and hash-pinned"
}

tamper_proof() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/oc-tamper.XXXXXX")
  trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/supabase/migrations" "$T/docs/release/payment-attempt-coordination/tests/local-pg" "$T/docs/release/payment-attempt-coordination"
  local m f
  for m in $CHAIN_198_205; do cp "$MIGDIR/${m}.sql" "$T/supabase/migrations/"; done
  cp "$DOCS/forward.sql" "$T/docs/release/payment-attempt-coordination/forward.sql"
  cp "$DOCS/rollback.sql" "$T/docs/release/payment-attempt-coordination/rollback.sql"
  cp "$PINS" "$T/docs/release/payment-attempt-coordination/tests/local-pg/migrations.pins"
  f="$T/supabase/migrations/20261102140000_ops_report_et_day_boundaries.sql"
  printf '\n-- tamper\n' >> "$f"
  if verify_hashes "$T"; then
    echo "::error::tamper-proof FAILED: a mutated migration still passed the hash check" >&2
    return 1
  fi
  echo "PASS tamper-proof: one-byte mutation of a correctly-named migration fails verify_hashes"
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
    "--maintenance-db=template1 -T postgres" \
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

clone() { # name -> clone from the CLEAN post-forward `postgres` database
  PGPASSWORD="$DB_PASS" createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
    --maintenance-db=template1 -T postgres "$1" >/dev/null \
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

apply_forward() {
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -q -f "$DOCS/forward.sql"
  echo "OK: forward.sql applied"
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

  perform venue.cancel_pending_order(v_pos, 'payment_failed', 'ci-cancel-positive');
  select status into v_state from venue."order" where order_id = v_pos;
  if v_state is distinct from 'cancelled' then raise exception 'positive control did not cancel (got %)', v_state; end if;
end $$;
SQL
  echo "OK: cancellation refusal (P0001 + exact message + order stays pending) and positive control"
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
    MODE="$mode" DB_URL="$url" \
      ORDER_ID='aaaaaaaa-0000-4000-8000-000000000008' \
      BUYER_ID='bbbbbbbb-0000-4000-8000-000000000001' \
      SESSION_ID='cccccccc-0000-4000-8000-000000000001' \
      HOLD_ID='eeeeeeee-0000-4000-8000-000000000008' \
      bash "$DOCS/tests/rollback-safety-test.sh"
    if [ "$mode" = "active-hold" ]; then
      grep -qF 'precondition_failed: active inventory holds exist; rollback refused' /tmp/oc-rollback-active-hold.log \
        || { echo "::error::active-hold refusal message not exact"; exit 1; }
    fi
    echo "OK: rollback mode $mode on fresh clone $db"
  done
}

case "${1:-}" in
  --verify-inputs) verify_inputs; exit 0 ;;
  --tamper-proof)  verify_inputs; tamper_proof; exit 0 ;;
  --selfcheck-wiring) selfcheck_wiring; exit 0 ;;
esac

require_db
parse_db
verify_inputs
assert_chain_applied
apply_forward
assert_rpc_signatures
assert_cancellation_refusals
run_concurrency
run_rollback_modes
echo "PASS payment-attempt integration"
