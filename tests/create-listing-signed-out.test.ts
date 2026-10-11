/**
 * tests/create-listing-signed-out.test.ts — tapping Publish signed out must not do nothing at all.
 *
 * E's finding (2026-10-05): `CreateListingScreen` line 511 was
 *
 *     if (!isValid || !user) return;
 *
 * — two unrelated conditions behind one silent return. `setSubmitted(true)` runs just before it,
 * so the invalid-form half is not silent: the fields show their own errors, which is the intended
 * feedback. The other half has nothing to say. A seller whose form is complete and whose session
 * has gone taps Publish and the screen does not move, does not spin and does not speak.
 *
 * INTENDED BEHAVIOUR, taken from the app rather than invented. Four screens already refuse an
 * action to a signed-out viewer, with one wording — 'Sign in required' + 'You need to be signed in
 * to …' (ListingDetailScreen buy and block, the public profile, the report screen). The order is
 * the app's too: ListingDetailScreen checks the session FIRST in handleBuyNow, before anything
 * about the purchase, because no amount of correcting the form helps a seller who is signed out.
 * CP6 pins that this suite is quoting the app and not a new invention.
 *
 * No confirmation dialog is added and nothing about who may sell changes: the phone-verification,
 * payout and risk gates below the precondition are untouched, and CP2 pins that a signed-in seller
 * with a valid form is still handed to them.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import { PUBLISH_SIGNED_OUT, publishBlock } from '@/src/lib/sell/sellState';
import { REPO_ROOT } from './helpers/nav-stack-harness';

const read = (rel: string) => readFileSync(join(REPO_ROOT, rel), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

describe('CP · what stops a publish before the gates run', () => {
  it('CP1: the form is complete and the seller is signed out — they are told, not ignored', () => {
    const block = publishBlock({ valid: true, signedIn: false });
    expect(block).toEqual({ kind: 'signed-out', title: PUBLISH_SIGNED_OUT.title, body: PUBLISH_SIGNED_OUT.body });
    // A refusal with nothing to say is the defect, so the sentence has to exist and be a sentence.
    expect(PUBLISH_SIGNED_OUT.body).toMatch(/^You need to be signed in to .+\.$/);
  });

  it('CP2: signed in with a valid form — nothing blocks, the gates still decide', () => {
    expect(publishBlock({ valid: true, signedIn: true })).toBeNull();
  });

  it('CP3: an incomplete form is the fields’ business, not a dialog', () => {
    expect(publishBlock({ valid: false, signedIn: true })).toEqual({ kind: 'invalid' });
  });

  it('CP4: signed out AND incomplete — the session is answered first, as handleBuyNow does', () => {
    expect(publishBlock({ valid: false, signedIn: false })!.kind).toBe('signed-out');
  });
});

describe('CP5 · the screen routes through it, and says the sentence on both platforms', () => {
  const screen = () => stripComments(read('src/screens/CreateListingScreen.tsx'));

  it('CP5a: the silent combined return is gone', () => {
    expect(screen()).not.toMatch(/if \(!isValid \|\| !user\) return;/);
  });

  it('CP5b: the precondition is the shared one, and the seller hears about it', () => {
    const s = screen();
    expect(s).toContain('publishBlock');
    // The sentence is shown from the block, so the screen holds no second copy of it to drift.
    expect(s).not.toContain(PUBLISH_SIGNED_OUT.title);
    expect(s).not.toContain(PUBLISH_SIGNED_OUT.body);
    // This file carries its own web/native split for every message it shows; a refusal that only
    // speaks on one of them is still silent on the other, and the harness renders on web.
    const branch = s.slice(s.indexOf('= publishBlock'), s.indexOf('Content moderation gate'));
    expect(branch).toContain('window.alert');
    expect(branch).toContain('Alert.alert');
  });
});

describe('CP6 · the copy is the app’s, not a new one', () => {
  it('CP6a: the title is the one the other signed-out refusals already use', () => {
    for (const rel of ['src/screens/ListingDetailScreen.tsx', 'app/profile/[id].tsx', 'app/report/[type]/[id].tsx']) {
      expect(read(rel), rel).toContain(`'${PUBLISH_SIGNED_OUT.title}'`);
    }
  });

  it('CP6b: and the sentence is built the same way they build theirs', () => {
    // 'You need to be signed in to block users.' / '… to submit a report.' — the same stem.
    const stem = 'You need to be signed in to ';
    expect(PUBLISH_SIGNED_OUT.body.startsWith(stem)).toBe(true);
    expect(read('app/report/[type]/[id].tsx')).toContain(stem);
  });
});
