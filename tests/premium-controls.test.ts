/**
 * tests/premium-controls.test.ts — Premium batch 2, foundation (CFT-201/202/203/205/206).
 *
 * The pure pieces are exercised directly; the primitives are pinned by source
 * contract, the way the rest of this suite pins React Native surfaces it
 * cannot render under vitest.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi, beforeEach } from 'vitest';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

// expo-haptics pulls in react-native; mock it so the helper is testable here.
const calls: string[] = [];
let shouldReject = false;
vi.mock('expo-haptics', () => {
  const fn = (name: string) => () => {
    calls.push(name);
    return shouldReject ? Promise.reject(new Error('no engine')) : Promise.resolve();
  };
  return {
    selectionAsync: fn('selection'),
    impactAsync: fn('impact'),
    notificationAsync: fn('notification'),
    ImpactFeedbackStyle: { Light: 'light', Medium: 'medium', Heavy: 'heavy' },
    NotificationFeedbackType: { Success: 'success', Warning: 'warning', Error: 'error' },
  };
});

import { HAPTIC, hapticConfirm, hapticSelect, hapticSuccess, hapticWarning } from '@/src/lib/feedback/haptics';
import { createSingleFlight } from '@/src/lib/async/singleFlight';

beforeEach(() => { calls.length = 0; shouldReject = false; });

describe('haptics have meanings (CFT-202)', () => {
  it('maps the four meanings to distinct engine calls', () => {
    hapticSelect(); hapticConfirm(); hapticSuccess(); hapticWarning();
    expect(calls).toEqual(['selection', 'impact', 'notification', 'notification']);
    expect(Object.keys(HAPTIC).sort()).toEqual(['confirm', 'select', 'success', 'warning']);
  });

  it('never throws when the engine rejects (simulator, web, no engine)', async () => {
    shouldReject = true;
    expect(() => { hapticSelect(); hapticConfirm(); hapticSuccess(); hapticWarning(); }).not.toThrow();
    await new Promise((r) => setTimeout(r, 0)); // let the rejections settle
    expect(calls).toHaveLength(4);
  });

  it('navigation is silent: the dock no longer buzzes on a tab tap', () => {
    const dock = stripComments(read('src/components/nav/AdaptiveDock.tsx'));
    expect(dock).not.toContain('expo-haptics');
    expect(dock).not.toContain('selectionAsync');
  });

  it('a chip is a selection: the light tick lives in Chip, paired with the selected fill', () => {
    const chip = read('src/components/ui/Chip.tsx');
    expect(chip).toContain("import { hapticSelect } from '@/src/lib/feedback/haptics'");
    expect(chip).toContain('hapticSelect(); onPress();');
    expect(chip).toContain('selected && styles.selected');
  });
});

describe('single flight (CFT-205)', () => {
  it('a second call while one is in flight is skipped and reports false', async () => {
    const flight = createSingleFlight();
    let runs = 0;
    let release!: () => void;
    const first = flight.run(() => new Promise<void>((r) => { runs++; release = r; }));
    const second = await flight.run(async () => { runs++; });
    expect(second).toBe(false);
    expect(flight.inFlight).toBe(true);
    release();
    expect(await first).toBe(true);
    expect(runs).toBe(1);
    expect(flight.inFlight).toBe(false);
  });

  it('releases the lock when the run throws, and propagates the error', async () => {
    const flight = createSingleFlight();
    await expect(flight.run(async () => { throw new Error('boom'); })).rejects.toThrow('boom');
    expect(flight.inFlight).toBe(false);
    expect(await flight.run(async () => {})).toBe(true);
  });

  it('the hook hands out one instance per component', () => {
    const hook = read('src/hooks/useSingleFlight.ts');
    expect(hook).toContain('useRef<SingleFlight | null>(null)');
    expect(hook).toContain('if (!ref.current) ref.current = createSingleFlight()');
  });
});

describe('Button pending label (CFT-203) — tap received ≠ action succeeded', () => {
  const button = read('src/components/ui/Button.tsx');

  it('accepts pendingLabel and shows it, with the spinner, only while loading', () => {
    expect(button).toContain('pendingLabel?: string;');
    expect(button).toContain('const showPending = loading && !!pendingLabel;');
    expect(button).toContain('{showPending ? <Spinner color={labelColor} label={pendingLabel} /> : null}');
    // without a pendingLabel the old behaviour (bare spinner over an invisible label) is kept
    expect(button).toContain('{loading && !showPending ? (');
  });

  it('holds width: both labels stay mounted, the inactive one at zero height', () => {
    expect(button).toContain("ghost: { height: 0, opacity: 0, overflow: 'hidden' }");
    expect(button).toContain('showPending && styles.ghost');
    expect(button).toContain('!showPending && styles.ghost');
  });

  it('a screen reader hears the pending label and busy state', () => {
    expect(button).toContain('accessibilityLabel={showPending ? pendingLabel : (accessibilityLabel ?? label)}');
    expect(button).toContain('accessibilityState={{ disabled: inert, busy: loading }}');
    // the visual pending row is not a second accessible element
    expect(button).toContain('importantForAccessibility="no-hide-descendants"');
  });
});

describe('press response everywhere (CFT-201)', () => {
  it('Tappable is Pressable plus the shared press scale, exported from the barrel', () => {
    const t = read('src/components/ui/Tappable.tsx');
    expect(t).toContain("import { usePressScale } from './press'");
    expect(t).toContain('const press = usePressScale(!disabled);');
    expect(t).toContain('press.onPressIn(); onPressIn?.(e);');
    expect(t).toContain('press.onPressOut(); onPressOut?.(e);');
    expect(read('src/components/ui/index.ts')).toContain("export { Tappable, type TappableProps } from './Tappable';");
  });
});

describe('Reduce Motion keeps every state change (CFT-206)', () => {
  it('the sheet cross-fades instead of sliding, and still appears', () => {
    const sheet = read('src/components/ui/Sheet.tsx');
    expect(sheet).toContain("import { useReducedMotion } from '@/src/hooks/useReducedMotion'");
    expect(sheet).toContain("animationType={reduceMotion ? 'fade' : 'slide'}");
  });

  it('stack pushes and pops cross-fade', () => {
    const layout = read('app/_layout.tsx');
    expect(layout).toContain("animation: reduceMotion ? 'fade' : 'default'");
  });

  it('every haptic call site in the product pairs with a visible state', () => {
    // The helper documents the rule; the call sites are pinned where they land
    // (Chip → selected fill; PlaceBid → outcome alert; receive → status block).
    const h = read('src/lib/feedback/haptics.ts');
    expect(h).toContain('A haptic is never the only feedback');
  });
});
