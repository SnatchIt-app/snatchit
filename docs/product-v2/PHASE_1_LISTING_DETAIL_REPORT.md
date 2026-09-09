# Phase 1 — Listing Detail redesign

**Session:** Front End · **Date:** 2026-09-03
**Authority:** `CORE_FRONTEND_HANDOFF.md`, `docs/product-v2/PHASE_0_FOUNDATION_REPORT.md`,
`DESIGN_SYSTEM_V2.md`, `SCREEN_REDESIGN_MATRIX.md`, `UI_IMPLEMENTATION_PLAN.md`,
`CURRENT_PRODUCT_AUDIT.md`, `ADVERSARIAL_UI_REVIEW.md`.

Nothing was committed, pushed, or opened as a PR. No Core-owned file was modified.

---

## 1. Branch and base

| | |
|---|---|
| Worktree | `/Users/josetascon/snatchit-fe-phase0` |
| Branch | `frontend/v2-phase1-listing-detail` |
| HEAD | `7d45cbf0edbabd06ca240a5d6386e62c572ff0de` |
| Integration branch | `frontend/v2` (tracking `origin/feature/venue-native-and-product-v2`) |

**A note on how the phases chain.** Phase 0 was completed under an explicit "do not commit"
instruction, so its work exists only as uncommitted changes in this worktree. The Phase 1 branch was
therefore created **in the same worktree**, carrying the Phase 0 tree forward
(`git checkout -b frontend/v2-phase1-listing-detail`), because a fresh worktree from `frontend/v2`
would have started without Phase 0. Both branches point at the same base commit and no published
branch was rebased or force-pushed. If phases are meant to remain separately reviewable, Phase 0
needs a commit before Phase 2 starts; that is an owner decision, not one I took.

**Pre-flight verification, re-run against production rather than assumed:**

- `origin/feature/venue-native-and-product-v2` still resolves to `7d45cbf`; no new commits.
- `origin/phase2/consolidation` still at `7e89f0e`.
- Migration **093 is still not deployed** (`supabase_migrations.schema_migrations` has no `093%` row).
- `feature.native_issuance_enabled`, `feature.native_resale_enabled`,
  `feature.native_scanning_enabled` are all **false**.
- No `fee` or `config` schema exists.
- `has_table_privilege('authenticated','kernel.tickets','SELECT')` is still **false**.

So: marketplace-only, no venue-direct anything, no Tickets. All Phase 0 output is present and the
foundation tests are green.

---

## 2. Files changed

**Rewritten**
```
src/screens/ListingDetailScreen.tsx        1705 → 1197 lines
```

**New — presentation, extracted from that file**
```
src/components/listing/ListingHero.tsx            artwork, controls, event identity
src/components/listing/ListingStatusBanner.tsx    the one status row
src/components/listing/TransactionPanel.tsx       price, clock, what is on offer
src/components/listing/SellerTrustRow.tsx         who is selling this
src/components/listing/TicketDetails.tsx          what you actually get
src/components/listing/BidActivity.tsx            how the price got here
src/components/listing/OutbidToast.tsx            the outbid notice
```

**New — logic, extracted and tested**
```
src/lib/listing/detailState.ts             role, mode, actions, status
```

**Extended**
```
app/_dev/foundation.tsx                    13 listing states + transaction block + artwork edges
tests/listing-detail-state.test.ts         NEW, 32 tests
```

No other screen was touched. No Core-owned path appears in `git status`.

---

## 3. Existing states preserved

Every item on the phase's inventory list was located in the old file before anything was rewritten,
and each is accounted for below. Nothing was dropped because it complicated the layout.

