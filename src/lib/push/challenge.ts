/**
 * src/lib/push/challenge.ts — the proof-of-possession challenge, as pure
 * state (contract v3, DRAFT; owner decision b2, 2026-09-16).
 *
 * When `register_push_token` answers `challenge_required`, nothing on the
 * server's row changes: the server sends a one-time nonce TO THIS TOKEN and
 * the device must echo it through `confirm_push_token_challenge`. The nonce
 * is handed to the caller exactly once and is never kept in state, never
 * logged, never sent anywhere else. Silent delivery is foreground-only (no
 * background mode in this build): while backgrounded the clock stops, and on
 * foreground the same open challenge is re-requested (no new nonce) until it
 * expires. If no push arrives within 60 s of foreground time the client asks
 * for a visible-code challenge and the user types the 6-digit code — which
 * IS the nonce in that mode.
 */

import type { ErrorLike } from './registration';

export const CHALLENGE_FALLBACK_MS = 60_000;
export const MAX_CODE_ATTEMPTS = 5;
export const CODE_LENGTH = 6;

export type ChallengeMode = 'silent' | 'visible';
export interface ChallengeInfo { id: string; mode: ChallengeMode; expires_in_s: number }

export type ChallengeErrorKind =
  | 'expired' | 'consumed' | 'exhausted' | 'nonce_mismatch' | 'other_session' | 'session_stale'
  | 'rate_limited' | 'auth' | 'network' | 'unknown';

export type ChallengeState =
  | { phase: 'none' }
  // `elapsedMs` = foreground time already spent before the last background (P3-3: a
  // transient `inactive` — shade, prompt, call — neither pauses nor resets the clock).
  | { phase: 'awaiting_push'; challengeId: string; startedAt: number; expiresAt: number; foreground: boolean; elapsedMs: number }
  | { phase: 'awaiting_code'; challengeId: string; expiresAt: number; attemptsLeft: number; lastError: ChallengeErrorKind | null }
  | { phase: 'confirming'; challengeId: string; via: 'push' | 'code' }
  | { phase: 'confirmed'; tokenId: string | null }
  | { phase: 'failed'; kind: ChallengeErrorKind; challengeId: string | null };

type AwaitingPush = Extract<ChallengeState, { phase: 'awaiting_push' }>;
type AwaitingCode = Extract<ChallengeState, { phase: 'awaiting_code' }>;

export function beginChallenge(info: ChallengeInfo, now: number, foreground: boolean): ChallengeState {
  const expiresAt = now + info.expires_in_s * 1000;
  if (info.mode === 'visible') {
    return { phase: 'awaiting_code', challengeId: info.id, expiresAt, attemptsLeft: MAX_CODE_ATTEMPTS, lastError: null };
  }
  return { phase: 'awaiting_push', challengeId: info.id, startedAt: now, expiresAt, foreground, elapsedMs: 0 };
}

export function isChallengeExpired(state: ChallengeState, now: number): boolean {
  return (state.phase === 'awaiting_push' || state.phase === 'awaiting_code') && now > state.expiresAt;
}

/** The silent push arrived: hand the nonce back once, keep nothing of it. */
export function onPushReceived(state: ChallengeState, data: unknown): { state: ChallengeState; nonce: string | null } {
  if (state.phase !== 'awaiting_push' || !data || typeof data !== 'object') return { state, nonce: null };
  const d = data as Record<string, unknown>;
  if (d.type !== 'push_token_challenge' || d.challenge_id !== state.challengeId || typeof d.nonce !== 'string' || !d.nonce) {
    return { state, nonce: null };
  }
  return { state: { phase: 'confirming', challengeId: state.challengeId, via: 'push' }, nonce: d.nonce };
}

/** 60 s of cumulative foreground time without the push, and the challenge still open. */
export function foregroundElapsedMs(state: ChallengeState, now: number): number {
  if (state.phase !== 'awaiting_push') return 0;
  return state.elapsedMs + (state.foreground ? Math.max(0, now - state.startedAt) : 0);
}

export function onFallbackDue(state: ChallengeState, now: number): boolean {
  if (state.phase !== 'awaiting_push' || !state.foreground) return false;
  if (now > state.expiresAt) return false;
  return foregroundElapsedMs(state, now) >= CHALLENGE_FALLBACK_MS;
}

export function toCodeEntry(state: ChallengeState): ChallengeState {
  if (state.phase !== 'awaiting_push') return state;
  return { phase: 'awaiting_code', challengeId: state.challengeId, expiresAt: state.expiresAt, attemptsLeft: MAX_CODE_ATTEMPTS, lastError: null };
}

