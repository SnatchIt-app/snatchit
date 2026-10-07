/**
 * V3 listing-detail stage (§3 hero over the curve scrim; §5 price panel, minimum-bid breakdown
 * and the corrected commitment sentence — mockup midnight-listing, freeze reconciliation §2).
 *
 * Truth rules pinned here: the panel states the CURRENT price and nothing about the buyer's
 * total; the breakdown belongs to the bid being offered and comes preformatted from the one
 * money module; "current bid" is never claimed with zero bids; the buy-now amount lives on its
 * CTA, not in the panel; identity moves onto the artwork but nothing transactional does.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

// The migrated screens read the resolved appearance. These suites assert behaviour, not colour, so
// the boundary is mocked to Midnight — whose values ARE the v2 tokens, so nothing they pin moves.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
const rn = vi.hoisted(() => ({ fontScale: 1 }));
vi.mock('react-native', () => ({
  Animated: { View: 'Animated.View' },
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: rn.fontScale }),
  Pressable: 'Pressable', Text: 'Text', View: 'View',
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  StyleSheet: {
    create: <T,>(s: T) => s,
    hairlineWidth: 1,
    absoluteFill: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
    absoluteFillObject: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  },
}));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/PriceDisplay', () => ({ PriceDisplay: 'PriceDisplay' }));
vi.mock('@/src/components/ui', () => ({ FromAFanBadge: 'FromAFanBadge', IconButton: 'IconButton' }));
vi.mock('@/src/hooks/usePulseOnChange', () => ({ usePulseOnChange: () => ({ opacity: 1 }) }));
const ins = vi.hoisted(() => ({ top: 0 }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => ins.top }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));

import { BID_COMMITMENT_COPY } from '@/src/lib/listing/detailState';
import { findElement, HookHost } from './helpers/nav-stack-harness';

const byText = (host: HookHost, text: string) =>
  findElement(host.output, (el) => el.type === 'Text' && el.props.children === text);
const priceDisplay = (host: HookHost, label: string) =>
  findElement(host.output, (el) => el.type === 'PriceDisplay' && el.props.label === label);

async function mountPanel(over: Record<string, unknown> = {}) {
  const mod = await import('@/src/components/listing/TransactionPanel');
  const Panel = mod.TransactionPanel as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Panel({
    mode: 'auction_and_buy_now',
    currentAllIn: '$99.00',
    buyNowAllIn: '$132.00',
    nextBidAllIn: '$104.50',
    minBidBase: '$95.00',
    minBidFee: '$9.50',
    clock: { text: '2h 14m left', urgent: false },
    soldAllIn: null,
    bidCount: 6,
    quantity: 2,
    ticketType: 'GA',
    ...over,
  }), new Map());
  host.mount();
  host.flush();
  return host;
}

async function mountHero(over: Record<string, unknown> = {}) {
  const mod = await import('@/src/components/listing/ListingHero');
  const Hero = mod.ListingHero as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Hero({
    asset: { path: 'covers/a.jpg', contract: 'legacy', bucket: 'auction-media' },
    eventName: 'Neon Choir',
    venue: 'Lantern Room',
    eventDate: '2026-09-26',
    eventTime: '19:30:00',
    neighborhood: 'Bushwick',
    onBack: () => {},
    onOverflow: () => {},
    ...over,
  }), new Map());
  host.mount();
  host.flush();
  return host;
}

beforeEach(() => { vi.resetModules(); rn.fontScale = 1; });

describe('the commitment sentence — de-duplicated (owner 2026-09-23)', () => {
  it('LP1: one sentence, no repeated numbers, and never an automatic-charge claim', () => {
    // The panel states the market price and the CTA sub-label states the minimum; the sentence
    // repeats neither. It carries only what nothing else on the screen says.
    expect(BID_COMMITMENT_COPY).toBe(
      "A bid is a commitment. If you win, you'll pay your own bid at checkout to complete the purchase.",
    );
    expect(BID_COMMITMENT_COPY).not.toMatch(/\$/);
    expect(BID_COMMITMENT_COPY.toLowerCase()).not.toContain('charged automatically');
  });
});

describe('TransactionPanel — the §5 panel', () => {
  it('LP2: states the current price, the qty column and the sub-line — nothing about the buyer\'s total', async () => {
    const host = await mountPanel();
    expect(priceDisplay(host, 'Current bid')).toBeDefined();
    expect((priceDisplay(host, 'Current bid')?.props as { amount?: string }).amount).toBe('$99.00');
    expect(byText(host, '2 × GA tickets')).toBeDefined();
    expect(byText(host, 'sold together')).toBeDefined();
    expect(byText(host, 'all-in · 6 bids · 2h 14m left')).toBeDefined();
  });

  it('LP3: one ticket is singular and NOT "sold together"; zero bids is "Starting bid" and "no bids yet"', async () => {
    const host = await mountPanel({ quantity: 1, bidCount: 0 });
    expect(byText(host, '1 × GA ticket')).toBeDefined();
    expect(byText(host, 'sold together')).toBeUndefined();
    expect(priceDisplay(host, 'Starting bid')).toBeDefined();
    expect(priceDisplay(host, 'Current bid')).toBeUndefined();
    expect(byText(host, 'all-in · no bids yet · 2h 14m left')).toBeDefined();
  });

  it('LP4: the minimum-bid breakdown, each number ONCE — and absent when there is no next bid', async () => {
    const host = await mountPanel();
    expect(byText(host, 'If you bid the minimum')).toBeDefined();
    // De-dup (owner 2026-09-23): "Tickets" — the quantity is already stated in the panel above;
    // and the total appears exactly once, on its own row, not also as a headline.
    expect(byText(host, 'Tickets')).toBeDefined();
    expect(byText(host, 'Tickets (2 × GA)')).toBeUndefined();
    expect(byText(host, '$95.00')).toBeDefined();
    expect(byText(host, 'Service fee (10%)')).toBeDefined();
    expect(byText(host, '$9.50')).toBeDefined();
    // R-2 (B): no total row — the CTA sub-label states the minimum all-in; the figure must not
    // appear in the panel at all.
    expect(byText(host, 'Your total if you win')).toBeUndefined();
    const totals: string[] = [];
    const walk = (node: unknown) => {
      if (Array.isArray(node)) { node.forEach(walk); return; }
      const el = node as { type?: unknown; props?: { children?: unknown } } | null;
      if (!el || typeof el !== 'object' || !('props' in el) || !el.props) return;
      if (el.props.children === '$104.50') totals.push('$104.50');
      walk(el.props.children);
    };
    walk(host.output);
    expect(totals).toHaveLength(0);
    // The fee is named in the breakdown; the old trailing fee sentence is gone from live views.
    expect(byText(host, 'All prices include the 10% service fee.')).toBeUndefined();

    const closed = await mountPanel({ mode: 'closed', nextBidAllIn: null, minBidBase: null, minBidFee: null, clock: null });
    expect(byText(closed, 'If you bid the minimum')).toBeUndefined();

    // Defence in depth: even if a caller hands a closed panel the row values (L6 survived the
    // first control run because only the nulled case was pinned), the block must stay hidden —
    // a would-be total on a closed auction is an offer that no longer exists.
    const closedWithValues = await mountPanel({ mode: 'closed', clock: null });
    expect(byText(closedWithValues, 'If you bid the minimum')).toBeUndefined();
    expect(byText(closedWithValues, 'Service fee (10%)')).toBeUndefined();
  });

  it('LP5: sold shows what it went for, no bid arithmetic — and keeps its one fee sentence', async () => {
    const host = await mountPanel({ soldAllIn: '$99.00' });
    expect(priceDisplay(host, 'Sold for')).toBeDefined();
    expect(byText(host, 'If you bid the minimum')).toBeUndefined();
    // With no breakdown on a sold view, this sentence is the only place the fee is explained.
    expect(byText(host, 'Price includes the 10% service fee.')).toBeDefined();
  });

  it('LP6: the buy-now amount lives on its CTA — the panel no longer prints it', async () => {
    const host = await mountPanel();
    expect(priceDisplay(host, 'Buy now')).toBeUndefined();
    expect(byText(host, 'Yours immediately. No waiting for the auction.')).toBeUndefined();
  });

  /*
   * LARGE TEXT IN THE PANEL (found in the C-operated a3xl capture at 0dfea8b2, after the Home
   * caption fix). Three two-column rows could not fit at accessibility-extra-extra-extra-large,
   * and all three lost text: "2 × GA ti…", "all-in · 6 bids…", and — the one that matters most —
   * the breakdown VALUE, which rendered "$95.0". A clipped amount is not an aesthetic problem; it
   * states a different number from the one the buyer would pay.
   *
   * Same rule as the Home feature's identity block, reused rather than restated: above
   * IDENTITY_STACK_SCALE the rows stack and every line gets the full width.
   */
  it('LP8: at a large text scale the panel stacks instead of clipping its lines', async () => {
    const styleOf = (host: HookHost, key: string) => {
      const el = findElement(host.output, (e) => {
        const st = e.props.style as { flexDirection?: string } | undefined;
        return e.type === 'View' && st?.flexDirection != null && (e.props as Record<string, unknown>).testID === key;
      });
      return el?.props.style as { flexDirection?: string } | undefined;
    };

    rn.fontScale = 1;
    expect(styleOf(await mountPanel(), 'panel-card-row')?.flexDirection).toBe('row');
    expect(styleOf(await mountPanel(), 'panel-breakdown-row')?.flexDirection).toBe('row');

    rn.fontScale = 3.1;
    const big = await mountPanel();
    expect(styleOf(big, 'panel-card-row')?.flexDirection).toBe('column');
    expect(styleOf(big, 'panel-breakdown-row')?.flexDirection).toBe('column');
  });

  it('LP9: nothing is capped at one line, and at a large scale nothing is capped at all', async () => {
    /*
     * Two lines was not enough: the a3xl capture of the first fix still showed
     * "all-in · 6 bids · Ends Wed 01…" because that line needs three at this scale. A cap exists
     * to keep the compact layout tidy, and the stacked layout is not the compact one — it is
     * already a column, and the screen scrolls. So the cap is lifted entirely when stacked rather
     * than raised to a number that the next string will exceed.
     */
    rn.fontScale = 3.1;
    const stacked = await mountPanel();
    const capsAt = (host: HookHost): { text: string; cap: unknown }[] => {
      const out: { text: string; cap: unknown }[] = [];
      const walk = (n: unknown): void => {
        if (Array.isArray(n)) { n.forEach(walk); return; }
        const el = n as { type?: unknown; props?: Record<string, unknown> } | null;
        if (!el || typeof el !== 'object' || !('props' in el)) return;
        if (el.type === 'Text' && el.props!.numberOfLines != null) {
          out.push({ text: String(el.props!.children).slice(0, 40), cap: el.props!.numberOfLines });
        }
        walk((el.props as { children?: unknown }).children);
      };
      walk(host.output);
      return out;
    };
    expect(capsAt(stacked), 'a stacked line may use as many lines as it needs').toEqual([]);

    rn.fontScale = 1;
    const host = await mountPanel();
    const capped: string[] = [];
    const walk = (n: unknown): void => {
      if (Array.isArray(n)) { n.forEach(walk); return; }
      const el = n as { type?: unknown; props?: Record<string, unknown> } | null;
      if (!el || typeof el !== 'object' || !('props' in el)) return;
      if (el.type === 'Text' && el.props!.numberOfLines === 1) capped.push(String(el.props!.children).slice(0, 40));
      walk((el.props as { children?: unknown }).children);
    };
    walk(host.output);
    expect(capped, `these clipped at a3xl on the device: ${capped.join(' | ')}`).toEqual([]);
  });

  it('LP7: the panel does no money arithmetic (source pin)', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/components/listing/TransactionPanel.tsx', 'utf8');
    expect(src).not.toMatch(/\* 100|\/ 100|\* 0\.1|lib\/money/);
  });
});

