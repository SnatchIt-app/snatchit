/**
 * tests/edit-listing-refusal.test.ts — Edit listing must never be left spinning.
 *
 * E's finding (2026-10-05): the spinner never stops on the "Not allowed" and "Cannot edit" paths.
 * Reproduced in source before fixing: `load()` returns from both branches without clearing
 * `loading`, so `if (loading || !listing)` keeps rendering the Spinner behind the alert.
 *
 * The cause is one step deeper than the two missing `setLoading(false)` calls, which is why this
 * suite covers four refusals rather than E's two. The render guard treats "no listing" as "still
 * loading", so the "Listing not found" branch — which DOES clear `loading` — spins just the same,
 * and a viewer whose session has resolved to signed-out spins before any read is attempted. All
 * four are the same defect on different inputs.
 *
 * INTENDED BEHAVIOUR, taken from the app rather than invented. ListingDetailScreen already rules
 * on a listing it cannot show: loading is a Spinner, a read failure is StateView, and a listing
 * that is not there is an EmptyState with a title, a sentence and an action that always works —
 * never an indefinite spinner. The signed-out copy is the app's existing one, from the four places
 * that already refuse an action to a signed-out viewer ('Sign in required'). No new dialog is
 * added: the refusal alerts already on these paths are unchanged, and the eligibility conditions
 * are pinned below so this cannot quietly widen who may edit.
 *
 * These tests run the REAL screen under the hook dispatcher and read what the seller would see
 * from the rendered tree. Not a device result.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { EDIT_REFUSAL_COPY, editRefusal } from '@/src/lib/listing/editAccess';
import { findElement, HookHost, REPO_ROOT } from './helpers/nav-stack-harness';

const h = vi.hoisted(() => ({
  alerts: [] as { title: string; message?: string; buttons: { text?: string; onPress?: () => void }[] }[],
  back: 0,
  reads: 0,
  user: { id: 'seller-1' } as null | { id: string },
  authLoading: false,
  reply: null as null | { data: unknown; error: null | { message: string } },
  pending: [] as ((r: { data: unknown; error: null | { message: string } }) => void)[],
}));

vi.mock('@/src/theme/appearance', async () => {
  const { dark } = await import('@/src/theme/palette');
  return { useTheme: () => ({ scheme: 'dark', palette: dark }) };
});
vi.mock('react-native', () => ({
  Alert: {
    alert: (title: string, message?: string, buttons?: { text?: string; onPress?: () => void }[]) => {
      h.alerts.push({ title, message, buttons: buttons ?? [] });
    },
  },
  Platform: { OS: 'ios' },
  StyleSheet: { create: <T,>(s: T) => s },
  KeyboardAvoidingView: 'KeyboardAvoidingView',
  ScrollView: 'ScrollView',
  Text: 'Text',
  TextInput: 'TextInput',
  View: 'View',
}));
vi.mock('expo-router', () => ({
  router: { back: () => { h.back += 1; } },
  useLocalSearchParams: () => ({ id: 'listing-1' }),
}));
vi.mock('@/src/lib/nav/navInsets', () => ({ useTopInset: () => 0 }));
vi.mock('@/src/hooks/useAuth', () => ({ useAuth: () => ({ user: h.user, loading: h.authLoading }) }));
vi.mock('@/src/hooks/useUnsavedChangesGuard', () => ({ useUnsavedChangesGuard: () => {} }));
vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    from: () => ({
      select: () => ({
        eq: () => ({
          single: () => {
            h.reads += 1;
            if (h.reply) return Promise.resolve(h.reply);
            return new Promise((resolve) => { h.pending.push(resolve); });
          },
        }),
      }),
      update: () => ({ eq: () => ({ eq: async () => ({ error: null }) }) }),
    }),
  },
}));
vi.mock('@/src/components/ui', () => ({
  Button: 'Button', Chip: 'Chip', EmptyState: 'EmptyState', IconButton: 'IconButton',
  Input: 'Input', Spinner: 'Spinner', StickyBar: 'StickyBar',
}));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}) }));

const OWNED = {
  id: 'listing-1', seller_id: 'seller-1', event_name: 'Weekend pool party', venue: 'LIV Miami',
  restrictions: null, ticket_platform: 'dice', bid_count: 0, auction_status: 'active',
};

const flush = async () => { for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r)); };

async function mountEdit(): Promise<HookHost> {
  const { default: EditListingScreen } = await import('@/app/listing/edit/[id]');
  const host = new HookHost(() => EditListingScreen(), new Map());
  host.mount();
  await flush();
  host.flush();
  return host;
}

const spinner = (host: HookHost) => findElement(host.output, (el) => el.type === 'Spinner');
const refusal = (host: HookHost) => findElement(host.output, (el) => el.type === 'EmptyState');
const eventName = (host: HookHost) =>
  findElement(host.output, (el) => el.type === 'Input' && el.props.label === 'Event name');

/** What the seller is looking at: exactly one of the three. */
function screen(host: HookHost): 'spinner' | 'refusal' | 'form' | 'nothing' {
  const seen = [spinner(host) && 'spinner', refusal(host) && 'refusal', eventName(host) && 'form']
    .filter(Boolean) as string[];
  if (seen.length > 1) throw new Error(`two states at once: ${seen.join(' + ')}`);
  return (seen[0] as 'spinner' | 'refusal' | 'form') ?? 'nothing';
}

beforeEach(() => {
  h.alerts.length = 0;
  h.pending.length = 0;
  h.back = 0;
  h.reads = 0;
  h.user = { id: 'seller-1' };
  h.authLoading = false;
  h.reply = null;
});

