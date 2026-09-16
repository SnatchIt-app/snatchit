/**
 * E2 follow-up — RESPONSE/ERROR REDACTION across every STS/KMS error path.
 *
 * Sentinel ARNs, account ids, principals, algorithm strings, session tokens
 * and raw bodies are planted in responses/inputs; every thrown `KmsSignError`
 * is then checked in all the forms an operator could ever see it:
 * `error.message`, `String(error)`, `error.stack`, `JSON.stringify(error)`,
 * and a Sentry-style logging payload built from the error. None may carry a
 * sentinel. Codes must be STABLE strings from the documented set.
 */
import { describe, expect, it } from 'vitest';
import {
  classifyAwsStsFailure,
  extractAwsJsonErrorCode,
  extractStsErrorCode,
  KmsSignError,
  parseAssumeRoleConfig,
  parseAssumeRoleResponse,
  validateAwsSignResponse,
} from '../supabase/functions/credential-sign/kms-taxonomy';

const SENTINEL_ARN = 'arn:aws:kms:us-east-1:999988887777:key/deadbeef-dead-4bad-8bad-deadbeefdead';
const SENTINEL_ACCOUNT = '999988887777';
const SENTINEL_PRINCIPAL = 'arn:aws:sts::999988887777:assumed-role/EvilRole/evil-session';
const SENTINEL_ALG = 'RSASSA_PSS_SHA_512_SENTINEL';
const SENTINEL_TOKEN = 'FQoGZXIvYXdzSENTINELTOKEN0123456789';
const SENTINELS = [SENTINEL_ARN, SENTINEL_ACCOUNT, SENTINEL_PRINCIPAL, SENTINEL_ALG, SENTINEL_TOKEN, 'SENTINEL', 'deadbeef', 'EvilRole', '(absent)'];

/** Every representation an error can take on its way to a human or a log. */
function representations(err: unknown): string[] {
  const e = err as Error & { errorClass?: string };
  const sentryLike = JSON.stringify({ level: 'error', message: e.message, name: e.name, extra: { kms_error_class: e.errorClass } });
  const consoleLike = `credential-sign: KMS sign failed: ${e.message} (${e.errorClass})`;
  return [e.message, String(e), e.stack ?? '', JSON.stringify(e), sentryLike, consoleLike, Object.keys(e).join(',')];
}

function expectRedacted(err: unknown): void {
  expect(err).toBeInstanceOf(KmsSignError);
  for (const repr of representations(err)) {
    for (const s of SENTINELS) expect(repr, `leaks '${s}' via ${repr.slice(0, 40)}…`).not.toContain(s);
  }
}

function thrown(fn: () => unknown): KmsSignError {
  try {
    fn();
  } catch (e) {
    return e as KmsSignError;
  }
  throw new Error('expected a throw');
}

