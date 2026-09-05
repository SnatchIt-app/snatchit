# SCANNER-CONTRACT-v1 — the scanner / mobile verifier boundary

**Status:** repository side IMPLEMENTED + TESTED (reference decoder, adapters, manifest-signature verifier, golden fixtures);
**the mobile/scanner implementation is NOT in this repository and is NOT claimed implemented.** Local/rehearsal only: no AWS, no
Supabase production call, no migration applied, no deployment, no secret, no activation. Production unchanged.

Normative inputs (unchanged by this document): `OFFLINE-VERIFY-v1` (`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §5.4.3, mirrored
door §9.2), edge §5.4.2 (M1), door §7.5/§7.5a + RPC §20.6.1 (M2), edge §3.9b (`door-manifest`), `PRODUCTION_SIGNING_KMS_CEREMONY.md`
D3/D5, migration 103 (algorithm pin), P1-PUBKEY-FORMAT normalizer, M6/E4 guards (110/111).
Reference implementation: `supabase/functions/_shared/offline-verify.ts` (no imports; every function pure). Conformance suite:
`tests/scanner-contract.test.ts`. Golden fixtures: `tests/fixtures/scanner-contract-v1.json`.

An external scanner CONFORMS to v1 iff, for every vector in the fixture file, it produces the same `expected` outcome (and, for a
refusal, the same `door_reason` or `null`), using only the wire token, the M1 rows and the M2 result in the file.

---

## 1. Wire token → predicate fields (one signed representation, no parallel fields)

Wire: `SNATCHIT-TICKET-CRED-V1` compact token `headerB64url.payloadB64url.signatureB64url` as `credential-sign` mints it
(`credential.ts` `buildCanonicalPayload` + `encodeToken`; canonical JSON with sorted keys, unpadded base64url).

| Predicate field | Derived from | Rule |
|---|---|---|
| `key_id` | `header.kid` | uuid (lowercase, 8-4-4-4-12) |
| `typ` | `header.typ` | must equal `SNATCHIT-TICKET-CRED-V1` (step 0) |
| `algorithm` | `header.alg` | informational; pinned against `M1[key_id].algorithm` (PFA-PT-8) |
| `claims` | the literal bytes `headerB64url.payloadB64url` | what the signature covers — recomputed from the segments, never a supplied field |
| `signature` | `signatureB64url` | 64 bytes: raw `R‖S` for ES256, raw for EdDSA |
| `session_id` | `payload.sess` | uuid |
| `atom_id` | `payload.atom` | uuid |
| `credential_version` | `payload.ver` | non-negative integer |
| `exp` | `payload.exp` | non-negative integer, unix seconds; `iat ≤ exp` |

Strictness (all ⇒ `malformed_token`): ≤ 8192 chars; exactly 3 segments; strict unpadded base64url (no `=`, no whitespace, canonical
trailing bits); header **exactly** `{alg,kid,typ}`; payload **exactly** `{atom,exp,iat,sess,ver}` — an extra key such as `atom_id`,
`session_id`, `credential_version` or `key_id` makes the token malformed, so nothing can ride alongside the signed claims; wrong
types/shapes; 64-byte signature when `alg` is a known algorithm (an unknown `alg` decodes and is refused `unsupported_alg` by the predicate).

Why there is no bypass: every field the predicate compares is read from the same bytes the signature covers; changing any of them changes
`claims` and the signature no longer verifies (suite §1: atom/session/version/exp/kid/typ/alg tampering ⇒ `signature_invalid`,
`unknown_key`, `wrong_typ`, `alg_mismatch`). A scanner MUST use `verifyOfflineWire(wire, ctx)` (decode → `OFFLINE-VERIFY-v1`) and MUST NOT
construct the decoded token by hand or accept any field from another channel (a QR side-band, a deep link, a cached row).

## 2. M1 contract (key manifest)

- **Source:** the world-readable `kernel.signing_key` projection `{ key_id, scope, event_id, venue_id, public_key, algorithm, status,
  not_before, not_after }` (083 grant + 103 `algorithm`), read with a **staff JWT** (PFA-16: `authenticated`, never `anon`). A door-session
  route for M1 does not exist (§7).
- **`public_key` format:** the DB stores an SPKI **PEM** block (runbook D3); a fixture/legacy row may carry bare base64 SPKI DER. The verifier
  MUST run `normalizeSpkiPublicKey(public_key, algorithm)` before its primitive: exactly one `PUBLIC KEY` PEM block **or** bare canonical
  base64 → canonical bare-base64 SPKI DER; refuses `PRIVATE KEY` material, other labels, malformed base64, non-SEQUENCE DER, and any SPKI whose
  algorithm identifier is not the pinned algorithm's (ES256 ⇒ uncompressed P-256, 91 bytes; EdDSA ⇒ Ed25519, 44 bytes) ⇒ `malformed_public_key`.
- **Algorithm pinning:** `M1[key_id].algorithm ∈ {ES256, EdDSA}` is the authority; `header.alg` must equal it (`alg_mismatch`) before any
  signature work. AWS bootstrap lineage is ES256 only (110/111); EdDSA remains in the verifier contract for the existing offline suite only.
- **SPKI / signature encoding:** the primitive receives canonical bare-base64 SPKI DER; ES256 signatures are raw `R‖S` (JWS/WebCrypto),
  never DER; EdDSA raw 64 bytes. Message = `claims` verbatim; ES256 primitive digests with SHA-256 (`ECDSA_SHA_256`, `MessageType: RAW` on the signer).
- **Windows:** `not_before`/`not_after` ISO-8601 (or unix seconds) → unix seconds; `not_after NULL` ⇒ unbounded. Refuse `key_window` outside.
- **Rotation:** a `rotating` key stays verifiable while in window (tokens pinned to it keep admitting until `exp`); new tokens pin the new
  `key_id`; 3c requires `token.key_id == M2[atom].signing_key_id`, so an atom re-pinned to the new key refuses an old-key token
  `wrong_signing_key` (operator copy `version_stale`). Rotation is parked (PFA-18A); the contract is stated for completeness.
- **Revocation:** `status='revoked'` ⇒ `key_revoked` on the next M1 refresh. Revocation force-closes open episodes (106): the server sets
  episode `not_after := now()`, so a reconnecting device loses M2 authority; a device offline across the revoke keeps admitting until its
  downloaded `not_after` (the accepted residual, door §8.2.1). M1 refresh: at check-in setup and on every reconnect.
- **Refusal order (M1 part):** `wrong_typ` → `unsupported_alg` → `unknown_key` → `key_revoked` → `key_window` → `alg_mismatch` →
  `malformed_public_key` → `signature_invalid`.

## 3. M2 contract (door/ticket manifest)

- **Source:** `venue.get_door_manifest(p_session_id, p_since_delta_seq)` via `door-session /manifest/sync` (door-session bearer) or the
  `door-manifest` edge (staff JWT). **Wire shape (RPC §20.6.1 reconciled):**
  `{ open, manifest_id, manifest_version, session_id, opened_at, not_after, manifest_digest, max_delta_seq, entries[], deltas[] }`,
  `entry = { ticket_atom_id, serial_no, ticket_type_id, credential_version, signing_key_id, ticket_state, resale_state }`,
  `delta(add) = { seq, ticket_atom_id, op } ∪ entry`, `delta(revoke) = { seq, ticket_atom_id, op }`.
- **Adapter:** `m2FromWire(result)` → `{ ok, m2 }` or `no_open_manifest` (`open:false` / `status ∈ {no_open_manifest, no_open_episode}`),
  `manifest_header_incomplete` (missing/invalid `session_id` or `not_after` — see §7 P1), `manifest_malformed` (any entry/delta lacking the
  MP1-READ-SET fields). A partially parseable manifest is never used.
- **Base ⊕ deltas / `lastSyncedSeq`:** the admissible set is `applyM2(m2, lastSyncedSeq)` = base ⊕ deltas with `seq ≤ lastSyncedSeq` in
  `seq` order (unsorted input tolerated). The device advertises `last_synced_seq` on sync and passes it as `p_since_delta_seq`; deltas beyond
  what it downloaded are never applied; `add` supplies/overwrites an entry, `revoke` marks it revoked (entry retained for reason splitting).
  `manifest_version` counts episodes, `seq` counts deltas — never interchange them; a new `manifest_version` ⇒ full re-sync from `seq 0`.
- **Manifest expiry / authority (door §3.1):** no M2 ⇒ `no_manifest`; `m2.session_id ≠ bound session` ⇒ `manifest_other_session`;
  `now > m2.not_after` ⇒ `manifest_expired`. Evaluated immediately before 3b. The device MUST NOT admit offline from an M2 it cannot
  bind to its session or whose horizon passed.
- **Session binding:** `token.session_id` must equal the device's bound scanning session (`wrong_session`), which is the session the
  door-session bearer was minted for (`kernel.assert_door_session` returns it) — never a session id chosen by the app.
- **Offline admission and first-in-wins:** after `{admit:true, atomId}` the scanner MUST record `atomId` in its local admitted set for the
  bound session **before** evaluating the next scan (`already_admitted` ⇒ operator `duplicate`); the set is per device per session and is
  reconciled later via `venue.reconcile_offline_scans_door` (evidence trail, not the control). `offlineVerify` never mutates the set.
- **Skew:** `expired` iff `now > exp + 2·30 s` (RPC §9.3 constant; not runtime-tunable).
- **Full refusal order:** `malformed_token` → `wrong_typ` → `unsupported_alg` → `unknown_key` → `key_revoked` → `key_window` →
  `alg_mismatch` → `malformed_public_key` → `signature_invalid` → `wrong_session` → `expired` → `no_manifest` → `manifest_other_session` →
  `manifest_expired` → `atom_absent` → `atom_revoked` → `stale_version` → `not_active` → `listed_locked` → `wrong_signing_key` →
  `already_admitted` → admit.
- **Operator vocabulary (door §9.2 / VD §12.5):** `toDoorReason(reason, appliedEntry)`: `atom_absent`/`wrong_session` → `wrong_session`;
  `atom_revoked` → `voided`; `not_active` → `duplicate` (scanned) / `voided` (voided) / `null` otherwise; `listed_locked` →
  `listed_locked` | `refund_hold` | `dispute_hold` by `resale_state`; `stale_version`/`wrong_signing_key` → `version_stale`;
  `already_admitted` → `duplicate`; every signature/key/manifest-authority/malformed refusal → `null` (generic "not a valid pass here";
  the scanner MUST NOT map these onto a §9.2 reason).

## 4. DOOR-MANIFEST-SIG-v1 (the `door-manifest` edge signature) — versioned contract for a missing integration

**Audit result.** The edge signs `canonicalManifestDigestBytes(open)` = `JSON.stringify({ manifest_id, manifest_version, session_id,
not_after, manifest_digest })` (that key order, UTF-8) with `kmsSigner.sign(DOOR_MANIFEST_KMS_HANDLE_REF, bytes, 'ES256')` and returns
`{ manifest, signature: { value: base64(raw R‖S), algorithm: 'ES256' } }`. **No canonical source in the repository tells a verifier which
public key to use:** the handle comes from an env var, not from `kernel.signing_key`; `get_door_manifest` excludes `public_key`
(PFA-24); no manifest-key registry, RPC, or M1 field names "the manifest key"; edge §5.4.2's "manifest key (also KMS)" is specified but
nothing implements or distributes it. No live key, KMS resource, DB row or deployment path is invented here.

**Contract (v1):** the artifact MUST carry `signature.key_id` — the `kernel.signing_key.key_id` whose `kms_handle_ref` is the handle the edge
signed with — and `signature.algorithm`; `signature.encoding` is `raw-r-s`; `value` is **standard** base64 of the 64-byte raw signature.
The verifier (`verifyDoorManifestSignature(artifact, m1, verify, now)`) rebuilds the canonical bytes from the received header (never trusts
a supplied byte string), resolves `M1[key_id]` under the same status/window/alg-pin/normalizer rules as a ticket credential, and refuses
`unsigned` (signature `null` — TLS-only fallback; policy is the scanner's), `missing_key_id`, `unsupported_alg`, `unknown_key`,
`key_revoked`, `key_window`, `alg_mismatch`, `malformed_public_key`, `malformed_signature`, `signature_invalid`.

**What the edge must gain before this integration is live (not done here):** resolve `key_id` for its handle (needs a definer RPC such as
`kernel.get_manifest_signing_key_id()` reading the fenced `kms_handle_ref`, or an owner-ratified env pairing `DOOR_MANIFEST_KMS_HANDLE_REF`
↔ `DOOR_MANIFEST_KEY_ID`), include `key_id`/`encoding` in the response, and — the owner decision edge §3.9b leaves open — whether M2 stays
TLS-only for MVP. Fixture `door_manifest` in the golden file is a v1-conformant artifact (signed with a throwaway key) so an external verifier
can be tested today.

## 5. Preserved guarantees

The ES256-only bootstrap guard (110/111), the P1 public-key normalizer, PFA-PT-8 pinning, and every existing `offlineVerify` refusal are
untouched; `tests/offline-verify.test.ts` (30) and `tests/credential-sign-pubkey-format.test.ts` (21) remain green. The additions only
add a `malformed_token` refusal ahead of step 0 and adapters that fail closed.

## 6. Boundary status

| Component | In this repo | Status |
|---|---|---|
| reference decoder / adapters / manifest-signature verifier / operator map | yes (`_shared/offline-verify.ts`) | implemented + tested |
| golden fixtures + conformance suite | yes | implemented + tested (19 token vectors, 1 manifest artifact) |
| mobile scanner app (QR capture, primitive, M1/M2 caching, admitted set, UI) | **no** (`app/` has no door/scan code) | **NOT implemented; external; must satisfy the fixtures** |
| `door-manifest` `key_id`/`encoding` in the response; manifest-key registry | no | **NOT implemented** (§4) |
| M1 bundle signing (edge §5.4.2 "signed by a manifest key") | no | **NOT implemented**; M1 integrity is TLS + RLS today |

## 7. Findings (external-boundary risks; nothing changed in production)

- **P1-M2-HEADER — the deployed-shape RPC body omits the header fields the predicate needs.** `venue.get_door_manifest` (086, unchanged
  through 111) returns `{status:'ok'|'no_open_episode', manifest_id, manifest_version, manifest_digest, max_delta_seq, entries, deltas}` —
  **no `open`, `session_id`, `opened_at`, `not_after`**, although RPC §20.6.1/door §7.5a (MP-1) require them and both edges assume them
  (`door-manifest`'s `isDoorManifestOpen` requires `open:true`, `session_id`, `not_after` and would answer `manifest_malformed` on every
  open episode; `/manifest/sync` relays a manifest a conforming scanner must refuse `manifest_header_incomplete`). Also `no_open_episode`
  vs the specified `no_open_manifest`. **Required fix (a body-only re-create of `venue.get_door_manifest`, a future migration, not authored
  here):** add `open`, `session_id`, `opened_at`, `not_after`, and return `{open:false, status:'no_open_manifest', entries:[], deltas:[]}`
  for no episode; keep 171 F5's reconnect-refuse semantics. Until then a v1 scanner has **no offline authority** from this RPC.
- **P2-MANIFEST-KEY** — §4: no verify-key distribution for the M2 signature; edge response lacks `key_id`.
- **P2-M1-DELIVERY** — no door-session route serves M1; a door device authenticated only by a door-session bearer cannot read
  `kernel.signing_key` (PFA-16 grants `authenticated`). Either the staff sets up M1 with a staff JWT at check-in or a `/keys` relay is added.
- **P3-M1-SIGNING** — edge §5.4.2's signed M1 bundle is unimplemented; M1 integrity rests on TLS + RLS.
- **Operator vocabulary** — door §9.2 defines copy for 3b/3c refusals only; the scanner's generic-refusal state for signature/key/manifest
  failures is a UI decision outside this contract (recorded, not invented).

## 8. Evidence
`tests/scanner-contract.test.ts` (this session): 18 passed (18); `tests/offline-verify.test.ts` green; full vitest 747 passed (747);
typecheck clean; lint 0 errors; G-4 PASS; `deno check` **OUTSTANDING** (not installed). **Tested commit `c6e2675`.**
