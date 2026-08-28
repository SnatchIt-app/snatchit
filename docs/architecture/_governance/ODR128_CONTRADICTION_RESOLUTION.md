# `ODR-128` — Cross-Document Contradiction Resolution under `OR-6`

**2026-08-28.** Re-enumerated from HEAD under owner ruling `OR-6` (`ODR-7` / `O11`: HYBRID PRECEDENCE).
Resolution and transcription mapping only — **no contract was edited to produce this.**

> ## DERIVED CONTRADICTION COUNT: **9**. IT IS NOT SIX.
>
> `ODR-128` named six. Verified at HEAD: **all six are live**, one of them is **two distinct
> contradictions folded under a single label**, and **two more of the same class are missing from the
> register entirely**. `6 → 9`.
>
> | | resolved by `OR-6` | how |
> |---|:--:|---|
> | by the owner map alone (rule 1) | **6** | `X-2 X-3 X-4 X-5 X-7 X-9` |
> | by the ratified-correction fallback (rule 2) | **0** | the map turned out to cover every subject that resolved |
> | **FAIL CLOSED (rule 4)** | **3** | `X-1 X-6` (subject `WRITER` is AMBIGUOUS) · `X-8` |
>
> ```
> TOTAL: 9   RESOLVED BY ODR-7: 6   STILL UNRESOLVED: 3
> ```
>
> **THREE FAIL CLOSED, NOT ONE — and the reason is a finding, not a shortfall.** Two independent
> reviewers were run over this: one built the subject-matter owner map, one resolved the
> contradictions. **They disagreed about `X-1` and `X-6`.** The contradiction pass resolved both in
> RPC's favour; the map pass found that **write authority has three declared owners, none deferring**
> — RLS claims it in the first person, RLS's own binding-inputs section assigns it to the schema
> spec, and RLS §11.0 assigns its EXEC rows to `ROLE_MODEL` §5.3 — with **both sides carrying
> ratified tags** (`GP-3a` vs `C89`). That is rule 4's case verbatim. **The disagreement between the
> two passes IS the ambiguity**, and resolving it by preferring the more confident reviewer would be
> exactly the silent pick the ruling forbids.

## The nine, and what each one is

| id | subject | in `ODR-128`? | resolution |
|---|---|:--:|---|
| **X-1** | writer of `kernel.payment_native` | yes | **UNRESOLVED — FAIL CLOSED** (`WRITER` is AMBIGUOUS) |
| **X-2** | `cause_ref` grain on `kernel.payout` (`settlement`) | yes | OWNER → schema |
| **X-3** | `cause_ref` grain on the ownership log (`issue`) | **folded under X-2's label; the Blocks line never reached it** | OWNER → schema |
| **X-4** | `append_door_manifest_delta` return type | yes | OWNER → `SEAM-RULE` (the plan) |
| **X-5** | `assert_may_request` arity — **three live forms** | yes | OWNER → RPC |
| **X-6** | `kernel.tickets` writer set (4 vs 10) | yes | **UNRESOLVED — FAIL CLOSED** (`WRITER` is AMBIGUOUS) |
| **X-7** | `078` seed semantics | yes | OWNER → schema §13 |
| **X-8** | `record_money_denial` grant class / actor | **MISSED** | **UNRESOLVED — FAIL CLOSED** |
| **X-9** | `kernel.payout.status='held'` | **MISSED** — carried only as defect `DF-15` | OWNER → schema |

**Deliberately NOT folded in:** the door-session selector (`door_session_id` vs `session_ref`) is a
cross-document contradiction of the identical class, but it already has its own register entry
(`ODR-21`) with a side named. Folding it here would double-count a registered decision.

## The ownership declarations this resolution relies on

`OR-6` rule 1 requires a *designated* owner. These are the only ownership declarations in the corpus;
every resolution below cites one. The full map is `PHASE_2_SUBJECT_MATTER_OWNER_MAP.md`.

