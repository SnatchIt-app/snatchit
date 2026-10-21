#!/usr/bin/env bash
# ============================================================================
# scripts/local/rehearsal_158_concurrency.sh — LOCAL-ONLY two-session proof for migration 158
# (20261021110000_ops_listing_relist_expected.sql, stacked on 157). pgTAP runs in one transaction and cannot show
# a lock wait; this drives real concurrent sessions against throwaway loopback clones.
#
#   usage: scripts/local/rehearsal_158_concurrency.sh <db_with_157_and_158> <control_db_with_157_only>
#   both names must start with a_sprint_ (a_sprint_prod_replay / _prod_template / _chain are refused);
#   host must be 127.0.0.1. Model: scripts/local/rehearsal_157_concurrency.sh.
#
# Scenarios (each prints PASS/FAIL). "Waited" is a LOCK-WAIT INDICATOR, never a wall-clock bound: pg_stat_activity is
# polled while session 2 runs and must show it in a heavyweight Lock wait (wait_event_type 'Lock', e.g.
# 'transactionid' = waiting for session 1's row lock); the elapsed ms are printed for information only.
# The sessions are found by application_name (r158_s1 / r158_s2) AND database: the server is shared, and a run of
# this script against other clones uses the same names, so every pg_stat_activity read is scoped to the race's
# own database (datname = current_database()). A second run against the SAME databases is refused at the start.
#   C1 session 1 (the owner's service-role path) BEGIN; admin_relist_listing + cancel_listing on listing L (a relist
#      and a deliberate re-cancel, uncommitted) and holds 3 s. Session 2 (founder A) submits the console relist with
#      the expected it read BEFORE session 1 began: it WAITS on the listing row lock, then answers rejected /
#      stale_state with result.current = the re-cancelled row; the listing stays cancelled.
#   C2 two founders relist the same cancelled listing with the same fresh expected: session 1 relists and holds;
#      session 2 WAITS, then gets stale_state. Exactly one relist (one succeeded action, one audit success).
#   C3 CONTROL — C1 against the clone WITHOUT 158 (157 only): session 2 waits (inside admin_relist_listing), then
#      SUCCEEDS: the re-cancellation is undone and the listing is live again (A15, reproduced under concurrency).
#   C4 CONTROL — C1 with a mutant dispatch that reads the listing WITHOUT FOR UPDATE (copies in schema rehearsal158;
#      the real ops functions are untouched): the compare runs on the committed pre-session-1 row and passes, then
#      admin_relist_listing waits and relists after session 1 commits. The FOR UPDATE is what makes the compare sound.
#   C5 relist vs the seller's cancel: session 1 relists (fresh expected) and holds; session 2 cancel_listing WAITS,
#      then cancels. No deadlock, no error (lock order unchanged: ops.action, then the listing; cancel takes only
#      the listing).
#   C6 INDICATOR CONTROL: session 1 holds the C1 relist + re-cancel on L1 again; session 2 relists ANOTHER listing (L5,
#      fresh expected): pg_stat_activity must show NO lock wait for it, and it succeeds. The indicator discriminates.
# Fixtures are committed under fixed ids (15800000-...) and LEFT IN PLACE: ops.audit is append-only, so the rows
# cannot be fully removed. Run only on throwaway clones; drop them afterwards.
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
    *) echo "refusing database '$d': name must start with a_sprint_ (usage: $0 <db_with_157_and_158> <control_db_with_157_only>)" >&2; exit 1 ;;
  esac
