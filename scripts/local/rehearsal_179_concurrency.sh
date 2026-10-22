#!/usr/bin/env bash
# ============================================================================
# scripts/local/rehearsal_179_concurrency.sh — LOCAL-ONLY two-session proof for migration 179
# (20261022003000_payout_claim_refused_during_refund.sql, stacked on 157 + 158 + 177). pgTAP runs in one transaction
# and cannot show a lock wait or a deadlock; this drives real concurrent sessions against throwaway loopback clones.
#
#   usage: scripts/local/rehearsal_179_concurrency.sh <db_with_157_158_177_179> <control_db_with_157_158_177_only>
#   both names must start with a_sprint_ (a_sprint_prod_replay / _prod_template / _chain are refused);
#   host must be 127.0.0.1. Model: scripts/local/rehearsal_177_concurrency.sh.
#
# Scenarios (each prints PASS/FAIL). "Waited" is a LOCK-WAIT INDICATOR, never a wall-clock bound: pg_stat_activity is
# polled while session 2 runs and must show it in a heavyweight Lock wait (wait_event_type 'Lock'; an advisory lock
# shows wait_event 'advisory'); the elapsed ms are printed for information only. Sessions are found by application_name
# (r179_s1 / r179_s2) AND database: the server is shared. A second run against the same databases is refused.
#   E1 claim vs the REQUEST: session 1 = founder A requests a refund on order 1 (ops.execute_action, holds 157's order
#      advisory lock and the new ops.action row, uncommitted, 3 s); meanwhile the cron auto-releases T1 (committed:
#      the request takes no transfer lock); session 2 = the payout worker's claim_payout_attempt(T1). Session 2 WAITS
#      on the advisory lock, then is refused REFUND_IN_FLIGHT with DETAIL = the parked action's id; no attempt row.
#      Then, sequentially: founder B's approval is 177's rejected / payout_released (status_auto_released) and the next
#      claim opens attempt #1 — both directions closed on one order.
#   E2 claim vs the APPROVAL: order 2's refund parked, then released by the cron; session 1 = founder B's approval
#      (177 refuses it: rejected / payout_released) held 3 s with the order advisory lock; session 2 = the claim: WAITS
#      on the advisory lock (not on the transfer row), then opens attempt #1 once the refund is rejected. No deadlock.
#   E3 the 177 D8 CYCLE shape with 179: a dispatch copy pauses 2 s between its payments FOR UPDATE and its transfers
#      FOR UPDATE (schema rehearsal179; the real ops functions are untouched); the claim on order 3 starts inside the
#      pause. With 179 the claim takes the order advisory lock FIRST, which the approval already holds: it waits there,
#      the copy wakes and finishes (rejected / payout_released: T3 released beforehand), the claim then opens attempt
#      #1. No 40P01 on either side.
#   E3c CONTROL: the same on the clone WITHOUT 179: 177's documented deadlock (40P01 after deadlock_timeout, one victim).
#   E4 the D2 defect, sequential, on both clones: order 4's refund parked, approved (processing: handed to the edge),
#      then the cron releases T4; the claim: WITH 179 refused REFUND_IN_FLIGHT (DETAIL = the action id), WITHOUT 179
#      attempt #1 is opened while the buyer's refund is at Stripe (the double payment path).
#   E5 INDICATOR CONTROL: session 1 holds a refund request on order 5; session 2 claims order 6 (released, no refund):
#      no lock wait is seen, attempt #1. The indicator discriminates.
# Fixtures are committed under fixed ids (17900000-...) and LEFT IN PLACE: ops.audit is append-only, so the rows cannot
# be fully removed. Run only on throwaway clones; drop them afterwards.
# SAFETY: loopback only (127.0.0.1); scrubs remote connection variables. bash 3.2.
# ============================================================================
set -uo pipefail
unset SUPABASE_DB_URL DATABASE_URL POSTGRES_URL PGSERVICE PGSERVICEFILE PGPASSWORD PGPASSFILE PGURL PGDATABASE TEST_DB_URL 2>/dev/null
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}" PGPORT="${REHEARSAL_PGPORT:-5432}" PGUSER="${REHEARSAL_PGUSER:-postgres}" PGCONNECT_TIMEOUT=5 LC_ALL=C
export PGOPTIONS='-c client_min_messages=warning'
[ "$PGHOST" = "127.0.0.1" ] || { echo "refusing host '$PGHOST': only 127.0.0.1" >&2; exit 1; }
DB="${1:-}"; CDB="${2:-}"
for d in "$DB" "$CDB"; do
  case "$d" in
    a_sprint_prod_replay|a_sprint_prod_template|a_sprint_chain) echo "refusing reserved database '$d'" >&2; exit 1 ;;
    a_sprint_*) ;;
    *) echo "refusing database '$d': name must start with a_sprint_ (usage: $0 <db_with_157_158_177_179> <control_db_with_157_158_177_only>)" >&2; exit 1 ;;
  esac
