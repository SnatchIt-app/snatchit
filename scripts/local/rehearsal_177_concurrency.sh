#!/usr/bin/env bash
# ============================================================================
# scripts/local/rehearsal_177_concurrency.sh — LOCAL-ONLY two-session proof for migration 177
# (20261022001000_ops_refund_refused_after_payout.sql, stacked on 157 + 158). pgTAP runs in one transaction and cannot
# show a lock wait; this drives real concurrent sessions against throwaway loopback clones.
#
#   usage: scripts/local/rehearsal_177_concurrency.sh <db_with_157_158_177> <control_db_with_157_158_only>
#   both names must start with a_sprint_ (a_sprint_prod_replay / _prod_template / _chain are refused);
#   host must be 127.0.0.1. Model: scripts/local/rehearsal_158_concurrency.sh.
#
# Scenarios (each prints PASS/FAIL). "Waited" is a LOCK-WAIT INDICATOR, never a wall-clock bound: pg_stat_activity is
# polled while session 2 runs and must show it in a heavyweight Lock wait (wait_event_type 'Lock'); the elapsed ms are
# printed for information only. Sessions are found by application_name (r177_s1 / r177_s2) AND database
# (datname = current_database()): the server is shared. A second run against the same databases is refused.
# Every scenario starts from a refund_execute that founder A parked (awaiting_approval) while the transfer was
# seller_sent; session 2 is founder B approving it (approve_action -> action_run -> action_dispatch).
#   D1 session 1 = the auto-release cron: BEGIN; apply_auto_release(T1) (locks + flips the transfer to auto_released,
#      uncommitted) and holds 3 s. Session 2 WAITS on the transfer row lock, then answers rejected / payout_released
#      (stage approval): the action ends rejected, nothing is handed to ops-refund-execute.
#   D2 session 1 = the buyer confirms (confirm_transfer_received as the buyer: buyer_confirmed, uncommitted), held 3 s.
#      Session 2 WAITS, then rejected / payout_released, basis status_buyer_confirmed.
#   D3 CONTROL: D1 with a mutant dispatch that skips the transfer FOR UPDATE (copies in schema rehearsal177; the real
#      ops functions are untouched): session 2 does not wait, reads the committed seller_sent row and hands off
#      (processing) while the release commits a moment later — the TOCTOU the lock closes.
#   D4 CONTROL: D1 against the clone WITHOUT 177 (157 + 158): session 2 hands off (processing) — the defect.
#   D5 INDICATOR CONTROL: session 1 holds the cron release of T3; session 2 approves the refund on ANOTHER order (6):
#      no lock wait is seen, processing. The indicator discriminates.
#   D6 the other direction (NOT COVERED by 177, recorded): session 1 = founder B's approval of a refund on T7 that
#      dispatches (processing) and holds 3 s with the transfer row locked; session 2 = the cron's apply_auto_release(T7)
#      (FOR UPDATE SKIP LOCKED): it does not wait and returns false (skipped); no deadlock, no error. A later cron run
#      can release T7 while the refund is at Stripe (payout side, out of scope).
# Fixtures are committed under fixed ids (17700000-...) and LEFT IN PLACE: ops.audit is append-only, so the rows cannot
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
    *) echo "refusing database '$d': name must start with a_sprint_ (usage: $0 <db_with_157_158_177> <control_db_with_157_158_only>)" >&2; exit 1 ;;
  esac
