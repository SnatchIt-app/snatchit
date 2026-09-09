/**
 * tests/env-guard.test.ts — the environment pairing guard (src/config/envGuard.ts).
 *
 * These are the pairings that must never produce a runnable build. The guard is
 * a pure function of three compile-time strings, so it is fully testable here.
 */
import { describe, expect, it } from 'vitest';
import { evaluateEnv } from '../src/config/envGuard';

const SANDBOX_URL = 'https://ofaidukbieeekqaboscm.supabase.co';
const PROD_URL = 'https://hqycwntpfoztoinemqns.supabase.co';
const SANDBOX_PK = 'pk_test_51T6Fb1GlD5aqtxIwXXXXXXXXXXXXXXXXXXXX';
const LIVE_PK = 'pk_live_51T6FarGdOzCmGbHwXXXXXXXXXXXXXXXXXXXX';
const LIVE_ACCT_TEST_PK = 'pk_test_51T6FarGdOzCmGbHwXXXXXXXXXXXXXXXXXXXX';

describe('env guard — accepted pairings', () => {
  it('sandbox app env + sandbox project + sandbox test key', () => {
    expect(evaluateEnv({ appEnv: 'sandbox', supabaseUrl: SANDBOX_URL, publishableKey: SANDBOX_PK }).failure).toBeNull();
  });
  it('production app env + production project + live key', () => {
    expect(evaluateEnv({ appEnv: 'production', supabaseUrl: PROD_URL, publishableKey: LIVE_PK }).failure).toBeNull();
  });
});

describe('env guard — refused pairings', () => {
  const cases: Array<[string, Parameters<typeof evaluateEnv>[0], string]> = [
    ['live key against the sandbox database', { appEnv: 'sandbox', supabaseUrl: SANDBOX_URL, publishableKey: LIVE_PK }, 'F3'],
    ['test key against production (today\'s development/preview defect)', { appEnv: 'development', supabaseUrl: PROD_URL, publishableKey: LIVE_ACCT_TEST_PK }, 'F4'],
    ['right mode, wrong Stripe account on sandbox', { appEnv: 'sandbox', supabaseUrl: SANDBOX_URL, publishableKey: LIVE_ACCT_TEST_PK }, 'F5'],
    ['sandbox label pointed at production', { appEnv: 'sandbox', supabaseUrl: PROD_URL, publishableKey: LIVE_PK }, 'F1'],
    ['production label with a test key', { appEnv: 'production', supabaseUrl: PROD_URL, publishableKey: LIVE_ACCT_TEST_PK }, 'F4'],
    ['unresolved environment', { appEnv: 'sandbox', supabaseUrl: '', publishableKey: '' }, 'F6'],
    ['unknown Supabase host', { appEnv: 'sandbox', supabaseUrl: 'https://someone-else.supabase.co', publishableKey: SANDBOX_PK }, 'F7'],
    ['return URL no longer matches the checkout literal', { appEnv: 'sandbox', supabaseUrl: SANDBOX_URL, publishableKey: SANDBOX_PK, returnUrl: 'snatchit://elsewhere' }, 'F8'],
  ];
  for (const [name, input, code] of cases) {
    it(`refuses: ${name} (${code})`, () => {
      const v = evaluateEnv(input);
      expect(v.failure).toBeTruthy();
      expect(v.failure).toContain(code);
    });
  }
});