- **OM-1** — ratified `C75`, verbatim: *"a named owner per subject (authority branches → RPC;
  predicates/grants → RLS; physical columns → schema; the money-authority **model** → the money spec)"*
- **OM-2** — schema spec: *"the document that is authoritative for columns, PKs, FKs, CHECKs and indexes"*
- **OM-3** — schema spec §13: *"**This section is the binding placement record.**"*
- **OM-4** — spec foundation: predicate *defining contracts* → RPC §1.1–§1.1e; *membership* → RLS §2.2
- **OM-5** — RPC `R-24`: *"§0.7a … is the callee half; the RLS spec owns the authority half"*
- **OM-6** — the package registry's own `CANONICAL` self-designation + SEAM-1/2/2a/4
- **OM-7** — edge spec: *"This spec owns the edge contract; it does not own the tables or the RPC signatures."*
- **OM-8** — schema spec: *"This spec owns the column and the key; the RPC owner owns the predicate"*

## The resolutions — the two that matter most

### X-6 — `kernel.tickets`: four writers or ten?

RLS §7.5 and §5 name **four**. RPC §20.14 (`R-24`) says: *"THE DOCUMENT THAT CALLS ITSELF 'the complete
statement of Phase-2 write authority' NAMES FOUR WRITERS OF `kernel.tickets`; THIS DOCUMENT CONTRACTS
TEN … Six are missing, and one of the four listed is the wrong function."*

**Ownership is contested on the face of it and it resolves.** `OM-5` says RLS owns the *authority half*
— which read alone assigns the subject to RLS. But the disputed fact is not an authority grant; it is
**which functions perform a write**, a per-function Writes-line fact, RPC's under `OM-1`. The decisive
point: **RLS's fourth entry, `venue.record_scan`, is a `venue.*` wrapper — so RLS's list asserts as
design the exact thing RPC §0.7 forbids, and §0.7 is a rule RPC unambiguously owns.** One side is
internally inconsistent with a rule the other side owns.

**The argument for ten is strong — and it is not enough.** `OR-6` rule 1 asks who OWNS the subject,
not which reading is better. `WRITER` has **three declared owners and none defers**, and both sides
carry ratified tags. **Rule 4 therefore applies and this fails closed**, together with `X-1`. The
ten-writer reading is recorded here as the likely outcome once ownership is settled; **it is not
adopted, because adopting it would be the silent pick the ruling exists to prevent.**

> **A confound worth naming, because `OR-6` was written to prevent it.** `R-24` is the newer text. Had
> we resolved by recency we would have reached the **same answer for the wrong reason** — and would
> have learned nothing about whether the rule works. Rule 3 was not consulted.

### X-8 — the one that fails closed

`kernel.record_money_denial`'s `EXECUTE` grant class and acting principal. RLS §3.1/§11 and MONEY §8.4
say **`service_role` only, no human path**. Schema §1.12.1 and RPC §17.9 (`S-17`/`C106`) say
**`EXECUTE` to `authenticated` only, bound by EDGE-CALLER-JWT, and it RAISES when `auth.uid()` IS NULL**.

**`OR-6` cannot settle it, and that is the correct outcome rather than a gap.** The owner map is **not
silent — it is self-splitting.** `OM-1` assigns the `EXECUTE` grant to RLS (*predicates/grants → RLS*)
and the actor derivation to RPC (*authority branches → RPC*), and the two owners state contradictory
halves of **one indivisible call contract**. Rule 1 yields two answers. Rule 2 explicitly bars breaking
the tie with the ratified-correction fallback *"just because it is newer or tagged"* — and **both sides
are tagged**. Rule 3 bars recency. **→ Rule 4: the implementer does not choose.**

