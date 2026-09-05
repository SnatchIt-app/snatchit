/**
 * supabase/functions/_shared/offline-verify.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * The PURE, dependency-injected core of the offline door admission predicate,
 * `OFFLINE-VERIFY-v1` (BINDING · NORMATIVE · SINGLE SOURCE:
 * `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §5.4.3, sanctioned mirror
 * at `PHASE_2_DOOR_LIFECYCLE_SPEC.md` §9.2). This module implements that
 * fenced block, faithfully and at full strength — it adds no predicate the
 * spec does not list and weakens none.
 *
 * WHY THIS FILE HAS NO IMPORTS
 *   Same discipline as `credential-sign/credential.ts`: no Deno/Node-specific
 *   API, no crypto library, no coupling to `credential-sign`'s own verifier
 *   shape. The crypto primitive (`verify`) is INJECTED by the caller — the
 *   real door/edge supplies whatever the platform offers, the test suite
 *   injects Node's Ed25519 — mirroring `credential.ts`'s `VerifyPrimitive`
 *   pattern without importing it, so this module stays independently
 *   testable and decoupled from that module's evolution.
 *
 * WHAT "TOKEN" MEANS AT THIS LAYER
 *   `OFFLINE-VERIFY-v1` step 2 reads `Verify(M1[kid].public_key, token.claims,
 *   token.sig)` — at the predicate's own level of abstraction the token is
 *   already an unpacked `{ key_id, claims (signed bytes), sig, session_id,
 *   exp, credential_version, atom_id }`, not a compact wire string. Wire
 *   decoding (base64url/JSON framing, as `credential-sign/credential.ts`
 *   defines for `SNATCHIT-TICKET-CRED-V1`) is a scanner-SDK concern one layer
 *   up; this module starts from the already-decoded claim set the predicate
 *   text itself operates on. See `OfflineToken` below.
 *
 * M1 / M2 — TWO ARTIFACTS, NEITHER SUBSTITUTES FOR THE OTHER (edge §5.4.1)
 *   M1 — the key manifest: `{ key_id, scope, event_id|venue_id, public_key,
 *   algorithm, not_before, not_after, status }`, keyed by `key_id` (edge
 *   §5.4.2 + migration `103`/`PFA-PT-8`'s added `algorithm` column — the
 *   algorithm-pin fix for alg-confusion). Verifies a token's SIGNATURE.
 *
 *   M2 — the per-session door/ticket manifest (door §9.1, §10.1/§10.3/§10.3a):
 *   a `base_snapshot` plus an ordered, append-only `deltas` log. Verifies a
 *   token's CURRENCY. The device MUST evaluate the APPLIED set —
 *   `base_snapshot ⊕ deltas[1..last_synced_seq]` (door §7.7) — never the base
 *   snapshot alone; `applyM2` below is that reducer. An `add` delta
 *   supplies/overwrites an atom's entry (a supplement — a ticket type added
 *   mid-session); a `revoke` delta marks a previously-visible atom revoked
 *   without erasing what it was (so the failing reason at 3b can still be
 *   distinguished from "never existed").
 *
 * REASON-CODE VOCABULARY — this module's, not door §9.2's UI map
 *   `OFFLINE-VERIFY-v1` step 3b is FIVE separate conjuncts and edge §5.4.3
 *   itself requires "a unit/integration regression test covering every
 *   conjunct SEPARATELY". Door §9.2's reader-facing map collapses several of
 *   those into shared operator copy (`wrong_session` doubles for "atom absent
 *   from M2", `voided` doubles for "revoked-by-delta" and "ticket_state=
 *   voided", `version_stale` doubles for 3b.iii AND 3c) — correct for a door
 *   screen, useless for isolating which conjunct a test fixture exercises.
 *   This module's `OfflineVerifyReason` enum is therefore ONE CODE PER
 *   CONJUNCT (see the per-branch comments in `offlineVerify` for the exact
 *   mapping) plus the manifest-authority and rotation/alg-confusion codes the
 *   conjuncts don't otherwise name. A door-facing UI would translate this
 *   module's reason into door §9.2's operator copy; that translation is out
 *   of this module's scope. Flagged in `docs/phase2/_impl/KOFFLINE.md` as a
 *   possible `PFA` candidate (reconcile or explicitly layer the two
 *   vocabularies) since the two are NOT the same vocabulary despite both
 *   citing door §9.2.
 *
 * WHAT THIS MODULE DOES NOT DO
 *   No network, no DB, no KMS, no mutation. `offlineVerify` does not write to
 *   `admittedSet` on an admit (conjunct 4, first-in-wins) — it is the
 *   CALLER's job to record the atom once admitted, because a pure predicate
 *   that silently mutates a Set passed in by reference is not testable
 *   idempotently and not what "pure" means here. See `offlineVerify`'s
 *   doc comment for the exact contract.
 */

// ─────────────────────────────────────────────────────────────────────────
// M1 — the key manifest (edge §5.4.2 + migration 103 / PFA-PT-8)
// ─────────────────────────────────────────────────────────────────────────

export interface M1Entry {
  key_id: string;
  scope: string;
  event_id?: string | null;
  venue_id?: string | null;
  public_key: string;
  /** PFA-PT-8 (migration 103): the algorithm pin. `Verify` MUST run under
   *  this value, refusing (`alg_mismatch`) if the token's own header `alg`
   *  disagrees — BEFORE the signature is ever checked. Prevents an
   *  alg-confusion attack where a token claims a different algorithm than
   *  the one the manifest trusts for that `kid`. */
  algorithm: string;
  /** Unix seconds. */
  not_before: number;
  /** Unix seconds. */
  not_after: number;
  /** `'revoked'` is the only status this predicate inspects (step 1). Any
   *  other value (`'active'`, etc.) is treated as usable. */
  status: string;
}

/** Keyed by `key_id`. A projection of the world-readable `kernel.signing_key`
 *  columns (edge §5.4.2) — public keys + windows only, never private
 *  material. */
export type M1Manifest = Record<string, M1Entry>;

// ─────────────────────────────────────────────────────────────────────────
// M2 — the per-session door/ticket manifest (door §9.1/§10.1/§10.3/§10.3a)
// ─────────────────────────────────────────────────────────────────────────

