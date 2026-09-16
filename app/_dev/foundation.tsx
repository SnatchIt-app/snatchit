/**
 * app/_dev/foundation.tsx — Product V2 Tier-0 foundation preview.
 *
 * A development-only gallery for inspecting the foundation before any Tier-1
 * screen is redesigned. It is the smallest preview mechanism this repository can
 * carry: there is no Storybook here, and adding one would mean adding
 * dependencies this pass is not taking.
 *
 * NOT REACHABLE IN PRODUCTION. The route renders nothing but a redirect unless
 * `__DEV__` is true, so a release build cannot display it even if someone deep
 * links to the path.
 *
 * It deliberately shows the ugly cases first: the artwork shapes that break the
 * current product are the reason the media system exists.
 */

import { Redirect } from 'expo-router';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { EventMedia } from '@/src/components/media/EventMedia';
import { MEDIA_SLOTS, slotHeight, type MediaSlotName } from '@/src/lib/media/slots';
import {
  allInPrice,
  asCents,
  centsFromDollars,
  formatMinor,
  priceLadder,
} from '@/src/lib/pricing/allIn';
import { provenanceLabel, type InventoryKind } from '@/src/lib/pricing/provenance';
import { brandFontsActive, fontFamily } from '@/src/theme/fonts';
import * as v2 from '@/src/theme/v2';

/**
 * The visual QA matrix. These are shapes, not real events: nothing here is
 * presented as genuine inventory. Paths that do not exist exercise the fallback,
 * which is exactly what we want to look at.
 */
const QA_ASSETS = [
  { label: 'Portrait flyer 4:5 (v2)', path: 'qa/portrait-4x5.jpg', contract: 'v2' as const },
  { label: 'Story flyer 9:16 (v2)', path: 'qa/portrait-9x16.jpg', contract: 'v2' as const },
  { label: 'Square artwork 1:1 (v2)', path: 'qa/square.jpg', contract: 'v2' as const },
  { label: 'Legacy landscape 16:9', path: 'qa/legacy-16x9.jpg', contract: 'legacy' as const },
  { label: 'Ultrawide banner 3:1', path: 'qa/wide-3x1.jpg', contract: 'legacy' as const },
  { label: 'Very dark artwork', path: 'qa/dark.jpg', contract: 'v2' as const },
  { label: 'Very bright artwork', path: 'qa/bright.jpg', contract: 'v2' as const },
  { label: 'Text-heavy poster', path: 'qa/text-heavy.jpg', contract: 'v2' as const },
  { label: 'Low-resolution legacy', path: 'qa/tiny.jpg', contract: 'legacy' as const },
  { label: 'Missing image (fallback)', path: null, contract: 'v2' as const },
  { label: 'Unsafe path (fallback)', path: '../secret.jpg', contract: 'v2' as const },
];

const TITLES = {
  short: 'III Points',
  long: 'III Points Saturday General Admission with Extended Lineup and Late Set',
};

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={[styles.h2, { fontFamily: fontFamily('display') }]}>{title}</Text>
      {children}
    </View>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={styles.row}>
      <Text style={[styles.micro, { fontFamily: fontFamily('bodyMedium') }]}>{label}</Text>
      {children}
    </View>
  );
}

