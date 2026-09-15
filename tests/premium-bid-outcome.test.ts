/**
 * tests/premium-bid-outcome.test.ts — Place bid: tap received ≠ bid accepted ≠ leading.
 *
 * CFT-203 / CFT-205 / CFT-207 on PlaceBidScreen. "You're leading" is said only
 * after the server accepted the insert AND a fresh read confirms the position;
 * the rule is the Bids tab's own, so both screens tell one truth (item 53).
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { bidOutcome, bidOutcomeCopy, bidTotalLabel } from '@/src/lib/bid/bidEntry';
import { bidStatusOf } from '@/src/lib/bids/bidState';
import { formatDollars } from '@/src/lib/money';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('bidOutcome — position from a fresh read, never from the tap', () => {
  it('leading when the fresh floor is the bid itself', () => {
    expect(bidOutcome(80, 80)).toBe('leading');
  });
  it('outbid when someone moved the floor above it in between', () => {
    expect(bidOutcome(80, 90)).toBe('outbid');
  });
  it('only "accepted" when the re-read is unavailable', () => {
    expect(bidOutcome(80, null)).toBe('accepted');
    expect(bidOutcome(80, undefined)).toBe('accepted');
    expect(bidOutcome(80, Number.NaN)).toBe('accepted');
  });
  it('agrees with the Bids tab rule (amount >= current_bid is winning)', () => {
    const me = 'u1';
    const row = (amount: number, current: number) => ({
      amount,
      bidder_id: me,
      listing: { current_bid: current, auction_status: 'active', ends_at: new Date(Date.now() + 3_600_000).toISOString(), status: 'active', winner_user_id: null, winning_bid_amount: null },
    });
    for (const [amount, current] of [[80, 80], [80, 90], [100, 95]] as const) {
      const tab = bidStatusOf(row(amount, current) as any, me);
      const here = bidOutcome(amount, current);
      expect(here === 'leading').toBe(tab === 'winning');
    }
  });
});

describe('bidOutcomeCopy — calm, exact, and honest about position', () => {
  it('leading: says it is the highest right now and repeats the all-in', () => {
    const c = bidOutcomeCopy('leading', 80, 80);
    expect(c.title).toBe("You're leading");
    expect(c.body).toContain('$80');
    expect(c.body).toContain('highest right now');
    expect(c.body).toContain(`${bidTotalLabel(80)} total`);
  });
  it('outbid: the bid is in, the higher bid is named, no celebration', () => {
    const c = bidOutcomeCopy('outbid', 80, 90);
    expect(c.title).toBe('Bid placed, but outbid');
    expect(c.body).toContain('someone has already bid $90');
    expect(c.body).not.toMatch(/leading|win/i);
  });
  it('accepted: the old "Bid placed" wording, unchanged', () => {
    const c = bidOutcomeCopy('accepted', 80, null);
    expect(c.title).toBe('Bid placed');
    expect(c.body).toBe("Your bid of $80 is in. If you win, you'll pay $88 total (includes the 10% service fee).");
  });
});

describe('formatDollars — the one formatter for dollar-held amounts (CFT-207)', () => {
  it('matches the three screen-local formatters it replaces', () => {
    expect(formatDollars(80)).toBe('$80');
    expect(formatDollars(1250)).toBe('$1,250');
    expect(formatDollars(22.5)).toBe('$22.50');
    expect(formatDollars(0)).toBe('$0');
  });
  it('never throws on a bad or negative value', () => {
    expect(formatDollars(Number.NaN)).toBe('—');
    expect(formatDollars(-5)).toBe('−$5');
    expect(formatDollars(-0.001)).toBe('$0');
  });
});

describe('PlaceBidScreen — shipped-source guards', () => {
  const screen = read('src/screens/PlaceBidScreen.tsx');
  const code = stripComments(screen);

  it('shows a visible pending label and holds a single-flight lock', () => {
    expect(screen).toContain('pendingLabel="Submitting bid…"');
    expect(screen).toContain('const flight = useSingleFlight();');
    expect(screen).toContain('flight.run(() => submitBid(user.id, selectedBid))');
  });

  it('confirms and re-reads only AFTER the insert succeeded', () => {
    const insert = code.indexOf("from('bids').insert(");
    const failed = code.indexOf("Alert.alert('Bid failed', error.message)");
    const haptic = code.indexOf('hapticConfirm();');
    const reread = code.indexOf("select('current_bid')");
    const outcome = code.indexOf('bidOutcomeCopy(bidOutcome(amount, freshBid), amount, freshBid)');
    expect(insert).toBeGreaterThan(0);
    expect(failed).toBeGreaterThan(insert);
    expect(haptic).toBeGreaterThan(failed);
    expect(reread).toBeGreaterThan(haptic);
    expect(outcome).toBeGreaterThan(reread);
    // no success copy is hard-coded in the screen any more
    expect(code).not.toContain("'Bid placed'");
    expect(code).not.toContain("You're leading");
  });

  it('the bid path is otherwise unchanged (F-5 guard, bids insert, back)', () => {
    for (const marker of ["schema('kernel')", "'DELETION_PENDING'", "from('bids').insert(", 'router.back()']) {
      expect(screen).toContain(marker);
    }
  });

  it('stepper and quick-add keys use Tappable, and amounts use formatDollars', () => {
    expect(code).not.toMatch(/<Pressable\b/);
    expect(screen).toContain('<Tappable');
    expect(screen).toContain('const fmt$ = formatDollars;');
    expect(code).not.toContain("toLocaleString('en-US')");
  });
});
