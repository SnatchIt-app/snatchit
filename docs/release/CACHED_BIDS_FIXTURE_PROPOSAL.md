# Cached-bids fixture — exact sandbox proposal (A, 2026-09-17) — **PREPARATION ONLY, NOT EXECUTED**

Owner's request (2026-09-17): "Prepare the exact sandbox bid fixture proposal: account, dedicated listing, amount, expected
auction/payment/notification side effects, notification suppression, and cleanup or retained-record consequences. Do not place
a bid yet. Carry the cached-rows check as untested until the concrete plan is approved and executed."

**SUPERSEDED (2026-09-17, after DV-ST2): the premise below is wrong.** `bids.length` counts the merged list, which includes the buyer's transfers (Build 18 `app/(tabs)/bids.tsx` 183+, 312). The DV buyer's tab held 21 rows, so DV-ST2b is observable without a fixture, and the fixture is not requested. The original text follows unchanged.

**Why a fixture is needed at all.** DV-ST2b (the "cached rows stay" clause of the server-error state) renders only when the
Bids tab already holds rows (`bids.length > 0`, C from source at `bf8b9ba`); `public.bids` on the sandbox holds **0 rows**
(read 2026-09-17 04:27Z), so the clause cannot be observed. Every fact below is from the sandbox's *applied* trigger and
function bodies (catalog reads 04:38–04:40Z), not from the repo.

## 1. The fixture, exactly

| Item | Proposal | Why |
|---|---|---|
| Bidder account | the DV **buyer** `919d511e…` (`sa***@snatchit.test`) | the account the owner already uses for buyer rows; a seller cannot bid on their own listing (`validate_and_apply_bid`) |
| Dedicated listing | **`58cc00e3…` "Device D8"**, seller `2f5844b4…` (the DV seller), `starting_bid` 100, `current_bid` 100, `bid_count` 0, `buy_now_enabled` true, `proof_status` pending_review, `ends_at` **2026-09-25 02:01Z** (the latest-ending active listing without bids) | already exists (no listing write), no bids yet, ends far enough away that the fixture outlives session 2. **C to confirm D8 is not reserved for another device row**; `b1c3c478…` "Device D7" (same end) is the alternate |
| Amount | **$101** | must exceed `current_bid` 100 and be ≤ 25 000 (`bids_amount_upper`); the minimum increment keeps the listing's state change as small as possible |
| Path | **the app's Place bid screen on the owner's handset, signed in as the buyer** (`PlaceBidScreen` inserts into `public.bids` under RLS `bids_insert_authenticated`: `bidder_id = auth.uid()`) | the production path; no service credential, no psql write, and the fixture is exactly what the Bids tab later shows. Alternative (not recommended): one `insert into public.bids(listing_id,bidder_id,amount)` as `postgres`, which bypasses RLS but not the triggers |
| Read-backs (A) | before: `count(*) from public.bids where bidder_id = buyer` = 0; listing `58cc00e3…` current_bid/bid_count/highest_bidder_id = 100/0/null. After: 1 row (id, amount 101, created_at); listing 101/1/buyer; `public.notifications` row `bid_received:<bid id>` for the seller; `net.http_request_queue` count unchanged; `notify.notification` count unchanged | proves the side effects are exactly the ones predicted below |

## 2. Expected side effects at insert time (from the five applied triggers on `public.bids`)
1. `before_bid_insert` → `validate_and_apply_bid`: refuses self-bid, cancelled/ended/expired listing, amount ≤ current bid,
   and a second bid by the same bidder within 3 s; then **updates the listing** (`current_bid` = 101, `bid_count` + 1,
   `highest_bidder_id` = buyer) under `app.bypass_listing_guard` set by the function itself (its own designed bypass, not a
   manual override).
2. `trg_sync_listing_current_bid` → `sync_listing_current_bid`: re-syncs `current_bid` and `updated_at`.
3. `trg_notify_bid_inbox` → `notify_bid_inbox`: **one in-app inbox row for the seller** in `public.notifications`
   (`type` bid_received, "New bid: $101", dedupe `bid_received:<bid id>`, link `/listing/58cc00e3…`); no "outbid" row because
   there is no previous bidder. This is the only notification produced.
