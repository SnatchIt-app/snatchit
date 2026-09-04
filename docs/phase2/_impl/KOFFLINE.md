# KOFFLINE — `OFFLINE-VERIFY-v1` pure predicate core (Build B)

DARK/local implementation report. **Not deployed, not committed, no production or Supabase MCP
touch, no scanner UI.** Covers `M1+M2` door admission only.

---

## 0. WHAT WAS DONE

| File | Status |
|---|---|
| `supabase/functions/_shared/offline-verify.ts` | NEW — pure, import-free predicate core |
| `tests/offline-verify.test.ts` | NEW — 36 cases |
| `docs/phase2/_impl/KOFFLINE.md` | NEW — this report |

Nothing else was touched. `credential-sign/` was read only (for its `VerifyPrimitive`
pattern and token/claims conventions — see §1) and never imported from or modified. No
migration or pgTAP file was touched.

---

## 1. THE MODULE'S API

`supabase/functions/_shared/offline-verify.ts`, no imports, no I/O, no mutation.

```ts
// M1 — the key manifest (edge §5.4.2 + migration 103 / PFA-PT-8)
interface M1Entry { key_id, scope, event_id?, venue_id?, public_key, algorithm, not_before, not_after, status }
type M1Manifest = Record<key_id, M1Entry>

// M2 — the per-session door/ticket manifest (door §9.1/§10.1/§10.3/§10.3a)
interface M2AtomEntry { credential_version, signing_key_id, ticket_state, resale_state }
type M2Delta = { seq, op:'add', atom, entry: M2AtomEntry } | { seq, op:'revoke', atom }
interface M2Manifest { manifest_id, session_id, not_after, base: Record<atom, M2AtomEntry>, deltas: M2Delta[] }
interface AppliedM2Entry extends M2AtomEntry { revoked: boolean }
type AppliedM2 = Record<atom, AppliedM2Entry>
function applyM2(m2: M2Manifest, lastSyncedSeq: number): AppliedM2   // the applied(lastSyncedSeq) reducer

// The device's local first-in-wins set
type LocalAdmittedSet = ReadonlySet<atom_id>

// The token, at the predicate's own level of abstraction (see §2)
interface OfflineToken { keyId, algorithm, claims: Uint8Array, sig: Uint8Array, sessionId, atomId, credentialVersion, exp }
type VerifyPrimitive = (publicKey, message, signature, algorithm) => boolean

type OfflineVerifyReason = 'unknown_key' | 'key_revoked' | 'key_window' | 'alg_mismatch'
  | 'signature_invalid' | 'wrong_session' | 'expired' | 'no_manifest' | 'manifest_other_session'
  | 'manifest_expired' | 'atom_absent' | 'atom_revoked' | 'stale_version' | 'not_active'
  | 'listed_locked' | 'wrong_signing_key' | 'already_admitted'
type OfflineVerifyResult = { admit: true, atomId } | { admit: false, reason: OfflineVerifyReason }

interface OfflineVerifyContext {
  m1: M1Manifest; m2: M2Manifest | null | undefined; lastSyncedSeq: number;
  boundSessionId: string; nowSeconds: number; timeBucketSeconds?: number;  // default 30
  admittedSet: LocalAdmittedSet; verify: VerifyPrimitive;
}
const DEFAULT_TIME_BUCKET_SECONDS = 30

function offlineVerify(token: OfflineToken, ctx: OfflineVerifyContext): OfflineVerifyResult
```

**Decoupling from `credential-sign/credential.ts` (brief requirement).** The crypto verify
(`VerifyPrimitive`) and key resolution (the caller passes an already-built `M1Manifest`, not a
resolver callback into KMS/DB) are both injected, mirroring `credential.ts`'s
`VerifyPrimitive` shape *without importing it* — this module has zero imports, including from
`credential-sign/`. `credential.ts` was read only to confirm the wire token's real shape
(`header={alg,kid,typ}`, `payload={atom,exp,iat,sess,ver}`, three-segment base64url-JSON
compact token) so `offline-verify.ts`'s abstraction stays consistent with it, without coupling
to its `verifyToken`/`PublicKeyResolver` signatures.

---

## 2. TOKEN ABSTRACTION — a deliberate, documented modeling choice