describe('validateAwsSignResponse — stable redacted codes, classifications preserved', () => {
  const REQUESTED = 'arn:aws:kms:us-east-1:111111111111:key/0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f';

  it('wrong algorithm echoed ⇒ exactly `kms_response_algorithm_mismatch` (SECURITY); the echoed value never appears', () => {
    const err = thrown(() => validateAwsSignResponse({ KeyId: REQUESTED, Signature: 'MEUCIQ==', SigningAlgorithm: SENTINEL_ALG }, REQUESTED, 'ECDSA_SHA_256'));
    expect(err.message).toBe('kms_response_algorithm_mismatch');
    expect(err.errorClass).toBe('security');
    expectRedacted(err);
  });

  it('absent algorithm ⇒ same stable code (no "(absent)" suffix)', () => {
    const err = thrown(() => validateAwsSignResponse({ KeyId: REQUESTED, Signature: 'MEUCIQ==' }, REQUESTED, 'ECDSA_SHA_256'));
    expect(err.message).toBe('kms_response_algorithm_mismatch');
    expect(err.errorClass).toBe('security');
    expectRedacted(err);
  });

  it('wrong key echoed ⇒ exactly `kms_response_key_mismatch` (SECURITY); the sentinel ARN / account never appears', () => {
    const err = thrown(() => validateAwsSignResponse({ KeyId: SENTINEL_ARN, Signature: 'MEUCIQ==', SigningAlgorithm: 'ECDSA_SHA_256' }, REQUESTED, 'ECDSA_SHA_256'));
    expect(err.message).toBe('kms_response_key_mismatch');
    expect(err.errorClass).toBe('security');
    expectRedacted(err);
  });

  it('absent key ⇒ same stable code; requested handle never appears either', () => {
    const err = thrown(() => validateAwsSignResponse({ Signature: 'MEUCIQ==', SigningAlgorithm: 'ECDSA_SHA_256' }, SENTINEL_ARN, 'ECDSA_SHA_256'));
    expect(err.message).toBe('kms_response_key_mismatch');
    expect(err.errorClass).toBe('security');
    expectRedacted(err);
  });

  it('missing signature ⇒ exactly `kms_response_missing_signature` (PERMANENT)', () => {
    const err = thrown(() => validateAwsSignResponse({ KeyId: SENTINEL_ARN, SigningAlgorithm: SENTINEL_ALG }, SENTINEL_ARN, 'ECDSA_SHA_256'));
    expect(err.message).toBe('kms_response_missing_signature');
    expect(err.errorClass).toBe('permanent');
    expectRedacted(err);
  });

  it('a well-formed response still validates (no behaviour change)', () => {
    expect(validateAwsSignResponse({ KeyId: REQUESTED, Signature: 'MEUCIQ==', SigningAlgorithm: 'ECDSA_SHA_256' }, REQUESTED, 'ECDSA_SHA_256')).toBe('MEUCIQ==');
  });
});

describe('surfaced error identifiers are allowlisted — response-derived tokens cannot reach a message', () => {
  it('STS: known codes pass through; an unknown-but-well-formed code (which could encode an id) becomes `unknown`', () => {
    expect(extractStsErrorCode('<Error><Code>AccessDenied</Code></Error>')).toBe('AccessDenied');
    expect(extractStsErrorCode('<Error><Code>Throttling</Code></Error>')).toBe('Throttling');
    expect(extractStsErrorCode(`<Error><Code>${SENTINEL_ACCOUNT}</Code></Error>`)).toBe('unknown');
    expect(extractStsErrorCode('<Error><Code>ASIAIOSFODNN7EXAMPLE</Code></Error>')).toBe('unknown');
    expect(extractStsErrorCode(`<Error><Code>${SENTINEL_TOKEN}</Code></Error>`)).toBe('unknown');
    expect(extractStsErrorCode('<Error><Code>Access<Denied</Code></Error>')).toBe('unknown');
    expect(extractStsErrorCode('')).toBe('unknown');
    const c = classifyAwsStsFailure(403, `<Error><Code>EvilRole${SENTINEL_ACCOUNT}</Code><Message>${SENTINEL_PRINCIPAL}</Message></Error>`);
    expect(c).toEqual({ errorClass: 'permanent', code: 'unknown' });
    // classification still sees the raw code for transient detection
    expect(classifyAwsStsFailure(400, '<Code>RequestLimitExceeded</Code>').errorClass).toBe('transient');
    expect(classifyAwsStsFailure(503, `<Code>${SENTINEL_ACCOUNT}</Code>`)).toEqual({ errorClass: 'transient', code: 'unknown' });
  });

  it('KMS: known __type identifiers pass through (namespace stripped); anything else becomes `unknown`', () => {
    expect(extractAwsJsonErrorCode('{"__type":"com.amazonaws.kms#AccessDeniedException","message":"x"}')).toBe('AccessDeniedException');
    expect(extractAwsJsonErrorCode('{"__type":"ThrottlingException"}')).toBe('ThrottlingException');
    expect(extractAwsJsonErrorCode('{"__type":"DisabledException"}')).toBe('DisabledException');
    expect(extractAwsJsonErrorCode(`{"__type":"${SENTINEL_ACCOUNT}"}`)).toBe('unknown');
    expect(extractAwsJsonErrorCode(`{"__type":"Evil#${SENTINEL_ALG}"}`)).toBe('unknown');
    expect(extractAwsJsonErrorCode(`{"__type":"KeyLeak${SENTINEL_ACCOUNT}Exception","message":"${SENTINEL_ARN}"}`)).toBe('unknown');
    expect(extractAwsJsonErrorCode(`not json ${SENTINEL_ARN}`)).toBe('unknown');
  });
});

