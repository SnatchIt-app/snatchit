-- ============================================================================
-- 089_market_bridge_view_and_late_fk_rollback.sql — REVERSES 089 (plan §8/089
-- Rollback row: REVERSIBLE — DROP VIEW + DROP CONSTRAINT). The external rail is
-- untouched (the view only ever SELECTed from public.listings); dropping the
-- view removes only the native union; dropping the FK restores 085's
-- deferred-FK shape (sale_id bare). No data lives in 089 objects. Idempotent.
-- ORDER: 089 rolls back BEFORE 088 (088's `drop table market.market_sale` is
-- blocked by this FK while it exists).
-- ============================================================================
begin;
drop view if exists market.listing_unified;
alter table kernel.payment_native drop constraint if exists fk_payment_native_sale;
commit;
