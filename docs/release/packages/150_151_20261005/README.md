# Frozen deployment package: migrations 150 + 151 and two function deploys (A, 2026-10-05)

**Status: PREPARED AND REHEARSED LOCALLY. NOTHING HERE IS AUTHORISED TO RUN AGAINST PRODUCTION.**
- Every production step below waits for the owner's own authorisation of that specific step.
- The operational choices O-R1–O-R4 are **open** and are not decided here.
- D registered independent expectations before delivery (`review/d-records-20261005 @ 7554d913`,
  `D_PACKAGE_EXPECTATIONS_150_151_20261005.md`, sha256 `eed961c9f1eaa094fb240bbe28368b969d89db9c738528422d8ffc6f3351654f`).
  D's PASS or STOP is still pending.

**Provenance.**
- `pkg.py` is **new code** that follows the design recorded in `PR93_PRODUCTION_EXECUTION_PACKAGE_20260924.md` §4–§10.
- The executed 147–149 scripts were never committed and are not recoverable; this is not a reconstruction of them.
- This package is committed in full so that it cannot be lost the same way.

## 1. Frozen inputs

| File | Source | git blob | sha256 |
|---|---|---|---|
| `frozen/migrations/20260925000000_refund_lifecycle_state.sql` (150) | PR #94 head `2eebc5bf1b8d1556981224b0b2775ba628e47828` | `b7ef57fa…` | `5b4f56f7…12f1` |
| `frozen/rollbacks/20260925000000_refund_lifecycle_state_rollback.sql` | same | `7122bcc1…` | `2ff67552…74c5` |
| `frozen/migrations/20260925010000_release_stuck_seller_win.sql` (151) | PR #95 head `9a66f29dc7249b62c60610ba77f234910255af96` | `cb9fa6aa…` | `f805d494…3bf4` |
| `frozen/rollbacks/20260925010000_release_stuck_seller_win_rollback.sql` | same | `3b06fb0e…` | `d8afbbaf…1c14` |
| `frozen/functions_manifest.json` | the import closure of each function's `index.ts` (`pkg.py fnmanifest`) | — | see `frozen.sha256` |

**Function bundles:**
- **stripe-webhook:** 3 files. `index.ts` changes (`7c2ae402…` → `2a5c4631…`); `_shared/sentry.ts` and
  `_shared/stripe.ts` are unchanged.
  - Previous: **v42**, from `5b255838` (SS:1416); `verify_jwt` false.
- **enforce-transfer-expiry:** 6 files. `index.ts` changes (`1425ec34…` → `24bde557…`); the 5 shared files are unchanged.
  - Previous: **v41**, from `e73553d2` (P92:473); `verify_jwt` true.
- **Closure check:** the closure computed at `e73553d2` is the recorded 6-file v41 bundle.

**Expected states:**
- `expected/pre150.txt` is the **observed** production-shaped baseline.
- `expected/post150.txt` (= `pre151.txt`) and `expected/post151.txt` were **predicted before any apply**. Function md5s
  come from the frozen migration text, the rest from the DDL.
- **Census:**
  - from the gate's `ci.yml` queries: 32|108|37|38 before, 34|111|37|40 after 150, unchanged by 151;
  - the candidate's stale 31|96|37|35 is not used.

## 2. Sequence (the plan's X1–X4; each step a separate owner authorisation)

Every PROD command needs `MODE=PROD CONFIRM_REF=hqycwntpfoztoinemqns`.

| Step | Command | STOP / FAIL behaviour |
|---|---|---|
| X1a owner | visual dashboard check that auto-deploy is off; backup status | prudence against a concurrent `main` push. **A targeted apply itself needs no AUTODEPLOY confirmation** (D, E-27) |
| X1b transport proof | `pkg.py probe`. A read-only two-statement query; `TRANSPORT=cli` by default | if the CLI path rejects multi-statement input (it does over `--db-url`: "cannot insert multiple commands into a prepared statement"), use `TRANSPORT=http` with `SUPABASE_ACCESS_TOKEN`, the transport the 147–149 records prove (HTTP 201). **Untested against production by design** |
| X1c preflight read | `pkg.py check expected/pre150.txt` | any MISMATCH = STOP. The md5s in `pre150.txt` come from the gate replay; this read is what confirms production equals them (it covers F-PROD-REPO-DRIFT-1) |
| X2 | `pkg.py apply 150` | prestate STOP (exit 3) sends nothing. POST FAIL (exit 4) → §3 |
| X3 | `pkg.py apply 151` | same |
| X4a | `SRC_DIR=<detached checkout of 2eebc5bf> pkg.py deploy stripe-webhook --live` | before-version 42 / pre-download = `5b255838` / deploy `--use-api --no-verify-jwt` / after 43 / post-download = frozen |
| X4b | `SRC_DIR=… pkg.py deploy enforce-transfer-expiry --live` | before 41 / pre = `e73553d2` / deploy `--use-api` / after 42 / post = frozen |
| **— stop —** | **O-R1** (subscribe `refund.created/updated/failed`; after X4a, C3), **O-R2** (`refund_state_detection_enabled`; after O-R1, and only once O-R3 is decided), **O-R3** (who handles failed and pending refunds), **O-R4** (historical reconciliation read) | **owner decisions, OPEN** |

