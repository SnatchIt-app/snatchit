-- Registry214 / pgTAP282. Local candidate only; no hosted authorization.
BEGIN;
SET LOCAL lock_timeout='3s';
DO $pre214$ BEGIN
IF md5(pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure)) <> '0ca6121d0306605cc8daab5415c450c0' THEN RAISE EXCEPTION 'PREFLIGHT_214_BODY_CHANGED: public.claim_payout_attempt(uuid,text,interval)'; END IF;
IF md5(pg_get_functiondef('ops.executor_claim(uuid,integer)'::regprocedure)) <> '23025535815c199354a75f31c768351c' THEN RAISE EXCEPTION 'PREFLIGHT_214_BODY_CHANGED: ops.executor_claim(uuid,integer)'; END IF;
IF md5(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure)) <> 'd2579c0f72d09570d2463e8ce3046a12' THEN RAISE EXCEPTION 'PREFLIGHT_214_BODY_CHANGED: ops.action_dispatch(ops.action)'; END IF;
IF md5(pg_get_functiondef('ops.action_precheck(ops.action)'::regprocedure)) <> '092aa4d6ae428653cd9b9d4cf845b0c0' THEN RAISE EXCEPTION 'PREFLIGHT_214_BODY_CHANGED: ops.action_precheck(ops.action)'; END IF;
END $pre214$;
CREATE OR REPLACE FUNCTION public.claim_payout_attempt(p_transfer_id uuid, p_actor text, p_lease interval DEFAULT '00:10:00'::interval)
 RETURNS TABLE(attempt_id uuid, attempt_no integer, idempotency_key text, destination text, amount_cents integer, source_charge_id text, payment_intent_id text, needs_reconcile boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order212 uuid;
  v_refund212 uuid;
  v_t     public.transfers%ROWTYPE;
  v_p     public.payments%ROWTYPE;
  v_open  public.payout_attempts%ROWTYPE;
  v_dest  text;
  v_pi    text;
  v_no    int;
  v_amt   int;
  v_lease interval := coalesce(p_lease, interval '10 minutes');
BEGIN
  IF v_lease <= interval '0' OR v_lease > interval '1 hour' THEN
    v_lease := interval '10 minutes';
  END IF;

  SELECT payment_id INTO v_order212 FROM public.transfers WHERE id=p_transfer_id;
  -- 212: shared payment lock must precede every action/approval/domain row lock.
  IF v_order212 is not null then
    IF current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'MONEY_ACTION_REQUIRES_READ_COMMITTED' using errcode='25001';
    END IF;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ops_money_order:' || v_order212::text,0));
  END IF;
  SELECT * INTO v_t FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSFER_NOT_FOUND';
  END IF;

  IF v_t.payment_id IS DISTINCT FROM v_order212 THEN
    RAISE EXCEPTION 'MONEY_ACTION_IDENTITY_CHANGED' USING ERRCODE='40001';
  END IF;

  -- An open attempt always wins: it is reconciled, never duplicated. This
  -- check precedes eligibility so an attempt stuck 'unknown' on a transfer
  -- that has since been disputed is still reconciled (F07 compounding).
  SELECT * INTO v_open FROM public.payout_attempts a
   WHERE a.transfer_id = p_transfer_id AND a.state IN ('claimed','requested','unknown')
   FOR UPDATE;
  IF FOUND THEN
    IF v_open.lease_expires_at > now() THEN
      -- Another worker owns it. Handing it out could let this caller mark a
      -- POST that is in flight elsewhere as failed.
      RAISE EXCEPTION 'PAYOUT_ATTEMPT_IN_PROGRESS' USING DETAIL = v_open.id::text;
    END IF;
    UPDATE public.payout_attempts SET lease_expires_at = now() + v_lease WHERE id = v_open.id;
    SELECT p.stripe_payment_intent_id INTO STRICT v_pi FROM public.payments p WHERE p.id = v_open.payment_id;
    RETURN QUERY SELECT v_open.id, v_open.attempt_no, v_open.idempotency_key, v_open.destination,
                        v_open.amount_cents, v_open.source_charge_id, v_pi, true;
    RETURN;
  END IF;

  -- 212: open-attempt reconciliation above always wins; guard only fresh money.
  SELECT a.id INTO v_refund212 FROM ops.action a
   WHERE a.action_type='refund_execute' AND a.subject_kind='payment' AND a.subject_id=v_t.payment_id
     AND a.state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')
   ORDER BY a.requested_at,a.id LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'REFUND_IN_FLIGHT' USING DETAIL=v_refund212::text;
  END IF;

  -- Eligibility (the 056d predicate plus the payment-side truths).
  IF v_t.payout_released_at IS NOT NULL OR v_t.stripe_transfer_id IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.payout_attempts a WHERE a.transfer_id = p_transfer_id AND a.state IN ('succeeded','reversal_required')) THEN
    RAISE EXCEPTION 'ALREADY_RELEASED';
  END IF;
  IF v_t.disputed_at IS NOT NULL AND v_t.dispute_resolution IS DISTINCT FROM 'resolved_seller_paid' THEN
    RAISE EXCEPTION 'DISPUTED';
  END IF;
  IF v_t.status NOT IN ('buyer_confirmed','auto_released') THEN
    RAISE EXCEPTION 'TRANSFER_NOT_RELEASABLE' USING DETAIL = 'status=' || v_t.status;
  END IF;
  -- 20260924000000 (registry 148, F-DISPUTE-SELLERWIN-1). A seller-win dispute
  -- resolution (065) leaves status 'buyer_confirmed' with buyer_confirmed_at NULL
  -- and dispute_resolution 'resolved_seller_paid'. That is an OPERATOR'S decision,
  -- not the buyer's statement, so it does NOT inherit the genuine buyer
  -- confirmation's override of risk holds: manual_review, or a payout_hold_until
  -- still in the future (or 'held' with no end), keeps it unpayable. The asymmetry
  -- is deliberate — do not harmonise it with the genuine-confirmation path, which
  -- stays exactly as before (buyer_confirmed_at IS NOT NULL is never tested here).
  IF v_t.status = 'buyer_confirmed' AND v_t.buyer_confirmed_at IS NULL
     AND v_t.dispute_resolution = 'resolved_seller_paid' THEN
    IF v_t.payout_review_status = 'manual_review' THEN
      RAISE EXCEPTION 'PAYOUT_UNDER_REVIEW';
    END IF;
    IF (v_t.payout_hold_until IS NOT NULL AND v_t.payout_hold_until > now())
       OR (v_t.payout_review_status = 'held' AND v_t.payout_hold_until IS NULL) THEN
      RAISE EXCEPTION 'PAYOUT_HELD' USING DETAIL = coalesce(v_t.payout_hold_until::text, 'no end');
    END IF;
  END IF;

  -- 214: existing native intent producers hold this same payment row.
  PERFORM 1 FROM public.payments WHERE id=v_t.payment_id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM kernel.refund r WHERE r.payment_id=v_t.payment_id AND r.status <> 'failed') THEN
    RAISE EXCEPTION 'NATIVE_REFUND_IN_FLIGHT';
  END IF;

  SELECT * INTO v_p FROM public.payments WHERE id = v_t.payment_id;
  IF NOT FOUND OR v_p.status <> 'succeeded' THEN
    RAISE EXCEPTION 'PAYMENT_NOT_SUCCEEDED' USING DETAIL = coalesce(v_p.status, '<missing>');
  END IF;
  -- Mode boundary (045): never pay out against a non-live capture. The
  -- sandbox-only switch app.allow_test_mode_money = 'on' (ALTER DATABASE on an
  -- isolated test project; never production) admits stripe_livemode = false
  -- rows so a Stripe test key can exercise real Connect test transfers. NULL
  -- (unclassified) is never admitted.
  IF v_p.stripe_livemode IS DISTINCT FROM true
     AND NOT (v_p.stripe_livemode IS NOT DISTINCT FROM false
              AND coalesce(current_setting('app.allow_test_mode_money', true), 'off') = 'on') THEN
    RAISE EXCEPTION 'PAYMENT_NOT_LIVE';
  END IF;
  IF v_p.stripe_payment_intent_id IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_SUCCEEDED' USING DETAIL = 'no payment intent id';
  END IF;
  -- A partially refunded charge (review round 2, MINOR-3): the platform no
  -- longer retains amount - seller_fee, and who bears a partial refund is an
  -- operator decision. Never pay automatically; the transfer stays an
  -- unpaid_seller_obligation until an operator settles it (DAY5 playbook).
  IF coalesce(v_p.amount_refunded_cents, 0) > 0 THEN
    RAISE EXCEPTION 'PAYMENT_PARTIALLY_REFUNDED'
      USING DETAIL = v_p.amount_refunded_cents::text || '/' || v_p.total::text;
  END IF;

  SELECT pr.stripe_connect_id INTO v_dest FROM public.profiles pr WHERE pr.id = v_t.seller_id;
  IF v_dest IS NULL OR v_dest = '' THEN
    RAISE EXCEPTION 'SELLER_NOT_ONBOARDED';
  END IF;

  -- 10/10 fee model: seller net = amount − seller_fee (integer cents).
  v_amt := v_p.amount - coalesce(v_p.seller_fee, 0);
  IF v_amt <= 0 THEN
    RAISE EXCEPTION 'PAYOUT_AMOUNT_INVALID' USING DETAIL = v_amt::text;
  END IF;

  -- The open-attempt branch above always reconciles. Only throttle fresh
  -- scheduled attempts, while holding the same transfer lock as the insert.
  IF p_actor = 'cron:enforce-transfer-expiry' AND EXISTS (
    SELECT 1
      FROM (
        SELECT a.state, a.error, a.resolved_at
          FROM public.payout_attempts a
         WHERE a.transfer_id = p_transfer_id
         ORDER BY a.attempt_no DESC
         LIMIT 1
      ) latest
     WHERE latest.state = 'failed'
       AND latest.resolved_at > now() - interval '1 hour'
       AND (
         latest.error->>'reason_code' = 'PAYOUT_INSUFFICIENT_FUNDS'
         OR latest.error->>'error_class' IN ('insufficient_funds', 'balance_insufficient')
       )
  ) THEN
    RAISE EXCEPTION 'PAYOUT_FUNDING_COOLDOWN';
  END IF;

  SELECT coalesce(max(a.attempt_no), 0) + 1 INTO v_no FROM public.payout_attempts a WHERE a.transfer_id = p_transfer_id;

  INSERT INTO public.payout_attempts
    (transfer_id, payment_id, attempt_no, state, destination, amount_cents, currency, source_charge_id,
     idempotency_key, actor, lease_expires_at)
  VALUES
    (p_transfer_id, v_p.id, v_no, 'claimed', v_dest, v_amt, 'usd', NULL,
     'payout_' || p_transfer_id::text || '_a' || v_no::text, coalesce(p_actor, 'unknown'), now() + v_lease)
  RETURNING * INTO v_open;

  RETURN QUERY SELECT v_open.id, v_open.attempt_no, v_open.idempotency_key, v_open.destination,
                      v_open.amount_cents, v_open.source_charge_id, v_p.stripe_payment_intent_id, false;
