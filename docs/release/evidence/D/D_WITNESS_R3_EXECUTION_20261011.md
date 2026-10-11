# D — witness record: R3 execution of the two reconciliation writes

2026-10-11. A executed both approved files under the owner's hash-specific approval. D witnessed by
independent reads. **D executed nothing.**

## 1. Result: both writes landed correctly. Every predicted value matches.

### Payments

| | #6 `32913315` | #7 `700d469b` |
|---|---|---|
| status | `refunded` (unchanged) | `refunded` (unchanged) |
| total | 1100 | 220 |
| `amount_refunded_cents` | NULL → **1100** | NULL → **220** |
| `stripe_refund_id` | NULL → **`re_3U0XuwGdOzCmGbHw0bL9UYzT`** | NULL → **`re_3U0YzcGdOzCmGbHw0Av5k7ZH`** |
| requested/succeeded/failed | 0/0/0 → **0/1100/0** | 0/0/0 → **0/220/0** |
| `refunded_at` | **2026-08-04 17:20:05.165Z — UNCHANGED** | **2026-08-04 17:20:19.353Z — UNCHANGED** |

`refunded_at` surviving to the millisecond is the one D predicted *structurally* from
`coalesce(refunded_at, now())` plus the set-once guard, rather than from the rehearsal. It held.

### Rows written — exactly 2 of each, none for any other payment

- **`payment_refund_state`** (2): both `succeeded`, amounts 1100/220, `source dashboard`,
  `failure_reason NULL`, `last_observed_via reconcile`, first observed 16:33:29Z / 16:33:47Z.
- **`payment_refund_state_log`** (2): same ids, statuses and amounts, `observed_via reconcile`.
- **`payment_refunds`** (2): correct refund ids, `stripe_dispute_id NULL`, 1100/220, `source dashboard`.

### Unchanged, as required

Transfers both still `reversed` with no `payout_released_at` and no `stripe_transfer_id`.
Payout attempts for these payments: 0. **Cases created today: 0.**

**The five excluded test-mode payments were not touched** — `payment_refund_state` holds exactly 2
rows and both belong to #6 and #7.

## 2. The detector tick after the writes — D's sharpest prediction, and it held

First `refunds` run after execution, **2026-10-11 16:35:00Z**: `succeeded`, **`items_scanned` 2**,
**`cases_opened` 0**, detail `{"opened": 0, "scanned": 2, "resolved": 0}`.
`refund_resolution`: `skipped`, `refund_resolution_disabled`.

**`items_scanned` is still 2 — identical to every run before the write.** D predicted this from reading
the two gated loops: they select `failed|canceled` and `pending|requires_action`, so a `succeeded` row
matches neither and never increments. Two real rows now exist and the detector's output did not move.

**This confirms what D told the owner in advance: completing O-R4 does not demonstrate that refund
detection works.** The figure was 2 across 288 runs before detection was enabled, 2 across 255 runs
after, and it is 2 now with live data present. The first genuine evidence still requires a refund that
is actually pending or failed.

## 3. Where D's witnessing was weaker than it should have been — stated plainly

**D did not capture an independent immediately-before prestate for record #6.**

A offered "a few minutes" to get a prestate in before #6 and said it would otherwise proceed. D's first
prestate query was malformed (a UNION column-count error), and by the time the corrected read landed,
**#6 had already been written**. #7 was still untouched at that moment, then executed between D's two
queries.

So, precisely:

- **#7 — clean witness.** D holds an independent read taken while #7 was still `NULL / NULL / 0/0/0`,
  minutes before it was written.
- **#6 — degraded witness.** D's nearest independent prestate is the verdict-stage read of
  **2026-10-10** (and R0 before it), both showing `NULL / NULL / 0/0/0` and all three tables empty.
  That is a day stale, not seconds stale.

**What still backs #6:** the file's own prestate guards re-check every one of those values atomically
and raise on any drift, so the write could only have proceeded from the state D had recorded. That is a
structural backstop, not an independent observation, and it should not be described as one.

**This was D's failure of timing, not A's.** A did exactly what it said it would do.

**One value D cannot independently confirm:** `payout_decisions` scoped to these two payments reads **2**
now. D never captured a scoped before-value — only a global count of 4 at prestate. The script asserts
that count unchanged and would have raised otherwise, so it rests on the script's assertion rather than
on D's own comparison.

