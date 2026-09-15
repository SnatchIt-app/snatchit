-- ============================================================================
-- 132_checkout_group_claim_rollback.sql — true inverse of 132.
-- Drops the two group-claim RPCs, then public.checkout_group_claim. No other
-- object is touched: 130's row claim, payments and listings are unchanged.
-- ORDER: roll the create-payment-intent edge back to the pre-132 version FIRST.
-- The 132 edge fails closed (503) when these RPCs are absent, so rolling back
-- the migration under it stops checkout; the pre-132 edge never calls them.
-- Production is forward-only by policy; this needs its own authorization.
-- ============================================================================
begin;

drop function if exists public.release_checkout_group(uuid, uuid, text, uuid);
drop function if exists public.claim_checkout_group(uuid, uuid, text);
drop table if exists public.checkout_group_claim;

commit;
