-- ============================================================================
-- 20261015000100_listing_duration_72h.sql — registry 155 (pgTAP 222).
-- Owner authorisation 2026-10-15 (A's chat): 72 h auction support, consistent everywhere.
--
-- WHAT.
--   1. listings_duration_hours_check gains 72 and nothing else:
--        before (baseline 000:88; production pg_get_constraintdef 2026-10-15):
--          CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48])))
--        after:
--          CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72])))
--   2. The end time is server-owned (ADDENDUM 2). Before this file ends_at was whatever the client sent
--      (CreateListingScreen / web create-listing compute Date.now() + duration on the device), so
--      duration_hours was only a label, and the seller could PATCH ends_at afterwards through the
--      listings UPDATE policies (guard_listing_state_columns does not cover it).
--      set_listing_ends_at_from_duration() (SECURITY INVOKER, search_path ''), trigger
--      trg_listing_ends_at_from_duration BEFORE INSERT OR UPDATE ON public.listings:
--        Trusted (untouched): the service_role SQL role with claims absent or service_role, or a
--          claims-less postgres session — the trust tests of guard_listing_insert_columns (072), read the
--          119 way (the `role` GUC, 'none' on a direct connection, else current_user), as 156 does.
--        INSERT, untrusted: NEW.ends_at := now() + make_interval(hours => NEW.duration_hours). The device
--          clock is irrelevant; a 72 h listing ends exactly 72 h after the insert.
--        UPDATE, untrusted: ends_at and duration_hours are frozen after creation -> 'Cannot change a
--          listing''s end time or duration after it is created.' unless app.bypass_listing_guard = 'on'
--          (set only inside the auction RPCs, exactly as guard_listing_state_columns honours it;
--          admin_relist_listing is the one RPC that writes ends_at). No shipped client sends either column
--          on UPDATE: app/listing/edit/[id].tsx and web seller-listings send event_name, venue,
--          restrictions and ticket_platform only.
--   Expiry is unchanged: auto_finalize_expired_auctions / finalize_auction act on ends_at.
--
-- GATE-2 census (public): functions +1 (set_listing_ends_at_from_duration, no-client-execute);
--   triggers +1 (trg_listing_ends_at_from_duration). Tables and policies unchanged.
-- ROLLBACK: supabase/rollbacks/20261015000100_listing_duration_72h_rollback.sql — refuses while any
--   listing has duration_hours = 72; otherwise drops the trigger and function (ends_at is client-set
--   again) and restores {1,3,6,12,24,48}.
-- VERIFY (read-only): select pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'public.listings'::regclass and conname = 'listings_duration_hours_check';
--   select tgname from pg_trigger where tgname = 'trg_listing_ends_at_from_duration';  -- 1 row
-- FAILURE BEHAVIOUR: one transaction; ACCESS EXCLUSIVE on listings while the new check validates every
--   row (113 in production: milliseconds); lock_timeout 3s, so it fails cleanly rather than queue.
-- OWNER APPROVAL POINT: prepared and tested locally only; applying it is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE public.listings DROP CONSTRAINT listings_duration_hours_check;
ALTER TABLE public.listings ADD CONSTRAINT listings_duration_hours_check
  CHECK (duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72]));

