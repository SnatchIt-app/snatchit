/**
 * app/(tabs)/profile.tsx — Profile (V2).
 *
 * PRESENTATION rebuilt on the V2 system; the DATA LAYER is unchanged. The same
 * get_my_profile() fetch, the same active/sold/proceeds computation (proceeds via
 * the canonical sellerNetDollars — money is untouched), the same non-blocking
 * payout-status probe with its 6s timeout, the same avatar pick+upload, sign out,
 * focus refetch and pull-to-refresh. Proceeds still render "—" when zero so an
 * UNKNOWN total stays distinct from a real $0 (the seller-trust false-zero rule).
 *
 * The public seller profile (app/profile/[id].tsx) is a separate surface and is
 * out of this batch's scope; it is not touched here.
 */

import { Image } from 'expo-image';
import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import type { MyProfileRPC } from '@/src/types';
import { useAuth } from '@/src/hooks/useAuth';
import { finalSoldPrice } from '@/src/lib/salePrice';
import { sellerNetDollars } from '@/src/lib/money';
import ScreenState from '@/src/components/ScreenState';
import { isNetworkError } from '@/src/hooks/useNetworkStatus';
import { getAvatarUrl, pickAndUploadAvatar } from '@/src/lib/avatarImage';
import { Badge, Button, Spinner } from '@/src/components/ui';
import { AccountSection } from '@/src/components/account/AccountSection';
import { useDockScroll } from '@/src/components/nav/dockContext';
import { useDockClearance } from '@/src/lib/nav/navInsets';
import { SettingsRow } from '@/src/components/account/SettingsRow';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

// ─── Types (data layer — unchanged) ─────────────────────────────────────────────

type Profile = {
  id:                 string;
  display_name:       string | null;
  phone_number:       string | null;
  avatar_url:         string | null;
  avatar_path:        string | null;
  is_verified_buyer:  boolean;
  is_verified_seller: boolean;
  wallet_balance:     number;
  stripe_connect_id:  string | null;
};

type PayoutStatus = 'not_connected' | 'onboarding_required' | 'connected';
type SellerStats = { active: number; sold: number; revenue: number };

// ─── Helpers (unchanged) ────────────────────────────────────────────────────────

