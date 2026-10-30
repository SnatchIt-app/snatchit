# Phase 7 batch — Auth / Onboarding + Transfer + My Listings / Edit

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase7-auth-transfer-listings` (from the Phase 6 checkpoint).
Not committed — awaiting device review. No push, no PR, no Core-owned file touched.

## 1. Phase 6 checkpoint SHA

`8f9621a440498960dd9575fde07c99287cc00145` — `feat(frontend-v2): redesign bid profile and settings`.
Verified at checkpoint: 486 tests / 16 files, tsc clean, 32 lint warnings / 0 errors.

## 2. Phase 7 branch / base

`frontend/v2-phase7-auth-transfer-listings`, branched from `8f9621a`. No rebase, no force-push, no
published branch touched.

## 3. Files changed

```
M  app/(auth)/login.tsx
M  app/(auth)/signup.tsx
M  app/(auth)/reset-password.tsx
M  app/transfer/send/[id].tsx
M  app/transfer/receive/[id].tsx
M  app/my-listings.tsx
M  app/listing/edit/[id].tsx
M  src/components/SellerListingCard.tsx        (my-listings-only; rebuilt on V2)
A  src/lib/auth/authForms.ts                   validation + friendlyAuthError
A  src/lib/transfer/transferState.ts           countdown + status + gates
A  src/lib/listing/sellerListing.ts            badge + edit/delete/cancel gates
A  tests/auth-forms.test.ts
A  tests/transfer-state.test.ts
A  tests/seller-listing.test.ts
A  docs/product-v2/PHASE_7_AUTH_TRANSFER_LISTINGS_REPORT.md
A  docs/product-v2/NAVIGATION_V2_DIRECTION.md
```

Home, Listing Detail, Checkout, Bids, Create, Place Bid, Profile, Settings hub and every shared UI
primitive / theme token are byte-unchanged.

## 4. Auth behavior inventory

Routes: `app/(auth)/login.tsx`, `signup.tsx`, `reset-password.tsx`, `_layout.tsx` (Stack, no header).
No separate onboarding route; email confirmation is Supabase's email link, phone verification lives
under `settings/verify-phone` (out of this batch). **Login:** email/password → `signInWithPassword`
(session detection routes to Home), forgot-password → `resetPasswordForEmail` with `snatchit://`
redirect, both-fields validation, error text. **Signup:** email/password → `signUp` with
`emailRedirectTo snatchit://`, validation order fields → password ≥ 6 → 18+ gate, App Store 1.4.3 age
checkbox, Terms/Privacy links, create button gated on age + loading, success/error message.
**Reset:** new + confirm → `updateUser`, sign out, back to login; both-required + match validation.

## 5. Auth behavior preserved

**All.** Every Supabase call, the deep-link redirects, the exact validation order and the 18+/legal
gates are unchanged; a source guard pins each. Validation copy moved verbatim into
`src/lib/auth/authForms.ts` and is tested. Added: `friendlyAuthError` passes known auth strings
through and generalises technical/internal ones, so a raw database/network string is never shown.

## 6. Transfer behavior inventory

Routes: `app/transfer/send/[id].tsx` (seller), `receive/[id].tsx` (buyer). **Send:** owner-scoped
fetch; expiry (pending, 24h) + auto-release (seller_sent, buyer review) countdowns; required evidence
upload to the private `proof-docs` bucket; `mark_transfer_sent` RPC; post-send states — seller_sent
(with `payout_review_status` sub-copy: null/held/manual_review), buyer_confirmed, auto_released,
disputed; buyer-delivery-missing gate; `PlatformInstructions`. **Receive:** owner-scoped fetch;
`mark_transfer_viewed` RPC; seller proof signed URL + `ProofImageViewer`; countdown; delivery-info
gate via `DeliveryInfoForm` → `set_transfer_delivery_info` (with `normalizeUSPhone`); confirm via the
`confirm-and-release` edge function; dispute via `buyer_dispute_transfer`; pending/seller_sent/
confirmed/disputed states.

## 7. Transfer behavior preserved

**All.** Every RPC, edge function, countdown, signed-URL flow, gate and state branch is unchanged;
countdown + status vocabulary now come from the tested `src/lib/transfer/transferState.ts`. The
private bucket, `DeliveryInfoForm`, `PlatformInstructions` and `ProofImageViewer` are untouched.
Ownership is only ever asserted on the `buyer_confirmed` branch — never before authoritative
confirmation (guarded by a test). The proof upload experience is now inside a V2 screen but still uses
the same `ImageUploadTile`, bucket and paths.

