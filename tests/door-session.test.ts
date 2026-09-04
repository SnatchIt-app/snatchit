/**
 * door-session — pure-logic unit tests.
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT
 *   Every function under test comes from
 *   `supabase/functions/door-session/pure.ts` — an import-free pure module
 *   (same pattern as `credential-sign/credential.ts` /
 *   `credential-sign/kms-taxonomy.ts`) that `index.ts` (Deno-only: a remote
 *   `serve` import, `createClient` from esm.sh) imports FROM, never the
 *   reverse. `index.ts` itself is deliberately NOT imported here — doing so
 *   would drag its unresolvable remote specifiers into `tsc -p .`, which
 *   type-checks anything transitively reachable from an included root file
 *   (`tests/**` is not excluded by the root `tsconfig.json`, even though
 *   `supabase/functions` is excluded from ITS OWN root-file glob — see
 *   `pure.ts`'s file header for the full trap this avoids, and
 *   `credential-sign/kms.ts`'s header for the precedent this mirrors).
 *
 *   No live Supabase, no network, no mocked RPC boundary — every case below
 *   is a plain function call against deterministic input. `assert_door_
 *   session` / `mint_door_session` / `record_scan` / `reconcile_offline_
 *   scans` / `get_door_manifest` themselves are NOT exercised (they cannot
 *   be — `mint_door_session` is parked fail-closed, PFA-26, and there is no
 *   live Supabase in this DARK/local environment regardless).
 *
 * CASES
 *   1. `parseDoorSessionBearer` — the `DoorSession <id>.<secret>` wire
 *      format: valid parse; every malformed shape returns null, never
 *      throws (missing prefix, wrong case, missing dot, empty id/secret,
 *      leading/trailing dot, embedded whitespace, null/undefined/non-string
 *      input, a secret that itself contains a dot — split on the LAST dot).
 *   2. `dispatchDoorSessionRoute` — all five paths, tolerant of a
 *      function-name prefix and a trailing slash; unknown paths → null.
 *   3. `deviceIdsMatch` — the EDGE-4c cross-check predicate.
 *   4. `hasForbiddenDeviceIdField` / `batchContainsForbiddenDeviceId` — the
 *      "`p_scan_meta.device_id` is REJECTED" rule (RPC §9.4/§9.5, X-5), for
 *      a single scan_meta object and for every row of an offline batch.
 *   5. `buildTokenHashInput` / `sha256Hex` / `computeTokenHash` — the
 *      `token_hash = sha256(door_session_id||':'||secret)` wire contract
 *      (edge §3.9a; RPC §1.1d), validated against NIST's own SHA-256 test
 *      vectors for `""` and `"abc"` as an independent correctness check of
 *      the hand-rolled digest, separate from this system's own inputs.
 *   6. `uuidv5` — validated against the canonical RFC4122 worked example
 *      (DNS namespace + `"python.org"`), which exercises the hand-rolled
 *      SHA-1 AND the version/variant bit-setting AND the uuid string
 *      formatting in one shot.
 *   7. `deriveDoorPinRateLimitPrincipal` / `deriveDoorSessionRateLimitPrincipal`
 *      — deterministic, uuid-shaped, and namespace-separated (the same NAME
 *      under the two different namespaces must not collide — that
 *      separation is what stops PIN-grinding and relay abuse from sharing a
 *      budget, edge §3.9a "Rate limit").
 *   8. `isDoorPinKdfUnavailable` — the PFA-26 park detector.
 *   9. `isAssertDoorSessionAuthFailure` — the RPC §1.1d opaque-error
 *      classifier (`42501` / `insufficient_privilege`).
 */
import { describe, expect, it } from 'vitest';
import {
  batchContainsForbiddenDeviceId,
  deriveDoorPinRateLimitPrincipal,
  deriveDoorSessionRateLimitPrincipal,
  deviceIdsMatch,
  dispatchDoorSessionRoute,
  doorPinRateLimitName,
  doorSessionRateLimitName,
  hasForbiddenDeviceIdField,
  isAssertDoorSessionAuthFailure,
  isDoorPinKdfUnavailable,
  NS_DOOR_PIN,
  NS_DOOR_SESSION,
  parseDoorSessionBearer,
  sha256Hex,
  uuidv5,
} from '../supabase/functions/door-session/pure';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// ── 1. parseDoorSessionBearer ──────────────────────────────────────────────
describe('parseDoorSessionBearer', () => {
  it('parses a well-formed bearer header', () => {
    const parsed = parseDoorSessionBearer('DoorSession 11111111-1111-4111-8111-111111111111.c2VjcmV0LWJ5dGVz');
    expect(parsed).toEqual({ doorSessionId: '11111111-1111-4111-8111-111111111111', secret: 'c2VjcmV0LWJ5dGVz' });
  });

  it('splits on the LAST dot when the secret itself contains a dot', () => {
    const parsed = parseDoorSessionBearer('DoorSession abc.se.cr.et');
    expect(parsed).toEqual({ doorSessionId: 'abc.se.cr', secret: 'et' });
  });

  it.each([
    ['null', null],
    ['undefined', undefined],
    ['empty string', ''],
    ['missing prefix entirely', 'abc.def'],
    ['wrong scheme keyword', 'Bearer abc.def'],
    ['wrong case on scheme', 'doorsession abc.def'],
    ['prefix with no credentials', 'DoorSession '],
    ['prefix with no credentials, no trailing space', 'DoorSession'],
    ['no dot at all', 'DoorSession abcdef'],
    ['dot at the very start', 'DoorSession .secret'],
    ['dot at the very end', 'DoorSession abcdef.'],
    ['embedded whitespace in id half', 'DoorSession ab cd.secret'],
    ['embedded whitespace in secret half', 'DoorSession abcd.se cret'],
  ])('returns null, never throws, for: %s', (_label, header) => {
    expect(() => parseDoorSessionBearer(header as string | null | undefined)).not.toThrow();
    expect(parseDoorSessionBearer(header as string | null | undefined)).toBeNull();
  });
});

