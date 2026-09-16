/**
 * src/lib/push/registrationStatus.ts — what the rest of the app may know about
 * push registration: enough for Settings to explain a device that is not
 * registered, and nothing secret.
 */

import type { ChallengeState } from './challenge';
import type { RegistrationErrorKind, RpcOutcome } from './registration';

export type RegistrationStatus =
  | { state: 'idle' }
  | { state: 'registered'; method: 'rpc' | 'legacy'; outcome: RpcOutcome; at: number }
  | { state: 'failed'; kind: RegistrationErrorKind; at: number }
  | { state: 'waiting'; kind: RegistrationErrorKind; retryAt: number | null }
  // v3: a proof-of-possession challenge is open for this device (nothing bound yet).
  | { state: 'challenge'; challenge: ChallengeState; at: number };

let current: RegistrationStatus = { state: 'idle' };
const listeners = new Set<(s: RegistrationStatus) => void>();

export function publishRegistrationStatus(next: RegistrationStatus): void {
  current = next;
  for (const l of listeners) l(next);
}

export function getRegistrationStatus(): RegistrationStatus {
  return current;
}

export function subscribeRegistrationStatus(l: (s: RegistrationStatus) => void): () => void {
  listeners.add(l);
  return () => { listeners.delete(l); };
}

// ── v3: what Settings › Notifications may ask the registration hook to do ──
// The hook owns the challenge; the screen only submits a code or asks for a
// fresh attempt. Handlers are set while the hook is mounted.
let codeHandler: ((code: string) => Promise<void>) | null = null;
let retryHandler: (() => void) | null = null;

export function setChallengeHandlers(h: { submitCode: (code: string) => Promise<void>; retry: () => void } | null): void {
  codeHandler = h?.submitCode ?? null;
  retryHandler = h?.retry ?? null;
}

/** Echo a typed 6-digit code for the open challenge. Resolves when the hook has handled it. */
export async function submitChallengeCode(code: string): Promise<void> {
  if (codeHandler) await codeHandler(code);
}

/** Start registration over (after a failed or expired challenge). */
export function requestRegistrationRetry(): void {
  retryHandler?.();
}
