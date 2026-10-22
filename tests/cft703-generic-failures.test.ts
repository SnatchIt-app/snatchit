/**
 * CFT-703 (P1, backlog): no raw server text in a dialog, for the failures where the server has no
 * sentence for the person. Block, unblock, the profile photo save and the delivery-details save
 * showed `error.message` verbatim (an RLS or network string, e.g. "new row violates row-level
 * security policy"). They now show calm copy held in one module. The raw text goes to the log.
 *
 * Out of scope here, with A: sites where the server's text can carry a real reason (listing delete,
 * cancel and edit; mark-as-sent; confirm-and-release). Those need A's refusal catalogue, like
 * serverRefusal.ts.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

import { ACTION_FAILED_COPY } from '@/src/lib/ui/errorCopy';

const code = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const SITES: Array<[string, string, RegExp]> = [
  ['app/settings/blocked-users.tsx', 'unblock', /Alert\.alert\('Could not unblock', error\.message\)/],
  ['app/profile/[id].tsx', 'block', /Alert\.alert\('Could not block', error\.message\)/],
  ['app/profile/[id].tsx', 'unblock', /Alert\.alert\('Could not unblock', error\.message\)/],
  ['src/screens/ListingDetailScreen.tsx', 'block', /Alert\.alert\('Could not block', error\.message\)/],
  ['src/lib/moderation/blockFlow.ts', 'block', /Alert\.alert\('Could not block', error\.message\)/],
  ['app/settings/edit-profile.tsx', 'photo', /Alert\.alert\('Save failed', dbError\.message\)/],
  ['app/(tabs)/profile.tsx', 'photo', /Alert\.alert\('Save failed', dbError\.message\)/],
  ['app/transfer/receive/[id].tsx', 'delivery', /Alert\.alert\('Error', rpcErr\.message\)/],
];

describe('CFT-703: generic failures say calm words, not server text', () => {
  it('G1: the copy is held in one place', () => {
    expect(ACTION_FAILED_COPY).toEqual({
      block: { title: 'Could not block', body: "We couldn't block this account. Please try again." },
      unblock: { title: 'Could not unblock', body: "We couldn't unblock this account. Please try again." },
      photo: { title: 'Save failed', body: "Your new photo wasn't saved. Please try again." },
      delivery: { title: "Couldn't save your details", body: "Your delivery details weren't saved. Please try again." },
    });
  });

  it.each(SITES)('G2: %s (%s) shows the copy, not the server text', (file, key, raw) => {
    const src = code(file);
    expect(src, 'raw message still shown').not.toMatch(raw);
    expect(src).toContain(`ACTION_FAILED_COPY.${key}.title, ACTION_FAILED_COPY.${key}.body`);
  });

  it('G3: the web path of the photo save no longer alerts the raw text either', () => {
    expect(code('app/settings/edit-profile.tsx')).not.toMatch(/window\.alert\(dbError\.message\)/);
  });
});
