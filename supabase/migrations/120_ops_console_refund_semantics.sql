-- ============================================================================
-- 120_ops_console_refund_semantics.sql — daily summary refund semantics
-- (PR #55 focused review, finding 1).
--
-- WHAT THIS MIGRATION IS. Body-only re-creates inside `ops` plus a one-time
-- rewrite of DERIVED rows in ops.daily_summary. 118 corrected the Money
-- dashboard and the metric snapshot to say that a refunded AMOUNT is not
-- knowable from public.payments (status-only model; charge.refunded also
-- fires for partial refunds), but ops.build_daily_summary still summed
-- payments.total over refunded rows into `refunded_cents`, and the summary
-- view rendered that as "Refunded". A $10 partial refund issued from the
-- Stripe Dashboard on a $100 payment therefore reported $100 refunded.
--
--   * ops.build_daily_summary: `money.live_24h.refunded_cents` is now JSON null;
--     `refunded_count` (reliable), `refunded_upper_bound_cents` (labelled) and
--     `refunded_certainty = 'uncertain'` are added — the same vocabulary as
--     ops.money_overview and the `money.refunded` snapshot after 118.
--   * ops.latest_summary(): legacy bodies (numeric refunded_cents, no
--     certainty key) are normalised on read to the same shape with
--     `legacy_normalized = true`, so no historical summary can render an
--     amount as fact.
--   * Stored ops.daily_summary rows are rewritten the same way (derived data,
--     regenerable; the underlying payments are untouched). No financial record
--     is modified and no refunded-amount fact is invented.
--
-- ZERO changes to public.* definitions. No storage policy.
-- Rollback: supabase/rollbacks/120_ops_console_refund_semantics_rollback.sql
-- Verification: select (body->'money'->'live_24h'->>'refunded_certainty') from ops.daily_summary;  -- 'uncertain' on every row
-- ============================================================================
begin;

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
        -- Refunds: the local model stores refund STATUS only and charge.refunded
        -- also fires for PARTIAL refunds, so the amount is unknowable here.
        -- Report the count (reliable) and an explicit upper bound; never a total.
        'refunded_cents', null,
        'refunded_count', (select count(*) from public.payments p
                            where p.status = 'refunded' and p.refunded_at >= v_from and p.refunded_at <= v_to),
        'refunded_upper_bound_cents', (select coalesce(sum(p.total), 0) from public.payments p
                            where p.status = 'refunded' and p.refunded_at >= v_from and p.refunded_at <= v_to),
        'refunded_certainty', 'uncertain',
        'refunded_note', 'amount not available locally: payments records refund status only and Stripe sends charge.refunded for partial refunds too; upper bound = Σ payments.total over refunded rows',
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

-- Normalise one summary body: legacy numeric refunded_cents → uncertain shape.
create or replace function ops.normalize_summary_body(p_body jsonb)
returns jsonb language sql immutable
as $ops$
  select case
    when p_body #> '{money,live_24h}' is null then p_body
    when (p_body #> '{money,live_24h}') ? 'refunded_certainty' then p_body
    else jsonb_set(p_body, '{money,live_24h}',
           (p_body #> '{money,live_24h}')
           || jsonb_build_object(
                'refunded_cents', null,
                'refunded_upper_bound_cents', (p_body #> '{money,live_24h}') -> 'refunded_cents',
                'refunded_count', null,
                'refunded_certainty', 'uncertain',
                'refunded_note', 'legacy summary: the stored figure was Σ payments.total over refunded rows and is only an upper bound; the count was not recorded',
                'legacy_normalized', true))
  end;
$ops$;
revoke all on function ops.normalize_summary_body(jsonb) from public, anon, authenticated;

create or replace function ops.latest_summary()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  return (select to_jsonb(s) || jsonb_build_object('body', ops.normalize_summary_body(s.body))
            from ops.daily_summary s order by s.summary_date desc limit 1);
end;
$ops$;
revoke all on function ops.latest_summary() from public, anon, authenticated;
grant execute on function ops.latest_summary() to authenticated;

-- One-time rewrite of already-stored derived summaries (idempotent: the
-- normaliser is a no-op on bodies that already carry refunded_certainty).
update ops.daily_summary
   set body = ops.normalize_summary_body(body)
 where (body #> '{money,live_24h}') is not null
   and not ((body #> '{money,live_24h}') ? 'refunded_certainty');

commit;
