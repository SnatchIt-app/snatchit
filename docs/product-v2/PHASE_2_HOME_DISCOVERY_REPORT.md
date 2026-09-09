# Phase 2 — Home and discovery

**Session:** Front End · **Date:** 2026-09-03
**Reference implementation:** the approved Phase 1 listing detail. Home was built to be the feed that
screen belongs to, not a new direction.

Nothing was committed, pushed, or opened as a PR. No Core-owned file was modified.

---

## 1. Branch and worktree

| | |
|---|---|
| Worktree | `/Users/josetascon/snatchit-fe-phase0` |
| Branch | `frontend/v2-phase2-home` |
| HEAD | `7d45cbf0edbabd06ca240a5d6386e62c572ff0de` |
| Carries | Phase 0 + Phase 1, uncommitted, verified present before work began |

### The checkpoint, and why it was not created

**This needs your decision.** Phases 0, 1 and 2 now sit as one pile of uncommitted changes in a
single worktree — 32 modified or new paths. That is a direct consequence of "do not commit" applied
across three phases: the only way each phase can build on the last is to keep the same working tree.

The instruction for this phase says that if a clean checkpoint requires a local commit, stop and
report rather than commit. So: **it does, and this is the report.** Nothing was committed.

The risk is concrete rather than theoretical. There is no way to see Phase 1 without Phase 2 on top
of it, no way to revert one phase, and a single `git checkout` in the wrong direction destroys
approved, reviewed work. Recommendation, when you authorize it: three commits on
`frontend/v2-phase0-foundation`, `…-phase1-listing-detail` and `…-phase2-home`, in order, so the
approved listing detail becomes a thing that can be pointed at.

### Upstream

`origin/feature/venue-native-and-product-v2` has advanced seven commits since this base
(`7d45cbf` → `609e0f4`): refund execution, payout state machine, 094/095, and `docs/phase2` records.
None of them touch a frontend-owned path — the only overlap is two backend test files under
`tests/`. **Not merged**, deliberately: pulling backend churn into the middle of a UI phase would
invalidate every verification run in this report. It should land with the checkpoint.

`expo-dev-client@6.0.21` is present in this worktree, matching Core's `IOS_DEVELOPMENT_BUILD_REPORT`.
That is the only change to `package.json`, and it came from Core.

---

## 2. Files changed

**Rewritten**
```
app/(tabs)/home.tsx        1005 → 435 lines   (data layer preserved verbatim, presentation replaced)
app/(tabs)/explore.tsx      210 → 205 lines   (dead route becomes Search — §10)
```

**New**
```
src/lib/listing/cardState.ts                         card status, mode-aware copy, price selection
src/components/discovery/DiscoveryCard.tsx           the one card
src/components/discovery/HomeHeader.tsx              compact, safe-area aware
src/components/discovery/FilterSheet.tsx             the filter modal, on Phase 0 primitives
src/components/discovery/DiscoveryGridSkeleton.tsx   the grid, before it loads
tests/discovery-card-state.test.ts                   21 tests
```

**Touched**
```
src/components/ui/IconButton.tsx    two glyphs added (search, filter). No behaviour change.
```

Listing detail was **not** touched. It is byte-identical to the approved implementation.

---

## 3. Home behaviours inventoried, and what happened to each

Taken from the previous `home.tsx` before anything was rewritten.

