-- =============================================================================
-- Migration 019: Create sentinel user for anonymized financial records
-- =============================================================================
-- The delete-account edge function replaces buyer_id/seller_id with this
-- sentinel UUID before deleting the auth user. This preserves NOT NULL
-- constraints on payments and transfers tables while removing PII.
--
-- Safe to re-run: uses ON CONFLICT DO NOTHING.
-- =============================================================================

-- 1. Create the sentinel auth user
--    instance_id and aud match Supabase's defaults for the authenticated role.
INSERT INTO auth.users (
  id,
  email,
  raw_app_meta_data,
  raw_user_meta_data,
  role,
  instance_id,
  aud,
  created_at,
  updated_at
)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  'deleted@snatchit.internal',
  '{"provider":"email","providers":["email"]}',
  '{}',
  'authenticated',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  now(),
  now()
)
ON CONFLICT (id) DO NOTHING;

-- 2. Create the matching profile row
--    The handle_new_user trigger may or may not fire depending on whether
--    the INSERT above was a no-op, so we explicitly insert here.
INSERT INTO public.profiles (id, display_name)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  'Deleted User'
)
ON CONFLICT (id) DO NOTHING;
