#!/bin/bash
# Run the R4 matrix (API-mode steps) against the SANDBOX. Every PASS is REAL Stripe test-mode evidence.
# Device-only steps (PaymentSheet 3DS / decline-retry UI / Apple Pay) are printed as manual instructions.
. "$(dirname "$0")/lib.sh"; need psql jq curl stripe; stripe_mode_guard; cd "$ROOT"
BUYER_JWT=$(jwt "$BUYER_EMAIL" "$BUYER_PASSWORD"); SELLER_JWT=$(jwt "$SELLER_EMAIL" "$SELLER_PASSWORD"); U2_JWT=$(jwt "$U2_EMAIL" "$U2_PASSWORD")
[ -n "$BUYER_JWT" ] && [ -n "$SELLER_JWT" ] && [ -n "$U2_JWT" ] || { echo "sign-in failed for a fixture user"; exit 1; }
BUYER=$(uid "$BUYER_JWT"); SELLER=$(uid "$SELLER_JWT"); U2=$(uid "$U2_JWT")
RUN_START=$(sql "select now()::text")   # every audit query is scoped to this run
note "users buyer=$BUYER seller=$SELLER u2=$U2"

# ── P0.9 seller Connect (Express test account) — hosted onboarding is a browser step the owner completes once
ACCT=$(sql "select stripe_connect_id from public.profiles where id='$SELLER'")
if [ -z "$ACCT" ]; then
  r=$(edge create-connect-account "$SELLER_JWT" '{}'); url=$(printf '%s' "$r" | head -1 | jq -r '.url // empty')
  note "OWNER: open this Express onboarding URL in a browser with Stripe TEST identity data, then re-run: $url"; exit 0
fi
check "P0.9 seller onboarded: connect id + onboarding complete" "select (stripe_connect_id is not null)::text || '|' || coalesce(stripe_onboarding_complete::text,'null') from public.profiles where id='$SELLER'" "true|true"
cap=$(sjson get "/v1/accounts/$ACCT" | jq -r '.capabilities.transfers // "missing"')
[ "$cap" = "active" ] && ok "P0.9 REAL Stripe: transfers capability active on $ACCT" || bad "P0.9 capability" "transfers=$cap"

# ── P0.10 listings (service SQL; client gates bypassed on purpose)
# NOTE: listings.buy_now_price / starting_bid are DOLLARS (payments.* are cents).
# 100 dollars => amount 10000c + 10% buyer fee = total 11000c (10/10 fee model).
mk_listing(){ sql "insert into public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status) values ('$SELLER','Sandbox $1','Club','wynwood', current_date + 30, '21:00','GA',1,'mobile_transfer',100,true,100,24, now(), now() + interval '24 hours',100,'fixtures/$1.jpg','active') returning id"; }
L1=$(mk_listing L1); L4=$(mk_listing L4); L6=$(mk_listing L6); L7=$(mk_listing L7); L9=$(mk_listing L9)
note "listings L1=$L1 L4=$L4 L6=$L6 L7=$L7 L9=$L9"

# create-payment-intent is rate limited to 5 calls / 60 s per user (fail-closed, by
# design). The matrix legitimately mints more than that, so pace: on 429 wait out the
# window once and retry. A 429 is recorded as real evidence that the limiter works.
RL_SEEN=0
mint(){ # $1 listing $2 jwt → prints PI id
  local r code pi
  r=$(edge create-payment-intent "$2" "{\"listing_id\":\"$1\",\"mode\":\"buy_now\",\"expected_total_cents\":11000}")
  code=$(printf '%s' "$r" | tail -1); pi=$(printf '%s' "$r" | head -1 | jq -r '.paymentIntentId // empty')
  if [ "$code" = "429" ]; then
    RL_SEEN=1
    sleep 62
    r=$(edge create-payment-intent "$2" "{\"listing_id\":\"$1\",\"mode\":\"buy_now\",\"expected_total_cents\":11000}")
    pi=$(printf '%s' "$r" | head -1 | jq -r '.paymentIntentId // empty')
  fi
  printf '%s' "$pi"; }
# PostgREST returns 204 (no content) for a void RPC; treat 200/204 as success
reserve(){ local c; c=$(rpc reserve_buy_now "$2" "{\"p_listing_id\":\"$1\",\"p_user_id\":\"$3\",\"p_minutes\":10}" | tail -1); case "$c" in 200|204) echo 200;; *) echo "$c";; esac; }
rpc_ok(){ local c; c=$(rpc "$1" "$2" "$3" | tail -1); case "$c" in 200|204) echo 200;; *) echo "$c";; esac; }

