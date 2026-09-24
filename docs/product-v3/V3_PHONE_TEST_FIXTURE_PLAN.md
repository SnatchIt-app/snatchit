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

`v3/midnight-app` @ **`9c6c9bf4`** (pushed). **The appearance migration is complete**: by actual static colour
access, comments stripped, **0 consumer files** still read Midnight-only colour tokens, down from 53 files /
546 refs. The only static readers left are the palette definition and the dev-only foundation screen, and
`AM1`/`AM2` scan the whole tree so a third exemption cannot appear quietly. The candidate carries complete
System / Light / Dark support — **there is no longer a "Light-appearance exception", and this plan no longer
records one** (owner 2026-09-24: it "must not become permission to build a knowingly incomplete light mode").

Four defect classes that a static-token count cannot see were found and closed as part of it: three
transfer-flow components that were never on v2 and still imported the pre-v2 `colors` module; text over
artwork renamed to canvas inks; the ink on a saturated status fill, which must flip with the scheme; and the
brand red used as text at 3.88:1. B measured four of these independently (F-31…F-34) plus six judgement calls
(N-1…N-6); F-31, F-32, F-33, F-34, N-1, N-4 and N-5 are implemented, and N-2, N-3 and the colour-alone
findings are recorded as design or copy decisions that do not block the build. Detail and the evidence states
(designed / implemented / tested / device-verified) are in `V3_COVERAGE_MATRIX.md`, which is the one current
coverage list.

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
| **W1** | One bid by the DV buyer on `58cc00e3` or `b1c3c478` (never `c343406e`) | 1 `bids` row; `listings.current_bid` / `bid_count` / `highest_bidder_id` updated; **1 `bid_received` inbox row for the DV seller**; **no push and no outbound request while option (b) holds**; no `outbid` row (no previous leader). **Finalisation follows `ends_at` unless the bid is deleted first:** job 1 makes the DV buyer the winner and writes an `auction_won` inbox row; **no payment, transfer, charge or push is created by finalisation.** **Reconciliation of the two traces:** B's source trace read the repo's producers (`notify_bid_placed`, `notify_outbid` → pg_net → `send-push`) and concluded two dispatches. A verified the DEPLOYED sandbox at 04:02Z: the five triggers on `public.bids` (`before_bid_insert`, `trg_sync_listing_current_bid`, `on_new_bid_notify`, `trg_notify_bid_placed`, `trg_notify_bid_inbox`) are all enabled, but `on_new_bid_notify` → the 054 `notify_outbid` body reads GUCs that are unset and returns before posting, `trg_notify_bid_placed` → the 133 `notify_bid_placed` body needs two Vault secrets and Vault holds `project_url` only, `enqueue_notification` writes `public.notifications` only (never `notify.outbox`), and every recent outbound request is 401. So on THIS sandbox the effect is one inbox row and no dispatch — a configuration fact (option (b)), not a source fact; it holds only while that configuration holds, and B's trace describes what a production-shaped configuration would do | Before `ends_at`, one transaction as `postgres` with `app.bypass_listing_guard`: delete the bid; reset `current_bid = starting_bid`, `bid_count = 0`, `highest_bidder_id = null`; delete the `bid_received` row by id. After `ends_at`: also revert `auction_status`, `winner_user_id`, `winning_bid_amount`, `ended_at`, delete the `auction_won` row, set a future `ends_at`. Read-back: bids 0, counters, notification count, row md5s | **D2 — NOT executed** |
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
| Commit | **`9c6c9bf4e6f9c201efe1fe760d2bf6ae12175d7f`** (`v3/midnight-app`, pushed) — pinned before `eas build` |
| Checks at that commit | `npx vitest run` **144 files, 2675/2675, run alone** at load average 4.16 with no peer vitest · `npx tsc --noEmit` **0** · `npm run lint` **0 errors, 29 warnings** (baseline) · negative controls: **three mutants, each killed by exactly the predicted gate** (AM1 / RD8 / AM4), clean baseline, digest-verified restore |
| Implementation closed | A-1…A-5 rendered literals (`212783f2`) · R-5 via the resolver (`212783f2`) · F-28 (`212783f2`) · A-1 neutral hairlines (`6c7fc18b`) · the synthetic gallery, sandbox-gated, with its tested Settings entry (`6c7fc18b`, hardened `2619b9e1`) · **the complete appearance migration (`4d1e4b3d`)** · **B's measured Daylight failures F-31/F-32/F-33/F-34/N-1/N-4/N-5 (`9c6c9bf4`)** |
| Owner's four acceptance conditions | **1.** No reachable consumer surface unintentionally uses the dark-only palette in Light — AM1/AM2 over the whole tree, AM4 for the legacy module, RD13 for red-as-text. **2.** Root layout responds correctly — splash inside the provider gate reading the palette (AM3), navigation theme and status bar already following the scheme, no dead token import. **3.** Literal colours individually classified — AM5, one written reason each, and the one reason that is a claim about the codebase is checked rather than asserted. **4.** Previously closed behavioural fixes intact — full suite green, including the R-5, F-28, gallery, transfer-cell and checkout-stage suites |
| Review | **B:** inventory reconciled; pressed value agreed (`#FF5353`); light designs delivered for the account group (`04220c3f`); review of C at `2619b9e1` closed (`ea4d7f88`); **independent traces of both remaining groups delivered and their measured failures now implemented** — B's group-by-group review of the migration commits themselves (`4d1e4b3d`, `9c6c9bf4`) is **outstanding**, and is a peer review, not an owner gate · **A:** checkout ruling implemented (`016087ea`); transfer cells PASS (`7e578ed5`); D-8 closed |
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
- **Expired and held** are rendered on device through the **synthetic gallery** — `app/_dev/transfer-states.tsx`
  (`6c7fc18b`). It renders the SAME blocks the real screens render
  (`src/components/transfer/TransferStateBlocks.tsx`) from labelled synthetic props: fourteen cases covering
  A's approved status / refund / hold combinations, in both appearances (in-page System / Light / Dark
  switch), at the phone's text size. **How it is opened on the sandbox iPhone build:** Settings › a
  "Sandbox" section › "Transfer states (sandbox gallery)" — the section and row render only in a paired
  sandbox build (`IS_SANDBOX_BUILD`), and pressing the row navigates to the route; both are rendered tests
  through the real Settings screen (`v3-gallery-entry` SG1 / SG2). **How production cannot render it:** the
  guard is component-level and runs at render — `if (!(IS_SANDBOX_BUILD || __DEV__)) return <Redirect …/>`
  (TG5 renders the route with the flag off and gets only the redirect) — while the module's static imports
  run at load, so they are held to a whitelist of side-effect-free modules (blocks, transfer wording, theme,
  env verdict; no client, storage, network or dialog — TG8). The date rules: a missing `payout_hold_until`
  or `auto_release_at` suppresses only the corresponding date line, never the status sentence (TG9).

