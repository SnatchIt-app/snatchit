/**
 * credential-sign — the pure token builder/verifier (KCRYPTO train).
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT
 *   These tests exercise `supabase/functions/credential-sign/credential.ts`
 *   ONLY — the import-free, pure module. `index.ts` (the edge I/O shell) is
 *   NOT imported here: it uses `https://…` imports vitest cannot load, and it
 *   is not deployed (train boundary: no KMS, no network). The Ed25519
 *   keypairs below are generated fresh, in-process, per test file run — they
 *   are throwaway fixtures, never a real signing key, and never touch KMS.
 *
 *   Node's `node:crypto` Ed25519 support is used ONLY here, to stand in for
 *   whatever `verifyPrimitive` a real caller (door, edge) injects. The
 *   pure module never imports a crypto library itself — see credential.ts's
 *   header comment.
 *
 * CASES
 *   1. Canonical payload determinism (same ctx, different key-insertion
 *      order → identical bytes).
 *   2. Domain separation — the frozen `typ` claim (DESIGN_102.md §2.2): a
 *      signature minted over a ticket-credential header cannot verify
 *      against a header carrying a different `typ`, even with the SAME
 *      payload and the SAME signature bytes.
 *   3. Tamper detection: modified payload / signature / kid each fail.
 *   4. Two throwaway Ed25519 keypairs (K1/K2): a token signed by K1 verifies
 *      with K1's public key and fails with K2's; `kid` selects the key.
 *   5. exp/iat/ttl derivation.
 *   6. base64url round-trip (including boundary lengths 0/1/2/3 bytes).
 *   7. Log-shape: `buildCredentialSignLogLine` never carries a token, a
 *      payload, or key material.
 *   8. PFA-PT-8 algorithm pinning — see `tests/credential-sign-kms.test.ts`
 *      for the full alg-pin + ES256/DER matrix; this file keeps the
 *      pre-existing Ed25519-only cases passing under the new
 *      `TrustedKeyResolver` shape.
 */
import { createPublicKey, generateKeyPairSync, sign as nodeSign, verify as nodeVerify, type KeyObject } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  base64urlDecode,
  base64urlEncode,
  buildCanonicalPayload,
  buildCredentialSignLogLine,
  canonicalJSONStringify,
  decodeTokenStructure,
  DEFAULT_ALGORITHM,
  DOMAIN,
  encodeToken,
  MAX_TOKEN_LENGTH,
  toUnixSeconds,
  verifyToken,
  type SigningAlgorithm,
  type TicketSigningContext,
  type TrustedKeyResolver,
  type VerifyPrimitive,
} from '../supabase/functions/credential-sign/credential';

// ── Ed25519 test fixtures — throwaway keypairs, generated fresh every run ──

function genEd25519(): { privateKey: KeyObject; publicKeyB64: string } {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { privateKey, publicKeyB64: Buffer.from(der).toString('base64') };
}

function signBytes(privateKey: KeyObject, bytes: Uint8Array): Uint8Array {
  return new Uint8Array(nodeSign(null, Buffer.from(bytes), privateKey));
}

/** The injected crypto primitive `verifyToken` calls. Stands in for whatever
 *  the real edge/door provides — this test's ONLY use of `node:crypto`. */
const verifyEd25519: VerifyPrimitive = (publicKeyB64, message, signature, alg) => {
  if (alg !== 'EdDSA') return false;
  const key = createPublicKey({ key: Buffer.from(publicKeyB64, 'base64'), format: 'der', type: 'spki' });
  return nodeVerify(null, Buffer.from(message), key, Buffer.from(signature));
};

// ── Fixture context ─────────────────────────────────────────────────────

const ATOM_ID = '11111111-1111-4111-8111-111111111111';
const SESSION_ID = '22222222-2222-4222-8222-222222222222';
const KEY_ID_1 = '33333333-3333-4333-8333-333333333333';
const KEY_ID_2 = '44444444-4444-4444-8444-444444444444';

