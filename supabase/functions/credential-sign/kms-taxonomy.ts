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

/** BASE credentials — the long-lived runtime IAM user's key pair (O1 design,
 *  `docs/phase2/_impl/KMS_RUNTIME_CREDENTIALS.md`). They are used for EXACTLY
 *  ONE thing: authenticating the `sts:AssumeRole` call inside
 *  `AssumeRoleCredentialProvider`. They are NEVER handed to the KMS signer —
 *  `AwsKmsSignerCore` structurally refuses any credential that is not a
 *  temporary (session-token-bearing, `ASIA…`) role credential, so there is no
 *  code path that signs with the base user even if its policy allowed it.
 *
 *  FAILS CLOSED: throws unless the base key pair is present. Pure — takes an
 *  env-getter function rather than reaching for `Deno.env`/`process.env`
 *  itself, so this is directly testable with a
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

// ═════════════════════════════════════════════════════════════════════════
// E2 — RUNTIME CREDENTIAL PROVIDER (sts:AssumeRole) + pure KMS signer core.
//
// Design: `docs/phase2/_impl/KMS_RUNTIME_CREDENTIALS.md`. Everything below is
// PURE and transport-injected: no `fetch`, no `Deno`, no `crypto.subtle`, no
// `.ts`-suffixed import — so the whole orchestration (config validation,
// endpoint derivation, request body, response parsing, identity/expiry
// checks, cache, single-flight refresh, early refresh, timeout, retry,
// error classification, redaction, and the KMS sign path that consumes the
// credentials) is exercised by `tests/credential-sign-sts-provider.test.ts`
// against MOCKED network transports. `kms.ts` supplies the two real
// transports (SigV4 over `fetch`) and nothing else.
//
// INVARIANTS (each one has a test):
//   • Base credentials authenticate STS ONLY. The signer core refuses any
//     credential that is not temporary (`ASIA…` + session token) — there is
//     no fallback to signing with the base IAM user.
//   • The STS endpoint is DERIVED from the validated region
//     (`sts.<region>.amazonaws.com`); no env var can point it elsewhere.
//   • Returned credentials are validated: all four fields present and
//     shaped, `AssumedRoleUser.Arn` == the exact expected assumed-role ARN
//     (account + role name + session name), `Expiration` parseable, not
//     already/nearly expired, not absurdly far out.
//   • Cached per provider instance AND per configuration fingerprint; a
//     config change invalidates the cache; concurrent callers share ONE
//     in-flight refresh; refresh starts `refreshAheadMs` before expiry;
//     expired credentials are NEVER returned (a failed refresh may serve
//     still-valid cached credentials with ≥ `minValidityMs` left, else it
//     throws).
//   • Per-attempt timeout; bounded retries with backoff for TRANSIENT
//     failures only (timeout, transport, 429/5xx, Throttling…); PERMANENT
//     (AccessDenied, InvalidClientTokenId, SignatureDoesNotMatch,
//     ExpiredToken, config) is thrown on the first attempt.
//   • Errors carry a CODE, never a value: no credential, session token,
//     Authorization header, request body, or raw STS/KMS response text ever
//     appears in a thrown message. Only `<Code>` / `__type` identifiers
//     (sanitized to `[A-Za-z0-9.]`) are surfaced.
// ═════════════════════════════════════════════════════════════════════════

export interface AwsTemporaryCredentials extends AwsCredentials {
  sessionToken: string;
  /** Absolute expiry, ms since epoch (from STS `Expiration`). */
  expiresAtMs: number;
}

/** THE credential-provider contract both signing consumers (`credential-sign`,
 *  `door-manifest`) use, via `AwsKmsSignerCore`. Implementations must only
 *  ever return TEMPORARY role credentials. */
export interface AwsCredentialProvider {
  getCredentials(): Promise<AwsTemporaryCredentials>;
}

export interface HttpResponseShape {
  status: number;
  text: string;
}

export interface StsTransportRequest {
  host: string;
  region: string;
  /** `application/x-www-form-urlencoded` AssumeRole Query-API body. */
  body: string;
  /** BASE credentials — sign this ONE request with them, nothing else. */
  baseCredentials: AwsCredentials;
  signal: AbortSignal;
}
export type StsTransport = (req: StsTransportRequest) => Promise<HttpResponseShape>;

