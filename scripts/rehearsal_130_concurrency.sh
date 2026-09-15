#!/usr/bin/env bash
# ============================================================================
# scripts/rehearsal_130_concurrency.sh — LOCAL-ONLY two-session proof for
# migration 130 (claim_checkout_supersede). pgTAP runs in one transaction and
# cannot show lock waits; this drives two real sessions against a loopback
# rehearsal database that already has 130 applied.
#
#   usage: scripts/rehearsal_130_concurrency.sh [dbname]   (default snatchit_rehears_130)
#
# Scenarios (each prints PASS/FAIL):
#   S1 claims on DIFFERENT rows of one group: session 2's claim on P2 waits for
#      session 1's claim on P1 to commit, then sees it -> claim_held.
#   S2 claims on the SAME row: session 2 waits, then -> claim_held.
#   S3 settlement order (payments -> listings) running while a claim arrives on
#      the same payment: no deadlock; the claim completes after settlement.
#   S4 a claim holding the listing while settlement-order locks arrive on a
#      sibling payment: no deadlock.
#   C1 CONTROL — the inverted order (listings first, then the payment) against
#      settlement order DOES deadlock (40P01): the reason 130 locks payments first.
# Fixture rows are committed under fixed ids and removed at the end.
# SAFETY: loopback only; scrubs remote connection variables. bash 3.2.
# ============================================================================
set -uo pipefail
unset SUPABASE_DB_URL DATABASE_URL PGSERVICE PGPASSWORD PGURL PGDATABASE 2>/dev/null
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}" PGPORT="${REHEARSAL_PGPORT:-5432}" PGUSER="${REHEARSAL_PGUSER:-postgres}" PGCONNECT_TIMEOUT=5
case "$PGHOST" in 127.0.0.1|localhost|::1) ;; *) echo "refusing non-loopback host $PGHOST" >&2; exit 1 ;; esac
DB="${1:-snatchit_rehears_130}"
q() { psql -X -At -v ON_ERROR_STOP=1 -d "$DB" -c "$1"; }
[ "$(q "select to_regprocedure('public.claim_checkout_supersede(uuid,uuid,uuid)') is not null")" = "t" ] || { echo "130 not applied to $DB" >&2; exit 1; }

L=13000000-0000-0000-0000-000000000001
P1=13000000-0000-0000-0000-000000000011
P2=13000000-0000-0000-0000-000000000012
BUYER=$(q "select id from auth.users order by created_at limit 1")
SELLER=$(q "select id from auth.users order by created_at offset 1 limit 1")
[ -n "$BUYER" ] && [ -n "$SELLER" ] || { echo "need two auth.users rows in $DB" >&2; exit 1; }
T=$(mktemp -d)
cleanup() {
  q "delete from public.payments where id in ('$P1','$P2'); delete from public.listings where id = '$L';" >/dev/null 2>&1
  rm -rf "$T"
}
trap cleanup EXIT
reset_fixture() {
  cleanup; mkdir -p "$T"
  q "insert into public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
        starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
     values ('$L', '$SELLER', 'C130', 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(), now() + interval '1 day', 100, 'f.jpg', 'active');
     insert into public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode)
     values ('$P1', '$L', '$BUYER', '$SELLER', 20000, 2000, 2000, 22000, 'pi_c130_p1', 'pending', 'buy_now', false),
            ('$P2', '$L', '$BUYER', '$SELLER', 30000, 3000, 3000, 33000, 'pi_c130_p2', 'pending', 'buy_now', false);" >/dev/null
}
ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
fail=0
report() { if [ "$2" = "PASS" ]; then echo "  PASS $1 — $3"; else echo "  FAIL $1 — $3"; fail=1; fi; }

