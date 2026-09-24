/**
 * V3 appearance — RENDERED colour combinations (owner 2026-09-24: "verify the rendered colour
 * combinations, not merely that components accept a palette"; B's A-1…A-5).
 *
 * Each check mounts the real component under one palette, reads the style values it actually
 * emits, composites translucent layers over what sits beneath them, and computes WCAG contrast on
 * the result. This is harness-rendered evidence — the values a screen would paint — not a device
 * observation; the device rows (D-9) stay open until a phone runs the build.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });
process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';

const th = vi.hoisted(() => ({ scheme: 'light' as 'light' | 'dark' }));

vi.mock('@/src/theme/appearance', async () => {
  const { paletteFor } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: th.scheme, palette: paletteFor(th.scheme) }) };
});
vi.mock('react-native', () => {
  class Value {
    v: number;
    constructor(v: number) { this.v = v; }
    interpolate() { return 0; }
    setValue(v: number) { this.v = v; }
  }
  return {
    AccessibilityInfo: { isReduceMotionEnabled: async () => true, addEventListener: () => ({ remove: () => {} }) },
    Animated: { View: 'Animated.View', Value, timing: () => ({ start: (cb?: () => void) => cb?.() }) },
    Keyboard: { addListener: () => ({ remove: () => {} }) },
    Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
    PixelRatio: { get: () => 2 },
    Pressable: 'Pressable', Text: 'Text', View: 'View', ScrollView: 'ScrollView', ActivityIndicator: 'ActivityIndicator',
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
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, EASING_BEZIER: [0.2, 0, 0, 1] }));
vi.mock('@/src/theme/fonts', () => ({ fontFamily: () => 'Inter', useBrandFonts: () => true }));
vi.mock('@/src/hooks/useReducedMotion', () => ({ useReducedMotion: () => true }));
vi.mock('@/src/components/nav/dockContext', () => ({ useDockCollapsed: () => false, useDockExpander: () => () => {} }));
vi.mock('@/src/lib/nav/navInsets', () => ({ DOCK_GAP: 12, DOCK_HEIGHT: 66, DOCK_RADIUS: 33, DOCK_SIDE_MARGIN: 16 }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'user-1' }, session: { user: { id: 'user-1' } } }) }));
vi.mock('@/src/lib/avatarImage', () => ({ getAvatarUrl: () => null }));

import { dark, light, type Palette } from '@/src/theme/palette';
import { findElement, HookHost, type Element } from './helpers/nav-stack-harness';

// ── WCAG helpers (rgba composited over an opaque backdrop) ──────────────────────────────────────
function parse(c: string): [number, number, number, number] {
  const hex = c.match(/^#([0-9a-f]{6})$/i);
  if (hex) { const n = parseInt(hex[1], 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1]; }
  const m = c.match(/rgba?\(([^)]+)\)/);
  if (!m) throw new Error(`unparseable colour ${c}`);
  const [r, g, b, a = '1'] = m[1].split(',').map((s) => s.trim());
  return [Number(r), Number(g), Number(b), Number(a)];
}
/** `fg` over `bg`, returned as an opaque hex so it can be composited again. */
function over(fg: string, bg: string): string {
  const [r, g, b, a] = parse(fg); const [br, bgc, bb] = parse(bg);
  const c = [r * a + br * (1 - a), g * a + bgc * (1 - a), b * a + bb * (1 - a)].map((v) => Math.round(v));
  return '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');
}
function lum(hex: string): number {
  const [r, g, b] = parse(hex);
  const f = (v: number) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
function contrast(fg: string, bg: string): number {
  const l1 = lum(over(fg, bg)); const l2 = lum(over(bg, bg));
  const [a, b] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (a + 0.05) / (b + 0.05);
}
/** The one value a style array resolves a key to (last wins, as React Native flattens). */
function styleValue(el: Element | undefined, key: string): string | undefined {
  const flat: Record<string, unknown> = {};
  const walk = (s: unknown) => { if (Array.isArray(s)) s.forEach(walk); else if (s && typeof s === 'object') Object.assign(flat, s); };
  walk(el?.props.style);
  return flat[key] as string | undefined;
}
const stripped = async (rel: string) => (await import('node:fs')).readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const palettes: [string, Palette][] = [['light', light], ['dark', dark]];

beforeEach(() => { th.scheme = 'light'; vi.resetModules(); });

// ── The dock (B's A-1, A-2) ─────────────────────────────────────────────────────────────────────
describe('AdaptiveDock — the floating material and its inks, composited over the canvas', () => {
  const ROUTES = ['home', 'create', 'bids', 'tickets', 'profile'].map((name, i) => ({ key: `k${i}`, name }));
  async function mountDock(activeIndex = 0): Promise<HookHost> {
    const mod = await import('@/src/components/nav/AdaptiveDock');
    const Dock = mod.AdaptiveDock as (p: unknown) => unknown;
    const host = new HookHost(() => Dock({
      state: { index: activeIndex, routes: ROUTES },
      navigation: { emit: () => ({ defaultPrevented: false }), navigate: () => {} },
      descriptors: {}, insets: { top: 0, bottom: 0, left: 0, right: 0 },
    }), new Map());
    host.mount(); host.flush();
    return host;
  }
  const byText = (h: HookHost, t: string) => findElement(h.output, (el) => el.type === 'Text' && el.props.children === t);

  it('RD1: dock surface, edge and selected capsule come from the palette; both label inks clear 4.5:1 over the composited dock in BOTH appearances', async () => {
    for (const [scheme, p] of palettes) {
      th.scheme = scheme as 'light' | 'dark';
      vi.resetModules();
      const h = await mountDock(0);                                   // Home selected
      const surface = findElement(h.output, (el) => el.props.testID === 'dock-surface');
      const capsule = findElement(h.output, (el) => el.props.testID === 'dock-selected');
      expect(styleValue(surface, 'backgroundColor'), scheme).toBe(p.chrome.glass);
      expect(styleValue(surface, 'borderColor'), scheme).toBe(p.chrome.glassEdge);
      expect(styleValue(capsule, 'backgroundColor'), scheme).toBe(p.chrome.glassSelected);
      // What is painted: glass over the canvas; the capsule over that for the active item.
      const dockFill = over(p.chrome.glass, p.surface.canvas);
      const activeFill = over(p.chrome.glassSelected, dockFill);
      const active = byText(h, 'Home');
      const inactive = byText(h, 'Sell');
      expect(contrast(styleValue(active, 'color')!, activeFill), `${scheme} active`).toBeGreaterThanOrEqual(4.5);
      expect(contrast(styleValue(inactive, 'color')!, dockFill), `${scheme} inactive`).toBeGreaterThanOrEqual(4.5);
      // The dock is a distinct control surface, not a smudge: its edge or fill separates it from the canvas.
      const edgeOnCanvas = contrast(over(p.chrome.glassEdge, dockFill), p.surface.canvas);
      const fillOnCanvas = contrast(dockFill, p.surface.canvas);
      expect(Math.max(edgeOnCanvas, fillOnCanvas), `${scheme} dock vs canvas`).toBeGreaterThanOrEqual(1.2);
    }
  });

  it('RD2: no hard-coded white or near-black literal survives in the dock', async () => {
    const src = await stripped('src/components/nav/AdaptiveDock.tsx');
    expect(src).not.toMatch(/rgba\(255,255,255/);
    expect(src).not.toMatch(/rgba\(18,18,20/);
  });
});

// ── The image fallback initial (B's A-5) ────────────────────────────────────────────────────────
describe('EventMedia — the missing-artwork plate keeps its initial legible in both appearances', () => {
  it('RD3: the initial is the palette\'s muted ink and clears 3:1 (large text) on the plate in BOTH appearances', async () => {
    for (const [scheme, p] of palettes) {
      th.scheme = scheme as 'light' | 'dark';
      vi.resetModules();
      const mod = await import('@/src/components/media/EventMedia');
      const Media = ((mod.EventMedia as { type?: unknown }).type ?? mod.EventMedia) as (props: unknown) => unknown;
      const h = new HookHost(() => Media({ asset: { path: null }, slot: 'DISCOVERY_CARD', width: 200, title: 'Neon Choir' }), new Map());
      h.mount(); h.flush();
      // The harness is shallow: the plate is a nested component element. Render it with its own
      // props to read what it paints.
      const plateEl = findElement(h.output, (el) => typeof el.type === 'function' && (el.type as { name?: string }).name === 'FallbackPlate');
      expect(plateEl, `${scheme} plate element`).toBeDefined();
      const h2 = new HookHost(() => (plateEl!.type as (props: unknown) => unknown)(plateEl!.props), new Map());
      h2.mount(); h2.flush();
      const plate = findElement(h2.output, (el) => el.type === 'View' && JSON.stringify(el.props.style ?? '').includes('"flex":1'));
      const initial = findElement(h2.output, (el) => el.type === 'Text' && el.props.children === 'N');
      expect(initial, scheme).toBeDefined();
      expect(styleValue(initial, 'color'), scheme).toBe(p.text.muted);
      const plateFill = styleValue(plate, 'backgroundColor');
      expect(plateFill, `${scheme} plate fill`).toBeDefined();
      expect(contrast(p.text.muted, over(plateFill!, p.surface.canvas)), `${scheme} initial on plate`).toBeGreaterThanOrEqual(3);
    }
  });

  it('RD4: the only white literals left in EventMedia are the scrim gradients over artwork (which do not invert)', async () => {
    const src = await stripped('src/components/media/EventMedia.tsx');
    expect(src).not.toMatch(/rgba\(255,255,255/);
    expect(src).toMatch(/linear-gradient\(to bottom, rgba\(0,0,0,0\)/);
  });
});

// ── StatCardStrip (B's A-4) ─────────────────────────────────────────────────────────────────────
describe('StatCardStrip — themed, even though nothing renders it today', () => {
  it('RD5: value and label inks and the card surface come from the palette under Light; the active fill is a palette surface', async () => {
    const mod = await import('@/src/components/StatCardStrip');
    const Strip = mod.default as (p: unknown) => unknown;
    const h = new HookHost(() => Strip({ items: [{ key: 'bids', label: 'Bids', value: 3 }, { key: 'won', label: 'Won', value: 1 }], activeKey: 'bids' }), new Map());
    h.mount(); h.flush();
    const value = findElement(h.output, (el) => el.type === 'Text' && el.props.children === 3);
    const label = findElement(h.output, (el) => el.type === 'Text' && el.props.children === 'Won');
    const card = findElement(h.output, (el) => el.type === 'Pressable' && styleValue(el as Element, 'minWidth') !== undefined);
    expect(styleValue(value, 'color')).toBe(light.text.primary);
    expect(styleValue(label, 'color')).toBe(light.text.muted);
    const cardFill = styleValue(card, 'backgroundColor')!;
    expect([light.surface.surface, light.surface.elevated]).toContain(cardFill);
    expect(contrast(light.text.muted, over(cardFill, light.surface.canvas))).toBeGreaterThanOrEqual(4.5);
  });

  it('RD6: no legacy palette import and no white literal', async () => {
    const src = await stripped('src/components/StatCardStrip.tsx');
    expect(src).toContain('useTheme()');
    expect(src).not.toMatch(/\bcolors\./);
    expect(src).not.toMatch(/rgba\(255,255,255/);
  });
});

// ── The sheet grabber (B's A-3) ─────────────────────────────────────────────────────────────────
describe('Sheet — the grabber identifies the sheet as draggable in both appearances', () => {
  it('RD7: the handle is border.control (3:1 graded) and clears 3:1 on the sheet surfaces in BOTH appearances', async () => {
    const src = await stripped('src/components/ui/Sheet.tsx');
    expect(src).toMatch(/handle: \{[^}]*backgroundColor: p\.border\.control,/);
    expect(src).not.toMatch(/rgba\(255,255,255/);
    for (const [scheme, p] of palettes) {
      for (const bg of [p.surface.surface, p.surface.elevated]) {
        expect(contrast(p.border.control, bg), `${scheme} grabber on ${bg}`).toBeGreaterThanOrEqual(3);
      }
    }
  });
});

// ── Where a key-for-key rename is the WRONG answer ──────────────────────────────────────────────
/**
 * Three surfaces the migration's own metric cannot judge, found while converting the tab group.
 * Each one renamed cleanly and was still wrong in Light, because the token it named was never the
 * token it meant. Counting static accesses would have called all three done (owner 2026-09-24:
 * "Zero static-token counts alone do not prove correct rendering").
 */
describe('over-artwork and on-fill inks — the cases a pure rename gets wrong', () => {
  it('RD8: the over-artwork vocabulary is one set of inks for BOTH appearances, and HomeFeature draws from it alone', async () => {
    // Text inside EventMedia sits on the photograph and its scrim, not on the canvas. Light's
    // near-black title (#0B0C0E) over a dark flyer is the defect; onArt is the group that exists
    // for this, deliberately identical in both appearances.
    expect(light.onArt).toEqual(dark.onArt);
    expect(dark.onArt.urgent).toBe('#FFB020');   // the Midnight amber, kept over artwork
    const src = await stripped('src/components/discovery/HomeFeature.tsx');
    const styles = src.slice(src.indexOf('function makeStyles'));
    expect(styles).toMatch(/color: p\.onArt\.primary/);
    expect(styles).toMatch(/color: p\.onArt\.urgent/);
    // Nothing in the overlay may take a canvas-side ink.
    expect(styles).not.toMatch(/color: p\.text\./);
    expect(styles).not.toMatch(/color: p\.status\./);

    // The listing hero's identity lines are the same case: B's measured 15.91 / 5.94 for that band
    // are white-on-artwork figures, which only hold if the ink is artwork-side.
    const hero = await stripped('src/components/listing/ListingHero.tsx');
    const heroStyles = hero.slice(hero.indexOf('function makeStyles'));
    expect(heroStyles).toMatch(/when: \{ color: p\.onArt\.secondary/);
    expect(heroStyles).toMatch(/title: \{ color: p\.onArt\.primary/);
  });

  it('RD9: the ink on a saturated status fill contrasts with the FILL, not with the canvas — in both appearances', async () => {
    // The sample-data caveat is black on amber in Midnight, which is right, and was black on
    // #8A5400 in Daylight, which is 3.35:1. The contrasting ink is the canvas colour.
    const src = await stripped('app/(tabs)/tickets.tsx');
    expect(src).toMatch(/sampleLabelText: \{ color: p\.surface\.canvas/);
    for (const [scheme, p] of palettes) {
      expect(contrast(p.surface.canvas, p.status.warning), `${scheme} caveat ink on fill`)
        .toBeGreaterThanOrEqual(4.5);
    }
  });

  it('RD10: the brand mark is tinted, so a white monogram is not invisible on a white canvas', async () => {
    const src = await stripped('src/components/discovery/HomeHeader.tsx');
    expect(src).toMatch(/tintColor: p\.text\.primary/);
    for (const [scheme, p] of palettes) {
      expect(contrast(p.text.primary, p.surface.canvas), `${scheme} mark on canvas`)
        .toBeGreaterThanOrEqual(4.5);
    }
  });
});
