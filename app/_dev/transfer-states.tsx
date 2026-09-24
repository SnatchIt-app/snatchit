/**
 * app/_dev/transfer-states.tsx — the synthetic transfer-state gallery (owner 2026-09-24).
 *
 * WHY IT EXISTS. The sandbox holds no `expired` or `held` transfer rows, so the buyer's expired
 * board and the seller's held board cannot be reached on a device through real data. The owner
 * authorised a sandbox-only, READ-ONLY gallery that renders the SAME components the real screens
 * render — `src/components/transfer/TransferStateBlocks.tsx` — from clearly labelled synthetic
 * props, in both appearances and at any text size the phone is set to.
 *
 * WHAT A PASS PROVES, AND WHAT IT DOES NOT. A gallery pass proves rendering with supplied props:
 * layout, contrast in both appearances, wrapping at large text. It proves nothing about whether a
 * real `expired` / `held` / `reversed` status reaches the screen through the read path; that data
 * path stays open until the sandbox holds such rows (owner decisions D5 / D6).
 *
 * NOT REACHABLE IN PRODUCTION. The route renders nothing but a redirect unless this is a paired
 * sandbox build (`IS_SANDBOX_BUILD`, a compile-time verdict on the bundled env) or a `__DEV__`
 * bundle — so a production build cannot display it through navigation or a deep link. The only
 * entry is a Settings row that itself renders only in a sandbox build.
 *
 * NO WRITES, NO ACTIONS. Nothing here imports the client, reads a server, opens a dialog, or
 * offers a control that confirms, sends, reports, pays or releases anything. The one control is
 * the appearance switch, which writes the device-local preference the Settings screen writes.
 */

