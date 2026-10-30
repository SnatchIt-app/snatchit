# Phase 4 — Bids + purchase ownership

**Session:** Front End · **Date:** 2026-09-03
**Branch:** `frontend/v2-phase4-bids-ownership` (from the Phase 3 checkpoint `f0c7044`).
Not committed — awaiting device review. No push, no PR, no Core-owned file touched.

## 1. Branch / base

Base `f0c7044` (approved Phase 3). Working set is Phase 4 only:

```
M  app/(tabs)/bids.tsx                       presentation rebuilt; data layer preserved
A  src/lib/bids/bidState.ts                  pure status/group/price/action model
A  src/components/bids/BidCard.tsx           V2 horizontal card
A  tests/bid-state.test.ts                   36 tests
A  docs/product-v2/PHASE_4_BIDS_OWNERSHIP_REPORT.md
```

Nothing else. Home, Listing Detail and Checkout are byte-unchanged (verified against their commits).

## 2. Existing bid behaviours inventoried

The old `app/(tabs)/bids.tsx` (720 lines): a `bids` query joined to listings; collapse of multiple
bids on one listing into a single card at the user's **max** bid; nine statuses via `getBidStatus`
(winning, outbid, won, lost, sold, awaiting_transfer, seller_sent, purchase_disputed,
purchase_confirmed); a six-pill `StatCardStrip` filter (Needs Action / Winning / Outbid / Won /
Purchases / Total) with live counts; hard load on mount, silent refetch on focus, pull-to-refresh;
`ScreenState` offline/error; per-filter empty copy; each card routing to the transfer flow for an
in-flight purchase, else the listing.

## 3. Existing purchase/ownership behaviours inventoried

A second query merges `transfers` where the user is the buyer, keyed by listing, covering the two gaps
bids alone miss: **Buy Now purchases** (no bid row) and **completed auction wins** (transfer status,
not stale `listing.status`, drives the badge). Purchase amount is `finalSoldPrice(listing)`. Delivery
gate (`needsDeliveryInfo`) surfaces "add your transfer info". Purchase state takes precedence over bid
state.

## 4. Behaviours preserved

**The entire data layer is preserved verbatim** — the `bids` query and collapse, the `transfers`
merge, `finalSoldPrice`, mount/focus/refresh, `ScreenState`. A source-guard test asserts the query
calls, the merge, `useFocusEffect`, `finalSoldPrice` and `RefreshControl` all remain. The nine-status
classification is preserved exactly, moved into `bidStatusOf` (pure) with identical logic including
the "clock expired but not finalised → conservative lost" rule and the purchase-precedence switch.

## 5. State model

`src/lib/bids/bidState.ts` is the pure, tested model (counterpart to `detailState`/`cardState`):

- `bidStatusOf(row, userId)` — the nine statuses, unchanged behaviour.
- `bidGroupOf(status)` — **Active** (winning, outbid, won, awaiting_transfer, seller_sent,
  purchase_disputed) vs **Past** (lost, sold, purchase_confirmed).
- `needsAction(status)` — won, outbid, and the three in-flight purchase states.
- `bidPresentation(row, userId)` — label, tone, action hint, transfer-vs-listing routing, sort
  priority, and the one price to show (with an optional secondary), selecting the existing
  whole-dollar column. No arithmetic.

## 6. Bid visual hierarchy

The six-pill filter strip is replaced by two segments, **Active** and **Past**, because the dataset is
small and the states collapse cleanly into "needs me / settled" — the structure the brief asked for
("ACTIVE / PAST … do not create five filters"). The Active segment's chip carries the needs-action
count. Within Active, cards sort most-urgent first: disputed → won (pay) → tickets sent (confirm) →
purchased (add info / waiting) → outbid → winning. No data is lost; every row is still reachable,
grouped instead of filtered.

Each card (`BidCard`) is a horizontal row: event artwork (`EventMedia` `CHECKOUT_THUMBNAIL`), a state
`Badge`, the event name (Inter, natural case), venue · date, the state-appropriate all-in price with an
optional secondary ("Your max"), and — only where the user must act — a short red action line. Past
cards are dimmed. Colour never carries state alone: the badge word does.

## 7. Purchase / ownership hierarchy

Ownership is expressed only through the **transfer state machine**, which is all the client is granted.
A purchased row leads with the event, shows "Purchased / Tickets sent / Confirmed" and the amount
paid, and routes into the existing transfer receive/confirm flow where the real next action lives.
"Won" shows what the buyer must pay and routes to the listing (whose Pay Now → checkout is unchanged).

## 8. Transfer-state treatment

