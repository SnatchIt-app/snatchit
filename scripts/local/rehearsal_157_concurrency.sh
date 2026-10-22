#!/usr/bin/env bash
# ============================================================================
# scripts/local/rehearsal_157_concurrency.sh — LOCAL-ONLY two-session proof for migration 157
# (20261021100000_ops_money_action_unsettled_guard.sql). pgTAP runs in one transaction and cannot show a
# lock wait; this drives real concurrent sessions against throwaway loopback clones.
#
#   usage: scripts/local/rehearsal_157_concurrency.sh <db_with_157> <control_db_without_157>
#   both names must start with a_sprint_ (a_sprint_prod_replay / _prod_template / _chain are refused);
#   host must be 127.0.0.1. Model: scripts/rehearsal_132_concurrency.sh.
#
# Scenarios (each prints PASS/FAIL). "Waited" is a LOCK-WAIT INDICATOR, never a wall-clock bound: pg_stat_activity
# is polled while session 2 runs and must show it in a heavyweight Lock wait of the expected kind (wait_event
# 'advisory' for the order lock, 'transactionid' for a unique-index wait); the elapsed ms are printed for information.
#   G1 session 1 BEGIN; execute_action(refund_execute P, k1) and holds the transaction; session 2
#      execute_action(refund_execute P, k2) WAITS on the order advisory lock, then returns
#      duplicate_unsettled naming session 1's action once session 1 commits. Exactly one unsettled row.
#   G2 the same for payout_release on transfer T.
#   G3 cross pair: session 1 refund_execute on P, session 2 payout_release on T(P) -> waits, then
#      duplicate_unsettled (cross_type). G3R the reverse order (payout first, then refund).
#   G4 CONTROL — G1 against the clone WITHOUT 157: session 2 does not wait and both requests park:
#      two unsettled rows (the defect, reproduced on the same fixture). "Does not wait" is a lock-wait
#      indicator, not a wall-clock bound (a < 1000 ms check flaked at 1018 ms under load): session 2 runs under
#      lock_timeout 500ms, so any wait on session 1's locks (which it holds 3 s) errors, and pg_stat_activity,
#      polled while session 2 runs, must never show it in a Lock wait (wait_event 'advisory' under 157).
#   G5 same-key race: session 2 reuses session 1's key -> waits (advisory), then idempotent_replay of session 1's
#      action (never duplicate_unsettled, never a second row): the re-check after the lock answers.
#   G7 same-key race on a NON-MONEY type (case_create: no advisory lock): session 2's key lookup misses session 1's
#      uncommitted row, its INSERT waits on the unique index (transactionid), then raises 23505 on
#      action_idempotency_key_key and the constraint-aware handler answers idempotent_replay of session 1's action
#      (the handler branch pgTAP 224 T3.6 can only simulate). One row for the key.
#   G6 approve race on a LEGACY cross pair (two awaiting rows written directly, as before 157): session 1
#      approves the refund and holds; session 2 approving the payout WAITS, then is refused
#      duplicate_unsettled and the payout's approval stays pending (transfer untouched).
#   C1 CONTROL — an execute_action copy WITHOUT the order lock and blocker check (index kept): session 2
#      waits on the backstop index instead (transactionid, not advisory), then the constraint-aware handler answers
#      duplicate_unsettled (never idempotent_replay with a NULL action_id). One unsettled row.
#   C2 CONTROL — an approve_action copy WITHOUT the advisory lock: G6's session 2 runs its recheck before
#      session 1 commits, cannot see session 1's 'processing', and releases the payout while the refund is in
#      flight (refund processing + payout succeeded): the lock is what makes the approve-time recheck sound.
# Fixtures are committed under fixed ids (15700000-...) and LEFT IN PLACE: ops.audit is append-only, so the
# rows cannot be fully removed. Run only on throwaway clones; drop them afterwards.
# SAFETY: loopback only (127.0.0.1); scrubs remote connection variables. bash 3.2.
# ============================================================================
set -uo pipefail
unset SUPABASE_DB_URL DATABASE_URL POSTGRES_URL PGSERVICE PGSERVICEFILE PGPASSWORD PGPASSFILE PGURL PGDATABASE TEST_DB_URL 2>/dev/null
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}" PGPORT="${REHEARSAL_PGPORT:-5432}" PGUSER="${REHEARSAL_PGUSER:-postgres}" PGCONNECT_TIMEOUT=5 LC_ALL=C
[ "$PGHOST" = "127.0.0.1" ] || { echo "refusing host '$PGHOST': only 127.0.0.1" >&2; exit 1; }
DB="${1:-}"; CDB="${2:-}"
for d in "$DB" "$CDB"; do
  case "$d" in
    a_sprint_prod_replay|a_sprint_prod_template|a_sprint_chain) echo "refusing reserved database '$d'" >&2; exit 1 ;;
    a_sprint_*) ;;
    *) echo "refusing database '$d': name must start with a_sprint_ (usage: $0 <db_with_157> <control_db_without_157>)" >&2; exit 1 ;;
  esac
