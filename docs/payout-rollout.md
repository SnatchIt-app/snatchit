# Risk-Based Payouts + All-In Pricing — Controlled Rollout Plan

Scope: migration `039_risk_based_payout.sql`, edge functions
(`enforce-transfer-expiry`, `confirm-and-release`, `create-payment-intent`),
client build ≥ 8. Audited at commit `75ed88b` + safety-audit follow-up.

## Rollout matrix

| # | DB | Edge Functions | Client | Checkout | Payouts | Notes |
|---|----|----|--------|----------|---------|-------|
| 1 | old | old | old (≤7) | ✅ works | ✅ blanket 72h (legacy behavior) | Pre-rollout status quo. |
| 2 | **new** | old | old | ✅ works (fn ignores new tables) | ⚠️ **auto-release PAUSED** — old fn calls `enforce_auto_release()`, now a stub returning zero rows. Buyer-confirmed payouts (`confirm-and-release`) and 24h expiry refunds keep working. No corruption possible; the pause is the designed fail-safe. Rollback safe. |
| 3 | new | **new** | old | ✅ works — old payload `{listing_id, mode}` omits `expected_total_cents`; `totalMismatch(undefined, …)` = false, server charges its own calculation | ✅ risk-based pipeline live | Old client still displays base-only prices (cosmetic); charged totals unchanged vs legacy (identical math). Rollback safe. |
| 4 | new | new | **new (≥8)** | ✅ works, displayed total server-verified (409 on drift) | ✅ risk-based | `mark_transfer_viewed` RPC + `payout_review_status` column exist before any client that references them ships. |

**Forbidden order:** deploying NEW edge functions before the migration.
`get_auto_release_candidates()` / `payout_decisions` / `transfers.payout_risk_tier`
would be missing → Phase 2 errors every run and the NEW `confirm-and-release`
transfer lookup (selects `payout_risk_tier`) fails → buyer-confirmed payouts
break. **Always migrate first.**

**Expected payout pause (state 2):** from `db push` until function deploy,
silent-buyer auto-releases queue up (status stays `seller_sent`, past
`auto_release_at`). They are evaluated on the first new-function cron run.
Keep this window short (minutes); nothing is lost, nothing double-pays.

## Controlled deployment procedure (DO NOT run until approved)

```bash
# 0. Pre-deploy checks + backup
supabase db dump -f backup_pre_039_$(date +%Y%m%d%H%M).sql          # schema+data snapshot
psql "$PROD_DB_URL" -c "SELECT count(*) FROM transfers WHERE status='seller_sent' AND auto_release_at < now() AND payout_released_at IS NULL;"   # payouts that will queue during the pause
npm test && npx tsc --noEmit -p . && npx expo lint                   # green locally

# 1. (Optional maintenance signal — payouts pause automatically; checkout unaffected)

# 2. Migration (starts the payout pause)
supabase db push                                                     # applies 039

# 3. Edge functions, this exact order (webhook JWT stays DISABLED — do not touch its verify_jwt setting)
supabase functions deploy enforce-transfer-expiry
supabase functions deploy confirm-and-release
supabase functions deploy create-payment-intent
# stripe-webhook is UNCHANGED — do not redeploy it in this rollout.

# 4. Smoke tests
curl -s -X POST "$SUPABASE_URL/functions/v1/enforce-transfer-expiry" \
  -H "Authorization: Bearer $INTERNAL_CRON_SECRET" | jq              # expect {expired,refunded,auto_released,held,manual_review,...}
psql "$PROD_DB_URL" -c "SELECT decision, risk_tier, reason_codes FROM payout_decisions ORDER BY decided_at DESC LIMIT 10;"
psql "$PROD_DB_URL" -c "SELECT * FROM get_payout_review_queue();"    # admin queue visibility

# 5. Cron verification (job unchanged, but confirm it's firing)
psql "$PROD_DB_URL" -c "SELECT jobname, schedule, active FROM cron.job;"
# then watch two consecutive runs in the function logs

# 6. Legacy-client checkout verification (build 7 payload)
#    → perform one live Buy Now from the currently distributed build; confirm
#      PaymentSheet total equals listing × 1.10 and payment row is written.

# 7. Client build (only after 1–6 are green)
eas build --profile production --platform ios --non-interactive      # build 8; submit after review sign-off
```

## Rollback

