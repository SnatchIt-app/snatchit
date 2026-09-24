# Production execution package — migration 149 + `confirm-and-release` (A, 2026-09-24)

**Status: PREPARED AND FROZEN; NOT AUTHORISED. Nothing in this package has touched production.**
- **Source:** the release gate `release/production-gate-20260918` at `037092f00cd46c0062c30b4a9dc70dd6928e998b`, which is
  #93 merged on top of #92. Both merges were owner-authorised and verified; see the #92 package §14.
- **What it does:**
  - Applies migration 149 (`20260924120000_payout_decisions_buyer_confirmed_truth.sql`).
  - Deploys `confirm-and-release` from the gate. v37 becomes v38.
  - Both fix the a1–a4 audit writers (FINDINGS F-CR-148-SHARED and its follow-ups).
- **Not in scope:** resolving disputes, merging to `main`, an app build, and any other function or migration.
- **Scripts:** in `scratchpad/apply_149/`, derived from the executed 148 scripts. The diffs are the review surface (§9).

## 1. Identity (verified 2026-09-24 ~18:30Z)

| Object | Value |
|---|---|
| Gate tip | `037092f0…` (parents `374103c0` = #92 merge and `9e7006bf` = #93 head); CI 36040031287 green, pgTAP Files=96 / Tests=5543 |
| Migration 149 file | blob `1b58b20c…`, sha256 `ce4440ca…`, md5 `7e4d3b2d347c1cedf63e554dd6358569`, 9,904 B |
| Rollback file | blob `5d7c5677…`, sha256 `c61c458b…`, 9,343 B |
| `confirm-and-release` bundle at the gate | `index.ts` `668e59d6`, `_shared/payouts.ts` `2d1da2f9`, `payout-logic.ts` `923c70b4`, `sentry.ts` `dc349604`, `stripe.ts` `141b3b61` |
| Running v37's source (`5b255838`) | `index.ts` `ea3b7a85`, `payouts.ts` `7c1eda16`; the other three are identical. So 2 of 5 files change, and neither byte comparison is vacuous |
| Deploy source worktree | `scratchpad/gate149`, detached at `037092f0`, clean, unlinked |
| Edge rollback | frozen `apply_5b255838/deploy_one.sh` (sha256 `029c6af7…`) run from `scratchpad/gate5b` (clean at `5b255838`) |

## 2. What changes in production

- **DB (149):** `record_payout_attempt_result` and `flag_payout_reversal_required` each change one expression:
  `buyer_confirmed := v_t.status = 'buyer_confirmed'` becomes `v_t.buyer_confirmed_at IS NOT NULL`.
  - prosrc md5 `6a8372b4…` → `62f74728…` and `d86c2b36…` → `03ea4589…`.
  - defn md5 `f8ffef47…` → `255e9022…` and `e26a538c…` → `0d692f32…`.
  - One ledger row is added, taking the ledger from 161 to 162.
  - No new object; grants and census are unchanged. No data row is written by the apply.
- **Edge (`confirm-and-release` v37 → v38):**
  - a1/a2 (the #93 change): §5 selects `buyer_confirmed_at, dispute_resolution`. `buyer_confirmed` becomes
    `Boolean(buyer_confirmed_at)`, and the first reason code becomes the actual basis.
  - #92's `_shared/payouts.ts` (+2 lines) maps `PAYOUT_HELD` / `PAYOUT_UNDER_REVIEW` to `not_eligible`.
  - No other function is deployed.

## 3. Expected effects

| # | Effect |
|---|---|
| E-1 | **At apply and deploy: no row changes, no money movement, no Stripe call, no notification.** Only function bodies, one ledger row and one function version change |
| E-2 | Genuine buyer confirmations are unchanged: `buyer_confirmed true`, `BUYER_CONFIRMED` (existing tests pass unchanged) |
| E-3 | Rows with no buyer confirmation record `buyer_confirmed false` and a truthful basis (`DISPUTE_RESOLVED_SELLER` / `AUTO_RELEASED` / `NO_BUYER_CONFIRMATION`). There are 0 seller-win rows today; P3 reports the count |
| E-4 | **Closes the #92 package's E-6.** A buyer call on a held or under-review seller-win now returns 200 `pending_review` and writes one truthful `manual_review` decision. v37 returned `processing` and wrote only a `db_error` log line |
| E-5 | A confirmed row later frozen by a chargeback records `true` on a reversal decision (was `false`) |
| E-6 | Admin shows the new basis codes verbatim. The flag's only reader is the admin label at `orders/[paymentId]/page.tsx:542` |
| E-7 | **After this package, a seller-win resolution produces no false audit record on any path.** Whether and when to resolve the 5 open disputes remains the owner's decision |

## 4. Preflight: read-only, each step a STOP on mismatch

- **P1** `CONFIRM_REF=hqycwntpfoztoinemqns deploy_149.sh confirm-and-release --dry`
  - Reads the functions list and downloads v37's source.
  - Expects version 37, `verify_jwt` True, and the pre-download equal to `5b255838`'s 5 blobs, with 0 mismatches.
- **P2** `CONFIRM_REF=… apply_one_149.sh 00`
  - The baseline read-back: ledger 161 with no 149 row, census 32/108/37/38, switches, grants matrix.
- **P3** `CONFIRM_REF=… apply_one_149.sh 01 prestate`
  - This is also run automatically inside the apply, immediately before the request.
  - 11 STOP keys: ledger 0/161/`20260924000000`; a3 defn/prosrc `f8ffef47…`/`6a8372b4…`; a4 defn/prosrc
    `e26a538c…`/`d86c2b36…`; the a3 and a4 binding contracts (args, result, secdef, search_path); 148's claim and notify
    prosrc still `ce30b56c…`/`ff103b3e…`.
  - Info: ACL and owner of both, payout_attempts, payout_decisions, seller-win rows, dispute_resolutions, open disputes.
  - **P3 is the production read of a3/a4 that D and A flagged as never having been made.** On a mismatch it prints the
    observed values and stops before any change.

## 5. Execution (A runs every step; the owner authorises)

1. Register predictions in `exec_predictions.txt` before any step.
2. P1, P2 (read-only).
3. `CONFIRM_REF=… apply_one_149.sh 01`: the D anchor check, P3, one request (migration + ledger insert, one implicit
   transaction), then read-back and the POST assertion.
4. `CONFIRM_REF=… deploy_149.sh confirm-and-release`: the before-version guard, the pre-download check, the deploy, the
   after read (version 38, `verify_jwt` True), and the post-download byte comparison against `037092f0`.
5. **Optional V-3** `CONFIRM_REF=… probe_149.sh`: one `OPTIONS` request with the public anon key. The handler answers
   `OPTIONS` before any auth, database or Stripe call, and only after every static import has evaluated. So it proves
   the new bundle boots, and it writes nothing.
   - **The discriminator is the body `ok`, the function's own string.** A gateway answering the preflight itself would
     not produce it, so the check must never be trimmed to "HTTP 200".
   - The response header `Access-Control-Allow-Methods: POST, OPTIONS` (from `getCorsHeaders`) is the function's own
     fingerprint.
   - Outcomes: body ok + header → **PASS**; body ok, header different → **INCONCLUSIVE**, reported and NOT a rollback
     trigger; anything else → **FAIL**.
   - **It exercises none of the changed code.** a1/a2 run in the POST path after authentication. It also does not
     identify the version; attribution is by timing, after `deploy_149.sh` has read v38 back (D).
6. Records: the registry row, the SPRINT_STATUS entry, the execution record in this file, and checklist R1.

## 6. Verification, and what it cannot show

- **DB POST assertion, 15 checks plus the grants matrix,** all pass/fail inside the script:
  - the ledger row (`created_by=claude-a/owner-authorised-149`, `stmts=1`) and ledger 162;
  - **`md5(statements[1])` = `7e4d3b2d…`**, D's anchor. This closes reviewed blob → applied file → **recorded**
    statement without needing any other production read;
  - both defn lines (secdef, search_path) and both prosrc lines;
  - both grant lines (service_role only);
  - census 32/108/37/38;
  - the three switches (detectors true, refund-resolution detector false, **alert delivery false**);
  - **148's claim and notify bodies unchanged** (`ce30b56c…`/`ff103b3e…`), showing the apply touched only what it
    should;
  - the grants matrix identical to P2's. P2 (`00`) must run first, or the assertion fails.
- **Edge:** version 38; `verify_jwt` True; post-download 5/5 files equal the gate blobs; no unexpected `_shared` file.
- **Not shown:** the new paths run only on a buyer call for a row with no buyer confirmation, or on a reversal. None
  occurs on its own and none will be triggered. Their evidence stays:
  - pgTAP 216, with D's independent red/green;
  - vitest BC-* and SW-AUDIT-*;
  - the mutants.

## 7. Stop conditions and rollback

| Where it stops | State left | Next |
|---|---|---|
| P1 / P3 mismatch, or the D anchor fails | nothing changed | report |
| Apply HTTP ≠ 201 | nothing changed (one request, one transaction) | report |
| POST assertion FAIL | 149 is in the DB; the edge is untouched | `rollback_149.sh` under (B-149). Guarded: it refuses unless 149's bodies and 1 ledger row are present. The file restores the bodies and verifies the pre-149 hashes; then a **conditional** ledger delete fires only if those hashes hold |
| Deploy failure, or a byte mismatch after the deploy | DB at 149; edge at v37 or an unverified v38 | edge rollback: frozen `deploy_one.sh confirm-and-release` from `gate5b`, which byte-verifies `5b255838`. The DB can stay at 149 |
| V-3 FAIL | both applied | edge rollback as above; then report |

- **The layers are independent.** Both are audit writers with no call between them, so either can be rolled back
  without the other, in either order.
- **There is deliberately no "bodies-only" mode** (D). The one state it would serve (ledger row gone, bodies still
  149's) is unreachable through these scripts: `ledger-only`'s delete is conditional on the pre-149 bodies, so it
  cannot fire against 149's. A later migration that owns these bodies also keeps 149's ledger row, which is correct.
- The delete's conditions use `::regprocedure`. That **raises** if either function has been dropped, rather than doing
  nothing. This is the loud direction, kept on purpose: read such an error as "a function is missing", not as corruption.
- **Runbook, P3:** if a **defn** pin mismatches while prosrc and the binding both match, the first hypothesis is a
  rendering difference in `pg_get_functiondef` (the pins come from a local replay; the precedent is n=1, at 148).
  Re-derive from production's own text. Do not treat it as drift or an incident; the stop was safe. (D)
- **Rollback transaction shape, disclosed:** the reviewed rollback file carries its own `BEGIN…COMMIT`, so the ledger
  delete runs as a second implicit transaction after it. If the file raises, nothing after it runs. If only the delete
  fails, `rollback_149.sh ledger-only` resumes. The frozen `rollback_148.sh` has the same shape, unconditional there; it
  was never run.
- The rollback reverses code only. Audit rows written in between stay as written.

## 8. Approval request (what the owner is asked to say)

**(A-149) Required:**
> "I authorise the production execution in `PR93_PRODUCTION_EXECUTION_PACKAGE_20260924.md` at `<commit>`: the
> preflight reads P1–P3, the apply of migration 149, the deploy of `confirm-and-release` only from the gate at `037092f0`,
> the verification and the records. This does not authorise resolving disputes, merging to `main`, an app build or any
> other production change."

**(B-149) Optional, the pre-authorised rollback:**
> "If a verification step fails, A may run the §7 rollback for the failing layer."

**(V-3) Optional, the boot probe:**
> "A may send the one `OPTIONS` boot probe in §5.5."

**Alternative, smaller first step (R-149), read only:**
> "I authorise P1–P3 of the package as read-only preflight."

The apply then needs (A-149) separately. P3 runs again inside the apply either way, so R-149 adds a checkpoint, not
extra safety.

## 9. Frozen artefacts (`scratchpad/apply_149/`, frozen 2026-09-24 ~18:30Z)

`FROZEN_SHA256.txt` (sha256 `8305d966…`, re-frozen after D's review) lists 16 files with sha256 and size. The execution-time check is that every
line matches. Review surfaces:

| File | sha256 | Derived from | Diff |
|---|---|---|---|
| `apply_one_149.sh` | `e2100356…` | executed `apply_one_148.sh` (`8cbd950d…`) | `diff_vs_apply_one_148.patch`, 136 changed lines: path, usage, the `prestate` sub-mode, the 149 STOP block, tag and `created_by`, and the 149 POST assertion (15 checks plus the grants matrix, after D). The vault mode and the 133 / #21 guards are kept verbatim and are inert |
| `rollback_149.sh` | `9f84866a…` | `rollback_148.sh` (`1419f12f…`) | `diff_vs_rollback_148.patch`: the 149 guard, the **conditional** ledger delete, `ledger-only`, and a LOCALDB rehearsal mode (148's rollback had none) |
| `deploy_149.sh` | `edf04467…` | executed `deploy_148.sh` (`142899c8…`) | `diff_vs_deploy_148.patch`, 28 changed lines: W = `gate149` at `037092f0`; `confirm-and-release` only; `verify_jwt` True; closure `payout-logic payouts sentry stripe` (= frozen `deploy_one.sh`'s table); before-version 37 |
| `probe_149.sh` | `754f93c6…` | new | the V-3 `OPTIONS` probe. The key comes from `eas.json`'s production profile, is checked for `role=anon`, `ref=hqycwntpfoztoinemqns`, and is never printed. Outcomes PASS / INCONCLUSIVE / FAIL (body `ok` + methods header) |
| migration / rollback | `ce4440ca…` / `c61c458b…` | git blobs `1b58b20c` / `5d7c5677` at `037092f0` | — |
| `d_md5.txt` | `20260924120000 7e4d3b2d347c1cedf63e554dd6358569 9904` | **D's independent anchor** from ref `037092f0` (`d_anchor_verbatim.txt`); equals A's `a_md5.txt` | — |
| Edge rollback | `apply_5b255838/deploy_one.sh` `029c6af7…` (pre-existing, frozen 2026-09-22) | — | — |

## 10. Rehearsal record (A, 2026-09-24 18:24–18:26Z; predictions registered first, `rehearsal_predictions.txt` `d36b69b9…`)

**Rehearsal database:** `a149_rh_rehears`, the pre-149 chain (replay 164/165 from `037092f0`, census 32/108/37/38) plus
a **161-row stand-in ledger** with max `20260924000000`. The frozen scripts ran in `LOCALDB` mode: the same request
texts, sent to a local database.

| Step | Result | vs prediction |
|---|---|---|
| R0 `00` | ledger 161, census 32/108/37/38, switches as production, 69 grant rows | — |
| R1 `01 prestate` | 11/11 STOP keys equal; **PASS**; nothing applied | match |
| R2 `01` | anchor ok; P3 PASS; 201; **POST 9/9 PASS**; ledger 162; grants delta none. Request sha256 `f1bb0489…` | match |
| R3 negative control: P3 on the applied DB | **FAIL on 7 keys**, exit 3 | **prediction said 6: I omitted `ledger_max`**, which necessarily moves to `20260924120000`. My prediction error, not the script's |
| R4 `rollback_149.sh` | rb-prestate PASS; 201 (request `749d690b…`); no 149 row; ledger 161; a3/a4 prosrc `6a8372b4`/`d86c2b36` | match |
| R5 rollback again | STOP at rb-prestate (5 keys), exit 3 | match |
| R6 partial-rollback resume | re-apply; only the rollback FILE run (ledger row left) → `rollback_149.sh` STOPs → `ledger-only` → ledger 161 | match |
| R6c condition control | `ledger-only` while 149's bodies are live → **deletes nothing** (ledger stays 162) | added control, as expected |
| R7 re-apply | POST PASS, identical hashes; pgTAP **216 26/26, 122 74/74, 215 43/43** on the re-applied DB | match |
| R8 `DRY=1` production assembly | `01_apply.sql` **byte-identical** to the rehearsed request (`f1bb0489…`, 20,051 B); the rollback request also identical (`749d690b…`) | match |

**v2 re-rehearsal after D's review** (18:34–18:36Z; `rehearsal_predictions_v2.txt` `8901e997…`, registered first):
**every prediction matched.**
- V2-R0 to R2 on a fresh DB: the POST assertion runs 15 checks plus the grants matrix, all PASS, with `stmt_md5` =
  `7e4d3b2d…`.
- **N1**, the comparator control (a copy of the script with the `stmt_md5` expectation zeroed): FAILS on exactly
  `stmt_md5`.
- **N2**, "00 not run": FAILS on exactly `grants_baseline`.
- R4 rollback PASS; R7 re-apply PASS with 216 at 26/26.
- R8 DRY request still byte-identical (`f1bb0489…`). The request text did not change; only the checks did.

**Controls:**
- All four scripts **REFUSE** without `CONFIRM_REF`. The first line names the mode; `deploy_149.sh --dry` also refuses,
  because it reads production.
- A tampered `d_md5.txt` gives `D-ANCHOR MISMATCH … NOT APPLYING`, exit 2. The file was restored and verified by digest.
- `deploy_149.sh` refuses any function other than `confirm-and-release`.

**Evidence limits:**
- The ledger is a stand-in.
- The local harness is superuser with default ACLs, so only the grants **delta** is meaningful.
- The edge download/deploy path cannot be rehearsed locally. It was byte-faithful today on 148's deploy (v40 → v41,
  6/6).
- P1 and the probe read production and are not rehearsable.
- The pre-149 defn md5s were computed locally. That matches 148's precedent: its locally computed claim and notify defn
  md5s equalled production's in P3 and in the read-back.

## 11. Review
- **D, 2026-09-24:** independent anchor (above), and a post-hoc PASS on both merges from D's own GitHub reads.
- **D, script review of the frozen package at `0d2851be` (2026-09-24 ~18:32Z): PASS.**
  - D's own checks: the manifest (15/15); the anchor, agreed by both parties; the import closure, derived independently
    (5 files; `payout-policy.ts` correctly absent); before-version 37 from D's own earlier read.
  - Rollback transaction shape: "sound, and materially better than 148's".
  - Keep the defn pins: they cover LANGUAGE, volatility, COST and parallel safety, which the binding does not.
  - V-3 is real evidence because of the body check.
  - D recommended adding `md5(statements[1])` before this went to the owner, plus three improvements. **All four are
    adopted:**
    - `stmt_md5`;
    - 148's bodies in the POST assertion;
    - switches and grants as pass/fail;
    - the probe fingerprint with an INCONCLUSIVE outcome.
  - The doc notes D asked for are in §5.5 and §7. Re-rehearsed as v2 and re-frozen (`8305d966…`).
