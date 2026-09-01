-- ============================================================================
-- ROLLBACK for 084_kernel_tickets_late_binding_fks.sql
-- POSTURE: UNCONDITIONALLY REVERSIBLE (registry §084 — the only package in the
-- chain with this property). DROP CONSTRAINT ×2 is valid forever, INCLUDING
-- with production rows present: removing an FK orphans no data and rewrites no
-- row. No refusal guard exists BY DESIGN — there is nothing to refuse over.
-- Restores the post-083 state exactly (kernel.tickets carries its three birth
-- FKs; ticket_type_id/signing_key_id revert to unconstrained NOT NULL uuids).
-- LOCKS: DROP CONSTRAINT takes a brief AccessExclusive on kernel.tickets and
-- locks both referenced tables to drop the RI triggers — no scan, no rewrite.
-- ORDERING: this rollback must run BEFORE 083's — 083's bare `drop table
-- kernel.signing_key` fails loudly (dependent fk_tickets_signing_key) while 084
-- stands. Reverse-order rollout guarantees it; the failure mode is fail-safe.
-- ============================================================================

begin;

alter table kernel.tickets drop constraint if exists fk_tickets_signing_key;
alter table kernel.tickets drop constraint if exists fk_tickets_ticket_type;

commit;