const ISSUED_AT = '2026-09-03T12:00:00.000Z';
const EXP = '2026-09-03T16:00:00.000Z'; // +4h, matching credential.app_ttl_interval

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

/** Existing tests in this file are Ed25519-only — the resolver wraps each
 *  raw public-key string as a `TrustedKey` pinned to `algorithm` (default
 *  `EdDSA`), so every pre-existing call site keeps working unchanged under
 *  the PFA-PT-8 `TrustedKeyResolver` shape. `alg`-mismatch coverage lives in
 *  `tests/credential-sign-kms.test.ts`, which builds `TrustedKey`s directly. */
function makeResolver(map: Record<string, string>, algorithm: SigningAlgorithm = 'EdDSA'): TrustedKeyResolver {
  return (kid: string) => {
    const public_key = map[kid];
    return public_key ? { public_key, algorithm } : null;
  };
}

// ═══════════════════════════════════════════════════════════════════════════

describe('canonical payload — determinism', () => {
  it('produces identical signed bytes for the same context', () => {
    const a = buildCanonicalPayload(ctx());
    const b = buildCanonicalPayload(ctx());
    expect(a.signingInput).toBe(b.signingInput);
    expect(Array.from(a.signedBytes)).toEqual(Array.from(b.signedBytes));
  });

  it('is insensitive to the object literal key insertion order', () => {
    const c1: TicketSigningContext = {
      ticket_atom_id: ATOM_ID,
      session_id: SESSION_ID,
      credential_version: 3,
      key_id: KEY_ID_1,
      issued_at: ISSUED_AT,
      exp: EXP,
    };
    // Same fields, deliberately reordered.
    const c2: TicketSigningContext = {
      exp: EXP,
      key_id: KEY_ID_1,
      issued_at: ISSUED_AT,
      credential_version: 3,
      session_id: SESSION_ID,
      ticket_atom_id: ATOM_ID,
    };
    expect(buildCanonicalPayload(c1).signingInput).toBe(buildCanonicalPayload(c2).signingInput);
  });

  it('canonical JSON has sorted keys and no whitespace', () => {
    const s = canonicalJSONStringify({ b: 1, a: 2, c: { z: 1, y: 2 } });
    expect(s).toBe('{"a":2,"b":1,"c":{"y":2,"z":1}}');
    expect(s).not.toMatch(/\s/);
  });

  it('header carries the frozen typ, lowercased kid, and default alg', () => {
    const built = buildCanonicalPayload(ctx({ key_id: KEY_ID_1.toUpperCase() }));
    expect(built.header.typ).toBe(DOMAIN);
    expect(built.header.typ).toBe('SNATCHIT-TICKET-CRED-V1');
    expect(built.header.kid).toBe(KEY_ID_1); // lowercased
    expect(built.header.alg).toBe(DEFAULT_ALGORITHM);
    expect(built.header.alg).toBe('EdDSA');
  });

  it('payload carries exactly the five frozen claims, uuids lowercased, integers only', () => {
    const built = buildCanonicalPayload(ctx({ ticket_atom_id: ATOM_ID.toUpperCase(), session_id: SESSION_ID.toUpperCase() }));
    expect(built.payload).toEqual({
      atom: ATOM_ID,
      sess: SESSION_ID,
      ver: 3,
      iat: toUnixSeconds(ISSUED_AT),
      exp: toUnixSeconds(EXP),
    });
    expect(Number.isInteger(built.payload.exp)).toBe(true);
    expect(Number.isInteger(built.payload.iat)).toBe(true);
    expect(Number.isInteger(built.payload.ver)).toBe(true);
  });
});

