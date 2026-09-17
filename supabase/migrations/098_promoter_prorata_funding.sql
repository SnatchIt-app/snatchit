-- ============================================================================
-- 098_promoter_prorata_funding.sql — pre-close promoter commission funding
--   is recomputed pro-rata against SURVIVING FACE REVENUE, replacing 093/10e's
--   total exclusion. PFA-PT-4 (POST_FREEZE_AMENDMENTS.md — PENDING OWNER
--   SIGNATURE). Investigator report: docs/phase2/_impl/KF_promoter_prorata.md.
--
-- WHAT THIS MIGRATION IS. Three BODY-ONLY re-creates, signatures/ACLs frozen
-- (CREATE OR REPLACE preserves grants — no GRANT/REVOKE statement is needed or
-- written here):
--   (1) kernel.settlement_commission_lines (093:889-925) — the eligible-set
--       predicate: drop the order-status total-exclusion clause, add
--       o.status <> 'cancelled', add the refund-in-flight deferral predicate
--       (the "could still succeed" arithmetic, copied verbatim from the same
--       predicate 097 adds to the chargeback and primary-line arms — DESIGN
--       097_099 §2.1 — so all three seams read one fact the same way).
--   (2) kernel.pay_promoter_commission (090:1401-1507) — the basis block
--       (090:1456-1466 / the 093 `v_o.status='refunded'` arm): surviving face
--       replaces surviving ATOMS as the commission basis.
--   (3) kernel.mark_payout_transfer_state (085:1668-1735) — ONE added guard:
--       a payout with cause='promoter_commission' is refused outright. No
--       promoter payout executor is contracted anywhere (ruling A4); KF P2-1
--       measured that the state-sync verb is otherwise cause-agnostic and
--       would accept a forced submitted→paid on a commission payout. This
--       turns lock 4 from an absence into a refusal.
--
-- WHAT THIS MIGRATION IS NOT. It does not fund, release, or pay a single
-- promoter dollar. Every commission payout this seam mints is still born
-- hold_state='held', hold_reason_code='unfunded_settlement' (090:1483-1486,
-- untouched). G4 (unsigned) — "commission stays HELD; no release, no payout"
-- — is unaffected: post-close reversal of an already-funded commission is
-- still not pursued (PROMO §5.3). Ruling A4 — "nothing in 093 may accidentally
-- release promoter money" — is unaffected: no hold is touched, no advance path
-- is added, `kernel.release_payout` remains the only release, and (3) makes
-- the fourth lock stronger, not weaker. This migration only changes the
-- AMOUNT the pre-close seam computes and funds under that same hold.
--
-- WHY A PFA IS NEEDED (KF §5). PROMO §6.1 defines the commission basis over
-- "surviving, non-voided items" (atoms); §5.2/test 45 REQUIRE a reduced single
-- line on a partial refund. The shipped refund verb voids atoms only on a
-- delegated or FULL refund (085:563-568) — a direct partial refund is "money
-- only", so the atom basis is unreduced on every partial refund (KF §2.1: 10000
-- on all nine measured rows) and 093/10e's total exclusion is a bandage, not a
-- correction the corpus already computes. Reading "surviving" as FACE MINUS
-- SETTLED REFUND SHARE is a normative change to §6.1/§5.2's "VERIFIED: D2"
-- sentence — filed as PFA-PT-4, PENDING OWNER SIGNATURE. Dark migration
-- (090's whole engine ships inert; no config key, no cron row — 155 A32/A33);
-- the signature is a deploy precondition, exactly as 094's Gate-M row, NOT a
-- precondition to authoring or testing the SQL.
--
-- THE RULE (KF §4.2, PFA-PT-4 RESOLUTION):
--   eligible(a)   := today's org/scope/currency/payee/deny filters, minus the
--                    status clause, plus o.status <> 'cancelled', plus the
--                    refund-in-flight deferral (mirrors 093:477-481 / 097's
--                    "could still succeed" predicate).
--   refunded(a)   := least(face, Σ kernel.refund.amount_minor WHERE
--                    status='succeeded') — 10h's operand, read live, not from
--                    settlement_line, so it is correct even in this same close.
--   disputed(a)   := least(face − refunded(a), Σ kernel.dispute_native.
--                    amount_minor WHERE status IN ('lost','charge_refunded'))
--                    — KF §4.4's default (include, capped so a chargeback never
--                    re-consumes face a refund already claimed).
--   surviving(a)  := face − refunded(a) − disputed(a)
--   payable(a)    := bps:  floor(surviving(a) × commission_bps_applied / 10000.0)
--                    flat: floor(surviving(a) / unit_price_minor) per order
--                          item, summed, × commission_flat_minor_applied
--                          (KF §4.5 option (a) — the owner-visible choice; a
--                          money-only partial refund has no atom count to read,
--                          so the surviving TICKET COUNT is derived from
--                          surviving face, capped at the item's own quantity).
--   line          := −payable(a) iff payable(a) > 0, else HELD basis_zero, NO
--                    line (as today — 090:1468-1470 unchanged; re-eligible at
--                    a later close only while unlined, per the index).
-- Properties (KF §4.2, executed against the KF fixture): payable ≤
-- credited_amount_minor always (surviving ≤ face, same floor); payable ≤
-- surviving revenue (bps ≤ 10000); ONE line per attribution ever (index +
-- NOT EXISTS, unchanged); idempotent across re-close (unchanged — the
-- NOT EXISTS runs before either seam body); no double funding (the line is
-- −payable, the payout is +payable, same number, one each); post-close
-- refunds are NOT re-funded (the attribution is out of the eligible set
-- forever once lined — G4's territory, untouched). Rounding is FLOOR, always
-- (PROMO §6.2); the residual stays with the org (090:29-32) — no rounding
-- convention changes.
--
-- WHAT 10e's DEFECT NARRATIVE GAINED, RETROACTIVELY (KF §5 last paragraph):
-- 093's own comment (093:861-876) called its status-only exclusion "a
-- deliberate, reversible over-correction" pending "an owner ruling on how a
-- partial refund maps onto ticket atoms" — but the deviation was never filed
-- in POST_FREEZE_AMENDMENTS.md. This migration's PFA-PT-4 entry files that
-- retroactive note in the same block (see docs/architecture/_governance/
-- POST_FREEZE_AMENDMENTS.md).
--
-- WHAT THIS MIGRATION DOES NOT TOUCH: G4 (iii) — whether a post-payout
-- shortfall should be booked net of a funded-and-held commission (KF §4.5 /
-- KC P1-3) — deferred to the G4 signature, as KF §6 O3 recommends. P1-4 (a WON
-- dispute's venue-payout `dispute` hold survives release, only Control-5
-- clears it) — venue-side, out of scope, KF §3. `unlined_reversal` — owned by
-- migration 097 (KD/KC), not re-created here.
--
-- SOURCES READ, NOT ASSUMED: docs/phase2/_impl/KF_promoter_prorata.md (all),
-- KC_chargeback_accounting.md §2.i, 090:1401-1548 (the whole commission leg),
-- 093:857-930 (10e), 085:1665-1734 (the state-sync pair),
-- docs/architecture/PHASE_2_PROMOTER_CODES_SPEC.md §5.2/§6.1-6.3,
-- docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md (E-132/E-138 and the
-- PFA entry format), supabase/tests/155 (fixtures), 161 (the state-sync
-- house style), DESIGN_097_099.md §M3 / §2.1 (the deferral predicate text).
-- ============================================================================
begin;

set local lock_timeout = '3s';

-- ============================================================================
-- (1) kernel.settlement_commission_lines — BODY ONLY, signature/VOLATILE/
--   E-104 per-org advisory lock/scope predicate/never-lined-before dedupe/
--   currency filter/payee-resolvable filter/deny-decision filter/the
--   pay_promoter_commission call and its 'seam:' command key/the negated
--   return projection are ALL PRESERVED VERBATIM from 093:889-925. The ONLY
--   change is inside the eligible-set WHERE clause: the terminal-class status
--   exclusion ('refunded','partially_refunded','cancelled') is replaced with
--   `o.status <> 'cancelled'` (a cancelled order has no economic basis at
--   all — 093's own reading, unchanged) plus a refund-in-flight deferral so a
--   pre-close attribution is never funded off a refund that has not yet
--   settled. 'refunded' and 'partially_refunded' orders are no longer
--   terminal here: kernel.pay_promoter_commission (2, below) now computes
--   their basis from SURVIVING FACE instead of forfeiting outright.
-- ============================================================================
create or replace function kernel.settlement_commission_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language plpgsql volatile security definer set search_path = ''
as $$
declare v_s venue.settlement%rowtype; v_ids uuid[]; v_res jsonb;
begin
  select * into v_s from venue.settlement st where st.settlement_id = p_settlement_id;
  if v_s.settlement_id is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_s.org_id::text));
  -- the eligible set: this org, this settlement's scope (event, or venue + period),
  -- never lined before (fresh snapshot after the lock — VOLATILE)
  select coalesce(array_agg(a.id order by a.order_paid_at, a.id), '{}') into v_ids
    from venue.attribution a
    join venue."order" o on o.order_id = a.order_id
    join catalog.event_session es on es.session_id = o.event_session_id
    join catalog.event e on e.event_id = a.event_id
   where a.org_id = v_s.org_id
     and ((v_s.event_id is not null and a.event_id = v_s.event_id)
          or (v_s.event_id is null and e.venue_id = v_s.venue_id
              and (v_s.period_start is null or es.starts_at >= v_s.period_start)
              and (v_s.period_end is null or es.starts_at < v_s.period_end)))
     and not exists (select 1 from venue.settlement_line l where l.cause = 'promoter_commission' and l.cause_ref = a.id)
     -- terminal classes are excluded HERE so a permanently-held attribution is not re-walked at every
     -- close under the settlement lock (red-team B5); pay_promoter_commission keeps its own defensive arms.
     -- 098/PFA-PT-4: a cancelled order has no economic basis at all and stays excluded here (unchanged
     -- reading). 'refunded'/'partially_refunded' are NO LONGER excluded — kernel.pay_promoter_commission
     -- now recomputes the basis from surviving face instead of forfeiting the whole attribution.
     and o.status <> 'cancelled'
     -- 098/PFA-PT-4 + 097 (DESIGN_097_099 §2.1): DEFER while a refund on this order's payment is
     -- IN FLIGHT AND COULD STILL SUCCEED — mirrors 093:477-481 (the primary-line arm) and the
     -- identical predicate 097 adds to the chargeback/primary seams, copied verbatim so all three
     -- seams read one fact the same way. A pending refund the executor's Σ-guard could never accept
     -- (refund-execute/executor.ts:276-285) does NOT defer — it can only ever fail, so the order's
     -- current surviving face already IS its final surviving face.
     and not exists (
       select 1 from kernel.payment_native pn
        where pn.order_id = o.order_id
          and exists (
            select 1 from kernel.refund r0
             where r0.payment_id = pn.payment_id
               and r0.status in ('pending','submitted')
               and r0.amount_minor
                   + coalesce((select sum(r1.amount_minor) from kernel.refund r1
                                where r1.payment_id = pn.payment_id and r1.status = 'succeeded'), 0)
                   + coalesce((select sum(d1.amount_minor) from kernel.dispute_native d1
                                where d1.payment_id = pn.payment_id and d1.status in ('lost','charge_refunded')), 0)
                   <= (select p.total from public.payments p where p.id = pn.payment_id)
          )
     )
     and a.currency = v_s.currency
     and exists (select 1 from venue.promoter p where p.promoter_id = a.promoter_id and p.identity_id is not null)
     and coalesce((select r.decision from venue.attribution_review r where r.attribution_id = a.id order by r.seq desc limit 1), 'held') <> 'deny';
  if cardinality(v_ids) = 0 then return; end if;
  v_res := kernel.pay_promoter_commission(p_settlement_id, v_ids, 'seam:' || p_settlement_id::text);
  return query
    select 'promoter_commission'::text, (x ->> 'attribution_id')::uuid, -((x ->> 'amount_minor')::bigint), v_s.currency,
           'identity'::text, (x ->> 'payee_identity_id')::uuid
      from jsonb_array_elements(coalesce(v_res -> 'lines', '[]'::jsonb)) x
     order by 2;
end;
$$;

-- ============================================================================
-- (2) kernel.pay_promoter_commission — BODY ONLY. The forbidden-caller guard,
--   the settlement re-lock (NOWAIT), the per-attribution loop shape, the
--   advisory review-lock (attribution.review:<id>), the self-deal/flagged
--   hold, the identity/currency holds, the amount_overflow guard, the payout
--   MINT (still hold_state='held', hold_reason_code='unfunded_settlement'),
--   the notify.emit_event calls, and the trailing settlement.commission audit
--   insert are ALL PRESERVED VERBATIM from 090:1401-1507. The ONLY change is
--   the basis block (090:1456-1466 / the 093-introduced `v_o.status =
--   'refunded'` short-circuit): surviving ATOMS is replaced by surviving FACE
--   (KF §4.2/§4.4/§4.5(a)). Because the eligible-set predicate above no longer
--   excludes 'refunded'/'partially_refunded' orders, this block now actually
--   runs for them, and — KF P1-1 — the settlement.commission audit row this
--   function already writes ONCE per call (090:1502-1504, unchanged) now
--   covers every evaluated attribution INCLUDING a basis_zero one, because the
--   attribution reaches this function at all instead of being silently
--   excluded one seam up.
-- ============================================================================
create or replace function kernel.pay_promoter_commission(p_settlement_id uuid, p_attribution_ids uuid[], p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_s venue.settlement%rowtype; v_ctx text; v_a venue.attribution%rowtype; v_p venue.promoter%rowtype; v_o venue."order"%rowtype;
        v_face bigint; v_refunded bigint; v_disputed bigint; v_surviving bigint;
        v_basis bigint; v_qty bigint; v_payable bigint; v_decision text; v_po uuid; v_key text;
        v_lines jsonb := '[]'::jsonb; v_held jsonb := '[]'::jsonb; v_ids uuid[] := '{}'; v_n int := 0; v_id uuid;
        v_sys constant uuid := '00000000-0000-0000-0000-0000000000f1';
begin
  -- FORBIDDEN CALLERS: every client and human role. Structural: the call stack
  -- must carry the seam AND the 087 close (asserted, not assumed).
  get diagnostics v_ctx = pg_context;
  if v_ctx !~ 'kernel\.settlement_commission_lines' or v_ctx !~ 'kernel\.close_settlement' then
    raise exception 'insufficient_privilege: pay_promoter_commission is reachable only from kernel.close_settlement via the commission seam' using errcode = '42501';
  end if;
  -- the settlement is being closed in THIS transaction: the call-stack guard above is the enforcement;
  -- the NOWAIT re-lock only refuses a settlement another transaction holds (it cannot prove the
  -- caller's own lock — a self-held row lock is immediate). Rank 6, same txn.
  begin
    select * into v_s from venue.settlement where settlement_id = p_settlement_id for update nowait;
  exception when lock_not_available then
    raise exception 'precondition_failed: settlement_not_locked' using errcode = 'P0001';
  end;
  if v_s.settlement_id is null or v_s.status <> 'open' then
    raise exception 'precondition_failed: settlement_not_locked (not an open settlement in this transaction)' using errcode = 'P0001';
  end if;
  foreach v_id in array coalesce(p_attribution_ids, '{}'::uuid[]) loop
    select * into v_a from venue.attribution where id = v_id;
    if v_a.id is null or v_a.org_id <> v_s.org_id then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'out_of_scope'); continue;
    end if;
    if exists (select 1 from venue.settlement_line l where l.cause = 'promoter_commission' and l.cause_ref = v_a.id) then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'already_lined'); continue;   -- conflict_locked class
    end if;
    -- the SAME advisory key review_attribution_flag takes: a release/deny cannot interleave between
    -- this decision read and the line commit (red-team E1 — "the money and the decision freeze together")
    perform pg_advisory_xact_lock(hashtext('attribution.review:' || v_a.id::text));
    -- HOLD: flagged and not released at max(seq)
    if v_a.self_deal_flag then
      select r.decision into v_decision from venue.attribution_review r where r.attribution_id = v_a.id order by r.seq desc limit 1;
      if coalesce(v_decision, 'held') <> 'release' then
        v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', case when v_decision = 'deny' then 'denied' else 'unreviewed_flag' end); continue;
      end if;
    end if;
    select * into v_p from venue.promoter where promoter_id = v_a.promoter_id;
    -- terms resolve from the ATTRIBUTION's snapshot (never the promoter's current terms)
    if not ((v_a.commission_kind = 'bps' and v_a.commission_bps_applied is not null)
            or (v_a.commission_kind = 'flat_per_ticket' and v_a.commission_flat_minor_applied is not null)) then
      raise exception 'precondition_failed: terms_unresolvable for attribution %', v_id using errcode = 'P0001';
    end if;
    if v_p.identity_id is null then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'payee_unresolvable'); continue;   -- E-128
    end if;
    if v_a.currency <> v_s.currency then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'currency_mismatch'); continue;    -- E-128
    end if;
    -- 098/PFA-PT-4: PAYABLE from surviving FACE REVENUE, not surviving atoms (KF §4.2). face = the
    -- order's frozen total_minor (= a.basis_minor at freeze, 082:424-426). refunded(a) = the SETTLED
    -- refund share (10h's operand, read live from kernel.refund so it is correct in this same close),
    -- capped at face. disputed(a) = lost/charge_refunded chargeback exposure, capped at the headroom
    -- refunded(a) left (KF §4.4 default: include, with 10h's cap, so a chargeback never re-consumes
    -- face a refund already claimed). surviving(a) = face − refunded(a) − disputed(a); surviving ≤ 0
    -- (a fully refunded/charged-back order, including 090's original 'refunded' short-circuit) is
    -- held basis_zero, no line — as today.
    select * into v_o from venue."order" where order_id = v_a.order_id;
    v_face := v_o.total_minor::bigint;
    select coalesce(sum(r.amount_minor), 0)::bigint into v_refunded
      from kernel.payment_native pn join kernel.refund r on r.payment_id = pn.payment_id and r.status = 'succeeded'
     where pn.order_id = v_a.order_id;
    v_refunded := least(v_face, v_refunded);
    select coalesce(sum(d.amount_minor), 0)::bigint into v_disputed
      from kernel.payment_native pn join kernel.dispute_native d on d.payment_id = pn.payment_id and d.status in ('lost','charge_refunded')
     where pn.order_id = v_a.order_id;
    v_disputed := least(greatest(0, v_face - v_refunded), v_disputed);
    v_surviving := greatest(0, v_face - v_refunded - v_disputed);
    if v_surviving <= 0 then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'basis_zero'); continue;
    end if;
    if v_a.commission_kind = 'bps' then
      v_basis := v_surviving;
      v_payable := floor(v_basis * v_a.commission_bps_applied / 10000.0)::bigint;
    else
      -- KF §4.5(a): a money-only partial refund voids no atom (085:563-568), so there is no surviving
      -- TICKET COUNT to read off custody state. The surviving quantity is DERIVED from surviving face:
      -- floor(surviving_face / unit_price) per order item, capped at that item's own quantity (never
      -- more tickets counted than existed), summed across items.
      select coalesce(sum(least(oi.quantity, floor(v_surviving::numeric / nullif(oi.unit_price_minor, 0))::bigint)), 0)
        into v_qty
        from venue.order_item oi where oi.order_id = v_a.order_id;
      v_payable := v_a.commission_flat_minor_applied::bigint * v_qty;
    end if;
    if v_payable <= 0 then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'basis_zero'); continue;
    end if;
    if v_payable > 2147483647 then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'amount_overflow'); continue;   -- never an opaque 22003 out of the close
    end if;
    -- ONE payout per (attribution, payee) — PROMOTER §4.2 (3), byte for byte.
    -- MINTED UNDER A SYSTEM HOLD (E-138 / X-12): the org's debit is a negative settlement line
    -- that 087's close never collects (no primary-revenue line exists in Phase 2, so the net is
    -- negative and no org payout is minted), and no advance path for a promoter_commission payout
    -- is contracted (request_org_payout is cause='settlement' only). Until the owner rules the
    -- funding source (COMMISSION_FUNDING_SOURCE) the liability is recorded but no money can leave:
    -- mark_payout_transfer_state refuses a held payout (AND, as of 098, refuses this cause outright);
    -- kernel.release_payout (platform_risk / platform_admin, Control-5) is the release path once funded.
    v_key := 'promoter_commission:' || v_a.id::text || ':' || v_p.identity_id::text;
    insert into kernel.payout (payee_kind, payee_identity_id, cause, cause_ref, amount_minor, currency, status, idempotency_key,
                               hold_state, hold_reason_code, held_by, held_at)
    values ('identity', v_p.identity_id, 'promoter_commission', v_a.id, v_payable::integer, v_s.currency, 'pending', v_key,
            'held', 'unfunded_settlement', null, now())
    on conflict (idempotency_key) do nothing
    returning payout_id into v_po;
    if v_po is null then select payout_id into v_po from kernel.payout where idempotency_key = v_key; end if;
    begin   -- BE (OR-14): the hold notice never gates the close (088's dispute-hold precedent)
      perform notify.emit_event('payout_on_hold', 'payout', v_po, 'payout_on_hold:' || v_po::text || ':unfunded_settlement',
        jsonb_build_object('reason', 'unfunded_settlement', 'amount_minor', v_payable, 'settlement_id', p_settlement_id));
    exception when others then null; end;
    v_ids := v_ids || v_po; v_n := v_n + 1;
    v_lines := v_lines || jsonb_build_object('attribution_id', v_a.id, 'amount_minor', v_payable, 'payee_identity_id', v_p.identity_id, 'payout_id', v_po);
    -- G-25 #32 PromoterCommissionAccrued — BE emit, dedup commission:<attribution_id> (NOTIF §5)
    begin
      perform notify.emit_event('promoter_commission_accrued', 'attribution', v_a.id, 'commission:' || v_a.id::text,
        jsonb_build_object('settlement_id', p_settlement_id, 'payout_id', v_po, 'amount_minor', v_payable, 'promoter_id', v_a.promoter_id));
    exception when others then null; end;
  end loop;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (coalesce(auth.uid(), v_sys), 'settlement.commission', 'settlement', p_settlement_id, coalesce(p_command_key, 'close'),
          jsonb_build_object('lines_written', v_n, 'payout_ids', to_jsonb(v_ids), 'held', v_held));
  return jsonb_build_object('status','ok','lines_written', v_n, 'payout_ids', to_jsonb(v_ids), 'held', v_held, 'lines', v_lines);
end;
$$;

-- ============================================================================
-- (3) kernel.mark_payout_transfer_state — BODY ONLY. Every existing predicate
--   (invalid_input on the status vocabulary, not_found, the hold refusal, the
--   noop-replay rule, forward-only, the mandatory-ref/failure-code checks, the
--   write-once ref, the admin_audit write, the venue.on_payout_settled hook)
--   is PRESERVED VERBATIM from 085:1668-1735. ONE guard is added, immediately
--   after the not_found check: a payout with cause='promoter_commission' is
--   refused outright, regardless of status or hold. KF P2-1 measured that this
--   verb is otherwise cause-agnostic — with status='submitted' forced as table
--   owner (unreachable by any contracted path today: every advancer to
--   'submitted' is cause='settlement' only, 093:1786 / 095:523), a
--   submitted→paid transition on a commission payout was ACCEPTED. No promoter
--   payout executor exists anywhere (ruling A4): this turns the fourth lock
--   from "nothing advances the row" into "the verb itself refuses the cause".
-- ============================================================================
create or replace function kernel.mark_payout_transfer_state(
  p_payout_id uuid, p_new_status text, p_stripe_transfer_ref text, p_failure_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.payout%rowtype;
begin
  -- O16: form (a) — 'paid' asserts the executor's synchronous transfer result;
  -- 'submitted' belongs to 087's request path and is REFUSED here (a second
  -- door past the money controls otherwise).
  if p_new_status not in ('paid','failed','reversed') then
    raise exception 'invalid_input: mark_payout_transfer_state takes paid|failed|reversed';
  end if;
  select * into v_row from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  -- 098/KF P2-1: the fourth "lock" on a promoter_commission payout was an ABSENCE (no contracted
  -- path ever advances one to 'submitted'), not a refusal — a forced submitted→paid was accepted
  -- (KF §2.4/§7 probe). No promoter payout executor exists anywhere (ruling A4). Refuse the cause
  -- outright, before status/hold are even read, so the lock holds structurally rather than by luck.
  if v_row.cause = 'promoter_commission' then
    raise exception 'precondition_failed: promoter_payout_dark — no promoter payout executor exists (ruling A4)';
  end if;
  -- Control-4-by-webhook defense: a HELD payout refuses the sync, BOTH columns
  -- untouched (T-SCHEMA-PAYOUT-06).
  if v_row.hold_state <> 'none' then
    raise exception 'precondition_failed: payout_held';
  end if;
  -- replay: same terminal + same ref = noop, never a raise
  if v_row.status = p_new_status
     and (p_stripe_transfer_ref is null or v_row.stripe_transfer_ref = p_stripe_transfer_ref) then
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id);
  end if;
  -- forward-only: submitted→paid|failed; paid→reversed (the one legal
  -- terminal-to-terminal edge). Everything else is backwards.
  if not ( (v_row.status = 'submitted' and p_new_status in ('paid','failed'))
        or (v_row.status = 'paid'      and p_new_status = 'reversed') ) then
    raise exception 'precondition_failed: payout_state_backwards (% → %)', v_row.status, p_new_status;
  end if;
  if p_new_status in ('paid','reversed') and p_stripe_transfer_ref is null then
    raise exception 'invalid_input: stripe_transfer_ref is mandatory for %', p_new_status;
  end if;
  if p_new_status = 'failed' and (p_failure_code is null or length(trim(p_failure_code)) = 0) then
    raise exception 'invalid_input: failure_code is mandatory for failed';
  end if;
  -- write-once ref: equal-on-replay, conflict otherwise
  if v_row.stripe_transfer_ref is not null and p_stripe_transfer_ref is not null
     and v_row.stripe_transfer_ref <> p_stripe_transfer_ref then
    raise exception 'conflict_locked: stripe_transfer_ref is write-once (% vs %)',
      v_row.stripe_transfer_ref, p_stripe_transfer_ref;
  end if;

  update kernel.payout
     set status = p_new_status,
         stripe_transfer_ref = coalesce(v_row.stripe_transfer_ref, p_stripe_transfer_ref),
         updated_at = now()
   where payout_id = p_payout_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'payout.state_sync', 'payout',
          p_payout_id, coalesce(p_failure_code, p_new_status),
          jsonb_build_object('status', v_row.status),
          jsonb_build_object('status', p_new_status));

  if p_new_status = 'paid' then
    -- the FIFTH seam: settlement closed→paid rides this hook (body 087).
    perform venue.on_payout_settled(p_payout_id);
  end if;
  return jsonb_build_object('status','ok','payout_id', p_payout_id, 'new_status', p_new_status);
end;
$$;

commit;