Preserved and surfaced truthfully: `pending` → "Purchased" (or "Add transfer info" when delivery info
is missing), `seller_sent` → "Tickets sent / Confirm receipt", `disputed` → "Disputed / View dispute",
`buyer_confirmed`/`auto_released` → "Confirmed". No delivery-timing promises, no "ticket ready", no
Apple Wallet.

## 9. Pricing

Every amount is all-in via `allInFromDollars`, tabular figures, with " all in" beside it. Column
selection matches `salePrice.ts` priority (winning bid → buy-now price → current bid). No new
conversion; the card cannot import the money module (asserted).

## 10. Empty / loading / error

- Loading: a skeleton list mirroring the row geometry (72pt thumb + three lines), no spinner takeover.
- Empty: `EmptyState`, per segment — "No active bids" / "Nothing here yet", with a "Find something"
  action on Active.
- Error: the same `ScreenState`; no raw Postgres string reaches the user.

## 11. Navigation

Unchanged. Bids stays a tab; no new Tickets tab; routes into listing detail and transfer receive are
preserved. The header dropped the hardcoded `paddingTop: 56` for the real safe-area inset.

## 12. kernel.tickets constraint

Honoured. `kernel.tickets` is not queried; no My Tickets, QR, barcode, wallet CTA or ticket object is
created; nothing claims ticket ownership beyond the transfer state. A source-guard test fails if any
of `kernel.tickets`, a `tickets` table read, "Apple Wallet", `.pkpass`, QR or barcode appears in the
screen.

## 13. Accessibility

Each card is one composed announcement (event, venue, state, price) with the action as a hint; the
header is a `header`; segments carry `selected` state; state is always a word plus tone; the skeleton
is hidden from assistive tech; press feedback and grouping respect reduced motion via the Phase 0
primitives; 44pt targets throughout.

## 14. Motion

Only the shared press feedback and the skeleton pulse. No celebration, no pulsing winning card, no
bouncing, no flashing countdown.

## 15–19. Tests, typecheck, lint

```
npm test  (vitest run)    → Test Files  14 passed (14)
                            Tests      434 passed (434)
npx tsc --noEmit -p .     → clean, exit 0
npm run lint (expo lint)  → 33 problems (0 errors, 33 warnings)
```

New: `tests/bid-state.test.ts` (36 tests) — the auction and purchase status matrix, purchase
precedence, Active/Past grouping, needs-action flags, urgency ordering, per-state copy/price/routing,
the no-colour-only / no-emoji rule, and shipped-source guards (kernel.tickets untouched, data layer
preserved, money via the one helper, no `paddingTop:56`, listing/transfer routes intact).

| | Phase 3 end | Phase 4 end |
|---|---|---|
| Tests / files | 413 / 13 | **434 / 14** |
| Typecheck | clean | **clean** |
| Lint | 33 warnings, 0 errors | **33 warnings, 0 errors** |

No new warnings.

## 20. Physical iPhone verification

**Not done in this session.** Metro serves this worktree and the iOS bundle compiles and serves
(HTTP 200) with the new Bids copy present, so the screen builds into the app. But I did not see it
render: the local iOS Simulator still reports **0 eligible destinations**
(`xcodebuild -showdestinations`; SDK 26.5 present, only a 26.2 runtime), the same environment blocker
as Phases 2–3, and the device pass needs the phone in hand. To review: `npx expo start --dev-client
--tunnel`, open Bids, and walk Active (winning, outbid, won-to-pay, purchased/awaiting, tickets sent),
Past (ended, sold, confirmed), a long event name, a missing-artwork card, narrow width, and a tap into
listing/transfer and back.

## 21. States not reproducible on device

None require faking data: bids, wins, purchases and transfer states all arise from real activity on
the account. Nothing in this phase modifies production records to manufacture a state. If a specific
state (e.g. disputed) is not present on Jose's account, it can be exercised through the normal flow or
left unverified and noted — no fixture writes are needed or used.

## 22. Core dependency discovered

None new. Re-noted: `kernel.tickets` SELECT is still absent, which is why ownership is expressed
through transfers rather than a canonical Tickets surface. No stable error-code vocabulary (the screen
maps failures to `ScreenState` and logs details). 093 undeployed / native flags false — Bids is
marketplace-only.

## 23. Phase 5 readiness (after owner review)

Ready pending Jose's device approval of Phase 4. Phase 5 (Selling + Create Listing) is a distinct
surface (`CreateListingScreen`, my-listings, `SellerListingCard`) that reuses the primitives, the
media pipeline and `StatCardStrip` (still used by Profile), and does not depend on anything this phase
changed. As with every phase: run Phase 4 on the phone, approve, checkpoint it, then start Phase 5 on
a branch from that checkpoint.
