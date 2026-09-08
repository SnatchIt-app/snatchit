# `O17` / `MD-2` / `ODR-23` — Owner Ruling B: complete impact map

**Status:** IMPACT MAP ONLY. **This document changes nothing.** No architecture contract, no
migration, no test, no production object is edited, created or contacted by it. It is the
enumeration a later remediation pass executes from, and the enumeration an owner reads to
know what the ruling actually costs.

**Produced:** 2026-08-28 · branch `docs/o17-impact-map`, cut from `phase2/consolidation`.
**Corpus read at:** `0f739d3` (see §0.1 — the base moved during this pass).
**Scope of the sweep:** `docs/architecture/**` and `ARCHITECTURE_FREEZE.md`.

---

## 0. The ruling

**`O17` / `MD-2` = OPTION B.** The CRM export function stays **`postgres`-owned**. The dedicated
`crm_export_builder` Postgres role is **NOT created**. The Layer-0 dedicated-role design is
**rejected for Phase 2**.

Owner's stated reason, verbatim:

> *"the proposed privilege wall has failed to converge across repeated independent reviews and
> introduces silent fail-closed data-integrity failure modes into CRM exports. We will retain the
> existing `postgres`-owned `SECURITY DEFINER` model and strengthen `X-6` through
> structural/catalog assertions and behavioral fixtures rather than maintaining a parallel
> grant/RLS policy matrix."*

**Not open for re-litigation.** Every entry below is a consequence of the ruling, never a
reconsideration of it. Where the corpus recorded a recommendation to adopt (`CRM` §10.1,
`RLS` §15.7, four sites in total), that recommendation is superseded, not argued with.

**`X-6` is not weakened.** The prohibition stands; its assurance moves from a privilege wall to
structural/catalog assertions plus behavioral fixtures. The replacement assurance is a separate
artifact and is **not** specified here — see §8, defect **N-1**.

### 0.1 The base commit moved, and it matters

The task named `phase2/consolidation` @ `269e473`. At the time of the sweep the branch head was
`0f739d3`, two commits ahead:

| Commit | What it did |
|---|---|
| `84cacf9` | `governance: record OWNER RULING O17/MD-2 = B` — added record row **`OR-1`** and flipped **`O17`** to `CLOSED — OWNER RULING B` |
| `0f739d3` | `fix(record): recompute the header id ranges from the rows` |

**One file changed: `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` (+4/−2).** This
map is written against `0f739d3`, because writing it against `269e473` would have re-flagged as
open a decision row that is already closed and would have missed row `OR-1` entirely. **Two class-A
sites (`A-1`, `A-2`) are therefore already applied.** Every other site in this document is
unremediated at `0f739d3`.

### 0.2 Freeze discipline governs the remediation pass

**Ten of the twelve affected files are on `ARCHITECTURE_FREEZE.md`'s covered-document list**, so
Rule 1 applies: every edit needs a new correction ID ratified into
`_governance/PHASE_2_RATIFICATION_RECORD.md` with owner approval — never a silent edit. `OR-1`
records the *ruling*; it does **not** authorise the *edits*. The remediation pass needs its own
ratified correction ID(s).

Two of the twelve are **not** covered — see §8, defect **N-6**.

---

## 1. Reading this map

Every site is classified into **exactly one** class:

| Class | Meaning |
|---|---|
| **A** | Governance decision record. Records the decision itself. Updatable to CLOSED immediately, low risk. |
| **B** | Architecture contract requiring later remediation. Normative text an implementer builds from. Careful edit. |
| **C** | Migration/package consequence. A package's contents change. |
| **D** | Test/fixture consequence. An assertion to delete, retarget or replace. |
| **E** | DAG consequence. A declared dependency edge that existed only because of this role. |
| **F** | Obsolete Layer-0 design artifact. Text whose only purpose was arguing for or specifying the rejected design. |

**Counts are stated beside their enumerations, never alone.** This corpus has been bitten
repeatedly by a count updated while its enumeration was not (`C128`, `C129`, `C131`, `C134`, `D35`
are all instances). Where a count appears in this document without the list it counts, that is a
defect in this document.

Line numbers are as at `0f739d3` and are navigational aids, not identifiers. Sections are the
identifiers.

---

## 2. CLASS A — governance decision records · **19 sites**, enumerated

Ordered: apply first. These are the cheapest edits and the ones that stop a second reader
re-opening a closed decision.

| # | File · section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **A-1** | `_governance/PHASE_2_RATIFICATION_RECORD.md` · row `O17` (L560) | *"**CLOSED — OWNER RULING B** (2026-08-28) — superseded by row `OR-1`"* | **NONE — already applied** at `84cacf9`. Verify only. | — |
| **A-2** | same · row `OR-1` (L561) | *"the CRM export function stays `postgres`-owned; the dedicated `crm_export_builder` role is NOT created"* | **NONE — already applied.** Verify the reason quote is verbatim and that it names this file. | — |
| **A-3** | same · header id-range line (L1) | `C26–C134 (gaps: C119) · D1–D35 · …` | Confirm `OR-1` is representable in the header's id vocabulary — it is the record's **first** `OR-` id and the header enumerates `C`/`D`/`O`/`RET` families only. Add an `OR` family or state the exception. | A ratified row outside every declared id family; the next recount drops it. |
| **A-4** | `_governance/PHASE_2_OWNER_DECISION_REGISTER.md` · index (L76) | *"`ODR-23` — Adopt the Layer-0 privilege wall for the export builder? · before `087`"* | Mark **CLOSED — ruled B, `OR-1`**. Do **not** "fix" the `087` deadline: the gate is discharged, not moved. | A discharged gate read as live; someone corrects `087`→`076` on a dead row. |
| **A-5** | same · silence-is-unsafe list (L190) | *"`ODR-23` (a half-adopted privilege wall emits a blank contact column that reads as \"nobody consented\")"* | Remove from the unsafe-on-silence list. Silence is no longer possible; the decision is made. | The register keeps reporting an unsafe default for a ruled decision, inflating its own "25 default to the unsafe direction" count. |
| **A-6** | same · `O11` blocking note (L603) | *"this register documents several places where two documents already disagree (`ODR-23`, `ODR-39` …)"* | Strike `ODR-23` from the delta-vs-delta example list — the disagreement it names is resolved. | `O11`'s stated motivation cites a closed conflict as live evidence. |
| **A-7** | same · `### ODR-23` body (L862–L882) | *"**Recommendation — yes, conditionally.**"* · *"**Blocks.** `087`, and hard gate `HG-4`"* | Rewrite as CLOSED: record ruling B, the owner's verbatim reason, and `OR-1`. **Keep** the *"Breaks"* paragraph as the record of why B was chosen. | The register's own recommendation contradicts the owner's ruling in the instrument built to summarise owner decisions. |
| **A-8** | same · merge table (L2196) | *"`ODR-23` \| CRM `D-2` · RLS `MD-2` · AMEND `HG-4`"* | Keep the merge; annotate CLOSED. **This row is the authority for the three-way id equivalence** and is what makes the class-A sweep complete. | Someone closes `MD-2` and leaves `D-2` and `HG-4` open under their own ids. |
| **A-9** | `PHASE_2_RLS_PERMISSION_SPEC.md` · §15.7 row `MD-2` (L2686) | *"**OPEN — recorded as owner decision `O17` (`R3-4`), NOT decided.** This column is headed *Recommendation* and the recommendation is **adopt**"* | Replace with CLOSED + ruling B + `OR-1`. **Delete the word "adopt"** — the corpus already records that *"the word 'Adopt' alone read as a ruling and was cited as one."* | The exact defect `R3-4` fixed, recurring in reverse: a superseded recommendation read as the standing position. |
| **A-10** | `PHASE_2_CRM_EXPORT_SPEC.md` · §13 row `D-2` (L2348) | *"**Recommend adopt.** … **Yes — before 087 / I**"* | Mark CLOSED — ruled B. Blocking column → *"discharged."* | The feature spec's own decision table recommends the rejected design. |
| **A-11** | `PHASE_2_SCOPE_AMENDMENT_2026_08.md` · §11 hard gate `HG-4` (L348) | *"**The Layer-0 privilege-wall decision (CRM D-2) must be made before `087` is authored.**"* | Mark **DISCHARGED** by `OR-1`. Do not delete the row — a hard gate that vanishes reads as a gate nobody checked. | `087` blocked on a decision already made; or worse, the gate silently dropped and no record of its discharge. |
| **A-12** | same · §12 rollout-gate table, CRM row (L390) | *"**HG-4** (Layer-0 decision before `087`) · the X-6 four-layer check green"* | Drop the `HG-4` clause. **Amend *"four-layer"* → *"three-layer"*** — see `B-7`. | A rollout gate naming a discharged prerequisite and a layer count that no longer exists. |
| **A-13** | same · §7 layer-14 rollout gate (L234) | *"The **Layer-0 privilege wall (D-2) must be decided before `087`**, because it changes who owns the builder function"* | Replace with the ruling: the builder is `postgres`-owned; no ownership decision remains. | Second live statement of a discharged gate, in the integration layer an implementer reads first. |
| **A-14** | `_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` · DECISION 3 (L138–L265) | *"## H. OWNER CHOICE"* (unfilled) · *"**RECOMMENDED: B** (revised — the brief as first published said C)"* | Stamp the choice: **B, ruled 2026-08-28**, with the owner's verbatim reason. **Keep §G's two specialist positions verbatim** — they are the record of why B, and `OR-1` cites *"seven independent reviews of which the last two disagreed."* | An unstamped owner-choice block in the instrument the ruling was made on. |
| **A-15** | same · §0.2 / §0.3 (L21, L26, L29) | *"`076` is gated by `ODR-1`, `ODR-2`, `ODR-3` and `O17`"* · *"`O11` → `ODR-2` → `ODR-3` → **`O17`** → `ODR-4` → `ODR-1` → `R2B-1`"* | Remove `O17` from `076`'s gate list. **Keep it in the order line, marked done** — the order's logic (`ODR-1` last) depends on `O17` preceding it. | `076` reported as blocked by a ruled decision; the ruling order read as untouched when its fourth step is complete. |
| **A-16** | same · DECISION 5 §B (L303) | *"the `crm_export_builder` placement is **expressly contingent on `O17`**"* | Restate: the contingency is **resolved**, and the resolution **deletes** the placement. See §7 for the full `ODR-1` interaction. | `ODR-1` signed against a contingency the signer believes is still open. |
| **A-17** | same · appendices (L425, L426, L431) | *"Correct the `HG-4` deadline from `087` to `076` in three documents"* · *"the register … does not know `O17`"* · *"The `O17` \"one silently wrong combination\" stated identically in four documents"* | Prerequisite 2 → **withdrawn** (the gate is discharged; do not correct a dead deadline). Prerequisite 3 → still owed, now widened. Verified-as-sound entry → historical, annotate. | An appendix ordering work on a discharged gate; ~minutes of wasted effort, and a corrected deadline that makes the gate look live. |
| **A-18** | `_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` · §7 (L94) | *"**Registered (acceptable):** package `076`, on `CREATE ROLE crm_export_builder` — gated on `MD-2`/`O17`"* | Delete the entry. **`076` no longer has a registered stop.** Re-check whether §7's *"where an implementer first stops"* verdict changes as a result. | The readiness report names a stop that no longer exists, and the *unregistered* `083` stop below it loses its contrast. |
| **A-19** | same · §8 item 5 (L117) | *"Take five rulings in one sitting — `ODR-1` …, `ODR-2`+`ODR-3` …, **`O17`/`MD-2`**, `R2B-1` …, `O11`"* | Five → **four**, enumerated: `ODR-1`, `ODR-2`, `ODR-3`, `R2B-1`, `O11`. **That is five items under a "four" heading — the enumeration is the authority; recount both.** | The work plan's own count-vs-enumeration defect, in the document that names that defect class. |

