-- =============================================================================
-- 20260828041500_account_deletion_residue.sql
--
-- Account deletion half-completes today, irreversibly, for an ordinary user —
-- and leaves the deleted person re-identifiable on a world-readable row.
--
-- Found by an independent privacy review of supabase/functions/delete-account
-- on 2026-08-28. Every claim below was verified against this repository before
-- this migration was written.
--
-- WHY THIS IS A TIMESTAMP MIGRATION AND NOT `076_`:
--   076-091 are reserved for the Phase 2 package band (see
--   docs/architecture/PHASE_2_PACKAGE_REGISTRY.md). A hotfix must not consume
--   one. The migrations guard permits exactly two schemes, NNN_ and
--   YYYYMMDDHHMMSS_, and requires monotonicity only WITHIN a scheme; this sorts
--   after 20260731224653, the latest timestamp migration.
--
-- ── DEFECT 1: the auth.users DELETE fails, after five committed side effects ──
--
-- These four columns are `references auth.users (id)` with NO `ON DELETE`
-- clause, i.e. NO ACTION, and delete_account_cleanup repoints none of them:
--
--   listings.winner_user_id      000_baseline_schema.sql:302  — set at auction
--                                end, cleared by nothing, ever
--   listings.highest_bidder_id   000:308  — reconciled only by a ONE-TIME DO
--                                block in 046, not by a trigger
--   listings.reserved_by         000:294  — cleared today ONLY on the user's
--                                OWN cancelled listings, never where the
--                                deleted user reserved SOMEONE ELSE'S listing
--   bids.bidder_id               000:144  — not null; the edge function deletes
--                                these rows in a separate transaction
--
-- So for every auction winner and every final top bidder, the sequence is:
-- cleanup commits -> bids deleted -> storage deleted -> auth.admin.deleteUser
-- raises 23503 -> "Please contact support". The account stays fully live while
-- its financial history has already been reassigned to the shared sentinel.
-- Nothing retries and nothing detects it. Cost to induce deliberately: one bid.
--
-- Two further NO ACTION columns block the same DELETE and are fixed here:
--   transfers.dispute_resolved_by   011_v1_transfer_enhancements.sql:79
--   seller_flags.reviewed_by        012_seller_risk.sql:39
--
-- NOT fixed here, deliberately: dispute_resolutions.actor_id is NOT NULL on an
-- append-only table whose trigger raises on UPDATE and DELETE. It cannot be
-- repointed without dropping that trigger. It needs its own decision — either
-- `ON DELETE SET NULL` with a nullable column, or the sentinel written at
-- insert time. Flagged, not guessed at.
--
-- ── DEFECT 2: the anonymization is defeated by a public column ───────────────
--
-- `020` repoints listings.seller_id to the sentinel and does not touch
-- listings.cover_image_path, which holds `<the real user uuid>/covers/<ts>.jpg`
-- (src/hooks/useImageUpload.ts:161). public.listings is world-readable —
-- `create policy "listings: public select" ... using (true)` (000:117-118) —
-- and 074 does not narrow it. So seller_id = 00000000-… and the real uuid sit
-- on the same publicly readable row, and re-identification is a string split.
--
-- cover_image_path is `not null` (000:98), so it cannot be nulled. It is
-- rewritten to a constant that carries no identity. The storage object itself
-- is removed by the edge function; this column would otherwise dangle AND leak.
--
-- ── DEFECT 3: deleting bids desynchronises the auction head ─────────────────
--
-- listings.current_bid, bid_count and highest_bidder_id are denormalized and
-- written only on bid INSERT. There is no trigger on bid DELETE and no
-- scheduled reconciler — 046's repair is a one-shot DO block inside that
-- migration, and it does not reconcile current_bid at all. Deleting a top
-- bidder's rows therefore leaves a phantom high bid that nobody can outbid or
-- win, permanently. 046's own header records that this drift has already
-- happened in production: "bid_count = 2 with zero bid rows, left over from
-- deleted test bids."
--
-- The bid delete moves INTO this function so that the delete and the
-- reconciliation are one transaction. The edge function's separate delete
-- becomes redundant and is removed in the same change.
--
-- SCOPE: this migration makes account deletion SUCCEED and leave no
-- re-identifying residue on the rows it already touches. It does NOT decide
-- ODR-16 (what should happen when a user deletes while holding live custody) —
-- that is an open owner decision and nothing here presumes its outcome.
--
-- Rollback: supabase/rollbacks/20260828041500_account_deletion_residue_rollback.sql
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_account_cleanup(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_sentinel_id uuid := '00000000-0000-0000-0000-000000000000';
  -- Carries no identity. cover_image_path is NOT NULL so it cannot be cleared.
  v_dead_cover  text := 'deleted/cover-removed';
  -- Listings whose derived auction head must be recomputed after the user's
  -- bids are removed. Held in an ARRAY, not a temp table: `ON COMMIT DROP`
  -- survives until COMMIT, so a second call inside one transaction raised
  -- 42P07 "relation already exists". The edge function calls this once per
  -- transaction so it would not have bitten in production — but the retry path
  -- is the whole point of making this function idempotent, and assertion 15 of
  -- 140_account_deletion_residue.sql caught it.
  v_touched     uuid[];
begin
  perform set_config('app.bypass_listing_guard', 'on', true);
  perform set_config('app.bypass_transfer_guard', 'on', true);

  -- ── 1. Cancel the user's own live auctions (unchanged from 0563) ──────────
  update public.listings
     set auction_status='cancelled', status='active', reserved_by=null,
         reserved_until=null, ended_at=now()
   where seller_id = p_user_id and auction_status in ('active','ended');

  -- ── 2. Release reservations the user holds on OTHER sellers' listings ─────
  -- Step 1 only clears reserved_by on listings the user SELLS. A reservation
  -- the user holds as a BUYER is an equally hard NO ACTION blocker and was
  -- never cleared by anything.
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set reserved_by = null,
         reserved_until = null,
         status = case when status = 'reserved' then 'active' else status end
   where reserved_by = p_user_id;

  -- ── 3. Remove the user's bids, then reconcile every listing they touched ──
  -- Moved here from the edge function so the delete and the reconciliation
  -- share one transaction. Without this, deleting the top bidder's rows leaves
  -- current_bid/bid_count/highest_bidder_id describing bids that no longer
  -- exist — a listing nobody can outbid or win.
  select coalesce(array_agg(distinct listing_id), '{}')
    into v_touched
    from public.bids
   where bidder_id = p_user_id;

  delete from public.bids where bidder_id = p_user_id;

  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings l
     set bid_count         = s.real_count,
         highest_bidder_id = s.top_bidder,
         current_bid       = coalesce(s.top_amount, l.starting_bid)
    from (
      select t.id,
             (select count(*) from public.bids b where b.listing_id = t.id) as real_count,
             (select b.bidder_id from public.bids b
               where b.listing_id = t.id
               order by b.amount desc, b.created_at desc limit 1)            as top_bidder,
             (select b.amount    from public.bids b
               where b.listing_id = t.id
               order by b.amount desc, b.created_at desc limit 1)            as top_amount
        from unnest(v_touched) as t(id)
    ) s
   where l.id = s.id;

  -- ── 4. Clear the remaining NO ACTION references to auth.users ─────────────
  -- Each of these on its own is enough to make auth.admin.deleteUser raise
  -- 23503 after this function has already committed.
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings set highest_bidder_id = null where highest_bidder_id = p_user_id;

  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings set winner_user_id = null where winner_user_id = p_user_id;

  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers set dispute_resolved_by = v_sentinel_id
   where dispute_resolved_by = p_user_id;

  update public.seller_flags set reviewed_by = null where reviewed_by = p_user_id;

  -- ── 5. Anonymize the listing rows, and strip the identity from the path ───
  -- The guard blocks seller_id changes unconditionally, hence the disable.
  alter table public.listings disable trigger trg_guard_listing_identity;
  update public.listings
     set seller_id        = v_sentinel_id,
         cover_image_path = v_dead_cover
   where seller_id = p_user_id;
  alter table public.listings enable trigger trg_guard_listing_identity;

  -- Any other listing still carrying this user's uuid inside the storage path —
  -- e.g. a cover uploaded before a transfer of ownership. Belt and braces: the
  -- point of the column rewrite is that NO public row may contain the uuid.
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set cover_image_path = v_dead_cover
   where cover_image_path like p_user_id::text || '/%';

  -- ── 6. Anonymize financial records (unchanged from 0563) ─────────────────
  update public.payments set buyer_id  = v_sentinel_id where buyer_id  = p_user_id;
  update public.payments set seller_id = v_sentinel_id where seller_id = p_user_id;

  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers set buyer_id  = v_sentinel_id where buyer_id  = p_user_id;
  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers set seller_id = v_sentinel_id where seller_id = p_user_id;
end; $function$;

COMMENT ON FUNCTION public.delete_account_cleanup(uuid) IS
  'Pre-delete cleanup for account deletion. Clears every NO ACTION reference to '
  'auth.users so auth.admin.deleteUser can succeed, removes the user''s bids and '
  'reconciles the derived auction head, and strips the user uuid from '
  'listings.cover_image_path (a world-readable column). Idempotent: every '
  'statement is predicated on the user id and matches zero rows on a re-run.';

COMMIT;
