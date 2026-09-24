/**
 * V3 My listings + Bids stage — the board rules, tested where they live.
 *
 * Boards: My listings composition `pkg3-my-listings-{clean,empty}.png`, tokens
 * `pkg8-mylistings-{dark,light}.png`; Bids `pkg6-bids-{clean,active,past,empty,refresh_failed}.png`
 * (dark only — no light board is drawn). Owner rulings that override a board where they collide:
 * EC7 (cancelled once — pinned in v3-eligibility-copy), "keep meaningful text outside dimmed
 * artwork layers" (pinned structurally in v3-dimmed-layers), the Create → "Sell" dock rename
 * (pinned in v3-selling-stage SL1), and DR12/DR9 on the purchase-confirmed labels — pinned HERE,
 * because the pkg6 board's ten-word list flattens Released/Resolved into "Received" and this
 * stage must never chase it.
 *
 * Source pins hold the screens to the V3 voice (sentence-case titles, bare chip words, radius
 * and hairline by role, the action voice on tappables) and hold the harness to the real
 * components with literal fixtures.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

import { bidPresentation, type BidRowInput } from '@/src/lib/bids/bidState';
import { allInFromDollarsV3 } from '@/src/lib/money';
import { soldOnLabel } from '@/src/components/SellerListingCard';

// soldOnLabel lives beside the card it feeds; the component's render-only imports are mocked
// (vi.mock hoists above the imports) so importing the pure helper never asks vitest to parse
// react-native's Flow sources.
vi.mock('react-native', () => ({
  Text: 'Text', View: 'View', StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
}));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Tappable: 'Tappable' }));
vi.mock('@/src/components/NameText', () => ({ NameText: 'NameText' }));
vi.mock('@/src/components/VerifiedSellerBadge', () => ({ default: 'VerifiedSellerBadge' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/theme/appearance', () => ({ useTheme: () => ({ scheme: 'dark', palette: {} }) }));

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

// ─── My listings ────────────────────────────────────────────────────────────────────────────────

describe('My listings — the V3 surface', () => {
  it('ML1: the header speaks the screen-title voice; no display token remains', () => {
    const s = strip(read('app/my-listings.tsx'));
    expect(s).toMatch(/textStyle\('screenTitle'\), s\.headerTitle\]\} accessibilityRole="header">My listings</);
    expect(s).not.toMatch(/textStyle\('display\w+'\)/);
  });

  it('ML2: the filter chips carry the board\'s bare words — no drawn counts', () => {
    const s = strip(read('app/my-listings.tsx'));
    expect(s).not.toContain('count={');
    expect(s).not.toContain('filterCounts');
    for (const label of ["'All'", "'Active'", "'Send tickets'", "'Sold'", "'Ended'"]) {
      expect(s).toContain(`label: ${label}`);
    }
  });

  it('ML3: the fixture short-circuits ONLY the network read, and every destructive path', () => {
    const s = strip(read('app/my-listings.tsx'));
    expect(s).toMatch(/const fetchMyListings = useCallback\(async \(silent = false\) => \{\s*if \(fixture\) return;/);
    expect(s).toMatch(/async function performDelete\(listing: Listing\) \{\s*if \(fixture\) return;/);
    expect(s).toMatch(/async function performCancel\(listing: Listing\) \{\s*if \(fixture\) return;/);
    // The real reads and the delete/cancel split stay exactly where they were, behind the guards.
    expect(s).toContain("rpc('cancel_listing'");
    expect(s).toMatch(/from\('listings'\)\s*\.delete\(\)/);
  });
});

describe('SellerListingCard — the board row', () => {
  const card = () => strip(read('src/components/SellerListingCard.tsx'));

  it('ML4: a hairline-separated row on the canvas, not a bordered box', () => {
    const c = card();
    expect(c).toMatch(/card: \{[^}]*borderBottomWidth: StyleSheet\.hairlineWidth/s);
    expect(c).not.toMatch(/borderWidth: 1/);
    expect(c).not.toMatch(/backgroundColor: p\.surface\.surface/);
  });

  it('ML5: board badge tones — Ending soon and Sold are the amber words; the label still comes from the module', () => {
    const c = card();
    expect(c).toMatch(/ending_soon: 'warning'/);
    expect(c).toMatch(/sold: 'warning'/);
    expect(c).toMatch(/active: 'success'/);
    expect(c).toMatch(/cancelled: 'neutral'/);
    expect(c).toMatch(/<Badge label=\{sellerBadgeLabel\(badge\)\} tone=\{V3_BADGE_TONE\[badge\]\}/);
    // The V2 tone source is no longer consulted; the word source still is.
    expect(c).not.toContain('sellerBadgeTone');
  });

  it('ML6: the countdown wears the status colour — green live, amber under the wire, never red', () => {
    const c = card();
    expect(c).toMatch(/live: \{ color: p\.status\.success \}/);
    expect(c).toMatch(/urgent: \{ color: p\.status\.warning \}/);
    expect(c).not.toMatch(/urgent: \{ color: p\.status\.error \}/);
  });

  it('ML7: sold rows date the sale on the meta line, in locale-fixed words', () => {
    // The board's sample writes "Sold Fri 17 Oct", but 17 Oct 2026 is a Saturday — the board
    // miscalendars its own fiction. The format is the board's; the weekday is the calendar's.
    expect(soldOnLabel('2026-10-17T21:00:00-04:00')).toBe('Sold Sat 17 Oct');
    expect(soldOnLabel('2026-10-16T21:00:00-04:00')).toBe('Sold Fri 16 Oct');
    expect(soldOnLabel('not-a-date')).toBe('');
    const c = card();
    expect(c).toMatch(/badge === 'sold' && listing\.sold_at \? soldOnLabel\(listing\.sold_at\) : bidMeta/);
  });

  it('ML8: the row actions speak the action voice — no uppercase-tracked V2 label remains', () => {
    const c = card();
    expect(c).not.toContain("textStyle('label')");
    for (const a of ['Edit listing', 'Delete listing', 'Cancel listing']) expect(c).toContain(a);
    // The cancelled recession recedes ink, and the 0.55 layer holds artwork only (v3-dimmed-layers
    // walks the rendered tree; this is the readable-source half of the same rule).
    expect(c).toMatch(/eventCancelled: \{ color: p\.text\.secondary/);
    expect(c).toContain('cardCancelled: { opacity: 0.55 }');
  });
});

// ─── Bids ───────────────────────────────────────────────────────────────────────────────────────

describe('Bids — the V3 surface', () => {
  const screen = () => strip(read('app/(tabs)/bids.tsx'));
  const card = () => strip(read('src/components/bids/BidCard.tsx'));

  it('BD1: the heading speaks the screen-title voice; the segments are the board\'s bare words', () => {
    const s = screen();
    expect(s).toMatch(/textStyle\('screenTitle'\), s\.title\]\} accessibilityRole="header">Your bids</);
    expect(s).not.toMatch(/textStyle\('display\w+'\)/);
    expect(s).toMatch(/<Chip label="Active" selected=\{segment === 'active'\}/);
    expect(s).toMatch(/<Chip label="Past" selected=\{segment === 'past'\}/);
    expect(s).not.toContain('count={');
  });

  it('BD2: the failed refresh is the board\'s inline panel — amber edge, the module\'s copy, Retry', () => {
    const s = screen();
    expect(s).toContain('BIDS_REFRESH_FAILED_COPY[loadError]');
    expect(s).toMatch(/noticeEdge: \{[^}]*backgroundColor: p\.status\.warning/);
    expect(s).toContain('accessibilityRole="alert"');
    expect(s).toMatch(/textStyle\('action'\), s\.noticeAction\]\}>Retry</);
    expect(s).not.toMatch(/textStyle\('label'\)/);
  });

  it('BD3: the row leads with the name in the display voice; state word and urgency sit beside each other', () => {
    const c = card();
    expect(c).toMatch(/<NameText token="nameRow" maxLines=\{2\} style=\{styles\.name\}>\{eventName\}<\/NameText>/);
    expect(c).toMatch(/<Badge label=\{presentation\.label\} tone=\{TONE\[presentation\.tone\]\} \/>/);
    // Urgency shares the badge row (board), in the amber role.
    const badgeRow = c.slice(c.indexOf('styles.badgeRow'), c.indexOf('</View>', c.indexOf('styles.badgeRow')));
    expect(badgeRow).toContain('urgencyLabel');
    expect(c).toMatch(/urgency: \{ color: p\.status\.warning \}/);
  });

  it('BD4: the right column is price, its all-in basis, and the hint on EVERY row', () => {
    const c = card();
    expect(c).toMatch(/>all-in</);
    // The hint is unconditional — the board draws it on every state, action or not.
    expect(c).toMatch(/\{presentation\.actionHint\}/);
    expect(c).not.toMatch(/act \?/);
    expect(c).not.toContain('needsAction');
    // The V2 chevron is gone; the row itself is the control.
    expect(c).not.toContain('›');
  });

  it('BD5: what left the drawn row stays in the spoken one — venue, the price\'s basis word, the max', () => {
    const c = card();
    expect(c).toContain('`${eventName}. ${venue}${whenLabel ? ` · ${whenLabel}` : \'\'}. ${presentation.label}. `');
    expect(c).toContain('`${presentation.priceLabel} ${priceAllIn} all in.`');
    expect(c).toContain('presentation.secondaryLabel && secondaryAllIn');
  });

  it('BD6: "Won" wears the buying-path red; artwork-only dimming survives on past rows', () => {
    const c = card();
    expect(c).toMatch(/brand: 'danger'/);
    expect(c).toContain('dimmed: { opacity: 0.55 }');
    // The dim wraps only the artwork, exactly as before (v3-dimmed-layers praises this shape).
    expect(c).toMatch(/<View style=\{dimmed \? styles\.dimmed : undefined\}>\s*<EventMedia/);
  });

  it('BD7 (DR12/DR9): the purchase-confirmed labels never chase the board\'s flattened "Received"', () => {
    const rowOf = (over: Partial<BidRowInput>): BidRowInput => ({
      amount: 72,
      listing: { status: 'sold', ends_at: '2026-10-01T00:00:00Z', current_bid: 72 },
      ...over,
    });
    expect(bidPresentation(rowOf({ purchaseTransferStatus: 'auto_released', purchaseBuyerConfirmedAt: null }), 'me').label).toBe('Released');
    expect(bidPresentation(rowOf({ purchaseTransferStatus: 'buyer_confirmed', purchaseBuyerConfirmedAt: null }), 'me').label).toBe('Resolved');
    expect(bidPresentation(rowOf({ purchaseTransferStatus: 'buyer_confirmed', purchaseBuyerConfirmedAt: '2026-10-14T18:00:00Z' }), 'me').label).toBe('Received');
  });

  it('BD8: the board\'s drawn amounts come from the one V3 formatter over the fixture bases', () => {
    // pkg6 rows, left to right on the boards: $99.00 · $132.00 · $70.40 · $48.40 · $143.00.
    expect(allInFromDollarsV3(90)).toBe('$99.00');
    expect(allInFromDollarsV3(120)).toBe('$132.00');
    expect(allInFromDollarsV3(64)).toBe('$70.40');
    expect(allInFromDollarsV3(44)).toBe('$48.40');
    expect(allInFromDollarsV3(130)).toBe('$143.00');
  });
});

// ─── Harness ────────────────────────────────────────────────────────────────────────────────────

describe('the v3-mylistings-bids harness — real components, literal fixtures, gated route', () => {
  const h = () => strip(read('app/_dev/v3-mylistings-bids.tsx'));

  it('HZ1: mounts the real screens with fixtures, never a recreated mock', () => {
    const s = h();
    expect(s).toContain("import MyListingsScreen, { type MyListingsFixture } from '@/app/my-listings'");
    expect(s).toContain("import BidsScreen, { type BidsFixture, type BidRow } from '@/app/(tabs)/bids'");
    expect(s).toMatch(/<MyListingsScreen fixture=\{myListingsFixture\} \/>/);
    expect(s).toMatch(/<BidsScreen fixture=\{bidsFixture\} \/>/);
    expect(s).toContain('if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />;');
    // Fixtures are literals: nothing here may reach a server or storage.
    expect(s).not.toMatch(/supabase|fetch\(|AsyncStorage|SecureStore/);
  });

  it('HZ2: the required states are staged — selling live, sold+send, cancelled; won, outbid, leading, purchase, lost', () => {
    const s = h();
    // My listings: active, ending-soon, sold with a pending transfer, cancelled.
    expect(s).toMatch(/status: 'sold', auction_status: 'ended'/);
    expect(s).toMatch(/transfers: \[\{ listing_id: 'fixture-sl3', transferId: 'fixture-tr1', status: 'pending' \}\]/);
    expect(s).toMatch(/auction_status: 'cancelled'/);
    // Bids: the winner is the fixture viewer, an outbid row, a leading row, a purchase in flight.
    expect(s).toContain('winner_user_id: FIXTURE_USER');
    expect(s).toContain("purchaseTransferStatus: 'seller_sent'");
    expect(s).toContain("winner_user_id: 'fixture-someone-else'");
    // The DR12/DR9 trio is staged so a capture SHOWS the ruled words, not the board's one.
    expect(s).toContain("purchaseTransferStatus: 'auto_released'");
    expect(s).toMatch(/purchaseTransferStatus: 'buyer_confirmed', purchaseBuyerConfirmedAt: null/);
    expect(s).toMatch(/purchaseTransferStatus: 'buyer_confirmed',\s*purchaseBuyerConfirmedAt: '2026-10-14T18:00:00Z'/);
  });

  it('HZ3: the screen fixtures short-circuit ONLY the network reads', () => {
    const bids = strip(read('app/(tabs)/bids.tsx'));
    expect(bids).toMatch(/if \(fixture\) return;\s*if \(!userId\) return;/);
    // The real reads stay exactly where they were, behind that gate.
    expect(bids).toContain("from('bids')");
    expect(bids).toContain("from('transfers')");
  });
});
