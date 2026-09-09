/**
 * app/(tabs)/home.tsx — Home / discovery feed.
 *
 * V2. The data layer below is UNCHANGED from the previous revision: the same
 * three queries, the same realtime channel, the same blocked-seller filtering,
 * the same neighbourhood preference sort, the same lazy sold/ended loads and the
 * same one-second ticker. Only the presentation was rewritten.
 *
 * What the presentation changed, and why:
 *  - The feed was listing-first: a full-width 180pt landscape band per row with a
 *    red "ACTIVE" pill on every card. It is now event-first — a two-up 4:5 grid
 *    of artwork, the shape the media system was designed around and the same one
 *    the approved listing detail hero uses.
 *  - Every card said "Current bid" and "Bid now", including on Buy Now listings
 *    and on listings with no bids at all. Card copy is now mode-aware, decided in
 *    src/lib/listing/cardState.ts and tested there.
 *  - The header hardcoded `paddingTop: 56`. It reads the real safe-area inset.
 *  - The floating "List Tickets" button is gone: Create is a tab, and the button
 *    was a second route to the same screen.
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Animated, FlatList, RefreshControl, StyleSheet, View, type NativeScrollEvent, type NativeSyntheticEvent } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { allInFromDollars } from '@/src/lib/money';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { applyBlockedSellerFilter, useBlockedUserIds } from '@/src/hooks/useBlockedUserIds';
import { Chip, EmptyState } from '@/src/components/ui';
import { useDockScroll } from '@/src/components/nav/dockContext';
import { useDockClearance } from '@/src/lib/nav/navInsets';
import {
  initialFilterBarState,
  reduceFilterBarScroll,
  type FilterBarState,
} from '@/src/lib/home/filterBarMachine';
import {
  DEFAULT_FILTERS,
  activeFilterCount,
  hasPriceFilter,
  hasSheetFilters,
  sheetFilterCount,
  type Filters,
  type QuickChip,
} from '@/src/lib/home/filterModel';
import { useReducedMotion } from '@/src/hooks/useReducedMotion';
import { DiscoveryCard } from '@/src/components/discovery/DiscoveryCard';
import { DiscoveryGridSkeleton } from '@/src/components/discovery/DiscoveryGridSkeleton';
import { FilterSheet } from '@/src/components/discovery/FilterSheet';
import { HomeHeader } from '@/src/components/discovery/HomeHeader';
import { cardPresentation, countdownLabel } from '@/src/lib/listing/cardState';
import * as v2 from '@/src/theme/v2';
import type { Listing, MyProfileRPC } from '@/src/types';

// ─── Neighborhood prefs helper ───────────────────────────────────────────────

async function getUserNeighborhoods(): Promise<Set<string>> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Set();
  const { data } = await supabase.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle();
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

// The filter model (QuickChip, Filters, DEFAULT_FILTERS, active-state helpers)
// lives in src/lib/home/filterModel.ts so the quick row and the full FilterSheet
// read exactly one model. The Home quick row shows three controls; the rest of
// the taxonomy lives inside the sheet.

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * The RAW stored cover value. EventMedia resolves it: path encoding, the trusted
 * host check, and a derivative sized to the frame it measured. The previous
 * revision pre-resolved these into full-size public URLs and cached them in a
 * Map, which is what shipped multi-megabyte originals into a small card.
 */
function coverPath(listing: Listing): string | null {
  return (listing as any).cover_image_path
      || (listing as any).cover_image_url
      || null;
}

/** "Sat, Oct 17 · 10:00 PM" */
function whenLabel(date: string, time: string): string {
  const d = new Date(`${date}T${time}`);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true,
  }).replace(/,([^,]*)$/, ' ·$1');
}