/** Six digits, whitespace trimmed; anything else is not sent. */
export function onCodeEntered(state: ChallengeState, code: string): { state: ChallengeState; nonce: string | null } {
  if (state.phase !== 'awaiting_code') return { state, nonce: null };
  const trimmed = code.trim();
  if (!new RegExp(`^\\d{${CODE_LENGTH}}$`).test(trimmed)) return { state, nonce: null };
  return { state: { phase: 'confirming', challengeId: state.challengeId, via: 'code' }, nonce: trimmed };
}

export function onConfirmOk(state: ChallengeState, tokenId: string | null): ChallengeState {
  if (state.phase !== 'confirming') return state;
  return { phase: 'confirmed', tokenId };
}

/**
 * A wrong code costs an attempt and returns to code entry while attempts
 * remain (`prior` is the code-entry state to return to); everything else is
 * terminal for this challenge.
 */
export function onConfirmError(state: ChallengeState, kind: ChallengeErrorKind, prior: AwaitingCode | null): ChallengeState {
  const challengeId = state.phase === 'confirming' ? state.challengeId : prior?.challengeId ?? null;
  if (kind === 'nonce_mismatch' && prior && state.phase === 'confirming' && state.via === 'code') {
    const left = prior.attemptsLeft - 1;
    if (left <= 0) return { phase: 'failed', kind: 'exhausted', challengeId };
    return { ...prior, attemptsLeft: left, lastError: 'nonce_mismatch' };
  }
  return { phase: 'failed', kind, challengeId };
}

/**
 * Back in the foreground after a real background: resume the clock where it
 * paused and re-request the same open challenge (the server re-dispatches, no
 * new nonce), or start over if it expired. Already foregrounded → no-op.
 */
export function onForeground(state: ChallengeState, now: number): { state: ChallengeState; reRequest: boolean } {
  if (state.phase !== 'awaiting_push') return { state, reRequest: false };
  if (now > state.expiresAt) return { state: { phase: 'failed', kind: 'expired', challengeId: state.challengeId }, reRequest: false };
  if (state.foreground) return { state, reRequest: false };
  const next: AwaitingPush = { ...state, foreground: true, startedAt: now };
  return { state: next, reRequest: true };
}

/** A real background (not iOS `inactive`): bank the foreground time so far and pause. */
export function onBackground(state: ChallengeState, now: number): ChallengeState {
  if (state.phase !== 'awaiting_push' || !state.foreground) return state;
  return { ...state, foreground: false, elapsedMs: state.elapsedMs + Math.max(0, now - state.startedAt) };
}

/** Contract v3 §4/§5 texts, exact. */
export function classifyChallengeError(err: ErrorLike | null | undefined): ChallengeErrorKind {
  if (!err) return 'unknown';
  const code = (err.code ?? '').toString();
  const msg = (err.message ?? '').toLowerCase();
  if (code === 'P0001') {
    if (/challenge expired/.test(msg)) return 'expired';
    if (/challenge consumed/.test(msg)) return 'consumed';
    if (/challenge attempts exhausted/.test(msg)) return 'exhausted';
    if (/nonce mismatch/.test(msg)) return 'nonce_mismatch';
    if (/too many challenge requests/.test(msg)) return 'rate_limited';
  }
  if (code === '42501') {
    if (/not_authenticated/.test(msg)) return 'auth';
    if (/challenge belongs to another session/.test(msg)) return 'other_session';
    if (/session predates a credential change/.test(msg)) return 'session_stale';
  }
  if (code === 'PGRST301' || err.status === 401 || /jwt|not authenticated|invalid claim/.test(msg)) return 'auth';
  if (/network request failed|failed to fetch|timeout|timed out|abort/.test(msg)) return 'network';
  return 'unknown';
}

export const CHALLENGE_COPY = {
  pending: 'Confirming this device for notifications…',
  codePrompt: 'Enter the 6-digit code from the notification we just sent to this phone. Never share this code.',
  requestingCode: 'No confirmation arrived. Sending a code to this phone instead…',
  confirmed: 'This device is confirmed for notifications.',
  wrongCode: (left: number) => `That code didn't match. ${left} ${left === 1 ? 'attempt' : 'attempts'} left.`,
  failed: {
    expired: 'The confirmation expired. Open Settings › Notifications again to start over.',
    consumed: 'This confirmation was already used. Start over from Settings › Notifications.',
    exhausted: 'Too many wrong codes. Tap Try again to get a new code.',
    nonce_mismatch: "That code didn't match.",
    other_session: 'This confirmation was started from a different session. Sign in again and retry.',
    session_stale: 'You were signed out on this device. Sign in again to keep notifications on.',
    rate_limited: 'Too many confirmation attempts. Try again in about 10 minutes.',
    auth: 'Sign in again to confirm notifications on this device.',
    network: "Couldn't reach the server. Check your connection and try again.",
    unknown: "Couldn't confirm this device. Try again later.",
  } satisfies Record<ChallengeErrorKind, string>,
};
