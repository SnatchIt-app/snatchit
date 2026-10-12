# D — independent C4 verification and candidate-safety verdict, RC-20261012 (2026-10-12)

**Who:** Claude D, session `9651e05a` (fork), independent release-safety reviewer. Working only from the SSD
(`repos/snatchit-drecords`, branch `review/d-records-20261005`). Retired D session `675d5134` is not this session.
**Keyed to:** `integration/rc-20261012` @ **`48d20ca1c0d0d53ce51c295c44447f3548496aa8`** (tree `7feadf07`), base gate
`abef9506`, per A's `CANDIDATE_MANIFEST.md` (frozen 04:19Z). The earlier trial `5450b348` is **not** tree-identical:
`git diff --stat 5450b348 48d20ca1` = 14 files (3 `admin/`, 11 `web/`); every one of those files is inside the roots I
scanned at `48d20ca1` (§2), so nothing below rests on the trial.
**What this session did not do:** no production write, refund, payout, setting change, deployment or migration; no rerun
of the historical refund reconciliation; the five excluded test-mode payments untouched; no force push. One fresh
**read-only configuration read** was made, with its purpose stated (§4.3). Everything else is local: git, the local
schema clone `pkg151_rehears`, the GitHub API read-only (`gh run view`, `gh api …/rulesets`).

