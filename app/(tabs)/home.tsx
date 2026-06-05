/**
 * app/(tabs)/home.tsx — Home / Feed screen
 *
 * Features:
 *  • Quick-filter chip bar: All, Your Scene, GA, VIP, Buy Now, Auction
 *  • Filters modal: neighborhood multi-select + price range
 *  • One shared `now` ticker (1 s interval) drives ALL card countdowns
 *  • Status pill badges: SOLD, RESERVED, ENDED, ENDING SOON, ACTIVE
 *  • Realtime INSERT/UPDATE via Supabase channel
 */

import { router } from 'expo-router';
import { Image } from 'expo-image';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  FlatList,
  Modal,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { resolveCoverUrls } from '@/src/lib/coverImage';
import { applyBlockedSellerFilter, useBlockedUserIds } from '@/src/hooks/useBlockedUserIds';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';
import { NEIGHBORHOODS, NEIGHBORHOOD_LABELS } from '@/src/constants/neighborhoods';
import type { Listing } from '@/src/types';

// ─── Neighborhood prefs helper ───────────────────────────────────────────────

async function getUserNeighborhoods(): Promise<Set<string>> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Set();
  const { data } = await supabase
    .from('profiles')
    .select('preferred_neighborhoods')
    .eq('id', user.id)
    .single();
  return new Set(data?.preferred_neighborhoods ?? []);
}

function sortByNeighborhoods(listings: Listing[], prefs: Set<string>): Listing[] {
  if (prefs.size === 0) return listings;
  const matched: Listing[] = [];
  const rest:    Listing[] = [];
  for (const l of listings) {
    (prefs.has(l.neighborhood) ? matched : rest).push(l);
  }
  return [...matched, ...rest];
}

// ─── Filter types ────────────────────────────────────────────────────────────

type QuickChip = 'all' | 'your_scene' | 'ga' | 'vip' | 'buy_now' | 'auction' | 'ended' | 'recently_sold';

const QUICK_CHIPS: { key: QuickChip; label: string }[] = [
  { key: 'all',             label: 'All' },
  { key: 'your_scene',      label: 'Your Scene' },
  { key: 'ga',              label: 'GA' },
  { key: 'vip',             label: 'VIP' },
  { key: 'buy_now',         label: 'Buy Now' },
  { key: 'auction',         label: 'Auction' },
  { key: 'ended',           label: 'Ended' },
  { key: 'recently_sold',   label: 'Recently Sold' },
];

type Filters = {
  chip: QuickChip;
  neighborhoods: Set<string>;
  priceMin: string;
  priceMax: string;
};

const DEFAULT_FILTERS: Filters = {
  chip: 'all',
  neighborhoods: new Set(),
  priceMin: '',
  priceMax: '',
};

