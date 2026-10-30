-- ============================================================================
-- 20261015000200_listing_proof_owner_waiver.sql — registry 156 (pgTAP 223).
-- An explicit, recorded owner proof waiver for an admin's own inventory, never marked verified.
-- Owner authorisation 2026-10-15 (A's chat). Addendum (F's request, A approved): current_user_is_admin().
--
-- WHAT.
--   1. public.listings gains three nullable columns: proof_waived_at timestamptz, proof_waived_by uuid,
--      proof_waiver_reason text (1..300 chars when set). listings_proof_waiver_all_or_none: all three are
--      NULL together or all three are set. ADD COLUMN without a default rewrites nothing.
--   2. guard_listing_proof_waiver() (SECURITY DEFINER: it reads public.admin_users, which is deny-all;
--      search_path ''), trigger trg_guard_listing_proof_waiver BEFORE INSERT OR UPDATE ON public.listings.
--        Trusted (allowed as-is): the service_role SQL role with claims absent or service_role, or a
--          claims-less postgres session — the trust tests of guard_listing_insert_columns (072), read the
--          119 way for a definer body (the PostgREST SET ROLE is the `role` GUC; 'none' on a direct
--          connection, where current_user is the owner).
--        INSERT, untrusted: three NULLs pass when a proof path is present (§4). Otherwise ALL of: proof_waived_by = auth.uid(); seller_id =
--          auth.uid(); the caller is in public.admin_users; proof_of_ownership_path IS NULL; a reason with
--          a non-blank character. Then proof_waived_at := now(), overriding whatever the client sent.
--          Anything else: 'Only an admin listing its own inventory can record an owner proof waiver.'
--        UPDATE, untrusted: the three fields must be NOT DISTINCT FROM OLD, else 'An owner proof waiver
--          is recorded only when the listing is created.' (No adding, rewriting or clearing later.)
--      proof_status is untouched by the guard: guard_proof_status (071) keeps clients at 'pending_review',
--      and the §5(b) CHECK keeps every other caller from approving a waived listing.
--   3. public.current_user_is_admin(): the caller's own boolean only (EXISTS admin_users for auth.uid()).
--      authenticated-execute; anon and PUBLIC revoked. The web /sell page uses it to show the waiver box.
--   4. ADDENDUM 3b (proof stays required): an untrusted INSERT with all three waiver fields NULL must carry
--      a non-blank proof_of_ownership_path, else 'Upload proof of ownership.' (HINT PROOF_REQUIRED). Every
--      shipped producer already sends one (native CreateListingScreen returns before the insert without
--      it; web create-listing types it required; RC9 and web #108 too). Trusted callers are unchanged.
--   5. Review fixes:
--      (b) CHECK listings_proof_waiver_never_approved: NOT (proof_waived_at IS NOT NULL AND proof_status =
--          'approved'). No caller (service_role, postgres, ops.* definers included) can approve a waived
--          listing, or create one already approved.
--      (c) the guard's UPDATE branch also refuses an untrusted change of proof_of_ownership_path on a
--          waived listing ('A listing with an owner proof waiver cannot take a proof of ownership.'), so a
--          waiver is never mixed with a client-supplied proof.
--   6. ADDENDUM 3a, the old-build purchase safeguard. Builds 25/27 cannot show the waiver disclosure, so a
--      bid or a NEW Buy Now hold on a waived listing needs the request to say the client can:
--        client_shows_proof_disclosure(): STABLE, invoker, search_path '', no-client-execute. True only if
--          request.headers (PostgREST: a JSON object, lower-cased names) ->> 'x-snatchit-caps' holds the
--          whole token proof-disclosure-v1 among space/comma separated tokens. NULL, empty, unparseable or
--          non-string -> false. RC9 sends it on every request (src/config/clientCapabilities.ts); web #108
--          on the cookie server client, which places every bid and reserve_buy_now.
--        trg_bid_requires_disclosure BEFORE INSERT ON bids -> guard_bid_requires_disclosure(): on a waived
--          listing, an untrusted caller without the token gets 'This listing needs the latest Snatch It
--          app. Update the app or use app.snatchitapp.com.' with HINT LISTING_UNAVAILABLE (builds 25/27
--          show "Not available", never "we couldn't confirm your bid").
--        trg_reservation_requires_disclosure BEFORE UPDATE OF reserved_by ON listings ->
--          guard_reservation_requires_disclosure(): when the row is waived and gets a NEW holder (NEW
--          reserved_by not NULL and distinct from OLD: NULL -> buyer, which is every reserve_buy_now
--          because it sweeps a lapsed hold to NULL first, and also buyer A -> buyer B, like 152's party
--          guard), an untrusted caller without the token gets the same message with NO hint (builds 25/27
--          show "Reservation failed — <message>"; it says neither "sold" nor "already reserved").
--          Releasing a hold (reserved_by -> NULL) is never checked.
--        Trust test (both): the guards' test read the 119 way, i.e. the PostgREST role GUC and the request
--          claims, never current_user alone. reserve_buy_now is SECURITY DEFINER, so current_user there is
--          the owner; the role GUC still says 'authenticated' and the claims are present, so a client call
--          is untrusted. Trusted = service_role (claims absent or service_role) or a claims-less postgres
--          session (migrations, cron, the SQL editor). A postgres session that carries claims is untrusted.
-- DISPLAY CONTRACT (clients): "Ticket proof waived by Snatch It" when proof_waived_at IS NOT NULL; never
--   show proof_waived_by or the reason; a waived listing's seller badge reads "Verified seller", never a bare
--   "Verified". NOTE: anon/authenticated hold table-level SELECT on listings, so the reason and waived_by
--   (which always equals seller_id) are readable through PostgREST like every other listings column.
--
-- GATE-2 census (public), on top of 154 + 155: functions 121 -> 126 (+guard_listing_proof_waiver,
--   current_user_is_admin, client_shows_proof_disclosure, guard_bid_requires_disclosure,
--   guard_reservation_requires_disclosure); triggers 46 -> 49 (+trg_guard_listing_proof_waiver,
--   trg_reservation_requires_disclosure on listings, trg_bid_requires_disclosure on bids). Tables and
--   policies unchanged.
-- ROLLBACK: supabase/rollbacks/20261015000200_listing_proof_owner_waiver_rollback.sql — REFUSES while any
--   listing carries a waiver (archival record; and leaving the columns without the guard would let any
--   client write a waiver); otherwise drops the three triggers, the five functions, the three checks and
--   the three columns. Rule (F): never roll web back past #108 while a waived listing is live.
-- VERIFY (read-only): select tgname from pg_trigger where tgname in ('trg_guard_listing_proof_waiver',
--   'trg_bid_requires_disclosure', 'trg_reservation_requires_disclosure'); -- 3 rows
-- FAILURE BEHAVIOUR: one transaction; ACCESS EXCLUSIVE on listings for the column adds and check validation
--   (113 rows, all NULL); brief SHARE ROW EXCLUSIVE on bids for its trigger; lock_timeout 3s, so it fails
--   cleanly rather than queue.
-- OWNER APPROVAL POINT: prepared and tested locally only; applying it is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 1. columns ──────────────────────────────────────────────────────────────
ALTER TABLE public.listings
  ADD COLUMN proof_waived_at     timestamptz NULL,
  ADD COLUMN proof_waived_by     uuid        NULL,
  ADD COLUMN proof_waiver_reason text        NULL
    CONSTRAINT listings_proof_waiver_reason_check
    CHECK (proof_waiver_reason IS NULL OR char_length(proof_waiver_reason) BETWEEN 1 AND 300);