> **Superseded candidate (A's message, 2026-10-12 ~04:50Z): `48d20ca1` is no longer the shipping candidate.** C's
> read-only critical-flow audit found seven defects, confirmed by A at source — three money-truth (F4: the 3-D Secure
> return drops the checkout mode, so a Buy Now buyer can take the auction path; F5: payout-return claims "Connected"
> unconditionally; F6: a race between the settled-payment read and the listing read shows "Nothing was charged" after a
> charge) and four others (F1 crash on a bad deep-link param; F2 listing edit "Saved" with 0 rows written; F3 signup
> profile-write failure swallowed; F7 recovery hold not released on a failed `verifyOtp`). RC2 = this line +
> `v3/rc-fixes-20261012` (C: F1–F5, F7) + `fix/rc-f6-settled-recheck-20261012` (A: F6, `50e74efb`).
> **Stated plainly: neither my own checks nor the integration/security sub-review (§3.2) surfaced F1–F7.** The
> sub-review verified server authority over amounts, enumerations and RPC ownership checks; it did not walk the 3-D
> Secure return path, the payout-return copy's truth condition, the settled-read/listing-read ordering, parameter
> validation on deep links, or write-count checks on edits. Those are the classes C's audit covered and this review did
> not — a limit of this record, not a disagreement with C.
> **What stands and what is redone at RC2:** §2's method, controls, negative control and blind-spot list stand, but
> **C4 is rerun at the RC2 sha over both roots** (F2 adds a select on the listing update, so the read surface changes);
> §4 (migration scope, AUTODEPLOY read, rollback) stands unless RC2 touches `supabase/` or `.github/` (checked by diff
> at RC2); §3.1 (rulesets, CI permissions) stands; §1 and the CI result are re-done at RC2; §3.2 is supplemented by a
> targeted review of the fix commits. The RC2 review will be a separate D record.

## 1. Candidate identity — A's claims, independently checked

| A's claim (manifest) | My check | Result |
|---|---|---|
| `48d20ca1` on origin, tree `7feadf07…` | `git rev-parse origin/integration/rc-20261012`; `git log -1 --format=%t` | match |
| parents `08409f55` (S4) + `d27aa449` (v3) | `git rev-parse 48d20ca1^@` | match |
| `app/ src/ packages/` = `d27aa449` | `git diff --stat d27aa449 48d20ca1 -- app src packages` | empty |
| `supabase/` = gate `abef9506` | `git diff --stat abef9506 48d20ca1 -- supabase` | empty |
| `web/` = live `0b389584`; `admin/` = live `f7e7e85f` | `git diff --stat` each | empty, empty |
| 14 files vs trial `5450b348`: 3 admin, 11 web | `git diff --name-only 5450b348 48d20ca1` | 3 + 11, nothing else |
| `.github/` unchanged from gate | `git diff --stat abef9506 48d20ca1 -- .github` | empty |
| CI run 38203105234 green | `gh run view … --json` | `conclusion: success`; 5/5 jobs success; **0 steps with a non-success conclusion** (none skipped) |

## 2. C4 — the static client-read check, verified independently

### 2.1 What A's scanner is, and reproduction
`docs/release/packages/S5_candidate_20261011/c4_client_read_check.py` (cc68f284): a regex walk over `.ts/.tsx` under the
given root, resolving literal `.from()/.select()/filters/.insert|update|upsert/.rpc()` names against
`information_schema.columns` + `pg_proc.proargnames` of a local database. Schema used: `pkg151_rehears` (164 ledger
rows, max `20260925010000` — my local read). Its equality to production rests on the recorded 150/151 execution
witness (`D_WITNESS_150_151_EXECUTION_20261008.md`: ledger 162→164), **not** on a fresh production read.

| Run (D, unmodified scanner) | resolved | MISSING | UNRESOLVED | exit |
|---|---|---|---|---|
| `app/ src/ packages/` @ `9bbeaec6` (A's input) | 63 from / 25 rpc | 0 | 16 | 0 — identical to A's `out/c4_run_9bbeaec6.txt` |
| same roots @ `d27aa449` | 63 / 25 | 0 | 16 | 0 — identical findings |
| same roots @ **`48d20ca1`** | 63 / 25 | 0 | 16 | 0 — identical findings |
| **`web/ admin/` @ `48d20ca1`** (not in A's C4) | 30 / 9 | 0 | 16 | 0 |

### 2.2 Negative control — the check is not vacuous
Same scanner, same source, database `postgres` (0 rows in the catalog query): **MISSING 88, exit 1** (every table and
every function reported missing). The catalog is consulted and a wrong schema fails the run.

### 2.3 Site reconciliation — every `.from(`/`.rpc(` accounted for
Independent enumeration (`grep`, all `.ts/.tsx`, tests excluded) of `app/ src/ packages/` @ `48d20ca1`: **125** lines
with `.from(` or `.rpc(`; 18 are `Array.from`/`Uint8Array.from`/`utf8.from`/`supabase.storage.from`. Of the remaining
107, an instrumented copy of the scanner (prints each counted site; logic unchanged) shows: 63 counted `from` + 25
counted `rpc` + 16 UNRESOLVED = 104 **touched**; the other 3 plus 3 more are comment lines (`useListingRealtime.ts:10,11,
123`, `useBlockedUserIds.ts:82`, `types/index.ts:34`) or a two-line `storage.from(BUCKET)` (`avatarImage.ts:153`),
all correctly skipped. Five `where` values differ by one line from my grep because the scanner reports the preceding
`.schema('kernel'|'venue')` line. **Nothing is unaccounted for.** `web/ admin/`: 41 supabase sites by grep, 41 touched
(30+9+16, with `transfers.ts:117/132` each counted once by grep and three/two times by the scanner — one `where` per
`.from` inside a `Promise.all`); the 5 scanner-only sites are `Array.from` in `loading.tsx` files.

### 2.4 D's planted-defect controls (new file `src/lib/zz_d_controls.ts` + `.js`, in a copy)
A's five mutants covered: a select column, a table, an RPC name, an RPC argument, a second RPC argument. **None covered a
filter column, a write key, an embedded-relation column, or `.schema()`.** Mine:

| # | Planted defect | Expected | Result |
|---|---|---|---|
| D01 | `.eq('zz_bogus')` on `listings` | MISSING | **caught** (eq) |
| D02 | `.update({ zz_bogus })` | MISSING | **caught** (update) |
| D03 | `select('*, profiles(zz_bogus)')` on `bids` | MISSING | **caught** (embedded column) |
| D04 | `select('zz_rel(id)')` unknown relation | UNRESOLVED | UNRESOLVED — FK-named embeds are never verified |
| D11 | `.schema('venue').from('zz_bogus')` | MISSING | **caught** (venue.zz_bogus) |
| D12 | `.order('zz_bogus')` | MISSING | **caught** |
| D13 | `.in('zz_bogus', …)` | MISSING | **caught** |
| D15 | `.upsert({ zz_bogus }, { onConflict })` | MISSING | **caught** |
| D05 | `.match({ zz_bogus: 1 })` | — | **silent** (object arg never read) |
| D06 | `.filter('zz_bogus', 'eq', 1)` | — | **silent** (`filter` explicitly skipped) |
| D07 | `.not('zz_bogus', 'is', null)` | — | **silent** (`not` explicitly skipped) |
| D08 | `let q = …select('id'); q = q.eq('zz_bogus', 1)` | — | **silent** (a chain extended in a later statement is never seen) |
| D09 | `const v = supabase.schema('venue'); v.from('listings')` | — | **silent and a FALSE PASS**: resolved as `public.listings` (exists); `venue.listings` does not exist |
| D10 | `const s = 'a//b'; await supabase.from('listings').select('zz_bogus')` | — | **silent**: the `//` stripper cut the call |
| D16 | `` .from(`${x}`) `` | UNRESOLVED | **silent** (the docstring promises UNRESOLVED; the code `continue`s) |
| D17 | `.from('zz_bogus_table')` in a `.js` file | — | **silent** (`.js/.jsx/.mjs` never read) |

Also by construction: `.or()` is not in the scanner's filter set, so column names inside `.or('a.eq.x,b.ilike.y')` are
never checked; RPC argument checking is subset-only (fewer keys than the signature always passes); OUT-parameter names
count as acceptable argument keys.

### 2.5 Which blind spots the candidate actually exercises — resolved by hand against `pkg151_rehears`
| Pattern | Sites @ `48d20ca1` | Table | Columns | Exist? |
|---|---|---|---|---|
| held builder (D08) | `src/hooks/useListingRealtime.ts:131` `q = q.gt('created_at')` | `bids` (`.from('bids')` at :127) | `created_at` | yes |
| held builder (D08) | `web/src/lib/listings.ts:87-110` (`query = query.or/eq/lte/order`) | `listings` (:80) | `event_name, venue, category, neighborhood, buy_now_enabled, current_bid, created_at, ends_at` | all yes |
| `.or()` | `app/(tabs)/profile.tsx:157` | `listings` (:154) | `status, auction_status` | yes |
| `.or()` | `app/(tabs)/explore.tsx:165`; `web/src/lib/listings.ts:87` | `listings` | `event_name, venue` | yes |
| `.not()` via helper (D07+D08) | `src/hooks/useBlockedUserIds.ts:98` `applyBlockedSellerFilter` | callers `home.tsx:248,272,298`, `explore.tsx:161` — all `.from('listings')` | `seller_id` | yes |
| `.match`/`.filter` | none | | | |
| `.schema()` held in a variable (D09) | none — all 8 `.schema(` uses are adjacent to `.from/.rpc`; `src/lib/supabase.ts:101 createClient` sets no `db.schema`; web/admin clients likewise | | | |
| `//` inside a string on a call line (D10) | 0 call lines altered by the stripper (checked programmatically, both roots) | | | |
| interpolated table/RPC name (D16) | none | | | |
| `.js/.jsx/.mjs` with supabase calls (D17) | none under `app/ src/ packages/`; `admin/scripts/acceptance/gate-probe.mjs`, `admin/scripts/auth-stub.mjs` are scripts, not shipped client code | | | |
Note on the two `.or()`/`.not()` string interpolations: `explore.tsx:165` and `web listings.ts:87` strip `, ( ) % \`
from the user term before interpolating (`sanitize`/`replace(/[,()%\\]/g,' ')`); `useBlockedUserIds.ts:98` interpolates
`user_blocks.blocked_id` values (uuid column) — not attacker-shaped.

### 2.6 The dynamic (UNRESOLVED) sites — 16 mobile + 16 web/admin
Resolved by the schema/contract sub-review (read-only, `pkg151_rehears`), spot-checked by me (marked ✓D):
- **Mobile (16):** `notifications.tsx:111 .update({[key]})` → key ∈ the six `notify_*` toggles of
  `public.notification_preferences` (✓D: exactly those six columns + `user_id, updated_at` exist);
  `CheckoutNative.tsx:173` → `LISTING_SUMMARY_COLUMNS` = 8 `listings` columns; `useSecurityNotices.ts:33/98` →
  `get_my_security_notices()`, `mark_security_notices_read(p_ids uuid[])`; `useListingRealtime.ts:127/173` →
  `BIDS_SELECT` on `bids` with the `profiles` embed over the single FK `bids.bidder_id→profiles`;
  `payments.ts:357 settleRpc` ∈ {`complete_auction_payment`, `mark_listing_sold`}`(p_listing_id, p_user_id)`;
  `signOut.ts:95/181/259` → `revoke_push_token(p_token)` (the `:95` call is an injected dependency whose only live
  binding is that RPC), `revoke_all_push_bindings()`; `registerToken.ts:92/184/196` →
  `register_push_token(p_token, p_platform, p_device_secret, p_device_name)` and an insert of
  `{user_id, token, platform, is_active}` into `push_tokens`; `venue/client.ts:87/93/99` → 7 `venue.*`, 2 `catalog.*`,
  1 `kernel.*` functions, all present — and **confirmed unreachable**: no import of `src/lib/venue` outside that
  directory (A's claim holds).
- **Web/admin (16):** `useListingBids.ts` `BIDS_SELECT`; `notifications.ts` 7 columns of `notifications`;
  `favorites.ts` `saved_listings` + `listings` embed; `checkout.ts:163` the same two settle RPCs; `sales.ts`
  `SALE_COLUMNS` on `transfers` with `profiles!buyer_id`, `listings!listing_id`, `payments!payment_id` embeds (FKs
  present); `listings.ts` `LISTING_COLUMNS` (24 columns); `transfers.ts` `TRANSFER_COLUMNS` (15) + three FK-hinted embeds;
  `seller-listings.ts` `SELLER_LISTING_COLUMNS`; **`admin/src/lib/ops.ts:23`** → every caller literal enumerated: **26
  distinct `ops.*` RPCs**, each with `proargnames` ⊇ the keys passed (✓D: `execute_action` 8 keys, `approve_action` 3);
  the only generic caller `GenericRpc` is never rendered.
- **Result: every dynamic site resolves to objects that exist at ledger 164. No MISSING.**

### 2.7 What C4 proves, and what it does not
- Proves: at `48d20ca1`, every **literal** table/view, selected or embedded column, filter column (for the filter
  methods the scanner knows), write key, RPC name and RPC argument key in `app/ src/ packages/ web/ admin/` exists in a
  schema equal to ledger 164; and (by §2.5–2.6) so does every hand-resolved dynamic one. Reproduced by me, not taken from
  A's report.
- Does not prove: column privileges, RLS, argument **types**, return shapes, required-argument completeness, or that
  `pkg151_rehears` equals production today (it equals the ledger-164 state witnessed on 2026-10-08).
- Scanner limits (for the record; optional fixes): §2.4 D05–D10, D16, D17, `.or()`, subset-only args.

### 2.8 C4 verdict
**PASS at `48d20ca1`** for `app/ src/ packages/` **and** for `web/ admin/`, with the limits in §2.7. "MISSING 0" was
reproduced, shown non-vacuous (§2.2), reconciled site-by-site (§2.3), and extended by hand over the scanner's blind
spots that the candidate actually uses (§2.5).

## 3. Candidate-safety review of the S5 diff (`abef9506..48d20ca1`, `native/` excluded)
### 3.1 Controls I checked myself
- **Rulesets** (`gh api …/rulesets/<id>`, read-only): `gate-protection` (24623964) on
  `release/production-gate-20260918`: deletion, non-fast-forward, PR required, **allowed merge method = merge only**,
  0 approving reviews, **bypass_actors = []**, required checks = Immutability + ordering, Migrations apply cleanly, Typecheck/
  Lint/Unit, Web build, Admin console, Deno type-check. `main-protection` (21624091) on the default branch: deletion,
  non-fast-forward, **required_linear_history**, PR required, **allowed merge method = squash only**, 0 reviews,
  bypass_actors = [], required checks = Immutability, Migrations, Typecheck, Web build, **Secret scan (TruffleHog)**.
  A's description of both is accurate. Observations: neither ruleset requires a human review (single-owner repo);
  the gate ruleset does **not** require the secret scan — A's plan lists it as a precondition, which is a plan rule,
  not an enforced one; `main` does not require the Admin console or Deno checks.
- **Workflows at `48d20ca1`** (= gate): `ci.yml`, `migrations-guard.yml`, `security.yml` all declare `permissions: contents: read` at workflow level (`security.yml` adds `pull-requests: write` for a PR comment and `actions: read` for CodeQL); **no `secrets.*` is referenced by any workflow**; `ci.yml` runs on `pull_request → main` and on `push` to every non-`main` branch (run 38203105234 was the push to `integration/rc-20261012`), `migrations-guard.yml` on every `pull_request` and `merge_group`, `security.yml` on `pull_request → main`, weekly cron and dispatch. Nothing in CI can reach Supabase, Stripe, Vercel or EAS: there is no credential to do it with. A's "CI has `contents: read`" is accurate.
### 3.2 Integration/security review
Integration/security sub-review of `git diff abef9506 48d20ca1` (`native/` excluded; `app/ src/` of the rc
equal the trial's, so the sub-review's reading of `5450b348` is the same code), read-only; items marked ✓D I re-checked.
- **Money authority (PASSED):** amounts are server-decided — `createPaymentIntent` sends `expected_total_cents` and the
  server 409s on mismatch (`src/lib/payments.ts:219-233`); checkout renders only `serverBreakdown`; the Apple Pay cart
  uses the server's `result.amount`; fee constants re-export `money.ts` (0.10 unchanged). Settlement RPCs and
  `ensure_transfer_exists` unchanged; the new report-problem network-failure branch re-reads before claiming anything.
- **State truth (PASSED, one gap):** client enumerations for `transfers.status`, `dispute_resolution`,
  `payout_review_status` equal the SQL sets; `partially_refunded` is derived, never asserted; "released" only from
  `payout_released_at` (written solely by `record_transfer_payout`, service_role); `reversed` renders neutrally.
  **Gap D-RC-3 (non-blocking):** the buyer-facing refund line reads only the one-way record
  (`settledRead.ts:42`: `status, refunded_at, amount_refunded_cents, total`) and **nothing in `app/ src/` reads
  `refund_failed_cents` / `refund_succeeded_cents`** (✓D: 0 hits) although 150 is in the gate and keeps a later-failed
  refund inside that one-way record. A refund that fails after creation keeps rendering "Refund … initiated" — literally
  true, never "refunded", but the client never shows the less favourable server fact. This is the client side of the
  owner's standing distinction (execution/alert delivery ≠ detection); operators see failures via ops cases, buyers do not.
  Also: the refund sentence is keyed by `(listing_id, buyer_id)` rather than `transfers.payment_id`
  (`refundState.ts:495`), so with two settled rows the sentence can come from the other payment (rare; `youPaidAmount`
  already guards its own case); "report it from your order" copy over-generalises (`buyer_dispute_transfer` accepts only
  `seller_sent`).
- **Auth/session (PASSED):** `signOut.ts` ordering — bounded revoke (3 s) → mark session end → `auth.signOut` → only on
  success clear registration and dock avatar; on error nothing is cleared. The `.rpc(token)` at `:95` is the injected
  revoke dependency whose only live binding is `revoke_push_token` (✓ sub1 agrees). `sessionStore`, `sessionCipher`,
  `push/registerToken` are **unchanged** by the diff. Auth screens are presentation-only; `payout-return/refresh.tsx`
  read no URL state.
- **Operator reachability (PASSED):** no `schema('ops')`, admin RPC or `service_role` reference in the client; the full
  client verb inventory is 18 user-scoped RPCs + 3 edge functions; operator writers have EXECUTE revoked from
  `authenticated`. `app/_dev/*` (13 routes) ship in the production bundle but are **runtime-gated**
  (`_dev/_layout.tsx:23`: `IS_SANDBOX_BUILD || __DEV__`, both compile-time constants in a production build) — no test
  covers that gate.
- **Environment pairing (PASSED):** `eas.json` unchanged — sandbox profiles pair sandbox ref + `pk_test_`, production
  pairs prod ref + `pk_live_`; `envGuard.ts` fails closed at runtime (unroutable host + blocking screen); CI asserts the
  static pairing (`ci.yml:441`). Hard-coded refs in the diff (`scripts/dev-web-guard.sh`) agree with `envGuard.ts` and
  `assert-env-pairing.mjs`. **No key, JWT or secret is added by the diff.** Limit: no EAS `eas-build-pre-install` hook,
  so a local `eas build` with an edited env relies on the runtime guard alone.
- **Production side effects on merge/CI/install (PASSED, two notes):** `.github/` unchanged; nothing in the diff invokes
  `db push`, function deploy, Stripe, Vercel or EAS submit. **New `postinstall`** (`package.json:6` →
  `scripts/patch-stripe-interop.mjs`, ✓D) rewrites one header inside `node_modules/@stripe/stripe-react-native/ios/`,
  pinned to 0.50.3 and to upstream pre/post SHA-256, `exit(1)` on any drift (✓D) — no network, fail-closed; it does
  change the native artefact G2 compiles relative to the previously shipped build (A's listed native-build input).
  **Harness configuration in the public repo:** `.claude/launch.json` (4 lines with a personal `/Users/<name>/` path, 0
  secrets, ✓D) and simulator UDIDs in `tools/v3-capture/*.sh` — **pre-existing**: `.claude/launch.json` is already on the
  gate `abef9506` and on public `v3/midnight-app` (✓D); S5 modifies, not adds, it. Not a release-safety defect; it is
  contrary to the owner's standing rule on harness configuration and is recorded for the owner's decision (D-RC-2).
- **Tests (PASSED, one defect, six gaps):** strong display-truth coverage (`v3-transfer-cells`, `v3-refund-read-states`,
  `v3-dispute-outcome-read`, `v3-order-stage`, `report-problem-truthful`, `v3-checkout-view` CV1–10 import-graph
  isolation). **Defect D-RC-4 (non-blocking, same shape as ML7):** `tests/v3-harness-art-selection.test.ts:39-48` builds
  dates from local midnight via `toISOString()`; in any UTC+ zone `iso(0)` is yesterday and HA1/HA2 fail. ✓D reproduced
  with plain node: `TZ=Europe/Berlin` and `TZ=Asia/Tokyo` give `iso(0)` = previous day; `UTC` and `America/New_York`
  pass — so CI (UTC) and the developer Macs are green and the defect is latent. Gaps with no test: the `_dev` layout gate;
  `authStateHandler` SIGNED_OUT → `clearDockAvatar`; the Apple Pay label; the two-settled-rows refund line; rendering of
  a 150-lifecycle failed refund.

## 4. Migration scope, automatic application, rollback
### 4.1 Scope
- Gate `abef9506` carries 167 migration files; the ledger (pkg151_rehears = witnessed production state) has 164 rows.
  **Gate − ledger = exactly `121`, `125`, `126`** (my `comm` over versions). Ledger − gate = ∅.
- `origin/main` (`eadd456a`, 2026-09-01) lacks `076`…`115` and every later file; all of those except 121/125/126 are
  already in the ledger, so S7 (gate → main) is "migration-bearing" in git terms while its only **unapplied** content is
  121/125/126.
- The candidate changes nothing under `supabase/` (§1): **S5 and G2 apply no migration and deploy no function.**
### 4.2 A's deployment plan (`DEPLOYMENT_PLAN.md`) — step by step
- **Step 1 (gate PR):** "applies migrations automatically: no" — **agreed.** The gate is not a Supabase git binding
  (§4.3), CI has no deploy credential (§3.1), the ruleset forbids non-fast-forward. Production effect none.
- **Step 2 (G2/X11):** "no" — **agreed**; a binary only; backend unchanged; C4 shows the binary reads only objects that
  exist at ledger 164.
- **Step 3 (S7, gate → main):** "POSSIBLY" is the right word for the dashboard toggle (not API-visible), **but the
  plan's sentence "Per the records they are all already in the production ledger" is false**: 121, 125 and 126 are on
  the gate and not in the ledger. If automatic deployment were on, S7 would apply exactly those three to production
  (121 is a PFA-18C-adjacent function hardening). **FINDING D-RC-1 (documentation, must fix before S7):** the plan must
  name 121/125/126 as the files S7 would apply, and the post-merge check must assert the ledger is still 164 **and**
  that none of the three versions appears in it.
### 4.3 Fresh configuration read — exact purpose, scope, result
- **Purpose:** the owner's instruction is to report whether the deployment steps can auto-apply migrations without
  inferring it from a stale setting. The last evidence was 2026-08-27 (`AUTODEPLOY_1_CLOSURE_REPORT.md`). The
  mechanism that applied `071` was the production project's Supabase branch record being bound to git `main`
  (`git_branch: "main"`); the closure was that field going to `""`.
- **Read:** Supabase MCP `list_projects` then `list_branches(project_id=hqycwntpfoztoinemqns)` — the production project
  (the other project in the org, `aihgejwdvkvngjwttxij` "Pulse", is INACTIVE and unrelated). Read-only; no data table
  touched. **2026-10-12T04:27:03Z.**
- **Result:** one branch record: `id 99b9a6ff-16dc-4570-9749-cfedf99c8372`, `name main`, **`git_branch: ""`**,
  `is_default true`, `parent_project_ref = project_ref`, **`updated_at 2026-08-27T15:49:25Z`** — byte-identical to the
  closure report's "after" state. The git binding severed on 2026-08-27 has not been touched since.
- **What this shows / does not show:** as configured at 04:27Z, a push to `main` is not bound to the production
  project, so the `db push` path that applied 071 is closed. It does **not** show the dashboard's deploy-on-merge
  label (no API surface, per the closure report), and it is a point-in-time read: **the same read must be repeated
  immediately before S7** (this is "D's pre-merge check" in A's step 3), and the owner's visual confirmation stays a
  precondition as the plan states.
### 4.4 Rollback
- `supabase/rollbacks/` at the gate has 110 files, including `121_…_rollback.sql`, `125_…_rollback.sql`,
  `126_…_rollback.sql`; `fix/153` adds `20261011000000_detect_refunds_state_on_rollback.sql` + pgTAP `220`.
- Rollbacks are **manual files**; nothing in the repo or CI applies them, and applying one does not remove the ledger
  row of the migration it reverses. Limits of each file: 
  - **121** (`venue.get_manifest_signing_context()` STRICT row read): body-only `create or replace` + comment + revoke/
    grant; **no apply-time read of `kernel.signing_key`** — the two `signing_key` selects are inside the function body
    (✓D: top-level statements are begin/create/comment/revoke/grant/commit). So "121 needs PFA-18C" (D1 in the final
    plan) is about *exercising* it, not applying it. EXECUTE service_role only. Rollback body byte-identical to the
    current production-mirror `prosrc`; no later migration redefines the function. Limitation: none.
  - **125** (`venue.sync_scan_device_manifest` binds only to an `open:true` episode): body-only re-create; preconditions
    present; grants unchanged; rollback byte-identical to current body; no later redefinition. Limitation: none.
  - **126** (ops refund exactness): **adds** `ops.refund_facts` (EXECUTE revoked from all client roles) and re-creates
    `ops.build_daily_summary`, `ops.money_overview`, `ops.refresh_metrics`; no table DDL, no data rewrite; the three
    replaced bodies were last defined by 118/120 and nothing later redefines them; rollback drops `refund_facts` and
    restores all three bodies byte-identically. Limitation: `ops.daily_summary` rows generated while 126 is live keep
    126's keys after rollback (benign).
  - All three are idempotent and wrapped in their own `begin;/commit;` (repo convention; CLI nesting behaviour inferred,
    not executed).
### 4.5 Migration 153 — parked, finding preserved
A claims **no release dependency** (manifest). It stays parked; I did not review it for application. Preserved: it is
timestamp-named `20261011000000_detect_refunds_state_on.sql`, which sorts after `20260925010000` under `LC_ALL=C`, so
a fresh replay applies it after the function it redefines — the "134 trap" is avoided by name. The second condition I
set (a separate gated-loop counter so that flag-off ≠ flag-on-with-zero-rows) — sub-review observation, information
only, not an approval: it holds. 153 adds `v_state_scanned` (incremented in both refund-state loops) and `v_state_rows` (`count(*)` of
`payment_refund_state`, **NULL when the flag is off**), and returns `state_on, state_scanned, state_rows` beside the
unchanged `scanned/opened/resolved` (✓D: diff of the two migration files). Flag-off → `(false, 0, null)`; flag-on-empty →
`(true, 0, 0)`; flag-on-rows-none-selected → `(true, 0, N)`. Rollback restores 150's body byte-identically; `ops.run_job`
reads only the three original keys and stores the jsonb whole; admin reads `job_run.detail` opaquely; edge functions
mention `detect_refunds` only in comments. This is information for when the owner un-parks it — not a review for
application, which stays parked.

## 5. Verdict
### 5.1 Blocking defects (with reproduction)
**None.** No defect was found that makes `48d20ca1` unsafe to build and distribute (G2) or to merge into the gate
(S5). Every finding below is non-blocking or a documentation/precondition item, each with its reproduction:
- **D-RC-1 — deployment plan, step 3 (required correction before S7, not before S5/G2).** `DEPLOYMENT_PLAN.md` says
  the gate's migrations are "all already in the production ledger". Reproduction: `comm -23 <(gate migration versions
  at abef9506, 167) <(select version from supabase_migrations.schema_migrations in pkg151_rehears, 164)` → `121 125 126`.
  If automatic deployment were on, S7 would apply exactly those three. The plan must say so and the post-merge check must
  assert ledger = 164 with none of the three present.
- **D-RC-4 — new timezone-dependent test** (`tests/v3-harness-art-selection.test.ts:39-48`). Reproduction: the node
  one-liner in §3.2 under `TZ=Europe/Berlin`. Green on CI (UTC) and on the UTC−4 Macs; red on any UTC+ machine. Fix is
  C's (build `iso()` from local Y/M/D as `v3-transfer-cells.test.ts:153` does); a fix changes `d27aa449` and re-keys
  the candidate — the owner decides whether to fold it in or carry it as a known test defect.
- **D-RC-3 — buyer never sees a failed refund** (`settledRead.ts:42`; 0 reads of `refund_failed_cents`). Reproduction
  (local, by inspection): a payment with `refund_failed_cents = total`, `refund_succeeded_cents = 0`,
  `amount_refunded_cents = total` renders "Refund … initiated". Truthful wording, no money action, so not blocking; it is
  the first item I would fix after this release.
- **D-RC-2 — harness configuration in the public repo** (`.claude/launch.json`, `tools/v3-capture/*` UDIDs). Pre-existing
  on the gate; no secret; an owner policy decision, not a safety defect.
### 5.2 Passed checks, with their limits
- C4 at `48d20ca1`, both roots: reproduced, non-vacuous, reconciled, blind spots hand-resolved (§2). Limits §2.7.
- Candidate identity: all manifest claims verified by `git diff` (§1). Limit: "live" web/admin deployment ids are A's
  statement; I compared against the commits A named, not against Vercel.
- CI 38203105234 green, 5/5 jobs, no skipped step (§1). Limit: I read the API result; I did not rerun suites (H1 in force).
- Rulesets and CI permissions as A described; no CI credential exists that could reach production (§3.1).
- Payment/refund/transfer invariants, auth ordering, operator reachability, env pairing, merge/CI/install side effects
  (§3.2). Limits: runtime Apple Pay/PaymentSheet, edge-function bodies and RLS predicates were not exercised; the hold/
  claim machine was not re-verified because the diff does not touch its logic.
- Dynamic-site and RPC contract depth: argument types, return fields read, error texts branched on, ownership/mode checks
  in every SECURITY DEFINER money/transfer RPC (§2.6 and sub-review T2). Five harmless client/server drifts noted (§5.3).
- Migration scope {121,125,126}; rollback bodies byte-identical to the mirror's current `prosrc`; 121 needs no PFA-18C
  state to apply (§4). Limit: `supabase db push` behaviour inferred from CLI semantics; nothing was applied.
- AUTODEPLOY binding: `git_branch: ""`, unchanged since 2026-08-27, read 2026-10-12T04:27:03Z (§4.3). Limit: point-in-time;
  the dashboard label is not API-visible.
### 5.3 Optional improvements (not release blockers)
- **Scanner (C4) hardening**, so the next run needs less hand work: report UNRESOLVED (never silence) when a `.from()`
  chain is assigned to a variable or extended in a later statement; parse `.or()`, `.match()`, `.filter()`, `.not()`
  column references; track `.schema()` held in a variable (today a false pass); fix the `//`-in-string stripper; report
  interpolated names as UNRESOLVED as the docstring promises; include `.js/.jsx/.mjs`; add `web/ admin/` to the
  default roots; add filter/write/embedded/schema mutants to the control set.
- **Client refund truth:** read `refund_failed_cents`/`refund_succeeded_cents` and render a failed refund as such
  (D-RC-3); key the refund sentence by `transfers.payment_id`; narrow the "report it from your order" copy.
- **Contract drift (harmless):** drop or correct `/not authenticated/i` (`payments.ts:52`; the SQL says "Unable to
  identify caller…"); reconsider classifying "already reserved" as terminal (the hold lapses in ≤10 min); remove the dead
  bare-42501 → `bound_to_other` branch and the `rebound_legacy` outcome; refresh the stale recovery-path header in
  `registerToken.ts:16-27`.
- **Tests:** fix D-RC-4; add a test for the `_dev` layout gate and for `authStateHandler` → `clearDockAvatar`.
- **Build-time pairing:** an `eas-build-pre-install` hook running `assert-env-pairing.mjs`, so a local `eas build`
  cannot bypass the CI assertion.
- **Repository hygiene (owner's call):** move `.claude/launch.json` and the capture tooling's machine identifiers out of
  the public tree (D-RC-2); `main`'s ruleset does not require the Admin console / Deno checks and the gate's does not
  require the secret scan — align if intended.
- **153**, when the owner un-parks it: the sub-review's checks (§4.5) are favourable; it still needs its own review for
  application, a sandbox rehearsal and the registry entry — none of which this record provides.
- **CI step masking** (`if: ${{ !cancelled() }}`): A's parked item; I concur it is worth doing.
### 5.4 Prerequisites for production approval (owner's steps; none executed here)
These are the owner's steps; none was executed or started by me.
- **Before S5 (gate PR from `integration/rc-20261012`):** CI green at `48d20ca1` (done); C's fresh-install native build
  log with exit status and env-pairing checks at `48d20ca1` (outstanding, H1); B's consumer review; E's acceptance
  matrix closed at `48d20ca1`; the owner's D2 decision on 152 (A recommends "not in this release"; a "yes" re-keys the
  candidate and reruns §5.3 including C4); a decision on D-RC-4 (fix now → new v3 sha → re-key; C4 carries over
  because the roots are unchanged, shown by an empty `git diff --stat <old> <new> -- app src packages web admin`).
- **Before G2/X11:** build from exactly the step-1 merge commit after A shows `git rev-parse <merge>^{tree}` =
  `7feadf07…`; EAS metadata names that commit; the production profile's pairing asserted.
- **Before S7 (gate → `main`):** D-RC-1 corrected in the plan; the PR-3 decision (the `main` ruleset today allows
  **squash only** with linear history; a squash still leaves `main` tree-equal to the gate); the owner's fresh visual
  confirmation that Supabase auto-deploy is off; **D's pre-merge read** — `list_branches(hqycwntpfoztoinemqns)` showing
  `git_branch: ""` immediately before the merge; **after** the merge: the "Supabase Preview" check reads `skipped` and an
  owner-authorised ledger read shows 164 rows with none of 121/125/126 present.
- **Standing, unchanged by this record:** no agent-initiated production write, refund, payout, setting change or
  deployment; the five test-mode payments stay excluded; historical refund reconciliation is closed and not rerun; 153
  parked; the owner-waived sign-in checks stay waived; VoiceOver optional.

## 6. Process notes
- Raw outputs (scanner runs, controls, reconciliation lists, the branch-record read) are preserved privately at
  `private-evidence/D-session-9651e05a/c4_rc20261012/` on the encrypted SSD; this record carries counts, paths and
  names only.
- Before pushing this record I scanned **every blob version and every commit message** in the outgoing range with a
  pattern set (Stripe keys/ids, 20–24-digit runs, JWTs, AWS keys, PEM, DSNs with passwords, Supabase tokens), with a
  built-in positive control that must trip or the scan fails; matches are never printed. Result: first pass on the committed record: 1 commit, 1 blob version, **0 hits**, positive control tripped as required; the amended final version was re-scanned before the push and the result is in the commit's push note in `D-HANDOFF.md` (sprint-control, private) — if that line is absent, the push did not happen.
- Two read-only subagents were used (schema/contract; integration/security); their findings are attributed in §2.6,
  §3.2, §4.4–4.5 and were spot-checked by me where stated.
