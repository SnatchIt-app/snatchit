-- ============================================================================
-- 20260910120000_venue_api_read_views.sql — a narrow, read-only API surface for
-- the venue dashboard (slice 1: events list + event setup, read side).
--
-- WHAT THIS MIGRATION IS. Additive only. Creates schema `venue_api` holding six
-- SECURITY INVOKER views over the Phase-2 catalog/venue tables, projecting
-- ONLY columns those tables already GRANT to `authenticated` (078 §1.1–1.3,
-- §1.5; 081 §9.1/§9.2). Because the views are security_invoker, every read
-- runs as the caller: the underlying tables' RLS policies and column grants
-- apply unchanged, so the views cannot widen anything — they only make a
-- subset reachable through one small PostgREST schema instead of exposing
-- `catalog` and `venue` wholesale.
--
-- Why views and not RPCs: no SECURITY DEFINER is introduced, no search_path or
-- caller-identity question arises, and the tenant scoping is exactly the
-- existing policies (catalog_event_sel_anon/_org/_venue, venue_ticket_type_sel_*,
-- venue_inventory_batch_sel_*; the _venue arms are 080's). What a caller cannot SELECT from the table it
-- cannot SELECT from the view.
--
-- What is deliberately NOT here: inventory counters (capacity/held/sold are not
-- granted to any client role — 081 E-29 — so the view carries `remaining`
-- only), door manifest episodes, orders, scans, and every write. Those are
-- later slices with their own review.
--
-- Exposure: this migration does NOT change PostgREST `db-schemas`. Adding
-- `venue_api` to the Data API's exposed schemas is a separate, owner-approved
-- configuration step (see docs/venue-dashboard/SLICE1_HANDOFF.md).
--
-- Gate-2 (public census): unchanged — nothing is created in `public`.
-- Grants: USAGE on venue_api and SELECT on the six views to `authenticated`
-- only. `anon` gets nothing (the dashboard has no anonymous surface, spec §5),
-- even though catalog.* is anon-readable at the table level.
--
-- Rollback: supabase/rollbacks/20260910120000_venue_api_read_views_rollback.sql
-- Verification:
--   select count(*) from pg_views where schemaname='venue_api';           -- 6
--   select relname, reloptions from pg_class c join pg_namespace n on n.oid=c.relnamespace
--    where n.nspname='venue_api' and c.relkind='v';   -- every row has security_invoker=true
-- Locks/runtime: CREATE VIEW only; no table is locked beyond a brief
-- ACCESS SHARE; no rewrite.
-- ============================================================================
BEGIN;

CREATE SCHEMA IF NOT EXISTS venue_api;
COMMENT ON SCHEMA venue_api IS
  'Venue dashboard read surface. security_invoker views over catalog/venue; RLS and column grants of the base tables apply to the caller. No writes, no definer functions.';

REVOKE ALL ON SCHEMA venue_api FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA venue_api TO authenticated;
-- Deny-by-default for anything added to this schema later without an explicit grant.
ALTER DEFAULT PRIVILEGES IN SCHEMA venue_api REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Venues (catalog.venue: anon-approved read + org-plane read; 078 §1.1)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW venue_api.venues
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT v.venue_id, v.org_id, v.name, v.neighborhood, v.approval_status, v.created_at, v.updated_at
    FROM catalog.venue v;
COMMENT ON VIEW venue_api.venues IS 'catalog.venue, granted columns only; caller''s RLS applies.';

-- ---------------------------------------------------------------------------
-- Events (catalog.event: non-draft public read; drafts for the org plane and the
-- venue's own venue_manager — 078 §1.2 + 080 catalog_event_sel_venue)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW venue_api.events
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT e.event_id, e.venue_id, e.org_id, e.title, e.status, e.created_at, e.updated_at
    FROM catalog.event e;
COMMENT ON VIEW venue_api.events IS 'catalog.event, granted columns only (no description/hero); caller''s RLS applies.';

-- ---------------------------------------------------------------------------
-- Sessions (catalog.event_session: visibility resolves through the event; 078 §1.3)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW venue_api.event_sessions
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT s.session_id, s.event_id, s.session_label, s.starts_at, s.ends_at, s.doors_at,
         s.door_open_at, s.status, s.created_at, s.updated_at
    FROM catalog.event_session s;
COMMENT ON VIEW venue_api.event_sessions IS 'catalog.event_session, granted columns only; caller''s RLS applies.';

-- ---------------------------------------------------------------------------
-- Resale policies (catalog.resale_policy: every version of a visible parent; 078 §1.5)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW venue_api.resale_policies
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT p.policy_id, p.scope_kind, p.venue_id, p.event_id, p.mode, p.price_cap_bps,
         p.royalty_bps, p.version, p.effective_from, p.created_at
    FROM catalog.resale_policy p;
COMMENT ON VIEW venue_api.resale_policies IS 'catalog.resale_policy, granted columns only; caller''s RLS applies.';

-- ---------------------------------------------------------------------------
-- Ticket types (venue.ticket_type: public-visibility read; hidden types only for
-- org_owner/org_admin/venue_manager; 081 §9.1 two-tier policy)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW venue_api.ticket_types
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT t.ticket_type_id, t.event_id, t.kind, t.name, t.price_minor, t.currency, t.visibility,
         t.created_at, t.updated_at
    FROM venue.ticket_type t;
COMMENT ON VIEW venue_api.ticket_types IS 'venue.ticket_type; caller''s RLS applies (hidden types are manager/org-plane only).';

-- ---------------------------------------------------------------------------
-- Inventory batches (venue.inventory_batch: `remaining` is the ONLY counter any
-- client may read — 081 footnote 23 / E-29. capacity/held/sold are not granted
-- and are therefore not projected.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW venue_api.inventory_batches
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT b.batch_id, b.ticket_type_id, b.event_session_id, b.release_kind, b.is_sharded,
         b.remaining, b.created_at, b.updated_at
    FROM venue.inventory_batch b;
COMMENT ON VIEW venue_api.inventory_batches IS 'venue.inventory_batch, remaining only (no capacity/held/sold); caller''s RLS applies.';

GRANT SELECT ON venue_api.venues, venue_api.events, venue_api.event_sessions,
                venue_api.resale_policies, venue_api.ticket_types, venue_api.inventory_batches
  TO authenticated;

COMMIT;
