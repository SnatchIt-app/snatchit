-- 073_drift_reconciliation_grants_storage_cron.sql
-- =============================================================================
-- DRIFT-1 REMEDIATION. Reconciles four independent source/production
-- divergences found by the read-only drift audit, plus one EXECUTE-posture
-- cleanup that source and production already agree on.
--
-- PURPOSE
--   Make the migration chain and the production database describe the SAME
--   authorization surface, in both directions:
--     * where production is WEAKER than source, tighten production (SEC-1, SEC-3);
--     * where a fresh replay is WEAKER than production, tighten the replay
--       (SEC-4, D-5) so a from-source rebuild is not a downgrade.
--
-- READ THIS BEFORE APPLYING TO PRODUCTION. The statements below are NOT
-- uniform in effect. Grouped explicitly:
--
--   CHANGES PRODUCTION
--     §1 SEC-1  revoke anon/authenticated DML on public.webhook_retries
--     §2 SEC-3  set file_size_limit + allowed_mime_types on all three buckets
--     §5 EXEC   strip PUBLIC/anon EXECUTE from six public functions
--
--   NO-OP ON PRODUCTION (fixes the fresh-replay rebuild only)
--     §3 SEC-4  drop six orphan storage.objects policies that exist only on a
--               from-source rebuild. Guarded by an existence check, so on
--               production ZERO DDL is attempted (see §3 for why that matters).
--     §4 D-5    vendor the sweep-auth-password-changes cron schedule. Guarded
--               by an exact schedule+command+active match, so production's
--               existing jobid 10 is left completely untouched.
--
-- EVIDENCE (production catalog, read-only, 2026-08-27, project hqycwntpfoztoinemqns)
--   webhook_retries relacl : {postgres=arwdDxtm/postgres, anon=arwdm/postgres,
--                             authenticated=arwdm/postgres, service_role=arwdDxtm/postgres}
--                            RLS enabled, 0 policies, 0 rows.
--   storage.buckets        : all three rows have file_size_limit IS NULL and
--                            allowed_mime_types IS NULL.
--   storage.objects        : 11 policies; none of the six §3 names present.
--   cron.job               : jobid 10, sweep-auth-password-changes, '*/5 * * * *',
--                            'select public.sweep_auth_password_changes();', active.
--   pg_default_acl         : public/r and public/f grant anon+authenticated (see §6).
--
-- COMPATIBILITY
--   Metadata only. No table is rewritten, no row of application data is read or
--   written, no function body changes. Every object-size and MIME constraint in
--   §2 was checked against the live object inventory first (§2 records the counts).
--
-- EXPECTED LOCKS / RUNTIME
--   Catalog-row locks only; three single-row UPDATEs on storage.buckets.
--   Milliseconds. No ACCESS EXCLUSIVE lock on any application table.
--
-- ROLLBACK
--   supabase/rollbacks/073_drift_reconciliation_grants_storage_cron_rollback.sql
--   Read its header first: §1 is not honestly reversible without reintroducing
--   the security regression it closes.
--
-- VERIFICATION (after apply)
--   select relacl from pg_class where oid='public.webhook_retries'::regclass;
--     -- expect NO anon= or authenticated= entry
--   select id, file_size_limit, allowed_mime_types from storage.buckets order by id;
--     -- expect 10485760 / 5242880 / 10485760 and non-null MIME arrays
--   select count(*) from pg_policies where schemaname='storage' and tablename='objects';
--     -- expect 11 on production (unchanged); 11 on a fresh replay (was 17)
--   select jobid, schedule, active from cron.job where jobname='sweep-auth-password-changes';
--     -- expect jobid 10 unchanged on production; one active row on a fresh replay
--   select has_function_privilege('anon','public.is_winner(uuid,uuid)','EXECUTE');        -- false
--   select has_function_privilege('authenticated','public.is_winner(uuid,uuid)','EXECUTE'); -- true
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- §1. SEC-1 — public.webhook_retries client DML  [CHANGES PRODUCTION]
-- ---------------------------------------------------------------------------
-- Migration 069 (line 22) already contains exactly this revoke, and the ledger
-- records 069 as executed. Production nonetheless still grants anon and
-- authenticated arwdm. The revoke never took effect.
--
-- Why we believe that rather than "something re-granted it": aclitem arrays are
-- append-ordered. Every table in this database where a migration revoked and
-- then re-granted a client role shows those roles moved to the END of the acl
-- array. webhook_retries shows the pristine default-privilege ordering
-- (postgres, anon, authenticated, service_role) — the shape of a table whose
-- ACL was written once, by the pg_default_acl in §6, and never edited since.
--
-- Live exposure today is nil and was verified, not assumed: RLS is enabled,
-- there are zero policies (deny-all), and the table holds zero rows. This is a
-- defence-in-depth regression, not an active leak — but it is one accidental
-- `ALTER TABLE ... DISABLE ROW LEVEL SECURITY`, or one permissive policy added
-- for an unrelated reason, away from being a live one.
--
-- Re-issued idempotently. REVOKE of an absent privilege is a no-op, so this is
-- safe to replay and safe on a fresh database where 069 already did the work.
REVOKE ALL ON public.webhook_retries FROM PUBLIC, anon, authenticated;

