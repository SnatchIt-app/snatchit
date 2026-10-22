/**
 * A signed-out viewer of a public profile isn't offered Report or Block (build-29 known limitation 2,
 * CANDIDATE_MANIFEST:389). Both buttons were shown on `!isSelf` alone, and both then refused with
 * "Sign in required": two controls offered only to fail. They now need a signed-in viewer who isn't
 * the seller. The handlers keep their own refusals, so a stale render still can't write anything.
 * Source contract with a witness. Not a device result.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';

const src = readFileSync('app/profile/[id].tsx', 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const gate = /\{user \&\& !isSelf \? \(\s*<View style=\{s\.actions\}>/;

describe('public profile safety actions', () => {
  it('PS1: Report and Block render only for a signed-in viewer who is not the seller', () => {
    expect(src).toMatch(gate);
    // Witness: build 29's gate fails the same check.
    expect(src.replace('{user && !isSelf ? (', '{!isSelf ? (')).not.toMatch(gate);
  });

  it('PS2: the handlers still refuse a signed-out press on their own (defence in depth)', () => {
    expect(src).toContain("if (!user?.id) { Alert.alert('Sign in required', 'You need to be signed in to block users.'); return; }");
    expect(readFileSync('app/report/[type]/[id].tsx', 'utf8')).toContain("if (!user) { Alert.alert('Sign in required'");
  });
});
