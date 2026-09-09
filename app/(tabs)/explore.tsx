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
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { allInFromDollars } from '@/src/lib/money';
import { applyBlockedSellerFilter, useBlockedUserIds } from '@/src/hooks/useBlockedUserIds';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import ScreenState from '@/src/components/ScreenState';
import { EmptyState, IconButton, Input } from '@/src/components/ui';
import { DiscoveryCard } from '@/src/components/discovery/DiscoveryCard';
import { DiscoveryGridSkeleton } from '@/src/components/discovery/DiscoveryGridSkeleton';
import { cardPresentation, countdownLabel } from '@/src/lib/listing/cardState';
import { useDockClearance } from '@/src/lib/nav/navInsets';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

function coverPath(listing: Listing): string | null {
  return (listing as any).cover_image_path || (listing as any).cover_image_url || null;
}

function whenLabel(date: string, time: string): string {
  const d = new Date(`${date}T${time}`);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true,
  }).replace(/,([^,]*)$/, ' ·$1');
}

/** PostgREST `or` treats these as syntax, so a raw query string cannot go in. */
function sanitize(term: string): string {
  return term.replace(/[%,()"\\]/g, ' ').trim();
}

export default function SearchScreen() {
  const insets = useSafeAreaInsets();
  const dockClearance = useDockClearance();
  const { blockedIds } = useBlockedUserIds();

  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Listing[]>([]);
  const [searching, setSearching] = useState(false);
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
      // The raw message goes to the log. The user gets a state, not a stack.
      console.warn('[search] query failed:', error.message);
      setLoadError(isNetworkError(error) ? 'offline' : 'error');
      setResults([]);
      return;
    }
    setResults((data ?? []) as Listing[]);
  }, [blockedIds]);

  // Debounced so a four-letter word is one query, not four.
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => runSearch(query), 300);
    return () => { if (timer.current) clearTimeout(timer.current); };
  }, [query, runSearch]);

  return (
    <View style={s.container}>
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
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

      {searching && results.length === 0 ? (
        <DiscoveryGridSkeleton rows={2} />
      ) : loadError ? (
        <ScreenState state={loadError} onRetry={() => runSearch(query)} />
      ) : (
        <FlatList
          data={results}
          keyExtractor={(item) => item.id}
          numColumns={2}
          columnWrapperStyle={s.column}
          contentContainerStyle={[s.list, { paddingBottom: dockClearance }]}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          showsVerticalScrollIndicator={false}
          extraData={now}
          ListEmptyComponent={
            searched ? (
              <EmptyState title="Nothing matches" body="Try the venue name, or a shorter word." />
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
            return (
              <DiscoveryCard
                eventName={item.event_name}
                venue={item.venue}
                whenLabel={whenLabel(item.event_date, item.event_time)}
                coverPath={coverPath(item)}
                presentation={presentation}
                priceAllIn={allInFromDollars(presentation.priceDollars)}
                altAllIn={presentation.altDollars != null ? allInFromDollars(presentation.altDollars) : null}
                countdown={presentation.showsCountdown ? countdownLabel(item.ends_at, now) : null}
                onPress={() => router.push(`/listing/${item.id}`)}
              />
            );
          }}
        />
      )}
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: v2.surface.canvas },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: v2.space.sm,
    paddingHorizontal: v2.space.lg,
    paddingBottom: v2.space.md,
  },
  field: { flex: 1 },
  list: { paddingTop: v2.space.md },
  column: {
    paddingHorizontal: v2.space.lg,
    gap: v2.space.lg,
    marginBottom: v2.space.xl,
  },
  hint: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.xl },
  hintText: { color: v2.text.muted },
});
