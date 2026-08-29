# Phase 2 — Apple Wallet / Ticket-Credential Delivery Specification

**Status:** BUILD-READY DELTA SPEC. **Design-only — no PassKit code, no React Native code, no SQL files, no
migrations, no certificates, no keys.** JSON and SQL fragments appear inline only to pin the *shape* of an
artifact or a constraint; they are illustrative, not deliverables.

This document is a **delta** on the frozen Phase-2 specification set and on the owner-ratified door-lifecycle
spec. It does not edit the constitution documents (`SNATCH_IT_DOMAIN_ARCHITECTURE.md`,
`SNATCH_IT_CANONICAL_DATA_MODEL.md`) and it does not edit
`docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md`. Where it needs the door-lifecycle spec changed, it says so
in §14 and changes nothing itself.

**Binding inputs (authority order):**
1. `docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md` (branch `design/o5-door-lifecycle` @ `212c861`) —
   **authoritative input, not a peer draft.** §5 Door Safety Theorem · §6 atomic open · §9.1 M1/M2 manifest
   disambiguation · §9.2 offline verify step 3b · §9.4 Wallet stale-read table · §10.1/§10.3 manifest tables ·
   §13.3 defect · §16 OQ-5.
2. `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` — **C33** (RATIFIED, Gate P), **C37**
   (Gate L), **C41** (RATIFIED, Gate P), **C43** (Gate M), C6, C23, C35, C36.
3. `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` §10.4 (credential + C33 key lifecycle), §3.1 (ticket
   state machine), §10.1 (two rails), §16.4, §7.2 (SoD, bulk-attendee-list rule).
4. `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` §1.1 (Issued Credential, Ticket Atom), §5 (storage
   categories — Credential/Secret Storage), §6 (Door Scanner read model).
5. `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.5, §1.7, §2.3, §2.4, §3.11, §3.12.
6. `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.2, §5.1–§5.7, §7, §8 — **and §5.4, which carries
   defect W-3 (§0.2 below).**
7. `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` §0, §7.2, §7.5, §9.3, §9.4, §9.5, §12.4.
8. `docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` §0, §4.4, §4.4.2, §4.5, §7, §10.2.

**Change-class tags.** Every element carries exactly one:
`NO SCHEMA CHANGE` · `ADDITIVE SCHEMA CHANGE` · `SPEC CORRECTION` · `NEW RPC` · `NEW EDGE FUNCTION` ·
`NEW RN SURFACE` · `NEW DASHBOARD SURFACE`.

**Migration packages.** Phase-2 packages are numbered **`076`–`091`**. Production migrations `071`–`075` are
applied security migrations and are unrelated. `PHASE_2_SUPABASE_MIGRATION_PLAN.md` on this branch still
numbers the same sixteen packages `073`–`088` (it records two `+1` shifts; a third `+3` shift has since
occurred as production consumed `073`/`074`/`075`). **This document uses `076`–`091`.** The mapping used
throughout is the migration plan's §2 dependency graph plus three:

| Plan node | This document | Contents |
|---|---|---|
| `073 A` | **076** | schemas + GRANTs + helpers |
| `075 C` | **078** | catalog + feature-flag seeds |
| `076 D` | **079** | `kernel.tickets` + ownership log |
| `080 G` | **083** | `kernel.signing_key` (key-ref, no secret) |
| `081 G` | **084** | ADOPT: `kernel.tickets` FKs → `ticket_type` + `signing_key` |
| `083 H` | **086** | venue door + scan (+ comp/guest) |
| `085 J` | **088** | market native rail |

---

## 0. Establishing facts (verified, not assumed)

### 0.1 There is no Wallet feature in this repository — VERIFIED

Searched the whole tree (excluding `.git`) for `PKPass`, `PKAddPasses`, `addPassesViewController`,
`vnd.apple.pkpass`, `passTypeIdentifier`, `serialNumber`, `authenticationToken`, `webServiceURL`; for files
matching `*.pkpass`, `*.p12`, `*.p8`, `*.cer`, `*.mobileprovision`; for `passkit`/`pass-js`/`node-passbook`/
`react-native-wallet` in `package.json`; and for `wallet_pass`/`pkpass`/`pass_type` under `supabase/`.

**Result: zero hits in all categories.** The only occurrences of the string "Apple Wallet" in the repository
are:

| File | What it actually is |
|---|---|
| `docs/product/TRANSFER_METHOD_RESEARCH.md:114–115` | competitor research about **Ballpark**, not Snatch It |
| `docs/security/TICKET_CREDENTIAL_AUDIT.md:230–232` | competitor research about how *other* platforms' wallet-bound tickets behave |
| `packages/core/src/platformInstructions.ts:542`, `src/lib/platformInstructions.ts:542` | user-facing copy describing **a third-party issuer's** transfer instructions |
| `src/components/StatCardStrip.tsx:116` | a code comment about *visual styling* ("Apple Wallet-style quiet label") |
| `src/screens/checkout/CheckoutNative.tsx:181` | a comment about the **Apple Pay payment sheet** line-item convention — a payments API, unrelated to `.pkpass` |

The door-lifecycle spec's §9.4 note is therefore correct and remains correct: *"The Apple Wallet / PassKit
surface itself is not built in Phase 2 — no PassKit code exists in the repo and the RN spec's 'wallet' is the
in-app Tickets tab (§4.4) plus the cached `credential-sign` token."* **This document establishes the feature
from zero.**

### 0.2 Defect W-3 — the offline door cannot detect a stale pass — VERIFIED, NOT FIXED

`PHASE_2_EDGE_FUNCTION_SPEC.md` §5.4 enumerates the offline door's verification steps verbatim:

> (1) checking the token's `key_id` is in the cached manifest and within `[not_before, not_after]`;
> (2) verifying the signature with that **public key**; (3) checking `session_id` matches and `exp` is within
> the offline skew window (±2 time-buckets, RPC §9.3); (4) enforcing first-in-wins locally from its offline
> scan log.

There is **no `credential_version` comparison**, and the only manifest §5.4 defines is a **public-key**
manifest (`{key_id, scope, public_key, not_before, not_after, status}`). Two different artifacts were
conflated: `venue.scan_device.manifest_version` (schema §3.11) and `venue.scan.manifest_version` (schema
§3.12) are integer columns that version **nothing**, because no ticket-manifest table exists.

**As specified today, an offline door verifies that a token was validly signed — never that it is current.**
The door-lifecycle spec independently found the same defect (its §13.3) and closed it by (a) naming the two
manifests **M1** (key manifest) and **M2** (door/ticket manifest), (b) giving M2 a physical home in
`venue.door_manifest` / `venue.door_manifest_entry`, and (c) adding offline-verify step **3b**
(`credential_version` equality against M2). **Neither the M2 tables nor step 3b exists in the frozen set.**

**Sequencing ruling (hard, §15 OQ-W3):** Apple Wallet **may not ship before** the door-lifecycle spec's M2
tables and offline-verify step 3b are implemented. Building Wallet first would mass-distribute a long-lived
bearer artifact into a world where the offline door has no staleness check at all — deploying defect W-3 at
scale, on devices the platform does not control.

---

## 1. Feature scope and explicit non-goals

### 1.1 In scope

A holder of an **Official Ticket** (a `kernel.tickets` atom they currently own) may add that ticket to Apple
Wallet on iOS. The pass is a **delivery vehicle** for the C33 credential token — the same token the in-app
Entry Pass (RN §4.4.2) displays — packaged so it renders without the app and without a network connection.

Covered: pass lifecycle · issuance · pass identity · ticket-atom linkage · event metadata · barcode credential
strategy · transfer · resale · refund · void · cancellation · event update · pass refresh · device
registration · push updates · revoked-pass behaviour · offline scanning · stale passes · re-entry policy ·
pass-after-ownership-transfer · privacy · signing keys · Pass Type ID certificate and operational
requirements · failure/recovery · the RN "Add to Apple Wallet" surface · venue/scanner behaviour.

### 1.2 Explicit non-goals

| Non-goal | Why |
|---|---|
| **Google Wallet / Google Pay passes** | Separate credential format, separate key custody, separate review surface. If added, it is a *second* delivery vehicle over the same token and inherits §4's proof unchanged — but it is not specified here. |
| **NFC passes / Apple VAS / `PKPaymentPass`** | Requires a separate Apple entitlement and NFC-capable readers. Snatch It doors are camera scanners (RN §7.4). Out. |
| **Rotating / animated barcodes (SafeTix-class)** | A rotating barcode exists to defeat screenshots *when the verifier cannot check currency*. §4 shows currency is checked by `credential_version` + M2 online **and** offline. Rotation would add device-clock coupling and an offline failure mode in exchange for a property already held. Recorded as a future option in §15 OQ-W9, deliberately not built. |
| **Re-entry / pass-out via Wallet** | **C41: MVP is no-re-entry GA; `scanned` is terminal; `direction` is the reserved hedge.** A second scan of any pass is a `duplicate`, never a re-admit. No Wallet surface may imply otherwise. |
| **Identity / name matching at the door** | The door verifies a *credential*, not a *person* (DA §9.3). Putting a name on a pass to enable visual ID matching is rejected in §9. |
| **Group / multi-atom passes** | One pass per atom, always. A group pass would make partial transfer, partial void, and partial scan unrepresentable. |
| **Wallet as a fallback when the app is unavailable** | Inverted: **the in-app Entry Pass is the fallback, and Wallet is the convenience.** No flow may depend on Wallet succeeding. |
| **Passes for external-rail (Rail B) inventory** | Invariant 1: the system never asserts ownership of what it did not issue (DA §10.1). Rail B tickets are claims, have no atom, no `credential_version`, and no credential. RN §4.4 already forbids merging them into the wallet; a `.pkpass` would be a much louder version of the same lie. |
| **Passes for `issued`-state atoms** | An atom in `issued` has not cleared the delivery/withhold window (DA §3.1). A pass whose barcode cannot admit is worse than no pass. Offer from `active` only. |

---

## 2. Credential architecture — where authority actually lives

### 2.1 The one-sentence answer

**A Wallet pass carries a claim; it never carries authority.** The barcode is the C33 credential token —
a KMS-signed assertion *"bearer presents atom X, session S, at `credential_version` N, signed by key K"* — and
every admission decision is made by comparing that claimed `N` against a value the platform controls: the live
`kernel.tickets.credential_version` (online, C37) or `venue.door_manifest_entry.credential_version` (offline,
M2). The `.pkpass` file, its Apple signature, its `serialNumber`, and its `authenticationToken` are **never
consulted by any scanner** and confer no admission rights whatsoever.

This is the ratified **credential-as-delivery** invariant (DA §10.1, §10.4; CDM §1.1 Issued Credential)
expressed for a bearer artifact on an uncontrolled device. It is not weakened by Wallet; it is what makes
Wallet safe.

### 2.2 Two signatures, two jobs — do not conflate them

```
┌──────────────────────────── the .pkpass bundle ─────────────────────────────┐
│                                                                              │
│  pass.json  ·  manifest.json  ·  images                                      │
│                                                                              │
│  signature  ──── PKCS#7 detached, by the APPLE PASS TYPE ID CERTIFICATE       │
│                  ├─ proves: "Snatch It authored this FILE"                    │
│                  ├─ verified by: iOS, once, at install time                   │
│                  └─ verified by the door: NEVER                               │
│                                                                              │
│  barcodes[0].message  ──── the C33 CREDENTIAL TOKEN                           │
│                  ├─ Sign_KMS(signer_K, {atom_id, session_id,                  │
│                  │            credential_version, key_id, iat, exp})          │
│                  ├─ proves: "this atom was at version N when minted"          │
│                  ├─ verified by: the door, every scan                         │
│                  └─ compared against: live kernel (online) / M2 (offline)     │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Consequence, stated plainly:** an attacker who forges a `.pkpass` with a self-signed certificate, or who
simply screenshots the barcode, produces exactly the same door outcome as a genuine pass — because the door
evaluates only the barcode payload. **Apple Wallet therefore adds zero admission authority and zero admission
risk beyond what a screenshot already carries.** The Apple certificate is an *iOS install-time* requirement,
not a security control for admission. Any design, code review, or incident response that treats the Apple
certificate as an admission control is wrong.

### 2.3 Exactly what the scanner verifies, and against what

> **`SPEC CORRECTION` — H-2.** This section previously carried **two** conjuncts at 3b. The door-lifecycle spec
> §9.2 requires **five**; the missing `resale_state` conjunct let the offline door admit a
> `paid_pending_transfer` or `refund_hold` atom that the online door refuses. This document's older wording was
> the copy that edge §5.4.3 adopted, which is how the regression travelled. **The predicate is now stated once,
> in edge §5.4.3, and reproduced here verbatim as a sanctioned mirror.**

<!-- SANCTIONED MIRROR of OFFLINE-VERIFY-v1. Byte-identical to PHASE_2_EDGE_FUNCTION_SPEC.md §5.4.3. CI-gated. -->

```text
OFFLINE-VERIFY-v1 — offline door admission predicate (NORMATIVE)
Single source: PHASE_2_EDGE_FUNCTION_SPEC.md §5.4.3. Mirrors must be byte-identical.

Applied set:  M2 := base_snapshot(manifest_id) ⊕ deltas[1 .. last_synced_seq]   (door §7.7)
              The device MUST evaluate against the APPLIED set. Evaluating the base
              snapshot alone silently ignores every revocation and every supplement
              the device has already downloaded.

ADMIT(token) requires ALL of:

  1    token.key_id ∈ M1  ∧  M1[token.key_id].status ≠ 'revoked'
                         ∧  now() ∈ [M1[token.key_id].not_before, not_after]
  2    Verify(M1[token.key_id].public_key, token.claims, token.sig)
  3    token.session_id == the device's bound scanning session
  3a   now() <= token.exp, ± 2 time-buckets                                     (RPC §9.3)
  3b   FIVE conjuncts, ALL required — this is the W-3 fix:
         i    atom ∈ M2
         ii   M2[atom] carries no applied `revoke` delta
         iii  token.credential_version == M2[atom].credential_version
         iv   M2[atom].ticket_state  == 'active'
         v    M2[atom].resale_state  == 'none'
  3c   token.key_id == M2[atom].signing_key_id                                  (Wallet §8.3)
  4    first-in-wins against the device's local admitted set

  No M2, an M2 past its downloaded not_after, or an M2 for another session
  ⇒ the door has NO offline authority and MUST NOT admit.                       (door §3.1)

Conjunct 3b.v is load-bearing, not defence in depth: a `paid_pending_transfer` atom is
`state='active', resale_state='locked'` and is excluded from the door-open drain, and a
`refund_hold` atom is `state='active'` too. Without 3b.v the offline door admits both —
atoms the ONLINE door refuses. Online and offline must reject for the same reasons, or the
offline door is not a shrunk version of the online one; it is a different one.