export default function FoundationPreview() {
  if (!__DEV__) return <Redirect href="/(tabs)/home" />;

  const slotNames = Object.keys(MEDIA_SLOTS) as MediaSlotName[];

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.body}>
        <Text style={[styles.h1, { fontFamily: fontFamily('display') }]}>V2 Foundation</Text>
        <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
          Development preview. Brand fonts active: {String(brandFontsActive())}. If false, this
          renders in the system face and the type below is not what ships.
        </Text>

        <Section title="Type scale">
          {(
            [
              ['displayXl', 'Find your night'],
              ['displayLg', 'Where the city is going'],
              ['displayMd', 'Section heading'],
              ['displaySm', 'Card heading'],
              ['title', TITLES.short],
              ['body', 'Body copy sits at fifteen points with comfortable leading.'],
              ['bodySm', 'Secondary copy, thirteen points.'],
              ['label', 'Buy tickets'],
              ['micro', 'Direct from event'],
              ['price', '$60'],
            ] as const
          ).map(([role, sample]) => {
            const t = v2.type[role];
            return (
              <View key={role} style={styles.typeRow}>
                <Text style={[styles.typeKey, { fontFamily: fontFamily('bodyMedium') }]}>{role}</Text>
                <Text
                  style={{
                    fontFamily: t.family.startsWith('Oswald')
                      ? fontFamily('display')
                      : fontFamily('body'),
                    fontSize: t.size,
                    lineHeight: t.lineHeight,
                    letterSpacing: t.letterSpacing,
                    color: v2.text.primary,
                    textTransform: t.uppercase ? 'uppercase' : 'none',
                  }}
                >
                  {sample}
                </Text>
              </View>
            );
          })}
        </Section>

        <Section title="Color">
          <View style={styles.swatches}>
            {(
              [
                ['canvas', v2.surface.canvas],
                ['surface', v2.surface.surface],
                ['elevated', v2.surface.elevated],
                ['brand red', v2.brand.red],
                ['red pressed', v2.brand.redPressed],
                ['success', v2.status.success],
                ['warning', v2.status.warning],
                ['error', v2.status.error],
              ] as const
            ).map(([name, value]) => (
              <View key={name} style={styles.swatchWrap}>
                <View style={[styles.swatch, { backgroundColor: value }]} />
                <Text style={[styles.swatchLabel, { fontFamily: fontFamily('body') }]}>{name}</Text>
              </View>
            ))}
          </View>
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            Error is deliberately a different red from the brand red, so a destructive action never
            looks like a primary one.
          </Text>
        </Section>

        <Section title="Media: every slot, one asset">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            The same portrait flyer through every slot. Sizes come from the slot table, never from a
            screen.
          </Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            <View style={styles.strip}>
              {slotNames
                .filter((n) => n !== 'PROMOTER_SHARE')
                .map((slot) => (
                  <View key={slot} style={styles.stripItem}>
                    <EventMedia
                      asset={{ path: 'qa/portrait-4x5.jpg', contract: 'v2' }}
                      slot={slot}
                      title={TITLES.short}
                      width={Math.min(MEDIA_SLOTS[slot].layoutWidth.mobile, 140)}
                    />
                    <Text style={[styles.tiny, { fontFamily: fontFamily('bodyMedium') }]}>
                      {slot}
                    </Text>
                    <Text style={[styles.tiny, { fontFamily: fontFamily('body') }]}>
                      {MEDIA_SLOTS[slot].layoutWidth.mobile}x{slotHeight(slot)} ·{' '}
                      {MEDIA_SLOTS[slot].defaultFit}
                    </Text>
                  </View>
                ))}
            </View>
          </ScrollView>
        </Section>

        <Section title="Media: the QA matrix in a discovery card">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            Every artwork shape that breaks the current product. Legacy assets are fitted rather
            than re-cropped, because their portrait pixels were never stored.
          </Text>
          <View style={styles.grid}>
            {QA_ASSETS.map((a) => (
              <View key={a.label} style={styles.gridItem}>
                <EventMedia
                  asset={{ path: a.path, contract: a.contract }}
                  slot="DISCOVERY_CARD"
                  title={TITLES.short}
                  width={150}
                />
                <Text style={[styles.tiny, { fontFamily: fontFamily('bodyMedium') }]}>{a.label}</Text>
              </View>
            ))}
          </View>
        </Section>

        <Section title="Title length">
          <View style={styles.grid}>
            {[TITLES.short, TITLES.long].map((t) => (
              <View key={t} style={styles.gridItem}>
                <EventMedia
                  asset={{ path: 'qa/portrait-4x5.jpg', contract: 'v2' }}
                  slot="DISCOVERY_CARD"
                  title={t}
                  width={150}
                />
                {/* Event titles are Inter, sentence case, never Oswald and never uppercased. */}
                <Text
                  numberOfLines={2}
                  style={[styles.cardTitle, { fontFamily: fontFamily('bodySemi') }]}
                >
                  {t}
                </Text>
                <Text style={[styles.cardMeta, { fontFamily: fontFamily('body') }]}>
                  III Points · Sat, Oct 17
                </Text>
              </View>
            ))}
          </View>
        </Section>

        <Section title="Price and provenance">
          {/*
            Post-A5 the direct rail is quoted from THREE server numbers, never
            from `order.total_minor` alone: face + buyer service fee = charge.
            The unset-rate row is the one that matters — it is what this harness
            shows today, because `fee.buyer_service_bps` is seeded null.
          */}
          {(
            [
              [
                'direct (server quote)',
                {
                  rail: 'direct',
                  faceValueMinor: asCents(6000),
                  buyerServiceFee: { source: 'server-quote', feeMinor: asCents(600) },
                  chargeTotalMinor: asCents(6600),
                } as const,
              ],
              // Fifty DOLLARS: the resale rail's columns are whole dollars, and only
              // `centsFromDollars` can produce the type it accepts.
              ['marketplace', { rail: 'marketplace', baseMinor: centsFromDollars(50) } as const],
              [
                'direct, fee rate unset',
                {
                  rail: 'direct',
                  faceValueMinor: asCents(6000),
                  buyerServiceFee: { source: 'unset' },
                } as const,
              ],
              [
                'tax unknown',
                {
                  rail: 'direct',
                  faceValueMinor: asCents(6000),
                  buyerServiceFee: { source: 'server-quote', feeMinor: asCents(600) },
                  chargeTotalMinor: asCents(6600),
                  tax: { status: 'applies-unknown' },
                } as const,
              ],
              ['missing base', { rail: 'marketplace', baseMinor: null } as const],
            ] as const
          ).map(([label, input]) => {
            const r = allInPrice(input);
            return (
              <Row key={label} label={label}>
                <Text style={[styles.price, { fontFamily: fontFamily('bodyBold') }]}>
                  {r.kind === 'all-in'
                    ? `${formatMinor(r.totalMinor, r.currency)} all-in` +
                      ` (face ${formatMinor(r.faceValueMinor, r.currency)}` +
                      ` + fee ${formatMinor(r.buyerServiceFeeMinor, r.currency)})`
                    : `no price shown (${r.reason})`}
                </Text>
              </Row>
            );
          })}
          <Row label="ladder, nothing listed">
            <Text style={[styles.price, { fontFamily: fontFamily('bodyBold') }]}>
              {priceLadder({ lowestAllIn: null, lastSaleMinor: null }).label}
            </Text>
          </Row>

          <View style={styles.badges}>
            {(['direct', 'marketplace_fixed', 'marketplace_auction'] as InventoryKind[]).map((k) => {
              const l = provenanceLabel(k);
              const brandTone = l.tone === 'brand';
              return (
                <View key={k} style={styles.badgeWrap}>
                  <View
                    style={[
                      styles.badge,
                      brandTone
                        ? { backgroundColor: v2.brand.red }
                        : { borderWidth: 1, borderColor: v2.text.primary },
                    ]}
                  >
                    <Text
                      style={[
                        styles.badgeText,
                        { fontFamily: fontFamily('bodyBold') },
                        brandTone ? { color: v2.text.inverse } : { color: v2.text.primary },
                      ]}
                    >
                      {l.badge}
                    </Text>
                  </View>
                  <Text style={[styles.tiny, { fontFamily: fontFamily('body') }]}>
                    {l.explanation}
                  </Text>
                </View>
              );
            })}
          </View>
        </Section>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: v2.surface.canvas },
  body: { padding: v2.space.lg, paddingBottom: 64 },
  h1: { fontSize: 34, lineHeight: 34, color: v2.text.primary, textTransform: 'uppercase' },
  h2: {
    fontSize: 20,
    lineHeight: 22,
    color: v2.text.primary,
    textTransform: 'uppercase',
    marginBottom: v2.space.md,
  },
  note: { fontSize: 13, lineHeight: 18, color: v2.text.secondary, marginTop: v2.space.sm },
  section: {
    marginTop: v2.space.xxl,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: v2.border.default,
    paddingTop: v2.space.lg,
  },
  typeRow: { marginBottom: v2.space.md },
  typeKey: { fontSize: 10, letterSpacing: 2, color: v2.text.muted, textTransform: 'uppercase' },
  swatches: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.md },
  swatchWrap: { width: 76 },
  swatch: {
    width: 76,
    height: 44,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: v2.border.overArt,
  },
  swatchLabel: { fontSize: 10, color: v2.text.muted, marginTop: 4 },
  strip: { flexDirection: 'row', gap: v2.space.md, paddingVertical: v2.space.sm },
  stripItem: { width: 150 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.md, marginTop: v2.space.md },
  gridItem: { width: 150 },
  tiny: { fontSize: 10, lineHeight: 14, color: v2.text.muted, marginTop: 4 },
  cardTitle: { fontSize: 15, lineHeight: 19, color: v2.text.primary, marginTop: v2.space.sm },
  cardMeta: { fontSize: 12, lineHeight: 16, color: v2.text.muted, marginTop: 2 },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: v2.space.sm,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: v2.border.default,
  },
  micro: { fontSize: 10, letterSpacing: 2, color: v2.text.muted, textTransform: 'uppercase' },
  price: { fontSize: 18, color: v2.text.primary },
  badges: { marginTop: v2.space.lg, gap: v2.space.md },
  badgeWrap: { gap: 4 },
  badge: { alignSelf: 'flex-start', paddingHorizontal: 8, paddingVertical: 4 },
  badgeText: { fontSize: 10, letterSpacing: 1.6, textTransform: 'uppercase' },
});
