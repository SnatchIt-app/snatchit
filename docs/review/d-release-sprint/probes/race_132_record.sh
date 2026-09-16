#!/bin/bash
# D: 132 @ 9d82247 — the claim-bound insert under two live sessions, plus a lock-mode control.
# Throwaway clone of a local 132 rehearsal DB; dropped at the end. Loopback only.
set -u; export PGHOST=127.0.0.1 PGUSER=postgres LC_ALL=C
SRC=${1:-snatchit_d_132_rehears}; DB=d132_race_rehears
dropdb --if-exists $DB 2>/dev/null; createdb -T $SRC $DB || exit 1
q(){ psql -X -qtA -d $DB -v ON_ERROR_STOP=1 -c "$1"; }
ms(){ python3 -c 'import time;print(int(time.time()*1000))'; }
q "select tap.seed_core()" >/dev/null   # committed fixtures in the throwaway clone
L=$(q "select tap.listing_b()"); B=$(q "select '22222222-2222-2222-2222-222222222222'::uuid"); S=$(q "select seller_id from public.listings where id='$L'")
setup(){ # a claim already 121 s old, holder token returned
  q "delete from public.checkout_group_claim; delete from public.payments where stripe_payment_intent_id like 'pi_race%'" >/dev/null
  tok=$(q "select (public.claim_checkout_group('$L','$B','buy_now'))->>'claim_token'")
  q "update public.checkout_group_claim set claimed_at = now() - interval '121 seconds' where listing_id='$L'" >/dev/null
  echo "$tok"
}
rec(){ echo "select (public.record_checkout_attempt('$L','$B','buy_now','$1','$S',10000,1000,1000,11000,'$2',false))->>'reason'"; }

echo "R1 holder records first (open transaction); the reclaim must WAIT and then see the row"
tok=$(setup)
( psql -X -qtA -d $DB -c "begin; $(rec $tok pi_race_r1); select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
out=$(psql -X -qtA -d $DB -c "select (public.claim_checkout_group('$L','$B','buy_now'))->>'reason'"); t1=$(ms); wait
rows=$(q "select count(*) from public.payments where stripe_payment_intent_id='pi_race_r1'")
echo "  reclaim waited $((t1-t0)) ms → $out; holder's row visible to the reclaimer: $rows"
[ "$out" = "claimed" ] && [ "$rows" = "1" ] && [ $((t1-t0)) -ge 2000 ] && echo "  PASS R1" || echo "  FAIL R1"

echo "R2 reclaim first (open transaction); the holder's record must WAIT and then refuse"
tok=$(setup)
( psql -X -qtA -d $DB -c "begin; select public.claim_checkout_group('$L','$B','auction'); select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
out=$(psql -X -qtA -d $DB -c "$(rec $tok pi_race_r2)"); t1=$(ms); wait
rows=$(q "select count(*) from public.payments where stripe_payment_intent_id='pi_race_r2'")
echo "  holder waited $((t1-t0)) ms → $out; rows written: $rows"
[ "$out" = "claim_lost" ] && [ "$rows" = "0" ] && [ $((t1-t0)) -ge 2000 ] && echo "  PASS R2" || echo "  FAIL R2"

echo "C1 control — plain INSERT instead of the verb: the reclaim does NOT wait and misses the row"
tok=$(setup)
( psql -X -qtA -d $DB -c "begin; insert into public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode) values ('$L','$B','$S',10000,1000,1000,11000,'pi_race_c1','pending','buy_now',false); select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
out=$(psql -X -qtA -d $DB -c "select (public.claim_checkout_group('$L','$B','buy_now'))->>'reason'")
seen=$(psql -X -qtA -d $DB -c "select count(*) from public.payments where listing_id='$L' and buyer_id='$B' and status='pending'"); t1=$(ms); wait
echo "  reclaim waited $((t1-t0)) ms → $out; pending rows the reclaimer's read would see: $seen"
[ $((t1-t0)) -lt 2000 ] && [ "$seen" = "0" ] && echo "  PASS C1 (the defect the verb removes)" || echo "  FAIL C1"

echo "C2 mutant — FOR KEY SHARE instead of FOR SHARE: the reclaim must stop waiting (lock mode is load-bearing)"
psql -X -qtA -d $DB -c "$(psql -X -qtA -d $DB -c "select replace(pg_get_functiondef(p.oid), 'for share', 'for key share') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='record_checkout_attempt'")" >/dev/null
tok=$(setup)
( psql -X -qtA -d $DB -c "begin; $(rec $tok pi_race_c2); select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
sleep 0.5; t0=$(ms)
out=$(psql -X -qtA -d $DB -c "select (public.claim_checkout_group('$L','$B','buy_now'))->>'reason'")
seen=$(psql -X -qtA -d $DB -c "select count(*) from public.payments where stripe_payment_intent_id='pi_race_c2'"); t1=$(ms); wait
echo "  reclaim waited $((t1-t0)) ms → $out; holder's row visible: $seen"
[ $((t1-t0)) -lt 2000 ] && echo "  PASS C2 (mutant reopens the race, so FOR SHARE is what blocks)" || echo "  FAIL C2 (mutant still blocked — check the substitution)"
dropdb $DB
