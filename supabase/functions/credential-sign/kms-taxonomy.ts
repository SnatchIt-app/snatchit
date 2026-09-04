/**
 * supabase/functions/credential-sign/kms-taxonomy.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * The PURE, IMPORT-FREE pieces of the KMS provider adapter — same pattern as
 * `credential.ts`: zero imports, no network, no WebCrypto, no Deno/Node-
 * specific API, so it type-checks cleanly under `npm run typecheck` AND can
 * be imported directly by `tests/credential-sign-kms.test.ts`.
 *
 * WHY THIS FILE EXISTS (separate from `kms.ts`)
 *   `kms.ts` is the Deno-only adapter: SigV4-over-`fetch` transport,
 *   WebCrypto (`crypto.subtle`) for HMAC/SHA-256, and a `./credential.ts`
 *   import written with the `.ts` extension Deno requires. The root
 *   `tsconfig.json` excludes `supabase/functions` from its OWN root-file
 *   glob, but `tests/**` is NOT excluded — so the moment a test imported
 *   `kms.ts` (even indirectly), `tsc -p .` was forced to type-check it too,
 *   and failed on both counts: `TS5097` (a `.ts`-suffixed import needs
 *   `allowImportingTsExtensions`, which this project does not enable) and
 *   `TS2345`/`TS2769` (a `Uint8Array<ArrayBufferLike>` vs `BufferSource`
 *   strictness tightening in recent `lib.dom.d.ts`, around the
 *   `crypto.subtle` calls). `index.ts` has the exact same two patterns and
 *   was NEVER a problem, because no test imports it — this file's whole
 *   purpose is to let `kms.ts` stay that same kind of Deno-only, untested-
 *   by-tsc shell, while every DECISION worth unit-testing (error taxonomy,
 *   algorithm mapping, env/credential fail-closed checks, response
 *   validation) lives here instead, importable by both sides.
 *
 * `SigningAlgorithm` is intentionally DUPLICATED from `credential.ts`
 * rather than imported — even `import type {...} from './credential.ts'`
 * trips the same `TS5097`. It is a frozen, DB-pinned 2-value enum
 * (migration 103's `check (algorithm in ('EdDSA','ES256'))`) — this
 * duplication is not a drift risk, and TypeScript compares string-literal
 * unions structurally, so this type and `credential.ts`'s are freely
 * interchangeable at every call site that crosses the two modules.
 * ═══════════════════════════════════════════════════════════════════════════
 */

export type SigningAlgorithm = 'EdDSA' | 'ES256';

// ─────────────────────────────────────────────────────────────────────────
// The KMS error taxonomy (index.ts §8) — three classes, never conflated:
//   TRANSIENT — timeout, throttle, 5xx, temporarily unavailable. Retryable
//     (503 + Retry-After).
//   PERMANENT/OPERATOR — access denied, key disabled/pending-deletion,
//     unknown key, wrong-alg-for-provider, invalid key usage, or ANY
//     misconfiguration (missing env, missing credentials). Not retryable
//     without operator action (500, alert, no Retry-After).
//   SECURITY — a response that contradicts what was requested: wrong
//     algorithm came back, the KMS response's key id doesn't match the
//     handle asked for. Fail closed, alert loudly, never retry blindly.
// ─────────────────────────────────────────────────────────────────────────

export type KmsErrorClass = 'transient' | 'permanent' | 'security';

export class KmsSignError extends Error {
  readonly errorClass: KmsErrorClass;
  constructor(message: string, errorClass: KmsErrorClass) {
    super(message);
    this.name = 'KmsSignError';
    this.errorClass = errorClass;
  }
}

export interface KmsSigner {
  /** Returns the JWS-raw signature (64 bytes for ES256's `R||S`; Ed25519
   *  signatures are already raw and need no conversion). `kmsHandleRef` is
   *  an opaque handle (an ARN, not key material) from
   *  `kernel.signing_key.kms_handle_ref` — never logged, never returned. */
  sign(kmsHandleRef: string, bytes: Uint8Array, algorithm: SigningAlgorithm): Promise<Uint8Array>;
}

/** Default, unchanged behavior: throws unconditionally. Selecting a real
 *  adapter (`AwsKmsSigner`, `kms.ts`, or a future GCP one) is a
 *  ceremony-time choice made in `index.ts`'s provider selection, never
 *  here. */
export class UnconfiguredKmsSigner implements KmsSigner {
  // eslint-disable-next-line @typescript-eslint/require-await
  async sign(_kmsHandleRef: string, _bytes: Uint8Array, _algorithm: SigningAlgorithm): Promise<Uint8Array> {
    throw new KmsSignError('kms_provider_unconfigured', 'permanent');
  }
}

// ─────────────────────────────────────────────────────────────────────────
// AWS KMS — pure decision logic. `kms.ts`'s `AwsKmsSigner` calls these, in
// this order, BEFORE any credential read or network call. Every one of them
// is directly unit-tested here without ever touching `kms.ts`, `fetch`, or
// a `Deno` global.
// ─────────────────────────────────────────────────────────────────────────

/** AWS KMS's `SigningAlgorithm` name for our algorithm, or throws — AWS KMS
 *  offers no Ed25519 (ceremony D2), so a request for EdDSA against this
 *  provider is a PERMANENT misconfiguration, never transient. */
