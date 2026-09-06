# Draft pull requests (stacked; review-ready branches — NOT to be merged or deployed without owner approval)

The reviewable unit is the integrated branch `fix/payments-reliability` (lead tooling + CI gates + docs + the three
packages with their review-round revisions merged). One draft PR is opened from it against `main` (link below); the
package branches remain available for per-package review but are NOT independently deployable — the integrated edge
sources depend on all three migrations (04 §1). The PR is migration-bearing:
per `AGENTS.md` / `DEPLOYMENT_PATHS.md` it must carry `AUTODEPLOY-VERIFIED-OFF: <date>` (an owner statement that the
Supabase deploy-on-merge integration is off, confirmed visually in the dashboard) before it may merge to `main`, and
the migration is applied only by an owner-authorized path afterwards. Reviewer must not be the author. Merging never
implies applying.

Release dependency for all three: production edge code is ahead of `main` (Phase-2 deletion guards; tombstone
`delete-account`). See `04_RELEASE_PLAN.md` §0 — the owner must decide the branch convergence before any deploy.

---

## PR-1 — Package 1: checkout authorization and reservation lifecycle

**Branch:** `fix/payments-p1-checkout-authz` (or the integrated `fix/payments-reliability` range 35cbdf6..39e8920)

**What.** Migration `20260906100000_checkout_reservation_authority.sql`: `settle_listing_for_payment(uuid)` (zero-grant
listing-settlement core), `mark_listing_sold`/`complete_auction_payment` require the caller's bound `succeeded` payment
and delegate to the core, `reserve_buy_now` becomes server-owned (10-minute window, holder keeps window, one live hold
per buyer, rate-limited, refuses listings holding a succeeded payment; fixed lock order). `create-payment-intent` binds
the intent to the live holder / entitled winner, refuses stale/foreign requests, retires stale pending intents (cancel
at Stripe, row → failed), cancels other buyers' pending intents when minting, and re-mints on amount/currency mismatch.

**Why.** Audit F01/F03/F04 (+ N3/N4): a buyer could obtain a chargeable intent for another buyer's reservation; sale RPCs
needed no payment; reservation duration was client-chosen. Invariants 1, 2, 3, 14.

**Verification evidence.** pgTAP `120_reservation_lifecycle.sql` 58/58 (red before: 8/49 with 36 psql errors);
`110_money_authz_matrix.sql` 18/18; vitest `tests/checkout-intent.test.ts` 23/23 (red before: 11 failed); rollback
restores the 0590 bodies verbatim (diff empty); fresh replay + reapply md5-identical; independent review round 1 →
REQUEST CHANGES → all five findings fixed in rev 2 (reviews/P1_review_round1.md). CI run on the integrated branch:
34046189039 all jobs green.

**Rollback.** `supabase/rollbacks/20260906100000_checkout_reservation_authority_rollback.sql`; redeploy previous
`create-payment-intent`.

**Blast radius.** Checkout entry (`reserve_buy_now`, `create-payment-intent`) and the sale wrappers. Client
compatibility: build 13 and web unchanged (see 04 §2). Gate-2 (whole branch): 30 / 84 / 37 / 30.

**Migration fields.** Rollback path above · verification query 04 §4 (P1) · failure behavior: the migration is a
single transaction of CREATE OR REPLACE statements; a failure leaves the prior bodies · owner approval point: apply.

`AUTODEPLOY-VERIFIED-OFF: <owner fills in>`

---

## PR-2 — Package 2: reliable settlement

**Branch:** `fix/payments-p2-settlement` + `fix/payments-p2-rev2` (integrated range fbf8313..a22c8e3 + rev 2)

**What.** Migration `20260906110000_settle_verified_payment.sql`: `settle_verified_payment(...)` (the one verified
settlement contract: binding, refund monotonicity, promotion, listing settlement via the core, transfer creation,
review rows in `webhook_retries` for non-settling outcomes), `get_unsettled_payments(int)`, `cleanup_expired_reservations`
never re-lists a paid listing. `stripe-webhook` `payment_intent.succeeded` collapses to one contract call (terminal
outcomes 200, RPC error 500 → retry resumes from state); `payment_failed`/new `payment_intent.canceled` release the
hold with a refunded-safe predicate. `confirm-payment` verifies ownership and settles through the contract (no direct
writes). `enforce-transfer-expiry` gains Phase 0: reconciles paid-but-unsettled rows against Stripe and compensates
unfulfillable captures with a deterministic refund key.

