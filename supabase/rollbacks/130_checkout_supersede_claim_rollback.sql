-- ============================================================================
-- 130_checkout_supersede_claim_rollback.sql — true inverse of 130.
-- Drops the two claim RPCs, then the two nullable claim columns on
-- public.payments. No other object is touched; no payment status, money or
-- identity column is involved. In-flight claims simply disappear: the edge
-- degrades to PR #64's unclaimed behaviour when the RPC is absent (PGRST202).
-- Production is forward-only by policy; this needs its own authorization.
-- ============================================================================
begin;

drop function if exists public.release_checkout_supersede(uuid, uuid);
drop function if exists public.claim_checkout_supersede(uuid, uuid, uuid);

alter table public.payments
  drop column if exists supersede_claimed_at,
  drop column if exists supersede_claim_token;

commit;