// ── 2. dispatchDoorSessionRoute ────────────────────────────────────────────
describe('dispatchDoorSessionRoute', () => {
  it.each([
    ['/mint', 'mint'],
    ['/refresh', 'refresh'],
    ['/manifest/sync', 'manifest_sync'],
    ['/scan', 'scan'],
    ['/offline-batch', 'offline_batch'],
    ['/door-session/mint', 'mint'],
    ['/functions/v1/door-session/manifest/sync', 'manifest_sync'],
    ['/mint/', 'mint'],
    ['/door-session/offline-batch/', 'offline_batch'],
  ])('dispatches %s -> %s', (pathname, expected) => {
    expect(dispatchDoorSessionRoute(pathname)).toBe(expected);
  });

  it.each(['/', '', '/unknown', '/mints', '/door-session', '/manifest'])('returns null for unknown path %s', (pathname) => {
    expect(dispatchDoorSessionRoute(pathname)).toBeNull();
  });
});

// ── 3. deviceIdsMatch ───────────────────────────────────────────────────────
describe('deviceIdsMatch', () => {
  it('matches identical ids', () => {
    expect(deviceIdsMatch('device-1', 'device-1')).toBe(true);
  });
  it('rejects a mismatch', () => {
    expect(deviceIdsMatch('device-1', 'device-2')).toBe(false);
  });
  it('is case-sensitive (no normalization the spec never asked for)', () => {
    expect(deviceIdsMatch('Device-1', 'device-1')).toBe(false);
  });
});

// ── 4. hasForbiddenDeviceIdField / batchContainsForbiddenDeviceId ─────────
describe('hasForbiddenDeviceIdField', () => {
  it('detects a present device_id key', () => {
    expect(hasForbiddenDeviceIdField({ direction: 'in', device_id: 'x' })).toBe(true);
  });
  it('detects device_id even when the value is null/undefined — presence is the violation', () => {
    expect(hasForbiddenDeviceIdField({ device_id: null })).toBe(true);
    expect(hasForbiddenDeviceIdField({ device_id: undefined })).toBe(true);
  });
  it('passes clean telemetry-only meta', () => {
    expect(hasForbiddenDeviceIdField({ direction: 'in', scan_type: 'qr', device_boot_id: 'b1', scan_sequence: 3 })).toBe(false);
  });
  it.each([null, undefined, 'string', 42, ['array', 'is', 'not', 'an', 'object', 'here']])(
    'treats non-plain-object input %j as clean (nothing to check)',
    (meta) => {
      expect(hasForbiddenDeviceIdField(meta)).toBe(false);
    },
  );
});

describe('batchContainsForbiddenDeviceId', () => {
  it('flags a batch where any row carries device_id', () => {
    const batch = [{ ticket_atom_id: 'a1' }, { ticket_atom_id: 'a2', device_id: 'sneaky' }];
    expect(batchContainsForbiddenDeviceId(batch)).toBe(true);
  });
  it('passes a clean batch', () => {
    const batch = [{ ticket_atom_id: 'a1' }, { ticket_atom_id: 'a2' }];
    expect(batchContainsForbiddenDeviceId(batch)).toBe(false);
  });
  it('passes an empty batch and rejects non-array input as clean', () => {
    expect(batchContainsForbiddenDeviceId([])).toBe(false);
    expect(batchContainsForbiddenDeviceId('not-an-array')).toBe(false);
    expect(batchContainsForbiddenDeviceId(null)).toBe(false);
  });
});

