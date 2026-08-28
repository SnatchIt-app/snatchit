-- ============================================================================
-- 140_account_deletion_residue.sql
--
-- The account-deletion path had ZERO test coverage. Eighteen pgTAP files cover
-- custody, money, payouts, admin and webhooks; not one exercised
-- delete_account_cleanup or any part of deletion. That is why the defects below
-- survived: they are not subtle, they were simply never executed.
--
-- WHAT DISCRIMINATES AND WHAT DOES NOT. An earlier version of this header said
-- "every assertion here FAILS against the 0563 body". That was false, and the
-- claim is the kind a test file must not make loosely: measured by execution,
-- 0563 scores 8/25 and 20260828041500 scores 25/25, both measured by running
-- the file against each body. The eight that pass BOTH ways are 14, 15, 17,
-- 18, 19, 20, 22 and 24 -- they are REGRESSION GUARDS for behaviour 0563
-- already had, and they are NOT evidence for anything this migration repairs.
-- 18/19/20 exist because four one-statement mutants survived the first version
-- of this file; 22 and 24 are non-vacuity guards on 23 and 25. Marked inline.
--
-- Assertions are written against OBSERVABLE STATE -- "no row anywhere still
-- points at the deleted user" -- rather than against the function's text,
-- because the thing that matters is whether auth.admin.deleteUser can succeed.
--
-- THE PROPERTIES:
--   A. Every reference that would block the DELETE is cleared. 1-7.
--   B. The derived auction head matches the surviving bids, so deleting a top
--      bidder does not leave a phantom high bid nobody can outbid. 8-11.
--   C. No world-readable column still carries the deleted user's uuid. 12-14.
--   D. The function is idempotent, because the edge function may retry. 15-17.
--   E. The anonymization statements that 0563 already had still run. 18-21.
--
-- 23 AND 25 ARE THE TWO THAT MATTER MOST (22 and 24 are their non-vacuity
-- guards), and no earlier draft of this file had either. THEY COVER DIFFERENT
-- CLASSES AND NEITHER SUBSUMES THE OTHER -- an earlier revision of this header
-- claimed 23 caught both defects below, which is false: 23 reads pg_constraint,
-- so it sees FOREIGN KEYS ONLY, and proof_of_ownership_path has none. 23 computes the blocking set from pg_constraint --
-- the TRANSITIVE closure: every table reachable from auth.users by CASCADE,
-- then every NO ACTION/RESTRICT reference into any of those tables -- and
-- asserts that after cleanup none of them still names the user. Two real
-- defects shipped green past the hand-written enumeration it replaces:
--   * stripe_connect_archive.profile_id blocks the DELETE second-order, via
--     profiles.id CASCADE, and no direct-reference census could see it.
--     Caught by 23.
--   * listings.proof_of_ownership_path kept the uuid on a world-readable row
--     while the old assertion 18 "proved" no column did. It has no FK, so 23
--     is blind to it. Caught by 25.
-- An enumeration cannot fail for a column nobody remembered. These two can.
-- ============================================================================

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(25);

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
   cover_image_path, proof_of_ownership_path, auction_status)
VALUES
  ('aaaaaaaa-0000-0000-0000-00000000dead', tap.buyer(), 'Buyer Sells Too', 'Club E',
   'wynwood', current_date + 30, '19:00', 'GA', 1, 'mobile_transfer', 50, false,
   NULL, 24, now(), now() + interval '24 hours', 50,
   tap.buyer()::text || '/covers/1724800000000.jpg',
   tap.buyer()::text || '/proofs/1724800000000.jpg', 'active');

-- The buyer resolved a dispute, and reviewed a seller flag. Both are NO ACTION
-- FKs to auth.users that nothing has ever repointed.
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET dispute_resolved_by = tap.buyer() WHERE id = tap.transfer_b();

INSERT INTO public.seller_flags (seller_id, flag_type, reviewed_by)
VALUES (tap.seller(), 'duplicate_proof', tap.buyer());