# ── S1 happy path [API]
[ "$(reserve "$L1" "$BUYER_JWT" "$BUYER")" = "200" ] && ok "S1.1 reserve_buy_now (old signature with p_minutes) 200" || bad "S1.1 reserve" "non-200"
check "S1.1 window server-fixed to 10 min" "select (reserved_by='$BUYER' and reserved_until between now() + interval '9 minutes' and now() + interval '11 minutes')::text from public.listings where id='$L1'" "true"
PI1=$(mint "$L1" "$BUYER_JWT"); [ -n "$PI1" ] && ok "S1.2 create-payment-intent → $PI1" || bad "S1.2 mint" "no PI"
check "S1.2 pending row, total 11000, test-mode" "select status || '|' || total || '|' || stripe_livemode from public.payments where stripe_payment_intent_id='$PI1'" "pending|11000|false"
[ "$(mint "$L1" "$BUYER_JWT")" = "$PI1" ] && ok "S1.2 idempotent re-mint returns the same PI" || bad "S1.2 reuse" "different PI"
req "S1.2 PI minted" "$PI1" && { st=$(sjson post "/v1/payment_intents/$PI1/confirm" -d payment_method=pm_card_visa -d return_url=snatchit://checkout | jq -r '.status // "error"'); [ "$st" = "succeeded" ] && ok "S1.3 REAL Stripe confirm (pm_card_visa) → succeeded" || bad "S1.3 confirm" "status=$st"; }
wait_for "S1.3 webhook settles: payment succeeded, listing sold, ONE transfer" "select p.status || '|' || l.status || '|' || (select count(*) from public.transfers t where t.payment_id=p.id) from public.payments p join public.listings l on l.id=p.listing_id where p.stripe_payment_intent_id='$PI1'" "succeeded|sold|1" 90
r=$(edge confirm-payment "$BUYER_JWT" "{\"payment_intent_id\":\"$PI1\"}"); [ "$(printf '%s' "$r" | tail -1)" = "200" ] && ok "S1.3 confirm-payment (build-13 shape) 200 after settlement" || bad "S1.3 confirm-payment" "$(printf '%s' "$r" | tail -1)"
r=$(edge confirm-payment "$U2_JWT" "{\"payment_intent_id\":\"$PI1\"}"); [ "$(printf '%s' "$r" | tail -1)" = "403" ] && ok "S1.4 wrong buyer → 403" || bad "S1.4 wrong buyer" "$(printf '%s' "$r" | tail -1)"
# Old-client parity: after the webhook settled the sale, the shipped build-13 call
# is REFUSED with the benign message the client already tolerates (src/lib/payments.ts
# /already sold/i; pgTAP 120 asserts the same text). Anything else is a regression.
msr=$(rpc mark_listing_sold "$BUYER_JWT" "{\"p_listing_id\":\"$L1\",\"p_user_id\":\"$BUYER\"}"); msg=$(printf '%s' "$msr" | head -1 | jq -r '.message // ""' 2>/dev/null)
case "$(printf '%s' "$msr" | tail -1)|$msg" in
  200*|204*) ok "S1.3 old-client mark_listing_sold accepted (idempotent)";;
  400*already*sold*) ok "S1.3 old-client mark_listing_sold refused with the benign, client-tolerated 'already been sold'";;
  *) bad "S1.3 old mark_listing_sold" "$(printf '%s' "$msr" | tail -1) $msg";;
esac
check "S1.3 still exactly one transfer" "select count(*) from public.transfers where listing_id='$L1'" "1"

