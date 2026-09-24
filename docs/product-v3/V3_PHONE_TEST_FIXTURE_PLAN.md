# V3 phone-test build — bounded sandbox fixture plan

**C → owner, 2026-09-24.** One sandbox EAS `preview` build is authorised once the V3 candidate passes its
implementation and review gates (owner, 2026-09-24). This plan is what that build needs on the shared
sandbox — nothing more. **It authorises nothing by itself**: every write below is listed so the owner can
approve or strike it; unlisted writes do not happen. **W1 and W2 are NOT executed** (owner, 2026-09-24) —
their real side effects are traced in §3b and B's appendix, and each needs the owner's word for that line.
No production project is touched, no store submission, no second build.

| | |
|---|---|
| Project | sandbox **`ofaidukbieeekqaboscm`** only — the project `eas.json` profile `preview` compiles in (`EXPO_PUBLIC_APP_ENV=sandbox`) |
| Production `hqycwntpfoztoinemqns` | not touched — no read, no write |
| Build | one EAS `preview` (iOS internal distribution), pinned to one commit recorded here before the build |
| Reads by C | **none directly.** Every read-back is A's, inside the owner's window |
| Writes by C | **none typed by hand — but the device checks are not write-free.** W2 intrinsically creates a Stripe test-mode PaymentIntent and a pending `payments` row the moment checkout mounts; W1 intrinsically dispatches two push-trigger notifications. Both are listed in §3/§3b with their cleanup, and **neither is executed** |

## 1 · Accounts and fixtures reused (A's records; nothing new is created)

| Fixture | Id | Used by |
|---|---|---|
| DV buyer `sandbox-buyer@snatchit.test` | `919d511e-c4e6-4422-a71d-e2bc0139de65` | every buyer-side check; Appearance; Tickets (empty state) |
| DV seller | `2f5844b4-5144-4cd6-936d-4b59d8d5c6a0` | Sell / My listings / transfer send; second account for D-6 |
| Listing "Phone P1" (image 400s) | `c343406e-be85-49c1-9951-ac08bb1daab2` | D-2 photo fallback in both appearances (feed row, hero, checkout thumbnail) |
| Listing "Device D7" (image 400s) | `b1c3c478-b32e-4167-8f8d-2b9a4a4fd212` | same, second sample |
| Listing "Device D8" (image 400s) | `58cc00e3-e219-4095-9b57-cbdaa83df421` | same, third sample |
| PENDING transfer | `92ee5156-7e82-40d8-ab54-73b489997797` | receive screen · pending board, both appearances |
| SELLER_SENT transfer, no proof | `8f59d37e-52fd-4733-b311-532445ff441c` | receive · seller_sent (deadline line), send · marked-sent (F-28), both appearances |

The DV buyer's 21 disputed purchase rows (A, 2026-09-17) give the Bids tab and the order boards real rows without
any fixture write.

## 2 · What each device check needs, and where it comes from

