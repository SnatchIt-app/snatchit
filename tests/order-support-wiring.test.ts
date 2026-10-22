/**
 * tests/order-support-wiring.test.ts — "Contact support about this order" on both order screens, and
 * the Support screen's copy (CFT-406 slice 1, the C-owned wiring).
 *
 * Mounts the REAL receive and send screens with harness fixtures (no read leaves the app) in every
 * transfer state, presses the action, and reads the mailto it opens: the role is the screen's, and
 * the status word in the subject is the word on the screen's own badge — the email never says
 * something the screen does not. Both screens take that badge from orderBadgeMeta, the selector the
 * email uses (OW2 pins the source; OW1 is the behavioural check in nine states). The Support screen
 * no longer asks for a "listing ID" that no screen shows; it points at the order screens' action
 * instead, by its exact label.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';
import { ORDER_SUPPORT_COPY } from '@/src/lib/support/orderSupport';

const h = vi.hoisted(() => ({ opened: [] as string[] }));

vi.mock('react-native', () => ({
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Alert: { alert: () => {} },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  AccessibilityInfo: { announceForAccessibility: () => {} },
  ActionSheetIOS: { showActionSheetWithOptions: () => {} },
  ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  Linking: { openURL: async (url: string) => { h.opened.push(url); return true; } },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Image: 'Image', Modal: 'Modal', KeyboardAvoidingView: 'KeyboardAvoidingView',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {}, replace: () => {} }, useLocalSearchParams: () => ({ id: 'fixture-order' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'viewer-1' }, session: { user: { id: 'viewer-1' } } }) }));
vi.mock('@/src/hooks/useNetworkStatus', () => ({ useNetworkStatus: () => ({ isOffline: false }), isNetworkError: () => false }));
vi.mock('@/src/components/ScreenState', () => ({ default: 'ScreenState' }));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge', Button: 'Button', IconButton: 'IconButton', MediaUpload: 'MediaUpload', Spinner: 'Spinner', EmptyState: 'EmptyState', Tappable: 'Tappable' }));
vi.mock('@/src/components/DeliveryInfoForm', () => ({ default: 'DeliveryInfoForm' }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/NameText', () => ({ NameText: 'NameText' }));
vi.mock('@/src/components/ProofImageViewer', () => ({ ProofImageViewer: 'ProofImageViewer' }));
vi.mock('@/src/components/PlatformInstructions', () => ({ default: 'PlatformInstructions' }));
vi.mock('@/src/lib/feedback/haptics', () => ({ hapticSuccess: () => {} }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useDockClearance: () => 0, useTopInset: () => 0 }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6 }));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('@/src/hooks/useImageUpload', () => ({
  useImageUpload: () => ({ localUri: null, status: 'idle', error: null, busy: false, pickImage: () => {}, reset: () => {}, readError: () => null, uploadImage: async () => null }),
}));
// Fixtures only: a read or RPC leaving the app is a failure of the fixture contract — except the
// buyer screen's mount-time mark_transfer_viewed, which is answered and ignored.
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    from: () => { throw new Error('fixture must not read'); },
    rpc: () => Promise.resolve({ data: null, error: null }),
    auth: { getUser: async () => ({ data: { user: null } }) },
    storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) },
  },
}));

const ID = '3f2a9c1b-7d4e-4a8f-9b6c-2e1d0a9f8c7b';
const BASE = {
  id: ID, listing_id: 'fixture-listing', status: 'seller_sent', transfer_method: 'mobile_transfer',
  expires_at: null, auto_release_at: null, buyer_confirmed_at: null, payout_released_at: null,
  payout_review_status: null, payout_hold_until: null,
  dispute_resolution: null, dispute_resolved_at: null,
  delivery_email: 'buyer.private@example.test', delivery_phone: '+13055554417', transfer_evidence_path: null,
  seller: { display_name: 'Sam Seller' }, seller_id: 'fixture-seller',
  buyer: { display_name: 'Bea Buyer' }, buyer_id: 'fixture-buyer',
  listing: { event_name: 'Neon Choir', ticket_platform: 'dice', event_date: '2026-10-24', event_time: '19:30', venue: 'Lantern Room', quantity: 2, ticket_type: 'GA', cover_image_path: null },
};

const STATES: [string, Record<string, unknown>][] = [
  ['pending', { status: 'pending' }],
  ['seller_sent', { status: 'seller_sent' }],
  ['buyer_confirmed (buyer confirmed)', { status: 'buyer_confirmed', buyer_confirmed_at: '2026-10-20T10:00:00Z' }],
  ['buyer_confirmed (operator decision)', { status: 'buyer_confirmed', buyer_confirmed_at: null, dispute_resolution: 'resolved_seller_paid' }],
  ['auto_released', { status: 'auto_released' }],
  ['disputed (open)', { status: 'disputed' }],
  ['disputed (decided)', { status: 'disputed', dispute_resolution: 'resolved_buyer_refunded', dispute_resolved_at: '2026-10-20T10:00:00Z' }],
  ['expired', { status: 'expired' }],
  ['reversed', { status: 'reversed', payout_released_at: '2026-10-19T10:00:00Z' }],
];

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

async function mountScreen(which: 'receive' | 'send', transfer: Record<string, unknown>): Promise<HookHost> {
  const mod = which === 'receive' ? await import('@/app/transfer/receive/[id]') : await import('@/app/transfer/send/[id]');
  const Screen = (mod.default ?? mod) as (p: { fixture?: unknown }) => unknown;
  const fixture = which === 'receive' ? { transfer, settled: [] } : { transfer };
  const host = new HookHost(() => Screen({ fixture }), new Map());
  host.mount(); await flush(); host.flush();
  return host;
}

const supportButtons = (tree: unknown): Element[] => {
  const out: Element[] = [];
  const walk = (n: unknown) => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (el.type === 'Button' && el.props.label === ORDER_SUPPORT_COPY.action) out.push(el);
    walk(el.props.children);
  };
  walk(tree);
  return out;
};

function subjectAndBody(url: string): { subject: string; body: string } {
  const query = url.slice(url.indexOf('?') + 1);
  const params = new Map(query.split('&').map((p) => [p.slice(0, p.indexOf('=')), decodeURIComponent(p.slice(p.indexOf('=') + 1))] as const));
  return { subject: params.get('subject') ?? '', body: params.get('body') ?? '' };
}

beforeEach(() => { h.opened.length = 0; });

for (const [which, role] of [['receive', 'Buyer'], ['send', 'Seller']] as const) {
  describe(`OW1 · ${which} screen (${role.toLowerCase()})`, () => {
    for (const [name, over] of STATES) {
      it(`${name}: one support action; its email carries this order, the ${role.toLowerCase()} role and the badge's word`, async () => {
        const host = await mountScreen(which, { ...BASE, ...over });
        const tree = expandTree(host.output);
        const buttons = supportButtons(tree);
        expect(buttons, 'expected exactly one "Contact support about this order"').toHaveLength(1);
        expect(buttons[0].props.variant).toBe('secondary');

        (buttons[0].props.onPress as () => void)();
        await flush();
        expect(h.opened).toHaveLength(1);
        expect(h.opened[0].startsWith('mailto:support@snatchitapp.com?subject=')).toBe(true);
        const { subject, body } = subjectAndBody(h.opened[0]);

        const badge = findElement(tree, (el) => el.type === 'Badge') as Element | undefined;
        expect(badge, 'the screen shows a status badge').toBeDefined();
        expect(subject).toBe(`Order 3f2a9c1b · ${badge!.props.label as string}`);
        expect(body).toContain(`Order ID: ${ID}\r\n`);
        expect(body).toContain(`Status: ${badge!.props.label as string}\r\n`);
        expect(body).toContain(`Role: ${role}\r\n`);
        // Only the order reference, its status and the role (C review M1): no event name — it is seller free text.
        expect(body.startsWith(`Order ID: ${ID}\r\n`)).toBe(true);
        for (const secret of ['Event', 'Neon', 'Choir', 'buyer.private', '3055554417', 'Sam', 'Bea', 'Lantern', 'fixture-seller', 'fixture-buyer', 'fixture-listing']) {
          expect(`${subject}\n${body}`, secret).not.toContain(secret);
        }
      });
    }
  });
}

describe('OW2 · source contract on the C-owned screens', () => {
  const src = (rel: string) => readFileSync(resolve(__dirname, '..', rel), 'utf8');
  for (const [rel, role] of [['app/transfer/receive/[id].tsx', 'buyer'], ['app/transfer/send/[id].tsx', 'seller']] as const) {
    it(`${rel}: renders the action once, for the ${role}, only after the order has loaded`, () => {
      const s = src(rel);
      expect(s).toContain("import { OrderSupportAction } from '@/src/components/transfer/OrderSupportAction';");
      expect(s.match(/<OrderSupportAction /g)).toHaveLength(1);
      expect(s).toContain(`<OrderSupportAction role="${role}" transfer={transfer} />`);
      // Not on the loading, offline, error or not-found states: those return before the order renders.
      expect(s.indexOf('<OrderSupportAction ')).toBeGreaterThan(s.indexOf('if (error || !transfer)'));
    });

    it(`${rel}: the badge comes from orderBadgeMeta(transfer, '${role}') — the email's selector — not an inline expression`, () => {
      const s = src(rel);
      expect(s).toContain("import { orderBadgeMeta } from '@/src/lib/transfer/orderBadge';");
      expect(s.match(/const meta = /g)).toHaveLength(1);
      expect(s).toContain(`const meta = orderBadgeMeta(transfer, '${role}');`);
      expect(s.match(/orderBadgeMeta\(/g)).toHaveLength(1);
      expect(s).toContain('<Badge label={meta.label} tone={meta.tone} />');
      // The former inline badge expression is gone (both of its branches).
      expect(s).not.toMatch(/transferStatusMeta\(\s*transfer\.status/);
      expect(s).not.toMatch(/disputedStateMeta\(/);
    });
  }
});

describe('OW3 · the Support screen copy', () => {
  // Comments stripped (as tests/v3-no-service-time-promises.test.ts does): a phrase quoted in a
  // rationale is not a phrase the screen says. Then the rendered text: entities resolved, wraps joined.
  const support = readFileSync(resolve(__dirname, '..', 'app/settings/support.tsx'), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1')
    .replace(/&apos;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, ' ');

  it('no longer asks for a listing ID that no screen shows', () => {
    expect(support).not.toMatch(/listing ID/i);
  });

  it('points at the order screens\' action by its exact label', () => {
    expect(support).toContain(`"${ORDER_SUPPORT_COPY.action}"`);
  });

  it('keeps what it had: the mailto, the address, a description of the issue, no reply time', () => {
    expect(support).toContain('mailto:');
    expect(support).toContain('support@snatchitapp.com');
    expect(support).toMatch(/a description of the issue/);
    expect(support).not.toMatch(/within \d+|business day|live chat/i);
  });
});
