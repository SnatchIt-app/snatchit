/**
 * tests/rc3-server-refusal.test.ts — RC3 S5: the four marketplace-safety refusals (migration 152).
 *
 * The server raises P0001 with the user-facing sentence as `message`, the stable code as `hint`
 * and, for PROHIBITED_CONTENT, the term as `details`. The client maps the HINT to the canonical
 * POLICY_WORDING K2 sentence it holds itself (so the wording is pinned here, not read off the wire)
 * and treats everything else as today's unknown error. Unknown ⇒ null ⇒ the caller keeps its copy.
 */
import { describe, expect, it } from 'vitest';

import { readServerRefusal, REFUSAL_COPY, PROHIBITED_CONTENT_FALLBACK } from '@/src/lib/moderation/serverRefusal';

const K2 = {
  BLOCKED_PARTY: "This listing isn't available to you.",
  LISTING_UNAVAILABLE: "This listing isn't available right now.",
  ACCOUNT_SUSPENDED: "Your account is suspended, so you can't bid, buy or create listings. Orders you already have aren't affected. Contact support@snatchitapp.com.",
} as const;

const pg = (hint: string | null | undefined, extra: Record<string, unknown> = {}) =>
  ({ code: 'P0001', message: 'server sentence', details: null, hint, ...extra });

describe('RC3 · readServerRefusal maps the stable hint, never the wire text', () => {
  it('SR1: the three fixed codes map to their K2 sentence whatever the message says', () => {
    for (const code of ['BLOCKED_PARTY', 'LISTING_UNAVAILABLE', 'ACCOUNT_SUSPENDED'] as const) {
      for (const message of ['server sentence', '', undefined, 'new row violates row-level security policy']) {
        const out = readServerRefusal(pg(code, { message }));
        expect(out?.code, `${code} / ${String(message)}`).toBe(code);
        expect(out?.body).toBe(K2[code]);
        expect(out?.body).toBe(REFUSAL_COPY[code].body);
        expect(out?.title).toBe(REFUSAL_COPY[code].title);
        expect(`${out?.title} ${out?.body}`).not.toContain('row-level');
      }
    }
  });

  it('SR2: PROHIBITED_CONTENT carries the term from `details` into the K2 sentence', () => {
    const out = readServerRefusal(pg('PROHIBITED_CONTENT', { details: 'resale ban', message: 'Listings can\'t mention "resale ban". Please revise your event name, venue, or restrictions and try again.' }));
    expect(out?.code).toBe('PROHIBITED_CONTENT');
    expect(out?.body).toBe('Listings can\'t mention "resale ban". Please revise your event name, venue, or restrictions and try again.');
  });

  it('SR3: without `details` the term is read from the quoted message; with neither, the pinned fallback — never the raw message', () => {
    const fromMessage = readServerRefusal(pg('PROHIBITED_CONTENT', { details: null, message: 'Listings can\'t mention "wristband". Please revise your event name, venue, or restrictions and try again.' }));
    expect(fromMessage?.body).toBe('Listings can\'t mention "wristband". Please revise your event name, venue, or restrictions and try again.');
    const bare = readServerRefusal(pg('PROHIBITED_CONTENT', { details: null, message: 'policy violation on relation "listings"' }));
    expect(bare?.code).toBe('PROHIBITED_CONTENT');
    expect(bare?.body).toBe(PROHIBITED_CONTENT_FALLBACK);
    expect(bare?.body).not.toContain('relation');
  });

  it('SR4: anything that is not one of the four hints is NOT a refusal — the caller keeps today\'s copy', () => {
    for (const bad of [
      pg(undefined), pg(null), pg(''), pg('SOMETHING_ELSE'), pg('blocked_party'), pg('BLOCKED_PARTY ') ,
      { message: 'This listing isn\'t available to you.' },      // the sentence alone is not a code
      { code: 'P0001', message: 'x' },
      new Error('BLOCKED_PARTY'), 'BLOCKED_PARTY', null, undefined, 42,
    ]) {
      expect(readServerRefusal(bad), JSON.stringify(bad)).toBeNull();
    }
  });

  it('SR5: BLOCKED_PARTY and ACCOUNT_SUSPENDED invite no retry, in flag or in words', () => {
    for (const code of ['BLOCKED_PARTY', 'ACCOUNT_SUSPENDED'] as const) {
      const out = readServerRefusal(pg(code))!;
      expect(out.invitesRetry).toBe(false);
      expect(`${out.title} ${out.body}`).not.toMatch(/try again/i);
    }
    // The content refusal's own sentence asks for a revision and a retry: that is the server's wording.
    expect(readServerRefusal(pg('PROHIBITED_CONTENT', { details: 'x' }))!.invitesRetry).toBe(true);
    expect(readServerRefusal(pg('LISTING_UNAVAILABLE'))!.invitesRetry).toBe(false);
  });

  it('SR6: the copy table is the exact K2 wording (POLICY_WORDING.md, 2026-10-13)', () => {
    expect(REFUSAL_COPY.BLOCKED_PARTY.body).toBe(K2.BLOCKED_PARTY);
    expect(REFUSAL_COPY.LISTING_UNAVAILABLE.body).toBe(K2.LISTING_UNAVAILABLE);
    expect(REFUSAL_COPY.ACCOUNT_SUSPENDED.body).toBe(K2.ACCOUNT_SUSPENDED);
  });
});