done
[ "$DB" != "$CDB" ] || { echo "the two databases must differ" >&2; exit 1; }
q()  { psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
srv=$(q "$DB" "select coalesce(host(inet_server_addr()),'socket')") || exit 1
case "$srv" in 127.0.0.1|::1|socket) ;; *) echo "refusing: server address $srv is not loopback" >&2; exit 1 ;; esac
HAS158="select position('-- 158 begin' in pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure)) > 0"
HAS157="select to_regclass('ops.action_money_unsettled_uidx') is not null"
[ "$(q "$DB"  "$HAS157")" = "t" ] && [ "$(q "$DB" "$HAS158")" = "t" ]  || { echo "$DB must have 157 and 158 applied" >&2; exit 1; }
[ "$(q "$CDB" "$HAS157")" = "t" ] && [ "$(q "$CDB" "$HAS158")" = "f" ] || { echo "$CDB must have 157 and NOT 158" >&2; exit 1; }
BUSY="select count(*) from pg_stat_activity where datname = current_database() and application_name in ('r158_s1', 'r158_s2')"
[ "$(q "$DB" "$BUSY")" = "0" ] && [ "$(q "$CDB" "$BUSY")" = "0" ] \
  || { echo "refusing: a rehearsal session (r158_s1 / r158_s2) is already connected to $DB or $CDB" >&2; exit 1; }

A=15800000-0000-0000-0000-0000000000a1      # founder A (platform_admin via admin_users; also the listings' seller)
B=15800000-0000-0000-0000-0000000000a2      # founder B
L() { printf '15800000-0000-0000-0001-%012d' "$1"; }
claims() { printf '{"sub":"%s","role":"authenticated","aal":"aal2"}' "$1"; }
as_founder() { printf "select set_config('request.jwt.claims', '%s', true); set local role authenticated;" "$(claims "$1")"; }