```bash
# Functions only (keeps DB; restores blanket 72h release):
git checkout a963092 -- supabase/functions
supabase functions deploy enforce-transfer-expiry confirm-and-release create-payment-intent
git checkout feat/risk-payouts-allin-pricing -- supabase/functions
# NOTE: rolling back functions WITHOUT the DB restores the pause (old fn +
# stubbed RPC = zero auto-releases), which is safe; buyer confirms still pay.

# Full DB rollback (only if 039 must be reverted; new columns are additive
# and ignored by old code, so this is rarely necessary):
psql "$PROD_DB_URL" << 'SQL'
DROP FUNCTION IF EXISTS public.get_payout_review_queue();
DROP FUNCTION IF EXISTS public.admin_release_held_payout(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.apply_manual_review(uuid, text, text[]);
DROP FUNCTION IF EXISTS public.apply_payout_hold(uuid, timestamptz, text, text[]);
DROP FUNCTION IF EXISTS public.apply_auto_release(uuid);
DROP FUNCTION IF EXISTS public.get_auto_release_candidates();
DROP FUNCTION IF EXISTS public.mark_transfer_viewed(uuid);
DROP TABLE IF EXISTS public.payout_decisions;
DROP TABLE IF EXISTS public.payout_policy;
ALTER TABLE public.transfers
  DROP COLUMN IF EXISTS buyer_viewed_at,
  DROP COLUMN IF EXISTS payout_hold_until,
  DROP COLUMN IF EXISTS payout_risk_tier,
  DROP COLUMN IF EXISTS payout_reason_codes,
  DROP COLUMN IF EXISTS payout_review_status;
SQL
# then re-apply migration 016's enforce_auto_release() body to restore the
# legacy blanket release (supabase/migrations/016_fix_auto_release_payout.sql).
```

## Medium-hold cap behavior (reason-code dependent)

The 7-day cap ends an indefinite automated wait — it is **not** a release
justification. At the cap, `classifyMediumCapAction()` routes by why the
transaction was medium:

| Medium reason | At the 7-day cap |
|---|---|
| `HIGH_VALUE_ORDER` (established, KYC-complete, clean seller) | **Release** (weak signal — every reliability check already passed) |
| `BUYER_NEVER_VIEWED` with corroborative evidence (supported non-rotating platform) | **Release** |
| `BUYER_NEVER_VIEWED` on a rotating-barcode provider (screenshot ≠ acceptance proof) | No release → post-event hold if near, else manual review |
| `SELLER_UNPROVEN` | No release → post-event hold if near, else **manual review** |
| `SELLER_RISK_TIER_MEDIUM` | Same |
| `PRIOR_DISPUTES` | Same |
| `UNSUPPORTED_PLATFORM` | Same |
| `ROTATING_BARCODE` | Same |
| `EVENT_DATE_UNKNOWN` | **Manual review, always** — elapsed time never releases an unknown date |
| Any unknown/future reason code | Treated as strong (conservative) — no cap release |

"Near" = the post-event point lands within one further cap-length
(`medium_max_hold_days`); those holds extend to the post-event grace
(`MEDIUM_HOLD_EXTENDED_POST_EVENT`) instead of going to an operator.
Buyer explicit confirmation remains an immediate release path at any time
(absent a dispute), and disputes freeze everything regardless of tier.

Examples (defaults: 24h grace, 7-day cap, sale at 72h mark 07-14):
- **Event tomorrow** (07-15): hold to 07-17T12:00Z (post-event grace) → release.
- **Event in five days** (07-19): hold to the earlier of grace/cap → release at the post-event point.
- **Event in thirty days** (08-13): hold to the cap (07-21); at the cap —
  weak-only reasons release; seller/transfer-risk reasons go to manual review
  (the event is too far for a bounded extension).

## Stripe/DB consistency model (honest statement)

Postgres and Stripe cannot be updated atomically. The protocol instead
guarantees at-most-one payout per transfer:

1. Atomic row claim in Postgres (`FOR UPDATE` / conditional `UPDATE`) decides
   WHICH path may pay; racing paths lose the state-machine precondition.
2. Every money call carries Stripe `Idempotency-Key: payout_<transfer_id>`,
   so even a protocol violation replays the SAME Stripe Transfer.
3. A final dispute recheck runs immediately before each Stripe call.
4. If Stripe succeeds and the DB write fails, the row remains
   claimed-but-unpaid and the Phase 2b sweep replays the idempotent call and
   persists `stripe_transfer_id` — recovery by replay, never by second payout.

Simulated deterministically in `tests/payout-races.test.ts`.
