/**
 * src/screens/PlaceBidScreen.tsx — Place a bid (V2).
 *
 * Reached from Listing Detail (`/bid/[id]`). PRESENTATION rebuilt on the V2
 * system; the BID PATH is unchanged: the same current-bid fetch and fresh floor,
 * the same +$increment stepper and quick-add chips, the same money breakdown from
 * src/lib/money.ts, the same F-5 account-deletion guard (own kernel.identity_ext
 * row), the same `bids` insert (the DB trigger moves current_bid), and the same
 * "Bid placed" → back. No bid math, minimum, increment or all-in logic changed;
 * the pure arithmetic now lives in src/lib/bid/bidEntry.ts and is tested.
 *
 * This is NOT the Bids tab — it is the entry surface where a bid is chosen and
 * committed, and it deliberately shares the conversion language of Listing Detail
 * and Checkout: a comparison, a focused amount, a breakdown, one sticky action.
 */

import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { APP_CONFIG } from '@/src/config/app';
import {
  bidPriceLines,
  bidTotalLabel,
  canPlaceBid,
  minNextBid,
  quickAdd,
  stepDown,
  stepUp,
} from '@/src/lib/bid/bidEntry';
import { Button, IconButton, Spinner, StickyBar } from '@/src/components/ui';
import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';

type Props = { id: string };

/** Whole-dollar bid display, e.g. "$80". Bid amounts are whole dollars. */
function fmt$(n: number) { return `$${Math.round(n).toLocaleString('en-US')}`; }

const MIN_INCREMENT = APP_CONFIG.MIN_BID_INCREMENT;
const QUICK_CHIPS = [5, 10, 25] as const;

