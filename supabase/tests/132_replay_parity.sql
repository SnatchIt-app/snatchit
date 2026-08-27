-- ============================================================================
-- 132_replay_parity.sql — SOURCE == FRESH REPLAY == PRODUCTION.
--
-- This file exists because the pgTAP suite runs against a FRESHLY REPLAYED
-- database, which makes it the only place in the project that can observe a
-- replay-only divergence. Two were found, and migration 075 closes both:
--
--   SEC-4  000_baseline_schema.sql creates six storage.objects policies
--          (block 5, lines 252-272; block 12, lines 850-871) that no later
--          migration drops — grep over supabase/migrations shows their names
--          appear ONLY in 000 (as its own pre-drops and creates) and in 075.
--          Production does not have them: its 11 policies all come from
--          033/034/048/049/051/053, because the live storage surface was
--          reconciled out-of-band before 051/053 codified it and 000 is a
--          RECONSTRUCTED baseline, not a transcript. So a rebuild gets 11 + 6
--          = 17 policies. The harm, stated at its true size:
--
--            * REACHABLE (this is the security part). "avatars: owner delete"
--              grants authenticated users a DELETE on the avatars bucket that
--              production does not grant in ANY form — production's avatars
--              policies are insert and update only. And "storage: owner
--              delete" is an unguarded DELETE over auction-media that ORs with
--              — and therefore defeats — the "unreferenced" guard 048 added
--              over listings.cover_image_path, because RLS policies are OR-ed
--              within a command. On a rebuilt stack a seller can delete the
--              cover image out from under a live listing. Scope: only 048's
--              guard is defeated; both orphan DELETEs are bucket-scoped
--              (auction-media, avatars) and neither mentions proof-docs, so
--              049's guard stands.
--
--            * CATALOG-LEVEL ONLY (do NOT read this as anon exposure). The six
--              carry no TO clause and so default to TO PUBLIC, which widens the
--              role set on a replay. It does NOT create an anon-reachable write
--              path: every orphan INSERT/DELETE predicate requires
--              auth.uid()::text = (storage.foldername(name))[1], and auth.uid()
--              is NULL in a genuine anon session, so the comparison yields NULL
--              and the policy never permits the row. The two orphan SELECTs are
--              inert beside production's "public read public buckets", which is
--              already TO public over exactly those two buckets. The real
--              effects are the authenticated-owner delete behaviour above, and
--              replay authorization drift.
--
--          Either way, a rebuild was WEAKER than the database it must
--          reproduce, which is the thing a rebuild must never be.
--
--   D-5    'sweep-auth-password-changes' runs in production (jobid 10) but is
--          scheduled by no migration; 0600 only mentions it in a comment
--          (line 55). A rebuild silently lost password-change security
--          notifications entirely — function present, nothing ever calling it.
--
-- WHY THIS FILE WAS REWRITTEN (test-strengthening pass, 2026-08-27)
-- The first revision had two weaknesses that a strong reviewer found:
--
--   1. Its cron drift assertion ("no drifted or inactive duplicate") was an
--      is_empty over cron.job filtered by jobname. On an UN-MIGRATED replay
--      there is no such job at all, so the subquery was trivially empty and the
--      assertion reported ok while the feature was 100% absent. It could not
--      fail for the reason it claimed to test. Assertion 9 below replaces it
--      with a shape that fails at zero rows as loudly as it fails at two.
--
--   2. Its storage coverage leaned on COUNTS (count = 11, count of DELETE
--      policies = 2). A count passes if one policy is swapped for another.
--      Assertions 2 and 3 below pin the full SET instead.
--
-- GROUND TRUTH. Every expected value below was read from the PRODUCTION
-- catalog of project hqycwntpfoztoinemqns on 2026-08-27 by read-only SELECT,
-- not transcribed from a migration or a note:
--   * storage.objects: 11 policies; 0 of the six baseline orphan names present
--     (checked individually, by name).
--   * cron.job jobid 10: jobname 'sweep-auth-password-changes',
--     schedule '*/5 * * * *', database 'postgres', username 'postgres',
--     active true, command 'select public.sweep_auth_password_changes();',
--     length 44, md5 a8688b5b2add782b9a988d1f3850cd07, hex tail 28293b (i.e.
--     "();" with no trailing whitespace).
--   * server PostgreSQL 17.6; CI replays on major_version 17, so the catalog
--     deparse of a policy predicate is the same on both sides.
--
-- PREDICATE NORMALIZATION, AND WHY IT DOES NOT WEAKEN THE CHECK
-- pg_policies.qual / .with_check are DEPARSED text: pg_get_expr renders a
-- schema qualification only when the object is not visible in the session
-- search_path, and it emits newlines inside sub-SELECTs. Neither is a property
-- of the policy. Assertions 2 and 3 therefore compare
--     btrim(regexp_replace(replace(x, 'public.', ''), '\s+', ' ', 'g'))
-- with NULL rendered as the sentinel '<null>' so a NULL qual can never be
-- confused with an empty one. None of the 11 predicates contains the literal
-- text 'public.' inside a string constant, so the replace() is lossless here.
-- Everything that makes a policy a policy — its name, its command, its role
-- set, and the structure of USING / WITH CHECK — still has to match exactly.
--
-- Assertion 3's expected digests were COMPUTED BY PRODUCTION with the same
-- normalization expression and pasted here; assertion 2's expected strings were
-- transcribed from the same read. They are deliberately two different encodings
-- of one production read, so a transcription slip in one is caught by the other.
--
-- CATALOG-LEVEL ONLY, for the same reason 100_storage.sql is: asserting
-- behaviour here would mean INSERTing into storage.objects, whose column set
-- and INSERT triggers vary across storage-api versions, and cron.job_run_details
-- would require actually waiting for a scheduled tick.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- ── SEC-4 — storage.objects ─────────────────────────────────────────────────

