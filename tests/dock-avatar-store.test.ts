/**
 * V3 "You" item — the dock-avatar store (owner approval 2026-09-22; acceptance 10/11 groundwork).
 *
 * The rule under test: the dock renders a photo ONLY for the CURRENT signed-in user, from state the
 * screens already hold — the store itself never fetches, and a previous account's entry answers
 * null the moment the account changes, whether or not anything cleared it.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

process.env.EXPO_PUBLIC_SUPABASE_URL = 'https://example.supabase.co';
vi.hoisted(() => { (globalThis as Record<string, unknown>).__DEV__ = false; });



import {
  _dockAvatarState,
  clearDockAvatar,
  dockAvatarPathFor,
  setDockAvatar,
  subscribeDockAvatar,
} from '@/src/lib/nav/dockAvatar';

beforeEach(() => clearDockAvatar());

describe('the render-time owner guard', () => {
  it('A1: answers the stored path for the CURRENT user only', () => {
    setDockAvatar('user-1', 'user-1/avatar.jpg');
    expect(dockAvatarPathFor('user-1')).toBe('user-1/avatar.jpg');
  });

  it('A2: a previous account\'s photo NEVER answers after the account changes — even with no clear', () => {
    setDockAvatar('user-1', 'user-1/avatar.jpg');
    expect(dockAvatarPathFor('user-2')).toBeNull();   // switched account, stale entry still present
    expect(dockAvatarPathFor(null)).toBeNull();       // signed out
    expect(dockAvatarPathFor(undefined)).toBeNull();
  });

  it('A3: no photo (path null) and an empty store both answer null — the person icon', () => {
    expect(dockAvatarPathFor('user-1')).toBeNull();
    setDockAvatar('user-1', null);
    expect(dockAvatarPathFor('user-1')).toBeNull();
  });

  it('A4: sign-out clears the entry', () => {
    setDockAvatar('user-1', 'p.jpg');
    clearDockAvatar();
    expect(_dockAvatarState()).toBeNull();
  });
});

describe('publishing (replacement, removal) and subscription — no polling anywhere', () => {
  it('A5: replacement and removal notify subscribers; identical publishes do not', () => {
    const seen = vi.fn();
    const off = subscribeDockAvatar(seen);
    setDockAvatar('user-1', 'a.jpg');
    setDockAvatar('user-1', 'a.jpg');            // no change — no notification
    setDockAvatar('user-1', 'b.jpg');            // replacement
    setDockAvatar('user-1', null);               // removal → icon, works the day a removal flow ships
    expect(seen).toHaveBeenCalledTimes(3);
    off();
    setDockAvatar('user-1', 'c.jpg');
    expect(seen).toHaveBeenCalledTimes(3);
  });

  it('A6: the store module owns no timer and no fetch (source pin)', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('src/lib/nav/dockAvatar.ts', 'utf8');
    expect(src).not.toMatch(/setInterval|setTimeout|fetch\(|supabase|rpc\(/);
    // And no import at all beyond types: sign-out and Home sit behind this module.
    expect(src).not.toMatch(/^import /m);
  });

  it('A7: the publishers are the screens that already hold the value, and sign-out clears (source pins)', async () => {
    const { readFileSync } = await import('node:fs');
    for (const f of ['app/(tabs)/profile.tsx', 'app/settings/edit-profile.tsx', 'app/(tabs)/home.tsx']) {
      expect(readFileSync(f, 'utf8'), f).toContain('setDockAvatar(user.id,');
    }
    const signOut = readFileSync('src/lib/auth/signOut.ts', 'utf8');
    expect(signOut).toContain('deps.clearDockAvatar?.()');
    // Cleared only AFTER a successful sign-out — beside the registration clear, past the failure return.
    expect(signOut.indexOf('deps.clearDockAvatar?.()')).toBeGreaterThan(signOut.indexOf('signedOut: false'));
    // Home publishes only on a successful read: a failed read never blanks a correct photo.
    const home = readFileSync('app/(tabs)/home.tsx', 'utf8');
    expect(home).toContain('if (data) setDockAvatar(user.id,');
  });
});