done
[ "$DB" != "$CDB" ] || { echo "the two databases must differ" >&2; exit 1; }
q()  { psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
srv=$(q "$DB" "select coalesce(host(inet_server_addr()),'socket')") || exit 1
case "$srv" in 127.0.0.1|::1|socket) ;; *) echo "refusing: server address $srv is not loopback" >&2; exit 1 ;; esac
[ "$(q "$DB"  "select to_regclass('ops.action_money_unsettled_uidx') is not null")" = "t" ] || { echo "157 not applied to $DB" >&2; exit 1; }
[ "$(q "$CDB" "select to_regclass('ops.action_money_unsettled_uidx') is null and to_regprocedure('ops.money_order_id(text,uuid)') is null")" = "t" ] || { echo "$CDB must NOT have 157" >&2; exit 1; }

A=15700000-0000-0000-0000-0000000000a1      # founder A (platform_admin via admin_users)
B=15700000-0000-0000-0000-0000000000a2      # founder B
S=15700000-0000-0000-0000-000000000051      # seller
U=15700000-0000-0000-0000-0000000000b1      # buyer
L() { printf '15700000-0000-0000-0001-%012d' "$1"; }
P() { printf '15700000-0000-0000-0002-%012d' "$1"; }
T() { printf '15700000-0000-0000-0003-%012d' "$1"; }
claims() { printf '{"sub":"%s","role":"authenticated","aal":"aal2"}' "$1"; }
as_founder() { printf "select set_config('request.jwt.claims', '%s', true); set local role authenticated;" "$(claims "$1")"; }
UNSETTLED="('requested','awaiting_approval','processing','unknown','succeeded_at_provider')"

