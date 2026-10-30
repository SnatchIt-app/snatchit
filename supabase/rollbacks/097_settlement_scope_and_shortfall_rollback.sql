-- ============================================================================
-- 097_settlement_scope_and_shortfall_rollback.sql
--   REVERSES supabase/migrations/097_settlement_scope_and_shortfall.sql
-- ----------------------------------------------------------------------------
-- POSTURE: BREAK-GLASS ONLY, AND IT RESTORES FOUR KNOWN DEFECTS. Read this
-- before running it.
--
--   1. Restoring kernel.settlement_royalty_lines to its 093 body REINTRODUCES
--      the cross-venue netting leak (097 §5 / KG P0-1): a chargeback at any
--      venue of an org is again offered to whichever venue's settlement
--      closes next, at full magnitude, with zero trace in kernel.
--      organization_obligation.
--   2. Restoring kernel.settlement_primary_lines and kernel.settlement_
--      royalty_lines to their pre-097 refund-deferral shape REINTRODUCES the
--      phantom-debt case (097 §4/§5 / KC P0-2): a chargeback can again be
--      booked against a venue that was paid zero because the matching credit
--      sits deferred behind a refund the executor will never accept.
--   3. Restoring kernel.record_organization_obligation to its 094 body makes
--      `unlined_reversal` free-amount and per-dispute-guarded again (097 §3 /
--      KC P1-2): a loss already absorbed by the chargeback arm, or already
--      booked once, becomes bookable a second time, uncapped.
--   4. Restoring kernel.settlement_payout_maturity / kernel.settlement_
--      maturity_hold_codes to their pre-097 bodies REMOVES the
--      'dispute_unabsorbed' hold (097 §7 / KB P0-1): a lost dispute against a
--      still-pending payout of the SAME order again holds nothing.
--
-- So this file exists for the case where 097 itself is found to be wrong. It
-- is not a routine undo.
--
-- FORWARD-FIX, NEVER DROP MONEY STATE. The guard below REFUSES to run while
-- kernel.organization_obligation holds ANY row at all — not only rows with a
-- venue_id set. 097 is the first writer to derive venue_id, so every row
-- written after 097 applied depends on the 097-shape verb to have produced
-- it, and dropping the column would silently discard that provenance for
-- every row, present or future, the instant the DDL runs. A table with rows
-- is evidence money already moved (settlement_shortfall) or a loss already
-- recorded (unlined_reversal); resolve or forward-fix instead of rolling
-- back under it.
--
-- `set local row_security = off` before the count is the 081-087/095/096
-- house pattern: kernel.organization_obligation is RLS-on with ZERO policies
-- and REVOKE ALL from every role including service_role, so a non-BYPASSRLS,
-- non-owner runner would count 0 rows and the guard would fail OPEN.
--
-- ORDER MATTERS, for the 091/095/096 reason: a PL/pgSQL body carries no
-- pg_depend edge, so dropping a COLUMN a live body still references leaves a
-- compiling-but-broken money function. Hence every function body that reads
-- or writes venue_id is restored to its PRE-097 text (which never mentions
-- the column) BEFORE the column itself is dropped:
--   (a) kernel.record_organization_obligation and kernel.organization_
--       obligation_guard — the two bodies that write/guard venue_id — go
--       FIRST;
--   (b) kernel.close_settlement, kernel.settlement_primary_lines, kernel.
--       settlement_royalty_lines, kernel.settlement_payout_maturity, kernel.
--       settlement_maturity_hold_codes, kernel.record_dispute_native, kernel.
--       mark_dispute_state follow, in any order — none of them names the
--       column, so their relative order does not matter;
--   (c) the column is dropped LAST, after every body that could reference it
--       is gone.
-- The restored texts below are 093/094/095/088's texts VERBATIM (093:435-560,
-- 093:1136-1216, 093:2076-2170, 094:260-293, 094:320-413, 094:544-790,
-- 095:458-478, 088:758-867, 088:875-902) — the only difference from the
-- shipped migrations' copies is that this file carries no other package's
-- unrelated sections.
--
-- ORDERING WITH THE OTHER 09x PACKAGES: 096_payout_reversal_and_obligation_
-- recovery.sql creates kernel.payout_reversal and kernel.organization_
-- obligation_recovery and touches neither this migration's re-created
-- functions nor kernel.organization_obligation's DDL; the two rollbacks are
-- independent and may be run in either order (096's own header makes the
-- same claim about 094/095).
-- Second run: NOTICE, no-op.
-- ============================================================================
begin;