import { Redirect } from 'expo-router';
import { useMemo, type ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import {
  BuyerClosedBlock,
  BuyerSellerSentBlock,
  SellerClosedBlock,
  SellerReversedBlock,
  SellerSentBlock,
} from '@/src/components/transfer/TransferStateBlocks';
import { IS_SANDBOX_BUILD } from '@/src/config/envGuard';
import { SELLER_ORDER_CLOSED_COPY } from '@/src/lib/transfer/transferState';
import { useAppearancePreference, useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

declare const __DEV__: boolean;

export const SYNTHETIC_LABEL = 'Synthetic fixture — not a sandbox row';

/** A future timestamp so the "release decision" and "review deadline" lines read as live. */
const FUTURE = '2026-10-02T19:30:00Z';
const PAST = '2026-09-20T10:00:00Z';

export interface TransferStateFixture {
  id: string;
  label: string;
  role: 'buyer' | 'seller';
  /** Which approved cell / combination this exercises. */
  covers: string;
  render: () => ReactNode;
}

/**
 * The approved status / refund / hold combinations (A's wording table, 2026-09-24), each rendered
 * through the real block with synthetic props. Twelve cases; nothing derived from another.
 */
export const TRANSFER_STATE_FIXTURES: TransferStateFixture[] = [
  { id: 'buyer-expired-full-refund', label: 'Buyer · expired · refund confirmed in full', role: 'buyer', covers: 'A 2a + refund full',
    render: () => <BuyerClosedBlock status="expired" refund={{ status: 'refunded', amount_refunded_cents: 12000, refunded_at: PAST, total: 12000 }} /> },
  { id: 'buyer-expired-no-row', label: 'Buyer · expired · no refund recorded yet', role: 'buyer', covers: 'A 2a + policy line',
    render: () => <BuyerClosedBlock status="expired" refund={null} /> },
  { id: 'buyer-reversed-partial', label: 'Buyer · reversed · partial refund', role: 'buyer', covers: 'A 2c + refund partial',
    render: () => <BuyerClosedBlock status="reversed" refund={{ status: null, amount_refunded_cents: 6000, refunded_at: null, total: 12000 }} /> },
  { id: 'buyer-reversed-pending', label: 'Buyer · reversed · nothing recorded', role: 'buyer', covers: 'A 2c + pending line',
    render: () => <BuyerClosedBlock status="reversed" refund={null} /> },
  { id: 'buyer-reversed-recorded-no-amount', label: 'Buyer · reversed · refund recorded, no amount', role: 'buyer', covers: 'A 2c + NULL amount > "refunded"',
    render: () => <BuyerClosedBlock status="reversed" refund={{ status: 'refunded', amount_refunded_cents: null, refunded_at: PAST, total: 12000 }} /> },
  { id: 'buyer-sent-deadline', label: 'Buyer · seller marked sent · review deadline', role: 'buyer', covers: 'B-5 / F-22 deadline from auto_release_at',
    render: () => <BuyerSellerSentBlock autoReleaseAt={FUTURE} /> },
  { id: 'buyer-sent-no-deadline', label: 'Buyer · seller marked sent · no deadline from the server', role: 'buyer', covers: 'B-5 omitted when absent',
    render: () => <BuyerSellerSentBlock autoReleaseAt={null} /> },
  { id: 'seller-expired', label: 'Seller · order expired (window closed)', role: 'seller', covers: 'A 2b — no payout ever moved',
    render: () => <SellerClosedBlock title={SELLER_ORDER_CLOSED_COPY.expired.title} body={SELLER_ORDER_CLOSED_COPY.expired.body} /> },
  { id: 'seller-reversed', label: 'Seller · payout reversed', role: 'seller', covers: 'A 2d — reversed > payout_released_at',
    render: () => <SellerReversedBlock /> },
  { id: 'seller-sent-held-date', label: 'Seller · marked sent · payout held with a date', role: 'seller', covers: 'A hold rule: held AND payout_hold_until',
    render: () => <SellerSentBlock payoutReviewStatus="held" payoutHoldUntil={FUTURE} autoReleaseAt={null} releaseCountdown={null} /> },
  { id: 'seller-sent-held-no-date', label: 'Seller · marked sent · held, no date from the server', role: 'seller', covers: 'A hold rule fallback',
    render: () => <SellerSentBlock payoutReviewStatus="held" payoutHoldUntil={null} autoReleaseAt={null} releaseCountdown={null} /> },
  { id: 'seller-sent-manual-review', label: 'Seller · marked sent · manual review', role: 'seller', covers: 'manual_review line',
    render: () => <SellerSentBlock payoutReviewStatus="manual_review" payoutHoldUntil={null} autoReleaseAt={null} releaseCountdown={null} /> },
  { id: 'seller-sent-release-line', label: 'Seller · marked sent · release decision time', role: 'seller', covers: 'A 2e release DECISION, not a payout',
    render: () => <SellerSentBlock payoutReviewStatus={null} payoutHoldUntil={null} autoReleaseAt={FUTURE} releaseCountdown="7d 12h" /> },
  { id: 'seller-sent-window-passed', label: 'Seller · marked sent · review window passed', role: 'seller', covers: 'window passed, payout pending',
    render: () => <SellerSentBlock payoutReviewStatus={null} payoutHoldUntil={null} autoReleaseAt={PAST} releaseCountdown="Expired" /> },
];

const APPEARANCES: { key: 'system' | 'light' | 'dark'; label: string }[] = [
  { key: 'system', label: 'System' },
  { key: 'light', label: 'Light' },
  { key: 'dark', label: 'Dark' },
];

export default function TransferStatesGallery() {
  if (!(IS_SANDBOX_BUILD || __DEV__)) return <Redirect href="/(tabs)/home" />;
  return <Gallery />;
}

function Gallery() {
  const { palette, scheme } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { preference, setPreference } = useAppearancePreference();
  return (
    <SafeAreaView style={s.root}>
      <ScrollView contentContainerStyle={s.content}>
        <Text style={[textStyle('displaySm'), s.title]} accessibilityRole="header">Transfer states — synthetic gallery</Text>
        <Text style={[textStyle('bodySm'), s.note]}>
          Every card below renders the real transfer-state block from synthetic props. A pass here proves
          rendering in this appearance and at this text size — nothing about live data.
        </Text>
        <View style={s.switchRow} accessibilityRole="radiogroup">
          {APPEARANCES.map((a) => (
            <Pressable
              key={a.key}
              onPress={() => setPreference(a.key)}
              accessibilityRole="radio"
              accessibilityState={{ checked: preference === a.key }}
              accessibilityLabel={`Appearance: ${a.label}`}
              style={[s.switch, preference === a.key && s.switchOn]}
            >
              <Text style={[textStyle('label'), preference === a.key ? s.switchOnText : s.switchText]}>{a.label}</Text>
            </Pressable>
          ))}
          <Text style={[textStyle('micro'), s.note]}>{`Rendering: ${scheme}`}</Text>
        </View>
        {TRANSFER_STATE_FIXTURES.map((f) => (
          <View key={f.id} style={s.card}>
            <Text style={[textStyle('micro'), s.synthetic]}>{SYNTHETIC_LABEL}</Text>
            <Text style={[textStyle('label'), s.cardLabel]}>{f.label}</Text>
            <Text style={[textStyle('micro'), s.covers]}>{`Covers: ${f.covers}`}</Text>
            {f.render()}
          </View>
        ))}
        <View style={{ height: v2.space.xxxl }} />
      </ScrollView>
    </SafeAreaView>
  );
}

function makeStyles(p: Palette) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: p.surface.canvas },
    content: { padding: v2.space.lg, gap: v2.space.md },
    title: { color: p.text.primary },
    note: { color: p.text.muted },
    switchRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: v2.space.sm },
    switch: { paddingVertical: v2.space.xs, paddingHorizontal: v2.space.md, borderWidth: 1, borderColor: p.border.control },
    switchOn: { borderColor: p.brand.red, backgroundColor: p.brand.redSoft },
    switchText: { color: p.text.secondary },
    switchOnText: { color: p.text.primary },
    card: { gap: v2.space.xs },
    synthetic: { color: p.status.warning },
    cardLabel: { color: p.text.primary },
    covers: { color: p.text.muted },
  });
}
