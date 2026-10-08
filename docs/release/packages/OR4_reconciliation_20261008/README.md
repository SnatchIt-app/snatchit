# O-R4 historical refund reconciliation: PREPARED, NOT RUN (A, 2026-10-08)

**Owner direction (2026-10-07):** "Prepare the historical reconciliation package; correction writes remain separately
gated." Nothing here has been read from or written to production. Each production step below needs the owner's own
authorisation of that step.

## Why

Migration 150 (applied 2026-10-08 02:37Z) added per-refund state. It did **not backfill** (150 header). So refunds
recorded before 150 have no `payment_refund_state` row, and the app shows them as a legacy "Refund recorded". The
records name 7 historical refunded rows, 2 of them live on 2026-08-04 (RL §B O-R4). That count is a **record, not a
read**; R0 establishes it.

## Steps

| Step | Kind | What | Gate |
|---|---|---|---|
| R0 | production read (DB, read-only) | list the payments recorded as refunded that have no `payment_refund_state` row: payment id, `stripe_payment_intent_id`, `total`, `amount_refunded_cents`, `status`, `refunded_at`, and `mode`, which says which Stripe mode R1 reads. Query below | owner authorises the read |
| R1 | Stripe read (read-only) | for each PaymentIntent from R0, in the right mode (live or test): every refund's `id`, `status`, `amount`, `created`, `failure_reason`. The owner reads in the Dashboard, or authorises a restricted read-only key. A holds no Stripe credential | owner authorises the read |
| R2 | local rehearsal | build R0's rows **with their existing `payment_refunds` ledger rows** on a prod-shape local DB, then run R3's exact calls. Asserts and controls below (§R2) | none (local) |
| R3 | production write | one call per refund: `select public.record_refund_state(<pi>, <re_…>, <status>, <amount_cents>, <failure_reason or null>, <source>, 'reconcile');` with `source` ∈ {`expiry`,`dashboard`,`admin`,`unfulfillable`}, taken from the original refund's path (R0/R1). One request per call, with a read-back | **separately gated** (owner) |
| R4 | read-back | per refund: the `payment_refund_state` row, the log row, the payment sums; and that no unexpected case opened | with R3 |

## R2: what the rehearsal must prove (revised after D's review, 2026-10-08)

**Not a re-call test.** A repeated call with the same refund id cannot double-count, by structure:
- `payment_refunds.stripe_refund_id` is UNIQUE and the insert is `ON CONFLICT (stripe_refund_id) DO NOTHING`
  (`20260906120000`:311, :506);
- the total is recomputed as `least(greatest(existing, sum), total)` (:514–515).

A test that calls twice with the same id is green whatever happens. A NULL refund id is also impossible here:
`record_refund_state` raises `REFUND_REFERENCE_REQUIRED` before it reaches `record_payment_refund`.

**The real hazards, which depend on R0's data:**
1. **The same refund is already in `payment_refunds` under another key** (another id, or the NULL-id/dispute path at
   :508–510). Reconciling with Stripe's `re_…` then adds a second ledger row; `sum` overstates it. The `least(…,
   total)` cap bounds the cents, but at `>= total` the same statement sets `status='refunded'` and `refunded_at`
   (:521–522). A partial refund would become a false full refund.
2. **The refund predates the ledger** (no `payment_refunds` row at all). The first insert recomputes the total; because
   `greatest` keeps the existing value, the cents should not move. But when the payment has a recorded payout, the
   insert emits `REFUNDED_AFTER_PAYOUT` / `PARTIAL_REFUND_AFTER_PAYOUT` (:540), which opens the reversal path.

**R2 asserts, per fixture:**
- `amount_refunded_cents`, **`status` and `refunded_at`**;
- the `payment_refunds` row count;
- any after-payout event.

**Negative control:** reconcile one fixture whose refund is already recorded, using a **different** id, and show the
cents and status move. If the control does not move them, the rehearsal cannot fail.

**R3 refuses any payment that has a hazard-1 row.** Those go to the owner for a decision instead.

**R0 query** (read-only):
```sql
select p.id, p.stripe_payment_intent_id, p.mode, p.total, p.amount_refunded_cents, p.status, p.refunded_at
  from public.payments p
 where (p.status = 'refunded' or p.refunded_at is not null)
   and not exists (select 1 from public.payment_refund_state s where s.payment_id = p.id)
 order by p.refunded_at nulls last
```
The column names were checked against the gate (`000_baseline` plus later `add column`s); the query is run on the R2
rehearsal DB before production. Before trusting a short list, run it with the `not exists` removed as a positive
control.
R0 also reads, for those payments:
- every `payment_refunds` row (`stripe_refund_id`, NULL or not; `stripe_dispute_id`; `amount_cents`);
- `amount_refunded_cents`;
- whether a payout is recorded.

## What R3 changes, and what it cannot undo

- `payment_refund_state` rows are upserts, but `payment_refund_state_log` is **append-only** (150's trigger). A
  reconciliation write cannot be cleanly rolled back; it can only be superseded by a later observation. Package 150's
  rollback guard (`payment_refund_state_rows=0`) will **block** rolling back 150 once R3 has written any row.
- **Detection.** If O-R2 is on when R3 runs, a reconciled `failed` or `canceled` refund not covered by succeeded refunds
  opens a p1 `refund_failed` case within 5 minutes. That is the intended effect. The owner works it per O-R3.
- **Unknown payment.** If R1 returns a refund whose PaymentIntent has no payment row, the function returns
  `recorded=false, reason=unknown_payment` and writes nothing. That is recorded, not retried.

## Order relative to O-R2

Either order is safe. Running R3 after O-R2 means a reconciled failure becomes a case, which is why the sheet prefers
it.
