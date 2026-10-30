# PHASE-2 PRODUCTION RUNBOOK — dark DB apply of migrations 076–092

**Status:** RELEASE-CANDIDATE RUNBOOK, authored at the 2026-09-02 release-readiness pass.
**This document authorizes nothing.** Execution requires a NEW explicit owner deployment
authorization naming the release train. Source tip it was written against:
`phase2/consolidation` @ the 092 merge `76bda03963d631c365b48aacc14a24e8ca3d1da6`
(+ the release-readiness PR). Project: `hqycwntpfoztoinemqns` (us-west-2, PG 17.6).

**Release model: OPTION A+C — apply all 17 migrations with every feature flag dark and
every operational integration unarmed.** Proven by the local production-order rehearsal
(`scripts/release/local_prod_order_rehearsal.sh`): 1 s wall-clock apply, ZERO live-row
mutation outside the two 078 sentinel identities, all 18 post-apply checks PASS, all 18
Phase-2 suites green on the production-order catalog. Option B (prefix apply) is
REJECTED: the train is a sealed dependency chain (SEAM bodies land in later packages;
084/089 adopt FKs across it) and the 077 release-train gate binds the deletion cutover
to the same train regardless of prefix. Option D does not hold: no P0 remains open
after this pass except the owner authorization itself.

## The train (what ships together — the 077 release-train gate's artifact set)

1. **DB:** migrations 076–092 (17 files; bytes immutable since their merges).
2. **Edge:** `delete-account` (the OR-17 cutover body — retires physical delete),
   `create-payment-intent` (F-5 guard), `confirm-and-release` (F-5 guard). All three
   already authored and merged; deploy order below. `send-push`/`stripe-webhook`/etc.
   are NOT redeployed (unchanged).
3. **API config:** PostgREST exposed schemas += `kernel` (Dashboard → Settings → API →
   "Exposed schemas"). Required by the deletion cutover (the edge calls
   `kernel.request_account_deletion` through PostgREST) and by the RN own-row
   deletion-state reads. `catalog`/`venue`/`market`/`notify` are NOT exposed on this
   train — they ride their rails' activation.
