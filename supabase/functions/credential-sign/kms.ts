/**
 * supabase/functions/credential-sign/kms.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * The Deno-only KMS transport adapter for `credential-sign` — DARK.
 *
 * ── DENO-ONLY, IMPORTED BY index.ts ALONE — NEVER BY A TEST ──────────────
 * This file mirrors `index.ts`'s own posture: a `.ts`-extension sibling
 * import (`./credential.ts`, Deno's required convention) and WebCrypto
 * (`crypto.subtle`) usage that a recent `lib.dom.d.ts` tightens around
 * `BufferSource`/`Uint8Array<ArrayBufferLike>`. Neither is a problem for the
 * Deno edge runtime this file actually executes under — but `tsc -p .`
 * (`npm run typecheck`) type-checks anything TRANSITIVELY reachable from an
 * included root file (`tests/**` is not excluded), so if any test imported
 * THIS file, both issues would surface as real `npm run typecheck` failures
 * — which is exactly what happened before this file was split. The fix:
 * every DECISION worth unit-testing (the KMS error taxonomy, the
 * algorithm→AWS-spec mapping, the env/credential fail-closed checks, the
 * response-validation security checks) now lives in `./kms-taxonomy.ts` —
 * PURE, zero imports, no `.ts`-suffixed sibling import, no WebCrypto —
 * which `tests/credential-sign-kms.test.ts` imports directly. This file
 * keeps only the SigV4-over-`fetch` transport plumbing and orchestration,
 * which is exercised by construction/composition, not by tsc, exactly like
 * `index.ts` always has been (nothing in `tests/` imports `index.ts` either
 * — both files are Deno-only shells around pure, separately-tested logic).
 *
 * Authoring this file creates no KMS key, calls no KMS, and signs no
 * credential. `AwsKmsSigner` below is REAL, REVIEWABLE transport code — not
 * a mock — but it fails closed (throws, before any network call) whenever
 * the AWS credentials it needs are absent from the environment, which they
 * always are in this repo/CI/local-rehearsal environment. Selecting AWS as
 * the LIVE provider (`KMS_PROVIDER=aws` plus real AWS credentials in the
 * deployed edge runtime's environment) is a ceremony-time operator decision,
 * never made by this file. See `docs/phase2/_impl/KMSADAPTER.md`.
 *
 * ── PROVIDER DECISION (PRODUCTION_SIGNING_KMS_CEREMONY.md D1/D2) ─────────
 * Sanctioned providers: AWS KMS / GCP KMS / CloudHSM ONLY. Supabase runs on
 * AWS and `KMS_SIGNER_ROLE_ARN` is AWS-shaped, so AWS KMS is the REFERENCE
 * adapter here. AWS KMS offers NO Ed25519 — its algorithm is ES256
 * (ECDSA P-256 / SHA-256). The `KmsSigner` interface (`kms-taxonomy.ts`)
 * stays provider-agnostic so a future GCP KMS adapter (which DOES offer
 * Ed25519) can be added alongside `AwsKmsSigner` without touching
 * `index.ts`'s call site. The final provider/algorithm choice for the LIVE
 * deploy is an OWNER decision (ceremony) — this file does not hard-fail
 * when unconfigured; the default export stays `UnconfiguredKmsSigner`.
 *
 * ── WHY `fetch` + hand-rolled SigV4, NOT the AWS SDK ─────────────────────
 * Deno edge modules need to load this file; a full AWS SDK (even via
 * `npm:`/esm.sh) pulls a large dependency tree with rough edges in the Deno
 * runtime and is unnecessary for ONE API call (`kms:Sign`). SigV4 over
 * `fetch` is ~100 lines, fully reviewable, and adds nothing that could
 * "accidentally" reach AWS outside this file's own `callSignApi`.
 *
 * ── CREDENTIAL RESOLUTION — E2 (`docs/phase2/_impl/KMS_RUNTIME_CREDENTIALS.md`) ─
 * `KMS_SIGNER_ROLE_ARN` NAMES the runtime IAM role; the BASE credentials in
 * `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` belong to the runtime IAM USER
 * whose only permission is `sts:AssumeRole` into that role. This file's
 * `createAwsKmsSigner` composes `kms-taxonomy.ts`'s PURE
 * `AssumeRoleCredentialProvider` (config validation, regional STS endpoint,
 * strict response parsing, identity + expiry checks, per-isolate cache,
 * single-flight + early refresh, bounded timeout/retry, redacted errors) and
 * `AwsKmsSignerCore` (temporary-credentials-only gate, key-scope check,
 * bounded Sign call, response validation) over the two SigV4 transports
 * below. The base credentials sign exactly ONE kind of request — the STS
 * call; the core refuses to sign KMS with anything but `ASIA…` + session
 * token. Without the env + base credentials it throws PERMANENT before any
 * network call. FAIL CLOSED, never sign. ADOPTION of this mechanism in
 * production (O1) is an OWNER decision — not made by this file.
 * ═══════════════════════════════════════════════════════════════════════════
 */

