-- ============================================================================
-- 094_organization_obligation_rollback.sql
--   REVERSES supabase/migrations/094_organization_obligation.sql
-- ----------------------------------------------------------------------------
-- POSTURE (E-151): FORWARD-FIX, NEVER DROP MONEY STATE. kernel.organization_
-- obligation is an append-only record of realized losses; a row in it is a
-- money fact that exists nowhere else (the settlement it derives from minted no
-- payout and its residue was, before 094, destroyed). The guard below therefore
-- REFUSES to run once ANY row exists — including a resolved one, because a
-- `written_off` row is the audit trail of a decision, not disposable state.
--
-- `set local row_security = off` before the count is the 081-087 house pattern:
-- a deny-all zero-policy table counts 0 for a non-BYPASSRLS, non-owner runner
-- and the guard would fail OPEN.
--
-- ORDER MATTERS. kernel.close_settlement is restored to its 093 body FIRST, so
-- that nothing references kernel.record_organization_obligation by the time the
-- verb is dropped (a PL/pgSQL body carries no pg_depend edge, so a drop would
-- otherwise leave a compiling-but-broken money function — the 091 lesson).
-- The restored text below is 093:640-854 VERBATIM.
--
-- ORDERING WITH THE OTHER 094: 094_payout_state_machine_recovery.sql does NOT
-- replace kernel.close_settlement and does not reference this table, so the two
-- rollbacks are independent. If BOTH are being rolled back, run this one first
-- (reverse chain order) only if that file has since come to read this table.
-- Second run: NOTICE, no-op.
-- ============================================================================
begin;

do $$
declare v_rows bigint;
begin
  if to_regclass('kernel.organization_obligation') is null then
    raise notice '094 rollback: already rolled back (kernel.organization_obligation absent) — no-op';
    return;
  end if;
  set local row_security = off;
  lock table kernel.organization_obligation in access exclusive mode;
  select count(*) into v_rows from kernel.organization_obligation;
  if v_rows > 0 then
    raise exception 'rollback_refused: kernel.organization_obligation holds % row(s) — a realized loss is not droppable state; forward-fix instead', v_rows;
  end if;
end $$;

