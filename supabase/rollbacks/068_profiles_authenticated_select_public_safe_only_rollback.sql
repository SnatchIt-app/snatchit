-- Rollback for migration 068. Restores authenticated SELECT on the previously-exposed
-- profile columns (returns to the pre-068 posture where any signed-in user could read
-- other users' full_name/phone_number/stripe_connect_id/wallet_balance).
grant select (id, display_name, avatar_url, avatar_path, bio, created_at,
              is_verified_seller, is_verified_buyer, stripe_onboarding_complete,
              full_name, phone_number, preferred_neighborhoods,
              stripe_connect_id, wallet_balance)
  on public.profiles to authenticated;
