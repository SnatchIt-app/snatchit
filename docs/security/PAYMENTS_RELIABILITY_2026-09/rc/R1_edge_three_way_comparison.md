# RC Agent 1 — Edge-function three-way behavioral comparison

Date: 2026-09-06. Read-only review. No repo file edited; no network/Supabase/Stripe/MCP calls.

## 0. Sources and identity facts

| Label | Source | Verified |
|---|---|---|
| **A** deployed prod | `scratchpad/deployed/<fn>/<fn>/index.ts` + `deployed/<fn>/_shared/*` | fetched today |
| **B** main | `git -C snatchit-pay show origin/main:supabase/functions/...` | |
| **C** draft PR #54 | `/Users/josetascon/snatchit-pay/supabase/functions/...` | `rev-parse HEAD` = `31128c160fbec88c37f4628547baa3149f2dbea7`, clean tree |
| **D** Phase-2 | `git -C snatchit-consol show 10ad9e42…~0:supabase/functions/...` (`<sha>:<path>` resolves to the commit in that repo; `<sha>~0:<path>` was used and cross-checked against `ls-tree` blob ids) | consol working tree untouched |

Byte-identity matrix (diff line counts; blob SHA of A files equals the D blob for the 5 that match):

| File | A vs D | A vs B | C vs A |
|---|---|---|---|
| create-payment-intent | **0** | 31 (F-5 guard) | 238 |
| confirm-payment | **0** | **0** | 239 |
| confirm-and-release | **0** | 41 (ANON_KEY + F-5 guard) | 499 |
| delete-account | **0** | 251 (OR-17 tombstone) | 364 |
| stripe-webhook | 899 (D is 1791 lines, A 902) | **0** | 635 |
| enforce-transfer-expiry | **0** | **0** | 790 |
| _shared/money, payout-policy, sentry, stripe | 0 | 0 | 0 |
| _shared/payout-logic | 0 | 0 | 58 |
| _shared/payouts | 0 | 0 | 361 |