# S1: different rows, one group
reset_fixture
( psql -X -At -d "$DB" -c "begin; select public.claim_checkout_supersede('$L','$BUYER','$P1')->>'reason'; select pg_sleep(3); commit;" > "$T/s1a" 2>&1 ) &
sleep 0.5; t0=$(ms)
r=$(q "select public.claim_checkout_supersede('$L','$BUYER','$P2')->>'reason'"); t1=$(ms); wait
w=$((t1 - t0)); a=$(head -2 "$T/s1a" | tail -1)
[ "$a" = "claimed" ] && [ "$r" = "claim_held" ] && [ $w -ge 2000 ] && report S1 PASS "session1=$a, session2 waited ${w}ms then $r" || report S1 FAIL "session1=$a session2=$r waited=${w}ms"

# S2: same row
reset_fixture
( psql -X -At -d "$DB" -c "begin; select public.claim_checkout_supersede('$L','$BUYER','$P1')->>'reason'; select pg_sleep(3); commit;" > "$T/s2a" 2>&1 ) &
sleep 0.5; t0=$(ms)
r=$(q "select public.claim_checkout_supersede('$L','$BUYER','$P1')->>'reason'"); t1=$(ms); wait
w=$((t1 - t0)); a=$(head -2 "$T/s2a" | tail -1)
[ "$a" = "claimed" ] && [ "$r" = "claim_held" ] && [ $w -ge 2000 ] && report S2 PASS "session1=$a, session2 waited ${w}ms then $r" || report S2 FAIL "session1=$a session2=$r waited=${w}ms"

# S3: settlement order (payment then listing) vs a claim on the same payment
reset_fixture
( psql -X -At -d "$DB" -c "begin; select 1 from public.payments where id='$P1' for update; select pg_sleep(1); select 1 from public.listings where id='$L' for update; select pg_sleep(2); commit;" > "$T/s3a" 2>&1 ) &
sleep 0.3
r=$(psql -X -At -d "$DB" -c "select public.claim_checkout_supersede('$L','$BUYER','$P1')->>'reason'" 2>&1); wait
if grep -q deadlock "$T/s3a" || echo "$r" | grep -q deadlock; then report S3 FAIL "deadlock: $(cat "$T/s3a") / $r"; else report S3 PASS "no deadlock; claim after settlement-order locks = $r"; fi

# S4: a claim holding the listing vs settlement-order locks on a sibling payment
reset_fixture
( psql -X -At -d "$DB" -c "begin; select public.claim_checkout_supersede('$L','$BUYER','$P1')->>'reason'; select pg_sleep(2); commit;" > "$T/s4a" 2>&1 ) &
sleep 0.3
r=$(psql -X -At -d "$DB" -c "begin; select 1 from public.payments where id='$P2' for update; select 1 from public.listings where id='$L' for update; commit;" 2>&1); wait
if grep -q deadlock "$T/s4a" || echo "$r" | grep -q deadlock; then report S4 FAIL "deadlock: $(cat "$T/s4a") / $r"; else report S4 PASS "no deadlock; claim=$(head -2 "$T/s4a" | tail -1)"; fi

# C1: CONTROL — inverted order (listing, then payment) against settlement order deadlocks
reset_fixture
( psql -X -At -d "$DB" -c "begin; select 1 from public.payments where id='$P1' for update; select pg_sleep(1); select 1 from public.listings where id='$L' for update; commit;" > "$T/c1a" 2>&1 ) &
sleep 0.3
r=$(psql -X -At -d "$DB" -c "begin; select 1 from public.listings where id='$L' for update; select pg_sleep(1); update public.payments set supersede_claimed_at = now() where id='$P1'; commit;" 2>&1); wait
if grep -q "deadlock detected" "$T/c1a" || echo "$r" | grep -q "deadlock detected"; then report C1 PASS "inverted order deadlocks (40P01) — the order 130 avoids"; else report C1 FAIL "control did not deadlock: $(cat "$T/c1a") / $r"; fi

[ $fail -eq 0 ] && echo "RESULT: all concurrency scenarios PASS" || echo "RESULT: FAILURES"
exit $fail
