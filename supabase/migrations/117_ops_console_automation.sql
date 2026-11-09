-- ============================================================================
-- 117_ops_console_automation.sql — Operating Console package, part 3 of 3.
--
-- WHAT THIS MIGRATION IS. Additive only, functions only. Installs the console's
-- automation inside the `ops` schema created by 115: the durable job runner
-- (`ops.run_job`), thirteen SQL job bodies (eleven detectors that open and
-- auto-resolve exception cases, a metric refresher, a daily-summary builder),
-- the alert helpers, the cron entry (`ops.run_all_detectors`) and two pg_cron
-- registrations. Design decision 9 (docs/admin-console/DESIGN_AND_EXECUTION_PLAN.md
-- §2.9, §3.5, §5): pg_cron every 5 min → run_job(name) → durable ops.job_run,
-- ops.job_state with consecutive-failure backoff, advisory lock against
-- overlap, duplicate-safe case upsert by dedupe_key (115 ops.case_upsert),
-- auto-resolve when the condition clears (115 ops.case_auto_resolve).
--
-- READ-ONLY OVER DOMAIN STATE. Every detector only SELECTs from public.*,
-- notify.* and cron.*; the only writes are to ops.* tables owned by 115.
-- ZERO changes to public.* objects (Gate-2 parity untouched). Nothing here
-- references a 110–114 object.
--
-- AUTHZ. ops.run_job is the only callable surface: service_role (pg_cron runs
-- as the owner with no JWT claims → request_is_service_role() is true) OR a
-- platform_admin operator with an aal2 session (the 115 `job_retry` action's
-- manual retry path). Every job body and helper is REVOKED from every client
-- role; only run_job (SECURITY DEFINER, owner) reaches them.
--
-- cron.job_run_details is read only when present (`to_regclass(...)`), through
-- dynamic SQL — it does not exist in the local rehearsal DB, where cron.schedule
-- is a stand-in over a plain cron.job table (registration is rehearsed,
-- execution is not — scripts/rehearsal_bootstrap.sql fidelity ledger).
--
-- DEPLOYMENT POSTURE: LOCAL / REHEARSAL. Requires 115 (tables + case engine).
-- Independent of 116 (read API) — no function named in design §3.3 is created
-- or referenced here.
--
-- Rollback: supabase/rollbacks/117_ops_console_automation_rollback.sql
-- Verification: select ops.run_all_detectors();                         -- as service_role
--               select job_name, status from ops.job_run order by started_at desc limit 13;
--               select jobname from cron.job where jobname like 'ops-%'; -- 2 rows
-- Locks/runtime: CREATE FUNCTION + two cron.job rows; no table rewrite.
-- ============================================================================
begin;

