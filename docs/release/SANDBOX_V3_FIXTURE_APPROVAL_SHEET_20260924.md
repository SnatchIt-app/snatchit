# V3 phone test — fixture approval sheet (A, 2026-09-24)

**Revision 2 (A, 2026-09-24 ~05:10Z), after the owner's corrections of ~04:55Z:** cleanup split into independent
tracks with their own deadlines (§5), both end-time restore outcomes handled (§5, track E), owner-unavailable rule
(§5b), pre-session dispatch recheck (§4), and the Buy Now amount reconciled with its history (D4).

**Status: NOT APPROVED. Nothing on this sheet has run.** Each line D1–D6 runs only if the owner approves that line in
the owner's own turn. Evidence behind every value: `SANDBOX_D8_READS_20260924.md` and the deployed function bodies
read from the sandbox at 04:36Z (`sbx_d8/fn/`, md5 per function listed in §8). Sandbox `ofaidukbieeekqaboscm` only.

## 0. When the writes may happen

All four must be true before the first write, which comes **no earlier than 15 minutes before the first device step**:
1. C's pre-build gates pass at one pinned commit, and the one authorised EAS `preview` build from that commit is FINISHED;
2. the build is installed on the owner's iPhone and signed in as the DV buyer;
3. the owner says "go" for the session in chat;
4. A's T0 capture (§4) has run and matches the expected values in §4.

**Fallback deadlines, per track (§5):** track W1 by bid time + 60 min; tracks T and E for L-BID by T0 + 2 h 30 min,
whatever the session state. Track C, the checkout listing and its intent, completes only when the Stripe cancellation
is confirmed; §5b says what happens meanwhile. A starts the timers at the first write. Steps not run by their deadline
are recorded as not run.

**Listing end times decide the D1 variant.** If the session starts before 2026-09-25 02:01:44Z, the two listings are
still live (variant A). After that, job 1 will have ended them with no bids, which gives variant B.

## 1. Fixture identities

| Role | Id | Current state (read 04:37Z) |
|---|---|---|
| DV buyer | `919d511e-c4e6-4422-a71d-e2bc0139de65` | 1 push token; Stripe customer present |
| DV seller | `2f5844b4-5144-4cd6-936d-4b59d8d5c6a0` | 0 push tokens |
| **L-BID** (W1) "Device D8" | `58cc00e3-e219-4095-9b57-cbdaa83df421` | active/active, qty 1, starting 100, current 100, bid_count 0, buy_now 100, ends 2026-09-25 02:01:44.985417Z, ended_at NULL; DV buyer has 1 failed payment `9fc40dd6-b57f-4536-a55f-473e16a78f73` |
| **L-CHK** (W2, D4) "Device D7" | `b1c3c478-b32e-4167-8f8d-2b9a4a4fd212` | same values, same end time; DV buyer has 2 failed payments `a79d6fe4-bce7-419d-afdc-49fbd22f9ef9`, `9a3dd888-8a35-4e20-ad7f-b5e5b4afb8d0`; **no pending** row |
| **L-P1** "Phone P1" (read-only, **not extended**) | `c343406e-be85-49c1-9951-ac08bb1daab2` | ends 2026-09-24 23:35:37.5802Z; holds the DV buyer's **pending** `9f4ab181-2df7-49d3-8336-8ffad73d2e5a` |
| **F-EXP** (D5) | transfer `19be875b-5a5e-428f-baa4-4ed80014b87f` | pending, expires 2026-09-11 20:49:55Z, expired_at NULL; payment `ca594f76-b4fd-4009-9411-6a03b028c6e8` succeeded 11000, no refund recorded; listing `5b9052c7-4b63-4eab-b09a-2a9246cb48c3` sold; row md5 `a4c234da03bf60aebdfa4d37578da41e` |
| **F-HELD** (D6) | transfer `83b83858-7c96-4887-bf6c-447858aec22a` | seller_sent 2026-09-08, auto_release_at 2026-09-11, payout not released; review status, hold_until, risk tier and reason codes all NULL; payment `6e912159-4e22-4476-a938-f90badc6d9cc` succeeded 11000; listing `c0dd0706-52c6-4a4f-892a-a4bbc85b26d7` sold; row md5 `d1b36045bef8429fc74959344ead068c` |
| Reversed, used as they are | `e6941c3f-d08b-4382-b990-7fd74fa7dbd3`, `b640737b-64a9-44d2-a405-ab665912604f`, `acbfd9fe-dcd8-4502-9d8d-39745cfbe765`, `ddeb0d69-a007-4050-9fa9-8b8777a5f05d` | no write |
| Deadline cells, used as they are | `8f59d37e-52fd-4733-b311-532445ff441c` (seller_sent), `92ee5156-7e82-40d8-ab54-73b489997797` (pending) | no write |
| **Never touched** | `bce07eef…`, `3118bd30…` (Line-3 quarantine); any payment row except the one W2 creates | — |

