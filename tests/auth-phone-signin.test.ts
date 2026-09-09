/**
 * tests/auth-phone-signin.test.ts — Sign in is the phone OTP path.
 *
 * Two kinds of assertion. The pure ones exercise the number format, the mask, the
 * cooldown and the provider-error mapping. The source guards read the shipped
 * screen, because the properties that matter most here are absences: no account is
 * created, no session is fabricated, and the email path is still there.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  canResend,
  classifyOtpError,
  DEFAULT_COUNTRY_CODE,
  DEFAULT_SIGN_IN_METHOD,
  isUnknownAccount,
  maskE164,
  otpErrorCopy,
  RESEND_COOLDOWN_S,
  resendLabel,
  toE164US,
} from '../src/lib/auth/phoneAuth';

const root = resolve(__dirname, '..');
const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
const stripComments = (s: string) =>
  s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

const login = read('app/(auth)/login.tsx');
const loginCode = stripComments(login);

// The provider errors this maps, in the shape supabase-js hands them over.
const ERR_UNKNOWN_PHONE = { code: 'otp_disabled', message: 'Signups not allowed for otp', status: 422 };
const ERR_BAD_CODE      = { code: 'otp_expired', message: 'Token has expired or is invalid', status: 403 };
const ERR_RATE          = { code: 'over_sms_send_rate_limit', message: 'For security purposes, you can only request this after 33 seconds', status: 429 };
const ERR_NETWORK       = { code: null, message: 'Network request failed', status: null };
// The exact payload the project returned on 2026-09-06 when the Twilio account
// behind Supabase Auth was inactive. Pinned so a future edit to the classifier
// cannot quietly turn a real delivery failure into "no account".
const ERR_PROVIDER_DOWN = {
  code: 'sms_send_failed',
  message: 'Error sending confirmation OTP to provider: authentication failed, account AC*** with status 4 is not active',
  status: 422,
};

describe('1. Sign in defaults to the phone number flow', () => {
  it('the default method is phone, not email', () => {
    expect(DEFAULT_SIGN_IN_METHOD).toBe('phone');
  });

  it('the screen opens on the phone method and its first step is the number', () => {
    expect(login).toContain('useState<SignInMethod>(DEFAULT_SIGN_IN_METHOD)');
    expect(login).toContain("useState<PhoneSignInStep>('enter_phone')");
    // the number field is what a returning user meets first
    expect(login).toContain('label="Mobile number"');
    expect(login).toContain('label="Continue"');
  });

  it('does not ask a returning user for name, gender or a second email', () => {
    expect(loginCode).not.toMatch(/label="Name"/);
    expect(loginCode).not.toMatch(/GenderSelect|gender/i);
  });
});

describe('2. a valid existing phone can request a code', () => {
  it('normalises every US format the field accepts into E.164', () => {
    expect(toE164US('3055551234')).toBe('+13055551234');
    expect(toE164US('(305) 555-1234')).toBe('+13055551234');
    expect(toE164US('+1 305 555 1234')).toBe('+13055551234');
    expect(toE164US('13055551234')).toBe('+13055551234');
    expect(DEFAULT_COUNTRY_CODE).toBe('+1');
  });

  it('refuses anything that is not a real US mobile number', () => {
    expect(toE164US('555-1234')).toBeNull();      // too short
    expect(toE164US('1055551234')).toBeNull();    // NANP area code cannot start with 1
    expect(toE164US('3051551234')).toBeNull();    // NANP exchange cannot start with 1
    expect(toE164US('')).toBeNull();
    expect(toE164US(null)).toBeNull();
  });

  it('the screen sends the E.164 value, never the raw field', () => {
    expect(login).toContain('const e164 = toE164US(phone)');
    expect(login).toContain('supabase.auth.signInWithOtp({');
    expect(login).toContain('phone: e164,');
  });
});

describe('3. OTP verification establishes the session', () => {
  it('the session comes from verifyOtp with the sms type', () => {
    expect(login).toContain('supabase.auth.verifyOtp({');
    expect(login).toContain("type: 'sms',");
  });

  it('nothing on this screen manufactures a session of its own', () => {
    expect(loginCode).not.toMatch(/setSession\(|refreshSession\(|admin\.|service_role|signInAnonymously/);
  });

  it('the code is masked back to the person, never echoed in full', () => {
    expect(maskE164('+13055551234')).toBe('••• ••• 1234');
    expect(maskE164('')).toBe('••• ••• ••••');
    expect(login).toContain('maskE164(sentTo)');
  });
});

describe('4 & 5. a wrong or expired code does not authenticate', () => {
  it('classifies both, and neither reads as success', () => {
    expect(classifyOtpError(ERR_BAD_CODE, 'verify')).toBe('expired_code');
    expect(classifyOtpError({ code: null, message: 'Invalid token' }, 'verify')).toBe('wrong_code');
    expect(otpErrorCopy('wrong_code')).toBe("That code didn't match. Check the text and try again.");
    expect(otpErrorCopy('expired_code')).toBe('That code expired. Send a new one.');
  });

  it('the verify handler returns on any provider error before anything else runs', () => {
    const handler = login.slice(login.indexOf('async function handleVerifyCode'), login.indexOf('async function handleEmailSignIn'));
    expect(handler).toMatch(/if \(verifyErr\) \{[\s\S]*?return;\n {4}\}/);
    // the only thing after the guard is the comment about the provider's session
    expect(stripComments(handler).trim().endsWith('}')).toBe(true);
  });

  it('a raw provider string is never what the person reads', () => {
    for (const stage of ['send', 'verify'] as const) {
      const copy = otpErrorCopy(classifyOtpError(ERR_BAD_CODE, stage));
      expect(copy).not.toMatch(/otp_|token|supabase|gotrue|422|403/i);
      expect(copy).not.toMatch(/—/);
    }
  });
});

describe('6. resend respects the cooldown', () => {
  it('the cooldown matches the one already shipped elsewhere', () => {
    expect(RESEND_COOLDOWN_S).toBe(30);
  });

  it('resend is closed while the timer runs or a request is in flight', () => {
    expect(canResend(30, false)).toBe(false);
    expect(canResend(1, false)).toBe(false);
    expect(canResend(0, true)).toBe(false);
    expect(canResend(0, false)).toBe(true);
    expect(resendLabel(12)).toBe('Resend code in 12s');
    expect(resendLabel(0)).toBe('Resend code');
  });

  it('the screen wires the control to that rule and starts the timer on send', () => {
    expect(login).toContain('disabled={!canResend(cooldown, loading)}');
    expect(login).toContain('label={resendLabel(cooldown)}');
    expect(login).toContain('startCooldown();');
  });

  it('rate limiting is reported as a wait, not as a bad code', () => {
    expect(classifyOtpError(ERR_RATE, 'send')).toBe('rate_limited');
    expect(classifyOtpError(ERR_RATE, 'verify')).toBe('rate_limited');
    expect(otpErrorCopy('rate_limited')).toBe('Too many attempts. Wait a few minutes and try again.');
  });
});

describe('7. an unknown phone never silently creates an account', () => {
  it('every sign-in send is explicitly non-creating', () => {
    expect(login).toContain('shouldCreateUser: false');
    expect(loginCode).not.toMatch(/shouldCreateUser:\s*true/);
    // sign in must not reach the account-creating primitives at all
    expect(loginCode).not.toMatch(/supabase\.auth\.signUp\(/);
  });

  it('the provider refusal is recognised and routed to Sign up', () => {
    expect(classifyOtpError(ERR_UNKNOWN_PHONE, 'send')).toBe('unknown_account');
    expect(isUnknownAccount(ERR_UNKNOWN_PHONE)).toBe(true);
    expect(otpErrorCopy('unknown_account')).toBe("This number isn't linked to an account.");
    expect(login).toContain("setNoAccount(failure === 'unknown_account')");
    expect(login).toContain('label="Sign up"');
  });

  it('a send failure never advances to the code step', () => {
    const handler = login.slice(login.indexOf('async function handleSendCode'), login.indexOf('async function handleVerifyCode'));
    const guardAt = handler.indexOf('if (otpErr)');
    const advanceAt = handler.indexOf("setStep('enter_code')");
    expect(guardAt).toBeGreaterThan(-1);
    expect(advanceAt).toBeGreaterThan(guardAt);
    expect(handler.slice(guardAt, advanceAt)).toContain('return;');
  });

  it('network trouble is not mistaken for a missing account', () => {
    expect(classifyOtpError(ERR_NETWORK, 'send')).toBe('network');
    expect(isUnknownAccount(ERR_NETWORK)).toBe(false);
  });

  it('a dead SMS provider reads as a send failure, never as a missing account', () => {
    expect(classifyOtpError(ERR_PROVIDER_DOWN, 'send')).toBe('send_failed');
    expect(isUnknownAccount(ERR_PROVIDER_DOWN)).toBe(false);
    const copy = otpErrorCopy(classifyOtpError(ERR_PROVIDER_DOWN, 'send'));
    expect(copy).toBe("We couldn't send the code. Try again.");
    // the account SID, the provider name and the status code stay out of the copy
    expect(copy).not.toMatch(/twilio|AC[0-9a-f]|account|422|provider/i);
  });
});

describe('8. the email and password path is preserved', () => {
  it('the same two calls the screen has always made are still here', () => {
    expect(login).toContain('supabase.auth.signInWithPassword({ email: email.trim(), password })');
    expect(login).toContain("supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: 'snatchit://' })");
    expect(login).toContain('validateLogin(email, password)');
    expect(login).toContain('friendlyAuthError(');
  });

  it('it is reachable in one tap from the phone step, and back again', () => {
    expect(login).toContain('Use email instead');
    expect(login).toContain('Use mobile number instead');
    expect(login).toContain("switchMethod('email')");
    expect(login).toContain("switchMethod('phone')");
  });
});

describe('9. an existing email-only account is not locked out', () => {
  it('the email form is a complete way in, not a stub', () => {
    const emailBlock = login.slice(login.indexOf("{method === 'email' ?"));
    expect(emailBlock).toContain('label="Email"');
    expect(emailBlock).toContain('label="Password"');
    expect(emailBlock).toContain('label="Sign in"');
    expect(emailBlock).toContain('Forgot password?');
  });

  it('nothing forces a phone number before the email sign-in can be used', () => {
    const handler = login.slice(login.indexOf('async function handleEmailSignIn'), login.indexOf('async function handleForgotPassword'));
    expect(handler).not.toMatch(/phone|otp/i);
  });
});

describe('10 & 11. the SN mark stays where it was', () => {
  it('sign in still renders through the shared shell that pins the mark', () => {
    expect(login).toContain('<AuthScreen>');
    expect(loginCode).not.toContain('sn-logo-white.png');
    expect(loginCode).not.toContain('KeyboardAvoidingView');
  });

  it('the shell still keeps the mark outside the keyboard-responsive region', () => {
    const shell = read('src/components/auth/AuthScreen.tsx');
    expect(shell.indexOf('<AuthBrandMark />')).toBeLessThan(shell.indexOf('<KeyboardAvoidingView'));
    expect(shell).toContain('insets.top + v2.space.xl');
  });
});
