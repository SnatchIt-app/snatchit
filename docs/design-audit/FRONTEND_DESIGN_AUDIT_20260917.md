# Snatch It — frontend design audit (B, 2026-09-17)

**Owner assignment:** a comprehensive design audit of every screen, a coherent improvement plan, a visual system, a
motion specification, and before/after proposals for the three highest-impact screens. **B owns the audit and the
proposals only.** C keeps handset testing and every active frontend fix; A keeps integration. Nothing here is a product
change, and no file outside this branch is touched.

## 0. Method, pins, and how evidence is labelled

| Label | Means |
|---|---|
| **[source]** | Read from the repository at the pin below, with `file:line`. |
| **[rendered]** | Produced by B locally in a browser at phone width from B's own mockup, with synthetic data. Not the app. |
| **[proposal]** | B's recommendation. Not a decision, not an owner ruling. |
| **[reported]** | Someone else's observation (C's records, A's reads, the owner's screenshots). Named, never adopted as B's own. |
| **UNVERIFIED VISUALLY** | B has not seen it on a device or in a simulator. **B has run no handset check and claims none.** |

**Pins.** Audit tree: `design/frontend-audit-20260917` off `release/production-gate-20260918 @ 6561d1f` (worktree
`/Users/josetascon/snatchit-audit`). **The handset's Build 19 is `f412d10`** (tag `candidate/2026-09-18-build-c3`) [reported, C];
`6561d1f` = `f412d10` + `accb40c` (F-BIDS-1, the Bids loading/failure states). So where this audit reads the Bids screen it reads
the **fixed** version, which the owner's phone does not yet run — every Bids finding says which tree it applies to.

**Already settled — presented as settled, not re-litigated** [reported, C]: rulings A-01…A-17 and findings F1…F10 in
`docs/product-v2/PREMIUM_EXPERIENCE_BACKLOG.md` (`frontend/premium-experience-backlog @ 653aa9f`) · the SANDBOX badge's fixed
20 pt and `useTopInset()` as the way every stack header clears it (F-SELL-2) · `MAX_DISPLAY_FONT_SCALE` 1.3 on chips, buttons
and badges · the state-view copy in `src/lib/ui/loadState.ts`, reviewed by the owner on Build 17 and again this sprint.
**Not settled, and therefore not treated as direction:** ML-1, the My Listings redesign — the owner approved the layout
direction and rejected the visual treatment; C's calmer v2 preview awaits the owner, and two ML-1 questions (whether the
calmer empty/error type changes the shared state component app-wide, and single- versus multi-line event names) are the
owner's. This audit's My Listings proposal therefore **defers to C's pending option** instead of competing with it.

**Authority for the app's visual direction** [reported, C]: `docs/product-v2/DESIGN_SYSTEM_V2.md` and `src/theme/v2.ts`
(the tokens that actually render), with `src/theme/typography.ts` and `src/theme/fonts.ts`; then
`docs/product-v2/NAVIGATION_V2_DIRECTION.md`, `EVENT_MEDIA_SYSTEM.md`, `ADVERSARIAL_UI_REVIEW.md` and the phase reports.
`docs/brand/` and the web brand-system document are marketing and web, cited as context only.

## 1. The finding that shapes the plan: the old UI is not spread out, it is concentrated

**[source]** Of the app's screen and component files, **66 import the v2 tokens and exactly 7 still import the legacy
theme** (`from '@/src/theme'`), with **no file importing both**:

| Legacy-token component | Used by | Consequence |
|---|---|---|
| `src/components/PlatformInstructions.tsx` | `app/transfer/send/[id].tsx`, `app/transfer/receive/[id].tsx` | the largest panel on both transfer screens is styled outside the system |
| `src/components/DeliveryInfoForm.tsx` | `app/transfer/receive/[id].tsx` | the buyer's only input on that screen |
| `src/components/ProofImageViewer.tsx` | `app/transfer/receive/[id].tsx` | how the buyer sees the proof |
| `src/components/PriceDisplay.tsx` | `src/screens/checkout/CheckoutNative.tsx`, `src/screens/ListingDetailScreen.tsx`, `src/components/ui/StickyBar.tsx`, `src/components/listing/TransactionPanel.tsx` | the price, on the two screens where money is decided |
| `src/components/VerifiedSellerBadge.tsx` | `src/components/SellerListingCard.tsx`, `src/components/listing/SellerTrustRow.tsx` | trust signals on listing surfaces |
| `src/components/StatCardStrip.tsx` | **nothing** | dead |
| `src/components/TransferStatusBadge.tsx` | **nothing** (superseded by `transferStatusMeta` + `Badge`, `src/lib/transfer/transferState.ts:46`) | dead |

That is the audit's central fact: **the redesign is not "the app looks old", it is "five live components and one flow were
left behind"** — and they sit precisely on the transfer/proof path and the money path. Two more are dead code. Nothing about
the 66 v2 screens needs novelty for its own sake.

## 2. Send Transfer — the screen the owner singled out

`app/transfer/send/[id].tsx` (490 lines). **[source]** Render order for a `pending` transfer, top to bottom:

| # | Block | Lines | What it competes with |
|---|---|---|---|
| 1 | "Send tickets to" — buyer email/phone | 288-291 | — |
| 2 | Warning box "Delivery info not yet provided" (conditional) | 292-299 | first coloured surface on screen |
| 3 | `PlatformInstructions` — icon, title, estimated time, numbered steps card, amber warnings box, collapsible Tips | 302-304 (component: `PlatformInstructions.tsx`) | **the largest block on the screen**, legacy tokens |
| 4 | Expiry chip — "Xh to send" or "Transfer window expired" | 306-313 | second/third coloured surface |
| 5 | Transfer summary — Event, Buyer, Method + status badge | 315-325 | — |
| 6 | Proof control + attestation line + blocked line + **Mark as sent** | 326-348 | **the only action, last** |