4. **Mobile (RN) cells riding the next app build** (do NOT block the DB apply; the DB
   sweep's BP wall is the enforcement): the PlaceBidScreen F-5 guard (authored), the
   Settings withdraw-deletion UI (named cell, not yet authored — see the readiness
   report §Owner packets).
5. **NOT on the train:** any feature flag flip, any Vault secret, any new cron beyond
   what the migrations schedule, PR #28, email, Stripe changes, Wallet/resale/dispute/
   CRM/promoter activation, notify dispatch ticks, PostgREST exposure of the four
   other schemas.

## T-24H
- [ ] Owner deployment authorization recorded (naming this runbook + the train above).
- [ ] Confirm tip unchanged: `git rev-parse origin/phase2/consolidation` equals the
      authorized SHA; CI green on that exact head.
- [ ] Read Dashboard → Database → Backups: note plan tier, backup cadence, PITR
      window. Record the answer in the owner packet for `retention.backup_window_days`
      (do NOT set the key on this train; the reaper stays fail-closed on NULL).
- [ ] Run `scripts/release/phase2_preflight.sql` read-only against production
      (psql or the SQL editor). Require: zero FAIL. (2026-09-02 dry run: 21/21 PASS.)
- [ ] Local rehearsal re-run on the authorized tip:
      `scripts/release/local_prod_order_rehearsal.sh` → zero live-row mutation, verify
      all-PASS, suites green; `scripts/release/local_rollback_battery.sh` → 17× diff 0.

## T-1H
- [ ] Announce internally; freeze merges to `phase2/consolidation`.
- [ ] On-demand backup: Dashboard → Database → Backups → "Back up now" (or confirm the
      most recent scheduled backup is < 24 h old and PITR is healthy). Record its id.
- [ ] Re-run `phase2_preflight.sql`. Zero FAIL required.
- [ ] Verify Stripe webhook deliveries healthy over the last hour (no backlog) — the
      apply does not touch Stripe, but a pre-existing incident would confound triage.

## T-15M
- [ ] Re-run `phase2_preflight.sql` one final time. Zero FAIL.
- [ ] Confirm the three legacy cron jobs are the only jobs
      (`select jobname from cron.job` → 3 rows).
- [ ] Open two terminals: one for the apply, one running the watch queries (§Monitoring).
- [ ] No app pause is required (the apply touches no live-row data and locks only
      new objects + seconds-long DDL on `public.push_tokens`, 2 rows), but avoid the
      top-of-hour cron boundary: start the apply just AFTER an even minute so the
      */2 jobs are quiet.

## APPLY
```bash
# from the repo root at the authorized tip; requires the production DB URL with the
# postgres role. The chain is non-linear vs the timestamped ledger rows -> --include-all.
supabase db push --db-url "$PROD_DB_URL" --include-all
```
- Expected: exactly 17 migrations applied (076..092), wall clock well under 5 minutes
  (local rehearsal: ~1 s of SQL; network dominates). Each migration is one transaction:
  a failure aborts THAT file atomically — the injected-failure proofs show a clean
  prefix state; fix forward or stop (rollback decision tree §1).
- Lock notes (measured against current sizes, all tables ≤ 240 kB):
  * Only pre-existing object touched by DDL: `public.push_tokens` (092 — 4 ADD COLUMN
    nullable + 1 partial index; ACCESS EXCLUSIVE for milliseconds at 2 rows).
  * 078 writes exactly 2 sentinel rows into `auth.users`/`public.profiles` (idempotent).
  * Everything else creates new objects. No rewrite, no constraint validation over
    legacy rows, no backfill. Expected user-visible downtime: none.

## POST-APPLY +5M
- [ ] `scripts/release/phase2_postapply_verify.sql` → require: V1..V18 all PASS
      (V13 is the PFA-1 walled-schema ACL sweep — the release gate's standing
      production control; V8 proves all five flags dark; V9 proves the three
      owner-unset keys NULL; V10 proves the data plane empty).
- [ ] `select jobname, active from cron.job order by jobid` → 19 rows, all active.
- [ ] Spot legacy flows read-only: latest `public.payments` row unchanged; a
      `select count(*) from public.bids` matches the T-1H count (+ any organic bids).

## POST-APPLY +5M → EDGE + API CONFIG (same train, this order)
1. Dashboard → Settings → API → Exposed schemas: add `kernel`. Verify:
   `curl -s "$SUPABASE_URL/rest/v1/rpc/is_deletion_pending"` with service key returns
   a PostgREST error naming the function (reachable), and with no auth returns 401.
2. `supabase functions deploy delete-account create-payment-intent confirm-and-release`.
3. Smoke (a throwaway staff test account, NOT a real user):
   - POST delete-account {} → 200 `{success, status:'ok', deletion_state:'DELETION_PENDING'}`;
     `kernel.identity_ext` row shows DELETION_PENDING; outbox holds one
     `account_deletion_pending` envelope (it will drain on the next */2 tick into a
     suppressed-push notification — harmless, notifications are fail-closed).
   - POST delete-account {action:'withdraw'} → 200, state back to ACTIVE.
   - create-payment-intent for the pending state → 403 `account_deletion_pending`
     (request again after withdraw → normal flow).

## +30M
- [ ] `select * from notify.outbox where state='dead'` → 0 rows expected.
- [ ] `select jobid, status, count(*) from cron.job_run_details where start_time > now() - interval '30 minutes' group by 1,2 order by 1` —
      every phase-2 job either `succeeded` or has not fired yet; ZERO `failed`.
      Known-quiet jobs: crm-export ticks no-op (Vault secret absent by design),
      notify-drain-outbox returns `{done:0}` on an empty outbox.
- [ ] Sentry: no new error class from the three redeployed edges.

## +2H
- [ ] Re-run postapply_verify (all PASS; V10 may now count deletion-request rows if a
      real user requested deletion — that is the ONE legal phase-2 write while dark:
      identity_ext state + outbox/notification rows. Adjust reading accordingly.)
- [ ] `select deletion_state, count(*) from kernel.identity_ext group by 1` — review.
- [ ] App stores untouched: existing mobile build still bids/buys/transfers (watch
      Sentry + support channel).

## +24H
- [ ] Repeat +2H checks. Review `cron.job_run_details` failure count = 0.
- [ ] Confirm no unexpected growth: `notify.outbox` rows ≈ deletion requests only.
- [ ] Close the apply window: record ledger count 107, tag the deployed SHA
      (`prod/phase2-apply-YYYYMMDD`), file the owner packet answers (backup window).

## Rollback decision point
Between APPLY and the first real deletion request, `supabase/rollbacks/092..076` (in
reverse order, each CLEAN-WHILE-EMPTY guard proven, `set local row_security = off`
house pattern) can walk production back to the 075 world — the rollback battery
proved identity-0 at every step. After the FIRST real Phase-2 fact (a deletion
request, once the switch is live), rollback of 077 is REFUSED by its own guard:
roll FORWARD from that moment. Full tree: `PHASE2_ROLLBACK_DECISION_TREE.md`.
