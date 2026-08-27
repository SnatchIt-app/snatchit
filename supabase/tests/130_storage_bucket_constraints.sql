-- ============================================================================
-- 130_storage_bucket_constraints.sql — SEC-3. Every storage bucket must bound
-- what an authenticated user can put in it: a maximum object size and an
-- explicit MIME allow-list. Signup is open and the three INSERT policies
-- (033/053) scope writes only to `(storage.foldername(name))[1] = auth.uid()`,
-- so they constrain WHERE a user writes and never WHAT — the bucket columns are
-- the only thing that does. Two of the three buckets are `public = true` and
-- world-readable through the policy "public read public buckets", which makes
-- an unrestricted MIME set arbitrary content hosting on the storage origin.
-- Ground truth: 000 (auction-media, avatars), 033 (proof-docs), 073 (the values
-- asserted here).
--
-- WHAT THIS FILE PROVES, AND WHAT IT DOES NOT — read before trusting a pass.
-- `file_size_limit` and `allowed_mime_types` are enforced by the STORAGE API,
-- not by Postgres. storage.objects carries exactly two non-internal triggers
-- (protect_objects_delete, update_objects_updated_at) and two constraints
-- (objects_pkey, objects_bucketId_fkey), and none of them reads either column
-- (verified against the production catalog, 2026-08-27). A direct SQL INSERT
-- into storage.objects bypasses both columns — before 073 and after it.
--
-- So this file asserts the CONFIGURATION is present, exact and coherent. It
-- does NOT assert that an upload is rejected, and no assertion here should ever
-- be described as proving one. Behavioural proof needs an HTTP upload against a
-- live Storage API, which the pgTAP gate cannot make. The configuration is
-- nonetheless the real control, on the INFERENCE — not verified here — that
-- client roles reach storage.objects only through that API: Supabase's
-- PostgREST default exposes `public, graphql_public` and not `storage`, and no
-- SQL surface reports the running db-schemas setting.
--
-- The "admissible" predicate used by the positive and negative controls below
-- is therefore catalog arithmetic — `bytes <= file_size_limit AND mimetype =
-- ANY(allowed_mime_types)` — i.e. what the Storage API is configured to accept.
-- One honest caveat: whether the API compares with `<=` or `<` at the exact
-- boundary is UNVERIFIED here; the boundary rows use `= file_size_limit`, so a
-- strict-`<` implementation would differ by one byte. That does not affect any
-- real upload path, all of which are bounded by the same numbers client-side.
--
-- Catalog-level only, deliberately — same reasoning as 100_storage.sql: seeding
-- storage.objects means matching a column set and INSERT triggers (path_tokens,
-- level, storage.prefixes) that differ across storage-api versions, and a
-- fixture that errors on a runner upgrade takes the whole gate down.
--
-- NOTE for anyone reading a RED run of this file: on a FRESH replay,
-- auction-media and avatars already carry their limits from 000, so assertions
-- 3-6 cannot go red in CI. Only proof-docs (created by 033 with no limits at
-- all) is NULL/NULL before 073. In PRODUCTION all three were NULL/NULL — 000's
-- INSERTs carry ON CONFLICT (id) DO NOTHING and both public buckets predate the
-- migration, so its declared limits never applied there. That environment split
-- is precisely what 073 repairs. Without it, assertions 1, 2, 7, 8, 9, 10, 11,
-- 16, 17 and 18 fail on a fresh replay (measured, run 33111390601).
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

-- ── A. The columns are set at all ──────────────────────────────────────────
-- NULL means "no restriction" to the Storage API. Scoped to the three buckets
-- this repository owns so an unrelated bucket added by a future storage-api
-- release cannot make the gate red for a reason nobody here controls.

-- 1
SELECT is_empty(
  $$ SELECT id FROM storage.buckets
      WHERE id IN ('auction-media','avatars','proof-docs')
        AND file_size_limit IS NULL $$,
  'every owned bucket has a file_size_limit (NULL = unbounded uploads)');

-- 2
SELECT is_empty(
  $$ SELECT id FROM storage.buckets
      WHERE id IN ('auction-media','avatars','proof-docs')
        AND allowed_mime_types IS NULL $$,
  'every owned bucket has an allowed_mime_types allow-list (NULL = any content type)');

-- ── B. The exact values, per bucket ────────────────────────────────────────
-- MIME sets are compared sorted: the Storage API treats the column as a set,
-- so reordering the literal is not drift and must not fail here.

