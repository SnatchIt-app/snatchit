-- ============================================================================
-- ROLLBACK for 20260906120000_payout_attempts_and_refund_monotonic.sql
--
-- Drops every object that migration created. It changed NO pre-existing
-- function body (record_transfer_payout / freeze_transfer_for_dispute /
-- delete_account_cleanup are untouched), so nothing is restored here.
--
-- EDGE ORDER: redeploy the pre-package confirm-and-release (v34),
-- enforce-transfer-expiry (v36), stripe-webhook and delete-account BEFORE
-- running this, or every payout/refund/deletion call fails PGRST202 on the
-- missing RPCs (record_transfer_payout still exists, so the old edges work).
--
-- DATA: payout_attempts / payment_refunds / account_deletions rows and the
-- payments refund facts are ARCHIVED into schema rollback_archive inside this
-- transaction (R5 §3) and RESTORED by the forward migration on re-apply.
-- Export them as well (\copy) — belt and braces. The rollback REFUSES while any
-- R5 D-detector is non-zero (gate block below) unless app.rollback_force=on.
--
-- Verification after rollback:
--   SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
--     ('claim_payout_attempt','mark_payout_requested','record_payout_attempt_result',
--      'reconcile_payout_attempt','flag_payout_reversal_required','record_payment_refund',
--      'account_deletion_blockers','guard_payout_attempt_columns','guard_payment_transitions',
--      'reset_payment_guard_bypass','payment_refunds_append_only',
--      'payout_attempts_no_delete');                                         -- 0
--   SELECT count(*) FROM pg_tables WHERE schemaname='public'
--     AND tablename IN ('payout_attempts','payment_refunds','account_deletions'); -- 0
-- ============================================================================

BEGIN;

-- ── Pre-rollback gates (R5 D-detectors). Rollback is data-safe only while every
-- detector is zero; otherwise old code re-interprets new-code facts (full-net
-- payout on a partially refunded order, re-POST of an in-flight payout, ...).
-- An operator may override ONLY with a ticketed decision:
--   SELECT set_config('app.rollback_force', 'on', true);
DO $gate$
DECLARE v_bad text := '';
BEGIN
  IF current_setting('app.rollback_force', true) = 'on' THEN
    RAISE WARNING 'rollback 20260906120000: gates OVERRIDDEN by app.rollback_force (ticketed operator decision expected)';
    RETURN;
  END IF;
  IF (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='account_deletion_block_reason') > 0 THEN v_bad := v_bad || ' O2=' || (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='account_deletion_block_reason')::text || ' [20260906130000 still applied - roll it back first]'; END IF;
  IF (SELECT count(*) FROM public.payout_attempts WHERE state IN ('claimed','requested','unknown')) > 0 THEN v_bad := v_bad || ' D1=' || (SELECT count(*) FROM public.payout_attempts WHERE state IN ('claimed','requested','unknown'))::text || ' [open payout attempts - reconcile against Stripe first]'; END IF;
  IF (SELECT count(*) FROM public.payments p JOIN public.transfers t ON t.payment_id = p.id WHERE coalesce(p.amount_refunded_cents,0) > 0 AND p.status = 'succeeded' AND t.stripe_transfer_id IS NULL AND t.payout_released_at IS NULL AND t.status IN ('pending','seller_sent','buyer_confirmed','auto_released')) > 0 THEN v_bad := v_bad || ' D2=' || (SELECT count(*) FROM public.payments p JOIN public.transfers t ON t.payment_id = p.id WHERE coalesce(p.amount_refunded_cents,0) > 0 AND p.status = 'succeeded' AND t.stripe_transfer_id IS NULL AND t.payout_released_at IS NULL AND t.status IN ('pending','seller_sent','buyer_confirmed','auto_released'))::text || ' [partially refunded orders with an unpaid transfer - old code would pay the FULL seller net]'; END IF;
  IF (SELECT count(*) FROM public.webhook_retries WHERE resolved IS NOT TRUE AND rpc_name IN ('settle_verified_payment','transfer.created')) > 0 THEN v_bad := v_bad || ' D3=' || (SELECT count(*) FROM public.webhook_retries WHERE resolved IS NOT TRUE AND rpc_name IN ('settle_verified_payment','transfer.created'))::text || ' [unresolved settlement/transfer review rows - no old-code reader]'; END IF;
  IF (SELECT count(*) FROM public.payout_attempts a WHERE a.state = 'reversal_required' AND NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.id = a.transfer_id AND t.status = 'reversed')) > 0 THEN v_bad := v_bad || ' D5=' || (SELECT count(*) FROM public.payout_attempts a WHERE a.state = 'reversal_required' AND NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.id = a.transfer_id AND t.status = 'reversed'))::text || ' [reversal obligations whose money has not come back - old code never gates on them]'; END IF;
  IF (SELECT count(*) FROM public.account_deletions WHERE phase <> 'done') > 0 THEN v_bad := v_bad || ' D7=' || (SELECT count(*) FROM public.account_deletions WHERE phase <> 'done')::text || ' [mid-flight deletion phases]'; END IF;
  IF (SELECT count(*) FROM public.payments WHERE status = 'refunded' AND coalesce(amount_refunded_cents, total) < total) > 0 THEN v_bad := v_bad || ' D8=' || (SELECT count(*) FROM public.payments WHERE status = 'refunded' AND coalesce(amount_refunded_cents, total) < total)::text || ' [refunded rows carrying a partial amount - inconsistent refund facts]'; END IF;

  IF v_bad <> '' THEN
    RAISE EXCEPTION 'rollback 20260906120000 REFUSED - unsafe state present:% (settle each, or set app.rollback_force=on with a ticket)', v_bad;
  END IF;
