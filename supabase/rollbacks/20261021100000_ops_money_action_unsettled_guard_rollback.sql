-- ============================================================================
-- ROLLBACK for 20261021100000_ops_money_action_unsettled_guard.sql (registry 157, pgTAP 224).
-- Pre-157 state = production 2026-10-21 (prod_ops_action_defs.json / prod_functions.json, A's read-only snapshot):
--   ops.execute_action  md5 e59c158453adabc662431cac9dca1040
--   ops.approve_action  md5 5de6235288b38792c31dca3e6b3f89af
--   ops.order_detail    md5 04d4e05f6c533fa428c4f7123d20eba8
--   no ops.action_money_unsettled_uidx; no ops.money_order_id / money_unsettled_blocker / expire_stale_money_approvals.
-- STACKING GUARD (first statement, read-only; three checks, each RAISEs before anything changes):
--   1. 158 (20261021110000_ops_listing_relist_expected.sql) is written on 157's bodies and redefines ops.action_dispatch.
--      Unless ops.action_dispatch still has production's md5 bfb8b9dcfaace5ff04009f96b6de7bef this file RAISEs 'roll
--      back 158 (20261021110000) first': restoring the production bodies under 158 would silently discard 158's
--      change, and the md5 verification below would still pass.
--   2. Each of the three bodies must carry 157's md5 (applied: execute_action 0da9bc63…, approve_action
--      ddcdcd14…, order_detail 4358f577…) or already its production md5 above (a re-run after a
--      successful rollback is a no-op that re-verifies). Any third body is someone else's change stacked on 157 (a
--      later migration, a hand edit, a comment-only redefinition): RAISE, nothing changed.
--   3. No routine other than 157's own (the three bodies and the three helpers) may reference ops.money_order_id,
--      ops.money_unsettled_blocker or ops.expire_stale_money_approvals: this file drops them. RAISE naming the routine.
-- LOCKS: DROP INDEX takes ACCESS EXCLUSIVE on ops.action (and on the index) from that statement until COMMIT, a brief
--   block of every ops.action read AND write (order_detail, list_actions, the console's lists, execute_action,
--   approve_action, executor_claim, record_action_outcome, detect_refunds) for the rest of this transaction (the three
--   CREATE OR REPLACE FUNCTION and the verification: milliseconds). lock_timeout 3s bounds the wait for the lock itself:
--   an open ops.action reader or writer that does not finish within 3 s fails the rollback, and nothing changes. Run it
--   in a quiet moment, never under an open console session. CREATE OR REPLACE FUNCTION and DROP FUNCTION take no table
--   lock (pg_proc rows; ACCESS SHARE object locks on the schema, language and owner role).
-- WHAT: drops the index; restores the three bodies VERBATIM (the production pg_get_functiondef text, byte for byte —
--   not an older repo migration: the repo chain differs from production in 17 functions); re-states their production
--   ACL (postgres + authenticated EXECUTE); drops the three helpers; then VERIFIES inside the same transaction that
--   md5(pg_get_functiondef(...)) equals the production md5s, that each ACL equals production's, and that the helpers
--   and the index are gone. Any mismatch RAISEs (the message names, per function, which of md5 / ACL differs, with
--   the live value), so a partial or drifted rollback changes nothing.
-- KEEPS: every ops.action row. 'rejected' / reject_reason 'duplicate_unsettled' refusals stay as history (valid
--   rejected rows; reject_reason has no check constraint), and approvals expired by the 157 sweep stay expired
--   (exactly what approve_action would have recorded).
-- AFTER ROLLBACK: duplicate unsettled refund/payout requests are accepted again (the pre-157 defect), and
--   ops.order_detail no longer returns 'unsettled_money_actions' — a console that reads it must fall back to the
--   capped 'actions' list or ops.list_actions (F's documented fallback). The refusal envelope simply stops occurring.
-- ORDER: independent of the 154–156 rollbacks (157 touches only ops.*). If 158 is applied, roll 158 back FIRST (the
--   stacking guard refuses otherwise). Run only under owner approval.
-- ============================================================================
BEGIN;
-- ── stacking guard: refuse (nothing changed) while 158 is applied ───────────
DO $stack157$
DECLARE
  v_md5  text := md5(pg_get_functiondef(to_regprocedure('ops.action_dispatch(ops.action)')));
  v_bad  text;
  v_refs text;
BEGIN
  -- 1. 158 stacked on these bodies
  IF v_md5 IS DISTINCT FROM 'bfb8b9dcfaace5ff04009f96b6de7bef' THEN
    RAISE EXCEPTION '157 rollback refused (nothing changed): ops.action_dispatch md5 % is not production''s bfb8b9dcfaace5ff04009f96b6de7bef; roll back 158 (20261021110000) first', coalesce(v_md5, '<missing>')
      USING ERRCODE = 'P0001';
  END IF;
  -- 2. each body is 157's (applied) or already production's (re-run); a third body is another change on top of 157
  SELECT string_agg(c.sig || ' md5 ' || coalesce(c.live, '<missing>') || ' is neither 157''s ' || c.m157 || ' nor production''s ' || c.prod,
                    '; ' ORDER BY c.sig)
    INTO v_bad
    FROM (SELECT v.sig, v.m157, v.prod, md5(pg_get_functiondef(to_regprocedure(v.sig))) AS live
            FROM (VALUES ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', '0da9bc63acb58f1d76a86f8039c0c877', 'e59c158453adabc662431cac9dca1040'),
                         ('ops.approve_action(uuid,text,text)',                             'ddcdcd1401839910726d20ddd206e40d', '5de6235288b38792c31dca3e6b3f89af'),
                         ('ops.order_detail(uuid)',                                         '4358f577291f84b25986b8904b38ab36', '04d4e05f6c533fa428c4f7123d20eba8')) v(sig, m157, prod)) c
   WHERE c.live IS DISTINCT FROM c.m157 AND c.live IS DISTINCT FROM c.prod;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '157 rollback refused (nothing changed): %; another change sits on top of 157: roll that back first', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  -- 3. nothing but 157's own routines may reference the helpers this file drops
  SELECT string_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ' ORDER BY n.nspname, p.proname)
    INTO v_refs
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
     AND p.prosrc ~ '(money_order_id|money_unsettled_blocker|expire_stale_money_approvals)\s*\('
     AND NOT (n.nspname = 'ops' AND p.proname IN ('execute_action', 'approve_action', 'order_detail',
                                                  'money_order_id', 'money_unsettled_blocker', 'expire_stale_money_approvals'));
  IF v_refs IS NOT NULL THEN
    RAISE EXCEPTION '157 rollback refused (nothing changed): % reference(s) a 157 helper this file drops; roll that change back first', v_refs
      USING ERRCODE = 'P0001';
  END IF;
END
$stack157$;
SET LOCAL lock_timeout = '3s';

DROP INDEX IF EXISTS ops.action_money_unsettled_uidx;

-- ── production bodies, verbatim ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ops.execute_action(p_idempotency_key text, p_action_type text, p_subject_kind text, p_subject_id uuid, p_params jsonb DEFAULT '{}'::jsonb, p_reason text DEFAULT NULL::text, p_expected jsonb DEFAULT NULL::jsonb, p_subject_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_role  text;
  a       ops.action%rowtype;
  v_appr  uuid;
  v_ttl   integer;
  v_res   jsonb;
begin
  perform ops.assert_reader();
  -- The pause switch itself stays operable, so a founder can un-pause from
  -- the console (platform_admin only; audited like every setting change).
  if not (p_action_type = 'setting_set' and p_subject_ref = 'actions_enabled') then
    perform ops.assert_actions_enabled();
  end if;
  v_role := ops.actor_role();

  if p_idempotency_key is null or p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,80}$' then
    raise exception 'invalid_input: idempotency key must be 8-80 chars of [A-Za-z0-9._:-]';
  end if;
  if p_action_type is null or p_action_type not in (
      'case_create','case_assign','case_status','case_priority','case_due','case_note',
      'case_refund_classify','case_refund_obligation',
      'dispute_resolve','payout_release','listing_relist','report_resolve',
      'user_restrict','user_unrestrict','refund_execute','job_retry','setting_set') then
    raise exception 'invalid_input: unknown action_type %', coalesce(p_action_type, '(null)');
  end if;
  if p_subject_kind is null or p_subject_kind not in ('case','payment','transfer','listing','user','report','job','setting','none') then
    raise exception 'invalid_input: unknown subject_kind %', coalesce(p_subject_kind, '(null)');
  end if;

  -- action ↔ subject pairing (a case verb may only target a case, etc.)
  if not (case p_action_type
            when 'case_create'     then p_subject_kind in ('none','payment','transfer','listing','user','report','job')
            when 'dispute_resolve' then p_subject_kind = 'transfer'
            when 'payout_release'  then p_subject_kind = 'transfer'
            when 'listing_relist'  then p_subject_kind = 'listing'
            when 'report_resolve'  then p_subject_kind = 'report'
            when 'user_restrict'   then p_subject_kind = 'user'
            when 'user_unrestrict' then p_subject_kind = 'user'
            when 'refund_execute'  then p_subject_kind = 'payment'
            when 'job_retry'       then p_subject_kind = 'job'
            when 'setting_set'     then p_subject_kind = 'setting'
            else p_subject_kind = 'case' end) then
    raise exception 'invalid_input: % cannot target a %', p_action_type, p_subject_kind;
  end if;
  if p_subject_id is null and p_action_type not in ('case_create','job_retry','setting_set') then
    raise exception 'invalid_input: subject_id required for %', p_action_type;
  end if;

  -- idempotency: the same key always returns the same action
  select * into a from ops.action where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state,
                              'result', a.result, 'approval_id', a.approval_id);
  end if;

  if not (v_role = any(ops.action_allowed_roles(p_action_type))) then
    raise exception 'insufficient_privilege: % may not perform %', v_role, p_action_type using errcode = '42501';
  end if;
  if p_action_type in ('dispute_resolve','payout_release','listing_relist','report_resolve','user_restrict',
                       'user_unrestrict','refund_execute','setting_set')
     and coalesce(trim(p_reason), '') = '' then
    raise exception 'invalid_input: a reason is required for %', p_action_type;
  end if;

  begin
    insert into ops.action (idempotency_key, action_type, subject_kind, subject_id, subject_ref, params, expected, reason, requested_by)
    values (p_idempotency_key, p_action_type, p_subject_kind, p_subject_id, p_subject_ref,
            coalesce(p_params, '{}'::jsonb), p_expected, nullif(trim(p_reason), ''), v_uid)
    returning * into a;
  exception when unique_violation then
    select * into a from ops.action where idempotency_key = p_idempotency_key;
    return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state,
                              'result', a.result, 'approval_id', a.approval_id);
  end;

  perform ops.audit_write('action.requested', a.subject_kind, a.subject_id, a.subject_ref, a.reason,
                          a.expected, jsonb_build_object('action_type', a.action_type, 'params', a.params),
                          'requested', a.correlation_id, a.id);
  if a.subject_kind = 'case' and a.action_type <> 'case_create' then
    insert into ops.case_event (case_id, actor, kind, data)
    select a.subject_id, v_uid, 'action_requested', jsonb_build_object('action_id', a.id, 'action_type', a.action_type)
     where exists (select 1 from ops."case" where id = a.subject_id);
  end if;

  if ops.action_requires_approval(a.action_type) then
    v_res := ops.action_precheck(a);
    if v_res is not null then
      update ops.action set state = 'rejected', reject_reason = v_res ->> 'reject_reason', result = v_res,
             completed_at = now(), version = version + 1 where id = a.id;
      perform ops.audit_write('action.' || a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.reason,
                              a.expected, v_res, 'rejected', a.correlation_id, a.id);
      return jsonb_build_object('status','rejected','action_id', a.id, 'result', v_res,
                                'reject_reason', v_res ->> 'reject_reason', 'message', v_res ->> 'message');
    end if;
    v_ttl := coalesce((select (value #>> '{}')::integer from ops.setting where key = 'approval_ttl_hours'), 72);
    insert into ops.approval (action_id, action_hash, requested_by, expires_at)
    values (a.id, ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params),
            v_uid, now() + make_interval(hours => v_ttl))
    returning id into v_appr;
    update ops.action set state = 'awaiting_approval', approval_id = v_appr, version = version + 1 where id = a.id;
    return jsonb_build_object('status','awaiting_approval','action_id', a.id, 'approval_id', v_appr,
                              'message','a second founder must approve this action');
  end if;

  return ops.action_run(a.id);
end;
$function$
;
REVOKE ALL ON FUNCTION ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION ops.approve_action(p_action_id uuid, p_decision text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  a     ops.action%rowtype;
  ap    ops.approval%rowtype;
begin
  perform ops.assert_role(array['platform_admin']);
  perform ops.assert_actions_enabled();
  if p_decision not in ('approve','deny') then
    raise exception 'invalid_input: decision must be approve or deny';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'invalid_input: a reason is required';
  end if;
  select * into a from ops.action where id = p_action_id for update;
  if not found then
    raise exception 'precondition_failed: action not found';
  end if;
  select * into ap from ops.approval where action_id = a.id and state = 'pending' for update;
  if not found then
    return jsonb_build_object('status','rejected','reject_reason','stale_state','message','no pending approval for this action', 'state', a.state);
  end if;
  if ap.requested_by = v_uid then
    raise exception 'precondition_failed: self_approval — the requester cannot approve their own action';
  end if;
  if ap.expires_at < now() then
    update ops.approval set state = 'expired' where id = ap.id;
    update ops.action set state = 'rejected', reject_reason = 'approval_expired', completed_at = now(), version = version + 1 where id = a.id;
    perform ops.audit_write('approval.expired', a.subject_kind, a.subject_id, a.subject_ref, p_reason, null, null, 'expired', a.correlation_id, a.id);
    return jsonb_build_object('status','rejected','reject_reason','approval_expired');
  end if;
  if ap.action_hash <> ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params) then
    update ops.approval set state = 'stale' where id = ap.id;
    update ops.action set state = 'rejected', reject_reason = 'approval_stale', completed_at = now(), version = version + 1 where id = a.id;
    perform ops.audit_write('approval.stale', a.subject_kind, a.subject_id, a.subject_ref, p_reason, null, null, 'stale', a.correlation_id, a.id);
    return jsonb_build_object('status','rejected','reject_reason','approval_stale','message','the action terms changed after approval was requested');
  end if;

  if p_decision = 'deny' then
    update ops.approval set state = 'denied', decided_by = v_uid, decided_at = now(), reason = p_reason where id = ap.id;
    update ops.action set state = 'rejected', reject_reason = 'denied', completed_at = now(), version = version + 1 where id = a.id;
    perform ops.audit_write('approval.denied', a.subject_kind, a.subject_id, a.subject_ref, p_reason, null,
                            jsonb_build_object('action_id', a.id), 'denied', a.correlation_id, a.id);
    return jsonb_build_object('status','rejected','reject_reason','denied','action_id', a.id);
  end if;

  update ops.approval set state = 'approved', decided_by = v_uid, decided_at = now(), reason = p_reason where id = ap.id;
  perform ops.audit_write('approval.approved', a.subject_kind, a.subject_id, a.subject_ref, p_reason, null,
                          jsonb_build_object('action_id', a.id, 'action_hash', ap.action_hash), 'approved', a.correlation_id, a.id);
  return ops.action_run(a.id);
end;
$function$
;
REVOKE ALL ON FUNCTION ops.approve_action(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ops.approve_action(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION ops.order_detail(p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  p public.payments%rowtype;
  t public.transfers%rowtype;
  v_listing_id uuid;
begin
  perform ops.assert_reader();
  select * into p from public.payments where id = p_payment_id;
  if not found then
    raise exception 'not_found: payment % does not exist', p_payment_id using errcode = 'P0002';
  end if;
  select * into t from public.transfers where payment_id = p.id;
  v_listing_id := p.listing_id;

  return jsonb_build_object(
    'payment',  ops.payment_json(p),
    'transfer', ops.transfer_json(t),
    'listing',  ops.listing_summary(v_listing_id),
    'buyer',    ops.user_summary(p.buyer_id),
    'seller',   ops.user_summary(p.seller_id),
    'disputes', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from public.disputes d
                           where d.payment_id = p.id or (t.id is not null and d.transfer_id = t.id)), '[]'::jsonb),
    'dispute_resolutions', coalesce((select jsonb_agg(to_jsonb(dr) || jsonb_build_object('actor_label', ops.actor_label(dr.actor_id)) order by dr.created_at)
                                       from public.dispute_resolutions dr where dr.transfer_id = t.id), '[]'::jsonb),
    'payout_decisions', coalesce((select jsonb_agg(to_jsonb(pd) order by pd.decided_at) from public.payout_decisions pd
                                   where pd.payment_id = p.id or pd.transfer_id = t.id), '[]'::jsonb),
    'refund', jsonb_build_object(
                'payment_status',   p.status,
                'refunded_at',      p.refunded_at,
                'stripe_refund_id', p.stripe_refund_id,
                'refund_actions',   coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from ops.action a
                                               where a.action_type = 'refund_execute' and a.subject_kind = 'payment' and a.subject_id = p.id), '[]'::jsonb)),
    'seller_funds_state', ops.funds_state(t, p),
    'cases', coalesce((select jsonb_agg(ops.case_row(c) order by c.created_at desc) from ops."case" c
                        where (c.subject_kind = 'payment'  and c.subject_id = p.id)
                           or (c.subject_kind = 'transfer' and c.subject_id = t.id)
                           or (c.subject_kind = 'listing'  and c.subject_id = v_listing_id)), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from (
                          select * from ops.action a
                           where (a.subject_kind = 'payment'  and a.subject_id = p.id)
                              or (a.subject_kind = 'transfer' and a.subject_id = t.id)
                              or (a.subject_kind = 'listing'  and a.subject_id = v_listing_id)
                           order by a.requested_at desc limit 50) a), '[]'::jsonb),
    'evidence', jsonb_build_object(
                  'transfer_evidence_path',   jsonb_build_object('bucket', 'proof-docs', 'path', t.transfer_evidence_path),
                  'transfer_screenshot_path', jsonb_build_object('bucket', 'proof-docs', 'path', to_jsonb(t) ->> 'transfer_screenshot_path'),
                  'dispute_evidence_path',    jsonb_build_object('bucket', 'proof-docs', 'path', t.dispute_evidence_path),
                  'proof_of_ownership_path',  jsonb_build_object('bucket', 'proof-docs',
                                                'path', (select l.proof_of_ownership_path from public.listings l where l.id = v_listing_id))),
    'bank_payout', jsonb_build_object('tracked', false, 'note', 'Bank payouts from the connected account are not tracked (payout.paid webhook only logged).'));
