-- 058_notification_producers.sql   APPLIED 2026-08-05, verified.
--
-- Inbox producers. These ADD durable inbox rows; they do NOT replace or
-- duplicate the existing pg_net push triggers (notify_bid_placed,
-- notify_outbid, notify_transfer_event, notify_moderation_event), which are
-- untouched. Push and inbox are separate channels with separate address spaces.
--
-- Deliberately NOT added: a trigger for any event that notify-transfer already
-- claims through transfer_notifications. Doing so would double-fire.
--
-- Events -> recipient -> dedupe key:
--   bid_received              seller           bid_received:<bid_id>
--   outbid                    prev leader      outbid:<new_bid_id>       (self-outbid skipped)
--   auction_won               winner           auction_won:<listing_id>
--   listing_sold              seller           listing_sold:<transfer_id>
--   buyer_info_needed         buyer            buyer_info_needed:<transfer_id>
--   buyer_confirmation_needed buyer            buyer_confirmation_needed:<transfer_id>
--   transfer_viewed           seller           transfer_viewed:<transfer_id>
--   transfer_confirmed        seller           transfer_confirmed:<transfer_id>
--   transfer_disputed         seller AND buyer transfer_disputed:<transfer_id>:{seller|buyer}
--   payout_released           seller           payout_released:<transfer_id>
--   order_complete            buyer            order_complete:<transfer_id>
--
-- ONE seller row on sale, not two: "listing sold" and "seller action required"
-- are the same instant, and two rows a second apart reads as a bug.
--
-- Payout uses `payout_released_at NULL -> NOT NULL` as its predicate, NOT
-- status: the auto-release path never changes status, so status would miss it.
-- Both release paths write that column exactly once under a guarded UPDATE.
--
-- Every trigger body is wrapped in EXCEPTION WHEN OTHERS -- a second layer
-- beneath the non-raising helper -- so a notification can never abort bidding,
-- payment, transfer or payout.
--
-- Verified live on throwaway data: 2 bids produced 2 bid_received + 1 outbid
-- with no self-outbid; the full transfer lifecycle produced all 9 rows with
-- correct recipients; replaying seller_sent / buyer_confirmed /
-- payout_released / disputed produced ZERO duplicates (every dup_count = 1).
-- All QA data removed afterwards.
--
-- password_changed / email_changed are NOT implemented here. Triggers on the
-- auth schema are not durable (GoTrue owns it) and an error there would abort
-- signup/login. The supported route is a cron sweep of auth.audit_log_entries
-- keyed on its PK -- deferred, and it needs a watermark seeded to now() or the
-- first run backfills historical events.
--
-- Rollback: supabase/rollbacks/057_notifications_dedupe_and_enqueue_helper_rollback.sql

-- ---------------------------------------------------------------------------
-- SQL below recovered verbatim from supabase_migrations.schema_migrations
-- version 20260805044159. This file previously contained documentation only.
-- ---------------------------------------------------------------------------
-- 058: inbox producers. These ADD durable inbox rows; they do not replace or
-- duplicate the existing pg_net push triggers (034/035, notify_transfer_event,
-- notify_moderation_event, notify_bid_placed, notify_outbid), which stay as-is.
-- Push and inbox are separate channels with separate address spaces.
--
-- Every trigger body is wrapped in EXCEPTION WHEN OTHERS: a notification must
-- never abort bidding, payment, transfer or payout. enqueue_notification() is
-- itself non-raising; this is the second layer for the lookups around it.

-- ── bids: new-bid (seller) + outbid (previous leader) ───────────────────────
CREATE OR REPLACE FUNCTION public.notify_bid_inbox()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_seller uuid; v_title text; v_prev uuid;
BEGIN
  BEGIN
    SELECT seller_id, event_name INTO v_seller, v_title
      FROM public.listings WHERE id = NEW.listing_id;

    -- Seller: a bid came in. One row per bid.
    IF v_seller IS NOT NULL AND v_seller <> NEW.bidder_id THEN
      PERFORM public.enqueue_notification(
        v_seller, 'bid_received', 'New bid: $' || NEW.amount,
        'Someone bid $' || NEW.amount || ' on ' || coalesce(v_title,'your listing') || '.',
        '/listing/' || NEW.listing_id::text,
        'bid_received:' || NEW.id::text,
        jsonb_build_object('listing_id', NEW.listing_id, 'bid_id', NEW.id, 'amount', NEW.amount));
    END IF;

    -- Previous high bidder: outbid. Skip self-outbid.
    SELECT bidder_id INTO v_prev FROM public.bids
     WHERE listing_id = NEW.listing_id AND id <> NEW.id
     ORDER BY amount DESC, created_at DESC LIMIT 1;

    IF v_prev IS NOT NULL AND v_prev <> NEW.bidder_id THEN
      PERFORM public.enqueue_notification(
        v_prev, 'outbid', 'You have been outbid',
        'Your bid on ' || coalesce(v_title,'a listing') || ' was beaten. Current bid is $' || NEW.amount || '.',
        '/listing/' || NEW.listing_id::text,
        'outbid:' || NEW.id::text,
        jsonb_build_object('listing_id', NEW.listing_id, 'bid_id', NEW.id));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_bid_inbox failed (bid preserved): %', SQLERRM;
  END;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_notify_bid_inbox ON public.bids;
CREATE TRIGGER trg_notify_bid_inbox AFTER INSERT ON public.bids
  FOR EACH ROW EXECUTE FUNCTION public.notify_bid_inbox();

