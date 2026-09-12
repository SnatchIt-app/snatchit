/**
 * E2 — runtime credential provider (`sts:AssumeRole`) + KMS signer core,
 * against MOCKED network transports. No AWS call is ever made: every
 * `StsTransport`/`KmsTransport` here is a local function; the KMS "service"
 * is a throwaway P-256 key that DER-signs like AWS KMS does.
 *
 * COVERAGE (each bullet is at least one test):
 *   • configuration validation (missing/invalid region, role ARN, ExternalId,
 *     session name, duration); the STS host is DERIVED from the region and
 *     no env var can redirect it
 *   • initial acquisition + reuse; expiry + early refresh; expired creds are
 *     never returned; concurrent callers share ONE in-flight refresh
 *   • malformed/missing credential fields; non-temporary (`AKIA`) key id;
 *     invalid / past / absurd Expiration; wrong assumed-role identity
 *   • timeout (fake timers; abort signalled), throttling (retried, then
 *     succeeds), 5xx (retried), AccessDenied (no retry), failed refresh
 *     (serves still-valid cache; throws when the cache is too close to expiry)
 *   • configuration change invalidates the cache (role / ExternalId / base key)
 *   • NO direct-base-credential fallback: provider failure ⇒ KMS transport
 *     never called; a provider that returns non-temporary creds ⇒ SECURITY
 *     refusal before any KMS call
 *   • redaction: no credential, token, request body, Authorization header, or
 *     raw STS/KMS body ever appears in a thrown message (sentinel search)
 *   • BOTH signing consumers (credential-sign-shaped and door-manifest-shaped
 *     calls) go through the same provider contract; one provider shared by
 *     two cores ⇒ one STS call; the produced R||S verifies locally; key-scope
 *     mismatch (other account/region) ⇒ SECURITY, no KMS call
 *   • ES256 pin, `MessageType: RAW`, KMS response echo validation, and the
 *     DARK default (`selectKmsProviderKind` ⇒ unconfigured) are preserved
 */
import { createPublicKey, generateKeyPairSync, sign as nodeSign, verify as nodeVerify, type KeyObject } from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { derToRawEcdsaP256 } from '../supabase/functions/credential-sign/credential';
import {
  AssumeRoleCredentialProvider,
  assertKmsHandleInScope,
  assertTemporaryCredentialsUsable,
  AwsKmsSignerCore,
  buildAssumeRoleRequestBody,
  classifyAwsStsFailure,
  DEFAULT_ASSUME_ROLE_PROVIDER_OPTIONS,
  expectedAssumedRoleArn,
  extractAwsJsonErrorCode,
  extractStsErrorCode,
  KmsSignError,
  kmsHostForRegion,
  parseAssumeRoleConfig,
  parseAssumeRoleResponse,
  selectKmsProviderKind,
  stsHostForRegion,
  UnconfiguredKmsSigner,
  type AwsCredentialProvider,
  type AwsTemporaryCredentials,
  type HttpResponseShape,
  type KmsTransport,
  type KmsTransportRequest,
  type StsTransport,
  type StsTransportRequest,
} from '../supabase/functions/credential-sign/kms-taxonomy';

// ── Fixtures ─────────────────────────────────────────────────────────────

const ACCOUNT = '652872010073';
const REGION = 'us-east-1';
const ROLE_ARN = `arn:aws:iam::${ACCOUNT}:role/SnatchIt-CredentialSign-Runtime`;
const KEY_ARN = `arn:aws:kms:${REGION}:${ACCOUNT}:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b`;
const EXTERNAL_ID = 'ext-id-test-SENTINEL-EXTERNALID';
const BASE_KEY_ID = 'AKIAIOSFODNN7EXAMPLE';
const BASE_SECRET = 'wJalrXUtnFEMI-BASESECRET-SENTINEL-1234567890';
const TEMP_KEY_ID = 'ASIAIOSFODNN7EXAMPLE';
const TEMP_SECRET = 'TEMPSECRET-SENTINEL-abcdefghijklmnopqrstuvwxyz';
const TEMP_TOKEN = 'SESSIONTOKEN-SENTINEL-FwoGZXIvYXdzEBYaDNNoGb4nvvFh9YRvBCK';
const SENTINELS = [BASE_SECRET, TEMP_SECRET, TEMP_TOKEN, 'SENTINEL', 'Authorization', 'AWS4-HMAC-SHA256', 'ExternalId=', '<SessionToken>'];

const T0 = Date.parse('2026-09-05T12:00:00.000Z');

function baseEnv(over: Record<string, string | undefined> = {}): (k: string) => string | undefined {
  const env: Record<string, string | undefined> = {
    KMS_PROVIDER: 'aws',
    AWS_REGION: REGION,
    KMS_SIGNER_ROLE_ARN: ROLE_ARN,
    KMS_SIGNER_EXTERNAL_ID: EXTERNAL_ID,
    AWS_ACCESS_KEY_ID: BASE_KEY_ID,
    AWS_SECRET_ACCESS_KEY: BASE_SECRET,
    ...over,
  };
  return (k) => env[k];
}