export interface M2AtomEntry {
  credential_version: number;
  signing_key_id: string;
  /** e.g. `'issued' | 'active' | 'scanned' | 'voided'`. Only `'active'`
   *  passes conjunct 3b.iv — every other value (including one this module
   *  has never seen named) fails it. Door §9.2's snapshot is now COMPLETE:
   *  every atom of the session, in every state (the DL-5 ruling) — so
   *  "absent from M2" means exactly one thing: this atom does not belong to
   *  this session. */
  ticket_state: string;
  /** e.g. `'none' | 'listed' | 'locked' | 'refund_hold' | 'dispute_hold'`.
   *  Only `'none'` passes conjunct 3b.v. This module maps every other value
   *  to the single reason `listed_locked` — see the module header's
   *  reason-vocabulary note; door §9.2 gives `refund_hold`/`dispute_hold`
   *  their own operator-facing reasons and `listed`/`locked` share
   *  `listed_locked`, a finer split this pure layer does not reproduce. */
  resale_state: string;
}

export type M2Delta =
  | { seq: number; op: 'add'; atom: string; entry: M2AtomEntry }
  | { seq: number; op: 'revoke'; atom: string };

export interface M2Manifest {
  manifest_id: string;
  /** The session this M2 has offline authority for (door §3.1: an M2 for
   *  another session has NO offline authority). */
  session_id: string;
  /** Unix seconds — this downloaded M2's own expiry. Distinct from any
   *  individual atom's fields. */
  not_after: number;
  /** The base snapshot at manifest-open time, per atom id. */
  base: Record<string, M2AtomEntry>;
  /** Append-only, ordered by `seq`. Not assumed pre-sorted by the caller —
   *  `applyM2` sorts defensively. */
  deltas: M2Delta[];
}

export interface AppliedM2Entry extends M2AtomEntry {
  /** `true` iff an applied `revoke` delta targeted this atom (conjunct
   *  3b.ii). The rest of the entry's fields are the last-known values (from
   *  the base snapshot or a prior `add`) so a revoked atom's prior state
   *  remains inspectable — the predicate itself never reads these fields
   *  once `revoked` is `true` (3b.ii short-circuits first). */
  revoked: boolean;
}

/** The applied set: `base_snapshot ⊕ deltas[1..lastSyncedSeq]`. Keyed by
 *  atom id. This is the *only* correct input to conjuncts 3b/3c — evaluating
 *  `m2.base` alone silently ignores every revocation and every supplement
 *  the device has already downloaded (edge §5.4.3's own warning, restated as
 *  a type here rather than left as a comment a caller can skip). */
export type AppliedM2 = Record<string, AppliedM2Entry>;

/**
 * The `applied(lastSyncedSeq)` reducer (edge §5.4.3 "Applied set", door
 * §7.7): folds `m2.deltas` with `seq <= lastSyncedSeq`, in `seq` order, over
 * `m2.base`. An `add` delta supplies or overwrites an atom's entry
 * (`revoked` reset to `false` — a supplement is a fresh, un-revoked entry).
 * A `revoke` delta marks the atom `revoked: true`, preserving whatever entry
 * it already had (or, if the atom was never seen before this delta — a
 * revoke with no prior `add`/base row, not expected in practice but not
 * ruled out by the type — a placeholder entry so the atom is still
 * "present", `revoked`), so 3b.ii ("no applied `revoke` delta") is
 * distinguishable from 3b.i ("atom ∈ M2") in every case.
 */
export function applyM2(m2: M2Manifest, lastSyncedSeq: number): AppliedM2 {
  const applied: AppliedM2 = {};
  for (const [atom, entry] of Object.entries(m2.base)) {
    applied[atom] = { ...entry, revoked: false };
  }
  const ordered = m2.deltas
    .filter((d) => d.seq <= lastSyncedSeq)
    .slice()
    .sort((a, b) => a.seq - b.seq);
  for (const delta of ordered) {
    if (delta.op === 'add') {
      applied[delta.atom] = { ...delta.entry, revoked: false };
    } else {
      const existing = applied[delta.atom];
      applied[delta.atom] = existing
        ? { ...existing, revoked: true }
        : {
            credential_version: 0,
            signing_key_id: '',
            ticket_state: 'unknown',
            resale_state: 'unknown',
            revoked: true,
          };
    }
  }
  return applied;
}

// ─────────────────────────────────────────────────────────────────────────
// The device's local admitted set — conjunct 4, first-in-wins
// ─────────────────────────────────────────────────────────────────────────

/** The device's local first-in-wins set of already-admitted atom ids for
 *  the current bound scanning session. `offlineVerify` reads it but never
 *  writes it — see the module header and `offlineVerify`'s doc comment. */
export type LocalAdmittedSet = ReadonlySet<string>;

// ─────────────────────────────────────────────────────────────────────────
// The token, at the predicate's own level of abstraction (see module header)
// ─────────────────────────────────────────────────────────────────────────

/** The ticket-credential domain separator — MUST byte-match
 *  `credential-sign/credential.ts`'s `DOMAIN` and `kernel.get_ticket_signing_
 *  context`'s `domain`. A token whose `typ` is not exactly this is not a ticket
 *  credential and is refused (`wrong_typ`) before any key/signature work — this
 *  is the door-side half of domain separation (a genuinely-signed token of a
 *  DIFFERENT type, e.g. a wallet/door manifest, must never be admitted here even
 *  if its payload shape-matches). */
export const DOMAIN = 'SNATCHIT-TICKET-CRED-V1';

/** The only algorithms this predicate will verify under. A whitelist on BOTH
 *  the token's claimed alg AND the trusted M1 entry's alg — so a non-canonical
 *  algorithm string in a manifest (data-quality/migration bug) can never be
 *  matched by a crafted token and passed through to `verify` as an arbitrary
 *  string (PFA-PT-8, defence-in-depth to match credential.ts's own whitelist). */
const KNOWN_ALGORITHMS: ReadonlySet<string> = new Set(['EdDSA', 'ES256']);

