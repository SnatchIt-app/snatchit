# RCA — App Review build 9 rejection (2026-07-29): checkout "Payment Failed"

## Root cause (confirmed, not inferred)

**Stripe live/test mode mismatch between client and server.**

- The shipped app (build 9, EAS `production` profile) uses the **live** publishable key
  (`pk_live_51T6FarGdOzCmGbHw…`, eas.json).
- The Supabase edge functions create PaymentIntents with `STRIPE_SECRET_KEY`, whose secret
  was **last set 2026-03-19** and is a **test-mode** key.
- PaymentSheet initializes, but the moment "Pay" is tapped the Stripe SDK (live key) cannot
  confirm the test-mode PaymentIntent. Apple's screenshot shows the exact alert:

  > Payment Failed — "No such payment_intent: 'pi_3TydVNGdOzCmGbHw1MXLjBK2'; a similar
  > object exists in test mode, but a live mode key was used to make this request."

  That PI id matches row `751eca0f…` in `payments` (Quavo, created 2026-07-29 19:51:05 UTC).

## Evidence chain

1. Reviewer signed in 2026-07-29 19:46:59 UTC (auth.sessions) on iPad Air 11" (M3).
2. Three PaymentIntents created — one per hero listing — 19:48:03 (III Points $330),
   19:49:01 (Mochakk $247.50), 19:51:05 (Quavo $275). All stuck `pending`
   (`requires_payment_method`); zero webhook events since Jul 29 → no confirm ever reached Stripe.
3. Apple's 4 attached screenshots (12:51:00–:10 PDT): home feed OK → listing detail OK →
   Checkout screen with "Pay · $275 total" **ready state (initPaymentSheet succeeded)** →
   "Payment Failed" alert on tapping Pay.
4. `supabase secrets list`: `STRIPE_SECRET_KEY` updated **2026-03-19** (dev era);
   `STRIPE_WEBHOOK_SECRET` updated 2026-03-27 (test-mode endpoint).
5. All 35 historical `succeeded` payments (latest 2026-07-04) were made by dev/preview
   builds carrying `pk_test` — test client + test server = worked. A live-pk production
   build had **never completed checkout**; Apple's Jul 29 attempt was the first ever.

## Why previous testing missed it
Every end-to-end purchase in beta used dev/preview builds (pk_test). Build 7's review never
reached checkout (expired listings). Pre-build checks for build 9 were static (grep-level);
no live-key purchase was ever executed.

## Scope
- Affects **all users, all devices, both payment methods** on any production (pk_live) build.
- Not iPad-specific. Not review-account-specific. Not Apple Pay-specific — Issue 2
  (PassKit/Apple Pay "not verifiable") is a downstream consequence: the reviewer never got a
  working PaymentSheet, where Apple Pay lives.
- iPad rendering: compatibility mode works; one cosmetic wart (listing-detail sticky bar
  wraps "CURRENT BID $198 total" into a narrow column — see Screenshot-0729-125103). Not a blocker.

## Fix (server config only — NO code change, NO new binary)

Only the founder can perform steps 1 and 3 (they involve the Stripe secret key):

1. Stripe Dashboard (live mode) → Developers → API keys → reveal the **live secret key**.
2. Set it as the edge-function secret (functions hot-reload on secret change):
   `supabase secrets set STRIPE_SECRET_KEY=sk_live_… --project-ref hqycwntpfoztoinemqns`
3. Stripe Dashboard (live mode) → Developers → Webhooks → Add endpoint
   `https://hqycwntpfoztoinemqns.supabase.co/functions/v1/stripe-webhook`
   with the same event set as the existing test-mode endpoint
   (payment_intent.succeeded, payment_intent.payment_failed, charge.refunded,
   charge.dispute.*, account.updated — mirror the test endpoint's list), then:
   `supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_… --project-ref hqycwntpfoztoinemqns`
4. Verify: complete one real checkout on a production build (low-value listing), confirm
   payment succeeds, webhook row lands in `stripe_webhook_events`, transfer row created;
   then refund via Stripe Dashboard.

## Live-mode follow-ups (post-swap reality)
- `profiles.stripe_customer_id` values are test-mode customers — `create-payment-intent`
  already self-heals (probes the customer, recreates if missing). No action.
- `profiles.stripe_connect_id` values are **test-mode Connect accounts** — payouts to them
  will fail in live mode. Sellers (including any real early sellers) must re-onboard through
  Stripe Connect in live mode before their first live payout. Demo seller payouts are
  disabled — irrelevant for review.
- PaymentIntent creation has no Connect references (plain platform charge + metadata), so
  checkout works in live mode regardless of seller account state.
- Apple Pay live-mode processing certificate for `merchant.com.snatchit` was configured per
  LAUNCH_PLAN §B — verify it shows in Stripe Dashboard (live) → Payment methods → Apple Pay.

## Risk note for next review
The reviewer TAPPED Pay this time. With checkout fixed they may complete a REAL charge
($330 on III Points). Consider lowering the three hero-listing prices (and syncing the
review notes' dollar references) before resubmitting, or accept + refund.
