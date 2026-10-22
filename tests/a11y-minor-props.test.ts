/**
 * Minor accessibility gaps from the C a11y audit (2026-10-21), accessibility props only. No visual
 * change: roles, labels, states, hidden glyphs and invisible hit areas. Each pin has a witness: the
 * same check on a copy with the fix removed must fail.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { TEXT_LINK_HIT_SLOP } from '@/src/lib/a11y/touch';

const code = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

function pinned(src: string, needle: string | RegExp, remove: (s: string) => string, what: string) {
  const has = (s: string) => (typeof needle === 'string' ? s.includes(needle) : needle.test(s));
  expect(has(src), `${what}: missing`).toBe(true);
  expect(has(remove(src)), `${what}: WITNESS`).toBe(false);
}

describe('minor a11y props', () => {
  it('M11: the proof viewer Retry is a button', () => {
    const s = code('src/components/ProofImageViewer.tsx');
    const n = '<Pressable style={s.retryBtn} onPress={() => setRetryKey((k) => k + 1)} accessibilityRole="button" accessibilityLabel="Try loading the image again">';
    pinned(s, n, (x) => x.replace(n, '<Pressable style={s.retryBtn} onPress={() => setRetryKey((k) => k + 1)}>'), 'proof retry');
  });

  it('M14: decorative check marks and FAQ +/– are hidden (their state is already spoken)', () => {
    const sell = code('src/screens/CreateListingScreen.tsx');
    const check = /<Text style=\{sx\.sheetCheck\} accessibilityElementsHidden importantForAccessibility="no">\{'✓'\}<\/Text>/g;
    expect(sell.match(check)?.length).toBe(3);
    expect(sell).toMatch(/<Text style=\{sx\.checkMark\} accessibilityElementsHidden importantForAccessibility="no">\{'✓'\}<\/Text>/);
    pinned(code('app/settings/support.tsx'), '<Text style={s.faqChevron} accessibilityElementsHidden importantForAccessibility="no">',
      (x) => x.replace(' accessibilityElementsHidden importantForAccessibility="no"', ''), 'faq chevron');
  });

  it('M16: the avatar controls report busy while uploading; the text twin is a button', () => {
    for (const f of ['app/settings/edit-profile.tsx', 'app/(tabs)/profile.tsx']) {
      pinned(code(f), 'accessibilityState={{ disabled: avatarUploading, busy: avatarUploading }}',
        (x) => x.split('accessibilityState={{ disabled: avatarUploading, busy: avatarUploading }}').join(''), f);
    }
    expect(code('app/settings/edit-profile.tsx')).toMatch(/<Pressable onPress=\{handleAvatarPress\} disabled=\{avatarUploading\} hitSlop=\{TEXT_LINK_HIT_SLOP\} accessibilityRole="button" accessibilityState=\{\{ disabled: avatarUploading, busy: avatarUploading \}\}>/);
  });

  it('M17: text-only links reach 44pt with an invisible hit area', () => {
    expect(TEXT_LINK_HIT_SLOP).toEqual({ top: 14, bottom: 14, left: 8, right: 8 });
    const sites: Array<[string, string]> = [
      ['app/(auth)/login.tsx', 'onPress={handleForgotPassword}'],
      ['app/(auth)/signup.tsx', 'setStep(prevStep(step)); }}'],
      ['app/(tabs)/explore.tsx', 'accessibilityLabel="Retry search"'],
      ['app/(tabs)/bids.tsx', 'accessibilityLabel="Retry loading bids and purchases"'],
      ['app/(tabs)/home.tsx', 'accessibilityLabel="Retry loading this filter"'],
      ['app/settings/index.tsx', 'onPress={refreshDeletionState}'],
      ['src/components/listing/BidActivity.tsx', 'accessibilityLabel="Retry loading bids"'],
    ];
    for (const [f, anchor] of sites) {
      const s = code(f);
      const at = s.indexOf(anchor);
      expect(at, `${f}: ${anchor}`).toBeGreaterThan(-1);
      const tag = s.slice(s.lastIndexOf('<Pressable', at), s.indexOf('>', at));
      expect(tag, f).toContain('hitSlop={TEXT_LINK_HIT_SLOP}');
      expect(tag.replace('hitSlop={TEXT_LINK_HIT_SLOP}', 'hitSlop={8}'), `${f} WITNESS`).not.toContain('TEXT_LINK_HIT_SLOP');
    }
  });

  it('M21: the bar action says its sub-line in the label, not only as a hint', () => {
    pinned(code('src/components/ui/StickyBar.tsx'), 'accessibilityLabel={subLabel ? `${label}. ${subLabel}` : undefined}',
      (x) => x.replace('accessibilityLabel={subLabel ? `${label}. ${subLabel}` : undefined}', ''), 'bar label');
  });

  it('M22: the listing name is a heading', () => {
    pinned(code('src/components/listing/ListingHero.tsx'), '<NameText token="nameDetail" maxLines={null} style={styles.title} accessibilityRole="header">',
      (x) => x.replace(' accessibilityRole="header"', ''), 'hero heading');
    expect(code('src/components/NameText.tsx')).toMatch(/accessibilityRole=\{accessibilityRole\}/);
  });

  it('M23: the public profile initials are hidden (the name follows)', () => {
    pinned(code('app/profile/[id].tsx'), '<Text style={s.avatarInitials} accessibilityElementsHidden importantForAccessibility="no">',
      (x) => x.split(' accessibilityElementsHidden importantForAccessibility="no"').join(''), 'initials');
  });
});
