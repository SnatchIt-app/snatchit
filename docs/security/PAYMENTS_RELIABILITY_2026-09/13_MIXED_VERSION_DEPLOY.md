# Deploying six edges that do not update atomically — what is safe in every intermediate state

Source: independent review `rc/R6_mixed_version_deploy_review.md` (matrix X1–X18 proved on a rehearsal DB against the
deployed edge sources), integrated by the lead. Code commit under review: `972619f` (+ the sandbox switch and evidence
merge landed after; neither changes a verdict).

## 1. What the NEW schema does with OLD edge writes

Every write the six deployed edges perform is accepted by the new schema except two guard refusals, both of which the
old code logs and continues past, both money-safe: `refunded → succeeded` (old webhook / old confirm-payment on a row a
refund already reached) and the old sweep's unpredicated Phase-1 refund rewrite. Every RPC the old edges call
(`record_transfer_payout`, `mark_listing_sold`, `complete_auction_payment`, `ensure_transfer_exists`, webhook lease
RPCs) is byte-unchanged. Old-webhook direct refund/dispute UPDATEs are later healed by `record_payment_refund` with the
same refund/dispute id.

## 2. The one genuinely unsafe pair

**confirm-and-release NEW + enforce-transfer-expiry OLD with the cron live.** The old sweep's Phase 2b ignores
`payout_attempts` and POSTs a transfer under its own idempotency key (`payout_<id>_<acct>_src`), while the new
confirm-and-release uses `payout_<id>_a<n>`: two keys, two Stripe transfers for one obligation (rehearsal E7 shape —
detected as `DUPLICATE_TRANSFER`, but detection is not prevention). Every other pair is safe: `enforce-transfer-expiry`
NEW + `confirm-and-release` OLD is covered by the legacy-aware pre-flight; `delete-account` NEW is safe at any point
(read-only predicate with an `unavailable` fallback); `create-payment-intent` NEW + `confirm-payment` OLD is the P1
state already rehearsed.

## 3. Deploy order (replaces the "five edges in one step" wording)

```
P1-a  apply 20260906100000                      P1-c  deploy create-payment-intent (v46)
P2-a  apply 20260906110000
P3-a  duplicate tr_ query = 0 rows               P3-b  apply 20260906120000       P3-b2 apply 20260906130000
P3-b3 legacy orphan reconciliation (Q9)
D1    deploy delete-account   (canary: no money interplay; proves CLI/auth)          → v20
D2    deploy confirm-payment                                                          → v35
D3    deploy stripe-webhook   (--no-verify-jwt preserved)                             → v40
PAUSE cron.unschedule('enforce-transfer-expiry'); wait ≥ 5 min; Q1–Q15 triage (the ONLY moment the backlog can be shaped)
D4    deploy enforce-transfer-expiry                                                  → v37
D5    deploy confirm-and-release                                                      → v35
D6    one MANUAL sweep run; read the summary JSON (reconciled_* keys present = new code)
RESUME cron.schedule(... 014 verbatim ...)
P2-d  Stripe endpoint: add payment_intent.canceled (08 doc)     P2-e  pending-intent backfill (12 doc)
```
Why this order: the webhook is new before the sweep so `paid_unsettled` rows are settled by one contract; the sweep is
new before confirm-and-release so the unsafe pair of §2 never exists with the cron live; the pause guards only the sweep
switch itself.

## 4. Interrupted deployment — stop/resume rule

Stop. Do not re-run the whole list. Resume checks:
1. `supabase functions list --project-ref hqycwntpfoztoinemqns` — version column against the expected +1 per function
   above tells you exactly where the deploy stopped.
2. `select jobname, active from cron.job where jobname='enforce-transfer-expiry'` — must be absent between PAUSE and
   RESUME; if it is present while `confirm-and-release` is new and `enforce-transfer-expiry` old, unschedule it NOW.
3. `select state, count(*) from public.payout_attempts group by 1` — no `unknown` older than 10 minutes.
4. Continue from the first undeployed step. Rolling back a single edge (redeploy the previous version) is safe for
   every edge except `enforce-transfer-expiry` while `confirm-and-release` is new — pause the cron first.

## 5. Incoming webhooks during the deploy

- An event the OLD webhook completed cannot be re-driven by `stripe events resend` (`already_processed`): reconciliation
  of old-webhook-processed rows is the sweep's Phase 0, not resend.
- The OLD webhook on the new schema 500-loops two classes (a refunded row; metadata buyer ≠ row buyer) until the NEW
  webhook drains them via the released lease — money-safe, noisy; check 15 minutes after D3 that
  `get_incomplete_webhook_events(300,100)` shows no `attempt_count > 1` older than 15 minutes.
- `payment_intent.canceled` is added only AFTER the new webhook (the old one acks unknown types terminally).

## 6. Cron resumption — the first NEW sweep moves money on legacy rows

On its first tick the new sweep (a) settles every `paid_unsettled` row regardless of age and gives each a fresh 24-hour
transfer clock (Phase-1 refund next day if the seller never sends), (b) refunds `unfulfillable` captures immediately,
(c) refunds the remainder of partially refunded expired transfers the old predicate skipped. Therefore Q1–Q15 (R6 §4,
validated SQL) run while the cron is paused, and rows that were delivered or paid out-of-band get a truthful
`transfers` row inserted BEFORE resuming (then the contract returns `already_settled` and no clock starts).
`get_auto_release_candidates` has no LIMIT: if Q4 is large, run D6 manually and watch the summary before scheduling.

## 7. Stop/resume checklist

The 23-step table with commands and expected values is `rc/R6_mixed_version_deploy_review.md` §5; it is the operator
artefact for the deploy and supersedes `04_RELEASE_PLAN.md` §1's step list where they differ.
