/**
 * app/saved.tsx — Saved listings (saved-listings; checklist items 11 and 53).
 *
 * The signed-in user's saved listings, newest save first, as §3 rows — the same row, presentation and
 * price rules as Search, so a saved listing reads exactly as it does everywhere else. Tapping a row
 * opens the listing; saving and removing happen on the listing itself (the bookmark beside its back
 * control). One in-memory state is shared with that control, so a listing removed there leaves this
 * list at once, and coming back here re-reads quietly.
 *
 * ONE READ: public.saved_listings (migration 040; RLS owner select) with the listing embedded by
 * PostgREST. A saved row whose listing this viewer cannot read comes back with a NULL embed —
 * migration 154 deliberately gives savers no visibility (pgTAP 221 E1/E2) — so those rows are COUNTED
 * ("N saved listings no longer available.") and never explained: the read cannot tell hidden, ended
 * or sold apart, so this screen does not guess.
 *
 * FOUR DIFFERENT SCREENS, never one for all (the owner's "no data versus failed lookup" rule):
 * signed out (a sign-in prompt — this route sits outside the tabs, so the root guard does not send a
 * signed-out deep link to login), a failed first read (offline or error, with Retry), genuinely empty
 * (its own words and a way to browse), and the list. A failed QUIET refresh keeps the rows already on
 * screen and says so above them (F-BIDS-1).
 *
 * "Browse live listings" goes back to the tabs already underneath (dismissTo), never a second copy of
 * them: a NAVIGATE from this root-Stack route to '(tabs)' pushes a new tabs navigator.
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

import { useAuth } from '@/src/hooks/useAuth';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import ScreenState from '@/src/components/ScreenState';
import { DiscoveryGridSkeleton } from '@/src/components/discovery/DiscoveryGridSkeleton';
import { FeedRow } from '@/src/components/discovery/FeedRow';
import { EmptyState } from '@/src/components/ui';
import { cardPresentation } from '@/src/lib/listing/cardState';
import { stageCardHandoff } from '@/src/lib/listing/cardHandoff';
import { allInFromDollarsV3 } from '@/src/lib/money';
import { classifyLoadFailure } from '@/src/lib/ui/loadState';
import { readSavedList, watchSavedSignOut } from '@/src/lib/saved/savedListings';
import { SAVED_COPY, savedView, type SavedLoad, type SavedRow } from '@/src/lib/saved/savedState';
import { bindSavedOwner, primeSavedList, savedShownFor, subscribeSaved } from '@/src/lib/saved/savedStore';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

/** The stored cover value, with the legacy URL column as Home and Search fall back to it. */
function coverPath(listing: Listing): string | null {
  return listing.cover_image_path || (listing as Listing & { cover_image_url?: string | null }).cover_image_url || null;
}

