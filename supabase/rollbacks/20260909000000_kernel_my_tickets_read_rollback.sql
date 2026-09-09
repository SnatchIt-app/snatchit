-- ============================================================================
-- 20260909000000_kernel_my_tickets_read_rollback.sql
-- Reverses 20260909000000_kernel_my_tickets_read.sql.
--
-- The migration is purely additive (one read-only function + its grant), so the
-- rollback simply drops the function. No table, RLS, trigger, grant on any
-- existing object, or data was changed by 110, so nothing else is restored.
-- Safe to run whether or not 110 was applied (IF EXISTS).
-- ============================================================================

drop function if exists public.get_my_tickets();
