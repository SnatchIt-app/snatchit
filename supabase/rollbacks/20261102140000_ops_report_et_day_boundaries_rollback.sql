-- ============================================================================
-- ROLLBACK for 20261102140000_ops_report_et_day_boundaries.sql (registry 200).
-- Restores the applied predecessor of each of the four functions, per environment, under an inverse md5 guard:
--   production ET -> 118 (money_overview, refresh_metrics) / 120 (build_daily_summary) body, verbatim;
--   CI ET         -> the parked 126's bodies, verbatim;
--   ET (one body) -> 189's ops.primary_reconciliation, verbatim.
-- The guard accepts, per function, only 200's ET md5s (restored) or the predecessor md5s (already restored: a no-op,
-- so a second run changes nothing). Any other body is refused, never overwritten. No drop, no CASCADE: CREATE OR
-- REPLACE keeps owner and grants; the post-check proves each predecessor md5 and an unchanged ACL / SECURITY DEFINER /
-- search_path / owner / volatility against this file's own pre-capture.
-- Data: 200 writes no row. ops.daily_summary rows written while 200 was live keep their ET summary_date / period;
-- the next ops-daily-summary run after this rollback writes 120/126's UTC shape again.
-- Order: roll back 200 BEFORE 189's rollback (189's guard refuses a non-189 primary_reconciliation).
-- ============================================================================
begin;
set local lock_timeout = '3s';

do $rbpf$
declare
  r      record;
  v_md5  text;
  v_n    integer;
  v_env  text;
  v_envs text[] := '{}';
  v_cap  jsonb  := '[]'::jsonb;
begin
  for r in
    select * from (values
      ('ops.money_overview(date,date)',           'money_overview',          '2903d6deb3a9949cb317ba9d05b860ab', '895b0fa065d7fbdae1cd192d92219b0e', '1183b6b0ea1449e4c62daee4e523b908', 'c5ba4b2b061acf43303c47ab27acb390'),
      ('ops.refresh_metrics()',                   'refresh_metrics',         '60ee7526afd18e411744492c4ccae0f7', '97be33e2546438353533ec75d0eaa52f', '765004a913c384e41f6dcff6edad6b60', '58e7ba9d6d621e4cb95ffafe8a18bc6d'),
      ('ops.build_daily_summary(date)',           'build_daily_summary',     'cc2e6085528cb74e0c233bded189dedf', '0b5eefaea2b976c46cbd906e1703695f', '0a2dbc93f29aad0f17acb620c564a933', '6667c83b04344e9f8b02334b4ac7c7ed'),
      ('ops.primary_reconciliation(date,date)',   'primary_reconciliation',  '4ee4fc15337e895cf180d9d6ce0dc121', '4ee4fc15337e895cf180d9d6ce0dc121', 'bc708b9977a9b2da5dac908f0f3f87d0', 'bc708b9977a9b2da5dac908f0f3f87d0')
    ) as t(sig, name, prod_pred, ci_pred, prod_et, ci_et)
  loop
    select count(*) into v_n from pg_proc p where p.pronamespace = 'ops'::regnamespace and p.proname = r.name;
    if to_regprocedure(r.sig) is null or v_n <> 1 then
      raise exception 'ROLLBACK_200_REFUSED: % — expected exactly one ops.% overload with this signature (overloads %); nothing changed',
        r.sig, r.name, v_n;
    end if;
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    v_env := case
               when r.prod_pred = r.ci_pred and v_md5 in (r.prod_pred, r.prod_et) then 'any'
               when v_md5 in (r.prod_pred, r.prod_et) then 'production'
               when v_md5 in (r.ci_pred, r.ci_et)     then 'ci'
             end;
    if v_env is null then
      raise exception 'ROLLBACK_200_REFUSED: % has md5 %, neither 200''s ET body (production %, CI %) nor its predecessor (production %, CI %) — not overwriting a foreign body; nothing changed',
        r.sig, v_md5, r.prod_et, r.ci_et, r.prod_pred, r.ci_pred;
    end if;
    if v_env <> 'any' then v_envs := v_envs || v_env; end if;
    v_cap := v_cap || jsonb_build_array((
      select jsonb_build_object('sig', r.sig, 'env', v_env, 'md5', v_md5,
               'want', case v_env when 'ci' then r.ci_pred else r.prod_pred end,
               'acl', coalesce(p.proacl::text, '<null>'), 'secdef', p.prosecdef,
               'cfg', coalesce(p.proconfig::text, '<null>'), 'owner', p.proowner::regrole::text,
               'vol', p.provolatile::text)
        from pg_proc p where p.oid = to_regprocedure(r.sig)));
  end loop;
  if (select count(distinct e) from unnest(v_envs) e) <> 1 then
    raise exception 'ROLLBACK_200_REFUSED: money_overview / refresh_metrics / build_daily_summary mix production and CI bodies (%); nothing changed',
      array_to_string(v_envs, ',');
  end if;
  perform set_config('rollback_200.preflight', v_cap::text, true);
