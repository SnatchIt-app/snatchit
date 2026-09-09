# Phase 12 — V2 frontend hardening pass

**Session:** Front End · **Date:** 2026-09-04
**Branch:** `frontend/v2-phase12-hardening` (from the Phase 11 checkpoint).
**Status: OWNER-APPROVED on physical iPhone (2026-09-04) and checkpointed.** No push, no PR. Frontend-only.

Not a feature phase. The approved V2 product and visual identity are frozen; only objective
defects (accessibility, Dynamic Type, responsive, reduced-motion, safe-area, keyboard) are fixed.

## 1. Base SHA
`1b137b1d6f93a8f85341b76bad19d5d3cfe5df49` — `feat(frontend-v2): add tickets ownership experience`
(Phase 11, owner-approved).

## 2. Branch
`frontend/v2-phase12-hardening`, cut from `1b137b1`. No rebase, no push, no PR.

## 3. Route inventory (30 reachable user-facing surfaces)
Enumerated from `app/**` (excluding `_layout` ×N, `_dev/foundation`, and the `(tabs)/index` redirect).

- Auth (3): `(auth)/login`, `(auth)/signup`, `(auth)/reset-password`
- Primary tabs (6): `(tabs)/home`, `(tabs)/explore` (Search, pushed from Home — not a dock tab),
  `(tabs)/create`, `(tabs)/bids`, `(tabs)/tickets`, `(tabs)/profile`
- Listing/commerce (5): `listing/[id]`, `listing/edit/[id]`, `bid/[id]`, `checkout/[id]`, `my-listings`
- Profile/safety (2): `profile/[id]` (public), `report/[type]/[id]`
- Settings hub + 9 subroutes (10): `settings/index`, `edit-profile`, `notifications`, `payout-setup`,
  `verify-phone`, `preferences`, `support`, `legal`, `privacy`, `blocked-users`
- Transfer (2): `transfer/receive/[id]`, `transfer/send/[id]`
- Payout (2): `payout-return`, `payout-refresh`

Total = 30. Legacy reachable screens remaining: 0 (no non-V2 theme import in any reachable screen).

## 4. Audit methodology
Static, code-level audit across three dimensions run in parallel, then triage to OBJECTIVE defects
only (a preference-level restyle is explicitly not a defect):
- Accessibility + touch targets (roles/labels/state, icon-only controls, hitSlop, color-only status).
- Dynamic Type + responsive (fixed heights that clip enlarged text, essential-text truncation,
  hardcoded widths / horizontal overflow, dock clearance, event-title handling on small/large viewports).
- Reduced motion + safe area + keyboard (every `Animated` usage vs `useReducedMotion`; header/bottom
  insets and double safe-area padding; keyboard avoidance and reachable submit).
Verification: full vitest suite, `tsc --noEmit`, `expo lint`, and the native iOS metro bundle. The
Oswald display line-height safety floor (`safeLineHeight`) is preserved and never reduced to reclaim
space.

## 5. Accessibility findings
The V2 primitives (`Button`, `IconButton`, `Chip`, `Badge`, `Sheet`, `MediaUpload`, `EventMedia`,
`SettingsRow`, `AdaptiveDock`) are already exemplary: correct roles/labels/state, `hitSlop` to 44pt,
word-bearing status (never color-only), decorative-image handling. **No P0s. No sub-44pt icon-only
control lacks a compensating `hitSlop`.** Defects were concentrated in the transfer-flow legacy
components and a few disclosure/error controls: unlabeled delivery-form inputs and submit; the shared
`ScreenState` retry with no name/`busy`; the "Tips" and "Key Terms" disclosures with no
`accessibilityRole`/`expanded`; a public-profile thumbnail double-read; and a `SellerListingCard` that
announced only the event name (dropping status + price).

## 6. Accessibility fixes
- `ScreenState` retry: `accessibilityRole="button"`, label "Retry", `accessibilityState.busy` (shared —
  fixes the gap on every offline/error surface at once).
