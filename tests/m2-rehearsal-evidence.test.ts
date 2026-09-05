/**
 * M2 rehearsal evidence — REAL `venue.get_door_manifest` output (captured from
 * the local rehearsal database by scripts/rehearsal_m2_evidence.sh into
 * tests/fixtures/m2-rehearsal-evidence.json; the capture transaction is rolled
 * back) driven through the two consumer paths:
 *   • the `door-manifest` edge's classifier (pure.ts)        — open / closed / malformed
 *   • the SCANNER-CONTRACT-v1 adapter + predicate            — m2FromWire / offlineVerify
 * Scenarios: open (full snapshot), incremental deltas, closed, expired,
 * wrong-session (bound-session mismatch + unknown session), unauthorized
 * callers (buyer, service_role door relay), malformed headers (mutated copies
 * of the real output). M1 and the ticket credential are synthetic (a throwaway
 * key generated in-process) but keyed to the REAL signing_key_id / session /
 * atoms / credential_version in the captured manifest.
 */
import { createPublicKey, generateKeyPairSync, sign as nodeSign, verify as nodeVerify } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { buildCanonicalPayload, encodeToken } from '../supabase/functions/credential-sign/credential';
import { classifyDoorManifestResponse } from '../supabase/functions/door-manifest/pure';
import { classifyMachineRpcError } from '../supabase/functions/door-session/pure';
import { m1FromWire, m2FromWire, verifyOfflineWire, type OfflineVerifyContext, type VerifyPrimitive } from '../supabase/functions/_shared/offline-verify';

const PATH = resolve(__dirname, 'fixtures/m2-rehearsal-evidence.json');
const ev: Record<string, any> | null = existsSync(PATH) ? JSON.parse(readFileSync(PATH, 'utf8')) : null;

const verifyNode: VerifyPrimitive = (pk, m, s, alg) => {
  const key = createPublicKey({ key: Buffer.from(pk, 'base64'), format: 'der', type: 'spki' });
  return alg === 'ES256' ? nodeVerify('sha256', Buffer.from(m), { key, dsaEncoding: 'ieee-p1363' }, Buffer.from(s)) : false;
};