import { derToRawEcdsaP256 } from './credential.ts';
import {
  AssumeRoleCredentialProvider,
  AwsKmsSignerCore,
  classifyAwsKmsHttpError,
  KmsSignError,
  selectKmsProviderKind,
  UnconfiguredKmsSigner,
  type KmsErrorClass,
  type KmsSigner,
  type KmsTransport,
  type StsTransport,
} from './kms-taxonomy.ts';

// Re-exported so `index.ts` (the only importer of this file) can pull the
// whole KMS surface — pure taxonomy AND the Deno transport adapter — from
// one place, unchanged from before the split.
export { KmsSignError, UnconfiguredKmsSigner, classifyAwsKmsHttpError, type KmsErrorClass, type KmsSigner };

// ─────────────────────────────────────────────────────────────────────────
// AWS SigV4 — pure-ish helpers (network only in `fetch` itself). Standard
// AWS Signature Version 4 for a single JSON POST request. No AWS SDK.
// ─────────────────────────────────────────────────────────────────────────

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return toHex(new Uint8Array(digest));
}

async function hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', cryptoKey, data);
  return new Uint8Array(sig);
}

function amzDateStamp(d: Date): { amzDate: string; dateStamp: string } {
  const amzDate = d.toISOString().replace(/[:-]|\.\d{3}/g, ''); // YYYYMMDDTHHMMSSZ
  return { amzDate, dateStamp: amzDate.slice(0, 8) };
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** Builds the SigV4 `Authorization` header (plus the other required
 *  headers) for one request. Canonical-request → string-to-sign → derived
 *  signing key → signature, per the AWS SigV4 spec, for a POST with an
 *  already-serialized JSON body and no query string (which is all `kms:Sign`
 *  ever needs). */
async function signSigV4(params: {
  host: string;
  path: string;
  region: string;
  service: string;
  headers: Record<string, string>;
  body: Uint8Array;
  creds: AwsCredentials;
  date: Date;
}): Promise<Record<string, string>> {
  const { host, path, region, service, body, creds, date } = params;
  const { amzDate, dateStamp } = amzDateStamp(date);
  const payloadHash = await sha256Hex(body);

  const headers: Record<string, string> = {
    ...params.headers,
    host,
    'x-amz-date': amzDate,
    'x-amz-content-sha256': payloadHash,
  };
  if (creds.sessionToken) headers['x-amz-security-token'] = creds.sessionToken;

  const lowerNames = Object.keys(headers).map((h) => h.toLowerCase());
  const nameByLower = new Map(Object.keys(headers).map((h) => [h.toLowerCase(), h]));
  const sortedLower = [...lowerNames].sort();
  const canonicalHeaders = sortedLower.map((h) => `${h}:${headers[nameByLower.get(h)!].trim()}\n`).join('');
  const signedHeaders = sortedLower.join(';');

  const canonicalRequest = ['POST', path, '', canonicalHeaders, signedHeaders, payloadHash].join('\n');
  const canonicalRequestHash = await sha256Hex(new TextEncoder().encode(canonicalRequest));

  const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = ['AWS4-HMAC-SHA256', amzDate, credentialScope, canonicalRequestHash].join('\n');

  const enc = new TextEncoder();
  const kDate = await hmacSha256(enc.encode(`AWS4${creds.secretAccessKey}`), enc.encode(dateStamp));
  const kRegion = await hmacSha256(kDate, enc.encode(region));
  const kService = await hmacSha256(kRegion, enc.encode(service));
  const kSigning = await hmacSha256(kService, enc.encode('aws4_request'));
  const signature = toHex(await hmacSha256(kSigning, enc.encode(stringToSign)));

  const authorization =
    `AWS4-HMAC-SHA256 Credential=${creds.accessKeyId}/${credentialScope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;

  return { ...headers, Authorization: authorization };
}

/** Reads one env var via `Deno.env` — Deno-only glue, deliberately NOT pure
 *  (the pure modules take this as an injected function). */
function readDenoEnv(name: string): string | undefined {
  return Deno.env.get(name);
}

// ─────────────────────────────────────────────────────────────────────────
// The two REAL transports. Each signs exactly one POST with SigV4 and returns
// `{ status, text }` — nothing else. They never log, never inspect bodies,
// never decide anything: every decision is in `kms-taxonomy.ts`.
// ─────────────────────────────────────────────────────────────────────────

/** `sts:AssumeRole` (Query API, form-encoded) signed with the BASE credentials
 *  — the only request the base credentials ever sign. */
export function makeStsTransport(fetchImpl: typeof fetch = fetch): StsTransport {
  return async (req) => {
    const body = new TextEncoder().encode(req.body);
    const headers = await signSigV4({
      host: req.host,
      path: '/',
      region: req.region,
      service: 'sts',
      headers: { 'content-type': 'application/x-www-form-urlencoded; charset=utf-8' },
      body,
      creds: req.baseCredentials,
      date: new Date(),
    });
    const res = await fetchImpl(`https://${req.host}/`, { method: 'POST', headers, body, signal: req.signal });
    return { status: res.status, text: await res.text() };
  };
}