- `DeliveryInfoForm`: `accessibilityLabel` on the email and phone inputs; the submit gains role, label
  "Save delivery info", and `{disabled, busy}`.
- `PlatformInstructions`: the Tips toggle gains role/label + `{expanded}`; the decorative header icon is
  hidden from VoiceOver.
- `settings/legal`: the "Key Terms Summary" disclosure gains role + `{expanded}`; the privacy-policy
  link gains `accessibilityRole="link"` + label.
- `SellerListingCard`: composed one spoken label (event, status badge, bid/price).
- `ErrorBoundary` "Try again": role + label. `profile/[id]` list thumbnail: marked `decorative` to stop
  a double read inside the already-labeled row.

## 7. Touch-target findings / fixes
No fix required. Every icon-only control audited (dock tabs, `IconButton`, back/close, media
remove/replace, chips, steppers) already meets 44pt directly or via `hitSlop` (e.g. `Button` `sm` is
36pt + `hitSlop:6`, steppers are 52pt). Recorded as verified.

## 8. Dynamic Type findings
`allowFontScaling` is disabled nowhere (good), and event titles are never force-uppercased (they use
the `title` token). The real gap was systemic: `MAX_DISPLAY_FONT_SCALE` was exported but consumed
nowhere, and the shared primitives locked a FIXED `height` around scalable labels — so at large iOS
text the labels clip in `Button` (every CTA), `Badge` (status/ownership/fulfillment words — the whole
point of the component), `Chip`, `Input`, and the Place-bid quick chips.

## 9. Dynamic Type fixes
- `Button`, `Badge`, `Chip`, `Input`, Place-bid quick chips: `height → minHeight` (+ modest
  `paddingVertical`) so the control grows instead of cropping; identical at normal text size.
- `maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}` applied to the uppercase chrome labels (`Button`,
  `Badge`, `Chip`) and the Place-bid stepper glyph (fixed 52pt square), capping chrome growth while
  body/title text keeps scaling. The Oswald `safeLineHeight` floor was NOT touched.

## 10. VoiceOver findings
The primary journeys (Launch→Home→Listing→Checkout; Home→Search→Result→Listing; Home→Create;
Home→Bids; Home→Tickets; Home→Profile→Settings; My-Listings→Edit; Transfer) read in a logical order.
The only broken reads were the unlabeled/duplicate controls in §5, now fixed. No new nested-accessible
wrappers were introduced.

## 11. Small-device findings
The one objective break: `explore` results hardcoded `paddingBottom: 96`, less than the floating dock's
clearance, so the last result row was covered. The checkout sticky pay bar hand-rolls its row layout
instead of the shared `StickyBar` (narrow-width crush risk at large text) — materially mitigated now
that the shared `Button` caps its label and grows vertically. Everything else (cards, rows) already uses
`minWidth:0` / `flexWrap` / `flexShrink` protection.

## 12. Small-device fixes
`explore` now uses `useDockClearance()` for its list `paddingBottom` (matching Home/Bids/Tickets/
Profile). The Dynamic Type `minHeight` + font-cap changes also make the SE layout robust at enlarged
text.

## 13. Large-device findings
No defects. Full-bleed heroes and grids scale by measured width (`EventMedia` `fluid`); no fixed
content width leaves broken blank space; the dock is centered by its own geometry. iPhone-only scope
preserved — no tablet/landscape work introduced.

## 14. Large-device fixes
None required.

## 15. Safe-area findings
Clean. All headers apply `insets.top`; all bottom CTAs clear the home indicator via `StickyBar`
(`space.md + insets.bottom`) or the checkout bar's own inset; the primary tabs pad by `dockClearance`;
no double `SafeAreaView`+manual-inset stacking. The only gap was `explore` (§11), now fixed.