function stsXml(over: Partial<{ arn: string; keyId: string; secret: string; token: string; expiration: string }> = {}, opts: { omit?: string[] } = {}): string {
  const v = {
    arn: `arn:aws:sts::${ACCOUNT}:assumed-role/SnatchIt-CredentialSign-Runtime/snatchit-kms-signer`,
    keyId: TEMP_KEY_ID,
    secret: TEMP_SECRET,
    token: TEMP_TOKEN,
    expiration: new Date(T0 + 3600_000).toISOString(),
    ...over,
  };
  const omit = new Set(opts.omit ?? []);
  const tag = (name: string, val: string) => (omit.has(name) ? '' : `<${name}>${val}</${name}>`);
  return `<AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/"><AssumeRoleResult>
  <AssumedRoleUser>${tag('Arn', v.arn)}<AssumedRoleId>ARO123EXAMPLE123:snatchit-kms-signer</AssumedRoleId></AssumedRoleUser>
  <Credentials>${tag('AccessKeyId', v.keyId)}${tag('SecretAccessKey', v.secret)}${tag('SessionToken', v.token)}${tag('Expiration', v.expiration)}</Credentials>
  </AssumeRoleResult><ResponseMetadata><RequestId>c6104cbe-af31-11e0-8154-cbc7ccf896c7</RequestId></ResponseMetadata></AssumeRoleResponse>`;
}

function stsError(code: string): string {
  return `<ErrorResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/"><Error><Type>Sender</Type><Code>${code}</Code><Message>Not authorized: ${BASE_KEY_ID} SENTINEL ${ROLE_ARN}</Message></Error><RequestId>x</RequestId></ErrorResponse>`;
}

/** A scripted STS transport: each call pops the next response (or throws). */
function scriptedSts(script: Array<HttpResponseShape | Error | 'hang'>) {
  const calls: StsTransportRequest[] = [];
  const transport: StsTransport = (req) => {
    calls.push(req);
    const next = script.shift();
    if (next === undefined) return Promise.reject(new Error('script exhausted'));
    if (next === 'hang') return new Promise<HttpResponseShape>(() => {});
    if (next instanceof Error) return Promise.reject(next);
    return Promise.resolve(next);
  };
  return { transport, calls };
}

const ok = (xml = stsXml()): HttpResponseShape => ({ status: 200, text: xml });

/** A throwaway "KMS service": DER-signs with a local P-256 key, echoes the
 *  KeyId/SigningAlgorithm the way AWS KMS does; records every request. */
function fakeKms(privateKey: KeyObject, opts: { status?: number; body?: string; keyIdEcho?: string; algEcho?: string } = {}) {
  const calls: KmsTransportRequest[] = [];
  const transport: KmsTransport = (req) => {
    calls.push(req);
    if (opts.status && opts.status !== 200) return Promise.resolve({ status: opts.status, text: opts.body ?? '' });
    const parsed = JSON.parse(req.body) as { KeyId: string; Message: string; MessageType: string; SigningAlgorithm: string };
    const message = Buffer.from(parsed.Message, 'base64');
    const der = nodeSign('sha256', message, { key: privateKey, dsaEncoding: 'der' });
    return Promise.resolve({
      status: 200,
      text: JSON.stringify({ KeyId: opts.keyIdEcho ?? parsed.KeyId, Signature: der.toString('base64'), SigningAlgorithm: opts.algEcho ?? parsed.SigningAlgorithm }),
    });
  };
  return { transport, calls };
}

function genP256() {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return { publicKey, privateKey };
}

function verifyRaw(publicKey: KeyObject, message: Uint8Array, raw: Uint8Array): boolean {
  return nodeVerify('sha256', Buffer.from(message), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(raw));
}

function expectRedacted(err: unknown): void {
  const text = `${err instanceof Error ? err.message : String(err)}|${err instanceof Error ? String(err.stack ?? '') : ''}`;
  for (const s of SENTINELS) expect(text, `message leaks '${s}'`).not.toContain(s);
}

async function expectKmsError(p: Promise<unknown>, message: string | RegExp, errorClass: 'transient' | 'permanent' | 'security'): Promise<KmsSignError> {
  try {
    await p;
  } catch (e) {
    expect(e).toBeInstanceOf(KmsSignError);
    const err = e as KmsSignError;
    if (typeof message === 'string') expect(err.message).toBe(message);
    else expect(err.message).toMatch(message);
    expect(err.errorClass).toBe(errorClass);
    expectRedacted(err);
    return err;
  }
  throw new Error(`expected rejection ${String(message)}`);
}

const immediateSleep = () => Promise.resolve();

afterEach(() => {
  vi.useRealTimers();
});

// ═══════════════════════════════════════════════════════════════════════════

