# O-R4 R3 execution record (A executes, D witnesses; 2026-10-11)

**Owner approval (verbatim, 2026-10-11):** "I approve execution of these exact correction files:
R3_proposed_6_32913315.sql SHA-256: d7f31cf175410b313a77b3475fe6444b6e34eac5f40b3ddc6b36c3ce0af20d88
R3_proposed_7_700d469b.sql SHA-256: dca8cb00db615104eef01c8ac3cb58f7cf075c294ba7a5aaa018348ad8d2a996
I ratify source='dashboard' as derived from our application's classification rule, not as a statement about who
initiated the refunds. I understand the history and ledger entries are append-only. Recompute both hashes and run the
existing prestate guards. Execute each approved file once, with D independently witnessing, then verify the resulting
records and next detector run. Stop on any mismatch or unexpected result; do not retry blindly. This approval does not
authorize new refunds, payouts, settings changes, deployments, or changes to the five excluded test-mode payments."

**Hashes recomputed 2026-10-11 16:32:34Z:** both MATCH. The tree is clean at `64277d68`.

**Transport.** One Supabase Management API request per file (`POST /v1/projects/hqycwntpfoztoinemqns/database/query`),
whose body is the exact file bytes. The helper recomputes the sha256 of the bytes it sends and refuses on any mismatch.
Each file is one atomic DO block, so any guard or assertion failure rolls back the whole file.

## Predictions (written before the first run)

**Per file:**
- the request succeeds;
- R4 read-back for that record: `status refunded`; `amount_refunded_cents` = total (1100 / 220); cents (requested,
  succeeded, failed) = (0, total, 0); `stripe_refund_id` = its `re_…`; `refunded_at` unchanged (17:20:05 / 17:20:19);
- `state` = one row `{re, succeeded, total, dashboard, reconcile}`; `log_rows` 1; `ledger` = one row
  `{re, total, dashboard}`;
- transfers unchanged (`reversed`, no payout); cases 0.

**The other record** is untouched between the two runs: #7 still equals R0 after #6 runs.

**The next `refunds` job_run after execution:**
- `status succeeded`, `opened` 0;
- `items_scanned` unchanged at 2, because a succeeded state row is selected by neither gated branch. This is expected,
  and it is no evidence that detection works (F-DETECT-REFUNDS-UNOBSERVABLE-1);
- no new `refund_failed` / `refund_pending` case.

**Not touched:** the five excluded test-mode payments (their refund cents and state stay empty), every other payment,
`ops.setting`.

**Stop conditions:** any HTTP error, any `R3_GUARD` or `R3_ASSERT`, or any read-back that differs from the above.
On a stop: no retry. Report the exact output.

## Results

**Prestate (2026-10-11 16:33:18Z), R4 read-back: equal to R0.** Both rows `refunded`, live, `amount_refunded_cents`
NULL, cents (0,0,0), `stripe_refund_id` NULL, no state, log or ledger rows, one reversed unpaid transfer, 0 cases.

**Baselines:**
- the last `refunds` run was 16:30:01Z, succeeded `{opened 0, scanned 2}`;
- 21 cases in total, 2 of them open refund cases (pre-existing);
- `payment_refund_state` 0 rows and `payment_refunds` 0 rows;
- the excluded five were `refunded`, with `amount_refunded_cents` NULL and succeeded cents 0;
- `refund_state_detection_enabled` true.

| step | time (UTC) | sha256 of bytes sent | result |
|---|---|---|---|
| #6 `R3_proposed_6_32913315.sql` | 16:33:29–16:33:30 | `d7f31cf175410b313a77b3475fe6444b6e34eac5f40b3ddc6b36c3ce0af20d88` | HTTP 201, `[]`: the DO block completed, so every guard and assertion passed |
| read-back after #6 | 16:33:40 | — | #6 as predicted; **#7 untouched (= R0)** |
| #7 `R3_proposed_7_700d469b.sql` | 16:33:46–16:33:47 | `dca8cb00db615104eef01c8ac3cb58f7cf075c294ba7a5aaa018348ad8d2a996` | HTTP 201, `[]` |
| read-back after #7 | 16:34:00 | — | both as predicted (below) |

The helper refuses on a hash mismatch before sending anything; a deliberate wrong hash was refused with exit 4.

