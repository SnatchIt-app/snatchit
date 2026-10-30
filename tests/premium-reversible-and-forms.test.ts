/**
 * tests/premium-reversible-and-forms.test.ts — batch 2: reversible actions,
 * unsaved-work guards, visual discipline.
 *
 * CFT-204 (instant preferences with rollback), CFT-208 (back gestures preserve
 * unfinished work), CFT-207 (one formatter, tabular countdowns), CFT-201 on the
 * seller card. The pure pieces run; the screens are pinned by source contract.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { createCoalescedSaver } from '@/src/lib/settings/coalescedSave';
import { shouldAskBeforeLeaving, UNSAVED_COPY } from '@/src/lib/nav/unsavedChanges';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

type Gate = { resolve: (ok: boolean) => void };
function gatedSave() {
  const gates: Gate[] = [];
  const calls: string[][] = [];
  const save = (v: string[]) => new Promise<boolean>((res) => { calls.push(v); gates.push({ resolve: res }); });
  return { save, gates, calls };
}
const tick = () => new Promise((r) => setTimeout(r, 0));

describe('coalesced save — latest wins, failure rolls back (CFT-204)', () => {
  it('commits a successful save and reports pending around it', async () => {
    const { save, gates } = gatedSave();
    const pending: boolean[] = [];
    const saver = createCoalescedSaver<string[]>({ initial: [], save, onPendingChange: (p) => pending.push(p) });
    const a = ['wynwood'];
    saver.submit(a);
    expect(saver.pending).toBe(true);
    gates[0].resolve(true);
    expect(await saver.settle()).toBe(true);
    expect(saver.committed).toBe(a);
    expect(pending).toEqual([true, false]);
  });

  it('rolls back to the committed value when a save fails, and says so once', async () => {
    const { save, gates } = gatedSave();
    const rollbacks: [string[], string[]][] = [];
    const initial = ['brickell'];
    const saver = createCoalescedSaver<string[]>({ initial, save, onRollback: (c, f) => rollbacks.push([c, f]) });
    const bad = ['brickell', 'wynwood'];
    saver.submit(bad);
    gates[0].resolve(false);
    expect(await saver.settle()).toBe(false);
    expect(saver.committed).toBe(initial);
    expect(rollbacks).toEqual([[initial, bad]]);
  });

  it('while a save runs, only the newest requested value is kept; the middle one is dropped', async () => {
    const { save, gates, calls } = gatedSave();
    const saver = createCoalescedSaver<string[]>({ initial: [], save });
    const one = ['a'], two = ['a', 'b'], three = ['a', 'b', 'c'];
    saver.submit(one);
    saver.submit(two);
    saver.submit(three);
    expect(calls).toEqual([one]);
    gates[0].resolve(true);
    await tick();
    expect(calls).toEqual([one, three]);
    gates[1].resolve(true);
    expect(await saver.settle()).toBe(true);
    expect(saver.committed).toBe(three);
  });

  it('a failure that a newer value supersedes does not roll back; the newer value decides', async () => {
    const { save, gates } = gatedSave();
    const rollbacks: unknown[] = [];
    const saver = createCoalescedSaver<string[]>({ initial: [], save, onRollback: (c, f) => rollbacks.push([c, f]) });
    const one = ['a'], two = ['a', 'b'];
    saver.submit(one);
    saver.submit(two);
    gates[0].resolve(false);   // `one` fails, but `two` is queued
    await tick();
    expect(rollbacks).toEqual([]);
    gates[1].resolve(true);
    expect(await saver.settle()).toBe(true);
    expect(saver.committed).toBe(two);
  });

  it('a throwing save counts as a failure, not a crash', async () => {
    const saver = createCoalescedSaver<string[]>({ initial: [], save: async () => { throw new Error('offline'); } });
    saver.submit(['x']);
    expect(await saver.settle()).toBe(false);
    expect(saver.committed).toEqual([]);
  });

  it('settle() with nothing submitted is true', async () => {
    const saver = createCoalescedSaver<string[]>({ initial: [], save: async () => true });
    expect(await saver.settle()).toBe(true);
  });
});

describe('shouldAskBeforeLeaving (CFT-208)', () => {
  it('asks exactly when there is something to lose', () => {
    expect(shouldAskBeforeLeaving({ dirty: true })).toBe(true);
    expect(shouldAskBeforeLeaving({ dirty: false })).toBe(false);
  });
  it('never asks during or after a save', () => {
    expect(shouldAskBeforeLeaving({ dirty: true, submitting: true })).toBe(false);
    expect(shouldAskBeforeLeaving({ dirty: true, saved: true })).toBe(false);
  });
  it('every dialog has a calm two-button shape', () => {
    for (const c of Object.values(UNSAVED_COPY)) {
      expect(c.title.length).toBeGreaterThan(0);
      expect(c.stayLabel).not.toMatch(/cancel|ok/i);
      expect(c.leaveLabel).not.toMatch(/ok|yes/i);
    }
  });
});

describe('Your scene — instant, background-saved, rolled back on failure', () => {
  const screen = read('app/settings/preferences.tsx');
  const code = stripComments(screen);

  it('toggles update at once and submit to the coalesced saver', () => {
    expect(screen).toContain("import { createCoalescedSaver, type CoalescedSaver } from '@/src/lib/settings/coalescedSave'");
    expect(code).toMatch(/setSelected\(next\);\s*saverRef\.current\?\.submit\(Array\.from\(next\)\)/);
  });

  it('a failed save rolls the chips back and explains, on screen and to a screen reader', () => {
    expect(code).toMatch(/onRollback: \(committed\) => \{\s*setSelected\(new Set\(committed\)\);\s*setNotice\(SCENE_ROLLBACK_NOTICE\);\s*AccessibilityInfo\.announceForAccessibility\(SCENE_ROLLBACK_NOTICE\)/);
    expect(screen).toContain('accessibilityRole="alert"');
  });

  it('Done waits for the in-flight save and leaves only when committed; a back gesture while saving asks', () => {
    expect(code).toMatch(/const ok = \(await saverRef\.current\?\.settle\(\)\) \?\? true;\s*if \(ok\) router\.back\(\);/);
    expect(screen).toContain('pendingLabel="Saving…"');
    expect(screen).toContain('useUnsavedChangesGuard({ when: pending, ...UNSAVED_COPY.stillSaving })');
    // the only navigation out is the guarded one above
    expect(code.split('router.back()').length - 1).toBe(1);
  });

  it('the data path is unchanged', () => {
    expect(screen).toContain("rpc('get_my_profile')");
    expect(screen).toContain("update({ preferred_neighborhoods: hoods })");
  });
});

describe('Notification toggles — revert explains itself inline', () => {
  const screen = read('app/settings/notifications.tsx');
  const code = stripComments(screen);
  it('keeps the optimistic flip and the revert, drops the modal alert', () => {
    expect(code).toMatch(/setPrefs\(\{ \.\.\.prefs, \[key\]: newValue \}\);/);
    expect(code).toMatch(/setPrefs\(\(p\) => \(p \? \{ \.\.\.p, \[key\]: prev \} : p\)\);/);
    expect(code).not.toContain('Alert.alert(');
    expect(code).toContain('AccessibilityInfo.announceForAccessibility(msg)');
    expect(screen).toContain("It's back to ${prev ? 'on' : 'off'}");
  });
});

describe('Forms ask before a back gesture discards work (CFT-208)', () => {
  it('edit listing: dirty = differs from the loaded row; stands down while saving and after save', () => {
    const edit = read('app/listing/edit/[id].tsx');
    expect(edit).toContain('when: shouldAskBeforeLeaving({ dirty, submitting: saving, saved })');
    expect(edit).toContain('...UNSAVED_COPY.listingEdit');
    expect(edit).toContain("eventName !== (listing.event_name ?? '')");
    expect(edit).toMatch(/setSaved\(true\);[^\n]*\n\s*Alert\.alert\('Saved'/);
    expect(edit).toContain('pendingLabel="Saving…"');
  });
  it('report: dirty = a reason chosen or notes typed', () => {
    const report = read('app/report/[type]/[id].tsx');
    expect(report).toContain('const dirty = reason != null || notes.trim().length > 0;');
    expect(report).toContain('when: shouldAskBeforeLeaving({ dirty, submitting, saved: sent })');
    expect(report).toMatch(/setSent\(true\);[^\n]*\n\s*Alert\.alert\('Report submitted'/);
    expect(report).toContain('pendingLabel="Sending report…"');
  });
  it('the guard replays the original navigation action on "leave"', () => {
    const hook = read('src/hooks/useUnsavedChangesGuard.ts');
    // usePreventRemove, not a bare beforeRemove listener: only it stops an iOS swipe natively
    // (F-NAV-1; behaviour in tests/unsaved-guard-native-dismiss.test.ts)
    expect(hook).toContain('usePreventRemove(opts.when, ({ data }) => {');
    expect(hook).not.toContain("addListener('beforeRemove'");
    expect(hook).toContain('navigation.dispatch(data.action)');
  });
});

describe('Visual discipline (CFT-207) and press response on the seller card (CFT-201)', () => {
  it('the three local currency formatters are gone; amounts go through formatDollars', () => {
    for (const rel of ['src/screens/PlaceBidScreen.tsx', 'src/components/SellerListingCard.tsx', 'app/(tabs)/profile.tsx']) {
      const code = stripComments(read(rel));
      expect(code, rel).not.toContain("toLocaleString('en-US')");
      expect(code, rel).toContain('formatDollars');
    }
  });
  it('countdowns use tabular digits', () => {
    expect(read('src/components/listing/ListingStatusBanner.tsx')).toContain("detail: { color: p.text.secondary, fontVariant: ['tabular-nums'] }");
    expect(read('app/transfer/receive/[id].tsx')).toContain("countdownText: { color: p.status.warning, fontVariant: ['tabular-nums'] }");
  });
  it('the seller card and its row actions are Tappable, not bare Pressables', () => {
    const card = stripComments(read('src/components/SellerListingCard.tsx'));
    expect(card).not.toMatch(/<Pressable\b/);
    expect(card.split('<Tappable').length - 1).toBe(4);
    expect(card).toContain('accessibilityLabel={a11yLabel}');
  });
  it('the large amount beside Place bid is capped like the CTA (item 52)', () => {
    // V3 (owner 2026-09-23): the sticky side-total is gone; the large figure beside the button
    // is now the summary's Total row, and it keeps the same cap.
    const bid = read('src/screens/PlaceBidScreen.tsx');
    expect(bid).toMatch(/s\.summaryTotalValue\]\}\s+numberOfLines=\{1\}\s+maxFontSizeMultiplier=\{MAX_DISPLAY_FONT_SCALE\}/);
  });
});
