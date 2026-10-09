/**
 * tests/v3-profile-trust-a3xl.test.ts — the trust panel survives the largest text size.
 *
 * Two defects C found while capturing the `null%` fix and B confirmed in batch 8:
 *
 *   P-1  the success rate renders as three stacked lines — "10", "0", "%" — because `heroValue`
 *        carries no line bound and no shrink-to-fit, so at the largest accessibility size a
 *        number breaks mid-digit-run. B measured ink to x = 392.7 pt on a 393 pt screen.
 *   P-2  every trust row keeps its fixed label-left / value-right form, so the VALUE is pushed
 *        off the right edge ("Member since" reads "F… 2…"). B measured 8,089 px in the gutter.
 *
 * Both are the class the shared rule already fixes elsewhere, so they take the same treatment
 * rather than a fifth invention. The screen is mounted for real, through the fixture door the
 * dev harness uses, because the last time this project pinned a layout rule by source text
 * alone the rule was never reached.
 *
 * PT5 is the generalisation B asked for: one test that names every surface carrying a
 * two-column label/value or identity row and fails when a new one does not consult the rule.
 * BidActivity was missed by the first sweep and this screen by the second; this is the guard
 * that would have caught both.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';

import { expandTree, HookHost, type Element } from './helpers/nav-stack-harness';

const rn = vi.hoisted(() => ({ fontScale: 1 }));
vi.mock('react-native', () => ({
  useWindowDimensions: () => ({ width: 393, height: 852, scale: 3, fontScale: rn.fontScale }),
  Text: 'Text', View: 'View', Pressable: 'Pressable', ScrollView: 'ScrollView',
  Alert: { alert: () => {} },
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1 },
}));
vi.mock('expo-image', () => ({ Image: 'Image' }));
vi.mock('expo-router', () => ({ router: { push: () => {} }, useLocalSearchParams: () => ({ id: 'fixture-seller' }) }));
// Never reached under a fixture — and if it ever is, the test says so rather than the screen
// quietly talking to a client in a unit run.
vi.mock('@/src/lib/supabase', () => ({
  supabase: new Proxy({}, { get() { throw new Error('the fixture path must not touch supabase'); } }),
}));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'viewer-1' } }) }));
vi.mock('@/src/lib/avatarImage', () => ({ getAvatarUrl: () => null }));
vi.mock('@/src/lib/money', () => ({ allInFromDollarsV3: (n: number) => `$${n.toFixed(2)}` }));
vi.mock('@/src/components/media/EventMedia', () => ({ EventMedia: 'EventMedia' }));
vi.mock('@/src/components/ui', () => ({
  Badge: 'Badge', Button: 'Button', EmptyState: 'EmptyState', Spinner: 'Spinner',
}));
vi.mock('@/src/components/account/AccountSection', () => ({ AccountSection: 'AccountSection' }));
vi.mock('@/src/components/account/SettingsHeader', () => ({ SettingsHeader: 'SettingsHeader' }));
vi.mock('@/src/theme/typography', () => ({
  textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6,
}));
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});

import type { ProfileTrustStats } from '@/src/types';

/** A real `get_profile_trust_stats` shape: 14 sales, every terminal transfer successful. */
const TRUST: ProfileTrustStats = {
  completed_sales: 14,
  completed_purchases: 3,
  active_listings: 2,
  disputes_opened: 1,
  disputes_lost: 0,
  seller_terminal_total: 15,
  seller_terminal_successful: 15,
  member_since: '2026-02-11T00:00:00Z',
};

const PROFILE = {
  id: 'fixture-seller', display_name: 'Lantern Room Regulars', avatar_url: null, avatar_path: null,
  bio: 'Two or three nights a month.', created_at: '2026-02-11T00:00:00Z',
  is_verified_seller: true, stripe_onboarding_complete: true,
};

async function mountProfile(fontScale: number, trust: ProfileTrustStats | null = TRUST) {
  rn.fontScale = fontScale;
  const mod = await import('@/app/profile/[id]');
  const Screen = mod.default as unknown as (p: unknown) => unknown;
  // One stable fixture object: the screen's loader is a useCallback keyed on it, so a literal
  // rebuilt per render would re-run the read forever and never settle.
  const fixture = { profile: PROFILE, trust, listings: [] };
  const host = new HookHost(() => Screen({ fixture }), new Map());
  host.mount();
  host.flush();
  await Promise.resolve();
  host.flush();
  // TrustRow is a component, so the rows only exist once nested components are rendered too.
  return expandTree(host.output);
}

/** Every element in the rendered tree, parents before children. */
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

type Tree = unknown;
const textWith = (tree: Tree, value: string) =>
  nodes(tree).find((el) => el.type === 'Text' && el.props.children === value);