done
[ "$DB" != "$CDB" ] || { echo "the two databases must differ" >&2; exit 1; }
q()  { psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
srv=$(q "$DB" "select coalesce(host(inet_server_addr()),'socket')") || exit 1
case "$srv" in 127.0.0.1|::1|socket) ;; *) echo "refusing: server address $srv is not loopback" >&2; exit 1 ;; esac
HAS158="select position('-- 158 begin' in pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure)) > 0"
HAS177="select to_regprocedure('ops.refund_payout_refusal(uuid,text)') is not null"
[ "$(q "$DB"  "$HAS158")" = "t" ] && [ "$(q "$DB" "$HAS177")" = "t" ]  || { echo "$DB must have 157, 158 and 177 applied" >&2; exit 1; }
[ "$(q "$CDB" "$HAS158")" = "t" ] && [ "$(q "$CDB" "$HAS177")" = "f" ] || { echo "$CDB must have 157 + 158 and NOT 177" >&2; exit 1; }
BUSY="select count(*) from pg_stat_activity where datname = current_database() and application_name in ('r177_s1', 'r177_s2')"
[ "$(q "$DB" "$BUSY")" = "0" ] && [ "$(q "$CDB" "$BUSY")" = "0" ] \
  || { echo "refusing: a rehearsal session (r177_s1 / r177_s2) is already connected to $DB or $CDB" >&2; exit 1; }

A=17700000-0000-0000-0000-0000000000a1      # founder A (platform_admin via admin_users)
B=17700000-0000-0000-0000-0000000000a2      # founder B
S=17700000-0000-0000-0000-0000000000b1      # seller
U=17700000-0000-0000-0000-0000000000b2      # buyer
L() { printf '17700000-0000-0000-0001-%012d' "$1"; }
P() { printf '17700000-0000-0000-0002-%012d' "$1"; }
T() { printf '17700000-0000-0000-0003-%012d' "$1"; }
claims() { printf '{"sub":"%s","role":"authenticated","aal":"aal2"}' "$1"; }
as_user() { printf "select set_config('request.jwt.claims', '%s', true); set local role authenticated;" "$(claims "$1")"; }