do $$
declare v_rows bigint;
begin
  if to_regprocedure('kernel.record_organization_obligation(uuid, text, uuid, text, integer, text, text, text)') is null then
    raise notice '097 rollback: kernel.record_organization_obligation is absent — nothing to roll back — no-op';
    return;
  end if;
  set local row_security = off;
  select count(*) into v_rows from kernel.organization_obligation;
  if v_rows > 0 then
    raise exception 'rollback_refused: kernel.organization_obligation holds % row(s). 097''s venue_id column carries provenance no pre-097 body can re-derive; dropping it here would silently discard that fact. Resolve or forward-fix instead.', v_rows;
  end if;
end $$;

-- (a) the two bodies that write/guard venue_id, restored FIRST.

-- kernel.record_organization_obligation — 094:320-413 VERBATIM.
create or replace function kernel.record_organization_obligation(
  p_org_id uuid, p_origin_kind text, p_origin_ref uuid, p_stripe_dispute_ref text,
  p_amount_minor integer, p_currency text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id  uuid;
  v_ccy text := coalesce(nullif(p_currency, ''), 'USD');
  v_s   venue.settlement%rowtype;
begin
  if p_origin_kind not in ('settlement_shortfall','unlined_reversal') then
    raise exception 'invalid_input: bad origin_kind %', p_origin_kind using errcode = 'P0001';
  end if;
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'invalid_input: bad_amount' using errcode = 'P0001';
  end if;
  if p_org_id is null or p_origin_ref is null then
    raise exception 'invalid_input: org_id and origin_ref are required' using errcode = 'P0001';
  end if;
  if v_ccy !~ '^[A-Z]{3}$' then
    raise exception 'invalid_input: currency % is not an ISO-4217 alpha code', v_ccy using errcode = 'P0001';
  end if;
  if not exists (select 1 from kernel.organization o where o.org_id = p_org_id) then
    raise exception 'not_found: organization %', p_org_id using errcode = 'P0002';
  end if;

  if p_origin_kind = 'settlement_shortfall' then
    select * into v_s from venue.settlement where settlement_id = p_origin_ref;
    if not found then
      raise exception 'not_found: settlement %', p_origin_ref using errcode = 'P0002';
    end if;
    if v_s.org_id <> p_org_id then
      raise exception 'precondition_failed: settlement % belongs to another org', p_origin_ref using errcode = 'P0001';
    end if;
    if v_s.status = 'open' or v_s.net_minor is null then
      raise exception 'precondition_failed: a shortfall is booked only from a CLOSED settlement' using errcode = 'P0001';
    end if;
    if v_s.net_minor >= 0 then
      raise exception 'precondition_failed: settlement % nets % — there is no shortfall', p_origin_ref, v_s.net_minor
        using errcode = 'P0001';
    end if;
    if p_amount_minor <> -v_s.net_minor then
      raise exception 'precondition_failed: amount % is not the settlement shortfall %', p_amount_minor, -v_s.net_minor
        using errcode = 'P0001';
    end if;
    if v_ccy <> v_s.currency then
      raise exception 'precondition_failed: currency % differs from the settlement currency %', v_ccy, v_s.currency
        using errcode = 'P0001';
    end if;
  else
    if exists (select 1 from venue.settlement_line l
                where l.cause in ('chargeback','refund_void') and l.cause_ref = p_origin_ref) then
      raise exception 'precondition_failed: origin % is already lined — netting has it, booking it here would double-count', p_origin_ref
        using errcode = 'P0001';
    end if;
  end if;

  insert into kernel.organization_obligation
         (org_id, origin_kind, origin_ref, stripe_dispute_ref, amount_minor, currency)
  values (p_org_id, p_origin_kind, p_origin_ref, p_stripe_dispute_ref, p_amount_minor, v_ccy)
  on conflict on constraint organization_obligation_origin_uq do nothing
  returning obligation_id into v_id;
  if v_id is null then
    select o.obligation_id into v_id from kernel.organization_obligation o
     where o.origin_kind = p_origin_kind and o.origin_ref = p_origin_ref;
    return jsonb_build_object('status','noop_replay','obligation_id', v_id);
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'org_obligation.record', 'org_obligation',
          v_id, coalesce(p_reason_code, p_origin_kind));
  return jsonb_build_object('status','ok','obligation_id', v_id, 'amount_minor', p_amount_minor, 'currency', v_ccy);
end;
$$;