END $gate$;

-- ── Archive (R5 §3): every new-code fact this rollback destroys or that old code
-- re-interprets is copied into rollback_archive INSIDE this transaction. The
-- forward migration restores from it (ON CONFLICT DO NOTHING / NULL->value) and
-- stamps manifest.restored_at; a second rollback refuses while an unrestored
-- archive exists (nothing is ever silently overwritten).
CREATE SCHEMA IF NOT EXISTS rollback_archive;
REVOKE ALL ON SCHEMA rollback_archive FROM PUBLIC, anon, authenticated;
DO $arch$
BEGIN
  IF to_regclass('rollback_archive.manifest') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM rollback_archive.manifest WHERE restored_at IS NULL)
       AND current_setting('app.rollback_force', true) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION 'rollback 20260906120000 REFUSED - rollback_archive holds an archive that was never restored (re-apply the migration to restore it, or set app.rollback_force=on with a ticket)';
    END IF;
  END IF;
END $arch$;
DROP TABLE IF EXISTS rollback_archive.manifest, rollback_archive.payments_refund_facts, rollback_archive.payout_attempts,
  rollback_archive.payment_refunds, rollback_archive.account_deletions, rollback_archive.payout_decisions_new,
  rollback_archive.webhook_retries_review, rollback_archive.transfers_money, rollback_archive.listings_reservation,
  rollback_archive.identity_bp13;
CREATE TABLE rollback_archive.payments_refund_facts AS
  SELECT id, stripe_payment_intent_id, status, total, amount_refunded_cents, refunded_at, stripe_refund_id, failed_at, paid_at, now() AS archived_at
    FROM public.payments;
CREATE TABLE rollback_archive.payout_attempts        AS SELECT *, now() AS archived_at FROM public.payout_attempts;
CREATE TABLE rollback_archive.payment_refunds        AS SELECT *, now() AS archived_at FROM public.payment_refunds;
CREATE TABLE rollback_archive.account_deletions      AS SELECT *, now() AS archived_at FROM public.account_deletions;
CREATE TABLE rollback_archive.payout_decisions_new   AS
  SELECT *, now() AS archived_at FROM public.payout_decisions
   WHERE (evidence ? 'attempt_id') OR reason_codes && ARRAY['PAID_DURING_DISPUTE','DUPLICATE_TRANSFER','REFUNDED_AFTER_PAYOUT','PARTIAL_REFUND_AFTER_PAYOUT','DISPUTE_LOST_AFTER_PAYOUT','PAYMENT_PARTIALLY_REFUNDED'];