seed() {  # $1 db: users, admin_users, eight orders (listing + succeeded payment + seller_sent transfer), refunds on
  q "$1" "
    insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    select x.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', x.email, '{\"provider\":\"email\"}', '{}', now(), now()
      from (values ('$A'::uuid, 'r157-a@test.local'), ('$B'::uuid, 'r157-b@test.local'), ('$S'::uuid, 'r157-s@test.local'), ('$U'::uuid, 'r157-u@test.local')) x(id, email)
    on conflict (id) do nothing;
    insert into public.profiles (id, full_name, display_name)
    select x.id, '', x.label from (values ('$A'::uuid, 'R157 A'), ('$B'::uuid, 'R157 B'), ('$S'::uuid, 'R157 S'), ('$U'::uuid, 'R157 U')) x(id, label)
    on conflict (id) do nothing;
    insert into public.admin_users (user_id, label) values ('$A', 'R157 FOUNDER A'), ('$B', 'R157 FOUNDER B') on conflict (user_id) do nothing;
    insert into public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
                                 starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
    select ('15700000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid, '$S', 'R157 #' || n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 2,
           'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'r157.jpg', 'active'
      from generate_series(1, 8) n on conflict (id) do nothing;
    insert into public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
    select ('15700000-0000-0000-0002-' || lpad(n::text, 12, '0'))::uuid, ('15700000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid, '$U', '$S',
           10000, 1000, 1000, 11000, 'pi_r157_' || n, 'succeeded', 'buy_now', now()
      from generate_series(1, 8) n on conflict (id) do nothing;
    insert into public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at,
                                  transfer_evidence_path, expires_at)
    select ('15700000-0000-0000-0003-' || lpad(n::text, 12, '0'))::uuid, ('15700000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid,
           ('15700000-0000-0000-0002-' || lpad(n::text, 12, '0'))::uuid, '$S', '$U', 'mobile_transfer', 'seller_sent', now(), now() + interval '72 hours',
           'r157-evidence.jpg', now() + interval '24 hours'
      from generate_series(1, 8) n on conflict (id) do nothing;
    update ops.setting set value = 'true'::jsonb where key = 'refund_execute_enabled';" >/dev/null
}
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
ex() {  # db who key type kind subject  -> one line "status|reject_reason|action_id|blocking_action_id|conflict"
  printf "begin; %s select 'R=' || concat_ws('|', coalesce(r->>'status',''), coalesce(r->>'reject_reason',''), coalesce(r->>'action_id',''), coalesce(r#>>'{blocking,action_id}',''), coalesce(r#>>'{blocking,conflict}',''))
          from (select ops.execute_action('%s','%s','%s','%s','{}'::jsonb,'rehearsal 157') r) x; commit;" "$(as_founder "$2")" "$3" "$4" "$5" "$6"
}
hold_ex() {  # same as ex, but holds the transaction 3 s after the call
  printf "begin; %s select 'R=' || concat_ws('|', coalesce(r->>'status',''), coalesce(r->>'reject_reason',''), coalesce(r->>'action_id','')) from (select ops.execute_action('%s','%s','%s','%s','{}'::jsonb,'rehearsal 157') r) x; select pg_sleep(3); commit;" \
    "$(as_founder "$2")" "$3" "$4" "$5" "$6"
}
field() { printf '%s' "$1" | cut -d'|' -f"$2"; }
unsettled() { q "$1" "select count(*) from ops.action where action_type in ('refund_execute','payout_release') and subject_id in ('$(P "$2")','$(T "$2")') and state in $UNSETTLED"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0
report() { if [ "$2" = "PASS" ]; then echo "  PASS $1 — $3"; else echo "  FAIL $1 — $3"; fail=1; fi; }

# race <db> <session-1 sql> <session-2 sql> : runs s1 in the background and starts s2 only once s1 is inside its
# 3 s hold (pg_stat_activity: application_name r157_s1, wait_event PgSleep), so s1 has made its call and holds
# its locks; sets R1, R2, W (ms s2 took) and LW: the heavyweight-lock waits pg_stat_activity showed for s2
# (application_name r157_s2, wait_event_type Lock, e.g. 'advisory'), polled while s2 runs; 'none' if never seen.
# Fixed sleeps proved flaky under load (a first run started s2 first).
race() {
  ( PGAPPNAME=r157_s1 psql -X -At -d "$1" -c "$2" > "$TMP/s1" 2>&1 ) &
  local p1=$! i=0
  until [ "$(q "$1" "select count(*) from pg_stat_activity where application_name = 'r157_s1' and wait_event = 'PgSleep'")" = "1" ] || [ $i -ge 200 ]; do
    sleep 0.05; i=$((i + 1))
  done
  [ $i -ge 200 ] && echo "  (warning: session 1 never reached its hold; the result below is not a race)"
  local t0; t0=$(ms)
  ( PGAPPNAME=r157_s2 psql -X -At -d "$1" -c "$3" > "$TMP/s2" 2>&1 ) &
  local p2=$! w
  : > "$TMP/lw"
  while kill -0 "$p2" 2>/dev/null; do
    w=$(q "$1" "select coalesce(string_agg(distinct wait_event, ','), '') from pg_stat_activity where application_name = 'r157_s2' and wait_event_type = 'Lock'")
    [ -n "$w" ] && echo "$w" >> "$TMP/lw"
    sleep 0.02
  done
  wait "$p2"; local t1; t1=$(ms); wait "$p1"
  W=$((t1 - t0)); R1=$(grep '^R=' "$TMP/s1" | sed 's/^R=//'); R2=$(grep '^R=' "$TMP/s2" | sed 's/^R=//')
  grep -qi 'deadlock\|ERROR' "$TMP/s1" && R1="ERROR:$(grep -i error "$TMP/s1" | head -1)"
  grep -qi 'ERROR' "$TMP/s2" && R2="ERROR:$(grep -i error "$TMP/s2" | head -1)"
  LW=$(sort -u "$TMP/lw" | tr '\n' ' ' | sed 's/ $//'); [ -n "$LW" ] || LW=none
}

echo "157 concurrency rehearsal: db=$DB control=$CDB $(date -u +%FT%TZ)"
seed "$DB"; seed "$CDB"

# G1: refund vs refund, order 1
race "$DB" "$(hold_ex "$DB" $A k157-g1-a refund_execute payment "$(P 1)")" "$(ex "$DB" $B k157-g1-b refund_execute payment "$(P 1)")"
n=$(unsettled "$DB" 1)
[ "$(field "$R1" 1)" = "awaiting_approval" ] && [ "$(field "$R2" 2)" = "duplicate_unsettled" ] && [ "$(field "$R2" 4)" = "$(field "$R1" 3)" ] && [ "$LW" = "advisory" ] && [ "$n" = "1" ] \
  && report G1 PASS "s1=$(field "$R1" 1) (held 3 s); s2 waited on the order lock ($LW; ${W}ms informational) then $(field "$R2" 1)/$(field "$R2" 2) blocking=s1 ($(field "$R2" 5)); unsettled rows=$n" \
  || report G1 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) unsettled=$n"

# G2: payout vs payout, order 2
race "$DB" "$(hold_ex "$DB" $A k157-g2-a payout_release transfer "$(T 2)")" "$(ex "$DB" $B k157-g2-b payout_release transfer "$(T 2)")"
n=$(unsettled "$DB" 2)
[ "$(field "$R1" 1)" = "awaiting_approval" ] && [ "$(field "$R2" 2)" = "duplicate_unsettled" ] && [ "$(field "$R2" 4)" = "$(field "$R1" 3)" ] && [ "$LW" = "advisory" ] && [ "$n" = "1" ] \
  && report G2 PASS "s1=$(field "$R1" 1) (held 3 s); s2 waited on the order lock ($LW; ${W}ms informational) then $(field "$R2" 1)/$(field "$R2" 2) blocking=s1 ($(field "$R2" 5)); unsettled rows=$n" \
  || report G2 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) unsettled=$n"

# G3: refund on P3, then payout on T3 (cross pair)
race "$DB" "$(hold_ex "$DB" $A k157-g3-a refund_execute payment "$(P 3)")" "$(ex "$DB" $B k157-g3-b payout_release transfer "$(T 3)")"
n=$(unsettled "$DB" 3)
[ "$(field "$R1" 1)" = "awaiting_approval" ] && [ "$(field "$R2" 2)" = "duplicate_unsettled" ] && [ "$(field "$R2" 5)" = "cross_type" ] && [ "$LW" = "advisory" ] && [ "$n" = "1" ] \
  && report G3 PASS "refund s1=$(field "$R1" 1); payout s2 waited on the order lock ($LW; ${W}ms informational) then $(field "$R2" 2) ($(field "$R2" 5)); unsettled rows=$n" \
  || report G3 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) unsettled=$n"
# G3R: payout on T4 first, then refund on P4
race "$DB" "$(hold_ex "$DB" $A k157-g3r-a payout_release transfer "$(T 4)")" "$(ex "$DB" $B k157-g3r-b refund_execute payment "$(P 4)")"
n=$(unsettled "$DB" 4)
[ "$(field "$R1" 1)" = "awaiting_approval" ] && [ "$(field "$R2" 2)" = "duplicate_unsettled" ] && [ "$(field "$R2" 5)" = "cross_type" ] && [ "$LW" = "advisory" ] && [ "$n" = "1" ] \
  && report G3R PASS "payout s1=$(field "$R1" 1); refund s2 waited on the order lock ($LW; ${W}ms informational) then $(field "$R2" 2) ($(field "$R2" 5)); unsettled rows=$n" \
  || report G3R FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) unsettled=$n"

