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
`docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` · `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` · `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` (record rows: C26–C50 + D1–D3 + O6 = 29, zero pending; C1–C25 prior-ratified in the constitutions; O2/O3/O4 tracked as open questions in DA §0.4)

**Architecture validation:**
`docs/architecture/_superseded/PHASE_2_ARCHITECTURE_REVIEW.md` · `docs/architecture/_superseded/PHASE_2_FINAL_ARCHITECTURE_AUDIT.md` · `docs/architecture/_governance/ARCHITECTURAL_RISK_REGISTER.md` · `docs/architecture/_governance/IMPLEMENTATION_READINESS_SCORE.md` · `docs/architecture/_governance/CTO_DECISION_MEMO.md` · `docs/architecture/_superseded/PHASE_2_IMPLEMENTATION_ROADMAP.md`

**Implementation specifications (addenda A1–A5 applied and closed):**
`docs/architecture/PHASE_2_SPEC_FOUNDATION.md` · `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` · `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md` · `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` · `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` · `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` · `docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` · `docs/architecture/_superseded/PHASE_2_IMPLEMENTATION_SPEC_REVIEW.md`

**Engineering governance:**
`docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` · `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md` · Phase-0 baseline docs (`docs/architecture/PHASE_1_FOUNDATION.md`, `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md`, `docs/security/SNATCH_IT_PHASE_0_COMPLETION_REPORT.md`, `docs/security/PHASE_0_GATE2_SCHEMA_DIFF.md`, `docs/security/PHASE_0_EXECUTION.md`)

## Rules of the freeze

1. **Modifications to any covered architecture/constitution document after this point require an explicit architectural amendment** — a new correction ID ratified into `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` with owner approval — never a silent edit.
2. **Normal implementation may clarify details but may not violate invariants.** If implementation contradicts the frozen design: STOP; determine whether the implementation is wrong or an amendment is required (`docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` §0).
3. Authority order: live production reality (deployed-state questions) → this freeze + constitutions → implementation specs → `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md` → current implementation → old audits/stale branches.
4. Gates stand: **Gate P** before the first native credential · **Gate M** before native resale/instant payout · **Gate L** before international/enterprise claims. Feature flags `feature.native_issuance_enabled` / `native_scanning_enabled` / `native_resale_enabled` are seeded **OFF** and are flipped only by an audited runtime config change, never a migration.
5. Supabase automatic production deployment remains **OFF** until the migration-history repair in `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md` is executed and verified with owner authorization.
6. The frozen money core and live external-rail marketplace (`public.*`) remain protected per `docs/architecture/_governance/PHASE_2_ENGINEERING_EXECUTION_PROTOCOL.md` §1.

Implementation begins at migration `071` per `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md`, on a `phase2/implementation` branch cut from the consolidated baseline, following the execution protocol package-by-package.
