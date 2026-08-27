-- ============================================================================
-- supabase/ci/parity_grants.sql — PRIVILEGE PARITY BOOTSTRAP FOR CI ONLY
--
-- THIS IS NOT A MIGRATION AND MUST NEVER BE APPLIED TO PRODUCTION.
-- Applied to the freshly-replayed CI database AFTER the migration chain so the
-- pgTAP security suite tests the SAME privilege surface production has.
--
-- WHY (finding REPLAY-1): production's table privileges do not come from the
-- migration chain. Migration 063 says so outright — "These grants come from the
-- default GRANT ALL ON ALL TABLES IN SCHEMA public" — and there is no GRANT for
-- public.listings anywhere in the 84 migrations.
--   fresh CI stack : anon 1 table, authenticated 2, service_role 27 without
--                    SELECT; pg_default_acl has SEQUENCE entries only, no TABLE
--                    entries at all.
--   production     : anon 19, authenticated 20, service_role 27.
-- Without this, "anon cannot read X" passes because the GRANT is absent rather
-- than because RLS works — vacuous green across most of the suite.
--
-- FIDELITY: transcribed from production's information_schema.role_table_grants
-- on 2026-08-27, WITH ONE DELIBERATE DEPARTURE (see DRIFT-1 below). It is PER-TABLE and PER-PRIVILEGE, not a blanket grant. An
-- earlier revision granted SELECT+INSERT+UPDATE+DELETE uniformly to every
-- allow-listed table and thereby OVER-granted: it broke three assertions that
-- correctly expect public.transfers to be SELECT-only for both client roles
-- (migration 055 revoked the rest). Blanket grants in a parity fixture are how
-- a security suite quietly stops testing the real system.
--
-- GRANT ONLY, NEVER REVOKE. public.profiles gets no table-level client grant:
-- migrations 041/052/062/068 install COLUMN-level grants there and a table-level
-- REVOKE would silently destroy them. Absence from a list IS the deny.
--
-- DRIFT-1 — the one place this fixture does NOT copy production. Production
-- grants anon and authenticated DELETE/INSERT/SELECT/UPDATE on
-- public.webhook_retries, but migration 069 line 22 explicitly does
--     revoke all on public.webhook_retries from public, anon, authenticated;
-- and no migration ever grants it back. Production has drifted from source.
-- This fixture follows SOURCE, because that is what the suite exists to verify:
-- it compensates only for the environment-provided defaults source cannot
-- express, and where source IS explicit, source wins. Copying the drift instead
-- made 090's "authenticated cannot read webhook retries" fail — the suite
-- correctly reporting that the database it was handed disagreed with the code.
-- Exposure in production is nil today (RLS on, zero policies, zero rows), so it
-- is a defence-in-depth regression rather than a live leak, but it should be
-- reconciled by running 069's revoke against production. That is a production
-- privilege change and therefore owner-gated; it is NOT bundled into 071.
--
-- REPLAY-1 REMAINS OPEN: source still cannot rebuild production's authorization
-- surface. A rebuild from this repo today yields a database in which the app
-- cannot read its own tables. Encoding grants in a migration is a separate
-- owner decision and is deliberately not taken here.
-- ============================================================================

-- service_role — 27 tables, full privileges.
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.admin_users TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.ambassador_applications TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.auth_audit_sweep_state TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.bids TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.dispute_resolutions TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.disputes TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.investor_leads TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.listings TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.notification_preferences TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.notifications TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.payments TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.payout_decisions TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.payout_policy TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.profiles TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.push_tokens TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rate_limits TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reports TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.saved_listings TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.seller_flags TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.seller_risk_scores TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.stripe_connect_archive TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.stripe_webhook_events TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.transfer_notifications TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.transfers TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.user_blocks TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.venue_partnership_inquiries TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.webhook_retries TO service_role;

-- anon — 19 of 27 tables. Withheld: admin_users, auth_audit_sweep_state,
-- dispute_resolutions, notifications, profiles, rate_limits,
-- stripe_webhook_events, transfer_notifications.
GRANT DELETE, INSERT, SELECT, UPDATE ON public.ambassador_applications TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.bids TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.disputes TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.investor_leads TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.listings TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.notification_preferences TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.payments TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.payout_decisions TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.payout_policy TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.push_tokens TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.reports TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.saved_listings TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.seller_flags TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.seller_risk_scores TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.stripe_connect_archive TO anon;
GRANT SELECT ON public.transfers TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.user_blocks TO anon;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.venue_partnership_inquiries TO anon;

-- authenticated — 20 of 27 tables. Withheld: admin_users,
-- auth_audit_sweep_state, dispute_resolutions, profiles, rate_limits,
-- stripe_webhook_events, transfer_notifications.
GRANT DELETE, INSERT, SELECT, UPDATE ON public.ambassador_applications TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.bids TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.disputes TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.investor_leads TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.listings TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.notification_preferences TO authenticated;
GRANT SELECT ON public.notifications TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.payments TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.payout_decisions TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.payout_policy TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.push_tokens TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.reports TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.saved_listings TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.seller_flags TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.seller_risk_scores TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.stripe_connect_archive TO authenticated;
GRANT SELECT ON public.transfers TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.user_blocks TO authenticated;
GRANT DELETE, INSERT, SELECT, UPDATE ON public.venue_partnership_inquiries TO authenticated;
