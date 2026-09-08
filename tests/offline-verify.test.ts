/**
 * offline-verify — the pure `OFFLINE-VERIFY-v1` admission predicate core
 * (`supabase/functions/_shared/offline-verify.ts`).
 *
 * WHAT THIS PROVES
 *   Every conjunct of `OFFLINE-VERIFY-v1` (edge §5.4.3 · door §9.2), each
 *   asserted SEPARATELY with the exact reason code, plus the door §32 attack
 *   scenarios named in the build brief: an old-owner screenshot after a
 *   version bump, a refund/dispute hold, a `paid_pending_transfer`-shaped
 *   lock, key rotation (both directions — admit under the still-valid old
 *   key, and detect a `kid` claim that doesn't match who actually signed),
 *   alg-confusion (a token claiming a different algorithm than the manifest
 *   pins for that `kid`), tamper detection, manifest-authority absence, and
 *   the applied-set correctness property (base ⊕ deltas, not base alone).
 *
 *   Real Ed25519 keypairs (Node `node:crypto`, throwaway, generated
 *   in-process) stand in for whatever `VerifyPrimitive` a door/edge injects —
 *   same convention as `tests/credential-sign.test.ts`. This suite never
 *   imports `credential-sign/credential.ts`; the token shape here is the
 *   predicate's own abstraction (`OfflineToken`), not that module's wire
 *   format — see `offline-verify.ts`'s header comment.
 */
import { createPublicKey, generateKeyPairSync, sign as nodeSign, verify as nodeVerify, type KeyObject } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  applyM2,
  DEFAULT_TIME_BUCKET_SECONDS,
  DOMAIN,
  offlineVerify,
  type LocalAdmittedSet,
  type M1Entry,
  type M1Manifest,
  type M2AtomEntry,
  type M2Manifest,
  type OfflineToken,
  type OfflineVerifyContext,
  type VerifyPrimitive,
} from '../supabase/functions/_shared/offline-verify';

// ── Ed25519 test fixtures — throwaway keypairs, generated fresh every run ──

function genKeypair(): { privateKey: KeyObject; publicKeyB64: string } {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const der = publicKey.export({ type: 'spki', format: 'der' });
  return { privateKey, publicKeyB64: Buffer.from(der).toString('base64') };
}

function signBytes(privateKey: KeyObject, bytes: Uint8Array): Uint8Array {
  return new Uint8Array(nodeSign(null, Buffer.from(bytes), privateKey));
}

/** The injected verify primitive under test: real Ed25519 verify, refusing
 *  any algorithm other than `'EdDSA'` (an `'ES256'`-claiming token has no
 *  matching key material in these fixtures and must never reach here for a
 *  passing case — the alg-confusion cases assert it is refused earlier, at
 *  the `alg_mismatch` check, before this primitive is ever called). */
const verifyEd25519: VerifyPrimitive = (publicKeyB64, message, signature, algorithm) => {
  if (algorithm !== 'EdDSA') return false;
  const keyObject = createPublicKey({
    key: Buffer.from(publicKeyB64, 'base64'),
    format: 'der',
    type: 'spki',
  });
  return nodeVerify(null, Buffer.from(message), keyObject, Buffer.from(signature));
};

/** A verify primitive that always returns `false` — used only to prove a
 *  case never reaches step 2 (it would fail differently if it did). */
const verifyNeverCalled: VerifyPrimitive = () => {
  throw new Error('verify() must not be called past an earlier short-circuit');
};

// ── Fixture builders ──────────────────────────────────────────────────────

const NOW = 1_700_000_000; // an arbitrary fixed unix-seconds instant
const SESSION = 'session-aaaa';
const ATOM = 'atom-0001';
const MANIFEST_ID = 'manifest-0001';

function claimsFor(atomId: string, sessionId: string, credentialVersion: number, exp: number): Uint8Array {
  return new TextEncoder().encode(JSON.stringify({ atom: atomId, sess: sessionId, ver: credentialVersion, exp }));
}

function m1Entry(overrides: Partial<M1Entry> = {}): M1Entry {
  return {
    key_id: 'key-1',
    scope: 'event',
    event_id: 'event-1',
    public_key: '',
    algorithm: 'EdDSA',
    not_before: NOW - 10_000,
    not_after: NOW + 10_000,
    status: 'active',
    ...overrides,
  };
}

