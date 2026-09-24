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

describe('screen wiring (source pins; behaviour suites stay green)', () => {
  it('CS2: all three checkout views render the ONE identity block; no per-view name rows remain', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/checkout/CheckoutNative.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(src.match(/<OrderIdentity/g)?.length).toBe(3);
    expect(src).not.toMatch(/s\.eventName\]\}/);
  });

  it('CS3: the breakdown item row is "Tickets" on buy-now — the identity line owns the count', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/screens/checkout/CheckoutNative.tsx', 'utf8');
    expect(src).toContain("label={isBuyNow ? 'Tickets' : 'Winning bid'}");
  });
});