/** The row element that directly contains a Text whose children is `label`. */
function rowFor(tree: Tree, label: string): Element | undefined {
  return nodes(tree).find((el) => {
    const kids = (el.props as { children?: unknown }).children;
    const list = Array.isArray(kids) ? kids : [kids];
    return el.type === 'View' && list.some((k) => {
      const c = k as Element | null;
      return !!c && typeof c === 'object' && c.type === 'Text' && (c.props as { children?: unknown }).children === label;
    });
  });
}

/** Flatten a style prop (object, or array of objects and falsy entries) into one object. */
function flat(style: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const add = (s: unknown): void => {
    if (!s) return;
    if (Array.isArray(s)) { s.forEach(add); return; }
    Object.assign(out, s as Record<string, unknown>);
  };
  add(style);
  return out;
}

const A3XL = 3.1;  // at or above the shared stacking threshold
beforeEach(() => { rn.fontScale = 1; vi.resetModules(); });

describe('the public profile trust panel at the largest text size', () => {
  it('PT1: at the default size the rate keeps the display cap and the rows stay two-column', async () => {
    const host = await mountProfile(1);
    const rate = textWith(host, '100%');
    expect(rate, 'the rate should render').toBeTruthy();
    expect(rate!.props.maxFontSizeMultiplier).toBe(1.3);
    expect(rate!.props.adjustsFontSizeToFit).toBeFalsy();
    expect(flat(rowFor(host, 'Member since')!.props.style).flexDirection).toBe('row');
  });

  it('PT2: at A3XL the rate is one line that shrinks to fit — never a number broken across lines', async () => {
    const host = await mountProfile(A3XL);
    const rate = textWith(host, '100%');
    expect(rate, 'the rate should render').toBeTruthy();
    expect(rate!.props.numberOfLines).toBe(1);
    expect(rate!.props.adjustsFontSizeToFit).toBe(true);
    expect(rate!.props.minimumFontScale).toBeGreaterThan(0);
    // The cap is what pinned it small at the top of the range; it must be gone, not re-applied.
    expect(rate!.props.maxFontSizeMultiplier).toBeUndefined();
  });

  it('PT3: at A3XL every trust row stacks, so no value is pushed into the gutter', async () => {
    const host = await mountProfile(A3XL);
    for (const label of ['Completed sales', 'Completed purchases', 'Active listings',
                         'Disputes opened', 'Disputes lost', 'Member since']) {
      const row = rowFor(host, label);
      expect(row, `${label} should render`).toBeTruthy();
      const st = flat(row!.props.style);
      expect(st.flexDirection, `${label} must not stay side-by-side`).not.toBe('row');
      expect(st.alignItems).toBe('flex-start');
    }
  });

  it('PT4: stacking changes the layout and nothing else — every value is still whole and unclamped', async () => {
    const host = await mountProfile(A3XL);
    for (const value of ['14', '3', '2', '1', '0']) {
      const node = textWith(host, value);
      expect(node, `the value ${value} should render`).toBeTruthy();
      expect(node!.props.numberOfLines, `the value ${value} must not be clamped`).toBeUndefined();
    }
    // The dash is the no-rate reading and must survive the same treatment.
    const noHistory = await mountProfile(A3XL, null);
    expect(textWith(noHistory, '—')).toBeTruthy();
  });

  it('PT6: at A3XL the badge blurb may use the lines it needs; at the default size it still clamps', async () => {
    /*
     * P-3. The blurb is clamped at two lines, and a real row the RPC can return — "14 sales ·
     * 98% transfer success" — does not fit two lines at A3XL, so the explanation beside the
     * badge is cut. B withdrew the stronger framing (that only a dash survives, which needed the
     * impossible no-rate shape) and classified what remains as a real but minor defect.
     */
    const def = await mountProfile(1);
    const defBlurb = textWith(def, '14 sales \u00b7 100% transfer success');
    expect(defBlurb, 'the blurb should render').toBeTruthy();
    expect(defBlurb!.props.numberOfLines, 'the default layout is unchanged').toBe(2);

    const big = await mountProfile(A3XL);
    const bigBlurb = textWith(big, '14 sales \u00b7 100% transfer success');
    expect(bigBlurb, 'the blurb should render').toBeTruthy();
    expect(bigBlurb!.props.numberOfLines, 'at A3XL the blurb must not be cut').toBeUndefined();
  });

  it('PT5: every two-column label/value surface consults the shared stacking rule', async () => {
    /*
     * The recurring failure is not a bad rule, it is a surface the sweep did not reach:
     * BidActivity was missed once and this screen twice. A new one belongs in this list.
     */
    const surfaces = [
      'src/components/discovery/HomeFeature.tsx',
      'src/components/discovery/FeedRow.tsx',
      'src/components/listing/TransactionPanel.tsx',
      'src/components/listing/BidActivity.tsx',
      'src/screens/ListingDetailScreen.tsx',
      'app/profile/[id].tsx',
    ];
    for (const rel of surfaces) {
      const src = readFileSync(rel, 'utf8');
      expect(src, `${rel} renders a label/value row and must consult identityStacks`)
        .toContain('identityStacks');
    }
  });
});
