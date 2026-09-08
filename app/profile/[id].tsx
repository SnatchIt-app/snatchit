/**
 * app/profile/[id].tsx — Public seller / community profile (V2).
 *
 * PRESENTATION rebuilt on the V2 system; behaviour and privacy are unchanged.
 * Reached by tapping a seller from a listing. Shows ONLY public columns (avatar,
 * name, verified badge, bio, member-since, trust counts, active listings) — never
 * email / phone / Stripe IDs / wallet / preferences. The block check,
 * `get_profile_trust_stats` RPC, the "history unavailable ≠ zero sales" distinction,
 * report/block/unblock and the self-view guard are all preserved. Reputation
 * derivation moves to src/lib/profile/reputation.ts (pure, tested). Money via the
 * all-in helper; media via EventMedia.
 */

import { Image } from 'expo-image';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { allInLabel } from '@/src/lib/money';
import { useAuth } from '@/src/hooks/useAuth';
import { getAvatarUrl } from '@/src/lib/avatarImage';
import { EventMedia } from '@/src/components/media/EventMedia';
import { Badge, Button, EmptyState, Spinner } from '@/src/components/ui';
import { AccountSection } from '@/src/components/account/AccountSection';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { deriveReputation, reputationTone } from '@/src/lib/profile/reputation';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Listing, ProfileTrustStats } from '@/src/types';

type PublicProfile = {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
  avatar_path: string | null;
  bio: string | null;
  created_at: string | null;
  is_verified_seller: boolean;
  stripe_onboarding_complete: boolean;
};

function getInitials(name: string | null): string {
  if (!name || !name.trim()) return '?';
  return name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]?.toUpperCase() ?? '').join('');
}

function memberSince(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
}

function ActiveListingRow({ listing }: { listing: Listing }) {
  return (
    <Pressable style={s.listingRow} onPress={() => router.push(`/listing/${listing.id}`)} accessibilityRole="button" accessibilityLabel={listing.event_name}>
      <EventMedia asset={{ path: listing.cover_image_path, contract: 'legacy', bucket: 'auction-media' }} slot="CHECKOUT_THUMBNAIL" width={64} title={listing.event_name} decorative />
      <View style={s.listingInfo}>
        <Text style={[textStyle('title'), s.listingName]} numberOfLines={1}>{listing.event_name}</Text>
        <Text style={[textStyle('bodySm'), s.listingVenue]} numberOfLines={1}>
          {listing.venue}{listing.neighborhood ? ` · ${listing.neighborhood.replace(/\b\w/g, (c) => c.toUpperCase())}` : ''}
        </Text>
      </View>
      <View style={s.listingRight}>
        <Text style={[textStyle('micro'), s.listingBidLabel]}>Current bid</Text>
        <Text style={[textStyle('price'), s.listingBid]} numberOfLines={1}>{allInLabel(listing.current_bid)}</Text>
      </View>
    </Pressable>
  );
}

function TrustRow({ label, value, emphasize, last }: { label: string; value: string; emphasize?: boolean; last?: boolean }) {
  return (
    <View style={[s.trustRow, !last && s.trustRowBorder]}>
      <Text style={[textStyle('body'), s.trustRowLabel]}>{label}</Text>
      <Text style={[textStyle('body'), emphasize ? s.trustRowValueEmphasize : s.trustRowValue]}>{value}</Text>
    </View>
  );
}

