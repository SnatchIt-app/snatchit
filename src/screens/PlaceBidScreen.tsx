/**
 * src/screens/PlaceBidScreen.tsx
 *
 * UI-only bid entry screen.
 * Shows: current bid, big selected amount, +/- stepper,
 *        quick-add chips, price breakdown, confirm button.
 *
 * "Confirm Bid" currently logs the amount and navigates back.
 * Wire up real Supabase insert in the next sprint.
 *
 * Props:
 *   id — listing uuid (passed from route wrapper)
 */

import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { APP_CONFIG } from '@/src/config/app';
import { buyerFeeCents, buyerTotalCents, dollarsToCents, formatCents } from '@/src/lib/money';
import { colors, fontSize, radius, spacing } from '@/src/theme';
import type { Listing } from '@/src/types';

// ─── Props ────────────────────────────────────────────────────────────────────

type Props = { id: string };

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmt$(n: number) { return `$${Math.round(n).toLocaleString('en-US')}`; }

const BUYER_FEE_RATE = APP_CONFIG.BUYER_FEE_RATE;
const MIN_INCREMENT  = APP_CONFIG.MIN_BID_INCREMENT;
const QUICK_CHIPS    = [5, 10, 25] as const;

// ─── Screen ───────────────────────────────────────────────────────────────────