END; $function$;
CREATE OR REPLACE FUNCTION ops.executor_claim(p_action_id uuid, p_lease_seconds integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order212 uuid;
  v_identity212 ops.action%rowtype;
  a    ops.action%rowtype;
  ap   ops.approval%rowtype;
  p    public.payments%rowtype;
  v_prev_sent boolean;
  v_cb        bigint;
  v_unobs     bigint;
  v_detail    jsonb;
begin
  if not public.request_is_service_role() then
    raise exception 'insufficient_privilege: service_role only' using errcode = '42501';
  end if;
  select * into v_identity212 from ops.action where id=p_action_id;
  v_order212 := case when v_identity212.action_type='refund_execute' and v_identity212.subject_kind='payment' then v_identity212.subject_id when v_identity212.action_type='payout_release' and v_identity212.subject_kind='transfer' then (select t.payment_id from public.transfers t where t.id=v_identity212.subject_id) end;
  -- 212: shared payment lock must precede every action/approval/domain row lock.
  if v_order212 is not null then
    if current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'MONEY_ACTION_REQUIRES_READ_COMMITTED' using errcode='25001';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ops_money_order:' || v_order212::text,0));
  end if;
  select * into a from ops.action where id = p_action_id for update;
  if (a.action_type,a.subject_kind,a.subject_id) is distinct from
     (v_identity212.action_type,v_identity212.subject_kind,v_identity212.subject_id)
     or v_order212 is distinct from (case when a.action_type='refund_execute' and a.subject_kind='payment' then a.subject_id when a.action_type='payout_release' and a.subject_kind='transfer' then (select t.payment_id from public.transfers t where t.id=a.subject_id) end) then
    raise exception 'MONEY_ACTION_IDENTITY_CHANGED' using errcode='40001';
  end if;

  if not found then
    return jsonb_build_object('status','refused','reason','not_found');
  end if;
  if a.action_type <> 'refund_execute' then
    return jsonb_build_object('status','refused','reason','wrong_type','state', a.state);
  end if;
  if a.state in ('succeeded','failed','rejected') then
    return jsonb_build_object('status','refused','reason','terminal','state', a.state);
  end if;
  if a.state = 'succeeded_at_provider' then
    return jsonb_build_object('status','refused','reason','succeeded_at_provider','state', a.state, 'provider_ref', a.provider_ref);
  end if;
  if a.state not in ('processing','unknown') then
    return jsonb_build_object('status','refused','reason','not_executable','state', a.state);
  end if;
  if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'actions_enabled'), true) then
    return jsonb_build_object('status','refused','reason','paused','state', a.state);
  end if;
  if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'refund_execute_enabled'), false) then
    return jsonb_build_object('status','refused','reason','disabled','state', a.state);
  end if;
  select * into ap from ops.approval where action_id = a.id and state = 'approved' order by decided_at desc limit 1;
  if not found then
    return jsonb_build_object('status','refused','reason','approval_missing','state', a.state);
  end if;
  if ap.action_hash <> ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params) then
    return jsonb_build_object('status','refused','reason','approval_stale','state', a.state);
  end if;
  if a.claimed_until is not null and a.claimed_until > now() then
    return jsonb_build_object('status','refused','reason','claim_busy','state', a.state, 'claimed_until', a.claimed_until);
  end if;
  select * into p from public.payments where id = a.subject_id;
  if not found then
    return jsonb_build_object('status','refused','reason','payment_missing','state', a.state);
  end if;
  v_prev_sent := a.attempt > 0 or a.provider_ref is not null or (a.result ? 'stripe_request_started_at');
  if not coalesce(v_prev_sent,false) then
    -- 214: payment is the cross-rail fence; never acquire a new advisory here.
    select * into p from public.payments where id=a.subject_id for update;
    if exists (select 1 from kernel.refund r where r.payment_id=a.subject_id and r.status <> 'failed') then
      return jsonb_build_object('status','refused','reason','native_refund_in_flight','state',a.state);
    end if;
  -- 212 guard begin: duplicate-unsettled precedence, then payout release.
  if v_order212 is not null then
    if exists (select 1 from ops.action sibling
      where sibling.id is distinct from a.id
        and sibling.state in ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')
        and ((sibling.action_type='refund_execute' and sibling.subject_kind='payment' and sibling.subject_id=v_order212)
          or (sibling.action_type='payout_release' and sibling.subject_kind='transfer' and sibling.subject_id in
             (select t.id from public.transfers t where t.payment_id=v_order212)))) then
      return jsonb_build_object('status','refused','reason','duplicate_unsettled','message','An unsettled money action already exists for this payment.');
    end if;
    if a.action_type='refund_execute' and exists (
      select 1 from public.transfers t where t.payment_id=v_order212
        and (t.payout_released_at is not null or t.stripe_transfer_id is not null
          or exists (select 1 from public.payout_attempts pa where pa.transfer_id=t.id
            and pa.state in ('claimed','requested','unknown','succeeded','reversal_required')))) then
      return jsonb_build_object('status','refused','reason','payout_released','message','Refund refused: seller payout is released or in flight. Use the manual refund review.');
    end if;
  end if;
  -- 212 guard end.
  end if;
  if p.refund_succeeded_cents >= p.total then
    return jsonb_build_object('status','refused','reason','already_refunded_locally','state', a.state, 'stripe_refund_id', p.stripe_refund_id);
  end if;
  if p.status = 'refunded' then
    v_cb := coalesce((select sum(pr.amount_cents) from public.payment_refunds pr
                       where pr.payment_id = p.id and pr.source = 'dispute_lost'), 0);
    v_detail := jsonb_build_object('payment_status', p.status, 'total_cents', p.total,
                                   'requested_cents', p.refund_requested_cents,
                                   'succeeded_cents', p.refund_succeeded_cents,
                                   'failed_cents', p.refund_failed_cents,
                                   'amount_refunded_cents', p.amount_refunded_cents,
                                   'chargeback_cents', v_cb,
                                   'previously_sent', v_prev_sent);
    if p.refund_succeeded_cents + v_cb >= p.total then
      return jsonb_build_object('status','refused','reason','charged_back','state', a.state, 'detail', v_detail);
    end if;
    if not coalesce(v_prev_sent, false) then
      v_unobs := coalesce((select sum(pr.amount_cents) from public.payment_refunds pr
                            where pr.payment_id = p.id and pr.source <> 'dispute_lost'
                              and pr.stripe_refund_id is not null
                              and not exists (select 1 from public.payment_refund_state s
                                               where s.stripe_refund_id = pr.stripe_refund_id)), 0);
      if v_unobs > 0 then
        return jsonb_build_object('status','refused','reason','refund_state_unobserved','state', a.state,
                                  'detail', v_detail || jsonb_build_object('unobserved_cents', v_unobs));
      end if;
      return jsonb_build_object('status','refused','reason','refund_state_unresolved','state', a.state, 'detail', v_detail);
    end if;
    if p.stripe_payment_intent_id is null then
      return jsonb_build_object('status','refused','reason','payment_not_refundable','state', a.state, 'payment_status', p.status);
    end if;
  elsif p.status <> 'succeeded' or p.stripe_payment_intent_id is null then
    return jsonb_build_object('status','refused','reason','payment_not_refundable','state', a.state, 'payment_status', p.status);
  end if;
  -- Preserve the established full-refund/chargeback/reconciliation refusals
  -- above. Only a genuinely fresh otherwise-eligible claim reaches this fence.
  if not coalesce(v_prev_sent,false) then
    if coalesce(p.amount_refunded_cents,0)>0 or coalesce(p.refund_requested_cents,0)>0
       or coalesce(p.refund_succeeded_cents,0)>0
       or exists (select 1 from public.payment_refunds pr where pr.payment_id=a.subject_id and pr.amount_cents>0) then
      return jsonb_build_object('status','refused','reason','refund_exposure','state',a.state);
    end if;
  end if;
  update ops.action
     set claimed_until = now() + make_interval(secs => greatest(coalesce(p_lease_seconds, 300), 30)),
         attempt = attempt + 1,
         state = 'processing',
         version = version + 1
   where id = a.id;
  perform ops.audit_write('action.claim.refund_execute', a.subject_kind, a.subject_id, a.subject_ref, null,
                          jsonb_build_object('state', a.state, 'attempt', a.attempt),
                          jsonb_build_object('attempt', a.attempt + 1, 'previously_sent', v_prev_sent),
                          'claimed', a.correlation_id, a.id);
  return jsonb_build_object(
    'status', 'claimed', 'action_id', a.id, 'payment_id', p.id,
    'stripe_payment_intent_id', p.stripe_payment_intent_id,
    'amount_cents', p.total, 'payment_total_cents', p.total, 'currency', 'usd',
    'reason_code', a.params ->> 'reason_code',
    'previously_sent', v_prev_sent, 'provider_ref', a.provider_ref, 'attempt', a.attempt + 1,
    'stripe_livemode', p.stripe_livemode);
