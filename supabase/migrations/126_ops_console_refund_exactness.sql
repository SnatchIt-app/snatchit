-- ============================================================================
-- 126_ops_console_refund_exactness.sql — the ops console states refunded MONEY
-- exactly when the ledger makes it knowable, and says "mixed" when it does not.
--
-- AUTHORSHIP. Part 1 (ops.refund_facts, the single definition) written by
-- Claude A at 048eeb1; taken over by Claude B 2026-09-15 per the owner's sprint
-- directive. refund_facts is rewritten here to close R126-1 and R126-2 (below);
-- parts 2–3 rewire every surface onto it. Number stays 126 (129 withdrawn).
--
-- WHY THIS IS POSSIBLE. `120` refuses to state an amount (status-only model;
-- charge.refunded fires for partial refunds). `20260906120000` added the
-- append-only public.payment_refunds ledger, payments.amount_refunded_cents and
-- the single writer public.record_payment_refund, so an amount is now recorded —
-- for refunds observed after that migration.
--
-- ONE DEFINITION. ops.refund_facts(p_from, p_to) is the only place refund
-- semantics live. ops.build_daily_summary (live_24h), ops.money_overview
-- (refunded_volume) and ops.refresh_metrics (money.refunded) map its result.
--
-- THE SEMANTICS (pgTAP 193 pins each):
--   * Window: ledger created_at, half-open [p_from, p_to), UTC. A NULL or
--     inverted window raises invalid_input (never a silent known zero).
--   * Per-payment cap (R126-1, A8/A9). The writer caps each ROW at total and
--     caps payments.amount_refunded_cents at total, but not the SUM of rows: a
--     full refund followed by a lost chargeback, or a partial refund followed
--     by an amount-less refund (writer: NULL = total), ledgers more than the
--     payment. Each row's effective amount is its slice of the payment's capped
--     running sum in (created_at, id) order —
--       least(run, total) − least(run − amount, total)
--     — so the all-time sum equals Σ payments.amount_refunded_cents exactly,
--     A3 (two partials) and A4 (window slicing) still hold, and a row that the
--     cap consumes moves no money and counts no payment.
--   * Unrecorded refunds (R126-2, A5/A10). A payment whose refunded_at falls in
--     the window and precedes every ledger row it has carries a refund with no
--     recorded amount: legacy rows (never backfilled, 20260906120000:303-305;
--     7 in production 2026-03-29..08-04) and settle_verified_payment's
--     status-only branch when Stripe gives no refund id. Their possible
--     unrecorded money is bounded by total − amount_refunded_cents and reported
--     as legacy_upper_bound_cents, never added into cents.
--   * certainty: 'known' — every refund in the window is recorded (A5: an empty
--     window is a known zero); 'mixed' — cents is the exact ledger part and
--     upper_bound_cents = cents + legacy_upper_bound_cents; 'uncertain' — the
--     ledger itself is absent (A7), 120's shape, cents null.
--   * count = distinct payments with money in the window (ledger slice > 0, or
--     an unrecorded refund); full/partial classify recorded payments only, on
--     the payment's cumulative refund (amount_refunded_cents >= total).
--
-- SURFACE MAPPING (the release admin client, checked in admin/src):
--   * build_daily_summary live_24h: refunded_cents/count/upper_bound/certainty
--     keep 120's names; adds refunded_legacy_upper_bound_cents,
--     refunded_legacy_count, refunded_full_count, refunded_partial_count. The
--     summary view renders a figure only for certainty 'known'; 'mixed' falls
--     to its bound rendering using refunded_upper_bound_cents (a true bound).
--   * money_overview refunded_volume: value_cents is the tile HEADLINE and the
--     client renders it without reading certainty, so value_cents is set only
--     when certainty is 'known'; known_cents always carries the exact part.
--   * refresh_metrics money.refunded: window_30d and all_time objects carry the
--     full fact set; top-level value_cents only when all-time is 'known'.
--
-- A6 needs no change: ops.normalize_summary_body passes any body that already
-- carries refunded_certainty through untouched and only rewrites legacy numeric
-- bodies into the uncertain shape; ops.latest_summary is unchanged.
--
-- BOUNDARY CHANGE, recorded: 120's build_daily_summary counted refunds with a
-- CLOSED upper bound (<= v_to), so a refund at exactly midnight was counted in
-- two adjacent daily summaries; refund_facts is half-open.
--
-- GRANTS. ops.refund_facts is INTERNAL (no EXECUTE for anon, authenticated or
-- service_role): its only callers are the three SECURITY DEFINER functions
-- below. Grants of the three re-created functions are unchanged (create or
-- replace preserves them; re-stated to match the applied migrations).
-- CI: no public object — Gate-2 census, grant-decision manifest and
-- expected_grants are unaffected (they count schema public only).
--
-- NOT CHANGED: public.* (record_payment_refund, payment_refunds are read-only
-- inputs), ops.normalize_summary_body, ops.latest_summary, every non-refund key
-- of the three functions (byte-identical to 120/118 outside the refund blocks).
-- Applied migrations 116/117/118/120 are not edited.
-- Rollback: supabase/rollbacks/126_ops_console_refund_exactness_rollback.sql
-- Tests: supabase/tests/193_ops_console_refund_exactness.sql
-- Applied nowhere by this file. Census: +1 function in schema ops.
-- ============================================================================
begin;

