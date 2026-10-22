/**
 * The checkout Tickets row shows cents like the rows under it (TEST-MODE capture finding 7, B04):
 * "$95" sat next to "$9.50" and "$104.50". The row went through `formatCents`, which trims ".00";
 * it now uses `formatCentsV3`, the 2dp display the rest of V3 money uses. Display only: the server
 * breakdown's cents are passed through unchanged. A's ruling (2026-10-21, after review M2): all three
 * rows, since one row alone moved the mismatch onto every multiple-of-$10 price ("$100.00 / $10").
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { formatCents, formatCentsV3 } from '@/src/lib/money';

const src = readFileSync('src/screens/checkout/CheckoutNative.tsx', 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('checkout breakdown: one formatter for all three rows (A, 2026-10-21)', () => {
  const rows = (amount: number, fee: number, total: number) => [formatCentsV3(amount), formatCentsV3(fee), formatCentsV3(total)];

  it('TC1: 9500/950/10450 and 10000/1000/11000 read with cents on every row', () => {
    expect(rows(9500, 950, 10450)).toEqual(['$95.00', '$9.50', '$104.50']);
    expect(rows(10000, 1000, 11000)).toEqual(['$100.00', '$10.00', '$110.00']);
    // Control: the old formatter mixes forms on the most common prices.
    expect([formatCents(10000), formatCents(1000), formatCents(11000)]).toEqual(['$100', '$10', '$110']);
    expect(formatCents(9500)).toBe('$95');
  });

  it.each(['amount: formatCentsV3(serverBreakdown.amount),', 'fee: formatCentsV3(serverBreakdown.buyerFee),', 'total: formatCentsV3(serverBreakdown.total),'])(
    'TC2: the breakdown row uses the 2dp formatter: %s', (line) => {
      // The pin itself. (A's review: the old "control" replaced the line and then asserted its absence,
      // which can never fail, so it is gone. TC1's formatCents assertions are the real control.)
      expect(src).toContain(line);
    });

  it('TC3: the price-change notice and its Accept label use the same 2dp formatter (A, 2026-10-21)', () => {
    expect(src).toContain('It was ${formatCentsV3(priceChange.previousCents)} and is now ${formatCentsV3(priceChange.nextCents)}');
    expect(src).toContain('label: `Accept ${formatCentsV3(priceChange.nextCents)}`');
    expect(src).not.toMatch(/formatCents\(priceChange\./);
  });
});
