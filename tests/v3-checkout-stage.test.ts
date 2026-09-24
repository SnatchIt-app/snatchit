/**
 * V3 checkout stage (pkg2 checkout board + the 2026-09-23 de-dup rule).
 *
 * What this pins: ONE order-identity block (display voice, shared dated line, whole-listing
 * quantity) reused by all three checkout views; the breakdown's item row no longer re-counts
 * a quantity the identity line already states; and the sticky bar's Total appears ONLY when
 * the pay control's own label does not state an amount — on the action or beside it, never
 * both. Payment behaviour is untouched: payControl/setupDecision/holdState are not edited
 * (gated surface), and the escrow-note gating keeps its own suite.
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
vi.mock('react-native', () => ({
  Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));

import { findElement, HookHost } from './helpers/nav-stack-harness';

const byText = (host: HookHost, text: string) =>
  findElement(host.output, (el) => el.type === 'Text' && el.props.children === text);

async function mountIdentity(over: Record<string, unknown> = {}) {
  const mod = await import('@/src/components/checkout/OrderIdentity');
  const C = ((mod.OrderIdentity as { type?: unknown }).type ?? mod.OrderIdentity) as (p: unknown) => unknown;
  const host = new HookHost(() => C({
    cover: 'covers/a.jpg',
    name: 'Neon Choir',
    venue: 'Lantern Room',
    eventDate: '2026-09-26',
    eventTime: '19:30:00',
    quantity: 2,
    ticketType: 'GA',
    ...over,
  }), new Map());
  host.mount();
  host.flush();
  return host;
}

beforeEach(() => { vi.resetModules(); });

describe('OrderIdentity — one block, each fact once', () => {
  it('CI1: display-voice name, the shared dated line, and the whole-listing quantity', async () => {
    const host = await mountIdentity();
    const name = findElement(host.output, (el) => (el.props as { token?: string }).token === 'nameOrder');
    expect(name?.props.children).toBe('Neon Choir');
    expect(byText(host, 'Sat 26 Sep · 19:30 · Lantern Room')).toBeDefined();
    expect(byText(host, '2 × GA · sold together')).toBeDefined();
    const art = findElement(host.output, (el) => el.type === 'EventMedia');
    expect(art?.props.slot).toBe('CHECKOUT_THUMBNAIL');
  });

  it('CI2: one ticket makes no "sold together" claim', async () => {
    const host = await mountIdentity({ quantity: 1 });
    expect(byText(host, '1 × GA')).toBeDefined();
    expect(byText(host, '1 × GA · sold together')).toBeUndefined();
  });

  it('CI3: missing pieces degrade to what is known — never an invented count or date', async () => {
    const noType = await mountIdentity({ ticketType: null });
    expect(byText(noType, '2 tickets · sold together')).toBeDefined();
    const noDate = await mountIdentity({ eventDate: null, eventTime: null });
    expect(byText(noDate, 'Lantern Room')).toBeDefined();
    const noQty = await mountIdentity({ quantity: null, ticketType: null });
    expect(findElement(noQty.output, (el) =>
      typeof el.props.children === 'string' && /sold together|×/.test(el.props.children as string),
    )).toBeUndefined();
  });
});

describe('no nearby Total beside the pay control (owner + A N2, 2026-09-24)', () => {
  it('CS1: the sticky bar carries no Total at all — before the intent the figure is an estimate, after it the button says it', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/checkout/CheckoutNative.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src).not.toMatch(/<PriceDisplay size="sticky" label="Total"/);
    expect(src).not.toContain('labelCarriesAmount');
  });
});

describe('the itemised rows are server figures only (A\'s ruling Q1–Q3, 2026-09-24)', () => {
  /*
   * RETARGETED 2026-09-24: checkout's presentation moved to `CheckoutView.tsx`, a module with no
   * native payment module in its import graph, so the owner's "rendering path that cannot mount
   * payment setup" exists at all (see tests/v3-checkout-view.test.ts). The RULE these cases pin is
   * unchanged and now has two halves: the SCREEN decides whether there is a breakdown to show and
   * formats every figure; the VIEW paints what it is handed and formats nothing.
   */
  const code = async (rel: string) => (await import('node:fs')).readFileSync(rel, 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
  const screen = () => code('src/screens/checkout/CheckoutNative.tsx');
  const view = () => code('src/screens/checkout/CheckoutView.tsx');

  it('CS4: the rows render only once create-payment-intent has answered and no price change is pending; every figure is the server\'s', async () => {
    const src = await screen();
    // The gate is still the same expression, and it is the screen's.
    expect(src).toMatch(/breakdown=\{serverBreakdown && !priceChange \? \{/);
    expect(src).toContain('amount: formatCents(serverBreakdown.amount)');
    expect(src).toContain('fee: formatCents(serverBreakdown.buyerFee)');
    expect(src).toContain('total: formatCents(serverBreakdown.total)');
    // The word "Total" never sits over the route estimate: the only remaining use of the mixed
    // figure is the pay control's input, which the control prints only when payment is ready.
    expect(src.match(/formatCents\(totalCents\)/g)?.length).toBe(1);
    expect(src).toContain('formattedTotal: formatCents(totalCents)');
    expect(src).not.toMatch(/acceptedTotalCents - dollarsToCents/);
    // The view cannot invent a figure: it neither formats money nor reads the server's breakdown.
    const v = await view();
    expect(v).not.toMatch(/formatCents|buyerTotalCents|dollarsToCents|serverBreakdown/);
    expect(v).toMatch(/<Row label=\{breakdown\.item\} value=\{breakdown\.amount\}/);
  });

  it('CS5: before the server answers, one line "Preparing your total" and no figure — only while setup is actually running', async () => {
    const src = await screen();
    expect(src).toContain('const preparing = authLoading || paymentLoading;');
    expect(src).toContain('preparing={preparing}');
    const v = await view();
    // One line, in the breakdown's own slot, and only when there is no breakdown yet.
    expect(v).toMatch(/\{breakdown \? \([\s\S]*?\) : preparing \? \(/);
    expect(v).toContain('PREPARING_TOTAL');
    expect(v).toContain("export const PREPARING_TOTAL = 'Preparing your total';");
  });
});

describe('screen wiring (source pins; behaviour suites stay green)', () => {
  it('CS2: all three checkout views render the ONE identity block; no per-view name rows remain', async () => {
    // RETARGETED: the three faces live in CheckoutView now. Two <OrderIdentity> sites cover them —
    // the main view's, and the one inside the shared terminal face that both the refund and the
    // confirmation render — and the screen passes ONE identity object to all three.
    const { readFileSync } = await import('node:fs');
    const view = readFileSync('src/screens/checkout/CheckoutView.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(view.match(/<OrderIdentity/g)?.length).toBe(2);
    expect(view).toContain('function TerminalFace(');       // one shape…
    expect(view.match(/<TerminalFace/g)?.length).toBe(2);   // …rendered by the refund and the confirmation
    expect(view).not.toMatch(/s\.eventName\]\}/);
    const screen = readFileSync('src/screens/checkout/CheckoutNative.tsx', 'utf8');
    expect(screen.match(/identity=\{identity\}/g)?.length).toBe(3);
  });

  it('CS3: the breakdown item row is "Tickets" on buy-now — the identity line owns the count', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/checkout/CheckoutNative.tsx', 'utf8');
    expect(src).toContain("item: isBuyNow ? 'Tickets' : 'Winning bid',");
  });
});