| Behaviour | Preserved | Note |
|---|---|---|
| Active listings query, 50, newest first | yes | unchanged |
| Sold listings query, 30, lazy on chip tap | yes | unchanged |
| Ended listings query, 30, lazy on chip tap | yes | unchanged |
| Blocked-seller filtering on all three | yes | `applyBlockedSellerFilter` untouched |
| Blocked-seller ref guard inside realtime handlers | yes | unchanged |
| Realtime INSERT: add active listings to the feed | yes | unchanged |
| Realtime UPDATE: patch, and drop sold or non-active rows | yes | unchanged |
| Neighbourhood preferences via `get_my_profile` | yes | unchanged |
| "Your scene" sort by preferred neighbourhoods | yes | unchanged |
| Quick chips (8) | yes | relabelled to sentence case; same keys, same filters |
| Category, area and price filters | yes | moved from a hand-rolled Modal into `FilterSheet` |
| Clear all filters | yes | now a chip in the row rather than a red word |
| One-second ticker driving every countdown | yes | unchanged, wired through `extraData` |
| Pull to refresh, per active chip | yes | unchanged |
| Refetch on focus | yes | unchanged |
| Loading state | yes | spinner-free skeleton grid instead of three grey cards |
| Offline / server error state | yes | same `ScreenState`, same retry |
| Empty states, per chip | yes | same four cases, rewritten copy |
| Tap a card to open the listing | yes | same route |
| Cover image with fallback | yes | now through `EventMedia` (§9) |
| All-in pricing | yes | same helper, more honest labels (§8) |
| Auction / Buy Now / sold / reserved / ended states | yes | now mode-aware (§7) |

**Two removals, both deliberate:**

1. **The floating "List Tickets" button.** Create is a tab in `app/(tabs)/_layout.tsx` and the button
   pushed `/(tabs)/create` — the same destination. Verified before removing: the tab is registered
   and visible, so no route is lost. It was a full-width red block permanently covering the bottom of
   the feed.
2. **The pre-resolved cover URL map.** `resolveCoverUrls` produced full-size public URLs and cached
   them in state. `EventMedia` resolves the raw path itself, which is what applies the Phase 0 host
   allowlist, the path encoding and the slot-sized transform. Keeping the map would have bypassed all
   three — it is how a multi-megabyte original ended up in a small card.

---

## 4. Information architecture

**No carousels, no invented sections.** The feed is one grid, segmented by the chip row that already
existed, because that is what the data actually supports: one `listings` table with a status, an
auction clock and an optional Buy Now price. "Happening this weekend" and friends would need event
grouping the client cannot see (§20), and inventing them from listing timestamps would be a
guess dressed as a section.

What changed is the shape, not the taxonomy:

```
Snatch It / Miami                          ⌕      compact, real safe-area inset
[All] [Your scene] [Buy now] [Auction] …[Filters 2] [Clear]
┌──────────┐ ┌──────────┐                        two-up, 4:5 artwork
│  4:5     │ │  4:5     │
└──────────┘ └──────────┘
 Title                    Title                  Inter, sentence case, 2 lines
 Venue · date             Venue · date
 BUY NOW  $66 all in      CURRENT BID $49 all in
 Bids from $33            02:14:08
```

"Miami" is stated because it is true of the entire product — every neighbourhood in
`src/constants/neighborhoods.ts` is a Miami one. It is not a location lookup and does not pretend to
be one. No greeting, no weather, no motivational line.

---

## 5. The discovery card

One card, replacing four unrelated geometries (a 180pt landscape band in the feed, a 64pt row in
explore, a 2.6:1 thumbnail in bids, an 80pt square in my listings). Home and Search now render the
same component; the remaining two belong to later phases.

Structure: 4:5 artwork, then text **below it**, never on it. Event flyers already contain typography
and a title layer over someone else's poster reads as a mistake — the same reasoning the approved
detail hero follows. The whole card is one tap target, so there is no button on it, which is also how
the old "Bid now" label stopped appearing on Buy Now listings.

The card carries **no status badge on an ordinary live listing**. The previous feed painted a red
`ACTIVE` pill on every card, which spent the brand colour on the one thing every row had in common.
Badges now appear only for `Ending soon`, `On hold`, `Sold` and `Ended`, and each is a word, never a
colour alone.

---

## 6. Where the card decisions live