-- 1. The six baseline orphans are gone. Kept as an explicit, named assertion
--    (rather than folded into the set check) because it is the one that names
--    the defect: it fails on an un-migrated fresh replay, where all six are
--    present, and passes on production unchanged, where none ever was.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND policyname IN ('storage: public read','storage: owner upload',
                           'storage: owner delete','avatars: public read',
                           'avatars: owner upload','avatars: owner delete') $$,
  'SEC-4/1: none of the six 000_baseline storage.objects policies survive (075)');

-- 2. THE FULL SET, not a count. (policyname, cmd, roles, qual, with_check) for
--    every policy on storage.objects must equal production's eleven exactly.
--    A count of 11 passes if one policy is swapped for another, if a predicate
--    is loosened in place, or if a TO clause is widened; this does not. This is
--    also the assertion that would catch a future migration that "fixes" an
--    orphan by recreating it under a different name.
SELECT set_eq(
  $$ SELECT p.policyname || '|' || p.cmd || '|' || p.roles::text || '|' ||
            coalesce(btrim(regexp_replace(replace(p.qual,       'public.', ''), '\s+', ' ', 'g')), '<null>') || '|' ||
            coalesce(btrim(regexp_replace(replace(p.with_check, 'public.', ''), '\s+', ' ', 'g')), '<null>')
       FROM pg_policies p
      WHERE p.schemaname = 'storage' AND p.tablename = 'objects' $$,
  ARRAY[
    $e$auction-media owner delete unreferenced|DELETE|{authenticated}|((bucket_id = 'auction-media'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND (NOT (EXISTS ( SELECT 1 FROM listings l WHERE (l.cover_image_path = objects.name)))))|<null>$e$,
    $e$auction-media owner insert|INSERT|{authenticated}|<null>|((bucket_id = 'auction-media'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))$e$,
    $e$auction-media owner update|UPDATE|{authenticated}|((bucket_id = 'auction-media'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))|((bucket_id = 'auction-media'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))$e$,
    $e$avatars owner insert|INSERT|{authenticated}|<null>|((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))$e$,
    $e$avatars owner update|UPDATE|{authenticated}|((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))|((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))$e$,
    $e$proof-docs owner delete unreferenced|DELETE|{authenticated}|((bucket_id = 'proof-docs'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND (NOT (EXISTS ( SELECT 1 FROM listings l WHERE (l.proof_of_ownership_path = objects.name)))) AND (NOT (EXISTS ( SELECT 1 FROM transfers t WHERE (t.transfer_evidence_path = objects.name)))))|<null>$e$,
    $e$proof-docs owner insert|INSERT|{authenticated}|<null>|((bucket_id = 'proof-docs'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))$e$,
    $e$proof-docs owner read|SELECT|{authenticated}|((bucket_id = 'proof-docs'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))|<null>$e$,
    $e$proof-docs owner update|UPDATE|{authenticated}|((bucket_id = 'proof-docs'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text) AND (NOT (EXISTS ( SELECT 1 FROM transfers t WHERE (t.transfer_evidence_path = objects.name)))))|((bucket_id = 'proof-docs'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))$e$,
    $e$proof-docs transfer party read|SELECT|{authenticated}|((bucket_id = 'proof-docs'::text) AND (EXISTS ( SELECT 1 FROM transfers t WHERE ((t.transfer_evidence_path = objects.name) AND ((t.buyer_id = auth.uid()) OR (t.seller_id = auth.uid()))))))|<null>$e$,
    $e$public read public buckets|SELECT|{public}|(bucket_id = ANY (ARRAY['auction-media'::text, 'avatars'::text]))|<null>$e$
  ],
  'SEC-4/2: the storage.objects policy set equals production''s eleven on (policyname, cmd, roles, qual, with_check)');

-- 3. STORAGE POLICY PARITY, encoded as production emitted it. Same eleven, but
--    the predicate compared as an md5 digest that PRODUCTION computed, with the
--    same normalization. Gate-2 counts pg_policies WHERE schemaname='public'
--    only, so it is structurally blind to the entire storage schema and cannot
--    see this divergence at all — EXPECT_POLICIES stayed 37 across the whole
--    SEC-4 defect. This assertion is the parity check Gate-2 does not perform.
SELECT set_eq(
  $$ SELECT p.policyname || '|' || p.cmd || '|' || p.roles::text || '|' ||
            md5(
              coalesce(btrim(regexp_replace(replace(p.qual,       'public.', ''), '\s+', ' ', 'g')), '<null>') || '|' ||
              coalesce(btrim(regexp_replace(replace(p.with_check, 'public.', ''), '\s+', ' ', 'g')), '<null>')
            )
       FROM pg_policies p
      WHERE p.schemaname = 'storage' AND p.tablename = 'objects' $$,
  ARRAY[
    'auction-media owner delete unreferenced|DELETE|{authenticated}|4d247944d8813ff31fa3105422fbd663',
    'auction-media owner insert|INSERT|{authenticated}|639d25e0a77650b3f549ffe2630d44ab',
    'auction-media owner update|UPDATE|{authenticated}|e579e58929fc012796dc191976698473',
    'avatars owner insert|INSERT|{authenticated}|7706af14caabc6390422d5bd84e67bca',
    'avatars owner update|UPDATE|{authenticated}|261757452f26e7c3442d8ca877b73f50',
    'proof-docs owner delete unreferenced|DELETE|{authenticated}|f88d8b9c5b71a63e2329ebe8ab933ac3',
    'proof-docs owner insert|INSERT|{authenticated}|a8c761d440e8b2525e1de46204f524ac',
    'proof-docs owner read|SELECT|{authenticated}|46136ba30756916ff30ae06ae924053b',
    'proof-docs owner update|UPDATE|{authenticated}|2f61d6b7cf0976716b72a5cb9bb1d66d',
    'proof-docs transfer party read|SELECT|{authenticated}|f76ee6cba447c285d21e81f1cb65f484',
    'public read public buckets|SELECT|{public}|bda9d9476954e11c9ae8d9b119156e88'
  ],
  'SEC-4/3 (parity): the replayed storage.objects policy set matches the PRODUCTION fixture (name, cmd, roles, md5 of USING|WITH CHECK)');

-- 4. THE DELETE GUARD. Kept, and kept separate from the set check, because it
--    is the assertion that states the reachable harm: RLS policies OR together
--    within a command, so ONE unguarded DELETE policy silently repeals 048 and
--    a seller can delete the cover image out from under a live listing. Both
--    orphan DELETE policies were unguarded. This fails on an un-migrated replay
--    and would fail again for any future DELETE policy that omits the guard.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND cmd = 'DELETE'
        AND (qual IS NULL OR qual NOT ILIKE '%NOT (EXISTS%') $$,
  'SEC-4/4: every storage.objects DELETE policy keeps the unreferenced guard (048/049 not defeated by an OR-ed sibling)');

-- 5. Exactly one policy reaches PUBLIC/anon, and it is 051's scoped public
--    read. Set equality, not a count: a swap would pass a count.
SELECT set_eq(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND roles::text[] && ARRAY['public','anon'] $$,
  ARRAY['public read public buckets'],
  'SEC-4/5: only "public read public buckets" carries public/anon in its role set');

-- 6. No WRITE policy on storage.objects carries public/anon in its role set.
--    Read this precisely: it is a ROLE-SET invariant, not a claim that anon
--    could write on a replay. The four orphan write policies had no TO clause
--    and so appeared as TO PUBLIC, but their predicates need auth.uid(), which
--    is NULL for anon, so nothing was ever permitted through them. The
--    assertion is worth keeping anyway — it is the cheap invariant that catches
--    a FUTURE write policy whose predicate is NOT auth.uid()-gated.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND cmd IN ('INSERT','UPDATE','DELETE')
        AND roles::text[] && ARRAY['public','anon'] $$,
  'SEC-4/6: no INSERT/UPDATE/DELETE policy on storage.objects carries public/anon in its role set');

