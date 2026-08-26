-- 055d_fix_mark_transfer_sent_overload_ambiguity.sql
-- Regression fix for 055: drops the DEFAULT on the third argument of
-- mark_transfer_sent(uuid, uuid, text) so PostgREST can again resolve the 2-arg
-- and 3-arg overloads unambiguously (PGRST203), restoring the seller mark-sent
-- path used by the shipped build 13 client. Re-applies the anon/PUBLIC revoke.
-- Recovered from supabase_migrations.schema_migrations version 20260805041030; applied 20260805041030. Not re-applied.

-- 055d: REGRESSION FIX. 055 recreated the 3-arg mark_transfer_sent with
-- `p_transfer_evidence_path text DEFAULT NULL::text`. That default made the
-- 3-arg overload a viable candidate for a 2-key JSON body, so PostgREST could
-- no longer resolve {p_transfer_id, p_user_id} and returned PGRST203
-- ("Could not choose the best candidate function").
--
-- That is precisely the payload shipped build 13 sends from
-- src/screens/ListingDetailScreen.tsx:798, so the seller mark-sent path was
-- broken for the build currently in App Review.
--
-- Dropping the default restores unambiguous resolution: a 2-key body matches
-- only the 2-arg overload, a 3-key body matches only the 3-arg one. This is how
-- PostgREST resolved these overloads before 055.

DROP FUNCTION IF EXISTS public.mark_transfer_sent(uuid, uuid, text);

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
GRANT  EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid, text) TO authenticated, service_role;
