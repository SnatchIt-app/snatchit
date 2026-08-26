# SnatchIt — Stripe Integration Audit Report

**Date:** March 3, 2026
**Auditor:** Principal Software Engineer (Production-Grade Review)
**Scope:** Full Stripe payment flow — frontend, edge functions, database, auth, security

---

## 1. ARCHITECTURE SUMMARY

### Payment Flow (Step-by-Step)

**Buy Now Flow:**

1. User navigates to `CheckoutScreen` (`app/checkout/[id].tsx`) with params: `listingId`, `mode=buy_now`, `bidAmount`, `total` (all passed from the previous screen as URL search params).
2. `useAuth()` hydrates the Supabase session from AsyncStorage.
3. Once `user.id` is available, `setupPayment()` fires: it calls `createPaymentIntent()` in `src/lib/payments.ts`.
4. `createPaymentIntent()` fetches the current JWT via `supabase.auth.getSession()`, then POSTs to the `create-payment-intent` Supabase Edge Function with `listing_id`, `buyer_id`, `mode`, plus `Authorization: Bearer <JWT>` and `apikey` headers.
5. The Edge Function (`supabase/functions/create-payment-intent/index.ts`) reads the request body, fetches the listing from the DB using the **service role key** (bypassing RLS), validates listing state (`status === 'reserved'` for buy_now), computes `amount` from `listing.buy_now_price`, calculates `serviceFee = amount * 0.05`, `total = amount + serviceFee`, then calls the Stripe API to create a PaymentIntent.
6. The Edge Function inserts a `payments` row with status `'pending'` and returns `{ clientSecret, paymentIntentId, amount, serviceFee, total }` to the client.
7. The client calls `initPaymentSheet()` with the `clientSecret`, then sets `paymentReady = true`.
8. User taps "Pay" → `presentPaymentSheet()` opens Stripe's native UI.
9. On success, `confirmPaymentSuccess(paymentIntentId)` is called (best-effort — does not throw). This POSTs to the `confirm-payment` Edge Function, which verifies with Stripe that the PaymentIntent status is `'succeeded'`, then updates the `payments` row to `status = 'succeeded'`.
10. Then `supabase.rpc('mark_listing_sold', { p_listing_id, p_user_id })` is called. This PL/pgSQL function locks the listing row with `FOR UPDATE`, validates `status = 'reserved'` and `reserved_by = user`, checks reservation hasn't expired, then sets `status = 'sold'`.
11. On unmount without confirmation (back button), `release_reservation` RPC fires to return the listing to `'active'`.

**Auction Flow:**

Same as above except: the Edge Function validates `auction_status === 'ended'` and `winner_user_id === buyer_id`, uses `winning_bid_amount` (or `current_bid` fallback) for the amount, and after payment, `complete_auction_payment` RPC is called instead of `mark_listing_sold`.

### Key Components

| Layer | File | Role |
|-------|------|------|
| Config | `src/config/app.ts` | Stripe publishable key, `SERVICE_FEE_RATE` |
| Provider | `app/_layout.tsx` | `<StripeProvider>` wraps entire app |
| Client lib | `src/lib/payments.ts` | `createPaymentIntent()`, `confirmPaymentSuccess()` |
| Checkout UI | `app/checkout/[id].tsx` | Full checkout screen with PaymentSheet |
| Edge Fn | `supabase/functions/create-payment-intent/index.ts` | Creates Stripe PaymentIntent, inserts payment row |
| Edge Fn | `supabase/functions/confirm-payment/index.ts` | Verifies with Stripe, updates payment status |
| DB | `supabase/schema.sql` (payments table) | Payment record storage with RLS |
| DB RPCs | `mark_listing_sold`, `complete_auction_payment` | Atomic listing state transitions |

---

## 2. SECURITY ANALYSIS

### 2.1 Authentication Risks

**CRITICAL — Edge Function Does Not Verify JWT Identity**