-- 3
SELECT is(
  (SELECT file_size_limit FROM storage.buckets WHERE id = 'auction-media'),
  10485760::bigint,
  'auction-media caps uploads at 10 MiB (= APP_CONFIG.MAX_IMAGE_SIZE_MB, and above the 6 361 057 B production maximum)');

-- 4
SELECT is(
  (SELECT array(SELECT unnest(b.allowed_mime_types) ORDER BY 1)
     FROM storage.buckets b WHERE b.id = 'auction-media'),
  ARRAY['image/heic','image/jpeg','image/png','image/webp']::text[],
  'auction-media admits exactly APP_CONFIG.ALLOWED_IMAGE_TYPES');

-- 5
SELECT is(
  (SELECT file_size_limit FROM storage.buckets WHERE id = 'avatars'),
  5242880::bigint,
  'avatars caps uploads at 5 MiB (= APP_CONFIG.MAX_AVATAR_SIZE_MB, the limit src/utils/validateImage.ts already applies)');

-- 6
SELECT is(
  (SELECT array(SELECT unnest(b.allowed_mime_types) ORDER BY 1)
     FROM storage.buckets b WHERE b.id = 'avatars'),
  ARRAY['image/heic','image/jpeg','image/png','image/webp']::text[],
  'avatars admits exactly APP_CONFIG.ALLOWED_IMAGE_TYPES');

-- 7
SELECT is(
  (SELECT file_size_limit FROM storage.buckets WHERE id = 'proof-docs'),
  10485760::bigint,
  'proof-docs caps uploads at 10 MiB (= MAX_EVIDENCE_SIZE_MB, and the ceiling useImageUpload applies to proof uploads)');

-- 8
SELECT is(
  (SELECT array(SELECT unnest(b.allowed_mime_types) ORDER BY 1)
     FROM storage.buckets b WHERE b.id = 'proof-docs'),
  ARRAY['application/pdf','image/heic','image/heif','image/jpeg',
        'image/png','image/webp']::text[],
  'proof-docs admits exactly ALLOWED_EVIDENCE_TYPES (the four image types plus heif plus pdf)');

-- ── C. The allow-list is an allow-list ─────────────────────────────────────

-- 9. A wildcard entry ('image/*', '*/*') would re-open the MIME hole while
--    still reading as "restricted". text/html and image/svg+xml execute script
--    on the storage origin; the rest are arbitrary-payload carriers.
--
--    A NULL allow-list is the WORST case, not a neutral one — it admits every
--    type on this list at once. The earlier shape of this assertion
--    (`FROM storage.buckets, unnest(allowed_mime_types)`) could not say so:
--    unnest(NULL) yields zero rows, the bucket dropped out of the cross join,
--    and the assertion PASSED against the exact pre-073 state it exists to
--    catch. LEFT JOIN LATERAL keeps the row so the NULL case is reported.
--    Scoped to the owned buckets for the same reason as 1-2.
SELECT is_empty(
  $$ SELECT b.id || ' admits ' || coalesce(m, 'EVERY TYPE (allowed_mime_types IS NULL)')
       FROM storage.buckets b
       LEFT JOIN LATERAL unnest(b.allowed_mime_types) AS m ON true
      WHERE b.id IN ('auction-media','avatars','proof-docs')
        AND (b.allowed_mime_types IS NULL
             OR m LIKE '%*%'
             OR m IN ('text/html','application/xhtml+xml','image/svg+xml',
                      'text/xml','application/xml','application/octet-stream',
                      'text/javascript','application/javascript',
                      'application/x-msdownload')) $$,
  'no owned bucket admits a wildcard, scriptable or arbitrary-payload MIME type (an unset allow-list admits all of them)');

-- 10. Nothing may quietly exceed the largest limit this repo intends. NULL is
--     included deliberately: an unset limit allows objects larger than 10 MiB
--     by definition, so omitting it made this assertion pass against the very
--     state 073 fixes. Scoped to the owned buckets, matching 1-2.
SELECT is_empty(
  $$ SELECT id || ' -> ' || coalesce(file_size_limit::text, 'NULL (unbounded)')
       FROM storage.buckets
      WHERE id IN ('auction-media','avatars','proof-docs')
        AND (file_size_limit IS NULL OR file_size_limit > 10485760) $$,
  'no owned bucket allows an object larger than 10 MiB (an unset limit allows any size)');

