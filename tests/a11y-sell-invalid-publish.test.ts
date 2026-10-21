/**
 * An invalid List press is spoken (C a11y audit 2026-10-21, finding 2).
 *
 * `setSubmitted(true)` makes every field show its error, but on iOS nothing was announced and focus
 * stayed on the button. A VoiceOver seller heard nothing and had to search a long form for what
 * failed. The press now announces how many fields need attention and what each one says, in form
 * order. Every press announces, including a repeat. Moving focus to the first field is not done here
 * (it needs a ref on each field) and stays open.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { invalidSellSummary, sellErrors } from '@/src/lib/sell/sellState';

const blank = {
  eventName: '', venue: 'Jolene Sound Room', neighborhood: 'downtown', ticketType: 'GA', transferMethod: 'mobile',
  startingBid: '', buyNowEnabled: false, buyNowPrice: '', durationHours: 72,
  coverLocalUri: 'file:///c.jpg', proofLocalUri: 'file:///p.jpg', commitmentAccepted: true,
};

describe('invalidSellSummary', () => {
  it('IS1: counts the fields and reads each message, in form order', () => {
    expect(invalidSellSummary(sellErrors(blank as never)))
      .toBe('2 fields need attention. Event name is required. Starting bid must be ≥ $1.');
  });

  it('IS2: one field is singular; a valid form says nothing', () => {
    expect(invalidSellSummary(sellErrors({ ...blank, startingBid: '20' } as never)))
      .toBe('1 field needs attention. Event name is required.');
    expect(invalidSellSummary(sellErrors({ ...blank, eventName: 'IDEMI', startingBid: '20' } as never))).toBe('');
  });

  it('IS3: the invalid branch of handlePublish announces it on iOS before returning', () => {
    const src = readFileSync('src/screens/CreateListingScreen.tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    const h = src.slice(src.indexOf('async function handlePublish()'), src.indexOf('const banned = findBannedContent('));
    expect(h).toMatch(/if \(block\?\.kind === 'invalid' && Platform\.OS === 'ios'\) \{\s*AccessibilityInfo\.announceForAccessibility\(invalidSellSummary\(errors\)\);/);
    expect(h.indexOf('invalidSellSummary(errors)')).toBeLessThan(h.lastIndexOf('return;'));
  });
});
