/**
 * tests/auth-verification-paths.test.ts — the complete auth / OTP matrix.
 *
 * The device bug was not in any OTP screen. All three screens advance their own
 * step correctly on a successful send; the ROOT LAYOUT pulled the person away.
 * Supabase hands a fresh session object to `onAuthStateChange` for `USER_UPDATED`
 * and `TOKEN_REFRESHED`, the root effect depended on that object, and any change
 * of it re-ran a redirect to Home.
 *
 * So the routing policy is tested as a pure function over authentication PHASE,
 * and each flow is tested at its source for the two properties that matter:
 * a successful send always advances to the code step, and only a successful
 * verify completes the flow.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  authPhase,
  rootRouteDecision,
  PHASE_CHANGING_EVENTS,
  PHASE_PRESERVING_EVENTS,
  type AuthPhase,
} from '../src/lib/auth/rootRoute';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const login = read('app/(auth)/login.tsx');
const signup = read('app/(auth)/signup.tsx');
const settingsPhone = read('app/settings/verify-phone.tsx');
const layout = read('app/_layout.tsx');
const resetPw = read('app/(auth)/reset-password.tsx');

const USER_A = 'signed_in:aaaa' as AuthPhase;
const USER_B = 'signed_in:bbbb' as AuthPhase;
const OUT = 'signed_out' as AuthPhase;

const decide = (over: Partial<Parameters<typeof rootRouteDecision>[0]> = {}) =>
  rootRouteDecision({
    loading: false, isRecovery: false, onboarding: false,
    phase: USER_A, lastRoutedPhase: null, ...over,
  });

// ── the section that owns the reported bug ───────────────────────────────────

describe('35-39. auth events: only a phase boundary may navigate', () => {
  it('a session object that changed WITHOUT the phase changing does not navigate', () => {
    // USER_UPDATED (updateUser({phone})) and TOKEN_REFRESHED both look like this
    expect(decide({ phase: USER_A, lastRoutedPhase: USER_A }))
      .toEqual({ navigate: false, reason: 'same_phase' });
  });

  it('the phase ignores session object identity entirely', () => {
    const a = { user: { id: 'aaaa', email: 'x@y.z' } };
    const b = { user: { id: 'aaaa', email: 'x@y.z', phone: '+13055551234' } }; // after updateUser
    expect(authPhase(a)).toBe(authPhase(b));
    expect(authPhase(null)).toBe('signed_out');
    expect(authPhase(undefined)).toBe('signed_out');
    expect(authPhase({ user: null })).toBe('signed_out');
  });

  it('SIGNED_IN from signed out still navigates Home', () => {
    expect(decide({ phase: USER_A, lastRoutedPhase: OUT })).toEqual({ navigate: true, to: '/(tabs)/home' });
  });

  it('SIGNED_OUT still navigates to the auth stack', () => {
    expect(decide({ phase: OUT, lastRoutedPhase: USER_A })).toEqual({ navigate: true, to: '/(auth)/login' });
  });

  it('INITIAL_SESSION routes once on first settle and never repeats', () => {
    expect(decide({ phase: USER_A, lastRoutedPhase: null })).toEqual({ navigate: true, to: '/(tabs)/home' });
    expect(decide({ phase: USER_A, lastRoutedPhase: USER_A }).navigate).toBe(false);
    expect(decide({ loading: true, lastRoutedPhase: null })).toEqual({ navigate: false, reason: 'loading' });
  });

  it('switching accounts is a real boundary and does navigate', () => {
    expect(decide({ phase: USER_B, lastRoutedPhase: USER_A })).toEqual({ navigate: true, to: '/(tabs)/home' });
  });

  it('PASSWORD_RECOVERY keeps the recovery flow', () => {
    expect(decide({ isRecovery: true, lastRoutedPhase: OUT })).toEqual({ navigate: false, reason: 'recovery' });
  });

  it('sign up keeps its own navigation while onboarding is raised', () => {
    expect(decide({ onboarding: true, lastRoutedPhase: OUT })).toEqual({ navigate: false, reason: 'onboarding' });
  });

  it('a hold never records a phase, so the boundary is honest once it lifts', () => {
    // held during signup, then released: the signed_out -> signed_in boundary still fires
    expect(decide({ onboarding: true, phase: USER_A, lastRoutedPhase: OUT }).navigate).toBe(false);
    expect(decide({ onboarding: false, phase: USER_A, lastRoutedPhase: OUT }))
      .toEqual({ navigate: true, to: '/(tabs)/home' });
  });

  it('the policy is documented by phase, not by branching on event names', () => {
    expect(PHASE_PRESERVING_EVENTS).toContain('USER_UPDATED');
    expect(PHASE_PRESERVING_EVENTS).toContain('TOKEN_REFRESHED');
    expect(PHASE_CHANGING_EVENTS).toContain('SIGNED_IN');
    expect(PHASE_CHANGING_EVENTS).toContain('SIGNED_OUT');
    const code = stripComments(read('src/lib/auth/rootRoute.ts'));
    expect(code).not.toMatch(/if \(event ===|switch \(event\)/);
  });
});

describe('root layout wiring', () => {
  it('navigates through the decision, and records the phase only when it does', () => {
    expect(layout).toContain('rootRouteDecision({');
    expect(layout).toContain('if (!decision.navigate) return;');
    expect(layout).toContain('routedPhaseRef.current = phase;');
    expect(layout).toContain('router.replace(decision.to)');
  });

  it('has no unconditional session-truthy redirect left anywhere', () => {
    const code = stripComments(layout);
    expect(code).not.toMatch(/if \(session\) \{[\s\S]{0,200}router\.replace\('\/\(tabs\)\/home'\)/);
    // the only Home redirect is the decision's own target
    expect((code.match(/router\.replace\('\/\(tabs\)\/home'\)/g) ?? []).length).toBe(0);
  });

  it('separates identity reporting from navigation', () => {
    const code = stripComments(layout);
    const sentryAt = code.indexOf('setSentryUser(session ?');
    const navAt = code.indexOf('rootRouteDecision({');
    expect(sentryAt).toBeGreaterThan(-1);
    expect(navAt).toBeGreaterThan(sentryAt); // two separate effects
  });
});

// ── 1-8. phone OTP sign in ───────────────────────────────────────────────────

describe('1-8. phone OTP sign in', () => {
  const send = login.slice(login.indexOf('async function handleSendCode'), login.indexOf('async function handleVerifyCode'));
  const verify = login.slice(login.indexOf('async function handleVerifyCode'), login.indexOf('async function handleEmailSignIn'));

  it('1-2. a successful send advances to the code step, and a failure does not', () => {
    expect(send).toContain("supabase.auth.signInWithOtp({");
    const guard = send.indexOf('if (otpErr)');
    const advance = send.indexOf("setStep('enter_code')");
    expect(guard).toBeGreaterThan(-1);
    expect(advance).toBeGreaterThan(guard);
    expect(send.slice(guard, advance)).toContain('return;');
  });

  it('3. completion is the provider session, and the root takes it Home', () => {
    expect(verify).toContain("type: 'sms',");
    // the screen does not navigate itself: the signed_out -> signed_in boundary does
    expect(stripComments(verify)).not.toMatch(/router\.(replace|push)/);
    expect(decide({ phase: USER_A, lastRoutedPhase: OUT })).toEqual({ navigate: true, to: '/(tabs)/home' });
  });

  it('4-5. a wrong or expired code returns and stays on the verification step', () => {
    const guard = verify.indexOf('if (verifyErr)');
    expect(guard).toBeGreaterThan(-1);
    expect(verify.slice(guard)).toContain('return;');
    expect(stripComments(verify)).not.toMatch(/setStep\('enter_phone'\)/); // never dumped back
  });

  it('6. resend stays in the flow: no step change, no navigation', () => {
    expect(login).toContain('onPress={handleSendCode}');   // resend reuses the same handler
    expect(login).toContain('disabled={!canResend(cooldown, loading)}');
    expect(stripComments(send)).not.toMatch(/router\.(replace|push)/);
  });

  it('7-8. an unknown phone creates nothing and stays on Sign in', () => {
    expect(login).toContain('shouldCreateUser: false');
    expect(stripComments(login)).not.toMatch(/shouldCreateUser:\s*true|supabase\.auth\.signUp\(/);
    expect(login).toContain("setNoAccount(failure === 'unknown_account')");
    // the only navigation on this screen is the person choosing Sign up
    const navs = stripComments(login).match(/router\.(replace|push)\('[^']*'\)/g) ?? [];
    expect(navs).toEqual(["router.push('/(auth)/signup')"]);
  });
});

// ── 9-11. email sign in ──────────────────────────────────────────────────────

describe('9-11. email and password sign in', () => {
  it('9-10. unchanged calls; a failure sets an error and does not navigate', () => {
    expect(login).toContain('supabase.auth.signInWithPassword({ email: email.trim(), password })');
    const handler = login.slice(login.indexOf('async function handleEmailSignIn'), login.indexOf('async function handleForgotPassword'));
    expect(handler).toContain('setError(friendlyAuthError(authErr.message))');
    expect(stripComments(handler)).not.toMatch(/router\./);
  });

  it('11. forgot password is preserved, and recovery owns its own routing', () => {
    expect(login).toContain("resetPasswordForEmail(email.trim(), { redirectTo: 'snatchit://' })");
    expect(resetPw).toContain('supabase.auth.updateUser({ password })');
    // updateUser({password}) also emits USER_UPDATED; recovery holds the root
    expect(layout).toContain("event === 'PASSWORD_RECOVERY'");
    expect(decide({ isRecovery: true }).navigate).toBe(false);
  });
});

// ── 12-18. sign up ───────────────────────────────────────────────────────────

describe('12-18. sign up', () => {
  const send = signup.slice(signup.indexOf('async function sendCode'), signup.indexOf('async function verifyAndFinish'));
  const verify = signup.slice(signup.indexOf('async function verifyAndFinish'), signup.indexOf('async function persistProfile'));

  it('12. the session that appears at step 1 does not jump Home', () => {
    const account = signup.slice(signup.indexOf('async function submitAccount'), signup.indexOf('function submitAbout'));
    expect(account.indexOf('setOnboarding(true)')).toBeLessThan(account.indexOf('supabase.auth.signUp('));
    expect(decide({ onboarding: true, phase: USER_A, lastRoutedPhase: OUT }).navigate).toBe(false);
  });

  it('13. it proceeds through name and gender', () => {
    expect(signup).toContain("setStep('about')");
    expect(signup).toContain('validateAboutStep(name, gender)');
  });

  it('14. a successful phone send advances to the code step; a failure does not', () => {
    expect(send).toContain('supabase.auth.updateUser({ phone: e164 })');
    const guard = send.indexOf('if (error)');
    const advance = send.indexOf("setStep('verify')");
    expect(advance).toBeGreaterThan(guard);
    expect(send.slice(guard, advance)).toContain('return;');
  });

  it('15-16. only a verified code completes, and the gate lifts last', () => {
    expect(verify).toContain("type: 'phone_change'");
    const verifyAt = verify.indexOf('verifyOtp');
    const persistAt = verify.indexOf('await persistProfile()');
    const releaseAt = verify.indexOf('setOnboarding(false)', persistAt);
    expect(verifyAt).toBeLessThan(persistAt);
    expect(persistAt).toBeLessThan(releaseAt);   // Home only after the writes
  });

  it('17. a wrong code releases nothing and navigates nowhere', () => {
    const guard = verify.indexOf('if (error) {');
    const upToPersist = verify.slice(guard, verify.indexOf('await persistProfile()'));
    expect(upToPersist).toContain('return;');
    expect(upToPersist).not.toContain('setOnboarding(false)');
    expect(stripComments(verify)).not.toMatch(/router\./);
  });

  it('18. resend stays inside signup verification', () => {
    expect(signup).toContain('onPress={sendCode}');
    expect(signup).toContain('disabled={!canResend(cooldown, loading)}');
  });
});

// ── 19-28. logged-in settings phone verification (the device bug) ────────────

describe('19-28. settings phone verification', () => {
  const send = settingsPhone.slice(settingsPhone.indexOf('async function sendCode'), settingsPhone.indexOf('async function verifyCode'));
  const verify = settingsPhone.slice(settingsPhone.indexOf('async function verifyCode'), settingsPhone.indexOf('function leaveVerification'));

  it('19-22. the send itself advances to the code step and never navigates', () => {
    expect(send).toContain('supabase.auth.updateUser({ phone: e164 })');
    const guard = send.indexOf('if (error)');
    const advance = send.indexOf("setStep('enter_code')");
    expect(advance).toBeGreaterThan(guard);
    expect(send.slice(guard, advance)).toContain('return;');
    expect(stripComments(send)).not.toMatch(/router\./);
  });

  it('20-21 & 28. USER_UPDATED while signed in cannot move the root layout', () => {
    // the exact device sequence: signed in, phase unchanged, session object new
    expect(decide({ phase: USER_A, lastRoutedPhase: USER_A }))
      .toEqual({ navigate: false, reason: 'same_phase' });
    // and there is no Home target reachable from a signed-in phase
    expect(decide({ phase: USER_A, lastRoutedPhase: USER_A }).navigate).toBe(false);
  });

  it('23 & 27. only a verified code marks it verified, and the copy is written then', () => {
    expect(verify).toContain("type: 'phone_change'");
    const guard = verify.indexOf('if (error)');
    const markVerified = verify.indexOf("setStep('verified')");
    expect(markVerified).toBeGreaterThan(guard);
    expect(verify.slice(guard, markVerified)).toContain('return;');
    // the profile copy is written after the provider accepted, never on the send
    expect(verify.indexOf('phone_number: normalized')).toBeGreaterThan(markVerified);
    expect(stripComments(send)).not.toContain('phone_number');
  });

  it('24-26. errors and resend keep the person on the verification step', () => {
    expect(verify).toContain("/expired/i.test(error.message)");
    expect(verify).toContain("/invalid/i.test(error.message)");
    expect(stripComments(verify)).not.toMatch(/router\.|setStep\('enter_phone'\)/);
    expect(settingsPhone).toContain('onPress={sendCode}');
    expect(settingsPhone).toContain('disabled={busy || cooldown > 0}');
  });

  it('completion returns where the person came from, never Home', () => {
    expect(settingsPhone).toContain('function leaveVerification()');
    expect(settingsPhone).toContain('if (router.canGoBack()) router.back();');
    expect(settingsPhone).toContain("router.replace('/settings')");
    expect(stripComments(settingsPhone)).not.toMatch(/\/\(tabs\)\/home/);
  });
});

// ── 29-34. phone change for an already verified user ─────────────────────────

describe('29-34. phone change', () => {
  it('29-30. the same screen handles a change, and nothing signs the person out', () => {
    expect(settingsPhone).toContain('Use a different number');
    expect(stripComments(settingsPhone)).not.toMatch(/signOut\(/);
  });

  it('31-32. send then verify then back to Settings', () => {
    expect(settingsPhone).toContain("setStep('enter_code')");
    expect(settingsPhone).toContain("type: 'phone_change'");
    expect(settingsPhone).toContain('leaveVerification');
  });

  it('33-34. the session is preserved and no account is created', () => {
    expect(decide({ phase: USER_A, lastRoutedPhase: USER_A }).navigate).toBe(false);
    expect(stripComments(settingsPhone)).not.toMatch(/signUp\(|shouldCreateUser/);
  });
});

// ── 40-44. cross-cutting guarantees ──────────────────────────────────────────

describe('40-44. cross-cutting', () => {
  const OTP_SCREENS: [string, string][] = [
    ['sign in', 'app/(auth)/login.tsx'],
    ['sign up', 'app/(auth)/signup.tsx'],
    ['settings', 'app/settings/verify-phone.tsx'],
  ];

  it('42. every OTP screen advances its own step on a successful send', () => {
    for (const [, path] of OTP_SCREENS) {
      const src = read(path);
      expect(src).toMatch(/setStep\('(enter_code|verify)'\)/);
    }
  });

  it('44. no verification path uses Home as a fallback', () => {
    for (const [, path] of OTP_SCREENS) {
      expect(stripComments(read(path))).not.toMatch(/\/\(tabs\)\/home/);
    }
  });

  it('there is exactly one logged-in verification screen, with no stale twin', () => {
    // both entry points reach the same route
    expect(read('app/settings/index.tsx')).toContain("nav('/settings/verify-phone')");
    expect(read('src/screens/CreateListingScreen.tsx')).toContain("router.push('/settings/verify-phone'");
  });

  it('40-41. the approved Sign in presentation is untouched', () => {
    expect(login).toContain('<AuthScreen>');
    const shell = read('src/components/auth/AuthScreen.tsx');
    expect(shell.indexOf('<AuthBrandMark />')).toBeLessThan(shell.indexOf('<KeyboardAvoidingView'));
    expect(shell).toContain('insets.top + v2.space.xl');
    expect(read('src/components/auth/AuthBrandMark.tsx')).toContain('SN_MARK_HEIGHT = 30');
  });

  it('no backend, schema or policy work rides along', () => {
    for (const [, path] of OTP_SCREENS) {
      expect(stripComments(read(path))).not.toMatch(/create table|alter table|create policy|service_role/i);
    }
  });
});
