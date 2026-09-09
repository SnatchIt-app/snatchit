# Phase 6 batch — Place Bid + Profile + Settings

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase6-account-bid-batch` (from the Phase 5 checkpoint).
Not committed — awaiting device review. No push, no PR, no Core-owned file touched.
First batch under the new "≈3 screens at a time" cadence.

## 1. Phase 5 checkpoint SHA

`66c4415be980f06b3423f3b6745f609b8b309317` — `feat(frontend-v2): redesign create listing`.
Verified at checkpoint: 469 tests / 15 files, tsc clean, 33 lint warnings / 0 errors.

## 2. Phase 6 branch / base

`frontend/v2-phase6-account-bid-batch`, branched from `66c4415`. No rebase, no force-push, no published
branch touched.

## 3. Files changed

```
M  src/screens/PlaceBidScreen.tsx           bid entry rebuilt on V2; bid path preserved
M  app/(tabs)/profile.tsx                    profile rebuilt on V2; data layer preserved
M  app/settings/index.tsx                    settings hub rebuilt on V2; deletion machine preserved
A  src/lib/bid/bidEntry.ts                   pure bid math (min / stepper / all-in)
A  src/components/account/AccountSection.tsx reusable Oswald-eyebrow + hairline group
A  src/components/account/SettingsRow.tsx    the one account navigation row
A  tests/bid-entry.test.ts                   17 tests (bid math + 3-screen source guards)
A  docs/product-v2/PHASE_6_BID_PROFILE_SETTINGS_REPORT.md
```

Nothing else. Home, Listing Detail, Checkout, Bids and Create Listing are byte-unchanged; no shared UI
primitive, theme token, or Core file was modified.

## 4. Place Bid behaviours inventoried

Route `app/bid/[id].tsx` → `src/screens/PlaceBidScreen.tsx` (reached from Listing Detail). Fetch of
`current_bid / starting_bid / event_name / venue / ends_at`; fresh floor = `current_bid + MIN_BID_INCREMENT`
(5); selected bid initialised and re-synced to the floor; +/- stepper (floored) and quick-add chips
(+$5/+$10/+$25); buyer all-in via `src/lib/money.ts`; guards — not-signed-in (→ login), below-minimum,
and the F-5 account-deletion guard (own `kernel.identity_ext` row, `DELETION_PENDING` blocks); `bids`
insert (DB trigger moves `current_bid`); duplicate-submit protection via `submitting`; "Bid placed" →
back; loading spinner.

## 5. Place Bid behaviours preserved

**All.** Same fetch, floor, stepper, chips, guards (including the exact `kernel.identity_ext` probe and
its pre-Phase-2 fail-open), the same insert, the same alerts, the same "Bid placed" → back. The
arithmetic moved verbatim into `src/lib/bid/bidEntry.ts` (`minNextBid`/`stepDown`/`stepUp`/`quickAdd`/
`canPlaceBid`/`bidPriceLines`) and is tested. A source guard pins every gate marker. The entry model
stays stepper + quick-chips (the real existing behaviour) — no free-text field was introduced, so the
increment/minimum contract is untouched.

## 6. Profile behaviours inventoried

`app/(tabs)/profile.tsx`: `get_my_profile()` RPC (owner row); avatar resolve + pick/upload (→ update
`profiles.avatar_path`); seller stats — active count, sold count, proceeds (seller net per row via
`sellerNetDollars` + `finalSoldPrice`); non-blocking payout-status probe (`create-connect-account`
`status_only`, 6s timeout race, only when `stripe_connect_id`); My Listings + stat navigation; sign
out; focus refetch; pull-to-refresh; loading + `ScreenState` offline/error; masked phone; initials
fallback.

## 7. Profile behaviours preserved

**All.** `loadData` (profile RPC, active/sold/proceeds, payout race) is unchanged, as are avatar
upload, sign out, focus refetch and refresh. Proceeds still render `—` when zero so an UNKNOWN total
stays distinct from a real `$0` (the false-zero rule); the counts remain real integers. The public
seller profile (`app/profile/[id].tsx`) is a separate surface and out of this batch's scope — untouched.

## 8. Settings behaviours inventoried

`app/settings/index.tsx`: OR-17 tombstone deletion machine — tri-state `unknown/pending/active` from the
caller's own `kernel.identity_ext` row, a separate probe-failed state, a pending withdraw banner
(`delete-account` `action: withdraw`), and an AppState foreground re-check; navigation to nine
sub-routes; sign-out (single confirm → `signOut` → login); delete-account (double confirm → edge
function → sign out); web `confirm`/native `Alert` parity.

## 9. Settings behaviours preserved

**All.** The deletion tri-state, the "a failed probe is never read as not-pending" invariant, the
probe-failed retry, the withdraw flow, the AppState listener, both confirmation flows and every
edge-function call are unchanged. A source guard pins the tri-state type, `DELETION_PENDING`,
`deletionProbeFailed`, both confirm strings and `executeDeleteAccount`. The settings SUB-screens keep
their current UI this batch; the hub only links to them.

## 10. Bid-entry hierarchy

Header (back + Oswald "Place bid") → event name + venue (Inter) → a **Current bid / Your bid**
comparison (two columns, hairline divider, your bid in red) → the **amount as the focus** (a 56pt
tabular Inter figure) with the +/- stepper and quick chips → a **breakdown** (bid, service fee, you pay
if you win) → a `StickyBar` with the all-in on the left and one "Place bid" action. It reads as the same
conversion system as Listing Detail and Checkout.

## 11. Pricing treatment

All amounts route through `bidPriceLines` / `bidTotalLabel`, which only compose `money.ts` helpers
(`buyerFeeCents`, `buyerTotalCents`, `dollarsToCents`, `formatCents`) — no fee arithmetic, no cents/
dollars conversion, no new math. Whole-dollar bid amounts display via a local `$` formatter; the all-in
(bid + 10% service fee) is shown before the bid is placed and again on the sticky bar. A test asserts
the composition mirrors the raw helpers, and a guard forbids importing the raw buyer helpers into the
screen.

## 12. Profile hierarchy

Header (Oswald "Profile" + a text "Settings" action, no gear emoji) → identity (circular avatar with a
red hairline ring — avatars are the sanctioned radius exception — name in Inter, masked phone, Verified
badges via the `Badge` primitive) → **Seller** section (a three-up Active / Sold / Proceeds stat strip
over a hairline, plus a "My listings" row) → **Payouts** section (status row, shown only when the user
has listings) → a restrained secondary "Sign out" button. Legacy glow shadows and the rounded stat
cards are gone.

## 13. Trust-state handling

Proceeds are the trust-sensitive figure: `stats.revenue > 0 ? formatMoney(...) : '—'` — a zero total
shows `—` (unknown), never a misleading `$0`. Verified buyer/seller badges render only when true, using
the word-bearing `Badge` (never colour-only). Payout status carries both a word and its tone, never
colour alone. No social stats, follower counts, ratings, or fake verification were invented.

## 14. Settings hierarchy

Header (back + Oswald "Settings") → deletion banners when applicable → **Account** (Edit profile,
Notifications, Phone verification) → **Payments** (Payout setup) → **Preferences** (Your scene) →
**Safety** (Blocked users) → **Support** (Help & support, Terms, Privacy) → account actions. Every group
is an `AccountSection` (Oswald eyebrow + hairline) of `SettingsRow`s — one row treatment, no emoji, no
cards, no colored tiles.

## 15. Preferences behaviour

Unchanged. The preferences persistence lives in `app/settings/preferences.tsx`, which is a separate
sub-route this batch does not modify — so its save path (and its "failed save must not look successful"
handling) is untouched. The hub only links to it.

## 16. Payout / settings routing

Preserved. Profile → `/settings/payout-setup` (from the Payouts row) and Settings → `/settings/payout-setup`
(Payments) both point at the existing route. No Stripe Connect backend behaviour was changed; only the
navigation presentation moved to V2.

## 17. Destructive-action treatment

Restrained and distinct without a red screen. Sign out is a **secondary** button (hairline, white
label) that still runs the existing confirm on Settings; Delete account is a **destructive** button
(hairline, error-red label — a different red from the brand) that keeps the full double-confirm. The
`SettingsRow` also carries a `tone="destructive"` (title-only recolour) for future use. All
confirmations and edge-function calls are preserved.

## 18. Accessibility

Place Bid: stepper and quick chips are `role="button"` with labels and disabled state, 44/52pt targets
or hitSlop; the amount has an `accessibilityLabel`; the CTA carries busy state. Profile: avatar,
Settings action, and each stat/row have roles + labels; badges are word-bearing. Settings: every row is
`SettingsRow` (role button, label incl. any value, 56pt), banners are `role="alert"`, the retry is a
labelled button, destructive actions keep native confirm dialogs. No state is colour-only; motion is
limited to the primitives' press-scale, which collapses under reduce-motion.

## 19. Motion

Restrained: only the primitives' existing press-scale and the platform alert/confirm dialogs. No
bouncing, pulsing, animated currency, or confetti on any of the three.

## 20. Tests added

17 tests in `tests/bid-entry.test.ts`. Suite total **486 / 16 files** (was 469 / 15). No existing test
weakened.

## 21. Exact tests

Bid math — minimum = current + increment, stepper floor + increment, quick add, `canPlaceBid` boundary
incl. NaN (4); all-in mirrors the canonical buyer helpers exactly (1). Source guards — Place Bid: bid
path survives (deletion guard, insert, `minNextBid`, `canPlaceBid`, `bidPriceLines`), reads
`identity_ext` and never `kernel.tickets`/wallet/barcode, no fee arithmetic in screen or model, confirms
"Bid placed" not ownership (4). Profile: data layer survives (`get_my_profile`, `sellerNetDollars`,
payout probe, avatar update, sign out), unknown-vs-zero proceeds, phone masked, no `kernel.tickets` (4).
Settings: deletion tri-state + guards survive, failed-probe never hides the withdraw banner, sign-out +
double-confirm delete survive, no emoji in rows (4).

## 22. Typecheck

`tsc --noEmit` clean.

## 23. Lint

`expo lint`: 32 problems, **0 errors, 32 warnings** — one fewer than the 33 baseline, **no new
warnings** (the redesign removed a stale eslint-disable).

## 24. Native iOS bundle

`platform=ios` metro bundle builds **HTTP 200**, 14.6 MB, no real `SyntaxError`/`Unable to resolve`
(only metro's own error-handling template strings match a naive grep). The new surfaces (`Place bid`,
`AccountSection`, `minNextBid`, `bidPriceLines`, `Withdraw deletion request`) and the preserved data
paths (`get_my_profile`, `identity_ext`, `delete-account`) are present in the bundle.

## 25. Physical-device verification status

**Not performed by this session.** The local simulator remains blocked (SDK 26.5 present, only a 26.2
runtime → 0 eligible destinations); no simulator claim is made. Prepared for one physical-iPhone review
pass across all three: Place Bid (open listing → bid flow, stepper/chips, min/current context, CTA,
back); Profile (header, identity, trust/badges, stats, scrolling, into Settings); Settings (all
sections, rows, payout route, sign-out placement, destructive treatment, narrow width, scrolling, and —
only on a dev-safe account — the deletion pending/withdraw banner). No production data should be mutated
to stage states.

## 26. Core dependencies discovered

None new. Consumes existing contracts only: `bids` insert + its `current_bid` trigger, `listings` read,
`kernel.identity_ext` owner-scoped SELECT, `get_my_profile` RPC, `create-connect-account` and
`delete-account` edge functions, `profiles.avatar_path` update, Storage avatar bucket. No schema, RLS,
RPC, edge function, or payment/auction/transfer architecture touched. `kernel.tickets` is not queried;
no venue-primary/direct-issuance UI (093 still off). Standing Core blockers unchanged: no stable
error-code vocabulary; `kernel.tickets` SELECT still absent.

## 27. Recommended next three screens

1. **Auth / onboarding** (`app/(auth)/*` — login, sign-up, verification) — the first-run surface, still
   legacy, and the natural pair before a navigation pass.
2. **Transfer flows** (`app/transfer/*` — send + receive) — the post-sale ownership handoff; `ImageUploadTile`
   was reused untouched in Phase 5 specifically so this can restyle it. (This is the deferred Phase 6
   "Transfer" work.)
3. **My Listings + Edit Listing** (`app/my-listings.tsx`, `app/listing/edit/[id].tsx`) — the seller's
   management surface, reached straight from the new Profile stat rows, so it closes that loop.