`src/lib/listing/cardState.ts`, pure and tested, the counterpart to `detailState.ts` from Phase 1.
Same vocabulary at one altitude lower, so a card and the screen it opens cannot disagree about what
is being sold. It performs **no arithmetic**: it selects which existing whole-dollar column the price
comes from, and formatting stays with `allInFromDollars` at the call site.

---

## 7. Mode-aware copy

The old feed hardcoded `'Current bid'` and `'Bid now'` for every row. Three untruths, all fixed:

| Listing | Old | New |
|---|---|---|
| Buy Now enabled, 3 bids | Current bid $45 · Bid now | **Buy now $66 all in** · Current bid $49 |
| Buy Now enabled, no bids | Current bid $30 · Bid now | **Buy now $66 all in** · Bids from $33 |
| Auction, no bids | Current bid $40 | **Starting bid $44 all in** |
| Auction, 2 bids | Current bid $55 | **Current bid $60 all in** |
| Ended, no bids | Current bid $40 · View | **Started at $44 all in** |
| Ended, with bids | Current bid $90 · View | **Final bid $99 all in** |
| Sold | Sold for … | **Sold for …**, dimmed |

Buy Now leads on the card for the same reason it leads on detail: it is the stronger offer, and the
feed hid it completely.

---

## 8. Pricing

Every number on a card is all-in, through `allInFromDollars`, with the words `all in` on the same
line, smaller and quieter, so the amount keeps the hierarchy and the promise stays visible. Tabular
figures, so a live bid update does not shift the row.

No new conversion, no arithmetic in any Phase 2 file, no fee toggle. A test asserts the card cannot
even import `src/lib/money.ts`: it receives preformatted strings.

The price filter still filters the **listing** price rather than the all-in total, which is what the
query has always done. The sheet now says so in one line instead of leaving it implied.

---

## 9. EventMedia usage

`DISCOVERY_CARD`, the 4:5 slot the media system was designed around, in `fluid` mode. Each cell
measures its real column width and requests a derivative at that width times the true `PixelRatio`,
so the two-up grid fits a 375pt iPhone SE without a breakpoint and without a hardcoded width
anywhere in the phase.

Assets are marked `contract: 'legacy'`, which is true of every existing cover — the old picker
cropped destructively to 16:9. In a portrait frame they are therefore fitted against a blurred copy
of themselves: no black letterboxing, no cropped-off lineup. A missing cover renders the branded
plate. Artwork runs at full strength; the only overlay is a small badge in a corner when there is a
state worth flagging.

---

## 10. Search, and the fate of explore.tsx

`app/(tabs)/explore.tsx` was a complete, working, entirely unreachable listing browser: hidden with
`href: null` and pushed from nowhere. Its fetch, blocked-seller filtering and refresh handling were
sound; the product's actual gap was that **there was no search anywhere in the app**.

So it was neither deleted nor duplicated. It is now the search surface, reusing its own data pattern:
a debounced `ilike` over `event_name` and `venue` on `public.listings`, active listings only, blocked
sellers filtered, rendered with the same `DiscoveryCard`. Home's header pushes to it.

**Navigation is unchanged.** It stays out of the tab bar; a Search tab is Phase 9's decision. Search
runs only against authorized data — there is no catalog access to search events or venues yet, so it
matches on the listing's own text. When Core exposes the catalog, this is the screen that grows.

---

## 11. Loading, empty, error

- **Loading:** a skeleton grid that mirrors the real one exactly — same two columns, same 4:5 frame,
  same three text lines — so nothing moves when data arrives. Opacity pulse, no shimmer, still under
  reduced motion, hidden from screen readers.
- **Empty:** the Phase 0 `EmptyState`. "Nothing live right now." / "Check back, or list the tickets
  you cannot use." Per-chip variants for sold, ended and filtered-to-nothing.
- **Error:** the same `ScreenState` with the same retry. Search logs the raw Postgres message and
  shows a state rather than a string. No raw error text reaches a user in either screen.

---

## 12. Accessibility

