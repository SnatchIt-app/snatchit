/**
 * tests/reservation-exit.test.ts — Buy Now hold release on explicit listing exit.
 *
 * Owner rule: Checkout -> Listing KEEPS the hold; Listing -> Home RELEASES it.
 * The decision is pure and tested here; the shipped wiring is guarded from source
 * (the exit signal must be navigation removal, never focus/background).
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { shouldReleaseReservation } from '../src/lib/listing/reservationExit';

const ME = 'user-1';
const base = {
  status: 'reserved' as string | null | undefined,
  reservedBy: ME as string | null | undefined,
  userId: ME as string | null | undefined,
  alreadyReleased: false,
  purchased: false,
};

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

describe('reservation exit decision', () => {
  it('releases my own active hold when I leave the listing', () => {
    expect(shouldReleaseReservation(base)).toBe(true);
  });

  it('never releases another buyer\'s hold', () => {
    expect(shouldReleaseReservation({ ...base, reservedBy: 'someone-else' })).toBe(false);
  });

  it('never releases after a completed purchase', () => {
    expect(shouldReleaseReservation({ ...base, purchased: true })).toBe(false);
    expect(shouldReleaseReservation({ ...base, status: 'sold' })).toBe(false);
  });

  it('is a no-op when nothing is held (already released / expired / active)', () => {
    expect(shouldReleaseReservation({ ...base, status: 'active' })).toBe(false);
    expect(shouldReleaseReservation({ ...base, reservedBy: null })).toBe(false);
  });

  it('is idempotent: a second exit does not fire again', () => {
    expect(shouldReleaseReservation({ ...base, alreadyReleased: true })).toBe(false);
  });

  it('does nothing when signed out', () => {
    expect(shouldReleaseReservation({ ...base, userId: null })).toBe(false);
  });
});

describe('reservation exit — shipped wiring', () => {
  const screen = read('src/screens/ListingDetailScreen.tsx');

  it('uses navigation removal as the exit signal (so Checkout -> Listing keeps the hold)', () => {
    // beforeRemove fires when the listing is popped, NOT when Checkout is pushed.
    expect(screen).toContain("navigation.addListener('beforeRemove'");
    expect(screen).toContain('shouldReleaseReservation');
  });

  it('never treats focus loss or backgrounding as abandonment', () => {
    // no AppState/blur-driven release anywhere in the screen
    expect(screen).not.toMatch(/AppState[\s\S]{0,200}release_reservation/);
    expect(screen).not.toMatch(/'blur'[\s\S]{0,200}release_reservation/);
  });

  it('calls the existing owner-scoped RPC and never writes reservation rows directly', () => {
    expect(screen).toContain("rpc('release_reservation'");
    expect(screen).not.toMatch(/from\('listings'\)[\s\S]{0,120}\.update\([\s\S]{0,120}reserved_/);
  });

  it('does not block navigation on the release', () => {
    // fire-and-forget: no await/preventDefault in the exit listener
    expect(screen).not.toMatch(/beforeRemove'[\s\S]{0,400}preventDefault/);
    expect(screen).not.toMatch(/beforeRemove',\s*async/);
  });
});
