-- ============================================================================
-- 144_ops_refund_resolution_detector.sql — a support case for every order whose payment is recorded refunded while
-- the order is still pending, expired without the expiry job's own refund, or sent with its payout blocked; closed
-- only by support, with a classification. Applying it detects nothing: the detector is OFF until the owner turns it on.
--
-- WHY (plan docs/release/REFUND_RESOLUTION_PLAN_20260919.md §4; design docs/operations/REFUND_RESOLUTION_DETECTOR_DESIGN.md).
-- The database cannot tell a partial refund from a full one: payments.status = 'refunded' for either, and no amount is
-- recorded. Nothing tells support that such an order needs a decision: a pending order waits until the seller sends
-- or the 24-hour expiry closes it silently; a sent order's payout is skipped for ever (F-PAYOUT-PARTIAL-1).
--
-- WHAT.
--   * ops."case".case_type gains 'refund_resolution'; ops.case_event.kind gains 'state_changed'.
--   * ops.detect_refund_resolution() (new): one case per transfer (subject = the transfer), p2, no due time, for
--       R1  pending transfer + payment refunded;
--       R2  expired transfer + payment refunded, where the refund is not recognised as the expiry job's own;
--       R3  seller_sent / buyer_confirmed / auto_released transfer + payment refunded + no payout.
--     R4 (a payout exists + payment refunded) is NOT duplicated: detect_reconciliation's p1 reconciliation_mismatch
--     already opens on it. An open case whose transfer reaches R4 records that, points there and stays open.
--     The detector NEVER resolves or sweeps this type. After support closes a case it opens a new one for the same
--     transfer only on a transition the closure did not cover: the same state never reopens; R1 closed as A (full)
--     or C (partial, cancelled, remainder refunded) → R2 stays closed; any other transition opens (design §4).
--   * ops.execute_action: the two new action types are added to its allow-list (its subject pairing already requires
--     a case for any type it does not name).
--   * ops.run_job / ops.run_all_detectors: job 'refund_resolution', skipped for EVERY trigger (manual included) while
--     ops.setting refund_resolution_detector_enabled is false. Seeded false here; turning it on is an audited,
--     approval-gated setting_set by the owner, after the console can send a classification (design §8).
--   * CLASSIFYING IS NOT CLOSING (owner, 2026-09-19). Two new action types, both on ops.execute_action and
--     ops.action_dispatch, named case_* so the dispatch's case_% preamble loads the case and checks the caller's
--     expected version, and so action_allowed_roles gives admin/risk/support:
--       - case_refund_classify {classification A|B|C, assignee?} + reason: records the classification in a
--         'classified' event. It NEVER changes status. It raises the obligation the classification implies —
--         B → payout_owed (nothing releases it today: F-PAYOUT-PARTIAL-1); C → remainder_refund_owed;
--         A → reversal_decision, but only when the transfer was already paid out. When an obligation is raised the
--         case must have an assignee (given here or already set), so money that is owed is never ownerless.
--       - case_refund_obligation {kind, settled, note}: records what happened to an obligation that was raised.
--     case_status resolved/dismissed on a refund_resolution case is then refused unless a classification is recorded
--     and EVERY obligation raised for the case is recorded settled — for 'dismissed' as well as 'resolved', because a
--     dismissal is a closure too. So choosing B, or A on a paid-out order, can never by itself close money that is
--     still owed, and a case cannot be dismissed before anyone has looked at the money.
--     The recorded classification is prefixed to resolution_note and carried in the closing event.
--     Every other case type dispatches exactly as before (211 C15-C17).
--   No public object (Gate-2 census and grant manifests unchanged), no table, no index, no schedule change.
--
-- THE R2 RULE (owner, 2026-09-19; design §2.1). EVERY expired + refunded order opens a case. Nothing is suppressed.
-- A refund id plus a timestamp within ten minutes of expiry does NOT prove the expiry job issued a FULL refund: the
-- database records no refund source and no amount, and `status = 'refunded'` is written for a partial refund too. The
-- earlier rule suppressed exactly the case that hides a remainder owed to a buyer:
--   expiry's own refund FAILS → detect_refunds opens p1 refund_pending → an external PARTIAL refund lands within ten
--   minutes of expiry carrying a refund id → payments.status = 'refunded' → detect_refunds' sweep auto-resolves
--   refund_pending (its query excludes refunded payments) → under the old rule, nothing was left to find.
-- pgTAP 211 (section M) drives that exact sequence. What the database knows about the refund's origin is carried as
-- TRIAGE TEXT in the case summary ("consistent with an expiry-issued refund, but UNCONFIRMED", "…did not come from the
-- expiry job", …) and never hides a case. Safe exclusion needs reliable provenance — the refund's source and amount
-- recorded at the source — which is a server change and the owner's decision.
-- RE-REVIEW TRIGGER (A, 2026-09-19): the rule is valid for the DEPLOYED refund writers only — enforce-transfer-expiry
-- v38 (byte-verified by A, 2026-09-19) and stripe-webhook as in the repository (deployed v41 not byte-read). Before any
-- edge deploy that changes how a refund is recorded (the release candidate's Phase 0 / record_payment_refund /
-- amount_refunded_cents, 20260906110000 / 20260906120000), this rule must be re-reviewed.
--
-- COLLISION WITH 138 (A, 2026-09-19). ops/138-operator-onboarding (unmerged, unapplied) also redefines
-- ops.action_dispatch. 144 sorts after 138, so on a fresh replay 144's body REPLACES 138's. This body is 118's (the
-- gate) plus 144's check. Before any PR, rebase 144's action_dispatch onto the body that lands immediately before it
-- (138's, if 138 merges first) and make the rollback restore that same body. pgTAP 211 pins a pre-existing action type
-- still dispatching (R7); the full suite with both in the chain is the backstop (206 exercises 138).
--
-- ROLLBACK / DISABLE: supabase/rollbacks/144_ops_refund_resolution_detector_rollback.sql never deletes case history
-- (owner, 2026-09-19). With no refund-resolution history it is a full reversal (bodies restored, detector dropped,
-- setting row deleted, all three checks narrowed). With history it DISABLES instead: the same bodies are restored and
-- the detector dropped, the cases, events and actions stay, the vocabulary stays widened because those rows need it,
-- and the setting is set false. RECOVERY is re-applying 144 (idempotent) and the owner flipping the setting; the kept
-- history is picked up again. job_state/job_run rows named 'refund_resolution' stay as history either way.
-- VERIFY (read-only): md5(pg_get_functiondef(...)) of ops.detect_refund_resolution(), ops.run_job(text,text),
--   ops.run_all_detectors(), ops.action_dispatch(ops.action) against the review; pg_get_constraintdef of
--   case_case_type_check and case_event_kind_check; select value from ops.setting
--   where key = 'refund_resolution_detector_enabled';  -- false
-- FAILURE BEHAVIOUR: one transaction; any failure rolls all of it back. The two check widenings take a brief ACCESS
-- EXCLUSIVE lock on ops."case" / ops.case_event and validate their rows (small tables). lock_timeout 3s: behind a
-- running detector tick it fails cleanly instead of queueing; retry between ticks.
-- OWNER APPROVAL POINT: local build only (A, 2026-09-19). No PR, apply or setting flip without the owner.
-- ============================================================================

begin;
-- The two check widenings take ACCESS EXCLUSIVE briefly; fail fast rather than queue behind a detector run.
set local lock_timeout = '3s';

-- ── vocabulary ────────────────────────────────────────────────────────────────────────────────────────────────
-- Each widening EXTENDS the list that is in force rather than restating one (138 may or may not have landed first,
-- and a re-add that loses existing values applies cleanly and only breaks at the first insert — 138's own lesson).
do $vocab$
declare
  v_spec  text[][] := array[['ops."case"', 'case_case_type_check', 'case_type', 'refund_resolution'],
                            ['ops.case_event', 'case_event_kind_check', 'kind', 'state_changed'],
                            ['ops.case_event', 'case_event_kind_check', 'kind', 'classified'],
                            ['ops.case_event', 'case_event_kind_check', 'kind', 'obligation_changed'],
                            ['ops.action', 'action_action_type_check', 'action_type', 'case_refund_classify'],
                            ['ops.action', 'action_action_type_check', 'action_type', 'case_refund_obligation']];
  v_i     integer;
  v_def   text;
  v_list  text;
  v_keep  text[] := array['case_case_type_check:job_failure', 'case_case_type_check:manual',
                          'case_event_kind_check:status_changed', 'case_event_kind_check:auto_resolved',
                          'action_action_type_check:case_create', 'action_action_type_check:payout_release',
                          'action_action_type_check:setting_set'];
  v_pair  text;
begin
  for v_i in 1 .. array_length(v_spec, 1) loop
    select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
     where c.conname = v_spec[v_i][2] and c.conrelid = v_spec[v_i][1]::regclass;
    if v_def is null then
      raise exception '144: % is missing on %', v_spec[v_i][2], v_spec[v_i][1];
    end if;
    continue when position('''' || v_spec[v_i][4] || '''' in v_def) > 0;   -- already admitted (re-apply, or a later base)
    select string_agg(quote_literal(m[1]), ', ' order by ord) into v_list
      from regexp_matches(v_def, '''([a-z_]+)''', 'g') with ordinality as t(m, ord);
    if v_list is null then
      raise exception '144: could not read the values of %', v_spec[v_i][2];
    end if;
    execute format('alter table %s drop constraint %I', v_spec[v_i][1], v_spec[v_i][2]);
    execute format('alter table %s add constraint %I check (%I = any (array[%s, %L]))',
                   v_spec[v_i][1], v_spec[v_i][2], v_spec[v_i][3], v_list, v_spec[v_i][4]);
  end loop;

  -- every value 144 needs is admitted…
  for v_i in 1 .. array_length(v_spec, 1) loop
    select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
     where c.conname = v_spec[v_i][2] and c.conrelid = v_spec[v_i][1]::regclass;
    if position('''' || v_spec[v_i][4] || '''' in v_def) = 0 then
      raise exception '144: % does not admit %', v_spec[v_i][2], v_spec[v_i][4];
    end if;
  end loop;
  -- …and nothing that was admitted before was lost (138's check, same shape)
  foreach v_pair in array v_keep loop
    select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
     where c.conname = split_part(v_pair, ':', 1);
    if position('''' || split_part(v_pair, ':', 2) || '''' in v_def) = 0 then
      raise exception '144: % lost the existing value %', split_part(v_pair, ':', 1), split_part(v_pair, ':', 2);
    end if;
  end loop;
end $vocab$;

-- ── the owner's switch, seeded OFF (feature flags are flipped only by an audited setting_set, never a migration)
insert into ops.setting (key, value) values ('refund_resolution_detector_enabled', 'false'::jsonb) on conflict (key) do nothing;

-- ── the detector ───────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function ops.detect_refund_resolution()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_scanned    integer := 0;
  v_opened     integer := 0;
  v_changed    integer := 0;
  v_suppressed integer := 0;
  r            record;
  v_case_id    uuid;
  v_cur        text;
  v_res        jsonb;
  v_steps      text;
begin
  -- (1) Transfers in R1, R2 or R3 now. The payment is the only refund evidence the database has; the amount refunded
  --     is not recorded, so no state says "full" or "partial": support classifies in Stripe (design §2).
  for r in
    select t.id as transfer_id, t.status as transfer_status, p.stripe_payment_intent_id, p.total, p.amount,
           p.seller_fee, p.refunded_at, l.event_name,
           case when t.status = 'pending' then 'R1' when t.status = 'expired' then 'R2' else 'R3' end as state,
           -- What the database can say about where the refund came from. TRIAGE ONLY: it never hides a case, because
           -- none of it proves the amount. Only Stripe shows the refund's metadata and how much was refunded.
           case when exists (select 1 from ops.action a
                              where a.action_type = 'refund_execute' and a.subject_id = p.id)
                  then 'a console refund_execute action exists for this payment, so the refund did not come from the expiry job'
                when p.stripe_refund_id is null
                  then 'no refund id is recorded, which the expiry job always writes, so the refund did not come from it'
                when p.refunded_at is null
                  then 'no refund timestamp is recorded'
                when p.refunded_at < coalesce(t.expired_at, t.expires_at)
                  then 'the refund was recorded BEFORE expiry, so the expiry job skipped its own refund'
                when p.refunded_at < coalesce(t.expired_at, t.expires_at) + interval '10 minutes'
                  then 'consistent with an expiry-issued refund, but UNCONFIRMED: the database records no refund source and no amount'
                else 'recorded more than 10 minutes after expiry, so it is unlikely to be the expiry job''s own refund'
           end as provenance
      from public.transfers t
      join public.payments p on p.id = t.payment_id
      left join public.listings l on l.id = t.listing_id
     where p.status = 'refunded'
       and (t.status = 'pending'
            -- R2: EVERY expired + refunded order (owner, 2026-09-19). A refund id plus a timestamp near expiry does
            -- not prove the expiry job issued a FULL refund, so it never suppresses a case; it is triage text only.
            or t.status = 'expired'
            or (t.status in ('seller_sent', 'buyer_confirmed', 'auto_released')
                and t.stripe_transfer_id is null and t.payout_released_at is null))
     order by t.id
  loop
    v_scanned := v_scanned + 1;
    v_cur := null;
    select c.id into v_case_id from ops."case" c
     where c.case_type = 'refund_resolution' and c.subject_kind = 'transfer' and c.subject_id = r.transfer_id
       and c.status not in ('resolved', 'dismissed');
    if found then
      -- An open case: follow the state; never resolve it.
      select e.data ->> 'to' into v_cur from ops.case_event e
       where e.case_id = v_case_id and e.kind = 'state_changed' order by e.created_at desc limit 1;
    else
      -- No open case. After support has closed one, reopen only on a transition the closure did not cover (design §4):
      --   the same (transfer, state) closed before → never again;
      --   R1 closed as A (full) or C (partial, cancelled, remainder refunded) → R2 is its natural end;
      --   anything else → open (B's R1 → R2 means fulfilment did not continue; any → R3 means tickets were sent).
      if exists (
           select 1 from ops."case" c
            where c.case_type = 'refund_resolution' and c.subject_kind = 'transfer' and c.subject_id = r.transfer_id
              and c.status in ('resolved', 'dismissed')
              and (select e.data ->> 'to' from ops.case_event e
                    where e.case_id = c.id and e.kind = 'state_changed' order by e.created_at desc limit 1) = r.state)
         or (r.state = 'R2' and exists (
           select 1 from ops."case" c
            where c.case_type = 'refund_resolution' and c.subject_kind = 'transfer' and c.subject_id = r.transfer_id
              and c.status in ('resolved', 'dismissed')
              and (select e.data ->> 'to' from ops.case_event e
                    where e.case_id = c.id and e.kind = 'state_changed' order by e.created_at desc limit 1) = 'R1'
              and (select e.data ->> 'classification' from ops.case_event e
                    where e.case_id = c.id and e.kind = 'classified'
                    order by e.created_at desc limit 1) in ('A', 'C'))) then
        v_suppressed := v_suppressed + 1;
        continue;
      end if;
    end if;

    v_steps := case r.state
      when 'R1' then 'R1: a refund is recorded on an order that is still pending (tickets not marked sent). Steps: '
                  || 'classify the refund in the Stripe Dashboard (payment amount, amount refunded, any transfer); tell '
                  || 'the seller whether to transfer the tickets; for C, refund the remainder in Stripe.'
      when 'R2' then 'R2: the order expired with a refund recorded. Whether the charge is FULLY refunded is unknown '
                  || 'here: a partial refund leaves a remainder owed to the buyer, and the database records no amount. '
                  || 'Steps: in Stripe, check the amount refunded against the charge (the expiry job''s own refunds carry '
                  || 'metadata reason transfer_expired); if a remainder is owed, refund it; tell the buyer and the seller.'
      else          'R3: the tickets are marked sent but the payment is refunded, so the seller payout is blocked and '
                  || 'no tool releases it (F-PAYOUT-PARTIAL-1). Steps: classify the refund in Stripe; escalate the payout '
                  || 'to the owner. A release_stuck case may also be open for this transfer.'
    end;
    v_res := ops.detect_case('refund_resolution', 'transfer', r.transfer_id, null,
               'Refund recorded — support action needed',
               format('%s Provenance (database only, triage): %s. Payment %s for "%s": total $%s, seller net $%s, '
                      || 'recorded refunded at %s; amount refunded: unknown (the database records none). Transfer '
                      || 'status: %s. Classify this case A full refund, B partial refund with fulfilment continuing, '
                      || 'C partial refund with the order cancelled and the remainder refunded.',
                      v_steps, r.provenance, coalesce(r.stripe_payment_intent_id, '?'), coalesce(r.event_name, '?'),
                      to_char(coalesce(r.total, 0) / 100.0, 'FM999999990.00'),
                      to_char((coalesce(r.amount, 0) - coalesce(r.seller_fee, 0)) / 100.0, 'FM999999990.00'),
                      coalesce(to_char(r.refunded_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), 'unknown'),
                      r.transfer_status),
               'p2', null, 'refund_resolution');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
    if v_cur is distinct from r.state then
      -- clock_timestamp: several runs in one transaction still order their state events
      insert into ops.case_event (case_id, actor, kind, data, created_at)
      values ((v_res ->> 'case_id')::uuid, null, 'state_changed', jsonb_build_object('from', v_cur, 'to', r.state),
              clock_timestamp());
      if v_cur is not null then v_changed := v_changed + 1; end if;
    end if;
  end loop;

  -- (2) R4: an open case whose transfer now has a payout while the payment is refunded. detect_reconciliation's p1
  --     reconciliation_mismatch owns that exposure; this case records the transition, points there and stays open.
  for r in
    select c.id as case_id, t.id as transfer_id,
           (select e.data ->> 'to' from ops.case_event e
             where e.case_id = c.id and e.kind = 'state_changed' order by e.created_at desc limit 1) as cur
      from ops."case" c
      join public.transfers t on t.id = c.subject_id
      join public.payments p on p.id = t.payment_id
     where c.case_type = 'refund_resolution' and c.subject_kind = 'transfer'
       and c.status not in ('resolved', 'dismissed')
       and p.status = 'refunded' and t.stripe_transfer_id is not null and t.status <> 'reversed'
  loop
    if r.cur is distinct from 'R4' then
      perform ops.detect_case('refund_resolution', 'transfer', r.transfer_id, null,
                'Refund recorded — support action needed',
                'R4: a payout to the seller exists and the payment is refunded. This exposure is handled by the '
                || 'reconciliation_mismatch case for the payment (a transfer reversal is an owner/finance decision). '
                || 'Close this case with the classification once that is settled.',
                'p2', null, 'refund_resolution');
      insert into ops.case_event (case_id, actor, kind, data, created_at)
      values (r.case_id, null, 'state_changed',
              jsonb_build_object('from', r.cur, 'to', 'R4', 'see', 'reconciliation_mismatch'), clock_timestamp());
      v_changed := v_changed + 1;
    end if;
  end loop;

  -- 'resolved' is always 0: only support closes these cases.
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened, 'resolved', 0,
                            'state_changes', v_changed, 'suppressed', v_suppressed);
end;
$ops$;
revoke all on function ops.detect_refund_resolution() from public, anon, authenticated, service_role;

-- ── ops.run_job (117 body + 144: job name, owner gate for every trigger, dispatch arm) ─────────────────────────
create or replace function ops.run_job(p_job_name text, p_trigger text default 'cron')
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  c_jobs   constant text[] := array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes',
                                    'payout_review','reports','webhooks','jobs','notifications','reconciliation',
                                    'refund_resolution','refresh_metrics','daily_summary'];
  v_uid    uuid := auth.uid();
  v_state  ops.job_state%rowtype;
  v_run_id uuid;
  v_body   jsonb;
  v_skip   text;
  v_err    text;
  v_errstate text;
  v_n      integer;
begin
  if not public.request_is_service_role() then
    perform ops.assert_role(array['platform_admin']);
  end if;
  if p_job_name is null or not (p_job_name = any(c_jobs)) then
    raise exception 'invalid_input: unknown job %', coalesce(p_job_name, '(null)');
  end if;
  if p_trigger is null or p_trigger not in ('cron', 'manual', 'test') then
    raise exception 'invalid_input: trigger must be cron, manual or test';
  end if;

  insert into ops.job_state (job_name) values (p_job_name) on conflict (job_name) do nothing;
  select * into v_state from ops.job_state where job_name = p_job_name for update;

  -- skip rules (cron / test only; a manual run is an operator's explicit choice)
  if p_trigger <> 'manual' then
    if not ops.setting_bool('detectors_enabled', true) then
      v_skip := 'detectors_disabled';
    elsif not v_state.enabled then
      v_skip := 'job_disabled';
    elsif v_state.backoff_until is not null and v_state.backoff_until > now() then
      v_skip := 'backoff';
    end if;
  end if;
  -- 144: the refund-resolution detector runs only after the owner turns it on — for EVERY trigger, manual included.
  if v_skip is null and p_job_name = 'refund_resolution'
     and not ops.setting_bool('refund_resolution_detector_enabled', false) then
    v_skip := 'refund_resolution_disabled';
  end if;
  if v_skip is null and not pg_try_advisory_xact_lock(hashtext('ops.run_job:' || p_job_name)) then
    v_skip := 'overlap';
  end if;
  if v_skip is not null then
    insert into ops.job_run (job_name, trigger, triggered_by, finished_at, status, detail)
    values (p_job_name, p_trigger, v_uid, now(), 'skipped',
            jsonb_build_object('reason', v_skip, 'backoff_until', v_state.backoff_until))
    returning id into v_run_id;
    return jsonb_build_object('status', 'skipped', 'job_run_id', v_run_id,
                              'detail', jsonb_build_object('reason', v_skip, 'backoff_until', v_state.backoff_until));
  end if;

  insert into ops.job_run (job_name, trigger, triggered_by, status, attempt)
  values (p_job_name, p_trigger, v_uid, 'running', v_state.consecutive_failures + 1)
  returning id into v_run_id;
  update ops.job_state set last_run_at = now(), updated_at = now() where job_name = p_job_name;

  begin
    v_body := case p_job_name
      when 'paid_unsettled'     then ops.detect_paid_unsettled()
      when 'transfer_deadlines' then ops.detect_transfer_deadlines()
      when 'release_stuck'      then ops.detect_release_stuck()
      when 'refunds'            then ops.detect_refunds()
      when 'disputes'           then ops.detect_disputes()
      when 'payout_review'      then ops.detect_payout_review()
      when 'reports'            then ops.detect_reports()
      when 'webhooks'           then ops.detect_webhooks()
      when 'jobs'               then ops.detect_jobs()
      when 'notifications'      then ops.detect_notifications()
      when 'reconciliation'     then ops.detect_reconciliation()
      when 'refund_resolution'  then ops.detect_refund_resolution()
      when 'refresh_metrics'    then ops.refresh_metrics()
      when 'daily_summary'      then ops.build_daily_summary()
    end;
  exception when others then
    v_err := sqlerrm; v_errstate := sqlstate;
  end;

  if v_err is not null then
    v_n := v_state.consecutive_failures + 1;
    update ops.job_run
       set status = 'failed', finished_at = now(), error = left(v_errstate || ': ' || v_err, 4000),
           detail = jsonb_build_object('sqlstate', v_errstate, 'consecutive_failures', v_n)
     where id = v_run_id;
    update ops.job_state
       set consecutive_failures = v_n,
           last_error = left(v_errstate || ': ' || v_err, 4000),
           backoff_until = now() + make_interval(mins => least(power(2, v_n)::integer, 60)),
           updated_at = now()
     where job_name = p_job_name;
    return jsonb_build_object('status', 'failed', 'job_run_id', v_run_id,
                              'detail', jsonb_build_object('error', v_err, 'sqlstate', v_errstate,
                                                           'consecutive_failures', v_n));
  end if;

  update ops.job_run
     set status = 'succeeded', finished_at = now(),
         items_scanned  = coalesce((v_body ->> 'scanned')::integer, 0),
         cases_opened   = coalesce((v_body ->> 'opened')::integer, 0),
         cases_resolved = coalesce((v_body ->> 'resolved')::integer, 0),
         detail = v_body
   where id = v_run_id;
  update ops.job_state
     set last_success_at = now(), consecutive_failures = 0, backoff_until = null, last_error = null, updated_at = now()
   where job_name = p_job_name;
  return jsonb_build_object('status', 'succeeded', 'job_run_id', v_run_id, 'detail', v_body);
end;
$ops$;
revoke all on function ops.run_job(text,text) from public, anon, authenticated;
grant execute on function ops.run_job(text,text) to authenticated, service_role;   -- authorizes itself

-- ── ops.run_all_detectors (117 body + 144: in the order, before refresh_metrics) ─────────────────────────────
create or replace function ops.run_all_detectors()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  c_order constant text[] := array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes',
                                   'payout_review','reports','webhooks','jobs','notifications','reconciliation',
                                   'refund_resolution','refresh_metrics'];
  v_name  text;
  v_res   jsonb;
  v_out   jsonb := '{}'::jsonb;
  v_fail  integer := 0;
  v_skip  integer := 0;
begin
  if not public.request_is_service_role() then
    perform ops.assert_role(array['platform_admin']);
  end if;
  foreach v_name in array c_order loop
    v_res := ops.run_job(v_name, 'cron');
    v_out := v_out || jsonb_build_object(v_name, jsonb_build_object('status', v_res ->> 'status', 'job_run_id', v_res ->> 'job_run_id',
                                                                    'opened', v_res #>> '{detail,opened}', 'resolved', v_res #>> '{detail,resolved}'));
    if v_res ->> 'status' = 'failed'  then v_fail := v_fail + 1; end if;
    if v_res ->> 'status' = 'skipped' then v_skip := v_skip + 1; end if;
  end loop;
  return jsonb_build_object('ran_at', now(), 'jobs', cardinality(c_order), 'failed', v_fail, 'skipped', v_skip, 'results', v_out);
end;
$ops$;
revoke all on function ops.run_all_detectors() from public, anon, authenticated;
grant execute on function ops.run_all_detectors() to service_role;

-- ── ops.execute_action (118 body + 144: the two new case_refund_* action types) ───────────────────────────────
-- 138 COLLISION: rebase this body too before any PR (header).
create or replace function ops.execute_action(
  p_idempotency_key text, p_action_type text, p_subject_kind text, p_subject_id uuid,
  p_params jsonb default '{}'::jsonb, p_reason text default null, p_expected jsonb default null,
  p_subject_ref text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
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
$ops$;
revoke all on function ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text) from public, anon, authenticated;
grant execute on function ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text) to authenticated;

-- ── ops.action_dispatch (118 body + 144: classification to close a refund_resolution case) ───────────────────
-- 138 COLLISION: rebase this body onto the one immediately before 144 before any PR (header).
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
revoke all on function ops.action_dispatch(ops.action) from public, anon, authenticated;

commit;
