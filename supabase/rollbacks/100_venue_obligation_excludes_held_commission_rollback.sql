-- ============================================================================
-- 100_venue_obligation_excludes_held_commission_rollback.sql — REVERSES 100.
--
-- 100 is a body-only re-creation of two candidate seams
-- (kernel.settlement_primary_lines, kernel.settlement_royalty_lines) that cap a
-- post-payout reversal debit at face minus the still-held funded promoter
-- commission. This rollback restores both seams to their 097 bodies, which
-- REINTRODUCES the G4 overstatement (a fully-reversed commissioned order books
-- the venue an obligation of the full face rather than what the venue received).
-- Break-glass only; forward-fix instead.
--
-- No data guard is needed: this re-creates two read-only STABLE functions; it
-- drops no table, mutates no money row. 100 added no new object (converge_held_
-- commission was removed from 100's final design — see 100's header), so there
-- is nothing to DROP. The restored bodies are 097's verbatim.
-- ============================================================================
begin;

-- kernel.settlement_primary_lines — 097 Section 4 VERBATIM (093:435-560 base).
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
       and not exists (
             select 1 from kernel.refund r0 where r0.payment_id = pn.payment_id and r0.status in ('pending','submitted')
               and r0.amount_minor
                   + coalesce((select sum(r1.amount_minor) from kernel.refund r1
                                where r1.payment_id = pn.payment_id and r1.status = 'succeeded'), 0)
                   + coalesce((select sum(d1.amount_minor) from kernel.dispute_native d1
                                where d1.payment_id = pn.payment_id and d1.status in ('lost','charge_refunded')), 0)
                 <= (select p.total from public.payments p where p.id = pn.payment_id)
           )
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
       and not exists (select 1 from kernel.organization_obligation oo
                         where oo.origin_kind = 'unlined_reversal' and oo.origin_ref = r.refund_id)
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

-- kernel.settlement_royalty_lines — 097 Section 5 VERBATIM (093:1136-1216 base).
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
      join catalog.event_session es on es.session_id = o.event_session_id
      join catalog.event e on e.event_id = es.event_id and e.venue_id = s.venue_id
     where d.currency = s.currency
       and not exists (select 1 from venue.settlement_line l where l.cause = 'chargeback' and l.cause_ref = d.dispute_id)
       and not exists (
             select 1 from kernel.refund r0 where r0.payment_id = pn.payment_id and r0.status in ('pending','submitted')
               and r0.amount_minor
                   + coalesce((select sum(r1.amount_minor) from kernel.refund r1
                                where r1.payment_id = pn.payment_id and r1.status = 'succeeded'), 0)
                   + coalesce((select sum(d1.amount_minor) from kernel.dispute_native d1
                                where d1.payment_id = pn.payment_id and d1.status in ('lost','charge_refunded')), 0)
                 <= (select p.total from public.payments p where p.id = pn.payment_id)
           )
       and not exists (
             select 1 from kernel.organization_obligation oo
              where oo.origin_kind = 'unlined_reversal' and oo.origin_ref = d.dispute_id
           )
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


commit;