// ─────────────────────────────────────────────────────────────────────────
// Trusted public-key NORMALIZATION (P1-PUBKEY-FORMAT) — an IDENTICAL, self-
// contained copy of `credential-sign/credential.ts`'s `normalizeSpkiPublicKey`
// (this module's no-imports rule; `tests/credential-sign-pubkey-format.test.ts`
// asserts the two copies agree on the full acceptance/rejection matrix).
// ACCEPTS one `-----BEGIN PUBLIC KEY-----` block (LF/CRLF, no headers) or bare
// padded canonical base64; REJECTS (→ `null`, never throws) PRIVATE KEY
// material, other PEM labels, base64url/unpadded/whitespace-laden base64,
// non-SEQUENCE DER, and any SPKI whose AlgorithmIdentifier is not the pinned
// algorithm's (ES256 ⇒ uncompressed P-256, 91 bytes; EdDSA ⇒ Ed25519, 44).
// RETURNS canonical bare-base64 SPKI DER. This is what the scanner SDK MUST
// call on every `M1[kid].public_key` before its own verify primitive.
// ─────────────────────────────────────────────────────────────────────────

const B64_STD = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const B64_STD_REVERSE: Record<string, number> = (() => {
  const map: Record<string, number> = {};
  for (let i = 0; i < B64_STD.length; i++) map[B64_STD[i]] = i;
  return map;
})();
const SPKI_PREFIX_P256_UNCOMPRESSED: readonly number[] = [
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
  0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
];
const SPKI_PREFIX_ED25519: readonly number[] = [
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
];
const SPKI_LENGTH: Record<string, number> = { ES256: 91, EdDSA: 44 };
const PEM_PUBLIC_KEY_RE = /^-----BEGIN PUBLIC KEY-----(?:\r?\n)([A-Za-z0-9+/=\r\n]+?)(?:\r?\n)-----END PUBLIC KEY-----$/;
const BARE_BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

function base64DecodeStrict(b64: string): Uint8Array | null {
  if (b64.length === 0 || b64.length % 4 !== 0 || !BARE_BASE64_RE.test(b64)) return null;
  const pad = b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0;
  const firstPad = b64.indexOf('=');
  if (firstPad !== -1 && firstPad !== b64.length - pad) return null;
  const out: number[] = [];
  for (let i = 0; i < b64.length; i += 4) {
    const c2 = b64[i + 2];
    const c3 = b64[i + 3];
    const n0 = B64_STD_REVERSE[b64[i]];
    const n1 = B64_STD_REVERSE[b64[i + 1]];
    const n2 = c2 === '=' ? 0 : B64_STD_REVERSE[c2];
    const n3 = c3 === '=' ? 0 : B64_STD_REVERSE[c3];
    if (n0 === undefined || n1 === undefined || n2 === undefined || n3 === undefined) return null;
    out.push(((n0 << 2) | (n1 >> 4)) & 0xff);
    if (c2 !== '=') out.push(((n1 << 4) | (n2 >> 2)) & 0xff);
    if (c3 !== '=') out.push(((n2 << 6) | n3) & 0xff);
  }
  if (pad === 1 && (B64_STD_REVERSE[b64[b64.length - 2]] & 0x03) !== 0) return null;
  if (pad === 2 && (B64_STD_REVERSE[b64[b64.length - 3]] & 0x0f) !== 0) return null;
  return new Uint8Array(out);
}

function base64EncodeStd(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  for (; i + 3 <= bytes.length; i += 3) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += B64_STD[(n >> 18) & 63] + B64_STD[(n >> 12) & 63] + B64_STD[(n >> 6) & 63] + B64_STD[n & 63];
  }
  const remaining = bytes.length - i;
  if (remaining === 1) {
    const n = bytes[i] << 16;
    out += B64_STD[(n >> 18) & 63] + B64_STD[(n >> 12) & 63] + '==';
  } else if (remaining === 2) {
    const n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += B64_STD[(n >> 18) & 63] + B64_STD[(n >> 12) & 63] + B64_STD[(n >> 6) & 63] + '=';
  }
  return out;
}

export function normalizeSpkiPublicKey(input: unknown, algorithm: string): string | null {
  if (typeof input !== 'string') return null;
  const text = input.replace(/^[\t\r\n ]+|[\t\r\n ]+$/g, '');
  if (text.length === 0 || text.length > 4096) return null;
  if (text.indexOf('PRIVATE KEY') !== -1) return null;

  let b64: string;
  if (text.startsWith('-----')) {
    const m = PEM_PUBLIC_KEY_RE.exec(text);
    if (!m) return null;
    b64 = m[1].replace(/\r?\n/g, '');
  } else {
    b64 = text;
  }

  const bytes = base64DecodeStrict(b64);
  if (!bytes || bytes.length < 4) return null;

  if (bytes[0] !== 0x30) return null;
  let len: number;
  let hdr: number;
  if (bytes[1] < 0x80) { len = bytes[1]; hdr = 2; }
  else if (bytes[1] === 0x81) { len = bytes[2]; hdr = 3; }
  else if (bytes[1] === 0x82) { len = (bytes[2] << 8) | bytes[3]; hdr = 4; }
  else return null;
  if (hdr + len !== bytes.length) return null;

  if (!KNOWN_ALGORITHMS.has(algorithm)) return null;
  if (bytes.length !== SPKI_LENGTH[algorithm]) return null;
  const prefix = algorithm === 'ES256' ? SPKI_PREFIX_P256_UNCOMPRESSED : SPKI_PREFIX_ED25519;
  for (let i = 0; i < prefix.length; i++) if (bytes[i] !== prefix[i]) return null;
  if (algorithm === 'ES256' && bytes[prefix.length] !== 0x04) return null;

  return base64EncodeStd(bytes);
}


export interface OfflineToken {
  /** `token.key_id` — selects the M1 entry (step 1) and, per 3c, must equal
   *  `M2[atom].signing_key_id`. */
  keyId: string;
  /** `token.typ` — the domain separator; must equal `DOMAIN` or the token is
   *  refused `wrong_typ` before any other check. */
  typ: string;
  /** The token's own claimed signing algorithm (its header `alg`, in
   *  `credential-sign` terms) — compared against `M1[kid].algorithm` before
   *  any signature check (PFA-PT-8 alg pin). */
  algorithm: string;
  /** The exact bytes the signature was computed over (`token.claims`, step
   *  2) — opaque to this module; only `verify` interprets them. */
  claims: Uint8Array;
  /** `token.sig`, step 2. */
  sig: Uint8Array;
  /** `token.session_id`, step 3. */
  sessionId: string;
  /** The atom this token admits — read for 3b/3c/4, never itself covered by
   *  the signature check in this module's abstraction (it lives inside
   *  `claims`, whose byte layout is a wire-format concern one layer up). */
  atomId: string;
  /** `token.credential_version`, compared at 3b.iii. */
  credentialVersion: number;
  /** `token.exp`, unix seconds, checked at 3a. */
  exp: number;
}