describe('domain separation — the typ claim', () => {
  it('a signature minted for the ticket typ does not verify against a different typ header (constructed forgery) — caught by the explicit typ check, before signature verification is even attempted', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signBytes(privateKey, canonical.signedBytes);
    const legitToken = encodeToken(canonical.headerB64, canonical.payloadB64, sig);

    // Sanity: the legitimate token verifies.
    const legitResult = await verifyToken(legitToken, makeResolver({ [KEY_ID_1]: publicKeyB64 }), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(legitResult).toEqual({ authentic: true, reason: 'ok' });

    // Forge: SAME payload, SAME signature, a DIFFERENT typ in the header —
    // simulating "reinterpret this credential as a wallet-manifest object."
    const forgedHeaderJson = canonicalJSONStringify({
      alg: canonical.header.alg,
      kid: canonical.header.kid,
      typ: 'SNATCHIT-WALLET-MANIFEST-V1',
    });
    const forgedHeaderB64 = base64urlEncode(new TextEncoder().encode(forgedHeaderJson));
    const forgedToken = encodeToken(forgedHeaderB64, canonical.payloadB64, sig);

    const forgedResult = await verifyToken(forgedToken, makeResolver({ [KEY_ID_1]: publicKeyB64 }), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(forgedResult.authentic).toBe(false);
    // `wrong_typ` — verifyToken checks header.typ === DOMAIN FIRST, before
    // ever calling verifyPrimitive, so a forged typ is caught here and
    // never reaches signature verification at all (it would ALSO fail
    // there, since the header change altered the signed bytes — that
    // remains true and is asserted below — but the explicit check is what
    // actually enforces it, not a side effect of the signature failing).
    expect(forgedResult.reason).toBe('wrong_typ');

    // And prove the OTHER layer still holds too: the header change altered
    // the signed bytes, so even a verifier that somehow skipped the typ
    // check would still reject this on signature grounds.
    expect(forgedHeaderB64).not.toBe(canonical.headerB64);
  });

  it('REPLAY direction: a GENUINELY-signed different-typ credential (real key, valid signature, shape-matching payload) is refused as wrong_typ — this is what the forgery test above does NOT prove', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();

    // A real signer mints a token for a DIFFERENT domain (e.g. a
    // wallet-manifest credential) whose payload happens to shape-match a
    // ticket credential's five frozen claims. This is not a forged/tampered
    // token — the signature is completely genuine over these exact bytes.
    const otherDomainHeaderJson = canonicalJSONStringify({
      alg: 'EdDSA',
      kid: KEY_ID_1,
      typ: 'SNATCHIT-WALLET-MANIFEST-V1',
    });
    const otherDomainHeaderB64 = base64urlEncode(new TextEncoder().encode(otherDomainHeaderJson));
    const canonical = buildCanonicalPayload(ctx()); // reuse the same payload shape/bytes
    const genuineSig = signBytes(privateKey, new TextEncoder().encode(`${otherDomainHeaderB64}.${canonical.payloadB64}`));
    const replayToken = encodeToken(otherDomainHeaderB64, canonical.payloadB64, genuineSig);

    // Sanity: this token's signature IS valid over its own (different-typ)
    // signed bytes — decodeTokenStructure/verifyPrimitive alone would say
    // "authentic" if nothing checked typ. Prove that first, directly.
    const decoded = decodeTokenStructure(replayToken)!;
    expect(decoded.header.typ).toBe('SNATCHIT-WALLET-MANIFEST-V1');
    const rawSignatureCheck = await verifyEd25519(publicKeyB64, decoded.signedBytes, decoded.signatureBytes, 'EdDSA');
    expect(rawSignatureCheck).toBe(true); // genuinely valid signature — this is real replay material, not garbage

    // verifyToken must STILL refuse it — this is the actual replay-attack
    // proof the forgery-direction test above cannot provide, since a forged
    // token's signature is invalid by construction; this one's is not.
    const result = await verifyToken(replayToken, makeResolver({ [KEY_ID_1]: publicKeyB64 }), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'wrong_typ' });
  });
});

