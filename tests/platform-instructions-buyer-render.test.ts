/**
 * Owner's decision 1: "omit empty contact fields" — pinned on the REAL instructions component.
 *
 * Every receive-screen test mocks `PlatformInstructions`, and O3 pins only the DATA it renders. D's review showed the
 * gap: a component line such as `Send to: ${buyerEmail}` would print "Send to: null" to a buyer with no contact on
 * file and pass every other suite. This renders the component itself, for every platform, as the sent-without-
 * delivery buyer sees it (role 'buyer', no email, no phone).
 *
 * The first assertion is a WITNESS, not decoration: a component that painted nothing would satisfy every absence
 * check below. (X6's vacuous title check, found in this same review cycle, is what an absence check without a
 * witness looks like.)
 */
import { describe, expect, it, vi } from 'vitest';

import PlatformInstructions from '@/src/components/PlatformInstructions';
import { PLATFORM_INSTRUCTIONS } from '@/src/lib/platformInstructions';
import type { TicketPlatform } from '@/src/types';
import { HookHost } from './helpers/nav-stack-harness';
import { screenText } from './helpers/screen-view';

// The migrated screens read the resolved appearance. These suites assert behaviour, not colour, so
// the boundary is mocked to Midnight — whose values ARE the v2 tokens, so nothing they pin moves.
vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: 'dark', palette: dark }),
    useAppearancePreference: () => ({ preference: 'system', setPreference: () => {} }),
  };
});
vi.mock('react-native', () => ({
  Pressable: 'Pressable', Text: 'Text', View: 'View', StyleSheet: { create: <T,>(s: T) => s },
}));

describe('Decision 1 — the real instructions component never prints an empty contact field', () => {
  it('I1: every platform, buyer role, no contact on file — renders its steps and no placeholder, null or fallback', () => {
    for (const platform of Object.keys(PLATFORM_INSTRUCTIONS) as TicketPlatform[]) {
      const host = new HookHost(
        () => PlatformInstructions({ platform, role: 'buyer', buyerEmail: null, buyerPhone: null }),
        new Map(),
      );
      host.mount();
      host.flush();
      const text = screenText(host.output);

      expect(text.length, `${platform} rendered something`).toBeGreaterThan(0);                  // witness
      expect(text, `${platform} shows its first step`).toContain(PLATFORM_INSTRUCTIONS[platform].buyer.steps[0]);
      expect(text, platform).not.toMatch(/\{buyer_|not yet provided|\bnull\b|\bundefined\b/);
    }
  });
});