| Behaviour | Status | Where it lives now |
|---|---|---|
| Active auction | preserved | `transactionMode → auction_only` |
| Buy Now available | preserved, **promoted** | `auction_and_buy_now`, primary action |
| Auction only | preserved | primary action is Place bid |
| Sold | preserved | status `sold`, purchase suppressed |
| Ended | preserved | status `ended` / `lost`, `mode: closed` |
| Reserved (by you / by another) | preserved | statuses `reserved_by_you` / `reserved_by_other` |
| Reservation countdown | preserved | live `mm:ss` in the status detail |
| Current high bid | preserved | `TransactionPanel`, all-in |
| Winning user | preserved | status `winning` |
| Losing user | preserved | status `outbid` / `lost` |
| Owner/seller state | preserved | status + overflow menu, no buyer CTA |
| Seller edit / cancel / delete | preserved, **moved** | overflow menu; handlers untouched |
| Report listing / report seller | preserved | overflow menu |
| Block seller | preserved | overflow menu; same RPC, same 23505 handling |
| Bid history | preserved | `BidActivity` |
| Realtime bid updates | untouched | `useListingRealtime` |
| Realtime listing updates | untouched | the singleton `listing-detail-${id}` channel |
| Outbid detection | untouched | `handleNewBid`, refs, baseline effect |
| Outbid haptics | untouched | same `Haptics.notificationAsync` call |
| Outbid banner | preserved, redesigned | `OutbidToast`, same trigger and 4s dwell |
| Auction winner | preserved | status `won`, primary Pay now |
| Payment routing | untouched | `navigateToWinnerCheckout` |
| Buy Now routing | untouched | `handleBuyNow` → `reserve_buy_now` → checkout |
| Transfer send routing | preserved | primary action → `/transfer/send/[id]` |
| Transfer receive routing | preserved | primary action → `/transfer/receive/[id]` |
| Dispute state | preserved | status + View dispute |
| Refresh / retry | preserved | `ScreenState` retry; seller Refresh for a late transfer row |
| Auth readiness | untouched | `authReady`, all gating intact |
| Narrow-width sticky bar | preserved, improved | `StickyBar` stacks from the live window width |
| Auction-ending-soon / won / lost notifications | untouched | all three effects and their once-only guards |
| Auto-finalize on expiry | untouched | `finalize_auction` call in `fetchData` |
| Late transfer-row retry (5 × 2s) | untouched | unchanged effect |

**Three deletions, all of unreachable code, each deliberate:**

1. `handleMarkSent`, `handleConfirmReceived`, `handleReportIssue`. These were **already dead before
   this phase** — the previous revision's lint output flags all three as defined-but-never-used —
   because the screen routes to `app/transfer/send/[id]` and `app/transfer/receive/[id]`, which carry
   the live implementations of the same three calls. One of them invoked `confirm-and-release`, which
   releases a seller's payout; a second, divergent copy of that call in a file where nothing invokes
   it is a hazard, not a safety net. The routes that own these actions are unchanged.
2. `InfoRow`, `BidRowItem`, `AuctionBanner` and their three local stylesheets, replaced by the
   extracted components.
3. `fmt$`, orphaned when `BidRowItem` was replaced.

**One capability intentionally re-presented rather than removed:** `TransferStatusBadge` no longer
renders on this screen. The same information is now the status row's own label and detail
("Send the tickets", "Tickets sent", "Issue reported"), which is more specific and is visible without
scrolling. The badge component is untouched and still used elsewhere.

---

## 4. Layout and hierarchy

The screen reads top to bottom as **event, then transaction, then details**:

```
artwork, full width, 4:5, controls floating on it, provenance badge bottom-left
event title (Inter, sentence case) · venue · neighborhood · date
[ one status row, only when there is something to say ]
transaction: Buy now price → current bid + next bid + countdown → the fee sentence
seller trust row
The ticket: type, quantity, delivery, category, started at, proof, restrictions
Bid activity
────────────────────────────────────────────
sticky: price  ·  [ Place bid ]  [ Buy now · $66 ]
```

What changed structurally:

- **The artwork is first and it is large.** It was previously below a stack of banners that could
  push it off the first screen entirely.
- **Four identical grey cards are gone.** Event details / Ticket info / Pricing / Bid history each
  had the same border, radius and weight, so nothing signalled which mattered. There is now one
  ticket section separated by hairlines, and pricing has moved into the transaction block where the
  decision is made.
- **The event title is Inter, sentence case, 22pt.** Oswald appears only on Snatch It's own section
  voice ("The ticket", "Bid activity") and in the empty states. An event name is the venue's content,
  not our brand voice, and both first-party benchmarks set titles this way next to artwork.
- **Metadata is stated once.** Venue, date and neighborhood live under the title and are not
  repeated in the details section.

---

## 5. Transaction hierarchy

**The defect this phase existed to fix:** `buyBtn` was `colors.bgInput` with a grey border while
`bidBtn` was `colors.primary`. Instant purchase — the strongest offer on the listing — was rendered
as the weaker of the two buttons on every dual-mode listing.

