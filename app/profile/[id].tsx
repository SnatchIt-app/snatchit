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
  ActivityIndicator,
  Alert,
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
import type { Listing, ProfileTrustStats, SellerReputationTier } from '@/src/types';

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

// ─── Reputation tier derivation ───────────────────────────────────────────────
// Sales-volume × success-rate × dispute-floor ladder. Sourced strictly from
// get_profile_trust_stats RPC fields — no hardcoded tiers.
//
//   Needs Review  — ANY lost dispute, OR insufficient success rate (< 95%)
//                   relative to completed sales floor (≥ 5).
//   New Seller    — < 5 completed sales (insufficient marketplace history).
//   Trusted       — 5+   sales · 95%+ success · 0 lost disputes
//   Top           — 25+  sales · 98%+ success · 0 lost disputes
//   Elite         — 100+ sales · 99%+ success · 0 lost disputes
//
// Edge cases:
//   • disputes_lost > 0 ALWAYS forces 'needs_review' regardless of sales
//     volume or rate — a single lost dispute is the trust floor.
//   • completed_sales < 5 → new_seller regardless of rate.
//   • denominator zero → rate treated as 0% (caller already gates
//     "No completed transfers yet" copy for new_seller).
function deriveReputation(stats: ProfileTrustStats | null): {
  tier:        SellerReputationTier;
  label:       string;
  blurb:       string;
  successRate: number | null;
} {
  if (!stats) {
    return {
      tier: 'new_seller', label: 'New Seller',
      blurb: 'No completed transfers yet', successRate: null,
    };
  }

  const sales = stats.completed_sales;
  const denom = stats.seller_terminal_total;
  const num   = stats.seller_terminal_successful;
  const rate  = denom > 0 ? num / denom : 0;
  const ratePct = denom > 0 ? Math.round(rate * 100) : null;

  // Any lost dispute → trust floor. Highest precedence after no-data.
  if (stats.disputes_lost > 0) {
    return {
      tier: 'needs_review', label: 'Needs Review',
      blurb: `${stats.disputes_lost} lost dispute${stats.disputes_lost === 1 ? '' : 's'}${ratePct == null ? '' : ` · ${ratePct}% success`}`,
      successRate: ratePct,
    };
  }

  // Insufficient history → new seller.
  if (sales < 5) {
    return {
      tier: 'new_seller', label: 'New Seller',
      blurb: sales === 0 ? 'No completed transfers yet' : `${sales} of 5 sales toward Trusted`,
      successRate: ratePct,
    };
  }

  // Elite — 100+ sales, 99%+ success
  if (sales >= 100 && rate >= 0.99) {
    return {
      tier: 'elite', label: 'Elite Seller',
      blurb: `${sales} sales · ${ratePct}% transfer success`,
      successRate: ratePct,
    };
  }
  // Top — 25+ sales, 98%+ success
  if (sales >= 25 && rate >= 0.98) {
    return {
      tier: 'top', label: 'Top Seller',
      blurb: `${sales} sales · ${ratePct}% transfer success`,
      successRate: ratePct,
    };
  }
  // Trusted — 5+ sales, 95%+ success
  if (sales >= 5 && rate >= 0.95) {
    return {
      tier: 'trusted', label: 'Trusted Seller',
      blurb: `${sales} sales · ${ratePct}% transfer success`,
      successRate: ratePct,
    };
  }
  // Has volume but rate below tier floor → review
  return {
    tier: 'needs_review', label: 'Needs Review',
    blurb: `${ratePct}% transfer success`,
    successRate: ratePct,
  };
}

