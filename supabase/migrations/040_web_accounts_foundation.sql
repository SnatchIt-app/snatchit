-- =============================================================================
-- 040_web_accounts_foundation.sql
-- Web Phase 1A — saved listings (favorites) + user-facing notifications.
--
-- Additive only. Does not alter any existing table, column, trigger, policy,
-- or function. Does not touch auth.users, public.profiles, the
-- on_auth_user_created trigger, or the internal public.transfer_notifications
-- dedupe log (unrelated — service-role only, no user-facing content).
--
-- Adds:
--   1. saved_listings          — user <-> listing favorites (mobile + web)
--   2. notifications           — user-facing notification inbox foundation
--
-- Policy style matches the established convention (see push_tokens,
-- notification_preferences): "table: purpose" naming, bare auth.uid()
-- (no `select` wrapper — this codebase does not use that optimization
-- elsewhere, so we don't introduce it here), policies default to role
-- `public` and are scoped correctly by the auth.uid() predicate itself.
--
-- Rollback: DROP TABLE IF EXISTS public.saved_listings, public.notifications;
-- Both tables are new and empty until this ships, so rollback is safe and
-- has zero blast radius on any other table (only FKs point INTO listings /
-- auth.users, nothing points OUT to these new tables).
-- =============================================================================

BEGIN;

-- ── 1. Saved listings (favorites) ────────────────────────────────────────────
-- Available to both mobile and web — same auth.users, same listings table.
CREATE TABLE IF NOT EXISTS public.saved_listings (
  id          uuid        NOT NULL DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  listing_id  uuid        NOT NULL REFERENCES public.listings(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (user_id, listing_id)
);

COMMENT ON TABLE public.saved_listings IS
  'User favorites/watchlist. One row per (user, listing); save = insert, unsave = delete.';

ALTER TABLE public.saved_listings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "saved_listings: owner select" ON public.saved_listings
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "saved_listings: owner insert" ON public.saved_listings
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "saved_listings: owner delete" ON public.saved_listings
  FOR DELETE
  USING (user_id = auth.uid());

-- No UPDATE policy: a save is either present or absent, nothing to edit.

-- ── 2. Notifications ──────────────────────────────────────────────────────────
-- Foundation only — nothing sends into this table yet. `type` is
-- intentionally NOT constrained by a CHECK enum: future trusted server
-- functions (transfer updates, outbid alerts, etc.) will add new types over
-- time, and locking the enum here would force a migration per new type.
-- Suggested initial values (illustrative, non-binding): 'saved_listing_ending_soon',
-- 'bid_outbid', 'auction_won', 'transfer_update'.
CREATE TABLE IF NOT EXISTS public.notifications (
  id          uuid        NOT NULL DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type        text        NOT NULL CHECK (char_length(type) <= 50),
  title       text        NOT NULL CHECK (char_length(title) <= 140),
  body        text        CHECK (body IS NULL OR char_length(body) <= 1000),
  link        text        CHECK (link IS NULL OR char_length(link) <= 2048),
  metadata    jsonb       NOT NULL DEFAULT '{}'::jsonb,
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id)
);

COMMENT ON TABLE public.notifications IS
  'User-facing notification inbox. Insert is service-role only (see grants below) — normal users can read their own rows and mark them read, never create arbitrary notifications.';

CREATE INDEX idx_notifications_user_created
  ON public.notifications (user_id, created_at DESC);

CREATE INDEX idx_notifications_user_unread
  ON public.notifications (user_id, created_at DESC)
  WHERE read_at IS NULL;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Column-level grants: RLS alone only restricts ROWS, not columns. A normal
-- user must be able to flip `read_at` on their own rows but must never be
-- able to rewrite `title`/`body`/`type`/`link`/`metadata`, and must never be
-- able to INSERT a row at all (that stays service-role-only, matching the
-- pattern in 034_transfer_notifications.sql). REVOKE first — Supabase's
-- default public-schema grants would otherwise hand authenticated/anon
-- broad table privileges before RLS ever gets a say.
REVOKE ALL ON public.notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notifications TO authenticated;
GRANT UPDATE (read_at) ON public.notifications TO authenticated;

CREATE POLICY "notifications: owner select" ON public.notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "notifications: owner update read state" ON public.notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- No INSERT/DELETE policy for authenticated or anon: creation is reserved
-- for future trusted server functions using the service-role key, which
-- bypasses RLS and retains its existing default table privileges (same
-- assumption the 034 migration already relies on for transfer_notifications).

COMMIT;