end;
$function$;
CREATE OR REPLACE FUNCTION ops.action_dispatch(p_action ops.action)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order212 uuid;
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
  v_order212 := case when a.action_type='refund_execute' and a.subject_kind='payment' then a.subject_id when a.action_type='payout_release' and a.subject_kind='transfer' then (select t.payment_id from public.transfers t where t.id=a.subject_id) end;
  -- 212: shared payment lock must precede every action/approval/domain row lock.
  if v_order212 is not null then
    if current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'MONEY_ACTION_REQUIRES_READ_COMMITTED' using errcode='25001';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ops_money_order:' || v_order212::text,0));
  end if;
  -- 212 guard begin: duplicate-unsettled precedence, then payout release.
  if v_order212 is not null then
    if exists (select 1 from ops.action sibling
      where sibling.id is distinct from a.id
        and sibling.state in ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')
        and ((sibling.action_type='refund_execute' and sibling.subject_kind='payment' and sibling.subject_id=v_order212)
          or (sibling.action_type='payout_release' and sibling.subject_kind='transfer' and sibling.subject_id in
             (select t.id from public.transfers t where t.payment_id=v_order212)))) then
      return jsonb_build_object('status','rejected','reject_reason','duplicate_unsettled','message','An unsettled money action already exists for this payment.');
    end if;
    if a.action_type='refund_execute' and exists (
      select 1 from public.transfers t where t.payment_id=v_order212
        and (t.payout_released_at is not null or t.stripe_transfer_id is not null
          or exists (select 1 from public.payout_attempts pa where pa.transfer_id=t.id
            and pa.state in ('claimed','requested','unknown','succeeded','reversal_required')))) then
      return jsonb_build_object('status','rejected','reject_reason','payout_released','message','Refund refused: seller payout is released or in flight. Use the manual refund review.');
    end if;
  end if;
  -- 212 guard end.
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
$function$;
CREATE OR REPLACE FUNCTION ops.action_precheck(p_action ops.action)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare   v_order212 uuid;
v_row record;
begin
  v_order212 := case when p_action.action_type='refund_execute' and p_action.subject_kind='payment' then p_action.subject_id when p_action.action_type='payout_release' and p_action.subject_kind='transfer' then (select t.payment_id from public.transfers t where t.id=p_action.subject_id) end;
  -- 212 guard begin: duplicate-unsettled precedence, then payout release.
  if v_order212 is not null then
    if exists (select 1 from ops.action sibling
      where sibling.id is distinct from p_action.id
        and sibling.state in ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')
        and ((sibling.action_type='refund_execute' and sibling.subject_kind='payment' and sibling.subject_id=v_order212)
          or (sibling.action_type='payout_release' and sibling.subject_kind='transfer' and sibling.subject_id in
             (select t.id from public.transfers t where t.payment_id=v_order212)))) then
      return jsonb_build_object('status','rejected','reject_reason','duplicate_unsettled','message','An unsettled money action already exists for this payment.');
    end if;
    if p_action.action_type='refund_execute' and exists (
      select 1 from public.transfers t where t.payment_id=v_order212
        and (t.payout_released_at is not null or t.stripe_transfer_id is not null
          or exists (select 1 from public.payout_attempts pa where pa.transfer_id=t.id
            and pa.state in ('claimed','requested','unknown','succeeded','reversal_required')))) then
      return jsonb_build_object('status','rejected','reject_reason','payout_released','message','Refund refused: seller payout is released or in flight. Use the manual refund review.');
    end if;
  end if;
  -- 212 guard end.
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
  else
    null;
  end case;
  return null;
