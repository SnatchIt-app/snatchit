/**
 * credential-sign-kms — PFA-PT-8 algorithm pinning, ES256/DER⇄raw
 * conversion, sign-after-verify, and the KMS error taxonomy.
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT
 *   `derToRawEcdsaP256`/`rawToDerEcdsaP256`/`verifyToken`/
 *   `verifyCanonicalSignature` come from `credential.ts` — the same
 *   import-free, pure module `tests/credential-sign.test.ts` exercises.
 *   `classifyAwsKmsHttpError`/`KmsSignError`/`UnconfiguredKmsSigner`/the
 *   AWS algorithm-mapping, env, credential, and response-validation
 *   decision functions all come from `kms-taxonomy.ts` — a SECOND
 *   import-free pure module (same pattern as `credential.ts`) that exists
 *   specifically so this test file never needs to import `kms.ts`.
 *
 *   `kms.ts` itself (the Deno-only SigV4-over-`fetch` transport adapter,
 *   `AwsKmsSigner`) is deliberately NOT imported here, anywhere. It has a
 *   `.ts`-extension sibling import (Deno's required convention) and
 *   `crypto.subtle` calls that trip a `lib.dom.d.ts` `BufferSource`
 *   strictness tightening under this project's `tsconfig.json` — neither is
 *   a problem for the Deno edge runtime it actually executes under, but
 *   `tsc -p .` (`npm run typecheck`) type-checks anything transitively
 *   reachable from an included root file, and `tests/**` is not excluded.
 *   Importing `kms.ts` from a test therefore broke `npm run typecheck` even
 *   though `npx vitest run` stayed green (vitest transpiles with esbuild,
 *   it does not do full project type-checking) — exactly the trap this
 *   split avoids. `kms.ts` is untested-by-tsc for the same reason
 *   `index.ts` always has been: both are thin Deno-only shells around pure,
 *   separately-tested decision logic, and nothing in `tests/` imports
 *   either of them.
 *
 * CASES
 *   1. `derToRawEcdsaP256`/`rawToDerEcdsaP256` round-trip (leading-zero,
 *      short, and max-value r/s) + malformed-DER rejection (wrong tag,
 *      truncated, trailing extra bytes, negative integer).
 *   2. PFA-PT-8 algorithm pinning: EdDSA token vs ES256 trusted key (and the
 *      reverse) ⇒ `alg_mismatch`; `alg:'none'` ⇒ `unsupported_alg`; unknown
 *      `kid` ⇒ `unknown_kid`; attacker public key ⇒ `signature_invalid`.
 *   3. ES256 end-to-end: sign with a P-256 keypair, DER→raw, `verifyToken`
 *      passes under the pinned ES256 trusted key; a flipped payload byte
 *      fails.
 *   4. Sign-after-verify (`verifyCanonicalSignature`): a signature from the
 *      WRONG key fails against the expected public key — the exact check
 *      `index.ts` §9 runs before ever returning a credential.
 *   5. KMS error taxonomy (`kms-taxonomy.ts`, pure): `classifyAwsKmsHttpError`
 *      buckets representative HTTP failures correctly; `UnconfiguredKmsSigner`
 *      throws the right `KmsSignError`; the AWS algorithm mapping, the
 *      region/role and credential fail-closed checks, and
 *      `validateAwsSignResponse`'s security-class response checks (wrong
 *      key, wrong algorithm, or either field simply ABSENT from an
 *      otherwise-200 response — an absent confirmation is treated the same
 *      as a wrong one, never as "no check needed") are each exercised
 *      directly as plain function calls — no network mock, no `Deno`
 *      global, no `kms.ts` import needed for any of it.
 */
import {
  createPublicKey,
  generateKeyPairSync,
  sign as nodeSign,
  verify as nodeVerify,
  type KeyObject,
} from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  buildCanonicalPayload,
  derToRawEcdsaP256,
  rawToDerEcdsaP256,
  encodeToken,
  toUnixSeconds,
  verifyCanonicalSignature,
  verifyToken,
  type SigningAlgorithm,
  type TicketSigningContext,
  type TrustedKey,
  type TrustedKeyResolver,
  type VerifyPrimitive,
} from '../supabase/functions/credential-sign/credential';
import {
  awsSigningAlgorithmForEs256Only,
  classifyAwsKmsHttpError,
  KmsSignError,
  requireAwsProviderConfig,
  resolveAwsCredentials,
  UnconfiguredKmsSigner,
  validateAwsSignResponse,
} from '../supabase/functions/credential-sign/kms-taxonomy';

