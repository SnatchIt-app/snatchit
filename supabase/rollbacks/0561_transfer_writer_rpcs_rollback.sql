-- Rollback for 056a.
-- Safe ONLY while the Edge Functions still use direct UPDATEs (i.e. before the
-- deploy in step 2). After they are converted, dropping these RPCs breaks the
-- payout, dispute-freeze and reversal paths.
BEGIN;
DROP FUNCTION IF EXISTS public.record_transfer_payout(uuid, text);
DROP FUNCTION IF EXISTS public.freeze_transfer_for_dispute(uuid);
DROP FUNCTION IF EXISTS public.mark_transfer_reversed(text);
COMMIT;
