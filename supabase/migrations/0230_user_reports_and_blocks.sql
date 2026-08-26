-- =============================================================================
-- Migration 023: UGC moderation — reports + user_blocks (App Store Guideline 1.2)
-- =============================================================================
-- Apple's Guideline 1.2 requires marketplaces with user-generated content to
-- provide:
--   (a) a way for users to report objectionable content,
--   (b) a way to block abusive users,
--   (c) timely moderation, and
--   (d) published contact information.
--
-- This migration delivers (a) and (b) at the data layer:
--   • public.reports     — user-submitted reports against listings or users
--   • public.user_blocks — symmetric block records (blocker hides blocked)
--   • public.is_blocked_by_me(uuid) — STABLE helper for feed filtering
--
-- (c) lives in operations / docs.  (d) is the support email on the Privacy
-- Policy + App Store Connect support URL.
--
-- Idempotent: re-running the migration is a no-op once the tables exist.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. REPORTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.reports (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_type  text        NOT NULL
                            CHECK (target_type IN ('listing','user')),
  target_id    uuid        NOT NULL,
  reason       text        NOT NULL
                            CHECK (reason IN (
                              'fraud_or_scam',
                              'counterfeit_or_invalid',
                              'inappropriate_content',
                              'misleading',
                              'harassment',
                              'other'
                            )),
  notes        text        CHECK (notes IS NULL OR char_length(notes) <= 1000),
  status       text        NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','reviewing','actioned','dismissed')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  resolved_at  timestamptz
);

CREATE INDEX IF NOT EXISTS reports_target_idx        ON public.reports (target_type, target_id);
CREATE INDEX IF NOT EXISTS reports_status_pending_idx ON public.reports (created_at DESC) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS reports_reporter_idx      ON public.reports (reporter_id, created_at DESC);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Reporters can submit their own reports.
DROP POLICY IF EXISTS "reports: reporter insert" ON public.reports;
CREATE POLICY "reports: reporter insert" ON public.reports
  FOR INSERT
  WITH CHECK (reporter_id = auth.uid());

-- Reporters can see their own reports (transparency / dedup UX).
DROP POLICY IF EXISTS "reports: reporter select own" ON public.reports;
CREATE POLICY "reports: reporter select own" ON public.reports
  FOR SELECT
  USING (reporter_id = auth.uid());

-- No client UPDATE or DELETE — only ops via service role.

-- =============================================================================
-- 2. USER_BLOCKS
-- =============================================================================
-- (blocker_id, blocked_id) composite key prevents duplicate blocks.
-- The CHECK ensures users cannot block themselves (which would otherwise
-- hide all their own listings via is_blocked_by_me).
CREATE TABLE IF NOT EXISTS public.user_blocks (
  blocker_id  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS user_blocks_blocker_idx ON public.user_blocks (blocker_id);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

-- Owner can read / insert / delete their own block records.
DROP POLICY IF EXISTS "user_blocks: owner all" ON public.user_blocks;
CREATE POLICY "user_blocks: owner all" ON public.user_blocks
  FOR ALL
  USING (blocker_id = auth.uid())
  WITH CHECK (blocker_id = auth.uid());

-- =============================================================================
-- 3. HELPER — is_blocked_by_me(seller_id)
-- =============================================================================
-- STABLE so PostgreSQL can cache results within a query.
-- SECURITY INVOKER so the policy reads auth.uid() from the caller's session.
CREATE OR REPLACE FUNCTION public.is_blocked_by_me(p_seller_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.user_blocks
     WHERE blocker_id = auth.uid()
       AND blocked_id = p_seller_id
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked_by_me(uuid) TO authenticated, anon;

COMMIT;
