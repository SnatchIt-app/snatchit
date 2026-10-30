-- ============================================================================
-- 095_payout_state_machine_recovery_rollback.sql
--   REVERSES supabase/migrations/095_payout_state_machine_recovery.sql
-- ----------------------------------------------------------------------------
-- POSTURE: BREAK-GLASS ONLY, AND IT RESTORES TWO KNOWN DEFECTS. Read this
-- before running it.
--
--   1. Restoring kernel.get_payout_execution_context to its 093 body
--      REINTRODUCES the refund_exposure_stale defeat (095 E-6): booking a
--      reversal into a settlement that nets negative — a settlement that mints
--      nothing and recovers nothing — makes the staleness guard stop firing,
--      and the executor then pays a venue in full for revenue that was entirely
--      reversed. That is a live money defect, executed end to end before the
--      fix, not a theoretical one.
--   2. Dropping kernel.rearm_failed_payout restores the strand: a settlement
--      payout that reaches 'failed' is destroyed as an obligation, because
--      'failed' is absorbing and kernel.close_settlement can never re-mint.
--
-- So this file exists for the case where 095 itself is found to be wrong. It is
-- not a routine undo.
--
-- FORWARD-FIX, NEVER DROP MONEY STATE. The guard below REFUSES to run while any
-- payout is still sitting in a hold this package created — 'failed_rearm'
-- (E-2), 'transfer_reversed' / 'transfer_partially_reversed' (E-4). Such a row
-- is mid-recovery: its state was reached through a verb this file removes, and
-- after the drop its hold_reason_code would name machinery that no longer
-- exists. Clear those holds through kernel.release_payout and settle the
-- payouts first, or forward-fix instead.
--
-- `set local row_security = off` before the count is the 081-087 house pattern:
-- kernel.payout is deny-all with zero policies, so a non-BYPASSRLS, non-owner
-- runner would count 0 and the guard would fail OPEN.
--
-- ORDER MATTERS, for the 091 reason: a PL/pgSQL body carries no pg_depend edge,
-- so dropping a function a live body still names leaves a compiling-but-broken
-- money function. Hence:
--   (a) kernel.get_payout_execution_context is restored to its 093 body FIRST,
--       so nothing references kernel.settlement_unbooked_refund_exposure;
--   (b) kernel.retry_held_payout is dropped BEFORE
--       kernel.settlement_maturity_hold_codes, which only it reads;
--   (c) the triggers are dropped before their functions.
-- The restored text below is 093:2266-2424 VERBATIM (the only difference from
-- 095's copy is the six-line block that called out to E-6).
--
-- ORDERING WITH THE OTHER 09x PACKAGES: 094_organization_obligation.sql
-- replaces kernel.close_settlement and creates kernel.organization_obligation;
-- this package replaces kernel.get_payout_execution_context and touches neither.
-- The two rollbacks are independent and may be run in either order.
-- Second run: NOTICE, no-op.
-- ============================================================================
begin;

do $$
declare v_stuck bigint;
begin
  if to_regprocedure('kernel.rearm_failed_payout(uuid, text, text)') is null then
    raise notice '095 rollback: already rolled back (kernel.rearm_failed_payout absent) — no-op';
    return;
  end if;
  set local row_security = off;
  select count(*) into v_stuck from kernel.payout p
   where p.hold_state <> 'none'
     and p.hold_reason_code in ('failed_rearm','transfer_reversed','transfer_partially_reversed');
  if v_stuck > 0 then
    raise exception 'rollback_refused: % payout(s) are held under a reason 095 created (failed_rearm / transfer_reversed / transfer_partially_reversed). They are mid-recovery; resolve them through kernel.release_payout and kernel.request_org_payout, or forward-fix. Dropping the machinery under a held payout leaves a hold whose reason names nothing.', v_stuck;
  end if;
end $$;

-- (a) restore the 093 body of the executor's context read, FIRST.
create or replace function kernel.get_payout_execution_context(p_payout_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_po           kernel.payout%rowtype;
  v_st           venue.settlement%rowtype;
  v_org          kernel.organization%rowtype;
  v_pinned       text;
  v_current      text;
  v_dest_indiv   boolean := false;
  -- The G2 conjunction is NOT re-implemented here; it is 10m's verdict, verbatim.
  v_maturity     jsonb;
  -- The one predicate 10m cannot carry, because it is meaningless at the mint.
  v_stale_minor  bigint := 0;
  v_code         text;
begin
  select * into v_po from kernel.payout where payout_id = p_payout_id;
  if not found then
    return null;                      -- non-enumerable: 404 at the edge
  end if;

  select * into v_st from venue.settlement where settlement_id = v_po.cause_ref;
  if v_po.payee_org_id is not null then
    select * into v_org from kernel.organization o where o.org_id = v_po.payee_org_id;
  end if;
  v_pinned  := v_po.destination_ref;
  v_current := v_org.stripe_connect_account_ref;   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)

  -- CROSS-PLANE: the personal seller Connect plane is not a payout destination
  -- for an organization settlement. Both the live column (002:25) and the 044
  -- archive are consulted, against the PINNED value — the one that would be
  -- sent. A NULL pin trivially matches neither.
  if v_pinned is not null then
    v_dest_indiv := exists (select 1 from public.profiles pr where pr.stripe_connect_id = v_pinned)
                 or exists (select 1 from public.stripe_connect_archive ar where ar.stripe_connect_id = v_pinned);
  end if;

  -- THE G2 CONJUNCTION IS NOT RE-IMPLEMENTED HERE. One definition (10m), three
  -- call sites: the mint (10d), the pending→submitted advance (10k), and this,
  -- the transfer. Re-evaluated against now(), so a refund that succeeded, a
  -- dispute that opened or an event that was cancelled AFTER the close is seen.
  v_maturity := kernel.settlement_payout_maturity(v_po.cause_ref);

  -- THE STALENESS OPERAND (H3 §5 step 4 / §7.1) — the one predicate 10m does
  -- not carry, because at the mint the lines were just written and it can only
  -- read zero. Per covered order: the settled refund exposure the ledger is
  -- ENTITLED to book, capped at the order's face value exactly as 10b caps
  -- 'refund_void', minus what has actually been lined for that order in ANY
  -- settlement. A positive remainder means money has left for the buyer that no
  -- settlement has debited, so the payout in hand is an obligation computed
  -- before that fact existed.
  --
  -- THE FACE CAP IS LOAD-BEARING, NOT DECORATION. kernel.refund.amount_minor is
  -- measured against public.payments.total = amount + buyer_fee (000:978-985),
  -- while a 'refund_void' line is capped at the order's face value because the
  -- buyer-side service fee is platform money under ruling A5. Comparing raw
  -- refund sums against refunds_minor would therefore fire on every ordinary
  -- fee-bearing refund and STRAND the venue's money — a false positive here is
  -- not conservative, it is the same permanent loss by another route.
  select coalesce(sum(x.entitled - x.lined), 0)::bigint into v_stale_minor
    from (
      select least(
               coalesce((select sum(r.amount_minor) from kernel.refund r
                          where r.payment_id = c.payment_id and r.status = 'succeeded'), 0),
               coalesce((select o.total_minor from venue."order" o
                          join kernel.payment_native pn on pn.order_id = o.order_id
                         where pn.payment_id = c.payment_id), 0))::bigint as entitled,
             coalesce((select sum(-l.amount_minor) from venue.settlement_line l
                        join kernel.refund r2 on r2.refund_id = l.cause_ref
                       where l.cause = 'refund_void' and r2.payment_id = c.payment_id), 0)::bigint as lined
        from (select distinct cp.payment_id
                from kernel.settlement_covered_payments(v_po.cause_ref) cp
               where cp.payment_id is not null) c
    ) x
   where x.entitled > x.lined;

  -- FIRST FAILING PREDICATE WINS, in causal order: identity and binding before
  -- money, money before the payee, the payee before maturity, maturity before
  -- staleness. Everything below REFUSES; nothing here is advisory.
  v_code := case
    -- ── binding: is this even a settlement payout to an organization? ──────
    when v_po.cause <> 'settlement'                        then 'cause_not_settlement'
    when v_po.payee_kind <> 'organization'
      or v_po.payee_org_id is null                         then 'payee_not_organization'
    -- ── the row's own state ───────────────────────────────────────────────
    when v_po.hold_state <> 'none'                         then 'payout_held'
    when v_po.status <> 'submitted'                        then 'payout_not_submitted'
    when v_po.stripe_transfer_ref is not null              then 'transfer_already_recorded'
    when v_po.amount_minor is null
      or v_po.amount_minor <= 0                            then 'amount_not_positive'
    when upper(coalesce(v_po.currency,'')) <> 'USD'        then 'currency_unsupported'
    -- ── the obligation ────────────────────────────────────────────────────
    when v_st.settlement_id is null                        then 'settlement_not_found'
    when v_st.org_id is distinct from v_po.payee_org_id    then 'org_mismatch'
    when v_st.status <> 'closed'                           then 'settlement_not_closed'
    when upper(coalesce(v_st.currency,'')) <> upper(coalesce(v_po.currency,''))
                                                           then 'currency_mismatch'
    when v_st.net_minor is distinct from v_po.amount_minor then 'amount_ledger_mismatch'
    -- ── the payee (H6) ────────────────────────────────────────────────────
    when v_org.org_id is null                              then 'organization_not_found'
    when v_org.status not in ('approved','active')         then 'org_not_active'
    when v_pinned is null                                  then 'destination_not_bound'
    when v_pinned !~ '^acct_[A-Za-z0-9]+$'                 then 'destination_malformed'
    when v_dest_indiv                                      then 'destination_individual_plane'
    when v_current is null                                 then 'no_payout_destination'
    when v_pinned is distinct from v_current               then 'destination_changed'
    when not coalesce(v_org.connect_transfers_active, false) then 'connect_transfers_inactive'
    when v_org.payout_destination_locked_until is not null
     and v_org.payout_destination_locked_until > now()     then 'destination_cooldown'
    -- ── maturity: 10m's verdict, adopted whole. ONE line, so this gate and
    --    the mint gate cannot disagree about what "matured" means. ──────────
    when (v_maturity ->> 'hold_reason') is not null        then v_maturity ->> 'hold_reason'
    -- ── staleness (H3 §5 step 4) ──────────────────────────────────────────
    when v_stale_minor > 0                                 then 'refund_exposure_stale'
    else null
  end;

  return jsonb_build_object(
    'payout_id',              v_po.payout_id,
    'cause',                  v_po.cause,
    'settlement_id',          v_po.cause_ref,
    'payee_kind',             v_po.payee_kind,
    'payee_org_id',           v_po.payee_org_id,
    'amount_minor',           v_po.amount_minor,
    'currency',               v_po.currency,
    'status',                 v_po.status,
    'hold_state',             v_po.hold_state,
    'hold_reason_code',       v_po.hold_reason_code,
    'stripe_transfer_ref',    v_po.stripe_transfer_ref,
    'source_transaction_ref', v_po.source_transaction_ref,   -- H3 §3: NULL on this rail, always
    'created_at',             v_po.created_at,
    -- the obligation, for the executor's own equality assertion and the audit
    'settlement_org_id',        v_st.org_id,
    'settlement_status',        v_st.status,
    'settlement_net_minor',     v_st.net_minor,
    'settlement_refunds_minor', v_st.refunds_minor,
    'settlement_currency',      v_st.currency,
    -- the payee: PINNED is what gets sent; CURRENT is what it is checked against
    'destination',              v_pinned,
    'destination_ref',          v_pinned,
    'org_connect_ref_current',  v_current,
    'org_status',               v_org.status,
    'connect_transfers_active', coalesce(v_org.connect_transfers_active, false),
    'destination_locked_until', v_org.payout_destination_locked_until,
    'destination_individual_plane', v_dest_indiv,
    -- transfer_group: the ONLY durable handle back to a transfer whose response
    -- was lost after the 24h idempotency window (H3 §6).
    'transfer_group',         'payout_' || v_po.payout_id::text,
    -- THE VERDICT. The worker consumes this; it does not re-derive it.
    'execution_eligible',     (v_code is null),
    'refusal_code',           v_code,
    'maturity_detail',        coalesce(v_maturity -> 'detail', '{}'::jsonb)
                                || jsonb_build_object('unbooked_refund_exposure_minor', v_stale_minor));
end;
$$;

revoke all on function kernel.get_payout_execution_context(uuid) from public, anon, authenticated;
grant execute on function kernel.get_payout_execution_context(uuid) to service_role;

-- (c) the guards: triggers before their functions.
drop trigger if exists tg_payout_org_payable_guard on kernel.payout;
drop trigger if exists tg_settlement_forward_only  on venue.settlement;
drop function if exists kernel.guard_payout_org_payable();
drop function if exists kernel.guard_settlement_forward_only();

-- (b) retry_held_payout reads settlement_maturity_hold_codes; drop the reader first.
drop function if exists kernel.retry_held_payout(uuid, uuid, text);
drop function if exists kernel.settlement_maturity_hold_codes();

drop function if exists kernel.rearm_failed_payout(uuid, text, text);
drop function if exists kernel.hold_payout_transfer_reversed(uuid, text, integer, integer, jsonb, text);
drop function if exists kernel.settlement_unbooked_refund_exposure(uuid);

commit;