-- service_role is deliberately NOT re-granted here. It is not affected by the
-- revoke above, and it already holds arwdDxtm in production (from the §6
-- default ACL) and receives its grants in CI from supabase/ci/parity_grants.sql.
-- Encoding service_role table grants into the migration chain is finding
-- REPLAY-1 — a real gap, but an explicit, separate owner decision that this
-- repo has deliberately not taken yet. This migration does not take it either.

-- ---------------------------------------------------------------------------
-- §2. SEC-3 — storage bucket size / MIME constraints  [CHANGES PRODUCTION]
-- ---------------------------------------------------------------------------
-- 000_baseline_schema.sql specifies file_size_limit and allowed_mime_types for
-- auction-media (10 MB) and avatars (5 MB) — but does so with
-- `insert ... on conflict (id) do nothing`. Both buckets already existed in
-- production (created 2026-02-20 and 2026-02-23, before the baseline was
-- written), so the INSERT hit the conflict path and the constraints were
-- silently discarded. Production has NULL for both columns on all three
-- buckets, meaning the storage API enforces NO server-side size or type limit
-- on any upload. Today the only enforcement is client-side, in code an
-- attacker calling the storage REST API directly never executes.
--
-- SAFETY PRE-CHECK against the live object inventory (read-only, 2026-08-27):
--   auction-media  134 objects, max 6,361,057 B, 0 over 10 MB
--   avatars          9 objects, max   612,685 B, 0 over  5 MB
--   proof-docs      29 objects, max 4,143,632 B, 0 over 10 MB
--   MIME types in use across ALL buckets: image/jpeg and image/png only.
-- Every existing object satisfies the constraints set below. Nothing already
-- stored is invalidated. (allowed_mime_types is enforced at upload time, not
-- retroactively, but the check was done anyway so the numbers are on record.)
UPDATE storage.buckets
   SET file_size_limit    = 10485760,   -- 10 MB, = APP_CONFIG.MAX_IMAGE_SIZE_MB
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/heic']
 WHERE id = 'auction-media';

UPDATE storage.buckets
   SET file_size_limit    = 5242880,    -- 5 MB, = APP_CONFIG.MAX_AVATAR_SIZE_MB
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/heic']
 WHERE id = 'avatars';

-- proof-docs: a DELIBERATE DEPARTURE from the baseline's image-only list.
--
-- The baseline never specified constraints for this bucket at all (033 created
-- it with id/name/public only), so there is no "source intent" to restore — the
-- constraint had to be chosen. Copying the other two buckets' 4-type image list
-- would have been the tidy-looking choice and would have BROKEN A LIVE SELLER
-- FLOW: web/src/lib/evidence-upload.ts (ALLOWED_EVIDENCE_TYPES) deliberately
-- accepts application/pdf — PDF receipts as ticket-transfer evidence — and
-- image/heif, neither of which is in that list. Production holds no PDF yet
-- only because the web transfer-evidence path is new, not because PDFs are
-- disallowed.
--
-- The allowlist below is therefore the exact union of what the three real
-- writers send, so it cannot reject a legitimate upload:
--   src/hooks/useImageUpload.ts        -> image/jpeg|png|webp|heic   (mobile)
--   web/src/lib/create-listing.ts      -> APP_CONFIG.ALLOWED_IMAGE_TYPES (same 4)
--   web/src/lib/transfers.ts           -> ALLOWED_EVIDENCE_TYPES (those 4 + heif + pdf)
-- and the size limit matches MAX_EVIDENCE_SIZE_MB = 10, which that same module
-- already enforces client-side.
--
-- Rationale for constraining it at all rather than leaving it NULL: proof-docs
-- is the most sensitive bucket the platform has (ownership proofs, ticket
-- screenshots, ID-adjacent material) and its INSERT policy lets ANY
-- authenticated user write into their own folder. Unconstrained, that is an
-- unbounded-size write primitive, and a path to storing an arbitrary
-- content-type — text/html included — that a signed URL would later serve back
-- from the storage origin. Moving the existing client-side validation to the
-- server closes the direct-to-storage-API bypass. This is defence in depth on
-- top of the RLS policies, not a replacement for them.
UPDATE storage.buckets
   SET file_size_limit    = 10485760,   -- 10 MB, = MAX_EVIDENCE_SIZE_MB
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp',
                                  'image/heic','image/heif','application/pdf']
 WHERE id = 'proof-docs';

