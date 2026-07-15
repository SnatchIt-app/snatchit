/**
 * app/(tabs)/profile.tsx — User Profile Screen
 *
 * Sections:
 *   1) Header          — "Profile" title + settings icon
 *   2) Identity        — avatar (image or initials), display name, masked phone
 *   3) Badges          — Verified Buyer / Verified Seller pills
 *   4) Seller dashboard— Active / Sold / Avg Sale stat cards
 *   5) Sign Out        — at bottom
 */

import { Image } from 'expo-image';
import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { finalSoldPrice } from '@/src/lib/salePrice';
import { sellerNetDollars } from '@/src/lib/money';
import StatCardStrip from '@/src/components/StatCardStrip';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { getAvatarUrl, pickAndUploadAvatar } from '@/src/lib/avatarImage';
import { useFocusEffect } from '@react-navigation/native';
import { colors, fontSize, radius, spacing } from '@/src/theme';

// ─── Types ────────────────────────────────────────────────────────────────────

type Profile = {
  id:                  string;
  display_name:        string | null;
  phone_number:        string | null;
  avatar_url:          string | null;  // legacy full URL column
  avatar_path:         string | null;  // storage path → signed URL
  is_verified_buyer:   boolean;
  is_verified_seller:  boolean;
  wallet_balance:      number;
  stripe_connect_id:   string | null;
};

type PayoutStatus = 'not_connected' | 'onboarding_required' | 'connected';