-- 11. application/pdf is document hosting. It is legitimate for seller transfer
--     evidence, which lives in the ONE private bucket read through short-lived
--     signed URLs (033/034/051) — and nowhere else. In a `public = true` bucket
--     it would be world-readable file hosting.
--     Scoped to the owned buckets: this hard-asserts an exact bucket-name
--     string, so without the filter an unrelated `invoices` bucket admitting
--     PDF would turn the SEC-3 gate red on every PR for something 073 neither
--     owns nor changed.
SELECT is(
  (SELECT coalesce(string_agg(id, ',' ORDER BY id), '<none>')
     FROM storage.buckets
    WHERE id IN ('auction-media','avatars','proof-docs')
      AND 'application/pdf' = ANY(allowed_mime_types)),
  'proof-docs',
  'of the owned buckets, application/pdf is admitted only by the private proof-docs bucket');

-- ── D. Why the configuration is durable, not advisory ──────────────────────
-- `anon` and `authenticated` both hold table-wide UPDATE on storage.buckets
-- from Supabase's bootstrap grants. RLS enabled with zero policies is the only
-- thing that makes that grant inert. If either fact changed, every value
-- asserted above would be rewritable by any signed-up user and this whole file
-- would be measuring something a client controls.

-- 12
SELECT ok(
  (SELECT c.relrowsecurity FROM pg_class c
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'storage' AND c.relname = 'buckets'),
  'RLS is enabled on storage.buckets (anon/authenticated hold table-wide UPDATE on it)');

-- 13
SELECT is(
  (SELECT count(*) FROM pg_policy p
     JOIN pg_class c ON c.oid = p.polrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'storage' AND c.relname = 'buckets'),
  0::bigint,
  'storage.buckets has zero RLS policies, so no client role can read or rewrite bucket config');

-- ── E. Positive controls — real traffic must still be admissible ───────────
-- Sizes are the OBSERVED PRODUCTION MAXIMA per bucket (census of all 172 live
-- objects, 2026-08-27). If a limit were set below real traffic these fail.

-- 14
SELECT ok(
  (SELECT coalesce(612685 <= b.file_size_limit
                   AND 'image/jpeg' = ANY(b.allowed_mime_types), false)
     FROM storage.buckets b WHERE b.id = 'avatars'),
  'a legitimate avatar (image/jpeg, 612 685 B — the largest avatar in production) is still admissible');

-- 15
SELECT ok(
  (SELECT coalesce(6361057 <= b.file_size_limit
                   AND 'image/jpeg' = ANY(b.allowed_mime_types), false)
     FROM storage.buckets b WHERE b.id = 'auction-media'),
  'a legitimate auction cover (image/jpeg, 6 361 057 B — the largest object in production) is still admissible');

-- 16
SELECT ok(
  (SELECT coalesce(4143632 <= b.file_size_limit
                   AND 'application/pdf' = ANY(b.allowed_mime_types), false)
     FROM storage.buckets b WHERE b.id = 'proof-docs'),
  'proof-docs admits an application/pdf of 4 143 632 B — the size of its largest stored object (which is an image/png; production holds no PDF yet, so this is a realistic size, not an observed file)');

