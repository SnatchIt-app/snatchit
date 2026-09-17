/**
 * F-611C-2 — a live challenge is re-requested only from a real background, and the
 * server's challenge rate limit is a wait, not a permanent refusal.
 *
 * Evidence (Build 18 = aad5f75, S2-1 step 2 seller sign-in on the buyer's handset,
 * A's read-back 2026-09-18 03:54:43Z): register_push_token was called four times in
 * 75 s — 03:50:52 (200 challenge_required), 03:50:57 (200), 03:51:41 (200), 03:52:07
 * (400 'too many challenge requests') — request_push_token_challenge never, and the
 * 03:54 relaunch made no register call at all.
 *
 * Root causes, from source:
 *  RC1  the AppState 'active' handler ignored `onForeground().reRequest` and ran
 *       `attempt()` on every 'active' event, including iOS inactive → active (shade,
 *       system prompt, Face ID). With a challenge open nothing is persisted, so each
 *       run re-registered; 135 re-issues a live challenge in place (fresh nonce, same
 *       row) and counts it against push_challenge_token (3 / 600 s).
 *  RC2  `classifyRegistrationError` knew only 'too many registration attempts'; 135's
 *       challenge path raises 'precondition_failed: too many challenge requests', which
 *       fell through to 'precondition' — decideRegistration's deterministic, never
 *       retried refusal — and had no remedy copy, so Settings showed nothing.
 *  RC3  every challenge_required reply replaced the open challenge with
 *       `beginChallenge()` (elapsedMs 0), restarting the cumulative 60 s visible-code
 *       budget that `fallbackDelayMs` is specified to resume (D mutant, 2026-09-16).
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  beginChallenge, CHALLENGE_FALLBACK_MS, fallbackDelayMs, isChallengeOpen, onBackground, onForeground,
  resumeChallenge, shouldReattemptOnForeground, type ChallengeInfo, type ChallengeState,
} from '@/src/lib/push/challenge';
import { classifyRegistrationError, decideRegistration, RATE_LIMIT_WAIT_MS, REGISTRATION_REMEDY } from '@/src/lib/push/registration';

const read = (p: string) => readFileSync(resolve(__dirname, '..', p), 'utf8');
const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

const T0 = 1_700_000_000_000;
const info: ChallengeInfo = { id: 'ch-1', mode: 'silent', expires_in_s: 300 };
type AwaitingPush = Extract<ChallengeState, { phase: 'awaiting_push' }>;

describe('RC1 — an open challenge is re-requested only from a real background', () => {
  it('open = awaiting the push, awaiting the code, or confirming', () => {
    expect(isChallengeOpen(beginChallenge(info, T0, true))).toBe(true);
    expect(isChallengeOpen(beginChallenge({ ...info, mode: 'visible' }, T0, true))).toBe(true);
    expect(isChallengeOpen({ phase: 'confirming', challengeId: 'ch-1', via: 'push' })).toBe(true);
    expect(isChallengeOpen({ phase: 'none' })).toBe(false);
    expect(isChallengeOpen({ phase: 'confirmed', tokenId: 't' })).toBe(false);
    expect(isChallengeOpen({ phase: 'failed', kind: 'expired', challengeId: 'ch-1' })).toBe(false);
  });

  it("iOS inactive → active with the challenge still in the foreground does NOT reach the register verb", () => {
    const open = beginChallenge(info, T0, true);
    const r = onForeground(open, T0 + 5_000);
    expect(r.reRequest).toBe(false);
    expect(shouldReattemptOnForeground(r)).toBe(false);
  });

  it('a real background → foreground re-requests the same open challenge', () => {
    const open = beginChallenge(info, T0, true);
    const bg = onBackground(open, T0 + 10_000);
    const r = onForeground(bg, T0 + 40_000);
    expect(r.reRequest).toBe(true);
    expect(shouldReattemptOnForeground(r)).toBe(true);
  });

  it('a visible challenge or a confirm in flight is never re-registered from a foreground event', () => {
    const code = beginChallenge({ ...info, mode: 'visible' }, T0, true);
    expect(shouldReattemptOnForeground(onForeground(code, T0 + 1))).toBe(false);
    const confirming: ChallengeState = { phase: 'confirming', challengeId: 'ch-1', via: 'code' };
    expect(shouldReattemptOnForeground(onForeground(confirming, T0 + 1))).toBe(false);
  });

  it('no open challenge → the usual foreground attempt (registered → skip; failed → retry)', () => {
    for (const st of [
      { phase: 'none' } as ChallengeState,
      { phase: 'confirmed', tokenId: 't' } as ChallengeState,
      { phase: 'failed', kind: 'exhausted', challengeId: 'ch-1' } as ChallengeState,
    ]) {
      expect(shouldReattemptOnForeground(onForeground(st, T0 + 1))).toBe(true);
    }
    // An expired open challenge is failed on foreground and then re-attempted (P3-1: fresh challenge).
    const expired = onForeground(beginChallenge(info, T0, true), T0 + 300_001);
    expect(expired.state.phase).toBe('failed');
    expect(shouldReattemptOnForeground(expired)).toBe(true);
  });

  it("hook: the 'active' branch gates attempt() on shouldReattemptOnForeground(r)", () => {
    const h = stripComments(read('src/hooks/usePushToken.ts'));
    const active = h.indexOf("if (st === 'active') {");
    expect(active).toBeGreaterThan(-1);
    const guard = h.indexOf('if (!shouldReattemptOnForeground(r)) return;', active);
    expect(guard).toBeGreaterThan(active);
    const fg = h.indexOf('const r = onForeground(challengeRef.current, Date.now());', active);
    expect(fg).toBeGreaterThan(active);
    expect(guard).toBeGreaterThan(fg);
    const attempt = h.indexOf('void attempt();', active);
    expect(attempt).toBeGreaterThan(guard);
    const branchEnd = h.indexOf("if (st === 'background') {", active);
    expect(branchEnd).toBeGreaterThan(attempt);
    // The fallback is re-armed before the gate, so a held challenge keeps its timer.
    const rearm = h.indexOf("if (r.state.phase === 'awaiting_push' && token) armFallback(token);", active);
    expect(rearm).toBeGreaterThan(fg);
    expect(rearm).toBeLessThan(guard);
  });
});

describe('RC2 — 135\'s challenge-path rate limit classifies as rate_limited, waits, and is visible', () => {
  const CHALLENGE_TEXT = 'precondition_failed: too many challenge requests';
  const REGISTER_TEXT = 'precondition_failed: too many registration attempts';

  it('both rate-limit texts are raised by 135 (guard against a reworded server)', () => {
    const sql = read('supabase/migrations/135_push_token_proof_of_possession.sql');
    expect(sql).toContain(`raise exception '${CHALLENGE_TEXT}' using errcode = 'P0001'`);
    expect(sql).toContain(`raise exception '${REGISTER_TEXT}' using errcode = 'P0001'`);
    // The challenge text is raised inside register_push_token's body, not only in request_push_token_challenge.
    const reg = sql.indexOf('create or replace function public.register_push_token(');
    const req = sql.indexOf('create or replace function public.request_push_token_challenge(');
    expect(reg).toBeGreaterThan(-1);
    expect(req).toBeGreaterThan(reg);
    expect(sql.slice(reg, req)).toContain(CHALLENGE_TEXT);
  });

  it('both texts → rate_limited; other precondition_failed texts still → precondition', () => {
    expect(classifyRegistrationError({ code: 'P0001', message: CHALLENGE_TEXT })).toBe('rate_limited');
    expect(classifyRegistrationError({ code: 'P0001', message: REGISTER_TEXT })).toBe('rate_limited');
    expect(classifyRegistrationError({ code: 'P0001', message: 'precondition_failed: no binding to challenge — register instead' })).toBe('precondition');
  });

  it('rate_limited waits out the server window and then registers; precondition never retries', () => {
    const base = { userId: 'u', token: 't', method: 'rpc' as const, at: T0, attempts: 1 };
    const limited = decideRegistration({ userId: 'u', token: 't', record: null, failure: { ...base, kind: 'rate_limited' }, rpcAvailable: true, now: T0 + 1_000 });
    expect(limited).toEqual({ action: 'wait', method: 'rpc', reason: 'backoff', retryAt: T0 + RATE_LIMIT_WAIT_MS });
    const after = decideRegistration({ userId: 'u', token: 't', record: null, failure: { ...base, kind: 'rate_limited' }, rpcAvailable: true, now: T0 + RATE_LIMIT_WAIT_MS });
    expect(after).toEqual({ action: 'register', method: 'rpc', reason: 'retry' });
    const permanent = decideRegistration({ userId: 'u', token: 't', record: null, failure: { ...base, kind: 'precondition' }, rpcAvailable: true, now: T0 + 24 * 3_600_000 });
    expect(permanent).toEqual({ action: 'wait', method: 'rpc', reason: 'precondition' });
  });

  it('a rate-limited device says so in Settings (no silent wait) and promises only the automatic retry', () => {
    const copy = REGISTRATION_REMEDY.rate_limited;
    expect(typeof copy).toBe('string');
    expect(copy).toMatch(/too many/i);
    expect(copy).toMatch(/retr(y|ies|ied)/i);
    expect(copy).not.toMatch(/contact support|reinstall|sign out/i);
  });
});

describe('RC3 — a re-issued challenge resumes the 60 s budget; only a different challenge begins fresh', () => {
  it('same id, silent: elapsed foreground time is kept and only the expiry is refreshed', () => {
    const open = beginChallenge(info, T0, true) as AwaitingPush;
    const bg = onBackground(open, T0 + 40_000) as AwaitingPush;             // 40 s banked
    const back = onForeground(bg, T0 + 90_000).state as AwaitingPush;        // startedAt = T0 + 90 s
    const reissued = resumeChallenge(back, { ...info, expires_in_s: 300 }, T0 + 95_000, true) as AwaitingPush;
    expect(reissued.phase).toBe('awaiting_push');
    expect(reissued.challengeId).toBe('ch-1');
    expect(reissued.elapsedMs).toBe(40_000);
    expect(reissued.startedAt).toBe(T0 + 90_000);
    expect(reissued.foreground).toBe(true);
    expect(reissued.expiresAt).toBe(T0 + 95_000 + 300_000);
    // 40 s banked + 5 s since the foreground: 15 s of the 60 s budget remain.
    expect(fallbackDelayMs(reissued, T0 + 95_000)).toBe(CHALLENGE_FALLBACK_MS - 45_000);
  });

  it('a different id, a visible mode, or no open challenge begins fresh', () => {
    const open = beginChallenge(info, T0, true);
    expect(resumeChallenge(open, { ...info, id: 'ch-2' }, T0 + 30_000, true)).toEqual(beginChallenge({ ...info, id: 'ch-2' }, T0 + 30_000, true));
    expect(resumeChallenge(open, { ...info, mode: 'visible' }, T0 + 30_000, true)).toEqual(beginChallenge({ ...info, mode: 'visible' }, T0 + 30_000, true));
    expect(resumeChallenge({ phase: 'none' }, info, T0, true)).toEqual(beginChallenge(info, T0, true));
    expect(resumeChallenge({ phase: 'failed', kind: 'expired', challengeId: 'ch-1' }, info, T0, false)).toEqual(beginChallenge(info, T0, false));
  });

  it('hook: challenge_required resumes the open challenge instead of beginning a new state', () => {
    const h = stripComments(read('src/hooks/usePushToken.ts'));
    const branch = h.indexOf("result.outcome === 'challenge_required'");
    expect(branch).toBeGreaterThan(-1);
    const next = h.indexOf("setChallenge(resumeChallenge(challengeRef.current, info, now, AppState.currentState === 'active'), token);", branch);
    expect(next).toBeGreaterThan(branch);
    expect(h).not.toContain('setChallenge(beginChallenge(');
  });
});