The `create-payment-intent` Edge Function receives `buyer_id` from the request body but **never verifies** that the JWT bearer token belongs to that `buyer_id`. The function creates a Supabase client with the **service role key** (line 33), completely bypassing RLS, and trusts the client-supplied `buyer_id` without validation.

An attacker with a valid JWT for User A could pass `buyer_id: <User B's UUID>` and create a PaymentIntent attributed to User B. While this wouldn't directly charge User B (Stripe charges the card presented in the PaymentSheet), it creates a fraudulent `payments` record and could be used in social engineering or dispute attacks.

**The `confirm-payment` Edge Function has no auth check at all.** It accepts `payment_intent_id` in the body and updates the payment record. While it does verify with Stripe that the payment succeeded, anyone who knows a `payment_intent_id` can trigger the status update. The JWT `Authorization` header is sent by the client but never read or validated by the function.

**Severity: HIGH** — Both edge functions effectively treat auth as decorative. The JWT is passed but never decoded or validated against the request payload.

### 2.2 Authorization Risks

**CRITICAL — No Server-Side Buyer Identity Verification**

Because `buyer_id` comes from the client body and the service role key bypasses RLS, there is no server-side enforcement that the authenticated user is the one making the purchase. The Edge Function should decode the JWT, extract `sub` (user ID), and use that as the `buyer_id` — ignoring the client-supplied value entirely.

**MEDIUM — No check that buyer ≠ seller**

The `create-payment-intent` function does not verify that `buyer_id !== listing.seller_id`. A seller could buy their own listing, which could be used for money laundering or to inflate metrics.

### 2.3 Secret Leakage Risks

**CRITICAL — Stripe Key in `app.ts` is Malformed and Contains Mixed Test/Live Fragments**

```
STRIPE_PUBLISHABLE_KEY: 'pk_tepk_test_51T6Fb1...pk_live_51T6Far...mk_1T6Fb2..._REPLACE_ME...'
```

This string contains what appears to be concatenated fragments of test keys, live keys, and a merchant key with a `_REPLACE_ME` suffix. While the `TODO` comment says to replace it, the presence of what looks like **partial live key material** (`pk_live_51T6Far...`) in source code is a serious concern. If this file is committed to version control, live key fragments are exposed in git history.

**HIGH — `stripe_client_secret` Stored in Database**

The `payments` table stores `stripe_client_secret` (line 946 of schema.sql, line 131 of create-payment-intent). The `client_secret` is only needed transiently for the PaymentSheet initialization. Storing it in the database creates unnecessary exposure — anyone with DB read access (admin, compromised service role key, SQL injection elsewhere) can retrieve secrets that could be used to confirm payments outside the app flow.

**MEDIUM — `client_secret` Returned Over the Wire**

The Edge Function returns `clientSecret` in the JSON response body. This is standard Stripe practice for client-side confirmation, but combined with no JWT validation, any authenticated user can obtain another user's payment intent secret.

**LOW — Console Logging of Auth Headers**

`payments.ts` lines 29-34 and 81-86 log `hasAuth`, `tokenLength`, `hasApiKey`, and `url` to the console. While this doesn't log the actual token, in production builds of React Native, `console.log` output may appear in device logs (e.g., `adb logcat` on Android), exposing metadata about auth state.

**LOW — `.env` in Repository Root**

The `.env` file contains Supabase URL and anon key. While anon keys are designed to be public, storing them in `.env` without `.gitignore` protection risks accidental exposure of future secrets added to this file.

### 2.4 Payment Tampering Risks

**GOOD — Amount is Server-Authoritative**

The Edge Function calculates the amount from the listing's database record (`buy_now_price` or `winning_bid_amount`), not from client-supplied values. The client sends `bidAmount` and `total` as URL params only for display purposes. The actual charge amount is determined server-side. This is correct.

**MEDIUM — Display Amount vs. Actual Amount Mismatch Possible**