/** Injected crypto verify primitive — mirrors `credential-sign/credential.ts`'s
 *  `VerifyPrimitive` shape without importing it (module header: decoupled on
 *  purpose). Synchronous: an offline door predicate does no I/O, and neither
 *  does this. */
export type VerifyPrimitive = (
  publicKey: string,
  message: Uint8Array,
  signature: Uint8Array,
  algorithm: string,
) => boolean;

// ─────────────────────────────────────────────────────────────────────────
// Reason codes — one per failing conjunct (see module header)
// ─────────────────────────────────────────────────────────────────────────

export type OfflineVerifyReason =
  // Step 0-wire (SCANNER-CONTRACT-v1) — the wire string did not decode strictly
  | 'malformed_token'
  // Step 0 — domain + algorithm shape (before any key/signature work)
  | 'wrong_typ' // token.typ != DOMAIN — not a ticket credential
  | 'unsupported_alg' // token.algorithm not in {EdDSA, ES256}
  // Step 1 — M1 key lookup
  | 'unknown_key' // token.key_id ∉ M1
  | 'key_revoked' // M1[kid].status == 'revoked'
  | 'key_window' // now() ∉ [M1[kid].not_before, not_after]
  // PFA-PT-8 alg pin, evaluated between step 1 and step 2
  | 'alg_mismatch' // token.algorithm != M1[kid].algorithm
  // P1-PUBKEY-FORMAT — M1[kid].public_key does not parse as the pinned algorithm's SPKI
  | 'malformed_public_key'
  // Step 2 — signature
  | 'signature_invalid' // Verify(...) == false
  // Step 3 — session binding
  | 'wrong_session' // token.session_id != boundSessionId
  // Step 3a — expiry ± skew
  | 'expired' // now() > token.exp + 2*timeBucketSeconds
  // Manifest-authority gate (precondition for 3b — door §3.1)
  | 'no_manifest' // no M2 downloaded/supplied at all
  | 'manifest_other_session' // M2.session_id != boundSessionId
  | 'manifest_expired' // now() > M2.not_after
  // Step 3b — FIVE conjuncts, one code each
  | 'atom_absent' // 3b.i   — atom ∉ applied M2
  | 'atom_revoked' // 3b.ii  — applied M2 carries a `revoke` for this atom
  | 'stale_version' // 3b.iii — token.credentialVersion != M2[atom].credential_version
  | 'not_active' // 3b.iv  — M2[atom].ticket_state != 'active'
  | 'listed_locked' // 3b.v   — M2[atom].resale_state != 'none'
  // Step 3c — signing-key/atom binding
  | 'wrong_signing_key' // token.key_id != M2[atom].signing_key_id
  // Step 4 — first-in-wins
  | 'already_admitted'; // atom ∈ admittedSet already

export type OfflineVerifyResult =
  | { admit: true; atomId: string }
  | { admit: false; reason: OfflineVerifyReason };

export interface OfflineVerifyContext {
  m1: M1Manifest;
  /** `null`/`undefined` ⇒ no offline authority at all (`no_manifest`). */
  m2: M2Manifest | null | undefined;
  /** `door §7.7`'s `last_synced_seq` — how far into `m2.deltas` this device
   *  has synced. Deltas past this are NOT applied (they haven't been
   *  downloaded yet from this device's point of view). */
  lastSyncedSeq: number;
  /** The device's bound scanning session (conjunct 3, and the session M2
   *  must belong to). */
  boundSessionId: string;
  nowSeconds: number;
  /** RPC §9.3 (`R-22`/`MP-1`): a fixed protocol constant, `30` seconds — NOT
   *  a runtime-tunable config key ("signer and long-offline verifier must
   *  agree, which a runtime-tunable value cannot guarantee"). Defaulted to
   *  `DEFAULT_TIME_BUCKET_SECONDS` below; overridable for tests. */
  timeBucketSeconds?: number;
  admittedSet: LocalAdmittedSet;
  verify: VerifyPrimitive;
}

/** RPC §9.3 / `R-22` (`MP-1`): "A time-bucket is `30 seconds`" — a fixed
 *  protocol constant, stated once, cited everywhere else. */
export const DEFAULT_TIME_BUCKET_SECONDS = 30;

/**
 * `ADMIT(token)` — `OFFLINE-VERIFY-v1` (edge §5.4.3 · door §9.2), evaluated
 * in the exact order the fenced block states: 1 → 2 (with the PFA-PT-8 alg
 * pin between them) → 3 → 3a → [manifest-authority gate] → 3b (i..v) → 3c →
 * 4. Short-circuits at the FIRST failing conjunct and returns that reason —
 * every later conjunct is simply not evaluated, matching "requires ALL of".
 *
 * PURE / NO MUTATION: on admit, this function does NOT add `token.atomId` to
 * `ctx.admittedSet` — conjunct 4 is checked (read-only) but never enforced by
 * writing. The CALLER is responsible for recording the atom (e.g.
 * `admittedSet.add(result.atomId)`) immediately after receiving
 * `{ admit: true }`, before the next scan is evaluated against the same set.
 * A pure function that mutates a caller-owned `Set` as a side effect is not
 * independently testable against a fixed fixture twice, which is the entire
 * reason this module exists as a pure core.
 */
