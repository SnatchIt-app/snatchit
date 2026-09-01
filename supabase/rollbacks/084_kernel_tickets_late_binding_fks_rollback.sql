-- ============================================================================
-- ROLLBACK for 084_kernel_tickets_late_binding_fks.sql
-- POSTURE: UNCONDITIONALLY REVERSIBLE (registry §084 — the only package in the
-- chain with this property). DROP CONSTRAINT ×2 is valid forever, INCLUDING
-- with production rows present: removing an FK orphans no data and rewrites no
-- row. No refusal guard exists BY DESIGN — there is nothing to refuse over.
-- Restores the post-083 state exactly (kernel.tickets carries its three birth
-- FKs; ticket_type_id/signing_key_id revert to unconstrained NOT NULL uuids).
-- ============================================================================

begin;

alter table kernel.tickets drop constraint if exists fk_tickets_signing_key;
alter table kernel.tickets drop constraint if exists fk_tickets_ticket_type;

commit;
