-- Rollback for 072.
--
-- WARNING: THIS RESTORES A KNOWN HIGH-SEVERITY VULNERABILITY (H-1).
--
-- What it honestly restores, and why it can:
-- 072 is PURELY ADDITIVE. It created one new function
-- (public.guard_listing_insert_columns) and one new trigger
-- (trg_guard_listing_insert on public.listings). It altered no existing
-- function, no existing trigger, no policy, no grant and no column. There is
-- therefore no prior definition to transcribe — before 072 neither object
-- existed — and dropping both returns public.listings to exactly the state the
-- production catalog held on 2026-08-27: two BEFORE UPDATE column guards
-- (guard_listing_state / trg_guard_listing_identity), 071's
-- trg_guard_proof_status BEFORE INSERT OR UPDATE, trg_listings_updated_at, and
-- trg_notify_auction_won_inbox. This rollback is exact, not approximate.
--
-- What it reopens, stated plainly:
-- With trg_guard_listing_insert gone, public.listings has column custody on
-- UPDATE and NONE on INSERT. `authenticated` holds table-wide INSERT, there is
-- not one column-level ACL on the table, and the INSERT policy
-- "listings: auth insert" constrains only WHO may create a listing
-- (seller_id = auth.uid(), stripe_onboarding_complete, phone_verified()) and
-- nothing about what is in it. Any onboarded, phone-verified seller can again
-- CREATE a listing that already carries:
--   * winner_user_id naming an arbitrary victim, with an arbitrary
--     winning_bid_amount — which supabase/functions/create-payment-intent
--     accepts as the auction result and prices a real Stripe PaymentIntent from,
--     while app/(tabs)/bids.tsx tells that victim they WON. The forgery is
--     silent: trg_notify_auction_won_inbox is AFTER UPDATE OF winner_user_id and
--     never fires for a row that arrives already carrying a winner.
--   * auction_status='ended' / status='sold', the states complete_auction_payment()
--     and the settlement path key on.
--   * bid_count, highest_bidder_id, current_bid — fabricated demand, and the
--     gates 046 closed on UPDATE for exactly this reason.
--   * reserved_by, reserved_until, sold_at, ended_at, and a backdated created_at.
--
-- Only run this if 072 itself is causing a production regression — the most
-- likely such regression is a legitimate listing creation being refused, which
-- would surface as 'Cannot set server-controlled listing columns on insert.'
-- with a DETAIL naming the column. In that case a corrected forward migration
-- that adjusts that ONE column's rule is almost always the better move: 072 adds
-- an isolated trigger, so a narrow CREATE OR REPLACE of
-- guard_listing_insert_columns() is available without dropping the protection.
-- Treat a full rollback as an incident; the window it opens is H-1 itself.

BEGIN;

DROP TRIGGER IF EXISTS trg_guard_listing_insert ON public.listings;

-- Safe to drop: the function is referenced by nothing else. It was created by
-- 072, is called only from the trigger dropped above, and EXECUTE was revoked
-- from anon/authenticated/PUBLIC. No CASCADE is used, so if anything unexpected
-- does depend on it this statement fails loudly rather than removing it too.
DROP FUNCTION IF EXISTS public.guard_listing_insert_columns();

COMMIT;
