# V3 phone-test build — the executable plan (fixtures, gates, device pass)

**C, with B's sections and A's sandbox reads · 2026-09-24.** One sandbox EAS `preview` build is **already
authorised** (owner, 2026-09-24), conditional on the pre-build gates in §5; no further authorisation is
requested. This document is the runbook: what the build needs on the shared sandbox, what each device check
intrinsically does there, and the exact owner decisions that remain. **It authorises nothing by itself.**
No production project is touched; no store submission; no second build.

| | |
|---|---|
| Project | sandbox **`ofaidukbieeekqaboscm`** only — the `eas.json` profile `preview` compiles it in (`EXPO_PUBLIC_APP_ENV=sandbox`) |
| Production `hqycwntpfoztoinemqns` | not touched — no read, no write |
| Build | one EAS `preview` (iOS internal), pinned to one commit recorded in §5 before `eas build` |
| Reads | A's, owner-authorised: **done 2026-09-24 ~04:00Z** (`docs/release/SANDBOX_D8_READS_20260924.md` @ `56ae4e4c`). C runs nothing against the sandbox |
| Writes | **none by hand.** The device checks are not write-free: W2 creates a Stripe test-mode PaymentIntent and a pending `payments` row the moment checkout mounts; W1 writes a bid, the listing counters and one inbox row. Each is an owner decision (§7) and **neither is executed** |

## 0 · Implementation coverage this plan is measured against

`v3/midnight-app` @ **`212783f2`** (A-1 hairlines and the gallery land in the next commit). By **actual static
colour access** (comments stripped; `v2.space` / `v2.radius` / type need no conversion): **54 files, 546
references** still read Midnight-only colour tokens; 14 files read the palette only; 1 is partial
(`app/_layout.tsx`, 2 refs). Largest: Create 58 · `_dev/foundation` 32 · receive 30 · send 29 · notifications
27 · profile/[id] 27 · Checkout 25. **Design coverage is not implementation:** B has drawn ten surfaces in
both appearances; the implemented-in-both set is the primitives, the dock, the bid screen and the Appearance
setting. The current matrix is `V3_COVERAGE_MATRIX.md` (one file, kept current by B and C).

## 1 · Accounts and fixtures reused — A's reads, nothing new created

| Fixture | Id | Used by |
|---|---|---|
| DV buyer `sandbox-buyer@snatchit.test` | `919d511e-c4e6-4422-a71d-e2bc0139de65` | every buyer-side check; Appearance; Tickets (empty state); the buyer boards (**42 payment rows, 25 transfers, 6 disputed**) |
| DV seller | `2f5844b4-5144-4cd6-936d-4b59d8d5c6a0` | Sell / My listings / transfer send; second account for D-6 |
| Listing "Phone P1" (image 400s) | `c343406e-be85-49c1-9951-ac08bb1daab2` | D-2 fallback plate · **ends 2026-09-24 23:35:37Z** · carries the buyer's pending intent `9f4ab181` |
| Listing "Device D7" (image 400s) | `b1c3c478-b32e-4167-8f8d-2b9a4a4fd212` | D-2 · **ends 2026-09-25 02:01:44Z** |
| Listing "Device D8" (image 400s) | `58cc00e3-e219-4095-9b57-cbdaa83df421` | D-2 · **ends 2026-09-25 02:01:44Z** |
| PENDING transfer | `92ee5156-7e82-40d8-ab54-73b489997797` | receive · pending board |
| SELLER_SENT transfer, no proof | `8f59d37e-52fd-4733-b311-532445ff441c` | receive · seller_sent + review deadline; send · marked-sent body (F-28) |
| **REVERSED transfers (4, DV pair)** | `e6941c3f-d08b-4382-b990-7fd74fa7dbd3` · `b640737b-64a9-44d2-a405-ab665912604f` · `acbfd9fe-dcd8-4502-9d8d-39745cfbe765` · `ddeb0d69-a007-4050-9fa9-8b8777a5f05d` | **buyer reversed AND seller reversed boards on real rows** — each payment `succeeded` with a NULL refund amount and no `refunded_at`, so the buyer sees "Order closed" + the pending line, never a figure |

**Live listings: 3 now (the three above; quantity 1, buy_now 100, 0 bids), 0 after 2026-09-25 02:01:44Z
without owner decision D1.** `public.bids` holds 0 rows. No quantity-2 listing exists. `expired` 0, `held` 0.

## 2 · What each device check needs, and what it does on the sandbox

