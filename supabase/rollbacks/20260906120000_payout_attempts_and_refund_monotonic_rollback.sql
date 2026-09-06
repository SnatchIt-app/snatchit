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
-- DATA: payout_attempts / payment_refunds / account_deletions rows are the
-- audit trail of every attempt made while the package was live. Export them
-- first (\copy) — this file destroys them. payments.amount_refunded_cents is
-- dropped WITH its values (a re-apply starts at NULL = unknown, by design).
--
-- Verification after rollback:
--   SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
--     ('claim_payout_attempt','mark_payout_requested','record_payout_attempt_result',
--      'reconcile_payout_attempt','flag_payout_reversal_required','record_payment_refund',
--      'account_deletion_blockers','guard_payout_attempt_columns','guard_payment_transitions',
--      'reset_payment_guard_bypass','payment_refunds_append_only');           -- 0
--   SELECT count(*) FROM pg_tables WHERE schemaname='public'
--     AND tablename IN ('payout_attempts','payment_refunds','account_deletions'); -- 0
-- ============================================================================

BEGIN;

-- Triggers first (they reference the functions).
DROP TRIGGER IF EXISTS trg_guard_payout_attempt_columns  ON public.payout_attempts;
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
