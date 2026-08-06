-- ONE-OFF incident remediation — 2026-08-03 payout incident.
-- ALREADY EXECUTED against production. DO NOT RUN AGAIN.
--
-- Deliberately NOT in supabase/migrations/ so no replay, CI reset, or
-- `supabase migration up` can execute it.
--
-- DESTRUCTIVE: archives and NULLs stripe_connect_id for EVERY profile that has
-- one. Production currently has 7 live Connect accounts; running this would
-- disconnect all of them from Stripe and stop their payouts. The Apple demo
-- seller (09f1ec06) is exempted from the onboarding-flag reset only.
--
-- Kept for the audit trail: this is what was done to the data, and when.

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