-- ── 1. The one definition ───────────────────────────────────────────────────
create or replace function ops.refund_facts(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cents        bigint;
  v_count        integer;
  v_full         integer;
  v_partial      integer;
  v_legacy_n     integer;
  v_legacy_bound bigint;
begin
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'invalid_input: refund_facts needs a non-null window with p_from <= p_to';
  end if;

  -- A7: a database replayed before the refund ledger. 120's shape, no error.
  if to_regclass('public.payment_refunds') is null then
    select coalesce(sum(p.total), 0), count(*)
      into v_legacy_bound, v_count
      from public.payments p
     where p.status = 'refunded' and p.refunded_at >= p_from and p.refunded_at < p_to;
    return jsonb_build_object(
      'cents', null, 'count', v_count,
      'upper_bound_cents', v_legacy_bound, 'legacy_upper_bound_cents', v_legacy_bound, 'legacy_count', v_count,
      'full_count', null, 'partial_count', null,
      'certainty', 'uncertain',
      'source', 'public.payments', 'basis', 'refunded_at, UTC, half-open',
      'note', 'amount not available locally: public.payment_refunds is absent, so only refund STATUS is known. upper_bound_cents = the sum of payments.total over refunded rows; the true amount may be lower.');
  end if;

  with touched as (
    select distinct r.payment_id from public.payment_refunds r
     where r.created_at >= p_from and r.created_at < p_to
  ), runs as (
    -- every ledger row of a touched payment, so the running cap sees history
    select r.payment_id, r.created_at, r.amount_cents, p.total,
           sum(r.amount_cents) over (partition by r.payment_id order by r.created_at, r.id
                                     rows between unbounded preceding and current row) as run
      from public.payment_refunds r
      join public.payments p on p.id = r.payment_id
     where r.payment_id in (select t.payment_id from touched t)
  ), sliced as (
    select payment_id,
           sum(greatest(0, least(run, total) - least(run - amount_cents, total))) as cents
      from runs
     where created_at >= p_from and created_at < p_to
     group by payment_id
  ), legacy as (
    -- refunded before any ledger row it has: the amount was never recorded
    select p.id, greatest(0, p.total - coalesce(p.amount_refunded_cents, 0)) as bound
      from public.payments p
     where p.refunded_at >= p_from and p.refunded_at < p_to
       and not exists (select 1 from public.payment_refunds r
                        where r.payment_id = p.id and r.created_at <= p.refunded_at)
  ), moved as (
    select s.payment_id from sliced s where s.cents > 0
    union
    select l.id from legacy l
  )
  select coalesce((select sum(s.cents) from sliced s), 0),
         (select count(*) from moved),
         (select count(*) from sliced s join public.payments p on p.id = s.payment_id
           where s.cents > 0 and p.amount_refunded_cents >= p.total
             and not exists (select 1 from legacy l where l.id = s.payment_id)),
         (select count(*) from sliced s join public.payments p on p.id = s.payment_id
           where s.cents > 0 and p.amount_refunded_cents <  p.total
             and not exists (select 1 from legacy l where l.id = s.payment_id)),
         (select count(*) from legacy),
         coalesce((select sum(l.bound) from legacy l), 0)
    into v_cents, v_count, v_full, v_partial, v_legacy_n, v_legacy_bound;

  return jsonb_build_object(
    'cents', v_cents, 'count', v_count,
    'upper_bound_cents', v_cents + v_legacy_bound,
    'legacy_upper_bound_cents', v_legacy_bound, 'legacy_count', v_legacy_n,
    'full_count', v_full, 'partial_count', v_partial,
    'certainty', case when v_legacy_n = 0 then 'known' else 'mixed' end,
    'source', case when v_legacy_n = 0 then 'public.payment_refunds' else 'public.payment_refunds + public.payments' end,
    'basis', 'ledger created_at, UTC, half-open; refunded_at for refunds with no ledger row',
    'note', case when v_legacy_n = 0
              then 'exact: summed from the append-only refund and chargeback ledger, each payment capped at what it refunded.'
              else 'mixed: cents is exact from the ledger; ' || v_legacy_n || ' refunded payment(s) in this range have no recorded amount (refunded before the ledger, or recorded by status only), bounded by legacy_upper_bound_cents.' end);
end;
$$;

comment on function ops.refund_facts(timestamptz, timestamptz) is
  '126: the single definition of refunded money for the ops console. Ledger rows (refunds and lost chargebacks) over the half-open window, each payment capped at what it refunded (its slice of the capped running sum), so the all-time figure equals Σ payments.amount_refunded_cents. certainty known when every refund in the window is recorded, mixed when some refunded payment has no recorded amount (cents exact, legacy_upper_bound_cents separate), uncertain (120''s shape) when the ledger is absent. INTERNAL: no client or service grant.';

revoke all on function ops.refund_facts(timestamptz, timestamptz) from public, anon, authenticated, service_role;

-- ── 2. ops.build_daily_summary — refund keys from refund_facts ──────────────
create or replace function ops.build_daily_summary(p_date date default (now() at time zone 'utc')::date)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
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
$ops$;
revoke all on function ops.build_daily_summary(date) from public, anon, authenticated, service_role;

-- ── 3. ops.money_overview — refunded_volume from refund_facts ───────────────
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
$ops$;
revoke all on function ops.money_overview(date,date) from public, anon, authenticated;
grant execute on function ops.money_overview(date,date) to authenticated;

-- ── 4. ops.refresh_metrics — money.refunded from refund_facts ───────────────
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
$ops$;
revoke all on function ops.refresh_metrics() from public, anon, authenticated, service_role;

commit;
