/**
 * CFT-603 / item 44 — return to the intended screen after sign-in (native, slice 1): the store and its allowlist.
 *
 * Build 29 sends every sign-in to Home (rootRoute.ts), so a person who opened a listing link while signed out,
 * or whose session expired on a screen ("Your session expired. Sign in to pick up where you left off."), lost
 * it. The store remembers ONE destination, in process memory only, and hands it back once. These are the rules
 * E required before it may route anyone:
 *   - only internal, allowlisted screens — no scheme, no host, no '//' or encoded or backslash variant, no auth,
 *     checkout, payout, settings or reset-password route, never '/' or a tab; query and fragment dropped whole;
 *   - it expires (10 minutes) and is single-use;
 *   - private screens (transfer send/receive, my-listings) come back only for the same user who was signed in
 *     on them; public screens (listing, bid, profile) captured signed out come back for whoever signs in;
 *   - it is a screen, never an action: no amount, no confirm flag, nothing that could re-run a bid or checkout.
 * Pure module, no mocks. Not device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { beforeEach, describe, expect, it } from 'vitest';

import {
  RETURN_TO_ROUTES,
  RETURN_TO_TTL_MS,
  captureReturnTo,
  classifyReturnPath,
  consumeReturnTo,
  peekReturnTo,
  resetReturnToForTests,
  settleReturnToOnRoute,
  shouldCaptureOnEntry,
  userIdOfPhase,
} from '../src/lib/auth/returnTo';
import { consumeSessionEnd, markSessionEnd, peekSessionEnd } from '../src/lib/auth/sessionEnd';

const T0 = Date.parse('2026-10-21T12:00:00Z');
const LISTING = '/listing/4a1d2c3b-0000-4000-8000-00000000abcd';
const TRANSFER = '/transfer/send/9f8e7d6c-0000-4000-8000-000000001234';

beforeEach(() => { resetReturnToForTests(); consumeSessionEnd(); });

describe('the allowlist — only internal, named screens', () => {
  it('RT1: exactly six screens can be restored; three public, three for the same user only', () => {
    expect(RETURN_TO_ROUTES).toEqual([
      { route: 'listing/[id]', scope: 'public' },
      { route: 'bid/[id]', scope: 'public' },
      { route: 'profile/[id]', scope: 'public' },
      { route: 'transfer/send/[id]', scope: 'same_user' },
      { route: 'transfer/receive/[id]', scope: 'same_user' },
      { route: 'my-listings', scope: 'same_user' },
    ]);
  });

  it('RT2: accepts each allowlisted screen, exactly as Expo Router reports its pathname', () => {
    expect(classifyReturnPath(LISTING)).toEqual({ path: LISTING, scope: 'public' });
    expect(classifyReturnPath('/bid/abc-123')).toEqual({ path: '/bid/abc-123', scope: 'public' });
    expect(classifyReturnPath('/profile/u_1')).toEqual({ path: '/profile/u_1', scope: 'public' });
    expect(classifyReturnPath(TRANSFER)).toEqual({ path: TRANSFER, scope: 'same_user' });
    expect(classifyReturnPath('/transfer/receive/t1')).toEqual({ path: '/transfer/receive/t1', scope: 'same_user' });
    expect(classifyReturnPath('/my-listings')).toEqual({ path: '/my-listings', scope: 'same_user' });
  });

  it('RT3: rejects every external URL and every scheme', () => {
    for (const raw of [
      'https://evil.example/listing/1', 'http://evil.example/listing/1', 'HTTPS://evil.example/listing/1',
      'snatchit://listing/1', 'snatchit:///listing/1', 'exp://127.0.0.1:8081/--/listing/1', 'javascript:alert(1)',
      'mailto:a@b.c', 'data:text/html,<script>', 'file:///etc/passwd', 'listing/1', 'evil.example/listing/1',
    ]) expect({ raw, got: classifyReturnPath(raw) }).toEqual({ raw, got: null });
  });

  it("RT4: rejects protocol-relative '//', its encoded forms, backslashes and dot segments", () => {
    for (const raw of [
      '//evil.example/listing/1', '///listing/1', '//listing/1', '/%2F%2Fevil.example', '/%2f%2fevil.example',
      '%2F%2Fevil.example', '/%5Cevil.example', '/listing/%2E%2E', '/listing/1%2F..%2Fcheckout', '/listing/%61',
      '\\\\evil.example', '/\\evil.example', '\\/evil.example', '/listing\\1', '/listing/1\\',
      '/listing/..', '/listing/1/..', '/listing/../checkout/1', '/./listing/1', '/listing/./1',
    ]) expect({ raw, got: classifyReturnPath(raw) }).toEqual({ raw, got: null });
  });

  it('RT5: rejects auth, reset-password, checkout, payout and settings routes', () => {
    for (const raw of [
      '/login', '/(auth)/login', '/signup', '/(auth)/signup', '/reset-password', '/(auth)/reset-password',
      '/checkout', '/checkout/1', '/checkout/index', '/payout-return', '/payout-refresh',
      '/settings', '/settings/index', '/settings/payout-setup', '/settings/verify-phone', '/settings/edit-profile',
    ]) expect({ raw, got: classifyReturnPath(raw) }).toEqual({ raw, got: null });
  });

  it("RT6: never '/', never a tab, never the dev harness, an edit or a report screen, never a malformed id", () => {
    for (const raw of [
      '/', '', '/(tabs)', '/(tabs)/home', '/home', '/index', '/explore', '/bids', '/tickets', '/profile', '/create',
      '/_dev/v3-home', '/listing/edit/1', '/report/listing/1', '/listing', '/listing/', '/listing/1/', '/transfer/send',
      '/transfer/1', '/my-listings/1', '/LISTING/1', ' /listing/1', '/listing/1 ', '/listing/1\n', '/listing/\u0000',
      '/listing/１', '/listing/a@b', '/listing/a:b', `/listing/${'a'.repeat(65)}`,
    ]) expect({ raw, got: classifyReturnPath(raw) }).toEqual({ raw, got: null });
  });

  it('RT7: non-strings are rejected', () => {
    for (const raw of [null, undefined, 42, {}, [LISTING], true]) expect(classifyReturnPath(raw)).toBeNull();
  });

  it('RT8: query and fragment are dropped whole — codes, tokens and action parameters never ride along', () => {
    expect(classifyReturnPath(`${LISTING}?code=abc&access_token=t&refresh_token=r&type=recovery`)?.path).toBe(LISTING);
    expect(classifyReturnPath(`${LISTING}#access_token=t&refresh_token=r`)?.path).toBe(LISTING);
    expect(classifyReturnPath('/bid/abc?amount=500&confirm=1&autoSubmit=true')?.path).toBe('/bid/abc');
    expect(classifyReturnPath('/my-listings?filter=sold&password=x&otp=123456')?.path).toBe('/my-listings');
    // the cut happens before validation, so a query cannot smuggle a host into the path
    expect(classifyReturnPath('//evil.example?/listing/1')).toBeNull();
    expect(classifyReturnPath('?/listing/1')).toBeNull();
  });
});

describe('the store — expires, single-use, same user for private screens', () => {
  it('RT9: the TTL is 10 minutes; a destination is usable just before it and gone at it', () => {
    expect(RETURN_TO_TTL_MS).toBe(10 * 60_000);
    expect(captureReturnTo(LISTING, null, T0)).toBe(true);
    expect(peekReturnTo('u1', T0 + RETURN_TO_TTL_MS - 1)).toBe(LISTING);
    expect(peekReturnTo('u1', T0 + RETURN_TO_TTL_MS)).toBeNull();
    expect(consumeReturnTo('u1', T0 + RETURN_TO_TTL_MS)).toBeNull();
    expect(peekReturnTo('u1', T0 + 1)).toBeNull(); // the expired entry was discarded, not kept for later
  });

  it('RT10: a clock that moved backwards is treated as expired', () => {
    captureReturnTo(LISTING, null, T0);
    expect(peekReturnTo('u1', T0 - 1)).toBeNull();
  });

  it('RT11: single-use — consumed once, then nothing', () => {
    captureReturnTo(LISTING, null, T0);
    expect(consumeReturnTo('u1', T0 + 1_000)).toBe(LISTING);
    expect(consumeReturnTo('u1', T0 + 2_000)).toBeNull();
    expect(peekReturnTo('u1', T0 + 2_000)).toBeNull();
  });

  it('RT12: peek does not consume; nobody signed in means nothing to restore', () => {
    captureReturnTo(LISTING, null, T0);
    expect(peekReturnTo('u1', T0 + 1)).toBe(LISTING);
    expect(peekReturnTo('u1', T0 + 2)).toBe(LISTING);
    expect(peekReturnTo(null, T0 + 2)).toBeNull();
    expect(peekReturnTo('', T0 + 2)).toBeNull();
  });

  it('RT13: a public screen captured while signed out comes back for whoever signs in', () => {
    captureReturnTo(LISTING, null, T0);
    expect(peekReturnTo('someone', T0 + 1)).toBe(LISTING);
    expect(peekReturnTo('someone-else', T0 + 1)).toBe(LISTING);
  });

  it('RT14: a private screen cannot be captured signed out — there is no one to give it back to', () => {
    expect(captureReturnTo(TRANSFER, null, T0)).toBe(false);
    expect(captureReturnTo('/my-listings', null, T0)).toBe(false);
    expect(peekReturnTo('u1', T0 + 1)).toBeNull();
  });

  it('RT15: a private screen captured for a user comes back for that user only; another user gets nothing and clears it', () => {
    expect(captureReturnTo(TRANSFER, 'user-a', T0)).toBe(true);
    expect(peekReturnTo('user-b', T0 + 1)).toBeNull();
    expect(peekReturnTo('user-a', T0 + 1)).toBe(TRANSFER);
    expect(consumeReturnTo('user-b', T0 + 1)).toBeNull();       // account change: the other account's screen is gone
    expect(consumeReturnTo('user-a', T0 + 2)).toBeNull();
  });

  it('RT16: a screen captured from a signed-in session is bound to that user, public screens included (default)', () => {
    captureReturnTo(LISTING, 'user-a', T0);
    expect(peekReturnTo('user-b', T0 + 1)).toBeNull();
    expect(peekReturnTo('user-a', T0 + 1)).toBe(LISTING);
  });

  it('RT17: a rejected capture stores nothing and leaves an earlier destination as it was', () => {
    expect(captureReturnTo('/checkout/1', 'user-a', T0)).toBe(false);
    expect(peekReturnTo('user-a', T0 + 1)).toBeNull();
    captureReturnTo(LISTING, null, T0);
    expect(captureReturnTo('/login', null, T0 + 5)).toBe(false);
    expect(peekReturnTo('u1', T0 + 6)).toBe(LISTING);
  });

  it('RT18: settings are never restored, not even for the same user (default)', () => {
    expect(captureReturnTo('/settings', 'user-a', T0)).toBe(false);
    expect(captureReturnTo('/settings/payout-setup', 'user-a', T0)).toBe(false);
    expect(peekReturnTo('user-a', T0 + 1)).toBeNull();
  });

  it('RT19: the destination is a screen, never an action — only the bare path is ever handed back', () => {
    captureReturnTo('/bid/abc?amount=900&confirm=1', null, T0);
    const back = consumeReturnTo('u1', T0 + 1);
    expect(back).toBe('/bid/abc');
    expect(typeof back).toBe('string');
  });
});

describe('the root layout policy — what happens to the destination when the root navigates', () => {
  const settle = (over: Partial<Parameters<typeof settleReturnToOnRoute>[0]>) =>
    settleReturnToOnRoute({ phase: 'signed_out', lastRoutedPhase: null, pathname: '/', sessionEnd: null, now: T0, ...over });

  it('RT20: the first signed-out route captures an allowlisted public screen (a cold-start link)', () => {
    expect(settle({ pathname: LISTING })).toBe('captured');
    expect(peekReturnTo('u1', T0 + 1)).toBe(LISTING);
  });

  it("RT21: the first signed-out route on '/', a tab, reset-password or a private screen captures nothing", () => {
    for (const pathname of ['/', '/home', '/reset-password', TRANSFER, '/checkout/1', null]) {
      expect(settle({ pathname })).toBe('kept');
    }
    expect(peekReturnTo('u1', T0 + 1)).toBeNull();
  });

  it('RT22: an expiry captures the screen for the user whose session ended; that user gets it back, another does not', () => {
    expect(settle({ lastRoutedPhase: 'signed_in:user-a', pathname: TRANSFER, sessionEnd: 'expired' })).toBe('captured');
    expect(peekReturnTo('user-a', T0 + 1)).toBe(TRANSFER);
    expect(peekReturnTo('user-b', T0 + 1)).toBeNull();
    // the next sign-in, by A: the destination is consumed by that navigation
    expect(settle({ phase: 'signed_in:user-a', lastRoutedPhase: 'signed_out', now: T0 + 1 })).toBe('consumed');
    expect(peekReturnTo('user-a', T0 + 2)).toBeNull();
  });

  it('RT23: a sign-out that is not an expiry keeps nothing — deliberate, password changed, credential change, unknown', () => {
    for (const sessionEnd of ['user', 'password_changed', 'credential_change', null] as const) {
      captureReturnTo(LISTING, null, T0);
      expect(settle({ lastRoutedPhase: 'signed_in:user-a', pathname: LISTING, sessionEnd })).toBe('cleared');
      expect(peekReturnTo('user-a', T0 + 1)).toBeNull();
    }
  });

  it('RT24: an expiry on a screen that is not allowlisted clears whatever was there', () => {
    captureReturnTo(LISTING, null, T0);
    expect(settle({ lastRoutedPhase: 'signed_in:user-a', pathname: '/settings', sessionEnd: 'expired' })).toBe('cleared');
    expect(peekReturnTo('user-a', T0 + 1)).toBeNull();
  });

  it('RT25: every navigation into the signed-in area consumes the destination, used or not (single-use)', () => {
    captureReturnTo(TRANSFER, 'user-a', T0);
    expect(settle({ phase: 'signed_in:user-b', lastRoutedPhase: 'signed_out' })).toBe('consumed');
    expect(peekReturnTo('user-a', T0 + 1)).toBeNull();
  });

  it('RT26: signed out to signed out (a signed-out tab sent to login) leaves the destination alone', () => {
    captureReturnTo(LISTING, null, T0);
    expect(settle({ lastRoutedPhase: 'signed_out', pathname: '/home' })).toBe('kept');
    expect(peekReturnTo('u1', T0 + 1)).toBe(LISTING);
  });

  it('RT27: signed-out entry capture only once the root has routed as signed out, with no hold up', () => {
    expect(shouldCaptureOnEntry({ phase: 'signed_out', routedPhase: 'signed_out', held: false })).toBe(true);
    expect(shouldCaptureOnEntry({ phase: 'signed_out', routedPhase: 'signed_out', held: true })).toBe(false);
    expect(shouldCaptureOnEntry({ phase: 'signed_out', routedPhase: null, held: false })).toBe(false);
    expect(shouldCaptureOnEntry({ phase: 'signed_out', routedPhase: 'signed_in:u1', held: false })).toBe(false);
    expect(shouldCaptureOnEntry({ phase: 'signed_in:u1', routedPhase: 'signed_in:u1', held: false })).toBe(false);
  });

  it('RT28: the user id is read from the phase, never from anything else', () => {
    expect(userIdOfPhase('signed_in:abc')).toBe('abc');
    expect(userIdOfPhase('signed_out')).toBeNull();
    expect(userIdOfPhase(null)).toBeNull();
  });
});

describe('sessionEnd — the layout reads the reason without taking it from the login screen', () => {
  it('RT29: peek returns the mark and leaves it for the login notice', () => {
    markSessionEnd('expired');
    expect(peekSessionEnd()).toBe('expired');
    expect(peekSessionEnd()).toBe('expired');
    expect(consumeSessionEnd()).toBe('expired');
    expect(peekSessionEnd()).toBeNull();
  });
});

describe('privacy and purity (source pins)', () => {
  const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const code = strip(readFileSync(resolve(__dirname, '..', 'src/lib/auth/returnTo.ts'), 'utf8'));

  it('RT30: process memory only — nothing is persisted, so nothing outlives the app or reaches another install', () => {
    expect(code).not.toMatch(/AsyncStorage|SecureStore|localStorage|MMKV|setItem\(/);
  });

  it('RT31: the store routes nothing and calls nothing — no navigation, no network, no bid, checkout or payment code', () => {
    expect(code).not.toMatch(/expo-router|router\.|supabase|\.rpc\(|fetch\(|payments|placeBid|checkout\(|reserve/i);
    // its only imports are types
    const imports = code.match(/^import .*$/gm) ?? [];
    for (const line of imports) expect(line).toMatch(/^import type /);
  });
});

describe('reserved ids (C-nit)', () => {
  it('RT32: "/listing/edit" is the edit route\'s folder, not a listing whose id is "edit" — never remembered', () => {
    expect(classifyReturnPath('/listing/edit')).toBeNull();
    expect(captureReturnTo('/listing/edit', null)).toBe(false);
    // An ordinary listing id still qualifies, and "edit" is only reserved where a static sibling exists.
    expect(classifyReturnPath('/listing/4a1d2c3b-0000-4000-8000-00000000abcd')?.scope).toBe('public');
    expect(classifyReturnPath('/profile/edit')?.scope).toBe('public');
  });
});