describe('EL1 · the states are distinguishable', () => {
  it('EL1a: the read has not answered yet — the Spinner is the right answer', async () => {
    const host = await mountEdit();
    expect(h.reads).toBe(1);
    expect(screen(host)).toBe('spinner');
  });

  it('EL1b: the seller owns an unbid, active listing — the form opens, nothing is alerted', async () => {
    h.reply = { data: OWNED, error: null };
    const host = await mountEdit();
    expect(screen(host)).toBe('form');
    expect(eventName(host)!.props.value).toBe('Weekend pool party');
    expect(h.alerts).toEqual([]);
  });

  it('EL1c: the session is still being checked — still the Spinner, not a refusal', async () => {
    h.user = null;
    h.authLoading = true;
    const host = await mountEdit();
    expect(h.reads).toBe(0);
    expect(screen(host)).toBe('spinner');
    expect(h.alerts).toEqual([]);
  });
});

describe('EL2 · a refusal stops the spinner and gives the seller a way out', () => {
  const cases = [
    { name: "EL2a: someone else's listing (E's 'Not allowed')", row: { ...OWNED, seller_id: 'other-seller' }, kind: 'not-owner' as const },
    { name: "EL2b: the listing already has bids (E's 'Cannot edit')", row: { ...OWNED, bid_count: 3 }, kind: 'has-bids' as const },
    { name: "EL2c: the auction is no longer active (E's 'Cannot edit')", row: { ...OWNED, auction_status: 'ended' }, kind: 'inactive' as const },
  ];

  for (const { name, row, kind } of cases) {
    it(name, async () => {
      h.reply = { data: row, error: null };
      const host = await mountEdit();

      // The alert that was already there is unchanged.
      expect(h.alerts).toHaveLength(1);
      expect(h.alerts[0]!.title).toBe(EDIT_REFUSAL_COPY[kind].title);
      expect(h.alerts[0]!.message).toBe(EDIT_REFUSAL_COPY[kind].body);

      // The defect: behind it the screen must not still be loading.
      expect(screen(host)).toBe('refusal');
      expect(refusal(host)!.props.title).toBe(EDIT_REFUSAL_COPY[kind].title);
      expect(refusal(host)!.props.body).toBe(EDIT_REFUSAL_COPY[kind].body);

      // And the way out does not depend on the alert: dismissing it with the hardware back
      // button never fires OK, which is how the seller got stranded on a spinner.
      const action = refusal(host)!.props.action as { label: string; onPress: () => void };
      expect(action.label.length).toBeGreaterThan(0);
      action.onPress();
      expect(h.back).toBe(1);
    });
  }

  it('EL2d: the listing is not there — the branch that DID clear loading spun too', async () => {
    h.reply = { data: null, error: { message: 'No rows returned' } };
    const host = await mountEdit();
    expect(h.alerts[0]!.title).toBe(EDIT_REFUSAL_COPY['not-found'].title);
    // The server's own sentence is kept, as before.
    expect(h.alerts[0]!.message).toBe('No rows returned');
    expect(screen(host)).toBe('refusal');
    expect(refusal(host)!.props.body).toBe('No rows returned');
  });

  it('EL2e: the session resolved to signed out — refused without a read, and without a new dialog', async () => {
    h.user = null;
    h.authLoading = false;
    const host = await mountEdit();
    expect(h.reads).toBe(0);
    expect(screen(host)).toBe('refusal');
    expect(refusal(host)!.props.title).toBe(EDIT_REFUSAL_COPY['signed-out'].title);
    expect(h.alerts).toEqual([]);
  });
});

describe('EL3 · who may edit is unchanged', () => {
  const viewer = 'seller-1';
  it('EL3a: the eligibility matrix refuses exactly what it refused before', () => {
    const row = (extra: Record<string, unknown> = {}) => ({ ...OWNED, ...extra });
    const kind = (r: Record<string, unknown>) => editRefusal({ listing: r, viewerId: viewer })?.kind ?? null;

    expect(kind(row())).toBeNull();                                       // owner · 0 bids · active
    expect(kind(row({ seller_id: 'other' }))).toBe('not-owner');
    expect(kind(row({ bid_count: 1 }))).toBe('has-bids');
    expect(kind(row({ auction_status: 'ended' }))).toBe('inactive');
    expect(kind(row({ auction_status: 'sold' }))).toBe('inactive');
    // Ownership is checked before the auction state, and bids before inactivity — the order the
    // screen used, so the seller reads the same sentence as before for a row that fails twice.
    expect(kind(row({ seller_id: 'other', bid_count: 4 }))).toBe('not-owner');
    expect(kind(row({ bid_count: 2, auction_status: 'ended' }))).toBe('has-bids');
  });

  it('EL3b: a missing row and a missing viewer are refusals of their own', () => {
    expect(editRefusal({ listing: null, viewerId: viewer })?.kind).toBe('not-found');
    expect(editRefusal({ listing: null, viewerId: viewer, readError: 'boom' })?.body).toBe('boom');
    expect(editRefusal({ listing: OWNED, viewerId: null })?.kind).toBe('signed-out');
  });
});

describe('EL4 · the screen cannot go back to inferring loading from the absence of a listing', () => {
  it('EL4a: the render guard is the phase, not `loading || !listing`', () => {
    const src = readFileSync(join(REPO_ROOT, 'app/listing/edit/[id].tsx'), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    expect(src).not.toMatch(/if \(loading \|\| !listing\)/);
    expect(src).toContain('editPhase');
    // One source for the copy: the screen must not carry its own second copy of these sentences.
    expect(src).not.toContain('You can only edit your own listings.');
    expect(src).not.toContain('This listing is no longer active.');
    expect(src).not.toContain('Listing not found');
  });
});
