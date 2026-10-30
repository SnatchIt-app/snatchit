/**
 * SCANNER-CONTRACT-v1 — repository-side conformance suite for the scanner/
 * mobile boundary (`docs/phase2/SCANNER_VERIFIER_CONTRACT.md`).
 *
 * The mobile scanner is NOT in this repository. This suite proves the
 * REFERENCE decoder/adapters/verifier in `_shared/offline-verify.ts` and
 * produces/verifies the GOLDEN FIXTURES an external scanner must reproduce
 * (`tests/fixtures/scanner-contract-v1.json`).
 *
 * Fixture generation: `SCANNER_FIXTURES_WRITE=1 npx vitest run tests/scanner-contract.test.ts`
 * regenerates the JSON from a throwaway P-256 / Ed25519 key pair generated
 * in-process and DISCARDED — only public keys, tokens and signatures are
 * written. A normal run loads the committed file and asserts every expected
 * outcome (and that the committed public keys/tokens are self-consistent).
 *
 * COVERAGE
 *   1  decoder: one signed wire ⇒ every predicate field; exact key sets; strict
 *      base64url; uuid/int shapes; 64-byte sig; no parallel-field bypass (an
 *      extra `atom_id`/`session_id` key ⇒ malformed; ANY change to a derived
 *      field changes the signed bytes ⇒ signature_invalid)
 *   2  M1 adapter: PEM/bare public_key, ISO/NULL windows, malformed rows, dup ids
 *   3  M2 adapter: reconciled shape ⇒ ok; the 086 body's shape (no
 *      session_id/not_after) ⇒ manifest_header_incomplete; no-open; malformed
 *   4  DOOR-MANIFEST-SIG-v1: sign/verify, tamper, unsigned, missing key_id,
 *      revoked/window/alg-pin/normalizer rules
 *   5  operator-reason map (door §9.2)
 *   6  golden fixtures: every vector's expected outcome
 */
import { createPublicKey, generateKeyPairSync, sign as nodeSign, verify as nodeVerify, type KeyObject } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { buildCanonicalPayload, encodeToken, type TicketSigningContext } from '../supabase/functions/credential-sign/credential';
import {
  applyM2,
  canonicalDoorManifestSignedBytes,
  decodeOfflineToken,
  DOMAIN,
  m1FromWire,
  m2FromWire,
  MAX_WIRE_TOKEN_LENGTH,
  offlineVerify,
  toDoorReason,
  verifyDoorManifestSignature,
  verifyOfflineWire,
  type M1Manifest,
  type OfflineVerifyContext,
  type OfflineVerifyResult,
  type VerifyPrimitive,
} from '../supabase/functions/_shared/offline-verify';

const FIXTURE_PATH = resolve(__dirname, 'fixtures/scanner-contract-v1.json');
const WRITE = process.env.SCANNER_FIXTURES_WRITE === '1';

// ── crypto helpers (test-only stand-ins for the scanner's primitive) ────────
const verifyNode: VerifyPrimitive = (publicKeyB64, message, signature, algorithm) => {
  const key = createPublicKey({ key: Buffer.from(publicKeyB64, 'base64'), format: 'der', type: 'spki' });
  if (algorithm === 'ES256') return nodeVerify('sha256', Buffer.from(message), { key, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature));
  if (algorithm === 'EdDSA') return nodeVerify(null, Buffer.from(message), key, Buffer.from(signature));
  return false;
};
function signEs256Raw(k: KeyObject, bytes: Uint8Array): Uint8Array {
  return new Uint8Array(nodeSign('sha256', Buffer.from(bytes), { key: k, dsaEncoding: 'ieee-p1363' }));
}
function signEd25519(k: KeyObject, bytes: Uint8Array): Uint8Array {
  return new Uint8Array(nodeSign(null, Buffer.from(bytes), k));
}
function genP256() {
  const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return { privateKey, pem: publicKey.export({ type: 'spki', format: 'pem' }) as string, bare: (publicKey.export({ type: 'spki', format: 'der' }) as Buffer).toString('base64') };
}
function genEd() {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  return { privateKey, pem: publicKey.export({ type: 'spki', format: 'pem' }) as string, bare: (publicKey.export({ type: 'spki', format: 'der' }) as Buffer).toString('base64') };
}

