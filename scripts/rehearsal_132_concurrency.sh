#!/usr/bin/env bash
# ============================================================================
# scripts/rehearsal_132_concurrency.sh — LOCAL-ONLY two-session proof for
# migration 132 (claim_checkout_group). pgTAP runs in one transaction and
# cannot show concurrent inserts or lock waits; this drives real sessions
# against a loopback rehearsal database that already has 132 applied.
#
#   usage: scripts/rehearsal_132_concurrency.sh [dbname]   (default snatchit_rehears_132)
#
# Scenarios (each prints PASS/FAIL):
#   G1 the fresh-mint interleave, committed: request 1 claims the group; request
#      2 of the same group, with NO pending payment row anywhere, is refused at
#      once (claim_held) and never reaches a mint.
#   G2 the same interleave while request 1's claim insert is still uncommitted:
#      request 2 waits for it, then -> claim_held (one winner, never two).
#   G3 two requests racing to reclaim one ABANDONED claim (121 s old): exactly
#      one reclaims; the other waits, then -> claim_held.
#   G4 no lock interaction with settlement: while a session holds the payment
#      and listing rows FOR UPDATE (settlement order), a group claim completes
#      without waiting.
#   G6 CROSS-MODE (D F-132-1): a Buy Now checkout's claim is uncommitted while
#      the same buyer's AUCTION checkout claims the same listing: the auction
#      request waits, then -> claim_held. The group is (listing, buyer).
#   G5 no lock interaction with 130: while a session holds 130's row claim
#      transaction open on the group's pending payment, a group claim completes
#      without waiting.
#   C1 CONTROL — the same G2 interleave against a mutant claim WITHOUT the
#      "older than 120 s" condition: BOTH requests claim. That condition is what
#      serializes the group.
#   C2 CONTROL — the 130-only world: two requests that find no pending row
#      cannot take 130's claim (unknown_payment) and both record a pending
#      payment with a different intent: two live, confirmable attempts. This is
#      the defect 132 closes, reproduced on the same database.
# Fixture rows are committed under fixed ids and removed at the end.
# SAFETY: loopback only; scrubs remote connection variables. bash 3.2.
# ============================================================================
set -uo pipefail
unset SUPABASE_DB_URL DATABASE_URL PGSERVICE PGPASSWORD PGURL PGDATABASE 2>/dev/null
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}" PGPORT="${REHEARSAL_PGPORT:-5432}" PGUSER="${REHEARSAL_PGUSER:-postgres}" PGCONNECT_TIMEOUT=5
case "$PGHOST" in 127.0.0.1|localhost|::1) ;; *) echo "refusing non-loopback host $PGHOST" >&2; exit 1 ;; esac
DB="${1:-snatchit_rehears_132}"
case "$DB" in *rehears*) ;; *) echo "refusing database '$DB': name must contain 'rehears'" >&2; exit 1 ;; esac
q() { psql -X -At -v ON_ERROR_STOP=1 -d "$DB" -c "$1"; }
[ "$(q "select to_regprocedure('public.claim_checkout_group(uuid,uuid,text)') is not null")" = "t" ] || { echo "132 not applied to $DB" >&2; exit 1; }

L=13200000-0000-0000-0000-000000000001
P1=13200000-0000-0000-0000-000000000011
PA=13200000-0000-0000-0000-000000000021
PB=13200000-0000-0000-0000-000000000022
BUYER=$(q "select id from auth.users order by created_at limit 1")
SELLER=$(q "select id from auth.users order by created_at offset 1 limit 1")
[ -n "$BUYER" ] && [ -n "$SELLER" ] || { echo "need two auth.users rows in $DB" >&2; exit 1; }
T=$(mktemp -d)
cleanup() {
  q "delete from public.checkout_group_claim where listing_id = '$L';
     delete from public.payments where id in ('$P1','$PA','$PB'); delete from public.listings where id = '$L';
     drop schema if exists rehearsal132 cascade;" >/dev/null 2>&1
  rm -rf "$T"
}
trap cleanup EXIT
reset_fixture() {  # $1 = with-pending | no-pending
  cleanup; mkdir -p "$T"
  q "insert into public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
        starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
     values ('$L', '$SELLER', 'C132', 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '1 day', 100, 'f.jpg', 'active');" >/dev/null
  if [ "${1:-no-pending}" = "with-pending" ]; then
    q "insert into public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode)
       values ('$P1', '$L', '$BUYER', '$SELLER', 20000, 2000, 2000, 22000, 'pi_c132_p1', 'pending', 'buy_now', false);" >/dev/null
  fi
}
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
claim() { echo "select public.claim_checkout_group('$L','$BUYER','buy_now')->>'reason'"; }
fail=0
report() { if [ "$2" = "PASS" ]; then echo "  PASS $1 — $3"; else echo "  FAIL $1 — $3"; fail=1; fi; }

