/**
 * app/(tabs)/home.tsx — Home / Feed screen
 *
 * Changes vs previous version:
 *  • One shared `now` ticker (1 s interval) drives ALL card countdowns
 *    — no per-card timer, no flicker.
 *  • `timeRemaining(endsAt, now)` is a pure function; takes `now` as arg
 *    so the FlatList re-renders once per second from a single setState.
 *  • Status pill badges on each card:
 *      SOLD       — listing.status === 'sold'
 *      RESERVED   — listing.status === 'reserved' AND reserved_until > now
 *      ENDED      — auction_status === 'ended' OR ends_at < now (and not sold)
 *      ENDING SOON — active + ends_at within 15 min
 *      ACTIVE     — default live state
 *  • HH:MM:SS countdown shown when < 24 h remaining.
 */

import { router } from 'expo-router';
import { Image } from 'expo-image';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { resolveCoverUrls } from '@/src/lib/coverImage';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';
import type { Listing } from '@/src/types';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function imagePath(listing: Listing): string | null {
  return (listing as any).cover_image_path
      || (listing as any).cover_image_url
      || null;
}

/**
 * Pure countdown string — takes pre-computed `now` so the card is
 * a pure function of props and needs no internal timer.
 */
function timeRemaining(endsAt: string, now: number): string {
  const diff = new Date(endsAt).getTime() - now;
  if (diff <= 0) return 'Ended';
  const totalSec = Math.floor(diff / 1000);
  const h   = Math.floor(totalSec / 3600);
  const m   = Math.floor((totalSec % 3600) / 60);
  const sec = totalSec % 60;
  if (h > 23) return `${Math.floor(h / 24)}d ${h % 24}h left`;
  if (h > 0)  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
  return `${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
}

// ─── Status badge logic ────────────────────────────────────────────────────────

type CardStatus = 'SOLD' | 'RESERVED' | 'ENDED' | 'ENDING SOON' | 'ACTIVE';

function getCardStatus(listing: Listing, now: number): CardStatus {
  // Buy-now sold
  if (listing.status === 'sold') return 'SOLD';

  // Buy-now reservation
  if (
    listing.status === 'reserved' &&
    listing.reserved_until &&
    new Date(listing.reserved_until).getTime() > now
  ) return 'RESERVED';

  // Auction finalised OR clock expired
  const auctionEnded =
    listing.auction_status === 'ended' ||
    new Date(listing.ends_at).getTime() <= now;
  if (auctionEnded) return 'ENDED';

  // Ending within 15 minutes
  const msLeft = new Date(listing.ends_at).getTime() - now;
  if (msLeft <= 15 * 60 * 1000) return 'ENDING SOON';

  return 'ACTIVE';
}

const CARD_STATUS_STYLE: Record<CardStatus, { bg: string; border: string; text: string }> = {
  'ACTIVE':       { bg: colors.primarySoft,            border: colors.primary,  text: colors.primary },
  'ENDING SOON':  { bg: 'rgba(255,77,109,0.15)',        border: colors.error,    text: colors.error },
  'ENDED':        { bg: 'rgba(255,255,255,0.06)',       border: colors.border,   text: colors.textMuted },
  'RESERVED':     { bg: 'rgba(255,165,0,0.12)',         border: '#FFA500',       text: '#FFA500' },
  'SOLD':         { bg: 'rgba(255,255,255,0.06)',       border: colors.border,   text: colors.textMuted },
};

// ─── Card ─────────────────────────────────────────────────────────────────────

function ListingCard({
  listing,
  coverUrl,
  now,
}: {
  listing: Listing;
  coverUrl: string | null;
  now: number;
}) {
  const status    = getCardStatus(listing, now);
  const timeLabel = timeRemaining(listing.ends_at, now);
  const isEnded   = status === 'ENDED' || status === 'SOLD';
  const statusStyle = CARD_STATUS_STYLE[status];

  return (
    <Pressable
      style={s.card}
      onPress={() => router.push(`/listing/${listing.id}`)}
      android_ripple={{ color: colors.primarySoft }}
    >
      {/* Cover image */}
      <View style={s.cardImageWrap}>
        {coverUrl ? (
          <Image source={{ uri: coverUrl }} style={s.cardImage} contentFit="cover" />
        ) : (
          <View style={[s.cardImage, s.cardImagePlaceholder]}>
            <Text style={s.cardImagePlaceholderText}>🎟️</Text>
          </View>
        )}

        {/* Countdown badge — top right */}
        <View style={[s.timeBadge, isEnded && s.timeBadgeEnded]}>
          <Text style={s.timeBadgeText}>{timeLabel}</Text>
        </View>

        {/* Ticket type badge — top left */}
        <View style={s.typeBadge}>
          <Text style={s.typeBadgeText}>{listing.ticket_type}</Text>
        </View>

        {/* Status pill — bottom left */}
        <View style={[s.statusPill, {
          backgroundColor: statusStyle.bg,
          borderColor:     statusStyle.border,
        }]}>
          <Text style={[s.statusPillText, { color: statusStyle.text }]}>{status}</Text>
        </View>
      </View>

      {/* Info */}
      <View style={s.cardBody}>
        <Text style={s.cardEvent} numberOfLines={1}>{listing.event_name}</Text>
        <Text style={s.cardVenue} numberOfLines={1}>
          {listing.venue} · {listing.neighborhood?.replace(/\b\w/g, c => c.toUpperCase()) ?? ''}
        </Text>
        <View style={s.cardFooter}>
          <View>
            <Text style={s.cardBidLabel}>Current bid</Text>
            <Text style={s.cardBidAmount}>${listing.current_bid.toLocaleString()}</Text>
          </View>
          <View style={[s.bidNowBtn, isEnded && s.bidNowBtnEnded]}>
            <Text style={s.bidNowText}>{isEnded ? 'View' : 'Bid now'}</Text>
          </View>
        </View>
      </View>
    </Pressable>
  );
}

// ─── Main Screen ──────────────────────────────────────────────────────────────

export default function HomeScreen() {
  const [listings,   setListings]   = useState<Listing[]>([]);
  const [coverUrls,  setCoverUrls]  = useState<Map<string, string | null>>(new Map());
  const [loading,    setLoading]    = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  // Single shared clock — drives all card countdowns simultaneously.
  const [now,        setNow]        = useState(() => Date.now());

  const initialLoadDone = useRef(false);

  // ── One interval for the whole screen ─────────────────────────────────────
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  async function fetchListings() {
    const { data, error } = await supabase
      .from('listings')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(50);

    if (error) {
      console.warn('[HomeScreen] fetch error:', error.message);
      return;
    }
    if (!data) return;

    const rows = data as Listing[];
    setListings(rows);

    const paths  = rows.map(r => imagePath(r));
    const urlMap = await resolveCoverUrls(paths);
    setCoverUrls(prev => new Map([...prev, ...urlMap]));
  }

  // ── Initial load ────────────────────────────────────────────────────────────
  useEffect(() => {
    fetchListings().finally(() => {
      setLoading(false);
      initialLoadDone.current = true;
    });
  }, []);

  // ── Refetch on focus ────────────────────────────────────────────────────────
  useFocusEffect(
    useCallback(() => {
      if (!initialLoadDone.current) return;
      fetchListings();
    }, []),
  );

  // ── Realtime: INSERT new listings + UPDATE current_bid / status ─────────────
  useEffect(() => {
    const channel = supabase
      .channel('home-listings-feed')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'listings' },
        async (payload) => {
          const { data } = await supabase
            .from('listings')
            .select('*')
            .eq('id', payload.new.id)
            .single();
          if (data) {
            const newListing = data as Listing;
            setListings(prev => [newListing, ...prev]);
            const urlMap = await resolveCoverUrls([imagePath(newListing)]);
            setCoverUrls(prev => new Map([...prev, ...urlMap]));
          }
        },
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'listings' },
        (payload) => {
          const updated = payload.new as Partial<Listing> & { id: string };
          setListings(prev =>
            prev.map(l => l.id === updated.id ? { ...l, ...updated } : l),
          );
        },
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, []);

  // ── Pull-to-refresh ─────────────────────────────────────────────────────────
  async function onRefresh() {
    setRefreshing(true);
    await fetchListings();
    setRefreshing(false);
  }

  // ── Render ──────────────────────────────────────────────────────────────────
  return (
    <View style={s.container}>
      <View style={s.header}>
        <Text style={s.logo}>SnatchIt</Text>
        <Text style={s.subtitle}>Live auctions, snatched.</Text>
      </View>

      {loading ? (
        <View style={s.list}>
          {[0, 1, 2].map(i => (
            <View key={i} style={s.skeletonCard}>
              <View style={s.skeletonImage} />
              <View style={s.skeletonBody}>
                <View style={[s.skeletonLine, { width: '70%' }]} />
                <View style={[s.skeletonLine, { width: '50%', marginTop: 6 }]} />
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginTop: 12 }}>
                  <View style={[s.skeletonLine, { width: '30%' }]} />
                  <View style={[s.skeletonLine, { width: 60, height: 28, borderRadius: radius.md }]} />
                </View>
              </View>
            </View>
          ))}
        </View>
      ) : (
        <FlatList
          data={listings}
          keyExtractor={(item) => item.id}
          contentContainerStyle={s.list}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={onRefresh}
              tintColor={colors.primary}
            />
          }
          ListEmptyComponent={
            <View style={s.empty}>
              <Text style={s.emptyIcon}>🎟️</Text>
              <Text style={s.emptyTitle}>No listings yet</Text>
              <Text style={s.emptyText}>Be the first to list your tickets!</Text>
            </View>
          }
          renderItem={({ item }) => (
            <ListingCard
              listing={item}
              coverUrl={coverUrls.get(imagePath(item) ?? '') ?? null}
              now={now}
            />
          )}
          // Re-render cards when the clock ticks (extraData ensures FlatList
          // doesn't skip renders when the data array reference is stable).
          extraData={now}
        />
      )}

      {/* Create FAB */}
      <TouchableOpacity
        style={s.fab}
        onPress={() => router.push('/(tabs)/create')}
        activeOpacity={0.85}>
        <Text style={s.fabText}>＋ List Tickets</Text>
      </TouchableOpacity>
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },

  header: {
    paddingTop: 56, paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
    borderBottomWidth: 1, borderBottomColor: colors.border,
  },
  logo:     { fontSize: 28, fontWeight: '900', color: colors.text, letterSpacing: 1 },
  subtitle: { fontSize: fontSize.sm, color: colors.textMuted, marginTop: 2 },

  loader: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  list:   { padding: spacing.md, paddingBottom: 120 },

  card: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.lg,
    borderWidth: 1, borderColor: colors.border,
    marginBottom: spacing.md,
    overflow: 'hidden',
    ...shadow.card,
  },
  cardImageWrap:            { position: 'relative', height: 180 },
  cardImage:                { width: '100%', height: '100%' },
  cardImagePlaceholder:     { backgroundColor: colors.bgInput, alignItems: 'center', justifyContent: 'center' },
  cardImagePlaceholderText: { fontSize: 40 },

  // Countdown — top right
  timeBadge: {
    position: 'absolute', top: 10, right: 10,
    backgroundColor: 'rgba(0,0,0,0.72)',
    paddingHorizontal: 10, paddingVertical: 4,
    borderRadius: radius.full,
    borderWidth: 1, borderColor: colors.border,
  },
  timeBadgeEnded: { borderColor: colors.error },
  timeBadgeText:  {
    color: colors.text, fontSize: fontSize.xs, fontWeight: '700',
    fontVariant: ['tabular-nums'], // prevent digit-width jitter
  },

  // Ticket type — top left
  typeBadge: {
    position: 'absolute', top: 10, left: 10,
    backgroundColor: colors.primarySoft,
    paddingHorizontal: 10, paddingVertical: 4,
    borderRadius: radius.full,
    borderWidth: 1, borderColor: colors.primary,
  },
  typeBadgeText: { color: colors.primary, fontSize: fontSize.xs, fontWeight: '700' },

  // Status pill — bottom left of image
  statusPill: {
    position: 'absolute', bottom: 10, left: 10,
    paddingHorizontal: 8, paddingVertical: 3,
    borderRadius: radius.full,
    borderWidth: 1,
  },
  statusPillText: { fontSize: 10, fontWeight: '800', letterSpacing: 0.6 },

  cardBody:     { padding: spacing.md },
  cardEvent:    { fontSize: fontSize.md, fontWeight: '700', color: colors.text, marginBottom: 2 },
  cardVenue:    { fontSize: fontSize.xs, color: colors.textMuted, marginBottom: spacing.sm },
  cardFooter:   { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end', marginTop: 4 },
  cardBidLabel: { fontSize: fontSize.xs, color: colors.textDim, textTransform: 'uppercase', letterSpacing: 0.8 },
  cardBidAmount:{ fontSize: fontSize.lg, fontWeight: '800', color: colors.text },

  bidNowBtn:      { backgroundColor: colors.primary, borderRadius: radius.md, paddingHorizontal: 16, paddingVertical: 7 },
  bidNowBtnEnded: { backgroundColor: colors.bgInput },
  bidNowText:     { color: colors.text, fontSize: fontSize.xs, fontWeight: '700' },

  empty:      { flex: 1, alignItems: 'center', justifyContent: 'center', paddingTop: 80, gap: spacing.sm },
  emptyIcon:  { fontSize: 48 },
  emptyTitle: { fontSize: fontSize.lg, fontWeight: '700', color: colors.text },
  emptyText:  { fontSize: fontSize.sm, color: colors.textMuted },

  fab: {
    position: 'absolute', bottom: spacing.xl, left: spacing.lg, right: spacing.lg,
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: radius.md,
    alignItems: 'center',
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 12,
    elevation: 8,
  },
  fabText: { color: colors.text, fontWeight: '800', fontSize: fontSize.md, letterSpacing: 0.5 },

  // Skeleton loading
  skeletonCard: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    marginBottom: spacing.md,
    overflow: 'hidden',
  },
  skeletonImage: {
    width: '100%',
    height: 180,
    backgroundColor: colors.bgInput,
  },
  skeletonBody: {
    padding: spacing.md,
  },
  skeletonLine: {
    height: 14,
    borderRadius: radius.sm,
    backgroundColor: colors.bgInput,
  },
});
