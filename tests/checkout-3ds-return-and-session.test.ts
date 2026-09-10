/**
 * tests/checkout-3ds-return-and-session.test.ts — the two D5 defects.
 *
 * D5 failed on a physical iPhone AFTER the charge had already succeeded: the
 * buyer authorised 3-D Secure, the page went white, and exiting showed
 * expo-router's unmatched/sitemap screen. Separately the session was lost.
 * Two independent causes, one shared trigger — the browser handoff.
 */

import { describe, expect, it } from 'vitest';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { isForeground } from '../src/lib/auth/appForeground';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const checkout = read('src/screens/checkout/CheckoutNative.tsx');
const shell = read('src/providers/NativeAppShell.native.tsx');
const autoRefresh = read('src/lib/auth/sessionAutoRefresh.ts');
const foreground = read('src/lib/auth/appForeground.ts');

describe('defect 1 — the 3-D Secure return URL must resolve to a real route', () => {
  it('the return URL carries the listing id', () => {
    expect(checkout).toContain('returnURL: `snatchit://checkout/${listingId}`');
    // the bare form is what stranded the buyer on the sitemap screen
    expect(stripComments(checkout)).not.toContain("returnURL: 'snatchit://checkout'");
  });

  it('every route the return URL can produce exists', () => {
    // snatchit://checkout/<id> -> app/checkout/[id].tsx
    expect(existsSync(resolve(root, 'app/checkout/[id].tsx'))).toBe(true);
    // snatchit://checkout      -> app/checkout/index.tsx (the floor)
    expect(existsSync(resolve(root, 'app/checkout/index.tsx'))).toBe(true);
  });

  it('the bare-link floor sends the person somewhere real and claims nothing', () => {
    const idx = read('app/checkout/index.tsx');
    expect(idx).toContain('<Redirect href="/(tabs)/home" />');
    // it must never assert an outcome it has not verified
    expect(stripComments(idx)).not.toMatch(/Purchase complete|success|paid|settled/i);
    expect(stripComments(idx)).not.toMatch(/supabase|rpc\(|payment/i);
  });

  it('the app scheme the return URL uses is the one the app registers', () => {
    const appJson = JSON.parse(read('app.json'));
    expect(appJson.expo.scheme).toBe('snatchit');
  });
});

describe('defect 2 — the refresh loop must follow the foreground', () => {
  it('the predicate module imports nothing, so the rule is directly testable', () => {
    expect(foreground).not.toMatch(/^import /m);
  });

  it('only the active state is foreground', () => {
    expect(isForeground('active')).toBe(true);
    expect(isForeground('background')).toBe(false);
    expect(isForeground('inactive')).toBe(false);   // the 3-D Secure handoff
    expect(isForeground('unknown' as never)).toBe(false);
  });

  it('refresh starts on foreground and stops when the app leaves', () => {
    expect(autoRefresh).toContain('supabase.auth.startAutoRefresh()');
    expect(autoRefresh).toContain('supabase.auth.stopAutoRefresh()');
    expect(autoRefresh).toContain("AppState.addEventListener('change'");
    // started eagerly, because the app is already foreground when this mounts
    const body = autoRefresh.slice(autoRefresh.indexOf('export function startSessionAutoRefresh'));
    expect(body.indexOf('startAutoRefresh()')).toBeLessThan(body.indexOf('addEventListener'));
  });

  it('it unsubscribes and stops the loop on teardown', () => {
    expect(autoRefresh).toContain('sub.remove()');
    const teardown = autoRefresh.slice(autoRefresh.lastIndexOf('return () => {'));
    expect(teardown).toContain('stopAutoRefresh()');
  });

  it('it is wired into the native shell only', () => {
    expect(shell).toContain('useEffect(() => startSessionAutoRefresh(), [])');
    expect(read('src/providers/NativeAppShell.web.tsx')).not.toContain('startSessionAutoRefresh');
  });

  it('authentication is not weakened: no session is created, extended or faked', () => {
    const code = stripComments(autoRefresh);
    expect(code).not.toMatch(/setSession|signInWith|admin\.|service_role|expires_at|persistSession/);
    // it may only start and stop the refresh the client was already configured for
    expect(code.match(/supabase\.auth\.\w+/g) ?? []).toEqual(
      expect.arrayContaining(['supabase.auth.startAutoRefresh', 'supabase.auth.stopAutoRefresh']),
    );
    expect(new Set(code.match(/supabase\.auth\.(\w+)/g) ?? []).size).toBe(2);
  });
});

describe('the payment path itself is unchanged', () => {
  it('only the return URL line moved in checkout', () => {
    for (const kept of [
      'presentPaymentSheet()',
      'setPaymentReady(true)',
      'paymentSheetErrorCopy(paymentError)',
      'createSingleFlight()',
    ]) expect(checkout).toContain(kept);
  });

  it('no success is shown without a verified payment', () => {
    // the settle path still gates on the provider, not on a deep link
    expect(stripComments(checkout)).not.toMatch(/returnURL[\s\S]{0,400}Purchase complete/);
  });
});
