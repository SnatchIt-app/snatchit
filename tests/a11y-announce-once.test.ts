/**
 * iOS announcements for text that appears or changes (C a11y audit, 2026-10-21, finding 1).
 *
 * `accessibilityRole="alert"` doesn't speak on iOS when the element appears, and
 * `accessibilityLiveRegion` is Android-only. So a failed sign-in, an outbid notice or a checkout error
 * said nothing to a VoiceOver user. `announcementFor` is the decision the shared hook makes on each
 * change: announce new words once, never the same words twice in a row, and forget them once they
 * clear, so the same error after a fresh attempt is heard again.
 */
import { describe, expect, it } from 'vitest';

import { announcementFor } from '@/src/lib/a11y/announce';

describe('announcementFor', () => {
  it('N1: new text is announced and remembered', () => {
    expect(announcementFor(null, 'Wrong email or password.')).toEqual({ say: 'Wrong email or password.', last: 'Wrong email or password.' });
  });

  it('N2: the same text again (a re-render) is not announced twice', () => {
    expect(announcementFor('Wrong email or password.', 'Wrong email or password.')).toEqual({ say: null, last: 'Wrong email or password.' });
  });

  it('N3: different text replaces the old and is announced', () => {
    expect(announcementFor('A', 'B')).toEqual({ say: 'B', last: 'B' });
  });

  it('N4: cleared text says nothing and forgets, so a repeat after a retry is heard again', () => {
    expect(announcementFor('A', null)).toEqual({ say: null, last: null });
    expect(announcementFor('A', '')).toEqual({ say: null, last: null });
    expect(announcementFor('A', '   ')).toEqual({ say: null, last: null });
    expect(announcementFor(null, 'A')).toEqual({ say: 'A', last: 'A' });
  });
});