-- ── D-5 — the sweep cron job ────────────────────────────────────────────────
-- Three assertions, each of which fails for a DIFFERENT reason. The previous
-- revision had one that could not fail on the very database it was written for.

-- 7. EXISTENCE. Exactly one row named 'sweep-auth-password-changes'. Fails at
--    0 (the un-migrated replay: password-change notifications never fire) and
--    fails at 2 (075 having double-scheduled instead of converging, the failure
--    mode the migration's four-way guard exists to avoid).
SELECT is(
  (SELECT count(*) FROM cron.job WHERE jobname = 'sweep-auth-password-changes'),
  1::bigint,
  'D-5/7 (existence): exactly one cron job named "sweep-auth-password-changes"');

-- 8. CRON PARITY — exact field match against production jobid 10, including the
--    command as an exact string plus its byte length and md5, so that trailing
--    whitespace or an invisible edit cannot slip through a "looks the same"
--    comparison. string_agg (not a scalar subquery) is deliberate: with two
--    rows a scalar subquery would ERROR and abort the file mid-plan; this
--    simply produces a different string and reports a clean failure. With zero
--    rows it yields NULL, which also fails.
--    active is rendered with ::text, NOT format('%s', active): format() calls
--    boolean's output function and yields 't', while the bool->text cast yields
--    'true'. Both this query and the expected literal below were EXECUTED
--    against production before being committed, which is how that was caught.
SELECT is(
  (SELECT string_agg(
            format('schedule=%s|database=%s|username=%s|active=%s|command=%s|len=%s|md5=%s',
                   j.schedule, j."database", j.username, j.active::text, j.command,
                   length(j.command), md5(j.command)),
            ' ;; ' ORDER BY j.jobid)
     FROM cron.job j
    WHERE j.jobname = 'sweep-auth-password-changes'),
  'schedule=*/5 * * * *|database=postgres|username=postgres|active=true|command=select public.sweep_auth_password_changes();|len=44|md5=a8688b5b2add782b9a988d1f3850cd07',
  'D-5/8 (parity): schedule, database, username, active and the exact command bytes match production jobid 10');

-- 9. NO DUPLICATE, NO DRIFT — and NOT VACUOUS. The assertion this replaces was
--    an is_empty over drifted rows, which passed trivially on an un-migrated
--    replay because there were no rows to be drifted. This one reports both
--    numbers in one string, so:
--        0 rows        -> 'canonical=0 total=0'  FAIL (the un-migrated replay)
--        2 canonical   -> 'canonical=2 total=2'  FAIL (double-scheduled)
--        1 drifted     -> 'canonical=0 total=1'  FAIL (wrong schedule/command,
--                                                      or inactive)
--        1 + 1 drifted -> 'canonical=1 total=2'  FAIL
--        exactly right -> 'canonical=1 total=1'  PASS
--    There is no state in which it passes without the job being present, single
--    and canonical.
SELECT is(
  (SELECT format('canonical=%s total=%s',
            count(*) FILTER (
              WHERE schedule   = '*/5 * * * *'
                AND "database" = 'postgres'
                AND username   = 'postgres'
                AND command    = 'select public.sweep_auth_password_changes();'
                AND active),
            count(*))
     FROM cron.job
    WHERE jobname = 'sweep-auth-password-changes'),
  'canonical=1 total=1',
  'D-5/9 (no duplicate, no drift): every row under that jobname is canonical and there is exactly one — fails at zero rows too, so it cannot pass vacuously');

-- 10. The function the job calls exists and is SECURITY DEFINER. It must be:
--     only postgres can read auth.audit_log_entries — service_role cannot —
--     which is why this is a cron job and not an edge function. A schedule
--     pointing at a missing or INVOKER function is a silent no-op, so restoring
--     the schedule without this is worthless.
SELECT is(
  (SELECT p.prosecdef FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'sweep_auth_password_changes'),
  true,
  'D-5/10: public.sweep_auth_password_changes() exists and is SECURITY DEFINER');

-- 11. The watermark row the sweep reads FOR UPDATE is seeded (0600). Without
--     it the function returns immediately on NOT FOUND and the schedule
--     restored by 075 would still deliver nothing.
SELECT is(
  (SELECT count(*) FROM public.auth_audit_sweep_state
    WHERE sweep_name = 'auth_password_changed'),
  1::bigint,
  'D-5/11: the auth_password_changed sweep watermark row is seeded (0600)');

SELECT * FROM finish();
ROLLBACK;
