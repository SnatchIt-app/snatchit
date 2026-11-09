#!/bin/bash
# LOCAL ARTIFACT ONLY — UNRUN. Do not execute in this task (no DB/services).
# Run only on disposable PG17 clones after forward.sql. DB_URL and
# NEGATIVE_DB_URL must be DIFFERENT disposable clones. DB_URL must already have
# three distinct pending venue."order" rows from the documented fixture:
#   ORDER_BEGIN_FIRST, ORDER_CANCEL_FIRST on DB_URL
#   ORDER_NEGATIVE on NEGATIVE_DB_URL, no attempt initially.
# Only order rows are used; inventory_hold is neither inspected nor mutated.
set -euo pipefail
: "${DB_URL:?disposable PG17 clone required}"
: "${NEGATIVE_DB_URL:?separate disposable PG17 clone required}"
: "${ORDER_BEGIN_FIRST:?distinct pending order required}"
: "${ORDER_CANCEL_FIRST:?distinct pending order required}"
: "${ORDER_NEGATIVE:?distinct pending order required}"
[ "$DB_URL" != "$NEGATIVE_DB_URL" ] || { echo "FAIL: DB_URL and NEGATIVE_DB_URL must be different clones" >&2; exit 1; }
[ "$ORDER_BEGIN_FIRST" != "$ORDER_CANCEL_FIRST" ] || { echo "FAIL: begin/cancel orders must be distinct" >&2; exit 1; }
[ "$ORDER_BEGIN_FIRST" != "$ORDER_NEGATIVE" ] || { echo "FAIL: begin/negative orders must be distinct" >&2; exit 1; }
[ "$ORDER_CANCEL_FIRST" != "$ORDER_NEGATIVE" ] || { echo "FAIL: cancel/negative orders must be distinct" >&2; exit 1; }
OUT=$(mktemp -d "${TMPDIR:-/tmp}/oc-atomic-2conn.XXXXXX")
PSQL=(psql "$DB_URL" -X -v ON_ERROR_STOP=1 -qAt)
PSQL_NEG=(psql "$NEGATIVE_DB_URL" -X -v ON_ERROR_STOP=1 -qAt)
sql() { "${PSQL[@]}" -c "$1"; }
sql_neg() { "${PSQL_NEG[@]}" -c "$1"; }
APID=""; BPID=""; AFD=""; BFD=""
cleanup() {
  local rc=$?
  for fd in "$AFD" "$BFD"; do [ -z "$fd" ] || eval "exec $fd>&-" 2>/dev/null || true; done
  [ -z "$APID" ] || kill "$APID" 2>/dev/null || true
  [ -z "$BPID" ] || kill "$BPID" 2>/dev/null || true
  [ -z "$APID" ] || wait "$APID" 2>/dev/null || true
  [ -z "$BPID" ] || wait "$BPID" 2>/dev/null || true
  APID=""; BPID=""
  if [ "$rc" -ne 0 ]; then
    echo "FAIL evidence retained (redacted): $OUT" >&2
  else
    rm -rf "$OUT"
  fi
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
wait_for_line() { # file, fixed substring, label
  local f="$1" needle="$2" label="$3" i
  for i in {1..100}; do
    grep -qF -- "$needle" "$f" 2>/dev/null && return 0
    sleep 0.1
  done
  fail "$label did not emit $needle (timeout/connection failure is not a PASS; evidence: $OUT)"
}
order_parts() { # URL, order -> buyer|session|face|currency|status
  local url="$1" order="$2"
  psql "$url" -X -v ON_ERROR_STOP=1 -qAt -F '|' -c \
    "select buyer_id::text, event_session_id::text, total_minor::text, currency, status
       from venue.\"order\" where order_id='$order'"
}
validate_order() { # URL, order, label -> O_BUYER O_SESSION O_FACE O_CURRENCY
  local url="$1" order="$2" label="$3" row status
  row=$(order_parts "$url" "$order") || fail "$label fixture query failed"
  [ "$(printf '%s\n' "$row" | grep -c .)" = 1 ] || fail "$label fixture must resolve to exactly one order"
  IFS='|' read -r O_BUYER O_SESSION O_FACE O_CURRENCY status <<<"$row"
  [ -n "$O_BUYER" ] && [ -n "$O_SESSION" ] && [ -n "$O_FACE" ] && [ -n "$O_CURRENCY" ] || fail "$label fixture incomplete"
  [ "$status" = "pending" ] || fail "$label must be pending before mutation (got $status)"
  [ "$O_CURRENCY" = "USD" ] || fail "$label currency must be USD (got $O_CURRENCY)"
}

# Validate all fixtures BEFORE any mutation.
validate_order "$DB_URL" "$ORDER_BEGIN_FIRST" "begin-first order"; BB=$O_BUYER; BS=$O_SESSION; BF=$O_FACE; BC=$O_CURRENCY
validate_order "$DB_URL" "$ORDER_CANCEL_FIRST" "cancel-first order"; CB=$O_BUYER; CS=$O_SESSION; CF=$O_FACE; CC=$O_CURRENCY
validate_order "$NEGATIVE_DB_URL" "$ORDER_NEGATIVE" "negative-control order"; NB=$O_BUYER; NS=$O_SESSION; NF=$O_FACE; NC=$O_CURRENCY

start_a() { # fifo, log; sets APID and AFD, feeds the pre-commit part
  local fifo="$1" log="$2"
  mkfifo "$fifo"
  "${PSQL[@]}" >"$log" 2>&1 <"$fifo" &
  APID=$!
  exec 3>"$fifo"
  AFD=3
}
feed_a() { printf '%s\n' "$1" >&3; }
release_a() { # marker, commit, then close A stdin
  local marker="$1"
  printf '%s\n' "commit;" "select '$marker';" >&3
  exec 3>&-
  AFD=""
}
reap_a() { wait "$APID" || fail "A failed"; APID=""; }
reap_b() { wait "$BPID" || fail "B connection/process failed"; BPID=""; }

echo "== 1. begin-first: A holds the order lock; B cancel starts and is observed waiting; then A commits =="
start_a "$OUT/a1.in" "$OUT/begin-first.out"
feed_a "begin;"
feed_a "select 'A_PID=' || pg_backend_pid();"
feed_a "select 'A_BEGIN=' || venue.begin_payment_attempt('$ORDER_BEGIN_FIRST','t-begin-first','$BB','$BS',$BF,0,$BF,'$BC')::text;"
feed_a "select 'A_READY';"
wait_for_line "$OUT/begin-first.out" "A_READY" "begin-first A"
APID_DB=$(grep -oE 'A_PID=[0-9]+' "$OUT/begin-first.out" | tail -1 | cut -d= -f2) || fail "begin-first A_PID missing"
[ -n "$APID_DB" ] || fail "begin-first A_PID empty"
"${PSQL[@]}" >"$OUT/cancel-b.out" 2>&1 <<SQL &
set statement_timeout='25s';
begin;
select 'B_PID=' || pg_backend_pid();
do \$b\$
begin
  begin
    perform venue.cancel_pending_order('$ORDER_BEGIN_FIRST','payment_failed','two-conn-cancel');
  exception when others then
    raise notice 'CANCEL_ERR=%|%', SQLSTATE, SQLERRM;
    return;
  end;
  raise exception 'UNEXPECTED_CANCEL_SUCCESS';
end
\$b\$;
rollback;
select 'B_DONE';
SQL
BPID=$!
wait_for_line "$OUT/cancel-b.out" "B_PID=" "begin-first B"
BPID_DB=$(grep -oE 'B_PID=[0-9]+' "$OUT/cancel-b.out" | tail -1 | cut -d= -f2) || fail "begin-first B_PID missing"
blocked=0
for i in {1..80}; do
  if [ "$(sql "select $APID_DB = any(pg_blocking_pids($BPID_DB))")" = "t" ]; then blocked=1; break; fi
  sleep 0.1
done
[ "$blocked" = 1 ] || fail "B was not observed blocked by A (timeout is not a PASS)"
release_a A_COMMITTED                                      # ONLY after observed B wait
reap_a
reap_b
grep -qF 'A_COMMITTED' "$OUT/begin-first.out" || fail "begin-first A did not commit"
grep -qF 'B_DONE' "$OUT/cancel-b.out" || fail "begin-first B did not finish cleanly"
grep -qF 'CANCEL_ERR=P0001|precondition_failed: order has an unresolved payment attempt' "$OUT/cancel-b.out" \
  || { cat "$OUT/cancel-b.out"; fail "begin-first missing exact trigger refusal"; }
[ "$(sql "select status from venue.\"order\" where order_id='$ORDER_BEGIN_FIRST'")" = "pending" ] || fail "begin-first order changed"
[ "$(sql "select state from venue.payment_attempt where order_id='$ORDER_BEGIN_FIRST' and attempt_key='t-begin-first'")" = "creating" ] || fail "begin-first attempt not creating"

echo "== 2. cancel-first: A holds cancel lock; B begin starts and is observed waiting; then A commits =="
start_a "$OUT/a2.in" "$OUT/cancel-first.out"
feed_a "begin;"
feed_a "select 'C_PID=' || pg_backend_pid();"
feed_a "with r as (select venue.cancel_pending_order('$ORDER_CANCEL_FIRST','payment_failed','two-conn-cancel-first') as body) select 'C_CANCEL=' || (body->>'status') || '|' || (body->>'order_id') from r;"
feed_a "select 'C_READY';"
wait_for_line "$OUT/cancel-first.out" "C_READY" "cancel-first A"
CPID_DB=$(grep -oE 'C_PID=[0-9]+' "$OUT/cancel-first.out" | tail -1 | cut -d= -f2) || fail "cancel-first C_PID missing"
grep -qF "C_CANCEL=cancelled|$ORDER_CANCEL_FIRST" "$OUT/cancel-first.out" || fail "cancel-first did not return exact cancelled JSON status/order"
"${PSQL[@]}" >"$OUT/begin-b.out" 2>&1 <<SQL &
set statement_timeout='20s';
begin;
select 'D_PID=' || pg_backend_pid();
do \$b\$
begin
  begin
    perform venue.begin_payment_attempt('$ORDER_CANCEL_FIRST','t-after-cancel','$CB','$CS',$CF,0,$CF,'$CC');
  exception when others then
    raise notice 'BEGIN_ERR=%|%', SQLSTATE, SQLERRM;
    return;
  end;
  raise exception 'UNEXPECTED_BEGIN_SUCCESS';
end
\$b\$;
rollback;
select 'D_DONE';
SQL
BPID=$!
wait_for_line "$OUT/begin-b.out" "D_PID=" "cancel-first B"
DPID_DB=$(grep -oE 'D_PID=[0-9]+' "$OUT/begin-b.out" | tail -1 | cut -d= -f2) || fail "cancel-first D_PID missing"
blocked=0
for i in {1..80}; do
  if [ "$(sql "select $CPID_DB = any(pg_blocking_pids($DPID_DB))")" = "t" ]; then blocked=1; break; fi
  sleep 0.1
done
[ "$blocked" = 1 ] || fail "begin after cancel was not observed waiting"
release_a C_COMMITTED
reap_a
reap_b
grep -qF 'C_COMMITTED' "$OUT/cancel-first.out" || fail "cancel-first A did not commit"
grep -qF 'D_DONE' "$OUT/begin-b.out" || fail "cancel-first B did not finish cleanly"
grep -qF 'BEGIN_ERR=P0001|precondition_failed: order_not_pending' "$OUT/begin-b.out" \
  || { cat "$OUT/begin-b.out"; fail "cancel-first missing exact order_not_pending"; }
[ "$(sql "select status from venue.\"order\" where order_id='$ORDER_CANCEL_FIRST'")" = "cancelled" ] || fail "cancel-first order not cancelled"
[ "$(sql "select count(*) from venue.payment_attempt where order_id='$ORDER_CANCEL_FIRST'")" = "0" ] || fail "cancel-first inserted an attempt"

echo "== 3. negative control: unresolved attempt, trigger disabled only inside rolled-back transaction =="
sql_neg "begin; select venue.begin_payment_attempt('$ORDER_NEGATIVE','t-negative','$NB','$NS',$NF,0,$NF,'$NC'); commit;" >/dev/null || fail "negative-control seed begin failed"
NEG_OUT=$OUT/negative.out
sql_neg "set statement_timeout='15s';
begin;
alter table venue.\"order\" disable trigger guard_order_cancel_attempts;
with r as (select venue.cancel_pending_order('$ORDER_NEGATIVE','payment_failed','two-conn-negative') as body)
  select 'NEG_CANCEL=' || (body->>'status') || '|' || (body->>'order_id') from r;
rollback;" >"$NEG_OUT" 2>&1 || fail "negative-control transaction failed (not a PASS)"
grep -qF "NEG_CANCEL=cancelled|$ORDER_NEGATIVE" "$NEG_OUT" || { cat "$NEG_OUT"; fail "negative control did not return exact cancelled JSON status/order"; }
[ "$(sql_neg "select status from venue.\"order\" where order_id='$ORDER_NEGATIVE'")" = "pending" ] || fail "negative control did not roll back order"
[ "$(sql_neg "select state from venue.payment_attempt where order_id='$ORDER_NEGATIVE' and attempt_key='t-negative'")" = "creating" ] || fail "negative control did not preserve attempt"
[ "$(sql_neg "select count(*) from pg_trigger where tgrelid='venue.\"order\"'::regclass and tgname='guard_order_cancel_attempts' and tgenabled <> 'D' and not tgisinternal")" = "1" ] || fail "negative control did not restore trigger"

echo "PASS (bidirectional lock waits observed; exact refusals; rolled-back negative control)"