4. `on_new_bid_notify` → `notify_outbid`: returns before doing anything — it posts to `send-push` only when
   `app.settings.supabase_url` and `app.settings.service_role_key` are set, and **both are unset on the sandbox**
   (`url_set=false key_set=false`, 04:40Z); there is also no previous bidder.
5. `trg_notify_bid_placed` → `notify_bid_placed`: same gate on the same two settings → **no `net.http_post` to
   `notify-transfer`**.

**Payment:** none. A bid creates no reservation, hold, payment intent or Stripe object; money is only ever requested after the
auction ends and the winner checks out.
**Phase-2 notify rail:** nothing — `notify.notification_type` has no bid-related type, so no `notify.notification` row and no
dispatch.
**Outbound notifications:** none by construction (the two GUCs are unset), and `send-push` would refuse any dispatch anyway
under option (b) (no sandbox service key). Nothing needs suppressing and nothing reaches the owner's handset.

## 3. What happens later if the fixture is retained
- `auto-finalize-auctions` (`*/2 * * * *`) finalizes the listing after **2026-09-25 02:01Z**: `auction_status` = ended,
  `winner_user_id` = buyer, `winning_bid_amount` = 101, `ended_at` set (function `auto_finalize_expired_auctions`, its own
  guard bypass). That fires `trg_notify_auction_won_inbox` → one in-app inbox row for the **buyer** ("auction won").
- No charge follows automatically: checkout is a buyer action. If nobody acts, the listing sits ended/won with an unpaid
  winner, which is the state the app's "needs action" surfaces show. The Bids tab keeps the row (C to confirm how it renders
  an ended listing).
- `buy_now_enabled` = true on D8 is unaffected by a bid; a buy-now by anyone would sell the listing and end the auction.

## 4. Cleanup options — and the one that is not proposed
| Option | Statements | Consequence | Recommendation |
|---|---|---|---|
| **R — retain until the ST2b observation, then seller-cancel from the app** | none by A; the owner, signed in as the seller, cancels D8 (`cancel_listing`: seller-only; refuses sold; sets `auction_status` = cancelled, keeps `status` active; tolerates existing bids) | no finalization, no winner, no "auction won" row; the bid row and the seller's `bid_received` row remain as history; D8 is gone from Explore | **Recommended** if the owner wants no won/unpaid outcome; entirely through app paths |
| **R′ — retain and let it end** | none | the §3 outcome on 2026-09-25 (buyer wins at $101, one inbox row); no money moves unless the buyer checks out | acceptable; simplest |
| **X — delete the bid row** | `delete from public.bids where id = '<bid id>'` as `postgres` | the row goes, but **no trigger reverts the listing**: `current_bid` 101, `bid_count` 1, `highest_bidder_id` buyer stay; reverting them is a direct `update public.listings` that must set `app.bypass_listing_guard` by hand — a manual guard override, which the owner has ruled out | **Not proposed** |
| Retained-record consequence, any option | 1 `public.bids` row; 1 `public.notifications` row (seller); under R′ a second one (buyer) later; no `notify.*`, `net.*`, payment or transfer rows | — | — |

## 5. Preconditions and abort conditions
- Sandbox identity asserted first (CS-1: ledger 130..141, no `ops` schema, `public.sandbox_gucs` present); `/Users/josetascon/snatchit` never used.
- Abort if the before-read shows any bid for the buyer, any bid on D8, D8 not active, `now() > ends_at`, or either GUC set.
- The DV-ST2a permission test must not overlap: place the fixture **before** ST2a or after the restore is verified, never inside the revoke window.

## 6. Authorization line (for the owner)
"Place one $101 bid as the DV buyer on listing `58cc00e3…` (Device D8) through the app's Place bid screen, A reading back before and after; retain the row for the DV-ST2b observation; afterwards [R: the seller cancels D8 from the app | R′: let it end 2026-09-25]." Until those words are given, **no bid is placed and DV-ST2b stays UNTESTED.**

## 7. Observed while preparing (not acted on)
`bids_select_all` is a `SELECT … using (true)` policy for `public` on `public.bids` — every bid row (listing, bidder UUID,
amount) is readable by anon and any authenticated user. Bid history is shown in-app by design (bidder names were removed
earlier), so this is recorded as an exposure to weigh, not a defect claimed here.