end;
$function$;
-- Internal service gate. A committed pending native refund fences later opposite
-- allocations; the payment row serializes against every existing native producer.
-- No DB lock survives the RPC response or spans a provider request.
CREATE FUNCTION kernel.authorize_fresh_refund(p_refund_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $gate214$
DECLARE
  v_payment uuid;
  r kernel.refund%ROWTYPE;
  p public.payments%ROWTYPE;
BEGIN
  IF NOT public.request_is_service_role() THEN
    RAISE EXCEPTION 'insufficient_privilege: service_role only' USING ERRCODE='42501';
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'MONEY_ACTION_REQUIRES_READ_COMMITTED' USING ERRCODE='25001';
  END IF;
  SELECT payment_id INTO v_payment FROM kernel.refund WHERE refund_id=p_refund_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('allowed',false,'reason','not_found'); END IF;
  SELECT * INTO p FROM public.payments WHERE id=v_payment FOR UPDATE;
  SELECT * INTO r FROM kernel.refund WHERE refund_id=p_refund_id;
  IF NOT FOUND OR r.payment_id IS DISTINCT FROM v_payment THEN
    RETURN jsonb_build_object('allowed',false,'reason','identity_changed');
  END IF;
  IF r.status <> 'pending' OR r.stripe_refund_ref IS NOT NULL THEN
    RETURN jsonb_build_object('allowed',false,'reason','reconcile_only');
  END IF;
  IF kernel.refund_executor_hold(p_refund_id) IS NOT NULL THEN
    RETURN jsonb_build_object('allowed',false,'reason','executor_hold');
  END IF;
  IF EXISTS (SELECT 1 FROM public.transfers t WHERE t.payment_id=v_payment
      AND (t.payout_released_at IS NOT NULL OR t.stripe_transfer_id IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.payout_attempts a WHERE a.payment_id=v_payment
        AND a.state IN ('claimed','requested','unknown','succeeded','reversal_required')) THEN
    RETURN jsonb_build_object('allowed',false,'reason','payout_exposure');
  END IF;
  IF EXISTS (SELECT 1 FROM ops.action a WHERE a.action_type='refund_execute'
      AND a.subject_kind='payment' AND a.subject_id=v_payment
      AND a.state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider','succeeded')) THEN
    RETURN jsonb_build_object('allowed',false,'reason','console_refund_exposure');
  END IF;
  -- Public mirrors of this rail's own earlier partial refunds are already in
  -- the native sum guard. Count only unbound/mismatched provider exposure or
  -- aggregate truth exceeding the refs that the native ledger accounts for.
  IF EXISTS (SELECT 1 FROM public.payment_refunds pr WHERE pr.payment_id=v_payment AND pr.amount_cents>0
      AND NOT EXISTS (SELECT 1 FROM kernel.refund kr WHERE kr.payment_id=v_payment
        AND kr.stripe_refund_ref=pr.stripe_refund_id AND kr.amount_minor=pr.amount_cents))
     OR EXISTS (SELECT 1 FROM public.payment_refund_state ps WHERE ps.payment_id=v_payment
      AND ps.status IN ('pending','requires_action','succeeded') AND ps.amount_cents>0
      AND NOT EXISTS (SELECT 1 FROM kernel.refund kr WHERE kr.payment_id=v_payment
        AND kr.stripe_refund_ref=ps.stripe_refund_id AND kr.amount_minor=ps.amount_cents))
     OR coalesce(p.amount_refunded_cents,0) > coalesce((SELECT sum(pr.amount_cents)
        FROM public.payment_refunds pr WHERE pr.payment_id=v_payment AND EXISTS
          (SELECT 1 FROM kernel.refund kr WHERE kr.payment_id=v_payment
            AND kr.stripe_refund_ref=pr.stripe_refund_id AND kr.amount_minor=pr.amount_cents)),0)
     OR coalesce(p.refund_requested_cents,0) > coalesce((SELECT sum(ps.amount_cents)
        FROM public.payment_refund_state ps WHERE ps.payment_id=v_payment AND ps.status IN ('pending','requires_action')
          AND EXISTS (SELECT 1 FROM kernel.refund kr WHERE kr.payment_id=v_payment
            AND kr.stripe_refund_ref=ps.stripe_refund_id AND kr.amount_minor=ps.amount_cents)),0)
     OR coalesce(p.refund_succeeded_cents,0) > coalesce((SELECT sum(ps.amount_cents)
        FROM public.payment_refund_state ps WHERE ps.payment_id=v_payment AND ps.status='succeeded'
          AND EXISTS (SELECT 1 FROM kernel.refund kr WHERE kr.payment_id=v_payment
            AND kr.stripe_refund_ref=ps.stripe_refund_id AND kr.amount_minor=ps.amount_cents)),0)
     OR EXISTS (SELECT 1 FROM kernel.dispute_native d WHERE d.payment_id=v_payment AND d.status IN ('lost','charge_refunded')) THEN
    RETURN jsonb_build_object('allowed',false,'reason','provider_refund_exposure');
  END IF;
  RETURN jsonb_build_object('allowed',true);
END;
$gate214$;
REVOKE ALL ON FUNCTION kernel.authorize_fresh_refund(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION kernel.authorize_fresh_refund(uuid) TO service_role;
DO $post214$ BEGIN
 IF md5(pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure)) IS DISTINCT FROM '247abd8a3e6a88524e0994410d303e7d' THEN RAISE EXCEPTION 'POSTFLIGHT_214_BODY_CHANGED: public.claim_payout_attempt(uuid,text,interval)'; END IF;
 IF md5(pg_get_functiondef('ops.executor_claim(uuid,integer)'::regprocedure)) IS DISTINCT FROM '22363ed1eb9be27d79f5bfabd44de398' THEN RAISE EXCEPTION 'POSTFLIGHT_214_BODY_CHANGED: ops.executor_claim(uuid,integer)'; END IF;
 IF md5(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure)) IS DISTINCT FROM 'a9d8dd7513a94ea17e2f59fdfe31520e' THEN RAISE EXCEPTION 'POSTFLIGHT_214_BODY_CHANGED: ops.action_dispatch(ops.action)'; END IF;
 IF md5(pg_get_functiondef('ops.action_precheck(ops.action)'::regprocedure)) IS DISTINCT FROM '07fa56bd68fcb405b2963159ebdbfad4' THEN RAISE EXCEPTION 'POSTFLIGHT_214_BODY_CHANGED: ops.action_precheck(ops.action)'; END IF;
 IF has_function_privilege('anon','kernel.authorize_fresh_refund(uuid)','EXECUTE')
 OR has_function_privilege('authenticated','kernel.authorize_fresh_refund(uuid)','EXECUTE')
 OR NOT has_function_privilege('service_role','kernel.authorize_fresh_refund(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'POSTFLIGHT_214_ACL_CHANGED';
 END IF;
END $post214$;
COMMIT;