**Class A total: 19 sites — `A-1` … `A-19`, enumerated above.** Of these, **2 are already applied**
(`A-1`, `A-2`) and **17 are owed**.

---

## 3. CLASS B — architecture contracts requiring later remediation · **18 sites**, enumerated

Normative text an implementer builds from. Each needs a careful edit, not a deletion.

| # | File · section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **B-1** | `PHASE_2_RLS_PERMISSION_SPEC.md` · §16.10 `AUTHZ-M11` ruling, frame + clause 5 (L3138–L3152, L3196–L3197) | *"**If `MD-2` resolves the other way** and the builder stays `postgres`-owned, **none of 1–4 is built** and the zero-policy list stands unamended."* | **Clause 5 becomes the operative ruling.** Rewrite the section so `postgres`-ownership is stated as the decided position, `BYPASSRLS` stays refused, and the zero-rows narrative is retained **as the reason B was chosen** rather than as a live hazard. | The **highest-risk site in the corpus.** RLS §16.10 is the named authority for the policy register; left as-is it instructs an implementer to build twelve policies the owner refused. |
| **B-2** | same · §16.10 `R3-4` resolution note (L3103–L3136) | *"**`MD-2` is OPEN** … It is recorded as open decision `O17` and is **not decided here**."* | Restate as resolved. **Retain the six-relation collision analysis** — it is what proves the zero-policy list is correct under B. | The document that named the collision reports it unresolved after the resolution. |
| **B-3** | same · header summary bullet 3 (L37) | *"the `crm_export_builder` relation set is **twelve, not ten** … **without the per-relation policy the builder reads zero rows silently**"* | Delete the `crm_export_builder` sentence. **Keep** the *"CRM deny-all set is SIX tables"* sentence — it is independent of this ruling. | A top-of-document summary asserting a relation set that is not built; read before §16.10 by anyone skimming. |
| **B-4** | `PHASE_2_RPC_FUNCTION_CONTRACTS.md` · §17.22 Layer-0 note (L3601–L3620) | *"**Three things must therefore ship together** … (a) `SELECT` on the ten enumerated … (b) a **column-scoped** `GRANT SELECT (id, email) ON auth.users` … (c) one permissive `<schema>_<table>_sel_svc_export` policy per relation."* | Collapse to the closing branch already written: *"If `MD-2` resolves the other way … none of (a)–(c) is built."* **Restate §0.1's `postgres`-owned global as applying unamended** — the deviation is withdrawn. | The RPC spec is where an implementer reads the function's security context. Left as-is it describes a three-part ship-together requirement for a design that does not ship. |
| **B-5** | same · §19 closing global (L4015) | *"The **only** policies in the Phase-2 model are **read** policies … **plus the one Layer-0 exception (`crm_export_builder`) named there**."* | Delete the exception clause. The sentence becomes stronger and simpler: read policies only, no exception. | A named exception to a global invariant, with nothing behind it. This is the sentence that tells an implementer *"policies you write on money tables never run"* — it must not carry a dangling carve-out. |
| **B-6** | `PHASE_2_CRM_EXPORT_SPEC.md` · §11.3 RLS-delta code block (L1830–L1831) | *"-- If D-2 is adopted, each of these additionally carries ONE permissive policy naming `crm_export_builder`"* | Delete the two comment lines. The block above them — six `REVOKE ALL`, RLS on, no policy admitting `anon`/`authenticated` — is **correct under B and needs no change**. | An implementer pasting the block also pastes the conditional and resolves it the wrong way. |
| **B-7** | same · §10 preamble + §13 pushback (L1525–L1527, L2386–L2387) | *"Specified in **four layers**."* · *"If rejected, layers 1–3 stand alone and **§10.2's empty-file-set guard becomes load-bearing rather than merely important**."* | **Four layers → three, enumerated** (§10.2 source grep, §10.3 catalog assertion, §10.4/pgTAP). Promote the empty-file-set guard from *"important"* to *"load-bearing"* — that branch is now taken. **This is where the owner's *"strengthen `X-6`"* obligation attaches.** | The `X-6` assurance silently drops from four layers to three with no compensating strengthening — which is the one thing the ruling explicitly promised not to do. |
| **B-8** | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` · §1.15 preamble (L1785) | *"both join the §16.10 zero-policy register, carrying **exactly one** policy each: the `_sel_svc_export` role gate"* | Delete the policy clause. Both tables carry **zero** policies. **Stated unconditionally today** — see §6, question 3. | Fails `T-RLS-POL-02` as written. A generic statement covering two tables, so one edit fixes two relations — and missing it breaks two. |
| **B-9** | same · §1.15.1 RLS bullet (L1816) | *"One `kernel_identity_contact_pref_event_sel_svc_export` policy per §16.10 clause 2."* | Delete the sentence. | Fails `T-RLS-POL-02` clause (d). |
| **B-10** | same · §1.15.1 Read-authority bullet (L1824) | *"the §5.1 gate inside `venue.build_export_rows`, running as `crm_export_builder`"* | *"…running as `postgres`"*, or drop the role clause entirely. | The canonical write/read-authority record names a principal that does not exist. |
| **B-11** | same · §1.15.2 RLS bullet (L1877) | *"One `kernel_org_contact_consent_event_sel_svc_export` policy per §16.10 clause 2."* | Delete the sentence. | Fails `T-RLS-POL-02` clause (d). |
| **B-12** | same · §1.15.2 Read-authority bullet (L1881) | *"the §5.1 gate inside `venue.build_export_rows` (as `crm_export_builder`)"* | As `B-10`. | As `B-10`. |
| **B-13** | same · §3.18 `venue.export_job` RLS bullet (L3299–L3301) | *"It carries the one `venue_export_job_sel_svc_export` policy of §16.10 clause 2, because `build_export_rows` reads its own job row as `crm_export_builder`."* | Delete. `venue.export_job` returns to **zero policies by design**, its stated posture everywhere else. | Fails `T-RLS-POL-02`. Also the relation the ECC reviewer identified as the one the builder **writes** — a stale grant/policy story here is the most confusing residue of all. |
| **B-14** | `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` · CRM/settlement RLS-EXEC row (L372) | *"`venue.export_job` carries **zero policies by design** — **or exactly one … if owner decision `MD-2` / `O17` adopts** … (the two states are exclusive and the decision is OPEN)"* | Collapse the conditional to the first limb: zero policies, full stop. Delete the `BYPASSRLS` clause with it. | Already conditional, so **low** risk — but it advertises an open decision that is closed. |
| **B-15** | same · architecture-invariant row (L475) | *"**GP-3a** + the **one Layer-0 exception** (if the builder runs as `crm_export_builder` rather than `postgres` …). Owner decision **MD-2**"* | Delete the exception. `GP-3a` stands unqualified. | An invariant row carrying an exception with no subject; `GP-3a` is cited corpus-wide. |
| **B-16** | `PHASE_2_PACKAGE_REGISTRY.md` · fourth-amendment `K-2` narrative (L142, L159) | *"`crm_export_builder` is a role **subject to RLS**, so a missing gate source yields no consent row for anybody"* | **Do NOT delete.** `K-2`'s placement of the two `_event` tables is correct and independent. Restate the *why* without the role: the tables are the gate's source and the gate is in-body. | Deleting it looks like `K-2` was reverted, which it was not. Leaving it makes a ratified amendment's rationale depend on a rejected design. |
| **B-17** | same · §2.2 `SEAM-4` rule statement (L491–L493) | *"**SEAM-4 (NEW, `R2B`)** — a **`GRANT`** is authored in the package equal to `max()` of the package creating the **relation** and the package creating the **grantee role**."* | **Recommendation only — see §6, question 2.** Keep the rule; relabel it as a standing rule with **no current subject**. | See §6.2. Retiring it silently invites recurrence of a hard `42704`; keeping it unlabelled sends the next reader hunting for a grant set that is not there. |
| **B-18** | `PHASE_2_SUPABASE_MIGRATION_PLAN.md` · §0 `SEAM-4` rule statement (L170–L173) | *"**SEAM-4 (NEW, `R2B`, binding — the GRANT corollary).**"* | As `B-17`. **Both statements must be edited identically or not at all** — two documents stating one rule differently is the `C128`/`D35` defect class. | Divergent statements of a binding rule across the two DDL-authoritative documents. |

**Class B total: 18 sites — `B-1` … `B-18`, enumerated above.**

---

## 4. CLASS C — migration/package consequences · **23 sites**, enumerated

A package's contents change. **Six packages** are touched: `076`, `077`, `078`, `079`, `082`, `087`.
No seventh — see §5 and §6.1.

### 4.1 Package `076` — the role itself — 7 sites

> **Three of these (`C-6`, `C-7`, and `C-19` in §4.6) still schedule the role in `087`.** They predate
> `C115`'s move and are stale on placement as well as on existence. Grouped by the object rather than
> by the number they quote; the canonical placement at head is `076`.

| # | Section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **C-1** | `PHASE_2_PACKAGE_REGISTRY.md` §2 table, `076` row (L392) | *"**`R2B` `CREATE ROLE crm_export_builder NOLOGIN` + the column-scoped `auth.users(id,email)` grant, moved from `087` (`C115`)**"* | Delete the clause. `076` returns to: 4 schemas + GRANT boundary + shared helpers. | The canonical package map — *"if another document disagrees, this table wins"* — orders a `CREATE ROLE` the owner refused. |
| **C-2** | same, JSON `packages[076].scope` (L651) | *"… + CREATE ROLE crm_export_builder NOLOGIN and GRANT SELECT (id,email) ON auth.users TO it (R2B/C115)"* | Delete the clause. | The machine-readable surface disagrees with the prose surface — the exact parity the registry asserts across four surfaces. |
| **C-3** | `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8/`076` **Purpose** (L1261) | *"**and the one non-superuser role the boundary needs (`crm_export_builder`, `R2B`/`C115`)**"* | Delete. | The package's stated purpose includes an object it must not create. |
| **C-4** | same §8/`076` **Grants** (L1267) | *"**Plus `CREATE ROLE crm_export_builder NOLOGIN` and `GRANT SELECT (id, email) ON auth.users TO crm_export_builder`, column-scoped — MOVED HERE from `087` by `R2B`/`C115`**"* | Delete both statements. **The `auth.users` grant goes with the role** — see §6, question 4. | The literal DDL an implementer authors. Highest-consequence single line in class C. |
| **C-5** | same §8/`076` **Rollback** (L1273) | *"`DROP SCHEMA … CASCADE` ×3 + drop helpers + **`DROP ROLE crm_export_builder`**"* | Delete the `DROP ROLE`. | A rollback that raises on a role that was never created. **Not covered by the registry's "one CREATE ROLE, thirteen grants, twelve policies" revert claim** — see §6.1. |
| **C-6** | `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §5 feature/package map, CRM row (L117) | *"`087` (`export_job`, `crm-exports` bucket, 8 export RPCs, **`crm_export_builder`**)"* | Delete the role from `087`'s contents. **Note the row is already stale** — it puts the role in `087` while the corpus at head puts it in `076`. | Two wrong facts in one cell; correcting only the placement leaves the role. |
| **C-7** | `PHASE_2_CRM_EXPORT_SPEC.md` §11.1 element 23 (L1737) | *"`crm_export_builder` role + policies (Layer 0) \| `ADDITIVE SCHEMA CHANGE` — **D-2** \| **087 / I**"* | **Delete element 23 outright** — it is the only element in the schedule that is wholly the rejected design. Renumber nothing; leave the id vacant with a note, per the corpus's own `T-SCHEMA-APPR-06` precedent. | The feature's own build schedule ships the rejected object. Renumbering instead of vacating would repoint ~30 element ids across five documents. |

### 4.2 Package `077` — 3 sites

| # | Section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **C-8** | `…MIGRATION_PLAN.md` §8/`077` **Grants** (L1286) | *"**Plus `GRANT SELECT … TO crm_export_builder` on FOUR of this package's tables — `identity_ext`, `identity_contact_pref`, `identity_contact_pref_event`, `org_customer_key`**"* | Delete. Four of the thirteen grants. | `42704` at `077` — the original `C115` defect, re-armed in the opposite direction. |
| **C-9** | same §8/`077` **RLS** (L1283) | *"`identity_contact_pref_event` joins the §16.10 zero-policy register and carries **exactly ONE policy** — `kernel_identity_contact_pref_event_sel_svc_export`, `USING (current_user = 'crm_export_builder')`"* | Delete the policy sentence. **Stated unconditionally, with the literal `USING`** — this is one of the three plan statements that now **fail `T-RLS-POL-02`**; see §6, question 3. | A policy created against a role that does not exist. Postgres accepts it (a bare string comparison), so it **applies green** and is a permanent dead grant-shaped artifact nothing removes. |
| **C-10** | `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §7 layer 4 (L224) | *"the `_sel_svc_export` policies that make the `crm_export_builder` owner work"* | Delete the clause; the RLS layer keeps its four matrices and `T-RLS-CRM-01`. | The integration layer schedules policies for a rejected owner across `077`/`082`/`087` in one cell. |

