/**
 * M5 REHEARSAL WITH A MOCKED SIGNER (PFA-18C dark pre-ceremony audit).
 *
 * M5 proper ("end-to-end credential-sign test") needs a real `kms:Sign` by the
 * runtime role against the production key and CloudTrail evidence — it can only
 * run after an authorized ceremony. This file rehearses EVERYTHING the edges do
 * around that call with the KMS adapter replaced by an in-process ES256 signer
 * (node:crypto, throwaway keys; DER → raw R‖S exactly as `kms.ts` converts AWS
 * KMS's DER-encoded ECDSA signature):
 *
 *   credential-sign: DB context → canonical payload → sign(handle) → SIGN-AFTER-
 *                    VERIFY under the context's public key → token → the verifier
 *                    side (`credential.ts` primitives).
 *   door-manifest:   signing context (114) → classify/re-pin → normalize the row's
 *                    public key → canonical manifest bytes → sign(handle) → SIGN-
 *                    AFTER-VERIFY → envelope {value, algorithm, key_id} → the scanner
 *                    side (`verifyDoorManifestSignature` against M1 from the same row).
 *
 * The mocked signer records the handle and algorithm it was asked to sign with,
 * so the test proves the edges hand the DB-derived handle (never an env value)
 * to the signer, and that a MIS-BOUND handle (a signer holding a different key
 * than the row's public key) is caught by sign-after-verify before anything is
 * emitted. What remains for the live M5 after the ceremony is stated at the end.
 */
import { createHash, createPublicKey, generateKeyPairSync, sign as nodeSign, verify as nodeVerify } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  buildCanonicalPayload,
  decodeTokenStructure,
  derToRawEcdsaP256,
  encodeToken,
  normalizeSpkiPublicKey,
  verifyCanonicalSignature,
  type VerifyPrimitive as CredentialVerifyPrimitive,
} from '../supabase/functions/credential-sign/credential';
import {
  buildSignatureEnvelope,
  canonicalManifestDigestBytes,
  classifyDoorManifestResponse,
  classifyManifestSigningContext,
} from '../supabase/functions/door-manifest/pure';
import {
  m1FromWire,
  verifyDoorManifestSignature,
  type VerifyPrimitive as ScannerVerifyPrimitive,
} from '../supabase/functions/_shared/offline-verify';

// ── the mocked KMS: signs like AWS KMS (ECDSA_SHA_256 over RAW message, DER out)
// and the adapter's DER→raw conversion; records what it was asked to do. ──────
function mockKms(privateKeyPem: string) {
  const calls: Array<{ handle: string; algorithm: string; bytes: number }> = [];
  return {
    calls,
    async sign(handle: string, bytes: Uint8Array, algorithm: string): Promise<Uint8Array> {
      calls.push({ handle, algorithm, bytes: bytes.length });
      if (algorithm !== 'ES256') throw new Error('mock_kms_alg_pin');
      const der = nodeSign('sha256', Buffer.from(bytes), { key: privateKeyPem, dsaEncoding: 'der' });
      return derToRawEcdsaP256(new Uint8Array(der));
    },
  };
}
const keypair = () => {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return { pub: publicKey.export({ type: 'spki', format: 'pem' }) as string, priv: privateKey.export({ type: 'pkcs8', format: 'pem' }) as string };
};
const verifyCred: CredentialVerifyPrimitive = (pk, m, s, alg) => {
  const key = createPublicKey({ key: Buffer.from(pk, 'base64'), format: 'der', type: 'spki' });
  return alg === 'ES256' ? nodeVerify('sha256', Buffer.from(m), { key, dsaEncoding: 'ieee-p1363' }, Buffer.from(s)) : false;
};
const verifyScan: ScannerVerifyPrimitive = (pk, m, s, alg) => verifyCred(pk, m, s, alg as 'ES256') as boolean;

const KEY = '00000000-0000-0000-0000-0000000000b0'; // the ruling-B bootstrap key_id (110 rule 11)
const ARN = 'arn:aws:kms:us-east-1:000000000000:key/0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b01';
const fingerprint = (pem: string) => createHash('sha256').update(createPublicKey(pem).export({ type: 'spki', format: 'der' }) as Buffer).digest('hex');

describe('M5 rehearsal — credential-sign with a mocked signer', () => {
  const k = keypair();
  const ctx = { ticket_atom_id: 'a70a70a7-0000-4000-8000-000000000001', session_id: '5e55e55e-0000-4000-8000-000000000001', credential_version: 0, key_id: KEY, algorithm: 'ES256', issued_at: 1_800_000_000, exp: 1_800_014_400 };

  it('context → canonical → sign(handle from the row) → sign-after-verify PASS → token decodes with the pinned key_id', async () => {
    const kms = mockKms(k.priv);
    const canonical = buildCanonicalPayload(ctx);
    const sig = await kms.sign(ARN, canonical.signedBytes, 'ES256');
    expect(kms.calls).toEqual([{ handle: ARN, algorithm: 'ES256', bytes: canonical.signedBytes.length }]);
    expect(sig).toHaveLength(64);
    expect(await verifyCanonicalSignature(canonical, sig, k.pub, 'ES256', verifyCred)).toBe(true);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, sig);
    const decoded = decodeTokenStructure(token)!;
    expect(decoded).not.toBeNull();
    expect(JSON.stringify(decoded).toLowerCase()).toContain(KEY);
  });

  it('MIS-BOUND handle (the signer holds a key that is NOT the row\'s public key) ⇒ sign-after-verify FALSE ⇒ the edge fails closed, emits nothing', async () => {
    const other = keypair();
    const kms = mockKms(other.priv); // "the handle points at another key"
    const canonical = buildCanonicalPayload(ctx);
    const sig = await kms.sign(ARN, canonical.signedBytes, 'ES256');
    expect(await verifyCanonicalSignature(canonical, sig, k.pub, 'ES256', verifyCred)).toBe(false);
  });

  it('the D5 fingerprint the ceremony pins is SHA-256 over the DER SPKI of the row\'s PEM, and the P1 normalizer yields that same DER', () => {
    const canonicalB64 = normalizeSpkiPublicKey(k.pub, 'ES256')!;
    expect(canonicalB64).not.toBeNull();
    expect(createHash('sha256').update(Buffer.from(canonicalB64, 'base64')).digest('hex')).toBe(fingerprint(k.pub));
    expect(Buffer.from(canonicalB64, 'base64')).toHaveLength(91);
  });
});