Reject reasons: door §9.2's map. No private key, no network, no DB.
```

**The table below is a NON-NORMATIVE presentation of that block.** Where they disagree, the block governs and
this table is the defect (edge §5.4.3 single-source rule, clause 4).

| # | Check | Input | Reference value | Online | Offline |
|:-:|---|---|---|:-:|:-:|
| 1 | `token.key_id` present, `status ≠ revoked`, `now() ∈ [not_before, not_after]` | token | **M1** key manifest (edge §5.4) | ✔ | ✔ |
| 2 | `Verify(pub_key[token.key_id], claims, sig)` | token | M1 public key | ✔ | ✔ |
| 3 | `token.session_id == scanning_session_id` | token | device's session binding | ✔ | ✔ |
| 3a | `now() <= token.exp` ± 2 time-buckets | token | device clock | ✔ | ✔ |
| **3b** | **all five conjuncts:** atom ∈ M2 ∧ no applied `revoke` delta ∧ `token.credential_version == M2[atom].credential_version` ∧ `M2[atom].ticket_state = 'active'` ∧ **`M2[atom].resale_state = 'none'`** | token | **M2** applied set (entry ⊕ deltas) | n/a | **✔ — this is the W-3 fix** |
| **3c** | `token.key_id == M2[atom].signing_key_id` — **REQUIRED** (§8.3; promoted from *recommended*, with the online counterpart in row 4) | token | M2 entry | n/a | **✔** |
| 4 | live authoritative read: `venue.validate_ticket_online(atom, session)` → require `admittable` ∧ returned `credential_version == token.credential_version` ∧ returned `signing_key_id == token.key_id` | token | **`kernel.tickets`, live (C37)** | **✔** | n/a |
| 5 | first-in-wins | — | local admitted set (offline) / `venue.record_scan` partial unique (online) | ✔ | ✔ |
| 6 | authoritative admit | — | `venue.record_scan` → `kernel.mark_ticket_scanned` | ✔ | deferred to `venue.reconcile_offline_scans` |
| — | **the `.pkpass` file, its PKCS#7 signature, `serialNumber`, `authenticationToken`, `passTypeIdentifier`** | — | — | **never** | **never** |

Checks 1–3a are already the frozen edge §5.4 contract. **3b is the door-lifecycle spec's step 3b — all five
conjuncts — and is the half of the guarantee that does not exist today.** 3c originated here as a
recommendation (§8.3) and is now **required**, with an online counterpart in row 4. Check 4 is C37 plus the
`signing_key_id` comparison that gives 3c its online half.

### 2.4 Which half of the stale-pass guarantee comes from where

This is the question defect W-3 exists to answer, and the two halves are not interchangeable:

- **The credential supplies the *claim*.** `credential_version` is a signed claim inside the token. Without it
  in the signed payload, a barcode that is merely an atom identifier gives the verifier *nothing to compare* —
  the previous owner's barcode and the new owner's barcode are the identical string, and no manifest, however
  fresh, can tell them apart. **This half makes staleness detectable at all.**
- **The manifest supplies the *reference value*.** M2 pins, per atom, the `credential_version` that was live
  at the instant the freeze engaged. Without M2 an offline door has nothing to compare the claim *to*.
  **This half makes staleness decidable without a network.**
- **Online, the live kernel read (C37) substitutes for M2** — the reference value is read authoritatively at
  the decision point. The credential half is still required, unchanged.

Neither half alone is sufficient. The frozen set ships the first half (`credential_version` is already in the
`credential-sign` token, edge §3.2) and omits the second (edge §5.4 defines no ticket manifest and no version
check). That asymmetry is exactly why W-3 is a safety defect and not a nuisance.

### 2.5 The invariant this design must not violate

> The pass must not **be** the authority — it must be a **delivery vehicle** for a credential whose validity is
> decided elsewhere.

Discharged structurally: the door's decision path (§2.3) reads **only** platform-controlled state
(`kernel.tickets` or `venue.door_manifest_entry`) for its reference value. The pass contributes exactly one
thing — a signed claim about which version it believes it holds — and a claim that disagrees with the
platform's value is rejected. **No push, no revocation call, no device cooperation, and no network on the
holder's phone is required for this to be true**, which is what makes §4.4's airplane-mode answer work.

---

## 3. Pass lifecycle state machine

### 3.1 Pass states

```
                      kernel.mint_wallet_pass (owner-authorized, atom state='active')
                                        │
   [ NO PASS ]  ────────────────────────▼──────────────►  [ issued ]  ◄── re-download (same generation,
        ▲                                                     │           same serial, same auth token)
        │                                                     │
        │                              ┌──────────────────────┼───────────────────────┐
        │                              │                      │                       │
        │           custody moves away │        atom scanned  │   atom voided/expired │   pass-level revoke
        │           (credential_version│                      │                       │   (auth-token
        │                        bumps)│                      │                       │    compromise, support)
        │                              ▼                      ▼                       ▼
        │                       [ superseded ]          [ consumed ]           [ invalidated ]     [ revoked ]
        │                              │                      │                       │                │
        └──────────────────────────────┴──────────────────────┴───────────────────────┴────────────────┘
                        all terminal; the row is retained permanently (evidence + registration history)
```

`superseded` · `consumed` · `invalidated` · `revoked` · `expired` are **terminal**. The row is never deleted:
device registrations reference it, and the pass registry is the evidence for "which artifact was on which
device when." A new custody tenure produces a **new generation with a new serial**, never a re-animation
(mirrors DA §3.1's "terminal states are terminal").

### 3.2 Mapping onto the ticket-atom state machine and `credential_version`

| `kernel.tickets.state` / event | `credential_version` | Pass action | Resulting pass state |
|---|---|---|---|
| `issued` (pre-delivery window) | 0 | **no pass offered** (§1.2) | — |
| `issued → active` | unchanged | "Add to Apple Wallet" becomes available | — |
| owner adds to Wallet | N | mint generation *g* | `issued` |
| `resale_state: none → listed` / `→ locked` | unchanged | pass **content** updated ("Listed for sale" / "Transfer pending"); **barcode unchanged** — the door already rejects `listed_locked` (RPC §9.3) and the pass must not pre-empt the door | `issued` |
| `resale_state → none` (delist / drain / TTL) | unchanged | content updated back | `issued` |
| **custody move** (`transfer_ticket_ownership`: p2p accept, native resale, admin) | **N → N+1** | old holder's pass → `superseded`, content replaced with a non-admitting "no longer valid" face; **new holder must add a new pass** (§7.1) | `superseded` + new `issued` |
| `active → scanned` (`mark_ticket_scanned`) | unchanged | content updated to "Used — <time>" | `consumed` |
| `active/issued → voided` (`refund_void`, fraud, event cancel) | **N → N+1** | content updated to "No longer valid" | `invalidated` |
| `active/scanned → expired` (post-event sweep) | unchanged | content updated to past-event | `expired` |
| session `status → cancelled` (`catalog.cancel_event`) | (atoms void → bump) | content updated to "Event cancelled" | `invalidated` |
| session time / venue / lineup edited | unchanged | content updated; barcode unchanged | `issued` |
| support revoke (auth-token compromise, lost device) | unchanged | pass → `revoked`; holder re-adds → new generation | `revoked` + new `issued` |

**The load-bearing row is the custody move.** `credential_version` bumps inside
`kernel.transfer_ticket_ownership` (schema §1.5, CDM §1.1 — pinned to the ownership log), and that single
arithmetic fact is what invalidates the old pass. The push, the `superseded` status, and the content rewrite
are **cosmetics that improve the old holder's UX**. They are not the mechanism, and none of them is required
for §4's proof.

### 3.3 Pass generation vs `credential_version` — why they are not the same counter

`credential_version` is per-atom and bumps on every custody move **and every void**. A pass `generation` is
per-atom and increments on every event that requires a **new `serialNumber`**: a custody move, or a support
revoke. They diverge on `void` (version bumps; the pass is `invalidated`, not regenerated — there is no next
holder) and on re-download (neither changes).

**Why a new serial per custody tenure is mandatory, not stylistic:** `(passTypeIdentifier, serialNumber)` is
the key Apple's update web service is addressed by (§6). If A and B shared a serial, then B's pass content
would be served to A's registered devices on their next refresh — leaking B's ticket, B's `credential_version`
and B's `authenticationToken` onto A's phone. A shared serial is a PII leak and a correctness failure, not an
optimization. The database enforces the rule structurally: **partial `UNIQUE(ticket_atom_id) WHERE
status = 'issued'`** (§11.1) — at most one live pass generation per atom, ever.

---

## 4. The stale-pass guarantee — proved for four scan scenarios

> **THE NON-NEGOTIABLE:** the previous owner's Wallet pass must not remain a valid admission credential after
> ownership changes.

**Setup, used by all four proofs.** Atom `X` belongs to session `S`. Owner `A` holds it at
`credential_version = N` and has installed Wallet pass generation `g_A` with serial `S_A`, whose barcode is the
token `T_A = Sign_K({X, S, N, K, iat, exp})`. At time `T_t`, `kernel.transfer_ticket_ownership` moves custody
to `B` and bumps `credential_version` to `N+1` **in the same transaction that appends the ownership-log row**
(schema §1.5, C27/C28). `A`'s device is never touched.

---

### 4.1 Scenario 1 — Online scan

**Result: DENIED.**

The door verifies checks 1–3a (§2.3) against its cached M1, then calls
`venue.validate_ticket_online(X, S)` (RPC §9.3), which performs a live authoritative read of
`kernel.tickets` at the decision point and returns `{admittable, reason, credential_version}`. Live
`credential_version = N+1 ≠ N` ⇒ reason `version_stale` ⇒ `admittable = false`. `venue.record_scan` is never
reached, so no `venue.scan` row with `result='admitted'` is written and `X` does not move to `scanned`.

**Assumptions, named:**
- **(A1)** the scanner has network at the decision point — that is the definition of this scenario;
- **(A2)** **C37 holds**: the online door performs a live authoritative per-scan kernel read at the decision
  point. C37 is `RATIFIED-MODELED-ONLY(GATE-L)` in the record, but the *claim correction* is already applied in
  the constitutions and RPC §9.3 already specifies the live read and the `version_stale` reason — so this is a
  contract that exists today, not a future one;
- **(A3)** the door passes the token's claimed `credential_version` into the comparison. RPC §9.3 returns
  `credential_version` and names `version_stale` as a reason, so the comparison is in-contract; the door
  client must actually perform it. **This is a door-client implementation requirement, stated so it is not
  assumed** (§10.2).

**Residual: none.** This scenario is closed unconditionally.

---

### 4.2 Scenario 2 — Offline scan, **fresh** manifest

Definition: the scanner holds M2 from an episode opened at `T_o`, with `T_t < T_o` and `now() < not_after`.

**Result: DENIED.**

Checks 1–3a pass (the token is genuinely signed, the key is live, the session matches, `exp` has not passed —
see §5.3 on why `exp` passing is *expected* and *irrelevant here*). Step **3b** compares `T_A`'s `N` against
`M2[X].credential_version`. The door-lifecycle spec's §6 step 7 snapshots every admissible atom's
`credential_version` **as read after the `FOR UPDATE` lock of step 1**, under READ COMMITTED (its §6.1), so
`M2[X].credential_version = N+1`. `N ≠ N+1` ⇒ reject `version_stale`.

**The stronger result: "fresh" is structural, not probabilistic.** The Door Safety Theorem (door spec §5.3)
proves that for every atom in an open episode, live `credential_version` at scan time equals the value in that
episode's snapshot — because every custody RPC takes `FOR SHARE` on the session row before the open's
`FOR UPDATE` (so it is *in* the snapshot) or after (so it is rejected `frozen`), and no third case exists.
Therefore **every committed transfer is either before the snapshot or impossible**, and every open manifest is
fresh with respect to every committed transfer. There is no window to hit.

**Assumptions, named:**
- **(A4)** **offline-verify step 3b is implemented.** It is specified in the door-lifecycle spec §9.2 and is
  **absent from the frozen edge §5.4** (defect W-3). This is the single assumption that today is false, and
  §15 OQ-W3 makes it a shipping gate;
- **(A5)** the device synced M2 for **this** episode and `now() < manifest.not_after`;
- **(A6)** the Door Safety Theorem's preconditions hold — every custody RPC takes the rank-1 session
  `FOR SHARE` gate (door spec §5.1) and `open_door_manifest` runs at READ COMMITTED with the snapshot issued
  after lock acquisition (door spec §6.1). Both are load-bearing implementation notes that are not inferable
  from the RPC contracts.

**Residual: none, given (A4)–(A6).**

---

### 4.3 Scenario 3 — Offline scan, **stale** manifest

"Stale" has three distinguishable meanings. All three are covered, and one carries a named residual.

**(a) The device holds M2 from an *earlier episode* of the same session** (opened → closed → re-opened).

**Result: DENIED — and this is the interesting case.**

`catalog.event_session.door_open_at = MIN(door_manifest.opened_at)` (door spec §2) — it is a monotone,
terminal head of an append-only episode ledger. Once the *first* episode opened at `T_1`, `is_transfer_frozen`
is true for every atom of `S` from `T_1` onward, **forever**, and closing an episode explicitly does not clear
it (door spec §7.2, req 9). Therefore **no `transfer_ticket_ownership` for any atom of `S` can commit at any
time ≥ `T_1`**, so `M2_{e1}[X].credential_version == M2_{e2}[X].credential_version == live`. An "old" manifest
is *not stale in the dimension that matters*. Step 3b rejects `T_A`'s `N` identically.

**(b) The device's M2 is past `not_after`.** The device refuses offline admits entirely and falls back to
"needs a connection" (door spec §14 failure #8). Fail-closed. Bounded by
`config('door.manifest_ttl_interval')`, default 12h.

**(c) The device never synced / holds M2 for a different session.** No M2 ⇒ no offline authority at all
(door spec §3.1) — the scanner renders `awaiting_manifest` and cannot admit offline. A different session's M2
fails check 3 (`session_id`). Fail-closed both ways.

**Named residual — the only one in this section.** Two audited break-glass paths can move custody while
`door_open_at` is set:
1. `kernel.grant_door_freeze_override` — `platform_admin` only, TTL ≤ `config('door.max_override_interval')`
   (default 2h), reason-coded, audited, and **structurally forbidden while an episode is open** (door spec
   §8.2 precondition 1);
2. `kernel.force_void_ticket` / `kernel.admin_refund` — platform break-glass, exempt from the freeze
   (door spec §7.6), audited.

If a custody move commits under (1) between the close of `e_1` and the open of `e_2`, a device still holding
`M2_{e1}` holds a genuinely stale reference value. It would then **admit the pre-override owner** (fail-open)
**and reject the post-override owner** (fail-closed against a paying fan). Both directions are real.

In C37's words: **the offline window is shrunk, not closed.** The mitigations are already ratified — the
override requires elevated authority, is TTL-bounded, is audited, and cannot coexist with an open episode —
and this document adds one operational requirement (§14, door-spec change **DL-3**): **after any
`door_freeze_override` or platform force-void touching a session, every scanner for that session must re-sync
M2 before resuming offline admission**, surfaced as a dashboard alert and a scanner banner. This does not close
the residual; it bounds it to the interval between the break-glass act and the re-sync.

---

### 4.4 Scenario 4 — A's device in **airplane mode since before the transfer**

**Result: DENIED at the door. The guarantee is completely unaffected by A's connectivity.**

`A`'s device never received the APNs push, never called the pass update web service, never re-fetched, and
still renders `g_A` with `T_A` claiming `N`. Every one of those facts is about **A's device**. None of them is
in the door's decision path: the door's reference value comes from `kernel.tickets` (online) or M2 (offline),
both of which the platform controls and both of which say `N+1`. So Scenario 4 collapses to Scenario 1, 2, or
3(a) depending on the *scanner's* connectivity — with the identical outcome.

**This is the payoff of §2.5.** Authority never lived on `A`'s device, so removing `A`'s device from the
network removes nothing from the enforcement path. It is also why the design does **not** need a
remote-wipe mechanism, and why it must not pretend to have one: PassKit provides no way to force-delete an
installed pass, and any design that needed one would be broken by exactly this scenario.

**What A's offline device *does* still have: a convincing-looking artifact.** `A` can show a genuine
Snatch-It-signed `.pkpass`, correctly rendered by iOS, with the right event, venue, date and tier. The residual
is therefore **social, not cryptographic**, and it is mitigated by policy, not by keys:
- **Design rule (binding, §9.3):** the Wallet pass **must not display a validity assertion** — no green tick,
  no "Valid", no "Admit One" status field, no live indicator of any kind. RN §4.4.2 specifies "a live *valid*
  indicator" for the **in-app** Entry Pass; that is acceptable in-app because the app re-reads state when
  online. **It must not be copied into the Wallet pass, which cannot.** Copying it would manufacture the exact
  false assurance this scenario exploits.
- **Venue rule (binding, §10.4):** **no visual admission.** A pass that looks right but does not scan is not
  admitted, ever. This must be in the door runbook and in the scanner's `awaiting_manifest` / offline copy.

**I will not claim this residual is closed by cryptography, because it is not.** It is closed by refusing to
admit anything that was not scanned.

---

### 4.5 Proof summary

| Scenario | Verdict | Mechanism | Assumptions | Residual |
|---|:-:|---|---|---|
| 1 · online | **DENIED** | live kernel read, C37 (§2.3 check 4) | A1 network · A2 C37 · A3 door compares the claimed version | none |
| 2 · offline, fresh M2 | **DENIED** | step 3b vs M2, guaranteed fresh by the Door Safety Theorem | **A4 step 3b implemented (false today)** · A5 synced, in-window · A6 rank-1 gate + READ COMMITTED | none given A4–A6 |
| 3 · offline, stale M2 | **DENIED** | monotone terminal freeze ⇒ old M2 carries identical versions; expired/absent M2 ⇒ fail-closed | A4 · door spec §2 monotonicity · §14 #8 | **`platform_admin` override / force-void between episodes — shrunk, not closed (C37)** |
| 4 · A offline since before transfer | **DENIED** | authority is not on A's device; collapses to 1/2/3 | inherits the above | **social engineering only** — mitigated by no-validity-display (§9.3) + no-visual-admission (§10.4) |

**The non-negotiable is met**, conditional on (A4): the door-lifecycle spec's offline-verify step 3b and its
M2 tables must exist before Wallet ships (§15 OQ-W3). Without step 3b, Scenarios 2, 3 and 4 all **ADMIT**, and
this document's central claim is false.

---

## 5. Barcode credential strategy — the wallet token profile

### 5.1 The problem a Wallet pass creates

The in-app Entry Pass refreshes trivially: the app is online when foregrounded and re-calls `credential-sign`
(edge §3.2), so a short `ttl_seconds` costs nothing. A Wallet pass's `barcodes[0].message` is a **static string
baked into `pass.json`**. It changes only when the pass is updated through the web service + APNs (§6), which
requires the device to be online. **A short-TTL token in a Wallet pass expires on an offline phone and locks a
paying fan out of the venue** — the same failure class as door-lifecycle §13.1, and unacceptable for the same
reason.

### 5.2 Ruling — two token profiles — `SPEC CORRECTION` to edge §5.5

`credential-sign` gains an **`aud` (audience) claim** selecting a TTL profile. `NO SCHEMA CHANGE`.

| Profile | `aud` | `exp` | Consumer | Refresh path |
|---|---|---|---|---|
| **app** (existing, default) | `app` | `now() + config('credential.app_ttl_interval')` (a few hours; edge §5.5 unchanged) | RN in-app Entry Pass (RN §4.4.2) | client re-calls `credential-sign` on foreground/reconnect |
| **wallet** (new) | `wallet` | the clamped value of **§5.2a** — session-bounded, then bounded again by the offline window | the `.pkpass` barcode | pass update web service + APNs, **best-effort** |

The wallet profile's `exp` is **session-bounded, not hours-bounded**. `LEAST` with `signing_key.not_after`
ensures a token never outlives its own key's planned window.

### 5.2a The `exp` clamp — bound the computed value, not the constants (`SPEC CORRECTION`)

> **The defect.** The cross-config invariant ratified with OQ-5
> (`wallet_default_span + wallet_exp_skew <= door.manifest_ttl_interval`, door §10.6) constrains
> **`wallet_default_span`** — which is used **only when `session.ends_at IS NULL`**. On the far more common
> branch, `ends_at` is present and the invariant constrains nothing at all: **a long or mistyped `ends_at`
> produces an unbounded `exp`**, and a fat-fingered year makes a multi-month bearer credential. The invariant
> was checked against the constants an operator sets and never against the number the signer actually emits.
> Door §16 OQ-5's item 1 says the token *"cannot outlive the offline window any manifest could authorise"* —
> as written, it could.

**Normative.** `credential-sign` computes the wallet-profile `exp` as:

```text
session_ref_start := COALESCE(session.doors_at, session.starts_at)
session_ref_end   := COALESCE(session.ends_at, session.starts_at + config('credential.wallet_default_span'))

