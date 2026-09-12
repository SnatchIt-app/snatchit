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

- **Source (ONE authority: `kernel.signing_key`).** Two delivery paths, the same rows, the same 9-field public projection
  `{ key_id, scope, event_id, venue_id, public_key, algorithm, status, not_before, not_after }` (083 grant + 103 `algorithm`):
  - **staff / client:** the table projection, read with a staff JWT (PFA-16: `authenticated`, never `anon`) — unchanged;
  - **bearer-only door device:** `door-session /keys` → `venue.get_signing_keys_door(session, door_session_id, token, device)` (migration
    114, service_role-only, `kernel.assert_door_session` the sole gate; commit `2153f44`, rehearsal only). Response `{ session_id, event_id,
    venue_id, generated_at, keys: [rows] }` → `m1FromDoorKeysResponse(resp)`. Scope is the RPC's, bound to the door session: every `global`
    key + `per_event` keys of the bound session's event + `per_venue` keys of its venue, **all statuses and windows** (the verifier applies
    `key_revoked`/`key_window`; the RPC never pre-filters — a device must be able to refuse a revoked key by name, not as `unknown_key`).
    Never `kms_handle_ref`, never identity, never an unrelated event's/venue's rows. M1 refresh: at check-in setup and on every reconnect.
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

## 4. DOOR-MANIFEST-SIG-v1 (the `door-manifest` edge signature) — IMPLEMENTED IN REHEARSAL (commit `2153f44`; not deployed)

**Signed bytes (unchanged):** `canonicalDoorManifestSignedBytes(header)` = `JSON.stringify({ manifest_id, manifest_version, session_id,
not_after, manifest_digest })` in that key order, UTF-8 — byte-identical to the edge's `canonicalManifestDigestBytes` (unit-tested parity).

**Envelope:** `{ manifest, signature: { value, algorithm: 'ES256', key_id } }` — EXACTLY those three signature fields
(`buildSignatureEnvelope`, `door-manifest/pure.ts`); `value` is **standard** base64 of the 64-byte raw `R‖S`; the encoding is fixed by
this version and is not carried as a field. No handle, no public key, no identity.

**Key identity — the source of truth.** `signature.key_id` is the `kernel.signing_key.key_id` of the **single active `global` key**
(083 `signing_key_active_global_uq` ⇒ at most one), resolved by the edge through `venue.get_manifest_signing_context()` (114,
service_role-only, called AFTER the caller was authorized by `venue.get_door_manifest`). That ONE row supplies `key_id`, `kms_handle_ref`
(the handle the edge signs with), `algorithm` and `public_key`. The former env-only `DOOR_MANIFEST_KMS_HANDLE_REF` inference is **removed**:
an environment identifier names no `key_id` and cannot be proven to correspond to one. The manifest key is therefore the same key M1
distributes as the platform trust root — there is no second registry.

**Fail-closed chain at the edge (before any KMS call):** RPC error ⇒ `manifest_signing_unavailable`; `status:'unavailable'` (stable codes
`no_active_global_key | ambiguous_active_global_key | key_window | algorithm_not_es256`) ⇒ `manifest_signing_key_unavailable`; the edge
re-pins ES256 / `key_status='active'` / window itself (`classifyManifestSigningContext`) ⇒ same code; a row whose `public_key` the shared
normalizer (`normalizeSpkiPublicKey`, P1-PUBKEY-FORMAT) rejects ⇒ `manifest_signing_key_malformed`; malformed context shape ⇒
`manifest_signing_context_malformed`. All are `500`, Sentry + audit line, KMS never reached.

**Proof of handle ↔ key_id, per response (sign-after-verify, credential-sign §9 discipline):** after `kms:Sign(kms_handle_ref, bytes)`
the edge verifies the returned bytes under the SAME row's normalized `public_key` with WebCrypto ES256. A `false` means the handle does
not correspond to the key the response would name (mis-bound ceremony, wrong key version, DER/raw drift): `500 manifest_signing_unhealthy`,
Sentry (SECURITY class), **nothing emitted, never retried**. Combined with E2's key-ARN scope check (`kms_handle_scope_mismatch`, region +
role account), a signature can only leave the edge if it verifies under the public key of the row whose `key_id` it names.