# G1: committed claim, no pending row anywhere
reset_fixture no-pending
a=$(q "$(claim)"); pend=$(q "select count(*) from public.payments where listing_id='$L'")
t0=$(ms); r=$(q "$(claim)"); t1=$(ms); w=$((t1 - t0))
[ "$a" = "claimed" ] && [ "$pend" = "0" ] && [ "$r" = "claim_held" ] && [ $w -lt 1000 ] \
  && report G1 PASS "no pending row; request1=$a, request2=$r after ${w}ms (no mint reachable)" || report G1 FAIL "request1=$a pending=$pend request2=$r waited=${w}ms"

# G2: request 1's claim still uncommitted
reset_fixture no-pending
( psql -X -At -d "$DB" -c "begin; $(claim); select pg_sleep(3); commit;" > "$T/g2a" 2>&1 ) &
sleep 0.5; t0=$(ms); r=$(q "$(claim)"); t1=$(ms); wait
w=$((t1 - t0)); a=$(head -2 "$T/g2a" | tail -1)
[ "$a" = "claimed" ] && [ "$r" = "claim_held" ] && [ $w -ge 2000 ] \
  && report G2 PASS "request1=$a (uncommitted), request2 waited ${w}ms then $r" || report G2 FAIL "request1=$a request2=$r waited=${w}ms"

# G3: two racers reclaim one abandoned claim
reset_fixture no-pending
q "insert into public.checkout_group_claim (listing_id, buyer_id, mode, claim_token, claimed_at) values ('$L','$BUYER','buy_now', gen_random_uuid(), now() - interval '121 seconds')" >/dev/null
( psql -X -At -d "$DB" -c "begin; $(claim); select pg_sleep(3); commit;" > "$T/g3a" 2>&1 ) &
sleep 0.5; t0=$(ms); r=$(q "$(claim)"); t1=$(ms); wait
w=$((t1 - t0)); a=$(head -2 "$T/g3a" | tail -1)
[ "$a" = "claimed" ] && [ "$r" = "claim_held" ] && [ $w -ge 2000 ] \
  && report G3 PASS "abandoned claim: racer1=$a, racer2 waited ${w}ms then $r" || report G3 FAIL "racer1=$a racer2=$r waited=${w}ms"

# G4: settlement-order locks held
reset_fixture with-pending
( psql -X -At -d "$DB" -c "begin; select 1 from public.payments where id='$P1' for update; select 1 from public.listings where id='$L' for update; select pg_sleep(3); commit;" > "$T/g4a" 2>&1 ) &
sleep 0.5; t0=$(ms); r=$(psql -X -At -d "$DB" -c "$(claim)" 2>&1); t1=$(ms); wait
w=$((t1 - t0))
if grep -q deadlock "$T/g4a" || [ "$r" != "claimed" ] || [ $w -ge 1000 ]; then report G4 FAIL "claim=$r waited=${w}ms $(cat "$T/g4a")"; else report G4 PASS "settlement locks held; claim=$r after ${w}ms"; fi

