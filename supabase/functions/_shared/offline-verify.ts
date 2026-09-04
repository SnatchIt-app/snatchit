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
  // Step 0 — domain + algorithm shape (before any key/signature work)
  | 'wrong_typ' // token.typ != DOMAIN — not a ticket credential
  | 'unsupported_alg' // token.algorithm not in {EdDSA, ES256}
  // Step 1 — M1 key lookup
  | 'unknown_key' // token.key_id ∉ M1
  | 'key_revoked' // M1[kid].status == 'revoked'
  | 'key_window' // now() ∉ [M1[kid].not_before, not_after]
  // PFA-PT-8 alg pin, evaluated between step 1 and step 2
  | 'alg_mismatch' // token.algorithm != M1[kid].algorithm
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

  // ── Step 2: Verify(M1[kid].public_key, token.claims, token.sig)
  const signatureOk = ctx.verify(m1Entry.public_key, token.claims, token.sig, m1Entry.algorithm);
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
