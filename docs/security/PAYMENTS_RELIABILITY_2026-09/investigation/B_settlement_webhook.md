# Agent B — settlement & webhook recovery (investigation report, eadd456)

All evidence gathered; harness run against the worktree copy (scratch at `.../scratchpad/agentB/repro.cjs`, root `/Users/josetascon/snatchit-pay`, commit eadd456). Report follows.

# Agent B — settlement & webhook recovery (eadd456)

Files: `W` = `supabase/functions/stripe-webhook/index.ts`, `C` = `supabase/functions/confirm-payment/index.ts`, `E` = `supabase/functions/enforce-transfer-expiry/index.ts`, `M` = `src/screens/checkout/CheckoutNative.tsx`, `Wc` = `web/src/lib/checkout.ts`.

## 1. Hypothesis verdicts (vm harness, real handlers, mocked supabase)

**F02 — CONFIRMED.** W:267-273 promotes `payments.status='succeeded'` (`.neq('status','succeeded')`) *before* the sale RPC at W:405. On the retry the row is already succeeded → W:283-371 "already processed" branch → only ensures a transfer row, never calls the RPC, then `finish(true)` (W:370) → terminal complete.
Harness S1 (mark_listing_sold injected to fail): HTTP `[500, 200, 200]`, `mark_listing_sold` calls = **1**, `fail_stripe_webhook_event` = 1, `complete` = true, transfer created = true, listing sold = false, retry body `{path:'fallback_transfer'}`. Matches the audit exactly.
confirm-payment: C:215-229 writes succeeded, C:243-284 inserts transfer; never touches listings. Settlement is the client's job (M:285/349, Wc:162).

**F05 — CONFIRMED (both writers).** C:216-224 filters only `stripe_payment_intent_id` + `buyer_id` (harness S3b: write keys `[status, paid_at, payment_method]`, filters `eq pi, eq buyer_id` — no status guard). W:267-271 filter is `neq status succeeded` only (harness S3: refunded row → `statusAfter='succeeded'`, `mark_listing_sold` called 1×, HTTP 200). Neither write clears `refunded_at`/`stripe_refund_id`, so the row ends `status='succeeded', refunded_at=<set>` — self-contradictory. Contrast: `payment_failed` branch W:512-513 *does* exclude refunded; the success branch does not.

**F06 — CONFIRMED, and broader than stated.** Harness: `charge.refunded` DB error → **HTTP 200**, `fail_stripe_webhook_event` called (lease released, `processed_at` NULL) — Stripe will never redeliver after a 200, so the release is inert. Same shape for: dispute upsert failure (W:652, 200), dispute.closed lookup error (W:681, 200), transfer.reversed error (W:759, 200), account.updated error (W:848, 200), payment_failed DB error (W:519-523, 200). Worse than audit: freeze RPC failure (W:610-613) and dispute-lost refund-mark failure (W:696) fall through to `markProcessed()` **success** → event is terminal-complete with no error recorded. `dispute.closed` unknown id → `markProcessed()` success (W:682-684), 200. `get_incomplete_webhook_events`: zero runtime callers (grep hits only 064, docs, governance md). `webhook_retries`: zero writers/readers in `supabase/functions/` (074_privilege_cleanup.sql:81 confirms).

Deployed-version caveat: 1358a21 "sync edge functions to the deployed source" implies v39/v34 == main. If deployed webhook predates a16a16d (064 lease + `finish()`), *every* failure path returns 200 and the retry hits the old 23505 gate — strictly worse.

## 2. Persistent-step trace + interruption matrix

**Webhook path** (one event): claim lease (064, atomic) → [1] UPDATE payments succeeded (W:267) → [2] sale RPC (W:405; idempotent via `status='sold'` early return, 0590:95/126) → [3] INSERT transfers (W:435; UNIQUE payment_id/listing_id, 23505 = benign) → push (fire-and-forget) → complete lease (W:499).
**Client path** (mobile M:280-303 / web Wc:128-176): confirm-payment [1'] UPDATE payments succeeded (C:216) → [3'] INSERT transfer (C:261) → client RPC [2'] `mark_listing_sold`/`complete_auction_payment` → client RPC `ensure_transfer_exists` (061: requires `status='succeeded'`, `ON CONFLICT DO NOTHING`). Mobile calls [2'] even when confirm-payment returned `stripe_verified:false`; web refuses (Wc:134-150).