ALTER TABLE public.listings ADD CONSTRAINT listings_proof_waiver_all_or_none CHECK (
     (proof_waived_at IS NULL     AND proof_waived_by IS NULL     AND proof_waiver_reason IS NULL)
  OR (proof_waived_at IS NOT NULL AND proof_waived_by IS NOT NULL AND proof_waiver_reason IS NOT NULL));
-- A waived listing is never 'approved' (never shown as verified), whoever writes it.
ALTER TABLE public.listings ADD CONSTRAINT listings_proof_waiver_never_approved CHECK (
  NOT (proof_waived_at IS NOT NULL AND proof_status = 'approved'));
COMMENT ON COLUMN public.listings.proof_waived_at IS
  '156: when an admin recorded an owner proof waiver for their own listing (server time; set only at creation).';
COMMENT ON COLUMN public.listings.proof_waived_by IS
  '156: the admin who recorded the waiver; always the listing''s seller. Never displayed.';
COMMENT ON COLUMN public.listings.proof_waiver_reason IS
  '156: the admin''s recorded reason for the waiver (1..300 chars). Never displayed.';

-- ── 2. the guard ────────────────────────────────────────────────────────────
CREATE FUNCTION public.guard_listing_proof_waiver()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
  v_uid        uuid;
BEGIN
  -- Trust test of 072 (guard_listing_insert_columns), read the 119 way inside a definer body.
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

  IF TG_OP = 'UPDATE' THEN
    IF NEW.proof_waived_at     IS DISTINCT FROM OLD.proof_waived_at
       OR NEW.proof_waived_by     IS DISTINCT FROM OLD.proof_waived_by
       OR NEW.proof_waiver_reason IS DISTINCT FROM OLD.proof_waiver_reason THEN
      RAISE EXCEPTION 'An owner proof waiver is recorded only when the listing is created.'
        USING ERRCODE = 'P0001', HINT = 'PROOF_WAIVER_FROZEN';
    END IF;
    -- the waiver stays clean: a client cannot attach a proof to a waived listing afterwards
    IF OLD.proof_waived_at IS NOT NULL
       AND NEW.proof_of_ownership_path IS DISTINCT FROM OLD.proof_of_ownership_path THEN
      RAISE EXCEPTION 'A listing with an owner proof waiver cannot take a proof of ownership.'
        USING ERRCODE = 'P0001', HINT = 'PROOF_WAIVER_FROZEN';
    END IF;
    RETURN NEW;
  END IF;

  -- INSERT. No waiver: the normal proof stays required (ADDENDUM 3b).
  IF NEW.proof_waived_at IS NULL AND NEW.proof_waived_by IS NULL AND NEW.proof_waiver_reason IS NULL THEN
    IF NOT coalesce(NEW.proof_of_ownership_path ~ '\S', false) THEN
      RAISE EXCEPTION 'Upload proof of ownership.'
        USING ERRCODE = 'P0001', HINT = 'PROOF_REQUIRED';
    END IF;
    RETURN NEW;
  END IF;
  v_uid := auth.uid();
  IF v_uid IS NOT NULL
     AND NEW.proof_waived_by IS NOT DISTINCT FROM v_uid
     AND NEW.seller_id       IS NOT DISTINCT FROM v_uid
     AND EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id = v_uid)
     AND NEW.proof_of_ownership_path IS NULL
     AND coalesce(NEW.proof_waiver_reason ~ '\S', false) THEN
    NEW.proof_waived_at := now();   -- the server's time, never the client's
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Only an admin listing its own inventory can record an owner proof waiver.'
    USING ERRCODE = 'P0001', HINT = 'PROOF_WAIVER_NOT_ALLOWED';
