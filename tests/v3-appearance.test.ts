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
    for (const group of ['surface', 'text', 'brand', 'border', 'status'] as const) {
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
    const host = new HookHost(() => mod.AppearanceProvider({ children: Probe(), store: fakeStore() }), new Map());
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