function m2AtomEntry(overrides: Partial<M2AtomEntry> = {}): M2AtomEntry {
  return {
    credential_version: 1,
    signing_key_id: 'key-1',
    ticket_state: 'active',
    resale_state: 'none',
    ...overrides,
  };
}

function baseM2(atomEntries: Record<string, M2AtomEntry>, overrides: Partial<M2Manifest> = {}): M2Manifest {
  return {
    manifest_id: MANIFEST_ID,
    session_id: SESSION,
    not_after: NOW + 10_000,
    base: atomEntries,
    deltas: [],
    ...overrides,
  };
}

function baseToken(overrides: Partial<OfflineToken> = {}, k: KeyObject | null = null): OfflineToken {
  const atomId = overrides.atomId ?? ATOM;
  const sessionId = overrides.sessionId ?? SESSION;
  const credentialVersion = overrides.credentialVersion ?? 1;
  const exp = overrides.exp ?? NOW + 5_000;
  const claims = overrides.claims ?? claimsFor(atomId, sessionId, credentialVersion, exp);
  const sig = overrides.sig ?? (k ? signBytes(k, claims) : new Uint8Array(64));
  return {
    keyId: 'key-1',
    typ: DOMAIN,
    algorithm: 'EdDSA',
    claims,
    sig,
    sessionId,
    atomId,
    credentialVersion,
    exp,
    ...overrides,
  };
}

function baseAdmittedSet(): LocalAdmittedSet {
  return new Set<string>();
}

function baseCtx(overrides: Partial<OfflineVerifyContext> = {}): OfflineVerifyContext {
  return {
    m1: {},
    m2: null,
    lastSyncedSeq: 0,
    boundSessionId: SESSION,
    nowSeconds: NOW,
    admittedSet: baseAdmittedSet(),
    verify: verifyEd25519,
    ...overrides,
  };
}

// ═══════════════════════════════════════════════════════════════════════════

describe('offlineVerify — happy path', () => {
  it('admits a well-formed, current, active, unlocked, correctly-signed token', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    const token = baseToken({}, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: true, atomId: ATOM });
  });
});

describe('offlineVerify — old-owner screenshot (credential_version staleness)', () => {
  it('rejects stale_version when the token predates a custody move, even though the signature verifies', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    // Post-transfer: the current owner's version is 2. The screenshot still
    // carries the old owner's version-1 token, genuinely signed by K1.
    const m2 = baseM2({ [ATOM]: m2AtomEntry({ credential_version: 2 }) });
    const staleToken = baseToken({ credentialVersion: 1 }, kp.privateKey);

    // Prove independently that M1/signature genuinely pass for this token —
    // the rejection is NOT a signature failure, it is a currency failure.
    expect(verifyEd25519(kp.publicKeyB64, staleToken.claims, staleToken.sig, 'EdDSA')).toBe(true);

    const result = offlineVerify(staleToken, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'stale_version' });
  });

  it('admits a fresh token minted at the new (post-transfer) version', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const m2 = baseM2({ [ATOM]: m2AtomEntry({ credential_version: 2 }) });
    const freshToken = baseToken({ credentialVersion: 2 }, kp.privateKey);

    const result = offlineVerify(freshToken, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: true, atomId: ATOM });
  });
});

describe('offlineVerify — 3b.v resale_state overlay (refund/dispute/paid_pending_transfer)', () => {
  const kp = genKeypair();
  const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };

  it.each([
    ['refund_hold', 'refund_hold'],
    ['dispute_hold', 'dispute_hold'],
    // paid_pending_transfer shape: state='active', resale_state='locked'
    ['locked', 'locked (paid_pending_transfer)'],
    ['listed', 'listed'],
  ])('rejects listed_locked for resale_state=%s (%s)', (resaleState) => {
    const m2 = baseM2({ [ATOM]: m2AtomEntry({ resale_state: resaleState }) });
    const token = baseToken({}, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'listed_locked' });
  });
});

describe('offlineVerify — 3b.iv ticket_state', () => {
  const kp = genKeypair();
  const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };

  it.each(['voided', 'scanned', 'expired', 'issued'])('rejects not_active for ticket_state=%s', (ticketState) => {
    const m2 = baseM2({ [ATOM]: m2AtomEntry({ ticket_state: ticketState }) });
    const token = baseToken({}, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'not_active' });
  });
});