> **Silence here is unsafe, not untidy.** Ratified `C93` already proved the RLS/MONEY form is
> **unbuildable**: on a `service_role` connection `auth.uid()` is NULL, `kernel.admin_audit.actor_identity`
> is `NOT NULL FK→auth.users`, and the FK forbids a sentinel — *"the INSERT cannot satisfy its own
> constraint."* **An implementer who follows RLS §11 ships a fraud-signal audit function that fails on
> its first call, on the fraud path, silently, in production.**
>
> And it cannot be transcribed away in either direction: the `S-17` repair **already landed in four of
> six sites**, so choosing the RLS side means **reverting four applied ratified edits**, while choosing
> the schema/RPC side means overriding an explicitly assigned owner, which rule 2 forbids. **Both
> directions create a new contradiction.**
>
> **What the owner must do (stated, not chosen):** either (a) refine the owner map with one clause for
> the case where a single RPC's grant class and actor derivation are inseparable, or (b) record that
> `C106` binds the RLS and MONEY sites as a discharge. Both are owner acts.

### The other seven, in one line each

**X-1 — FAILS CLOSED with `X-6`, same subject.** The evidence is that
`venue.finalize_primary_order` and `kernel.transfer_ticket_ownership` write `kernel.payment_native`
and **`issue_ticket_atoms` does not** — but `WRITER` is AMBIGUOUS, so nothing here is adopted.
*(This is also the one row with **no filed `R-` request** — filing that gap is a prerequisite to any
transcription, whichever way ownership lands.)*

**X-2** — schema owns the column: `cause_ref` for `cause='settlement'` is a **`settlement_line.id`**, so
a settlement has **N** payouts and the header is two hops away. RPC §20.11.5's one-hop lookup loses; its
*reason* for taking the payout rather than the settlement survives untouched.

**X-3** — schema §3.8 owns it: `cause_ref := venue.order_item.id` for `cause='issue'`. RPC §6.3's
`/order_id` alternative is deleted. Lowest severity of the nine — a slash in one line — **and
load-bearing on the partial-refund path, which is already written against the order-item grain.**

**X-4 — and this one moved when the map arrived.** The contradiction pass resolved it by the rule-2
**fallback**, reasoning that the owner map is *"silent on function return types"*. **The gate rejected
that**: `RPC-SIG` explicitly covers return types with `CORRECTION_FALLBACK=NO`, so rule 2 was not
available. The correct resolution is by **owner** and a different subject — the object is a **SEAM-2
hook**, whose parameter list, parameter names and return type are frozen at the stub by ratified
**SEAM-2a**, and `SEAM-RULE` has a designated owner. `RETURNS void` wins on ownership, not on its tag.
**The converse edit is not merely unattractive — it would violate SEAM-2a.**
*This correction was made by the CI gate, on its first run against real inputs.*

