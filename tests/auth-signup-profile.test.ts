/**
 * tests/auth-signup-profile.test.ts — Sign up collects the account, and stores it
 * where the database already keeps it.
 *
 * The interesting assertions are about ownership: that name, phone and gender go to
 * the columns and the RPC that already exist, that no second copy of any of them is
 * introduced, and that the phone is verified by the provider rather than by us.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { rootRouteDecision } from '../src/lib/auth/rootRoute';
import {
  canGoBack,
  DEMOGRAPHIC_NOTICE_VERSION,
  GENDER_OPTIONS,
  nextStep,
  prevStep,
  SIGNUP_STEPS,
  SIGNUP_STEP_COUNT,
  stepIndex,
  validateAboutStep,
  validateAccountStep,
  validateCodeStep,
} from '../src/lib/auth/signupFlow';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const signup = read('app/(auth)/signup.tsx');
const signupCode = stripComments(signup);
const gate = read('src/lib/auth/onboardingGate.ts');
const layout = read('app/_layout.tsx');

describe('1-3. Sign up collects email, name and mobile number', () => {
  it('email and password create the account', () => {
    expect(signup).toContain('label="Email"');
    expect(signup).toContain('label="Password"');
    expect(signup).toContain('supabase.auth.signUp({');
    expect(signup).toContain('email: email.trim(),');
  });

  it('name is collected', () => {
    expect(signup).toContain('label="Name"');
    expect(validateAboutStep('', 'man')).toBe('Enter your name.');
    expect(validateAboutStep('J', 'man')).toBe('Name must be at least 2 characters.');
    expect(validateAboutStep('x'.repeat(51), 'man')).toBe('Name must be 50 characters or fewer.');
    expect(validateAboutStep('Jose', 'man')).toBeNull();
  });

  it('mobile number is collected on its own step', () => {
    expect(SIGNUP_STEPS).toEqual(['account', 'about', 'phone', 'verify']);
    expect(SIGNUP_STEP_COUNT).toBe(4);
    expect(signup).toContain('label="Mobile number"');
    expect(nextStep('account')).toBe('about');
    expect(nextStep('about')).toBe('phone');
    expect(nextStep('phone')).toBe('verify');
    expect(nextStep('verify')).toBe('verify');   // terminal
    expect(prevStep('phone')).toBe('about');
    expect(canGoBack('account')).toBe(false);    // the account already exists
    expect(canGoBack('about')).toBe(false);
    expect(canGoBack('phone')).toBe(true);
  });

  it('the 18+ gate and the legal disclosure still gate account creation', () => {
    expect(validateAccountStep('a@b.co', 'secret1', false))
      .toBe('You must confirm you are 18 or older to use Snatch It.');
    expect(validateAccountStep('a@b.co', 'short', true)).toBe('Password must be at least 6 characters.');
    expect(validateAccountStep('', '', true)).toBe('Please enter your email and password.');
    expect(validateAccountStep('a@b.co', 'secret1', true)).toBeNull();
    expect(signup).toContain('disabled={loading || !ageConfirmed}');
    expect(signup).toContain('Terms of Service');
    expect(signup).toContain('Privacy Policy');
  });
});

describe('4. the mobile verification is real and server-authoritative', () => {
  it('uses the provider contract the shipped verify-phone screen already uses', () => {
    expect(signup).toContain('supabase.auth.updateUser({ phone: e164 })');
    expect(signup).toContain("supabase.auth.verifyOtp({ phone: e164, token: code.trim(), type: 'phone_change' })");
    // the same contract, so there is one phone-verification path in the product
    expect(read('app/settings/verify-phone.tsx')).toContain("type: 'phone_change'");
  });

  it('nothing marks a number verified in client state', () => {
    expect(signupCode).not.toMatch(/setVerified\(|phone_confirmed|verified\s*=\s*true/);
    expect(signupCode).not.toMatch(/twilio|fetch\(|axios/i);   // no side-channel SMS
  });

  it('a six digit code is required, and a bad one stops the flow before any write', () => {
    expect(validateCodeStep('12345')).toBe('Enter the 6-digit code from the text message.');
    expect(validateCodeStep('123456')).toBeNull();
    const handler = signup.slice(signup.indexOf('async function verifyAndFinish'), signup.indexOf('async function persistProfile'));
    const guardAt = handler.indexOf('if (error) {');
    const persistAt = handler.indexOf('await persistProfile()');
    expect(guardAt).toBeGreaterThan(-1);
    expect(persistAt).toBeGreaterThan(guardAt);
    expect(handler.slice(guardAt, persistAt)).toContain('return;');
  });

  it('the profile is written only after the provider accepted the code', () => {
    const handler = signup.slice(signup.indexOf('async function verifyAndFinish'), signup.indexOf('async function persistProfile'));
    expect(handler.indexOf('verifyOtp')).toBeLessThan(handler.indexOf('await persistProfile()'));
  });
});

describe('5. exactly three gender options', () => {
  it('the labels are exactly MALE, FEMALE and PREFER NOT TO SAY', () => {
    expect(GENDER_OPTIONS.map((o) => o.label)).toEqual(['MALE', 'FEMALE', 'PREFER NOT TO SAY']);
    expect(GENDER_OPTIONS).toHaveLength(3);
  });

  it('no icon, emoji or explanatory paragraph rides along', () => {
    const select = read('src/components/auth/GenderSelect.tsx');
    expect(select).not.toMatch(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u);
    expect(select).not.toMatch(/<Image|IconButton|icon=/);
    expect(stripComments(select)).not.toMatch(/textStyle\('body'\)/);  // no paragraph
  });

  it('the selector is one accessible choice, built from the V2 chip', () => {
    const select = read('src/components/auth/GenderSelect.tsx');
    expect(select).toContain('accessibilityRole="radiogroup"');
    expect(select).toContain("from '@/src/components/ui'");
    expect(select).toContain('<Chip');
  });

  it('gender is required before the step can advance', () => {
    expect(validateAboutStep('Jose', null)).toBe('Select an option to continue.');
  });
});

describe('6 & 7. canonical storage, and no duplicate fields', () => {
  it('name and phone go to the profile columns Edit profile already writes', () => {
    expect(signup).toContain(".from('profiles')");
    expect(signup).toContain('display_name: name.trim()');
    expect(signup).toContain('phone_number: normalizeUSPhone(phone)');
    const editProfile = read('app/settings/edit-profile.tsx');
    expect(editProfile).toContain('display_name:');
    expect(editProfile).toContain('phone_number:');
  });

  it('gender goes through the deployed kernel demographics RPC', () => {
    expect(signup).toContain("rpc('set_my_demographics'");
    expect(signup).toContain('p_gender_identity: gender');
    expect(signup).toContain('p_notice_version: DEMOGRAPHIC_NOTICE_VERSION');
    expect(DEMOGRAPHIC_NOTICE_VERSION.trim().length).toBeGreaterThan(0);  // the RPC rejects an empty one
  });

  it('every stored gender value is one the deployed check constraint accepts', () => {
    const migration = read('supabase/migrations/077_kernel_identity_orgs_and_roles.sql');
    const accepted = ['woman', 'man', 'non_binary', 'another_gender_identity', 'prefer_not_to_say'];
    // the vocabulary is read off the migration, so a change there fails this test
    for (const value of accepted) expect(migration).toContain(`'${value}'`);
    for (const option of GENDER_OPTIONS) expect(accepted).toContain(option.value);
  });

  it('no second home for any of these fields is introduced', () => {
    // the profiles write carries exactly the two columns that already own this data
    const update = signupCode.slice(signupCode.indexOf(".from('profiles')"));
    const payload = update.slice(update.indexOf('.update({'), update.indexOf('})') + 2);
    expect(payload).toContain('display_name');
    expect(payload).toContain('phone_number');
    expect(payload).not.toMatch(/gender|email|full_name|first_name|last_name/);
    // no shadow copy anywhere else, and no schema work from the front end
    expect(signupCode).not.toMatch(/AsyncStorage|SecureStore/);
    expect(signupCode).not.toMatch(/create table|alter table|create policy/i);
  });
});

describe('8. the verified number lands on the right account', () => {
  it('the profile write is scoped to the signed-in user', () => {
    expect(signup).toContain('const { data: { user } } = await supabase.auth.getUser()');
    expect(signup).toContain(".eq('id', user.id)");
    expect(signup).toContain('if (!user) return;');
  });

  it('the phone becomes part of the authenticated identity, not just a profile string', () => {
    // updateUser + verifyOtp set auth.users.phone / phone_confirmed_at, which is
    // what the phone sign-in path later looks up
    expect(signup).toContain('supabase.auth.updateUser({ phone: e164 })');
    expect(signup).toContain('toE164US(phone)');
  });

  it('the demographics RPC is owner scoped by the database, not by an argument', () => {
    const migration = read('supabase/migrations/077_kernel_identity_orgs_and_roles.sql');
    expect(migration).toContain('create or replace function kernel.set_my_demographics(p_gender_identity text, p_notice_version text)');
    expect(migration).toContain('security definer');
    expect(signupCode).not.toMatch(/set_my_demographics'[\s\S]{0,200}p_identity_id|p_user_id/);
  });
});

describe('9. existing auth behaviour is intact', () => {
  it('account creation is still email and password through signUp', () => {
    expect(signup).toContain("options: { emailRedirectTo: 'snatchit://' }");
    expect(signup).toContain('friendlyAuthError(error.message)');
  });

  it('a project that requires email confirmation still ends the way it always did', () => {
    expect(signup).toContain('if (!data.session)');
    expect(signup).toContain('Account created. Check your email to confirm, then sign in.');
    expect(signup).toContain("setStep('check_email')");
    expect(stepIndex('check_email')).toBe(-1);   // an exit, not a numbered step
  });

  it('reset password is untouched', () => {
    const reset = read('app/(auth)/reset-password.tsx');
    expect(reset).toContain('supabase.auth.updateUser({ password })');
    expect(reset).toContain('<AuthScreen>');
  });

  it('the root redirect is held only while signup is mid flow, and always released', () => {
    expect(layout).toContain('useIsOnboarding');
    // the hold now lives in the root routing policy, which refuses to navigate
    // while it is raised (see tests/auth-verification-paths.test.ts)
    expect(layout).toContain('onboarding,');
    expect(rootRouteDecision({
      loading: false, isRecovery: false, onboarding: true,
      phase: 'signed_in:u1', lastRoutedPhase: 'signed_out',
    })).toEqual({ navigate: false, reason: 'onboarding' });
    expect(signup).toContain('setOnboarding(true)');
    // released on success, on failure, and on unmount
    expect((signup.match(/setOnboarding\(false\)/g) ?? []).length).toBeGreaterThanOrEqual(3);
    expect(signup).toContain('useEffect(() => () => {');
  });

  it('the gate changes routing only: it grants nothing and touches no session', () => {
    expect(stripComments(gate)).not.toMatch(/supabase|session|token|role|permission/i);
    const effect = layout.slice(layout.indexOf('rootRouteDecision({'), layout.indexOf('}, [session, loading, isRecovery, onboarding]);'));
    expect(effect).toContain('router.replace(decision.to)');
    expect(effect).not.toMatch(/signOut|setSession/);
  });
});

describe('copy discipline', () => {
  it('no em dash and no provider jargon reaches the person', () => {
    const visible = signup.match(/"[A-Z][^"]{6,}"|>[A-Z][^<>{}]{10,}</g) ?? [];
    for (const line of visible) {
      expect(line).not.toMatch(/—/);
      expect(line).not.toMatch(/supabase|gotrue|otp_|rpc|postgres/i);
    }
  });
});