The client displays `bidAmount` and `total` from URL params (passed by the previous screen), but the Edge Function may calculate a different total (e.g., if the listing price changed between screen navigation and PaymentIntent creation). The user could see "$100" on screen but be charged a different amount by Stripe. The PaymentSheet itself shows the correct Stripe amount, so this is somewhat mitigated.

### 2.5 Replay / Duplicate Charge Risks

**CRITICAL — No Idempotency Keys on Stripe PaymentIntent Creation**

The `create-payment-intent` Edge Function does not pass an `Idempotency-Key` header to the Stripe API call (lines 92-107). If a network retry, double-tap, or React re-render causes `createPaymentIntent()` to fire twice, two separate PaymentIntents (and two `payments` rows) are created for the same listing. The Stripe `automatic_payment_methods` flow would then allow the user to be charged twice.

**HIGH — No Duplicate Payment Prevention Per Listing**

There is no unique constraint on `(listing_id, buyer_id, mode)` in the `payments` table and no check in the Edge Function for an existing pending payment for the same listing. A rapidly tapping user or a network-triggered retry could create multiple PaymentIntents.

**MEDIUM — `useEffect` Dependency Array Could Trigger Double Setup**

The checkout screen's `setupPayment()` runs in a `useEffect` with deps `[user?.id, authLoading, listingId]`. If auth hydrates, then the session refreshes (causing `user.id` to briefly change reference), this could fire twice. The `paymentLoading` state guards the UI but doesn't prevent duplicate API calls.

---

## 3. CORRECTNESS RISKS

### 3.1 Race Conditions

**HIGH — Payment Succeeded but `mark_listing_sold` Fails**

After `presentPaymentSheet()` succeeds (Stripe has charged the card), the code calls `confirmPaymentSuccess()` (best-effort, non-throwing) and then `mark_listing_sold` RPC. If the RPC fails (network error, reservation expired between payment and RPC call, concurrent DB issue), the user is charged but the listing is not marked sold. The error message says "contact support" but there is no automated reconciliation mechanism.

**HIGH — Reservation Expiry During Payment**

The reservation window is 10 minutes. If the user takes 9 minutes to enter card details in the PaymentSheet, the reservation could expire between `presentPaymentSheet()` returning success and `mark_listing_sold` executing. The RPC would then fail with "Your reservation has expired" and reset the listing to `'active'`, allowing another buyer to purchase it — while the first buyer has already been charged.

**MEDIUM — No Transaction Wrapping Between Payment and Listing Update**

Steps 9-10 (confirm payment → mark listing sold) are two separate operations. There's no saga pattern or compensating transaction. If the app crashes between these steps, the payment is collected but the listing remains unsold.

**MEDIUM — `confirm-payment` Edge Function Is Optional**

`confirmPaymentSuccess()` is documented as "best-effort bookkeeping" and doesn't throw on failure. This means the `payments` row could remain in `'pending'` status indefinitely even after a successful Stripe charge. Without webhooks, there's no reconciliation path.

### 3.2 Amount Mismatches

**LOW — Dollar vs. Cent Ambiguity**

The `amount` field in the `payments` table and types is documented as "in cents," and the DB has `check (amount > 0)`. However, the `buy_now_price` on listings — where does it come from? If listing prices are stored in dollars and the Edge Function passes them directly to Stripe (which expects cents), charges would be 100x too low. Conversely, if prices are already in cents and the checkout screen displays `fmt$(bidAmount)` treating them as dollars, the displayed price would be 100x too high.

The Edge Function computes `total = amount + serviceFee` and passes `total` to Stripe as the `amount` param. If listing prices are in cents (as the schema comments suggest), this is correct. But `fmt$()` in the checkout screen does `Math.round(n)` on the URL param, which may misrepresent cents as dollars.

### 3.3 Listing State Inconsistencies

**GOOD — PL/pgSQL RPCs Use `FOR UPDATE` Locking**

Both `mark_listing_sold` and `complete_auction_payment` acquire row-level locks, preventing concurrent state mutations. This is properly implemented.

**GOOD — Idempotent on Already-Sold**

Both RPCs return silently if the listing is already `'sold'`, preventing errors on retry.

