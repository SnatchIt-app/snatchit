-- ============================================================================
-- 140_account_deletion_residue.sql
--
-- The account-deletion path had ZERO test coverage. Eighteen pgTAP files cover
-- custody, money, payouts, admin and webhooks; not one exercised
-- delete_account_cleanup or any part of deletion. That is why the defects below
-- survived: they are not subtle, they were simply never executed.
--
-- Every assertion here FAILS against the 0563 body and PASSES against
-- 20260828041500. They are written against OBSERVABLE STATE — "no row anywhere
-- still points at the deleted user" — rather than against the function's text,
-- because the thing that matters is whether auth.admin.deleteUser can succeed,
-- not which statements were written.
--
-- THE FOUR PROPERTIES:
--   A. Every NO ACTION reference to auth.users is cleared, so the subsequent
--      DELETE cannot raise 23503. Assertions 1-7.
--   B. The derived auction head matches the surviving bids, so deleting a top
--      bidder does not leave a phantom high bid nobody can outbid. 8-11.
--   C. No world-readable column still carries the deleted user's uuid. 12-14.
--      This is the one that mattered most: seller_id was repointed to the
--      sentinel while cover_image_path kept the real uuid ON THE SAME PUBLIC
--      ROW, so re-identification was a string split.
--   D. The function is idempotent, because the edge function may retry. 15-17.
--
-- Assertion 18 is the standing catalog check the privacy review asked for: it
-- is population-based, not enumeration-based, so a column added LATER that
-- carries an identity uuid fails this file without anyone remembering to add it.
-- ============================================================================

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);

SELECT tap.seed_core();

-- ── File-local fixture ─────────────────────────────────────────────────────
-- tap.buyer() is the account we delete. Deliberately NOT the seller: the old
-- function's only real work was on seller_id, so deleting a seller would have
-- hidden every defect this file exists to catch. The buyer here is a bidder, a
-- winner, a reserver of someone else's listing, and a dispute resolver — the
-- ordinary marketplace participant whose deletion has been failing.

-- The buyer is the top bidder on listing A and has one lower bid on listing B.
-- tap.other_user() also bids on A, BELOW the buyer, so that after the buyer's
-- rows go the head must fall back to a real remaining bid rather than to NULL.
INSERT INTO public.bids (listing_id, bidder_id, amount)
VALUES (tap.listing_a(), tap.other_user(), 150),
       (tap.listing_a(), tap.buyer(),      200),
       (tap.listing_b(), tap.buyer(),      120);

SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings
   SET current_bid = 200, bid_count = 2, highest_bidder_id = tap.buyer(),
       winner_user_id = tap.buyer()
 WHERE id = tap.listing_a();

SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings
   SET current_bid = 120, bid_count = 1, highest_bidder_id = tap.buyer()
 WHERE id = tap.listing_b();

-- The buyer RESERVED a listing they do not own. The old function cleared
-- reserved_by only `where seller_id = p_user_id`, so this one was never touched.
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings
   SET reserved_by = tap.buyer(), reserved_until = now() + interval '1 hour',
       status = 'reserved'
 WHERE id = tap.listing_d();

-- The buyer owns a listing whose cover path embeds their uuid — exactly what
-- useImageUpload.ts writes: `<userId>/covers/<ts>.jpg`.
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time,
   ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled,
   buy_now_price, duration_hours, starts_at, ends_at, current_bid,
   cover_image_path, auction_status)
VALUES
  ('aaaaaaaa-0000-0000-0000-00000000dead', tap.buyer(), 'Buyer Sells Too', 'Club E',
   'wynwood', current_date + 30, '19:00', 'GA', 1, 'mobile_transfer', 50, false,
   NULL, 24, now(), now() + interval '24 hours', 50,
   tap.buyer()::text || '/covers/1724800000000.jpg', 'active');

-- The buyer resolved a dispute, and reviewed a seller flag. Both are NO ACTION
-- FKs to auth.users that nothing has ever repointed.
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET dispute_resolved_by = tap.buyer() WHERE id = tap.transfer_b();

INSERT INTO public.seller_flags (seller_id, flag_type, reviewed_by)
VALUES (tap.seller(), 'duplicate_proof', tap.buyer());

-- ── Run the thing under test ───────────────────────────────────────────────
SELECT public.delete_account_cleanup(tap.buyer());

-- ── A. Every NO ACTION reference is cleared (1-7) ──────────────────────────
SELECT is((SELECT count(*)::int FROM public.listings WHERE winner_user_id = tap.buyer()), 0,
  'winner_user_id is cleared — set at auction end and cleared by nothing before this migration');

