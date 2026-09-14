/**
 * src/lib/push/registrationStatus.ts — what the rest of the app may know about
 * push registration: enough for Settings to explain a device that is not
 * registered, and nothing secret.
 */

import type { RegistrationErrorKind, RpcOutcome } from './registration';

export type RegistrationStatus =
  | { state: 'idle' }
  | { state: 'registered'; method: 'rpc' | 'legacy'; outcome: RpcOutcome; at: number }
  | { state: 'failed'; kind: RegistrationErrorKind; at: number }
  | { state: 'waiting'; kind: RegistrationErrorKind; retryAt: number | null };

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
