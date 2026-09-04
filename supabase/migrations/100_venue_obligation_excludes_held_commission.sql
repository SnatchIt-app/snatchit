-- ============================================================================
-- 100_venue_obligation_excludes_held_commission.sql — the G4 economic-
-- consistency fix (venue debt must exclude money the venue never received).
--
-- ── WHAT THIS MIGRATION IS ──────────────────────────────────────────────────
-- TWO body-only re-creations, nothing else. No new object, no new column, no
-- new grant, no public-schema object — Gate-2 and the kernel function census
-- are UNCHANGED. Replay-safe (create or replace).
--   kernel.settlement_primary_lines  (093:435-560, 097 Section 4) — the
--     refund_void debit is capped at what the venue RECEIVED, i.e. face minus
--     the still-HELD funded promoter commission for the order.
--   kernel.settlement_royalty_lines  (093:1136-1216, 097 Section 5) — the
--     chargeback debit gets the SAME reduction.
--
-- ── THE DEFECT (owner G4, success conditions #6/#7; KC 2.i / KF P1-3) ────────
-- On a POST-PAYOUT reversal (chargeback or post-payout refund_void) of a
-- primary order that carried a FUNDED-BUT-HELD promoter commission (Option B:
-- the commission was funded by REDUCING the venue's distributable and never
-- left the platform), the settlement_shortfall organization obligation
-- overstated the venue's debt by that held commission. Canonical fixture:
-- face 10000, funded commission 1000 (bps 1000), venue paid 9000, full
-- reversal 10000 — today the chargeback lines at −10000, net −10000, obligation
-- 10000. WRONG: the venue only ever received 9000.
--
-- ── THE FIX, AND WHY IT IS COMPLETE ON ITS OWN ──────────────────────────────
-- The venue's obligation is DB-derived and now EXCLUDES the held commission:
-- the reversal debit is capped at `greatest(0, face − refund_exposure −
-- prior_cb − held_commission_for_order)`, where held_commission_for_order is
-- Σ kernel.payout.amount_minor over the order's attribution(s) with
-- cause='promoter_commission', status='pending', hold_state='held'. For the
-- canonical fixture: 10000 − 0 − 0 − 1000 = 9000 ⇒ chargeback line −9000 ⇒
-- net −9000 ⇒ obligation 9000. CORRECT, and conservation closes from LEDGER
-- ROWS ONLY (no hand-derived quantity) — which is what lets Gate-M C31 stay
-- deferred. A5's face cap did not contemplate an Option-B funded commission;
-- the venue's real receipt is face minus the commission that reduced its
-- distributable, and that is its obligation. The held-commission slice was
-- returned to the buyer as part of the chargeback, so it is neither double-
-- counted here nor turned into platform revenue.
--
-- ── WHAT IS DELIBERATELY NOT DONE HERE (specified, deferred — G4) ────────────
-- This migration does NOT touch the held commission PAYOUT itself. Converging
-- that held payout down to its pro-rata surviving amount is a SEPARATE concern
-- that is NOT required for launch: promoter payout is DARK (no commission
-- payout ever leaves pending/held), and G4 rules that "before the FIRST future
-- promoter commission payout, a separate owner ruling and architecture for
-- paid-commission recovery/receivable is required." The held payout therefore
-- remains at its funded amount (dark, never paying) and its convergence to the
-- surviving amount is SPECIFIED for that future ruling (PFA-PT-5). An earlier
-- draft of this migration voided-and-re-minted the held payout inside
-- close_settlement; that introduced a SECOND `promoter_commission` payout row
-- per attribution, which (a) broke the single-minter fence (155 B18), (b) broke
-- single-row `cause_ref` lookups (164), and (c) made every "latest payout by
-- created_at" reader — including the production promoter-status projection at
-- 090:1325 — nondeterministic (two rows share the transaction-frozen now()).
-- The obligation fix above stands alone and needs none of that: it changes only
-- the two candidate seams, never a payout row, never close_settlement.
--
-- ── SYMMETRY (refund_void as well as chargeback) ────────────────────────────
-- A post-payout refund of a commissioned, already-paid-out order overstates the
-- venue debt the same way, so settlement_primary_lines' refund_void cap gets the
-- identical held-commission reduction. A PRE-payout / same-close refund is
-- unaffected: the held commission is funded in that same close (098) and there
-- is no post-payout held excess — the seams run before any convergence and the
-- reduction reads the commission as it stands, so a same-close funding nets to
-- the correct number with no special case.
--
-- Every other line of both seams — the royalty arm, refund seniority, the
-- cumulative-cap window, the E-94 boundary, 097's venue ring-fence, deferral
-- mirror and unlined fence, VOLATILE, the advisory lock, the order by — is
-- 097's text unchanged. The seams remain STABLE candidate emitters that only
-- READ the held commission; they mutate nothing. close_settlement (097) is not
-- re-created; it books −net from the reduced lines, so record_organization_
-- obligation's `amount = -net` invariant is preserved and now correct.
-- ============================================================================

begin;

-- ============================================================================
-- SECTION 1 — kernel.settlement_primary_lines (093:435-560, 097 Section 4)
--   BODY ONLY. ONE change from 097's text: refund_candidate gains
--   held_commission_minor (the order's live, unconverged held
--   promoter_commission payout total) and refund_alloc's cap is reduced by
--   it, mirroring Section 2's chargeback-arm change below byte-for-byte in
--   shape. Everything else — scoped_order, the 097 "could still succeed"
--   deferral, primary_sale, order_prior_debit, refund_prior, the
--   unlined-reversal fence, the trailing union/order by, the E-104 lock,
--   VOLATILE, the currency filters — is 097's text unchanged.
-- ============================================================================
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
       -- 097 (KC P0-2 O4): the "could still succeed" deferral, mirrored
       -- verbatim into settlement_royalty_lines' cb_candidate below — copy
       -- this exact fragment there and nowhere else, it is not restated by
       -- accident.
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
           coalesce(rp.prior_debit_minor, 0) as prior_debit_minor,
           -- 100 (G4 symmetry, KC §2.i): the order's own STILL-LIVE (never
           -- converged) held funded promoter_commission total — see Section
           -- 2's identical fragment and the file header for why this is 0
           -- for every same-close (pre-payout) refund by construction (branch
           -- 1 runs before settlement_commission_lines' branch 3), and
           -- non-zero only for a POST-payout refund on an order whose
           -- commission was funded and held in an earlier, separate close.
           coalesce((select sum(po.amount_minor) from kernel.payout po
                       join venue.attribution a2 on a2.id = po.cause_ref
                      where po.cause = 'promoter_commission' and po.status = 'pending' and po.hold_state = 'held'
                        and coalesce(po.hold_reason_code, '') <> 'commission_converged'
                        and a2.order_id = so.order_id), 0)::bigint as held_commission_minor
      from scoped_order so
      join kernel.payment_native pn on pn.order_id = so.order_id
      join kernel.refund r on r.payment_id = pn.payment_id and r.status = 'succeeded'
      left join refund_prior rp on rp.order_id = so.order_id
     where r.currency = so.currency
       and not exists (select 1 from venue.settlement_line l
                        where l.cause = 'refund_void' and l.cause_ref = r.refund_id)
       -- 097 (KC P0-2 symmetry): the bidirectional fence, mirrored from the
       -- chargeback arm below — a refund already booked as an unlined_
       -- reversal obligation is never also lined here.
       and not exists (select 1 from kernel.organization_obligation oo
                         where oo.origin_kind = 'unlined_reversal' and oo.origin_ref = r.refund_id)
  ),
  refund_alloc as (
    select rc.refund_id, rc.currency, rc.org_id,
           greatest(
             0,
               least(rc.prior_debit_minor + sum(rc.refund_minor) over w,
                     greatest(0, rc.face_minor - rc.held_commission_minor))
             - least(rc.prior_debit_minor + sum(rc.refund_minor) over w - rc.refund_minor,
                     greatest(0, rc.face_minor - rc.held_commission_minor))
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

-- ============================================================================
-- SECTION 2 — kernel.settlement_royalty_lines (093:1136-1216, 097 Section 5)
--   BODY ONLY. The royalty arm is untouched. cb_candidate gains
--   held_commission_minor (the disputed order's live, unconverged held
--   funded promoter_commission total, read the SAME way Section 1's
--   refund_candidate reads it) and cb_alloc's cap is reduced by it — the
--   fourth subtracted term alongside face, refund_exposure and prior_cb.
--   Everything else — the 097 venue ring-fence, the refund-deferral mirror,
--   the unlined fence, the royalty arm, VOLATILE, the advisory lock, order
--   by — is 097's text unchanged.
-- ============================================================================
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
                      where l2.cause = 'chargeback' and pn2.order_id = o.order_id), 0)::bigint as prior_cb_minor,
           -- 100 (G4, KC §2.i): the STILL-LIVE (never converged) held funded
           -- promoter_commission total for this order — the venue's real
           -- receipt is face minus the commission that reduced its
           -- distributable and never left the platform; charging back that
           -- portion would claw back money the venue was never paid. The
           -- held slice itself is separately voided/converged by
           -- the venue's obligation (100 books the reduced net). The held
           -- commission — it is not double-counted here and does not become
           -- platform revenue; the held-commission PAYOUT convergence is
           -- cap did not contemplate Option-B funded commission — filed as
           -- PFA-PT-5 (docs/architecture/_governance/POST_FREEZE_
           -- AMENDMENTS.md), PENDING OWNER SIGNATURE.
           coalesce((select sum(po.amount_minor) from kernel.payout po
                       join venue.attribution a2 on a2.id = po.cause_ref
                      where po.cause = 'promoter_commission' and po.status = 'pending' and po.hold_state = 'held'
                        and coalesce(po.hold_reason_code, '') <> 'commission_converged'
                        and a2.order_id = o.order_id), 0)::bigint as held_commission_minor
      from s
      join kernel.dispute_native d on d.status in ('lost','charge_refunded') and d.amount_minor > 0
      join kernel.payment_native pn on pn.payment_id = d.payment_id and pn.order_id is not null   -- E-94
      join venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id
      -- 097 (a): the ring-fence — the disputed order's OWN venue, not any
      -- venue of the org (KG P1 prototype, executed clean against 817/817).
      join catalog.event_session es on es.session_id = o.event_session_id
      join catalog.event e on e.event_id = es.event_id and e.venue_id = s.venue_id
     where d.currency = s.currency
       and not exists (select 1 from venue.settlement_line l where l.cause = 'chargeback' and l.cause_ref = d.dispute_id)
       -- 097 (b): the refund-deferral mirror — identical to Section 1's
       -- scoped_order fragment. A chargeback on an order whose refund could
       -- still succeed never lines alone; credit and debit land together.
       and not exists (
             select 1 from kernel.refund r0 where r0.payment_id = pn.payment_id and r0.status in ('pending','submitted')
               and r0.amount_minor
                   + coalesce((select sum(r1.amount_minor) from kernel.refund r1
                                where r1.payment_id = pn.payment_id and r1.status = 'succeeded'), 0)
                   + coalesce((select sum(d1.amount_minor) from kernel.dispute_native d1
                                where d1.payment_id = pn.payment_id and d1.status in ('lost','charge_refunded')), 0)
                 <= (select p.total from public.payments p where p.id = pn.payment_id)
           )
       -- 097 (c): the bidirectional fence — a loss already booked as an
       -- unlined_reversal obligation is never also lined here. Section 3's
       -- guard already refuses the reverse (booking an obligation over an
       -- existing line); this is the other half.
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
                     greatest(0, cb.face_minor - cb.refund_exposure_minor - cb.prior_cb_minor - cb.held_commission_minor))
             - least(sum(cb.disputed_minor) over w - cb.disputed_minor,
                     greatest(0, cb.face_minor - cb.refund_exposure_minor - cb.prior_cb_minor - cb.held_commission_minor))
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
