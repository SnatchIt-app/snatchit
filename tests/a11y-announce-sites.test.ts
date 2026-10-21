/**
 * Where VoiceOver must hear text that appears (C a11y audit 2026-10-21, findings 1, 3, 5 and 7).
 *
 * Each site below showed its text in an `accessibilityRole="alert"` element or an Android-only live
 * region, so iOS said nothing. Each now passes the shown text to `useAnnounceOnce` (or `<Announce>`
 * where the text is computed after an early return). Source contracts with a witness: the check is
 * run again on a copy with the call removed and must fail. Not a device result.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

function code(rel: string): string {
  return readFileSync(rel, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
}

function pinned(src: string, pattern: RegExp, what: string) {
  expect(pattern.test(src), `${what}: missing`).toBe(true);
  const removed = src.replace(/useAnnounceOnce\([\s\S]*?\);\n|<Announce [^>]*\/>/g, '');
  expect(pattern.test(removed), `${what}: WITNESS — still passes with the announcement removed`).toBe(false);
}

const SITES: Array<[string, string, RegExp]> = [
  ['sign-in error', 'app/(auth)/login.tsx', /useAnnounceOnce\(error\)/],
  ['sign-in session notice', 'app/(auth)/login.tsx', /useAnnounceOnce\(sessionNotice\)/],
  ['sign-up message', 'app/(auth)/signup.tsx', /useAnnounceOnce\(message\?\.text\)/],
  ['search failure notice', 'app/(tabs)/explore.tsx', /useAnnounceOnce\(text\)/],
  ['search results settled', 'app/(tabs)/explore.tsx', /useAnnounceOnce\([\s\S]{0,80}searchResultsHeader\(shown\.length\)[\s\S]{0,80}searchEmptyState\(/],
  ['bids refresh failed', 'app/(tabs)/bids.tsx', /useAnnounceOnce\(loadError && bids\.length > 0 \? BIDS_REFRESH_FAILED_COPY\[loadError\]/],
  ['home filter refresh failed', 'app/(tabs)/home.tsx', /useAnnounceOnce\(datasetFailure === 'inline'[\s\S]{0,60}HOME_FILTER_REFRESH_FAILED_COPY/],
  ['settings deletion banners', 'app/settings/index.tsx', /useAnnounceOnce\(\s*deletionPending \? 'Account deletion requested\.[\s\S]{0,160}deletionProbeFailed \? 'We could not check your account status\.'/],
  ['outbid toast', 'src/components/listing/OutbidToast.tsx', /useAnnounceOnce\(visible \? message : null\)/],
  ['listing connection notice', 'src/screens/ListingDetailScreen.tsx', /<Announce text=\{liveNotice\} \/>/],
  ['checkout error line', 'src/screens/checkout/CheckoutView.tsx', /useAnnounceOnce\(!preparing && !paymentMethodLine && !notice \? errorLine : null\)/],
  ['checkout notice', 'src/screens/checkout/CheckoutView.tsx', /useAnnounceOnce\(`\$\{notice\.title\}\. \$\{notice\.body\}`\)/],
  ['checkout outcome face', 'src/screens/checkout/CheckoutView.tsx', /useAnnounceOnce\(`\$\{kicker\}\. \$\{title\}`\)/],
];

describe('VoiceOver announcements at the sites iOS left silent', () => {
  it.each(SITES)('AS: %s (%s)', (what, file, pattern) => {
    pinned(code(file), pattern, what);
  });

  it('AS-copy: the settings announcement says the banner\'s own words', () => {
    const src = code('app/settings/index.tsx');
    expect(src).toContain('>Account deletion requested</Text>');
    expect(src).toContain('Your account deletion request is pending. You can withdraw it to keep your account.');
    expect(src).toContain('>We could not check your account status.</Text>');
  });

  it('AS-hook: ListingDetailScreen calls no announce HOOK after its early returns', () => {
    const src = code('src/screens/ListingDetailScreen.tsx');
    expect(src).not.toMatch(/useAnnounceOnce\(/);
  });
});