-- ---------------------------------------------------------------------------
-- §3. SEC-4 — six orphan storage.objects policies  [NO-OP ON PRODUCTION]
-- ---------------------------------------------------------------------------
-- 000_baseline_schema.sql (blocks 5 and 12) creates six storage.objects
-- policies. NO later migration drops them. Production does not have them —
-- they were superseded out-of-band by the scoped policies that 048/049/051/053
-- install. The result is that a from-source rebuild produces 17 storage
-- policies where production has 11, and the six extras are STRICTLY WEAKER
-- than what they sit beside:
--
--   * they are TO PUBLIC, where the surviving production policies are TO
--     authenticated — so on a rebuild the upload/delete paths are open to anon;
--   * "storage: owner delete" and "avatars: owner delete" have no
--     "unreferenced" guard, where 048/049 added exactly that so a seller cannot
--     delete an image a live listing or transfer still points at.
--
-- A rebuilt-from-source database is therefore not a faithful copy of
-- production: it is production with a weaker storage authorization surface.
-- Dropping them here makes the rebuild match.
--
-- WHY THE EXISTENCE GUARD, and why it is not defensive boilerplate:
-- `postgres` does not own storage.objects in production (owner is
-- supabase_storage_admin) and is not a member of that role — verified. A bare
-- `DROP POLICY IF EXISTS ... ON storage.objects` still requires table
-- ownership, so depending on the applying role it could ERROR and abort this
-- entire migration on production, for six policies that are not even there.
-- Locally the migration role is superuser, so the drops succeed on a fresh
-- replay. The guard makes the outcome identical and safe in both environments:
-- production attempts ZERO DDL here, a fresh replay drops exactly six.
DO $$
DECLARE
  p text;
BEGIN
  FOREACH p IN ARRAY ARRAY[
    'storage: public read',
    'storage: owner upload',
    'storage: owner delete',
    'avatars: public read',
    'avatars: owner upload',
    'avatars: owner delete'
  ] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_policies
       WHERE schemaname = 'storage'
         AND tablename  = 'objects'
         AND policyname = p
    ) THEN
      EXECUTE format('DROP POLICY %I ON storage.objects', p);
      RAISE NOTICE '073: dropped orphan storage policy %', p;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- §4. D-5 — vendor the password-change sweep cron schedule  [NO-OP ON PRODUCTION]
-- ---------------------------------------------------------------------------
-- Production runs cron job 10, 'sweep-auth-password-changes', every 5 minutes.
-- It is what turns an auth.audit_log_entries password-change row into a
-- security notification in the user's inbox. NO migration schedules it — 0600
-- only mentions it in a comment ("Scheduled: sweep-auth-password-changes @
-- */5 * * * *, active"), which is a note about an out-of-band action, not the
-- action itself. A database rebuilt from this repo has the function
-- (0600/0601) but nothing ever calls it, so password-change security
-- notifications silently stop. Silently is the problem: nothing errors.
--
-- The command string below is transcribed verbatim from production
-- cron.job.command, not reconstructed.
--
-- The guard makes this a TRUE no-op on production rather than a
-- delete-and-recreate: production's row already matches on name, schedule,
-- command and active, so cron.unschedule is never reached and jobid 10 keeps
-- its identity and its run history. On a fresh replay the row is absent and
-- the job is created. The unschedule-first branch exists for the third case —
-- a database where the job exists but DRIFTS from this definition.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job
     WHERE jobname  = 'sweep-auth-password-changes'
       AND schedule = '*/5 * * * *'
       AND command  = 'select public.sweep_auth_password_changes();'
       AND active
  ) THEN
    PERFORM cron.unschedule(jobname)
       FROM cron.job
      WHERE jobname = 'sweep-auth-password-changes';

    PERFORM cron.schedule(
      'sweep-auth-password-changes',
      '*/5 * * * *',
      'select public.sweep_auth_password_changes();'
    );
    RAISE NOTICE '073: scheduled sweep-auth-password-changes';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- §5. PUBLIC EXECUTE cleanup — six functions 067 missed  [CHANGES PRODUCTION]
