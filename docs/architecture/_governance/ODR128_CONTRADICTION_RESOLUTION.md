# `ODR-128` — Cross-Document Contradiction Resolution under `OR-6`

**2026-08-28.** Re-enumerated from HEAD under owner ruling `OR-6` (`ODR-7` / `O11`: HYBRID PRECEDENCE).
Resolution and transcription mapping only — **no contract was edited to produce this.**

> ## DERIVED CONTRADICTION COUNT: **9**. IT IS NOT SIX.
>
> `ODR-128` named six. Verified at HEAD: **all six are live**, one of them is **two distinct
> contradictions folded under a single label**, and **two more of the same class are missing from the
> register entirely**. `6 → 9`.
>
> | | resolved | how |
> |---|:--:|---|
> | by the owner map (rule 1) | **8** | `X-1 X-2 X-3 X-4 X-5 X-6 X-7 X-9` |
> | by the ratified-correction fallback (rule 2) | **0** | the map covers every subject that resolved |
> | **FAIL CLOSED (rule 4)** | **1** | `X-8` |
>
> ```
> TOTAL: 9   RESOLVED: 8   STILL UNRESOLVED: 1
> ```
>
> **`X-1` and `X-6` closed on 2026-08-28**, when the owner ruled that
> `PHASE_2_RPC_FUNCTION_CONTRACTS.md` owns the canonical writer registry (`OR-7`). They had failed
> closed because `WRITER` had three declared owners and none deferred — which is what rule 4 is for,
> and the ruling is what rule 4 was waiting on.
>
> **And the answer was not the one either reviewer had: it is 11 writers, not 10.** The eleventh is a
> **cron/sweep** function the earlier enumeration omitted — precisely the class the ruling says must
> be counted. Full derivation: `WRITER_OWNER_RULING_CONSEQUENCE_MAP.md`.
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
| **X-1** | writer of `kernel.payment_native` | yes | **RESOLVED** → RPC (`OR-7`) — 2 unambiguous writers |
| **X-2** | `cause_ref` grain on `kernel.payout` (`settlement`) | yes | OWNER → schema |
| **X-3** | `cause_ref` grain on the ownership log (`issue`) | **folded under X-2's label; the Blocks line never reached it** | OWNER → schema |
| **X-4** | `append_door_manifest_delta` return type | yes | OWNER → `SEAM-RULE` (the plan) |
| **X-5** | `assert_may_request` arity — **three live forms** | yes | OWNER → RPC |
| **X-6** | `kernel.tickets` writer set (4 vs 10) | yes | **RESOLVED** → RPC (`OR-7`) — and the answer is **11**, not 10 |
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

**RESOLVED 2026-08-28 by owner ruling `OR-7`: the RPC contracts own writer membership.** And the
derived answer is **eleven**, not the ten either side had argued — the eleventh being
`kernel.sweep_expired_ticket_atoms`, a cron/sweep writer that expires ticket atoms on a two-minute
heartbeat. The earlier "ten" was written by one pass; §12.5, which creates the eleventh writer, was
authored into the **same document** by a later pass and the count was never re-derived.

**This is the case for having refused to pick earlier.** Had `X-6` been closed by preferring the more
confident reviewer, the transcription would have written a ten-writer authority statement into the RLS
spec — **still wrong by one, and wrong about the function that silently expires tickets.** `venue.record_scan`
is confirmed a delegating caller, not a writer, on three independent grounds.

> **A confound worth naming, because `OR-6` was written to prevent it.** `R-24` is the newer text. Had
> we resolved by recency we would have reached the **same answer for the wrong reason** — and would
> have learned nothing about whether the rule works. Rule 3 was not consulted.

### X-8 — the one that still fails closed, **for a corrected reason**

`kernel.record_money_denial`'s `EXECUTE` grant class and acting principal. RLS §3.1/§11 and MONEY §8.4
say **`service_role` only, no human path**. Schema §1.12.1 and RPC §17.9 (`S-17`/`C106`) say
**`EXECUTE` to `authenticated` only, bound by EDGE-CALLER-JWT, RAISING when `auth.uid()` IS NULL**.

