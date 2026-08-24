-- =============================================================================
-- Migration 033: Marketplace expansion — categories, platforms, venues,
--                admin system, proof-of-ownership review, moderation alerts
-- =============================================================================
-- Companion code: TRANSFER_METHOD_RESEARCH.md (official-source platform list),
-- src/constants/{categories,neighborhoods}.ts, src/lib/platformInstructions.ts,
-- supabase/functions/notify-report.
--
-- 1. listings.category          — Snatch It is a full event marketplace.
-- 2. ticket_platform CHECK      — expanded 6 → 16 confirmed platforms.
-- 3. listings.proof_status      — manual admin review MVP for ownership proof.
-- 4. admin_users + is_admin()   — single-allowlist admin system. NOT client-
--                                 controlled: RLS-on with NO client policies;
--                                 only service_role (bypasses RLS) can write.
-- 5. proof-docs storage bucket  — PRIVATE; owner upload/read; admin via
--                                 service role. Proof images never public.
-- 6. Moderation notifications   — AFTER INSERT on reports / dispute freeze on
--                                 transfers → pg_net → notify-report edge fn
--                                 (auth via Vault service_role_key, same
--                                 pattern as the transfer-expiry cron).
--                                 Failures NEVER block the user action.
--
-- Idempotent. No changes to payments / Stripe / transfer state machines.
-- =============================================================================

BEGIN;

-- ── 1. Event category ────────────────────────────────────────────────────────
ALTER TABLE public.listings ADD COLUMN IF NOT EXISTS category text;

UPDATE public.listings SET category = 'nightlife' WHERE category IS NULL;

ALTER TABLE public.listings ALTER COLUMN category SET DEFAULT 'nightlife';
ALTER TABLE public.listings ALTER COLUMN category SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'listings_category_check') THEN
    ALTER TABLE public.listings ADD CONSTRAINT listings_category_check
      CHECK (category IN ('nightlife','clubs','concerts','festivals',
                          'sports','music','special_events','other'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS listings_category_idx ON public.listings (category);

-- ── 2. Ticket platform expansion (research-confirmed platforms only) ────────
ALTER TABLE public.listings DROP CONSTRAINT IF EXISTS listings_ticket_platform_check;
ALTER TABLE public.listings ADD CONSTRAINT listings_ticket_platform_check
  CHECK (ticket_platform IN (
    'dice','eventbrite','posh','axs','ticketmaster','other',
    'seatgeek','tixr','fever','shotgun','universe',
    'see_tickets','mlb_ballpark','stubhub','vivid_seats','gametime'
  ));

-- ── 3. Proof-of-ownership review state (manual admin MVP) ───────────────────
-- Listings stay live immediately (TestFlight decision — does not break the
-- tested create→bid→buy flows). The badge in the app shows ONLY when an
-- admin sets proof_status = 'approved' via service role. 'rejected' is the
-- ops signal to cancel the listing / contact the seller.
ALTER TABLE public.listings ADD COLUMN IF NOT EXISTS proof_status text;

UPDATE public.listings SET proof_status = 'pending_review' WHERE proof_status IS NULL;

ALTER TABLE public.listings ALTER COLUMN proof_status SET DEFAULT 'pending_review';
ALTER TABLE public.listings ALTER COLUMN proof_status SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'listings_proof_status_check') THEN
    ALTER TABLE public.listings ADD CONSTRAINT listings_proof_status_check
      CHECK (proof_status IN ('pending_review','approved','rejected'));
  END IF;
END $$;

-- Clients must NEVER set/modify proof_status (no self-verification).
-- The listing-state guard trigger may not know this column, so add a
-- dedicated guard: only service_role / postgres may change it.
CREATE OR REPLACE FUNCTION public.guard_proof_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.proof_status IS DISTINCT FROM OLD.proof_status THEN
    IF current_setting('request.jwt.claim.role', true) NOT IN ('service_role')
       AND session_user NOT IN ('postgres') THEN
      RAISE EXCEPTION 'proof_status can only be changed by Snatch It review';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_proof_status ON public.listings;
CREATE TRIGGER trg_guard_proof_status
  BEFORE UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_proof_status();

-- ── 4. Admin system — allowlist table, server-side only ─────────────────────
CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  label      text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- RLS ON with NO policies = no client (anon/authenticated) can read or write.
-- service_role bypasses RLS; that is the ONLY write path. No self-promotion
-- is possible from the app by construction.
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_users FROM PUBLIC, anon, authenticated;

-- Seed: the official admin account "SNATCH IT APP ADMIN"
-- (profiles.id verified in production: 2b117757-f4e3-41c1-b7df-68a4502d0fba)
-- Gate-2 fix: guard on auth.users existence so a FRESH/staging DB (where this
-- production user does not exist) does not hit the admin_users→auth.users FK and
-- roll back the whole migration. This is a NO-OP on production (the row already
-- exists) — it only makes the migration bootstrap-safe. The admin allowlist is an
-- intentionally environment-specific object (prod has one admin; fresh envs have none).
INSERT INTO public.admin_users (user_id, label)
SELECT '2b117757-f4e3-41c1-b7df-68a4502d0fba', 'SNATCH IT APP ADMIN'
WHERE EXISTS (SELECT 1 FROM auth.users WHERE id = '2b117757-f4e3-41c1-b7df-68a4502d0fba')
ON CONFLICT (user_id) DO NOTHING;

-- App-side check: lets the signed-in user ask "am I an admin?" (and nothing
-- else — it only ever evaluates auth.uid(), never an arbitrary user).
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid());
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;