### 3.4 Edge Function Reliability

**MEDIUM — No Retry Logic for Stripe API Calls**

If the Stripe API returns a transient error (network timeout, 500), the Edge Function returns 500 to the client. The client has no retry mechanism.

**MEDIUM — DB Insert Failure Swallowed**

In `create-payment-intent`, if the `payments` insert fails (line 135-138), the function logs the error but still returns success to the client. This means a PaymentIntent exists in Stripe with no corresponding DB record, making reconciliation difficult.

---

## 4. PRODUCTION READINESS SCORE: 28 / 100

**Reasoning:**

| Category | Score | Max | Notes |
|----------|-------|-----|-------|
| Auth / Identity Verification | 2 | 20 | JWT passed but never validated in edge functions |
| Payment Integrity | 8 | 20 | Server-side amounts are good, but no idempotency, no duplicate prevention |
| Webhook / Reconciliation | 0 | 15 | No webhooks at all — single point of failure |
| Error Recovery | 3 | 15 | "Contact support" on critical failures, no automated recovery |
| Secret Management | 5 | 10 | Mixed test/live key in source, client_secret stored in DB |
| PCI Compliance | 7 | 10 | Uses Stripe PaymentSheet (good), but logging concerns |
| Observability | 2 | 5 | Console.log only, no structured logging or alerting |
| Env Separation | 1 | 5 | Hardcoded key with test/live mixed, no env-based switching |

---

## 5. HIGH PRIORITY FIXES (Ranked)

### H1. Validate JWT and Extract User Identity Server-Side

**Both edge functions must decode the JWT** from the `Authorization` header and use the `sub` claim as the authenticated user ID. Never trust `buyer_id` from the request body.

```
// Pseudocode for create-payment-intent
const jwt = req.headers.get('Authorization')?.replace('Bearer ', '');
const { data: { user }, error } = await supabaseClient.auth.getUser(jwt);
if (error || !user) return 401;
const buyer_id = user.id; // Use this, ignore request body buyer_id
```

### H2. Implement Stripe Webhooks for Payment Confirmation

Replace client-side `confirmPaymentSuccess()` with a Stripe webhook handler (`payment_intent.succeeded`). The webhook should update the `payments` table AND call the `mark_listing_sold` / `complete_auction_payment` RPC. This is the only reliable way to know a payment succeeded.

### H3. Add Idempotency Keys to Stripe PaymentIntent Creation

Generate a deterministic idempotency key based on `listing_id + buyer_id + mode` and pass it as the `Idempotency-Key` header to Stripe. Also add a unique constraint or "check for existing pending payment" query before creating a new one.

### H4. Fix the Stripe Publishable Key Configuration

Remove the malformed key from source code immediately. Use environment variables (`EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY`) with separate `.env.development` and `.env.production` files. Ensure no live key material exists in git history.

### H5. Handle Payment-Succeeded-but-Listing-Update-Failed Atomically

If `mark_listing_sold` fails after payment, the system must either (a) automatically refund via Stripe, or (b) queue a retry. Currently the user is charged with no recourse except manually contacting support. With webhooks (H2), this becomes the webhook's responsibility and can be retried reliably.

### H6. Remove `stripe_client_secret` from Database Storage

The client secret is only needed transiently. Don't persist it. Remove the column from the `payments` table.

---

## 6. MEDIUM PRIORITY FIXES

### M1. Add Buyer ≠ Seller Validation

In `create-payment-intent`, check that `buyer_id !== listing.seller_id` and reject with 403.

### M2. Prevent Duplicate PaymentIntents Per Listing

Before creating a new PaymentIntent, query the `payments` table for existing `pending` or `processing` payments for the same `listing_id + buyer_id`. Return the existing `client_secret` instead of creating a new one.

### M3. Extend Reservation Window or Validate Before Stripe Charge

Either extend the reservation when a PaymentIntent is created, or validate reservation status immediately before charging (not possible with PaymentSheet — reinforces the need for webhooks).