describe('configuration + endpoint derivation', () => {
  it('parses a valid configuration (role account/name extracted; defaults applied)', () => {
    const cfg = parseAssumeRoleConfig(baseEnv());
    expect(cfg).toEqual({
      region: REGION, roleArn: ROLE_ARN, roleAccountId: ACCOUNT, roleName: 'SnatchIt-CredentialSign-Runtime',
      externalId: EXTERNAL_ID, sessionName: 'snatchit-kms-signer', durationSeconds: 3600,
    });
    expect(expectedAssumedRoleArn(cfg)).toBe(`arn:aws:sts::${ACCOUNT}:assumed-role/SnatchIt-CredentialSign-Runtime/snatchit-kms-signer`);
    expect(parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_ROLE_ARN: `arn:aws:iam::${ACCOUNT}:role/service/path/Runtime` })).roleName).toBe('Runtime');
  });

  it('refuses missing/invalid region, role ARN, ExternalId, session name, duration — PERMANENT, field name only', () => {
    expect(() => parseAssumeRoleConfig(baseEnv({ AWS_REGION: undefined }))).toThrow(expect.objectContaining({ message: 'aws_kms_env_missing', errorClass: 'permanent' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_ROLE_ARN: undefined }))).toThrow(expect.objectContaining({ message: 'aws_kms_env_missing' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ AWS_REGION: 'US-EAST-1' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:region', errorClass: 'permanent' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ AWS_REGION: 'sts.evil.example.com' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:region' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_ROLE_ARN: `arn:aws:iam::${ACCOUNT}:user/not-a-role` }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:role_arn' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_ROLE_ARN: 'arn:aws:iam::12345:role/x' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:role_arn' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_EXTERNAL_ID: undefined }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:external_id' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_EXTERNAL_ID: 'x' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:external_id' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_EXTERNAL_ID: 'has space' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:external_id' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_SESSION_NAME: 'bad/name' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:session_name' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_DURATION_SECONDS: '60' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:duration' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_DURATION_SECONDS: '43200' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:duration' }));
    expect(() => parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_DURATION_SECONDS: 'abc' }))).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:duration' }));
    expect(parseAssumeRoleConfig(baseEnv({ KMS_SIGNER_DURATION_SECONDS: '900' })).durationSeconds).toBe(900);
  });

  it('the STS/KMS hosts are derived from the region only — an endpoint-looking env var is ignored', async () => {
    expect(stsHostForRegion('us-east-1')).toBe('sts.us-east-1.amazonaws.com');
    expect(stsHostForRegion('eu-west-2')).toBe('sts.eu-west-2.amazonaws.com');
    expect(kmsHostForRegion('us-east-1')).toBe('kms.us-east-1.amazonaws.com');
    expect(() => stsHostForRegion('evil.example.com')).toThrow(expect.objectContaining({ message: 'aws_sts_config_invalid:region' }));
    const { transport, calls } = scriptedSts([ok()]);
    const provider = new AssumeRoleCredentialProvider({
      getEnv: baseEnv({ AWS_STS_ENDPOINT: 'https://evil.example.com', STS_ENDPOINT: 'https://evil.example.com', AWS_ENDPOINT_URL_STS: 'https://evil.example.com' }),
      transport, now: () => T0, sleep: immediateSleep,
    });
    await provider.getCredentials();
    expect(calls).toHaveLength(1);
    expect(calls[0].host).toBe('sts.us-east-1.amazonaws.com');
    expect(calls[0].region).toBe(REGION);
    expect(calls[0].baseCredentials).toEqual({ accessKeyId: BASE_KEY_ID, secretAccessKey: BASE_SECRET, sessionToken: undefined });
    expect(calls[0].body).toBe(buildAssumeRoleRequestBody(parseAssumeRoleConfig(baseEnv())));
    expect(calls[0].body).toBe(`Action=AssumeRole&Version=2011-06-15&RoleArn=${encodeURIComponent(ROLE_ARN)}&RoleSessionName=snatchit-kms-signer&ExternalId=${encodeURIComponent(EXTERNAL_ID)}&DurationSeconds=3600`);
  });
});

// ═══════════════════════════════════════════════════════════════════════════