seed() {  # $1 db: founders, five admin-owned listings, each cancelled by its seller through cancel_listing
  q "$1" "
    insert into auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    select x.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', x.email, '{\"provider\":\"email\"}', '{}', now(), now()
      from (values ('$A'::uuid, 'r158-a@test.local'), ('$B'::uuid, 'r158-b@test.local')) x(id, email)
    on conflict (id) do nothing;
    insert into public.profiles (id, full_name, display_name)
    select x.id, '', x.label from (values ('$A'::uuid, 'R158 A'), ('$B'::uuid, 'R158 B')) x(id, label)
    on conflict (id) do nothing;
    insert into public.admin_users (user_id, label) values ('$A', 'R158 FOUNDER A'), ('$B', 'R158 FOUNDER B') on conflict (user_id) do nothing;
    insert into public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
                                 starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
    select ('15800000-0000-0000-0001-' || lpad(n::text, 12, '0'))::uuid, '$A', 'R158 #' || n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 1,
           'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'r158.jpg', 'active'
      from generate_series(1, 5) n on conflict (id) do nothing;" >/dev/null
  local n; for n in 1 2 3 4 5; do q "$1" "select public.cancel_listing('$(L $n)', '$A')" >/dev/null; done
}
# expected, exactly as the console reads it: the five relist keys of ops.listing_detail(id)->'listing' (founder A)
capture() {
  psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "begin; $(as_founder $A) select jsonb_build_object('updated_at', l->'updated_at', 'status', l->'status',
    'auction_status', l->'auction_status', 'ends_at', l->'ends_at', 'ended_at', l->'ended_at') from (select ops.listing_detail('$2') -> 'listing' l) x; commit;" \
    | grep '"updated_at"' | sed "s/'/''/g"      # (the set_config line is the claims JSON: not this one)
}
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
# console relist: db who key listing expected(sql-escaped) hold(0|1) [fn]  -> "status|reject_reason|action_id|current.auction_status|message"
relist() {
  local hold=""; [ "$6" = "1" ] && hold="select pg_sleep(3);"
  printf "begin; %s select 'R=' || concat_ws('|', coalesce(r->>'status',''), coalesce(r->>'reject_reason',''), coalesce(r->>'action_id',''),
            coalesce(r#>>'{result,current,auction_status}',''), coalesce(r->>'message',''))
          from (select %s('%s','listing_relist','listing','%s', jsonb_build_object('new_ends_at', now() + interval '3 days'), 'rehearsal 158', '%s'::jsonb) r) x; %s commit;" \
    "$(as_founder "$2")" "${7:-ops.execute_action}" "$3" "$4" "$5" "$hold"
}
# the owner's service-role path (postgres, no request claims): relist + deliberate re-cancel, uncommitted, held 3 s
owner_aba() {
  printf "begin; select public.admin_relist_listing('%s', now() + interval '7 days', '%s'); select public.cancel_listing('%s', '%s');
          select 'R=' || auction_status from public.listings where id = '%s'; select pg_sleep(3); commit;" "$1" "$A" "$1" "$A" "$1"
}
field() { printf '%s' "$1" | cut -d'|' -f"$2"; }
lst() { q "$1" "select status || '/' || auction_status || '/' || case when ended_at is null then 'open' else 'ended_at_set' end from public.listings where id = '$2'"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0
report() { if [ "$2" = "PASS" ]; then echo "  PASS $1 — $3"; else echo "  FAIL $1 — $3"; fail=1; fi; }

# race <db> <session-1 sql> <session-2 sql>: s1 in the background; s2 starts only once s1 is inside its 3 s hold
# (pg_stat_activity in <db>: application_name r158_s1, wait_event PgSleep). Sets R1, R2, W (ms s2 took, informational)
# and LW: the heavyweight-lock waits pg_stat_activity showed for s2 (in <db>: application_name r158_s2,
# wait_event_type Lock), polled while s2 runs; 'none' if never seen. Both reads run in <db> and filter on
# datname = current_database(), so sessions of the same name in another database are never counted.
race() {
  ( PGAPPNAME=r158_s1 psql -X -At -d "$1" -c "$2" > "$TMP/s1" 2>&1 ) &
  local p1=$! i=0
  until [ "$(q "$1" "select count(*) from pg_stat_activity where datname = current_database() and application_name = 'r158_s1' and wait_event = 'PgSleep'")" = "1" ] || [ $i -ge 200 ]; do
    sleep 0.05; i=$((i + 1))
  done
  [ $i -ge 200 ] && { echo "  FAIL — session 1 never reached its hold: the result below is not a race"; fail=1; }
  local t0; t0=$(ms)
  ( PGAPPNAME=r158_s2 psql -X -At -d "$1" -c "$3" > "$TMP/s2" 2>&1 ) &
  local p2=$! w
  : > "$TMP/lw"
  while kill -0 "$p2" 2>/dev/null; do
    w=$(q "$1" "select coalesce(string_agg(distinct wait_event, ','), '') from pg_stat_activity where datname = current_database() and application_name = 'r158_s2' and wait_event_type = 'Lock'")
    [ -n "$w" ] && echo "$w" >> "$TMP/lw"
    sleep 0.02
  done
  wait "$p2"; local t1; t1=$(ms); wait "$p1"
  W=$((t1 - t0)); R1=$(grep '^R=' "$TMP/s1" | sed 's/^R=//'); R2=$(grep '^R=' "$TMP/s2" | sed 's/^R=//')
  grep -qi 'deadlock\|ERROR' "$TMP/s1" && R1="ERROR:$(grep -i error "$TMP/s1" | head -1)"
  grep -qi 'ERROR' "$TMP/s2" && R2="ERROR:$(grep -i error "$TMP/s2" | head -1)"
  LW=$(sort -u "$TMP/lw" | tr '\n' ' ' | sed 's/ $//'); [ -n "$LW" ] || LW=none
}

echo "158 concurrency rehearsal: db=$DB control=$CDB $(date -u +%FT%TZ)"
seed "$DB"; seed "$CDB"
echo "  fixtures: $DB L1..L5 = $(lst "$DB" "$(L 1)"); $CDB L1 = $(lst "$CDB" "$(L 1)")"

# C1: relist + re-cancel held by the owner path; the stale console submit waits, then stale_state
E=$(capture "$DB" "$(L 1)")
race "$DB" "$(owner_aba "$(L 1)")" "$(relist "$DB" $A k158-c1-a "$(L 1)" "$E" 0)"
s=$(lst "$DB" "$(L 1)"); row=$(q "$DB" "select state || '/' || coalesce(reject_reason, '') from ops.action where idempotency_key = 'k158-c1-a'")
[ "$R1" = "cancelled" ] && [ "$(field "$R2" 1)" = "rejected" ] && [ "$(field "$R2" 2)" = "stale_state" ] && [ "$(field "$R2" 4)" = "cancelled" ] \
  && [ "$LW" != "none" ] && [ "$s" = "active/cancelled/ended_at_set" ] && [ "$row" = "rejected/stale_state" ] \
  && report C1 PASS "owner relist+re-cancel held 3 s; console s2 waited on a lock ($LW; ${W}ms informational), then $(field "$R2" 1)/$(field "$R2" 2) current.auction_status=$(field "$R2" 4); listing $s; action $row" \
  || report C1 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) listing=$s action=$row"

# C2: two founders, same fresh expected
E=$(capture "$DB" "$(L 2)")
race "$DB" "$(relist "$DB" $A k158-c2-a "$(L 2)" "$E" 1)" "$(relist "$DB" $B k158-c2-b "$(L 2)" "$E" 0)"
s=$(lst "$DB" "$(L 2)")
n_ok=$(q "$DB" "select count(*) from ops.action where action_type = 'listing_relist' and subject_id = '$(L 2)' and state = 'succeeded'")
n_aud=$(q "$DB" "select count(*) from ops.audit where action = 'action.listing_relist' and subject_id = '$(L 2)' and outcome = 'succeeded'")
[ "$(field "$R1" 1)" = "succeeded" ] && [ "$(field "$R2" 1)" = "rejected" ] && [ "$(field "$R2" 2)" = "stale_state" ] && [ "$(field "$R2" 4)" = "active" ] \
  && [ "$LW" != "none" ] && [ "$s" = "active/active/open" ] && [ "$n_ok" = "1" ] && [ "$n_aud" = "1" ] \
  && report C2 PASS "s1 $(field "$R1" 1) (held 3 s); s2 waited on a lock ($LW; ${W}ms informational), then $(field "$R2" 1)/$(field "$R2" 2); listing $s; succeeded relist actions=$n_ok, audit successes=$n_aud" \
  || report C2 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) listing=$s succeeded=$n_ok audit=$n_aud"