-- ── 5. Private storage bucket for ownership proofs ──────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('proof-docs', 'proof-docs', false)
ON CONFLICT (id) DO NOTHING;

-- Owner-only access: path convention <userId>/proofs/<ts>.<ext> — first path
-- segment must equal auth.uid(). Admin review reads via service role
-- (bypasses RLS). No public read policy exists → never publicly fetchable.
DROP POLICY IF EXISTS "proof-docs owner insert" ON storage.objects;
CREATE POLICY "proof-docs owner insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'proof-docs'
              AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "proof-docs owner read" ON storage.objects;
CREATE POLICY "proof-docs owner read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'proof-docs'
         AND (storage.foldername(name))[1] = auth.uid()::text);

-- ── 6. Moderation notifications (reports + dispute freeze) ──────────────────
-- Fire-and-forget: wraps net.http_post in an exception handler so a
-- notification failure can NEVER block a report insert or dispute update.
CREATE OR REPLACE FUNCTION public.notify_moderation_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key     text;
  v_event   text;
  v_payload jsonb;
BEGIN
  -- Build event payload
  IF TG_TABLE_NAME = 'reports' THEN
    v_event   := 'report_created';
    v_payload := jsonb_build_object(
      'event',        v_event,
      'report_id',    NEW.id,
      'reporter_id',  NEW.reporter_id,
      'target_type',  NEW.target_type,
      'target_id',    NEW.target_id,
      'reason',       NEW.reason
    );
  ELSIF TG_TABLE_NAME = 'transfers' THEN
    v_event   := 'dispute_opened';
    v_payload := jsonb_build_object(
      'event',        v_event,
      'transfer_id',  NEW.id,
      'listing_id',   NEW.listing_id,
      'buyer_id',     NEW.buyer_id,
      'seller_id',    NEW.seller_id,
      'reason',       COALESCE(NEW.dispute_reason, 'unspecified')
    );
  ELSE
    RETURN NEW;
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_key
      FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/notify-report',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type',  'application/json'
        ),
        body    := v_payload
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Never block the user action because a notification failed.
    RAISE WARNING 'notify_moderation_event: % notification failed: %', v_event, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_report_created ON public.reports;
CREATE TRIGGER trg_notify_report_created
  AFTER INSERT ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.notify_moderation_event();

DROP TRIGGER IF EXISTS trg_notify_dispute_opened ON public.transfers;
CREATE TRIGGER trg_notify_dispute_opened
  AFTER UPDATE OF status ON public.transfers
  FOR EACH ROW
  WHEN (NEW.status = 'disputed' AND OLD.status IS DISTINCT FROM 'disputed')
  EXECUTE FUNCTION public.notify_moderation_event();

COMMIT;

-- =============================================================================
-- POST-DEPLOY (manual, not in this migration):
--   1. supabase functions deploy notify-report
--   2. supabase secrets set RESEND_API_KEY=<key>  EMAIL_ENABLED=true \
--        EMAIL_FROM="Snatch It <no-reply@snatchitapp.com>" \
--        ADMIN_EMAIL="support@snatchitapp.com"
--      (EMAIL_ENABLED defaults to OFF — emails are skipped unless explicitly
--       enabled, so tests never send mail.)
--   3. Verify: insert a test report → check edge function logs.
-- VERIFICATION:
--   SELECT is_admin();                       -- as admin user → true
--   SELECT COUNT(*) FROM admin_users;        -- = 1 (service role only)
--   has_function_privilege('anon','public.is_admin()','EXECUTE')  -- false
-- =============================================================================
