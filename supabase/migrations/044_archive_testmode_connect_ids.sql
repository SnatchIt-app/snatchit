-- 044_archive_testmode_connect_ids.sql
-- 2026-08-03 payout incident: every profiles.stripe_connect_id predates the
-- live-key cutover and exists ONLY in Stripe test mode. Stripe (live key):
--   "The account acct_1TX...oHgF was a test account created with a testmode
--    key, and therefore can only be used with testmode keys."
-- Live GET /v1/accounts returns zero connected accounts. A live Transfer to
-- any of these ids can never succeed, which surfaced to the buyer as
-- "Payout to seller failed" on confirm-and-release.
--
-- This migration:
--   1. Archives every test-mode Connect id (audit trail — ids are never lost).
--   2. Nulls profiles.stripe_connect_id so the existing create-connect-account
--      flow mints a fresh LIVE Express account on next payout setup.
--   3. Resets stripe_onboarding_complete = false for real sellers so the app
--      routes them through live onboarding again.
--   EXCEPTION: the App Review demo seller (09f1ec06-...) keeps
--   stripe_onboarding_complete = true. Listing creation is gated on that flag
--   (CreateListingScreen two-tier check) and Apple's review notes promise the
--   seller account demonstrates listing creation. Demo-seller payouts are
--   intentionally impossible; confirm-and-release now records them as
--   manual_review instead of failing the buyer.

CREATE TABLE IF NOT EXISTS stripe_connect_archive (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id        uuid        NOT NULL REFERENCES profiles(id),
  stripe_connect_id text        NOT NULL,
  reason            text        NOT NULL,
  archived_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE stripe_connect_archive ENABLE ROW LEVEL SECURITY;
-- No policies: service-role only. Clients never read this table.

INSERT INTO stripe_connect_archive (profile_id, stripe_connect_id, reason)
SELECT id, stripe_connect_id,
       'test-mode account unusable with live key (2026-08-03 payout incident)'
FROM profiles
WHERE stripe_connect_id IS NOT NULL;

UPDATE profiles
SET stripe_connect_id = NULL,
    stripe_onboarding_complete = CASE
      WHEN id = '09f1ec06-2bd5-45de-8851-2dd8af08d4eb' THEN stripe_onboarding_complete
      ELSE false
    END
WHERE stripe_connect_id IS NOT NULL;