/** `kms:Sign` (JSON 1.1) signed with the TEMPORARY role credentials. */
export function makeKmsTransport(fetchImpl: typeof fetch = fetch): KmsTransport {
  return async (req) => {
    const body = new TextEncoder().encode(req.body);
    const headers = await signSigV4({
      host: req.host,
      path: '/',
      region: req.region,
      service: 'kms',
      headers: { 'content-type': 'application/x-amz-json-1.1', 'x-amz-target': 'TrentService.Sign' },
      body,
      creds: req.credentials,
      date: new Date(),
    });
    const res = await fetchImpl(`https://${req.host}/`, { method: 'POST', headers, body, signal: req.signal });
    return { status: res.status, text: await res.text() };
  };
}

/**
 * AWS KMS signer — ES256 only, DARK. Composition of the pure core over the
 * real transports: base env credentials → `sts:AssumeRole` (cached,
 * single-flight, early-refresh) → temporary role credentials → `kms:Sign`.
 * Nothing here can reach AWS without `KMS_PROVIDER=aws`, a valid
 * `AWS_REGION`/`KMS_SIGNER_ROLE_ARN`/`KMS_SIGNER_EXTERNAL_ID`, AND base
 * credentials in the environment — none of which exist in this repo, CI,
 * or the local rehearsal (fail closed: `aws_kms_env_missing` /
 * `aws_kms_credentials_unavailable`, PERMANENT, before any network call).
 *
 * MESSAGE MODE DECISION (load-bearing): `MessageType: 'RAW'` — KMS SHA-256-
 * digests `Message` itself; `index.ts`'s sign-after-verify verifies the SAME
 * `canonical.signedBytes` with a digesting WebCrypto verify. Same bytes, same
 * mode, both sides, by construction (set in `AwsKmsSignerCore`).
 */
export function createAwsKmsSigner(getEnv: (name: string) => string | undefined = readDenoEnv, fetchImpl: typeof fetch = fetch): KmsSigner {
  const credentialProvider = new AssumeRoleCredentialProvider({ getEnv, transport: makeStsTransport(fetchImpl) });
  return new AwsKmsSignerCore({ getEnv, credentialProvider, transport: makeKmsTransport(fetchImpl), derToRaw: derToRawEcdsaP256 });
}

/**
 * THE selector both edges call at module scope (one signer — and therefore
 * one credential cache — per runtime isolate). Unchanged DARK default:
 *   KMS_PROVIDER unset / anything but "aws" → UnconfiguredKmsSigner (throws
 *     `kms_provider_unconfigured`, PERMANENT, always).
 *   KMS_PROVIDER="aws" → `createAwsKmsSigner()` (still fails closed without
 *     the full env + base credentials, before any network call).
 */
export function selectKmsSignerFromEnv(getEnv: (name: string) => string | undefined = readDenoEnv): KmsSigner {
  return selectKmsProviderKind(getEnv) === 'aws' ? createAwsKmsSigner(getEnv) : new UnconfiguredKmsSigner();
}