| Check | Needs | Source | Sandbox effect |
|---|---|---|---|
| **D-9 Appearance** — System / Light / Dark, persistence across relaunch, live phone change, no startup flash | any signed-in account | reuse | none |
| **D-1 mixed-case leading** | live listings | the 3 above (D1 after 02:01Z) | none |
| **D-2 contrast over artwork + the fallback plate** | P1 / D7 / D8 (image 400s) | reuse | none |
| **D-3 enlarged text · D-4 narrowest width · D-5 keyboard** (Sell form, bid entry) | the Sell form; a live listing's bid entry | reuse | none — the form is not submitted, no bid is placed |
| **D-6 avatar across account switch** | buyer then seller on one device | reuse | none (auth only; push-token rules of DV-611 are A's read-back) |
| **Bid screen with ≥ 1 bid, "You're leading", three-row summary after a bid** | an auction with a bid | **none exists** | **W1 (D2)** or source-only (CFT-202/203 tests) |
| **"Buy both now" verb** | a quantity-2 buy-now listing | **none exists** | **D4** or source-only (LP verb tests) |
| **Checkout boards** (server-figures-only rows, "Preparing your total", hold lost) | a Buy Now hold + the checkout screen | D7 / D8 (fresh) or P1 (reuse) | **W2 (D3)**: 10-minute server hold; entering the screen creates 1 PaymentIntent + 1 pending `payments` row on D7/D8, or reuses `9f4ab181` on P1; hold-lost reachable by waiting ~12 min; **price-change is not covered** |
| **Transfer boards: reversed (buyer + seller)** | reversed rows | **4 real rows** | none — read-only |
| **Transfer boards: expired · held-with-`payout_hold_until`** | rows in those states | **none exist** | **gallery (§7) renders the blocks from synthetic props; the data path stays open (D5 / D6)** |
| **D-8 Tickets RPC** | `public.get_my_tickets()` on this sandbox | **CLOSED by A's read**: function present, `security definer`, `search_path=public, pg_temp`, authenticated may execute, anon may not, 17 columns in the client's order, ledger row present, `kernel.tickets` = 0 | none — the build exercises the real RPC and the empty state; populated Tickets stay excluded |

## 3 · The two writes the device checks would make — traced, NOT executed

| # | Write | What actually happens (A's read of THIS sandbox, 04:02Z) | Cleanup | Decision |
|---|---|---|---|---|
| **W1** | One bid by the DV buyer on `58cc00e3` or `b1c3c478` (never `c343406e`) | 1 `bids` row; `listings.current_bid` / `bid_count` / `highest_bidder_id` updated; **1 `bid_received` inbox row for the DV seller**; **no push and no outbound request while option (b) holds** (Vault holds `project_url` only, the GUCs are unset, the 054 `notify_outbid` body returns before posting, every recent outbound request is 401); no `outbid` row (no previous leader). **Finalisation follows `ends_at` unless the bid is deleted first:** job 1 makes the DV buyer the winner and writes an `auction_won` inbox row; **no payment, transfer, charge or push is created by finalisation** | Before `ends_at`, one transaction as `postgres` with `app.bypass_listing_guard`: delete the bid; reset `current_bid = starting_bid`, `bid_count = 0`, `highest_bidder_id = null`; delete the `bid_received` row by id. After `ends_at`: also revert `auction_status`, `winner_user_id`, `winning_bid_amount`, `ended_at`, delete the `auction_won` row, set a future `ends_at`. Read-back: bids 0, counters, notification count, row md5s | **D2 — NOT executed** |
| **W2** | One Buy Now hold on D7 / D8 (or P1), then the checkout screen | The server sets a **10-minute** hold (`p_minutes` ignored). Entering checkout runs setup on mount (`CheckoutNative.tsx:211` → `setupDecision.ts:229` → `create-payment-intent`): on D7 / D8 the **FRESH** path — exactly 1 new test-mode PaymentIntent + 1 pending `payments` row; on P1 the **REUSE** path of `9f4ab181` if intact — 0 new intents. A remount or retry reuses the same intent. `statusUnknown`, `holdLost` and `priceChange` create no intent. **No charge** — that needs the payment sheet confirmed | Hold: `release_reservation` (or lapse). Intent + row: **the only complete cleanup is explicit** — the owner cancels the PaymentIntent in the Stripe test dashboard and a fixture update moves the row `pending → failed`; otherwise the owner accepts one residue row. `release_reservation`, the expiry cleanup, cron and the edges never touch the intent or the row; the function's own retire path fires only for other buyers' rows or on supersede | **D3 — NOT executed** |
| W3 | Appearance preference | device-local (AsyncStorage) — not a sandbox write | — | n/a |

Explicitly not requested: any payment-sheet confirmation, any `finalize`, any `kernel.tickets` row, any flag
change, any migration on the sandbox. A push registration happens as a side effect of sign-in (DV-611 rules)
and is A's read-back, not a fixture.

## 4 · Reads — done

A's owner-authorised reads of 2026-09-24 (~03:49Z and ~04:00Z) answered (a) bids: none · (b) quantity-2: none
· (c) reversed 4 / expired 0 / held 0 · (d) `get_my_tickets`: closed. Ledger 144, signing keys 0, confirmed
before any query. Nothing was written.

## 5 · Pre-build gates — source, CI and review only. No device evidence.

**Device verification cannot gate the build that produces it.** Nothing in this table needs a phone.

| | |
|---|---|
| Commit | _pinned here, full sha from `git rev-parse`, before `eas build`_ |
| Checks at that commit | `npm run typecheck` 0 · `npm run lint` 0 errors · full `vitest` **run alone**, clean · predicted mutants killed |
| Implementation closed | A-1…A-5 rendered literals (`212783f2`) · R-5 via the resolver (`212783f2`) · F-28 (`212783f2`) · **A-1 neutral hairlines** · **the synthetic gallery, sandbox-gated** · **the remaining static-colour files (§0) migrated, or the exact list of surfaces still Midnight-only in the Light appearance recorded here** |
| Review closed | **B:** inventory reconciled against §0; pressed value agreed (`#FF5353`); light designs delivered for every surface C has implemented · **A:** checkout ruling implemented (`016087ea`); transfer cells PASS (`7e578ed5`); D-8 closed |
| Profile | `preview` · iOS internal · one build |

**Not a pre-build gate:** D-1…D-9 and every row in §2. Those are what the build is *for*.

## 6 · Post-build — the device pass

Runs only once the build exists. Results are recorded as **device** evidence; nothing in §5 is restated as
device evidence.

| Group | Checks |
|---|---|
| Appearance | D-9 (three settings, persistence across relaunch, live phone change, **no startup flash**), both status bars, keyboard appearance, native dialogs |
| Rendered colour | Every combination in §2 **as rendered** — disabled controls, selected states, overlays, artwork. A component accepting a palette is not evidence that it renders correctly; the harness-rendered contrast tests (`v3-appearance-rendered`) are not device evidence either |
| Type and layout | D-1 mixed-case leading · D-3 enlarged text · D-4 narrowest width · D-5 keyboard |
| Media | D-2 contrast over real uploads and the fallback plate, both appearances |
| Identity | D-6 avatar across account switch |
| Transfers | reversed boards on the 4 real rows (buyer and seller) · the gallery pass for expired / held / deadline / refund combinations (§7) |
| Tickets | D-8 on the build: the real RPC, the empty state |

## 7 · Expired and held — no rows; a bounded, owner-authorised way to see them

**`expired` and `held` have no sandbox rows** (A, 04:00Z). `reversed` has four. So:

- **Reversed** is verified on device through real data (both roles).
- **Expired and held** are rendered on device through the **synthetic gallery** — `app/_dev/transfer-states.tsx`,
  reachable only from a sandbox-build Settings row, redirecting home in any other build, importing no client,
  offering no action. It renders the SAME blocks the real screens render
  (`src/components/transfer/TransferStateBlocks.tsx`) from labelled synthetic props: fourteen cases covering
  A's approved status / refund / hold combinations, in both appearances, at the phone's text size.

**Evidence, recorded precisely:** a gallery pass proves **rendering with supplied props**; the block and
screen tests prove **the mappings they exercise**; **neither proves live sandbox retrieval or the full device
data path.** That data-path gap stays **open for a release decision** — it is not accepted for App Store
submission by passing another state, and it closes only through D5 / D6 or real rows later.

## 8 · The exact remaining owner decisions (from A's record §7; A cannot take any of them)

| # | Decision | Fixture | Side effects | Cleanup |
|---|---|---|---|---|
| **D1** | Extend `ends_at` on the three live listings, or accept a sandbox with **no live listing after 2026-09-25 02:01:44Z** | `c343406e`, `b1c3c478`, `58cc00e3` | as `postgres` with `app.bypass_listing_guard`; no notification trigger keys on `ends_at` | restore the three values |
| **D2** | **W1** — one bid, or strike W1 (bid-with-bids screens stay source-only) | `58cc00e3` or `b1c3c478` | §3 W1 | §3 W1 |
| **D3** | **W2** — one hold + checkout entry, or strike W2 (checkout boards stay source-only) | `b1c3c478` / `58cc00e3` (fresh) or `c343406e` (reuse) | §3 W2 | §3 W2 |
| **D4** | "Buy both now": set `quantity = 2` on one DV listing, create a quantity-2 listing from the Sell form, or strike (verb stays source-only) | `58cc00e3` or new | one column; or a listing insert + upload | restore `quantity = 1`; or cancel |
| **D5** | An `expired` fixture on `19be875b…` (A's F-EXP) — closes the buyer-expired **data path** | `19be875b…` | none beyond the row | restore to md5 `a4c234da…` |
| **D6** | A `held` fixture with `payout_hold_until` on `83b83858…` (A's F-HELD) — closes the seller-held **data path** | `83b83858…` | none beyond the row | restore to md5 `d1b36045…` |

Reversed: no decision (4 real rows). Tickets RPC: closed. **None of D1–D6 is approved; A brings them to the
owner.** The build does not wait for them: without D2–D4 the affected screens are exercised in their real,
current sandbox states and the rest stays source-only; without D5 / D6 the gallery renders the visuals and
the data path stays open.
