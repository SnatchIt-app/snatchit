-- 073_storage_bucket_upload_constraints.sql
-- =============================================================================
-- SECURITY FIX (SEC-3). Storage upload constraints.
--
-- THE DEFECT
-- All three storage buckets accept files of ANY size and ANY content type.
-- Read from the production catalog on 2026-08-27:
--
--   id             public  file_size_limit  allowed_mime_types  objects
--   auction-media  true    NULL             NULL                134
--   avatars        true    NULL             NULL                  9
--   proof-docs     false   NULL             NULL                 29
--
-- NULL in either column means "no restriction" to the Storage API.
--
-- WHY THE CHAIN LOOKED FINE AND PRODUCTION WAS NOT (the actual root cause)
-- 000_baseline_schema.sql ALREADY declares the correct values:
--   block 5  — auction-media: 10485760, {image/jpeg,image/png,image/webp,image/heic}
--   block 12 — avatars:        5242880, {image/jpeg,image/png,image/webp,image/heic}
-- Both statements end `ON CONFLICT (id) DO NOTHING`, and block 5 says so in a
-- comment: "Run once. Skip if you already created the bucket in the Storage UI."
-- Production's buckets WERE created in the Storage UI first (auction-media
-- 2026-02-20, avatars 2026-02-23), so both INSERTs hit the conflict and did
-- nothing — the restrictions were never applied to the live project. 033 creates
-- proof-docs with `(id, name, public)` only and never declared any limit at all.
--
-- The consequence is a silent environment split that no existing check catches:
-- a FRESH replay of the chain gets restricted auction-media / avatars buckets,
-- while production has neither. Every audit that read the migration source
-- concluded the limits were in place. They were not.
--
-- This migration is an UPDATE, not an INSERT — that is the entire point. It is
-- the only statement shape that changes a bucket row that already exists.
--
-- IMPACT (no evidence of exploitation; 172 objects total, all image/jpeg or
-- image/png, largest 6.07 MB — see the census below)
--   * Two of the three buckets are `public = true`, and the policy
--     "public read public buckets" is USING (bucket_id = ANY
--     (ARRAY['auction-media','avatars'])) with roles = public — i.e. no auth at
--     all. Anything landing there is world-readable by URL forever.
--   * The three INSERT policies (033/053) grant `authenticated` writes scoped
--     only to `(storage.foldername(name))[1] = auth.uid()::text`. They constrain
--     WHERE a user may write, and nothing about WHAT. Signup is open, so the
--     attacker is any authenticated user.
--   * Unbounded size => storage-cost and egress abuse. One account can push
--     arbitrarily many multi-GB objects into a CDN-fronted public bucket. The
--     account holds DELETE only for UNREFERENCED objects (049) — attaching an
--     object to a listing makes it undeletable by its own uploader, so the
--     platform cannot even be cleaned up by asking the user to remove it.
--   * Unrestricted MIME => arbitrary content hosting on the project's own
--     storage origin: malware, phishing pages, warez, CSAM — served from a
--     snatchit-branded URL, which is a takedown/abuse-report exposure, not just
--     a bandwidth one. `text/html` and `image/svg+xml` additionally execute
--     script on the storage origin when fetched directly. web/src/lib/
--     evidence-upload.ts already fixed the CLIENT half of that for transfer
--     evidence ("a seller could upload evidence.html with content-type
--     text/html"); nothing fixed the BUCKET half, so a direct Storage API call
--     that skips that module still lands the file.
--
-- WHAT ENFORCES THIS — read this before believing a green test
-- `file_size_limit` and `allowed_mime_types` are enforced by the STORAGE API
-- (the Node service in front of the bucket), not by Postgres. Verified against
-- the production catalog: storage.objects carries exactly two non-internal
-- triggers (protect_objects_delete, update_objects_updated_at) and exactly two
-- constraints (objects_pkey, objects_bucketId_fkey). Not one of them consults
-- storage.buckets.file_size_limit or allowed_mime_types. A direct SQL INSERT
-- into storage.objects therefore bypasses both columns entirely — before this
-- migration AND after it.
--
-- INFERENCE, not verified here: that is not a hole in practice, because the
-- client roles reach storage.objects only through the Storage API — Supabase's
-- PostgREST default exposes `public, graphql_public` and not `storage`, and no
-- SQL surface reports the running db-schemas setting, so this was NOT confirmed
-- against this project. If `storage` were ever added to that list, `anon` and
-- `authenticated` hold table-wide INSERT on storage.objects (relacl arwdDxtm)
-- and only the 033/053 folder-scoped policies would stand between a client and
-- a row with any mimetype and any metadata.size it chose. Worth confirming in
-- the dashboard; it is not something this migration can assert.
--
-- Either way it means supabase/tests/
-- 130_storage_bucket_constraints.sql proves the CONFIGURATION is set and
-- coherent, NOT that an upload is rejected. The file says so in its own header.
-- Behavioural proof would require an HTTP upload against a live Storage API,
-- which is not something the pgTAP gate can do.
--
-- WHY THE CONFIGURATION CANNOT BE REVERTED BY A CLIENT
-- `authenticated` and `anon` both hold table-wide UPDATE on storage.buckets
-- (Supabase's own bootstrap grants: relacl shows arwdDxtm for both). That grant
-- is inert only because storage.buckets has RLS ENABLED with ZERO policies —
-- a non-owner without BYPASSRLS is denied every row. That single fact is what
-- makes this migration's values durable rather than advisory, so it is asserted
-- here (fail-closed) and pinned by the test file. It is NOT changed here: it is
-- already true in production and on a fresh replay. Migration 074 owns grant
-- cleanup; this migration deliberately touches no grant.
--
-- THE VALUES, AND THE EVIDENCE FOR EACH
-- Reconciled against every upload path in the repo (all five of them) and
-- against a census of all 172 live objects.
--
--   auction-media  10485760 bytes (10 MiB)
--                  {image/jpeg, image/png, image/webp, image/heic}
--     Client authority: APP_CONFIG.MAX_IMAGE_SIZE_MB = 10 and
--     APP_CONFIG.ALLOWED_IMAGE_TYPES = exactly those four types
--     (src/config/app.ts, mirrored in packages/core/src/appConfig.ts, whose
--     comment already reads "must match Supabase storage policies").
--     Writers: src/hooks/useImageUpload.ts (mobile) derives contentType from an
--     extension whitelist ['jpg','jpeg','png','webp','heic'] -> those four MIME
--     types and no others; web/src/lib/create-listing.ts uploadListingImage
--     validates file.type against ALLOWED_IMAGE_TYPES and file.size against
--     MAX_IMAGE_SIZE_MB before uploading. Bucket == client, exactly.
--     Live data: 134 objects, 111 image/jpeg + 23 image/png, max 6 361 057 B.
--
--   avatars         5242880 bytes (5 MiB)
--                  {image/jpeg, image/png, image/webp, image/heic}
--     Client authority: APP_CONFIG.MAX_AVATAR_SIZE_MB = 5, applied by
--     src/utils/validateImage.ts when called with bucket 'avatars'.
--     Writer: src/lib/avatarImage.ts pickAndUploadAvatar — the ONLY writer;
--     the web app has no avatar upload path. Same extension whitelist, so the
--     same four MIME types.
--     Live data: 9 objects, 7 image/jpeg + 2 image/png, max 612 685 B.
--
--   proof-docs     10485760 bytes (10 MiB)
--                  {image/jpeg, image/png, image/webp, image/heic,
--                   image/heif, application/pdf}
--     Three writers, and the allowlist is the UNION of what they emit:
--       - src/hooks/useImageUpload.ts with bucket:'proof-docs'
--         (src/screens/CreateListingScreen.tsx:200 proof-of-ownership,
--         app/transfer/send/[id].tsx:92 transfer evidence) -> the four image
--         types. NOTE it calls validateImage(..., 'auction-media') at line 123
--         even for proof uploads, so its size ceiling is 10 MB, not 5.
--       - web/src/lib/create-listing.ts kind:'proof' -> the same four.
--       - web/src/lib/transfers.ts uploadTransferEvidence -> whatever
--         web/src/lib/evidence-upload.ts ALLOWED_EVIDENCE_TYPES admits, which
--         is those four PLUS image/heif PLUS application/pdf, bounded by
--         MAX_EVIDENCE_SIZE_MB = 10. Its contentType is looked up from
--         MIME_FOR_EXTENSION, never echoed from the client, so the set is
--         closed. Omitting image/heif or application/pdf here would break the
--         seller evidence upload outright — that path is why the union is six.
--     Live data: 29 objects, 20 image/png + 9 image/jpeg, max 4 143 632 B.
--     application/pdf is admitted ONLY here: proof-docs is the one PRIVATE
--     bucket, read through short-lived signed URLs by the two transfer parties
--     (033/034/051). A PDF in a world-readable bucket would be arbitrary
--     document hosting, so neither public bucket gets it.
--
-- image/heif is deliberately NOT added to auction-media or avatars. iOS does
-- emit both HEIC and HEIF labels, so this was checked rather than assumed: the
-- mobile writers derive the MIME from an extension whitelist that contains
-- 'heic' and not 'heif' (a .heif file falls through to the 'jpg' fallback and
-- is uploaded as image/jpeg), and the web writer validates file.type against
-- ALLOWED_IMAGE_TYPES, which has no heif. No shipped path can emit image/heif
-- into either public bucket. If ALLOWED_IMAGE_TYPES ever gains it, this bucket
-- config must change in the SAME pull request or covers will start failing.
--
-- COMPATIBILITY — NO EXISTING OBJECT IS INVALIDATED
-- Proven, not assumed. Against production, 2026-08-27:
--   with proposed(bucket_id, lim, mimes) as (values (...the three rows above...))
--   select o.bucket_id, o.name, (o.metadata->>'size')::bigint, o.metadata->>'mimetype'
--     from storage.objects o join proposed p on p.bucket_id = o.bucket_id
--    where (o.metadata->>'size')::bigint > p.lim
--       or not ((o.metadata->>'mimetype') = any(p.mimes));
--   -> 0 rows, over all 172 objects (0 with a NULL mimetype, 0 with a NULL size).
-- These columns gate NEW uploads only; stored objects are never re-checked. The
-- query is the stronger statement: the limits do not contradict a single piece
-- of real production traffic, so nothing that works today stops working.
--
-- CLIENT IMPACT: none required, one behaviour change worth knowing.
-- Every limit here EQUALS the limit its client already enforces, so no code
-- change ships with this migration. The one difference is at the seam:
-- src/utils/validateImage.ts checks size only `if (file.fileSize)` — when
-- expo-image-picker returns an asset with no fileSize the client check is
-- skipped entirely, and an oversized file that previously uploaded will now be
-- refused by the Storage API. That is the fix working; the cost is that the
-- user sees the raw storage error surfaced by useImageUpload's catch rather
-- than the friendly "Image must be under 10MB" copy. A follow-up that maps the
-- storage 413/415 responses onto that copy is a UX improvement, not a blocker,
-- and is deliberately not bundled here.
--
-- LOCKS AND RUNTIME
-- Three single-row UPDATEs on storage.buckets (3 rows total in that table) plus
-- two catalog SELECTs. RowExclusiveLock on storage.buckets, held for well under
-- a millisecond. No table is rewritten, no index is built, no lock is taken on
-- storage.objects. The Storage API reads bucket config per request, so the new
-- limits take effect on the next upload with no restart. Zero downtime.
--
-- SCOPE: storage.buckets.file_size_limit and allowed_mime_types only.
-- No grant change, no EXECUTE revoke, no policy added/dropped/altered, no cron
-- change, no object mutated, no public/private flag touched. Those belong to
-- 074 and 075.
--
-- Tests: supabase/tests/130_storage_bucket_constraints.sql (18 assertions).
-- Rollback: supabase/rollbacks/073_storage_bucket_upload_constraints_rollback.sql
-- =============================================================================

BEGIN;

-- Idempotent by construction: assignment of literal values, not accumulation.
-- Re-running is a no-op. Written as UPDATE because all three rows already
-- exist in every environment — an INSERT ... ON CONFLICT DO NOTHING is exactly
-- the shape that failed to apply these values to production in the first place.

UPDATE storage.buckets
   SET file_size_limit    = 10485760,
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/heic']
 WHERE id = 'auction-media';

UPDATE storage.buckets
   SET file_size_limit    = 5242880,
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/heic']
 WHERE id = 'avatars';

UPDATE storage.buckets
   SET file_size_limit    = 10485760,
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/heic',
                                  'image/heif','application/pdf']
 WHERE id = 'proof-docs';

-- ── Self-verification. Fail closed. ────────────────────────────────────────
-- A bare UPDATE reports success when it matches zero rows. Without this block a
-- renamed or missing bucket would let the migration COMMIT while changing
-- nothing — the same silent no-op that produced this defect. Each expected row
-- must exist AND hold exactly the intended values.
DO $$
DECLARE
  v_ok integer;
BEGIN
  SELECT count(*) INTO v_ok
    FROM (VALUES
      ('auction-media', 10485760::bigint,
       ARRAY['image/jpeg','image/png','image/webp','image/heic']),
      ('avatars',        5242880::bigint,
       ARRAY['image/jpeg','image/png','image/webp','image/heic']),
      ('proof-docs',    10485760::bigint,
       ARRAY['image/jpeg','image/png','image/webp','image/heic',
             'image/heif','application/pdf'])
    ) AS want(id, lim, mimes)
    JOIN storage.buckets b ON b.id = want.id
   WHERE b.file_size_limit = want.lim
     -- Order-insensitive set comparison: the Storage API treats
     -- allowed_mime_types as a set, and a future editor reordering the literal
     -- must not be reported as drift.
     AND b.allowed_mime_types @> want.mimes
     AND b.allowed_mime_types <@ want.mimes;

  IF v_ok <> 3 THEN
    RAISE EXCEPTION 'SEC-3: storage bucket constraints not applied to all three buckets (matched % of 3).', v_ok
      USING DETAIL = 'Expected auction-media 10485760, avatars 5242880, proof-docs 10485760, each with its exact MIME allow-list.',
            HINT   = 'A bucket is missing or renamed. Reconcile storage.buckets before re-running; do not weaken this check.';
  END IF;
END $$;

-- The values above are only durable because a client cannot rewrite them.
-- `authenticated` and `anon` hold table-wide UPDATE on storage.buckets from
-- Supabase's bootstrap grants; RLS enabled with zero policies is the only thing
-- denying them. If that ever stopped being true, this migration would be
-- decoration and the correct response is to stop, not to proceed quietly.
-- Read-only assertion — no DDL, nothing altered.
--
-- (How the UPDATEs above get past that same RLS: storage.buckets is owned by
-- supabase_storage_admin, and `postgres` — the role the CLI and the Supabase
-- GitHub integration apply migrations as — is NOT a member of it. It succeeds
-- because pg_roles.rolbypassrls is true for `postgres` and false for
-- authenticated/anon/authenticator. That asymmetry is the whole mechanism.)
DO $$
DECLARE
  v_rls      boolean;
  v_policies integer;
BEGIN
  SELECT c.relrowsecurity,
         (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid)
    INTO v_rls, v_policies
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'storage' AND c.relname = 'buckets';

  IF v_rls IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'SEC-3: RLS is not enabled on storage.buckets — these limits would be client-editable.'
      USING DETAIL = 'anon and authenticated hold table-wide UPDATE on storage.buckets; RLS with no policies is what makes that grant inert.',
            HINT   = 'Do not weaken this check. Restore RLS on storage.buckets (or revoke the grants, which is migration 074) first.';
  END IF;

  IF v_policies <> 0 THEN
    RAISE WARNING 'SEC-3: storage.buckets now has % RLS polic(ies). Confirm none of them grants a client UPDATE, or these limits are advisory.', v_policies;
  END IF;
END $$;

COMMIT;