export interface KmsTransportRequest {
  host: string;
  region: string;
  /** JSON body for `TrentService.Sign`. */
  body: string;
  /** TEMPORARY role credentials only — the core enforces this before calling. */
  credentials: AwsTemporaryCredentials;
  signal: AbortSignal;
}
export type KmsTransport = (req: KmsTransportRequest) => Promise<HttpResponseShape>;

// ── Configuration ────────────────────────────────────────────────────────

export interface AssumeRoleConfig {
  region: string;
  roleArn: string;
  roleAccountId: string;
  /** Role NAME (last path segment) — what STS echoes in the assumed-role ARN. */
  roleName: string;
  externalId: string;
  sessionName: string;
  durationSeconds: number;
}

const REGION_RE = /^[a-z]{2}(?:-[a-z]+)+-\d$/;
const ROLE_ARN_RE = /^arn:aws:iam::(\d{12}):role\/((?:[\w+=,.@-]+\/)*)([\w+=,.@-]{1,64})$/;
const EXTERNAL_ID_RE = /^[\w+=,.@:\/-]{2,1224}$/;
const SESSION_NAME_RE = /^[\w+=,.@-]{2,64}$/;
const KMS_KEY_ARN_RE = /^arn:aws:kms:([a-z0-9-]+):(\d{12}):key\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/;

export const DEFAULT_ASSUME_ROLE_SESSION_NAME = 'snatchit-kms-signer';
export const DEFAULT_ASSUME_ROLE_DURATION_SECONDS = 3600;

/** Reads + validates the AssumeRole configuration. Throws PERMANENT
 *  `aws_sts_config_invalid:<field>` naming ONLY the offending field. */
export function parseAssumeRoleConfig(getEnv: (name: string) => string | undefined): AssumeRoleConfig {
  const region = getEnv('AWS_REGION') || getEnv('KMS_REGION') || '';
  const roleArn = getEnv('KMS_SIGNER_ROLE_ARN') || '';
  const externalId = getEnv('KMS_SIGNER_EXTERNAL_ID') || '';
  const sessionName = getEnv('KMS_SIGNER_SESSION_NAME') || DEFAULT_ASSUME_ROLE_SESSION_NAME;
  const durationRaw = getEnv('KMS_SIGNER_DURATION_SECONDS');

  if (!region || !roleArn) throw new KmsSignError('aws_kms_env_missing', 'permanent');
  if (!REGION_RE.test(region)) throw new KmsSignError('aws_sts_config_invalid:region', 'permanent');
  const m = ROLE_ARN_RE.exec(roleArn);
  if (!m) throw new KmsSignError('aws_sts_config_invalid:role_arn', 'permanent');
  if (!EXTERNAL_ID_RE.test(externalId)) throw new KmsSignError('aws_sts_config_invalid:external_id', 'permanent');
  if (!SESSION_NAME_RE.test(sessionName)) throw new KmsSignError('aws_sts_config_invalid:session_name', 'permanent');
  let durationSeconds = DEFAULT_ASSUME_ROLE_DURATION_SECONDS;
  if (durationRaw !== undefined && durationRaw !== '') {
    if (!/^\d{3,5}$/.test(durationRaw)) throw new KmsSignError('aws_sts_config_invalid:duration', 'permanent');
    durationSeconds = Number(durationRaw);
    if (durationSeconds < 900 || durationSeconds > 3600) throw new KmsSignError('aws_sts_config_invalid:duration', 'permanent');
  }
  return { region, roleArn, roleAccountId: m[1], roleName: m[3], externalId, sessionName, durationSeconds };
}

/** The ONLY way an STS host is chosen: derived from the validated region.
 *  There is deliberately no env override — an arbitrary endpoint would let a
 *  misconfiguration ship the base credentials' signature elsewhere. */
export function stsHostForRegion(region: string): string {
  if (!REGION_RE.test(region)) throw new KmsSignError('aws_sts_config_invalid:region', 'permanent');
  return `sts.${region}.amazonaws.com`;
}