# G4: CONTROL — G1 on the clone without 157. "s2 did not wait" = no lock wait, not a wall-clock bound: s2 runs
# under lock_timeout 500ms (a wait on s1's 3 s hold would raise) and pg_stat_activity never showed it in a Lock wait.
s2=$(ex "$CDB" $B k157-g4-b refund_execute payment "$(P 1)" | sed "s/^begin; /begin; set local lock_timeout = '500ms'; /")
case "$s2" in "begin; set local lock_timeout = '500ms'; "*) ;; *) echo "  FAIL G4 — could not build session 2's SQL"; fail=1 ;; esac
race "$CDB" "$(hold_ex "$CDB" $A k157-g4-a refund_execute payment "$(P 1)")" "$s2"
n=$(unsettled "$CDB" 1)
[ "$(field "$R1" 1)" = "awaiting_approval" ] && [ "$(field "$R2" 1)" = "awaiting_approval" ] && [ "$LW" = "none" ] && [ "$n" = "2" ] \
  && report G4 PASS "CONTROL without 157: s2 never waited on a lock (Lock waits seen: $LW; lock_timeout 500ms not hit; ${W}ms, informational) while s1 held its transaction; both parked ($(field "$R1" 1) / $(field "$R2" 1)): $n unsettled refund rows on one payment — the defect" \
  || report G4 FAIL "control did not reproduce the defect: s1=$R1 s2=$R2 s2 Lock waits=$LW (${W}ms) unsettled=$n"

