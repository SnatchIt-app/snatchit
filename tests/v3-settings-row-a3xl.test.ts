/**
 * tests/v3-settings-row-a3xl.test.ts — S-1: the settings rows ARE the navigation.
 *
 * At the largest accessibility size every row label was cut to its first word and a half:
 * "Edit prof…", "Notificat…", "Phone v…", "Payout s…". Two of those are indistinguishable from
 * each other, and the label is the only thing telling you where the row goes — so this is a
 * navigation defect, not a cosmetic one. Found by capturing the W-4 header fix, confirmed by E.
 *
 * Above the shared threshold the label takes the lines it needs and breaks on words. Below it
 * nothing moves: one line, same clamp, same row. The chevron stays either way, because a row
 * that stops looking like navigation is a different defect in the same place.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { HookHost, type Element } from './helpers/nav-stack-harness';

const rn = vi.hoisted(() => ({ fontScale: 1 }));
vi.mock('react-native', () => ({
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: rn.fontScale }),
  Animated: { View: 'Animated.View' },
  Pressable: 'Pressable', Text: 'Text', View: 'View',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('@/src/theme/typography', () => ({
  textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6,
}));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('@/src/components/ui', () => ({
  usePressScale: () => ({ style: {}, onPressIn: () => {}, onPressOut: () => {} }),
}));

function nodes(root: unknown): Element[] {
  const out: Element[] = [];
  const walk = (n: unknown): void => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    out.push(el);
    walk((el.props as { children?: unknown }).children);
  };
  walk(root);
  return out;
}

async function mountRow(fontScale: number, props: Record<string, unknown> = {}) {
  rn.fontScale = fontScale;
  const mod = await import('@/src/components/account/SettingsRow');
  const Row = mod.SettingsRow as unknown as (p: unknown) => unknown;
  const host = new HookHost(() => Row({ label: 'Phone verification', onPress: () => {}, ...props }), new Map());
  host.mount();
  host.flush();
  return nodes(host.output);
}

const textWith = (els: Element[], value: string) =>
  els.find((el) => el.type === 'Text' && el.props.children === value);

beforeEach(() => { rn.fontScale = 1; vi.resetModules(); });

describe('S-1: a settings row label is navigation, so it must not be cut', () => {
  it('SR1: at the default size the label keeps its single clamped line', async () => {
    const els = await mountRow(1);
    const label = textWith(els, 'Phone verification');
    expect(label, 'the label should render').toBeTruthy();
    expect(label!.props.numberOfLines).toBe(1);
  });

  it('SR2: at A3XL the label may use the lines it needs', async () => {
    const els = await mountRow(3.1);
    const label = textWith(els, 'Phone verification');
    expect(label, 'the label should render').toBeTruthy();
    expect(label!.props.numberOfLines, 'a cut label is a row you cannot identify').toBeUndefined();
  });

  it('SR3: the chevron survives at both sizes — a row must still read as navigation', async () => {
    for (const scale of [1, 3.1]) {
      const els = await mountRow(scale);
      expect(textWith(els, '›'), `chevron missing at ${scale}`).toBeTruthy();
    }
  });

  it('SR4: the accessibility label is unchanged, and still carries any trailing value', async () => {
    for (const scale of [1, 3.1]) {
      const els = await mountRow(scale, { value: 'System' });
      const pressable = els.find((el) => el.type === 'Pressable');
      expect(pressable!.props.accessibilityLabel).toBe('Phone verification, System');
      expect(pressable!.props.accessibilityRole).toBe('button');
    }
  });
});
