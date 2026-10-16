/**
 * Payout status — an UNKNOWN state is never shown as "not set up".
 *
 * Found by C on the frozen RC9 candidate (2026-10-16), A's decision: follow-up for the next build.
 * The Profile tab started its payout row at 'not_connected' ("Set up payouts — Not set up") and kept it
 * whenever the Stripe status probe (create-connect-account status_only, 6 s timeout) was still running,
 * failed or timed out; Payout setup did the same on a failed first check and offered "Set up payouts".
 * A connected seller (production admin: charges and payouts enabled, 0 requirements) was told the
 * opposite of the truth. The server state was right; the presentation turned "don't know yet" into a
 * definitive negative. Pure functions + source pins; mocked nothing, but NOT device evidence.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  PAYOUT_ROW_COPY,
  PAYOUT_UNKNOWN_SETUP_COPY,
  isServerPayoutStatus,
  parsePayoutStatusReply,
  payoutViewAfterProfileRead,
  settlePayoutView,
  type PayoutView,
} from '../src/lib/payout/payoutStatusView';

describe('reading the status_only reply', () => {
  it('PV1: only a recognised status counts; anything else says nothing', () => {
    expect(parsePayoutStatusReply({ status: 'connected' })).toBe('connected');
    expect(parsePayoutStatusReply('{"status":"onboarding_required"}')).toBe('onboarding_required');
    expect(parsePayoutStatusReply({ status: 'not_connected' })).toBe('not_connected');
    expect(parsePayoutStatusReply({ status: 'pending' })).toBeNull();
    expect(parsePayoutStatusReply('{not json')).toBeNull();
    expect(parsePayoutStatusReply(null)).toBeNull();
    expect(parsePayoutStatusReply(undefined)).toBeNull();
    expect(isServerPayoutStatus('connected')).toBe(true);
    expect(isServerPayoutStatus('checking')).toBe(false);
  });
});

describe('what the screens show', () => {
  it('PV2: a reported status wins; with no answer a known status is kept, and an unknown one becomes "unavailable" — never "not connected"', () => {
    expect(settlePayoutView('checking', 'connected')).toBe('connected');
    expect(settlePayoutView('connected', 'onboarding_required')).toBe('onboarding_required');
    expect(settlePayoutView('connected', null)).toBe('connected');          // never regress on a blip
    expect(settlePayoutView('checking', null)).toBe('unavailable');
    expect(settlePayoutView('unavailable', null)).toBe('unavailable');
  });

  it('PV3: the profile read decides only what it knows', () => {
    expect(payoutViewAfterProfileRead('checking', null)).toBe('unavailable');                  // read failed, nothing known
    expect(payoutViewAfterProfileRead('connected', null)).toBe('connected');                    // read failed, keep what we knew
    expect(payoutViewAfterProfileRead('checking', { connectId: null })).toBe('not_connected');  // definitive: no account
    expect(payoutViewAfterProfileRead('checking', { connectId: 'acct_x' })).toBe('checking');   // ask Stripe
    expect(payoutViewAfterProfileRead('connected', { connectId: 'acct_x' })).toBe('connected'); // re-check without a flicker
  });

  it('PV4: the production case — a connected seller whose probe times out sees "unavailable", not "Not set up"', () => {
    let view: PayoutView = 'checking';
    view = payoutViewAfterProfileRead(view, { connectId: 'acct_connected' });
    expect(PAYOUT_ROW_COPY[view].state).not.toMatch(/not set up|not connected/i);   // while the probe runs
    view = settlePayoutView(view, parsePayoutStatusReply(null));                     // timeout → no reply
    expect(view).toBe('unavailable');
    expect(PAYOUT_ROW_COPY[view].state).not.toMatch(/not set up|not connected/i);
    expect(PAYOUT_ROW_COPY.not_connected.state).toBe('Not set up');                 // the real negative is unchanged
    expect(PAYOUT_ROW_COPY.connected.state).toBe('Payouts enabled');
  });

  it('PV5: the unknown-state copy on Payout setup offers a re-check, never a setup call to action', () => {
    expect(PAYOUT_UNKNOWN_SETUP_COPY.btnLabel).toBe('Try again');
    expect(`${PAYOUT_UNKNOWN_SETUP_COPY.title} ${PAYOUT_UNKNOWN_SETUP_COPY.description} ${PAYOUT_UNKNOWN_SETUP_COPY.statusLabel}`)
      .not.toMatch(/set up payouts|not connected|not set up/i);
  });
});

describe('wiring', () => {
  const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const profile = strip(readFileSync(resolve(__dirname, '..', 'app/(tabs)/profile.tsx'), 'utf8'));
  const setup = strip(readFileSync(resolve(__dirname, '..', 'app/settings/payout-setup.tsx'), 'utf8'));

  it('PV6: Profile starts at "checking" and routes the profile read and the probe reply through the rules', () => {
    expect(profile).toMatch(/useState<PayoutView>\('checking'\)/);
    expect(profile).not.toMatch(/useState<PayoutStatus>\('not_connected'\)/);
    expect(profile).toMatch(/payoutViewAfterProfileRead\(/);
    expect(profile).toMatch(/settlePayoutView\(/);
    expect(profile).toMatch(/PAYOUT_ROW_COPY\[payoutView\]/);
  });

  it('PV7: Payout setup starts at "checking", settles through the rules, and an unknown state\'s button re-checks instead of starting setup', () => {
    expect(setup).toMatch(/useState<PayoutView>\('checking'\)/);
    expect(setup).toMatch(/payoutViewAfterProfileRead\(/);
    expect(setup).toMatch(/settlePayoutView\(/);
    expect(setup).toMatch(/onPress=\{statusKnown \? handleSetup : recheck\}/);
    // existing pins kept (the no-regress comment is pinned raw by settings-completion)
    expect(setup).toContain('status_only');
    expect(setup).toContain("statusLabel: 'Not connected'");
  });
});