# G5: same-key race, order 5
race "$DB" "$(hold_ex "$DB" $A k157-g5-same refund_execute payment "$(P 5)")" "$(ex "$DB" $B k157-g5-same refund_execute payment "$(P 5)")"
rows=$(q "$DB" "select count(*) from ops.action where idempotency_key = 'k157-g5-same'")
[ "$(field "$R1" 1)" = "awaiting_approval" ] && [ "$(field "$R2" 1)" = "idempotent_replay" ] && [ "$(field "$R2" 3)" = "$(field "$R1" 3)" ] && [ "$LW" = "advisory" ] && [ "$rows" = "1" ] \
  && report G5 PASS "same key: s2 waited on the order lock ($LW; ${W}ms informational) then $(field "$R2" 1) of s1's action; rows for the key=$rows" \
  || report G5 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) rows=$rows"

# G7: same-key race on a NON-MONEY type (no advisory lock): s2's INSERT waits on the unique index, then the handler
# answers idempotent_replay of s1's committed row (the branch pgTAP 224 T3.6 can only simulate in one session).
g7() {  # who hold(0|1): case_create with the shared key k157-g7-same
  local hold=""; [ "$2" = "1" ] && hold="select pg_sleep(3);"
  printf "begin; %s select 'R=' || concat_ws('|', coalesce(r->>'status',''), coalesce(r->>'reject_reason',''), coalesce(r->>'action_id',''))
          from (select ops.execute_action('k157-g7-same','case_create','none',null::uuid,'{\"title\":\"rehearsal 157 g7\"}'::jsonb,'rehearsal 157') r) x; %s commit;" "$(as_founder "$1")" "$hold"
}
race "$DB" "$(g7 $A 1)" "$(g7 $B 0)"
rows=$(q "$DB" "select count(*) from ops.action where idempotency_key = 'k157-g7-same'")
[ "$(field "$R1" 1)" = "succeeded" ] && [ "$(field "$R2" 1)" = "idempotent_replay" ] && [ "$(field "$R2" 3)" = "$(field "$R1" 3)" ] && [ -n "$(field "$R2" 3)" ] && [ "$LW" = "transactionid" ] && [ "$rows" = "1" ] \
  && report G7 PASS "non-money same key: s1=$(field "$R1" 1) (held); s2 waited on the unique index ($LW; ${W}ms informational), then the handler answered $(field "$R2" 1) of s1's action (id present); rows for the key=$rows" \
  || report G7 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) rows=$rows"

