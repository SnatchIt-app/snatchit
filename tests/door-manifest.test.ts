/**
 * door-manifest — pure classification (P1-M2-HEADER follow-up).
 * Proves: open ⇒ 'open'; a legitimate no-episode result (either spelling) ⇒
 * 'closed'; the 086 open-episode shape (no open/session_id/not_after) and
 * every other deviation ⇒ 'malformed' with a stable reason — so the edge can
 * fail closed BEFORE any KMS call. Also: the signed bytes are byte-identical
 * to the SCANNER-CONTRACT-v1 verifier's canonical bytes.
 */
import { describe, expect, it } from 'vitest';
import { buildSignatureEnvelope, canonicalManifestDigestBytes, classifyDoorManifestResponse, classifyManifestSigningContext } from '../supabase/functions/door-manifest/pure';
import { canonicalDoorManifestSignedBytes } from '../supabase/functions/_shared/offline-verify';

const SESSION = '5e55e55e-0000-4000-8000-000000000001';
const MID = 'aa00aa00-0000-4000-8000-000000000001';
const open = (over: Record<string, unknown> = {}) => ({
  open: true, status: 'ok', manifest_id: MID, manifest_version: 1, session_id: SESSION,
  opened_at: '2027-01-15T07:50:00+00:00', not_after: '2027-01-15T19:50:00.123456+00:00',
  manifest_digest: 'd1'.repeat(32), max_delta_seq: 0, entries: [], deltas: [], ...over,
});

describe('classifyDoorManifestResponse', () => {
  it('a well-formed open episode ⇒ open', () => {
    expect(classifyDoorManifestResponse(open()).kind).toBe('open');
  });
  it('the legitimate closed results ⇒ closed (both status spellings; with or without empty arrays)', () => {
    expect(classifyDoorManifestResponse({ open: false, status: 'no_open_episode', entries: [], deltas: [] }).kind).toBe('closed');
    expect(classifyDoorManifestResponse({ open: false, status: 'no_open_manifest', entries: [], deltas: [] }).kind).toBe('closed');
    expect(classifyDoorManifestResponse({ status: 'no_open_episode' }).kind).toBe('closed'); // legacy 086 no-episode shape
    expect(classifyDoorManifestResponse({ open: false }).kind).toBe('closed');
  });
  it('the 086 OPEN-episode shape (status ok, no open/session_id/not_after) ⇒ malformed:missing_open — never closed, never signed', () => {
    const legacy = open();
    delete (legacy as Record<string, unknown>).open;
    delete (legacy as Record<string, unknown>).session_id;
    delete (legacy as Record<string, unknown>).not_after;
    delete (legacy as Record<string, unknown>).opened_at;
    expect(classifyDoorManifestResponse(legacy)).toEqual({ kind: 'malformed', reason: 'missing_open' });
  });
  it('every header deviation ⇒ malformed with a stable reason', () => {
    expect(classifyDoorManifestResponse(null)).toEqual({ kind: 'malformed', reason: 'not_an_object' });
    expect(classifyDoorManifestResponse([])).toEqual({ kind: 'malformed', reason: 'not_an_object' });
    expect(classifyDoorManifestResponse(open({ open: 'true' }))).toEqual({ kind: 'malformed', reason: 'open_not_boolean' });
    expect(classifyDoorManifestResponse(open({ manifest_id: 'x' }))).toEqual({ kind: 'malformed', reason: 'invalid:manifest_id' });
    expect(classifyDoorManifestResponse(open({ manifest_version: 0 }))).toEqual({ kind: 'malformed', reason: 'invalid:manifest_version' });
    expect(classifyDoorManifestResponse(open({ session_id: undefined }))).toEqual({ kind: 'malformed', reason: 'invalid:session_id' });
    expect(classifyDoorManifestResponse(open({ opened_at: 'yesterday' }))).toEqual({ kind: 'malformed', reason: 'invalid:opened_at' });
    expect(classifyDoorManifestResponse(open({ not_after: 42 }))).toEqual({ kind: 'malformed', reason: 'invalid:not_after' });
    expect(classifyDoorManifestResponse(open({ manifest_digest: '' }))).toEqual({ kind: 'malformed', reason: 'invalid:manifest_digest' });
    expect(classifyDoorManifestResponse(open({ max_delta_seq: -1 }))).toEqual({ kind: 'malformed', reason: 'invalid:max_delta_seq' });
    expect(classifyDoorManifestResponse(open({ entries: 'nope' }))).toEqual({ kind: 'malformed', reason: 'invalid:entries' });
    expect(classifyDoorManifestResponse(open({ deltas: {} }))).toEqual({ kind: 'malformed', reason: 'invalid:deltas' });
    expect(classifyDoorManifestResponse({ open: false, entries: 'nope' })).toEqual({ kind: 'malformed', reason: 'invalid:entries_or_deltas' });
    expect(classifyDoorManifestResponse({ status: 'ok' })).toEqual({ kind: 'malformed', reason: 'missing_open' });
  });
  it('accepts PostgreSQL timestamptz text (microseconds + offset) as the header timestamps', () => {
    expect(classifyDoorManifestResponse(open({ opened_at: '2026-09-05 22:57:12.123456+00', not_after: '2026-09-06T10:57:12.1+00:00' })).kind).toBe('open');
  });
});

