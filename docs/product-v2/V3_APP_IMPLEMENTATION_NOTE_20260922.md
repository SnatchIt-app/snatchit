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