exp := LEAST(
         session_ref_end   + config('credential.wallet_exp_skew'),      -- session-bounded
         session_ref_start + config('door.manifest_ttl_interval')
                           + config('credential.wallet_exp_skew'),      -- the OFFLINE-WINDOW clamp  ← the fix
         signing_key.not_after                                          -- never outlive its own key
       )
```

The middle term is the whole correction: it is expressed over the **computed** instant, so it binds on **both**
branches of the `COALESCE` and is immune to a bad `ends_at`. A session whose `ends_at` is mistyped by a year
still yields a token that dies one offline window after doors could open. **No new config key is introduced** —
the clamp reuses `door.manifest_ttl_interval` and `credential.wallet_exp_skew`, both already seeded.

**Enforcement, in three places, because one is where this defect came from:**
1. **At sign time** in `credential-sign` — the clamp is applied, not merely asserted. A signer that *validates*
   an out-of-range `exp` and refuses would deny a paying fan a barcode over an operator's typo; a signer that
   **clamps** issues a correct, shorter one. Clamp, then log the clamping at `warn` with the session id.
2. **In `catalog.set_platform_config`** — door §10.6's constants invariant stays, as a cheap early warning. It
   is now explicitly **necessary and not sufficient**, and it is not the control.
3. **In CI/pgTAP** — over the **computed** value, with adversarial fixtures: `ends_at` NULL, `ends_at` a year
   out, `ends_at` before `starts_at`, and `signing_key.not_after` inside the session. Asserting only over the
   seeded constants is what let this through.

**Door §10.6's invariant is amended in place by this section** and its "load-bearing for §16 OQ-5" note now
points here: the clamp is the load-bearing half, the constants invariant is the guardrail on the operator.

**Door-side impact: none.** The door's check 3a is `now() <= exp ± 2 buckets`; a longer `exp` simply passes it.
No door code branches on `aud`; `aud` is a claim the signer sets and the door ignores. The door must **not**
treat the two profiles differently — that would reintroduce a Wallet-vs-app distinction the camera cannot make
(§10.1).

### 5.3 Why this is safe — and exactly what it costs

This ruling **conflicts with door-lifecycle §16 OQ-5** as written (*"If a real `.pkpass` is added later … it is
a display layer over the same token and inherits this guarantee unchanged, **provided it never carries a longer
TTL than the token**"*). OQ-5 is an **open question**, recorded expressly so a later PassKit ticket would not
silently invalidate a proven property. This section is the non-silent answer. **It requires owner sign-off
(§15 OQ-W4); it is not settled by this document.**

**What was `exp` actually protecting?** Trace it against each threat:

| Threat | Bounded by `exp`? | Actually bounded by |
|---|:-:|---|
| Stale token after a transfer | **no** (post-3b) | `credential_version` claim vs M2 / live kernel (§2.4) |
| Stale token after a routine refund-void | **no** (post-3b) | version bump + `M2.ticket_state` check (3b) |
| Screenshot resale to a second person | **no** | first-in-wins (C41, RPC §9.4 partial unique) |
| Token signed by a **revoked key** | **no** | check 1 — `key_id ∈ M1 ∧ status ≠ revoked`; the residual is the **M1 refresh window**, which a shorter `exp` does not shorten |
| Stale token at an offline door **with no version check** | **YES** | — this is defect W-3's world, and only `exp` bounds it there |

**The last row is the whole answer: the short TTL was compensating for W-3.** Once offline-verify step 3b
exists, the short TTL's job is done, and the coupling recorded in OQ-5 dissolves — which is exactly why OQ-5
and defect W-3 were noticed by the same reviewer at the same time.

**What is genuinely given up, stated plainly:** a defence-in-depth layer. If step 3b regresses (a scanner
build ships without it, a manifest fails to sync in a way that is mishandled, an implementer "optimizes" the
check away), a short `exp` would still have expired the stale token within hours; a session-bounded `exp` will
not. **Mitigations, all required:** (i) pgTAP/CI assertion W-14 that the offline verifier's version check
exists as a structural test (§12); (ii) the `wallet.apple.enabled` config kill switch (§11.5) so Wallet can be
disabled platform-wide in one dual-controlled config write without a client release; (iii) the scanner refuses
offline admits when it holds no M2 (door spec §3.1), so there is no "offline, no manifest, admit anyway" path
to regress into.

### 5.4 Barcode format

- **QR (`PKBarcodeFormatQR`)**, matching the in-app Entry Pass, so the scanner runs **one** decoder and cannot
  branch on delivery surface. `UNVERIFIED — confirm against Apple documentation before implementation:` the
  exact `format` string constants, the `barcodes` array vs the deprecated singular `barcode` key and which
  iOS versions require which, and whether `PKBarcodeFormatCode128` is excluded from the `barcodes` array.
- `messageEncoding`: `UNVERIFIED — confirm against Apple documentation before implementation.` The
  conventional value is `iso-8859-1`; the token is base64url (ASCII-safe) either way.
- `altText`: **must be omitted or set to a non-identifying string.** It is rendered as human-readable text
  under the barcode. It must never contain the token, the atom id, the holder's name, or an order reference.
- **Payload size:** an Ed25519 signature is 64 bytes (~86 chars base64url); with compact claims the token is
  ~250–350 characters, comfortably inside QR capacity at a scannable module size.

---

## 6. Update / push architecture

> **Accuracy rule applies throughout this section.** Apple's pass update protocol is a documented web service
> with a fixed path shape, but every specific path, header, status code, and payload below is labelled.

### 6.1 The pass update web service — `NEW EDGE FUNCTION` `wallet-pass-webservice` (package **084**)

`pass.json` carries `webServiceURL` and a per-pass `authenticationToken`; when both are present iOS registers
the pass for updates and calls the service. *(Documented Apple platform behaviour — confident.)*

`UNVERIFIED — confirm every row against Apple documentation before implementation:`

| Verb + path (relative to `webServiceURL`) | Purpose | Auth | Notes |
|---|---|---|---|
| `POST /v1/devices/{deviceLibraryIdentifier}/registrations/{passTypeIdentifier}/{serialNumber}` | register device for updates; body carries `pushToken` | `Authorization: ApplePass <authenticationToken>` | 201 new / 200 already registered |
| `DELETE` (same path) | unregister | same | |
| `GET /v1/devices/{deviceLibraryIdentifier}/registrations/{passTypeIdentifier}?passesUpdatedSince=<tag>` | list serials with updates | same | 200 + `{serialNumbers[], lastUpdated}`; 204 when none |
| `GET /v1/passes/{passTypeIdentifier}/{serialNumber}` | fetch the updated `.pkpass` | same | honours `If-Modified-Since` → 304 |
| `POST /v1/log` | device diagnostic log | none | |

**Security posture — called out explicitly.** This function must run **`verify_jwt: false`**, because iOS
presents `Authorization: ApplePass <token>`, not a Supabase JWT. **`SPEC CORRECTION`: this section said it was
*"the second function in the entire system with `verify_jwt=false`, after `stripe-webhook`"*. That count is
wrong and is not this document's to state — edge §7 enumerates **five**, including **`door-session`**, which
relays scan and offline-batch calls while holding the service-role key. **The count lives in edge §7 and
nowhere else**; this document cites it. Compensating controls, all mandatory:
- the `authenticationToken` is compared **constant-time** against `auth_token_hash` (edge §7 invariant I-9,
  `timingSafeEqual`);
- the token authorizes **one serial only** — never a session, never an account, never another pass;
- **the token authorizes one serial only *while that pass is live and its holder still owns the atom*** — the
  auth-token compare is **not** the whole authority. Every route that returns or rebuilds pass content goes
  through `get_wallet_pass_build_context`, which additionally requires `status='issued'` **and**
  `holder_identity_id = kernel.tickets.current_owner_id`, read live (**§11.6a — the H-4 fix**). Without it a
  former owner reads `serialNumber` and `authenticationToken` out of their own `.pkpass` — it is a zip — and
  polls this endpoint for the current state of a ticket they sold. **A pass file is not a bearer credential
  for its atom's *current* state, and the auth token must never be treated as one;**
- `check_rate_limit` keyed on the derived principal `uuidv5(NS_WALLET_PASS, serial_no_opaque || ':' ||
  deviceLibraryIdentifier)` — see edge §7's derived-principal rule; `check_rate_limit`'s first parameter is a
  `uuid`, so the pair cannot be passed as-is — **fail-closed** (429/503 with `Retry-After`);
- **no enumeration:** an unknown serial and a wrong token return the **same** status with the same timing
  budget;
- responses carry no PII beyond what is already inside the pass the caller authenticated for;
- CORS is irrelevant (device-originated) but the security headers from the existing functions still apply.

**All DB access is through definer RPCs** (§11.6) using `service_role`; the function never issues raw SQL and
never reads a table directly.

### 6.2 APNs

- The push tells the device *"something changed for this pass"* — the device then calls the web service to
  find out what. *(Documented Apple platform behaviour — confident.)*
- `UNVERIFIED — confirm against Apple documentation before implementation:` the APNs **topic for a pass push is
  the `passTypeIdentifier`** (not an app bundle id); the payload is **empty** (`{}`) and carries no `aps`
  alert; the priority/`apns-push-type` header value required for pass updates.
- `UNVERIFIED — confirm against Apple documentation before implementation, and treat as an implementation
  risk:` whether **token-based APNs authentication (a `.p8` auth key + key id + team id)** is accepted for
  pass-type topics, or whether certificate-based authentication using the Pass Type ID certificate is
  required. This materially changes §8's custody design — if certificate-based auth is required, the Pass Type
  ID identity is used for *two* jobs (signing bundles and authenticating to APNs), and the KMS handle must
  support both operations.
- **Delivery is best-effort.** APNs offers no delivery guarantee to an offline device. **No safety property in
  this document depends on a push arriving** (§4.4). Pushes are retried with backoff up to
  `config('wallet.apple.push_retry_max')`; permanent failures (device unregistered / invalid token) mark the
  registration `unregistered` and are not retried.

### 6.3 What triggers a push

Driven by the existing outbox (CDM C12 envelope: per-aggregate monotonic `sequence`, `causation_id`,
`correlation_id`, at-least-once, consumer idempotent by dedup key). `NEW EDGE FUNCTION` `wallet-pass-push`
(package **084**) drains it.

| Trigger | Source | Priority |
|---|---|---|
| `credential_version` bump (custody move, void) | `kernel.transfer_ticket_ownership` / `void_ticket_atom` outbox row | **always, unconditionally** |
| atom `→ scanned` | `kernel.mark_ticket_scanned` | best-effort |
| `resale_state` change | `lock_ticket` / `unlock_ticket` / listing lifecycle | best-effort |
| session time / venue / status change, `catalog.cancel_event` | catalog outbox | **always** |
| `DoorManifestDrained` (door spec event #40 — a listing or pending transfer cancelled at door-open) | market outbox | best-effort |
| pass-type certificate rotation | `rotate_pass_type_cert` | batch, low priority |

Dedup key: `(wallet_pass_id, trigger_kind, cause_ref)`. Consumers are idempotent; a replay re-pushes at worst.

### 6.4 Does the door freeze let us stop pushing? — argued, then checked against re-opens

**The argument.** After `door_open_at`, `is_transfer_frozen` is true and terminal for the session, so
`transfer_ticket_ownership` and the routine `void_ticket_atom` path are rejected `frozen` (door spec §7.6).
No custody move ⇒ no `credential_version` bump ⇒ the barcode cannot change ⇒ the only remaining reason to push
is cosmetic (a "Used" face after scanning).

**Check against re-open episodes.** A re-open creates a new `manifest_version` and a fresh snapshot but
explicitly **does not move `door_open_at`** (door spec §7.2, §14 #6). The freeze is monotone and terminal, so
the argument survives re-opens unchanged — indeed re-opens are precisely why the argument survives: if closing
an episode cleared the boundary, transfers would resume between episodes and the conclusion would collapse.

**Check against the exceptions.** `kernel.grant_door_freeze_override` (§4.3's residual) *can* permit a custody
move post-freeze — it requires no open episode, but `door_open_at` is already set by then. Platform
force-void likewise. So the conclusion "no bump can occur post-freeze" is **true under the routine paths and
false under break-glass**.

**Ruling — the safe form of the conclusion.** **Push on every `credential_version` bump, unconditionally,
forever.** The freeze is a *load-reduction observation* (post-freeze pushes become rare, which is useful for
capacity planning at doors-open), **not a licence to skip them**. A rule of the form "stop pushing after
`door_open_at`" would be exactly correct under the routine paths and silently wrong under the audited
exceptions — the failure shape this whole programme exists to eliminate. `NO SCHEMA CHANGE`.

---

## 7. Transfer · resale · refund · void · cancellation · event update

### 7.1 Transfer (native p2p) and native resale — the pass-after-ownership-change flow

Both run through `kernel.transfer_ticket_ownership`, the **sole custody writer** (DA §9.4). One flow:

1. **Custody moves.** Ownership-log row appended; `current_owner_id` and `credential_version` advance to `N+1`
   in the same transaction (schema §1.5). **At this instant `A`'s pass is already dead as a credential** — no
   further step is required for §4's guarantee.
2. **Registry update** (`kernel.supersede_wallet_passes_for_atom`, definer, called from the outbox consumer —
   *not* inside the custody transaction, so a Wallet outage can never block a transfer):
   `A`'s `kernel.wallet_pass` row → `superseded`; `last_updated_at := now()`.
3. **Push to `A`'s registered devices.** On refresh, the web service returns a rebuilt pass for `S_A` whose
   **`barcodes` array is empty** and whose primary field reads *"No longer valid — this ticket was
   transferred."*
   `UNVERIFIED — confirm against Apple documentation before implementation:` that a pass may be updated to
   carry an empty `barcodes` array and still render (the alternative is a barcode whose message is a
   deliberately non-verifying sentinel — pick whichever Apple actually supports; **either is safe**, because
   the door rejects both).
   `UNVERIFIED — confirm against Apple documentation before implementation:` whether returning **410 Gone** on
   `GET /v1/passes/...` causes iOS to *unregister* the pass, and whether any response can cause iOS to
   **delete** an installed pass. **This design assumes deletion is impossible and never relies on it** (§4.4).
4. **`B` must add a new pass.** `UNVERIFIED — confirm against Apple documentation before implementation:` that
   a pass cannot be added to a user's Wallet without an explicit user gesture (`PKAddPassesViewController`
   confirmation). Assume it cannot. So the recipient flow is: push notification → open app → My Ticket detail
   → **Add to Apple Wallet** → new generation, new serial, new auth token.
   **This is a first-class flow, not an edge case** (§9.2) — a transferred-in ticket has no Wallet pass until
   the recipient adds one, and the RN copy must say so without mentioning generations or serials (RN §0).
5. **If `A` is offline:** step 3 is simply never delivered. See §4.4 — nothing about the guarantee changes.

**Door-open drain interaction.** Door spec §7.3 cancels pending p2p transfers and active listings when the
manifest opens. Cancel-to-self is C43-exempt: **owner and `credential_version` do not change**, so the sender's
Wallet pass remains valid and correct, and needs at most a cosmetic content refresh. This is the right outcome
and requires no special handling — recorded so an implementer does not "helpfully" supersede a pass on a drain.

### 7.2 Refund and void

`kernel.void_ticket_atom` bumps `credential_version` and moves the atom to `voided` (DA §3.1 — **there is no
`refunded` ticket terminal**; D2). Pass → `invalidated`, content *"No longer valid — refunded."*

Door outcomes for a presented invalidated pass:
- **online:** live read → `voided` → `admittable=false`, reason `voided`. Denied.
- **offline, void committed before the manifest opened:** `venue.door_manifest_entry` admits only
  `ticket_state ∈ {issued, active}` (door spec §10.3 check), so the atom is **absent from M2** ⇒ rejected.
- **offline, void committed after the manifest opened:** the routine refund-void path is **frozen** (C23, door
  spec §7.6), so this cannot happen routinely. A `platform_admin` force-void can — M2 still says `active`, and
  an offline door **admits**. That is the audited C6 residual, named in §4.3 and by door spec §5's "what the
  theorem does not cover."

**The refunded-but-scanned case** (door spec decouples money from custody: money refunded, atom never voided,
seat consumed):

| Question | Answer |
|---|---|
| What does the pass show? | Pass state is `consumed` (driven by `state='scanned'`, not by the refund). Content: *"Used — 11:42 PM."* The refund is a **money** fact and belongs in the app's order history, **not on the pass** — a pass that read "Refunded" would contradict the venue's own scan log and invite a chargeback argument at the door. |
| What does the scanner do if it is presented again? | **`duplicate`** — first-in-wins (C41, RPC §9.4 partial unique `(ticket_atom_id, event_session_id) WHERE result='admitted' AND direction='in'`). Deny, and show the first-scan time. Not `voided`, because the atom was never voided. The distinction is what makes the scan log defensible evidence. |
| Does the version change? | **No.** No custody moved and no void occurred, so `credential_version` is unchanged and the pass's barcode is still *current* — it is refused on **atom state**, not on staleness. This is the one case where a Wallet pass is refused for a reason that has nothing to do with §4, and stating it prevents a misdiagnosis at the door. |

### 7.3 Event cancellation and postponement — the honest guarantee

**Cancellation.** `catalog.cancel_event` voids the atoms (a bounded batch of SSCAS member #3) → versions bump
→ passes → `invalidated` → pushes queued.

- **Online devices:** pass updates to *"Event cancelled."* Best-effort, usually within seconds.
- **Offline devices:** the pass shows the last state it received, **indefinitely**. There is no mechanism to
  change that, and this document does not claim one.
- **At the door, online:** `venue.record_scan` requires `session.status = 'live'`; a cancelled session is not
  `live` ⇒ admission refused (door spec §14 failure #11).
- **At the door, offline: honestly, the scanner will admit.** M2 carries no session status, and the offline
  verify path (§2.3 checks 1–3c) never consults it. A device holding a valid M2 for a session cancelled after
  the episode opened will keep admitting locally until it reconnects. **This is a genuine gap in the frozen +
  door-lifecycle set, not a Wallet gap**, and this document does not paper over it. §14 **DL-2** requests that
  `catalog.cancel_event` close any open door-manifest episode, which disarms every device *on its next
  contact* — a real improvement that still does not help a device that never reconnects.
- **The honest guarantee, in one sentence:** *cancellation is enforced at online doors and is communicated
  best-effort to phones; an offline scanner will admit into a cancelled event until it reconnects, and the
  operational control for that is the venue not scanning a cancelled show.*

**Postponement / rescheduling.** The session moves; the atoms and their `credential_version` do not. Passes
update with the new date/time and the barcode is **unchanged** — correct, because custody did not move. Note
the interaction with door spec §10.2: once `door_open_at IS NOT NULL`, `starts_at`/`doors_at` edits are
**rejected**, so a postponement after doors opened is not representable and must be handled as a cancellation.
Worth surfacing in the venue runbook.

### 7.4 Event metadata updates

Title, venue, doors time, tier name, artwork: content-only. Push, rebuild, barcode untouched. `NO SCHEMA
CHANGE`. The pass's `relevantDate` (§9.1) is rebuilt from `COALESCE(doors_at, starts_at)`.

---

## 8. Key and certificate management

### 8.1 Two independent key systems — do not conflate them

| | **C33 credential signer** | **Apple Pass Type ID certificate** |
|---|---|---|
| Issued by | Snatch It (KMS keygen) | **Apple**, via the Apple Developer Program account |
| Identifier | `kernel.signing_key.key_id` (uuid) | `passTypeIdentifier` (reverse-DNS, e.g. `pass.com.snatchit.ticket`) + `teamIdentifier` |
| Scope | **per event** by default; per-venue allowed; global discouraged (C33, schema §1.7) | **account-level**, one active certificate per pass type identifier |
| Signs | the credential token (the barcode payload) | the `.pkpass` bundle's `manifest.json` (PKCS#7 detached) |
| Verified by | **the door**, every scan, against M1 public keys | **iOS**, once, at install time |
| Verified by the door | ✅ always | ❌ **never** |
| Custody | KMS/HSM; `kernel.signing_key.kms_handle_ref` is an opaque handle (schema §1.7) | KMS/HSM; `kernel.pass_type_cert.kms_handle_ref` is an opaque handle (§11.3) |
| Public half distributed to | doors (M1 manifest) — world-readable by design | nobody; the certificate travels **inside each `.pkpass`** |
| Rotation trigger | `kernel.rotate_signing_key`; per-scope; validity **overlap** so in-flight credentials keep verifying (edge §5.6) | **calendar** — Apple certificate expiry |
| Rotation cadence | per event (default scope), or on compromise | `UNVERIFIED — confirm against Apple documentation:` Apple Pass Type ID certificates are believed to be issued with roughly **one year** validity and must be renewed in the developer portal |
| **Compromise blast radius** | **forged credentials** for that scope, accepted by offline doors until M1 refreshes — an admission-security event | **forged `.pkpass` files** that install cleanly on iOS — but which **carry no valid credential and therefore cannot admit**. A brand and phishing event, **not an admission event.** |
| **Expiry blast radius** | `credential-sign` 500s; clients fall back to cached tokens; doors keep verifying already-issued tokens against retained keys | **no new passes can be built and no pass update can be signed** — a silent, calendar-driven outage of the whole Wallet feature |

**The two rows to internalize.** (1) An Apple-certificate compromise **does not compromise admission**, because
the door never checks it — that is the direct payoff of §2.2's two-signature separation. (2) The Apple
certificate is **the only object in this design that fails on a calendar rather than on an event**, which is
why §13 makes its expiry a monitored, alerted, owner-assigned obligation rather than a note.

### 8.2 The absolute custody rule

> **No private key material of any kind — the C33 signer, the Apple Pass Type ID private key, the APNs auth
> key, or any per-pass `authenticationToken` in plaintext — may exist in git, in the React Native bundle or its
> EAS/native build inputs, in browser JavaScript, in an environment variable's *value*, or in a
> world-readable, client-readable, or `authenticated`-readable database column.**

| Secret | Where it lives | What the DB stores | What the client sees |
|---|---|---|---|
| C33 signer private key | **KMS/HSM only** (C33, edge §5.3) | `kernel.signing_key.kms_handle_ref` — an opaque ARN | nothing |
| Apple Pass Type ID private key | **KMS/HSM only** | `kernel.pass_type_cert.kms_handle_ref` — an opaque ARN | nothing |
| Apple WWDR intermediate + the pass-type **certificate** | public by nature | `certificate_pem`, `wwdr_cert_pem` (platform-read only — no reason to expose them) | inside the `.pkpass` they downloaded |
| APNs auth key (`.p8`) or APNs client certificate | **KMS/HSM or the platform secret store** | nothing | nothing |
| Per-pass `authenticationToken` | **envelope-encrypted** (`auth_token_enc`) + a hash (`auth_token_hash`) | both columns, **audit-only RLS**, no client policy, no RPC returns either | only inside their own `.pkpass` |
| APNs device push token | **envelope-encrypted** (`push_token_enc`) | audit-only RLS | nothing |

Environment variables hold **references only** — `KMS_SIGNER_ROLE_ARN`, `KMS_ENDPOINT`,
`APPLE_PASS_KMS_HANDLE`, `APNS_KEY_KMS_HANDLE`, `APPLE_TEAM_ID`, `APPLE_PASS_TYPE_ID` — never material
(edge §7: *"No key material in env"*).

**CI enforcement (`SPEC CORRECTION` to the CI gate).** A repository scan job fails the build on any tracked
file matching `*.p12`, `*.p8`, `*.cer`, `*.pkpass`, `*.mobileprovision`, or any file containing
`-----BEGIN … PRIVATE KEY-----`. **Today the repo is clean on all of these — VERIFIED (§0.1) — so this gate
can be added green and can only ever go red on a regression.**

### 8.3 Offline strengthening — step 3c — **REQUIRED** (`SPEC CORRECTION`)

Add to the offline verify (§2.3): `token.key_id == M2[atom].signing_key_id`.

> **`SPEC CORRECTION`.** This was *"recommended, not required"* and had **no online counterpart** — so the
> claimed blast radius of a key compromise ("one event") was **not achieved**: any key in a door's M1 manifest,
> in-window and un-revoked, forged admission for any atom of any session that door could scan, and the one
> check that would have caught it was optional offline and absent online. A control that is optional on one
> path and missing on the other bounds nothing. **3c is now required, on both paths:**
>
> - **Offline:** `token.key_id == M2[atom].signing_key_id` — mandatory conjunct 3c of `OFFLINE-VERIFY-v1`.
> - **Online:** `venue.validate_ticket_online` MUST return `signing_key_id` and the door MUST compare it to
>   `token.key_id`, refusing on mismatch. **This is a result-shape change to RPC §9.3 — reported to the RPC
>   contract owner, not made here.**
> - **Delta-supplemented atoms** must carry a pinned key: door §10.3a's CHECK is tightened to
>   `(op='add') ⇒ signing_key_id IS NOT NULL`.
>
> With both paths carrying it, a compromised key from another scope is refused at every door for every atom it
> was not pinned to, and "blast radius = the atoms actually pinned to that key" becomes a fact rather than a
> claim.

**Why it is sound:** `kernel.tickets.signing_key_id` changes only at issuance and at transfer (edge §5.2: a
mid-event rotation deliberately does **not** re-pin already-issued credentials, so they keep verifying against
the key they were pinned to). Under the freeze no transfer commits during an episode, so M2's `signing_key_id`
equals the live pin equals what the current owner's token carries.
**Assumption, named, in the same sentence as the guarantee:** step 3c is safe **only while
`kernel.tickets.signing_key_id` is re-pinned exclusively at issuance and transfer.** An implementer who adds a
bulk re-pin (e.g. a rotation sweep that re-pins live atoms) breaks 3c and must remove it in the same change.

**Now that 3c is mandatory, that assumption gets a guard rather than a sentence** (`SPEC CORRECTION` to §12):
a pgTAP structural assertion that **no function other than the issuance and transfer RPCs writes
`kernel.tickets.signing_key_id`** — asserted over `pg_get_functiondef`, the same technique §12 W-F 31 already
uses. A bulk re-pin then fails CI at the moment it is written, instead of failing at a door.

**What it buys:** an independent staleness signal that does not depend on the version counter, and a defence
against a compromised key from a *different* scope being used to mint tokens for this session's atoms — check
1 alone would accept such a token if the attacker's key is in M1 and in-window.

### 8.4 Rotation

**C33 signer** — unchanged from edge §5.6. Note one Wallet-specific consequence: **existing Wallet passes are
unaffected by a signer rotation**, because their tokens are pinned to the old key and revoked/rotated keys are
retained permanently so old credentials stay verifiable (schema §1.7 Archival). No mass re-push is needed.
This is a real benefit of the pinning design and should not be undone.

**Apple Pass Type ID certificate** — `kernel.rotate_pass_type_cert` (`NEW RPC`, §11.6), wrapped by
`pass-cert-provision` (`NEW EDGE FUNCTION`):
1. new certificate obtained from Apple and imported into KMS (manual, out-of-band, `platform_admin`, dual-
   controlled per DA §12.4);
2. one DB transaction: old row `active → rotating`, new row `active`, both under the partial
   `UNIQUE(pass_type_identifier) WHERE status='active'`;
3. **new passes** are built and signed with the new certificate immediately;
4. **existing installed passes** — `UNVERIFIED — confirm against Apple documentation before implementation:`
   whether an installed pass keeps working after the certificate that signed it expires (believed yes; iOS
   validates at install), and whether an **update** to that pass may be signed by a *different, current*
   certificate for the **same** `passTypeIdentifier` (believed yes — the identifier is what binds). **If the
   second belief is wrong, rotation requires every holder to re-add, which is a materially different product
   experience and must be discovered before implementation, not after.** This is the single highest-value
   Apple fact to verify in this document.
5. old row → `revoked`/`expired` at `not_after`; retained permanently for audit.

### 8.5 Compromise runbook

**C33 signer suspected exposed** — edge §5.6 unchanged: revoke → rotate → push an M1 manifest refresh to all
doors of the scope → force client re-sign → for the offline-skew residual, tighten the affected event to
online-only scanning until manifests are confirmed refreshed → audit + Sentry.
**Wallet addition:** because wallet-profile tokens are session-bounded (§5.2), a signer compromise **must**
trigger the M1 refresh — it is the only bound on a forged token, and `exp` will not help. **And
`revoke_signing_key` must force-close every open door-manifest episode in the key's scope in the same
transaction** (edge §5.6, door §8.2.1, `reason='key_revoked'`) — this is door OQ-5's second grant condition,
and it is what collapses the exposure from the token's remaining life to the device's offline duration. **Do
not treat the M1 refresh as sufficient on its own:** an offline door does not see M1 refresh either. Wallet passes for
the affected scope are rebuilt and re-pushed with tokens signed by the new key; devices that never reconnect
keep a token signed by a revoked key, which check 1 rejects at every door that has refreshed M1.

**Apple Pass Type ID private key suspected exposed:**
1. **State the blast radius correctly, first, in the incident channel:** *the attacker can produce installable
   `.pkpass` files that look like Snatch It tickets. They cannot admit anyone.* Preventing an
   over-reaction that pulls the credential signer is part of the runbook.
2. Revoke the certificate in the Apple Developer portal; issue a replacement for the same
   `passTypeIdentifier`.
3. `kernel.revoke_pass_type_cert` then `kernel.provision_pass_type_cert` + `rotate_pass_type_cert`.
4. Rebuild and re-push every `status='issued'` pass (batch, low priority — see §8.4 step 4's `UNVERIFIED`).
5. **Do not rotate the C33 signer** unless there is independent evidence it was also exposed. They are
   different keys with different custody; conflating them turns a brand incident into an admission incident.
6. Public communication: forged passes are a **phishing** vector (a fake pass linking to a fake site), so the
   response is a customer-comms action, not a door action.
7. `kernel.admin_audit` rows for every step; Sentry alert; post-incident review.

**Per-pass `authenticationToken` compromise (single pass, e.g. a leaked pass file):** `kernel.revoke_wallet_pass`
→ pass `revoked`, all its device registrations unregistered, holder prompted to re-add (new generation, new
serial, new token). **No credential impact** — the auth token grants only "fetch/register this one pass."

**APNs auth key compromise:** rotate the key in the Apple Developer portal and in KMS. Impact: an attacker
could send empty pushes to Snatch It passes, causing devices to call the web service — a nuisance and a
rate-limit event, not a data exposure, because the push carries no payload and the web service still requires
the per-pass `authenticationToken`.

---

## 9. RN "Add to Apple Wallet" surface — `NEW RN SURFACE`

Governed by RN §0's product-language rule: **no screen copy may say "manifest", "credential version",
"generation", "serial", "token", or "signing key".**

### 9.1 What the pass carries — privacy ruling

| `pass.json` element | Value | Rationale |
|---|---|---|
| style | `eventTicket` | `UNVERIFIED — confirm the exact pass-style key and its field-layout constraints against Apple documentation.` |
| `organizationName` | `Snatch It` | |
| `description` | event name + date | accessibility string |
| `serialNumber` | **opaque random 128-bit**, base32 | **never** the atom id, never a sequential serial, never derived from anything guessable — it is an addressable web-service key |
| `passTypeIdentifier`, `teamIdentifier` | from `kernel.pass_type_cert` | |
| `webServiceURL`, `authenticationToken` | §6.1 | token ≥16 chars random. `UNVERIFIED — confirm Apple's minimum length requirement.` |
| header / primary / secondary fields | event name · venue · date & doors time · tier ("General Admission") | |
| **holder name** | **ABSENT** — see below | |
| `barcodes[0].message` | the wallet-profile credential token (§5.2) | |
| `barcodes[0].altText` | omitted, or a non-identifying string | never the token, atom id, name, or order ref |
| **any "Valid" / status field** | **ABSENT** — binding rule from §4.4 | a Wallet pass cannot re-read state, so it must not assert validity |
| `relevantDate` | `COALESCE(doors_at, starts_at)` | `UNVERIFIED — confirm the key name and lock-screen relevance behaviour.` |
| `locations` / `maxDistance` | venue coordinates | `UNVERIFIED — confirm keys, the 10-location limit believed to apply, and geofence behaviour.` |
| `expirationDate` / `voided` | set on `invalidated` / `expired` | `UNVERIFIED — confirm both keys and exactly what iOS does when voided is true (believed: the pass renders greyed and moves to an expired group).` |
| `semantics` (event/venue metadata) | optional | `UNVERIFIED — confirm the semantic-tag vocabulary; omit entirely if unverified rather than guessing.` |

