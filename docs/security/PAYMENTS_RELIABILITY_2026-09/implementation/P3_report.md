## Package 3 report — `fix/payments-p3-payout-integrity` (4 commits on `35cbdf6`, not pushed)

**Commits:** `333ba91` failing tests → `106dccd` migration+rollback+manifest → `63d898a` shared payouts modules → `403afa3` edges.

### Files changed (21)
- **New migration** `supabase/migrations/20260906120000_payout_attempts_and_refund_monotonic.sql` + `supabase/rollbacks/…_rollback.sql`
- **CI manifest** `supabase/ci/assert_public_table_grant_decisions.sql` (+3 tables no-client-access, +11 functions no-client-execute), `supabase/ci/expected_grants.txt` (+3 service_role lines)
- **pgTAP** new `122_payout_attempts.sql` (53), `123_payment_monotonic.sql` (51), `124_account_deletion.sql` (24); `060_payments_money.sql` F-2/F-3 `todo()` → real assertions (both now pass)
- **Shared** `_shared/payout-logic.ts` (key = `payout_<transfer>_a<n>`, `classifyPayoutPostFailure`), `_shared/payouts.ts` (`createSellerPayout` on the claimed attempt with `transfer_group`+`metadata[attempt_id]`, `findTransferByAttempt`, and `executePayoutAttempt` = the one claim→reconcile→pre-flight→mark→POST→record implementation used by both callers)
- **Edges** `confirm-and-release`, `enforce-transfer-expiry` (Phase 1/1b → `record_payment_refund`; Phase 2/2b → `executePayoutAttempt`; 2b now also sweeps expired-lease `payout_attempts`, including on disputed transfers), `stripe-webhook` (only the 5 owned branches + one `stripeFetchRaw` import), `delete-account` (gate + phase ledger)
- **Vitest** new `tests/payout-attempts.test.ts`, `tests/delete-account.test.ts`, `tests/refund-dispute-webhook.test.ts`; rewritten `tests/payout-races.test.ts` (now runs the REAL `payouts.ts`); updated `tests/payout-logic.test.ts`; **new helpers** `tests/helpers/payouts-vm.ts` (loads real `payouts.ts` into vm) and `tests/helpers/payout-protocol.ts` (Stripe mock with 24h key expiry + transfer_group; DB model of the new RPC predicates) — outside my named list, lead may fold into `edge-vm.ts`.

### Red → green evidence
- pgTAP before migration: `122 ok=1 not_ok=5 psql_err=57 · 123 ok=14 not_ok=23 psql_err=18 · 124 ok=0 not_ok=1 psql_err=32`. After: `122 53/53 · 123 51/51 · 124 24/24 · 060 12/12`.
- Vitest before edges: `Tests 27 failed | 142 passed (169)` (all 27 = handler suites: delete-account ×8, refund-dispute-webhook ×12, confirm-and-release ×5, sweep ×2). After: `8 files / 167 tests pass` for every Package-3 + pre-existing mobile suite.
- Scenarios proven: dispute between claim and record ⇒ `record_payout_attempt_result(tr_1,'succeeded')` called, row gets `tr_1`, attempt `reversal_required`, `PAID_DURING_DISPUTE` decision, exact RPC sequence `check_rate_limit, confirm_transfer_received, claim_payout_attempt, mark_payout_requested, record_payout_attempt_result`, no `profiles` read; lost response ⇒ `processing`, retry reconciles via `GET /transfers?transfer_group=` with POST count 1; >24h retry ⇒ 1 transfer; new attempt `_a2` only after `failed`; destination change ⇒ frozen `acct_A` reconciled; delete-account 503/409/phase order `gate→archived→cleaned→storage→done`, retry from `cleaned` never re-runs the gate; webhook DB failures ⇒ 500 + `fail_stripe_webhook_event`; unknown dispute close ⇒ upsert then handled.

### Rollback → reapply probe (local `snatchit_p3_rehearsal`)
rollback rc=0 → `tables=0 fns=0 idx=0 col=0` → suites RED (122/123/124/060 as above) → apply #1 rc=0 → apply #2 rc=0 → GREEN; md5 of the 11 function bodies identical fresh-replay vs rollback→reapply.

### Full-suite results
- `scripts/rehearsal_reset.sh snatchit_p3_rehearsal`: **REPLAY OK 90/90**; `GATE-2 tables=30 functions=80 policies=37 triggers=28` (baseline 27/69/37/24).
- `scripts/rehearsal_test.sh`: **TOTAL plan=427 ok=425 not_ok=2** (only 132 D-5/8,9 db-name artifacts). New baseline = 299+128. The script reports `REGRESSION 060: not_ok=0, expected 2` only because its `known_notok` still expects 060=2 — lead: set `060_payments_money.sql) echo 0`.
- Manifest run (pgtap dropped first): every table/function has a decision, postures match, known gaps unchanged (2). Grants diff vs `expected_grants.txt`: **MATCH**.
- `npm run typecheck`: clean. `npm run lint`: 0 errors / 44 pre-existing warnings (none in my files). `npx vitest run`: 168/170 — the 2 failures are in lead-owned `tests/edge-harness.test.ts` (loads stripe-webhook without providing the new `stripeFetchRaw` import); fix = `provide: { stripeFetchRaw }` in those two tests.

