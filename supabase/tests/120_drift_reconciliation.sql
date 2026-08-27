-- ============================================================================
-- 120_drift_reconciliation.sql — pins the five things migration 073 reconciled.
--
-- 073 exists because source and production had silently diverged in both
-- directions: production was weaker in two places (a revoke that never landed,
-- storage constraints that never applied) and a from-source REBUILD was weaker
-- in two others (six over-broad storage policies nothing ever dropped, a cron
-- job nothing ever scheduled). This file is the regression net for all of it.
--
-- WHAT THIS FILE CAN AND CANNOT PROVE. It runs against the fresh CI replay, so
-- it proves the CHAIN produces the intended state. It says nothing about the
-- production database, which is a separate, owner-gated apply. Two assertions
-- (§1) were already green before 073 for exactly that reason — on a fresh
-- replay migration 069's revoke works fine; it is only production where it did
-- not take effect. They are pinned here anyway so the day someone re-grants
-- webhook_retries in a migration, this fails.
--
-- Ground truth: 073 (all five sections), 000 blocks 5/12 (the orphan policies),
-- 033/048/049/051/053 (the storage policies production actually has), 0600/0601
-- (the sweep function), 063/067 (the EXECUTE-posture precedent this follows).
--
-- CATALOG-LEVEL ONLY, following 100_storage.sql: asserting storage behaviour
-- would mean INSERTing into storage.objects, whose column set and triggers move
-- between storage-api versions — a fixture that breaks on a runner upgrade
-- takes the whole gate down with it.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- ---------------------------------------------------------------------------
-- §1. SEC-1 — public.webhook_retries carries no client DML.
-- Migration 069 revokes it and 073 re-issues that revoke. Production had drifted
-- to anon=arwdm/authenticated=arwdm; the fresh replay never had it. Asserting
-- the FULL privilege set rather than SELECT alone: the drifted production ACL
-- included INSERT/UPDATE/DELETE, and a check that only looked at SELECT would
-- have called that state clean.
-- ---------------------------------------------------------------------------
SELECT is_empty(
  $$ SELECT privilege_type FROM information_schema.role_table_grants
      WHERE table_schema = 'public' AND table_name = 'webhook_retries'
        AND grantee = 'anon' $$,
  'anon holds no privilege of any kind on webhook_retries (069/073)');

SELECT is_empty(
  $$ SELECT privilege_type FROM information_schema.role_table_grants
      WHERE table_schema = 'public' AND table_name = 'webhook_retries'
        AND grantee = 'authenticated' $$,
  'authenticated holds no privilege of any kind on webhook_retries (069/073)');

-- ---------------------------------------------------------------------------
-- §2. SEC-3 — storage buckets carry server-side size and MIME constraints.
-- 000 specified these but used `on conflict (id) do nothing` against buckets
-- that already existed, so production got NULL/NULL — no server-side limit at
-- all, with only client-side code standing between the storage REST API and an
-- arbitrary upload.
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT ROW(file_size_limit, allowed_mime_types)::text
     FROM storage.buckets WHERE id = 'auction-media'),
  ROW(10485760::bigint,
      ARRAY['image/jpeg','image/png','image/webp','image/heic'])::text,
  'auction-media: 10MB limit + 4 image types (073 §2)');

SELECT is(
  (SELECT ROW(file_size_limit, allowed_mime_types)::text
     FROM storage.buckets WHERE id = 'avatars'),
  ROW(5242880::bigint,
      ARRAY['image/jpeg','image/png','image/webp','image/heic'])::text,
  'avatars: 5MB limit + 4 image types (073 §2)');

-- proof-docs deliberately differs. It takes transfer evidence, and
-- web/src/lib/evidence-upload.ts accepts application/pdf (receipts) and
-- image/heif. Narrowing this to the other buckets' image-only list would look
-- tidier and would break a live seller flow — so the allowlist is asserted
-- EXACTLY, to stop exactly that "cleanup" landing later.
SELECT is(
  (SELECT ROW(file_size_limit, allowed_mime_types)::text
     FROM storage.buckets WHERE id = 'proof-docs'),
  ROW(10485760::bigint,
      ARRAY['image/jpeg','image/png','image/webp',
            'image/heic','image/heif','application/pdf'])::text,
  'proof-docs: 10MB limit + evidence types incl. PDF/HEIF (073 §2)');

SELECT is_empty(
  $$ SELECT id FROM storage.buckets
      WHERE file_size_limit IS NULL OR allowed_mime_types IS NULL $$,
  'no bucket is left unconstrained — a new bucket must declare its limits');