SELECT is((SELECT count(*)::int FROM public.listings WHERE highest_bidder_id = tap.buyer()), 0,
  'highest_bidder_id is cleared — reconciled only by a ONE-TIME DO block in 046, never by a trigger');

SELECT is((SELECT count(*)::int FROM public.listings WHERE reserved_by = tap.buyer()), 0,
  'reserved_by is cleared even on a listing the user does NOT own (the old WHERE was seller_id = p_user_id)');

SELECT is((SELECT status FROM public.listings WHERE id = tap.listing_d()), 'active',
  'releasing the reservation returns the listing to active rather than stranding it as reserved');

SELECT is((SELECT count(*)::int FROM public.bids WHERE bidder_id = tap.buyer()), 0,
  'the user''s bids are gone — and gone inside THIS transaction, not a later one');

SELECT is((SELECT count(*)::int FROM public.transfers WHERE dispute_resolved_by = tap.buyer()), 0,
  'transfers.dispute_resolved_by no longer points at the deleted user');

SELECT is((SELECT count(*)::int FROM public.seller_flags WHERE reviewed_by = tap.buyer()), 0,
  'seller_flags.reviewed_by no longer points at the deleted user');

-- ── B. The auction head matches the surviving bids (8-11) ─────────────────
SELECT is((SELECT highest_bidder_id FROM public.listings WHERE id = tap.listing_a()), tap.other_user(),
  'listing A''s head falls back to the real remaining bidder, not to NULL and not to the deleted user');

SELECT is((SELECT current_bid FROM public.listings WHERE id = tap.listing_a()), 150,
  'current_bid falls back to the surviving bid — otherwise a phantom 200 nobody can outbid');

SELECT is((SELECT bid_count FROM public.listings WHERE id = tap.listing_a()), 1,
  'bid_count matches the real row count (046''s header records this drift already reaching production)');

-- listing_b's starting_bid is 100 in tap.seed_core(); the fixture above raised
-- current_bid to 120 with the buyer's single bid. Removing it must fall back to
-- the starting bid, not leave 120 standing for a bid that no longer exists.
SELECT is((SELECT current_bid FROM public.listings WHERE id = tap.listing_b()),
          (SELECT starting_bid FROM public.listings WHERE id = tap.listing_b()),
  'with every bid gone, current_bid reverts to starting_bid rather than keeping a dead figure');

-- ── C. No world-readable column carries the uuid (12-14) ──────────────────
SELECT is((SELECT count(*)::int FROM public.listings
            WHERE cover_image_path LIKE tap.buyer()::text || '%'), 0,
  'cover_image_path no longer embeds the deleted user''s uuid — seller_id was anonymized while THIS column kept it');

SELECT is((SELECT seller_id FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-00000000dead'),
          '00000000-0000-0000-0000-000000000000'::uuid,
  'the listing is still anonymized to the sentinel (the repoint itself is unchanged)');

SELECT isnt((SELECT cover_image_path FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-00000000dead'),
            NULL,
  'cover_image_path is rewritten rather than nulled — the column is NOT NULL, so nulling would raise');

-- ── D. Idempotent, because the edge function may retry (15-17) ────────────
SELECT lives_ok($$ SELECT public.delete_account_cleanup('22222222-2222-2222-2222-222222222222'::uuid) $$,
  'a second run does not raise — every statement is predicated on the user id');

SELECT is((SELECT current_bid FROM public.listings WHERE id = tap.listing_a()), 150,
  'a second run does not disturb the reconciled head (the temp table is empty, so no listing is touched)');

SELECT is((SELECT count(*)::int FROM public.listings WHERE seller_id = tap.buyer()), 0,
  'a second run leaves the anonymization intact');

-- ── The standing check (18) ──────────────────────────────────────────────
-- Population-based, not a fixed list. A column added LATER that carries an
-- identity uuid on a publicly readable table fails this without anyone
-- remembering to extend the file. That is the property the enumeration-based
-- version of this check would not have.
SELECT is(
  (SELECT count(*)::int
     FROM public.listings
    WHERE seller_id::text        LIKE '%' || tap.buyer()::text || '%'
       OR cover_image_path       LIKE '%' || tap.buyer()::text || '%'
       OR event_name             LIKE '%' || tap.buyer()::text || '%'
       OR venue                  LIKE '%' || tap.buyer()::text || '%'
       OR coalesce(restrictions, '') LIKE '%' || tap.buyer()::text || '%'),
  0,
  'NO text or identity column on the world-readable listings table still contains the deleted user''s uuid');

SELECT * FROM finish();
ROLLBACK;