describe('STS response/config error paths — field/tag names only', () => {
  const cfg = parseAssumeRoleConfig((k) => ({
    AWS_REGION: 'us-east-1',
    KMS_SIGNER_ROLE_ARN: 'arn:aws:iam::111111111111:role/Runtime',
    KMS_SIGNER_EXTERNAL_ID: 'ext-0000000000',
  })[k]);
  const T0 = Date.parse('2026-09-05T12:00:00.000Z');

  it('identity mismatch never surfaces the echoed principal', () => {
    const xml = `<AssumeRoleResponse><AssumedRoleUser><Arn>${SENTINEL_PRINCIPAL}</Arn></AssumedRoleUser><Credentials><AccessKeyId>ASIAIOSFODNN7EXAMPLE</AccessKeyId><SecretAccessKey>abcdefghijklmnopqrstuvwxyz</SecretAccessKey><SessionToken>${SENTINEL_TOKEN}</SessionToken><Expiration>${new Date(T0 + 3600_000).toISOString()}</Expiration></Credentials></AssumeRoleResponse>`;
    const err = thrown(() => parseAssumeRoleResponse(xml, cfg, T0));
    expect(err.message).toBe('aws_sts_identity_mismatch');
    expect(err.errorClass).toBe('security');
    expectRedacted(err);
  });

  it('malformed document / missing tags never surface body content (tokens, ARNs)', () => {
    for (const xml of [
      `<html>${SENTINEL_TOKEN} ${SENTINEL_ARN}</html>`,
      `<AssumeRoleResponse>${SENTINEL_TOKEN}</AssumeRoleResponse>`,
      `<AssumeRoleResponse><AssumedRoleUser><Arn>arn:aws:sts::111111111111:assumed-role/Runtime/snatchit-kms-signer</Arn></AssumedRoleUser><Credentials><SessionToken>${SENTINEL_TOKEN}</SessionToken></Credentials></AssumeRoleResponse>`,
    ]) {
      const err = thrown(() => parseAssumeRoleResponse(xml, cfg, T0));
      expect(err.message).toMatch(/^aws_sts_response_malformed:(document|AssumedRoleUser|Credentials|Arn|AccessKeyId|SecretAccessKey|SessionToken|Expiration)$/);
      expect(err.errorClass).toBe('permanent');
      expectRedacted(err);
    }
  });

  it('configuration errors name the field, never the value (a role ARN with a sentinel account, an ExternalId with a sentinel)', () => {
    const bad = (over: Record<string, string>) => parseAssumeRoleConfig((k) => ({
      AWS_REGION: 'us-east-1', KMS_SIGNER_ROLE_ARN: 'arn:aws:iam::111111111111:role/Runtime', KMS_SIGNER_EXTERNAL_ID: 'ext-0000000000', ...over,
    })[k]);
    for (const [over, field] of [
      [{ KMS_SIGNER_ROLE_ARN: `arn:aws:iam::${SENTINEL_ACCOUNT}:user/EvilRole` }, 'role_arn'],
      [{ KMS_SIGNER_EXTERNAL_ID: `bad value ${SENTINEL_TOKEN}` }, 'external_id'],
      [{ AWS_REGION: `${SENTINEL_ACCOUNT}.evil` }, 'region'],
      [{ KMS_SIGNER_SESSION_NAME: `evil/${SENTINEL_ACCOUNT}` }, 'session_name'],
    ] as Array<[Record<string, string>, string]>) {
      const err = thrown(() => bad(over));
      expect(err.message).toBe(`aws_sts_config_invalid:${field}`);
      expect(err.errorClass).toBe('permanent');
      expectRedacted(err);
    }
  });
});
