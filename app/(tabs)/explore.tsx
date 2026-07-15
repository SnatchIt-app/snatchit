/**
 * app/(tabs)/explore.tsx — Explore / Search listings
 *
 * Hidden from the tab bar (href: null) but accessible via router.push.
 * Fetches all active listings with loading, empty, and error states.
 */

import { router } from 'expo-router';
import { Image } from 'expo-image';
import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { resolveCoverUrls } from '@/src/lib/coverImage';
import { allInLabel } from '@/src/lib/money';
import { applyBlockedSellerFilter, useBlockedUserIds } from '@/src/hooks/useBlockedUserIds';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { Listing } from '@/src/types';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function imagePath(listing: Listing): string | null {
  return (listing as any).cover_image_path
      || (listing as any).cover_image_url
      || null;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

export default function ExploreScreen() {
  const [listings,   setListings]   = useState<Listing[]>([]);
  const [coverUrls,  setCoverUrls]  = useState<Map<string, string | null>>(new Map());
  const [loading,    setLoading]    = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error,      setError]      = useState<string | null>(null);

  // UGC moderation: hide listings from sellers the caller has blocked.
  const { blockedIds } = useBlockedUserIds();

  const fetchListings = useCallback(async () => {
    try {
      setError(null);

      const baseQuery = supabase
        .from('listings')
        .select('*')
        .eq('auction_status', 'active')
        .order('created_at', { ascending: false })
        .limit(50);
      const { data, error: fetchErr } = await applyBlockedSellerFilter(
        baseQuery,
        blockedIds,
      );

      if (fetchErr) {
        setError("Couldn't load listings. Pull to refresh.");
        console.warn('[ExploreScreen] fetch error:', fetchErr.message);
        return;
      }

      const rows = (data ?? []) as Listing[];
      setListings(rows);

      const paths  = rows.map(r => imagePath(r));
      const urlMap = await resolveCoverUrls(paths);
      setCoverUrls(prev => new Map([...prev, ...urlMap]));
    } catch (err) {
      console.warn('[ExploreScreen] unexpected error:', err);
      setError("Couldn't load listings. Pull to refresh.");
    }
  }, [blockedIds]);

  useEffect(() => {
    fetchListings().finally(() => setLoading(false));
  }, [fetchListings]);

  async function onRefresh() {
    setRefreshing(true);
    await fetchListings();
    setRefreshing(false);
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  return (
    <View style={s.container}>
      <View style={s.header}>
        <Text style={s.title}>Explore</Text>
        <Text style={s.subtitle}>Browse active listings</Text>
      </View>

      {loading ? (
        <View style={s.centered}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      ) : error ? (
        <View style={s.centered}>
          <Text style={s.errorIcon}>⚠️</Text>
          <Text style={s.errorText}>{error}</Text>
          <Pressable style={s.retryBtn} onPress={() => { setLoading(true); fetchListings().finally(() => setLoading(false)); }}>
            <Text style={s.retryBtnText}>Try Again</Text>
          </Pressable>
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
            <View style={s.centered}>
              <Text style={s.emptyIcon}>🔍</Text>
              <Text style={s.emptyTitle}>No listings found</Text>
              <Text style={s.emptyText}>
                There are no active listings right now. Pull to refresh or check back later.
              </Text>
            </View>
          }
          renderItem={({ item }) => {
            const cover = coverUrls.get(imagePath(item) ?? '') ?? null;
            return (
              <Pressable
                style={s.card}
                onPress={() => router.push(`/listing/${item.id}`)}
                android_ripple={{ color: colors.primarySoft }}
              >
                {cover ? (
                  <Image source={{ uri: cover }} style={s.thumb} contentFit="cover" />
                ) : (
                  <View style={[s.thumb, s.thumbPlaceholder]}>
                    <Text style={s.thumbEmoji}>🎟️</Text>
                  </View>
                )}
                <View style={s.cardBody}>
                  <Text style={s.cardEvent} numberOfLines={1}>{item.event_name}</Text>
                  <Text style={s.cardVenue} numberOfLines={1}>
                    {item.venue} · {item.neighborhood?.replace(/\b\w/g, c => c.toUpperCase())}
                  </Text>
                  {/* All-in pricing: first displayed price includes the 10% service fee. */}
                  <Text style={s.cardBid}>{allInLabel(item.current_bid)}</Text>
                </View>
              </Pressable>
            );
          }}
        />
      )}
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
  title:    { fontSize: 28, fontWeight: '900', color: colors.text, letterSpacing: 1 },
  subtitle: { fontSize: fontSize.sm, color: colors.textMuted, marginTop: 2 },

  centered: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl, gap: spacing.md },

  list: { padding: spacing.md, paddingBottom: 120 },

  // Error state
  errorIcon: { fontSize: 48 },
  errorText: { fontSize: fontSize.sm, color: colors.textMuted, textAlign: 'center' },
  retryBtn:     { backgroundColor: colors.primary, borderRadius: radius.md, paddingHorizontal: spacing.xl, paddingVertical: spacing.sm },
  retryBtnText: { color: colors.text, fontWeight: '700', fontSize: fontSize.sm },

  // Empty state
  emptyIcon:  { fontSize: 48 },
  emptyTitle: { fontSize: fontSize.lg, fontWeight: '700', color: colors.text },
  emptyText:  { fontSize: fontSize.sm, color: colors.textMuted, textAlign: 'center', lineHeight: 20 },

  // Cards — compact horizontal rows
  card: {
    flexDirection: 'row',
    backgroundColor: colors.bgCard,
    borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.border,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  thumb:            { width: 64, height: 64, borderRadius: radius.sm },
  thumbPlaceholder: { backgroundColor: colors.bgInput, alignItems: 'center', justifyContent: 'center' },
  thumbEmoji:       { fontSize: 24 },
  cardBody:  { flex: 1, marginLeft: spacing.md, justifyContent: 'center' },
  cardEvent: { fontSize: fontSize.sm, fontWeight: '700', color: colors.text, marginBottom: 2 },
  cardVenue: { fontSize: fontSize.xs, color: colors.textMuted, marginBottom: 4 },
  cardBid:   { fontSize: fontSize.sm, fontWeight: '800', color: colors.primary },
});