# ── S4 abandoned checkout → PaymentIntent canceled [API]
reserve "$L4" "$BUYER_JWT" "$BUYER" >/dev/null; PI4=$(mint "$L4" "$BUYER_JWT")
sql "select set_config('app.bypass_listing_guard','on',true); update public.listings set reserved_until = now() - interval '1 minute' where id='$L4'" >/dev/null
r=$(edge create-payment-intent "$BUYER_JWT" "{\"listing_id\":\"$L4\",\"mode\":\"buy_now\",\"expected_total_cents\":11000}"); [ "$(printf '%s' "$r" | tail -1)" = "409" ] && ok "S4 lapsed hold: re-mint → 409, old PI retired" || bad "S4 re-mint" "$(printf '%s' "$r" | tail -1)"
check "S4 abandoned row failed" "select status from public.payments where stripe_payment_intent_id='$PI4'" "failed"
st4=$(sjson get "/v1/payment_intents/$PI4" | jq -r '.status // "error"'); [ "$st4" = "canceled" ] && ok "S4 REAL Stripe: PI canceled" || bad "S4 stripe status" "status=$st4"
wait_for "S4 payment_intent.canceled delivered and processed (endpoint subscribed)" "select (count(*) >= 1)::text from public.stripe_webhook_events where event_type='payment_intent.canceled' and processed_at is not null and received_at >= '$RUN_START'" "true" 90 || note "S4 if the sandbox endpoint lacks payment_intent.canceled this proves the 08 doc gap"

# ── S5 webhook twice / out of order [API]
EVT=$(sjson get /v1/events -d "type=payment_intent.succeeded" -d limit=1 | jq -r '.data[0].id // empty'); req "S5.1 a succeeded event exists to resend" "$EVT" || EVT=""
AC=$(sql "select attempt_count from public.stripe_webhook_events where event_id='$EVT'")
[ -n "$EVT" ] && { stripe events resend "$EVT" --webhook-endpoint "$STRIPE_WEBHOOK_ENDPOINT_ID" >/dev/null 2>&1; sleep 8; }
[ -n "$EVT" ] && check "S5.1 resend of a processed event: attempt_count unchanged (already_processed)" "select coalesce((select attempt_count from public.stripe_webhook_events where event_id='$EVT')::text,'missing')" "${AC:-missing}"
check "S5.1 no double settlement" "select count(*) from public.transfers where listing_id='$L1'" "1"

# ── S6 refunds partial + full [API] (on PI1)
rid=$(sjson post /v1/refunds -d "payment_intent=$PI1" -d amount=500 | jq -r '.id // empty'); [ -n "$rid" ] && ok "S6.1 REAL partial refund 500 ($rid)" || bad "S6.1 refund" "no refund id"
wait_for "S6.1 ledgered: succeeded|500|1 refund row" "select p.status || '|' || p.amount_refunded_cents || '|' || (select count(*) from public.payment_refunds r where r.payment_id=p.id) from public.payments p where stripe_payment_intent_id='$PI1'" "succeeded|500|1" 60
RID1=$(sql "select stripe_refund_id from public.payments where stripe_payment_intent_id='$PI1'")
rid2=$(sjson post /v1/refunds -d "payment_intent=$PI1" | jq -r '.id // empty'); [ -n "$rid2" ] && ok "S6.2 REAL full remainder refund ($rid2)" || bad "S6.2 refund" "no refund id"
wait_for "S6.2 refunded|11000|2 rows, first refund id kept (monotonic)" "select p.status || '|' || p.amount_refunded_cents || '|' || (select count(*) from public.payment_refunds r where r.payment_id=p.id) || '|' || (p.stripe_refund_id='$RID1')::text from public.payments p where stripe_payment_intent_id='$PI1'" "refunded|11000|2|true" 60
check "S6.2 REFUNDED_AFTER_PAYOUT not raised (transfer unpaid) but transfer obligation closed for deletion" "select count(*) from public.payout_decisions d join public.transfers t on t.id=d.transfer_id where t.listing_id='$L1' and 'REFUNDED_AFTER_PAYOUT' = any(d.reason_codes)" "0"

# ── S7 dispute [API] (L6, pm_card_createDispute)
reserve "$L6" "$BUYER_JWT" "$BUYER" >/dev/null; PI6=$(mint "$L6" "$BUYER_JWT")
req "S7 PI minted" "$PI6" && sjson post "/v1/payment_intents/$PI6/confirm" -d payment_method=pm_card_createDispute -d return_url=snatchit://checkout >/dev/null
wait_for "S7 settled then disputed: transfer disputed, disputes row needs_response" "select coalesce((select t.status from public.transfers t join public.payments p on p.id=t.payment_id where p.stripe_payment_intent_id='$PI6'),'-') || '|' || coalesce((select d.status from public.disputes d join public.payments p on p.id=d.payment_id where p.stripe_payment_intent_id='$PI6'),'-')" "disputed|needs_response" 150
DP=$(sql "select d.stripe_dispute_id from public.disputes d join public.payments p on p.id=d.payment_id where p.stripe_payment_intent_id='$PI6'")
req "S7 dispute id" "$DP" && sjson post "/v1/disputes/$DP" -d "evidence[uncategorized_text]=losing_evidence" >/dev/null
wait_for "S7 LOST: payment refunded via chargeback ledger (dispute id, no refund id)" "select p.status || '|' || (select count(*) from public.payment_refunds r where r.payment_id=p.id and r.stripe_dispute_id='$DP' and r.stripe_refund_id is null) from public.payments p where p.stripe_payment_intent_id='$PI6'" "refunded|1" 120