Consequences:
* Deployed A **is** the Phase-2 source D for everything except stripe-webhook (D's native-venue webhook was never deployed).
* A ≡ B for confirm-payment, stripe-webhook, enforce-transfer-expiry and every `_shared` file → there is **no production-only behavior** in those five files. Production-only behavior lives only in create-payment-intent, confirm-and-release and delete-account.
* CORS allow-lists (`https://snatchitapp.com`, `https://www.snatchitapp.com`), security headers, `Allow-Headers` (webhook adds `stripe-signature`) are identical across A/B/C for all six functions. No env-var differences except `SUPABASE_ANON_KEY` (see §2).
* No `supabase/config.toml` exists in B, C or D (verify_jwt settings are dashboard-side; A's headers state "Verify JWT must be DISABLED" for confirm-payment / confirm-and-release — unchanged in C).

---

## 1. Per-function behavioral differences

Line numbers: `A:` deployed file, `B:` origin/main, `C:` draft worktree, `D:` Phase-2 commit.

### 1.1 create-payment-intent

**A vs B** (only one difference):

| # | Behavior | A (deployed) | B (main) |
|---|---|---|---|
| 1 | F-5 live-rail acquisition guard | A:253-282. After rate-limit, before body parse: service client `db.schema='kernel'`, `rpc('is_deletion_pending',{p_identity: buyerId})`; `pending===true` → **403** `{error:'Your account deletion request is pending. Withdraw it in Settings to make new purchases.', code:'account_deletion_pending'}`; RPC error / throw → fail-open, proceed. | absent (B:253 goes straight to `req.json()`). |

**A vs D**: identical.

**C vs A** (draft adds Package-1 reservation authority; draft DROPS the F-5 guard):

| # | Behavior | A | C |
|---|---|---|---|
| 1 | F-5 guard | present A:253-282 | **absent** (C:327→329 jumps from rate limit to `req.json()`) |
| 2 | Listing select | A:300 no reservation cols | C:344 adds `reserved_by, reserved_until, ends_at` |
| 3 | "Sold in fact" check | none | C:396-418: SELECT payments where `status='succeeded'` for listing; DB error → **503** `Retry-After:10`; another buyer's succeeded row → **409** `This listing is already sold.` (via `refuse()`, which retires this buyer's pending PIs) |
| 4 | buy_now gating | A:331-343: `status!=='reserved'` → 400 `Listing is not reserved for purchase`; buy_now disabled → 400 | C:420-441: `status==='sold'` → 409 `already sold`; `!=='reserved'` → 400 same text (now via `refuse()`); `reserved_by!==buyer` → 409 `This listing is already reserved by another buyer.`; window lapsed → 409 `Your reservation expired. Please reserve the listing again.`; then buy_now-disabled 400 unchanged |
| 5 | auction gating | A:345-358 | C:445-463 adds `status==='sold'` → 409, and live Buy-Now hold by another buyer → 409 `already reserved by another buyer` |
| 6 | Stale-PI retirement | A only retires the buyer's own pending row when Stripe reports the PI `canceled` (A:461-475) | C:210-275 `retirePendingIntents()` + `cancelPaymentIntentBestEffort()` — on every refusal, this buyer's pending PIs for (listing,mode) are cancelled at Stripe (POST `/payment_intents/{id}/cancel`) and rows set `failed` only when cancel confirmed; C:555 before reuse/mint, **all OTHER buyers'** pending PIs on the listing are cancelled + retired |
| 7 | Pending-PI reuse amount binding | A:476 reuses any non-canceled pending PI with a `client_secret` | C:588-621: if `pi.amount !== totalCents || currency!=='usd'` → cancel; if cancel refused → **409** `Price changed…` with `server_total_cents`; else retire row, `failedAttempts++`, mint fresh |
| 8 | PI body | A:513-527 | C adds `metadata[reserved_until]` for buy_now (C:672-679) |
| 9 | Stage logs | — | C adds `checkout-refused`, `sold-check-failed`, `stale-pending-retired`, `other-buyer-pending-retired`, `reuse-rejected-amount-mismatch` |
| 10 | Typing only | `ReturnType<typeof createClient>` | `SupabaseClient` (no behavior) |

Unchanged in C: auth (401 regex path), rate limit 5/60 (503/429), 404/400 texts, fee math, customer/ephemeral-key flow, 23505 race recovery, PI-cancel-on-insert-fail, response shape.

### 1.2 confirm-payment

**A vs B**: identical. **A vs D**: identical.

**C vs A**:

| # | Behavior | A | C |
|---|---|---|---|
| 1 | Stripe GET | A:178 `/payment_intents/{id}` | C:190 `?expand[]=latest_charge&expand[]=latest_charge.refunds` |
| 2 | Ownership check | none (writes filtered by `.eq('buyer_id', buyerId)`) | C:222-246: `metadata.buyer_id===caller` OR `payments.buyer_id===caller`; otherwise **403** `This payment does not belong to you.` (new non-2xx path; probing another buyer's PI is refused) |
| 3 | Not-succeeded / Stripe unreachable | 200 `{success:true, stripe_verified:false}`, no writes | same (C:216-219, 248-257) |
| 4 | Settlement | A:215-229 direct `payments` UPDATE (`status,paid_at,payment_method`); A:243-288 direct `transfers` INSERT (24h expiry, transfer_method from listing), errors swallowed | C:268-280 single RPC `settle_verified_payment(p_payment_intent_id, p_stripe_status, p_amount_received, p_currency, p_livemode, p_amount_refunded, p_stripe_refund_id, p_payment_method, p_metadata, p_source='confirm-payment')`; no direct table writes |
| 5 | RPC error | n/a | **500** `Payment could not be recorded. Please do not pay again; …` + Sentry `confirm-payment:settle` (A never returned 500 except catch-all) |
| 6 | Success response | `{success:true, stripe_verified:true}` | adds `outcome`, `transfer_id` (additive) |

Unchanged: auth, rate limit 10/60, 400 on missing `payment_intent_id`, CORS/security headers.

### 1.3 confirm-and-release

**A vs B**:

| # | Behavior | A | B |
|---|---|---|---|
| 1 | Env | A:40 `SUPABASE_ANON_KEY` | absent |
| 2 | F-5 inbound-transfer guard | A:257-295: after the transfer SELECT, before the not-found check: anon-key client carrying the caller's `authorization` header, `db.schema='kernel'`, `from('identity_ext').select('deletion_state, deletion_requested_at').eq('identity_id', buyerId).maybeSingle()`; if `DELETION_PENDING` and `transfers.created_at > deletion_requested_at` (service-client read A:278-282) → **403** `{error:'Your account deletion request is pending. Withdraw it in Settings to accept new transfers.', code:'account_deletion_pending'}`; any error → fail-open | absent |

**A vs D**: identical.

**C vs A**:

| # | Behavior | A | C |
|---|---|---|---|
| 1 | Env | `STRIPE_SECRET_KEY` (unused), `SUPABASE_ANON_KEY` | both removed (C:37-38); `_shared/stripe.ts` reads the Stripe key itself so only ANON_KEY matters |
| 2 | F-5 guard | A:257-295 | **absent** (C:234→236) |
| 3 | Status gate | A:328 only `buyer_confirmed` | C:265 also accepts `auto_released` |
| 4 | Already-paid short-circuit | A:336-345 on `payout_released_at` | removed; handled by `claim_payout_attempt` → `ALREADY_RELEASED` |
| 5 | Payment / seller lookups | A:405-449 direct selects; deferrals `PAYMENT_LOOKUP_FAILED`, `PAYMENT_NOT_SUCCEEDED`, `SELLER_NOT_ONBOARDED` | removed; claim RPC returns `not_eligible` reasons (`TRANSFER_NOT_FOUND, TRANSFER_NOT_RELEASABLE, DISPUTED, PAYMENT_NOT_SUCCEEDED, PAYMENT_NOT_LIVE, SELLER_NOT_ONBOARDED, PAYOUT_AMOUNT_INVALID`); `DISPUTED` → **409** frozen text; others → `payoutDeferred(reason)` 200 `pending_review` |
| 6 | Final dispute recheck | A:475-508 re-read transfers before Stripe | removed (inside claim RPC) |
| 7 | Money movement | A:518-525 `createSellerPayout` (POST `/transfers`, key `payout_<id>_<dest>_src`) then A:586-590 `record_transfer_payout` | C:345-350 `executePayoutAttempt` → RPCs `claim_payout_attempt`, `reconcile_payout_attempt`, `mark_payout_requested`, `record_payout_attempt_result`; Stripe GET `/transfers?transfer_group=<id>` on open attempts; POST `/transfers` with `transfer_group`, `metadata[attempt_id/attempt_no]`, key `payout_<id>_a<n>` |
| 8 | New 200 bodies | `{success, stripe_transfer_id}`, `{success, already_released}`, `{success, payout_status:'pending_review'}`, `{success, warning:'Payout sent but record update failed'}` | drops `warning` body; adds `{success, payout_status:'processing'}` (in_progress / reconcile_pending / unknown / db_error / reconciled-not-found) and `{success, already_released, stripe_transfer_id}` (reconciled-found) |
| 9 | Sentry | on unexpected Stripe error classes; DB-update-after-transfer is log-only | adds `confirm-and-release:paid-during-dispute` and `confirm-and-release:record-payout-failed` (3-arg `captureException`, supported by unchanged sentry.ts:78-82) |
| 10 | Audit row | A:626-644 `payout_decisions` release row | same fields + `attempt_id, attempt_no, destination_suffix` (C:356-377) |

Unchanged: auth (401), rate limit 5/300 (503/429), 400 missing transfer_id, `confirm_transfer_received` RPC and its `buyer_confirmed|auto_released` tolerance, 404, 403 not-buyer, 409 dispute freeze (pre-claim), CORS/security.

### 1.4 delete-account

**A vs B** (A is the OR-17 tombstone; B is the original physical delete):

| # | Behavior | A (deployed, 186 lines) | B (main, 235 lines) |
|---|---|---|---|
| 1 | Env | A:45 `SUPABASE_ANON_KEY` | absent |
| 2 | OPTIONS | A:108-110 **204** empty body | B:105-107 200 `'ok'` |
| 3 | Non-POST | A:111-113 **405** `Method not allowed` | no check |
| 4 | Auth | A:116-131 service client `auth:{autoRefreshToken:false,persistSession:false}`, `getUser(token)`; 401 texts `Missing authorization` / `Invalid or expired token` | B:111-127 same texts, client built with global Authorization header |
| 5 | Rate limit | A:89-105 `delete_account` **5 / 3600s**; 429 checked before 503 | B:135-145 **3 / 300s**; 503 checked before 429 (same codes/texts) |
| 6 | Body | A:141-150 `{action}`; empty/unparseable → `'request'`; not `request|withdraw` → **400** `action must be 'request' or 'withdraw'` | body ignored |
| 7 | Request-time blockers | none (A header L12-14: request-time 409s retired; active transfer is BP-7 in the DB sweep) | B:150-161 active transfers (`pending|seller_sent`) → **409** `You have active ticket transfers in progress…` |
| 8 | Core action | A:154-162 anon-key client with caller JWT, `db.schema='kernel'`, `rpc(request_account_deletion | withdraw_account_deletion, {p_command_key:'edge-<action>-<uuid>'})` | B:171-224 `delete_account_cleanup` RPC (500 on error) → delete `bids` → storage `avatars`/`auction-media` remove (non-fatal) → `auth.admin.deleteUser` (500 on error) |
| 9 | RPC error | A:164-172 **500** action-specific text + `captureException('delete-account', …)` | B:175-180 500 cleanup text, no Sentry; B:221-224 500 delete text |
| 10 | Success body | A:176-181 `{success:true, action, status:<rpc status ?? 'ok'>, deletion_state:'DELETION_PENDING'|'ACTIVE'}` | B:227 `{success:true}` |
| 11 | Storage / auth user | never touched | deleted |

**A vs D**: identical.

**C vs A** (C = B + F10 ledger/blockers; still a physical delete):

| # | Behavior | A | C (342 lines) |
|---|---|---|---|
| 1 | Env | `SUPABASE_ANON_KEY` | absent (C:38-39) |
| 2 | OPTIONS / 405 | 204 / 405 | C:124-126 200 `'ok'`; no method check |
| 3 | Rate limit | 5/3600, 429-first | C:154-164 3/300, 503-first |
| 4 | Action body | request/withdraw | ignored |
| 5 | Ledger | none | C:168-206 `account_deletions` select/upsert (`phase` gate→archived→cleaned→storage→done); ledger read error → 503; `phase==='done'` → 200 `{success:true, already_deleted:true}` |
| 6 | Blockers gate | none | C:208-233 `rpc('account_deletion_blockers',{p_user_id})`; error → **503**; rows → **409** `{error:'You have open ticket transfers, payouts, refunds or disputes…', blockers:[kinds]}` |
| 7 | Connect-id archive | none | C:235-251 `profiles.stripe_connect_id` → ledger `connect_id`; errors → 503 |
| 8 | Physical delete | none | C:253-331 `delete_account_cleanup` (500), bids + storage, `auth.admin.deleteUser` (500), ledger `done` |
| 9 | Kernel RPCs | `request_account_deletion` / `withdraw_account_deletion` | none |
| 10 | Success body | `{success, action, status, deletion_state}` | `{success:true}` / `{success:true, already_deleted:true}` |
| 11 | Sentry | RPC error + catch-all | catch-all only |

### 1.5 stripe-webhook

**A vs B**: identical. **A vs D**: see §4 (D adds the native arm; A's legacy arm is preserved in D except 5 lines).

**C vs A**:

| # | Event / area | A | C |
|---|---|---|---|
| 1 | Imports | — | C:5 `stripeFetchRaw` (one Stripe GET, see #8) |
| 2 | Signature / lease gate | A:150-244 unchanged | unchanged (`claim_stripe_webhook_event` 500/200/409, `finish`, `markProcessed`) |
| 3 | `payment_intent.succeeded` | A:261-499: claim UPDATE `payments.status='succeeded'` (`neq succeeded`, maybeSingle) → fallback path when already processed (ensure transfer row; `payment_not_found` → 200) → `mark_listing_sold` / `complete_auction_payment` RPC (unknown mode → 500) → `transfers` INSERT (23505 benign) → pushes → `markProcessed` | C:262-329: single `settle_verified_payment(... p_amount_refunded:0, p_stripe_refund_id:null, p_source:'webhook:<event.id>')`; RPC error or no row → **500** `finish(false)`; every outcome → **200** `finish(true,{outcome,payment_id,transfer_id})`; pushes only when `outcome==='settled'` and metadata has buyer/seller; `transferId` from contract |
| 4 | `payment_intent.payment_failed` | A:501-563 only `payment_failed`; predicate `.neq succeeded .neq refunded`; lookup error → **200** + `markProcessed({error})`; no row → 200 | C:331-413 also handles **`payment_intent.canceled`**; predicate `.not('status','in','("succeeded","refunded")')`; lookup error → **500** `finish(false)`; no row → 200 `finish(true,{skipped:'no_claimable_row'})`; `release_reservation` unchanged; ends with `finish(true,{path, payment_id})` |
| 5 | `charge.dispute.created` | A:566-661 upsert error → 200 with `markProcessed({error})` | C:513-516 upsert error → **500** `finish(false)`; `freeze_transfer_for_dispute` unchanged |
| 6 | `charge.dispute.closed` | A:663-703: update `disputes.status`; lookup error → 200; unknown → warn+200; `lost` → direct `payments.update({status:'refunded', refunded_at})` | C:526-669: lookup error → **500**; unknown dispute → upsert from event (payment/transfer lookups; errors → 500); `lost` → `record_payment_refund(p_stripe_refund_id:null, p_stripe_dispute_id, p_amount_cents, p_source:'dispute_lost')` (error → 500); if transfer already paid (`payout_released_at`/`stripe_transfer_id`) → `flag_payout_reversal_required(p_reason_code:'DISPUTE_LOST_AFTER_PAYOUT', p_evidence)` (error → 500) |
| 7 | `charge.refunded` | A:705-735 direct `payments.update({status:'refunded', refunded_at, stripe_refund_id?})`; error → 200 | C:671-731: if `charge.refunds` absent → Stripe GET `/charges/{id}?expand[]=refunds` (fail → 500); per refund `record_payment_refund(p_source:'expiry'|'dashboard' from `metadata.source`)`; any error → 500 |
| 8 | `transfer.created` | A:737-746 log only | C:733-780: if `metadata.attempt_id` → `record_payout_attempt_result(p_outcome:'succeeded', p_error:{source:'webhook:transfer.created'})`; `ATTEMPT_NOT_FOUND` → insert `webhook_retries` review row then 200 (insert failure → 500); other error → 500 |
| 9 | `transfer.reversed` | A:748-770 `mark_transfer_reversed` error → 200 | C:782-786 error → **500** |
| 10 | `payout.paid/failed`, `account.updated`, unknown, catch-all | A:772-902 | unchanged |

### 1.6 enforce-transfer-expiry

**A vs B**: identical. **A vs D**: identical.

**C vs A**:

| # | Area | A | C |
|---|---|---|---|
| 1 | Auth | A:139-166 `INTERNAL_CRON_SECRET` or service-role bearer, constant-time; 401 | unchanged |
| 2 | Imports | `createSellerPayout, classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry` | `executePayoutAttempt` only (C:70) |
| 3 | **Phase 0 (new)** | none | C:186-466: `get_unsettled_payments(p_limit:50)`; per row Stripe GET `/payment_intents/{id}?expand[]=latest_charge&expand[]=latest_charge.refunds` → `settle_verified_payment(p_source:'sweep')`; `legacy_unknown_mode` counted only; on `settled` retire other buyers' pending PIs (Stripe cancel + `payments.status='failed'`); `unfulfillable` → if not fully refunded and no transfer row: Stripe POST `/refunds` key `refund_unfulfillable_<payment_id>` → `record_payment_refund(p_source:'unfulfillable')` with PGRST202/42883 fallback to guarded `payments.update`; transfer exists → `webhook_retries.error_message='unfulfillable:manual_review'` + Sentry once; resolves `webhook_retries` rows; Sentry `phase0-*` captures; counts added to summary |
| 4 | Phase 1 refund idempotency | A:231 `status==='refunded' \|\| stripe_refund_id` | C:520-526 `fullyRefunded()` = `status==='refunded' \|\| amount_refunded_cents >= total`; select adds `total, amount_refunded_cents` |
| 5 | Phase 1 refund record | A:275-283 direct `payments.update({status:'refunded', refunded_at, stripe_refund_id})` | C:569-583 `record_payment_refund(p_source:'expiry', p_amount_cents)` |
| 6 | Phase 1b self-heal query | A:366-373 `.is('payments.stripe_refund_id', null)` | C:664-670 filter dropped; per-row `fullyRefunded` skip; record via `record_payment_refund` |
| 7 | Phase 2/2b money mover | A:513-711 `payReleasedTransfer → boolean`: profile + payment lookups, `payment.status!=='succeeded'` guard, final transfers recheck, `createSellerPayout`, `record_transfer_payout` (Sentry on failure), pushes | C:816-991 `payReleasedTransfer → 'paid'|'skipped'|'failed'` via `executePayoutAttempt(actor:'cron:enforce-transfer-expiry')`; `skipped` (already_released / in_progress / reconciled-empty) **no longer increments errorCount**; `not_eligible` `SELLER_NOT_ONBOARDED|PAYMENT_NOT_LIVE` → manual_review once; `reconcile_pending` with unmatched → `PAYOUT_UNMATCHED_TRANSFER` review; Sentry `paid-during-dispute`, `record-payout-failed` |
| 8 | Phase 2b sweep | A:779-827 stuck `auto_released` + stale `buyer_confirmed` | C:1051-1132 first sweeps `payout_attempts` in `claimed|requested|unknown` with `lease_expires_at < now` (join transfers, limit 20), then a)/b) with `swept` de-dup |
| 9 | Phase 3 reminders, summary | A:830-916 | unchanged + `reconciled_*` fields (C:1208-1212) |

### 1.7 `_shared` (A ≡ B ≡ D for all)

| File | C vs A |
|---|---|
| payout-logic.ts | `buildPayoutIdempotencyKey(transferId, attemptNo)` → `payout_<id>_a<n>` (was `(transferId, destination)` → `payout_<id>_<dest>_src`; throws on non-positive int); new `classifyPayoutPostFailure(status, error)` → `failed_not_created` (4xx except 409/429/idempotency_error) or `unknown` |
| payouts.ts | `createSellerPayout` now requires `attemptId, attemptNo, idempotencyKey, sourceChargeId?` + `hooks.beforeTransfer`; asserts key matches; POST via `stripeFetchRaw` (no throw) with `transfer_group` + attempt metadata; returns new variants `not_requested`, `transfer_rejected`, `transfer_unknown`; new `findTransferByAttempt` (GET `/transfers?transfer_group=&limit=100`); new `executePayoutAttempt` (RPCs `claim_payout_attempt`, `reconcile_payout_attempt`, `mark_payout_requested`, `record_payout_attempt_result`) |
| money, payout-policy, sentry, stripe | identical |

---

## 2. Production-only behavior that MUST survive convergence (in A; absent in B and C)

Verified exhaustively: because A ≡ B for confirm-payment, stripe-webhook, enforce-transfer-expiry and all `_shared`, the complete list is:

**P1 — create-payment-intent F-5 live-rail acquisition guard** (A:253-282)
* Position: after rate limit, before `req.json()`.
* Service-role client `createClient(URL, SERVICE_ROLE, {db:{schema:'kernel'}})`, `rpc('is_deletion_pending', {p_identity: buyerId})`.
* `!pendErr && pending === true` → 403 `{error:'Your account deletion request is pending. Withdraw it in Settings to make new purchases.', code:'account_deletion_pending'}` with standard headers.
* Fail-open on RPC error / throw (comment: pre-077 world; DB sweep BP wall is enforcement).
* Depends on PostgREST exposing schema `kernel` (already true in prod).

**P2 — confirm-and-release F-5 inbound-transfer guard** (A:40, A:257-295)
* `const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;` (A:40).
* Position: after `confirm_transfer_received` (step 4) and after the transfer SELECT, before the not-found check.
* Caller-JWT anon-key client (`global.headers.Authorization = req.headers.get('authorization')`, `auth:{autoRefreshToken:false, persistSession:false}`, `db:{schema:'kernel'}`), reads `identity_ext(deletion_state, deletion_requested_at)` for `identity_id = buyerId`.
* If `DELETION_PENDING` with a `deletion_requested_at`: service-client read of `transfers.created_at`; `created_at > deletion_requested_at` → 403 `{error:'Your account deletion request is pending. Withdraw it in Settings to accept new transfers.', code:'account_deletion_pending'}`.
* Fail-open on any error.

**P3 — delete-account OR-17 tombstone flow** (A whole file; items absent from both B and C)
* a. `SUPABASE_ANON_KEY` env (A:45).
* b. OPTIONS → 204 empty body (A:108-110); non-POST → 405 (A:111-113).
* c. Rate limit `delete_account` **5 per 3600 s**, fail-closed (A:89-105, 133-139).
* d. Body `{action}`: empty/invalid JSON → `'request'`; anything other than `request|withdraw` → 400 `action must be 'request' or 'withdraw'` (A:141-150).
* e. Kernel RPC via caller JWT (EA-1): anon-key client with caller `Authorization`, `db.schema='kernel'`, `rpc('request_account_deletion' | 'withdraw_account_deletion', {p_command_key: 'edge-<action>-<uuid>'})` (A:152-162).
* f. RPC error → 500 with action-specific message + `captureException('delete-account', new Error(`${fn}: ${msg}`))` (A:164-172). (RC instruction says 503 — see §3.3.)
* g. Success → 200 `{success:true, action, status:(data.status ?? 'ok'), deletion_state:'DELETION_PENDING'|'ACTIVE'}` (A:174-181).
* h. **No** physical delete: no `delete_account_cleanup`, no bids/storage deletion, no `auth.admin.deleteUser`, no request-time active-transfer 409 (A header L8-16, L33-36).

No other production-only behaviors exist (CORS, security headers, other env vars, Sentry usage and response codes are identical between A and B outside the three blocks above).

---

## 3. Exact insertion points in the DRAFT (C)

### 3.1 create-payment-intent (`/Users/josetascon/snatchit-pay/supabase/functions/create-payment-intent/index.ts`)
* **Where**: inside `serve()`'s `try`, immediately after the closing `}` of `if (rl === 'over_limit') { … }` (C:315-327) and before `const { listing_id, mode, expected_total_cents } = await req.json();` (C:329). Paste A:253-282 verbatim.
* **Ordering constraints**: (1) after auth + rate limit (uses `buyerId`, C:294); (2) before body parse and therefore before the listing fetch (C:342), the sold-in-fact check (C:396), the reservation-authority `refuse()` closure (C:406-413) and both `retirePendingIntents` calls (C:410, C:555) — the guard must produce its 403 **without** retiring PIs or touching Stripe; do not route it through `refuse()`. (3) Keep the fail-open `catch {}`. (4) Uses `createClient`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (all present in C:2, 8-9).

### 3.2 confirm-and-release (`…/confirm-and-release/index.ts`)
* **Env**: add `const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;` after C:38.
* **Guard**: insert A:257-295 verbatim between C:234 (`.single();` ending the transfer SELECT) and C:236 (`if (transferErr || !transfer) {`). This reproduces the deployed position exactly: after `confirm_transfer_received` (C:196-223), before the 404/403/409/400 gates (C:236-271), before `respond`/`payoutDeferred` (C:293-336) and before `executePayoutAttempt` (C:345). `supabase` (service client, C:141) and `buyerId` (C:139) are in scope.
* **Note**: in A the guard runs *after* the confirm RPC, so a DELETION_PENDING buyer's transfer may already be `buyer_confirmed` when the 403 is returned. Moving it before step 4 would be more correct but is a behavior change vs prod; keep parity in the RC and record the follow-up.

### 3.3 delete-account (`…/delete-account/index.ts`) — structural merge, not a paste
Target shape = A's tombstone flow + C's `account_deletion_blockers` gate (fail-closed) for `action === 'request'` only.

1. **Env**: add `const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;` after C:39. Remove `ANONYMIZED_USER_ID` (C:45, unused).
2. **Preflight/method**: replace C:124-126 with A:108-113 (204 OPTIONS; 405 non-POST).
3. **Auth**: C:130-146 or A:116-131 are interchangeable (same 401 texts). Prefer A's client options.
4. **Rate limit**: replace C:150-164 with A's production values `('delete_account', 5, 3600)` (A:94-98). Keep fail-closed 429/503.
5. **Delete C:166-206** (ledger read, `advance`, `already_deleted`) and **C:235-334** (archive, cleanup, bids/storage, deleteUser, done). None applies to a tombstone.
6. **Action parse**: insert A:141-150 right after the rate-limit block. Must come **before** the blockers gate so `withdraw` is never blocked (withdrawing restores ACTIVE; blockers are irrelevant to it).
7. **Blockers gate (from C:208-229, adapted)**: run only when `action === 'request'`, after action parse and before the kernel RPC: `service.rpc('account_deletion_blockers', {p_user_id: user.id})`; RPC error (including PGRST202 if migration 20260906120000 is not applied) → **503** `Service temporarily unavailable…` (fail-closed — never proceed on a blind read); rows → **409** `{error:'You have open ticket transfers, payouts, refunds or disputes…', blockers:[kinds]}`. Drop the `advance('gate')` ledger write (C:230-232).
8. **Kernel RPC**: insert A:152-162 (caller-JWT anon client, `kernel` schema, `p_command_key`).
9. **RPC error**: A returns 500 (A:164-172). RC rule says **503** fail-closed; either way keep the action-specific message and the `captureException`. Mobile only surfaces `body.error`, so the code change is client-safe; record the chosen code in the RC notes.
10. **Success**: A:174-181 body `{success:true, action, status, deletion_state}`.
11. **Ordering summary**: OPTIONS/405 → auth 401 → rate limit 429/503 → action parse 400 → (`request` only) blockers gate 503/409 → kernel RPC 503(500)+Sentry → 200.
12. **Preconditions** (A header L25-31): migrations 076..092 applied (true in prod) and PostgREST exposed schemas include `kernel` (true in prod); `account_deletion_blockers` requires PR #54's migration `20260906120000` — until it is applied the gate fails closed (503) and deletion requests are refused, so the migration must ship in the same release as this edge body.

---

## 4. Behavior in D NOT in A (Phase-2 edge changes never deployed) — must NOT enter the RC

All in `stripe-webhook` (D:1-1791) plus one `_shared` file; A's legacy arm is intact in D (only 5 A-lines removed: the `payment_failed` condition line, and the `account.updated synced` log block).

1. `supabase/functions/stripe-webhook/native.ts` (726 lines) and `native-dispute.ts` (828 lines) — pure decision modules imported at D:9-67.
2. Rail dispatch on `metadata.rail` for `payment_intent.succeeded` (D:752-903): `resolveRail`, `rail_mode_mismatch`/`unknown_rail` refusal, native claim/verify, `venue.finalize_primary_order` RPC via `venueService()` (D:456-465 `db.schema='venue'`).
3. `payment_intent.canceled` handled alongside `payment_failed` (D:1150) with a native branch → `venue.cancel_pending_order` (D:1214); legacy canceled → ack-only.
4. Native dispute arm on `charge.dispute.created/closed` → `kernel.record_dispute_native`, `kernel.mark_dispute_state` (D:504-611), livemode gate, status allow-list.
5. **New event branch** `charge.dispute.updated | funds_withdrawn | funds_reinstated` (D:1426-1438).
6. `transfer.reversed` native routing → `kernel.record_payout_reversal` per reversal fact, `transfer_rail_ambiguous` alert, paged reversal list read (D:667-750, 1531).
7. `account.updated` organization arm → `kernel.sync_org_connect_state` (D:1672, `selectAccountPlane`, `decideAccountUpdatedOutcome`), replacing A's simple "synced" log (A:850-858).
8. One authenticated Stripe GET to recover `instrument_fingerprint` from `latest_charge` with `CHARGE_READ_TIMEOUT_MS = 4000` (D:185-200).
9. `finishDecision` / `alertDecision` helpers and `Decision`-typed ACK/500 semantics (D:426-486).
10. Header comment `// READY TO DEPLOY` (D:1).
11. `_shared/offline-verify.ts` (536 lines; only referenced from `credential-sign/credential.ts`, not by any of the six functions).

Note: the draft C independently adds `payment_intent.canceled` handling to the legacy arm (C:331) — that is a Package-3 change, not the D native branch, and is in scope for the RC on its own merits.

---

## 5. Client-compat notes (shipped mobile build 13 + web) — what any variant must keep

Source checked in the C worktree (`app/`, `src/`, `web/src/`). Only tag present is `mobile/v1.0-build9-apple-review`; `src/lib/payments.ts` is unchanged since that tag, `ListingDetailScreen.tsx`/`CheckoutNative.tsx` drifted (+89/+46 lines) — build-13 consumer code is inferred from HEAD.

**create-payment-intent**
* Mobile reads `clientSecret, paymentIntentId, amount, buyer_fee, seller_fee, total, customerId, customerEphemeralKeySecret` (`src/lib/payments.ts:12-28`, `CheckoutNative.tsx:150, 216, 226`) and sends `expected_total_cents`. All three variants return this shape on every 200 path — keep it.
* Non-2xx: mobile surfaces `body.error` and classifies with `EXPECTED_ERROR_PATTERNS` (`payments.ts:33-44`): `/not reserved for purchase/`, `/reservation expired/`, `/already sold/`, `/already reserved/`, `/cannot purchase your own/`, `/auction.*not ended/`, `/not the winner/`. C's new 409 texts match. The F-5 403 text (`Your account deletion request is pending…`) matches **no** pattern → logged as unexpected but still displayed; `code:'account_deletion_pending'` is not read by any client yet.
* Web reads `clientSecret, amount, buyer_fee, total, error` (`web/src/lib/checkout.ts:71-77`).

**confirm-payment**
* Mobile fires and forgets; logs `fnError.message` only (`payments.ts:107-127`). C's new 403/500 paths are invisible to the user; the mobile app then calls its own follow-up RPCs (must stay idempotent after `settle_verified_payment`).
* Web reads `stripe_verified === true` (`web/src/lib/checkout.ts:127-134`); on `error` or `false` it falls back to a `payments.status='succeeded'` lookup, then calls `mark_listing_sold`/`complete_auction_payment` (`checkout.ts:152-160`) — these must no-op cleanly once the contract already settled. Additive `outcome`/`transfer_id` fields are safe.

**confirm-and-release**
* Mobile treats any 2xx as "confirmed" regardless of body (`ListingDetailScreen.tsx:838-843`); on non-2xx shows `body.error` (`:821-836`). So every post-confirmation state must stay 2xx (`pending_review`, `processing`, `already_released`) — C honors this. The F-5 403 is shown as `body.error`.
* Web reads `already_released`, `payout_status`, `warning`, `error` (`web/src/lib/transfers.ts:266-296`); only `payout_status === 'pending_review'` produces a message; C's `'processing'` is silently OK (no warning). A's dropped `warning:'Payout sent but record update failed'` body was only echoed as `warning`.

**delete-account**
* Mobile POSTs `body: {}` (`app/settings/index.tsx:143`), treats a non-error 2xx without a `body.error` field as success and signs out (`:159-166`); on non-2xx shows `body.error` (`:145-156`). Requirements: empty body ⇒ `request`; 200 body must not contain `error`; `success:true` retained; 409 `blockers`/403/503 bodies must carry `error` text. No web consumer of delete-account was found.

**stripe-webhook / enforce-transfer-expiry**: no client consumers; contract is with Stripe (2xx vs non-2xx retry semantics) and pg_cron (`INTERNAL_CRON_SECRET` / service-role bearer). C converts several formerly-ACKed DB failures into 500s (webhook #4-#9 above) — intentional, no client impact.
