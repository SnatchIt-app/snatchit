-- ============================================================================
-- 096_payout_reversal_and_obligation_recovery_rollback.sql
--   REVERSES supabase/migrations/096_payout_reversal_and_obligation_recovery.sql
-- ----------------------------------------------------------------------------
-- POSTURE: BREAK-GLASS ONLY, AND IT DESTROYS RECORDED MONEY FACTS. Read this
-- before running it.
--
--   Dropping kernel.payout_reversal and kernel.organization_obligation_
--   recovery does not merely remove verbs — it deletes every Stripe transfer-
--   reversal fact and every recovery receipt 096 exists to make durable
--   (096's own header: "A REVERSAL HAS NOWHERE TO LIVE" / "A DEBT CAN ONLY BE
--   ALL-OR-NOTHING" are the defects those tables close). Once dropped, "how
--   much of payout X came back" and "how much of org Y's debt was repaid,
--   by what receipt" are unanswerable from the ledger again — exactly the
--   pre-096 state.
--
-- FORWARD-FIX, NEVER DROP MONEY STATE. The guard below REFUSES to run while
-- EITHER new table holds any row: a fact recorded there is evidence of money
-- that moved (a Stripe transfer_reversal actually observed) or a receipt a
-- human already declared, and this file has no way to preserve either once
-- the tables are gone. Forward-fix instead, or — if 096 itself is proven
-- wrong before anything has been recorded against it — run this while both
-- tables are still empty.
--
-- `set local row_security = off` before the count is the 095/081-087 house
-- pattern: both tables are RLS-on with zero policies and REVOKE ALL from
-- every role including service_role (096 R-1/R-4), so a non-BYPASSRLS,
-- non-owner runner would count 0 rows and the guard would fail OPEN.
--
-- ORDER MATTERS, for the 091/095 reason: a PL/pgSQL body carries no pg_depend
-- edge, so dropping a function a live body still names leaves a compiling-
-- but-broken money function. Hence:
--   (a) kernel.resolve_organization_obligation and kernel.org_outstanding_
--       obligation_minor are restored to their 094 bodies FIRST — 096's
--       organization_obligation_recovery_settle() trigger function is not
--       named by either 094 body, so this order is safe, and it means no
--       window exists where the re-created 094 verb's grant (service_role
--       only, authenticated revoked) coexists with a still-live 096 recovery
--       table an operator might expect it to see.
--   (b) R-7 (kernel.reconcile_payout_transfer, kernel.claim_failed_payouts_
--       for_reconcile) are dropped next: reconcile_payout_transfer's body
--       calls kernel.record_payout_reversal (R-3), so it must go BEFORE R-3.
--   (c) R-3 (kernel.record_payout_reversal) is dropped next: its body calls
--       kernel.payout_reversed_minor (the projection) and kernel.hold_
--       payout_transfer_reversed (095, untouched, NOT dropped here), so R-3
--       goes before the projection.
--   (d) R-5 (kernel.record_obligation_recovery) is dropped next: its body
--       calls kernel.obligation_outstanding_minor (the projection), so it
--       goes before that projection too.
--   (e) the two projections (kernel.payout_reversed_minor, kernel.
--       obligation_outstanding_minor) are dropped next — nothing else in
--       096 or the surviving corpus names them (org_outstanding_obligation_
--       minor was already restored to its 094 body in (a), which never
--       named kernel.organization_obligation_recovery at all).
--   (f) the triggers are dropped before their functions, on both tables.
--   (g) R-2 (the unique partial index on kernel.payout.stripe_transfer_ref)
--       is dropped — 085/095 own that column and never assumed uniqueness,
--       so nothing else references the index by name.
--   (h) the two tables themselves (kernel.organization_obligation_recovery,
--       kernel.payout_reversal) are dropped last, guard functions with them.
--
-- ORDERING WITH THE OTHER 09x PACKAGES: 094_organization_obligation.sql owns
-- kernel.organization_obligation and the two verbs restored in (a); 095_
-- payout_state_machine_recovery.sql owns kernel.get_payout_execution_context,
-- kernel.hold_payout_transfer_reversed, kernel.rearm_failed_payout and is
-- untouched by 096 and by this file. This rollback is independent of the 094
-- and 095 rollbacks and may run before, after, or without either — it never
-- reaches into 094's or 095's own tables.
--
-- The restored bodies below are 094:431-476 and 094:504-514 VERBATIM (byte-
-- for-byte the text 096 itself quotes as "094 J7-3 RE-CREATED" / "094 J7-3b
-- RE-CREATED, BODY ONLY" in its own header) — diffable against that file.
--
-- Second run: NOTICE, no-op.
-- ============================================================================
begin;

do $$
declare v_facts bigint; v_receipts bigint;
begin
  if to_regclass('kernel.payout_reversal') is null
     and to_regclass('kernel.organization_obligation_recovery') is null then
    raise notice '096 rollback: already rolled back (kernel.payout_reversal and kernel.organization_obligation_recovery both absent) — no-op';
    return;
  end if;
  set local row_security = off;
  select count(*) into v_facts    from kernel.payout_reversal;
  select count(*) into v_receipts from kernel.organization_obligation_recovery;
  if v_facts > 0 or v_receipts > 0 then
    raise exception 'rollback_refused: % payout_reversal fact(s) and % organization_obligation_recovery receipt(s) exist. Both tables are append-only records of money already observed or already declared recovered; dropping them destroys that evidence with no forward path to reconstruct it. Forward-fix instead, or run this only while both tables are empty.',
      v_facts, v_receipts;
  end if;
end $$;

-- ============================================================================
-- (a) RESTORE kernel.resolve_organization_obligation AND kernel.org_
--     outstanding_obligation_minor to their 094 bodies, FIRST.
-- ============================================================================
create or replace function kernel.resolve_organization_obligation(
  p_obligation_id uuid, p_resolution text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.organization_obligation%rowtype;
begin
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  if p_resolution not in ('recovered','written_off') then
    raise exception 'invalid_input: resolution must be recovered|written_off' using errcode = 'P0001';
  end if;
  select * into v_row from kernel.organization_obligation
   where obligation_id = p_obligation_id for update;
  if not found then
    raise exception 'not_found: obligation %', p_obligation_id using errcode = 'P0002';
  end if;
  if v_row.status = p_resolution then
    return jsonb_build_object('status','noop_replay','obligation_id', p_obligation_id);
  end if;
  if v_row.status <> 'outstanding' then
    raise exception 'state_conflict: obligation % already % — terminals are exclusive', p_obligation_id, v_row.status
      using errcode = 'P0001';
  end if;
  update kernel.organization_obligation
     set status = p_resolution,
         resolution_reason_code = coalesce(p_reason_code, p_resolution),
         resolved_by = auth.uid(), resolved_at = now(), updated_at = now()
   where obligation_id = p_obligation_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (auth.uid(), 'org_obligation.resolve', 'org_obligation', p_obligation_id,
          coalesce(p_reason_code, p_resolution),
          jsonb_build_object('status','outstanding'), jsonb_build_object('status', p_resolution));
  -- NOTE, deliberately: this verb moves NO money. `recovered` records that an
  -- off-platform payment happened; it does not collect one, does not credit a
  -- settlement, and does not release, unhold or advance any payout of any
  -- cause whatsoever. (The word for the commission payee is deliberately absent
  -- from every 094 verb BODY so that "no verb here can even name one" is a
  -- CHECKABLE property rather than a claim — pgTAP 160/F5 greps for it.)
  return jsonb_build_object('status','ok','obligation_id', p_obligation_id, 'status_now', p_resolution);
end;
$$;

create or replace function kernel.org_outstanding_obligation_minor(p_org_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(o.amount_minor)::bigint, 0::bigint)
    from kernel.organization_obligation o
   where o.org_id = p_org_id and o.status = 'outstanding';
$$;

-- Restore the 094 grant class: service_role only, authenticated revoked —
-- the reachability defect (KD P1-1) 096 R-6 fixed by grant is reintroduced
-- deliberately, since this file undoes 096 in full.
revoke all on function kernel.resolve_organization_obligation(uuid, text, text, text) from public, anon, authenticated;
grant execute on function kernel.resolve_organization_obligation(uuid, text, text, text) to service_role;
revoke all on function kernel.org_outstanding_obligation_minor(uuid) from public, anon, authenticated;
grant execute on function kernel.org_outstanding_obligation_minor(uuid) to service_role;

-- ============================================================================
-- (b) R-7 — the reconcile pair. reconcile_payout_transfer's body calls
--     kernel.record_payout_reversal, so it is dropped before R-3.
-- ============================================================================
drop function if exists kernel.reconcile_payout_transfer(uuid, text, jsonb, text);
drop function if exists kernel.claim_failed_payouts_for_reconcile(integer, integer);

-- ============================================================================
-- (c) R-3 — the reversal fact writer. Its body calls kernel.payout_reversed_
--     minor and kernel.hold_payout_transfer_reversed (095, untouched here).
-- ============================================================================
drop function if exists kernel.record_payout_reversal(uuid, text, text, integer, jsonb, text);

-- ============================================================================
-- (d) R-5 — the human recovery writer. Its body calls kernel.obligation_
--     outstanding_minor.
-- ============================================================================
drop function if exists kernel.record_obligation_recovery(uuid, integer, text, text, text, text);

-- ============================================================================
-- (e) the two projections.
-- ============================================================================
drop function if exists kernel.payout_reversed_minor(uuid);
drop function if exists kernel.obligation_outstanding_minor(uuid);

-- ============================================================================
-- (f) triggers before their functions, on both new tables.
-- ============================================================================
drop trigger if exists tg_payout_reversal_guard on kernel.payout_reversal;
drop function if exists kernel.payout_reversal_guard();

drop trigger if exists tg_organization_obligation_recovery_settle on kernel.organization_obligation_recovery;
drop function if exists kernel.organization_obligation_recovery_settle();
drop trigger if exists tg_organization_obligation_recovery_guard on kernel.organization_obligation_recovery;
drop function if exists kernel.organization_obligation_recovery_guard();

-- ============================================================================
-- (g) R-2 — the unique partial index (KE F-6). 085/095 own kernel.payout and
--     never assumed uniqueness on stripe_transfer_ref; dropping the index
--     restores exactly that (known-defective) prior state.
-- ============================================================================
drop index if exists kernel.payout_stripe_transfer_ref_uq;

-- ============================================================================
-- (h) the two tables, last. Both were confirmed empty by the guard above.
-- ============================================================================
drop table if exists kernel.organization_obligation_recovery;
drop table if exists kernel.payout_reversal;

commit;
