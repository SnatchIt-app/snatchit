# Frozen deployment package: migrations 150 + 151 and two function deploys (A, 2026-10-05)

**Status: EXECUTED IN PRODUCTION 2026-10-08 (X1b–X4b), owner-authorised 2026-10-07 (item 4). See §6.** (Superseded: "prepared and rehearsed locally; nothing authorised".)
- Every production step below waits for the owner's own authorisation of that specific step.
- The operational choices O-R1–O-R4 are **open** and are not decided here.
- D registered independent expectations before delivery (`review/d-records-20261005 @ 7554d913`,
  `D_PACKAGE_EXPECTATIONS_150_151_20261005.md`, sha256 `eed961c9f1eaa094fb240bbe28368b969d89db9c738528422d8ffc6f3351654f`).
- D's first verdict: 26 of 28 blocking expectations met. **E-18 and E-24 were unmet**, and D raised findings **F-1 and F-2**.
  All four are addressed in this revision (§2, §2A, §3, §4); rehearsal v2 re-ran everything.
- **D PASS at `887cb49a` (2026-10-06): all 28 blocking expectations met.** D independently rebuilt both apply requests
  (45,287 B `8e930001`; 13,339 B `908607ca`). **Scope of the PASS:** the package as written and rehearsed. Not the
  production transport, which X1b must establish before X2, and not any real failed-refund path.

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
| X1b transport proof | `pkg.py probe`. Three read-only statements in **one** request. It passes only if a transaction-local setting survives to the last statement (`same_txn=true`), which proves one request = one transaction (F-1). **Default `TRANSPORT=http`** (`SUPABASE_ACCESS_TOKEN`, never printed), the transport the 147–149 records prove (HTTP 201). `TRANSPORT=cli` is opt-in and was never exercised for a multi-statement write (over `--db-url` the CLI rejects one: "cannot insert multiple commands into a prepared statement") | anything but `same_txn=true` = STOP. **Untested against production by design** |
| X1c preflight read | `pkg.py check expected/pre150.txt` | any MISMATCH = STOP. The md5s in `pre150.txt` come from the gate replay; this read is what confirms production equals them (it covers F-PROD-REPO-DRIFT-1) |
| X2 | `pkg.py apply 150` | prestate STOP (exit 3) sends nothing. POST FAIL (exit 4) → §3 |
| X3 | `pkg.py apply 151` | same. **151 is live on apply (E-18).**<br>- There is no per-detector switch: `detectors_enabled` is true (pre150) and `ops-detect-tick` runs `ops.run_all_detectors()` every 5 minutes (117:1123), so the new dating takes effect within 5 minutes.<br>- It changes **only seller-win rows** (`buyer_confirmed`, `buyer_confirmed_at` NULL, `resolved_seller_paid`). Every other row is dated exactly as before, so no other case changes.<br>- **What a first run can open:** a p2 `release_stuck` case for each seller-win payout still unpaid more than 30 minutes after it became payable, or in manual_review, or held with no end.<br>- The records show **no dispute resolved** as of 2026-09-24 02:29Z (5 open). Any resolved since would be visible only in a production read.<br>- No money moves. Alert delivery is off, so a case is seen in `/cases` only |
| X4a | `SRC_DIR=<detached checkout of 2eebc5bf> pkg.py deploy stripe-webhook --live` | before-version 42 / pre-download = `5b255838` / deploy `--use-api --no-verify-jwt` / after 43 / post-download = frozen |
| X4b | `SRC_DIR=… pkg.py deploy enforce-transfer-expiry --live` | before 41 / pre = `e73553d2` / deploy `--use-api` / after 42 / post = frozen |
| (resume) | `pkg.py apply <n> --ledger-only` | only if POST shows the migration's objects in place **without** its ledger row (a split transport). It refuses otherwise (F-1; rehearsal R14/R14c) |
| **— stop —** | **O-R1** (subscribe `refund.created/updated/failed`; after X4a, C3), **O-R2** (`refund_state_detection_enabled`; after O-R1, and only once O-R3 is decided), **O-R3** (who handles failed and pending refunds), **O-R4** (historical reconciliation read) | **owner decisions, OPEN** |