type SellerStats = {
  active:  number;
  sold:    number;
  revenue: number;
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** formatMoney(1234.5) => "$1,235" (whole dollars) */
function formatMoney(value: number): string {
  // Proceeds can carry real cents (net of the 10% seller fee) — keep them.
  return Number.isInteger(value)
    ? `$${value.toLocaleString('en-US')}`
    : `$${value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/**
 * maskPhone("+13055551234") => "+1 (305) ***-**34"
 * Works on 10-digit US numbers with or without country code.
 * Shows only the last 4 digits; everything else is masked.
 */
function maskPhone(phone: string | null): string {
  if (!phone) return '—';
  // Strip everything except digits
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 10) return phone; // not a recognisable format
  // last 4 digits
  const last4 = digits.slice(-4);
  return `+1 (***) ***-${last4}`;
}

/** getInitials("Jose Tascon") => "JT" */
function getInitials(name: string | null): string {
  if (!name) return '?';
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map(w => w[0]?.toUpperCase() ?? '')
    .join('');
}

// ─── Sub-components ───────────────────────────────────────────────────────────

/** Uppercase section label */
function SectionLabel({ text }: { text: string }) {
  return <Text style={sc.label}>{text}</Text>;
}
const sc = StyleSheet.create({
  label: {
    fontSize: fontSize.xs,
    fontWeight: '700',
    color: colors.textDim,
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    marginBottom: spacing.md,
  },
});

// ─── Main Screen ─────────────────────────────────────────────────────────────

export default function ProfileScreen() {
  const { user } = useAuth();

  const [profile,         setProfile]         = useState<Profile | null>(null);
  const [stats,           setStats]           = useState<SellerStats>({ active: 0, sold: 0, revenue: 0 });
  const [pageLoading,     setPageLoading]     = useState(true);
  const [loadError,       setLoadError]       = useState<'offline' | 'error' | null>(null);
  const [refreshing,      setRefreshing]      = useState(false);
  const [signOutBusy,     setSignOutBusy]     = useState(false);
  // Resolved signed URL for the avatar (async, computed from avatar_path or avatar_url)
  const [avatarUrl,       setAvatarUrl]       = useState<string | null>(null);
  const [avatarUploading, setAvatarUploading] = useState(false);
  // Real payout status from backend (not from local DB column)
  const [payoutStatus,    setPayoutStatus]    = useState<PayoutStatus>('not_connected');

  // ── Data fetch ─────────────────────────────────────────────────────────────

  async function loadData() {
    if (!user) return;

    // 1. Fetch profile row (avatar_path added; falls back gracefully if column missing)
    const { data: profileData, error: profileErr } = await supabase
      .from('profiles')
      .select('id, display_name, phone_number, avatar_url, avatar_path, is_verified_buyer, is_verified_seller, wallet_balance, stripe_connect_id')
      .eq('id', user.id)
      .single();

    setLoadError(profileData ? null
      : profileErr && isNetworkError(profileErr) ? 'offline'
      : profileErr ? 'error' : null);

    if (profileData) {
      const p = profileData as Profile;
      setProfile(p);
      // Resolve avatar: prefer avatar_path (storage path), fall back to avatar_url (legacy full URL).
      // getAvatarUrl is now synchronous (public bucket → getPublicUrl).
      setAvatarUrl(getAvatarUrl(p.avatar_path ?? p.avatar_url));
    }

    // 2. Active listings — auction still running (uses auction_status column)
    const { count: activeCount } = await supabase
      .from('listings')
      .select('id', { count: 'exact', head: true })
      .eq('seller_id', user.id)
      .eq('auction_status', 'active');

    // 3. Sold / ended listings — completed via auction OR buy-now
    //    Fetch the amounts so we can compute total revenue.
    const { data: soldData } = await supabase
      .from('listings')
      .select('winning_bid_amount, current_bid, buy_now_enabled, buy_now_price, status, auction_status')
      .eq('seller_id', user.id)
      .or('status.eq.sold,auction_status.eq.ended');

    const soldCount = soldData?.length ?? 0;

    // Proceeds: what the seller actually receives — base sale price minus the
    // 10% seller fee, computed per transaction with the canonical money util
    // (matches the real per-payout rounding). Auction wins use
    // winning_bid_amount; Buy Now uses buy_now_price via finalSoldPrice.
    const totalRevenue = (soldData ?? []).reduce((sum, row) => {
      if (row.winning_bid_amount != null && row.winning_bid_amount > 0) {
        return sum + sellerNetDollars(row.winning_bid_amount);
      }
      if (row.status === 'sold') {
        const price = finalSoldPrice(row);
        return sum + (price > 0 ? sellerNetDollars(price) : 0);
      }
      return sum;
    }, 0);

    setStats({
      active:  activeCount ?? 0,
      sold:    soldCount,
      revenue: totalRevenue,
    });

    // 4. Payout status — non-blocking. The Stripe round-trip can take
    //    several seconds; the UI must render before it resolves. Fire-
    //    and-forget with a 6 s timeout so a slow Stripe call can never
    //    wedge the profile tab.
    if (profileData?.stripe_connect_id) {
      void (async () => {
        try {
          const result = await Promise.race([
            supabase.functions.invoke('create-connect-account', { body: { status_only: true } }),
            new Promise<{ data: null; error: { message: string } }>((resolve) =>
              setTimeout(() => resolve({ data: null, error: { message: 'timeout' } }), 6000),
            ),
          ]);
          const { data: statusData, error: statusErr } = result as { data: unknown; error: { message: string } | null };
          if (!statusErr && statusData) {
            const parsed = typeof statusData === 'string' ? JSON.parse(statusData) : statusData;
            const s = (parsed as { status?: string })?.status;
            if (s === 'connected' || s === 'onboarding_required' || s === 'not_connected') {
              setPayoutStatus(s);
            }
          }
        } catch { /* keep current */ }
      })();
    } else {
      setPayoutStatus('not_connected');
    }
  }

  useEffect(() => {
    loadData().finally(() => setPageLoading(false));
  }, [user?.id]);

  // Re-fetch profile + stats every time the tab gains focus
  // (e.g. returning from Edit Profile, My Listings, or Settings).
  // Runs silently — no loading spinner, just refreshes data in place.
  useFocusEffect(
    useCallback(() => {
      if (!user?.id) return;
      // Skip the very first focus event (the initial mount useEffect handles that)
      if (pageLoading) return;
      loadData();
    }, [user?.id, pageLoading]),
  );

  async function onRefresh() {
    setRefreshing(true);
    await loadData();
    setRefreshing(false);
  }

  // ── Avatar upload ───────────────────────────────────────────────────────────

  async function handleAvatarPress() {
    if (!user) return;
    if (avatarUploading) return;

    setAvatarUploading(true);
    const result = await pickAndUploadAvatar(user.id);
    setAvatarUploading(false);

    if (!result.ok) {
      // Cancelled silently — don't show an alert for cancellation
      if (result.error !== 'Cancelled.') {
        Alert.alert('Upload failed', result.error);
      }
      return;
    }

    // Update profiles.avatar_path in the DB
    const { error: dbError } = await supabase
      .from('profiles')
      .update({ avatar_path: result.storagePath })
      .eq('id', user.id);

    if (dbError) {
      Alert.alert('Save failed', dbError.message);
      return;
    }

    // Immediately reflect new avatar in the UI (no state re-fetch needed)
    setAvatarUrl(result.publicUrl);
    setProfile(prev => prev ? { ...prev, avatar_path: result.storagePath } : prev);
  }

  async function handleSignOut() {
    setSignOutBusy(true);
    await supabase.auth.signOut();
    // useAuth in _layout.tsx detects session → null → routes to /(auth)/login
    setSignOutBusy(false);
  }

  // ── Loading state ──────────────────────────────────────────────────────────

  if (pageLoading) {
    return (
      <View style={s.centered}>
        <ActivityIndicator color={colors.primary} size="large" />
      </View>
    );
  }

  // Nothing loaded at all (fresh open while offline / server down) — show the
  // dedicated fallback. With cached profile data the screen renders normally.
  if (!profile && loadError) {
    return (
      <View style={{ flex: 1, backgroundColor: colors.bg }}>
        <ScreenState state={loadError} onRetry={loadData} />
      </View>
    );
  }

  // ── Derived display values ─────────────────────────────────────────────────

  const displayName  = profile?.display_name ?? user?.email?.split('@')[0] ?? 'User';
  const initials     = getInitials(displayName);
  const maskedPhone  = maskPhone(profile?.phone_number ?? null);
  // ─────────────────────────────────────────────────────────────────────────
  // RENDER
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <View style={s.root}>
      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.scrollContent}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.primary} />
        }
      >

        {/* ── 1. HEADER ──────────────────────────────────────────────────── */}
        <View style={s.header}>
          <Text style={s.headerTitle}>Profile</Text>
          {/* Settings icon — routes to /settings (create that screen later) */}
          <TouchableOpacity
            style={s.settingsBtn}
            onPress={() => router.push('/settings')}
            activeOpacity={0.7}
          >
            <Text style={s.settingsIcon}>⚙️</Text>
          </TouchableOpacity>
        </View>

        {/* ── 2. IDENTITY ────────────────────────────────────────────────── */}
        <View style={s.identitySection}>

          {/* Avatar — tap to pick + upload */}
          <TouchableOpacity
            style={s.avatarRing}
            onPress={handleAvatarPress}
            activeOpacity={0.75}
            disabled={avatarUploading}
          >
            {avatarUrl ? (
              <Image
                source={{ uri: avatarUrl }}
                style={s.avatarImage}
                contentFit="cover"
              />
            ) : (
              <View style={s.avatarFallback}>
                <Text style={s.avatarInitials}>{initials}</Text>
              </View>
            )}

            {/* Uploading overlay */}
            {avatarUploading && (
              <View style={s.avatarOverlay}>
                <ActivityIndicator color={colors.text} size="small" />
              </View>
            )}

            {/* Edit badge */}
            {!avatarUploading && (
              <View style={s.avatarEditBadge}>
                <Text style={s.avatarEditIcon}>✎</Text>
              </View>
            )}
          </TouchableOpacity>

          {/* Display name */}
          <Text style={s.displayName}>{displayName}</Text>

          {/* Masked phone */}
          <Text style={s.phoneNumber}>{maskedPhone}</Text>

          {/* ── 3. VERIFICATION BADGES ─────────────────────────── */}
          {(profile?.is_verified_buyer || profile?.is_verified_seller) && (
            <View style={s.badgesRow}>
              {profile?.is_verified_buyer && (
                <View style={[s.badge, s.badgeBuyer]}>
                  <Text style={[s.badgeText, s.badgeBuyerText]}>✓ Verified Buyer</Text>
                </View>
              )}
              {profile?.is_verified_seller && (
                <View style={[s.badge, s.badgeSeller]}>
                  <Text style={[s.badgeText, s.badgeSellerText]}>✓ Verified Seller</Text>
                </View>
              )}
            </View>
          )}
        </View>

        {/* ── 4. SELLER DASHBOARD ────────────────────────────────────────── */}
        <View style={s.section}>
          <SectionLabel text="Seller Dashboard" />
          <StatCardStrip
            style={s.statsStrip}
            contentPaddingHorizontal={0}
            items={[
              {
                key: 'active',
                label: 'Active',
                value: String(stats.active),
                onPress: () => router.push({ pathname: '/my-listings', params: { filter: 'active' } }),
              },
              {
                key: 'sold',
                label: 'Sold',
                value: String(stats.sold),
                onPress: () => router.push({ pathname: '/my-listings', params: { filter: 'sold' } }),
              },
              {
                key: 'revenue',
                label: 'Proceeds',
                value: stats.revenue > 0 ? formatMoney(stats.revenue) : '—',
              },
            ]}
          />

          {/* My Listings — full-width navigation row */}
          <Pressable
            style={s.myListingsBtn}
            onPress={() => router.push('/my-listings')}
            android_ripple={{ color: colors.primarySoft }}
          >
            <Text style={s.myListingsIcon}>📋</Text>
            <View style={s.myListingsInfo}>
              <Text style={s.myListingsText}>My Listings</Text>
              <Text style={s.myListingsSub}>
                {stats.active + stats.sold} total listing{stats.active + stats.sold !== 1 ? 's' : ''}
              </Text>
            </View>
            <Text style={s.myListingsChevron}>›</Text>
          </Pressable>
        </View>

        {/* ── 4b. PAYOUT STATUS ──────────────────────────────────────────── */}
        {(stats.sold > 0 || stats.active > 0) && (
          <View style={s.section}>
            <SectionLabel text="Payouts" />
            <Pressable
              style={s.payoutRow}
              onPress={() => router.push('/settings/payout-setup')}
              android_ripple={{ color: colors.primarySoft }}
            >
              <Text style={s.payoutIcon}>{payoutStatus === 'connected' ? '✅' : '⚠️'}</Text>
              <View style={s.payoutInfo}>
                <Text style={s.payoutTitle}>
                  {payoutStatus === 'connected'
                    ? 'Connected to Stripe'
                    : payoutStatus === 'onboarding_required'
                      ? 'Complete Payout Setup'
                      : 'Set Up Payouts'}
                </Text>
                <View style={s.payoutStatusRow}>
                  <View style={[
                    s.payoutDot,
                    { backgroundColor: payoutStatus === 'connected' ? colors.success : colors.warning },
                  ]} />
                  <Text style={[
                    s.payoutStatusText,
                    { color: payoutStatus === 'connected' ? colors.success : colors.warning },
                  ]}>
                    {payoutStatus === 'connected'
                      ? 'Payouts enabled'
                      : payoutStatus === 'onboarding_required'
                        ? 'Onboarding Incomplete'
                        : 'Payouts Not Set Up'}
                  </Text>
                </View>
              </View>
              <Text style={s.payoutChevron}>›</Text>
            </Pressable>
          </View>
        )}

        {/* ── 5. SIGN OUT ────────────────────────────────────────────────── */}
        <View style={s.section}>
          <TouchableOpacity
            style={[s.signOutBtn, signOutBusy && { opacity: 0.6 }]}
            onPress={handleSignOut}
            disabled={signOutBusy}
            activeOpacity={0.8}
          >
            {signOutBusy
              ? <ActivityIndicator color={colors.error} size="small" />
              : <Text style={s.signOutText}>Sign Out</Text>
            }
          </TouchableOpacity>
        </View>

        <View style={{ height: spacing.xxl }} />
      </ScrollView>
    </View>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const AVATAR_SIZE  = 96;
const RING_SIZE    = AVATAR_SIZE + 8; // 4px padding each side

const s = StyleSheet.create({
  root:  { flex: 1, backgroundColor: colors.bg },
  centered: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
  scroll:       { flex: 1 },
  scrollContent:{ paddingBottom: spacing.xxl },

  // ── Header ────────────────────────────────────────────────────────────────
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: 56,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  headerTitle: {
    fontSize: fontSize.xl,
    fontWeight: '800',
    color: colors.text,
  },
  settingsBtn: {
    width: 40, height: 40,
    alignItems: 'center', justifyContent: 'center',
  },
  settingsIcon: { fontSize: 22 },

  // ── Identity ──────────────────────────────────────────────────────────────
  identitySection: {
    alignItems: 'center',
    paddingTop: spacing.xl,
    paddingBottom: spacing.lg,
    paddingHorizontal: spacing.lg,
  },

  // Red glowing ring around avatar
  avatarRing: {
    width:         RING_SIZE,
    height:        RING_SIZE,
    borderRadius:  RING_SIZE / 2,
    borderWidth:   2,
    borderColor:   colors.primary,
    alignItems:    'center',
    justifyContent:'center',
    marginBottom:  spacing.md,
    // Glow via shadow
    shadowColor:   colors.primary,
    shadowOffset:  { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius:  12,
    elevation:     10,
  },
  avatarImage: {
    width:        AVATAR_SIZE,
    height:       AVATAR_SIZE,
    borderRadius: AVATAR_SIZE / 2,
  },
  avatarFallback: {
    width:            AVATAR_SIZE,
    height:           AVATAR_SIZE,
    borderRadius:     AVATAR_SIZE / 2,
    backgroundColor:  colors.primarySoft,
    alignItems:       'center',
    justifyContent:   'center',
  },
  avatarInitials: {
    fontSize:   fontSize.xl,
    fontWeight: '800',
    color:      colors.primary,
  },

  // Semi-transparent spinner overlay while uploading
  avatarOverlay: {
    position:        'absolute',
    inset:           0,
    borderRadius:    AVATAR_SIZE / 2,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems:      'center',
    justifyContent:  'center',
  },

  // Small edit pencil badge in the bottom-right corner of the avatar
  avatarEditBadge: {
    position:        'absolute',
    bottom:          0,
    right:           0,
    width:           26,
    height:          26,
    borderRadius:    13,
    backgroundColor: colors.primary,
    alignItems:      'center',
    justifyContent:  'center',
    borderWidth:     2,
    borderColor:     colors.bg,
  },
  avatarEditIcon: {
    color:      colors.text,
    fontSize:   13,
    fontWeight: '700',
    lineHeight: 15,
  },

  displayName: {
    fontSize:   fontSize.lg,
    fontWeight: '800',
    color:      colors.text,
    marginBottom: spacing.xs,
    textAlign: 'center',
  },
  phoneNumber: {
    fontSize: fontSize.sm,
    color:    colors.textMuted,
    marginBottom: spacing.md,
  },

  // ── Badges ────────────────────────────────────────────────────────────────
  badgesRow: {
    flexDirection: 'row',
    gap: spacing.sm,
    flexWrap: 'wrap',
    justifyContent: 'center',
  },
  badge: {
    paddingHorizontal: spacing.md,
    paddingVertical:   spacing.xs,
    borderRadius:      radius.full,
    borderWidth:       1,
  },
  badgeText: { fontSize: fontSize.xs, fontWeight: '700' },
  badgeBuyer:       { backgroundColor: 'rgba(74,222,128,0.12)', borderColor: colors.success },
  badgeBuyerText:   { color: colors.success },
  badgeSeller:      { backgroundColor: colors.primarySoft,       borderColor: colors.primary },
  badgeSellerText:  { color: colors.primary },

  // ── Sections ──────────────────────────────────────────────────────────────
  section: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
  },

  // ── Seller stats ──────────────────────────────────────────────────────────
  statsStrip: {},

  // ── My Listings button ──────────────────────────────────────────────────
  myListingsBtn: {
    flexDirection:   'row',
    alignItems:      'center',
    backgroundColor: colors.bgCard,
    borderRadius:    radius.lg,
    borderWidth:     1,
    borderColor:     colors.border,
    padding:         spacing.md,
    marginTop:       spacing.md,
    gap:             spacing.md,
  },
  myListingsIcon: { fontSize: 24, width: 32, textAlign: 'center' },
  myListingsInfo: { flex: 1 },
  myListingsText: { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },
  myListingsSub:  { color: colors.textMuted, fontSize: fontSize.xs, marginTop: 2 },
  myListingsChevron: { color: colors.textMuted, fontSize: fontSize.xl, fontWeight: '300' },

  // ── Payout status ───────────────────────────────────────────────────────
  payoutRow: {
    flexDirection:   'row',
    alignItems:      'center',
    backgroundColor: colors.bgCard,
    borderRadius:    radius.lg,
    borderWidth:     1,
    borderColor:     colors.border,
    padding:         spacing.md,
    gap:             spacing.md,
  },
  payoutIcon:       { fontSize: 24, width: 32, textAlign: 'center' },
  payoutInfo:       { flex: 1 },
  payoutTitle:      { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },
  payoutStatusRow:  { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, marginTop: 4 },
  payoutDot:        { width: 8, height: 8, borderRadius: 4 },
  payoutStatusText: { fontSize: fontSize.xs, fontWeight: '600' },
  payoutChevron:    { color: colors.textMuted, fontSize: fontSize.xl, fontWeight: '300' },

  // ── Sign Out ──────────────────────────────────────────────────────────────
  signOutBtn: {
    borderWidth:   1,
    borderColor:   colors.error,
    borderRadius:  radius.md,
    paddingVertical: spacing.md,
    alignItems:    'center',
  },
  signOutText: {
    color:      colors.error,
    fontWeight: '700',
    fontSize:   fontSize.md,
    letterSpacing: 0.5,
  },
});
