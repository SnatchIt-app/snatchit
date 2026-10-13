-- ============================================================================
-- ROLLBACK for 20261013000000_marketplace_safety_enforcement.sql (registry 152).
-- Restores the APPLIED bodies that precede 152: ops.action_dispatch from 144 and
-- public.can_create_listing from 013 (verbatim). Drops the three triggers and five functions.
-- History is never deleted: ops.user_restriction rows of kind 'suspended' stay, and while any
-- exists the kind check stays widened (narrowing would fail on them).
-- CONSEQUENCE: after this rollback, blocks are a client-side hide again, recorded suspensions are
-- NOT enforced, and listing text is checked only by the app. Lift recorded suspensions through the
-- console first, or re-apply 152, before relying on any of them.
-- Run only under owner approval, with D's read-back.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DROP TRIGGER IF EXISTS before_bid_guard_parties ON public.bids;
DROP TRIGGER IF EXISTS trg_guard_listing_reservation_parties ON public.listings;
DROP TRIGGER IF EXISTS trg_guard_listing_content ON public.listings;
DROP FUNCTION IF EXISTS public.guard_bid_parties();
DROP FUNCTION IF EXISTS public.guard_listing_reservation_parties();
DROP FUNCTION IF EXISTS public.guard_listing_content();
DROP FUNCTION IF EXISTS public.listing_prohibited_term(text[]);
DROP FUNCTION IF EXISTS public.assert_marketplace_parties(uuid, uuid);

-- 013's body, verbatim
CREATE OR REPLACE FUNCTION public.can_create_listing(p_seller_id uuid)
RETURNS TABLE (
  allowed   boolean,
  reason    text,
  risk_tier text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_risk_tier         text;
  v_is_blocked        boolean;
BEGIN
  -- Caller must be the seller themselves
  IF auth.uid() IS DISTINCT FROM p_seller_id THEN
    RAISE EXCEPTION 'Unauthorized: caller does not match p_seller_id';
  END IF;

  -- Fetch current risk posture
  SELECT
    srs.risk_tier,
    srs.is_listing_blocked
  INTO
    v_risk_tier,
    v_is_blocked
  FROM seller_risk_scores srs
  WHERE srs.seller_id = p_seller_id;

  -- No row → new/clean seller → allow
  IF NOT FOUND THEN
    RETURN QUERY SELECT true, 'ok'::text, NULL::text;
    RETURN;
  END IF;

  -- Hard block: admin has toggled is_listing_blocked
  IF v_is_blocked THEN
    RETURN QUERY SELECT false, 'listing_blocked'::text, v_risk_tier;
    RETURN;
  END IF;

  -- Critical tier: block listing creation
  IF v_risk_tier = 'critical' THEN
    RETURN QUERY SELECT false, 'critical_risk'::text, v_risk_tier;
    RETURN;
  END IF;

  -- High tier: allow with warning
  IF v_risk_tier = 'high' THEN
    RETURN QUERY SELECT true, 'high_risk_warning'::text, v_risk_tier;
    RETURN;
  END IF;

  -- Medium tier: allow with light warning
  IF v_risk_tier = 'medium' THEN
    RETURN QUERY SELECT true, 'medium_risk_warning'::text, v_risk_tier;
    RETURN;
  END IF;

  -- Low tier: all clear
  RETURN QUERY SELECT true, 'ok'::text, v_risk_tier;
END;
$$;

-- 144's body, verbatim
create or replace function ops.action_dispatch(p_action ops.action)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
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
    v_res := public.admin_relist_listing(a.subject_id, (a.params ->> 'new_ends_at')::timestamptz, v_uid);
    return jsonb_build_object('status','succeeded','result', v_res);

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
    if coalesce(a.params ->> 'kind','listing_blocked') <> 'listing_blocked' then
      return jsonb_build_object('status','rejected','reject_reason','not_supported','message','only listing_blocked is enforceable (can_create_listing); account suspension has no backend mechanism');
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
$ops$;

DO $rb$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM ops.user_restriction WHERE kind = 'suspended') THEN
    ALTER TABLE ops.user_restriction DROP CONSTRAINT IF EXISTS user_restriction_kind_check;
    ALTER TABLE ops.user_restriction ADD CONSTRAINT user_restriction_kind_check CHECK (kind IN ('listing_blocked'));
  ELSE
    RAISE NOTICE '152 rollback: suspension history exists; kind check left widened, rows kept';
  END IF;
END
$rb$;

COMMIT;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261013000000' AND to_regprocedure('public.assert_marketplace_parties(uuid,uuid)') IS NULL AND to_regprocedure('public.guard_bid_parties()') IS NULL AND to_regprocedure('public.guard_listing_reservation_parties()') IS NULL AND to_regprocedure('public.guard_listing_content()') IS NULL AND to_regprocedure('public.listing_prohibited_term(text[])') IS NULL AND md5(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure)) = 'a1b6c7f63121d2027e55e9d99ba07f9b' AND md5(pg_get_functiondef('public.can_create_listing(uuid)'::regprocedure)) = '8369a2a6ee4f0b777c9eafcacfe8df62';
