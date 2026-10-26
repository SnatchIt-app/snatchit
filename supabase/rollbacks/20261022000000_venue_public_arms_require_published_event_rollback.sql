-- ============================================================================
-- ROLLBACK for 20261022000000_venue_public_arms_require_published_event.sql (registry 176, pgTAP 246).
--
-- !! THIS ROLLBACK REOPENS THE DRAFT READ (owner decision V-13). !!
-- It restores 081's two public arms exactly as 081 created them (the statements below are copied byte
-- for byte from supabase/migrations/081_venue_inventory.sql lines 989-992 and 1019-1024; no later
-- migration on the chain redefines either policy). After it runs, ANY signed-in user again reads a
-- public ticket type's name and price_minor, and its batch's `remaining`, on a DRAFT event, and over
-- REST too if venue_api is exposed. Remove venue_api from the Data API exposed schemas first, or accept
-- that exposure explicitly (the owner's call).
--
-- Touches nothing else: venue_ticket_type_sel_venue, venue_inventory_batch_sel_venue, every grant,
-- RLS enablement and every function stay as they are (176 never changed them). Idempotent.
-- Applied body check BEFORE using this on a hosted project: the pre-apply read P0 in
-- docs/venue-dashboard/176_PUBLIC_ARMS_PUBLISHED_EVENT.md must have shown 081's text on that project;
-- if it showed anything else, this file does not restore that project's prior state. STOP and ask A.
-- The supabase_migrations ledger row is NOT removed here; that is a separate owner-authorised step.
-- Run only under owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 081 verbatim (lines 989-992)
drop policy if exists venue_ticket_type_sel_public on venue.ticket_type;
create policy venue_ticket_type_sel_public
  on venue.ticket_type for select to authenticated
  using (visibility = 'public');

-- 081 verbatim (lines 1019-1024)
drop policy if exists venue_inventory_batch_sel_public on venue.inventory_batch;
create policy venue_inventory_batch_sel_public
  on venue.inventory_batch for select to authenticated
  using (exists (select 1 from venue.ticket_type tt
                  where tt.ticket_type_id = venue.inventory_batch.ticket_type_id
                    and tt.visibility = 'public'));

COMMIT;