-- ----------------------------------------------------------------------------
-- PART 1 — helpers (settings readers, alert dedup, detector case wrapper)
-- ----------------------------------------------------------------------------
create or replace function ops.setting_int(p_key text, p_default integer)
returns integer language sql stable security definer set search_path = ''
as $ops$
  select coalesce((select nullif(s.value #>> '{}', '')::integer from ops.setting s where s.key = p_key), p_default);
$ops$;
revoke all on function ops.setting_int(text,integer) from public, anon, authenticated, service_role;

create or replace function ops.setting_bool(p_key text, p_default boolean)
returns boolean language sql stable security definer set search_path = ''
as $ops$
  select coalesce((select nullif(s.value #>> '{}', '')::boolean from ops.setting s where s.key = p_key), p_default);
$ops$;
revoke all on function ops.setting_bool(text,boolean) from public, anon, authenticated, service_role;

-- Fire (or re-fire) an alert. Deduped by key: an already-firing alert only
-- bumps last_fired_at / fire_count / payload; a recovered one starts firing
-- again with a fresh first_fired_at.
create or replace function ops.alert_fire(p_key text, p_kind text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare v_state text;
begin
  select state into v_state from ops.alert where alert_key = p_key for update;
  if not found then
    insert into ops.alert (alert_key, kind, state, payload)
    values (p_key, p_kind, 'firing', coalesce(p_payload, '{}'::jsonb));
    return jsonb_build_object('alert_key', p_key, 'fired', true, 'was', null);
  end if;
  update ops.alert
     set state = 'firing',
         kind = p_kind,
         payload = coalesce(p_payload, payload),
         last_fired_at = now(),
         fire_count = fire_count + 1,
         first_fired_at = case when v_state = 'recovered' then now() else first_fired_at end,
         recovered_at = null
   where alert_key = p_key;
  return jsonb_build_object('alert_key', p_key, 'fired', v_state = 'recovered', 'was', v_state);
end;
$ops$;
revoke all on function ops.alert_fire(text,text,jsonb) from public, anon, authenticated, service_role;

create or replace function ops.alert_recover(p_key text)
returns boolean language plpgsql security definer set search_path = ''
as $ops$
declare v_n integer;
begin
  update ops.alert set state = 'recovered', recovered_at = now()
   where alert_key = p_key and state = 'firing';
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$ops$;
revoke all on function ops.alert_recover(text) from public, anon, authenticated, service_role;

-- Recover every firing alert whose key starts with p_prefix and whose suffix is
-- NOT in the still-active set — the alert twin of ops.case_auto_resolve.
create or replace function ops.alert_recover_stale(p_prefix text, p_active_suffixes text[])
returns integer language plpgsql security definer set search_path = ''
as $ops$
declare v_n integer;
begin
  update ops.alert set state = 'recovered', recovered_at = now()
   where state = 'firing'
     and left(alert_key, length(p_prefix)) = p_prefix
     and not (substr(alert_key, length(p_prefix) + 1) = any(coalesce(p_active_suffixes, array[]::text[])));
  get diagnostics v_n = row_count;
  return v_n;
end;
$ops$;
revoke all on function ops.alert_recover_stale(text,text[]) from public, anon, authenticated, service_role;

-- Detector-side case writer: ops.case_upsert plus the p1 alert rule (any p1
-- case OPENED fires alert `case:<dedupe_key>`; a touched-but-already-open case
-- does not re-fire). Returns case_upsert's jsonb {case_id, opened, dedupe_key}.
create or replace function ops.detect_case(
  p_case_type text, p_subject_kind text, p_subject_id uuid, p_subject_ref text,
  p_title text, p_summary text, p_priority text, p_due_at timestamptz, p_detector text)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare v_res jsonb;
begin
  v_res := ops.case_upsert(p_case_type, p_subject_kind, p_subject_id, p_subject_ref,
                           p_title, p_summary, p_priority, p_due_at, p_detector);
  if p_priority = 'p1' and (v_res ->> 'opened')::boolean then
    perform ops.alert_fire('case:' || (v_res ->> 'dedupe_key'), 'p1_case',
              jsonb_build_object('case_id', v_res ->> 'case_id', 'case_type', p_case_type,
                                 'subject_kind', p_subject_kind, 'subject_id', p_subject_id,
                                 'subject_ref', p_subject_ref, 'title', p_title, 'detector', p_detector));
  end if;
  return v_res;
end;
$ops$;
revoke all on function ops.detect_case(text,text,uuid,text,text,text,text,timestamptz,text) from public, anon, authenticated, service_role;

-- Detector-side sweep: auto-resolve cleared cases of one type AND recover their
-- `case:` alerts. Returns the number of cases resolved.
create or replace function ops.detect_sweep(p_case_type text, p_active_keys text[])
returns integer language plpgsql security definer set search_path = ''
as $ops$
declare v_n integer;
begin
  v_n := ops.case_auto_resolve(p_case_type, p_active_keys);
  perform ops.alert_recover_stale('case:' || p_case_type || ':',
            (select array_agg(substr(k, length(p_case_type) + 2)) from unnest(coalesce(p_active_keys, array[]::text[])) k));
  return v_n;
end;
$ops$;
revoke all on function ops.detect_sweep(text,text[]) from public, anon, authenticated, service_role;

-- `*/N * * * *` → N minutes; anything else → 25 hours (daily-or-slower jobs).
create or replace function ops.cron_interval_minutes(p_schedule text)
returns integer language sql immutable
as $ops$
  select case when p_schedule ~ '^\*/[0-9]+ \* \* \* \*$'
              then substring(p_schedule from '^\*/([0-9]+)')::integer
              else 25 * 60 end;
$ops$;
revoke all on function ops.cron_interval_minutes(text) from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- PART 2 — detectors. Each: read-only over domain state, idempotent (dedupe by
-- case_type:subject via ops.case_upsert), auto-resolves cleared conditions,
-- returns {scanned, opened, resolved}. Internal: only ops.run_job calls them.
-- ----------------------------------------------------------------------------

-- paid_unsettled — a succeeded payment older than the grace window whose
-- listing is not 'sold' OR that has no transfer row. Money captured with no
-- marketplace consequence → p1.
create or replace function ops.detect_paid_unsettled()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_grace   integer := ops.setting_int('paid_unsettled_grace_minutes', 10);
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
  v_why     text;
begin
  for r in
    select p.id, p.total, p.amount, p.paid_at, p.created_at, p.stripe_payment_intent_id,
           l.status as listing_status, l.event_name,
           exists (select 1 from public.transfers t where t.payment_id = p.id) as has_transfer
      from public.payments p
      left join public.listings l on l.id = p.listing_id
     where p.status = 'succeeded'
       and coalesce(p.paid_at, p.created_at) < now() - make_interval(mins => v_grace)
       and (l.status is distinct from 'sold'
            or not exists (select 1 from public.transfers t where t.payment_id = p.id))
     order by coalesce(p.paid_at, p.created_at)
  loop
    v_scanned := v_scanned + 1;
    v_why := concat_ws('; ',
               case when r.listing_status is distinct from 'sold'
                    then format('listing.status is %s (expected sold)', coalesce(r.listing_status, 'missing')) end,
               case when not r.has_transfer then 'no transfer row exists for this payment' end);
    v_res := ops.detect_case('paid_unsettled', 'payment', r.id, null,
               'Paid but not settled',
               format('Payment %s captured $%s (%s) at %s for "%s" — %s.',
                      r.stripe_payment_intent_id, to_char(r.total / 100.0, 'FM999999990.00'), 'USD',
                      to_char(coalesce(r.paid_at, r.created_at) at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                      coalesce(r.event_name, '?'), v_why),
               'p1', null, 'paid_unsettled');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('paid_unsettled', v_keys));
end;
$ops$;
revoke all on function ops.detect_paid_unsettled() from public, anon, authenticated, service_role;

-- transfer_deadlines — pending transfers approaching (transfer_deadline_soon,
-- p2, due_at = expires_at) or past (transfer_overdue, p1) their expiry.
create or replace function ops.detect_transfer_deadlines()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_soon    integer := ops.setting_int('transfer_deadline_soon_hours', 6);
  v_soon_keys    text[] := array[]::text[];
  v_overdue_keys text[] := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  v_resolved integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select t.id, t.expires_at, t.created_at, l.event_name, p.total
      from public.transfers t
      left join public.listings l on l.id = t.listing_id
      left join public.payments p on p.id = t.payment_id
     where t.status = 'pending'
       and t.expires_at is not null
       and t.expires_at < now() + make_interval(hours => v_soon)
     order by t.expires_at
  loop
    v_scanned := v_scanned + 1;
    if r.expires_at < now() then
      v_res := ops.detect_case('transfer_overdue', 'transfer', r.id, null,
                 'Transfer overdue',
                 format('Seller has not sent the tickets for "%s" ($%s); the delivery window expired at %s and the transfer is still pending (expiry job has not acted).',
                        coalesce(r.event_name, '?'), to_char(coalesce(r.total, 0) / 100.0, 'FM999999990.00'),
                        to_char(r.expires_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')),
                 'p1', r.expires_at, 'transfer_deadlines');
      v_overdue_keys := v_overdue_keys || (v_res ->> 'dedupe_key');
    else
      v_res := ops.detect_case('transfer_deadline_soon', 'transfer', r.id, null,
                 'Transfer deadline approaching',
                 format('Seller has not sent the tickets for "%s" ($%s); the delivery window closes at %s.',
                        coalesce(r.event_name, '?'), to_char(coalesce(r.total, 0) / 100.0, 'FM999999990.00'),
                        to_char(r.expires_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')),
                 'p2', r.expires_at, 'transfer_deadlines');
      v_soon_keys := v_soon_keys || (v_res ->> 'dedupe_key');
    end if;
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  v_resolved := ops.detect_sweep('transfer_deadline_soon', v_soon_keys)
              + ops.detect_sweep('transfer_overdue', v_overdue_keys);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened, 'resolved', v_resolved);
end;
$ops$;
revoke all on function ops.detect_transfer_deadlines() from public, anon, authenticated, service_role;

-- release_stuck — a release decision exists but the connected-account transfer
-- has not happened: (a) auto_released / buyer_confirmed, payout_released_at
-- null, no stripe_transfer_id, decision older than the window; (b) released
-- locally (payout_released_at set) but still no provider transfer id.
create or replace function ops.detect_release_stuck()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_mins    integer := ops.setting_int('release_stuck_minutes', 30);
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select t.id, t.status, t.payout_released_at, t.auto_release_at, t.buyer_confirmed_at, l.event_name, p.amount, p.seller_fee,
           case when t.payout_released_at is null
                then case when t.status = 'auto_released' then coalesce(t.auto_release_at, t.buyer_confirmed_at)
                          else coalesce(t.buyer_confirmed_at, t.auto_release_at) end
                else t.payout_released_at end as since,
           (t.payout_released_at is not null) as released_locally
      from public.transfers t
      left join public.listings l on l.id = t.listing_id
      left join public.payments p on p.id = t.payment_id
     where t.stripe_transfer_id is null
       and ((t.status in ('auto_released', 'buyer_confirmed') and t.payout_released_at is null)
            or t.payout_released_at is not null)
       and (t.disputed_at is null or t.dispute_resolved_at is not null)
       and t.status <> 'reversed'
  loop
    if r.since is null or r.since >= now() - make_interval(mins => v_mins) then continue; end if;
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('release_stuck', 'transfer', r.id, null,
               'Seller funds release stuck',
               case when r.released_locally
                    then format('Transfer for "%s" was released locally at %s but has no provider transfer id (stripe_transfer_id null); seller net $%s has not moved to the connected account.',
                                coalesce(r.event_name, '?'), to_char(r.since at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                                to_char((coalesce(r.amount, 0) - coalesce(r.seller_fee, 0)) / 100.0, 'FM999999990.00'))
                    else format('Transfer for "%s" is %s since %s with payout_released_at null and no stripe_transfer_id; seller net $%s awaiting release for more than %s minutes.',
                                coalesce(r.event_name, '?'), r.status, to_char(r.since at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                                to_char((coalesce(r.amount, 0) - coalesce(r.seller_fee, 0)) / 100.0, 'FM999999990.00'), v_mins) end,
               'p2', null, 'release_stuck');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('release_stuck', v_keys));
end;
$ops$;
revoke all on function ops.detect_release_stuck() from public, anon, authenticated, service_role;

-- refunds — refund_pending (buyer is owed money and the payment is not
-- refunded: dispute resolved for the buyer, or an expired transfer with a
-- succeeded payment > 60 min) and refund_failed (an ops refund_execute action
-- failed / unknown, or stuck at succeeded_at_provider > 60 min without the
-- charge.refunded webhook landing). Subject = payment for both.
create or replace function ops.detect_refunds()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_pending_keys text[] := array[]::text[];
  v_failed_keys  text[] := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  v_resolved integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select p.id as payment_id, p.status as payment_status, p.total, p.stripe_payment_intent_id, t.id as transfer_id,
           l.event_name,
           case when t.dispute_resolution in ('resolved_buyer_refunded', 'resolved_partial_refund')
                then format('dispute resolved %s at %s', t.dispute_resolution,
                            to_char(t.dispute_resolved_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'))
                else format('transfer expired at %s and the payment is still succeeded',
                            to_char(coalesce(t.expired_at, t.expires_at) at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')) end as why
      from public.transfers t
      join public.payments p on p.id = t.payment_id
      left join public.listings l on l.id = t.listing_id
     where p.status <> 'refunded'
       and ((t.dispute_resolution in ('resolved_buyer_refunded', 'resolved_partial_refund'))
            or (t.status = 'expired' and p.status = 'succeeded'
                and coalesce(t.expired_at, t.expires_at, t.created_at) < now() - interval '60 minutes'))
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('refund_pending', 'payment', r.payment_id, null,
               'Refund owed to buyer',
               format('Payment %s ($%s, status %s) for "%s": %s. No refund has landed (payments.status <> refunded).',
                      r.stripe_payment_intent_id, to_char(coalesce(r.total, 0) / 100.0, 'FM999999990.00'),
                      r.payment_status, coalesce(r.event_name, '?'), r.why),
               'p1', null, 'refunds');
    v_pending_keys := v_pending_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;

  for r in
    select a.id as action_id, a.subject_id as payment_id, a.state, a.error, a.provider_ref, a.updated_at, a.completed_at
      from ops.action a
     where a.action_type = 'refund_execute'
       and a.subject_id is not null
       and (a.state in ('failed', 'unknown')
            or (a.state = 'succeeded_at_provider' and a.updated_at < now() - interval '60 minutes'))
       and not exists (select 1 from public.payments p where p.id = a.subject_id and p.status = 'refunded')
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('refund_failed', 'payment', r.payment_id, null,
               'Refund execution needs attention',
               format('ops action %s (refund_execute) is %s%s%s; the payment is not refunded locally.',
                      r.action_id, r.state,
                      case when r.provider_ref is not null then format(' (provider ref %s)', r.provider_ref) else '' end,
                      case when r.error is not null then format(': %s', left(r.error, 500)) else '' end),
               'p1', null, 'refunds');
    v_failed_keys := v_failed_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;

  v_resolved := ops.detect_sweep('refund_pending', v_pending_keys) + ops.detect_sweep('refund_failed', v_failed_keys);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened, 'resolved', v_resolved);
end;
$ops$;
revoke all on function ops.detect_refunds() from public, anon, authenticated, service_role;

-- disputes — dispute_open (marketplace dispute on a transfer, SLA clock from
-- disputed_at, p1) and dispute_evidence_due (Stripe dispute with an evidence
-- deadline; p1 inside 72h, p2 otherwise).
create or replace function ops.detect_disputes()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_sla     integer := ops.setting_int('dispute_sla_hours', 72);
  v_open_keys     text[] := array[]::text[];
  v_evidence_keys text[] := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  v_resolved integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select t.id, t.disputed_at, t.dispute_reason, t.status, l.event_name, p.total
      from public.transfers t
      left join public.listings l on l.id = t.listing_id
      left join public.payments p on p.id = t.payment_id
     where t.disputed_at is not null and t.dispute_resolved_at is null
     order by t.disputed_at
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('dispute_open', 'transfer', r.id, null,
               'Open dispute awaiting resolution',
               format('Buyer disputed "%s" ($%s) at %s (reason %s); transfer status %s. SLA %s h.',
                      coalesce(r.event_name, '?'), to_char(coalesce(r.total, 0) / 100.0, 'FM999999990.00'),
                      to_char(r.disputed_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                      coalesce(r.dispute_reason, 'unspecified'), r.status, v_sla),
               'p1', r.disputed_at + make_interval(hours => v_sla), 'disputes');
    v_open_keys := v_open_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;

  for r in
    select d.id, d.stripe_dispute_id, d.amount, d.status, d.evidence_due_by, d.payment_id
      from public.disputes d
     where d.status not in ('won', 'lost', 'warning_closed', 'charge_refunded')
       and d.evidence_due_by is not null
     order by d.evidence_due_by
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('dispute_evidence_due', 'dispute', r.id, null,
               'Stripe dispute evidence due',
               format('Stripe dispute %s ($%s, status %s) needs evidence by %s%s.',
                      r.stripe_dispute_id, to_char(coalesce(r.amount, 0) / 100.0, 'FM999999990.00'), r.status,
                      to_char(r.evidence_due_by at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                      case when r.payment_id is not null then format(' (payment %s)', r.payment_id) else '' end),
               case when r.evidence_due_by < now() + interval '72 hours' then 'p1' else 'p2' end,
               r.evidence_due_by, 'disputes');
    v_evidence_keys := v_evidence_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;

  v_resolved := ops.detect_sweep('dispute_open', v_open_keys) + ops.detect_sweep('dispute_evidence_due', v_evidence_keys);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened, 'resolved', v_resolved);
end;
$ops$;
revoke all on function ops.detect_disputes() from public, anon, authenticated, service_role;

-- payout_review — seller_sent transfers parked in manual_review by the risk
-- engine (039), not yet released. due_at = auto_release_at.
create or replace function ops.detect_payout_review()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select t.id, t.auto_release_at, t.payout_risk_tier, t.payout_reason_codes, l.event_name, p.amount, p.seller_fee
      from public.transfers t
      left join public.listings l on l.id = t.listing_id
      left join public.payments p on p.id = t.payment_id
     where t.payout_review_status = 'manual_review'
       and t.payout_released_at is null
       and t.status = 'seller_sent'
     order by t.auto_release_at nulls last
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('payout_review', 'transfer', r.id, null,
               'Payout held for manual review',
               format('Seller net $%s for "%s" is in manual_review (risk tier %s%s)%s.',
                      to_char((coalesce(r.amount, 0) - coalesce(r.seller_fee, 0)) / 100.0, 'FM999999990.00'),
                      coalesce(r.event_name, '?'), coalesce(r.payout_risk_tier, 'unknown'),
                      case when r.payout_reason_codes is not null and cardinality(r.payout_reason_codes) > 0
                           then '; ' || array_to_string(r.payout_reason_codes, ', ') else '' end,
                      case when r.auto_release_at is not null
                           then format('; auto-release scheduled %s', to_char(r.auto_release_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')) else '' end),
               'p2', r.auto_release_at, 'payout_review');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('payout_review', v_keys));
end;
$ops$;
revoke all on function ops.detect_payout_review() from public, anon, authenticated, service_role;

-- reports — user reports awaiting triage. `pending` opens the case; a report
-- moved to `reviewing` by the report_resolve action (115) keeps its case alive
-- (the action only closes the case on actioned / dismissed).
create or replace function ops.detect_reports()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select rp.id, rp.target_type, rp.target_id, rp.reason, rp.status, rp.created_at
      from public.reports rp
     where rp.status in ('pending', 'reviewing')
     order by rp.created_at
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('report_review', 'report', r.id, null,
               'User report awaiting review',
               format('Report on %s %s (%s) filed %s; status %s.', r.target_type, r.target_id, r.reason,
                      to_char(r.created_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), r.status),
               'p3', null, 'reports');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('report_review', v_keys));
end;
$ops$;
revoke all on function ops.detect_reports() from public, anon, authenticated, service_role;

-- webhooks — Stripe events not processed within the window, or marked failed
-- without a terminal processed_at. Also drives the `webhook_backlog` alert.
create or replace function ops.detect_webhooks()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_mins    integer := ops.setting_int('webhook_stuck_minutes', 15);
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select e.event_id, e.event_type, e.received_at, e.failed_at, e.last_error, e.attempt_count
      from public.stripe_webhook_events e
     where e.processed_at is null
       and (e.received_at < now() - make_interval(mins => v_mins) or e.failed_at is not null)
     order by e.received_at
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('webhook_stuck', 'webhook_event', null, r.event_id,
               'Stripe webhook not processed',
               format('%s received %s%s, %s attempt(s)%s. Replay from the Stripe Dashboard (no in-console replay).',
                      r.event_type, to_char(r.received_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                      case when r.failed_at is not null then format(', failed %s', to_char(r.failed_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')) else '' end,
                      coalesce(r.attempt_count, 0),
                      case when r.last_error is not null then format(': %s', left(r.last_error, 500)) else '' end),
               'p2', null, 'webhooks');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  if v_scanned > 0 then
    perform ops.alert_fire('webhook_backlog', 'webhook_backlog',
              jsonb_build_object('count', v_scanned, 'threshold_minutes', v_mins));
  else
    perform ops.alert_recover('webhook_backlog');
  end if;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('webhook_stuck', v_keys));
end;
$ops$;
revoke all on function ops.detect_webhooks() from public, anon, authenticated, service_role;

-- jobs — job_failure for (a) each active pg_cron job whose two most recent
-- runs both failed, or that has run before but has no succeeded run within
-- 3× its interval (`*/N * * * *` → N min; otherwise 25 h) — only when
-- cron.job_run_details exists; (b) ops.job_state rows with ≥ 3 consecutive
-- failures. Also drives the `job_failure:<ref>` alerts.
create or replace function ops.detect_jobs()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_keys    text[]  := array[]::text[];
  v_refs    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
  v_cron_available boolean := to_regclass('cron.job_run_details') is not null and to_regclass('cron.job') is not null;
begin
  if v_cron_available then
    for r in execute $q$
      with recent as (
        select d.jobid, d.status, d.start_time, d.end_time, d.return_message,
               row_number() over (partition by d.jobid order by d.start_time desc) as rn
          from cron.job_run_details d
         where d.start_time > now() - interval '7 days'
      ),
      per_job as (
        select j.jobid, j.jobname, j.schedule,
               ops.cron_interval_minutes(j.schedule) as interval_min,
               (select count(*) from recent x where x.jobid = j.jobid) as runs_7d,
               (select bool_and(x.status = 'failed') from recent x where x.jobid = j.jobid and x.rn <= 2) as last2_failed,
               (select count(*) from recent x where x.jobid = j.jobid and x.rn <= 5 and x.status = 'failed') as failed_of_last5,
               (select max(x.start_time) from recent x where x.jobid = j.jobid and x.status = 'succeeded') as last_success,
               (select x.return_message from recent x where x.jobid = j.jobid and x.status = 'failed' order by x.start_time desc limit 1) as last_error
          from cron.job j
         where j.active
      )
      select * from per_job
       where runs_7d > 0
         and (coalesce(last2_failed, false)
              or last_success is null
              or last_success < now() - make_interval(mins => 3 * interval_min))
    $q$
    loop
      v_scanned := v_scanned + 1;
      v_res := ops.detect_case('job_failure', 'job', null, r.jobname,
                 format('Cron job %s failing', r.jobname),
                 format('pg_cron job "%s" (%s): %s of the last 5 runs failed; last success %s%s.',
                        r.jobname, r.schedule, r.failed_of_last5,
                        coalesce(to_char(r.last_success at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), 'never in the last 7 days'),
                        case when r.last_error is not null then format('; last error: %s', left(r.last_error, 500)) else '' end),
                 'p2', null, 'jobs');
      v_keys := v_keys || (v_res ->> 'dedupe_key');
      v_refs := v_refs || r.jobname;
      if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
      perform ops.alert_fire('job_failure:' || r.jobname, 'job_failure',
                jsonb_build_object('source', 'pg_cron', 'jobname', r.jobname, 'failed_of_last5', r.failed_of_last5,
                                   'last_success', r.last_success));
    end loop;
  end if;

  for r in
    select s.job_name, s.consecutive_failures, s.last_error, s.last_success_at, s.backoff_until
      from ops.job_state s
     where s.consecutive_failures >= 3
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('job_failure', 'job', null, 'ops:' || r.job_name,
               format('Console job %s failing', r.job_name),
               format('ops job "%s" has failed %s times in a row (backing off until %s); last success %s%s.',
                      r.job_name, r.consecutive_failures,
                      coalesce(to_char(r.backoff_until at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), 'n/a'),
                      coalesce(to_char(r.last_success_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), 'never'),
                      case when r.last_error is not null then format('; last error: %s', left(r.last_error, 500)) else '' end),
               'p2', null, 'jobs');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    v_refs := v_refs || ('ops:' || r.job_name);
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
    perform ops.alert_fire('job_failure:ops:' || r.job_name, 'job_failure',
              jsonb_build_object('source', 'ops', 'job_name', r.job_name, 'consecutive_failures', r.consecutive_failures));
  end loop;

  perform ops.alert_recover_stale('job_failure:', v_refs);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('job_failure', v_keys),
                            'cron_run_details_available', v_cron_available);
end;
$ops$;
revoke all on function ops.detect_jobs() from public, anon, authenticated, service_role;

-- notifications — notify.delivery rows failed / dead in the last 7 days, one
-- case per delivery.
create or replace function ops.detect_notifications()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select d.delivery_id, d.notification_id, d.channel, d.state, d.attempt, d.next_attempt_at, d.last_error, d.created_at,
           n.type_key
      from notify.delivery d
      left join notify.notification n on n.notification_id = d.notification_id
     where d.state in ('failed', 'dead')
       and d.created_at > now() - interval '7 days'
     order by d.created_at
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('notification_failure', 'notification', r.delivery_id, null,
               format('Notification delivery %s', r.state),
               format('%s delivery of %s (created %s) is %s after %s attempt(s)%s%s.',
                      r.channel, coalesce(r.type_key, 'unknown type'),
                      to_char(r.created_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), r.state, coalesce(r.attempt, 0),
                      case when r.state = 'failed' and r.next_attempt_at is not null
                           then format('; next attempt %s', to_char(r.next_attempt_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')) else '' end,
                      case when r.last_error is not null then format(': %s', left(r.last_error, 500)) else '' end),
               'p3', null, 'notifications');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('notification_failure', v_keys));
end;
$ops$;
revoke all on function ops.detect_notifications() from public, anon, authenticated, service_role;

-- reconciliation — reconciliation_mismatch (p1) per payment for: a refunded
-- payment whose transfer has a provider transfer id and is not reversed
-- (money went both ways); total <> amount + buyer_fee. Released-locally-without-
-- provider-id is release_stuck's; buyer-win-with-succeeded-payment is
-- refund_pending's — neither is duplicated here.
create or replace function ops.detect_reconciliation()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_keys    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
begin
  for r in
    select p.id, p.stripe_payment_intent_id, p.status, p.amount, p.buyer_fee, p.total,
           concat_ws('; ',
             case when p.status = 'refunded' and exists (
                    select 1 from public.transfers t
                     where t.payment_id = p.id and t.stripe_transfer_id is not null and t.status <> 'reversed')
                  then 'payment refunded but a connected-account transfer exists (stripe_transfer_id set) and the transfer is not reversed' end,
             case when p.total <> p.amount + p.buyer_fee
                  then format('total %s <> amount %s + buyer_fee %s', p.total, p.amount, p.buyer_fee) end) as why
      from public.payments p
     where (p.status = 'refunded' and exists (
              select 1 from public.transfers t
               where t.payment_id = p.id and t.stripe_transfer_id is not null and t.status <> 'reversed'))
        or p.total <> p.amount + p.buyer_fee
     order by p.created_at
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('reconciliation_mismatch', 'payment', r.id, null,
               'Reconciliation mismatch',
               format('Payment %s (status %s): %s.', r.stripe_payment_intent_id, r.status, r.why),
               'p1', null, 'reconciliation');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('reconciliation_mismatch', v_keys));
end;
$ops$;
revoke all on function ops.detect_reconciliation() from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- PART 3 — metrics (design §5) and the daily summary
-- ----------------------------------------------------------------------------
-- Every money metric is stored as {definition, basis, currency, window_30d:
-- {count, cents}, all_time: {count, cents}}; UTC date basis; USD only; no
-- "revenue" vocabulary. Queue counts are point-in-time.
create or replace function ops.refresh_metrics()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_now   timestamptz := now();
  v_from  timestamptz := (date_trunc('day', now() at time zone 'utc') - interval '30 days') at time zone 'utc';
  v_rows  jsonb := '{}'::jsonb;
  v_n     integer := 0;
  v_key   text;
  v_val   jsonb;
begin
  -- Gross captured volume: Σ payments.total, status ∈ (succeeded, refunded), by paid_at.
  select jsonb_build_object(
           'definition', 'Sum of payments.total where status in (succeeded, refunded); refunds are NOT netted here',
           'basis', 'paid_at (UTC date)', 'currency', 'USD',
           'window_30d', jsonb_build_object('count', count(*) filter (where p.paid_at >= v_from),
                                            'cents', coalesce(sum(p.total) filter (where p.paid_at >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.total), 0)))
    into v_val
    from public.payments p where p.status in ('succeeded', 'refunded');
  v_rows := v_rows || jsonb_build_object('money.gross_captured', v_val);

  -- Refunded volume: Σ payments.total, status = refunded, by refunded_at.
  select jsonb_build_object(
           'definition', 'Sum of payments.total where status = refunded',
           'basis', 'refunded_at (UTC date)', 'currency', 'USD',
           'window_30d', jsonb_build_object('count', count(*) filter (where coalesce(p.refunded_at, p.paid_at) >= v_from),
                                            'cents', coalesce(sum(p.total) filter (where coalesce(p.refunded_at, p.paid_at) >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.total), 0)))
    into v_val
    from public.payments p where p.status = 'refunded';
  v_rows := v_rows || jsonb_build_object('money.refunded', v_val);

  -- Platform fees (gross, pre-refund): Σ buyer_fee + seller_fee on succeeded, by paid_at.
  select jsonb_build_object(
           'definition', 'Sum of buyer_fee + seller_fee on succeeded payments (gross, before refunds)',
           'basis', 'paid_at (UTC date)', 'currency', 'USD',
           'window_30d', jsonb_build_object('count', count(*) filter (where p.paid_at >= v_from),
                                            'cents', coalesce(sum(p.buyer_fee + p.seller_fee) filter (where p.paid_at >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.buyer_fee + p.seller_fee), 0)))
    into v_val
    from public.payments p where p.status = 'succeeded';
  v_rows := v_rows || jsonb_build_object('money.platform_fees', v_val);

  -- Seller funds released to connected account: transfers.stripe_transfer_id set, Σ amount - seller_fee, by payout_released_at.
  select jsonb_build_object(
           'definition', 'Transfers with a Stripe connected-account transfer id; sum of payments.amount - seller_fee. Not a bank payout.',
           'basis', 'payout_released_at (UTC date)', 'currency', 'USD',
           'window_30d', jsonb_build_object('count', count(*) filter (where t.payout_released_at >= v_from),
                                            'cents', coalesce(sum(p.amount - coalesce(p.seller_fee, 0)) filter (where t.payout_released_at >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0)))
    into v_val
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.stripe_transfer_id is not null;
  v_rows := v_rows || jsonb_build_object('money.released_to_connected', v_val);

  -- Seller funds pending: seller_sent / buyer_confirmed / auto_released without stripe_transfer_id (now).
  select jsonb_build_object(
           'definition', 'Transfers in seller_sent, buyer_confirmed or auto_released with no connected-account transfer yet; sum of payments.amount - seller_fee',
           'basis', 'now', 'currency', 'USD',
           'now', jsonb_build_object('count', count(*), 'cents', coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0)),
           'by_status', coalesce((select jsonb_object_agg(s.status, s.n) from (
                          select t2.status, count(*) as n from public.transfers t2
                           where t2.status in ('seller_sent', 'buyer_confirmed', 'auto_released') and t2.stripe_transfer_id is null
                           group by t2.status) s), '{}'::jsonb))
    into v_val
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status in ('seller_sent', 'buyer_confirmed', 'auto_released') and t.stripe_transfer_id is null;
  v_rows := v_rows || jsonb_build_object('money.seller_funds_pending', v_val);

  v_rows := v_rows || jsonb_build_object('money.bank_payouts', jsonb_build_object(
              'definition', 'Bank payouts from connected accounts are not tracked (payout.paid webhook is only logged)',
              'tracked', false));

  -- Queue counts (point in time).
  v_rows := v_rows || jsonb_build_object('queue.cases_open', (
    select jsonb_build_object('total', count(*),
             'by_priority', coalesce(jsonb_object_agg(pr, n) filter (where pr is not null), '{}'::jsonb))
      from (select c.priority as pr, count(*) as n from ops."case" c
             where c.status not in ('resolved', 'dismissed') group by c.priority) q));
  v_rows := v_rows || jsonb_build_object('queue.cases_open_by_type', coalesce((
    select jsonb_object_agg(c.case_type, c.n) from (
      select case_type, count(*) as n from ops."case" where status not in ('resolved', 'dismissed') group by case_type) c), '{}'::jsonb));
  v_rows := v_rows || jsonb_build_object('queue.refunds_pending', (
    select count(*) from ops."case" where case_type = 'refund_pending' and status not in ('resolved', 'dismissed')));
  v_rows := v_rows || jsonb_build_object('queue.webhook_backlog', (
    select count(*) from public.stripe_webhook_events e
     where e.processed_at is null
       and (e.received_at < now() - make_interval(mins => ops.setting_int('webhook_stuck_minutes', 15)) or e.failed_at is not null)));
  v_rows := v_rows || jsonb_build_object('queue.notify_failed_7d', (
    select jsonb_build_object('failed', count(*) filter (where d.state = 'failed'), 'dead', count(*) filter (where d.state = 'dead'))
      from notify.delivery d where d.state in ('failed', 'dead') and d.created_at > now() - interval '7 days'));
  v_rows := v_rows || jsonb_build_object('queue.disputes_open', (
    select jsonb_build_object(
             'transfers', (select count(*) from public.transfers t where t.disputed_at is not null and t.dispute_resolved_at is null),
             'stripe',    (select count(*) from public.disputes d where d.status not in ('won', 'lost', 'warning_closed', 'charge_refunded')))));
  v_rows := v_rows || jsonb_build_object('queue.transfers_pending', (
    select jsonb_build_object('pending', count(*) filter (where t.status = 'pending'),
                              'seller_sent', count(*) filter (where t.status = 'seller_sent'),
                              'manual_review', count(*) filter (where t.payout_review_status = 'manual_review' and t.payout_released_at is null))
      from public.transfers t));
  v_rows := v_rows || jsonb_build_object('queue.alerts_firing', (select count(*) from ops.alert where state = 'firing'));

  for v_key, v_val in select * from jsonb_each(v_rows) loop
    insert into ops.metric_snapshot (key, value, computed_at) values (v_key, v_val, v_now)
    on conflict (key) do update set value = excluded.value, computed_at = excluded.computed_at;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('scanned', v_n, 'opened', 0, 'resolved', 0, 'keys', v_n, 'computed_at', v_now);
end;
$ops$;
revoke all on function ops.refresh_metrics() from public, anon, authenticated, service_role;

-- Daily summary for p_date (UTC). The window is the 24 h ending at the end of
-- p_date, capped at now() when p_date is today (the 13:00Z cron therefore
-- summarises 13:00Z→13:00Z); half-open on the left, closed on the right
-- ((from, to]) so rows stamped at the generation instant are counted. Overwrites any existing row; portal_only — no
-- delivery channel is configured (design §2.11).
create or replace function ops.build_daily_summary(p_date date default (now() at time zone 'utc')::date)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_to    timestamptz := least(((p_date + 1)::timestamp at time zone 'utc'), now());
  v_from  timestamptz;
  v_body  jsonb;
  v_detectors text[] := array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes','payout_review',
                              'reports','webhooks','jobs','notifications','reconciliation'];
begin
  if p_date is null then
    raise exception 'invalid_input: p_date is required';
  end if;
  v_from := v_to - interval '24 hours';

  v_body := jsonb_build_object(
    'generated_at', now(),
    'summary_date', p_date,
    'period', jsonb_build_object('from', v_from, 'to', v_to),
    'cases', jsonb_build_object(
      'opened_24h',   (select count(*) from ops."case" c where c.detected_at >= v_from and c.detected_at <= v_to),
      'resolved_24h', (select count(*) from ops."case" c where c.resolved_at >= v_from and c.resolved_at <= v_to),
      'open_total',   (select count(*) from ops."case" c where c.status not in ('resolved', 'dismissed')),
      'open_by_type', coalesce((select jsonb_object_agg(x.case_type, x.n) from (
                         select case_type, count(*) as n from ops."case" where status not in ('resolved', 'dismissed') group by case_type) x), '{}'::jsonb),
      'open_by_priority', coalesce((select jsonb_object_agg(x.priority, x.n) from (
                         select priority, count(*) as n from ops."case" where status not in ('resolved', 'dismissed') group by priority) x), '{}'::jsonb),
      'oldest_open',  (select min(c.detected_at) from ops."case" c where c.status not in ('resolved', 'dismissed')),
      'unassigned',   (select count(*) from ops."case" c where c.status not in ('resolved', 'dismissed') and c.assignee is null),
      'overdue_due_at', (select count(*) from ops."case" c where c.status not in ('resolved', 'dismissed') and c.due_at < now())),
    'money', jsonb_build_object(
      'snapshot', coalesce((select jsonb_object_agg(m.key, m.value || jsonb_build_object('computed_at', m.computed_at))
                              from ops.metric_snapshot m where m.key like 'money.%'), '{}'::jsonb),
      'live_24h', jsonb_build_object(
        'captured_cents', (select coalesce(sum(p.total), 0) from public.payments p
                            where p.status in ('succeeded', 'refunded') and p.paid_at >= v_from and p.paid_at <= v_to),
        'captured_count', (select count(*) from public.payments p
                            where p.status in ('succeeded', 'refunded') and p.paid_at >= v_from and p.paid_at <= v_to),
        'refunded_cents', (select coalesce(sum(p.total), 0) from public.payments p
                            where p.status = 'refunded' and p.refunded_at >= v_from and p.refunded_at <= v_to),
        'released_to_connected_cents', (select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0)
                                          from public.transfers t join public.payments p on p.id = t.payment_id
                                         where t.stripe_transfer_id is not null and t.payout_released_at >= v_from and t.payout_released_at <= v_to),
        'refunds_pending_count', (select count(*) from ops."case" c
                                   where c.case_type = 'refund_pending' and c.status not in ('resolved', 'dismissed'))),
      'currency', 'USD', 'basis', 'UTC'),
    'deadlines', jsonb_build_object(
      'transfers_due_24h', (select count(*) from public.transfers t
                             where t.status = 'pending' and t.expires_at >= now() and t.expires_at < now() + interval '24 hours'),
      'transfers_overdue', (select count(*) from public.transfers t where t.status = 'pending' and t.expires_at < now()),
      'evidence_due_72h',  (select count(*) from public.disputes d
                             where d.status not in ('won', 'lost', 'warning_closed', 'charge_refunded')
                               and d.evidence_due_by is not null and d.evidence_due_by < now() + interval '72 hours')),
    'jobs', jsonb_build_object(
      'failing', coalesce((select jsonb_agg(jsonb_build_object('job_name', s.job_name, 'consecutive_failures', s.consecutive_failures,
                                                               'last_error', left(s.last_error, 300), 'backoff_until', s.backoff_until)
                                            order by s.job_name)
                             from ops.job_state s where s.consecutive_failures > 0), '[]'::jsonb),
      'runs_24h', (select jsonb_build_object('succeeded', count(*) filter (where r.status = 'succeeded'),
                                             'failed', count(*) filter (where r.status = 'failed'),
                                             'skipped', count(*) filter (where r.status = 'skipped'))
                     from ops.job_run r where r.started_at >= v_from and r.started_at <= v_to),
      'last_detector_success_at', (select max(s.last_success_at) from ops.job_state s where s.job_name = any(v_detectors))),
    'alerts_firing', coalesce((select jsonb_agg(jsonb_build_object('alert_key', a.alert_key, 'kind', a.kind,
                                                                   'first_fired_at', a.first_fired_at, 'fire_count', a.fire_count)
                                                order by a.first_fired_at)
                                 from ops.alert a where a.state = 'firing'), '[]'::jsonb),
    'alerts_firing_count', (select count(*) from ops.alert a where a.state = 'firing'));

  insert into ops.daily_summary (summary_date, generated_at, body, delivery_state)
  values (p_date, now(), v_body, 'portal_only')
  on conflict (summary_date) do update
    set generated_at = excluded.generated_at, body = excluded.body, delivery_state = 'portal_only';

  return jsonb_build_object('scanned', 1, 'opened', 0, 'resolved', 0, 'summary_date', p_date,
                            'period', v_body -> 'period', 'delivery_state', 'portal_only');
end;
$ops$;
revoke all on function ops.build_daily_summary(date) from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- PART 4 — the durable runner
-- ----------------------------------------------------------------------------
-- ops.run_job(name, trigger) — the ONLY callable automation surface.
--   authz     service_role (pg_cron / edge) OR platform_admin + aal2 (manual
--             retry via the 115 job_retry action).
--   names     fixed list; anything else → invalid_input.
--   skips     recorded as job_run.status = 'skipped' with detail.reason ∈
--             detectors_disabled | job_disabled | backoff | overlap. Manual
--             triggers ignore detectors_disabled / job_disabled / backoff,
--             never overlap.
--   failure   the body runs in a subtransaction; an error is RECORDED (job_run
--             failed + error, job_state.consecutive_failures + 1, last_error,
--             backoff_until = now() + least(2^n, 60) min) and never raised.
--   success   job_run counters from the body's {scanned, opened, resolved};
--             job_state.last_success_at, failures reset, backoff cleared.
create or replace function ops.run_job(p_job_name text, p_trigger text default 'cron')
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  c_jobs   constant text[] := array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes',
                                    'payout_review','reports','webhooks','jobs','notifications','reconciliation',
                                    'refresh_metrics','daily_summary'];
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

-- Cron entry: every detector in a fixed order (each isolated by run_job's
-- exception handling — one failing detector never stops the others), then
-- the metric refresh. daily_summary has its own schedule.
create or replace function ops.run_all_detectors()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  c_order constant text[] := array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes',
                                   'payout_review','reports','webhooks','jobs','notifications','reconciliation',
                                   'refresh_metrics'];
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

-- ----------------------------------------------------------------------------
-- PART 5 — job_state seed + cron registration
-- ----------------------------------------------------------------------------
insert into ops.job_state (job_name, enabled)
select unnest(array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes','payout_review',
                    'reports','webhooks','jobs','notifications','reconciliation','refresh_metrics','daily_summary']), true
on conflict (job_name) do nothing;

-- cron (owning-package registration, kebab names — 014/032/075/092/099 idiom;
-- remove any same-named job first so a replay never leaves a duplicate)
select cron.unschedule(jobname) from cron.job where jobname = 'ops-detect-tick';
select cron.schedule('ops-detect-tick', '*/5 * * * *', $$select ops.run_all_detectors();$$);

select cron.unschedule(jobname) from cron.job where jobname = 'ops-daily-summary';
select cron.schedule('ops-daily-summary', '0 13 * * *', $$select ops.run_job('daily_summary', 'cron');$$);

commit;
