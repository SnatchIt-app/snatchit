# O-R4 historical refund reconciliation (A, 2026-10-09)

**Status:**
- R0 DONE.
- Test-mode five EXCLUDED by the owner's ruling.
- R1 PARTIAL: the owner's live Dashboard read gives amounts and displayed status. The refund ids, refund status and
  refund-object count are still needed.
- R2 rehearsal PASS.
- R3 PREPARED, NOT AUTHORISED.
- No production writes.

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

**What reconciliation would do, per R1 outcome** (written at R0; **superseded by the rehearsed matrix in §R3
"Effects depend on what R1 part 2 returns"**, which is the reference):
- **Succeeded, amount = total:** a refund-state row, a log row and the first ledger row; `amount_refunded_cents`
  NULL → total; `status` and `refunded_at` unchanged; no payout flag; no case. What the app then displays is not
  verified in this package.
- **Failed or canceled:**
  - `refund_failed_cents > 0`, and with detection now on, a **p1 `refund_failed` case** opens within 5 minutes;
  - **the buyer may never have been repaid**; the owner follows O-R3.
- **Pending:** a `refund_pending` case 120 h after **reconciliation** (the clock is `first_observed_at`, not Stripe's
  `created`).
- **Amount < total:**
  - the cents would be recorded below total while `status` stays `refunded` (the monotonic trigger);
  - **stop for the owner** before writing.
- **No refund in Stripe at all:** **do not reconcile**. The row says refunded but Stripe shows no refund; the owner
  investigates. Money may not have been returned.

**Proposed scope:**
- **Reconcile the 2 live rows (#6, #7)** after R1 and the source decision.
- **The 5 test-mode rows: EXCLUDED by the owner's ruling (2026-10-09).** The owner's words: "I approve excluding
  the five identified test-mode payments from the live historical refund reconciliation. Preserve their records and
  document the exclusion; this is not permission to delete records or change their mode."
  - #1–#5 stay as they are: no refund-state, log or ledger rows; `stripe_livemode` unchanged; nothing deleted.
  - Their test-mode Stripe reads are not required.
  - The R3 script refuses any non-live payment in any case (R2 control C6, killed only by its own guard, M1).
  - The reasoning recorded for the recommendation follows, kept as history.
  - **Primary reason: the mode boundary lives at the edge, and R3 bypasses it** (D; verified by A at `abef9506` from
    function bodies, not line numbers).
    - `rowIsLiveActionable` (`_shared/payout-logic.ts:144–152`) admits only `stripe_livemode = true` rows into the
      money rails. `false` means "preserved-but-inert test-era audit data". Its one call site is
      `enforce-transfer-expiry:618`; `ops-refund-execute` and `stripe-webhook` enforce equivalent rules in their own
      code.
    - **R3's SQL path is mode-blind:** `record_refund_state` (150:125), `record_payment_refund` (`20260906120000`:457)
      and `ops.detect_refunds` (150:262) contain no livemode check. Only `claim_payout_attempt` (`…120000`:559)
      refuses non-live rows (`PAYMENT_NOT_LIVE`).
    - So what keeps these five inert today is edge code, and a direct R3 call is not constrained by it.
  - **Operational cost:** detection is on, and `ops.detect_refunds` has no livemode filter. A reconciled
    failed/canceled test refund would open a **p1 `refund_failed` case about money that never moved**, in the queue
    the owner works daily (O-R3).
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

**Scope after the owner's ruling:** #6 and #7 only. The test-mode five are excluded (above), so no test-mode read is
needed.

### R1 part 1: the owner's live Dashboard screenshots (2026-10-09)

The owner supplied two live-mode payment pages and stated, "I confirm this is Live mode". The screenshots truncate
the PaymentIntent ids; the full ids come from R0.

**Matching to R0.** Each item is checked against our own rows, not inferred from the screenshot:

| check | #6 `32913315` | #7 `700d469b` |
|---|---|---|
| PaymentIntent prefix shown | `pi_3U0XuwGdOzCmGbHw0WVJ…` = R0 `pi_3U0XuwGdOzCmGbHw0WVJfW3y` | `pi_3U0YzcGdOzCmGbHw0Z6l7b…` = R0 `pi_3U0YzcGdOzCmGbHw0Z6l7bf7` |
| Payment amount shown = R0 `total` | $11.00 = 1100 | $2.20 = 220 |
| **Pairing** | the larger amount sits on the `…0WVJ…` intent in both sources | (same) |
| Payment status shown | Refunded = R0 `status` refunded | Refunded = R0 `status` refunded |
| "Refunded amount" line | −$11.00, equal to the total | −$2.20, equal to the total |
| Live mode | owner's statement **and** R0 `stripe_livemode = true` (recorded from Stripe's own `livemode`) | (same) |
| Refund activity shown | "Aug 4, 5:20 PM" | "Aug 4, 5:20 PM" |
| R0 `refunded_at` (UTC) | 2026-08-04 17:20:05 | 2026-08-04 17:20:19 |

