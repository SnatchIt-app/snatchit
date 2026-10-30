-- ============================================================================
-- ROLLBACK for 20260925000000_refund_lifecycle_state.sql (registry 150).
-- Lives outside supabase/migrations/ (a rollback there is parsed as a duplicate
-- version). Run only under the owner's rollback authorisation.
--
-- Restores ops.detect_refunds to 118's APPLIED body (byte for byte, extracted from
-- 118_ops_console_corrections.sql) and removes every object 150 created.
-- DATA: payment_refund_state and payment_refund_state_log are dropped. If they hold
-- rows, export them first (they are the only record of Stripe-reported refund
-- states). payment_refunds rows the writer counted stay: they are the one-way
-- "refund requested" record 20260906120000 defines and remain correct.
-- ops cases opened by the 150 branches stay; an operator closes them.
-- ============================================================================
BEGIN;

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

  v_resolved := ops.detect_sweep('refund_pending', v_pending_keys) + ops.detect_sweep('refund_failed', v_failed_keys);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened, 'resolved', v_resolved);
end;
$ops$;
revoke all on function ops.detect_refunds() from public, anon, authenticated, service_role;

DELETE FROM ops.setting WHERE key IN ('refund_state_detection_enabled', 'refund_state_pending_hours');

DROP FUNCTION IF EXISTS public.record_refund_state(text, text, text, integer, text, text, text);

DROP TRIGGER IF EXISTS trg_guard_payment_refund_state_columns ON public.payments;
DROP FUNCTION IF EXISTS public.guard_payment_refund_state_columns();
ALTER TABLE public.payments
  DROP COLUMN IF EXISTS refund_requested_cents,
  DROP COLUMN IF EXISTS refund_succeeded_cents,
  DROP COLUMN IF EXISTS refund_failed_cents;

DROP TABLE IF EXISTS public.payment_refund_state_log;
DROP FUNCTION IF EXISTS public.payment_refund_state_log_append_only();
DROP TABLE IF EXISTS public.payment_refund_state;

COMMIT;