function hasAdvancedFilters(f: Filters): boolean {
  return f.neighborhoods.size > 0 || f.priceMin !== '' || f.priceMax !== '';
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function imagePath(listing: Listing): string | null {
  return (listing as any).cover_image_path
      || (listing as any).cover_image_url
      || null;
}

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

// ─── Status badge logic ──────────────────────────────────────────────────────

type CardStatus = 'SOLD' | 'RESERVED' | 'ENDED' | 'ENDING SOON' | 'ACTIVE';

function getCardStatus(listing: Listing, now: number): CardStatus {
  if (listing.status === 'sold') return 'SOLD';
  if (
    listing.status === 'reserved' &&
    listing.reserved_until &&
    new Date(listing.reserved_until).getTime() > now
  ) return 'RESERVED';
  const auctionEnded =
    listing.auction_status === 'ended' ||
    new Date(listing.ends_at).getTime() <= now;
  if (auctionEnded) return 'ENDED';
  const msLeft = new Date(listing.ends_at).getTime() - now;
  if (msLeft <= 15 * 60 * 1000) return 'ENDING SOON';
  return 'ACTIVE';
}

const CARD_STATUS_STYLE: Record<CardStatus, { bg: string; border: string; text: string }> = {
  'ACTIVE':       { bg: colors.primarySoft,            border: colors.primary,  text: colors.primary },
  'ENDING SOON':  { bg: 'rgba(255,77,109,0.15)',       border: colors.error,    text: colors.error },
  'ENDED':        { bg: 'rgba(255,255,255,0.06)',       border: colors.border,   text: colors.textMuted },
  'RESERVED':     { bg: 'rgba(255,165,0,0.12)',         border: '#FFA500',       text: '#FFA500' },
  'SOLD':         { bg: 'rgba(255,255,255,0.06)',       border: colors.border,   text: colors.textMuted },
};

// ─── Card ────────────────────────────────────────────────────────────────────

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
      <View style={s.cardImageWrap}>
        {coverUrl ? (
          <Image source={{ uri: coverUrl }} style={s.cardImage} contentFit="cover" />
        ) : (
          <View style={[s.cardImage, s.cardImagePlaceholder]}>
            <Text style={s.cardImagePlaceholderText}>🎟️</Text>
          </View>
        )}
        <View style={[s.timeBadge, isEnded && s.timeBadgeEnded]}>
          <Text style={s.timeBadgeText}>{timeLabel}</Text>
        </View>
        <View style={s.typeBadge}>
          <Text style={s.typeBadgeText}>{listing.ticket_type}</Text>
        </View>
        <View style={[s.statusPill, {
          backgroundColor: statusStyle.bg,
          borderColor:     statusStyle.border,
        }]}>
          <Text style={[s.statusPillText, { color: statusStyle.text }]}>{status}</Text>
        </View>
      </View>

      <View style={s.cardBody}>
        <Text style={s.cardEvent} numberOfLines={1}>{listing.event_name}</Text>
        <Text style={s.cardVenue} numberOfLines={1}>
          {listing.venue} · {listing.neighborhood?.replace(/\b\w/g, c => c.toUpperCase()) ?? ''}
        </Text>
        <View style={s.cardFooter}>
          <View>
            <Text style={s.cardBidLabel}>{status === 'SOLD' ? 'Sold for' : 'Current bid'}</Text>
            <Text style={[s.cardBidAmount, status === 'SOLD' && s.cardBidAmountSold]}>
              ${listing.current_bid.toLocaleString()}
            </Text>
          </View>
          <View style={[s.bidNowBtn, isEnded && s.bidNowBtnEnded]}>
            <Text style={s.bidNowText}>{isEnded ? 'View' : 'Bid now'}</Text>
          </View>
        </View>
      </View>
    </Pressable>
  );
}

// ─── Filter Modal ────────────────────────────────────────────────────────────

function FiltersModal({
  visible,
  filters,
  onApply,
  onClose,
}: {
  visible: boolean;
  filters: Filters;
  onApply: (f: Filters) => void;
  onClose: () => void;
}) {
  const [localHoods, setLocalHoods] = useState<Set<string>>(new Set(filters.neighborhoods));
  const [minP, setMinP] = useState(filters.priceMin);
  const [maxP, setMaxP] = useState(filters.priceMax);

  // Sync when modal opens
  useEffect(() => {
    if (visible) {
      setLocalHoods(new Set(filters.neighborhoods));
      setMinP(filters.priceMin);
      setMaxP(filters.priceMax);
    }
  }, [visible]);

  function toggleHood(h: string) {
    setLocalHoods(prev => {
      const next = new Set(prev);
      next.has(h) ? next.delete(h) : next.add(h);
      return next;
    });
  }

  function apply() {
    onApply({ ...filters, neighborhoods: localHoods, priceMin: minP, priceMax: maxP });
  }

  function clearAll() {
    setLocalHoods(new Set());
    setMinP('');
    setMaxP('');
  }

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <View style={ms.overlay}>
        <View style={ms.sheet}>
          {/* Header */}
          <View style={ms.header}>
            <Text style={ms.title}>Filters</Text>
            <Pressable onPress={onClose} hitSlop={8}>
              <Text style={ms.closeBtn}>✕</Text>
            </Pressable>
          </View>

          <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: spacing.lg }}>
            {/* Neighborhoods */}
            <Text style={ms.sectionLabel}>NEIGHBORHOOD</Text>
            <View style={ms.chipGrid}>
              {NEIGHBORHOODS.map(h => {
                const active = localHoods.has(h);
                return (
                  <Pressable
                    key={h}
                    style={[ms.chip, active && ms.chipActive]}
                    onPress={() => toggleHood(h)}
                  >
                    <Text style={[ms.chipText, active && ms.chipTextActive]}>
                      {NEIGHBORHOOD_LABELS[h]}
                    </Text>
                  </Pressable>
                );
              })}
            </View>

            {/* Price range */}
            <Text style={ms.sectionLabel}>PRICE RANGE</Text>
            <View style={ms.priceRow}>
              <TextInput
                style={ms.priceInput}
                placeholder="Min"
                placeholderTextColor={colors.textPlaceholder}
                keyboardType="numeric"
                value={minP}
                onChangeText={setMinP}
              />
              <Text style={ms.priceDash}>—</Text>
              <TextInput
                style={ms.priceInput}
                placeholder="Max"
                placeholderTextColor={colors.textPlaceholder}
                keyboardType="numeric"
                value={maxP}
                onChangeText={setMaxP}
              />
            </View>
          </ScrollView>

          {/* Footer */}
          <View style={ms.footer}>
            <Pressable onPress={clearAll} style={ms.clearBtn}>
              <Text style={ms.clearBtnText}>Clear All</Text>
            </Pressable>
            <Pressable onPress={apply} style={ms.applyBtn}>
              <Text style={ms.applyBtnText}>Apply</Text>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

