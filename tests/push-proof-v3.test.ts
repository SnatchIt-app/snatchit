/**
 * tests/push-proof-v3.test.ts — client v3 for push-token proof of possession
 * (docs/release/PUSH_TOKEN_CONTRACT_V3.md, DRAFT; owner decision b2,
 * 2026-09-16). The challenge lifecycle is pure logic here; the network and the
 * notification listener are injected in the hook.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/src/lib/supabase', () => ({ supabase: { rpc: vi.fn(), from: vi.fn() } }));

import {
  beginChallenge, CHALLENGE_COPY, CHALLENGE_FALLBACK_MS, classifyChallengeError, foregroundElapsedMs, isChallengeExpired, MAX_CODE_ATTEMPTS,
  onBackground, onCodeEntered, onConfirmError, onConfirmOk, onFallbackDue, onForeground, onPushReceived, toCodeEntry,
  type ChallengeState,
} from '@/src/lib/push/challenge';
import { ACCEPTED_REGISTER_CONTRACT_VERSIONS, EXPECTED_CHALLENGE_CONTRACT_VERSION, REGISTRATION_REMEDY } from '@/src/lib/push/registration';
import { registerWithRpc } from '@/src/lib/push/registerToken';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
const T0 = 1_700_000_000_000;
const info = { id: 'ch-1', mode: 'silent' as const, expires_in_s: 300 };

describe('contract v3 reply', () => {
  it('stamping: a challenge is always v3; plain outcomes accept v2 or v3 (the installed base keeps registering)', async () => {
    expect(EXPECTED_CHALLENGE_CONTRACT_VERSION).toBe(3);
    expect([...ACCEPTED_REGISTER_CONTRACT_VERSIONS]).toEqual([2, 3]);
    const r = await registerWithRpc(
      { rpc: async () => ({ data: { token_id: 'tok-1', outcome: 'challenge_required', platform: 'ios', contract_version: 3, challenge: info }, error: null }) },
      { token: 'ExponentPushToken[x]', platform: 'ios', secret: 's'.repeat(32), deviceName: null },
    );
    expect(r).toMatchObject({ ok: true, method: 'rpc', outcome: 'challenge_required', contractVersion: 3, challenge: info });
    const plainV2 = await registerWithRpc(
      { rpc: async () => ({ data: { token_id: 'tok-1', outcome: 'refreshed', platform: 'ios', contract_version: 2 }, error: null }) },
      { token: 'ExponentPushToken[x]', platform: 'ios', secret: 's'.repeat(32), deviceName: null },
    );
    expect(plainV2).toMatchObject({ ok: true, outcome: 'refreshed', contractVersion: 2 });
    const challengeV2 = await registerWithRpc(
      { rpc: async () => ({ data: { token_id: 'tok-1', outcome: 'challenge_required', platform: 'ios', contract_version: 2, challenge: info }, error: null }) },
      { token: 'ExponentPushToken[x]', platform: 'ios', secret: 's'.repeat(32), deviceName: null },
    );
    expect(challengeV2).toEqual({ ok: false, kind: 'contract_mismatch' });
    const v4 = await registerWithRpc(
      { rpc: async () => ({ data: { token_id: 'tok-1', outcome: 'refreshed', platform: 'ios', contract_version: 4 }, error: null }) },
      { token: 'ExponentPushToken[x]', platform: 'ios', secret: 's'.repeat(32), deviceName: null },
    );
    expect(v4).toEqual({ ok: false, kind: 'contract_mismatch' });
  });

  it('has refusal copy for a build that cannot talk to this server', () => {
    expect(REGISTRATION_REMEDY.contract_mismatch).toMatch(/update/i);
  });
});

describe('challenge lifecycle (pure)', () => {
  it('begins awaiting the silent push, expiring per the server', () => {
    const s = beginChallenge(info, T0, true);
    expect(s).toEqual({ phase: 'awaiting_push', challengeId: 'ch-1', startedAt: T0, expiresAt: T0 + 300_000, foreground: true, elapsedMs: 0 });
  });

  it('a matching push moves to confirming and hands back the nonce once; anything else is ignored', () => {
    const s = beginChallenge(info, T0, true);
    const wrongType = onPushReceived(s, { type: 'outbid', challenge_id: 'ch-1', nonce: 'n' });
    expect(wrongType).toEqual({ state: s, nonce: null });
    const wrongId = onPushReceived(s, { type: 'push_token_challenge', challenge_id: 'ch-2', nonce: 'n' });
    expect(wrongId).toEqual({ state: s, nonce: null });
    const ok = onPushReceived(s, { type: 'push_token_challenge', challenge_id: 'ch-1', nonce: 'the-nonce' });
    expect(ok.nonce).toBe('the-nonce');
    expect(ok.state).toEqual({ phase: 'confirming', challengeId: 'ch-1', via: 'push' });
    expect(JSON.stringify(ok.state)).not.toContain('the-nonce');
  });

  it('the 60 s fallback is due only while foregrounded, before expiry', () => {
    const s = beginChallenge(info, T0, true) as Extract<ChallengeState, { phase: 'awaiting_push' }>;
    expect(CHALLENGE_FALLBACK_MS).toBe(60_000);
    expect(onFallbackDue(s, T0 + 59_999)).toBe(false);
    expect(onFallbackDue(s, T0 + 60_000)).toBe(true);
    expect(onFallbackDue({ ...s, foreground: false }, T0 + 60_000)).toBe(false);
    expect(onFallbackDue(s, T0 + 300_001)).toBe(false);
    expect(isChallengeExpired(s, T0 + 300_001)).toBe(true);
  });

  it('code entry: six digits only; a wrong code costs an attempt; the last failure is terminal', () => {
    const s = toCodeEntry(beginChallenge(info, T0, true)) as Extract<ChallengeState, { phase: 'awaiting_code' }>;
    expect(s).toEqual({ phase: 'awaiting_code', challengeId: 'ch-1', expiresAt: T0 + 300_000, attemptsLeft: MAX_CODE_ATTEMPTS, lastError: null });
    expect(onCodeEntered(s, '12345')).toEqual({ state: s, nonce: null });
    expect(onCodeEntered(s, '12a456')).toEqual({ state: s, nonce: null });
    const c = onCodeEntered(s, ' 123456 ');
    expect(c.nonce).toBe('123456');
    expect(c.state).toEqual({ phase: 'confirming', challengeId: 'ch-1', via: 'code' });
    type Code = Extract<ChallengeState, { phase: 'awaiting_code' }>;
    let st = onConfirmError(c.state, 'nonce_mismatch', s) as Code;
    expect(st).toEqual({ ...s, attemptsLeft: MAX_CODE_ATTEMPTS - 1, lastError: 'nonce_mismatch' });
    for (let i = 0; i < MAX_CODE_ATTEMPTS - 2; i++) st = onConfirmError({ phase: 'confirming', challengeId: 'ch-1', via: 'code' }, 'nonce_mismatch', st) as Code;
    expect(st.attemptsLeft).toBe(1);
    const last = onConfirmError({ phase: 'confirming', challengeId: 'ch-1', via: 'code' }, 'nonce_mismatch', st);
    expect(last).toEqual({ phase: 'failed', kind: 'exhausted', challengeId: 'ch-1' });
  });

  it('confirm outcomes: rebound → confirmed; expired/consumed/exhausted/other_session/session_stale → failed', () => {
    const confirming: ChallengeState = { phase: 'confirming', challengeId: 'ch-1', via: 'push' };
    expect(onConfirmOk(confirming, 'tok-1')).toEqual({ phase: 'confirmed', tokenId: 'tok-1' });
    for (const k of ['expired', 'consumed', 'exhausted', 'other_session', 'session_stale', 'rate_limited'] as const) {
      expect(onConfirmError(confirming, k, null)).toEqual({ phase: 'failed', kind: k, challengeId: 'ch-1' });
    }
  });

  it('P3-3: the 60 s is cumulative foreground time — a background pauses it, a resume continues it, inactive never touches it', () => {
    const s = beginChallenge(info, T0, true) as Extract<ChallengeState, { phase: 'awaiting_push' }>;
    const bg = onBackground(s, T0 + 20_000) as Extract<ChallengeState, { phase: 'awaiting_push' }>;
    expect(bg).toEqual({ ...s, foreground: false, elapsedMs: 20_000 });
    expect(onFallbackDue(bg, T0 + 90_000)).toBe(false);
    const back = onForeground(bg, T0 + 90_000);
    expect(back).toEqual({ state: { ...bg, foreground: true, startedAt: T0 + 90_000 }, reRequest: true });
    expect(foregroundElapsedMs(back.state, T0 + 120_000)).toBe(50_000);
    expect(onFallbackDue(back.state, T0 + 129_999)).toBe(false);
    expect(onFallbackDue(back.state, T0 + 130_000)).toBe(true);
    // Already foregrounded (an iOS `inactive` blip never called onBackground): a no-op, clock untouched.
    expect(onForeground(s, T0 + 30_000)).toEqual({ state: s, reRequest: false });
    expect(onBackground(bg, T0 + 95_000)).toEqual(bg);
  });

  it('foreground after a real background re-requests the same challenge; after expiry it starts over', () => {
    const s = beginChallenge(info, T0, true) as Extract<ChallengeState, { phase: 'awaiting_push' }>;
    const bg: ChallengeState = { ...s, foreground: false };
    const back = onForeground(bg, T0 + 30_000);
    expect(back).toEqual({ state: { ...s, foreground: true, startedAt: T0 + 30_000 }, reRequest: true });
    const late = onForeground(bg, T0 + 300_001);
    expect(late).toEqual({ state: { phase: 'failed', kind: 'expired', challengeId: 'ch-1' }, reRequest: false });
    expect(onForeground({ phase: 'none' }, T0)).toEqual({ state: { phase: 'none' }, reRequest: false });
  });

  it('classifies the confirm/request errors by the contract\'s exact texts', () => {
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: challenge expired' })).toBe('expired');
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: challenge consumed' })).toBe('consumed');
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: challenge attempts exhausted' })).toBe('exhausted');
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: nonce mismatch' })).toBe('nonce_mismatch');
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: too many challenge requests' })).toBe('rate_limited');
    expect(classifyChallengeError({ code: '42501', message: 'insufficient_privilege: challenge belongs to another session' })).toBe('other_session');
    expect(classifyChallengeError({ code: '42501', message: 'insufficient_privilege: session predates a credential change' })).toBe('session_stale');
    expect(classifyChallengeError({ code: '42501', message: 'not_authenticated' })).toBe('auth');
    expect(classifyChallengeError({ message: 'Network request failed' })).toBe('network');
    expect(classifyChallengeError({ code: 'XX', message: '?' })).toBe('unknown');
  });

  it('copy: never asks the user to share the code, and names every terminal state', () => {
    expect(CHALLENGE_COPY.codePrompt).toMatch(/never share this code/i);
    expect(CHALLENGE_COPY.pending).toMatch(/confirming/i);
    expect(CHALLENGE_COPY.wrongCode(2)).toMatch(/2 attempts left/);
    expect(CHALLENGE_COPY.wrongCode(1)).toMatch(/1 attempt left/);
    for (const k of ['expired', 'consumed', 'exhausted', 'other_session', 'session_stale', 'rate_limited', 'auth', 'network', 'unknown'] as const) {
      expect(typeof CHALLENGE_COPY.failed[k]).toBe('string');
    }
  });
});

describe('wiring (source contract)', () => {
  it('the hook starts a challenge on challenge_required, echoes the foreground push, falls back after 60 s foregrounded, and re-requests on foreground', () => {
    const h = stripComments(read('src/hooks/usePushToken.ts'));
    expect(h).toContain("result.outcome === 'challenge_required'");
    expect(h).toContain('addNotificationReceivedListener');
    expect(h).toContain('onPushReceived(');
    expect(h).toContain('onFallbackDue(');
    expect(h).toContain('onForeground(');
    expect(h).toContain("if (st === 'background') {");
    expect(h).not.toContain("st === 'inactive'");
    expect(h).not.toMatch(/console\.(log|warn)\([^)]*nonce/);
  });

  it('the network deps carry confirm and request; no UIBackgroundModes was added', () => {
    const r = stripComments(read('src/lib/push/registerToken.ts'));
    expect(r).toContain("supabase.rpc('confirm_push_token_challenge', { p_challenge_id: challengeId, p_nonce: nonce })");
    expect(r).toContain("supabase.rpc('request_push_token_challenge', { p_token: token, p_device_secret: secret, p_mode: 'visible' })");
    expect(r).not.toMatch(/console\.(log|warn)\([^)]*secret/);
    expect(read('app.json')).not.toContain('UIBackgroundModes');
  });

  it('Settings › Notifications shows the pending state and a six-digit code entry with the never-share line', () => {
    const n = stripComments(read('app/settings/notifications.tsx'));
    expect(n).toContain("challenge.phase === 'awaiting_code'");
    expect(n).toContain('CHALLENGE_COPY.codePrompt');
    expect(n).toContain('maxLength={6}');
    expect(n).toContain('submitChallengeCode(');
  });
});