-- kernel.organization_obligation_guard — 094:260-293 VERBATIM.
create or replace function kernel.organization_obligation_guard()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'append_only: kernel.organization_obligation rows are never deleted' using errcode = 'P0001';
  end if;
  if new.obligation_id is distinct from old.obligation_id
     or new.org_id      is distinct from old.org_id
     or new.origin_kind is distinct from old.origin_kind
     or new.origin_ref  is distinct from old.origin_ref
     or new.amount_minor is distinct from old.amount_minor
     or new.currency    is distinct from old.currency
     or new.created_at  is distinct from old.created_at then
    raise exception 'append_only: obligation identity, magnitude and currency are write-once' using errcode = 'P0001';
  end if;
  if old.status <> 'outstanding' and new.status is distinct from old.status then
    raise exception 'state_conflict: obligation % is already % — terminals are exclusive', old.obligation_id, old.status
      using errcode = 'P0001';
  end if;
  if new.status = 'outstanding' and old.status <> 'outstanding' then
    raise exception 'state_conflict: an obligation never returns to outstanding' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- (b) every other re-created body, restored to its pre-097 text. Order does
-- not matter among these — none names kernel.organization_obligation.venue_id.

-- kernel.settlement_primary_lines — 093:435-560 VERBATIM.
create or replace function kernel.settlement_primary_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language plpgsql volatile security definer set search_path = ''
as $$
declare v_org uuid;
begin
  select st.org_id into v_org from venue.settlement st where st.settlement_id = p_settlement_id;
  if v_org is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_org::text));
  return query
  with s as (
    select st.settlement_id, st.org_id, st.venue_id, st.event_id,
           st.period_start, st.period_end, st.currency
      from venue.settlement st where st.settlement_id = p_settlement_id
  ),
  scoped_order as (
    select o.order_id, o.total_minor::bigint as face_minor, o.currency, s.org_id
      from s
      join venue."order" o on o.org_id = s.org_id
      join kernel.payment_native pn on pn.order_id = o.order_id
      join catalog.event_session es on es.session_id = o.event_session_id
      join catalog.event e on e.event_id = es.event_id
     where o.status in ('paid','partially_refunded','refunded')
       and o.currency = s.currency
       and ((s.event_id is not null and e.event_id = s.event_id)
            or (s.event_id is null and e.venue_id = s.venue_id
                and (s.period_start is null or es.starts_at >= s.period_start)
                and (s.period_end is null or es.starts_at < s.period_end)))
       and not exists (select 1 from kernel.refund r0
                        where r0.payment_id = pn.payment_id
                          and r0.status in ('pending','submitted'))
  ),
  primary_sale as (
    select 'primary_sale'::text as cause, so.order_id as cause_ref,
           so.face_minor as amount_minor, so.currency,
           'organization'::text as payee_kind, so.org_id as payee_id
      from scoped_order so
     where not exists (select 1 from venue.settlement_line l
                        where l.cause = 'primary_sale' and l.cause_ref = so.order_id)
  ),
  order_prior_debit as (
    select pn2.order_id, (-l.amount_minor)::bigint as debit_minor
      from venue.settlement_line l
      join kernel.refund r2 on r2.refund_id = l.cause_ref
      join kernel.payment_native pn2 on pn2.payment_id = r2.payment_id
     where l.cause = 'refund_void'
    union all
    select pn3.order_id, (-l.amount_minor)::bigint
      from venue.settlement_line l
      join kernel.dispute_native d3 on d3.dispute_id = l.cause_ref
      join kernel.payment_native pn3 on pn3.payment_id = d3.payment_id
     where l.cause = 'chargeback'
  ),
  refund_prior as (
    select opd.order_id, coalesce(sum(opd.debit_minor), 0)::bigint as prior_debit_minor
      from order_prior_debit opd
     where opd.order_id in (select so2.order_id from scoped_order so2)
     group by opd.order_id
  ),
  refund_candidate as (
    select so.order_id, so.face_minor, so.currency, so.org_id,
           r.refund_id, r.amount_minor::bigint as refund_minor, r.created_at,
           coalesce(rp.prior_debit_minor, 0) as prior_debit_minor
      from scoped_order so
      join kernel.payment_native pn on pn.order_id = so.order_id
      join kernel.refund r on r.payment_id = pn.payment_id and r.status = 'succeeded'
      left join refund_prior rp on rp.order_id = so.order_id
     where r.currency = so.currency
       and not exists (select 1 from venue.settlement_line l
                        where l.cause = 'refund_void' and l.cause_ref = r.refund_id)
  ),
  refund_alloc as (
    select rc.refund_id, rc.currency, rc.org_id,
           greatest(
             0,
               least(rc.prior_debit_minor + sum(rc.refund_minor) over w, rc.face_minor)
             - least(rc.prior_debit_minor + sum(rc.refund_minor) over w - rc.refund_minor, rc.face_minor)
           )::bigint as debit_minor
      from refund_candidate rc
    window w as (partition by rc.order_id order by rc.created_at, rc.refund_id
                 rows between unbounded preceding and current row)
  ),
  refund_void as (
    select 'refund_void'::text as cause, ra.refund_id as cause_ref,
           (-ra.debit_minor)::bigint as amount_minor, ra.currency,
           'organization'::text as payee_kind, ra.org_id as payee_id
      from refund_alloc ra
     where ra.debit_minor > 0
  )
  select * from primary_sale
  union all
  select * from refund_void
  order by 1, 2;