-- The SECOND-ORDER blocker. profiles.id is ON DELETE CASCADE from auth.users
-- (000:14), so the auth delete cascades into profiles and THAT delete trips
-- this NO ACTION FK (044:22). Production holds 4 such rows. No census of
-- direct references to auth.users can see this, which is why it was missed.
INSERT INTO public.stripe_connect_archive (profile_id, stripe_connect_id, reason)
VALUES (tap.buyer(), 'acct_TEST_DELETED', 'testmode_cleanup');

-- The buyer is party to a payment and a transfer, so the anonymization
-- statements 0563 already had have something to act on (assertions 18-21).
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET buyer_id = tap.buyer() WHERE id = tap.transfer_b();

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

SELECT is((SELECT count(*)::int FROM public.listings
            WHERE proof_of_ownership_path LIKE tap.buyer()::text || '%'), 0,
  'proof_of_ownership_path no longer embeds the uuid either — it leaked the SAME id on the SAME public row, and the first version of this file did not check it');

SELECT is((SELECT seller_id FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-00000000dead'),
          '00000000-0000-0000-0000-000000000000'::uuid,
  'REGRESSION GUARD (green against 0563 too): the listing is still anonymized to the sentinel');

-- ── D. Idempotent, because the edge function may retry (15-17) ────────────
SELECT lives_ok($$ SELECT public.delete_account_cleanup(tap.buyer()) $$,
  'REGRESSION GUARD for a defect that only existed in an intermediate draft: a temp table with ON COMMIT DROP raised 42P07 here on the second call in ONE transaction. pgTAP wraps the file in BEGIN/ROLLBACK, so this really is the same transaction as line 94.');

SELECT is((SELECT current_bid FROM public.listings WHERE id = tap.listing_a()), 150,
  'a second run does not disturb the reconciled head (v_touched is empty, so no listing is touched)');

SELECT is((SELECT count(*)::int FROM public.listings WHERE seller_id = tap.buyer()), 0,
  'REGRESSION GUARD (green against 0563 too): a second run leaves the anonymization intact');

-- ── E. The statements 0563 already had still run (18-21) ─────────────────
-- Four one-statement mutants survived the first version of this file: both
-- payments anonymizations, both transfers anonymizations, and the step-1
-- auction cancellation. A test file that cannot see a statement deleted is not
-- protecting it.
SELECT is((SELECT count(*)::int FROM public.payments WHERE buyer_id = tap.buyer() OR seller_id = tap.buyer()), 0,
  'payments buyer_id/seller_id are repointed to the sentinel — deleting this statement must fail something');

SELECT is((SELECT count(*)::int FROM public.transfers WHERE buyer_id = tap.buyer() OR seller_id = tap.buyer()), 0,
  'transfers buyer_id/seller_id are repointed to the sentinel');

SELECT is((SELECT auction_status FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-00000000dead'), 'cancelled',
  'REGRESSION GUARD (green against 0563 too): the user''s own live auction is still cancelled by step 1');

SELECT is((SELECT count(*)::int FROM public.stripe_connect_archive WHERE profile_id = tap.buyer()), 0,
  'stripe_connect_archive.profile_id is repointed — it blocks the DELETE through profiles CASCADE, and no direct-reference census could see it');

-- ── 22. The standing check, computed from the catalog ────────────────────
-- This is the assertion that would have caught BOTH defects the hand-written
-- version missed. It asks pg_constraint for the transitive blocking set --
-- every table reachable from auth.users by CASCADE/SET NULL, then every
-- NO ACTION/RESTRICT reference INTO any of those tables -- builds the predicate
-- dynamically, and counts rows that still name the deleted user.
--
-- dispute_resolutions.actor_id is excluded BY NAME and only by name: it is
-- NOT NULL on an append-only table whose trigger raises on UPDATE and DELETE
-- (065:44), so nothing in the database can repoint it. The edge function
-- refuses deletion up front when such a row exists. When that decision is
-- made, delete the exclusion here and this assertion will hold it to it.
CREATE OR REPLACE FUNCTION pg_temp.residual_refs(p_user uuid)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE r record; n int; total int := 0;
BEGIN
  FOR r IN
    WITH RECURSIVE cascaded(rel) AS (
      SELECT 'auth.users'::regclass
      UNION
      SELECT c.conrelid FROM pg_constraint c JOIN cascaded x ON c.confrelid = x.rel
       WHERE c.contype = 'f' AND c.confdeltype IN ('c','n','d')
    )
    SELECT c.conrelid::regclass::text AS tbl, a.attname::text AS col
      FROM pg_constraint c
      JOIN unnest(c.conkey) WITH ORDINALITY k(attnum, ord) ON true
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
      JOIN cascaded x ON c.confrelid = x.rel
     WHERE c.contype = 'f' AND c.confdeltype IN ('a','r')
       AND NOT (c.conrelid = 'public.dispute_resolutions'::regclass AND a.attname = 'actor_id')
  LOOP
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', r.tbl, r.col)
       INTO n USING p_user;
    total := total + n;
  END LOOP;
  RETURN total;
END $fn$;

-- Non-vacuity: the query must actually find blockers to check, or a typo that
-- returns the empty set would make the assertion below pass for free.
SELECT cmp_ok((SELECT count(*)::int FROM (
  WITH RECURSIVE cascaded(rel) AS (
    SELECT 'auth.users'::regclass
    UNION
    SELECT c.conrelid FROM pg_constraint c JOIN cascaded x ON c.confrelid = x.rel
     WHERE c.contype = 'f' AND c.confdeltype IN ('c','n','d'))
  SELECT 1 FROM pg_constraint c JOIN cascaded x ON c.confrelid = x.rel
   WHERE c.contype = 'f' AND c.confdeltype IN ('a','r')) q), '>=', 13,
  'the catalog sweep finds at least the 13 blocking references known today — if this drops, the sweep broke, it did not get better');

SELECT is(pg_temp.residual_refs(tap.buyer()), 0,
  'NO table reachable from auth.users by CASCADE still holds a NO ACTION/RESTRICT reference to the deleted user (dispute_resolutions.actor_id excluded by name — see above)');


-- ── 24-25. The OTHER population sweep, over world-readable TEXT ──────────
-- 23 draws its columns from pg_constraint, so it sees FK blockers and nothing
-- else. listings.proof_of_ownership_path — the leak that shipped green past the
-- first revision — is a plain text column with NO foreign key, so 23 could
-- never have caught it, and an earlier version of this header wrongly said it
-- did. This is the sweep that covers that class: every text/varchar column on
-- every table carrying a permissive `USING (true)` SELECT policy, matched on
-- SUBSTRING rather than prefix. A Phase-2 migration that adds
-- `listings.receipt_image_path` written as `<uid>/receipts/<ts>.jpg` fails here
-- without anyone remembering to extend this file.
CREATE OR REPLACE FUNCTION pg_temp.public_text_residue(p_user uuid, OUT cols int, OUT hits int)
LANGUAGE plpgsql AS $fn$
DECLARE r record; n int;
BEGIN
  cols := 0; hits := 0;
  FOR r IN
    SELECT DISTINCT c.relname::text AS tbl, a.attname::text AS col
      FROM pg_policy p
      JOIN pg_class c       ON c.oid = p.polrelid
      JOIN pg_namespace ns  ON ns.oid = c.relnamespace
      JOIN pg_attribute a   ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
     WHERE ns.nspname = 'public'
       AND p.polpermissive
       AND p.polcmd IN ('r', '*')
       AND pg_get_expr(p.polqual, p.polrelid) = 'true'
       AND a.atttypid IN ('text'::regtype, 'varchar'::regtype)
  LOOP
    cols := cols + 1;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE %I LIKE %L',
                   r.tbl, r.col, '%' || p_user::text || '%')
       INTO n;
    hits := hits + n;
  END LOOP;
END $fn$;

SELECT cmp_ok((SELECT cols FROM pg_temp.public_text_residue(tap.buyer())), '>=', 10,
  'the world-readable text sweep actually inspects columns — if this drops to zero the next assertion passes for free');

SELECT is((SELECT hits FROM pg_temp.public_text_residue(tap.buyer())), 0,
  'NO text column on ANY world-readable table contains the deleted user''s uuid anywhere in its value — this is the class that caught proof_of_ownership_path, and 23 structurally cannot');

SELECT * FROM finish();
ROLLBACK;
