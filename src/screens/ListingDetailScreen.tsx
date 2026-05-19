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

import { Image } from 'expo-image';
import { router } from 'expo-router';
import * as Haptics from 'expo-haptics';
// import { Audio } from 'expo-av'; // re-enable once mallet-hit.mp3 is added
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActionSheetIOS,
  Animated,
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useFocusEffect } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useListingRealtime } from '@/src/hooks/useListingRealtime';
import { getCoverImageUrl } from '@/src/lib/coverImage';
import { APP_CONFIG } from '@/src/config/app';
import { sendLocalNotification } from '@/src/utils/notifications';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';
import VerifiedSellerBadge from '@/src/components/VerifiedSellerBadge';
import TransferStatusBadge from '@/src/components/TransferStatusBadge';
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

function fmt$(n: number | null | undefined) {
  if (n == null) return '$0';
  return n % 1 === 0
    ? `$${n.toLocaleString('en-US')}`
    : `$${n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

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

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={ir.row}>
      <Text style={ir.label}>{label}</Text>
      <Text style={ir.value}>{value}</Text>
    </View>
  );
}
const ir = StyleSheet.create({
  row:   { flexDirection:'row', justifyContent:'space-between', alignItems:'center',
           paddingVertical: 10, borderBottomWidth:1, borderBottomColor: colors.border },
  label: { fontSize: fontSize.sm, color: colors.textMuted },
  value: { fontSize: fontSize.sm, color: colors.text, fontWeight:'600', flexShrink:1,
           textAlign:'right', marginLeft: spacing.md },
});

function BidRowItem({ bid }: { bid: Bid }) {
  // Prefer display_name, fall back to full_name, then a short id tag.
  const short = bid.bidder_id ? bid.bidder_id.slice(0, 4).toUpperCase() : '----';
  const name  = bid.profiles?.display_name
             ?? bid.profiles?.full_name
             ?? `Bidder ${short}`;
  const initial = name.charAt(0).toUpperCase();
  return (
    <View style={br.row}>
      <View style={br.avatar}><Text style={br.initial}>{initial}</Text></View>
      <View style={{ flex:1 }}>
        <Text style={br.name}>{name}</Text>
        <Text style={br.time}>{timeAgo(bid.created_at)}</Text>
      </View>
      <Text style={br.amount}>{fmt$(bid.amount)}</Text>
    </View>
  );
}
const br = StyleSheet.create({
  row:     { flexDirection:'row', alignItems:'center', gap: spacing.sm,
             paddingVertical: 10, borderBottomWidth:1, borderBottomColor: colors.border },
  avatar:  { width:36, height:36, borderRadius:18, backgroundColor: colors.bgInput,
             alignItems:'center', justifyContent:'center' },
  initial: { color: colors.textMuted, fontSize: fontSize.sm, fontWeight:'700' },
  name:    { color: colors.text, fontSize: fontSize.sm, fontWeight:'600' },
  time:    { color: colors.textDim, fontSize: fontSize.xs, marginTop:1 },
  amount:  { color: colors.text, fontSize: fontSize.md, fontWeight:'800' },
});

// ─── Auction status banner ────────────────────────────────────────────────────

type AuctionBannerVariant = 'winning' | 'outbid' | 'won' | 'lost';

function AuctionBanner({ variant }: { variant: AuctionBannerVariant }) {
  const cfg: Record<AuctionBannerVariant, { bg: string; border: string; text: string; label: string }> = {
    winning: { bg: 'rgba(34,197,94,0.12)',  border: colors.success, text: colors.success, label: "🏆 You're Winning" },
    outbid:  { bg: 'rgba(255,77,109,0.10)', border: colors.error,   text: colors.error,   label: "⚡ You've Been Outbid — Bid Again" },
    won:     { bg: 'rgba(34,197,94,0.14)',  border: colors.success, text: colors.success, label: '🎉 You Won — Tap "Pay Now" below' },
    lost:    { bg: colors.bgCard,           border: colors.border,  text: colors.textMuted, label: 'Auction Ended' },
  };
  const c = cfg[variant];
  return (
    <View style={[ab.wrap, { backgroundColor: c.bg, borderColor: c.border }]}>
      <Text style={[ab.text, { color: c.text }]}>{c.label}</Text>
    </View>
  );
}
const ab = StyleSheet.create({
  wrap: { marginHorizontal: spacing.lg, marginTop: spacing.sm, marginBottom: 2,
          borderRadius: radius.md, borderWidth: 1, paddingVertical: 9,
          alignItems: 'center' },
  text: { fontSize: fontSize.sm, fontWeight: '700' },
});

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

  // ── Auth — wait for getSession() before any outbid logic ──────────────────
  // authLoading is true until the stored session has been resolved once.
  // authReady flips true exactly once and never goes back to false.
  const { user, loading: authLoading } = useAuth();
  const authReady = !authLoading;

  // ── State ──────────────────────────────────────────────────────────────────
  const [listing,    setListing]    = useState<Listing | null>(null);
  const [loading,    setLoading]    = useState(true);
  const [error,      setError]      = useState<string | null>(null);
  const [coverUrl,   setCoverUrl]   = useState<string | null>(null);
  const [reserving,  setReserving]  = useState(false);
  const [finalizing, setFinalizing] = useState(false);
  const [sellerProfile, setSellerProfile] = useState<{ display_name: string | null; is_verified_seller: boolean } | null>(null);
  const [transferStatus,        setTransferStatus]        = useState<TransferStatus | null>(null);
  const [transferId,            setTransferId]            = useState<string | null>(null);
  const [transferBuyerId,       setTransferBuyerId]       = useState<string | null>(null);
  const [transferActionLoading, setTransferActionLoading] = useState(false);

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

  // ── Animation refs ────────────────────────────────────────────────────────
  const outbidAnimY       = useRef(new Animated.Value(-30)).current;
  const outbidAnimOpacity = useRef(new Animated.Value(0)).current;
  const hideTimerRef      = useRef<ReturnType<typeof setTimeout> | null>(null);

  // ── Win banner refs ───────────────────────────────────────────────────────
  // winTitleRef: holds the chosen title string for this win event (set once).
  const winTitleRef        = useRef<string>('');
  const winAnimY           = useRef(new Animated.Value(-30)).current;
  const winAnimOpacity     = useRef(new Animated.Value(0)).current;
  const winHideTimerRef    = useRef<ReturnType<typeof setTimeout> | null>(null);

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
        .select('display_name, is_verified_seller')
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

  // ── Animation helpers ──────────────────────────────────────────────────────
  const animateOutbidIn = useCallback(() => {
    outbidAnimY.setValue(-30);
    outbidAnimOpacity.setValue(0);
    Animated.parallel([
      Animated.timing(outbidAnimY,       { toValue: 0,   duration: 220, useNativeDriver: true }),
      Animated.timing(outbidAnimOpacity, { toValue: 1,   duration: 220, useNativeDriver: true }),
    ]).start();
  }, [outbidAnimY, outbidAnimOpacity]);

  const animateOutbidOut = useCallback(() => {
    Animated.parallel([
      Animated.timing(outbidAnimY,       { toValue: -30, duration: 200, useNativeDriver: true }),
      Animated.timing(outbidAnimOpacity, { toValue: 0,   duration: 200, useNativeDriver: true }),
    ]).start();
  }, [outbidAnimY, outbidAnimOpacity]);

  const animateWinIn = useCallback(() => {
    winAnimY.setValue(-30);
    winAnimOpacity.setValue(0);
    Animated.parallel([
      Animated.timing(winAnimY,       { toValue: 0, duration: 260, useNativeDriver: true }),
      Animated.timing(winAnimOpacity, { toValue: 1, duration: 260, useNativeDriver: true }),
    ]).start();
  }, [winAnimY, winAnimOpacity]);

  const animateWinOut = useCallback(() => {
    Animated.parallel([
      Animated.timing(winAnimY,       { toValue: -30, duration: 220, useNativeDriver: true }),
      Animated.timing(winAnimOpacity, { toValue: 0,   duration: 220, useNativeDriver: true }),
    ]).start();
  }, [winAnimY, winAnimOpacity]);

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
    //    TODO (deep-link routing): when the user taps the notification,
    //    iOS opens the app and the response payload arrives in the
    //    notification-response listener. Wire that listener (in
    //    NativeAppShell or app/_layout.tsx) to read
    //    `data.listingId` + `data.type === 'auction_won'` and call
    //    `router.push('/listing/' + listingId)`. Out of scope here.
    sendLocalNotification({
      title: 'You Snatched It 🎉',
      body:  `You won ${listing.event_name}. Complete checkout to claim your ticket.`,
      data:  { listingId: listing.id, type: 'auction_won' },
    });
  }, [listing?.auction_status, listing?.winner_user_id, listing?.event_name, listing?.id, user?.id, animateWinIn, animateWinOut]); // eslint-disable-line react-hooks/exhaustive-deps

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

  // ── Cleanup hide timers on unmount ────────────────────────────────────────
  useEffect(() => {
    return () => {
      if (hideTimerRef.current)    clearTimeout(hideTimerRef.current);
      if (winHideTimerRef.current) clearTimeout(winHideTimerRef.current);
    };
  }, []);

  // ── Cover image ────────────────────────────────────────────────────────────
  useEffect(() => {
    const raw: string | null =
      (listing as any)?.cover_image_path || (listing as any)?.cover_image_url || null;
    setCoverUrl(raw ? getCoverImageUrl(raw) : null);
  }, [(listing as any)?.cover_image_path, (listing as any)?.cover_image_url]);

  // ── Checkout navigation (10/10 fee model: total = price * (1 + buyer fee)) ─
  function navigateToCheckout() {
    if (!listing || listing.buy_now_price == null) return;
    const price = listing.buy_now_price;
    const fee   = Math.round(price * APP_CONFIG.BUYER_FEE_RATE);
    router.push({
      pathname: '/checkout/[id]',
      params: { id: listing.id, mode: 'buy_now', bidAmount: String(price),
                total: String(price + fee), eventName: listing.event_name, venue: listing.venue },
    });
  }

  function navigateToWinnerCheckout() {
    if (!listing) return;
    const winAmount = (listing as any).winning_bid_amount ?? listing.current_bid ?? 0;
    const fee = Math.round(winAmount * APP_CONFIG.BUYER_FEE_RATE);
    router.push({
      pathname: '/checkout/[id]',
      params: { id: listing.id, mode: 'bid', bidAmount: String(winAmount),
                total: String(winAmount + fee), eventName: listing.event_name, venue: listing.venue },
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

  async function handleMarkSent() {
    if (!transferId || !user?.id) return;
    setTransferActionLoading(true);
    const { error } = await supabase.rpc('mark_transfer_sent', {
      p_transfer_id: transferId,
      p_user_id:     user.id,
    });
    setTransferActionLoading(false);
    if (error) { Alert.alert('Error', error.message); return; }
    setTransferStatus('seller_sent');
    Alert.alert('Sent!', 'Transfer marked as sent.');
  }

  async function handleConfirmReceived() {
    if (!transferId || !user?.id) return;
    setTransferActionLoading(true);

    try {
      const { data, error: fnError } = await supabase.functions.invoke(
        'confirm-and-release',
        {
          body: { transfer_id: transferId },
        },
      );

      setTransferActionLoading(false);

      if (fnError) {
        let message = 'Something went wrong. Please try again.';
        try {
          const ctx = (fnError as any).context;
          if (ctx && typeof ctx.json === 'function') {
            const body = await ctx.json();
            console.error('[confirm-and-release] server error:', JSON.stringify(body));
            if (body?.error) message = body.error;
          } else {
            const body = typeof data === 'string' ? JSON.parse(data) : data;
            if (body?.error) message = body.error;
          }
        } catch {
        }
        Alert.alert('Error', message);
        return;
      }

      // Success — includes both fresh confirmations and idempotent retries
      // (already_released: true). Either way, the transfer is confirmed
      // and the seller payout has been released.
      setTransferStatus('buyer_confirmed');
      Alert.alert('Confirmed!', 'Transfer complete. Enjoy the event! 🎉');
    } catch (err) {
      setTransferActionLoading(false);
      console.error('handleConfirmReceived: unexpected error:', err);
      Alert.alert('Error', 'Something went wrong. Please try again.');
    }
  }

  async function handleReportIssue() {
    if (!transferId || !user?.id) return;
    Alert.alert(
      'Report Issue',
      'Are you sure you want to report a problem with this transfer? This will freeze the transfer and notify support.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Report Issue',
          style: 'destructive',
          onPress: async () => {
            setTransferActionLoading(true);
            const { error } = await supabase.rpc('buyer_dispute_transfer', {
              p_transfer_id: transferId,
            });
            setTransferActionLoading(false);
            if (error) {
              Alert.alert('Error', error.message);
              return;
            }
            setTransferStatus('disputed');
            Alert.alert('Reported', 'The transfer has been flagged. Support will review.');
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

    // expo-router typed routes regenerate on next `expo prebuild` /
    // dev-server start; until then, the string-path form bypasses the
    // outdated route manifest cleanly.
    const actions: { label: string; handler: () => void }[] = [
      {
        label: 'Report this listing',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        handler: () => router.push(`/report/listing/${listing.id}` as any),
      },
      {
        label: 'Report this seller',
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        handler: () => router.push(`/report/user/${sellerId}` as any),
      },
      {
        label: `Block ${sellerName}`,
        handler: () => handleBlockSeller(sellerId, sellerName),
      },
    ];

    if (Platform.OS === 'ios') {
      ActionSheetIOS.showActionSheetWithOptions(
        {
          options:           [...actions.map(a => a.label), 'Cancel'],
          cancelButtonIndex: actions.length,
          destructiveButtonIndex: 2, // "Block …"
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
          ...actions.map(a => ({ text: a.label, onPress: a.handler, style: a.label.startsWith('Block') ? 'destructive' as const : 'default' as const })),
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
    <SafeAreaView style={s.centered}>
      <ActivityIndicator color={colors.primary} size="large" />
    </SafeAreaView>
  );

  if (error) return (
    <SafeAreaView style={s.centered}>
      <Text style={s.errText}>{error}</Text>
      <TouchableOpacity style={s.retryBtn} onPress={() => fetchData()}>
        <Text style={s.retryText}>Retry</Text>
      </TouchableOpacity>
    </SafeAreaView>
  );

  if (!listing) return (
    <SafeAreaView style={s.centered}>
      <Text style={s.errText}>Listing not found.</Text>
      <TouchableOpacity style={s.retryBtn} onPress={() => router.back()}>
        <Text style={s.retryText}>Go Back</Text>
      </TouchableOpacity>
    </SafeAreaView>
  );

  // ─── Derived display values ────────────────────────────────────────────────

  const ticketLabel   = listing.ticket_type;
  const transferLabel = listing.transfer_method === 'mobile_transfer' ? 'Mobile Transfer' : 'Email';

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

  let auctionBannerVariant: AuctionBannerVariant | null = null;
  if (auctionEnded) {
    if (iAmWinner)       auctionBannerVariant = 'won';
    else if (userHasBid) auctionBannerVariant = 'lost';
  } else if (!ended && userHasBid) {
    auctionBannerVariant = myMaxBid >= currentHighest ? 'winning' : 'outbid';
  }

  const hardLocked    = ended || isSold || reservedByOther || reserving || finalizing;
  const bidLocked     = hardLocked || auctionEnded;
  const buyNowVisible = listing.buy_now_enabled && listing.buy_now_price != null
                        && !ended && !isSold && !auctionEnded && !isSeller;
  const buyNowLabel   = reservedByMe ? 'Continue' : `Buy ${fmt$(listing.buy_now_price!)}`;
  const placeBidLabel = isSold        ? 'Sold'
    : reservedByOther                 ? 'Reserved'
    : auctionEnded                    ? 'Ended'
    : ended                           ? 'Ended'
    : '⚡ Place Bid';

  // ─── Render ────────────────────────────────────────────────────────────────

  return (
    <SafeAreaView style={s.safe}>

      {/* ── Top bar ─────────────────────────────────────────── */}
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>←</Text>
        </Pressable>
        <Text style={s.topTitle} numberOfLines={1}>{listing.event_name}</Text>
        {/* Overflow menu — hidden for the seller's own listing (no point
            reporting yourself), shown for everyone else (App Store 1.2). */}
        {!isSeller ? (
          <Pressable
            onPress={openListingActions}
            style={s.backBtn}
            hitSlop={8}
            accessibilityLabel="More actions"
            accessibilityRole="button"
          >
            <Text style={s.backArrow}>{'⋯'}</Text>{/* horizontal ellipsis */}
          </Pressable>
        ) : (
          <View style={{ width: 44 }} />
        )}
      </View>

      {/* ── Animated outbid banner ──────────────────────────────────────────
          position:absolute — always mounted, never shifts layout.
          Starts at translateY:-60 (off-screen above the topBar).
          Slides to translateY:56 on false→true outbid transition; auto-hides
          after 4s.  pointerEvents="none" — never blocks taps.              */}
      <Animated.View
        pointerEvents="none"
        style={[s.outbidBanner, { transform: [{ translateY: outbidAnimY }], opacity: outbidAnimOpacity }]}
      >
        <Text style={s.outbidBannerText}>You've been outbid</Text>
      </Animated.View>

      {/* ── Win notification ────────────────────────────────────────────────
          The slide-in win banner that previously rendered here has been
          removed — it overlapped the navigation header and only worked when
          the user was foregrounded on this screen. The win signal is now
          delivered via a system notification (see the win-detect effect).
          The static "You Won — Tap Pay Now below" pill remains in
          AuctionBanner; that one sits inside the content area and never
          overlaps the header. */}

      {/* ── Reservation / sold banners ─────────────────────── */}
      {isSold && (
        <View style={[s.resBanner, s.resBannerSold]}>
          <Text style={s.resBannerText}>SOLD</Text>
          {transferStatus && (
            <View style={{ marginTop: 4 }}>
              <TransferStatusBadge status={transferStatus} />
            </View>
          )}
        </View>
      )}
      {/* ── Seller refresh hint when transfer not yet visible ─────────── */}
      {isSold && isSeller && !transferStatus && !loading && (
        <TouchableOpacity
          style={s.refreshHint}
          onPress={() => fetchData(true)}
          activeOpacity={0.7}
        >
          <Text style={s.refreshHintText}>
            Transfer loading… tap to refresh
          </Text>
        </TouchableOpacity>
      )}
      {/* ── Transfer action buttons — route to dedicated screens ──────── */}
      {isSold && isSeller && transferId && (transferStatus === 'pending' || transferStatus === 'seller_sent') && (
        <View style={s.transferActionRow}>
          <TouchableOpacity
            style={s.transferBtn}
            onPress={() => router.push(`/transfer/send/${transferId}`)}
            activeOpacity={0.8}
          >
            <Text style={s.transferBtnText}>
              {transferStatus === 'pending' ? '📤 Send Tickets' : '📋 View Transfer'}
            </Text>
          </TouchableOpacity>
        </View>
      )}
      {isSold && isBuyer && transferId && (transferStatus === 'pending' || transferStatus === 'seller_sent') && (
        <View style={s.transferActionRow}>
          <TouchableOpacity
            style={[s.transferBtn, s.transferBtnConfirm]}
            onPress={() => router.push(`/transfer/receive/${transferId}`)}
            activeOpacity={0.8}
          >
            <Text style={s.transferBtnText}>
              {transferStatus === 'seller_sent' ? '📥 Review Transfer' : '📋 View Transfer'}
            </Text>
          </TouchableOpacity>
        </View>
      )}
      {isSold && isBuyer && transferId && transferStatus === 'disputed' && (
        <View style={s.transferActionRow}>
          <TouchableOpacity
            style={[s.transferBtn, s.transferBtnDispute]}
            onPress={() => router.push(`/transfer/receive/${transferId}`)}
            activeOpacity={0.8}
          >
            <Text style={s.transferBtnText}>⚠️ View Dispute</Text>
          </TouchableOpacity>
        </View>
      )}

      {!isSold && reservedByMe && (
        <View style={[s.resBanner, s.resBannerMine]}>
          <Text style={s.resBannerText}>
            🔒  Reserved for you — {fmtCountdownMs(reservationMsLeft)} remaining
          </Text>
        </View>
      )}
      {!isSold && reservedByOther && (
        <View style={[s.resBanner, s.resBannerOther]}>
          <Text style={s.resBannerText}>⏳  Reserved — payment pending</Text>
        </View>
      )}

      {/* ── Static auction status banner ────────────────────── */}
      {auctionBannerVariant !== null && <AuctionBanner variant={auctionBannerVariant} />}

      {finalizing && (
        <View style={s.finalizingRow}>
          <ActivityIndicator color={colors.textMuted} size="small" />
          <Text style={s.finalizingText}>Calculating winner…</Text>
        </View>
      )}

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 120 }}>

        {coverUrl ? (
          <Image source={{ uri: coverUrl }} style={s.cover} contentFit="cover" />
        ) : (
          <View style={[s.cover, s.coverPlaceholder]}>
            <Text style={s.coverPlaceholderText}>🎟️</Text>
          </View>
        )}

        <View style={s.body}>

          {/* Hero card */}
          <View style={s.heroCard}>
            <View style={{ flex: 1 }}>
              <Text style={s.heroLabel}>CURRENT BID</Text>
              <Text style={s.heroAmount}>{fmt$(currentHighest)}</Text>
            </View>
            <View style={s.heroRight}>
              <Text style={s.heroLabel}>TIME LEFT</Text>
              <Text style={[s.heroCountdown, ended && { color: colors.error }]}>
                {countdown || '—'}
              </Text>
            </View>
          </View>

          {sellerProfile && (
            <View style={s.sellerRow}>
              <Text style={s.sellerName}>{sellerProfile.display_name || 'Seller'}</Text>
              <VerifiedSellerBadge isVerified={sellerProfile.is_verified_seller} />
            </View>
          )}

          <Text style={s.sectionHead}>EVENT DETAILS</Text>
          <View style={s.card}>
            <InfoRow label="Venue"        value={listing.venue} />
            <InfoRow label="Date & Time"  value={fmtDate(listing.event_date, listing.event_time)} />
            <InfoRow label="Neighborhood" value={listing.neighborhood.replace(/\b\w/g, c => c.toUpperCase())} />
          </View>

          <Text style={s.sectionHead}>TICKET INFO</Text>
          <View style={s.card}>
            <InfoRow label="Type"     value={ticketLabel} />
            <InfoRow label="Quantity" value={String(listing.quantity)} />
            <InfoRow label="Transfer" value={transferLabel} />
            {listing.restrictions ? <InfoRow label="Restrictions" value={listing.restrictions} /> : null}
          </View>

          <Text style={s.sectionHead}>PRICING</Text>
          <View style={s.card}>
            <InfoRow label="Starting bid" value={fmt$(listing.starting_bid)} />
            {listing.buy_now_enabled && listing.buy_now_price != null && (
              <InfoRow label="Buy Now" value={fmt$(listing.buy_now_price)} />
            )}
          </View>

          <Text style={s.sectionHead}>BID HISTORY ({bids.length})</Text>
          <View style={s.card}>
            {bids.length === 0 ? (
              <Text style={s.emptyBids}>No bids yet — be the first!</Text>
            ) : (
              bids.map(bid => <BidRowItem key={bid.id} bid={bid} />)
            )}
          </View>

        </View>
      </ScrollView>

      {/* ── Sticky bottom action bar ─────────────────────────────────────── */}
      <View style={s.bar}>
        <View style={{ flex: 1 }}>
          <Text style={s.barLabel}>CURRENT BID</Text>
          <Text style={s.barAmount}>{fmt$(currentHighest)}</Text>
        </View>

        <View style={s.barActions}>

          {buyNowVisible && (
            <TouchableOpacity
              style={[s.buyBtn, hardLocked && s.buyBtnDisabled]}
              onPress={hardLocked ? undefined : handleBuyNow}
              disabled={hardLocked}
              activeOpacity={0.8}
            >
              {reserving
                ? <ActivityIndicator color={colors.text} size="small" />
                : <Text style={[s.buyBtnText, hardLocked && s.btnTextDisabled]}>{buyNowLabel}</Text>
              }
            </TouchableOpacity>
          )}

          {iAmWinner && (
            <TouchableOpacity style={s.payNowBtn} onPress={navigateToWinnerCheckout} activeOpacity={0.85}>
              <Text style={s.payNowBtnText}>💳 Pay Now</Text>
            </TouchableOpacity>
          )}

          {!iAmWinner && (
            <TouchableOpacity
              style={[s.bidBtn, bidLocked && s.bidBtnDisabled]}
              onPress={bidLocked ? undefined : () => router.push(`/bid/${listing.id}`)}
              disabled={bidLocked}
              activeOpacity={0.85}
            >
              {finalizing ? (
                <ActivityIndicator color={colors.text} size="small" />
              ) : (
                <Text style={[s.bidBtnText, bidLocked && s.btnTextDisabled]}>{placeBidLabel}</Text>
              )}
            </TouchableOpacity>
          )}

        </View>
      </View>

    </SafeAreaView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe:     { flex: 1, backgroundColor: colors.bg },
  centered: { flex: 1, justifyContent:'center', alignItems:'center',
              backgroundColor: colors.bg, gap: spacing.md },
  errText:  { color: colors.error, fontSize: fontSize.md, textAlign:'center',
              paddingHorizontal: spacing.xl },
  retryBtn: { backgroundColor: colors.primary, paddingHorizontal: spacing.xl,
              paddingVertical: spacing.sm, borderRadius: radius.md },
  retryText:{ color: colors.text, fontWeight:'700' },

  // Animated outbid banner — absolute, sits just below the topBar.
  // top:60 ≈ topBar height (paddingVertical:8×2 + height:44 + border:1 = 61px).
  // translateY -30→0 slides it into its natural position; opacity 0→1 fades in.
  // zIndex:1 keeps it visually under the topBar (zIndex:2) while animating.
  outbidBanner: {
    position: 'absolute', left: 0, right: 0, top: 60, zIndex: 1,
    backgroundColor: colors.bgCard,
    borderBottomWidth: 2, borderBottomColor: colors.primary,
    paddingVertical: 10, alignItems: 'center', justifyContent: 'center',
  },
  outbidBannerText: {
    color: colors.text, fontWeight: '700',
    fontSize: fontSize.sm, letterSpacing: 0.3,
  },

  // Win banner — green accent, two lines (title + body)
  winBanner: {
    position: 'absolute', left: 0, right: 0, top: 60, zIndex: 1,
    backgroundColor: 'rgba(20, 48, 24, 0.97)',
    borderBottomWidth: 2, borderBottomColor: colors.success,
    paddingVertical: 11, paddingHorizontal: spacing.lg,
    alignItems: 'center', gap: 2,
  },
  winBannerTitle: {
    color: colors.success, fontWeight: '800',
    fontSize: fontSize.sm, letterSpacing: 0.5, textAlign: 'center',
  },
  winBannerBody: {
    color: '#a0b8a2', fontWeight: '500',
    fontSize: fontSize.xs, textAlign: 'center',
  },

  topBar:   { flexDirection:'row', alignItems:'center', justifyContent:'space-between',
              paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
              borderBottomWidth:1, borderBottomColor: colors.border, zIndex: 2 },
  backBtn:  { width:44, height:44, alignItems:'flex-start', justifyContent:'center' },
  backArrow:{ color: colors.text, fontSize: fontSize.xl, fontWeight:'600' },
  topTitle: { flex:1, textAlign:'center', color: colors.text,
              fontSize: fontSize.md, fontWeight:'700' },

  resBanner:      { paddingVertical: spacing.sm, paddingHorizontal: spacing.lg, alignItems: 'center' },
  resBannerMine:  { backgroundColor: colors.primary },
  resBannerOther: { backgroundColor: colors.bgInput },
  resBannerSold:  { backgroundColor: colors.bgCard, borderBottomWidth: 1,
                    borderBottomColor: colors.border },
  resBannerText:  { fontSize: fontSize.sm, fontWeight: '700', color: colors.text },

  finalizingRow:  { flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
                    gap: spacing.sm, paddingVertical: 6, backgroundColor: colors.bgInput },
  finalizingText: { fontSize: fontSize.xs, color: colors.textMuted, fontWeight: '600' },

  cover:                { width:'100%', height: 220 },
  coverPlaceholder:     { backgroundColor: colors.bgInput, alignItems:'center', justifyContent:'center' },
  coverPlaceholderText: { fontSize: 48 },

  body: { padding: spacing.lg },

  heroCard: {
    flexDirection:'row', alignItems:'center',
    backgroundColor: colors.bgCard, borderRadius: radius.lg,
    borderWidth:1, borderColor: colors.border,
    padding: spacing.lg, marginBottom: spacing.lg, ...shadow.card,
  },
  heroLabel:     { fontSize: fontSize.xs, fontWeight:'700', color: colors.textDim,
                   letterSpacing:1.2, textTransform:'uppercase', marginBottom:4 },
  heroAmount:    { fontSize: fontSize.xxl, fontWeight:'900', color: colors.text },
  heroRight:     { alignItems:'flex-end' },
  heroCountdown: { fontSize: fontSize.lg, fontWeight:'800', color: colors.primary,
                   fontVariant:['tabular-nums'] },

  sellerRow:   { flexDirection:'row', alignItems:'center', gap: spacing.sm, marginBottom: spacing.md },
  sellerName:  { fontSize: fontSize.sm, fontWeight:'600', color: colors.text },

  sectionHead: { fontSize: fontSize.xs, fontWeight:'700', color: colors.textDim,
                 letterSpacing:1.4, textTransform:'uppercase', marginBottom: spacing.sm },
  card:        { backgroundColor: colors.bgCard, borderRadius: radius.lg,
                 borderWidth:1, borderColor: colors.border,
                 paddingHorizontal: spacing.md, marginBottom: spacing.lg, ...shadow.card },
  emptyBids:   { color: colors.textMuted, fontSize: fontSize.sm, textAlign:'center',
                 paddingVertical: spacing.lg },

  bar: {
    flexDirection:'row', alignItems:'center',
    paddingHorizontal: spacing.lg, paddingVertical: spacing.md, paddingBottom: spacing.xl,
    backgroundColor: colors.bgCard,
    borderTopWidth:1, borderTopColor: colors.border, gap: spacing.md,
  },
  barLabel:  { fontSize: fontSize.xs, fontWeight:'700', color: colors.textDim,
               letterSpacing:1.2, textTransform:'uppercase', marginBottom:2 },
  barAmount: { fontSize: fontSize.xl, fontWeight:'800', color: colors.text },
  barActions:{ flexDirection:'row', gap: spacing.sm },

  buyBtn:         { backgroundColor: colors.bgInput, borderWidth:1, borderColor: colors.borderInput,
                    borderRadius: radius.md, paddingVertical: spacing.sm+2, paddingHorizontal: spacing.md,
                    alignItems:'center', justifyContent:'center', minWidth: 80 },
  buyBtnDisabled: { opacity: 0.4 },
  buyBtnText:     { color: colors.text, fontSize: fontSize.sm, fontWeight:'700' },

  payNowBtn:     { backgroundColor: colors.success, borderRadius: radius.md,
                   paddingVertical: spacing.sm+2, paddingHorizontal: spacing.lg,
                   alignItems:'center', justifyContent:'center' },
  payNowBtnText: { color: '#fff', fontSize: fontSize.sm, fontWeight:'800', letterSpacing:0.5 },

  bidBtn:         { backgroundColor: colors.primary, borderRadius: radius.md,
                    paddingVertical: spacing.sm+2, paddingHorizontal: spacing.lg,
                    alignItems:'center', justifyContent:'center' },
  bidBtnDisabled: { backgroundColor: colors.borderInput },
  bidBtnText:     { color: colors.text, fontSize: fontSize.sm, fontWeight:'800', letterSpacing:0.5 },
  btnTextDisabled:{ color: colors.textDim },

  // Transfer refresh hint (seller sees SOLD but transfer not yet loaded)
  refreshHint: {
    paddingHorizontal: spacing.lg,
    paddingVertical:   spacing.sm,
    alignItems:        'center',
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  refreshHintText: {
    color:      colors.textMuted,
    fontSize:   fontSize.xs,
    fontWeight: '600',
  },
  disputedBanner: {
    backgroundColor: 'rgba(139, 0, 0, 0.15)',
    borderRadius:    10,
    padding:         14,
    marginTop:       10,
  },
  disputedBannerText: {
    color:     '#FF6B6B',
    fontSize:  14,
    textAlign: 'center' as const,
  },

  // Transfer action buttons
  transferActionRow: {
    paddingHorizontal: spacing.lg,
    paddingVertical:   spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  transferBtn: {
    backgroundColor: colors.primary,
    borderRadius:    radius.md,
    paddingVertical: spacing.sm + 2,
    alignItems:      'center',
    justifyContent:  'center',
  },
  transferBtnConfirm:  { backgroundColor: colors.success },
  transferBtnDispute:  { backgroundColor: '#8B0000' },
  transferBtnDisabled: { opacity: 0.4 },
  transferBtnText: {
    color:      colors.text,
    fontSize:   fontSize.sm,
    fontWeight: '700',
  },
});