### 2a. Information order: the task is last and the explanation is first
The seller arrives to do one thing — transfer the tickets on the ticket platform, then record that here. The screen opens
with the recipient, then a warning, then a full instructional panel, then a countdown, then a summary, and only then the
proof control and the CTA. **[proposal]** invert the middle: recipient → **action block (proof + CTA)** → collapsed
instructions → summary. Instructions matter once, on the first visit; the action matters on every visit, including the
retry after a failed attempt, where today the seller must scroll past everything they have already read.
**UNVERIFIED VISUALLY:** how far below the fold the CTA sits on the owner's device, at default and at largest text.

### 2b. One condition, three voices; another condition, none
Missing delivery info is announced **three times**: the warning box (292-299), a line above the CTA (344-346) and the
disabled CTA itself (347). Expiry gets the opposite treatment: the chip says "Transfer window expired" (309) while the
CTA stays **enabled** — `disabled={busy || refreshing || buyerDeliveryMissing}` (347) does not include expiry.
**[source]** and the server agrees with the button, not the chip: `mark_transfer_sent` has no `expires_at` check
(migration 140), so until the every-2-minute sweep flips the row to `expired`, marking sent still succeeds; after it,
the same tap raises "Transfer cannot be marked as sent from current status: expired."
**[proposal]** say the true state in one place each: delivery missing → one notice that owns the CTA's disabled reason;
expiry → a state the screen commits to, either "the window has passed, you can still send until the system closes it" (what
the code does) or a disabled CTA (what the chip implies). The owner's instruction is that expiry is a functional state to
communicate, not to hide — today it is communicated in a way the button contradicts.

### 2c. The attestation is body text
"I have transferred the ticket(s) to the buyer using the instructions above." (341-343) is the seller's declaration, rendered
as a grey sentence between the upload control and the button. **[proposal]** either make it the CTA's own line ("Mark as
sent — I have transferred these tickets") or a real checkbox; a claim that carries dispute weight should not look like a hint.

### 2d. Seller-facing versus buyer-facing instructions
`PlatformInstructions` takes `role` and renders `instruction[role]`, but its **warnings block is shared**: `const { warnings }
= instruction` (`PlatformInstructions.tsx:50`), so both parties see the same amber warnings, and `info.tips` (`:89`) is collapsed by
default for both. **[proposal]** warnings should be role-scoped like steps and titles; a seller does not need the buyer's
cautions on the screen where they are trying to send.

### 2e. Prominence, measured in styles
**[source]** `PlatformInstructions` renders its steps in a bordered card (`stepsCard`, `bgCard` + `border`), its warnings in
an amber panel (`rgba(251,191,36,0.10)` on `colors.warning`), and the tips as a disclosure — three surfaces inside one
block, all above the action. The screen's own warning box and expiry chip add two more coloured surfaces. Five decorated
surfaces compete before the seller reaches a single primary button.

### 2f. The fold, measured
**[rendered]** B rebuilt both versions as HTML at 375×812 from the source block order
(`docs/design-audit/prototypes/send-transfer-before-after.html`) and measured them in a browser:

| | Content height | Primary CTA starts at | Ends below the fold by | Decorated surfaces |
|---|---|---|---|---|
| Current order | **1093 px** in an 810 px frame | 1028 px | **268 px** | **6** |
| Proposed order | **810 px** (fits) | 399 px | — (visible) | **3** |

So a seller on a phone-sized viewport scrolls roughly 1.3 screens to reach the only button on the screen, and meets six
decorated surfaces on the way. **UNVERIFIED VISUALLY:** these are browser measurements of B's reconstruction with web fonts,
not iOS with the app's fonts, not Dynamic Type at its largest step, and not the real SANDBOX badge inset — all three make
the current order worse, not better, but the exact numbers on device are C's to observe.

## 3. Cross-cutting state gaps (the highest-value findings outside Send Transfer)

Inventory by B's subagent over all 36 routes and 7 screen modules; **the two most consequential claims were re-verified by
B directly in source** and are marked accordingly.

### 3a. Release-critical: Place bid renders a form built on a $0 floor after a failed read
**[source, B verified]** `src/screens/PlaceBidScreen.tsx:68-83`:
```
.then(({ data }) => { if (data) { setListing(...); setSelectedBid(data.current_bid + MIN_INCREMENT); } setLoading(false); })
```
`error` is never destructured and there is no `.catch`. Two failure modes follow:
1. A resolved-with-error read (the normal supabase-js shape for a failed query) leaves `listing` null, so
   `minNextBid(listing?.current_bid ?? 0, MIN_INCREMENT)` (`:83`) computes the floor **from zero** and the screen offers a
   bid form with a blank event name and a minimum derived from nothing. The server still validates the bid, so this is not a
   money defect — it is the app stating a price it does not know, which is exactly what C's own product truths forbid
   ("cached data never authorises a transaction", "a server reply asserts only what it says").
2. A thrown/rejected read never runs the handler, so `setLoading(false)` never fires and the screen holds its spinner.

**Priority: release-critical, and it belongs to C.** B proposes no patch here — the fix is one error branch plus the shared
`ScreenState`, in C's lane, and this audit does not touch their active work.