function formatMoney(value: number): string {
  return Number.isInteger(value)
    ? `$${value.toLocaleString('en-US')}`
    : `$${value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function maskPhone(phone: string | null): string {
  if (!phone) return '—';
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 10) return phone;
  const last4 = digits.slice(-4);
  return `+1 (***) ***-${last4}`;
}

function getInitials(name: string | null): string {
  if (!name) return '?';
  return name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]?.toUpperCase() ?? '').join('');
}

const PAYOUT_COPY: Record<PayoutStatus, { title: string; state: string; tone: 'success' | 'warning' }> = {
  connected:           { title: 'Connected to Stripe',    state: 'Payouts enabled',       tone: 'success' },
  onboarding_required: { title: 'Complete payout setup',  state: 'Onboarding incomplete', tone: 'warning' },
  not_connected:       { title: 'Set up payouts',         state: 'Not set up',            tone: 'warning' },
};

// ─── Screen ─────────────────────────────────────────────────────────────────────

export default function ProfileScreen() {
  const { user } = useAuth();
  const insets = useSafeAreaInsets();
  const dockClearance = useDockClearance();
  const { onScroll: onDockScroll, expand: expandDock } = useDockScroll('profile');

  const [profile,         setProfile]         = useState<Profile | null>(null);
  const [stats,           setStats]           = useState<SellerStats>({ active: 0, sold: 0, revenue: 0 });
  const [pageLoading,     setPageLoading]     = useState(true);
  const [loadError,       setLoadError]       = useState<'offline' | 'error' | null>(null);
  const [refreshing,      setRefreshing]      = useState(false);
  const [signOutBusy,     setSignOutBusy]     = useState(false);
  const [avatarUrl,       setAvatarUrl]       = useState<string | null>(null);
  const [avatarUploading, setAvatarUploading] = useState(false);
  const [payoutStatus,    setPayoutStatus]    = useState<PayoutStatus>('not_connected');

  async function loadData() {
    if (!user) return;

    // 1. Profile row via get_my_profile()
    const { data: profileData, error: profileErr } = await supabase.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle();

    setLoadError(profileData ? null
      : profileErr && isNetworkError(profileErr) ? 'offline'
      : profileErr ? 'error' : null);

    if (profileData) {
      const p = profileData as Profile;
      setProfile(p);
      setAvatarUrl(getAvatarUrl(p.avatar_path ?? p.avatar_url));
    }

    // 2. Active listings
    const { count: activeCount } = await supabase
      .from('listings')
      .select('id', { count: 'exact', head: true })
      .eq('seller_id', user.id)
      .eq('auction_status', 'active');

    // 3. Sold / ended listings + amounts for proceeds
    const { data: soldData } = await supabase
      .from('listings')
      .select('winning_bid_amount, current_bid, buy_now_enabled, buy_now_price, status, auction_status')
      .eq('seller_id', user.id)
      .or('status.eq.sold,auction_status.eq.ended');

    const soldCount = soldData?.length ?? 0;

    // Proceeds: seller net per transaction via the canonical money util.
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

    setStats({ active: activeCount ?? 0, sold: soldCount, revenue: totalRevenue });

    // 4. Payout status — non-blocking, 6s timeout so a slow Stripe call can never
    //    wedge the tab.
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
            const st = (parsed as { status?: string })?.status;
            if (st === 'connected' || st === 'onboarding_required' || st === 'not_connected') {
              setPayoutStatus(st);
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

  useFocusEffect(
    useCallback(() => {
      expandDock(); // arrive with the full dock
      if (!user?.id) return;
      if (pageLoading) return;
      loadData();
    }, [user?.id, pageLoading, expandDock]),
  );

  async function onRefresh() {
    setRefreshing(true);
    await loadData();
    setRefreshing(false);
  }

  async function handleAvatarPress() {
    if (!user || avatarUploading) return;
    setAvatarUploading(true);
    const result = await pickAndUploadAvatar(user.id);
    setAvatarUploading(false);

    if (!result.ok) {
      if (result.error !== 'Cancelled.') Alert.alert('Upload failed', result.error);
      return;
    }
    const { error: dbError } = await supabase.from('profiles').update({ avatar_path: result.storagePath }).eq('id', user.id);
    if (dbError) { Alert.alert('Save failed', dbError.message); return; }
    setAvatarUrl(result.publicUrl);
    setProfile((prev) => (prev ? { ...prev, avatar_path: result.storagePath } : prev));
  }

  async function handleSignOut() {
    setSignOutBusy(true);
    await supabase.auth.signOut();
    setSignOutBusy(false);
  }

  if (pageLoading) {
    return (
      <View style={[s.root, s.centered]}>
        <Spinner color={v2.brand.red} />
      </View>
    );
  }

  if (!profile && loadError) {
    return (
      <View style={s.root}>
        <ScreenState state={loadError} onRetry={loadData} />
      </View>
    );
  }

  const displayName = profile?.display_name ?? user?.email?.split('@')[0] ?? 'User';
  const initials    = getInitials(displayName);
  const maskedPhone = maskPhone(profile?.phone_number ?? null);
  const totalListings = stats.active + stats.sold;
  const showPayouts = stats.sold > 0 || stats.active > 0;
  const payout = PAYOUT_COPY[payoutStatus];

  return (
    <View style={s.root}>
      {/* ── Header ──────────────────────────────────────────── */}
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
        <Text style={[textStyle('displayMd'), s.headerTitle]} accessibilityRole="header">Profile</Text>
        <Pressable onPress={() => router.push('/settings')} hitSlop={8} accessibilityRole="button" accessibilityLabel="Settings">
          <Text style={[textStyle('label'), s.headerAction]}>Settings</Text>
        </Pressable>
      </View>

      <ScrollView
        contentContainerStyle={[s.scroll, { paddingBottom: dockClearance }]}
        showsVerticalScrollIndicator={false}
        onScroll={onDockScroll}
        scrollEventThrottle={16}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={v2.brand.red} />}
      >
        {/* ── Identity ──────────────────────────────────────── */}
        <View style={s.identity}>
          <Pressable style={s.avatarRing} onPress={handleAvatarPress} disabled={avatarUploading} accessibilityRole="button" accessibilityLabel="Change profile photo">
            {avatarUrl ? (
              <Image source={{ uri: avatarUrl }} style={s.avatarImage} contentFit="cover" />
            ) : (
              <View style={s.avatarFallback}>
                <Text style={s.avatarInitials}>{initials}</Text>
              </View>
            )}
            {avatarUploading ? (
              <View style={s.avatarOverlay}><Spinner color={v2.text.primary} /></View>
            ) : (
              <View style={s.avatarEditBadge}><Text style={s.avatarEditGlyph}>{'✎'}</Text></View>
            )}
          </Pressable>

          <Text style={s.name} numberOfLines={1}>{displayName}</Text>
          <Text style={[textStyle('bodySm'), s.phone]}>{maskedPhone}</Text>

          {(profile?.is_verified_buyer || profile?.is_verified_seller) ? (
            <View style={s.badges}>
              {profile?.is_verified_buyer ? <Badge label="Verified buyer" tone="success" /> : null}
              {profile?.is_verified_seller ? <Badge label="Verified seller" tone="neutral" /> : null}
            </View>
          ) : null}
        </View>

        {/* ── Seller ────────────────────────────────────────── */}
        <AccountSection title="Seller">
          <View style={s.stats}>
            <Stat label="Active" value={String(stats.active)} onPress={() => router.push({ pathname: '/my-listings', params: { filter: 'active' } })} />
            <View style={s.statDivider} />
            <Stat label="Sold" value={String(stats.sold)} onPress={() => router.push({ pathname: '/my-listings', params: { filter: 'sold' } })} />
            <View style={s.statDivider} />
            {/* Proceeds: "—" when zero keeps unknown distinct from a real $0. */}
            <Stat label="Proceeds" value={stats.revenue > 0 ? formatMoney(stats.revenue) : '—'} />
          </View>
          <SettingsRow
            label="My listings"
            value={`${totalListings} total`}
            onPress={() => router.push('/my-listings')}
          />
        </AccountSection>

        {/* ── Payouts ───────────────────────────────────────── */}
        {showPayouts ? (
          <AccountSection title="Payouts">
            <SettingsRow
              label={payout.title}
              description={payout.state}
              onPress={() => router.push('/settings/payout-setup')}
            />
          </AccountSection>
        ) : null}

        {/* ── Sign out ──────────────────────────────────────── */}
        <View style={s.signOut}>
          <Button label="Sign out" variant="secondary" onPress={handleSignOut} loading={signOutBusy} disabled={signOutBusy} block />
        </View>
      </ScrollView>
    </View>
  );
}

function Stat({ label, value, onPress }: { label: string; value: string; onPress?: () => void }) {
  const body = (
    <View style={s.stat}>
      <Text style={[textStyle('price'), s.statValue]} numberOfLines={1}>{value}</Text>
      <Text style={[textStyle('micro'), s.statLabel]}>{label}</Text>
    </View>
  );
  if (!onPress) return body;
  return (
    <Pressable style={s.statPressable} onPress={onPress} accessibilityRole="button" accessibilityLabel={`${label}, ${value}`}>
      {body}
    </Pressable>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const AVATAR = 92;
const RING = AVATAR + 8;

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  centered: { alignItems: 'center', justifyContent: 'center' },

  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: v2.space.lg, paddingBottom: v2.space.md,
    borderBottomWidth: 1, borderBottomColor: v2.border.default,
  },
  headerTitle: { color: v2.text.primary },
  headerAction: { color: v2.brand.red },

  scroll: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.xxxl },

  identity: { alignItems: 'center', paddingTop: v2.space.xl, paddingBottom: v2.space.lg },
  avatarRing: {
    width: RING, height: RING, borderRadius: RING / 2,
    borderWidth: 1, borderColor: v2.brand.red,
    alignItems: 'center', justifyContent: 'center', marginBottom: v2.space.md,
  },
  avatarImage: { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2 },
  avatarFallback: {
    width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2,
    backgroundColor: v2.brand.redSoft, alignItems: 'center', justifyContent: 'center',
  },
  avatarInitials: { fontFamily: v2.font.bodyBold, fontSize: 30, color: v2.brand.red },
  avatarOverlay: {
    ...StyleSheet.absoluteFillObject, borderRadius: RING / 2,
    backgroundColor: 'rgba(0,0,0,0.55)', alignItems: 'center', justifyContent: 'center',
  },
  avatarEditBadge: {
    position: 'absolute', bottom: 0, right: 4,
    width: 26, height: 26, borderRadius: 13,
    backgroundColor: v2.brand.red, alignItems: 'center', justifyContent: 'center',
    borderWidth: 2, borderColor: v2.surface.canvas,
  },
  avatarEditGlyph: { color: v2.text.inverse, fontSize: 13, fontWeight: '700', lineHeight: 15 },

  name: { fontFamily: v2.font.bodyBold, fontSize: 22, color: v2.text.primary, textAlign: 'center' },
  phone: { color: v2.text.muted, marginTop: v2.space.xs },
  badges: { flexDirection: 'row', gap: v2.space.sm, marginTop: v2.space.md },

  stats: { flexDirection: 'row', alignItems: 'stretch', paddingVertical: v2.space.md },
  statPressable: { flex: 1 },
  stat: { flex: 1, alignItems: 'center', gap: v2.space.xs },
  statValue: { color: v2.text.primary },
  statLabel: { color: v2.text.muted },
  statDivider: { width: 1, backgroundColor: v2.border.default, marginVertical: v2.space.xs },

  signOut: { marginTop: v2.space.xxl },
});
