# Production execution package — migration 149 + `confirm-and-release` (A, 2026-09-24)

**Status: EXECUTED 2026-09-24 20:29–20:31Z under the owner's authorisation (A-149 + B-149 + V-3). All PASS; no rollback. See §12.**
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

## 12. Execution record (owner authorisation 2026-09-24: A-149 + B-149 rollback + V-3 probe, package `dddb93a7`)

**Before any step:**
- Frozen artefacts: `FROZEN_SHA256.txt` `8305d966…`, 16/16 on sha256 and size.
- The package doc is unchanged since `dddb93a7`.
- Gate tip `037092f0` and `main` `eadd456a`, both unchanged. `gate149` clean at `037092f0`; `gate5b` clean at `5b255838`.
- `deploy_one.sh` `029c6af7…`; CLI 2.115.0.
- Dry-run leftovers moved out of `out/`.
- A's predictions registered at 20:27:48Z (`exec_predictions.txt` `528eb22f…`), including the defn-only-mismatch
  contingency.
- **D registered its expectations blind at 20:29:36Z** (sha256 `10942503…`).
- **D's W0 PASS at 20:30:14Z** came from D's own production reads: every stop value, the 14 function versions and
  `payout_decisions` 4.

| Step | UTC | Result | vs prediction |
|---|---|---|---|
| P1 `deploy_149.sh --dry` | 20:29:58 | v37, ezbr `3b033bb8…`, `verify_jwt` True; pre-download 5/5 = `5b255838` | match |
| P2 `00` | 20:30:12 | ledger 161, no 149 row; census 32/108/37/38; 69 grant rows (`00_grants.txt` `9955f5d9…`, byte-identical to 148's post-apply read); switches detectors true, refund-detector false, alert delivery false | match |
| P3 `01 prestate` | 20:30:20 | **11/11 STOP keys equal.** This is the first production read of a3/a4: prosrc `6a8372b4…`/`d86c2b36…` = the repo, and **the replay-derived defn pins `f8ffef47…`/`e26a538c…` matched production** (n=2 with 148). Info: ACLs postgres + service_role; dispute_resolutions 0; open disputes 5; payout_attempts 0; **payout_decisions 4** (not predicted, never read before; D read the same 4); seller-win rows 0 | match |
| **Apply `01`** | **20:31:03** | P3 re-run 11/11 PASS; the request `01_apply.sql` `f1bb0489…` = the rehearsed request, byte for byte; **HTTP 201** | match |
| POST assertion | 20:31:05 | **PASS**, 15 checks plus grants. Ledger row `20260924120000 \| payout_decisions_buyer_confirmed_truth \| created_by=claude-a/owner-authorised-149 \| stmts=1`; ledger **162**; `stmt_md5` `7e4d3b2d…` = D's anchor; a3 `255e9022…`/`62f74728…`, a4 `0d692f32…`/`03ea4589…`, secdef, search_path=public, service_role only; claim148 and notify148 intact; census and switches unchanged; grants `01` == `00` | match |
| **Deploy** | **20:31:13–20:31:30** | before v37 (guard passed); pre-download 5/5 = `5b255838`; deploy rc 0; **after v38**, ezbr `f4b61150…`, `verify_jwt` True, updated_at 1790281880378 ms; **post-download 5/5 = `037092f0`** | match |
| **V-3 probe** | **20:31:39** | HTTP 200, body `ok`, `access-control-allow-methods: POST, OPTIONS`, `x-frame-options: DENY` → **PASS** | match |

- **Rollback: not needed.** B-149 was not exercised.
- **Not done, outside the authorisation:** no dispute was resolved; no payment, payout or refund path was invoked; no
  other function was deployed; no other migration was applied; `main` is untouched; no app build.
- Output sha256 values are in the sprint status and in D's W2 request. The outputs are in `scratchpad/apply_149/out/`
  and `edge/out/`.

**Evidence limits:**
1. The changed code paths are deployed but not exercised in production. a1/a2 run only on a buyer's POST for a row
   with no buyer confirmation; a3/a4 run only on a reversal. None occurs on its own, and none was triggered, since the
   authorisation excluded invoking payment or payout paths. Their evidence stays pgTAP 216 (with D's independent
   red/green), vitest BC-* / SW-AUDIT-*, and the mutants.
2. The probe proves the v38 bundle boots. It exercises none of the changed code, and attributes the version by timing
   (after the deploy read-back).
3. Stripe was not read. No payout attempt and no Stripe-calling path was invoked by any step.
4. The 4 existing `payout_decisions` rows were counted, not inspected. The migration does not rewrite existing audit
   rows; any past row with a false `buyer_confirmed` stays as written.
5. ~~D's W2 pending~~ **D's W2 PASS at 20:32:18Z**, from D's own reads, below.

**D's independent witness.** D registered its expectations blind at 20:29:36Z, and W0 passed at 20:30:14Z.
**W2 PASS at 20:32:18Z**; no stop condition fired, and every blind expectation was met. D's own reads:
- **Database:**
  - ledger 162, max `20260924120000`; the 149 row with `created_by=claude-a/owner-authorised-149`, `stmts=1` and
    `stmt_md5` `7e4d3b2d…`, which is D's anchor. So reviewed blob → applied text → recorded text is closed in A's
    script and in D's read independently.
  - 148's row and both its bodies are untouched.
  - a3 `255e9022…`/`62f74728…` and a4 `0d692f32…`/`03ea4589…`, with bindings, secdef, search_path, service_role-only
    ACLs and owner as expected.
  - Census 32/108/37/38; grants md5 identical to D's W0 (D's own serialisation); switches unchanged; alert delivery off.
- **Window invariants, counted rather than inferred from intent:** payout_attempts 0→0, payout_decisions 4→4,
  dispute_resolutions 0→0, seller-win rows 0→0.
- **Edge**, from D's GET and D's **own** download:
  - Exactly one of the 14 functions changed: `confirm-and-release` v37→v38, `verify_jwt` True, ACTIVE, updated
    20:31:20.378Z (= A's 1790281880378 ms). ezbr `f4b61150…`.
  - D's download is 5/5 sha256-identical to the `037092f0` blobs, with no extra `_shared` file.
  - D's control: the deployed `payouts.ts` differs from `5b255838`'s, so the comparison is non-vacuous.
  - `enforce-transfer-expiry` is still v41; the other 12 are byte-stable.
- **GitHub:** `main` `eadd456a` has not moved; the gate tip is `037092f0`.
- **The probe** is witnessed from A's recorded output only. D did not call the endpoint, which is outside D's scope,
  so the probe line carries A's evidence class.
- **D's evidence boundary, quoted:**
  - (1) nothing establishes that v38 has served a request beyond A's probe, which is attributed by timing;
  - (2) a1–a4 and the hold refusal remain unexercised in production (zero seller-win rows, zero attempts). Their
    evidence is 216's two-party red/green, CI 96/5543 and vitest. The first production exercise is E-5;
  - (3) Stripe is unread, bounded by attempts 0→0 and claim-before-POST;
  - (4) the 4 `payout_decisions` rows were counted, never inspected.
- **Method note (D):** the replay-derived defn pins are now measured true against production for both functions at 148
  and again at 149 (n=2).