done
[ "$DB" != "$CDB" ] || { echo "the two databases must differ" >&2; exit 1; }
q()  { psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
srv=$(q "$DB" "select coalesce(host(inet_server_addr()),'socket')") || exit 1
case "$srv" in 127.0.0.1|::1|socket) ;; *) echo "refusing: server address $srv is not loopback" >&2; exit 1 ;; esac
HAS177="select to_regprocedure('ops.refund_payout_refusal(uuid,text)') is not null and position('-- 158 begin' in pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure)) > 0"
HAS179="select position('-- 179 begin' in pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure)) > 0"
[ "$(q "$DB"  "$HAS177")" = "t" ] && [ "$(q "$DB" "$HAS179")" = "t" ]  || { echo "$DB must have 157, 158, 177 and 179 applied" >&2; exit 1; }
[ "$(q "$CDB" "$HAS177")" = "t" ] && [ "$(q "$CDB" "$HAS179")" = "f" ] || { echo "$CDB must have 157 + 158 + 177 and NOT 179" >&2; exit 1; }
BUSY="select count(*) from pg_stat_activity where datname = current_database() and application_name in ('r179_s1', 'r179_s2')"
[ "$(q "$DB" "$BUSY")" = "0" ] && [ "$(q "$CDB" "$BUSY")" = "0" ] \
  || { echo "refusing: a rehearsal session (r179_s1 / r179_s2) is already connected to $DB or $CDB" >&2; exit 1; }

A=17900000-0000-0000-0000-0000000000a1      # founder A (platform_admin via admin_users)
B=17900000-0000-0000-0000-0000000000a2      # founder B
S=17900000-0000-0000-0000-0000000000b1      # seller
U=17900000-0000-0000-0000-0000000000b2      # buyer
P() { printf '17900000-0000-0000-0002-%012d' "$1"; }
T() { printf '17900000-0000-0000-0003-%012d' "$1"; }
claims() { printf '{"sub":"%s","role":"authenticated","aal":"aal2"}' "$1"; }
as_user() { printf "select set_config('request.jwt.claims', '%s', true); set local role authenticated;" "$(claims "$1")"; }

