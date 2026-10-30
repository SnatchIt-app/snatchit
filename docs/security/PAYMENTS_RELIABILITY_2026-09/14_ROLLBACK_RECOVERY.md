# Rollback and recovery — archive, gates, the point of no return, and forward-fix

Source: independent review `rc/R5_rollback_recovery_review.md` (partial-refund overpay, in-flight re-POST and tombstone
regressions proved on rehearsal DBs), integrated by the lead as code: every rollback script now carries **pre-rollback
gates**, the 120000 rollback **archives** every new-code fact in its own transaction, and the forward migration
**restores** the archive and reports the window. Rehearsed end to end in `scripts/release/payments_rc_prod_order_rehearsal.sh` §F.

## 1. What the review proved (and what would have happened without the fix)

| Hazard | Mechanism | Fix |
|---|---|---|
| Partial refund → full-net payout | Old edges read only `payments.status`; after rollback the refund fact (`amount_refunded_cents`, `payment_refunds`) was gone; a 2 500-refunded `buyer_confirmed` order was paid 9 000 (proved). No 039 hold stops it. | Gate D2 refuses the rollback while any partially refunded order has an unpaid transfer; the fact is archived and restored |
| In-flight attempt → second transfer | Dropping `payout_attempts` erases the lease and key; the old sweep re-POSTs under a different key | Gate D1 refuses while any attempt is open; drain by reconciling against Stripe (`metadata.transfer_id`) |
| BP-13-only identity → tombstoned | Removing the BP-13 arm tombstones an identity that still owes/awaits money (proved `ERASED`) | Gate D6 on the 130000 rollback |
| Unfulfillable captures orphaned | `webhook_retries` review rows survive but no old code reads them → charged buyer never refunded | Gates D3 (120000, 110000) |
| Paid-unsettled re-listed | 000 `cleanup_expired_reservations` re-lists a paid listing; payer then refused by 0590 | Gate D4 on the 110000 rollback |
| Out-of-order rollbacks | 100000 before 110000 → every webhook 500s at runtime; 120000 before 130000 → sweep fails closed | Gates O1 / O2 |
| Half-applied rollback | 100000/110000/130000 ran autocommit | All four wrapped in one transaction; run with `psql -1` |
| Duplicate `tr_` in the window | unique index gone; re-apply aborts | Rehearsed: abort is clean; operator resolves, re-apply restores |

Override exists for a ticketed decision only: `select set_config('app.rollback_force','on',true)` in the same session.

## 2. The archive (`rollback_archive`, created by the 120000 rollback inside its transaction)

`payments_refund_facts` (every payment's status/refund columns), `payout_attempts`, `payment_refunds`,
`account_deletions`, `payout_decisions_new`, `webhook_retries_review`, `transfers_money` and `listings_reservation`
baselines, `identity_bp13`, and a `manifest` (counts, operator, `restored_at`). Anon/authenticated have no access. A
second rollback refuses while an unrestored archive exists.

Restore (forward migration §9, on re-apply): ledgers re-inserted on common columns with `ON CONFLICT DO NOTHING`;
`amount_refunded_cents` restored only where the current value is NULL (never overwrites a newer fact); **C1** row counts
must match or the migration aborts; **C2** ledger sum = column is checked (warning); **C4** transfers paid by OLD code
in the window (a `tr_` with no attempt row) are listed in a warning for reconciliation against Stripe; manifest stamped.
Rehearsed: F13–F16 (restore, C1, C2, C4 report, `ALREADY_RELEASED` on the window payout).

Cannot be restored by anyone but Stripe: whether an in-flight POST created a transfer (hence gate D1), the frozen
params of window payouts, a refund id the old webhook wrote over, tombstoned identities, listings re-sold in the window.

## 3. Before money-moving workers resume after a recovery

All must hold (queries in R5 §3/§4 and in the restore block): C1 counts equal; C2 no ledger/column mismatch;
`payout_attempts` has no `unknown` older than 10 min; C4 list empty or every listed transfer matched to a Stripe
transfer by `metadata.transfer_id`; duplicate `tr_` query empty; Q6 = 0. Only then `cron.schedule` and redeploy
`confirm-and-release`.

## 4. The point at which rollback becomes unsafe — and forward-fix

**Data-safe rollback exists only before the first NEW-code money fact** — in the release order, before step D4/D5
(first payout attempt or refund through the new webhook). After that, rollback is possible only while every detector
D1–D8 is zero with the cron paused and edges frozen; the gates enforce it. In practice the first live attempt or refund
ends the rollback era; from then on:

| Failure class | Rollback | Forward-fix | Recommendation |
|---|---|---|---|
| Bad edge | redeploy previous version — fine for create-payment-intent / delete-account; reopens D2 overpay and the §2 pair for confirm-and-release / expiry; loses partial facts for the webhook | fix the edge | **Forward-fix**; edge-revert only for the two safe edges |
| Bad RPC logic | drops ledgers to fix a body | `CREATE OR REPLACE` body-only hotfix migration (+ its rollback = previous body); `REVOKE EXECUTE` first if money-moving | **Forward-fix** |
| Bad schema (guard/index too strict) | package rollback | disable the one trigger / drop the one index, keep column and ledgers | **Forward-fix (surgical)** |
| Data corruption | destroys the ledger needed to diagnose | freeze workers; correct with the bypass GUCs + an audit row | **Never rollback** |
