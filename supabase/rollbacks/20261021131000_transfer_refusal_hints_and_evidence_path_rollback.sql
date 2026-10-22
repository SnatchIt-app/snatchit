-- ============================================================================
-- ROLLBACK for 20261021131000_transfer_refusal_hints_and_evidence_path.sql (registry 171, pgTAP 241).
-- DRAFT like the migration: not for apply before 2026-10-28 03:47:04Z (four live listings) and before build 29's
-- review settles; owner-gated. Run only under owner approval, and only if 171 was applied.
-- Pre-171 state = production 2026-10-21 (prod_functions.json, A's read-only snapshot; md5(pg_get_functiondef)):
--   public.guard_transfer_state_columns()           0b630eeffc932fb564f57d6d12c687e5
--   public.confirm_transfer_received(uuid,uuid)     a009719657758db9d117d91108b09cbd
--   public.attach_transfer_evidence(uuid,text)      7d98e6471a7e3c58199840804231304d
--   public.mark_transfer_sent(uuid,uuid,text)       d9addfdbfbddd193026e319c23d82535
--   public.mark_transfer_sent(uuid,uuid)            f7a463220fd62029753925c920c72872  (171 never touches it)
-- WHAT: restores the four bodies VERBATIM (the production pg_get_functiondef text read from a_sprint_prod_template,
--   byte for byte — not an older repo migration). CREATE OR REPLACE keeps the grants, owners and COMMENTs, which 171
--   never changed. Then VERIFIES inside the same transaction that md5(pg_get_functiondef) of all five routines equals
--   production and that their grants, SECURITY DEFINER and search_path are production's. Any mismatch RAISEs, so a
--   partial or drifted rollback changes nothing.
-- STACKING GUARD: before restoring, each routine must be either 171's body (md5s below) or already production's.
--   Any other body means a LATER migration redefined it; this file then refuses (rolling back 171 would silently
--   revert that later change — roll the later one back first).
-- KEEPS: every row. 171 wrote no data; transfers marked sent while 171 was live keep the (validated) paths they stored.
-- AFTER ROLLBACK: the five refusals lose their HINT/DETAIL (messages were never changed, so text matchers keep
--   working; a client that keys on the hints falls back to its text/code path), and mark_transfer_sent again stores
--   ANY evidence path unchecked (the pre-171 defect, private-evidence/A-sprint-20261021/a2/p2/01_repro.out).
-- ORDER: independent of the 154–156 rollbacks and of 157 (171 touches only these four public routines).
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $guard171rb$
DECLARE
  v_bad text;
BEGIN
  -- mark_transfer_sent's production body contains an em dash (U+2014): byte-identity needs a UTF8 client
  IF current_setting('client_encoding') <> 'UTF8' THEN
    RAISE EXCEPTION '171 rollback refused: client_encoding is %, UTF8 required. Nothing changed.', current_setting('client_encoding')
      USING ERRCODE = 'P0001';
  END IF;
  SELECT string_agg(v.sig || ' md5 ' || coalesce(md5(pg_get_functiondef(pg_catalog.to_regprocedure(v.sig))), '<missing>'), '; ')
    INTO v_bad
    FROM (VALUES ('public.guard_transfer_state_columns()',       '3604ee46775d173036efd47a4d121ed9', '0b630eeffc932fb564f57d6d12c687e5'),
                 ('public.confirm_transfer_received(uuid,uuid)', '2628bda3533c447295ae153e3e276f9a', 'a009719657758db9d117d91108b09cbd'),
                 ('public.attach_transfer_evidence(uuid,text)',  'f6e1241aac88d6c58ab932d75c01a565', '7d98e6471a7e3c58199840804231304d'),
                 ('public.mark_transfer_sent(uuid,uuid,text)',   'e1886099b66b0df8e2648be63fa6c8f0', 'd9addfdbfbddd193026e319c23d82535'),
                 ('public.mark_transfer_sent(uuid,uuid)',        'f7a463220fd62029753925c920c72872', 'f7a463220fd62029753925c920c72872')) v(sig, md5_171, md5_prod)
   WHERE md5(pg_get_functiondef(pg_catalog.to_regprocedure(v.sig))) IS DISTINCT FROM v.md5_171
     AND md5(pg_get_functiondef(pg_catalog.to_regprocedure(v.sig))) IS DISTINCT FROM v.md5_prod;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '171 rollback refused (nothing changed): a routine is neither 171''s body nor production''s — a later migration redefined it; roll that back first: %', v_bad
      USING ERRCODE = 'P0001';
  END IF;
END
$guard171rb$;

-- ── production bodies, verbatim ─────────────────────────────────────────────
-- 1. guard_transfer_state_columns (production md5 0b630eeffc932fb564f57d6d12c687e5)
CREATE OR REPLACE FUNCTION public.guard_transfer_state_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_setting('app.bypass_transfer_guard', true) = 'on' THEN RETURN NEW; END IF;

  IF NEW.status               IS DISTINCT FROM OLD.status
  OR NEW.seller_id            IS DISTINCT FROM OLD.seller_id
  OR NEW.buyer_id             IS DISTINCT FROM OLD.buyer_id
  OR NEW.payment_id           IS DISTINCT FROM OLD.payment_id
  OR NEW.listing_id           IS DISTINCT FROM OLD.listing_id
  OR NEW.seller_sent_at       IS DISTINCT FROM OLD.seller_sent_at
  OR NEW.buyer_confirmed_at   IS DISTINCT FROM OLD.buyer_confirmed_at
  OR NEW.disputed_at          IS DISTINCT FROM OLD.disputed_at
  OR NEW.dispute_resolution   IS DISTINCT FROM OLD.dispute_resolution
  OR NEW.dispute_resolved_at  IS DISTINCT FROM OLD.dispute_resolved_at
  OR NEW.dispute_resolved_by  IS DISTINCT FROM OLD.dispute_resolved_by
  OR NEW.payout_released_at   IS DISTINCT FROM OLD.payout_released_at
  OR NEW.stripe_transfer_id   IS DISTINCT FROM OLD.stripe_transfer_id
  OR NEW.payout_hold_until    IS DISTINCT FROM OLD.payout_hold_until
  OR NEW.payout_review_status IS DISTINCT FROM OLD.payout_review_status
  OR NEW.payout_risk_tier     IS DISTINCT FROM OLD.payout_risk_tier
  OR NEW.payout_reason_codes  IS DISTINCT FROM OLD.payout_reason_codes
  OR NEW.auto_release_at      IS DISTINCT FROM OLD.auto_release_at
  OR NEW.expires_at           IS DISTINCT FROM OLD.expires_at
  OR NEW.expired_at           IS DISTINCT FROM OLD.expired_at
  THEN
    RAISE EXCEPTION 'Cannot directly modify transfer state columns. Use the appropriate RPC.';
  END IF;

  IF OLD.transfer_evidence_path IS NOT NULL
     AND NEW.transfer_evidence_path IS DISTINCT FROM OLD.transfer_evidence_path THEN
    RAISE EXCEPTION 'transfer_evidence_path is append-only.';
  END IF;
  IF OLD.dispute_evidence_path IS NOT NULL
     AND NEW.dispute_evidence_path IS DISTINCT FROM OLD.dispute_evidence_path THEN
    RAISE EXCEPTION 'dispute_evidence_path is append-only.';
  END IF;
  RETURN NEW;
END; $function$

;

-- 2. confirm_transfer_received (production md5 a009719657758db9d117d91108b09cbd)
CREATE OR REPLACE FUNCTION public.confirm_transfer_received(p_transfer_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_buyer_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, buyer_id INTO v_status, v_buyer_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the buyer can confirm transfer receipt.'; END IF;
  IF v_status <> 'seller_sent' THEN RAISE EXCEPTION 'Transfer cannot be confirmed from current status: %.', v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET status='buyer_confirmed', buyer_confirmed_at=now() WHERE id=p_transfer_id;
END; $function$

;

-- 3. attach_transfer_evidence (production md5 7d98e6471a7e3c58199840804231304d)
CREATE OR REPLACE FUNCTION public.attach_transfer_evidence(p_transfer_id uuid, p_transfer_evidence_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid; v_status text; v_seller uuid; v_path text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_transfer_evidence_path is null or p_transfer_evidence_path = '' then
    raise exception 'precondition_failed: evidence path is required' using errcode = 'P0001';
  end if;

  select t.status, t.seller_id, t.transfer_evidence_path
    into v_status, v_seller, v_path
    from public.transfers t
   where t.id = p_transfer_id
     for update;
  if not found then raise exception 'Transfer not found.'; end if;
  if v_seller is distinct from v_caller then
    raise exception 'insufficient_privilege: only the seller can attach evidence' using errcode = '42501';
  end if;
  if v_status <> 'seller_sent' then
    raise exception 'precondition_failed: evidence can only be attached to a sent transfer (status: %)', v_status
      using errcode = 'P0001';
  end if;

  -- The path must be the caller's own object, in the evidence folder, and REAL:
  -- a dangling path would record proof that cannot be fetched.
  if pg_catalog.split_part(p_transfer_evidence_path, '/', 1) <> v_caller::text then
    raise exception 'precondition_failed: evidence path must be inside the caller''s own folder' using errcode = 'P0001';
  end if;
  if p_transfer_evidence_path not like '%/transfer-evidence/%' then
    raise exception 'precondition_failed: evidence path must be under transfer-evidence/' using errcode = 'P0001';
  end if;
  if not exists (select 1 from storage.objects o
                  where o.bucket_id = 'proof-docs' and o.name = p_transfer_evidence_path) then
    raise exception 'precondition_failed: no such object in proof-docs' using errcode = 'P0001';
  end if;

  -- Same path twice is the retry of a successful attach: answer, write nothing.
  if v_path is not null and v_path = p_transfer_evidence_path then
    return jsonb_build_object('outcome', 'already_attached', 'status', v_status,
                              'transfer_evidence_path', v_path, 'evidence_replaced', false);
  end if;

  -- NO BYPASS. The guard is left armed on purpose: null -> value passes it, and a
  -- second attach with a DIFFERENT path is refused by the guard itself
  -- ('transfer_evidence_path is append-only.'). The append-only rule is not
  -- weakened anywhere in this migration.
  update public.transfers t
     set transfer_evidence_path = p_transfer_evidence_path
   where t.id = p_transfer_id;

  return jsonb_build_object('outcome', 'attached', 'status', v_status,
                            'transfer_evidence_path', p_transfer_evidence_path, 'evidence_replaced', false);
end;
$function$

;

-- 4. mark_transfer_sent(uuid,uuid,text) (production md5 d9addfdbfbddd193026e319c23d82535)
CREATE OR REPLACE FUNCTION public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid, p_transfer_evidence_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid; v_status text; v_seller uuid; v_path text; v_sent timestamptz;
begin
  v_caller := auth.uid();
  if v_caller is null and public.request_is_service_role() then v_caller := p_user_id; end if;
  if v_caller is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  select t.status, t.seller_id, t.transfer_evidence_path, t.seller_sent_at
    into v_status, v_seller, v_path, v_sent
    from public.transfers t
   where t.id = p_transfer_id
     for update;                                   -- two concurrent retries serialize here
  if not found then raise exception 'Transfer not found.'; end if;
  if v_seller is distinct from v_caller then
    raise exception 'Only the seller can mark a transfer as sent.';
  end if;

  -- ALREADY SENT: answer with what is recorded, write nothing. This is the
  -- lost-response retry — with no path, the same path, or a DIFFERENT path.
  -- Accepted proof is never replaced, so a second upload stays an orphan the
  -- seller may delete under the owner-delete policy. Because no UPDATE happens,
  -- the transfer-sent notification triggers do not fire a second time.
  if v_status = 'seller_sent' then
    if v_path is null and p_transfer_evidence_path is not null then
      -- Do NOT let mark-sent become a silent backfill route; §2 is the explicit one.
      raise exception 'precondition_failed: transfer already sent without evidence — use attach_transfer_evidence'
        using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'outcome', 'already_sent', 'status', v_status, 'seller_sent_at', v_sent,
      'transfer_evidence_path', v_path, 'evidence_replaced', false);
  end if;

  -- Any other status is a genuine conflict and still raises, message unchanged.
  if v_status <> 'pending' then
    raise exception 'Transfer cannot be marked as sent from current status: %.', v_status;
  end if;

  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers t
     set status = 'seller_sent',
         seller_sent_at = pg_catalog.now(),
         auto_release_at = pg_catalog.now() + interval '72 hours',
         transfer_evidence_path = coalesce(p_transfer_evidence_path, t.transfer_evidence_path)
   where t.id = p_transfer_id
   returning t.seller_sent_at, t.transfer_evidence_path into v_sent, v_path;

  return jsonb_build_object(
    'outcome', 'transitioned', 'status', 'seller_sent', 'seller_sent_at', v_sent,
    'transfer_evidence_path', v_path, 'evidence_replaced', false);
end;
$function$

;

-- ── verification (inside the transaction: a mismatch aborts the whole rollback) ─
DO $verify171$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(v.sig || ' md5 ' || coalesce(md5(pg_get_functiondef(p.oid)), '<missing>') || ' (production ' || v.prod_md5 || ')'
                    || ' acl=' || coalesce(array_to_string(p.proacl, ','), '<null>') || ' secdef=' || coalesce(p.prosecdef::text, '<missing>')
                    || ' config=' || coalesce(array_to_string(p.proconfig, ','), '<null>'), '; ')
    INTO v_bad
    FROM (VALUES ('public.guard_transfer_state_columns()',       '0b630eeffc932fb564f57d6d12c687e5', 'postgres=X/postgres,service_role=X/postgres',                         false, 'search_path=public'),
                 ('public.confirm_transfer_received(uuid,uuid)', 'a009719657758db9d117d91108b09cbd', 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres', true,  'search_path=public'),
                 ('public.attach_transfer_evidence(uuid,text)',  '7d98e6471a7e3c58199840804231304d', 'postgres=X/postgres,authenticated=X/postgres',                          true,  'search_path=""'),
                 ('public.mark_transfer_sent(uuid,uuid,text)',   'd9addfdbfbddd193026e319c23d82535', 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres', true,  'search_path=""'),
                 ('public.mark_transfer_sent(uuid,uuid)',        'f7a463220fd62029753925c920c72872', 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres', true,  'search_path=""')) v(sig, prod_md5, acl, secdef, config)
    LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig)
   WHERE md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM v.prod_md5
      OR array_to_string(p.proacl, ',') IS DISTINCT FROM v.acl
      OR p.prosecdef IS DISTINCT FROM v.secdef
      OR array_to_string(p.proconfig, ',') IS DISTINCT FROM v.config;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '171 rollback verification failed (nothing changed): %', v_bad USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '171 rollback verified: all five routines = production md5s, grants, definer and search_path';
END
$verify171$;

COMMIT;

-- Read-only re-check after COMMIT (expect five rows, ok = true):
SELECT v.sig, md5(pg_get_functiondef(pg_catalog.to_regprocedure(v.sig))) = v.prod_md5 AS ok
  FROM (VALUES ('public.guard_transfer_state_columns()',       '0b630eeffc932fb564f57d6d12c687e5'),
               ('public.confirm_transfer_received(uuid,uuid)', 'a009719657758db9d117d91108b09cbd'),
               ('public.attach_transfer_evidence(uuid,text)',  '7d98e6471a7e3c58199840804231304d'),
               ('public.mark_transfer_sent(uuid,uuid,text)',   'd9addfdbfbddd193026e319c23d82535'),
               ('public.mark_transfer_sent(uuid,uuid)',        'f7a463220fd62029753925c920c72872')) v(sig, prod_md5);
