/**
 * app/(tabs)/explore.tsx — Search.
 *
 * WHAT THIS FILE WAS, AND WHY IT IS NOT DELETED
 * It was a complete, working, and completely unreachable listing browser: hidden
 * from the tab bar with `href: null` and pushed from nowhere, so no user had ever
 * seen it. Its fetch, its blocked-seller filtering and its refresh handling were
 * all sound. Rather than delete working code or write a second copy of it
 * somewhere else, that logic now backs the thing the product actually lacked:
 * there was no search anywhere in the app.
 *
 * It stays OUT of the tab bar. Navigation is not this phase's to change; Home
 * pushes here from the search control in its header.
 *
 * SEARCH RUNS AGAINST AUTHORIZED DATA ONLY — `public.listings`, the same table
 * the feed reads. There is no catalog access to search events or venues yet, so
 * this matches on the listing's own event name and venue text. When Core exposes
 * the catalog, this is the screen that grows.
 *
 * A FAILED QUERY KEEPS THE RESULTS ALREADY ON SCREEN. It used to clear them and
 * show the full error screen; now the failure is surfaced inline above the rows
 * that are still valid, and the state screen is reserved for a failure with
 * nothing to keep (src/lib/screens/refreshPolicy.ts).
 *
 * V3 (owner 2026-09-22; B's package §5 + search mockups). Presentation and client-side narrowing
 * only: results render as §3 rows; three chips narrow on columns ALREADY in the row (ticket
 * type, all-in price, delivery method — annotation ②); a "N listings · Soonest first" header
 * counts what is on screen against the order the query really uses; and the §5 empty state
 * appears only when active filters can honestly be blamed. No count of excluded listings — no
 * read returns one (§7). The mockup's "Any date" chip is not built: no spec text; flagged for B.
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { allInFromDollars } from '@/src/lib/money';
import { applyBlockedSellerFilter, useBlockedUserIds } from '@/src/hooks/useBlockedUserIds';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { classifyLoadFailure } from '@/src/lib/ui/loadState';
import ScreenState from '@/src/components/ScreenState';
import { Chip, IconButton, Input, StateView } from '@/src/components/ui';
import { DiscoveryGridSkeleton } from '@/src/components/discovery/DiscoveryGridSkeleton';
import { FeedRow } from '@/src/components/discovery/FeedRow';
import { cardPresentation } from '@/src/lib/listing/cardState';
import {
  CLEAR_ALL_LABEL,
  CLEAR_PRICE_LABEL,
  matchesSearchFilters,
  NO_SEARCH_FILTERS,
  searchEmptyState,
  searchResultsHeader,
  SORT_LABEL,
  type SearchFilters,
} from '@/src/lib/search/searchFilters';
import { stageCardHandoff } from '@/src/lib/listing/cardHandoff';
import { useDockClearance, useTopInset } from '@/src/lib/nav/navInsets';
import { failureSurface } from '@/src/lib/screens/refreshPolicy';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

function coverPath(listing: Listing): string | null {
  return (listing as any).cover_image_path || (listing as any).cover_image_url || null;
}

/** PostgREST `or` treats these as syntax, so a raw query string cannot go in. */
function sanitize(term: string): string {
  return term.replace(/[%,()"\\]/g, ' ').trim();
}

/**
 * A failed query over results that are still valid. Inline, above the rows, with
 * the same two states ScreenState distinguishes. Never carries server text.
 */
function SearchFailureNotice({ s, kind, onRetry }: { s: Styles; kind: 'offline' | 'error'; onRetry: () => void }) {
  return (
    <View style={s.notice} accessibilityRole="alert">
      <Text style={[textStyle('bodySm'), s.noticeText]}>
        {kind === 'offline'
          ? "You're offline. Showing earlier results."
          : 'Search did not go through. Showing earlier results.'}
      </Text>
      <Pressable onPress={onRetry} hitSlop={8} accessibilityRole="button" accessibilityLabel="Retry search">
        <Text style={[textStyle('label'), s.noticeAction]}>Retry</Text>
      </Pressable>
    </View>
  );
}

export default function SearchScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const topPad = useTopInset();
  const dockClearance = useDockClearance();
  const { blockedIds } = useBlockedUserIds();

  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Listing[]>([]);
  const [filters, setFilters] = useState<SearchFilters>(NO_SEARCH_FILTERS);
  const [searching, setSearching] = useState(false);
  const { isOffline } = useNetworkStatus();
  const offlineRef = useRef(false);
  offlineRef.current = isOffline;
  const [loadError, setLoadError] = useState<'offline' | 'error' | null>(null);
  const [now, setNow] = useState(() => Date.now());
  const [searched, setSearched] = useState(false);

  // One shared clock for every countdown on screen, as on Home.
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  const runSearch = useCallback(async (term: string) => {
    const clean = sanitize(term);
    if (clean.length < 2) {
      setResults([]);
      setSearched(false);
      setLoadError(null);
      return;
    }

    setSearching(true);
    setLoadError(null);

    const base = supabase
      .from('listings')
      .select('*')
      .eq('status', 'active')
      .eq('auction_status', 'active')
      .or(`event_name.ilike.%${clean}%,venue.ilike.%${clean}%`)
      .order('ends_at', { ascending: true })
      .limit(40);

    const { data, error } = await applyBlockedSellerFilter(base, blockedIds);

    setSearching(false);
    setSearched(true);

    if (error) {
      // The raw message goes to the log. The user gets a state, not a stack —
      // and keeps the results already on screen. Nothing is cleared here.
      console.warn('[search] query failed:', error.message);
      setLoadError(classifyLoadFailure(error, offlineRef.current));
      return;
    }
    setResults((data ?? []) as Listing[]);
  }, [blockedIds]);

  // A failure takes over the screen only when there is nothing to keep on it. Keyed on the RAW
  // results: rows hidden by a chip are kept data, not a loss.
  const failure = failureSurface(results.length, loadError != null);

  // Client-side narrowing of rows already fetched — no second query, no excluded count.
  const shown = results.filter((r) => matchesSearchFilters(r as never, filters, now));

  // Debounced so a four-letter word is one query, not four.
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => runSearch(query), 300);
    return () => { if (timer.current) clearTimeout(timer.current); };
  }, [query, runSearch]);

  return (
    <View style={s.container}>
      <View style={[s.header, { paddingTop: topPad + v2.space.sm }]}>
        <IconButton glyph="back" accessibilityLabel="Go back" onPress={() => router.back()} />
        <View style={s.field}>
          <Input
            label="Search"
            value={query}
            onChangeText={setQuery}
            placeholder="Event or venue"
            autoFocus
            autoCorrect={false}
            autoCapitalize="none"
            returnKeyType="search"
            accessibilityHint="Searches live listings by event name and venue"
          />
        </View>
      </View>

      {/* The three real-column chips (annotation ②). "Any date" is deliberately absent. */}
      <View style={s.chips}>
        <Chip
          label="GA"
          selected={filters.ga}
          onPress={() => setFilters((f) => ({ ...f, ga: !f.ga }))}
        />
        <Chip
          label={'Under $150'}
          selected={filters.under150}
          onPress={() => setFilters((f) => ({ ...f, under150: !f.under150 }))}
        />
        <Chip
          label={'Mobile transfer'}
          selected={filters.mobileTransfer}
          onPress={() => setFilters((f) => ({ ...f, mobileTransfer: !f.mobileTransfer }))}
        />
      </View>

      {searching && results.length === 0 ? (
        <DiscoveryGridSkeleton rows={2} />
      ) : failure === 'screen' && loadError ? (
        <ScreenState state={loadError} onRetry={() => runSearch(query)} />
      ) : (
        <FlatList
          data={shown}
          keyExtractor={(item) => item.id}
          ItemSeparatorComponent={() => <View style={s.divider} />}
          contentContainerStyle={[s.list, { paddingBottom: dockClearance }]}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          showsVerticalScrollIndicator={false}
          extraData={now}
          ListHeaderComponent={
            <>
              {failure === 'inline' && loadError ? (
                <SearchFailureNotice s={s} kind={loadError} onRetry={() => runSearch(query)} />
              ) : null}
              {shown.length > 0 ? (
                // "2 listings · Soonest first": a count of what is ON SCREEN, and a sort label
                // that matches the query's real `ends_at` ascending order.
                <View style={s.resultsHeader}>
                  <Text style={[textStyle('label'), s.resultsCount]}>
                    {searchResultsHeader(shown.length)}
                  </Text>
                  <Text style={[textStyle('bodySm'), s.resultsSort]}>{SORT_LABEL}</Text>
                </View>
              ) : null}
            </>
          }
          ListEmptyComponent={
            searched ? (
              (() => {
                const empty = searchEmptyState(query.trim(), filters);
                return empty ? (
                  <View style={s.emptyWrap}>
                    <Text style={[textStyle('nameState'), s.emptyTitle]}>{empty.title}</Text>
                    <Text style={[textStyle('bodySm'), s.emptyBody]}>{empty.body}</Text>
                    <View style={s.emptyActions}>
                      {empty.clearPrice ? (
                        <Chip
                          label={CLEAR_PRICE_LABEL}
                          onPress={() => setFilters((f) => ({ ...f, under150: false }))}
                        />
                      ) : null}
                      <Chip label={CLEAR_ALL_LABEL} onPress={() => setFilters(NO_SEARCH_FILTERS)} />
                    </View>
                  </View>
                ) : (
                  <StateView kind="noMatch" />
                );
              })()
            ) : (
              <View style={s.hint}>
                <Text style={[textStyle('bodySm'), s.hintText]}>
                  Search live listings by event or venue.
                </Text>
              </View>
            )
          }
          renderItem={({ item }) => {
            const presentation = cardPresentation(item, now);
            const priceAllIn = allInFromDollars(presentation.priceDollars);
            return (
              <FeedRow
                eventName={item.event_name}
                venue={item.venue}
                eventDate={item.event_date}
                eventTime={item.event_time}
                quantity={item.quantity}
                ticketType={item.ticket_type}
                coverPath={coverPath(item)}
                presentation={presentation}
                bidCount={item.bid_count ?? null}
                priceAllIn={priceAllIn}
                endsAt={item.ends_at}
                nowMs={now}
                onPress={() => {
                  // Display-only handoff, as on Home: the detail screen paints
                  // this card's content first; the fresh row still gates every action.
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
                }}
              />
            );
          }}
        />
      )}
    </View>
  );
}