## 16. Keyboard findings
Auth, edit-profile, listing/edit, report, and Create already wrap correctly (KAV +
`keyboardShouldPersistTaps`, Create lifts its CTA with `useCtaDockOffset`). Three forms were missing
keyboard avoidance: `settings/verify-phone` (OTP CTA behind the number pad), `transfer/receive`'s
`DeliveryInfoForm` (required buyer gate), and the shared bottom `Sheet` (used by Create's neighborhood /
platform pickers — iOS Modals do not auto-avoid the keyboard).

## 17. Reduced-motion findings / fixes
**No defects — nothing changed.** Every `Animated` path already respects `useReducedMotion`
(`AdaptiveDock` collapse/expand width-morph + row-translate + keyboard-drop all gate `duration` on the
live reduce-motion flag; `press.ts`, `OutbidToast`, `Skeleton`, `Spinner` all short-circuit; `Sheet`
uses the OS `Modal` slide which honors reduce-motion natively). No spatial travel animates
unconditionally, the dock included.

## 18. Contrast findings
Code-level review surfaced no objective contrast defect: status is always word-bearing, `muted`/`faint`
tokens are used only for non-critical metadata, and black-on-red / white-on-black are the brand
signatures. No token was changed. (Instrumented per-pixel ratio measurement is a device-review item.)

## 19. Image / media findings
`EventMedia` remains the single media path (crop/fit/backdrop/fallback, storage-path resolver, 4:5
discovery). No URL is built by hand anywhere. The only change was marking one duplicate thumbnail
`decorative` (§6). Missing/portrait/landscape/dark/bright/failed artwork all render through the existing
fallback and fit modes.

## 20. Loading / error / empty findings
Every async surface distinguishes loading / success-with-data / success-empty / retryable-error, and
auth failure where relevant (Tickets, Bids, Home, Profile, transfers, Search). No new product copy was
added; the only change was accessibility on the shared retry control.

## 21. Explore / Search review status
**Prepared for a dedicated owner device pass.** It is not redesigned. The dock-clearance defect (§12)
is fixed. Search is confirmed to live inside Home and to NOT be a primary dock destination
(`navItems` excludes it; guarded by test). States to review on device: initial, typing, results, no
results, loading, error, long title, missing artwork, keyboard open, small/large device, Dynamic Type.
No backend search ranking/query/filter change was made.

## 22. Nav integrity
Final primary order `HOME · CREATE · BIDS · TICKETS · PROFILE` intact; Search inside Home; no hidden
duplicate tab; selected states and auth redirects unchanged. The AdaptiveDock geometry, glass,
animation, capsule, thresholds, and safe-area math are untouched (guarded by the adaptive-nav tests).

## 23. Files changed
Primitives: `src/components/ui/Button.tsx`, `Badge.tsx`, `Chip.tsx`, `Input.tsx`, `Sheet.tsx`,
`ScreenState.tsx`. Screens/components: `app/(tabs)/explore.tsx`, `app/settings/verify-phone.tsx`,
`app/settings/legal.tsx`, `app/transfer/receive/[id].tsx`, `app/profile/[id].tsx`,
`src/screens/PlaceBidScreen.tsx`, `src/components/DeliveryInfoForm.tsx`,
`src/components/PlatformInstructions.tsx`, `src/components/SellerListingCard.tsx`,
`src/components/ErrorBoundary.tsx`. Tests/report: `tests/hardening.test.ts` (new),
`docs/product-v2/PHASE_12_FRONTEND_HARDENING_REPORT.md`.

## 24. Defect-to-change table

