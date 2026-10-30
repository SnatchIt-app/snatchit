# Credential Signing + Ticket Cryptographic Trust + SALEABLE (A8a′) — Implementation Report

**Package 102 · 2026-09-03 · DARK / UNAPPLIED / UNDEPLOYED**
Branch `feature/venue-native-and-product-v2` · repo `snatchit-consol` · base HEAD `d16ad7f`.

> **THIS IS NOT PRODUCTION AUTHORIZATION.** Nothing here was applied to production, deployed, or run
> against a live KMS/Stripe. No signing key was created; no KMS ceremony was run; no feature flag was
> enabled; no secret was rotated; no production row was mutated. Production inspection was READ-ONLY.
> The credential signer's KMS adapter throws unconditionally (`UnconfiguredKmsSigner`) — the code
> **cannot** sign a credential in this state. The deletion post-event hold remains owner-unset
> (untouched). Tax remains unsolved and fail-closed (see §7 / PFA-PT-7).

---

## 1. What this package delivers

Three things the frozen architecture required but no code had yet built, plus the two owner-directed
gates for this train — all DARK:

1. **`kernel.get_ticket_signing_context(uuid)`** (migration 102, NEW kernel function) — the single
   server-derived authority the credential signer reads. Owner-gated; returns the frozen signing
   context (atom, session, credential_version, pinned key_id, kms_handle_ref, public_key, issued_at,
   exp, ttl, domain) or a typed refusal. The signer chooses **no** fact itself.
2. **`credential-sign` edge** (`supabase/functions/credential-sign/`, DARK, `verify_jwt: true`) — the
   synchronous, stateless, on-demand signer. Pure token builder/verifier in `credential.ts`; I/O shell
   in `index.ts`; KMS adapter stubbed to throw.
3. **A8a′ SALEABLE gate** on `catalog.publish_event`'s `on_sale` transition (migration 102, body-only
   re-create of 081) — the ratified **reading B** of the on_sale/SALEABLE ambiguity.
4. **`signing.%` trust-root dual-control** in `catalog.set_platform_config` (migration 102, body-only
   re-create of 093) — closes adversarial finding P1-1 / owner §21.
5. **Governance:** PFA-PT-6 (wire format, from CRYPTO-IMPL), PFA-PT-7 (tax locus held), PFA-PT-8 (door
   alg-pinning).

Migrations 093–101 are IMMUTABLE and were not edited. 102 touches them only via `create or replace`
(no DROP, no column/table change to anything they own). Gate-2 public census is unchanged
(tables=27 functions=70 policies=37 triggers=26).

---

## 2. The frozen credential model (restated, not re-derived)

The prior activation audit (`FINAL_ACTIVATION_BLOCKER_RULINGS.md` ITEM (iii)) framed the missing signer
as needing "an additive schema change … for signature storage." That framing is **superseded by the
frozen contract itself**: `PHASE_2_EDGE_FUNCTION_SPEC.md` §3.2/§5 (C33) specifies a **STATELESS**
credential —

- the signature is **never stored**; `credential-sign` re-derives it on demand;
- `kernel.tickets.credential_version` (bumped on custody move/void by the RPCs 102 does not touch) is
  the **currency mechanism** — a version bump invalidates every previously issued token via the door's
  M2 check, not by revoking a stored signature;
- the token is a compact signed object over the six frozen claims `{atom_id, session_id,
  credential_version, key_id, issued_at, exp}`; short TTL (`credential.app_ttl_interval`, seed "4 hours");
- idempotency is a **business-level** property over `(atom_id, credential_version)` — there is **no**
  dedup row, **no** signature-storage table, **no** async batch signer.

So the genuine gaps were (a) the on-demand `credential-sign` edge, (b) a DB authority that derives the
signing context under one ownership check in one transaction, and (c) the wire encoding the freeze left
as prose. This package builds exactly those. It adds **no** signature-storage table and **no** async
signer — either would contradict the frozen model.

---

## 3. `kernel.get_ticket_signing_context` — the signing authority

`supabase/migrations/102_…sql` PART 1. `SECURITY DEFINER`, `set search_path=''`, granted `authenticated`
(anon/public revoked). Returns `jsonb`.

**Ownership gate.** `auth.uid()` must equal the atom's live `current_owner_id`. A non-owner AND a
non-existent atom both fall to the SAME refusal `{status:'refused', code:'not_owner'}` — a probe cannot
distinguish "wrong owner" from "no such atom" (no existence oracle). §3.2 contracts no separate
`not_found`.

