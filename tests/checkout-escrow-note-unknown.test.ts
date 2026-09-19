/**
 * The escrow line hides whenever the payment status is unknown (owner, 2026-09-19, direct).
 *
 * Owner: "hide 'Payment is held until your ticket reaches you. Secured by Stripe.' whenever payment status is unknown.
 * It implies a payment state we haven't established."
 *
 * Observed on Build 22's H5 screen (owner's screenshot): the line showed under "We couldn't check whether this has
 * already been paid." Checkout has exactly two states in which the payment status is unknown:
 * - the settled-payment lookup failed (F-CHK-READERR: "We couldn't check whether this has already been paid."), from
 *   setup or re-validation;
 * - a payment result could not be confirmed (`checkUnreachable`: "We couldn't confirm your payment yet").
 *
 * Owner, 2026-09-19 (refinement): "hide the payment-held assurance in the unknown-reservation state too, including while
 * its recheck is pending. The distinction is whether the message is supported, not merely whether payment status is
 * known. A successful lookup finding no payment does not establish that money is being held." So the reservation-
 * unknown state ("We couldn't check your reservation.") hides it as well, until a listing read succeeds. Visibility of
 * the assurance only: no payment decision, reservation behaviour, Pay or "Check again" action changes.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { ESCROW_NOTE_COPY, showEscrowNote } from '../src/lib/checkout/holdState';

describe('the rule', () => {
  it('E1: the line is the existing sentence, now held in the copy module', () => {
    expect(ESCROW_NOTE_COPY).toBe('Payment is held until your ticket reaches you. Secured by Stripe.');
  });

  it('E2: hidden when the payment lookup failed', () => {
    expect(showEscrowNote({ paymentStatusUnknown: true, reservationStatusUnknown: false, confirmUnreachable: false })).toBe(false);
  });

  it('E3: hidden when a payment result could not be confirmed', () => {
    expect(showEscrowNote({ paymentStatusUnknown: false, reservationStatusUnknown: false, confirmUnreachable: true })).toBe(false);
    expect(showEscrowNote({ paymentStatusUnknown: true, reservationStatusUnknown: false, confirmUnreachable: true })).toBe(false);
  });

  it('E10: hidden when the reservation could not be checked (owner: the assurance is not supported there)', () => {
    expect(showEscrowNote({ paymentStatusUnknown: false, reservationStatusUnknown: true, confirmUnreachable: false })).toBe(false);
  });

  it('E4 (witness): shown when neither the payment nor the reservation is unknown', () => {
    expect(showEscrowNote({ paymentStatusUnknown: false, reservationStatusUnknown: false, confirmUnreachable: false })).toBe(true);
  });
});

// ── The screen's wiring (no CheckoutNative render harness; these pin how it applies the rule) ─────────────────────
const src = () => readFileSync(resolve(__dirname, '../src/screens/checkout/CheckoutNative.tsx'), 'utf8');
const between = (s: string, from: string, to: string) => {
  const a = s.indexOf(from), b = s.indexOf(to, a + 1);
  expect(a, from).toBeGreaterThan(-1);
  expect(b, to).toBeGreaterThan(a);
  return s.slice(a, b);
};

describe('the screen applies it', () => {
  it('E5: the line renders once, only through the rule, fed every unknown state; the screen no longer spells it out', () => {
    const s = src();
    expect(s).toContain('showEscrowNote({ paymentStatusUnknown, reservationStatusUnknown, confirmUnreachable: checkUnreachable }) ? (');
    expect(s.split('{ESCROW_NOTE_COPY}').length - 1).toBe(1);
    expect(s).not.toContain('Payment is held until your ticket reaches you');   // witness: E1 finds it in holdState
  });

  it('E6: setup marks the payment status unknown when its payment lookup fails', () => {
    const block = between(src(), "if (decision.kind === 'payment_status_unknown') {", "if (decision.kind === 'already_settled')");
    expect(block).toContain('setPaymentStatusUnknown(true);');
  });

  it('E7: re-validation marks it too', () => {
    const block = between(src(), "if (outcome.kind === 'payment_status_unknown') {", '}\n');
    expect(block).toContain('setPaymentStatusUnknown(true);');
  });

  it('E8: a reservation-unknown state does not mark the PAYMENT flag — it has its own (witness: E6, E7)', () => {
    const s = src();
    expect(between(s, "if (decision.kind === 'reservation_unverifiable') {", "if (decision.kind === 'not_held')")).not.toContain('setPaymentStatusUnknown');
    expect(between(s, "if (outcome.kind === 'reservation_unverifiable') {", '}\n')).not.toContain('setPaymentStatusUnknown');
  });

  it('E9: only a SUCCESSFUL payment lookup clears it — not the start of the re-check, while the status is still unknown', () => {
    const s = src();
    const dep = between(s, 'fetchSettledPayment: async (lid, bid) => {', 'fetchListing: async (lid) => {');
    const afterRead = between(dep, "if ('error' in read) throw new SettledReadError(read.error);", 'return read.rows;');
    expect(afterRead).toContain('setPaymentStatusUnknown(false);');
    const setupStart = between(s, 'async function setupPayment() {', 'const decision = await decideCheckoutSetup(');
    expect(setupStart).not.toContain('setPaymentStatusUnknown');   // witness: the same query finds it in the dependency
    expect(s.split('setPaymentStatusUnknown(false);').length - 1).toBe(1);
  });

  it('E11: setup marks the reservation unknown when its listing read fails', () => {
    const block = between(src(), "if (decision.kind === 'reservation_unverifiable') {", "if (decision.kind === 'not_held')");
    expect(block).toContain('setReservationStatusUnknown(true);');
  });

  it('E12: re-validation marks it too', () => {
    const block = between(src(), "if (outcome.kind === 'reservation_unverifiable') {", '}\n');
    expect(block).toContain('setReservationStatusUnknown(true);');
  });

  it('E13: only a SUCCESSFUL listing read clears it — so the line stays hidden while the recheck is pending', () => {
    const s = src();
    const dep = between(s, 'fetchListing: async (lid) => {', 'createIntent: () =>');
    expect(dep).toContain('if (!error) setReservationStatusUnknown(false);');
    expect(dep.indexOf('if (!error) setReservationStatusUnknown(false);')).toBeLessThan(dep.indexOf('return error ? null : data;'));
    const setupStart = between(s, 'async function setupPayment() {', 'const decision = await decideCheckoutSetup(');
    expect(setupStart).not.toContain('setReservationStatusUnknown');   // witness: the same query finds it in the dependency
    expect(s.split('setReservationStatusUnknown(false)').length - 1).toBe(1);
  });
});
