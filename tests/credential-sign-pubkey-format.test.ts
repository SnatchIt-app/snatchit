/**
 * P1-PUBKEY-FORMAT — trusted public-key normalization across every verify path.
 *
 * WHAT THIS PROVES
 *   The DB / runbook D3 stores `kernel.signing_key.public_key` as an SPKI PEM
 *   block; the verify primitives (edge WebCrypto, `node:crypto` here) consume
 *   bare base64 SPKI DER. Before `normalizeSpkiPublicKey`, the edge `atob()`'d
 *   the PEM and every verification failed. These tests use REAL keys (P-256 for
 *   ES256, Ed25519 for EdDSA — throwaway, generated per run) and prove:
 *     1. the parser's acceptance/rejection matrix (PEM LF/CRLF, bare base64,
 *        malformed PEM/base64, PRIVATE KEY, other labels, base64url, wrong
 *        key type for the pinned algorithm, compressed point, truncation);
 *     2. the two copies (`credential.ts`, `_shared/offline-verify.ts`) agree
 *        byte-for-byte on that whole matrix;
 *     3. `verifyToken` end-to-end with a PEM trusted key: PASS; bare: PASS;
 *        wrong key / altered message / altered signature: FAIL as
 *        `signature_invalid`; malformed key: `malformed_public_key` (distinct);
 *        the PFA-PT-8 alg pin is unchanged (header alg ≠ trusted alg ⇒
 *        `alg_mismatch` before any key parsing);
 *     4. `verifyCanonicalSignature` (the edge's sign-after-verify) with the
 *        PEM the DB will actually return: PASS / wrong key FAIL / malformed
 *        FALSE — using the exact `atob`-based WebCrypto primitive shape the
 *        edge injects, so the regression is reproduced then closed;
 *     5. `offlineVerify` admits with a PEM M1 entry (EdDSA, the suite's
 *        existing contract, and ES256 via an injected P-256 primitive) and
 *        refuses `malformed_public_key` for a malformed M1 entry.
 *   AWS signing stays ES256-only; EdDSA coverage here is confined to what the
 *   verifier contract already supports (offline door / vitest fixtures).
 */
import { createPublicKey, generateKeyPairSync, sign as nodeSign, verify as nodeVerify, webcrypto, type KeyObject } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  buildCanonicalPayload,
  DOMAIN,
  encodeToken,
  normalizeSpkiPublicKey,
  verifyCanonicalSignature,
  verifyToken,
  type SigningAlgorithm,
  type TicketSigningContext,
  type TrustedKeyResolver,
  type VerifyPrimitive,
} from '../supabase/functions/credential-sign/credential';
import {
  DOMAIN as OFFLINE_DOMAIN,
  normalizeSpkiPublicKey as normalizeOffline,
  offlineVerify,
  type M1Entry,
  type M1Manifest,
  type M2Manifest,
  type OfflineToken,
  type OfflineVerifyContext,
  type VerifyPrimitive as OfflineVerifyPrimitive,
} from '../supabase/functions/_shared/offline-verify';

// ── Real key fixtures (throwaway, per run) ───────────────────────────────

interface Fixture { privateKey: KeyObject; der: Buffer; bare: string; pem: string }

function genP256(): Fixture {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const der = publicKey.export({ type: 'spki', format: 'der' }) as Buffer;
  const pem = publicKey.export({ type: 'spki', format: 'pem' }) as string; // openssl-style, 64-col, LF
  return { privateKey, der, bare: der.toString('base64'), pem };
}
function genEd25519(): Fixture {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' }) as Buffer;
  const pem = publicKey.export({ type: 'spki', format: 'pem' }) as string;
  return { privateKey, der, bare: der.toString('base64'), pem };
}