CREATE FUNCTION public.set_listing_ends_at_from_duration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
BEGIN
  -- Trust test of 072 (guard_listing_insert_columns), read the 119 way (as 156's guard does).
  v_role   := coalesce(nullif(current_setting('role', true), 'none'), current_user::text);
  v_claims := nullif(current_setting('request.jwt.claims', true), '');
  IF v_claims IS NOT NULL THEN
    BEGIN
      v_claim_role := v_claims::jsonb ->> 'role';
    EXCEPTION WHEN others THEN
      v_claim_role := NULL;   -- unparseable claims assert nothing
    END;
  END IF;
  IF v_role = 'service_role' AND coalesce(v_claim_role, 'service_role') = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF v_role = 'postgres' AND v_claims IS NULL THEN
    RETURN NEW;               -- migrations, cron, the SQL editor: no request context
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.ends_at := now() + make_interval(hours => NEW.duration_hours);   -- the server's clock, never the device's
    RETURN NEW;
  END IF;

  -- UPDATE, untrusted.
  IF current_setting('app.bypass_listing_guard', true) = 'on' THEN
    RETURN NEW;               -- an auction RPC that already decided (admin_relist_listing)
  END IF;
  IF NEW.ends_at IS DISTINCT FROM OLD.ends_at OR NEW.duration_hours IS DISTINCT FROM OLD.duration_hours THEN
    RAISE EXCEPTION 'Cannot change a listing''s end time or duration after it is created.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_END_TIME_FIXED';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.set_listing_ends_at_from_duration() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.set_listing_ends_at_from_duration() IS
  '155: BEFORE INSERT OR UPDATE on public.listings. Untrusted inserts get ends_at = now() + duration_hours (server clock); '
  'untrusted updates may not change ends_at or duration_hours unless an auction RPC set app.bypass_listing_guard. '
  'service_role / claims-less postgres pass untouched.';

DROP TRIGGER IF EXISTS trg_listing_ends_at_from_duration ON public.listings;
CREATE TRIGGER trg_listing_ends_at_from_duration
  BEFORE INSERT OR UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.set_listing_ends_at_from_duration();

COMMIT;
;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)
VALUES ('20261015000100', 'listing_duration_72h', ARRAY[$pkg155$-- ============================================================================
-- 20261015000100_listing_duration_72h.sql — registry 155 (pgTAP 222).
-- Owner authorisation 2026-10-15 (A's chat): 72 h auction support, consistent everywhere.
--
-- WHAT.
--   1. listings_duration_hours_check gains 72 and nothing else:
--        before (baseline 000:88; production pg_get_constraintdef 2026-10-15):
--          CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48])))
--        after:
--          CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72])))
--   2. The end time is server-owned (ADDENDUM 2). Before this file ends_at was whatever the client sent
--      (CreateListingScreen / web create-listing compute Date.now() + duration on the device), so
--      duration_hours was only a label, and the seller could PATCH ends_at afterwards through the
--      listings UPDATE policies (guard_listing_state_columns does not cover it).
--      set_listing_ends_at_from_duration() (SECURITY INVOKER, search_path ''), trigger
--      trg_listing_ends_at_from_duration BEFORE INSERT OR UPDATE ON public.listings:
--        Trusted (untouched): the service_role SQL role with claims absent or service_role, or a
--          claims-less postgres session — the trust tests of guard_listing_insert_columns (072), read the
--          119 way (the `role` GUC, 'none' on a direct connection, else current_user), as 156 does.
--        INSERT, untrusted: NEW.ends_at := now() + make_interval(hours => NEW.duration_hours). The device
--          clock is irrelevant; a 72 h listing ends exactly 72 h after the insert.
--        UPDATE, untrusted: ends_at and duration_hours are frozen after creation -> 'Cannot change a
--          listing''s end time or duration after it is created.' unless app.bypass_listing_guard = 'on'
--          (set only inside the auction RPCs, exactly as guard_listing_state_columns honours it;
--          admin_relist_listing is the one RPC that writes ends_at). No shipped client sends either column
--          on UPDATE: app/listing/edit/[id].tsx and web seller-listings send event_name, venue,
--          restrictions and ticket_platform only.
--   Expiry is unchanged: auto_finalize_expired_auctions / finalize_auction act on ends_at.
--
-- GATE-2 census (public): functions +1 (set_listing_ends_at_from_duration, no-client-execute);
--   triggers +1 (trg_listing_ends_at_from_duration). Tables and policies unchanged.
-- ROLLBACK: supabase/rollbacks/20261015000100_listing_duration_72h_rollback.sql — refuses while any
--   listing has duration_hours = 72; otherwise drops the trigger and function (ends_at is client-set
--   again) and restores {1,3,6,12,24,48}.
-- VERIFY (read-only): select pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'public.listings'::regclass and conname = 'listings_duration_hours_check';
--   select tgname from pg_trigger where tgname = 'trg_listing_ends_at_from_duration';  -- 1 row
-- FAILURE BEHAVIOUR: one transaction; ACCESS EXCLUSIVE on listings while the new check validates every
--   row (113 in production: milliseconds); lock_timeout 3s, so it fails cleanly rather than queue.
-- OWNER APPROVAL POINT: prepared and tested locally only; applying it is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE public.listings DROP CONSTRAINT listings_duration_hours_check;
ALTER TABLE public.listings ADD CONSTRAINT listings_duration_hours_check
  CHECK (duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72]));

CREATE FUNCTION public.set_listing_ends_at_from_duration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
BEGIN
  -- Trust test of 072 (guard_listing_insert_columns), read the 119 way (as 156's guard does).
  v_role   := coalesce(nullif(current_setting('role', true), 'none'), current_user::text);
  v_claims := nullif(current_setting('request.jwt.claims', true), '');
  IF v_claims IS NOT NULL THEN
    BEGIN
      v_claim_role := v_claims::jsonb ->> 'role';
    EXCEPTION WHEN others THEN
      v_claim_role := NULL;   -- unparseable claims assert nothing
    END;
  END IF;
  IF v_role = 'service_role' AND coalesce(v_claim_role, 'service_role') = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF v_role = 'postgres' AND v_claims IS NULL THEN
    RETURN NEW;               -- migrations, cron, the SQL editor: no request context
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.ends_at := now() + make_interval(hours => NEW.duration_hours);   -- the server's clock, never the device's
    RETURN NEW;
  END IF;

  -- UPDATE, untrusted.
  IF current_setting('app.bypass_listing_guard', true) = 'on' THEN
    RETURN NEW;               -- an auction RPC that already decided (admin_relist_listing)
  END IF;
  IF NEW.ends_at IS DISTINCT FROM OLD.ends_at OR NEW.duration_hours IS DISTINCT FROM OLD.duration_hours THEN
    RAISE EXCEPTION 'Cannot change a listing''s end time or duration after it is created.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_END_TIME_FIXED';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.set_listing_ends_at_from_duration() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.set_listing_ends_at_from_duration() IS
  '155: BEFORE INSERT OR UPDATE on public.listings. Untrusted inserts get ends_at = now() + duration_hours (server clock); '
  'untrusted updates may not change ends_at or duration_hours unless an auction RPC set app.bypass_listing_guard. '
  'service_role / claims-less postgres pass untouched.';

DROP TRIGGER IF EXISTS trg_listing_ends_at_from_duration ON public.listings;
CREATE TRIGGER trg_listing_ends_at_from_duration
  BEFORE INSERT OR UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.set_listing_ends_at_from_duration();

COMMIT;
$pkg155$], 'claude-a/owner-authorised-155');