`deploy --live` reads function metadata over HTTPS and needs `SUPABASE_ACCESS_TOKEN`. The default `deploy` (PLAN) only
verifies `SRC_DIR` against the manifest and prints the commands.

## 3. Rollback (order matters)

- **Functions first:** redeploy v42/v41 from detached checkouts of `5b255838`/`e73553d2`. The new functions call
  `record_refund_state`, so 150 must not be rolled back under them.
- **Then** `pkg.py rollback 151` and/or `pkg.py rollback 150`.
  - Each is guarded: it refuses unless the state equals the migration's post-state.
  - The request is the frozen rollback file, followed by a ledger delete that only fires once the objects are gone.
- **Resume after a partial rollback:** `pkg.py rollback <n> --ledger-only`. It refuses while the migration's objects are
  live.
- **150's rollback drops the refund-state tables, and their rows with them** (the file header says so). Before X4 nothing
  writes them. After X4, export first. Unlike 151's, 150's rollback file has no body guard; the package's state guard is
  what stands in front of it.

## 4. Local rehearsal (2026-10-05/06; predictions registered first: `rehearsal/predictions.txt`, sha256 `ed934082…`)

**Database:** `pkg150_rehears`, the LC_ALL=C replay of gate `037092f0` **minus 121/125/126** (162 files, census
32|108|37|38, 12 `ops.setting` rows, detectors on), plus a **162-row stand-in ledger** (max `20260924120000`). The
transport was `psql -c`: the identical request text as one simple query, i.e. one implicit transaction.

| Run | Result | vs prediction |
|---|---|---|
| R0 check pre150 | PASS | match |
| R1 DRY | apply_150 45,287 B `8e930001…`; apply_151 13,339 B `908607ca…`; rollback_150 `7ddf9c48…`; rollback_151 `b3efdfdd…`; ledger-only `ec1a3b2b…` | — |
| R2 apply 150 | prestate PASS; POST PASS: **every predicted key, including md5s computed from the text** | match |
| R3 NEG apply 150 again | STOP exit 3; exactly the 14 predicted MISMATCH keys + the 3 new `fn_public.*` keys | match |
| R4 rollback 150 | guard PASS; restored = pre150 | match |
| R5 NEG rollback 150 again | STOP exit 3 | match |
| R6 apply 150, apply 151 | both PASS | match |
| R7 NEG apply 151 again | STOP exit 3; exactly 4 keys (ledger_count, ledger_max, ledger_151, detect_release_stuck) | match |
| R8 partial rollback (file only) | full rollback STOP (1 key: detect_release_stuck); `--ledger-only` PASS → pre151 | match |
| R8c control | `--ledger-only` with 151's body live: STOP exit 3; ledger stays 164 | match |
| R9 pgTAP | 217 @`2eebc5bf` 45/45; 218 @`9a66f29d` 17/17 | match. The harness then leaves 1,098 pgTAP functions in `public`; the non-pgTAP count stays 111. Hence R9 runs last |
| R10 DRY again | all five request hashes identical to R1 | match |
| R11 deploy PLAN, `SRC_DIR` = `2eebc5bf` | stripe-webhook 3/3, enforce-transfer-expiry 6/6, 0 mismatches | added (no prediction registered) |
| R12 NEG deploy PLAN, `SRC_DIR` = gate `037092f0` | source STOP exit 3: exactly `stripe-webhook/index.ts` (`7c2ae402` ≠ `2a5c4631`) | added control |

Full log: `rehearsal/run_20261005.log`.

## 5. What this rehearsal cannot show

- **The production transport** (X1b) and **the production bodies**: X1c reads them at execution.
- **The function deploy and download path.** Only PLAN mode was exercised here. The live path is reviewed by reading.
- **The real ledger table's columns:** the insert uses `version, name, statements, created_by`, as 147–149 did.
- **Any behaviour of real refunds.** No Stripe call and no data write beyond the migrations is in scope.