- Each card is **one** announcement in reading order: "III Points Saturday. Space. Sat, Oct 17 · 10:00
  PM. Buy now $66 all in. Ending soon." with the action as a hint. The old card was eight unlabelled
  fragments.
- The header wordmark is a `header` role; the search control is a labelled 44pt `IconButton`.
- Chips carry `selected` state, so a filter's state is spoken rather than only shown in red.
- Status is always a word as well as a tone.
- The skeleton is hidden from assistive tech so the real content is what gets announced.
- **The 56pt safe-area guess is gone.** `HomeHeader` and Search read `useSafeAreaInsets`. A test
  asserts `paddingTop: 56` cannot come back to either file.
- Search: labelled field, `keyboardShouldPersistTaps="handled"` so a result is tappable with the
  keyboard up, dismiss on drag.

---

## 13. Motion

Only what the Phase 0 system already provides: press feedback on cards and chips (scale to 0.98,
90ms, brand easing, no bounce), the 180ms artwork cross-dissolve as each derivative loads over a
pre-painted frame, and the skeleton's opacity pulse. All three collapse under reduce motion. No
parallax, no floating elements, no autoplay.

---

## 14. Tests

`tests/discovery-card-state.test.ts`, 21 new tests, state mapping only:

- status: live, ending soon, reserved, ended, cancelled, sold, and an **expired** hold treated as no
  hold;
- Buy Now leads and keeps the auction as the alternative; an opening price is never called a current
  bid; "Current bid" only once someone has bid; "Bids from" on a Buy Now listing with no bids;
- no bid verb on anything sold, ended or expired, and no countdown on them either;
- sold price by the same priority as `salePrice.ts`, including the Buy Now case where
  `finalize_auction` never stamps a winning bid;
- ended-with-bids versus ended-without;
- badges: none on an ordinary live card, present for every state that changes what the user does,
  never tone alone;
- countdown formatting across seconds, hours and days.

Plus source guards on the shipped feed: prices only through `allInFromDollars`, no arithmetic, the
card cannot import the money module, no `'Bid now'` or `'Current bid'` string constants left, no
venue-direct claim, no emoji, no `paddingTop: 56`, the listing route intact, and the nine data-layer
markers (`applyBlockedSellerFilter`, `postgres_changes`, `get_my_profile`, `sortByNeighborhoods`,
`fetchSoldListings`, `fetchEndedListings`, `RefreshControl`, `useFocusEffect`, `useBlockedUserIds`)
still present in `home.tsx`.

All Phase 0 and Phase 1 tests are unchanged and still pass. Nothing was weakened.

## 15–17. Results

```
npm test  (vitest run)    → Test Files  12 passed (12)
                            Tests      399 passed (399)
npx tsc --noEmit -p .     → clean, exit 0
npm run lint (expo lint)  → 36 problems (0 errors, 36 warnings)
```

| | Phase 1 end | Phase 2 end |
|---|---|---|
| Test files / tests | 11 / 378 | **12 / 399** |
| Typecheck | clean | **clean** |
| Lint | 39 warnings, 0 errors | **36 warnings, 0 errors** |

**New warnings: none.** Down three, because the rewritten `home.tsx` dropped dead imports and an
unused helper. Every remaining warning is pre-existing.

---

## 18. Runtime verification

**What was actually run, and what it proves:**

- Metro was started from this worktree (`npx expo start --dev-client`, `.env` loaded, values not
  printed) and is **live on port 8081**.
- The complete iOS bundle was requested and served: **HTTP 200, 14,602,863 bytes, 2,227 modules,
  ~51s**. That compiles and transforms every module in the app graph — the rewritten Home, the new
  Search, all discovery components, the approved listing detail, the primitives and the brand fonts.
  A missing import, a bad path, a syntax error or a broken module boundary anywhere in the app would
  fail this, and none did.
