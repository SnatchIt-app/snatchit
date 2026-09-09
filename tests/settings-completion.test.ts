/**
 * tests/settings-completion.test.ts — behaviour guards for the nine settings
 * subroutes redesigned in Phase 8. These screens are effect-heavy (Supabase,
 * Stripe, OTP), so their critical invariants are pinned by asserting the shipped
 * source still contains each one: a failed save never looks successful, a failed
 * load is distinct from empty, payout status never regresses on a blip, and the
 * legal/privacy CONTENT is byte-preserved (not paraphrased).
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');

const files = {
  notifications: read('app/settings/notifications.tsx'),
  preferences: read('app/settings/preferences.tsx'),
  blocked: read('app/settings/blocked-users.tsx'),
  editProfile: read('app/settings/edit-profile.tsx'),
  payout: read('app/settings/payout-setup.tsx'),
  verify: read('app/settings/verify-phone.tsx'),
  support: read('app/settings/support.tsx'),
  legal: read('app/settings/legal.tsx'),
  privacy: read('app/settings/privacy.tsx'),
};

describe('Group A — notifications / preferences / blocked users', () => {
  it('notifications keeps the optimistic toggle with revert on failure', () => {
    expect(files.notifications).toContain("from('notification_preferences')");
    expect(files.notifications).toContain('.update({ [key]: newValue })');
    // revert: the previous value is restored when the write errors
    expect(files.notifications).toMatch(/if \(updateErr\)[\s\S]*setPrefs\(\(p\) =>/);
    expect(files.notifications).toContain('getPermissionsAsync'); // permission banner
  });

  it('preferences: a failed save is not treated as success', () => {
    expect(files.preferences).toContain("rpc('get_my_profile')"); // hydrate
    expect(files.preferences).toContain('preferred_neighborhoods');
    // on error: set saveError and RETURN before router.back — never navigate on failure
    expect(files.preferences).toMatch(/if \(error\)[\s\S]*setSaveError\([\s\S]*return;/);
    expect(files.preferences).toContain('router.back()');
  });

  it('blocked users keeps failed-load distinct from empty', () => {
    expect(files.blocked).toContain('loadFailed');
    expect(files.blocked).toMatch(/loadFailed && rows\.length === 0/);
    expect(files.blocked).toContain("from('user_blocks')"); // fetch
    expect(files.blocked).toMatch(/\.delete\(\)[\s\S]*blocked_id/);   // unblock
  });
});

describe('Group B — edit profile / payout / verify phone', () => {
  it('edit profile keeps validation, phone normalization and the avatar path', () => {
    expect(files.editProfile).toContain('Display name is required.');
    expect(files.editProfile).toContain('normalizeUSPhone(phoneNumber)'); // normalize before persist
    expect(files.editProfile).toContain('avatar_path:');
    expect(files.editProfile).toContain("from('profiles')");
    // no invented social fields
    expect(files.editProfile).not.toMatch(/followers|following/i);
  });

  it('payout never regresses status on a network error and is presentation-only', () => {
    expect(files.payout).toContain("functions.invoke('create-connect-account'");
    expect(files.payout).toContain('status_only');
    expect(files.payout).toContain('openAuthSessionAsync');
    expect(files.payout).toContain('snatchit://payout-return');
    // the catch block keeps current status rather than downgrading it
    expect(files.payout).toMatch(/catch \{[\s\S]*keep current status/);
  });

  it('verify phone keeps the phone_change OTP flow and resend cooldown', () => {
    expect(files.verify).toContain("updateUser({ phone: e164 })");
    expect(files.verify).toContain("type: 'phone_change'");
    expect(files.verify).toContain('verifyOtp');
    expect(files.verify).toContain('RESEND_COOLDOWN_S');
    // no banned AI phrase in the user-facing copy
    expect(files.verify).not.toMatch(/you're all set/i);
  });
});

describe('Group C — support / legal / privacy', () => {
  it('support keeps the mailto and invents no chat/SLA', () => {
    expect(files.support).toContain('mailto:');
    expect(files.support).toContain('support@snatchitapp.com');
    expect(files.support).not.toMatch(/live chat|response within \d+ (minutes|hours)/i);
  });

  it('legal CONTENT is preserved verbatim (not paraphrased)', () => {
    for (const phrase of [
      'Effective Date: March 20, 2026',
      'A 10% service fee is added to the buyer',
      'Form 1099-K',
      'binding individual arbitration administered by the AAA',
      'JDT LLC',
    ]) {
      expect(files.legal, `legal must keep: ${phrase}`).toContain(phrase);
    }
  });

  it('privacy CONTENT is preserved verbatim (not paraphrased)', () => {
    for (const phrase of [
      'Effective Date: March 20, 2026',
      'We do not sell your personal information to third parties.',
      'PCI DSS Level 1 certified',
      'not intended for users under 18 years of age',
    ]) {
      expect(files.privacy, `privacy must keep: ${phrase}`).toContain(phrase);
    }
  });
});

describe('all nine — house rules', () => {
  it('none query kernel.tickets or touch the money modules', () => {
    for (const [name, src] of Object.entries(files)) {
      expect(src, `${name} must not query kernel.tickets`).not.toMatch(/kernel[^\n]*tickets/);
      expect(src, `${name} must not import money/payments`).not.toMatch(/lib\/money|lib\/payments/);
    }
  });

  it('the interactive settings screens use no emoji UI', () => {
    // Legal/privacy are dense legal prose (no emoji anyway); the redesigned
    // interactive screens must carry none.
    for (const name of ['notifications', 'preferences', 'blocked', 'editProfile', 'payout', 'verify', 'support'] as const) {
      expect(files[name], `${name} must have no emoji`).not.toMatch(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u);
    }
  });

  it('all nine wear the shared V2 SettingsHeader', () => {
    for (const [name, src] of Object.entries(files)) {
      expect(src, `${name} uses SettingsHeader`).toContain('SettingsHeader');
    }
  });
});
