/**
 * The past ticket card's recession, measured rather than assumed (N-3, 2026-09-24).
 *
 * A reviewer raised four opacity/border sites as possible Light-appearance defects. Judged in their
 * rendered context, three are not: the transfer screens' `status.warning` borders clear 3:1 and 4.5:1
 * in both appearances and never carry meaning the copy does not (6.27:1 on white, 11.48:1 on black),
 * and BidCard dims only its artwork, which is `decorative` and accompanied by a Badge that says
 * "Ended" in words.
 *
 * This one is real, and Daylight-only. `TicketEventGroup`'s past card carried `opacity: 0.92` on its
 * OUTER view, so it scaled the event date and the venue name along with the artwork. `text.muted` is
 * #686C73 in Daylight — the value the palette says was solved to clear 4.5:1 — and at 0.92 over the
 * white canvas it composites to #74787E, which is **4.44:1**. The palette test passes because it
 * grades the token; an ancestor multiplier is invisible to it.
 *
 * So this test does not pin a line: it renders the real card and walks the tree carrying the product
 * of every ancestor's opacity, so an ancestor opacity above text fails here wherever it is added.
 * The artwork keeps its dim, on the one element where dimming costs no contrast.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

const th = vi.hoisted(() => ({ scheme: 'light' as 'light' | 'dark' }));

vi.mock('@/src/theme/appearance', async () => {
  const { paletteFor } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: th.scheme, palette: paletteFor(th.scheme) }) };
});
vi.mock('react-native', () => ({
  Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('@/src/components/ui', () => ({ Badge: 'Badge' }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3 }));

import { dark, light, type Palette } from '@/src/theme/palette';
import { HookHost, type Element } from './helpers/nav-stack-harness';

// ── WCAG, on values composited over an opaque backdrop ──────────────────────────────────────────
function parse(c: string): [number, number, number, number] {
  const hex = c.match(/^#([0-9a-f]{6})$/i);
  if (hex) { const n = parseInt(hex[1], 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1]; }
  const m = c.match(/rgba?\(([^)]+)\)/);
  if (!m) throw new Error(`unparseable colour ${c}`);
  const [r, g, b, a = '1'] = m[1].split(',').map((s) => s.trim());
  return [Number(r), Number(g), Number(b), Number(a)];
}
function over(fg: string, bg: string, alpha = 1): string {
  const [r, g, b, a] = parse(fg); const [br, bgc, bb] = parse(bg);
  const eff = a * alpha;
  const c = [r * eff + br * (1 - eff), g * eff + bgc * (1 - eff), b * eff + bb * (1 - eff)].map((v) => Math.round(v));
  return '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');
}
function lum(hex: string): number {
  const [r, g, b] = parse(hex);
  const f = (v: number) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
function contrast(fg: string, bg: string, alpha = 1): number {
  const l1 = lum(over(fg, bg, alpha)); const l2 = lum(over(bg, bg));
  const [a, b] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (a + 0.05) / (b + 0.05);
}

const palettes: [string, Palette][] = [['light', light], ['dark', dark]];

const GROUP = {
  event_id: 'e1', event_title: 'Past Event', venue_name: 'The Venue',
  starts_at: '2026-01-02T20:00:00Z', artwork_ref: null, time_class: 'past' as const,
  rows: [{
    ticket_type_id: 't1', ticket_type_name: 'GA', quantity: 1,
    ownership_status: 'owned' as const, fulfillment_status: 'delivered' as const,
  }],
};

/** Every node, paired with the product of the opacities on it and on all its ancestors. */
function withEffectiveOpacity(node: unknown, acc = 1, out: { el: Element; opacity: number }[] = []) {
  if (Array.isArray(node)) { node.forEach((n) => withEffectiveOpacity(n, acc, out)); return out; }
  if (!node || typeof node !== 'object') return out;
  const el = node as Element;
  const flat: Record<string, unknown> = {};
  const walk = (s: unknown) => { if (Array.isArray(s)) s.forEach(walk); else if (s && typeof s === 'object') Object.assign(flat, s); };
  walk(el.props?.style);
  const here = typeof flat.opacity === 'number' ? acc * flat.opacity : acc;
  out.push({ el, opacity: here });
  withEffectiveOpacity(el.props?.children, here, out);
  return out;
}

beforeEach(() => { th.scheme = 'light'; vi.resetModules(); });

describe('the past ticket card recedes without dimming its own text', () => {
  it('TP1: the ink an ancestor opacity was scaling is BELOW its bar in Daylight — which is why this test exists', () => {
    // 0.92 over the canvas, computed the same way the renderer composites it.
    expect(contrast(light.text.muted, light.surface.canvas, 0.92)).toBeLessThan(4.5);
    expect(contrast(light.text.muted, light.surface.canvas)).toBeGreaterThanOrEqual(4.5);
  });

  it('TP2: no text in the past card is scaled by an ancestor opacity, in either appearance', async () => {
    for (const [scheme, p] of palettes) {
      th.scheme = scheme as 'light' | 'dark';
      vi.resetModules();
      const mod = await import('@/src/components/tickets/TicketEventGroup');
      const exported = mod.TicketEventGroup as unknown;
      // The component is memo()-wrapped; render the function it holds.
      const Fn = (typeof exported === 'function'
        ? exported
        : (exported as { type: (p: unknown) => unknown }).type) as (props: unknown) => unknown;
      const host = new HookHost(() => Fn({ group: GROUP, emphasis: 'past' }), new Map());
      host.mount(); host.flush();

      const nodes = withEffectiveOpacity(host.output);
      const texts = nodes.filter((n) => n.el.type === 'Text');
      expect(texts.length, `${scheme}: the past card should render text`).toBeGreaterThan(0);
      for (const t of texts) {
        expect(t.opacity, `${scheme}: text is scaled by an ancestor opacity`).toBe(1);
      }
      // The recession cue survives, on the artwork, where dimming costs no contrast.
      expect(nodes.some((n) => n.opacity < 1), `${scheme}: the artwork should still recede`).toBe(true);
      // And the ink that was being scaled clears the bar it was solved for.
      expect(contrast(p.text.muted, p.surface.canvas)).toBeGreaterThanOrEqual(4.5);
    }
  });
});