**Terminal gate.** `state in ('voided','scanned','expired')` → `atom_terminal`. The ticket `state`
domain is exactly `{issued,active,scanned,voided,expired}` (079:41-42, verified), so the live signable
states are `issued` and `active` — both sign. `resale_state` is **deliberately excluded**: §3.2 states a
listed/locked atom still signs (the door refuses listed/locked at scan), and OFFLINE-VERIFY-v1 3b.v
(`resale_state='none'`) is a **door admission** check, not a signing precondition. A `refund_hold` /
`dispute_hold` atom is `state='active'` and is refused at the same door conjunct, not here.

**Pinned-key resolution (§5.2), NOT a fresh scope lookup.** The function reads the atom's OWN
`signing_key_id` (pinned at issue/transfer) and verifies it is `active` and inside `[not_before,
not_after)`. `not_before` is `NOT NULL` (083:59, verified), so the window test is exact. Missing /
inactive / out-of-window → `signing_key_unavailable` (ops-critical, §3.2 → 500 + Sentry). It never
re-resolves to a different active key — that would silently sign under a key the atom was never minted
under, which §5.2 forbids ("mid-event rotation does not orphan already-issued credentials").

**No private material.** `kms_handle_ref` is an opaque KMS ARN/handle (never key material). It is
column-scoped OUT of every client grant on `kernel.signing_key` (083:114); the `SECURITY DEFINER`
function is the controlled door that surfaces it to the owner-gated caller. `public_key` is the verify
key, already client-readable. Possessing the handle grants no signing ability without the KMS IAM role
the edge alone holds.

