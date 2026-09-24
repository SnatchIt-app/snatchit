/**
 * V3 "You" navigation item (owner approval 2026-09-22) — acceptance 7–12 groundwork.
 *
 * The dock shows the signed-in user's photo in the profile slot: identical 28pt circle in every
 * image state (photo / none / loading-fallback / failed), ring + capsule for selected, a 12% dim —
 * never a smudge — for unselected, visible labels with "You" as both the visible and accessible
 * name, and NO fetch of its own. A previous account's photo never renders after the account
 * changes: the store's owner guard is exercised here through the real component.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });
process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';

const h = vi.hoisted(() => ({ userId: 'user-1' as string | null }));

// V3 appearance: primitives read the palette; pin the shipped dark one here.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => {
  class Value {
    v: number;
    constructor(v: number) { this.v = v; }
    interpolate() { return 0; }
    setValue(v: number) { this.v = v; }
  }
  return {
    AccessibilityInfo: {
      isReduceMotionEnabled: async () => true,
      addEventListener: () => ({ remove: () => {} }),
    },
    Animated: { View: 'Animated.View', Value, timing: () => ({ start: (cb?: () => void) => cb?.() }) },
    Keyboard: { addListener: () => ({ remove: () => {} }) },
    Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
    PixelRatio: { get: () => 2 },
    Pressable: 'Pressable', Text: 'Text', View: 'View',
    StyleSheet: {
      create: <T,>(s: T) => s,
      hairlineWidth: 1,
      absoluteFill: { position: 'absolute' },
      absoluteFillObject: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
    },
    useWindowDimensions: () => ({ width: 390, height: 844 }),
  };
});
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
vi.mock('expo-image', () => ({ Image: 'Image' }));
vi.mock('@/components/ui/icon-symbol', () => ({ IconSymbol: 'IconSymbol' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));
vi.mock('@/src/components/nav/dockContext', () => ({
  useDockCollapsed: () => false,
  useDockExpander: () => () => {},
}));
vi.mock('@/src/lib/nav/navInsets', () => ({ DOCK_GAP: 12, DOCK_HEIGHT: 66, DOCK_RADIUS: 33, DOCK_SIDE_MARGIN: 16 }));
vi.mock('@/src/hooks/useAuth', () => ({
  useAuth: () => ({ user: h.userId ? { id: h.userId } : null, session: h.userId ? { user: { id: h.userId } } : null }),
}));
vi.mock('@/src/lib/avatarImage', () => ({
  getAvatarUrl: (path: string | null | undefined, opts: { width?: number } = {}) =>
    path ? `mock://avatars/${path}?w=${opts.width}` : null,
}));

import { clearDockAvatar, setDockAvatar } from '@/src/lib/nav/dockAvatar';
import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

const ROUTES = ['home', 'create', 'bids', 'tickets', 'profile'].map((name, i) => ({ key: `k${i}`, name }));

async function mountDock(activeIndex = 0): Promise<HookHost> {
  const mod = await import('@/src/components/nav/AdaptiveDock');
  const Dock = mod.AdaptiveDock as (p: unknown) => unknown;
  const props = {
    state: { index: activeIndex, routes: ROUTES },
    navigation: { emit: () => ({ defaultPrevented: false }), navigate: () => {} },
    descriptors: {}, insets: { top: 0, bottom: 0, left: 0, right: 0 },
  };
  const host = new HookHost(() => Dock(props), new Map());
  host.mount();
  host.flush();
  return host;
}

function texts(host: HookHost): string {
  const out: string[] = [];
  const walk = (node: unknown) => {
    if (Array.isArray(node)) { node.forEach(walk); return; }
    const el = node as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (typeof el.props.children === 'string') out.push(el.props.children);
    walk(el.props.children);
  };
  walk(host.output);
  return out.join(' | ');
}
const youTab = (host: HookHost) => findElement(host.output, (el) => el.type === 'Pressable' && el.props.accessibilityLabel === 'You');
const avatarImage = (host: HookHost) => findElement(host.output, (el) => el.type === 'Image' && String((el.props.source as { uri?: string })?.uri ?? '').includes('mock://avatars/'));
const personIcon = (host: HookHost) => findElement(host.output, (el) => el.type === 'IconSymbol' && el.props.name === 'person.fill');
const ring = (host: HookHost) => findElement(host.output, (el) => el.props.testID === 'dock-you-ring');
const dim = (host: HookHost) => findElement(host.output, (el) => el.props.testID === 'dock-you-dim');

beforeEach(() => {
  h.userId = 'user-1';
  clearDockAvatar();
  // NO vi.resetModules(): the dock must share THIS file's dockAvatar module instance, or the
  // test would write to one store while the component reads another.
});

describe('labels and accessibility (O-5; acceptance 12)', () => {
  it('Y1: every destination shows its label; the profile item is "You" — visible AND accessible — and selection is announced', async () => {
    const host = await mountDock(4);   // profile focused
    const shown = texts(host);
    // V3 (owner ruling 2026-09-22): Create is labelled "Sell" — same destination, same behaviour.
    for (const label of ['Home', 'Sell', 'Bids', 'Tickets', 'You']) expect(shown).toContain(label);
    expect(shown).not.toContain('Profile');
    expect(shown).not.toContain('Create');
    const tab = youTab(host);
    expect(tab).toBeDefined();
    expect(tab?.props.accessibilityState).toEqual({ selected: true });
    expect(tab?.props.accessibilityRole).toBe('tab');
  });
});

describe('the four image states — one 28pt circle, no reflow (acceptance 7–9)', () => {
  it('Y2: with a photo for the CURRENT user, the circle renders it, cover-cropped at 28pt from a 28pt request', async () => {
    setDockAvatar('user-1', 'user-1/a.jpg');
    const host = await mountDock(0);
    const img = avatarImage(host);
    expect(img).toBeDefined();
    expect((img?.props.source as { uri: string }).uri).toBe('mock://avatars/user-1/a.jpg?w=28');
    expect(img?.props.contentFit).toBe('cover');
    expect(personIcon(host)).toBeUndefined();
  });

  it('Y3: a previous account\'s photo never renders after the account changes (acceptance 10)', async () => {
    setDockAvatar('user-1', 'user-1/a.jpg');
    h.userId = 'user-2';               // switched account; the stale entry was never cleared
    const host = await mountDock(0);
    expect(avatarImage(host)).toBeUndefined();
    expect(personIcon(host)).toBeDefined();
  });

  it('Y4: no photo → the existing person icon; signed out → the person icon', async () => {
    setDockAvatar('user-1', null);
    let host = await mountDock(0);
    expect(avatarImage(host)).toBeUndefined();
    expect(personIcon(host)).toBeDefined();

    h.userId = null;
    host = await mountDock(0);
    expect(personIcon(host)).toBeDefined();
  });

  it('Y5: a failed image falls back to the person icon — never a broken-image glyph', async () => {
    setDockAvatar('user-1', 'user-1/broken.jpg');
    const host = await mountDock(0);
    const img = avatarImage(host);
    expect(img).toBeDefined();
    (img?.props.onError as () => void)();
    host.flush();
    expect(avatarImage(host)).toBeUndefined();
    expect(personIcon(host)).toBeDefined();
  });

  it('Y6: replacement and removal update the dock without a restart (acceptance 11)', async () => {
    setDockAvatar('user-1', 'user-1/a.jpg');
    const host = await mountDock(0);
    setDockAvatar('user-1', 'user-1/b.jpg');
    host.flush();
    expect((avatarImage(host)?.props.source as { uri: string }).uri).toContain('b.jpg');
    setDockAvatar('user-1', null);     // removal → icon, the day a removal flow ships
    host.flush();
    expect(avatarImage(host)).toBeUndefined();
    expect(personIcon(host)).toBeDefined();
  });
});

describe('selected and unselected treatments (acceptance 8)', () => {
  it('Y7: selected = capsule + a ring in text.primary; no dim over the photo', async () => {
    setDockAvatar('user-1', 'user-1/a.jpg');
    const host = await mountDock(4);
    expect(ring(host)).toBeDefined();
    expect(dim(host)).toBeUndefined();
  });

  it('Y8: unselected = recognisable photo with only the 12% dim; no ring; and never red anywhere', async () => {
    setDockAvatar('user-1', 'user-1/a.jpg');
    const host = await mountDock(0);   // Home focused
    expect(ring(host)).toBeUndefined();
    const overlay = dim(host);
    expect(overlay).toBeDefined();
    expect(avatarImage(host)).toBeDefined();   // the photo still renders under the dim
    const styles = JSON.stringify([overlay?.props.style, ring(host)?.props.style ?? null]);
    expect(styles).not.toMatch(/FF1A1A/i);
  });
});

describe('the dock never fetches (source pin)', () => {
  it('Y9: AdaptiveDock has no supabase, rpc, fetch or avatar-store WRITE — it only subscribes', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/components/nav/AdaptiveDock.tsx', 'utf8');
    expect(src).not.toMatch(/supabase|rpc\(|fetch\(|setDockAvatar/);
    expect(src).toContain('subscribeDockAvatar');
    expect(src).toContain('dockAvatarPathFor');
    expect(src).toContain('width: AVATAR');   // the 28pt request, never full size
  });
});