**Privacy ruling — no holder name on the pass. `NEW RN SURFACE` decision, owner-confirmable (§15 OQ-W1).**

A Wallet pass surfaces on the **lock screen** when relevant by time or location. A lock screen reading
*"Jane Doe · <Club> · Tonight 11:00 PM"*, on a phone left on a bar in a nightlife venue, tells any stranger a
named person's location, that they are out, and that they are not home. For this platform's demographic and
venue type that is a physical-safety leak, not a theoretical one — and it buys nothing, because **the door
verifies a credential, not a person** (DA §9.3), so the name is never checked against anything.

The same instinct is already ratified elsewhere: door staff never receive a bulk attendee list (DA §7.2, VD §5
note 11), and `venue.door_manifest_entry` is specified to carry **no identity column by construction** (door
spec §10A.2). Printing the holder's name on a lock-screen artifact would be the loudest possible violation of
that posture.

If a venue later needs name-matching, it belongs on the scanner's **authenticated single-record lookup**
(`venue.validate_ticket_online`, RPC §9.3 / VD §12.6) — behind a role, not printed on a lock screen.

**Location relevance is retained** (the pass surfacing at the venue is the feature's main convenience), and the
residual is acceptable: a lock screen revealing "this person is here for this event" at a venue reveals only
what the person's physical presence already reveals.

### 9.2 Surfaces

**My Ticket detail (RN §4.4.1) — add one control.** "Add to Apple Wallet", using Apple's official badge.
`UNVERIFIED — confirm the current "Add to Apple Wallet" badge assets, required localizations, minimum sizes,
and marketing guidelines before implementation;` badge misuse is a common App Review rejection.

Visibility:
- iOS only; hidden entirely on Android/web (RN never renders a disabled control a platform cannot satisfy).
- `state = 'active'` only (§1.2).
- **hidden while `resale_state ∈ {listed, locked}`** — a ticket being sold or transferred should not gain a
  new copy on a device. It reappears on delist/unlock. (§15 OQ-W5 — mirrors the same open question edge §3.2
  flags for `credential-sign` on a listed atom; the two should be answered together.)
- hidden when `config('wallet.apple.enabled') = false` (the kill switch, §11.5).
- Once added, the control becomes **"Re-add to Apple Wallet"** and remains available forever (recovery path).

**Transfer-in flow (RN §4.5 step 7).** After accepting a transfer, the recipient's confirmation screen offers
"Add to Apple Wallet" inline. Copy: *"Add this ticket to Apple Wallet."* No mention of the sender's pass, no
mention of invalidation — the sender's pass is not the recipient's business, and the product-language rule
forbids explaining the mechanism.

**Sender after transferring out.** No new surface. The ticket leaves the Tickets tab (RN §4.5 step 7,
unchanged). **The app must not claim the Wallet pass was removed** — it cannot be, and saying so would be a
lie the user can disprove by opening Wallet. If copy is needed: *"This ticket is no longer yours. Any copy in
Apple Wallet won't work at the door."* — true, verifiable, and it does not over-promise.

### 9.3 Failure and recovery UX

| Failure | Behaviour | Copy (product language) |
|---|---|---|
| Device offline when tapping Add | building requires the server; do not fake it | *"You'll need a connection to add this to Apple Wallet. Your Entry Pass in the app still works."* |
| KMS unavailable / certificate expired / `pass-cert` misconfigured | 503 from `wallet-pass-issue`; **the in-app Entry Pass is never gated on this** | *"Apple Wallet is temporarily unavailable. Use your Entry Pass in the app."* |
| `wallet.apple.enabled = false` | control absent, no error | — |
| iOS refuses the pass (malformed / signature invalid) | log + Sentry + retry once with a rebuilt pass, then surface | *"We couldn't add this to Apple Wallet. Your Entry Pass in the app still works."* |
| Holder deleted the pass from Wallet | "Re-add to Apple Wallet" always available; serves the **same generation** (same serial, same auth token) | *"Add to Apple Wallet"* |
| Holder switched devices | the new device registers on add; the old registration ages out on push failure | — |
| Pass shows stale content (push missed) | opening the app and re-adding always yields current content; the door is authoritative regardless | *"Re-add to Apple Wallet"* |

**Design rule, binding, repeated from §4.4:** the Wallet pass never displays a validity assertion. The
**in-app** Entry Pass keeps its live "valid" indicator (RN §4.4.2) — that asymmetry is intentional and must
survive code review.

**Absolute rule:** no admission path may require Wallet. The in-app Entry Pass (RN §4.4.2) is the primary
surface; Wallet is a convenience layer over the same token.

---

## 10. Scanner and venue behaviour

### 10.1 The scanner must not know Wallet exists — `NO CHANGE` to the scanner's decision logic

A camera sees a QR code. It **cannot** determine whether that QR was rendered by Wallet, by the Snatch It app,
by a screenshot, or by a printout — and it must not try. **Any scanner code path that branches on delivery
surface is a security bug**, because the branch condition is unverifiable and therefore forgeable.

Consequences:
- one decoder (QR, §5.4);
- one verification pipeline (§2.3), applied identically;
- no "Wallet pass" result state in RN §7.2's banner set;
- no `aud` claim inspection (the door ignores `aud` entirely, §5.2);
- **no new scanner UI at all.** The scanner changes required for Wallet are exactly the changes already
  required by the door-lifecycle spec: offline-verify step 3b and the `awaiting_manifest` state.

### 10.2 Scanner implementation requirements this document depends on

Stated so they are not assumed (they are the door-client half of §4's assumptions A3 and A4):

1. **The door must evaluate every conjunct of `OFFLINE-VERIFY-v1` — all five of 3b, plus 3c** — against the
   **applied** set `M2 = base_snapshot ⊕ deltas[1 .. last_synced_seq]`, never the base snapshot alone. Online,
   it must compare both the returned `credential_version` **and** the returned `signing_key_id` to the token's.
   Obtaining a reference value and not comparing it is the whole of defect W-3 reproduced at the client;
   **comparing three of five is H-2 reproduced at the client**, and it fails in the direction that admits.
   The scanner build MUST carry **one failing-case regression test per conjunct** — the case table in edge
   §5.4.3 is the required minimum set, and it includes the `resale_state ∈ {locked, refund_hold}` cases that
   the two-conjunct wording admitted.
2. **Offline, no M2 ⇒ no admit.** Never "verify signature and let them in."
2a. **The manifest must actually carry what the predicate reads — `SPEC CORRECTION` (`MP-1`).** Item 1 is a
   requirement on the *scanner*; it is unsatisfiable if the wire omits an input, and for a period it did.
   Door §7.5 and RPC §20.6.1 described **two different** M2 wire shapes, and each was missing a different
   conjunct's input — `resale_state` (3b.v) from one, `ticket_state` (3b.iv) and the delta's `signing_key_id`
   (3c, for every atom supplemented after doors open) from the other. **This is §10.2's own failure mode
   arriving one layer earlier than §10.2 anticipated:** a scanner that dutifully evaluates all six conjuncts
   still admits a `paid_pending_transfer` atom if `resale_state` never reached it, and the scanner is not the
   defective component. Door **§7.5a** now binds the projection as a superset of the predicate's read set,
   with a structural acceptance property in both contracts (door §15 assertions 77–83, RPC
   `T-RPC-DOOR-33`/`-34`). **A scanner build MUST fail closed if a field the predicate reads is absent from
   the manifest it received** — an absent field is not a passed check, and treating a missing input as
   satisfied is H-2 restored by omission.
3. **`version_stale` must render as an unmistakable deny banner** reusing the existing operator copy
   *"This pass is out of date. Ask them to open the Snatch It app."* (door spec §11.2) — **no new vocabulary**.
   Critically, the copy must not imply the pass is fake: a stale pass is usually an honest previous owner, not
   a fraudster, and door staff escalate very differently for the two.

### 10.3 Venue operational requirements

- Sync M2 and all devices **at soundcheck**, hours before doors (door spec §14.5).
- After any platform break-glass touching the session, **re-sync every device before resuming offline
  admission** (§4.3, requested as door-spec change **DL-3**).
- A cancelled show is **not scanned** — the offline path does not enforce cancellation (§7.3).

### 10.4 The no-visual-admission rule — binding

**A pass is never admitted by sight.** Not when the scanner is down, not when the queue is long, not when the
pass "obviously looks right", not when a manager vouches. The fallback for a pass that will not scan is the
scanner's **manual single-record lookup** (`venue.validate_ticket_online`, RN §7.1 step 5) — which performs the
same authoritative check — never a human eyeballing a lock screen.

This is the only mitigation for §4.4's residual, and it is the reason that residual is acceptable. It belongs
in the door runbook, in door-staff training, and in the scanner's offline banner copy.

---

## 11. Schema · RLS · RPC · Edge deltas

### 11.1 `kernel.wallet_pass` — `ADDITIVE SCHEMA CHANGE` (new table) — package **084**

- **Purpose:** the registry of Wallet pass artifacts. One row per (atom, custody tenure). The SoT for "which
  pass artifact is live for this atom", and the evidence for "which artifact was on which device when".
- **Schema:** `kernel` — it is a credential-delivery object, custody-adjacent, and it holds encrypted secrets.
- **PK:** `wallet_pass_id` uuid.
- **Columns:** `wallet_pass_id` uuid PK; `ticket_atom_id` uuid not null FK→`kernel.tickets` on delete
  restrict; `holder_identity_id` uuid not null FK→`auth.users(id)` on delete restrict — **a snapshot of the
  owner at mint, deliberately not a head**, so a divergence from `kernel.tickets.current_owner_id` is
  detectable; `generation` integer not null (per-atom monotonic, starts at 1); `serial_no_opaque` text not
  null (random 128-bit, base32); `pass_type_cert_id` uuid not null FK→`kernel.pass_type_cert`;
  `auth_token_enc` bytea not null (envelope-encrypted); `auth_token_hash` text not null;
  `credential_version_at_build` integer not null; `signing_key_id` uuid not null FK→`kernel.signing_key`;
  `status` enum(`issued`·`superseded`·`revoked`·`consumed`·`invalidated`·`expired`) not null default `issued`;
  `status_reason_code` text nullable; `built_at` timestamptz not null default now(); `last_updated_at`
  timestamptz not null default now(); `command_idempotency_key` text not null; `created_at`, `updated_at`.
- **Unique:** `UNIQUE(ticket_atom_id, generation)`; `UNIQUE(serial_no_opaque)`;
  `UNIQUE(holder_identity_id, command_idempotency_key)`;
  **partial `UNIQUE(ticket_atom_id) WHERE status = 'issued'`** — *at most one live pass generation per atom,
  enforced by the database, not by the RPC.* **This constraint is the structural half of the non-negotiable**
  (§3.3): a previous owner's pass row cannot remain `issued` while the new owner's exists.
- **Check:** `generation >= 1`; `credential_version_at_build >= 0`; `length(serial_no_opaque) >= 20`;
  enum coherence; `last_updated_at >= built_at`.
- **Immutability:** identity columns (`wallet_pass_id`, `ticket_atom_id`, `holder_identity_id`, `generation`,
  `serial_no_opaque`, `pass_type_cert_id`, `credential_version_at_build`, `signing_key_id`, `built_at`) **IMM
  after insert.** `status` transitions **forward only** (`issued → {superseded|revoked|consumed|invalidated|
  expired}`; no reverse, no terminal→terminal). `last_updated_at` MUT. A guard trigger rejects every other
  UPDATE and every DELETE (schema §0.8 AO pattern).
- **Index:** PK; the partial unique doubles as the live-pass lookup; `UNIQUE(serial_no_opaque)` is the web
  service's hot path; index on `(ticket_atom_id)`; index on `(status, last_updated_at)` for the push drain.
- **Archival:** permanent (registration evidence; also the audit trail behind "who held a working pass when").
- **RLS:** **audit-only for the secret columns; owner-scoped for the rest.** No client policy grants SELECT on
  `auth_token_enc`, `auth_token_hash`, or `serial_no_opaque`. The owner may read only
  `{wallet_pass_id, ticket_atom_id, status, built_at, last_updated_at}` for their **own** atoms, and only via
  an RPC (there is no client table read). Writes RPC-only.
- **Write authority:** `kernel.mint_wallet_pass`, `kernel.supersede_wallet_passes_for_atom`,
  `kernel.revoke_wallet_pass`, `kernel.touch_wallet_pass`, `kernel.sweep_wallet_pass_lifecycle`.
- **SoT/PROJ:** SoT.

### 11.2 `kernel.wallet_pass_device` — `ADDITIVE SCHEMA CHANGE` (new table) — package **084**

- **Purpose:** Apple device registrations for pass updates. Holds an APNs push token, which is both a secret
  and a tracking identifier.
- **PK:** `registration_id` uuid.
- **Columns:** `registration_id` uuid PK; `wallet_pass_id` uuid not null FK→`kernel.wallet_pass` on delete
  restrict; `device_library_identifier` text not null (Apple-supplied, opaque); `push_token_enc` bytea not
  null (envelope-encrypted); `registered_at` timestamptz not null default now(); `unregistered_at` timestamptz
  nullable; `last_push_at` timestamptz nullable; `last_push_result` text nullable; `push_failure_count`
  integer not null default 0; `created_at`.
- **Unique:** `UNIQUE(wallet_pass_id, device_library_identifier)`.
- **Check:** `push_failure_count >= 0`; `unregistered_at IS NULL OR unregistered_at >= registered_at`.
- **Immutability:** AO on insert; the only permitted UPDATEs are `unregistered_at`, `last_push_at`,
  `last_push_result`, `push_failure_count`. Guard trigger; DELETE denied.
- **Index:** PK; the unique; partial index on `(wallet_pass_id) WHERE unregistered_at IS NULL` (the push fan-out).
- **RLS:** **audit-only** — RLS on, **zero policies**, `REVOKE ALL FROM anon, authenticated`. **No client, no
  venue role, and no org role ever reads a push token.** Platform read via an `is_platform` RPC only.
- **Write authority:** `kernel.register_wallet_pass_device`, `kernel.unregister_wallet_pass_device`,
  `kernel.record_wallet_push_result` — all definer, `service_role` only.
- **SoT/PROJ:** SoT.

### 11.3 `kernel.pass_type_cert` — `ADDITIVE SCHEMA CHANGE` (new table, key-reference, NO secret) — package **083**

- **Purpose:** the DB-side **reference** to the Apple Pass Type ID signing identity. **Structurally the same
  pattern as `kernel.signing_key` (schema §1.7): public certificate + opaque KMS handle, never key material.**
- **PK:** `pass_type_cert_id` uuid.
- **Columns:** `pass_type_cert_id` uuid PK; `pass_type_identifier` text not null (e.g.
  `pass.com.snatchit.ticket`); `team_identifier` text not null; `certificate_pem` text not null (**public**);
  `wwdr_cert_pem` text not null (**public**, Apple's intermediate); `kms_handle_ref` text not null
  (**opaque handle — NOT key material**); `status` enum(`active`·`rotating`·`revoked`·`expired`) not null
  default `active`; `not_before` timestamptz not null; `not_after` timestamptz not null; `created_at`,
  `updated_at`.
- **Unique:** **partial `UNIQUE(pass_type_identifier) WHERE status = 'active'`** — exactly one active
  certificate per pass type at a time; rotation flips old→`rotating`, new→`active` in one transaction. Mirrors
  §1.7's one-active-signer-per-scope discipline exactly.
- **Check:** `not_after > not_before`; enum coherence; `pass_type_identifier` matches a reverse-DNS shape.
- **Immutability:** `pass_type_identifier`, `team_identifier`, `certificate_pem`, `wwdr_cert_pem`,
  `kms_handle_ref`, `not_before`, `not_after` **IMM after creation**; only `status` transitions, audited.
- **Index:** PK; the active partial unique; index on `(status, not_after)` — **the expiry-monitoring query**
  (§13).
- **Archival:** permanent (retained so historical passes remain explicable and auditable, like revoked signing
  keys).
- **RLS:** **no client access at all.** Unlike `kernel.signing_key.public_key`, doors do **not** need this —
  they never verify the Apple signature (§2.2). `certificate_pem`/`wwdr_cert_pem`/`not_after` readable by
  `is_platform`; `kms_handle_ref` `is_platform` only. `REVOKE ALL FROM anon, authenticated`.
- **Write authority:** `kernel.provision_pass_type_cert`, `kernel.rotate_pass_type_cert`,
  `kernel.revoke_pass_type_cert` (all `is_platform([platform_admin])`).
- **SoT/PROJ:** SoT.

### 11.4 `kernel.wallet_pass_push_log` — `ADDITIVE SCHEMA CHANGE` (new table, AO) — package **084** — *recommended*

- **Purpose:** APNs attempt/outcome ledger. Not load-bearing for any safety property; it exists so the
  compromise runbook and the "did the holder ever get the update" question are answerable.
- **Columns:** `push_log_id` uuid PK; `wallet_pass_id` uuid not null FK; `registration_id` uuid nullable FK;
  `trigger_kind` text not null; `cause_ref` uuid nullable; `attempted_at` timestamptz not null default now();
  `outcome` enum(`sent`·`rejected`·`unregistered`·`error`) not null; `apns_status` integer nullable;
  `apns_reason` text nullable; `created_at`.
- **Unique:** `UNIQUE(wallet_pass_id, trigger_kind, cause_ref, registration_id)` — the outbox dedup key.
- **Immutability:** AO. UPDATE and DELETE denied.
- **RLS:** audit-only.
- **Archival:** 90-day rolling (Temporary/Analytics class, CDM §5) — it is diagnostics, not evidence.

### 11.5 `catalog.platform_config` seeds — `ADDITIVE SCHEMA CHANGE` (rows only, AO-per-version) — package **078**

| Key | Type | Default | Meaning |
|---|---|---|---|
| `wallet.apple.enabled` | boolean | **`false`** | **kill switch — gates the whole Wallet plane, not just minting (§11.5a).** Ships off; turned on only by a **mandatory-dual-control** config write after the §13 checklist is green; **turned off by a single `platform_admin`, directly** (§11.5b). |
| `credential.wallet_exp_skew` | interval | `'6 hours'` | added past session end for the wallet token profile (§5.2) |
| `credential.wallet_default_span` | interval | `'12 hours'` | used when `session.ends_at IS NULL` |
| `credential.app_ttl_interval` | interval | `'4 hours'` | names the existing app-profile TTL (edge §5.5 left it as prose) |
| `wallet.apple.push_retry_max` | integer | `5` | |
| `wallet.apple.cert_expiry_warn_interval` | interval | `'45 days'` | §13 alert threshold |

These are **operational thresholds, not secrets** — public-read like every other config value (door spec
§10A.6's reasoning applies verbatim).

### 11.5a What `wallet.apple.enabled = false` must actually stop — `SPEC CORRECTION`

> **The defect.** The kill switch gated **minting only** (`kernel.mint_wallet_pass`'s precondition, §11.6).
> Flipping it stopped *new* passes while **the installed fleet kept being served, rebuilt and pushed** — the
> population it is named to protect and the only population that can be harmed by a Wallet defect. A switch
> that protects the people who do not have the feature yet is not a kill switch.

With `wallet.apple.enabled = false`, **all four** of the following hold:

| Plane | Behaviour when disabled |
|---|---|
| **Mint** (`wallet-pass-issue` → `mint_wallet_pass`) | `precondition_failed('wallet_disabled')` for every caller **including `platform_admin`** — unchanged, and still not role-bypassable (§12 W-E 27). |
| **Serve / rebuild** (`wallet-pass-webservice`) | **every route returns `503` with `Retry-After`, uniformly** — the same response for every serial, every device, and every token, valid or not. Uniform **by route, never by pass**: a per-pass branch would be an enumeration oracle (§11.6a) wearing the kill switch's clothes. `get_wallet_pass_build_context` builds nothing. |
| **Register** (`register_wallet_pass_device`) | refuses; no new registration rows. Existing rows are **left intact**, so re-enabling does not require the fleet to re-add. |
| **Push** (`wallet-pass-push`) | stops draining Wallet triggers from the outbox. The rows are **not discarded** — they age normally and are re-drained on re-enable, because a skipped `credential_version` push is a stale face, and §6.4's ruling is *"push on every bump, unconditionally, forever."* |

**What the kill switch does NOT do, stated plainly so nobody plans around it.** It does **not** invalidate the
barcodes already installed on phones. That barcode is a C33 credential token; the door evaluates it under
`OFFLINE-VERIFY-v1` exactly as it evaluates the in-app Entry Pass, and it will keep admitting the current owner
of a live atom. **Admission safety never rested on this switch and must not be described as if it did** — it
rests on step 3b. What the switch buys is the ability to stop the *Wallet delivery plane* — the one part of the
feature that talks to devices we do not control — in one config write, without a client release. That is worth
having; it is not a revocation, and the incident runbook (§8.5) must not treat it as one. **Per-pass
revocation is `kernel.revoke_wallet_pass`; fleet-wide credential revocation is a signer rotation.**

### 11.5b Config namespace and dual control — `SPEC CORRECTION`

> **The defect.** `wallet.*` and `credential.*` sat **outside** the namespaces for which RLS §11 makes dual
> control **mandatory** (`refund.*`, `payout.*`, `authn.*`). Dual control was described as a *seam* for these
> keys, which is the default `set_platform_config` posture — so **one `platform_admin` could enable Wallet
> before the §13 checklist was green**, and one `platform_admin` could widen `credential.wallet_exp_skew`,
> which lengthens the life of a bearer credential.

**Required (reported to the RLS-spec owner, not made here):**
`PHASE_2_RLS_PERMISSION_SPEC.md` §11's `catalog.set_platform_config` row — the one that reads *"for keys in the
`refund.*` / `payout.*` / `authn.*` namespaces dual control is MANDATORY, not a seam"* — must add
**`wallet.*`** and **`credential.*`**. The row's own **direction asymmetry** then applies and is exactly right
for a kill switch:

- **Loosening executes with two approvers.** Setting `wallet.apple.enabled := true`, or *raising* any
  `credential.wallet_*` interval, creates a `kernel.approval_request` that a **second distinct
  `platform_admin`** must approve. Enabling a feature whose §13 checklist has eighteen items is exactly as
  consequential as raising a money threshold — and the checklist is the thing the second approver is there to
  have looked at.
- **Tightening executes directly.** Setting `wallet.apple.enabled := false`, or *lowering* any interval, needs
  **one** admin and no approval round. **A kill switch that needs a quorum is not a kill switch**, and the
  asymmetry is already the ratified pattern (RLS §11: *"a security control that is hard to tighten in an
  incident is a liability"*).

Door §10.6's three `door.session_*` keys take the same treatment for the same reason: they bound a bearer
credential.

### 11.6 RPC contracts — all `NEW RPC`, all **DB-RPC**

| RPC | Actor / EXEC authority | Purpose · notes |
|---|---|---|
| `kernel.mint_wallet_pass(p_atom_id, p_command_key)` | `authenticated`; **authorizes `current_owner_id = auth.uid()` internally, live-read (C35, I-5)** | Supersedes any prior `issued` generation for the atom, inserts generation *g+1*, returns build context to the **edge** (`serial`, `generation`, `credential_version`, `signing_key_id`, `pass_type_cert_id`, plaintext auth token **once, never stored in plaintext, never re-returned**). Preconditions: atom `state='active'`; `resale_state='none'` (§15 OQ-W5); `config('wallet.apple.enabled')`. Locks: `kernel.tickets` PK `FOR SHARE` (rank 5). **SSCAS: n/a** — no custody moves, no ownership-log row, **no `credential_version` bump.** Idempotency: `UNIQUE(holder_identity_id, command_idempotency_key)` + state guard (an existing `issued` generation for the same owner returns `noop_replay` with the same serial). Errors: `insufficient_privilege(42501)` · `precondition_failed(atom_not_active\|atom_listed_locked\|wallet_disabled)` · `not_found`. |
| `kernel.supersede_wallet_passes_for_atom(p_atom_id, p_reason_code)` | **`service_role`/definer only**; `REVOKE EXECUTE FROM anon, authenticated, public` | Marks every `issued` pass for the atom `superseded`/`invalidated`/`consumed`/`expired` per reason. Called from the **outbox consumer, not inside the custody transaction** — a Wallet failure must never be able to roll back or block a transfer. |
| `kernel.touch_wallet_pass(p_wallet_pass_id)` | `service_role`/definer | Bumps `last_updated_at` (drives `passesUpdatedSince` / `Last-Modified`). |
| `kernel.get_wallet_pass_build_context(p_serial, p_auth_token)` | `service_role`/definer | Web-service authentication + build inputs. **Constant-time comparison against `auth_token_hash` inside the function**, **plus the two liveness preconditions of §11.6a — `status='issued'` AND holder = live current owner.** Returns identical shape, status and timing for not-found, bad token, superseded pass and stale holder. |
| `kernel.register_wallet_pass_device(p_serial, p_auth_token, p_device_library_identifier, p_push_token)` | `service_role`/definer | Constant-time auth; upserts the registration; encrypts the push token. |
| `kernel.unregister_wallet_pass_device(p_serial, p_auth_token, p_device_library_identifier)` | `service_role`/definer | Terminal-state idempotent. |
| `kernel.list_updated_wallet_passes(p_device_library_identifier, **p_auth_token**, p_since)` | `service_role`/definer | **Signature corrected — §11.6b.** Constant-time auth against a pass **registered to that device**; serials drawn **only** from that device's live registrations, filtered by §11.6a's liveness rule; `serial_no_opaque` only. It previously took **no token** — the one multi-serial route was unauthenticated by contract. |
| `kernel.record_wallet_push_result(...)` | `service_role`/definer | Appends `wallet_pass_push_log`; increments `push_failure_count`; unregisters on a permanent APNs rejection. |
| `kernel.revoke_wallet_pass(p_wallet_pass_id, p_reason_code, p_command_key)` | `is_platform([platform_admin, platform_support])` | Support path (leaked pass file, lost device). Audited. |
| `kernel.provision_pass_type_cert` · `rotate_pass_type_cert` · `revoke_pass_type_cert` | **`is_platform([platform_admin])` only** | Mirrors `provision/rotate/revoke_signing_key`. Dual-controlled (DA §12.4). Audited. |
| `kernel.sweep_wallet_pass_lifecycle()` | `service_role`/definer (cron) | Reconciles pass status to atom state (`scanned`→`consumed`, `voided`→`invalidated`, post-event→`expired`) and enqueues pushes. **Explicitly NOT load-bearing:** every safety property in §4 holds whether or not this ever runs. Stated because "a correct thing that nothing called" is the exact failure class the door-lifecycle ruling was issued to eliminate. |

### 11.6a `get_wallet_pass_build_context` preconditions — the H-4 fix (`SPEC CORRECTION`, NORMATIVE)

> **The defect.** As contracted, this function's entire authority was the auth-token compare. It had **no
> `status='issued'` precondition** and **no comparison of `wallet_pass.holder_identity_id` against
> `kernel.tickets.current_owner_id`** — even though §11.1 documents `holder_identity_id` as a snapshot at mint
> *"so a divergence is detectable"*. **It was detected by nothing.** A former owner unzips their own `.pkpass`
> (it is a zip), reads `serialNumber` and `authenticationToken`, and polls the `verify_jwt=false` web service
> **with no device, no app, and no account** — a live oracle on a ticket they no longer own, and, if the
> service rebuilds at the live version, a credential *refresh* endpoint for someone else's ticket.
> Supersession was the only guard, and it runs **outside the custody transaction** (§11.6,
> `supersede_wallet_passes_for_atom`, deliberately, so Wallet can never block a transfer) — so between the
> custody commit and the outbox consumer draining, the only remaining check was one this function did not make.

**Normative.** `kernel.get_wallet_pass_build_context(p_serial, p_auth_token)` MUST return a build context
**only if all three hold**, evaluated in one statement, under one live read of `kernel.tickets`:

1. the presented token matches `wallet_pass.auth_token_hash` under a **constant-time** comparison (I-9);
2. **`wallet_pass.status = 'issued'`**;
3. **`wallet_pass.holder_identity_id = kernel.tickets.current_owner_id`** for the pass's `ticket_atom_id`,
   read **live, at this call** — not from a cached projection, not from the pass row.

Any of the three failing — and a serial that does not exist — returns the **identical result shape, the
identical status, and the same timing budget**. There is no discriminating error, no "pass superseded" hint,
no `wallet_disabled` branch visible to the caller: a distinguishable failure is the enumeration oracle in a
different costume.

**Precondition 3 is not redundant with precondition 2.** 2 depends on the outbox consumer having run; 3 does
not depend on anything having run. 3 is what makes the window between the custody commit and supersession
**zero-width**, and it is the reason `holder_identity_id` is stored as a snapshot at all.

**Rebuild rule (NORMATIVE).** A rebuild re-signs the barcode at **`wallet_pass.credential_version_at_build`** —
the version the pass was minted at — and **never** at the live `kernel.tickets.credential_version`. Rebuilding
at the live version would make the web service a credential-refresh endpoint for whoever holds the auth token,
which is exactly the authority §2.1 says a pass must never carry. **A pass whose version is behind the live one
is not brought up to date — it is superseded, and its holder re-adds** (§7.1). The only things a legitimate
rebuild changes are pass *presentation* fields (event time, venue, status face) and the certificate it is
signed with; the credential claim inside the barcode is immutable for the life of the generation.

**Two pgTAP assertions (added to §12 W-F):**

- `get_wallet_pass_build_context` with a **correct** token on a pass whose `holder_identity_id ≠` the live
  `kernel.tickets.current_owner_id` returns the **same** shape and status as an unknown serial.
- The same, with `status='superseded'` and a correct token.

### 11.6b `list_updated_wallet_passes` — the multi-serial route must be the most bound, not the least (`SPEC CORRECTION`)

> **The defect.** `kernel.list_updated_wallet_passes(p_device_library_identifier, p_since)` took **no auth
> token**. **The one endpoint in the design that returns *many* serials was unauthenticated by contract** — a
> direct contradiction of §6.1's own rule that *"the token authorizes one serial only."* Its only input was a
> `deviceLibraryIdentifier`, a value that arrives in the request path.

**Corrected signature and contract:**

`kernel.list_updated_wallet_passes(p_device_library_identifier, p_auth_token, p_since)` — `service_role`/definer.

1. **Authenticate first.** Constant-time compare `p_auth_token` against the `auth_token_hash` of the passes
   **registered to `p_device_library_identifier`**. At least one must match, or the call returns the
   **empty/204 shape** — the same shape an unknown device gets.
2. **Answer from registrations only.** Return serials **exclusively** from that device's live
   `kernel.wallet_pass_device` rows — never a scan over `kernel.wallet_pass` by `last_updated_at`. A
   registration exists only because an **authenticated** `register` call created it, so the device's reachable
   set is bounded by what it has already proved it holds.
3. **Apply §11.6a's liveness filter.** A pass that is not `status='issued'`, or whose `holder_identity_id` is
   no longer the live `current_owner_id`, is **omitted** — not reported as changed. A former owner's device
   must stop being told anything about a ticket that moved, and the omission must be indistinguishable from
   "nothing changed".
4. **Return `serial_no_opaque` only.** No `wallet_pass_id`, no `ticket_atom_id`, no counts, no timestamps
   beyond the `lastUpdated` tag Apple requires.
5. **Fail-closed rate limit** on `uuidv5(NS_WALLET_PASS, …)` (edge §7).

> **`UNVERIFIED — confirm against Apple documentation before implementation.`** Whether iOS sends
> `Authorization: ApplePass <token>` on the *list* path (`GET /v1/devices/{id}/registrations/{passTypeId}`) —
> §6.1's table asserts it does, and that row is already labelled `UNVERIFIED`. **This must be resolved before
> implementation, and the resolution changes only step 1, never steps 2–5.** If Apple does **not** send a token
> on this path, step 1 cannot be performed and the endpoint's whole authority becomes steps 2–5 plus the
> entropy of the `deviceLibraryIdentifier`. **That residual must then be written down and signed off in the
> §13 item 12 security review** — as a named, bounded exposure — rather than discovered by an implementer and
> quietly accepted, which is how it reached this spec unauthenticated in the first place.

**Unregistration must be real.** `supersede_wallet_passes_for_atom` and `revoke_wallet_pass` MUST mark the
pass's registrations `unregistered` (§8.5 already says so for the revoke path). Steps 2–3 are only as strong as
that severing.

### 11.7 RLS delta

Inherits RLS §1.3's global postures: **GP-1** (no client principal holds direct INSERT/UPDATE/DELETE on any
Phase-2 table) and **GP-2** (DELETE is `D` for every role on every table). Vocabulary per RLS §1.2:
`A` allow · `D` deny · `R` RPC-only · `V` scoped-read-only.

**`kernel.wallet_pass`** — owner-scoped read of non-secret columns; secrets audit-only.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon | D | D | D | D | — |
| **fan / current owner** | **V** — own atoms only, columns `{wallet_pass_id, ticket_atom_id, status, built_at, last_updated_at}`, **via RPC only** | R | D | D | `mint_wallet_pass` |
| every org role · every venue role (all six: `venue_manager` · `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `venue_scanner`) · every door-session principal | **D** | D | D | D | — |
| platform_support | V | D | R | D | `revoke_wallet_pass` |
| platform_risk | V | D | D | D | — |
| platform_admin | A | R | R | D | `revoke_wallet_pass` |
| service_role | A (machine) | R (def) | R (def) | D | definer |

**No venue or org role reads this table at all.** A pass registry is not venue-operations data; the door's
bulk read is M2 and nothing else (door spec §10A.2's column discipline). Columns `auth_token_enc`,
`auth_token_hash`, `serial_no_opaque` are granted to **no** role except `service_role`, and no RPC returns
them to a client.

**`kernel.wallet_pass_device`** and **`kernel.wallet_pass_push_log`** — class **audit-only** (RLS §4): RLS on,
**zero policies**, `REVOKE ALL FROM anon, authenticated`. Read only through an `is_platform` RPC.

**`kernel.pass_type_cert`** — class **audit-only** for clients; `is_platform` read; `kms_handle_ref` granted to
`service_role` only. Note the deliberate contrast with `kernel.signing_key`, whose `public_key` **is** a
world-readable projection because doors need it: **doors never need the Apple certificate** (§2.2), so it gets
no public projection.

**Deny-by-default conformance.** Every new object is `REVOKE ALL FROM anon, authenticated, public` first, then
GRANT only the exact columns/EXECUTE above (I-7). Absence of a policy is denial (I-1). No new object uses
`USING (true)` (I-2). No new object exposes an identity or money column to a broad role (I-4) — `holder_
identity_id` is readable by nobody except platform and the holder themselves. Every predicate is a live-table
read via `has_org_role`/`has_venue_role`/`is_platform`, never a JWT claim (I-5, C36).

### 11.8 Edge Function contracts

| Fn | Method | `verify_jwt` | Authz | Wraps | External | Idempotency | Pkg |
|---|---|---|---|---|---|---|:-:|
| **`wallet-pass-issue`** | POST | **true** | atom current owner (**in the wrapped RPC**, C35) | `kernel.mint_wallet_pass` | KMS sign (Apple cert), object storage | RPC `command_key`; a re-issue for the same owner+atom returns the same serial | **084** |
| **`wallet-pass-webservice`** | GET/POST/DELETE | **false** — Apple devices present `Authorization: ApplePass <token>` | per-pass `authenticationToken`, **constant-time** | `get_wallet_pass_build_context` · `register/unregister_wallet_pass_device` · `list_updated_wallet_passes` | KMS sign (rebuild) | natural (reads/upserts) | **084** |
| **`wallet-pass-push`** | POST | true | `is_platform` or scheduler `service_role` | `record_wallet_push_result` | **APNs** | outbox dedup `(wallet_pass_id, trigger_kind, cause_ref, registration_id)` | **084** |
| **`pass-cert-provision`** | POST | true | `is_platform([platform_admin])` | `provision/rotate/revoke_pass_type_cert` | KMS import/keygen | RPC `command_key` | **083** |

All four inherit edge §7 cross-cutting requirements verbatim: CORS + security headers, secrets by **name only**
(`APPLE_PASS_KMS_HANDLE`, `APNS_KEY_KMS_HANDLE`, `APPLE_TEAM_ID`, `APPLE_PASS_TYPE_ID`, `KMS_ENDPOINT`,
`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SENTRY_DSN` — **no key material in env**), fail-closed rate
limiting, RPC-first-then-side-effect ordering, structured logging that **never logs the token, the pass bytes,
the `authenticationToken`, a push token, or key material**, Sentry on KMS/APNs failures and on
owner-mismatch spikes, and deny-by-default failure mapping (400/403/409/429/503).

### 11.9 The defect W-3 fix — `SPEC CORRECTION` to `PHASE_2_EDGE_FUNCTION_SPEC.md` §5.4

> **`SPEC CORRECTION` — H-2.** The two-conjunct wording that stood here **is the text edge §5.4.3 adopted**,
> after door §9.2 had already corrected the predicate to five. This section is therefore the origin of the
> regression and is corrected first. **The predicate is now stated once — in edge §5.4.3 — and this section is
> a sanctioned verbatim mirror, not an independent statement.** Do not edit the block below; edit edge §5.4.3
> and re-mirror.

Replace §5.4's offline-verify enumeration with:

<!-- SANCTIONED MIRROR of OFFLINE-VERIFY-v1. Byte-identical to PHASE_2_EDGE_FUNCTION_SPEC.md §5.4.3. CI-gated. -->

```text
OFFLINE-VERIFY-v1 — offline door admission predicate (NORMATIVE)
Single source: PHASE_2_EDGE_FUNCTION_SPEC.md §5.4.3. Mirrors must be byte-identical.

Applied set:  M2 := base_snapshot(manifest_id) ⊕ deltas[1 .. last_synced_seq]   (door §7.7)
              The device MUST evaluate against the APPLIED set. Evaluating the base
              snapshot alone silently ignores every revocation and every supplement
              the device has already downloaded.

ADMIT(token) requires ALL of:

  1    token.key_id ∈ M1  ∧  M1[token.key_id].status ≠ 'revoked'
                         ∧  now() ∈ [M1[token.key_id].not_before, not_after]
  2    Verify(M1[token.key_id].public_key, token.claims, token.sig)
  3    token.session_id == the device's bound scanning session
  3a   now() <= token.exp, ± 2 time-buckets                                     (RPC §9.3)
  3b   FIVE conjuncts, ALL required — this is the W-3 fix:
         i    atom ∈ M2
         ii   M2[atom] carries no applied `revoke` delta
         iii  token.credential_version == M2[atom].credential_version
         iv   M2[atom].ticket_state  == 'active'
         v    M2[atom].resale_state  == 'none'
  3c   token.key_id == M2[atom].signing_key_id                                  (Wallet §8.3)
  4    first-in-wins against the device's local admitted set

  No M2, an M2 past its downloaded not_after, or an M2 for another session
  ⇒ the door has NO offline authority and MUST NOT admit.                       (door §3.1)

Conjunct 3b.v is load-bearing, not defence in depth: a `paid_pending_transfer` atom is
`state='active', resale_state='locked'` and is excluded from the door-open drain, and a
`refund_hold` atom is `state='active'` too. Without 3b.v the offline door admits both —
atoms the ONLINE door refuses. Online and offline must reject for the same reasons, or the
offline door is not a shrunk version of the online one; it is a different one.

Reject reasons: door §9.2's map. No private key, no network, no DB.
```

And add to §5.4's manifest paragraph: *"§5.4's manifest is **M1**, the public-key manifest. It is a distinct
artifact from **M2**, the per-session door/ticket manifest (door-lifecycle §9.1). Both are required for offline
verification and neither substitutes for the other."*

And to §5.5, add the two-profile `aud` contract from §5.2 above, and replace *"TTL: short enough to bound
screenshot-resale"* with the accurate statement: *"screenshot resale is bounded by first-in-wins (C41) and by
the `credential_version` check (online C37, offline step 3b), not by the TTL; the TTL bounds only the residual
of a verifier that cannot check currency."*

**All three are `SPEC CORRECTION`. None requires a schema change. All three are prerequisites for Wallet.**

**Fourth correction — the single-source rule (H-2).** Edge §5.4.3 now carries the predicate as
`OFFLINE-VERIFY-v1`, the one normative statement; §2.3 and this section are **verbatim mirrors** under a CI
byte-identity gate. This is `SPEC CORRECTION` to the CI gate set and is the fix for the *mechanism* — four
documents each holding an independently editable copy — rather than for the instance. It requires no schema
change and can be added green today.

### 11.10 Change-class index

| Element | Class | Package |
|---|---|:-:|
| `kernel.pass_type_cert` | `ADDITIVE SCHEMA CHANGE` | **083** |
| `kernel.wallet_pass` | `ADDITIVE SCHEMA CHANGE` | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| `kernel.wallet_pass_device` | `ADDITIVE SCHEMA CHANGE` | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| `kernel.wallet_pass_push_log` | `ADDITIVE SCHEMA CHANGE` (recommended) | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| private `.pkpass` storage bucket + policies | `ADDITIVE SCHEMA CHANGE` | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| six `catalog.platform_config` seed keys | `ADDITIVE SCHEMA CHANGE` (rows) | **078** |
| `kernel.mint_wallet_pass` | `NEW RPC` | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| `kernel.supersede_wallet_passes_for_atom` · `touch_wallet_pass` · `revoke_wallet_pass` | `NEW RPC` | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| `kernel.get_wallet_pass_build_context` · `register/unregister_wallet_pass_device` · `list_updated_wallet_passes` · `record_wallet_push_result` | `NEW RPC` | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| `kernel.sweep_wallet_pass_lifecycle` | `NEW RPC` | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| `kernel.provision/rotate/revoke_pass_type_cert` | `NEW RPC` | **083** |
| `wallet-pass-issue` · `wallet-pass-webservice` · `wallet-pass-push` | `NEW EDGE FUNCTION` | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| `pass-cert-provision` | `NEW EDGE FUNCTION` | **083** |
| Offline verify steps 3b/3c (edge §5.4) — **the W-3 fix** | `SPEC CORRECTION` | — |
| M1/M2 naming in edge §5.4 | `SPEC CORRECTION` | — |
| Two token profiles + `aud` claim (edge §5.5, §3.2) | `SPEC CORRECTION` | — |
| Screenshot/TTL claim in edge §5.5 | `SPEC CORRECTION` | — |
| CI private-key/certificate scan gate | `SPEC CORRECTION` | — |
| Offline predicate stated once as `OFFLINE-VERIFY-v1` (edge §5.4.3); §2.3 and §11.9 become verbatim mirrors + CI byte-identity gate | `SPEC CORRECTION` (**H-2**) | — |
| Step 3c promoted to **required**, with an online counterpart (`validate_ticket_online` returns `signing_key_id`) and a `signing_key_id` re-pin guard (§8.3) | `SPEC CORRECTION` | — |
| `get_wallet_pass_build_context` liveness preconditions — `status='issued'` ∧ holder = live current owner; rebuild at `credential_version_at_build` (§11.6a) | `SPEC CORRECTION` (**H-4**) | — |
| `list_updated_wallet_passes` gains `p_auth_token`; registration-scoped, liveness-filtered (§11.6b) | `SPEC CORRECTION` (signature) | **083** *(was `084` — red-team `P1-6`, corrected 2026-08-29: `084` is the ratified zero-relations/zero-routines ADOPT step and nothing may be added to it; the wallet family is built by `083`)* |
| Kill switch gates serve/rebuild/register/push, not minting alone (§11.5a) | `SPEC CORRECTION` | — |
| `wallet.*` / `credential.*` added to the dual-control-mandatory namespaces (§11.5b) | `SPEC CORRECTION` — **RLS-spec owner** | — |
| Wallet `exp` clamped on the **computed** value (§5.2a) | `SPEC CORRECTION` | — |
| `kernel.revoke_signing_key` force-closes open door episodes (OQ-5 grant condition 2) | `SPEC CORRECTION` — **RPC-spec owner** | — |
| `verify_jwt=false` count: five surfaces, enumerated only in edge §7 | `SPEC CORRECTION` | — |
| pgTAP W-F 30a/30b, W-I 42/43 | `ADDITIVE` (assertions) | — |
| RLS matrices for the four new tables | `ADDITIVE` (new matrices) | — |
| RLS §11 EXECUTE rows for the new RPCs | `ADDITIVE` | — |
| "Add to Apple Wallet" control · re-add · transfer-in add · failure copy | `NEW RN SURFACE` | — |
| Pass-registry / cert-expiry ops view | `NEW DASHBOARD SURFACE` (§13) | — |
| Scanner decision logic | **`NO CHANGE`** (§10.1) | — |
| `kernel.tickets` · `kernel.ticket_ownership_log` · `venue.scan` · `market.*` · `public.*` | **`NO SCHEMA CHANGE`** | — |
| SSCAS membership | **`NO CHANGE`** — nothing here moves custody or money | — |

---
## 12. pgTAP assertion list (described — no SQL authored)

Grouped by the property each defends. All DB-level; none require the app.

**W-A. Structure and grants (8)**
1. `kernel.wallet_pass`, `kernel.wallet_pass_device`, `kernel.pass_type_cert`, `kernel.wallet_pass_push_log`
   exist with RLS **enabled**.
2. `anon` and `authenticated` hold **no** INSERT/UPDATE/DELETE on any of the four (GP-1).
3. `authenticated` holds **no** SELECT on `kernel.wallet_pass.auth_token_enc`, `.auth_token_hash`, or
   `.serial_no_opaque` (column-level ACL assertion).
4. `kernel.wallet_pass_device` and `kernel.pass_type_cert` have RLS on with **zero** policies (audit-only class).
5. No `venue_*` or `org_*` role holds SELECT on any of the four tables.
6. `kernel.pass_type_cert` exposes no column whose name matches `%private%`/`%secret%`, and
   `kms_handle_ref` has SELECT granted only to `service_role`.
7. Every new function is owned by `postgres`, is `SECURITY DEFINER`, and has a pinned `search_path`
   (Standards §8).
8. `kernel.get_wallet_pass_build_context`, `register/unregister_wallet_pass_device`,
   `list_updated_wallet_passes`, `record_wallet_push_result`, `supersede_wallet_passes_for_atom` have **no**
   EXECUTE grant to `anon` or `authenticated`.

**W-B. One live pass per atom — the non-negotiable's structural half (5)**
9. Minting a pass for an atom that already has an `issued` pass returns `noop_replay` with the **same**
   `serial_no_opaque`, and creates no second row.
10. A direct `INSERT` of a second `status='issued'` row for the same `ticket_atom_id` **raises**
    (the partial unique is the backstop even if the RPC guard is bypassed).
11. `transfer_ticket_ownership` followed by `supersede_wallet_passes_for_atom` leaves **zero** rows with
    `status='issued'` for that atom until the new owner mints.
12. After the new owner mints, exactly **one** `issued` row exists, `generation` = old + 1, and
    `serial_no_opaque` **differs** from the superseded row's.
13. `holder_identity_id` on the superseded row still equals the **old** owner (it is a snapshot, not a head).

**W-C. Immutability and append-only guards (6)**
14. `UPDATE kernel.wallet_pass SET serial_no_opaque = …` raises.
15. `UPDATE kernel.wallet_pass SET credential_version_at_build = …` raises.
16. `UPDATE kernel.wallet_pass SET status='issued'` on a `superseded` row raises (no reverse transition).
17. `UPDATE kernel.wallet_pass SET status='consumed'` on an `invalidated` row raises (no terminal→terminal).
18. `DELETE FROM` any of the four tables raises (GP-2).
19. `UPDATE kernel.pass_type_cert SET certificate_pem = …` / `SET kms_handle_ref = …` raises.

**W-D. Certificate lifecycle (4)**
20. Two `status='active'` rows for the same `pass_type_identifier` raise (partial unique).
21. `rotate_pass_type_cert` flips old→`rotating` and new→`active` in **one** transaction; a mid-rotation
    snapshot never shows zero or two active certificates.
22. `provision_pass_type_cert` by `org_owner`, `venue_manager`, `platform_support`, `platform_risk` →
    `insufficient_privilege(42501)`; by `platform_admin` → ok.
23. `not_after <= not_before` → `check_violation`.

**W-E. Mint authority and preconditions (6)**
24. A non-owner calling `mint_wallet_pass` → `42501`, and **no row is written**.
25. The owner of an atom in `state='issued'` → `precondition_failed('atom_not_active')`.
26. The owner of an atom with `resale_state='listed'` → `precondition_failed('atom_listed_locked')`
    (pins §15 OQ-W5's answer once the owner decides).
27. With `config('wallet.apple.enabled') = false` → `precondition_failed('wallet_disabled')` for every caller
    including `platform_admin` (the kill switch is not role-bypassable).
28. `mint_wallet_pass` appends **no** `kernel.ticket_ownership_log` row and **does not** change
    `kernel.tickets.credential_version` — a structural test asserting the pass registry is outside custody.
29. `mint_wallet_pass` is not a member of any SSCAS lock sequence — asserted via `pg_get_functiondef` not
    referencing `market.*` or `kernel.ticket_ownership_log`.

**W-F. Web-service authentication (6)**
30. `get_wallet_pass_build_context` with a **wrong** token returns the same shape and error as with an
    **unknown serial** (no enumeration oracle).
30a. **(H-4)** `get_wallet_pass_build_context` with a **correct** token, on a pass whose `holder_identity_id`
    differs from the live `kernel.tickets.current_owner_id`, returns the **same shape and status** as an
    unknown serial — asserted **without** running the supersession consumer, so the test proves precondition 3
    and not the outbox.
30b. **(H-4)** The same with `status='superseded'` and a correct token.
31. `pg_get_functiondef(get_wallet_pass_build_context)` contains a constant-time comparison and does **not**
    contain a bare `=` comparison against `auth_token_hash` (structural test for I-9).
32. `register_wallet_pass_device` with a wrong token writes **no** row.
33. Registering the same `(wallet_pass_id, device_library_identifier)` twice yields one row with an updated
    push token, not two.

**W-G. The stale-pass guarantee, at DB level (5)**
34. After `transfer_ticket_ownership`, `kernel.tickets.credential_version` **differs** from the superseded
    pass's `credential_version_at_build` — the arithmetic that §4 rests on, asserted directly.
35. With an open door manifest, `venue.door_manifest_entry.credential_version` for every atom of the session
    equals the live `kernel.tickets.credential_version` (the Door Safety Theorem, re-asserted here because
    Wallet depends on it — duplicates door-spec pgTAP 32 deliberately, so a Wallet regression is caught by a
    Wallet test).
36. With an open manifest, `transfer_ticket_ownership` → `frozen`, and the superseded/live pass rows are
    unchanged.
37. `void_ticket_atom` bumps `credential_version` and the atom is **absent** from any subsequently-opened
    `venue.door_manifest_entry` set (`ticket_state ∈ {issued, active}` check).
38. A `scanned` atom's pass reaches `consumed` via `sweep_wallet_pass_lifecycle`, **and** the guarantee
    assertions 34–37 hold identically when the sweep has **not** run (the sweep is not load-bearing).

**W-H. Audit (3)**
39. `mint_wallet_pass`, `revoke_wallet_pass`, `provision/rotate/revoke_pass_type_cert` each write exactly one
    `kernel.admin_audit` row **in the same transaction**, with a non-null `reason_code` and a server-derived
    actor equal to the test's `auth.uid()`.
40. A rolled-back mint writes **no** audit row and **no** `wallet_pass` row.
41. `kernel.admin_audit` remains unreadable by `authenticated`.

**Subtotal: 41 assertions** (plus two added below, W-I). Groups **W-B** and **W-G** are the regression suites for the non-negotiable;
**W-A**/**W-C** defend the secret-custody rule; **W-F** defends the `verify_jwt=false` surface.

**Client-side structural gate (not pgTAP — named here because §4 depends on it).** The scanner build must carry
a unit/integration test **per conjunct of `OFFLINE-VERIFY-v1`** — the case table in edge §5.4.3 is the required
minimum: 3b.i–v (including both `resale_state` cases, `locked` and `refund_hold`), 3c, applied-set evaluation,
and refuse-when-M2-absent. This is the W-3 **and H-2** regression test at the only layer where either can be
tested, and it is item 11 of §13. A test that covers only `credential_version` passes while the door is two
conjuncts more permissive than the online one — that is precisely how H-2 survived review.

**W-I. Two additions to the pgTAP set (`SPEC CORRECTION`), both structural (2):**

42. **No function other than the issuance and transfer RPCs writes `kernel.tickets.signing_key_id`** — asserted
    over `pg_get_functiondef`. This is the guard for §8.3's named assumption, now that 3c is mandatory.
43. `venue.door_manifest_delta` rejects an `op='add'` row with a NULL `signing_key_id` (door §10.3a CHECK) —
    an atom supplemented into M2 with no pinned key is unadmittable offline under 3c.

**Total: 43 assertions.**

---

## 13. Operational requirements checklist

Nothing below is optional, and **every item must be green before `wallet.apple.enabled` is flipped to `true`.**

| # | Requirement | Owner | Cadence | Failure if missed |
|:-:|---|---|---|---|
| 1 | **Apple Developer Program membership**, active and paid, under a company account (not an individual) | owner / finance | annual renewal | everything Apple-side stops, including app releases |
| 2 | A registered **Pass Type Identifier** (`pass.com.snatchit.…`) in the developer portal | platform_admin | once | no passes can be built |
| 3 | **Pass Type ID certificate** issued, private key imported to KMS/HSM, `kernel.pass_type_cert` row provisioned | platform_admin (dual-controlled) | on issue + rotation | no passes can be built |
| 4 | **Certificate expiry monitoring** — alert at `config('wallet.apple.cert_expiry_warn_interval')` (default 45 days) before `not_after`, escalating weekly, paging at 7 days | platform ops | continuous | **silent, calendar-driven outage of the whole feature** (§8.1) |
| 5 | **Calendar entry + named backup owner** for certificate renewal, independent of the alert | owner | annual | a single person's absence takes the feature down |
| 6 | **APNs credentials** (auth key or certificate — resolve the §6.2 `UNVERIFIED` first) in KMS/secret store, with their own expiry monitoring | platform_admin | per Apple's validity | pass updates stop silently |
| 7 | **Apple WWDR intermediate certificate** current in `kernel.pass_type_cert.wwdr_cert_pem` | platform_admin | on Apple rotation | passes fail to install on iOS |
| 8 | **Private object-storage bucket** for built `.pkpass` bytes; no public read; signed URLs only, short TTL | platform_admin | once | pass files enumerable |
| 9 | **CI gate**: no `*.p12`/`*.p8`/`*.cer`/`*.pkpass`/`*.mobileprovision`/`PRIVATE KEY` in tracked files (§8.2) — **can be added green today (§0.1)** | eng | every build | key material in git |
| 10 | **Door-lifecycle prerequisites shipped**: M2 tables (`venue.door_manifest`, `venue.door_manifest_entry`, `door_manifest_delta`) + offline-verify **all five conjuncts of step 3b** + **3c** | eng | **before enabling** | §4's proof is false; W-3 deployed at scale; H-2's more-permissive-offline-door deployed at scale |
| 10a | **The OQ-5 grant's second condition is actually implemented**: `kernel.revoke_signing_key` force-closes and invalidates open door-manifest episodes in its own transaction (edge §5.6). The ruling says *"without this I would reject DL-4"* — until it exists, the session-bounded wallet profile this feature depends on rests on a condition nothing satisfies | eng | **before enabling** | a 12-hour token against a revoked key |
| 10b | **The `exp` clamp is applied at sign time** and asserted in CI over the **computed** value with adversarial `ends_at` fixtures (§5.2a), not merely over the seeded constants | eng | before enabling | a mistyped `ends_at` mints an unbounded bearer credential |
| 11 | **Scanner build implements every conjunct of `OFFLINE-VERIFY-v1`** (§10.2 items 1–2) — all five of 3b, 3c, applied-set evaluation, no-M2-no-admit — covered by **one failing-case regression test per conjunct** (edge §5.4.3's case table), and verified by an end-to-end stale-pass drill **and** a `paid_pending_transfer` drill at a real door | eng + venue ops | before enabling + per scanner release | the reference value is fetched and ignored, or fetched and only partly compared (H-2) |
| **11a** | **The manifest the scanner receives carries every field the predicate reads** (§10.2 item 2a, door §7.5a) — verified by the **structural** assertions, not by a sample scan: door §15 **77–83** and RPC **`T-RPC-DOOR-33`/`-34`**, with the compared read set derived from the fenced block rather than hard-coded. Plus the drill item 11 already requires, run against an atom that reaches M2 **only via an `op='add'` delta** (the post-open door sale) | eng | **before enabling** + per scanner release | item 11 passes and the door still admits a `paid_pending_transfer` atom, because a conjunct's input never arrived (`MP-1`). **Item 11 tests the scanner; this tests the wire, and item 11 cannot detect its absence** |
| 12 | **`wallet-pass-webservice` security review sign-off** for its `verify_jwt=false` posture (§6.1) | platform_admin | before enabling | the second unauthenticated endpoint ships unreviewed |
| 13 | **Rate limits configured and fail-closed** on all four edge functions | eng | before enabling | abuse surface |
| 14 | **Runbook published**: certificate rotation, certificate compromise, signer compromise, APNs key rotation, per-pass revoke, post-break-glass M2 re-sync (§10.3) | platform ops | before enabling | incident improvisation |
| 15 | **Venue door runbook**: no-visual-admission (§10.4), soundcheck M2 sync, cancelled-show handling | venue ops | before enabling + per venue onboarding | §4.4's residual becomes exploitable |
| 16 | **`NEW DASHBOARD SURFACE`** (internal admin plane, RN §8): live pass count, certificate expiry countdown, push failure rate, registration count, superseded-not-re-added count | eng | before enabling | no observability on a device fleet you do not control |
| 17 | **App Review readiness**: "Add to Apple Wallet" badge assets and usage per Apple's current guidelines (§9.2 `UNVERIFIED`) | eng + design | per release | App Review rejection |
| 18 | **Budget** approved for KMS operations, APNs, and object storage at expected pass volume | owner | once + review | — |

---

## 14. Changes required in the door-lifecycle spec

**These were requests** at the time this section was written, and DL-1…DL-6 were dispositioned by the door
spec's §19. **Since then the security remediation has edited the door spec directly** (H-2's mirror and
single-source pointer in door §9.2, the `refund_hold` reject arm, the `door.session_*` config seeds, the
`door_manifest_delta` CHECK, the OQ-5 grant-condition correction, and the demotion of §10.6's constants
invariant). Those are recorded in door §17's change-class index, not here. **The table below is preserved as
the original request record.**

| ID | Change | Why | Severity |
|:-:|---|---|:-:|
| **DL-1** | **Post-open issuance is invisible to offline scanners.** §6 step 7 snapshots M2 once, at open. Atoms issued afterwards (box-office/door sales, late comps) are absent from M2, so an offline door rejects them — a paying fan refused with no remedy, the same shape as §13.5's lockout. Not covered in §14's failure table. **Proposed fix:** an append-only **manifest supplement** — `venue.append_door_manifest_entries(p_session_id, p_atom_ids)`, definer, called from `kernel.issue_ticket_atoms` when an open episode exists; it appends entries to the current episode, bumps `manifest_version`, and pushes devices to re-sync. **This is safe under the theorem**: issuing a *new* atom is not a custody move of an existing one, its `credential_version` starts at 0, and it can strand nobody. Alternative if the supplement is rejected: door sales after manifest open are **online-only**, stated as an operational limit rather than left as an unnoticed rejection. | fans locked out; not a safety issue | **HIGH** |
| **DL-2** | **`catalog.cancel_event` must close any open door-manifest episode.** §7.6 exempts `cancel_event` from the freeze but never closes the episode, so an offline scanner keeps admitting into a cancelled event until it reconnects (§7.3 above). Closing the episode disarms every device on its next contact. Does not help a device that never reconnects — that residual should be stated in §14's failure table alongside failure #11. | offline admission into a cancelled show | **HIGH** |
| **DL-3** | **Mandatory M2 re-sync after break-glass.** §8's `door_freeze_override` and §7.6's platform force-void can move custody between episodes, leaving a device's older M2 genuinely stale (§4.3's residual — it would admit the pre-override owner and reject the post-override owner). Add to §8.2/§7.6: after any such act, every scanner for that session must re-sync M2 before resuming offline admission, surfaced as a dashboard alert and a scanner banner. | bounds the only real residual in §4 | **MEDIUM** |
| **DL-4** | **Amend OQ-5.** It records the constraint *"a `.pkpass` … must never carry a longer TTL than the token."* §5.3 above shows the short TTL was compensating for defect W-3, and that once step 3b exists the guarantee rests on `credential_version` + M2, not on `exp`. As written, OQ-5 makes Wallet impossible (a short-TTL barcode expires on an offline phone). **Requested amendment:** replace the TTL constraint with *"a `.pkpass` may carry a session-bounded token provided offline-verify step 3b is implemented; the guarantee rests on the version check, not on `exp`."* **Owner decision — §15 OQ-W4.** | unblocks the feature; must not be done silently | **BLOCKING** |
| **DL-5** | **Reject-reason vocabulary.** §9.2 rules that an atom absent from M2 is rejected `wrong_session`. For a **voided** atom (absent because M2 admits only `{issued, active}`) that reason misleads door staff into re-checking the session rather than telling the holder their ticket was refunded. Suggest a distinct `not_admissible`. | operator clarity | **LOW** |
| **DL-6** | **§9.4's "not built in Phase 2" note is now stale.** Once this document is ratified, §9.4's closing paragraph and §16 OQ-5 should point at `PHASE_2_APPLE_WALLET_SPEC.md`. | traceability | **LOW** |

---

## 15. Open questions — owner decisions

| ID | Question | Recommendation |
|:-:|---|---|
| **OQ-W1** | **Holder name on the pass?** §9.1 rules **no name**, on lock-screen physical-safety grounds for a nightlife product. Venues sometimes ask for name-on-ticket. | **No name.** If a venue needs ID matching, put it behind the scanner's authenticated single-record lookup, never on a lock screen. **Owner/product call.** |
| **OQ-W2** | **Who owns the Apple Developer account, and who can renew the Pass Type ID certificate?** This is an organizational single point of failure with an annual calendar trigger (§13 items 1, 3, 5). | Name a primary and a **backup** with portal access and KMS import authority; put the renewal in a shared calendar independent of the alerting. **Owner call — organizational, not technical.** |
| **OQ-W3** | **Sequencing.** Wallet's entire guarantee rests on offline-verify step 3b and the M2 tables, neither of which exists (defect W-3, §0.2). | **Hard gate: Wallet may not ship before the door-lifecycle spec's M2 tables and step 3b are implemented and drilled.** Shipping first deploys W-3 at scale onto devices we do not control. **Owner acknowledgement required.** |
| **OQ-W4** | **The two token profiles (§5.2) conflict with door-lifecycle OQ-5 as written (DL-4).** **RULED by door §16 OQ-5 — GRANTED, owner sign-off still owed.** | Accept the session-bounded wallet profile with the three §5.3 mitigations **and both of the ruling's own conditions, neither of which was implemented when granted**: (1) the offline-window bound — now a **clamp on the computed `exp`** (§5.2a), because the ratified constants invariant bound only the `ends_at IS NULL` branch; (2) **key revocation force-closes open door episodes** (edge §5.6) — the mechanism existed, the caller did not. **The owner is signing off on a relaxation whose safety rests on these two; §13 items 10a/10b gate the enable on them.** |
| **OQ-W5** | **Offer a Wallet pass while `resale_state ∈ {listed, locked}`?** §9.2 hides the control. Edge §3.2 flags the *same* question for `credential-sign` on a listed atom and leaves it open (its §12.2). | Answer both together. Recommend **hide/refuse while listed or locked** — it reduces screenshot-resale confusion at zero product cost, since the holder can add after delisting. **Product call.** |
| **OQ-W6** | **`wallet-pass-webservice` runs `verify_jwt=false`** — **one of five such surfaces (edge §7), not the second of two** as this row previously said. | Accept with the §6.1 compensating controls **and §11.6a's liveness preconditions (H-4)**, subject to an explicit security sign-off (§13 item 12). **The sign-off should cover the `verify_jwt=false` set as a whole, not this function alone** — `door-session` (edge §3.9a) is the higher-risk member, since it relays admission. **Security call.** |
| **OQ-W7** | **DL-1 — post-open issuance.** Should the manifest supplement be built, or is "door sales after manifest open are online-only" acceptable for MVP? | Build the supplement; it is small, provably safe, and the alternative silently refuses paying fans. **Owner call.** |
| **OQ-W8** | **Budget** for KMS sign operations, APNs, and object storage at expected volume (§13 item 18). | — |
| **OQ-W9** | **Rotating barcodes (SafeTix-class), later?** §1.2 declines them because the version check already defeats screenshots. | Revisit only if a venue contractually requires it. Note it would add device-clock coupling and a new offline failure mode. **Deferred.** |
| **OQ-W10** | **Google Wallet.** Second delivery vehicle over the same token; inherits §4 unchanged but needs its own key custody, format, and review. | Out of scope; revisit after Apple ships and is measured. |

---

## 16. Ratified-invariant conformance

| Invariant | Interaction | Verdict |
|---|---|---|
| **Ticket atom** | untouched — no column added, no state added, no new terminal | ✔ preserved |
| **Append-only ownership log** | `mint_wallet_pass` appends nothing and bumps nothing (pgTAP W-E 28) | ✔ preserved |
| **Single transfer engine** | the pass registry is entirely outside the custody path; supersession runs in the **outbox consumer**, so Wallet can never block or roll back a transfer | ✔ preserved |
| **Credential-as-delivery** | **strengthened** — the pass carries a claim, the platform holds the reference value (§2). Invalidation on transfer is arithmetic (`credential_version`), not a push | ✔ reinforced |
| **Two-rail honesty** | Rail B has no atom, no credential, no pass (§1.2). No `.pkpass` may ever be minted for an external claim | ✔ preserved |
| **Modular monolith** | all new objects are `kernel.*` + `catalog.*` config rows; no cross-schema write; `venue.*` untouched | ✔ preserved |
| **Frozen Stripe core** | no `public.payments` column, no charge path, no fee change | ✔ preserved |
| **SSCAS membership + global lock order** | nothing here moves custody or money; `mint_wallet_pass` takes one rank-5 `FOR SHARE` and writes only `kernel.wallet_pass` | ✔ preserved, **no sixteenth member** |
| **Server-authoritative money/custody** | no client timestamp, no client actor, no client-writable path to any pass column; C35 authorization is inside the RPC | ✔ preserved |
| **C1/C33 key lifecycle** | the Apple certificate is a **second, separate** key system with its own table, custody, rotation and runbook (§8) — never conflated with the C33 signer; both KMS-only, both handle-referenced | ✔ preserved, extended |
| **C6** (offline door = reconcile window + transfer freeze) | Wallet consumes the freeze; it does not weaken it. §4.3's residual is C6's own, named | ✔ preserved |
| **C23** (ordered offline reconciliation; freeze covers refund-voids) | pass invalidation on refund-void rides the existing version bump | ✔ preserved |
| **C37** (live authoritative per-scan read online; offline honestly shrunk) | §4.1 relies on the live read verbatim; §4.3's residual is stated in C37's own words — **shrunk, not closed** | ✔ preserved, claim still honest |
| **C41** (no re-entry; `scanned` terminal; `direction` hedge) | a re-presented pass is `duplicate`, never a re-admit (§7.2); no Wallet surface implies re-entry (§1.2) | ✔ preserved |
| **C43** (p2p hard TTL; cancel-to-self exempt; per-open-manifest narrowing) | the door-open drain's cancel-to-self leaves owner and version unchanged, so the sender's pass stays valid and correct (§7.1) | ✔ preserved |
| **DA §7.2 / VD §5 note 11** (door staff never receive a bulk attendee list) | no venue or org role can read the pass registry; the pass carries no holder name (§9.1); M2 carries no identity column | ✔ reinforced |

**No ratified invariant is violated by this design.** One **recorded open question** (door-lifecycle OQ-5) is
asked to be amended, explicitly and with its reasoning shown (§5.3, DL-4, OQ-W4) — not worked around.

---

*End of `docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md`. Design-only; no PassKit code, no SQL files, no
migrations, no React Native code, no certificates, no keys. Delta on the Phase-2 implementation specs and on
the owner-ratified door-lifecycle spec; establishes the Apple Wallet feature from zero and specifies the fix
for defect W-3.*
