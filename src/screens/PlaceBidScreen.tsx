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
  bidPriceLinesV3,
  canPlaceBid,
  minNextBid,
  quickAdd,
  stepDown,
  stepUp,
} from '@/src/lib/bid/bidEntry';
import { hapticConfirm } from '@/src/lib/feedback/haptics';
import { rowMeta } from '@/src/lib/listing/feedRowState';
import { formatDollars, formatDollarsV3 } from '@/src/lib/money';
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

type Props = {
  id: string;
  /**
   * DEVELOPMENT RENDERING ONLY (owner 2026-09-24). When supplied, the screen paints this
   * listing instead of reading one, so the approved boards can be compared against what the
   * REAL component renders without a session or a sandbox row. Only `app/_dev/v3-screens.tsx`
   * passes it, and that route redirects unless the bundle is a sandbox or __DEV__ build; the
   * real `/bid/[id]` route never passes it, so the production path is byte-for-byte the read
   * path above. It short-circuits the READ only — the bid path, the floor arithmetic and the
   * insert are untouched.
   */
  fixture?: Listing;
};

/**
 * V3 money display (owner 2026-09-24): the approved boards show cents on every amount,
 * so displayed figures read "$95.00". The bid itself is still chosen and submitted in
 * whole dollars — `selectedBid` and the `bids` insert are untouched; only the string is
 * formatted with cents. `fmtStep$` keeps the whole-dollar form for the +$5 / +$10 / +$25
 * keys and the "$5 steps" hint, which the boards also draw without cents.
 */
const fmt$ = formatDollarsV3;
const fmtStep$ = formatDollars;

const MIN_INCREMENT = APP_CONFIG.MIN_BID_INCREMENT;
const QUICK_CHIPS = [5, 10, 25] as const;

/**
 * What the bidder is told when the `bids` insert comes back with an error (V3, 2026-09-24).
 *
 * It used to be the server's own `error.message` — a raw PostgREST/Postgres string ("new row violates
 * row-level security policy for table \"bids\"", a trigger's RAISE text, a transport failure's
 * message) shown verbatim in an Alert on the screen where money is committed. That is not product
 * copy, it is not written for a bidder, and it can disclose schema and policy names.
 *
 * The wording is deliberately silent on whether the bid landed, because the client does not know.
 * supabase-js returns transport failures in the same `error` channel as a server rejection, so an
 * error here is consistent with (i) the server rejecting the insert and (ii) the row committing and
 * the response being lost. "Bid failed" would assert (i); "try again" alone would invite a second
 * bid on top of a first that may already be in. So it says only what is true — no confirmation came
 * back — and points at the one place that settles it, the listing's own current bid, which the
 * insert trigger moves atomically.
 *
 * There is no KNOWN-error branch above this in `submitBid`: the only mapped case is the F-5 deletion
 * guard, which returns BEFORE the insert. So this is the sole unknown-case fallback, not a
 * replacement for specific copy.
 */
const BID_UNCONFIRMED_COPY = {
  title: "We couldn't confirm your bid",
  body: "We didn't get a confirmation back for it. Check the listing's current bid before bidding again, in case it did go through.",
} as const;