type Styles = ReturnType<typeof makeStyles>;

function makeStyles(p: Palette) {
  return StyleSheet.create({
  container: { flex: 1, backgroundColor: p.surface.canvas },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: v2.space.sm,
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.md,
  },
  field: { flex: 1 },
  list: { paddingTop: v2.space.md },
  chips: {
    flexDirection: 'row',
    gap: v2.space.sm,
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.sm,
    alignItems: 'center',
  },
  // §3 row divider — same drawing as Home's.
  divider: {
    height: 1,
    marginHorizontal: 20,
    marginBottom: 10,
    backgroundColor: p.border.overArt,
  },
  resultsHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.md,
  },
  resultsCount: { color: p.text.primary },
  resultsSort: { color: p.text.muted },
  // §5 empty state: the heading wraps inside the column, left on the same 20pt gutter.
  emptyWrap: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.xl, gap: v2.space.sm },
  emptyTitle: { color: p.text.primary },
  emptyBody: { color: p.text.muted },
  emptyActions: { flexDirection: 'row', gap: v2.space.sm, paddingTop: v2.space.lg },
  hint: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.xl },
  hintText: { color: p.text.muted },
  notice: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: v2.space.sm,
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.md,
  },
  noticeText: { color: p.text.muted, flexShrink: 1 },
  noticeAction: { color: p.brand.redText },
  });
}