// ── Fixture context (mirrors credential-sign.test.ts) ─────────────────────

const ATOM_ID = '11111111-1111-4111-8111-111111111111';
const SESSION_ID = '22222222-2222-4222-8222-222222222222';
const KEY_ID_1 = '33333333-3333-4333-8333-333333333333';

const ISSUED_AT = '2026-09-03T12:00:00.000Z';
const EXP = '2026-09-03T16:00:00.000Z';

function ctx(over: Partial<TicketSigningContext> = {}): TicketSigningContext {
  return {
    ticket_atom_id: ATOM_ID,
    session_id: SESSION_ID,
    credential_version: 3,
    key_id: KEY_ID_1,
    algorithm: null,
    issued_at: ISSUED_AT,
    exp: EXP,
    ...over,
  };
}

function trustedResolver(map: Record<string, TrustedKey>): TrustedKeyResolver {
  return (kid: string) => map[kid] ?? null;
}

// ── Ed25519 fixtures ────────────────────────────────────────────────────

function genEd25519(): { privateKey: KeyObject; publicKeyB64: string } {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { privateKey, publicKeyB64: Buffer.from(der).toString('base64') };
}

function signEd25519(privateKey: KeyObject, bytes: Uint8Array): Uint8Array {
  return new Uint8Array(nodeSign(null, Buffer.from(bytes), privateKey));
}

const verifyEd25519: VerifyPrimitive = (publicKeyB64, message, signature, alg) => {
  if (alg !== 'EdDSA') return false;
  const key = createPublicKey({ key: Buffer.from(publicKeyB64, 'base64'), format: 'der', type: 'spki' });
  return nodeVerify(null, Buffer.from(message), key, Buffer.from(signature));
};

// ── P-256 (ES256) fixtures ──────────────────────────────────────────────

function genP256(): { privateKey: KeyObject; publicKeyB64: string } {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { privateKey, publicKeyB64: Buffer.from(der).toString('base64') };
}

/** DER-encoded ECDSA signature (Node's default `dsaEncoding` — the same
 *  shape AWS KMS's `Sign` API returns) over `bytes`. Test-only stand-in for
 *  the KMS call `AwsKmsSigner.callSignApi` would make. */
function signP256Der(privateKey: KeyObject, bytes: Uint8Array): Uint8Array {
  return new Uint8Array(nodeSign('sha256', Buffer.from(bytes), { key: privateKey, dsaEncoding: 'der' }));
}

/** Raw `R||S` verify — the SAME encoding this module's wire format and
 *  WebCrypto's ECDSA verify use, matching `derToRawEcdsaP256`'s output.
 *  Node accepts raw ECDSA signatures via `dsaEncoding: 'ieee-p1363'`
 *  (stable since Node 12). */
const verifyEs256Raw: VerifyPrimitive = (publicKeyB64, message, signature, alg) => {
  if (alg !== 'ES256') return false;
  const key = createPublicKey({ key: Buffer.from(publicKeyB64, 'base64'), format: 'der', type: 'spki' });
  return nodeVerify('sha256', Buffer.from(message), { key, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature));
};

// ═══════════════════════════════════════════════════════════════════════════

