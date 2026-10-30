-- ============================================================================
-- 097_settlement_scope_and_shortfall.sql — the chargeback arm stops netting
-- across venues, a shortfall stops being booked ahead of the money, and a
-- loss stops being bookable twice.
--
-- WHAT THIS MIGRATION IS. Nine body-only re-creations and one column, closing
-- the seam-level defects docs/phase2/_impl/KC_chargeback_accounting.md,
-- KG_cross_venue_isolation.md, KB_dispute_db_mapping.md, KD_obligation_
-- recovery.md §4.4 and KH_webhook_routing_idempotency.md §3 P1-6 proved by
-- execution against a fresh 000-096 replay, as fixed by the orchestrator's
-- DESIGN_097_099 memo, section M2. Where this file and a report disagree,
-- the memo wins and docs/phase2/_impl/KM2_097_implementation.md says so.
--
-- THE FOUR DEFECTS, EACH PROVED BY EXECUTION BEFORE IT WAS CLOSED.
--
--   1. CROSS-VENUE NETTING BY DEFAULT (KG P0-1/P0-2). kernel.settlement_
--      royalty_lines' chargeback arm (093:1136-1219, cb_candidate at
--      093:1169-1190) scopes the disputed order by `o.org_id = s.org_id`
--      ONLY — no join to the order's own session/event/venue. Executed
--      (KG V1/V2/V4): Venue A owes 50000, Venue B earns 100000; Venue B's
--      period- or event-scoped settlement absorbs A's whole debt, mints B a
--      100000 payout, books ZERO rows in kernel.organization_obligation, and
--      names venue A nowhere. When B's own revenue is smaller than the
--      foreign debt (KG V4) the RESIDUAL is booked as B's OWN shortfall — the
--      obligation's origin_ref then resolves to the wrong venue (KD §2.5/
--      P1-5). This is exactly the outcome the owner ruled out (brief §3/§27:
--      "Venue A's debt must not silently consume Venue B's payout"). Closed
--      by a ring-fence: cb_candidate now joins the disputed order to its own
--      catalog.event and requires `e.venue_id = s.venue_id` — the same
--      predicate the royalty arm two CTEs above it, and settlement_
--      primary_lines' scoped_order, already carry. Grain-agnostic by the
--      owner's own wording ("originating venue", not "originating event" —
--      KG V10, option B): an event-scoped settlement at venue X may still
--      absorb a chargeback from a DIFFERENT event at venue X.
--
--   2. A CHARGEBACK IS BOOKED AHEAD OF A REFUND THAT COULD STILL REVERSE IT
--      (KC P0-2, 2.d-i). settlement_primary_lines defers an order WHOLE while
--      a refund on it is pending/submitted (093:471-479) — but the
--      chargeback arm carried NO symmetric deferral, so a close can book
--      `chargeback -19000` while the matching `primary_sale +19000` sits
--      deferred behind a refund the executor's own Σ-guard (refund-execute/
--      executor.ts:276-285) will refuse forever once the dispute is counted
--      in it (093:1061). Executed: a venue that was PAID ZERO ends up owing
--      19000. Closed by mirroring 093:477-479's shape on BOTH debit arms with
--      the "could still succeed" form: a pending/submitted refund defers only
--      while `refund.amount_minor + Σ succeeded refunds + Σ lost/charge_
--      refunded dispute amounts` is still ≤ the payment's total — the exact
--      arithmetic refund-execute's Σ-guard evaluates, so a refund the
--      executor can never accept does not defer anything.
--
--   3. `unlined_reversal` IS FREE-AMOUNT, PER-DISPUTE-GUARDED, AND CAN COLLIDE
--      WITH THE CHARGEBACK ARM'S OWN NETTING (KC P1-2, 2.e/2.g/2.U; KD §4.4).
--      094's guard (094:387-392) only asks "does THIS origin already carry a
--      line" — a loss the chargeback arm already absorbed via `refund_void`
--      seniority (KC 2.e), or capped away by a prior dispute on the same
--      order (KC 2.g), or booked before the org ever opens another
--      settlement (KC 2.U), still passes it, and the amount is whatever the
--      caller types — uncapped, and (2.U) inclusive of the platform's own
--      fee slice. Executed: outstanding 42000 against a venue paid 19000 for
--      ONE loss. Closed by turning the origin into a FENCED, DERIVED fact:
--      the origin must be a real adverse fact (a lost/charge_refunded
--      dispute or a succeeded refund); the order it resolves to must have
--      been PAID OUT (a settlement whose payout already reached paid or
--      reversed — G5's "durable record of POST-PAYOUT debt", not post-close
--      residue); the amount is derived from the same per-order headroom the
--      seams themselves compute, never caller-priced; and the chargeback and
--      refund_void arms both now refuse to line an origin that already
--      carries an unlined_reversal row (094's guard already refuses the
--      reverse) — one loss, one origin, by construction in both directions.
--
--   4. A LOST/CHARGE-REFUNDED DISPUTE NEVER HOLDS THE PENDING PAYOUT OF THE
--      SAME ORDER (KB P0-1, KC 2.c-ii/2.c-v). kernel.record_dispute_native
--      freezes a payout only while the dispute is OPEN (088:804); kernel.
--      settlement_payout_maturity's `dispute_open` predicate counts only the
--      four open statuses (093:2130) — a `lost` dispute holds NOTHING.
--      Executed (KC 2.c-ii): a venue's own 19000 payout stays fully
--      execution_eligible after that same order's dispute is lost and the
--      matching 19000 `settlement_shortfall` is booked — the org shows
--      19000 outstanding while its own 19000 sits payable. Closed by a NINTH
--      settlement_payout_maturity predicate, `dispute_unabsorbed`: hold while
--      any covered payment carries a lost/charge_refunded dispute that no
--      chargeback line and no unlined_reversal obligation has yet absorbed.
--
-- A FIFTH, SMALLER CLOSURE RIDES ALONG (KC P1-1 O7 / KD P1-3, "is a shortfall
--   whose covered payout is unpaid a debt at all"): close_settlement now
--   HOLDS — never nets, never pays, never releases — this org's OTHER
--   pending settlement payouts at the SAME originating venue the instant it
--   books a shortfall there, under a NEW hold_reason_code, 'shortfall_pending',
--   that is deliberately NOT added to kernel.settlement_maturity_hold_codes()
--   (095) — so kernel.retry_held_payout cannot self-clear it; only
--   kernel.release_payout (platform_risk/platform_admin) can. This makes the
--   coexistence KD §2.7 P-1 measured (an outstanding debt AND an unpaid,
--   held-nothing payout, at once) at least VISIBLE and un-executable at the
--   SAME venue, without deciding whether the debt nets against it (an owner
--   item — KD §4.3, recorded, not decided here).
--
-- A SIXTH CLOSURE fences the dispute writers themselves (KB P1-1/P2-2/P2-3):
--   kernel.record_dispute_native now refuses a payment that is not on the
--   native rail (mode <> 'native_primary' and no payment_native.sale_id
--   link — KB A2's legacy leak), refuses empty-string refs/reason (KB A12),
--   and AUDITS (never refuses) a replay that disagrees with what is already
--   recorded (KB A5) and a currency that disagrees with the order's own
--   currency (KB A4). kernel.mark_dispute_state now requires the same
--   command_key shape record_dispute_native already enforces (KB A8b).
--
-- WHAT THIS FILE IS NOT.
--   - It does NOT add cross-venue netting of any kind, does not add an
--     'offset_settlement' obligation source (no producer — 094:198-200's own
--     rule), does not collect organization debt, and does not release,
--     unhold or advance any payout other than the two new hold writes named
--     above. G4's "commission stays HELD" is untouched — no promoter payout,
--     no promoter hold change, no commission line (that is 098's remit).
--   - It does NOT open a platform arm on venue.open_settlement (KG option C /
--     KC 4.1 O3) — a dormant venue whose chargeback the ring-fence can no
--     longer offer to a sibling stays unlined until it opens its own
--     settlement or an operator books an unlined_reversal against it. That
--     stranding is an OWNER ITEM (KG §5.3, KD §5.2/§5.3), recorded, not
--     decided here.
--   - It does NOT touch the WON-dispute release path (KB P1-2, parked
--     PFA-31), the freeze-before-finalize gap (KB P1-3), the submitted-payout
--     freeze strand (KB P1-4), the 'prevented' status gap (KB P0-2), the
--     dispute_native status CHECK, or resolve_dispute_native.
--   - It does NOT book unlined_reversal from the webhook (KH P1-6): no
--     TypeScript caller of any organization_obligation verb exists after
--     this file either; the chargeback line arm at the next close remains
--     the PRIMARY producer, and this migration only fences the origin the
--     operator-only verb already had.
--   - It does NOT widen kernel.payout.status, kernel.dispute_native.status,
--     or kernel.refund.status; does not touch mark_payout_transfer_state,
--     request_org_payout, get_payout_execution_context, hold_payout_
--     transfer_reversed, kernel.payout_reversal or kernel.organization_
--     obligation_recovery (096's objects — untouched, unread).
--
-- OBJECTS RE-CREATED, BODY-ONLY, EACH DIFF NAMED IN ITS OWN SECTION BELOW:
--   kernel.settlement_royalty_lines      (093:1136-1216)
--   kernel.settlement_primary_lines      (093:435-560)
--   kernel.record_organization_obligation(094:320-413)
--   kernel.organization_obligation_guard (094:260-293)
--   kernel.close_settlement              (094:544-790)
--   kernel.settlement_payout_maturity    (093:2076-2170)
--   kernel.settlement_maturity_hold_codes(095:458-478)
--   kernel.record_dispute_native         (088:758-867)
--   kernel.mark_dispute_state            (088:875-902)
-- PLUS ONE COLUMN: kernel.organization_obligation.venue_id (KG (ii) / KD
--   §4.4 — the venue a debit line's ORIGIN resolves to; NOT the settlement
--   that absorbed it, which after the ring-fence are the same venue by
--   construction for settlement_shortfall, and were always independently
--   derivable for unlined_reversal).
--
-- GRANTS: NOT TOUCHED ANYWHERE IN THIS FILE. `create or replace function`
--   preserves the ACL of every re-created function (087 PART 8 / 093:561 /
--   094 J7-5 discipline); re-asserting a grant that is not changing would be
--   a second source of truth for it. The new column carries no privilege of
--   its own — kernel.organization_obligation is REVOKE ALL at the table
--   level (094 J7-1), which already covers every column, present or future.
--
-- GATE-2 IS UNCHANGED. No table is created (one column is added to an
--   existing one), no function is created (nine are re-created under their
--   existing signatures), no trigger is created (organization_obligation_
--   guard's trigger already exists and is re-bound to the same function OID
--   by CREATE OR REPLACE), no policy is added or removed.
--
-- ONE TRANSACTION. REPLAY-SAFE (`create or replace`, `add column if not
--   exists`). 093/094/095/096 are immutable and are NOT edited by this file.
-- ============================================================================
begin;

set local lock_timeout = '3s';

-- ============================================================================
-- SECTION 1 — kernel.organization_obligation.venue_id (KG (ii), KD §4.4).
--   Nullable: no backfill exists (094 is unapplied; venue.settlement_line is
--   empty in production, 093:580-582) and neither origin can leave it NULL
--   once Section 3 below derives it on every write, but the column itself
--   carries no NOT NULL — that is a property of the writer, not the storage.
-- ============================================================================
alter table kernel.organization_obligation
  add column if not exists venue_id uuid references catalog.venue(venue_id) on delete restrict;

-- ============================================================================
-- SECTION 2 — kernel.organization_obligation_guard() (094:260-293) BODY ONLY.
--   ONE addition to the write-once identity list: venue_id. Everything else —
--   DELETE refusal, the other five write-once columns, the forward-only
--   status transition, the terminal-exclusivity check — is 094's text
--   unchanged.
-- ============================================================================
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
     -- 097: the origin venue is derived once, at record time, from the same
     -- immutable facts (origin_kind, origin_ref) that are already write-once
     -- above — rewriting it would restate a booked fact exactly as rewriting
     -- the amount would.
     or new.venue_id    is distinct from old.venue_id
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

-- ============================================================================
-- SECTION 3 — kernel.record_organization_obligation (094:320-413) BODY ONLY.
--   settlement_shortfall: 094's checks unchanged; ADDS venue_id := the
--   settlement's own venue_id (after Section 5's ring-fence, every debit line
--   a header carries is that venue's, so the header's venue IS the origin's).
--   unlined_reversal: REPLACED. 094's branch was one guard (origin not
--   already lined) and a caller-chosen amount. This branch now: resolves the
--   origin to a real adverse fact; refuses a resale-rail (sale_id) origin;
--   requires the order to belong to p_org_id; requires POST-PAYOUT proof;
--   DERIVES the amount from the order's own ledger, never the caller's
--   number; and derives venue_id from the order's own event. The existing
--   already-lined guard is kept, verbatim, unmoved.
-- ============================================================================
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
  v_venue_id uuid;
  -- 097 unlined_reversal fence — origin resolution and derivation locals.
  v_d              kernel.dispute_native%rowtype;
  v_r              kernel.refund%rowtype;
  v_dispute_found  boolean;
  v_refund_found   boolean;
  v_pn             kernel.payment_native%rowtype;
  v_order          venue."order"%rowtype;
  v_origin_amt     bigint;
  v_exposure       bigint;
  v_prior_cb       bigint;
  v_prior_rv       bigint;
  v_prior_unlined  bigint;
  v_derived        bigint;
  v_paid_out       boolean;
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
    v_venue_id := v_s.venue_id;
  else
    -- unlined_reversal — 097 FENCE (KC P1-2/2.U, KD §4.4, KG (ii)).
    -- Kept verbatim: does THIS origin already carry a chargeback/refund_void
    -- line anywhere. The shipped netting already offered to recover it.
    if exists (select 1 from venue.settlement_line l
                where l.cause in ('chargeback','refund_void') and l.cause_ref = p_origin_ref) then
      raise exception 'precondition_failed: origin % is already lined — netting has it, booking it here would double-count', p_origin_ref
        using errcode = 'P0001';
    end if;

    -- resolve the origin to a real adverse fact — a lost/charge_refunded
    -- dispute, or a succeeded refund. Anything else is not a loss.
    select * into v_d from kernel.dispute_native where dispute_id = p_origin_ref and status in ('lost','charge_refunded');
    v_dispute_found := found;
    if not v_dispute_found then
      select * into v_r from kernel.refund where refund_id = p_origin_ref and status = 'succeeded';
      v_refund_found := found;
    else
      v_refund_found := false;
    end if;
    if not v_dispute_found and not v_refund_found then
      raise exception 'not_found: unlined origin % is neither a lost/charge_refunded dispute nor a succeeded refund', p_origin_ref
        using errcode = 'P0002';
    end if;

    if v_dispute_found then
      v_origin_amt := v_d.amount_minor;
      select * into v_pn from kernel.payment_native where payment_id = v_d.payment_id;
    else
      v_origin_amt := v_r.amount_minor;
      select * into v_pn from kernel.payment_native where payment_id = v_r.payment_id;
    end if;
    if not found then
      raise exception 'not_found: unlined origin % has no linked order or sale', p_origin_ref using errcode = 'P0002';
    end if;
    -- E-94's boundary, applied here too: a resale-rail (sale_id) origin is not
    -- an org-side sale and this branch has no headroom model for it.
    if v_pn.order_id is null then
      raise exception 'precondition_failed: unlined_reversal_sale_arm_unsupported — origin % is a resale-rail fact', p_origin_ref
        using errcode = 'P0001';
    end if;

    select * into v_order from venue."order" where order_id = v_pn.order_id;
    if not found then
      raise exception 'not_found: order % for unlined origin %', v_pn.order_id, p_origin_ref using errcode = 'P0002';
    end if;
    if v_order.org_id <> p_org_id then
      raise exception 'precondition_failed: order % belongs to another org', v_pn.order_id using errcode = 'P0001';
    end if;

    -- POST-PAYOUT PROOF (G5: the durable record of POST-PAYOUT debt, not
    -- post-close residue — KD P1-3/2.7). The order's credit line must sit in
    -- a settlement whose payout actually left the platform or came back.
    select exists (
      select 1 from venue.settlement_line l
        join kernel.payout po on po.cause = 'settlement' and po.cause_ref = l.settlement_id
       where l.cause = 'primary_sale' and l.cause_ref = v_order.order_id
         and po.status in ('paid','reversed')
    ) into v_paid_out;
    if not v_paid_out then
      raise exception 'precondition_failed: order_not_paid_out — a loss on money the organization never received is not a debt'
        using errcode = 'P0001';
    end if;

    -- DERIVE THE AMOUNT — never caller-priced. The same per-order headroom
    -- Section 5's cb_candidate and Section 4's refund_candidate compute: face,
    -- minus what already left the order's pool through EITHER debit cause in
    -- ANY settlement, minus this SAME order's OTHER unlined_reversal rows (an
    -- order can carry more than one adverse fact; each is fenced against the
    -- others so the pool is never drawn down twice).
    v_exposure := case when v_dispute_found then
                    coalesce((select sum(r2.amount_minor) from kernel.refund r2
                               where r2.payment_id = v_pn.payment_id and r2.status = 'succeeded'), 0)
                  else
                    v_r.amount_minor   -- the refund IS the amount; not also summed via the branch above
                  end;
    v_prior_cb := coalesce((select sum(-l.amount_minor) from venue.settlement_line l
                              join kernel.dispute_native d2 on d2.dispute_id = l.cause_ref
                              join kernel.payment_native pn2 on pn2.payment_id = d2.payment_id
                             where l.cause = 'chargeback' and pn2.order_id = v_order.order_id), 0);
    v_prior_rv := coalesce((select sum(-l.amount_minor) from venue.settlement_line l
                              join kernel.refund r3 on r3.refund_id = l.cause_ref
                              join kernel.payment_native pn3 on pn3.payment_id = r3.payment_id
                             where l.cause = 'refund_void' and pn3.order_id = v_order.order_id), 0);
    v_prior_unlined := coalesce((select sum(oo.amount_minor) from kernel.organization_obligation oo
                                   where oo.origin_kind = 'unlined_reversal'
                                     and oo.origin_ref <> p_origin_ref
                                     and oo.origin_ref in (
                                       select d3.dispute_id from kernel.dispute_native d3 where d3.payment_id = v_pn.payment_id
                                       union all
                                       select r4.refund_id from kernel.refund r4 where r4.payment_id = v_pn.payment_id
                                     )), 0);
    v_derived := least(v_origin_amt,
                        greatest(0, v_order.total_minor::bigint - v_exposure - v_prior_cb - v_prior_rv - v_prior_unlined));
    if v_derived = 0 then
      raise exception 'precondition_failed: no_headroom — origin % has no unlined face-value exposure left on order %', p_origin_ref, v_order.order_id
        using errcode = 'P0001';
    end if;
    if p_amount_minor <> v_derived then
      raise exception 'precondition_failed: amount % is not the ledger-derived loss % for origin %', p_amount_minor, v_derived, p_origin_ref
        using errcode = 'P0001';
    end if;
    if v_ccy <> v_order.currency then
      raise exception 'precondition_failed: currency % differs from the order currency %', v_ccy, v_order.currency
        using errcode = 'P0001';
    end if;

    select e.venue_id into v_venue_id
      from catalog.event_session es join catalog.event e on e.event_id = es.event_id
     where es.session_id = v_order.event_session_id;
  end if;

  insert into kernel.organization_obligation
         (org_id, origin_kind, origin_ref, stripe_dispute_ref, amount_minor, currency, venue_id)
  values (p_org_id, p_origin_kind, p_origin_ref, p_stripe_dispute_ref, p_amount_minor, v_ccy, v_venue_id)
  on conflict on constraint organization_obligation_origin_uq do nothing
  returning obligation_id into v_id;
  if v_id is null then
    select o.obligation_id into v_id from kernel.organization_obligation o
     where o.origin_kind = p_origin_kind and o.origin_ref = p_origin_ref;
    return jsonb_build_object('status','noop_replay','obligation_id', v_id);
  end if;
  -- 097 (KD P2-2): the audit row now carries the number, not just the fact
  -- that a debt was recorded.
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'org_obligation.record', 'org_obligation',
          v_id, coalesce(p_reason_code, p_origin_kind),
          jsonb_build_object('amount_minor', p_amount_minor, 'currency', v_ccy, 'origin_ref', p_origin_ref, 'venue_id', v_venue_id));
  return jsonb_build_object('status','ok','obligation_id', v_id, 'amount_minor', p_amount_minor, 'currency', v_ccy, 'venue_id', v_venue_id);
end;
$$;

-- ============================================================================
-- SECTION 4 — kernel.settlement_primary_lines (093:435-560) BODY ONLY.
--   TWO changes, both in the debit (credit-deferral / debit-fence) shape:
--     (a) scoped_order's in-flight-refund deferral (093:471-479) is REPLACED
--         with the "could still succeed" form (KC 4.2 O4): a pending/
--         submitted refund defers the order only while it, plus every
--         already-succeeded refund, plus every lost/charge_refunded dispute
--         amount on the SAME payment, could still sum to at most the
--         payment's own total — the exact arithmetic refund-execute's
--         Σ-guard (executor.ts:276-285) evaluates. A refund the executor can
--         never accept no longer defers a venue's unrelated revenue forever.
--     (b) refund_candidate (093:515-531) gains the unlined-reversal fence:
--         a refund already booked as an unlined_reversal obligation is never
--         also lined here (Section 3's guard already refuses the reverse).
--   Everything else — primary_sale, order_prior_debit, refund_prior,
--   refund_alloc, refund_void, the trailing union/order by — is 093's text
--   unchanged, including the E-104 lock, VOLATILE, and the currency filters.
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
           coalesce(rp.prior_debit_minor, 0) as prior_debit_minor
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

-- ============================================================================
-- SECTION 5 — kernel.settlement_royalty_lines (093:1136-1216) BODY ONLY.
--   The royalty arm is untouched (093's own attestation: byte-identical from
--   088:336-350). The chargeback arm (cb_candidate, 093:1169-1190) gets
--   THREE additions:
--     (a) THE VENUE RING-FENCE (KG P0-1, option B): join the disputed order to
--         its own event and require e.venue_id = s.venue_id.
--     (b) THE REFUND-DEFERRAL MIRROR (KC P0-2): the identical "could still
--         succeed" fragment from Section 4's scoped_order.
--     (c) THE UNLINED FENCE (KC P1-2): a dispute already booked as an
--         unlined_reversal obligation is never also lined here.
--   The header comment 093 carried at 093:1130-1133 ("the deliberate absence
--   of a scope predicate on the chargeback arm... not 093's to change") is
--   SUPERSEDED by owner direction (G5: recovery source = originating venue;
--   brief §3/§27) — recorded here rather than left to contradict the code.
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
                      where l2.cause = 'chargeback' and pn2.order_id = o.order_id), 0)::bigint as prior_cb_minor
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
       -- 097 (b): the refund-deferral mirror — identical to Section 4's
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

-- ============================================================================
-- SECTION 6 — kernel.settlement_maturity_hold_codes() (095:458-478) BODY ONLY.
--   Adds the ninth code, 'dispute_unabsorbed' (Section 7). Deliberately does
--   NOT add 'shortfall_pending' (Section 8's close_settlement hold) — that
--   hold is a RISK-class hold (its own writer's decision, not a re-derivable
--   maturity predicate) and is released only by kernel.release_payout, never
--   self-clearable through kernel.retry_held_payout.
-- ============================================================================
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
    'dispute_open',
    'dispute_unabsorbed'
  ]::text[];
$$;

comment on function kernel.settlement_maturity_hold_codes() is
  'The closed set of hold_reason_code values kernel.settlement_payout_maturity (093 slice 10m, 097 ninth predicate) can emit. The ONLY reasons kernel.retry_held_payout may clear. Every other hold — risk, probation, destination, unfunded commission, failed re-arm, reversed transfer, shortfall_pending — is released solely by kernel.release_payout.';

-- ============================================================================
-- SECTION 7 — kernel.settlement_payout_maturity (093:2076-2170) BODY ONLY.
--   ONE addition, in causal order AFTER dispute_open: a ninth predicate,
--   'dispute_unabsorbed' (KB P0-1 O1). Hold when any covered payment carries
--   a lost/charge_refunded dispute that no chargeback line and no unlined_
--   reversal obligation has yet absorbed. Everything else — the operand
--   initialisation-to-hold discipline, the covered-set derivation, the eight
--   existing predicates and their order, the detail vector shape — is 093's
--   text unchanged.
-- ============================================================================
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
  -- 097: fails toward the hold, exactly like every other operand above.
  v_dispute_unabsorbed boolean := true;
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
                     where d.status in ('warning_needs_response','warning_under_review','needs_response','under_review'))),
    -- 097 (KB P0-1 O1): an ADVERSE, TERMINAL dispute against a covered payment
    -- that no chargeback line has absorbed AND no unlined_reversal obligation
    -- has recorded. Mirrors E-6's own reasoning for refunds ("a line written
    -- is not a debt recovered") on the side of the ledger that, before this
    -- migration, held nothing at all for a dispute observed already lost.
    (select exists (select 1 from cov c
                      join kernel.dispute_native d on d.payment_id = c.payment_id
                     where d.status in ('lost','charge_refunded')
                       and not exists (select 1 from venue.settlement_line l
                                        where l.cause = 'chargeback' and l.cause_ref = d.dispute_id)
                       and not exists (select 1 from kernel.organization_obligation oo
                                        where oo.origin_kind = 'unlined_reversal' and oo.origin_ref = d.dispute_id)))
    into v_unresolved, v_sess_n, v_sess_no_end, v_anchor, v_cancelled, v_refund_open, v_dispute_open, v_dispute_unabsorbed;

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
    when coalesce(v_dispute_unabsorbed, true)                  then 'dispute_unabsorbed'
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
      'refund_in_flight',   v_refund_open, 'dispute_open', v_dispute_open,
      'dispute_unabsorbed', v_dispute_unabsorbed));
