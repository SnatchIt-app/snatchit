-- =============================================================================
-- 051_storage_scope_public_read.sql
--
-- LIVE DATA EXPOSURE. `proof-docs` is a private bucket (storage.buckets.public
-- = false) holding proof-of-ownership documents and transfer/dispute evidence.
-- The code says so explicitly — CreateListingScreen.tsx: "PRIVATE bucket
-- (migration 033) — owner + admin only"; transfer/send/[id].tsx: "PRIVATE —
-- only buyer/seller/admin can read (migration 034)".
--
-- It was readable by ANYONE, including unauthenticated callers holding only the
-- publishable anon key (which ships inside both clients and is therefore public).
--
-- Cause: three legacy dashboard-generated SELECT policies on storage.objects
-- grant role `public` with no bucket filter at all —
--
--   "Allow public read avatars 1oj01fe_0"     SELECT, public,        USING (true)
--   "allow public read v2 51etwa_0"           SELECT, public,        USING (true)
--   "Allow authenticated avatar update 1oj01fe_1"
--                                             SELECT, authenticated, USING (auth.role() = 'authenticated')
--
-- RLS policies are OR-ed, so a single unqualified `USING (true)` defeats every
-- carefully scoped policy on the table. Both "proof-docs owner read" and
-- "proof-docs transfer party read" were dead letters — correct, and irrelevant.
--
-- Confirmed empirically before this migration, as role `anon`:
--   auction-media 132 rows, avatars 9 rows, proof-docs 23 rows — all readable.
--
-- A fourth policy, "allow public read 51etwa_0", uses USING (bucket_id =
-- 'true') — a bug that compares bucket_id to the string 'true'. It matches no
-- bucket and grants nothing. Dropped as dead weight, not as a fix.
--
-- FIX: drop the four legacy read policies and replace them with one policy
-- scoped to the two buckets that are genuinely public. `TO public` covers both
-- anon and authenticated, so this single policy replaces all four.
--
-- proof-docs SELECT is then governed solely by its two scoped policies, as
-- always intended:
--   "proof-docs owner read"          — uploader reads their own folder
--   "proof-docs transfer party read" — buyer/seller of the matching transfer
--
-- COMPATIBILITY — read paths audited on both clients, nothing legitimate breaks:
--   * auction-media covers render via /storage/v1/object/public/..., which
--     bypasses RLS entirely on a public bucket (web listings.ts:150,
--     SellerListings.tsx:133).
--   * auction-media .remove() (web seller-listings.ts:240, mobile
--     ListingDetailScreen.tsx:924, my-listings.tsx:162) keeps SELECT via the
--     new policy and DELETE via 048.
--   * proof-docs is only ever read through createSignedUrl by an authenticated
--     transfer party (web transfers.ts:152, mobile transfer/receive/[id].tsx:88)
--     — covered by "proof-docs transfer party read".
--   * Service-role callers (Edge Functions) bypass RLS and are unaffected.
--
-- SCOPE: read path only. storage.objects also carries unscoped INSERT and
-- UPDATE policies granting any authenticated user write access to every bucket.
-- Those are deliberately NOT touched here — mobile build 13 is in App Review,
-- and changing the write path requires verifying the upload path conventions of
-- both shipped clients first. Tracked separately for a staged 052.
--
-- No data is read, moved, or deleted by this migration. Policy definitions only.
--
-- Rollback: supabase/rollbacks/051_storage_scope_public_read_rollback.sql
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "Allow public read avatars 1oj01fe_0"        ON storage.objects;
DROP POLICY IF EXISTS "allow public read 51etwa_0"                 ON storage.objects;
DROP POLICY IF EXISTS "allow public read v2 51etwa_0"              ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated avatar update 1oj01fe_1" ON storage.objects;

DROP POLICY IF EXISTS "public read public buckets" ON storage.objects;

CREATE POLICY "public read public buckets"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id IN ('auction-media', 'avatars'));

COMMIT;
