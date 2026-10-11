-- ============================================================================
-- 20261011000000_detect_refunds_state_on.sql — registry 153, pgTAP 220.
-- F-DETECT-REFUNDS-UNOBSERVABLE-1 (FINDINGS_20260924_DISPUTE_GRANT_AND_OPS_CASE.md).
--
-- WHY. ops.detect_refunds() returned {scanned, opened, resolved}; `scanned` mixes
-- the ungated loops with the two 150 refund-state branches. A tick with
-- refund_state_detection_enabled off, a tick over an empty refund-state table,
-- and a tick over rows neither branch selects all produced the same output.
-- Production: items_scanned = 2 across 288 runs before the flip, 255 after, and
-- still 2 with two real succeeded rows present (2026-10-11).
--
-- WHAT. 150's body, byte for byte, plus three result fields:
--   state_on       whether the branches ran;
--   state_scanned  rows the two branches iterated (0 when off);
--   state_rows     refund-state rows visible to the branches (NULL when off).
-- `scanned`, `opened` and `resolved` keep their meaning. ops.run_job writes the
-- result to ops.job_run.detail, so every tick now records which case it was.
-- No new object, no signature change, grants unchanged (re-revoked below as 150
-- does). Timestamp-named on purpose: it redefines a function owned by the
-- timestamped 20260925000000, and a numbered file would replay first and be
-- overwritten (the 134 trap).
--
-- ROLLBACK: supabase/rollbacks/20261011000000_detect_refunds_state_on_rollback.sql
--   restores 150's body exactly.
-- VERIFY:   select ops.detect_refunds() ?& array['state_on','state_scanned','state_rows'];
-- FAILURE:  none expected (CREATE OR REPLACE of a SECURITY DEFINER function; no data touched).
-- APPLY:    owner-gated, like any production migration. Not applied by this branch.
-- ============================================================================

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
  -- 150: Stripe-reported refund state, off until the owner flips it.
  v_state_on      boolean := ops.setting_bool('refund_state_detection_enabled', false);
  v_pending_hours integer := ops.setting_int('refund_state_pending_hours', 120);
  -- 153: what the 150 branches did, so a run log can tell skipped from ran-over-nothing from ran-over-rows.
  v_state_scanned integer := 0;
  v_state_rows    integer;            -- NULL when the branches are skipped: the table was not read
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

  -- Completion: a refund that succeeded at the provider is confirmed locally
  -- once the charge.refunded webhook has marked the payment refunded.
  for r in
    select a.id as action_id
      from ops.action a
      join public.payments p on p.id = a.subject_id
     where a.action_type = 'refund_execute' and a.state = 'succeeded_at_provider' and p.status = 'refunded'
  loop
    update ops.action set state = 'succeeded', completed_at = now(), claimed_until = null, version = version + 1
     where id = r.action_id and state = 'succeeded_at_provider';
    perform ops.audit_write('action.outcome.refund_execute', 'payment', null, null, null,
                            jsonb_build_object('state', 'succeeded_at_provider'),
                            jsonb_build_object('state', 'succeeded', 'confirmed_by', 'charge.refunded webhook'),
                            'succeeded', null, r.action_id);
  end loop;

  for r in
    select a.id as action_id, a.subject_id as payment_id, a.state, a.error, a.provider_ref, a.updated_at, a.completed_at
      from ops.action a
     where a.action_type = 'refund_execute'
       and a.subject_id is not null
       and (a.state in ('failed', 'unknown')
            or (a.state = 'succeeded_at_provider' and a.updated_at < now() - interval '60 minutes')
            -- a crash between the claim and the outcome callback leaves the
            -- action at `processing` with an expired (or no) lease
            or (a.state = 'processing'
                and ((a.claimed_until is not null and a.claimed_until < now() - interval '30 minutes')
                     or (a.claimed_until is null and a.updated_at < now() - interval '30 minutes'))))
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

  -- 150: Stripe's own refund state (public.payment_refund_state, written only by
  -- record_refund_state). Keyed per refund (subject_ref = re_…, subject_id NULL, so the
  -- dedupe key is case_type:re_…) and merged into the same sweep sets, so these cases and
  -- the payment-keyed cases above never resolve each other. A case a human closed
  -- (resolved/dismissed with resolved_by set) is not re-opened for the same refund.
  if v_state_on then
    select count(*) into v_state_rows from public.payment_refund_state;
    for r in
      select s.stripe_refund_id, s.payment_id, s.status, s.failure_reason, s.amount_cents, s.source,
             p.stripe_payment_intent_id
        from public.payment_refund_state s
        join public.payments p on p.id = s.payment_id
       where s.status in ('failed', 'canceled')
         and p.refund_succeeded_cents < p.total
         and not exists (select 1 from ops."case" c
                          where c.dedupe_key = 'refund_failed:' || s.stripe_refund_id
                            and c.status in ('resolved', 'dismissed') and c.resolved_by is not null)
    loop
      v_scanned := v_scanned + 1;
      v_state_scanned := v_state_scanned + 1;
      v_res := ops.detect_case('refund_failed', 'payment', null, r.stripe_refund_id,
                 'Refund failed at Stripe',
                 format('Refund %s ($%s, source %s) on payment %s (%s) is %s at Stripe%s. This refund did not reach the buyer. '
                        || 'Stripe asks the platform to arrange another way to refund the customer (docs.stripe.com/refunds#failed-refunds); '
                        || 'record what was done on this case, then close it.',
                        r.stripe_refund_id, to_char(r.amount_cents / 100.0, 'FM999999990.00'), r.source,
                        r.payment_id, r.stripe_payment_intent_id, r.status,
                        case when r.failure_reason is not null then format(' (%s)', r.failure_reason) else '' end),
                 'p1', null, 'refunds');
      v_failed_keys := v_failed_keys || (v_res ->> 'dedupe_key');
      if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
    end loop;

    for r in
      select s.stripe_refund_id, s.payment_id, s.status, s.amount_cents, s.first_observed_at,
             p.stripe_payment_intent_id
        from public.payment_refund_state s
        join public.payments p on p.id = s.payment_id
       where s.status in ('pending', 'requires_action')
         and s.first_observed_at < now() - make_interval(hours => v_pending_hours)
         and not exists (select 1 from ops."case" c
                          where c.dedupe_key = 'refund_pending:' || s.stripe_refund_id
                            and c.status in ('resolved', 'dismissed') and c.resolved_by is not null)
    loop
      v_scanned := v_scanned + 1;
      v_state_scanned := v_state_scanned + 1;
      v_res := ops.detect_case('refund_pending', 'payment', null, r.stripe_refund_id,
                 'Refund still pending at Stripe',
                 format('Refund %s ($%s) on payment %s (%s) has been %s at Stripe since %s. Check it in the Stripe Dashboard.',
                        r.stripe_refund_id, to_char(r.amount_cents / 100.0, 'FM999999990.00'),
                        r.payment_id, r.stripe_payment_intent_id, r.status,
                        to_char(r.first_observed_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')),
                 'p1', null, 'refunds');
      v_pending_keys := v_pending_keys || (v_res ->> 'dedupe_key');
      if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
    end loop;
  end if;

  v_resolved := ops.detect_sweep('refund_pending', v_pending_keys) + ops.detect_sweep('refund_failed', v_failed_keys);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened, 'resolved', v_resolved,
                            'state_on', v_state_on, 'state_scanned', v_state_scanned, 'state_rows', v_state_rows);
end;
$ops$;
revoke all on function ops.detect_refunds() from public, anon, authenticated, service_role;