### M4. Add Retry Logic for Stripe API Calls

Wrap Stripe API calls in a retry with exponential backoff for transient failures (429, 500, 502, 503).

### M5. Don't Swallow DB Insert Failures

If the `payments` insert fails in `create-payment-intent`, cancel the Stripe PaymentIntent before returning an error. An orphaned PaymentIntent without a DB record is a reconciliation nightmare.

### M6. Add CORS Origin Restrictions

Both edge functions return `Access-Control-Allow-Origin: *`. In production, restrict this to your app's domain/scheme.

### M7. Validate `payment_intent_id` Format in `confirm-payment`

The `confirm-payment` function passes user input directly into a Stripe API URL. Validate that it matches the `pi_` prefix pattern to prevent SSRF-adjacent issues.

---

## 7. LOW PRIORITY IMPROVEMENTS

### L1. Remove Console Logging of Auth Metadata

Strip `console.log` statements from `payments.ts` in production builds, or use a proper logging library with log levels.

### L2. Add Structured Logging in Edge Functions

Replace `console.error` with structured JSON logging including `listing_id`, `buyer_id`, `payment_intent_id`, and timestamps for audit trail.

### L3. Add `returnURL` to `initPaymentSheet`

The Stripe SDK warns about missing `returnURL` for iOS redirect-based payment methods. Add it for broader payment method support.

### L4. Track Payment Method More Accurately in `confirm-payment`

Line 55 uses `payment_method_types?.[0]` which gives the type (e.g., `'card'`), not the specific method. Consider storing the actual `payment_method` ID for dispute resolution.

### L5. Add Payment Amount Verification on Confirmation

In `confirm-payment`, after fetching the PaymentIntent from Stripe, verify that `stripeData.amount` matches the `payments` table `total`. This catches any theoretical tampering.

### L6. Add Rate Limiting to Edge Functions

Protect against abuse by rate-limiting PaymentIntent creation per user (e.g., max 3 pending intents per user per hour).

---

## 8. WHAT WOULD BREAK AT SCALE?

### 10,000 Users

- **Orphaned PaymentIntents accumulate.** Without webhooks, failed confirmations leave Stripe PaymentIntents in `requires_capture` or `succeeded` state with no corresponding DB update. At 10k users, manual reconciliation becomes impossible.
- **Console logging becomes noise.** No structured logging means debugging payment issues requires reading raw device logs.
- **Support burden from "Payment Received but listing update failed" alerts.** Even at a 1% failure rate, that's 100+ support tickets requiring manual intervention.

### 100,000 Users

- **Duplicate PaymentIntents per listing** become statistically certain. Multiple users hitting "Pay" simultaneously on popular listings create multiple charges for the same item.
- **Reservation window (10 minutes)** causes bottlenecks on hot listings. One user can block everyone else for 10 minutes, and if they abandon, the listing was effectively unavailable.
- **Supabase Edge Function cold starts** add latency to payment creation. Under load, users see extended "Setting up payment..." spinners.
- **The `payments` table lacks archival strategy.** Indexes on `listing_id`, `buyer_id`, `seller_id`, and `status` help, but without partitioning, query performance degrades.

### Payment Spikes (Flash Sales, Viral Events)

- **Stripe rate limits** (25 requests/second on test, higher on live but still finite) could be hit without retry logic or queuing.
- **Multiple PaymentIntents per listing** multiply the spike. If 1000 users try to buy the same listing, 1000 PaymentIntents are created (only 1 should exist).
- **`FOR UPDATE` row locks** on the listings table serialize `mark_listing_sold` calls, creating a bottleneck but preventing corruption. This is correct but slow under contention.

### Concurrency Edge Cases

- **User opens checkout on two devices simultaneously** → two PaymentIntents, potential double charge.
- **User's session expires mid-payment** → `confirmPaymentSuccess()` silently fails (no session), payment is charged but DB never updated.
- **Network disconnect after `presentPaymentSheet()` succeeds** → Stripe charges the card, but `confirmPaymentSuccess()` and `mark_listing_sold` never fire. Without webhooks, this payment is lost.