`OFFLINE-VERIFY-v1` step 2 reads `Verify(M1[kid].public_key, token.claims, token.sig)` — the
predicate text itself already treats `token` as a decoded structure with named fields
(`token.key_id`, `token.session_id`, `token.credential_version`, `token.exp`, `token.claims`,
`token.sig`). `offlineVerify` starts from exactly that abstraction (`OfflineToken`): `claims`/
`sig` are opaque bytes only `verify` interprets, and `sessionId`/`atomId`/`credentialVersion`/
`exp` are separate structured fields the predicate compares directly. Wire decoding (the
base64url/canonical-JSON compact-token framing `credential-sign/credential.ts` defines for
`SNATCHIT-TICKET-CRED-V1`) is a scanner-SDK concern one layer up, out of this module's scope.

**Integration invariant this implies, not enforced by the type system — flagged, not a
defect in this module.** The predicate is only sound if the caller populates `OfflineToken`'s
structured fields by decoding them from the SAME `claims` bytes passed as `sig`'s message —
i.e. `sessionId`/`atomId`/`credentialVersion`/`exp` must be derived post-decode, never supplied
from an independent, untrusted source alongside a genuine `claims`/`sig` pair for a different
atom. This is exactly how `credential-sign/credential.ts`'s own `decodeTokenStructure` +
`verifyToken` behave (one parse, one set of derived fields, signature re-verified over the
same bytes) — so a scanner SDK built the obvious way already satisfies it. Noted as a
candidate integration-contract line for the scanner-SDK spec; not a `PFA` against
`OFFLINE-VERIFY-v1` itself, since the fenced block already operates at this same `token.X`
abstraction level.

---

## 3. REASON-CODE ↔ CONJUNCT MAP

Evaluation order matches the fenced block exactly: **1 → [alg pin] → 2 → 3 → 3a → [manifest
gate] → 3b(i..v) → 3c → 4**, short-circuiting at the first failure.

| Order | Conjunct | Check | Reason on failure |
|:-:|---|---|---|
| 1 | step 1 | `token.key_id ∈ M1` | `unknown_key` |
| 1 | step 1 | `M1[kid].status ≠ 'revoked'` | `key_revoked` |
| 1 | step 1 | `now() ∈ [not_before, not_after]` | `key_window` |
| — | PFA-PT-8 | `token.algorithm == M1[kid].algorithm` | `alg_mismatch` |
| 2 | step 2 | `Verify(M1[kid].public_key, token.claims, token.sig)` | `signature_invalid` |
| 3 | step 3 | `token.session_id == boundSessionId` | `wrong_session` |
| 3a | step 3a | `now() <= token.exp + 2×bucket` | `expired` |
| — | manifest gate | M2 present | `no_manifest` |
| — | manifest gate | `M2.session_id == boundSessionId` | `manifest_other_session` |
| — | manifest gate | `now() <= M2.not_after` | `manifest_expired` |
| 3b.i | | `atom ∈ applied(M2)` | `atom_absent` |
| 3b.ii | | no applied `revoke` | `atom_revoked` |
| 3b.iii | | `token.credential_version == M2[atom].credential_version` | `stale_version` |
| 3b.iv | | `M2[atom].ticket_state == 'active'` | `not_active` |
| 3b.v | | `M2[atom].resale_state == 'none'` | `listed_locked` |
| 3c | | `token.key_id == M2[atom].signing_key_id` | `wrong_signing_key` |
| 4 | | `atom ∉ admittedSet` | `already_admitted` |

**Manifest-authority-gate placement — a documented reading, not stated as a numbered step in
the fenced block.** The block states "No M2, an M2 past its downloaded `not_after`, or an M2
for another session ⇒ NO offline authority" as a coda after step 4, but the check is logically
a *precondition* for evaluating 3b (which reads M2) — it cannot be deferred to "after step 4"
without evaluating 3b against a manifest that may not exist. Placed here, immediately before
3b, so the overall sequence still reads 1→2→3→3a→3b→3c→4 with the gate folded into "the step
just before 3b needs its input." No test in the brief cross-checks ordering *among*
`no_manifest`/`manifest_other_session`/`manifest_expired` against each other (each fixture is
independent), so this placement choice is low-risk but is called out here as a reading, per
the brief's instruction to document ambiguity resolutions.