export function offlineVerify(token: OfflineToken, ctx: OfflineVerifyContext): OfflineVerifyResult {
  const timeBucketSeconds = ctx.timeBucketSeconds ?? DEFAULT_TIME_BUCKET_SECONDS;
  const toleranceSeconds = 2 * timeBucketSeconds;

  // ── Step 0: domain separation + algorithm whitelist — before any key lookup
  // or signature work, so a garbage typ/alg never drives a manifest read (no
  // oracle) and a non-canonical alg can never be matched-through to `verify`.
  if (token.typ !== DOMAIN) return { admit: false, reason: 'wrong_typ' };
  if (!KNOWN_ALGORITHMS.has(token.algorithm)) return { admit: false, reason: 'unsupported_alg' };

  // ── Step 1: token.key_id ∈ M1 ∧ status ≠ 'revoked' ∧ now() ∈ [not_before, not_after]
  const m1Entry = ctx.m1[token.keyId];
  if (!m1Entry) return { admit: false, reason: 'unknown_key' };
  if (m1Entry.status === 'revoked') return { admit: false, reason: 'key_revoked' };
  if (ctx.nowSeconds < m1Entry.not_before || ctx.nowSeconds > m1Entry.not_after) {
    return { admit: false, reason: 'key_window' };
  }

  // ── PFA-PT-8 (migration 103): algorithm pin, checked before Verify runs.
  if (!KNOWN_ALGORITHMS.has(m1Entry.algorithm) || token.algorithm !== m1Entry.algorithm) {
    return { admit: false, reason: 'alg_mismatch' };
  }

  // ── P1-PUBKEY-FORMAT: M1 carries `kernel.signing_key.public_key` verbatim —
  // an SPKI PEM block (runbook D3) or bare base64. Normalize STRICTLY to the
  // pinned algorithm's canonical SPKI DER before any primitive runs; a key
  // that does not parse is its own refusal, not a signature failure.
  const canonicalPublicKey = normalizeSpkiPublicKey(m1Entry.public_key, m1Entry.algorithm);
  if (canonicalPublicKey === null) return { admit: false, reason: 'malformed_public_key' };

  // ── Step 2: Verify(M1[kid].public_key, token.claims, token.sig)
  const signatureOk = ctx.verify(canonicalPublicKey, token.claims, token.sig, m1Entry.algorithm);
  if (!signatureOk) return { admit: false, reason: 'signature_invalid' };

  // ── Step 3: token.session_id == the device's bound scanning session
  if (token.sessionId !== ctx.boundSessionId) return { admit: false, reason: 'wrong_session' };

  // ── Step 3a: now() <= token.exp, ± 2 time-buckets (RPC §9.3). The
  // tolerance is on LATENESS only (a token already past `exp`, or a device
  // clock running ahead) — there is no analogous "not yet valid" tolerance
  // in the spec text, and `now() <= exp` alone already passes trivially
  // whenever `now()` is before `exp`, so only the reject boundary needs the
  // skew added: reject iff `now() > exp + 2*bucket`.
  if (ctx.nowSeconds > token.exp + toleranceSeconds) return { admit: false, reason: 'expired' };

  // ── Manifest-authority gate (door §3.1): "No M2, an M2 past its
  // downloaded not_after, or an M2 for another session ⇒ the door has NO
  // offline authority and MUST NOT admit." A precondition for evaluating 3b,
  // which reads M2 — checked here, immediately before 3b, so the overall
  // order stays 1 → 2 → 3 → 3a → 3b → 3c → 4 with this gate folded into the
  // step just before 3b needs its input.
  if (!ctx.m2) return { admit: false, reason: 'no_manifest' };
  if (ctx.m2.session_id !== ctx.boundSessionId) return { admit: false, reason: 'manifest_other_session' };
  if (ctx.nowSeconds > ctx.m2.not_after) return { admit: false, reason: 'manifest_expired' };

  const applied = applyM2(ctx.m2, ctx.lastSyncedSeq);
  const atomState = applied[token.atomId];

  // ── 3b.i: atom ∈ M2 (applied set)
  if (!atomState) return { admit: false, reason: 'atom_absent' };
  // ── 3b.ii: M2[atom] carries no applied `revoke` delta
  if (atomState.revoked) return { admit: false, reason: 'atom_revoked' };
  // ── 3b.iii: token.credential_version == M2[atom].credential_version
  if (token.credentialVersion !== atomState.credential_version) return { admit: false, reason: 'stale_version' };
  // ── 3b.iv: M2[atom].ticket_state == 'active'
  if (atomState.ticket_state !== 'active') return { admit: false, reason: 'not_active' };
  // ── 3b.v: M2[atom].resale_state == 'none'
  if (atomState.resale_state !== 'none') return { admit: false, reason: 'listed_locked' };

  // ── 3c: token.key_id == M2[atom].signing_key_id (Wallet §8.3)
  if (token.keyId !== atomState.signing_key_id) return { admit: false, reason: 'wrong_signing_key' };

  // ── Step 4: first-in-wins against the device's local admitted set
  if (ctx.admittedSet.has(token.atomId)) return { admit: false, reason: 'already_admitted' };

  return { admit: true, atomId: token.atomId };
}

// ═════════════════════════════════════════════════════════════════════════
// SCANNER-CONTRACT-v1 — the repository side of the scanner/mobile boundary.
// (`docs/phase2/SCANNER_VERIFIER_CONTRACT.md`; fixtures in
// `tests/fixtures/scanner-contract-v1.json`; suite `tests/scanner-contract.test.ts`.)
//
// The mobile/scanner implementation is NOT in this repository. What IS here is
// the reference decoder + adapters an external scanner must reproduce, so that
// every field the predicate reads is DERIVED from one signed wire string and
// one server-delivered manifest — never supplied alongside them:
//   • `decodeOfflineToken(wire)`  — ONE parse of `header.payload.signature`;
//     `keyId/typ/algorithm` come from the header, `sessionId/atomId/
//     credentialVersion/exp` from the payload, `claims` are the exact bytes
//     `header.payload` (what the signature covers). Exact key sets, strict
//     base64url, uuid-shaped ids, integer times, 64-byte signatures. A caller
//     has no way to inject a parallel `atom_id`/`session_id`: unknown keys
//     make the token malformed, and any byte change to the claims breaks
//     the signature.
//   • `verifyOfflineWire(wire, ctx)` — decode THEN `offlineVerify`; the only
//     entry point a scanner should call (it never constructs `OfflineToken`).
//   • `m1FromWire(rows)` / `m2FromWire(result)` — the `kernel.signing_key`
//     public projection and the `venue.get_door_manifest` result (RPC
//     §20.6.1 reconciled shape) turned into `M1Manifest` / `M2Manifest`,
//     strictly. An M2 whose header lacks `session_id`/`not_after` is refused
//     `manifest_header_incomplete`: without them the door §3.1 authority
//     clause cannot be evaluated, so the door has NO offline authority.
//   • `verifyDoorManifestSignature(artifact, m1, verify, now)` —
//     DOOR-MANIFEST-SIG-v1: the `door-manifest` edge signs the canonical JSON
//     `{manifest_id, manifest_version, session_id, not_after, manifest_digest}`
//     (key order as written, `JSON.stringify`, UTF-8) with ES256 and returns
//     `signature.value` = standard base64 of the RAW `R||S` (64 bytes). The
//     verify key is `M1[signature.key_id]` — the contract REQUIRES the
//     artifact to name `key_id` (today's edge omits it; see the contract doc).
//   • `toDoorReason(reason, atom)` — this module's per-conjunct codes → door
//     §9.2's operator vocabulary; `null` where door §9.2 defines no copy.
// ═════════════════════════════════════════════════════════════════════════