export default function PublicProfileScreen() {
  const { user } = useAuth();
  const { id } = useLocalSearchParams<{ id: string }>();
  const sellerId = id ?? '';
  const isSelf = !!user?.id && user.id === sellerId;

  const [loading, setLoading] = useState(true);
  const [profile, setProfile] = useState<PublicProfile | null>(null);
  const [avatarUrl, setAvatarUrl] = useState<string | null>(null);
  const [trustStats, setTrustStats] = useState<ProfileTrustStats | null>(null);
  // A FAILED stats query is a different fact from "no history" — see reputation.ts.
  const [statsUnavailable, setStatsUnavailable] = useState(false);
  const [activeListings, setActiveListings] = useState<Listing[]>([]);
  const [isBlocked, setIsBlocked] = useState(false);
  const [working, setWorking] = useState(false);

  const load = useCallback(async () => {
    if (!sellerId) { setLoading(false); return; }
    setLoading(true);

    let blocked = false;
    if (user?.id && !isSelf) {
      const { data: blockRow } = await supabase
        .from('user_blocks').select('blocked_id').eq('blocker_id', user.id).eq('blocked_id', sellerId).maybeSingle();
      blocked = !!blockRow;
    }
    setIsBlocked(blocked);

    // Safe columns only — never select phone/stripe/wallet.
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

    if (blocked) {
      setTrustStats(null); setStatsUnavailable(false); setActiveListings([]); setLoading(false); return;
    }

    const { data: statsRow, error: statsErr } = await supabase.rpc('get_profile_trust_stats', { p_user_id: sellerId });
    if (statsErr) {
      console.warn('[profile] get_profile_trust_stats error:', statsErr.message);
      setTrustStats(null); setStatsUnavailable(true);
    } else {
      const row = Array.isArray(statsRow) ? statsRow[0] : statsRow;
      setTrustStats((row as ProfileTrustStats) ?? null); setStatsUnavailable(false);
    }

    const { data: actives } = await supabase
      .from('listings').select('*').eq('seller_id', sellerId).eq('status', 'active').eq('auction_status', 'active').order('ends_at', { ascending: true });
    setActiveListings((actives as Listing[]) ?? []);
    setLoading(false);
  }, [sellerId, user?.id, isSelf]);

  useEffect(() => { load(); }, [load]);

  function handleReport() {
    router.push(`/report/user/${sellerId}` as never);
  }

  function handleBlock() {
    if (!user?.id) { Alert.alert('Sign in required', 'You need to be signed in to block users.'); return; }
    const name = profile?.display_name?.trim() || 'this seller';
    Alert.alert(`Block ${name}?`, 'Their listings will be hidden from your feed. You can unblock anytime in Settings → Blocked users.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Block',
        style: 'destructive',
        onPress: async () => {
          setWorking(true);
          const { error } = await supabase.from('user_blocks').insert({ blocker_id: user.id, blocked_id: sellerId });
          setWorking(false);
          if (error && error.code !== '23505') { Alert.alert('Could not block', error.message); return; }
          Alert.alert('Blocked', `${name} is hidden from your feed.`, [{ text: 'OK', onPress: () => router.back() }]);
        },
      },
    ]);
  }

  async function handleUnblock() {
    if (!user?.id) return;
    setWorking(true);
    const { error } = await supabase.from('user_blocks').delete().eq('blocker_id', user.id).eq('blocked_id', sellerId);
    setWorking(false);
    if (error) { Alert.alert('Could not unblock', error.message); return; }
    setIsBlocked(false);
    load();
  }

  if (loading) {
    return (
      <View style={s.root}>
        <SettingsHeader title="Profile" />
        <View style={s.centered}><Spinner color={v2.brand.red} /></View>
      </View>
    );
  }

  if (!profile) {
    return (
      <View style={s.root}>
        <SettingsHeader title="Profile" />
        <View style={s.centered}><EmptyState title="Profile unavailable" body="This profile isn't available." /></View>
      </View>
    );
  }

  const displayName = profile.display_name?.trim() || 'Seller';
  const verified = profile.is_verified_seller === true;

  if (isBlocked) {
    return (
      <View style={s.root}>
        <SettingsHeader title="Profile" />
        <View style={s.centered}>
          <View style={s.avatarRing}><View style={s.avatarFallback}><Text style={s.avatarInitials}>{getInitials(displayName)}</Text></View></View>
          <Text style={[textStyle('title'), s.blockedTitle]}>You&apos;ve blocked {displayName}</Text>
          <Text style={[textStyle('bodySm'), s.blockedBody]}>Their listings are hidden from your feed. Unblock to see this profile again.</Text>
          <Button label="Unblock" onPress={handleUnblock} loading={working} disabled={working} style={s.unblock} />
        </View>
      </View>
    );
  }

  const rep = deriveReputation(trustStats);
  const insufficientData = !trustStats || trustStats.seller_terminal_total < 1;

  return (
    <View style={s.root}>
      <SettingsHeader title="Profile" />
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.scroll}>
        {/* Identity */}
        <View style={s.identity}>
          <View style={s.avatarRing}>
            {avatarUrl ? (
              <Image source={{ uri: avatarUrl }} style={s.avatarImage} contentFit="cover" />
            ) : (
              <View style={s.avatarFallback}><Text style={s.avatarInitials}>{getInitials(displayName)}</Text></View>
            )}
          </View>
          <Text style={s.name} numberOfLines={1}>{displayName}</Text>
          {verified ? <View style={s.badgeWrap}><Badge label="Verified seller" tone="success" /></View> : null}
          {profile.bio ? <Text style={[textStyle('bodySm'), s.bio]}>{profile.bio}</Text> : null}
        </View>

        {/* Trust & activity */}
        <AccountSection title="Trust & activity">
          {statsUnavailable ? (
            <View style={s.unavailable}>
              <Text style={[textStyle('title'), s.unavailableTitle]}>Seller history unavailable</Text>
              <Text style={[textStyle('bodySm'), s.unavailableBody]}>We could not load this seller&apos;s history. This is not a record of zero sales.</Text>
              <Button label="Retry" variant="secondary" onPress={load} style={s.retry} />
            </View>
          ) : (
            <>
              <View style={s.hero}>
                <View style={s.heroLeft}>
                  <Text style={[textStyle('micro'), s.heroLabel]}>Transfer success rate</Text>
                  <Text style={s.heroValue}>{rep.successRate == null ? '—' : `${rep.successRate}%`}</Text>
                  {insufficientData ? <Text style={[textStyle('bodySm'), s.heroSub]}>No completed transfers yet</Text> : null}
                </View>
                <View style={s.heroRight}>
                  <Badge label={rep.label} tone={reputationTone(rep.tier)} />
                  <Text style={[textStyle('bodySm'), s.heroBlurb]} numberOfLines={2}>{rep.blurb}</Text>
                </View>
              </View>
              <View style={s.trustRows}>
                <TrustRow label="Completed sales" value={String(trustStats?.completed_sales ?? 0)} />
                <TrustRow label="Completed purchases" value={String(trustStats?.completed_purchases ?? 0)} />
                <TrustRow label="Active listings" value={String(trustStats?.active_listings ?? activeListings.length)} />
                <TrustRow label="Disputes opened" value={String(trustStats?.disputes_opened ?? 0)} />
                <TrustRow label="Disputes lost" value={String(trustStats?.disputes_lost ?? 0)} emphasize={!!trustStats && trustStats.disputes_lost > 0} />
                <TrustRow label="Member since" value={memberSince(trustStats?.member_since ?? profile.created_at)} last />
              </View>
            </>
          )}
        </AccountSection>

        {/* Active listings */}
        <AccountSection title={`Active listings (${activeListings.length})`}>
          {activeListings.length === 0 ? (
            <Text style={[textStyle('bodySm'), s.emptyListings]}>No active listings right now.</Text>
          ) : (
            <View style={s.listings}>{activeListings.map((l) => <ActiveListingRow key={l.id} listing={l} />)}</View>
          )}
        </AccountSection>

        {/* Safety actions (hidden on your own profile) */}
        {!isSelf ? (
          <View style={s.actions}>
            <Button label="Report user" variant="secondary" onPress={handleReport} block />
            <Button label="Block user" variant="destructive" onPress={handleBlock} disabled={working} block />
          </View>
        ) : null}
      </ScrollView>
    </View>
  );
}