### Gate-2 delta (for ci.yml)
**tables +3** (payout_attempts, payment_refunds, account_deletions) · **functions +11** (claim_payout_attempt, mark_payout_requested, record_payout_attempt_result, reconcile_payout_attempt, flag_payout_reversal_required, record_payment_refund, account_deletion_blockers, guard_payout_attempt_columns, guard_payment_transitions, reset_payment_guard_bypass, payment_refunds_append_only) · **triggers +4** · **policies +0** → EXPECT 30/80/37/28 (CI's own baseline says funcs 70 → 81; verify on the real stack).

### Compatibility notes
- `record_transfer_payout` untouched: deployed v34/v36 edges keep working in either deploy order; they just write no attempt rows. New edges require the migration first (PGRST202 otherwise).
- Payments guard vs writers (all proven in 123): webhook succeeded/failed claims, confirm-payment same-status no-op, create-payment-intent retire, Phase 1/1b refund, quarantine, `delete_account_cleanup` all live. `refunded→succeeded` RAISES by design (Package 2 must use `NOT IN ('succeeded','refunded')`; confirm-payment needs a status predicate). Defined machine: pending→processing|succeeded|failed|refunded; processing→succeeded|failed|refunded; failed→pending|succeeded|refunded; succeeded→refunded; refunded terminal.
- Claim requires `payments.stripe_livemode = true`; NULL/false rows surface as `PAYMENT_NOT_LIVE` → manual review.
- Guard honours `app.bypass_transfer_guard` for the sentinel-only party rewrite so 0563's `delete_account_cleanup` body is untouched (documented in header).
- Ops: DAY5 Part 2 Step 3 (direct `UPDATE transfers SET payout_released_at…`) is blocked since 0562; and a manual dashboard transfer into a transfer_group now shows up as `PAYOUT_UNMATCHED_TRANSFER` review (attempt stays open) — playbook must switch to `reconcile_payout_attempt(<attempt>, 'tr_…')` / `record_payout_attempt_result`, and reversal cases to `flag_payout_reversal_required`.
- New reason codes: `PAID_DURING_DISPUTE`, `DUPLICATE_TRANSFER`, `DISPUTE_LOST_AFTER_PAYOUT`, `PAYOUT_UNMATCHED_TRANSFER`, `SELLER_NOT_ONBOARDED`, `PAYMENT_NOT_LIVE`.

### Not done / deviations
- **`stripe_connect_archive` not written on deletion**: its `profile_id NOT NULL REFERENCES profiles(id)` (no ON DELETE) would make the `auth.users→profiles` cascade fail and block every deletion. Connect id is preserved on `account_deletions.connect_id` instead (phase `archived`). Changing that FK is a destructive-class change — lead decision.
- Added `flag_payout_reversal_required(uuid,text,jsonb)` beyond the spec list (atomic attempt flag + decision insert for dispute-lost-after-payout).
- `source_charge_id` is never frozen at claim (no `payments.stripe_charge_id`); pre-flight discovers it and refuses a mismatch if one is ever supplied.
- No `deno check` on the edges (would fetch remote modules); syntax/behaviour is proven by the vm loader executing all four handlers.
- Migration-bearing branch: `AUTODEPLOY-VERIFIED-OFF` still required before any merge.

### Open questions for the lead
1. FK on `stripe_connect_archive` — accept ledger-only archive, or ship an FK relaxation in a later migration?
2. `scripts/rehearsal_test.sh` known_notok for 060 → 0, and `tests/edge-harness.test.ts` `provide: { stripeFetchRaw }` — both lead-owned.
3. `refunded` reachable from `failed` (charge captured but our row lagged) — confirm Package 2's settlement contract agrees.
4. Client: `payout_status: 'processing'` is a new value for web/mobile renderers (older clients just see `success: true`).

## Lead disposition
1. stripe_connect_archive FK: ledger-only archive on account_deletions.connect_id accepted; FK relaxation recorded as a follow-up migration.
2. Lead fixes: rehearsal_test.sh known 060 delta -> 0; edge-harness smoke test provides stripeFetchRaw.
3. failed -> refunded accepted (consistent with Package 2).
4. payout_status "processing" is additive; old clients read success:true.