export default function HomeScreen() {
  const [allListings,   setAllListings]   = useState<Listing[]>([]);
  const [soldListings,  setSoldListings]  = useState<Listing[]>([]);
  const [endedListings, setEndedListings] = useState<Listing[]>([]);
  const [coverUrls,     setCoverUrls]     = useState<Map<string, string | null>>(new Map());
  const [loading,       setLoading]       = useState(true);
  const [refreshing,    setRefreshing]    = useState(false);
  const [now,           setNow]           = useState(() => Date.now());
  const [filters,       setFilters]       = useState<Filters>(DEFAULT_FILTERS);
  const [modalOpen,     setModalOpen]     = useState(false);

  const initialLoadDone   = useRef(false);
  const soldLoadedOnce    = useRef(false);
  const endedLoadedOnce   = useRef(false);
  const neighborhoodPrefs = useRef<Set<string>>(new Set());

  // UGC moderation: filter out blocked-seller listings from every feed.
  const { blockedIds } = useBlockedUserIds();
  // Mirror to a ref so realtime postgres_changes handlers (mounted once via
  // an empty-deps useEffect below) always see the current block set without
  // re-subscribing on every block/unblock.
  const blockedIdsRef = useRef<Set<string>>(blockedIds);
  useEffect(() => { blockedIdsRef.current = blockedIds; }, [blockedIds]);

  // ── Clock ─────────────────────────────────────────────────────────────────
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  // ── Fetch ─────────────────────────────────────────────────────────────────
  async function fetchListings() {
    neighborhoodPrefs.current = await getUserNeighborhoods();

    const baseQuery = supabase
      .from('listings')
      .select('*')
      .eq('status', 'active')
      .order('created_at', { ascending: false })
      .limit(50);
    const { data, error } = await applyBlockedSellerFilter(baseQuery, blockedIds);

    if (error) { console.warn('[HomeScreen] fetch error:', error.message); return; }
    if (!data) return;

    const rows = data as Listing[];
    setAllListings(rows);

    const paths  = rows.map(r => imagePath(r));
    const urlMap = await resolveCoverUrls(paths);
    setCoverUrls(prev => new Map([...prev, ...urlMap]));
  }

  async function fetchSoldListings() {
    const baseQuery = supabase
      .from('listings')
      .select('*')
      .eq('status', 'sold')
      .order('sold_at', { ascending: false })
      .limit(30);
    const { data, error } = await applyBlockedSellerFilter(baseQuery, blockedIds);

    if (error) { console.warn('[HomeScreen] sold fetch error:', error.message); return; }
    if (!data) return;

    const rows = data as Listing[];
    setSoldListings(rows);
    soldLoadedOnce.current = true;

    const paths  = rows.map(r => imagePath(r));
    const urlMap = await resolveCoverUrls(paths);
    setCoverUrls(prev => new Map([...prev, ...urlMap]));
  }

  async function fetchEndedListings() {
    // Ended = auction_status 'ended' but not yet sold
    const baseQuery = supabase
      .from('listings')
      .select('*')
      .eq('auction_status', 'ended')
      .neq('status', 'sold')
      .order('ends_at', { ascending: false })
      .limit(30);
    const { data, error } = await applyBlockedSellerFilter(baseQuery, blockedIds);

    if (error) { console.warn('[HomeScreen] ended fetch error:', error.message); return; }
    if (!data) return;

    const rows = data as Listing[];
    setEndedListings(rows);
    endedLoadedOnce.current = true;

    const paths  = rows.map(r => imagePath(r));
    const urlMap = await resolveCoverUrls(paths);
    setCoverUrls(prev => new Map([...prev, ...urlMap]));
  }

  useEffect(() => {
    fetchListings().finally(() => { setLoading(false); initialLoadDone.current = true; });
  }, []);

  useFocusEffect(
    useCallback(() => {
      if (!initialLoadDone.current) return;
      fetchListings();
    }, []),
  );

  // ── Realtime ──────────────────────────────────────────────────────────────
  useEffect(() => {
    const channel = supabase
      .channel('home-listings-feed')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'listings' },
        async (payload) => {
          // Only add active listings to the default feed
          if (payload.new.status !== 'active') return;
          // UGC moderation — never surface a blocked seller's new listing.
          if (payload.new.seller_id && blockedIdsRef.current.has(payload.new.seller_id)) return;
          const { data } = await supabase.from('listings').select('*').eq('id', payload.new.id).single();
          if (data) {
            const nl = data as Listing;
            // Re-check after the round trip in case the user just blocked.
            if (blockedIdsRef.current.has(nl.seller_id)) return;
            setAllListings(prev => [nl, ...prev]);
            const urlMap = await resolveCoverUrls([imagePath(nl)]);
            setCoverUrls(prev => new Map([...prev, ...urlMap]));
          }
        })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'listings' },
        (payload) => {
          const updated = payload.new as Partial<Listing> & { id: string; seller_id?: string };
          // UGC moderation — drop updates for blocked sellers' listings.
          if (updated.seller_id && blockedIdsRef.current.has(updated.seller_id)) {
            setAllListings(prev => prev.filter(l => l.id !== updated.id));
            return;
          }
          // If a listing transitions to sold, remove it from active feed
          if (updated.status === 'sold') {
            setAllListings(prev => prev.filter(l => l.id !== updated.id));
            return;
          }
          // Only keep active listings in the default feed
          if (updated.status && updated.status !== 'active') {
            setAllListings(prev => prev.filter(l => l.id !== updated.id));
            return;
          }
          setAllListings(prev => prev.map(l => l.id === updated.id ? { ...l, ...updated } : l));
        })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, []);

  // ── Helper: is a listing ended (auction over but not sold)? ─────────────
  function isListingEnded(l: Listing): boolean {
    return l.auction_status === 'ended' || new Date(l.ends_at).getTime() <= now;
  }

  // ── Apply filters ─────────────────────────────────────────────────────────
  const filteredListings = useMemo(() => {
    const { chip } = filters;

    // Recently Sold / Ended: separate datasets, no further filtering
    if (chip === 'recently_sold') return soldListings;
    if (chip === 'ended')         return endedListings;

    // Default feed: active only — strip out ended listings
    let result = allListings.filter(l => !isListingEnded(l));

    // Quick chip filters
    if (chip === 'your_scene') {
      result = neighborhoodPrefs.current.size > 0
        ? sortByNeighborhoods(result, neighborhoodPrefs.current)
        : result;
    }
    if (chip === 'ga')       result = result.filter(l => l.ticket_type === 'GA');
    if (chip === 'vip')      result = result.filter(l => l.ticket_type === 'VIP');
    if (chip === 'buy_now')  result = result.filter(l => l.buy_now_enabled);
    if (chip === 'auction')  result = result.filter(l => !l.buy_now_enabled);

    // Advanced: neighborhoods
    if (filters.neighborhoods.size > 0) {
      result = result.filter(l => filters.neighborhoods.has(l.neighborhood));
    }

    // Advanced: price
    const minP = parseFloat(filters.priceMin);
    const maxP = parseFloat(filters.priceMax);
    if (!isNaN(minP)) result = result.filter(l => l.current_bid >= minP);
    if (!isNaN(maxP)) result = result.filter(l => l.current_bid <= maxP);

    return result;
  }, [allListings, soldListings, endedListings, filters, now]);

  // ── Chip tap ──────────────────────────────────────────────────────────────
  function onChipTap(key: QuickChip) {
    const nextChip = key === filters.chip ? 'all' : key;
    setFilters(prev => ({ ...prev, chip: nextChip }));
    // Lazy-load on first tap
    if (nextChip === 'recently_sold' && !soldLoadedOnce.current)  fetchSoldListings();
    if (nextChip === 'ended'         && !endedLoadedOnce.current) fetchEndedListings();
  }

  function clearAllFilters() {
    setFilters(DEFAULT_FILTERS);
  }

  function onModalApply(f: Filters) {
    setFilters(f);
    setModalOpen(false);
  }

  const activeCount =
    (filters.chip !== 'all' ? 1 : 0) +
    filters.neighborhoods.size +
    (filters.priceMin ? 1 : 0) +
    (filters.priceMax ? 1 : 0);

  // ── Pull-to-refresh ───────────────────────────────────────────────────────
  async function onRefresh() {
    setRefreshing(true);
    if (filters.chip === 'recently_sold')     await fetchSoldListings();
    else if (filters.chip === 'ended')        await fetchEndedListings();
    else                                      await fetchListings();
    setRefreshing(false);
  }

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <View style={s.container}>
      <View style={s.header}>
        <Text style={s.logo}>Snatch It</Text>
        <Text style={s.subtitle}>Live auctions, snatched.</Text>
      </View>

      {/* ── Filter bar ─────────────────────────────────────────────────────── */}
      <View style={s.filterBar}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={s.filterChips}
        >
          {QUICK_CHIPS.map(({ key, label }) => {
            const active = filters.chip === key;
            return (
              <Pressable
                key={key}
                style={[s.filterChip, active && s.filterChipActive]}
                onPress={() => onChipTap(key)}
              >
                <Text style={[s.filterChipText, active && s.filterChipTextActive]}>
                  {label}
                </Text>
              </Pressable>
            );
          })}

          {/* Filters button */}
          <Pressable
            style={[s.filterChip, s.filterChipOutline, hasAdvancedFilters(filters) && s.filterChipActive]}
            onPress={() => setModalOpen(true)}
          >
            <Text style={[
              s.filterChipText,
              hasAdvancedFilters(filters) && s.filterChipTextActive,
            ]}>
              Filters{hasAdvancedFilters(filters) ? ` (${filters.neighborhoods.size + (filters.priceMin ? 1 : 0) + (filters.priceMax ? 1 : 0)})` : ''}
            </Text>
          </Pressable>
        </ScrollView>

        {activeCount > 0 && (
          <Pressable onPress={clearAllFilters} style={s.clearAll} hitSlop={6}>
            <Text style={s.clearAllText}>Clear</Text>
          </Pressable>
        )}
      </View>

      {/* ── Feed ───────────────────────────────────────────────────────────── */}
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
          data={filteredListings}
          keyExtractor={(item) => item.id}
          contentContainerStyle={s.list}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.primary} />
          }
          ListEmptyComponent={
            <View style={s.empty}>
              <Text style={s.emptyIcon}>🎟️</Text>
              <Text style={s.emptyTitle}>
                {filters.chip === 'recently_sold'
                  ? 'No sold listings yet'
                  : filters.chip === 'ended'
                    ? 'No ended auctions'
                    : activeCount > 0 ? 'No matches' : 'No listings yet'}
              </Text>
              <Text style={s.emptyText}>
                {filters.chip === 'recently_sold'
                  ? 'Sold listings will appear here.'
                  : filters.chip === 'ended'
                    ? 'Ended auctions will appear here.'
                    : activeCount > 0
                      ? 'Try adjusting your filters.'
                      : 'Be the first to list your tickets!'}
              </Text>
            </View>
          }
          renderItem={({ item }) => (
            <ListingCard
              listing={item}
              coverUrl={coverUrls.get(imagePath(item) ?? '') ?? null}
              now={now}
            />
          )}
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

      {/* Filters modal */}
      <FiltersModal
        visible={modalOpen}
        filters={filters}
        onApply={onModalApply}
        onClose={() => setModalOpen(false)}
      />
    </View>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bg },

  header: {
    paddingTop: 56, paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
    borderBottomWidth: 1, borderBottomColor: colors.border,
  },
  logo:     { fontSize: 28, fontWeight: '900', color: colors.text, letterSpacing: 1 },
  subtitle: { fontSize: fontSize.sm, color: colors.textMuted, marginTop: 2 },

  // ── Filter bar ────────────────────────────────────────────────────────────
  filterBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    paddingRight: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  filterChips: {
    paddingLeft: spacing.md,
    paddingRight: spacing.xs,
    gap: spacing.xs,
    alignItems: 'center',
  },
  filterChip: {
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: radius.full,
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.border,
  },
  filterChipActive: {
    backgroundColor: colors.primarySoft,
    borderColor: colors.primary,
  },
  filterChipOutline: {
    borderStyle: 'dashed' as any,
  },
  filterChipText: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textMuted,
  },
  filterChipTextActive: {
    color: colors.primary,
  },
  clearAll: {
    paddingHorizontal: spacing.sm,
    paddingVertical: 6,
  },
  clearAllText: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.error,
  },

  // ── Feed ──────────────────────────────────────────────────────────────────
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
    fontVariant: ['tabular-nums'],
  },

  typeBadge: {
    position: 'absolute', top: 10, left: 10,
    backgroundColor: colors.primarySoft,
    paddingHorizontal: 10, paddingVertical: 4,
    borderRadius: radius.full,
    borderWidth: 1, borderColor: colors.primary,
  },
  typeBadgeText: { color: colors.primary, fontSize: fontSize.xs, fontWeight: '700' },

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
  cardBidAmount:     { fontSize: fontSize.lg, fontWeight: '800', color: colors.text },
  cardBidAmountSold: { color: colors.textMuted },

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

  skeletonCard: {
    backgroundColor: colors.bgCard,
    borderRadius: radius.lg,
    borderWidth: 1, borderColor: colors.border,
    marginBottom: spacing.md,
    overflow: 'hidden',
  },
  skeletonImage: { width: '100%', height: 180, backgroundColor: colors.bgInput },
  skeletonBody:  { padding: spacing.md },
  skeletonLine:  { height: 14, borderRadius: radius.sm, backgroundColor: colors.bgInput },
});

