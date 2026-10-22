-- ============================================================================
-- 20261022001000_ops_refund_refused_after_payout.sql — registry 177 (pgTAP 247). Stacked on 157
-- (20261021100000_ops_money_action_unsettled_guard.sql) and 158 (20261021110000_ops_listing_relist_expected.sql).
-- Owner decision (Jose, 2026-10-21): "Keep manual refunds, no automatic refund after released payout."
-- A sprint 2026-10-21. Server side only; the console already renders the 'rejected' envelope. Prepared and tested on
-- the local production replay only.
--
-- WHY. The console's automated refund (refund_execute: ops.execute_action -> ops.action_precheck -> ops.approve_action
--   -> ops.action_dispatch -> 'processing' handoff to the ops-refund-execute edge, which refunds at Stripe) checked only
--   the PAYMENT (succeeded, full amount). Nothing read the seller payout, so a refund after the payout was released, or
--   while the payout worker was paying it, was accepted, approved and handed off: the buyer is refunded AND the seller
--   keeps the transfer (REFUNDED_AFTER_PAYOUT, detected only afterwards by record_payment_refund ->
--   flag_payout_reversal_required; a reversal is manual). 157 closed only the console-vs-console race (one UNSETTLED
--   refund_execute / payout_release per order). A SETTLED console payout_release (transfer auto_released) and every
--   release outside the console (buyer confirmation, the auto-release cron, a seller-win resolution, the payout worker)
--   left the refund open; pgTAP 224 T5.16 pinned it ("a refund after a SETTLED payout is not blocked").
--
-- RELEASED OR IN FLIGHT, derived from the production payout writers (their md5s are pinned in pgTAP 247 P9.8):
--   a. MONEY MOVED: transfers.payout_released_at IS NOT NULL or transfers.stripe_transfer_id IS NOT NULL. Written
--      together by record_payout_attempt_result('succeeded') (it always records a transfer Stripe reports, F07) and by
--      the legacy record_transfer_payout; no writer clears either column (mark_transfer_reversed changes status only).
--   b. AN ATTEMPT IN FLIGHT OR PAID: a payout_attempts row of the order's transfer in claimed / requested / unknown
--      (claim_payout_attempt's open set, index payout_attempts_one_open: reconciled before any new claim whatever the
--      transfer's status; 'unknown' means Stripe may already hold the transfer) or succeeded / reversal_required (money
--      moved). NOT 'failed': record_payout_attempt_result('failed_not_created') and reconcile_payout_attempt write it
--      when Stripe has no transfer; if Stripe later reports one, record_payout_attempt_result promotes the attempt AND
--      sets (a).
--   c. RELEASE DECIDED: transfers.status IN ('buyer_confirmed','auto_released'), claim_payout_attempt's releasable
--      statuses. From there no further human step is needed: confirm-and-release and the payout sweep
--      (enforce-transfer-expiry phase 2b) claim and pay it. Writers: confirm_transfer_received (the buyer),
--      apply_auto_release (the cron), admin_release_held_payout (the console's payout_release), resolve_transfer_dispute
--      seller_win (the console's dispute_resolve: an unpaid transfer becomes buyer_confirmed). This is the task's
--      "auto_released with a payout claimed": the status flip is the release claim (enforce-transfer-expiry: "Releases
--      claim the row via apply_auto_release()"), and it is what a SETTLED console payout_release leaves behind. Also
--      'reversed' (mark_transfer_reversed, only on a transfer that carried a Stripe transfer, on any reversal, partial
--      or full: the seller may still hold funds).
--   Not released: pending, seller_sent, disputed, expired without (a) or (b); a held or manual-review seller_sent
--   transfer included (only a release decision makes it payable).
--
-- WHAT (ops layer only; ops-refund-execute, ops.executor_claim, every payout function and every other action type are
--   untouched: pgTAP 247 P9.5 / P9.6 strip the marked blocks and get the predecessor bodies byte for byte).
--   1. Pre-flight (read-only DO block): RAISEs, changing nothing, unless ops.action_precheck is production's (md5
--      fbc3d08e…), ops.action_dispatch is 158's (md5 7f507fc8…) and ops.refund_payout_refusal does not exist.
--   2. ops.refund_payout_refusal(p_payment_id uuid, p_stage text) -> jsonb (internal: SECURITY DEFINER, search_path '',
--      STABLE, EXECUTE revoked from PUBLIC / anon / authenticated, the ops.action_precheck ACL): NULL unless the order's
--      transfer matches (a), (b) or (c); otherwise the refusal envelope (CONTRACT below).
--   3. ops.action_precheck = production's body + ONE block, marked '-- 177 begin' / '-- 177 end', at the END of the
--      refund_execute branch: after every existing check, so 'disabled', 'payment not found', stale_state, precondition
--      and not_supported still answer first, byte for byte (pgTAP 247 P8). Request time, no lock.
--   4. ops.action_dispatch = 158's body + ONE marked block at the end of the refund_execute branch, before the
--      'processing' handoff: SELECT 1 FROM public.transfers WHERE payment_id = subject FOR UPDATE, then the same check
--      (stage 'approval'). A payout released or put in flight between the request and the approval (TOCTOU) ->
--      rejected / payout_released: ops.action_run records the action 'rejected' (completed), nothing is handed to
--      ops-refund-execute, executor_claim refuses it ('terminal'). Money not moved.
--
-- CONTRACT FOR THE CONSOLE (F). reject_reason 'payout_released' is new; the shape is the existing rejection envelope.
--   Request (ops.execute_action): {status:'rejected', action_id, reject_reason:'payout_released', message,
--     result:{status:'rejected', reject_reason:'payout_released', message, stage:'request', payout:{transfer_id,
--     transfer_status, payout_released_at, stripe_transfer_id, attempt_id, attempt_no, attempt_state, basis[]}}}.
--     The action row is 'rejected' (key bound, completed, no approval), audited action.requested +
--     action.refund_execute / rejected; replaying the key returns it (idempotent_replay, state rejected).
--   Approval (ops.approve_action -> ops.action_run): {status:'rejected', action_id, reject_reason:'payout_released',
--     message, result:{… stage:'approval' …}}; the approval is consumed (approved), the action is 'rejected'.
--   message: 'Refund refused: the seller payout for this order is released or in flight (<why>). Owner decision
--     2026-10-21: refunds stay manual, and the console never refunds automatically after a released payout. Follow the
--     manual refund SOP (docs/admin-console/MANUAL_REFUND_SOP.md, §2 row 8 and §9) and escalate to the owner. Nothing
--     was refunded.' At approval it begins 'Refund refused at approval: the seller payout for this order is now
--     released or in flight (<why>).' <why> joins with '; ' (each part only when present): 'transfer <status>',
--     'payout recorded YYYY-MM-DD HH24:MI UTC', 'Stripe transfer <tr_…>', 'payout attempt #<n> <state>'.
--   basis, in this order: payout_released_at, stripe_transfer_id, payout_attempt_<state>,
--     status_<buyer_confirmed|auto_released|reversed>.
--   Precedence: 157's duplicate_unsettled answers first (an UNSETTLED payout_release on the order); 177 answers once the
--     payout_release is SETTLED or the payout is released outside the console. Every existing refusal is unchanged.
--
-- LOCK ORDER. approve_action (157): order advisory lock -> ops.action FOR UPDATE -> ops.approval FOR UPDATE ->
--   action_run -> action_dispatch: public.payments FOR UPDATE (unchanged) -> public.transfers FOR UPDATE (new).
--   payments -> transfers is the order record_payment_refund (-> flag_payout_reversal_required) and
--   delete_account_cleanup already take; claim_payout_attempt, record_payout_attempt_result,
--   flag_payout_reversal_required, admin_release_held_payout, apply_auto_release, record_transfer_payout and the buyer's
--   RPCs lock the transfer and never lock payments, so no cycle. Under READ COMMITTED the FOR UPDATE waits for an open
--   payout writer and the check (a new statement, a new snapshot) reads what it committed (two-session rehearsal:
--   private-evidence a177). ops.action_precheck takes no lock (request time; the dispatch is the authority).
--
-- NOT COVERED (by design or scope).
--   - The reverse race: a payout released or claimed AFTER the refund was dispatched ('processing', the edge refunding
--     at Stripe). The payout side (claim_payout_attempt, mark_payout_requested: payments.status and
--     amount_refunded_cents, which change only once the refund is recorded) does not read ops.action, and the payout
--     functions are out of scope. While the dispatch holds the transfer lock apply_auto_release (SKIP LOCKED) skips the
--     row; a later run can release it. REFUNDED_AFTER_PAYOUT detection stays the backstop for that window.
--   - ops.executor_claim (the edge's claim before it calls Stripe) is unchanged: a payout released in the seconds
--     between the approval and the edge's claim is not refused there (a follow-up could call the same helper).
--   - A refund_execute already processing / unknown / succeeded_at_provider when this is applied is not re-checked.
--   - The SOP's human rule is broader (§2 row 8: escalate for any confirmed or released status, buyer_confirmed_at set,
--     and for seller_sent too). 177 enforces the payout writers' predicate; the SOP still governs manual refunds.
--   - The console cannot pre-compute (b): ops.order_detail returns no payout_attempts (a separate change if wanted).
--
-- IMPACT (aggregate counts only, local replay of the 2026-10-15 production snapshot): transfers buyer_confirmed 19 and
--   auto_released 4 (all paid: both money-moved columns set) and reversed 2 => a console refund on any of these 25
--   orders is now refused; disputed 5 and expired 6 are unaffected; payout_attempts holds 0 rows; ops.action holds no
--   refund_execute or payout_release row.
--
-- ROLLOUT (each step an owner decision).
--   1. Read-only pre-checks in production: md5(pg_get_functiondef) of ops.action_precheck = fbc3d08e… and of
--      ops.action_dispatch = 7f507fc8… (157 and 158 applied); ops.refund_payout_refusal absent.
--   2. Apply this file (one transaction; lock_timeout 3s). Locks: no user table (CREATE FUNCTION / CREATE OR REPLACE
--      FUNCTION rewrite pg_proc rows: AccessShare on the schema / language / type / role objects the definitions
--      reference); no reader or writer waits on the apply (pg_locks on a clone before COMMIT: private-evidence a177).
--      An approval already running when this commits finishes with the body it started with.
--   3. Console: no deploy needed. The live console renders "Rejected: payout_released" plus the message. F may later
--      read result.payout / result.stage.
-- ROLLBACK: supabase/rollbacks/20261022001000_ops_refund_refused_after_payout_rollback.sql restores ops.action_precheck
--   VERBATIM from production (md5 fbc3d08e…) and ops.action_dispatch VERBATIM from 158 (md5 7f507fc8…), drops the
--   helper, and verifies md5 + ACL inside the transaction (a mismatch changes nothing). Its stacking guard refuses if a
--   body is neither 177's nor its target. ORDER: roll back 177 BEFORE 158 (158's rollback refuses while
--   ops.action_dispatch is not 158's) and before 157.
-- CI (four-file rule): no change. The rule is public-scoped: Gate-2 counts tables / functions / policies / triggers in
--   'public' (.github/workflows/ci.yml:605-608; :638 records that ops-only migrations add nothing to public), the grant
--   diff reads public only (:723, :730 against supabase/ci/expected_grants.txt), and
--   supabase/ci/assert_public_table_grant_decisions.sql:315 and :601 read schema public. This file creates one ops
--   function and touches nothing in public. The pgTAP gate picks up 247 by glob (ci.yml:795-802).
-- VERIFY (read-only):
--   select md5(pg_get_functiondef('ops.action_precheck(ops.action)'::regprocedure));       -- 20a5ae0386be0644293f5230fad84dde
--   select md5(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure));       -- 530105443dff97cdf1639c12d2bf24f1
--   select md5(pg_get_functiondef('ops.refund_payout_refusal(uuid,text)'::regprocedure));  -- 897a1f932f20cd775795e7bea740c3b4
--   ACLs: all three postgres=X/postgres.
-- FAILURE BEHAVIOUR: one transaction. The pre-flight RAISE, a lock timeout or any error leaves production exactly as it
--   was.
-- OWNER APPROVAL POINT: DRAFT, applied nowhere; prepared and tested locally only. Applying it (after 157 and 158) is a
--   separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 1. pre-flight (read-only): action_precheck = production, action_dispatch = 158, no helper yet ─
DO $pre177$
DECLARE
  v_prec text := md5(pg_get_functiondef(to_regprocedure('ops.action_precheck(ops.action)')));
  v_disp text := md5(pg_get_functiondef(to_regprocedure('ops.action_dispatch(ops.action)')));
  v_help regprocedure := to_regprocedure('ops.refund_payout_refusal(uuid,text)');
BEGIN
  IF v_prec IS DISTINCT FROM 'fbc3d08eae4de831ab3f085e170e8f10' OR v_disp IS DISTINCT FROM '7f507fc880c02617c53d1e4f679c608c'
     OR v_help IS NOT NULL THEN
    RAISE EXCEPTION '177 pre-flight refused (nothing changed): ops.action_precheck md5 % (needs production''s fbc3d08eae4de831ab3f085e170e8f10), ops.action_dispatch md5 % (needs 158''s 7f507fc880c02617c53d1e4f679c608c), ops.refund_payout_refusal % (needs absent). Apply 157 (20261021100000) and 158 (20261021110000) first; do not re-apply 177.',
      coalesce(v_prec, '<missing>'), coalesce(v_disp, '<missing>'), CASE WHEN v_help IS NULL THEN 'absent' ELSE 'present' END
      USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '177 pre-flight: action_precheck = production, action_dispatch = 158, helper absent';
END
$pre177$;

-- ── 2. internal helper: the payout check and the refusal envelope ─────────
CREATE OR REPLACE FUNCTION ops.refund_payout_refusal(p_payment_id uuid, p_stage text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 177: NULL unless the seller payout of the order (payment p_payment_id) is released or in flight; then the refusal
  -- envelope. Released or in flight (derived from the production payout writers; see migration 20261022001000):
  --   a. transfers.payout_released_at or stripe_transfer_id set (record_payout_attempt_result, record_transfer_payout);
  --   b. a payout attempt claimed / requested / unknown (claim_payout_attempt's open set) or succeeded /
  --      reversal_required; a 'failed' attempt (no Stripe transfer) is not;
  --   c. the transfer is buyer_confirmed / auto_released (claim_payout_attempt's releasable statuses) or reversed.
  with tr as (
    select t.id, t.status, t.payout_released_at, t.stripe_transfer_id,
           pa.id as attempt_id, pa.attempt_no, pa.state as attempt_state
      from public.transfers t
      left join lateral (
             select a.id, a.attempt_no, a.state
               from public.payout_attempts a
              where a.transfer_id = t.id
                and a.state in ('claimed','requested','unknown','succeeded','reversal_required')
              order by a.attempt_no desc
              limit 1) pa on true
     where t.payment_id = p_payment_id),
  b as (
    select tr.*,
           array_remove(array[
             case when tr.payout_released_at is not null then 'payout_released_at' end,
             case when tr.stripe_transfer_id is not null then 'stripe_transfer_id' end,
             case when tr.attempt_id is not null then 'payout_attempt_' || tr.attempt_state end,
             case when tr.status in ('buyer_confirmed','auto_released','reversed') then 'status_' || tr.status end], null) as basis,
           concat_ws('; ',
             'transfer ' || tr.status,
             'payout recorded ' || to_char(tr.payout_released_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"'),
             'Stripe transfer ' || tr.stripe_transfer_id,
             'payout attempt #' || tr.attempt_no || ' ' || tr.attempt_state) as why
      from tr)
  select jsonb_build_object(
           'status',        'rejected',
           'reject_reason', 'payout_released',
           'message',       format(case when p_stage = 'approval'
                                        then 'Refund refused at approval: the seller payout for this order is now released or in flight (%s). '
                                        else 'Refund refused: the seller payout for this order is released or in flight (%s). ' end
                                   || 'Owner decision 2026-10-21: refunds stay manual, and the console never refunds automatically after a released payout. '
                                   || 'Follow the manual refund SOP (docs/admin-console/MANUAL_REFUND_SOP.md, §2 row 8 and §9) and escalate to the owner. Nothing was refunded.',
                                   b.why),
           'stage',         p_stage,
           'payout',        jsonb_build_object(
                              'transfer_id',        b.id,
                              'transfer_status',    b.status,
                              'payout_released_at', b.payout_released_at,
                              'stripe_transfer_id', b.stripe_transfer_id,
                              'attempt_id',         b.attempt_id,
                              'attempt_no',         b.attempt_no,
                              'attempt_state',      b.attempt_state,
                              'basis',              to_jsonb(b.basis)))
    from b
   where cardinality(b.basis) > 0;
$function$
;
REVOKE ALL ON FUNCTION ops.refund_payout_refusal(uuid, text) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION ops.refund_payout_refusal(uuid, text) IS
  '177: NULL unless the order''s seller payout is released or in flight (money-moved columns, a claimed / requested / unknown / '
  'succeeded / reversal_required payout attempt, or a buyer_confirmed / auto_released / reversed transfer); then the refund_execute '
  'refusal envelope (reject_reason payout_released, p_stage request | approval). Internal (postgres only).';

-- ── 3. ops.action_precheck (production body + the marked 177 block) ────────
CREATE OR REPLACE FUNCTION ops.action_precheck(p_action ops.action)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row record;
begin
  case p_action.action_type
  when 'payout_release' then
    select status, payout_released_at, disputed_at, dispute_resolved_at, payout_review_status
      into v_row from public.transfers where id = p_action.subject_id;
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
    if p_action.expected is not null and (p_action.expected ->> 'payout_review_status') is distinct from v_row.payout_review_status then
      return jsonb_build_object('status','rejected','reject_reason','stale_state','message','payout review state changed since you loaded it');
    end if;
  when 'refund_execute' then
    if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'refund_execute_enabled'), false) then
      return jsonb_build_object('status','rejected','reject_reason','disabled',
               'message','refund execution is disabled until the ops-refund-execute function is deployed (see runbook); use the Stripe Dashboard SOP');
    end if;
    select status, total into v_row from public.payments where id = p_action.subject_id;
    if not found then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','payment not found');
    end if;
    if v_row.status <> 'succeeded' then
      return jsonb_build_object('status','rejected','reject_reason','stale_state', 'message', format('payment is %s; only a succeeded payment can be refunded', v_row.status));
    end if;
    if (p_action.params ->> 'amount_cents') is not null
       and ((p_action.params ->> 'amount_cents')::integer <= 0 or (p_action.params ->> 'amount_cents')::integer > v_row.total) then
      return jsonb_build_object('status','rejected','reject_reason','precondition','message','amount must be between 1 and the payment total');
    end if;
    if (p_action.params ->> 'amount_cents') is not null
       and (p_action.params ->> 'amount_cents')::integer <> v_row.total then
      return jsonb_build_object('status','rejected','reject_reason','not_supported',
               'message','partial refunds are not supported in this release: the local money model records refund status only (no refunded amount), so a partial refund would be reported as a full one. Request a full refund or use the Stripe Dashboard SOP.');
    end if;
    -- 177 begin: no automatic refund once the order's seller payout is released or in flight (owner decision
    -- 2026-10-21, migration 20261022001000). Runs after every existing check, so each existing answer is unchanged;
    -- ops.action_dispatch re-checks under the transfer row lock when the refund is approved.
    declare
      v_refusal jsonb := ops.refund_payout_refusal(p_action.subject_id, 'request');
    begin
      if v_refusal is not null then
        return v_refusal;
      end if;
    end;
    -- 177 end
  else
    null;
  end case;
  return null;
end;
$function$
;
REVOKE ALL ON FUNCTION ops.action_precheck(ops.action) FROM PUBLIC, anon, authenticated;

-- ── 4. ops.action_dispatch (158's body + the marked 177 block in refund_execute) ─
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
    -- 177 begin: re-check at approval, under the order's transfer row lock, that the seller payout is neither released
    -- nor in flight (released after the request was parked: the cron, a buyer confirmation, a seller-win resolution,
    -- the payout worker). Lock order payments -> transfers, as record_payment_refund; the payout writers lock the
    -- transfer and never lock payments, so this waits for an open claim / release / payout record and then reads it.
    perform 1 from public.transfers t where t.payment_id = a.subject_id for update;
    v_res := ops.refund_payout_refusal(a.subject_id, 'approval');
    if v_res is not null then
      return v_res;
    end if;
    -- 177 end
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
