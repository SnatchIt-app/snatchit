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
 *
 * PHASE 0 ADDITION: every primitive in `src/components/ui` is rendered here in
 * every state it claims to have, because a component is not finished until each
 * of its states has been looked at. The sample copy is representative text inside
 * a development-only route; nothing here reads or writes production data, and no
 * control does anything but demonstrate itself.
 */

import { Redirect } from 'expo-router';
import { useState } from 'react';
import { ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
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
import { detailState, type DetailStateInput } from '@/src/lib/listing/detailState';
import { ListingStatusBanner } from '@/src/components/listing/ListingStatusBanner';
import { TransactionPanel } from '@/src/components/listing/TransactionPanel';
import { resolveImage } from '@/src/lib/media/url';
import {
  Badge,
  Button,
  Chip,
  EmptyState,
  FromAFanBadge,
  IconButton,
  Input,
  Sheet,
  Skeleton,
  StickyBar,
  STACK_WIDTH,
} from '@/src/components/ui';
import { brandFontsActive, fontFamily } from '@/src/theme/fonts';
import { safeLineHeight, textStyle } from '@/src/theme/typography';
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

/**
 * Representative listing shapes for the state gallery below. They are inputs to a
 * pure function, not product data: no id, no seller, no price that is presented
 * as real inventory.
 */
const SCENARIO_VIEWER = 'viewer';
const SCENARIO_SELLER = 'seller';

type ScenarioOver = Partial<Omit<DetailStateInput, 'listing'>> & {
  listing?: Partial<DetailStateInput['listing']>;
};

function scenario(over: ScenarioOver = {}): DetailStateInput {
  const { listing: listingOver, ...rest } = over;
  return {
    userId: SCENARIO_VIEWER,
    clockEnded: false,
    reservationActive: false,
    finalizing: false,
    reserving: false,
    transfer: { id: null, status: null, buyerId: null },
    isHighestBidder: false,
    hasBid: false,
    buyNowAllIn: null,
    ...rest,
    listing: {
      status: 'active',
      auction_status: 'active',
      buy_now_enabled: false,
      buy_now_price: null,
      seller_id: SCENARIO_SELLER,
      reserved_by: null,
      winner_user_id: null,
      bid_count: 3,
      ...(listingOver ?? {}),
    },
  };
}

const LISTING_SCENARIOS: { label: string; input: DetailStateInput }[] = [
  { label: 'Auction only', input: scenario() },
  {
    label: 'Buy Now + auction',
    input: scenario({
      listing: { buy_now_enabled: true, buy_now_price: 60 },
      buyNowAllIn: '$66',
    }),
  },
  { label: 'You are winning', input: scenario({ hasBid: true, isHighestBidder: true }) },
  { label: 'You were outbid', input: scenario({ hasBid: true, isHighestBidder: false }) },
  {
    label: 'Held for you',
    input: scenario({ listing: { reserved_by: SCENARIO_VIEWER }, reservationActive: true }),
  },
  {
    label: 'Held for someone else',
    input: scenario({ listing: { reserved_by: 'someone' }, reservationActive: true }),
  },
  {
    label: 'You won',
    input: scenario({
      listing: { auction_status: 'ended', winner_user_id: SCENARIO_VIEWER },
      hasBid: true,
    }),
  },
  {
    label: 'Ended, you did not win',
    input: scenario({ listing: { auction_status: 'ended' }, hasBid: true }),
  },
  {
    label: 'Sold, you are the buyer, seller has sent',
    input: scenario({
      listing: { status: 'sold', auction_status: 'ended' },
      transfer: { id: 't1', status: 'seller_sent', buyerId: SCENARIO_VIEWER },
    }),
  },
  {
    label: 'Sold, you are the seller, tickets not sent',
    input: scenario({
      listing: { status: 'sold', auction_status: 'ended' },
      userId: SCENARIO_SELLER,
      transfer: { id: 't1', status: 'pending', buyerId: 'buyer' },
    }),
  },
  {
    label: 'Owner viewing their live listing',
    input: scenario({
      userId: SCENARIO_SELLER,
      listing: { buy_now_enabled: true, buy_now_price: 60 },
      buyNowAllIn: '$66',
    }),
  },
  { label: 'Closing the auction', input: scenario({ finalizing: true, hasBid: true }) },
  { label: 'Cancelled', input: scenario({ listing: { auction_status: 'cancelled' } }) },
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
  // Hooks run BEFORE the guard. The guard used to sit above them, which was fine
  // while this component had none and would have become a Rules-of-Hooks
  // violation the moment it had one. It now has several.
  const [sheetOpen, setSheetOpen] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const [chip, setChip] = useState<string>('all');
  const { width: windowWidth } = useWindowDimensions();

  if (!__DEV__) return <Redirect href="/(tabs)/home" />;

  const slotNames = Object.keys(MEDIA_SLOTS) as MediaSlotName[];

  // What the media layer actually asks the CDN for, at this device's real width
  // and density. Printed rather than described, so a wrong number is visible.
  const sampleResolved = resolveImage(
    { path: 'qa/portrait-4x5.jpg', contract: 'v2' },
    'DISCOVERY_CARD',
    { layoutWidth: Math.round((windowWidth - v2.space.lg * 2 - v2.space.md) / 2) },
  );

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
            const resolved = safeLineHeight(t.size, t.lineHeight);
            const raised = resolved !== t.lineHeight;
            return (
              <View key={role} style={styles.typeRow}>
                <Text style={[styles.typeKey, { fontFamily: fontFamily('bodyMedium') }]}>
                  {role} · {t.size}/{resolved}
                  {raised ? ` (token ${t.lineHeight}, raised for Android)` : ''}
                </Text>
                {/*
                  Rendered through `textStyle`, which is how every screen will get
                  its type. Reading `v2.type[role].lineHeight` directly is what
                  this row used to do, and it reproduced the Android clipping the
                  resolver exists to prevent.
                */}
                <Text style={[textStyle(role), { color: v2.text.primary }]}>{sample}</Text>
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

        <Section title="Listing detail: every state">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            The state machine behind the listing screen, resolved for each case it has to handle.
            Representative shapes, not real inventory: nothing here reads or writes anything.
          </Text>
          {LISTING_SCENARIOS.map(({ label, input }) => {
            const st = detailState(input);
            return (
              <View key={label} style={styles.scenario}>
                <Text style={[styles.typeKey, { fontFamily: fontFamily('bodyMedium') }]}>{label}</Text>
                <Text style={[styles.tiny, { fontFamily: fontFamily('body') }]}>
                  {st.mode} · primary {st.primary.kind}
                  {st.primary.disabled ? ' (disabled)' : ''}
                  {st.secondary ? ` · secondary ${st.secondary.kind}` : ''}
                  {st.status ? ` · status ${st.status.kind}` : ' · no status'}
                </Text>
                {st.status ? <ListingStatusBanner status={st.status} /> : null}
              </View>
            );
          })}
        </Section>

        <Section title="Listing detail: the transaction block">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            Buy Now leads when it exists. The bid sits under a hairline, one step down, and every
            amount shown is all-in.
          </Text>
          <TransactionPanel
            mode="auction_and_buy_now"
            currentAllIn="$44"
            buyNowAllIn="$66"
            nextBidAllIn="$49.50"
            countdown="02:14:08"
            bidCount={7}
          />
          <TransactionPanel
            mode="auction_only"
            currentAllIn="$44"
            nextBidAllIn="$49.50"
            countdown="00:04:12"
            bidCount={0}
          />
          <TransactionPanel mode="closed" currentAllIn="$44" countdown={null} soldAllIn="$66" bidCount={7} />
        </Section>

        <Section title="Listing detail: artwork edge cases">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            A long lineup title and a listing with no cover at all. The hero measures itself, so
            neither case depends on a device width.
          </Text>
          <View style={styles.heroPreview}>
            <EventMedia
              asset={{ path: 'qa/legacy-16x9.jpg', contract: 'legacy' }}
              slot="EVENT_HERO"
              title={TITLES.long}
              fluid
            />
            <Text
              numberOfLines={2}
              style={[styles.cardTitle, { fontFamily: fontFamily('bodySemi') }]}
            >
              {TITLES.long}
            </Text>
          </View>
          <View style={styles.heroPreview}>
            <EventMedia asset={{ path: null }} slot="EVENT_HERO" title="Space" fluid />
            <Text style={[styles.tiny, { fontFamily: fontFamily('body') }]}>
              No artwork: the branded plate, not a broken image.
            </Text>
          </View>
        </Section>

        <Section title="Buttons">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            Primary is red with a black label. Destructive is a different red and is never a filled
            block, so a delete cannot be mistaken for a purchase.
          </Text>
          <View style={styles.stack}>
            <Button label="Buy · $66" onPress={() => {}} variant="primary" size="lg" block />
            <Button label="Place bid" onPress={() => {}} variant="secondary" size="lg" block />
            <Button label="Cancel listing" onPress={() => {}} variant="destructive" size="md" />
            <Button label="See all" onPress={() => {}} variant="ghost" size="sm" />
          </View>
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>States</Text>
          <View style={styles.stack}>
            <Button label="Loading" onPress={() => {}} loading block />
            <Button label="Disabled" onPress={() => {}} disabled block />
            <Button label="Disabled secondary" onPress={() => {}} variant="secondary" disabled block />
          </View>
          <View style={styles.iconRow}>
            <IconButton glyph="back" accessibilityLabel="Go back" onPress={() => {}} />
            <IconButton glyph="close" accessibilityLabel="Close" onPress={() => {}} />
            <IconButton glyph="more" accessibilityLabel="More actions" onPress={() => {}} />
            <IconButton glyph="back" accessibilityLabel="Go back" onPress={() => {}} onArt />
          </View>
        </Section>

        <Section title="Inputs">
          <View style={styles.stack}>
            <Input
              label="Email"
              value={inputValue}
              onChangeText={setInputValue}
              placeholder="you@example.com"
              keyboardType="email-address"
              autoCapitalize="none"
              helper="We only use this to sign you in."
            />
            <Input label="Password" value="" secureTextEntry placeholder="••••••••" />
            <Input
              label="Starting bid"
              value="0"
              keyboardType="numeric"
              error="Enter an amount above $1."
            />
            <Input label="Venue" value="Space" disabled />
          </View>
        </Section>

        <Section title="Chips">
          <View style={styles.chipRow}>
            {['all', 'tonight', 'this weekend', 'buy now', 'auction'].map((c) => (
              <Chip key={c} label={c} selected={chip === c} onPress={() => setChip(c)} />
            ))}
            <Chip label="sold out" disabled />
            <Chip label="filters" count={3} onPress={() => setSheetOpen(true)} />
          </View>
        </Section>

        <Section title="Badges">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            Meaning is carried by the word, never by the colour alone. There is no venue-direct
            badge here: no venue-issued ticket exists yet, and a badge that can lie is worse than
            no badge.
          </Text>
          <View style={styles.chipRow}>
            <FromAFanBadge />
            <Badge label="Ending soon" tone="warning" />
            <Badge label="Delivered" tone="success" />
            <Badge label="Disputed" tone="danger" />
            <Badge label="3" tone="count" />
          </View>
        </Section>

        <Section title="Skeleton">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            Opacity pulse only, and it holds still under reduce motion. A skeleton mirrors the exact
            geometry of what replaces it, so nothing shifts on load.
          </Text>
          <View style={styles.grid}>
            <View style={styles.gridItem}>
              <Skeleton aspectRatio={v2.ratio.portrait} />
              <Skeleton height={14} style={{ marginTop: v2.space.sm }} />
              <Skeleton height={12} width="60%" style={{ marginTop: 6 }} />
            </View>
            <View style={styles.gridItem}>
              <EventMedia
                asset={{ path: 'qa/portrait-4x5.jpg', contract: 'v2' }}
                slot="DISCOVERY_CARD"
                title={TITLES.short}
                width={150}
              />
              <Text
                numberOfLines={2}
                style={[styles.cardTitle, { fontFamily: fontFamily('bodySemi') }]}
              >
                {TITLES.short}
              </Text>
            </View>
          </View>
        </Section>

        <Section title="Empty state">
          <EmptyState
            title="Nothing here yet"
            body="Listings you save will show up here."
            action={{ label: 'Browse tonight', onPress: () => {} }}
          />
        </Section>

        <Section title="Sheet">
          <Button label="Open sheet" onPress={() => setSheetOpen(true)} variant="secondary" />
        </Section>

        <Section title="Media: fluid width and the content layer">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            The frame measures itself and requests a derivative at that width. Nothing here knows a
            device width, which is what stops a nominal 390pt slot overflowing a 375pt phone. The
            title sits in the content layer, above the scrim, inside the frame.
          </Text>
          <EventMedia
            asset={{ path: 'qa/portrait-4x5.jpg', contract: 'v2' }}
            slot="FEATURED_EVENT"
            title={TITLES.short}
            fluid
          >
            <View style={styles.overlay}>
              <FromAFanBadge />
              <Text style={[textStyle('title'), { color: v2.text.primary }]} numberOfLines={2}>
                {TITLES.long}
              </Text>
              <Text style={[textStyle('bodySm'), { color: v2.text.secondary }]}>
                III Points · Sat, Oct 17
              </Text>
            </View>
          </EventMedia>
        </Section>

        <Section title="Transformed image request">
          <Text style={[styles.note, { fontFamily: fontFamily('body') }]}>
            What the media layer actually asks for at this device&apos;s width and density. If this
            shows no width parameter, transformations are off and every card is downloading an
            original.
          </Text>
          <Text style={[styles.tiny, { fontFamily: fontFamily('body') }]} selectable>
            {sampleResolved.kind === 'image'
              ? sampleResolved.uri
              : `fallback (${sampleResolved.reason})`}
          </Text>
          <Text style={[styles.tiny, { fontFamily: fontFamily('body') }]}>
            Window {Math.round(windowWidth)}pt · sticky bar stacks below {STACK_WIDTH}pt ·{' '}
            {windowWidth < STACK_WIDTH ? 'STACKED' : 'side by side'}
          </Text>
          <Text style={[styles.tiny, { fontFamily: fontFamily('body') }]} selectable>
            {resolveImage({ path: 'https://cdn.example.com/a.jpg' }, 'DISCOVERY_CARD').kind ===
            'fallback'
              ? 'untrusted absolute host: refused (correct)'
              : 'untrusted absolute host: RENDERED (defect)'}
          </Text>
        </Section>
      </ScrollView>

      {/* The sticky bar is pinned, so it sits outside the scroll view. */}
      <StickyBar
        left={
          <View>
            <Text style={[textStyle('micro'), { color: v2.text.muted }]}>Current bid</Text>
            <Text style={[textStyle('price'), { color: v2.text.primary }]} numberOfLines={1}>
              $66 total
            </Text>
          </View>
        }
      >
        <Button label="Place bid" onPress={() => {}} variant="primary" size="md" />
      </StickyBar>

      <Sheet
        visible={sheetOpen}
        onClose={() => setSheetOpen(false)}
        title="Filters"
        footer={
          <>
            <Button label="Clear" variant="secondary" onPress={() => setSheetOpen(false)} block />
            <Button label="Apply" variant="primary" onPress={() => setSheetOpen(false)} block />
          </>
        }
      >
        <Text style={[textStyle('body'), { color: v2.text.secondary }]}>
          Tap the scrim, or the Android back button, to dismiss. Both work, which is more than the
          sheets in the product do today.
        </Text>
        <View style={styles.chipRow}>
          {['wynwood', 'downtown', 'south beach', 'little haiti'].map((c) => (
            <Chip key={c} label={c} selected={chip === c} onPress={() => setChip(c)} />
          ))}
        </View>
      </Sheet>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: v2.surface.canvas },
  body: { padding: v2.space.lg, paddingBottom: 64 },
  // Line heights come from `safeLineHeight`, not from the raw token: this file
  // used to hardcode 34/34, which is the Android clipping case itself.
  h1: {
    fontSize: 34,
    lineHeight: safeLineHeight(34, 34),
    color: v2.text.primary,
    textTransform: 'uppercase',
  },
  h2: {
    fontSize: 20,
    lineHeight: safeLineHeight(20, 22),
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
  stack: { gap: v2.space.sm, marginTop: v2.space.md, alignItems: 'flex-start' },
  iconRow: { flexDirection: 'row', gap: v2.space.sm, marginTop: v2.space.md },
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: v2.space.sm,
    marginTop: v2.space.md,
    alignItems: 'center',
  },
  scenario: { marginTop: v2.space.lg, gap: v2.space.xs },
  heroPreview: { marginTop: v2.space.lg },
  overlay: {
    position: 'absolute',
    left: v2.space.md,
    right: v2.space.md,
    bottom: v2.space.md,
    gap: 4,
  },
});
