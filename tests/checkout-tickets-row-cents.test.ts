/**
 * The checkout Tickets row shows cents like the rows under it (TEST-MODE capture finding 7, B04):
 * "$95" sat next to "$9.50" and "$104.50". The row went through `formatCents`, which trims ".00";
 * it now uses `formatCentsV3`, the 2dp display the rest of V3 money uses. Display only: the server
 * breakdown's cents are passed through unchanged. A ruled this row only (2026-10-21).
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { formatCents, formatCentsV3 } from '@/src/lib/money';

const src = readFileSync('src/screens/checkout/CheckoutNative.tsx', 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('checkout Tickets row', () => {
  it('TC1: 9500 cents reads "$95.00" beside "$9.50" and "$104.50"; formatCents is the control', () => {
    expect(formatCentsV3(9500)).toBe('$95.00');
    expect(formatCents(9500)).toBe('$95');          // negative control: the old formatter
    expect(formatCents(950)).toBe('$9.50');
    expect(formatCents(10450)).toBe('$104.50');
  });

  it('TC2: the breakdown item amount uses the 2dp formatter; fee and total are unchanged', () => {
    expect(src).toContain('amount: formatCentsV3(serverBreakdown.amount),');
    expect(src.replace('amount: formatCentsV3(', 'amount: formatCents(')).not.toContain('amount: formatCentsV3(serverBreakdown.amount),');
    expect(src).toContain('fee: formatCents(serverBreakdown.buyerFee),');
    expect(src).toContain('total: formatCents(serverBreakdown.total),');
  });
});