**After, per record, as predicted:**
- #6: `amount_refunded_cents` 1100; cents (0, 1100, 0); `stripe_refund_id` `re_3U0XuwGdOzCmGbHw0bL9UYzT`;
  `refunded_at` 17:20:05 (unchanged).
- #7: 220; (0, 220, 0); `re_3U0YzcGdOzCmGbHw0Av5k7ZH`; 17:20:19 (unchanged).
- Each has one state row `{succeeded, dashboard, reconcile}`, one log row and one ledger row `{dashboard}`; its
  transfer is still `reversed` with no payout; 0 cases.

**Side effects:**
- totals: 2 state rows, 2 log rows, 2 ledger rows;
- 21 cases (unchanged);
- the excluded five are unchanged;
- `refund_state_detection_enabled` is still true.

**Unbaselined value, resolved.** After the run, `payout_decisions` showed 2 rows for #6/#7. A had not baselined that
table, so the rows' own `decided_at` was read:
- #6: 2026-08-04 03:00:03Z, `manual_review {PAYOUT_TRANSFER_FAILED}`, by `edge:enforce-transfer-expiry`;
- #7: 2026-08-04 03:27:40Z, `manual_review {BUYER_CONFIRMED,PAYOUT_TRANSFER_FAILED}`, by `edge:confirm-and-release`.

Both predate the run by two months and come from the August payout incident. An after-payout flag from R3 would read
`REFUNDED_AFTER_PAYOUT`. The R3 files' in-transaction postcondition also asserted these rows unchanged.
- Not a mismatch. The lesson: baseline every table a postcondition watches.

**Consequences, now in force:**
- 150's rollback guard (`payment_refund_state` rows = 0) no longer holds.
- The log and ledger rows are permanent.
- `stripe_refund_id` and `amount_refunded_cents` on #6/#7 are set-once / non-decreasing.

**Next detector run after execution (16:35:00Z), as predicted:**
- `refunds` succeeded `{opened 0, scanned 2, resolved 0}`. The scan count is unchanged: a succeeded state row is
  selected by neither gated branch, so this run is **not** evidence that detection works
  (F-DETECT-REFUNDS-UNOBSERVABLE-1).
- `reconciliation` and `release_stuck` succeeded, each opening 0.
- `refund_resolution` was skipped (`refund_resolution_disabled`).

**Cases at 16:35:27Z:** 21 in total (unchanged); 2 open refund cases (the pre-existing ones); 0 on either refund id;
0 created since the run began.

**Outcome: EXECUTED. Every prediction held; no stop condition was met; nothing was retried.**

## D's witness: CONFIRMED (D `1046b78e`, `D_WITNESS_R3_EXECUTION_20261011.md`)

D's own reads confirm all four checks:
- **(a)** Both rows changed as predicted. `refunded_at` is unchanged to the millisecond (17:20:05.165 / 17:20:19.353).
  There are exactly 2 state, 2 log and 2 ledger rows, all succeeded/dashboard/reconcile with `stripe_dispute_id` NULL.
  Transfers are still reversed, with no payout.
- **(b)** The excluded five are untouched: 0 state rows each, and the 2/2/2 totals are fully accounted for by #6 and
  #7.
- **(c)** The 16:35:00Z run: `refunds` scanned 2 and opened 0; `refund_resolution` was skipped; 0 cases today.
- **(d)** The `payout_decisions` dates are 2026-08-04 03:00:03Z and 03:27:40Z. This independently closes the one item
  neither A nor D had baselined.

**D's stated limit:** D has no independent immediately-before prestate for **#6**.
- D's corrected read landed after #6 was written. D's nearest independent prestate for #6 is its verdict-stage read
  of 2026-10-10. The file's atomic prestate guards are the structural backstop.
- **#7** has a clean independent prestate, taken minutes before its run.

**Detection, restated so it cannot be misread:** `items_scanned` is still 2 with two real succeeded state rows present
(2 across 288 runs before detection was enabled, 2 across 255 after, 2 now). Completing O-R4 demonstrates
**nothing** about refund-state detection (F-DETECT-REFUNDS-UNOBSERVABLE-1). "Reconciliation done, detector clean" is
not validation.

**Observation, pre-existing and out of scope (D):** four of the excluded five carry a `stripe_refund_id` while
`amount_refunded_cents` is NULL. `record_payment_refund` sets both, so an earlier path or a backfill set the id alone.
There is no baseline for that column on those rows, so it is stated as pre-existing, not as unchanged. It is worth
someone's attention eventually; nothing here touched it.