END;
$$;
REVOKE ALL ON FUNCTION public.guard_listing_proof_waiver() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_listing_proof_waiver() IS
  '156: BEFORE INSERT OR UPDATE on public.listings. Untrusted callers may record an owner proof waiver only at '
  'creation, only as an admin listing their own inventory with no proof path and a reason (waived_at stamped '
  'now()); the three waiver fields are frozen for clients afterwards, and a waived listing takes no client proof '
  'path later. Without a waiver an untrusted create needs a non-blank proof path. service_role / claims-less '
  'postgres pass.';

DROP TRIGGER IF EXISTS trg_guard_listing_proof_waiver ON public.listings;
CREATE TRIGGER trg_guard_listing_proof_waiver
  BEFORE INSERT OR UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_listing_proof_waiver();

-- ── 3. the caller's own admin bit (web /sell) ───────────────────────────────
CREATE FUNCTION public.current_user_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = (SELECT auth.uid()))
$$;
REVOKE ALL ON FUNCTION public.current_user_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_is_admin() TO authenticated;
COMMENT ON FUNCTION public.current_user_is_admin() IS
  '156: true when the signed-in caller is in public.admin_users. The caller''s own boolean only; authenticated-execute.';

-- ── 4. ADDENDUM 3a: the old-build purchase safeguard ────────────────────────
CREATE FUNCTION public.client_shows_proof_disclosure()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_caps text;
BEGIN
  BEGIN
    v_caps := nullif(current_setting('request.headers', true), '')::json ->> 'x-snatchit-caps';
  EXCEPTION WHEN others THEN
    RETURN false;             -- unparseable request.headers asserts nothing
  END;
  RETURN coalesce('proof-disclosure-v1' = ANY (regexp_split_to_array(v_caps, '[[:space:],]+')), false);
