# Sandbox reads for C's V3 phone-test plan — D-8, fixture state, W1/W2 side effects (A, 2026-09-24)

**Authority:** owner, 2026-09-24 ~03:49Z ("I directly authorise the read-only sandbox checks needed for C's V3
phone-test preparation … reads only") and ~04:00Z ("Complete the already authorised sandbox reads now … Establish
W2's actual behaviour … Prefer an existing bid fixture over W1 … Return the exact remaining owner decisions").
**Nothing was written.** W1 and W2 remain unexecuted. No fixture, migration, payment, notification or flag changed.

## 0. Project identity, read path, evidence files

| | |
|---|---|
| Target | **`ofaidukbieeekqaboscm`** — CLI `supabase projects list`: name `snatchit-sandbox`, organisation `lkmqqbmfatuwlixcfriw`, `ACTIVE_HEALTHY`, `linked: false`. Production `hqycwntpfoztoinemqns` is in a different organisation (`zcxpqolueooqkslolfrt`) and is linked only from `/Users/josetascon/snatchit`. |
| Supabase MCP | cannot see the sandbox (its `list_projects` returns only the production organisation) — recorded so nobody looks for a sandbox `execute_sql` there. |
| Command | `supabase db query --linked --project-ref ofaidukbieeekqaboscm --output-format json -f <file>` (CLI 2.115.0), run from `/Users/josetascon/snatchit-converge`, which has **no** `supabase/.temp/project-ref`; each run is preceded by `test ! -f supabase/.temp/project-ref` and refuses otherwise. `--project-ref` without `--linked` is rejected by this CLI ("only applies when targeting the linked project"); with an unlinked working directory the explicit ref is the only ref the command can resolve. |
| Read-only | every file begins `set default_transaction_read_only = on`; `grep -ciE '^(insert|update|delete|alter|create|drop|grant|revoke|truncate)'` = 0 on each. The Management API returns only the last statement's rows, so v2/v3 are single `UNION ALL` statements. |
| Discriminators (probe 03:57:25Z) | ledger **144** rows, max `20260916000000`; `kernel.signing_key` **0**; DV buyer present; listings 53. Production would read 160 / 1. |
| Files (scratchpad `sbx_d8/`) | `probe.json`; `reads_d8_v2.sql` sha256 `d199d047…` → `reads_d8_v2.out.json` `b2ef9046…` (101 rows, 04:02:48Z); `reads_d8_v3.sql` `15e3b90a…` → `reads_d8_v3.out.json` `0ae75da3…` (37 rows, 04:05:36Z); `gmt_prosrc.json`; `expired_candidates.json`. |
| Privacy | ids only; no e-mail, name, phone or delivery field was selected or printed. |

## 1. D-8 — `public.get_my_tickets()` on the sandbox: **CLOSED, evidence supports the RPC path and the empty state**

C's three statements, verbatim, and their results:

| Statement | Result |
|---|---|
| catalog row | **one row**: `prosecdef = t`; `proconfig = {"search_path=public, pg_temp"}`; `auth_exec = true`; `anon_exec = false`; `proacl = {postgres=X/postgres, authenticated=X/postgres, service_role=X/postgres}` (no PUBLIC, no anon) |
| result shape | `TABLE(event_id uuid, event_session_id uuid, event_title text, session_label text, starts_at timestamptz, ends_at timestamptz, doors_at timestamptz, venue_id uuid, venue_name text, artwork_ref text, ticket_type_id uuid, ticket_type_name text, ticket_type_kind text, quantity integer, ownership_status text, fulfillment_status text, time_class text)` — the 17 columns of `src/lib/tickets/types.ts`, same names, same order |
| ledger `20260909000000` | present: `kernel_my_tickets_read` (ticket-related rows also present: 079, 084, 093) |
| `kernel.tickets` | **0** — populated Tickets fixtures stay excluded (manifest §6) |
| joined relations | `catalog.event`, `catalog.event_session`, `catalog.venue`, `venue.ticket_type` all present |

**Body check.** Sandbox `prosrc` md5 `554773e6…` vs the repo file's dollar-quoted body md5 `b62f8fc2…` — the diff is exactly three `--` comment lines that are absent on the sandbox; with `--` lines stripped the two bodies are byte-identical (md5 `1dacb3bf…` both). The file `20260909000000_kernel_my_tickets_read.sql` is identical (sha256 `310f6003…`) at the gate `5b255838`, on the docs branch and in C's worktree, and unchanged since `597533e1` (2026-09-09). The cause of the comment stripping is not established (apply tooling is the likely one) and it changes nothing executable. **Verdict:** the sandbox build exercises the real RPC (grants, shape, empty set for the DV buyer) — D-8 closes on this evidence. Populated Tickets remain a separate, unauthorised phase.

## 2. Fixture state (reads (a), (b), (c) and the accounts)

- **Accounts:** DV buyer `919d511e-c4e6-4422-a71d-e2bc0139de65` and DV seller `2f5844b4-5144-4cd6-936d-4b59d8d5c6a0` both present, not deleted, not banned. DV buyer has a Stripe customer id and **1** push token; DV seller has **0** push tokens.
- **Listings census (53):** **3 live** (`status=active`, `auction_status=active`, `ends_at > now()`); 13 active/ended; 4 active/cancelled; 31 sold (+2 sold with a future `ends_at`). **The only three live listings are the image-400 fixtures, all owned by the DV seller, all quantity 1, `buy_now_enabled`, `buy_now_price` 100, `bid_count` 0, not reserved:**

  | Listing | Ends (UTC) |
  |---|---|
  | `c343406e-be85-49c1-9951-ac08bb1daab2` "Phone P1" | **2026-09-24 23:35:37Z** |
  | `b1c3c478-b32e-4167-8f8d-2b9a4a4fd212` "Device D7" | 2026-09-25 02:01:44Z |
  | `58cc00e3-e219-4095-9b57-cbdaa83df421` "Device D8" | 2026-09-25 02:01:44Z |

  Cron job 1 (`auto-finalize-auctions`, `*/2 * * * *`) ends each within two minutes of its `ends_at`. **After 2026-09-25 02:01:44Z the sandbox has zero live listings** — no feed rows, no bid screen, no Buy Now. C's plan line "any live listings (49 on the sandbox)" is wrong: 3 now, 0 then.
- **(a) open auctions with ≥ 1 bid: NONE.** `public.bids` has **0 rows**; the 3 open auctions all have `bid_count` 0. There is no existing bid fixture, so W1 cannot be replaced by one.
- **(b) active listing with `quantity ≥ 2` and buy_now: NONE** (3 active buy-now listings, all quantity 1). "Buy both now" has no fixture.
- **(c) transfers (33):** pending 19 · seller_sent 4 · disputed 6 · **reversed 4** · expired **0** · auto_released 0 · buyer_confirmed 0. `payout_review_status` is NULL on all 33; `payout_hold_until` non-null: **0**. Status check on the sandbox admits `pending, seller_sent, buyer_confirmed, disputed, expired, auto_released, reversed`; `payout_review_status` admits `held, manual_review`.
  - **Reversed — usable without any write**, all DV buyer + DV seller, created 2026-09-08: `e6941c3f-d08b-4382-b990-7fd74fa7dbd3`, `b640737b-64a9-44d2-a405-ab665912604f`, `acbfd9fe-dcd8-4502-9d8d-39745cfbe765`, `ddeb0d69-a007-4050-9fa9-8b8777a5f05d`. Each has `payout_released_at` set (2026-09-08) and its payment `succeeded`, total 11000, **`amount_refunded_cents` NULL, `refunded_at` NULL, `stripe_refund_id` NULL**, `stripe_livemode` false. So the buyer-reversed and seller-reversed cells can be exercised on the device, and by the wording table (§3, NULL amount) they must show a reversal **without** a refunded amount or the word "refunded".
  - **Expired: none. Held: none.** Coverage of those two cells is **outstanding** (bounded fixture options in §5, D5/D6).
- **Plan fixtures:** `92ee5156-7e82-40d8-ab54-73b489997797` pending (expires_at 2026-09-12 past; no evidence; `auto_release_at` null); `8f59d37e-52fd-4733-b311-532445ff441c` seller_sent (sent 2026-09-08; `auto_release_at` 2026-09-11 past; payout not released; no evidence; review status NULL). Other seller_sent rows: `83b83858…` (2026-09-08), and `bce07eef…` / `3118bd30…` (2026-09-17, **Line-3 quarantine — off-limits**, manifest §16).
- **DV buyer boards:** payments as buyer: succeeded 13, refunded 15, pending 2, failed 12; transfers as buyer: pending 11, seller_sent 4, disputed 6, reversed 4. C's "21 disputed purchase rows" is not what the sandbox holds — the buyer has **6** disputed transfers; the boards are populated either way. Two **pending intents already exist** for the DV buyer: `9f4ab181-2df7-49d3-8336-8ffad73d2e5a` on `c343406e` (2026-09-11) and `fd616e02-11e6-4db5-bb1f-9dd349265607` on `dfab7d5e…` (2026-09-08), both `stripe_livemode` false.
- **Baseline counts for any after-check:** `public.notifications` 109 (DV seller 58, DV buyer 43, other 8); `notify.notification` 9; bids 0; transfers 33; `net._http_response` last 6 h: 180 (cron ticks).

## 3. W1 — a new bid, traced on THIS sandbox's catalog (04:02Z)

Triggers on `public.bids`: `before_bid_insert`, `trg_sync_listing_current_bid`, `on_new_bid_notify`, `trg_notify_bid_placed`, `trg_notify_bid_inbox` (all enabled).

| Path | On the sandbox now | Effect of one DV-buyer bid on a DV-seller listing |
|---|---|---|
| `before_bid_insert` / `trg_sync_listing_current_bid` | active | 1 `bids` row; `listings.current_bid`, `bid_count`, `highest_bidder_id` updated |
| `on_new_bid_notify` → `notify_outbid` (054 body) | reads GUCs `app.settings.supabase_url` / `app.settings.service_role_key` — **both unset** (read 04:02Z) → returns before any `net.http_post` | no request; also no previous bidder exists |
| `trg_notify_bid_placed` → `notify_bid_placed` (133 body) | reads Vault `project_url` **and** `service_role_key`; **Vault holds only `project_url`** (created 2026-09-16T04:37Z) → posts only when both exist | no request |
| `trg_notify_bid_inbox` (058) | active | **1 `public.notifications` row (`bid_received`) for the DV seller**; an `outbid` row only for a previous leader (none) |
| push | `enqueue_notification` (057) inserts into `public.notifications` only — not `notify.outbox`, so job 20 `notify.drain_outbox` never sees it; send-push v4 (option (b), manifest §11) | nothing dispatched; DV seller has no push token anyway |

**Option (b) is still the sandbox state at 04:02Z:** Vault = `project_url` only; the GUCs are unset; every pg_net producer either does not post or cannot authenticate. Note for the record: 133 rewrote `notify_bid_placed` and `notify_transfer_event`; the sandbox's `notify_outbid` is still the 054 GUC-reading body.

**Later consequences (not contained by the window):** at `ends_at`, job 1 finalises the auction: `auction_status='ended'`, `winner_user_id` = DV buyer, `winning_bid_amount`, `ended_at`; `trg_notify_auction_won_inbox` writes an `auction_won` inbox row for the DV buyer. **No payment, transfer, charge or push is created by finalisation** — a winner's checkout would be a separate action the plan does not request. The listing leaves the live set and shows as won/ended to both accounts until reverted.

**Concrete cleanup (fixture write; owner decision D2):** one transaction as `postgres` with the sandbox ref, `select set_config('app.bypass_listing_guard','on',true)`: `delete from public.bids where id = <bid id>`; `update public.listings set current_bid = starting_bid, bid_count = 0, highest_bidder_id = null where id = <listing>`; `delete from public.notifications where id = <bid_received row id>`; if the auction already ended: also `auction_status='active', winner_user_id=null, winning_bid_amount=null, ended_at=null` plus the `auction_won` row and an `ends_at` in the future (D1). Read-back: bids 0, listing counters, notification count back to baseline, row md5s. Run it **before `ends_at`** or accept the revert path. Listing of choice: `58cc00e3` or `b1c3c478` (the later `ends_at`, no pending intent); not `c343406e`.

**No-write alternative:** the bid screen is exercised only in its no-bids state; "Current bid with ≥ 1 bid", the three-row summary after a bid and "You're leading" stay **source-only** (CFT-202/203 tests).

## 4. W2 — Buy Now hold + checkout entry, actual behaviour (source at gate `5b255838` = C's base for these files)

**Entry.** `ListingDetailScreen.tsx:775` → `rpc('reserve_buy_now', {listing, user, p_minutes})`; the server ignores `p_minutes` and sets **`reserved_until = now() + 10 minutes`** (`20260906100000`, `v_minutes := 10`). Then checkout mounts and `CheckoutNative` runs `setupPayment` in an effect keyed on `[user?.id, authLoading, listingId]` → `decideCheckoutSetup`: (1) `readSettledPayments` (a failure stops **before** hold and intent — F-CHK-READERR); (2) `fetchListing` — the hold must be the buyer's, otherwise `lost` and **no intent**; (3) `createIntent` → `create-payment-intent`.

**`create-payment-intent` writes, by path** (`index.ts` at the gate; the sandbox runs v5 from the pinned source):

| Path | When | Stripe (test mode) | `payments` | Other rows |
|---|---|---|---|---|
| **FRESH** | no `pending` row for (listing, buyer, mode) | **one new PaymentIntent** (`livemode` false) | **one new row** `status='pending'` (mode, total, PI id, `stripe_livemode`) | Stripe customer only if the profile has none (DV buyer has one → no write); other buyers' pending rows on the listing → `failed` (none exist on the three listings → no-op) |
| **REUSE** | a `pending` row exists and the PI's amount/currency still match | none | none | same retire rule (no-op here) |
| **SUPERSEDE** | a `pending` row exists but amount/currency differ, or the PI is gone | new PI; **old PI cancelled** in Stripe | new `pending` row; old row → `failed` | — |
| price check 409 | server total ≠ client `expected_total_cents` | none (the check precedes creation on both paths) | none | — |

**So:** on `b1c3c478` or `58cc00e3` the first checkout entry is FRESH → **exactly one** new test-mode PI and one pending row; on `c343406e` the DV buyer already holds `9f4ab181` → REUSE (zero new intents) if that PI is intact and the amount unchanged, else SUPERSEDE (+1 PI, old cancelled, old row failed). **Remount / retry / second appearance:** each entry re-runs setup; with the pending row present it is REUSE — no additional PI (that idempotence is the design intent stated in the effect's comment). **"Every checkout state creates an intent" is false:** `statusUnknown`/`unavailable` (settled read failed), `holdLost` (not the buyer's hold) and `priceChange` (409 before creation) create none; only the ready/held path creates or reuses one. **"Exactly one new intent" holds only for the FRESH path.**

**Which states one hold covers.** Ready/held boards in both appearances: yes (one intent). **hold-lost: yes, by waiting** — the hold is 10 minutes and job 1 clears lapsed holds within 2 minutes, so a buyer who stays in checkout past ~12 minutes sees the lost-hold state from `revalidateAgainstServer` with no extra write. **price-change: no** — it needs the server total to differ from the client's expected total (a seller price edit while the buyer is in checkout, or a fee change): a write not in the plan; stays source-only (tests CS4/CS5, control RC4) unless the owner authorises that edit.

**Cleanup — two separate objects.**
- *Reservation:* `release_reservation(listing, buyer)` (127) — resets the listing to active only if reserved by that caller and no `succeeded` payment; the client sends it on leaving, except on the F-HOLD-EXIT-1 path ("Back to home" may leave the listing screen mounted, so nothing is sent); backstop: `cleanup_expired_reservations` via job 1 within ~2 min after the 10-minute hold. Either way the listing is back to `active` within 12 minutes.
- *Intent and row:* **not touched** by `release_reservation`, `cleanup_expired_reservations`, any cron job or any edge; the repo has no cancel endpoint (the only `paymentIntents.cancel` is the supersede branch above). A pending test-mode PI stays open in Stripe indefinitely and the row stays `pending` (as `9f4ab181` and `fd616e02` already do). **Complete cleanup = (i) cancel the PI in the Stripe test dashboard or CLI (owner) and (ii) a fixture update `status: pending → failed` on that row** (`trg_guard_payment_transitions` allows it for the retire path; as `postgres` with `app.bypass_payment_guard`, or via service role) — or the owner accepts one more residue row. **A's rule (answer to C's question 1): explicit cancel + retire is the only complete cleanup; "leave it to the function's retire path" is not cleanup, because that path fires only for other buyers or on supersede.**
- *Correct plan wording:* "one 10-minute hold and, on a fresh listing, one test-mode PaymentIntent with a pending payments row; no charge; the hold is released by `release_reservation` or lapses; the intent and row are not released by anything and need their own cleanup."

