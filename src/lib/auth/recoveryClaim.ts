/**
 * src/lib/auth/recoveryClaim.ts — is the PKCE code in a deep link a password-recovery code?
 *
 * The app requests recovery with PKCE and redirectTo 'snatchit://' (login.tsx). GoTrue's redirect after
 * /verify is `snatchit://?code=…`: it carries no `type`, and auth-js's exchangeCodeForSession emits
 * SIGNED_IN, never PASSWORD_RECOVERY. So the link itself cannot say "recovery", and the Redirect URL
 * allowlist holds only the literal `snatchit://` (a marker in the redirect would be an owner-gated
 * auth-config change). Builds 25 and 27 therefore exchanged a recovery link into a plain sign-in and
 * routed to Home (C's audit, 2026-10-15).
 *
 * The device's own evidence is the verifier auth-js stored on THIS installation when
 * resetPasswordForEmail ran: `<verifier>/PASSWORD_RECOVERY` under `<storageKey>-code-verifier`
 * (auth-js 2.98.0, lib/helpers getCodeChallengeAndMethod; read back by _exchangeCodeForSession). Both
 * the format and the client fields read here are pinned against the real GoTrueClient in
 * tests/recovery-claim.test.ts, so an auth-js upgrade that changes them fails CI, not a phone.
 *
 * Read-only: the verifier is never logged, returned or copied — only its suffix is compared. A claim
 * grants nothing: the session still comes only from exchangeCodeForSession (H-5).
 */

export const RECOVERY_REDIRECT_TYPE = 'PASSWORD_RECOVERY';

/** True when a stored verifier value (raw, as the storage adapter returns it) belongs to a recovery request. */
export function verifierIsRecovery(raw: string | null | undefined): boolean {
  if (!raw) return false;
  let value: unknown = raw;
  try {
    value = JSON.parse(raw);   // auth-js stores JSON.stringify(verifier)
  } catch {
    // stored without JSON encoding; compare as is
  }
  return typeof value === 'string' && value.split('/')[1] === RECOVERY_REDIRECT_TYPE;
}

type StorageView = { storageKey?: unknown; storage?: { getItem?: (key: string) => unknown } };

/**
 * Whether the code waiting to be exchanged on this installation is a recovery code. Any failure
 * (no client, locked keychain, nothing stored) is "no": the exchange then runs as an ordinary sign-in.
 */
export async function pendingCodeIsRecovery(auth: unknown): Promise<boolean> {
  try {
    const a = auth as StorageView | null;
    if (!a || typeof a.storageKey !== 'string' || typeof a.storage?.getItem !== 'function') return false;
    const raw = await a.storage.getItem(`${a.storageKey}-code-verifier`);
    return verifierIsRecovery(typeof raw === 'string' ? raw : null);
  } catch {
    return false;
  }
}

/** The late signal: auth-js returns the stored redirect type from exchangeCodeForSession (undocumented field). */
export function exchangeWasRecovery(data: unknown): boolean {
  return (data as { redirectType?: unknown } | null | undefined)?.redirectType === RECOVERY_REDIRECT_TYPE;
}