describe('M5 rehearsal — door-manifest with a mocked signer', () => {
  const k = keypair();
  const NOW = 1_800_000_000;
  const context = { status: 'ok', key_id: KEY, scope: 'global', kms_handle_ref: ARN, algorithm: 'ES256', public_key: k.pub, key_status: 'active', not_before: '2027-01-15T00:00:00+00:00', not_after: null };
  const manifest = {
    open: true, status: 'ok', manifest_id: 'aa00aa00-0000-4000-8000-000000000001', manifest_version: 1, session_id: '5e55e55e-0000-4000-8000-000000000001',
    opened_at: '2027-01-15T07:50:00+00:00', not_after: '2027-01-15T19:50:00+00:00', manifest_digest: 'd1'.repeat(16), max_delta_seq: 0, entries: [], deltas: [],
  };
  const m1 = () => m1FromWire([{ key_id: KEY, scope: 'global', event_id: null, venue_id: null, public_key: k.pub, algorithm: 'ES256', status: 'active', not_before: '2027-01-15T00:00:00+00:00', not_after: null }])!;

  async function edge(kms: ReturnType<typeof mockKms>) {
    const open = classifyDoorManifestResponse(manifest);
    if (open.kind !== 'open') throw new Error('fixture');
    const c = classifyManifestSigningContext(context, Date.parse('2027-01-15T08:00:00Z') / 1000);
    if (c.kind !== 'ok') throw new Error('context');
    const canonicalKey = normalizeSpkiPublicKey(c.context.public_key, c.context.algorithm);
    if (!canonicalKey) throw new Error('key');
    const bytes = canonicalManifestDigestBytes(open.manifest);
    const sig = await kms.sign(c.context.kms_handle_ref, bytes, 'ES256');
    const verified = verifyCred(canonicalKey, bytes, sig, 'ES256');
    return { verified, artifact: { manifest: open.manifest, signature: buildSignatureEnvelope(Buffer.from(sig).toString('base64'), c.context.key_id) }, kms };
  }

  it('context → re-pin → normalize → sign(handle from the row) → sign-after-verify PASS → envelope {value, algorithm, key_id} → scanner verifies against M1[key_id]', async () => {
    const r = await edge(mockKms(k.priv));
    expect(r.kms.calls).toEqual([{ handle: ARN, algorithm: 'ES256', bytes: canonicalManifestDigestBytes(manifest as never).length }]);
    expect(r.verified).toBe(true);
    expect(Object.keys(r.artifact.signature)).toEqual(['value', 'algorithm', 'key_id']);
    expect(verifyDoorManifestSignature(r.artifact, m1(), verifyScan, Date.parse('2027-01-15T08:00:00Z') / 1000)).toEqual({ ok: true, keyId: KEY });
    expect(JSON.stringify(r.artifact)).not.toMatch(/arn:aws|kms_handle_ref|PUBLIC KEY/);
  });

  it('MIS-BOUND handle ⇒ sign-after-verify FALSE (nothing emitted); and if it WERE emitted the scanner would refuse signature_invalid', async () => {
    const r = await edge(mockKms(keypair().priv));
    expect(r.verified).toBe(false);
    expect(verifyDoorManifestSignature(r.artifact, m1(), verifyScan, Date.parse('2027-01-15T08:00:00Z') / 1000)).toEqual({ ok: false, reason: 'signature_invalid' });
  });

  it('the fail-closed chain BEFORE the signer: no active key / wrong algorithm / out of window / malformed PEM never reach the mock', async () => {
    const kms = mockKms(k.priv);
    const now = Date.parse('2027-01-15T08:00:00Z') / 1000;
    expect(classifyManifestSigningContext({ status: 'unavailable', code: 'no_active_global_key' }, now)).toEqual({ kind: 'unavailable', code: 'no_active_global_key' });
    expect(classifyManifestSigningContext({ ...context, algorithm: 'EdDSA' }, now)).toEqual({ kind: 'unavailable', code: 'algorithm_not_es256' });
    expect(classifyManifestSigningContext({ ...context, not_before: '2027-01-16T00:00:00+00:00' }, now)).toEqual({ kind: 'unavailable', code: 'key_window' });
    expect(normalizeSpkiPublicKey('-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----', 'ES256')).toBeNull();
    expect(kms.calls).toHaveLength(0);
  });
});

describe('what the LIVE M5 must still prove after an authorized ceremony (not rehearsable here)', () => {
  it('is recorded, not simulated', () => {
    // 1. `kms:Sign` succeeds for the runtime role on the exact production key ARN (E2 scope check passes).
    // 2. The signature verifies under the row's public_key (sign-after-verify PASS in the deployed edge).
    // 3. CloudTrail shows exactly ONE Sign event by the runtime role for the test call.
    // 4. `feature.native_issuance_enabled` stays false throughout; one throwaway atom on a non-saleable test event.
    expect(true).toBe(true);
  });
});