export default function SavedScreen() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { user, loading: authLoading } = useAuth();
  const userId = user?.id ?? null;
  const { isOffline } = useNetworkStatus();
  const offlineRef = useRef(isOffline);
  useEffect(() => { offlineRef.current = isOffline; }, [isOffline]);

  const [load, setLoad] = useState<SavedLoad>({ phase: 'loading' });
  const [refreshing, setRefreshing] = useState(false);
  const [now, setNow] = useState(() => Date.now());
  const [, setVersion] = useState(0);
  // Only the newest read may write the screen (a slow first read must not land over a refresh).
  const requestRef = useRef(0);
  // The account whose first read has finished; focus re-reads only after it.
  const loadedFor = useRef<string | null>(null);

  useEffect(() => { watchSavedSignOut(); }, []);
  useEffect(() => subscribeSaved(() => setVersion((v) => v + 1)), []);
  // Row clocks ("2h left") stay true while the screen is open, as on Search.
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);
  useEffect(() => {
    if (!authLoading) bindSavedOwner(userId);
  }, [authLoading, userId]);

  const fetchSaved = useCallback(async () => {
    if (!userId) return;
    const request = ++requestRef.current;
    const result = await readSavedList(userId);
    if (request !== requestRef.current) return;
    if (result.ok) {
      primeSavedList(userId, result.savedIds);
      setLoad({ phase: 'ready', rows: result.rows, unavailableCount: result.unavailableCount, refreshFailure: null });
      return;
    }
    const failure = classifyLoadFailure(result.error, offlineRef.current);
    // Rows already shown stay; only a first read with nothing to keep becomes the failure screen.
    setLoad((prev) => (prev.phase === 'ready' ? { ...prev, refreshFailure: failure } : { phase: 'failed', failure }));
  }, [userId]);

  // The first read, and again from scratch for a different account.
  useEffect(() => {
    if (authLoading) return;
    loadedFor.current = null;
    setLoad({ phase: 'loading' });
    if (!userId) return;
    fetchSaved().finally(() => { loadedFor.current = userId; });
  }, [authLoading, userId, fetchSaved]);

  // Back on this screen (from a listing, say): re-read quietly.
  useFocusEffect(
    useCallback(() => {
      if (!userId || loadedFor.current !== userId) return;
      fetchSaved();
    }, [fetchSaved, userId]),
  );

  async function onRefresh() {
    setRefreshing(true);
    await fetchSaved();
    setRefreshing(false);
  }

  const view = savedView({
    authLoading,
    userId,
    load,
    isUnsaved: (listingId) => savedShownFor(userId, listingId) === false,
  });

  function renderRow(row: SavedRow) {
    const item = row.listing;
    const presentation = cardPresentation(item, now);
    const priceAllIn = allInFromDollarsV3(presentation.priceDollars);
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
          // Display-only handoff, as on Home and Search: the detail screen paints this row's content
          // first; the fresh row still gates every action there.
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
  }

  return (
    <View style={s.root}>
      <SettingsHeader title={SAVED_COPY.screenTitle} />
      {view.kind === 'auth-loading' || view.kind === 'loading' ? (
        <DiscoveryGridSkeleton rows={3} shape="rows" />
      ) : view.kind === 'signed-out' ? (
        <EmptyState
          title={SAVED_COPY.signedOutTitle}
          body={SAVED_COPY.signedOutBody}
          action={{ label: SAVED_COPY.signedOutAction, onPress: () => router.replace('/(auth)/login') }}
        />
      ) : view.kind === 'failed' ? (
        <ScreenState state={view.failure} onRetry={fetchSaved} />
      ) : view.kind === 'empty' ? (
        <EmptyState
          title={SAVED_COPY.emptyTitle}
          body={SAVED_COPY.emptyBody}
          action={{ label: SAVED_COPY.emptyAction, onPress: () => router.dismissTo('/(tabs)/home') }}
        />
      ) : (
        <FlatList
          data={view.rows}
          keyExtractor={(row) => row.id}
          extraData={now}
          ItemSeparatorComponent={() => <View style={s.divider} />}
          contentContainerStyle={s.list}
          showsVerticalScrollIndicator={false}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={palette.brand.red} />}
          ListHeaderComponent={
            view.refreshNote ? (
              <Text style={[textStyle('bodySm'), s.notice]} accessibilityRole="alert">{view.refreshNote}</Text>
            ) : null
          }
          ListFooterComponent={
            view.unavailableLine ? (
              <Text style={[textStyle('bodySm'), s.unavailable]}>{view.unavailableLine}</Text>
            ) : null
          }
          renderItem={({ item }) => renderRow(item)}
        />
      )}
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },
  list: { paddingTop: v2.space.md, paddingBottom: 96 },
  // §3 row divider — the same drawing as Home's and Search's.
  divider: {
    height: 1,
    marginHorizontal: 20,
    marginBottom: 10,
    backgroundColor: p.border.default,
  },
  notice: { color: p.text.muted, paddingHorizontal: v2.space.lg, paddingBottom: v2.space.md },
  unavailable: { color: p.text.muted, paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg },
  });
}
