-- ============================================================================
-- a67_shim.sql (REBUILT 2026-09-02 for package 089) — LOCAL REPLAY TOOLING ONLY.
-- Why it exists: the migration chain is Supabase-flavoured SQL that references
-- objects Supabase's platform provides before any migration runs (the auth /
-- storage / vault / net / cron / extensions schemas, auth.users, auth.uid(),
-- storage.buckets/objects, storage.foldername(), cron.schedule/unschedule +
-- cron.job, net.http_post, vault.decrypted_secrets, the anon / authenticated /
-- service_role roles, the supabase_realtime publication). A plain PostgreSQL
-- cluster has none of them, so a local fresh replay needs this scaffolding
-- first. It is NOT part of the migration chain, changes no migration or
-- production semantics, seeds no data, and CI never uses it (CI replays on the
-- real Supabase local stack — the authoritative fresh replay). Provenance: the
-- original shim was lost mid-session; this file is the schema-only dump of the
-- scaffolding schemas from c087 (the last database the original shim built),
-- minus the objects the MIGRATIONS create inside those schemas (the
-- on_auth_user_created trigger, the storage.objects policies), plus the
-- cluster-level pieces (roles, publication) the dump cannot carry. Parity is
-- proven by replaying 001→088 through it and diffing the catalog against the
-- c087-clone + 088 path (identical) and by running the full pgTAP suite.
-- Known local-only gaps (unchanged from the original): no `authenticator` role
-- (test 131), no real pg_cron (test 132's cron.database_name; cron.schedule /
-- unschedule are stand-ins over a plain cron.job table — nothing ever fires),
-- net.http_post is a stand-in returning 1 (nothing is posted),
-- vault.decrypted_secrets is an EMPTY plain table (production: a decrypting
-- view — secret reads return NULL locally, so any secret-gated cron body is
-- inert here by construction), pgcrypto not installed (the platform
-- pre-installs it; PFA-28 is asserted structurally).
-- ============================================================================
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;
SET default_tablespace = '';
SET default_table_access_method = heap;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon')          THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')  THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
GRANT anon, authenticated, service_role TO postgres;
CREATE PUBLICATION supabase_realtime;
CREATE SCHEMA auth;


--
-- Name: cron; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA cron;


--
-- Name: extensions; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA extensions;


--
-- Name: net; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA net;


--
-- Name: storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA storage;


--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA vault;


--
-- Name: jwt(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.jwt() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  )
$$;


--
-- Name: role(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.role() RETURNS text
    LANGUAGE sql STABLE
    AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  )
$$;


--
-- Name: uid(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid
$$;


--
-- Name: schedule(text, text, text); Type: FUNCTION; Schema: cron; Owner: -
--

CREATE FUNCTION cron.schedule(jobname text, schedule text, command text) RETURNS bigint
    LANGUAGE sql
    AS $$
  INSERT INTO cron.job (jobname, schedule, command)
  VALUES (jobname, schedule, command)
  RETURNING jobid
$$;


--
-- Name: unschedule(text); Type: FUNCTION; Schema: cron; Owner: -
--

CREATE FUNCTION cron.unschedule(jobname text) RETURNS boolean
    LANGUAGE sql
    AS $$
  WITH d AS (DELETE FROM cron.job j WHERE j.jobname = unschedule.jobname RETURNING 1)
  SELECT count(*) > 0 FROM d
$$;


--
-- Name: http_post(text, jsonb, jsonb); Type: FUNCTION; Schema: net; Owner: -
--

CREATE FUNCTION net.http_post(url text, headers jsonb DEFAULT '{}'::jsonb, body jsonb DEFAULT '{}'::jsonb) RETURNS bigint
    LANGUAGE sql
    AS $$ SELECT 1::bigint $$;


--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT (string_to_array(name, '/'))[1:cardinality(string_to_array(name, '/')) - 1]
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payload json,
    created_at timestamp with time zone DEFAULT now(),
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud text,
    role text,
    email text,
    encrypted_password text,
    email_confirmed_at timestamp with time zone,
    phone text,
    phone_confirmed_at timestamp with time zone,
    raw_app_meta_data jsonb DEFAULT '{}'::jsonb,
    raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: job; Type: TABLE; Schema: cron; Owner: -
--

CREATE TABLE cron.job (
    jobid bigint NOT NULL,
    jobname text,
    schedule text,
    command text,
    active boolean DEFAULT true
);


--
-- Name: job_jobid_seq; Type: SEQUENCE; Schema: cron; Owner: -
--

ALTER TABLE cron.job ALTER COLUMN jobid ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME cron.job_jobid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    public boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: objects; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: decrypted_secrets; Type: TABLE; Schema: vault; Owner: -
--

CREATE TABLE vault.decrypted_secrets (
    id uuid DEFAULT gen_random_uuid(),
    name text,
    decrypted_secret text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: audit_log_entries audit_log_entries_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: job job_pkey; Type: CONSTRAINT; Schema: cron; Owner: -
--

ALTER TABLE ONLY cron.job
    ADD CONSTRAINT job_pkey PRIMARY KEY (jobid);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: users on_auth_user_created; Type: TRIGGER; Schema: auth; Owner: -
--



--
-- Name: objects objects_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: objects auction-media owner delete unreferenced; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects auction-media owner insert; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects auction-media owner update; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects avatars owner insert; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects avatars owner update; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: objects proof-docs owner delete unreferenced; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects proof-docs owner insert; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects proof-docs owner read; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects proof-docs owner update; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects proof-docs transfer party read; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: objects public read public buckets; Type: POLICY; Schema: storage; Owner: -
--



--
-- Name: SCHEMA auth; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA auth TO anon;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA auth TO service_role;


--
-- Name: SCHEMA extensions; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA extensions TO anon;
GRANT USAGE ON SCHEMA extensions TO authenticated;
GRANT USAGE ON SCHEMA extensions TO service_role;


--
-- Name: SCHEMA net; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA net TO PUBLIC;


--
-- Name: SCHEMA storage; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA storage TO anon;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT USAGE ON SCHEMA storage TO service_role;


--
-- Name: TABLE buckets; Type: ACL; Schema: storage; Owner: -
--

GRANT ALL ON TABLE storage.buckets TO anon;
GRANT ALL ON TABLE storage.buckets TO authenticated;
GRANT ALL ON TABLE storage.buckets TO service_role;


--
-- Name: TABLE objects; Type: ACL; Schema: storage; Owner: -
--

GRANT ALL ON TABLE storage.objects TO anon;
GRANT ALL ON TABLE storage.objects TO authenticated;
GRANT ALL ON TABLE storage.objects TO service_role;


--
-- PostgreSQL database dump complete
--



-- Supabase default privileges + public schema USAGE, read back from c087's catalog (the original shim's exact set)
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, SELECT, UPDATE ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, SELECT, UPDATE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO service_role;