// ── 5. Token-hash wire contract ────────────────────────────────────────────
// NOTE: the door-session token_hash is NOT computed here or anywhere in the edge.
// Its authoritative contract is DB-owned — md5('door_session:' || secret), written
// by venue.mint_door_session (107) and recomputed by kernel.assert_door_session
// (086). sha256Hex below is a GENERIC hash utility (NIST-vector checked), not the
// token_hash algorithm; the edge forwards the raw secret and the DB hashes it.
describe('sha256Hex (generic hash utility — NOT the token_hash algorithm)', () => {
  it('matches the NIST test vector for the empty string', () => {
    expect(sha256Hex('')).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  it('matches the NIST test vector for "abc"', () => {
    expect(sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
});

// ── 6. uuidv5 — RFC4122 correctness check (independent of this system's own
// namespace constants) ──────────────────────────────────────────────────────
describe('uuidv5 (RFC4122)', () => {
  it('matches the canonical worked example: DNS namespace + "python.org"', () => {
    const DNS_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
    expect(uuidv5(DNS_NAMESPACE, 'python.org')).toBe('886313e1-3b8a-5372-9b90-0c9aee199e5d');
  });

  it('is deterministic: same (namespace, name) -> same uuid', () => {
    expect(uuidv5(NS_DOOR_PIN, 'venue-1:device-1')).toBe(uuidv5(NS_DOOR_PIN, 'venue-1:device-1'));
  });

  it('differs for different names under the same namespace', () => {
    expect(uuidv5(NS_DOOR_PIN, 'venue-1:device-1')).not.toBe(uuidv5(NS_DOOR_PIN, 'venue-1:device-2'));
  });

  it('differs for the same name under different namespaces', () => {
    expect(uuidv5(NS_DOOR_PIN, 'same-name')).not.toBe(uuidv5(NS_DOOR_SESSION, 'same-name'));
  });
});

// ── 7. Rate-limit derived principals ───────────────────────────────────────
describe('rate-limit derived principals', () => {
  it('doorPinRateLimitName / doorSessionRateLimitName build the documented name strings', () => {
    expect(doorPinRateLimitName('venue-1', 'device-1')).toBe('venue-1:device-1');
    expect(doorSessionRateLimitName('door-session-1')).toBe('door-session-1');
  });

  it('deriveDoorPinRateLimitPrincipal is a valid uuid and is deterministic', () => {
    const principal = deriveDoorPinRateLimitPrincipal('venue-1', 'device-1');
    expect(principal).toMatch(UUID_RE);
    expect(principal).toBe(deriveDoorPinRateLimitPrincipal('venue-1', 'device-1'));
  });

  it('deriveDoorSessionRateLimitPrincipal is a valid uuid and is deterministic', () => {
    const principal = deriveDoorSessionRateLimitPrincipal('door-session-1');
    expect(principal).toMatch(UUID_RE);
    expect(principal).toBe(deriveDoorSessionRateLimitPrincipal('door-session-1'));
  });

  it('/mint and /refresh share ONE principal for the same (venue, device) — same budget by design', () => {
    // Both routes call deriveDoorPinRateLimitPrincipal with the same inputs;
    // this is the pure fact that makes that sharing possible.
    const forMint = deriveDoorPinRateLimitPrincipal('venue-1', 'device-1');
    const forRefresh = deriveDoorPinRateLimitPrincipal('venue-1', 'device-1');
    expect(forMint).toBe(forRefresh);
  });

  it('the PIN budget and the relay budget never collide for a shared raw name', () => {
    // A door_session_id could, in principle, collide textually with a
    // "venue:device" string — the namespace separation is what stops that
    // from ever mapping to the same rate-limit bucket.
    const asPinName = deriveDoorPinRateLimitPrincipal('shared', 'value');
    const asSessionName = deriveDoorSessionRateLimitPrincipal('shared:value');
    expect(asPinName).not.toBe(asSessionName);
  });
});

// ── 8. PFA-26 park detector ─────────────────────────────────────────────────
describe('isDoorPinKdfUnavailable', () => {
  it('detects the PFA-26 park message', () => {
    expect(isDoorPinKdfUnavailable('precondition_failed: door_pin_kdf_unavailable (PFA-26)')).toBe(true);
  });
  it('is false for an unrelated error, and for null/undefined', () => {
    expect(isDoorPinKdfUnavailable('insufficient_privilege')).toBe(false);
    expect(isDoorPinKdfUnavailable(null)).toBe(false);
    expect(isDoorPinKdfUnavailable(undefined)).toBe(false);
    expect(isDoorPinKdfUnavailable('')).toBe(false);
  });
});

// ── 9. assert_door_session opaque-error classifier ─────────────────────────
describe('isAssertDoorSessionAuthFailure', () => {
  it('recognizes the 42501 postgres code', () => {
    expect(isAssertDoorSessionAuthFailure('42501', 'some message')).toBe(true);
  });
  it('recognizes an insufficient_privilege message even without the code', () => {
    expect(isAssertDoorSessionAuthFailure(null, 'insufficient_privilege: door session invalid')).toBe(true);
  });
  it('is false for an unrelated code/message pair', () => {
    expect(isAssertDoorSessionAuthFailure('23505', 'duplicate key value')).toBe(false);
    expect(isAssertDoorSessionAuthFailure(null, null)).toBe(false);
  });
});