describe('derToRawEcdsaP256 / rawToDerEcdsaP256 — round trip', () => {
  function rawVector(rFill: (i: number) => number, sFill: (i: number) => number): Uint8Array {
    const raw = new Uint8Array(64);
    for (let i = 0; i < 32; i++) raw[i] = rFill(i) & 0xff;
    for (let i = 0; i < 32; i++) raw[32 + i] = sFill(i) & 0xff;
    return raw;
  }

  it('round-trips a value requiring DER sign-padding zeros (r and s both have their high bit set)', () => {
    // Every byte 0xff ⇒ DER must prepend a 0x00 to each INTEGER's content.
    const raw = rawVector(() => 0xff, () => 0xff);
    const der = rawToDerEcdsaP256(raw);
    // DER content: 0x30 LEN [0x02 0x21 0x00 <32 bytes 0xff>] x2 — 33-byte
    // integers because of the sign-padding zero.
    expect(der[0]).toBe(0x30);
    expect(derToRawEcdsaP256(der)).toEqual(raw);
  });

  it('round-trips a "leading zero" value (high byte 0x00, rest nonzero — no padding needed, but a natural leading zero byte)', () => {
    const raw = rawVector((i) => (i === 0 ? 0x00 : 0x42), (i) => (i === 0 ? 0x00 : 0x99));
    const der = rawToDerEcdsaP256(raw);
    expect(derToRawEcdsaP256(der)).toEqual(raw);
  });

  it('round-trips a short value (mostly leading zero bytes ⇒ short DER INTEGER content)', () => {
    const raw = rawVector((i) => (i === 31 ? 0x07 : 0x00), (i) => (i === 31 ? 0x2a : 0x00));
    const der = rawToDerEcdsaP256(raw);
    // Minimal DER content for r=7 is a single byte (0x07); for s=0x2a a
    // single byte (0x2a) — neither needs sign-padding (both < 0x80).
    expect(der.length).toBe(2 + 2 + 1 + 2 + 1); // SEQ hdr + 2×(INT hdr + 1 byte)
    expect(derToRawEcdsaP256(der)).toEqual(raw);
  });

  it('round-trips the maximum representable value (all 0xff, both r and s)', () => {
    const raw = rawVector(() => 0xff, () => 0xff);
    expect(derToRawEcdsaP256(rawToDerEcdsaP256(raw))).toEqual(raw);
  });

  it('round-trips a zero value (r = s = 0)', () => {
    const raw = rawVector(() => 0x00, () => 0x00);
    expect(derToRawEcdsaP256(rawToDerEcdsaP256(raw))).toEqual(raw);
  });

  it('round-trips 32 random-ish vectors', () => {
    for (let seed = 0; seed < 32; seed++) {
      const raw = rawVector((i) => (i * 7 + seed * 13) % 256, (i) => (i * 11 + seed * 17) % 256);
      expect(derToRawEcdsaP256(rawToDerEcdsaP256(raw))).toEqual(raw);
    }
  });

  it('a real P-256 signature: DER (as AWS KMS would return) → raw verifies with a raw-accepting primitive', () => {
    const { privateKey, publicKeyB64 } = genP256();
    const canonical = buildCanonicalPayload(ctx({ algorithm: 'ES256' }));
    const der = signP256Der(privateKey, canonical.signedBytes);
    const raw = derToRawEcdsaP256(der);
    expect(raw.length).toBe(64);
    expect(verifyEs256Raw(publicKeyB64, canonical.signedBytes, raw, 'ES256')).toBe(true);
  });

  describe('rejects malformed DER', () => {
    it('wrong outer tag (not SEQUENCE)', () => {
      const bad = new Uint8Array([0x31, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01]);
      expect(() => derToRawEcdsaP256(bad)).toThrow(/SEQUENCE/);
    });

    it('truncated buffer (declared length exceeds actual bytes)', () => {
      const bad = new Uint8Array([0x30, 0x08, 0x02, 0x01, 0x01, 0x02, 0x01]); // missing last byte
      expect(() => derToRawEcdsaP256(bad)).toThrow();
    });

    it('extra trailing bytes after a structurally valid SEQUENCE', () => {
      const good = rawToDerEcdsaP256(new Uint8Array(64).fill(1));
      const withGarbage = new Uint8Array(good.length + 3);
      withGarbage.set(good);
      withGarbage.set([0xde, 0xad, 0xbe], good.length);
      // NOTE: appending bytes after a valid SEQUENCE also changes what the
      // (now stale) outer length claims vs. the buffer's actual length —
      // caught by the SEQUENCE-length-vs-buffer-length check.
      expect(() => derToRawEcdsaP256(withGarbage)).toThrow();
    });

    it('a negative integer (high bit set, no sign-padding zero)', () => {
      // SEQUENCE{ INTEGER(len=1, 0x80 /* negative */), INTEGER(len=1, 0x01) }
      const bad = new Uint8Array([0x30, 0x06, 0x02, 0x01, 0x80, 0x02, 0x01, 0x01]);
      expect(() => derToRawEcdsaP256(bad)).toThrow(/negative/);
    });

    it('an integer wider than the P-256 field (33+ significant bytes)', () => {
      const oversized = new Uint8Array(34);
      oversized[0] = 0x01; // no leading zero to strip — genuinely 34 significant bytes
      const rInt = new Uint8Array([0x02, oversized.length, ...oversized]);
      const sInt = new Uint8Array([0x02, 0x01, 0x01]);
      const seqContent = new Uint8Array([...rInt, ...sInt]);
      const bad = new Uint8Array([0x30, seqContent.length, ...seqContent]);
      expect(() => derToRawEcdsaP256(bad)).toThrow(/field width/);
    });

    it('a non-minimal long-form length via a leading 0x00 length byte (SEQUENCE length encoded 0x82 0x00 0x06 instead of short-form 0x06)', () => {
      // SEQUENCE{ INTEGER(len=1,0x01), INTEGER(len=1,0x01) } — 6 bytes of
      // content, syntactically valid on its own — but the outer length is
      // long-form 0x82 0x00 0x06 (2 length-bytes, leading one 0x00), which
      // contributes nothing: the same value fits in a single length byte.
      const content = new Uint8Array([0x02, 0x01, 0x01, 0x02, 0x01, 0x01]);
      const bad = new Uint8Array([0x30, 0x82, 0x00, 0x06, ...content]);
      expect(() => derToRawEcdsaP256(bad)).toThrow(/non-minimal length encoding \(leading zero byte\)/);
    });

    it('a non-minimal long-form length that could have used short form (SEQUENCE length encoded 0x81 0x06 instead of 0x06)', () => {
      // Same 6-byte content; this time the outer length is long-form
      // 0x81 0x06 (1 length-byte, nonzero) — no leading-zero padding, but
      // the resulting value (6) is well under 0x80 and should NEVER have
      // used long form at all.
      const content = new Uint8Array([0x02, 0x01, 0x01, 0x02, 0x01, 0x01]);
      const bad = new Uint8Array([0x30, 0x81, 0x06, ...content]);
      expect(() => derToRawEcdsaP256(bad)).toThrow(/non-minimal length encoding/);
    });

    it('a syntactically minimal long-form length that is still out of range for the buffer — a DISTINCT message from "non-minimal"', () => {
      // Long-form 0x81 0x90 declares length 144 (minimal: single nonzero
      // length byte, value >= 0x80) but the buffer holds only 2 content
      // bytes after it — nowhere near 144. This must be rejected as
      // out-of-range, not misreported as a minimality defect (it IS
      // minimally encoded; it is simply too large for what follows).
      const bad = new Uint8Array([0x30, 0x81, 0x90, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06]);
      expect(() => derToRawEcdsaP256(bad)).toThrow(/exceeds buffer size \(out of range\)/);
    });
  });

  it('rawToDerEcdsaP256 rejects a non-64-byte input', () => {
    expect(() => rawToDerEcdsaP256(new Uint8Array(63))).toThrow();
    expect(() => rawToDerEcdsaP256(new Uint8Array(65))).toThrow();
  });
});

