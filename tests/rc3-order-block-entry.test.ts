/**
 * tests/rc3-order-block-entry.test.ts — C-RC3-2: the Block entry paints on the order screens.
 *
 * On the RC3 50d8fcf1 binary the `_dev/v3-tickets?screen=order` harness showed no "More actions"
 * control: both order screens derive `userId` as `session?.user.id ?? ''`, and the harness fallback
 * `userId ?? 'fixture-viewer'` never fires on an empty string. Production is unaffected (a signed-in
 * viewer has an id; a signed-out one never reaches the order), but the harness — the only way the
 * entry can be reviewed without a sign-in — painted nothing. This test mounts the REAL screens with a
 * fixture and NO session and reads the header.
 */
import { describe, expect, it, vi } from 'vitest';

import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

vi.mock('react-native', () => ({
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: 1 }),
  Alert: { alert: () => {} },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  AccessibilityInfo: { announceForAccessibility: () => {} },
  ActionSheetIOS: { showActionSheetWithOptions: () => {} },
  ActivityIndicator: 'ActivityIndicator', Pressable: 'Pressable', RefreshControl: 'RefreshControl',
  ScrollView: 'ScrollView', Text: 'Text', View: 'View', Linking: { openURL: () => {} },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Image: 'Image', Modal: 'Modal', KeyboardAvoidingView: 'KeyboardAvoidingView',
  StyleSheet: { create: <T,>(s: T) => s },
}));
vi.mock('expo-router', () => ({ router: { push: () => {}, back: () => {}, replace: () => {} }, useLocalSearchParams: () => ({ id: 'fixture-order' }) }));
vi.mock('@react-navigation/native', () => ({ useFocusEffect: () => {} }));
// SIGNED OUT: the harness case.
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: null, session: null }) }));
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
// No read leaves the app under a fixture; anything that does is a failure of the fixture contract.
vi.mock('@/src/lib/supabase', () => ({ supabase: { from: () => { throw new Error('fixture must not read'); }, rpc: () => { throw new Error('fixture must not rpc'); }, auth: { getUser: async () => ({ data: { user: null } }) }, storage: { from: () => ({ createSignedUrl: async () => ({ data: null, error: null }) }) } } }));

const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

const TRANSFER = {
  id: 'fixture-order', listing_id: 'fixture-listing', status: 'seller_sent', transfer_method: 'mobile_transfer',
  expires_at: null, auto_release_at: new Date(Date.now() + 40 * 3600_000).toISOString(), buyer_confirmed_at: null,
  payout_released_at: null, dispute_resolution: null, dispute_resolved_at: null, delivery_email: 'b@example.test',
  delivery_phone: null, transfer_evidence_path: null, seller: { display_name: 'the seller' }, seller_id: 'fixture-seller',
  listing: { event_name: 'Neon Choir', ticket_platform: 'dice', event_date: '2026-10-24', event_time: '19:30', venue: 'Lantern Room', quantity: 2, ticket_type: 'GA', cover_image_path: null },
};

async function mountReceive(fixture: unknown): Promise<HookHost> {
  const mod = await import('@/app/transfer/receive/[id]');
  const Screen = (mod.default ?? mod) as (p: { fixture?: unknown }) => unknown;
  const host = new HookHost(() => Screen({ fixture }), new Map());
  host.mount(); await flush(); host.flush(); return host;
}
async function mountSend(fixture: unknown): Promise<HookHost> {
  const mod = await import('@/app/transfer/send/[id]');
  const Screen = (mod.default ?? mod) as (p: { fixture?: unknown }) => unknown;
  const host = new HookHost(() => Screen({ fixture }), new Map());
  host.mount(); await flush(); host.flush(); return host;
}
const moreButton = (host: HookHost) =>
  findElement(expandTree(host.output), (el) => el.type === 'IconButton' && el.props.glyph === 'more') as Element | undefined;

describe('C-RC3-2 · the Block entry paints under a fixture with no session', () => {
  it('OB1: the buyer order screen shows "More actions" when the fixture names the seller', async () => {
    const host = await mountReceive({ transfer: TRANSFER, settled: [{ status: 'succeeded', amount_refunded_cents: null, refunded_at: null, total: 9900 }] });
    const more = moreButton(host);
    expect(more, 'no More control in the header').toBeDefined();
    expect(more!.props.accessibilityLabel).toBe('More actions');
  });

  it('OB2: the seller send screen shows it when the fixture names the buyer', async () => {
    const host = await mountSend({ transfer: { ...TRANSFER, delivery_email: null, delivery_phone: '(305) 555-4417', payout_review_status: null, payout_hold_until: null, buyer: { display_name: 'Buyer One' }, buyer_id: 'fixture-buyer' } });
    const more = moreButton(host);
    expect(more, 'no More control in the header').toBeDefined();
  });

  it('OB3: without a counterparty id there is no entry (the spacer stays)', async () => {
    const { seller_id: _dropped, ...noSeller } = TRANSFER;
    const host = await mountReceive({ transfer: noSeller, settled: [] });
    expect(moreButton(host)).toBeUndefined();
  });
});