L-P1 is deliberately left to end on its own at 23:35:37Z today. A Buy Now there would reuse the DV buyer's old pending
intent and would release W2's hold, so the session has no reason to open its checkout. Photo fallback is still covered
by L-BID and L-CHK, both image-400 listings, in the feed, the hero and, through W2, the checkout thumbnail.

## 2. The decisions, with exact values

Every SQL write below runs as `postgres` against the explicit sandbox ref, in one transaction per line. Each has a
row-count guard of exactly 1 per row and a before/after `to_jsonb` diff, which must show only the named columns plus
`updated_at` where a trigger sets it.

**D1 — extend two listings' end time.** Rows: L-BID and L-CHK only.
- Value: `ends_at = date_trunc('minute', now()) + interval '24 hours'`, computed once in the transaction and identical
  for both rows. The absolute value is recorded at the write.
- Variant A (still live): `ends_at` only. `ends_at` is not a column the state guard protects, so no bypass is needed.
- Variant B (already ended by job 1): also `auction_status 'ended' → 'active'` and `ended_at → NULL`, with
  `app.bypass_listing_guard` on. The transaction refuses unless `bid_count = 0`, `winner_user_id IS NULL` and
  `status = 'active'`.
- Triggers: `trg_listings_updated_at` sets `updated_at`. `trg_notify_auction_won_inbox` keys on `winner_user_id`, so
  it does not fire. No notification, no outbound request.
- The extension is not containment. Containment is the cleanup in §5, which runs long before the new end time.

**D4 — quantity 2 on L-CHK.** `quantity 1 → 2` on `b1c3c478` only, with no bypass; `quantity` is not guarded.
- Effect: the listing shows "Buy both now" and "2 tickets".
- **Price semantics are settled, not new.** `buy_now_price` is charged once for the whole listing. A established it
  as finding A-01 (`PRODUCTION_RELEASE_PACKAGE.md:2488`: `create-payment-intent` charges `buy_now_price` once, fees and
  payout come off that base). The owner ruled whole-listing on 2026-09-22, as cited at
  `src/lib/listing/detailState.ts:344` on C's branch. The current labels follow it at `2619b9e1`:
  - the verb is "Buy both now" for two tickets and "Buy all N now" beyond that (`detailState.ts:348`);
  - the quantity reads "2 × <type>" in the checkout identity (`OrderIdentity.tsx:47`) and on the bid screen, where it
    adds "· sold together" (`PlaceBidScreen.tsx:260`);
  - tests pin it: `listing-detail-state.test.ts:138` and `sell-state.test.ts:252` ("never says per ticket").
- **Expected on L-CHK:** the button reads "Buy both now" with the all-in figure for **$110**, which is $100 plus the
  $10 buyer fee; checkout shows 2 tickets and a **$110** total. The device check verifies these labels against the
  server figure. It does not change pricing.

**D2 (W1) — one bid, from the handset.** DV buyer on **L-BID only**, amount **$105**. That is the screen's preselected
minimum: current $100 plus `MIN_BID_INCREMENT` 5. It is the only bid of the session. Verified effects, from the
deployed bodies:

| Trigger (all AFTER/BEFORE INSERT on `bids`) | Effect on the sandbox |
|---|---|
| `before_bid_insert` → `validate_and_apply_bid` | requires active, not ended, amount > current, 3 s spacing; sets `current_bid 105`, `bid_count 1`, `highest_bidder_id` = DV buyer |
| `trg_sync_listing_current_bid` | `current_bid = GREATEST(100, 105)`, `updated_at` |
| `trg_notify_bid_inbox` | **1 `public.notifications` row** for the DV seller: type `bid_received`, dedupe `bid_received:<bid id>`, "New bid: $105". No `outbid` row, because there is no previous bidder |
| `trg_notify_bid_placed` | posts to `notify-transfer` only if Vault holds both `service_role_key` and `project_url`; the Vault holds only `project_url`, so **no request** |
| `on_new_bid_notify` → `notify_outbid` | reads `app.settings.supabase_url` and `app.settings.service_role_key`; both are unset, so it **returns before any request** |
| push | `enqueue_notification` writes only `public.notifications`, never `notify.outbox`, so the drain job never sees it; **no push** |

- **If W1 is not cleaned before the new end time:** job 1 ends L-BID with the DV buyer as winner at $105 and writes an
  `auction_won` inbox row for the DV buyer. No payment and no transfer are created.
- **Reconciliation with B's source trace, which predicted real dispatch attempts:** the two pg_net triggers do exist
  on the sandbox. Both are inert here because of the dispatch configuration: Vault holds `project_url` only and both
  `app.settings` values are unset, as read at 04:02Z and 04:36Z. In an environment with those set, B's trace holds:
  `notify_bid_placed` posts to `notify-transfer`, and `notify_outbid` posts to `send-push` for a previous leader. The
  trace was right about the code and wrong about this sandbox. The in-app row is the only effect here.

**D3 (W2) — one Buy Now hold and checkout, from the handset.** DV buyer on **L-CHK only**, after D4. It is the only
Buy Now of the session, because `reserve_buy_now` releases any other active hold held by the same buyer.
- Server path: `reserve_buy_now` sets a **10-minute** hold, fixed by the server whatever `p_minutes` says. Checkout
  mounts, reads settled payments (none), confirms the hold is the buyer's, then calls `create-payment-intent`.
- **Expected FRESH**, because T0 must show no pending DV-buyer row on L-CHK. FRESH means **exactly one** new Stripe
  test-mode PaymentIntent, `livemode` false.
- Database writes from that request:
  - 1 `payments` row, `pending`, total 11000, mode `buy_now`, written through `record_checkout_attempt`;
  - one `checkout_group_claim` row, inserted and deleted within the request; an abandoned one is reclaimable after
    120 s;
  - `rate_limits` upserts;
  - the listing set to `reserved`;
  - no profile write, since the Stripe customer exists, and no notification.
- Remount, retry and switching appearance take the **REUSE** path: no new intent. Unknown status, a lost hold and a
  price change create none. If A's post-session read finds more than one new row or intent, that is a finding. Each
  extra is cleaned the same way.
- **Device sequence:**
  1. Open L-CHK by deep link.
  2. Tap "Buy both now".
  3. Capture the ready boards in Light and in Dark within the 10 minutes.
  4. **Do not tap Pay.** Pay presents the Stripe sheet; a card must never be entered.
  5. Stay on the screen. At 10:00 the client countdown shows the hold-lost board (`CheckoutNative.tsx:695` at
     `016087ea`), and job 1 clears the server hold within about 2 minutes after that.
  6. Leave with Back.
- **Price change is not covered.** No write is proposed for it; it stays test-only (CS4/CS5, control RC4).

**D5 — F-EXP.** On `19be875b`, set `status 'pending' → 'expired'` and `expired_at NULL → now()`. That is exactly what
`enforce_transfer_expiry` writes (`0551`). It represents the production state between expiry and the refund step.
- The write sets `app.bypass_transfer_guard`. It refuses unless the row is `pending` with `expires_at < now()`.
- Triggers: the guard is bypassed. The state-inbox trigger has no branch for `expired`, so it writes **0 rows**. No
  pg_net trigger keys on `expired`. Job 24 gets 401 and acts only on `pending` rows anyway.
- Device: the buyer's receive screen shows the expired state, with a succeeded payment and no refund recorded.