### 2A. A failed refund while O-R3 is undecided: the interim state, stated (E-24)

- **After X2 + X4, before O-R1:** `refund.*` events are not subscribed. A later failure reaches the database only via
  `charge.refunded` (each listed refund recorded with its own status) or the expiry job's reconcile of its own refunds.
  Otherwise it is **not observed at all**.
- **Once observed:**
  - the refund's row says `failed` and `payments.refund_failed_cents > 0`;
  - the expiry job **parks** that payment (`refund_failed_cents = 0` is required for automatic handling), so it never
    re-refunds automatically;
  - the app still says "Refund of $X initiated" (ruling 3);
  - **nobody contacts the buyer.**
- **After O-R2 (detection on):** a p1 `refund_failed` case opens in `/cases`. With alert delivery off and **no O-R3
  owner, nobody is notified and nobody acts.**
- That is why O-R2 is sequenced after O-R3 is decided, and why O-R3 is a submission prerequisite (plan §6.0 D6).

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
- **150's rollback drops the refund-state tables, and their rows with them.**
  - The state guard now includes `payment_refund_state_rows=0` and `payment_refund_state_log_rows=0` (F-2). So once the
    functions have written **any** row, `rollback 150` **STOPs** (rehearsal R15). The guard does the work, not an
    instruction.
  - Rolling back with rows present is outside this package: export first, then an owner decision on a manual drop.

## 4. Local rehearsal