export const MAX_WIRE_TOKEN_LENGTH = 8192;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const B64URL_RE = /^[A-Za-z0-9_-]+$/;
const B64URL_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
const B64URL_REVERSE: Record<string, number> = (() => {
  const map: Record<string, number> = {};
  for (let i = 0; i < B64URL_ALPHABET.length; i++) map[B64URL_ALPHABET[i]] = i;
  return map;
})();

/** Strict unpadded base64url (RFC 4648 §5, as `credential-sign/credential.ts`
 *  emits): no `=`, no whitespace, canonical trailing bits, length % 4 ≠ 1. */
function base64urlDecodeStrict(s: string): Uint8Array | null {
  if (s.length === 0 || s.length % 4 === 1 || !B64URL_RE.test(s)) return null;
  const out: number[] = [];
  let i = 0;
  for (; i + 4 <= s.length; i += 4) {
    const n = (B64URL_REVERSE[s[i]] << 18) | (B64URL_REVERSE[s[i + 1]] << 12) | (B64URL_REVERSE[s[i + 2]] << 6) | B64URL_REVERSE[s[i + 3]];
    out.push((n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff);
  }
  const rem = s.length - i;
  if (rem === 2) {
    const a = B64URL_REVERSE[s[i]], b = B64URL_REVERSE[s[i + 1]];
    if ((b & 0x0f) !== 0) return null;
    out.push(((a << 2) | (b >> 4)) & 0xff);
  } else if (rem === 3) {
    const a = B64URL_REVERSE[s[i]], b = B64URL_REVERSE[s[i + 1]], c = B64URL_REVERSE[s[i + 2]];
    if ((c & 0x03) !== 0) return null;
    out.push(((a << 2) | (b >> 4)) & 0xff, ((b << 4) | (c >> 2)) & 0xff);
  }
  return new Uint8Array(out);
}

function isPlainObjectWithExactKeys(v: unknown, keys: readonly string[]): v is Record<string, unknown> {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return false;
  const own = Object.keys(v as object).sort();
  const want = [...keys].sort();
  if (own.length !== want.length) return false;
  for (let i = 0; i < own.length; i++) if (own[i] !== want[i]) return false;
  return true;
}

function isNonNegativeInt(v: unknown): v is number {
  return typeof v === 'number' && Number.isInteger(v) && v >= 0;
}

/**
 * ONE parse of the compact wire token `header.payload.signature`
 * (`SNATCHIT-TICKET-CRED-V1`, `credential-sign/credential.ts`). Returns the
 * fully-derived `OfflineToken` or `null` for ANY deviation — the scanner must
 * treat `null` as `malformed_token` and never fall back to a looser parse.
 *   header  = exactly { alg: string, kid: uuid, typ: string }
 *   payload = exactly { atom: uuid, exp: int, iat: int, sess: uuid, ver: int }, iat ≤ exp
 *   claims  = UTF-8 bytes of `<headerB64>.<payloadB64>` verbatim (what was signed)
 *   sig     = 64 bytes when alg is a known algorithm (raw R||S for ES256, raw for EdDSA)
 * `header.alg` is INFORMATIONAL — the predicate pins the M1 algorithm and
 * refuses on disagreement; it is carried only so that check can run.
 */
export function decodeOfflineToken(wire: unknown): OfflineToken | null {
  if (typeof wire !== 'string' || wire.length === 0 || wire.length > MAX_WIRE_TOKEN_LENGTH) return null;
  const parts = wire.split('.');
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  const hb = base64urlDecodeStrict(h);
  const pb = base64urlDecodeStrict(p);
  const sig = base64urlDecodeStrict(s);
  if (!hb || !pb || !sig) return null;
  let header: unknown;
  let payload: unknown;
  try {
    header = JSON.parse(new TextDecoder().decode(hb));
    payload = JSON.parse(new TextDecoder().decode(pb));
  } catch {
    return null;
  }
  if (!isPlainObjectWithExactKeys(header, ['alg', 'kid', 'typ'])) return null;
  if (!isPlainObjectWithExactKeys(payload, ['atom', 'exp', 'iat', 'sess', 'ver'])) return null;
  const alg = header.alg, kid = header.kid, typ = header.typ;
  const atom = payload.atom, exp = payload.exp, iat = payload.iat, sess = payload.sess, ver = payload.ver;
  if (typeof alg !== 'string' || typeof kid !== 'string' || typeof typ !== 'string') return null;
  if (!UUID_RE.test(kid)) return null;
  if (typeof atom !== 'string' || !UUID_RE.test(atom)) return null;
  if (typeof sess !== 'string' || !UUID_RE.test(sess)) return null;
  if (!isNonNegativeInt(exp) || !isNonNegativeInt(iat) || !isNonNegativeInt(ver)) return null;
  if (iat > exp) return null;
  if (KNOWN_ALGORITHMS.has(alg) && sig.length !== 64) return null;
  return {
    keyId: kid,
    typ,
    algorithm: alg,
    claims: new TextEncoder().encode(`${h}.${p}`),
    sig,
    sessionId: sess,
    atomId: atom,
    credentialVersion: ver,
    exp,
  };
}

/** The scanner's single entry point: decode, then `OFFLINE-VERIFY-v1`. */
export function verifyOfflineWire(wire: unknown, ctx: OfflineVerifyContext): OfflineVerifyResult {
  const token = decodeOfflineToken(wire);
  if (!token) return { admit: false, reason: 'malformed_token' };
  return offlineVerify(token, ctx);
}

// ── M1 wire adapter — the kernel.signing_key public projection ──────────────

function unixSecondsFromWire(v: unknown, nullMeans: number | null): number | null {
  if (v === null || v === undefined) return nullMeans;
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  if (typeof v === 'string') {
    const ms = Date.parse(v);
    return Number.isFinite(ms) ? Math.floor(ms / 1000) : null;
  }
  return null;
}

/** One `kernel.signing_key` public-projection row (`key_id, scope, event_id,
 *  venue_id, public_key, algorithm, status, not_before, not_after`) → `M1Entry`.
 *  `public_key` is carried verbatim (PEM per runbook D3, or bare base64) —
 *  `offlineVerify` normalizes it. `not_after` NULL ⇒ no upper bound. */
export function m1EntryFromWire(row: unknown): M1Entry | null {
  if (!row || typeof row !== 'object') return null;
  const r = row as Record<string, unknown>;
  if (typeof r.key_id !== 'string' || !UUID_RE.test(r.key_id)) return null;
  if (r.scope !== 'global' && r.scope !== 'per_event' && r.scope !== 'per_venue') return null;
  if (typeof r.public_key !== 'string' || r.public_key.length === 0) return null;
  if (typeof r.algorithm !== 'string') return null;
  if (typeof r.status !== 'string') return null;
  const nb = unixSecondsFromWire(r.not_before, null);
  const na = unixSecondsFromWire(r.not_after, Number.POSITIVE_INFINITY);
  if (nb === null || na === null) return null;
  return {
    key_id: r.key_id,
    scope: r.scope,
    event_id: typeof r.event_id === 'string' ? r.event_id : null,
    venue_id: typeof r.venue_id === 'string' ? r.venue_id : null,
    public_key: r.public_key,
    algorithm: r.algorithm,
    not_before: nb,
    not_after: na,
    status: r.status,
  };
}

/** An array of projection rows → `M1Manifest`; ANY malformed row ⇒ `null`
 *  (a partially-trusted keyring is worse than none). Duplicate key_id ⇒ null. */
export function m1FromWire(rows: unknown): M1Manifest | null {
  if (!Array.isArray(rows)) return null;
  const out: M1Manifest = {};
  for (const row of rows) {
    const e = m1EntryFromWire(row);
    if (!e || out[e.key_id]) return null;
    out[e.key_id] = e;
  }
  return out;
}

// ── M2 wire adapter — venue.get_door_manifest (RPC §20.6.1 reconciled shape) ─

export type M2WireResult =
  | { ok: true; m2: M2Manifest; manifestVersion: number; maxDeltaSeq: number; manifestDigest: string }
  | { ok: false; reason: 'no_open_manifest' | 'manifest_header_incomplete' | 'manifest_malformed' };

function atomEntryFromWire(v: Record<string, unknown>): M2AtomEntry | null {
  if (!isNonNegativeInt(v.credential_version)) return null;
  if (typeof v.signing_key_id !== 'string' || !UUID_RE.test(v.signing_key_id)) return null;
  if (typeof v.ticket_state !== 'string' || typeof v.resale_state !== 'string') return null;
  return {
    credential_version: v.credential_version,
    signing_key_id: v.signing_key_id,
    ticket_state: v.ticket_state,
    resale_state: v.resale_state,
  };
}

/**
 * `{ open, manifest_id, manifest_version, session_id, opened_at, not_after,
 *    manifest_digest, max_delta_seq, entries[], deltas[] }` → `M2Manifest`.
 * `open:false` / `status:'no_open_manifest'|'no_open_episode'` ⇒ `no_open_manifest`.
 * A result with the per-atom fields but WITHOUT `session_id` + `not_after`
 * (the header fields door §3.1's authority clause reads — the shape the 086
 * RPC body emits today) ⇒ `manifest_header_incomplete`: the door MUST NOT
 * admit offline from it. Entries become the base snapshot keyed by
 * `ticket_atom_id`; deltas keep `seq`/`op`; an `add` carries the full entry.
 */
export function m2FromWire(result: unknown): M2WireResult {
  if (!result || typeof result !== 'object') return { ok: false, reason: 'manifest_malformed' };
  const r = result as Record<string, unknown>;
  if (r.open === false || r.status === 'no_open_manifest' || r.status === 'no_open_episode') {
    return { ok: false, reason: 'no_open_manifest' };
  }
  if (typeof r.manifest_id !== 'string' || !UUID_RE.test(r.manifest_id)) return { ok: false, reason: 'manifest_malformed' };
  if (!Array.isArray(r.entries) || !Array.isArray(r.deltas)) return { ok: false, reason: 'manifest_malformed' };
  const notAfter = unixSecondsFromWire(r.not_after, null);
  if (typeof r.session_id !== 'string' || !UUID_RE.test(r.session_id) || notAfter === null) {
    return { ok: false, reason: 'manifest_header_incomplete' };
  }
  const base: Record<string, M2AtomEntry> = {};
  for (const e of r.entries) {
    if (!e || typeof e !== 'object') return { ok: false, reason: 'manifest_malformed' };
    const v = e as Record<string, unknown>;
    if (typeof v.ticket_atom_id !== 'string' || !UUID_RE.test(v.ticket_atom_id)) return { ok: false, reason: 'manifest_malformed' };
    const entry = atomEntryFromWire(v);
    if (!entry) return { ok: false, reason: 'manifest_malformed' };
    base[v.ticket_atom_id] = entry;
  }
  const deltas: M2Delta[] = [];
  for (const d of r.deltas) {
    if (!d || typeof d !== 'object') return { ok: false, reason: 'manifest_malformed' };
    const v = d as Record<string, unknown>;
    if (!isNonNegativeInt(v.seq) || typeof v.ticket_atom_id !== 'string' || !UUID_RE.test(v.ticket_atom_id)) {
      return { ok: false, reason: 'manifest_malformed' };
    }
    if (v.op === 'revoke') {
      deltas.push({ seq: v.seq, op: 'revoke', atom: v.ticket_atom_id });
    } else if (v.op === 'add') {
      const entry = atomEntryFromWire(v);
      if (!entry) return { ok: false, reason: 'manifest_malformed' };
      deltas.push({ seq: v.seq, op: 'add', atom: v.ticket_atom_id, entry });
    } else {
      return { ok: false, reason: 'manifest_malformed' };
    }
  }
  return {
    ok: true,
    m2: { manifest_id: r.manifest_id, session_id: r.session_id, not_after: notAfter, base, deltas },
    manifestVersion: isNonNegativeInt(r.manifest_version) ? r.manifest_version : 0,
    maxDeltaSeq: isNonNegativeInt(r.max_delta_seq) ? r.max_delta_seq : 0,
    manifestDigest: typeof r.manifest_digest === 'string' ? r.manifest_digest : '',
  };
}

// ── DOOR-MANIFEST-SIG-v1 — verifying the door-manifest edge's signature ─────

export interface DoorManifestSignedHeader {
  manifest_id: string;
  manifest_version: number;
  session_id: string;
  /** ISO-8601 as the RPC returns it — signed VERBATIM (string), not re-parsed. */
  not_after: string;
  manifest_digest: string;
}

/** The exact bytes the `door-manifest` edge signs: `JSON.stringify` of the
 *  five fields in THIS key order (`canonicalManifestDigestBytes` in
 *  `door-manifest/index.ts`), UTF-8. A verifier MUST rebuild them from the
 *  header it received — never trust a "signed_bytes" field. */
export function canonicalDoorManifestSignedBytes(h: DoorManifestSignedHeader): Uint8Array {
  const canonical = {
    manifest_id: h.manifest_id,
    manifest_version: h.manifest_version,
    session_id: h.session_id,
    not_after: h.not_after,
    manifest_digest: h.manifest_digest,
  };
  return new TextEncoder().encode(JSON.stringify(canonical));
}

export type DoorManifestSignatureReason =
  | 'unsigned'            // signature: null — TLS-only artifact; the caller decides policy
  | 'malformed_artifact'
  | 'missing_key_id'      // the artifact names no key_id — v1 REQUIRES it
  | 'unsupported_alg'
  | 'unknown_key'
  | 'key_revoked'
  | 'key_window'
  | 'alg_mismatch'
  | 'malformed_public_key'
  | 'malformed_signature'
  | 'signature_invalid';

export type DoorManifestSignatureResult = { ok: true; keyId: string } | { ok: false; reason: DoorManifestSignatureReason };

/**
 * Verifies a `door-manifest` artifact `{ manifest, signature }` against M1.
 * `signature` = `{ key_id, algorithm, value }` where `value` is STANDARD
 * base64 of the raw 64-byte `R||S` (the edge base64-encodes what
 * `KmsSigner.sign` returns, which is already `derToRawEcdsaP256`'d). The key
 * is `M1[key_id]` with the same status/window/alg-pin/normalization rules as
 * a ticket credential (steps 1, PFA-PT-8, P1-PUBKEY-FORMAT) — a manifest
 * signature is verified under exactly the discipline a token is.
 */
export function verifyDoorManifestSignature(
  artifact: unknown,
  m1: M1Manifest,
  verify: VerifyPrimitive,
  nowSeconds: number,
): DoorManifestSignatureResult {
  if (!artifact || typeof artifact !== 'object') return { ok: false, reason: 'malformed_artifact' };
  const a = artifact as Record<string, unknown>;
  const m = a.manifest as Record<string, unknown> | undefined;
  if (!m || typeof m !== 'object') return { ok: false, reason: 'malformed_artifact' };
  if (a.signature === null || a.signature === undefined) return { ok: false, reason: 'unsigned' };
  const s = a.signature as Record<string, unknown>;
  if (typeof s !== 'object') return { ok: false, reason: 'malformed_artifact' };
  if (typeof m.manifest_id !== 'string' || !isNonNegativeInt(m.manifest_version) || typeof m.session_id !== 'string'
      || typeof m.not_after !== 'string' || typeof m.manifest_digest !== 'string') {
    return { ok: false, reason: 'malformed_artifact' };
  }
  if (typeof s.key_id !== 'string' || !UUID_RE.test(s.key_id)) return { ok: false, reason: 'missing_key_id' };
  if (typeof s.algorithm !== 'string' || !KNOWN_ALGORITHMS.has(s.algorithm)) return { ok: false, reason: 'unsupported_alg' };
  const entry = m1[s.key_id];
  if (!entry) return { ok: false, reason: 'unknown_key' };
  if (entry.status === 'revoked') return { ok: false, reason: 'key_revoked' };
  if (nowSeconds < entry.not_before || nowSeconds > entry.not_after) return { ok: false, reason: 'key_window' };
  if (!KNOWN_ALGORITHMS.has(entry.algorithm) || entry.algorithm !== s.algorithm) return { ok: false, reason: 'alg_mismatch' };
  const canonicalKey = normalizeSpkiPublicKey(entry.public_key, entry.algorithm);
  if (canonicalKey === null) return { ok: false, reason: 'malformed_public_key' };
  if (typeof s.value !== 'string') return { ok: false, reason: 'malformed_signature' };
  const sig = base64DecodeStrict(s.value);
  if (!sig || sig.length !== 64) return { ok: false, reason: 'malformed_signature' };
  const bytes = canonicalDoorManifestSignedBytes({
    manifest_id: m.manifest_id,
    manifest_version: m.manifest_version,
    session_id: m.session_id,
    not_after: m.not_after,
    manifest_digest: m.manifest_digest,
  });
  if (!verify(canonicalKey, bytes, sig, entry.algorithm)) return { ok: false, reason: 'signature_invalid' };
  return { ok: true, keyId: s.key_id };
}

// ── door §9.2 operator vocabulary ───────────────────────────────────────────

export type DoorOperatorReason =
  | 'wrong_session' | 'voided' | 'duplicate' | 'listed_locked' | 'refund_hold' | 'dispute_hold' | 'version_stale';

/** This module's per-conjunct reason → door §9.2's operator-facing reason
 *  (VD §12.5 copy). `null` = door §9.2 defines no operator copy for this
 *  refusal (signature/key/manifest-authority/malformed refusals): the scanner
 *  shows its generic "not a valid pass for this door" state — it MUST NOT
 *  map these onto a §9.2 reason. `atom` is the applied M2 entry for the
 *  token's atom, when one exists, used to split `not_active`/`listed_locked`. */
export function toDoorReason(reason: OfflineVerifyReason, atom?: AppliedM2Entry | null): DoorOperatorReason | null {
  switch (reason) {
    case 'wrong_session':
    case 'atom_absent':
      return 'wrong_session';
    case 'atom_revoked':
      return 'voided';
    case 'not_active':
      if (atom?.ticket_state === 'scanned') return 'duplicate';
      if (atom?.ticket_state === 'voided') return 'voided';
      return null;
    case 'listed_locked':
      if (atom?.resale_state === 'refund_hold') return 'refund_hold';
      if (atom?.resale_state === 'dispute_hold') return 'dispute_hold';
      return 'listed_locked';
    case 'stale_version':
    case 'wrong_signing_key':
      return 'version_stale';
    case 'already_admitted':
      return 'duplicate';
    default:
      return null;
  }
}
