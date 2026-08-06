-- 055b_transfer_guard_bypass_for_remaining_writers.sql
-- Adds the transaction-local app.bypass_transfer_guard GUC to every remaining
-- SECURITY DEFINER writer of public.transfers (expiry sweep, auto-release, payout
-- hold / manual review, admin release, dispute resolution, account cleanup). Those
-- functions run as `postgres`, not `service_role`, so the 055 current_user exemption
-- does not cover them and the state guard would otherwise block their writes.
-- Recovered from supabase_migrations.schema_migrations version 20260805040826; applied 20260805040826. Not re-applied.

-- 055b: SECURITY DEFINER functions run as `postgres`, not `service_role`, so the
-- temporary current_user exemption in 055 does NOT cover them. Every remaining
-- writer needs the transaction-local bypass GUC or the guard blocks it.

CREATE OR REPLACE FUNCTION public.enforce_transfer_expiry()
RETURNS TABLE(transfer_id uuid, payment_id uuid, listing_id uuid, buyer_id uuid, seller_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  perform set_config('app.bypass_transfer_guard', 'on', true);
  return query
  with expired as (
    select t.id, t.payment_id, t.listing_id, t.buyer_id, t.seller_id
      from public.transfers t
     where t.status = 'pending' and t.expires_at < now()
       for update skip locked
  )
  update public.transfers t
     set status = 'expired', expired_at = now()
    from expired e
   where t.id = e.id
  returning t.id as transfer_id, t.payment_id, t.listing_id, t.buyer_id, t.seller_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.apply_auto_release(p_transfer_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_claimed int;
BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  WITH claimable AS (
    SELECT t.id FROM public.transfers t
     WHERE t.id = p_transfer_id AND t.status = 'seller_sent'
       AND t.payout_released_at IS NULL
       AND (t.payout_review_status IS DISTINCT FROM 'manual_review')
       FOR UPDATE SKIP LOCKED
  )
  UPDATE public.transfers t
     SET status='auto_released', payout_review_status=NULL, payout_hold_until=NULL
    FROM claimable c WHERE t.id = c.id;
  GET DIAGNOSTICS v_claimed = ROW_COUNT;
  RETURN v_claimed = 1;
END; $function$;

CREATE OR REPLACE FUNCTION public.apply_payout_hold(p_transfer_id uuid, p_hold_until timestamp with time zone, p_tier text, p_reasons text[])
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET payout_hold_until=p_hold_until, payout_review_status='held',
         payout_risk_tier=p_tier, payout_reason_codes=p_reasons
   WHERE id=p_transfer_id AND status='seller_sent' AND payout_released_at IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END; $function$;

CREATE OR REPLACE FUNCTION public.apply_manual_review(p_transfer_id uuid, p_tier text, p_reasons text[])
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET payout_review_status='manual_review', payout_hold_until=NULL,
         payout_risk_tier=p_tier, payout_reason_codes=p_reasons
   WHERE id=p_transfer_id AND status='seller_sent' AND payout_released_at IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END; $function$;

CREATE OR REPLACE FUNCTION public.admin_release_held_payout(p_transfer_id uuid, p_admin_id uuid, p_note text DEFAULT NULL::text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_updated int; v_row public.transfers%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_row.status <> 'seller_sent' OR v_row.payout_released_at IS NOT NULL THEN RETURN false; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET status='auto_released', payout_review_status=NULL, payout_hold_until=NULL
   WHERE id=p_transfer_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  INSERT INTO public.payout_decisions
    (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, evidence, actor)
  VALUES (p_transfer_id, v_row.payment_id, v_row.seller_id, v_row.buyer_id,
     COALESCE(v_row.payout_risk_tier,'high'), 'release', ARRAY['ADMIN_MANUAL_RELEASE'],
     jsonb_build_object('note', p_note), 'admin:' || p_admin_id::text);
  RETURN v_updated = 1;
END; $function$;

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(p_transfer_id uuid, p_resolution text, p_admin_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF p_resolution NOT IN ('resolved_seller_paid','resolved_buyer_refunded','resolved_partial_refund') THEN
    RAISE EXCEPTION 'Invalid resolution type: %', p_resolution;
  END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET dispute_resolution=p_resolution, dispute_resolved_at=now(), dispute_resolved_by=p_admin_id
   WHERE id=p_transfer_id AND status='disputed' AND dispute_resolved_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found, not in disputed state, or already resolved.';
  END IF;
END; $function$;

CREATE OR REPLACE FUNCTION public.delete_account_cleanup(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_sentinel_id uuid := '00000000-0000-0000-0000-000000000000';
begin
  perform set_config('app.bypass_listing_guard', 'on', true);
  perform set_config('app.bypass_transfer_guard', 'on', true);

  update public.listings
     set auction_status='cancelled', status='active', reserved_by=null,
         reserved_until=null, ended_at=now()
   where seller_id = p_user_id and auction_status in ('active','ended');

  alter table public.listings disable trigger trg_guard_listing_identity;
  update public.listings set seller_id = v_sentinel_id where seller_id = p_user_id;
  alter table public.listings enable trigger trg_guard_listing_identity;

  update public.payments set buyer_id  = v_sentinel_id where buyer_id  = p_user_id;
  update public.payments set seller_id = v_sentinel_id where seller_id = p_user_id;
  update public.transfers set buyer_id  = v_sentinel_id where buyer_id  = p_user_id;
  update public.transfers set seller_id = v_sentinel_id where seller_id = p_user_id;
end; $function$;