CREATE TABLE rollback_archive.webhook_retries_review AS SELECT *, now() AS archived_at FROM public.webhook_retries WHERE rpc_name IN ('settle_verified_payment','transfer.created');
CREATE TABLE rollback_archive.transfers_money        AS SELECT id, status, stripe_transfer_id, payout_released_at, disputed_at, now() AS archived_at FROM public.transfers;
CREATE TABLE rollback_archive.listings_reservation   AS SELECT id, status, reserved_by, reserved_until, now() AS archived_at FROM public.listings WHERE reserved_by IS NOT NULL OR status = 'reserved';
CREATE TABLE rollback_archive.identity_bp13          AS SELECT identity_id, deletion_state, deletion_block_reason, deletion_requested_at, now() AS archived_at FROM kernel.identity_ext WHERE deletion_block_reason LIKE 'BP-13%';
CREATE TABLE rollback_archive.manifest AS
  SELECT now() AS archived_at, NULL::timestamptz AS restored_at, '20260906120000'::text AS package, current_user::text AS operator,
         (SELECT count(*) FROM rollback_archive.payout_attempts)  AS n_attempts,
         (SELECT count(*) FROM rollback_archive.payment_refunds)  AS n_refunds,
         (SELECT count(*) FROM rollback_archive.account_deletions) AS n_deletions,
         (SELECT count(*) FROM rollback_archive.payments_refund_facts WHERE amount_refunded_cents IS NOT NULL) AS n_partial_refund_facts;

-- Triggers first (they reference the functions).
DROP TRIGGER IF EXISTS trg_guard_payout_attempt_columns  ON public.payout_attempts;
DROP TRIGGER IF EXISTS trg_payout_attempts_no_delete     ON public.payout_attempts;
DROP TRIGGER IF EXISTS trg_payout_attempts_no_truncate   ON public.payout_attempts;
DROP TRIGGER IF EXISTS trg_payment_refunds_append_only   ON public.payment_refunds;
DROP TRIGGER IF EXISTS trg_guard_payment_transitions     ON public.payments;
DROP TRIGGER IF EXISTS trg_reset_payment_guard_bypass    ON public.payments;

-- RPCs.
DROP FUNCTION IF EXISTS public.account_deletion_blockers(uuid);
DROP FUNCTION IF EXISTS public.flag_payout_reversal_required(uuid, text, jsonb);
DROP FUNCTION IF EXISTS public.reconcile_payout_attempt(uuid, text);
DROP FUNCTION IF EXISTS public.record_payout_attempt_result(uuid, text, text, jsonb);
DROP FUNCTION IF EXISTS public.mark_payout_requested(uuid);
DROP FUNCTION IF EXISTS public.claim_payout_attempt(uuid, text, interval);
DROP FUNCTION IF EXISTS public.record_payment_refund(text, text, text, int, text);

-- Trigger functions.
DROP FUNCTION IF EXISTS public.guard_payout_attempt_columns();
DROP FUNCTION IF EXISTS public.payout_attempts_no_delete();
DROP FUNCTION IF EXISTS public.guard_payment_transitions();
DROP FUNCTION IF EXISTS public.reset_payment_guard_bypass();
DROP FUNCTION IF EXISTS public.payment_refunds_append_only();

-- Tables (indexes go with them).
DROP TABLE IF EXISTS public.account_deletions;
DROP TABLE IF EXISTS public.payment_refunds;
DROP TABLE IF EXISTS public.payout_attempts;

-- transfers unique index (F-2 reopens).
DROP INDEX IF EXISTS public.transfers_stripe_transfer_id_uniq;

-- payments column (guarded: only if present).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'payments'
                AND column_name = 'amount_refunded_cents') THEN
    ALTER TABLE public.payments DROP COLUMN amount_refunded_cents;
  END IF;
END $$;

COMMIT;
