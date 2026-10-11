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
