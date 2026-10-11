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
    // Pinned after a P-5 mutant added a tier word here and nothing failed: a FAILED read is not
    // a seller with a tier, and this branch's wording must not drift into claiming one.
    expect(r.blurb).toBe('No completed transfers yet');
    expect(r.label).toBe('New seller');
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

describe('an unknown transfer-success rate is neither a zero nor a failure', () => {
  /*
   * The rate's denominator is `seller_terminal_total`. When it is 0 there is no rate to state,
   * and this module's own rule is that a zero would misrepresent a seller on the one screen whose
   * job is trust. B's batch-7 native review at 3c03778a found the public profile printing the
   * literal `null% transfer success` beside a "Needs review" chip, which is both an invented
   * failure and a broken string. R1/R2 pin the guard; R3/R4/R5 pin what must NOT change.
   */

  it('R1: volume with no terminal transfers states no percentage, and no verdict either', () => {
    const r = deriveReputation(stats({ completed_sales: 14, seller_terminal_total: 0, seller_terminal_successful: 0 }));
    expect(r.successRate).toBeNull();
    expect(r.blurb).not.toContain('null');
    // No invented rate — not a 0%, not a 100%.
    expect(r.blurb).not.toMatch(/\d+\s*%/);
    // An unknown rate is not a trust failure...
    expect(r.tier).not.toBe('needs_review');
    // ...and not a promotion. Both would be claims the data does not carry.
    expect(['trusted', 'top', 'elite']).not.toContain(r.tier);
    expect(reputationTone(r.tier)).toBe('neutral');
  });

  it('R2: no stats shape puts null, undefined or NaN in front of a reader', () => {
    const shapes: Partial<ProfileTrustStats>[] = [
      {},
      { completed_sales: 1 },
      { completed_sales: 5 },
      { completed_sales: 14, seller_terminal_total: 0, seller_terminal_successful: 0 },
      { completed_sales: 14, seller_terminal_total: 0, disputes_lost: 1 },
      { completed_sales: 120, seller_terminal_total: 0, seller_terminal_successful: 0 },
      { completed_sales: 9, seller_terminal_total: 9, seller_terminal_successful: 9 },
      { completed_sales: 9, seller_terminal_total: 12, seller_terminal_successful: 4 },
    ];
    for (const over of shapes) {
      const r = deriveReputation(stats(over));
      expect(r.blurb, JSON.stringify(over)).not.toMatch(/null|undefined|NaN/);
      expect(r.label, JSON.stringify(over)).not.toMatch(/null|undefined|NaN/);
    }
  });

  it('R3: every shape the RPC can actually return still carries its real percentage', () => {
    /*
     * Migration 031: `completed_sales` counts seller transfers in
     * ('buyer_confirmed','auto_released'); `seller_terminal_total` counts those PLUS
     * ('disputed','expired','reversed') — same table, same predicate, a strict superset. So a row
     * the RPC returns always has denom >= completed_sales, and R1's shape cannot come from it.
     * This is the control: the guard must not move any rate that does exist.
     */
    for (const sales of [5, 9, 25, 100]) {
      for (const extra of [0, 3]) {
        const denom = sales + extra;
        for (const successful of [denom, Math.floor(denom * 0.8)]) {
          const r = deriveReputation(stats({
            completed_sales: sales, seller_terminal_total: denom, seller_terminal_successful: successful,
          }));
          expect(r.successRate).toBe(Math.round((successful / denom) * 100));
          expect(r.blurb).toMatch(/\d+% (transfer )?success/);
        }
      }
    }
  });

  it('R4: a true no-history seller says so in words, not as a zero', () => {
    const r = deriveReputation(stats());
    expect(r.successRate).toBeNull();
    expect(r.blurb).toBe('No completed transfers yet');
  });

  it('R6: the tier word rides in the blurb, because the badge is capped at 1.3x', async () => {
    /*
     * P-5 (B, 069eeb9c): Badge pins its label to MAX_DISPLAY_FONT_SCALE, so at A3XL the word
     * "Needs review" paints at 0.47x the blurb beside it — the only adverse signal on the panel
     * is the smallest text on it, and colour is not a carrier. Until the badge can scale, the
     * four branches whose tier word appears nowhere else carry it in the blurb too.
     */
    const cases: Array<[Partial<ProfileTrustStats>, string]> = [
      [{ completed_sales: 120, seller_terminal_total: 120, seller_terminal_successful: 120 }, 'Elite seller'],
      [{ completed_sales: 30,  seller_terminal_total: 100, seller_terminal_successful: 99 },  'Top seller'],
      [{ completed_sales: 10,  seller_terminal_total: 100, seller_terminal_successful: 96 },  'Trusted seller'],
      [{ completed_sales: 20,  seller_terminal_total: 100, seller_terminal_successful: 82 },  'Needs review'],
    ];
    for (const [over, word] of cases) {
      const r = deriveReputation(stats(over));
      expect(r.label, JSON.stringify(over)).toBe(word);
      expect(r.blurb, `${word} must say so in the blurb as well as the badge`).toContain(word);
      expect(r.blurb).toMatch(/\d+%/);           // and still carries the number
    }
    // The two branches whose blurb already says what the badge says keep their wording.
    expect(deriveReputation(stats()).blurb).toBe('No completed transfers yet');
    expect(deriveReputation(stats({ completed_sales: 14, seller_terminal_total: 0 })).blurb)
      .toBe('14 sales \u00b7 transfer success unavailable');
  });

  it('R5: a lost dispute is still the floor, and its blurb was already guarded', () => {
    const r = deriveReputation(stats({ completed_sales: 14, disputes_lost: 2, seller_terminal_total: 0 }));
    expect(r.tier).toBe('needs_review');
    expect(r.blurb).toContain('2 lost disputes');
    expect(r.blurb).not.toContain('null');
    expect(r.blurb).not.toMatch(/%/);
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
    // RETARGETED (E, 2026-09-24): the V3 all-in display, 2dp, and the trailing "total" dropped because
    // the label above the figure already says what it is.
    expect(profile).toContain('allInFromDollarsV3('); // money via the all-in helper
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