**Database and transport.**
- **v1** (2026-10-05) ran on `pkg150_rehears`; its log is `rehearsal/run_20261005.log`, predictions `ed934082…`.
- **v2** (2026-10-06, after D's review) ran on a **fresh** `pkg151_rehears`: the LC_ALL=C replay of gate `037092f0`
  **minus 121/125/126** (census 32|108|37|38, 12 `ops.setting` rows, detectors on) plus a **162-row stand-in ledger**.
  Predictions were registered first (`rehearsal/predictions_v2.txt`, `61de833a…`); the log is
  `rehearsal/run_v2_20261006.log`.
- The transport was `psql -c`: the identical request text as one simple query, i.e. one implicit transaction.

| Run | v2 result | vs prediction |
|---|---|---|
| R0 check pre150 (row keys `absent`) | PASS | match |
| R1 DRY | apply_150 `8e930001…` and apply_151 `908607ca…`, **unchanged from v1**; rollback_150 `7ddf9c48…`; rollback_151 `b3efdfdd…`; rollback ledger-only `ec1a3b2b…`; apply_151 ledger-only `650a81d2…` | match |
| R2 apply 150 | prestate PASS; POST PASS on every predicted key (md5s from the text; rows 0) | match |
| R3 NEG apply 150 again | STOP exit 3; **16** MISMATCH (v1's 14 + the two row keys) + 3 UNEXPECTED | match |
| R4 rollback 150 | PASS → pre150 | match |
| R5 NEG rollback 150 again | STOP exit 3 | match |
| R6 apply 150, apply 151 | PASS, PASS | match |
| R7 NEG apply 151 again | STOP exit 3; 4 keys | match |
| R8 partial rollback (file only) | full rollback STOP (1 key) → `--ledger-only` PASS | match |
| R8c control | ledger-only with 151's body live: STOP; ledger 164 | match |
| **R13 probe** | last row `same_txn=true`, PASS | match |
| **R14 partial apply (file only, no ledger row)** | `apply 151` STOP (1 key: detect_release_stuck) → `apply 151 --ledger-only` PASS → post151 | match |
| **R14c control** | `apply 151 --ledger-only` with the row present: STOP; ledger 164 | match |
| **R15 row guard** | one `payment_refund_state` row inserted (local; FK triggers suspended) → `rollback 150` STOP with exactly 1 key (`payment_refund_state_rows` 0 ≠ 1) → row deleted → `rollback 150` PASS | match |
| R9 pgTAP | 217 @`2eebc5bf` 45/45; 218 @`9a66f29d` 17/17 | match. **No red control here (E-29):** the RED runs are in #94's and #95's records. The harness leaves pgTAP's 1,098 functions in `public`, which is why R9 runs last |
| R10 DRY again | all six request hashes identical to R1 | match |
| R11/R12 deploy PLAN | `2eebc5bf` accepted 3/3 and 6/6; the gate refused on exactly `stripe-webhook/index.ts` | match |

## 5. What this rehearsal cannot show

- **The production transport** (X1b) and **the production bodies**: X1c reads them at execution.
- **The function deploy and download path.** Only PLAN mode was exercised here. The live path is reviewed by reading.
- **The real ledger table's columns:** the insert uses `version, name, statements, created_by`, as 147–149 did.
- **Any behaviour of real refunds.** No Stripe call and no data write beyond the migrations is in scope.

## 6. Production execution, 2026-10-08 (A executes; D witnesses against `cc94532c` and amendment `04d756be`)

The token came from the Supabase CLI keychain entry, loaded into the process environment only and never printed.
Transport: HTTP to the Management API.

| Step | UTC | Result |
|---|---|---|
| X1a prudence | 02:3x | Physical backups are daily; latest 2026-10-07 13:51:18Z COMPLETED; PITR off. Default branch `git_branch` `''` |
| X1b probe | before X2 | HTTP 201, `same_txn=true`. **PASS** |
| X1c / W0 | 02:36:37 (re-read) | `check pre150` exit 0. Full state, 21 rows, **identical** to `pre150.txt` and to the first W0. Control against `post150` gives 19 MISMATCH, exit 3. D's own W0 PASS: `9434cbf7`. `frozen.sha256` 16/16 OK; DRY request hashes as rehearsed |
| X2 apply 150 | 02:37:17–22 | prestate PASS; request `8e930001…` (45,287 B), HTTP 201; POST matched `post150.txt`. **W1:** 24 rows identical to `post150.txt` (sha256 `26cd383c…`); ledger 163; census 34\|111\|37\|40; `record_payment_refund` `08924da5…` unchanged; detection `false`; rows 0 |
| X3 apply 151 | 02:37:56–38:03 | prestate PASS; request `908607ca…` (13,339 B), HTTP 201; POST matched `post151.txt`. **W2:** identical to `post151.txt`; exactly 4 keys changed (`detect_release_stuck` `12ed7fc2`→`6e0a9c5d`, `ledger_151`, count 164, max) |
| X4a stripe-webhook | 02:38:44–39:11 | v42→**v43**, `verify_jwt` false, ezbr `e4239d64…`→`425c1e63…`; pre-download equals `5b255838`'s manifest; post-download equals frozen (3/3). Boot probe: unsigned POST gives 400 "Invalid signature" (no DB access) |
| X4b enforce-transfer-expiry | 02:39:48–40:05 | v41→**v42**, `verify_jwt` true, ezbr `d7410c97…`→`d6c898ce…`; pre-download equals `e73553d2` (6/6); post-download equals frozen (6/6) |
| Detector after 151 | tick 02:40:01 | `release_stuck` succeeded, scanned 0, opened 0; `refunds` succeeded, scanned 2, opened 0. Open cases of these types: 2 pre-existing `refund_pending` (2026-09-08) |
| Expiry run check | 02:42:01, 02:44:00 | both post-deploy runs on v42: HTTP 200, not timed out, `errors` 0 (= baseline). **Limit:** the response bodies are byte-length identical to the baseline (326). This shows v42 *runs without erroring*, not that its new seller-win path ran: there are no seller-win candidates. It is not behavioural coverage |

No guarded recovery or rollback was needed. The rollback boundary from here on:
- functions first, to v42/v41 from `5b255838`/`e73553d2`;
- then `rollback 151` / `rollback 150`, each guarded. **`rollback 150` STOPs once any refund-state row exists** (F-2).