# C3: CONTROL — C1 on the clone without 158
E=$(capture "$CDB" "$(L 1)")
race "$CDB" "$(owner_aba "$(L 1)")" "$(relist "$CDB" $A k158-c3-a "$(L 1)" "$E" 0)"
s=$(lst "$CDB" "$(L 1)")
[ "$R1" = "cancelled" ] && [ "$(field "$R2" 1)" = "succeeded" ] && [ "$LW" != "none" ] && [ "$s" = "active/active/open" ] \
  && report C3 PASS "CONTROL without 158: s2 waited ($LW; ${W}ms informational) and then $(field "$R2" 1): the deliberate re-cancellation was undone, listing $s — the A15 defect" \
  || report C3 FAIL "control did not reproduce the defect: s1=$R1 s2=$R2 lock waits=$LW (${W}ms) listing=$s"

# C4: CONTROL — dispatch without FOR UPDATE (copies; the real ops functions are untouched)
q "$DB" "drop schema if exists rehearsal158 cascade; create schema rehearsal158; grant usage on schema rehearsal158 to authenticated;" >/dev/null
q "$DB" "do \$m\$ declare d text; begin
  d := pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure);
  if (length(d) - length(replace(d, 'into v_row from public.listings where id = a.subject_id for update;', ''))) / length('into v_row from public.listings where id = a.subject_id for update;') <> 1 then
    raise exception 'C4 mutant: dispatch anchor count <> 1';
  end if;
  d := replace(d, 'CREATE OR REPLACE FUNCTION ops.action_dispatch(', 'CREATE OR REPLACE FUNCTION rehearsal158.action_dispatch_nolock(');
  d := replace(d, 'into v_row from public.listings where id = a.subject_id for update;', 'into v_row from public.listings where id = a.subject_id;');
  execute d;
  d := pg_get_functiondef('ops.action_run(uuid)'::regprocedure);
  if position('v_res := ops.action_dispatch(a);' in d) = 0 then raise exception 'C4 mutant: action_run anchor missing'; end if;
  d := replace(d, 'CREATE OR REPLACE FUNCTION ops.action_run(', 'CREATE OR REPLACE FUNCTION rehearsal158.action_run(');
  d := replace(d, 'v_res := ops.action_dispatch(a);', 'v_res := rehearsal158.action_dispatch_nolock(a);');
  execute d;
  d := pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure);
  if position('return ops.action_run(a.id);' in d) = 0 then raise exception 'C4 mutant: execute_action anchor missing'; end if;
  d := replace(d, 'CREATE OR REPLACE FUNCTION ops.execute_action(', 'CREATE OR REPLACE FUNCTION rehearsal158.execute_action(');
  d := replace(d, 'return ops.action_run(a.id);', 'return rehearsal158.action_run(a.id);');
  execute d;
