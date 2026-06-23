-- =============================================================================
-- 034_transfer_notifications.sql
-- Transaction-progress notifications + buyer-visible seller transfer proof.
--
-- Adds:
--   1. transfer_notifications  — idempotency log (one row per transfer+event)
--   2. notify_transfer_event() — trigger → pg_net → notify-transfer edge fn
--        * AFTER INSERT  ON transfers              → 'transfer_created'
--        * AFTER UPDATE  ON transfers (→seller_sent)→ 'tickets_marked_sent'
--   3. proof-docs storage policy so the BUYER and SELLER of a transfer can
--      read that transfer's seller proof (transfer_evidence_path). Bucket
--      stays private; admin/service-role already bypasses RLS.
--
-- Reminder sweeps (transfer_reminder_seller / transfer_reminder_buyer) reuse
-- the existing every-2-min enforce-transfer-expiry cron and the existing
-- partial indexes idx_transfers_pending_expires / idx_transfers_seller_sent_*.
-- Payment/Stripe/charge logic is untouched.
-- =============================================================================

BEGIN;

-- ── 1. Idempotency log ───────────────────────────────────────────────────────
-- One row per (transfer, event_type) guarantees "one notification per transfer
-- per event type" — the PK is the dedupe key. No client access.
CREATE TABLE IF NOT EXISTS public.transfer_notifications (
  transfer_id uuid        NOT NULL REFERENCES public.transfers(id) ON DELETE CASCADE,
  event_type  text        NOT NULL CHECK (event_type IN (
                            'seller_action_required',
                            'buyer_transfer_info_needed',
                            'tickets_marked_sent',
                            'buyer_confirmation_needed',
                            'transfer_reminder_seller',
                            'transfer_reminder_buyer'
                          )),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (transfer_id, event_type)
);

ALTER TABLE public.transfer_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.transfer_notifications FROM PUBLIC, anon, authenticated;
-- service_role bypasses RLS; only the edge functions read/write this table.

-- ── 2. Notify-transfer trigger (fire-and-forget via pg_net + Vault) ──────────
CREATE OR REPLACE FUNCTION public.notify_transfer_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key     text;
  v_event   text;
  v_payload jsonb;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event := 'transfer_created';
  ELSE
    v_event := 'tickets_marked_sent';
  END IF;

  v_payload := jsonb_build_object(
    'event',       v_event,
    'transfer_id', NEW.id,
    'listing_id',  NEW.listing_id,
    'buyer_id',    NEW.buyer_id,
    'seller_id',   NEW.seller_id
  );

  BEGIN
    SELECT decrypted_secret INTO v_key
      FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/notify-transfer',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type',  'application/json'
        ),
        body    := v_payload
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Never block the buyer/seller action because a notification failed.
    RAISE WARNING 'notify_transfer_event: % notification failed: %', v_event, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_transfer_created ON public.transfers;
CREATE TRIGGER trg_notify_transfer_created
  AFTER INSERT ON public.transfers
  FOR EACH ROW EXECUTE FUNCTION public.notify_transfer_event();

DROP TRIGGER IF EXISTS trg_notify_transfer_sent ON public.transfers;
CREATE TRIGGER trg_notify_transfer_sent
  AFTER UPDATE OF status ON public.transfers
  FOR EACH ROW
  WHEN (NEW.status = 'seller_sent' AND OLD.status IS DISTINCT FROM 'seller_sent')
  EXECUTE FUNCTION public.notify_transfer_event();

-- ── 3. Buyer-visible seller proof (private bucket stays private) ─────────────
-- Seller proof now lands in proof-docs at <seller_uid>/transfer-evidence/...
-- The existing "proof-docs owner read/insert" policies (033) cover the seller.
-- This policy additionally lets the matching BUYER (and seller) read the exact
-- object referenced by their transfer's transfer_evidence_path — nothing else.
DROP POLICY IF EXISTS "proof-docs transfer party read" ON storage.objects;
CREATE POLICY "proof-docs transfer party read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'proof-docs'
    AND EXISTS (
      SELECT 1 FROM public.transfers t
       WHERE t.transfer_evidence_path = storage.objects.name
         AND (t.buyer_id = auth.uid() OR t.seller_id = auth.uid())
    )
  );

COMMIT;
