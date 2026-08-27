-- 072_fix_listing_insert_guards.sql
-- =============================================================================
-- SECURITY HOTFIX (H-1, HIGH). Pre-Phase-2.
--
-- THE DEFECT
-- public.listings had column custody on UPDATE and NONE on INSERT.
--
--   guard_listing_state    BEFORE UPDATE -> guard_listing_state_columns()
--   trg_guard_listing_identity BEFORE UPDATE -> guard_listing_identity_columns()
--
-- (verified from the production catalog, pg_trigger/pg_get_triggerdef, 2026-08-27;
-- trg_guard_proof_status, added by 071, was the only INSERT-firing trigger on the
-- table.) Meanwhile:
--
--   * `authenticated` holds table-wide INSERT on public.listings
--     (information_schema.role_table_grants).
--   * pg_attribute.attacl is NULL for all 36 columns — there is not one
--     column-level ACL on this table.
--   * The INSERT policy "listings: auth insert" has WITH CHECK
--       seller_id = auth.uid()
--       AND EXISTS (profiles p WHERE p.id = auth.uid()
--                     AND p.stripe_onboarding_complete = true)
--       AND phone_verified()
--     — it constrains WHO may create a listing, and nothing about WHAT is in it.
--   * listings_status_check / listings_auction_status_check permit 'sold' and
--     'ended', so the CHECK constraints do not stand in either.
--
-- So every column the UPDATE guards protect could simply be supplied AT
-- CREATION by an ordinary onboarded, phone-verified seller.
--
-- IMPACT (no evidence of exploitation; production listings count 111 unchanged,
-- and no probe was run against production for this migration)
--   * supabase/functions/create-payment-intent/index.ts, auction branch:
--       if (listing.winner_user_id !== buyerId) -> 'You are not the auction winner'
--       amount = listing.winning_bid_amount ?? listing.current_bid
--     A seller could CREATE a listing naming an arbitrary victim as
--     winner_user_id with an arbitrary winning_bid_amount, and that victim is
--     served a real Stripe PaymentIntent for a listing they never bid on.
--     app/(tabs)/bids.tsx renders auction_status='ended' AND winner_user_id = me
--     as "WON", which is the prompt that leads them to it.
--   * The forgery is SILENT: trg_notify_auction_won_inbox is
--     AFTER UPDATE OF winner_user_id, so a row that arrives already carrying a
--     winner never fires it. Nothing is logged and nobody is notified.
--   * complete_auction_payment() reads status/auction_status/winner_user_id from
--     the row and requires auction_status='ended' — a state the seller could
--     stamp at INSERT.
--   * bid_count/highest_bidder_id are the gates 046 closed on UPDATE for exactly
--     this reason (edit-after-bids, delete-after-bids, seller dashboard); they
--     were forgeable at INSERT the whole time.
--   * current_bid on a zero-bid listing is a fabricated demand signal on every
--     listing card.
--
-- WHY THIS SHAPE
-- 1. A NEW function and a NEW trigger, not an extension of
--    guard_listing_state_columns(). That body dereferences OLD on every branch;
--    on INSERT OLD is unassigned and PL/pgSQL raises. Widening the existing
--    trigger to BEFORE INSERT OR UPDATE would break every listing creation.
--    This migration is purely additive and does not touch either existing guard.
--
-- 2. FAIL-CLOSED, and in that order: the ALLOW condition is computed into a
--    boolean initialised false, and the column check runs only when it is still
--    false. Anything unmatched, NULL, or unparseable falls through to the
--    column check and is rejected. This is 071's shape, deliberately.
--
-- 3. SECURITY INVOKER, not DEFINER. The body touches no table, so it needs no
--    privileges. Under DEFINER current_user would be the OWNER and could not
--    identify the caller at all; under INVOKER it is the caller's real SQL role,
--    which PostgreSQL enforces through role membership — `authenticator` may SET
--    ROLE only to anon/authenticated/service_role, never postgres. EXECUTE is
--    not consulted when a trigger fires, which is why the two sibling guards on
--    this table are already prosecdef=false with EXECUTE revoked (067) and still
--    work for `authenticated`.
--
-- 4. The SQL ROLE decides; a CLAIM may only contradict, never grant. A forged
--    {"role":"service_role"} claim held under the authenticated SQL role is
--    denied. Same reasoning as 071 §3; not reinvented here.
--
-- 5. request_is_service_role() (0550) is deliberately NOT reused. It reads the
--    legacy singular request.jwt.claim.role GUC first, grants on the claim alone
--    without checking the SQL role, and returns TRUE when the claims GUC is NULL.
--    Each of those would reopen this hole. It is separately under audit
--    (MONEY-1).
--
-- 6. app.bypass_listing_guard is deliberately NOT honoured on INSERT. This is
--    the one place this migration departs from the sibling guard, and it is
--    intentional:
--      - Zero functions in this database INSERT into public.listings. Verified
--        against the production catalog: of the eleven public functions that
--        write the table (auto_finalize_expired_auctions, cancel_listing,
--        cleanup_expired_reservations, complete_auction_payment,
--        delete_account_cleanup, finalize_auction, mark_listing_sold,
--        release_reservation, reserve_buy_now, sync_listing_current_bid,
--        validate_and_apply_bid) every one is UPDATE-only. There is no server
--        INSERT path to preserve.
--      - The GUC is a plain transaction-local setting with NO statement-level
--        reset for listings (transfers got that in 056c; listings never did —
--        supabase/tests/README.md harness rule 2 records it). It is armed by
--        validate_and_apply_bid(), reserve_buy_now(), complete_auction_payment()
--        and friends and stays armed for the rest of the transaction. Honouring
--        it here would mean "a transaction that has placed a bid may then forge
--        a listing" — a real widening, for no consumer.
--    A future RPC that must INSERT a listing should be SECURITY DEFINER owned by
--    a service role (ALLOW 1), or run as the operator (ALLOW 2). Do not add the
--    bypass GUC to this guard.
--
-- 7. search_path = public, pg_temp matches the 0660 hardening pattern and both
--    sibling guards on this table.
--
-- WHAT IS AND IS NOT FROZEN AT INSERT (the deliberate line)
--   Frozen to its fresh-listing value: winner_user_id, winning_bid_amount,
--   highest_bidder_id, reserved_by, reserved_until, sold_at, ended_at (all NULL);
--   bid_count (0); status and auction_status ('active'); created_at (now()).
--   Constrained, not banned: current_bid. It is NOT NULL with no default and the
--   real client sends it — src/screens/CreateListingScreen.tsx line 482 sets
--   current_bid = startingBidNum. Banning it would break every listing creation.
--   The correct boundary is current_bid = starting_bid: a new listing opens at
--   its own asking price and nowhere else.
--   NOT frozen, deliberately: `id` (a client-chosen uuid confers no privilege —
--   the primary key still holds and RLS still binds seller_id — and pinning it
--   would forbid a legitimate idempotency idiom); `updated_at` (set_updated_at()
--   overwrites it on the first UPDATE); `starts_at` (referenced by no migration
--   after the baseline and by no RPC); the seller's own descriptive and price
--   fields (event_*, venue, neighborhood, ticket_*, quantity, transfer_method,
--   restrictions, starting_bid, buy_now_*, duration_hours, ends_at,
--   cover_image_path, proof_of_ownership_path, seller_commitment_accepted_at,
--   category) which are his to set by definition; `seller_id`, already pinned to
--   auth.uid() by the INSERT policy; and `proof_status`, which is 071's.
--
-- KNOWN ADJACENT GAP, recorded not fixed (out of scope for H-1, which is the
-- INSERT side): guard_listing_state_columns() does not freeze starting_bid or
-- buy_now_price on UPDATE, so a seller can still re-price a listing after bids
-- have landed. That is an UPDATE-side finding and needs its own migration.
--
-- SCOPE: access control only. No money semantics, no amounts, no fees, no payout
-- logic, no RLS policy, no existing function or trigger altered.
--
-- Tests: supabase/tests/045_listing_insert_authority.sql (20 assertions).
-- Rollback: supabase/rollbacks/072_fix_listing_insert_guards_rollback.sql
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.guard_listing_insert_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
  v_allow      boolean := false;
  v_bad        text;