**X-5** — `OM-4` splits the subject explicitly: RLS owns *which* predicates exist and who may call them;
**RPC owns what each one's contract is.** Winner: the five-parameter form with `p_raise boolean DEFAULT
true`. Form C is additionally wrong on scope decomposition, not only arity.

**X-7** — schema §13 declares itself *"the binding placement record"* and consolidates **all**
`platform_config` seeds into `078`, recording CRM's dissent explicitly (`▲ CRM said 087`). CRM keeps the
*semantics* of its limits; it does not own *which package writes the row*. **The plan's own `087` row
already reads "seeded in `078`"** — it consumes the winning placement while CRM claims to write it.

**X-9** — schema owns enum membership: `status='held'` **never existed**. Probation is `status='pending'`
+ `hold_state='probation_hold'`. The money spec keeps the control *model*; it loses the physical claim,
and its `NO SCHEMA CHANGE` classification becomes **`SCHEMA CHANGE` — four additive columns.** **Every
other document has already moved to the winning representation.**

## INTRA-DOCUMENT DEFECTS — `OR-6` does NOT reach these

`OR-6`'s scope limit is binding: two sections of the **same** normative document contradicting each
other is a mechanical defect, and this ruling may not be cited to settle one. The corpus already
established the class at ratified `C121` (*"Same document, so `O11` cannot help."*).

- **ID-1** — Apple Wallet §6.3 (drain is a push trigger, with a dedup key giving it first-class
  identity) vs §7.1 (*"requires no special handling"*). → **Wallet spec owner.**
- **ID-2** — package registry §7: `COND-B` floors an entire package on a notify→promoter coupling,
  and **fifteen lines later** calls promoter codes *"Unaffected … carries its own scheduler."*
  Corroboration that one side is wrong: **the notifications spec contains zero occurrences of
  `promoter`.** → **Registry owner.**
- **ID-3** — RPC §10.2 (*"generate the payout"*, singular) vs §20.11.5 (*"every `cause='settlement'`
  payout"*, plural). Surfaced by resolving X-2, **not created by it** — the two disagree at HEAD
  independently. → **RPC owner.**
- **ID-4** — CRM §9.5 (scope split in two) vs §12 `K-15` (scope collapsed to one). Distinct from X-5:
  X-5 settles the arity, this is the CRM spec disagreeing with **itself** on scope decomposition.
  → **CRM owner**, and `K-15` needs a `C`-row because it is a ratified correction row.

*(`ODR-127` — RPC §6.3 vs §7.1 on the inventory write — is the fifth member of this class and is
already correctly filed as its own entry.)*

## TRANSCRIPTION WORK LIST

**28 edit sites across 8 files.** **17 are pure transcription** needing no new correction id.
**7 require a new `C`-row or an explicit discharge** — RLS §11 EXEC row · RLS structural assertion ·
RPC §20.11.5 ×2 · CRM `K-15` · MONEY §8.4 Control 4 · MONEY §12. **4 are intra-document** and belong to
their own document's owner. **4 sites are BLOCKED pending the X-8 escalation and must not be edited**:
RLS §3.1, RLS §11 (`record_money_denial` row), MONEY §8.4 ×2.

| file | sites | `C`-row needed |
|---|:--:|---|
| `PHASE_2_RLS_PERMISSION_SPEC.md` | 10 | 2 (+2 blocked) |
| `PHASE_2_RPC_FUNCTION_CONTRACTS.md` | 4 | 2 |
| `PHASE_2_CRM_EXPORT_SPEC.md` | 4 | 1 |
| `PHASE_2_MONEY_AUTHORITY_SPEC.md` | 4 | 2 (+2 blocked) |
| `PHASE_2_PACKAGE_REGISTRY.md` | 4 | 0 |
| `PHASE_2_SUPABASE_MIGRATION_PLAN.md` | 1 | 0 |
| `PHASE_2_DOOR_LIFECYCLE_SPEC.md` | 1 | 0 |
| `PHASE_2_APPLE_WALLET_SPEC.md` | 1 (intra-doc) | 0 |

**A prerequisite under the corpus's own filing discipline:** every cross-document row is covered by a
filed request (`R-24`, `R-29`, `R-31`, `R-33`) or a ratified placement decision — **except X-1**. That
gap must be filed before the transcription pass runs.

## Machine-parseable record — parsed by `scripts/precedence_gate.py`

`ID|SUBJECT_ID|RESOLUTION|WINNER_DOC|TRANSCRIPTION_SITES`

```contradictions
X-1|WRITER|UNRESOLVED||
X-2|SCHEMA-PHYS|OWNER|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md
X-3|SCHEMA-PHYS|OWNER|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md
X-4|SEAM-RULE|OWNER|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md|docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md
X-5|RPC-SIG|OWNER|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_PACKAGE_REGISTRY.md;docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md
X-6|WRITER|UNRESOLVED||
X-7|PKG-PLACE|OWNER|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md
X-8|GRANTS|UNRESOLVED||
X-9|SCHEMA-PHYS|OWNER|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md
```

**`X-1`, `X-6` and `X-8` are `UNRESOLVED` on purpose. The gate fails red while they stay that way,
and that is `OR-6` rule 4 working exactly as ruled — not a bug to be silenced by editing these
lines.** Silencing them by asserting an owner the corpus has not designated would reintroduce the
precise failure the ruling was made to end.
