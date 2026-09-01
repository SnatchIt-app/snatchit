-- ============================================================================
-- 084_kernel_tickets_late_binding_fks — Phase-2 package 084 (family G2, ADOPT).
-- Frozen source: phase2-architecture-v2 · PACKAGE_REGISTRY §084 · plan §8/084 ·
-- schema §1.6 (the two FK rows) · §0.4 adopt discipline. Depends: 079, 081, 083.
--
-- THE ADOPT STEP, AND NOTHING ELSE. kernel.tickets (079) was born unable to
-- carry these two outgoing FKs — their targets are an 081 table and an 083
-- table. Now both exist, the forward reference closes:
--   fk_tickets_ticket_type  (ticket_type_id) -> venue.ticket_type   ON DELETE RESTRICT
--   fk_tickets_signing_key  (signing_key_id) -> kernel.signing_key  ON DELETE RESTRICT
-- Each ADD CONSTRAINT ... NOT VALID, then VALIDATE CONSTRAINT — trivial on the
-- empty table; the pattern is the standing discipline for the populated case
-- (NOT VALID takes a brief ShareRowExclusive; VALIDATE only ShareUpdateExclusive).
--
-- PURITY INVARIANT (registry §084): this package creates ZERO relations and
-- ZERO routines — no tables, no functions, no RLS, no triggers, no indexes,
-- no grants, no flags. That purity is what makes its rollback UNCONDITIONALLY
-- reversible (DROP CONSTRAINT ×2, valid forever, production rows included) —
-- the only package in the chain with that property. NOTHING MAY BE ADDED TO IT.
--
-- unit_row_id gets NO FK (C42): its target venue.inventory_unit is EXT — never
-- built in MVP. Enabling assigned seating later adds that FK as ANOTHER adopt
-- step (a future package of exactly this shape), not as an edit to this one.
-- ============================================================================

begin;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'kernel.tickets'::regclass and conname = 'fk_tickets_ticket_type'
  ) then
    alter table kernel.tickets
      add constraint fk_tickets_ticket_type
      foreign key (ticket_type_id) references venue.ticket_type(ticket_type_id)
      on delete restrict
      not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'kernel.tickets'::regclass and conname = 'fk_tickets_signing_key'
  ) then
    alter table kernel.tickets
      add constraint fk_tickets_signing_key
      foreign key (signing_key_id) references kernel.signing_key(key_id)
      on delete restrict
      not valid;
  end if;
end $$;

-- VALIDATE is a no-op on an already-validated constraint — re-runnable.
alter table kernel.tickets validate constraint fk_tickets_ticket_type;
alter table kernel.tickets validate constraint fk_tickets_signing_key;

commit;