describe('acquisition, cache, early refresh, expiry, concurrency', () => {
  it('acquires once and reuses the cached temporary credentials', async () => {
    const { transport, calls } = scriptedSts([ok()]);
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport, now: () => T0, sleep: immediateSleep });
    const a = await provider.getCredentials();
    const b = await provider.getCredentials();
    expect(calls).toHaveLength(1);
    expect(a).toEqual({ accessKeyId: TEMP_KEY_ID, secretAccessKey: TEMP_SECRET, sessionToken: TEMP_TOKEN, expiresAtMs: T0 + 3600_000 });
    expect(b).toBe(a);
  });

  it('refreshes AHEAD of expiry (inside refreshAheadMs) and never returns an expired credential', async () => {
    let now = T0;
    const second = stsXml({ keyId: 'ASIAREFRESHED0000000', expiration: new Date(T0 + 2 * 3600_000).toISOString() });
    const { transport, calls } = scriptedSts([ok(), ok(second)]);
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport, now: () => now, sleep: immediateSleep });
    const first = await provider.getCredentials();
    now = T0 + 3600_000 - DEFAULT_ASSUME_ROLE_PROVIDER_OPTIONS.refreshAheadMs - 1; // just before the window
    expect(await provider.getCredentials()).toBe(first);
    expect(calls).toHaveLength(1);
    now = T0 + 3600_000 - DEFAULT_ASSUME_ROLE_PROVIDER_OPTIONS.refreshAheadMs + 1; // inside the window
    const refreshed = await provider.getCredentials();
    expect(calls).toHaveLength(2);
    expect(refreshed.accessKeyId).toBe('ASIAREFRESHED0000000');
    // now the FIRST credential is past expiry; a refresh that fails must NOT serve it
    now = T0 + 2 * 3600_000 + 1;
    const { transport: failing } = scriptedSts([{ status: 403, text: stsError('AccessDenied') }]);
    const p2 = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport: failing, now: () => now, sleep: immediateSleep });
    await expectKmsError(p2.getCredentials(), 'aws_sts_http_403:AccessDenied', 'permanent');
  });

  it('a refresh that STARTS after expiry never hands back the stale credential even if the refresh fails', async () => {
    let now = T0;
    const { transport } = scriptedSts([ok(), { status: 503, text: stsError('ServiceUnavailable') }, { status: 503, text: stsError('ServiceUnavailable') }, { status: 503, text: stsError('ServiceUnavailable') }]);
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport, now: () => now, sleep: immediateSleep });
    await provider.getCredentials();
    now = T0 + 3600_000 + 5; // expired
    await expectKmsError(provider.getCredentials(), 'aws_sts_http_503:ServiceUnavailable', 'transient');
  });

  it('concurrent callers share ONE in-flight refresh', async () => {
    let resolve!: (r: HttpResponseShape) => void;
    const calls: StsTransportRequest[] = [];
    const transport: StsTransport = (req) => { calls.push(req); return new Promise((r) => { resolve = r; }); };
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport, now: () => T0, sleep: immediateSleep });
    const pending = Promise.all([1, 2, 3, 4, 5].map(() => provider.getCredentials()));
    await Promise.resolve();
    expect(calls).toHaveLength(1);
    resolve(ok());
    const results = await pending;
    expect(new Set(results).size).toBe(1);
    expect(calls).toHaveLength(1);
    // and after settling, a further call still reuses the cache
    await provider.getCredentials();
    expect(calls).toHaveLength(1);
  });

  it('a failed EARLY refresh keeps serving the still-valid cached credential; throws once the cache is within minValidityMs', async () => {
    let now = T0;
    const { transport, calls } = scriptedSts([
      ok(),
      { status: 500, text: stsError('InternalFailure') }, { status: 500, text: stsError('InternalFailure') }, { status: 500, text: stsError('InternalFailure') },
      { status: 500, text: stsError('InternalFailure') }, { status: 500, text: stsError('InternalFailure') }, { status: 500, text: stsError('InternalFailure') },
    ]);
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport, now: () => now, sleep: immediateSleep });
    const first = await provider.getCredentials();
    now = T0 + 3600_000 - 2 * 60_000; // inside refresh window, 2 min left (> minValidity 30 s)
    expect(await provider.getCredentials()).toBe(first); // refresh failed (3 attempts) but cache still valid
    expect(calls).toHaveLength(4);
    now = T0 + 3600_000 - 10_000; // 10 s left (< minValidity)
    await expectKmsError(provider.getCredentials(), 'aws_sts_http_500:InternalFailure', 'transient');
    expect(calls).toHaveLength(7);
  });

  it('a configuration change (role ARN, ExternalId, or base access key) invalidates the cache', async () => {
    const { transport, calls } = scriptedSts([ok(), ok(), ok(), ok()]);
    const env: Record<string, string | undefined> = {
      AWS_REGION: REGION, KMS_SIGNER_ROLE_ARN: ROLE_ARN, KMS_SIGNER_EXTERNAL_ID: EXTERNAL_ID, AWS_ACCESS_KEY_ID: BASE_KEY_ID, AWS_SECRET_ACCESS_KEY: BASE_SECRET,
    };
    const provider = new AssumeRoleCredentialProvider({ getEnv: (k) => env[k], transport, now: () => T0, sleep: immediateSleep });
    await provider.getCredentials();
    await provider.getCredentials();
    expect(calls).toHaveLength(1);
    env.KMS_SIGNER_EXTERNAL_ID = 'ext-id-rotated-000000';
    await provider.getCredentials();
    expect(calls).toHaveLength(2);
    env.AWS_ACCESS_KEY_ID = 'AKIAROTATEDBASEKEY01';
    await provider.getCredentials();
    expect(calls).toHaveLength(3);
    expect(calls[2].baseCredentials.accessKeyId).toBe('AKIAROTATEDBASEKEY01');
    env.KMS_SIGNER_ROLE_ARN = `arn:aws:iam::${ACCOUNT}:role/Other`;
    await expectKmsError(provider.getCredentials(), 'aws_sts_identity_mismatch', 'security'); // XML echoes the OLD role
    expect(calls).toHaveLength(4);
  });
});

// ═══════════════════════════════════════════════════════════════════════════

