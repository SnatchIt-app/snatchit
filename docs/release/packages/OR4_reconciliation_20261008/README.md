# O-R4 historical refund reconciliation: R0 DONE; R1 PENDING (owner's Dashboard read); no writes (A, 2026-10-09)

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
| R0 | production read (DB, read-only) | list the payments recorded as refunded that have no `payment_refund_state` row: payment id, `stripe_payment_intent_id`, `total`, `amount_refunded_cents`, `status`, `refunded_at`, and `mode`. **Correction:** `mode` is the purchase type (`buy_now`/`auction`). The Stripe mode is **`payments.stripe_livemode`** (D, verified by A). Query below | owner authorises the read |
| R1 | Stripe read (read-only) | for each PaymentIntent from R0, in the right mode (live or test): every refund's `id`, `status`, `amount`, `created`, `failure_reason`. The owner reads in the Dashboard, or authorises a restricted read-only key. A holds no Stripe credential | owner authorises the read |
| R2 | local rehearsal | build R0's rows **with their existing `payment_refunds` ledger rows** on a prod-shape local DB, then run R3's exact calls. Asserts and controls below (§R2) | none (local) |
| R3 | production write | one call per refund: `select public.record_refund_state(<pi>, <re_…>, <status>, <amount_cents>, <failure_reason or null>, <source>, 'reconcile');` with `source` ∈ {`expiry`,`dashboard`,`admin`,`unfulfillable`}. **Where a `payment_refunds` row exists, `source` is that row's `source`. Where none exists, the original path is not recoverable**: Stripe's refund object has no field for our source taxonomy. Then `source` is **the owner's decision per row, recorded as a decision**, never a script default. It is written to `payment_refund_state.source` and `payment_refunds.source`, carried in the after-payout event, and `record_payment_refund` branches on it. One request per call, with a read-back | **separately gated** (owner) |
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

**Chargebacks are out of scope.** A historical `payment_refunds` row with `source = 'dispute_lost'` is **excluded from
O-R4**. `record_refund_state` accepts only four sources (150:157) and raises `INVALID_REFUND_SOURCE`. A chargeback usually
has no refund id either (`REFUND_REFERENCE_REQUIRED`, 150:149). R0 surfaces such a row; O-R4 declines it; it stays
recorded as a chargeback with no refund-state row. It is **never** passed through under a substituted source such as
`admin` (D, 2026-10-08).

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
- every `payment_refunds` row (`stripe_refund_id`, NULL or not; `stripe_dispute_id`; `amount_cents`; **`source`**);
- `amount_refunded_cents`;
- whether a payout is recorded.