BEGIN
  v_role   := current_user::text;
  v_claims := nullif(current_setting('request.jwt.claims', true), '');

  -- set_config(name, '', true) CREATES the GUC, so current_setting(name, true)
  -- returns '' rather than NULL; an IS NULL test on the raw GUC would be wrong.
  IF v_claims IS NOT NULL THEN
    BEGIN
      v_claim_role := v_claims::jsonb ->> 'role';
    EXCEPTION WHEN others THEN
      -- Unparseable claims assert nothing; both ALLOW paths below then fail.
      v_claim_role := NULL;
    END;
  END IF;

  -- ALLOW 1 — trusted server role. The SQL role must actually BE service_role;
  -- a claim can only contradict it.
  IF v_role = 'service_role'
     AND coalesce(v_claim_role, 'service_role') = 'service_role' THEN
    v_allow := true;

  -- ALLOW 2 — direct admin connection with no request context: migrations,
  -- pg_cron, the Supabase SQL editor. A PostgREST request always carries claims,
  -- so this cannot be reached from a client.
  ELSIF v_role = 'postgres' AND v_claims IS NULL THEN
    v_allow := true;
  END IF;

  IF v_allow THEN
    RETURN NEW;
  END IF;

  -- Untrusted caller. Every server-controlled column must arrive at its
  -- fresh-listing value. NULL-safe throughout: IS DISTINCT FROM / IS NOT NULL
  -- never yield UNKNOWN, so there is no three-valued fall-through.
  --
  -- created_at: the column DEFAULT now() is applied BEFORE a BEFORE-INSERT
  -- trigger fires, and now() is transaction_timestamp() — stable for the whole
  -- transaction — so a row that took the default compares exactly equal here,
  -- while any client-supplied timestamp (or an explicit NULL) does not.
  v_bad := CASE
    WHEN NEW.winner_user_id     IS NOT NULL                       THEN 'winner_user_id'
    WHEN NEW.winning_bid_amount IS NOT NULL                       THEN 'winning_bid_amount'
    WHEN NEW.highest_bidder_id  IS NOT NULL                       THEN 'highest_bidder_id'
    WHEN NEW.reserved_by        IS NOT NULL                       THEN 'reserved_by'
    WHEN NEW.reserved_until     IS NOT NULL                       THEN 'reserved_until'
    WHEN NEW.sold_at            IS NOT NULL                       THEN 'sold_at'
    WHEN NEW.ended_at           IS NOT NULL                       THEN 'ended_at'
    WHEN NEW.bid_count          IS DISTINCT FROM 0                THEN 'bid_count'
    WHEN NEW.status             IS DISTINCT FROM 'active'         THEN 'status'
    WHEN NEW.auction_status     IS DISTINCT FROM 'active'         THEN 'auction_status'
    WHEN NEW.current_bid        IS DISTINCT FROM NEW.starting_bid THEN 'current_bid'
    WHEN NEW.created_at         IS DISTINCT FROM now()            THEN 'created_at'
    ELSE NULL
  END;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot set server-controlled listing columns on insert.'
      USING DETAIL = format(
              'listings.%s is written only by the auction RPCs, never by the creator.',
              v_bad),
            HINT = 'Create the listing without it; the server maintains it.';
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.guard_listing_insert_columns() IS
  'Fail-closed INSERT-side custody for public.listings (H-1). Requires every '
  'server-controlled column to arrive at its fresh-listing value (auction/'
  'settlement columns NULL, bid_count 0, status and auction_status active, '
  'current_bid = starting_bid, created_at = now()) unless the caller is the '
  'service_role SQL role (claims may contradict, never grant) or a claims-less '
  'postgres session. Companion to guard_listing_state_columns(), which covers '
  'UPDATE only. Deliberately does NOT honour app.bypass_listing_guard: no '
  'function in this database INSERTs into listings, and that GUC stays armed for '
  'the rest of any transaction that ran a bid or reservation RPC.';

-- Additive. The two existing BEFORE UPDATE guards are untouched; this fires
-- alongside trg_guard_proof_status (071) on the INSERT path only.
DROP TRIGGER IF EXISTS trg_guard_listing_insert ON public.listings;
CREATE TRIGGER trg_guard_listing_insert
  BEFORE INSERT ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_listing_insert_columns();

-- Idempotent restatement of the 067 posture. EXECUTE is irrelevant when a
-- trigger fires; this keeps the function self-contained if it is ever replayed
-- onto a database that predates 067.
REVOKE EXECUTE ON FUNCTION public.guard_listing_insert_columns() FROM anon, authenticated, PUBLIC;

COMMIT;