## 8. My Listings behavior inventory

`app/my-listings.tsx`: seller listings fetch + resolved covers; a per-listing transfer map driving
"send the tickets"; hard-load + focus refetch + pull-to-refresh; filters all/active/needs_action/
ended/sold with counts; delete (no bids, active) vs cancel (has bids → `cancel_listing` RPC), each
double-checked and confirmed; card routing (send screen when sold-and-unsent, else listing detail),
edit and delete affordances; `ScreenState` offline/error.

## 9. My Listings behavior preserved

**All.** The fetch, transfer map, focus/refresh, the exact delete/cancel decision and their
confirmations, the count logic and the routing are unchanged (source-guarded). Presentation moved to
Oswald header + `Chip` filters + `EmptyState` + skeletons + the V2 `SellerListingCard`. The
`needs_action` filter label dropped its emoji ("Send tickets").

## 10. Edit Listing behavior inventory

`app/listing/edit/[id].tsx`: load + guards (not found / not owner / has bids or inactive → alert →
back); editable subset event_name / venue / restrictions / ticket_platform; save requires event +
venue, runs the content-moderation gate, updates only those four columns scoped to the owner, alerts
and returns. Pricing / quantity / dates are intentionally not editable (server
`guard_listing_state_columns` + RLS are the hard wall).

## 11. Edit Listing behavior preserved

**All.** The load guards, the editable-field scope, the required-field + moderation checks and the
scoped update are unchanged. The moderation gate now reuses Create's `findBannedContent` from
`src/lib/sell/sellState.ts` (the duplicated lexicon is gone). A source guard asserts no price/quantity
/date field entered the update.

## 12. Auth hierarchy

Centered, minimal: the official white **SN** mark, an Oswald display title (`Sign in` / `Create
account` / `New password`), `Input` fields with proper keyboard/content types and autofill, one
primary `Button`, and a quiet cross-link. Signup adds the square 18+ checkbox and the Terms/Privacy
line. No marketing paragraphs, no full wordmark, black/white with red only on the action and links.

## 13. Transfer-state hierarchy

Header (back + Oswald title) → the highest-priority action first (delivery gate, or evidence upload,
or confirm/dispute) → a details section carrying a status `Badge` (word + tone) → state blocks with
the role-specific payout/dispute copy. Countdown and "who acts" read at a glance; colour never carries
meaning alone.

## 14. Upload treatment

The transfer screens are now V2 (header, hairline sections, `Badge`, `Button`, `Spinner`) with the
evidence tile embedded in a clear "Transfer evidence" block and a plain-language confirmation line.
The upload mechanism itself — `useImageUpload`, the `proof-docs` bucket, validation, retry, the
`mark_transfer_sent` path — is unchanged. `DeliveryInfoForm` is retained as-is.

## 15. Listing-management hierarchy

My Listings closes the loop from Profile: header → chip filters with live counts → event-first cards
(cover, event, venue, status Badge, bids/current bid, the seller's next action) → edit/delete/cancel
inline. Internal IDs are never surfaced.

## 16. Create / Edit shared-pattern decisions

Edit reuses Create's language (`Input`, `Chip` platform row, a matching multiline field, a `StickyBar`
"Save changes") and shares Create's `findBannedContent`, but the two screens stay separate modules:
their submission logic and editable scope differ (Create inserts a full listing through a gate chain;
Edit updates four safe columns). Unifying them would have merged different business rules, which the
brief forbade — so the sharing is at the presentation + pure-helper layer only.

## 17. Accessibility

Auth: `Input` labels are programmatic, fields carry keyboard/content/autofill types, the age control is
`role="checkbox"` with state, legal links are `role="link"`, errors are `role="alert"`. Transfer:
back button labelled, status is a word-bearing `Badge`, primary/dispute actions carry busy state,
proof image is an `imagebutton`. Listings: cards and every edit/delete/cancel control are labelled
buttons with 44pt targets (or hitSlop); filters are accessible `Chip`s. No colour-only state; motion
limited to the primitives' press-scale (collapses under reduce-motion).

## 18. Motion

Restrained: primitive press-scale and the platform sheet/alert only. No confetti, pulsing, bouncing,
or fake celebration on any surface.

