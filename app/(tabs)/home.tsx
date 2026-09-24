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
 *
 * V3 (owner 2026-09-22; B's package §3). Presentation only, again: the two-up grid becomes one
 * full-bleed FEATURE (the first live listing, name over the curve-scrimmed artwork) above
 * single-column ROWS — 62pt artwork, name in the display voice, all-in price right-aligned,
 * content-driven heights. The data layer is still byte-for-byte the V2 one.
 *
 * V3 SECTION HEADINGS (owner 2026-09-24, on the pkg8 home boards). The previous revision left the
 * boards' "Tonight" / "This week" headings UNDRAWN because their grouping rule was not written
 * anywhere, and a heading the data cannot guarantee is a small lie. The rule is now written — one
 * pure function in `src/lib/home/sections.ts` — so the headings are drawn from it and from
 * nothing else. The feed is REGROUPED by that rule (soonest first, order preserved inside each
 * section); no row is added, removed or filtered by it, and a bucket that cannot be honestly named
 * — anything already past, which is every row of the Recently sold and Ended datasets — is drawn
 * with no heading at all rather than borrowing the one above it.
 *
 * Still presentation only. Every read, the realtime channel, the blocked-seller filtering, the
 * neighbourhood sort, the lazy sold/ended loads, their F-HOME-1 load states and the one-second
 * ticker are untouched.
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { supabase } from '@/src/lib/supabase';
import { allInFromDollarsV3 } from '@/src/lib/money';
import ScreenState from '@/src/components/ScreenState';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { classifyLoadFailure } from '@/src/lib/ui/loadState';
import {
  HOME_FILTER_REFRESH_FAILED_COPY,
  initialFilterLoadState,
  mayShowEmptyCopy,
  type FilterDataset,
  type FilterLoadState,
} from '@/src/lib/home/filterLoad';
import { failureSurface } from '@/src/lib/screens/refreshPolicy';
import { textStyle } from '@/src/theme/typography';
import { applyBlockedSellerFilter, useBlockedUserIds } from '@/src/hooks/useBlockedUserIds';
import { EmptyState } from '@/src/components/ui';
import { useDockScroll } from '@/src/components/nav/dockContext';
import { useDockClearance } from '@/src/lib/nav/navInsets';
import { groupByEventDate } from '@/src/lib/home/sections';
import { ROW_GUTTER } from '@/src/lib/design/featureMetrics';
import {
  DEFAULT_FILTERS,
  activeFilterCount,
  sheetFilterCount,
  type Filters,
  type QuickChip,
} from '@/src/lib/home/filterModel';
import { DiscoveryGridSkeleton } from '@/src/components/discovery/DiscoveryGridSkeleton';
import { FeedRow } from '@/src/components/discovery/FeedRow';
import { FilterSheet } from '@/src/components/discovery/FilterSheet';
import { HomeFeature } from '@/src/components/discovery/HomeFeature';
import { HomeHeader } from '@/src/components/discovery/HomeHeader';
import { cardPresentation } from '@/src/lib/listing/cardState';
import { stageCardHandoff } from '@/src/lib/listing/cardHandoff';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { Listing, MyProfileRPC } from '@/src/types';
import { setDockAvatar } from '@/src/lib/nav/dockAvatar';

// ─── Neighborhood prefs helper ───────────────────────────────────────────────

async function getUserNeighborhoods(): Promise<Set<string>> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Set();
  const { data } = await supabase.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle();
  // V3: this read already carries the avatar — publish it for the dock's "You" item. Only a
  // successful read publishes; a failure must never blank an already-correct photo.
  if (data) setDockAvatar(user.id, data.avatar_path ?? data.avatar_url);
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
// lives in src/lib/home/filterModel.ts. Home reads it for the header control's
// count; the sheet owns the whole taxonomy, `your_scene` and price included.

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

// V3: date formatting for rows/feature lives in src/lib/listing/feedRowState.ts, inside the
// components, so home and search cannot drift apart.

/**
 * The harness seam's shape (`app/_dev/v3-home.tsx`). It stands in for the THREE reads and for the
 * realtime subscription, and for nothing else: every filter, sort, section, countdown and piece of
 * copy still runs exactly as it does in the app.
 *
 * The lazy datasets and the failure arm are here because their states are otherwise unreachable for
 * review: "Nothing sold yet", "No ended auctions" and the failed-read view each need a read that
 * ACTUALLY RAN — the settled-empty copy is gated on `mayShowEmptyCopy`, which is what stops a slow or
 * failed read from telling a shopper the marketplace is empty. A fixture that only replaced the main
 * feed could not produce any of them, which is exactly what the harness agent found.
 */
export interface HomeFixture {
  /** The live feed's rows. */
  rows?: Listing[];
  /** The lazily-loaded datasets, so their settled-empty copy is reachable. */
  sold?: Listing[];
  ended?: Listing[];
  /** A FIRST-LOAD failure of the live feed, which is the state that shows ScreenState. */
  failure?: 'offline' | 'error';
  /** Which chip the harness starts on, so a dataset's own empty state is the one on screen. */
  chip?: QuickChip;
}

export interface HomeScreenProps {
  /**
   * Render harness seam ONLY. Never passed by a route. An array is the live feed's rows, which is
   * what the first version of this seam took.
   */
  fixture?: Listing[] | HomeFixture;
}

export default function HomeScreen({ fixture: rawFixture }: HomeScreenProps = {}) {
  const fixture: HomeFixture | undefined = Array.isArray(rawFixture) ? { rows: rawFixture } : rawFixture;
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  // Adaptive dock: feed scroll direction in, and give the list bottom clearance
  // so its last row is not hidden behind the floating dock.
  const { onScroll: onHomeScroll, expand } = useDockScroll('home');
  const dockClearance = useDockClearance();

  // ── Filters ────────────────────────────────────────────────────────────────
  // ONE control, on the header line (B's H1 at 911f65fd; the owner's placement ruling). What used to
  // be here: a three-chip overlay on the feed, slid out of the way on scroll by its own state
  // machine. B's finding is that the row is not in the approved composition at all — the board goes
  // header → section heading → feature — so the row, the overlay, its top inset and the machine that
  // hid it are all gone. Nothing was lost with them: the sheet the control opens already owned the
  // taxonomy, and `your_scene` and price are groups in it now.

  const [allListings,   setAllListings]   = useState<Listing[]>([]);
  const [soldListings,  setSoldListings]  = useState<Listing[]>([]);
  const [endedListings, setEndedListings] = useState<Listing[]>([]);
  // F-HOME-1: the two lazy datasets each carry their own load state. Without this a slow or failed read
  // rendered the settled empty copy, so the screen told the shopper the marketplace was empty when it had
  // only failed to look.
  const [filterLoad, setFilterLoad] = useState<Record<FilterDataset, FilterLoadState>>({
    recently_sold: initialFilterLoadState,
    ended: initialFilterLoadState,
  });

  function markFilterLoading(ds: FilterDataset) {
    setFilterLoad((prev) => ({ ...prev, [ds]: { ...prev[ds], loading: true } }));
  }
  function markFilterFailed(ds: FilterDataset, kind: FilterLoadState['error']) {
    setFilterLoad((prev) => ({ ...prev, [ds]: { ...prev[ds], loading: false, error: kind } }));
  }
  function markFilterLoaded(ds: FilterDataset) {
    setFilterLoad((prev) => ({ ...prev, [ds]: { loading: false, error: null, settled: true } }));
  }
  const [loading,       setLoading]       = useState(true);
  const [refreshing,    setRefreshing]    = useState(false);
  const { isOffline } = useNetworkStatus();
  const offlineRef = useRef(false);
  offlineRef.current = isOffline;
  const [loadError,     setLoadError]     = useState<'offline' | 'error' | null>(null);
  const [now,           setNow]           = useState(() => Date.now());
  // The harness may start on a chip, so a lazy dataset's own empty state is the one on screen.
  const [filters,       setFilters]       = useState<Filters>(
    fixture?.chip ? { ...DEFAULT_FILTERS, chip: fixture.chip } : DEFAULT_FILTERS,
  );
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
    // The harness seam, and the only thing it replaces: the read. Nothing below this line changes.
    if (fixture) {
      // The harness seam, and the only thing it replaces: the read. A fixture failure takes the same
      // path a real one does — `setLoadError` — so the screen decides what to paint, not the fixture.
      if (fixture.failure) { setLoadError(fixture.failure); setAllListings([]); return; }
      setAllListings(fixture.rows ?? []); setLoadError(null); return;
    }
    neighborhoodPrefs.current = await getUserNeighborhoods();

    const baseQuery = supabase
      .from('listings')
      .select('*')
      .eq('status', 'active')
      .order('created_at', { ascending: false })
      .limit(50);
    const { data, error } = await applyBlockedSellerFilter(baseQuery, blockedIdsRef.current);

    if (error) {
      console.warn('[HomeScreen] fetch error:', error.message);
      setLoadError(classifyLoadFailure(error, offlineRef.current));
      return;
    }
    if (!data) return;
    setLoadError(null);

    const rows = data as Listing[];
    setAllListings(rows);

  }

  async function fetchSoldListings() {
    markFilterLoading('recently_sold');
    if (fixture) { setSoldListings(fixture.sold ?? []); markFilterLoaded('recently_sold'); soldLoadedOnce.current = true; return; }
    const baseQuery = supabase
      .from('listings')
      .select('*')
      .eq('status', 'sold')
      .order('sold_at', { ascending: false })
      .limit(30);
    const { data, error } = await applyBlockedSellerFilter(baseQuery, blockedIdsRef.current);

    if (error || !data) {
      // Rows already on screen stay: a failed refresh never empties the feed (F-BIDS-1's rule).
      console.warn('[HomeScreen] sold fetch error:', error?.message ?? 'no rows returned');
      markFilterFailed('recently_sold', classifyLoadFailure(error, offlineRef.current));
      return;
    }

    const rows = data as Listing[];
    setSoldListings(rows);
    soldLoadedOnce.current = true;
    markFilterLoaded('recently_sold');

  }

  async function fetchEndedListings() {
    markFilterLoading('ended');
    if (fixture) { setEndedListings(fixture.ended ?? []); markFilterLoaded('ended'); endedLoadedOnce.current = true; return; }
    // Ended = auction_status 'ended' but not yet sold
    const baseQuery = supabase
      .from('listings')
      .select('*')
      .eq('auction_status', 'ended')
      .neq('status', 'sold')
      .order('ends_at', { ascending: false })
      .limit(30);
    const { data, error } = await applyBlockedSellerFilter(baseQuery, blockedIdsRef.current);

    if (error || !data) {
      console.warn('[HomeScreen] ended fetch error:', error?.message ?? 'no rows returned');
      markFilterFailed('ended', classifyLoadFailure(error, offlineRef.current));
      return;
    }

    const rows = data as Listing[];
    setEndedListings(rows);
    endedLoadedOnce.current = true;
    markFilterLoaded('ended');

  }

  useEffect(() => {
    fetchListings().finally(() => { setLoading(false); initialLoadDone.current = true; });
    /*
     * A HARNESS THAT STARTS ON A LAZY CHIP MUST READ THAT DATASET (B's F-91-7 at 91062ab1: the
     * sold-empty and ended-empty variants painted NOTHING below the header). The lazy datasets are
     * fetched when a selection asks for them, and a fixture that SEEDS the chip never made that
     * selection — so the dataset had no settled read, `mayShowEmptyCopy` was false, and the screen
     * correctly refused to say the marketplace was empty. The seed now performs the read the
     * selection would have performed. Nothing changes for a real session, which has no `fixture`.
     */
    if (fixture?.chip === 'recently_sold') void fetchSoldListings();
    if (fixture?.chip === 'ended') void fetchEndedListings();
  }, []);

  /*
   * THE BLOCK SET ARRIVES AFTER THE FIRST READ (A's finding, 2026-09-24). `useBlockedUserIds` starts
   * empty and answers asynchronously, and both callers above hold the first render's `fetchListings`
   * — `deps: []` and `deps: [expand]` — so nothing re-read when the real set landed. A blocked
   * seller's rows were therefore on Home on every load and every return to the tab, until a
   * pull-to-refresh, whose handler is the only one re-created each render.
   *
   * The reads now filter through `blockedIdsRef` (which the realtime handlers already used), so no
   * read can hold a stale set; and this corrects what is ALREADY on screen when the set changes,
   * without the user doing anything. It cannot loop: a fetch does not change the block set.
   */
  useEffect(() => {
    if (!initialLoadDone.current || blockedIds.size === 0) return;
    void fetchListings();
    if (soldLoadedOnce.current) void fetchSoldListings();
    if (endedLoadedOnce.current) void fetchEndedListings();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [blockedIds]);

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
    if (fixture) return; // harness: no server, no subscription
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

  // ── Sections (V3) ─────────────────────────────────────────────────────────
  // The bucket an event falls in changes once a DAY, not once a second, so the grouping is keyed
  // to local midnight rather than to the ticker — otherwise every countdown tick would rebuild
  // the whole feed. `sectionFor` normalises to the same midnight, so this is the exact basis.
  const todayStart = useMemo(() => {
    const d = new Date(now);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }, [now]);

  const { ordered, headingFor, dividerAfter } = useMemo(() => {
    const sections = groupByEventDate(filteredListings, (l) => l.event_date, todayStart);
    const flat = sections.flatMap((s) => s.items);
    // A heading belongs to the FIRST row of its section. A section whose bucket cannot be named
    // (anything already past — the whole of the sold and ended datasets) gets none.
    const heading = new Map<string, string>();
    for (const s of sections) {
      if (s.label && s.items.length > 0) heading.set(s.items[0].id, s.label);
    }
    // The §3 divider separates rows INSIDE a section. Where a heading follows, the heading and its
    // own rule are the break, and the board draws no second hairline above it.
    const divider = new Set<string>();
    for (let i = 0; i < flat.length - 1; i += 1) {
      if (!heading.has(flat[i + 1].id)) divider.add(flat[i].id);
    }
    return { ordered: flat, headingFor: heading, dividerAfter: divider };
  }, [filteredListings, todayStart]);

  function onFiltersApply(next: {
    chip: QuickChip; neighborhoods: Set<string>; categories: Set<string>; priceMin: string; priceMax: string;
  }) {
    setFilters(prev => ({ ...prev, ...next }));
    setModalOpen(false);
    // The lazy loads the removed quick row also did: sold and ended are separate datasets, fetched
    // the first time a selection asks for them.
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

  // The one control signals EVERY applied filter, so a narrowed feed never looks unnarrowed.
  const sheetCount = sheetFilterCount(filters);

  // F-HOME-1: which lazy dataset the active chip is showing, and how its last read went.
  const activeDataset: FilterDataset | null =
    filters.chip === 'recently_sold' ? 'recently_sold' : filters.chip === 'ended' ? 'ended' : null;
  const datasetState = activeDataset ? filterLoad[activeDataset] : null;
  const datasetBusy = datasetState?.loading === true && filteredListings.length === 0;
  const datasetFailure = datasetState
    ? failureSurface(filteredListings.length, datasetState.error !== null)
    : 'none';
  const retryDataset = () => {
    if (activeDataset === 'recently_sold') void fetchSoldListings();
    if (activeDataset === 'ended')         void fetchEndedListings();
  };

  const emptyCopy =
    filters.chip === 'recently_sold' ? { title: 'Nothing sold yet', body: 'Completed sales show up here.' }
    : filters.chip === 'ended'       ? { title: 'No ended auctions', body: 'Auctions that closed without a sale show up here.' }
    : activeCount > 0                ? { title: 'No matches', body: 'Try fewer filters.' }
    :                                  { title: 'Nothing live right now', body: 'Check back, or list the tickets you cannot use.' };

  return (
    <View style={s.container}>
      {/* The approved composition: this header, then the headings and rows. The one filter control
          sits on the header's line and carries the count of everything currently applied. */}
      <HomeHeader
        onSearch={() => router.push('/(tabs)/explore')}
        onFilters={() => setModalOpen(true)}
        filterCount={sheetCount}
      />

      <View style={s.feed}>
      <FlatList
        data={loading ? [] : ordered}
        keyExtractor={(item) => item.id}
        // §3: 1px divider, inset to the row gutter, drawn 10pt above the next row's top. The
        // clearance ABOVE it is the rows' own ROW_META_CLEARANCE — content-driven, never a height.
        // It is suppressed immediately before a section heading, which carries its own rule.
        ItemSeparatorComponent={({ leadingItem }: { leadingItem?: Listing }) =>
          leadingItem && !dividerAfter.has(leadingItem.id) ? null : <View style={s.divider} />
        }
        contentContainerStyle={[s.list, { paddingBottom: dockClearance }]}
        showsVerticalScrollIndicator={false}
        // The dock's own machine is the only consumer of the feed's scroll now.
        onScroll={(e) => onHomeScroll(e)}
        scrollEventThrottle={16}
        // The ticker drives every countdown on screen; without this the cells
        // memoize and the clocks freeze.
        extraData={now}
        // A realtime INSERT prepends to the feed (handler below, unchanged).
        // Anchoring the visible content means a new row lands above what the
        // user is reading instead of shoving it down by one card.
        maintainVisibleContentPosition={{ minIndexForVisible: 0 }}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={palette.brand.red}
          />
        }
        ListHeaderComponent={
          loading || datasetBusy ? <DiscoveryGridSkeleton /> :
          datasetFailure === 'inline' && datasetState?.error ? (
            <View style={s.notice} accessibilityRole="alert">
              <Text style={[textStyle('bodySm'), s.noticeText]}>
                {HOME_FILTER_REFRESH_FAILED_COPY[datasetState.error]}
              </Text>
              <Pressable onPress={retryDataset} hitSlop={8} accessibilityRole="button" accessibilityLabel="Retry loading this filter">
                <Text style={[textStyle('label'), s.noticeAction]}>Retry</Text>
              </Pressable>
            </View>
          ) : null
        }
        ListEmptyComponent={
          loading || datasetBusy ? null :
          datasetFailure === 'screen' && datasetState?.error ? (
            // The filter's own read failed with nothing to keep — say so, never "nothing sold yet".
            <ScreenState state={datasetState.error} onRetry={retryDataset} />
          ) : loadError ? (
            <ScreenState
              state={loadError}
              onRetry={() => fetchListings().finally(() => setLoading(false))}
            />
          ) : datasetState && !mayShowEmptyCopy(datasetState) ? null : (
            <EmptyState title={emptyCopy.title} body={emptyCopy.body} />
          )
        }
        renderItem={({ item, index }) => {
          const presentation = cardPresentation(item, now);
          // All-in, through the one money helper. No arithmetic here.
          // V3 (pkg8-home boards): displayed money carries cents — $132.00, not $132. Display
          // only; the underlying dollars and every calculation are unchanged.
          const priceAllIn = allInFromDollarsV3(presentation.priceDollars);
          const shared = {
            eventName: item.event_name,
            venue: item.venue,
            eventDate: item.event_date,
            eventTime: item.event_time,
            quantity: item.quantity,
            ticketType: item.ticket_type,
            coverPath: coverPath(item),
            presentation,
            bidCount: item.bid_count ?? null,
            priceAllIn,
            endsAt: item.ends_at,
            nowMs: now,
            onPress: () => {
              // Display-only handoff so the detail screen paints this card's
              // content on its first frame. The route is unchanged, and the
              // fresh row still gates every action there.
              stageCardHandoff(item.id, {
                coverPath: coverPath(item),
                eventName: item.event_name,
                venue: item.venue,
                eventDate: item.event_date,
                eventTime: item.event_time,
                neighborhood: item.neighborhood,
                priceLabel: presentation.priceLabel,
                priceAllIn,
              });
              router.push(`/listing/${item.id}`);
            },
          };
          // The first LIVE listing is the full-bleed feature. Sold/ended datasets (and a feed
          // whose first row is no longer buyable) get plain rows: a feature is a spotlight, and
          // a spotlight on something that cannot be bought reads as an offer.
          const featured =
            index === 0 && presentation.status !== 'sold' && presentation.status !== 'ended';
          const body = featured ? <HomeFeature {...shared} /> : <FeedRow {...shared} />;
          // The heading is drawn ABOVE the first item of its section — over the feature on the
          // board, over the first row of every section after it. `headingFor` is the only source.
          const heading = headingFor.get(item.id);
          if (!heading) return body;
          return (
            <View>
              <Text
                style={[textStyle('sectionLabel'), s.sectionLabel]}
                accessibilityRole="header"
                numberOfLines={1}
              >
                {heading}
              </Text>
              <View style={s.sectionRule} />
              {body}
            </View>
          );
        }}
      />

      </View>

      <FilterSheet
        visible={modalOpen}
        value={filters}
        onApply={onFiltersApply}
        onClose={() => setModalOpen(false)}
      />
    </View>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

function makeStyles(p: Palette) {
  return StyleSheet.create({
  notice: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: v2.space.sm,
    paddingBottom: v2.space.md,
  },
  noticeText: { color: p.text.muted, flexShrink: 1 },
  noticeAction: { color: p.brand.redText },
  container: { flex: 1, backgroundColor: p.surface.canvas },
  // The feed region: nothing floats over it any more, so it needs no clipping.
  feed: { flex: 1 },
  // The tab bar sits over the last row; this keeps it reachable.
  list: { paddingBottom: 96 },
  // §3 divider: 1px, inset to the 20pt row gutter, with the 10pt gap to the next row's top.
  // INK, settled: the pkg8 home boards draw it as `border.default` in both appearances — #28292D
  // on Midnight and #DFE0E4 on Daylight, sampled off the boards at 2×. It used to be the over-art
  // hairline white, which renders #1A1A1A on Midnight and was flagged as unsettled.
  divider: {
    height: 1,
    marginHorizontal: ROW_GUTTER,
    marginBottom: 10,
    backgroundColor: p.border.default,
  },
  /** V3 section heading: the `sectionLabel` token carries the voice; only layout lives here. */
  sectionLabel: {
    color: p.text.secondary,
    paddingHorizontal: ROW_GUTTER,
    marginTop: v2.space.md,
  },
  /** The board's hairline under the heading: same ink and inset as the row divider. */
  sectionRule: {
    height: 1,
    marginHorizontal: ROW_GUTTER,
    marginTop: v2.space.xs,
    marginBottom: v2.space.sm,
    backgroundColor: p.border.default,
  },
  });
}
