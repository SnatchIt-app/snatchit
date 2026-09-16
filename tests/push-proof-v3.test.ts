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
  fallbackDelayMs, interpretConfirmReply, onBackground, onCodeEntered, onConfirmError, onConfirmOk, onConsumed, onFallbackDue, onForeground, onPushReceived, onStaleNonce, onVisibleIssued, onWrongCode, retryPlan, toCodeEntry,
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

  it('re-arming the fallback resumes the 60 s where it left off, never restarts it (D mutant: flat 60 s survived)', () => {
    const s = beginChallenge(info, T0, true);
    expect(fallbackDelayMs(s, T0)).toBe(CHALLENGE_FALLBACK_MS);
    expect(fallbackDelayMs(s, T0 + 45_000)).toBe(15_000);
    expect(fallbackDelayMs(s, T0 + 60_000)).toBe(0);
    expect(fallbackDelayMs(s, T0 + 90_000)).toBe(0);
    // banked time from before a background counts too
    const bg = onBackground(s, T0 + 20_000);
    const back = onForeground(bg, T0 + 100_000).state;
    expect(fallbackDelayMs(back, T0 + 125_000)).toBe(15_000);
    expect(fallbackDelayMs({ phase: 'none' }, T0)).toBe(CHALLENGE_FALLBACK_MS);
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

  it('a 200 from confirm is a bind only when it says rebound; nonce_mismatch and challenge_consumed are not', () => {
    expect(interpretConfirmReply({ outcome: 'rebound', token_id: 'tok-1', contract_version: 3 })).toEqual({ kind: 'rebound', tokenId: 'tok-1' });
    expect(interpretConfirmReply({ outcome: 'nonce_mismatch', attempts_left: 3 })).toEqual({ kind: 'nonce_mismatch', attemptsLeft: 3 });
    expect(interpretConfirmReply({ outcome: 'challenge_consumed' })).toEqual({ kind: 'consumed' });
    expect(interpretConfirmReply({ outcome: 'stale_nonce', token_id: 'tok-1' })).toEqual({ kind: 'stale' });
    expect(interpretConfirmReply({ ok: true })).toEqual({ kind: 'unknown' });
    expect(interpretConfirmReply(null)).toEqual({ kind: 'unknown' });
    expect(interpretConfirmReply({ outcome: 'registered' })).toEqual({ kind: 'unknown' });
  });

  it('a wrong code in a 200 uses the server\'s attempts_left when given, else the local counter; zero is exhausted', () => {
    const prior = toCodeEntry(beginChallenge(info, T0, true)) as Extract<ChallengeState, { phase: 'awaiting_code' }>;
    const confirming: ChallengeState = { phase: 'confirming', challengeId: 'ch-1', via: 'code' };
    expect(onWrongCode(confirming, prior, 2)).toEqual({ ...prior, attemptsLeft: 2, lastError: 'nonce_mismatch' });
    expect(onWrongCode(confirming, prior, null)).toEqual({ ...prior, attemptsLeft: MAX_CODE_ATTEMPTS - 1, lastError: 'nonce_mismatch' });
    expect(onWrongCode(confirming, prior, 0)).toEqual({ phase: 'failed', kind: 'exhausted', challengeId: 'ch-1' });
    expect(onWrongCode({ phase: 'confirming', challengeId: 'ch-1', via: 'push' }, null, 4)).toEqual({ phase: 'failed', kind: 'nonce_mismatch', challengeId: 'ch-1' });
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
    // A's final list (135 @ ac716da): a missing row is as good as consumed; a gone binding or a
    // request that should have been a register are told to register instead — never a bind.
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: challenge not found' })).toBe('consumed');
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: binding no longer exists' })).toBe('register_instead');
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: no binding to challenge — register instead' })).toBe('register_instead');
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: the caller already owns this binding — register instead' })).toBe('register_instead');
    expect(classifyChallengeError({ message: 'Network request failed' })).toBe('network');
    expect(classifyChallengeError({ code: 'XX', message: '?' })).toBe('unknown');
    // CV-1 (D): a timed-out or aborted request is not evidence the device is offline — the
    // network copy says "check your connection", so these fall to unknown, not network.
    expect(classifyChallengeError({ message: 'Request timed out' })).toBe('unknown');
    expect(classifyChallengeError({ message: 'timeout of 10000ms exceeded' })).toBe('unknown');
    expect(classifyChallengeError({ message: 'AbortError: The operation was aborted' })).toBe('unknown');
    // CV-2 (D): the register limit can surface on the request path too (20 / 10 min).
    expect(classifyChallengeError({ code: 'P0001', message: 'precondition_failed: too many registration attempts' })).toBe('rate_limited');
  });

  it('copy: never asks the user to share the code, and names every terminal state', () => {
    expect(CHALLENGE_COPY.codePrompt).toMatch(/never share this code/i);
    expect(CHALLENGE_COPY.pending).toMatch(/confirming/i);
    expect(CHALLENGE_COPY.wrongCode(2)).toMatch(/2 attempts left/);
    expect(CHALLENGE_COPY.wrongCode(1)).toMatch(/1 attempt left/);
    for (const k of ['expired', 'consumed', 'exhausted', 'other_session', 'session_stale', 'rate_limited', 'auth', 'network', 'unknown', 'stale_nonce', 'register_instead'] as const) {
      expect(typeof CHALLENGE_COPY.failed[k]).toBe('string');
    }
    // P3-1 (A): "Try again" always gets a new code, so the dead-challenge states say so.
    for (const k of ['expired', 'consumed', 'exhausted'] as const) expect(CHALLENGE_COPY.failed[k]).toMatch(/Try again/);
    expect(CHALLENGE_COPY.staleCode).toMatch(/latest notification/i);
    expect(CHALLENGE_COPY.staleCode).not.toMatch(/didn't match|wrong/i);
  });
});

describe("A's rulings on 135 (2026-09-16): stale echo is free, Try again gets a fresh challenge", () => {
  const push = beginChallenge(info, T0, true) as Extract<ChallengeState, { phase: 'awaiting_push' }>;
  const code = toCodeEntry(push) as Extract<ChallengeState, { phase: 'awaiting_code' }>;

  it('stale_nonce on the push path is neutral: back to the same awaiting_push state, clock intact, no attempt, no failure', () => {
    const confirming: ChallengeState = { phase: 'confirming', challengeId: 'ch-1', via: 'push' };
    expect(onStaleNonce(confirming, push)).toEqual(push);
  });

  it('stale_nonce on the code path returns to code entry with no attempt spent and says the code was replaced', () => {
    const confirming: ChallengeState = { phase: 'confirming', challengeId: 'ch-1', via: 'code' };
    expect(onStaleNonce(confirming, code)).toEqual({ ...code, lastError: 'stale_nonce' });
    // nothing to go back to → not a bind, not silent: a terminal that Try again recovers
    expect(onStaleNonce(confirming, null)).toEqual({ phase: 'failed', kind: 'unknown', challengeId: 'ch-1' });
  });

  it('challenge_consumed after a typed code is "too many wrong codes"; on the push path it is consumed', () => {
    expect(onConsumed({ phase: 'confirming', challengeId: 'ch-1', via: 'code' })).toEqual({ phase: 'failed', kind: 'exhausted', challengeId: 'ch-1' });
    expect(onConsumed({ phase: 'confirming', challengeId: 'ch-1', via: 'push' })).toEqual({ phase: 'failed', kind: 'consumed', challengeId: 'ch-1' });
  });

  it('a visible-code reply that carries a fresh challenge replaces the id and expiry (P3-1); without one, the same row switches to code entry', () => {
    const fresh = { outcome: 'challenge_required', challenge: { id: 'ch-2', mode: 'visible', expires_in_s: 300 } };
    expect(onVisibleIssued(push, fresh, T0 + 70_000)).toEqual({ phase: 'awaiting_code', challengeId: 'ch-2', expiresAt: T0 + 370_000, attemptsLeft: MAX_CODE_ATTEMPTS, lastError: null });
    const dead: ChallengeState = { phase: 'failed', kind: 'exhausted', challengeId: 'ch-1' };
    expect(onVisibleIssued(dead, fresh, T0 + 70_000)).toEqual({ phase: 'awaiting_code', challengeId: 'ch-2', expiresAt: T0 + 370_000, attemptsLeft: MAX_CODE_ATTEMPTS, lastError: null });
    expect(onVisibleIssued(push, { ok: true }, T0 + 70_000)).toEqual(toCodeEntry(push));
    // a dead challenge with no fresh id in the reply cannot be revived
    expect(onVisibleIssued(dead, { ok: true }, T0 + 70_000)).toEqual({ phase: 'failed', kind: 'unknown', challengeId: 'ch-1' });
  });

  it('Try again from a dead challenge asks for a fresh visible code; from anything else it registers again', () => {
    for (const k of ['exhausted', 'expired', 'consumed'] as const) expect(retryPlan({ phase: 'failed', kind: k, challengeId: 'ch-1' })).toBe('visible');
    for (const k of ['register_instead', 'network', 'auth', 'rate_limited', 'other_session', 'session_stale', 'unknown', 'nonce_mismatch', 'stale_nonce'] as const) {
      expect(retryPlan({ phase: 'failed', kind: k, challengeId: 'ch-1' })).toBe('register');
    }
    expect(retryPlan({ phase: 'none' })).toBe('register');
  });
});

describe('wiring (source contract)', () => {
  it('the hook starts a challenge on challenge_required, echoes the foreground push, falls back after 60 s foregrounded, and re-requests on foreground', () => {
    const h = stripComments(read('src/hooks/usePushToken.ts'));
    expect(h).toContain("result.outcome === 'challenge_required'");
    expect(h).toContain('addNotificationReceivedListener');
    expect(h).toContain('onPushReceived(');
    expect(h).toContain('onFallbackDue(');
    // the timer is armed from the pure remaining-time helper; the hook never does its own 60 s arithmetic
    expect(h).toContain('const delay = fallbackDelayMs(st, Date.now());');
    expect(h).not.toContain('CHALLENGE_FALLBACK_MS');
    // A 200 that is not `rebound` must never reach `confirmed` or write a record.
    expect(h).toContain('const reply = interpretConfirmReply(r.data);');
    expect(h).toContain("if (reply.kind !== 'rebound') {");
    expect(h.indexOf("if (reply.kind !== 'rebound') {")).toBeLessThan(h.indexOf('onConfirmOk(st, reply.tokenId)'));
    expect(h.indexOf('onConfirmOk(st, reply.tokenId)')).toBeLessThan(h.indexOf('await saveRegistrationState({ record, failure: null });', h.indexOf('async function confirm(')));
    // stale_nonce (A's ruling): neutral — restore the prior state and re-arm the fallback; never a record.
    expect(h).toContain("if (reply.kind === 'stale') {");
    expect(h).toContain('onStaleNonce(st, prior)');
    expect(h.indexOf("if (reply.kind === 'stale') {")).toBeLessThan(h.indexOf("if (reply.kind !== 'rebound') {"));
    expect(h).toContain('onConsumed(st)');
    expect(h).toContain('onVisibleIssued(st, r.data, Date.now())');
    expect(h).toContain('retryPlan(challengeRef.current)');
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
    expect(n).toContain("challenge.lastError === 'stale_nonce'");
    expect(n).toContain('CHALLENGE_COPY.staleCode');
  });
});
