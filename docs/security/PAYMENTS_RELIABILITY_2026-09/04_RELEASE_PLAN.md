# Release plan — payments reliability packages 1–3 (NOT DEPLOYED; owner approval required)

Everything below is a proposal. No production migration has been applied, no edge function deployed, no data or setting
changed. Per `AGENTS.md`/`DEPLOYMENT_PATHS.md`, every migration-bearing PR needs `AUTODEPLOY-VERIFIED-OFF: <date>` in its
description and an explicit owner-authorized apply; money changes need a reviewer other than the author and a
rollback script written before applying (all three rollbacks exist under `supabase/rollbacks/`).

## 0. Release dependency (blocker until resolved)

Production edge code is ahead of `main` for `create-payment-intent`, `confirm-and-release` (Phase-2 deletion guards)
and `delete-account` (OR-17 tombstone flow), and production carries migrations `076`–`109` + `20260902003623` that
`main` lacks (`00_BASELINE.md`). Deploying these packages from `main` would silently drop those guards and replace the
tombstone deletion with the physical-delete handler. **Either** merge the Phase-2 branch (`feature/venue-native-and-
product-v2`) to `main` first and forward-port these packages onto it (expected to be mechanical: the deletion guards
are additive blocks; the deployed `delete-account` should keep its tombstone flow and call
`account_deletion_blockers` from `kernel.sweep_deletion_pending`'s blocker chain), **or** forward-port now and deploy
from that branch. Owner decision; not made here.

## 1. Deployment order (per package, expand → verify → contract)

Packages are stacked and independent at the migration level (versions sort 1 → 2 → 3); edge functions must never
run ahead of the migration they call.

| Step | What | Type | Approval |
|---|---|---|---|
| P1-a | apply `20260906100000_checkout_reservation_authority.sql` (manual SQL editor or `supabase db push` by the owner) | PRODUCTION DB MUTATION | owner |
| P1-b | verify (queries §4) | read-only | — |
| P1-c | deploy `create-payment-intent` (with the Phase-2 guard block preserved) | EDGE DEPLOY | owner |
| P2-a | apply `20260906110000_settle_verified_payment.sql` | PRODUCTION DB MUTATION | owner |
| P2-b | verify §4 | read-only | — |
| P2-c | **(collapsed into P3-d)** — the integrated `stripe-webhook`, `confirm-payment` and `enforce-transfer-expiry` sources read `payments.amount_refunded_cents` and call the Package 3 payout RPCs, so they must not be deployed before P3-b. Only `create-payment-intent` (P1-c) is deployable between migrations. | — | — |
| P2-d | add `payment_intent.canceled` to the Stripe webhook endpoint's event list | STRIPE DASHBOARD SETTING | owner |
| P3-a | pre-flight `SELECT stripe_transfer_id, count(*) FROM transfers WHERE stripe_transfer_id IS NOT NULL GROUP BY 1 HAVING count(*) > 1` must be empty (the migration also aborts on duplicates) | read-only | — |
| P3-b | apply `20260906120000_payout_attempts_and_refund_monotonic.sql` | PRODUCTION DB MUTATION | owner |
| P3-b2 | apply `20260906130000_deletion_sweep_live_rail_obligations.sql` (BP-13 arm; requires 078 + 120000 — both asserted by the file) | PRODUCTION DB MUTATION | owner |
| P3-b3 | **legacy orphan reconciliation** (R3 §2.2): `SELECT id, seller_id, status FROM transfers WHERE status IN ('buyer_confirmed','auto_released') AND stripe_transfer_id IS NULL;` — for each row list the seller's Stripe transfers (`stripe transfers list --destination acct_… --limit 100`) and match `metadata.transfer_id`; where a `tr_` exists, `SELECT record_transfer_payout(<id>, '<tr_>')`. The new edges ALSO run this check before every first POST (legacy-aware pre-flight), so this step is belt-and-braces, not the only defence | read-only + owner SQL | owner |
| P3-c | verify §4 | read-only | — |
| P3-c2 | **pause the payout cron** (`cron.unschedule` of the enforce-transfer-expiry job) for the duration of P3-d so the old sweep and the new edges never run in the same window (R2 NOTE-7); re-schedule after P3-d | PRODUCTION CRON SETTING | owner |
| P3-d | deploy (in the R6 order of 13 §3, not as one step) `confirm-payment`, `confirm-and-release`, `enforce-transfer-expiry`, `stripe-webhook`, `delete-account` (tombstone variant + blockers) — one step, after all three migrations | EDGE DEPLOY | owner |
| P3-e | update `docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md` Part 2 to `reconcile_payout_attempt` / `record_payout_attempt_result`; manual dashboard transfers are no longer a supported path | docs | — |

Old edge versions keep working after each migration (`record_transfer_payout`, `mark_listing_sold`, `ensure_transfer_exists`
signatures unchanged), so a migration can be applied before its edge deploy; the reverse is not safe for P2/P3 edges.
The safe order is therefore (R6, `13_MIXED_VERSION_DEPLOY.md` §3): P1-a → P1-c → P2-a → P3-a/b/b2/b3 → delete-account →
confirm-payment → stripe-webhook → PAUSE cron + Q1–Q15 triage → enforce-transfer-expiry → confirm-and-release → one manual
sweep → RESUME cron → P2-d → pending-intent backfill. The six edges are NOT deployed "in one step": the order above is what
keeps every intermediate state money-safe; the 23-step stop/resume checklist is `rc/R6_mixed_version_deploy_review.md` §5.
**Source of the deploy**: the converged branch `release/payments-converged-rc` (= PR #54 head after fast-forward), never the
original main-only branch — the edges there would regress the deployed Phase-2 deletion guards and tombstone flow
(`09_CONVERGENCE.md` §1). `supabase db push --linked --include-all` from that checkout plans exactly the four `20260906*`
versions because the checkout's ledger set equals production's plus those four (rehearsed: `payments_rc_prod_order_rehearsal.sh` A1). Between P2-a and P3-d the old webhook keeps
settling through `mark_listing_sold` (now payment-gated by P1) — no window in which a paid listing is unsettleable.

## 2. Client compatibility

- **Mobile build 13 (current binary)** and every 1.0 build: `reserve_buy_now(…, p_minutes)` still accepted (window is
  now server-fixed 10 min); `confirm-payment` → `mark_listing_sold`/`complete_auction_payment` → `ensure_transfer_exists`
  keeps working: the wrappers find the confirmed payment and the core returns `already_settled`. New refusal strings
  match `src/lib/payments.ts` regexes; other new strings surface through the existing generic alert. Response keys are
  supersets. `payout_status: 'processing'` is additive (old builds read `success: true`).
- **Web**: `finalizePurchase` reads `stripe_verified` (kept); `outcome`/`transfer_id` are additive; web still does not send
  `expected_total_cents` (unchanged, optional improvement).
- **Minimum client**: none required. Rollout dependency documented: none.

## 3. Rollback (rewritten 2026-09-06 — see `14_ROLLBACK_RECOVERY.md`)

Rollback is a supported path ONLY before the first new-code money fact (before the sweep / confirm-and-release deploy).
After that, prefer forward-fix (14 §4). Every rollback script is one transaction (`psql -1 -f …`), refuses while its
D-detectors are non-zero (D1 open attempts, D2 partial refund + unpaid transfer, D3 unresolved review rows, D4
paid-unsettled, D5 reversal obligations, D6 BP-13-only identities, D7 mid-flight deletions, D8 inconsistent refund facts,
O1/O2 ordering), and the 120000 rollback archives every fact it destroys into `rollback_archive`; re-apply restores it
and reports window payouts. Order: 130000 → 120000 → 110000 → 100000. Drain first by settlement (reconcile, refund,
reverse, resolve, withdraw) — never by editing state. Override only with a ticket: `set_config('app.rollback_force','on',true)`.

| Package | Rollback file | Gates | Data |
|---|---|---|---|
| 130000 | `20260906130000_…_rollback.sql` | D6 | none destroyed (sweep body → 078 verbatim) |
| 120000 | `20260906120000_…_rollback.sql` | O2, D1, D2, D3, D5, D7, D8 | ledgers + refund facts ARCHIVED, restored on re-apply |
| 110000 | `20260906110000_…_rollback.sql` | D3, D4 | review rows survive; sweep gone until re-apply |
| 100000 | `20260906100000_…_rollback.sql` | O1 | reservations keep their rows; F03/F04 reopen |

## 4. Read-only post-apply verification queries (run by the owner; paste output)

```sql
-- P1
select p.proname, has_function_privilege('authenticated',p.oid,'EXECUTE') a, has_function_privilege('service_role',p.oid,'EXECUTE') s, has_function_privilege('anon',p.oid,'EXECUTE') n
  from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public'
   and p.proname in ('settle_listing_for_payment','mark_listing_sold','complete_auction_payment','reserve_buy_now') order by 1;
-- expected: core a=f s=f n=f; wrappers a=t s=t n=f
-- P2
select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('settle_verified_payment','get_unsettled_payments');
select count(*) from public.payments p join public.listings l on l.id=p.listing_id where p.status='succeeded' and l.status<>'sold';  -- paid-but-unsettled backlog (expect small; Phase 0 drains it)
select count(*) from public.webhook_retries where resolved=false;                                                               -- review queue
-- P3
select relname, relrowsecurity from pg_class where relname in ('payout_attempts','payment_refunds','account_deletions');        -- all t
select indexname from pg_indexes where tablename='transfers' and indexname='transfers_stripe_transfer_id_uniq';
select tgname from pg_trigger where tgname in ('trg_guard_payment_transitions','trg_guard_payout_attempt_columns') ;
select state, count(*) from public.payout_attempts group by 1;                                                                  -- expect empty right after apply
-- Gate-2 census (compare with CI: 30 / 83 / 37 / 28 on a main-only replay; production also carries Phase-2 objects — compare deltas, not absolutes)
```

## 5. Post-deploy observation (first 24h, read-only)

- `webhook_retries` unresolved rows by `error_message` prefix (`unknown_payment`, `binding_mismatch`, `unfulfillable`).
- `payout_attempts` in `unknown`/`reversal_required`; `payout_decisions` with the new reason codes.
- Stripe: any `payment_intent.canceled` deliveries acknowledged 200; no 500 loops older than one hour in
  `get_incomplete_webhook_events()`.
- Edge logs: `checkout-refused` reasons, `settle` outcomes, Phase 0 counts.


## 6. Open follow-ups (not blockers for this release; recorded from review round 2)

- R2 MINOR-6: captures that succeed more than 2 h after PaymentIntent creation with a lost webhook are not in the
  `pending_stale` window; they are settled when the buyer's app calls `confirm-payment`, and they block deletion via
  `pending_payment` (24 h) — a widened window plus Stripe-side cancellation of abandoned intents is a follow-up.
- R2 NOTE-8: `binding_mismatch` / `unknown_payment` review rows are ops-visible (`webhook_retries`) but raise no alert;
  add a Sentry `captureMessage` or a daily digest.
- R2 NOTE-9: a `reversal_required` attempt whose dispute is later WON keeps its decision open until an operator records
  a `release` decision or the transfer is reversed.
- CI: run the rollback scripts in the `db` job (R3 §4); today they are release-time rehearsals only.
- `stripe_connect_archive.profile_id` FK relaxation (archived sellers cannot be erased) — separate migration.
