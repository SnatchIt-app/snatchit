-- Rollback for 055_transfer_state_guard.sql
--
-- WARNING: this REOPENS three confirmed-exploitable holes:
--   * a buyer can rewrite status/seller_id on their own transfer, and
--     enforce-transfer-expiry Phase 2b will pay the forged seller_id;
--   * the shipped anon key can drive the whole transfer state machine with no
--     session, via coalesce(auth.uid(), p_user_id);
--   * transfer/dispute evidence paths become rewritable.
-- Only run this if a legitimate production flow regressed and cannot be fixed
-- forward.

BEGIN;

DROP TRIGGER IF EXISTS trg_guard_transfer_state_columns ON public.transfers;
DROP FUNCTION IF EXISTS public.guard_transfer_state_columns();

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.transfers TO authenticated, anon;

CREATE POLICY "Buyers can update own transfers"  ON public.transfers
  FOR UPDATE USING (auth.uid() = buyer_id);
CREATE POLICY "Sellers can update own transfers" ON public.transfers
  FOR UPDATE USING (auth.uid() = seller_id);

GRANT EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid)                        TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid, text)                  TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_transfer_received(uuid, uuid)                 TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buyer_dispute_transfer(uuid, uuid, text, text, text)  TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_transfer_exists(uuid, uuid)                    TO PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_transfer_delivery_info(uuid, text, text)          TO PUBLIC, anon;

-- Restore the coalesce() identity fallback on the five affected RPCs.
CREATE OR REPLACE FUNCTION public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_seller_id uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, seller_id INTO v_status, v_seller_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the seller can mark a transfer as sent.'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status; END IF;
  UPDATE public.transfers SET status='seller_sent', seller_sent_at=now(), auto_release_at=now()+interval '72 hours' WHERE id=p_transfer_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid, p_transfer_evidence_path text DEFAULT NULL::text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_seller_id uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, seller_id INTO v_status, v_seller_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the seller can mark a transfer as sent.'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status; END IF;
  UPDATE public.transfers SET status='seller_sent', seller_sent_at=now(), auto_release_at=now()+INTERVAL '72 hours',
    transfer_evidence_path=COALESCE(p_transfer_evidence_path, transfer_evidence_path) WHERE id=p_transfer_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.confirm_transfer_received(p_transfer_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_caller_id uuid; v_status text; v_buyer_id uuid;
begin
  v_caller_id := coalesce(auth.uid(), p_user_id);
  if v_caller_id is null then raise exception 'Unable to identify caller. Ensure the request is authenticated.'; end if;
  select status, buyer_id into v_status, v_buyer_id from public.transfers where id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found.'; end if;
  if v_buyer_id is distinct from v_caller_id then raise exception 'Only the buyer can confirm transfer receipt.'; end if;
  if v_status <> 'seller_sent' then raise exception 'Transfer cannot be confirmed from current status: %.', v_status; end if;
  update public.transfers set status='buyer_confirmed', buyer_confirmed_at=now() where id=p_transfer_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.buyer_dispute_transfer(p_transfer_id uuid, p_user_id uuid DEFAULT NULL::uuid, p_dispute_reason text DEFAULT NULL::text, p_dispute_evidence_path text DEFAULT NULL::text, p_dispute_notes text DEFAULT NULL::text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_buyer_id uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, buyer_id INTO v_status, v_buyer_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the buyer can dispute a transfer.'; END IF;
  IF v_status = 'disputed' THEN RETURN; END IF;
  IF v_status <> 'seller_sent' THEN RAISE EXCEPTION 'Cannot dispute transfer in current status: %.', v_status; END IF;
  UPDATE public.transfers SET status='disputed', disputed_at=now(),
    dispute_reason=COALESCE(p_dispute_reason, dispute_reason),
    dispute_evidence_path=COALESCE(p_dispute_evidence_path, dispute_evidence_path),
    dispute_notes=COALESCE(p_dispute_notes, dispute_notes) WHERE id=p_transfer_id;
END; $function$;

-- The remaining writers differ from their pre-055 bodies only by the added
-- set_config() line, which is inert once the trigger above is dropped.

DROP FUNCTION IF EXISTS public.request_is_service_role();

COMMIT;