> #### CORRECTION — the reason recorded in this document's first edition was WRONG
>
> It said the owner map *"is not silent — it is self-splitting"*, with `OM-1` assigning the `EXECUTE`
> grant to RLS and the actor derivation to RPC. **RLS is not an owner of `GRANTS`.** The map assigns
> `GRANTS` to `PHASE_2_ROLE_MODEL_SPEC.md` §5.3 and lists RLS as a **derived** document — and RLS's own
> `EXEC-DERIVED` rule agrees: *"§5.3 governs and §11 is the defect."* The first edition was quoting
> `OM-1`, which is ratified `C75`'s **pre-map** phrasing — superseded by the very map `C75` demanded.
>
> **So the "two owners disagree" framing collapses, and the real configuration is narrower and worse.**

**The actual reason it fails closed: the owner is SILENT, and the fallback is barred.**

**`PHASE_2_ROLE_MODEL_SPEC.md` contains ZERO occurrences of `record_money_denial`** — verified by
grep over the whole file. RLS's capability→RPC map, which `T-RLS-EXEC-01` joins on, has no entry for
it either. So:

- **Rule 1** yields nothing — the owner does not cover the function.
- **Rule 2** is barred — the map declares `GRANTS` `CORRECTION_FALLBACK = NO`.
- **Rule 3** is barred.
- **→ Rule 4.**

> **THE SILENCE IS NOT NEUTRAL, AND THAT IS EXACTLY WHY IT CANNOT BE READ.** Under `EXEC-DERIVED`, a
> §11 row granting a capability §5.3 marks `·` is an over-grant — and §5.3 marks every principal `·`
> on every capability it does not list, which mechanically forbids the `authenticated` grant. But §5.3
> equally carries **no `SVC`-only row**, so the mirror reading — that definer-only RPCs are simply
> outside §5.3's frame — is just as available. **Two readings of one owner's silence, pointing
> opposite ways, is not an owner statement.**

**A MAP DEFECT, recorded and deliberately NOT fixed here.** `GRANTS` is declared
`CORRECTION_FALLBACK = NO`, which the map defines as *"the owner covers the subject."* **The text
falsifies that declaration** — the owner does not cover this function. Flipping it to `YES` would make
`C93`/`C106` directly applicable and resolve the row **by the back door**. That is an owner act, and
it is not taken here.

#### The decomposition, registered as required

| part | disputed property | subject | owner |
|:--|---|---|---|
| **A** | who may EXECUTE | **`GRANTS`** | `PHASE_2_ROLE_MODEL_SPEC.md` §5.3 — **SILENT on this function** |
| **B1** | whether the call is bound by EDGE-CALLER-JWT | `EDGE` | edge spec — but no subject registers the *rule's scope* |
| **B2** | run-time actor derivation, RAISE on NULL | `AUTHZ-BRANCH` *by subject text only* | RPC — **but §17.9 is not among the map's enumerated normative sections**, and assigning it would be inference, which the map forbids |
| **B3** | signature unchanged, no actor parameter | `RPC-SIG` | RPC — **undisputed; every side agrees** |

**The decomposition does not resolve it**, because the component the dispute turns on (**A**) has a
silent owner and a closed fallback. It is registered anyway because it **changes which owner act closes
the row**.

#### Mutual satisfiability — a finding sharper than ambiguity

The parts are jointly satisfiable in **exactly one** configuration, and **it is not the one currently
transcribed at four sites**:

| A | B | satisfiable? |
|---|---|---|
| `service_role` only | `auth.uid()`, RAISE on NULL | **NO — provably unbuildable.** Ratified `C93`: every call is on a service-role connection, so `auth.uid()` is NULL and it RAISES; drop the RAISE and `actor_identity` violates `NOT NULL FK→auth.users` with no sentinel permitted. *"The INSERT cannot satisfy its own constraint."* |
| `authenticated` only | caller-JWT derivation | **YES** |
| both grantees | — | **barred by construction** — the RPC class table admits two classes and no union |

