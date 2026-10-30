-- Rollback for 140_proof_upload_repair.sql
--
-- ROLL THE CLIENT BACK FIRST if a client has begun reading the jsonb result.
-- The pre-140 verbs return void, so a client that branches on `outcome` sees
-- nothing rather than an error — it would treat every send as unconfirmed.
--
-- Restores the APPLIED bodies, not an older baseline: the 3-argument form as
-- 0553 defined it (no DEFAULT on the third argument, which is what keeps
-- PostgREST able to resolve the two overloads — PGRST203 regression) and the
-- 2-argument form as 0550 defined it. Both return void again, with 0553's exact
-- grants. attach_transfer_evidence is dropped.
--
-- Restores the census exactly: public functions 108 -> 107.
--
-- NOTE: rolling back reinstates BOTH defects 140 fixed — a retry after a lost
-- response raises again, and a transfer sent without proof becomes permanently
-- unrecoverable again. Any transfer that had evidence ATTACHED while 140 was in
-- force keeps it; the rollback removes the route, not the data.
begin;

drop function if exists public.attach_transfer_evidence(uuid, text);
drop function if exists public.mark_transfer_sent(uuid, uuid, text);
drop function if exists public.mark_transfer_sent(uuid, uuid);

CREATE FUNCTION public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_seller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, seller_id INTO v_status, v_seller_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the seller can mark a transfer as sent.'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET status='seller_sent', seller_sent_at=now(), auto_release_at=now()+interval '72 hours' WHERE id=p_transfer_id;
END; $function$;

CREATE FUNCTION public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid, p_transfer_evidence_path text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_seller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, seller_id INTO v_status, v_seller_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the seller can mark a transfer as sent.'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET status='seller_sent', seller_sent_at=now(), auto_release_at=now()+INTERVAL '72 hours',
    transfer_evidence_path=COALESCE(p_transfer_evidence_path, transfer_evidence_path) WHERE id=p_transfer_id;
END; $function$;

REVOKE EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid)       FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid, text) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid)       TO authenticated, service_role;

commit;
