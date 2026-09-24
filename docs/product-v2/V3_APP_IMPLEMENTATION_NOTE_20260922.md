# V3 revision — implementation-grounded note for B (C, 2026-09-22)

Read-only code investigation and design guidance, authorised by the owner. **No V3 change enters the production
safety package, and no app code changes until the owner approves the visual package.** All references are at the
current app target (gate `e191cbfa` + PR #81 `19b6fc2b` + PR #84 `131017a5`; combined reference tree `e079fcc1`,
app-identical to A's `integration/refund-payout-round-v3` @ `3da63d9b`). Build 22, the last phone-tested build,
is `05d85732`; its app code differs from the target only by the five files of #81/#84.

## 1. Display type — what actually exists
- **Faces shipped:** Oswald **700 only** for display; Inter 400/500/600/700 for body
  (`src/theme/fonts.ts:44-49`, `AVAILABLE_WEIGHTS` :65-68). Any other weight would be OS-synthesised — the type
  system deliberately prevents it. **Do not design display at other weights.**
- **Loading path:** per-weight imports from `@expo-google-fonts/*` (bundle-size rule at `fonts.ts:40-44` — never
  root imports), registered once via `useBrandFonts()` (expo-font `useFonts`) in the root layout, which holds the
  first frame; **on load failure every screen renders in the system face** (`fonts.ts:104-113`), so mockups must
  survive a system-font fallback without truncation that hides meaning.
- **Scale:** `displayXl 44 / Lg 34 / Md 26 / Sm 20`, all uppercase, tokens only via `textStyle()`
  (`src/theme/v2.ts:130-141`; rule at `typography.ts:28`). Oswald clips below a 1.25 line-height ratio on iOS —
  `MIN_LINE_HEIGHT_RATIO` (`typography.ts:58`) raises it automatically; **poster-tight leading below that is not
  achievable in React Native**, so don't draw it.
- **Enlarged system text:** display and price text is capped at `MAX_DISPLAY_FONT_SCALE = 1.3`
  (`typography.ts:123`), applied via `maxFontSizeMultiplier` on Chip/Badge/Button/price lines; body text scales
  freely. Mock titles at 1.3× before signing them off.
- **Long names:** list/detail titles use `numberOfLines` (e.g. checkout `numberOfLines={2}`). ACCEPTANCE:
  every V3 title mock shows the 2-line truncation case for a 60+ character event name at both 1.0× and 1.3×,
  in Oswald 700 and once in the system-face fallback.

## 2. "You" tab with the signed-in user's photo
- **Tab bar today:** `app/(tabs)/_layout.tsx` renders `AdaptiveDock` (`src/components/nav/AdaptiveDock.tsx`),
  items from `navItems()` (`src/lib/nav/navItems.ts:26-35`) — Profile = `{ label: 'Profile', icon: 'person.fill' }`,
  icons via `IconSymbol` (SF on iOS, Material on Android). Selected state = inner capsule + larger icon + primary
  colour; `accessibilityState={{ selected }}`, `accessibilityLabel={item.label}` (`AdaptiveDock.tsx:141-151`).
  The collapsed dock reuses the active item's icon (:162).
- **Photo source of truth:** `profiles.avatar_path` (public `avatars` bucket), resolved by
  `getAvatarUrl(path, {width, devicePixelRatio})` (`src/lib/avatarImage.ts:51`), rendered with `expo-image`.
  Fetched today by each screen via `rpc('get_my_profile')` (profile tab :115, home :74, edit-profile :54).
  **There is no shared profile store** — that is the gap the You tab must not paper over with per-render fetches.
- **Design contract:** the photo replaces only the glyph inside the existing Pressable; label ("You" is a
  `navItems.ts` data change), selected capsule, sizes, `accessibilityLabel`/`accessibilityState` all stay.
  Selected state must remain distinguishable with a photo present (ring/capsule, not colour-of-glyph).
  Fallback is the current `person.fill` icon whenever no photo is available for the CURRENT user.

## 3. Photo lifecycle (the criteria the mockups must not contradict)
Mechanism prepared (not built): a tiny module-level avatar store `{ userId, path } | null` with subscribe —
hydrated wherever `get_my_profile`/avatar writes already happen (profile tab load, edit-profile pick, home load),
never fetched by the dock itself.
- **Loading:** icon shows until a URL exists; no spinner in the dock.
- **Broken URL:** `expo-image` `onError` → icon fallback; no retry loop.
- **Replacement:** edit-profile already updates `avatar_path` on pick (`profile.tsx:206-209`); the store update
  rides that write. No polling anywhere.
- **Removal:** no removal UI exists today (`edit-profile.tsx` offers pick/replace only). The store treats
  `path: null` → icon, so removal works the day it ships; mockups should not promise a removal flow V3 doesn't add.
- **Sign-out:** cleared in `performSignOut`'s existing post-success cleanup (the `clearRegistration` slot,
  `signOut.ts:170,192` — same pattern, cleared only after sign-out succeeded).