-- ---------------------------------------------------------------------------
-- Not drift: source and production agree. These six public functions still
-- carry `=X/postgres` (EXECUTE to PUBLIC) plus explicit anon/authenticated
-- grants, all inherited from the pg_default_acl in §6. Migration 067 swept this
-- class of function and did not reach them. All six are prosecdef = false.
--
-- Group A — trigger functions. RETURNS trigger, so PostgreSQL refuses a direct
-- call ("trigger functions can only be called as triggers") regardless of any
-- grant, and firing a trigger does not consult the caller's EXECUTE privilege
-- at all. Revoking from all three client roles is therefore provably
-- behaviour-preserving. Same treatment, same reasoning, as 067 Group A.
REVOKE EXECUTE ON FUNCTION public.dispute_resolutions_append_only()      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.guard_transfer_state_columns()         FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reset_transfer_guard_bypass()          FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_ambassador_application_updated_at() FROM PUBLIC, anon, authenticated;

-- Group B — read-only helpers. These two are the ones that needed evidence
-- before touching, because a reader CAN be invoked by a client over PostgREST
-- and CAN appear inside an RLS policy, where EXECUTE *is* checked.
--
-- Call sites established (or rather, their absence established):
--   * pg_policies: no policy on any schema references either function. Queried
--     directly against production.
--   * No other function body, view definition or check constraint in production
--     references either name.
--   * Repo: zero references in app/, src/, web/ or supabase/functions/. The
--     grep enumerated all 33 distinct names passed to `.rpc(` across the mobile
--     app, the web app and the edge functions; neither appears. The same grep
--     does find can_create_listing, get_profile_trust_stats, finalize_auction
--     and so on, so it is finding real call sites, not silently failing.
--
-- So anon EXECUTE is unused, and is removed. Note also that is_blocked_by_me is
-- structurally meaningless to anon: its body is
-- `blocker_id = auth.uid()`, which for an anonymous session is NULL, so it can
-- only ever return false.
--
-- authenticated is DELIBERATELY RETAINED even though no call site exists today.
-- is_blocked_by_me was written to be a feed-filter RLS predicate — the design
-- ticket specifies `USING (NOT public.is_blocked_by_me(seller_id))` on listings
-- — and the feature's user_blocks table is live in production with its policies
-- in place. If that predicate ships, authenticated MUST hold EXECUTE or every
-- signed-in listing read fails. Removing a grant that costs nothing to keep, in
-- order to tidy an ACL, is how a security cleanup becomes an outage.
--
-- Same shape as 067 Group C: drop anon and PUBLIC, keep the roles that plausibly
-- call it. This also supersedes migration 063's comment, which listed both
-- functions as "read-only helpers anon legitimately needs while browsing
-- signed-out" — 067 already overrode that same sentence for can_create_listing
-- and get_profile_trust_stats with no ill effect.
REVOKE EXECUTE ON FUNCTION public.is_blocked_by_me(uuid)        FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.is_blocked_by_me(uuid)        TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.is_winner(uuid, uuid)         FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.is_winner(uuid, uuid)         TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- §6. SEC-2 — the forward risk. NO SQL HERE, DELIBERATELY.
-- ---------------------------------------------------------------------------
-- Production's pg_default_acl on schema public (verified 2026-08-27):
--
--   public / r (TABLE)    postgres        -> anon=arwdm,    authenticated=arwdm
--   public / r (TABLE)    supabase_admin  -> anon=arwdDxtm, authenticated=arwdDxtm
--   public / f (FUNCTION) postgres        -> anon=X,        authenticated=X
--   public / f (FUNCTION) supabase_admin  -> anon=X,        authenticated=X
--
-- Read that plainly: EVERY new table created in public is automatically granted
-- SELECT/INSERT/UPDATE/DELETE to anon and authenticated, and EVERY new function
-- is automatically anon-EXECUTE — which means PostgREST-callable at
-- /rest/v1/rpc/<name> by an unauthenticated caller. This is the mechanism that
-- produced SEC-1 above: 069 created webhook_retries and the default ACL granted
-- the client roles before 069's own revoke line was reached or took effect.
--
-- It also means EVERY PHASE-2 TABLE WILL SHIP OPEN unless its own migration
-- explicitly revokes. That is a property of the next several dozen migrations,
-- not of this one.
--
-- These default ACLs are VENDOR-MANAGED. Supabase's provisioning depends on
-- them; removing them would break new-object provisioning across the project.
-- So this migration does not touch them. The countermeasure is procedural and
-- automated instead:
--   1. A standing rule in docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md
--      §5 and docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md
--      §4: every migration creating a table or function in public MUST end with
--      an explicit REVOKE ALL ... FROM PUBLIC, anon, authenticated, followed by
--      only the grants it actually needs.
--   2. A CI assertion that fails CLOSED when a public table appears in the
--      fresh replay with no recorded grant decision:
--      supabase/ci/assert_public_table_grant_decisions.sql.
-- The rule alone would not have caught SEC-1 — 069 followed the rule and the
-- revoke still did not land. The CI assertion is the part that would.

COMMIT;