describe('PFA-PT-8 — algorithm pinning', () => {
  it('EdDSA token header vs an ES256 trusted key ⇒ alg_mismatch (no fallback)', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx()); // header.alg defaults to EdDSA
    const sig = signEd25519(privateKey, canonical.signedBytes);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, sig);

    // The trusted keyring pins THIS kid to ES256 — a keyring/DB desync, or
    // an attacker trying to get an EdDSA-signed token accepted by declaring
    // ES256 doesn't matter for; either way, refuse.
    const resolver = trustedResolver({ [KEY_ID_1]: { public_key: publicKeyB64, algorithm: 'ES256' } });
    const result = await verifyToken(token, resolver, toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'alg_mismatch' });
  });

  it('ES256 token header vs an EdDSA trusted key ⇒ alg_mismatch (the reverse)', async () => {
    const { privateKey, publicKeyB64 } = genP256();
    const canonical = buildCanonicalPayload(ctx({ algorithm: 'ES256' }));
    const der = signP256Der(privateKey, canonical.signedBytes);
    const raw = derToRawEcdsaP256(der);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, raw);

    const resolver = trustedResolver({ [KEY_ID_1]: { public_key: publicKeyB64, algorithm: 'EdDSA' } });
    const result = await verifyToken(token, resolver, toUnixSeconds(ISSUED_AT), verifyEs256Raw);
    expect(result).toEqual({ authentic: false, reason: 'alg_mismatch' });
  });

  it("alg:'none' is rejected as unsupported_alg — before any key lookup", async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signEd25519(privateKey, canonical.signedBytes);

    // Forge a header claiming alg:'none', reusing the real payload/signature
    // (an attacker's cheapest move against a naive verifier).
    const forgedHeaderJson = JSON.stringify({ alg: 'none', kid: canonical.header.kid, typ: canonical.header.typ });
    const forgedHeaderB64 = Buffer.from(forgedHeaderJson).toString('base64url');
    const forgedToken = encodeToken(forgedHeaderB64, canonical.payloadB64, sig);

    let resolverCalled = false;
    const resolver: TrustedKeyResolver = (_kid) => {
      resolverCalled = true;
      return { public_key: publicKeyB64, algorithm: 'EdDSA' } as TrustedKey;
    };
    const result = await verifyToken(forgedToken, resolver, toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'unsupported_alg' });
    expect(resolverCalled).toBe(false); // never even looked up the kid
  });

  it('a missing alg entirely is also unsupported_alg, not malformed_token', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signEd25519(privateKey, canonical.signedBytes);

    const forgedHeaderJson = JSON.stringify({ kid: canonical.header.kid, typ: canonical.header.typ }); // no alg
    const forgedHeaderB64 = Buffer.from(forgedHeaderJson).toString('base64url');
    const forgedToken = encodeToken(forgedHeaderB64, canonical.payloadB64, sig);

    const resolver = trustedResolver({ [KEY_ID_1]: { public_key: publicKeyB64, algorithm: 'EdDSA' } });
    const result = await verifyToken(forgedToken, resolver, toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'unsupported_alg' });
  });

  it('an unrecognized alg string is unsupported_alg', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signEd25519(privateKey, canonical.signedBytes);
    const forgedHeaderJson = JSON.stringify({ alg: 'RS256', kid: canonical.header.kid, typ: canonical.header.typ });
    const forgedHeaderB64 = Buffer.from(forgedHeaderJson).toString('base64url');
    const forgedToken = encodeToken(forgedHeaderB64, canonical.payloadB64, sig);

    const resolver = trustedResolver({ [KEY_ID_1]: { public_key: publicKeyB64, algorithm: 'EdDSA' } });
    const result = await verifyToken(forgedToken, resolver, toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'unsupported_alg' });
  });

  it('unknown kid ⇒ unknown_kid', async () => {
    const { privateKey } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signEd25519(privateKey, canonical.signedBytes);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, sig);

    const result = await verifyToken(token, trustedResolver({}), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'unknown_kid' });
  });

  it('attacker public key (same kid, same algorithm, wrong key material) ⇒ signature_invalid', async () => {
    const legit = genEd25519();
    const attacker = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signEd25519(legit.privateKey, canonical.signedBytes);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, sig);

    // The resolver is compromised/desynced and hands back the ATTACKER's
    // key for the legitimate kid — same alg (so it passes the pin), wrong
    // key content (so the signature itself must still fail).
    const resolver = trustedResolver({ [KEY_ID_1]: { public_key: attacker.publicKeyB64, algorithm: 'EdDSA' } });
    const result = await verifyToken(token, resolver, toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'signature_invalid' });
  });
});

