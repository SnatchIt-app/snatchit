/**
 * src/screens/ListingDetailScreen.tsx
 *
 * Realtime — two-channel architecture
 * ─────────────────────────────────────
 * 1. useListingRealtime (hook) — owns all bids: initial fetch + INSERT subscription.
 *    Returns { bids, currentBid, bidCount, highestBidderId, loading }.
 * 2. singleton guard channel here — subscribes only to listings UPDATE.
 *    Dep array is [id] only — never re-subscribes due to unrelated state changes.
 *
 * Auth readiness
 * ──────────────
 * useAuth().loading is true until getSession() resolves.
 * authReady = !authLoading.
 * Outbid detection MUST NOT run until authReady — prevents false positives
 * when user?.id flips null briefly during token refresh.
 *
 * Outbid detection — INSERT-driven, never from render effects
 * ────────────────────────────────────────────────────────────
 * Baseline: set once in useEffect([rt.loading, authReady]) — silent, no haptics.
 * Haptics + animated banner: fire ONLY inside onNewBid (realtime INSERT callback).
 * This guarantees zero false positives on screen entry or auth-token refresh.
 */

import { router } from 'expo-router';
import * as Haptics from 'expo-haptics';
// import { Audio } from 'expo-av'; // re-enable once mallet-hit.mp3 is added
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActionSheetIOS,
  Alert,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useFocusEffect, useNavigation } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { PriceDisplay } from '@/src/components/PriceDisplay';
import { useAuth } from '@/src/hooks/useAuth';
import { useListingRealtime } from '@/src/hooks/useListingRealtime';
import { finalSoldPrice } from '@/src/lib/salePrice';
import { allInFromDollars, allInLabel, buyerTotalCents, dollarsToCents } from '@/src/lib/money';
import { getAvatarUrl } from '@/src/lib/avatarImage';
import { APP_CONFIG } from '@/src/config/app';
import { sendLocalNotification } from '@/src/utils/notifications';
import { Button, EmptyState, Spinner, StickyBar } from '@/src/components/ui';
import { BidActivity } from '@/src/components/listing/BidActivity';
import { ListingHero } from '@/src/components/listing/ListingHero';
import { ListingStatusBanner } from '@/src/components/listing/ListingStatusBanner';
import { OutbidToast } from '@/src/components/listing/OutbidToast';
import { SellerTrustRow } from '@/src/components/listing/SellerTrustRow';
import { TicketDetails, type DetailRow } from '@/src/components/listing/TicketDetails';
import { TransactionPanel } from '@/src/components/listing/TransactionPanel';
import { detailState, type ActionKind } from '@/src/lib/listing/detailState';
import { shouldReleaseReservation } from '@/src/lib/listing/reservationExit';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import type { Bid, Listing, TransferStatus } from '@/src/types';

// ─── Props ────────────────────────────────────────────────────────────────────

type Props = { id: string };

const VALID_TRANSFER_STATUSES: readonly TransferStatus[] = [
  'pending', 'seller_sent', 'buyer_confirmed', 'disputed', 'expired', 'auto_released',
];
function toTransferStatus(s: string | null | undefined): TransferStatus | null {
  if (s && (VALID_TRANSFER_STATUSES as readonly string[]).includes(s)) return s as TransferStatus;
  return null;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmtCountdownMs(ms: number): string {
  if (ms <= 0) return '0:00';
  const totalSec = Math.floor(ms / 1000);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

function useAuctionCountdown(endsAt: string | null): string {
  const [label, setLabel] = useState('');
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (!endsAt) return;
    function tick() {
      const diff = new Date(endsAt!).getTime() - Date.now();
      if (diff <= 0) {
        setLabel('Ended');
        if (timerRef.current) clearInterval(timerRef.current);
        return;
      }
      const h   = Math.floor(diff / 3_600_000);
      const m   = Math.floor((diff % 3_600_000) / 60_000);
      const sec = Math.floor((diff % 60_000) / 1_000);
      if (h > 23) setLabel(`${Math.floor(h / 24)}d ${h % 24}h left`);
      else        setLabel(`${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(sec).padStart(2,'0')}`);
    }
    tick();
    timerRef.current = setInterval(tick, 1000);
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [endsAt]);

  return label;
}

function fmtDate(date: string, time: string): string {
  const d = new Date(`${date}T${time}`);
  return d.toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true,
  });
}

function timeAgo(iso: string): string {
  const sec = (Date.now() - new Date(iso).getTime()) / 1000;
  if (sec < 60)    return `${Math.floor(sec)}s ago`;
  if (sec < 3600)  return `${Math.floor(sec / 60)}m ago`;
  if (sec < 86400) return `${Math.floor(sec / 3600)}h ago`;
  return `${Math.floor(sec / 86400)}d ago`;
}

// ─── Sub-components ───────────────────────────────────────────────────────────
//
// InfoRow, BidRowItem and AuctionBanner used to live here, each with its own
// StyleSheet. They are gone, not renamed: their jobs are now done by
// src/components/listing/{TicketDetails,BidActivity,ListingStatusBanner}, which
// are shared, tokenised and testable. The four grey cards they produced are what
// made this screen read as a stack of boxes.

// ─── Auction-win rotating titles ──────────────────────────────────────────────
// One title is chosen per win event using a deterministic index from listing.id
// so it stays stable for that session (no re-randomise on re-render).

const WIN_TITLES = [
  'LFG. You Snatched It.',
  'Entry is yours.',
  'You just snatched that.',
  "That's yours. Don't fumble it.",
  'Snatched. Locked in.',
] as const;

// ─── Main Screen ──────────────────────────────────────────────────────────────