Now, when Buy Now exists:

- it is stated first, as a price, with the line "Yours immediately. No waiting for the auction.";
- the current bid sits below it under a hairline, one size down;
- in the sticky bar Buy Now is the **primary** (red fill, black label) and Place bid is the
  **secondary** (hairline, white label). Two different weights, one obvious relationship, never two
  equal red blocks.

Auction-only listings show one price, the countdown, "Next bid from $X", and a single primary
Place bid. No Buy Now language appears anywhere on them.

**Nothing is offered that cannot work.** A seller viewing their own live listing previously got an
enabled "⚡ Place Bid" whose only possible outcome was the database raising *You cannot bid on your
own listing* (`validate_and_apply_bid`'s shill-bid guard). They now get a disabled "Your listing" and
their controls in the overflow menu. The same rule removes purchase actions on sold, cancelled,
ended, finalizing and other-buyer-reserved listings, each with a specific label — Sold, Cancelled,
Ended, On hold.

All amounts on this screen are **all-in**, produced by `allInFromDollars` / `allInLabel` and rendered
by `PriceDisplay`. The fee is stated once as a sentence, not as a table: *All prices include the 10%
service fee.* The screen performs no arithmetic; a test asserts it contains exactly the two
pre-existing `dollarsToCents` calls, both in the untouched checkout navigation.

---

## 6. Status system

`listingStatus()` returns **at most one** status, chosen by priority: closing → sold/transfer →
cancelled → won/lost → ended → reservation → winning/outbid → nothing. The old screen could stack
five banner rows above the artwork simultaneously — SOLD, a "transfer loading, tap to refresh" hint,
a transfer action button, an "Owner Actions" block and a reservation notice.

The row is a 2pt left edge on a near-black surface with a coloured label and one sentence of
consequence. Tone never carries meaning alone: every state is a word first. Secondary detail lives
where it belongs — the reservation countdown is the status's own detail line, the transfer step is
the sticky bar's primary action.

**Owner actions are not status** and no longer render in the buyer flow at all.

---

## 7. Seller and trust

`SellerTrustRow` answers one question: can I trust who is selling this. Avatar (the one circle in the
product), the name, the verified badge the database sets, and a chevron into the existing public
profile route. It is a 64pt row with a real accessibility label reading
"Seller Marco, verified. View profile."

It invents nothing. There is no score, no star rating, no derived rank, and no fabricated zero: the
completed-sales figures live on the public profile screen, where Phase 0 fixed the bug that rendered
a failed stats query as "0 completed sales".

---

## 8. Ticket details

One section, hairline-separated rows, quiet label and loud value:

Type · Quantity ("2 tickets", not "2") · Delivery ("Mobile transfer" / "Email") · Category ·
Started at (all-in) · Ownership proof, only when `proof_status === 'approved'` · Restrictions, which
wrap under their label instead of being squeezed into a right-aligned column.

Internal vocabulary stays internal: the user reads "Delivery", not "transfer_method".

---

## 9. Media treatment

`EventMedia` in `EVENT_HERO`, `fluid`. Consequences, all of them measured rather than assumed:

- the frame **measures itself** and requests a derivative at exactly that width times the real
  `PixelRatio`, so nothing depends on a device width and a 375pt SE cannot overflow;
- the stored path is handed over raw, so the Phase 0 policy applies — per-segment encoding, host
  allowlist, and legacy `cover_image_url` rows rewritten into bucket paths so they get transformed
  too. Pre-resolving the URL in the screen, as the old code did, bypassed all three and shipped the
  original;
- assets are marked `contract: 'legacy'`, which is true of every existing listing cover (the old
  picker cropped destructively to 16:9). In the portrait hero they are therefore **fitted against a
  blurred copy of themselves**, never re-cropped and never letterboxed with black bars;
- a missing cover renders the branded plate, not a broken image;
- the scrim is a gradient band across the bottom third, not a veil over the whole image. The artwork
  stays visible.

Nothing transactional sits on the artwork. Only the back and overflow controls and the provenance
badge do, and the badge is a label rather than a decision.

---

## 10. Accessibility

- **Controls.** The hand-built `←` and `⋯` Pressables are replaced by `IconButton`, which is 44×44,
  requires a label, and takes a dark plate over artwork so it stays legible on a white poster. It
  also clears the notch: the artwork runs under the status bar deliberately, so the inset is applied
  to the controls rather than to the frame.
- **Labels everywhere.** Seller row, refresh, status row, every detail row, every bid row, both
  sticky actions. Bid rows read as one sentence — "Marco, $66 total, 4m ago. Highest bid." — instead
  of three unlabelled fragments.
- **State is never colour alone.** The leading bid is marked with the word "Leading" as well as red.
  Every status is a word first. The disabled primary says why: Sold, Ended, On hold, Your listing.
- **The countdown does not spam.** It is explicitly not a live region; announcing every second would
  make the screen unusable with a reader. The outbid toast announces once, politely, and the status
  row carries the same fact persistently for anyone who misses it.
- **Loading is announced.** `Spinner` reports "Loading this listing" via `progressbar` rather than
  rendering a silent `ActivityIndicator`.
- **Targets.** The seller row is 64pt, the refresh control 44pt, both sticky buttons 44pt, icon
  buttons 44pt.

---

## 11. Motion

Three things move, all through the Phase 0 system, all collapsing under the OS reduce-motion setting:

- **press feedback** on every button, chip and icon button: scale to 0.98, 90ms, brand easing, no
  bounce and no overshoot;
- **the outbid toast**: opacity plus a 12pt translate over 180ms on `cubic-bezier(0.22, 1, 0.36, 1)`.
  It now sits below the top of the screen rather than sliding over the navigation header, and it is
  `pointerEvents="none"`, so it can never swallow a tap on the bid button underneath;
- **the artwork reveal**: `EventMedia`'s 180ms cross-dissolve as the derivative loads, over a
  pre-painted frame of the correct geometry, so nothing shifts.

The trigger for the outbid notice is untouched: same INSERT-driven callback, same baseline guard,
same haptic, same four-second dwell. Only the mechanism moved from two `Animated.Value` refs in the
screen to a component that honours reduced motion.

---

## 12. Components extracted

Seven presentation components and one pure logic module (§2). The split is deliberate: **behaviour
stayed in the screen**. Every hook, ref, effect, channel subscription, RPC call and navigation
handler is still in `ListingDetailScreen.tsx` and, apart from the outbid mechanism, is byte-for-byte
what it was. What moved out is layout and copy.

`detailState.ts` is the exception, and it is logic that was worth moving: it was previously a dozen
booleans recombined at five render sites, which is how Buy Now ended up styled as the weaker action
and how a seller ended up with a bid button. It is pure, imports no React, and is tested directly.

No state-management library was added. No dependency of any kind was added.

---

## 13. Tests

`tests/listing-detail-state.test.ts`, 32 new tests:

- **transaction mode** — auction-only, both offers, and every closing condition (sold, cancelled,
  ended, clock run out, held by another buyer), plus the case that must stay open: held by *you*.
- **the Buy Now hierarchy** — Buy Now leads and carries its all-in price; bidding is the secondary;
  auction-only offers nothing else; no number is invented when the all-in string is absent.
- **nothing offered that cannot work** — the seller gets no buyer action; purchase is suppressed on
  sold, ended, finalizing and other-held listings, each with its own label; the reservation holder is
  sent to checkout rather than re-reserving.
- **after the sale** — winner pays, seller sends, buyer reviews, dispute routes to the dispute, and a
  passer-by sees only "Sold".
- **status priority** — closing outranks everything; the sale outranks a stale outbid; each side of a
  live transfer is told what it needs to do; winning and outbid are distinguished in words; a viewer
  with no stake sees nothing; a non-bidder is never told they lost.
- **shipped-source guards** — no venue-direct claim and no `isVenuePrimarySale` anywhere in the
  screen, hero or panel (comments stripped before matching, since they quote the forbidden strings);
  no money arithmetic outside the canonical helpers and exactly two `dollarsToCents` calls; prices go
  through `PriceDisplay`; no emoji left in the rendered interface; and the realtime, outbid, haptic,
  `finalize_auction`, `reserve_buy_now`, `cancel_listing` and `user_blocks` machinery all still
  present.

All Phase 0 tests are unchanged and still pass. No expectation was weakened.

---

## 14. Results

```
npx tsc --noEmit -p .     → clean, exit 0
npm test  (vitest run)    → Test Files  11 passed (11)
                            Tests      378 passed (378)
npm run lint (expo lint)  → 39 problems (0 errors, 39 warnings)
```

| | Phase 0 end | Phase 1 end |
|---|---|---|
| Test files / tests | 10 / 346 | **11 / 378** |
| Typecheck | clean | **clean** |
| Lint | 45 warnings, 0 errors | **39 warnings, 0 errors** |

**New warnings: none.** The count fell by six because three unreachable transfer handlers and an
orphaned formatter were removed. Every remaining warning is pre-existing (`exhaustive-deps`, stale
eslint-disable directives, `isOutbidNow` which was already unused on the previous revision).

`src/screens/ListingDetailScreen.tsx`: 1705 → 1197 lines.

---

## 15. Deferred

| Item | Why |
|---|---|
| Adopting `EventMedia` on the remaining screens | Home is Phase 2 and will do it as part of its own redesign. |
| A dev-only Listing Detail *route* rendering the full screen against fixtures | The state gallery in `app/_dev/foundation.tsx` covers the decisions; a full fixture route would need a fake `useListingRealtime`, which means a seam through live realtime code for a preview. Not worth that risk. |
| Bid entry (`PlaceBidScreen`) | Tier 3 in the implementation plan. The forty-tap stepper problem is real and untouched. |
| `TransferStatusBadge` restyling | Still carries hardcoded hexes but is no longer used by this screen. It belongs to the transfer screens' phase. |
| Focal-point control on hero artwork | Needs the event media schema, which is Core's (§16). |

---

## 16. Core dependencies

Nothing new blocks this phase. Restating what remains open and was re-verified today:

1. **Event media schema** — `catalog.event.hero_image_ref` is a bare text column; no focal point, no
   crop metadata, no event-artwork bucket. Until it exists, hero artwork uses `DEFAULT_FOCAL` and the
   fit-with-backdrop path. Core-owned.
2. **`kernel.tickets` SELECT grant** — still absent, so no Tickets destination.
3. **Venue-direct rails** — 093 undeployed, all three flags false. This screen ships marketplace-only
   provenance and a test now enforces that it cannot silently start claiming otherwise.
4. **Error-code vocabulary** — the screen still surfaces raw Postgres strings inside `Alert.alert`
   for reservation, cancel, delete and block failures. That is pre-existing behaviour I did not
   change, because mapping those messages needs the stable codes Core has not shipped. It remains the
   largest copy defect on the screen.

---

## 17. Device review

**None performed.** No simulator run, no screenshots, no on-device pass. Static verification only:
typecheck, lint and 378 unit tests.

That is a real gap and it is the same one Phase 0 recorded, now with more surface behind it: the
brand faces have never been seen rendering, the 4:5 hero has never been seen at a real width, and the
sticky bar's stacking threshold has never been observed against an actual 375pt screen. Layouts were
built to avoid device assumptions rather than tuned against one — no width, height or breakpoint in
any file added this phase, `fluid` media measuring itself, and `StickyBar` reading the live window —
but "cannot be wrong by construction" is not the same as "has been looked at".

**The first action of Phase 2 should be to run the app and open `/_dev/foundation`.** It prints
whether the brand faces registered, the exact transformed image URL being requested, the live window
width against the stacking threshold, and all thirteen listing states in one scroll.

---

## 18. Is Phase 2 (Home) safe to begin?

**Yes.**

Home inherits everything it needs and is a simpler problem than this screen was: the card is
`EventMedia` in `DISCOVERY_CARD` plus `PriceDisplay`, the filter bar is `Chip`, the filter sheet is
`Sheet`, the loading state is `Skeleton`, and the empty states are `EmptyState`. The provenance badge
and the all-in price rule are settled and enforced by tests.

Three things carry forward into it:

1. **The feed still hardcodes "Current bid" and "Bid now" on every card**, including Buy Now
   listings, which is the same defect this phase just fixed on detail. `detailState` is reusable for
   the card's label and CTA.
2. **All five tab screens hardcode `paddingTop: 56`** and ignore `useSafeAreaInsets`. Home is where
   that starts getting fixed.
3. **There is still no search anywhere in the app**, and `app/(tabs)/explore.tsx` remains a dead
   route. Phase 2 should either make it the search surface or delete it, deliberately.

The one thing Phase 2 should not do is start before someone has run the app once.
