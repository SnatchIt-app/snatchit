-- =============================================================================
-- Migration 003: Payment and transfer integrity
-- =============================================================================
-- PURPOSE: Prevent the double-sale / duplicate-transfer incident from recurring.
--
-- This migration is purely additive or replaces existing RPCs with safer logic.
-- It does NOT redesign the data model or touch unrelated features.
--
-- ROOT CAUSES FIXED:
--   1. mark_listing_sold did not set auction_status='sold', allowing
--      complete_auction_payment to succeed after a buy_now sale.
--   2. complete_auction_payment did not check listings.status, allowing it to
--      succeed even when the listing was already sold via buy_now.
--   3. No DB-level guard against two transfers for the same listing/payment.
--   4. No DB-level guard against two succeeded payments for the same listing.
--
-- REQUIRED PRE-CHECKS (run in SQL editor BEFORE applying this migration):
-- =============================================================================
--
--   -- 1. Verify no listing has two succeeded payments (must return 0 rows):
--   SELECT listing_id, count(*)
--     FROM public.payments
--    WHERE status = 'succeeded'
--    GROUP BY listing_id
--   HAVING count(*) > 1;
--
--   -- 2. Verify no listing has two transfer rows (must return 0 rows):
--   SELECT listing_id, count(*)
--     FROM public.transfers
--    GROUP BY listing_id
--   HAVING count(*) > 1;
--
--   -- 3. Verify no payment_id appears in transfers twice (must return 0 rows):
--   SELECT payment_id, count(*)
--     FROM public.transfers
--    GROUP BY payment_id
--   HAVING count(*) > 1;
--
-- If any query returns rows, clean up the duplicate data FIRST, then apply.
-- =============================================================================


-- ===========================================================================
-- 1. Partial unique index on payments: one succeeded payment per listing
-- ===========================================================================
-- Enforces the invariant that a listing can have at most one successful charge.
-- Partial index covers only status='succeeded', so pending/failed payments
-- are unaffected and multiple retries before success remain possible.
-- The second `update payments set status='succeeded'` for the same listing
-- will be rejected by the DB with a unique-constraint violation.
-- ===========================================================================
create unique index if not exists idx_payments_one_success_per_listing
  on public.payments (listing_id)
  where status = 'succeeded';


-- ===========================================================================
-- 2. Unique constraint on transfers.payment_id
-- ===========================================================================
-- One payment → one transfer row, always.
-- Protects against webhook replay creating a second transfer for the same
-- Stripe PaymentIntent. The existing transferErr handler in the webhook
-- already logs and continues, so this is a silent, safe guard.
-- ===========================================================================
alter table public.transfers
  add constraint if not exists transfers_payment_id_key unique (payment_id);
-- NOTE: PostgreSQL <15 does not support ADD CONSTRAINT IF NOT EXISTS.
-- If your Postgres version is < 15, use:
--   alter table public.transfers add constraint transfers_payment_id_key unique (payment_id);
-- and run only if the constraint does not already exist.


-- ===========================================================================
-- 3. Unique constraint on transfers.listing_id
-- ===========================================================================
-- One listing → one transfer row, always.
-- A listing can only be sold once. Two transfers for the same listing can only
-- exist as the result of the buy_now + auction double-sale bug. This constraint
-- ensures the DB rejects any second insert regardless of how it is triggered.
-- ===========================================================================
alter table public.transfers
  add constraint if not exists transfers_listing_id_key unique (listing_id);


-- ===========================================================================
-- 4. mark_listing_sold — set auction_status = 'sold' on buy_now sale
-- ===========================================================================
-- FIX: The final UPDATE now also sets auction_status = 'sold'.
-- Effect: after a successful buy_now sale, complete_auction_payment reads
-- auction_status = 'sold' and hits its existing idempotency guard (return early).
-- This closes the primary cross-mode double-sale window.
--
-- All other logic is identical to the current production function.
-- ===========================================================================
create or replace function public.mark_listing_sold(
  p_listing_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id      uuid;
  v_status         text;
  v_reserved_by    uuid;
  v_reserved_until timestamptz;
begin
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  select status, reserved_by, reserved_until
    into v_status, v_reserved_by, v_reserved_until
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    raise exception 'Listing not found.';
  end if;

  -- Already sold — idempotent exit. Covers both buy_now and auction replays.
  if v_status = 'sold' then
    return;
  end if;

  if v_status <> 'reserved' or v_reserved_by is distinct from v_caller_id then
    raise exception 'This listing is not reserved by you.';
  end if;

  if v_reserved_until <= now() then
    perform set_config('app.bypass_listing_guard', 'on', true);
    update public.listings
       set status         = 'active',
           reserved_by    = null,
           reserved_until = null
     where id = p_listing_id;
    raise exception 'Your reservation has expired. Please try again.';
  end if;

  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set status         = 'sold',
         -- FIX: also mark auction_status sold so complete_auction_payment
         -- cannot succeed after this buy_now sale.
         auction_status = 'sold',
         sold_at        = now(),
         reserved_by    = null,
         reserved_until = null
   where id = p_listing_id;
end;
$$;


-- ===========================================================================
-- 5. complete_auction_payment — guard against post-buy_now double-sale
-- ===========================================================================
-- FIX: Read listings.status in addition to auction_status.
-- If listings.status is already 'sold' (set by mark_listing_sold), exit early.
-- This is defense-in-depth: even if Fix 4 above hasn't taken effect inside
-- a concurrent transaction (e.g., mark_listing_sold and complete_auction_payment
-- race), the FOR UPDATE lock ensures one waits for the other, then sees
-- status='sold' and returns without doing any work.
--
-- All other logic is identical to the current production function.
-- ===========================================================================
create or replace function public.complete_auction_payment(
  p_listing_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id      uuid;
  v_status         text;   -- FIX: added
  v_auction_status text;
  v_winner_id      uuid;
begin
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  -- FIX: also select listings.status so we can detect a prior buy_now sale.
  select status, auction_status, winner_user_id
    into v_status, v_auction_status, v_winner_id
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    raise exception 'Listing not found.';
  end if;

  -- FIX: If the listing is already sold via any path (buy_now or prior auction
  -- payment), exit early. The FOR UPDATE lock above ensures we see the
  -- committed result of any concurrent mark_listing_sold transaction.
  if v_status = 'sold' then
    return;
  end if;

  -- Existing idempotency guard for auction_status (unchanged).
  if v_auction_status = 'sold' then
    return;
  end if;

  if v_auction_status <> 'ended' then
    raise exception 'Auction is not in ended state.';
  end if;

  if v_winner_id is distinct from v_caller_id then
    raise exception 'You are not the auction winner.';
  end if;

  perform set_config('app.bypass_listing_guard', 'on', true);

  update public.listings
     set status         = 'sold',
         auction_status = 'sold',
         sold_at        = now()
   where id = p_listing_id;
end;
$$;