describe('ES256 end-to-end', () => {
  it('sign with P-256, DER→raw, verifyToken PASSES under the pinned ES256 trusted key', async () => {
    const { privateKey, publicKeyB64 } = genP256();
    const canonical = buildCanonicalPayload(ctx({ algorithm: 'ES256' }));
    expect(canonical.header.alg).toBe('ES256');

    const der = signP256Der(privateKey, canonical.signedBytes);
    const raw = derToRawEcdsaP256(der);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, raw);

    const resolver = trustedResolver({ [KEY_ID_1]: { public_key: publicKeyB64, algorithm: 'ES256' } });
    const result = await verifyToken(token, resolver, toUnixSeconds(ISSUED_AT), verifyEs256Raw);
    expect(result).toEqual({ authentic: true, reason: 'ok' });
  });

  it('a flipped payload byte fails verification', async () => {
    const { privateKey, publicKeyB64 } = genP256();
    const canonical = buildCanonicalPayload(ctx({ algorithm: 'ES256' }));
    const der = signP256Der(privateKey, canonical.signedBytes);
    const raw = derToRawEcdsaP256(der);

    const tamperedPayload = new Uint8Array(Buffer.from(canonical.payloadB64, 'base64url'));
    tamperedPayload[0] ^= 0xff;
    const tamperedPayloadB64 = Buffer.from(tamperedPayload).toString('base64url');
    const tamperedToken = encodeToken(canonical.headerB64, tamperedPayloadB64, raw);

    const resolver = trustedResolver({ [KEY_ID_1]: { public_key: publicKeyB64, algorithm: 'ES256' } });
    const result = await verifyToken(tamperedToken, resolver, toUnixSeconds(ISSUED_AT), verifyEs256Raw);
    expect(result.authentic).toBe(false);
    // Either the payload no longer parses as valid JSON (malformed_token) or
    // it parses but the signature no longer covers it (signature_invalid) —
    // both are correct rejections; assert it is one of the two, not "ok".
    expect(['malformed_token', 'signature_invalid']).toContain(result.reason);
  });
});