**This module's reason vocabulary is NOT door §9.2's operator-facing map — flagged as a
possible `PFA` candidate.** Door §9.2's reader-facing table collapses several conjuncts onto
shared UI copy: `wrong_session` doubles for "atom absent from M2" (its complete-snapshot
ruling means absence *means* wrong-session at the door), `voided` covers both an applied
`revoke` delta and `ticket_state='voided'`, and `version_stale` covers **both** 3b.iii *and*
3c. That collapsing is correct for an operator screen but useless for isolating which conjunct
a test fixture exercises — and edge §5.4.3 itself requires "a unit/integration regression test
covering every conjunct **separately**." This module's `OfflineVerifyReason` is therefore
ONE CODE PER CONJUNCT (`atom_absent` ≠ `wrong_session`; `atom_revoked` ≠ `not_active`;
`stale_version` ≠ `wrong_signing_key`), which is what the brief's own reason list specifies
and what its test list demands per-conjunct. A door-facing UI would need a translation layer
from this module's codes to door §9.2's six operator reasons (`wrong_session`, `voided`,
`duplicate`, `listed_locked`, `refund_hold`/`dispute_hold`, `version_stale`) — that layer does
not exist yet anywhere in the corpus I found, and is worth a `PFA` line item so a future
scanner-UI build doesn't invent its own ad hoc mapping.