const AVATAR = 88;
const RING = AVATAR + 8;

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  centered: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: v2.space.xl, gap: v2.space.md },

  scroll: { paddingHorizontal: v2.space.lg, paddingBottom: v2.space.xxxl },

  identity: { alignItems: 'center', paddingTop: v2.space.xl },
  avatarRing: {
    width: RING, height: RING, borderRadius: RING / 2,
    borderWidth: 1, borderColor: v2.brand.red, alignItems: 'center', justifyContent: 'center',
  },
  avatarImage: { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2 },
  avatarFallback: { width: AVATAR, height: AVATAR, borderRadius: AVATAR / 2, backgroundColor: v2.brand.redSoft, alignItems: 'center', justifyContent: 'center' },
  avatarInitials: { fontFamily: v2.font.bodyBold, fontSize: 28, color: v2.brand.red },
  name: { fontFamily: v2.font.bodyBold, fontSize: 22, color: v2.text.primary, marginTop: v2.space.md, textAlign: 'center' },
  badgeWrap: { marginTop: v2.space.sm },
  bio: { color: v2.text.muted, textAlign: 'center', marginTop: v2.space.md },

  unavailable: { paddingVertical: v2.space.md, gap: v2.space.sm, alignItems: 'flex-start' },
  unavailableTitle: { color: v2.text.primary },
  unavailableBody: { color: v2.text.muted },
  retry: { minWidth: 140, marginTop: v2.space.xs },

  hero: { flexDirection: 'row', alignItems: 'flex-start', gap: v2.space.lg, paddingVertical: v2.space.md },
  heroLeft: { flex: 1 },
  heroLabel: { color: v2.text.muted, marginBottom: v2.space.xs },
  heroValue: { fontFamily: v2.font.bodyBold, fontSize: 34, color: v2.text.primary, letterSpacing: -0.5 },
  heroSub: { color: v2.text.muted, marginTop: 2 },
  heroRight: { alignItems: 'flex-end', gap: v2.space.xs, maxWidth: 150 },
  heroBlurb: { color: v2.text.muted, textAlign: 'right' },

  trustRows: { borderTopWidth: 1, borderTopColor: v2.border.default },
  trustRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: v2.space.md },
  trustRowBorder: { borderBottomWidth: 1, borderBottomColor: v2.border.default },
  trustRowLabel: { color: v2.text.muted },
  trustRowValue: { color: v2.text.primary },
  trustRowValueEmphasize: { color: v2.status.error },

  listings: { gap: v2.space.sm },
  listingRow: { flexDirection: 'row', alignItems: 'center', gap: v2.space.md, borderWidth: 1, borderColor: v2.border.default, backgroundColor: v2.surface.surface, padding: v2.space.md },
  listingInfo: { flex: 1, minWidth: 0 },
  listingName: { color: v2.text.primary },
  listingVenue: { color: v2.text.muted, marginTop: 2 },
  listingRight: { alignItems: 'flex-end' },
  listingBidLabel: { color: v2.text.muted },
  listingBid: { color: v2.text.primary, marginTop: 1 },
  emptyListings: { color: v2.text.muted, paddingVertical: v2.space.md },

  actions: { marginTop: v2.space.xxl, gap: v2.space.md },

  blockedTitle: { color: v2.text.primary, textAlign: 'center' },
  blockedBody: { color: v2.text.muted, textAlign: 'center', maxWidth: 320 },
  unblock: { minWidth: 160, marginTop: v2.space.sm },
});
