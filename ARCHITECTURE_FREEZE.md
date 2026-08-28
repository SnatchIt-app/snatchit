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

Record contents, current as of 2026-08-27: **44 rows** — C26–C52 + D1–D8 + E-1 + OBS-1 + A-2 + O6 + the five owner rulings O-1 … O-5. C1–C25 are prior-ratified inside the constitutions themselves. **Three open decisions block a gate: O6** (cross-region native-resale form, carried from 2026-08-24), **O7** (the event outbox — promised by DA §6.2/§6.3 and CDM C12, scheduled by no implementation spec; row C51) and **O8** (the `notify` schema — Gate-P/MVP under C7, do-not-build in all four implementation specs; row C52). The record's earlier "zero pending" line no longer holds and has been withdrawn.

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

1. **The record-row inventory was stale** — "C26–C50 + D1–D3 + O6 = 29, zero pending". The record now carries
   **44 rows** and **three open decisions (O6, O7, O8)**; "zero pending" is withdrawn rather than restated.
2. **The covered-document list predated the delta specs.** Eight design-only delta specifications (three
   owner-ruling, five feature) plus the venue dashboard product spec and the package registry now exist and are
   listed. Adding them to the covered set is what puts them under Rule 1.
3. **The `O` namespace was ambiguous.** This document previously said "O2/O3/O4 tracked as open questions in DA
   §0.4" beside owner rulings numbered `O-2`/`O-3`/`O-4`. Both readings are legitimate and neither series is
   renumbered; the sentence is replaced by an explicit note (record row **D4**).

**Checked and already correct, therefore not changed:** the migration statement above already reads *implementation
begins at `076`; `071`–`075` are applied production security migrations, not Phase-2 packages*. It needed no fix
at this baseline.

Corrections applied under record rows **D4**, **D5** and **D6**, and under the owner rulings **O-1 … O-5**, in
`docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`.