end $rbpf$;

-- ── C1 ops.money_overview(date,date)
do $rb1$
declare v_md5 text := md5(pg_get_functiondef(to_regprocedure('ops.money_overview(date,date)')));
begin
  if v_md5 = '1183b6b0ea1449e4c62daee4e523b908' then
    execute $prod$
CREATE OR REPLACE FUNCTION ops.money_overview(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
$prod$;
    raise notice '200 rollback: ops.money_overview(date,date) production ET -> 118/120 body';
  elsif v_md5 = 'c5ba4b2b061acf43303c47ab27acb390' then
    execute $ci$
CREATE OR REPLACE FUNCTION ops.money_overview(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_to    date := coalesce(p_to,   (now() at time zone 'UTC')::date);
  v_from  date := coalesce(p_from, v_to - 30);
  lo      timestamptz;
  hi      timestamptz;
  m       jsonb;
  v_val   bigint; v_cnt bigint;
  v_rf    jsonb;
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

  -- Refunded volume (126): the one definition, ops.refund_facts, over [lo, hi).
  -- value_cents is the page headline and the release client renders it without
  -- reading certainty, so it is set ONLY when certainty is 'known'; the exact
  -- ledger part always rides in known_cents, and upper_bound_cents is a true
  -- bound (exact + legacy) whenever an unrecorded refund exists.
  v_rf := ops.refund_facts(lo, hi);
  m := m || jsonb_build_object('refunded_volume', jsonb_build_object(
         'value_cents', case when v_rf ->> 'certainty' = 'known' then v_rf -> 'cents' else 'null'::jsonb end,
         'known_cents', v_rf -> 'cents',
         'upper_bound_cents', v_rf -> 'upper_bound_cents',
         'legacy_upper_bound_cents', v_rf -> 'legacy_upper_bound_cents',
         'legacy_count', v_rf -> 'legacy_count',
         'count', v_rf -> 'count', 'full_count', v_rf -> 'full_count', 'partial_count', v_rf -> 'partial_count',
         'certainty', v_rf ->> 'certainty',
         'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Money returned to buyers: refunds and lost chargebacks recorded in the append-only ledger, each payment capped at what it actually refunded. Exact (certainty known) only when every refund in the range is recorded; refunds that predate the ledger have no recorded amount (certainty mixed: known_cents is exact, upper_bound_cents adds those payments'' unrefunded totals).',
         'note', v_rf ->> 'note',
         'source', v_rf ->> 'source', 'basis', v_rf ->> 'basis'));

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
$function$
$ci$;
    raise notice '200 rollback: ops.money_overview(date,date) CI ET -> 126 body';
  elsif v_md5 in ('2903d6deb3a9949cb317ba9d05b860ab', '895b0fa065d7fbdae1cd192d92219b0e') then
    raise notice '200 rollback: ops.money_overview(date,date) already carries its predecessor; unchanged';
  else
    raise exception 'ROLLBACK_200_REFUSED: ops.money_overview(date,date) has md5 % (unexpected after the pre-flight)', v_md5;
  end if;
end $rb1$;

-- ── C2 ops.refresh_metrics()
do $rb2$
declare v_md5 text := md5(pg_get_functiondef(to_regprocedure('ops.refresh_metrics()')));
begin
  if v_md5 = '765004a913c384e41f6dcff6edad6b60' then
    execute $prod$
CREATE OR REPLACE FUNCTION ops.refresh_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
$prod$;
    raise notice '200 rollback: ops.refresh_metrics() production ET -> 118/120 body';
  elsif v_md5 = '58e7ba9d6d621e4cb95ffafe8a18bc6d' then
    execute $ci$
CREATE OR REPLACE FUNCTION ops.refresh_metrics()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_now   timestamptz := now();
  v_from  timestamptz := (date_trunc('day', now() at time zone 'utc') - interval '30 days') at time zone 'utc';
  v_rows  jsonb := '{}'::jsonb;
  v_n     integer := 0;
  v_key   text;
  v_val   jsonb;
  v_rf30  jsonb;
  v_rfall jsonb;
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

  -- Refunded volume (126): the one definition, ops.refund_facts. window_30d is
  -- [v_from, +infinity), all_time (-infinity, +infinity). value_cents (all-time)
  -- only when all-time certainty is 'known'.
  v_rf30  := ops.refund_facts(v_from, 'infinity');
  v_rfall := ops.refund_facts('-infinity', 'infinity');
  v_val := jsonb_build_object(
           'definition', 'Refunds and lost chargebacks from the append-only ledger, each payment capped at what it refunded; exact only when every refund is recorded (see certainty, known_cents is the exact part, upper_bound_cents adds unrecorded refunds'' unrefunded totals)',
           'basis', 'ledger created_at (UTC); refunded_at for refunds with no ledger row', 'currency', 'USD',
           'certainty', v_rfall ->> 'certainty',
           'value_cents', case when v_rfall ->> 'certainty' = 'known' then v_rfall -> 'cents' else 'null'::jsonb end,
           'window_30d', jsonb_build_object('count', v_rf30 -> 'count', 'cents', v_rf30 -> 'cents',
                                            'upper_bound_cents', v_rf30 -> 'upper_bound_cents',
                                            'legacy_upper_bound_cents', v_rf30 -> 'legacy_upper_bound_cents',
                                            'legacy_count', v_rf30 -> 'legacy_count',
                                            'full_count', v_rf30 -> 'full_count', 'partial_count', v_rf30 -> 'partial_count',
                                            'certainty', v_rf30 ->> 'certainty'),
           'all_time',   jsonb_build_object('count', v_rfall -> 'count', 'cents', v_rfall -> 'cents',
                                            'upper_bound_cents', v_rfall -> 'upper_bound_cents',
                                            'legacy_upper_bound_cents', v_rfall -> 'legacy_upper_bound_cents',
                                            'legacy_count', v_rfall -> 'legacy_count',
                                            'full_count', v_rfall -> 'full_count', 'partial_count', v_rfall -> 'partial_count',
                                            'certainty', v_rfall ->> 'certainty'));
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
$function$
$ci$;
    raise notice '200 rollback: ops.refresh_metrics() CI ET -> 126 body';
  elsif v_md5 in ('60ee7526afd18e411744492c4ccae0f7', '97be33e2546438353533ec75d0eaa52f') then
    raise notice '200 rollback: ops.refresh_metrics() already carries its predecessor; unchanged';
  else
    raise exception 'ROLLBACK_200_REFUSED: ops.refresh_metrics() has md5 % (unexpected after the pre-flight)', v_md5;
  end if;
end $rb2$;

-- ── C3 ops.build_daily_summary(date)
do $rb3$
declare v_md5 text := md5(pg_get_functiondef(to_regprocedure('ops.build_daily_summary(date)')));
begin
  if v_md5 = '0a2dbc93f29aad0f17acb620c564a933' then
    execute $prod$
CREATE OR REPLACE FUNCTION ops.build_daily_summary(p_date date DEFAULT ((now() AT TIME ZONE 'utc'::text))::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
$prod$;
    raise notice '200 rollback: ops.build_daily_summary(date) production ET -> 118/120 body';
  elsif v_md5 = '6667c83b04344e9f8b02334b4ac7c7ed' then
    execute $ci$
CREATE OR REPLACE FUNCTION ops.build_daily_summary(p_date date DEFAULT ((now() AT TIME ZONE 'utc'::text))::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_to    timestamptz := least(((p_date + 1)::timestamp at time zone 'utc'), now());
  v_from  timestamptz;
  v_body  jsonb;
  v_rf    jsonb;
  v_detectors text[] := array['paid_unsettled','transfer_deadlines','release_stuck','refunds','disputes','payout_review',
                              'reports','webhooks','jobs','notifications','reconciliation'];
begin
  if p_date is null then
    raise exception 'invalid_input: p_date is required';
  end if;
  v_from := v_to - interval '24 hours';
  v_rf   := ops.refund_facts(v_from, v_to);

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
        -- 126: refunds come from the ONE definition, ops.refund_facts, over the
        -- half-open window [v_from, v_to). Known only when every refund in the
        -- window is ledgered; mixed keeps exact ledger cents and a separate
        -- legacy bound; uncertain (120's shape) only when the ledger is absent.
        'refunded_cents', v_rf -> 'cents',
        'refunded_count', v_rf -> 'count',
        'refunded_upper_bound_cents', v_rf -> 'upper_bound_cents',
        'refunded_legacy_upper_bound_cents', v_rf -> 'legacy_upper_bound_cents',
        'refunded_legacy_count', v_rf -> 'legacy_count',
        'refunded_full_count', v_rf -> 'full_count',
        'refunded_partial_count', v_rf -> 'partial_count',
        'refunded_certainty', v_rf ->> 'certainty',
        'refunded_note', v_rf ->> 'note',
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
$function$
$ci$;
    raise notice '200 rollback: ops.build_daily_summary(date) CI ET -> 126 body';
  elsif v_md5 in ('cc2e6085528cb74e0c233bded189dedf', '0b5eefaea2b976c46cbd906e1703695f') then
    raise notice '200 rollback: ops.build_daily_summary(date) already carries its predecessor; unchanged';
  else
    raise exception 'ROLLBACK_200_REFUSED: ops.build_daily_summary(date) has md5 % (unexpected after the pre-flight)', v_md5;
  end if;
end $rb3$;

-- ── C4 ops.primary_reconciliation(date,date) (ET -> 189)
do $rb4$
declare v_md5 text := md5(pg_get_functiondef(to_regprocedure('ops.primary_reconciliation(date,date)')));
begin
  if v_md5 = 'bc708b9977a9b2da5dac908f0f3f87d0' then
    execute $one$
CREATE OR REPLACE FUNCTION ops.primary_reconciliation(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 189 (A, 2026-10-27): primary (ticket) money vs tickets, one row per FINALIZED native payment
-- (kernel.payment_native with an order — written by venue.finalize_primary_order in the same
-- transaction that mints the atoms). Read-only (STABLE: a write raises). Window: linked_at, UTC
-- calendar days; a NULL bound is open on that side (the default reads every linked payment).
--   tickets   atoms whose sequence-1 ownership-log cause_ref is one of the order's items — the
--             linkage finalize / refund_primary_order / admin_refund use. live = issued|active (the
--             door can still admit), admitted = scanned, voided = voided.
--   kernel    kernel.refund rows of the payment, status <> 'failed' (refund_primary_order's own sum).
--   stripe    public.payment_refund_state of the payment (every Stripe refund the webhook saw,
--             Dashboard refunds included): succeeded, and open = pending|requires_action.
-- Attention items:
--   (i)   stripe_refunded_tickets_live  CRITICAL  Stripe refunded money but tickets are still live
--         (the door would still admit) — unless the kernel recorded a deliberate partial refund
--         (order partially_refunded) covering at least Stripe's amount.
--   (ii)  kernel_refund_without_stripe            kernel refunds older than 24 h exceed every refund
--         Stripe recorded (succeeded or open): the manual Stripe step was not done.
--   (iii) refund_amount_mismatch                  Stripe's succeeded sum <> the kernel sum (Stripe has
--         refunded something; a kernel refund with nothing in Stripe yet is (ii)'s, after 24 h).
--   (iv)  issuance_missing                        linked more than 15 min ago and no atom ever issued.
--         issuance_over                           an order item carries more issued|active|scanned
--                                                 atoms than its quantity (a second issuance).
--   (v)   paid_never_finalized          CRITICAL  a succeeded native payment (public.payments.mode =
--         'native_primary' — the 093 rail-pairing CHECK pins listing_id and seller_id NULL on it) with NO
--         kernel.payment_native link more than 15 min after it succeeded: the buyer paid and holds no
--         ticket. Success time = paid_at, else created_at when paid_at is NULL (earlier: it can only
--         alarm sooner). It has no order to show, so it is an attention item only (order_id NULL);
--         the window applies to that same time.
-- ops.is_test_payment (DC-1) is not on this tree: no test-data filter; stripe_livemode is returned.
declare
  lo     timestamptz;
  hi     timestamptz;
  v_rows jsonb;
  v_att  jsonb;
begin
  -- the console's reader gate: an operator role and an aal2 session (115)
  perform ops.assert_reader();
  if p_from is not null and p_to is not null and p_from > p_to then
    raise exception 'invalid_input: from must not be after to';
  end if;
  lo := (p_from::timestamp) at time zone 'UTC';
  hi := ((p_to + 1)::timestamp) at time zone 'UTC';

  with pn as (
    select x.payment_id, x.order_id, x.linked_at
      from kernel.payment_native x
     where x.order_id is not null
       and (lo is null or x.linked_at >= lo)
       and (hi is null or x.linked_at <  hi)
  ),
  item as (
    select oi.order_id, oi.id as item_id, oi.quantity,
           count(t.ticket_atom_id)::integer                                                  as issued,
           count(t.ticket_atom_id) filter (where t.state = 'voided')::integer                  as voided,
           count(t.ticket_atom_id) filter (where t.state = 'scanned')::integer                 as admitted,
           count(t.ticket_atom_id) filter (where t.state in ('issued', 'active'))::integer     as live,
           count(t.ticket_atom_id) filter (where t.state in ('issued', 'active', 'scanned'))::integer as held_or_used
      from venue.order_item oi
      left join kernel.ticket_ownership_log l1 on l1.cause_ref = oi.id and l1.sequence = 1
      left join kernel.tickets t on t.ticket_atom_id = l1.ticket_atom_id
     where oi.order_id in (select pn.order_id from pn)
     group by oi.order_id, oi.id, oi.quantity
  ),
  ord as (
    select i.order_id,
           sum(i.issued)::integer as issued, sum(i.voided)::integer as voided,
           sum(i.admitted)::integer as admitted, sum(i.live)::integer as live,
           bool_or(i.held_or_used > i.quantity) as over
      from item i
     group by i.order_id
  ),
  kr as (
    select r.payment_id,
           sum(r.amount_minor)::bigint as minor,
           coalesce(sum(r.amount_minor) filter (where r.created_at <= now() - interval '24 hours'), 0)::bigint as aged,
           count(*)::integer as n
      from kernel.refund r
     where r.status <> 'failed'
       and r.payment_id in (select pn.payment_id from pn)
     group by r.payment_id
  ),
  sr as (
    select s.payment_id,
           coalesce(sum(s.amount_cents) filter (where s.status = 'succeeded'), 0)::bigint as ok,
           coalesce(sum(s.amount_cents) filter (where s.status in ('pending', 'requires_action')), 0)::bigint as open
      from public.payment_refund_state s
     where s.payment_id in (select pn.payment_id from pn)
     group by s.payment_id
  ),
  r as (
    select pn.payment_id, pn.order_id, pn.linked_at,
           p.status as payment_status, p.total as payment_total_minor, p.stripe_livemode,
           o.status as order_status, o.total_minor as order_total_minor,
           coalesce(ord.issued, 0) as issued, coalesce(ord.voided, 0) as voided,
           coalesce(ord.admitted, 0) as admitted, coalesce(ord.live, 0) as live,
           coalesce(ord.over, false) as over,
           coalesce(kr.minor, 0) as k_minor, coalesce(kr.aged, 0) as k_aged, coalesce(kr.n, 0) as k_n,
           coalesce(sr.ok, 0) as s_ok, coalesce(sr.open, 0) as s_open
      from pn
      join public.payments p on p.id = pn.payment_id
      join venue."order" o on o.order_id = pn.order_id
      left join ord on ord.order_id = pn.order_id
      left join kr on kr.payment_id = pn.payment_id
      left join sr on sr.payment_id = pn.payment_id
  ),
  a as (
    select r.*,
           array_remove(array[
             -- (i) CRITICAL: Stripe refunded, the door would still admit
             case when r.s_ok > 0 and r.live > 0
                   and not (r.order_status = 'partially_refunded' and r.s_ok <= r.k_minor)
                  then 'stripe_refunded_tickets_live' end,
             -- (ii) a kernel refund with no matching Stripe refund after 24 h
             case when r.k_aged > r.s_ok + r.s_open then 'kernel_refund_without_stripe' end,
             -- (iii) the kernel sum and Stripe's succeeded sum disagree
             case when r.s_ok > 0 and r.s_ok <> r.k_minor then 'refund_amount_mismatch' end,
             -- (iv) exactly-one issuance: none after 15 min, or more than the item's quantity
             case when r.issued = 0 and r.linked_at <= now() - interval '15 minutes' then 'issuance_missing' end,
             case when r.over then 'issuance_over' end
           ]::text[], null) as codes
      from r
  ),
  unl as (
    -- (v) CRITICAL: paid, never finalized
    select p.id as payment_id, null::uuid as order_id, coalesce(p.paid_at, p.created_at) as linked_at,
           'paid_never_finalized'::text as code, 1::bigint as n
      from public.payments p
     where p.mode = 'native_primary'
       and p.status = 'succeeded'
       and coalesce(p.paid_at, p.created_at) <= now() - interval '15 minutes'
       and (lo is null or coalesce(p.paid_at, p.created_at) >= lo)
       and (hi is null or coalesce(p.paid_at, p.created_at) <  hi)
       and not exists (select 1 from kernel.payment_native x where x.payment_id = p.id)
  ),
  att as (
    select a.payment_id, a.order_id, a.linked_at, c.code, c.n
      from a, unnest(a.codes) with ordinality as c(code, n)
    union all
    select u.payment_id, u.order_id, u.linked_at, u.code, u.n
      from unl u
  )
  select (select coalesce(jsonb_agg(jsonb_build_object(
                   'payment_id', a.payment_id, 'order_id', a.order_id, 'linked_at', a.linked_at,
                   'payment_status', a.payment_status, 'payment_total_minor', a.payment_total_minor,
                   'stripe_livemode', a.stripe_livemode,
                   'order_status', a.order_status, 'order_total_minor', a.order_total_minor,
                   'tickets_issued', a.issued, 'tickets_voided', a.voided,
                   'tickets_admitted', a.admitted, 'tickets_live', a.live,
                   'kernel_refund_minor', a.k_minor, 'kernel_refund_count', a.k_n,
                   'stripe_refund_succeeded_minor', a.s_ok, 'stripe_refund_open_minor', a.s_open,
                   'state', case when cardinality(a.codes) > 0 then 'attention'
                                 when a.k_minor > a.s_ok then 'refund_awaiting_stripe'
                                 when a.s_ok > 0 then 'refund_settled'
                                 else 'ok' end,
                   'attention', to_jsonb(a.codes))
                 order by a.linked_at desc, a.payment_id), '[]'::jsonb)
            from a),
         (select coalesce(jsonb_agg(jsonb_build_object(
                   'code', att.code,
                   'severity', case when att.code in ('stripe_refunded_tickets_live', 'paid_never_finalized') then 'critical' else 'warning' end,
                   'payment_id', att.payment_id, 'order_id', att.order_id,
                   'message', case att.code
                     when 'stripe_refunded_tickets_live' then 'Stripe shows a succeeded refund but tickets of this order are still live: the door would still admit them. Record the refund (it voids them) or confirm a deliberate partial.'
                     when 'kernel_refund_without_stripe' then 'A refund recorded here more than 24 h ago has no matching refund in Stripe: refund the PaymentIntent in the Stripe Dashboard.'
                     when 'refund_amount_mismatch'       then 'The refunds recorded here and the refunds Stripe shows as succeeded differ in amount.'
                     when 'issuance_missing'             then 'Paid and linked more than 15 minutes ago, but no ticket was ever issued for this order.'
                     when 'issuance_over'                then 'An order item carries more tickets than its quantity.'
                     when 'paid_never_finalized'         then 'The buyer paid more than 15 minutes ago and the payment was never finalized: no order is linked and no ticket was issued. Finalize the order or refund the payment.'
                   end)
                 order by (att.code not in ('stripe_refunded_tickets_live', 'paid_never_finalized')), att.linked_at desc, att.payment_id, att.n), '[]'::jsonb)
            from att)
    into v_rows, v_att;

  return jsonb_build_object(
    'from', p_from, 'to', p_to, 'computed_at', now(), 'currency', 'USD',
    'basis', 'kernel.payment_native.linked_at, UTC calendar day; a NULL bound is open',
    'count', jsonb_array_length(v_rows),
    'attention_count', jsonb_array_length(v_att),
    'critical_count', (select count(*) from jsonb_array_elements(v_att) e where e ->> 'severity' = 'critical'),
    'rows', v_rows,
    'attention', v_att);
end;
$function$
$one$;
    raise notice '200 rollback: ops.primary_reconciliation(date,date) ET -> 189';
  elsif v_md5 = '4ee4fc15337e895cf180d9d6ce0dc121' then
    raise notice '200 rollback: ops.primary_reconciliation(date,date) already carries its predecessor; unchanged';
  else
    raise exception 'ROLLBACK_200_REFUSED: ops.primary_reconciliation(date,date) has md5 % (unexpected after the pre-flight)', v_md5;
  end if;
end $rb4$;

-- ── POST-CHECK: the predecessor md5 of the detected environment, and every captured attribute unchanged.
do $rbpc$
declare
  v_cap jsonb := nullif(current_setting('rollback_200.preflight', true), '')::jsonb;
  e     jsonb;
  q     record;
begin
  if v_cap is null or jsonb_array_length(v_cap) <> 4 then
    raise exception 'ROLLBACK_200_FAILED: the pre-flight capture is missing — run this file as one transaction';
  end if;
  for e in select * from jsonb_array_elements(v_cap) loop
    select md5(pg_get_functiondef(p.oid)) as md5, coalesce(p.proacl::text, '<null>') as acl, p.prosecdef,
           p.proconfig, coalesce(p.proconfig::text, '<null>') as cfg, p.proowner::regrole::text as owner,
           p.provolatile::text as vol,
           (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) as n
      into q from pg_proc p where p.oid = to_regprocedure(e ->> 'sig');
    if q.md5 is distinct from e ->> 'want' then
      raise exception 'ROLLBACK_200_FAILED: % body md5 % is not its predecessor % (environment %) — this file was modified',
        e ->> 'sig', coalesce(q.md5, '<absent>'), e ->> 'want', e ->> 'env';
    end if;
    if q.acl is distinct from e ->> 'acl' then
      raise exception 'ROLLBACK_200_FAILED: % ACL changed from % to %', e ->> 'sig', e ->> 'acl', q.acl;
    end if;
    if q.prosecdef is distinct from (e ->> 'secdef')::boolean or not q.prosecdef then
      raise exception 'ROLLBACK_200_FAILED: % SECURITY DEFINER changed (was %, now %)', e ->> 'sig', e ->> 'secdef', q.prosecdef;
    end if;
    if q.cfg is distinct from e ->> 'cfg' or q.proconfig is distinct from array['search_path=""'] then
      raise exception 'ROLLBACK_200_FAILED: % proconfig changed (was %, now %)', e ->> 'sig', e ->> 'cfg', q.cfg;
    end if;
    if q.owner is distinct from e ->> 'owner' or q.vol is distinct from e ->> 'vol' or q.n <> 1 then
      raise exception 'ROLLBACK_200_FAILED: % owner/volatility/overloads changed (owner % -> %, volatility % -> %, overloads %)',
        e ->> 'sig', e ->> 'owner', q.owner, e ->> 'vol', q.vol, q.n;
    end if;
  end loop;
  raise notice '200 rollback post-check: % ok',
    (select string_agg((x ->> 'sig') || '=' || left(x ->> 'want', 8), ' ') from jsonb_array_elements(v_cap) x);
end $rbpc$;

commit;
