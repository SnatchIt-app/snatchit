/**
 * connect-onboarding — redirect allowlist unit tests.
 *
 * Every function under test comes from `supabase/functions/connect-onboarding/redirect.ts`, an import-free pure
 * module that `index.ts` imports FROM (the door-session/pure.ts pattern). `index.ts` itself is not imported here.
 *
 * The contract: Stripe account-link return/refresh targets must be https, on an allowlisted host, and carry no
 * state (Ruling G §3). Production's allowlist is exactly the two snatchitapp.com hosts. One extra EXACT hostname may
 * be added per environment from VENUE_CONNECT_ALLOWED_HOST (the sandbox venue host); a malformed value adds nothing.
 */
import { describe, expect, it } from 'vitest';
import { BASE_REDIRECT_HOSTS, isSafeRedirect, redirectHosts } from '../supabase/functions/connect-onboarding/redirect';

const SANDBOX = 'snatchit-venue-git-sandbox-team.vercel.app';

describe('redirectHosts — production stays exactly the two existing hosts', () => {
  it('R1 unset, empty or whitespace adds nothing', () => {
    for (const v of [undefined, null, '', '   ']) {
      expect([...redirectHosts(v)].sort()).toEqual(['snatchitapp.com', 'www.snatchitapp.com']);
    }
    expect([...BASE_REDIRECT_HOSTS]).toEqual(['snatchitapp.com', 'www.snatchitapp.com']);
  });
  it('R2 one exact bare hostname is added (trimmed, lower-cased)', () => {
    expect(redirectHosts(SANDBOX).has(SANDBOX)).toBe(true);
    expect(redirectHosts(`  ${SANDBOX.toUpperCase()}  `).has(SANDBOX)).toBe(true);
    expect(redirectHosts(SANDBOX).size).toBe(3);
  });
  it('R3 anything that is not a bare hostname adds nothing (no scheme, port, path, list, wildcard, single label)', () => {
    for (const bad of [`https://${SANDBOX}`, `${SANDBOX}:443`, `${SANDBOX}/connect`, `${SANDBOX},evil.example`,
                       `*.vercel.app`, `.vercel.app`, `${SANDBOX}.`, 'localhost', 'a..b.com', '-x.example.com', 'x-.example.com',
                       `${SANDBOX} evil.example`, 'evil.example?x=1']) {
      expect(redirectHosts(bad).size, bad).toBe(2);
    }
  });
});

describe('isSafeRedirect — https, exact allowlisted host, no state', () => {
  const prod = redirectHosts(undefined);
  const sbx = redirectHosts(SANDBOX);
  it('S1 production targets are accepted; the sandbox host is NOT accepted in production', () => {
    expect(isSafeRedirect('https://snatchitapp.com/dashboard/payments/connect/return', prod)).toBe(true);
    expect(isSafeRedirect(`https://${SANDBOX}/connect/return`, prod)).toBe(false);
  });
  it('S2 the sandbox host is accepted only where it is configured', () => {
    expect(isSafeRedirect(`https://${SANDBOX}/connect/return`, sbx)).toBe(true);
    expect(isSafeRedirect(`https://${SANDBOX}/connect/refresh`, sbx)).toBe(true);
  });
  it('S3 http, a query, a fragment or a malformed URL are refused', () => {
    expect(isSafeRedirect(`http://${SANDBOX}/connect/return`, sbx)).toBe(false);
    expect(isSafeRedirect(`https://${SANDBOX}/connect/return?org=x`, sbx)).toBe(false);
    expect(isSafeRedirect(`https://${SANDBOX}/connect/return#x`, sbx)).toBe(false);
    expect(isSafeRedirect('not a url', sbx)).toBe(false);
  });
  it('S4 exact host only: a subdomain, a parent domain or a look-alike suffix is refused', () => {
    expect(isSafeRedirect(`https://evil.${SANDBOX}/connect/return`, sbx)).toBe(false);
    expect(isSafeRedirect('https://vercel.app/connect/return', sbx)).toBe(false);
    expect(isSafeRedirect(`https://x${SANDBOX}/connect/return`, sbx)).toBe(false);
    expect(isSafeRedirect('https://evil.snatchitapp.com/x', prod)).toBe(false);
  });
});