export function awsSigningAlgorithmForEs256Only(algorithm: SigningAlgorithm): 'ECDSA_SHA_256' {
  if (algorithm !== 'ES256') {
    throw new KmsSignError('unsupported_algorithm_for_provider', 'permanent');
  }
  return 'ECDSA_SHA_256';
}

/** Deployment-level fact, checked before touching credentials or network:
 *  `KMS_PROVIDER=aws` was selected but the region/role env is incomplete. */
export function requireAwsProviderConfig(
  region: string | undefined,
  roleArn: string | undefined,
): { region: string; roleArn: string } {
  if (!region || !roleArn) {
    throw new KmsSignError('aws_kms_env_missing', 'permanent');
  }
  return { region, roleArn };
}

export interface AwsCredentials {
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken?: string;
}

/** FAILS CLOSED: throws (never signs) unless real AWS credentials are
 *  present. Pure — takes an env-getter function rather than reaching for
 *  `Deno.env`/`process.env` itself, so this is directly testable with a
 *  plain function, no global mocking. `kms.ts`'s `AwsKmsSigner` deliberately
 *  does NOT call `sts:AssumeRole` itself (see its file header) — it expects
 *  the deployed runtime to have already materialized `KMS_SIGNER_ROLE_ARN`'s
 *  temporary credentials into the standard `AWS_ACCESS_KEY_ID`/
 *  `AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` environment shape. */
export function resolveAwsCredentials(getEnv: (name: string) => string | undefined): AwsCredentials {
  const accessKeyId = getEnv('AWS_ACCESS_KEY_ID');
  const secretAccessKey = getEnv('AWS_SECRET_ACCESS_KEY');
  const sessionToken = getEnv('AWS_SESSION_TOKEN');
  if (!accessKeyId || !secretAccessKey) {
    throw new KmsSignError('aws_kms_credentials_unavailable', 'permanent');
  }
  return { accessKeyId, secretAccessKey, sessionToken };
}

/** Pure classification of a `kms:Sign` HTTP failure into the error taxonomy
 *  — TRANSIENT (retryable: throttling, 5xx, too-many-requests) vs PERMANENT
 *  (operator action needed: access denied, key disabled/pending-deletion,
 *  not found, invalid key usage — or any 4xx AWS error shape this function
 *  does not specifically recognize, which fails closed as PERMANENT rather
 *  than being guessed as safe to retry). */
export function classifyAwsKmsHttpError(status: number, bodyText: string): KmsErrorClass {
  if (status === 429 || status >= 500) return 'transient';
  if (/Throttl|LimitExceeded/i.test(bodyText)) return 'transient';
  return 'permanent';
}

/** A KMS `KeyId` in a `Sign` response may be a key ARN, an alias ARN, or a
 *  bare key id — compare the trailing path segment so an ARN response still
 *  matches a bare-id (or differently-qualified) request handle, while a
 *  genuinely DIFFERENT key still fails the check. */
function keyMatchesRequestedHandle(responseKeyId: string, requestedHandle: string): boolean {
  const tail = (s: string) => s.split('/').pop() ?? s;
  return tail(responseKeyId) === tail(requestedHandle) || responseKeyId === requestedHandle;
}

export interface AwsKmsSignResponseShape {
  KeyId?: string;
  Signature?: string;
  SigningAlgorithm?: string;
}

/**
 * Pure validation of a parsed `kms:Sign` JSON response against what was
 * requested. Returns the base64 `Signature` on success; throws
 * `KmsSignError` — PERMANENT for a missing signature, SECURITY for a
 * response that contradicts (or fails to CONFIRM) the request: wrong
 * algorithm came back, the response's key id doesn't match the handle asked
 * for, OR either field is simply ABSENT from an otherwise-200 response.
 *
 * The absent-field case is deliberately NOT "no check needed" — a 200
 * response that omits `KeyId`/`SigningAlgorithm` gives this adapter no way
 * to confirm AWS actually used the requested key/algorithm at all, which is
 * exactly the class of defect sign-after-verify (`index.ts` §9) exists to
 * catch defense-in-depth against. Treating "field absent" as "check passed"
 * would silently narrow that defense to only the responses that happen to
 * restate what was asked — this validator refuses to assume good faith from
 * a missing confirmation, same as it refuses a present-but-wrong one.
 *
 * `kms.ts`'s `callSignApi` is the only caller that feeds this a REAL
 * network response; every test drives it directly with a constructed one.
 */
export function validateAwsSignResponse(
  response: AwsKmsSignResponseShape,
  requestedKeyId: string,
  expectedAwsAlgorithm: string,
): string {
  if (!response.Signature) {
    throw new KmsSignError('kms_response_missing_signature', 'permanent');
  }
  if (response.SigningAlgorithm !== expectedAwsAlgorithm) {
    throw new KmsSignError(`kms_response_algorithm_mismatch:${response.SigningAlgorithm ?? '(absent)'}`, 'security');
  }
  if (!response.KeyId || !keyMatchesRequestedHandle(response.KeyId, requestedKeyId)) {
    throw new KmsSignError(`kms_response_key_mismatch:${response.KeyId ?? '(absent)'}`, 'security');
  }
  return response.Signature;
}