export default function PlaceBidScreen({ id }: Props) {
  const { user } = useAuth();

  const [listing,     setListing]     = useState<Listing | null>(null);
  const [loading,     setLoading]     = useState(true);
  const [submitting,  setSubmitting]  = useState(false);

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
          // Initialise selected bid to current_bid + MIN_INCREMENT
          setSelectedBid(data.current_bid + MIN_INCREMENT);
        }
        setLoading(false);
      });
  }, [id]);

  const minimumBid = (listing?.current_bid ?? 0) + MIN_INCREMENT;
  const [selectedBid, setSelectedBid] = useState(minimumBid);

  // Keep selectedBid in sync if listing loads after state initialises
  useEffect(() => {
    if (listing) setSelectedBid(listing.current_bid + MIN_INCREMENT);
  }, [listing?.current_bid]);

  function decrease() { setSelectedBid(p => Math.max(minimumBid, p - MIN_INCREMENT)); }
  function increase() { setSelectedBid(p => p + MIN_INCREMENT); }
  function addQuick(n: number) { setSelectedBid(p => p + n); }

  // 10/10 fee model, canonical integer-cent math (src/lib/money.ts):
  // a bid is the seller's BASE price; the buyer's all-in commitment is
  // base + 10% service fee, shown before the bid is submitted.
  const feeCents   = buyerFeeCents(dollarsToCents(selectedBid));
  const totalCents = buyerTotalCents(dollarsToCents(selectedBid));

  async function handleConfirm() {
    // Guard: must be signed in
    if (!user) {
      Alert.alert('Not signed in', 'Please sign in to place a bid.');
      router.replace('/(auth)/login');
      return;
    }

    // Guard: bid must meet minimum
    if (selectedBid < minimumBid) {
      Alert.alert('Bid too low', `Minimum bid is ${fmt$(minimumBid)}.`);
      return;
    }

    setSubmitting(true);

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

    // Bid placed successfully — go back to the listing.
    // Checkout is only available after the auction ends (via the "Pay Now" button on the listing).
    Alert.alert('Bid placed!', `Your bid of ${fmt$(selectedBid)} is in. If you win, you'll pay ${formatCents(totalCents)} total (includes the 10% service fee).`, [
      { text: 'OK', onPress: () => router.back() },
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  if (loading) {
    return (
      <SafeAreaView style={s.centered}>
        <ActivityIndicator color={colors.primary} size="large" />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={s.safe}>

      {/* ── Header ──────────────────────────────────────── */}
      <View style={s.topBar}>
        <TouchableOpacity onPress={() => router.back()} style={s.backBtn} activeOpacity={0.7}>
          <Text style={s.backArrow}>←</Text>
        </TouchableOpacity>
        <Text style={s.topTitle}>Place Bid</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled">

        {/* ── Event name ──────────────────────────────────── */}
        {listing?.event_name ? (
          <Text style={s.eventName} numberOfLines={1}>{listing.event_name}</Text>
        ) : null}

        {/* 1. BID COMPARISON ─────────────────────────────── */}
        <View style={s.compareCard}>
          <View style={s.compareSide}>
            <Text style={s.compareLabel}>CURRENT BID</Text>
            <Text style={s.compareAmt}>{fmt$(listing?.current_bid ?? 0)}</Text>
          </View>
          <View style={s.compareDivider} />
          <View style={s.compareSide}>
            <Text style={s.compareLabel}>YOUR BID</Text>
            <Text style={[s.compareAmt, { color: colors.primary }]}>{fmt$(selectedBid)}</Text>
          </View>
        </View>

        {/* 2. YOUR BID CARD ───────────────────────────────── */}
        <View style={s.card}>
          <Text style={s.cardTitle}>YOUR BID</Text>

          {/* Big amount */}
          <Text style={s.bigAmt}>{fmt$(selectedBid)}</Text>
          <Text style={s.stepHint}>
            +{fmt$(MIN_INCREMENT)} per step · min {fmt$(minimumBid)}
          </Text>

          {/* Stepper */}
          <View style={s.stepperRow}>
            <TouchableOpacity
              style={[s.stepBtn, selectedBid <= minimumBid && s.stepBtnOff]}
              onPress={decrease} disabled={selectedBid <= minimumBid} activeOpacity={0.75}>
              <Text style={s.stepGlyph}>−</Text>
            </TouchableOpacity>
            <Text style={s.stepVal}>{fmt$(selectedBid)}</Text>
            <TouchableOpacity style={s.stepBtn} onPress={increase} activeOpacity={0.75}>
              <Text style={s.stepGlyph}>+</Text>
            </TouchableOpacity>
          </View>

          {/* Quick chips */}
          <View style={s.chipRow}>
            {QUICK_CHIPS.map(n => (
              <TouchableOpacity key={n} style={s.chip} onPress={() => addQuick(n)} activeOpacity={0.75}>
                <Text style={s.chipText}>+{fmt$(n)}</Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>

        {/* 3. PRICE BREAKDOWN ─────────────────────────────── */}
        <View style={s.card}>
          <Text style={s.cardTitle}>PRICE BREAKDOWN</Text>

          <View style={s.breakRow}>
            <Text style={s.breakLabel}>Your bid</Text>
            <Text style={s.breakVal}>{fmt$(selectedBid)}</Text>
          </View>
          <View style={s.breakRow}>
            <Text style={s.breakLabel}>Service fee ({Math.round(BUYER_FEE_RATE * 100)}%)</Text>
            <Text style={s.breakVal}>{formatCents(feeCents)}</Text>
          </View>
          <View style={s.breakDivider} />
          <View style={s.breakRow}>
            <Text style={[s.breakLabel, s.totalLabel]}>You pay if you win</Text>
            <Text style={[s.breakVal, s.totalVal]}>{formatCents(totalCents)} total</Text>
          </View>
          <Text style={s.breakNote}>* Only charged if you win the auction.</Text>
        </View>

        {/* 4. TRUST LINE ───────────────────────────────────── */}
        <Text style={s.trustLine}>🔒  Secure · Only charged if you win</Text>

        <View style={{ height: 100 }} />
      </ScrollView>

      {/* ── Sticky CTA ──────────────────────────────────────── */}
      <View style={s.stickyBar}>
        <TouchableOpacity
          style={[s.ctaBtn, submitting && s.ctaBtnBusy]}
          onPress={handleConfirm}
          disabled={submitting}
          activeOpacity={0.88}
        >
          {submitting
            ? <ActivityIndicator color={colors.text} />
            : <Text style={s.ctaText}>⚡ Place bid · {formatCents(totalCents)} total</Text>
          }
        </TouchableOpacity>
      </View>

    </SafeAreaView>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  safe:    { flex:1, backgroundColor: colors.bg },
  centered:{ flex:1, justifyContent:'center', alignItems:'center', backgroundColor: colors.bg },

  topBar:   { flexDirection:'row', alignItems:'center', justifyContent:'space-between',
              paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
              borderBottomWidth:1, borderBottomColor: colors.border },
  backBtn:  { width:44, height:44, justifyContent:'center' },
  backArrow:{ color: colors.text, fontSize: fontSize.xl, fontWeight:'600' },
  topTitle: { color: colors.text, fontSize: fontSize.md, fontWeight:'700' },

  body:      { padding: spacing.lg },
  eventName: { fontSize: fontSize.md, fontWeight:'700', color: colors.textMuted,
               marginBottom: spacing.md, textAlign:'center' },

  // Comparison card
  compareCard:    { flexDirection:'row', backgroundColor: colors.bgCard,
                    borderRadius: radius.lg, borderWidth:1, borderColor: colors.border,
                    marginBottom: spacing.md, overflow:'hidden' },
  compareSide:    { flex:1, alignItems:'center', paddingVertical: spacing.lg },
  compareDivider: { width:1, backgroundColor: colors.border, marginVertical: spacing.md },
  compareLabel:   { fontSize: fontSize.xs, fontWeight:'700', color: colors.textDim,
                    letterSpacing:1.2, textTransform:'uppercase', marginBottom:4 },
  compareAmt:     { fontSize: fontSize.xl, fontWeight:'800', color: colors.text },

  // Generic card
  card:      { backgroundColor: colors.bgCard, borderRadius: radius.lg,
               borderWidth:1, borderColor: colors.border, padding: spacing.lg,
               marginBottom: spacing.md },
  cardTitle: { fontSize: fontSize.xs, fontWeight:'700', color: colors.textDim,
               letterSpacing:1.4, textTransform:'uppercase', marginBottom: spacing.md },

  bigAmt:   { fontSize: 44, fontWeight:'900', color: colors.primary,
              textAlign:'center', marginBottom:4 },
  stepHint: { fontSize: fontSize.xs, color: colors.textMuted,
              textAlign:'center', marginBottom: spacing.lg },

  stepperRow: { flexDirection:'row', alignItems:'center', gap: spacing.sm, marginBottom: spacing.md },
  stepBtn:    { width:52, height:52, borderRadius: radius.md, backgroundColor: colors.bgInput,
                borderWidth:1, borderColor: colors.borderInput, alignItems:'center', justifyContent:'center' },
  stepBtnOff: { opacity:0.3 },
  stepGlyph:  { color: colors.text, fontSize:26, fontWeight:'600', lineHeight:30 },
  stepVal:    { flex:1, textAlign:'center', fontSize: fontSize.lg, fontWeight:'800', color: colors.text },

  chipRow: { flexDirection:'row', gap: spacing.sm, justifyContent:'center' },
  chip:    { flex:1, paddingVertical: spacing.sm, borderRadius: radius.xl,
             borderWidth:1, borderColor: colors.primary, backgroundColor: colors.primarySoft,
             alignItems:'center' },
  chipText:{ color: colors.primary, fontSize: fontSize.sm, fontWeight:'700' },

  breakRow:     { flexDirection:'row', justifyContent:'space-between',
                  alignItems:'center', marginBottom: spacing.sm },
  breakLabel:   { fontSize: fontSize.sm, color: colors.textMuted },
  breakVal:     { fontSize: fontSize.sm, color: colors.text, fontWeight:'600' },
  breakDivider: { height:1, backgroundColor: colors.border, marginVertical: spacing.sm },
  totalLabel:   { color: colors.text, fontWeight:'700', fontSize: fontSize.md },
  totalVal:     { color: colors.primary, fontWeight:'800', fontSize: fontSize.md },
  breakNote:    { marginTop: spacing.sm, fontSize: fontSize.xs, color: colors.textDim },

  trustLine: { textAlign:'center', color: colors.textDim, fontSize: fontSize.xs,
               marginBottom: spacing.md },

  stickyBar: { paddingHorizontal: spacing.lg, paddingVertical: spacing.md,
               paddingBottom: spacing.lg, borderTopWidth:1, borderTopColor: colors.border,
               backgroundColor: colors.bg },
  ctaBtn: {
    backgroundColor: colors.primary, borderRadius: radius.md,
    paddingVertical: spacing.md + 2, alignItems:'center',
    shadowColor: colors.primary, shadowOffset:{ width:0, height:4 },
    shadowOpacity:0.4, shadowRadius:10, elevation:6,
  },
  ctaBtnBusy: { opacity: 0.65 },
  ctaText: { color: colors.text, fontSize: fontSize.md, fontWeight:'800', letterSpacing:0.5 },
});