seed() {  # $1 db: founders, seller, buyer; orders 1..8 (listing + succeeded live payment + seller_sent transfer); refund execution on
  q "$1" "
    insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    select x.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', x.email, '{\"provider\":\"email\"}', '{}', now(), now()
      from (values ('$A'::uuid, 'r179-a@test.local'), ('$B'::uuid, 'r179-b@test.local'), ('$S'::uuid, 'r179-s@test.local'), ('$U'::uuid, 'r179-u@test.local')) x(id, email)
    on conflict (id) do nothing;
    insert into public.profiles (id, full_name, display_name)
    select x.id, '', x.label from (values ('$A'::uuid, 'R179 A'), ('$B'::uuid, 'R179 B'), ('$S'::uuid, 'R179 S'), ('$U'::uuid, 'R179 U')) x(id, label)
    on conflict (id) do nothing;
    insert into public.admin_users (user_id, label) values ('$A', 'R179 FOUNDER A'), ('$B', 'R179 FOUNDER B') on conflict (user_id) do nothing;
    update public.profiles set stripe_connect_id = 'acct_r179_seller' where id = '$S' and stripe_connect_id is null;  -- claim_payout_attempt needs an onboarded seller
    insert into public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
                                 starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
    select ('17900000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid, '$S', 'R179 #' || n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 1,
           'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'r179.jpg', 'active'
      from generate_series(1, 8) n on conflict (id) do nothing;
    insert into public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
    select ('17900000-0000-0000-0002-' || lpad(n::text, 12, '0'))::uuid, ('17900000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid, '$U', '$S',
           10000, 1000, 1000, 11000, 'pi_r179_' || n, 'succeeded', 'buy_now', now(), true
      from generate_series(1, 8) n on conflict (id) do nothing;
    insert into public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at, transfer_evidence_path, expires_at)
    select ('17900000-0000-0000-0003-' || lpad(n::text, 12, '0'))::uuid, ('17900000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid,
           ('17900000-0000-0000-0002-' || lpad(n::text, 12, '0'))::uuid, '$S', '$U', 'mobile_transfer', 'seller_sent', now(), now() + interval '72 hours',
           'r179/evidence.jpg', now() + interval '24 hours'
      from generate_series(1, 8) n on conflict (id) do nothing;" >/dev/null
  psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "begin; $(as_user $A)
    select ops.execute_action('k179-r-set-on', 'setting_set', 'setting', null, '{\"value\": true}'::jsonb, 'rehearsal 179', null, 'refund_execute_enabled');
    commit;" >/dev/null
}
# founder A parks a refund on order n (committed): db n
park() { psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "begin; $(as_user $A)
  select ops.execute_action('k179-r-refund-$2', 'refund_execute', 'payment', '$(P $2)', '{}'::jsonb, 'rehearsal 179', null, null); commit;" >/dev/null; }
aid() { q "$1" "select id from ops.action where idempotency_key = 'k179-r-refund-$2'"; }
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
# founder A's request on order n, held 3 s inside its transaction (the advisory lock and the new row uncommitted)
request_hold() { printf "begin; %s select 'R=' || (ops.execute_action('k179-r-refund-%s', 'refund_execute', 'payment', '%s', '{}'::jsonb, 'rehearsal 179', null, null) ->> 'status'); select pg_sleep(3); commit;" "$(as_user $A)" "$1" "$(P "$1")"; }
# founder B approves: action_id hold(0|1) [approve fn] -> "status|reject_reason|stage|handoff|basis"
approve() {
  local hold=""; [ "$2" = "1" ] && hold="select pg_sleep(3);"
  printf "begin; %s select 'R=' || concat_ws('|', coalesce(r->>'status',''), coalesce(r->>'reject_reason',''), coalesce(r#>>'{result,stage}',''),
            coalesce(r#>>'{result,handoff}',''), coalesce(r#>>'{result,payout,basis}',''))
          from (select %s('%s', 'approve', 'rehearsal 179') r) x; %s commit;" "$(as_user $B)" "${3:-ops.approve_action}" "$1" "$hold"
}
# the payout worker's claim (postgres, as service_role would): "R=<attempt_no>" or an ERROR with DETAIL
claim() { printf "set lock_timeout = '10s'; select 'R=' || coalesce((select attempt_no::text from public.claim_payout_attempt('%s', 'r179-worker', interval '10 minutes')), 'none');" "$1"; }
field() { printf '%s' "$1" | cut -d'|' -f"$2"; }
act() { q "$1" "select state || '/' || coalesce(reject_reason, '') from ops.action where idempotency_key = 'k179-r-refund-$2'"; }
trs() { q "$1" "select status from public.transfers where id = '$(T "$2")'"; }
atts() { q "$1" "select coalesce(string_agg(state, ',' order by attempt_no), 'none') from public.payout_attempts where transfer_id = '$(T "$2")'"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0
report() { if [ "$2" = "PASS" ]; then echo "  PASS $1 — $3"; else echo "  FAIL $1 — $3"; fail=1; fi; }

# race <db> <session-1 sql> <session-2 sql>: s1 in the background; once s1 is inside its hold (PgSleep) the optional
# BETWEEN statement runs on the main thread (committed), then s2 starts. Sets R1, R2, D2 (s2's DETAIL line), W (ms s2
# took, informational) and LW: the heavyweight-lock wait events pg_stat_activity showed for s2.
BETWEEN=""
race() {
  ( PGAPPNAME=r179_s1 psql -X -At -d "$1" -c "$2" > "$TMP/s1" 2>&1 ) &
  local p1=$! i=0
  until [ "$(q "$1" "select count(*) from pg_stat_activity where datname = current_database() and application_name = 'r179_s1' and wait_event = 'PgSleep'")" = "1" ] || [ $i -ge 200 ]; do
    sleep 0.05; i=$((i + 1))
  done
  [ $i -ge 200 ] && { echo "  FAIL — session 1 never reached its hold: the result below is not a race"; fail=1; }
  [ -n "$BETWEEN" ] && { q "$1" "$BETWEEN" > "$TMP/between" 2>&1 || { echo "  FAIL — BETWEEN statement failed: $(cat "$TMP/between")"; fail=1; }; }
  local t0; t0=$(ms)
  ( PGAPPNAME=r179_s2 psql -X -At -d "$1" -c "$3" > "$TMP/s2" 2>&1 ) &
  local p2=$! w
  : > "$TMP/lw"
  while kill -0 "$p2" 2>/dev/null; do
    w=$(q "$1" "select coalesce(string_agg(distinct wait_event, ','), '') from pg_stat_activity where datname = current_database() and application_name = 'r179_s2' and wait_event_type = 'Lock'")
    [ -n "$w" ] && echo "$w" >> "$TMP/lw"
    sleep 0.02
  done
  wait "$p2"; local t1; t1=$(ms); wait "$p1"
  W=$((t1 - t0)); R1=$(grep '^R=' "$TMP/s1" | sed 's/^R=//'); R2=$(grep '^R=' "$TMP/s2" | sed 's/^R=//')
  grep -qi 'deadlock\|ERROR' "$TMP/s1" && R1="ERROR:$(grep -i error "$TMP/s1" | head -1)"
  grep -qi 'ERROR' "$TMP/s2" && R2="ERROR:$(grep -i error "$TMP/s2" | head -1)"
  D2=$(grep '^DETAIL:' "$TMP/s2" | head -1 | sed 's/^DETAIL:  *//')
  LW=$(sort -u "$TMP/lw" | tr '\n' ' ' | sed 's/ $//'); [ -n "$LW" ] || LW=none
  BETWEEN=""
}
# the paused dispatch copy (177 D8's construction): schema rehearsal179 on db $1
build_paused_copy() {
  q "$1" "drop schema if exists rehearsal179 cascade; create schema rehearsal179; grant usage on schema rehearsal179 to authenticated;" >/dev/null
  q "$1" "do \$m\$ declare d text; k text := 'perform 1 from public.transfers t where t.payment_id = a.subject_id for update;'; begin
    d := pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure);
    if (length(d) - length(replace(d, k, ''))) / length(k) <> 1 then raise exception 'copy: dispatch anchor count <> 1'; end if;
    d := replace(d, 'CREATE OR REPLACE FUNCTION ops.action_dispatch(', 'CREATE OR REPLACE FUNCTION rehearsal179.action_dispatch_paused(');
    d := replace(d, k, 'perform pg_sleep(2); ' || k);
    execute d;
    d := pg_get_functiondef('ops.action_run(uuid)'::regprocedure);
    if position('v_res := ops.action_dispatch(a);' in d) = 0 then raise exception 'copy: action_run anchor missing'; end if;
    d := replace(d, 'CREATE OR REPLACE FUNCTION ops.action_run(', 'CREATE OR REPLACE FUNCTION rehearsal179.action_run(');
    d := replace(d, 'v_res := ops.action_dispatch(a);', 'v_res := rehearsal179.action_dispatch_paused(a);');
    execute d;
    d := pg_get_functiondef('ops.approve_action(uuid,text,text)'::regprocedure);
    if position('return ops.action_run(a.id);' in d) = 0 then raise exception 'copy: approve_action anchor missing'; end if;
    d := replace(d, 'CREATE OR REPLACE FUNCTION ops.approve_action(', 'CREATE OR REPLACE FUNCTION rehearsal179.approve_action(');
    d := replace(d, 'return ops.action_run(a.id);', 'return rehearsal179.action_run(a.id);');
    execute d;
  end \$m\$;" >/dev/null || { echo "  FAIL — could not build the paused copies on $1"; fail=1; }
}

echo "179 concurrency rehearsal: db=$DB control=$CDB $(date -u +%FT%TZ)"
seed "$DB"; seed "$CDB"
echo "  fixtures: orders 1..8 seller_sent on both clones; refund execution on; no refund parked yet"

# E1: claim vs the REQUEST (order 1). The cron releases T1 while founder A's request is held.
BETWEEN="select public.apply_auto_release('$(T 1)')"
race "$DB" "$(request_hold 1)" "$(claim "$(T 1)")"
a=$(act "$DB" 1); id1=$(aid "$DB" 1)
if [ "$R1" = "awaiting_approval" ] && case "$R2" in ERROR:*REFUND_IN_FLIGHT*) true ;; *) false ;; esac && [ "$D2" = "$id1" ] && [ "$LW" != "none" ] \
   && [ "$a" = "awaiting_approval/" ] && [ "$(atts "$DB" 1)" = "none" ] && [ "$(trs "$DB" 1)" = "auto_released" ]; then
  ap=$(PGAPPNAME=r179_seq psql -X -At -d "$DB" -c "$(approve "$id1" 0)" 2>&1 | grep '^R=' | sed 's/^R=//')
  c2=$(PGAPPNAME=r179_seq psql -X -At -d "$DB" -c "$(claim "$(T 1)")" 2>&1 | grep '^R=' | sed 's/^R=//')
  if [ "$(field "$ap" 1)" = "rejected" ] && [ "$(field "$ap" 2)" = "payout_released" ] && [ "$c2" = "1" ] && [ "$(atts "$DB" 1)" = "claimed" ]; then
    report E1 PASS "request held 3 s (parked: $R1); the cron released T1 meanwhile; claim s2 waited on a lock ($LW; ${W}ms informational), then REFUND_IN_FLIGHT, DETAIL = the action id; no attempt. Then B's approval: $(field "$ap" 1)/$(field "$ap" 2) basis $(field "$ap" 5) (177), and the next claim opened attempt #$c2"
  else
    report E1 FAIL "race ok but the sequel differs: approval=$ap claim=$c2 attempts=$(atts "$DB" 1)"
  fi
else
  report E1 FAIL "s1=$R1 s2=$R2 detail=$D2 (want $id1) lock waits=$LW (${W}ms) action=$a attempts=$(atts "$DB" 1) transfer=$(trs "$DB" 1)"
fi

# E2: claim vs the APPROVAL (order 2): refund parked, T2 released by the cron, B's approval (177 rejects) held 3 s
park "$DB" 2; q "$DB" "select public.apply_auto_release('$(T 2)')" >/dev/null
race "$DB" "$(approve "$(aid "$DB" 2)" 1)" "$(claim "$(T 2)")"
a=$(act "$DB" 2)
[ "$(field "$R1" 1)" = "rejected" ] && [ "$(field "$R1" 2)" = "payout_released" ] && [ "$(field "$R1" 3)" = "approval" ] && [ "$R2" = "1" ] && [ "$LW" != "none" ] \
  && [ "$a" = "rejected/payout_released" ] && [ "$(atts "$DB" 2)" = "claimed" ] \
  && report E2 PASS "approval s1 (177: $(field "$R1" 1)/$(field "$R1" 2) stage $(field "$R1" 3)) held 3 s; claim s2 waited on a lock ($LW; ${W}ms informational), no deadlock, then opened attempt #$R2 once the refund was rejected; action $a" \
  || report E2 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a attempts=$(atts "$DB" 2)"

# E3: the 177 D8 cycle shape WITH 179 (order 3): paused dispatch copy; the claim starts inside the pause
park "$DB" 3; q "$DB" "select public.apply_auto_release('$(T 3)')" >/dev/null
build_paused_copy "$DB"
race "$DB" "$(approve "$(aid "$DB" 3)" 0 rehearsal179.approve_action)" "$(claim "$(T 3)")"
a=$(act "$DB" 3); err=$(q "$DB" "select coalesce(error, '') from ops.action where idempotency_key = 'k179-r-refund-3'")
if [ "$(field "$R1" 1)" = "rejected" ] && [ "$(field "$R1" 2)" = "payout_released" ] && [ "$R2" = "1" ] && [ "$LW" != "none" ] && [ "$a" = "rejected/payout_released" ] \
   && [ -z "$err" ] && ! grep -qi deadlock "$TMP/s1" "$TMP/s2"; then
  report E3 PASS "paused dispatch copy (payments lock -> 2 s -> transfers lock) vs the claim started inside the pause: the claim waited on a lock ($LW; ${W}ms informational), no 40P01 on either side; approval $(field "$R1" 1)/$(field "$R1" 2); claim opened attempt #$R2 afterwards — the D8 cycle is gone"
else
  report E3 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a error='$err' attempts=$(atts "$DB" 3)"
fi
q "$DB" "drop schema if exists rehearsal179 cascade;" >/dev/null

# E3c: CONTROL — the same on the clone WITHOUT 179: 177's documented 40P01
park "$CDB" 3; q "$CDB" "select public.apply_auto_release('$(T 3)')" >/dev/null
build_paused_copy "$CDB"
race "$CDB" "$(approve "$(aid "$CDB" 3)" 0 rehearsal179.approve_action)" "$(claim "$(T 3)")"
a=$(act "$CDB" 3); err=$(q "$CDB" "select coalesce(error, '') from ops.action where idempotency_key = 'k179-r-refund-3'")
if grep -qi deadlock "$TMP/s1" "$TMP/s2" || case "$err" in *deadlock*) true ;; *) false ;; esac; then
  report E3c PASS "CONTROL without 179: the cycle is real — 40P01 (s1=$(field "$R1" 1) error='$err'; s2=$R2); action $a; attempts $(atts "$CDB" 3) — 177's D8, reproduced"
else
  report E3c FAIL "control did not reproduce the deadlock: s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a error='$err' attempts=$(atts "$CDB" 3)"
fi
q "$CDB" "drop schema if exists rehearsal179 cascade;" >/dev/null

# E4: the D2 defect, sequential, on both clones (order 4): parked -> approved (processing) -> cron release -> claim
for d in "$DB" "$CDB"; do
  park "$d" 4
  ap=$(PGAPPNAME=r179_seq psql -X -At -d "$d" -c "$(approve "$(aid "$d" 4)" 0)" 2>&1 | grep '^R=' | sed 's/^R=//')
  q "$d" "select public.apply_auto_release('$(T 4)')" >/dev/null
  PGAPPNAME=r179_seq psql -X -At -d "$d" -c "$(claim "$(T 4)")" > "$TMP/e4" 2>&1
  c=$(grep '^R=' "$TMP/e4" | sed 's/^R=//'); grep -qi ERROR "$TMP/e4" && c="ERROR:$(grep -i error "$TMP/e4" | head -1)"; det=$(grep '^DETAIL:' "$TMP/e4" | head -1 | sed 's/^DETAIL:  *//')
  a=$(act "$d" 4)
  if [ "$d" = "$DB" ]; then
    [ "$(field "$ap" 1)" = "processing" ] && case "$c" in ERROR:*REFUND_IN_FLIGHT*) true ;; *) false ;; esac && [ "$det" = "$(aid "$d" 4)" ] && [ "$a" = "processing/" ] && [ "$(atts "$d" 4)" = "none" ] \
      && report E4 PASS "WITH 179: refund $(field "$ap" 1) (handoff $(field "$ap" 4)), cron released T4, the claim was refused REFUND_IN_FLIGHT with DETAIL = the action id; no attempt; action $a" \
      || report E4 FAIL "with 179: approval=$ap claim=$c detail=$det action=$a attempts=$(atts "$d" 4)"
  else
    [ "$(field "$ap" 1)" = "processing" ] && [ "$c" = "1" ] && [ "$a" = "processing/" ] && [ "$(atts "$d" 4)" = "claimed" ] \
      && report E4c PASS "CONTROL without 179: refund $(field "$ap" 1) at the edge, cron released T4, the claim opened attempt #$c while the buyer's refund is at Stripe — the D2 defect" \
      || report E4c FAIL "control did not reproduce the defect: approval=$ap claim=$c action=$a attempts=$(atts "$d" 4)"
  fi
done

# E5: INDICATOR CONTROL — s1 holds a request on order 5; s2 claims order 6 (released beforehand, no refund)
q "$DB" "select public.apply_auto_release('$(T 6)')" >/dev/null
race "$DB" "$(request_hold 5)" "$(claim "$(T 6)")"
[ "$R1" = "awaiting_approval" ] && [ "$R2" = "1" ] && [ "$LW" = "none" ] && [ "$(atts "$DB" 6)" = "claimed" ] \
  && report E5 PASS "INDICATOR CONTROL: while s1 held order 5's request, s2 claimed order 6 with no lock wait (Lock waits: $LW; ${W}ms informational): attempt #$R2" \
  || report E5 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) attempts=$(atts "$DB" 6)"

echo "RESULT: $([ $fail -eq 0 ] && echo ALL-PASS || echo FAILURES)"
exit $fail