export function kmsHostForRegion(region: string): string {
  if (!REGION_RE.test(region)) throw new KmsSignError('aws_sts_config_invalid:region', 'permanent');
  return `kms.${region}.amazonaws.com`;
}

function formEncode(pairs: Array<[string, string]>): string {
  return pairs.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
}

/** AssumeRole Query-API body (STS API version 2011-06-15). */
export function buildAssumeRoleRequestBody(cfg: AssumeRoleConfig): string {
  return formEncode([
    ['Action', 'AssumeRole'],
    ['Version', '2011-06-15'],
    ['RoleArn', cfg.roleArn],
    ['RoleSessionName', cfg.sessionName],
    ['ExternalId', cfg.externalId],
    ['DurationSeconds', String(cfg.durationSeconds)],
  ]);
}

/** Expected `AssumedRoleUser.Arn` for this configuration — an EXACT string. */
export function expectedAssumedRoleArn(cfg: AssumeRoleConfig): string {
  return `arn:aws:sts::${cfg.roleAccountId}:assumed-role/${cfg.roleName}/${cfg.sessionName}`;
}

// ── Response parsing / validation ────────────────────────────────────────

const MIN_ACCEPTED_VALIDITY_MS = 60_000; // a fresh credential with < 60 s left is not usable
const MAX_PLAUSIBLE_VALIDITY_MS = 12 * 3600_000 + 5 * 60_000; // STS max 12 h + skew

function tagText(xml: string, tag: string): string | null {
  const m = new RegExp(`<${tag}>([^<]*)</${tag}>`).exec(xml);
  return m ? m[1].trim() : null;
}

/**
 * Strict extraction of the five fields this provider needs from an
 * `AssumeRoleResponse` document. Not a general XML parser on purpose: exact
 * tag matches, no attributes, no entities, no nesting — anything else is
 * `aws_sts_response_malformed:<tag>` (PERMANENT, tag name only).
 * Identity: `AssumedRoleUser.Arn` must EQUAL `expectedAssumedRoleArn(cfg)` →
 * else `aws_sts_identity_mismatch` (SECURITY). Temporariness:
 * `AccessKeyId` must be `ASIA…` → else `aws_sts_credentials_not_temporary`
 * (SECURITY). Expiry: parseable, ≥ 60 s ahead, ≤ 12 h + skew ahead → else
 * `aws_sts_expiration_invalid` (PERMANENT). Values never appear in errors.
 */
export function parseAssumeRoleResponse(xml: string, cfg: AssumeRoleConfig, nowMs: number): AwsTemporaryCredentials {
  if (typeof xml !== 'string' || xml.length === 0 || xml.length > 65_536 || !xml.includes('<AssumeRoleResponse')) {
    throw new KmsSignError('aws_sts_response_malformed:document', 'permanent');
  }
  const userBlock = /<AssumedRoleUser>([\s\S]*?)<\/AssumedRoleUser>/.exec(xml)?.[1] ?? null;
  const credBlock = /<Credentials>([\s\S]*?)<\/Credentials>/.exec(xml)?.[1] ?? null;
  if (userBlock === null) throw new KmsSignError('aws_sts_response_malformed:AssumedRoleUser', 'permanent');
  if (credBlock === null) throw new KmsSignError('aws_sts_response_malformed:Credentials', 'permanent');

  const arn = tagText(userBlock, 'Arn');
  if (!arn) throw new KmsSignError('aws_sts_response_malformed:Arn', 'permanent');
  if (arn !== expectedAssumedRoleArn(cfg)) throw new KmsSignError('aws_sts_identity_mismatch', 'security');

  const accessKeyId = tagText(credBlock, 'AccessKeyId');
  const secretAccessKey = tagText(credBlock, 'SecretAccessKey');
  const sessionToken = tagText(credBlock, 'SessionToken');
  const expiration = tagText(credBlock, 'Expiration');
  if (!accessKeyId) throw new KmsSignError('aws_sts_response_malformed:AccessKeyId', 'permanent');
  if (!secretAccessKey || secretAccessKey.length < 16) throw new KmsSignError('aws_sts_response_malformed:SecretAccessKey', 'permanent');
  if (!sessionToken || sessionToken.length < 16) throw new KmsSignError('aws_sts_response_malformed:SessionToken', 'permanent');
  if (!expiration) throw new KmsSignError('aws_sts_response_malformed:Expiration', 'permanent');
  if (!/^ASIA[A-Z0-9]{16}$/.test(accessKeyId)) throw new KmsSignError('aws_sts_credentials_not_temporary', 'security');

  const expiresAtMs = Date.parse(expiration);
  if (!Number.isFinite(expiresAtMs)) throw new KmsSignError('aws_sts_expiration_invalid', 'permanent');
  if (expiresAtMs - nowMs < MIN_ACCEPTED_VALIDITY_MS) throw new KmsSignError('aws_sts_expiration_invalid', 'permanent');
  if (expiresAtMs - nowMs > MAX_PLAUSIBLE_VALIDITY_MS) throw new KmsSignError('aws_sts_expiration_invalid', 'permanent');

  return { accessKeyId, secretAccessKey, sessionToken, expiresAtMs };
}

