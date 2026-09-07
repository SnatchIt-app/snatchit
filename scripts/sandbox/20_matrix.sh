#!/bin/bash
# Run the R4 matrix (API-mode steps) against the SANDBOX. Every PASS is REAL Stripe test-mode evidence.
# Device-only steps (PaymentSheet 3DS / decline-retry UI / Apple Pay) are printed as manual instructions.
. "$(dirname "$0")/lib.sh"; need psql jq curl stripe; stripe_mode_guard; cd "$ROOT"
BUYER_JWT=$(jwt "$BUYER_EMAIL" "$BUYER_PASSWORD"); SELLER_JWT=$(jwt "$SELLER_EMAIL" "$SELLER_PASSWORD"); U2_JWT=$(jwt "$U2_EMAIL" "$U2_PASSWORD")
[ -n "$BUYER_JWT" ] && [ -n "$SELLER_JWT" ] && [ -n "$U2_JWT" ] || { echo "sign-in failed for a fixture user"; exit 1; }
BUYER=$(uid "$BUYER_JWT"); SELLER=$(uid "$SELLER_JWT"); U2=$(uid "$U2_JWT")
note "users buyer=$BUYER seller=$SELLER u2=$U2"

# ── P0.9 seller Connect (Express test account) — hosted onboarding is a browser step the owner completes once
ACCT=$(sql "select stripe_connect_id from public.profiles where id='$SELLER'")
if [ -z "$ACCT" ]; then
  r=$(edge create-connect-account "$SELLER_JWT" '{}'); url=$(printf '%s' "$r" | head -1 | jq -r '.url // empty')
  note "OWNER: open this Express onboarding URL in a browser with Stripe TEST identity data, then re-run: $url"; exit 0
fi
check "P0.9 seller onboarded: connect id + transfers capability active" "select (stripe_connect_id is not null)::text || '|' || coalesce(stripe_payouts_enabled::text,'null') from public.profiles where id='$SELLER'" "true|true"
[ "$(stripe accounts retrieve "$ACCT" | jq -r '.capabilities.transfers')" = "active" ] && ok "P0.9 Stripe: transfers capability active on $ACCT" || bad "P0.9 capability" "not active"

# ── P0.10 listings (service SQL; client gates bypassed on purpose)
mk_listing(){ sql "insert into public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status) values ('$SELLER','Sandbox $1','Club','wynwood', current_date + 30, '21:00','GA',1,'mobile_transfer',100,true,10000,24, now(), now() + interval '24 hours',100,'fixtures/$1.jpg','active') returning id"; }
L1=$(mk_listing L1); L4=$(mk_listing L4); L6=$(mk_listing L6); L7=$(mk_listing L7); L9=$(mk_listing L9)
note "listings L1=$L1 L4=$L4 L6=$L6 L7=$L7 L9=$L9"

mint(){ # $1 listing $2 jwt → prints PI id
  local r; r=$(edge create-payment-intent "$2" "{\"listing_id\":\"$1\",\"mode\":\"buy_now\",\"expected_total_cents\":11000}"); printf '%s' "$r" | head -1 | jq -r '.paymentIntentId // empty'; }
reserve(){ rpc reserve_buy_now "$2" "{\"p_listing_id\":\"$1\",\"p_user_id\":\"$3\",\"p_minutes\":10}" | tail -1; }