**Stripe subscription, as found 2026-10-08 (owner's live-mode read).** Endpoint `we_1TCqy5GdOzCmGbHwxBkCHKL2` already
lists `refund.created`, `refund.failed` and `refund.updated`. How long it has, and what the handlers before v43 did with
any such deliveries, is **unknown**: "0 deliveries this week" says nothing about the historical window. R1 reads the
refunds from Stripe directly, so reconciliation does not depend on past deliveries.

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

## R0 result, 2026-10-09 00:02Z (owner-authorised read; production, read-only)

**Method.**
- Queries validated first on `pkg151_rehears` (ledger 164, same schema).
- Selection widened beyond "status refunded" to catch partial refunds: status `refunded`, OR `refunded_at` set, OR
  `amount_refunded_cents > 0`, OR any `payment_refunds` row.
- Predictions registered first: about 7 rows.

**Totals:**
- 57 payments, 37 succeeded.
- `payment_refund_state` 0 rows; **`payment_refunds` (ledger) 0 rows** production-wide.
- Payout control: 23 of 36 transfers have `payout_released_at` and a `stripe_transfer_id`, so the payout columns are
  populated where payouts exist.
- No open case references these payments or their transfers.

**Hazards.**
- **Hazard 1** (ledger row under another key) **cannot occur**: there are no ledger rows.
- **Hazard 2** (after-payout flag) **cannot occur**: no transfer of these payments has `payout_released_at` or a
  `stripe_transfer_id` (the exact predicate at `20260906120000`:534–535).

All seven PaymentIntents carry the account segment `GdOzCmGbHw`, the same as the live endpoint `we_1TCqy5GdOzCmGbHw…`,
so they are all on the production Stripe account. The 2026-09-22 record says only the 2026-08-04 pair was live; R1
confirms each.

| # | payment | PaymentIntent | type | total | refunded_at (UTC) | transfer | proposed `source` (evidence) | `stripe_livemode` (measured) |
|---|---|---|---|---|---|---|---|---|
| 1 | `50f9a2e3` | `pi_3TFPZiGdOzCmGbHw1JOFjc65` | buy_now | $157.50 | 2026-03-29 22:01 | **none** | **owner decision**: no transfer, no ledger row; the path is not recoverable (`dashboard`, `admin` or `unfulfillable`) | false |
| 2 | `d15dd918` | `pi_3TFRdxGdOzCmGbHw1sfT7nF6` | auction | $78.75 | 2026-04-01 20:25 | expired | `expiry` (the transfer expired; the expiry job refunds expired transfers) | false |
| 3 | `4460d80f` | `pi_3THufwGdOzCmGbHw1ehCiZqd` | buy_now | $31.50 | 2026-04-02 23:35 | expired | `expiry` | false |
| 4 | `49304db7` | `pi_3THuOyGdOzCmGbHw1nGe4nXM` | buy_now | $26.25 | 2026-04-03 23:15 | expired | `expiry` | false |
| 5 | `e52c98e3` | `pi_3TpCE5GdOzCmGbHw1OWqPwF3` | buy_now | $330.00 | 2026-07-04 18:56 | expired | `expiry` | false |
| 6 | `32913315` | `pi_3U0XuwGdOzCmGbHw0WVJfW3y` | buy_now | $11.00 | 2026-08-04 17:20 | **reversed** | **owner decision**: a reversed transfer is not the expiry path. This is the Aug-3 incident's $11 refund; `dashboard` if you refunded it by hand | **true** |
| 7 | `700d469b` | `pi_3U0YzcGdOzCmGbHw0Z6l7bf7` | buy_now | $2.20 | 2026-08-04 17:20 | **reversed** | **owner decision**, as for #6 | **true** |

`amount_refunded_cents` is NULL **table-wide** (0 non-null of 57 payments), not just on these seven. The recompute is
therefore `least(refund_amount, total)`; there is no prior value.

**Live/test, measured** (`payments.stripe_livemode`): #1–#5 are `false` (test); **#6 and #7 are `true` (live)**, refunded
14 seconds apart. Production has 8 live and 49 test payments in total. Only two records involve real money.

**Control weights:**
- **The payout control is the 23/36 transfers.** `payout_attempts` has **0 rows table-wide**, so "0 attempts for these
  seven" carries no weight.
- **The chargeback exclusion has zero members here** (no dispute id, empty ledger). It remains a guard on what R3 must
  refuse; it filtered nothing in this data set.
- **The first detector tick after O-R2** (opened 0 over 0 refund-state rows) shows the job runs without erroring. It is
  not detection evidence. The first such evidence can only exist after an authorised R3, or the first real refund
  event.

**What reconciliation would do, per R1 outcome** (R3 stays separately gated):
- **Succeeded, amount = total:**
  - writes a refund-state row and a log row, and the first ledger row (source as decided);
  - `amount_refunded_cents` NULL → total; `status` stays `refunded`; `refunded_at` unchanged;
  - no payout flag; no case;
  - the app's "Refund recorded" becomes a confirmed refund.
- **Failed or canceled:**
  - `refund_failed_cents > 0`, and with detection now on, a **p1 `refund_failed` case** opens within 5 minutes;
  - **the buyer may never have been repaid**; the owner follows O-R3.
- **Pending:** a `refund_pending` case after 120 h.
- **Amount < total:**
  - the cents would be recorded below total while `status` stays `refunded` (the monotonic trigger);
  - **stop for the owner** before writing.
- **No refund in Stripe at all:** **do not reconcile**. The row says refunded but Stripe shows no refund; the owner
  investigates. Money may not have been returned.

**Proposed scope:**
- **Reconcile the 2 live rows (#6, #7)** after R1 and the source decision.
- **The 5 test-mode rows: exclusion RECOMMENDED (A and D), PENDING THE OWNER'S RULING.** This is a recommendation,
  not a decision. The owner chooses: **exclude**, or **reconcile for display consistency**.
  - **Primary reason: the system's own boundary.** `_shared/payout-logic.ts:144–152` (`rowIsLiveActionable`) admits
    only `stripe_livemode = true` rows into refund, payout and reconciliation paths. `false` rows are
    "preserved-but-inert test-era audit data"; the only exception is a sandbox-only switch that the release checklist
    asserts is absent in production. Production code already treats all five as inert, so R3 would be the only
    money-rail write across that boundary.
  - **Secondary reason:** the write would permanently trip 150's rollback guard for payments where no money moved.
  - **Reversible alternative**, if they look wrong in an account view: a `stripe_livemode` display filter (D's lane).
- **Provenance of `stripe_livemode`** (D, verified at source): it is recorded from Stripe's own `livemode`
  (`create-payment-intent`, `confirm-payment`). The only path that writes `false` afterwards is the cross-mode
  quarantine in `enforce-transfer-expiry`, which matches Stripe's "similar object exists in test mode" error. That
  correction is logged to Sentry, not the row. So the right wording is **"Stripe classifies these as test mode"**, not
  "never live". Whether any of #1–#5 was quarantined is unestablished (Sentry unread).

## R1: the owner's Dashboard read (A holds no live-account access)

The Stripe CLI on this machine is logged into "SNATCH IT sandbox" (`acct_1T6Fb1GlD5aqtxIw`), a different account, so it
cannot read these. For each PaymentIntent above:
1. Open `https://dashboard.stripe.com/payments/<pi>` (live). If it is not found, open
   `https://dashboard.stripe.com/test/payments/<pi>` (test).
2. Report: live or test, and **for every refund on it**: refund id (`re_…`), status, amount, date, and failure reason
   if any.

**Live read, required now:** #6 and #7. **The test-mode five: conditional.** If the owner rules exclude, no read is needed. If the owner chooses to reconcile them, R1 must also read #1–#5 in the real account's **test mode** (`https://dashboard.stripe.com/test/payments/<pi>`) before anything is written. Writing a refund state without reading the real one would reintroduce the defect 150 fixed. They are not in the sandbox: D's CLI read returned `resource_missing` in `acct_1T6Fb1…`.
