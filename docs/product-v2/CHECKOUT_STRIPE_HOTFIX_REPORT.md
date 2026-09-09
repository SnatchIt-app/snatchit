# Checkout Stripe payment-sheet hotfix

**Session:** Front End · **Date:** 2026-09-04 · **Severity:** P1 (blocks ticket purchase)
**Technical checkpoint: YES** · **Physical iPhone verification: BUILD VERIFIED (2026-09-04)** ·
**Owner approval: PENDING (rapid-tap case not separately confirmed)**

> Update 2026-09-04: the owner reached a working checkout on a build containing this latch ("stripe
> sheet loads now, checkout works") after a second, unrelated defect was fixed — a smart-quoted
> publishable key in `.env` (see STRIPE_NETWORK_TIMEOUT_REPORT.md). The sheet now presents, so the
> latch is exercised on the happy path and no duplicate-presentation red screen occurred. The explicit
> rapid-tap test remains unconfirmed in the owner's own words.
Committed as a technical checkpoint so it can be integrated without depending on an uncommitted
worktree. No push, no PR, no deploy.

> **Why the device still showed the old behaviour.** Process evidence taken 2026-09-04: port 8081 was
> held by `expo start --dev-client --lan` running from `/Users/josetascon/snatchit-fe-home` (the Home
> worktree), and port 8082 by a second server from the same worktree. Both served **Home**, which does
> not contain this fix. Metro serves whatever code lives in *its* worktree, independent of git state, so
> a build taken from those ports could never include the latch. Owner checkout testing must be done from
> the integration worktree (see FRONTEND_V2_FINAL_INTEGRATION_REPORT.md).

## 1. Branch
`frontend/checkout-stripe-hotfix`

## 2. Base SHA
`085e2984cc89b1bf03cdf11c93f0ba182c3f17a4` (Phase 12, owner-approved).

## 3. Exact reproduced error
On a physical iPhone, tapping Pay in checkout produced the RN red screen:
`StripeSdk.presentPaymentSheet(): Tried to resolve a promise more than once.` — the Stripe payment
sheet failed to load.

## 4. Root cause
Both pay handlers guarded re-entry with **React state only** (`setConfirming(true)`), which does not
update before a second tap's event handler runs in the same frame. The handler entry checked
`!paymentReady || !user` but never `confirming`, and the Pay button's `disabled` is state-driven
(async). So a rapid double-tap (or two touch events in one frame) entered the handler twice and called
`presentPaymentSheet()` twice. The Stripe native module keeps a single stored promise for the
presentation; the second call makes it resolve/reject that promise again → "Tried to resolve a promise
more than once." It is a UI concurrency defect, not a Stripe-config or key defect.

## 5. Exact call path before fix
`Button onPress → payOnPress → payHandler` (`handleConfirmPurchase` for Buy Now, `handleAuctionPayment`
for an auction win) `→ if (!paymentReady || !user) return; setConfirming(true); → await presentPaymentSheet()`.
Second synchronous tap re-enters the same handler before the first `await` yields → second
`presentPaymentSheet()`.

## 6. Number of presentPaymentSheet call sites
**2**, both in `src/screens/checkout/CheckoutNative.tsx`: `handleConfirmPurchase` (Buy Now) and
`handleAuctionPayment` (auction winner). They are mutually exclusive by `mode`, so only one is wired to
the Pay button per checkout; each was independently vulnerable to double-tap.

## 7. Duplicate invocation mechanism
Double-tap / same-frame re-entry (failure class #1 and #2 from the brief). Not an effect re-entry (#4 —
presentation is never called from render or an effect), not a duplicate handler (#3 — one `payOnPress`),
not a retry collision (#6 — retry only re-runs `setupPayment`/init, never present). The auto-present
effect classes were ruled out by inspection: `presentPaymentSheet` appears only inside the two async
handlers, never in a `useEffect` or during render.

## 8. Fix
Added a synchronous single-flight latch, `src/lib/checkout/paymentGuard.ts` (`createSingleFlight()`:
`begin()` returns true once and flips an in-memory boolean synchronously; re-entrant callers get false
until `end()`). `CheckoutNative` holds one in a ref (`payLatchRef`) and each handler now does
`if (!payLatchRef.current.begin()) return;` as the first synchronous step, releasing with
`payLatchRef.current.end()` in `finally`. No visual, pricing, init, or architecture change.

## 9. Why the fix prevents promise double-resolution
`begin()` sets the latch **synchronously**, before any `await`, so a second tap in the same frame hits
`begin() === false` and returns without calling `presentPaymentSheet()` a second time — exactly one
presentation per attempt, so the native promise is resolved once. React state is no longer relied on as
the lock. The latch is released in `finally`, which runs on every exit (success, `Canceled` early
return, payment error, or thrown error), so a cancel or failure cleanly permits a retry and checkout is
never permanently locked.

## 10. Publishable-key runtime verification
- `.env` defines `EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY` with a `pk_` prefix (value not printed).
- The iOS bundle contains a `pk_` publishable key and **zero `sk_` secret keys** (grepped by prefix,
  count only — no value shown).
- `NativeAppShell.native.tsx` passes it through: `StripeProvider publishableKey={APP_CONFIG.STRIPE_PUBLISHABLE_KEY}`
  where `STRIPE_PUBLISHABLE_KEY = process.env.EXPO_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? ''`. An empty value
  logs a developer-visible config error (not a throw) and checkout surfaces a clean payment error rather
  than presenting with an invalid setup. The reported crash was NOT a missing-key case (key is present).
- No key printed, none committed, no `sk_` secret used client-side.

## 11. Files changed
- `src/screens/checkout/CheckoutNative.tsx` — latch ref + guard at both handlers, release in `finally`,
  import of the helper. No other logic touched.
- `src/lib/checkout/paymentGuard.ts` — new pure single-flight helper.
- `tests/payment-guard.test.ts` — new behavioral + source-guard tests.
- `docs/product-v2/CHECKOUT_STRIPE_HOTFIX_REPORT.md` — this report.

## 12. Core-owned files changed
**None.** `src/lib/payments.ts`, `money.ts`, `supabase.ts`, `supabase/**`, `packages/**`, `scripts/**`,
`.github/workflows/**`, `app.json`, `eas.json` — untouched. `payments.ts` is imported, not modified.

## 13. Payment architecture changed
No. PaymentIntent creation, `initPaymentSheet`, client secret handling, Apple Pay probe, success RPCs
(`mark_listing_sold`, `complete_auction_payment`, `ensure_transfer_exists`), and error handling are
unchanged. `confirmedRef` still guards post-payment; the fix adds an orthogonal presentation latch.

## 14. Pricing / money logic changed
No. Fees, all-in pricing, cents/dollars contract, PaymentIntent amount, currency, seller payout, and the
server-authoritative `serverBreakdown` are untouched.

## 15. Tests added
`tests/payment-guard.test.ts` (7): latch acquire-once/blocks-re-entry/release; **three rapid Pay
invocations present exactly once**; release-then-retry presents again; cancel/error path still releases
(no permanent lock); plus shipped-source guards (both handlers acquire the synchronous latch before
presenting, release in `finally`, present is never called from an effect/render, publishable key flows
through `StripeProvider`, no `sk_` client-side).

## 16. Full verification
- Tests: **602 passed / 25 files** (was 595; +7). No existing checkout/webhook test weakened.
- Typecheck: `tsc --noEmit` clean (exit 0).
- Lint: `expo lint` 27 problems, **0 errors, 27 warnings** — no new warnings.
- Native iOS bundle: **HTTP 200, ~14.6 MB**, contains the latch, no unresolved-import/error banner.

## 17. Physical-device status
**Not verified on device (owner re-test pending).** Verified at checkpoint from THIS worktree on an
isolated metro (port 8083): iOS bundle HTTP 200 and the latch present in the bundle. Prepared for the owner to test: open a real ticket →
Checkout → tap Pay once (sheet + card UI load) → Cancel → retry (second clean sheet) → rapidly tap Pay
several times (only one sheet, no red screen). Do not complete a real charge unless intended.

## 18. Remaining risks
- Low. The latch is per-screen-instance (a ref), released in `finally`; if the screen unmounts mid-
  presentation the instance is discarded, so no stale lock persists across navigations.
- The `CheckoutNative` sticky pay bar still hand-rolls its layout (documented Phase 12 architectural
  inconsistency, no user-facing defect) — untouched here.
- If the sheet still fails to load on device for a non-concurrency reason (e.g. an environment/key
  mismatch on that specific build), that is a separate configuration issue; this fix addresses the
  reported double-resolve concurrency crash.

## 19. Recommendation
**READY FOR OWNER CHECKOUT RE-TEST.** The smallest safe change fixes the objective P1 double-resolve
with no visual, pricing, init, or architecture change and no Core-owned edit; behavioral tests pin the
one-presentation invariant. Keep uncommitted until the owner confirms checkout on a physical iPhone.