**D6 — F-HELD.** On `83b83858`, set exactly what `apply_payout_hold` writes (`0551`):
- `payout_review_status NULL → 'held'`;
- `payout_hold_until NULL → date_trunc('day', now()) + interval '3 days 18 hours'`, recorded at the write: 18:00 UTC,
  shown as 14:00 on a US-Eastern phone;
- `payout_risk_tier NULL → 'medium'`;
- `payout_reason_codes NULL → ARRAY['SELLER_UNPROVEN']`.

The write sets `app.bypass_transfer_guard` and refuses unless the row is `seller_sent` with all four columns NULL.
- Triggers: the guard is bypassed. The state-inbox trigger has no branch, so it writes **0 rows**. No pg_net. Both
  executor flags are false.
- Device: the seller's send screen shows the held branch with the dated line, and the countdown lines are suppressed.

## 3. Dependencies, so that no test invalidates another

| Rule | Why |
|---|---|
| D1 before W1 and W2; D4 before W2 | both need live listings; "Buy both now" needs quantity 2 |
| W1 only on L-BID, W2 only on L-CHK, neither on L-P1 | a bid on L-CHK would lift its current bid above the Buy Now price; L-P1 carries an old pending intent |
| exactly one Buy Now in the session | a second Buy Now anywhere releases W2's hold (`reserve_buy_now`) |
| exactly one bid | a second bid would create an `outbid`-class state and more cleanup |
| device order: no-write checks, then W1, then W2 (about 12 minutes), then transfer cells (reversed ×4, F-EXP, F-HELD, deadline rows), then the buyer-to-seller account switch last | the account switch registers the seller's push token (DV-611 rule) and must not interrupt W2 |
| L-BID's end-time restore only after track W1 is complete | restoring a past end time with the bid still present would let job 1 make the DV buyer the winner |
| **Nothing on L-CHK or its payment row changes until the intent's cancellation is confirmed**, except that the 10-minute hold lapses on its own | a late confirmation of an open intent must meet the listing in the state it was created against |
| tracks W1 and T never wait for Stripe | the bid, the seller's inbox row and the transfer fixtures have no link to the intent |

## 4. Pre-session dispatch recheck and T0 before-state capture (A, read-only, one file with md5; D witnesses if the owner authorises D's reads)

**Dispatch and executor recheck, run twice:** once at T0, immediately before the first write, and again immediately
before W1, the only step that fires a notification trigger. Each run must match, or the session stops before the
next write:
- Vault secret names: exactly `project_url`; no `service_role_key`;
- `app.settings.supabase_url` and `app.settings.service_role_key`: both unset;
- `refund.executor_enabled` and `payout.executor_enabled`: both false;
- `cron.job`: the same 22 jobs and active flags as read at 04:02Z; no new job;
- deployed bodies of `notify_bid_placed`, `notify_outbid` and `notify_bid_inbox`: prosrc md5 as in §8;
- edge function list: the same 9 functions and versions as read at 03:5xZ (`send-push` v4; `notify-transfer` not deployed);
- `net._http_response`, last 30 minutes: status 401 only;
- `notify.outbox`: count unchanged from T0.


- **Rows:** L-BID, L-CHK and L-P1, full `to_jsonb` plus the D1/D4 columns. F-EXP, F-HELD, the four reversed rows,
  `8f59d37e` and `92ee5156` as row md5. Payments on the three listings (id, status, PI present). All DV-buyer
  `pending` payments.
- **Counts:** bids, per-user `public.notifications`, `notify.notification`, `push_tokens` per DV user, reserved
  listings, payments, transfers, listings.
- **Configuration:** Vault secret names, the two `app.settings` values, `refund.executor_enabled` and
  `payout.executor_enabled`, cron job active flags, the last 30 minutes of `net._http_response` status codes.
- **Expected, or STOP:**
  - bids 0;
  - no pending DV-buyer row on L-CHK;
  - F-EXP and F-HELD md5 as in §1;
  - Vault = `project_url` only;
  - both `app.settings` values unset;
  - both executor flags false;
  - outbound responses 401 only.

## 5. Cleanup — four independent tracks

