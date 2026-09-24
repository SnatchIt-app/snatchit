/**
 * Transfer-state blocks shared by the real screens, and the sandbox-only synthetic gallery
 * (owner 2026-09-24): "Render the same components used by the real screens, with clearly labelled
 * synthetic fixtures. Do not create duplicate mock implementations. Limit access to these visual test
 * cases. No database writes, payment setup, notifications or actionable transaction controls. Verify
 * that production configuration cannot expose it through navigation or a direct link."
 *
 * Evidence boundary, stated once: these tests prove the MAPPINGS the blocks exercise with supplied
 * props, and the gate. They prove nothing about live sandbox retrieval or the device data path.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });
process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';

const th = vi.hoisted(() => ({ scheme: 'light' as 'light' | 'dark', sandbox: false, pref: 'system' }));

vi.mock('@/src/theme/appearance', async () => {
  const { paletteFor } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: th.scheme, palette: paletteFor(th.scheme) }),
    useAppearancePreference: () => ({ preference: th.pref, setPreference: (p: string) => { th.pref = p; } }),
  };
});
vi.mock('@/src/config/envGuard', () => ({
  get IS_SANDBOX_BUILD() { return th.sandbox; },
  ENV_GUARD_FAILURE: null,
}));
vi.mock('react-native', () => ({
  AccessibilityInfo: { announceForAccessibility: () => {}, isReduceMotionEnabled: async () => true, addEventListener: () => ({ remove: () => {} }) },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Pressable: 'Pressable', Text: 'Text', View: 'View', ScrollView: 'ScrollView',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1, absoluteFill: {}, absoluteFillObject: {} },
  useWindowDimensions: () => ({ width: 390, height: 844 }),
}));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }), SafeAreaView: 'SafeAreaView' }));
vi.mock('expo-router', () => ({ Redirect: 'Redirect', router: { back: () => {}, push: () => {} } }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, EASING_BEZIER: [0.2, 0, 0, 1] }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 0, DOCK_GAP: 12, DOCK_HEIGHT: 66, DOCK_RADIUS: 33, DOCK_SIDE_MARGIN: 16 }));
vi.mock('@/components/ui/icon-symbol', () => ({ IconSymbol: 'IconSymbol' }));
vi.mock('@/src/components/ui', () => ({ IconButton: 'IconButton', Button: 'Button', Badge: 'Badge', Chip: 'Chip' }));

import { dark, light } from '@/src/theme/palette';
import {
  BUYER_ORDER_CLOSED_COPY, REFUND_DUE_POLICY, REFUND_PENDING_LINE, SELLER_NO_PAYOUT_LINE, SELLER_REVERSED_COPY,
  buyerReviewDeadlineLine, sellerHoldLine, sellerReleaseLine,
} from '@/src/lib/transfer/transferState';
import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const stripped = async (rel: string) => (await import('node:fs')).readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
function texts(node: unknown): string[] {
  const out: string[] = [];
  const walk = (n: unknown) => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (typeof el.props.children === 'string') out.push(el.props.children);
    walk(el.props.children);
  };
  walk(expandTree(node));   // blocks nest StateBlock; the gallery nests the blocks — render them through
  return out;
}
function styleValue(el: Element | undefined, key: string): string | undefined {
  const flat: Record<string, unknown> = {};
  const walk = (s: unknown) => { if (Array.isArray(s)) s.forEach(walk); else if (s && typeof s === 'object') Object.assign(flat, s); };
  walk(el?.props.style);
  return flat[key] as string | undefined;
}
function mount(fn: () => unknown): HookHost {
  const h = new HookHost(fn, new Map()); h.mount(); h.flush(); return h;
}

beforeEach(() => { th.scheme = 'light'; th.sandbox = false; th.pref = 'system'; vi.resetModules(); });

describe('one implementation — the real screens render the shared blocks', () => {
  it('TG1: receive and send import the blocks from the shared module and keep no local StateBlock', async () => {
    const receive = await stripped('app/transfer/receive/[id].tsx');
    const send = await stripped('app/transfer/send/[id].tsx');
    for (const src of [receive, send]) {
      expect(src).toContain("from '@/src/components/transfer/TransferStateBlocks'");
      expect(src).not.toMatch(/function StateBlock\(/);
    }
    expect(receive).toContain('<BuyerClosedBlock');
    expect(receive).toContain('<BuyerSellerSentBlock');
    expect(send).toContain('<SellerClosedBlock');
    expect(send).toContain('<SellerReversedBlock');
    expect(send).toContain('<SellerSentBlock');
  });
});

describe('the buyer blocks — order fact from the status, refund fact only from the payment row', () => {
  it('TG2: expired + full refund reads "Order expired" and "Refunded $120"; the title wears the palette warning ink in BOTH appearances', async () => {
    for (const [scheme, p] of [['light', light], ['dark', dark]] as const) {
      th.scheme = scheme; vi.resetModules();
      const mod = await import('@/src/components/transfer/TransferStateBlocks');
      const h = mount(() => mod.BuyerClosedBlock({ status: 'expired', refund: { status: 'refunded', amount_refunded_cents: 12000, refunded_at: '2026-09-20T10:00:00Z', total: 12000 } }));
      const t = texts(h.output);
      expect(t).toContain(BUYER_ORDER_CLOSED_COPY.expired.title);
      expect(t).toContain(BUYER_ORDER_CLOSED_COPY.expired.body);
      expect(t).toContain('Refunded $120');
      const title = findElement(expandTree(h.output), (el) => el.type === 'Text' && el.props.children === BUYER_ORDER_CLOSED_COPY.expired.title);
      expect(styleValue(title, 'color'), scheme).toBe(p.status.warning);
    }
  });

  it('TG3: expired without a payment row states the policy; reversed states the pending line, a partial, or "Refund recorded" — never "reversed" or "released"', async () => {
    const mod = await import('@/src/components/transfer/TransferStateBlocks');
    expect(texts(mount(() => mod.BuyerClosedBlock({ status: 'expired', refund: null })).output)).toContain(REFUND_DUE_POLICY);
    const pending = texts(mount(() => mod.BuyerClosedBlock({ status: 'reversed', refund: null })).output);
    expect(pending).toContain(BUYER_ORDER_CLOSED_COPY.reversed.title);
    expect(pending).toContain(REFUND_PENDING_LINE);
    expect(pending.join(' ')).not.toMatch(/reversed|released/i);
    expect(texts(mount(() => mod.BuyerClosedBlock({ status: 'reversed', refund: { status: null, amount_refunded_cents: 6000, refunded_at: null, total: 12000 } })).output)).toContain('Partly refunded $60 of $120');
    expect(texts(mount(() => mod.BuyerClosedBlock({ status: 'reversed', refund: { status: 'refunded', amount_refunded_cents: null, refunded_at: '2026-09-20T10:00:00Z', total: 12000 } })).output)).toContain('Refund recorded');
    // seller_sent for the buyer: the claim, then the review deadline from the server or nothing.
    const withDeadline = texts(mount(() => mod.BuyerSellerSentBlock({ autoReleaseAt: '2026-09-26T21:00:00Z' })).output);
    expect(withDeadline).toContain(buyerReviewDeadlineLine('2026-09-26T21:00:00Z'));
    expect(texts(mount(() => mod.BuyerSellerSentBlock({ autoReleaseAt: null })).output).join(' ')).not.toMatch(/before/);
  });
});

describe('the seller blocks — no payout claim before payout_released_at; the hold only when held with a date', () => {
  it('TG4: closed, reversed, held-with-date, held-without-date, manual review and the release decision line', async () => {
    const mod = await import('@/src/components/transfer/TransferStateBlocks');
    const closed = texts(mount(() => mod.SellerClosedBlock({ title: 'Transfer window expired', body: "The window to send these tickets has passed." })).output);
    expect(closed).toContain(SELLER_NO_PAYOUT_LINE);
    const reversed = texts(mount(() => mod.SellerReversedBlock({})).output);
    expect(reversed).toContain(SELLER_REVERSED_COPY.title);
    expect(reversed).toContain(SELLER_REVERSED_COPY.body);
    const held = texts(mount(() => mod.SellerSentBlock({ payoutReviewStatus: 'held', payoutHoldUntil: '2026-10-02T12:00:00Z', autoReleaseAt: null, releaseCountdown: null })).output);
    expect(held).toContain(sellerHoldLine('held', '2026-10-02T12:00:00Z'));
    const heldNoDate = texts(mount(() => mod.SellerSentBlock({ payoutReviewStatus: 'held', payoutHoldUntil: null, autoReleaseAt: null, releaseCountdown: null })).output).join(' ');
    expect(heldNoDate).toMatch(/funds are held until shortly after the event/);
    expect(heldNoDate).not.toMatch(/Payout held until/);
    const manual = texts(mount(() => mod.SellerSentBlock({ payoutReviewStatus: 'manual_review', payoutHoldUntil: null, autoReleaseAt: null, releaseCountdown: null })).output).join(' ');
    expect(manual).toMatch(/manual review/);
    const release = texts(mount(() => mod.SellerSentBlock({ payoutReviewStatus: null, payoutHoldUntil: null, autoReleaseAt: '2026-09-26T21:00:00Z', releaseCountdown: '2d 3h' })).output);
    expect(release).toContain(sellerReleaseLine('2026-09-26T21:00:00Z'));
    expect(release.join(' ')).not.toMatch(/has been released/);
  });
});

describe('the gallery — sandbox-only, read-only, synthetic and labelled', () => {
  it('TG5: outside a sandbox build (production config, a deep link) the route renders only a redirect home', async () => {
    th.sandbox = false;
    const mod = await import('@/app/_dev/transfer-states');
    const h = mount(() => (mod.default as () => unknown)());
    const out = h.output as Element;
    expect(out?.type).toBe('Redirect');
    expect(out?.props.href).toBe('/(tabs)/home');
    expect(texts(h.output)).toHaveLength(0);
  });

  it('TG6: in a sandbox build it renders every fixture through the shared blocks, each labelled synthetic, with no actionable transaction control', async () => {
    th.sandbox = true;
    const mod = await import('@/app/_dev/transfer-states');
    expect(mod.TRANSFER_STATE_FIXTURES.length).toBeGreaterThanOrEqual(12);
    const h = mount(() => (mod.default as () => unknown)());
    const t = texts(h.output);
    for (const f of mod.TRANSFER_STATE_FIXTURES) expect(t, f.id).toContain(f.label);
    expect(t.filter((x) => x === mod.SYNTHETIC_LABEL).length).toBeGreaterThanOrEqual(mod.TRANSFER_STATE_FIXTURES.length);
    // The approved combinations are all present as rendered text.
    expect(t).toContain('Refunded $120');
    expect(t).toContain('Partly refunded $60 of $120');
    expect(t).toContain(REFUND_DUE_POLICY);
    expect(t).toContain(REFUND_PENDING_LINE);
    expect(t).toContain(SELLER_REVERSED_COPY.title);
    expect(t.some((x) => x.startsWith('Payout held until'))).toBe(true);
    // Nothing on the page can confirm, send, report, pay or release anything.
    const actionable = findElement(expandTree(h.output), (el) =>
      (el.type === 'Button' || el.type === 'Pressable') &&
      /confirm|mark as sent|report|pay|release|dispute/i.test(String((el.props as { label?: string }).label ?? el.props.accessibilityLabel ?? '')));
    expect(actionable).toBeUndefined();
  });

  it('TG8: the gallery\'s and the blocks\' static imports are side-effect-free modules only (the guard runs at render, imports run at load)', async () => {
    // Owner 2026-09-24: "a component-level environment guard does not run before static imports. Keep
    // imports side-effect-free." Every module the route pulls in at load is a pure module or the app's
    // own theme/env layer; none opens a client, storage, network or dialog.
    const allowed = new Set([
      'expo-router', 'react', 'react-native', 'react-native-safe-area-context',
      '@/src/components/transfer/TransferStateBlocks', '@/src/config/envGuard', '@/src/lib/transfer/transferState',
      '@/src/theme/appearance', '@/src/theme/palette', '@/src/theme/typography', '@/src/theme/v2',
      '@/src/lib/listing/feedRowState', '@/src/lib/money',
    ]);
    for (const rel of ['app/_dev/transfer-states.tsx', 'src/components/transfer/TransferStateBlocks.tsx']) {
      const src = await stripped(rel);
      const imports = [...src.matchAll(/from '([^']+)'/g)].map((m) => m[1]);
      expect(imports.length, rel).toBeGreaterThan(0);
      for (const i of imports) expect(allowed.has(i), `${rel} imports ${i}`).toBe(true);
    }
    // And the blocks' own dependency, transferState, reaches nothing but the money formatter and the row formatter.
    const state = await stripped('src/lib/transfer/transferState.ts');
    for (const i of [...state.matchAll(/from '([^']+)'/g)].map((m) => m[1])) expect(allowed.has(i), `transferState imports ${i}`).toBe(true);
  });

  it('TG9: a missing payout_hold_until or auto_release_at suppresses only the corresponding date line — never the status information', async () => {
    const mod = await import('@/src/components/transfer/TransferStateBlocks');
    // Countdown running but the server gave no auto_release_at: no release line, no EMPTY line; body + warning stay.
    const noDate = mount(() => mod.SellerSentBlock({ payoutReviewStatus: null, payoutHoldUntil: null, autoReleaseAt: null, releaseCountdown: '2d 3h' }));
    const t = texts(noDate.output);
    expect(t.join(' ')).toMatch(/Waiting for the buyer to confirm/);
    expect(t.join(' ')).toMatch(/If the buyer reports an issue/);
    expect(t.join(' ')).not.toMatch(/Release decision/);
    expect(findElement(expandTree(noDate.output), (el) => el.type === 'Text' && el.props.children == null)).toBeUndefined();
    // Held without a date: the hold's status sentence stays; only the dated line is absent.
    const heldNoDate = texts(mount(() => mod.SellerSentBlock({ payoutReviewStatus: 'held', payoutHoldUntil: null, autoReleaseAt: null, releaseCountdown: null })).output).join(' ');
    expect(heldNoDate).toMatch(/funds are held until shortly after the event/);
    expect(heldNoDate).not.toMatch(/Payout held until/);
    // The buyer's claim without a server deadline: the claim stays, no deadline sentence, no empty line.
    const claim = mount(() => mod.BuyerSellerSentBlock({ autoReleaseAt: null }));
    expect(texts(claim.output).join(' ')).toMatch(/Seller marked as sent/);
    expect(findElement(expandTree(claim.output), (el) => el.type === 'Text' && el.props.children == null)).toBeUndefined();
  });

  it('TG7: the gallery reaches no server and no dialog, and its only entry is a sandbox-gated Settings row', async () => {
    const gallery = await stripped('app/_dev/transfer-states.tsx');
    expect(gallery).not.toMatch(/supabase|\.rpc\(|functions\.invoke|Alert\b|payments|fetch\(/);
    expect(gallery).toMatch(/if \(!\(IS_SANDBOX_BUILD \|\| __DEV__\)\) return <Redirect href="\/\(tabs\)\/home" \/>;/);
    expect(gallery).toContain('useAppearancePreference()');   // both appearances from inside the gallery
    const settings = await stripped('app/settings/index.tsx');
    expect(settings).toMatch(/\{IS_SANDBOX_BUILD \? \(\s*<AccountSection title="Sandbox">\s*<SettingsRow label="Transfer states \(sandbox gallery\)"/);
  });
});
