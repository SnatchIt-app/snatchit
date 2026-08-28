# Snatch It — Architecture Freeze

**Status: FROZEN.** Date: 2026-08-24. Branch: `phase2/architecture`.

## Authoritative architecture baseline

- **Frozen baseline commit: `dd960c4`** (branch `phase2/architecture`). Content was baselined at `51cce52`
  (parent chain `85ea818 → 25f55bb → 6a8df64 → 51cce52` on top of the consolidated `main` = `3482133`, which
  carries the full authoritative Phase-0 migration chain `000_baseline + 001–070` + website-form migrations
  and the Phase-0 engineering docs, Gate-2 = PASS) and **closed out in-session** by the review-driven commits
  `ffa6e22 · 164243e · 2635f9e · 57765fa · 64ba92f · fc1a0ba · cf20f1b · dd960c4` — independent-review
  closures (Agents D/E/G) converging on already-ratified corrections; **no new architectural decision was
  taken after `51cce52`**.
- **Rule 1 binds every commit after `dd960c4`.** The first such commit is **Freeze Amendment A-1** (this
  wording + ratification-record rows E-1/OBS-1 + repository-path pointer fixes — administrative closures
  prescribed by the Agent-G adversarial review, introducing no design change).
- A repository tag (`phase2-architecture-v1`) MAY be added by the owner; this file is the immutable reference either way.

## Documents covered by this freeze

**Constitutions (consolidated — the body is authoritative; no precedence algorithm needed):**
`docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` · `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` · `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`

> **`SPEC CORRECTION R4-6` (2026-08-28; ratification rows `C125` / `D33`) — THIS DOCUMENT STATED A FALSE
> INVENTORY OF THE REGISTER THAT GATES EVERYTHING, AND RULE 3 RANKS THIS DOCUMENT *ABOVE* THE REGISTER'S
> READERS.**
>
> It read: *"Record contents, current as of 2026-08-27: **44 rows** … **Three open decisions block a gate:
> O6, O7, O8**."* The record at head carries **114 rows** and **eleven** open decisions. Because Rule 3
> places this freeze above the implementation specs, **the stale count won under the corpus's own stated
> precedence** — a reader reconciling the two was instructed to prefer the wrong one. **Recounted
> mechanically over the record's row tables, not carried forward, and every count below is stated with its
> enumeration** (this corpus has been bitten repeatedly by a count updated while its enumeration was not).

**Record contents — recounted mechanically at `f97f6cd`, 2026-08-28. Every count is followed by its
enumeration; no count in this document may stand alone.**

**114 rows**, and they are: **C26–C98** (73 — the correction series, contiguous, none missing) · **D1–D21**
(21 — the documentation-fix series) · **O-1 … O-5** (5 — the hyphenated owner rulings) · **O6, O12, O13, O14,
O15, O16** (6 — the open decisions that carry their own row; `O7`–`O11` are carried by rows `C51`, `C52`,
`C56`, `C72`, `C75` and have none) · **RET-1 … RET-6** (6 — retractions) · **E-1, OBS-1, A-2** (3). Sum:
73 + 21 + 5 + 6 + 6 + 3 = **114**. C1–C25 are prior-ratified inside the constitutions themselves and are not
counted here.

**99 of the 114 are terminal. 15 rows are `OPEN-GATED`**, and they are: **C50 · O6 · C51 · C52 · C56 · C72 ·
C75 · C77 · O12 · C85 · O13 · C90 · O14 · C95→O15 · C92→O16** — fifteen. *(The record's status table gives
the same fifteen; 114 − 15 = 99.)*

**Eleven distinct open decisions block a gate, and they are `O6` … `O16`** — a row count and a decision count
are **not** the same number, because five decisions are carried by a correction row rather than a row of
their own:

