# V3 phone-test build — bounded sandbox fixture plan

**C → owner, 2026-09-24.** One sandbox EAS `preview` build is authorised once the V3 candidate passes its
implementation and review gates (owner, 2026-09-24). This plan is what that build needs on the shared
sandbox — nothing more. **It authorises nothing by itself**: every write below is listed so the owner can
approve or strike it; unlisted writes do not happen. No payment is created, no notification is sent, no
production project is touched, no store submission, no second build.

| | |
|---|---|
| Project | sandbox **`ofaidukbieeekqaboscm`** only — the project `eas.json` profile `preview` compiles in (`EXPO_PUBLIC_APP_ENV=sandbox`) |
| Production `hqycwntpfoztoinemqns` | not touched — no read, no write |
| Build | one EAS `preview` (iOS internal distribution), pinned to one commit recorded here before the build |
| Reads by C | **none directly.** Every read-back is A's, inside the owner's window |
| Writes by C | **none.** The only writes are the ones the device checks intrinsically produce (listed in §3) |

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
| **Checkout boards, both appearances** (server-figures-only rows, "Preparing your total", price-change, hold lost) | a Buy Now hold on a live listing | DV-609 listing | **one hold**, released by `release_reservation` (§3) — no payment |
| **Transfer cells: expired · reversed · held with `payout_hold_until`** (D-7) | rows in those states | none known (A) — needs read (c) | **none proposed.** If read (c) finds none these cells stay **source-only** for this build and the plan says so |
| **D-8 Tickets RPC** | `public.get_my_tickets()` on this sandbox | A's catalog read (owner-authorised, optional item in A's report) | none; `kernel.tickets` stays 0 — populated Tickets fixtures remain excluded (A's manifest §6) |

## 3 · Permitted writes — each one named, each with its cleanup

Nothing here runs without the owner's word for that line.

| # | Write | By | Why | Cleanup | Owner decision |
|---|---|---|---|---|---|
| W1 | One **bid** by the DV buyer on one open auction (only if read (a) finds none with bids) | the handset, C driving | "Current bid" line, Bid/Fee/Total rows, "You're leading" only after the fresh read | none needed for the app; A records the bid id; **no payment follows** (the auction is not finalised in the window) | ☐ |
| W2 | One **Buy Now hold** on the quantity-2 listing | the handset | checkout boards in both appearances; "Buy both now" → reserved → checkout | released explicitly with `release_reservation` before the window closes — never left to lapse (A's rule) | ☐ |
| W3 | **None** for transfer states | — | — | — | — |
| W4 | Appearance preference | the handset (AsyncStorage) | D-9 | device-local; not a sandbox write | n/a |

Explicitly **not** requested: any payment intent confirmation, any `finalize`, any `send-push` dispatch, any
`kernel.tickets` row, any change to a flag, any migration on the sandbox. A push registration happens as a side
effect of sign-in (DV-611 rules) and is A's read-back, not a fixture.

## 4 · Reads C asks A to make (owner-authorised, read-only)

(a) open auctions with `bid_count ≥ 1` · (b) active listings with `quantity ≥ 2 and buy_now_price is not null` ·
(c) transfers by status in (`expired`, `reversed`) and `payout_review_status = 'held' and payout_hold_until is not null`
· (d) the `get_my_tickets` catalog check (three statements, in A's report). C writes nothing and runs nothing
against the sandbox.

## 5 · Build pin and gates (filled in before the build)

| | |
|---|---|
| Commit | _pinned here, full sha from `git rev-parse`, before `eas build`_ |
| Gates at that commit | `tsc` 0 · `lint` 0 errors · full `vitest` alone, clean · controls as predicted |
| Reviews closed | B: inventory reconciled, pressed value one · A: checkout ruling implemented, transfer cells PASS |
| Profile | `preview` · iOS internal · one build |

---

# B · Side-effect trace of W1 and W2 (2026-09-24) — source-traced, not assumed

**Both rows understate what happens. Traced on `v3/midnight-app` @ `3f295bca`; nothing executed.**

## W2 — "one hold, released by `release_reservation` — no payment" is incomplete

**Navigating into checkout initialises a payment. No Pay tap is required.**

`CheckoutNative.tsx:211` runs `setupPayment()` in a mount effect gated only on `authLoading` and `user?.id`.
It calls `decideCheckoutSetup`, which is settled-first → hold → intent, and at
**`setupDecision.ts:229`** reaches `const intent = await deps.createIntent();` whenever no settled payment
exists and the hold is the buyer's. `createIntent` is
`payments.ts:198` → `supabase.functions.invoke('create-payment-intent')`.

**W2's actual side effects on the sandbox:**

| | |
|---|---|
| 1 | The Buy Now hold (`reserve_buy_now`) — as recorded |
| 2 | **A Stripe PaymentIntent created by `create-payment-intent`**, on the sandbox Stripe account |
| 3 | Whatever that function writes server-side — `payments.ts:53` refers to a **"reuse" path**, so an intent is persisted and re-found, not created fresh each time |
| 4 | `initPaymentSheet` is then called locally with that intent |

**No charge occurs** — that needs the payment sheet confirmed. **But "no payment" is the wrong word for a
created PaymentIntent.** The accurate line is *"one hold and one PaymentIntent; no charge."*

**Consequences for the plan:** the release step must cover the intent as well as the hold — A confirms
whether `release_reservation` leaves an intent open, and whether an open sandbox intent needs cancelling.
**Reaching the checkout boards in both appearances cannot be done without creating an intent**, because the
effect runs on mount.

## W1 — "no payment follows" is true, and it is not the whole side effect

`PlaceBidScreen.tsx:181` inserts into `bids`. A DB trigger moves `listings.current_bid`. Beyond that,
migration **058_notification_producers.sql** (and the existing `notify_bid_placed` / `notify_outbid`
**pg_net push triggers**) fire on that insert:

| Produced | To |
|---|---|
| **`bid_received`** | **the seller of the listing** |
| **`outbid`** | **the previous high bidder** (self-outbid is skipped) |

Both are dispatched through **pg_net push triggers**, so these are **real dispatch attempts, not just rows**.
Per **F-23**, `send-push` applies **no notification preference** to these.

**And the bid does not stop when the window closes.** It enters auction finalisation: if that auction ends,
this bid can **win**, which creates an order and a transfer obligation for the DV buyer. *"The auction is not
finalised in the window"* describes the window, not the bid's lifetime.

**Consequences for the plan:** pick a listing whose seller and previous leader are **fixture accounts**, or
accept that two notifications leave the system. **A confirms the auction's end time is outside the window
and that a win would be acceptable if it happens.**

**Neither W1 nor W2 has been executed.**
