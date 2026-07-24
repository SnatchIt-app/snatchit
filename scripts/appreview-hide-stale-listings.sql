-- App Review marketplace cleanup — hide stale test listings from the "Ended" chip
-- Run in the Supabase SQL editor (production hqycwntpfoztoinemqns).
--
-- Context (2026-07-24): the live Home rail already shows only the three curated
-- review listings (III Points Saturday GA, Space Miami — Mochakk, Quavo E11even).
-- This script removes the leftover expired test/beta listings from the lazy-loaded
-- "Ended" chip by cancelling them through the app's own cancel_listing RPC
-- (owner-scoped, SECURITY DEFINER — no guard weakened, nothing deleted).
--
-- Safe by construction:
--   • touches only status='active' listings whose auction already ended
--   • sold listings, payments, transfers, bids are untouched
--   • idempotent — cancel_listing no-ops on already-cancelled rows

SELECT l.id, l.event_name, cancel_listing(l.id, l.seller_id)
FROM listings l
WHERE l.status = 'active'
  AND l.auction_status = 'ended';

-- Verify: the Ended chip query should return 0 rows afterwards
SELECT count(*) AS still_in_ended_chip
FROM listings
WHERE auction_status = 'ended' AND status <> 'sold';