end;
$$;

-- ============================================================================
-- SECTION 8 — kernel.close_settlement (094:544-790) BODY ONLY.
--   ONE addition: inside the `elsif v_net < 0` branch, immediately AFTER the
--   existing `perform kernel.record_organization_obligation(...)` call —
--   HOLD (never net, never pay, never release) this org's OTHER pending
--   settlement payouts at the SAME originating venue (KC P1-1 O7 / KD P1-3).
--   'submitted' payouts are never touched (an executor may be mid-transfer —
--   KB P1-4) and are counted into the audit row as submitted_unheld instead.
--   Every other line — the mint, the G2 maturity gate, the int4 ceilings, the
--   hold-reason vector, the closing audit row, the return value — is 094's
--   text unchanged; diffable by stripping the one new block below.
-- ============================================================================
create or replace function kernel.close_settlement(p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_s venue.settlement%rowtype; v_c kernel.settlement_line_candidate;
  v_gross bigint; v_fees bigint; v_refunds bigint; v_net bigint;
  v_payout_id uuid; v_ids uuid[] := '{}';
  v_held boolean := false; v_hold_reason text; v_hold_detail jsonb;
  v_maturity_verdict jsonb;
  -- 097 — the shortfall-hold operands.
  v_shortfall_held      integer := 0;
  v_shortfall_submitted integer := 0;
  v_shortfall_ids       uuid[]  := '{}';
  v_hold_po             record;
begin
  select * into v_s from venue.settlement where settlement_id = p_settlement_id for update;   -- SSCAS #4 rank-6
  if not found then raise exception 'not_found: settlement %', p_settlement_id using errcode = 'P0002'; end if;
  if not ((kernel.has_venue_role(v_s.venue_id, array['venue_finance'])
           and (select v.org_id from catalog.venue v where v.venue_id = v_s.venue_id) = v_s.org_id)   -- E-76: current operator
          or kernel.has_org_role(v_s.org_id, array['org_finance'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: venue_finance / org_finance / platform only' using errcode = '42501';
  end if;
  if v_s.status <> 'open' then   -- forward-only: a re-close is an idempotent replay
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

    -- ── 097 — THE SHORTFALL HOLD (KC P1-1 O7 / KD P1-3). NOT AN OFFSET. ────
    -- This org's OTHER pending settlement payouts at the SAME venue this
    -- shortfall originated at are held under a NEW reason, 'shortfall_
    -- pending' — deliberately NOT a kernel.settlement_maturity_hold_codes()
    -- member (Section 6), so kernel.retry_held_payout cannot self-clear it;
    -- only kernel.release_payout (platform_risk/platform_admin) can. A
    -- payout already 'held' under a MATURITY reason (the 093/10m codes,
    -- machine-owned, no human name on it) is upgraded the same way 088:846
    -- upgrades a probation hold — a human hold or an unrelated risk hold is
    -- left exactly as it is. A 'submitted' payout is NEVER touched (an
    -- executor may be mid-transfer, KB P1-4) — counted instead.
    for v_hold_po in
      select po.payout_id
        from kernel.payout po
        join venue.settlement s2 on s2.settlement_id = po.cause_ref
       where po.cause = 'settlement'
         and po.payee_org_id = v_s.org_id
         and po.status = 'pending'
         and s2.venue_id = v_s.venue_id
         and (po.hold_state = 'none'
              or (po.hold_state = 'held' and po.held_by is null
                  and po.hold_reason_code = any (kernel.settlement_maturity_hold_codes())))
       order by po.payout_id for update of po loop
      update kernel.payout
         set hold_state = 'held', hold_reason_code = 'shortfall_pending', held_by = null, held_at = now(), updated_at = now()
       where payout_id = v_hold_po.payout_id;
      v_shortfall_held := v_shortfall_held + 1;
      v_shortfall_ids := array_append(v_shortfall_ids, v_hold_po.payout_id);
      begin   -- OR-14: a notice failure never blocks the hold
        perform notify.emit_event('payout_on_hold', 'payout', v_hold_po.payout_id,
                  'payout_on_hold:' || v_hold_po.payout_id::text || ':' || p_settlement_id::text,
                  jsonb_build_object('settlement_id', p_settlement_id, 'reason', 'shortfall_pending'));
      exception when others then null; end;
    end loop;
    select count(*) into v_shortfall_submitted
      from kernel.payout po join venue.settlement s2 on s2.settlement_id = po.cause_ref
     where po.cause = 'settlement' and po.payee_org_id = v_s.org_id and po.status = 'submitted' and s2.venue_id = v_s.venue_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (auth.uid(), 'payout.shortfall_hold', 'settlement', p_settlement_id, 'shortfall_pending',
            jsonb_build_object('settlement_id', p_settlement_id),
            jsonb_build_object('settlement_id', p_settlement_id, 'venue_id', v_s.venue_id,
                                'held_payout_ids', v_shortfall_ids, 'submitted_unheld', v_shortfall_submitted));
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

-- ============================================================================
-- SECTION 9 — kernel.record_dispute_native (088:758-867) BODY ONLY.
--   FOUR additions, all fail-safe or alert-only, none of them touch the
--   status CHECK, the freeze semantics, or the terminal set:
--     (a) THE RAIL GUARD (KB P1-1): refuse a payment that is neither
--         mode='native_primary' nor already linked through kernel.
--         payment_native.sale_id (the resale rail, which today carries
--         legacy mode='buy_now').
--     (b) INPUT HYGIENE (KB P2-3): '' is refused wherever NULL already is.
--     (c) REPLAY-DRIFT AUDIT (KB A5/P2-6): a replay whose amount or charge
--         ref disagrees with what is already recorded is still a noop — but
--         audited, not silent.
--     (d) CURRENCY-MISMATCH AUDIT (KB A4/P2-1): a dispute currency that
--         disagrees with the order's own currency is still stored (093:1188
--         then leaves it unlined forever) — but audited, not invisible.
--   The wrong comment at 088:753-757 ("settlement AND commission payouts
--   alike") is corrected in place (KB P2-4): the payout leg has never reached
--   a commission payout — cause_ref there is an attribution id, never a
--   settlement id.
-- ============================================================================
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
  v_pn_found boolean;
  v_order_ccy text;
begin
  -- 097 (b): '' is not a valid ref/reason any more than NULL is.
  if p_stripe_dispute_ref is null or p_stripe_dispute_ref = ''
     or p_stripe_charge_ref is null or p_stripe_charge_ref = ''
     or p_reason is null or p_reason = ''
     or p_command_key is null then
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
    -- 097 (c): the first writer still wins (unchanged) — but a disagreeing
    -- replay is no longer silent.
    if v_d.amount_minor is distinct from p_amount_minor or v_d.stripe_charge_ref is distinct from p_stripe_charge_ref then
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'dispute.alert', 'dispute_native', v_d.dispute_id, 'replay_drift',
              jsonb_build_object('recorded_amount', v_d.amount_minor, 'replay_amount', p_amount_minor,
                                  'recorded_charge', v_d.stripe_charge_ref, 'replay_charge', p_stripe_charge_ref,
                                  'audience', 'platform_risk'));
    end if;
    return jsonb_build_object('status','noop_replay','dispute_id', v_d.dispute_id);
  end if;
  select * into v_pay from public.payments p where p.stripe_payment_intent_id = p_stripe_pi_ref;
  if not found then
    raise exception 'not_found: no payment for payment intent %', coalesce(p_stripe_pi_ref,'<null>') using errcode = 'P0002';
  end if;
  -- 097 (a): the rail guard. Recordable ONLY against the native rail — a
  -- native_primary-mode payment, OR any payment already linked through
  -- kernel.payment_native (the order arm writes order_id at finalize_primary_order,
  -- the resale arm writes sale_id at the market-sale transfer). A legacy resale
  -- payment (mode buy_now/auction) never gets a payment_native row, so it is the
  -- only shape this rejects — closing the KB P1-1 leak without refusing a genuine
  -- primary-order dispute whose fixture/mode literal is not yet native_primary.
  if v_pay.mode <> 'native_primary'
     and not exists (select 1 from kernel.payment_native pn where pn.payment_id = v_pay.id) then
    raise exception 'precondition_failed: not_native_rail — payment % is not on the native dispute rail', v_pay.id using errcode = 'P0001';
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
  v_pn_found := found;
  -- 097 (d): the currency-mismatch alert.
  if v_pn_found and v_pn.order_id is not null then
    select o.currency into v_order_ccy from venue."order" o where o.order_id = v_pn.order_id;
    if v_order_ccy is not null and v_order_ccy <> v_ccy then
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_sys, 'dispute.alert', 'dispute_native', v_d.dispute_id, 'currency_mismatch',
              jsonb_build_object('dispute_currency', v_ccy, 'order_currency', v_order_ccy, 'audience','platform_risk'));
    end if;
  end if;
  if v_open and v_pn_found then
    -- ATOM LEG: the disputed payment's atoms (order arm via the issuance ledger; sale arm via the sale).
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
      perform 1 from catalog.event_session s where s.session_id = v_atom.event_session_id for share;   -- rank 1
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
    -- PAYOUT LEG: every pending/submitted payout reachable from the disputed
    -- payment that is not already under a dispute hold (a probation hold is
    -- upgraded: its own release path is reason-scoped and never releases a
    -- 'dispute' hold — 087). CORRECTED (097 / KB P2-4): this predicate has
    -- never reached a promoter_commission payout — its cause_ref is the
    -- attribution id (090:1483-1485), never a settlement id — dark today,
    -- recorded not fixed (KC 4.5 O12, an orchestrator item).
    for v_po in
      select po.payout_id, po.payee_org_id, po.payee_identity_id, po.amount_minor from kernel.payout po
       where po.status in ('pending','submitted') and po.hold_state in ('none','probation_hold')
         and (   (v_pn.sale_id is not null and po.cause_ref = v_pn.sale_id)
              or po.cause_ref in (select sl.settlement_id from venue.settlement_line sl
                                   where sl.cause_ref = coalesce(v_pn.order_id, v_pn.sale_id)))
       order by po.payout_id for update loop                                                    -- rank 6
      update kernel.payout set hold_state = 'held', hold_reason_code = 'dispute', held_at = now(), held_by = null, updated_at = now()
       where payout_id = v_po.payout_id;
      v_held := v_held + 1;
      begin   -- BE: a notice failure never blocks the freeze (OR-14)
        perform notify.emit_event('payout_on_hold', 'payout', v_po.payout_id, 'payout_on_hold:' || v_po.payout_id::text || ':' || v_d.dispute_id::text,
                  jsonb_build_object('dispute_id', v_d.dispute_id, 'reason', 'dispute', 'amount_minor', v_po.amount_minor));
      exception when others then null; end;
    end loop;
  elsif v_open then
    -- NO-LINK ARM: recorded, zero freeze legs, alerted (the dwell-window refusal rides finalize_market_sale).
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

-- ============================================================================
-- SECTION 10 — kernel.mark_dispute_state (088:875-902) BODY ONLY.
--   ONE addition: p_command_key is now bound by record_dispute_native's own
--   regex (KB P2-2) — a NULL or unbounded string no longer lands unexamined
--   in the immutable audit. Everything else is 088's text unchanged.
-- ============================================================================
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
  -- 097 (KB P2-2): the same shape record_dispute_native already enforces.
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
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
  values (v_sys, 'dispute.state_sync', 'dispute_native', v_d.dispute_id, p_command_key,
          jsonb_build_object('status', v_d.status), jsonb_build_object('status', p_new_status));
  return jsonb_build_object('status','ok','dispute_id', v_d.dispute_id,'dispute_status', p_new_status);
end;
$$;

commit;
