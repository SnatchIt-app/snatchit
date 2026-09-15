-- ============================================================================
-- 126_ops_console_refund_exactness_rollback.sql — restores the APPLIED bodies
-- 126 replaced and removes the one object it added:
--   * ops.build_daily_summary  → 120_ops_console_refund_semantics.sql body, verbatim
--   * ops.money_overview       → 118_ops_console_corrections.sql body, verbatim
--   * ops.refresh_metrics      → 118_ops_console_corrections.sql body, verbatim
--   * ops.refund_facts         → dropped (after the three callers stop using it)
-- Grants re-stated exactly as the applied migrations set them. Derived rows in
-- ops.daily_summary / ops.metric_snapshot written by 126 are left in place:
-- ops.latest_summary passes any body carrying refunded_certainty through, and
-- the next daily_summary / refresh_metrics run rewrites them in 120/118's shape.
-- No public.* object is touched. Production is forward-only by policy; this is
-- an emergency measure requiring its own authorization.
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

create or replace function ops.money_overview(p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  v_to    date := coalesce(p_to,   (now() at time zone 'UTC')::date);
  v_from  date := coalesce(p_from, v_to - 30);
  lo      timestamptz;
  hi      timestamptz;
  m       jsonb;
  v_val   bigint; v_cnt bigint;
begin
  perform ops.assert_reader();
  if v_from > v_to then
    raise exception 'invalid_input: from must not be after to';
  end if;
  if v_to - v_from > 400 then
    raise exception 'invalid_input: range must be 400 days or fewer';
  end if;
  lo := (v_from::timestamp) at time zone 'UTC';
  hi := ((v_to + 1)::timestamp) at time zone 'UTC';
  m := '{}'::jsonb;

  -- Gross captured volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status in ('succeeded','refunded') and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('gross_captured_volume', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.total where status in (succeeded, refunded). Captured card volume including buyer fees; refunds are NOT netted out — see refunded_volume.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Refunded volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'refunded' and p.refunded_at >= lo and p.refunded_at < hi;
  -- The local model records refund STATUS only: charge.refunded (which Stripe
  -- also sends for partial refunds) flips payments.status to refunded and no
  -- refunded amount is stored. The amount is therefore an UPPER BOUND, never a
  -- headline figure.
  m := m || jsonb_build_object('refunded_volume', jsonb_build_object(
         'value_cents', null, 'upper_bound_cents', v_val, 'count', v_cnt, 'certainty', 'uncertain',
         'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Count of payments with status = refunded. The amount is not available locally: payments records refund status only, and Stripe sends charge.refunded for partial refunds too, so Σ payments.total is only an upper bound. Verify amounts in the Stripe Dashboard.',
         'note', 'upper_bound_cents = Σ payments.total over refunded rows; the true refunded amount may be lower.',
         'source', 'public.payments', 'basis', 'refunded_at, UTC calendar day'));

  -- Platform fees (gross, pre-refund)
  select coalesce(sum(p.buyer_fee + coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'succeeded' and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('platform_fees_gross', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of buyer_fee + seller_fee on succeeded payments. Gross and pre-refund; not revenue.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Seller funds released to connected account
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.stripe_transfer_id is not null and t.payout_released_at >= lo and t.payout_released_at < hi;
  m := m || jsonb_build_object('seller_funds_released', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.amount - seller_fee for transfers whose stripe_transfer_id is set (a Stripe Transfer to the seller''s connected account exists). Not a bank payout.',
         'source', 'public.transfers + public.payments', 'basis', 'payout_released_at, UTC calendar day'));

  -- Seller funds pending (point in time)
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status in ('seller_sent','buyer_confirmed','auto_released') and t.stripe_transfer_id is null
     and p.status = 'succeeded';
  m := m || jsonb_build_object('seller_funds_pending', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Seller share (amount - seller_fee) of transfers in seller_sent / buyer_confirmed / auto_released with no Stripe Transfer yet. Point-in-time, not a date range.',
         'source', 'public.transfers + public.payments', 'basis', 'now()'));

  -- Bank payouts — not tracked
  m := m || jsonb_build_object('bank_payouts', jsonb_build_object(
         'value_cents', null, 'count', null, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Not tracked. Payouts from connected accounts to sellers'' banks are Stripe-side; the payout.paid webhook is only logged.',
         'source', null, 'basis', 'not_tracked'));

  return jsonb_build_object(
    'from', v_from, 'to', v_to, 'currency', 'USD', 'computed_at', now(),
    'metrics', m,
    'snapshot', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value, 'computed_at', s.computed_at) order by s.key)
                            from ops.metric_snapshot s), '[]'::jsonb),
    'snapshot_computed_at', (select max(computed_at) from ops.metric_snapshot));
end;
$ops$;
revoke all on function ops.money_overview(date,date) from public, anon, authenticated;
grant execute on function ops.money_overview(date,date) to authenticated;

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
           'definition', 'Count of payments with status = refunded; amount NOT available locally (status-only model, partial refunds indistinguishable) — cents below are an upper bound',
           'basis', 'refunded_at (UTC date)', 'currency', 'USD', 'certainty', 'uncertain', 'value_cents', null,
           'window_30d', jsonb_build_object('count', count(*) filter (where coalesce(p.refunded_at, p.paid_at) >= v_from),
                                            'upper_bound_cents', coalesce(sum(p.total) filter (where coalesce(p.refunded_at, p.paid_at) >= v_from), 0)),
           'all_time',   jsonb_build_object('count', count(*), 'upper_bound_cents', coalesce(sum(p.total), 0)))
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

drop function if exists ops.refund_facts(timestamptz, timestamptz);

commit;