| File | Defect | Why a defect | Change | Visible impact | Owner review |
| --- | --- | --- | --- | --- | --- |
| ui/Button.tsx | Fixed `height` + unused scale cap | CTA labels clip at large text | `minHeight` + `paddingVertical` + `maxFontSizeMultiplier` | Buttons grow (not clip) at large text; identical at normal | No |
| ui/Badge.tsx | Fixed `height:20` | Status/ownership words clip at large text | `minHeight` + `maxFontSizeMultiplier` | Badges grow to fit their word | No |
| ui/Chip.tsx | Fixed `height:32` | Chip label clips at large text | `minHeight` + `maxFontSizeMultiplier` | Chips grow at large text | No |
| ui/Input.tsx | Fixed `height:50` | Entered text/caret clip at large text | `minHeight` | Field grows at large text | No |
| (tabs)/explore.tsx | Hardcoded `paddingBottom:96` | Dock covers last result row | `useDockClearance()` | Last row clears the dock | Yes (Search pass) |
| ui/Sheet.tsx | Modal has no keyboard avoidance | Search field/rows hide behind keyboard | wrap in `KeyboardAvoidingView` | Sheet lifts above keyboard | No |
| settings/verify-phone.tsx | No KAV | OTP CTA behind number pad | wrap in `KeyboardAvoidingView` + `on-drag` | CTA reachable with keyboard up | Yes |
| transfer/receive/[id].tsx | No KAV | Delivery submit behind keyboard | wrap in `KeyboardAvoidingView` + `on-drag` | Submit reachable with keyboard up | Yes |
| ScreenState.tsx | Retry unlabeled, no `busy` | Screen reader hears an unnamed control | role + label + `busy` | VoiceOver names Retry / announces busy | No |
| DeliveryInfoForm.tsx | Inputs + submit unlabeled | Fields announce only placeholder; submit unnamed while saving | labels + submit role/label/state | VoiceOver labels each field + submit | No |
| PlatformInstructions.tsx | Tips toggle no role/expanded; icon noise | Disclosure state invisible; emoji read as noise | role/label/`expanded`; icon `decorative` | VoiceOver states Tips expanded/collapsed | No |
| settings/legal.tsx | Key Terms toggle + privacy link no semantics | Disclosure state/link invisible | role/`expanded`; link role | VoiceOver states expanded; link is a link | No |
| SellerListingCard.tsx | Label only event name | Status + price dropped for VoiceOver | composed label | VoiceOver announces status + price | No |
| ErrorBoundary.tsx | Try-again no role | Crash-fallback control un-roled | role + label | VoiceOver names Try again | No |
| profile/[id].tsx | Thumbnail not decorative | Double read in a labeled row | `decorative` | One clean read per listing row | No |
| PlaceBidScreen.tsx | Quick chips fixed `height:40`; stepper glyph uncapped | Chip label clips; glyph overflows 52pt box | `minHeight`; glyph `maxFontSizeMultiplier` | Chips grow; +/- stays in its box | No |

## 25. Tests
Full suite **595 passed / 25 files** (was 586 / 24). New `tests/hardening.test.ts` (9) guards the
font-scale cap consumption, `minHeight` on primitives, explore dock clearance, the three KAV wraps, and
the a11y labels/state. No existing test weakened.

## 26. Typecheck
`tsc --noEmit` clean (exit 0).

## 27. Lint
`expo lint`: 27 problems, 0 errors, **27 warnings** — identical to baseline. No new warnings.

## 28. Native iOS bundle
`platform=ios` bundle: **HTTP 200, ~14.6 MB**, no unresolved-import/error banner.

## 29. Core-owned files changed
**None.** No `supabase/**`, `money.ts`, `payments.ts`, `supabase.ts`, `secureStorage.ts`, `venue/**`,
`packages/**`, `.github/workflows/**`, `scripts/**`, `app.json`, or `eas.json` touched.

## 30. Blocked features untouched
No Ticket Detail, QR/barcode, scanner, entry credential, Apple Wallet/PassKit, live issuance,
notification feed, or new marketplace/social surface was added. No new product capability.

## 31. Physical-device status
**Physical iPhone runtime verified: YES. Owner approval: APPROVED (2026-09-04). Phase 12 status:
APPROVED.** Jose reviewed the hardening changes on a physical iPhone — the dedicated Explore/Search
pass, Dynamic Type normal vs enlarged (headings, badges, buttons, chips, inputs), SE-class and
Pro-Max-class layout, Tickets, Create with keyboard, Settings, and reduced-motion — and approved.

