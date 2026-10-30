# Phase 3 — Checkout + purchase confirmation

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase3-checkout` (from `frontend/v2-phase2-home`, which carries the three
checkpoint commits plus the SN-logo revision).

The money and Stripe path is unchanged; the presentation is V2; the buyer now sees what they are
buying; and the web bundle no longer breaks. No committing (this phase is not yet device-reviewed),
no push, no PR, no Core-owned file touched.

---

## 1. Money and payment logic — preserved verbatim

This is the money-sensitive screen, so the rule was absolute: change presentation, touch nothing that
computes or moves money. Preserved exactly, and asserted by a source guard test:

`serverBreakdown` as the sole amount authority · `createPaymentIntent` with `expectedTotalCents` ·
`confirmPaymentSuccess` · `mark_listing_sold` (Buy Now) · `complete_auction_payment` (auction) ·
`ensure_transfer_exists` and the transfer-id fetch · the Buy Now reservation pre-check · the Apple
Pay `isPlatformPaySupported` probe, cart line items and sum invariant · `initPaymentSheet` with saved
cards (customerId + ephemeral key) and `returnURL` · `presentPaymentSheet`, the Canceled path, and
the Sentry `reportCheckoutFailure` / `isExpectedCheckoutError` error handling.

No new money arithmetic. Every displayed amount is `formatCents(...)` of a server figure (with the
same client estimate fallback as before). The only `/100` in the file is the pre-existing Apple Pay
cart, which PassKit requires as decimal strings — unchanged.

## 2. What the redesign changed

- **The buyer sees the event.** The old order summary was two text rows (Event, Venue) and no image,
  on the screen where the money leaves. It now leads with the event artwork (`EventMedia`,
  `CHECKOUT_THUMBNAIL` slot), name, venue and date. These come from a small read-only fetch of
  `public.listings` display columns, independent of the payment flow — it touches no money and never
  blocks payment if it fails. Listing Detail did not have to change to pass anything.
- **A live reservation countdown.** Buy Now showed a static "reserved for 10 minutes" line. It now
  shows `Held for you · m:ss left`, counting down from the fetched `reserved_until`, and
  `Reservation expired` at zero.
- **V2 surface.** True-black canvas, the primitives (`Button`, `IconButton`, `Spinner`), `PriceDisplay`
  and `textStyle`. The pay control is one `Button` driven by a single state function; the old screen
  duplicated its six-state logic across the Buy Now and auction JSX branches.
- **The confirmation.** The "Purchase complete!" screen with a check glyph and emoji is replaced by a
  branded confirmation: an Oswald "You're in.", the event card, one plain sentence about what happens
  next (payment held until the ticket lands), and one primary action into the transfer or home. Same
  routing as before.
- **No emoji anywhere on checkout** (was 🛒 🎉 🔒 💳 ⚠️ ✓). No em dashes in copy.

## 3. Pay control as tested logic

`src/lib/checkout/payControl.ts` resolves the pay button's six states — processing, authenticating,
setting up, ready, error, unavailable — in one place with a fixed precedence (an in-flight charge
outranks everything; setup outranks readiness). The component consumes it, so the Buy Now and auction
paths cannot drift. `fmtCountdown` lives here too. Both are pure and tested.

## 4. The web bundle fix

Phase 2 flagged that `app/checkout/[id].tsx` broke the web build: its `Platform.OS !== 'web'` guard
was a runtime check, but the web bundler still traced the `require('@/src/screens/checkout/
CheckoutNative')` inside it and pulled in `@stripe/stripe-react-native`, which reaches native-only
code (`codegenNativeCommands`).

Fixed with platform-extension resolution instead of a runtime guard:

```
app/checkout/[id].tsx        → re-exports CheckoutRoute
src/screens/checkout/CheckoutRoute.tsx   → renders <CheckoutEntry/>
src/screens/checkout/CheckoutEntry.native.tsx  → re-exports CheckoutNative (Stripe)   [native only]
src/screens/checkout/CheckoutEntry.tsx         → web-safe fallback, imports no native  [web + default]
```

Metro resolves `.native.tsx` on native and the base `.tsx` elsewhere, so Stripe is only ever in the
native graph. The `CheckoutRoute` indirection exists because the eslint TS resolver does not apply RN
platform suffixes when the importer is a bracketed route file (`[id].tsx`); routing through a
non-bracketed module resolves cleanly for every tool, matching the existing `NativeAppShell` pattern.

**Verified by building both bundles from Metro in this worktree:**

| Bundle | Result | Stripe |
|---|---|---|
| iOS (`platform=ios`) | HTTP 200, 14.6 MB | present (20 refs) — correct |
| Web (`platform=web`) | HTTP 200, 9.4 MB | **0 module imports** — the base entry has none; the web fallback copy is present |

The web bundle previously returned a 500 fatal. This restores web as a smoke-test path for the rest
of the app (Home, Listing Detail); checkout itself remains mobile-only and shows the fallback on web.

## 5. Behaviours inventoried and preserved

| Behaviour | Status |
|---|---|
| Auth gating, setup on mount | preserved |
| Buy Now reservation pre-validation | preserved |
| createPaymentIntent + serverBreakdown | preserved (authority) |
| Apple Pay probe / cart / saved cards | preserved |
| initPaymentSheet + returnURL | preserved |
| presentPaymentSheet, Canceled handling | preserved |
| confirmPaymentSuccess | preserved |
| mark_listing_sold / complete_auction_payment | preserved (mode-branched) |
| ensure_transfer_exists + transfer-id fetch | preserved |
| Expected vs unexpected error → Sentry + safe copy | preserved |
| Retry on setup failure | preserved (pay button "Try again") |
| Order summary (event, price, fee, total) | redesigned, server numbers preserved, image added |
| Reservation notice | upgraded to a live countdown |
| Sold / confirmation screen + routing | redesigned, routing preserved |
| Processing state | preserved (Button loading) |

## 6. Accessibility

Back control is the labelled 44pt `IconButton`; the title is a `header`. The order row, breakdown
rows and confirmation card carry composed labels. The pay button carries busy/disabled state through
the primitive. The countdown is not a live region (it would announce every second). Amounts use
tabular figures.

## 7. Tests, typecheck, lint

```
npm test  (vitest run)    → Test Files  13 passed (13)
                            Tests      413 passed (413)
npx tsc --noEmit -p .     → clean, exit 0
npm run lint (expo lint)  → 33 problems (0 errors, 33 warnings)
```

New: `tests/checkout-pay-control.test.ts` (14 tests) — the pay-state precedence matrix, the countdown
formatter, and source guards (server authority + every payment RPC still present; amounts via
`formatCents`; the event image present; Stripe absent from the base entry and reached only via the
native entry; no emoji; no venue-direct claim).

| | Phase 2 end | Phase 3 end |
|---|---|---|
| Tests / files | 399 / 12 | **413 / 13** |
| Typecheck | clean | **clean** |
| Lint | 36 warnings, 0 errors | **33 warnings, 0 errors** |

No new warnings; the count fell because the checkout rewrite dropped dead code the old file carried.

## 8. Runtime verification

**What ran:** Metro serves this worktree; both the iOS and web bundles compile and serve (§4). The
new checkout copy and the web fallback are present in their respective bundles. tsc, lint and 413
tests pass.

**What did not:** I did not see the native checkout render. It is Stripe-native, so it cannot render
on web (the point of the fallback), and the local iOS Simulator is still unusable —
`xcodebuild -showdestinations` lists no eligible simulator destination (SDK 26.5 present, only a 26.2
runtime installed), the same environment blocker recorded in Phase 2, reproduced by the simulator
build tool. Device review needs the phone in hand.

**To finish the review** with Metro running (`npx expo start --dev-client --tunnel`), walk: open a
Buy Now listing → Buy → confirm the event image, the live "Held for you" countdown, the price
breakdown, Apple Pay/card, and the "You're in." confirmation → View transfer; then an auction win →
Pay now → same. Money numbers must match what the server returns.

## 9. Core dependencies

None new. Unchanged and re-noted: no stable error-code vocabulary (checkout still surfaces the
server's own actionable messages verbatim for expected errors and a safe generic for the rest, which
is the pre-existing, correct behaviour); 093 undeployed and native flags false (checkout is
marketplace-only); no event-media schema (checkout uses the listing cover, like the rest of the app).

## 10. Phase 4 (Bids + ownership) readiness

Ready. Phase 4 rebuilds the Bids surface and introduces the ownership view; it reuses the discovery
card, the primitives and the transfer routing this phase leaves intact. The one dependency it will
hit is the `kernel.tickets` SELECT grant for a real Tickets destination, still absent — Phase 4
should scope ownership to what the transfer/purchase data already exposes until Core ships it.

**Before Phase 4:** Phase 3 has not been device-reviewed. It should be run on the phone and approved,
then checkpointed alongside the earlier phases, before the next phase stacks on top.