**This is not two defensible readings. It is one reading that cannot execute even once** — and that
reading is the one written at RLS §3.1, RLS §11, MONEY §8.4 and MONEY §12. **Stating this is not
choosing it:** buildability is not an authority under `OR-6`, and rule 4 bars the implementer from
picking even when one side is unbuildable.

#### A second correction: the repair landed in THREE of six, not four

The first edition said four. Verified at HEAD: **three landed** (RPC §17.9 *body*, edge `EA-2`, edge
`EA-3(B-ii)`), and the RPC §17.9 **heading still reads `EXEC: DEF`** — so even the landed site is only
half-landed. **Three further sites are missing from `C106`'s enumeration entirely** (RPC §0.1a, MONEY
§2.3, MONEY §12). The blocked-edit set therefore grows from four sites to **seven**.

#### A NEW intra-document defect — the owner document fails its own test

**RPC §0.1a and the §17.9 heading say `EXEC: DEF`; the §17.9 body says `EXECUTE` to `authenticated`
only.** The document therefore fails its own global assertion `T-RPC-GLOBAL-02` — *"every `EXEC: DEF`
function has no grant to `anon`/`authenticated`."* `OR-6` cannot reach this (ratified `C121`: same
document, so precedence cannot help). **It belongs to the RPC owner and is added to the intra-document
list as `ID-5`.**

> #### UPDATE 2026-08-28 — the owner ruled capability ownership (`OR-8`), and `X-8` still does not close.
>
> Remedy 1 below was taken: **`PHASE_2_ROLE_MODEL_SPEC.md` now owns capability existence, identifiers,
> semantics and the capability→RPC mapping.** The subject is no longer silent-with-no-owner.
>
> **It closes on one bit the corpus cannot supply.** The naming convention was induced from 69 ids
> with zero exceptions and fixes the identifier's form completely — **except the block letter**, where
> two options are equally rule-consistent (`A7` / `B13`). Per the instruction not to proceed by
> preference, **no row was written.**
>
> **And two blockers survive the naming decision:** the mapping has **no normative home** (the owner
> carries no capability→RPC map at all — subject `CAP-MAP` is owned-but-unhoused), and **`ID-5` bars
> it** — the RLS map explicitly excludes every `DEF` RPC, and this function is still labelled `DEF` in
> two RPC sites while its own body contracts `authenticated`.
>
> Full derivation, including the forced cell values and the proof that no role possesses the
> capability: `_governance/ROLE_MODEL_DENIAL_AUDIT_CAPABILITY_RULING.md`.

