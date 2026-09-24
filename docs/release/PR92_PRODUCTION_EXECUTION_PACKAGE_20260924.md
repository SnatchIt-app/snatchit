# PR #92 — production execution package: migration 148 + `enforce-transfer-expiry` (A, 2026-09-24)

**Status: PREPARED, NOT EXECUTED, NOT AUTHORISED.** Nothing here has touched production. The owner's message of
2026-09-24 authorised preparing this package, and explicitly not production execution or dispute resolution. D reviews
it independently before it goes to the owner. The frozen artefacts are in A's scratchpad at `apply_148/`; §9 lists
their hashes.

## 1. Identity (verified 2026-09-24)

| Item | Value | How verified |
|---|---|---|
| PR | [#92](https://github.com/SnatchIt-app/snatchit/pull/92), draft, "DO NOT MERGE — fix(disputes): seller-win payout eligibility and truthful seller notice (148)" | `gh pr view 92` |
| Head | `e73553d26636ca2faa6ec846eba0dc19ee31a538` | `gh pr view` `headRefOid`; the frozen worktree `pr92_head` is at this sha and clean |
| Base | `release/production-gate-20260918` at `aadf996e298c6733b4b23af4fcbf0efea1f8f6af` (the #91/147 merge); an ancestor of the head; `mergeStateStatus` CLEAN | `git merge-base --is-ancestor` |
| CI at head | 9 checks pass: Admin console, Deno type-check, Immutability + ordering, Migrations apply cleanly (fresh DB), Typecheck/Lint/Unit, Web build, Vercel web, Vercel comments. Supabase Preview skipping. pgTAP at `e2205bbb`: Files=95, Tests=5517, PASS | `gh pr checks 92` |
| Migration | `supabase/migrations/20260924000000_seller_win_dispute_payout_and_notice.sql`: blob `2b6e54d7…`, 13,567 B, md5 `4eb38855e9eb2dcbbdb45a13b50beeff`, sha256 `f9f45ae4aeaf86f843cb41da0db362188f6d073a89fff689ee291c375fe99a2d` | `git show` at the head; frozen copy `cmp`-equal |
| Rollback | `supabase/rollbacks/20260924000000_…_rollback.sql`: blob `584af1b8…`, sha256 `8c5e34c403f964261064cf12f162a329db3f4606adba46bbec1f1c33cc3abaeb` | same |
| Diff vs the gate | 8 files: the migration, the rollback, pgTAP 215, 2 test files, 1 fixture, `_shared/payouts.ts` (+2), `enforce-transfer-expiry/index.ts` (+49). No import line changed | `git diff --stat aadf996e..e73553d2` |
| Reviews | D: 18 pass, with 2 "could not determine" (the mutant outcomes and P1 end to end). D has since reproduced both independently in an owner-authorised machine window: edge mutants 12/12 and SQL 12/12 against the pre-registered `predictions.json` (sha256 `dba54f11…`), an unmutated baseline 43/43, and Q5 (the genuine-confirmation control) failing exactly [28,29] | D's report, 2026-09-24 |

## 2. What changes in production

**Database, one request (migration text + ledger row, implicit single transaction):**
- `public.claim_payout_attempt(uuid,text,interval)` and `public.notify_transfer_state_inbox()` are redefined by
  `CREATE OR REPLACE`. The bodies are verbatim plus the additions. There is no table DDL, no grant statement and no
  top-level DML; the only INSERT/UPDATE lines are inside the claim body, as a static check of the file shows.
  `CREATE OR REPLACE` keeps the ACL, and the local ACL is identical before and after.
- One ledger row is added: `20260924000000 | seller_win_dispute_payout_and_notice | created_by=claude-a/owner-authorised-148`.
  The ledger goes from 160 to 161.

**Edge:** `enforce-transfer-expiry` goes from v40 to v41. Its bundle is the gate's plus exactly two hunks: Phase 2b (d)
in `index.ts`, and `_shared/payouts.ts` gaining `PAYOUT_HELD` and `PAYOUT_UNDER_REVIEW` in
`PAYOUT_NOT_ELIGIBLE_REASONS`. The import closure is unchanged (5 shared files).

**Deliberately NOT deployed: `confirm-and-release`, which stays at v37.** It bundles the same `_shared/payouts.ts`.
With the new file, the two new refusal codes would classify as `not_eligible` and reach `payoutDeferred`
(`confirm-and-release/index.ts:345-376`). For a seller-win row, that inserts a `payout_decisions` row asserting
`buyer_confirmed true`, `reason_codes ['BUYER_CONFIRMED', <code>]`, `dispute_open false` and `risk_tier 'low'`, all
hard-coded. That is an operator-facing record saying the buyer confirmed on a transfer the buyer disputed and lost:
the same root cause as the false seller notice, in a different table for a different audience. D traced both
branches and put it this way: deploying it "would fix a notification that lies to the seller while adding a decision
row that lies to the operator". This is finding **F-CR-148-SHARED**. `payoutDeferred` must be fixed before any future
`confirm-and-release` deploy from a tree that contains #92, including the gate once #92 merges into it.

## 3. Expected effects

| # | Effect | Evidence |
|---|---|---|
| E-1 | **At apply: no row changes, and nothing becomes payable.** The preflight requires 0 transfers in the seller-win shape (`status 'buyer_confirmed'`, `buyer_confirmed_at` NULL, `dispute_resolution 'resolved_seller_paid'`); D's reads show `dispute_resolutions` 0 rows and 5 open disputes | static file check; preflight |
| E-2 | `claim_payout_attempt`: **for seller-win rows only**, it refuses `PAYOUT_UNDER_REVIEW` under manual review, and `PAYOUT_HELD` under a future hold or `held` with no end. Genuine buyer confirmations are unchanged | pgTAP 215 P-block; Q1–Q6, Q5 control |
| E-3 | Trigger: the "Buyer confirmed receipt" notice fires only when `buyer_confirmed_at` is set. A seller-win resolution enqueues one in-app row: `dispute_resolved_seller`, "Dispute resolved in your favour", "The dispute on <title> was resolved in your favour.", dedupe `dispute_resolved:<id>:seller`. The notice says nothing about payout | 215 N-block; Q7–Q11 |
| E-4 | Edge (d): each run selects up to 20 seller-win rows that meet all of these: resolved more than 15 min ago, payment succeeded, no Stripe transfer, not released, not disputed, not under manual review. It skips held rows and pays through the same attempt executor as (b). **With 0 such rows, (d) is a no-op** | vitest SW-*; edge mutants E1–E12 |
| E-5 | **The first real effect is an operator's first seller-win resolution of one of the 5 open disputes.** The seller's in-app notice is written at once. About 15 min later the sweep pays, if there is no hold, the payment is live and succeeded, and the seller is onboarded. This is likely to be **the first production run of the attempt-based payout executor** (checklist E5), unless a genuine buyer confirmation comes first | source |
| E-6 | **Expected log noise, by design, until F-CR-148-SHARED is fixed and `confirm-and-release` redeployed.** v37 is unchanged. If a buyer calls it on a held or manual-review seller-win row, the claim refuses with `PAYOUT_HELD` / `PAYOUT_UNDER_REVIEW`. v37's `rpcReason` does not know the code, so the outcome is `db_error` at stage `claim`. The function logs `confirm-and-release: payout attempt DB error: {stage: 'claim', …PAYOUT_HELD…}` (`console.error` only, no Sentry capture) and returns 200 `payout_status 'processing'`. No money moves and no row is written. Current clients do not offer that call on a resolved transfer: mobile `app/transfer/receive/[id].tsx:422` (`seller_sent`/`pending` only, at `404bce38`) and web `BuyerTransferPanel.tsx:140` (`seller_sent` only, at the gate). Older installed builds were not checked, and a direct API call remains possible. **Before 148, the same call pays the seller despite the hold**: the pre-148 claim body has no hold or review check at all (pre-148 replay, lines 48-86) | source; local body; D's trace |

## 4. Preflight: production reads, run at execution time, each a STOP on mismatch

| # | Step | Expected, or STOP |
|---|---|---|
| P1 | `deploy_148.sh enforce-transfer-expiry --dry` | `before` version **40**, `verify_jwt` True. The deployed source, downloaded, is byte-equal to the gate `5b255838` blobs (index + 5 shared). Proves the rollback target is the running code |
| P2 | `apply_one_148.sh 00` (baseline read-back) | recorded, including census, grants matrix and switches; the comparison base for the post read-back |
| P3 | `apply_one_148.sh 01`, starting-state block, run before the apply request is built | 148 ledger rows 0; ledger **160**, max `20260923000000`; claim defn md5 `d3cd9fdd…` and prosrc md5 `083bf9a3…`; notify defn md5 `37a46d03…` and prosrc md5 `203f7c7d…`; trigger `trg_notify_transfer_state_inbox@transfers=O`; **seller-win rows 0**; **the seller-win writer is the repo's**. Its logic: `resolve_transfer_dispute` prosrc md5 `19161d7a…` and `admin_resolve_dispute` prosrc md5 `4548b9ee…`. Its binding contract, which prosrc cannot see (D): ordered args, result type and `SECURITY DEFINER` for both, plus the admin wrapper's `search_path=public`, because it calls `resolve_transfer_dispute` unqualified (A). Informational, as an attribute-level delta: defn md5, the writer's config (its only unqualified call is `pg_catalog.set_config`), owner, volatility; dispute_resolutions, open disputes, payout_attempts, both ACLs |

**Why the writer check exists:** 148 keys on the exact row shape that `resolve_transfer_dispute` writes (status
`buyer_confirmed`, `buyer_confirmed_at` NULL, `dispute_resolution 'resolved_seller_paid'`). The defect analysis was
source-verified at the gate, not against production's body. Production's **defn** md5 for both writers differed from
the replay in the 2026-09-22 capture: `resolve_transfer_dispute` `7d18f1d8` vs `7b9e17a5`, `admin_resolve_dispute`
`9f70196f` vs `2649898d`. The cause is unknown; it may be attributes only. Ten other functions differ in the same way,
none of which 148 touches.
- A **prosrc** match proves the logic is the repo's.
- A mismatch stops the run (exit 3). A then reads that body (a preflight read), and A and D diff its seller-win branch.
- Any difference comes back to the owner as a one-line re-approval; nothing is applied meanwhile.
- **If production's writer set `buyer_confirmed_at` on a seller-win, the defect and the fix would both be different**,
  which is why this is a stop and not a note.
- **Offline decomposition attempted, and it does not explain the drift.** Nine attribute-only variants of the local
  definitions were hashed against production's 8-character prefixes for all 12 drifted functions: search_path
  `''` / `public,pg_temp` / `public,extensions` / none, SECURITY DEFINER removed or added, a trailing newline, and
  CRLF. **Not one matched any of the twelve.** So the differences are most likely in the bodies. P3's prosrc check is
  therefore **likely to stop** on `resolve_transfer_dispute`, whose only definition in git is 065 (`c11c8b45`, never
  edited). **A one-query read before execution day settles this; see §8 (R0).**

The expected pre-state is not assumed. Production's last recorded values match it: claim defn `d3cd9fdd…` from the
2026-09-22 read-back of `20260906120000`, and notify defn `37a46d03…` from the 2026-09-22 untouched-function comparison.
Only 147 (`get_unsettled_payments`) has been applied since. The four claim and notify values were recomputed on the
pre-148 replay today by A, and **independently by D** (8/8, pre and post, on D's own fresh copy). Record paths:
`apply_5b255838/out/21_readback.json` (claim), and `apply_5b255838/out/prod_untouched_fns.txt` (notify
`37a46d03`), a production capture written 2026-09-23 ~03:11Z, just after the 24-file apply completed at 03:06:35Z. Its
producing command is not in a script, only in that session's history; its content differs from the local list in 12
functions, so it is not a copy.

## 5. Execution (A runs every step; owner authorises; D witnesses the reads if the owner authorises D)

Every production invocation carries `CONFIRM_REF=hqycwntpfoztoinemqns`. Without it, each script refuses (exit 2)
before reading the token or making any network call. The first printed line always names the mode and target
(`### MODE=PRODUCTION target=hqycwntpfoztoinemqns`, `MODE=REHEARSAL …`, `MODE=DRY …`). This makes production a
deliberate choice in both directions (D's review, 2026-09-24).

1. **P1, P2** (reads).
2. **Apply:** `apply_one_148.sh 01`. This runs the P3 guard, then POSTs the migration text plus the ledger insert as one
   request to the Management API (`POST /v1/projects/hqycwntpfoztoinemqns/database/query`, the 147 route), then the
   read-back, then the **automatic post-assert**:
   - ledger row, and ledger 161;
   - claim defn `b6aae868…` + prosrc `ce30b56c…`;
   - notify defn `8de79350…` + prosrc `ff103b3e…`;
   - `secdef=true`, `search_path=public`;
   - read-back grants delta: none.
3. **Deploy, only after step 2 PASS:** `deploy_148.sh enforce-transfer-expiry`. It repeats the P1 guards, then runs
   `supabase functions deploy --use-api` from the frozen `e73553d2` worktree, then checks:
   - version 41, `verify_jwt` True;
   - the deployed source downloaded back and **byte-compared to `e73553d2`**.
4. **Run check, after at least 2 cron ticks** (every 2 min): `runcheck_148.sh <deploy time>`. This reads the cron's own
   response bodies. It PASSes with at least 2 post-deploy runs, all HTTP 200, not timed out, and `errors` equal to the
   newest pre-deploy run's value. A failing (d) query increments `errors`
   (`index.ts:1224-1226`).
5. **Records:** registry row 148 → applied; SPRINT_STATUS; this package's §10.
6. **Repository, only under approval (C):** mark #92 ready, retitle it without "DO NOT MERGE" and merge it into
   `release/production-gate-20260918`, **not `main`**, as #91/147 was. This happens only after steps 2–4 PASS, so the
   gate's tree equals production.

Duration is about 15 minutes. It must happen **before the first of the 5 open disputes is resolved**. Nothing else
needs to be quiet.

## 6. Stop conditions and rollback

| Where it stops | State left | Next |
|---|---|---|
| P1/P3 mismatch | nothing changed | report to the owner |
| Apply HTTP ≠ 201 | nothing changed (one request, one transaction) | report |
| Post-assert FAIL | 148 is in the database; the edge is untouched | under (B), or on the owner's word: `rollback_148.sh`. Its guard requires the 148 bodies and 1 ledger row; the rollback file itself refuses unless the bodies are 148's, and raises unless the restored bodies hash to pre-148. It then deletes the ledger row and reads back |
| Deploy failure, or byte mismatch after deploy | DB at 148; edge at v40 or at an unverified v41 | rollback the edge with the **frozen** `deploy_one.sh enforce-transfer-expiry` (sha256 `029c6af7…`) from the `5b255838` worktree, which byte-verifies the gate source. The DB can stay at 148: the claim is only stricter, and seller-win rows stay unpaid as today |
| Run check FAIL | both applied | edge rollback as above, then report. The DB decision is the owner's |

**Rollback order when both must go: edge first, then the DB. Do not simplify this.** The pre-148 claim already admits a
seller-win row but has no hold rule. If the DB were rolled back first, the new edge's (d) selection would still find
seller-win candidates while the authority no longer enforced holds: a window in which a held or manual-review row
could be paid, guarded only by (d)'s inline check. Edge first removes the candidates before the authority weakens
(A's reasoning; D confirmed it independently). The rollback reverses code only. It cannot reverse a payout already made, which is why the post-assert and run
check come before any seller-win resolution.

## 7. Local rehearsal (production-shaped for the objects 148 touches)

See §10 for the run evidence. The rehearsal runs the **frozen apply script itself**. Its `LOCALDB=<db>_rehears` mode
sends the same request texts to a local copy of the pre-148 replay with a 160-row stand-in ledger. It runs:
- the positive control, P3 PASS on the base;
- apply → read-back → post-assert;
- the negative control, P3 re-run on the applied DB, which must FAIL;
- the rollback request (the frozen rollback assembled by `rollback_148.sh`, `DRY=1`), then pre-hashes restored and the
  ledger back to 160;
- re-apply, with identical hashes;
- pgTAP 215 on the re-applied DB, 43/43.

**Evidence limits:**
- The local harness is superuser with default ACLs, so its grants matrix is not production's. Only the delta is
  meaningful.
- The ledger is a stand-in.
- The edge deploy and download path cannot be rehearsed locally. It was proven byte-faithful on 2026-09-22/23 (v38 → v39,
  and the ten-function release).
- 148 was not applied to the sandbox. That was not authorised, and the sandbox at ledger 144 is not production-shaped for
  the payout path.

## 8. Approval request (what the owner is asked to say)

These are three separate decisions, following D's review, so the apply can be approved without pre-authorising a
rollback or a merge.

**(R0) Recommended first, and separate: one read-only production query** of the two dispute-writer definitions:
defn and prosrc md5, arguments, result, security, config, and the two `prosrc` texts. These are function definitions
only; no user data is read. It answers the drift question before (A), instead of at P3 on the day.
> "I authorise one read-only production query of the definitions of `public.resolve_transfer_dispute` and
> `public.admin_resolve_dispute`, as in §8 R0 of the package."

**(A) Required: the apply and deploy.**
> "I authorise the PR #92 production apply and deploy as in `PR92_PRODUCTION_EXECUTION_PACKAGE_20260924.md` at
> `<commit>`: the preflight reads P1–P3, the apply of migration 148, the deploy of `enforce-transfer-expiry` only, the
> run check, and the records. This does not authorise any rollback, merging #92, resolving any dispute, deploying
> `confirm-and-release`, or any other production change."

**(B) Optional: pre-authorised rollback.** Without it, A stops at a failed check, reports, and waits.
> "If a read-back or the run check fails, A may run the §6 rollback for the failing layer, edge first."

**(C) Separate, and may come later: source reconciliation,** as with #91/147.
> "After A reports the apply, deploy and run check as PASS, A may mark #92 ready and merge it into
> `release/production-gate-20260918` (not `main`)."

**Optional (D): D's read-only witness** of P1–P3 and the read-backs.

## 9. Frozen artefacts (`scratchpad/apply_148/`)

Recorded at freeze time in `README_148.md`, with sha256 values. Each derived script has its diff against the frozen
precedent as the review surface:
- `apply_one_148.sh`, vs `apply_one_147.sh` (`2260c00a…`);
- `rollback_148.sh`, vs `rollback_147.sh`;
- `deploy_148.sh`, vs `deploy_one.sh` (`029c6af7…`). Its `--dry` mode performs production **reads** (version and the pre-download), so it could not be exercised before authorisation; it is reviewed by diff only;
- `runcheck_148.sh`, which is new;
- `manifest_sha256.txt`, `rollback_sha256.txt` and `a_md5.txt`;
- `d_md5.txt`, D's external anchor, computed from the git ref.

## 10. Rehearsal and freeze record (A, 2026-09-24 ~15:58Z)

**Rehearsal**, run by the frozen `apply_one_148.sh` in `LOCALDB` mode against `a_148fbf_rehears`: a copy of the pre-148
replay `a_sw_base_rehears`, with a 160-row stand-in ledger whose max is `20260923000000`.
1. `00` baseline: ledger 160; census recorded; 75 grant rows.
2. `01`: D anchor ok (md5 `4eb38855…`, 13,567 B). P3 **PASS**, every value equal to production's recorded pre-state. HTTP 201.
   Read-back: ledger row + 161, claim `b6aae868…`/`ce30b56c…`, notify `8de79350…`/`ff103b3e…`, `secdef=true`,
   `search_path=public`, execute grants unchanged (service_role only), grants delta none, census unchanged.
   **POST-APPLY ASSERTION: PASS.**
3. Negative control, `01` on the applied DB: P3 reports ledger 1/161 and both 148 hashes; "UNEXPECTED STARTING STATE —
   NOT APPLYING 148", exit 3.
4. Rollback: `DRY=1 rollback_148.sh` assembled the request (sha256 `626db799…`). Its guard SQL on the applied DB returned
   exactly the rollback's expected values. The request ran; the read-back shows ledger 160, claim `d3cd9fdd…`/`083bf9a3…`,
   notify `37a46d03…`/`203f7c7d…`, grants delta none. The guard SQL re-run afterwards no longer matches, which is its
   negative control.
5. Re-apply: P3 PASS, and the same four post hashes. **POST-APPLY ASSERTION: PASS.**
6. pgTAP 215 on the re-applied DB: plan 1..43, **ok 43, not ok 0**.
7. The production request assembled offline (`DRY=1 apply_one_148.sh 01`, no network call) is **byte-identical** to the
   rehearsed request: sha256 `c91cec23ac3d87bba2d988326b07c4f445e3f529da48be5c60f9093f50fcb145`, 27,375 B.

Run check: `runcheck_148.sh`'s query and verdict logic were exercised on a stub `net._http_response` with the same
columns. Two healthy post-deploy runs gave PASS. One post-deploy run with `errors=1` gave FAIL.

**D's external anchor** (`d_anchor_verbatim.txt`), computed by D from the git ref: migration md5 `4eb38855…`, 13,567 B,
sha256 `f9f45ae4…`, blob `2b6e54d7…`; rollback sha256 `8c5e34c4…`, md5 `b72d4104…`, 11,271 B, blob `584af1b8…`. All
equal A's. `d_md5.txt` holds it in the script's one-line format: `20260924000000 4eb38855e9eb2dcbbdb45a13b50beeff 13567`.

**Rehearsal 2, after the mode gate was added** (~16:04Z; fresh copy of the same template): banner
`MODE=REHEARSAL`; P3 PASS; apply → POST-ASSERTION PASS; the negative control refused (exit 3); rollback request sha256
`626db799…` (unchanged) → pre-hashes restored and 160 rows; re-apply → PASS; pgTAP 215 43/43. The DRY production
request is still sha256 `c91cec23…`, byte-identical. Negative controls for the gate: with no `CONFIRM_REF`, all four
scripts print `### REFUSED …` and exit 2.

**Frozen (read-only), sha256:**

| File | sha256 | Bytes |
|---|---|---|
| `apply_one_148.sh` | `0bf97b89c15d12d2d784a21fa1c720069b58ac7c30427b46508d4266b328eaa0` | 16,007 |
| `rollback_148.sh` | `1419f12fcc0ffecf7c0cb2a9915494ac2b7d119af66706d21da1ad69e5b3d0c6` | 5,018 |
| `deploy_148.sh` | `142899c83dd3a864a45a5a8f31788af8b44864d07a052cf523dbf04d4457eebf` | 6,919 |
| `runcheck_148.sh` | `14e0b918ee424ff3f7e246b19050d4b85fd973d99d3518a1948c750e1a20fc5b` | 3,889 |
| `migrations/20260924000000_…sql` | `f9f45ae4aeaf86f843cb41da0db362188f6d073a89fff689ee291c375fe99a2d` | 13,567 |
| `rollbacks/20260924000000_…_rollback.sql` | `8c5e34c403f964261064cf12f162a329db3f4606adba46bbec1f1c33cc3abaeb` | 11,271 |
| `d_md5.txt` (= `a_md5.txt`) | `b7f8961747ecf1b3cbdb5a2aaba771bbf09db6db8e797404d0182924663b5385` | 54 |
| review surfaces: `diff_vs_apply_one_147.patch` (99 changed lines), `diff_vs_rollback_147.patch` (55), `diff_vs_deploy_one.patch` (48) | `8287d7fa…`, `7b9d52a8…`, `bac20588…` | |

The first freeze (`8977efae…` / `f33ade58…` / `4db0969b…` / `c1b9abf9…`) is superseded. The only change is the mode gate
and banner.

**Rehearsal 3, after the writer check was added to P3** (~16:12Z; fresh copy):
- **Negative control first:** the writer body was changed by one comment (prosrc `2bfbca0a…`); P3 reported the mismatch
  and exited 3 before any request.
- **Clean copy:** P3 PASS (writer prosrc `19161d7a…` / `4548b9ee…`; defn `7b9e17a5…` / `2649898d…`); apply → POST
  PASS; re-run refused (exit 3); rollback `626db799…` → 160 rows and pre-hashes; re-apply → PASS; 215 43/43.
- The production request is still `c91cec23…`, byte-identical.
- `apply_one_148.sh` became `1c477598…` (107 changed lines), superseding `0bf97b89…`.

**Rehearsal 4, after D's binding-contract recommendation** (~16:16Z):
- **Three negative controls, each on a fresh copy:**
  - NC1: the admin wrapper's search_path set to `''`, with the body identical, **stops** (exit 3);
  - NC2: the writer set to `SECURITY INVOKER`, with the body identical, **stops**;
  - NC3: the writer's search_path set to `public, pg_temp` is informational, so it **proceeds** to POST PASS.
- **Clean copy:** P3 PASS, then apply, POST PASS; re-run refused (exit 3); rollback `626db799…` → 160 rows; re-apply →
  PASS; 215 43/43; the production request is still `c91cec23…`.
- The rehearsal DB was dropped afterwards.
- **`apply_one_148.sh` is now `3d74a714ddd093a50002e5292e7bebc72f2a26e45ea33af2cdc70354bdb34e1a`** (18,693 B; diff
  `f36836de…`, 115 changed lines). The other scripts are unchanged: rollback `1419f12f…`, deploy `142899c8…`, runcheck
  `14e0b918…`. `FROZEN_SHA256.txt` is regenerated.
The full list is `apply_148/FROZEN_SHA256.txt`. Any change means disclosure, D re-review and a new hash.

## 11. Review status and bearing of the reader sweep (2026-09-24 ~16:10Z)

**D's review so far (as of ~16:15Z):**
- **Reviewed and passed:**
  - the frozen artefacts (scripts, anchor files, directory and hashes);
  - the anchor read-back, recomputed from the ref;
  - the anchor guard;
  - `LOCALDB` safety;
  - the `CONFIRM_REF` gate, in both directions;
  - the rollback order;
  - §8. D found two faults in it: the quote pre-authorised the rollback while an option claimed to let the owner
    decline it, and it bundled the merge with the apply. §8 is rewritten as (A)/(B)/(C).
- **Independently determined by D:** all 8 claim and notify hashes, pre and post (claim `d3cd9fdd`/`083bf9a3` →
  `b6aae868`/`ce30b56c`; notify `37a46d03`/`203f7c7d` → `8de79350`/`ff103b3e`), on D's own fresh copy, applying the
  frozen migration.
- D could not find `prod_untouched_fns.txt`. It is in `apply_5b255838/out/`, one level below the directory D checked
  (A verified; the path is now given in full in §4).
- **Not reviewed by D:**
  - §10's rehearsal narrative;
  - the regenerated diffs, beyond the presence of the `CONFIRM_REF` lines;
  - the writer check added after D's review (rehearsal 3);
  - `deploy_148.sh --dry` (a production read).
- **Reviewed by D after that:** the added P3 lines and the prosrc bar. D judged prosrc right but not sufficient and
  recommended the binding contract, which A adopted in rehearsal 4. D judged search_path not to matter because the
  writer's references are qualified. A verified that this holds for the writer but not for the admin wrapper, whose
  unqualified call makes its config part of the contract.
- **Adopted from D:** the mode gate, the rollback-order reasoning, the §8 split, and the binding contract.

**Reader sweep** (A's read-only subagent, SERVER = #92 head, CLIENT = `404bce38`): every place that treats
`status='buyer_confirmed'` as proof the buyer confirmed.
- **Class (a), a false claim to someone, 10 entries:** 7 unfixed, 2 fixed (the 058 trigger by #92; mobile by C's three
  commits), 1 dead code.
- **Class (b), a decision that acts on it, 4 entries:** 2 fixed by #92; 2 unfixed or partly fixed.
- **Bearing on R1, checked by A in source:** #92's new (d) path reuses `payReleasedTransfer`. Its only decision write
  records `buyer_confirmed: false` (`enforce-transfer-expiry/index.ts:883-897`). **So #92 adds no new false record.**
- **Every unfixed item predates #92.** None is made reachable by it, except `payoutDeferred` (a1), which is reachable
  only if `confirm-and-release` is redeployed. That is excluded (F-CR-148-SHARED).
- The unfixed items are recorded in `FINDINGS_20260924_DISPUTE_GRANT_AND_OPS_CASE.md` for follow-up owners:
  - the web copy (a7);
  - the admin labels (a5, a6);
  - three decision writers (a2–a4);
  - `confirm-and-release`'s already-confirmed inference (b1);
  - `ops.detect_release_stuck`, which would open false "stuck" cases for held seller-win rows (b2).
- **None of them blocks R1.**
- D's five (b4, a8, b1, b2, a1) are all in the list. D missed a3 and a4, although both lines were in D's own grep output.
  D takes a5 and a6. a6 displays a flag that a1–a4 corrupt, so fixing the writers fixes a6; a5, the label mapping, is
  independently wrong.