describe('offlineVerify — 3b.i/3b.ii atom presence and revocation', () => {
  const kp = genKeypair();
  const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };

  it('rejects atom_absent when the atom is not in the applied M2 set at all', () => {
    const m2 = baseM2({}); // empty — no atoms
    const token = baseToken({}, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'atom_absent' });
  });

  it('rejects atom_revoked when an applied `revoke` delta targets the atom', () => {
    const m2 = baseM2(
      { [ATOM]: m2AtomEntry() },
      { deltas: [{ seq: 1, op: 'revoke', atom: ATOM }] },
    );
    const token = baseToken({}, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2, lastSyncedSeq: 1 }));
    expect(result).toEqual({ admit: false, reason: 'atom_revoked' });
  });
});

describe('offlineVerify — session binding, expiry, and skew', () => {
  const kp = genKeypair();
  const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
  const m2 = baseM2({ [ATOM]: m2AtomEntry() });

  it('rejects wrong_session when token.session_id != the bound scanning session', () => {
    const token = baseToken({ sessionId: 'session-other' }, kp.privateKey);
    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'wrong_session' });
  });

  it('rejects expired once past exp + 2 time-buckets (60s default)', () => {
    const exp = NOW - 61; // 61s in the past, 1s beyond the 60s tolerance
    const token = baseToken({ exp }, kp.privateKey);
    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'expired' });
  });

  it('admits within the ±2 time-bucket (60s) skew past exp', () => {
    const exp = NOW - 60; // exactly at the tolerance boundary
    const token = baseToken({ exp }, kp.privateKey);
    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: true, atomId: ATOM });
  });

  it('honors a custom timeBucketSeconds override', () => {
    const exp = NOW - 15; // 15s past exp
    const token = baseToken({ exp }, kp.privateKey);
    // bucket=5 => tolerance=10s; 15s late must reject
    const rejected = offlineVerify(token, baseCtx({ m1, m2, timeBucketSeconds: 5 }));
    expect(rejected).toEqual({ admit: false, reason: 'expired' });
    // bucket=10 => tolerance=20s; 15s late must admit
    const admitted = offlineVerify(token, baseCtx({ m1, m2, timeBucketSeconds: 10 }));
    expect(admitted).toEqual({ admit: true, atomId: ATOM });
  });
});

describe('offlineVerify — M1 key lookup (step 1)', () => {
  const kp = genKeypair();

  it('rejects unknown_key for a kid absent from M1', () => {
    const m1: M1Manifest = {};
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    const token = baseToken({}, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2, verify: verifyNeverCalled }));
    expect(result).toEqual({ admit: false, reason: 'unknown_key' });
  });

  it('rejects key_revoked when M1[kid].status == "revoked"', () => {
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64, status: 'revoked' }) };
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    const token = baseToken({}, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2, verify: verifyNeverCalled }));
    expect(result).toEqual({ admit: false, reason: 'key_revoked' });
  });

  it('rejects key_window when now() is outside [not_before, not_after]', () => {
    const m1: M1Manifest = {
      'key-1': m1Entry({ public_key: kp.publicKeyB64, not_before: NOW + 1, not_after: NOW + 10_000 }),
    };
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    const token = baseToken({}, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2, verify: verifyNeverCalled }));
    expect(result).toEqual({ admit: false, reason: 'key_window' });
  });
});