// ── Failure classification (STS + KMS), redacted ─────────────────────────

const SAFE_CODE_RE = /^[A-Za-z0-9.]{1,64}$/;

function sanitizeCode(raw: string | null | undefined): string {
  if (!raw) return 'unknown';
  const code = raw.includes('#') ? raw.slice(raw.lastIndexOf('#') + 1) : raw;
  return SAFE_CODE_RE.test(code) ? code : 'unknown';
}

/** The `<Code>` of an STS/Query-API error document — identifier only. */
export function extractStsErrorCode(bodyText: string): string {
  return sanitizeCode(tagText(bodyText, 'Code'));
}

/** The `__type` of a KMS/JSON error body — identifier only (never the
 *  `message`, which can restate the key ARN and principal). */
export function extractAwsJsonErrorCode(bodyText: string): string {
  const m = /"__type"\s*:\s*"([^"]{1,128})"/.exec(bodyText);
  return sanitizeCode(m?.[1] ?? null);
}

const STS_TRANSIENT_CODES = new Set([
  'Throttling', 'ThrottlingException', 'RequestLimitExceeded', 'ServiceUnavailable', 'InternalFailure',
  'InternalError', 'ServiceFailure', 'RequestTimeout',
]);

/** TRANSIENT: 429, any 5xx, or a throttling/availability code. PERMANENT:
 *  everything else (AccessDenied, InvalidClientTokenId, SignatureDoesNotMatch,
 *  ExpiredToken (the BASE credentials), MalformedPolicyDocument, RegionDisabled,
 *  ValidationError, …) — operator action needed, never retried. */
export function classifyAwsStsFailure(status: number, bodyText: string): { errorClass: KmsErrorClass; code: string } {
  const code = extractStsErrorCode(bodyText);
  if (status === 429 || status >= 500) return { errorClass: 'transient', code };
  if (STS_TRANSIENT_CODES.has(code)) return { errorClass: 'transient', code };
  return { errorClass: 'permanent', code };
}

// ── Cache + single-flight + timeout + retry ──────────────────────────────

export interface RetryTimingOptions {
  /** Per-attempt wall-clock bound. */
  timeoutMs: number;
  /** Total attempts (1 = no retry). Only TRANSIENT failures are retried. */
  maxAttempts: number;
  /** Backoff before attempt 2, 3, … (last value repeats). */
  backoffMs: readonly number[];
}

export interface AssumeRoleProviderOptions extends RetryTimingOptions {
  /** Start a refresh this long before expiry. */
  refreshAheadMs: number;
  /** A cached credential with less than this left is never returned. */
  minValidityMs: number;
}

export const DEFAULT_ASSUME_ROLE_PROVIDER_OPTIONS: AssumeRoleProviderOptions = {
  timeoutMs: 5_000,
  maxAttempts: 3,
  backoffMs: [200, 600],
  refreshAheadMs: 5 * 60_000,
  minValidityMs: 30_000,
};

export interface TimerFns {
  setTimeout: (fn: () => void, ms: number) => unknown;
  clearTimeout: (handle: unknown) => void;
}

