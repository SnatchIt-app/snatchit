/**
 * app/profile/[id].tsx — Public seller / community profile (trust surface)
 *
 * Reached by tapping a seller's name/avatar from the listing-detail screen.
 *
 * Shows ONLY profile-safe, public information:
 *   • avatar (or initials fallback)
 *   • display name
 *   • "Verified Seller" badge when stripe_onboarding_complete = true
 *   • bio
 *   • member since (created_at)
 *   • completed sales count (listings sold by this seller)
 *   • active listings by this seller (tappable cards)
 *   • Report User / Block User (App Store Guideline 1.2)
 *
 * NEVER surfaces email, phone, Stripe IDs, wallet balance, or any payment data.
 *
 * Blocking:
 *   • If the viewer has blocked this seller, the profile renders a "blocked"
 *     state and hides all listings.
 *   • The Block action inserts into public.user_blocks and routes back; the
 *     home/explore feeds drop the seller's listings on next focus
 *     (see useBlockedUserIds).
 */

import { Image } from 'expo-image';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  ActionSheetIOS,
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

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { getAvatarUrl } from '@/src/lib/avatarImage';
import { getCoverImageUrl } from '@/src/lib/coverImage';
import VerifiedSellerBadge from '@/src/components/VerifiedSellerBadge';
import { colors, fontSize, radius, shadow, spacing } from '@/src/theme';
import type { Listing } from '@/src/types';

// ─── Types ─────────────────────────────────────────────────────────────────

type PublicProfile = {
  id:                         string;
  display_name:               string | null;
  avatar_url:                 string | null;
  avatar_path:                string | null;
  bio:                        string | null;
  created_at:                 string | null;
  is_verified_seller:         boolean;
  stripe_onboarding_complete: boolean;
};

// ─── Helpers ───────────────────────────────────────────────────────────────

function getInitials(name: string | null): string {
  if (!name || !name.trim()) return '?';
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map(w => w[0]?.toUpperCase() ?? '')
    .join('');
}

function memberSince(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
}

function fmt$(n: number | null | undefined): string {
  if (n == null) return '$0';
  return `$${Math.round(n).toLocaleString('en-US')}`;
}

// ─── Active-listing card (compact, tappable) ────────────────────────────────

function ActiveListingRow({ listing }: { listing: Listing }) {
  const coverUrl = getCoverImageUrl(
    listing.cover_image_path ?? (listing as any).cover_image_url ?? null,
  );
  return (
    <Pressable
      style={s.listingRow}
      onPress={() => router.push(`/listing/${listing.id}`)}
      android_ripple={{ color: colors.primarySoft }}
    >
      {coverUrl ? (
        <Image source={{ uri: coverUrl }} style={s.listingThumb} contentFit="cover" />
      ) : (
        <View style={[s.listingThumb, s.listingThumbPlaceholder]}>
          <Text style={s.listingThumbEmoji}>🎟️</Text>
        </View>
      )}
      <View style={s.listingInfo}>
        <Text style={s.listingName} numberOfLines={1}>{listing.event_name}</Text>
        <Text style={s.listingVenue} numberOfLines={1}>
          {listing.venue}
          {listing.neighborhood ? ` · ${listing.neighborhood.replace(/\b\w/g, c => c.toUpperCase())}` : ''}
        </Text>
      </View>
      <View style={s.listingRight}>
        <Text style={s.listingBidLabel}>Current bid</Text>
        <Text style={s.listingBid}>{fmt$(listing.current_bid)}</Text>
      </View>
    </Pressable>
  );
}

// ─── Screen ────────────────────────────────────────────────────────────────