export default function HomeScreen() {
  // Adaptive dock: feed scroll direction in, and give the list bottom clearance
  // so its last row is not hidden behind the floating dock.
  const { onScroll: onHomeScroll, expand } = useDockScroll('home');
  const dockClearance = useDockClearance();

  // ── Quick-filter bar (disappearing toolbar) ────────────────────────────────
  // The bar is an OVERLAY on the feed, moved with a transform on the native
  // driver. The previous revision animated its layout HEIGHT above the list,
  // which re-laid out the scroll container on every frame of an active gesture
  // and fed the resulting offset changes straight back into the same state
  // machine — the loop that made a half-finished collapse stick or judder when
  // the finger reversed. Nothing about the feed's layout changes while scrolling
  // now: the list carries a constant top padding equal to the bar, and only the
  // bar's translateY moves, so a reversal simply retargets a UI-thread animation.
  const reduceMotion = useReducedMotion();
  const [filterBar, setFilterBar] = useState<FilterBarState>(initialFilterBarState);
  const [filterBarHeight, setFilterBarHeight] = useState(0);
  const barAnim = useRef(new Animated.Value(0)).current; // 0 = shown, 1 = hidden

  useEffect(() => {
    Animated.timing(barAnim, {
      toValue: filterBar.hidden ? 1 : 0,
      duration: reduceMotion ? 0 : 200,
      useNativeDriver: true, // transform + opacity only
    }).start();
  }, [filterBar.hidden, reduceMotion, barAnim]);

  // Which section the sheet opens on: PRICE lands on price, FILTERS on the top.
  const [sheetFocus, setSheetFocus] = useState<'price' | undefined>(undefined);

  const onFeedScroll = useCallback((e: NativeSyntheticEvent<NativeScrollEvent>) => {
    onHomeScroll(e); // bottom dock — independent state, unchanged
    const y = e.nativeEvent.contentOffset.y;
    setFilterBar((prev) => reduceFilterBarScroll(prev, y));
  }, [onHomeScroll]);

  const [allListings,   setAllListings]   = useState<Listing[]>([]);
  const [soldListings,  setSoldListings]  = useState<Listing[]>([]);
  const [endedListings, setEndedListings] = useState<Listing[]>([]);
  const [loading,       setLoading]       = useState(true);
  const [refreshing,    setRefreshing]    = useState(false);
  const [loadError,     setLoadError]     = useState<'offline' | 'error' | null>(null);
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

    if (error) {
      console.warn('[HomeScreen] fetch error:', error.message);
      setLoadError(isNetworkError(error) ? 'offline' : 'error');
      return;
    }
    if (!data) return;
    setLoadError(null);

    const rows = data as Listing[];
    setAllListings(rows);

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

  }

  useEffect(() => {
    fetchListings().finally(() => { setLoading(false); initialLoadDone.current = true; });
  }, []);

  useFocusEffect(
    useCallback(() => {
      // Returning to Home always shows the full dock.
      expand();
      if (!initialLoadDone.current) return;
      fetchListings();
    }, [expand]),
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

    // Advanced: categories (migration 033 — listings without a category yet
    // default to 'nightlife' server-side, so l.category is always present)
    if (filters.categories.size > 0) {
      result = result.filter(l => filters.categories.has(l.category ?? 'nightlife'));
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

  function onFiltersApply(next: {
    chip: QuickChip; neighborhoods: Set<string>; categories: Set<string>; priceMin: string; priceMax: string;
  }) {
    setFilters(prev => ({ ...prev, ...next }));
    setModalOpen(false);
    // Same lazy-load the quick chips did: these two are separate datasets.
    if (next.chip === 'recently_sold' && !soldLoadedOnce.current)  fetchSoldListings();
    if (next.chip === 'ended'         && !endedLoadedOnce.current) fetchEndedListings();
  }

  const activeCount = activeFilterCount(filters);

  // ── Pull-to-refresh ───────────────────────────────────────────────────────
  async function onRefresh() {
    setRefreshing(true);
    if (filters.chip === 'recently_sold')     await fetchSoldListings();
    else if (filters.chip === 'ended')        await fetchEndedListings();
    else                                      await fetchListings();
    setRefreshing(false);
  }
  // ── Render ────────────────────────────────────────────────────────────────

  // FILTERS signals what the sheet owns. Price and Your scene have their own
  // controls, so they are not counted here and never double-signalled.
  const sheetCount = sheetFilterCount(filters);
  const priceActive = hasPriceFilter(filters);
  const yourSceneActive = filters.chip === 'your_scene';

  const emptyCopy =
    filters.chip === 'recently_sold' ? { title: 'Nothing sold yet', body: 'Completed sales show up here.' }
    : filters.chip === 'ended'       ? { title: 'No ended auctions', body: 'Auctions that closed without a sale show up here.' }
    : activeCount > 0                ? { title: 'No matches', body: 'Try fewer filters.' }
    :                                  { title: 'Nothing live right now', body: 'Check back, or list the tickets you cannot use.' };

  return (
    <View style={s.container}>
      {/* Brand header stays put: the owner's note was about the filter controls. */}
      <HomeHeader onSearch={() => router.push('/(tabs)/explore')} />

      {/* The feed and the quick-filter overlay share this region. `overflow:
          hidden` clips the bar as it slides up, so it never rides over the
          header. */}
      <View style={s.feed}>
      <FlatList
        data={loading ? [] : filteredListings}
        keyExtractor={(item) => item.id}
        numColumns={2}
        columnWrapperStyle={s.column}
        // Constant top inset for the bar: the feed's layout never changes while
        // scrolling, which is what keeps the gesture smooth and interruptible.
        contentContainerStyle={[s.list, { paddingTop: filterBarHeight, paddingBottom: dockClearance }]}
        showsVerticalScrollIndicator={false}
        onScroll={onFeedScroll}
        scrollEventThrottle={16}
        // The ticker drives every countdown on screen; without this the cells
        // memoize and the clocks freeze.
        extraData={now}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={v2.brand.red}
          />
        }
        ListHeaderComponent={loading ? <DiscoveryGridSkeleton /> : null}
        ListEmptyComponent={
          loading ? null : loadError ? (
            <ScreenState
              state={loadError}
              onRetry={() => fetchListings().finally(() => setLoading(false))}
            />
          ) : (
            <EmptyState title={emptyCopy.title} body={emptyCopy.body} />
          )
        }
        renderItem={({ item }) => {
          const presentation = cardPresentation(item, now);
          return (
            <DiscoveryCard
              eventName={item.event_name}
              venue={item.venue}
              whenLabel={whenLabel(item.event_date, item.event_time)}
              coverPath={coverPath(item)}
              presentation={presentation}
              // All-in, through the one money helper. No arithmetic here.
              priceAllIn={allInFromDollars(presentation.priceDollars)}
              altAllIn={presentation.altDollars != null ? allInFromDollars(presentation.altDollars) : null}
              countdown={presentation.showsCountdown ? countdownLabel(item.ends_at, now) : null}
              onPress={() => router.push(`/listing/${item.id}`)}
            />
          );
        }}
      />

      {/* Quick controls: three, and only three. Everything else is behind
          Filters. Hidden state is removed from the a11y tree and untappable. */}
      <Animated.View
        style={[
          s.filterBar,
          {
            opacity: barAnim.interpolate({ inputRange: [0, 1], outputRange: [1, 0] }),
            transform: [{
              translateY: barAnim.interpolate({
                inputRange: [0, 1],
                outputRange: [0, -(filterBarHeight || 0)],
              }),
            }],
          },
        ]}
        onLayout={(e) => {
          const h = e.nativeEvent.layout.height;
          if (h > 0 && h !== filterBarHeight) setFilterBarHeight(h);
        }}
        pointerEvents={filterBar.hidden ? 'none' : 'auto'}
        accessibilityElementsHidden={filterBar.hidden}
        importantForAccessibility={filterBar.hidden ? 'no-hide-descendants' : 'auto'}
      >
        <View style={s.quickRow}>
          <Chip
            label="Your scene"
            selected={yourSceneActive}
            onPress={() => onChipTap('your_scene')}
          />
          <Chip
            label="Price"
            selected={priceActive}
            onPress={() => { setSheetFocus('price'); setModalOpen(true); }}
          />
          <Chip
            label="Filters"
            count={sheetCount > 0 ? sheetCount : undefined}
            selected={hasSheetFilters(filters)}
            onPress={() => { setSheetFocus(undefined); setModalOpen(true); }}
          />
        </View>
      </Animated.View>
      </View>

      <FilterSheet
        visible={modalOpen}
        value={filters}
        focus={sheetFocus}
        onApply={onFiltersApply}
        onClose={() => setModalOpen(false)}
      />
    </View>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: v2.surface.canvas },
  // Holds the feed and the overlay bar; clips the bar as it slides up so it
  // never rides over the brand header.
  feed: { flex: 1, overflow: 'hidden' },
  // Overlay, not a layout row: moving it never re-lays out the feed.
  filterBar: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    backgroundColor: v2.surface.canvas,
  },
  quickRow: {
    flexDirection: 'row',
    gap: v2.space.sm,
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.lg,
    alignItems: 'center',
  },
  chips: {
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.lg,
    gap: v2.space.sm,
    alignItems: 'center',
  },
  // The tab bar sits over the last row; this keeps it reachable.
  list: { paddingBottom: 96 },
  column: {
    paddingHorizontal: v2.space.lg,
    gap: v2.space.lg,
    marginBottom: v2.space.xl,
  },
});
