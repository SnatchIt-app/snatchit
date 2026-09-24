/**
 * V3 appearance (owner 2026-09-23): full light and dark support.
 *
 *   default System (follow the phone) · Settings › Appearance with System / Light / Dark ·
 *   an explicit choice persists across restarts · while System is selected the app follows
 *   phone changes live · Light or Dark overrides the phone until System is chosen again ·
 *   shared semantic tokens, never per-screen colours · artwork overlays readable in both.
 *
 * Midnight is the dark appearance; light is derived from the same hierarchy (B owns the final
 * values — the light palette here is PROVISIONAL and marked so). Contrast is COMPUTED below, not
 * estimated. Behaviour is tested through the real provider; screens are source-pinned.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

const rn = vi.hoisted(() => ({
  scheme: 'light' as 'light' | 'dark' | null,
  setColorScheme: [] as (string | null)[],
}));

vi.mock('@react-native-async-storage/async-storage', () => ({ default: { getItem: async () => null, setItem: async () => {} } }));
vi.mock('react-native', () => ({
  Appearance: { setColorScheme: (s: string | null) => { rn.setColorScheme.push(s); } },
  useColorScheme: () => rn.scheme,
  Text: 'Text', View: 'View', Pressable: 'Pressable', ScrollView: 'ScrollView',
  StyleSheet: { create: <T,>(s: T) => s },
}));

import * as v2 from '@/src/theme/v2';
import { dark, light, ON_ART, paletteFor } from '@/src/theme/palette';
import {
  APPEARANCE_KEY,
  getAppearancePreference,
  loadAppearancePreference,
  resolveScheme,
  saveAppearancePreference,
  setAppearancePreference,
  subscribeAppearance,
  type KeyValueStore,
} from '@/src/lib/appearance/appearanceStore';
import { HookHost } from './helpers/nav-stack-harness';

function fakeStore(initial: Record<string, string> = {}): KeyValueStore & { data: Record<string, string> } {
  const data = { ...initial };
  return {
    data,
    getItem: async (k) => data[k] ?? null,
    setItem: async (k, v) => { data[k] = v; },
  };
}

// WCAG relative luminance + contrast, with rgba composited over an opaque backdrop.
function parse(c: string): [number, number, number, number] {
  const hex = c.match(/^#([0-9a-f]{6})$/i);
  if (hex) { const n = parseInt(hex[1], 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1]; }
  const m = c.match(/rgba?\(([^)]+)\)/);
  if (!m) throw new Error(`unparseable colour ${c}`);
  const [r, g, b, a = '1'] = m[1].split(',').map((s) => s.trim());
  return [Number(r), Number(g), Number(b), Number(a)];
}
function over(fg: string, bg: string): [number, number, number] {
  const [r, g, b, a] = parse(fg); const [br, bgc, bb] = parse(bg);
  return [r * a + br * (1 - a), g * a + bgc * (1 - a), b * a + bb * (1 - a)];
}
function lum([r, g, b]: [number, number, number]): number {
  const f = (v: number) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
function contrast(fg: string, bg: string): number {
  const l1 = lum(over(fg, bg)); const l2 = lum(over(bg, bg));
  const [a, b] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (a + 0.05) / (b + 0.05);
}

beforeEach(() => {
  rn.scheme = 'light';
  rn.setColorScheme.length = 0;
  setAppearancePreference('system');
});

describe('appearanceStore — resolution, persistence, subscription', () => {
  it('AP1: System follows the phone; an unknown phone scheme falls back to the approved dark appearance', () => {
    expect(resolveScheme('system', 'light')).toBe('light');
    expect(resolveScheme('system', 'dark')).toBe('dark');
    expect(resolveScheme('system', null)).toBe('dark');
    expect(resolveScheme('light', 'dark')).toBe('light');
    expect(resolveScheme('dark', 'light')).toBe('dark');
  });

  it('AP2: an explicit choice round-trips through storage; garbage or absence reads as System', async () => {
    const store = fakeStore();
    await saveAppearancePreference('light', store);
    expect(store.data[APPEARANCE_KEY]).toBe('light');
    expect(await loadAppearancePreference(store)).toBe('light');
    expect(await loadAppearancePreference(fakeStore({ [APPEARANCE_KEY]: 'sepia' }))).toBe('system');
    expect(await loadAppearancePreference(fakeStore())).toBe('system');
    const broken: KeyValueStore = { getItem: async () => { throw new Error('io'); }, setItem: async () => {} };
    expect(await loadAppearancePreference(broken)).toBe('system');
  });

  it('AP3: the in-memory preference notifies subscribers', () => {
    const seen: string[] = [];
    const off = subscribeAppearance(() => seen.push(getAppearancePreference()));
    setAppearancePreference('dark');
    setAppearancePreference('system');
    off();
    setAppearancePreference('light');
    expect(seen).toEqual(['dark', 'system']);
    expect(getAppearancePreference()).toBe('light');
  });
});

describe('palette — one semantic shape, two appearances', () => {
  it('AP4: dark IS Midnight (the v2 tokens); light has the same keys; artwork inks are fixed in both', () => {
    expect(dark.surface).toStrictEqual(v2.surface);
    expect(dark.text).toStrictEqual(v2.text);
    expect(dark.brand).toStrictEqual(v2.brand);
    expect(dark.border).toStrictEqual(v2.border);
    expect(dark.status).toStrictEqual(v2.status);
    expect(dark.chrome).toStrictEqual(v2.chrome);   // the floating dock's material (owner 2026-09-24, B's A-1/A-2)
    for (const group of ['surface', 'text', 'brand', 'border', 'status', 'chrome'] as const) {
      expect(Object.keys(light[group]).sort()).toEqual(Object.keys(dark[group]).sort());
      for (const v of Object.values(light[group])) expect(typeof v).toBe('string');
    }
    expect(light.surface.canvas).not.toBe(dark.surface.canvas);
    expect(paletteFor('dark')).toBe(dark);
    expect(paletteFor('light')).toBe(light);
    // Text over artwork sits on the image + scrim, not on the canvas: the same inks in both.
    expect(ON_ART.primary).toBe('#FFFFFF');
    expect(dark.onArt).toStrictEqual(ON_ART);
    expect(light.onArt).toStrictEqual(ON_ART);
  });

  it('AP5: computed contrast — body inks clear 4.5:1 on their own canvas and surface in BOTH appearances', () => {
    for (const p of [dark, light]) {
      for (const bg of [p.surface.canvas, p.surface.surface, p.surface.elevated]) {
        expect(contrast(p.text.primary, bg)).toBeGreaterThanOrEqual(4.5);
        expect(contrast(p.text.secondary, bg)).toBeGreaterThanOrEqual(4.5);
        expect(contrast(p.text.muted, bg)).toBeGreaterThanOrEqual(4.5);
      }
      // Black on brand red is the signature; it must stay legible in both.
      expect(contrast(p.text.inverse, p.brand.red)).toBeGreaterThanOrEqual(4.5);
      // F-30: the PRESSED primary keeps the black label ≥ 4.5:1 — measured on the token itself,
      // and the press helper adds no opacity, so the rendered fill IS the token in both appearances.
      expect(contrast(p.text.inverse, p.brand.redPressed)).toBeGreaterThanOrEqual(4.5);
      expect(p.brand.redPressed).not.toBe(p.brand.red);   // visibly distinct
    }
  });
});

describe('the provider — live System following and explicit overrides', () => {
  async function mountProbe() {
    const mod = await import('@/src/theme/appearance');
    let latest: { scheme: string; pref: string } | null = null;
    let setPref: ((p: 'system' | 'light' | 'dark') => void) | null = null;
    const Probe = () => {
      const { scheme } = mod.useTheme();
      const { preference, setPreference } = mod.useAppearancePreference();
      latest = { scheme, pref: preference };
      setPref = setPreference;
      return null;
    };
    // ONE store for the host's life, as the root passes one: a store built inside the render
    // closure re-runs the load effect on every re-render and writes the stored value back over a
    // newer in-memory choice — a fixture artefact that AP14 exposed, not app behaviour.
    const store = fakeStore();
    const host = new HookHost(() => mod.AppearanceProvider({ children: Probe(), store }), new Map());
    host.mount();
    for (let i = 0; i < 4; i++) await new Promise((r) => setImmediate(r));
    host.flush();
    return { host, read: () => latest as { scheme: string; pref: string } | null, setPref: () => setPref as NonNullable<typeof setPref> };
  }

  it('AP6: System follows the phone live; Light/Dark override it and tell the OS so native surfaces follow', async () => {
    const { host, read, setPref } = await mountProbe();
    expect(read()?.scheme).toBe('light');
    rn.scheme = 'dark';
    host.flush();
    expect(read()?.scheme).toBe('dark');                   // live, no restart
    setPref()('light');
    host.flush();
    expect(read()?.scheme).toBe('light');                  // overrides the phone
    expect(rn.setColorScheme.at(-1)).toBe('light');        // keyboard, alerts, nav follow
    setPref()('system');
    host.flush();
    expect(read()?.scheme).toBe('dark');                   // back to the phone
    expect(rn.setColorScheme.at(-1)).toBeNull();
    host.unmount();                                        // no live subscriber leaks into later tests
  });
});

describe('screens (source pins) — the root, Settings, and the first migrated screen', () => {
  const code = async (rel: string) => (await import('node:fs')).readFileSync(rel, 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

  it('AP7: the root no longer forces dark — provider mounted, navigation theme and status bar follow the scheme', async () => {
    const root = await code('app/_layout.tsx');
    expect(root).toContain('AppearanceProvider');
    expect(root).not.toContain('value={DarkTheme}');
    expect(root).not.toContain('<StatusBar style="light" />');
  });

  it('AP8: Settings offers Appearance with System / Light / Dark as radio options', async () => {
    const index = await code('app/settings/index.tsx');
    expect(index).toContain("label=\"Appearance\"");
    expect(index).toContain("nav('/settings/appearance')");
    const screen = await code('app/settings/appearance.tsx');
    for (const opt of ["'system'", "'light'", "'dark'"]) expect(screen).toContain(opt);
    expect(screen).toContain('accessibilityRole="radio"');
    expect(screen).toContain('accessibilityState={{ checked:');
  });

  it('AP10 (F-30): the primary button recolours to the measured pressed token while pressed; the press helper has no opacity', async () => {
    const btn = await code('src/components/ui/Button.tsx');
    expect(btn).toMatch(/variant === 'primary' && pressed && !inert \? \{ backgroundColor: palette\.brand\.redPressed \}/);
    const press = await code('src/components/ui/press.ts');
    expect(press).not.toMatch(/opacity/);
    expect(press).toContain('PRESSED_SCALE = 0.98');
  });

  it('AP9: the bid screen reads every colour from the theme — no static token colours remain', async () => {
    const bid = await code('src/screens/PlaceBidScreen.tsx');
    expect(bid).toContain('useTheme()');
    expect(bid).not.toMatch(/v2\.(surface|text|border|brand|status)\./);
  });
});

describe('reconciliation with B (owner 2026-09-24) — one pressed value, B\'s Daylight column, one control edge', () => {
  it('AP11: the pressed primary is ONE agreed value, #FF5353, in BOTH token mirrors — no second round', async () => {
    // B first closed F-30 at #FF4C4C while C shipped #FF5353; both pass (black label 6.39:1 vs 6.6:1,
    // fill vs white 3.29:1 vs 3.17:1). B's reconciliation record (design c1e23125) adopts #FF5353, so
    // that is the shared value. Pinned on both mirrors so the parity test is not the only thing
    // holding them together, and the label contrast is recomputed here rather than trusted.
    expect(v2.brand.redPressed).toBe('#FF5353');
    const mirror = await import('../packages/design-tokens/src/brand');
    expect(mirror.brand.redPressed).toBe('#FF5353');
    expect(light.brand.redPressed).toBe('#FF5353');
    expect(contrast('#000000', '#FF5353')).toBeGreaterThanOrEqual(4.5);
    expect(contrast('#FF5353', '#FFFFFF')).toBeGreaterThanOrEqual(3);   // identifiable on Daylight
  });

  it('AP12: Daylight IS B\'s token board (pkg8-appearance-tokens) — no provisional ink survives', () => {
    expect(light.surface.canvas).toBe('#FFFFFF');
    expect(light.surface.surface).toBe('#F4F4F6');     // B's surface.panel
    expect(light.text.primary).toBe('#0B0C0E');
    expect(light.text.secondary).toBe('#4A4D53');
    expect(light.text.muted).toBe('#686C73');           // solved on the plate, not mirrored
    expect(light.text.inverse).toBe('#000000');
    expect(light.brand.red).toBe('#FF1A1A');            // the brand red never needed changing
    expect(light.border.default).toBe('#DFE0E4');
    expect(light.status.error).toBe('#C41414');
    expect(light.status.warning).toBe('#8A5400');       // #FFB020 is 1.9:1 as text on white
    expect(light.status.success).toBe('#0B7A3C');       // #3DDC84 is 1.6:1 as text on white
    // Status colours are used as TEXT (badges, money states): they must clear 4.5:1 on the light surfaces.
    for (const bg of [light.surface.canvas, light.surface.surface]) {
      expect(contrast(light.status.error, bg)).toBeGreaterThanOrEqual(4.5);
      expect(contrast(light.status.warning, bg)).toBeGreaterThanOrEqual(4.5);
      expect(contrast(light.status.success, bg)).toBeGreaterThanOrEqual(4.5);
    }
  });

  it('AP13: border.control — the edge that identifies a control — exists in both mirrors and clears 3:1 on canvas and surface in both appearances', async () => {
    const mirror = await import('../packages/design-tokens/src/brand');
    expect(v2.border.control).toBe('#64656A');
    expect(mirror.border.control).toBe('#64656A');
    expect(light.border.control).toBe('#8A8B90');
    for (const p of [dark, light]) {
      for (const bg of [p.surface.canvas, p.surface.surface]) {
        expect(contrast(p.border.control, bg)).toBeGreaterThanOrEqual(3);
      }
    }
    // The primitives whose edge identifies them use it at rest: Input's underline, Chip's outline,
    // the secondary Button's outline. Focus/selected/error states keep their own colours.
    const code = async (rel: string) => (await import('node:fs')).readFileSync(rel, 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(await code('src/components/ui/Input.tsx')).toMatch(/:\s*palette\.border\.control;/);
    expect(await code('src/components/ui/Chip.tsx')).toMatch(/borderColor: p\.border\.control,/);
    expect(await code('src/components/ui/Button.tsx')).toMatch(/borderWidth: 1, borderColor: palette\.border\.control \}/);
  });
});

describe('status.info — the verification blue, graded for Daylight', () => {
  it('AP18: both mirrors keep Midnight\'s existing blue and Light gets one that clears 4.5:1 on canvas and surface', async () => {
    const mirror = await import('../packages/design-tokens/src/brand');
    // Midnight is unchanged by this addition: #60A5FA is the value the Verified Seller badge has
    // always drawn, promoted from a literal into the one place colours are allowed to live.
    expect(v2.status.info).toBe('#60A5FA');
    expect(mirror.status.info).toBe('#60A5FA');
    // Daylight cannot reuse it: #60A5FA on white is 2.28:1, which is not text.
    expect(contrast('#60A5FA', '#FFFFFF')).toBeLessThan(3);
    for (const p of [dark, light]) {
      for (const bg of [p.surface.canvas, p.surface.surface]) {
        expect(contrast(p.status.info, bg)).toBeGreaterThanOrEqual(4.5);
      }
    }
  });
});

describe('A-1 — neutral hairlines, approved (owner 2026-09-22, restated 2026-09-24)', () => {
  it('AP17: Midnight dividers are the approved neutral #28292D, the stronger rule is the graded control edge, no red-tinted hairline survives in either mirror; the canvas stays #000000', async () => {
    const mirror = await import('../packages/design-tokens/src/brand');
    for (const b of [v2.border, mirror.border]) {
      expect(b.default).toBe('#28292D');
      expect(b.strong).toBe('#64656A');
      for (const v of Object.values(b)) expect(v).not.toMatch(/255,\s*26,\s*26/);
    }
    for (const v of Object.values(light.border)) expect(v).not.toMatch(/255,\s*26,\s*26/);
    expect(v2.surface.canvas).toBe('#000000');
    expect(mirror.surface.canvas).toBe('#000000');
    // The brand's red stays on actions and the selected tint — not on passive rules.
    expect(v2.brand.redSoft).toMatch(/255,26,26/);
  });
});

describe('startup — no flash of the wrong appearance before the stored choice is read', () => {
  it('AP14: the provider withholds the tree until the persisted choice loads, then renders the CHOSEN scheme; a silent store is bounded', async () => {
    const mod = await import('@/src/theme/appearance');
    rn.scheme = 'dark';                                   // the phone is dark …
    let resolve!: (v: string | null) => void;
    const slow: KeyValueStore = {
      getItem: () => new Promise<string | null>((r) => { resolve = r; }),
      setItem: async () => {},
    };
    let seen: string | null = null;
    const Probe = () => { seen = mod.useTheme().scheme; return null; };
    const host = new HookHost(() => mod.AppearanceProvider({ children: Probe(), store: slow }), new Map());
    host.mount();
    await new Promise((r) => setImmediate(r));
    host.flush();
    expect(host.output).toBeNull();                       // nothing painted yet — no dark first frame
    resolve('light');                                     // … but the person chose Light
    for (let i = 0; i < 4; i++) await new Promise((r) => setImmediate(r));
    host.flush();
    expect(host.output).not.toBeNull();
    expect(seen).toBe('light');                           // first painted frame is the chosen one

    host.unmount();

    // A store that never answers must not wedge the app: after the bound it renders under System.
    // The bound is a real timer, so the wait is a real timer too — four immediates can complete in
    // under a millisecond and race a 0 ms bound (observed once as a flake under an unrelated mutant).
    const silent: KeyValueStore = { getItem: () => new Promise(() => {}), setItem: async () => {} };
    const host2 = new HookHost(() => mod.AppearanceProvider({ children: Probe(), store: silent, maxWaitMs: 1 }), new Map());
    host2.mount();
    host2.flush();
    expect(host2.output).toBeNull();                      // still withheld before the bound
    await new Promise((r) => setTimeout(r, 25));
    host2.flush();
    expect(host2.output).not.toBeNull();
    host2.unmount();
  });

  it('AP15: the root holds the splash until fonts AND the appearance choice are ready (source pin)', async () => {
    const root = (await import('node:fs')).readFileSync('app/_layout.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    expect(root).toContain('SplashScreen.preventAutoHideAsync()');
    // The hide lives in ThemedShell, which mounts only inside the provider's withheld tree, and
    // fires on fonts — so both gates are open when the splash goes.
    expect(root).toMatch(/function ThemedShell[\s\S]*?if \(fontsReady\) void SplashScreen\.hideAsync\(\)[\s\S]*?function RootLayout/);
    expect(root).toContain('<ThemedShell fontsReady={fontsReady}>');
  });
});
