/**
 * tests/auth-forms.test.ts — auth validation + error mapping, plus source guards
 * that the auth screens still call the real Supabase paths.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { validateLogin, validateSignup, validateReset, friendlyAuthError } from '../src/lib/auth/authForms';

describe('login validation', () => {
  it('requires both fields', () => {
    expect(validateLogin('', '')).toMatch(/email and password/);
    expect(validateLogin('a@b.co', '')).toMatch(/email and password/);
    expect(validateLogin('a@b.co', 'pw')).toBeNull();
  });
});

describe('signup validation — order preserved', () => {
  it('fields, then 6-char floor, then the 18+ gate', () => {
    expect(validateSignup('', '', false)).toMatch(/email and password/);
    expect(validateSignup('a@b.co', '123', false)).toMatch(/at least 6/);
    expect(validateSignup('a@b.co', '123456', false)).toMatch(/18 or older/);
    expect(validateSignup('a@b.co', '123456', true)).toBeNull();
  });
});

describe('reset validation', () => {
  it('requires both fields and a match', () => {
    expect(validateReset('', '')).toMatch(/required/);
    expect(validateReset('abcdef', 'abcxyz')).toMatch(/do not match/);
    expect(validateReset('abcdef', 'abcdef')).toBeNull();
  });
});

describe('friendlyAuthError', () => {
  it('passes through known auth messages', () => {
    expect(friendlyAuthError('Invalid login credentials')).toBe('Invalid login credentials');
    expect(friendlyAuthError('Email not confirmed')).toBe('Email not confirmed');
  });
  it('generalises technical / internal strings', () => {
    expect(friendlyAuthError('fetch failed: network error')).toMatch(/went wrong/i);
    expect(friendlyAuthError('null value in column "x" violates')).toMatch(/went wrong/i);
    expect(friendlyAuthError('')).toMatch(/went wrong/i);
  });
});

describe('auth screens — shipped-source guards', () => {
  const root = resolve(__dirname, '..');
  const read = (rel: string) => readFileSync(resolve(root, rel), 'utf8');
  const login = read('app/(auth)/login.tsx');
  const signup = read('app/(auth)/signup.tsx');
  const reset = read('app/(auth)/reset-password.tsx');

  it('login keeps sign-in + forgot-password with the deep-link redirect', () => {
    expect(login).toContain('signInWithPassword');
    expect(login).toContain('resetPasswordForEmail');
    expect(login).toContain("redirectTo: 'snatchit://'");
    expect(login).toContain('friendlyAuthError(');
  });

  it('signup keeps signUp, the email redirect, the 18+ gate and legal links', () => {
    expect(signup).toContain('auth.signUp');
    expect(signup).toContain("emailRedirectTo: 'snatchit://'");
    expect(signup).toContain('ageConfirmed');
    expect(signup).toContain("accessibilityRole=\"checkbox\"");
    expect(signup).toContain('/settings/legal');
    expect(signup).toContain('/settings/privacy');
    // the create button stays gated on the age confirmation
    expect(signup).toMatch(/disabled=\{loading \|\| !ageConfirmed\}/);
  });

  it('reset keeps updateUser + sign out + return to login', () => {
    expect(reset).toContain('updateUser({ password })');
    expect(reset).toContain('auth.signOut()');
    expect(reset).toContain("router.replace('/(auth)/login')");
  });
});
