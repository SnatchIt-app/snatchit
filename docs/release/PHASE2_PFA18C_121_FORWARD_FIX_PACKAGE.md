# PFA-18C — MIGRATION 121 (DEFENSIVE HARDENING OF `venue.get_manifest_signing_context`) — REVIEW PACKAGE rev 2 (NOT APPLIED · C5 PAUSED · C6 REVIEW-ONLY)

**Date:** 2026-09-10 (rev 2 — rationale corrected per Claude A's review of PR #58; implementation unchanged) · **Coordinator:** Claude B.
**Owner instruction (rev 1):** prepare the 114 L121 forward fix on an isolated branch, no apply anywhere. **Owner instruction (rev 2):** correct the rationale in the migration header, PR description, this package and the C6 prerequisite wording; keep the implementation scoped to 121; no production apply, merge, deployment, or sibling implementation; coordinate integration with Claude A after Build 16's handset matrix closes.
**State:** nothing applied anywhere; production ledger 135 / tip 120; production function md5 `b14d938eab69c94768578daf8b6d1c4f` (the 114 body). C5 paused after C5-1; C6 review-only.

## 1. What 121 is (corrected): defensive hardening, not a demonstrated defect

`venue.get_manifest_signing_context()` (114) counts the active global rows, returns the stable `unavailable` codes when the count is 0 or > 1, then re-reads the row with a non-STRICT `select * into v_k`. Rev 1 of this package claimed a concurrent-revoke race between the count and the read. **That claim was wrong and is withdrawn (dated 2026-09-10):** the function is **STABLE**, and every statement inside a STABLE PL/pgSQL function reads the **calling query's snapshot**, so a status flip committing between the two statements is not visible to the second read. The race is **not reachable in the current function**.

**Supporting evidence.**
- **Claude A's review of PR #58 (2026-09-10, relayed by the owner):** concurrent STABLE/VOLATILE experiment demonstrating that the STABLE function's reads share one snapshot; A found no deployment blocker in the sibling `kernel.get_ticket_signing_context`, which already fails closed through its explicit null guard; A separately verified ordering and immutability locally.
- **Claude B's local reproduction (REHEARSAL, local replica `snatchit_rehears_121`, 2026-09-10T23:53Z):** two throwaway copies of the 114 body with a 3-second pause between the count and the row read, one STABLE and one VOLATILE; a concurrent session flipped the only active global row to `rotating` during the pause. Result: **STABLE → `{status:ok, key_id:…b0, kms_handle_ref:…}`** (the original row; the flip was invisible); **VOLATILE → `{status:ok, key_id:null, kms_handle_ref:null}`** (the ok-of-NULLs shape). Throwaway schema dropped; rows cleaned.

**Why harden anyway.** The 114 body expresses "exactly one row" only through the pre-check count; the correctness of the non-STRICT read depends on the STABLE snapshot property surviving future edits (a body-only re-create marked VOLATILE, or a read moved into a separate query, would silently reintroduce an ok-of-NULLs path). 121 makes the read `STRICT` and maps `no_data_found` / `too_many_rows` to the stable `unavailable` codes, stating the invariant in the code so it holds by construction regardless of volatility. **No observable result of the current function changes** (suite 180 unchanged; suite 189 pins the contract).

**Effect on the dark deployment (C6).** None required for correctness today; the door-manifest edge already receives the stable codes, and in the non-reachable NULL case the E2 signer would fail closed. 121 is **recommended before C6 as hardening, not a blocker** (C6 package P2 re-worded accordingly).

## 2. Implementation (unchanged from rev 1; isolated branch; applied migration 114 untouched)

| Item | Value |
|---|---|
| Branch | `fix/121-manifest-signing-context-strict`, cut from `origin/admin/operating-console @ 562fda9` (carries 110–120) |
| Commits | rev 1 `29ad7f87ea11ed212eac32be7209bee515d6b01e` (implementation) · **rev 2 `030a922bc054501f28f8baef4d7710ef6a374868`** (rationale corrected in the header, the in-body `-- 121:` comment and the function comment; logic unchanged; definition md5 now `333372bbbe7dd8fe1a95db4de66ea4c6` — rev 1 was `c321ad7e516ac91b57fb884013180061`) · draft PR **#58** into `admin/operating-console` (review-only; not for apply) |
| Migration | `supabase/migrations/121_get_manifest_signing_context_strict.sql` — body-only `create or replace`: `select * into strict v_k …` in a nested block; `no_data_found` → `{unavailable, no_active_global_key}`, `too_many_rows` → `{unavailable, ambiguous_active_global_key}`; signature, STABLE, SECURITY DEFINER, `search_path=''`, pre-checks, window/algorithm checks, ok payload, grants (service_role only) unchanged; comment extended by one sentence. **Census 0.** |
| Rollback | `supabase/rollbacks/121_…_rollback.sql` — restores the 114 body verbatim; md5 round-trip verified (`b14d938e…` = production) |
| Test | `supabase/tests/189_get_manifest_signing_context_strict.sql` — 19 assertions (definition; grants/shape; 0-row / 1-row / status-flip contract; census). Header corrected: no race is claimed. |

## 3. Numbering coordination (Claude A)
Reserved **migration 121**, **rollback 121**, **test 189** (187 taken on `release/convergence-135`, 188 on `venue/read-adapters-slice-1`; no branch carries `121_`/`122_`). Direct session messaging was unavailable from this session; the reservation is recorded here and in the PR body. **Integration gate (owner):** coordinate with Claude A **after Build 16's handset matrix closes**; the combined release + venue + 121 chain is **142 migrations** (A's count).