export default function PlaceBidScreen({ id, fixture }: Props) {
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
    if (fixture) {
      setListing(fixture);
      setSelectedBid(fixture.current_bid + MIN_INCREMENT);
      setLoadError(null);
      setLoading(false);
      return;
    }
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
  }, [id, fixture]);

  useEffect(() => { void load(); }, [load]);

  // Keep selectedBid in sync if listing loads after state initialises
  useEffect(() => {
    if (listing) setSelectedBid(listing.current_bid + MIN_INCREMENT);
  }, [listing?.current_bid]);

  function decrease() { setSelectedBid((p) => stepDown(p, minimumBid, MIN_INCREMENT)); }
  function increase() { setSelectedBid((p) => stepUp(p, MIN_INCREMENT)); }
  function addQuick(n: number) { setSelectedBid((p) => quickAdd(p, n)); }

  const lines = bidPriceLinesV3(selectedBid);

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
        // The raw server string never reaches the bidder; see BID_UNCONFIRMED_COPY for why the
        // wording claims neither outcome.
        Alert.alert(BID_UNCONFIRMED_COPY.title, BID_UNCONFIRMED_COPY.body);
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
        <Spinner color={palette.brand.red} />
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
        <IconButton glyph="back" chip onPress={() => router.back()} accessibilityLabel="Back" />
        <Text style={[textStyle('screenTitle'), s.headerTitle]} accessibilityRole="header">Place bid</Text>
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

        {/* V3 (pkg8-bid-*): the market price is a LABELLED ROW between hairlines — the label
            left, the amount right in the price face — not a middot-joined sentence. The label
            still depends on the data: "Current bid" only when a bid exists, else "Starting bid".
            De-dup (owner 2026-09-23) holds: the market price appears once, in the same units as
            the editable bid, and the buyer's total appears once, in the summary below. */}
        <View style={[s.rule, s.ruleTop]} />
        <View style={s.marketRow}>
          <Text style={[textStyle('body'), s.marketLabel]}>
            {(listing?.bid_count ?? 0) > 0 ? 'Current bid' : 'Starting bid'}
          </Text>
          <Text style={[textStyle('price'), s.marketValue]} numberOfLines={1}>
            {fmt$(listing?.current_bid ?? 0)}
          </Text>
        </View>
        <View style={s.rule} />

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
              <Text style={[s.stepGlyph, s.stepGlyphMinus]} maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}>{'−'}</Text>
            </Tappable>
            <Text
              style={s.bigAmount}
              numberOfLines={1}
              adjustsFontSizeToFit
              minimumFontScale={0.6}
              maxFontSizeMultiplier={MAX_DISPLAY_FONT_SCALE}
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

          {/* The board puts the guidance directly under the amount and the quick keys under
              that, and states the step size as well as the floor. */}
          <Text style={[textStyle('bodySm'), s.stepHint]}>
            {`Minimum ${fmt$(minimumBid)} · ${fmtStep$(MIN_INCREMENT)} steps`}
          </Text>

          <View style={s.quickRow}>
            {QUICK_CHIPS.map((n) => (
              <Tappable
                key={n}
                wrapperStyle={s.quickWrap}
                style={s.quick}
                onPress={() => addQuick(n)}
                accessibilityRole="button"
                accessibilityLabel={`Add ${fmtStep$(n)}`}
                hitSlop={4}
              >
                <Text style={[textStyle('action'), s.quickText]}>+{fmtStep$(n)}</Text>
              </Tappable>
            ))}
          </View>
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
          size="lg"
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

  // V3: no rule under the header — the board separates the header from the content with
  // space, and the first hairline on the screen is the one above "Current bid".
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: v2.space.md,
    paddingBottom: v2.space.sm,
  },
  headerTitle: { color: p.text.primary },
  headerSpacer: { width: 44 },

  body: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.lg, paddingBottom: v2.space.xxl },
  eventName: { color: p.text.primary },
  venue: { color: p.text.secondary, marginTop: 2 },

  // The row supplies its own vertical padding, so only the FIRST hairline adds space above
  // itself — the board closes the second one up under the row rather than leaving a second gap.
  rule: { height: 1, backgroundColor: p.border.default },
  ruleTop: { marginTop: v2.space.lg },
  marketRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: v2.space.md,
    paddingVertical: v2.space.lg,
  },
  marketLabel: { color: p.text.primary },
  marketValue: { color: p.text.primary, fontSize: 24, lineHeight: 28 },

  amountBlock: { alignItems: 'center', marginTop: v2.space.xl },
  bidLabel: { color: p.text.secondary, alignSelf: 'flex-start' },

  // The amount is the loudest thing on the screen and it is TEXT-coloured, not brand red:
  // red is the action, and an amount painted in it reads as a button.
  bigAmount: {
    flex: 1,
    textAlign: 'center',
    fontFamily: v2.font.bodyBold,
    fontSize: 54,
    lineHeight: 64,
    color: p.text.primary,
    fontVariant: ['tabular-nums'],
  },
  stepHint: { color: p.text.muted, marginTop: v2.space.md, textAlign: 'center' },

  // V3 steppers: tall rounded keys on a transparent fill, flanking the amount.
  stepper: { flexDirection: 'row', alignItems: 'center', gap: v2.space.md, alignSelf: 'stretch', marginTop: v2.space.lg },
  stepBtn: {
    width: 62, height: 104,
    borderRadius: v2.radius.md,
    borderWidth: 1, borderColor: p.border.control,
    alignItems: 'center', justifyContent: 'center',
  },
  stepBtnOff: { opacity: 0.35 },
  stepGlyph: { color: p.text.primary, fontSize: 30, lineHeight: 34 },
  // The board draws the minus quieter than the plus: lowering is the secondary direction.
  stepGlyphMinus: { color: p.text.muted },

  // V3 quick-add keys: neutral rounded keys, not red rectangles. Red is reserved for the
  // one committing action, so an increment key can never read as "Place bid".
  quickRow: { flexDirection: 'row', gap: v2.space.md, alignSelf: 'stretch', marginTop: v2.space.lg },
  quickWrap: { flex: 1 },
  quick: {
    minHeight: 56,
    borderRadius: v2.radius.md,
    borderWidth: 1, borderColor: p.border.control,
    alignItems: 'center', justifyContent: 'center',
  },
  quickText: { color: p.text.primary },

  breakNote: { color: p.text.secondary, marginTop: v2.space.xl },

  // The footer: the filled summary panel, then the action directly below it.
  footer: {
    paddingHorizontal: v2.space.lg,
    paddingTop: v2.space.md,
    gap: v2.space.md,
    backgroundColor: p.surface.canvas,
  },
  // Square by design: the board fills this panel and leaves its corners sharp, which is
  // why `radius.none` is still a value in the scale.
  summary: {
    gap: v2.space.xs,
    backgroundColor: p.surface.surface,
    borderRadius: v2.radius.none,
    paddingHorizontal: v2.space.lg,
    paddingVertical: v2.space.lg,
  },
  summaryRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline', gap: v2.space.md },
  summaryLabel: { color: p.text.secondary },
  summaryValue: { color: p.text.primary, fontVariant: ['tabular-nums'] },
  // Total is the strongest row: heavier label, the price face, a hairline above.
  summaryTotalRow: { borderTopWidth: 1, borderTopColor: p.border.default, paddingTop: v2.space.md, marginTop: v2.space.xs },
  summaryTotalLabel: { color: p.text.primary },
  summaryTotalValue: { color: p.text.primary, fontVariant: ['tabular-nums'], fontSize: 26, lineHeight: 30 },

});
}
