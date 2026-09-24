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
 * PREMIUM BATCH 2 (CFT-201/203/205/207). The stepper and quick-add keys share
 * the product's press response; Place bid reads "Submitting bid…" while the
 * insert is in flight and a ref-held lock drops a second tap; "You're leading"
 * is said only after the server accepted the bid AND a fresh read confirms the
 * position; amounts format through the one dollar formatter.
 *
 * This is NOT the Bids tab — it is the entry surface where a bid is chosen and
 * committed, and it deliberately shares the conversion language of Listing Detail
 * and Checkout: a comparison, a focused amount, a breakdown, one sticky action.
 */

import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { useSingleFlight } from '@/src/hooks/useSingleFlight';
import { APP_CONFIG } from '@/src/config/app';
import {
  bidOutcome,
  bidOutcomeCopy,
  bidPriceLines,
  canPlaceBid,
  minNextBid,
  quickAdd,
  stepDown,
  stepUp,
} from '@/src/lib/bid/bidEntry';
import { hapticConfirm } from '@/src/lib/feedback/haptics';
import { rowMeta } from '@/src/lib/listing/feedRowState';
import { formatDollars } from '@/src/lib/money';
import { NameText } from '@/src/components/NameText';
import ScreenState from '@/src/components/ScreenState';
import { Button, IconButton, Spinner, Tappable } from '@/src/components/ui';
import { classifyLoadFailure, type LoadFailureKind } from '@/src/lib/ui/loadState';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle, MAX_DISPLAY_FONT_SCALE } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';
import type { Listing } from '@/src/types';
import { useTopInset } from '@/src/lib/nav/navInsets';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

type Props = { id: string };

/** Whole-dollar bid display, e.g. "$80". Bid amounts are whole dollars. */
const fmt$ = formatDollars;

const MIN_INCREMENT = APP_CONFIG.MIN_BID_INCREMENT;
const QUICK_CHIPS = [5, 10, 25] as const;