describe('ListingHero — identity over the curve-scrimmed §3 hero', () => {
  it('LH1: the V3 hero slot, fluid, with the dated identity line and the name over the artwork', async () => {
    const host = await mountHero();
    const art = findElement(host.output, (el) => el.type === 'EventMedia');
    expect(art?.props.slot).toBe('LISTING_HERO_V3');
    expect(art?.props.fluid).toBe(true);
    expect(byText(host, 'Sat 26 Sep · 19:30 · Lantern Room')).toBeDefined();
    const name = findElement(host.output, (el) => (el.props as { token?: string }).token === 'nameDetail');
    expect(name?.props.children).toBe('Neon Choir');
  });

  it('LH2: provenance is not quietly dropped — the badge still renders', async () => {
    const host = await mountHero();
    expect(findElement(host.output, (el) => el.type === 'FromAFanBadge')).toBeDefined();
  });

  /*
   * THE POSTER IS NOT COVERED (B's native batch 3 at d5217530; owner-settled 2026-10-06).
   *
   * B measured the Listing poster as complete and 4:5 — 0 to 490.7 pt, not re-cropped — and then
   * measured what sits ON it: the SANDBOX banner over its top 79 pt, and the two navigation chips
   * at (5,80)-(79.7,159.7) and (310,80)-(389.7,159.7), on printed lines. The owner's requirement is
   * that navigation controls, the status bar and the sandbox banner must not cover printed content,
   * with navigation in its own area if needed. So the fix is positional, as B said: the poster
   * starts below the banner and the controls move off it. Nothing is re-cropped.
   */
  it('LH4: the poster carries nothing — navigation is no longer inside the frame', async () => {
    ins.top = 79;
    const host = await mountHero();
    const art = findElement(host.output, (el) => el.type === 'EventMedia');
    expect(art).toBeDefined();
    // A child of EventMedia draws INSIDE the frame, which is what put chips on printed lines.
    expect(art!.props.children ?? null).toBeNull();
    // And the chips are still on screen — moved, not deleted.
    const back = findElement(host.output, (el) => el.type === 'IconButton' && el.props.glyph === 'back');
    const more = findElement(host.output, (el) => el.type === 'IconButton' && el.props.glyph === 'more');
    expect(back).toBeDefined();
    expect(more).toBeDefined();
  });

  it('LH5: navigation sits in its own area ABOVE the poster, and that area carries the inset', async () => {
    ins.top = 79;
    const host = await mountHero();
    // Order in the tree is order on screen: the nav area must precede the poster.
    const kinds: string[] = [];
    const walk = (n: unknown): void => {
      if (Array.isArray(n)) { n.forEach(walk); return; }
      const el = n as { type?: unknown; props?: Record<string, unknown> } | null;
      if (!el || typeof el !== 'object' || !('props' in el)) return;
      if (el.type === 'EventMedia') kinds.push('poster');
      if (el.type === 'IconButton') kinds.push('nav');
      walk((el.props as { children?: unknown }).children);
    };
    walk(host.output);
    expect(kinds[0], `tree order was ${kinds.join(',')}`).toBe('nav');
    expect(kinds).toContain('poster');

    // The inset belongs to the nav area now, so the status bar and the banner are above the
    // poster rather than over it. With no inset the area still exists, just tighter.
    const navRow = findElement(host.output, (el) => {
      const st = el.props.style as { paddingTop?: number } | Array<{ paddingTop?: number }> | undefined;
      const flat = Array.isArray(st) ? Object.assign({}, ...st.filter(Boolean)) : st;
      return el.type === 'View' && typeof flat?.paddingTop === 'number' && flat.paddingTop >= 79;
    });
    expect(navRow, 'a nav area padded past the banner').toBeDefined();
  });

  it('LH6: the chips take canvas form now that they are not on artwork', async () => {
    const host = await mountHero();
    for (const glyph of ['back', 'more']) {
      const chip = findElement(host.output, (el) => el.type === 'IconButton' && el.props.glyph === glyph);
      // `onArt` is the over-media vocabulary: white ink on its own dark plate. Off the poster it
      // would be a dark chip floating on the canvas.
      expect(chip!.props.onArt ?? false, `${glyph} must not declare over-art form`).toBe(false);
    }
  });

  it('LH3: nothing transactional over the image, and no local font override (source pins)', async () => {
    const { readFileSync } = await import('node:fs');
    // Comments stripped — the rule is about what RENDERS, and the rationale comment itself
    // names the price it forbids (the SL4/B15 lesson applied on first writing).
    const src = readFileSync('src/components/listing/ListingHero.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).not.toMatch(/fontSize: \d/);
    expect(src).not.toMatch(/price|allIn|\$\{.*Amount/i);   // identity only — never a price on the hero
  });
});

describe('screen wiring (source pins)', () => {
  it('LS1: the screen renders the commitment sentence, the relocated neighborhood row, and the platform on Delivery', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/ListingDetailScreen.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).toContain('BID_COMMITMENT_COPY');
    expect(src).toContain("label: 'Neighborhood'");
    expect(src).toContain('PLATFORM_INSTRUCTIONS[');
    expect(src).toContain('minBidBase');
  });

  it('LS2 (F-29 → R-5): the "place a bid instead" recovery reads the AUTHORITATIVE action resolver — no competing availability formula', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/ListingDetailScreen.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    // One predicate over the resolved actions, used at BOTH sites: the dialog body and the
    // commitment sentence. The local re-derivation (B's R-5: it said "true" while holding a
    // reservation, where the resolver offers continue_reservation and no bid at all) is gone.
    expect(src).not.toContain('bidAvailable');
    expect(src).toContain("offersBid(state) ? 'You can place a bid instead.' : \"Buy Now isn't offered on this listing.\"");
    expect(src).toMatch(/\{offersBid\(state\) \? \(\s*<Text style=\{\[textStyle\('bodySm'\), s\.commitment\]\}>\{BID_COMMITMENT_COPY\}/);
    expect(src).not.toContain("'This listing does not have Buy Now enabled.'");
  });

  it('LS4 (owner rulings 2026-09-24, 2026-09-25): the RESOLVED PRIMARY carries the filled emphasis and leads the column, whichever action that is', async () => {
    const { readFileSync } = await import('node:fs');
    const raw = readFileSync('src/screens/ListingDetailScreen.tsx', 'utf8');
    const src = raw.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    // The flip pinned the emphasis to the board (`pkg8-listing-*` draws the bid filled and Buy Now
    // outlined beneath it) while `detailState` rule 1 resolves Buy Now as the primary. The owner
    // ruled the resolver decides: "Buy Now leads whenever the resolver selects it as primary."
    expect(src).not.toContain("variant={state.secondary ? 'secondary' : 'primary'}");
    // Exactly one filled action, and it is the primary's.
    const primaryBlock = src.slice(src.indexOf('label={state.primary.label}'));
    expect(primaryBlock.slice(0, primaryBlock.indexOf('/>'))).toContain('variant="primary"');
    const secondaryBlock = src.slice(src.indexOf('label={state.secondary.label}'));
    expect(secondaryBlock.slice(0, secondaryBlock.indexOf('/>'))).toContain('variant="secondary"');
    // Leading also means FIRST in the stacked footer: the primary's BarAction precedes the
    // secondary's in source order, which is the order StickyBar layout="stack" paints.
    expect(src.indexOf('label={state.primary.label}')).toBeLessThan(src.indexOf('label={state.secondary.label}'));
    // Nothing about what either action DOES changed: both still dispatch through runAction.
    expect(src).toContain('onPress={() => runAction(state.primary.kind)}');
    expect(src).toContain('onPress={() => runAction(state.secondary!.kind)}');
  });
});

describe('offersBid — the resolver decides whether a bid exists on this screen (R-5)', () => {
  const SELLER = 'seller-uuid';
  const BUYER = 'buyer-uuid';
  type Input = import('@/src/lib/listing/detailState').DetailStateInput;
  function input(over: Partial<Omit<Input, 'listing'>> & { listing?: Partial<Input['listing']> } = {}): Input {
    const { listing, ...rest } = over;
    return {
      userId: BUYER, clockEnded: false, reservationActive: false, finalizing: false, reserving: false,
      transfer: { id: null, status: null, buyerId: null }, isHighestBidder: false, hasBid: false, buyNowAllIn: null,
      ...rest,
      listing: {
        status: 'active', auction_status: 'active', buy_now_enabled: false, buy_now_price: null,
        seller_id: SELLER, reserved_by: null, winner_user_id: null, bid_count: 0, ...(listing ?? {}),
      },
    };
  }

  it('LS3: a live auction offers a bid; holding a reservation offers "Finish checkout" and NO bid; ended and the seller offer none', async () => {
    const { listingActions, offersBid } = await import('@/src/lib/listing/detailState');
    expect(offersBid(listingActions(input()))).toBe(true);
    // Buy Now + auction: the bid is the secondary — still offered.
    expect(offersBid(listingActions(input({ buyNowAllIn: '$132', listing: { buy_now_enabled: true, buy_now_price: 120 } })))).toBe(true);
    // R-5's case: reserved by me → continue_reservation as primary with no secondary.
    const held = listingActions(input({ reservationActive: true, listing: { reserved_by: BUYER, buy_now_enabled: true, buy_now_price: 120 } }));
    expect(held.primary.kind).toBe('continue_reservation');
    expect(held.secondary).toBeNull();
    expect(offersBid(held)).toBe(false);
    // Ended, and the seller's own listing.
    expect(offersBid(listingActions(input({ listing: { auction_status: 'ended' } })))).toBe(false);
    expect(offersBid(listingActions(input({ userId: SELLER })))).toBe(false);
    // Reserved by someone else → "On hold", no bid.
    expect(offersBid(listingActions(input({ reservationActive: true, listing: { reserved_by: 'other-uuid' } })))).toBe(false);
  });
});