describe('M2 rehearsal evidence (real RPC output)', () => {
  it('evidence file present (run scripts/rehearsal_m2_evidence.sh against the rehearsal DB to refresh)', () => {
    expect(ev, 'tests/fixtures/m2-rehearsal-evidence.json missing').not.toBeNull();
  });
  if (!ev) return;

  const stored = ev.stored_header;
  const toSec = (iso: string) => Math.floor(Date.parse(iso) / 1000);

  it('open (full snapshot): classifier ⇒ open; m2FromWire ⇒ ok with the STORED session_id / not_after; 3 atoms in the base', () => {
    expect(classifyDoorManifestResponse(ev.open_full).kind).toBe('open');
    const r = m2FromWire(ev.open_full);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.m2.session_id).toBe(ev.ids.session_id);
    expect(r.m2.session_id).toBe(stored.session_id);
    expect(r.m2.not_after).toBe(toSec(stored.not_after));
    expect(Number.isFinite(Date.parse(ev.open_full.opened_at))).toBe(true);
    expect(r.manifestDigest).toBe(stored.manifest_digest);
    expect(Object.keys(r.m2.base)).toHaveLength(3);
    for (const e of Object.values(r.m2.base)) {
      expect(e.signing_key_id).toBe(ev.ids.signing_key_id);
      expect(e.ticket_state).toBe('active');
      expect(e.resale_state).toBe('none');
    }
    expect(JSON.stringify(ev.open_full)).not.toContain('public_key');
  });

  it('incremental: since 0 carries the revoke delta and is applied; since 1 carries none', () => {
    const r0 = m2FromWire(ev.open_incremental_since_0);
    const r1 = m2FromWire(ev.open_incremental_since_1);
    expect(r0.ok && r1.ok).toBe(true);
    if (!r0.ok || !r1.ok) return;
    expect(r0.m2.deltas).toHaveLength(1);
    expect(r0.m2.deltas[0].op).toBe('revoke');
    expect(r0.maxDeltaSeq).toBe(1);
    expect(r1.m2.deltas).toHaveLength(0);
    expect(Object.keys(r1.m2.base)).toHaveLength(3);
  });

  it('closed and expired: classifier ⇒ closed; m2FromWire ⇒ no_open_manifest; the expired row is untouched in the DB', () => {
    for (const k of ['closed', 'expired']) {
      expect(classifyDoorManifestResponse(ev[k]).kind, k).toBe('closed');
      expect(m2FromWire(ev[k]), k).toEqual({ ok: false, reason: 'no_open_manifest' });
      expect(ev[k].open).toBe(false);
      expect(ev[k].status).toBe('no_open_episode');
    }
    expect(classifyDoorManifestResponse(ev.reopened_v2_fresh).kind).toBe('open');
    expect(ev.reopened_v2_fresh.manifest_version).toBe(2);
    expect(ev.expired_stored_row.status).toBe('open');
    expect(Date.parse(ev.expired_stored_row.not_after)).toBeLessThan(Date.parse(ev.expired_stored_row.now));
  });

  it('unauthorized callers never receive a manifest (real error text)', () => {
    expect(String(ev.unauthorized_buyer)).toMatch(/42501.*insufficient_privilege/);
    expect(String(ev.unauthorized_service_role_door_relay)).toMatch(/42501/);
    expect(String(ev.wrong_session_unknown)).toMatch(/42501/);
  });

  it('malformed headers (mutated copies of the real output) ⇒ edge malformed (never KMS) and adapter manifest_header_incomplete / manifest_malformed', () => {
    const legacyShape = { ...ev.open_full };
    delete legacyShape.open; delete legacyShape.session_id; delete legacyShape.not_after; delete legacyShape.opened_at;
    expect(classifyDoorManifestResponse(legacyShape)).toEqual({ kind: 'malformed', reason: 'missing_open' });
    expect(m2FromWire(legacyShape)).toEqual({ ok: false, reason: 'manifest_header_incomplete' });
    expect(classifyDoorManifestResponse({ ...ev.open_full, not_after: 'never' })).toEqual({ kind: 'malformed', reason: 'invalid:not_after' });
    expect(m2FromWire({ ...ev.open_full, session_id: 'x' })).toEqual({ ok: false, reason: 'manifest_header_incomplete' });
    expect(m2FromWire({ ...ev.open_full, entries: [{ ticket_atom_id: ev.open_full.entries[0].ticket_atom_id }] })).toEqual({ ok: false, reason: 'manifest_malformed' });
  });

  it('end-to-end: a credential for a real atom admits against the real manifest; wrong bound session / expiry refuse at the authority gate', () => {
    const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const m1 = m1FromWire([{ key_id: ev.ids.signing_key_id, scope: 'per_event', event_id: ev.ids.event_id, venue_id: null,
      public_key: publicKey.export({ type: 'spki', format: 'pem' }) as string, algorithm: 'ES256', status: 'active', not_before: '2026-01-01T00:00:00Z', not_after: null }])!;
    const r = m2FromWire(ev.open_incremental_since_0);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const live = Object.entries(r.m2.base).find(([id]) => !r.m2.deltas.some((d) => d.atom === id))!;
    const revoked = r.m2.deltas[0].atom;
    const now = toSec(stored.opened_at) + 60;
    const mint = (atom: string, ver: number) => {
      const c = buildCanonicalPayload({ ticket_atom_id: atom, session_id: ev.ids.session_id, credential_version: ver, key_id: ev.ids.signing_key_id, algorithm: 'ES256', issued_at: now - 30, exp: now + 3600 });
      return encodeToken(c.headerB64, c.payloadB64, new Uint8Array(nodeSign('sha256', Buffer.from(c.signedBytes), { key: privateKey, dsaEncoding: 'ieee-p1363' })));
    };
    const ctx = (over: Partial<OfflineVerifyContext> = {}): OfflineVerifyContext =>
      ({ m1, m2: r.m2, lastSyncedSeq: 1, boundSessionId: ev.ids.session_id, nowSeconds: now, admittedSet: new Set(), verify: verifyNode, ...over });
    expect(verifyOfflineWire(mint(live[0], live[1].credential_version), ctx())).toEqual({ admit: true, atomId: live[0] });
    expect(verifyOfflineWire(mint(revoked, r.m2.base[revoked].credential_version), ctx())).toEqual({ admit: false, reason: 'atom_revoked' });
    expect(verifyOfflineWire(mint(live[0], live[1].credential_version + 1), ctx())).toEqual({ admit: false, reason: 'stale_version' });
    expect(verifyOfflineWire(mint(live[0], live[1].credential_version), ctx({ boundSessionId: '5e55e55e-0000-4000-8000-0000000000ff' }))).toEqual({ admit: false, reason: 'wrong_session' });
    const other = { ...r.m2, session_id: '5e55e55e-0000-4000-8000-0000000000ff' };
    expect(verifyOfflineWire(mint(live[0], live[1].credential_version), ctx({ m2: other, boundSessionId: '5e55e55e-0000-4000-8000-0000000000ff' }))).toEqual({ admit: false, reason: 'wrong_session' });
    expect(verifyOfflineWire(mint(live[0], live[1].credential_version), ctx({ nowSeconds: r.m2.not_after + 1 }))).toEqual({ admit: false, reason: 'expired' });
    const longLived = (() => {
      const c = buildCanonicalPayload({ ticket_atom_id: live[0], session_id: ev.ids.session_id, credential_version: live[1].credential_version, key_id: ev.ids.signing_key_id, algorithm: 'ES256', issued_at: now - 30, exp: r.m2.not_after + 7200 });
      return encodeToken(c.headerB64, c.payloadB64, new Uint8Array(nodeSign('sha256', Buffer.from(c.signedBytes), { key: privateKey, dsaEncoding: 'ieee-p1363' })));
    })();
    expect(verifyOfflineWire(longLived, ctx({ nowSeconds: r.m2.not_after + 1 }))).toEqual({ admit: false, reason: 'manifest_expired' });
  });

  // ── 113: the service_role MACHINE path (venue.get_door_manifest_door) — what
  // door-session /manifest/sync now relays. Real RPC output, same consumers. ──
  describe('machine path (get_door_manifest_door, migration 113 — P1-M2-DOOR-AUTHZ)', () => {
    it('a valid bound device gets the manifest for its BOUND session — byte-identical to the staff read; passes the classifier and m2FromWire', () => {
      expect(ev.door_full).toEqual(ev.open_full);
      expect(classifyDoorManifestResponse(ev.door_full).kind).toBe('open');
      const r = m2FromWire(ev.door_full);
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      expect(r.m2.session_id).toBe(ev.ids.session_id);
      expect(r.m2.not_after).toBe(toSec(stored.not_after));
      expect(Object.keys(r.m2.base)).toHaveLength(3);
    });
    it('incremental sync through the machine path: since 0 ⇒ the revoke delta; since 1 ⇒ none; null ⇒ full', () => {
      expect(ev.door_incremental_since_0).toEqual(ev.open_incremental_since_0);
      expect(ev.door_incremental_since_1).toEqual(ev.open_incremental_since_1);
      const r0 = m2FromWire(ev.door_incremental_since_0);
      const rn = m2FromWire(ev.door_incremental_since_null);
      expect(r0.ok && rn.ok).toBe(true);
      if (!r0.ok || !rn.ok) return;
      expect(r0.m2.deltas).toHaveLength(1);
      expect(r0.m2.deltas[0].op).toBe('revoke');
      expect(rn.maxDeltaSeq).toBe(1);
      expect(m2FromWire(ev.door_incremental_since_1)).toMatchObject({ ok: true, maxDeltaSeq: 1 });
    });
    it('wrong token / device / session, unknown id, and service_role WITHOUT credentials are all the ONE opaque door_session_invalid (42501) — the machine never picks scope', () => {
      for (const k of ['door_wrong_token', 'door_wrong_device', 'door_wrong_session', 'door_unknown_door_session_id', 'door_service_role_no_credentials']) {
        expect(ev[k], k).toBe('42501 door_session_invalid');
        expect(classifyMachineRpcError('42501', ev[k])).toBe('door_session_invalid');
      }
    });
    it('revoked (between the edge admit check and the machine RPC) and expired door sessions are refused by the RPC itself', () => {
      expect(ev.door_admit_check_before_revoke).toEqual({ device_id: ev.ids.device_id, event_session_id: ev.ids.session_id });
      expect(ev.door_revoked_between_checks).toBe('42501 door_session_invalid');
      expect(ev.door_expired_door_session).toBe('42501 door_session_invalid');
    });
    it('direct anon / authenticated calls (even with VALID door credentials) and direct core calls are permission errors — classified as deployment defects (500), never as auth', () => {
      expect(ev.door_anon_direct_valid_credentials).toMatch(/^42501 permission denied/);
      expect(ev.door_authenticated_direct_valid_credentials).toBe('42501 permission denied for function get_door_manifest_door');
      expect(ev.door_core_direct_service_role).toBe('42501 permission denied for function _get_door_manifest_core');
      expect(classifyMachineRpcError('42501', ev.door_authenticated_direct_valid_credentials)).toBe('other');
    });
    it('closed and expired manifests through the machine path ⇒ closed / no_open_manifest', () => {
      for (const k of ['door_closed', 'door_expired']) {
        expect(ev[k], k).toEqual({ open: false, status: 'no_open_episode', entries: [], deltas: [] });
        expect(classifyDoorManifestResponse(ev[k]).kind, k).toBe('closed');
        expect(m2FromWire(ev[k]), k).toEqual({ ok: false, reason: 'no_open_manifest' });
      }
    });
    it('the staff path is unchanged (authorized scanner reads; buyer and service_role refused)', () => {
      expect(classifyDoorManifestResponse(ev.open_full).kind).toBe('open');
      expect(String(ev.unauthorized_buyer)).toBe('42501 insufficient_privilege');
      expect(String(ev.unauthorized_service_role_door_relay)).toBe('42501 permission denied for function get_door_manifest');
    });
    it('the committed fixture carries NO bearer secret: no secret/token keys, no token_hash, no "door_session:" preimage; ids hold only selectors', () => {
      const text = readFileSync(PATH, 'utf8');
      expect(text).not.toMatch(/"secret"|"p_session_token"|"token_hash"|door_session:/);
      expect(Object.keys(ev.ids).sort()).toEqual(['device_id', 'door_session_id', 'event_id', 'manifest_id', 'session_id', 'signing_key_id', 'venue_id']);
    });
  });
});