-- ---------------------------------------------------------------------------
-- §3. SEC-4 — the six orphan policies from 000 are gone.
-- They were never dropped by any migration, so a rebuild had 17 storage
-- policies where production has 11 — and the six extras were STRICTLY WEAKER
-- than the ones they sat beside (TO PUBLIC rather than TO authenticated, and
-- the DELETE variants lacked the "unreferenced" guard 048/049 added). A rebuild
-- was therefore not a copy of production but a downgrade of it.
-- ---------------------------------------------------------------------------
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND policyname IN ('storage: public read',
                           'storage: owner upload',
                           'storage: owner delete',
                           'avatars: public read',
                           'avatars: owner upload',
                           'avatars: owner delete') $$,
  'the six orphan 000 storage policies are absent (073 §3)');

SELECT is(
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'),
  11::bigint,
  'storage.objects has exactly 11 policies — parity with production');

-- The orphans were the only writes ever granted TO PUBLIC on storage. After the
-- drop, exactly one PUBLIC policy may remain: 051's read, scoped to the two
-- public buckets. Any other is a new anon path onto stored files.
SELECT is(
  (SELECT coalesce(string_agg(policyname, ', ' ORDER BY policyname), '(none)')
     FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND roles::text[] && ARRAY['public','anon']),
  'public read public buckets',
  'only 051''s scoped read is TO PUBLIC on storage.objects');

-- ---------------------------------------------------------------------------
-- §4. D-5 — the password-change sweep is scheduled by the chain.
-- Production runs it (jobid 10) but no migration created it — 0600 only
-- mentions it in a comment. A rebuild kept the function and lost the caller, so
-- password-change security notifications stopped with nothing erroring.
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*) FROM cron.job
    WHERE jobname  = 'sweep-auth-password-changes'
      AND schedule = '*/5 * * * *'
      AND command  = 'select public.sweep_auth_password_changes();'
      AND active),
  1::bigint,
  'sweep-auth-password-changes is scheduled, active, every 5 min (073 §4)');

-- ---------------------------------------------------------------------------
-- §5. EXECUTE posture on the six functions 067 missed.
--
-- The PUBLIC check is the one that matters and the one a naive test gets wrong:
-- a NULL proacl does not mean "no grants", it means "defaults apply", and the
-- default for a function IS EXECUTE TO PUBLIC. So NULL must count as a
-- failure, not a pass — otherwise this assertion would go green on a database
-- where nothing had ever been revoked at all.
-- ---------------------------------------------------------------------------
SELECT is_empty(
  $$ SELECT p.proname FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN ('dispute_resolutions_append_only',
                          'guard_transfer_state_columns',
                          'reset_transfer_guard_bypass')
        AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR has_function_privilege('authenticated', p.oid, 'EXECUTE')) $$,
  'trigger functions: no anon/authenticated EXECUTE (073 §5 group A)');

SELECT is_empty(
  $$ SELECT p.proname FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN ('dispute_resolutions_append_only',
                          'guard_transfer_state_columns',
                          'reset_transfer_guard_bypass')
        AND (p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                      WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')) $$,
  'trigger functions: no PUBLIC EXECUTE, and proacl is not defaulted');

-- set_ambassador_application_updated_at() is the fourth function in this group
-- and still carries PUBLIC EXECUTE on a fresh replay. 073 deliberately does not
-- revoke it: it is created by a TIMESTAMP-scheme migration
-- (20260730212326_ambassador_applications_website_form.sql) that the CLI orders
-- AFTER 073, so a revoke there would apply on production and silently skip on
-- every rebuild — new drift, in a migration written to remove drift.
--
-- What makes leaving it safe is a property, not a grant: all four RETURN
-- trigger, so PostgreSQL refuses a direct call whoever holds EXECUTE. That is
-- the entire basis of 067's group-A reasoning and it has never been asserted
-- anywhere. Pin it here. If one of these is ever redefined to return something
-- callable, the grant stops being harmless and this fails.
SELECT is(
  (SELECT count(*) FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('dispute_resolutions_append_only',
                        'guard_transfer_state_columns',
                        'reset_transfer_guard_bypass',
                        'set_ambassador_application_updated_at')
      AND p.prorettype = 'trigger'::regtype),
  4::bigint,
  'all four group-A functions RETURN trigger — not directly invokable');

SELECT is_empty(
  $$ SELECT p.proname FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN ('is_blocked_by_me', 'is_winner')
        AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                      WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')) $$,
  'is_blocked_by_me / is_winner: no anon and no PUBLIC EXECUTE (073 §5 group B)');

-- authenticated is retained on purpose. is_blocked_by_me was designed as a
-- listings-feed RLS predicate and its user_blocks table is live; if that
-- predicate ever ships, authenticated MUST hold EXECUTE or every signed-in
-- listing read fails. This asserts the grant that a future "tidy the ACL" pass
-- would otherwise remove without noticing what depends on it.
SELECT is(
  (SELECT count(*) FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('is_blocked_by_me', 'is_winner')
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  2::bigint,
  'is_blocked_by_me / is_winner: authenticated retains EXECUTE (073 §5 group B)');

SELECT * FROM finish();
ROLLBACK;