describe('sign-after-verify (verifyCanonicalSignature) — index.ts §9 in isolation', () => {
  it('a signature from the WRONG key fails against the expected public key (the exact defect sign-after-verify exists to catch)', async () => {
    const rightKey = genEd25519();
    const wrongKey = genEd25519();
    const canonical = buildCanonicalPayload(ctx());

    // Simulate a mock KmsSigner returning bytes signed by the WRONG key
    // (wrong KMS handle / wrong key version — the failure mode §9 targets).
    const mockKmsSigner = {
      async sign(_kmsHandleRef: string, bytes: Uint8Array, _algorithm: SigningAlgorithm): Promise<Uint8Array> {
        return signEd25519(wrongKey.privateKey, bytes);
      },
    };
    const signatureFromKms = await mockKmsSigner.sign('kms://wrong-handle', canonical.signedBytes, canonical.header.alg);

    // index.ts would verify against `response.public_key` — the RIGHT key,
    // per the DB's pinned signing context — not whatever the signer used.
    const verified = await verifyCanonicalSignature(
      canonical,
      signatureFromKms,
      rightKey.publicKeyB64,
      canonical.header.alg,
      verifyEd25519,
    );
    expect(verified).toBe(false); // index.ts: NO credential returned, signing_unhealthy
  });

  it('a signature from the RIGHT key over the EXACT canonical.signedBytes verifies', async () => {
    const key = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signEd25519(key.privateKey, canonical.signedBytes);
    const verified = await verifyCanonicalSignature(canonical, sig, key.publicKeyB64, canonical.header.alg, verifyEd25519);
    expect(verified).toBe(true);
  });

  it('ES256: sign-after-verify also catches a DER→raw conversion drift (unconverted DER handed to a raw-expecting verify)', async () => {
    const { privateKey, publicKeyB64 } = genP256();
    const canonical = buildCanonicalPayload(ctx({ algorithm: 'ES256' }));
    const der = signP256Der(privateKey, canonical.signedBytes); // NOT converted to raw
    // A raw-expecting primitive (WebCrypto/`ieee-p1363`) rejects a DER blob
    // outright — proving the DER→raw step is load-bearing, not cosmetic.
    const verified = await verifyCanonicalSignature(canonical, der, publicKeyB64, 'ES256', verifyEs256Raw);
    expect(verified).toBe(false);
  });
});