| Decision | Carried by | Gate | What it blocks |
|---|---|---|---|
| **O6** | `C50` + its own row | **M/region** | cross-region native-resale form (saga/escrow vs intra-region-only); carried from 2026-08-24 |
| **O7** | `C51` | **P** if (a), — if (b) | the event outbox — promised by DA §6.2/§6.3 and CDM C12, scheduled by no implementation spec |
| **O8** | `C52` | **P** per C7 / **L** per the implementation specs — *the contradiction is the row* | the `notify` schema |
| **O9** | `C56` | **P** (Wallet enable) | the `OQ-5`/`OQ-W4` Wallet relaxation — conditions specified, **owner sign-off still owed** |
| **O10** | `C72` | **P** | the second structural amendment to the package DAG, pending re-ratification |
| **O11** | `C75` | **P** | **precedence between delta specifications — there is none**; blocks the next delta-vs-delta conflict |
| **O12** | `C77` + its own row | **P** | platform-plane grant maturity — the platform money-key arm ships with no maturity floor until ruled |
| **O13** | `C85` + its own row | **P** | `org_admin` on the money plane |
| **O14** | `C90` + its own row | **P** | the payout tier operand — blocks the payout tier's implementation |
| **O15** | `C95` + its own row | **P** | account deletion for an identity holding live custody |
| **O16** | `C92` + its own row | **P** | what `kernel.payout.status='paid'` asserts |

**Ten of the eleven name Gate P** (all but `O6`), two of those ten conditionally (`O7`, `O8`). The record's
earlier "zero pending" line does not hold, is withdrawn, and is not restated.

**This document has no mechanism that fails when these numbers go stale**, which is why they were three
passes and seventy rows behind. Until one exists, **the record's own status table is the authority and this
paragraph is a convenience copy**: on any disagreement, recount from
`docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` and correct this file. Filed as `C125`.

> **Two `O` namespaces, and they are not the same series — read the hyphen.** `O1`…`O8` **unhyphenated** are the architecture **open questions** tracked in DA §0.4 and the risk register (`O3` = resale-policy snapshot drift, `O4` = per-event identity-verification strength, `O6`/`O7`/`O8` as above). `O-1`…`O-5` **hyphenated** are the **owner rulings** ratified 2026-08-27 (`O-3` = payout visibility/requests, `O-4` = door-manifest authority). `O3` ≠ `O-3` and `O4` ≠ `O-4`. Neither series is renumbered; the disambiguation is the fix (record row **D4**).

**Architecture validation:**
`docs/architecture/_superseded/PHASE_2_ARCHITECTURE_REVIEW.md` · `docs/architecture/_superseded/PHASE_2_FINAL_ARCHITECTURE_AUDIT.md` · `docs/architecture/_governance/ARCHITECTURAL_RISK_REGISTER.md` · `docs/architecture/_governance/IMPLEMENTATION_READINESS_SCORE.md` · `docs/architecture/_governance/CTO_DECISION_MEMO.md` · `docs/architecture/_superseded/PHASE_2_IMPLEMENTATION_ROADMAP.md`

**Implementation specifications (addenda A1–A5 applied and closed):**
`docs/architecture/PHASE_2_SPEC_FOUNDATION.md` · `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` · `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md` · `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` · `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` · `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` · `docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` · `docs/architecture/_superseded/PHASE_2_IMPLEMENTATION_SPEC_REVIEW.md`

**Delta specifications added after the 2026-08-24 freeze (design-only; same tier as the implementation specs in the authority order below, and covered by Rule 1 from the moment they are ratified into the record):**

*Owner-ruling deltas — the design work behind record rows O-1 … O-5:*
`docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md` (O-1, O-3) · `docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md` (O-2, O-4) · `docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md` (O-5, O-4)

*Feature deltas:*
`docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md` · `docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md` · `docs/architecture/PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` · `docs/architecture/PHASE_2_NOTIFICATIONS_SPEC.md` · `docs/architecture/PHASE_2_PROMOTER_CODES_SPEC.md`

*Surface and registry:*
`docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` · `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md` (the canonical migration-package map)

**Registers and integration layer — added to the covered set 2026-08-28 (`R4-7`; ratification rows `C126` / `D33`):**

> **These four documents existed and were NOT listed, which is precisely what left them outside Rule 1.** The
> omission was found by diffing the covered set against `docs/architecture/**/*.md`: **36 files in the tree,
> 32 named here, four missing.** They are named below with their tier, because a covered-document list that
> is silently incomplete is worse than one that is short — it reads as exhaustive.