C's "session done or abandoned" signal starts every track that has not started yet. **Each track has its own
deadline and none waits for another, except where this section says so.** A executes every SQL step; the owner
executes only the Stripe cancellation; D witnesses the reads if authorised.

**Track W1 — the bid, the seller's inbox row, L-BID's counters (A).** Start as soon as C reports the bid-screen
check done, which may be mid-session. **Deadline: bid time + 60 minutes**, and in any case before L-BID's extended
end. It never waits for Stripe.
1. Delete the `public.notifications` row with dedupe `bid_received:<bid id>` for the DV seller: expect 1.
2. Delete the bid by id: expect 1. `bids` has no delete trigger.
3. With the listing bypass, set L-BID `current_bid 100, bid_count 0, highest_bidder_id NULL`.
4. Verify: bids 0; L-BID equals T0 except `updated_at` and `ends_at`; the seller's notification count equals T0.

**Track T — the transfer fixtures (A).** Start as soon as C reports the transfer-cell checks done. **Deadline: T0 +
2 h 30 min.** It never waits for Stripe.
1. D5: F-EXP back to `status 'pending', expired_at NULL`; verify row md5 `a4c234da…`.
2. D6: F-HELD's four columns back to NULL; verify row md5 `d1b36045…`.

**Track C — L-CHK and its intent, ordered around confirmed cancellation.**
1. **Hold (automatic, verified by A):** the hold lapses 10 minutes after reservation and job 1 clears it within 2
   more. A verifies `reserved_by` NULL by reservation + 15 minutes. Nothing forces it.
2. **Identify (A):** the one DV-buyer `payments` row on L-CHK created after T0; record its id and `pi_…`; send the
   `pi_…` to the owner at session end.
3. **Cancel (owner):** the Stripe step in §6.
4. **Confirm (A):** poll the row for up to 10 minutes. The deployed `stripe-webhook` moves it `pending → failed` on
   `payment_intent.canceled`, and only from `pending`/`processing`. If it moves, cancellation is confirmed by two
   routes, the owner's screen and Stripe's own event, and no SQL is needed.
   Whether the sandbox Stripe account's webhook endpoint subscribes to `payment_intent.canceled` is **not
   established**; the production subscription is itself an open owner decision (`PRODUCTION_RELEASE_PACKAGE.md:177`).
   Expect step 5 to be the normal path unless step 4 moves the row.
5. **Only if step 4 does not move it:** `update public.payments set status='failed' where id=<row> and
   status='pending' and stripe_payment_intent_id=<pi>`, row count 1. Run it only if all hold: the owner confirmed
   "Canceled" for exactly that id; the row still carries that id and is `pending`; L-CHK has no `succeeded` payment;
   L-CHK is not reserved. The guard permits `pending → failed`. Record the missing webhook delivery as a finding,
   with cancellation confirmed by one route.
6. **Then, and only then:** D4 restore, L-CHK `quantity 2 → 1`; followed by track E for L-CHK.

**Track E — end-time restore, per listing (A).** L-BID: after track W1. L-CHK: after track C step 6. Each restore
writes back exactly the T0 values, and refuses unless `bid_count = 0`, `winner_user_id IS NULL` and the listing is not
reserved. Three outcomes, all handled:

| At T0 the listing was | At restore time R, the captured `ends_at` is | Restore writes | What follows |
|---|---|---|---|
| live (variant A) | **still in the future** | `ends_at` only | the listing stays live until the captured time, then job 1 ends it with no bids: exactly the course it was on without the test |
| live (variant A) | **already past** | `ends_at` only | job 1 ends it within 2 minutes with no bids; `ended_at` is later than it would have been, the only difference |
| already ended (variant B) | past | `ends_at`, `auction_status 'ended'`, `ended_at` = T0 values, with the bypass | job 1 ignores ended listings; the row equals T0 except `updated_at` |

**Closing read (A, D witness):** counts equal T0 plus the known residue:
- the W2 row, now `failed`;
- `rate_limits` rows;
- any push token the account switch registered, per the DV-611 rule.

**Why the row is never marked failed before cancellation:** marking the row failed does not stop a charge. A live
intent can still be confirmed, and the webhook would then move `failed → succeeded`, which the guard allows. Only
cancellation is terminal in Stripe. `release_reservation`, the hold-expiry cleanup, cron and the edges never touch the
intent or the row.