end \$m\$;" >/dev/null || { echo "  FAIL C4 — could not build the mutant copies"; fail=1; }
E=$(capture "$DB" "$(L 3)")
race "$DB" "$(owner_aba "$(L 3)")" "$(relist "$DB" $A k158-c4-a "$(L 3)" "$E" 0 rehearsal158.execute_action)"
s=$(lst "$DB" "$(L 3)")
[ "$R1" = "cancelled" ] && [ "$(field "$R2" 1)" = "succeeded" ] && [ "$LW" != "none" ] && [ "$s" = "active/active/open" ] \
  && report C4 PASS "CONTROL dispatch without FOR UPDATE: the compare read the committed pre-s1 row and passed; s2 then waited inside admin_relist_listing ($LW; ${W}ms informational) and $(field "$R2" 1): re-cancellation undone, listing $s — the lock is load-bearing" \
  || report C4 FAIL "control did not reproduce: s1=$R1 s2=$R2 lock waits=$LW (${W}ms) listing=$s"
q "$DB" "drop schema if exists rehearsal158 cascade;" >/dev/null

# C5: console relist held vs the seller's cancel_listing (postgres = the service-role path, seller id given)
E=$(capture "$DB" "$(L 4)")
race "$DB" "$(relist "$DB" $A k158-c5-a "$(L 4)" "$E" 1)" \
  "set lock_timeout = '10s'; select public.cancel_listing('$(L 4)', '$A'); select 'R=' || auction_status from public.listings where id = '$(L 4)';"
s=$(lst "$DB" "$(L 4)")
[ "$(field "$R1" 1)" = "succeeded" ] && [ "$R2" = "cancelled" ] && [ "$LW" != "none" ] && [ "$s" = "active/cancelled/ended_at_set" ] \
  && report C5 PASS "relist s1 $(field "$R1" 1) (held); seller cancel s2 waited ($LW; ${W}ms informational) then ran; listing $s; no deadlock, no error" \
  || report C5 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) listing=$s"

# C6: INDICATOR CONTROL — a session that never touches the held row shows no lock wait
E=$(capture "$DB" "$(L 5)")
race "$DB" "$(owner_aba "$(L 1)")" "$(relist "$DB" $A k158-c6-a "$(L 5)" "$E" 0)"
s=$(lst "$DB" "$(L 5)")
[ "$R1" = "cancelled" ] && [ "$(field "$R2" 1)" = "succeeded" ] && [ "$LW" = "none" ] && [ "$s" = "active/active/open" ] \
  && report C6 PASS "INDICATOR CONTROL: while s1 held L1, s2 relisted L5 with no lock wait seen (Lock waits: $LW; ${W}ms informational): $(field "$R2" 1), listing $s" \
  || report C6 FAIL "s1=$R1 s2=$R2 lock waits=$LW (${W}ms) listing=$s"

echo "RESULT: $([ $fail -eq 0 ] && echo ALL-PASS || echo FAILURES)"
exit $fail