`docs/architecture/PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` — **a register other documents cite**, therefore squarely inside Rule 1 and not merely eligible for it: RLS §2.2 cites its `C2 · O-2` row as one of the six statements of the helper set, RPC §20.14 rows `R-15`/`R-20` are addressed to it, and it carries **two ratified rows of its own (`C83`, `C84`)**. Same tier as the implementation specs. **It also has a live staleness hazard its own header states** — body baselined at `64d2aac`, reconciled forward to `cbf8926` for RLS §16.10 only — and `C84` records that it has **no mechanism that fails when its baseline goes stale**. Covering it does not fix that; it makes changing it require an amendment.
`docs/architecture/PHASE_2_SCOPE_AMENDMENT_2026_08.md` — the **INTEGRATION LAYER** for the six owner-approved Phase-2 additions (Wallet · demographics · promoter codes · CRM export · notifications · venue dashboard). It is the document that authorizes the five feature deltas already covered above, so covering the deltas and not their authorization was the gap. Same tier as the implementation specs.
`docs/architecture/_governance/PHASE_2_PREIMPLEMENTATION_CLOSEOUT.md` — **engineering governance**, and load-bearing: it carries the `071`–`075` → `076`–`091` renumbering note that Rule 4 and the migration statement below both depend on.
`docs/architecture/_governance/GUARD_RESTORATION_PATCH.md` — **engineering governance**, `STATUS: APPLIED 2026-08-26`. Covered as the record of a **CI-guard change** (`migrations-guard.yml`, the Scheme-B exception retired). **Rule 1 covers the record; it does not freeze the workflow file**, and nothing in this freeze may be read as licence to weaken that guard.

**None of the four is excluded.** The covered set is now **36 of 36** files under `docs/architecture/`, and that equality is the check to re-run whenever a document is added.

**These deltas do not themselves edit the constitutions.** Each records the constitutional edits it requires; those edits reach DA/CDM only through a ratified row in `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`, per Rule 1. Where two deltas prescribed conflicting edits to the same constitution section, the conflict is resolved and the rejected instruction named in the record (see row **D6**, DA §7.6).

**Engineering governance:**
`docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` · `docs/architecture/_governance/PHASE_2_FINAL_PREIMPLEMENTATION_GATE.md` · `docs/architecture/_governance/SNATCHIT_GITHUB_REPOSITORY_STABILIZATION_ROADMAP.md` · `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md` · Phase-0 baseline docs (`docs/architecture/PHASE_1_FOUNDATION.md`, `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md`, `docs/security/SNATCH_IT_PHASE_0_COMPLETION_REPORT.md`, `docs/security/PHASE_0_GATE2_SCHEMA_DIFF.md`, `docs/security/PHASE_0_EXECUTION.md`)

## Rules of the freeze

