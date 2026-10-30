-- ============================================================================
-- 101_recovery_venue_scope_rollback.sql — REVERSES 101.
--
-- POSTURE: BREAK-GLASS ONLY. This restores kernel.organization_obligation_
-- recovery_guard() to its 096:518-582 body, which REINTRODUCES the ADV P0-1
-- cross-venue recovery hole: a transfer reversal of Venue B's payout could
-- again mark Venue A's obligation recovered (default cross-venue netting, which
-- ruling G5 forbids). Run this only if 101 itself is found wrong; otherwise
-- forward-fix.
--
-- No data guard is needed (this re-creates a function; it drops no table and no
-- money row). The restored body is 096's verbatim.
-- ============================================================================
begin;

create or replace function kernel.organization_obligation_recovery_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ob   kernel.organization_obligation%rowtype;
  v_sum  bigint;
  v_rev  record;
begin
  if tg_op in ('UPDATE','DELETE') then
    raise exception 'append_only: kernel.organization_obligation_recovery rows are never updated or deleted — a receipt recorded is a receipt recorded' using errcode = 'P0001';
  end if;

  select * into v_ob from kernel.organization_obligation where obligation_id = new.obligation_id for update;
  if not found then
    raise exception 'not_found: obligation %', new.obligation_id using errcode = 'P0002';
  end if;
  if v_ob.status = 'written_off' then
    raise exception 'precondition_failed: obligation_written_off — obligation % was written off; a receipt after write-off is an owner item and is not recorded here', new.obligation_id
      using errcode = 'P0001';
  end if;
  if upper(coalesce(new.currency,'')) <> upper(coalesce(v_ob.currency,'')) then
    raise exception 'precondition_failed: currency_mismatch — recovery % vs obligation %', new.currency, v_ob.currency
      using errcode = 'P0001';
  end if;
  select coalesce(sum(r.amount_minor), 0)::bigint into v_sum
    from kernel.organization_obligation_recovery r where r.obligation_id = new.obligation_id;
  if v_sum + new.amount_minor > v_ob.amount_minor then
    raise exception 'precondition_failed: recovery_exceeds_debt — % already recovered + % would exceed the obligation''s %', v_sum, new.amount_minor, v_ob.amount_minor
      using errcode = 'P0001';
  end if;

  if new.source_kind = 'transfer_reversal' then
    if new.source_ref !~ '^trr_[A-Za-z0-9]+$' then
      raise exception 'invalid_input: a transfer_reversal recovery must cite a trr_… reference' using errcode = 'P0001';
    end if;
    select r.amount_minor, p.payee_org_id, p.payout_id
      into v_rev
      from kernel.payout_reversal r
      join kernel.payout p on p.payout_id = r.payout_id
     where r.stripe_reversal_ref = new.source_ref;
    if not found then
      raise exception 'not_found: reversal_not_found — no kernel.payout_reversal row carries %', new.source_ref using errcode = 'P0002';
    end if;
    if v_rev.payee_org_id is distinct from v_ob.org_id then
      raise exception 'precondition_failed: reversal_org_mismatch — % reversed a payout of organization %, the obligation belongs to %', new.source_ref, v_rev.payee_org_id, v_ob.org_id
        using errcode = 'P0001';
    end if;
    if new.amount_minor > v_rev.amount_minor then
      raise exception 'precondition_failed: recovery_exceeds_reversal — % returned %, a recovery cannot cite more', new.source_ref, v_rev.amount_minor
        using errcode = 'P0001';
    end if;
  else
    if new.source_ref is null or length(trim(new.source_ref)) < 1 or length(new.source_ref) > 128 then
      raise exception 'invalid_input: a manual recovery must cite a receipt/ticket reference of 1-128 characters' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function kernel.organization_obligation_recovery_guard() from public, anon, authenticated;

drop trigger if exists tg_organization_obligation_recovery_guard on kernel.organization_obligation_recovery;
create trigger tg_organization_obligation_recovery_guard
  before insert or update or delete on kernel.organization_obligation_recovery
  for each row execute function kernel.organization_obligation_recovery_guard();

commit;
