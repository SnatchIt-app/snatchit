# Frontend V2 — final integration

**Session:** Front End · **Date:** 2026-09-04
**Status:** assembled and committed. **NOT owner-approved** — Jose must still verify Home, Stripe
checkout and reservation behaviour on a physical iPhone from **this** worktree.
No push, no PR, no deploy, no migrations, no Core flags.

## 1. Integration branch
`frontend/v2-final-integration` — worktree `/Users/josetascon/snatchit-fe-integration`

## 2. Integration base
`085e2984cc89b1bf03cdf11c93f0ba182c3f17a4` — Phase 12 (owner-approved hardening).

## 3. Home checkpoint SHA
`1c1f471b42439c961715f1014137f6151965d313` — `feat(frontend-v2): refine home discovery controls`
(**owner-approved on device**).

## 4. Stripe checkpoint SHA
`a7eeea5ba037bb511df0c268206d06b85b5ff55f` — `fix(checkout): prevent duplicate payment sheet
presentation` (**technical checkpoint only**).

## 5. Resulting integration HEAD
`41c1583728b49b59d1ab219f7c20661bc185dfa3`

History (no rebase, no squash):
```
41c1583 feat(listing): release Buy Now hold when leaving the listing for Home
12f3028 Merge branch 'frontend/checkout-stripe-hotfix' into frontend/v2-final-integration
a7eeea5 fix(checkout): prevent duplicate payment sheet presentation
1c1f471 feat(frontend-v2): refine home discovery controls
085e298 fix(frontend-v2): harden accessibility and responsive behavior
```

## 6. Home approval state
**APPROVED on physical iPhone.** Centred SN mark, MIAMI from the current-market abstraction, Search
preserved, quick row reduced to **Your scene · Price · Filters** (Price opens the existing sheet
directly on the price section), full taxonomy preserved behind Filters, smooth interruptible collapse
bar, AdaptiveDock unchanged.

## 7. Stripe physical-device state
**PENDING.** The latch is present and bundles correctly, but the owner has never run a build containing
it — see §8.

### Why the device kept showing the old Stripe behaviour
Process evidence taken during this session:
- port **8081** → `expo start --dev-client --lan` running from `/Users/josetascon/snatchit-fe-home`
- port **8082** → a second server, also from `/Users/josetascon/snatchit-fe-home`

Both served the **Home** worktree, which does not contain the checkout fix. Metro serves whatever code
exists in *its own* worktree, independent of git state, so no build taken from those ports could ever
include the latch. This is exactly why the integration worktree now exists: it is the single place that
contains Home + Stripe + Phase 12 together, and it is the only worktree that should be used for owner
checkout testing.

## 8. Reservation architecture findings
| Question | Finding |
| --- | --- |
| Where is the 10-minute hold created? | `public.reserve_buy_now(p_listing_id, p_user_id, p_minutes)`, called from `ListingDetailScreen`; window from `APP_CONFIG.RESERVATION_MINUTES = 10` |
| Which layer owns it? | **Core / Postgres.** State lives on `public.listings` (`status='reserved'`, `reserved_by`, `reserved_until`) |
| DB-backed? | Yes |
| Existing release contract? | **YES — `public.release_reservation(p_listing_id, p_user_id)`**, `SECURITY DEFINER`, granted to `authenticated` (0552/0590) |
| Ownership validated? | Yes: `auth.uid()`, then acts only `IF v_status='reserved' AND v_reserved_by = v_caller_id` |
| Idempotent? | Yes: anything not actively reserved falls through as a no-op |
| After payment succeeded? | Refused: `IF v_status='sold' THEN RETURN` |
| Concurrency | `SELECT … FOR UPDATE` row lock |
| Already expired/released? | No-op |
| Can another buyer acquire it after release? | Yes: it sets `status='active'`, `reserved_by=null`, `reserved_until=null` |

Because a safe, owner-scoped, idempotent Core contract already exists, the frontend was permitted to
wire it. **No Core handoff was required.**

## 9. Reservation frontend implementation
- **Exit signal:** React Navigation `beforeRemove` on the listing screen. It fires when the listing is
  **popped** and not when Checkout is **pushed on top** — so `Checkout → Listing` keeps the hold and its
  remaining timer, while `Listing → Home` releases. Backgrounding, phone calls, the Stripe sheet,
  modals, the keyboard and transitions are not navigation removals and never release.
- **Decision:** pure, tested `src/lib/listing/reservationExit.ts` — releases only when the listing is
  `reserved`, `reserved_by === auth user`, not purchased, and not already released by this screen.