## 4. Local rehearsal (REHEARSAL; production untouched)
Replica from the fix branch: 136 migrations, GATE-2 census = CI baseline (27/71/37/27). Post-121: `strict=true`, md5 `c321ad7e…`; kernel fns 153 / venue fns 87 / kernel tables 32 / signing_key triggers 3 — identical to pre-121 and to production. pgTAP **176 + 180 + 189 = 112/112 ALL-PASS**. Rollback round-trip: `b14d938e…` → `c321ad7e…`; suite 189 PASS again. Rev 2 re-applied locally: md5 `333372bb…` (comment text inside the body/function comment changed; logic identical), suites 180 + 189 = 61/61 ALL-PASS, rollback round-trip `b14d938e…` verified again.

## 5. CI on PR #58 (CLAUDE-OBSERVED) — read precisely
- **PASS:** Migrations apply cleanly (fresh DB); Typecheck/Lint/Unit; Deno type-check; Admin console build; Web build.
- **FAIL (by design): "Immutability + ordering"** — the job **stopped at the missing AUTODEPLOY-1 attestation** (`AUTODEPLOY-VERIFIED-OFF: <date>` in the PR body) **before** its later immutability/ordering checks ran; it is therefore **not evidence** about ordering or immutability either way. Those properties were verified separately: **Claude A locally**, and **Claude B** by `git diff --name-status 562fda9..29ad7f87 -- supabase/migrations supabase/rollbacks supabase/tests` = three **additions** only (no existing file modified) and `121 > 120` (highest 3-digit migration at the base). The attestation is added only on the day of apply.

## 6. Rollback considerations (unchanged)
Body-only, reversible in seconds; production forward-only ⇒ rollback needs its own authorization; rolling back merely restores the non-STRICT read (safe in the current STABLE function). Any later migration re-creating this function must be rolled back first (none exists).

## 7. Integration dependencies and apply path (not authorized)
1. Owner review of PR #58; integration sequencing with Claude A after Build 16's handset matrix closes (combined chain 142).
2. Apply only under **`AUTHORIZE PFA-18C MIGRATION 121`** with the C4 discipline (dry run lists exactly `121_…`; `git_branch ""`; ledger 135 → 136, tip 121; read-backs: md5 `333372bb…` (rev 2), `strict=true`, grants service_role-only, census unchanged, context `ok`/`…b0`; CI suites 180/189 green).
3. Recommended before C6 (hardening); no interaction with C5 or AWS; no edge change needed.
4. Sibling `kernel.get_ticket_signing_context`: **no deployment blocker** (explicit null guard, Claude A); no sibling implementation in this task.

## 8. Dated corrections
- 2026-09-10 rev 1 → rev 2: "demonstrated production defect / concurrent-revoke race" → **not reachable (STABLE snapshot)**; 121 re-described as defensive hardening. The C4 package's §5.2b D1 note (2026-09-09) predates this finding and stands as historical text; this package and the execution record carry the correction.
- CI reading corrected: the ordering job's red status is the attestation gate, not a failed ordering/immutability check.
