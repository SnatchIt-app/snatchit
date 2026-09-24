/**
 * V3 appearance — the shared primitives read the palette (owner 2026-09-23: shared semantic tokens,
 * never per-screen colours). Every screen inherits these, so migrating them is what makes Light real.
 *
 * Witness discipline: the behavioural check renders a primitive under the LIGHT palette and asserts an
 * ink that differs between the two palettes; the source pins assert no static dark token survives.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

const th = vi.hoisted(() => ({ scheme: 'light' as 'light' | 'dark' }));

vi.mock('react-native', () => ({
  Animated: { View: 'Animated.View', Value: class { v: number; constructor(v: number) { this.v = v; } interpolate() { return 0; } setValue(v: number) { this.v = v; } }, timing: () => ({ start: (cb?: () => void) => cb?.() }) },
  Pressable: 'Pressable', Text: 'Text', View: 'View', ActivityIndicator: 'ActivityIndicator',
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1, absoluteFill: {}, absoluteFillObject: {} },
  useWindowDimensions: () => ({ width: 390, height: 844 }),
}));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }) }));
vi.mock('@/components/ui/icon-symbol', () => ({ IconSymbol: 'IconSymbol' }));
vi.mock('@/src/hooks/useReducedMotion', () => ({ useReducedMotion: () => true }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, EASING_BEZIER: [0.2, 0, 0, 1] }));
vi.mock('@/src/theme/appearance', async () => {
  const { paletteFor } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: th.scheme, palette: paletteFor(th.scheme) }) };
});

import { dark, light } from '@/src/theme/palette';
import { findElement, HookHost } from './helpers/nav-stack-harness';

const PRIMITIVES = [
  'src/components/ui/Button.tsx', 'src/components/ui/IconButton.tsx', 'src/components/ui/Chip.tsx',
  'src/components/ui/Badge.tsx', 'src/components/ui/StateView.tsx', 'src/components/ui/Spinner.tsx',
  'src/components/ui/Skeleton.tsx', 'src/components/ui/StickyBar.tsx', 'src/components/ui/Input.tsx',
  'src/components/ui/MediaUpload.tsx', 'src/components/ui/Sheet.tsx',
  'src/components/PriceDisplay.tsx', 'src/components/nav/AdaptiveDock.tsx', 'src/components/media/EventMedia.tsx',
];

const styleJson = (el: { props: Record<string, unknown> } | undefined) => JSON.stringify(el?.props.style ?? null);

beforeEach(() => { th.scheme = 'light'; vi.resetModules(); });

describe('behaviour — a primitive rendered under Light wears the light inks', () => {
  it('PR1: StateView title ink is the light primary under Light and the dark primary under Dark', async () => {
    const mod = await import('@/src/components/ui/StateView');
    const mount = () => { const h = new HookHost(() => mod.StateView({ kind: 'noMatch' }), new Map()); h.mount(); h.flush(); return h; };
    const title = (h: HookHost) => findElement(h.output, (el) => el.props.accessibilityRole === 'header');
    expect(styleJson(title(mount()))).toContain(light.text.primary);
    th.scheme = 'dark';
    expect(styleJson(title(mount()))).toContain(dark.text.primary);
  });

  it('PR2: a secondary Button\'s label ink follows the palette; the primary keeps black on brand red in both', async () => {
    const mod = await import('@/src/components/ui/Button');
    const mount = (variant: 'primary' | 'secondary') => { const h = new HookHost(() => mod.Button({ label: 'Go', onPress: () => {}, variant }), new Map()); h.mount(); h.flush(); return h; };
    const label = (h: HookHost) => findElement(h.output, (el) => el.type === 'Text' && el.props.children === 'Go');
    expect(styleJson(label(mount('secondary')))).toContain(light.text.primary);
    expect(styleJson(label(mount('primary')))).toContain(light.text.inverse);
    th.scheme = 'dark';
    expect(styleJson(label(mount('secondary')))).toContain(dark.text.primary);
  });

  it('PR3: Badge tones resolve from the palette (light status colours under Light)', async () => {
    const mod = await import('@/src/components/ui/Badge');
    const h = new HookHost(() => mod.Badge({ label: 'Sold', tone: 'success' }), new Map());
    h.mount(); h.flush();
    const text = findElement(h.output, (el) => el.type === 'Text' && el.props.children === 'Sold');
    expect(styleJson(text)).toContain(light.status.success);
    expect(styleJson(text)).not.toContain(dark.status.success);
  });
});

describe('source — no static dark token survives in the shared primitives', () => {
  it('PR4: every primitive reads useTheme() and references no v2 colour group or legacy colours', async () => {
    const { readFileSync } = await import('node:fs');
    for (const rel of PRIMITIVES) {
      const src = readFileSync(rel, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
      expect(src, rel).toContain('useTheme()');
      expect(src, rel).not.toMatch(/v2\.(surface|text|border|brand|status)\./);
      expect(src, rel).not.toMatch(/\bcolors\.(bg|text|primary|border|error|success|warning)/);
    }
  });
});