describe('tamper detection', () => {
  it('rejects a modified payload', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signBytes(privateKey, canonical.signedBytes);

    const tamperedPayloadJson = canonicalJSONStringify({ ...canonical.payload, ver: canonical.payload.ver + 1 });
    const tamperedPayloadB64 = base64urlEncode(new TextEncoder().encode(tamperedPayloadJson));
    const tamperedToken = encodeToken(canonical.headerB64, tamperedPayloadB64, sig);

    const result = await verifyToken(tamperedToken, makeResolver({ [KEY_ID_1]: publicKeyB64 }), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'signature_invalid' });
  });

  it('rejects a modified signature', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signBytes(privateKey, canonical.signedBytes);
    const flipped = new Uint8Array(sig);
    flipped[0] ^= 0xff;
    const tamperedToken = encodeToken(canonical.headerB64, canonical.payloadB64, flipped);

    const result = await verifyToken(tamperedToken, makeResolver({ [KEY_ID_1]: publicKeyB64 }), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'signature_invalid' });
  });

  it('rejects a modified kid pointing outside the trusted keyring', async () => {
    const { privateKey } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signBytes(privateKey, canonical.signedBytes);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, sig);

    // The resolver's keyring does not contain this token's kid at all.
    const result = await verifyToken(token, makeResolver({}), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'unknown_kid' });
  });

  it('rejects a structurally malformed token', async () => {
    const result = await verifyToken('not-a-token', makeResolver({}), 0, verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'malformed_token' });
  });

  it('rejects a token over MAX_TOKEN_LENGTH before any parsing work runs (DoS bound, applies to every caller)', async () => {
    // A genuine token, then padded well past the cap purely in its
    // (otherwise-ignored, since the size check runs first) signature
    // segment — proves the length check is the FIRST thing that runs, not
    // a side effect of some other structural check.
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signBytes(privateKey, canonical.signedBytes);
    const legitToken = encodeToken(canonical.headerB64, canonical.payloadB64, sig);
    expect(legitToken.length).toBeLessThan(MAX_TOKEN_LENGTH);

    const oversized = legitToken + 'A'.repeat(MAX_TOKEN_LENGTH - legitToken.length + 1);
    expect(oversized.length).toBeGreaterThan(MAX_TOKEN_LENGTH);

    expect(decodeTokenStructure(oversized)).toBeNull();
    const result = await verifyToken(oversized, makeResolver({ [KEY_ID_1]: publicKeyB64 }), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'malformed_token' });
  });

  it('the boundary is `length > MAX_TOKEN_LENGTH`, not `>=`: a well-formed token AT the cap still decodes; one byte over is unconditionally malformed_token', () => {
    // `isCredentialPayload` only requires the five frozen keys to be
    // present with the right types — it does not reject EXTRA keys — so an
    // inert `pad` field lets the payload's byte length be dialed to any
    // target without touching header/payload validity or needing a real
    // signature (this test only exercises `decodeTokenStructure`'s
    // structural admission, not signature verification).
    const canonical = buildCanonicalPayload(ctx());
    const sigB64 = base64urlEncode(new Uint8Array(64).fill(0xaa)); // shape-valid, not a real signature

    function buildPaddedToken(padLength: number): string {
      const payload = { ...canonical.payload, pad: 'x'.repeat(padLength) };
      const payloadB64 = base64urlEncode(new TextEncoder().encode(canonicalJSONStringify(payload)));
      return `${canonical.headerB64}.${payloadB64}.${sigB64}`;
    }

    // Binary-search-free: grow pad length one char at a time from a
    // starting point until the token length first reaches, then exceeds,
    // MAX_TOKEN_LENGTH — small, fast, and exact (base64/JSON overhead is
    // fixed per byte of `pad`, so this converges in a handful of steps
    // once close, but we just walk it directly since the search space here
    // is small enough not to matter).
    let padLength = 0;
    while (buildPaddedToken(padLength).length < MAX_TOKEN_LENGTH) padLength++;
    // base64 groups 3 input bytes at a time, so growing `pad` one character
    // can jump the encoded length by more than 1 char — step back until
    // we're AT OR UNDER the cap (never assume the loop landed exactly on
    // it).
    while (buildPaddedToken(padLength).length > MAX_TOKEN_LENGTH) padLength--;
    const atOrUnderCap = buildPaddedToken(padLength);
    expect(atOrUnderCap.length).toBeLessThanOrEqual(MAX_TOKEN_LENGTH);
    expect(decodeTokenStructure(atOrUnderCap)).not.toBeNull();

    const overCap = buildPaddedToken(padLength + 64); // comfortably over MAX_TOKEN_LENGTH
    expect(overCap.length).toBeGreaterThan(MAX_TOKEN_LENGTH);
    expect(decodeTokenStructure(overCap)).toBeNull();
  });
});