END;
$$;
REVOKE ALL ON FUNCTION public.client_shows_proof_disclosure() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.client_shows_proof_disclosure() IS
  '156: true only when the request header x-snatchit-caps (PostgREST request.headers) carries the token '
  'proof-disclosure-v1 (space/comma separated); NULL, empty or unparseable -> false. Read by the bid and Buy Now '
  'hold guards; not client-executable.';

CREATE FUNCTION public.guard_bid_requires_disclosure()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.listings l WHERE l.id = NEW.listing_id AND l.proof_waived_at IS NOT NULL) THEN
    RETURN NEW;               -- no waiver: nothing to disclose
  END IF;
  -- The guards' trust test, read the 119 way (role GUC + request claims; never current_user alone).
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
  IF public.client_shows_proof_disclosure() THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'This listing needs the latest Snatch It app. Update the app or use app.snatchitapp.com.'
    USING ERRCODE = 'P0001', HINT = 'LISTING_UNAVAILABLE';
END;
$$;
REVOKE ALL ON FUNCTION public.guard_bid_requires_disclosure() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_bid_requires_disclosure() IS
  '156: BEFORE INSERT on public.bids. A bid on a listing with an owner proof waiver needs a client that can show the '
  'disclosure (x-snatchit-caps: proof-disclosure-v1); otherwise the update message with HINT LISTING_UNAVAILABLE. '
  'service_role / claims-less postgres pass.';

DROP TRIGGER IF EXISTS trg_bid_requires_disclosure ON public.bids;
CREATE TRIGGER trg_bid_requires_disclosure
  BEFORE INSERT ON public.bids
  FOR EACH ROW EXECUTE FUNCTION public.guard_bid_requires_disclosure();

CREATE FUNCTION public.guard_reservation_requires_disclosure()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
BEGIN
  IF NEW.reserved_by IS NULL OR NEW.reserved_by IS NOT DISTINCT FROM OLD.reserved_by
     OR NEW.proof_waived_at IS NULL THEN
    RETURN NEW;               -- not a new holder on a waived listing
  END IF;
  -- The guards' trust test, read the 119 way. reserve_buy_now is SECURITY DEFINER: current_user is the
  -- owner there, but the PostgREST role GUC and the request claims still describe the client.
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
  IF public.client_shows_proof_disclosure() THEN
    RETURN NEW;
  END IF;
  -- No HINT: builds 25/27 show "Reservation failed — <message>".
  RAISE EXCEPTION 'This listing needs the latest Snatch It app. Update the app or use app.snatchitapp.com.'
    USING ERRCODE = 'P0001';
END;
$$;
REVOKE ALL ON FUNCTION public.guard_reservation_requires_disclosure() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_reservation_requires_disclosure() IS
  '156: BEFORE UPDATE OF reserved_by on public.listings. A new Buy Now holder on a listing with an owner proof waiver '
  'needs a client that can show the disclosure (x-snatchit-caps: proof-disclosure-v1); otherwise the update message, '
  'no hint. Releasing a hold is never checked. service_role / claims-less postgres pass.';

DROP TRIGGER IF EXISTS trg_reservation_requires_disclosure ON public.listings;
CREATE TRIGGER trg_reservation_requires_disclosure
  BEFORE UPDATE OF reserved_by ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_reservation_requires_disclosure();

COMMIT;
