# Package 3 rev2 — report (worktree `/Users/josetascon/snatchit-pay-p3r`, branch `fix/payments-p3-rev2`)

**Commits (local only, not pushed):** `f699b52` tests (red) → `3f2dc02` fix. Base `7798f5d`. Package 2 files untouched.

## Per-finding (M = `supabase/migrations/20260906120000_payout_attempts_and_refund_monotonic.sql`)
| Finding | Change | Test |
|---|---|---|
| MAJOR-1 | M:883-899 — `pending_payment` keeps the 24h bound only when no unresolved `webhook_retries` row exists; new kind `unresolved_review` (join payments, buyer or seller) | 124:40-55 (A1: 3-day-old pending + review row blocks buyer+seller; resolved ⇒ clean) |
| MAJOR-2 | M:912-927 — `open_manual_review` drops `payout_released_at IS NULL`; blocks while `t.status <> 'reversed'` and no later `release` decision; party from transfers so `attempt_id NULL` rows count | 124:104-150 (A2: legacy `record_transfer_payout` + `dispute_lost` + `flag_payout_reversal_required` ⇒ only blocker is `open_manual_review`; later release ⇒ clear; new review ⇒ blocks; `mark_transfer_reversed` ⇒ clear) |
| MINOR-1 | `delete-account/index.ts:205-224, 253-276` — gate + cleanup run on every attempt < done; `advance('cleaned')` only when phase < cleaned (ledger never regresses); header rewritten | `tests/delete-account.test.ts:113-152` (4 cases: cleaned re-runs both; cleaned + gate error ⇒ 503; storage + new obligation ⇒ 409, no cleanup; storage clean ⇒ `['done']`) |
| MINOR-2 | M:675-685 — `record_payout_attempt_result` reads `transfer_id` unlocked (immutable by guard), locks `transfers`, then the attempt. `flag_…` already locked transfers first (717→725); `reconcile_…` delegates | 122:190-208 (A6: source-order assertion on claim/record/flag; two-session probe not possible without dblink — documented in the test) |
| MINOR-3 | M:258-280 `payout_attempts_no_delete()` + `BEFORE DELETE` (row) + `BEFORE TRUNCATE` (statement); REVOKE M:961; rollback :33-34,:50; manifest `supabase/ci/assert_public_table_grant_decisions.sql:381` | 122:211-227 (A3: DELETE and TRUNCATE raise as `service_role`, row count unchanged) |
| MINOR-5 | `stripe-webhook/index.ts:728-748` — `ATTEMPT_NOT_FOUND` ⇒ insert `webhook_retries` (`rpc_name 'transfer.created'`, `error_message 'ATTEMPT_NOT_FOUND:<attempt>:<tr>'`) then `finish(true)`; insert failure ⇒ `finish(false)` | `tests/refund-dispute-webhook.test.ts:183-201` (A4 both branches) |
| MINOR-4 / NOTE-3 | M:107-141 — pre-enable ops query (live transfers, `stripe_transfer_id IS NULL`, `PAYOUT_TRANSFER_FAILED`) plus a second query listing already-paid transfers with un-superseded `manual_review` rows (they now block deletion); NOTE-3 FK follow-up recorded | — |

Header also updated: review round-1 change log (M:81-105), counts 12 functions / 6 triggers, Gate-2 delta note, `account_deletions` table comment (M:948-951).

## Red → green
- pgTAP RED (pre-fix DB): 122 `plan=60 ok=55 not_ok=5` (A6 record order, A3 ×4); 124 `plan=40 ok=34 not_ok=6` (A1 ×3, A2 ×3). vitest RED: 5 failed / 22 passed (4 delete-account retry cases, A4 ack).
- GREEN: 122 60/60, 123 51/51, 124 40/40; vitest 227/227 (13 files).

## Suite totals
- `scripts/rehearsal_reset.sh snatchit_p3r_rehearsal`: `REPLAY OK: 92/92`; `GATE-2 tables=30 functions=84 policies=37 triggers=30`.
- `scripts/rehearsal_test.sh snatchit_p3r_rehearsal`: `TOTAL plan=583 ok=581 not_ok=2` — only `132_replay_parity` D-5/8,9; harness: "pgTAP suite matches the expected local baseline".
- Rollback→reapply probe: fresh verification `3|12|6|1|1` → rollback `0|0|0|0|0` → reapply `3|12|6|1|1`; `md5(prosrc)` of the 12 functions fresh vs reapply: **equal** (diff empty). 122/123/124 re-run after reapply: 151/151.
- `assert_public_table_grant_decisions.sql` against the DB (pgtap dropped first): "every recorded function posture matches the catalog"; `expected_grants.txt` P3 tables match (no new tables).
- `npx vitest run`: 227 passed. `npm run typecheck`: clean. `npm run lint`: 0 errors, 44 pre-existing warnings (all in `src/`).

## Disagreements / deviations
- None with the disposition. Two additions beyond the letter: a `BEFORE TRUNCATE` trigger (service_role holds TRUNCATE; row triggers do not fire on it), and the second ops query for already-paid transfers with un-superseded reviews, because MAJOR-2 makes those block deletion retroactively.

## Open questions for the lead
1. **ci.yml Gate-2** must be bumped: `EXPECT_FUNCS 83→84`, `EXPECT_TRIGGERS 28→30` (I did not touch ci.yml).
2. MINOR-1 vitest cannot make `auth.admin.deleteUser` fail (`tests/helpers/edge-vm.ts:106` is hard-coded, not in my edit list); the "auth delete failed last time" case is modelled as a retry from recorded phase `storage`. Adding a `deleteUserError` knob to the helper would close that.
3. MINOR-5 records the stray transfer for review only; it does not try `metadata.transfer_id` → `record_transfer_payout`. Fine for a rollback-destroyed ledger, but say if you want the transfer row written when `transfer_id` is resolvable.
4. A6 is a source-order assertion, not a concurrency probe (no dblink/pg_background in the rehearsal stack).
