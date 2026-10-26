-- ============================================================================
-- 20261021110000_ops_listing_relist_expected.sql — registry 158 (pgTAP 225). Stacked on 157
-- (20261021100000_ops_money_action_unsettled_guard.sql): a console relist must state the listing version the
-- operator saw, and the server compares it under the listing row lock (A15).
-- A sprint 2026-10-21. Server side only; F owns the console change that sends the version. Prepared and tested on
-- the local production replay only.
--
-- WHY. ops.action_dispatch 'listing_relist' (production body md5 bfb8b9dcfaace5ff04009f96b6de7bef, branch L260-262)
--   called public.admin_relist_listing without reading, locking or comparing the listing against ops.action.expected.
--   admin_relist_listing only checks the CURRENT state (admin-owned, cancelled resting state, no winner / hold, no
--   bid / payment / transfer history), so a stale console tab relisted any listing that was back in the cancelled
--   resting state: one relisted and deliberately cancelled again after the operator loaded the page (ABA) went live
--   again, and content edited after the load was published unreviewed. The console's {status, auction_status} could
--   not catch it (identical in both cancelled states), and the server dropped them anyway.
--   Map: private-evidence/A-sprint-20261021/understand_wf_c569d0d7.json (result.relist, Option 3); F's evidence:
--   F_EVIDENCE_20261021.md section 2.
--
-- WHAT (ops layer only; public.admin_relist_listing, its grants, ops.action_requires_approval, ops.action_precheck,
--   every listing guard and every other action type are untouched).
--   1. Pre-flight (read-only DO block): RAISEs, changing nothing, unless ops.execute_action is 157's body (md5
--      0da9bc63acb58f1d76a86f8039c0c877) and ops.action_dispatch is production's (md5 bfb8b9dc…). Both bodies below
--      are full redefinitions written on exactly those bodies; on anything else this file would silently replace
--      someone else's change (or install 157's money guard without its helpers).
--   2. ops.execute_action = 157's body + ONE block, marked '-- 158 begin' / '-- 158 end', after the reason check
--      (so after the idempotency-key lookup, the role check and the reason check, before any row or audit is
--      written): for listing_relist only, expected.updated_at must be a JSON string holding an ISO-8601 instant
--      with its UTC offset (the to_jsonb shape ops.listing_detail returns, e.g. 2026-10-20T11:04:05.123456-04:00;
--      'Z' and a space separator are accepted) that casts to timestamptz. Otherwise RAISE
--      'invalid_input: listing_relist requires expected.updated_at (the listing's updated_at exactly as
--      ops.listing_detail returned it); reload the listing' (P0001, the body's invalid_input style). Refused:
--      expected NULL or {}, today's console payload {status, auction_status}, JSON null, a number, '', 'yesterday' /
--      'now' (they cast, but name no version), a string with no offset (its instant would depend on the session
--      TimeZone). Everything else in the body, 157's money guard included, is byte for byte 157's (pgTAP 225 R12.5
--      strips the block and gets md5 0da9bc63).
--   3. ops.action_dispatch = production's body with ONLY the 'listing_relist' branch replaced (pgTAP 225 R12.6 puts
--      the production branch back and gets md5 bfb8b9dc):
--        SELECT status, auction_status, ends_at, ended_at, updated_at FROM public.listings WHERE id = subject FOR UPDATE;
--        not found -> rejected / precondition 'Listing not found.': the existing refusal, byte for byte (before 158
--        admin_relist_listing RAISEd that text and ops.action_run recorded exactly this jsonb).
--        (expected.updated_at)::timestamptz IS DISTINCT FROM updated_at — exact, to the microsecond (a value
--        truncated to milliseconds by a JS Date round trip is stale) — or, for each of status, auction_status,
--        ends_at, ended_at whose key is PRESENT in expected (a JSON null means NULL), a difference ->
--        rejected / stale_state, message 'listing changed since you loaded it — reload and try again', and
--        'current' = {status, auction_status, ends_at, ended_at, updated_at} of the locked row. Nothing is written.
--        Otherwise the UNCHANGED public.admin_relist_listing(subject, params.new_ends_at, requester) runs its own
--        guards (its FOR UPDATE on the same row is re-entrant); its refusals keep surfacing as today: ops.action_run
--        maps its P0001 to rejected / precondition with the domain message (bid / payment / transfer history,
--        non-admin seller, the 154 hidden-listing trigger, new end time not in the future). Success returns
--        {status:'succeeded', result:<admin_relist_listing's answer>, before:<the locked row's compared fields>}.
--   updated_at is the version token: trg_listings_updated_at (public.set_updated_at, NEW.updated_at = now()) stamps
--   every UPDATE of public.listings, and listings.updated_at is timestamptz NOT NULL in production (cols_md5 7364a391).
--
-- CONTRACT FOR THE CONSOLE (F). listing_relist through ops.execute_action:
--   p_expected (REQUIRED): updated_at = ops.listing_detail(id).listing.updated_at as the raw string, never passed
--     through new Date() / toISOString() (milliseconds => stale_state every time); also status, auction_status,
--     ends_at, ended_at as returned (raw strings or null): compared when present.
--   answers: succeeded {result:{status, result:{listing_id, event_name, relisted_by, new_ends_at, previous_ends_at},
--     before:{...}}}; rejected / stale_state {message, result.current:{...}} -> the existing reload prompt;
--     rejected / precondition {message: the domain text, unchanged, 'Listing not found.' included};
--     idempotent_replay (unchanged: a reused key returns the original action before this check runs); a raised
--     P0001 'invalid_input: listing_relist requires expected.updated_at …' means an out-of-date console build; 42501
--     and 'precondition_failed: console_actions_paused' unchanged.
--
-- LOCK ORDER. Unchanged: ops.action FOR UPDATE (action_run) -> public.listings FOR UPDATE (now taken by the dispatch
--   branch, previously by admin_relist_listing, the same row) -> admin_relist_listing's reads. No new lock, no new
--   edge. Under READ COMMITTED the FOR UPDATE waits for an open writer of the listing (cancel_listing, a seller edit,
--   a direct relist) and compares against the row it committed: a stale submit that raced a relist + re-cancel
--   waits, then answers stale_state (scripts/local/rehearsal_158_concurrency.sh C1); two operators with the same
--   expected: one relists, the other gets stale_state (C2).
--
-- NOT COVERED (by design).
--   - The owner's direct service-role path (public.admin_relist_listing(id, ts, admin), the RELIST_FOUR_LISTINGS_7D
--     DO block) takes no expected and is unchanged (md5 ef4c9ba0a832230db6752c069e467ca4; pgTAP 225 R11).
--   - A writer that skips triggers (session_replication_role = replica) does not bump updated_at (operator-only).
--   - updated_at is now() of the writing transaction, i.e. its START instant: a write by a transaction that started in
--     the same microsecond as the one that wrote the version the operator saw would stamp an equal value (theoretical).
--   - Order of answers: the compare runs first, so a stale request that admin_relist_listing would also refuse (e.g.
--     the loser of two concurrent relists, which got 'Listing is not in the cancelled resting state …' before 158) is
--     now answered stale_state; every admin_relist_listing message itself is unchanged.
--   - A present but malformed ends_at / ended_at string fails the cast inside the dispatch: the action is recorded
--     'failed' (22007) by ops.action_run and nothing is written; only updated_at is validated up front.
--   - ops.action_run still audits the client's expected as 'before'; result.before (above) records the verified row.
--   - Relist stays single-founder (not approval-gated); if it is ever gated, approve_action -> action_run runs this
--     same locked compare at approve time.
--   - ops.listing_detail needs no change: it already returns 'listing' = to_jsonb(row), whose updated_at is the raw
--     microsecond string (production md5 5208dbb14d749db54c2fdd62e50ab800; pgTAP 225 R1.1, R12.8).
--
-- ROLLOUT (each step an owner decision). Order matters:
--   1. F's console sends expected.updated_at (the raw string) with the relist form FIRST, and that build is deployed
--      and its pin verified. The current server ignores relist expected, so this is safe on its own. If 158 were
--      applied first, every console relist would fail closed with invalid_input (no money effect, no listing
--      change); the owner's SQL path is unaffected.
--   2. Read-only pre-checks in production: md5(pg_get_functiondef) of ops.execute_action = 0da9bc63… (157 applied)
--      and of ops.action_dispatch = bfb8b9dc…; no ops.action row with action_type 'listing_relist' in state
--      'processing' (relist runs synchronously; such a row means a call is in flight).
--   3. Apply this file (one transaction; lock_timeout 3s). Locks (pg_locks on a clone just before COMMIT,
--      private-evidence a158/06_rollback.out R7): none on any user table (public.listings, ops.action, …); only
--      AccessShare on the role / language / schema / type objects the two definitions reference and RowExclusive on
--      pg_proc's TOAST, so no reader or writer waits on the apply. The pre-flight reads only pg_proc. A relist already
--      running when this commits finishes with the body it started with (the pre-158 logic).
-- ROLLBACK: supabase/rollbacks/20261021110000_ops_listing_relist_expected_rollback.sql restores ops.action_dispatch
--   VERBATIM from production (md5 bfb8b9dc…) and ops.execute_action VERBATIM from 157 (md5 0da9bc63…), re-states
--   their ACLs, verifies both md5s and ACLs inside the transaction, and changes nothing on a mismatch. Its own
--   stacking guard refuses, changing nothing, if either body is neither 158's nor its target (a later change on top).
--   ORDER: roll back 158 BEFORE 157 (157's rollback refuses while action_dispatch is not production's); 158 must also
--   be rolled back before any rollback of 152 / 144 / 20261013000000, which recreate older dispatch bodies.
-- CI (four-file rule): no change. Gate-2 census and the grant manifests cover schema public only
--   (.github/workflows/ci.yml:605-608 counts tables/functions/policies/triggers in 'public'; :638 records that the ops
--   migrations add nothing to public; :723-730 diff public table grants against supabase/ci/expected_grants.txt;
--   supabase/ci/assert_public_table_grant_decisions.sql:315 and :601 read schema public). This file creates no
--   object and touches nothing in public. The pgTAP gate picks up 225 by glob (ci.yml:795-802).
-- VERIFY (read-only):
--   select md5(pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure));
--   -- 24209d0697132d5df7bd12f5cf3e5c0c
--   select md5(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure));  -- 7f507fc880c02617c53d1e4f679c608c
--   select md5(pg_get_functiondef('public.admin_relist_listing(uuid,timestamptz,uuid)'::regprocedure));  -- ef4c9ba0a832230db6752c069e467ca4
--   ACLs: execute_action postgres=X/postgres,authenticated=X/postgres; action_dispatch postgres=X/postgres.
-- FAILURE BEHAVIOUR: one transaction. The pre-flight RAISE, a lock timeout or any error leaves production exactly
--   as it was.
-- OWNER APPROVAL POINT: DRAFT, applied nowhere; prepared and tested locally only. Not for apply before
--   2026-10-28 03:47:04Z (the four relisted listings' live window) and build 29's review; applying it is a separate owner
--   approval, after ROLLOUT step 1.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 1. pre-flight (read-only): 157 applied, action_dispatch still production's ─
DO $pre158$
DECLARE
  v_exec text := md5(pg_get_functiondef(to_regprocedure('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)')));
  v_disp text := md5(pg_get_functiondef(to_regprocedure('ops.action_dispatch(ops.action)')));
BEGIN
  IF v_exec IS DISTINCT FROM '0da9bc63acb58f1d76a86f8039c0c877' OR v_disp IS DISTINCT FROM 'bfb8b9dcfaace5ff04009f96b6de7bef' THEN
    RAISE EXCEPTION '158 pre-flight refused (nothing changed): ops.execute_action md5 % (needs 157''s 0da9bc63acb58f1d76a86f8039c0c877), ops.action_dispatch md5 % (needs production''s bfb8b9dcfaace5ff04009f96b6de7bef). Apply 157 (20261021100000) first; do not re-apply 158.',
      coalesce(v_exec, '<missing>'), coalesce(v_disp, '<missing>') USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '158 pre-flight: execute_action = 157, action_dispatch = production';
END
$pre158$;

-- ── 2. ops.execute_action (157's body + the marked 158 block) ────────────────
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
  -- 157: one unsettled refund_execute / payout_release per order (see the migration header)
  v_unsettled constant text[] := array['requested','awaiting_approval','processing','unknown','succeeded_at_provider'];
  v_order uuid;
  v_block jsonb;
  v_con   text;
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
  -- 158 begin: a console relist states the listing version the operator saw. expected.updated_at must be the
  -- listing's updated_at exactly as ops.listing_detail returned it (to_jsonb: an ISO-8601 instant with its UTC
  -- offset, microseconds included). A missing key, JSON null, a number, '', 'yesterday' / 'now' (they cast but name
  -- no version) or a string without an offset is refused here, before any row or audit is written;
  -- ops.action_dispatch compares the value under the listing row lock.
  if p_action_type = 'listing_relist' then
    if jsonb_typeof(p_expected -> 'updated_at') is distinct from 'string'
       or (p_expected ->> 'updated_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}(:?[0-9]{2}){0,2})$' then
      raise exception 'invalid_input: listing_relist requires expected.updated_at (the listing''s updated_at exactly as ops.listing_detail returned it); reload the listing';
    end if;
    begin
      perform (p_expected ->> 'updated_at')::timestamptz;
    exception when others then
      raise exception 'invalid_input: listing_relist requires expected.updated_at (the listing''s updated_at exactly as ops.listing_detail returned it); reload the listing';
    end;
  end if;
  -- 158 end

  -- 157: money types only. Serialize every request on the ORDER (the payment; a transfer's order is its
  -- payment, transfers.payment_id is unique), then: re-check the key (a same-key racer that committed while
  -- this one waited is a replay, not a duplicate), sweep expired approvals on this order exactly as
  -- approve_action expires one, and refuse if any refund_execute / payout_release on the order is unsettled.
  -- A subject that resolves to no order (no such payment / transfer) takes no lock: the precheck rejects it
  -- and action_money_unsettled_uidx still holds the same-subject rule.
  if p_action_type in ('refund_execute','payout_release') then
    v_order := ops.money_order_id(p_subject_kind, p_subject_id);
    if v_order is not null then
      perform pg_advisory_xact_lock(hashtextextended('ops_money_order:' || v_order::text, 0));
      select * into a from ops.action where idempotency_key = p_idempotency_key;
      if found then
        return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state,
                                  'result', a.result, 'approval_id', a.approval_id);
      end if;
      perform ops.expire_stale_money_approvals(v_order);
      v_block := ops.money_unsettled_blocker(v_order, null, v_unsettled, p_action_type);
    end if;
  end if;

  if v_block is null then
    begin
      insert into ops.action (idempotency_key, action_type, subject_kind, subject_id, subject_ref, params, expected, reason, requested_by)
      values (p_idempotency_key, p_action_type, p_subject_kind, p_subject_id, p_subject_ref,
              coalesce(p_params, '{}'::jsonb), p_expected, nullif(trim(p_reason), ''), v_uid)
      returning * into a;
    exception when unique_violation then
      -- 157: only the idempotency key is a replay. The money backstop index is a duplicate_unsettled
      -- refusal (never 'idempotent_replay' with a NULL action_id); any other unique violation re-raises.
      get stacked diagnostics v_con = constraint_name;
      if v_con = 'action_idempotency_key_key' then
        select * into a from ops.action where idempotency_key = p_idempotency_key;
        return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state,
                                  'result', a.result, 'approval_id', a.approval_id);
      elsif v_con = 'action_money_unsettled_uidx' then
        v_block := ops.money_unsettled_blocker(v_order, null, v_unsettled, p_action_type, p_subject_id);
        if v_block is null then
          raise;   -- the colliding row settled before the re-read: report the collision, a retry succeeds
        end if;
      else
        raise;
      end if;
    end;
  end if;

  if v_block is not null then
    -- 157: record the refusal the way a precheck rejection is recorded (a 'rejected' row bound to this key,
    -- audited action.requested + action.<type>/rejected), inserted directly as 'rejected' so it never meets
    -- the money index; the replay of this key returns it.
    v_res := jsonb_build_object('status','rejected','reject_reason','duplicate_unsettled',
               'message', format('A %s for this %s is already %s (requested %s by %s). A new request is refused until it settles.',
                                 v_block ->> 'action_type',
                                 case when v_block ->> 'conflict' = 'same_type' then v_block ->> 'subject_kind' else 'order' end,
                                 case v_block ->> 'state'
                                   when 'awaiting_approval'     then 'awaiting approval'
                                   when 'unknown'               then 'outcome unknown'
                                   when 'succeeded_at_provider' then 'succeeded at Stripe, awaiting webhook'
                                   else v_block ->> 'state' end,
                                 to_char((v_block ->> 'requested_at')::timestamptz at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"'),
                                 coalesce(v_block ->> 'requested_by_label', 'an operator')),
               'hint', format('Decide it (System → Approvals), resume it (/actions/%s), or wait. A new request is accepted once it is succeeded, failed or rejected. An expired approval is cleared automatically on your next request.',
                              v_block ->> 'action_id'),
               'blocking', v_block);
    begin
      insert into ops.action (idempotency_key, action_type, subject_kind, subject_id, subject_ref, params, expected, reason, requested_by,
                              state, reject_reason, result, completed_at)
      values (p_idempotency_key, p_action_type, p_subject_kind, p_subject_id, p_subject_ref,
              coalesce(p_params, '{}'::jsonb), p_expected, nullif(trim(p_reason), ''), v_uid,
              'rejected', 'duplicate_unsettled', v_res, now())
      returning * into a;
    exception when unique_violation then
      get stacked diagnostics v_con = constraint_name;
      if v_con is distinct from 'action_idempotency_key_key' then
        raise;
      end if;
      select * into a from ops.action where idempotency_key = p_idempotency_key;
      return jsonb_build_object('status','idempotent_replay','action_id', a.id, 'state', a.state,
                                'result', a.result, 'approval_id', a.approval_id);
    end;
    perform ops.audit_write('action.requested', a.subject_kind, a.subject_id, a.subject_ref, a.reason,
                            a.expected, jsonb_build_object('action_type', a.action_type, 'params', a.params),
                            'requested', a.correlation_id, a.id);
    perform ops.audit_write('action.' || a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.reason,
                            a.expected, v_res, 'rejected', a.correlation_id, a.id);
    return jsonb_build_object('status','rejected','action_id', a.id, 'result', v_res,
                              'reject_reason', 'duplicate_unsettled', 'message', v_res ->> 'message',
                              'hint', v_res ->> 'hint', 'blocking', v_block);
  end if;

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

-- ── 3. ops.action_dispatch (production body; only the listing_relist branch replaced) ─
CREATE OR REPLACE FUNCTION ops.action_dispatch(p_action ops.action)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  a        alias for p_action;
  -- Domain attribution is the REQUESTER (the founder who decided). For an
  -- approval-gated action the executing session is the approver; the approval
  -- row and the audit actor record that separately.
  v_uid    uuid := p_action.requested_by;
  v_case   ops."case"%rowtype;
  v_ver    integer;
  v_n      integer;
  v_res    jsonb;
  v_ok     boolean;
  v_row    record;
  v_note   uuid;
  v_status text;
  v_before jsonb;
  v_class    text;     -- 144: the recorded classification (A/B/C)
  v_open_obl text;     -- 144: obligations raised for this case and not recorded settled
  v_obl      text;
  v_assignee uuid;
  v_paid     boolean;
begin
  -- ── case_* ──────────────────────────────────────────────────────────────
  if a.action_type like 'case_%' and a.action_type <> 'case_create' then
    select * into v_case from ops."case" where id = a.subject_id for update;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','case not found');
    end if;
    v_ver := nullif(a.expected ->> 'version', '')::integer;
    if v_ver is not null and v_ver <> v_case.version then
      return jsonb_build_object('status','rejected','reject_reason','stale_state',
                                'message', format('case changed since you loaded it (version %s, you had %s)', v_case.version, v_ver),
                                'current_version', v_case.version);
    end if;
    v_before := jsonb_build_object('status', v_case.status, 'assignee', v_case.assignee,
                                   'priority', v_case.priority, 'due_at', v_case.due_at, 'version', v_case.version);
  end if;

  case a.action_type
  when 'case_create' then
    if (a.params ->> 'title') is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','title required');
    end if;
    v_res := ops.case_upsert('manual', coalesce(a.params ->> 'subject_kind','none'),
               nullif(a.params ->> 'subject_id','')::uuid, a.params ->> 'subject_ref',
               a.params ->> 'title', a.params ->> 'summary', coalesce(a.params ->> 'priority','p3'),
               nullif(a.params ->> 'due_at','')::timestamptz, 'manual');
    -- a manual case is never auto-resolved and dedupes on its own id
    update ops."case" set dedupe_key = 'manual:' || id::text, assignee = coalesce(nullif(a.params ->> 'assignee','')::uuid, assignee)
     where id = (v_res ->> 'case_id')::uuid;
    return jsonb_build_object('status','succeeded','case_id', v_res ->> 'case_id');

  when 'case_assign' then
    update ops."case" set assignee = nullif(a.params ->> 'assignee','')::uuid,
           status = case when status = 'open' and (a.params ->> 'assignee') is not null then 'in_progress' else status end,
           version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, 'assigned', jsonb_build_object('assignee', v_case.assignee, 'before', v_before, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','version', v_case.version);

  when 'case_status' then
    v_status := a.params ->> 'status';
    if v_status not in ('open','in_progress','waiting','resolved','dismissed') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','invalid status');
    end if;
    if v_status in ('resolved','dismissed') and coalesce(trim(a.reason),'') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','a reason is required to resolve or dismiss');
    end if;
    -- 144: closing is not the same act as classifying (owner, 2026-09-19). A classification must be RECORDED
    -- (case_refund_classify) and every obligation it raised recorded SETTLED (case_refund_obligation). So choosing B,
    -- or A on a paid-out order, can never by itself close money that is still owed.
    if v_case.case_type = 'refund_resolution' and v_status in ('resolved','dismissed') then
      v_class := (select e.data ->> 'classification' from ops.case_event e
                   where e.case_id = a.subject_id and e.kind = 'classified'
                   order by e.created_at desc limit 1);
      v_open_obl := (select string_agg(x.kind, ', ' order by x.kind) from (
                       select distinct on (e.data ->> 'kind') e.data ->> 'kind' as kind, e.data ->> 'settled' as settled
                         from ops.case_event e
                        where e.case_id = a.subject_id and e.kind = 'obligation_changed'
                        order by e.data ->> 'kind', e.created_at desc) x
                      where x.settled is distinct from 'true');
      if v_class is null then
        -- dismissal is a closure too: without a classification nobody has looked at the money (A, 2026-09-19)
        return jsonb_build_object('status','rejected','reject_reason','precondition',
                                  'message','classify this case first (case_refund_classify: A, B or C)');
      end if;
      if v_open_obl is not null then
        return jsonb_build_object('status','rejected','reject_reason','precondition',
                                  'message', format('unsettled obligation(s): %s — record each with case_refund_obligation before closing', v_open_obl));
      end if;
    end if;
    update ops."case"
       set status = v_status,
           resolved_at = case when v_status in ('resolved','dismissed') then now() else null end,
           resolved_by = case when v_status in ('resolved','dismissed') then v_uid else null end,
           resolution_note = case when v_status in ('resolved','dismissed')
                                  then case when v_case.case_type = 'refund_resolution' and v_class is not null
                                            then '[' || v_class || '] ' || a.reason
                                            else a.reason end
                                  else resolution_note end,
           version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, case when v_before ->> 'status' in ('resolved','dismissed') and v_status not in ('resolved','dismissed') then 'reopened' else 'status_changed' end,
            jsonb_build_object('from', v_before ->> 'status', 'to', v_status, 'reason', a.reason, 'action_id', a.id)
            || case when v_case.case_type = 'refund_resolution' and v_status in ('resolved','dismissed')
                    then jsonb_build_object('classification', v_class) else '{}'::jsonb end);
    return jsonb_build_object('status','succeeded','version', v_case.version);

  -- ── 144: classify, and raise the obligation that classification implies ─────────────────────────────
  when 'case_refund_classify' then
    if v_case.case_type <> 'refund_resolution' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','only a refund-resolution case is classified');
    end if;
    if coalesce(a.params ->> 'classification','') not in ('A','B','C') then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
                                'message','classification must be A (full refund), B (partial, fulfilment continues) or C (partial, order cancelled)');
    end if;
    if coalesce(trim(a.reason),'') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','a reason is required to classify (what Stripe showed)');
    end if;
    select (t.stripe_transfer_id is not null or t.payout_released_at is not null) into v_paid
      from public.transfers t where t.id = v_case.subject_id;
    v_obl := case a.params ->> 'classification'
               when 'B' then 'payout_owed'                 -- nothing releases it today: F-PAYOUT-PARTIAL-1
               when 'C' then 'remainder_refund_owed'
               else case when coalesce(v_paid, false) then 'reversal_decision' else null end
             end;
    -- money that is owed is never merely open and ownerless (A, 2026-09-19)
    v_assignee := coalesce(nullif(a.params ->> 'assignee','')::uuid, v_case.assignee);
    if v_obl is not null and v_assignee is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
                                'message', format('classification %s leaves %s outstanding: an assignee is required',
                                                  a.params ->> 'classification', v_obl));
    end if;
    update ops."case" set assignee = coalesce(v_assignee, assignee), version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data, created_at)
    values (a.subject_id, v_uid, 'classified',
            jsonb_build_object('classification', a.params ->> 'classification', 'reason', a.reason,
                               'implies_obligation', v_obl, 'assignee', v_assignee, 'action_id', a.id),
            clock_timestamp());
    if v_obl is not null and not exists (select 1 from ops.case_event e
                                          where e.case_id = a.subject_id and e.kind = 'obligation_changed'
                                            and e.data ->> 'kind' = v_obl) then
      insert into ops.case_event (case_id, actor, kind, data, created_at)
      values (a.subject_id, v_uid, 'obligation_changed',
              jsonb_build_object('kind', v_obl, 'settled', false, 'raised_by', a.params ->> 'classification', 'action_id', a.id),
              clock_timestamp());
    end if;
    return jsonb_build_object('status','succeeded','classification', a.params ->> 'classification',
                              'obligation', v_obl, 'assignee', v_assignee, 'version', v_case.version);

  -- ── 144: record what happened to an obligation — settling one is its own human record ────────────────
  when 'case_refund_obligation' then
    if v_case.case_type <> 'refund_resolution' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','only a refund-resolution case carries these obligations');
    end if;
    if coalesce(a.params ->> 'kind','') not in ('payout_owed','remainder_refund_owed','reversal_decision') then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
                                'message','kind must be payout_owed, remainder_refund_owed or reversal_decision');
    end if;
    if not exists (select 1 from ops.case_event e where e.case_id = a.subject_id and e.kind = 'obligation_changed'
                     and e.data ->> 'kind' = a.params ->> 'kind') then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
                                'message','that obligation was never raised for this case');
    end if;
    if coalesce(trim(coalesce(a.params ->> 'note', a.reason)),'') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition',
                                'message','a note is required: what was done, and where it can be seen');
    end if;
    update ops."case" set version = version + 1 where id = a.subject_id returning version into v_ver;
    insert into ops.case_event (case_id, actor, kind, data, created_at)
    values (a.subject_id, v_uid, 'obligation_changed',
            jsonb_build_object('kind', a.params ->> 'kind',
                               'settled', coalesce((a.params ->> 'settled')::boolean, false),
                               'note', coalesce(a.params ->> 'note', a.reason), 'action_id', a.id),
            clock_timestamp());
    return jsonb_build_object('status','succeeded','kind', a.params ->> 'kind',
                              'settled', coalesce((a.params ->> 'settled')::boolean, false), 'version', v_ver);

  when 'case_priority' then
    if (a.params ->> 'priority') not in ('p1','p2','p3','p4') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','invalid priority');
    end if;
    update ops."case" set priority = a.params ->> 'priority', version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, 'priority_changed', jsonb_build_object('from', v_before ->> 'priority', 'to', v_case.priority, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','version', v_case.version);

  when 'case_due' then
    update ops."case" set due_at = nullif(a.params ->> 'due_at','')::timestamptz, version = version + 1
     where id = a.subject_id returning * into v_case;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, 'due_changed', jsonb_build_object('from', v_before ->> 'due_at', 'to', v_case.due_at, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','version', v_case.version);

  when 'case_note' then
    if coalesce(trim(a.params ->> 'body'),'') = '' then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','note body required');
    end if;
    insert into ops.case_note (case_id, author, body) values (a.subject_id, v_uid, a.params ->> 'body')
    returning id into v_note;
    update ops."case" set version = version + 1 where id = a.subject_id returning version into v_ver;
    insert into ops.case_event (case_id, actor, kind, data)
    values (a.subject_id, v_uid, 'note_added', jsonb_build_object('note_id', v_note, 'action_id', a.id));
    return jsonb_build_object('status','succeeded','note_id', v_note, 'version', v_ver);

  -- ── money / marketplace: published domain functions only ───────────────
  when 'dispute_resolve' then
    if (a.params ->> 'outcome') not in ('seller_win','buyer_win','partial_refund') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','outcome must be seller_win, buyer_win or partial_refund');
    end if;
    select status, disputed_at, dispute_resolved_at into v_row from public.transfers where id = a.subject_id;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','transfer not found');
    end if;
    if v_row.disputed_at is null or v_row.dispute_resolved_at is not null then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','transfer has no open dispute');
    end if;
    if a.expected is not null and (a.expected ->> 'status') is not null and (a.expected ->> 'status') <> v_row.status then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message', format('transfer status is %s, you saw %s', v_row.status, a.expected ->> 'status'));
    end if;
    v_res := public.resolve_transfer_dispute(a.subject_id, a.params ->> 'outcome', v_uid, a.reason, a.params ->> 'notes');
    perform ops.case_auto_resolve_subject('dispute_open', a.subject_id, a.id);
    return jsonb_build_object('status','succeeded','result', v_res,
             'follow_up', case when (v_res ->> 'refund_required')::boolean
                               then 'refund_required: a refund is NOT executed by this action' else null end);

  when 'payout_release' then
    select status, payout_released_at, payout_review_status, disputed_at, dispute_resolved_at
      into v_row from public.transfers where id = a.subject_id for update;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','transfer not found');
    end if;
    if v_row.status <> 'seller_sent' or v_row.payout_released_at is not null then
      return jsonb_build_object('status','rejected','reject_reason','stale_state',
               'message', format('transfer is %s (released_at %s); only an unreleased seller_sent transfer can be released', v_row.status, v_row.payout_released_at));
    end if;
    if v_row.disputed_at is not null and v_row.dispute_resolved_at is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','transfer has an open dispute');
    end if;
    if a.expected is not null and (a.expected ->> 'payout_review_status') is distinct from v_row.payout_review_status then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','payout review state changed since you loaded it');
    end if;
    v_ok := public.admin_release_held_payout(a.subject_id, v_uid, a.reason);
    if not v_ok then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','release refused by domain guard (state changed)');
    end if;
    perform ops.case_auto_resolve_subject('payout_review', a.subject_id, a.id);
    return jsonb_build_object('status','succeeded','note','Transfer marked released; the payout worker moves funds on its next run (this is not a bank payout).');

  when 'listing_relist' then
    -- 158: compare what the operator saw under the listing row lock (lock order unchanged: ops.action in
    -- action_run, then this listing, which admin_relist_listing used to lock first). expected.updated_at is
    -- required (ops.execute_action) and compared exactly, to the microsecond; status, auction_status, ends_at and
    -- ended_at are compared when their key is present (a JSON null means NULL). A difference is stale_state with
    -- the live row in 'current' and writes nothing. Otherwise the unchanged admin_relist_listing runs its own
    -- guards (its row lock is re-entrant) and its refusals still surface as precondition through ops.action_run.
    select status, auction_status, ends_at, ended_at, updated_at
      into v_row from public.listings where id = a.subject_id for update;
    if not found then
      -- the answer a missing listing got before 158, byte for byte (admin_relist_listing's RAISE through action_run)
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','Listing not found.');
    end if;
    v_before := jsonb_build_object('status', v_row.status, 'auction_status', v_row.auction_status,
                                   'ends_at', v_row.ends_at, 'ended_at', v_row.ended_at, 'updated_at', v_row.updated_at);
    if (a.expected ->> 'updated_at')::timestamptz is distinct from v_row.updated_at
       or (a.expected ? 'status'         and (a.expected ->> 'status') is distinct from v_row.status)
       or (a.expected ? 'auction_status' and (a.expected ->> 'auction_status') is distinct from v_row.auction_status)
       or (a.expected ? 'ends_at'        and (a.expected ->> 'ends_at')::timestamptz is distinct from v_row.ends_at)
       or (a.expected ? 'ended_at'       and (a.expected ->> 'ended_at')::timestamptz is distinct from v_row.ended_at) then
      return jsonb_build_object('status','rejected','reject_reason','stale_state',
                                'message','listing changed since you loaded it — reload and try again',
                                'current', v_before);
    end if;
    v_res := public.admin_relist_listing(a.subject_id, (a.params ->> 'new_ends_at')::timestamptz, v_uid);
    return jsonb_build_object('status','succeeded','result', v_res, 'before', v_before);

  when 'report_resolve' then
    v_status := a.params ->> 'status';
    if v_status not in ('reviewing','actioned','dismissed') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','status must be reviewing, actioned or dismissed');
    end if;
    select status into v_row from public.reports where id = a.subject_id for update;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','report not found');
    end if;
    if a.expected is not null and (a.expected ->> 'status') is not null and (a.expected ->> 'status') <> v_row.status then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message', format('report is %s, you saw %s', v_row.status, a.expected ->> 'status'));
    end if;
    if v_row.status in ('actioned','dismissed') then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','report already closed');
    end if;
    update public.reports set status = v_status,
           resolved_at = case when v_status in ('actioned','dismissed') then now() else null end
     where id = a.subject_id;
    if v_status in ('actioned','dismissed') then
      perform ops.case_auto_resolve_subject('report_review', a.subject_id, a.id);
    end if;
    return jsonb_build_object('status','succeeded','from', v_row.status, 'to', v_status);

  when 'user_restrict' then
    -- 152: kind 'suspended' is an account suspension. It is stronger than a listing block, so only
    -- platform_admin and platform_risk may do it (support keeps listing_blocked). Enforcement is
    -- the refusal rule in public.assert_marketplace_parties, which the bids, reservation and listing guards call.
    if coalesce(a.params ->> 'kind','listing_blocked') = 'suspended' then
      if coalesce(ops.actor_role(), '') not in ('platform_admin','platform_risk') then
        return jsonb_build_object('status','rejected','reject_reason','forbidden',
                 'message','only platform_admin or platform_risk may suspend an account');
      end if;
      if a.subject_id = v_uid then
        return jsonb_build_object('status','rejected','reject_reason','precondition','message','you cannot suspend your own account');
      end if;
      if not exists (select 1 from public.profiles where id = a.subject_id) then
        return jsonb_build_object('status','rejected','reject_reason','precondition','message','user not found');
      end if;
      insert into ops.user_restriction (user_id, kind, reason, actor) values (a.subject_id, 'suspended', a.reason, v_uid)
      on conflict do nothing;
      get diagnostics v_n = row_count;
      if v_n = 0 then
        return jsonb_build_object('status','rejected','reject_reason','stale_state','message','user is already suspended');
      end if;
      return jsonb_build_object('status','succeeded','kind','suspended',
               'enforcement','the database refuses this user''s new bids, Buy Now reservations, listings and listing edits, and new bids and reservations on their listings; orders that already exist, refunds, payouts and reports continue');
    end if;
    if coalesce(a.params ->> 'kind','listing_blocked') <> 'listing_blocked' then
      return jsonb_build_object('status','rejected','reject_reason','not_supported','message','kind must be listing_blocked or suspended');
    end if;
    if not exists (select 1 from public.profiles where id = a.subject_id) then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','user not found');
    end if;
    insert into public.seller_risk_scores (seller_id, is_listing_blocked, listing_blocked_at, listing_blocked_reason)
    values (a.subject_id, true, now(), a.reason)
    on conflict (seller_id) do update
      set is_listing_blocked = true, listing_blocked_at = now(), listing_blocked_reason = excluded.listing_blocked_reason
      where public.seller_risk_scores.is_listing_blocked = false;
    get diagnostics v_n = row_count;
    if v_n = 0 then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','user is already listing-blocked');
    end if;
    insert into ops.user_restriction (user_id, kind, reason, actor) values (a.subject_id, 'listing_blocked', a.reason, v_uid)
    on conflict do nothing;
    return jsonb_build_object('status','succeeded','kind','listing_blocked',
             'enforcement','public.can_create_listing() returns listing_blocked; clients check it before creating a listing');

  when 'user_unrestrict' then
    -- 152: restoring a suspended account. user_unrestrict is platform_admin / platform_risk only
    -- (ops.action_allowed_roles). The suspension row is kept, with who lifted it, when and why.
    if coalesce(a.params ->> 'kind','listing_blocked') = 'suspended' then
      update ops.user_restriction set lifted_at = now(), lifted_by = v_uid, lift_reason = a.reason
       where user_id = a.subject_id and kind = 'suspended' and lifted_at is null;
      get diagnostics v_n = row_count;
      if v_n = 0 then
        return jsonb_build_object('status','rejected','reject_reason','stale_state','message','user is not suspended');
      end if;
      return jsonb_build_object('status','succeeded','kind','suspended');
    end if;
    if coalesce(a.params ->> 'kind','listing_blocked') <> 'listing_blocked' then
      return jsonb_build_object('status','rejected','reject_reason','not_supported','message','kind must be listing_blocked or suspended');
    end if;
    update public.seller_risk_scores set is_listing_blocked = false
     where seller_id = a.subject_id and is_listing_blocked = true;
    get diagnostics v_n = row_count;
    if v_n = 0 then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','user is not listing-blocked');
    end if;
    update ops.user_restriction set lifted_at = now(), lifted_by = v_uid, lift_reason = a.reason
     where user_id = a.subject_id and kind = 'listing_blocked' and lifted_at is null;
    return jsonb_build_object('status','succeeded','kind','listing_blocked');

  when 'refund_execute' then
    if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'refund_execute_enabled'), false) then
      return jsonb_build_object('status','rejected','reject_reason','disabled',
               'message','refund execution is disabled until the ops-refund-execute function is deployed (see runbook); use the Stripe Dashboard SOP');
    end if;
    select status, total, stripe_payment_intent_id into v_row from public.payments where id = a.subject_id for update;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','payment not found');
    end if;
    if v_row.status <> 'succeeded' then
      return jsonb_build_object('status','rejected','reject_reason','stale_state', 'message', format('payment is %s; only a succeeded payment can be refunded', v_row.status));
    end if;
    if (a.params ->> 'amount_cents') is not null and ((a.params ->> 'amount_cents')::integer <= 0 or (a.params ->> 'amount_cents')::integer > v_row.total) then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','amount must be between 1 and the payment total');
    end if;
    if (a.params ->> 'amount_cents') is not null
       and (a.params ->> 'amount_cents')::integer <> v_row.total then
      return jsonb_build_object('status','rejected','reject_reason','not_supported',
               'message','partial refunds are not supported in this release: the local money model records refund status only (no refunded amount), so a partial refund would be reported as a full one. Request a full refund or use the Stripe Dashboard SOP.');
    end if;
    -- The money leg runs in the ops-refund-execute edge function (Stripe
    -- idempotency key = ops_action_<id>); it reports back through
    -- ops.record_action_outcome. Until then the action is `processing`.
    return jsonb_build_object('status','processing','handoff','ops-refund-execute',
             'stripe_payment_intent_id', v_row.stripe_payment_intent_id,
             'amount_cents', v_row.total, 'currency', 'usd');

  when 'job_retry' then
    if coalesce(a.subject_ref, a.params ->> 'job_name') is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','job_name required');
    end if;
    if to_regprocedure('ops.run_job(text,text)') is null then
      return jsonb_build_object('status','rejected','reject_reason','not_supported','message','ops.run_job not installed (migration 117)');
    end if;
    execute 'select ops.run_job($1, $2)' into v_res using coalesce(a.subject_ref, a.params ->> 'job_name'), 'manual';
    return jsonb_build_object('status', case when v_res ->> 'status' = 'failed' then 'failed' else 'succeeded' end, 'result', v_res);

  when 'setting_set' then
    if not exists (select 1 from ops.setting where key = a.subject_ref) then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','unknown setting');
    end if;
    if a.params -> 'value' is null then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','value required');
    end if;
    select value into v_before from ops.setting where key = a.subject_ref for update;
    if jsonb_typeof(v_before) <> jsonb_typeof(a.params -> 'value') then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message', format('setting is %s, not %s', jsonb_typeof(v_before), jsonb_typeof(a.params -> 'value')));
    end if;
    update ops.setting set value = a.params -> 'value', updated_at = now(), updated_by = v_uid where key = a.subject_ref;
    return jsonb_build_object('status','succeeded','before', v_before, 'after', a.params -> 'value');

  else
    return jsonb_build_object('status','rejected','reject_reason','not_supported','message','unknown action type');
  end case;
end;
$function$
;
REVOKE ALL ON FUNCTION ops.action_dispatch(ops.action) FROM PUBLIC, anon, authenticated;

COMMIT;