Similarly, this module's **3b.v collapses `listed`/`locked`/`refund_hold`/`dispute_hold` into
one reason, `listed_locked`**, exactly as the brief specifies ("refunded/dispute-held ⇒
`listed_locked`"). Door §9.2 gives `refund_hold`/`dispute_hold` their own operator reasons
with their own remedy copy (`kernel.cancel_refund_request`, RPC §17.3). Same translation-layer
gap as above — flagged once, not repeated.

---

## 4. TIME-BUCKET / SKEW READING

**Formula:** reject `expired` iff `nowSeconds > token.exp + 2 × timeBucketSeconds`; equivalently
admit-side iff `token.exp >= nowSeconds - 2 × timeBucketSeconds` (brief's own phrasing,
`BRIEF_B_OFFLINE.md` line 37). The tolerance is applied to the LATE side only — a token not yet
expired (`nowSeconds <= token.exp`) trivially passes with no skew arithmetic needed; there is
no analogous "not yet valid" grace period anywhere in the corpus for `token.exp`, so none is
added here.

**Default `timeBucketSeconds = 30`**, per `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md`
§9.3 / owner-confirmed `R-22` (`MP-1`): *"A time-bucket is `30 seconds`, so `± 2 time-buckets`
is `± 60 seconds`"* — stated there as "a fixed protocol constant rather than a config key…
signer and long-offline verifier must agree, which a runtime-tunable value cannot guarantee."
`DEFAULT_TIME_BUCKET_SECONDS = 30` is exported; `timeBucketSeconds` remains an
`OfflineVerifyContext` parameter (overridable, mainly for the test suite's own skew-boundary
cases) rather than hard-coded, per the brief's explicit instruction to keep it a parameter.
Verified against the spec's exact wording — this was NOT left to inference; RPC §9.3 states the
magnitude explicitly (also cross-checked at `PHASE_2_RPC_FUNCTION_CONTRACTS.md:7326`, ratified
row `R-22`).

---

## 5. FIRST-IN-WINS (STEP 4) MUTATION CONTRACT

`offlineVerify` reads `ctx.admittedSet` (via `.has(atomId)`) but never writes it, on admit or
otherwise. Confirmed by an explicit test (`does not mutate the caller's admittedSet on admit`).
**The caller records the atom** — e.g. `admittedSet.add(result.atomId)` — immediately after
receiving `{ admit: true }`, before the next scan is evaluated against the same set. This was
the brief's own explicit choice-point ("document"): a pure predicate that mutates a
caller-owned `Set` as a side effect on the happy path stops being idempotently testable against
a fixed fixture (calling it twice against the same fixture would then admit once and reject
once purely from internal state, not from two different inputs) — which defeats the reason
this module is split out as a pure core in the first place. `OfflineVerifyResult`'s admit arm
carries `atomId` specifically so the caller doesn't need to thread the original token back
through just to know what to record.

---

## 6. TEST COUNTS

```
$ npx vitest run tests/offline-verify.test.ts
 Test Files  1 passed (1)
      Tests  36 passed (36)
```

Coverage by brief requirement:
- happy path admit — 1
- old-owner screenshot (`stale_version`, independently proving the signature verifies; then a
  fresh token at the bumped version admits) — 2
- refund/dispute/`paid_pending_transfer`-shaped locks → `listed_locked` — 4 (`it.each`)
- voided/scanned/expired/issued `ticket_state` → `not_active` — 4 (`it.each`)
- `atom_absent`, `atom_revoked` — 2
- `wrong_session`, `expired` beyond skew, admit within skew, custom-bucket override — 4
- `unknown_key`, `key_revoked`, `key_window` — 3
- rotation: admit under in-window K1 while K2 is active; `kid=K2` claimed but signed by K1 ⇒
  `signature_invalid`; `wrong_signing_key` (3c) — 3
- alg-confusion (PFA-PT-8) ⇒ `alg_mismatch` before any signature check — 1
- tamper detection: mutated claims, substituted public key for the same `kid`, corrupted
  signature bytes — 3
- manifest-authority gate: `no_manifest`, `manifest_other_session`, `manifest_expired` — 3
- double-scan ⇒ `already_admitted`; no-mutation-on-admit proof — 2
- applied-set correctness: revoke-within-`lastSyncedSeq` ⇒ `atom_revoked` (with an explicit
  proof that the PRE-delta applied view still admits, isolating the property); a delta beyond
  `lastSyncedSeq` is NOT applied; an `add` delta supplements a brand-new atom — 3
- `DEFAULT_TIME_BUCKET_SECONDS === 30` — 1

Total: 36 (matches the run above).

**Standalone strict type-check** (the root `tsconfig.json` excludes `supabase/functions`
entirely — Deno edge modules use URL imports it can't resolve — so `npm run typecheck` does not
cover this file; ad hoc `tsc --noEmit --strict` against just the two new files is clean, exit
0):

```
$ npx tsc --noEmit --strict --target es2020 --module esnext --moduleResolution bundler \
    --types node,vitest --esModuleInterop \
    supabase/functions/_shared/offline-verify.ts tests/offline-verify.test.ts
(no output, exit 0)
```

**Pre-existing, out-of-scope failure observed and NOT caused by this build.** `npx vitest run`
(full suite) shows `tests/credential-sign.test.ts` currently red — **6 failing, 17 passing**,
independent of whether `tests/offline-verify.test.ts` runs at all (reproduced by running
`credential-sign.test.ts` alone). Root cause: `supabase/functions/credential-sign/credential.ts`
is mid-edit by another agent on this same branch (uncommitted local diff, +269/-24, adding its
own `alg_mismatch` reason for the same PFA-PT-8 algorithm pin this build reads about) — the
failures are that in-progress work's fixtures not yet lining up with its own new code, nothing
to do with `offline-verify.ts`. Per the brief, `credential-sign/` is explicitly out of scope
("Do NOT modify") and was left untouched. Full-suite tally at the time of this report:
`542 passed | 6 failed` — all 6 failures in `credential-sign.test.ts`; `offline-verify.test.ts`
contributes 36/36 passing to that total.

---

## 7. SPEC AMBIGUITIES RESOLVED (candidate `PFA` items)

1. **Reason-vocabulary layering (§3 above).** This module's per-conjunct reason codes are not
   door §9.2's operator-facing map, despite both nominally citing "door §9.2's map" (brief line
   35: *"the exact door §9.2 reason code"*, which the door §9.2 table itself does not actually
   provide at this granularity). Recommend either (a) a documented translation layer between
   this module's codes and door §9.2's six UI reasons, owned by whichever build ships the
   scanner UI, or (b) an explicit note in edge §5.4.3/door §9.2 that the "test every conjunct
   separately" requirement necessarily implies a finer internal vocabulary than the UI map, so
   future implementers don't treat the two as the same list.
2. **Manifest-authority-gate ordering (§3 above).** The fenced block states the "no M2" rule as
   a coda, not a numbered step; this implementation places it as a precondition immediately
   before 3b. Recommend the next edit to `OFFLINE-VERIFY-v1` fold it in explicitly as, e.g.,
   step "3b-gate", so mirrors don't each pick their own placement.
3. **Token/claims abstraction boundary (§2 above).** Worth a line in the scanner-SDK
   integration spec (not `OFFLINE-VERIFY-v1` itself) stating that `token.session_id`,
   `token.credential_version`, `token.exp`, and the atom identifier must be derived from the
   same decoded bytes covered by `token.sig` — implicit today, enforced by no test outside this
   note.

No predicate conjunct was weakened or added; all three items above are packaging/documentation
gaps around the predicate, not changes to `ADMIT(token)` itself.