The amount pairing is the real cross-check: two different amounts land on the right two intents. The PaymentIntent
prefixes alone would be weaker.

**On the time.** "5:20 PM" equals our recorded 17:20 **only if the Dashboard displays UTC**. The display timezone is
not established, and this machine's local zone is UTC−4, so the agreement is recorded as conditional.
- `refunded_at` is when *our* row was marked refunded, not Stripe's refund `created`. The two may differ.

**Disregarded, as the owner instructed:** the activity notes "test" and "test 2". They are not evidence of Stripe
test mode or of the refund's origin.

**Not established by the screenshots** (owner's list, with D's additions):
1. **The refund id (`re_…`).** The 23-digit ARN shown on each page is an Acquirer
   Reference Number for the card network, not a refund id. It is never substituted for one (R2 control C2 refuses an
   ARN).
2. **The refund object's status.** "Refunded" is the **payment's** badge, and it is not even a value of the refund
   status enum (`pending|requires_action|succeeded|failed|canceled`). A payment can read Refunded while its refund is
   `pending`, or later `failed`; telling those apart is what 150 exists for. The badge is never mapped onto the refund
   status.
3. **How many refund objects** each payment has. One aggregate "Refunded amount" line cannot exclude two partial
   refunds that sum to the total, and one activity entry is suggestive, not conclusive. R3 makes one call per refund
   object.
4. **The refund's `created`** with year and timezone. It is not an R3 input (`record_refund_state` takes no
   timestamp), but it is provenance and a cross-check against `refunded_at`.
5. **The failure reason**, if any.
6. **Provenance** (how the refund was initiated), and whether the customer's bank received it. Neither is claimed.

**Source** (`expiry|dashboard|admin|unfulfillable`) stays the owner's recorded decision per row. Stripe's refund
object has no field for our taxonomy.

**Observed, out of scope.** One screenshot only, the $2.20 page (#7, clock 5:56 PM), shows a Dashboard notice:
- where: a popover at the top right, below the notifications bell, with a red warning icon;
- text: "Add funds in USD to cover your negative balance";
- it partly covers the "+ Add to block list" button, which reads "+ Add to bloc";
- the $11.00 screenshot does not show it.

It establishes nothing about the balance: not the amount, the date, the cause, or whether it is current. It is not
part of O-R4. It may matter to any future refund execution, which stays off (`refund_execute_enabled = false`).

### R1 part 2: the one remaining request

For each of the two payments:
- open the refund's **View details**, from "Payment refunded … View details";
- report **each refund listed** (normally one): its id (`re_…`), its own status, its amount, its created date with year
  and timezone, and its failure reason (if any);
- state how many refunds the payment lists;
- say how each refund was issued: by hand in the Dashboard, through our admin tool, by the expiry job, or because
  the order could not be fulfilled. This is the owner's `source` decision; Stripe does not record our categories.

If any refund is not a single `succeeded` refund equal to the total, that payment's script is revised and
re-rehearsed before it is offered for approval (§R3).

## R2 rehearsal: PASS (2026-10-09, local clone of `pkg151_rehears`, ledger 164; never production)

Run with `bash rehearsal/run_R2.sh or4_r2_rehears_<n>` against a fresh clone. Predictions were written before run 1
(`rehearsal/R2_predictions.txt`).

**Fixtures.** #6 and #7 use their real ids, PaymentIntents, totals and `refunded_at`. Control payments cover test
mode, an existing ledger row, a paid transfer, a pre-set `stripe_refund_id`, and a genuine partial refund. They were
seeded with `session_replication_role = replica` for setup only; every call under test ran with all triggers on.

**Run 4: 24 PASS, 0 FAIL** (`rehearsal/out/R2_run_4.txt`; run 3 was identical before the ARN redaction):
- **Refusals, nothing written:** C1–C9.
  - C1: the committed file with its markers unfilled.
  - C2: the ARN given as the refund id.
  - C3–C5: status `pending`, source `reconcile`, amount 600 of 1100.
  - C6: a test-mode payment.
  - C7: a ledger row under another key.
  - C8: a paid transfer.
  - C9: `payments.stripe_refund_id` already set to another id.
- **Writes:** W6 and W7 used the committed files, with exactly the 3 marker lines replaced.
  - Read-back per record: `amount_refunded_cents` = total; cents (requested, succeeded, failed) = (0, total, 0);
    `refunded_at` unchanged.
  - One succeeded state row (via `reconcile`), one log row, one ledger row. The transfer is unchanged; 0 cases.
  - A second run of W6 is refused before writing.
- **Detection:** `ops.detect_refunds()` read `opened 0` before and after.
  - **Positive control:** a *failed* state row opens exactly one `refund_failed` case in the same DB, so the 0 for
    succeeded rows discriminates.
- **Mutants, rolled back, each shown applied:**
  - M1: livemode guard removed → the test-mode write goes through. C6's refusal comes from that guard alone; no
    postcondition covers live mode.
  - M2: ledger guard removed → caught by the postcondition `ledger rows: 2`.
  - M3: payout guard removed → caught by `payout records changed`.
- **Raw hazard-1 control (no script):** a second refund id for 600 turns a 600 partial into `refunded` 1100. The
  hazard is real, and C7/M2 are what stop it.

**Run 1 found a gap, now fixed.** The after-payout flag writes `payout_attempts` and `payout_decisions`, not
`transfers`, so a "transfer unchanged" postcondition could not see hazard 2. The template now snapshots both payout
tables before the write and asserts they are unchanged after. Runs 1–3 are kept in `rehearsal/out/`, with the real ARN that C2 first used redacted; C2 now uses a synthetic 23-digit value.

## R3: prepared, NOT authorised

**Files:**

| file | sha256 (with markers) |
|---|---|
| `R3_record_refund.sql.tmpl` (source) | `97f1d0a1370e92a5b22142807bacb91a99e50119f8b86d46ac32fbe63cdcef9d` |
| `R3_proposed_6_32913315.sql` | `74cfe59a69da8d7d77deefb8887a1bc32e24ab556155938553a9661fd5fa5298` |
| `R3_proposed_7_700d469b.sql` | `41372b17fd232ffc44db37f4ec9cc9b7cb18423d3ca8a228d95d9ff42cd5828f` |

Each file is one atomic `DO` block: input guards, then prestate guards (exactly R0), then
`record_refund_state(pi, re_…, 'succeeded', total, null, <source>, 'reconcile')`, then postconditions. Any failure
rolls the whole block back.

**Markers.** Three remain in each file: `__R1_REFUND_ID__`, `__R1_REFUND_STATUS__` and `__OWNER_SOURCE__`. As
committed, each file refuses to run (C1).
- After R1 part 2 and the source decision, A fills the three markers and nothing else.
- A then presents the filled files, a diff showing exactly 3 changed lines, and their new sha256.
- **The owner approves those exact shas.**

**Scope.** Only a single succeeded refund equal to the total is handled. If R1 shows anything else for a record
(pending, failed, canceled, a partial, or more than one refund object), the script refuses and that record gets its
own plan, with the expected case or flag stated before anything runs.

**Effects depend on what R1 part 2 returns.** None of the effects below is a promise until the actual refund
details are in. They were rehearsed per branch on the #6 fixture (`rehearsal/run_R2b_outcomes.sh`, run 2: 8/8 PASS,
all rolled back; predictions in `R2b_outcomes_predictions.txt`). The calls were raw `record_refund_state`, one per refund
object.

