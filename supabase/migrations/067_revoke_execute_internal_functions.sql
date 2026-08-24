-- Migration 067: remove client EXECUTE on internal / trigger / maintenance functions
--
-- Finding addressed: Supabase linter 0028/0029 (anon / authenticated can execute a
--   SECURITY DEFINER function). Under Postgres defaults every function is EXECUTE-able by
--   PUBLIC, and PostgREST exposes it as an RPC at /rest/v1/rpc/<fn>. Additionally, several
--   of these functions carry EXPLICIT anon/authenticated grants (confirmed by a transactional
--   dry-run against the live catalog on 2026-08-24 — a bare REVOKE FROM PUBLIC left
--   notify_bid_placed and phone_verified still anon-executable). Therefore every REVOKE below
--   strips anon + authenticated + public, and intended callers are re-granted explicitly.
--
-- Grant model:
--   A. Trigger functions — REVOKE from anon, authenticated, public; no re-grant. Trigger
--      execution runs in the table-owner context and never consults EXECUTE grants, so
--      cron/edge writes that fire these triggers are unaffected. No client calls them directly.
--   B. Internal / maintenance — REVOKE from anon, authenticated, public; GRANT service_role.
--      These run under the service role (edge/cron) or inside other SECURITY DEFINER RPCs (as
--      owner), so stripping the client grant does not affect real call paths. Verified:
--      is_admin() is referenced in NO RLS policy; no client code calls any Group B function.
--   C. Signed-in reads — REVOKE from anon, public; GRANT authenticated, service_role (removes
--      anon, keeps the real callers). phone_verified() is used in the `listings: auth insert`
--      RLS WITH CHECK, so authenticated MUST retain EXECUTE or listing creation breaks.
--
-- Validation: applied inside a rolled-back transaction against production first; resulting
--   has_function_privilege state verified to match intent for every group before this file was
--   finalized. Metadata-only (no bodies, no data). Reversible via the rollback script.
-- Expected locks: catalog-row only. Runtime: milliseconds.
-- Rollback: rollbacks/067_revoke_execute_internal_functions_rollback.sql.
-- Verification (after apply): re-run get_advisors(security) — 0028/0029 drop to only the
--   intentionally-retained authenticated RPCs; and:
--   select has_function_privilege('anon','public.notify_bid_placed()','EXECUTE');              -- false
--   select has_function_privilege('authenticated','public.validate_and_apply_bid()','EXECUTE');-- false
--   select has_function_privilege('authenticated','public.phone_verified()','EXECUTE');        -- true
--   select has_function_privilege('service_role','public.check_rate_limit(uuid,text,integer,integer)','EXECUTE'); -- true

-- ── Group A: trigger functions (no direct caller) ───────────────────────────────
revoke execute on function public.disputes_set_updated_at()        from anon, authenticated, public;
revoke execute on function public.guard_listing_identity_columns() from anon, authenticated, public;
revoke execute on function public.guard_listing_state_columns()    from anon, authenticated, public;
revoke execute on function public.guard_proof_status()             from anon, authenticated, public;
revoke execute on function public.handle_new_user()                from anon, authenticated, public;
revoke execute on function public.handle_new_user_notification_prefs() from anon, authenticated, public;
revoke execute on function public.notify_auction_won_inbox()       from anon, authenticated, public;
revoke execute on function public.notify_bid_inbox()               from anon, authenticated, public;
revoke execute on function public.notify_bid_placed()              from anon, authenticated, public;
revoke execute on function public.notify_moderation_event()        from anon, authenticated, public;
revoke execute on function public.notify_outbid()                  from anon, authenticated, public;
revoke execute on function public.notify_transfer_created_inbox()  from anon, authenticated, public;
revoke execute on function public.notify_transfer_event()          from anon, authenticated, public;
revoke execute on function public.notify_transfer_state_inbox()    from anon, authenticated, public;
revoke execute on function public.set_updated_at()                 from anon, authenticated, public;
revoke execute on function public.sync_listing_current_bid()       from anon, authenticated, public;
revoke execute on function public.validate_and_apply_bid()         from anon, authenticated, public;

-- ── Group B: internal / maintenance (service_role only) ─────────────────────────
revoke execute on function public.is_admin()                       from anon, authenticated, public;
grant  execute on function public.is_admin()                       to service_role;
revoke execute on function public.request_is_service_role()        from anon, authenticated, public;
grant  execute on function public.request_is_service_role()        to service_role;
revoke execute on function public.check_rate_limit(uuid, text, integer, integer) from anon, authenticated, public;
grant  execute on function public.check_rate_limit(uuid, text, integer, integer) to service_role;
revoke execute on function public.refresh_seller_risk_score(uuid)  from anon, authenticated, public;
grant  execute on function public.refresh_seller_risk_score(uuid)  to service_role;
revoke execute on function public.refresh_all_seller_risk_scores() from anon, authenticated, public;
grant  execute on function public.refresh_all_seller_risk_scores() to service_role;
revoke execute on function public.cleanup_expired_reservations()   from anon, authenticated, public;
grant  execute on function public.cleanup_expired_reservations()   to service_role;
revoke execute on function public.auto_finalize_expired_auctions() from anon, authenticated, public;
grant  execute on function public.auto_finalize_expired_auctions() to service_role;

-- ── Group C: signed-in reads (remove anon, keep authenticated) ──────────────────
revoke execute on function public.finalize_auction(uuid)           from anon, public;
grant  execute on function public.finalize_auction(uuid)           to authenticated, service_role;
revoke execute on function public.can_create_listing(uuid)         from anon, public;
grant  execute on function public.can_create_listing(uuid)         to authenticated, service_role;
revoke execute on function public.get_profile_trust_stats(uuid)    from anon, public;
grant  execute on function public.get_profile_trust_stats(uuid)    to authenticated, service_role;
revoke execute on function public.phone_verified()                 from anon, public;
grant  execute on function public.phone_verified()                 to authenticated, service_role;