- The served bundle was grepped for the new copy (`Nothing live right now`, `Buy or bid`) and
  contains it, so what Metro is serving is this code and not a stale cache.

**What was not achieved, stated plainly: I did not see Home render.**

Three routes to a render were attempted and each is blocked for a reason outside this phase:

1. **Physical iPhone.** The dev client is installed and Metro is up, but the review itself needs
   someone holding the phone. I cannot perform it.
2. **iOS Simulator.** A full local build was attempted: `expo prebuild` succeeded; `pod install`
   failed on a CocoaPods/Ruby locale error and was fixed by running it with `LANG=en_US.UTF-8`
   (environment only, no repository change); `xcodebuild` then refused every simulator destination.
   `xcodebuild -showdestinations` lists **no eligible destination at all** for the scheme, only the
   device placeholder with `iOS 26.5 is not installed`. The iOS Simulator SDK 26.5 is present but the
   only installed runtime is 26.2, and Xcode 26.6 will not pair them. The independent simulator
   build tool fails identically (exit 70, "Unable to find a destination matching the provided
   destination specifier"). Fixing it means downloading a multi-gigabyte platform component in
   Xcode → Settings → Components, which is your machine and your call.
3. **Web.** `expo start --web` fails during static rendering on
   `Importing native-only module "react-native/Libraries/Utilities/codegenNativeCommands"`, pulled in
   through `app/checkout/[id].tsx` → `CheckoutNative` → `@stripe/stripe-react-native`. Pre-existing,
   untouched by this phase, and inside Phase 3's file.

**To finish the verification, with Metro already running:**

```bash
cd /Users/josetascon/snatchit-fe-phase0 && npx expo start --dev-client --tunnel
```

(or reuse the running LAN server, which is how Phase 1 was reviewed). Then open the dev client and
walk: the grid with real inventory; a Buy Now listing versus an auction-only one; a long event title;
a listing with no artwork; pull to refresh; the filter sheet; the chip row including Sold and Ended;
search from the header; tap into the approved listing detail; come back.

`/_dev/foundation` still prints whether the brand faces registered and the exact image URL being
requested, which answers the two questions a screenshot cannot.

---

## 19. Visual issues found on device

**None observed, because no device pass happened in this session.** This section stays empty rather
than being filled with what I expect the screens to look like.

---

## 20. Core dependencies

Nothing new blocks Phase 2. Re-verified against production earlier in this branch's work and
unchanged: 093 undeployed, all three native flags false, `kernel.tickets` SELECT still absent, no
event-media schema.

Discovered by this phase:

1. **No catalog access means search is listing-text search.** Matching on `event_name` and `venue`
   strings is the honest ceiling until `catalog.event` is readable. Two sellers listing the same night
   with different spellings are two unrelated results. This is the same gap that stops the feed being
   grouped by event.
2. **A price ladder on the list query would remove a compromise.** The card shows one listing's price.
   "From $48" across all listings for an event needs the event to exist client-side first.
3. **Still no stable error-code vocabulary.** Search maps failures locally and logs the raw string.

---

## 21. Is Phase 3 (Checkout) safe to begin?

**Yes, with one caveat that belongs to it.**

Checkout inherits the primitives, the media pipeline and the price posture, and its money math is
correct and shared with the server — the Phase 1 rule holds: use the existing helpers, add no
conversion. The known work is the one the audit identified: the buyer currently pays without ever
seeing what they are buying. `CHECKOUT_THUMBNAIL` exists in the slot system for exactly that.

The caveat: **`app/checkout/[id].tsx` is the file that breaks the web bundle** (§18). Phase 3 touches
it, so it is the natural moment to make the native-only import genuinely lazy. That would also
restore a second rendering path for verification, which this phase could have used.

Two things should happen before Phase 3 starts:

1. **the checkpoint decision** (§1) — three phases of approved work are one `git checkout` from gone;
2. **a device pass on Home**, since Phase 3 begins where Home ends.