**Writes no custody.** No `credential_version` bump, no ownership_log row (§3.2 "No state write —
signing does not mutate custody"). The one write is an optional, non-secret `kernel.admin_audit`
observability row (atom, version, key, outcome-code) so a refusal spike is greppable.

---

## 4. `credential-sign` edge (DARK) + the wire format (PFA-PT-6)

`credential.ts` — the PURE, import-free core (base64url, canonical JSON, header/payload builders,
structural decode, verify), so the vitest suite exercises the exact bytes that reach a KMS signature.
`index.ts` — the I/O shell (HTTP, auth, Supabase client, KMS adapter, Sentry, rate limit).

**Wire format (PFA-PT-6, pending owner signature):**
`token = b64url(header) . b64url(payload) . b64url(sig)` (JWS-compact shaped).
- header (canonical JSON, sorted keys, no whitespace): `{ "alg": "EdDSA"|"ES256", "kid": <key_id>,
  "typ": "SNATCHIT-TICKET-CRED-V1" }`.
- payload: `{ "atom", "exp", "iat", "sess", "ver" }` — the other five frozen claims; only machine-
  checkable facts, no display fields (a display field would make two credentials for the same
  atom+version sign differently, breaking the business-idempotency argument).

**Domain separation.** `typ` sits INSIDE the signed header, so a signature over a ticket credential can
never be replayed as a wallet/door manifest — changing `typ` changes the signed bytes. Proven by a
constructed test (forge a different `typ`, reuse a genuine signature → fails).

**Verify is JWS-correct.** `verifyToken` re-derives `signedBytes` from the token's OWN literal
`headerB64.payloadB64` segments (not a re-serialization), so a canonicalization-confusion attack cannot
change the signed bytes without changing the string the signature covers. The public key is resolved by
`kid` against a TRUSTED keyring — never a key embedded in the token. `verifyToken` proves
**authenticity**, not **admissibility**: it does not check `credential_version` currency or `session_id`
binding — those are the door's M2/live concern (§5.4.3, "Signature authenticity ≠ current
admissibility").

**Edge is DARK.** The shipped `UnconfiguredKmsSigner.sign` throws `kms_provider_unconfigured` — a
permanent 500 (no retry). Selecting a real AWS KMS / GCP KMS / CloudHSM adapter is a ceremony-time
decision made by a separate change. The request body carries only `{ticket_atom_id}`; the signed bytes
are built ENTIRELY from the DB context (`buildCanonicalPayload(ctx).signedBytes`) — there is no path
from any client input into the signed bytes, and no client-supplied version/key is accepted (§2.4 "the
signer signs one type only"). The RPC is called AS THE OWNER (forwarded JWT + anon key, schema kernel)
— never service_role, so the ownership check binds. Refusal→HTTP mapping: `not_owner`→403 (Sentry
message, fraud signal), `atom_terminal`→409, `signing_key_unavailable`→500 (Sentry exception), KMS
transient→503+Retry-After, rate-limiter fault→503 (fail closed), over limit→429. The token, payload,
and key material are NEVER logged (enforced by a typed log-field set).

---

## 5. A8a′ — the SALEABLE gate on `publish_event`, exactly as ratified (reading B)

**The ruling.** `FINAL_ACTIVATION_BLOCKER_RULINGS.md` ITEM (i) records that ratified A8 is AMBIGUOUS on
the SALEABLE enforcement locus and that the choice — reading A (on_sale is display-only; SALEABLE gates
only checkout) vs reading B / **A8a′** (SALEABLE also gates the transition) — is **the owner's**. The
Train-3 owner direction selects **A8a′**: `on_sale` must require the server-derived SALEABLE
prerequisites.

**What A8a′'s ratified text scopes the gate to.** The A8a′ text requires the transition refuse "unless
the organization satisfies **the same Connect-readiness predicate `venue.create_primary_checkout`
enforces**, evaluated at transition time." That predicate is exactly org status / Connect / signing key
/ fee. So migration 102 adds **exactly those four gates**, in order, each a stable machine code, fail-
closed, after the existing auth/role/forward-transition/empty_inventory checks:

1. `org_not_saleable` — event's org `status ∈ ('approved','active')`
2. `connect_not_ready` — `stripe_connect_account_ref` bound AND `connect_transfers_active = true`
3. `signing_not_ready` — an active, in-window `kernel.signing_key` resolves per_event→per_venue→global
4. `fee_policy_unset` — `fee.buyer_service_bps` (highest version) is non-null

Predicates are copied character-for-character from `create_primary_checkout`'s G2/G2b/A5 so a future
edit to one ladder is an obvious mismatch, not a silent divergence.

**Two gates a first draft carried were REMOVED as unratified overreach** (this is the substantive
correction this train made to the initial implementation — see §6):
- **Inventory-policy gate — removed.** Not part of `create_primary_checkout`'s SALEABLE set, so not part
  of ratified A8a′; inventory hold cap/TTL are dynamic quote-time config that reserve re-reads live (and
  test 145 deliberately exercises unset). Gating publish on it exceeds the ratified predicate.
- **Tax gate + `tax.policy_resolved` seed — removed.** See §7.

**Static / dynamic split (documented in the migration header).** `on_sale` PASS is a publish-time
admission control, not a live invariant: a later config change can regress readiness and nothing here
re-checks it (on_sale→live→completed never revisits on_sale). Checkout remains the point that re-observes
state when money moves and is UNCHANGED — this migration does not touch `create_primary_checkout`. The
GLOBAL `feature.native_issuance_enabled` kill-switch and live inventory/timing stay checkout-side.

---

## 6. The correction: from six gates to four (why the first cut was wrong, and how it was caught)

The concurrently-authored migration draft (DB-IMPL, report `KM6`) implemented SIX publish gates —
adding an inventory-policy gate and a tax gate beyond the checkout mirror, with a new
`tax.policy_resolved` config key. **The orchestrator's full-suite verification caught this**: fixtures
145 (venue inventory) and 146 (venue orders) aborted, and 145 aborts *specifically* because its
deliberate inventory-policy-UNSET narrative collided with the inventory publish gate. Reading the
ratified A8a′ text against the actual rulings showed both extra gates exceeded what the owner ratified:

- The A8a′ text names only "the same Connect-readiness predicate `create_primary_checkout` enforces"
  (org/connect/signing/fee) — no inventory, no tax.
- Tax is separately reserved by ITEM (ii) as an owner/legal locus decision (§7).

Both extra gates and the tax seed were removed; the migration now ships the four ratified gates. This
is exactly the "narrow, ruling-faithful, don't-invent-beyond-the-mandate" discipline the train
required. The consequence to census (§9) and to test 168 (dropped its inventory/tax assertions,
`plan(52)`→`plan(49)`) was reconciled centrally.

---

## 7. Tax — held as an owner/legal decision, not wired (PFA-PT-7)

Owner constraint (verbatim): *"Do NOT solve tax or silently define tax=zero (tax stays fail-closed)."*
ITEM (ii) records tax as "an activation blocker of an OWNER/LEGAL kind, not an engineering one … no
rate or model is invented here or anywhere in this corpus, and none should be assumed."

The removed tax gate would have SILENTLY DECIDED the tax enforcement **locus** (publish-time) that the
owner reserved — the same unratified-locus move ITEM (i) itself warns against. "Tax stays fail-closed"
is ALREADY the system's state without any such gate: the backend computes no tax and assumes none (face
value + explicitly-modeled adjustments, ruling A5), and the only tax representation anywhere is a
client-side advisory that refuses to quote. Migration 102 therefore introduces **no** tax key, gate,
model, or rate. Recorded as **PFA-PT-7 (boundary held)**; the locus/mechanism decision is left OPEN for
the owner (publish-time vs checkout-time vs the current compute-none posture).

---

## 8. `signing.%` trust-root dual-control (owner §21 / finding P1-1)

`catalog.set_platform_config` (093:6544) dual-controlled `refund./payout./authn./comp./wallet./
credential./door.session_/fee./deletion./ticket.` but NOT `signing.%` — so a single `platform_admin`
could re-pin the monitor's expected fingerprint to match a substituted key (the "who watches the
watchman" gap). 102 adds the two TRUST-ROOT keys to the dual-control set:

- `signing.expected_key_fingerprint` and `signing.expected_max_not_after` → **park for a second
  platform_admin** (both non-scalar → no declared polarity → park in BOTH directions; arming/changing a
  trust root at all takes two humans).
- `signing.monitor_enabled` → **stays single-admin both directions** (deliberately excluded): an
  emergency detection kill-switch that needs a quorum is not a kill-switch (WALLET §11.5b polarity);
  re-arming detection is a tightening. The separation — dangerous trust-root change vs emergency toggle
  — is intentional.

Body-only re-create; everything else byte-identical to 093.

---

## 9. Census reconciliation (applied by the orchestrator)

Migration 102 adds ONE kernel function and ONE `authenticated` grant, and no public-schema object and
no config key. Applied bumps:

- **Kernel function 146 → 147** (`get_ticket_signing_context`): tests 141:164, 142:1327/1361,
  143:143/173/175, 144:94/125, 148:137/175.
- **Five-schema routine 280 → 281**: 148:75/120, 156:45/74, 157:197/218.
- **`22/146/16` → `22/147/16`** market/kernel/catalog string: 154:49.
- **141 F2 `authenticated`-EXECUTE exact-name set 66 → 67** (`get_ticket_signing_context` inserted in
  COLLATE-"C" order after `get_org_connect_state`) + description. **This bump was missed by KM6 §7 and
  caught by the orchestrator's suite run** — it is the grant census, distinct from the function-count
  census.
- **`catalog.platform_config` census — deliberately NOT moved** (no new key after the tax seed was
  removed): the initial 54→55 / 46→47 bumps were reverted.
- **Test 168** dropped its inventory (B6/B6b) and tax (B7) assertions: `plan(52)` → `plan(49)`.

Gate-2 public census unchanged: **tables=27 functions=70 policies=37 triggers=26** (kernel-only
migration).

---

## 10. Verification (local rehearsal harness; CI is the authoritative fresh replay)

| Check | Result |
|---|---|
| Fresh replay 000→102 (`rehearsal_reset.sh`) | **clean**; Gate-2 27/70/37/26 |
| Full pgTAP suite (`rehearsal_test.sh`) | **PASS** — `TOTAL plan=3598 ok=3594 not_ok=4`; RESULT "matches the expected local baseline" (the only 4 failures are the documented local-only deltas: 060_payments_money ×2, 132_replay_parity ×2). 145 PASS (plan 96), 146 PASS (plan 78), 168 PASS (plan 49). |
| Test 168 (get_ticket_signing_context + A8a′ 4-gate + signing dual-control) | 168 rewritten to `plan(49)`; passes |
| vitest — `credential-sign.test.ts` | **23/23** |
| vitest — full suite | **512/512** (12 files) |
| 093 assembler integrity (`assembled_migration_integrity.sh`) | **G-4 PASS** (093 byte-identical) |
| Rollback 102 (targeted) | **verified**: kernel fns 147→146; `get_ticket_signing_context` dropped; `publish_event` body reverts to 081 (no `org_not_saleable`); `set_platform_config` drops `signing.expected_*` dual-control |
| Production inspection | READ-ONLY; 0 signing keys; ledger at 107 (through 092); 093-102 unapplied |

### 10.1 Fixtures 145 / 146

Both predated A8a′ and published `on_sale` without the (now-required) SALEABLE prerequisites, so they
aborted under the 4-gate publish. 146 additionally tests checkout refusing on
`payout_not_ready`/`no_active_signing_key`/`service_fee_unset` — under reading-B those become
**regression** cases (publish saleable, then regress each condition), navigating the append-only
`platform_config` version-monotonicity constraint. Both fixtures were repaired to establish the four
gates before publish while preserving every original behavioral assertion (see `KFIX_145_146.md`).
**Confirmed green** on a clean end-to-end reset+replay+suite with all package-102 edits combined:
145 PASS (plan 96), 146 PASS (plan 78), full-suite `TOTAL plan=3598 ok=3594 not_ok=4` with the four
failures being exactly the two documented local-only deltas — RESULT "matches the expected local
baseline." 146 used a grant-then-regress structure (publish saleable, regress each condition) and
renumbered its happy-path fee row v2→v4 for the append-only/highest-version-wins constraint; no original
assertion was weakened, deleted, or had its expected code/message changed.

---

## 11. Adversarial pass — vectors examined against the authored code

Money non-regression + transfer/resale/rotation/offline/first-mint were independently CONFIRMED-SAFE by
the read-only architecture review (`KARCHV_credential_architecture.md`): version bump 0→1→2 is atomic
with custody (088:707/085:386); rotation keeps old atoms pinned to K1; full 000-101 replay green;
canonical G4 case (obligation 9000) and cross-venue recovery refusal both execute; neither 100 nor 101
touches signing. On the code THIS package added:

| Vector | Finding |
|---|---|
| Existence oracle on `get_ticket_signing_context` | None — non-existent and wrong-owner collapse to `not_owner`. |
| Terminal-state completeness | `state` domain is `{issued,active,scanned,voided,expired}`; gate refuses the 3 dead states; `issued`/`active` sign. Correct. |
| Signing-key window (null `not_before`) | `not_before NOT NULL` (083:59) — window test exact; no asymmetry. |
| Fresh-scope key substitution | Prevented — reads the atom's PINNED `signing_key_id` only (§5.2). |
| Private-key / handle leakage | `kms_handle_ref` is a handle, column-scoped out of client grants; definer surfaces it only to the owner. No key material anywhere. |
| Client-controlled signed bytes | None — body carries only `ticket_atom_id`; signed bytes built entirely from DB ctx; no version/key accepted from client. |
| Algorithm confusion (JWS) | Bounded — verify resolves key by `kid`, an alg/key-type mismatch fails in the primitive. **Hardening: `kernel.signing_key` has no `algorithm` column; the door M1 manifest MUST pin `alg` per `kid` — PFA-PT-8.** |
| Canonicalization confusion | Prevented — verify re-derives signed bytes from the token's own literal segments (JWS-correct). |
| Domain cross-protocol replay | Prevented — `typ` domain separator inside the signed header. |
| service_role bypass of ownership | Prevented — edge calls the RPC as the owner (forwarded JWT), never service_role. |
| Rate-limiter / KMS fault | Fail-closed (503); KMS unconfigured is a permanent 500; token/keys never logged. |
| `signing.%` unilateral trust-root change | Closed — trust-root pair now dual-controlled; monitor toggle intentionally single-admin (§8). |
| Money invariants G4/G5 | Non-regressed — 166/167 pass; 100/101 untouched. |

---

## 12. Owner / follow-up items (all tracked in `POST_FREEZE_AMENDMENTS.md`)

- **PFA-PT-6** — sign the credential wire format (adopt or replace). Deploy precondition for
  `credential-sign`; not a precondition to authoring/testing.
- **PFA-PT-7** — decide the tax enforcement locus (or affirm the compute-none posture). No tax gate is
  added by engineering until decided.
- **PFA-PT-8** — ratify the door M1 `alg`-per-`kid` pinning rule; decide whether
  `kernel.signing_key` gains an `algorithm` column (future additive migration).
- **KMS ceremony + provider adapter** — separate ceremony-time act; the ceremony now has a consumer
  (`PRODUCTION_SIGNING_KMS_CEREMONY.md` §17). A `global` bootstrap key + `fee.buyer_service_bps` are now
  prerequisites for the first event reaching on_sale (A8a′).
- **Offline door verifier (M1/M2)** — not built here; requirements captured in the Claude B handoff and
  the activation matrix.

## 13. Files

New: `supabase/migrations/102_credential_signing_context_and_saleable.sql`,
`supabase/rollbacks/102_…_rollback.sql`, `supabase/tests/168_…sql`,
`supabase/functions/credential-sign/{credential.ts,index.ts}`, `tests/credential-sign.test.ts`,
`docs/phase2/_impl/{KM6_102_implementation.md, KCRYPTO_credential_sign.md,
KARCHV_credential_architecture.md, KFIX_145_146.md}`.
Modified: `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` (PFA-PT-6/7/8),
`docs/phase2/{PRODUCTION_SIGNING_KMS_CEREMONY.md, PRIMARY_TICKETING_ACTIVATION_MATRIX.md,
CLAUDE_B_BACKEND_HANDOFF.md}`, census tests 141-157, fixtures 145/146.
Untouched: migrations 093-101 (immutable); `create_primary_checkout`; production.