# ── S8 payout leg [API] — REAL Connect test transfer through the attempt ledger.
# Precondition: the sandbox PLATFORM must hold enough AVAILABLE balance, else Stripe
# refuses with "insufficient available funds" and the attempt is recorded failed
# (correct behaviour, but it does not exercise the success path). Top up with Stripe's
# designated test card, which credits the available balance immediately.
avail=$(sjson get /v1/balance | jq -r '[.available[] | select(.currency=="usd") | .amount] | first // 0')
if [ "${avail:-0}" -lt 15000 ]; then
  sjson post /v1/payment_intents -d amount=50000 -d currency=usd -d payment_method=pm_card_bypassPending -d confirm=true -d "automatic_payment_methods[enabled]=true" -d "automatic_payment_methods[allow_redirects]=never" >/dev/null
  sleep 5; avail=$(sjson get /v1/balance | jq -r '[.available[] | select(.currency=="usd") | .amount] | first // 0')
fi
[ "${avail:-0}" -ge 9000 ] && ok "S8.pre sandbox platform AVAILABLE balance sufficient for the payout ($avail cents)" || bad "S8.pre balance" "$avail cents"
reserve "$L7" "$BUYER_JWT" "$BUYER" >/dev/null; PI7=$(mint "$L7" "$BUYER_JWT")
req "S8 PI minted" "$PI7" && sjson post "/v1/payment_intents/$PI7/confirm" -d payment_method=pm_card_bypassPending -d return_url=snatchit://checkout >/dev/null
wait_for "S8.0 settled (funds available immediately: bypassPending card)" "select count(*) from public.transfers t join public.payments p on p.id=t.payment_id where p.stripe_payment_intent_id='$PI7'" "1" 90
T7=$(sql "select t.id from public.transfers t join public.payments p on p.id=t.payment_id where p.stripe_payment_intent_id='$PI7'"); req "S8.0 transfer row exists" "$T7" || T7=""
st_before=$(sql "select status from public.transfers where id='$T7'")
msr=$(rpc mark_transfer_sent "$SELLER_JWT" "{\"p_transfer_id\":\"$T7\",\"p_user_id\":\"$SELLER\"}")
case "$(printf '%s' "$msr" | tail -1)" in
  200|204) ok "S8.1 seller marks sent (status was $st_before)";;
  *) bad "S8.1 mark sent" "HTTP $(printf '%s' "$msr" | tail -1) status_before=$st_before body=$(printf '%s' "$msr" | head -1 | head -c 160)";;
esac
r=$(edge confirm-and-release "$BUYER_JWT" "{\"transfer_id\":\"$T7\"}"); body=$(printf '%s' "$r" | head -1)
cr_tr=$(printf '%s' "$body" | jq -r '.stripe_transfer_id // empty'); cr_ok=$(printf '%s' "$body" | jq -r '.success // false')
if [ "$cr_ok" = "true" ] && [ "${cr_tr#tr_}" != "$cr_tr" ]; then
  ok "S8.2 confirm-and-release → REAL Stripe transfer created ($cr_tr)"
else
  bad "S8.2 confirm-and-release" "success=$cr_ok tr=$cr_tr status=$(sql "select status from public.transfers where id='$T7'") body=$(printf '%s' "$body" | head -c 200)"
