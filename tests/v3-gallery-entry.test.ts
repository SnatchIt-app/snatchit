/**
 * The tested way to OPEN the synthetic transfer-state gallery on the sandbox iPhone build (owner
 * 2026-09-24: "'Type the path' is insufficient"): the real Settings screen renders a "Sandbox" section
 * with the gallery row only in a paired sandbox build, and pressing it navigates to the route. In any
 * other build the row does not exist — and the route itself redirects home (v3-transfer-gallery TG5).
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

(globalThis as Record<string, unknown>).__DEV__ = false;
process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';

const h = vi.hoisted(() => ({ sandbox: false, pushed: [] as string[] }));

vi.mock('@/src/config/envGuard', () => ({ get IS_SANDBOX_BUILD() { return h.sandbox; }, ENV_GUARD_FAILURE: null }));
vi.mock('expo-router', () => ({ router: { push: (p: string) => { h.pushed.push(p); }, back: () => {}, replace: () => {} } }));
vi.mock('react-native', () => ({
  Alert: { alert: () => {} },
  AppState: { addEventListener: () => ({ remove: () => {} }), currentState: 'active' },
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Pressable: 'Pressable', ScrollView: 'ScrollView', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    auth: { getUser: async () => ({ data: { user: { id: 'buyer-1' } } }) },
    schema: () => ({ from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) }) }) }) }),
    functions: { invoke: async () => ({ data: null, error: null }) },
  },
}));
vi.mock('@/src/lib/auth/signOut', () => ({ SIGN_OUT_FAILED_COPY: { title: 'x', body: 'y' }, signOutAllDevices: async () => ({}), signOutThisDevice: async () => ({}) }));
vi.mock('@/src/components/ui', () => ({ Button: 'Button', IconButton: 'IconButton' }));
// The row and section are the app's own primitives; as plain elements their props (label, title, onPress)
// are what the screen wires, which is exactly what these tests assert.
vi.mock('@/src/components/account/SettingsRow', () => ({ SettingsRow: 'SettingsRow' }));
vi.mock('@/src/components/account/AccountSection', () => ({ AccountSection: 'AccountSection' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 0, useDockClearance: () => 0 }));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});

import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const GALLERY_LABEL = 'Transfer states (sandbox gallery)';
const flush = async () => { for (let i = 0; i < 6; i++) await new Promise((r) => setImmediate(r)); };

async function mountSettings(): Promise<HookHost> {
  const mod = await import('@/app/settings/index');
  const Screen = (mod.default ?? mod) as () => unknown;
  const host = new HookHost(() => Screen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}
const galleryRow = (host: HookHost) =>
  findElement(host.output, (el) => (el.props as { label?: string }).label === GALLERY_LABEL);

beforeEach(() => { h.sandbox = false; h.pushed.length = 0; vi.resetModules(); });

describe('opening the gallery from the real Settings screen', () => {
  it('SG1: in a paired sandbox build the "Sandbox" section offers the row, and pressing it navigates to the gallery route', async () => {
    h.sandbox = true;
    const host = await mountSettings();
    const row = galleryRow(host);
    expect(row).toBeDefined();
    (row!.props.onPress as () => void)();
    expect(h.pushed).toEqual(['/_dev/transfer-states']);
    // The section is labelled so a tester can find it, and the row's own description says what it is.
    expect(findElement(host.output, (el) => (el.props as { title?: string }).title === 'Sandbox')).toBeDefined();
    expect((row!.props as { description?: string }).description).toBe('Synthetic fixtures, both appearances');
  });

  it('SG2: in any other build there is no such row and no "Sandbox" section — nothing to tap, nothing to discover', async () => {
    h.sandbox = false;
    const host = await mountSettings();
    expect(galleryRow(host)).toBeUndefined();
    expect(findElement(host.output, (el) => (el.props as { title?: string }).title === 'Sandbox')).toBeUndefined();
    const all = expandTree(host.output);
    expect(findElement(all, (el) => typeof (el as Element).props.children === 'string' && /sandbox gallery/i.test((el as Element).props.children as string))).toBeUndefined();
  });
});