describe('response validation (identity, temporariness, expiration) — redacted', () => {
  const cfg = parseAssumeRoleConfig(baseEnv());

  it('accepts a well-formed response', () => {
    expect(parseAssumeRoleResponse(stsXml(), cfg, T0)).toEqual({ accessKeyId: TEMP_KEY_ID, secretAccessKey: TEMP_SECRET, sessionToken: TEMP_TOKEN, expiresAtMs: T0 + 3600_000 });
  });

  it('missing fields ⇒ aws_sts_response_malformed:<tag> (PERMANENT), tag name only', () => {
    for (const tag of ['Arn', 'AccessKeyId', 'SecretAccessKey', 'SessionToken', 'Expiration']) {
      let err: unknown;
      try { parseAssumeRoleResponse(stsXml({}, { omit: [tag] }), cfg, T0); } catch (e) { err = e; }
      expect(err).toEqual(expect.objectContaining({ message: `aws_sts_response_malformed:${tag}`, errorClass: 'permanent' }));
      expectRedacted(err);
    }
    expect(() => parseAssumeRoleResponse('', cfg, T0)).toThrow(expect.objectContaining({ message: 'aws_sts_response_malformed:document' }));
    expect(() => parseAssumeRoleResponse('<html>SENTINEL</html>', cfg, T0)).toThrow(expect.objectContaining({ message: 'aws_sts_response_malformed:document' }));
    expect(() => parseAssumeRoleResponse('<AssumeRoleResponse></AssumeRoleResponse>', cfg, T0)).toThrow(expect.objectContaining({ message: 'aws_sts_response_malformed:AssumedRoleUser' }));
  });

  it('wrong assumed-role identity (other role / account / session) ⇒ SECURITY', () => {
    for (const arn of [
      `arn:aws:sts::${ACCOUNT}:assumed-role/OtherRole/snatchit-kms-signer`,
      `arn:aws:sts::999999999999:assumed-role/SnatchIt-CredentialSign-Runtime/snatchit-kms-signer`,
      `arn:aws:sts::${ACCOUNT}:assumed-role/SnatchIt-CredentialSign-Runtime/other-session`,
    ]) {
      let err: unknown;
      try { parseAssumeRoleResponse(stsXml({ arn }), cfg, T0); } catch (e) { err = e; }
      expect(err).toEqual(expect.objectContaining({ message: 'aws_sts_identity_mismatch', errorClass: 'security' }));
      expectRedacted(err);
    }
  });

  it('a non-temporary access key (AKIA…) in the response ⇒ SECURITY aws_sts_credentials_not_temporary', () => {
    expect(() => parseAssumeRoleResponse(stsXml({ keyId: BASE_KEY_ID }), cfg, T0)).toThrow(expect.objectContaining({ message: 'aws_sts_credentials_not_temporary', errorClass: 'security' }));
  });

  it('invalid / past / too-soon / absurd Expiration ⇒ PERMANENT aws_sts_expiration_invalid', () => {
    for (const expiration of ['not-a-date', new Date(T0 - 1).toISOString(), new Date(T0 + 30_000).toISOString(), new Date(T0 + 13 * 3600_000).toISOString()]) {
      expect(() => parseAssumeRoleResponse(stsXml({ expiration }), cfg, T0)).toThrow(expect.objectContaining({ message: 'aws_sts_expiration_invalid', errorClass: 'permanent' }));
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════

describe('timeouts, throttling, service failures, AccessDenied — classification + bounded retry', () => {
  it('classifies STS failures: transient (429/5xx/Throttling…) vs permanent (AccessDenied, InvalidClientTokenId, ExpiredToken, SignatureDoesNotMatch, unknown)', () => {
    expect(classifyAwsStsFailure(429, '')).toEqual({ errorClass: 'transient', code: 'unknown' });
    expect(classifyAwsStsFailure(503, stsError('ServiceUnavailable'))).toEqual({ errorClass: 'transient', code: 'ServiceUnavailable' });
    expect(classifyAwsStsFailure(400, stsError('Throttling'))).toEqual({ errorClass: 'transient', code: 'Throttling' });
    expect(classifyAwsStsFailure(400, stsError('RequestLimitExceeded'))).toEqual({ errorClass: 'transient', code: 'RequestLimitExceeded' });
    expect(classifyAwsStsFailure(403, stsError('AccessDenied'))).toEqual({ errorClass: 'permanent', code: 'AccessDenied' });
    expect(classifyAwsStsFailure(403, stsError('InvalidClientTokenId'))).toEqual({ errorClass: 'permanent', code: 'InvalidClientTokenId' });
    expect(classifyAwsStsFailure(403, stsError('ExpiredToken'))).toEqual({ errorClass: 'permanent', code: 'ExpiredToken' });
    expect(classifyAwsStsFailure(403, stsError('SignatureDoesNotMatch'))).toEqual({ errorClass: 'permanent', code: 'SignatureDoesNotMatch' });
    expect(classifyAwsStsFailure(400, '<Code>bad code with spaces</Code>')).toEqual({ errorClass: 'permanent', code: 'unknown' });
    expect(extractStsErrorCode(`<Code>Access<script>Denied</Code>`)).toBe('unknown');
    expect(extractAwsJsonErrorCode('{"__type":"com.amazonaws.kms#AccessDeniedException","message":"SENTINEL arn:..."}')).toBe('AccessDeniedException');
    expect(extractAwsJsonErrorCode('{"__type":"ThrottlingException"}')).toBe('ThrottlingException');
    expect(extractAwsJsonErrorCode('not json SENTINEL')).toBe('unknown');
  });

  it('throttling is retried with backoff and then succeeds (2 attempts, 1 sleep)', async () => {
    const sleeps: number[] = [];
    const { transport, calls } = scriptedSts([{ status: 400, text: stsError('Throttling') }, ok()]);
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport, now: () => T0, sleep: (ms) => { sleeps.push(ms); return Promise.resolve(); } });
    const creds = await provider.getCredentials();
    expect(creds.accessKeyId).toBe(TEMP_KEY_ID);
    expect(calls).toHaveLength(2);
    expect(sleeps).toEqual([DEFAULT_ASSUME_ROLE_PROVIDER_OPTIONS.backoffMs[0]]);
  });

  it('5xx is retried up to maxAttempts then thrown as TRANSIENT; AccessDenied is NOT retried (1 attempt, PERMANENT)', async () => {
    const sleeps: number[] = [];
    const s1 = scriptedSts([{ status: 500, text: stsError('InternalFailure') }, { status: 502, text: '' }, { status: 503, text: stsError('ServiceUnavailable') }, ok()]);
    const p1 = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport: s1.transport, now: () => T0, sleep: (ms) => { sleeps.push(ms); return Promise.resolve(); } });
    await expectKmsError(p1.getCredentials(), 'aws_sts_http_503:ServiceUnavailable', 'transient');
    expect(s1.calls).toHaveLength(3);
    expect(sleeps).toEqual([200, 600]);

    const s2 = scriptedSts([{ status: 403, text: stsError('AccessDenied') }, ok()]);
    const p2 = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport: s2.transport, now: () => T0, sleep: immediateSleep });
    await expectKmsError(p2.getCredentials(), 'aws_sts_http_403:AccessDenied', 'permanent');
    expect(s2.calls).toHaveLength(1);
  });

  it('a transport rejection is TRANSIENT and its message is dropped (redacted)', async () => {
    const { transport, calls } = scriptedSts([new Error(`fetch failed to https://sts SENTINEL ${BASE_SECRET}`), ok()]);
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport, now: () => T0, sleep: immediateSleep });
    const creds = await provider.getCredentials(); // retried, then ok
    expect(creds.accessKeyId).toBe(TEMP_KEY_ID);
    expect(calls).toHaveLength(2);
    const only = scriptedSts([new Error(`boom SENTINEL`)]);
    const p2 = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport: only.transport, now: () => T0, sleep: immediateSleep, options: { maxAttempts: 1 } });
    await expectKmsError(p2.getCredentials(), 'aws_sts_transport_unavailable', 'transient');
  });

  it('a hanging transport times out (fake timers), aborts the signal, and is retried up to maxAttempts as TRANSIENT', async () => {
    vi.useFakeTimers();
    const { transport, calls } = scriptedSts(['hang', 'hang', 'hang']);
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport, now: () => Date.now(), sleep: immediateSleep, options: { timeoutMs: 1000 } });
    const pending = provider.getCredentials();
    const expectation = expectKmsError(pending, 'aws_sts_timeout', 'transient');
    await vi.advanceTimersByTimeAsync(1000);
    await vi.advanceTimersByTimeAsync(1000);
    await vi.advanceTimersByTimeAsync(1000);
    await expectation;
    expect(calls).toHaveLength(3);
    for (const c of calls) expect(c.signal.aborted).toBe(true);
  });
});