1. **Modifications to any covered architecture/constitution document after this point require an explicit architectural amendment** — a new correction ID ratified into `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` with owner approval — never a silent edit.
2. **Normal implementation may clarify details but may not violate invariants.** If implementation contradicts the frozen design: STOP; determine whether the implementation is wrong or an amendment is required (`docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` §0).
3. Authority order: live production reality (deployed-state questions) → this freeze + constitutions → implementation specs → `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md` → current implementation → old audits/stale branches.

   > **This order ranks TIERS, and every delta specification sits in ONE of them.** The covered-document list
   > above places the eight delta specs *"same tier as the implementation specs in the authority order below"*
   > — so **when two documents inside that tier contradict each other, this rule decides nothing**, and
   > `docs/architecture/PHASE_2_SPEC_FOUNDATION.md` §0 supplies no companion: it says *"if a source document
   > conflicts with this file, surface the conflict; **do not silently pick a side**"*, which is correct and
   > names no winner. **That gap is not hypothetical.** `PHASE_2_MONEY_AUTHORITY_SPEC.md` §6.2 and
   > `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §17.2 each carried a build-ready authority branch for the same money
   > RPC and **they contradicted each other**, with the money spec's branch keyed on two strings that are
   > stored nowhere — an implementer following it routes every parked refund to the org arm, above-ceiling and
   > consumed-atom cases included.
   >
   > **The three admissible forms** — recorded so the choice is a choice, **not decided here**: **(a) recency**
   > (the later ratified correction governs); **(b) subject-matter ownership** (a named owner per subject —
   > authority branches → RPC, predicates/grants → RLS, physical columns → schema, the money-authority model →
   > the money spec); **(c) remediation-tag precedence** (where two documents state the same rule and one
   > carries a ratified correction tag and the other carries none, the tagged text governs and the untagged is
   > presumed pre-remediation).
   >
   > **Choosing among them decides which document's authority statement binds an implementer, which is an
   > OWNER decision.** Recorded as row **`C75`**, open decision **`O11`**, in
   > `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`; **until it is made, the standing
   > obligation remains SPEC_FOUNDATION §0's — surface the conflict, do not pick a side.** The 2026-08-28
   > money-authority reconciliation (row `D14`) relied on **neither** of these forms as a general rule: it
   > read *this record*, in which one side's text is a **ratified correction** (rows `C57`/`C58`) and the
   > other's is **the text that correction replaced** — a determination available with no precedence rule at
   > all, and one that does not generalize to a conflict where neither side carries a ratified row.
4. Gates stand: **Gate P** before the first native credential · **Gate M** before native resale/instant payout · **Gate L** before international/enterprise claims. Feature flags `feature.native_issuance_enabled` / `native_scanning_enabled` / `native_resale_enabled` are seeded **OFF** and are flipped only by an audited runtime config change, never a migration.
5. Supabase automatic production deployment remains **OFF** until the migration-history repair in `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md` is executed and verified with owner authorization.
6. The frozen money core and live external-rail marketplace (`public.*`) remain protected per `docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` §1.

Implementation begins at migration `076` per `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md` (Phase-2 packages are `076`–`091`; `071`–`075` are applied production security migrations, not Phase-2 packages — canonical map in `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md`), on a `phase2/implementation` branch cut from the consolidated baseline, following the execution protocol package-by-package.

## Amendment A-2 (administrative, 2026-08-25)

PR #3 (`phase2/architecture` → `main`) was **rebase-merged**. Recorded consequences — no design change:

- The original freeze SHAs named above (`51cce52` baseline chain, closeout `dd960c4`) live on the branch
  lineage anchored by tag **`phase2-architecture-v1`**; that tag remains the anchor for those SHAs.
- `main` carries byte-identical rebased equivalents of the frozen content: `cf7d6b9` (E-1 consistency
  closure), `e24989c` (Amendment A-1), `f66bf1d` (pre-implementation closeout).
- The frozen documents were relocated to `docs/architecture/` (governance set under `_governance/`,
  superseded reviews under `_superseded/`) by the repository-hygiene PR, which also rewrote this
  document's path references accordingly. Nothing else changed.

Recorded as row **A-2** in `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`.

## Maintenance note (2026-08-27) — this is not a new freeze

Three statements in this document had become **false** and are corrected above. Nothing else changed: the rules
are untouched, the baseline commit is untouched, no new freeze is declared, and **no new freeze record is
written here** — that is a separate, later act gated on a readiness verdict.

1. **The record-row inventory was stale** — "C26–C50 + D1–D3 + O6 = 29, zero pending". It was corrected to
   **44 rows / three open decisions (O6, O7, O8)** on 2026-08-27, and **that correction is itself now
   superseded**: see the recount above (**114 rows · 15 `OPEN-GATED` · eleven decisions `O6`–`O16`**, each
   with its enumeration). "Zero pending" is withdrawn and not restated. **This is the third time this
   paragraph has gone stale, which is the argument for the recount-from-the-record rule stated above.**
2. **The covered-document list predated the delta specs.** Eight design-only delta specifications (three
   owner-ruling, five feature) plus the venue dashboard product spec and the package registry now exist and are
   listed. Adding them to the covered set is what puts them under Rule 1. **Amended 2026-08-28 (`R4-7`,
   row `C126`): that pass still omitted four files** — the traceability matrix, the scope amendment, the
   pre-implementation closeout and the guard-restoration patch — **and the traceability matrix is a register
   other documents cite, so it was outside Rule 1 while being treated as authority.** All four are now
   listed; coverage is 36 of 36.
3. **The `O` namespace was ambiguous.** This document previously said "O2/O3/O4 tracked as open questions in DA
   §0.4" beside owner rulings numbered `O-2`/`O-3`/`O-4`. Both readings are legitimate and neither series is
   renumbered; the sentence is replaced by an explicit note (record row **D4**).

**Checked and already correct, therefore not changed:** the migration statement above already reads *implementation
begins at `076`; `071`–`075` are applied production security migrations, not Phase-2 packages*. It needed no fix
at this baseline.

Corrections applied under record rows **D4**, **D5** and **D6**, and under the owner rulings **O-1 … O-5**, in
`docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`.