describe('offlineVerify — key rotation', () => {
  it('admits under a rotating key (K1) still in-window while K2 is the new active key', () => {
    const k1 = genKeypair();
    const k2 = genKeypair();
    const m1: M1Manifest = {
      'key-1': m1Entry({ key_id: 'key-1', public_key: k1.publicKeyB64, status: 'active' }),
      'key-2': m1Entry({ key_id: 'key-2', public_key: k2.publicKeyB64, status: 'active' }),
    };
    const m2 = baseM2({ [ATOM]: m2AtomEntry({ signing_key_id: 'key-1' }) });
    const token = baseToken({ keyId: 'key-1' }, k1.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: true, atomId: ATOM });
  });

  it('rejects signature_invalid when a token claims kid=K2 but was actually signed by K1', () => {
    const k1 = genKeypair();
    const k2 = genKeypair();
    const m1: M1Manifest = {
      'key-1': m1Entry({ key_id: 'key-1', public_key: k1.publicKeyB64, status: 'active' }),
      'key-2': m1Entry({ key_id: 'key-2', public_key: k2.publicKeyB64, status: 'active' }),
    };
    const m2 = baseM2({ [ATOM]: m2AtomEntry({ signing_key_id: 'key-2' }) });
    // Signed by K1's private key, but the header claims kid=K2 — verification
    // must run against K2's public key (per the claimed kid) and fail.
    const token = baseToken({ keyId: 'key-2' }, k1.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'signature_invalid' });
  });

  it('rejects wrong_signing_key (3c) when token.key_id != M2[atom].signing_key_id, both valid in M1', () => {
    const k1 = genKeypair();
    const k2 = genKeypair();
    const m1: M1Manifest = {
      'key-1': m1Entry({ key_id: 'key-1', public_key: k1.publicKeyB64, status: 'active' }),
      'key-2': m1Entry({ key_id: 'key-2', public_key: k2.publicKeyB64, status: 'active' }),
    };
    // The atom's pinned signing key is K2, but the token is genuinely signed
    // by K1 (in-window, valid, verifies fine against M1) — 3c must still fail.
    const m2 = baseM2({ [ATOM]: m2AtomEntry({ signing_key_id: 'key-2' }) });
    const token = baseToken({ keyId: 'key-1' }, k1.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'wrong_signing_key' });
  });
});

describe('offlineVerify — alg-confusion (PFA-PT-8)', () => {
  it('rejects alg_mismatch when token.algorithm disagrees with M1[kid].algorithm, before any signature check', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64, algorithm: 'EdDSA' }) };
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    const token = baseToken({ algorithm: 'ES256' }, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2, verify: verifyNeverCalled }));
    expect(result).toEqual({ admit: false, reason: 'alg_mismatch' });
  });
});

describe('offlineVerify — tamper detection', () => {
  const kp = genKeypair();
  const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
  const m2 = baseM2({ [ATOM]: m2AtomEntry() });

  it('rejects signature_invalid for a tampered payload (claims mutated post-sign)', () => {
    const genuine = baseToken({}, kp.privateKey);
    const tamperedClaims = claimsFor('atom-9999', SESSION, 1, genuine.exp); // different atom, same sig
    const token: OfflineToken = { ...genuine, claims: tamperedClaims };

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'signature_invalid' });
  });

  it('rejects signature_invalid when a genuine signature is checked against a substituted public key for the same kid', () => {
    // A genuinely-signed token (by kp) verified against a DIFFERENT key
    // trusted under the same `kid` — models a corrupted/substituted M1
    // public_key entry (still passes the alg pin: both declare EdDSA).
    const otherKp = genKeypair();
    const token = baseToken({}, kp.privateKey);
    const m1WithSubstitutedKey: M1Manifest = { 'key-1': m1Entry({ public_key: otherKp.publicKeyB64 }) };

    const result = offlineVerify(token, baseCtx({ m1: m1WithSubstitutedKey, m2 }));
    expect(result).toEqual({ admit: false, reason: 'signature_invalid' });
  });

  it('rejects signature_invalid for a tampered/corrupted signature', () => {
    const genuine = baseToken({}, kp.privateKey);
    const corrupted = new Uint8Array(genuine.sig);
    corrupted[0] ^= 0xff;
    const token: OfflineToken = { ...genuine, sig: corrupted };

    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'signature_invalid' });
  });
});

describe('offlineVerify — manifest-authority gate', () => {
  const kp = genKeypair();
  const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };

  it('rejects no_manifest when M2 is absent', () => {
    const token = baseToken({}, kp.privateKey);
    const result = offlineVerify(token, baseCtx({ m1, m2: null }));
    expect(result).toEqual({ admit: false, reason: 'no_manifest' });
  });

  it('rejects manifest_other_session when M2.session_id != the bound session', () => {
    const m2 = baseM2({ [ATOM]: m2AtomEntry() }, { session_id: 'session-other' });
    const token = baseToken({}, kp.privateKey);
    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'manifest_other_session' });
  });

  it('rejects manifest_expired once past the M2\'s own downloaded not_after', () => {
    const m2 = baseM2({ [ATOM]: m2AtomEntry() }, { not_after: NOW - 1 });
    const token = baseToken({}, kp.privateKey);
    const result = offlineVerify(token, baseCtx({ m1, m2 }));
    expect(result).toEqual({ admit: false, reason: 'manifest_expired' });
  });
});

