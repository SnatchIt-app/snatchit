-- ============================================================================
-- 20261021100000_ops_money_action_unsettled_guard.sql — registry 157 (pgTAP 224).
-- One unsettled refund_execute / payout_release per ORDER (a payment and its one transfer).
-- A sprint 2026-10-21 (owner's priority 1: "block duplicate unsettled refund/payout actions"). Server side only;
-- F's console already renders the refusal envelope. Prepared and tested on the local production replay only.
--
-- WHY. ops.execute_action deduplicated on the idempotency key alone, and the console mints a new key on every
--   render, so a reload, a second tab, a second founder or a direct RPC parked a second refund_execute or
--   payout_release on the same payment / transfer. Nothing related a refund on payment P to a payout_release on
--   P's transfer: approving the payout while the refund was in flight pays the seller AND refunds the buyer
--   (REFUNDED_AFTER_PAYOUT, a manual reversal). Expired approvals were never swept, so a naive unique rule would
--   freeze an order forever, and the blanket unique_violation handler would have reported a new index collision
--   as 'idempotent_replay' with a NULL action_id. Map: private-evidence/A-sprint-20261021/understand_wf_c569d0d7.json
--   (result.duplicate_action); F's evidence: F_EVIDENCE_20261021.md.
--
-- STATES (ops.action_state_check). Unsettled: requested, awaiting_approval, processing, unknown,
--   succeeded_at_provider. Terminal: succeeded, failed, rejected ('denied', 'approval_expired', 'stale' and
--   'duplicate_unsettled' are reject_reasons of 'rejected', not states).
--
-- WHAT.
--   1. Pre-flight (read-only DO block, first): RAISEs, listing the action ids, if any order already holds two
--      unsettled money actions (same type and subject, or refund on P plus payout_release on P's transfer), or
--      if two unsettled rows share the index key below. Nothing changes when it raises. Expected 0.
--   2. Internal helpers (SECURITY DEFINER, search_path '', EXECUTE revoked from PUBLIC/anon/authenticated:
--      the ops.action_precheck ACL, postgres=X/postgres):
--        ops.money_order_id(p_subject_kind, p_subject_id) -> uuid: the payment id for a 'payment' subject (the
--          row must exist) or for a 'transfer' subject (transfers.payment_id); NULL otherwise.
--        ops.money_unsettled_blocker(p_order, p_exclude, p_states[, p_action_type][, p_subject_id]) -> jsonb|NULL:
--          the newest refund_execute on the payment or payout_release on its transfer in p_states, other than
--          p_exclude, as {action_id, action_type, subject_kind, subject_id, state, requested_at,
--          requested_by_label, approval_id, approval_expires_at, conflict: same_type|cross_type}. conflict is
--          relative to p_action_type, else to p_exclude's type. p_subject_id (with p_action_type) also matches
--          the same-type row on exactly that subject: the backstop index's key, used to name the colliding row
--          when the subject resolves to no order.
--        ops.expire_stale_money_approvals(p_order) -> int: for the order's awaiting_approval money actions whose
--          pending approval has expires_at <= now(), EXACTLY approve_action's expiry transition (production body
--          L31-35): approval 'expired'; action 'rejected' / 'approval_expired', completed_at now(), version + 1;
--          audit 'approval.expired' (before/after NULL, outcome 'expired', the action's correlation id). The only
--          differences: the audit reason is fixed text (there is no decider's reason), and the boundary is <=
--          (an approval is decidable only while expires_at > now(), ops.action_detail.can_decide).
--   3. ops.execute_action, from the PRODUCTION body (md5 e59c158453adabc662431cac9dca1040). For refund_execute
--      and payout_release only, after the existing validation, key lookup, role and reason checks: take
--      pg_advisory_xact_lock(hashtextextended('ops_money_order:' || <payment id>, 0)); re-check the key (a
--      same-key racer -> idempotent_replay); sweep (2); compute the blocker over ALL unsettled states. A blocker
--      -> INSERT this request directly as 'rejected' / reject_reason 'duplicate_unsettled' (key bound, result =
--      the payload, completed_at now()), audited like a precheck rejection (action.requested, then
--      action.<type> / rejected), and RETURN {status:'rejected', reject_reason:'duplicate_unsettled', action_id,
--      message, hint, blocking:{...}, result:{status, reject_reason, message, hint, blocking}}.
--      The unique_violation handler now reads the constraint name: action_idempotency_key_key keeps the
--      idempotent_replay answer; action_money_unsettled_uidx becomes the same duplicate_unsettled refusal (the
--      blocker re-read); anything else re-raises. Every other action type runs the production statements
--      unchanged (pgTAP 224 T9: same answers, same shape, no lock).
--   4. ops.approve_action, from the PRODUCTION body (md5 5de6235288b38792c31dca3e6b3f89af): for money actions
--      the order advisory lock is taken BEFORE the action row FOR UPDATE; then, for 'approve' only, after the
--      existing self-approval / expiry / hash / deny branches and BEFORE the approval is marked approved, a
--      NON-DESTRUCTIVE recheck: another money action on the order in processing / unknown /
--      succeeded_at_provider -> {status:'rejected', reject_reason:'duplicate_unsettled', action_id, state,
--      message, hint, blocking} with NO state change (the approval stays pending). Deny is never blocked.
--   5. Backstop: UNIQUE INDEX ops.action_money_unsettled_uidx ON ops.action (action_type, subject_kind,
--      subject_id) WHERE action_type IN (refund_execute, payout_release) AND state IN (unsettled). It enforces
--      the SAME-TYPE rule against every writer. The CROSS-TYPE rule (refund on P vs payout on T(P): different
--      subject ids) is enforced by the order lock + blocker check in (3) and the recheck in (4), not by the index.
--   6. ops.order_detail, from the PRODUCTION body (md5 04d4e05f6c533fa428c4f7123d20eba8): new key
--      'unsettled_money_actions', UNCAPPED: refund_execute on the payment and payout_release on its transfer in
--      unsettled states, as ops.action_row(a) plus approval_id, approval_expires_at, approval_expired. The capped
--      'actions' key (50) is unchanged.
--
-- LOCK ORDER. execute_action (money): order advisory lock -> its own new row -> the sweep's rows (action, then
--   approval). approve_action (money): order advisory lock -> action row FOR UPDATE -> approval FOR UPDATE ->
--   action_run / action_dispatch (payments or transfers FOR UPDATE, as before). Both take the advisory lock first,
--   so they serialize per order and cannot form a cycle. executor_claim, record_action_outcome and
--   detect_refunds take no advisory lock and only touch processing / unknown / succeeded_at_provider rows, which
--   the sweep never updates. Non-money types take no new lock.
--
-- NOT COVERED (by design).
--   - A refund AFTER a SETTLED (succeeded) payout is not blocked: a succeeded payout_release is terminal. It
--     stays REFUNDED_AFTER_PAYOUT detection (record_payment_refund -> flag_payout_reversal_required).
--   - No requester withdraw is added (approval state 'cancelled' still has no writer); a parked request is
--     freed by the other founder's deny or by expiry (swept on the next request).
--   - A refund_execute stuck in processing / unknown blocks new money requests on its order until it is
--     reconciled (Resume, or service_role record_action_outcome after a Stripe check). Intended: money may
--     have moved.
--   - executor_claim is unchanged (no sibling check: the index makes a same-payment sibling unreachable).
--
-- ROLLOUT (each step an owner decision).
--   1. Read-only pre-flight count in production (the DO block's query, as SELECT). Expected 0 rows; at
--      2026-10-15 ops.action held 5 rows, none refund/payout, and 0 approvals.
--   2. Apply this file (one transaction; lock_timeout 3s; ACCESS EXCLUSIVE only for the function swaps and a
--      SHARE lock on ops.action while the index builds over a handful of rows).
--   3. Console: no deploy needed. The refusal is the existing 'rejected' envelope, which the live console
--      renders as "Rejected: duplicate_unsettled" plus the message. F may later read unsettled_money_actions.
-- ROLLBACK: supabase/rollbacks/20261021100000_ops_money_action_unsettled_guard_rollback.sql. Drops the index,
--   restores the three bodies VERBATIM from production (prod_ops_action_defs.json), drops the helpers, and
--   verifies md5(pg_get_functiondef) = the production md5s. 'rejected' / duplicate_unsettled rows stay as
--   history (valid rejected rows; reject_reason has no check constraint).
-- CI (four-file rule): no change. Gate-2 census and the grant manifests cover schema public only
--   (.github/workflows/ci.yml:605-608, :723, :730; supabase/ci/assert_public_table_grant_decisions.sql:315, :601);
--   ci.yml:638 records that the ops migrations add nothing to public. This file adds nothing to public.
-- VERIFY (read-only): select indexrelid::regclass from pg_index where indexrelid = 'ops.action_money_unsettled_uidx'::regclass;
--   select md5(pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure));
--   -- 0da9bc63acb58f1d76a86f8039c0c877
--   select md5(pg_get_functiondef('ops.approve_action(uuid,text,text)'::regprocedure));  -- 60fb8ce43d5ff1b051e379ac6affb53f
--   select md5(pg_get_functiondef('ops.order_detail(uuid)'::regprocedure));               -- 4358f577291f84b25986b8904b38ab36
-- FAILURE BEHAVIOUR: one transaction. The pre-flight RAISE, a lock timeout or any error leaves production exactly
--   as it was.
-- OWNER APPROVAL POINT: prepared and tested locally only; applying it is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 1. pre-flight (read-only) ───────────────────────────────────────────────
DO $pre157$
DECLARE
  v_bad text;
BEGIN
  WITH u AS (
    SELECT a.id, a.action_type, a.subject_kind, a.subject_id,
           CASE WHEN a.action_type = 'refund_execute' AND a.subject_kind = 'payment' THEN
                  (SELECT p.id FROM public.payments p WHERE p.id = a.subject_id)
                WHEN a.action_type = 'payout_release' AND a.subject_kind = 'transfer' THEN
                  (SELECT t.payment_id FROM public.transfers t WHERE t.id = a.subject_id)
           END AS order_id
      FROM ops.action a
     WHERE a.action_type IN ('refund_execute','payout_release')
       AND a.state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')),
  g AS (
    SELECT 'order ' || order_id::text AS grp, string_agg(id::text || ' (' || action_type || ')', ', ' ORDER BY id::text) AS ids
      FROM u WHERE order_id IS NOT NULL GROUP BY order_id HAVING count(*) > 1
    UNION ALL
    SELECT 'index key ' || action_type || '/' || subject_kind || '/' || subject_id::text,
           string_agg(id::text, ', ' ORDER BY id::text)
      FROM u GROUP BY action_type, subject_kind, subject_id HAVING count(*) > 1)
  SELECT string_agg(grp || ': ' || ids, '; ' ORDER BY grp) INTO v_bad FROM g;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '157 pre-flight refused: unsettled refund_execute/payout_release duplicates exist: %. Settle or reject them first (an owner decision). Nothing changed.', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '157 pre-flight: 0 orders with more than one unsettled money action';
END
$pre157$;

-- ── 2. internal helpers ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ops.money_order_id(p_subject_kind text, p_subject_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case p_subject_kind
           when 'payment'  then (select p.id from public.payments p where p.id = p_subject_id)
           when 'transfer' then (select t.payment_id from public.transfers t where t.id = p_subject_id)
         end;
$function$;
REVOKE ALL ON FUNCTION ops.money_order_id(text, uuid) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION ops.money_order_id(text, uuid) IS
  '157: the ORDER of a money subject = its payment id (payment: the row''s id; transfer: transfers.payment_id). NULL when the '
  'subject is not a payment/transfer or does not exist. Internal (postgres only).';

CREATE OR REPLACE FUNCTION ops.money_unsettled_blocker(p_order uuid, p_exclude uuid, p_states text[],
                                                       p_action_type text DEFAULT NULL, p_subject_id uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
           'action_id',           a.id,
           'action_type',         a.action_type,
           'subject_kind',        a.subject_kind,
           'subject_id',          a.subject_id,
           'state',               a.state,
           'requested_at',        a.requested_at,
           'requested_by_label',  ops.actor_label(a.requested_by),
           'approval_id',         a.approval_id,
           'approval_expires_at', ap.expires_at,
           'conflict',            case when coalesce(p_action_type, x.action_type) is null then null
                                       when a.action_type = coalesce(p_action_type, x.action_type) then 'same_type'
                                       else 'cross_type' end)
    from ops.action a
    left join ops.approval ap on ap.id = a.approval_id
    left join ops.action x on x.id = p_exclude
   where a.action_type in ('refund_execute','payout_release')
     and a.state = any (p_states)
     and a.id is distinct from p_exclude
     and (   (p_order is not null and a.action_type = 'refund_execute' and a.subject_kind = 'payment' and a.subject_id = p_order)
          or (p_order is not null and a.action_type = 'payout_release' and a.subject_kind = 'transfer'
              and a.subject_id in (select t.id from public.transfers t where t.payment_id = p_order))
          or (p_subject_id is not null and a.action_type = p_action_type and a.subject_id = p_subject_id
              and a.subject_kind = case p_action_type when 'refund_execute' then 'payment' else 'transfer' end))
   order by a.requested_at desc, a.id
   limit 1;
$function$;
REVOKE ALL ON FUNCTION ops.money_unsettled_blocker(uuid, uuid, text[], text, uuid) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION ops.money_unsettled_blocker(uuid, uuid, text[], text, uuid) IS
  '157: the newest refund_execute (payment) / payout_release (its transfer) of an order in p_states, excluding p_exclude, as the '
  'contract''s blocking object; conflict relative to p_action_type (else p_exclude''s type). p_subject_id also matches the '
  'same-type row on exactly that subject (the backstop index key). Internal (postgres only).';

CREATE OR REPLACE FUNCTION ops.expire_stale_money_approvals(p_order uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  n integer := 0;
begin
  if p_order is null then
    return 0;
  end if;
  for r in
    select a.id, a.subject_kind, a.subject_id, a.subject_ref, a.correlation_id, ap.id as approval_id
      from ops.action a
      join ops.approval ap on ap.action_id = a.id and ap.state = 'pending'
     where a.state = 'awaiting_approval'
       and ap.expires_at <= now()
       and (   (a.action_type = 'refund_execute' and a.subject_kind = 'payment' and a.subject_id = p_order)
            or (a.action_type = 'payout_release' and a.subject_kind = 'transfer'
                and a.subject_id in (select t.id from public.transfers t where t.payment_id = p_order)))
     order by a.requested_at, a.id
     for update of a, ap
  loop
    -- ops.approve_action's expiry transition (production body L31-35), statement for statement:
    update ops.approval set state = 'expired' where id = r.approval_id;
    update ops.action set state = 'rejected', reject_reason = 'approval_expired', completed_at = now(), version = version + 1 where id = r.id;
    perform ops.audit_write('approval.expired', r.subject_kind, r.subject_id, r.subject_ref,
                            'approval expired; cleared by the next money request on this order', null, null, 'expired',
                            r.correlation_id, r.id);
    n := n + 1;
  end loop;
  return n;
end;
$function$;
REVOKE ALL ON FUNCTION ops.expire_stale_money_approvals(uuid) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION ops.expire_stale_money_approvals(uuid) IS
  '157: expires the order''s awaiting_approval refund_execute/payout_release whose pending approval has expires_at <= now(), '
  'with ops.approve_action''s expiry transition and audit (approval.expired). Returns how many. Internal (postgres only).';

-- ── 3. ops.execute_action (production body + the 157 money guard) ───────────
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

-- ── 4. ops.approve_action (production body + advisory lock first + non-destructive recheck) ─
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
  v_order uuid;    -- 157
  v_block jsonb;   -- 157
begin
  perform ops.assert_role(array['platform_admin']);
  perform ops.assert_actions_enabled();
  if p_decision not in ('approve','deny') then
    raise exception 'invalid_input: decision must be approve or deny';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'invalid_input: a reason is required';
  end if;
  -- 157 LOCK ORDER for money actions: the order advisory lock FIRST, then the action row FOR UPDATE, then its
  -- approval row; ops.execute_action takes the same advisory lock before it touches any ops.action row, so the
  -- two never wait on each other in opposite orders. The type/subject read here is unlocked (both immutable).
  select ops.money_order_id(x.subject_kind, x.subject_id) into v_order
    from ops.action x
   where x.id = p_action_id and x.action_type in ('refund_execute','payout_release');
  if v_order is not null then
    perform pg_advisory_xact_lock(hashtextextended('ops_money_order:' || v_order::text, 0));
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

  -- 157 approve-time recheck, NON-DESTRUCTIVE: another money action on this order already in flight
  -- (processing / unknown / succeeded_at_provider) refuses this approval without changing any state; the
  -- approval stays pending and can be approved once the other one is succeeded, failed or rejected. Only rows
  -- written outside ops.execute_action (before 157, or by a direct write) can reach this.
  if v_order is not null then
    v_block := ops.money_unsettled_blocker(v_order, a.id, array['processing','unknown','succeeded_at_provider']);
    if v_block is not null then
      return jsonb_build_object('status','rejected','reject_reason','duplicate_unsettled','action_id', a.id, 'state', a.state,
               'message', format('A %s for this %s is already %s (requested %s by %s). This approval is refused until it settles; the approval stays pending.',
                                 v_block ->> 'action_type',
                                 case when v_block ->> 'conflict' = 'same_type' then v_block ->> 'subject_kind' else 'order' end,
                                 case v_block ->> 'state'
                                   when 'unknown'               then 'outcome unknown'
                                   when 'succeeded_at_provider' then 'succeeded at Stripe, awaiting webhook'
                                   else v_block ->> 'state' end,
                                 to_char((v_block ->> 'requested_at')::timestamptz at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"'),
                                 coalesce(v_block ->> 'requested_by_label', 'an operator')),
               'hint', format('Resume or reconcile it (/actions/%s); approve this action again once it is succeeded, failed or rejected.',
                              v_block ->> 'action_id'),
               'blocking', v_block);
    end if;
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

-- ── 5. backstop: one unsettled money action per (type, subject) ─────────────
-- Same-type only; the cross-type rule is the order lock + blocker check (3) and the recheck (4).
CREATE UNIQUE INDEX action_money_unsettled_uidx ON ops.action (action_type, subject_kind, subject_id)
  WHERE action_type IN ('refund_execute','payout_release')
    AND state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider');
COMMENT ON INDEX ops.action_money_unsettled_uidx IS
  '157 backstop: at most one unsettled refund_execute / payout_release per subject. ops.execute_action maps a collision to '
  'reject_reason duplicate_unsettled. Cross-type (refund on P vs payout on P''s transfer) is enforced by the order advisory lock.';

-- ── 6. ops.order_detail (production body + uncapped unsettled_money_actions) ─
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
    -- 157: UNCAPPED: every unsettled refund_execute on the payment and payout_release on its transfer, with the
    -- approval that gates it (drives the console's pending-request guard; 'actions' above stays capped at 50).
    'unsettled_money_actions', coalesce((select jsonb_agg(ops.action_row(a) || jsonb_build_object(
                                     'approval_id',         ap.id,
                                     'approval_expires_at', ap.expires_at,
                                     'approval_expired',    coalesce(ap.state = 'pending' and ap.expires_at <= now(), false))
                                   order by a.requested_at desc, a.id)
                                   from ops.action a left join ops.approval ap on ap.id = a.approval_id
                                  where a.state in ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')
                                    and (   (a.action_type = 'refund_execute' and a.subject_kind = 'payment'  and a.subject_id = p.id)
                                         or (a.action_type = 'payout_release' and a.subject_kind = 'transfer' and a.subject_id = t.id))), '[]'::jsonb),
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

COMMIT;