end;
$$;

-- kernel.settlement_royalty_lines — 093:1136-1216 VERBATIM.
create or replace function kernel.settlement_royalty_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language plpgsql volatile security definer set search_path = ''
as $$
declare v_org uuid;
begin
  select st.org_id into v_org from venue.settlement st where st.settlement_id = p_settlement_id;
  if v_org is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_org::text));
  return query
  with s as (
    select st.settlement_id, st.org_id, st.venue_id, st.event_id, st.period_start, st.period_end, st.currency
      from venue.settlement st where st.settlement_id = p_settlement_id
  ),
  royalty as (
    select 'market_sale'::text as cause, ms.sale_id as cause_ref,
           ms.venue_royalty_minor::bigint as amount_minor, ms.currency, 'organization'::text as payee_kind, s.org_id as payee_id
      from s
      join market.market_sale ms on ms.terminal_state = 'completed' and ms.venue_royalty_minor is not null and ms.venue_royalty_minor > 0
      join kernel.tickets t on t.ticket_atom_id = ms.ticket_atom_id and t.org_id = s.org_id
      join catalog.event_session es on es.session_id = t.event_session_id
      join catalog.event e on e.event_id = es.event_id
     where ms.currency = s.currency
       and ((s.event_id is not null and e.event_id = s.event_id)
            or (s.event_id is null and e.venue_id = s.venue_id
                and (s.period_start is null or es.starts_at >= s.period_start)
                and (s.period_end is null or es.starts_at < s.period_end)))
       and not exists (select 1 from venue.settlement_line l where l.cause = 'market_sale' and l.cause_ref = ms.sale_id)
  ),
  cb_candidate as (
    select d.dispute_id, d.created_at, d.currency, s.org_id,
           d.amount_minor::bigint as disputed_minor,
           o.order_id, o.total_minor::bigint as face_minor,
           least(coalesce((select sum(r.amount_minor) from kernel.refund r
                            where r.payment_id = pn.payment_id and r.status = 'succeeded'), 0),
                 o.total_minor)::bigint as refund_exposure_minor,
           coalesce((select sum(-l2.amount_minor) from venue.settlement_line l2
                       join kernel.dispute_native d2 on d2.dispute_id = l2.cause_ref
                       join kernel.payment_native pn2 on pn2.payment_id = d2.payment_id
                      where l2.cause = 'chargeback' and pn2.order_id = o.order_id), 0)::bigint as prior_cb_minor
      from s
      join kernel.dispute_native d on d.status in ('lost','charge_refunded') and d.amount_minor > 0
      join kernel.payment_native pn on pn.payment_id = d.payment_id and pn.order_id is not null   -- E-94
      join venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id
     where d.currency = s.currency
       and not exists (select 1 from venue.settlement_line l where l.cause = 'chargeback' and l.cause_ref = d.dispute_id)
  ),
  cb_alloc as (
    select cb.dispute_id, cb.currency, cb.org_id,
           greatest(
             0,
               least(sum(cb.disputed_minor) over w,
                     greatest(0, cb.face_minor - cb.refund_exposure_minor - cb.prior_cb_minor))
             - least(sum(cb.disputed_minor) over w - cb.disputed_minor,
                     greatest(0, cb.face_minor - cb.refund_exposure_minor - cb.prior_cb_minor))
           )::bigint as debit_minor
      from cb_candidate cb
    window w as (partition by cb.order_id order by cb.created_at, cb.dispute_id
                 rows between unbounded preceding and current row)
  ),
  chargeback as (
    select 'chargeback'::text as cause, ca.dispute_id as cause_ref,
           (-ca.debit_minor)::bigint as amount_minor, ca.currency, 'organization'::text as payee_kind, ca.org_id as payee_id
      from cb_alloc ca
     where ca.debit_minor > 0
  )
  select * from royalty
  union all
  select * from chargeback
  order by 1, 2;