### 4.3 Package `078` — 1 site

| # | Section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **C-11** | `…MIGRATION_PLAN.md` §8/`078` **Grants** (L1302) | *"**Plus `GRANT SELECT … TO crm_export_builder` on TWO of this package's tables — `catalog.event`, `catalog.event_session`**"* | Delete. Two of the thirteen. | `42704` at `078`. |

### 4.4 Package `079` — 1 site

| # | Section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **C-12** | `…MIGRATION_PLAN.md` §8/`079` **Grants** (L1319) | *"**Plus `GRANT SELECT … TO crm_export_builder` on ONE of this package's tables — `kernel.tickets`**"* | Delete. One of the thirteen. | `42704` at `079`, in the custody package. |

### 4.5 Package `082` — 2 sites

| # | Section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **C-13** | `…MIGRATION_PLAN.md` §8/`082` **Grants** (L1368) | *"**Plus `GRANT SELECT … TO crm_export_builder` on FOUR of this package's tables — `org_contact_consent`, `org_contact_consent_event`, `venue.order`, `venue.order_item`**"* | Delete. Four of the thirteen. | `42704` at `082`. |
| **C-14** | same §8/`082` **RLS** (L1365) | *"**Both join the §16.10 zero-policy register and each carries exactly ONE policy — `<schema>_<table>_sel_svc_export`, `USING (current_user = 'crm_export_builder')` and nothing else.**"* | Delete the policy sentence. **Two relations, stated unconditionally** — plan statements 2 and 3 of the three that now fail `T-RLS-POL-02`. | As `C-9`, doubled. |

### 4.6 Package `087` — 5 sites

| # | Section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **C-15** | `…MIGRATION_PLAN.md` §8/`087` **Grants** (L1456) | *"**Plus `GRANT SELECT ON venue.export_job TO crm_export_builder` — the twelfth and last of the `SEAM-4` set … The ROLE itself is no longer created here — it moves to `076`**"* | Delete both sentences. The second is a pointer to `C115` and dies with it. | `42704` at `087`; and a dangling forward reference to a `076` object that is not there. |
| **C-16** | same §8/`087` **RLS** (L1451) | *"`build_export_rows` runs as the narrow **`crm_export_builder`** role — granted SELECT on exactly the enumerated roster relations … and never `BYPASSRLS`"* + the `R2B` parenthetical *"the `crm_export_builder` grant of `C115` is not a client grant and does not falsify it"* | Rewrite: `build_export_rows` is `postgres`-owned per RPC §0.1. **Delete the parenthetical** — it defends a grant that no longer exists and makes the *empty client grant set* statement read as qualified when it is absolute. | **This is an ownership assertion, not a grant or a policy — the registry's revert claim does not name it.** See §6.1. |
| **C-17** | `PHASE_2_PACKAGE_REGISTRY.md` JSON `packages[087].delta_added` (L662) | *"crm_export_builder role MOVED to 076 by R2B/C115"* | Delete the entry. | Machine-readable surface retains a move of an object that does not exist. |
| **C-18** | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.1 placement row `087` (L3945) | *"`venue.export_job`, the `crm-exports` bucket, the eight export RPCs, **`crm_export_builder` role** \| CRM §11.1-9…19/23 \| ✓"* | Delete the role from the placement row; drop the `/23` from the CRM element citation (see `C-7`). | The schema spec's placement register — the third of the four surfaces — keeps the object. |
| **C-19** | `PHASE_2_SCOPE_AMENDMENT_2026_08.md` §7 layer 2c (L221) | *"`venue.export_job` · the private `crm-exports` bucket (zero client policies) · **the `crm_export_builder` definer role**"* | Delete the third item. | The integration layer's physical-schema row schedules the role as an `ADDITIVE SCHEMA CHANGE`. |