### 3b. ~~Checkout has no offline state at all~~ — **WITHDRAWN: this finding was wrong (§14)**
**What B published:** that `CheckoutNative.tsx` has zero occurrences of `useNetworkStatus`, `isNetworkError` or `offline`,
and therefore cannot tell a dead connection from a decline at the moment of payment.
**Why it was wrong:** the keyword count was right; the conclusion did not follow. The distinction is fully implemented under
other names, and B verified each line in source before accepting A's correction: `reconcileAfterSheetError()` returns
`'verified' | 'not_verified' | 'unreachable'` (`:569-585`); on `unreachable` it calls `setPaymentReady(false)`, so Pay is
**withdrawn, not re-offered**, and the buyer reads "We couldn't confirm your payment yet - Your last attempt may or may not
have gone through. Please don't pay again. We'll keep checking; you can also check now." with a **Check status** button
(`:851-858`). A sheet error is explicitly not proof of failure (`:508-519`, A-04), and `revalidateAgainstServer()` is
settled-first so Pay is never restored on the device clock alone. A has reclassified F-CHK-1 in the release records.

**What survives, narrower and not release-critical [source, B verified]:** on the **setup path**, before any Stripe sheet
exists, a transport failure falls to the final `else` of the catch at `:383-422` and yields `SAFE_PAYMENT_ERROR` - "We
couldn't start payment. Please try again." - the same copy as any unexpected server failure. The repository already owns a
transport classifier, `isNetworkPaymentError` (`src/lib/checkout/paymentErrors.ts:16`, copy "Payment connection timed out.
Try again."), used **only inside that file**; the setup path never consults it. That is a diagnosis gap on the pre-request
path, not a correctness defect, so its honest severity is **polish**. The discriminating test is still a transport failure
that is not a Stripe decline.

### 3c. Pull-to-refresh is missing exactly where recovery matters
**[source, inventory]** No `RefreshControl` on: `src/screens/ListingDetailScreen.tsx`, `app/(tabs)/explore.tsx`,
`app/transfer/receive/[id].tsx`, `app/profile/[id].tsx`, and all nine `settings/*` screens. The transfer **send** screen has
it (`:285`); the **receive** screen does not, so the buyer waiting for proof to appear has no way to ask again except
leaving and returning (it re-reads quietly on foreground, `:145-155`).

### 3d. Two error surfaces bypass the shared state component
**[source, inventory]** `app/transfer/send/[id].tsx:270` and `app/transfer/receive/[id].tsx:295` render a bare
`<Text>` for a failed load, while their offline branch uses `ScreenState`. Same screen, two different failure languages.

### 3e. Every header is hand-rolled
**[source, inventory]** Root and tabs both set `headerShown: false`, and each screen builds its own bar: `SettingsHeader`
(10 screens), `HomeHeader`, `ListingHero`, or an inline `View` + `IconButton` row (bids, tickets, profile, my-listings,
place bid, create, edit, checkout, both transfer screens). That is why F-SELL-2 had to apply `useTopInset()` to eleven
surfaces one by one: there is no single header to fix. **[proposal]** one `ScreenHeader` component, adopted screen by
screen, with the inset and the largest-text clearance solved once.

### 3f. The static legal surfaces are the largest unstyled text in the app
**[source, inventory]** `app/settings/legal.tsx` renders four sections plus a collapsible summary with roughly fourteen
subsections (`:148-300`); `app/settings/privacy.tsx` renders nine (`:55-159`). Neither implements any state. They are not
release-critical, but they are where the v2 type scale would pay off most per line changed.

## 4. Visual hierarchy: what fights for attention

The app has a real system — `src/theme/v2.ts`, consumed by **70 files** [source, B verified] — and its hierarchy rules are
sound: one display face that shouts (Oswald), one UI face that whispers (Inter), red reserved for action or attention,
square geometry, red-tinted hairlines instead of shadows (V2 defines **no shadow token at all**, and no screen uses one).
Where attention goes wrong, it is almost never the token layer. It is **three specific habits**:

**(a) Every notice is the same weight, so none of them ranks.** The transfer screens stack a bordered card, an amber panel,
a countdown chip, a status pill and a warning box, all at similar visual weight (§2e). Checkout adds a trust line, a hold
countdown, a price-change explanation and a breakdown footnote. Settings stacks a probe banner, a deletion banner and a
double-confirm block. Nothing tells the eye which one is load-bearing, because the system has **no notice hierarchy**: there
is `SecurityNoticeBanner` (fixed warning tone), `ListingStatusBanner` (tone prop), `StateView` (full-screen), and then
hand-rolled `View`s with a border. **[proposal]** one `Notice` primitive with exactly three ranks — *blocking* (owns the CTA's
reason), *advisory* (explains a state the user cannot change), *ambient* (metadata) — and a rule that **at most one blocking
notice renders per screen**.

**(b) The primary action is frequently the last thing on the screen.** Measured on Send Transfer: 268 px below the fold
(§2f). The same shape appears on Create listing (risk banner + commitment checkbox + review card above the CTA) and on the
receive screen (instructions + arrival prompt + release warning above Confirm). The v2 primitives already solve this —
`StickyBar` exists, with keyboard-aware bottom padding — but the transfer and create flows do not use it.

**(c) Type hierarchy collapses where screens hand-roll it.** `src/theme/typography.ts:27` states the rule: nothing reads
`v2.type.*` directly, everything calls `textStyle()`. Six files break it [source, agent; B verified two]:
`app/settings/legal.tsx` (~12 hand-written styles), `app/settings/privacy.tsx` (~9, byte-identical duplicates of legal's),
`app/profile/[id].tsx`, `app/(tabs)/profile.tsx`, `src/screens/PlaceBidScreen.tsx` (a raw 56 pt number), and
`app/settings/edit-profile.tsx`. These skip the font resolver and the 1.25 line-height floor that exists so Oswald's caps
do not clip — so they are the screens most likely to break at large text, which is exactly where the owner asked me to look.

**What the user should notice first, by screen type** [proposal]: on a *task* screen (send, receive, create, checkout,
place bid) — the action and its one blocker; on a *browse* screen (home, explore, tickets, bids, my listings) — the content
grid, with state copy only when there is no content; on a *settings* screen — the row they came for, never the banner above it.

**No enforcement exists.** `eslint.config.js` is 12 lines with **no `rules` key** [source, B verified], although
`DESIGN_SYSTEM_V2.md:249-250` and `UI_IMPLEMENTATION_PLAN.md:28` both require "a lint guard that fails the build on a raw
hex color or a non-zero radius outside the token files". That absence is why the seven legacy components survived the
migration invisibly, and it is the cheapest durable fix in this audit.

## 5. Screen-by-screen classification

**Keep as is** = no visual work; **Targeted polish** = swap to v2 primitives/tokens, fix one or two state gaps, no layout
rethink; **Substantial redesign** = information order or hierarchy has to change, not just styling.

| Area | Route / file | Class | Concrete reason (evidence) |
|---|---|---|---|
| **Transfer send** | `app/transfer/send/[id].tsx` | **Substantial redesign** | Action 268 px below the fold, six decorated surfaces, one condition stated three times and another contradicted by its own button (§2). Carries a legacy component. |
| **Transfer receive** | `app/transfer/receive/[id].tsx` | **Substantial redesign** | Three of the five live legacy components (`PlatformInstructions`, `DeliveryInfoForm`, `ProofImageViewer`); success is an `Alert` (`:219`); no pull-to-refresh on the screen where the buyer waits for proof; "By confirming, you release payment" sits below the instructions rather than on the action. |
| **Proof upload** | inline in send/create via `MediaUpload` | **Keep as is** | `MediaUpload` is a v2 primitive with correct border escalation and an error tone; F-IMG-1 already fixed the byte-level behaviour. Its *placement* is what §2 changes, not the control. |
| **Checkout** | `src/screens/checkout/CheckoutNative.tsx` | **Targeted polish** | The best-instrumented screen in the app (33 `textStyle()` calls, `pendingLabel` on every CTA, haptic success, hold countdown) with two real gaps: **no offline state at all** (§3b) and prices rendered by the legacy `PriceDisplay`. Do not redesign it — instrument it. |
| **Listing detail** | `src/screens/ListingDetailScreen.tsx` (1353 lines) | **Substantial redesign** | 23 `Alert.alert` calls — the most in the repo — for states newer screens render inline; raw `Haptics` import bypassing the four-meaning wrapper; only 2 `textStyle()` calls in 1353 lines; the only major screen without `useTopInset()`; legacy `PriceDisplay` + `VerifiedSellerBadge`. |
| **Place bid** | `src/screens/PlaceBidScreen.tsx` | **Targeted polish + release-critical fix** | The `$0`-floor defect (§3a) is a state fix, not a redesign; visually it only needs the raw 56 pt number moved onto the type scale. |
| **Home / search** | `app/(tabs)/home.tsx`, `app/(tabs)/explore.tsx` | **Targeted polish** | Home's structure is current (skeleton, four empty-copy variants, offline classify, refresh). Two gaps: the lazy chip fetches show `EmptyState` **while loading** and swallow errors into `console.warn` (`:213,233`), so a failed filter reads as "nothing here"; Explore has no pull-to-refresh. |
| **Tickets** | `app/(tabs)/tickets.tsx` | **Keep as is** | Quiet-refresh policy, offline classification, the dev-fixture caveat banner, `SectionList` grouping — this is the reference implementation. |
| **Bids** | `app/(tabs)/bids.tsx` (+ `accb40c`) | **Keep as is** | F-BIDS-1 already did the work: skeleton rows, inline refresh-failed notice above kept rows, error only when empty. **Note for the owner:** Build 19 (`f412d10`) does **not** contain it; `6561d1f` does. |
| **My listings** | `app/my-listings.tsx` | **Targeted polish — deferred to C** | ML-1 is open: the owner approved the layout and rejected the visual treatment, and C's calmer option awaits them. B adds only the two state gaps: delete/cancel have no busy state (repeat taps re-fire) and the card's affordances are bare `Tappable`s. |
| **Selling / create** | `src/screens/CreateListingScreen.tsx` | **Targeted polish** | Fully v2 except four invented risk-banner hexes (`:1089-1092`) with no `status.*` equivalent, and the CTA sitting under a risk banner + checkbox + review card. Use `StickyBar`. |
| **Edit listing** | `app/listing/edit/[id].tsx` | **Targeted polish** | Seven `Alert.alert`, including success-as-alert (`:131`); not-found is an alert rather than a state. The unsaved-changes guard (F-NAV-1) is current and stays. |
| **Onboarding / auth** | `app/(auth)/*` | **Targeted polish** | Step structure and disabled logic are sound; none of the three screens has an offline state, so a failed sign-in during a dead connection reads as a credential problem. |
| **Profile (own)** | `app/(tabs)/profile.tsx` | **Targeted polish** | Two off-scale font sizes and a synthetic weight; the avatar spinner clears **before** the database write (`:193` vs `:199`), so the last second of the upload shows no progress; zeros render as "—" instead of an empty state. |
| **Profile (public)** | `app/profile/[id].tsx` | **Targeted polish** | Three hand-rolled display styles; success-as-alert on block; no offline classification. Its "Seller history unavailable … not a record of zero sales" block is **exemplary** and should become the pattern elsewhere. |
| **Settings (index + 9 sub-screens)** | `app/settings/*` | **Targeted polish** | No loading state on the deletion probe; `blocked-users` hand-rolls its failure block and has no busy state on Unblock; `legal` and `privacy` hand-roll 21 type styles between them; none of the nine has pull-to-refresh. Settings **rows** are already a shared primitive and stay. |
| **Disputes / reporting** | `app/report/[type]/[id].tsx` | **Keep as is** | Correct loading label, disabled logic, unsaved guard, fineprint. The dispute path itself lives in receive and moves with it. |
| **Notices** | `SecurityNoticeBanner`, sandbox badge, env blocker | **Targeted polish** | The banner requests `fontWeight: '700'` over Inter_600 (`:53`), which asks iOS for a synthetic bold the font loader explicitly bans; and while it shows, the screen beneath pays its own top inset too, so the gap doubles (documented at `:22-26`). |
| **Crash screen** | `src/components/ErrorBoundary.tsx` | **Substantial redesign (tiny file)** | It imports **no theme at all**: `#111` canvas, a third red `#E63946`, `borderRadius: 12`, a 48 pt 🚧 emoji, and the repo's only `TouchableOpacity`. It wraps the whole app, so it is the one screen guaranteed to be seen at the worst moment. ~40 lines to bring onto `StateView`. |
| **Dev gallery** | `app/_dev/foundation.tsx` | **Keep as is** | `__DEV__`-gated; its own 11 raw font sizes are not shipped. |
| **Dead code** | `StatCardStrip`, `TransferStatusBadge`, `src/constants/theme.ts`, `components/haptic-tab.tsx` | **Delete** | Zero consumers each [source, B verified for the first two]. Deleting them removes a whole legacy palette from the repo. |

### 5b. Two findings C observed on the device, and one B found following them up
**[reported, C — the owner's Build 19 screenshots, 16:34 EDT, "Device D1"; B did not see the device]**
1. **"Transfer window expired" gates nothing.** This is the same defect B derived from source in §2b, reached independently
   from the other side: C observed the warning on screen while the button's real blocker was something else. Source and
   device agree, which is the strongest form this finding can take.
2. **The buyer reads as "Unknown".** `profiles.display_name` is NULL for the sandbox accounts, so the seller is told their
   buyer is "Unknown".
**[source, B verified]** following that up: there is **no shared display-name resolver**. Three surfaces, three behaviours:
`app/transfer/send/[id].tsx:321` → `buyer?.display_name || 'Unknown'` · `app/transfer/receive/[id].tsx:353` →
`seller?.display_name || 'Unknown'` · `app/(tabs)/profile.tsx:229` → `display_name ?? email.split('@')[0] ?? 'User'`.
**[proposal]** one `personLabel()` helper with a single ladder (display name → verified handle → "the buyer"/"the seller" by
role), and never the word "Unknown" about a counterparty a user is transacting with: on a transfer screen the role is known
even when the name is not.

## 6. The visual system, as a set of decisions rather than a repaint

The system exists and is good. What is missing is **six decisions that stop each screen from inventing its own answer.**
Each is small, and each removes a class of drift permanently.

| # | Decision | Today | **[proposal]** |
|---|---|---|---|
| 1 | **Notice ranks** | 4 mechanisms, no ranking (§4a) | One `Notice` primitive, three ranks — *blocking* / *advisory* / *ambient*. At most one blocking notice per screen, and it owns the CTA's disabled reason. `SecurityNoticeBanner` becomes its *blocking* instance. |
| 2 | **Action placement** | `StickyBar` exists, unused by the task flows | Every task screen puts its primary action in `StickyBar` (keyboard-aware padding is already built in, `StickyBar.tsx:55`), and instructional content goes below or behind a disclosure. |
| 3 | **Type: no hand-rolled styles** | 6 files hand-write `fontFamily + fontSize + lineHeight` (§4c) | `textStyle()` only, with two tokens added so the exceptions disappear: `displayNumeric` (the bid screen's 56 pt) and `glyph` (the 22 pt icon size each site currently invents). Then the lint guard below can be absolute. |
| 4 | **Largest text** | `MAX_DISPLAY_FONT_SCALE` applied at 11 usages, concentrated in `Button`/`Chip`/`Badge`/`PlaceBid`; every screen heading, `Input`, `StateView` title and list row is uncapped | Cap inside `textStyle()` for display tokens, so a screen cannot forget it, and keep `minHeight` (never `height`) on every control — `Button` already does this right. |
| 4b | **Sandbox-only vs production** | `useTopInset()` adds a fixed 20 pt on sandbox builds, and the badge itself is `allowFontScaling={false}` so its height never changes | **Sandbox-only:** the doubled gap while `SecurityNoticeBanner` shows (`:22-26`), and any 20 pt-related crowding. **Production:** everything else in this audit. Keep the two apart in every report; a sandbox-only gap is not a release blocker. |
| 5 | **Colour roles** | `status.error` ≠ `brand.red` is a genuinely good decision already in the tokens | Add the two missing roles the screens keep inventing: a *caution surface* (Create listing invented four hexes; `PlatformInstructions` invented an amber wash) and an *info surface* for advisory notices. Both as `status.*` fills at a fixed opacity, so no screen mixes its own. |
| 6 | **Enforcement** | `eslint.config.js` has no `rules` key at all | The guard both design docs already require: fail on raw hex, on non-zero radius outside the token files, on `fontWeight` in a project style, and on `fontSize` outside `theme/`. Land it **after** the polish batch, or it fails on code the audit is about to change. |

**Form controls, empty/error states and bottom navigation need no new direction.** `Input` (label required, underline only,
error tone), the three-layer `StateView`/`EmptyState`/`ScreenState` stack, and `AdaptiveDock` are current and consistent;
the dock's 33 pt radius is a **documented, approved exception** (`navInsets.ts:30-31` + `NAVIGATION_V2_DIRECTION.md`), not drift.

### 6b. Doc hygiene, worth ten minutes
`DESIGN_SYSTEM_V2.md:3` still says "proposal, pending owner approval. Nothing here is implemented yet" and
`UI_IMPLEMENTATION_PLAN.md:3` says "No UI work has been started", while **70 files import the v2 tokens** [B verified].
`src/theme/v2.ts:27` likewise says "Nothing imports it by default yet". Three stale status lines are how a future session
concludes the system is unapproved and starts a fourth one. Also worth recording as deliberate, not drift: `text.muted` is
0.55 rather than the doc's 0.45 **for a measured contrast reason**, and `textStyle()` floors line height at 1.25× so Oswald
caps cannot clip — both are code-wins-over-doc, and both are already argued in the code comments.

## 7. Motion specification

### 7a. The constraint that decides everything here
**[source, B verified]** `react-native-reanimated` **4.1.6** and `react-native-worklets` 0.5.1 are installed, but
**there is no `babel.config.js` in the repository** and no Reanimated/worklets Babel plugin in any config. The only
Reanimated reference in the app is a side-effect import (`src/providers/NativeAppShell.native.tsx:16`); no worklet has ever
executed, which `src/components/ui/press.ts:10-14` already says in as many words. `react-native-gesture-handler` 2.28.0 is
installed with **zero imports**. `expo-blur`, `expo-linear-gradient`, `react-native-svg` and any sheet library are **not
installed**.

**Therefore every recommendation below uses RN `Animated` with `useNativeDriver: true`, the existing
`usePressScale`/`usePulseOnChange` primitives, and the existing `v2.motion` tokens.** Adopting Reanimated would mean adding
a Babel config and proving worklets on device — a new build, which this audit is not authorized to make and does not need.

### 7b. What already exists and should not be rebuilt
`v2.motion` = `instant 90 / swift 180 / settle 280`, easing `cubic-bezier(0.22, 1, 0.36, 1)` (`v2.ts:158-169`) ·
press scale 0.98 at `instant` (`press.ts:26-47`, consumed by 8 components) · skeleton pulse 0.4↔0.7, 600 ms per leg, no
shimmer, by choice (`Skeleton.tsx:32-52`) · value-change pulse 350 ms (`usePulseOnChange.ts:27-40`) · outbid toast fade +
12 pt rise at `swift` (`OutbidToast.tsx:31-54`) · dock collapse 220 ms and keyboard drop 160 ms (`AdaptiveDock.tsx:68-95`) ·
`expo-image` crossfade at `swift` (`EventMedia.tsx:233`) · four haptic meanings (`src/lib/feedback/haptics.ts:30-54`) ·
**Reduce Motion is already honoured in nine places** through `useReducedMotion()` (`src/hooks/useReducedMotion.ts:16-30`),
including a static `• • •` instead of a spinner.

### 7c. Proposed motion, and only where it carries meaning

| # | Trigger | What it helps the user understand | Motion + duration | Reduce Motion alternative | Implementation / performance |
|---|---|---|---|---|---|
| M1 | A **blocking notice** appears or clears (delivery info arrives, window closes) | That the screen just changed its mind about whether they can act — today the button silently flips | Height+opacity reveal, `settle` 280 ms, brand easing | Instant swap, no transition | `Animated` on opacity + a measured height; **not** `LayoutAnimation` (it is global and would animate unrelated rows). One node, native driver for opacity only |
| M2 | **Proof image chosen or replaced** | That the new file replaced the old one rather than being added | Crossfade 180 ms (`swift`) on the thumbnail + press scale already present | Instant swap | `expo-image` already crossfades at `swift` (`EventMedia.tsx:233`); reuse the same prop on `MediaUpload`'s thumb. Zero new dependencies |
| M3 | **Primary action submitting** | That the tap was received and the wait is the server's | No new motion: `Button` already has `loading` + `pendingLabel`. Extend it to the four handlers that lack it (§8, P2) | n/a — a label change, not motion | Pure prop work |
| M4 | **Success on a task screen** (marked sent, proof attached, receipt confirmed) | That the thing is done, without a modal to dismiss | State block fades in at `settle` while the action row fades out at `swift`, plus the existing `hapticSuccess()` | Both instant; haptic unchanged | Two `Animated.View`s in one screen; replaces `Alert.alert` on the success path, which is the bigger win |
| M5 | **Pull-to-refresh completes with new data** | Which rows changed, instead of re-reading the list | Reuse `usePulseOnChange` (350 ms opacity dip) on changed rows only | Skipped entirely (the hook already does this) | Already built; needs a changed-key comparison, not new animation |
| M6 | **Sheet open/close** | Where the sheet came from | Keep RN `Modal` `animationType="slide"`, already fading under Reduce Motion (`Sheet.tsx:65-77`) | Already implemented | No sheet library needed; do not add one for this |
| M7 | **Navigation between task steps** | Continuity | Keep the stack default, already `'fade'` under Reduce Motion (`app/_layout.tsx:129`) | Already implemented | Nothing to do |
| M8 | **A failed action that keeps the screen** | That nothing was lost and they can retry | Notice reveal (M1) + the existing press scale. **No shake, no bounce** | Instant | Deliberately boring: error motion that draws the eye twice reads as a second failure |

**Explicitly not proposed:** skeleton shimmer (rejected in code, for good reason), spring/overshoot on presses, parallax
heroes, animated tab indicators, decorative gradient sweeps, and any motion on the checkout confirmation beyond what ships
today. Each would compete with content or delay a tap.

**Two motion gaps to close first, both tiny:** `ProofImageViewer` uses a raw `Modal` + raw `ActivityIndicator` with **no
Reduce Motion path** (it is the buyer's proof viewer, so it matters), and `AdaptiveDock` re-implements the Reduce Motion
probe with its own `AccessibilityInfo` ref instead of the shared hook — one divergent implementation is how the next one
starts.

## 8. Ranked improvements

### Release-critical (usability or correctness, before the next candidate)
| # | Item | Why now | Owner |
|---|---|---|---|
| **P1** | Place bid renders a bid form on a **$0 floor** after a failed read (§3a) | The app states a price it does not know, on the screen where a user commits money. One error branch + `ScreenState` | **C** |
| ~~**P2**~~ | ~~Checkout has no offline state~~ | **WITHDRAWN - the finding was wrong (§3b, §14).** What remains is a setup-path copy gap, demoted to polish as **P16** | - |
| **P3** | Send Transfer: expiry warning that gates nothing, one blocker stated three times, action below the fold (§2, corroborated on device by C) | The owner named this screen; it is also the screen the sandbox sequence is exercising right now | **C**, after the handset pass |
| **P4** | Actions with no busy state re-fire on repeat taps: Unblock, delete listing, cancel listing (§ inventory A.4 #1-3) | Delete and cancel are destructive and currently re-entrant | **C** |
| **P5** | Home's lazy filter fetches show "nothing here" **while loading** and swallow errors into `console.warn` | A failed filter looks like an empty marketplace | **C** |
| **P6** | Avatar spinner clears before the database write completes (`profile.tsx:193` vs `:199`) | The user sees "done" while a write is still in flight — the same class of claim the payments work spent weeks removing | **C** |

### Later polish (worth doing, not release-gating)
**P7** ErrorBoundary onto `StateView` (~40 lines; it is the crash screen users actually see) · **P8** retire the five live
legacy components, starting with `PriceDisplay` on the money screens · **P9** delete the two dead legacy components and the
dead constants shim · **P10** `legal`/`privacy` onto `textStyle()` (21 hand-rolled styles, zero behaviour risk) ·
**P11** one `ScreenHeader` to replace eleven hand-rolled bars · **P12** `personLabel()` so no seller is told their buyer is
"Unknown" · **P13** the `Notice` primitive and the three ranks · **P14** the lint guard, last, once the above have landed ·
**P15** the three stale doc status lines · **P16** the setup path's transport copy (what survived the withdrawn P2).

## 9. Implementation sequence, dependencies, acceptance criteria

| Stage | Contents | Depends on | Acceptance criteria (each provable locally, no device claim) |
|---|---|---|---|
| **S0** | P1, P2, P4, P5, P6 — the state fixes | Nothing. Each is one screen | For each: a test that fails on the current code and passes after (the negative control is the point, not the green run); `npm run typecheck`, `npm run lint`, `npm run test` all clean; no token or layout change in the diff |
| **S1** | P3 Send Transfer re-order, behind no flag but in one PR | S0 (so the screen is not moving while its states change); **C's handset pass finished**, since the sandbox sequence is using this exact screen | The six blocks render in the proposed order; exactly one blocking notice; the CTA's disabled reason comes from that notice; expiry copy matches what the server does; a rendered check that the CTA is above the fold at 375×812 and at `MAX_DISPLAY_FONT_SCALE` |
| **S2** | P7, P8, P9 — legacy retirement | S1 for the transfer screens' components | Zero files import `@/src/theme` except the token file itself; the two dead components and the constants shim are gone; `tests/premium-transfer-wording.test.ts` updated where it reads the dead badge |
| **S3** | P10, P11, P12 — typography, header, person label | S2 | No `fontFamily: v2.font.*` outside `theme/`; eleven hand-rolled headers replaced by one component with the inset solved once; one resolver, no "Unknown" about a counterparty |
| **S4** | P13 `Notice` primitive, then M1/M4 motion | S3 (the primitive needs the type and colour roles settled) | Three ranks exist; at most one blocking notice per screen (assertable in tests); every animation respects `useReducedMotion()`; no `LayoutAnimation`; no new dependency |
| **S5** | P14 lint guard, P15 doc status lines | S0–S4, or it fails on code in flight | The guard fails on a planted raw hex and a planted non-zero radius, and passes on the clean tree — demonstrated both ways |

**Dependencies that are not mine to schedule:** ML-1 (My Listings) waits on the owner's decision about C's calmer option;
141/F-NOTICE-1 changes what the Settings deletion banner should say, so P-level work on that banner waits for the server
decision; and nothing in S1 starts while the handset sequence is still on the Send screen.

## 10. Keep as is — what this audit protects

- **The v2 token layer** (`src/theme/v2.ts`) and `textStyle()`: the geometry, the two faces, the red-tinted hairlines, the
  no-shadow rule, `status.error` ≠ `brand.red`, and the argued-for 0.55 muted ink. 70 files already consume it.
- **The `ui/` primitive set**: `Button` (four variants, `minHeight`, `pendingLabel`), `Badge`, `Chip`, `Input`,
  `StateView`/`EmptyState`/`ScreenState`, `Sheet`, `StickyBar`, `Skeleton`, `Spinner`, `MediaUpload`, `usePressScale`.
- **`AdaptiveDock`**, including its approved 33 pt exception and its keyboard drop-out.
- **Reduce Motion support as built** — `useReducedMotion()` and its nine call sites, the static spinner, the still skeleton.
- **The state-copy layer** `src/lib/ui/loadState.ts` and the offline-vs-server-error distinction the owner reviewed twice.
- **Tickets, Bids (with F-BIDS-1), Report, and Checkout's instrumentation** — these are the reference implementations, and
  the audit's proposals are largely "make the rest look like these".
- **F-SELL-2's `useTopInset()`**, the fixed 20 pt sandbox badge, `MAX_DISPLAY_FONT_SCALE` where applied, and the
  `MIN_LINE_HEIGHT_RATIO` floor — all four are load-bearing accessibility work that a redesign must not undo.
- **Haptics restricted to four meanings**, each paired with a visible change.

## 11. Visual proposals (local, synthetic data)

**[rendered]** Two self-contained HTML files, reconstructed from source at `6561d1f` and measured in a browser at 375×812.
They are **not** screenshots of the app and no device check is claimed. The "before" frames reproduce the legacy components'
own declared tokens (`src/theme/index.ts`: `#0B0F14` canvas, `#E10600` red, 10 px radii, `#60a5fa` accent), which is why
they look like a different product — inside those components, they are.

| File | Screens | Measured |
|---|---|---|
| `docs/design-audit/prototypes/send-transfer-before-after.html` | Send Transfer, pending + delivery missing + window expired | before: 1093 px of content, CTA 268 px below the fold, 6 decorated surfaces → after: 810 px, CTA visible, 3 surfaces |
| `docs/design-audit/prototypes/receive-and-checkout-before-after.html` | Receive Transfer (buyer) and Checkout (offline) | receive before: 850 px content, first CTA at 730 px, 5 surfaces, success as a system alert → after: fits, action in a sticky bar, 3 surfaces · checkout: same layout both sides, offline state and `textStyle('price')` added |

Verified in-browser rather than by eye: both fonts load, no frame scrolls horizontally, every "after" surface has square
geometry (0 non-zero radii outside the pill allowance), the warning ink is exactly `#FFB020`, and the legacy frame renders
`rgb(11,15,20)` against the v2 frame's `rgb(0,0,0)`.

## 12. What B could not verify, and who can
- **Anything on a device.** No handset, no simulator, no screenshot of the running app was used. Every layout claim is either
  source-derived or measured in a browser reconstruction. **C owns device verification.**
- **Dynamic Type at its largest step, the real badge inset, and keyboard behaviour on Android** — all three need the app running.
- **Whether the owner's screenshots show something these files do not.** C holds the observations; the images are the owner's.
- **Whether ML-1's calmer treatment supersedes this audit's My Listings notes** — the owner's decision, pending on C's option.

## 13. Routing and confirmations from A (2026-09-17, after the audit was published)

- **P2 (checkout has no offline state) is a gated-surface item, not a visual one.** A owns pre-merge review of
  `src/lib/payments.ts`, `src/lib/checkout/{setupDecision,payControl,holdState}.ts` and any authoritative-state read, and
  classes this finding as payment correctness: *a server reply asserts only what it says, and a failure to reach the server
  asserts nothing at all.* **When it becomes a proposal it routes to A as well as C**, and A reviews it as correctness
  rather than styling. P1 (the bid screen's `0` floor) stays classified as a truthfulness defect, not a money defect, since
  the server still validates — A agrees with that classification.
- **`6561d1f` is confirmed as the audit head** by A, on the strength of the `f412d10..6561d1f` diff touching nothing under
  `supabase/`. The per-finding tree annotations stay, because the Bids fix is in `6561d1f` and **not** in the Build 19 the
  handset runs — A names this as the single place a reader is most likely to go wrong.
- **A records the Reanimated constraint as an integration fact:** any Reanimated-based proposal implies a Babel config
  change plus a new build to prove it, and no build is authorized. §7's use of RN `Animated` + `v2.motion` stands.
- **Also settled, per A, and not re-litigated here:** the v2 system is in force (its visual direction was approved for the
  admin analytics work), and the SANDBOX badge with the badge-aware header inset (F-SELL-2) was re-confirmed on Build 19.
- **Ownership of the two cleanups:** A asks that the dead code (`StatCardStrip`, `TransferStatusBadge` with the one test that
  reads it, `src/constants/theme.ts`) and the three stale status lines be **their own small change**, not folded into a
  polish batch. They stay P9 and P15 here; **B does not make them** — deleting components is a product change, and the two
  design docs belong to C's and A's records, not to this audit branch.


## 14. Correction: a wrong finding, and the method error behind it

**P2/F-CHK-1 as B published it was wrong.** A checked it instead of accepting it and produced the disproving lines; B then
verified those lines in source. §3b now carries the withdrawal and the much narrower finding that survives.

**The method error, stated plainly, because it is the same one this audit criticises elsewhere:** B ran
`grep -c "useNetworkStatus\|isNetworkError\|offline"` on one file, got 0, and published a behavioural conclusion labelled
**[source, B verified]**. What was verified was the grep, not the claim. The screen implements the distinction under its own
vocabulary - `reachable`, `verified`, `unreachable`, `checkUnreachable` - so the probe was looking for other screens'
words. **A keyword absence is not a behaviour absence**, and the rule this audit applies to tests applies to audit findings
too: state what would distinguish the claim, then go looking for that. A did exactly that and found the distinguishing code
already present.

Everything else in §3 was derived by reading the relevant code paths rather than counting keywords, and the two other
load-bearing items (§3a's discarded fetch error, §7a's absent Babel config) were re-verified line by line by B and again
independently by A. The failure was one finding's method, not the audit's, but the label **[source, B verified]** now means
less than it did, so §0's table gains this rule: that label is only used where B read the code path, never where B counted
occurrences.