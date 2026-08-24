-- Migration 067: remove client EXECUTE on internal / trigger / maintenance functions
--
-- Finding addressed: Supabase linter 0028/0029 (anon / authenticated can execute a
--   SECURITY DEFINER function). Under Postgres defaults every function is granted
--   EXECUTE to PUBLIC, and PostgREST then exposes it as an RPC at /rest/v1/rpc/<fn>.
--   Trigger functions and service-only maintenance helpers must not be client-callable.
--
-- Grant model used throughout: REVOKE ... FROM PUBLIC, then GRANT only to the roles that
--   genuinely call the function. This is the ONLY correct way to exclude anon/authenticated,
--   because both are members of PUBLIC — a bare `REVOKE FROM anon, authenticated` is a no-op
--   while the PUBLIC grant stands. service_role is re-granted wherever edge/cron code calls
--   the function directly, so those paths are unaffected.
--
-- Groups:
--   A. Trigger functions — revoke from PUBLIC, grant to nobody. Trigger execution runs in
--      the table-owner's context and never consults EXECUTE grants, so cron/edge writes that
--      fire these triggers are unaffected. No client ever calls them directly.
--   B. Internal / maintenance (service_role only) — revoke from PUBLIC, grant service_role.
--      Verified: is_admin() is referenced in NO RLS policy (checked pg_policy 2026-08-24),
--      so RLS evaluation by authenticated does not need the grant.
--   C. Client-facing reads reachable only when signed in — revoke from PUBLIC, grant
--      authenticated + service_role (removes anon, keeps the real callers). phone_verified()
--      is used inside the `listings: auth insert` RLS WITH CHECK, so authenticated MUST retain
--      EXECUTE or listing creation breaks.
--
-- Compatibility: verified against the live catalog, RLS policies, and edge/cron call sites
--   on 2026-08-24. MUST be validated on a scratch database (fresh bootstrap of 001..067) before
--   production apply, per the Phase 0 change-control rule — a mis-scoped service_role grant
--   here would break cron payouts or rate limiting.
-- Expected locks: catalog-row only. Runtime: milliseconds.
-- Rollback: rollbacks/067_revoke_execute_internal_functions_rollback.sql (restores PUBLIC grant).
-- Verification (after apply): re-run get_advisors(security) — 0028/0029 counts drop to only the
--   intentionally-retained authenticated RPCs; and spot-check:
--   select has_function_privilege('anon','public.notify_bid_placed()','EXECUTE');            -- false
--   select has_function_privilege('authenticated','public.validate_and_apply_bid()','EXECUTE'); -- false
--   select has_function_privilege('authenticated','public.phone_verified()','EXECUTE');       -- true
--   select has_function_privilege('service_role','public.check_rate_limit(uuid,text,integer,integer)','EXECUTE'); -- true

-- ── Group A: trigger functions (no direct caller) ───────────────────────────────
revoke execute on function public.disputes_set_updated_at()        from public;
revoke execute on function public.guard_listing_identity_columns() from public;
revoke execute on function public.guard_listing_state_columns()    from public;
revoke execute on function public.guard_proof_status()             from public;
revoke execute on function public.handle_new_user()                from public;
revoke execute on function public.handle_new_user_notification_prefs() from public;
revoke execute on function public.notify_auction_won_inbox()       from public;
revoke execute on function public.notify_bid_inbox()               from public;
revoke execute on function public.notify_bid_placed()              from public;
revoke execute on function public.notify_moderation_event()        from public;
revoke execute on function public.notify_outbid()                  from public;
revoke execute on function public.notify_transfer_created_inbox()  from public;
revoke execute on function public.notify_transfer_event()          from public;
revoke execute on function public.notify_transfer_state_inbox()    from public;
revoke execute on function public.set_updated_at()                 from public;
revoke execute on function public.sync_listing_current_bid()       from public;
revoke execute on function public.validate_and_apply_bid()         from public;

-- ── Group B: internal / maintenance (service_role only) ─────────────────────────
revoke execute on function public.is_admin()                       from public;
grant  execute on function public.is_admin()                       to service_role;
revoke execute on function public.request_is_service_role()        from public;
grant  execute on function public.request_is_service_role()        to service_role;
revoke execute on function public.check_rate_limit(uuid, text, integer, integer) from public;
grant  execute on function public.check_rate_limit(uuid, text, integer, integer) to service_role;
revoke execute on function public.refresh_seller_risk_score(uuid)  from public;
grant  execute on function public.refresh_seller_risk_score(uuid)  to service_role;
revoke execute on function public.refresh_all_seller_risk_scores() from public;
grant  execute on function public.refresh_all_seller_risk_scores() to service_role;
revoke execute on function public.cleanup_expired_reservations()   from public;
grant  execute on function public.cleanup_expired_reservations()   to service_role;
revoke execute on function public.auto_finalize_expired_auctions() from public;
grant  execute on function public.auto_finalize_expired_auctions() to service_role;

-- ── Group C: signed-in reads (remove anon, keep authenticated) ──────────────────
revoke execute on function public.finalize_auction(uuid)           from public;
grant  execute on function public.finalize_auction(uuid)           to authenticated, service_role;
revoke execute on function public.can_create_listing(uuid)         from public;
grant  execute on function public.can_create_listing(uuid)         to authenticated, service_role;
revoke execute on function public.get_profile_trust_stats(uuid)    from public;
grant  execute on function public.get_profile_trust_stats(uuid)    to authenticated, service_role;
revoke execute on function public.phone_verified()                 from public;
grant  execute on function public.phone_verified()                 to authenticated, service_role;
