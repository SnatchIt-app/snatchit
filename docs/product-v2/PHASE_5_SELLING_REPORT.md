# Phase 5 — Selling / Create Listing

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase5-selling` (from the Phase 4 checkpoint).
Not committed — awaiting device review. No push, no PR, no Core-owned file touched.

## 1. Phase 4 checkpoint SHA

`40dd9f25b4617daf20560cccae3c28a81c0bc158` — `feat(frontend-v2): redesign bids and ownership`.
Includes the owner-approved Bids/ownership redesign **and** the approved native Oswald line-height
correction (`MIN_LINE_HEIGHT_RATIO 1.02 → 1.25`). Verified at checkpoint: 434 tests / 14 files, tsc
clean, 33 lint warnings / 0 errors.

## 2. Phase 5 branch / base

`frontend/v2-phase5-selling`, branched from `40dd9f2`. No rebase, no force-push, no published branch
touched.

## 3. Files changed

```
M  src/screens/CreateListingScreen.tsx   presentation rebuilt on V2 primitives; publish path preserved
A  src/lib/sell/sellState.ts             pure validation / moderation / risk-parse / money-preview model
A  tests/sell-state.test.ts              35 tests
A  docs/product-v2/PHASE_5_SELLING_REPORT.md
```

Nothing else. Home, Listing Detail, Checkout and Bids are byte-unchanged (working set contains only the
three files above). No shared UI primitive, theme token, or Core file was modified.

## 4. Seller behaviours inventoried

The only seller-create surface is `app/(tabs)/create.tsx` → `src/screens/CreateListingScreen.tsx`
(the previous ~1,139-line single screen). Inventory:

- **Auth**: `useAuth()` user; publish requires a user.
- **Event**: event name, venue, neighborhood (searchable modal over `NEIGHBORHOOD_GROUPS`), category
  (pills over `CATEGORIES`), event date + time (`DateTimePicker`, iOS modal / Android inline).
- **Ticket**: ticket type (GA/VIP), quantity (stepper, min 1), transfer method (mobile_transfer/email),
  ticket platform (searchable modal, 16 platforms), restrictions (optional multiline).
- **Pricing**: starting bid ($, digits-only, number-pad, ≥ $1), Buy Now toggle + conditional Buy Now
  price (must exceed starting bid), auction duration (1/3/6/12/24/48h).
- **Trust**: seller commitment checkbox; ticket platform provenance.
- **Media**: cover image (`useImageUpload` covers, 16:9) and proof of ownership (`useImageUpload`,
  PRIVATE `proof-docs` bucket, migration 033).
- **Validation**: 11 field rules; `isValid` gate.
- **Fee preview**: seller net + buyer all-in via `src/lib/money.ts`.
- **Publish gate chain** (order): submit-mark → validity guard → content moderation (Apple 1.4.3) →
  verified-phone gate (`getUser().phone_confirmed_at` → route to verify-phone) → connected-payout gate
  (`get_my_profile` fast path, else `create-connect-account` `status_only` edge function → route to
  payout-setup) → risk check (`can_create_listing` RPC → ok/warn/block/transient/bad_shape; high-risk
  modal confirm, medium banner, block alert, transient fail-open) → cover upload → proof upload →
  `ends_at` compute → `public.listings` insert → form reset → `router.push(/listing/<id>)`.
- **Duplicate-submit protection**: `busy` (loading || cover uploading || proof uploading) disables the
  action and shows a spinner.
- **Error/success**: RN `Alert` / web `confirm`/`alert`; success navigates to the real detail route.

## 5. Seller behaviours preserved

**All of them.** The redesign is presentation-only. `handlePublish`, `runRiskCheck`, the moderation
gate, both uploads, the exact insert object (including `starting_bid`/`current_bid` = whole-dollar
integers, `buy_now_price` null when off, `proof_of_ownership_path`, `seller_commitment_accepted_at`,
`category`, `ticket_platform`), the form reset and the navigate are byte-for-byte the prior logic.
A shipped-source test asserts every gate marker still exists in the screen. The pure pieces
(validation, moderation, risk parse) moved verbatim into `sellState.ts` and are now tested.

## 6. Form architecture — before / after

**Before:** one long scroll of legacy cards, rounded wells (`radius.md`), pill buttons, a shadowed
`Publish Auction` button, four RN `Modal` sheets, ad-hoc `SectionHeader`/`FieldError`, legacy `colors`.
**After:** the same single screen (no wizard — a multi-step flow would fork the single submission path
and add a duplicate-submit surface, which the brief warned against). Reorganised into five V2 sections
— **Event · Ticket · Selling method · Price · Confirm** — with Oswald section heads, red-tinted
hairlines, `Input`/`Chip`/`Sheet`/`Button`/`StickyBar` primitives, black surfaces, radius 0. The
publish button becomes a `StickyBar` with a live "You get" proceeds figure and a `List ticket(s)` CTA.

## 7. Event selection treatment

No catalog exists, so the manual-entry capability is preserved and re-presented: `Input` for name and
venue; neighborhood and ticket-platform become tappable `SelectRow`s opening a V2 `Sheet` with a search
`Input` and grouped, checkable rows (same filter logic, same data). Date and time are two side-by-side
`SelectRow`s opening the picker inside a `Sheet` (iOS) or inline (Android).

## 8. Ticket-information treatment

Category, ticket type, transfer method and duration render as `Chip` groups (horizontal-scroll where
they can overflow, honoring the primitive's no-wrap contract). Quantity is a square 44pt hairline
stepper. Restrictions stays an optional multiline field. No conditionally-suppressed field was removed.

## 9. Buy Now treatment

A hairline toggle row (`Switch`, red track) with the sentence "Let a buyer skip the auction." When on,
the conditional Buy Now `MoneyField` appears; when off, its value is cleared and it is not validated —
exactly the prior conditional behaviour. `sellingMethodBlurb` states the auction-vs-Buy-Now difference
in one plain sentence.

## 10. Auction treatment

Duration chips (1h–2d) unchanged in value; `ends_at = now + durationHours × 3.6e6` unchanged. Starting
bid, minimum-bid and ending-time rules are untouched — presentation only.

## 11. Pricing treatment

`MoneyField`: a large `$`-prefixed number-pad field with a red focus underline — no tiny box. Digits
are stored raw (`digitsOnly`); visual context never alters the submitted integer. The whole-dollars
listing contract is intact: `starting_bid`/`current_bid` insert as the entered integer; `money.ts` and
`payments.ts` are not imported by the screen and not modified.

## 12. Seller economics treatment

Preserved and clarified. Each price field shows "You get {sellerNet} · buyers pay {allIn} total", and
the sticky bar shows the live seller-proceeds figure. Every amount is composed by `priceSummary`, which
does **no arithmetic** — it only names which authoritative helper produces each line
(`sellerNetFromDollars`, `sellerNetDollars`, `allInFromDollars`, `allInLabel`). A test pins that
composition so a future edit can't silently swap a helper. No proceeds math was invented in the view.

## 13. Validation behaviour

Same 11 rules, moved to `sellErrors(input)` and pinned by tests (each required field; starting bid
≥ $1 incl. the $1 boundary; Buy Now conditional and must exceed the starting bid, with the starting
bid named in the message). Errors surface inline under each field on submit, plus a summary line, plus
`accessibilityRole="alert"`.

## 14. Keyboard / form behaviour

`KeyboardAvoidingView` (iOS padding); `ScrollView` `keyboardShouldPersistTaps="handled"` and
`keyboardDismissMode="on-drag"`; number-pad on money fields; `returnKeyType="next"` on the text inputs;
sheets keep taps alive while filtering. The sticky CTA sits above the safe-area inset via `StickyBar`.

## 15. Review / publish experience

A lightweight review card appears in **Confirm** once a price is set — event, tickets, selling mode,
buyer all-in, seller-per-ticket — rendered only from existing helpers, with **no** new submission path
or backend call. Publishing still goes through the single `handlePublish`.

## 16. Submission state

Unchanged protection: `busy` disables the CTA and shows the `Button` spinner; the label stays mounted
so the control can't change width mid-press. Success is only implied after the insert resolves.

## 17. Success state

Unchanged: on a successful insert the form resets and routing pushes to the real `/listing/<id>` detail
screen (the truthful "view your live listing" outcome). No fake success screen, no confetti, no
"sold" promise.

## 18. Error state

Unchanged surfaces: upload/insert failures use `Alert` (native) / `alert` (web) with human messages;
risk `bad_shape`/`block` show the mapped copy; transient risk errors fail open with a banner and a
console log. No raw Postgres/Supabase/stack text is shown. No Core error architecture was changed.

## 19. Accessibility

Section heads `accessibilityRole="header"`; `Input` labels are programmatic; `SelectRow`/stepper/toggle
carry roles + labels + state; the commitment control is `accessibilityRole="checkbox"` with
`checked` state; the Buy Now row is `role="switch"`; errors are `role="alert"` and never colour-only
(a word always accompanies the red); stepper and chips meet 44pt via size or hitSlop; motion is limited
to the primitives' own press-scale, which already collapses under reduce-motion.

## 20. Motion

Restrained: only the primitives' existing press feedback and the platform sheet slide. No bouncing
controls, animated currency, pulsing price, or confetti.

## 21. Tests added

35 new tests in `tests/sell-state.test.ts`. Suite total **469 / 15 files** (was 434 / 14). No existing
test weakened.

## 22. Exact tests

Amount parsing (2); complete-draft valid (1); each required field enforced (9); price rules incl. the
$1 boundary (2); Buy Now conditional — off ignores, on must exceed, names the starting bid (4); CTA +
method copy incl. a no-em-dash guard (3); price summary invalid + mirrors `money.ts` exactly (2);
content moderation catch/label + clean pass (2); `can_create_listing` parse — array unwrap, transient
fail-open, bad-shape fail-closed, block, high/medium warn (5); shipped-source guards — every publish
gate survives, money contract unchanged in the screen, whole-dollars insert, display type via
`textStyle`, model does no money math, no venue-primary/direct-issuance path (6).

## 23. Typecheck

`tsc --noEmit` clean.

## 24. Lint

`expo lint`: 33 problems, **0 errors, 33 warnings** — identical to baseline, no new warnings.

## 25. iOS bundle result

`platform=ios` metro bundle builds **HTTP 200**, 14.6 MB, no `SyntaxError`/`Unable to resolve`. The new
screen (`Sell your ticket`, `sellingMethodBlurb`, `priceSummary`) and the full gate chain
(`can_create_listing`, `create-connect-account`, `proof_of_ownership_path`) are present in the bundle.

## 26. Physical-device verification status

**Not performed by this session.** The local simulator remains blocked (SDK 26.5 present, only a 26.2
runtime → 0 eligible destinations), so no simulator claim is made. Prepared for Jose's physical-iPhone
review: open Create; event entry; neighborhood/date/platform sheets; ticket details + quantity; Buy Now
on/off; price entry + live proceeds; validation on empty submit; long event title; narrow screen;
scrolling under the sticky bar; the `List ticket(s)` CTA; back behaviour. A real successful publish
should be exercised only with a dev-safe account (it hits the live listings table) — no production data
should be mutated to stage visuals.

## 27. Core dependencies discovered

None new. The screen consumes existing contracts only: `can_create_listing` RPC, `get_my_profile` RPC,
`create-connect-account` edge function, `public.listings` insert (RLS-guarded), and Storage buckets
`covers` / `proof-docs`. No schema, RLS, RPC, edge function, or fee/auction/transfer architecture was
touched. The direct/venue-inventory path stays OFF (093 undeployed) — no venue-primary listing, direct
issuance, or scanning surface was added, and a source guard enforces it.

## 28. Phase 6 (Transfer Flows) readiness

Safe to start after owner approval of Phase 5. Phase 6 touches `app/transfer/*` and the transfer state
machine, which are independent of Create. Note: `ImageUploadTile` is **shared** with
`app/transfer/send/[id].tsx`; it was deliberately reused untouched here, so Phase 6 can restyle it
without any Phase 5 regression. Standing Core blockers unchanged: no stable error-code vocabulary;
`kernel.tickets` SELECT still absent; 093 undeployed with native flags false.