**Operational binding the ceremony MUST satisfy (runbook `PRODUCTION_SIGNING_KMS_CEREMONY.md`):**
1. D4 — the §6.1 bootstrap INSERT's `kms_handle_ref` is the FULL ARN of the key created at `CreateKey` (110 guard rejects anything else);
2. D3/D5 — `public_key` is the SPKI PEM exported from THAT key; `signing.expected_key_fingerprint` = SHA-256(DER) (099 monitor);
3. E2 — the runtime signer role's account and region equal the ARN's (otherwise every sign fails `kms_handle_scope_mismatch`, SECURITY);
4. nothing else: no env var names the manifest key; rotation = a new active global row (the edge follows the row; the old key stays
   verifiable in window per §2's rotation rule); revocation = 106 (force-close) and the context turns `no_active_global_key` — the edge
   stops signing until the E4 two-person recovery inserts a new active global row.

**Verifier (unchanged rules):** `verifyDoorManifestSignature(artifact, m1, verify, now)` rebuilds the canonical bytes from the received
header (never trusts a supplied byte string), resolves `M1[key_id]` under the same status/window/alg-pin/normalizer rules as a ticket
credential, and refuses `unsigned`, `missing_key_id`, `unsupported_alg`, `unknown_key`, `key_revoked`, `key_window`, `alg_mismatch`,
`malformed_public_key`, `malformed_signature`, `signature_invalid`. **Rotation:** a `rotating` key verifies while in window; **revocation:**
refused by name on the next M1 refresh. Real-output evidence: §8.

## 5. Preserved guarantees

The ES256-only bootstrap guard (110/111), the P1 public-key normalizer, PFA-PT-8 pinning, and every existing `offlineVerify` refusal are
untouched; `tests/offline-verify.test.ts` (30) and `tests/credential-sign-pubkey-format.test.ts` (21) remain green. The additions only
add a `malformed_token` refusal ahead of step 0 and adapters that fail closed.

## 6. Boundary status

| Component | In this repo | Status |
|---|---|---|
| reference decoder / adapters / manifest-signature verifier / operator map | yes (`_shared/offline-verify.ts`) | implemented + tested |
| golden fixtures + conformance suite | yes | implemented + tested (19 token vectors, 1 manifest artifact) + real-rehearsal evidence (`tests/fixtures/m2-rehearsal-evidence.json`) |
| mobile scanner app (QR capture, primitive, M1/M2 caching, admitted set, UI) | **no** (`app/` has no door/scan code) | **NOT implemented; external; must satisfy the fixtures** |
| `door-manifest` `signature.key_id` from `kernel.signing_key` (114 `get_manifest_signing_context`); sign-after-verify | yes | **implemented in rehearsal** (`2153f44`); not deployed |
| M1 delivery to a bearer-only door device (`door-session /keys` → 114 `get_signing_keys_door`) | yes | **implemented in rehearsal** (`2153f44`); not deployed |
| M1 bundle signing (edge §5.4.2 "signed by a manifest key") | no | **NOT implemented — explicitly open**; M1 integrity is TLS + the door-session gate (device) / RLS (staff). Would add a second signed artifact type to the ratified protocol; not done in 114. |

## 7. Findings (external-boundary risks; nothing changed in production)

- **P1-M2-HEADER — RESOLVED IN REHEARSAL (migration 112 + `door-manifest` classifier, commit `f097115`; NOT deployed, NOT
  applied to production).** The 086 body of `venue.get_door_manifest` (unchanged through 111) returned
  `{status:'ok'|'no_open_episode', manifest_id, manifest_version, manifest_digest, max_delta_seq, entries, deltas}` — **no `open`,
  `session_id`, `opened_at`, `not_after`** — although RPC §20.6.1 / door §7.5a (MP-1) require them.
  - *Observed BEFORE behaviour (corrected record).* An earlier revision of this finding claimed `door-manifest` "would answer
    `manifest_malformed` on every open episode". **That claim was wrong.** The edge had a single shape check (`isDoorManifestOpen`)
    whose only failure branch was the "no open episode" branch: against the 086 shape it classified **every open episode as closed**
    and returned it **`200 {manifest, signature:null}` — unsigned, silently, without reaching KMS** (`tests/door-manifest.test.ts`
    "the 086 OPEN-episode shape" pins the shape; the pre-fix branch is quoted in `door-manifest/pure.ts`'s header). A conforming
    scanner receiving that relay refused `manifest_header_incomplete` (this contract, §3) — so a v1 scanner had no offline authority.
  - *AFTER (rehearsal).* **Migration 112** (`supabase/migrations/112_get_door_manifest_headers.sql`, body-only re-create; rollback =
    the 086 body generated verbatim) returns the stored header **`open:true, session_id, opened_at, not_after`** (the immutable row
    values — nothing is manufactured at fetch time) alongside the unchanged 086 fields, entries and deltas; no-episode ⇒
    `{open:false, status:'no_open_episode', entries:[], deltas:[]}`. **`door-manifest`** now classifies three ways
    (`classifyDoorManifestResponse`, `supabase/functions/door-manifest/pure.ts`): `open` ⇒ sign via KMS; `closed` ⇒ `200` unsigned
    (legitimate); `malformed` ⇒ **`500 {code:'manifest_malformed'}`**, Sentry + audit line, **before any KMS call**. The 086
    open-episode shape now lands in `malformed:missing_open`, never in `closed`.
  - *Canonical conflicts, documented (not silently changed).* (1) `status` string: 086/171 F5 `no_open_episode` vs §20.6.1
    `no_open_manifest` — **kept `no_open_episode`** and added the canonical `open:false`; consumers key on `open`; both spellings are
    accepted by `m2FromWire` and the edge classifier. (2) Expired-but-'open' episode: 086 returned it; door §7.5 preconditions the read on
    `status='open' AND not_after > now()` — **aligned to §7.5** (reported `open:false`; the row is untouched, `not_after` stays immutable,
    no expiry is written; strictly less permissive). (3) `p_since_delta_seq` NULL vs non-NULL: 086's superset behaviour (entries always
    returned, deltas filtered) preserved unchanged.
  - *Evidence with REAL rehearsal RPC output.* `scripts/rehearsal_m2_evidence.sh` captures `venue.get_door_manifest`'s actual JSON from
    the local rehearsal database (rolled-back transaction) into `tests/fixtures/m2-rehearsal-evidence.json`;
    `tests/m2-rehearsal-evidence.test.ts` drives it through both consumers: open full snapshot (`m2FromWire` ok, `session_id`/`not_after`
    equal the stored row, 3 atoms), incremental (`since 0` ⇒ the revoke delta applied, `since 1` ⇒ none), closed and expired (`closed` /
    `no_open_manifest`; expired row still `status='open'`), unauthorized callers (buyer `42501 insufficient_privilege`; service_role
    `42501 permission denied for function get_door_manifest`; unknown session `42501`), malformed headers (mutated copies ⇒ edge
    `malformed`, adapter `manifest_header_incomplete`/`manifest_malformed`), and an end-to-end OFFLINE-VERIFY-v1 run keyed to the real
    `signing_key_id`/session/atoms (admit; `atom_revoked`; `stale_version`; `wrong_session` for a wrong bound session and for another
    session's M2; `expired`; `manifest_expired`). pgTAP `supabase/tests/178_get_door_manifest_headers.sql` (41) covers the same matrix
    against the database, plus grants/definer invariants and rollback→reapply.
- **P1-M2-DOOR-AUTHZ — RESOLVED IN REHEARSAL (migration 113 + `door-session /manifest/sync` rewire, commit `a122a6c`; NOT
  deployed, NOT applied to production).** Found while fixing P1-M2-HEADER: `venue.get_door_manifest`'s authorization is
  `kernel.has_venue_role(venue, [venue_scanner, venue_manager])` — caller identity only — and its grants are `postgres` + `authenticated`
  (no `service_role`), so `door-session /manifest/sync` (service_role client) was refused `42501` (178 A2/D4).
  - *Closure, following migration 108's machine-authority pattern (MACHINE MAY EXECUTE, DOOR SESSION DECIDES SCOPE).* **Migration 113**
    adds `venue._get_door_manifest_core(session, since)` — the 112 read body verbatim minus the role gate, **zero grant** (PUBLIC, anon,
    authenticated, service_role all revoked) — and `venue.get_door_manifest_door(session, door_session_id, token, device, since)` —
    **service_role-only** (PUBLIC/anon/authenticated explicitly revoked), whose ONLY gate is `kernel.assert_door_session`; the manifest is
    read for the RETURNED bound session, never a body field (a body device/session that disagrees raises the same opaque
    `door_session_invalid`). The staff RPC is re-created body-only as role gate → core; its grants and authorization are unchanged and
    its response is byte-identical to 112 (suite 178 unchanged and green; 179 B5 asserts machine read == staff read as jsonb).
  - *Edge.* `/manifest/sync` now relays through `get_door_manifest_door` (`buildManifestSyncMachineCall`, `door-session/pure.ts`): the
    edge's earlier `assert_door_session` admit call remains the rate-limit + opaque-auth gate, but the machine RPC's own database-side
    assert is the authorization of record — credentials revoked/expired between the two checks are refused there and mapped to the SAME
    opaque 401 (`classifyMachineRpcError`: only `door_session_invalid` is an auth outcome; any other error, including a non-`door_session_invalid`
    42501 = missing grant, is a 500 + Sentry, never disguised as auth). The bearer secret is only ever an RPC argument; `redactSecret`
    scrubs it from any error text before Sentry; log lines carry fixed non-secret selectors only.
  - *Census.* venue functions 83 → 85; five-schema routine count 292 → 294 (suites 144 A15 / 145 A4 / 148 B5 / 156 A20 / 179 A8–A9 moved by
    exactly these two, re-derived from the live catalog). The 140 anon/PUBLIC/authenticated sweep is unmoved.
  - *Evidence with REAL rehearsal RPC output* (`tests/fixtures/m2-rehearsal-evidence.json`, `door_*` keys; the fixture carries NO secret —
    asserted): valid bound device full + incremental (`since 0/1/null`) byte-identical to the staff read and passing `m2FromWire` + the
    `door-manifest` classifier; wrong token / device / session / unknown id / service_role without credentials ⇒ the ONE opaque
    `42501 door_session_invalid`; admit check passes then revoke ⇒ machine RPC refused; expired door session refused; anon / authenticated
    (even with VALID door credentials) and direct core calls ⇒ `permission denied`; closed and expired manifests ⇒ `no_open_manifest`;
    staff path unchanged. pgTAP `supabase/tests/179_get_door_manifest_door_machine_authority.sql` (45) covers the same matrix plus grants,
    definer/volatility invariants, census, and rollback→reapply.
- **P2-MANIFEST-KEY — RESOLVED IN REHEARSAL (114 + `door-manifest`, `2153f44`).** `signature.key_id` now names the single active global
  `kernel.signing_key` resolved through `venue.get_manifest_signing_context()`; the env-only handle is gone; every emitted signature is
  verified under that row's public key before it leaves the edge (§4).
- **P2-M1-DELIVERY — RESOLVED IN REHEARSAL (114 + `door-session /keys`, `2153f44`).** `venue.get_signing_keys_door` serves the bound
  scope's public projection to a bearer-only device (§2). *Former text:* no door-session route serves M1; a door device authenticated only by a door-session bearer cannot read
  `kernel.signing_key` (PFA-16 grants `authenticated`). Either the staff sets up M1 with a staff JWT at check-in or a `/keys` relay is added.
- **P3-M1-SIGNING — OPEN (explicitly kept).** edge §5.4.2's signed M1 bundle is unimplemented; M1 integrity rests on TLS + the door-session
  gate (device) / RLS (staff). Implementing it would add a second signed artifact type to the ratified protocol — deliberately not bundled into 114.
- **Operator vocabulary** — door §9.2 defines copy for 3b/3c refusals only; the scanner's generic-refusal state for signature/key/manifest
  failures is a UI decision outside this contract (recorded, not invented).

## 8. Evidence
`tests/scanner-contract.test.ts` (c6e2675 session): 18 passed (18); `tests/offline-verify.test.ts` green; full vitest 747 passed (747);
typecheck clean; lint 0 errors; G-4 PASS. **Tested commit `c6e2675`.**

**P1-M2-HEADER train (commit `f097115`).** Fresh rehearsal replay through 112 (`scripts/rehearsal_reset.sh`); full pgTAP baseline
+ suite 178 (41/41) — see the train's commit message for the totals; rollback 112 ⇒ 178 fails exactly its 11 header assertions, double
reapply ⇒ identical definition md5 `362c28545c16ec02bec6af5a34b31bf8`, grants unchanged (`authenticated` yes / `service_role` no);
`tests/door-manifest.test.ts` 6 + `tests/m2-rehearsal-evidence.test.ts` 7; full vitest 760 passed (760); typecheck clean; lint 0 errors
(45 pre-existing warnings); G-4 PASS. **`deno check`:** CLOSED IN CI — the `deno-check` job added in f097115 (denoland/setup-deno pinned by SHA, v2.0.3) type-checks the shared pure modules and the three edge entrypoints; its first run found 8 pre-existing Deno-only type errors in credential-sign/door-session (never seen by the Node typecheck, which excludes `supabase/functions`), fixed type-level-only in d9ce602; run 33998491950 at d9ce602: Deno type-check success, Typecheck/Lint/Unit success, Migrations success, Web build success. Still not runnable on the engineering host (no Deno installed).

**P1-M2-DOOR-AUTHZ train (commit `a122a6c`).** Fresh rehearsal replay through 113 (Gate-2 27/70/37/26 unchanged); full pgTAP
plan 3899 · ok 3895 · not_ok 4 (only the documented 060×2/132×2 local deltas; 3854 post-112 + 45); suites 178 41/41 (unchanged) + 179 45/45; rollback 113 ⇒ staff definition md5 back to 112's `362c28545c16ec02bec6af5a34b31bf8`,
venue 83, both new functions gone, 178 green / 179 absent-function errors; double reapply ⇒ venue 85, grants correct;
`tests/door-session.test.ts` +10, `tests/m2-rehearsal-evidence.test.ts` +8 (15); full vitest 777 passed (777); typecheck clean; lint
0 errors (45 pre-existing warnings); G-4 PASS. **`deno check` (CI):** run 33999411593 at a122a6c — Deno type-check success (door-session/pure.ts + index.ts included), Typecheck/Lint/Unit success, Migrations success, Web build success.

**M1 delivery + manifest key identity train (commit `2153f44`).** Fresh rehearsal replay through 114 (Gate-2 27/70/37/26; venue 87 /
five-schema 296); full pgTAP plan 3941 · ok 3937 · not_ok 4 (documented 060×2/132×2 only); suites 178 41/41, 179 45/45, **180 42/42**
(grants + PUBLIC revoked + definer invariants + census; staff projection unchanged — 9 columns, `kms_handle_ref` fenced, PFA-16 policy
intact; M1 door read = exactly the 6 in-scope rows incl. rotating/revoked/future, unrelated event + venue rows absent, 9-field projection
per row, no handle/ARN leak; wrong token/device/session, no-credential service_role, anon/authenticated direct refused; signing context =
the active global key with the same `public_key` M1 lists; no active global ⇒ `no_active_global_key` while M1 shows the key `rotating`;
revoked door session refused); rollback 114 ⇒ venue 85, both functions gone, staff projection intact, double reapply idempotent.
**Real rehearsal output** (`scripts/rehearsal_m2_evidence.sh`: a throwaway P-256 key's PUBLIC half is inserted as the active global row
inside the rolled-back capture; its private half signs the captured open manifest's canonical header once and is discarded; the fixture
carries no handle, secret, or private material — asserted): `tests/m2-rehearsal-evidence.test.ts` 25/25 — the real artifact verifies under
DOOR-MANIFEST-SIG-v1 against M1 built from the real `/keys` output (`m1FromDoorKeysResponse`); missing `key_id`, unknown key, revoked key,
out-of-window rotating key, future key, alg mismatch, tampered header, unsigned all refused with the contract's codes; key-window boundaries
on real rows (rotating key verifiable AT `not_after`, refused after; future key refused before `not_before`, window-ok at it); direct
anon/authenticated/service_role access outcomes; the shared normalizer accepts the real PEM. `tests/door-manifest.test.ts` +5
(`classifyManifestSigningContext` re-pins ES256/active/window; `buildSignatureEnvelope` is exactly three fields), `tests/door-session.test.ts`
+3 (`/keys` dispatch, `buildKeysMachineCall`); full vitest 796 passed (796); typecheck clean; lint 0 errors (45 pre-existing warnings);
G-4 PASS; CI run 34000767749 at `2153f44`: Deno type-check (edge functions incl. the rewired `door-manifest`/`door-session`) success, Typecheck/Lint/Unit
success, Migrations success, Web build success.
