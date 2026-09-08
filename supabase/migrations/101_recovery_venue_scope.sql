-- ============================================================================
-- 101_recovery_venue_scope.sql — close the cross-venue obligation-recovery hole.
--
-- WHAT THIS MIGRATION IS. A single body-only re-creation of
-- kernel.organization_obligation_recovery_guard() (096:518-582) that adds ONE
-- predicate: a `transfer_reversal` recovery may only discharge an obligation
-- whose ORIGINATING VENUE is the same venue whose payout was reversed. Nothing
-- else in the chain is modified. Replay-safe (create or replace / drop trigger
-- if exists). No new object, no new column, no grant change, no public-schema
-- object — Gate-2 is untouched and the kernel function census does not move.
--
-- ── THE DEFECT (adversarial finding ADV P0-1) ───────────────────────────────
-- 096's guard verified the reversed payout's ORGANISATION (`payee_org_id =
-- obligation.org_id`) but NOT its venue. Executed end to end: an organisation
-- with two venues could mark Venue A's `settlement_shortfall` obligation
-- `recovered` by citing a `trr_` from a transfer reversal of Venue B's payout —
-- i.e. Venue B's money recovering Venue A's debt. That is exactly the default
-- cross-venue netting ruling G5 forbids ("Venue A's debt must not silently
-- consume Venue B's earnings even if both belong to the same organization").
-- The legal debtor stays the organisation; the RECOVERY SOURCE is venue-scoped
-- to the originating venue (owner direction 2026-09-03, G5).
--
-- ── WHY THE VENUE IS DERIVABLE, AND WHY THIS IS SAFE ────────────────────────
-- 097 added kernel.organization_obligation.venue_id (NOT NULL for every
-- settlement_shortfall — it is the closed settlement's venue — and derived for
-- unlined_reversal). A kernel.payout_reversal only ever exists on a
-- cause='settlement', payee_kind='organization' payout (kernel.record_payout_
-- reversal refuses anything else), so the reversed payout's cause_ref IS a
-- venue.settlement id, and that settlement carries venue_id NOT NULL (087). The
-- guard therefore joins trr_ → payout_reversal → payout → settlement → venue_id
-- and compares it to the obligation's own venue.
--
-- FAIL CLOSED. If the obligation carries no venue (a data shape 097 does not
-- produce for a settlement_shortfall, but the column is nullable), a
-- transfer_reversal recovery is REFUSED rather than allowed org-wide — a
-- venue-scoped recovery whose venue cannot be established is not a venue-scoped
-- recovery. `manual` recoveries are untouched: they are an explicit, audited,
-- off-platform receipt against ONE named obligation and do not consume any
-- other venue's on-platform earnings, so they carry no cross-venue hazard.
--
-- Every other line of 096's guard — the append-only refusal, the obligation
-- lock, the write-off refusal, the currency match, the Σ ≤ debt cap, the trr_
-- existence + org match + reversal-amount cap, the manual receipt-ref shape —
-- is reproduced verbatim. Diffable: strip the `reversal_venue_mismatch` block
-- and the two texts are identical.
-- ============================================================================
begin;

create or replace function kernel.organization_obligation_recovery_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ob        kernel.organization_obligation%rowtype;
  v_sum       bigint;
  v_rev       record;
  v_rev_venue uuid;
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
    select r.amount_minor, p.payee_org_id, p.payout_id, p.cause, p.cause_ref
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
    -- ── 101 — THE VENUE SCOPE (G5; ADV P0-1). ─────────────────────────────
    -- A payout_reversal only exists on a cause='settlement' organization
    -- payout, so cause_ref is a venue.settlement id whose venue_id is NOT NULL.
    -- The reversed venue must equal the obligation's originating venue: no
    -- default cross-venue netting.
    if v_ob.venue_id is null then
      raise exception 'precondition_failed: obligation_venue_unknown — obligation % has no originating venue; a venue-scoped transfer_reversal recovery cannot be established (fail closed)', new.obligation_id
        using errcode = 'P0001';
    end if;
    select st.venue_id into v_rev_venue from venue.settlement st where st.settlement_id = v_rev.cause_ref;
    if v_rev_venue is distinct from v_ob.venue_id then
      raise exception 'precondition_failed: reversal_venue_mismatch — % reversed a payout of venue %, the obligation originates at venue % (no cross-venue netting, ruling G5)', new.source_ref, v_rev_venue, v_ob.venue_id
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

comment on function kernel.organization_obligation_recovery_guard() is
  'BEFORE INSERT/UPDATE/DELETE on kernel.organization_obligation_recovery: append-only; obligation locked; refused after write-off; currency must match; Σ never exceeds the debt; a transfer_reversal must cite an existing trr_ on a payout of the same organization AND the same originating venue (G5 — no cross-venue netting), at most that reversal''s amount.';

revoke all on function kernel.organization_obligation_recovery_guard() from public, anon, authenticated, service_role;

drop trigger if exists tg_organization_obligation_recovery_guard on kernel.organization_obligation_recovery;
create trigger tg_organization_obligation_recovery_guard
  before insert or update or delete on kernel.organization_obligation_recovery
  for each row execute function kernel.organization_obligation_recovery_guard();

commit;