### 4.7 Cross-package — the `C115` grant map itself · 4 sites

| # | Section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **C-20** | `PHASE_2_PACKAGE_REGISTRY.md` JSON `contents.grants.crm_export_builder` (L581–L599) | `"role_created_in": "076"` · `"relation_count": 12` · `"grants_by_package": {…}` · `"edges_added": 0` | **Delete the whole `grants` object** (or set `grants: {}`). It is the single machine-readable home of the thirteen-grant map. **Preserve `edges_added: 0` as evidence** in the remediation's own record — it is what proves class E is empty. | The one place a parser could rebuild the entire rejected grant set from. Leaving it means every automated four-surface check keeps finding it. |
| **C-21** | `…MIGRATION_PLAN.md` §8/`076` `C115` enumeration row (L1268) | *"**The defect: `GRANT … TO crm_export_builder` appeared in NO package's Grants row, anywhere** … **Repair … `SEAM-4`**"* | Delete the row. **Retain the `42704`/`SEAM-4` derivation in the remediation's ratified record**, not in the plan — it is the evidence for the class-B `SEAM-4` recommendation. | The longest single statement of the rejected design in the DDL-authoritative document. |
| **C-22** | same §8/`076` *"The twelve, plus `auth.users`"* row (L1269) | *"`076` — **`auth.users`** … `077` — … *(4)* · `078` — … *(2)* · `079` — … *(1)* · `082` — … *(4)* · `087` — … *(1)*. **Four plus two plus one plus four plus one is twelve**"* | Delete the row. **This row is the authority for the thirteen-grant enumeration** — copy it into the remediation record before deleting, or the revert loses its own checklist. | Delete the map before executing the revert and you cannot prove all thirteen were removed. **Sequence this site LAST within class C.** |
| **C-23** | same §8/`076` *"OWNER DECISION, recorded and NOT taken"* row (L1270) | *"if `MD-2` resolves `postgres`-owned, **`C115` reverts as one unit** — `CREATE ROLE` in `076`, thirteen grants, twelve policies — with no other package affected"* | Replace with the ruling and a pointer to this map. **This row is the pre-authored revert instruction** — the remediation is executing a branch the plan already wrote, not inventing one. | Losing the fact that the revert was pre-specified; and leaving a live conditional on a closed decision. |

**Class C total: 23 sites — `C-1` … `C-23`, enumerated above.**
**Packages affected: 6 — `076` (7), `077` (3), `078` (1), `079` (1), `082` (2), `087` (5), plus 4 cross-package map sites. 7+3+1+1+2+5+4 = 23.**

---

## 5. CLASS D — test/fixture consequences · **13 sites**, enumerated