// ── fixed identifiers (the golden vectors are deterministic apart from key material) ──
const NOW = 1_800_000_000; // 2027-01-15T08:00:00Z
const SESSION = '5e55e55e-0000-4000-8000-000000000001';
const OTHER_SESSION = '5e55e55e-0000-4000-8000-000000000002';
const ATOM = 'a70a70a7-0000-4000-8000-000000000001';
const ATOM_SCANNED = 'a70a70a7-0000-4000-8000-000000000002';
const ATOM_LISTED = 'a70a70a7-0000-4000-8000-000000000003';
const ATOM_REFUND = 'a70a70a7-0000-4000-8000-000000000004';
const ATOM_REVOKED = 'a70a70a7-0000-4000-8000-000000000005';
const ATOM_ADDED = 'a70a70a7-0000-4000-8000-000000000006';
const K1 = '00000000-0000-0000-0000-0000000000b0'; // ES256, PEM in M1 (the bootstrap lineage id)
const K2 = '00000000-0000-0000-0000-0000000000b1'; // ES256, bare base64 in M1
const K3 = '00000000-0000-0000-0000-0000000000b2'; // ES256, revoked
const K4 = '00000000-0000-0000-0000-0000000000b3'; // EdDSA (existing verifier contract)
const MANIFEST_ID = 'aa00aa00-0000-4000-8000-000000000001';

function ctx(over: Partial<TicketSigningContext> & { key_id: string; algorithm: 'ES256' | 'EdDSA' }): TicketSigningContext {
  return { ticket_atom_id: ATOM, session_id: SESSION, credential_version: 1, issued_at: NOW - 60, exp: NOW + 3600, ...over };
}
/** `signAs` overrides which primitive signs (default: the header's alg) — used
 *  to mint the alg-confusion vector: a header that CLAIMS EdDSA over an ES256
 *  signature, so the decoder accepts it (64 bytes) and the predicate's pin refuses it. */
function mint(k: KeyObject, c: TicketSigningContext, signAs?: 'ES256' | 'EdDSA'): string {
  const canonical = buildCanonicalPayload(c);
  const alg = signAs ?? c.algorithm;
  const sig = alg === 'EdDSA' ? signEd25519(k, canonical.signedBytes) : signEs256Raw(k, canonical.signedBytes);
  return encodeToken(canonical.headerB64, canonical.payloadB64, sig);
}

// ── the reconciled M2 wire shape (RPC §20.6.1) ─────────────────────────────
function m2Wire(over: Record<string, unknown> = {}) {
  const entry = (id: string, ver: number, key: string, ts = 'active', rs = 'none') => ({
    ticket_atom_id: id, serial_no: 1, ticket_type_id: 'tt00tt00-0000-4000-8000-000000000001',
    credential_version: ver, signing_key_id: key, ticket_state: ts, resale_state: rs,
  });
  return {
    open: true, status: 'ok', manifest_id: MANIFEST_ID, manifest_version: 1, session_id: SESSION,
    opened_at: new Date((NOW - 600) * 1000).toISOString(), not_after: new Date((NOW + 7200) * 1000).toISOString(),
    manifest_digest: 'd1d1d1d1'.repeat(8), max_delta_seq: 2,
    entries: [entry(ATOM, 1, K1), entry(ATOM_SCANNED, 1, K1, 'scanned'), entry(ATOM_LISTED, 1, K1, 'active', 'listed'),
              entry(ATOM_REFUND, 1, K1, 'active', 'refund_hold'), entry(ATOM_REVOKED, 1, K1)],
    deltas: [
      { seq: 1, ticket_atom_id: ATOM_REVOKED, op: 'revoke' },
      { ...entry(ATOM_ADDED, 0, K2), seq: 2, op: 'add' },
    ],
    ...over,
  };
}

function baseCtx(m1: M1Manifest, m2wire: unknown, over: Partial<OfflineVerifyContext> = {}): OfflineVerifyContext {
  const m2 = m2FromWire(m2wire);
  return { m1, m2: m2.ok ? m2.m2 : null, lastSyncedSeq: 2, boundSessionId: SESSION, nowSeconds: NOW, admittedSet: new Set(), verify: verifyNode, ...over };
}

// ═══════════════════════════════════════════════════════════════════════════