describe('offlineVerify — first-in-wins (step 4, double-scan)', () => {
  it('rejects already_admitted when the atom is already in the local admitted set', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    const token = baseToken({}, kp.privateKey);
    const admittedSet: LocalAdmittedSet = new Set([ATOM]);

    const result = offlineVerify(token, baseCtx({ m1, m2, admittedSet }));
    expect(result).toEqual({ admit: false, reason: 'already_admitted' });
  });

  it('does not mutate the caller\'s admittedSet on admit — the caller must record it', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    const token = baseToken({}, kp.privateKey);
    const admittedSet = new Set<string>();

    const result = offlineVerify(token, baseCtx({ m1, m2, admittedSet }));
    expect(result).toEqual({ admit: true, atomId: ATOM });
    expect(admittedSet.size).toBe(0); // unchanged — pure function, no side effect
  });
});

describe('offlineVerify — applied-set correctness (base ⊕ deltas, not base alone)', () => {
  it('rejects atom_revoked when a base-admitting snapshot has a later revoke delta within last_synced_seq', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const m2 = baseM2(
      { [ATOM]: m2AtomEntry() }, // base snapshot: perfectly admissible
      { deltas: [{ seq: 1, op: 'revoke', atom: ATOM }] },
    );
    const token = baseToken({}, kp.privateKey);

    // Proof this is genuinely an applied-set property, not a base-snapshot
    // rejection: evaluating the base snapshot alone (applyM2 with
    // lastSyncedSeq=0, before the delta is synced) still admits.
    const preDeltaApplied = applyM2(m2, 0);
    expect(preDeltaApplied[ATOM]?.revoked).toBe(false);

    const result = offlineVerify(token, baseCtx({ m1, m2, lastSyncedSeq: 1 }));
    expect(result).toEqual({ admit: false, reason: 'atom_revoked' });
  });

  it('does not apply a delta whose seq is beyond lastSyncedSeq (not yet downloaded)', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const m2 = baseM2(
      { [ATOM]: m2AtomEntry() },
      { deltas: [{ seq: 5, op: 'revoke', atom: ATOM }] },
    );
    const token = baseToken({}, kp.privateKey);

    // Device has only synced up to seq=2 — the seq=5 revoke is not applied.
    const result = offlineVerify(token, baseCtx({ m1, m2, lastSyncedSeq: 2 }));
    expect(result).toEqual({ admit: true, atomId: ATOM });
  });

  it('an `add` delta supplements a brand-new atom not in the base snapshot', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const supplementedAtom = 'atom-supplemented';
    const m2 = baseM2(
      {}, // empty base
      { deltas: [{ seq: 1, op: 'add', atom: supplementedAtom, entry: m2AtomEntry() }] },
    );
    const token = baseToken({ atomId: supplementedAtom }, kp.privateKey);

    const result = offlineVerify(token, baseCtx({ m1, m2, lastSyncedSeq: 1 }));
    expect(result).toEqual({ admit: true, atomId: supplementedAtom });
  });
});

describe('step 0 — domain separation + algorithm whitelist (adversarial hardening)', () => {
  it('refuses wrong_typ before any key/signature work — a genuinely-signed non-ticket token is not admitted', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    // Correctly signed under a TRUSTED key, but declaring a different typ.
    const token = baseToken({ typ: 'SNATCHIT-WALLET-MANIFEST-V1' }, kp.privateKey);
    expect(offlineVerify(token, baseCtx({ m1, m2 }))).toEqual({ admit: false, reason: 'wrong_typ' });
  });

  it('refuses an unrecognized token algorithm (unsupported_alg) before the M1 lookup', () => {
    const kp = genKeypair();
    const m1: M1Manifest = { 'key-1': m1Entry({ public_key: kp.publicKeyB64 }) };
    const m2 = baseM2({ [ATOM]: m2AtomEntry() });
    const token = baseToken({ algorithm: 'HS256' }, kp.privateKey);
    expect(offlineVerify(token, baseCtx({ m1, m2 }))).toEqual({ admit: false, reason: 'unsupported_alg' });
  });
});

describe('DEFAULT_TIME_BUCKET_SECONDS', () => {
  it('is 30 seconds, so the default skew tolerance is ±60s (RPC §9.3 / R-22 / MP-1)', () => {
    expect(DEFAULT_TIME_BUCKET_SECONDS).toBe(30);
  });
});