// ─── Modal styles ────────────────────────────────────────────────────────────

const ms = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.65)',
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: colors.bg,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    maxHeight: '80%',
    paddingTop: spacing.lg,
    paddingHorizontal: spacing.lg,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.lg,
  },
  title: {
    fontSize: fontSize.lg,
    fontWeight: '800',
    color: colors.text,
  },
  closeBtn: {
    fontSize: fontSize.lg,
    color: colors.textMuted,
    fontWeight: '600',
  },

  sectionLabel: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textDim,
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
    marginTop: spacing.sm,
  },

  chipGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs,
    marginBottom: spacing.md,
  },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: radius.full,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.bgCard,
  },
  chipActive: {
    borderColor: colors.primary,
    backgroundColor: colors.primarySoft,
  },
  chipText: {
    fontSize: fontSize.xs,
    fontWeight: '600',
    color: colors.textMuted,
  },
  chipTextActive: {
    color: colors.primary,
  },

  priceRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  priceInput: {
    flex: 1,
    backgroundColor: colors.bgInput,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    color: colors.text,
    fontSize: fontSize.sm,
  },
  priceDash: {
    color: colors.textMuted,
    fontSize: fontSize.md,
  },

  footer: {
    flexDirection: 'row',
    gap: spacing.sm,
    paddingVertical: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.border,
  },
  clearBtn: {
    flex: 1,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
  },
  clearBtnText: {
    color: colors.textMuted,
    fontWeight: '700',
    fontSize: fontSize.sm,
  },
  applyBtn: {
    flex: 2,
    backgroundColor: colors.primary,
    borderRadius: radius.md,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
  },
  applyBtnText: {
    color: colors.text,
    fontWeight: '800',
    fontSize: fontSize.sm,
  },
});
