-- ============================================================================
-- 114_signing_key_door_delivery_and_manifest_signing_context_rollback.sql —
-- mechanical reversal of migration 114 (P2-M1-DELIVERY / P2-MANIFEST-KEY).
-- MECHANICAL-REVERSIBILITY REHEARSAL ONLY (production is forward-only). Drops
-- the two service_role-only venue functions 114 added; nothing else was
-- touched (no table, no grant on kernel.signing_key, no policy). Census
-- returns to venue 85 / five-schema 294. Idempotent.
-- ============================================================================
begin;

drop function if exists venue.get_signing_keys_door(uuid,uuid,text,uuid);
drop function if exists venue.get_manifest_signing_context();

commit;
