/**
 * The checkout hold countdown is spoken as a duration (C a11y audit 2026-10-21, finding 6; with 9).
 *
 * "Held for you · 4:32 · until 7:34 pm" is read by VoiceOver with "4:32" as a time of day, on the one
 * row that says how long a buyer's hold on a ticket lasts. The visible m:ss is unchanged. It still
 * comes from gated payControl.fmtCountdown, which is not edited. The row and the listing's
 * "reserved by you" banner now carry a spoken label: "4 minutes 32 seconds left". The banner also
 * becomes one accessible element, so iOS reads its label at all (finding 9).
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { spokenDuration } from '@/src/lib/a11y/spoken';

const code = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('spokenDuration', () => {
  it('SD1: minutes and seconds, singular and plural, floored like the visible m:ss', () => {
    expect(spokenDuration(272_000)).toBe('4 minutes 32 seconds');
    expect(spokenDuration(272_999)).toBe('4 minutes 32 seconds');
    expect(spokenDuration(61_000)).toBe('1 minute 1 second');
    expect(spokenDuration(120_000)).toBe('2 minutes');
    expect(spokenDuration(45_000)).toBe('45 seconds');
    expect(spokenDuration(900)).toBe('less than a second');
    expect(spokenDuration(0)).toBe('no time');
    expect(spokenDuration(-5)).toBe('no time');
  });
});

describe('the spoken labels are wired, and the gated formatter is untouched', () => {
  it('SD2: the checkout hold row speaks the duration', () => {
    const view = code('src/screens/checkout/CheckoutView.tsx');
    expect(view).toMatch(/accessibilityLabel=\{`Held for you, \$\{spokenDuration\(reservationMsLeft\)\} left\$\{holdUntil \? `, until \$\{holdUntil\}` : ''\}`\}/);
  });

  it('SD3: the listing banner is one element and speaks the duration for "reserved by you"', () => {
    const banner = code('src/components/listing/ListingStatusBanner.tsx');
    expect(banner).toMatch(/\n\s*accessible\n/);
    expect(banner).toContain('spokenDetail ?? status.detail');
    const screen = code('src/screens/ListingDetailScreen.tsx');
    expect(screen).toMatch(/spokenDetail=\{status\?\.kind === 'reserved_by_you' \? `\$\{spokenDuration\(reservationMsLeft\)\} left to finish checkout\.` : undefined\}/);
  });

  it('SD4: payControl.ts has no spoken form (it stays as it is)', () => {
    expect(readFileSync('src/lib/checkout/payControl.ts', 'utf8')).not.toContain('spoken');
  });
});