**Evidence, recorded precisely:** a gallery pass proves **rendering with supplied props**; the block and
screen tests prove **the mappings they exercise**; **neither proves live sandbox retrieval or the full device
data path.** That data-path gap stays **open for a release decision** — it is not accepted for App Store
submission by passing another state, and it closes only through D5 / D6 or real rows later.

## 8 · The exact remaining owner decisions — A's approval sheet governs

**The one approval sheet is A's: `docs/release/SANDBOX_V3_FIXTURE_APPROVAL_SHEET_20260924.md` on
`release/candidate-20260918` @ `20ef22b7` — full fixture ids, exact deadline extensions and held-state values,
test dependencies, before-state capture, cleanup order and owner, the Stripe step for W2's intent, and the
verified W1 trace (its §2 supersedes the paragraph in §3 above where they differ). It is NOT approved.** The
table below is the summary only; the sheet is what the owner signs.

**Device rules the sheet fixes (A, 2026-09-24), which §6 follows:** W1 is exactly one bid of $105 (the
screen's preselected minimum) on `58cc00e3` only. W2 is the only Buy Now of the session, on `b1c3c478` only,
after its quantity is set to 2 — `reserve_buy_now` releases any other active hold by the same buyer, so a second
Buy Now anywhere kills W2's hold. `c343406e` is not extended and must not enter checkout (it carries the DV
buyer's old pending intent `9f4ab181`). In W2 never tap Pay: capture the Light and Dark boards within the
10-minute hold, stay on the screen, at 10:00 the countdown shows the hold-lost board, then leave with Back.
"Buy both now" will show a $110 total because the server charges `buy_now_price` whatever the quantity — a
product question the check exposes, not something to change. Device order: no-write checks → W1 → W2 → the
transfer cells (reversed ×4, F-EXP `19be875b`, F-HELD `83b83858`, deadline rows `8f59d37e` and `92ee5156`) →
the buyer-to-seller account switch last. Timing: the writes happen no earlier than 15 minutes before the first
device step, after the build is installed and the owner says go, never while implementation is moving; cleanup
has a fallback deadline of T0 + 2h30m; **C owns the "session done or abandoned" signal that starts cleanup.**

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