| Check | Needs | Source | Sandbox write? |
|---|---|---|---|
| **D-9 Appearance** — System / Light / Dark, persistence across relaunch, live phone change, no startup flash | any signed-in account | reuse | none |
| **D-1 mixed-case leading** | any live listings (49 on the sandbox) | reuse | none |
| **D-2 contrast over real artwork + photo fallback** | listings with real uploads; P1/D7/D8 for the fallback plate | reuse | none |
| **D-3 enlarged text · D-4 narrowest width · D-5 keyboard (Sell form, bid entry)** | the Sell form and an open auction | reuse | none — the form is not submitted |
| **D-6 avatar across account switch** | buyer then seller on one device | reuse | none (auth only; the push-token rules of DV-611 apply and are A's read-back) |
| **Bid screen "Current bid" / three-row summary** | an open auction with ≥ 1 bid | **unknown** — needs A's authorised read (a) | one bid by the DV buyer if none exists (§3) |
| **"Buy both now" verb** | an active quantity-2 listing with buy_now | manifest records one (DV-609) at the last window; current state needs read (b) | none to see the verb; a Buy Now hold only if the checkout board is exercised (§3) |
| **Checkout boards, both appearances** (server-figures-only rows, "Preparing your total", price-change, hold lost) | a Buy Now hold on a live listing | DV-609 listing | **W2 — a hold AND a PaymentIntent** (§3b): entering the screen runs setup on mount; no charge, but not "no payment" |
| **Transfer cells: expired · reversed · held with `payout_hold_until`** (D-7) | rows in those states | none known (A) — needs read (c) | **none proposed.** If read (c) finds none these cells are **explicitly UNVERIFIED on-device** for this build — passing another transfer state does not cover them |
| **D-8 Tickets RPC** | `public.get_my_tickets()` on this sandbox | A's catalog read (owner-authorised, optional item in A's report) | none; `kernel.tickets` stays 0 — populated Tickets fixtures remain excluded (A's manifest §6) |

## 3 · Permitted writes — each one named, each with its cleanup

Nothing here runs without the owner's word for that line.

| # | Write | By | Why | Cleanup | Owner decision |
|---|---|---|---|---|---|
| W1 | One **bid** by the DV buyer on one open auction (only if read (a) finds none with bids) | the handset, C driving | "Current bid" line, Bid/Fee/Total rows, "You're leading" only after the fresh read | A records the bid id. **Side effects beyond the row — see §3b: two push-trigger dispatches and a possible auction win after the window.** Not "no payment follows" | ☐ **NOT executed** |
| W2 | One **Buy Now hold** on the quantity-2 listing, then the checkout screen | the handset | checkout boards in both appearances; "Buy both now" → reserved → checkout | `release_reservation` before the window closes — never left to lapse (A's rule) — **plus whatever A rules for the PaymentIntent and the pending `payments` row that entering the screen creates (§3b)** | ☐ **NOT executed** |
| W3 | **None** for transfer states | — | — | — | — |
| W4 | Appearance preference | the handset (AsyncStorage) | D-9 | device-local; not a sandbox write | n/a |

Explicitly **not** requested: any payment-sheet confirmation (a charge), any `finalize`, any `kernel.tickets`
row, any change to a flag, any migration on the sandbox. A push registration happens as a side effect of
sign-in (DV-611 rules) and is A's read-back, not a fixture.

## 3b · What W1 and W2 actually do — traced in source (C, after B's appendix below), nothing executed

**W2 — entering checkout initialises a payment without a Pay tap.** `CheckoutNative.tsx:211` runs setup in a
mount effect; `setupDecision.ts:229` calls `createIntent()` whenever no settled payment exists and the hold is
the buyer's; that is `payments.ts:198` → the `create-payment-intent` edge function, which creates a **Stripe
test-mode PaymentIntent** and persists a **pending `payments` row** for the buyer and listing (the function's
own retire path later cancels stale pending intents and marks their rows `failed`; `release_reservation` (127)
releases the hold and touches no `payments` row). So W2 = **one hold + one PaymentIntent + one pending
`payments` row; no charge.** Cleanup beyond the hold is **A's ruling**: cancel the intent and retire the row,
or leave them to the function's own retire path on the next attempt. **Reaching the checkout boards in both
appearances cannot be done without this** — the setup runs on mount.

**W1 — a bid does not stop at the row.** `bids` insert → `listings.current_bid` moves (trigger) →
`trg_notify_bid_inbox` (058) writes inbox rows, and the production-era `bids.on_new_bid_notify` trigger posts
through pg_net to `send-push` for **`bid_received` (the seller)** and **`outbid` (the previous leader)**; per
F-23 no preference is consulted. On the sandbox under option (b) `send-push` refuses every dispatch (A's
records, 2026-09-16) — **A confirms that is still the sandbox state.** After the window, if that auction
ends with the DV buyer leading, `auto_finalize_expired_auctions` sets the winner (→ `auction_won` inbox row)
and the buyer owes payment. So W1 needs either an auction whose seller is the **DV seller** with no other
bidder, and an end time A confirms is outside any window where a win matters — or it is not run and the bid
screen's "Current bid" state is read from an existing auction with bids (read (a)).

**Rule for both (owner, 2026-09-24):** not executed yet; existing fixtures first; the three transfer states
without fixtures are **unverified on-device** and recorded as such.

## 4 · Reads C asks A to make (owner-authorised, read-only)

(a) open auctions with `bid_count ≥ 1` · (b) active listings with `quantity ≥ 2 and buy_now_price is not null` ·
(c) transfers by status in (`expired`, `reversed`) and `payout_review_status = 'held' and payout_hold_until is not null`
· (d) the `get_my_tickets` catalog check (three statements, in A's report). C writes nothing and runs nothing
against the sandbox.

## 5 · Pre-build gates — everything here is source, CI or review. No device evidence.

**Device verification cannot gate the build that produces it.** Nothing in this table requires a phone.

| | |
|---|---|
| Commit | _pinned here, full sha from `git rev-parse`, before `eas build`_ |
| Checks at that commit | `npm run typecheck` 0 · `npm run lint` 0 errors · full `vitest` **run alone**, clean · predicted mutants killed |
| Implementation closed | A-1…A-5 appearance literals · R-5 via the resolver · F-28 |
| Review closed | **B:** inventory reconciled, pressed value agreed, light designs delivered for every surface C has implemented · **A:** checkout ruling implemented, transfer cells PASS |
| Profile | `preview` · iOS internal · one build |

**Not a pre-build gate:** D-1…D-9, the appearance device checks, and every row in §2. Those are what the
build is *for*.

## 6 · Post-build — the device pass

Runs only once the build exists. Results are recorded as **device** evidence; nothing in §5 is restated as
device evidence, and nothing here is a prerequisite for §5.

| Group | Checks |
|---|---|
| Appearance | D-9 (three settings, persistence across relaunch, live phone change, **no startup flash**), both status bars, keyboard appearance, native dialogs |
| Rendered colour | Every combination in §2 **as rendered** — including disabled controls, selected states, overlays and artwork. **A component accepting a palette is not evidence that it renders correctly** |
| Type and layout | D-1 mixed-case leading · D-3 enlarged text · D-4 narrowest width · D-5 keyboard |
| Media | D-2 contrast over real uploads and the fallback plate, both appearances |
| Identity | D-6 avatar across account switch |
| Data-dependent | D-7 transfer cells (see §7) · D-8 Tickets |

## 7 · The three states with no fixtures — a bounded option

**`expired`, `reversed` and `held` have no sandbox rows.** They stay **explicitly unverified on device**, and
**another transfer state passing does not cover them.** A's source PASS of the cells is source evidence.

Three ways forward, in order of cost:

| | Option | What it proves | What it does not |
|---|---|---|---|
| **1** | **Extend the existing `app/_dev/foundation.tsx` gallery** to render the five blocks (buyer expired, buyer reversed, seller reversed, held-with-`payout_hold_until`, review deadline) from **synthetic props**, and gate it on `EXPO_PUBLIC_APP_ENV === 'sandbox'` instead of `__DEV__` | **Device evidence of rendering**: layout, contrast in both appearances, large text, wrapping — on the real handset | **Nothing about whether the real status reaches the screen.** The data path stays untested. **Needs C to change the gate**, because `__DEV__` is false in a `preview` build, so the gallery is unreachable there today |
| **2** | A creates sandbox transfer rows in those states | The full path, end to end | A fixture mutation with its own cleanup — **an owner decision, not A's to take** |
| **3** | Leave them uncovered | — | Records the gap honestly and ships the build without them |

**Recommendation: option 1**, with its limit stated in the result — *"rendering verified on device; the data
path for these three states is not."* Option 2 only if the owner wants the data path covered in this build.