/** DER-encoded ECDSA (what AWS KMS returns) → raw R||S (what the wire carries). */
function signEs256Raw(privateKey: KeyObject, bytes: Uint8Array): Uint8Array {
  return new Uint8Array(nodeSign('sha256', Buffer.from(bytes), { key: privateKey, dsaEncoding: 'ieee-p1363' }));
}
function signEd25519(privateKey: KeyObject, bytes: Uint8Array): Uint8Array {
  return new Uint8Array(nodeSign(null, Buffer.from(bytes), privateKey));
}

/** node:crypto primitive in the shape the suites already use. */
const verifyNode: VerifyPrimitive = (publicKeyB64, message, signature, alg) => {
  const key = createPublicKey({ key: Buffer.from(publicKeyB64, 'base64'), format: 'der', type: 'spki' });
  if (alg === 'ES256') return nodeVerify('sha256', Buffer.from(message), { key, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature));
  if (alg === 'EdDSA') return nodeVerify(null, Buffer.from(message), key, Buffer.from(signature));
  return false;
};

/** The EXACT primitive shape `credential-sign/index.ts` injects (`atob` +
 *  WebCrypto `importKey('spki')`) — reproduced here so the regression the fix
 *  closes is exercised against the real decoder behaviour, not a stand-in. */
const verifyWithWebCryptoLikeTheEdge: VerifyPrimitive = async (publicKeyB64, message, signature, alg) => {
  try {
    const binary = atob(publicKeyB64);
    const der = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
    const subtle = webcrypto.subtle;
    // Copies: `tsc -p .` (lib.dom strictness) wants `Uint8Array<ArrayBuffer>`
    // for BufferSource; a fresh `new Uint8Array(x)` is exactly that.
    const sig = new Uint8Array(signature);
    const msg = new Uint8Array(message);
    if (alg === 'EdDSA') {
      const key = await subtle.importKey('spki', der, { name: 'Ed25519' }, false, ['verify']);
      return await subtle.verify({ name: 'Ed25519' }, key, sig, msg);
    }
    if (alg === 'ES256') {
      const key = await subtle.importKey('spki', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
      return await subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, sig, msg);
    }
    return false;
  } catch {
    return false;
  }
};

const ATOM_ID = '11111111-1111-4111-8111-111111111111';
const SESSION_ID = '22222222-2222-4222-8222-222222222222';
const KEY_ID = '33333333-3333-4333-8333-333333333333';
const NOW = Math.floor(Date.parse('2026-09-05T12:00:00.000Z') / 1000);

function ctx(algorithm: SigningAlgorithm): TicketSigningContext {
  return {
    ticket_atom_id: ATOM_ID,
    session_id: SESSION_ID,
    credential_version: 3,
    key_id: KEY_ID,
    algorithm,
    issued_at: '2026-09-05T12:00:00.000Z',
    exp: '2026-09-05T16:00:00.000Z',
  };
}

function mintToken(fx: Fixture, algorithm: SigningAlgorithm): { token: string; canonical: ReturnType<typeof buildCanonicalPayload> } {
  const canonical = buildCanonicalPayload(ctx(algorithm));
  const sig = algorithm === 'ES256' ? signEs256Raw(fx.privateKey, canonical.signedBytes) : signEd25519(fx.privateKey, canonical.signedBytes);
  return { token: encodeToken(canonical.headerB64, canonical.payloadB64, sig), canonical };
}

function resolver(public_key: string, algorithm: SigningAlgorithm): TrustedKeyResolver {
  return (kid) => (kid === KEY_ID ? { public_key, algorithm } : null);
}

// ═══════════════════════════════════════════════════════════════════════════

