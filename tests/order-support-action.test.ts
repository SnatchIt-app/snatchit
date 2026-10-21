/**
 * tests/order-support-action.test.ts — the "Contact support about this order" control (CFT-406 slice 1).
 *
 * Mounts the REAL component under the hook harness. It opens the prefilled mailto through Linking;
 * when the mail app cannot open, it shows the address and the order ID as text (the Support screen
 * shows the address on its own button, so the user is never left without it) and announces that for
 * VoiceOver. It persists nothing: the only state is "the last open failed".
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => ({
  opened: [] as string[],
  announced: [] as string[],
  openImpl: (async () => true) as (url: string) => Promise<unknown>,
}));

vi.mock('react-native', () => ({
  AccessibilityInfo: { announceForAccessibility: (m: string) => { h.announced.push(m); } },
  Linking: { openURL: (url: string) => { h.opened.push(url); return h.openImpl(url); } },
  Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('@/src/components/ui', () => ({ Button: 'Button' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}) }));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});

const ID = '3f2a9c1b-7d4e-4a8f-9b6c-2e1d0a9f8c7b';
const TRANSFER = {
  id: ID, status: 'seller_sent', buyer_confirmed_at: null, dispute_resolution: null,
  delivery_email: 'buyer.private@example.test', delivery_phone: '+13055554417',
  seller: { display_name: 'Sam Seller' },
  listing: { event_name: 'Neon Choir', venue: 'Lantern Room' },
};

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

async function mount(props: { role: 'buyer' | 'seller'; transfer: Record<string, unknown> }): Promise<HookHost> {
  const mod = await import('@/src/components/transfer/OrderSupportAction');
  const host = new HookHost(() => mod.OrderSupportAction(props as never), new Map());
  host.mount(); host.flush();
  return host;
}
const tree = (host: HookHost) => expandTree(host.output);
const button = (host: HookHost) =>
  findElement(tree(host), (el) => el.type === 'Button' && el.props.label === 'Contact support about this order') as Element | undefined;
const texts = (node: unknown, out: string[] = []): string[] => {
  if (Array.isArray(node)) { node.forEach((n) => texts(n, out)); return out; }
  const el = node as Element | null;
  if (!el || typeof el !== 'object' || !('props' in el)) return out;
  if (el.type === 'Text') {
    const c = el.props.children;
    out.push(Array.isArray(c) ? c.join('') : String(c));
  }
  texts(el.props.children, out);
  return out;
};
const textElement = (host: HookHost, needle: string) =>
  findElement(tree(host), (el) => el.type === 'Text' && String(el.props.children).includes(needle));

beforeEach(() => {
  h.opened.length = 0;
  h.announced.length = 0;
  h.openImpl = async () => true;
});

describe('OA1 · the control', () => {
  it('renders one secondary button with the agreed label and a hint', async () => {
    const host = await mount({ role: 'buyer', transfer: TRANSFER });
    const b = button(host);
    expect(b, 'no Contact support button').toBeDefined();
    expect(b!.props.variant).toBe('secondary');
    expect(b!.props.accessibilityHint).toMatch(/email/i);
  });

  it('a tap opens the prefilled mailto for this order and role — and nothing else', async () => {
    const host = await mount({ role: 'seller', transfer: { ...TRANSFER, status: 'expired' } });
    (button(host)!.props.onPress as () => void)();
    await flush(); host.flush();
    expect(h.opened).toHaveLength(1);
    const url = h.opened[0];
    expect(url.startsWith('mailto:support@snatchitapp.com?subject=Order%203f2a9c1b%20%C2%B7%20Expired&body=')).toBe(true);
    expect(decodeURIComponent(url)).toContain('Role: Seller');
    // No PII from the row reaches the URL.
    for (const secret of ['buyer.private', '3055554417', 'Sam', 'Lantern']) expect(decodeURIComponent(url)).not.toContain(secret);
    // Success shows no fallback and announces nothing.
    expect(textElement(host, "Couldn't open")).toBeUndefined();
    expect(h.announced).toEqual([]);
  });

  it('a double tap while the first open is in flight opens the mail app once', async () => {
    let release: () => void = () => {};
    h.openImpl = () => new Promise((r) => { release = () => r(true); });
    const host = await mount({ role: 'buyer', transfer: TRANSFER });
    const press = button(host)!.props.onPress as () => void;
    press(); press();
    expect(h.opened).toHaveLength(1);
    release(); await flush(); host.flush();
    (button(host)!.props.onPress as () => void)();
    expect(h.opened).toHaveLength(2);
  });

  it('renders nothing when the row has no usable order ID', async () => {
    const host = await mount({ role: 'buyer', transfer: { ...TRANSFER, id: '' } });
    expect(button(host)).toBeUndefined();
    expect(host.output).toBeNull();
  });
});

describe('OA2 · when the mail app cannot open', () => {
  it('shows the address and the full order ID as selectable text, and announces it', async () => {
    h.openImpl = async () => { throw new Error('Unable to open URL: mailto:…'); };
    const host = await mount({ role: 'buyer', transfer: TRANSFER });
    expect(textElement(host, "Couldn't open")).toBeUndefined();
    (button(host)!.props.onPress as () => void)();
    await flush(); host.flush();
    const fallback = textElement(host, "Couldn't open");
    expect(fallback, 'no fallback text').toBeDefined();
    const said = String(fallback!.props.children);
    expect(said).toContain('support@snatchitapp.com');
    expect(said).toContain(ID);
    expect(fallback!.props.selectable).toBe(true);
    expect(fallback!.props.accessibilityLiveRegion).toBe('polite');
    expect(h.announced).toEqual([said]);
  });

  it('a later successful open clears the fallback', async () => {
    h.openImpl = async () => false;
    const host = await mount({ role: 'seller', transfer: TRANSFER });
    (button(host)!.props.onPress as () => void)();
    await flush(); host.flush();
    expect(textElement(host, "Couldn't open")).toBeDefined();
    h.openImpl = async () => true;
    (button(host)!.props.onPress as () => void)();
    await flush(); host.flush();
    expect(textElement(host, "Couldn't open")).toBeUndefined();
  });
});

describe('OA3 · the buyer\'s "Marked sent" note', () => {
  it('the buyer on a "Marked sent" order is told an email does not freeze the payout', async () => {
    const host = await mount({ role: 'buyer', transfer: TRANSFER });
    expect(texts(tree(host)).join(' | ')).toContain("Emailing support doesn't freeze the seller's payout.");
  });

  it('the seller, and the buyer in any other state, see no note', async () => {
    const seller = await mount({ role: 'seller', transfer: TRANSFER });
    expect(texts(tree(seller)).join(' | ')).not.toContain('Emailing support');
    for (const status of ['pending', 'buyer_confirmed', 'auto_released', 'disputed', 'expired', 'reversed']) {
      const buyer = await mount({ role: 'buyer', transfer: { ...TRANSFER, status } });
      expect(texts(tree(buyer)).join(' | '), status).not.toContain('Emailing support');
    }
  });
});