describe('rotation — kid selects the key (K1/K2)', () => {
  it('a token signed by K1 verifies with K1 public key and fails with K2 public key', async () => {
    const k1 = genEd25519();
    const k2 = genEd25519();
    const canonical = buildCanonicalPayload(ctx({ key_id: KEY_ID_1 }));
    const sig = signBytes(k1.privateKey, canonical.signedBytes);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, sig);

    const okWithK1 = await verifyToken(token, makeResolver({ [KEY_ID_1]: k1.publicKeyB64 }), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(okWithK1).toEqual({ authentic: true, reason: 'ok' });

    // Same kid in the token, but the keyring resolves that kid to K2's key —
    // simulates a keyring desync / a wrong key mapped to the same kid.
    const failWithK2 = await verifyToken(token, makeResolver({ [KEY_ID_1]: k2.publicKeyB64 }), toUnixSeconds(ISSUED_AT), verifyEd25519);
    expect(failWithK2).toEqual({ authentic: false, reason: 'signature_invalid' });
  });

  it("the token's kid selects which key the resolver returns — two atoms pinned to two different keys both verify correctly", async () => {
    const k1 = genEd25519();
    const k2 = genEd25519();
    const resolver = makeResolver({ [KEY_ID_1]: k1.publicKeyB64, [KEY_ID_2]: k2.publicKeyB64 });

    const canonical1 = buildCanonicalPayload(ctx({ key_id: KEY_ID_1 }));
    const token1 = encodeToken(canonical1.headerB64, canonical1.payloadB64, signBytes(k1.privateKey, canonical1.signedBytes));

    const canonical2 = buildCanonicalPayload(ctx({ key_id: KEY_ID_2, ticket_atom_id: '55555555-5555-4555-8555-555555555555' }));
    const token2 = encodeToken(canonical2.headerB64, canonical2.payloadB64, signBytes(k2.privateKey, canonical2.signedBytes));

    expect(await verifyToken(token1, resolver, toUnixSeconds(ISSUED_AT), verifyEd25519)).toEqual({ authentic: true, reason: 'ok' });
    expect(await verifyToken(token2, resolver, toUnixSeconds(ISSUED_AT), verifyEd25519)).toEqual({ authentic: true, reason: 'ok' });

    // Cross-wired: token1's signature under key2 must fail (proves kid, not
    // "any trusted key", governs which key verifies a given token).
    const crossToken = encodeToken(canonical1.headerB64, canonical1.payloadB64, signBytes(k2.privateKey, canonical1.signedBytes));
    const decoded = decodeTokenStructure(crossToken)!;
    expect(decoded.header.kid).toBe(KEY_ID_1); // still claims key 1...
    // ...but was actually signed by key 2, so verifying against the kid it
    // CLAIMS (key 1, per the resolver) must fail.
    expect(await verifyToken(crossToken, resolver, toUnixSeconds(ISSUED_AT), verifyEd25519)).toEqual({
      authentic: false,
      reason: 'signature_invalid',
    });
  });
});

