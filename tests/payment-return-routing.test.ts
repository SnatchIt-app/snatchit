/**
 * c35-D6 (iOS) — a cold payment return lands on the ticket page, not Home.
 *
 * The primary checkout's 3-D Secure / bank-app return URL is snatchit://primary-checkout/<session>?tt&qty&attempt
 * (checkoutRoute.ts). When iOS killed the app while the buyer was in the bank app, the relaunch opens
 * [(tabs), primary-checkout/<session>], and the root's first signed-in route replaced the checkout with Home: a
 * buyer who may just have paid landed on Home with nothing said.
 *
 * rootRouteDecision gains one optional input, `pathname` — the route on screen, as expo-router's pathname. On the
 * first route of a signed-in phase, after every hold and after a remembered returnTo, a primary checkout with a
 * valid session id goes to that session's ticket page (read-only and server-authoritative: "Awaiting payment
 * confirmation" or the tickets). The checkout itself is never kept (it reserves on mount, and a link is untrusted),
 * and nothing after a '?' or '#' is ever read: Stripe may append payment_intent, its client secret or
 * redirect_status, and none of them may decide where the buyer goes. Pure function + source pins; the real root
 * layout runs the same sequence in return-to-root-layout.test.ts (LP1–LP4). Not device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { paymentReturnTicket, rootRouteDecision, type AuthPhase } from '../src/lib/auth/rootRoute';

const S = '5e55e55e-c0de-4abc-8def-00000000beef';
const CHECKOUT = `/primary-checkout/${S}`;
const TICKET = `/ticket/${S}`;
const LISTING = '/listing/4a1d2c3b-0000-4000-8000-00000000abcd';
const HOME = { navigate: true, to: '/(tabs)/home' };
const OUT = 'signed_out' as AuthPhase;
const USER_A = 'signed_in:user-a' as AuthPhase;
const USER_B = 'signed_in:user-b' as AuthPhase;

const decide = (over: Partial<Parameters<typeof rootRouteDecision>[0]> = {}) =>
  rootRouteDecision({ loading: false, isRecovery: false, onboarding: false, phase: USER_A, lastRoutedPhase: null, ...over });

describe('rootRouteDecision — a cold payment return', () => {
  it('PRT1: the first signed-in route on a primary checkout goes to that session’s ticket page', () => {
    expect(decide({ pathname: CHECKOUT })).toEqual({ navigate: true, to: TICKET });
    // the id is lowercased, as the server spells the id the ticket page compares against
    expect(decide({ pathname: `/primary-checkout/${S.toUpperCase()}` })).toEqual({ navigate: true, to: TICKET });
    // only the very first route is a relaunch: a sign-in or an account change on screen goes Home as before
    // (review of bda5c639 — the brief's "later phase changes stay exactly as today")
    expect(decide({ lastRoutedPhase: OUT, pathname: CHECKOUT })).toEqual(HOME);
    expect(decide({ phase: USER_B, lastRoutedPhase: USER_A, pathname: CHECKOUT })).toEqual(HOME);
  });

  it('PRT2: nothing after a ? or # is read — whatever the payment provider appended, the same bare ticket page', () => {
    for (const tail of [
      '?tt=7ab1e5e5-c0de-4abc-8def-00000000cafe&qty=2&attempt=attempt-abc123',
      '?payment_intent=REDACTED&payment_intent_client_secret=REDACTED&redirect_status=succeeded',
      '?payment_intent=REDACTED&payment_intent_client_secret=REDACTED&redirect_status=failed',
      '?redirect_status=requires_payment_method#paid',
      '#redirect_status=succeeded',
      '?',
    ]) expect({ tail, d: decide({ pathname: `${CHECKOUT}${tail}` }) }).toEqual({ tail, d: { navigate: true, to: TICKET } });
  });

  it('PRT3: anything but a primary checkout with a valid session id goes Home, as before', () => {
    for (const pathname of [
      '/primary-checkout/not-a-uuid', '/primary-checkout/', '/primary-checkout', `/primary-checkout/${S}/`,
      `/primary-checkout/${S}/extra`, `//primary-checkout/${S}`, `primary-checkout/${S}`, `/PRIMARY-CHECKOUT/${S}`,
      '/primary-checkout/5e55e55e-c0de-0abc-8def-00000000beef', '/primary-checkout/5e55e55e-c0de-4abc-cdef-00000000beef',
      `/primary-checkout/${S}x`, `/primary-checkout/%2F${S}`, `/primary-checkout/${S.toUpperCase()}%00`,
      `snatchit://primary-checkout/${S}`, `/checkout/${S}`, `/event/${S}`, TICKET, '/home', '/', '',
    ]) expect({ pathname, d: decide({ pathname }) }).toEqual({ pathname, d: HOME });
    expect(decide({ pathname: null })).toEqual(HOME);
    expect(decide({ pathname: undefined })).toEqual(HOME);
    expect(decide()).toEqual(HOME);
  });

  it('PRT4: a remembered returnTo keeps its precedence over the route on screen', () => {
    expect(decide({ pathname: CHECKOUT, returnTo: LISTING })).toEqual({ navigate: true, to: LISTING });
    // an unusable returnTo is no returnTo
    expect(decide({ pathname: CHECKOUT, returnTo: '/checkout/1' })).toEqual({ navigate: true, to: TICKET });
  });

  it('PRT5: signed out, the checkout is replaced by login exactly as before', () => {
    expect(decide({ phase: OUT, lastRoutedPhase: null, pathname: CHECKOUT })).toEqual({ navigate: true, to: '/(auth)/login' });
    expect(decide({ phase: OUT, lastRoutedPhase: USER_A, pathname: CHECKOUT })).toEqual({ navigate: true, to: '/(auth)/login' });
    // K-2 is about the tabs: a signed-out checkout already routed for stays where it is
    expect(decide({ phase: OUT, lastRoutedPhase: OUT, pathname: CHECKOUT, inSignedInArea: false }))
      .toEqual({ navigate: false, reason: 'same_phase' });
  });

  it('PRT6: once the phase has been routed, the checkout keeps control — a token refresh or user update moves no one', () => {
    expect(decide({ lastRoutedPhase: USER_A, pathname: CHECKOUT })).toEqual({ navigate: false, reason: 'same_phase' });
    expect(decide({ lastRoutedPhase: USER_A, pathname: `${CHECKOUT}?redirect_status=succeeded` }))
      .toEqual({ navigate: false, reason: 'same_phase' });
  });

  it('PRT7: every hold still wins — loading, navigator, recovery, onboarding — and none records anything', () => {
    expect(decide({ loading: true, pathname: CHECKOUT })).toEqual({ navigate: false, reason: 'loading' });
    expect(decide({ navigatorReady: false, pathname: CHECKOUT })).toEqual({ navigate: false, reason: 'navigator' });
    expect(decide({ isRecovery: true, pathname: CHECKOUT })).toEqual({ navigate: false, reason: 'recovery' });
    expect(decide({ onboarding: true, pathname: CHECKOUT })).toEqual({ navigate: false, reason: 'onboarding' });
  });
});

describe('paymentReturnTicket', () => {
  it('PRT8: the ticket page is built from the validated session id only, and nothing else is a target', () => {
    expect(paymentReturnTicket(CHECKOUT)).toBe(TICKET);
    expect(paymentReturnTicket(`${CHECKOUT}?redirect_status=failed`)).toBe(TICKET);
    // the session id is as case-blind as the two routes' own uuid checks (the route name is not), and it is
    // lowercased: the ticket page compares it with === against the server's lowercase id (review of bda5c639)
    expect(paymentReturnTicket(`/primary-checkout/${S.toUpperCase()}`)).toBe(TICKET);
    for (const raw of [null, undefined, 42, {}, [CHECKOUT], LISTING, TICKET, '/primary-checkout/x']) {
      expect(paymentReturnTicket(raw)).toBeNull();
    }
  });
});

const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');

describe('wiring', () => {
  const layout = strip(read('app/_layout.tsx'));
  const rule = strip(read('src/lib/auth/rootRoute.ts'));

  it('PRT9: the root layout hands the decision the pathname it already holds, with the pinned dependency list unchanged', () => {
    expect(layout).toMatch(/rootRouteDecision\(\{[\s\S]{0,300}inSignedInArea,\s*pathname: pathnameRef\.current,\s*navigatorReady: fontsReady,/);
    expect(layout).toMatch(/\}, \[session, routingLoading, isRecovery, onboarding, inDevHarness, inSignedInArea, fontsReady\]\);/);
    expect(layout).not.toMatch(/\[[^\]]*pathname[^\]]*\]\);/);
    expect(layout).not.toMatch(/useLocalSearchParams|useGlobalSearchParams|searchParams/);
  });

  it('PRT10: the rule reads the ticket page after every hold, the signed-out branch and returnTo, and never a query', () => {
    const body = rule.slice(rule.indexOf('export function rootRouteDecision('), rule.indexOf('export function isResetScreen('));
    const samePhaseAt = body.indexOf('if (input.phase === input.lastRoutedPhase)');
    const signedOutAt = body.indexOf("if (input.phase === 'signed_out') return");
    const returnToAt = body.indexOf('classifyReturnPath(input.returnTo)');
    const ticketAt = body.indexOf('paymentReturnTicket(input.pathname)');
    expect(samePhaseAt).toBeGreaterThan(body.indexOf('if (input.onboarding)'));
    expect(signedOutAt).toBeGreaterThan(samePhaseAt);
    expect(returnToAt).toBeGreaterThan(signedOutAt);
    expect(ticketAt).toBeGreaterThan(returnToAt);
    expect(rule).not.toMatch(/URLSearchParams|searchParams|payment_intent|redirect_status|client_secret/);
  });
});