- **Account switch:** the dock renders the photo **only when `store.userId === session.user.id`** — a render-time
  guard, so a previous user's photo cannot appear even if a clear was missed. ACCEPTANCE: sign out → sign in as
  another account shows icon (or the new user's photo) with no frame of the old photo.

## 4. Order / failure-state wording — the behaviour the copy must match
Canonical states already in the product (V3 wording must not blur them):
- **Locally unsent:** nothing left the device — e.g. Cancel in the confirm-receipt dialog
  (`CONFIRM_RECEIPT_DIALOG`, transferState.ts), a bid insert that returned an error. Copy may say the action
  didn't happen.
- **Submitted, result unknown:** the request went out and no answer established the result — checkout's
  `checkUnreachable` ("We couldn't confirm your payment yet … may or may not have gone through. Please don't pay
  again.", CheckoutNative), mark-as-sent `'unconfirmed'` → "Not confirmed yet" (markSent.ts:61). Copy must NOT
  claim the action failed, and **an unreachable server is never evidence that money did not move**.
- **Read unknown:** `payment_status_unknown` / reservation-unknown / `transferReadOutcome` 'unavailable' — neutral
  "couldn't check/load" + retry; never "not found", never a refund/cancellation claim.
ACCEPTANCE: every V3 failure string maps to exactly one of these three states; no string in the
submitted-unknown state asserts failure, refund, or safety to retry a payment. **B: send the V3 wording draft —
I could not locate it in the repos — and I'll review it line-by-line against these anchors.**

## 5. Excluded-result counts in search — not supported today
`explore.tsx:118-126` runs one PostgREST query (`status='active'`, `auction_status='active'`, `ilike`, `limit 40`)
with blocked sellers excluded **inside the WHERE** (`applyBlockedSellerFilter` → `.not('seller_id','in',…)`,
`useBlockedUserIds.ts:91-99`). Excluded rows are never fetched and never counted; the 40-row cap means a client
count would be wrong anyway. **Omit excluded-result counts from V3**, or explicitly propose the capability: a
second head/count request per search (with vs without exclusions) or a server RPC — a per-keystroke cost the
owner would have to accept. Do not mock a count the implementation cannot honestly produce.

## 6. Price labels — the four concepts and their bases
All four are distinguished today, but with **two different numeric bases** — V3 must keep the bases straight:
- **Current bid:** "Current bid" (all-in, `TransactionPanel.tsx:84-88`; "Starting bid" before any bid,
  "Final bid" when closed). Bids tab rows: `bidState.ts:169`.
- **Minimum next bid:** listing panel "Next bid from {all-in}" (`TransactionPanel.tsx:91-95`,
  `nextBidAllIn = allIn(current + increment)`, ListingDetailScreen:1137) — **all-in**; PlaceBid's
  "+$X per step · min $Y" (`PlaceBidScreen.tsx:255`) — **raw bid dollars**. Same concept, two bases; if V3 shows
  both on one screen it must label the base.
- **Proposed bid total:** "{total} total" with "includes the 10% service fee" (`PlaceBidScreen.tsx:314`,
  `bidEntry.ts:111`) — all-in.
- **Buy-now total:** "Buy now · {all-in}" (`detailState.ts:318`, `TransactionPanel.tsx:72`) — whole-listing
  all-in (whole-listing pricing is a product truth).
ACCEPTANCE: each mock price carries one of these four labels; no unlabelled number mixes raw-bid and all-in
bases on one surface; buy-now is always the whole-listing total.

## Bounded implementation plan (prepared; starts only on the owner's approval of the visual package)
One branch off the then-current gate, isolated from the production safety package; payment, reservation,
transfer and navigation behaviour untouched (dock routes, order, collapse behaviour unchanged).
1. `src/lib/nav/avatarStore.ts` (new, pure): `{userId, path}` store + subscribe; unit tests incl. user-switch
   and null-path cases.
2. Hydration: 3 call sites that already hold the data (profile tab, edit-profile, home) + sign-out clear via
   the existing deps slot. No new reads, no polling (tests pin: no `rpc(`/`from(` added to the dock).
3. `navItems.ts`: Profile label → 'You' (data change).
4. `AdaptiveDock`: render avatar (expo-image, `onError` fallback) when `store.userId === session.user.id`,
   else `IconSymbol person.fill`; capsule/selected/accessibility unchanged; collapsed control inherits the same
   rendering. Render tests: photo, fallback, broken URL, switch-user guard, selected treatment, a11y props.
5. Gates + mutants as usual; A reviews any gated-file contact (none expected), D reviews behaviour.
Out of scope until separately specified: photo removal UI, V3 fonts/search/pricing changes.

**Mockup review:** I review B's final mockups against the ACCEPTANCE lines above before recommending
implementation.

---

# V3 stage 2 — freeze consumed, home + search implemented (C, 2026-09-22, later session)

**Frozen reference:** `design/frontend-audit-20260917` @ `c95dae33` (freeze commit `77a122b4`), read in
order: freeze reconciliation → coverage matrix → packages → findings → gap audit. My matrix update with the
evidence below: `36105e30` on the same branch (pushed).

**Branch:** `v3/midnight-app` @ **`e2c564ce`** — commits this session: `3e66068a` (§3 formulas +
`feedRowState` vocabulary + the curve scrim RENDERING — a 15-stop CSS gradient via RN 0.81
`experimental_backgroundImage`, the mechanism EventMedia's V2 scrims already use; **no native module; the
expo-linear-gradient plan is retired, never committed**) · `05489dfb` (home = first-LIVE-listing feature +
§3 rows, V2 data layer byte-untouched) · `85855607` (search: `N listings · Soonest first`, GA / Under $150
(all-in, through money) / Mobile transfer chips, exact §5 filtered empty state) · `e2c564ce` (V2 pins
re-pointed with labels; control-gap strengthening).

**Evidence at `e2c564ce`:** tsc 0 · lint 0 errors/29 warnings (baseline) · vitest 133 files / 2568 tests,
run alone · 16/16 deliberate-bug controls killed as predicted (`scratchpad/v3_stage2_mutants.py`; first run
15/16 — B15 survived because a COMMENT containing "heightFor" satisfied SL4's bare regex while the mutated
code no longer called it; pin comment-stripped and re-verified red→green; disclosed in `e2c564ce`).

**Independent verification of the freeze mapping, on my branch:** 23 `Alert.alert` call sites · the 24th
variant at the branching cancel body · `More actions` = Android Alert / iOS `ActionSheetIOS` with COMPUTED
`destructiveButtonIndex` · `my-listings.tsx` 5 alerts · F-27 confirmed (the reservation failure branch
returns before `fetchData()`; refetch only after success) · buy-now = reserve RPC → refetch → navigate
(reservation before navigation, no charge).

**Rulings (recorded in the matrix):** F-25 deferred (copy unification is consent language + a structural
product decision — proposal to B's copy backlog, owner approves) · F-26 preserve the platform split ·
F-27 excluded from restyling (stays PROPOSED; no restyled dialog claims a refresh).

**B-5 client half:** `auto_release_at` exists (008), whole-table `GRANT SELECT ... TO authenticated`
(0550:267) under the buyer row policy, absent only from the select list → showing it is client-only. Its
meaning per state / staleness after extension → A's evidence table (requested; A queued it behind the
production release window, answering against the RC-deployed sources).

**Flagged for B (implemented conservatively):** same-day clock boundary ("2h 14m left" vs "Ends Sat
20:30") · divider ink (border.overArt) · "Tonight"/"This week" headings NOT drawn (no grouping rule) ·
"Any date" chip NOT built · single-clear actions limited to Clear price filter · skeleton keeps V2 grid
shape. Still open for the owner: Create→"Sell", bid-primary hierarchy, "Buy both now".

**Held/blocked:** order screen (B-4/O-1 + no caching) · three transfer cells B-1/B-2/B-3 (A first) ·
review-deadline display (B-5, A's half). **Next slices:** listing hero + §5 price block (LISTING_HERO_V3
slot ready), bid entry/checkout restyle (pkg2), then pkg3. **Device checks:** D-1…D-8 per
`V3_GAP_AUDIT.md` — canonical list; local simulator blocker unchanged (8 GB free vs ~20 GB).

---

# V3 stage 3 — rulings landed; listing detail + bid entry implemented (C, 2026-09-23)

**Branch:** `v3/midnight-app` @ **`debb1b98`** — `57419079` (three owner rulings: Create→"Sell";
Buy now stays primary; quantity-aware verb "Buy both now"/"Buy all N now", no invented count) ·
`dd839e28` (listing detail: identity over the LISTING_HERO_V3 curve hero, §5 panel + minimum-bid
breakdown + commitment sentence with the truthful starting-bid variant; neighborhood → details table;
Delivery + platform name; old countdown hook removed) · `debb1b98` (bid entry: restated listing, both
columns all-in with "bid + fee" beneath, headline = the total — pkg2 card ③'s EXISTS tag was wrong in
source and is corrected in the matrix).

**Evidence at `debb1b98`:** tsc 0 · lint 0/29 · vitest 135 files / 2586 tests run alone · controls 9/9
(rulings+listing; L6 first-run survivor → closed-with-values defence pinned red-green, disclosed) and 5/5
(bid entry; N1 killed by a prediction superset, corrected on record).

**Records:** matrix + explicit B review request (11 classified differences, nothing quietly omitted)
pushed at `8d2e9c2b` on design/frontend-audit-20260917.

**Owner clarifications applied:** Order redesign will use LIVE data + truthful existing error behaviour
only (no cached-order presentation without separate authorization); F-25/F-27 stay proposed; F-26
preserved. **Next slice:** checkout restyle (pkg2) — borders gated payControl/setupDecision/holdState, so
its own pass with A flagged on any contact; then pkg3. Gradient rendering on device = D-2-adjacent check
(tests pin the math only, per owner's note).

---

# V3 de-duplication direction — bid/listing/rows/checkout corrected (C, 2026-09-23)

**Owner direction:** each fact once, app-wide; amount on an action OR beside it; no control-explaining
sentences; earlier approvals/pins of repeated wording overridden. **Branch @ `d8d7be1a`** (one commit).

**Bid entry rebuilt to the directed shape** (supersedes the day's earlier two-column build): identity +
qty · market price once ("Current/Starting bid · $110 all-in") · labelled editable bid (stepper focus,
"Minimum $105") · fee once · total beside the plain "Place bid" button ("If you win / $115.50"). Payment
sentence corrected after verifying the winner's path (pay_now → winner checkout → payControl's Pay; nothing
charges automatically): "Nothing is charged now. If you win, you'll pay this total at checkout to complete
the purchase." — the shipped "Only charged if you win the auction." implied an auto-charge and is gone.
**Listing:** commitment sentence number-free (panel + CTA sub-label carry them); breakdown each number once;
live fee note dropped (sold view keeps its only fee sentence). **Rows:** sold rows say "Sold" once.
**Checkout:** the total-restating sentence under the breakdown removed — zero gated-file contact (diff vs
e079fcc1 gated surface: still only round 1's signOut.ts +5, flagged).

**Evidence:** tsc 0 · lint 0/29 · vitest 135 files / 2587 run alone · lean controls 3/3 as predicted
(button-amount revert · auto-charge revert · total-beside-action removal); obsolete pins updated in place,
behavioural checks retained (F-BID-1 8/8, CFT-205 single-flight untouched).

**Inventory sweep:** Home/Search already one-fact-per-row; transfers/create/my-listings/tickets/settings
grep-audited — no same-state money repeats; checkout success sentence vs ESCROW_NOTE_COPY render in
different payment states (#81 gating untouched; boundary re-checked in the checkout slice with A).
Per-screen copy de-dup continues as each restyle slice lands. **Phone-dimension review: rendered evidence is
NOT producible on this machine** (simulator blocker stands); layouts are content-driven with no fixed row
heights and keyboard paths unchanged in source — actual-dimension/large-text/keyboard checks remain D-3/D-4/
D-5 device items. Matrix updated + pushed (`9b21e403`).

---

# Post-deployment shipped-client compatibility checks (C → A, 2026-09-23, after 23:22Z)

**Trigger:** A's verification-window ping after the owner-authorised production sequence (migration 147 →
ledger 160; ten edge functions deployed from gate 5b255838; one listing data fix). **Result: PASS on all
seven checks**, reported to A (msg 4c84b611) with evidence per check.

Highlights: 147's blast radius is exactly one function (get_unsettled_payments — absent from both shipped
builds); 12/12 RPC argument-name matches at Builds 9 (47400911, tag re-resolved) and 13 (3c67dfc9, A's
recorded EAS commit) including explicit DEFAULT-NULL verification for the two wider signatures
(buyer_dispute_transfer, ensure_transfer_exists) and the 0553 bare-CREATE overload fix for
mark_transfer_sent; delete-account's additive pending_obligations/obligations_check invisible to the
shipped parse (reads only parsed?.error; success:true unchanged); send-push contract unchanged and the b2
challenge path unreachable from clients (zero references to send-push or push_token_challenge in either
build); full-chain checkout + transfer witnesses at the deployed sources.

**Evidence limits, stated in the report:** all source-derived at the pinned refs, re-read fresh this
session; NO live production query (prod reads stay owner-routed with exact queries); live parity of
production with those refs rests on A/D's witnessed ledger/version records. Release completion remains
A's call after the verification window.

**Provenance correction (2026-09-23, verified locally):** the APPLIED 147 blob is from `2bf67af9`
(PR #91 head), not `a77d2b8d`. Verified myself, not taken on trust: non-comment text of
20260923000000_sweep_manual_review_exclusion.sql is identical between the two commits (69 = 69 lines,
byte-equal after comment stripping), so the blast-radius derivation and PASS carry unchanged. A confirms
window item 1 (this gate) closed; remaining item = the 05:23Z signing-monitor run; release not-complete
until then; nothing further runs against production without the owner.

---

# V3 checkout slice (C, 2026-09-23) — `dd410da4`

One OrderIdentity block across all three checkout views (display voice, shared dated line,
"2 × GA · sold together"); breakdown row "Tickets" (identity owns the count); sticky Total gated on
labelCarriesAmount(pay.label) — the action or beside it, never both. Untouched: payControl label,
escrow-note #81 gating, A-02 flow, hold countdown, refund/settlement views. Gated surface: payControl/
setupDecision/holdState diffs EMPTY; listingSummary.ts +ticket_type (display-only) — flagged to A.
Board ④ ("Paying with" method row) recorded PROPOSED: requires Stripe FlowController = payment-flow
change, A's call. Evidence: tsc 0 · lint 0/29 · 2594/136 alone · controls 3/3 (K3 superset disclosed).
Matrix pushed 51e97db8. Next: pkg3 (Create/My listings/edit + payout setup screens) under the same rules.

**A ack (2026-09-23):** listingSummary touch queued with diff-stat acceptance; "Paying with"/FlowController
logged as payments-flow work, stop-and-ask class, assessed only after the window closes; nothing V3 in the
release record. Both picked up after the 2026-09-24 05:23Z monitor run + owner window close.

---

# V3 selling slice (C, 2026-09-23) — `646361f8`

pkg3 §1–§2: my-listings five distinct empties (Sell-rename consistency fix included; action only on All);
seller rows in display voice; Create money sides once each (buyer side inline per active value; seller net
+ fee clause at the sticky — clause had been in the invalid branch); §1 submit summary at the action.
Untouched: 22 dialogs, six status words, review-card gate, upload limits/copy, payout probe semantics,
F-1…F-8 (F-5 PROPOSED). Evidence: tsc 0 · lint 0/29 · 2599/137 alone · controls 2/2. Matrix pushed.
Remaining pkg3 items: edit-listing screen restyle rides the same components (no spec deltas found beyond
findings); payout screens conform as shipped. Next: pkg4 non-blocked cells + pkg5/pkg6 sweeps, order
screen still on A (O-1/B-4), transfer cells B-1/2/3 on A.

---

# Bid summary final + R-1 + F-28 (C, 2026-09-23) — `67b7f306`

Owner's final direction implemented without another round: three rows (Bid / Fee (10%) / Total, Total
strongest) directly above a full-width plain "Place bid" in one footer; sticky side-total, fee row, gap,
every "all-in" and in-summary captions removed; one concise payment sentence outside ("Placing a bid
doesn't charge you. If you win, you pay the total at checkout."). R-1: market line = the underlying bid
(same units as the editable value). F-28: success announced via AccessibilityInfo, no repeating dialog;
all failure dialogs + needs_proof path untouched. No keyboard on this screen; footer grows with large
text. Evidence: tsc 0 · lint 0/29 · 2601/137 alone (one full run flaked two edge suites under load — both
73/73 alone, no supabase/ diff) · controls 3/3 (Q1 superset disclosed). A's base question answered:
batch base e079fcc1; #81 files identical 19b6fc2b↔e079fcc1.

**New owner requirement (2026-09-23): full light/dark appearance** — System default, Settings
Appearance (System/Light/Dark), local persistence, live system changes, semantic tokens app-wide; B owns
both appearances (Midnight = dark; light derived), C implements. Bid screen in both appearances first.
Also queued: R-2 (listing total twice), R-4 (Create duplication, keep the review card's purpose), F-29
(place-a-bid recovery vs full eligibility), checkout nearby-total only when valid for the state, order/
transfer/search refinements as A's table lands.

---

# Appearance foundation · N1/N2 · R-2/R-4/F-29 (C, 2026-09-24)

**Commits on v3/midnight-app:** `1825bd0c` appearance (System/Light/Dark, persisted via AsyncStorage
through an injectable KeyValueStore, live phone following, Appearance.setColorScheme for explicit
overrides, Settings › Appearance radio screen, root nav theme + status bar follow the scheme; one
semantic palette shape — dark = Midnight/v2 untouched, light PROVISIONAL for B, computed contrast ≥4.5:1,
onArt inks fixed white; the bid screen fully theme-driven) · `7d44f87d` checkout: sticky Total REMOVED
(no state where a nearby amount is both valid and non-duplicate — A accepted), labelCarriesAmount gone,
N1 ticket_type mapping tests + presence-rule mutant · `be6aebfc` R-2 (listing total row gone), R-4
(review card keeps Event/Tickets/Selling, money rows gone), F-29 (recovery only when a bid is available).
Evidence per commit in the messages; appearance controls 5/5; R/F controls 3/3; one edge-suite load flake
disclosed (passes alone; no supabase/ diff).

**A's table consumed** (PAYMENT_STATE_WORDING_TABLE_20260924.md @ fbbe0440): the four cells + deadline
+ §3 precedence are the spec for the next slice (buyer expired/reversed, seller expired/reversed, deadline).
Buyer may read own payments row (baseline RLS buyer_id = auth.uid(); settledRead already selects status,
refunded_at, amount_refunded_cents, total). FlowController: not built (A: stop-and-ask class); design
question to B — read-only "Default card" from the intent's customer key, or drop the card.

**Appearance inventory status (source-only evidence):** foundation + bid screen migrated; every other
screen and shared component (Button, IconButton, Chip, StateView, EmptyState, ScreenState, NameText inks,
dock, sheets, dialogs, keyboard appearance) still carries static dark tokens — the migration continues
screen by screen. Simulator/device evidence: none (blocker stands); all three settings, persistence,
live system change, contrast on device, large text, keyboard appearance and photo fallbacks are device
checks (add D-9: appearance).

---

# Order/transfer cells (C, 2026-09-24) — `7e578ed5`

Built against A's table (fbbe0440). Buyer expired / reversed blocks; seller reversed block (before any
payout claim) + "No payout for this order." on expired; refund line from the buyer's own payments row via
readSettledPayments (full only with amount = total; partial; "Refund recorded"; else policy/pending line);
buyer review deadline from auto_release_at (omitted when absent); seller "Release decision at <t>."
Badges by role ("Closed" for the buyer, "Payout reversed" for the seller). Evidence: 24 RED→green;
controls 5/5; tsc 0; lint 0/29; full run flaked ONE untouched edge suite (credential-sign; passes alone) —
disclosed in the commit, not claimed green. Follow-ups: the seller "held" line lacks payout_hold_until
(client-only select widening, A to confirm the date may be shown); dispute-record outcome not read (no
client read exists; not added). Per-cell mapping sent to A for his read before "done".

**Process lesson (recorded):** three times this session a full run flaked one untouched edge suite; write
the commit message AFTER inspecting the full-run output, never before.

---

# F-30 · held date · conditional fallback (C, 2026-09-24) — `6f116c8e`

**F-30 closed (owner-bounded):** primary stays #FF1A1A + black (5.4:1). Pressed = LIGHTER fill
`brand.redPressed = #FF5353` (= #FF1A1A under 25% white), measured 6.6:1 under black vs 3.6:1 on the old
#CC0000; visibly distinct with the existing 0.98 press scale; press helper adds no opacity (pinned), so
the rendered fill is the token in both appearances; disabled (0.4 whole-control opacity) unchanged —
inactive controls exempt. Both token mirrors updated identically (parity kept). Control: token reverted
→ AP5 fails. **A's cell read: PASS at 7e578ed5**; held date shown only when held AND non-null; buyer
reversed fallback made strictly conditional. Cells + deadline DONE on the mapping side; B's visual
review of the five states pending. **B's checkout amount condition: PENDING A's lifecycle review** —
the nearby total stays removed; the route estimate is never promoted (nothing to change until A rules).
Evidence: tsc 0 · lint 0/29 · full run 2628/2628 (139 files), inspected before the commit message.

**A verified 6f116c8e from source (2026-09-24):** sellerHoldLine branches, select + call, conditional fallback, gated surface unchanged; cells + deadline recorded done pending B's visual review.

---

# Appearance — shared primitives migrated (C, 2026-09-24) — `3f295bca`

Button/IconButton/Chip/Badge/StateView/Spinner/Skeleton/StickyBar/Input/MediaUpload/Sheet/PriceDisplay/
AdaptiveDock/EventMedia now read useTheme(); makeStyles(palette) memoised per scheme; Light inks
witnessed on StateView/Button/Badge (PR1–PR3), no static colour groups left in them (PR4). Controls 3/3.
Evidence inspected before commit: tsc 0 · lint 0/29 · full 2632/2632 (140 files) clean. Remaining
inventory: the screens themselves (static refs remain in ~55 files: Create 51, profile/[id] 26,
Checkout 25, send/receive 25 each, notifications 24, …) plus 8 legacy-palette imports — next slices,
screen by screen, same pattern. Still no rendered/device evidence for Light (D-9).

---

# Reconciliation with B and A (C, 2026-09-24) — `016087ea`, `212783f2`

**`016087ea`:** one pressed value #FF5353 in both mirrors (B adopted it at c1e23125; B's #FF4C4C also
passed — settled without another round); Daylight = B's token board on the v2 key shape; `border.control`
(3:1) in both mirrors on Input/Chip/secondary Button; startup gate (provider withholds until the stored
choice is read, bounded 400 ms; root holds the splash until fonts + choice — AP14/AP15; AP6's fixture built
a store per render and wrote System back over a newer choice — fixed); checkout per A's ruling Q1–Q3
(rows only when `serverBreakdown && !priceChange`, server figures only, "Preparing your total" while setup
runs, lost hold keeps only a server figure; CS4/CS5; gated surface unchanged). Controls RC1–RC5 as predicted.
**`212783f2`:** B's A-1…A-5 rendered defects (dock `chrome` tokens, grabber, StatCardStrip, fallback
initial) verified by mounting the real components under each palette and computing contrast on the
emitted styles (RD1–RD7); R-5 via `offersBid(actions)` (LS3); F-28 body-only block. Controls RC6–RC11 as
predicted. Evidence each: tsc 0 · lint 0/29 · full run alone clean (2639 then 2647). One full run with a
survey script for company failed 8 timeouts and was voided; the five files pass alone.
**Owner directives absorbed:** build authorised (one sandbox EAS preview, once pre-build gates pass —
no re-asking); W1/W2 NOT executed, side effects traced in the plan; A-1 neutral hairlines approved → next;
synthetic transfer-state gallery authorised (sandbox-only, read-only, same components as the real screens)
→ in progress; the three transfer states stay unverified on device until then, and the data path stays open.
**Inventory at 212783f2 by actual colour access:** 54 files / 546 static refs; 14 palette-only; 1 partial
(app/_layout). B's 55+15 counts imports (space/radius/type included).