-- ── listings: auction won ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_auction_won_inbox()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    PERFORM public.enqueue_notification(
      NEW.winner_user_id, 'auction_won', 'You won!',
      'You won ' || coalesce(NEW.event_name,'the auction') || '. Complete checkout to secure your tickets.',
      '/checkout/' || NEW.id::text,
      'auction_won:' || NEW.id::text,
      jsonb_build_object('listing_id', NEW.id));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_auction_won_inbox failed: %', SQLERRM;
  END;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_notify_auction_won_inbox ON public.listings;
CREATE TRIGGER trg_notify_auction_won_inbox AFTER UPDATE OF winner_user_id ON public.listings
  FOR EACH ROW WHEN (NEW.winner_user_id IS NOT NULL AND OLD.winner_user_id IS NULL)
  EXECUTE FUNCTION public.notify_auction_won_inbox();

-- ── transfers INSERT: listing sold (seller) + action needed (buyer) ─────────
-- Deliberately ONE seller row. "listing sold" and "seller action required" are
-- the same instant; two rows a second apart reads as a bug.
CREATE OR REPLACE FUNCTION public.notify_transfer_created_inbox()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_title text;
BEGIN
  BEGIN
    SELECT event_name INTO v_title FROM public.listings WHERE id = NEW.listing_id;

    PERFORM public.enqueue_notification(
      NEW.seller_id, 'listing_sold', 'Your tickets sold - send them now',
      coalesce(v_title,'Your listing') || ' sold. Send the tickets within 24 hours.',
      '/transfer/send/' || NEW.id::text,
      'listing_sold:' || NEW.id::text,
      jsonb_build_object('transfer_id', NEW.id, 'listing_id', NEW.listing_id));

    PERFORM public.enqueue_notification(
      NEW.buyer_id, 'buyer_info_needed', 'Add your delivery details',
      'Tell the seller where to send your tickets for ' || coalesce(v_title,'your purchase') || '.',
      '/transfer/receive/' || NEW.id::text,
      'buyer_info_needed:' || NEW.id::text,
      jsonb_build_object('transfer_id', NEW.id, 'listing_id', NEW.listing_id));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_transfer_created_inbox failed: %', SQLERRM;
  END;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_notify_transfer_created_inbox ON public.transfers;
CREATE TRIGGER trg_notify_transfer_created_inbox AFTER INSERT ON public.transfers
  FOR EACH ROW EXECUTE FUNCTION public.notify_transfer_created_inbox();

-- ── transfers UPDATE: sent / viewed / confirmed / disputed / payout ─────────
CREATE OR REPLACE FUNCTION public.notify_transfer_state_inbox()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_title text;
BEGIN
  BEGIN
    SELECT event_name INTO v_title FROM public.listings WHERE id = NEW.listing_id;

    IF NEW.status = 'seller_sent' AND OLD.status IS DISTINCT FROM 'seller_sent' THEN
      PERFORM public.enqueue_notification(
        NEW.buyer_id, 'buyer_confirmation_needed', 'Your tickets were sent',
        'The seller sent your tickets for ' || coalesce(v_title,'your purchase') || '. Confirm once you have them.',
        '/transfer/receive/' || NEW.id::text,
        'buyer_confirmation_needed:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    IF NEW.buyer_viewed_at IS NOT NULL AND OLD.buyer_viewed_at IS NULL THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'transfer_viewed', 'Buyer viewed your transfer',
        'The buyer opened the transfer for ' || coalesce(v_title,'your sale') || '.',
        '/transfer/send/' || NEW.id::text,
        'transfer_viewed:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    IF NEW.status = 'buyer_confirmed' AND OLD.status IS DISTINCT FROM 'buyer_confirmed' THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'transfer_confirmed', 'Buyer confirmed receipt',
        'The buyer confirmed they received the tickets for ' || coalesce(v_title,'your sale') || '.',
        '/transfer/send/' || NEW.id::text,
        'transfer_confirmed:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    IF NEW.status = 'disputed' AND OLD.status IS DISTINCT FROM 'disputed' THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'transfer_disputed', 'A dispute was opened',
        'The buyer opened a dispute on ' || coalesce(v_title,'your sale') || '. Your payout is on hold.',
        '/transfer/send/' || NEW.id::text,
        'transfer_disputed:' || NEW.id::text || ':seller',
        jsonb_build_object('transfer_id', NEW.id));
      PERFORM public.enqueue_notification(
        NEW.buyer_id, 'transfer_disputed', 'Your dispute was opened',
        'We received your dispute for ' || coalesce(v_title,'your purchase') || '. Support will follow up.',
        '/transfer/receive/' || NEW.id::text,
        'transfer_disputed:' || NEW.id::text || ':buyer',
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    -- Single authoritative payout predicate. The auto-release path does NOT
    -- change status, so status is unusable here; payout_released_at is the only
    -- transition that happens exactly once, on both release paths.
    IF NEW.payout_released_at IS NOT NULL AND OLD.payout_released_at IS NULL THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'payout_released', 'Your payout was released',
        'Your payout for ' || coalesce(v_title,'your sale') || ' is on its way to your bank.',
        '/account/sales',
        'payout_released:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
      PERFORM public.enqueue_notification(
        NEW.buyer_id, 'order_complete', 'Order complete',
        'Your order for ' || coalesce(v_title,'your purchase') || ' is complete. Enjoy the event!',
        '/account/purchases',
        'order_complete:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_transfer_state_inbox failed: %', SQLERRM;
  END;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_notify_transfer_state_inbox ON public.transfers;
CREATE TRIGGER trg_notify_transfer_state_inbox AFTER UPDATE ON public.transfers
  FOR EACH ROW EXECUTE FUNCTION public.notify_transfer_state_inbox();