-- ── 1. kernel.close_settlement restored to its 093 body (093:640-854 verbatim).
--      The `elsif v_net < 0` branch 094 added is removed; the negative residue
--      goes back to being destroyed silently, which is what rolling back means.
create or replace function kernel.close_settlement(p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_s venue.settlement%rowtype; v_c kernel.settlement_line_candidate;
  v_gross bigint; v_fees bigint; v_refunds bigint; v_net bigint;
  v_payout_id uuid; v_ids uuid[] := '{}';
  -- G2 payout-maturity operands. THE CONJUNCTION ITSELF NOW LIVES IN
  -- kernel.settlement_payout_maturity (10m) and is called from THREE sites: here
  -- at the mint, in kernel.request_org_payout immediately before the
  -- pending→submitted advance (10k), and in kernel.get_payout_execution_context
  -- immediately before the transfer (10n). It was extracted (D-1) for exactly
  -- one reason: inline, it was a CLOSE-TIME SNAPSHOT that four later state
  -- changes defeat — a refund reaching 'succeeded' after the close;
  -- catalog.cancel_event, which touches kernel.payout NOWHERE; a dispute first
  -- observed already 'lost' (record_dispute_native freezes only on an OPEN
  -- dispute, 088:804, so the freeze is inverted relative to risk); and Connect
  -- capability loss. request_org_payout re-derived NONE of the eight predicates.
  -- One definition, three call sites, so the evaluations cannot drift. The
  -- operands themselves, and their fail-toward-the-hold initialisation, moved
  -- wholesale into 10m — nothing about the gate's meaning changed here.
  v_held boolean := false; v_hold_reason text; v_hold_detail jsonb;
  v_maturity_verdict jsonb;
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
  -- generate the money lines from the THREE seams: primary revenue (093/10b),
  -- royalty + chargeback (088:319), promoter commission (090:1511).
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
      -- NAMED, never bare: this tolerates ONLY a replay of this settlement's own
      -- line. A cross-settlement duplicate (10c) raises and aborts the close.
      on conflict on constraint settlement_line_cause_uq do nothing;
    end if;
  end loop;
  if exists (select 1 from venue.settlement_line l where l.settlement_id = p_settlement_id and l.currency <> v_s.currency) then
    raise exception 'precondition_failed: settlement lines carry a currency other than the header''s' using errcode = 'P0001';
  end if;
  -- one derivation from the lines this settlement holds, by the frozen SIGN
  -- convention (E-73): credits + / debits −; refund causes are the refund bucket.
  -- net = gross − fees − refunds = Σ all lines, exactly.
  select coalesce(sum(amount_minor)  filter (where amount_minor > 0 and cause not in ('refund_void','chargeback')), 0),
         coalesce(sum(-amount_minor) filter (where amount_minor < 0 and cause not in ('refund_void','chargeback')), 0),
         coalesce(sum(-amount_minor) filter (where cause in ('refund_void','chargeback')), 0)
    into v_gross, v_fees, v_refunds from venue.settlement_line where settlement_id = p_settlement_id;
  v_net := v_gross - v_fees - v_refunds;
  -- (3) INT4 CEILING, NAMED INSTEAD OF OPAQUE. The four money columns are integer
  -- (087:52-55, frozen) while these locals are bigint, so a settlement whose gross
  -- exceeds 2^31-1 minor units (~$21.47M) raised a bare 22003 out of the UPDATE
  -- below. That rolled the whole close back, leaving the header `open` with zero
  -- lines and EVERY retry failing identically — a permanently wedged settlement
  -- whose error names nothing. Refuse first, with the remedy in the message. This
  -- is 090:1471-1473's rule ("never an opaque 22003 out of the close") applied to
  -- the header. The ceiling itself is structural — widening the columns is DDL on
  -- a frozen money table and an owner item, NOT 093.
  if v_gross > 2147483647 or v_fees > 2147483647 or v_refunds > 2147483647
     or v_net > 2147483647 or v_net < -2147483648 then
    raise exception 'precondition_failed: settlement_amount_overflow — gross %, fees %, refunds %, net % exceed the int4 money columns (schema §3.13); settle this scope as narrower periods, or widen the columns (owner item)',
      v_gross, v_fees, v_refunds, v_net using errcode = 'P0001';
  end if;
  update venue.settlement
     set status='closed', gross_minor=v_gross::integer, fees_minor=v_fees::integer,
         refunds_minor=v_refunds::integer, net_minor=v_net::integer, updated_at=now()
   where settlement_id = p_settlement_id;
  -- generate the pending payout only when there is positive net (kernel.payout
  -- amount_minor > 0). Deterministic idempotency on (cause, cause_ref, payee).
  if v_net > 0 then
    -- (2) THE PAYOUT-MATURITY GATE (G2 — docs/phase2/_impl/G2_settlement_maturity.md).
    -- A refund that succeeds AFTER this close cannot be collected: its debit lands
    -- in a settlement nobody opens, or in one that nets negative — and a negative
    -- net mints no payout and creates no receivable, because this schema has no
    -- carry-forward object. The payout is therefore MINTED (so the obligation is a
    -- durable ledger fact — ruling A3: the debt must be knowable without
    -- reconstructing it from Stripe) but minted HELD unless EVERY predicate below
    -- is satisfied, so no money can move on a partial proof.
    --
    -- ── WHAT THIS REPLACES, AND WHY ──────────────────────────────────────────
    -- The first cut of this gate was `v_held := v_refund_window is null` — the
    -- ONLY predicate was "is the config key set". Setting the key to any value
    -- released every payout immediately, with no maturity semantics implemented
    -- anywhere: an owner config value was a hidden feature flag for logic that did
    -- not exist, and the slice's own comment had to warn that SETTING the key was
    -- the dangerous act. That is inverted here. The key is now ONE CONJUNCT of a
    -- gate that also has to prove the event happened, that it happened long enough
    -- ago, and that no money is still in motion against the orders being paid for.
    --
    -- ── THE PREDICATES, ALL OF WHICH MUST HOLD TO RELEASE ────────────────────
    --   1. the maturity policy VALUE is set and non-negative;
    --   2. every money line in this settlement resolves to its payment AND its
    --      session — we must know what this money is about before we can time it;
    --   3. no covered session and no covered event is cancelled;
    --   4. the maturity INSTANT is known: at least one covered session, and every
    --      covered session carries ends_at;
    --   5. that instant plus the policy interval has ELAPSED;
    --   6. no refund against any covered payment is in a non-terminal state;
    --   7. no dispute against any covered payment is open.
    -- Any single failure holds, with its own hold_reason_code. An operand that
    -- cannot be computed is NOT assumed satisfied: all seven locals are declared
    -- pre-set to the value that holds.
    --
    -- ── WHY ends_at OF THE LAST COVERED SESSION IS THE ANCHOR ────────────────
    -- The buyer's own chargeback clock starts THERE, not at payment: Stripe states
    -- it in terms of this exact industry — "when a customer pays for a future
    -- event or service (like a vacation reservation, professional services
    -- appointment, or event ticket), the dispute window starts on the event date,
    -- not the payment date" (https://docs.stripe.com/disputes/how-disputes-work).
    -- Anchoring on payment would make a ticket bought three months early payable
    -- three months before anyone could attend. catalog.event carries NO time
    -- column at all (078:134-154) — the only instants in the schema are on
    -- catalog.event_session — and venue."order".event_session_id is NOT NULL
    -- (082:369-372), so every covered order resolves to exactly one session. That
    -- makes the anchor computable for BOTH settlement grains: event-scoped and
    -- period-scoped headers alike derive it from their OWN LINES rather than from
    -- the header's scope, so a period settlement is timed by the last session it
    -- actually paid for and not by period_end (which is nullable, bounds
    -- starts_at rather than ends_at, and can be open-ended).
    --
    -- ends_at IS NULLABLE (078:170) and catalog.create_event_session requires only
    -- starts_at (078:805-807). The corpus's ticket-expiry sweep meets the same
    -- fact and FAILS OPEN — it skips such sessions (079:490-492), which slice 40
    -- already records as an unfixed schema hole. This gate fails CLOSED on it: a
    -- session with no end has not verifiably ended, so its money does not mature.
    -- Session STATUS is deliberately not used: nothing in 076-092 ever writes
    -- event_session.status = 'completed' (the only writer of that column is
    -- 088:1793, which writes 'cancelled'), so requiring it would hold every payout
    -- forever.
    --
    -- WHY HELD RATHER THAN REFUSING THE CLOSE OR MINTING NOTHING. Refusing the
    -- close would also refuse the LINES, so the ledger would never record what the
    -- venue is owed — the opposite of A3. Minting nothing would strand the payout
    -- permanently, because close_settlement is the only minter of a
    -- cause='settlement' payout and it is forward-only (a re-close returns
    -- noop_replay above), so no later run could ever create it. The hold overlay
    -- is the corpus's own answer to exactly this shape: 090:1487-1491 mints an
    -- unfunded promoter commission 'held'/'unfunded_settlement' for the same
    -- reason. A held payout cannot be requested (087:463-465 refuses
    -- hold_state <> 'none') and cannot be advanced by
    -- kernel.mark_payout_transfer_state; kernel.release_payout (085:807,
    -- platform_risk/platform_admin, Control-5) is the contracted release path once
    -- the owner rules. The hold is therefore recoverable; an overpayment is not.
    --
    -- ── THE KEY WAS RENAMED, BECAUSE THE OLD NAME WAS A LIE ──────────────────
    -- 'settlement.refund_window_interval' named a REFUND ELIGIBILITY window — how
    -- long a buyer may still ask for money back. That policy exists, it is owned
    -- by an entirely different set of keys (refund.buyer_self_service_window_hours
    -- / refund.request_ttl_hours / refund.scanned_atom_policy, 078:1544-1551), and
    -- this value is not it. What this value actually is: HOW LONG AFTER THE EVENT
    -- THE VENUE'S MONEY MUST SIT STILL. It is a payout property, so it is spelled
    -- 'payout.settlement_maturity_interval' — and that prefix is load-bearing, not
    -- cosmetic: 078:1145-1147 puts every 'payout.%' key under DUAL CONTROL, and
    -- the key carries no declared polarity, so EVERY set of it parks for a second
    -- platform_admin (078:1268-1285). Slice 40's own caveat on the old name was
    -- that "there is no second human in the way"; under the new name there is.
    --
    -- READ AS THE HOUSE PATTERN: absent row, JSON null and unparseable value all
    -- collapse to NULL and therefore to the hold (the 081:630-639 idiom).
    -- ONE CALL, AND THE OPERANDS ARE NO LONGER RE-DERIVED HERE. Everything the
    -- commentary above describes — the config read with its absent / JSON-null /
    -- unparseable collapse to NULL, the covered set derived from THIS
    -- settlement's own lines, the causal predicate order, the
    -- first-failing-predicate-wins rule and the full detail vector — is now
    -- kernel.settlement_payout_maturity (10m), verbatim. It never raises (a
    -- raise here would roll back the whole close and the ledger would never
    -- record what the venue is owed) and it fails toward the hold on every
    -- missing operand, exactly as this block did.
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
  end if;
  -- the audit row gains `after` — ADDITIVE, and the only durable place an operator
  -- can read the WHOLE predicate vector rather than the one code that won.
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (auth.uid(), 'settlement.close', 'settlement', p_settlement_id, coalesce(p_command_key,'close'),
          jsonb_build_object('payout_hold', v_hold_reason, 'hold_predicates', v_hold_detail));
  -- net_minor is a READ-BACK of the column this function wrote (§10.2 R1-2), never a local.
  -- 'payout_hold' is ADDITIVE — every contracted key (status, payout_ids,
  -- net_minor) keeps its meaning; callers that do not read it are unaffected.
  -- 'payout_hold_detail' is additive in the same way and is NULL when nothing held.
  return jsonb_build_object('status','ok','payout_ids', v_ids,
           'net_minor', (select net_minor from venue.settlement where settlement_id = p_settlement_id),
           'payout_hold', v_hold_reason,
           'payout_hold_detail', case when v_held then v_hold_detail else null end);
end;
$$;

-- ── 2. the record and its verbs. The table drop carries its two triggers, its
--      three indexes, its RLS state and its constraints along with it.
drop function if exists kernel.org_outstanding_obligation_minor(uuid);
drop function if exists kernel.resolve_organization_obligation(uuid, text, text, text);
drop function if exists kernel.record_organization_obligation(uuid, text, uuid, text, integer, text, text, text);
drop trigger if exists tg_organization_obligation_guard on kernel.organization_obligation;
drop trigger if exists tg_organization_obligation_set_updated_at on kernel.organization_obligation;
drop table if exists kernel.organization_obligation;
drop function if exists kernel.organization_obligation_guard();

commit;