export interface AssumeRoleProviderDeps {
  getEnv: (name: string) => string | undefined;
  transport: StsTransport;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  timers?: TimerFns;
  options?: Partial<AssumeRoleProviderOptions>;
}

function defaultTimers(): TimerFns {
  return {
    setTimeout: (fn, ms) => globalThis.setTimeout(fn, ms),
    clearTimeout: (h) => globalThis.clearTimeout(h as ReturnType<typeof setTimeout>),
  };
}

/** Runs `work(signal)` bounded by `timeoutMs`; on timeout aborts the signal
 *  and throws TRANSIENT `<label>_timeout`. Non-`KmsSignError` rejections are
 *  wrapped as TRANSIENT `<label>_transport_unavailable` WITHOUT their message
 *  (a transport error message can echo the URL/host — never a credential,
 *  but redaction is uniform on purpose). */
export async function withBoundedTimeout<T>(
  label: string,
  timeoutMs: number,
  timers: TimerFns,
  work: (signal: AbortSignal) => Promise<T>,
): Promise<T> {
  const controller = new AbortController();
  let handle: unknown;
  const timeout = new Promise<never>((_, reject) => {
    handle = timers.setTimeout(() => {
      controller.abort();
      reject(new KmsSignError(`${label}_timeout`, 'transient'));
    }, timeoutMs);
  });
  try {
    return await Promise.race([
      work(controller.signal).catch((e: unknown) => {
        if (e instanceof KmsSignError) throw e;
        throw new KmsSignError(`${label}_transport_unavailable`, 'transient');
      }),
      timeout,
    ]);
  } finally {
    timers.clearTimeout(handle);
  }
}

/** Bounded retry for TRANSIENT `KmsSignError`s only. */
export async function retryTransient<T>(
  attempt: () => Promise<T>,
  opts: RetryTimingOptions,
  sleep: (ms: number) => Promise<void>,
): Promise<T> {
  let lastErr: unknown;
  for (let i = 1; i <= Math.max(1, opts.maxAttempts); i++) {
    try {
      return await attempt();
    } catch (err) {
      lastErr = err;
      const transient = err instanceof KmsSignError && err.errorClass === 'transient';
      if (!transient || i === opts.maxAttempts) throw err;
      const backoff = opts.backoffMs[Math.min(i - 1, opts.backoffMs.length - 1)] ?? 0;
      await sleep(backoff);
    }
  }
  throw lastErr;
}

/** A fingerprint of everything that, if changed, must invalidate the cached
 *  credential. Contains identifiers only (the base ACCESS KEY ID, never the
 *  secret) and lives only in memory — it is never logged or thrown. */
export function assumeRoleConfigKey(cfg: AssumeRoleConfig, baseAccessKeyId: string): string {
  return [cfg.region, cfg.roleArn, cfg.externalId, cfg.sessionName, String(cfg.durationSeconds), baseAccessKeyId].join(' ');
}

export class AssumeRoleCredentialProvider implements AwsCredentialProvider {
  private readonly options: AssumeRoleProviderOptions;
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly timers: TimerFns;
  private cache: { configKey: string; creds: AwsTemporaryCredentials } | null = null;
  private inflight: { configKey: string; promise: Promise<AwsTemporaryCredentials> } | null = null;

  constructor(private readonly deps: AssumeRoleProviderDeps) {
    this.options = { ...DEFAULT_ASSUME_ROLE_PROVIDER_OPTIONS, ...(deps.options ?? {}) };
    this.now = deps.now ?? (() => Date.now());
    this.timers = deps.timers ?? defaultTimers();
    this.sleep = deps.sleep ?? ((ms) => new Promise((r) => this.timers.setTimeout(() => r(), ms)));
  }

