-- ============================================================================
-- 098_promoter_prorata_funding_rollback.sql
--   REVERSES supabase/migrations/098_promoter_prorata_funding.sql
-- ----------------------------------------------------------------------------
-- POSTURE: FORWARD-FIX PREFERRED, BUT THIS ONE IS SAFE TO RUN. Unlike 095's
-- rollback, 098 creates no table, no column, no index, no trigger and holds no
-- money in a state only its own machinery understands — it is three BODY-ONLY
-- CREATE OR REPLACE statements over 090/093/085-owned functions. Restoring the
-- pre-098 bodies below is a complete, symmetric undo: no guard is needed
-- because there is no new object whose absence would break a held row, and no
-- 098-authored hold_reason_code or state exists anywhere in kernel.payout for
-- a stuck-row check to protect.
--
-- WHAT RESTORING DOES, ECONOMICALLY. Any commission line/payout written under
-- 098's pro-rata rule (kernel.settlement_line cause='promoter_commission',
-- kernel.payout cause='promoter_commission') is APPEND-ONLY and UNTOUCHED by
-- this rollback — those facts stand, at whatever amount 098 computed, exactly
-- as 090's original code would leave a pre-098 line standing. This rollback
-- only changes what a FUTURE close computes and whether mark_payout_transfer_
-- state's fourth-cause guard exists; it does not revalue, unwind or re-line
-- anything already written. After rollback, an order that is 'refunded' or
-- 'partially_refunded' at a future close is excluded WHOLE again (093/10e's
-- behaviour), and mark_payout_transfer_state returns to being cause-agnostic
-- (098's promoter_payout_dark guard is removed — KF P2-1's unreachable-by-
-- contract gap re-opens; no contracted path exploits it, per 090/093/095).
--
-- ORDER: the three restores are independent of each other and of any other
-- 09x package (098 re-created no object 097/096/099 depend on and depends on
-- none of theirs). Restored in the same order 098 created them for
-- readability only.
--
-- RESTORED TEXT: 093:889-925 (kernel.settlement_commission_lines, byte-
-- identical to the shipped 093 body), 090:1401-1507 (kernel.
-- pay_promoter_commission, byte-identical to the shipped 090 body),
-- 085:1668-1735 (kernel.mark_payout_transfer_state, byte-identical to the
-- shipped 085 body). CREATE OR REPLACE preserves ACLs — no GRANT/REVOKE is
-- written here, matching 098's own posture.
--
-- Second run: idempotent (CREATE OR REPLACE), no-op in effect, no NOTICE
-- needed — there is no marker object whose absence would signal "already
-- rolled back" the way 095's rollback checks kernel.rearm_failed_payout.
-- ============================================================================
begin;

set local lock_timeout = '3s';

-- ----------------------------------------------------------------------------
-- restore kernel.settlement_commission_lines to 093:889-925 — total exclusion
-- of ('refunded','partially_refunded','cancelled'), no deferral predicate.
-- ----------------------------------------------------------------------------
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
     -- 093/A4: 'partially_refunded' joins the exclusion — a direct partial refund voids no atoms
     -- (085:571-573), so the surviving-atom basis (090:1461-1466) is unreduced and FULL commission
     -- would be paid on partly refunded revenue. Excluding is the reversible error.
     and o.status not in ('refunded','partially_refunded','cancelled')
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

-- ----------------------------------------------------------------------------
-- restore kernel.pay_promoter_commission to 090:1401-1507 — surviving-ATOM
-- basis, order status='refunded' short-circuit.
-- ----------------------------------------------------------------------------
create or replace function kernel.pay_promoter_commission(p_settlement_id uuid, p_attribution_ids uuid[], p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_s venue.settlement%rowtype; v_ctx text; v_a venue.attribution%rowtype; v_p venue.promoter%rowtype; v_o venue."order"%rowtype;
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
    -- PAYABLE from live state: surviving (non-voided) atoms per item; a refunded order ⇒ 0
    select * into v_o from venue."order" where order_id = v_a.order_id;
    if v_o.status = 'refunded' then
      v_held := v_held || jsonb_build_object('attribution_id', v_id, 'reason', 'basis_zero'); continue;
    end if;
    select coalesce(sum(oi.unit_price_minor::bigint * surv.n), 0), coalesce(sum(surv.n), 0) into v_basis, v_qty
      from venue.order_item oi
      cross join lateral (select count(*) as n from kernel.ticket_ownership_log l join kernel.tickets t on t.ticket_atom_id = l.ticket_atom_id
                            where l.sequence = 1 and l.cause = 'issue' and l.cause_ref = oi.id and t.state <> 'voided') surv
     where oi.order_id = v_a.order_id;
    v_payable := case when v_a.commission_kind = 'bps' then floor(v_basis * v_a.commission_bps_applied / 10000.0)::bigint
                      else v_a.commission_flat_minor_applied::bigint * v_qty end;
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
    -- mark_payout_transfer_state refuses a held payout; kernel.release_payout (platform_risk /
    -- platform_admin, Control-5) is the release path once funded.
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

-- ----------------------------------------------------------------------------
-- restore kernel.mark_payout_transfer_state to 085:1668-1735 — cause-agnostic,
-- no promoter_commission guard.
-- ----------------------------------------------------------------------------
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