export default function ListingDetailScreen({ id }: Props) {

  // Sticky-bar stacking is decided by StickyBar itself, from the live window
  // width against a threshold derived from the layout. This screen no longer
  // carries a device breakpoint.

  // ── Auth — wait for getSession() before any outbid logic ──────────────────
  // authLoading is true until the stored session has been resolved once.
  // authReady flips true exactly once and never goes back to false.
  const { user, loading: authLoading } = useAuth();
  const authReady = !authLoading;

  // ── Reservation exit (owner rule) ─────────────────────────────────────────
  // Leaving the listing back to Home releases our Buy Now hold immediately so the
  // ticket returns to other buyers. `beforeRemove` fires when THIS screen is
  // popped; pushing Checkout on top does not fire it, so Checkout -> Listing keeps
  // the hold and its remaining timer. Backgrounding, the Stripe sheet, modals and
  // the keyboard are not navigation removals and never release.
  const navigation = useNavigation();
  const releasedRef = useRef(false);
  const purchasedRef = useRef(false);
  const listingRef = useRef<Listing | null>(null);

  // ── State ──────────────────────────────────────────────────────────────────
  const [listing,    setListing]    = useState<Listing | null>(null);

  // Keep the latest listing for the exit listener, and latch "purchased" so an
  // exit after a completed sale never even asks to release.
  useEffect(() => {
    listingRef.current = listing;
    if (listing?.status === 'sold') purchasedRef.current = true;
  }, [listing]);

  useEffect(() => {
    const unsubscribe = navigation.addListener('beforeRemove', () => {
      const l = listingRef.current;
      const decide = shouldReleaseReservation({
        status: l?.status,
        reservedBy: l?.reserved_by,
        userId: user?.id,
        alreadyReleased: releasedRef.current,
        purchased: purchasedRef.current,
      });
      if (!decide || !user?.id) return;
      releasedRef.current = true;
      // Fire and forget: navigation is never blocked, and the server-side
      // expiry remains the safety net if this request never lands.
      supabase
        .rpc('release_reservation', { p_listing_id: id, p_user_id: user.id })
        .then(({ error }) => {
          if (error) console.warn('[listing] release_reservation failed:', error.message);
        });
    });
    return unsubscribe;
  }, [navigation, user?.id, id]);
  const [loading,    setLoading]    = useState(true);
  const [error,      setError]      = useState<string | null>(null);
  const [reserving,  setReserving]  = useState(false);
  const [finalizing, setFinalizing] = useState(false);
  const [sellerProfile, setSellerProfile] = useState<{ display_name: string | null; is_verified_seller: boolean; avatar_url: string | null; avatar_path: string | null } | null>(null);
  const [transferStatus,        setTransferStatus]        = useState<TransferStatus | null>(null);
  const [transferId,            setTransferId]            = useState<string | null>(null);
  const [transferBuyerId,       setTransferBuyerId]       = useState<string | null>(null);

  // ── Realtime bids hook ─────────────────────────────────────────────────────
  const rt         = useListingRealtime(id, listing?.starting_bid ?? 0, {
    // Stable wrapper — handleNewBidRef.current is updated after every render,
    // so the hook always dispatches to the latest version of the callback.
    onNewBid: (bid, allBids) => handleNewBidRef.current(bid, allBids),
  });
  const bids       = rt.bids;
  const bidsLoaded = !rt.loading;

  // ── Ticker ─────────────────────────────────────────────────────────────────
  const [now, setNow] = useState(() => Date.now());
  const initialLoadDone = useRef(false);

  // ── Singleton channel refs — listings UPDATE only ─────────────────────────
  // Prevents the channel from being torn down and recreated on spurious
  // re-runs of the subscription effect (StrictMode double-invoke, Fast Refresh,
  // parent re-renders that change state but NOT id).
  const channelRef              = useRef<ReturnType<typeof supabase.channel> | null>(null);
  // Tracks last listing channel status for reconnect catch-up.
  const listingChannelStatusRef = useRef<string>('');

  // ── fetchDataRef — always-current reference to fetchData ──────────────────
  // The listing UPDATE channel subscribe callback is created once inside a
  // useEffect.  If we closed over `fetchData` directly, React's closure would
  // capture a stale version.  Storing it in a ref and keeping the ref current
  // gives the callback a stable pointer to the latest function.
  // eslint-disable-next-line @typescript-eslint/no-use-before-define
  const fetchDataRef = useRef<(silent?: boolean) => Promise<void>>(async () => {});

  // ── Outbid gate refs ───────────────────────────────────────────────────────
  // wasOutbidRef:         last known outbid state (false → true triggers haptics)
  // outbidInitializedRef: becomes true after first valid baseline run so we
  //                       never fire haptics on initial load when already outbid
  const wasOutbidRef         = useRef(false);
  const outbidInitializedRef = useRef(false);
  // Always-current userId for the INSERT callback (avoids stale-closure reads).
  const userIdRef            = useRef<string | undefined>(undefined);
  // Always-current handleNewBid — hook calls this via a stable wrapper.
  const handleNewBidRef      = useRef<(bid: Bid, allBids: Bid[]) => void>(() => {});

  // ── Outbid notice ─────────────────────────────────────────────────────────
  // The animation now lives inside OutbidToast, which honours reduced motion.
  // This screen owns only WHEN it shows, which is the part that took several
  // iterations to get free of false positives — see handleNewBid below.
  const [outbidToastVisible, setOutbidToastVisible] = useState(false);
  const hideTimerRef      = useRef<ReturnType<typeof setTimeout> | null>(null);

  // ── Win banner refs ───────────────────────────────────────────────────────
  // winTitleRef: holds the chosen title string for this win event (set once).
  const winTitleRef        = useRef<string>('');

  // ── Notification guard refs — prevent duplicate sends ──────────────────
  const endingSoonSentRef = useRef(false);
  const wonNotifSentRef   = useRef(false);
  const lostNotifSentRef  = useRef(false);

  // ── Countdown ──────────────────────────────────────────────────────────────
  const countdown = useAuctionCountdown(listing?.ends_at ?? null);
  const ended     = listing ? new Date(listing.ends_at) <= new Date() : false;

  // ── Derived render values ──────────────────────────────────────────────────
  // Gate on authReady so banner/derived state never shows while auth is
  // still resolving — avoids one-frame flicker from user?.id being null.
  const myMaxBid = authReady && user?.id
    ? rt.bids.reduce((max, b) => b.bidder_id === user.id ? Math.max(max, b.amount) : max, 0)
    : 0;

  const currentHighest = rt.currentBid;

  const isOutbidNow =
    authReady &&
    !!user?.id &&
    bidsLoaded &&
    rt.bids.length > 0 &&
    myMaxBid > 0 &&
    myMaxBid < currentHighest;

  // ── Reset outbid baseline when listing id changes ─────────────────────────
  // Ensures we never carry stale outbid state from a previous listing visit.
  useEffect(() => {
    wasOutbidRef.current         = false;
    outbidInitializedRef.current = false;
    endingSoonSentRef.current    = false;
    wonNotifSentRef.current      = false;
    lostNotifSentRef.current     = false;
  }, [id]);

  // ── 1-second ticker ────────────────────────────────────────────────────────
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  // ── fetchData ─────────────────────────────────────────────────────────────
  // Only fetches the listing row — bids are owned by useListingRealtime.
  async function fetchData(silent = false) {
    if (!silent) setLoading(true);
    setError(null);

    const listingRes = await supabase.from('listings').select('*').eq('id', id).maybeSingle();

    if (listingRes.error) {
      if (!silent) { setError(listingRes.error.message); setLoading(false); }
      return;
    }
    if (listingRes.data === null) { setListing(null); setLoading(false); return; }

    const fetchedListing = listingRes.data as Listing;
    setListing(fetchedListing);
    setLoading(false);

    // Fetch seller profile
    if (fetchedListing.seller_id) {
      const { data: sp } = await supabase
        .from('profiles')
        .select('display_name, is_verified_seller, avatar_url, avatar_path')
        .eq('id', fetchedListing.seller_id)
        .single();
      if (sp) setSellerProfile(sp);
    }

    // Fetch transfer status if listing is sold
    if (fetchedListing.status === 'sold') {
      const { data: transfer } = await supabase
        .from('transfers')
        .select('id, status, buyer_id')
        .eq('listing_id', fetchedListing.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      setTransferStatus(toTransferStatus(transfer?.status));
      setTransferId(transfer?.id ?? null);
      setTransferBuyerId(transfer?.buyer_id ?? null);
    }

    // Auto-finalize if the auction clock has expired.
    if (new Date(fetchedListing.ends_at) <= new Date() && fetchedListing.auction_status === 'active') {
      setFinalizing(true);
      const { error: rpcErr } = await supabase.rpc('finalize_auction', { p_listing_id: fetchedListing.id });
      setFinalizing(false);
      if (!rpcErr) {
        const { data: refreshed } = await supabase.from('listings').select('*').eq('id', id).maybeSingle();
        if (refreshed) setListing(refreshed as Listing);
      }
    }
  }

  // Keep the ref current so the channel callback always calls the latest version.
  useEffect(() => { fetchDataRef.current = fetchData; });

  useEffect(() => {
    fetchData(false).finally(() => { initialLoadDone.current = true; });
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      if (!initialLoadDone.current) return;
      fetchData(true);
    }, [id]),
  );

  // ── Re-fetch transfer data when listing transitions to sold ────────────────
  // Covers the timing gap where the initial fetchData() ran while the listing
  // was still 'reserved', so the transfer query was skipped. Once the realtime
  // UPDATE patches listing.status to 'sold', this effect fires and loads the
  // transfer row that the webhook inserted.
  //
  // Retry-aware: the webhook inserts the transfer row AFTER the RPC that sets
  // listing.status='sold'. The realtime UPDATE may arrive before the insert
  // completes, so the first query can find nothing. We retry up to 5 times
  // with 2-second gaps to cover this window (10s total).
  useEffect(() => {
    if (listing?.status !== 'sold' || !listing?.id || transferId) return;

    let cancelled = false;

    (async () => {
      for (let attempt = 0; attempt < 5 && !cancelled; attempt++) {
        if (attempt > 0) await new Promise(r => setTimeout(r, 2000));

        const { data: transfer } = await supabase
          .from('transfers')
          .select('id, status, buyer_id')
          .eq('listing_id', listing.id)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();

        if (cancelled) return;

        if (transfer) {
          setTransferStatus(toTransferStatus(transfer.status));
          setTransferId(transfer.id);
          setTransferBuyerId(transfer.buyer_id);
          return; // found it, stop retrying
        }
      }
    })();

    return () => { cancelled = true; };
  }, [listing?.status, listing?.id, transferId]);

  // ── Outbid notice show/hide ────────────────────────────────────────────────
  // Same names, same call sites, same 4-second dwell. Only the mechanism moved.
  const animateOutbidIn  = useCallback(() => setOutbidToastVisible(true), []);
  const animateOutbidOut = useCallback(() => setOutbidToastVisible(false), []);

  // ── Always-current userId ref ─────────────────────────────────────────────
  // Updated every render (no deps) so INSERT callback never reads a stale value.
  useEffect(() => { userIdRef.current = user?.id; }); // no deps

  // ── handleNewBid — fires ONLY from realtime INSERT, never from effects ─────
  //
  // All mutable state is read through refs so this callback needs no
  // React-state deps and won't cause re-subscription in the hook.
  //
  // Rules:
  //   myMax === 0  → user hasn't bid on this listing; ignore entirely.
  //   !initialized → record baseline silently (covers rare race where INSERT
  //                  fires before the rt.loading baseline effect runs).
  //   initialized  → haptics + banner ONLY on false → true transition.
  const handleNewBid = useCallback((newBid: Bid, allBids: Bid[]) => {
    const uid = userIdRef.current;
    if (!uid) return;

    const myMax = allBids.reduce(
      (max, b) => b.bidder_id === uid ? Math.max(max, b.amount) : max, 0,
    );
    if (myMax === 0) return; // User has never bid — nothing to track.

    const highestAmount = allBids.reduce((max, b) => Math.max(max, b.amount), 0);
    const nextIsOutbid  = highestAmount > myMax;

    if (!outbidInitializedRef.current) {
      // Rare: INSERT arrived before the initial-load baseline effect ran.
      // Set baseline silently — no haptics.
      outbidInitializedRef.current = true;
      wasOutbidRef.current         = nextIsOutbid;
      return;
    }

    // Haptics + banner: only on winning → outbid (false → true).
    if (!wasOutbidRef.current && nextIsOutbid) {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {});
      sendLocalNotification({
        title: "You've been outbid!",
        body: `Someone bid higher on ${listing?.event_name ?? 'this listing'}. Tap to bid again.`,
        data: { listingId: listing?.id, type: 'outbid' },
      });
      animateOutbidIn();
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current);
      hideTimerRef.current = setTimeout(() => animateOutbidOut(), 4_000);
    }

    wasOutbidRef.current = nextIsOutbid;
  }, [animateOutbidIn, animateOutbidOut]); // eslint-disable-line react-hooks/exhaustive-deps

  // Keep handleNewBidRef current so the hook always dispatches to the latest fn.
  useEffect(() => { handleNewBidRef.current = handleNewBid; });

  // ── Listings UPDATE subscription — singleton guard ─────────────────────────
  //
  // Dep array is [id] only.  channelRef guards against StrictMode double-invoke
  // and Fast Refresh: if a channel already exists for this id, bail out without
  // returning a cleanup so the live channel is never torn down by a spurious
  // second run.
  //
  // Bids INSERT is handled entirely by useListingRealtime.
  useEffect(() => {
    if (!id) return;

    if (channelRef.current) {
      return; // ← intentionally no cleanup returned
    }

    const channel = supabase
      .channel(`listing-detail-${id}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'listings', filter: `id=eq.${id}` },
        (payload) => {
          setListing(prev => prev ? { ...prev, ...(payload.new as Partial<Listing>) } : prev);
        },
      )
      .subscribe((status, err) => {
        const prev = listingChannelStatusRef.current;
        listingChannelStatusRef.current = status;

        if (status === 'SUBSCRIBED' && (prev === 'CHANNEL_ERROR' || prev === 'TIMED_OUT')) {
          // WebSocket reconnected — silently re-fetch the listing row in case
          // an UPDATE (e.g. auction_status change) arrived while disconnected.
          fetchDataRef.current(true);
        }

        if (status === 'CHANNEL_ERROR') {
          console.warn('[realtime] listing CHANNEL_ERROR id:', id, err ?? '');
          // Do NOT recreate the channel — the Supabase SDK retries automatically.
        }

        if (status === 'TIMED_OUT') {
          console.warn('[realtime] listing TIMED_OUT id:', id);
        }
      });

    channelRef.current = channel;

    // Cleanup only on genuine unmount (or id change).
    return () => {
      if (channelRef.current) {
        supabase.removeChannel(channelRef.current);
        channelRef.current = null;
      }
    };
  }, [id]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Outbid baseline — initial load only, NO haptics ──────────────────────
  //
  // Runs once when the bids are first fully loaded (rt.loading flips false)
  // and auth is ready.  Records wasOutbidRef so that the first realtime INSERT
  // can detect a genuine winning→outbid transition, not a false positive that
  // was already true before the user opened the screen.
  //
  // Haptics are intentionally absent here.  All haptics fire inside
  // handleNewBid (the onNewBid INSERT callback in useListingRealtime).
  useEffect(() => {
    if (rt.loading || !authReady) return;
    if (outbidInitializedRef.current) return;       // already set
    const uid = userIdRef.current;
    if (!uid) return;
    const myMax = rt.bids.reduce(
      (max, b) => b.bidder_id === uid ? Math.max(max, b.amount) : max, 0,
    );
    if (myMax === 0) return; // User hasn't bid yet — baseline set on first INSERT.
    outbidInitializedRef.current = true;
    wasOutbidRef.current = rt.currentBid > myMax;
  }, [rt.loading, authReady]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── "Auction ending soon" notification ──────────────────────────────────
  // Fires once when the auction enters the last 5 minutes and the user has
  // placed at least one bid.  Uses a setTimeout if not yet at the 5-min
  // mark; fires immediately if already within the window.
  useEffect(() => {
    if (!listing?.ends_at || !user?.id || !bidsLoaded) return;
    if (endingSoonSentRef.current) return;
    if ((listing.auction_status ?? 'active') !== 'active') return;

    const hasBid = bids.some(b => b.bidder_id === user.id);
    if (!hasBid) return;

    const endsMs       = new Date(listing.ends_at).getTime();
    const fiveMinBefore = endsMs - 5 * 60 * 1000;
    const nowMs        = Date.now();

    if (nowMs >= endsMs) return; // Already ended

    if (nowMs >= fiveMinBefore) {
      // Already inside the 5-minute window — send immediately
      endingSoonSentRef.current = true;
      sendLocalNotification({
        title: '⏰ Auction Ending Soon',
        body: `${listing.event_name} ends in less than 5 minutes!`,
        data: { listingId: listing.id, type: 'auction_ending_soon' },
      });
      return;
    }

    // Schedule for when the 5-min window starts
    const timer = setTimeout(() => {
      if (!endingSoonSentRef.current) {
        endingSoonSentRef.current = true;
        sendLocalNotification({
          title: '⏰ Auction Ending Soon',
          body: `${listing.event_name} ends in less than 5 minutes!`,
          data: { listingId: listing.id, type: 'auction_ending_soon' },
        });
      }
    }, fiveMinBefore - nowMs);
    return () => clearTimeout(timer);
  }, [listing?.ends_at, listing?.auction_status, listing?.event_name, listing?.id, user?.id, bids, bidsLoaded]);

  // ── "Auction won" notification + in-app banner + sound + haptic ──────────
  // Fires exactly once per win event:
  //   wonNotifSentRef guards against re-fire on re-renders / tab refocus.
  //   Title is deterministic from listing.id — stable for this session.
  //   Banner auto-dismisses after 6 s.  Sound and haptic fire inline.
  useEffect(() => {
    if (!listing || !user?.id) return;
    if (wonNotifSentRef.current) return;
    if ((listing.auction_status ?? 'active') !== 'ended') return;
    if (listing.winner_user_id !== user.id) return;

    wonNotifSentRef.current = true;

    // Deterministic title — last char code of listing UUID mod array length.
    // Never re-randomises on re-render; same win always shows the same title.
    const idx = listing.id.charCodeAt(listing.id.length - 1) % WIN_TITLES.length;
    winTitleRef.current = WIN_TITLES[idx];

    // 1. Haptic — success pattern
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});

    // 2. Local notification — replaces the previous slide-in in-screen
    //    banner. The banner overlapped the screen header (looked broken)
    //    and only fired in-foreground, so users who already navigated
    //    away never saw it. A system notification is visible in the
    //    Notification Center regardless of foreground/background state.
    //    The legacy animateWinIn / animateWinOut / winTitleRef / WIN_TITLES
    //    declarations are intentionally left in place — they're harmless
    //    dead refs and removing them is out of scope for this fix.
    //
    //    Notification-tap deep-link routing is implemented in
    //    src/providers/NativeAppShell.native.tsx via
    //    Notifications.addNotificationResponseReceivedListener — it reads
    //    data.type === 'auction_won' + data.listingId and routes to
    //    /listing/<id>. See useNativeEffects().
    sendLocalNotification({
      title: 'You Snatched It 🎉',
      body:  `You won ${listing.event_name}. Complete checkout to claim your ticket.`,
      data:  { listingId: listing.id, type: 'auction_won' },
    });
  }, [listing?.auction_status, listing?.winner_user_id, listing?.event_name, listing?.id, user?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── "Auction lost" notification ─────────────────────────────────────────
  // Fires once when auction_status flips to 'ended', the user had placed a
  // bid, but is NOT the winner.
  useEffect(() => {
    if (!listing || !user?.id || !bidsLoaded) return;
    if (lostNotifSentRef.current) return;
    if ((listing.auction_status ?? 'active') !== 'ended') return;
    if (listing.winner_user_id === user.id) return; // Won, not lost

    const hasBid = bids.some(b => b.bidder_id === user.id);
    if (!hasBid) return;

    lostNotifSentRef.current = true;
    sendLocalNotification({
      title: 'Auction Ended',
      body: `The auction for ${listing.event_name} has ended. Better luck next time!`,
      data: { listingId: listing.id, type: 'auction_lost' },
    });
  }, [listing?.auction_status, listing?.winner_user_id, listing?.event_name, listing?.id, user?.id, bids, bidsLoaded]);

  // ── Cleanup hide timer on unmount ─────────────────────────────────────────
  useEffect(() => {
    return () => {
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current);
    };
  }, []);

  // ── Cover image ────────────────────────────────────────────────────────────
  // The RAW stored value, handed straight to EventMedia. It resolves the URL
  // itself — encoding the path, checking the host allowlist and requesting a
  // derivative sized to the frame it measured. Pre-resolving here would bypass
  // all three and re-introduce the full-size original.
  const coverPath: string | null =
    (listing as any)?.cover_image_path || (listing as any)?.cover_image_url || null;

  // ── Checkout navigation ─────────────────────────────────────────────────
  // Display estimates use the canonical money util (integer cents); the
  // server independently recomputes and rejects any total mismatch.
  function navigateToCheckout() {
    if (!listing || listing.buy_now_price == null) return;
    const price = listing.buy_now_price;
    router.push({
      pathname: '/checkout/[id]',
      params: { id: listing.id, mode: 'buy_now', bidAmount: String(price),
                totalCents: String(buyerTotalCents(dollarsToCents(price))),
                eventName: listing.event_name, venue: listing.venue },
    });
  }

  function navigateToWinnerCheckout() {
    if (!listing) return;
    const winAmount = (listing as any).winning_bid_amount ?? listing.current_bid ?? 0;
    router.push({
      pathname: '/checkout/[id]',
      params: { id: listing.id, mode: 'bid', bidAmount: String(winAmount),
                totalCents: String(buyerTotalCents(dollarsToCents(winAmount))),
                eventName: listing.event_name, venue: listing.venue },
    });
  }

  // ── Buy Now ────────────────────────────────────────────────────────────────
  async function handleBuyNow() {
    if (!listing) return;
    if (!user?.id) { Alert.alert('Sign in required', 'Please log in to buy tickets.'); return; }
    if (listing.seller_id === user.id) {
      Alert.alert('Not allowed', 'You cannot purchase your own listing.'); return;
    }
    if (!listing.buy_now_enabled || listing.buy_now_price == null) {
      Alert.alert('Buy Now unavailable', 'This listing does not have Buy Now enabled.'); return;
    }
    if (ended || isSold) { Alert.alert('Not available', 'This listing is no longer available.'); return; }
    if (reservedByOther) {
      Alert.alert('Currently reserved', 'Reserved by another buyer. Try again in a few minutes.'); return;
    }
    if (reservedByMe) { navigateToCheckout(); return; }

    setReserving(true);
    const { error: rpcError } = await supabase.rpc('reserve_buy_now', {
      p_listing_id: listing.id, p_user_id: user.id, p_minutes: APP_CONFIG.RESERVATION_MINUTES,
    });
    if (rpcError) {
      setReserving(false);
      const msg = rpcError.message ?? 'Could not reserve this listing.';
      if      (msg.includes('already reserved')) Alert.alert('Currently reserved', 'Reserved by another buyer. Try again soon.');
      else if (msg.includes('sold'))             Alert.alert('Already sold', 'This listing has already been sold.');
      else                                       Alert.alert('Reservation failed', msg);
      return;
    }
    await fetchData();
    setReserving(false);
    navigateToCheckout();
  }

  // ── Transfer actions ───────────────────────────────────────────────────────
  //
  // handleMarkSent, handleConfirmReceived and handleReportIssue used to live
  // here. They were ALREADY UNREACHABLE before this redesign — lint flagged all
  // three as defined-but-never-used on the previous revision, because the screen
  // routes to app/transfer/send/[id] and app/transfer/receive/[id], which carry
  // the live implementations of exactly these three calls.
  //
  // They are deleted rather than kept, deliberately: one of them invoked
  // `confirm-and-release`, which releases a seller's payout. A second, divergent
  // copy of that call sitting in a file where nothing invokes it is a hazard, not
  // a safety net. No capability is lost — the routes that own these actions are
  // unchanged and are still the sticky bar's destinations.

  // ── Seller actions on their own listing ────────────────────────────────────
  // Section is ALWAYS rendered when isSeller === true (no gate).
  // Each handler decides legality at the moment it's tapped and surfaces a
  // user-friendly alert when the action isn't allowed.
  function handleSellerEdit() {
    if (!listing) return;
    // Block edit once any sale activity exists.
    if (listing.status === 'sold' || transferId) {
      Alert.alert('Cannot edit', 'Sold listings can’t be edited.');
      return;
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    router.push(`/listing/edit/${listing.id}` as any);
  }

  async function handleSellerDelete() {
    if (!listing || !user) return;
    // Refuse delete when activity already exists.
    if (listing.status === 'sold' || transferId || (listing.bid_count ?? 0) > 0) {
      Alert.alert(
        'Cannot delete',
        'This listing can’t be deleted because activity already exists. Cancel it instead.',
      );
      return;
    }
    Alert.alert(
      'Delete listing?',
      `Delete "${listing.event_name}" permanently? This cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            const { error } = await supabase
              .from('listings')
              .delete()
              .eq('id', listing.id)
              .eq('seller_id', user.id);
            if (error) {
              Alert.alert('Delete failed', error.message);
              return;
            }
            if (listing.cover_image_path) {
              try { await supabase.storage.from('auction-media').remove([listing.cover_image_path]); }
              catch (e) { console.warn('[ListingDetail] cover cleanup:', e); }
            }
            Alert.alert('Deleted', 'Your listing has been removed.', [
              { text: 'OK', onPress: () => router.back() },
            ]);
          },
        },
      ],
    );
  }

  async function handleSellerCancel() {
    if (!listing || !user) return;
    if (listing.status === 'sold' || transferId) {
      Alert.alert('Cannot cancel', 'Sold listings can’t be canceled.');
      return;
    }
    if (listing.auction_status === 'cancelled') {
      Alert.alert('Already cancelled', 'This listing has already been cancelled.');
      return;
    }
    Alert.alert(
      'Cancel listing?',
      (listing.bid_count ?? 0) > 0
        ? 'This listing has bids. Cancelling will void all bids. Continue?'
        : 'Cancel this listing? Buyers will no longer see it.',
      [
        { text: 'Keep Listing', style: 'cancel' },
        {
          text: 'Cancel Listing',
          style: 'destructive',
          onPress: async () => {
            const { error } = await supabase.rpc('cancel_listing', {
              p_listing_id: listing.id,
              p_user_id:    user.id,
            });
            if (error) {
              Alert.alert('Cancel failed', error.message);
              return;
            }
            Alert.alert('Cancelled', 'Your listing has been cancelled.', [
              { text: 'OK', onPress: () => router.back() },
            ]);
          },
        },
      ],
    );
  }

  // ── UGC moderation actions (App Store Guideline 1.2) ───────────────────────
  // Opens an ActionSheet (iOS-native) / Alert (Android) with three options
  // applicable to viewers who are NOT the seller of the listing:
  //   • Report listing      → /report/listing/<listing-id>
  //   • Report user (seller)→ /report/user/<seller-id>
  //   • Block user (seller) → inserts into public.user_blocks; the seller's
  //                            listings are filtered out of the home/explore
  //                            feeds on the next refresh.
  function openListingActions() {
    if (!listing) return;
    const sellerId   = listing.seller_id;
    const sellerName = sellerProfile?.display_name?.trim() || 'this seller';
    const owner      = !!user?.id && listing.seller_id === user.id;

    // Two menus behind one control. The seller of a listing manages it; everyone
    // else reports or blocks. Owner controls used to sit in a permanent "Owner
    // Actions" block above the artwork, in the middle of the buyer's purchase
    // flow, with a red Delete competing with the primary action.
    const actions: { label: string; destructive?: boolean; handler: () => void }[] = owner
      ? [
          { label: 'Edit listing',   handler: handleSellerEdit },
          { label: 'Cancel listing', destructive: true, handler: handleSellerCancel },
          { label: 'Delete listing', destructive: true, handler: handleSellerDelete },
        ]
      : [
          // expo-router typed routes regenerate on the next prebuild / dev-server
          // start; the string-path form bypasses the stale manifest cleanly.
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          { label: 'Report this listing', handler: () => router.push(`/report/listing/${listing.id}` as any) },
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          { label: 'Report this seller',  handler: () => router.push(`/report/user/${sellerId}` as any) },
          { label: `Block ${sellerName}`, destructive: true, handler: () => handleBlockSeller(sellerId, sellerName) },
        ];

    if (Platform.OS === 'ios') {
      ActionSheetIOS.showActionSheetWithOptions(
        {
          options:                [...actions.map(a => a.label), 'Cancel'],
          cancelButtonIndex:      actions.length,
          // The LAST destructive entry, found rather than hardcoded: the index
          // used to be a literal 2, which is only correct for one of these menus.
          destructiveButtonIndex: actions.reduce(
            (idx, a, i) => (a.destructive ? i : idx),
            -1,
          ),
        },
        (idx) => {
          if (idx >= 0 && idx < actions.length) actions[idx].handler();
        },
      );
    } else {
      // Android: native Alert with one button per action.
      Alert.alert(
        'More actions',
        '',
        [
          ...actions.map(a => ({
            text: a.label,
            onPress: a.handler,
            style: (a.destructive ? 'destructive' : 'default') as 'destructive' | 'default',
          })),
          { text: 'Cancel', style: 'cancel' as const },
        ],
      );
    }
  }

  async function handleBlockSeller(sellerId: string, sellerName: string) {
    if (!user) {
      Alert.alert('Sign in required', 'You need to be signed in to block users.');
      return;
    }
    if (sellerId === user.id) {
      // Defensive — the trigger should be hidden via !isSeller above, but
      // ActionSheet handlers can fire after listing/user state changes.
      return;
    }
    Alert.alert(
      `Block ${sellerName}?`,
      'Their listings will be hidden from your feed. You can unblock from Settings → Blocked Users.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Block',
          style: 'destructive',
          onPress: async () => {
            const { error } = await supabase.from('user_blocks').insert({
              blocker_id: user.id,
              blocked_id: sellerId,
            });
            // 23505 = unique_violation → already blocked. Treat as success.
            if (error && error.code !== '23505') {
              Alert.alert('Could not block', error.message);
              return;
            }
            Alert.alert(
              'Blocked',
              `${sellerName} is hidden from your feed. Unblock anytime in Settings.`,
              [{ text: 'OK', onPress: () => router.back() }],
            );
          },
        },
      ],
    );
  }

  // ─── Guards ────────────────────────────────────────────────────────────────

  if (loading) return (
    <View style={s.centered}>
      <Spinner size="large" label="Loading this listing" />
    </View>
  );

  if (error) return (
    // A raw fetch failure gets the dedicated offline / server-error screen.
    // "Listing not found" (data null) stays its own state below: a listing that
    // was deleted is not a connection problem, and saying so wastes a retry.
    <View style={s.centered}>
      <ScreenState
        state={isNetworkError(error) ? 'offline' : 'error'}
        onRetry={() => fetchData()}
      />
    </View>
  );

  if (!listing) return (
    <View style={s.centered}>
      <EmptyState
        title="Listing not found"
        body="It may have been sold or taken down."
        action={{ label: 'Go back', onPress: () => router.back() }}
      />
    </View>
  );

  // ─── Derived display values ────────────────────────────────────────────────

  const ticketLabel   = listing.ticket_type;
  const transferLabel = listing.transfer_method === 'mobile_transfer' ? 'Mobile transfer' : 'Email';

  const isSold          = listing.status === 'sold';
  const isSeller        = listing.seller_id === user?.id;
  const isBuyer         = !!transferBuyerId && transferBuyerId === user?.id;
  const reservedUntil   = listing.reserved_until ? new Date(listing.reserved_until) : null;
  const isReserved      = listing.status === 'reserved' && reservedUntil != null && reservedUntil > new Date();
  const reservedByMe    = isReserved && listing.reserved_by === user?.id;
  const reservedByOther = isReserved && !!listing.reserved_by && listing.reserved_by !== user?.id;
  const reservationMsLeft = reservedByMe && reservedUntil
    ? Math.max(0, reservedUntil.getTime() - now) : 0;

  const auctionStatus = listing.auction_status ?? 'active';
  const auctionEnded  = auctionStatus === 'ended';
  const winnerUserId  = listing.winner_user_id ?? null;
  const iAmWinner     = auctionEnded && !!user?.id && winnerUserId === user?.id;
  const userHasBid    = myMaxBid > 0;

  // Preformatted by the canonical money helper. Nothing downstream does arithmetic.
  const buyNowAllIn = listing.buy_now_price != null ? allInFromDollars(listing.buy_now_price) : null;

  // ─── One state object drives the whole screen ──────────────────────────────
  // Every offer, refusal and status decision is made in src/lib/listing/detailState.ts
  // and tested there. The render below reads it; it does not re-derive it.
  const state = detailState({
    listing: {
      status:          listing.status,
      auction_status:  listing.auction_status,
      buy_now_enabled: listing.buy_now_enabled,
      buy_now_price:   listing.buy_now_price,
      seller_id:       listing.seller_id,
      reserved_by:     listing.reserved_by,
      winner_user_id:  listing.winner_user_id,
      bid_count:       listing.bid_count,
    },
    userId:            user?.id,
    clockEnded:        ended,
    reservationActive: isReserved,
    finalizing,
    reserving,
    transfer:          { id: transferId, status: transferStatus, buyerId: transferBuyerId },
    isHighestBidder:   userHasBid && myMaxBid >= currentHighest,
    hasBid:            userHasBid,
    buyNowAllIn,
  });

  // The reservation status carries a live clock, which a pure function cannot.
  const status = state.status && state.status.kind === 'reserved_by_you'
    ? { ...state.status, detail: `${fmtCountdownMs(reservationMsLeft)} left to finish checkout.` }
    : state.status;

  // The sold-but-transfer-not-loaded case. The webhook writes the transfer row
  // after the listing flips to sold, so a seller can arrive before it exists.
  // The retry effect above polls for ten seconds; this is the manual escape.
  const needsTransferRefresh = isSold && isSeller && !transferId;

  const soldAllIn = isSold ? allInFromDollars(finalSoldPrice(listing)) : null;
  const currentAllIn = allInFromDollars(currentHighest);
  const nextBidAllIn = allInFromDollars(currentHighest + APP_CONFIG.MIN_BID_INCREMENT);

  const detailRows: DetailRow[] = [
    { label: 'Type', value: ticketLabel },
    { label: 'Quantity', value: `${listing.quantity} ${listing.quantity === 1 ? 'ticket' : 'tickets'}` },
    { label: 'Delivery', value: transferLabel },
    {
      label: 'Category',
      value: (listing.category ?? 'nightlife').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
    },
    { label: 'Started at', value: allInLabel(listing.starting_bid) },
  ];
  // Ownership proof appears only after a human reviewed it. It never claims
  // verification before review (migration 033).
  if (listing.proof_status === 'approved') {
    detailRows.push({ label: 'Ownership proof', value: 'Reviewed by Snatch It' });
  }
  if (listing.restrictions) {
    detailRows.push({ label: 'Restrictions', value: listing.restrictions, block: true });
  }

  // ─── Action wiring ─────────────────────────────────────────────────────────
  // `detailState` decides WHAT is offered; this maps it onto the existing,
  // unchanged handlers. No new navigation target and no new RPC is introduced.
  function runAction(kind: ActionKind) {
    switch (kind) {
      case 'buy_now':
      case 'continue_reservation':
        handleBuyNow();
        return;
      case 'place_bid':
        router.push(`/bid/${listing!.id}`);
        return;
      case 'pay_now':
        navigateToWinnerCheckout();
        return;
      case 'send_tickets':
      case 'view_transfer':
        if (!transferId) return;
        router.push(isSeller ? `/transfer/send/${transferId}` : `/transfer/receive/${transferId}`);
        return;
      case 'review_transfer':
      case 'view_dispute':
        if (!transferId) return;
        router.push(`/transfer/receive/${transferId}`);
        return;
      default:
        return;
    }
  }

  const primaryBusy =
    (state.primary.kind === 'buy_now' || state.primary.kind === 'continue_reservation') && reserving;

  const stickyPriceLabel = isSold ? 'Sold for' : state.mode === 'closed' ? 'Final bid' : 'Current bid';
  const stickyPriceAmount = soldAllIn ?? currentAllIn;

  // ─── Render ────────────────────────────────────────────────────────────────

  return (
    <View style={s.safe}>
      <OutbidToast visible={outbidToastVisible} message="You've been outbid" />

      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={s.scroll}
        // The sticky bar sits over the bottom of the content; this keeps the last
        // section reachable instead of permanently hidden behind it.
        contentInsetAdjustmentBehavior="never"
      >
        <ListingHero
          asset={{
            path: coverPath,
            // Legacy assets were cropped destructively to 16:9 before upload, so
            // they are fitted against a blurred copy of themselves rather than
            // re-cropped into the portrait frame. No black bars, no lost lineup.
            contract: 'legacy',
            bucket: 'auction-media',
          }}
          eventName={listing.event_name}
          venue={listing.venue}
          whenLabel={fmtDate(listing.event_date, listing.event_time)}
          neighborhood={listing.neighborhood?.replace(/\b\w/g, c => c.toUpperCase()) ?? null}
          onBack={() => router.back()}
          onOverflow={openListingActions}
        />

        {status ? (
          <View style={s.statusWrap}>
            <ListingStatusBanner status={status} />
            {needsTransferRefresh ? (
              <Pressable
                onPress={() => fetchData(true)}
                style={s.refreshRow}
                accessibilityRole="button"
                accessibilityLabel="Refresh transfer status"
                hitSlop={8}
              >
                <Text style={[textStyle('label'), s.refreshText]}>Refresh</Text>
              </Pressable>
            ) : null}
          </View>
        ) : null}

        <TransactionPanel
          mode={state.mode}
          currentAllIn={currentAllIn}
          buyNowAllIn={state.mode === 'auction_and_buy_now' ? buyNowAllIn : null}
          nextBidAllIn={state.mode === 'closed' ? null : nextBidAllIn}
          countdown={state.mode === 'closed' ? null : (countdown || null)}
          soldAllIn={soldAllIn}
          bidCount={listing.bid_count ?? 0}
        />

        {sellerProfile ? (
          <SellerTrustRow
            displayName={sellerProfile.display_name || 'Seller'}
            avatarUrl={getAvatarUrl(sellerProfile.avatar_path ?? sellerProfile.avatar_url)}
            isVerified={sellerProfile.is_verified_seller}
            onPress={() => router.push(`/profile/${listing.seller_id}`)}
          />
        ) : null}

        <TicketDetails rows={detailRows} />

        {state.showsBidActivity ? (
          <BidActivity
            bids={bids}
            amountFor={(b) => allInFromDollars(b.amount)}
            timeFor={(b) => timeAgo(b.created_at)}
            viewerId={user?.id}
            highlightTop={!isSold && !auctionEnded && !ended}
          />
        ) : null}

        <View style={s.scrollTail} />
      </ScrollView>

      {/*
        One bar, one decision. Buy Now leads when it exists and bidding sits
        beside it as the secondary; the old screen inverted that, giving instant
        purchase a grey outline and the bid a red fill.
      */}
      <StickyBar
        left={
          <PriceDisplay
            size="sticky"
            label={stickyPriceLabel}
            amount={stickyPriceAmount}
            muted={isSold || state.mode === 'closed'}
          />
        }
      >
        {state.secondary ? (
          <Button
            label={state.secondary.label}
            variant="secondary"
            size="md"
            disabled={state.secondary.disabled}
            onPress={() => runAction(state.secondary!.kind)}
          />
        ) : null}
        <Button
          label={state.primary.label}
          variant="primary"
          size="md"
          disabled={state.primary.disabled || state.primary.kind === 'unavailable'}
          loading={primaryBusy}
          onPress={() => runAction(state.primary.kind)}
        />
      </StickyBar>
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: v2.surface.canvas },

  // The artwork runs under the status bar: the hero is the first thing on the
  // screen and a safe-area gap above it would frame it like a card.
  scroll: { paddingBottom: v2.space.xxxl },
  scrollTail: { height: 96 },

  statusWrap: { marginTop: v2.space.lg },
  refreshRow: {
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: v2.space.lg,
  },
  refreshText: { color: v2.brand.red },

  centered: {
    flex: 1,
    backgroundColor: v2.surface.canvas,
    alignItems: 'center',
    justifyContent: 'center',
    gap: v2.space.md,
    paddingHorizontal: v2.space.xl,
  },
  errText: { color: v2.text.secondary, textAlign: 'center' },
});
