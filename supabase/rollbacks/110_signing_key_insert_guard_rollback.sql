-- ============================================================================
-- 110_signing_key_insert_guard_rollback.sql — mechanical reversal of migration
-- 110 (M6 BEFORE INSERT guard on kernel.signing_key). MECHANICAL-REVERSIBILITY
-- REHEARSAL ONLY (production is forward-only; nothing here is a production
-- runbook). Restores the pre-110 state exactly: no insert guard, no function.
-- The 083/103 immutable UPDATE guard, the partial unique indexes, and the parked
-- lifecycle functions are untouched by 110 and therefore untouched here.
-- Idempotent: safe to run when 110 was never applied.
-- ============================================================================
begin;

drop trigger if exists tg_signing_key_insert_guard on kernel.signing_key;
drop function if exists kernel.guard_signing_key_insert();

commit;