const TIER_COLORS: Record<SellerReputationTier, { bg: string; fg: string; border: string }> = {
  elite:        { bg: 'rgba(168,85,247,0.10)',  fg: '#A855F7', border: 'rgba(168,85,247,0.45)' },
  top:          { bg: 'rgba(34,197,94,0.10)',   fg: '#22C55E', border: 'rgba(34,197,94,0.45)'  },
  trusted:      { bg: 'rgba(59,130,246,0.10)',  fg: '#3B82F6', border: 'rgba(59,130,246,0.45)' },
  needs_review: { bg: 'rgba(239,68,68,0.10)',   fg: '#EF4444', border: 'rgba(239,68,68,0.45)'  },
  new_seller:   { bg: 'rgba(148,163,184,0.10)', fg: '#94A3B8', border: 'rgba(148,163,184,0.45)' },
};

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

// ─── Trust & Activity row (compact, label + value) ─────────────────────────
function TrustRow({
  label,
  value,
  emphasize,
  last,
}: {
  label:      string;
  value:      string;
  emphasize?: boolean;
  last?:      boolean;
}) {
  return (
    <View style={[s.trustRow, !last && s.trustRowBorder]}>
      <Text style={s.trustRowLabel}>{label}</Text>
      <Text style={[s.trustRowValue, emphasize && s.trustRowValueEmphasize]}>
        {value}
      </Text>
    </View>
  );
}

// ─── Screen ────────────────────────────────────────────────────────────────