# legacy cross pair on order <n>: two awaiting rows with pending approvals, written directly (as before 157)
legacy_pair() {
  q "$1" "do \$d\$ declare v uuid; ap uuid; begin
    insert into ops.action (idempotency_key, action_type, subject_kind, subject_id, params, reason, requested_by, state)
    values ('k157-legacy-ref-$2', 'refund_execute', 'payment', '$(P "$2")', '{}', 'legacy', '$A', 'awaiting_approval') returning id into v;
    insert into ops.approval (action_id, action_hash, requested_by, expires_at)
    values (v, ops.action_hash('refund_execute','payment','$(P "$2")'::uuid, null, '{}'::jsonb), '$A', now() + interval '72 hours') returning id into ap;
    update ops.action set approval_id = ap, version = version + 1 where id = v;
    insert into ops.action (idempotency_key, action_type, subject_kind, subject_id, params, reason, requested_by, state)
    values ('k157-legacy-pay-$2', 'payout_release', 'transfer', '$(T "$2")', '{}', 'legacy', '$A', 'awaiting_approval') returning id into v;
    insert into ops.approval (action_id, action_hash, requested_by, expires_at)
    values (v, ops.action_hash('payout_release','transfer','$(T "$2")'::uuid, null, '{}'::jsonb), '$A', now() + interval '72 hours') returning id into ap;
    update ops.action set approval_id = ap, version = version + 1 where id = v;
  end \$d\$;" >/dev/null
}
approve() {  # db who fn action_id hold(0|1)
  local hold=""; [ "$5" = "1" ] && hold="select pg_sleep(3);"
  printf "begin; %s select 'R=' || concat_ws('|', coalesce(r->>'status',''), coalesce(r->>'reject_reason',''), coalesce(r#>>'{blocking,action_id}',''), coalesce(r#>>'{blocking,state}','')) from (select %s('%s'::uuid,'approve','rehearsal 157') r) x; %s commit;" \
    "$(as_founder "$2")" "$3" "$4" "$hold"
}

# G6: approve race on a legacy cross pair, order 6
legacy_pair "$DB" 6
r1=$(q "$DB" "select id from ops.action where idempotency_key='k157-legacy-ref-6'"); r2=$(q "$DB" "select id from ops.action where idempotency_key='k157-legacy-pay-6'")
race "$DB" "$(approve "$DB" $B ops.approve_action "$r1" 1)" "$(approve "$DB" $B ops.approve_action "$r2" 0)"
st=$(q "$DB" "select a.state || '/' || ap.state || '/' || t.status from ops.action a join ops.approval ap on ap.action_id = a.id join public.transfers t on t.id = a.subject_id where a.id = '$r2'")
[ "$(field "$R1" 1)" = "processing" ] && [ "$(field "$R2" 2)" = "duplicate_unsettled" ] && [ "$(field "$R2" 3)" = "$r1" ] && [ "$LW" = "advisory" ] && [ "$st" = "awaiting_approval/pending/seller_sent" ] \
  && report G6 PASS "approve refund s1=$(field "$R1" 1) (held); approve payout s2 waited on the order lock ($LW; ${W}ms informational) then $(field "$R2" 2) (blocker $(field "$R2" 4)); payout/approval/transfer=$st" \
  || report G6 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) payout=$st"