---

## 9. WHAT IS MISSING FOR A REAL MONEY LAUNCH?

1. **Stripe Webhooks** — The single most critical missing piece. Without `payment_intent.succeeded`, `payment_intent.payment_failed`, and `charge.dispute.created` webhooks, the system has no reliable payment confirmation path.

2. **Stripe Connect for Seller Payouts** — There is no mechanism to pay sellers. The system collects money from buyers but has no Stripe Connect integration, no connected accounts, no transfer/payout logic. Sellers see a `wallet_balance` field in their profile but it's never updated by the payment flow.

3. **Refund Flow** — The `payments` table has a `refunded` status and `refunded_at` timestamp, but there is no refund API endpoint, no admin interface, and no automated refund on failure scenarios.

4. **Dispute/Chargeback Handling** — No webhook for `charge.dispute.created`. No evidence submission flow. No automatic listing status reversion on successful disputes.

5. **Receipt/Confirmation Emails** — No email sent to buyer or seller after payment. Stripe can send automatic receipts if configured, but there's no evidence of this setup.

6. **Proper Environment Configuration** — Need separate Stripe accounts or API key sets for development, staging, and production. The current hardcoded key approach is untenable.

7. **Payment Intent Expiration Cleanup** — Stripe PaymentIntents expire after 24 hours by default. Need a cron job or scheduled function to clean up `pending` payment rows where the intent has expired.

8. **Amount Validation in Currency Display** — Need to verify whether listing amounts are stored in cents or dollars throughout the entire flow, with explicit conversion functions and unit tests.

9. **3D Secure / SCA Compliance** — While `automatic_payment_methods` handles SCA for most cases, there's no testing evidence or handling for 3DS challenge flows. European transactions require SCA.

10. **Terms of Service / Refund Policy** — Legal requirements for processing payments including buyer/seller agreements, refund policy disclosure at checkout, and marketplace terms.

11. **PCI SAQ-A Compliance Documentation** — While using Stripe PaymentSheet (which handles PCI scope), the marketplace still needs to complete Stripe's PCI compliance questionnaire.

12. **Fraud Detection** — No Stripe Radar rules configured (metadata is passed which helps), no velocity checks, no device fingerprinting.

---

## 10. FINAL VERDICT

### Can this safely process real payments?

**No. Absolutely not in its current state.**

### What must be fixed before enabling live Stripe keys?

**Non-negotiable (must fix):**

1. **JWT validation in both edge functions** — The fact that edge functions don't verify caller identity is a fundamental security flaw. Any authenticated user can create payment intents attributed to any other user.

2. **Stripe webhooks** — Client-side payment confirmation as the sole path is architecturally unsound. Network failures, app crashes, and race conditions all lead to money collected with no DB record. This is lawsuit territory.

3. **Idempotency keys** — Without them, duplicate charges are inevitable at any meaningful scale.

4. **Stripe publishable key management** — Remove the hardcoded key (especially the live key fragment) from source code. Use environment variables with proper separation.

5. **Seller payout mechanism** — Collecting buyer payments without a way to pay sellers is not a viable marketplace.

6. **Refund capability** — Legally required for any payment processor agreement.

**Strongly recommended before launch:**

7. Duplicate payment prevention per listing
8. Automated recovery for payment-succeeded-but-update-failed scenarios
9. Proper error monitoring and alerting (not console.log)
10. Receipt/confirmation emails
11. Reservation window management tied to payment flow

### Bottom Line

The code demonstrates a solid understanding of the Stripe PaymentSheet pattern and good database-level safety (row locking, idempotent RPCs, RLS on the payments table). However, the **edge functions are essentially unauthenticated**, there are **no webhooks** for reliable payment confirmation, and there is **no idempotency protection** against duplicate charges. These three issues alone make this unsuitable for processing real money. The fix list is well-defined and achievable, but each item is critical — not optional.