  async getCredentials(): Promise<AwsTemporaryCredentials> {
    // Config + base creds are re-read on EVERY call so a changed configuration
    // (rotated base key, different role/ExternalId/region) invalidates the cache.
    const cfg = parseAssumeRoleConfig(this.deps.getEnv);
    const base = resolveAwsCredentials(this.deps.getEnv);
    const configKey = assumeRoleConfigKey(cfg, base.accessKeyId);

    if (this.cache && this.cache.configKey !== configKey) this.cache = null;
    if (this.inflight && this.inflight.configKey !== configKey) this.inflight = null;

    const now = this.now();
    if (this.cache && now < this.cache.creds.expiresAtMs - this.options.refreshAheadMs) {
      return this.cache.creds;
    }
    if (this.inflight) return this.inflight.promise;

    const promise = this.refresh(cfg, base, configKey);
    this.inflight = { configKey, promise };
    try {
      return await promise;
    } finally {
      if (this.inflight?.promise === promise) this.inflight = null;
    }
  }

  private async refresh(cfg: AssumeRoleConfig, base: AwsCredentials, configKey: string): Promise<AwsTemporaryCredentials> {
    try {
      const creds = await retryTransient(() => this.assumeRoleOnce(cfg, base), this.options, this.sleep);
      this.cache = { configKey, creds };
      return creds;
    } catch (err) {
      // A failed EARLY refresh may keep serving a still-valid credential;
      // an EXPIRED (or nearly expired) one is never returned.
      const now = this.now();
      if (this.cache && this.cache.configKey === configKey && now < this.cache.creds.expiresAtMs - this.options.minValidityMs) {
        return this.cache.creds;
      }
      this.cache = null;
      throw err;
    }
  }

  private async assumeRoleOnce(cfg: AssumeRoleConfig, base: AwsCredentials): Promise<AwsTemporaryCredentials> {
    const host = stsHostForRegion(cfg.region);
    const body = buildAssumeRoleRequestBody(cfg);
    const res = await withBoundedTimeout('aws_sts', this.options.timeoutMs, this.timers, (signal) =>
      this.deps.transport({ host, region: cfg.region, body, baseCredentials: base, signal }),
    );
    if (res.status !== 200) {
      const { errorClass, code } = classifyAwsStsFailure(res.status, res.text);
      throw new KmsSignError(`aws_sts_http_${res.status}:${code}`, errorClass);
    }
    return parseAssumeRoleResponse(res.text, cfg, this.now());
  }
}

// ── KMS signer core (pure) ───────────────────────────────────────────────

export interface AwsKmsSignerCoreDeps {
  getEnv: (name: string) => string | undefined;
  credentialProvider: AwsCredentialProvider;
  transport: KmsTransport;
  /** `credential.ts`'s `derToRawEcdsaP256` — injected (this module imports nothing). */
  derToRaw: (der: Uint8Array) => Uint8Array;
  now?: () => number;
  timers?: TimerFns;
  options?: Partial<RetryTimingOptions>;
}

export const DEFAULT_KMS_SIGN_OPTIONS: RetryTimingOptions = { timeoutMs: 5_000, maxAttempts: 2, backoffMs: [200] };

/** `kms_handle_ref` must be a full KEY ARN (runbook D4) in the configured
 *  region and the runtime role's account — the exact intended key scope.
 *  Malformed → PERMANENT `kms_handle_malformed`; out of scope → SECURITY
 *  `kms_handle_scope_mismatch`. The handle itself never appears in errors. */
export function assertKmsHandleInScope(kmsHandleRef: string, cfg: Pick<AssumeRoleConfig, 'region' | 'roleAccountId'>): void {
  const m = KMS_KEY_ARN_RE.exec(kmsHandleRef);
  if (!m) throw new KmsSignError('kms_handle_malformed', 'permanent');
  if (m[1] !== cfg.region || m[2] !== cfg.roleAccountId) throw new KmsSignError('kms_handle_scope_mismatch', 'security');
}

/** Temporary-only gate: `ASIA…` access key + session token + unexpired. This
 *  is what makes "never sign with the base IAM user" structural. */
export function assertTemporaryCredentialsUsable(creds: AwsTemporaryCredentials, nowMs: number): void {
  if (!creds || typeof creds.accessKeyId !== 'string' || !/^ASIA[A-Z0-9]{16}$/.test(creds.accessKeyId) || !creds.sessionToken) {
    throw new KmsSignError('kms_credentials_not_temporary', 'security');
  }
  if (!Number.isFinite(creds.expiresAtMs) || nowMs >= creds.expiresAtMs) {
    throw new KmsSignError('kms_credentials_expired', 'permanent');
  }
}