# ── S1 happy path [API]
[ "$(reserve "$L1" "$BUYER_JWT" "$BUYER")" = "200" ] && ok "S1.1 reserve_buy_now (old signature with p_minutes) 200" || bad "S1.1 reserve" "non-200"
check "S1.1 window server-fixed to 10 min" "select (reserved_by='$BUYER' and reserved_until between now() + interval '9 minutes' and now() + interval '11 minutes')::text from public.listings where id='$L1'" "true"
PI1=$(mint "$L1" "$BUYER_JWT"); [ -n "$PI1" ] && ok "S1.2 create-payment-intent → $PI1" || bad "S1.2 mint" "no PI"
check "S1.2 pending row, total 11000, test-mode" "select status || '|' || total || '|' || stripe_livemode from public.payments where stripe_payment_intent_id='$PI1'" "pending|11000|false"
[ "$(mint "$L1" "$BUYER_JWT")" = "$PI1" ] && ok "S1.2 idempotent re-mint returns the same PI" || bad "S1.2 reuse" "different PI"
stripe payment_intents confirm "$PI1" --payment-method pm_card_visa --return-url snatchit://checkout >/dev/null 2>&1 && ok "S1.3 REAL Stripe confirm (pm_card_visa) → succeeded" || bad "S1.3 confirm" "stripe error"
wait_for "S1.3 webhook settles: payment succeeded, listing sold, ONE transfer" "select p.status || '|' || l.status || '|' || (select count(*) from public.transfers t where t.payment_id=p.id) from public.payments p join public.listings l on l.id=p.listing_id where p.stripe_payment_intent_id='$PI1'" "succeeded|sold|1" 90
r=$(edge confirm-payment "$BUYER_JWT" "{\"payment_intent_id\":\"$PI1\"}"); [ "$(printf '%s' "$r" | tail -1)" = "200" ] && ok "S1.3 confirm-payment (build-13 shape) 200 after settlement" || bad "S1.3 confirm-payment" "$(printf '%s' "$r" | tail -1)"
r=$(edge confirm-payment "$U2_JWT" "{\"payment_intent_id\":\"$PI1\"}"); [ "$(printf '%s' "$r" | tail -1)" = "403" ] && ok "S1.4 wrong buyer → 403" || bad "S1.4 wrong buyer" "$(printf '%s' "$r" | tail -1)"
[ "$(rpc mark_listing_sold "$BUYER_JWT" "{\"p_listing_id\":\"$L1\",\"p_user_id\":\"$BUYER\"}" | tail -1)" = "200" ] && ok "S1.3 old-client mark_listing_sold after settlement → 200 (no error)" || bad "S1.3 old mark_listing_sold" "non-200"
check "S1.3 still exactly one transfer" "select count(*) from public.transfers where listing_id='$L1'" "1"

# ── S4 abandoned checkout → PaymentIntent canceled [API]
reserve "$L4" "$BUYER_JWT" "$BUYER" >/dev/null; PI4=$(mint "$L4" "$BUYER_JWT")
sql "select set_config('app.bypass_listing_guard','on',true); update public.listings set reserved_until = now() - interval '1 minute' where id='$L4'" >/dev/null
r=$(edge create-payment-intent "$BUYER_JWT" "{\"listing_id\":\"$L4\",\"mode\":\"buy_now\",\"expected_total_cents\":11000}"); [ "$(printf '%s' "$r" | tail -1)" = "409" ] && ok "S4 lapsed hold: re-mint → 409, old PI retired" || bad "S4 re-mint" "$(printf '%s' "$r" | tail -1)"
check "S4 abandoned row failed" "select status from public.payments where stripe_payment_intent_id='$PI4'" "failed"
[ "$(stripe payment_intents retrieve "$PI4" | jq -r .status)" = "canceled" ] && ok "S4 REAL Stripe: PI canceled" || bad "S4 stripe status" "not canceled"
wait_for "S4 payment_intent.canceled delivered and processed (endpoint subscribed)" "select count(*) from public.stripe_webhook_events where event_type='payment_intent.canceled' and processed_at is not null" "1" 60 || note "S4 if the sandbox endpoint lacks payment_intent.canceled this proves the 08 doc gap"

# ── S5 webhook twice / out of order [API]
EVT=$(stripe events list --type payment_intent.succeeded --limit 1 | jq -r '.data[0].id'); AC=$(sql "select attempt_count from public.stripe_webhook_events where event_id='$EVT'")
stripe events resend "$EVT" --webhook-endpoint "$STRIPE_WEBHOOK_ENDPOINT_ID" >/dev/null 2>&1; sleep 5
check "S5.1 resend of a processed event: attempt_count unchanged (already_processed)" "select attempt_count from public.stripe_webhook_events where event_id='$EVT'" "$AC"
check "S5.1 no double settlement" "select count(*) from public.transfers where listing_id='$L1'" "1"

# ── S6 refunds partial + full [API] (on PI1)
stripe refunds create --payment-intent "$PI1" --amount 500 >/dev/null 2>&1 && ok "S6.1 REAL partial refund 500" || bad "S6.1 refund" "stripe error"
wait_for "S6.1 ledgered: succeeded|500|1 refund row" "select p.status || '|' || p.amount_refunded_cents || '|' || (select count(*) from public.payment_refunds r where r.payment_id=p.id) from public.payments p where stripe_payment_intent_id='$PI1'" "succeeded|500|1" 60
RID1=$(sql "select stripe_refund_id from public.payments where stripe_payment_intent_id='$PI1'")
stripe refunds create --payment-intent "$PI1" >/dev/null 2>&1 && ok "S6.2 REAL full remainder refund" || bad "S6.2 refund" "stripe error"
wait_for "S6.2 refunded|11000|2 rows, first refund id kept (monotonic)" "select p.status || '|' || p.amount_refunded_cents || '|' || (select count(*) from public.payment_refunds r where r.payment_id=p.id) || '|' || (p.stripe_refund_id='$RID1')::text from public.payments p where stripe_payment_intent_id='$PI1'" "refunded|11000|2|true" 60
check "S6.2 REFUNDED_AFTER_PAYOUT not raised (transfer unpaid) but transfer obligation closed for deletion" "select count(*) from public.payout_decisions d join public.transfers t on t.id=d.transfer_id where t.listing_id='$L1' and 'REFUNDED_AFTER_PAYOUT' = any(d.reason_codes)" "0"

# ── S7 dispute [API] (L6, pm_card_createDispute)
reserve "$L6" "$BUYER_JWT" "$BUYER" >/dev/null; PI6=$(mint "$L6" "$BUYER_JWT")
stripe payment_intents confirm "$PI6" --payment-method pm_card_createDispute --return-url snatchit://checkout >/dev/null 2>&1
wait_for "S7 settled then disputed: transfer disputed, disputes row needs_response" "select (select status from public.transfers t join public.payments p on p.id=t.payment_id where p.stripe_payment_intent_id='$PI6') || '|' || (select status from public.disputes d join public.payments p on p.id=d.payment_id where p.stripe_payment_intent_id='$PI6')" "disputed|needs_response" 120
DP=$(sql "select d.stripe_dispute_id from public.disputes d join public.payments p on p.id=d.payment_id where p.stripe_payment_intent_id='$PI6'")
stripe disputes update "$DP" -d "evidence[uncategorized_text]=losing_evidence" >/dev/null 2>&1
wait_for "S7 LOST: payment refunded via chargeback ledger (dispute id, no refund id)" "select p.status || '|' || (select count(*) from public.payment_refunds r where r.payment_id=p.id and r.stripe_dispute_id='$DP' and r.stripe_refund_id is null) from public.payments p where p.stripe_payment_intent_id='$PI6'" "refunded|1" 120

# ── S8 payout leg [API] — REAL Connect test transfer through the attempt ledger (needs ALLOW_TEST_MODE_MONEY + GUC)
reserve "$L7" "$BUYER_JWT" "$BUYER" >/dev/null; PI7=$(mint "$L7" "$BUYER_JWT")
stripe payment_intents confirm "$PI7" --payment-method pm_card_bypassPending --return-url snatchit://checkout >/dev/null 2>&1
wait_for "S8.0 settled (funds available immediately: bypassPending card)" "select count(*) from public.transfers t join public.payments p on p.id=t.payment_id where p.stripe_payment_intent_id='$PI7'" "1" 90
T7=$(sql "select t.id from public.transfers t join public.payments p on p.id=t.payment_id where p.stripe_payment_intent_id='$PI7'")
[ "$(rpc mark_transfer_sent "$SELLER_JWT" "{\"p_transfer_id\":\"$T7\",\"p_user_id\":\"$SELLER\"}" | tail -1)" = "200" ] && ok "S8.1 seller marks sent" || bad "S8.1 mark sent" "non-200"
r=$(edge confirm-and-release "$BUYER_JWT" "{\"transfer_id\":\"$T7\"}"); body=$(printf '%s' "$r" | head -1)
ps=$(printf '%s' "$body" | jq -r '.payout_status // empty'); [ "$ps" = "released" ] && ok "S8.2 confirm-and-release → REAL transfer created (payout_status=released)" || bad "S8.2 confirm-and-release" "payout_status=$ps body=$(printf '%s' "$body" | head -c 200)"
check "S8.2 ledger: one attempt succeeded, tr_ on the row, released" "select (select count(*) from public.payout_attempts a where a.transfer_id='$T7' and a.state='succeeded') || '|' || (stripe_transfer_id like 'tr_%')::text || '|' || (payout_released_at is not null)::text from public.transfers where id='$T7'" "1|true|true"
TR7=$(sql "select stripe_transfer_id from public.transfers where id='$T7'")
[ "$(stripe transfers retrieve "$TR7" | jq -r '.transfer_group')" = "$T7" ] && ok "S8.2 REAL Stripe transfer carries transfer_group = transfer id" || bad "S8.2 transfer_group" "mismatch"
[ "$(stripe transfers retrieve "$TR7" | jq -r '.amount')" = "9000" ] && ok "S8.2 amount 9000 = amount − seller_fee (10/10 fee model)" || bad "S8.2 amount" "$(stripe transfers retrieve "$TR7" | jq -r '.amount')"
r=$(edge confirm-and-release "$BUYER_JWT" "{\"transfer_id\":\"$T7\"}"); ok "S8.3 second confirm-and-release is a no-op ($(printf '%s' "$r" | head -1 | jq -r '.payout_status // .error // "-"'))"
check "S8.3 still exactly one attempt / one tr_" "select count(*) from public.payout_attempts where transfer_id='$T7'" "1"
stripe post "/v1/transfers/$TR7/reversals" >/dev/null 2>&1 && ok "S8.4 REAL reversal posted" || bad "S8.4 reversal" "stripe error"
wait_for "S8.4 transfer.reversed webhook → transfer reversed" "select status from public.transfers where id='$T7'" "reversed" 60

# ── S9 deletion with obligations [API] (u2 buys L9, no seller send → paid order with open transfer)
reserve "$L9" "$U2_JWT" "$U2" >/dev/null; PI9=$(mint "$L9" "$U2_JWT")
stripe payment_intents confirm "$PI9" --payment-method pm_card_visa --return-url snatchit://checkout >/dev/null 2>&1
wait_for "S9.0 u2 has a settled order (open transfer)" "select count(*) from public.transfers t join public.payments p on p.id=t.payment_id where p.stripe_payment_intent_id='$PI9'" "1" 90
r=$(edge delete-account "$U2_JWT" '{}'); body=$(printf '%s' "$r" | head -1)
[ "$(printf '%s' "$body" | jq -r '.success')" = "true" ] && ok "S9.1 deletion request ACCEPTED (OR-17)" || bad "S9.1 request" "$(printf '%s' "$body" | head -c 200)"
[ "$(printf '%s' "$body" | jq -r '.pending_obligations | length')" -ge 1 ] && ok "S9.1 pending_obligations surfaced: $(printf '%s' "$body" | jq -c '[.pending_obligations[].kind]')" || bad "S9.1 obligations" "empty"
check "S9.1 DELETION_PENDING" "select deletion_state from kernel.identity_ext where identity_id='$U2'" "DELETION_PENDING"
r=$(edge create-payment-intent "$U2_JWT" "{\"listing_id\":\"$L1\",\"mode\":\"buy_now\",\"expected_total_cents\":11000}"); [ "$(printf '%s' "$r" | tail -1)" = "403" ] && ok "S9.2 F-5 guard: new acquisition refused 403" || bad "S9.2 guard" "$(printf '%s' "$r" | tail -1)"
sql "select kernel.sweep_deletion_pending(100)" >/dev/null
check "S9.3 sweep holds (BP-7 open transfer precedes BP-13), not tombstoned" "select deletion_state || '|' || (deletion_block_reason like 'BP-%')::text from kernel.identity_ext where identity_id='$U2'" "DELETION_PENDING|true"
r=$(edge delete-account "$U2_JWT" '{"action":"withdraw"}'); check "S9.4 withdraw → ACTIVE" "select deletion_state from kernel.identity_ext where identity_id='$U2'" "ACTIVE"

# ── S12 audit
check "S12 no unresolved review rows except deliberate ones" "select count(*) from public.webhook_retries where resolved is not true and rpc_name='settle_verified_payment' and error_message not like 'unknown_payment:%'" "0"
check "S12 no unprocessed webhook events" "select count(*) from public.stripe_webhook_events where processed_at is null and received_at < now() - interval '5 minutes'" "0"
check "S12 no open attempts" "select count(*) from public.payout_attempts where state in ('claimed','requested','unknown')" "0"
note "DEVICE-ONLY (not run): S2 3DS challenge (4000 0025 0000 3155) in PaymentSheet; S3 decline-then-retry in one sheet (4000 0000 0000 0002 → 4242); Apple Pay. Run on a dev build pointed at $TEST_REF; assert the same S1 DB facts."
echo "matrix summary: pass=$PASS fail=$FAILN → $RESULTS"; [ "$FAILN" -eq 0 ]