export default function PublicProfileScreen() {
  const { user } = useAuth();
  const { id } = useLocalSearchParams<{ id: string }>();
  const sellerId = id ?? '';

  const isSelf = !!user?.id && user.id === sellerId;

  const [loading,        setLoading]        = useState(true);
  const [profile,        setProfile]        = useState<PublicProfile | null>(null);
  const [avatarUrl,      setAvatarUrl]      = useState<string | null>(null);
  const [trustStats,     setTrustStats]     = useState<ProfileTrustStats | null>(null);
  const [activeListings, setActiveListings] = useState<Listing[]>([]);
  const [isBlocked,      setIsBlocked]      = useState(false);
  const [working,        setWorking]        = useState(false);

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
      setTrustStats(null);
      setActiveListings([]);
      setLoading(false);
      return;
    }

    // 3. Trust + activity stats — single RPC round-trip.
    //    Returns counts only; never amounts/Stripe IDs/emails.
    const { data: statsRow, error: statsErr } = await supabase
      .rpc('get_profile_trust_stats', { p_user_id: sellerId });
    if (statsErr) {
      console.warn('[profile] get_profile_trust_stats error:', statsErr.message);
      setTrustStats(null);
    } else {
      // RPC returns array (TABLE function) — take first row.
      const row = Array.isArray(statsRow) ? statsRow[0] : statsRow;
      setTrustStats((row as ProfileTrustStats) ?? null);
    }

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

  // ── Header bar (shared) ──────────────────────────────────────────────────
  // No three-dot overflow menu: moderation actions live in the dedicated
  // "Report User" / "Block User" buttons at the bottom of the profile.
  // A right-side spacer keeps the title visually centered.
  const TopBar = (
    <View style={s.topBar}>
      <Pressable onPress={() => router.back()} style={s.iconBtn} hitSlop={8}>
        <Text style={s.backArrow}>←</Text>
      </Pressable>
      <Text style={s.topTitle}>Profile</Text>
      <View style={s.iconBtn} />
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
  // Badge = admin-reviewed proof of ownership (is_verified_seller), matching
  // every other surface. Stripe onboarding alone must NOT show "Verified".
  const verified    = profile.is_verified_seller === true;

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

        {/* ── Trust & Activity ────────────────────────────────────────
             Premium marketplace trust panel (Airbnb/StubHub/StockX pattern).
             Hero row: Transfer Success Rate + Seller Reputation tier.
             Detail rows: counts only — never amounts. */}
        {(() => {
          const rep = deriveReputation(trustStats);
          const tone = TIER_COLORS[rep.tier];
          const insufficientData = !trustStats || trustStats.seller_terminal_total < 1;
          return (
            <>
              <Text style={s.sectionHead}>TRUST & ACTIVITY</Text>
              <View style={s.trustCard}>
                {/* Hero row */}
                <View style={s.trustHero}>
                  <View style={{ flex: 1 }}>
                    <Text style={s.trustHeroLabel}>Transfer Success Rate</Text>
                    <Text style={s.trustHeroValue}>
                      {rep.successRate == null ? '—' : `${rep.successRate}%`}
                    </Text>
                    {insufficientData && (
                      <Text style={s.trustHeroSub}>No completed transfers yet</Text>
                    )}
                  </View>
                  <View style={[
                    s.tierPill,
                    { backgroundColor: tone.bg, borderColor: tone.border },
                  ]}>
                    <Text style={s.tierPillKicker}>Seller Reputation</Text>
                    <Text style={[s.tierPillLabel, { color: tone.fg }]}>{rep.label}</Text>
                    <Text style={s.tierPillBlurb}>{rep.blurb}</Text>
                  </View>
                </View>

                {/* Detail rows */}
                <View style={s.trustDivider} />
                <TrustRow
                  label="Completed Sales"
                  value={String(trustStats?.completed_sales ?? 0)}
                />
                <TrustRow
                  label="Completed Purchases"
                  value={String(trustStats?.completed_purchases ?? 0)}
                />
                <TrustRow
                  label="Active Listings"
                  value={String(trustStats?.active_listings ?? activeListings.length)}
                />
                <TrustRow
                  label="Disputes Opened"
                  value={String(trustStats?.disputes_opened ?? 0)}
                />
                <TrustRow
                  label="Disputes Lost"
                  value={String(trustStats?.disputes_lost ?? 0)}
                  emphasize={!!trustStats && trustStats.disputes_lost > 0}
                />
                <TrustRow
                  label="Member Since"
                  value={memberSince(trustStats?.member_since ?? profile.created_at)}
                  last
                />
              </View>
            </>
          );
        })()}

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

  // Trust & Activity (premium marketplace pattern — Airbnb/StubHub/StockX)
  trustCard: {
    marginHorizontal: spacing.lg, marginTop: spacing.sm,
    backgroundColor: colors.bgCard, borderRadius: radius.lg,
    borderWidth: 1, borderColor: colors.border,
    paddingHorizontal: spacing.lg, paddingVertical: spacing.md,
    ...shadow.card,
  },
  trustHero: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    paddingBottom: spacing.md,
  },
  trustHeroLabel: {
    color: colors.textDim, fontSize: fontSize.xs, fontWeight: '600',
    letterSpacing: 0.4, textTransform: 'uppercase', marginBottom: 4,
  },
  trustHeroValue: {
    color: colors.text, fontSize: 32, fontWeight: '800', letterSpacing: -0.5,
  },
  trustHeroSub: {
    color: colors.textMuted, fontSize: fontSize.xs, marginTop: 2,
  },
  tierPill: {
    minWidth: 130,
    borderWidth: 1, borderRadius: radius.md,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.sm,
    alignItems: 'flex-start',
  },
  tierPillKicker: {
    color: colors.textDim, fontSize: 10, fontWeight: '700',
    letterSpacing: 0.6, textTransform: 'uppercase', marginBottom: 2,
  },
  tierPillLabel: {
    fontSize: fontSize.md, fontWeight: '800', letterSpacing: -0.2,
  },
  tierPillBlurb: {
    color: colors.textMuted, fontSize: fontSize.xs, marginTop: 2, lineHeight: 16,
  },
  trustDivider: {
    height: 1, backgroundColor: colors.border, marginBottom: spacing.xs,
  },
  trustRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingVertical: spacing.sm + 2,
  },
  trustRowBorder: {
    borderBottomWidth: 1, borderBottomColor: colors.border,
  },
  trustRowLabel: {
    color: colors.textMuted, fontSize: fontSize.sm, fontWeight: '500',
  },
  trustRowValue: {
    color: colors.text, fontSize: fontSize.sm, fontWeight: '700',
  },
  trustRowValueEmphasize: {
    color: colors.error,
  },

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
