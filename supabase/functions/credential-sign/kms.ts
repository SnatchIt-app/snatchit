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
 * ── CREDENTIAL RESOLUTION — explicitly OUT OF SCOPE here ─────────────────
 * `KMS_SIGNER_ROLE_ARN` NAMES which IAM role must sign KMS calls; this
 * adapter does NOT itself call `sts:AssumeRole`. It expects the deployed
 * runtime to have already materialized that role's temporary credentials
 * into the standard `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` /
 * `AWS_SESSION_TOKEN` environment shape (how AWS-hosted compute — Lambda,
 * ECS task roles, and by extension a Supabase-on-AWS edge runtime —
 * conventionally exposes assumed-role credentials to application code).
 * Wiring the ACTUAL AssumeRole call (or whatever mechanism Supabase's AWS
 * hosting uses) is ceremony-time infrastructure work, not a credential-sign
 * concern. Without those credentials present, `AwsKmsSigner.sign` throws
 * `aws_kms_credentials_unavailable` (PERMANENT, via `kms-taxonomy.ts`'s
 * `resolveAwsCredentials`) before attempting any network call. FAIL CLOSED,
 * never sign.
 * ═══════════════════════════════════════════════════════════════════════════
 */

import { derToRawEcdsaP256, type SigningAlgorithm } from './credential.ts';
import {
  awsSigningAlgorithmForEs256Only,
  classifyAwsKmsHttpError,
  KmsSignError,
  requireAwsProviderConfig,
  resolveAwsCredentials,
  UnconfiguredKmsSigner,
  validateAwsSignResponse,
  type AwsCredentials,
  type AwsKmsSignResponseShape,
  type KmsErrorClass,
  type KmsSigner,
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
 *  (unlike `kms-taxonomy.ts`'s `resolveAwsCredentials`, which takes this as
 *  an injected function so IT can be unit-tested without a `Deno` global). */
function readDenoEnv(name: string): string | undefined {
  return Deno.env.get(name);
}

/**
 * AWS KMS `Sign` adapter — ES256 (ECDSA_SHA_256) ONLY, DARK.
 *
 * MESSAGE MODE DECISION (documented, load-bearing): `MessageType: 'RAW'`.
 * For `ECDSA_SHA_256`, `MessageType: 'RAW'` tells KMS to SHA-256-digest the
 * `Message` bytes itself before signing; `MessageType: 'DIGEST'` would
 * require pre-hashing here and sending the digest. This adapter always sends
 * `MessageType: 'RAW'` with `canonical.signedBytes` verbatim as `Message` —
 * the SAME bytes `index.ts`'s sign-after-verify step verifies the returned
 * signature against (via a `{name:'ECDSA',hash:'SHA-256'}` WebCrypto verify,
 * which also digests internally). Mode and bytes are the same on both sides
 * by construction — there is no code path where they could drift.
 */
export class AwsKmsSigner implements KmsSigner {
  constructor(
    private readonly region: string | undefined,
    private readonly roleArn: string | undefined,
  ) {}

  async sign(kmsHandleRef: string, bytes: Uint8Array, algorithm: SigningAlgorithm): Promise<Uint8Array> {
    // Three fail-closed checks, in order, ALL from kms-taxonomy.ts (pure,
    // unit-tested there) — nothing below runs unless every one passes.
    const awsAlgorithm = awsSigningAlgorithmForEs256Only(algorithm); // AWS KMS offers no Ed25519
    const { region } = requireAwsProviderConfig(this.region, this.roleArn); // KMS_PROVIDER=aws but incomplete env
    const creds = resolveAwsCredentials(readDenoEnv); // no live AWS credentials in this environment
    const der = await this.callSignApi(kmsHandleRef, bytes, creds, region, awsAlgorithm);
    return derToRawEcdsaP256(der);
  }

  private async callSignApi(
    keyId: string,
    message: Uint8Array,
    creds: AwsCredentials,
    region: string,
    awsAlgorithm: string,
  ): Promise<Uint8Array> {
    const host = `kms.${region}.amazonaws.com`;
    const body = new TextEncoder().encode(
      JSON.stringify({
        KeyId: keyId,
        Message: bytesToBase64(message),
        MessageType: 'RAW', // see class doc — decision is load-bearing, not incidental
        SigningAlgorithm: awsAlgorithm,
      }),
    );

    const headers = await signSigV4({
      host,
      path: '/',
      region,
      service: 'kms',
      headers: {
        'content-type': 'application/x-amz-json-1.1',
        'x-amz-target': 'TrentService.Sign',
      },
      body,
      creds,
      date: new Date(),
    });

    let res: Response;
    try {
      res = await fetch(`https://${host}/`, { method: 'POST', headers, body });
    } catch (e) {
      throw new KmsSignError(`kms_transport_unavailable: ${e instanceof Error ? e.message : String(e)}`, 'transient');
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      // AccessDeniedException, DisabledException, NotFoundException,
      // KMSInvalidStateException (pending deletion), InvalidKeyUsageException
      // — all operator-actionable, none retryable as-is; throttling/5xx are
      // the only TRANSIENT shapes. `classifyAwsKmsHttpError`
      // (kms-taxonomy.ts) is the single source of truth for this split.
      throw new KmsSignError(`kms_http_${res.status}:${text.slice(0, 200)}`, classifyAwsKmsHttpError(res.status, text));
    }

    const json = (await res.json()) as AwsKmsSignResponseShape;
    // `validateAwsSignResponse` (kms-taxonomy.ts, pure) throws PERMANENT for
    // a missing signature, SECURITY for a response that contradicts what
    // was requested (wrong algorithm, wrong key came back).
    const sigB64 = validateAwsSignResponse(json, keyId, awsAlgorithm);
    return base64ToBytes(sigB64);
  }
}