| Crash after | State left | Who repairs | Gap |
|---|---|---|---|
| lease claimed, before [1] | nothing changed, lease held | Stripe retry ≥300s later reclaims (064) | none (delay only) |
| [1] payment succeeded, before [2] | paid, listing `reserved`, no transfer | webhook retry → fallback branch creates transfer only (W:321-370); client [2'] if app alive | **listing never sold by server.** `cleanup_expired_reservations` (000:335-350, cron 2 min) flips listing to `active` after `reserved_until` → resellable. Second buyer's PI.succeeded UPDATE then hits `idx_payments_one_success_per_listing` (003:52) → `lookupErr` → 500 forever; second buyer charged with no row promoted, no refund path. `E` has no paid-but-unsettled loop (grep: none). |
| [2] sold, before [3] | paid, sold, no transfer | retry fallback branch (harness S1b: `[500,200]`, transfer created); `ensure_transfer_exists` from client | none if metadata present; if `metadata.listing_id/seller_id` missing → 23502 → 500 loop forever (harness S1c: `[500,500]`) |
| [3] transfer, before complete | fully settled, lease held | retry → fallback → `transfer_exists` → 200 | none |
| client [1'] confirm ok, app killed before [2'] | paid, `reserved`, transfer exists (C:261) | webhook (if its own [1] ran first, W:405); else fallback branch does *not* sell | same as row 2 but with a transfer row: seller told to ship (transfer push not sent; transfer visible in UI) for an unsold listing |
| webhook [1] fails with 23505 (double sale) | 2nd buyer charged, row `pending` | nobody | 500 loop 3 days; money stranded |
| `unknown_mode` (W:395) | paid, unsold, no transfer | nobody | 500 loop; metadata never changes |
| refund event DB fail | Stripe refunded, DB `succeeded` | nobody (200 acked) | `E` Phase 1/1b will later POST a *second* refund (E:262, 388) → Stripe "already refunded" error → Sentry every cron run |
| dispute freeze fail | dispute row ok, transfer unfrozen | nobody (event completed) | payout only blocked if `payments.status<>'succeeded'` (E:536, confirm-and-release:385); dispute alone does not block |

`get_incomplete_webhook_events` exists (064:164) but nothing calls it; `E` repairs only expired-unrefunded (Phase 1b) and released-unpaid (Phase 2b) transfers — both *downstream* of settlement.

## 3. Duplicate / out-of-order outcomes (today)

- **PI.succeeded ×2, same event id**: 2nd → `already_processed` 200 (lease) or 409 if in-flight. Correct.
- **PI.succeeded ×2, different ids / vs confirm-payment race**: 2nd → fallback branch → `transfer_exists` 200. Correct *only if* the first delivery finished the sale.
- **charge.refunded before PI.succeeded**: refunded write hits pending row (W:716-724 `neq refunded` passes) → `refunded`. Then PI.succeeded: `neq succeeded` passes → `succeeded`, `mark_listing_sold` runs, transfer created, seller pushed to ship a refunded order; `refunded_at` remains set. `E` Phase 1 later skips refund only if `stripe_refund_id` was captured (best-effort, W:715).
- **PI.succeeded after refund**: identical overwrite (harness S3). confirm-payment retry does the same with no `mark_listing_sold` (client would, on mobile).
- **dispute.created before PI.succeeded**: payment found (pending), no transfer → no freeze; disputes row `transfer_id=NULL`. Later settlement creates an unfrozen transfer; dispute.closed lost marks payment refunded (W:691-695) which blocks payout via `E:536` but never freezes/cancels the transfer.
- **dispute.created after PI.succeeded** (normal): freeze ok; `payout_released_at` set → skip freeze; closed-lost → payment refunded, no reversal (documented ops choice).
- **dispute.closed before dispute.created**: closed → unknown → terminal 200; created then upserts `status='needs_response'` (stale) — no reconciliation.

## 4. Incorrect HTTP acknowledgments

**200 while authoritative work incomplete**: W:519-523 (payment_failed DB error), W:541-547 (`release_reservation` error → `markProcessed()` *success*), W:610-613 (freeze error → success), W:652, W:681, W:696 (refund-mark error → success), W:727, W:759, W:848, W:682-684 (unknown dispute → success), W:733 (refund with no PI → success), W:302 (`payment_not_found` → success; PI charged with no row = create-payment-intent insert-fail path, no compensation).
**Non-2xx where retry cannot help (3-day loop)**: W:280 when the error is 23505 from the partial unique index; W:395 `unknown_mode`; W:355-360 fallback insert 23502/23503; W:459 same; W:418 when RPC raises permanent errors — `'This listing is not reserved by you.'` (reservation released by cleanup or listing resold), `'Your reservation has expired'` (0590:99-103 **also flips the listing back to active as a side effect of the webhook retry**), `'Auction is not in ended state'`, `'You are not the auction winner'`.

## 5. Proposed settlement contract (one function, service_role only, SECURITY DEFINER)

```sql
settle_verified_payment(
  p_payment_intent_id text, p_stripe_status text,        -- 'succeeded' | 'processing' | 'canceled'
  p_amount_received int, p_currency text, p_livemode boolean,
  p_amount_refunded int, p_stripe_refund_id text,        -- from PI/charge; 0/NULL if none
  p_metadata jsonb,                                       -- PI metadata; cross-checked, never trusted
  p_source text                                           -- 'webhook:<evt>' | 'confirm-payment' | 'sweep'
) RETURNS TABLE(payment_id uuid, payment_status text, listing_status text,
                transfer_id uuid, outcome text)          -- outcome: settled | already_settled |
                                                         -- refunded | unknown_payment | binding_mismatch |
                                                         -- unfulfillable | retry_transient
```
Semantics (single transaction; every step guarded by current state, not by "did I run before"):
1. `SELECT ... FROM payments WHERE stripe_payment_intent_id=$1 FOR UPDATE`; none → `unknown_payment` (terminal; caller acks + writes review row).
2. **Binding**: `total = p_amount_received`, `currency`, `stripe_livemode = p_livemode`, `mode/listing_id/buyer_id/seller_id` in metadata equal the row → else `binding_mismatch`, no writes, review row.
3. **Refund monotonicity**: if `status='refunded'` or `p_amount_refunded>0` → set/keep `refunded` (+`stripe_refund_id`, `refunded_at` coalesce), never write `succeeded`; if a transfer exists and is not paid out → hand to Agent C's transition (cancel/freeze); return `refunded`.
4. If `p_stripe_status<>'succeeded'` → no promotion, return current state.
5. Promote `pending/processing/failed → succeeded` (`paid_at = coalesce`). 23505 on partial unique → `unfulfillable` (another payment already settled this listing).
6. `SELECT listings FOR UPDATE`. Sold and this payment is the listing's succeeded payment → continue. `reserved` by buyer (ignore `reserved_until` — money is verified; **Agent A must ratify**) or auction `ended` + `winner_user_id=buyer` → set `status='sold', auction_status='sold', sold_at` (bypass listing guard). Anything else (sold to other, cancelled, reserved by other) → `unfulfillable`.
7. `INSERT transfers ... ON CONFLICT (payment_id) DO NOTHING` (bypass GUC, 056c resets); select id.
8. `unfulfillable`/`binding_mismatch`/`unknown_payment` → `INSERT webhook_retries(payment_id, listing_id, rpc_name='settle_verified_payment', error_message=outcome, resolved=false)` — reuse the orphan table as the compensation/review queue (no new table); Agent C decides refund automation from it.

Callers: webhook `payment_intent.succeeded` (both branches collapse to one call; 200 on any terminal outcome, 500 only on `retry_transient`); confirm-payment (after Stripe fetch, passes `amount_received`, `latest_charge.amount_refunded`); reconciliation sweep (cron edge fn: `get_incomplete_webhook_events` ∪ `payments.status='succeeded' AND (listing not sold OR no transfer) AND paid_at < now()-5min` → refetch PI from Stripe → call). Client RPCs `mark_listing_sold`/`complete_auction_payment` become wrappers that require a succeeded, bound payment (Agent A's domain to finalise). Refund side: `record_payment_refund(pi, refund_id, amount, source)` monotonic; webhook `charge.refunded`/dispute-lost call it; `E` Phase 1/1b must consult `stripe_refund_id` written by it. No new columns needed; one optional: `listings.sold_payment_id` would make step 6 a direct check instead of a join on the partial unique index.

Interfaces needed: **Agent A** — may a verified payment settle a lapsed reservation? must `reserve_buy_now`/cleanup refuse listings holding a succeeded payment? **Agent C** — transfer state on refund/dispute-before-transfer; who consumes the `webhook_retries` review queue for compensation.

## 6. Failing-test designs

1. **Duplicate/out-of-order (pgTAP, `supabase/tests/`)**: seed `payment_d` pending; call the settle contract ×2 with same args → `results_eq` one transfer, `listings.status='sold'`, second call `outcome='already_settled'`. Refund-before-success: `record_payment_refund` then settle → assert `status='refunded'`, listing not sold. *Fails today*: functions don't exist; nearest current assertion — after `UPDATE payments SET status='refunded'` + webhook-equivalent `UPDATE ... WHERE status<>'succeeded'` → status must stay refunded (today flips).
2. **Crash after promotion, before sale (vm handler, vitest `tests/webhook-recovery.test.ts` using the S1 harness)**: inject RPC failure, deliver twice; assert retry is 200 ⇒ `mark_listing_sold` calls ≥ 2 **or** listing sold. Today: calls=1, listing unsold, 200.
3. **Crash after sale, before transfer (vm)**: inject transfer insert 23502 with empty metadata; assert either 200+transfer or a review row. Today: `[500,500]` forever.
4. **Refund/dispute DB failure must not ack (vm)**: S2/S2b/S2c/S2e/S2f; assert `status !== 200` or a durable retry record exists. Today: 200; S2b/S2e even `complete`.
5. **Confirmation after refund (vm, confirm-payment)**: mock payments row `refunded`; assert no `status:'succeeded'` write reaches a row with status refunded (harness asserts filters include `neq status refunded` or a settle RPC call). Today: unconditional write.
6. **Unknown-dispute close (vm)**: assert not `complete_stripe_webhook_event` and a disputes row upserted (or `fail_`). Today: completes, 200.
7. **pgTAP invariant**: after any settle, `NOT EXISTS (payments succeeded ∧ listing.status<>'sold')` and `cleanup_expired_reservations()` must not touch a listing with a succeeded payment. Today the second assertion fails (000:343-348 has no payments check).

## 7. Audit text corrections

- F06 understates: freeze failure (W:610) and dispute-lost payment-mark failure (W:696) are not "recorded then 200" — they are recorded as **success** (`markProcessed()` with no error), so `get_incomplete_webhook_events` would not even surface them.
- F05 "overwrite refund state and paid_at": accurate for `status`/`paid_at`; `refunded_at`/`stripe_refund_id` survive, so the residual row is contradictory rather than cleanly regressed. `E` Phase 1 idempotency (E:239) keys on `stripe_refund_id`, which W:715 stores only when present in the payload — partial mitigation the audit omits.
- F02 scope: the mobile client (M:285) settles the listing itself immediately after PaymentSheet, so real exposure = client failed/killed ∧ webhook RPC failed (or a permanent RPC error). Not wrong, but the practical trigger is narrower than "any redelivery". The audit misses the more dangerous consequence: `cleanup_expired_reservations` re-lists the paid listing and the second buyer's promotion 500-loops on the partial unique index.
- F06 "no consumer of get_incomplete_webhook_events" — confirmed; also `webhook_retries` (069) has no writer at all, so the audit's "durably enqueue" recommendation has an existing empty table to reuse.