export default function PlaceBidScreen({ id }: Props) {
  const { user } = useAuth();
  // F-SELL-2: the badge-aware top inset (status bar + the SANDBOX badge on sandbox builds; production unchanged).
  const topPad = useTopInset();
  const insets = useSafeAreaInsets();
  // Appearance: every colour on this screen comes from the resolved palette (light or dark).
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);

  const [listing,    setListing]    = useState<Listing | null>(null);
  const [loading,    setLoading]    = useState(true);
  const [loadError,  setLoadError]  = useState<LoadFailureKind | null>(null);
  const [submitting, setSubmitting] = useState(false);
  // One submission at a time (CFT-205): a second tap that lands before the
  // re-render disables the button is dropped here, not by React state.
  const flight = useSingleFlight();

  const { isOffline } = useNetworkStatus();
  const offlineRef = useRef(isOffline);
  offlineRef.current = isOffline;

  const minimumBid = minNextBid(listing?.current_bid ?? 0, MIN_INCREMENT);
  const [selectedBid, setSelectedBid] = useState(minimumBid);

  // Fetch current_bid so the floor is always fresh.
  // F-BID-1: a read that fails — resolved-with-error, thrown, or a row that is not there — must never fall
  // through to the form. Without a listing the floor comes from `?? 0`, so the screen would state a minimum
  // it invented and a "Current bid" of $0 on the screen where a bid is committed. A thrown read used to skip
  // the handler entirely and leave the spinner up for good.
  const load = useCallback(async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('listings')
        // V3: the header restates the listing (date, venue, whole-listing quantity) and the
        // market column needs the bid count to avoid claiming a "current bid" nobody placed.
        // Same authorized row, same policy — only the column list widened.
        .select('current_bid, starting_bid, event_name, venue, ends_at, event_date, event_time, quantity, ticket_type, bid_count')
        .eq('id', id)
        .single();
      if (error || !data) {
        setLoadError(classifyLoadFailure(error, offlineRef.current));
        setLoading(false);
        return;
      }
      setListing(data as Listing);
      setSelectedBid(data.current_bid + MIN_INCREMENT);
      setLoadError(null);
      setLoading(false);
    } catch (err) {
      setLoadError(classifyLoadFailure(err, offlineRef.current));
      setLoading(false);
    }
  }, [id]);

  useEffect(() => { void load(); }, [load]);

  // Keep selectedBid in sync if listing loads after state initialises
  useEffect(() => {
    if (listing) setSelectedBid(listing.current_bid + MIN_INCREMENT);
  }, [listing?.current_bid]);

  function decrease() { setSelectedBid((p) => stepDown(p, minimumBid, MIN_INCREMENT)); }
  function increase() { setSelectedBid((p) => stepUp(p, MIN_INCREMENT)); }
  function addQuick(n: number) { setSelectedBid((p) => quickAdd(p, n)); }

  const lines = bidPriceLines(selectedBid);

  function handleConfirm() {
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

    // A skipped run means a submission is already in flight: nothing to do.
    flight.run(() => submitBid(user.id, selectedBid)).catch(() => {
      setSubmitting(false);
      Alert.alert('Bid failed', 'Something went wrong. Please try again.');
    });
  }

  async function submitBid(userId: string, amount: number) {
    setSubmitting(true);
    try {
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
          .eq('identity_id', userId)
          .maybeSingle();
        if (ext?.deletion_state === 'DELETION_PENDING') {
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
        bidder_id:  userId,
        amount,
      });

      if (error) {
        Alert.alert('Bid failed', error.message);
        return;
      }

      // Accepted by the server: the insert trigger rejects any bid that is not
      // above the current bid, so nothing below this line runs on a rejection.
      // Only now the restrained confirmation (CFT-202), and a fresh read to tell
      // "leading" from "already outbid" (CFT-203; source A-17). The alert is the
      // haptic's visible equivalent.
      hapticConfirm();
      const { data: fresh } = await supabase
        .from('listings')
        .select('current_bid')
        .eq('id', id)
        .maybeSingle();
      const freshBid: number | null = typeof fresh?.current_bid === 'number' ? fresh.current_bid : null;
      const copy = bidOutcomeCopy(bidOutcome(amount, freshBid), amount, freshBid);

      // Go back to the listing. Checkout only opens after the auction ends (via
      // "Pay now" on the listing).
      Alert.alert(copy.title, copy.body, [{ text: 'OK', onPress: () => router.back() }]);
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return (
      <View style={[s.root, s.centered]}>
        <Spinner color={palette.brand.redText} />
      </View>
    );
  }

  // F-BID-1: no listing means no floor, so there is no form to show — the shared state owns the wording.
  if (loadError || !listing) {
    return (
      <View style={s.root}>
        <ScreenState state={loadError ?? 'error'} onRetry={load} />
      </View>
    );
  }

  const atFloor = selectedBid <= minimumBid;

  return (
    <View style={s.root}>
      {/* ── Header ──────────────────────────────────────────── */}
      <View style={[s.header, { paddingTop: topPad + v2.space.sm }]}>
        <IconButton glyph="back" onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('displaySm'), s.headerTitle]} accessibilityRole="header">Place bid</Text>
        <View style={s.headerSpacer} />
      </View>

      <ScrollView contentContainerStyle={s.body} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        {/* V3 (pkg2 ①): the listing is RESTATED, not re-sold — the name in the display voice,
            the dated line home and search also use, and the quantity, because the bid buys the
            whole listing. */}
        {listing?.event_name ? (
          <NameText token="nameOrder" maxLines={2} style={s.eventName}>{listing.event_name}</NameText>
        ) : null}
        {listing?.venue && listing?.event_date ? (
          <Text style={[textStyle('bodySm'), s.venue]} numberOfLines={1}>
            {rowMeta({
              eventDate: listing.event_date, eventTime: listing.event_time ?? '',
              venue: listing.venue, quantity: listing.quantity ?? 1,
              ticketType: listing.ticket_type ?? '', bidCount: listing.bid_count,
            }).meta1}
          </Text>
        ) : null}
        {listing?.quantity && listing?.ticket_type ? (
          <Text style={[textStyle('bodySm'), s.venue]} numberOfLines={1}>
            {`${listing.quantity} × ${listing.ticket_type}${listing.quantity > 1 ? ' · sold together' : ''}`}
          </Text>
        ) : null}

        {/* De-dup (owner 2026-09-23): each fact once. The market price is ONE line; the buyer's
            total appears exactly once, beside the Place bid action in the sticky bar. */}
        {/* R-1 (owner 2026-09-23): the market price in the SAME UNITS as the editable bid — the
            underlying bid, never a fee-inclusive figure beside a fee-exclusive input. The
            summary below supplies the fee and the total. */}
        <Text style={[textStyle('bodySm'), s.marketLine]} numberOfLines={1}>
          {`${(listing?.bid_count ?? 0) > 0 ? 'Current bid' : 'Starting bid'} · ${fmt$(listing?.current_bid ?? 0)}`}
        </Text>

        {/* ── The editable bid (the focus), clearly labelled ── */}
        <View style={s.amountBlock}>
          <Text style={[textStyle('label'), s.bidLabel]}>Your bid</Text>

          {/* Stepper and quick-add keys carry the product's press response
              (CFT-201): they are Tappable, not bare Pressables. */}
          <View style={s.stepper}>
            <Tappable
              style={[s.stepBtn, atFloor && s.stepBtnOff]}
              onPress={decrease}
              disabled={atFloor}
              accessibilityRole="button"
              accessibilityLabel="Lower bid"
              accessibilityState={{ disabled: atFloor }}
              hitSlop={6}
            >
              <Text style={s.stepGlyph} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>{'−'}</Text>
            </Tappable>
            <Text
              style={s.bigAmount}
              numberOfLines={1}
              accessibilityLabel={`Your bid ${fmt$(selectedBid)}`}
            >
              {fmt$(selectedBid)}
            </Text>
            <Tappable
              style={s.stepBtn}
              onPress={increase}
              accessibilityRole="button"
              accessibilityLabel="Raise bid"
              hitSlop={6}
            >
              <Text style={s.stepGlyph} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>+</Text>
            </Tappable>
          </View>

          <View style={s.quickRow}>
            {QUICK_CHIPS.map((n) => (
              <Tappable
                key={n}
                wrapperStyle={s.quickWrap}
                style={s.quick}
                onPress={() => addQuick(n)}
                accessibilityRole="button"
                accessibilityLabel={`Add ${fmt$(n)}`}
                hitSlop={4}
              >
                <Text style={[textStyle('label'), s.quickText]}>+{fmt$(n)}</Text>
              </Tappable>
            ))}
          </View>

          {/* Minimum guidance at the point of entry — validation says the rest. */}
          <Text style={[textStyle('bodySm'), s.stepHint]}>{`Minimum ${fmt$(minimumBid)}`}</Text>
        </View>

        {/* The one payment sentence, OUTSIDE the summary (owner 2026-09-23). Verified in
            source: nothing charges on a win — the winner's route is pay_now → winner checkout →
            payControl's Pay, the only control that moves the buyer's money. */}
        <Text style={[textStyle('bodySm'), s.breakNote]}>
          Placing a bid doesn&apos;t charge you. If you win, you pay the total at checkout.
        </Text>
      </ScrollView>

      {/* ── Summary + action (owner's final direction, 2026-09-23) ──
          Exactly three rows from the existing calculation — Bid / Fee / Total, Total strongest —
          and the plain "Place bid" button DIRECTLY below them. No side total, no "all-in", no
          caption. The bid repeating here is intentional. */}
      <View testID="bid-footer" style={[s.footer, { paddingBottom: v2.space.md + insets.bottom }]}>
        <View testID="bid-summary" style={s.summary}>
          <View style={s.summaryRow}>
            <Text style={[textStyle('body'), s.summaryLabel]}>Bid</Text>
            <Text style={[textStyle('body'), s.summaryValue]} numberOfLines={1}>{lines.bid}</Text>
          </View>
          <View style={s.summaryRow}>
            <Text style={[textStyle('body'), s.summaryLabel]}>{`Fee (${Math.round(APP_CONFIG.BUYER_FEE_RATE * 100)}%)`}</Text>
            <Text style={[textStyle('body'), s.summaryValue]} numberOfLines={1}>{lines.fee}</Text>
          </View>
          <View testID="bid-summary-total" style={[s.summaryRow, s.summaryTotalRow]}>
            <Text style={[textStyle('title'), s.summaryTotalLabel]}>Total</Text>
            <Text
              style={[textStyle('price'), s.summaryTotalValue]}
              numberOfLines={1}
              maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}
            >
              {lines.total}
            </Text>
          </View>
        </View>
        <Button
          label="Place bid"
          pendingLabel="Submitting bid…"
          onPress={handleConfirm}
          loading={submitting}
          disabled={submitting}
          block
        />
      </View>
    </View>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
  root: { flex: 1, backgroundColor: p.surface.canvas },
  centered: { alignItems: 'center', justifyContent: 'center' },

  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: v2.space.md,
    paddingBottom: v2.space.sm,
    borderBottomWidth: 1,
    borderBottomColor: p.border.default,
  },
  headerTitle: { color: p.text.primary },
  headerSpacer: { width: 44 },

  body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, paddingBottom: v2.space.xxl },
  eventName: { color: p.text.primary },
  venue: { color: p.text.muted, marginTop: 2 },

  // De-dup: the market price is one quiet line; the buyer's own bid is the focus below it.
  marketLine: { color: p.text.muted, marginTop: v2.space.md },

  amountBlock: { alignItems: 'center', marginTop: v2.space.xxl },
  bidLabel: { color: p.text.secondary, alignSelf: 'flex-start' },
  bigAmount: {
    flex: 1,
    textAlign: 'center',
    fontFamily: v2.font.bodyBold,
    fontSize: 56,
    lineHeight: 64,
    color: p.brand.redText,
    fontVariant: ['tabular-nums'],
  },
  stepHint: { color: p.text.muted, marginTop: v2.space.xs, marginBottom: v2.space.lg },

  stepper: { flexDirection: 'row', alignItems: 'center', gap: v2.space.md, alignSelf: 'stretch' },
  stepBtn: {
    width: 52, height: 52,
    borderWidth: 1, borderColor: p.border.strong,
    alignItems: 'center', justifyContent: 'center',
  },
  stepBtnOff: { opacity: 0.35 },
  stepGlyph: { color: p.text.primary, fontSize: 26, lineHeight: 30 },

  quickRow: { flexDirection: 'row', gap: v2.space.sm, alignSelf: 'stretch', marginTop: v2.space.md },
  quickWrap: { flex: 1 },
  quick: {
    minHeight: 40, paddingVertical: v2.space.xs,
    borderWidth: 1, borderColor: p.brand.red,
    backgroundColor: p.brand.redSoft,
    alignItems: 'center', justifyContent: 'center',
  },
  quickText: { color: p.brand.redText },

  breakNote: { color: p.text.muted, marginTop: v2.space.xl },

  // The footer: the summary directly above the action, no gap, no second amount.
  footer: {
    paddingHorizontal: v2.space.lg,
    paddingTop: v2.space.md,
    gap: v2.space.md,
    backgroundColor: p.surface.surface,
    borderTopWidth: 1,
    borderTopColor: p.border.strong,
  },
  summary: { gap: v2.space.xs },
  summaryRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', gap: v2.space.md },
  summaryLabel: { color: p.text.secondary },
  summaryValue: { color: p.text.primary, fontVariant: ['tabular-nums'] },
  // Total is the strongest row: heavier label, the price face, a hairline above.
  summaryTotalRow: { borderTopWidth: 1, borderTopColor: p.border.default, paddingTop: v2.space.xs, marginTop: 2 },
  summaryTotalLabel: { color: p.text.primary },
  summaryTotalValue: { color: p.text.primary, fontVariant: ['tabular-nums'] },

});
}