describe('KMS error taxonomy (kms-taxonomy.ts, pure — no network, no Deno global, no kms.ts import)', () => {
  describe('classifyAwsKmsHttpError — pure HTTP-shape classification', () => {
    it('429 (too many requests) ⇒ transient', () => {
      expect(classifyAwsKmsHttpError(429, '')).toBe('transient');
    });
    it('5xx ⇒ transient', () => {
      expect(classifyAwsKmsHttpError(500, '')).toBe('transient');
      expect(classifyAwsKmsHttpError(503, '')).toBe('transient');
    });
    it('a 400 ThrottlingException body ⇒ transient', () => {
      expect(classifyAwsKmsHttpError(400, '{"__type":"ThrottlingException","message":"Rate exceeded"}')).toBe('transient');
    });
    it('a 400 LimitExceededException body ⇒ transient', () => {
      expect(classifyAwsKmsHttpError(400, '{"__type":"LimitExceededException"}')).toBe('transient');
    });
    it('AccessDeniedException ⇒ permanent', () => {
      expect(classifyAwsKmsHttpError(400, '{"__type":"AccessDeniedException"}')).toBe('permanent');
    });
    it('DisabledException (key disabled) ⇒ permanent', () => {
      expect(classifyAwsKmsHttpError(400, '{"__type":"DisabledException"}')).toBe('permanent');
    });
    it('NotFoundException (unknown key) ⇒ permanent', () => {
      expect(classifyAwsKmsHttpError(404, '{"__type":"NotFoundException"}')).toBe('permanent');
    });
    it('an unrecognized 4xx shape fails closed as permanent, never guessed as retryable', () => {
      expect(classifyAwsKmsHttpError(418, '{"__type":"SomeNewExceptionAwsInventedLater"}')).toBe('permanent');
    });
  });

  describe('UnconfiguredKmsSigner — default, unchanged behavior', () => {
    it('always throws kms_provider_unconfigured, PERMANENT', async () => {
      const signer = new UnconfiguredKmsSigner();
      await expect(signer.sign('handle', new Uint8Array(1), 'EdDSA')).rejects.toMatchObject({
        errorClass: 'permanent',
        message: 'kms_provider_unconfigured',
      });
    });
  });

  describe('awsSigningAlgorithmForEs256Only — AWS KMS has no Ed25519', () => {
    it('ES256 → ECDSA_SHA_256', () => {
      expect(awsSigningAlgorithmForEs256Only('ES256')).toBe('ECDSA_SHA_256');
    });
    it('EdDSA ⇒ unsupported_algorithm_for_provider, PERMANENT', () => {
      expect(() => awsSigningAlgorithmForEs256Only('EdDSA')).toThrow(
        expect.objectContaining({ errorClass: 'permanent', message: 'unsupported_algorithm_for_provider' }),
      );
    });
  });

  describe('requireAwsProviderConfig — deployment-level fact, checked before any credential/network access', () => {
    it('both region and role present → returns them', () => {
      expect(requireAwsProviderConfig('us-east-1', 'arn:aws:iam::111111111111:role/kms-signer')).toEqual({
        region: 'us-east-1',
        roleArn: 'arn:aws:iam::111111111111:role/kms-signer',
      });
    });
    it('both missing ⇒ aws_kms_env_missing, PERMANENT', () => {
      expect(() => requireAwsProviderConfig(undefined, undefined)).toThrow(
        expect.objectContaining({ errorClass: 'permanent', message: 'aws_kms_env_missing' }),
      );
    });
    it('region present, role missing ⇒ aws_kms_env_missing, PERMANENT', () => {
      expect(() => requireAwsProviderConfig('us-east-1', undefined)).toThrow(
        expect.objectContaining({ errorClass: 'permanent', message: 'aws_kms_env_missing' }),
      );
    });
    it('role present, region missing ⇒ aws_kms_env_missing, PERMANENT', () => {
      expect(() => requireAwsProviderConfig(undefined, 'arn:aws:iam::111111111111:role/kms-signer')).toThrow(
        expect.objectContaining({ errorClass: 'permanent', message: 'aws_kms_env_missing' }),
      );
    });
  });

  describe('resolveAwsCredentials — FAILS CLOSED, pure (an injected env-getter, never a Deno/process global)', () => {
    it('both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY present → resolves credentials', () => {
      const env: Record<string, string> = { AWS_ACCESS_KEY_ID: 'AKIATEST', AWS_SECRET_ACCESS_KEY: 'test-secret' };
      expect(resolveAwsCredentials((k) => env[k])).toEqual({
        accessKeyId: 'AKIATEST',
        secretAccessKey: 'test-secret',
        sessionToken: undefined,
      });
    });

    it('includes an optional session token when present', () => {
      const env: Record<string, string> = {
        AWS_ACCESS_KEY_ID: 'AKIATEST',
        AWS_SECRET_ACCESS_KEY: 'test-secret',
        AWS_SESSION_TOKEN: 'session-token-value',
      };
      expect(resolveAwsCredentials((k) => env[k])).toEqual({
        accessKeyId: 'AKIATEST',
        secretAccessKey: 'test-secret',
        sessionToken: 'session-token-value',
      });
    });

    it('no credentials present (this is exactly what a plain Node/vitest env with no Deno global naturally is) ⇒ fails closed, PERMANENT, never signs', () => {
      expect(() => resolveAwsCredentials(() => undefined)).toThrow(
        expect.objectContaining({ errorClass: 'permanent', message: 'aws_kms_credentials_unavailable' }),
      );
    });

    it('only the access key id present (secret missing) ⇒ still fails closed, PERMANENT', () => {
      const env: Record<string, string> = { AWS_ACCESS_KEY_ID: 'AKIATEST' };
      expect(() => resolveAwsCredentials((k) => env[k])).toThrow(
        expect.objectContaining({ errorClass: 'permanent', message: 'aws_kms_credentials_unavailable' }),
      );
    });
  });

  describe('validateAwsSignResponse — pure response validation against the requested key/algorithm', () => {
    const sigB64 = Buffer.from(new Uint8Array(64).fill(7)).toString('base64');

    it('a matching KeyId (exact) and matching algorithm → returns the signature', () => {
      const result = validateAwsSignResponse(
        { KeyId: 'kms-handle', Signature: sigB64, SigningAlgorithm: 'ECDSA_SHA_256' },
        'kms-handle',
        'ECDSA_SHA_256',
      );
      expect(result).toBe(sigB64);
    });

    it('a response KeyId that is a full ARN still matches a bare-id request (trailing-segment comparison)', () => {
      const result = validateAwsSignResponse(
        {
          KeyId: 'arn:aws:kms:us-east-1:111111111111:key/REQUESTED-KEY',
          Signature: sigB64,
          SigningAlgorithm: 'ECDSA_SHA_256',
        },
        'REQUESTED-KEY',
        'ECDSA_SHA_256',
      );
      expect(result).toBe(sigB64);
    });

    it('no KeyId in the response at all (200 OK, otherwise well-formed) ⇒ SECURITY, not "no check needed" — an absent confirmation is not a passed check', () => {
      expect(() => validateAwsSignResponse({ Signature: sigB64, SigningAlgorithm: 'ECDSA_SHA_256' }, 'kms-handle', 'ECDSA_SHA_256')).toThrow(
        expect.objectContaining({ errorClass: 'security', message: expect.stringContaining('kms_response_key_mismatch') }),
      );
    });

    it('no SigningAlgorithm in the response at all ⇒ SECURITY, same reasoning', () => {
      expect(() => validateAwsSignResponse({ KeyId: 'kms-handle', Signature: sigB64 }, 'kms-handle', 'ECDSA_SHA_256')).toThrow(
        expect.objectContaining({ errorClass: 'security', message: expect.stringContaining('kms_response_algorithm_mismatch') }),
      );
    });

    it('BOTH KeyId and SigningAlgorithm absent (only Signature present) ⇒ SECURITY on the algorithm check first', () => {
      expect(() => validateAwsSignResponse({ Signature: sigB64 }, 'kms-handle', 'ECDSA_SHA_256')).toThrow(
        expect.objectContaining({ errorClass: 'security' }),
      );
    });

    it('a response whose KeyId does not match the requested handle ⇒ SECURITY (unexpected fingerprint)', () => {
      expect(() =>
        validateAwsSignResponse(
          {
            KeyId: 'arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000',
            Signature: sigB64,
            SigningAlgorithm: 'ECDSA_SHA_256',
          },
          'arn:aws:kms:us-east-1:111111111111:key/REQUESTED-KEY',
          'ECDSA_SHA_256',
        ),
      ).toThrow(expect.objectContaining({ errorClass: 'security', message: expect.stringContaining('kms_response_key_mismatch') }));
    });

    it('a response whose SigningAlgorithm does not match what was requested ⇒ SECURITY', () => {
      expect(() =>
        validateAwsSignResponse({ KeyId: 'kms-handle', Signature: sigB64, SigningAlgorithm: 'ECDSA_SHA_384' }, 'kms-handle', 'ECDSA_SHA_256'),
      ).toThrow(expect.objectContaining({ errorClass: 'security', message: expect.stringContaining('kms_response_algorithm_mismatch') }));
    });

    it('a missing Signature ⇒ PERMANENT (not security — nothing to validate a fingerprint against)', () => {
      expect(() => validateAwsSignResponse({ KeyId: 'kms-handle', SigningAlgorithm: 'ECDSA_SHA_256' }, 'kms-handle', 'ECDSA_SHA_256')).toThrow(
        expect.objectContaining({ errorClass: 'permanent', message: 'kms_response_missing_signature' }),
      );
    });
  });

  describe('KmsSignError instances carry the taxonomy end to end', () => {
    it('each of the three classes round-trips through errorClass/message/instanceof', () => {
      const transient = new KmsSignError('kms_http_503:timeout', 'transient');
      const permanent = new KmsSignError('aws_kms_env_missing', 'permanent');
      const security = new KmsSignError('kms_response_key_mismatch', 'security');
      for (const err of [transient, permanent, security]) {
        expect(err).toBeInstanceOf(Error);
        expect(err).toBeInstanceOf(KmsSignError);
        expect(err.name).toBe('KmsSignError');
      }
      expect(transient.errorClass).toBe('transient');
      expect(permanent.errorClass).toBe('permanent');
      expect(security.errorClass).toBe('security');
    });
  });
});