fi
check "S8.2 ledger: one attempt succeeded, tr_ on the row, released" "select (select count(*) from public.payout_attempts a where a.transfer_id='$T7' and a.state='succeeded') || '|' || (stripe_transfer_id like 'tr_%')::text || '|' || (payout_released_at is not null)::text from public.transfers where id='$T7'" "1|true|true"
TR7=$([ -n "$T7" ] && sql "select coalesce(stripe_transfer_id,'') from public.transfers where id='$T7'")
if req "S8.2 stripe transfer id recorded" "$TR7"; then
  tr_json=$(sjson get "/v1/transfers/$TR7")
  [ "$(printf '%s' "$tr_json" | jq -r '.transfer_group // empty')" = "$T7" ] && ok "S8.2 REAL Stripe transfer carries transfer_group = transfer id" || bad "S8.2 transfer_group" "$(printf '%s' "$tr_json" | jq -r '.transfer_group // "none"')"
  [ "$(printf '%s' "$tr_json" | jq -r '.amount // empty')" = "9000" ] && ok "S8.2 amount 9000 = amount − seller_fee (10/10 fee model)" || bad "S8.2 amount" "$(printf '%s' "$tr_json" | jq -r '.amount // "none"')"
  [ "$(printf '%s' "$tr_json" | jq -r 'if .livemode == false then "false" else "other" end')" = "false" ] && ok "S8.2 the transfer is TEST mode (livemode=false)" || bad "S8.2 livemode" "not false"
fi
if [ -n "$T7" ]; then r=$(edge confirm-and-release "$BUYER_JWT" "{\"transfer_id\":\"$T7\"}"); b2=$(printf '%s' "$r" | head -1)
  # documented repeat-call contract (confirm-and-release/index.ts): {success:true, already_released:true}
  tr2=$(printf '%s' "$b2" | jq -r '.stripe_transfer_id // empty'); ar2=$(printf '%s' "$b2" | jq -r 'if .already_released == true then "true" else "false" end'); ok2=$(printf '%s' "$b2" | jq -r '.success // false')
  if [ "$ok2" = "true" ] && { [ "$ar2" = "true" ] || [ "$tr2" = "$TR7" ]; }; then ok "S8.3 second confirm-and-release is an idempotent no-op (already_released=$ar2, no second payout)"; else bad "S8.3 second confirm-and-release" "success=$ok2 already_released=$ar2 tr=$tr2 body=$(printf '%s' "$b2" | head -c 160)"; fi; fi
check "S8.3 still exactly one attempt / one tr_" "select count(*) from public.payout_attempts where transfer_id='$T7'" "1"
if [ -n "$TR7" ]; then rev=$(sjson post "/v1/transfers/$TR7/reversals" | jq -r '.id // empty'); [ -n "$rev" ] && ok "S8.4 REAL reversal posted ($rev)" || bad "S8.4 reversal" "no reversal id"; fi
wait_for "S8.4 transfer.reversed webhook → transfer reversed" "select status from public.transfers where id='$T7'" "reversed" 60

# ── S9 deletion with obligations [API] (u2 buys L9, no seller send → paid order with open transfer)
reserve "$L9" "$U2_JWT" "$U2" >/dev/null; PI9=$(mint "$L9" "$U2_JWT")
req "S9 PI minted" "$PI9" && sjson post "/v1/payment_intents/$PI9/confirm" -d payment_method=pm_card_visa -d return_url=snatchit://checkout >/dev/null
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
check "S12 no unresolved review rows from this run" "select count(*) from public.webhook_retries where resolved is not true and rpc_name='settle_verified_payment' and error_message not like 'unknown_payment:%' and created_at >= '$RUN_START'" "0"
check "S12 every webhook event of this run was processed" "select count(*) from public.stripe_webhook_events where processed_at is null and received_at >= '$RUN_START' and received_at < now() - interval '2 minutes'" "0"
check "S12 no open payout attempts from this run" "select count(*) from public.payout_attempts where state in ('claimed','requested','unknown') and claimed_at >= '$RUN_START'" "0"
check "S12 no live-mode payment row exists in the sandbox (mode boundary)" "select count(*) from public.payments where stripe_livemode is true" "0"
[ "$RL_SEEN" = "1" ] && ok "REAL rate limiter: create-payment-intent returned 429 after 5 calls in 60 s and succeeded after the window (fail-closed, by design)"
note "DEVICE-ONLY (not run): S2 3DS challenge (4000 0025 0000 3155) in PaymentSheet; S3 decline-then-retry in one sheet (4000 0000 0000 0002 → 4242); Apple Pay. Run on a dev build pointed at $TEST_REF; assert the same S1 DB facts."
echo "matrix summary: pass=$PASS fail=$FAILN → $RESULTS"; [ "$FAILN" -eq 0 ]
