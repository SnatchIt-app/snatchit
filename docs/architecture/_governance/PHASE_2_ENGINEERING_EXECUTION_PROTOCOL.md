# Snatch It — Phase 2 Engineering Execution Protocol

**The standing workflow for EVERY Phase-2 implementation task, from migration `071` onward.** This protocol is binding on Claude (and any engineer) executing Phase-2 packages. It operationalizes the ECC operating model with specialist subagents and independent review. Deviation requires an explicit, recorded owner decision.

**Skill-name note (installed reality).** The environment's installed skills differ from the generic ECC category names; the mapping used by this protocol (record actual names in each session report): planning/orchestration → `anthropic-skills:ecc-harness`, `anthropic-skills:dispatching-parallel-agents`, `anthropic-skills:make-plan`/`writing-plans`/`executing-plans`; code review → `anthropic-skills:deep-code-review`, `/code-review`; security → `anthropic-skills:security-audit`, `security-review`, `anthropic-skills:ecc-harness` (security agents); debugging → `anthropic-skills:systematic-debugging`; TDD → `anthropic-skills:test-driven-development`; verification → `anthropic-skills:verification-before-completion`; git → `anthropic-skills:using-git-worktrees`, `finishing-a-development-branch`. Where a named ECC skill (e.g. `postgres-patterns`, `database-reviewer`) has no installed counterpart, a specialist **subagent prompt** carrying that mandate substitutes for it. Subagent types: `general-purpose`, `Explore` (read-only), `Plan`.

---

## 0. Source-of-truth authority order (binding)

1. **Live production reality** (when assessing deployed state)
2. **`ARCHITECTURE_FREEZE.md` + the frozen constitutions** (`docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md`, `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md`)
3. **The final Phase-2 implementation specifications** (schema / migration / RLS / RPC / edge / RN + spec review)
4. **`docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md`**
5. Current implementation
6. Old audits / stale branches

**If implementation contradicts the frozen design: STOP.** Do not silently "fix" the architecture to match code. Determine whether (A) the implementation is wrong → fix the code, or (B) an explicit amendment is required → propose it through the ratification process (a new correction ID, recorded in `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`), with owner approval.

## 1. Protected infrastructure (never reopened casually)

The external marketplace; the Stripe money-in path (`public.payments` + signed/leased webhook); integer-cents math; deterministic Stripe idempotency; webhook leases/replay protection; seller payout recovery; the external-rail transfer engine; Phase-0 RLS hardening (041/052/062/066/067/068 discipline); production migration reproducibility (Gate-2). Phase 2 is additive; `public.*` stays frozen except explicitly-ratified additive links (e.g. `kernel.payment_native.payment_id`).

**Standing flags/config that stay OFF until their gate:** `feature.native_issuance_enabled` (Gate P / 15.A) · `feature.native_scanning_enabled` (2B door gate) · `feature.native_resale_enabled` (Gate M + 2C). Flags are runtime config: a migration may seed them OFF; **a migration must never flip them ON**. Supabase automatic production deploy remains **OFF** until migration-history repair is completed and verified (see `PHASE_2_MIGRATION_HISTORY_RECONCILIATION.md`).

## 2. The 12-step package loop (every package/task)

1. **Read** — `ARCHITECTURE_FREEZE.md`; the constitution sections and implementation-spec sections relevant to the package; every prior migration in the chain; the migration plan entry for this package.
2. **Plan** — planner pass (Plan agent / make-plan) + the domain-lead subagent for the task type (§3). Output: object list, dependency check against the plan's DAG, definition-of-done.
3. **Threat / invariant analysis** — state explicitly: invariants touched; tables touched; SSCAS member (if any) + lock order; RLS impact; money impact; custody impact; rollback plan. A package touching money/custody/authz without this section does not proceed.
4. **Tests first** — TDD where applicable: pgTAP/SQL harness tests for DB behavior (constraints, RLS allow/deny pairs, state machines, idempotency replays), unit/integration for edge/app code, adversarial RLS probes (each deny cell of the matrix that the package creates).
5. **Implement the smallest package** — one migration package / one coherent change. No unrelated cleanup, no opportunistic refactors.
6. **Specialist review** — minimum: database-reviewer mandate for DB work; security-reviewer mandate for authz/RLS/SECURITY DEFINER; typescript-reviewer for TS; RN reviewer for UI; deployment review for env/deploy changes. Reviewers are subagents that did NOT author the change.
7. **Verification loop** — as relevant: lint, types, unit, integration, **fresh-DB replay of the full migration chain (the CI `db` job / Gate-2 bootstrap)**, RLS tests, security scan, targeted E2E. A package is not done while any gate is red.
8. **Independent adversarial review** — a read-only agent that did not author the change attempts to reject it (contradiction with the freeze, invariant breach, silent scope creep, flag/deploy violations).
9. **Staging** — apply to the isolated staging environment first; run the package's staging-verification checklist from the migration plan.
10. **Production gate** — no production apply without: staging PASS, migration verification, rollback/recovery plan in hand, and **explicit owner/human approval for anything touching money, custody, auth, or RLS**.
11. **Documentation** — update the migration tracker/package status, architecture traceability (which spec sections the package realizes), and known risks.
12. **Stop at the package boundary.** Never opportunistically start the next package in the same change.

## 3. Task-type → lead + reviewers (subagent mandates)

| Task type | Lead mandate | Mandatory reviewers (non-authors) |
|---|---|---|
| Database / migrations | PostgreSQL/Supabase Architect | Security · Database · Reproduction/CI Verifier · Adversarial Staff Engineer |
| RLS / authorization | Security/Authorization Engineer | Database Architect · Adversarial Security |
| RPC / SECURITY DEFINER | Backend/Postgres Engineer | Security · Database · Distributed-Systems (if SSCAS member) |
| Edge / Stripe / KMS | Backend Integration Engineer | Payments · Security · TypeScript |
| React Native | RN Product Engineer | TypeScript · Security (auth/token/credential surfaces) · E2E |
| Payments | Payments Engineer | Database · Security · Adversarial Money Reviewer |
| Ticket ownership / transfer | Ticketing Systems Engineer | Distributed Systems · Database · Security |
| Scanning / offline | Ticketing + Mobile Engineer | Distributed Systems · Security · E2E |
| CI / deployment | DevSecOps Engineer | Security · Database (if migrations affected) |

Concurrency rule: read-only analysis may parallelize; agents editing overlapping files may not run concurrently; one integrator owns final edits/merges; every major change gets an independent reviewer who did not author it.

## 4. Standing verification gates

- **Gate-2 reproducibility:** every package must leave the chain `000 → … → latest` fresh-replayable (CI `db` job green). No out-of-band objects — anything created in production must exist in the chain.
- **Migration discipline:** zero-padded `NNN_` version prefixes continuing from the current max; expand → verify → adopt → contract; additive-only in Phase 2; rollback file per package (in `supabase/rollbacks/`).
- **RLS discipline:** deny-by-default; adversarial probe per new deny cell; no client write path to money/custody; live-table rechecks for money-consequential authority.
- **Money discipline:** no production money mutation without Stripe evidence; deterministic idempotency; never mark succeeded without verification; payout/refund via existing recovery-capable writers.
- **Gates P/M/L:** package work that would realize gated behavior ships dark (flag OFF, or object inert) until the gate is cleared and recorded.

## 5. Session reporting

Every implementation session ends with: package(s) completed; gates run + results; reviewers used (actual installed skills/agents recorded); deviations (should be none); next package; explicit blockers.
