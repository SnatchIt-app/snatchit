/*
 * RETARGETED (A's interim refund ruling, 2026-09-24). Every refund row is written the moment the
 * refund is CREATED, and today's columns cannot distinguish that from a completed one, so "Refunded
 * $X" and "Full refund" asserted a settlement the data does not establish. Until migration 150 gives
 * the lifecycle its own columns the word is "initiated", and the partial line drops "of $total",
 * which implied a settled shortfall. Details: REFUND_LIFECYCLE_TRACE_AND_FIX_20260924.md.
 */
/**
 * tests/v3-transfer-gallery-cases.test.ts — the four combinations the synthetic gallery was missing
 * (A, 2026-09-24), each proven through the REAL shared block and the REAL mapping functions.
 *
 * The cases:
 *   (a) buyer · expired · PARTIAL refund — amount < total with both figures on the row;
 *   (b) buyer · expired · refund RECORDED with no confirmable amount (refunded_at set, amount NULL);
 *   (c) buyer · reversed · FULL refund (amount === total);
 *   (d) seller · seller_sent · payout_review_status NULL and auto_release_at NULL — no date line,
 *       the rest of the block intact.
 *
 * WHAT THESE PROVE. Each fixture in `app/_dev/transfer-states.tsx` is mounted by calling its own
 * `render()` — so what is under test is the fixture the gallery ships, not a re-typed copy of its
 * props — and every sentence it paints is then matched against what the mapping functions in
 * `src/lib/transfer/{transferState,refundState}.ts` return for those same facts. The gallery's own
 * comment-stripped source is scanned for each produced sentence and must NOT contain it: a case
 * that passed by holding its own literal would fail here.
 *
 * WHAT THEY DO NOT PROVE. Rendering from supplied props, nothing more. No sandbox row, no read path,
 * no device result. Same evidence boundary as tests/v3-transfer-gallery.test.ts.
 *
 * NO seller-reversed refund variants are asserted, and that is the ruling, not an omission (A,
 * 2026-09-24): `reversed` is written only by `mark_transfer_reversed` from the stripe-webhook
 * `transfer.reversed` handler, so it is a fact about the SELLER's payout transfer and establishes
 * nothing about the buyer's refund. `SellerReversedBlock` taking no refund props is correct, and the
 * buyer's refund for that status is read from the buyer's own payment row — case (c).
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });

const th = vi.hoisted(() => ({ scheme: 'light' as 'light' | 'dark', sandbox: false, pref: 'system' }));

vi.mock('@/src/theme/appearance', async () => {
  const { paletteFor } = await import('@/src/theme/palette');
  return {
    useTheme: () => ({ scheme: th.scheme, palette: paletteFor(th.scheme) }),
    useAppearancePreference: () => ({ preference: th.pref, setPreference: (p: string) => { th.pref = p; } }),
  };
});
vi.mock('@/src/config/envGuard', () => ({
  get IS_SANDBOX_BUILD() { return th.sandbox; },
  ENV_GUARD_FAILURE: null,
}));
vi.mock('react-native', () => ({
  Platform: { OS: 'ios', select: (o: Record<string, unknown>) => o.ios },
  Pressable: 'Pressable', Text: 'Text', View: 'View', ScrollView: 'ScrollView',
  StyleSheet: { create: <T,>(s: T) => s, hairlineWidth: 1, absoluteFill: {}, absoluteFillObject: {} },
  useWindowDimensions: () => ({ width: 390, height: 844 }),
}));
vi.mock('react-native-safe-area-context', () => ({ useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }), SafeAreaView: 'SafeAreaView' }));
vi.mock('expo-router', () => ({ Redirect: 'Redirect', router: { back: () => {}, push: () => {} } }));
vi.mock('@/src/theme/typography', () => ({ textStyle: () => ({}), MAX_DISPLAY_FONT_SCALE: 1.3, AMOUNT_MIN_FONT_SCALE: 0.6, EASING_BEZIER: [0.2, 0, 0, 1] }));

import {
  BUYER_ORDER_CLOSED_COPY, REFUND_DUE_POLICY, REFUND_PENDING_LINE,
  refundLine, sellerHoldLine, sellerReleaseLine, type PaymentRefundFacts,
} from '@/src/lib/transfer/transferState';
import { refundStateLine } from '@/src/lib/transfer/refundState';
import { expandTree, findElement, HookHost, type Element } from './helpers/nav-stack-harness';

/** The gallery source with comments removed — a sentence found here would be a gallery literal. */
const galleryCode = async () => (await import('node:fs')).readFileSync('app/_dev/transfer-states.tsx', 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

/** Every string rendered anywhere under `node`, blocks rendered through (see tests/v3-transfer-gallery.test.ts). */
function texts(node: unknown): string[] {
  const out: string[] = [];
  const walk = (n: unknown) => {
    if (Array.isArray(n)) { n.forEach(walk); return; }
    const el = n as Element | null;
    if (!el || typeof el !== 'object' || !('props' in el)) return;
    if (typeof el.props.children === 'string') out.push(el.props.children);
    walk(el.props.children);
  };
  walk(expandTree(node));
  return out;
}

function mount(fn: () => unknown): HookHost {
  const h = new HookHost(fn, new Map()); h.mount(); h.flush(); return h;
}

type Fixture = { id: string; label: string; role: string; covers: string; render: () => unknown };

/** The fixture the gallery ships, by id — never a hand-built stand-in. */
async function fixture(id: string): Promise<Fixture> {
  const mod = await import('@/app/_dev/transfer-states');
  const f = (mod.TRANSFER_STATE_FIXTURES as unknown as Fixture[]).find((x) => x.id === id);
  expect(f, `no gallery fixture with id ${id}`).toBeDefined();
  return f!;
}

/** Mount that fixture's own render() and return what it painted. */
function paint(f: Fixture): string[] {
  return texts(mount(() => f.render()).output);
}

/** The props the fixture handed the shared block — the facts the case claims to exercise. */
function props(f: Fixture): Record<string, unknown> {
  return (f.render() as Element).props;
}

/** Every sentence this case painted must come from the mapping, not from a literal in the gallery. */
async function noGalleryLiterals(lines: string[]): Promise<void> {
  const code = await galleryCode();
  expect(lines.length).toBeGreaterThan(0);
  for (const line of lines) expect(code, `gallery holds the literal: ${line}`).not.toContain(line);
}

beforeEach(() => { th.scheme = 'light'; th.sandbox = false; th.pref = 'system'; vi.resetModules(); });

describe('(a) buyer · expired · PARTIAL refund — both figures established, both from the row', () => {
  it('GC1: the fixture supplies amount < total with neither NULL, and the block states both figures', async () => {
    const f = await fixture('buyer-expired-partial-refund');
    const refund = props(f).refund as PaymentRefundFacts;
    // The case is only a partial if the row establishes BOTH figures. Pin the facts, so a later edit
    // that drops `total` cannot leave the case passing while the sentence changes underneath it.
    expect(refund.amount_refunded_cents).not.toBeNull();
    expect(refund.total).not.toBeNull();
    expect(refund.amount_refunded_cents!).toBeLessThan(refund.total!);
    expect(props(f).status).toBe('expired');

    const lines = paint(f);
    const mapped = refundStateLine({ kind: 'loaded', facts: refund }, 'expired');
    expect(mapped).toBe(refundLine(refund));            // an EXECUTED refund: the row speaks for itself
    expect(mapped).toBe('Partial refund of $90 initiated');  // amount AND total, from this row alone
    expect(lines).toContain(mapped);
    expect(lines).toContain(BUYER_ORDER_CLOSED_COPY.expired.title);
    expect(lines).toContain(BUYER_ORDER_CLOSED_COPY.expired.body);
    // A recorded refund outranks the capture-based policy line, and the buyer never reads "reversed".
    expect(lines).not.toContain(REFUND_DUE_POLICY);
    expect(lines).not.toContain(REFUND_PENDING_LINE);
    expect(lines.join(' ')).not.toMatch(/reversed|released/i);
    await noGalleryLiterals(lines);
  });
});

describe('(b) buyer · expired · refund RECORDED with no confirmable amount', () => {
  it('GC2: refunded_at with a NULL amount reads "Refund recorded" — and NO amount appears anywhere', async () => {
    const f = await fixture('buyer-expired-refund-recorded-no-amount');
    const refund = props(f).refund as PaymentRefundFacts;
    expect(refund.refunded_at).not.toBeNull();
    expect(refund.amount_refunded_cents).toBeNull();
    expect(props(f).status).toBe('expired');

    const lines = paint(f);
    const mapped = refundStateLine({ kind: 'loaded', facts: refund }, 'expired');
    expect(mapped).toBe(refundLine(refund));
    expect(mapped).toBe('Refund recorded');
    expect(lines).toContain(mapped);
    expect(lines).toContain(BUYER_ORDER_CLOSED_COPY.expired.title);
    // THE POINT OF THE CASE: no figure is shown. `total` IS known on this row (12000), so a block
    // that reached for "the amount" would print "$120" and assert a refund the row does not record.
    expect(refund.total).not.toBeNull();
    const joined = lines.join(' ');
    expect(joined).not.toMatch(/\$/);
    expect(joined).not.toMatch(/\d/);
    expect(joined).not.toMatch(/in full/i);
    // An execution already recorded also outranks the due policy, even though status === 'succeeded'
    // would otherwise be the capture that policy needs.
    expect(refund.status).toBe('succeeded');
    expect(lines).not.toContain(REFUND_DUE_POLICY);
    expect(lines).not.toContain(REFUND_PENDING_LINE);
    await noGalleryLiterals(lines);
  });
});

describe('(c) buyer · reversed · FULL refund', () => {
  it('GC3: amount === total reads "Refund of $75 initiated" under the neutral closed-order words, never "reversed"', async () => {
    const f = await fixture('buyer-reversed-full-refund');
    const refund = props(f).refund as PaymentRefundFacts;
    expect(refund.amount_refunded_cents).toBe(refund.total);
    expect(refund.amount_refunded_cents).not.toBeNull();
    expect(props(f).status).toBe('reversed');

    const lines = paint(f);
    const mapped = refundStateLine({ kind: 'loaded', facts: refund }, 'reversed');
    expect(mapped).toBe(refundLine(refund));
    expect(mapped).toBe('Refund of $75 initiated');
    expect(lines).toContain(mapped);
    // The ORDER fact stays the buyer's neutral wording — the seller's payout event is not the
    // buyer's word, and "reversed" never reaches this screen.
    expect(lines).toContain(BUYER_ORDER_CLOSED_COPY.reversed.title);
    expect(lines).toContain(BUYER_ORDER_CLOSED_COPY.reversed.body);
    expect(lines.join(' ')).not.toMatch(/reversed|released|payout/i);
    expect(lines).not.toContain(REFUND_PENDING_LINE);
    await noGalleryLiterals(lines);
  });
});

describe('(d) seller · seller_sent · no review status and no auto_release_at', () => {
  it('GC4: no date line at all, while the status sentence and the report warning both stay', async () => {
    const f = await fixture('seller-sent-no-review-no-deadline');
    const p = props(f);
    expect(p.payoutReviewStatus).toBeNull();
    expect(p.autoReleaseAt).toBeNull();
    expect(p.payoutHoldUntil).toBeNull();
    // The block no longer takes a countdown at all (A's ruling, 2026-09-24): no sentence in it may be
    // keyed to the device clock, so the prop and the timer that fed it are gone.
    expect(p.releaseCountdown).toBeUndefined();
    // The mapping itself yields nothing for these facts — there is no date to omit downstream.
    expect(sellerHoldLine(null, null)).toBeNull();
    expect(sellerReleaseLine(null)).toBeNull();

    const lines = paint(f);
    const joined = lines.join(' ');
    // THE REST OF THE BLOCK IS INTACT: the status sentence and the report warning are unconditional.
    expect(joined).toMatch(/Waiting for the buyer to confirm they received the tickets/);
    expect(joined).toMatch(/If the buyer reports an issue, your payout will be held for review/);
    // NO DATE LINE, and no line that stands in for one.
    expect(joined).not.toMatch(/Payout held until/);
    expect(joined).not.toMatch(/Release decision/);
    expect(joined).not.toMatch(/review window has passed/i);
    expect(joined).not.toMatch(/manual review/i);
    expect(joined).not.toMatch(/\d{1,2}:\d{2}|\b\d{1,2} [A-Z][a-z]{2}\b/);   // TG4b's date shape
    expect(joined).not.toMatch(/automatic|shortly after|business day|once it clears/i);
    // …and no EMPTY Text painted where a date would have gone.
    const h = mount(() => f.render());
    expect(findElement(expandTree(h.output), (el) => el.type === 'Text' && el.props.children == null)).toBeUndefined();
    await noGalleryLiterals(lines);
  });
});

describe('the four cases are reachable in the route, labelled like the rest', () => {
  it('GC5: a sandbox build renders all four through the gallery itself, each with the synthetic caveat', async () => {
    th.sandbox = true;
    const mod = await import('@/app/_dev/transfer-states');
    const ids = [
      'buyer-expired-partial-refund',
      'buyer-expired-refund-recorded-no-amount',
      'buyer-reversed-full-refund',
      'seller-sent-no-review-no-deadline',
    ];
    const all = mod.TRANSFER_STATE_FIXTURES as unknown as Fixture[];
    for (const id of ids) expect(all.map((f) => f.id), id).toContain(id);
    // The route takes no query parameter: it renders every fixture in one scroll, so these four are
    // reached by opening it. Entry is the sandbox-gated Settings row (TG7).
    const h = mount(() => (mod.default as () => unknown)());
    const t = texts(h.output);
    for (const id of ids) {
      const f = all.find((x) => x.id === id)!;
      expect(t, id).toContain(f.label);
      expect(t, id).toContain(`Covers: ${f.covers}`);
      for (const line of paint(f)) expect(t, `${id}: ${line}`).toContain(line);
    }
    // The caveat is still on every card, the four new ones included.
    expect(t.filter((x) => x === mod.SYNTHETIC_LABEL).length).toBeGreaterThanOrEqual(all.length);
  });
});
