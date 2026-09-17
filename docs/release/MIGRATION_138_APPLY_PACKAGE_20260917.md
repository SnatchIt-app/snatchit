# Migration 138 — apply package (A, 2026-09-17)

**NOTHING HERE IS AUTHORIZED.** The owner ruled, 2026-09-17: *"Keep migration 138 unapplied and outside the marketplace candidate. A may finish the review and prepare the apply package, but applying 138 still requires a separate authorization, including the prerequisite 115–120 sandbox chain and any hosted-project detection read."* This document is the request; each numbered approval point in §8 needs the owner's word before anything runs.

## 1. What would be applied

| Item | Value |
|---|---|
| Migration | `supabase/migrations/138_ops_operator_onboarding.sql` @ `ops/138-operator-onboarding a9aa34e` · sha256 `2e9a1aaf7fcf4782d4cb178f7bc6a6581045f73974ff1f5211d931a6d7829f42` |
| Rollback | `supabase/rollbacks/138_ops_operator_onboarding_rollback.sql` · sha256 `7755e1c8d1364d544aab5bbdde44bd965a246e6844181930d8119ec6a0785ab5` |
| Concurrency proof (not applied; evidence only) | `scripts/rehearsal_138_a6_concurrency.sh` · sha256 `82275595f82e423f1e9cd1dae506e0aef8bc022d345fa339a69de32d4c29f48e` |
| Governance | **PFA-33 SIGNED** (governance `99ecf31`, block md5 `2da381a1…`); **PFA-34 PROPOSED, NOT SIGNED** (governance `b7895bb`, placed block md5 `026cb858319bc7c0181e1dad01e23ef1`, 2726 bytes, 27 lines) |
| Contents | A1–A3 bootstrap verbs, A4 acceptance refusal, **A5** direct-creation refusal, **R1** recovery owner invite, **A6** no invitation overwrites or demotes an owner, **D1** `ops.list_platform_identity_memberships()`, `ops.action_invitee` and its two triggers, the console action types and their revokes |
| One transaction | Yes. The migration's own sanity block aborts it whole, so a failure leaves nothing applied. |

## 2. Evidence carried

- **CI 35257712408 at `a9aa34e`:** five jobs success; pgTAP `Files=88, Tests=5441, Result: PASS`.
- **A's independent replay at `a9aa34e`** (local, not D's): 157/157 migrations, Gate-2 `32|107|37|38`, 87 files `5435/5435`, plus a strict TAP::Parser pass with 0 failures and 0 parse errors on every file.
- **A's source checks:** `kernel.create_organization` and `kernel.accept_org_invite` are 077's bodies plus only the marked A4/A5/A6 blocks; the rollback's two bodies are byte-identical to 077's; the migration and rollback are byte-identical to the already-reviewed `5960b51`.
- **A's mutants**, each asserted to apply, change the live digest and restore to baseline, with kill sets predicted in advance: `MA5-off`, `MA6-off`, `MA6-any-owner-accept`, `MD-email`, `MD-no-admin-users`, `MD-no-assert`, `MD-support-allowed`, `MRec-no-org-status`. The over-broad A6 mutant is killed by I134/I135/I135b/I136 (A's F-A6-TEST, now closed). `MA6-off` and `MA6-any-owner-accept` fail *differently*, which is what makes the pair discriminating.
- **A's own run of the two-session proof** on a loopback replay: S1 (the lower-role acceptance blocks on the organisation row, shown by `pg_blocking_pids`, then is refused), S2 (a legitimate owner acceptance blocks, then succeeds), S3 (both racing lower-role acceptances refused), **C1 (without A6 both commit and the organisation is left with ZERO owners)**, C2 (the rollback RED: after rollback the identical call succeeds and owners drop to 0). ALL PASS.

## 3. Prerequisites, per target

- 077, 078, 080 (kernel, catalog, venue) and 115 and 118 (ops) must be applied.
- **Production:** the release package records 115–120 applied 2026-09-08.
- **Sandbox `ofaidukbieeekqaboscm`: there is no `ops` schema** (A and D both read this). A sandbox apply of 138 needs 115–120 there first, which is a separate authorization and has consequences — see §7.

## 4. Pre-apply reads (each is a read the owner authorizes for that project)

- **(a) Ledger:** 077, 078, 080, 115 and 118 present; 138 absent.
- **(b) The seven objects 138 redefines** — `md5(prosrc)` and ACL. Expected `md5(prosrc)`, which **A recomputed from the migration text independently of any replay**, all seven matching D's values:

