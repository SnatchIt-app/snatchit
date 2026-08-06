-- =============================================================================
-- 054_fix_notify_outbid_aborts_bids.sql
--
-- APPLIED 2026-08-05. PRODUCTION OUTAGE FIX: outbidding was broken.
--
-- The live trigger `on_new_bid_notify` (AFTER INSERT ON public.bids) calls
-- notify_outbid(), which is present in the database but in NO repo migration —
-- it was applied out-of-band and never tracked.
--
-- Its body used the ONE-ARGUMENT form of current_setting():
--     current_setting('app.settings.supabase_url')
-- which RAISES `unrecognized configuration parameter` when the GUC is unset,
-- rather than returning NULL. Verified live: both app.settings.supabase_url and
-- app.settings.service_role_key are unset, and pg_db_role_setting contains no
-- app.settings.* entry for any role or for the database.
--
-- The function had NO exception handler, so that error propagated out of the
-- AFTER trigger and aborted the parent transaction — the bid INSERT itself.
--
-- The blast radius was hidden by the function's own guard:
--     IF v_previous_bidder IS NOT NULL AND v_previous_bidder != NEW.bidder_id
-- The raising line only runs when a DIFFERENT user outbids the current leader.
-- So a first bid succeeded, and the same bidder raising their own bid
-- succeeded, but a genuine competitive bid — the core auction mechanic — failed.
--
-- Consistent with the data: every listing that ever attracted two distinct
-- bidders did so in Feb 2026; no second-distinct-bidder bid has succeeded since.
--
-- FIX: two-argument current_setting (returns NULL instead of raising), an early
-- return when unconfigured, and a belt-and-braces EXCEPTION WHEN OTHERS so no
-- future failure in this notification path can ever roll back a bid again.
-- search_path is now pinned, which it previously was not.
--
-- Behaviour preserved: when the GUCs are configured, the same push fires to the
-- same recipient with the same copy. Today they are unset, so the function
-- returns early and bids simply succeed.
--
-- This is a stopgap that restores bidding. notify_outbid() should ultimately be
-- replaced by the tracked outbid producer, which reads the previous high bidder
-- from validate_and_apply_bid()'s existing SELECT ... FOR UPDATE (race-free)
-- instead of re-deriving it with ORDER BY amount DESC, which mis-attributes on
-- equal amounts, and which uses Vault like 034/035 rather than these
-- never-set app.settings.* GUCs.
--
-- Verified after applying: has_exception_handler = true,
-- uses_safe_current_setting = true, still_has_raising_form = false,
-- search_path = public.
--
-- Rollback: supabase/rollbacks/054_fix_notify_outbid_aborts_bids_rollback.sql
--           (restores the raising version — do not run; it re-breaks bidding)
-- =============================================================================

-- Function body as applied; see the tool-applied migration of the same name.

-- ---------------------------------------------------------------------------
-- SQL below recovered verbatim from supabase_migrations.schema_migrations
-- version 20260805034758. This file previously contained documentation only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_outbid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_previous_bidder uuid;
  v_listing_title   text;
  v_url             text;
  v_key             text;
BEGIN
  -- Everything here is best-effort. A notification must never abort a bid.
  BEGIN
    -- Two-argument current_setting: returns NULL when unset instead of raising.
    -- The one-argument form raised 'unrecognized configuration parameter', and
    -- with no exception handler that error propagated out of this AFTER trigger
    -- and rolled back the bid INSERT itself -- but only on the path where a
    -- DIFFERENT user outbids the current leader, which is exactly the core
    -- competitive-auction case.
    v_url := current_setting('app.settings.supabase_url', true);
    v_key := current_setting('app.settings.service_role_key', true);

    IF v_url IS NULL OR v_key IS NULL THEN
      RETURN NEW;
    END IF;

    SELECT event_name INTO v_listing_title
      FROM listings
     WHERE id = NEW.listing_id;

    SELECT bidder_id INTO v_previous_bidder
      FROM bids
     WHERE listing_id = NEW.listing_id
       AND id != NEW.id
     ORDER BY amount DESC
     LIMIT 1;

    IF v_previous_bidder IS NOT NULL AND v_previous_bidder != NEW.bidder_id THEN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/send-push',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type', 'application/json'
        ),
        body    := jsonb_build_object(
          'user_id', v_previous_bidder,
          'title',   'You''ve been outbid!',
          'body',    'Someone placed a higher bid on ' || coalesce(v_listing_title, 'a listing') || '. Bid again now!'
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_outbid failed (bid preserved): %', SQLERRM;
  END;

  RETURN NEW;
END;
$function$;