seed() {  # $1 db: founders, seller, buyer; orders 1..7 (listing + succeeded live payment + seller_sent transfer);
          # refund execution on (setting_set by founder A); a refund parked by founder A on orders 1, 2, 5, 6, 7
  q "$1" "
    insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    select x.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', x.email, '{\"provider\":\"email\"}', '{}', now(), now()
      from (values ('$A'::uuid, 'r177-a@test.local'), ('$B'::uuid, 'r177-b@test.local'), ('$S'::uuid, 'r177-s@test.local'), ('$U'::uuid, 'r177-u@test.local')) x(id, email)
    on conflict (id) do nothing;
    insert into public.profiles (id, full_name, display_name)
    select x.id, '', x.label from (values ('$A'::uuid, 'R177 A'), ('$B'::uuid, 'R177 B'), ('$S'::uuid, 'R177 S'), ('$U'::uuid, 'R177 U')) x(id, label)
    on conflict (id) do nothing;
    insert into public.admin_users (user_id, label) values ('$A', 'R177 FOUNDER A'), ('$B', 'R177 FOUNDER B') on conflict (user_id) do nothing;
    insert into public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
                                 starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
    select ('17700000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid, '$S', 'R177 #' || n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 1,
           'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'r177.jpg', 'active'
      from generate_series(1, 7) n on conflict (id) do nothing;
    insert into public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
    select ('17700000-0000-0000-0002-' || lpad(n::text, 12, '0'))::uuid, ('17700000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid, '$U', '$S',
           10000, 1000, 1000, 11000, 'pi_r177_' || n, 'succeeded', 'buy_now', now(), true
      from generate_series(1, 7) n on conflict (id) do nothing;
    insert into public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at, transfer_evidence_path, expires_at)
    select ('17700000-0000-0000-0003-' || lpad(n::text, 12, '0'))::uuid, ('17700000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid,
           ('17700000-0000-0000-0002-' || lpad(n::text, 12, '0'))::uuid, '$S', '$U', 'mobile_transfer', 'seller_sent', now(), now() + interval '72 hours',
           'r177/evidence.jpg', now() + interval '24 hours'
      from generate_series(1, 7) n on conflict (id) do nothing;" >/dev/null
  psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "begin; $(as_user $A)
    select ops.execute_action('k177-r-set-on', 'setting_set', 'setting', null, '{\"value\": true}'::jsonb, 'rehearsal 177', null, 'refund_execute_enabled');
    commit;" >/dev/null
  local n; for n in 1 2 5 6 7; do
    psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "begin; $(as_user $A)
      select ops.execute_action('k177-r-refund-$n', 'refund_execute', 'payment', '$(P $n)', '{}'::jsonb, 'rehearsal 177', null, null); commit;" >/dev/null
  done
}
aid() { q "$1" "select id from ops.action where idempotency_key = 'k177-r-refund-$2'"; }
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
# founder B approves: db action_id hold(0|1) [approve fn] -> "status|reject_reason|stage|handoff|basis"
approve() {
  local hold=""; [ "$3" = "1" ] && hold="select pg_sleep(3);"
  printf "begin; %s select 'R=' || concat_ws('|', coalesce(r->>'status',''), coalesce(r->>'reject_reason',''), coalesce(r#>>'{result,stage}',''),
            coalesce(r#>>'{result,handoff}',''), coalesce(r#>>'{result,payout,basis}',''))
          from (select %s('%s', 'approve', 'rehearsal 177') r) x; %s commit;" "$(as_user $B)" "${4:-ops.approve_action}" "$2" "$hold"
}
# the cron path (postgres): release T, uncommitted, held 3 s
cron_hold() { printf "begin; select 'R=' || public.apply_auto_release('%s'); select pg_sleep(3); commit;" "$1"; }
# the buyer confirms receipt (as the buyer), uncommitted, held 3 s
buyer_hold() { printf "begin; %s select public.confirm_transfer_received('%s', '%s'); select 'R=' || 'confirmed'; select pg_sleep(3); commit;" "$(as_user $U)" "$1" "$U"; }
field() { printf '%s' "$1" | cut -d'|' -f"$2"; }
act() { q "$1" "select state || '/' || coalesce(reject_reason, '') from ops.action where idempotency_key = 'k177-r-refund-$2'"; }
trs() { q "$1" "select status from public.transfers where id = '$(T "$2")'"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0
report() { if [ "$2" = "PASS" ]; then echo "  PASS $1 — $3"; else echo "  FAIL $1 — $3"; fail=1; fi; }

# race <db> <session-1 sql> <session-2 sql>: s1 in the background; s2 starts only once s1 is inside its 3 s hold.
# Sets R1, R2, W (ms s2 took, informational) and LW: the heavyweight-lock waits pg_stat_activity showed for s2.
race() {
  ( PGAPPNAME=r177_s1 psql -X -At -d "$1" -c "$2" > "$TMP/s1" 2>&1 ) &
  local p1=$! i=0
  until [ "$(q "$1" "select count(*) from pg_stat_activity where datname = current_database() and application_name = 'r177_s1' and wait_event = 'PgSleep'")" = "1" ] || [ $i -ge 200 ]; do
    sleep 0.05; i=$((i + 1))
  done
  [ $i -ge 200 ] && { echo "  FAIL — session 1 never reached its hold: the result below is not a race"; fail=1; }
  local t0; t0=$(ms)
  ( PGAPPNAME=r177_s2 psql -X -At -d "$1" -c "$3" > "$TMP/s2" 2>&1 ) &
  local p2=$! w
  : > "$TMP/lw"
  while kill -0 "$p2" 2>/dev/null; do
    w=$(q "$1" "select coalesce(string_agg(distinct wait_event, ','), '') from pg_stat_activity where datname = current_database() and application_name = 'r177_s2' and wait_event_type = 'Lock'")
    [ -n "$w" ] && echo "$w" >> "$TMP/lw"
    sleep 0.02
  done
  wait "$p2"; local t1; t1=$(ms); wait "$p1"
  W=$((t1 - t0)); R1=$(grep '^R=' "$TMP/s1" | sed 's/^R=//'); R2=$(grep '^R=' "$TMP/s2" | sed 's/^R=//')
  grep -qi 'deadlock\|ERROR' "$TMP/s1" && R1="ERROR:$(grep -i error "$TMP/s1" | head -1)"
  grep -qi 'ERROR' "$TMP/s2" && R2="ERROR:$(grep -i error "$TMP/s2" | head -1)"
  LW=$(sort -u "$TMP/lw" | tr '\n' ' ' | sed 's/ $//'); [ -n "$LW" ] || LW=none
}

echo "177 concurrency rehearsal: db=$DB control=$CDB $(date -u +%FT%TZ)"
seed "$DB"; seed "$CDB"
echo "  fixtures: $DB refunds parked on orders 1 2 5 6 7: $(act "$DB" 1) $(act "$DB" 2) $(act "$DB" 5) $(act "$DB" 6) $(act "$DB" 7); control order 1: $(act "$CDB" 1)"

# D1: the cron releases T1 while founder B approves the parked refund
race "$DB" "$(cron_hold "$(T 1)")" "$(approve "$DB" "$(aid "$DB" 1)" 0)"
a=$(act "$DB" 1)
[ "$R1" = "true" ] && [ "$(field "$R2" 1)" = "rejected" ] && [ "$(field "$R2" 2)" = "payout_released" ] && [ "$(field "$R2" 3)" = "approval" ] \
  && [ -z "$(field "$R2" 4)" ] && [ "$LW" != "none" ] && [ "$a" = "rejected/payout_released" ] && [ "$(trs "$DB" 1)" = "auto_released" ] \
  && report D1 PASS "cron release held 3 s; approval s2 waited on a lock ($LW; ${W}ms informational), then $(field "$R2" 1)/$(field "$R2" 2) stage $(field "$R2" 3) basis $(field "$R2" 5); action $a; no handoff" \
  || report D1 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a transfer=$(trs "$DB" 1)"

# D2: the buyer confirms T2 while founder B approves
race "$DB" "$(buyer_hold "$(T 2)")" "$(approve "$DB" "$(aid "$DB" 2)" 0)"
a=$(act "$DB" 2)
[ "$R1" = "confirmed" ] && [ "$(field "$R2" 2)" = "payout_released" ] && [ "$(field "$R2" 5)" = '["status_buyer_confirmed"]' ] && [ "$LW" != "none" ] \
  && [ "$a" = "rejected/payout_released" ] \
  && report D2 PASS "buyer confirmation held 3 s; approval s2 waited ($LW; ${W}ms informational), then $(field "$R2" 1)/$(field "$R2" 2) basis $(field "$R2" 5); action $a" \
  || report D2 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a"

# D3: CONTROL — dispatch without the transfer FOR UPDATE (copies; the real ops functions are untouched)
q "$DB" "drop schema if exists rehearsal177 cascade; create schema rehearsal177; grant usage on schema rehearsal177 to authenticated;" >/dev/null
q "$DB" "do \$m\$ declare d text; k text := 'perform 1 from public.transfers t where t.payment_id = a.subject_id for update;'; begin
  d := pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure);
  if (length(d) - length(replace(d, k, ''))) / length(k) <> 1 then raise exception 'D3 mutant: dispatch anchor count <> 1'; end if;
  d := replace(d, 'CREATE OR REPLACE FUNCTION ops.action_dispatch(', 'CREATE OR REPLACE FUNCTION rehearsal177.action_dispatch_nolock(');
  d := replace(d, k, 'perform 1 from public.transfers t where t.payment_id = a.subject_id;');
  execute d;
  d := pg_get_functiondef('ops.action_run(uuid)'::regprocedure);
  if position('v_res := ops.action_dispatch(a);' in d) = 0 then raise exception 'D3 mutant: action_run anchor missing'; end if;
  d := replace(d, 'CREATE OR REPLACE FUNCTION ops.action_run(', 'CREATE OR REPLACE FUNCTION rehearsal177.action_run(');
  d := replace(d, 'v_res := ops.action_dispatch(a);', 'v_res := rehearsal177.action_dispatch_nolock(a);');
  execute d;
  d := pg_get_functiondef('ops.approve_action(uuid,text,text)'::regprocedure);
  if position('return ops.action_run(a.id);' in d) = 0 then raise exception 'D3 mutant: approve_action anchor missing'; end if;
  d := replace(d, 'CREATE OR REPLACE FUNCTION ops.approve_action(', 'CREATE OR REPLACE FUNCTION rehearsal177.approve_action(');
  d := replace(d, 'return ops.action_run(a.id);', 'return rehearsal177.action_run(a.id);');
  execute d;
end \$m\$;" >/dev/null || { echo "  FAIL D3 — could not build the mutant copies"; fail=1; }
race "$DB" "$(cron_hold "$(T 5)")" "$(approve "$DB" "$(aid "$DB" 5)" 0 rehearsal177.approve_action)"
a=$(act "$DB" 5)
[ "$R1" = "true" ] && [ "$(field "$R2" 1)" = "processing" ] && [ "$(field "$R2" 4)" = "ops-refund-execute" ] && [ "$LW" = "none" ] \
  && [ "$a" = "processing/" ] && [ "$(trs "$DB" 5)" = "auto_released" ] \
  && report D3 PASS "CONTROL dispatch without the transfer FOR UPDATE: s2 did not wait ($LW; ${W}ms informational), read the committed seller_sent row and handed off ($(field "$R2" 1), $(field "$R2" 4)) while the release committed: transfer $(trs "$DB" 5), action $a — the lock is load-bearing" \
  || report D3 FAIL "control did not reproduce: s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a transfer=$(trs "$DB" 5)"
q "$DB" "drop schema if exists rehearsal177 cascade;" >/dev/null

# D4: CONTROL — D1 on the clone without 177
race "$CDB" "$(cron_hold "$(T 1)")" "$(approve "$CDB" "$(aid "$CDB" 1)" 0)"
a=$(act "$CDB" 1)
[ "$R1" = "true" ] && [ "$(field "$R2" 1)" = "processing" ] && [ "$(field "$R2" 4)" = "ops-refund-execute" ] && [ "$a" = "processing/" ] \
  && report D4 PASS "CONTROL without 177: s2 handed off ($(field "$R2" 1), $(field "$R2" 4); lock waits: $LW; ${W}ms informational) on an order whose payout the cron released: transfer $(trs "$CDB" 1), action $a — the defect" \
  || report D4 FAIL "control did not reproduce the defect: s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a"

# D5: INDICATOR CONTROL — s1 holds the cron release of T3 (no refund parked on order 3); s2 approves order 6's refund
race "$DB" "$(cron_hold "$(T 3)")" "$(approve "$DB" "$(aid "$DB" 6)" 0)"
a=$(act "$DB" 6)
[ "$R1" = "true" ] && [ "$(field "$R2" 1)" = "processing" ] && [ "$LW" = "none" ] && [ "$a" = "processing/" ] \
  && report D5 PASS "INDICATOR CONTROL: while s1 held T3's release, s2 approved the refund on order 6 with no lock wait (Lock waits: $LW; ${W}ms informational): $(field "$R2" 1), action $a" \
  || report D5 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a"

# D6: the other direction (NOT COVERED, recorded): the approval holds T7 locked; the cron skips it
race "$DB" "$(approve "$DB" "$(aid "$DB" 7)" 1)" \
  "set lock_timeout = '10s'; select 'R=' || public.apply_auto_release('$(T 7)');"
a=$(act "$DB" 7)
[ "$(field "$R1" 1)" = "processing" ] && [ "$R2" = "false" ] && [ "$LW" = "none" ] && [ "$a" = "processing/" ] && [ "$(trs "$DB" 7)" = "seller_sent" ] \
  && report D6 PASS "approval s1 dispatched ($(field "$R1" 1)) and held T7; the cron's apply_auto_release s2 did not wait (SKIP LOCKED; Lock waits: $LW) and returned $R2; transfer $(trs "$DB" 7); no deadlock. A later cron run can release it while the refund is at Stripe: the reverse race, out of 177's scope" \
  || report D6 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) action=$a transfer=$(trs "$DB" 7)"

echo "RESULT: $([ $fail -eq 0 ] && echo ALL-PASS || echo FAILURES)"
exit $fail