| Object | md5(prosrc) |
|---|---|
| `ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)` | `67cd21460e02fb5e53aa0e01e9858a03` |
| `ops.action_dispatch(ops.action)` | `b37e66a70168c79b5eed9dccaf0d1917` |
| `ops.action_precheck(ops.action)` | `00e2e682a7ce88db32c9268dd264d066` |
| `ops.action_allowed_roles(text)` | `98d8aba103710706fd8fb6d4081a0a1c` |
| `ops.action_requires_approval(text)` | `57174426627268e60df6bae330f58b8a` |
| `kernel.accept_org_invite(uuid,text)` | `a7bd098425f1ca041f402449bba4e1a9` |
| `kernel.create_organization(text,text,text)` | `11a046a68ef5f48e0b6d0ab62f2a6d7d` |

  - **A md5 mismatch is a HARD STOP.** The rollback restores the repo's body, so applying over something else would overwrite an unknown change.
  - **An ACL difference is report-and-decide, not an automatic stop** (A's F-ACL-REPLAY): the expectations come from a replay that runs as superuser with parity grants, and a hosted project can legitimately differ. The expectation is to be taken from a real Supabase stack (`supabase start`, CLI 2.115.0) rather than from any hosted read.
- **(c) The names-only detection query, run BEFORE the apply.** A4 and A5 stop *new* memberships; they remove none that already exist. Its text is D1's body without the role gate, it returns names only, and running it against any hosted project is its own owner-authorized read (PFA-34 D1; the owner deferred nothing else here).
- **(d) A census** of ops/kernel/catalog function counts and the ops table count, for the post-apply delta.

## 5. Apply procedure

- **Never by merging to `main`** (AUTODEPLOY-1): merging applies pending migrations to production outside CI with no approval gate. 138 goes through the owner-gated path in `docs/operations/DEPLOYMENT_PATHS.md`.
- One transaction, applied from a clean detached tree at `a9aa34e`, with the pre-apply reads immediately before it, A executing and D witnessing, exactly as W-C3 ran.

## 6. Post-apply verification

- Deltas: ops functions **+13**, kernel **+2**, catalog **+1**, ops tables **+1**, triggers **+2**. Public census unchanged.
- `kernel.bootstrap_organization`, `kernel.invite_bootstrap_owner`, `catalog.bootstrap_venue`, `ops.identity_holds_platform_authority` and `ops.action_invitee_release_on_terminal`: executable by none of public, anon, authenticated, service_role.
- `create_organization` and `accept_org_invite` ACLs unchanged; `ops.list_platform_identity_memberships` executable by `authenticated` only.
- Rollback restores code, not data, and refuses rather than narrowing the CHECK constraints if rows with a 138 action type exist.

## 7. Blast radius, and what the sandbox option costs

- Operators can no longer create organisations directly or accept customer invitations; an owner can no longer be demoted by accepting an invitation. Onboarding console actions become available, all platform_admin, with two people required for an invite.
- No public-schema change, no data migration, no notification, no job — **from 138 itself**.
- **But the sandbox prerequisite is not neutral.** Applying 115–120 to the sandbox would:
  - start `ops-detect-tick` every 5 minutes and `ops-daily-summary` daily (migration 117), which open ops cases from existing sandbox data while the handset sprint is running;
  - add 119's listing-block guard, changing the sandbox's known census deltas that W-C3 and the Line 3 baseline are reconciled against.
- **A's recommendation:** treat CI plus A's independent replay, mutants and two-session proof as the rehearsal, and do **not** apply 115–120 to the sandbox during the marketplace sprint. If the owner wants a hosted rehearsal, do it after the sprint closes, as its own window.

## 8. Owner approval points (each separate; none is given)

1. Sign **PFA-34** (governance `b7895bb`, placed block md5 `026cb858319bc7c0181e1dad01e23ef1`). Signing does not apply anything.
2. The pre-apply reads, per project.
3. The pre-apply detection read, per project (PFA-34 D1).
4. The sandbox prerequisite chain 115–120, **if** a hosted rehearsal is wanted — with §7's consequences.
5. The production apply of 138, with its pre-apply reads and D witnessing.
6. Open, not decided: whether D1 should also report venue staff. The owner's ruling said organisation membership, and that is what is built; venue-plane membership at a customer venue is reachable by the same reverse path, so it is the owner's call whether to extend it later.