| # | File · section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **D-1** | `…MIGRATION_PLAN.md` §8/`076` Tests · `T-SCHEMA-GRANT-01` (L1274) | *"the role `crm_export_builder` **exists** after THIS package's replay — `pg_roles`, not a grep — and is `NOLOGIN` with no membership"* | **RETIRE.** Optionally **invert** to a new assertion: `pg_roles` contains **no** `crm_export_builder` after `076`. An inverted assertion is cheap and pins the ruling structurally. | A required test asserting the existence of an object the owner refused. It fails on a correct chain — a red gate on day one, the `C134` failure shape. |
| **D-2** | same · `T-SCHEMA-GRANT-02` (L1274) | *"it holds `SELECT` on exactly `(id, email)` of `auth.users` and on no other column of it — asserted column-by-column"* | **RETIRE.** No grantee exists. | As `D-1`. |
| **D-3** | same · `T-SCHEMA-GRANT-03` (L1274) | *"replay `000 → 077` and every `GRANT … TO crm_export_builder` in `077` succeeds"* | **RETIRE.** Its subject — thirteen grants — is deleted by `C-8`/`C-11`/`C-12`/`C-13`/`C-15`. | As `D-1`. Note this is the assertion written to fail against the *pre-fix* chain; under B it fails against the *post-fix* chain too, for the opposite reason. |
| **D-4** | `PHASE_2_RLS_PERMISSION_SPEC.md` §16.11 row `T-RLS-POL-02` (L3377) | *"**`MD-2`-GATED (`O17`): if `MD-2` resolves `postgres`-owned, ZERO `_sel_svc_export` policies exist and clauses (a)–(d) collapse to the original assertion** — the test reads the resolution, it does not assume it"* | **The gate resolves; take the collapse.** Clauses (a)–(d) and the six-relation carve-out are deleted; the row returns to *"every relation in the zero-policy list has RLS enabled and holds zero policies"*, plus the unconditional no-`USING (true)` clause. | **This row is already correct under B** and is the test that catches the three plan statements and four schema statements. Editing the plan/schema without collapsing this row leaves the corpus internally consistent but describing the wrong design. |
| **D-5** | same §16.11 row `T-RLS-CRM-04` (L3408) | *"An export run **as `crm_export_builder`** over a one-granted / one-withdrawn consent fixture emits **exactly one** contact cell and suppresses exactly one — **not merely \"the job succeeded\"**"* | **RETARGET, do not retire.** Delete *"as `crm_export_builder`"*; the fixture runs as the `postgres`-owned definer. **The assertion is the single most important survivor of this ruling** — it is the behavioral fixture the owner's reason names. | Retiring it removes the one positive detector of a silently-blank contact column. Leaving it unretargeted makes it unrunnable and it gets deleted as dead. |
| **D-6** | same §16.10 clause 4 (L3187) | *"**`T-RLS-CRM-04` (positive, and load-bearing):** an export job run end-to-end as `crm_export_builder` …"* | Retarget identically to `D-5`. **Move the clause out of the rejected clause-1–4 block** or it is deleted with them. | The clause is *inside* the block that clause 5 says is not built — so a literal revert deletes the corpus's best fixture by accident. **Flag this explicitly to the remediation pass.** |
| **D-7** | same §16.10 clause 1 (L3170) | *"**No demographic relation appears, and none may be added** — that is the property `T-RPC-CRM-06`'s reader enumeration asserts."* | **Preserve the property and re-home it.** Under B it is no longer a property of a grant set; it becomes a property of the **function bodies**, asserted structurally over `pg_proc`. | The property survives the ruling only if it is moved before its host clause is deleted. This is the `X-6` structural assurance the owner's reason promises. |
| **D-8** | `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §17.22 Tests · `T-RPC-CRM-06` (L3622) | *"**reader enumeration**: no export function's definition matches a demographic relation, **with a non-vacuity guard proving the assertion can see all twelve export functions**"* | **KEEP AND STRENGTHEN.** Under B this becomes the **sole** structural guard on `X-6` — the grant wall that was to make the violation impossible is gone. **First disambiguate the id: `T-RPC-CRM-06` is defined twice in this document** — see §8, defect **N-2**. | Retargeting the wrong `T-RPC-CRM-06` (the `assert_may_request` one at §20.7.8) leaves the reader enumeration untouched and silently strengthens nothing. |
| **D-9** | `PHASE_2_CRM_EXPORT_SPEC.md` §12 assertion 34g (L2324) | *"**The Layer-0 builder role actually returns rows.** With `crm_export_builder` as definer owner, a build over a fixture … returns the expected row count and a non-zero `contact_cells_emitted`."* | **RETIRE.** Its entire premise is the rejected design. | An assertion in the pgTAP list that cannot be written. |
| **D-10** | same §12 assertion 34f (L2321) | *"**The blank-column canary.** A `ready` job with `contact_cells_emitted = 0` and `contact_cells_suppressed = row_count` raises a `platform_risk` signal … the builder fixture … asserts `contact_cells_emitted > 0`"* | **KEEP; retarget the rationale.** Under B the canary's *cause* changes (a consent bug, not a privilege bug) but the detector is unchanged. **`B-7`'s strengthening obligation should extend it past the contact column** — the brief records it covers **1 of 21** columns. | Deleted alongside 34g as "the Layer-0 fixtures", which would remove the ruling's own named replacement assurance. |
| **D-11** | `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` §10 · the twelve `_sel_svc_export` policies (L1014) | *"**CONDITIONAL on owner decision `MD-2` / `O17`**: if the builder stays `postgres`-owned, **none of the twelve exists**"* | Take the stated branch: delete the row. **This is the only place in the corpus where the twelve policy names are written out** — see §8, defect **N-4**. Copy them into the remediation record first. | Delete without copying and the revert has no checklist of what it removed. |
| **D-12** | same §9.1 register · `T-RLS-POL-02` row (L325, L819) | register entry scheduling `T-RLS-POL-02` | Repoint to the collapsed assertion (`D-4`). The matrix's binding vocabulary is *"exists in the cited spec at this baseline"* (`C84`) — so it goes stale the moment `D-4` lands. | The matrix's `67/67` set-equality claim (`C129`) breaks silently. |
| **D-13** | same §9.1 register · `T-RLS-CRM-03`/`-04` row (L852) | *"the one-granted / one-withdrawn export fixture emitting **exactly one** cell … (`AUTHZ-M11`)"* | Retarget with `D-5`; the `AUTHZ-M11` citation now points at a rewritten section. | Same staleness class as `D-12`. |

**Class D total: 13 sites — `D-1` … `D-13`, enumerated above.**
**Of these: 4 retired (`D-1`, `D-2`, `D-3`, `D-9`), 8 retargeted or collapsed (`D-4`…`D-8`, `D-10`, `D-12`, `D-13`), 1 deleted-after-copy (`D-11`). 4+8+1 = 13.**

---

## 6. CLASS E — DAG consequences · **0 sites**

**No package-DAG dependency edge exists solely because of `crm_export_builder`. The enumeration is
empty, and that is a verified result rather than an assumption.**

Evidence, three independent surfaces:

1. `PHASE_2_PACKAGE_REGISTRY.md` JSON `contents.grants.crm_export_builder.edges_added: 0`, with
   `edges_note`: *"Every package holding a grant reaches `076` transitively (`077 → 076` directly,
   the rest through it) and the corpus does not declare transitive edges — `085` does not declare
   `076` either, yet needs its schemas."*
2. The seventh amendment's edge tally, §3: *"`declared_edge_count` 39 → 45, six added, enumerated —
   `081 → 083`, `078 → 085`, `081 → 085`, `083 → 085`, `086 → 088`, `087 → 088`. **`C112`, `C115`,
   `C116` and `C117` add none.**"*
3. Direct check of the JSON `depends_on` sets: **`077` is the only package declaring `076`**, and it
   declares it for the four schemas and the two shared trigger functions — not for the role. `076`'s
   own `depends_on` is `[]`. Removing the role changes no `depends_on` on any package.

**Consequence: `declared_edge_count` is unchanged at 45, and four-surface parity is unaffected.**
See §7.

**Two sites to VERIFY, not change** (they assert the emptiness this class relies on): registry JSON
`edges_added`/`edges_note` (L595–L596) and the seventh amendment's edge tally (L335). Both are
correct as written and must survive the class-C deletion of the surrounding `grants` object — copy
`edges_added: 0` into the remediation record before `C-20` deletes it.

---

## 7. CLASS F — obsolete Layer-0 design artifacts · **8 sites**, enumerated

Text whose only purpose was arguing for, or specifying, the rejected design.

| # | File · section | Quoted text (short) | Remediation | Risk if missed |
|---|---|---|---|---|
| **F-1** | `PHASE_2_CRM_EXPORT_SPEC.md` §10.1 *"Layer 0 (structural, recommended) — a privilege wall"* (L1531–L1575) | *"Make the reference **impossible**, not merely detectable."* … *"**Recommendation: adopt Layer 0.**"* | **Retire the subsection wholly**, keeping its heading as a tombstone that names `OR-1`. It contains the three-row *"Needed / Why it was missing"* table, the `auth.users` grant, the per-relation policy requirement and the cost paragraph — every one of them the rejected design. | The most persuasive single argument for the rejected wall, sitting in the feature spec an implementer reads first. Deleting it without a tombstone invites a future pass to re-derive it — which is exactly what the owner's *"failed to converge across repeated independent reviews"* is about. |
| **F-2** | `PHASE_2_RLS_PERMISSION_SPEC.md` §16.10 clauses 1–4 (L3156–L3195) | clause 1 *"the relation set is closed and named here … **twelve, not ten**"* · clause 2 *"`USING` clause is `current_user = 'crm_export_builder'` and nothing else"* · clause 3 *"`T-RLS-POL-02` is amended to exclude exactly this policy name pattern"* · clause 4 the `T-RLS-CRM-04` requirement | Retire clauses 1–3 per clause 5. **Rescue two things first: `T-RLS-CRM-04` from clause 4 (`D-6`) and the demographic-exclusion property from clause 1 (`D-7`).** | Clause 5 already says *"none of 1–4 is built."* A literal execution deletes the corpus's best behavioral fixture and its `X-6` structural property along with the wall. **This is the single most dangerous instruction in the remediation.** |
| **F-3** | `PHASE_2_PACKAGE_REGISTRY.md` §2.2 `SEAM-4` worked example (L494–L495) | *"**The corollary is that a role with grants owed from package N must be created at or before N** — which is why `crm_export_builder` moves to `076` (`C115`)."* | Delete the *"which is why …"* clause. **Keep the corollary** — it is the rule, and it is right. | The rule's only worked example points at a deleted object; a reader concludes the rule was reverted with it. |
| **F-4** | `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §0 `SEAM-4` cross-reference (L174) | *"a role with grants owed from package `N` must be created at or before `N` — **see §8/`076` and `C115`**"* | Delete the cross-reference; keep the rule. **Edit in lockstep with `F-3`.** | A pointer into a deleted plan row. |
| **F-5** | `PHASE_2_PACKAGE_REGISTRY.md` §3 seventh amendment, `R2B`-9 / `C115` paragraph (L318–L330) | *"**`R2B`-9 (`C115`) — a twelve-relation GRANT set that no package's Grants row contained.** … Repair by new rule **`SEAM-4`**: the role moves to **`076`** … = **twelve** plus the `auth.users` grant. … **The whole set is contingent on RLS `MD-2`, which is recorded and NOT taken here.**"* | Replace with a superseded note citing `OR-1`. **Do not delete silently** — the seventh amendment is a ratified structure and a vanished paragraph reads as a merge accident. | The registry's own narrative of the amendment still places the role. |
| **F-6** | same §3 · objects-moved tally (L343) | *"**Objects moved between packages: three** … **plus the role `crm_export_builder` (`087 → 076`)**."* | *"Objects moved between packages: **three**"* — the three named objects stand; delete the *"plus the role"* clause. **A count-beside-enumeration site: the count `three` is already correct; only the appendix goes.** | The exact defect class this corpus keeps hitting. Editing the count instead of the appendix would make it wrong in the other direction. |
| **F-7** | same §3 · open-owner-questions list (L350–L353) | *"**Three questions ARE owner decisions and NONE is taken here:** (1) `p_cause`'s admissible values … (2) **the whole `crm_export_builder` grant set is contingent on RLS `MD-2`** … (3) `090`'s *reverts as one unit* property"* | **Three → two, enumerated:** (1) `p_cause` (`R2B-1`), (2) `090`'s revert property. Item (2) is now **taken** by `OR-1`. | A ratified amendment reporting three open owner questions when one is ruled — and it is the count-not-enumeration shape again. |
| **F-8** | `_governance/PHASE_2_RATIFICATION_RECORD.md` · ratified row `C115` (L643) | *"**`GRANT … TO crm_export_builder` is required on twelve relations spanning `077`–`087` and appears in NO package's Grants row** …"* | **DO NOT EDIT.** The record is append-only — its own rule: *"No prior row — anyone's — is renumbered, reworded or retracted."* `C115` is **superseded by `OR-1`**, which already names it. Add nothing to row `C115` itself. | A remediation pass that "reverts `C115`" by editing row `C115` breaks the append-only discipline of the one file that must merge cleanly across concurrent passes. **State this constraint explicitly in the remediation brief.** |

**Class F total: 8 sites — `F-1` … `F-8`, enumerated above.**

---

## 8. The six specific questions

### 8.1 Does `C115` revert cleanly as one unit? — **Substantially YES, with four items the claim omits**

The claim under test, from `…MIGRATION_PLAN.md` §8/`076` and registry JSON
`grants.crm_export_builder.owner_decision`:

> *"`C115` reverts as one unit if so: one `CREATE ROLE`, thirteen grants, twelve policies, **no other
> package affected**."*

**Verified against the actual package rows:**

| Claim element | Verdict | Evidence |
|---|---|---|
| **One `CREATE ROLE` in `076`** | **HOLDS** | Registry §2 `076` row (L392) · registry JSON `packages[076].scope` (L651) · plan §8/`076` Grants (L1267). Three surfaces, one object, no fourth site. `crm_export_builder` is the **only** `CREATE ROLE` in `docs/architecture/**`. |
| **Thirteen grants** | **HOLDS — arithmetic and rows both check** | `076` ×1 (`auth.users`, column-scoped) + `077` ×4 + `078` ×2 + `079` ×1 + `082` ×4 + `087` ×1 = **13**. All six Grants rows exist and carry exactly those counts: L1267, L1286, L1302, L1319, L1368, L1456. |
| **Twelve policies** | **HOLDS arithmetically; MISLEADS as to where they live** | 4+2+1+4+1 = 12 by table package. **But only THREE of the twelve are stated in any package row** (`077` ×1 at L1283, `082` ×2 at L1365). The other **nine** exist only as a *pattern* in RLS §16.10 clause 2 and as an *enumeration* in matrix §10. So the "twelve policies" revert is 3 package-row edits + 1 authority edit + 1 matrix edit — **not twelve package-row deletions.** |
| **No other package affected** | **HOLDS** | Six packages — `076`, `077`, `078`, `079`, `082`, `087` — and no seventh. Verified three ways: the grant map names exactly six; `edges_added: 0` and no `depends_on` set changes (§6); and no site in classes B/C/D/F falls in `080`, `081`, `083`–`086`, `088`–`091`. |