describe('1. decoder — one signed wire representation, no parallel fields', () => {
  const k1 = genP256();
  const wire = mint(k1.privateKey, ctx({ key_id: K1, algorithm: 'ES256' }));

  it('derives key_id/typ/algorithm from the header and session/atom/version/exp from the payload; claims are the signed bytes', () => {
    const t = decodeOfflineToken(wire)!;
    expect(t).not.toBeNull();
    expect(t.keyId).toBe(K1);
    expect(t.typ).toBe(DOMAIN);
    expect(t.algorithm).toBe('ES256');
    expect(t.sessionId).toBe(SESSION);
    expect(t.atomId).toBe(ATOM);
    expect(t.credentialVersion).toBe(1);
    expect(t.exp).toBe(NOW + 3600);
    const [h, p] = wire.split('.');
    expect(Buffer.from(t.claims).toString()).toBe(`${h}.${p}`);
    expect(t.sig).toHaveLength(64);
    expect(verifyNode(k1.bare, t.claims, t.sig, 'ES256')).toBe(true);
  });

  it('rejects structural deviations: wrong segment count, padding, whitespace, non-base64url, oversize, non-string', () => {
    const [h, p, s] = wire.split('.');
    for (const bad of [`${h}.${p}`, `${h}.${p}.${s}.x`, `${h}=.${p}.${s}`, `${h}.${p}.${s} `, `${h}.${p}.${s.replace(/[A-Za-z]/, '+')}`, '', 'x'.repeat(MAX_WIRE_TOKEN_LENGTH + 1), 42, null, undefined, {}]) {
      expect(decodeOfflineToken(bad), String(bad).slice(0, 30)).toBeNull();
    }
  });

  function reencode(h: string, p: string, s: string, edit: (hdr: Record<string, unknown>, pl: Record<string, unknown>) => void): string {
    const hdr = JSON.parse(Buffer.from(h, 'base64url').toString());
    const pl = JSON.parse(Buffer.from(p, 'base64url').toString());
    edit(hdr, pl);
    return `${Buffer.from(JSON.stringify(hdr)).toString('base64url')}.${Buffer.from(JSON.stringify(pl)).toString('base64url')}.${s}`;
  }

  it('rejects an extra or missing key in header/payload — a parallel `atom_id`/`session_id`/`ver2` cannot ride alongside the signed claims', () => {
    const [h, p, s] = wire.split('.');
    expect(decodeOfflineToken(reencode(h, p, s, (_, pl) => { pl.atom_id = ATOM_SCANNED; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (_, pl) => { pl.session_id = OTHER_SESSION; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (_, pl) => { pl.credential_version = 9; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (hdr) => { hdr.key_id = K2; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (hdr) => { delete hdr.typ; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (_, pl) => { delete pl.ver; }))).toBeNull();
  });

  it('rejects wrong shapes: non-uuid ids, non-integer times/version, iat > exp, a 63-byte signature under a known alg', () => {
    const [h, p, s] = wire.split('.');
    expect(decodeOfflineToken(reencode(h, p, s, (_, pl) => { pl.atom = 'not-a-uuid'; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (hdr) => { hdr.kid = 'K1'; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (_, pl) => { pl.exp = '1800003600'; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (_, pl) => { pl.ver = 1.5; }))).toBeNull();
    expect(decodeOfflineToken(reencode(h, p, s, (_, pl) => { pl.iat = pl.exp as number + 1; }))).toBeNull();
    const short = Buffer.from(s, 'base64url').subarray(0, 63);
    expect(decodeOfflineToken(`${h}.${p}.${Buffer.from(short).toString('base64url')}`)).toBeNull();
    // an UNKNOWN alg is decodable (the predicate refuses it) — the decoder only pins length for known algs
    expect(decodeOfflineToken(reencode(h, p, s, (hdr) => { hdr.alg = 'RS256'; }))).not.toBeNull();
  });

  it('any change to a derived field changes the signed bytes ⇒ the predicate refuses signature_invalid (or earlier)', () => {
    const [h, p, s] = wire.split('.');
    const m1 = m1FromWire([{ key_id: K1, scope: 'global', public_key: k1.pem, algorithm: 'ES256', status: 'active', not_before: new Date((NOW - 86400) * 1000).toISOString(), not_after: null }])!;
    const c = baseCtx(m1, m2Wire());
    expect(verifyOfflineWire(wire, c)).toEqual({ admit: true, atomId: ATOM });
    expect(verifyOfflineWire(reencode(h, p, s, (_, pl) => { pl.atom = ATOM_SCANNED; }), c)).toEqual({ admit: false, reason: 'signature_invalid' });
    expect(verifyOfflineWire(reencode(h, p, s, (_, pl) => { pl.sess = OTHER_SESSION; }), c)).toEqual({ admit: false, reason: 'signature_invalid' });
    expect(verifyOfflineWire(reencode(h, p, s, (_, pl) => { pl.ver = 2; }), c)).toEqual({ admit: false, reason: 'signature_invalid' });
    expect(verifyOfflineWire(reencode(h, p, s, (_, pl) => { pl.exp = NOW + 99999; }), c)).toEqual({ admit: false, reason: 'signature_invalid' });
    expect(verifyOfflineWire(reencode(h, p, s, (hdr) => { hdr.kid = K2; }), c)).toEqual({ admit: false, reason: 'unknown_key' });
    expect(verifyOfflineWire(reencode(h, p, s, (hdr) => { hdr.typ = 'SNATCHIT-DOOR-MANIFEST-V1'; }), c)).toEqual({ admit: false, reason: 'wrong_typ' });
    expect(verifyOfflineWire(reencode(h, p, s, (hdr) => { hdr.alg = 'EdDSA'; }), c)).toEqual({ admit: false, reason: 'alg_mismatch' });
    expect(verifyOfflineWire('garbage', c)).toEqual({ admit: false, reason: 'malformed_token' });
  });
});

describe('2. M1 wire adapter', () => {
  const k1 = genP256();
  it('accepts PEM or bare public_key, ISO windows, NULL not_after (⇒ unbounded), and keeps status/scope', () => {
    const m1 = m1FromWire([
      { key_id: K1, scope: 'global', event_id: null, venue_id: null, public_key: k1.pem, algorithm: 'ES256', status: 'active', not_before: '2026-09-05T00:00:00Z', not_after: null },
      { key_id: K2, scope: 'per_event', event_id: 'e0e0e0e0-0000-4000-8000-000000000001', venue_id: null, public_key: k1.bare, algorithm: 'ES256', status: 'rotating', not_before: 1_700_000_000, not_after: '2027-01-01T00:00:00Z' },
    ])!;
    expect(m1[K1].not_after).toBe(Number.POSITIVE_INFINITY);
    expect(m1[K1].not_before).toBe(Math.floor(Date.parse('2026-09-05T00:00:00Z') / 1000));
    expect(m1[K2].not_after).toBe(Math.floor(Date.parse('2027-01-01T00:00:00Z') / 1000));
    expect(m1[K2].status).toBe('rotating');
  });
  it('refuses the whole keyring on any malformed row or duplicate key_id', () => {
    const good = { key_id: K1, scope: 'global', public_key: k1.pem, algorithm: 'ES256', status: 'active', not_before: '2026-09-05T00:00:00Z', not_after: null };
    expect(m1FromWire([good, { ...good, key_id: 'K2' }])).toBeNull();
    expect(m1FromWire([good, { ...good, scope: 'per_show' }])).toBeNull();
    expect(m1FromWire([good, { ...good, key_id: K2, not_before: 'yesterday' }])).toBeNull();
    expect(m1FromWire([good, { ...good, key_id: K2, public_key: '' }])).toBeNull();
    expect(m1FromWire([good, good])).toBeNull();
    expect(m1FromWire('nope')).toBeNull();
    expect(m1FromWire([])).toEqual({});
  });
});

describe('3. M2 wire adapter (RPC §20.6.1 reconciled shape)', () => {
  it('turns the reconciled result into base ⊕ deltas with the header the authority clause needs', () => {
    const r = m2FromWire(m2Wire());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.m2.session_id).toBe(SESSION);
    expect(r.m2.not_after).toBe(NOW + 7200);
    expect(Object.keys(r.m2.base)).toHaveLength(5);
    expect(r.m2.deltas).toEqual([
      { seq: 1, op: 'revoke', atom: ATOM_REVOKED },
      { seq: 2, op: 'add', atom: ATOM_ADDED, entry: { credential_version: 0, signing_key_id: K2, ticket_state: 'active', resale_state: 'none' } },
    ]);
    expect(r.maxDeltaSeq).toBe(2);
  });
  it('the 086 RPC body shape (status ok, NO session_id / not_after / open) ⇒ manifest_header_incomplete — no offline authority', () => {
    const legacy = m2Wire();
    delete (legacy as Record<string, unknown>).open;
    delete (legacy as Record<string, unknown>).session_id;
    delete (legacy as Record<string, unknown>).not_after;
    delete (legacy as Record<string, unknown>).opened_at;
    expect(m2FromWire(legacy)).toEqual({ ok: false, reason: 'manifest_header_incomplete' });
    expect(m2FromWire(m2Wire({ session_id: 'not-a-uuid' }))).toEqual({ ok: false, reason: 'manifest_header_incomplete' });
    expect(m2FromWire(m2Wire({ not_after: 'never' }))).toEqual({ ok: false, reason: 'manifest_header_incomplete' });
  });
  it('no-open states (both spellings) and malformed entries/deltas', () => {
    expect(m2FromWire({ open: false, status: 'no_open_manifest', entries: [], deltas: [] })).toEqual({ ok: false, reason: 'no_open_manifest' });
    expect(m2FromWire({ status: 'no_open_episode' })).toEqual({ ok: false, reason: 'no_open_manifest' });
    expect(m2FromWire(m2Wire({ entries: [{ ticket_atom_id: ATOM }] }))).toEqual({ ok: false, reason: 'manifest_malformed' });
    expect(m2FromWire(m2Wire({ deltas: [{ seq: 1, ticket_atom_id: ATOM, op: 'drop' }] }))).toEqual({ ok: false, reason: 'manifest_malformed' });
    expect(m2FromWire(m2Wire({ deltas: [{ seq: 1, ticket_atom_id: ATOM, op: 'add' }] }))).toEqual({ ok: false, reason: 'manifest_malformed' });
    expect(m2FromWire(m2Wire({ manifest_id: 'x' }))).toEqual({ ok: false, reason: 'manifest_malformed' });
    expect(m2FromWire(null)).toEqual({ ok: false, reason: 'manifest_malformed' });
  });
});

describe('4. DOOR-MANIFEST-SIG-v1', () => {
  const k1 = genP256();
  const m1 = m1FromWire([{ key_id: K1, scope: 'global', public_key: k1.pem, algorithm: 'ES256', status: 'active', not_before: '2026-09-05T00:00:00Z', not_after: null },
                         { key_id: K3, scope: 'global', public_key: k1.pem, algorithm: 'ES256', status: 'revoked', not_before: '2026-09-05T00:00:00Z', not_after: null }])!;
  const header = { manifest_id: MANIFEST_ID, manifest_version: 1, session_id: SESSION, not_after: new Date((NOW + 7200) * 1000).toISOString(), manifest_digest: 'd1d1d1d1'.repeat(8) };
  const bytes = canonicalDoorManifestSignedBytes(header);
  const sigB64 = Buffer.from(signEs256Raw(k1.privateKey, bytes)).toString('base64');
  const artifact = (over: Record<string, unknown> = {}, sig: Record<string, unknown> | null = { key_id: K1, algorithm: 'ES256', value: sigB64 }) =>
    ({ manifest: { ...header, entries: [], deltas: [], max_delta_seq: 0, ...over }, signature: sig });

  it('the canonical bytes are JSON.stringify of the five header fields in the edge\'s key order', () => {
    expect(Buffer.from(bytes).toString()).toBe(`{"manifest_id":"${MANIFEST_ID}","manifest_version":1,"session_id":"${SESSION}","not_after":"${header.not_after}","manifest_digest":"${header.manifest_digest}"}`);
  });
  it('verifies a correctly signed artifact against M1[key_id]', () => {
    expect(verifyDoorManifestSignature(artifact(), m1, verifyNode, NOW)).toEqual({ ok: true, keyId: K1 });
  });
  it('refuses tampering of any signed header field, a wrong/absent key_id, an unsigned artifact, a revoked key, alg mismatch, malformed signature', () => {
    expect(verifyDoorManifestSignature(artifact({ manifest_digest: 'e2e2e2e2'.repeat(8) }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'signature_invalid' });
    expect(verifyDoorManifestSignature(artifact({ not_after: new Date((NOW + 99999) * 1000).toISOString() }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'signature_invalid' });
    expect(verifyDoorManifestSignature(artifact({ session_id: OTHER_SESSION }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'signature_invalid' });
    expect(verifyDoorManifestSignature(artifact({ manifest_version: 2 }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'signature_invalid' });
    expect(verifyDoorManifestSignature(artifact({}, { algorithm: 'ES256', value: sigB64 }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'missing_key_id' });
    expect(verifyDoorManifestSignature(artifact({}, null), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'unsigned' });
    expect(verifyDoorManifestSignature(artifact({}, { key_id: K2, algorithm: 'ES256', value: sigB64 }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'unknown_key' });
    expect(verifyDoorManifestSignature(artifact({}, { key_id: K3, algorithm: 'ES256', value: sigB64 }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'key_revoked' });
    expect(verifyDoorManifestSignature(artifact({}, { key_id: K1, algorithm: 'EdDSA', value: sigB64 }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'alg_mismatch' });
    expect(verifyDoorManifestSignature(artifact({}, { key_id: K1, algorithm: 'RS256', value: sigB64 }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'unsupported_alg' });
    expect(verifyDoorManifestSignature(artifact({}, { key_id: K1, algorithm: 'ES256', value: sigB64.slice(0, -4) }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'malformed_signature' });
    expect(verifyDoorManifestSignature(artifact({}, { key_id: K1, algorithm: 'ES256', value: Buffer.from(signEs256Raw(k1.privateKey, bytes)).toString('base64url') }), m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'malformed_signature' });
    expect(verifyDoorManifestSignature(artifact(), m1, verifyNode, Math.floor(Date.parse('2026-01-01T00:00:00Z') / 1000))).toEqual({ ok: false, reason: 'key_window' });
    expect(verifyDoorManifestSignature('x', m1, verifyNode, NOW)).toEqual({ ok: false, reason: 'malformed_artifact' });
  });
});

describe('5. operator vocabulary (door §9.2)', () => {
  it('maps per-conjunct codes onto the six door reasons and returns null where §9.2 defines no copy', () => {
    const e = (ticket_state: string, resale_state = 'none') => ({ credential_version: 1, signing_key_id: K1, ticket_state, resale_state, revoked: false });
    expect(toDoorReason('atom_absent')).toBe('wrong_session');
    expect(toDoorReason('wrong_session')).toBe('wrong_session');
    expect(toDoorReason('atom_revoked', e('active'))).toBe('voided');
    expect(toDoorReason('not_active', e('scanned'))).toBe('duplicate');
    expect(toDoorReason('not_active', e('voided'))).toBe('voided');
    expect(toDoorReason('not_active', e('issued'))).toBeNull();
    expect(toDoorReason('listed_locked', e('active', 'listed'))).toBe('listed_locked');
    expect(toDoorReason('listed_locked', e('active', 'refund_hold'))).toBe('refund_hold');
    expect(toDoorReason('listed_locked', e('active', 'dispute_hold'))).toBe('dispute_hold');
    expect(toDoorReason('stale_version')).toBe('version_stale');
    expect(toDoorReason('wrong_signing_key')).toBe('version_stale');
    expect(toDoorReason('already_admitted')).toBe('duplicate');
    for (const r of ['signature_invalid', 'unknown_key', 'key_revoked', 'key_window', 'alg_mismatch', 'malformed_public_key', 'malformed_token', 'no_manifest', 'manifest_expired', 'manifest_other_session', 'expired', 'wrong_typ', 'unsupported_alg'] as const) {
      expect(toDoorReason(r), r).toBeNull();
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 6. GOLDEN FIXTURES — generated by the reference implementation, verified on every run.
// ═══════════════════════════════════════════════════════════════════════════

interface FixtureVector { name: string; wire: string; now_seconds: number; bound_session: string; last_synced_seq: number; expected: OfflineVerifyResult; door_reason: string | null }
interface FixtureFile {
  contract: 'SCANNER-CONTRACT-v1';
  generated_by: string;
  m1_wire: unknown[];
  m2_wire: unknown;
  tokens: FixtureVector[];
  door_manifest: { artifact: unknown; expected: { ok: boolean; reason?: string; keyId?: string }; tampered_digest_expected: { ok: false; reason: 'signature_invalid' } };
}

function buildFixtures(): FixtureFile {
  const p1 = genP256(), p2 = genP256(), p3 = genP256(), ed = genEd();
  const iso = (s: number) => new Date(s * 1000).toISOString();
  const m1_wire = [
    { key_id: K1, scope: 'global', event_id: null, venue_id: null, public_key: p1.pem, algorithm: 'ES256', status: 'active', not_before: iso(NOW - 86400), not_after: null },
    { key_id: K2, scope: 'global', event_id: null, venue_id: null, public_key: p2.bare, algorithm: 'ES256', status: 'rotating', not_before: iso(NOW - 86400), not_after: iso(NOW + 86400) },
    { key_id: K3, scope: 'global', event_id: null, venue_id: null, public_key: p3.pem, algorithm: 'ES256', status: 'revoked', not_before: iso(NOW - 86400), not_after: null },
    { key_id: K4, scope: 'global', event_id: null, venue_id: null, public_key: ed.pem, algorithm: 'EdDSA', status: 'active', not_before: iso(NOW - 86400), not_after: null },
  ];
  const m2_wire = m2Wire();
  const v = (name: string, wire: string, expected: OfflineVerifyResult, door_reason: string | null, over: Partial<FixtureVector> = {}): FixtureVector =>
    ({ name, wire, now_seconds: NOW, bound_session: SESSION, last_synced_seq: 2, expected, door_reason, ...over });
  const tokens: FixtureVector[] = [
    v('admit_es256_pem_key', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256' })), { admit: true, atomId: ATOM }, null),
    v('admit_es256_bare_key_rotating_added_atom', mint(p2.privateKey, ctx({ key_id: K2, algorithm: 'ES256', ticket_atom_id: ATOM_ADDED, credential_version: 0 })), { admit: true, atomId: ATOM_ADDED }, null),
    v('admit_eddsa_existing_contract_wrong_signing_key', mint(ed.privateKey, ctx({ key_id: K4, algorithm: 'EdDSA' })), { admit: false, reason: 'wrong_signing_key' }, 'version_stale'),
    v('stale_version_old_owner_screenshot', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', credential_version: 0 })), { admit: false, reason: 'stale_version' }, 'version_stale'),
    v('wrong_session', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', session_id: OTHER_SESSION })), { admit: false, reason: 'wrong_session' }, 'wrong_session'),
    v('expired_past_skew', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', issued_at: NOW - 7200, exp: NOW - 61 })), { admit: false, reason: 'expired' }, null),
    v('admit_within_skew', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', issued_at: NOW - 7200, exp: NOW - 59 })), { admit: true, atomId: ATOM }, null),
    v('key_revoked', mint(p3.privateKey, ctx({ key_id: K3, algorithm: 'ES256' })), { admit: false, reason: 'key_revoked' }, null),
    v('key_window_rotating_key_after_not_after', mint(p2.privateKey, ctx({ key_id: K2, algorithm: 'ES256', ticket_atom_id: ATOM_ADDED, credential_version: 0 })), { admit: false, reason: 'key_window' }, null, { now_seconds: NOW + 86401 }),
    v('alg_mismatch_header_claims_eddsa_under_es256_key', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'EdDSA' }), 'ES256'), { admit: false, reason: 'alg_mismatch' }, null),
    v('signature_invalid_signed_by_other_key', mint(p2.privateKey, ctx({ key_id: K1, algorithm: 'ES256' })), { admit: false, reason: 'signature_invalid' }, null),
    v('atom_scanned_duplicate', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', ticket_atom_id: ATOM_SCANNED })), { admit: false, reason: 'not_active' }, 'duplicate'),
    v('atom_listed', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', ticket_atom_id: ATOM_LISTED })), { admit: false, reason: 'listed_locked' }, 'listed_locked'),
    v('atom_refund_hold', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', ticket_atom_id: ATOM_REFUND })), { admit: false, reason: 'listed_locked' }, 'refund_hold'),
    v('atom_revoked_by_delta', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', ticket_atom_id: ATOM_REVOKED })), { admit: false, reason: 'atom_revoked' }, 'voided'),
    v('delta_not_yet_synced_added_atom_absent', mint(p2.privateKey, ctx({ key_id: K2, algorithm: 'ES256', ticket_atom_id: ATOM_ADDED, credential_version: 0 })), { admit: false, reason: 'atom_absent' }, 'wrong_session', { last_synced_seq: 1 }),
    v('manifest_other_session', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', session_id: OTHER_SESSION })), { admit: false, reason: 'manifest_other_session' }, null, { bound_session: OTHER_SESSION }),
    v('manifest_expired', mint(p1.privateKey, ctx({ key_id: K1, algorithm: 'ES256', exp: NOW + 10000 })), { admit: false, reason: 'manifest_expired' }, null, { now_seconds: NOW + 7201 }),
    v('malformed_token', 'not.a.token', { admit: false, reason: 'malformed_token' }, null),
  ];
  const header = { manifest_id: MANIFEST_ID, manifest_version: 1, session_id: SESSION, not_after: iso(NOW + 7200), manifest_digest: 'd1d1d1d1'.repeat(8) };
  const sig = Buffer.from(signEs256Raw(p1.privateKey, canonicalDoorManifestSignedBytes(header))).toString('base64');
  return {
    contract: 'SCANNER-CONTRACT-v1',
    generated_by: 'tests/scanner-contract.test.ts (SCANNER_FIXTURES_WRITE=1); private keys generated in-process and discarded',
    m1_wire, m2_wire, tokens,
    door_manifest: {
      artifact: { manifest: { ...header, opened_at: iso(NOW - 600), max_delta_seq: 2, entries: (m2_wire as { entries: unknown[] }).entries, deltas: (m2_wire as { deltas: unknown[] }).deltas }, signature: { key_id: K1, algorithm: 'ES256', encoding: 'raw-r-s', value: sig } },
      expected: { ok: true, keyId: K1 },
      tampered_digest_expected: { ok: false, reason: 'signature_invalid' },
    },
  };
}

describe('6. golden fixtures (tests/fixtures/scanner-contract-v1.json)', () => {
  // WRITE mode: build once, persist, and verify THAT object (never a stale file).
  const built: FixtureFile | null = WRITE ? buildFixtures() : null;
  if (WRITE && built) {
    it('writes the fixture file from the reference implementation', () => {
      mkdirSync(resolve(__dirname, 'fixtures'), { recursive: true });
      writeFileSync(FIXTURE_PATH, JSON.stringify(built, null, 2) + '\n');
      expect(existsSync(FIXTURE_PATH)).toBe(true);
    });
  }
  const fx: FixtureFile = built ?? (existsSync(FIXTURE_PATH) ? JSON.parse(readFileSync(FIXTURE_PATH, 'utf8')) : buildFixtures());

  it('is the v1 contract and carries no private material', () => {
    expect(fx.contract).toBe('SCANNER-CONTRACT-v1');
    expect(JSON.stringify(fx)).not.toMatch(/PRIVATE KEY/);
  });

  it('every token vector produces exactly its expected outcome and door reason', () => {
    const m1 = m1FromWire(fx.m1_wire)!;
    expect(m1).not.toBeNull();
    for (const t of fx.tokens) {
      const m2r = m2FromWire(fx.m2_wire);
      expect(m2r.ok).toBe(true);
      const c: OfflineVerifyContext = { m1, m2: m2r.ok ? m2r.m2 : null, lastSyncedSeq: t.last_synced_seq, boundSessionId: t.bound_session, nowSeconds: t.now_seconds, admittedSet: new Set(), verify: verifyNode };
      const result = verifyOfflineWire(t.wire, c);
      expect(result, t.name).toEqual(t.expected);
      if (!result.admit) {
        const tok = decodeOfflineToken(t.wire);
        const applied = tok && m2r.ok ? (applyM2(m2r.m2, t.last_synced_seq)[tok.atomId] ?? null) : null;
        expect(toDoorReason(result.reason, applied), t.name).toBe(t.door_reason);
      }
    }
  });

  it('first-in-wins: an admitted vector is refused already_admitted once the scanner records it', () => {
    const m1 = m1FromWire(fx.m1_wire)!;
    const m2r = m2FromWire(fx.m2_wire);
    const admitted = new Set<string>();
    const c: OfflineVerifyContext = { m1, m2: m2r.ok ? m2r.m2 : null, lastSyncedSeq: 2, boundSessionId: SESSION, nowSeconds: NOW, admittedSet: admitted, verify: verifyNode };
    const first = verifyOfflineWire(fx.tokens[0].wire, c);
    expect(first.admit).toBe(true);
    if (first.admit) admitted.add(first.atomId);
    expect(verifyOfflineWire(fx.tokens[0].wire, c)).toEqual({ admit: false, reason: 'already_admitted' });
  });

  it('the door-manifest artifact verifies under DOOR-MANIFEST-SIG-v1 and a tampered digest does not', () => {
    const m1 = m1FromWire(fx.m1_wire)!;
    expect(verifyDoorManifestSignature(fx.door_manifest.artifact, m1, verifyNode, NOW)).toEqual(fx.door_manifest.expected);
    const tampered = JSON.parse(JSON.stringify(fx.door_manifest.artifact)) as { manifest: Record<string, unknown> };
    tampered.manifest.manifest_digest = 'ffffffff'.repeat(8);
    expect(verifyDoorManifestSignature(tampered, m1, verifyNode, NOW)).toEqual(fx.door_manifest.tampered_digest_expected);
  });
});
