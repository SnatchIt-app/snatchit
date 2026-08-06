-- 063 — take TRUNCATE away from the client roles, and stop anon executing
-- state-changing maintenance RPCs.
--
-- ── Part 1: TRUNCATE / REFERENCES / TRIGGER ─────────────────────────────────
--
-- anon and authenticated each hold TRUNCATE on 18 tables, including payments,
-- bids, listings and disputes. Row Level Security does not apply to TRUNCATE —
-- it is a table-level DDL-ish privilege, so every carefully scoped RLS policy
-- on payments is irrelevant to `TRUNCATE public.payments`, which empties it.
--
-- These grants come from the default `GRANT ALL ON ALL TABLES IN SCHEMA public
-- TO anon, authenticated` that ships with a new Supabase project; nothing in
-- this codebase asked for them. PostgREST does not expose TRUNCATE, so this is
-- not reachable with an anon JWT alone — it needs a direct Postgres connection.
-- That makes it a latent privilege, not a live hole, but there is no reason for
-- a client role to be one connection away from dropping the payments table.
--
-- REFERENCES and TRIGGER go too: they let a role attach foreign keys and
-- triggers to these tables. No client uses either.
--
-- SELECT/INSERT/UPDATE/DELETE are deliberately untouched — those are what RLS
-- governs and what the app actually needs.
--
-- ── Part 2: maintenance RPC EXECUTE ─────────────────────────────────────────
--
-- anon can currently EXECUTE:
--
--   finalize_auction(uuid)             ends any auction on demand, by id
--   auto_finalize_expired_auctions()   bulk finalize
--   cleanup_expired_reservations()     releases other buyers' reservations
--   refresh_all_seller_risk_scores()   full-table recompute, unbounded work
--   refresh_seller_risk_score(uuid)    per-seller recompute
--   check_rate_limit(uuid,text,int,int) consumes a named user's rate budget
--
-- finalize_auction is the sharp one: an unauthenticated caller can close a live
-- auction at whatever the current bid happens to be, which is a direct attack
-- on sale price. The rest are unauthenticated compute and state churn.
--
-- These are cron/maintenance entry points — they are invoked by pg_cron and by
-- Edge Functions holding the service key, never by a browser. check_rate_limit
-- is called by SECURITY DEFINER functions, which run as their owner and so do
-- not consult the caller's EXECUTE privilege.
--
-- Read-only helpers anon legitimately needs while browsing signed-out
-- (get_profile_trust_stats, is_winner, is_blocked_by_me, can_create_listing,
-- phone_verified) are left alone. Trigger functions are also left alone —
-- Postgres refuses to call them outside a trigger context regardless of grants.

-- Part 1
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public
  FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM anon, authenticated;

-- Part 2
REVOKE EXECUTE ON FUNCTION public.finalize_auction(uuid)                        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.auto_finalize_expired_auctions()              FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_reservations()                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.refresh_all_seller_risk_scores()              FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.refresh_seller_risk_score(uuid)               FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_rate_limit(uuid, text, integer, integer) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.finalize_auction(uuid)                         TO service_role;
GRANT EXECUTE ON FUNCTION public.auto_finalize_expired_auctions()               TO service_role;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_reservations()                 TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_all_seller_risk_scores()               TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_seller_risk_score(uuid)                TO service_role;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(uuid, text, integer, integer)  TO service_role;
