#!/bin/bash
# LOCAL ARTIFACT ONLY — UNRUN. Do not execute against any DB in this task.
# One MODE per invocation. Every refusal mode requires its OWN fresh disposable
# clone at the forwarded state; success destroys the clone it runs on, so never
# pass the same clone to a later mode. No auto-create/reset/services.
#
#   MODE=success      DB_URL=... ORDER_ID=... BUYER_ID=... SESSION_ID=... HOLD_ID=... ./rollback-safety-test.sh
#   MODE=unresolved   DB_URL=<fresh clone> ORDER_ID=... ... ./rollback-safety-test.sh
#   MODE=pending-order|active-hold|collision|partial|missing-rpc|extra-overload ...
set -euo pipefail
: "${MODE:?success|unresolved|pending-order|active-hold|collision|partial|missing-rpc|extra-overload}"
: "${DB_URL:?disposable PG17 clone required}"
: "${ORDER_ID:?fixture order id required}"
: "${BUYER_ID:?fixture buyer id required}"
: "${SESSION_ID:?fixture session id required}"
: "${HOLD_ID:?fixture inventory_hold.hold_id required}"
HERE=$(cd "$(dirname "$0")" && pwd)
ROLLBACK="$HERE/../rollback.sql"
PSQL=(psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qAt)
sql() { "${PSQL[@]}" -c "$1"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
OUT=${ROLLBACK_EVID:-$(mktemp -d "${TMPDIR:-/tmp}/oc-rollback-evid.XXXXXX")}
mkdir -p "$OUT"

normalize_schema() { # strip only pg_dump random restrict/unrestrict tokens
  sed -E -e 's/^(\\restrict ).*/\1TOKEN/' -e 's/^(\\unrestrict ).*/\1TOKEN/'
}
schema_digest() { local out="${1:-/dev/null}"; pg_dump --schema-only --no-owner "$DB_URL" | tee "$out" | normalize_schema | shasum -a 256; }
data_digest() {
  local attempt event
  attempt=$(sql "select case when to_regclass('venue.payment_attempt') is not null then 'venue.payment_attempt' else 'venue.payment_attempt_retired_20261103' end") || return 1
  event=$(sql "select case when to_regclass('venue.payment_attempt_event') is not null then 'venue.payment_attempt_event' else 'venue.payment_attempt_event_retired_20261103' end") || return 1
  [ -n "$attempt" ] && [ -n "$event" ] || return 1
  # Full rows, canonical ordering; all attempt/event fields and timestamps.
  sql "select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.id), '')) from (
         select attempt_id::text as id, to_jsonb(a) as payload from $attempt a
         union all
         select event_id::text as id, to_jsonb(e) as payload from $event e) x"
}
full_digest() {
  local sfile="${1:-/dev/null}" s d
  s=$(schema_digest "$sfile") || return 1
  d=$(data_digest) || return 1
  printf '%s %s\n' "$s" "$d"
}
assert_fixture() {
  [ "$(sql "select count(*) from venue.\"order\" where order_id='$ORDER_ID' and buyer_id='$BUYER_ID' and event_session_id='$SESSION_ID'")" = 1 ] || fail "fixture order/buyer/session not unique"
  [ "$(sql "select count(*) from venue.inventory_hold where hold_id='$HOLD_ID'")" = 1 ] || fail "fixture hold_id not found (use the real inventory_hold.hold_id)"
}
seed_canceled_history() {
  sql "insert into venue.payment_attempt
         (order_id, attempt_key, buyer_id, session_id, face_minor, buyer_fee_minor, amount_minor, currency, state, last_stripe_status)
       values ('$ORDER_ID','rollback-seed','$BUYER_ID','$SESSION_ID',5500,500,6000,'USD','canceled','canceled')
       on conflict (order_id, attempt_key) do update set state='canceled'" || fail "seed attempt"
  sql "insert into venue.payment_attempt_event (attempt_id, event_kind, from_state, to_state, stripe_status)
       select attempt_id, 'mark', 'open', 'canceled', 'canceled'
         from venue.payment_attempt where order_id='$ORDER_ID' and attempt_key='rollback-seed'" || fail "seed event"
}
assert_active_gone() {
  local fn
  for fn in \
    'venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)' \
    'venue.store_payment_attempt_request(uuid,uuid,uuid,uuid,jsonb)' \
    'venue.attach_payment_attempt(uuid,text,uuid,uuid,uuid,integer,integer,integer,text)' \
    'venue.mark_payment_attempt(uuid,text,text)' \
    'venue.mark_payment_attempt_by_pi(text,text,text)' \
    'venue.read_payment_attempt_recovery(uuid,uuid,uuid)' \
    'venue.read_payment_attempt_binding(uuid,text,uuid,uuid)' \
    'venue.guard_order_cancel_attempts()'; do
    local got
    got=$(sql "select coalesce(to_regprocedure('$fn')::text,'')") || fail "active RPC query failed: $fn"
    [ -z "$got" ] || fail "active RPC remains: $fn"
  done
  [ "$(sql "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue' and p.proname in ('begin_payment_attempt','store_payment_attempt_request','attach_payment_attempt','mark_payment_attempt','mark_payment_attempt_by_pi','read_payment_attempt_recovery','read_payment_attempt_binding','guard_order_cancel_attempts')")" = 0 ] || fail "active overload remains"
}
assert_archive() {
  [ "$(sql "select count(*) from pg_trigger where tgrelid='venue.payment_attempt_event_retired_20261103'::regclass and tgname='payment_attempt_event_append_only' and not tgisinternal")" = 1 ] || fail "archive append-only trigger missing"
  [ -n "$(sql "select coalesce(to_regprocedure('venue.payment_attempt_event_append_only()')::text,'')")" ] || fail "archive append-only function missing"
}
assert_archive_writes_denied() {
  local rc
  for stmt in \
    "update venue.payment_attempt_event_retired_20261103 set to_state='x'" \
    "delete from venue.payment_attempt_event_retired_20261103" \
    "insert into venue.payment_attempt_event_retired_20261103 (attempt_id,event_kind,to_state) values (gen_random_uuid(),'mark','x')"; do
    set +e
    sql "set role service_role; $stmt" >/dev/null 2>&1
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "archive write allowed: $stmt"
  done
}

run_success() {
  seed_canceled_history
  local before after before2 after2
  before=$(data_digest) || fail "pre-rollback data digest"
  "${PSQL[@]}" -f "$ROLLBACK" || fail "rollback"
  after=$(data_digest) || fail "post-rollback data digest"
  [ "$before" = "$after" ] || fail "rollback changed archived history"
  assert_active_gone
  assert_archive
  assert_archive_writes_denied
  before2=$(full_digest "$OUT/schema-before2.sql") || fail "pre-rerun digest"
  "${PSQL[@]}" -f "$ROLLBACK" || fail "second rollback"
  after2=$(full_digest "$OUT/schema-after2.sql") || fail "post-rerun digest"
  if [ "$before2" != "$after2" ]; then
    { echo "=== schema-before2 vs schema-after2 (pg_dump --schema-only --no-owner) ==="; diff -u "$OUT/schema-before2.sql" "$OUT/schema-after2.sql"; } >"$OUT/schema-diff.diff" 2>&1 || true
    fail "second rollback mutated schema/history (diff: $OUT/schema-diff.diff, evidence: $OUT)"
  fi
  echo "PASS (success + rerun; disposable clone; evidence: $OUT)"
}

run_refusal() { # name, setup-sql, exact-error-substring
  local name="$1" setup="$2" expected="$3" before after rc
  seed_canceled_history
  sql "$setup" || fail "$name setup"
  before=$(full_digest) || fail "$name pre-digest"
  set +e
  "${PSQL[@]}" -f "$ROLLBACK" >"/tmp/oc-rollback-${name}.log" 2>&1
  rc=$?
  set -e
  after=$(full_digest) || fail "$name post-digest"
  [ "$rc" -ne 0 ] || fail "$name rollback did not refuse"
  grep -qF -- "$expected" "/tmp/oc-rollback-${name}.log" || { cat "/tmp/oc-rollback-${name}.log"; fail "$name wrong/absent refusal"; }
  [ "$before" = "$after" ] || fail "$name mutated schema/history"
  echo "PASS ($name refusal; disposable clone)"
}

assert_fixture
case "$MODE" in
  success) run_success ;;
  unresolved) run_refusal unresolved "update venue.payment_attempt set state='unknown' where order_id='$ORDER_ID' and attempt_key='rollback-seed'" 'unresolved payment attempts' ;;
  pending-order) run_refusal pending-order "update venue.\"order\" set status='pending' where order_id='$ORDER_ID'" 'pending venue orders' ;;
  active-hold) run_refusal active-hold "update venue.\"order\" set status='cancelled' where order_id='$ORDER_ID'; update venue.inventory_hold set status='active' where hold_id='$HOLD_ID'" 'active inventory holds' ;;
  collision) run_refusal collision "create table venue.payment_attempt_retired_20261103 (x int); create table venue.payment_attempt_event_retired_20261103 (x int)" 'collide' ;;
  partial) run_refusal partial "alter table venue.payment_attempt_event rename to payment_attempt_event_retired_20261103" 'partial active' ;;
  missing-rpc) run_refusal missing-rpc "drop function venue.mark_payment_attempt_by_pi(text,text,text)" 'missing/extra function overloads' ;;
  extra-overload) run_refusal extra-overload "create function venue.begin_payment_attempt(text) returns text language sql as 'select \$1'" 'missing/extra function overloads' ;;
  *) fail "unknown MODE=$MODE" ;;
esac