## 5. Expired and held — the smallest fixture proposal (owner, ~04:10Z: "No transfer-row mutations are authorised … prepare the smallest concrete fixture proposal")

Additional reads 04:12:54Z (`reads_d8_v4.sql` `086f7593…` → `f653a917…`) and 04:15Z (`fixture_rel.json`):

- **Triggers on `public.transfers`:** `trg_guard_transfer_state_columns` (BEFORE UPDATE; returns early when `app.bypass_transfer_guard = 'on'`, 065:231); `trg_notify_transfer_sent` (AFTER UPDATE OF status **WHEN new.status = 'seller_sent'**); `trg_notify_dispute_opened` (**WHEN new.status = 'disputed'**); `trg_notify_transfer_created` / `_created_inbox` (INSERT only); `trg_notify_transfer_state_inbox` (every UPDATE, but its body (058) writes rows only for → seller_sent, buyer_viewed_at set, → buyer_confirmed, → disputed, payout_released_at set); `trg_reset_transfer_guard_bypass` (statement). **Neither `status → expired` nor setting `payout_review_status` / `payout_hold_until` matches any branch: zero inbox rows, zero pg_net requests.**
- **Jobs that could touch the rows:** job 24 `enforce-transfer-expiry` posts every 2 min without a `service_role_key` → **401** (15 × 401 in the last 30 min, 0 other codes); it acts only on `pending` rows anyway. Jobs 27/28 (`refund-execute-tick`, `payout-execute-tick`) are gated on `refund.executor_enabled` / `payout.executor_enabled` = **false**. Nothing else reads `payout_review_status`.
- **Read path on the sandbox:** `authenticated` has SELECT on every `transfers` column (incl. `status`, `expired_at`, `payout_review_status`, `payout_hold_until`) and on the payment refund columns; SELECT policies for buyer and seller (`auth.uid() = buyer_id` / `seller_id`). No migration in the gate tree narrows those grants.