### 31a. Checkpoint record
- **Final verification at checkpoint:** 595 tests / 25 files passed; `tsc --noEmit` clean; `expo lint`
  27 problems / 0 errors / 27 warnings (no new); native iOS bundle HTTP 200.
- **Frozen (owner-approved):** the shared Button/Badge/Chip/Input Dynamic Type behavior, ScreenState
  a11y, Sheet keyboard avoidance, explore dock clearance, verify-phone and transfer/receive keyboard
  behavior, SellerListingCard VoiceOver composition, PlatformInstructions and legal disclosure
  semantics, public-profile decorative thumbnail, ErrorBoundary retry a11y, and Place-bid quick-chip
  Dynamic Type. No visual redesign, no dock geometry change, no new feature, no Core-owned change.
- **Checkpoint commit SHA** is recorded in the session completion response; the worktree is clean
  afterward except the two pre-existing unrelated stray docs (`FRONTEND_V2_CHECKPOINT_REPORT.md`,
  `PHASE_3_CHECKPOINT_REPORT.md`), deliberately excluded.

### 31b. Post-Phase-12 disposition of deferred / polish items
- **Checkout deferred P2 — no reproducible user-facing defect after Phase 12.** `CheckoutNative`'s pay
  bar still hand-rolls its row layout, but the price uses `PriceDisplay` (`flexShrink`/`minWidth:0`) and
  the action now uses the hardened shared `Button` (label capped at `MAX_DISPLAY_FONT_SCALE`, grows in
  height not width). At SE width + enlarged text the bar no longer crushes. This is now **architectural
  inconsistency, not a defect** — left unchanged (Checkout is owner-frozen); a StickyBar swap, if ever
  wanted, belongs in a future owner-approved micro-phase. Rank: **NONE (no user-facing defect)**.
- **profile stat value truncation** — a secondary dashboard figure truncates only at the largest text
  on a narrow column; not on any task path. Rank: **POLISH**.
- **ProofImageViewer zoom affordance** — the double-tap-zoom is undiscoverable to VoiceOver, but the
  proof image is viewable and the close control is labeled; no flow blocked. Rank: **POLISH**.
- **PlatformInstructions step-number digit** — can crowd its 22pt circle at extreme scale; the step
  text beside it still reads. Rank: **POLISH**.

### 31c. Post-Phase-12 frontend readiness
Every reachable user-facing surface (30) is V2 and hardened; no objective P0/P1/P2 defect remains
(the one deferred P2 resolved to no user-facing defect). Only three POLISH items remain, none blocking.
All feature-shaped work is Core-blocked. **Recommendation: FRONTEND V2 COMPLETE — WAIT FOR CORE.**
A tiny optional POLISH micro-phase (the three items above) is available if the owner wants it, but is
not warranted on its own.

## 32. Remaining issues ranked
- **P0:** none.
- **P1:** none remaining.
- **P2:** `CheckoutNative` sticky pay bar still hand-rolls its row layout rather than the shared
  `StickyBar` (narrow-width crush) — materially mitigated by the `Button` primitive fix; a full swap is
  deferred because Checkout is owner-frozen and the swap risks a visual change without device review.
- **Polish:** `profile.tsx` stat value truncates at large text on a narrow column; `ProofImageViewer`
  double-tap-zoom affordance is not announced; `PlatformInstructions` step-number digit can crowd its
  22pt circle at very large text. None gate a flow.

## 33. Recommendation
**REVIEW REQUIRED.** The pass fixed every objective P1/P2 accessibility, Dynamic Type, responsive, and
keyboard defect with no visual change at normal settings, no Core-owned change, and no new warnings; it
is ready for the owner's physical-iPhone review (with the dedicated Explore/Search pass). The remaining
items are one deferred P2 (checkout bar, mitigated) and three polish items — none blocking.