end;
$function$
;
REVOKE ALL ON FUNCTION ops.order_detail(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ops.order_detail(uuid) TO authenticated;

DROP FUNCTION IF EXISTS ops.expire_stale_money_approvals(uuid);
DROP FUNCTION IF EXISTS ops.money_unsettled_blocker(uuid, uuid, text[], text, uuid);
DROP FUNCTION IF EXISTS ops.money_order_id(text, uuid);

-- ── verification (inside the transaction: a mismatch aborts the whole rollback) ─
DO $verify157$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(c.sig || ': '
                    || CASE WHEN c.live_md5 IS DISTINCT FROM c.prod_md5
                            THEN 'md5 ' || coalesce(c.live_md5, '<missing>') || ' <> production ' || c.prod_md5
                            ELSE 'md5 ok' END
                    || ', '
                    || CASE WHEN c.live_acl IS DISTINCT FROM c.prod_acl
                            THEN 'ACL ' || coalesce(c.live_acl, '<default>') || ' <> production ' || c.prod_acl
                            ELSE 'ACL ok' END, '; ' ORDER BY c.sig)
    INTO v_bad
    FROM (SELECT v.sig, v.prod_md5, 'postgres=X/postgres,authenticated=X/postgres'::text AS prod_acl,
                 md5(pg_get_functiondef(to_regprocedure(v.sig))) AS live_md5,
                 (SELECT array_to_string(p.proacl, ',') FROM pg_proc p WHERE p.oid = to_regprocedure(v.sig)) AS live_acl
            FROM (VALUES ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', 'e59c158453adabc662431cac9dca1040'),
                         ('ops.approve_action(uuid,text,text)',                             '5de6235288b38792c31dca3e6b3f89af'),
                         ('ops.order_detail(uuid)',                                         '04d4e05f6c533fa428c4f7123d20eba8')) v(sig, prod_md5)) c
   WHERE c.live_md5 IS DISTINCT FROM c.prod_md5
      OR c.live_acl IS DISTINCT FROM c.prod_acl;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '157 rollback verification failed (nothing changed): md5 or ACL mismatch: %', v_bad USING ERRCODE = 'P0001';
  END IF;
  IF to_regclass('ops.action_money_unsettled_uidx') IS NOT NULL
     OR to_regprocedure('ops.money_order_id(text,uuid)') IS NOT NULL
     OR to_regprocedure('ops.money_unsettled_blocker(uuid,uuid,text[],text,uuid)') IS NOT NULL
     OR to_regprocedure('ops.expire_stale_money_approvals(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '157 rollback verification failed (nothing changed): an index or helper of 157 is still present' USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '157 rollback verified: execute_action, approve_action, order_detail = production md5s and ACLs; index and helpers gone';
END
$verify157$;

COMMIT;

-- Read-only re-check after COMMIT (expect three rows, ok = true):
SELECT v.sig, md5(pg_get_functiondef(to_regprocedure(v.sig))) = v.prod_md5 AS ok
  FROM (VALUES ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', 'e59c158453adabc662431cac9dca1040'),
               ('ops.approve_action(uuid,text,text)',                             '5de6235288b38792c31dca3e6b3f89af'),
               ('ops.order_detail(uuid)',                                         '04d4e05f6c533fa428c4f7123d20eba8')) v(sig, prod_md5);