- **Call:** the existing `release_reservation` RPC, fire-and-forget so Home navigation is never blocked;
  a transient failure is logged and the server-side expiry remains the safety net. No client row writes,
  no timers, no fake availability, no schema/RLS/migration change.
- **Never after purchase:** three independent guards — the screen latches `purchased` when it sees the
  listing go `sold` (realtime), the pure helper refuses on `status !== 'reserved'`, and the server
  refuses when `status='sold'`.
- **No UX noise:** silent, no confirmation dialog, no payment copy.

## 10. Core handoff path
**Not required** — the contract already exists. No `docs/product-v2/RESERVATION_EXIT_CORE_HANDOFF.md`
was created, because writing a handoff for an RPC that ships today would be misleading.

## 11. Files changed vs the Phase 12 base
`app/(tabs)/home.tsx` · `src/components/discovery/HomeHeader.tsx` ·
`src/components/discovery/FilterSheet.tsx` · `src/lib/home/filterBarMachine.ts` ·
`src/lib/home/filterModel.ts` · `src/lib/market/currentMarket.ts` ·
`src/screens/checkout/CheckoutNative.tsx` · `src/lib/checkout/paymentGuard.ts` ·
`src/screens/ListingDetailScreen.tsx` · `src/lib/listing/reservationExit.ts` ·
`tests/home-header.test.ts` · `tests/payment-guard.test.ts` · `tests/reservation-exit.test.ts` ·
the three reports.

## 12. Conflicts / resolutions
**None.** Home fast-forwarded onto the base; Stripe merged as a merge commit. The two checkpoints touch
disjoint files (discovery/home vs checkout), so git resolved everything automatically. No behaviour was
altered during integration.

## 13. Core-owned files changed
**None.** No `supabase/**`, migration, RLS, `money.ts`, `payments.ts`, `supabase.ts`, `secureStorage.ts`,
`venue/**`, `packages/**`, `scripts/**`, `.github/workflows/**`, `app.json` or `eas.json`.
Payment architecture and money/fee logic unchanged.

## 14. Route inventory status
**30 reachable user-facing surfaces, all V2. 0 legacy** (no non-V2 theme import in any reachable
screen). Nav order `HOME · CREATE · BIDS · TICKETS · PROFILE`; Search stays inside Home; Tickets remains
a primary tab. `AdaptiveDock.tsx`, `navInsets.ts` and `dockMachine.ts` are **byte-identical** to the
Phase 12 base. No Ticket Detail / QR / barcode / Wallet feature was added (the only matches for those
words are a "no QR/barcode" doc comment, an Apple Pay cart-item convention comment, and pre-existing
third-party transfer instructions).

## 15. Tests
**637 passed / 28 files** (Phase 12 base 595/25 → +21 Home, +7 Stripe, +14 reservation... net 637).
Covers: three quick controls only, collapse/return/partial-reverse/rapid-reversal/jitter/top-reset/
empty-feed, centred SN, single market label, PRICE focus; rapid taps present the sheet once, cancel and
error release the latch, retry works; `Checkout → Listing` does not release, `Listing → Home` does,
duplicate exit cannot double-fire, purchase suppresses release, another buyer's hold is never touched.

## 16. Typecheck
`tsc --noEmit` clean (exit 0).

## 17. Lint
27 problems, **0 errors, 27 warnings** — identical to baseline, no new warnings.

## 18. Native iOS bundle
**HTTP 200, ~14.64 MB** from the integration worktree (port 8084), containing the checkout latch, the
Home filter-bar controller and the reservation release call.

## 19. Physical-device tests still required
- **Home:** approved behaviour still correct after integration.
- **Stripe:** open a ticket → Checkout → tap Pay **once** → PaymentSheet appears and card entry loads →
  Cancel → retry → sheet opens cleanly again → rapid-tap Pay → only one sheet, no red screen. Do not
  complete a real charge unless intended.
- **Reservation:** A) Listing → Checkout → back to Listing = hold survives, timer continues, no reset.
  B) Listing → Home = hold releases immediately. C) Listing → Checkout → Listing → Home = survives then
  releases. D) background the app on Listing/Checkout = hold must NOT release. E) complete a purchase =
  release must never fire.

## 20. Final frontend readiness
All three workstreams are assembled on one branch with clean history, full green verification and no
Core change. The frontend is ready for a single consolidated device pass; it is **not** owner-approved
until that pass succeeds. Blocked feature work (Ticket Detail, QR/barcode, Apple Wallet, populated
Tickets data) remains untouched and Core-gated.