| | **F-EXP (buyer "expired")** | **F-HELD (seller "held")** |
|---|---|---|
| Row | `19be875b-5a5e-428f-baa4-4ed80014b87f` — pending, expires 2026-09-11 (past), mobile_transfer, no evidence, no delivery fields | `83b83858-7c96-4887-bf6c-447858aec22a` — seller_sent 2026-09-08, `auto_release_at` 2026-09-11 (past), payout not released, review status NULL |
| Relationships | buyer DV `919d511e`, seller DV `2f5844b4`; listing `5b9052c7-4b63-4eab-b09a-2a9246cb48c3` (sold); payment `ca594f76-b4fd-4009-9411-6a03b028c6e8` succeeded, 11000, refund columns NULL, test mode; the buyer has 2 payment rows on that listing | same two accounts; listing `c0dd0706-52c6-4a4f-892a-a4bbc85b26d7` (sold); payment `6e912159-4e22-4476-a938-f90badc6d9cc` succeeded, 11000, refund NULL, test mode |
| Baseline row md5 (`md5(to_jsonb(row)::text)`) | `a4c234da03bf60aebdfa4d37578da41e` | `d1b36045bef8429fc74959344ead068c` (= its Line-3 control value, unchanged since 2026-09-17) |
| Change | `status = 'expired'`, `expired_at = now()` | `payout_review_status = 'held'`, `payout_hold_until = now() + interval '72 hours'`, `payout_risk_tier = 'MEDIUM'` (what 039 writes) |
| How | one transaction as `postgres`, sandbox ref, `set_config('app.bypass_transfer_guard','on',true)`, `update … where id = <row> and <expected current status>`, row-count guard = 1, before/after `to_jsonb` diff proving only the named columns changed | same |
| Triggers / jobs / notifications | guard bypassed; state-inbox fires, no branch → **0 rows**; no pg_net; job 24 cannot act (401, and the row is no longer `pending`) | guard bypassed; state-inbox fires, no branch → **0 rows**; no pg_net; payout executor off |
| What the device shows | buyer receive screen: status `expired` with a succeeded payment and no recorded refund → the refund-policy line, no amount (TR1's copy class); the row also moves on the buyer's board | seller send screen: held branch → `sellerHoldLine('held', <server date>)`; the countdown lines are suppressed (they require review status NULL) |
| Why not the plan's rows | `92ee5156` is the plan's pending fixture | `8f59d37e` carries the plan's seller_sent deadline cell; held would suppress that cell's line |
| Cleanup | same transaction shape: `status = 'pending', expired_at = null`; read-back md5 = `a4c234da…` | `payout_review_status = null, payout_hold_until = null, payout_risk_tier = <baseline value>`; md5 = `d1b36045…` |
| Coverage it adds | the real select → RLS → row → screen path for `expired` on a device, both appearances, with a real payment row behind it | the real select → row → held branch on a device, and the server timestamp formatted in the device's time zone |

Never touched: `bce07eef`, `3118bd30` (Line-3 quarantine), `92ee5156`, `8f59d37e`, any payment row.

## 6. Submission-gap assessment (gallery + tests, without F-EXP / F-HELD)

| Cell | Real sandbox row on device | Real screen driven in tests | Gallery | Gap |
|---|---|---|---|---|
| buyer reversed | **yes** — 4 rows (§2) | yes, TR5 (`receive/[id]` rendered with mocked rows) | optional | none material |
| seller reversed | **yes** — same 4 rows | source pins only (TS1) | optional | closed by the device check |
| buyer expired | **no** | yes, TR1–TR4 (four refund variants through the real screen, mocked data) | synthetic render | device path of a real expired row |
| seller held | **no** | **no** — pure function TC6 + source pins TS2; the send screen's held branch is never rendered | synthetic render | screen wiring **and** device path |
| buyer / seller "review deadline" | yes — `8f59d37e`, `83b83858` | TR6 | — | none |

**Finding: the gap is material for held, narrower for expired.** Both are money-adjacent states that production produces (enforce-transfer-expiry is live there; 039's MEDIUM tier writes holds). A gallery renders components from synthetic props; it cannot show that the screen reads these fields and routes them to the cell, which is exactly the class of defect that passed green before (a selected column whose failure the screen swallowed; a guard whose entry point never admitted the new path). For held, nothing today renders the real send screen in that state — a wiring defect would reach users with no failing test. "Recorded as unverified" does not close either gap.

**Smallest closure, in order:**
1. **C, no authorisation needed:** add a send-screen render test for held (TS3: `send/[id]` rendered with a mocked row `seller_sent`, `payout_review_status 'held'`, `payout_hold_until` set, asserting the hold line and the absence of both countdown lines), with a negative control that removes the held branch. This closes the wiring half for held.
2. **Owner decision D5/D6 (§5):** two reversible row updates, zero notifications, zero outbound requests, zero job effects, restored to their baseline md5 after the device check. This closes the device half for both cells.
3. **If D5/D6 are declined:** the two cells ship with test + gallery evidence only, and the release record must state that they were never exercised on a device with real data. That is the owner's risk decision, not a pass.

## 7. The exact remaining owner decisions (A cannot take any of them)

| # | Decision | Fixture identity | Side effects | Cleanup |
|---|---|---|---|---|
| **D1** | Extend `ends_at` on the three live listings; otherwise the sandbox has **no live listing after 2026-09-25 02:01:44Z** (`c343406e` ends 2026-09-24 23:35:37Z) | `c343406e…`, `b1c3c478…`, `58cc00e3…` (DV seller) | as `postgres` with `app.bypass_listing_guard`; no notification trigger keys on `ends_at` (`trg_notify_auction_won_inbox` keys on `winner_user_id`); which listing guard inspects `ends_at` was not read | none needed; or restore the three values in §2 |
| **D2** | **W1** — one bid by the DV buyer on `58cc00e3` or `b1c3c478`, or strike W1 | listing chosen; bid id recorded at write | 1 bid row; listing counters; **1 `bid_received` inbox row for the DV seller**; no push, no outbound request; at `ends_at` job 1 makes the DV buyer the winner and writes an `auction_won` inbox row; **no payment or transfer is created** | before `ends_at`: delete the bid, reset `current_bid`/`bid_count`/`highest_bidder_id`, delete the inbox row by id; after: also revert `auction_status`, `winner_user_id`, `winning_bid_amount`, `ended_at`, delete `auction_won`, set a future `ends_at` |
| **D3** | **W2** — one Buy Now hold + checkout entry, or strike W2 | `b1c3c478`/`58cc00e3` (FRESH: 1 new test-mode PaymentIntent + 1 pending `payments` row) or `c343406e` (REUSE of existing pending `9f4ab181` if intact: 0 new intents) | 10-minute hold; hold-lost reachable by waiting ~12 min; price-change **not** covered | hold: `release_reservation` or lapse; intent + row: **owner cancels the PI in the Stripe test dashboard** + fixture `pending → failed` on that row, or the owner accepts one residue row |
| **D4** | "Buy both now": fixture `quantity = 2` on one DV listing, **or** a new quantity-2 listing from the device Sell form, **or** strike | `58cc00e3…` or new id | one column; or a full listing insert + image upload | restore `quantity = 1`; or cancel the new listing |
| **D5** | **F-EXP** (§5) | `19be875b…` | none beyond the row | restore to md5 `a4c234da…` |
| **D6** | **F-HELD** (§5) | `83b83858…` | none beyond the row | restore to md5 `d1b36045…` |
| — | Reversed cells: no decision (4 real rows). Tickets RPC: closed (§1). | | | |

## 8. Corrections C's plan must carry (owner: rewrite in place, not append)

1. "no payment" → §4's wording; "no notifications" → "one `bid_received` inbox row for the DV seller; no push and no outbound request while option (b) holds".
2. "any live listings (49)" → 3 live now, 0 after 2026-09-25 02:01:44Z without D1.
3. "The DV buyer's 21 disputed purchase rows" → 6 disputed transfers; the boards hold 42 payment rows and 25 transfers for the DV buyer.
4. Read (a): none (0 bids on the sandbox). Read (b): none. Read (c): reversed 4 (usable), expired 0, held 0.
5. W2: name the 10-minute hold, the intent and the row separately; hold-lost is reachable by waiting; price-change is not covered by W2.
6. W1: "the auction is not finalised in the window" → "finalisation follows `ends_at` unless the bid is deleted first".
7. D-8: closed.

**Record correction (A, 04:16Z):** an earlier draft of this file said D5/D6 would write inbox rows through `trg_notify_transfer_state_inbox`. The trigger body read at 04:12Z has no branch for either change: they write none. The draft was never sent.
