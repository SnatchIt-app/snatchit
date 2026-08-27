-- Rollback for 073.
--
-- WARNING: THIS RESTORES SEC-3 — UNBOUNDED SIZE AND UNRESTRICTED CONTENT TYPE
-- ON TWO WORLD-READABLE BUCKETS.
--
-- ── Does it exactly restore prior production? YES, for production. ──────────
-- Read from the production catalog on 2026-08-27, before 073 was written:
--   auction-media  file_size_limit NULL  allowed_mime_types NULL
--   avatars        file_size_limit NULL  allowed_mime_types NULL
--   proof-docs     file_size_limit NULL  allowed_mime_types NULL
-- 073 changed those six values and nothing else — no grant, no policy, no
-- trigger, no object, no public/private flag. Setting all six back to NULL
-- returns the PRODUCTION database to byte-for-byte the state it held before.
-- This rollback is exact for production, not approximate.
--
-- ── Does it restore prior state EVERYWHERE? NO. Read this before running it
-- ── against a non-production database. ──────────────────────────────────────
-- A freshly replayed chain is NOT the same as production here, which is the
-- whole reason 073 exists. 000_baseline_schema.sql already declares
--   auction-media 10485760 {image/jpeg,image/png,image/webp,image/heic}
--   avatars        5242880 {image/jpeg,image/png,image/webp,image/heic}
-- so on a fresh database those two buckets are ALREADY restricted before 073
-- runs (only proof-docs is NULL/NULL there). Production escaped that because
-- both INSERTs carry ON CONFLICT (id) DO NOTHING and the buckets had been
-- created in the Storage UI first.
--
-- So on a fresh/CI/branch database this file does NOT undo 073 — it goes
-- FURTHER than 073 ever did, stripping limits that 000 put there. If you need
-- to unwind 073 on such a database, run only the proof-docs statement and
-- restore the other two to 000's values instead of NULL.
--
-- ── What it reopens, stated plainly ─────────────────────────────────────────
-- NULL in either column means "no restriction" to the Storage API. With these
-- six values back to NULL, any authenticated user — signup is open, so that is
-- anyone — can again:
--   * Upload objects of ARBITRARY SIZE. The three INSERT policies (033/053)
--     scope writes to `(storage.foldername(name))[1] = auth.uid()::text`: they
--     constrain WHERE a user writes, never WHAT or HOW MUCH. Storage and egress
--     cost is then attacker-controlled, and 049 lets the uploader delete only
--     UNREFERENCED objects — attaching one to a listing makes it undeletable by
--     the account that uploaded it.
--   * Upload ARBITRARY CONTENT TYPES, including text/html and image/svg+xml,
--     into auction-media and avatars — both `public = true`, both covered by
--     the policy "public read public buckets" whose roles are `public` with no
--     auth check at all. That is script execution on the project's storage
--     origin and arbitrary file hosting (malware, phishing, warez) from a
--     snatchit-branded URL. web/src/lib/evidence-upload.ts closed the CLIENT
--     half of this for transfer evidence; with the bucket half gone, a direct
--     Storage API call that skips that module lands the file anyway.
--   * Upload application/pdf and any other document type into the two public
--     buckets, which 073 restricted to the private proof-docs bucket only.
--
-- ── Prefer a narrower forward fix ───────────────────────────────────────────
-- The realistic reason to reach for this file is a legitimate upload being
-- refused — a Storage API 413 (payload too large) or 415 (invalid mime type)
-- surfaced through src/hooks/useImageUpload.ts, src/lib/avatarImage.ts,
-- web/src/lib/create-listing.ts or web/src/lib/transfers.ts. Every value in 073
-- equals the limit its client already enforces, so that would mean a client
-- gained a type or a size the bucket did not. The correct response is a forward
-- migration raising THAT ONE limit or adding THAT ONE MIME type, in the same PR
-- as the client change — not removing every restriction on all three buckets.
-- Treat a full rollback as an incident: the window it opens is SEC-3 itself.
--
-- Neither 073 nor this file touches stored objects. These columns gate NEW
-- uploads only; nothing already in a bucket is affected either way.

BEGIN;

UPDATE storage.buckets
   SET file_size_limit    = NULL,
       allowed_mime_types = NULL
 WHERE id IN ('auction-media', 'avatars', 'proof-docs');

COMMIT;