# G5: 130's row claim transaction open
reset_fixture with-pending
( psql -X -At -d "$DB" -c "begin; select public.claim_checkout_supersede('$L','$BUYER','$P1')->>'reason'; select pg_sleep(3); commit;" > "$T/g5a" 2>&1 ) &
sleep 0.5; t0=$(ms); r=$(psql -X -At -d "$DB" -c "$(claim)" 2>&1); t1=$(ms); wait
w=$((t1 - t0)); a=$(head -2 "$T/g5a" | tail -1)
if [ "$a" != "claimed" ] || [ "$r" != "claimed" ] || [ $w -ge 1000 ]; then report G5 FAIL "130 claim=$a group claim=$r waited=${w}ms"; else report G5 PASS "130 row claim=$a open; group claim=$r after ${w}ms"; fi

# G6: cross-mode, same buyer and listing
reset_fixture no-pending
( psql -X -At -d "$DB" -c "begin; select public.claim_checkout_group('$L','$BUYER','buy_now')->>'reason'; select pg_sleep(3); commit;" > "$T/g6a" 2>&1 ) &
sleep 0.5; t0=$(ms); r=$(q "select public.claim_checkout_group('$L','$BUYER','auction')->>'reason'"); t1=$(ms); wait
w=$((t1 - t0)); a=$(head -2 "$T/g6a" | tail -1)
[ "$a" = "claimed" ] && [ "$r" = "claim_held" ] && [ $w -ge 2000 ] \
  && report G6 PASS "buy_now=$a (uncommitted), auction request waited ${w}ms then $r" || report G6 FAIL "buy_now=$a auction=$r waited=${w}ms"

# C1: CONTROL — mutant without the staleness condition
reset_fixture no-pending
q "create schema rehearsal132;
   create function rehearsal132.claim_unconditional(p_listing_id uuid, p_buyer_id uuid, p_mode text) returns text language plpgsql as \$f\$
   declare v uuid; begin
     insert into public.checkout_group_claim as g (listing_id, buyer_id, mode, claim_token, claimed_at)
     values (p_listing_id, p_buyer_id, p_mode, gen_random_uuid(), now())
     on conflict on constraint checkout_group_claim_pkey do update set claim_token = excluded.claim_token, claimed_at = excluded.claimed_at
     returning g.claim_token into v;
     return case when v is null then 'claim_held' else 'claimed' end; end \$f\$;" >/dev/null
( psql -X -At -d "$DB" -c "begin; select rehearsal132.claim_unconditional('$L','$BUYER','buy_now'); select pg_sleep(3); commit;" > "$T/c1a" 2>&1 ) &
sleep 0.5; r=$(q "select rehearsal132.claim_unconditional('$L','$BUYER','buy_now')"); wait
a=$(head -2 "$T/c1a" | tail -1)
[ "$a" = "claimed" ] && [ "$r" = "claimed" ] \
  && report C1 PASS "without the 120 s condition both requests claim ($a / $r) — the condition is what serializes" || report C1 FAIL "control did not double-claim: $a / $r"

# C2: CONTROL — the 130-only world has nothing to claim before the mint
reset_fixture no-pending
c130=$(q "select public.claim_checkout_supersede('$L','$BUYER','$PA')->>'reason'")
( psql -X -At -d "$DB" -c "begin; select pg_sleep(1); insert into public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode) values ('$PA', '$L', '$BUYER', '$SELLER', 20000, 2000, 2000, 22000, 'pi_c132_a', 'pending', 'buy_now', false); commit;" > "$T/c2a" 2>&1 ) &
r=$(psql -X -At -d "$DB" -c "begin; select pg_sleep(1); insert into public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode) values ('$PB', '$L', '$BUYER', '$SELLER', 30000, 3000, 3000, 33000, 'pi_c132_b', 'pending', 'buy_now', false); commit;" 2>&1); wait
live=$(q "select count(distinct stripe_payment_intent_id) from public.payments where listing_id='$L' and buyer_id='$BUYER' and mode='buy_now' and status='pending'")
[ "$c130" = "unknown_payment" ] && [ "$live" = "2" ] \
  && report C2 PASS "130 claim before mint=$c130; both requests recorded a live attempt ($live intents) — the defect" || report C2 FAIL "130 claim=$c130 live=$live $(cat "$T/c2a") $r"

[ $fail -eq 0 ] && echo "RESULT: all concurrency scenarios PASS" || echo "RESULT: FAILURES"
exit $fail
