-- ===========================================================================
-- scripts/local/replay_shim_supplements.sql — fidelity supplements applied
-- AFTER scripts/local/replay_shim.sql, by ALL THREE local paths:
--   * scripts/rehearsal_bootstrap.sql  (\ir, the certified rehearsal_reset path)
--   * scripts/release/convergence_prod_order_rehearsal.sh (FRESH and PROD)
--   * scripts/local/replay.sh          (added 2026-09-22 — see below)
-- Until 2026-09-15 only the bootstrap applied these, so the production-order
-- path lacked every supplement (D found it on 131: "relation auth.sessions
-- does not exist"). The same omission then survived in replay.sh for another
-- week: it cost D a run and A a production-order rehearsal on 2026-09-22,
-- with the identical 131 error, because this header said "two callers" while a
-- third existed. One file, THREE callers, one truth — if you add a fourth,
-- add it here too. Ledger entries for each
-- object live in rehearsal_bootstrap.sql's FIDELITY LEDGER; do not duplicate.
-- Idempotent: every statement is IF NOT EXISTS / guarded.
-- ===========================================================================
\set ON_ERROR_STOP on

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

-- 3d. auth.sessions: column subset of GoTrue's table (see the ledger). ---------
CREATE TABLE IF NOT EXISTS auth.sessions (
  id           uuid        PRIMARY KEY,
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at   timestamptz,
  updated_at   timestamptz,
  not_after    timestamptz,
  refreshed_at timestamp,
  aal          text
);
CREATE INDEX IF NOT EXISTS sessions_user_id_idx ON auth.sessions (user_id);