## 5b. If the owner is unavailable during cleanup

- **Tracks W1 and T complete regardless**, by their own deadlines. The hold lapses by itself.
- **Track C stops at step 2.** The intent stays open and the row stays `pending`. **A never marks the row failed as a
  substitute for cancelling the intent, however long the owner is away.** L-CHK keeps quantity 2 and its extended end
  time until cancellation is confirmed.
- **Why that residue is contained:**
  - no charge can occur unless someone confirms the intent with a payment method;
  - only the handset that opened the checkout has its client secret, and the tester stops using L-CHK;
  - the intent remains cancellable at any time;
  - if the extended end time passes first, job 1 ends L-CHK with no bids, and track E then restores whatever T0
    values still apply.
- **Record:** A records the open intent in `SANDBOX_D8_READS_20260924.md` as an owner action: the `pi_…` id, the row
  id and the time. A sends it to the owner with the other open items, and resumes at step 3 when the owner returns.
- **Existing residue, outside this sheet:** the two older pending test intents `9f4ab181` and `fd616e02` are
  recorded as owner items. They are not cancelled under this sheet.

## 6. The owner's Stripe step (step 4)

Use the Stripe account whose **test** keys the sandbox project uses; the build carries a `pk_test_` key. A sends the
exact `pi_…` id.
- **Dashboard:**
  1. Open dashboard.stripe.com.
  2. Turn on **Test mode**.
  3. Go to **Payments** and search for the `pi_…` id.
  4. Open it, choose **Cancel payment**, pick reason **Abandoned**, and confirm.
  5. The status must read **Canceled**.
- **Or the CLI**, in the owner's own terminal and logged in to that account's test mode:
  ```bash
  stripe payment_intents cancel pi_REPLACE_WITH_ID --cancellation-reason=abandoned
  ```
  The output must show `"status": "canceled"`.
- **Stop** if the id is not found. That means the wrong account or live mode.

## 7. Stop conditions during the session

- Any T0 value differs from §4.
- Any write's row count is not exactly 1.
- More than one new PaymentIntent or payment row.
- Any notification row other than W1's `bid_received`.
- Any `net._http_response` code other than 401 inside the window.
- Any change to a row not named on this sheet.

On a stop, C pauses the device and A runs §5 from the first applicable step.

## 8. Evidence pointers

Deployed function bodies read at 04:36Z, with prosrc md5:

| Function | prosrc md5 |
|---|---|
| `notify_bid_placed` | `4c1b12ee…` |
| `notify_outbid` | `e9ebcf77…` |
| `notify_bid_inbox` | `6afbc6f1…` |
| `validate_and_apply_bid` | `17f17d65…` |
| `sync_listing_current_bid` | `5382db72…` |
| `guard_listing_state_columns` | `dd4a10ac…` |
| `guard_listing_identity_columns` | `f6d26f2c…` |
| `reserve_buy_now` | `cbae5652…` |
| `guard_payment_transitions` | `85e7834f…` |

Trigger timings on `bids`, `listings` and `payments` were read the same minute. Repository source, at gate `5b255838`:
- `create-payment-intent`: FRESH/REUSE/SUPERSEDE, `record_checkout_attempt`, quantity-independent price;
- `stripe-webhook:391–458`: the cancel branch;
- `0551`: `enforce_transfer_expiry` and `apply_payout_hold`.

Client source, at C's `016087ea` / `6c7fc18b`: minimum increment 5, the hold-lost countdown, and the one-Buy-Now
behaviour.

## Owner approval (tick per line; nothing is approved by default)

- [ ] D1 end-time extension, L-BID and L-CHK
- [ ] D2 W1 bid of $105 on L-BID
- [ ] D3 W2 hold and checkout on L-CHK, with the owner's Stripe cancel (track C step 3); L-CHK restores only after confirmed cancellation
- [ ] D4 quantity 2 on L-CHK
- [ ] D5 F-EXP
- [ ] D6 F-HELD
- [ ] D's read-only witness reads on the sandbox for T0 and §5