describe('normalizeSpkiPublicKey — acceptance matrix (real P-256 / Ed25519 SPKI)', () => {
  const p256 = genP256();
  const ed = genEd25519();

  it('accepts openssl-style PEM (LF) and yields the canonical bare base64 identical to the DER', () => {
    expect(normalizeSpkiPublicKey(p256.pem, 'ES256')).toBe(p256.bare);
    expect(normalizeSpkiPublicKey(ed.pem, 'EdDSA')).toBe(ed.bare);
    expect(p256.der.length).toBe(91);
    expect(ed.der.length).toBe(44);
  });

  it('accepts CRLF PEM, PEM with surrounding whitespace/trailing newline (as `cat pub.pem` yields), and PEM whose body is one long line', () => {
    const crlf = p256.pem.replace(/\n/g, '\r\n');
    expect(normalizeSpkiPublicKey(crlf, 'ES256')).toBe(p256.bare);
    expect(normalizeSpkiPublicKey(`\n  ${p256.pem}\n\n`, 'ES256')).toBe(p256.bare);
    const oneLine = `-----BEGIN PUBLIC KEY-----\n${p256.bare}\n-----END PUBLIC KEY-----`;
    expect(normalizeSpkiPublicKey(oneLine, 'ES256')).toBe(p256.bare);
  });

  it('accepts the pre-existing bare base64 SPKI representation unchanged', () => {
    expect(normalizeSpkiPublicKey(p256.bare, 'ES256')).toBe(p256.bare);
    expect(normalizeSpkiPublicKey(ed.bare, 'EdDSA')).toBe(ed.bare);
  });

  it('rejects PRIVATE KEY material under any label, even if the bytes were otherwise well-formed', () => {
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const privPem = privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;
    expect(normalizeSpkiPublicKey(privPem, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`-----BEGIN PRIVATE KEY-----\n${p256.bare}\n-----END PRIVATE KEY-----`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`-----BEGIN EC PRIVATE KEY-----\n${p256.bare}\n-----END EC PRIVATE KEY-----`, 'ES256')).toBeNull();
  });

  it('rejects other PEM labels, mismatched/missing END, encapsulated headers, and trailing junk', () => {
    const body = p256.pem.split('\n').slice(1, -2).join('\n');
    expect(normalizeSpkiPublicKey(`-----BEGIN CERTIFICATE-----\n${body}\n-----END CERTIFICATE-----`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`-----BEGIN RSA PUBLIC KEY-----\n${body}\n-----END RSA PUBLIC KEY-----`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`-----BEGIN PUBLIC KEY-----\n${body}\n-----END CERTIFICATE-----`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`-----BEGIN PUBLIC KEY-----\n${body}`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`-----BEGIN PUBLIC KEY-----\nProc-Type: 4,ENCRYPTED\n\n${body}\n-----END PUBLIC KEY-----`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`${p256.pem}junk`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`-----BEGIN PUBLIC KEY-----\n\n-----END PUBLIC KEY-----`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey('-----BEGIN PUBLIC KEY-----', 'ES256')).toBeNull();
  });

  it('rejects malformed bare base64: base64url, unpadded, over-padded, internal whitespace, non-canonical trailing bits, non-alphabet chars, non-strings', () => {
    // base64url: find a P-256 key whose standard base64 contains '+' or '/'
    // (each of the 124 symbols is uniform over the alphabet; ~98% per key).
    let urlFx = p256;
    for (let i = 0; i < 40 && !/[+/]/.test(urlFx.bare); i++) urlFx = genP256();
    expect(/[+/]/.test(urlFx.bare)).toBe(true);
    expect(normalizeSpkiPublicKey(urlFx.bare.replace(/\+/g, '-').replace(/\//g, '_'), 'ES256')).toBeNull();
    // 91 bytes ≡ 1 (mod 3) ⇒ canonical form ends with '==' — unpadded is refused
    expect(p256.bare.endsWith('==')).toBe(true);
    expect(normalizeSpkiPublicKey(p256.bare.replace(/=+$/, ''), 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`${p256.bare}=`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`${p256.bare.slice(0, 20)} ${p256.bare.slice(20)}`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`${p256.bare.slice(0, 20)}\n${p256.bare.slice(20)}`, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(`${p256.bare.slice(0, -3)}!==`, 'ES256')).toBeNull();
    // Non-canonical encoding: 44 bytes ≡ 2 (mod 3) ⇒ one '=' and the last
    // data symbol's low 2 bits MUST be zero. Set one ⇒ same length, same
    // alphabet, but not a canonical encoding of any byte string ⇒ refused.
    const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    expect(ed.bare.endsWith('=') && !ed.bare.endsWith('==')).toBe(true);
    const lastSym = ed.bare[ed.bare.length - 2];
    const v = ALPHABET.indexOf(lastSym);
    expect(v & 0x03).toBe(0); // proves the fixture itself is canonical
    const nonCanonical = `${ed.bare.slice(0, -2)}${ALPHABET[v | 0x01]}=`;
    expect(normalizeSpkiPublicKey(nonCanonical, 'EdDSA')).toBeNull();
    expect(normalizeSpkiPublicKey('', 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey('   ', 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(42, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(null, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(undefined, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey({ toString: () => p256.bare }, 'ES256')).toBeNull();
  });

  it('rejects DER that is not a single outer SEQUENCE spanning the buffer (truncated, extended, wrong tag)', () => {
    const truncated = Buffer.from(p256.der.subarray(0, 90)).toString('base64');
    const extended = Buffer.concat([p256.der, Buffer.from([0x00])]).toString('base64');
    const wrongTag = Buffer.from(p256.der);
    wrongTag[0] = 0x31;
    expect(normalizeSpkiPublicKey(truncated, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(extended, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(wrongTag.toString('base64'), 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(Buffer.from([0x30, 0x80, 0x00, 0x00]).toString('base64'), 'ES256')).toBeNull(); // indefinite length
  });

  it('PINS the key TYPE to the algorithm: an Ed25519 SPKI is refused for ES256 and a P-256 SPKI for EdDSA; compressed P-256 points are refused', () => {
    expect(normalizeSpkiPublicKey(ed.pem, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(ed.bare, 'ES256')).toBeNull();
    expect(normalizeSpkiPublicKey(p256.pem, 'EdDSA')).toBeNull();
    expect(normalizeSpkiPublicKey(p256.bare, 'EdDSA')).toBeNull();
    // Compressed-point SPKI (59 bytes) — valid X.509, but NOT the canonical
    // form AWS KMS / openssl emit; refused to keep exactly one accepted shape.
    const pub = createPublicKey({ key: p256.der, format: 'der', type: 'spki' });
    const jwk = pub.export({ format: 'jwk' }) as { x: string; y: string };
    const x = Buffer.from(jwk.x, 'base64url');
    const y = Buffer.from(jwk.y, 'base64url');
    const compressed = Buffer.concat([
      Buffer.from([0x30, 0x39, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x22, 0x00]),
      Buffer.from([y[31] & 1 ? 0x03 : 0x02]),
      x,
    ]);
    expect(compressed.length).toBe(59);
    expect(normalizeSpkiPublicKey(compressed.toString('base64'), 'ES256')).toBeNull();
    // and a P-384 key (different curve OID, 120 bytes) is refused for ES256
    const p384 = generateKeyPairSync('ec', { namedCurve: 'P-384' }).publicKey.export({ type: 'spki', format: 'der' }) as Buffer;
    expect(normalizeSpkiPublicKey(p384.toString('base64'), 'ES256')).toBeNull();
    // an unknown algorithm string is refused regardless of key
    expect(normalizeSpkiPublicKey(p256.pem, 'RS256' as unknown as SigningAlgorithm)).toBeNull();
  });

  it('the credential.ts and _shared/offline-verify.ts copies agree on the entire matrix', () => {
    const p384 = generateKeyPairSync('ec', { namedCurve: 'P-384' }).publicKey.export({ type: 'spki', format: 'der' }) as Buffer;
    const inputs: Array<[unknown, SigningAlgorithm]> = [
      [p256.pem, 'ES256'], [p256.bare, 'ES256'], [p256.pem.replace(/\n/g, '\r\n'), 'ES256'],
      [ed.pem, 'EdDSA'], [ed.bare, 'EdDSA'], [ed.pem, 'ES256'], [p256.pem, 'EdDSA'],
      [`${p256.bare}=`, 'ES256'], [p256.bare.slice(0, -4), 'ES256'], [p384.toString('base64'), 'ES256'],
      ['', 'ES256'], [null, 'ES256'], [`-----BEGIN PRIVATE KEY-----\n${p256.bare}\n-----END PRIVATE KEY-----`, 'ES256'],
      [`-----BEGIN CERTIFICATE-----\n${p256.bare}\n-----END CERTIFICATE-----`, 'ES256'],
      [`${p256.bare.slice(0, 10)} ${p256.bare.slice(10)}`, 'ES256'],
    ];
    for (const [input, alg] of inputs) {
      expect(normalizeOffline(input, alg)).toBe(normalizeSpkiPublicKey(input, alg));
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════

describe('verifyToken — ES256 with the PEM the DB actually stores (real P-256 keys)', () => {
  const k1 = genP256();
  const k2 = genP256();

  it('PASSES with a PEM trusted key and with the bare representation — identical outcome', async () => {
    const { token } = mintToken(k1, 'ES256');
    expect(await verifyToken(token, resolver(k1.pem, 'ES256'), NOW, verifyNode)).toEqual({ authentic: true, reason: 'ok' });
    expect(await verifyToken(token, resolver(k1.bare, 'ES256'), NOW, verifyNode)).toEqual({ authentic: true, reason: 'ok' });
    expect(await verifyToken(token, resolver(k1.pem, 'ES256'), NOW, verifyWithWebCryptoLikeTheEdge)).toEqual({ authentic: true, reason: 'ok' });
  });

  it('the primitive receives canonical bare base64 SPKI DER, never the PEM text', async () => {
    const { token } = mintToken(k1, 'ES256');
    const seen: string[] = [];
    const spy: VerifyPrimitive = (pk, m, s, a) => { seen.push(pk); return verifyNode(pk, m, s, a); };
    await verifyToken(token, resolver(k1.pem, 'ES256'), NOW, spy);
    expect(seen).toEqual([k1.bare]);
  });

  it('FAILS signature_invalid for the wrong key (PEM), an altered message, and an altered signature', async () => {
    const { token, canonical } = mintToken(k1, 'ES256');
    expect(await verifyToken(token, resolver(k2.pem, 'ES256'), NOW, verifyNode)).toEqual({ authentic: false, reason: 'signature_invalid' });

    const sig = signEs256Raw(k1.privateKey, canonical.signedBytes);
    const tamperedSig = new Uint8Array(sig);
    tamperedSig[10] ^= 0x01;
    const tokenBadSig = encodeToken(canonical.headerB64, canonical.payloadB64, tamperedSig);
    expect(await verifyToken(tokenBadSig, resolver(k1.pem, 'ES256'), NOW, verifyNode)).toEqual({ authentic: false, reason: 'signature_invalid' });

    // Altered message: re-frame a DIFFERENT payload under the original signature.
    const other = buildCanonicalPayload({ ...ctx('ES256'), credential_version: 4 });
    const tokenAlteredMsg = encodeToken(other.headerB64, other.payloadB64, sig);
    expect(await verifyToken(tokenAlteredMsg, resolver(k1.pem, 'ES256'), NOW, verifyNode)).toEqual({ authentic: false, reason: 'signature_invalid' });
  });

  it('refuses malformed_public_key (distinct from signature_invalid) for a malformed trusted key, and never calls the primitive', async () => {
    const { token } = mintToken(k1, 'ES256');
    const neverCalled: VerifyPrimitive = () => { throw new Error('primitive must not run on a malformed key'); };
    for (const bad of [`${k1.bare}=`, 'not a key', `-----BEGIN PRIVATE KEY-----\n${k1.bare}\n-----END PRIVATE KEY-----`, genEd25519().pem]) {
      expect(await verifyToken(token, resolver(bad, 'ES256'), NOW, neverCalled)).toEqual({ authentic: false, reason: 'malformed_public_key' });
    }
  });

  it('keeps the PFA-PT-8 pin: header alg ≠ trusted alg ⇒ alg_mismatch BEFORE any key parsing (even with a malformed key)', async () => {
    const { token } = mintToken(k1, 'ES256'); // header alg = ES256
    const neverCalled: VerifyPrimitive = () => { throw new Error('must not run'); };
    expect(await verifyToken(token, resolver('garbage', 'EdDSA'), NOW, neverCalled)).toEqual({ authentic: false, reason: 'alg_mismatch' });
  });

  it('EdDSA path (existing verifier contract): PEM Ed25519 trusted key PASSES; P-256 key under EdDSA is malformed_public_key', async () => {
    const ed = genEd25519();
    const { token } = mintToken(ed, 'EdDSA');
    expect(await verifyToken(token, resolver(ed.pem, 'EdDSA'), NOW, verifyNode)).toEqual({ authentic: true, reason: 'ok' });
    expect(await verifyToken(token, resolver(k1.pem, 'EdDSA'), NOW, verifyNode)).toEqual({ authentic: false, reason: 'malformed_public_key' });
  });
});

// ═══════════════════════════════════════════════════════════════════════════

describe('verifyCanonicalSignature — the edge sign-after-verify with the DB PEM (regression closed)', () => {
  const k1 = genP256();
  const k2 = genP256();

  it('REGRESSION REPRODUCED: the edge primitive alone, fed the PEM, returns false (atob throws on the armor)', async () => {
    const canonical = buildCanonicalPayload(ctx('ES256'));
    const sig = signEs256Raw(k1.privateKey, canonical.signedBytes);
    expect(await verifyWithWebCryptoLikeTheEdge(k1.pem, canonical.signedBytes, sig, 'ES256')).toBe(false);
    expect(await verifyWithWebCryptoLikeTheEdge(k1.bare, canonical.signedBytes, sig, 'ES256')).toBe(true);
  });

  it('REGRESSION CLOSED: through verifyCanonicalSignature the PEM verifies with that same edge primitive', async () => {
    const canonical = buildCanonicalPayload(ctx('ES256'));
    const sig = signEs256Raw(k1.privateKey, canonical.signedBytes);
    expect(await verifyCanonicalSignature(canonical, sig, k1.pem, 'ES256', verifyWithWebCryptoLikeTheEdge)).toBe(true);
    expect(await verifyCanonicalSignature(canonical, sig, k1.bare, 'ES256', verifyWithWebCryptoLikeTheEdge)).toBe(true);
    expect(await verifyCanonicalSignature(canonical, sig, `${k1.pem}\n`, 'ES256', verifyNode)).toBe(true);
  });

  it('wrong key ⇒ false; altered signature ⇒ false; malformed key ⇒ false without invoking the primitive; wrong-type key ⇒ false', async () => {
    const canonical = buildCanonicalPayload(ctx('ES256'));
    const sig = signEs256Raw(k1.privateKey, canonical.signedBytes);
    expect(await verifyCanonicalSignature(canonical, sig, k2.pem, 'ES256', verifyNode)).toBe(false);
    const bad = new Uint8Array(sig);
    bad[0] ^= 0xff;
    expect(await verifyCanonicalSignature(canonical, bad, k1.pem, 'ES256', verifyNode)).toBe(false);
    const neverCalled: VerifyPrimitive = () => { throw new Error('must not run'); };
    expect(await verifyCanonicalSignature(canonical, sig, 'garbage', 'ES256', neverCalled)).toBe(false);
    expect(await verifyCanonicalSignature(canonical, sig, genEd25519().pem, 'ES256', neverCalled)).toBe(false);
  });
});

// ═══════════════════════════════════════════════════════════════════════════

describe('offlineVerify — M1 entries carrying the DB PEM', () => {
  const NOW_OFF = 1_700_000_000;
  const SESSION = 'session-aaaa';
  const ATOM = 'atom-0001';

  const verifyOffline: OfflineVerifyPrimitive = (publicKeyB64, message, signature, algorithm) => {
    const key = createPublicKey({ key: Buffer.from(publicKeyB64, 'base64'), format: 'der', type: 'spki' });
    if (algorithm === 'ES256') return nodeVerify('sha256', Buffer.from(message), { key, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature));
    if (algorithm === 'EdDSA') return nodeVerify(null, Buffer.from(message), key, Buffer.from(signature));
    return false;
  };

  function entry(public_key: string, algorithm: string): M1Entry {
    return { key_id: 'key-1', scope: 'event', event_id: 'event-1', public_key, algorithm, not_before: NOW_OFF - 10_000, not_after: NOW_OFF + 10_000, status: 'active' };
  }
  function m2(): M2Manifest {
    return {
      manifest_id: 'manifest-0001', session_id: SESSION, not_after: NOW_OFF + 10_000,
      base: { [ATOM]: { credential_version: 1, signing_key_id: 'key-1', ticket_state: 'active', resale_state: 'none' } },
      deltas: [],
    };
  }
  function token(fx: Fixture, algorithm: SigningAlgorithm): OfflineToken {
    const exp = NOW_OFF + 5_000;
    const claims = new TextEncoder().encode(JSON.stringify({ atom: ATOM, sess: SESSION, ver: 1, exp }));
    const sig = algorithm === 'ES256' ? signEs256Raw(fx.privateKey, claims) : signEd25519(fx.privateKey, claims);
    return { keyId: 'key-1', typ: OFFLINE_DOMAIN, algorithm, claims, sig, sessionId: SESSION, atomId: ATOM, credentialVersion: 1, exp };
  }
  function ctxFor(m1: M1Manifest, verify: OfflineVerifyPrimitive = verifyOffline): OfflineVerifyContext {
    return { m1, m2: m2(), lastSyncedSeq: 0, boundSessionId: SESSION, nowSeconds: NOW_OFF, admittedSet: new Set<string>(), verify };
  }

  it('admits with a PEM Ed25519 M1 entry (the existing door contract) and with a PEM ES256 entry', () => {
    const ed = genEd25519();
    expect(offlineVerify(token(ed, 'EdDSA'), ctxFor({ 'key-1': entry(ed.pem, 'EdDSA') }))).toEqual({ admit: true, atomId: ATOM });
    const p = genP256();
    expect(offlineVerify(token(p, 'ES256'), ctxFor({ 'key-1': entry(p.pem, 'ES256') }))).toEqual({ admit: true, atomId: ATOM });
    expect(offlineVerify(token(p, 'ES256'), ctxFor({ 'key-1': entry(p.bare, 'ES256') }))).toEqual({ admit: true, atomId: ATOM });
  });

  it('the door primitive receives canonical bare base64, never PEM text', () => {
    const ed = genEd25519();
    const seen: string[] = [];
    const spy: OfflineVerifyPrimitive = (pk, m, s, a) => { seen.push(pk); return verifyOffline(pk, m, s, a); };
    offlineVerify(token(ed, 'EdDSA'), ctxFor({ 'key-1': entry(ed.pem, 'EdDSA') }, spy));
    expect(seen).toEqual([ed.bare]);
  });

  it('refuses malformed_public_key for a malformed / wrong-type M1 key without calling the primitive; wrong key ⇒ signature_invalid', () => {
    const ed = genEd25519();
    const never: OfflineVerifyPrimitive = () => { throw new Error('must not run'); };
    expect(offlineVerify(token(ed, 'EdDSA'), ctxFor({ 'key-1': entry('', 'EdDSA') }, never))).toEqual({ admit: false, reason: 'malformed_public_key' });
    expect(offlineVerify(token(ed, 'EdDSA'), ctxFor({ 'key-1': entry(genP256().pem, 'EdDSA') }, never))).toEqual({ admit: false, reason: 'malformed_public_key' });
    expect(offlineVerify(token(ed, 'EdDSA'), ctxFor({ 'key-1': entry(genEd25519().pem, 'EdDSA') }))).toEqual({ admit: false, reason: 'signature_invalid' });
  });
});