| R1 shows | state / log / ledger rows | `amount_refunded_cents` | cents (requested, succeeded, failed) | case on the next tick | handled by the current script? |
|---|---|---|---|---|---|
| O1 one refund, `succeeded`, = total | 1 / 1 / 1 | NULL → total | (0, total, 0) | none | **yes** (the only branch) |
| O2/O3 one refund, `pending` or `requires_action` | 1 / 1 / 1 | NULL → total | (total, 0, 0) | none at first. A p1 `refund_pending` opens **120 h after reconciliation** (simulated, O2t) | no: revise, then rehearse |
| O4/O5 one refund, `failed` or `canceled` | 1 / 1 / **0** | stays NULL | (0, 0, total) | **p1 `refund_failed` opens** | no: revise, then rehearse |
| O6 two refunds, both `succeeded`, summing to total | 2 / 2 / 2 | NULL → total | (0, total, 0) | none | no: one call per refund; revise |
| O7 two refunds, `failed` then `succeeded` (a retry) | 2 / 2 / 1 | NULL → total | (0, total, total) | none (the failure is covered) | no: revise |

In every branch:
- `payments.status` stays `refunded`; it is terminal, even when the refund failed;
- `refunded_at` is unchanged;
- the transfer is unchanged, and no payout rows are written (no payout exists).

The ledger entry carries the owner's `source`. **What the app then displays** for each branch is not verified in this
package; that is C's surface, and it needs a device or app check before any claim is made about it.

The console's refunded-money figure (126) would count a ledger row; a failed refund adds none.

**If the details show anything other than O1 for a payment, A revises that payment's script and rehearses it**, with
the exact effects (including any case) stated before it is offered for approval.

**Irreversible once run:**
- the log and ledger are append-only;
- `stripe_refund_id` and `refunded_at` are set-once, and `amount_refunded_cents` is non-decreasing;
- 150's rollback guard stops holding.

**Run, when approved:** one Management API request per file, then `R4_readback.sql` (read-only), then the next
`refunds` tick's `ops.job_run` row and a case check. D witnesses.