**Four things the revert touches that the claim does not name:**

1. **`076`'s Rollback row** (`C-5`) — `DROP ROLE crm_export_builder`. Not a grant, not a policy.
2. **`076`'s Tests row** (`D-1`, `D-2`, `D-3`) — three `T-SCHEMA-GRANT-*` assertions.
3. **`087`'s ownership sentence and its `R2B` parenthetical** (`C-16`) — *"`build_export_rows` runs
   as the narrow `crm_export_builder` role"*. An **ownership** assertion, which is neither a
   `CREATE ROLE`, nor a grant, nor a policy — and it is the assertion the ruling is actually about.
4. **`SEAM-4`** (`B-17`, `B-18`, `F-3`, `F-4`) — a corpus rule in two documents, left with **zero
   subjects**. Not a package, so *"no other package affected"* survives — but the corpus does not.

**Plus two consequences outside the package system:** the seventh amendment's own two numeric claims
(`F-6`, `F-7`), and the append-only constraint on ratified row `C115` (`F-8`).

**VERDICT: `C115` reverts cleanly as one unit at the package level — six packages, and there is no
seventh. The registry's sentence is true and is a safe basis for the revert, but it is an
incomplete checklist: four further items in three of those same six packages, plus `SEAM-4` and two
amendment-level counts, are not covered by it. Do not use it as the acceptance criterion.** Use the
class-C enumeration (§4) plus `D-1`…`D-3` and `F-3`…`F-7`.

### 8.2 `SEAM-4` — does it still have any other subject? — **NO. Recommendation: KEEP, relabelled.**

**`SEAM-4` has exactly one subject in the entire corpus, and ruling B removes it.**

Verified: `crm_export_builder` is the only `CREATE ROLE` anywhere in `docs/architecture/**`. Every
other grantee named in any Grants row — `anon`, `authenticated`, `service_role`, `PUBLIC`,
`postgres` — is a pre-existing Supabase role that exists before migration `000`. For every one of
them `max(package(relation), package(grantee))` collapses unconditionally to the relation's own
package, so `SEAM-4` is **vacuously satisfied everywhere else** and constrains nothing.

**Under ruling B, `SEAM-4` becomes dead text: a binding rule with zero live subjects.**

**RECOMMENDATION — this is a recommendation, not a change; it is an owner/registry-owner call:**

> **Keep `SEAM-4` as a standing general rule, and relabel it as having no current subject.**

Reasons, in order of weight:

1. **It was derived from a real hard-replay failure, not invented.** `C115` found a `42704` that
   would have aborted `077` on the first authoring attempt. A rule retired for want of a subject is
   a rule whose failure mode returns the next time a subject appears — and the corpus's own record
   of that failure would then be in a superseded amendment nobody reads.
2. **Two open conditionals could give it a subject immediately.** `COND-A` (event outbox, package
   `076`) and `COND-B` (`notify` schema, package `092`) are both unruled. Neither currently proposes
   a role, but `COND-B` introduces a whole schema with its own grant surface.
3. **Retiring it costs a corpus-wide edit and buys nothing.** It is cited in six places across two
   documents (`registry` §2.2 ×2, §6 rule 6c; `plan` §0 ×2, §8 acceptance property) and is part of
   the `SEAM-1`/`-2`/`-2a`/`-3`/`-4` set that registry rule 6 names as a unit.

**But it must not be left as written.** Today both statements say *"which is why `crm_export_builder`
moves to `076` (`C115`)"* — a worked example pointing at a deleted object. Relabel to: *a standing
rule with no current instance in the `076`–`091` band; the instance that motivated it was
`C115`, superseded by `OR-1`.* That is `F-3` and `F-4`, and the rule statements themselves
(`B-17`, `B-18`) are edited in lockstep or not at all.

### 8.3 The `_sel_svc_export` policies — **CONFIRMED. Twelve specified, three stated unconditionally in the plan, zero permitted, and the plan's three now FAIL `T-RLS-POL-02`.**

**Confirmed, in all four parts:**