export default function PublicProfileScreen() {
  const { user } = useAuth();
  const { id } = useLocalSearchParams<{ id: string }>();
  const sellerId = id ?? '';

  const isSelf = !!user?.id && user.id === sellerId;

  const [loading,      setLoading]      = useState(true);
  const [profile,      setProfile]      = useState<PublicProfile | null>(null);
  const [avatarUrl,    setAvatarUrl]    = useState<string | null>(null);
  const [salesCount,   setSalesCount]   = useState(0);
  const [activeListings, setActiveListings] = useState<Listing[]>([]);
  const [isBlocked,    setIsBlocked]    = useState(false);
  const [working,      setWorking]      = useState(false);

  const load = useCallback(async () => {
    if (!sellerId) { setLoading(false); return; }
    setLoading(true);

    // 1. Whether the current viewer has blocked this seller.
    let blocked = false;
    if (user?.id && !isSelf) {
      const { data: blockRow } = await supabase
        .from('user_blocks')
        .select('blocked_id')
        .eq('blocker_id', user.id)
        .eq('blocked_id', sellerId)
        .maybeSingle();
      blocked = !!blockRow;
    }
    setIsBlocked(blocked);

    // 2. Profile (safe columns only — never select phone/stripe/wallet).
    const { data: p } = await supabase
      .from('profiles')
      .select('id, display_name, avatar_url, avatar_path, bio, created_at, is_verified_seller, stripe_onboarding_complete')
      .eq('id', sellerId)
      .maybeSingle();

    if (p) {
      const prof = p as PublicProfile;
      setProfile(prof);
      setAvatarUrl(getAvatarUrl(prof.avatar_path ?? prof.avatar_url));
    } else {
      setProfile(null);
    }

    // If blocked, skip loading the seller's listings entirely.
    if (blocked) {
      setSalesCount(0);
      setActiveListings([]);
      setLoading(false);
      return;
    }

    // 3. Completed sales count — listings this seller has sold.
    const { count } = await supabase
      .from('listings')
      .select('id', { count: 'exact', head: true })
      .eq('seller_id', sellerId)
      .eq('status', 'sold');
    setSalesCount(count ?? 0);

    // 4. Active listings by this seller.
    const { data: actives } = await supabase
      .from('listings')
      .select('*')
      .eq('seller_id', sellerId)
      .eq('status', 'active')
      .eq('auction_status', 'active')
      .order('ends_at', { ascending: true });
    setActiveListings((actives as Listing[]) ?? []);

    setLoading(false);
  }, [sellerId, user?.id, isSelf]);

  useEffect(() => { load(); }, [load]);

  // ── Report ────────────────────────────────────────────────────────────────
  function handleReport() {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    router.push(`/report/user/${sellerId}` as any);
  }

  // ── Block / Unblock ─────────────────────────────────────────────────────────
  function handleBlock() {
    if (!user?.id) {
      Alert.alert('Sign in required', 'You need to be signed in to block users.');
      return;
    }
    const name = profile?.display_name?.trim() || 'this seller';
    Alert.alert(
      `Block ${name}?`,
      'Their listings will be hidden from your feed. You can unblock anytime in Settings → Blocked Users.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Block',
          style: 'destructive',
          onPress: async () => {
            setWorking(true);
            const { error } = await supabase.from('user_blocks').insert({
              blocker_id: user.id,
              blocked_id: sellerId,
            });
            setWorking(false);
            // 23505 = unique_violation → already blocked. Treat as success.
            if (error && error.code !== '23505') {
              Alert.alert('Could not block', error.message);
              return;
            }
            Alert.alert(
              'Blocked',
              `${name} is hidden from your feed.`,
              [{ text: 'OK', onPress: () => router.back() }],
            );
          },
        },
      ],
    );
  }

  async function handleUnblock() {
    if (!user?.id) return;
    setWorking(true);
    const { error } = await supabase
      .from('user_blocks')
      .delete()
      .eq('blocker_id', user.id)
      .eq('blocked_id', sellerId);
    setWorking(false);
    if (error) {
      Alert.alert('Could not unblock', error.message);
      return;
    }
    setIsBlocked(false);
    load();
  }

  function openActions() {
    const actions: { label: string; destructive?: boolean; handler: () => void }[] = [
      { label: 'Report this user', handler: handleReport },
      isBlocked
        ? { label: 'Unblock user', handler: handleUnblock }
        : { label: 'Block user', destructive: true, handler: handleBlock },
    ];

    if (Platform.OS === 'ios') {
      ActionSheetIOS.showActionSheetWithOptions(
        {
          options: [...actions.map(a => a.label), 'Cancel'],
          cancelButtonIndex: actions.length,
          destructiveButtonIndex: actions.findIndex(a => a.destructive),
        },
        (idx) => { if (idx >= 0 && idx < actions.length) actions[idx].handler(); },
      );
    } else {
      Alert.alert('Actions', '', [
        ...actions.map(a => ({
          text: a.label,
          onPress: a.handler,
          style: (a.destructive ? 'destructive' : 'default') as 'destructive' | 'default',
        })),
        { text: 'Cancel', style: 'cancel' as const },
      ]);
    }
  }

  // ── Header bar (shared) ──────────────────────────────────────────────────
  const TopBar = (
    <View style={s.topBar}>
      <Pressable onPress={() => router.back()} style={s.iconBtn} hitSlop={8}>
        <Text style={s.backArrow}>←</Text>
      </Pressable>
      <Text style={s.topTitle}>Profile</Text>
      {!isSelf ? (
        <Pressable
          onPress={openActions}
          style={s.iconBtn}
          hitSlop={8}
          accessibilityRole="button"
          accessibilityLabel="More actions"
        >
          <Text style={s.backArrow}>{'⋯'}</Text>
        </Pressable>
      ) : (
        <View style={s.iconBtn} />
      )}
    </View>
  );

  // ── Loading ──────────────────────────────────────────────────────────────
  if (loading) {
    return (
      <SafeAreaView style={s.safe}>
        {TopBar}
        <View style={s.centered}>
          <ActivityIndicator color={colors.primary} size="large" />
        </View>
      </SafeAreaView>
    );
  }

  // ── Not found ────────────────────────────────────────────────────────────
  if (!profile) {
    return (
      <SafeAreaView style={s.safe}>
        {TopBar}
        <View style={s.centered}>
          <Text style={s.emptyText}>This profile isn’t available.</Text>
        </View>
      </SafeAreaView>
    );
  }

  const displayName = profile.display_name?.trim() || 'Seller';
  const verified    = profile.stripe_onboarding_complete === true;

  // ── Blocked state ────────────────────────────────────────────────────────
  if (isBlocked) {
    return (
      <SafeAreaView style={s.safe}>
        {TopBar}
        <View style={s.centered}>
          <View style={s.avatarRing}>
            <View style={s.avatarFallback}>
              <Text style={s.avatarInitials}>{getInitials(displayName)}</Text>
            </View>
          </View>
          <Text style={s.blockedTitle}>You’ve blocked {displayName}</Text>
          <Text style={s.blockedBody}>
            Their listings are hidden from your feed. Unblock to see this profile again.
          </Text>
          <TouchableOpacity
            style={s.unblockBtn}
            onPress={handleUnblock}
            disabled={working}
            activeOpacity={0.85}
          >
            {working
              ? <ActivityIndicator color={colors.text} size="small" />
              : <Text style={s.unblockBtnText}>Unblock</Text>}
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  // ── Normal profile ───────────────────────────────────────────────────────
  return (
    <SafeAreaView style={s.safe}>
      {TopBar}
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{ paddingBottom: spacing.xxl }}
      >
        {/* Header card */}
        <View style={s.header}>
          <View style={s.avatarRing}>
            {avatarUrl ? (
              <Image source={{ uri: avatarUrl }} style={s.avatarImage} contentFit="cover" />
            ) : (
              <View style={s.avatarFallback}>
                <Text style={s.avatarInitials}>{getInitials(displayName)}</Text>
              </View>
            )}
          </View>

          <Text style={s.name}>{displayName}</Text>

          {verified && (
            <View style={s.badgeWrap}>
              <VerifiedSellerBadge isVerified={true} />
            </View>
          )}

          {profile.bio ? <Text style={s.bio}>{profile.bio}</Text> : null}
        </View>

        {/* Stats */}
        <View style={s.statsRow}>
          <View style={s.statBox}>
            <Text style={s.statValue}>{salesCount}</Text>
            <Text style={s.statLabel}>Completed sales</Text>
          </View>
          <View style={s.statDivider} />
          <View style={s.statBox}>
            <Text style={s.statValue}>{memberSince(profile.created_at)}</Text>
            <Text style={s.statLabel}>Member since</Text>
          </View>
        </View>

        {/* Active listings */}
        <Text style={s.sectionHead}>ACTIVE LISTINGS ({activeListings.length})</Text>
        <View style={s.section}>
          {activeListings.length === 0 ? (
            <Text style={s.emptyListings}>No active listings right now.</Text>
          ) : (
            activeListings.map(l => <ActiveListingRow key={l.id} listing={l} />)
          )}
        </View>

        {/* Safety actions — hidden on your own profile */}
        {!isSelf && (
          <View style={s.actionsWrap}>
            <TouchableOpacity style={s.actionBtn} onPress={handleReport} activeOpacity={0.8}>
              <Text style={s.actionBtnText}>Report User</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[s.actionBtn, s.blockBtn]}
              onPress={handleBlock}
              disabled={working}
              activeOpacity={0.8}
            >
              <Text style={[s.actionBtnText, s.blockBtnText]}>Block User</Text>
            </TouchableOpacity>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

// ─── Styles ──────────────────────────────────────────────────────────────────

const AVATAR_SIZE = 88;
const RING_SIZE   = AVATAR_SIZE + 8;

const s = StyleSheet.create({
  safe:     { flex: 1, backgroundColor: colors.bg },
  centered: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl, gap: spacing.md },

  // Top bar
  topBar: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    borderBottomWidth: 1, borderBottomColor: colors.border,
  },
  iconBtn:   { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  backArrow: { color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle:  { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  // Header
  header:      { alignItems: 'center', paddingTop: spacing.xl, paddingHorizontal: spacing.lg },
  avatarRing: {
    width: RING_SIZE, height: RING_SIZE, borderRadius: RING_SIZE / 2,
    borderWidth: 2, borderColor: colors.primary,
    alignItems: 'center', justifyContent: 'center',
    shadowColor: colors.primary, shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5, shadowRadius: 12, elevation: 8,
  },
  avatarImage:    { width: AVATAR_SIZE, height: AVATAR_SIZE, borderRadius: AVATAR_SIZE / 2 },
  avatarFallback: {
    width: AVATAR_SIZE, height: AVATAR_SIZE, borderRadius: AVATAR_SIZE / 2,
    backgroundColor: colors.primarySoft, alignItems: 'center', justifyContent: 'center',
  },
  avatarInitials: { fontSize: fontSize.xl, fontWeight: '800', color: colors.primary },

  name:     { color: colors.text, fontSize: fontSize.lg, fontWeight: '800', marginTop: spacing.md },
  badgeWrap:{ marginTop: spacing.xs },
  bio:      { color: colors.textMuted, fontSize: fontSize.sm, lineHeight: 20,
              textAlign: 'center', marginTop: spacing.md },

  // Stats
  statsRow: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.bgCard, borderRadius: radius.lg,
    borderWidth: 1, borderColor: colors.border,
    marginHorizontal: spacing.lg, marginTop: spacing.lg,
    paddingVertical: spacing.md, ...shadow.card,
  },
  statBox:     { flex: 1, alignItems: 'center', gap: 2 },
  statDivider: { width: 1, alignSelf: 'stretch', backgroundColor: colors.border, marginVertical: spacing.xs },
  statValue:   { color: colors.text, fontSize: fontSize.md, fontWeight: '800' },
  statLabel:   { color: colors.textDim, fontSize: fontSize.xs, fontWeight: '600',
                 letterSpacing: 0.3, textTransform: 'uppercase' },

  // Sections
  sectionHead: {
    color: colors.textDim, fontSize: fontSize.xs, fontWeight: '700',
    letterSpacing: 1.4, textTransform: 'uppercase',
    marginHorizontal: spacing.lg, marginTop: spacing.xl, marginBottom: spacing.sm,
  },
  section: { marginHorizontal: spacing.lg },
  emptyListings: {
    color: colors.textMuted, fontSize: fontSize.sm, textAlign: 'center',
    paddingVertical: spacing.lg,
    backgroundColor: colors.bgCard, borderRadius: radius.lg,
    borderWidth: 1, borderColor: colors.border,
  },

  // Active listing row
  listingRow: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.bgCard, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.border,
    padding: spacing.sm, marginBottom: spacing.sm,
  },
  listingThumb:            { width: 56, height: 56, borderRadius: radius.sm },
  listingThumbPlaceholder: { backgroundColor: colors.bgInput, alignItems: 'center', justifyContent: 'center' },
  listingThumbEmoji:       { fontSize: 22 },
  listingInfo:  { flex: 1, marginLeft: spacing.md },
  listingName:  { color: colors.text, fontSize: fontSize.sm, fontWeight: '700' },
  listingVenue: { color: colors.textMuted, fontSize: fontSize.xs, marginTop: 2 },
  listingRight: { alignItems: 'flex-end', marginLeft: spacing.sm },
  listingBidLabel: { color: colors.textDim, fontSize: 10, fontWeight: '600',
                     textTransform: 'uppercase', letterSpacing: 0.3 },
  listingBid:   { color: colors.text, fontSize: fontSize.sm, fontWeight: '800', marginTop: 1 },

  // Actions
  actionsWrap: { marginHorizontal: spacing.lg, marginTop: spacing.xl, gap: spacing.sm },
  actionBtn: {
    paddingVertical: spacing.md, borderRadius: radius.md, alignItems: 'center',
    borderWidth: 1, borderColor: colors.borderInput, backgroundColor: colors.bgInput,
  },
  actionBtnText: { color: colors.text, fontSize: fontSize.sm, fontWeight: '700' },
  blockBtn:      { borderColor: colors.error, backgroundColor: 'transparent' },
  blockBtnText:  { color: colors.error },

  // Blocked / empty states
  emptyText:    { color: colors.textMuted, fontSize: fontSize.md, textAlign: 'center' },
  blockedTitle: { color: colors.text, fontSize: fontSize.md, fontWeight: '800', textAlign: 'center' },
  blockedBody:  { color: colors.textMuted, fontSize: fontSize.sm, lineHeight: 20, textAlign: 'center' },
  unblockBtn: {
    marginTop: spacing.sm, backgroundColor: colors.primary,
    paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.xl, borderRadius: radius.md,
  },
  unblockBtnText: { color: colors.text, fontSize: fontSize.sm, fontWeight: '800' },
});
