/**
 * tests/reputation.test.ts — the seller-reputation model + Phase 10 surface guards.
 *
 * The reputation ladder is pinned here; the public profile / report / payout
 * screens are effect-heavy, so their privacy and behaviour are guarded from the
 * shipped source (safe columns only, stats-unavailable ≠ zero, block/report flows,
 * auto-redirect, no kernel.tickets, money via helpers).
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { deriveReputation, reputationTone } from '../src/lib/profile/reputation';
import type { ProfileTrustStats } from '../src/types';

function stats(over: Partial<ProfileTrustStats> = {}): ProfileTrustStats {
  return {
    completed_sales: 0,
    completed_purchases: 0,
    active_listings: 0,
    disputes_opened: 0,
    disputes_lost: 0,
    seller_terminal_total: 0,
    seller_terminal_successful: 0,
    member_since: null,
    ...over,
  } as ProfileTrustStats;
}

describe('reputation ladder', () => {
  it('null stats → new seller, no success rate', () => {
    const r = deriveReputation(null);
    expect(r.tier).toBe('new_seller');
    expect(r.successRate).toBeNull();
  });

  it('any lost dispute is the trust floor, even at high volume', () => {
    const r = deriveReputation(stats({ completed_sales: 500, seller_terminal_total: 500, seller_terminal_successful: 500, disputes_lost: 1 }));
    expect(r.tier).toBe('needs_review');
  });

  it('under 5 completed sales is a new seller', () => {
    expect(deriveReputation(stats({ completed_sales: 4, seller_terminal_total: 4, seller_terminal_successful: 4 })).tier).toBe('new_seller');
  });

  it('promotes through Trusted / Top / Elite by volume × rate', () => {
    expect(deriveReputation(stats({ completed_sales: 10, seller_terminal_total: 100, seller_terminal_successful: 96 })).tier).toBe('trusted');
    expect(deriveReputation(stats({ completed_sales: 30, seller_terminal_total: 100, seller_terminal_successful: 98 })).tier).toBe('top');
    expect(deriveReputation(stats({ completed_sales: 100, seller_terminal_total: 100, seller_terminal_successful: 100 })).tier).toBe('elite');
  });

  it('volume but below the rate floor → needs review', () => {
    expect(deriveReputation(stats({ completed_sales: 20, seller_terminal_total: 100, seller_terminal_successful: 80 })).tier).toBe('needs_review');
  });

  it('tones are restrained (no rainbow)', () => {
    expect(reputationTone('elite')).toBe('success');
    expect(reputationTone('trusted')).toBe('success');
    expect(reputationTone('needs_review')).toBe('danger');
    expect(reputationTone('new_seller')).toBe('neutral');
  });
});

describe('Phase 10 surfaces — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
  const profile = read('app/profile/[id].tsx');
  const report = read('app/report/[type]/[id].tsx');
  const payoutReturn = read('app/payout-return.tsx');
  const payoutRefresh = read('app/payout-refresh.tsx');

  it('public profile selects ONLY safe columns — never private data', () => {
    expect(profile).toContain('get_profile_trust_stats');
    // the profile select carries no private columns (the boolean
    // stripe_onboarding_complete IS public — it is the verified-seller signal).
    const select = profile.match(/\.select\('([^']*is_verified_seller[^']*)'\)/)?.[1] ?? '';
    for (const banned of ['phone_number', 'stripe_connect_id', 'wallet_balance', 'email', 'preferred_neighborhoods']) {
      expect(select, `select must not expose ${banned}`).not.toContain(banned);
    }
  });

  it('public profile keeps stats-unavailable distinct from zero + block/report/unblock', () => {
    expect(profile).toContain('statsUnavailable');
    expect(profile).toContain("from('user_blocks')");
    expect(profile).toContain('/report/user/');
    expect(profile).toContain('deriveReputation(');
    expect(profile).toContain('allInLabel('); // money via the all-in helper
    expect(profile).toContain('EventMedia');   // shared media system
    expect(profile).toContain('!isSelf');       // actions hidden on your own profile
    expect(profile).not.toMatch(/kernel[^\n]*tickets/);
  });

  it('report keeps the reasons insert filtered by target type, no raw error shown', () => {
    expect(report).toContain("from('reports').insert");
    expect(report).toContain('appliesTo.includes(targetType)');
    expect(report).toContain('Could not submit report'); // friendly, not the raw string
    expect(report).not.toMatch(/error\.message[^)]*Alert\.alert\('Could not submit/s);
  });

  it('payout landing pages keep the auto-redirect + replace routing', () => {
    for (const src of [payoutReturn, payoutRefresh]) {
      expect(src).toContain('AUTO_REDIRECT_MS');
      expect(src).toContain('router.replace(');
      expect(src).not.toMatch(/kernel[^\n]*tickets/);
    }
    expect(payoutReturn).toContain("router.replace('/(tabs)/profile')");
    expect(payoutRefresh).toContain('/settings/payout-setup');
  });
});