-- 17. The reconciliation, as data: every (bucket, MIME, ceiling) a SHIPPED
--     writer can emit must be admissible. Writers, exhaustively:
--       src/hooks/useImageUpload.ts        -> auction-media + proof-docs
--       src/lib/avatarImage.ts             -> avatars
--       web/src/lib/create-listing.ts      -> auction-media (cover) + proof-docs (proof)
--       web/src/lib/transfers.ts           -> proof-docs (evidence; the only
--                                             source of image/heif and application/pdf)
--     Both mobile writers derive contentType from the extension whitelist
--     ['jpg','jpeg','png','webp','heic'], which is why image/heic must be here
--     and image/heif is absent from the two public buckets.
SELECT is_empty(
  $$ WITH emits(bucket_id, mimetype, bytes, writer) AS (VALUES
       -- auction-media, at APP_CONFIG.MAX_IMAGE_SIZE_MB
       ('auction-media','image/jpeg',    10485760::bigint,'useImageUpload/create-listing cover'),
       ('auction-media','image/png',     10485760::bigint,'useImageUpload/create-listing cover'),
       ('auction-media','image/webp',    10485760::bigint,'useImageUpload/create-listing cover'),
       ('auction-media','image/heic',    10485760::bigint,'useImageUpload iOS HEIC'),
       ('auction-media','image/jpeg',     6361057::bigint,'production maximum'),
       -- avatars, at APP_CONFIG.MAX_AVATAR_SIZE_MB
       ('avatars','image/jpeg',           5242880::bigint,'pickAndUploadAvatar'),
       ('avatars','image/png',            5242880::bigint,'pickAndUploadAvatar'),
       ('avatars','image/webp',           5242880::bigint,'pickAndUploadAvatar'),
       ('avatars','image/heic',           5242880::bigint,'pickAndUploadAvatar iOS HEIC'),
       ('avatars','image/jpeg',            612685::bigint,'production maximum'),
       -- proof-docs, at MAX_EVIDENCE_SIZE_MB
       ('proof-docs','image/jpeg',       10485760::bigint,'useImageUpload proof / evidence'),
       ('proof-docs','image/png',        10485760::bigint,'useImageUpload proof / evidence'),
       ('proof-docs','image/webp',       10485760::bigint,'useImageUpload proof / evidence'),
       ('proof-docs','image/heic',       10485760::bigint,'evidence iOS HEIC'),
       ('proof-docs','image/heif',       10485760::bigint,'evidence iOS HEIF (web only)'),
       ('proof-docs','application/pdf',  10485760::bigint,'evidence PDF receipt (web only)'),
       ('proof-docs','image/png',         4143632::bigint,'production maximum')
     )
     SELECT e.writer || ': ' || e.bucket_id || ' ' || e.mimetype || ' @' || e.bytes || 'B'
       FROM emits e LEFT JOIN storage.buckets b ON b.id = e.bucket_id
      WHERE NOT coalesce(e.bytes <= b.file_size_limit
                         AND e.mimetype = ANY(b.allowed_mime_types), false) $$,
  'every MIME type and size a shipped upload path can emit is admissible in its bucket');

-- 18. The discriminating half. Each row is something an authenticated user
--     could send today and must not be able to send after 073 — script-capable
--     types on the two world-readable buckets, documents in a public bucket,
--     and one-byte-over-the-limit payloads.
--
--     The NULL branches are what make this control discriminate at all. Its
--     first form tested only `bytes <= file_size_limit AND mimetype = ANY(...)`,
--     which is NULL for an unrestricted bucket — so every abuse row filtered
--     out and is_empty PASSED against production's actual pre-073 state, while
--     every listed abuse was in fact possible. An unset limit or allow-list is
--     not "no match", it is "admits everything", and is reported as such.
SELECT is_empty(
  $$ WITH abuse(bucket_id, mimetype, bytes, why) AS (VALUES
       ('auction-media','text/html',                 1024::bigint,'stored XSS on the storage origin'),
       ('auction-media','image/svg+xml',             1024::bigint,'SVG carries <script>'),
       ('auction-media','application/octet-stream',  1024::bigint,'arbitrary binary hosting'),
       ('auction-media','application/pdf',           1024::bigint,'document hosting in a public bucket'),
       ('auction-media','video/mp4',             52428800::bigint,'egress abuse'),
       ('avatars','text/html',                       1024::bigint,'stored XSS on the storage origin'),
       ('avatars','image/svg+xml',                   1024::bigint,'SVG carries <script>'),
       ('avatars','application/pdf',                 1024::bigint,'document hosting in a public bucket'),
       ('proof-docs','text/html',                    1024::bigint,'signed URL renders attacker markup'),
       ('proof-docs','image/svg+xml',                1024::bigint,'signed URL renders attacker script'),
       ('auction-media','image/jpeg',            10485761::bigint,'one byte over the cover limit'),
       ('avatars','image/jpeg',                   5242881::bigint,'one byte over the avatar limit'),
       ('proof-docs','application/pdf',          10485761::bigint,'one byte over the evidence limit'),
       ('avatars','image/jpeg',                 104857600::bigint,'100 MB avatar — storage-cost abuse')
     )
     SELECT a.bucket_id || ' still admits ' || a.mimetype || ' @' || a.bytes || 'B (' || a.why || ')'
            || CASE WHEN b.file_size_limit IS NULL OR b.allowed_mime_types IS NULL
                    THEN ' — bucket is UNRESTRICTED' ELSE '' END
       FROM abuse a JOIN storage.buckets b ON b.id = a.bucket_id
      WHERE b.file_size_limit IS NULL
         OR b.allowed_mime_types IS NULL
         OR (a.bytes <= b.file_size_limit
             AND a.mimetype = ANY(b.allowed_mime_types)) $$,
  'no owned bucket admits a scriptable type, a document in a public bucket, or an over-limit payload');

SELECT * FROM finish();
ROLLBACK;