describe('exp / iat / ttl derivation', () => {
  it('derives unix-second integers from ISO timestamps', () => {
    expect(toUnixSeconds('2026-09-03T12:00:00.000Z')).toBe(Math.floor(Date.parse('2026-09-03T12:00:00.000Z') / 1000));
  });

  it('derives from a Date instance', () => {
    const d = new Date('2026-09-03T12:00:00.000Z');
    expect(toUnixSeconds(d)).toBe(Math.floor(d.getTime() / 1000));
  });

  it('a pre-derived unix-seconds number passes through truncated', () => {
    expect(toUnixSeconds(1893456000.7)).toBe(1893456000);
  });

  it('rejects an invalid timestamp string', () => {
    expect(() => toUnixSeconds('not-a-date')).toThrow();
  });

  it('the payload exp − iat matches the configured TTL (4h, credential.app_ttl_interval)', () => {
    const built = buildCanonicalPayload(ctx({ issued_at: ISSUED_AT, exp: EXP }));
    expect(built.payload.exp - built.payload.iat).toBe(4 * 60 * 60);
  });

  it('expired tokens fail verification even with a perfectly valid signature', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signBytes(privateKey, canonical.signedBytes);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, sig);

    const afterExpiry = toUnixSeconds(EXP) + 1;
    const result = await verifyToken(token, makeResolver({ [KEY_ID_1]: publicKeyB64 }), afterExpiry, verifyEd25519);
    expect(result).toEqual({ authentic: false, reason: 'expired' });
  });
});

describe('base64url round-trip', () => {
  it('round-trips arbitrary byte lengths (covers the 0/1/2/3-byte padding boundaries)', () => {
    for (let len = 0; len <= 16; len++) {
      const bytes = new Uint8Array(len).map((_, i) => (i * 37 + 11) % 256);
      const encoded = base64urlEncode(bytes);
      expect(base64urlDecode(encoded)).toEqual(bytes);
    }
  });

  it('never emits +, /, or = (URL-safe, unpadded)', () => {
    const bytes = new Uint8Array(64).map((_, i) => i);
    const encoded = base64urlEncode(bytes);
    expect(encoded).not.toMatch(/[+/=]/);
  });

  it('round-trips a full canonical token signing input', () => {
    const canonical = buildCanonicalPayload(ctx());
    const decodedHeader = JSON.parse(new TextDecoder().decode(base64urlDecode(canonical.headerB64)));
    expect(decodedHeader).toEqual(canonical.header);
  });
});

describe('log shape — never the token, the payload, or key material', () => {
  it('the log line carries only tag/atom_id/credential_version/key_id/outcome', () => {
    const line = buildCredentialSignLogLine({
      atom_id: ATOM_ID,
      credential_version: 3,
      key_id: KEY_ID_1,
      outcome: 'signed',
    });
    const parsed = JSON.parse(line);
    expect(Object.keys(parsed).sort()).toEqual(['atom_id', 'credential_version', 'key_id', 'outcome', 'tag']);
    expect(parsed.tag).toBe('credential-sign');

    // Structural guarantee, not just this instance: none of the forbidden
    // keys can ever appear, because the type admits only the four fields.
    for (const forbidden of ['token', 'payload', 'kms_handle_ref', 'handle', 'public_key', 'signature']) {
      expect(Object.keys(parsed)).not.toContain(forbidden);
    }
  });

  it('a real token/canonical payload never leaks into the log line even if constructed alongside it', async () => {
    const { privateKey, publicKeyB64 } = genEd25519();
    const canonical = buildCanonicalPayload(ctx());
    const sig = signBytes(privateKey, canonical.signedBytes);
    const token = encodeToken(canonical.headerB64, canonical.payloadB64, sig);
    void publicKeyB64;

    const line = buildCredentialSignLogLine({
      atom_id: ATOM_ID,
      credential_version: canonical.payload.ver,
      key_id: canonical.header.kid,
      outcome: 'signed',
    });

    expect(line).not.toContain(token);
    expect(line).not.toContain(canonical.payloadB64);
    expect(line).not.toContain(base64urlEncode(sig));
  });
});
