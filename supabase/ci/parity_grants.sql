-- ============================================================================
-- supabase/ci/parity_grants.sql — PRIVILEGE PARITY BOOTSTRAP FOR CI ONLY
--
-- THIS IS NOT A MIGRATION AND MUST NEVER BE APPLIED TO PRODUCTION.
-- It is applied to the freshly-replayed CI database, after the migration chain,
-- so the pgTAP security suite tests the SAME privilege surface production has.
--
-- WHY THIS FILE EXISTS (finding REPLAY-1)
-- Production's table privileges do not come from the migration chain. They come
-- from Supabase's environment bootstrap — migration 063 says so outright:
-- "These grants come from the default GRANT ALL ON ALL TABLES IN SCHEMA public".
-- There is no GRANT for public.listings anywhere in the 84 migrations.
--
-- Measured on the fresh CI stack (2026-08-27):
--   anon           1 table  (SELECT only)
--   authenticated  2 tables (SELECT only)
--   service_role  27 tables (REFERENCES, TRIGGER, TRUNCATE only — no SELECT)
--   pg_default_acl holds entries for SEQUENCES only; none for TABLES.
-- Measured on production the same day:
--   anon 19 · authenticated 20 · service_role 27, each SELECT+INSERT+UPDATE+DELETE.
--
-- Consequence this compensates for: without it, "anon cannot read X" passes
-- because the GRANT is absent, not because RLS works — a vacuous green across
-- most of the suite, which is worse than a red one.
--
-- GRANT ONLY, NEVER REVOKE. public.profiles deliberately has no table-level
-- grant here: migrations 041/052/062/068 install COLUMN-level grants on it, and
-- a table-level REVOKE would silently destroy them. The allow-lists below are
-- production's actual state (27 tables; 8 withheld from anon, 7 from
-- authenticated), so absence from a list is itself the deny.
--
-- REPLAY-1 remains OPEN: source still cannot rebuild production's authorization
-- surface. Rebuilding production from this repo today would produce a database
-- in which the application cannot read its own tables. Fixing that properly
-- means encoding grants in a migration, which is a separate owner decision.
-- ============================================================================

-- service_role: full DML on every table (it already holds REFERENCES/TRIGGER/TRUNCATE).
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_users TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ambassador_applications TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.auth_audit_sweep_state TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bids TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dispute_resolutions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.disputes TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.investor_leads TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.listings TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_decisions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_policy TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_tokens TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.rate_limits TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reports TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_listings TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_flags TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_risk_scores TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.stripe_connect_archive TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.stripe_webhook_events TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transfer_notifications TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transfers TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_blocks TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.venue_partnership_inquiries TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.webhook_retries TO service_role;

-- anon: 19 of 27 tables. Withheld: admin_users, auth_audit_sweep_state, dispute_resolutions, notifications, profiles, rate_limits, stripe_webhook_events, transfer_notifications.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ambassador_applications TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bids TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.disputes TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.investor_leads TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.listings TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_decisions TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_policy TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_tokens TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reports TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_listings TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_flags TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_risk_scores TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.stripe_connect_archive TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transfers TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_blocks TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.venue_partnership_inquiries TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.webhook_retries TO anon;

-- authenticated: 20 of 27 tables. Withheld: admin_users, auth_audit_sweep_state, dispute_resolutions, profiles, rate_limits, stripe_webhook_events, transfer_notifications.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ambassador_applications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bids TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.disputes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.investor_leads TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.listings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_decisions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payout_policy TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_tokens TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reports TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_listings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_flags TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_risk_scores TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.stripe_connect_archive TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transfers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_blocks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.venue_partnership_inquiries TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.webhook_retries TO authenticated;
