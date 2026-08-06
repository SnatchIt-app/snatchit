-- Rollback 062 — give `authenticated` table-wide SELECT on profiles again.
--
-- This re-exposes is_admin, trust_status_override, stripe_customer_id,
-- stripe_connect_status, stripe_payouts_enabled, stripe_charges_enabled and
-- the legacy phone column to every signed-in user, on every row, because both
-- RLS SELECT policies on profiles are USING (true).
--
-- Apply only if a client turns out to read one of the seven revoked columns
-- and is failing with:
--     permission denied for column ... of relation profiles
-- The forward fix is to re-grant just that one column, not to restore the
-- table-wide grant.

GRANT SELECT ON public.profiles TO authenticated;