function base64ToBytesStd(b64: string): Uint8Array {
  if (typeof b64 !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(b64) || b64.length % 4 !== 0) {
    throw new KmsSignError('kms_response_signature_malformed', 'permanent');
  }
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64EncodeBytes(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

/**
 * The shared signer both edges use. Order, all fail-closed, nothing below
 * runs unless the step above passed:
 *   1 algorithm pin (ES256 only for AWS)          → permanent
 *   2 configuration (region/role/ExternalId)       → permanent
 *   3 key-handle scope (region + account of role)  → security / permanent
 *   4 credentials from the provider (TEMPORARY)    → provider's class
 *   5 temporary-only + unexpired gate              → security / permanent
 *   6 bounded, retried (transient-only) Sign call  → transient / permanent
 *   7 response validation (key + algorithm echo)   → security / permanent
 *   8 DER → raw R||S
 * Sign-after-verify stays where it is (`index.ts` §9), after this returns.
 */
export class AwsKmsSignerCore implements KmsSigner {
  private readonly options: RetryTimingOptions;
  private readonly now: () => number;
  private readonly timers: TimerFns;

  constructor(private readonly deps: AwsKmsSignerCoreDeps) {
    this.options = { ...DEFAULT_KMS_SIGN_OPTIONS, ...(deps.options ?? {}) };
    this.now = deps.now ?? (() => Date.now());
    this.timers = deps.timers ?? defaultTimers();
  }

  async sign(kmsHandleRef: string, bytes: Uint8Array, algorithm: SigningAlgorithm): Promise<Uint8Array> {
    const awsAlgorithm = awsSigningAlgorithmForEs256Only(algorithm);
    const cfg = parseAssumeRoleConfig(this.deps.getEnv);
    assertKmsHandleInScope(kmsHandleRef, cfg);

    const creds = await this.deps.credentialProvider.getCredentials();
    assertTemporaryCredentialsUsable(creds, this.now());

    const host = kmsHostForRegion(cfg.region);
    const body = JSON.stringify({
      KeyId: kmsHandleRef,
      Message: base64EncodeBytes(bytes),
      MessageType: 'RAW', // load-bearing: sign-after-verify digests the same way
      SigningAlgorithm: awsAlgorithm,
    });

    const sleep = (ms: number) => new Promise<void>((r) => this.timers.setTimeout(() => r(), ms));
    // The HTTP-status classification lives INSIDE the retried attempt so a
    // TRANSIENT service answer (429/5xx/ThrottlingException) is retried
    // exactly like a timeout or a transport error; PERMANENT answers
    // (AccessDenied, key disabled, …) still stop on the first attempt.
    const res = await retryTransient(
      async () => {
        const r = await withBoundedTimeout('kms_sign', this.options.timeoutMs, this.timers, (signal) =>
          this.deps.transport({ host, region: cfg.region, body, credentials: creds, signal }),
        );
        if (r.status !== 200) {
          // Body is used ONLY for classification; the thrown message carries
          // the error identifier, never the body (which restates key ARN +
          // principal).
          throw new KmsSignError(`kms_http_${r.status}:${extractAwsJsonErrorCode(r.text)}`, classifyAwsKmsHttpError(r.status, r.text));
        }
        return r;
      },
      this.options,
      sleep,
    );

    let json: AwsKmsSignResponseShape;
    try {
      json = JSON.parse(res.text) as AwsKmsSignResponseShape;
    } catch {
      throw new KmsSignError('kms_response_malformed', 'permanent');
    }
    const sigB64 = validateAwsSignResponse(json, kmsHandleRef, awsAlgorithm);
    return this.deps.derToRaw(base64ToBytesStd(sigB64));
  }
}

/** Pure provider selection both consumers share (`kms.ts` wraps it with the
 *  real transports). `aws` only when `KMS_PROVIDER === 'aws'`; anything else
 *  is the DARK default. */
export function selectKmsProviderKind(getEnv: (name: string) => string | undefined): 'aws' | 'unconfigured' {
  return (getEnv('KMS_PROVIDER') ?? '') === 'aws' ? 'aws' : 'unconfigured';
}
