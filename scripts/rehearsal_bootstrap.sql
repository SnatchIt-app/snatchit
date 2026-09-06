-- ===========================================================================
-- scripts/rehearsal_bootstrap.sql — LOCAL MIGRATION-REHEARSAL BOOTSTRAP ONLY.
--
-- Purpose
--   Make a *vanilla* Homebrew PostgreSQL 17 database look enough like a fresh
--   Supabase database that supabase/migrations/*.sql can be replayed on it in
--   canonical order. It is scaffolding, NOT part of the migration chain: it is
--   never applied to staging or production, CI never uses it (CI's authoritative
--   fresh replay is `supabase start` on the real Supabase local stack), it seeds
--   no application data, and it changes no migration semantics.
--
-- Composition
--   1. cluster roles that Supabase provisions before migration 000 runs
--   2. \ir local/replay_shim.sql  — the pre-existing, catalog-diff-validated
--      scaffolding dump (auth / storage / cron / net / vault / extensions).
--      This file deliberately does NOT duplicate it; that file remains the
--      single source of truth for the shimmed object bodies.
--   3. fidelity supplements this harness adds on top of that shim (see below)
--
-- FIDELITY LEDGER — every object here that differs from real Supabase.
-- Read this before trusting a rehearsal result.
--
--   ROLES
--     postgres        SUPERUSER LOGIN. Supabase's owner role. Homebrew initdb
--                     names the bootstrap superuser after the OS user instead,
--                     so it must be created. Superuser in both -> faithful.
--     anon /          created by replay_shim.sql. NOLOGIN; service_role is
--     authenticated / BYPASSRLS as in Supabase. Faithful for grant/RLS tests.
--     service_role
--     authenticator   NOINHERIT LOGIN, member of the three above, holding no
--                     explicit grants. This is exactly PostgREST's connection
--                     role in Supabase, and it is what 131_privilege_cleanup
--                     probes. RISK: low — no migration references it (074 names
--                     it only in comments), so it changes nothing in the chain.
--     supabase_auth_admin / supabase_storage_admin / dashboard_user / pgbouncer
--                     NOT created. No migration or test resolves them (074
--                     mentions the first three in comments only). Anything that
--                     later grants to them would need them added here.
--
--   SCHEMAS/OBJECTS (from replay_shim.sql — see its header for provenance)
--     auth.uid()/role()/jwt()   GUC-reading stand-ins. Faithful in shape and
--                               return type; the tests drive them via
--                               request.jwt.claims exactly as PostgREST does.
--     auth.users, auth.audit_log_entries   column subsets, no GoTrue triggers.
--     storage.buckets/objects/foldername() column subsets of the Storage schema.
--                               No Storage API, no owner bookkeeping.
--     vault.decrypted_secrets   an EMPTY PLAIN TABLE. Production has a
--                               DECRYPTING VIEW. FIDELITY RISK (documented):
--                               every secret read returns NULL locally, so any
--                               secret-gated body (e.g. the 087 CRM export
--                               post) is inert here BY CONSTRUCTION. A
--                               rehearsal can therefore never exercise the
--                               secret-present branch of such code.
--     net.http_post()           stand-in returning 1::bigint. NOTHING IS EVER
--                               POSTED. FIDELITY RISK: notification/webhook
--                               side effects are structural-only locally.
--     cron.schedule/unschedule  stand-ins over a plain cron.job table.
--                               NO JOB EVER FIRES. FIDELITY RISK: schedule
--                               *registration* is rehearsed, execution is not.
--     supabase_realtime         empty publication (migrations add tables).
--
--   SUPPLEMENTS ADDED BY THIS FILE (beyond replay_shim.sql)
--     cron.job.nodename/nodeport/database/username
--                     pg_cron's real column set. Without them
--                     132_replay_parity ABORTS mid-file (`column j.database
--                     does not exist`) and its last 4 assertions never run.
--                     Populated faithfully: database = current_database(),
--                     username = current_user, exactly as pg_cron records them.
--                     FIDELITY RISK / KNOWN DELTA: production recorded
--                     database='postgres' because the chain ran in the
--                     database named `postgres`; a rehearsal database cannot
--                     be named `postgres`, so 132's D-5/8 and D-5/9 report the
--                     rehearsal database name and FAIL. That is a database-NAME
--                     artifact of the harness, not schema drift. Do not "fix"
--                     it by hardcoding 'postgres' — that would fabricate parity.
--     pgcrypto, uuid-ossp in `extensions`
--                     Supabase pre-installs both. The chain does not need them
--                     (only gen_random_uuid() is used, built into PG13+), but
--                     installing them keeps "no migration creates an extension"
--                     assertions honest rather than vacuous.
-- ===========================================================================

\set ON_ERROR_STOP on

-- 1. Cluster roles Supabase provisions before migration 000. -----------------
--    CREATE ROLE is cluster-wide; guarded so the file is idempotent across
--    repeated rehearsals in the same cluster.
DO $bootstrap$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
    CREATE ROLE postgres LOGIN SUPERUSER CREATEDB CREATEROLE;
  END IF;
END
$bootstrap$;

-- 2. The validated Supabase scaffolding dump. --------------------------------
--    Path is relative to THIS file (psql \ir), so the harness works from any cwd.
\ir local/replay_shim.sql

-- --------------------------------------------------------------------------
-- replay_shim.sql leaves search_path = '' set for the session; everything
-- below is fully schema-qualified on purpose.
-- --------------------------------------------------------------------------

-- 3a. authenticator: PostgREST's NOINHERIT connection role. -------------------
DO $bootstrap$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT;
  END IF;
END
$bootstrap$;
GRANT anon, authenticated, service_role TO authenticator;

-- 3b. cron.job: pg_cron's real column set. ------------------------------------
ALTER TABLE cron.job ADD COLUMN IF NOT EXISTS nodename text    DEFAULT 'localhost';
ALTER TABLE cron.job ADD COLUMN IF NOT EXISTS nodeport integer DEFAULT 5432;
ALTER TABLE cron.job ADD COLUMN IF NOT EXISTS "database" text  DEFAULT pg_catalog.current_database();
ALTER TABLE cron.job ADD COLUMN IF NOT EXISTS username text    DEFAULT CURRENT_USER;

-- 3c. Extensions the Supabase platform pre-installs. --------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto    WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
