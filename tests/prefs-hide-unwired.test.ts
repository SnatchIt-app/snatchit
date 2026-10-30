/**
 * tests/prefs-hide-unwired.test.ts — notification batch 1, item 1 (owner ruling
 * 2026-09-17): Settings › Notifications keeps "Listing sold" as the one live
 * switch and HIDES the five switches whose paths do not exist yet, PRESERVING
 * stored preferences — hiding never writes, never resets a default.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { PREF_TOGGLES, visibleToggles, WIRED_PREF_KEYS } from '@/src/lib/settings/notificationPrefs';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('which notification switches are shown', () => {
  it('only the wired switch is visible; the five unwired definitions are kept, not deleted', () => {
    expect(WIRED_PREF_KEYS).toEqual(['notify_listing_sold']);
    expect(PREF_TOGGLES.map((t) => t.key)).toEqual([
      'notify_outbid', 'notify_auction_ending', 'notify_auction_won', 'notify_auction_lost', 'notify_reservation_exp', 'notify_listing_sold',
    ]);
    const shown = visibleToggles(PREF_TOGGLES, WIRED_PREF_KEYS);
    expect(shown.map((t) => t.key)).toEqual(['notify_listing_sold']);
    expect(shown[0].label).toBe('Listing sold');
  });
});

describe('Settings › Notifications (source contract)', () => {
  const n = stripComments(read('app/settings/notifications.tsx'));
  it('renders only the visible toggles and still writes the one live switch by its column name', () => {
    expect(n).toContain('visibleToggles(PREF_TOGGLES, WIRED_PREF_KEYS)');
    expect(n).toContain('const TOGGLES = visibleToggles(PREF_TOGGLES, WIRED_PREF_KEYS);');
    expect(n).not.toMatch(/PREF_TOGGLES\.map\(/);   // the full list is never rendered directly
    expect(n).toContain(".from('notification_preferences')");
    expect(n).toContain('.update({ [key]: newValue })');
  });
  it('hiding never writes: exactly one write site (the toggle), no upsert/insert/delete, no default reset', () => {
    expect((n.match(/\.update\(/g) ?? []).length).toBe(1);
    expect(n).not.toMatch(/\.upsert\(|\.insert\(|\.delete\(/);
    expect(n).not.toMatch(/notify_(outbid|auction_ending|auction_won|auction_lost|reservation_exp):\s*(true|false)/);
  });
});