// ═══════════════════════════════════════════════════════════════════════════

describe('KMS signer core — both consumers, temporary-only credentials, scope, redaction', () => {
  const kp = genP256();
  const credentialSignBytes = new TextEncoder().encode('eyJhbGciOiJFUzI1NiJ9.eyJhdG9tIjoiYXRvbS0xIn0'); // credential-sign: header.payload bytes
  const doorManifestDigest = new TextEncoder().encode('{"manifest_id":"m-1","session_id":"s-1","manifest_digest":"abc"}'); // door-manifest: canonical digest object

  function buildSigner(sts: StsTransport, kms: KmsTransport, env = baseEnv(), provider?: AwsCredentialProvider, now = () => T0) {
    const credentialProvider = provider ?? new AssumeRoleCredentialProvider({ getEnv: env, transport: sts, now, sleep: immediateSleep });
    // Real timers (the per-attempt timeout must NOT fire before the mocked
    // transport resolves); backoff between KMS retries is 0 ms.
    const core = new AwsKmsSignerCore({ getEnv: env, credentialProvider, transport: kms, derToRaw: derToRawEcdsaP256, now, options: { backoffMs: [0] } });
    return { core, credentialProvider };
  }

  it('credential-sign-shaped AND door-manifest-shaped calls go through the SAME provider contract; ONE STS call for two signers sharing a provider; signatures verify; KMS saw only temporary creds + MessageType RAW + ECDSA_SHA_256', async () => {
    const sts = scriptedSts([ok()]);
    const kms = fakeKms(kp.privateKey);
    const provider = new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport: sts.transport, now: () => T0, sleep: immediateSleep });
    const credentialSign = buildSigner(sts.transport, kms.transport, baseEnv(), provider).core; // as credential-sign/index.ts wires it
    const doorManifest = buildSigner(sts.transport, kms.transport, baseEnv(), provider).core; // as door-manifest/index.ts wires it

    const sig1 = await credentialSign.sign(KEY_ARN, credentialSignBytes, 'ES256');
    const sig2 = await doorManifest.sign(KEY_ARN, doorManifestDigest, 'ES256');
    expect(sig1).toHaveLength(64);
    expect(sig2).toHaveLength(64);
    expect(verifyRaw(kp.publicKey, credentialSignBytes, sig1)).toBe(true);
    expect(verifyRaw(kp.publicKey, doorManifestDigest, sig2)).toBe(true);
    expect(verifyRaw(kp.publicKey, doorManifestDigest, sig1)).toBe(false);

    expect(sts.calls).toHaveLength(1);
    expect(kms.calls).toHaveLength(2);
    for (const c of kms.calls) {
      expect(c.credentials.accessKeyId).toBe(TEMP_KEY_ID);
      expect(c.credentials.sessionToken).toBe(TEMP_TOKEN);
      expect(c.credentials.accessKeyId).not.toBe(BASE_KEY_ID);
      expect(c.host).toBe('kms.us-east-1.amazonaws.com');
      const body = JSON.parse(c.body) as Record<string, string>;
      expect(body.KeyId).toBe(KEY_ARN);
      expect(body.MessageType).toBe('RAW');
      expect(body.SigningAlgorithm).toBe('ECDSA_SHA_256');
    }
  });

  it('NO base-credential fallback: when the provider fails, the KMS transport is never called and the provider error propagates', async () => {
    const sts = scriptedSts([{ status: 403, text: stsError('AccessDenied') }]);
    const kms = fakeKms(kp.privateKey);
    const { core } = buildSigner(sts.transport, kms.transport);
    await expectKmsError(core.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'aws_sts_http_403:AccessDenied', 'permanent');
    expect(kms.calls).toHaveLength(0);
  });

  it('NO base-credential fallback (structural): a provider that hands back non-temporary or expired credentials is refused before any KMS call', async () => {
    const kms = fakeKms(kp.privateKey);
    const baseAsIfTemporary: AwsCredentialProvider = { getCredentials: () => Promise.resolve({ accessKeyId: BASE_KEY_ID, secretAccessKey: BASE_SECRET, sessionToken: '', expiresAtMs: T0 + 3600_000 }) };
    const { core: c1 } = buildSigner(scriptedSts([]).transport, kms.transport, baseEnv(), baseAsIfTemporary);
    await expectKmsError(c1.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'kms_credentials_not_temporary', 'security');
    const noToken: AwsCredentialProvider = { getCredentials: () => Promise.resolve({ accessKeyId: TEMP_KEY_ID, secretAccessKey: TEMP_SECRET, sessionToken: '', expiresAtMs: T0 + 3600_000 }) };
    const { core: c2 } = buildSigner(scriptedSts([]).transport, kms.transport, baseEnv(), noToken);
    await expectKmsError(c2.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'kms_credentials_not_temporary', 'security');
    const expired: AwsCredentialProvider = { getCredentials: () => Promise.resolve({ accessKeyId: TEMP_KEY_ID, secretAccessKey: TEMP_SECRET, sessionToken: TEMP_TOKEN, expiresAtMs: T0 - 1 }) };
    const { core: c3 } = buildSigner(scriptedSts([]).transport, kms.transport, baseEnv(), expired);
    await expectKmsError(c3.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'kms_credentials_expired', 'permanent');
    expect(kms.calls).toHaveLength(0);
    expect(() => assertTemporaryCredentialsUsable({ accessKeyId: 'ASIA1', secretAccessKey: 'x', sessionToken: 't', expiresAtMs: T0 + 1 } as AwsTemporaryCredentials, T0)).toThrow(expect.objectContaining({ message: 'kms_credentials_not_temporary' }));
  });

  it('exact key scope: a handle in another account or region ⇒ SECURITY; a non-ARN handle ⇒ PERMANENT; no STS/KMS call either way', async () => {
    const sts = scriptedSts([ok()]);
    const kms = fakeKms(kp.privateKey);
    const { core } = buildSigner(sts.transport, kms.transport);
    await expectKmsError(core.sign(`arn:aws:kms:${REGION}:999999999999:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b`, credentialSignBytes, 'ES256'), 'kms_handle_scope_mismatch', 'security');
    await expectKmsError(core.sign(`arn:aws:kms:eu-west-1:${ACCOUNT}:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b`, credentialSignBytes, 'ES256'), 'kms_handle_scope_mismatch', 'security');
    await expectKmsError(core.sign('alias/snatchit-signer', credentialSignBytes, 'ES256'), 'kms_handle_malformed', 'permanent');
    await expectKmsError(core.sign('1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', credentialSignBytes, 'ES256'), 'kms_handle_malformed', 'permanent');
    expect(sts.calls).toHaveLength(0);
    expect(kms.calls).toHaveLength(0);
    expect(() => assertKmsHandleInScope(KEY_ARN, { region: REGION, roleAccountId: ACCOUNT })).not.toThrow();
  });

  it('ES256 pin preserved: EdDSA against the AWS signer ⇒ PERMANENT before config/credentials/network', async () => {
    const sts = scriptedSts([]);
    const kms = fakeKms(kp.privateKey);
    const { core } = buildSigner(sts.transport, kms.transport, baseEnv({ KMS_SIGNER_ROLE_ARN: undefined }));
    await expectKmsError(core.sign(KEY_ARN, credentialSignBytes, 'EdDSA'), 'unsupported_algorithm_for_provider', 'permanent');
    expect(sts.calls).toHaveLength(0);
    expect(kms.calls).toHaveLength(0);
  });

  it('KMS response validation preserved: wrong algorithm / wrong key echoed ⇒ SECURITY; malformed JSON ⇒ PERMANENT', async () => {
    const { core: c1 } = buildSigner(scriptedSts([ok()]).transport, fakeKms(kp.privateKey, { algEcho: 'RSASSA_PSS_SHA_256' }).transport);
    await expectKmsError(c1.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'kms_response_algorithm_mismatch', 'security');
    const { core: c2 } = buildSigner(scriptedSts([ok()]).transport, fakeKms(kp.privateKey, { keyIdEcho: `arn:aws:kms:${REGION}:${ACCOUNT}:key/ffffffff-ffff-4fff-8fff-ffffffffffff` }).transport);
    await expectKmsError(c2.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'kms_response_key_mismatch', 'security');
    const { core: c3 } = buildSigner(scriptedSts([ok()]).transport, fakeKms(kp.privateKey, { status: 200, body: 'not json' }).transport);
    // status 200 with garbage body: fakeKms only honours status≠200 for `body`, so craft a transport directly
    const garbage: KmsTransport = () => Promise.resolve({ status: 200, text: '{"KeyId": SENTINEL' });
    const { core: c4 } = buildSigner(scriptedSts([ok()]).transport, garbage);
    await expectKmsError(c4.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'kms_response_malformed', 'permanent');
    void c3;
  });

  it('KMS HTTP failures: code-only message (the body restating key ARN + principal is never surfaced); throttling retried; AccessDenied not', async () => {
    const body = JSON.stringify({ __type: 'com.amazonaws.kms#AccessDeniedException', message: `User arn:aws:sts::${ACCOUNT}:assumed-role/x/y is not authorized to perform kms:Sign on ${KEY_ARN} SENTINEL` });
    const denied = fakeKms(kp.privateKey, { status: 400, body });
    const { core: c1 } = buildSigner(scriptedSts([ok()]).transport, denied.transport);
    const err = await expectKmsError(c1.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'kms_http_400:AccessDeniedException', 'permanent');
    expect(err.message).not.toContain(KEY_ARN);
    expect(denied.calls).toHaveLength(1);

    let n = 0;
    const flaky: KmsTransport = (req) => {
      n++;
      if (n === 1) return Promise.resolve({ status: 400, text: JSON.stringify({ __type: 'ThrottlingException', message: 'slow down SENTINEL' }) });
      return fakeKms(kp.privateKey).transport(req);
    };
    const { core: c2 } = buildSigner(scriptedSts([ok()]).transport, flaky);
    const sig = await c2.sign(KEY_ARN, credentialSignBytes, 'ES256');
    expect(verifyRaw(kp.publicKey, credentialSignBytes, sig)).toBe(true);
    expect(n).toBe(2);
  });

  it('every failure path is redacted: no base secret, temp secret, session token, ExternalId, Authorization, or raw body in messages', async () => {
    const scenarios: Array<() => Promise<unknown>> = [
      () => new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport: scriptedSts([{ status: 403, text: stsError('AccessDenied') }]).transport, now: () => T0, sleep: immediateSleep }).getCredentials(),
      () => new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport: scriptedSts([{ status: 200, text: stsXml({ arn: 'arn:aws:sts::1:assumed-role/x/y' }) }]).transport, now: () => T0, sleep: immediateSleep }).getCredentials(),
      () => new AssumeRoleCredentialProvider({ getEnv: baseEnv(), transport: scriptedSts([{ status: 200, text: `<AssumeRoleResponse>${TEMP_TOKEN} ${BASE_SECRET}</AssumeRoleResponse>` }]).transport, now: () => T0, sleep: immediateSleep }).getCredentials(),
      () => new AssumeRoleCredentialProvider({ getEnv: baseEnv({ KMS_SIGNER_EXTERNAL_ID: 'no' }), transport: scriptedSts([]).transport, now: () => T0 }).getCredentials(),
      () => buildSigner(scriptedSts([ok()]).transport, fakeKms(kp.privateKey, { status: 500, body: `{"__type":"KMSInternalException","message":"${TEMP_TOKEN} SENTINEL"}` }).transport).core.sign(KEY_ARN, credentialSignBytes, 'ES256'),
    ];
    for (const run of scenarios) {
      let err: unknown;
      try { await run(); } catch (e) { err = e; }
      expect(err).toBeInstanceOf(KmsSignError);
      expectRedacted(err);
      expect(JSON.stringify(err)).not.toMatch(/SENTINEL|SESSIONTOKEN|BASESECRET/);
    }
  });

  it('DARK default preserved: provider selection is env-driven and anything but "aws" is the unconfigured, always-throwing signer', async () => {
    expect(selectKmsProviderKind(() => undefined)).toBe('unconfigured');
    expect(selectKmsProviderKind((k) => (k === 'KMS_PROVIDER' ? 'AWS' : undefined))).toBe('unconfigured');
    expect(selectKmsProviderKind((k) => (k === 'KMS_PROVIDER' ? 'gcp' : undefined))).toBe('unconfigured');
    expect(selectKmsProviderKind((k) => (k === 'KMS_PROVIDER' ? 'aws' : undefined))).toBe('aws');
    await expectKmsError(new UnconfiguredKmsSigner().sign(KEY_ARN, credentialSignBytes, 'ES256'), 'kms_provider_unconfigured', 'permanent');
    // and with KMS_PROVIDER=aws but NO base credentials, the core fails closed before any network call
    const sts = scriptedSts([ok()]);
    const kms = fakeKms(kp.privateKey);
    const { core } = buildSigner(sts.transport, kms.transport, baseEnv({ AWS_ACCESS_KEY_ID: undefined, AWS_SECRET_ACCESS_KEY: undefined }));
    await expectKmsError(core.sign(KEY_ARN, credentialSignBytes, 'ES256'), 'aws_kms_credentials_unavailable', 'permanent');
    expect(sts.calls).toHaveLength(0);
    expect(kms.calls).toHaveLength(0);
  });
});