> #### UPDATE 2026-08-29 — the owner chose `A7` (`OR-9`). `X-8` is **still UNRESOLVED**, and one blocker of two is gone.
>
> **What closed.** The naming bit and the housing gap.
>
> - **`A7` is written.** `ROLE_MODEL` §5.3 block **A** now carries `A7 Record own money-action denial
>   (kernel.admin_audit)`, 70 rows. Cells forced by the contract, not chosen: `ANO` `·`, `DOO` `·`,
>   **`SVC` `·`** (first denial of `service_role` in the matrix — a **narrowing**, flagged first-of-kind),
>   seventeen authenticated principals **identical** at `R◐`. **NEW HUMAN `EXECUTE` AUTHORITY CREATED:
>   NO** — the `authenticated` grant was already ratified twice (`C93`, `C106`).
> - **`CAP-MAP` is housed.** New `ROLE_MODEL` **§5.4**, thirteen rows transcribed **unchanged** from RLS
>   §16.11a, plus an enumerated gap list (§5.4.1). RLS §16.11a becomes the roll-up — filed as
>   `ROLE_MODEL` §11.2 **`R-19`**, **not applied** (the RLS spec was not edited). The housing *form* was
>   mechanical: a §5.3 column cannot carry a grouped many-to-many map without inventing decompositions.
>
> **What did not close: `ID-5`, and it is now the only thing between `X-8` and RESOLVED.**
>
> The `A7 → kernel.record_money_denial` entry sits in §5.4 as **`⛔ BLOCKED`**, not as a mapping. The
> map's exclusion rule — *every `DEF` RPC is deliberately absent* — is carried into §5.4 **verbatim and
> unweakened**, and it fires on the two stale `EXEC: DEF` labels at RPC §0.1a and the §17.9 heading.
>
> **Classification of the collision: `C` — a later ratified correction supersedes the relevant portion**,
> where *the relevant portion* is **the `EXEC: DEF` classification of this one function, not the exclusion
> rule**, which stands. `C93` proved the `DEF` configuration **unbuildable** and `C106`/`S-17` re-contracted
> the function as `EXECUTE` to `authenticated` only; the two surviving labels are **unpropagated residue**
> of a correction the document itself announces in the same subsection. Not `A` — the rule's own rationale
> (*"would reintroduce the human grant the `DEF` class exists to deny"*) is false here: the grant already
> exists and the row's `SVC` `·` is a narrowing. Not `B` in the strict sense — the labels do make the rule
> fire lexically, so it is not merely over-cited. Not `D` — `OR-8` already performed that decomposition.
> Not `E`.
>
> **And therefore `ID-5` is a MECHANICAL REMEDIATION, not an owner decision.** §0.1a defines exactly two
> grant classes and the other one — *caller-authorized (default)* — **carries no tag**, so the repair is
> `delete "EXEC: DEF" at two sites` and adds no vocabulary and makes no choice. Filed as `ROLE_MODEL`
> §11.4 **`P-6`**. **`OR-6`'s scope limit is binding: this is intra-document, so no precedence rule
> reaches it and `OR-6` may not be cited to settle it** — it belongs to the RPC owner.
> `PHASE_2_RPC_FUNCTION_CONTRACTS.md` was **not** edited by this pass.
>
> **`X-8` therefore stays `UNRESOLVED` in the fenced block below and the gate stays RED. That is the gate
> working, not failing.** Remaining owner bits for `X-8`: **zero**. Minimum brief:
> `_governance/X8_CAP_MAP_ID5_OWNER_BRIEF.md`.

#### What closes the row — stated, not chosen

The first edition's proposed remedy was *"refine the owner map for the case where a single RPC's grant
class and actor derivation are inseparable."* **That aims at a split which does not exist at HEAD.**
Any **one** of these suffices:

1. **Fill the `GRANTS` owner's silence** — one capability row in `ROLE_MODEL` §5.3 for denial audit,
   plus the matching capability→RPC entry. **Smallest act, and the only one that also unblocks
   `T-RLS-EXEC-01`**, whose join currently has no entry for this function *in either direction*.
2. **Or correct the map** — flip `GRANTS` to `CORRECTION_FALLBACK = YES`, or state that this function
   is outside `GRANTS`' frame and name its owner.
3. **Or record that `C106` discharges the RLS and MONEY sites** — still available, but it must now be
   written as a **discharge of derived text**, not as an override of an owner.
4. **Independently required either way:** the RPC owner must repair `ID-5`.

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

A **decomposed** contradiction — one call contract whose parts have different owners — carries a
comma-separated subject list. `X-8` is the first, and the field was widened to express it: collapsing
it to a single subject would be the subject substitution the gate caught on `X-4`.

```contradictions
X-1|WRITER|OWNER|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md
X-2|SCHEMA-PHYS|OWNER|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md
X-3|SCHEMA-PHYS|OWNER|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md
X-4|SEAM-RULE|OWNER|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md|docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md
X-5|RPC-SIG|OWNER|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_PACKAGE_REGISTRY.md;docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md
X-6|WRITER|OWNER|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md
X-7|PKG-PLACE|OWNER|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md
X-8|CAPABILITY,CAP-MAP,GRANTS|UNRESOLVED||
X-9|SCHEMA-PHYS|OWNER|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md
```

**`X-1`, `X-6` and `X-8` are `UNRESOLVED` on purpose. The gate fails red while they stay that way,
and that is `OR-6` rule 4 working exactly as ruled — not a bug to be silenced by editing these
lines.** Silencing them by asserting an owner the corpus has not designated would reintroduce the
precise failure the ruling was made to end.
