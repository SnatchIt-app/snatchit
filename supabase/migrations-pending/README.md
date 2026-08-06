# Pending migrations — NOT in the auto-apply path

Files here are written and reviewed but deliberately **not** applied, and are
kept out of `supabase/migrations/` so that `supabase migration up` or a CI
replay cannot apply them by accident.

## 043_profiles_select_column_restriction.sql

Revokes the remaining sensitive columns on `public.profiles` from the
`authenticated` role. Applying it today **breaks the shipped mobile app.**

Column privileges in Postgres are per-role, not per-row, so a revoked column
becomes unreadable on *every* row including the caller's own. Build 13, which
is in the field, reads its own `phone_number`, `wallet_balance` and
`stripe_connect_id` straight from the table, and reads other users'
`full_name` through the bid-history embed — where a revoked column fails the
whole PostgREST query with 42501 rather than omitting the column, emptying the
bid list and silently taking `currentBid`, bid count and the outbid banners
with it.

The safely-shippable part of 043 was already applied as migration 062, which
revoked the seven columns no client reads.

### Gate before applying

1. Ship the mobile release on branch `mobile/profile-rpc-compat` — it moves
   every self-profile read to `get_my_profile()` (SECURITY DEFINER, therefore
   unaffected by column grants) and drops `full_name` from the bid embed.
2. Wait for adoption. Build 13 has no fallback path; older installs break the
   moment this is applied.
3. Then move this file into `supabase/migrations/` and apply it.