# mutant copies for the controls (schema rehearsal157 in the 157 clone; the real ops functions are untouched)
q "$DB" "drop schema if exists rehearsal157 cascade; create schema rehearsal157; grant usage on schema rehearsal157 to authenticated;" >/dev/null
q "$DB" "do \$m\$ declare d text; begin
  d := pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure);
  d := replace(d, 'CREATE OR REPLACE FUNCTION ops.execute_action(', 'CREATE OR REPLACE FUNCTION rehearsal157.execute_action_nolock(');
  if position('perform pg_advisory_xact_lock(' in d) = 0 or position('v_block := ops.money_unsettled_blocker(v_order, null, v_unsettled, p_action_type);' in d) = 0 then
    raise exception 'C1 mutant: expected text not found';
  end if;
  d := replace(d, 'perform pg_advisory_xact_lock(', 'perform 0 * (');
  d := replace(d, 'v_block := ops.money_unsettled_blocker(v_order, null, v_unsettled, p_action_type);', 'null; -- blocker check removed');
  execute d;
  d := pg_get_functiondef('ops.approve_action(uuid,text,text)'::regprocedure);
  d := replace(d, 'CREATE OR REPLACE FUNCTION ops.approve_action(', 'CREATE OR REPLACE FUNCTION rehearsal157.approve_action_nolock(');
  if position('perform pg_advisory_xact_lock(' in d) = 0 then raise exception 'C2 mutant: expected text not found'; end if;
  d := replace(d, 'perform pg_advisory_xact_lock(', 'perform 0 * (');
  execute d;
end \$m\$;" >/dev/null || { echo "  FAIL controls: could not build the mutant copies"; fail=1; }

# C1: CONTROL — index-only mutant as session 2, order 7
s2=$(ex "$DB" $B k157-c1-b refund_execute payment "$(P 7)" | sed 's/ops\.execute_action(/rehearsal157.execute_action_nolock(/')
race "$DB" "$(hold_ex "$DB" $A k157-c1-a refund_execute payment "$(P 7)")" "$s2"
n=$(unsettled "$DB" 7)
[ "$(field "$R1" 1)" = "awaiting_approval" ] && [ "$(field "$R2" 2)" = "duplicate_unsettled" ] && [ "$(field "$R2" 4)" = "$(field "$R1" 3)" ] && [ -n "$(field "$R2" 3)" ] && [ "$LW" = "transactionid" ] && [ "$n" = "1" ] \
  && report C1 PASS "CONTROL no lock/no check: s2 waited on the INDEX ($LW, not advisory; ${W}ms informational), then the handler answered $(field "$R2" 1)/$(field "$R2" 2) with its own action id (not idempotent_replay); unsettled rows=$n" \
  || report C1 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) unsettled=$n"

# C2: CONTROL — approve without the advisory lock as session 2, legacy pair on order 8
legacy_pair "$DB" 8
r1=$(q "$DB" "select id from ops.action where idempotency_key='k157-legacy-ref-8'"); r2=$(q "$DB" "select id from ops.action where idempotency_key='k157-legacy-pay-8'")
race "$DB" "$(approve "$DB" $B ops.approve_action "$r1" 1)" "$(approve "$DB" $B rehearsal157.approve_action_nolock "$r2" 0)"
inflight=$(q "$DB" "select string_agg(action_type || '=' || state, ', ' order by action_type) from ops.action where id in ('$r1','$r2')")
[ "$(field "$R1" 1)" = "processing" ] && [ "$(field "$R2" 1)" = "succeeded" ] && [ "$inflight" = "payout_release=succeeded, refund_execute=processing" ] \
  && report C2 PASS "CONTROL approve without the lock: s2 ($W ms) ran its recheck before s1 committed, missed s1's processing and released the payout: $inflight — refund in flight AND payout released; the lock is load-bearing" \
  || report C2 FAIL "control did not reproduce: s1=$R1 s2=$R2 waited=${W}ms ($inflight)"
q "$DB" "drop schema if exists rehearsal157 cascade;" >/dev/null

echo "RESULT: $([ $fail -eq 0 ] && echo ALL-PASS || echo FAILURES)"
exit $fail