1. **Twelve are specified.** RLS §16.10 clause 2, as a pattern (*"each of those relations carries
   exactly one additional policy, `<schema>_<table>_sel_svc_export`"*), over clause 1's closed
   twelve-relation set. The twelve **names** are written out in exactly one place: matrix §10
   (L1014).
2. **The migration plan names three, unconditionally.** §8/`077` RLS row (L1283) —
   `kernel_identity_contact_pref_event_sel_svc_export`, **with the literal `USING` clause**; §8/`082`
   RLS row (L1365) — `org_contact_consent` and `org_contact_consent_event`, *"each carries exactly
   ONE policy."* **1 + 2 = 3.** Neither statement is conditioned on `MD-2`. This is `C-9` and `C-14`.
3. **Under ruling B, ZERO must exist.** RLS §16.10 clause 5: *"none of 1–4 is built and the
   zero-policy list stands unamended."*
4. **`T-RLS-POL-02` already says so.** Its `MD-2`-gated clause reads verbatim: *"**`MD-2`-GATED
   (`O17`): if `MD-2` resolves `postgres`-owned, ZERO `_sel_svc_export` policies exist and clauses
   (a)–(d) collapse to the original assertion** — the test reads the resolution, it does not assume
   it."*

**Therefore the plan's three unconditional statements now FAIL `T-RLS-POL-02` as written.** Two of
the three relations (`kernel.identity_contact_pref_event`, `kernel.org_contact_consent_event`) are
zero-policy relations, so they fail the collapsed original assertion directly; the third
(`kernel.org_contact_consent`) is likewise in the zero-policy register. The test does not need
amending — **it is already correct under B, and the plan is already wrong against it.**

**CLASSIFICATION: `C` (migration/package consequence)** — `C-9` (`077`, one relation) and `C-14`
(`082`, two relations). They are package-contents rows: what the package creates changes.

**And it is worse than three.** The **schema spec states it unconditionally in FOUR places**, not
three: §1.15 preamble (L1785, generic, covering both `_event` tables), §1.15.1 (L1816), §1.15.2
(L1877), §3.18 (L3299). RLS's own `R3-4` note counts *"three (§1.15.1, §1.15.2, §3.18)"* and then
names the §1.15 preamble separately without counting it. **True total of unconditional statements
across the corpus: 3 (plan) + 4 (schema) = 7**, classified `C-9`, `C-14`, `B-8`, `B-9`, `B-11`,
`B-13` — six sites, because `B-8`'s single generic sentence covers two relations. **All seven
statements fail `T-RLS-POL-02` under ruling B.**

Every other statement of the set is already conditional and needs only its condition collapsed:
RLS §16.10 clause 2 (`F-2`), matrix §10 (`D-11`), matrix L372 (`B-14`), matrix L475 (`B-15`),
CRM §11.3 (`B-6`), RPC §17.22 (`B-4`), plan §8/`076` (`C-21`, `C-22`, `C-23`).

### 8.4 The `auth.users` column-scoped grant — **it goes with the role. Unambiguously.**

`GRANT SELECT (id, email) ON auth.users TO crm_export_builder` **does not survive ruling B.**

Four independent statements settle it:

1. **RLS §16.10** places it inside **clause 1** (*"Plus one GRANT that is not a policy and was
   missing entirely"*), and **clause 5** says *"none of 1–4 is built."*
2. **RPC §17.22** states the mechanism directly: *"free under a `postgres` owner, a grant that must
   exist under a narrow one."* Under `postgres` ownership the read is free; the grant is not merely
   unnecessary, it has no grantee.
3. **Plan §8/`076`** counts it inside the contingency: *"The **entire** grant set is contingent on
   RLS open decision `MD-2`"*, and the revert is *"thirteen grants"* — twelve plus this one.
4. **Registry JSON** `count_note`: *"`auth.users` is a thirteenth GRANT and is **NOT** one of the
   twelve."*

**The trap, and it is the original defect running backwards.** Because the corpus consistently
describes the set as *"the twelve"* **plus** a thirteenth that is *"not one of the twelve"*, a
remediation pass that reverts "the twelve" and stops leaves
`GRANT SELECT (id, email) ON auth.users TO crm_export_builder` in `076`'s Grants row — a grant to a
role that is never created. **That is `42704` at `076`, the very first Phase-2 package, and a hard
replay failure rather than a runtime one** — the same SQLSTATE, the same immediacy and the same
class of oversight that `C115` existed to close. **`C-4` must be executed as a two-part deletion:
the `CREATE ROLE` and the `auth.users` grant, in the same edit.**

### 8.5 Registry amendments affected, and the post-remediation numbers

**Amendments affected: exactly one — the SEVENTH (`R2B`).** The first six touch nothing
`crm_export_builder`-related. The fourth amendment's `K-2` narrative *mentions* the role
(`B-16`) but places nothing; its placement of `kernel.identity_contact_pref_event` in `077` and
`kernel.org_contact_consent_event` in `082` is independent and correct under B.

**Does the seventh amendment survive intact without its `crm_export_builder` clauses? — YES.**

`R2B` carries **nine** corrections: `C110`, `C111`, `C112`, `C113`, `C114`, `C115`, `C116`, `C117`,
`C118`. **Only `C115` is `crm_export_builder`.** The other eight — the door-drain hooks, the
`finalize_primary_order` move, the two `venue.order` columns, the manifest-delta stub, the
`issue_ticket_atoms` move, the `settlement_line_candidate` type, the `on_atom_voided` arity, the two
undeclared edges — stand untouched. **The amendment survives as an amendment; it loses one of its
nine corrections' content.**

Three edits are needed inside it, all enumerated: `F-5` (the `R2B`-9 paragraph), `F-6` (objects
moved), `F-7` (open owner questions).

**Post-remediation registry numbers — computed:**

| Field | At `0f739d3` | After remediation | Why |
|---|---|---|---|
| `amendment_count` | **7** | **7** — unchanged | The seventh amendment survives; it loses one correction's content, not its status. Nothing is unwound. |
| `declared_edge_count` | **45** | **45** — unchanged | `C115` added zero edges (registry `edges_added: 0`; seventh amendment tally *"`C112`, `C115`, `C116` and `C117` add none"*). No `depends_on` set changes. Class E is empty. |
| **Four-surface parity** | **PASS** | **PASS** — unchanged | The four surfaces enumerate *edges*; no edge changes. Verified independently: `076`'s `depends_on` is `[]`, and `077` is the only package declaring `076` — for the schemas and helpers, not the role. |
| `phase2_range` | `{076, 091, count 16}` | **unchanged** | No package added, removed or renumbered. |
| `contents.grants` | 1 role · 13 grants · `relation_count: 12` | **`{}` — 0 roles, 0 grants, `relation_count` field removed** | `C-20`. |
| Roles created in the band | **1** | **0** | `C-1`, `C-2`, `C-4`. |
| Seventh amendment · objects moved between packages | *"three … plus the role"* | **three** — `kernel.issue_ticket_atoms`, `venue.finalize_primary_order`, the `venue.order` attribution-candidate column pair | `F-6`. The **count is already correct**; only the appendix is deleted. |
| Seventh amendment · open owner questions | *"**Three** … and NONE is taken here"* | **two** — (1) `p_cause`'s admissible values (`R2B-1`), (2) `090`'s *reverts-as-one-unit* property | `F-7`. Question (2), the `crm_export_builder` contingency, is **taken** by `OR-1`. |

**All four properties the caller asked about — `amendment_count`, `declared_edge_count`, four-surface
parity, and the count-vs-enumeration discipline — hold after remediation. Two numbers inside the
seventh amendment change, and both are appendix deletions rather than recounts.**

### 8.6 `ODR-1` interaction — **ruling B changes what `ODR-1` would ratify, in four specific ways**

The owner has not yet ratified the package registry (`ODR-1` / brief Decision 5). Ruling B changes
it as follows:

**(1) It resolves one of `ODR-1`'s two non-derived contingencies, making `ODR-1` strictly more
mechanical.** The brief states: *"two of its contents are not derived: the package **count** turns on
`ODR-3`, and the **`crm_export_builder` placement** is expressly contingent on `O17`."* One of the
two is now closed. Only `ODR-3` remains.

**(2) But `ODR-1` MUST NOT be signed against the registry as it stands.** At `0f739d3` the registry's
`076` row creates the role, its JSON `grants` object carries the thirteen-grant map, and its seventh
amendment records the placement as contingent. **Signing today ratifies a `CREATE ROLE` the owner
has just refused.** The brief anticipated exactly this — §0.3: *"`ODR-1` late, because it ratifies
the outputs of the others — and **`O17` option (b) would *delete* content the seventh amendment
places**."* Option (b) is what was ruled.

**(3) The sequencing therefore tightens.** The brief's ruling order (`O11 → ODR-2 → ODR-3 → O17 →
ODR-4 → ODR-1 → R2B-1`) is unchanged in shape, but `O17`'s prerequisite for `ODR-1` is no longer
just *the ruling* — it is **the ruling plus its class-C remediation** (`C-1`, `C-2`, `C-17`, `C-20`
at minimum, being the four registry sites). **`ODR-1` is now gated on this map being executed, not
merely on `OR-1` existing.**

**(4) The numbers `ODR-1` ratifies are unchanged.** Brief Decision 5's independently verified table —
16 packages · band `076`–`091` with 0 gaps and 0 duplicates · **45** declared edges · four-surface
set-equality PASS · every dependency strictly precedes its dependent · DAG acyclic · package set
identical across seven surfaces · all 8 SEAM-2 stub→replacement edges declared — **stands verbatim
after remediation.** Nothing in ruling B touches a package number, a band boundary or an edge.

**One wording consequence.** Brief Decision 5's recommended option reads: *"Ratify all seven
amendments — band 076-091, 16 packages, 45 edges — CONDITIONAL on ODR-3 …"*. It must now read
**"all seven amendments, the seventh as amended by `OR-1`"**, or the signature ratifies the
pre-ruling text of the amendment it names.

**And a caution against attributing the wrong number to this ruling.** `ODR-1`'s option B also
absorbs two owed declaration-only edges (`078 → 086`, `077 → 090`), taking `declared_edge_count`
from **45 → 47**. **That is `ODR-1`'s act and has nothing to do with `O17`.** If both land in one
pass, the remediation record must attribute 45→47 to `ODR-1` and 45→45 to `OR-1`, or the next
reviewer cannot tell which ruling moved the graph.

---

## 9. Found in the sweep and not in the brief — **8 defects**, enumerated

These are consequences and hazards the task description did not name. None is an owner decision;
all are reported, none is acted on.

**N-1 — `_governance/X6_POSTGRES_OWNED_ASSURANCE_PLAN.md` does not exist.** Ratified row `OR-1`
states *"its replacement assurance is specified in `_governance/X6_POSTGRES_OWNED_ASSURANCE_PLAN.md`."*
There is no such file in the tree. **A ratified row with a dangling reference to the artifact that
carries the ruling's one substantive promise** — the *"strengthen `X-6`"* half. Until it exists,
`X-6`'s assurance is three detective layers with no compensating strengthening, which is materially
weaker than either option the owner was offered. **Highest-priority follow-on.**

**N-2 — `T-RPC-CRM-06` is defined TWICE, in one document, with two different assertions.**
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §17.22 (L3622) defines it as the **reader enumeration** (*"no
export function's definition matches a demographic relation, with a non-vacuity guard"*), while
§20.7.8 (L5887, L5942) defines it as the **`assert_may_request` raising-mode structural assertion**
(*"`request_export` and `authorize_export_download` call this function in raising mode … and
`list_export_jobs` is the only caller passing `p_raise := false`"*). RLS §16.10 (L3170) cites the
*first* meaning. **This is exactly the `C128` defect** (`T-RLS-POL-03` naming two assertions), one
document over, and it is live. **It is material to this ruling:** under B the reader-enumeration half
becomes the **sole** structural guard on `X-6`, and a remediation pass that "strengthens
`T-RPC-CRM-06`" without disambiguating has a coin-flip chance of strengthening the wrong assertion.
**Disambiguate before executing `D-8`.**

**N-3 — two different `X-6` ids exist in the corpus.** `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §9
`X-6` is the demographic-reference prohibition — the one the owner's ruling names.
`PHASE_2_RLS_PERMISSION_SPEC.md` §17 `X-6` is a **dashboard/RN integrator** item about the export
allow-list gaining both marketing labels; the traceability matrix (L607) cites *that* one as
*"RLS X-6"*. **The `X6_POSTGRES_OWNED_ASSURANCE_PLAN` of `N-1` must state which `X-6` it assures**,
or it will be read against the wrong one by anyone who greps.

**N-4 — the twelve `_sel_svc_export` policy names exist in exactly ONE place, and it is not the
stated authority.** RLS §16.10 is the declared authority (*"this section is the authority: twelve
relations"*) and states the policy as a **pattern**. The twelve literal names appear only in
traceability matrix §10 (L1014). **This is the `C131` defect verbatim** — *"`T-RLS-POL-01` is
`policies_are(schema, table, ARRAY[…])` and `ARRAY[…]` cannot be filled from a template"* — and
`C131` fixed it for 25 other policies while leaving these twelve as a pattern. Harmless under B
(the set is empty), and it is why `T-RLS-POL-01` needs **no** edit: its arrays never contained a
`_sel_svc_export` element. Recorded so nobody concludes the authority ever enumerated them.

**N-5 — open decision `O18` is stale and is falsified by the freeze at head.** `O18` (ratification
record, 2026-08-28) states *"`ARCHITECTURE_FREEZE.md`'s covered-document list does not name it — nor
`PHASE_2_SCOPE_AMENDMENT_2026_08.md` — so neither is under Rule 1."* **The freeze at head names both**,
in *"Registers and integration layer — added to the covered set 2026-08-28 (`R4-7`; ratification rows
`C126` / `D33`)."* Two same-day passes, opposite conclusions. **Consequence for this remediation:
`O18` creates no exception — both files are under Rule 1 and every edit in classes B/C/D/F needs a
ratified correction ID.**

**N-6 — the freeze's covered-set arithmetic is stale again, by exactly the two files that carry this
ruling.** `R4-7` states *"36 files in the tree, 32 named here, four missing."* At head there are
**39** `.md` files under `docs/architecture/`, **37 named**, and **two missing**:
`_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` and
`_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md`. **Both are in this map's affected-file list**
(sites `A-14` … `A-19`). So **two of the twelve files this remediation must edit are outside Rule 1**,
in a corpus whose freeze note says *"a covered-document list that is silently incomplete is worse
than one that is short — it reads as exhaustive."* Third recurrence of the same staleness.

**N-7 — `ARCHITECTURE_FREEZE.md` itself contains ZERO affected sites.** Swept for
`crm_export_builder`, `MD-2`, `O17`, `ODR-23`, `HG-4`, `SEAM-4`, `_sel_svc_export`, `C115`,
`build_export_rows` and `X-6`: **no hits.** The freeze is untouched by this ruling. Recorded as a
positive result so no one re-sweeps it, and because the freeze *governs* the remediation (§0.2)
without *containing* any of it.

**N-8 — the revert instruction was pre-authored, which lowers the risk of the whole pass.** Plan
§8/`076`'s *"OWNER DECISION, recorded and NOT taken"* row (`C-23`) already contains the branch:
*"if `MD-2` resolves `postgres`-owned, `C115` reverts as one unit … with no other package affected."*
**The remediation is executing a written branch, not designing one.** That is worth stating plainly
against the four items §8.1 shows the branch omits: the branch is a correct starting point and an
incomplete acceptance criterion.

---

## 10. Suggested execution order

Ordered so that no edit destroys the evidence a later edit needs.

| Step | Work | Why here |
|---|---|---|
| **0** | Obtain a ratified correction ID for the remediation pass (freeze Rule 1). Confirm `OR-1` authorises the *ruling* only. | Ten of twelve files are covered; `A-14`…`A-19`'s two are not (`N-6`). |
| **1** | **Copy out, before deleting anything:** the thirteen-grant map (`C-22`), the twelve policy names (`D-11`), `edges_added: 0` (§6), and the `42704`/`SEAM-4` derivation (`C-21`). | Four sites are the corpus's only record of what the revert removes. Delete them first and the revert has no checklist. |
| **2** | **Class A** — 19 sites. Cheapest, and stops a concurrent reader re-opening a closed decision. | Two already applied. |
| **3** | **Rescue before demolition:** `D-6` (`T-RLS-CRM-04` out of RLS §16.10 clause 4) and `D-7` (the demographic-exclusion property out of clause 1). | `F-2` deletes their host block. This is the single most dangerous ordering dependency in the pass. |
| **4** | **Class F** — 8 sites, `F-8` excepted (do not edit; append-only). | Now safe. |
| **5** | **Class B** — 18 sites. `B-17`/`B-18` in lockstep with `F-3`/`F-4`. | Contracts settle before packages so the packages have something correct to point at. |
| **6** | **Class C** — 23 sites, `C-4` as a two-part deletion (§8.4), `C-22` last within the class. | |
| **7** | **Class D** — 13 sites. `D-8` only after `N-2` is disambiguated. | |
| **8** | **Class E** — nothing to do. Verify `declared_edge_count` is still 45 and four-surface parity still PASSes, by parser. | The registry's own §6 rule: *"re-verified by parser after every commit of this pass, not by reading."* |
| **9** | Re-run the count-vs-enumeration check over every count this pass touched: `F-6` (three), `F-7` (two), `A-19` (four/five), `B-7` (three layers), §8.5's table. | The corpus's recurring defect class. |
| **10** | **Then, and separately: `N-1`** — author `X6_POSTGRES_OWNED_ASSURANCE_PLAN.md`, naming which `X-6` (`N-3`). Until it exists the ruling's second half is unfulfilled. | Not remediation; it is the ruling's other obligation. |

**Not in scope for the remediation pass, and named so nobody folds them in:** `ODR-1`'s two owed
edges (45 → 47, §8.6), `ODR-3`'s effect on the package count, `N-2`'s id collision beyond
disambiguating it, `N-5`/`N-6`'s freeze staleness, and any production contact whatsoever.

---

## 11. Totals

**Total sites: 81.**

| Class | Count | Enumeration |
|---|---:|---|
| **A** — governance decision record | **19** | `A-1` `A-2` `A-3` `A-4` `A-5` `A-6` `A-7` `A-8` `A-9` `A-10` `A-11` `A-12` `A-13` `A-14` `A-15` `A-16` `A-17` `A-18` `A-19` |
| **B** — architecture contract | **18** | `B-1` `B-2` `B-3` `B-4` `B-5` `B-6` `B-7` `B-8` `B-9` `B-10` `B-11` `B-12` `B-13` `B-14` `B-15` `B-16` `B-17` `B-18` |
| **C** — migration/package | **23** | `C-1` `C-2` `C-3` `C-4` `C-5` `C-6` `C-7` `C-8` `C-9` `C-10` `C-11` `C-12` `C-13` `C-14` `C-15` `C-16` `C-17` `C-18` `C-19` `C-20` `C-21` `C-22` `C-23` |
| **D** — test/fixture | **13** | `D-1` `D-2` `D-3` `D-4` `D-5` `D-6` `D-7` `D-8` `D-9` `D-10` `D-11` `D-12` `D-13` |
| **E** — DAG | **0** | *(empty — verified in §6, not assumed)* |
| **F** — obsolete Layer-0 artifact | **8** | `F-1` `F-2` `F-3` `F-4` `F-5` `F-6` `F-7` `F-8` |

**19 + 18 + 23 + 13 + 0 + 8 = 81.**

**Files affected: 12.**

| # | File | Sites |
|---|---|---|
| 1 | `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md` | `B-18` · `C-3` `C-4` `C-5` `C-8` `C-9` `C-11` `C-12` `C-13` `C-14` `C-15` `C-16` `C-21` `C-22` `C-23` · `D-1` `D-2` `D-3` · `F-4` — **19** |
| 2 | `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` | `A-9` · `B-1` `B-2` `B-3` · `D-4` `D-5` `D-6` `D-7` · `F-2` — **9** |
| 3 | `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md` | `B-16` `B-17` · `C-1` `C-2` `C-17` `C-20` · `F-3` `F-5` `F-6` `F-7` — **10** |
| 4 | `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` | `B-8` `B-9` `B-10` `B-11` `B-12` `B-13` · `C-18` — **7** |
| 5 | `docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md` | `A-10` · `B-6` `B-7` · `C-7` · `D-9` `D-10` · `F-1` — **7** |
| 6 | `docs/architecture/_governance/PHASE_2_OWNER_DECISION_REGISTER.md` | `A-4` `A-5` `A-6` `A-7` `A-8` — **5** |
| 7 | `docs/architecture/_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` | `A-14` `A-15` `A-16` `A-17` — **4** |
| 8 | `docs/architecture/PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` | `B-14` `B-15` · `D-11` `D-12` `D-13` — **5** |
| 9 | `docs/architecture/PHASE_2_SCOPE_AMENDMENT_2026_08.md` | `A-11` `A-12` `A-13` · `C-6` `C-10` `C-19` — **6** |
| 10 | `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` | `A-1` `A-2` `A-3` · `F-8` — **4** *(`A-1`/`A-2` applied; `F-8` = do not edit)* |
| 11 | `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` | `B-4` `B-5` · `D-8` — **3** |
| 12 | `docs/architecture/_governance/PHASE_2_CONSOLIDATION_FINAL_REPORT.md` | `A-18` `A-19` — **2** |

**19 + 9 + 10 + 7 + 7 + 5 + 4 + 5 + 6 + 4 + 3 + 2 = 81.**

**`ARCHITECTURE_FREEZE.md`: 0 sites** (`N-7`). Swept and clean.

**Packages affected: 6.**

| Package | Sites | What changes |
|---|---|---|
| **`076`** | `C-1` `C-2` `C-3` `C-4` `C-5` `C-6` `C-7` · `D-1` `D-2` `D-3` | `CREATE ROLE` removed · `auth.users` grant removed · rollback `DROP ROLE` removed · three `T-SCHEMA-GRANT-*` retired |
| **`077`** | `C-8` `C-9` `C-10` | 4 grants removed · 1 `_sel_svc_export` policy removed |
| **`078`** | `C-11` | 2 grants removed |
| **`079`** | `C-12` | 1 grant removed |
| **`082`** | `C-13` `C-14` | 4 grants removed · 2 `_sel_svc_export` policies removed |
| **`087`** | `C-15` `C-16` `C-17` `C-18` `C-19` | 1 grant removed · builder ownership restated to `postgres` · role removed from three placement registers |

**No seventh package. Verified three ways in §8.1.** `080`, `081`, `083`, `084`, `085`, `086`, `088`,
`089`, `090`, `091` are untouched.

---

*Design-only. No SQL file, migration, rollback, edge function or implementation code was written,
applied, or contacted. No architecture contract was modified. This document is an enumeration and a
recommendation set; every edit it describes is owed to a later pass under freeze Rule 1.*