end;
$$;

-- kernel.close_settlement — 094:544-790 VERBATIM (the shortfall branch is
-- 093's `if v_net > 0` block plus the ONE 094 `elsif v_net < 0` INSERT; the
-- 097 shortfall-hold block is removed along with it).
create or replace function kernel.close_settlement(p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_s venue.settlement%rowtype; v_c kernel.settlement_line_candidate;
  v_gross bigint; v_fees bigint; v_refunds bigint; v_net bigint;
  v_payout_id uuid; v_ids uuid[] := '{}';
  v_held boolean := false; v_hold_reason text; v_hold_detail jsonb;
  v_maturity_verdict jsonb;
begin
  select * into v_s from venue.settlement where settlement_id = p_settlement_id for update;
  if not found then raise exception 'not_found: settlement %', p_settlement_id using errcode = 'P0002'; end if;
  if not ((kernel.has_venue_role(v_s.venue_id, array['venue_finance'])
           and (select v.org_id from catalog.venue v where v.venue_id = v_s.venue_id) = v_s.org_id)
          or kernel.has_org_role(v_s.org_id, array['org_finance'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: venue_finance / org_finance / platform only' using errcode = '42501';
  end if;
  if v_s.status <> 'open' then
    return jsonb_build_object('status','noop_replay','net_minor', v_s.net_minor,
      'payout_ids', (select coalesce(array_agg(payout_id),'{}') from kernel.payout
                      where cause='settlement' and cause_ref=p_settlement_id));
  end if;
  for v_c in select * from kernel.settlement_primary_lines(p_settlement_id)
             union all select * from kernel.settlement_royalty_lines(p_settlement_id)
             union all select * from kernel.settlement_commission_lines(p_settlement_id) loop
    if v_c.cause is not null then
      if v_c.currency is not null and v_c.currency <> v_s.currency then
        raise exception 'precondition_failed: candidate currency % differs from the settlement currency %', v_c.currency, v_s.currency
          using errcode = 'P0001';
      end if;
      insert into venue.settlement_line (settlement_id, cause, cause_ref, amount_minor, currency)
      values (p_settlement_id, v_c.cause, v_c.cause_ref, v_c.amount_minor::integer, v_s.currency)
      on conflict on constraint settlement_line_cause_uq do nothing;
    end if;
  end loop;
  if exists (select 1 from venue.settlement_line l where l.settlement_id = p_settlement_id and l.currency <> v_s.currency) then
    raise exception 'precondition_failed: settlement lines carry a currency other than the header''s' using errcode = 'P0001';
  end if;
  select coalesce(sum(amount_minor)  filter (where amount_minor > 0 and cause not in ('refund_void','chargeback')), 0),
         coalesce(sum(-amount_minor) filter (where amount_minor < 0 and cause not in ('refund_void','chargeback')), 0),
         coalesce(sum(-amount_minor) filter (where cause in ('refund_void','chargeback')), 0)
    into v_gross, v_fees, v_refunds from venue.settlement_line where settlement_id = p_settlement_id;
  v_net := v_gross - v_fees - v_refunds;
  if v_gross > 2147483647 or v_fees > 2147483647 or v_refunds > 2147483647
     or v_net > 2147483647 or v_net < -2147483648 then
    raise exception 'precondition_failed: settlement_amount_overflow — gross %, fees %, refunds %, net % exceed the int4 money columns (schema §3.13); settle this scope as narrower periods, or widen the columns (owner item)',
      v_gross, v_fees, v_refunds, v_net using errcode = 'P0001';
  end if;
  update venue.settlement
     set status='closed', gross_minor=v_gross::integer, fees_minor=v_fees::integer,
         refunds_minor=v_refunds::integer, net_minor=v_net::integer, updated_at=now()
   where settlement_id = p_settlement_id;
  if v_net > 0 then
    v_maturity_verdict := kernel.settlement_payout_maturity(p_settlement_id);
    v_hold_reason := v_maturity_verdict ->> 'hold_reason';
    v_held        := v_hold_reason is not null;
    v_hold_detail := coalesce(v_maturity_verdict -> 'detail', '{}'::jsonb);
    insert into kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, currency, status, idempotency_key,
                               hold_state, hold_reason_code, held_by, held_at)
    values ('organization', v_s.org_id, 'settlement', p_settlement_id, v_net::integer, v_s.currency, 'pending',
            'settlement:' || p_settlement_id::text,
            case when v_held then 'held' else 'none' end,
            v_hold_reason,
            null,
            case when v_held then now() else null end)
    on conflict (idempotency_key) do nothing
    returning payout_id into v_payout_id;
    if v_payout_id is not null then v_ids := array[v_payout_id]; end if;
  elsif v_net < 0 then
    if -v_net > 2147483647 then
      raise exception 'precondition_failed: settlement_shortfall_overflow — a shortfall of % minor units exceeds the int4 obligation magnitude; settle this scope as narrower periods (owner item)', -v_net
        using errcode = 'P0001';
    end if;
    perform kernel.record_organization_obligation(
      v_s.org_id, 'settlement_shortfall', p_settlement_id, null,
      (-v_net)::integer, v_s.currency, 'settlement_shortfall',
      coalesce(p_command_key, 'close') || ':shortfall');
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (auth.uid(), 'settlement.close', 'settlement', p_settlement_id, coalesce(p_command_key,'close'),
          jsonb_build_object('payout_hold', v_hold_reason, 'hold_predicates', v_hold_detail));
  return jsonb_build_object('status','ok','payout_ids', v_ids,
           'net_minor', (select net_minor from venue.settlement where settlement_id = p_settlement_id),
           'payout_hold', v_hold_reason,
           'payout_hold_detail', case when v_held then v_hold_detail else null end);
end;
$$;

-- kernel.settlement_payout_maturity — 093:2076-2170 VERBATIM.
create or replace function kernel.settlement_payout_maturity(p_settlement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_maturity     interval;
  v_unresolved   bigint  := 1;
  v_sess_n       bigint  := 0;
  v_sess_no_end  bigint  := 1;
  v_anchor       timestamptz;
  v_cancelled    boolean := true;
  v_refund_open  boolean := true;
  v_dispute_open boolean := true;
  v_reason       text;
begin
  begin
    v_maturity := (select (c.value #>> '{}')::interval
                     from catalog.platform_config c
                    where c.key = 'payout.settlement_maturity_interval'
                    order by c.version desc limit 1);
  exception when others then v_maturity := null;
  end;

  with cov as (select * from kernel.settlement_covered_payments(p_settlement_id)),
       cov_session as (select distinct c.session_id from cov c where c.session_id is not null)
  select
    (select count(*) from cov c where c.payment_id is null or c.session_id is null),
    (select count(*) from cov_session),
    (select count(*) from cov_session cs join catalog.event_session es on es.session_id = cs.session_id where es.ends_at is null),
    (select max(es.ends_at) from cov_session cs join catalog.event_session es on es.session_id = cs.session_id),
    (select exists (select 1 from cov_session cs
                      join catalog.event_session es on es.session_id = cs.session_id
                      join catalog.event e on e.event_id = es.event_id
                     where es.status = 'cancelled' or e.status = 'cancelled')),
    (select exists (select 1 from cov c join kernel.refund r on r.payment_id = c.payment_id
                     where r.status in ('pending','submitted'))),
    (select exists (select 1 from cov c join kernel.dispute_native d on d.payment_id = c.payment_id
                     where d.status in ('warning_needs_response','warning_under_review','needs_response','under_review')))
    into v_unresolved, v_sess_n, v_sess_no_end, v_anchor, v_cancelled, v_refund_open, v_dispute_open;

  v_reason := case
    when v_maturity is null                                    then 'unbounded_refund_exposure'
    when v_maturity < interval '0'                             then 'maturity_policy_invalid'
    when coalesce(v_unresolved, 1) > 0                         then 'covered_set_unresolvable'
    when coalesce(v_cancelled, true)                           then 'event_cancelled'
    when coalesce(v_sess_n, 0) = 0
      or coalesce(v_sess_no_end, 1) > 0
      or v_anchor is null                                      then 'maturity_instant_unknown'
    when now() < v_anchor + v_maturity                         then 'maturity_not_elapsed'
    when coalesce(v_refund_open, true)                         then 'refund_in_flight'
    when coalesce(v_dispute_open, true)                        then 'dispute_open'
    else null
  end;

  return jsonb_build_object(
    'hold_reason', v_reason,
    'detail', jsonb_build_object(
      'maturity_interval',  case when v_maturity is null then null else v_maturity::text end,
      'maturity_anchor',    v_anchor,
      'matures_at',         case when v_anchor is null or v_maturity is null then null else (v_anchor + v_maturity) end,
      'covered_sessions',   v_sess_n, 'sessions_without_end', v_sess_no_end,
      'unresolvable_lines', v_unresolved, 'event_cancelled', v_cancelled,
      'refund_in_flight',   v_refund_open, 'dispute_open', v_dispute_open));
end;
$$;

-- kernel.settlement_maturity_hold_codes — 095:458-478 VERBATIM.
create or replace function kernel.settlement_maturity_hold_codes()
returns text[]
language sql
immutable
security definer
set search_path = ''
as $$
  select array[
    'unbounded_refund_exposure',
    'maturity_policy_invalid',
    'covered_set_unresolvable',
    'event_cancelled',
    'maturity_instant_unknown',
    'maturity_not_elapsed',
    'refund_in_flight',
    'dispute_open'
  ]::text[];
$$;

comment on function kernel.settlement_maturity_hold_codes() is
  'The closed set of hold_reason_code values kernel.settlement_payout_maturity (093 slice 10m) can emit. The ONLY reasons kernel.retry_held_payout may clear. Every other hold — risk, probation, destination, unfunded commission, failed re-arm, reversed transfer — is released solely by kernel.release_payout.';

-- kernel.record_dispute_native — 088:758-867 VERBATIM.
create or replace function kernel.record_dispute_native(
  p_stripe_dispute_ref text, p_stripe_charge_ref text, p_stripe_pi_ref text, p_amount_minor integer, p_currency text,
  p_reason text, p_status text, p_evidence_due_at timestamptz, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_pay public.payments%rowtype; v_pn kernel.payment_native%rowtype; v_d kernel.dispute_native%rowtype;
  v_open boolean; v_atom record; v_row record; v_po record; v_held integer := 0; v_atoms integer := 0; v_skipped integer := 0;
  v_ccy text;
begin
  if p_stripe_dispute_ref is null or p_stripe_charge_ref is null or p_reason is null or p_command_key is null then
    raise exception 'invalid_input: dispute ref, charge ref, reason and command_key are required';
  end if;
  if p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
  end if;
  if p_status is null or p_status not in ('warning_needs_response','warning_under_review','warning_closed',
                                           'needs_response','under_review','won','lost','charge_refunded') then
    raise exception 'invalid_input: % is not a dispute status', coalesce(p_status,'<null>');
  end if;
  if p_amount_minor is null or p_amount_minor < 0 then raise exception 'invalid_input: amount_minor must be >= 0'; end if;
  v_ccy := upper(coalesce(p_currency, 'USD'));
  if v_ccy !~ '^[A-Z]{3}$' then raise exception 'invalid_input: currency must be a 3-letter ISO code'; end if;
  select * into v_d from kernel.dispute_native d where d.stripe_dispute_ref = p_stripe_dispute_ref for update;
  if found then
    return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id);
  end if;
  select * into v_pay from public.payments p where p.stripe_payment_intent_id = p_stripe_pi_ref;
  if not found then
    raise exception 'not_found: no payment for payment intent %', coalesce(p_stripe_pi_ref,'<null>') using errcode = 'P0002';
  end if;
  begin
    insert into kernel.dispute_native (stripe_dispute_ref, stripe_charge_ref, stripe_pi_ref, payment_id, amount_minor, currency,
                                       reason, evidence_due_at, status)
    values (p_stripe_dispute_ref, p_stripe_charge_ref, p_stripe_pi_ref, v_pay.id, p_amount_minor, v_ccy,
            p_reason, p_evidence_due_at, p_status)
    returning * into v_d;
  exception when unique_violation then
    select * into v_d from kernel.dispute_native d where d.stripe_dispute_ref = p_stripe_dispute_ref;
    return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id);
  end;
  v_open := p_status not in ('won','lost','warning_closed','charge_refunded');
  select * into v_pn from kernel.payment_native pn where pn.payment_id = v_pay.id;
  if v_open and found then
    for v_atom in
      select t.ticket_atom_id, t.event_session_id
        from kernel.tickets t
       where t.ticket_atom_id in (
               select l.ticket_atom_id from kernel.ticket_ownership_log l
                 join venue.order_item oi on oi.id = l.cause_ref
                where v_pn.order_id is not null and l.sequence = 1 and l.cause = 'issue' and oi.order_id = v_pn.order_id
               union
               select ms.ticket_atom_id from market.market_sale ms where v_pn.sale_id is not null and ms.sale_id = v_pn.sale_id)
       order by t.ticket_atom_id loop
      perform 1 from catalog.event_session s where s.session_id = v_atom.event_session_id for share;
      select t.state, t.resale_state, t.current_owner_id into v_row
        from kernel.tickets t where t.ticket_atom_id = v_atom.ticket_atom_id for update;
      if v_row.current_owner_id = v_pay.buyer_id and v_row.state in ('issued','active') and v_row.resale_state = 'none' then
        update kernel.tickets set resale_state = 'dispute_hold', updated_at = now()
         where ticket_atom_id = v_atom.ticket_atom_id;
        v_atoms := v_atoms + 1;
      else
        v_skipped := v_skipped + 1;
        insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
        values (v_sys, 'dispute.alert', 'ticket_atom', v_atom.ticket_atom_id,
                case when v_row.current_owner_id <> v_pay.buyer_id then 'custody_moved' else 'overlay_occupied' end,
                jsonb_build_object('dispute_id', v_d.dispute_id, 'resale_state', v_row.resale_state, 'state', v_row.state, 'audience', 'platform_risk'));
      end if;
    end loop;
    for v_po in
      select po.payout_id, po.payee_org_id, po.payee_identity_id, po.amount_minor from kernel.payout po
       where po.status in ('pending','submitted') and po.hold_state in ('none','probation_hold')
         and (   (v_pn.sale_id is not null and po.cause_ref = v_pn.sale_id)
              or po.cause_ref in (select sl.settlement_id from venue.settlement_line sl
                                   where sl.cause_ref = coalesce(v_pn.order_id, v_pn.sale_id)))
       order by po.payout_id for update loop
      update kernel.payout set hold_state = 'held', hold_reason_code = 'dispute', held_at = now(), held_by = null, updated_at = now()
       where payout_id = v_po.payout_id;
      v_held := v_held + 1;
      begin
        perform notify.emit_event('payout_on_hold', 'payout', v_po.payout_id, 'payout_on_hold:' || v_po.payout_id::text || ':' || v_d.dispute_id::text,
                  jsonb_build_object('dispute_id', v_d.dispute_id, 'reason', 'dispute', 'amount_minor', v_po.amount_minor));
      exception when others then null; end;
    end loop;
  elsif v_open then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_sys, 'dispute.alert', 'dispute_native', v_d.dispute_id, 'no_link',
            jsonb_build_object('payment_id', v_pay.id, 'audience', 'platform_risk'));
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (v_sys, 'dispute.record', 'dispute_native', v_d.dispute_id, p_command_key,
          jsonb_build_object('status', p_status, 'atoms_held', v_atoms, 'atoms_skipped', v_skipped, 'payouts_held', v_held,
                             'linked', (v_pn.id is not null)));
  return jsonb_build_object('status','ok','dispute_id', v_d.dispute_id, 'atoms_held', v_atoms, 'atoms_skipped', v_skipped,
                            'payouts_held', v_held, 'linked', (v_pn.id is not null));
end;
$$;

-- kernel.mark_dispute_state — 088:875-902 VERBATIM.
create or replace function kernel.mark_dispute_state(p_stripe_dispute_ref text, p_new_status text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_d kernel.dispute_native%rowtype; v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_terminal constant text[] := array['won','lost','warning_closed','charge_refunded'];
begin
  if p_new_status is null or p_new_status not in ('warning_needs_response','warning_under_review','warning_closed',
                                                   'needs_response','under_review','won','lost','charge_refunded') then
    raise exception 'invalid_input: % is not a dispute status', coalesce(p_new_status,'<null>');
  end if;
  select * into v_d from kernel.dispute_native d where d.stripe_dispute_ref = p_stripe_dispute_ref for update;
  if not found then raise exception 'not_found: dispute %', p_stripe_dispute_ref using errcode = 'P0002'; end if;
  if v_d.status = any(v_terminal) then
    if v_d.status = p_new_status then
      return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id,'dispute_status', v_d.status);
    end if;
    raise exception 'state_conflict: dispute % is terminal (%) — % refused', v_d.dispute_id, v_d.status, p_new_status;
  end if;
  if v_d.status = p_new_status then
    return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id,'dispute_status', v_d.status);
  end if;
  update kernel.dispute_native set status = p_new_status, updated_at = now() where dispute_id = v_d.dispute_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_sys, 'dispute.state_sync', 'dispute_native', v_d.dispute_id, coalesce(p_command_key,'state_sync'),
          jsonb_build_object('status', v_d.status), jsonb_build_object('status', p_new_status));
  return jsonb_build_object('status','ok','dispute_id', v_d.dispute_id,'dispute_status', p_new_status);
end;
$$;

-- (c) the column, LAST — guarded above to refuse while the table holds any row.
alter table kernel.organization_obligation drop column if exists venue_id;

commit;
