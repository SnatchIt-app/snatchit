-- ============================================================================
-- 20261021131000_transfer_refusal_hints_and_evidence_path.sql — registry 171 (pgTAP 241).
-- DRAFT, APPLIED NOWHERE: not for apply before 2026-10-28 03:47:04Z (four live listings) and before build 29's
-- review settles; owner-gated. (STATUS.md item 88: no release-bound change to listing/bid/transfer paths while
-- the four are live and build 29 is in review.) Prepared and tested on local production-replay clones only.
--
-- WHY.
--   (a) Five transfer refusals reach the app, the web and the confirm-and-release edge with NO hint, so clients key
--       on message text (sprint-control/SERVER_REFUSAL_CATALOGUE_C_20261021.md §7 P1: SNT-1, SNT-2, PRF-1, PRF-2,
--       CNF-1; e.g. src/lib/transfer/markSent.ts PROOF_LITERALS matches an em dash). Each now carries a stable HINT
--       (and DETAIL = the status where the message embeds one). MESSAGES ARE BYTE-IDENTICAL and SQLSTATEs unchanged
--       (P0001 everywhere: set explicitly where production set it, the default where it did not), so every text
--       matcher keeps working (app markSent.ts, web/src/lib/transfers.ts mapTransferError, the edge's
--       includes('buyer_confirmed' | 'auto_released') at confirm-and-release/index.ts:207-208).
--   (b) Catalogue finding 8: mark_transfer_sent(uuid,uuid,text) stored ANY evidence path, while
--       attach_transfer_evidence validates it. REPRODUCED on a replay clone before this file was written
--       (private-evidence/A-sprint-20261021/a2/p2/01_repro.out): a seller marked their own pending transfer sent
--       with ANOTHER seller's proof path (stored; the seller's read of that private proof-docs object went 0 -> 1
--       through the "proof-docs transfer party read" policy, and their buyer gains the same read), with a dangling
--       path, and with their own non-evidence object — while attach refused the foreign path. A stored path also
--       clears the payout engine's EVIDENCE_MISSING signal (supabase/functions/_shared/payout-policy.ts:70) without
--       any upload. The web already guards this client-side (web/src/lib/evidence-path.ts isOwnEvidencePath); the
--       app calls the RPC directly, and any seller session can.
--
-- WHAT. Every body below is the PRODUCTION pg_get_functiondef text (read from a_sprint_prod_template, fingerprint-
--   identical to production 2026-10-21; prod_functions.json md5s) with only the lines named here changed.
--   1. public.guard_transfer_state_columns() (trigger; production md5 0b630eeffc932fb564f57d6d12c687e5):
--      'transfer_evidence_path is append-only.' -> HINT PROOF_ALREADY_ATTACHED (PRF-1; reached by attach's
--      unbypassed UPDATE and by any direct write). Its other two refusals are untouched.
--   2. public.confirm_transfer_received(uuid,uuid) (production md5 a009719657758db9d117d91108b09cbd) — the function
--      the confirm-and-release edge calls (index.ts:197, service role, p_user_id = the buyer):
--      'Transfer cannot be confirmed from current status: %.' -> HINT TRANSFER_NOT_CONFIRMABLE, DETAIL = status (CNF-1).
--   3. public.attach_transfer_evidence(uuid,text) (production md5 7d98e6471a7e3c58199840804231304d):
--      'precondition_failed: evidence can only be attached to a sent transfer (status: %)' -> HINT TRANSFER_NOT_SENT,
--      DETAIL = status (PRF-2). Its four evidence-path refusals ('evidence path is required', '...inside the
--      caller''s own folder', '...under transfer-evidence/', 'no such object in proof-docs') had no hint and gain
--      HINT PROOF_PATH_INVALID (PRF-4..7), so attach and mark-sent refuse an invalid path identically.
--   4. public.mark_transfer_sent(uuid,uuid,text) (production md5 d9addfdbfbddd193026e319c23d82535):
--      SNT-1 'precondition_failed: transfer already sent without evidence — use attach_transfer_evidence'
--        -> HINT TRANSFER_SENT_WITHOUT_PROOF (errcode P0001 kept);
--      SNT-2 'Transfer cannot be marked as sent from current status: %.' -> HINT TRANSFER_NOT_PENDING, DETAIL = status;
--      NEW: a NON-NULL p_transfer_evidence_path must pass EXACTLY attach's checks, in attach's order and with attach's
--        messages and errcode, HINT PROOF_PATH_INVALID: '' -> 'evidence path is required'; first segment = the
--        caller (auth.uid(), or p_user_id on the service path — the seller once the seller check has passed);
--        LIKE '%/transfer-evidence/%'; an object in storage.objects with bucket_id 'proof-docs'.
--      Placement: after the status check and before the write — the same place attach validates (after its status
--        check). So: NULL keeps today's sent-without-evidence flow; the already-sent retry (140's contract) still
--        answers already_sent and writes nothing whatever path it carries (pgTAP 050 sends a non-object path there);
--        SNT-1 and SNT-2 still win over a bad path; a refused call writes nothing and notifies nobody.
--   5. public.mark_transfer_sent(uuid,uuid) (production md5 f7a463220fd62029753925c920c72872) is NOT redefined: it
--      only delegates with a NULL path, so its refusals are (4)'s and carry the same hints (pgTAP 241 H6, H9, C8).
--   The validation is inlined, not a shared helper: a helper would be a new public function (four-file rule) for
--   no behavioural gain. Grants, owners, SECURITY DEFINER, search_path and COMMENTs are untouched (CREATE OR REPLACE
--   keeps ACL and comment; the post-check below verifies the ACLs and config).
--
-- CLIENT CONTRACT (new; text matching keeps working):
--   hint TRANSFER_SENT_WITHOUT_PROOF            mark_transfer_sent            route to "Add proof" (attach)
--   hint TRANSFER_NOT_PENDING  + detail status  mark_transfer_sent (both)     status moved on; re-read
--   hint PROOF_PATH_INVALID                     mark_transfer_sent, attach    re-upload the screenshot
--   hint PROOF_ALREADY_ATTACHED                 attach (guard trigger)        proof exists, cannot be replaced
--   hint TRANSFER_NOT_SENT     + detail status  attach_transfer_evidence      not eligible now; re-read
--   hint TRANSFER_NOT_CONFIRMABLE + detail status  confirm_transfer_received (edge forwards message only today;
--                                                 C/A may later forward hint as the edge's JSON code)
--
-- CALLERS (enumerated; each pinned with valid input in pgTAP 241 section C, with and without this file):
--   app e46fc2031b595c02a157fd9fd448065eb0956045 (and C's next 61edd69f, same call sites):
--     app/transfer/send/[id].tsx:225 mark_transfer_sent {p_transfer_id, p_user_id, p_transfer_evidence_path} after
--     uploading '<uid>/transfer-evidence/<stamp>.<ext>' to proof-docs (src/lib/media/uploadFlow.ts:135-136,
--     send/[id].tsx:131-136; runMarkSent returns upload_failed before calling with an empty path);
--     send/[id].tsx:290 attach_transfer_evidence; app/transfer/receive/[id].tsx -> the confirm-and-release edge.
--   web (bfc5cf97): web/src/lib/transfers.ts:251 mark_transfer_sent (3 keys, path pre-checked by isOwnEvidencePath,
--     uploaded by evidence-upload.ts:100); confirmReceipt -> the edge.
--   edge: supabase/functions/confirm-and-release/index.ts:197 confirm_transfer_received (service role). No edge calls
--     mark_transfer_sent or attach_transfer_evidence.
--   console: admin/ has no caller (only a comment, admin/src/lib/format.ts:261). SQL: no other function calls these
--     (pg_proc prosrc scan on the replay). Scripts: scripts/sandbox/20_matrix.sh:115 and
--     scripts/release/payments_rc_prod_order_rehearsal.sh:201 use the 2-arg overload (NULL path: unchanged).
--
-- CI (four-file rule): NO change. No new table, function, trigger or policy, and no grant change: the five routines
--   already have grant-decision rows (supabase/ci/assert_public_table_grant_decisions.sql:414 guard
--   'no-client-execute'; :489 confirm, :495 attach, :503-504 mark (both) 'authenticated-execute'); the Gate-2 census
--   counts objects in public (.github/workflows/ci.yml:605-608, EXPECT_* at :661/:688/:691/:701) and CREATE OR
--   REPLACE adds none; supabase/ci/expected_grants.txt lists table grants only (ci.yml:727-733) and no table grant
--   changes.
-- ROLLBACK: supabase/rollbacks/20261021131000_transfer_refusal_hints_and_evidence_path_rollback.sql restores the four
--   production bodies VERBATIM and verifies md5(pg_get_functiondef) of all five routines = production, inside its
--   transaction (a partial rollback raises and changes nothing).
-- VERIFY (read-only; expected after apply, PostgreSQL 17):
--   select p.oid::regprocedure, md5(pg_get_functiondef(p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('mark_transfer_sent','attach_transfer_evidence','confirm_transfer_received','guard_transfer_state_columns');
--   -- attach_transfer_evidence(uuid,text)    f6e1241aac88d6c58ab932d75c01a565  (production 7d98e6471a7e3c58199840804231304d)
--   -- confirm_transfer_received(uuid,uuid)   2628bda3533c447295ae153e3e276f9a  (production a009719657758db9d117d91108b09cbd)
--   -- guard_transfer_state_columns()         3604ee46775d173036efd47a4d121ed9  (production 0b630eeffc932fb564f57d6d12c687e5)
--   -- mark_transfer_sent(uuid,uuid)          f7a463220fd62029753925c920c72872  (= production, not redefined)
--   -- mark_transfer_sent(uuid,uuid,text)     e1886099b66b0df8e2648be63fa6c8f0  (production d9addfdbfbddd193026e319c23d82535)
-- FAILURE BEHAVIOUR: one transaction. The client_encoding guard, the pre-flight (live bodies must be production's,
--   by md5(prosrc)), a lock timeout, the post-check or any error leaves the database exactly as it was.
-- EVIDENCE LIMITS: the replay restores 8 app schemas, not storage: storage.objects/buckets and the proof-docs
--   policies on the clones come from the chain (replay/60 supplement), not production (BE-37 §1.4 limit 2).
-- OWNER APPROVAL POINT: applying this file (after the date and build-29 conditions above) is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 0. guards (read-only) ───────────────────────────────────────────────────
DO $enc171$
BEGIN
  -- SNT-1 contains an em dash (U+2014); a non-UTF8 client would store other bytes and break byte-identity.
  IF current_setting('client_encoding') <> 'UTF8' THEN
    RAISE EXCEPTION '171 refused: client_encoding is %, UTF8 required. Nothing changed.', current_setting('client_encoding')
      USING ERRCODE = 'P0001';
  END IF;
END
$enc171$;

DO $pre171$
DECLARE
  v_bad text;
  v_n int; v_owner int; v_prefix int; v_object int;
BEGIN
  -- the live bodies must be the production bodies this file was derived from (md5 of the stored source)
  SELECT string_agg(v.sig || ' prosrc md5 ' || coalesce(md5(p.prosrc), '<missing>') || ' <> ' || v.prosrc_md5, '; ')
    INTO v_bad
    FROM (VALUES ('public.guard_transfer_state_columns()',              'c423ef62372e43e5c4c91e5e83976782'),
                 ('public.confirm_transfer_received(uuid,uuid)',        '00d318aa449bfb4ed8940c04c7a0b345'),
                 ('public.attach_transfer_evidence(uuid,text)',         '67615b89040a9f60dd6082d1cf54cbcd'),
                 ('public.mark_transfer_sent(uuid,uuid,text)',          '17453329765e9e0787732fd61846a399'),
                 ('public.mark_transfer_sent(uuid,uuid)',               'd816c53e9e1e77e7de8d432d7ecf9680')) v(sig, prosrc_md5)
    LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig)
   WHERE md5(p.prosrc) IS DISTINCT FROM v.prosrc_md5;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '171 pre-flight refused: a routine differs from the production body this file was derived from: %. Rebase 171 on the live body. Nothing changed.', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  -- informational only (171 changes no stored row): stored evidence paths that 171 would now refuse
  SELECT count(*)::int,
         count(*) FILTER (WHERE pg_catalog.split_part(t.transfer_evidence_path, '/', 1) <> t.seller_id::text)::int,
         count(*) FILTER (WHERE t.transfer_evidence_path NOT LIKE '%/transfer-evidence/%')::int,
         count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM storage.objects o
                                             WHERE o.bucket_id = 'proof-docs' AND o.name = t.transfer_evidence_path))::int
    INTO v_n, v_owner, v_prefix, v_object
    FROM public.transfers t
   WHERE t.transfer_evidence_path IS NOT NULL;
  RAISE NOTICE '171 pre-flight: bodies = production. Stored evidence paths: % total; % outside the seller''s folder, % outside transfer-evidence/, % with no proof-docs object (counts only; no row is changed)',
    v_n, v_owner, v_prefix, v_object;
END
$pre171$;

-- Capture each routine's grants, definer flag and search_path BEFORE the replacement, so the post-check proves
-- this file changed none of them in WHATEVER environment it runs in. (On production these equal the values in the
-- post-check comment below; CI's fresh chain carries different, pre-existing ACLs - BE-37 - which 171 must not touch.)
CREATE TEMP TABLE m171_pre ON COMMIT DROP AS
SELECT v.sig, array_to_string(p.proacl, ',') AS acl, p.prosecdef AS secdef, array_to_string(p.proconfig, ',') AS config
  FROM (VALUES ('public.guard_transfer_state_columns()'),
               ('public.confirm_transfer_received(uuid,uuid)'),
               ('public.attach_transfer_evidence(uuid,text)'),
               ('public.mark_transfer_sent(uuid,uuid,text)'),
               ('public.mark_transfer_sent(uuid,uuid)')) v(sig)
  JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig);

-- ── 1. guard_transfer_state_columns: PRF-1 hint ─────────────────────────────
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
    RAISE EXCEPTION 'transfer_evidence_path is append-only.'
      USING HINT = 'PROOF_ALREADY_ATTACHED';
  END IF;
  IF OLD.dispute_evidence_path IS NOT NULL
     AND NEW.dispute_evidence_path IS DISTINCT FROM OLD.dispute_evidence_path THEN
    RAISE EXCEPTION 'dispute_evidence_path is append-only.';
  END IF;
  RETURN NEW;
END; $function$

;

-- ── 2. confirm_transfer_received: CNF-1 hint + detail (the confirm-and-release edge calls this) ─
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
  IF v_status <> 'seller_sent' THEN RAISE EXCEPTION 'Transfer cannot be confirmed from current status: %.', v_status
    USING HINT = 'TRANSFER_NOT_CONFIRMABLE', DETAIL = v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET status='buyer_confirmed', buyer_confirmed_at=now() WHERE id=p_transfer_id;
END; $function$

;

-- ── 3. attach_transfer_evidence: PRF-2 hint + detail; PROOF_PATH_INVALID on its path refusals ─
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
    raise exception 'precondition_failed: evidence path is required' using errcode = 'P0001', hint = 'PROOF_PATH_INVALID';
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
      using errcode = 'P0001', hint = 'TRANSFER_NOT_SENT', detail = v_status;
  end if;

  -- The path must be the caller's own object, in the evidence folder, and REAL:
  -- a dangling path would record proof that cannot be fetched.
  if pg_catalog.split_part(p_transfer_evidence_path, '/', 1) <> v_caller::text then
    raise exception 'precondition_failed: evidence path must be inside the caller''s own folder' using errcode = 'P0001', hint = 'PROOF_PATH_INVALID';
  end if;
  if p_transfer_evidence_path not like '%/transfer-evidence/%' then
    raise exception 'precondition_failed: evidence path must be under transfer-evidence/' using errcode = 'P0001', hint = 'PROOF_PATH_INVALID';
  end if;
  if not exists (select 1 from storage.objects o
                  where o.bucket_id = 'proof-docs' and o.name = p_transfer_evidence_path) then
    raise exception 'precondition_failed: no such object in proof-docs' using errcode = 'P0001', hint = 'PROOF_PATH_INVALID';
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

-- ── 4. mark_transfer_sent(uuid,uuid,text): SNT-1/SNT-2 hints; attach's path validation ─
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
        using errcode = 'P0001', hint = 'TRANSFER_SENT_WITHOUT_PROOF';
    end if;
    return jsonb_build_object(
      'outcome', 'already_sent', 'status', v_status, 'seller_sent_at', v_sent,
      'transfer_evidence_path', v_path, 'evidence_replaced', false);
  end if;

  -- Any other status is a genuine conflict and still raises, message unchanged.
  if v_status <> 'pending' then
    raise exception 'Transfer cannot be marked as sent from current status: %.', v_status
      using hint = 'TRANSFER_NOT_PENDING', detail = v_status;
  end if;

  -- 171: a non-NULL evidence path is stored only if it passes EXACTLY attach_transfer_evidence's checks
  -- (same order, messages and errcode; HINT PROOF_PATH_INVALID). NULL = marked sent without evidence (unchanged).
  if p_transfer_evidence_path is not null then
    if p_transfer_evidence_path = '' then
      raise exception 'precondition_failed: evidence path is required' using errcode = 'P0001', hint = 'PROOF_PATH_INVALID';
    end if;
    if pg_catalog.split_part(p_transfer_evidence_path, '/', 1) <> v_caller::text then
      raise exception 'precondition_failed: evidence path must be inside the caller''s own folder' using errcode = 'P0001', hint = 'PROOF_PATH_INVALID';
    end if;
    if p_transfer_evidence_path not like '%/transfer-evidence/%' then
      raise exception 'precondition_failed: evidence path must be under transfer-evidence/' using errcode = 'P0001', hint = 'PROOF_PATH_INVALID';
    end if;
    if not exists (select 1 from storage.objects o
                    where o.bucket_id = 'proof-docs' and o.name = p_transfer_evidence_path) then
      raise exception 'precondition_failed: no such object in proof-docs' using errcode = 'P0001', hint = 'PROOF_PATH_INVALID';
    end if;
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

-- ── 5. post-check (inside the transaction: a mismatch aborts everything) ────
DO $post171$
DECLARE
  v_bad text;
BEGIN
  -- Production values (verified on the production replay; informational): guard_transfer_state_columns()
  --   postgres=X,service_role=X / secdef false / search_path=public; confirm_transfer_received(uuid,uuid)
  --   postgres,authenticated,service_role / true / search_path=public; attach_transfer_evidence(uuid,text)
  --   postgres,authenticated / true / search_path=""; mark_transfer_sent (both) postgres,authenticated,service_role /
  --   true / search_path="". The check below compares with the captured pre-apply state, not these literals.
  SELECT string_agg(v.sig || ' acl ' || coalesce(v.acl, '<null>') || ' -> ' || coalesce(array_to_string(p.proacl, ','), '<null>')
                    || ' secdef ' || coalesce(v.secdef::text, '<null>') || ' -> ' || coalesce(p.prosecdef::text, '<missing>')
                    || ' config ' || coalesce(v.config, '<null>') || ' -> ' || coalesce(array_to_string(p.proconfig, ','), '<null>'), '; ')
    INTO v_bad
    FROM m171_pre v
    LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig)
   WHERE array_to_string(p.proacl, ',') IS DISTINCT FROM v.acl
      OR p.prosecdef IS DISTINCT FROM v.secdef
      OR array_to_string(p.proconfig, ',') IS DISTINCT FROM v.config;
  IF (SELECT count(*) FROM m171_pre) <> 5 THEN
    RAISE EXCEPTION '171 post-check failed (nothing changed): expected 5 captured routines' USING ERRCODE = 'P0001';
  END IF;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '171 post-check failed (nothing changed): grant, definer or search_path changed by this file: %', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = 'public.mark_transfer_sent(uuid,uuid)'::regprocedure)
       IS DISTINCT FROM 'd816c53e9e1e77e7de8d432d7ecf9680' THEN
    RAISE EXCEPTION '171 post-check failed (nothing changed): the 2-arg mark_transfer_sent wrapper changed' USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '171 applied: 4 bodies replaced; grants, definer and search_path unchanged from the pre-apply state; 2-arg wrapper untouched';
END
$post171$;

COMMIT;