export default function PlaceBidScreen({ id }: Props) {
  const { user } = useAuth();
  const insets = useSafeAreaInsets();

  const [listing,    setListing]    = useState<Listing | null>(null);
  const [loading,    setLoading]    = useState(true);
  const [submitting, setSubmitting] = useState(false);

  // Fetch current_bid so the floor is always fresh
  useEffect(() => {
    supabase
      .from('listings')
      .select('current_bid, starting_bid, event_name, venue, ends_at')
      .eq('id', id)
      .single()
      .then(({ data }) => {
        if (data) {
          setListing(data as Listing);
          setSelectedBid(data.current_bid + MIN_INCREMENT);
        }
        setLoading(false);
      });
  }, [id]);

  const minimumBid = minNextBid(listing?.current_bid ?? 0, MIN_INCREMENT);
  const [selectedBid, setSelectedBid] = useState(minimumBid);

  // Keep selectedBid in sync if listing loads after state initialises
  useEffect(() => {
    if (listing) setSelectedBid(listing.current_bid + MIN_INCREMENT);
  }, [listing?.current_bid]);

  function decrease() { setSelectedBid((p) => stepDown(p, minimumBid, MIN_INCREMENT)); }
  function increase() { setSelectedBid((p) => stepUp(p, MIN_INCREMENT)); }
  function addQuick(n: number) { setSelectedBid((p) => quickAdd(p, n)); }

  const lines = bidPriceLines(selectedBid);

  async function handleConfirm() {
    // Guard: must be signed in
    if (!user) {
      Alert.alert('Not signed in', 'Please sign in to place a bid.');
      router.replace('/(auth)/login');
      return;
    }

    // Guard: bid must meet minimum
    if (!canPlaceBid(selectedBid, minimumBid)) {
      Alert.alert('Bid too low', `Minimum bid is ${fmt$(minimumBid)}.`);
      return;
    }

    setSubmitting(true);

    // F-5 live-rail acquisition guard (OR-17; FR-9; DSM §3.2 F-5): a signed-in
    // user whose account deletion is pending must not place a live bid. Reads the
    // caller's OWN kernel.identity_ext row (owner-scoped SELECT, migration 077).
    // Pre-Phase-2 the kernel schema is not exposed and the probe errors → treated
    // as not-pending (the DB sweep's re-check is the hard wall).
    try {
      const { data: ext } = await supabase
        .schema('kernel')
        .from('identity_ext')
        .select('deletion_state')
        .eq('identity_id', user.id)
        .maybeSingle();
      if (ext?.deletion_state === 'DELETION_PENDING') {
        setSubmitting(false);
        Alert.alert(
          'Account deletion pending',
          'Your account deletion request is pending. Withdraw it in Settings to place new bids.',
        );
        return;
      }
    } catch {
      // pre-Phase-2 world or transient probe failure — proceed; the DB wall holds
    }

    // Insert bid row — the DB trigger updates listings.current_bid atomically
    const { error } = await supabase.from('bids').insert({
      listing_id: id,
      bidder_id:  user.id,
      amount:     selectedBid,
    });

    setSubmitting(false);

    if (error) {
      Alert.alert('Bid failed', error.message);
      return;
    }

    // Bid placed — go back to the listing. Checkout only opens after the auction
    // ends (via "Pay now" on the listing).
    Alert.alert(
      'Bid placed',
      `Your bid of ${fmt$(selectedBid)} is in. If you win, you'll pay ${bidTotalLabel(selectedBid)} total (includes the 10% service fee).`,
      [{ text: 'OK', onPress: () => router.back() }],
    );
  }

  if (loading) {
    return (
      <View style={[s.root, s.centered]}>
        <Spinner color={v2.brand.red} />
      </View>
    );
  }

  const atFloor = selectedBid <= minimumBid;

  return (
    <View style={s.root}>
      {/* ── Header ──────────────────────────────────────────── */}
      <View style={[s.header, { paddingTop: insets.top + v2.space.sm }]}>
        <IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('displaySm'), s.headerTitle]} accessibilityRole="header">Place bid</Text>
        <View style={s.headerSpacer} />
      </View>

      <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        {listing?.event_name ? (
          <Text style={[textStyle('title'), s.eventName]} numberOfLines={2}>{listing.event_name}</Text>
        ) : null}
        {listing?.venue ? (
          <Text style={[textStyle('bodySm'), s.venue]} numberOfLines={1}>{listing.venue}</Text>
        ) : null}

        {/* ── Current vs your bid ───────────────────────────── */}
        <View style={s.compare}>
          <View style={s.compareSide}>
            <Text style={[textStyle('micro'), s.compareLabel]}>Current bid</Text>
            <Text style={[textStyle('price'), s.compareAmt]} numberOfLines={1}>{fmt$(listing?.current_bid ?? 0)}</Text>
          </View>
          <View style={s.compareDivider} />
          <View style={s.compareSide}>
            <Text style={[textStyle('micro'), s.compareLabel]}>Your bid</Text>
            <Text style={[textStyle('price'), s.compareAmt, s.compareYours]} numberOfLines={1}>{fmt$(selectedBid)}</Text>
          </View>
        </View>

        {/* ── Amount (the focus) ────────────────────────────── */}
        <View style={s.amountBlock}>
          <Text style={s.bigAmount} accessibilityLabel={`Your bid ${fmt$(selectedBid)}`}>{fmt$(selectedBid)}</Text>
          <Text style={[textStyle('bodySm'), s.stepHint]}>
            +{fmt$(MIN_INCREMENT)} per step · min {fmt$(minimumBid)}
          </Text>

          <View style={s.stepper}>
            <Pressable
              style={[s.stepBtn, atFloor && s.stepBtnOff]}
              onPress={decrease}
              disabled={atFloor}
              accessibilityRole="button"
              accessibilityLabel="Lower bid"
              accessibilityState={{ disabled: atFloor }}
              hitSlop={6}
            >
              <Text style={s.stepGlyph} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>{'−'}</Text>
            </Pressable>
            <Text style={[textStyle('price'), s.stepVal]} numberOfLines={1}>{fmt$(selectedBid)}</Text>
            <Pressable
              style={s.stepBtn}
              onPress={increase}
              accessibilityRole="button"
              accessibilityLabel="Raise bid"
              hitSlop={6}
            >
              <Text style={s.stepGlyph} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>+</Text>
            </Pressable>
          </View>

          <View style={s.quickRow}>
            {QUICK_CHIPS.map((n) => (
              <Pressable
                key={n}
                style={s.quick}
                onPress={() => addQuick(n)}
                accessibilityRole="button"
                accessibilityLabel={`Add ${fmt$(n)}`}
                hitSlop={4}
              >
                <Text style={[textStyle('label'), s.quickText]}>+{fmt$(n)}</Text>
              </Pressable>
            ))}
          </View>
        </View>

        {/* ── Breakdown ─────────────────────────────────────── */}
        <View style={s.breakdown}>
          <View style={s.breakRow}>
            <Text style={[textStyle('body'), s.breakLabel]}>Your bid</Text>
            <Text style={[textStyle('body'), s.breakVal]}>{lines.bid}</Text>
          </View>
          <View style={s.breakRow}>
            <Text style={[textStyle('body'), s.breakLabel]}>Service fee ({Math.round(APP_CONFIG.BUYER_FEE_RATE * 100)}%)</Text>
            <Text style={[textStyle('body'), s.breakVal]}>{lines.fee}</Text>
          </View>
          <View style={s.breakDivider} />
          <View style={s.breakRow}>
            <Text style={[textStyle('title'), s.breakTotalLabel]}>You pay if you win</Text>
            <Text style={[textStyle('price'), s.breakTotalVal]} numberOfLines={1}>{lines.total} total</Text>
          </View>
          <Text style={[textStyle('bodySm'), s.breakNote]}>Only charged if you win the auction.</Text>
        </View>
      </ScrollView>

      {/* ── Sticky action ───────────────────────────────────── */}
      <StickyBar
        left={
          <View>
            <Text style={[textStyle('micro'), s.stickyKicker]}>If you win</Text>
            <Text style={[textStyle('price'), s.stickyTotal]} numberOfLines={1}>{lines.total}</Text>
          </View>
        }
      >
        <Button label="Place bid" onPress={handleConfirm} loading={submitting} disabled={submitting} block />
      </StickyBar>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  centered: { alignItems: 'center', justifyContent: 'center' },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: v2.space.md,
    paddingBottom: v2.space.sm,
    borderBottomWidth: 1,
    borderBottomColor: v2.border.default,
  },
  headerTitle: { color: v2.text.primary },
  headerSpacer: { width: 44 },

  body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, paddingBottom: v2.space.xxl },
  eventName: { color: v2.text.primary },
  venue: { color: v2.text.muted, marginTop: 2 },

  compare: {
    flexDirection: 'row',
    marginTop: v2.space.xl,
    borderWidth: 1,
    borderColor: v2.border.default,
  },
  compareSide: { flex: 1, alignItems: 'center', paddingVertical: v2.space.lg },
  compareDivider: { width: 1, backgroundColor: v2.border.default },
  compareLabel: { color: v2.text.muted, marginBottom: v2.space.xs },
  compareAmt: { color: v2.text.primary },
  compareYours: { color: v2.brand.red },

  amountBlock: { alignItems: 'center', marginTop: v2.space.xxl },
  bigAmount: {
    fontFamily: v2.font.bodyBold,
    fontSize: 56,
    lineHeight: 64,
    color: v2.brand.red,
    fontVariant: ['tabular-nums'],
  },
  stepHint: { color: v2.text.muted, marginTop: v2.space.xs, marginBottom: v2.space.lg },

  stepper: { flexDirection: 'row', alignItems: 'center', gap: v2.space.md, alignSelf: 'stretch' },
  stepBtn: {
    width: 52, height: 52,
    borderWidth: 1, borderColor: v2.border.strong,
    alignItems: 'center', justifyContent: 'center',
  },
  stepBtnOff: { opacity: 0.35 },
  stepGlyph: { color: v2.text.primary, fontSize: 26, lineHeight: 30 },
  stepVal: { flex: 1, textAlign: 'center', color: v2.text.primary },

  quickRow: { flexDirection: 'row', gap: v2.space.sm, alignSelf: 'stretch', marginTop: v2.space.md },
  quick: {
    flex: 1, minHeight: 40, paddingVertical: v2.space.xs,
    borderWidth: 1, borderColor: v2.brand.red,
    backgroundColor: v2.brand.redSoft,
    alignItems: 'center', justifyContent: 'center',
  },
  quickText: { color: v2.brand.red },

  breakdown: {
    marginTop: v2.space.xxl,
    borderWidth: 1, borderColor: v2.border.default,
    backgroundColor: v2.surface.surface,
    padding: v2.space.lg,
  },
  breakRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: v2.space.sm },
  breakLabel: { color: v2.text.secondary },
  breakVal: { color: v2.text.primary },
  breakDivider: { height: 1, backgroundColor: v2.border.default, marginVertical: v2.space.sm },
  breakTotalLabel: { color: v2.text.primary },
  breakTotalVal: { color: v2.brand.red },
  breakNote: { color: v2.text.muted, marginTop: v2.space.sm },

  stickyKicker: { color: v2.text.muted },
  stickyTotal: { color: v2.text.primary, marginTop: 2 },
});