**Why.** Audit F02/F05 (writer half)/F06 (ack semantics) + N1/N2. Invariants 4–9.

**Verification evidence.** pgTAP `121_settlement.sql` 89/89 after rev 2 (red: 0/75 before P2; 10 not ok before rev 2);
vitest settlement-webhook / settlement-confirm / settlement-sweep (red: 24 failed before P2, 8 before rev 2) incl. the
audit's F02 reproduction turned green;
rollback restores `cleanup_expired_reservations` verbatim; independent review round 1 → APPROVE WITH CHANGES →
MAJOR-1 (partial refunds) and minors fixed in rev 2 (reviews/P2_review_round1.md).

**Rollback.** `supabase/rollbacks/20260906110000_settle_verified_payment_rollback.sql`; redeploy previous
stripe-webhook / confirm-payment / enforce-transfer-expiry.

**Blast radius.** Every successful charge's settlement path; the cron sweep now issues refunds for unfulfillable
captures (idempotent). Stripe endpoint must add `payment_intent.canceled`. Deploy-order: Phase 0's refund recording
prefers Package 3's `record_payment_refund` and falls back safely.

`AUTODEPLOY-VERIFIED-OFF: <owner fills in>`

---

## PR-3 — Package 3: refund monotonicity, payout attempt ledger, account-deletion gate

**Branch:** `fix/payments-p3-payout-integrity` + `fix/payments-p3-rev2`

**What.** Migration `20260906120000_payout_attempts_and_refund_monotonic.sql`: `payout_attempts` (immutable request
params, per-attempt idempotency key, one open / one succeeded per transfer, append-only), partial UNIQUE on
`transfers.stripe_transfer_id` (duplicate pre-flight aborts safely), `guard_payment_transitions` (refunded terminal;
money columns immutable once succeeded), `payment_refunds` + `payments.amount_refunded_cents` + `record_payment_refund`,
payout RPCs (`claim_payout_attempt`, `mark_payout_requested`, `record_payout_attempt_result`, `reconcile_payout_attempt`,
`flag_payout_reversal_required`), `account_deletion_blockers`, `account_deletions`. Edges: confirm-and-release and the
payout sweep run the attempt protocol (reconcile-before-POST, transfer_group + attempt metadata, transfer always
recorded); webhook refund/dispute/transfer branches record facts through the ledger and return non-2xx on DB failure;
delete-account fails closed on blockers/lookup errors and is restartable.

**Why.** Audit F05 (DB half)/F06 (branches)/F07/F08/F10 + F15 (partial). Invariants 8, 10, 11, 12, 13.

**Verification evidence.** pgTAP 122 60/60, 123 51/51, 124 40/40 after rev 2 (053/024 before), 060 12/12 (its two
TODO markers are now real assertions — the masking ratchets moved to 0); vitest payout-attempts, delete-account,
refund-dispute-webhook, payout-races (now against the real `payouts.ts`); independent review round 1 → APPROVE WITH CHANGES →
MAJOR-1/2 (deletion gate coverage) and minors fixed in rev 2 (reviews/P3_review_round1.md).

**Rollback.** `supabase/rollbacks/20260906120000_payout_attempts_and_refund_monotonic_rollback.sql` (drops the ledger
tables — export first if rows exist); redeploy previous edges. Old edges keep working against the new schema
(`record_transfer_payout` untouched).

**Blast radius.** Every payout and refund; account deletion. Ops: `DAY5_MANUAL_REFUND_PLAYBOOK.md` Part 2 must switch to
the attempt RPCs; a pre-enable query for legacy transfers with `stripe_transfer_id IS NULL` + `PAYOUT_TRANSFER_FAILED`.
Follow-up migration needed: relax `stripe_connect_archive.profile_id` FK so archived users can be deleted.

`AUTODEPLOY-VERIFIED-OFF: <owner fills in>`

---

## Integrated draft PR

Branch `fix/payments-reliability` → `main`. Final local evidence: `05_VERIFICATION.md` §1 (rollback rehearsal, final run)
and §4 (whole-branch table). CI on the final push: run id recorded below once green. The `AUTODEPLOY-VERIFIED-OFF` line in
the PR body is left as a placeholder on purpose — the migrations guard is expected to FAIL until the owner confirms the
Supabase deploy-on-merge integration is off in the dashboard and fills in the date. Merging never implies applying; the
apply/deploy order is `04_RELEASE_PLAN.md` §1.
