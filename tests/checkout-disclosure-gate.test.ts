/**
 * Owner (2026-10-15, direct and via A): "The final app must not offer payment for a waived listing while hiding
 * its disclosure because summary loading failed." The waiver state comes from checkout's summary read
 * (listingSummary: proof_status, proof_waived_at). Until that read has answered, the waiver state is unknown, so
 * Pay is withheld for EVERY listing; a failed read offers a retry of the read, never Pay. GATED FILE
 * (payControl.ts): sent to A before merge. Pure precedence tests. Not device evidence.
 */
import { describe, expect, it } from 'vitest';

import { payControl, type PayControlInput } from '../src/lib/checkout/payControl';

const ready: PayControlInput = {
  authLoading: false, paymentLoading: false, confirming: false, paymentReady: true, paymentError: false, formattedTotal: '$66',
};

describe('the disclosure gate', () => {
  it('DG1: details still loading → no Pay, a loading state', () => {
    expect(payControl({ ...ready, disclosure: 'loading' })).toEqual({ label: 'Loading listing details', loading: true, disabled: true, action: 'none' });
  });
  it('DG2: details failed to load → no Pay; the only action re-reads the details', () => {
    expect(payControl({ ...ready, disclosure: 'failed' })).toEqual({ label: 'Load listing details', loading: false, disabled: false, action: 'reload_details' });
  });
  it('DG3: details loaded → Pay as before', () => {
    expect(payControl({ ...ready, disclosure: 'ready' })).toEqual({ label: 'Pay $66', loading: false, disabled: false, action: 'pay' });
  });
  it('DG4: a failed details read outranks a payment-setup error (Pay is never reachable without the details)', () => {
    expect(payControl({ ...ready, paymentReady: false, paymentError: true, disclosure: 'failed' }).action).toBe('reload_details');
  });
  it('DG5: money states keep their precedence — in-flight charge, eligibility unknown and a lost hold outrank the gate', () => {
    expect(payControl({ ...ready, confirming: true, disclosure: 'failed' }).action).toBe('none');
    expect(payControl({ ...ready, confirming: true, disclosure: 'failed' }).label).toBe('Confirming payment');
    expect(payControl({ ...ready, statusUnknown: true, disclosure: 'failed' }).action).toBe('retry');
    expect(payControl({ ...ready, holdLost: true, disclosure: 'failed' }).action).toBe('back');
  });
  it('DG6: no Pay in any gate state, whatever else is ready', () => {
    for (const disclosure of ['loading', 'failed'] as const) {
      for (const over of [{}, { reservationMsLeft: 60_000 }, { paymentError: true }]) {
        expect(payControl({ ...ready, ...over, disclosure }).action).not.toBe('pay');
      }
    }
  });
});

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { LISTING_DETAILS_UNAVAILABLE_COPY } from '../src/lib/checkout/listingSummary';

describe('the checkout screen feeds the gate (not gated: CheckoutNative.tsx)', () => {
  const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const n = strip(readFileSync(resolve(__dirname, '..', 'src/screens/checkout/CheckoutNative.tsx'), 'utf8'));

  it('DG7: the details read records loading / ready / failed, and is re-runnable', () => {
    expect(n).toMatch(/const \[detailsState, setDetailsState\] = useState<'loading' \| 'ready' \| 'failed'>\('loading'\);/);
    expect(n).toMatch(/if \(error \|\| !data\) \{[\s\S]{0,300}setDetailsState\('failed'\);/);
    expect(n).toMatch(/setDisplay\(mapListingSummary\(row, \{ eventName, venue \}\)\);\s*setDetailsState\('ready'\);/);
    expect(n).toMatch(/const reloadDetails = useCallback\(/);
  });
  it('DG8: payControl receives the details state, and reload_details re-reads them', () => {
    expect(n).toMatch(/payControl\(\{[\s\S]{0,600}disclosure: detailsState,/);
    expect(n).toMatch(/pay\.action === 'reload_details' \? reloadDetails/);
  });
  it('DG9: a failed details read is said on screen, with its own retry', () => {
    expect(LISTING_DETAILS_UNAVAILABLE_COPY.title).toBe("Couldn't load listing details");
    expect(n).toMatch(/: detailsState === 'failed' \? \{\s*title: LISTING_DETAILS_UNAVAILABLE_COPY\.title,\s*body: LISTING_DETAILS_UNAVAILABLE_COPY\.body,/);
  });
});