## 4. Owner's conditions, checked

| condition | result |
|---|---|
| exact approved files, hashes recomputed | A reports MATCH at 16:32:34Z; D independently recomputed the same two hashes before approval (`45fbe3dd`) |
| prestate guards run | passed — the writes proceeded, and they refuse otherwise |
| each file executed once | 2 state rows, 2 log rows, 2 ledger rows; no duplicates |
| stop on mismatch, no blind retry | no mismatch arose; nothing retried |
| five excluded payments unchanged | confirmed — no rows for them |
| no new refunds, payouts, settings or deployments | none observed; transfers and payout records unchanged |
| verify resulting records and next detector run | §1 and §2 |

## 5. What this closes, and what it does not

**Closed:** the historical refund reconciliation for both live payments. The app will now show these as
refunds with a recorded succeeded state rather than a legacy "refund recorded".

**Not closed, and unchanged by this:** refund-state detection remains unevidenced (§2); refund
execution and alert delivery remain off; the five test-mode payments remain excluded; the rendered
wording on the authenticated pages remains waived rather than verified.

**Irreversible from here:** `payment_refund_state_log` and `payment_refunds` are append-only, and 150's
rollback guard (`payment_refund_state rows = 0`) no longer holds. That was stated before approval and
is now the standing position.

---

## 6. A's four requested checks, on D's own reads

**(a) After-state of both rows and their state/log/ledger rows** — §1. Matches A on every field.

**(b) The excluded five — unchanged and untouched.** All five: `stripe_livemode false`, status
`refunded`, `amount_refunded_cents` **NULL**, cents **0/0/0**, and **0 `payment_refund_state` rows
each**. Global totals are **2 state / 2 log / 2 ledger**, every one of them accounted for by #6 and #7,
so nothing was written for any other payment. The scripts also pin `c_payment_id`, so they could not
have reached them.

*One observation, not a change:* four of the five already carry a `stripe_refund_id`
(`re_3THufw…`, `re_3THuOy…`, `re_3TFRdx…`, `re_3TpCE5…`) while `50f9a2e3` does not. **D has no
baseline for that column on these rows** — R0 did not select it — so D states it as pre-existing rather
than as unchanged. It cannot have been written today, since today's writes produced exactly the two
ledger rows above. Mildly odd that those four have a refund id while `amount_refunded_cents` is NULL,
since `record_payment_refund` sets both; it suggests an earlier path or backfill populated the id
alone. Out of scope here, flagged for the record.

**(c) The 16:35:00Z run and no new case** — §2. `refunds` succeeded, scanned 2, opened 0;
`refund_resolution` skipped. **0 cases created today**, and the total stands at 21.

**(d) The `payout_decisions` dates — this closes the gap D could not close itself.**

| payment | decision | decided_at (UTC) | reason codes |
|---|---|---|---|
| `32913315` | `manual_review` | **2026-08-04 03:00:03Z** | `PAYOUT_TRANSFER_FAILED` |
| `700d469b` | `manual_review` | **2026-08-04 03:27:40Z** | `BUYER_CONFIRMED,PAYOUT_TRANSFER_FAILED` |

**Both predate the run by two months.** D had recorded that it could not independently confirm the
scoped `payout_decisions` count was unchanged, having never captured a before-value. The `decided_at`
dates settle it directly: these rows existed long before today, so the run did not create them. A's
equivalent miss resolves the same way.

**A contextual finding that falls out of it.** Both payments were flagged `manual_review` with
`PAYOUT_TRANSFER_FAILED` at 03:00 and 03:27 on 2026-08-04, and were refunded at 17:20 the same day.
That is a coherent sequence: the payout transfers failed in the early hours, and the payments were
refunded about fourteen hours later. It fits `source = 'dashboard'` — a manual refund following a
failed payout — though the determination already rests on the code rule and does not need this.
It also matches the owner's own records of an August payment incident.

## 7. D's verdict on the execution

**Both writes are correct, complete and confined to the two approved records.** Every value D
predicted in advance matched, including the two D derived structurally rather than from rehearsal:
`refunded_at` preserved to the millisecond, and the detector's `items_scanned` staying at 2.

The owner's conditions were met. The limitation in D's own witnessing of #6 (§3) stands as recorded
and does not change the verdict — it changes only how strongly D can claim to have observed the
before-state of that one record, as opposed to relying on the file's atomic guards.