## 19. Tests

25 new tests across three files. Suite total **511 / 19 files** (was 486 / 16). No existing test
weakened. — auth-forms (login/signup/reset validation, `friendlyAuthError`, 3 auth source guards);
transfer-state (countdown, status meta, three gates, 3 transfer source guards incl. no-ownership-
before-confirm); seller-listing (badge matrix, edit/delete/cancel gates, time-left, My Listings/Edit
source guards incl. no price fields, no money import, no `kernel.tickets`).

## 20. Typecheck

`tsc --noEmit` clean.

## 21. Lint

`expo lint`: 30 problems, **0 errors, 30 warnings** — two fewer than the 32 baseline, **no new
warnings** (the rewrites removed stale eslint-disable directives).

## 22. Native iOS bundle

`platform=ios` metro bundle builds **HTTP 200**, 14.6 MB, no real errors (only metro's own error-parser
regexes match a naive grep). New surfaces (`Send transfer`, `Receive transfer`, `My listings`,
`Create account`, `validateSignup`, `transferStatusMeta`, `sellerBadge`) and preserved paths
(`mark_transfer_sent`, `confirm-and-release`, `buyer_dispute_transfer`, `cancel_listing`,
`signInWithPassword`) are present in the bundle.

## 23. Physical-device verification

**Not performed by this session.** The local simulator remains blocked (SDK 26.5 present, only a 26.2
runtime → 0 eligible destinations); no simulator claim is made. Prepared for one physical-iPhone
review across: Auth (login, signup, verification/reset, keyboard, errors); Transfer (pending, upload/
proof, confirm/dispute states, navigation) — exercise real state changes only on a dev-safe
buyer/seller pair; My Listings / Edit (list, filters, status, edit + validation, seller action). No
production data should be mutated to stage states.

## 24. Core dependencies

None new. Consumes existing contracts only: Supabase auth (`signInWithPassword`, `signUp`,
`resetPasswordForEmail`, `updateUser`, `signOut`); transfer RPCs (`mark_transfer_sent`,
`mark_transfer_viewed`, `set_transfer_delivery_info`, `buyer_dispute_transfer`) + the
`confirm-and-release` edge function; the `proof-docs` bucket; `listings` read/update/delete +
`cancel_listing` RPC; `auction-media` bucket cleanup. No schema, RLS, RPC, edge function, or money/
auction/transfer architecture touched. No `kernel.tickets` query; no venue-primary/direct-issuance UI
(093 still off). Standing blockers unchanged: no stable error-code vocabulary; `kernel.tickets` SELECT
absent.

## 25. Settings subroutes still pending

Phase 6 redesigned only the Settings hub. Nine subroutes remain visually legacy and are **not** touched
here: `edit-profile`, `notifications`, `preferences`, `blocked-users`, `payout-setup`, `verify-phone`,
`support`, `legal`, `privacy`. Recommended as a future dedicated account-settings batch (they carry
their own persistence logic — e.g. preferences' save-error handling — that must be preserved when
restyled).

## 26. Global nav / Tickets readiness

`docs/product-v2/NAVIGATION_V2_DIRECTION.md` records the approved long-term direction: the five-
destination model (Home · Create · Bids · Tickets · Profile), Search inside discovery, the Home-only
scroll-collapse dock (full → compact-Home on scroll-down, restore on scroll-up), the sharp Snatch It
dock character (no DICE/Posh copying), BIDS-vs-TICKETS product split, the Tickets HARD BLOCK on the
canonical contract, and the Profile/event-history direction. **Nothing was implemented** — the
adaptive dock and Tickets are each their own future batch. Every Phase 7 screen is a
predictable-navigation utility context, so it slots into that model unchanged.

## 27. Recommended next three-screen batch

1. **Settings subroutes — group A** (`notifications`, `preferences`, `blocked-users`) — the
   persistence-bearing account screens, closing the Settings hub loop.
2. **Settings subroutes — group B** (`edit-profile`, `payout-setup`, `verify-phone`) — identity +
   payout/verification, adjacent to the approved Profile.
3. **Static/legal** (`support`, `legal`, `privacy`) — low-risk content screens to finish the account
   area — *or*, if the owner prefers, pivot to the **Global adaptive-navigation batch** now that the
   direction is documented and all transactional surfaces are V2.