describe('signed bytes parity with SCANNER-CONTRACT-v1', () => {
  it('canonicalManifestDigestBytes (edge) === canonicalDoorManifestSignedBytes (verifier), byte for byte', () => {
    const c = classifyDoorManifestResponse(open({ max_delta_seq: 3, entries: [{ x: 1 }], deltas: [{ y: 2 }] }));
    expect(c.kind).toBe('open');
    if (c.kind !== 'open') return;
    const a = canonicalManifestDigestBytes(c.manifest);
    const b = canonicalDoorManifestSignedBytes({
      manifest_id: c.manifest.manifest_id, manifest_version: c.manifest.manifest_version, session_id: c.manifest.session_id,
      not_after: c.manifest.not_after, manifest_digest: c.manifest.manifest_digest,
    });
    expect(Buffer.from(a).equals(Buffer.from(b))).toBe(true);
    expect(Buffer.from(a).toString()).not.toContain('entries');
  });
});

// ── 114: manifest-signing key identity from the canonical authority ────────
describe('classifyManifestSigningContext', () => {
  const NOW = Date.parse('2026-09-05T12:00:00Z') / 1000;
  const KEY = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b01';
  const ok = (over: Record<string, unknown> = {}) => ({
    status: 'ok', key_id: KEY, scope: 'global', kms_handle_ref: 'arn:aws:kms:us-east-1:000000000000:key/' + KEY,
    algorithm: 'ES256', public_key: '-----BEGIN PUBLIC KEY-----\nMFkw\n-----END PUBLIC KEY-----', key_status: 'active',
    not_before: '2026-09-05T11:00:00+00:00', not_after: null, ...over,
  });
  it('a well-formed active ES256 global key in window ⇒ ok with exactly the fields the edge needs', () => {
    const c = classifyManifestSigningContext(ok(), NOW);
    expect(c.kind).toBe('ok');
    if (c.kind !== 'ok') return;
    expect(Object.keys(c.context).sort()).toEqual(['algorithm', 'key_id', 'kms_handle_ref', 'not_after', 'not_before', 'public_key']);
    expect(c.context.key_id).toBe(KEY);
  });
  it('the RPC\'s own unavailable answers pass through with their stable code (no active global key etc.)', () => {
    expect(classifyManifestSigningContext({ status: 'unavailable', code: 'no_active_global_key' }, NOW)).toEqual({ kind: 'unavailable', code: 'no_active_global_key' });
    expect(classifyManifestSigningContext({ status: 'unavailable', code: 'Weird Code!' }, NOW)).toEqual({ kind: 'unavailable', code: 'unspecified' });
  });
  it('the edge re-pins what the DB decided: not ES256 / not active / outside the window ⇒ unavailable (never KMS)', () => {
    expect(classifyManifestSigningContext(ok({ algorithm: 'EdDSA' }), NOW)).toEqual({ kind: 'unavailable', code: 'algorithm_not_es256' });
    expect(classifyManifestSigningContext(ok({ key_status: 'rotating' }), NOW)).toEqual({ kind: 'unavailable', code: 'key_not_active' });
    expect(classifyManifestSigningContext(ok({ not_before: '2026-09-05T12:00:01+00:00' }), NOW)).toEqual({ kind: 'unavailable', code: 'key_window' });
    expect(classifyManifestSigningContext(ok({ not_after: '2026-09-05T12:00:00+00:00' }), NOW)).toEqual({ kind: 'unavailable', code: 'key_window' });
    expect(classifyManifestSigningContext(ok({ not_before: '2026-09-05T12:00:00+00:00' }), NOW).kind).toBe('ok');
    expect(classifyManifestSigningContext(ok({ not_after: '2026-09-05T12:00:01+00:00' }), NOW).kind).toBe('ok');
  });
  it('shape deviations ⇒ malformed with a stable code', () => {
    expect(classifyManifestSigningContext(null, NOW)).toEqual({ kind: 'malformed', code: 'not_an_object' });
    expect(classifyManifestSigningContext({ status: 'ready' }, NOW)).toEqual({ kind: 'malformed', code: 'unknown_status' });
    expect(classifyManifestSigningContext(ok({ key_id: 'x' }), NOW)).toEqual({ kind: 'malformed', code: 'invalid:key_id' });
    expect(classifyManifestSigningContext(ok({ kms_handle_ref: '' }), NOW)).toEqual({ kind: 'malformed', code: 'invalid:kms_handle_ref' });
    expect(classifyManifestSigningContext(ok({ public_key: '' }), NOW)).toEqual({ kind: 'malformed', code: 'invalid:public_key' });
    expect(classifyManifestSigningContext(ok({ not_before: 'soon' }), NOW)).toEqual({ kind: 'malformed', code: 'invalid:not_before' });
  });
});

describe('buildSignatureEnvelope', () => {
  it('is EXACTLY { value, algorithm: ES256, key_id } — a handle or public key can never ride along', () => {
    const env = buildSignatureEnvelope('AAAA', '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b01');
    expect(env).toEqual({ value: 'AAAA', algorithm: 'ES256', key_id: '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b01' });
    expect(Object.keys(env)).toEqual(['value', 'algorithm', 'key_id']);
  });
});
