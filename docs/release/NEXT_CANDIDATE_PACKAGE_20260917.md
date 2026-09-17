# Candidate c3 — execution package and final approval request (A, 2026-09-17) — LINE 1 AUTHORIZED: tag `candidate/2026-09-18-build-c3` created at `f412d10`, one sandbox preview build by C; nothing is applied or deployed

**Supersedes** the `4dbee98` version of this file, which is preserved byte-for-byte in git
(`4dbee98:docs/release/NEXT_CANDIDATE_PACKAGE_20260917.md`, sha256 `347bf5eb842d588d2361d9af08e834c2f160ee290d7b65f269c9bb425629c8c8`).
The layered status sentences of that version ("pending D", "still to join", "running") are gone: every status below was re-derived
from the stack, CI and the reviewers' own records on 2026-09-17, and it is stated only in §0. D's statements that D asked to
survive are carried verbatim in §9.

## 0. Status — the only place status is stated
| Item | State (2026-09-17, after the 14:35Z sandbox read) |
|---|---|
| **Build** | **The hold's condition is met, and the package is issued for approval.** The owner held the build until C's Keep editing fix (F-NAV-1) passed D's review and was integrated. D PASSED 2ba9e3a (product) and 76b8622 (the required tests); A integrated at `f412d10`; CI 35237352892 SUCCEEDED on all five jobs; **D's merge-preservation gate on `f412d10`: PASS**. No build exists until the owner speaks line 1 |
| Reviewed, CI-green tree | **`f412d10`** on `release/production-gate-20260918`, tree `0409138f` (= 76b8622's tree): CI 35237352892 success on all five jobs; D merge gate PASS. It contains `db16e1a` (tree `aa93c03b`, CI 35188006272, D merge gate PASS, D: no open review item). **Every constituent review is closed (§1). No review is pending on this tree** |
| Tag line | **AUTHORIZED by the owner (2026-09-17): "I authorize creating candidate/2026-09-18-build-c3 at f412d10 and having C submit one sandbox preview build from that exact commit."** Tag created by A, annotated `b4c3b908`, pushed, and resolving on origin to `f412d10a1131` (tree `0409138f`). Unchanged: `candidate/2026-09-18-build-b2` → `aad5f75` (Build 18), `candidate/2026-09-18-pin-b2` → `9bef640` (sandbox application pin), `candidate/2026-09-18-pin` → `aabe029`. **The build is C's; A relays the installation link to the owner.** W-C3, the staged notice, the round trip and the permanent transfer-test writes remain separate and unauthorized |
| What a tag will mean | a reviewed, CI-green tree, **not a working image flow on a handset** |
| Checks rerun for F-NAV-1 (only what it can affect) | **on `f412d10`, by A, run alone:** vitest 2229/2229 in 105 files (14:59:37–14:59:59Z); tsc exit 0; lint 0 errors / 29 warnings · **CI 35237352892 SUCCESS on all five jobs** · D's merge gate pending. **The DB evidence and the §3 pins carry over:** `db16e1a..f412d10` changes 0 files under `supabase/`, `scripts/`, `.github/` and the gated client surface |
| Sandbox | unchanged since the B2 window; read 14:35:00–14:35:40Z and 14:51:11Z (§2) |
| **Test design** | **settled by the owner (2026-09-17):** B's evidence checklist adopted (§7) with five rulings: U2 as the unrelated reader, no N5 and no destructive test, synthetic images with downloads limited to those uploads, the corrected notification expectation, and every affected transfer recorded with its deadline and disposition (§5a). The message started no window and authorized no production access |
| Production | ledger 135; nothing applied since 2026-09-12. Nothing in this package reads or touches production |

**Evidence limits (the owner's words, unsoftened):** "database outcomes 1 and 2 passed; image conversion and buyer display remain
unverified until a real iPhone round trip, and the remaining device behavior needs a build. Do not describe the whole image issue as
fixed yet." "A MIME allow-list match does not establish that the bytes render correctly." Current statuses: outcome 3 UNVERIFIED
(DV-IMG-9) · outcome 4's device half unrun · **DV-S2 on Build 18 is not a full pass:** header clearance FAILS at the largest text
(F-SELL-2, fixed in source at 9d01bad, device re-check on the next build), and **Keep editing returns to My Listings instead of
keeping the edit screen open (F-NAV-1: fixed in source and tests at `f412d10`, **not verified on a device**; the owner: do not infer that unsaved text survived)**; Discard PASSED;
Event name "mostly visible" stays UNRESOLVED · every push-delivery row is UNTESTED (sandbox push key deferred) · 140 is applied
nowhere, so no recovery behaviour has run against a real database other than CI's and the local harness.

## 1. Code — reconciled; every review closed
| Layer | Head → stack commit | Review (final) | Contents |
|---|---|---|---|
| Batch 1 | `e9b52ce` | D PASS; CI 35181982625 | 136 (rev3) security-notice read/ack + template v2 · 139 notify-report delivery claims (5a62bf0 + test-only 7612c8b) · aeb4081 webhook honours `notify_listing_sold` · C: cf94311, df5127c, da1d11d, 296439c (F-611C-2), ac70643 (development-only Tickets label; exclusion from preview and production builds preserved) |
| 140 server | `fix/140-proof-upload-repair @ 251cda2` → `0523793`; test-only `259246e` → `759d3a0` | A PASS (912a7d6, from source); D PASS on substance and on the 251cda2 delta; D confirmed 259246e | idempotent `mark_transfer_sent` (both overloads, jsonb); `attach_transfer_evidence`; rollback = the applied 0550/0553 bodies; 207 (37); 050's custody assertion on transfer B fails under the writing mutant |
| Proof-image client | `frontend/proof-image-flow @ c0281aa` → `4331ea4` | D PASS | byte-sniffed type, HEIC via the picker's compatible mode, 120 s bounded upload + 30 s exists-check, status read before and after, recall guard |
| F-SELL-2 | `frontend/sandbox-header-inset @ 9d01bad` → `e9413d8` | D PASS | `useTopInset()` on eleven surfaces + the outbid toast; production spacing identical; sandbox builds only |
| 140 client adaptation | `frontend/proof-outcome-attach @ 5e14a68` → `db16e1a` | D PASS (after D's finding on 5e9c80b) | Mark as sent reads `transitioned`/`already_sent` with a sent read-back; an outcome without a sent status = unconfirmed; Add proof section for seller_sent + null path; refresh and the actions single-flight |
| **F-NAV-1** | `frontend/unsaved-guard-native-dismiss @ 2ba9e3a` (fix) + `76b8622` (tests: settle before the text reads; repeated attempts in all four swipe/Back orders) → **`f412d10`** | **D PASS** on 2ba9e3a (product) and on 76b8622 (gate: 1 file in `tests/`, +60; R0 = 8, M7 = 12, M8 = 12 as predicted; 2229/105, tsc 0, lint 0/29); **D merge-preservation gate on f412d10: PASS** (parents db16e1a + 76b8622, tree identical to 76b8622's, 3 commits added, db16e1a/5e14a68/759d3a0/e9413d8 still ancestors, 0 files under supabase/scripts/.github/gated surface; CI 35237352892 read by D: 15:00:19–15:02:23Z, success ×5). D, verbatim in substance: the gate says the merge kept the reviewed fix, not that the fix works on a phone | the guard moves from a bare `beforeRemove` listener to `usePreventRemove(opts.when, …)`, so native-stack sets `preventNativeDismiss` and an iOS swipe is cancelled natively; the same dialog decides; Discard replays once; same fix on the report form and Settings → Preferences. **No phone has run it;** D's phone-only residual: a swipe begun within one frame of the first keystroke, before the prop reaches native |

**F-NAV-1 — C's evidence, and A's static checks (2026-09-17):** *Root cause (C):* the guard held the pop in navigation state only. On iOS, native-stack 7.14.4 prevents a swipe natively only for routes registered through `usePreventRemove`, so UIKit completed the swipe, `onDismissed` dispatched a pop the guard refused, and the dialog appeared over My Listings. Discard replayed the pop, so state caught up with the screen and it *looked* right; Keep editing did nothing, which left the edit route in state but off screen. The in-screen Back arrow (`router.back` → GO_BACK) starts in JavaScript, is refused before anything moves, and **by source already held on Build 18. No device has checked that.** *A verified from installed source:* versions native-stack 7.14.4, core 7.16.1, native 7.1.33, react-native-screens 4.16.0; `NativeStackView.native.tsx:278/410` sets `preventNativeDismiss` from `preventedRoutes[route.key]?.preventRemove` only; `usePreventRemove` calls the latest callback (`useLatestCallback`); a replayed action carries `VISITED_ROUTE_KEYS` (`useOnPreventRemove.tsx`), so Discard is not asked twice; one guard per screen (`app/listing/edit/[id].tsx:64`, `app/report/[type]/[id].tsx:53`, `app/settings/preferences.tsx:79`); `git diff db16e1a 2ba9e3a -- supabase/ scripts/ .github/` plus the gated client surface: **0 lines**, so the §3 pins and the DB evidence carry over. *Tests (C):* 17, rendering the real Edit listing screen and hook with real React Navigation core + StackRouter. **The native-stack/RNS iOS layer is a model** pinned to the installed source and versions, so the tests prove behaviour against that model and only the device row proves UIKit. RED on the `db16e1a` hook: 3/17, all swipe rows, with the owner's symptom (`['my-listings']` instead of `['my-listings','listing/edit/[id]']`). **Deviation accepted:** the Back-arrow rows cannot be RED because that path has no defect in source; they are regression guards proven able to fail by M2. Mutants 6/6 killed as predicted (M1 swipe = the db16e1a hook → 3; M2 Back arrow skips the prompt → 4; M3 Keep editing dispatches → 4; M4 Discard no-op → 2; M5 `usePreventRemove(true)` → the 4 clean/undone rows; M6 dirty ignores Event name → 8), with a clean baseline, an anchor matched once, and a digest-verified restore. **Gap (C's own):** no mutant targets the typed-text assertion alone, so its ability to fail is not yet shown; A asked for one (a Keep editing that keeps the route but resets the form). *M7 (typed-text mutant; C and D each ran one):* an in-place reset of the form that keeps the route and the mounted instance kills exactly 4/17 = {swipe, Back arrow} × {Keep editing (the first failure is the text assertion), asks again (downstream: with the edits gone the guard correctly stands down)}; every screen-still-open assertion survives. *Harness limit (C):* routes added after start (push/replace) are not mounted, so a re-key mutant would read as "no screen"; no current test adds routes. *D's review (2026-09-17):* the native-layer model holds against RNS 4.16.0's iOS source (a prevented interactive pop is cancelled in `interactionControllerForAnimationController`, then `notifyDismissCancelled`; the cancel is gated on `fromView.reactSuperview`, so a JS-started pop is never cancelled); the app's `Stack` is expo-router 6.0.24's fork, which renders upstream `NativeStackView`, so the upstream pins describe the running code; D reproduced tsc 0, lint 0 errors / 29 warnings, vitest 2221/105 run alone, and 0 files under the gated surface, `supabase/`, `scripts/` and `.github/`. **Required test-only additions:** M8 and GAP 2 above. **D's out-of-scope source observation (pre-existing):** a swipe during an in-flight save (the guard is off while submitting), after which the "Saved" OK calls `router.back()` from My Listings. It is recorded, not in F-NAV-1's scope. *Counts (C, on 2ba9e3a):* tsc 0; lint 0 errors / 29 warnings; vitest 2221 in 105 files, not run concurrently. A reruns these on the integrated head.

**Combined checks on record:** rehearsal `c3461a0` (tree = `4331ea4`), 05:40–05:41Z: replay clean; Gate-2 32/108/37/38; pgTAP
5296/5296 (050 20, 207 37); census notify 22 / five-schema 305; vitest 2157; tsc 0; lint 0 errors. Then 050 21/21 on the candidate
DB with 259246e. On `db16e1a`: vitest 2204/2204 (104 files), tsc 0, lint 0 errors (06:00–06:02Z); CI 35188006272, including
"Migrations apply cleanly on a fresh DB" over the full chain with 140 and the 050 follow-up.

**Client property D asks the package to state, because no device evidence sits behind it yet:** a transfer sent without a screenshot routes to the explicit recovery at all three points it can be discovered — the read before the call, the server's refusal, and the read after; refresh and the two actions exclude each other via a single-flight ref, so a late read can never show a confirmed proof vanishing.

**Recovery behaviour verified on the combined tree (unit and pgTAP only):** server — 207 R3–R7/R9 (same-path, different-path and
2-arg retries answer `already_sent`; they write, notify and replace nothing); S1–S13 (attach eligibility, write with the guard
armed, dangling path refused). Client — the proof-image and mark-sent suites: status read before and after, success only on a
sent read-back, timeout treated as uncertain and settled by `storage.exists`, Add proof outcomes. **None of it has run on a device
or against the sandbox.**

## 2. Sandbox state now (A, read-only, sandbox only, 2026-09-17 14:35:00Z–14:35:40Z; scratchpad `pkg_c4_preread.txt`, md5 `a7fa72a424cb91ac79831078cec9afa7`)
**Disclosure:** in the first batch, statement 6 failed on a type cast (`text || "char"`), and `ON_ERROR_STOP` halted statements 6–10.
At 14:35:29Z A ran only those five unexecuted statements, with the cast fixed. No statement ran twice.
| Read | Value |
|---|---|
| Ledger | 141; 136, 139, 140 absent; 20260916000000 present |
| `public.mark_transfer_sent` | 2-arg returns void, body md5 `bab0d402e47ab4fb81e6c9927df271d2`, len 955; 3-arg returns void, md5 `c3281f0a4c662338a7775380efa7de77`, len 1042. **Equal to the bodies 140's rollback restores**, so the repo rollback is this sandbox's rollback (unlike 133's) |
| `public.attach_transfer_evidence` | absent |
| Triggers on `public.transfers` | `trg_guard_transfer_state_columns`, `trg_reset_transfer_guard_bypass`, `trg_notify_transfer_created`, `trg_notify_transfer_created_inbox`, `trg_notify_transfer_sent`, `trg_notify_transfer_state_inbox`, `trg_notify_dispute_opened`, all enabled (`O`) |
| Money executors | `catalog.platform_config`: `payout.executor_enabled` = false, `refund.executor_enabled` = false |
| Cron touching transfers/payouts | `enforce-transfer-expiry` */2 active · `market-sweep-expired-p2p-transfers` */2 active · `payout-execute-tick` */10 active (gated on the false flag) |
| Vault | names only: `project_url` (no `service_role_key`; every cron post to an edge is refused 401, as recorded in the B2 window) |
| `proof-docs`, `2f5844b4-5144-4cd6-936d-4b59d8d5c6a0/transfer-evidence/` | 0 objects; 0 `rt-` objects |
| Edges (`functions list`) | notify-report **v3** ezbr `90dc5e9b…` 2026-09-07T16:05:29Z · stripe-webhook **v4** `897283ef…` 2026-09-15T13:51:22Z (byte-identical to `aabe029` and `9bef640`, manifest §10) · create-payment-intent v5 · send-push v4 · enforce-transfer-expiry v4 · confirm-and-release v3 · confirm-payment v3 · create-connect-account v3 · delete-account v3 · **all nine `verify_jwt=false`** |

**Transfers named for the device rows** (DV seller `2f5844b4-5144-4cd6-936d-4b59d8d5c6a0`, DV buyer `919d511e-c4e6-4422-a71d-e2bc0139de65` on every row; none disputed, none released):
| Transfer | Status | Created | Sent | auto_release_at | Proof path | Used by |
|---|---|---|---|---|---|---|
| `92ee5156-7e82-40d8-ab54-73b489997797` | pending | 2026-09-11T01:19:01Z | — | — | null | DV-IMG-4 (P) |
| `3118bd30-276f-4183-8579-cfea852421cb` | pending | 2026-09-11T01:05:11Z | — | — | null | DV-IMG-9 (P) |
| `bce07eef-ed72-4d85-96db-8ef340838b89` | pending | 2026-09-10T20:58:47Z | — | — | null | DV-IMG-5 (P) |
| `8f59d37e-52fd-4733-b311-532445ff441c` | seller_sent | 2026-09-08T01:20:22Z | 2026-09-08T01:20:24Z | 2026-09-11T01:20:24Z (past) | null | DV-IMG-10 Add proof (P); then RT6 |
| `83b83858-7c96-4887-bf6c-447858aec22a` | seller_sent | 2026-09-08T00:52:17Z | 2026-09-08T00:54:49Z | 2026-09-11T00:54:49Z (past) | null | **untouched**: the only remaining sent-without-proof transfer |
**Mapping confirmed by C (2026-09-17)**; DV-IMG-4 and -5 stay separate rows (§6). There is no pending spare: if a named transfer is not in
its §2 state at the pre-read, A stops and reports. There is no silent switch, and no new fixture without the owner's authorization.

**Third-account read (A, read-only, sandbox, 2026-09-17 14:51:11Z; scratchpad `pkg_c4_u2_read.txt`, md5 `e14fc0f38cae9e4dcf11c7cf0cfeb643`):** U2 `f53b8466-9571-4f41-88c3-1c33847dd8ee` (credentials by NAME `U2_EMAIL`/`U2_PASSWORD` in the sandbox env; last used by the payments matrix, where S9.4 withdrew its deletion back to ACTIVE): the auth row exists, not banned, `deleted_at` unset; `kernel.identity_ext.deletion_state` = ACTIVE; buyer on 6 transfers and seller on 0, **none of them the five named here**; `public.profiles` has no admin/role/operator/staff column. The `proof-docs` policies on `storage.objects` are exactly five (owner delete unreferenced, owner insert, owner read, owner update, transfer party read), none mentioning a role, admin or operator (qual md5s recorded in the scratchpad file; PC5 compares them with the chain).

## 3. Pins (at `db16e1a`; re-verified byte-for-byte at the tag commit as pre-flight PF1)
| Migration | File | sha256 | Ledger md5 (script method: file bytes minus trailing newlines) |
|---|---|---|---|
| 136 | `supabase/migrations/136_public_security_notices_read.sql` | `5133d3021987d11b8dfe8b412d4a0031e11e8cc157f202aca4705b0aef19a9a8` | `735b992076ef07265af28e5204916fb8` |
| 139 | `supabase/migrations/139_notify_report_delivery_claims.sql` | `8549c658153f310d05ad510f5dc88113272456ff3c23fae670bcccdfd525ddcc` | `f36734e2f6053544e23a913dd3ebd638` |
| 140 | `supabase/migrations/140_proof_upload_repair.sql` | `44ee31a6bad0e5d2d261b9018a2bff307e882cb8065bbeeb3e1f0d8887a8a3c1` | `f62968705af88430d0334e1652f08c9e` |

| Rollback | sha256 | Restores |
|---|---|---|
| `supabase/rollbacks/136_public_security_notices_read_rollback.sql` | `fee9c24e309557e4590c60db86f03713ab40a51332fd57e75db476605ae4a564` | drops both wrappers + the v2 template row |
| `supabase/rollbacks/139_notify_report_delivery_claims_rollback.sql` | `8dd40dea8bd3d6be27d64deb35a230755a347f445bc15e4ab740424d2ff34936` | drops `notify.report_delivery_claim` and its two functions |
| `supabase/rollbacks/140_proof_upload_repair_rollback.sql` | `9ee81807040e85d53944a51795409c1ddf406bf97551eba76f5e733b0db78270` | drops attach; recreates both void overloads = the §2 md5s |

| Edge | Bundled local files (relative-import closure) | sha256 at `db16e1a` | at `9bef640` | Deployed now |
|---|---|---|---|---|
| stripe-webhook | `stripe-webhook/index.ts` | `7c2ae402af5b20af154ba0a713225a12a65d336013232e7e0c61ae694cbedcbb` | `68701c07…` (changed by aeb4081) | v4 `897283ef…` = the 9bef640 source |
| | `_shared/sentry.ts` | `e41fd1f83843e719351ffc494c55f8c4c255b8edaafb0e0e0344f16d9248fa23` | same | |
| | `_shared/stripe.ts` | `21cd0a09f7372eb81b438233ff1b7258c5c888aa483d48faf14f5ef759e8a000` | same | |
| notify-report | `notify-report/index.ts` | `fb8e8ec3d77ef4f4a643836c5654227f812730949fb1b95a8494450111fd0b8f` | `c0625835…` (changed by 139: d07d425, ef8e2d5, 5a62bf0) | v3 `90dc5e9b…` (2026-09-07). **Its parity with any pin was never recorded**, so PF6 captures it as the rollback source |
| | `_shared/sentry.ts` | `e41fd1f8…` (as above) | same | |
Remote imports: stripe-webhook `deno.land/std@0.177.0`, `esm.sh/@supabase/supabase-js@2.39.0`; notify-report `deno.land/std@0.177.0` and
**`esm.sh/@supabase/supabase-js@2` (floating major; unchanged since 9bef640)**. Evidence limit: that import resolves at bundle time, so
parity for notify-report is a source parity only, and the resolved version is recorded at S4b.
Caller authentication (both deploy with `verify_jwt=false`, as every sandbox edge does today): stripe-webhook verifies the Stripe
signature (`index.ts:149–154`, 400); notify-report requires `INTERNAL_CRON_SECRET` or the service-role bearer, compared in constant time
(`index.ts:106–113`, 401).
**Apply method:** `ORDER_GUARD_SKIP=126 scripts/release/apply_sandbox_migration.sh <v> preflight|apply|verify <exec tree>` (script at
`838bceb`, byte-identical on the stack and converge). It asserts the sandbox ref twice, refuses the production ref, refuses a
recorded version, and refuses unless every numbered 123…v−1 file is recorded except 126 (owner-deferred; 134 has no file because it
is 20260916000000). The exec tree is a detached worktree of the tag commit in A's scratchpad with 0 dirty files.

## 4. Window W-C3 — sandbox updates (one owner-authorized window; A executes, D witnesses; each step's evidence goes into the manifest)
**Census reconciliation (the owner's instruction, done before any execution; nothing here was read from the sandbox except the recorded baseline):** D's independent prediction and the package's expectation are the same, **32|109|37|37 after S3**, and no expected count was adjusted to reach it. The census is CI's four Gate-2 queries (`ci.yml:605–608`: public tables, public functions, public policies, public non-internal triggers).
1. `git diff --name-status 9bef640 f412d10 -- supabase/migrations/` = exactly `A 136`, `A 139`, `A 140`. No existing migration changed.
2. The declared counts come from `ci.yml` EXPECT: 105 functions at the pin `9bef640`, 107 at `e9b52ce` (with 136 and 139), and 108 at `f412d10` (with 140). D's local replays match these: the full chain at `f412d10` = 32|108|37|38, and the same tree without 136/139/140 = 32|105|37|38.
3. Name-level diff (D, local replays; A's source count agrees: 136 creates 2 public functions, 139 none, 140 three, of which two re-create `mark_transfer_sent` under the same signatures): **+`get_my_security_notices()`, +`mark_security_notices_read(uuid[])`, +`attach_transfer_evidence(uuid,text)`**; 0 tables, 0 policies, 0 triggers. 139's table is in `notify`, outside the census. 121 and 126, absent on the sandbox, create no public objects.
4. Sandbox baseline = the B2 close **32|106|37|37** (A 04:56:09Z, D's closing read, and A's 14:35Z pre-read), which is the pin's declared 32|105|37|38 plus exactly four named sandbox deltas: +`sandbox_gucs`, +`sandbox_pre_request` (sandbox-only functions); −`guard_listing_seller_not_blocked` and −`trg_guard_listing_seller_not_blocked` (119, never on this sandbox). These four names read 1|1|0|0 on the sandbox and 0|0|1|1 on a full local chain.
5. After S3: 32|106|37|37 + 0|3|0|0 = **32|109|37|37**. Against the declared 32|108|37|38 the difference, 0|+1|0|−1, is the same four deltas.

| Read point | Census | notify tables | new objects present (get_my_security_notices, mark_security_notices_read, attach_transfer_evidence, notify.report_delivery_claim) | Other |
|---|---|---|---|---|
| V0, before S1 | 32|106|37|37 | 8 | false, false, false, false | sandbox deltas 1|1|0|0; `mark_transfer_sent` void, prosrc md5 `bab0d402…`/955 and `c3281f0a…`/1042 |
| after S1 (136) | 32|108|37|37 | 8 | true, true, false, false | deltas 1|1|0|0 |
| after S2 (139) | 32|108|37|37 | 9 | true, true, false, true | deltas 1|1|0|0 |
| after S3 (140) | 32|109|37|37 | 9 | true, true, true, true | both overloads return jsonb, prosrc md5 `d816c53e…`/86 (2-arg) and `17453329…`/2560 (3-arg); deltas 1|1|0|0 |
**Void conditions (a stop, never a re-derivation):** V0 ≠ 32|106|37|37; sandbox deltas ≠ 1|1|0|0; any of the three new function names present before S1; pre-140 bodies ≠ PF3; any step's read ≠ its row. Any difference is explained from the sandbox's actual objects before anything proceeds, and an expected count is never changed to pass.

**Pre-flight (every item must hold before S1; any miss stops the window):**
PF1 exec tree = tag commit, 0 dirty; the sha256 of the three migrations, three rollbacks and four edge files equal §3.
PF2 D's V0 and A's read agree: ledger 141 with 136/139/140 absent; census 32|106|37|37; notify tables 8; business counts (listings,
payments, transfers, push_tokens) recorded as values; `net.http_request_queue` 0; Vault `project_url` only; both executors false.
**D predicts the post-S3 census tuple in writing before S1** (A's prediction: 32|109|37|37 = the candidate's declared 32|108|37|38 with
the B2 window's named sandbox deltas).
PF3 the pre-140 bodies still have md5 `bab0d402…`/955 and `c3281f0a…`/1042. If not, the repo rollback is not this sandbox's rollback:
stop, and capture as for 133.
PF4 `trg_guard_transfer_state_columns` is enabled, and the five §2 transfers are unchanged.
PF5 no DV-ST2 revoke window is open; no handset test is running.
PF6 `functions list` equals §2 for notify-report and stripe-webhook. notify-report v3's bundle is downloaded to the scratchpad as its
rollback source, with its file list and sha256 recorded and compared with 9bef640's notify-report closure; the comparison result is
recorded either way.

| Step | Action | Expected read-back | Stop if |
|---|---|---|---|
| S1 | 136 preflight → apply → verify | ledger 142, md5 `735b9920…`; +`public.get_my_security_notices()`, +`public.mark_security_notices_read(uuid[])`; `notify.template` +1 (v2) | anything else, or the script prints anything but `APPLIED` / `VERIFY OK` |
| S2 | 139 | ledger 143, md5 `f36734e2…`; `notify.report_delivery_claim` (RLS on); +`notify.claim_report_delivery`, +`notify.release_report_delivery`; notify tables 9 | same |
| S3 | 140 | ledger 144, md5 `f6296870…`; both `mark_transfer_sent` overloads return jsonb; `attach_transfer_evidence` executable by authenticated only (not anon, not service_role); census = D's prediction | same, or census ≠ prediction |
| S4a | deploy stripe-webhook from the exec tree, `--project-ref ofaidukbieeekqaboscm --no-verify-jwt` | v5, `verify_jwt=false`; downloaded bundle byte-equal on all three closure files | parity fails or `verify_jwt` reads true |
| S4b | deploy notify-report, same flags | v4, `verify_jwt=false`; bundle byte-equal on both files; resolved supabase-js version recorded | same |
| Close | A and D closing reads | zero drift on business counts; queue 0; Vault names `project_url` only; executors false; the live bodies of the migrated functions equal a local replay at the pin | any drift; a Vault name change; any production ref or `*.supabase.co` literal introduced; **a 2xx in `net._http_response` is attributed before anything proceeds** (it is not used as proof of silence, since that table carries no URL) |
A step never proceeds while one of D's reads is unexplained.

**Rollback (only on the owner's order; never automatic):** edges first: notify-report is redeployed from the PF6 capture, and
stripe-webhook from `9bef640` (tag `candidate/2026-09-18-pin-b2`). Then migrations 140 → 139 → 136 from the exec tree's
`supabase/rollbacks/` (sha256 §3), each followed by deleting its ledger row and re-reading the pre-state (for 140, the PF3 md5s). **A
rollback restores code, not data:** a sent status, an attached path and a referenced object written by the P rows stay, and the void
bodies still read them. S5's notice row is deleted at its own cleanup, before any 136 rollback.

## 5. Shared-environment effects by class, and every affected transfer's disposition
| Class | Tests | Records touched | Removal |
|---|---|---|---|
| **T1 temporary** | image round trip RT1–RT5, RT7 (Line 1) | three `storage.objects` rows `…/transfer-evidence/rt-20260917-*` | deleted at RT7; the **`rt-%` count** returns to 0 (not the folder count, which P objects change); nothing retained |
| **T2 temporary** | staged security notice (S5, batch plan §3b) → DV-N-1..3 | one `notify.notification` row for the DV buyer (`read_at` set by DV-N-2); 0 delivery rows | deleted by id after DV-N-3; buyer pre-count restored; `notify.delivery` total unchanged |
| **T3 temporary** | DV-ST2a (standing authorization, C's trigger) | `public.bids` relacl | restored and verified immediately |
| **N no write** | F-NAV-1 (edit listing, report form), F-SELL-2, Event name, F-DT-1, DV-IMG-1, -2, -3a, -6, -7 (picker only; Transfer send and the Sell form are **never submitted**), copy rows, the DV-611C-2 counting half; API probes N1–N4; read probes RT6, U1, RT5-P | none | — |
| **P permanent** (Line 3) | DV-IMG-4, -5, -9 (+3b) Mark as sent with proof; DV-IMG-10 Add proof | `public.transfers` status, `seller_sent_at`, `auto_release_at` (+72 h), `transfer_evidence_path`; the referenced `proof-docs` object; **`public.notifications` +1 per Mark as sent** (buyer `919d511e…`, type `buyer_confirmation_needed`, dedupe `buyer_confirmation_needed:<transfer id>`); **+0 per Add proof** (the buyer is not told proof was added: a source fact, not a defect claim) | **none possible or proposed.** The state guard and the append-only guard make these one-way; referenced objects are evidence and stay; objects from refused, failed or unconfirmed attempts are retained under the owner's 30-day direction |
| ~~P permanent (Line 2)~~ | cached-bids fixture: **WITHDRAWN, not requested** (its premise was wrong; see §8 item 6) | none | — |
| authorized write | DV-131-1 epoch bump | as already authorized for session 2 | — |
| reversible own write | F-NAV-1 Preferences row | the owner's own preference toggle | restored in the same row, with A's read-back |

**Notification expectation (owner ruling 4, from B's source trace):** Mark as sent creates the buyer's in-app notification.
`public.notify_transfer_event` (as 133 defines it) posts only `IF v_key IS NOT NULL AND v_url IS NOT NULL` (133:145). With no
`service_role_key` in the Vault it makes **no outbound call: no 401 is expected from this path**, and unrelated `net._http_response`
rows (the `enforce-transfer-expiry` cron, 135's challenge post) are **not** used as proof of silence, because that table carries no
URL. The evidence is the **live code and the secret names, read before and after**: PC3 (live bodies = local replay at the pin) and
PC2 (Vault names). **Any call that could come from this path is investigated before anything proceeds:** a queued request naming
`notify-transfer`, or an unattributable 2xx. (`notify-transfer` is not deployed on the sandbox, per the nine functions read at 14:35:40Z, so its edge logs
could show zero invocations without proving anything; that check is dropped as vacuous.)

### 5a. Every affected transfer and its auto-release deadline (owner ruling 5)
All: seller `2f5844b4-5144-4cd6-936d-4b59d8d5c6a0`, buyer `919d511e-c4e6-4422-a71d-e2bc0139de65`; states read 2026-09-17 14:35:00Z.
| Transfer | Used by | State before | auto_release_at | After the tests |
|---|---|---|---|---|
| `92ee5156-7e82-40d8-ab54-73b489997797` | DV-IMG-4; N1, N2 | pending, no proof | none | seller_sent with proof; **deadline = the recorded `seller_sent_at` + 72 h** (written into the manifest at the row) |
| `bce07eef-ed72-4d85-96db-8ef340838b89` | DV-IMG-5 | pending, no proof | none | same: `seller_sent_at` + 72 h, recorded |
| `3118bd30-276f-4183-8579-cfea852421cb` | picker-only N rows, then DV-IMG-9 + 3b | pending, no proof | none | same: `seller_sent_at` + 72 h, recorded |
| `8f59d37e-52fd-4733-b311-532445ff441c` | N3, DV-IMG-10, N4, RT6, U1, RT5-P | seller_sent, no proof | **2026-09-11T01:20:24Z (already past)** | seller_sent **with** proof, deadline unchanged (attach does not move it); payout policy's `EVIDENCE_MISSING` reason gone |
| `83b83858-7c96-4887-bf6c-447858aec22a` | **none** (untouched) | seller_sent, no proof | **2026-09-11T00:54:49Z (already past)** | unchanged |
**Disposition:** every transfer stays exactly as the tests leave it. This package adds no key, flips no executor and changes no payment
state. They are not processed today because `payout.executor_enabled` = false and the Vault holds no `service_role_key` (read at
14:35:00Z, and re-read as PC2 at Line 3's start and end). **Standing precondition (manifest §13):** before any future sandbox
activation of a `service_role_key`, `payout.executor_enabled` or `refund.executor_enabled`, **or any manual invocation of
`enforce-transfer-expiry` with `INTERNAL_CRON_SECRET`** (it authenticates that secret too, `index.ts:165-170`, and its NAME is in the local sandbox env,
so the sweep would run with no Vault key and no executor flag), the activation package must re-read every transfer in this table, plus every
other sandbox transfer the sweep or `payout-execute` would select, and carry an owner-approved disposition for each one. **The re-read is a plain
SELECT, never `public.get_auto_release_candidates()`**: that function PERFORMs `refresh_seller_risk_score` for each due seller (039), so a
"read" through it writes. The predicate is 039's: `status = 'seller_sent' and auto_release_at is not null and auto_release_at < now() and
payout_released_at is null and (payout_hold_until is null or payout_hold_until < now()) and payout_review_status is distinct from 'manual_review'`. No activation proceeds while a test transfer is eligible. The disposition itself is chosen
then, not now.

## 6. Targeted device tests on the next build (C guides; owner's handset; A reads back; D witnesses; all UNTESTED until run)
**Images (owner ruling 3):** every handset upload is a **synthetic ticket image made by the owner**, with no real ticket codes and no
personal information. DV-IMG-9's HEIC camera photo is a photo of such an image. A downloads **only** the exact objects these rows create,
as the seller and as the buyer. A touches no other photo or file: the folder listing reads names and metadata only, and a baseline
object in the folder that these tests did not create stops the read.
| Row | Class | Exactly |
|---|---|---|
| **F-NAV-1 re-check** | N | Edit listing on a bid-free listing (Phone P1 `c343406e-be85-49c1-9951-ac08bb1daab2`; Save changes is never tapped): change Event name → swipe back → **Keep editing** → still on Edit listing **with the change visible**; leave again → asked again; repeat with the **in-screen Back arrow** (there is no native header); then Discard → My Listings after one prompt; no edit, or an edit typed and undone → leaves at once. The Back-arrow half is also the first device observation of that path |
| F-NAV-1 same hook: report form | N | type in a report → swipe back → **Keep writing** → still on the form with the text; **never submitted** |
| F-NAV-1 same hook: Settings → Preferences | reversible own write | toggle a preference and swipe back while it saves → "Still saving" → **Wait** → stays; restore the toggle (A reads back before and after). Observable only while the save is in flight; if it finishes too fast to catch, the row is UNTESTED, not passed |
| F-SELL-2 re-check | N | the badge clears every header at normal and largest text; no doubled spacing; My Listings, one SettingsHeader screen and the security banner at the largest text in one look |
| Event name "mostly visible" | N | UNRESOLVED until directly confirmed |
| F-DT-1 | N | does a text-size change apply without a relaunch |
| DV-IMG-1, -2, -3a, -6, -7 | N | on `3118bd30…` (the pending transfer consumed last), before any P row; the upload happens only inside Mark as sent (`uploadImage` is called from `runMarkSent`). **3a:** Pick → Replace → Remove → pick again, watching the preview; after Remove, Mark as sent → "Evidence required" before any network call (`send/[id].tsx` checks `localUri` first); A reads back no new object |
| DV-IMG-4 | P | `92ee5156…`: airplane mode on after picking → Mark as sent (offline wording, Retry, no success) → off → Mark as sent. A: one object (name, metadata mimetype/size/eTag, seller download sha256 + first 16 bytes; extension ↔ mimetype ↔ magic bytes agree), one transition, buyer inbox +1 (`buyer_confirmation_needed:92ee5156…`) |
| N1, N2 | N | after DV-IMG-4, A as the seller (JWT, not service_role, not psql): `mark_transfer_sent(92ee5156…, seller, <DV-IMG-4 path>)` then with a **different** path string → `already_sent`, `evidence_replaced=false`, returned path = DV-IMG-4's; row unchanged; inbox +0. The only lost-response retry evidence on the applied database, since a handset cannot force a lost response |
| DV-IMG-5 | P | `bce07eef…`: two quick taps → one object, one transition, one success, inbox +1. **Never merged with DV-IMG-4** (each row's evidence is "one object, one mark") |
| DV-IMG-9 + 3b | P | `3118bd30…`: pick a synthetic **screenshot**, **Replace** it with a HEIC camera photo of a synthetic image, Mark as sent. **Location (owner ruling 3; B, from expo-image-picker 17.0.10 `ios/ImageUtils.swift`):** a `.heic` result is passed through as raw data with its original metadata, including GPS; `exif: false` only limits what JavaScript receives. So the photo is taken **with Camera location off**, or Photos › Info is checked to show no location before picking. A records only whether a GPS block is present (yes/no), never its values. **Expected: `.jpg`, `ffd8ff`, `image/jpeg`** (Compatible mode). PNG bytes → the stale image was sent, **3b FAILS**. `.heic` with `ftyp` bytes → a finding for C: outcome 3 FAILS, not a storage failure. The owner observes the render on the iPhone. **Not render surfaces:** the operator console (bound to production), and the web receive page, which is UNTESTED because its Supabase host is fixed at build time and `web/next.config.ts` defaults to production |
| N3 | N | **before** DV-IMG-10: `mark_transfer_sent(8f59d37e…, seller, <any path>)` → exactly `precondition_failed: transfer already sent without evidence — use attach_transfer_evidence`; row unchanged; inbox +0 |
| DV-IMG-10 | P | `8f59d37e…`: the Add proof section shows (only while seller_sent with no path, `send/[id].tsx:372`) → Add proof → **`attached`** → the screen re-reads and the section disappears (`:209-211`). **On the handset this row can only produce `attached`.** A: path null → the uploaded name, nothing else changes, inbox +0 |
| N4 | N | after DV-IMG-10: `attach_transfer_evidence(8f59d37e…, <DV-IMG-10 path>)` → `already_attached`; row unchanged |
| RT6 | read | the buyer (JWT) signs and downloads each P object (DV-IMG-4, -5, -9, -10) → 200, sha256 = the seller's download |
| **U1** | read | **U2 `f53b8466-9571-4f41-88c3-1c33847dd8ee`**, an existing sandbox test account whose credentials are in the sandbox env by NAME (`U2_EMAIL`/`U2_PASSWORD`). Read at 14:51:11Z: active, not banned, `deletion_state` ACTIVE, party to **none** of the five transfers above (buyer on 6 others), and no `proof-docs` policy mentions a role, admin or operator. U2 signs and makes an authenticated download of DV-IMG-10's referenced object → denied at both. **This counts only when paired with the seller's successful read of the same name in the same minute**, and never through a URL the seller signed. Until U1 runs: "unrelated authenticated user UNTESTED" |
| RT5-P | read | anon → the same referenced object → denied, with the same positive control |
| DV-IMG-8 Android | — | UNTESTED: no device |
| DV-N-1..3 | T2 | banner shows the server title/body; Dismiss → `read_at` (A); relaunch → not shown; unknown type → Dismiss only |
| DV-611C-2 | N | register-call counting half; push half DEFERRED |
| DV-131-1 | authorized write | the epoch bump within 2 s of a sign-in on C's trigger |
| Settings truth (cf94311) · F-2S-1 wording (df5127c) · Tickets label ABSENT in the preview build (ac70643) | N | copy and visibility |
| DV-ST2a / ST2b | T3 | **ST2a PASS on Build 18** (window closed 15:29:36Z). ST2b UNTESTED: it needs a new revoke window (pull-to-refresh with rows loaded) on the owner's word, and **no bid fixture** (the Bids tab merges the buyer's transfers: 21 rows; manifest §13) |
| Carried at true status | — | two-session K-2 UNTESTED · row 18 DEFERRED · A11Y-1 UNTESTED · every push-delivery row DEFERRED · HEIC conversion UNVERIFIED until DV-IMG-9 · F-AUTH-2 open (LOW, not blocking) |
**Not run, by owner ruling 2:** N5 (attach with a different path) and any handset different-photo attempt; any delete or overwrite of
attached proof. The evidence instead is PC3 (the live bodies of both `mark_transfer_sent` overloads, `attach_transfer_evidence` and
`guard_transfer_state_columns` equal a local replay at the pin), the preserved local evidence (207's R-series, mutant-verified, and
050's custody assertion), and PC5 (the `proof-docs` policy quals equal the chain's).
**Order (C and B):** PC1–PC8 → picker-only N rows on `3118bd30…` → DV-IMG-4 → N1, N2 → DV-IMG-5 → DV-IMG-9 + 3b → N3 → DV-IMG-10 → N4 →
RT6 → U1 → RT5-P → close: PC2 and PC3 again, then the closing equation: folder total = PC8 baseline + 4 referenced P objects + listed
orphans; `rt-%` = 0; an object that fits none of those stops the close. A submitting row that ends uncertain is recorded as it stands;
any replacement fixture is a new write for the owner, and nothing is re-run on `83b83858…`. No P row or round trip overlaps
a DV-ST2 revoke window (any ST2b re-run is a new window on the owner's word).

## 7. Image round-trip evidence checklist (B with A) — ADOPTED
B's checklist is copied byte-identical to `docs/release/IMAGE_ROUND_TRIP_EVIDENCE_CHECKLIST_20260917.md` (from
`feature/venue-native-and-product-v2 @ fb25c9e`; sha256 `d718ec47465396408d0c1517996f00d3bfe9c11fc888e38966574bb8ae5669a3`). B made
no sandbox or production read; its source pins are 259246e (migrations) and 5e14a68 (client). **Its pre-conditions PC1–PC8 are Line 3's
pre-conditions, and PC2/PC3 are read again at the close.** Where the owner's rulings of 2026-09-17 settle B's named decisions, the
rulings govern:
- **U1 = U2** (ruling 1);
- **N5 not run: option (b)**, with no destructive overwrite or delete test (ruling 2; B's recommendation);
- downloads only of the exact test uploads, as the seller and the buyer (ruling 3);
- no 401 expected from the notifier path, and no response logs used as proof of silence (ruling 4);
- the transfer register and disposition in §5a (ruling 5).

B's corrections are applied as follows:
- C1/C2 → §5 notification expectation;
- C3 → DV-IMG-10 produces `attached` only, and N4 is an API probe;
- C4 → N5 not run;
- C5 → U1;
- the denial-pairing rule → U1, RT5-P, and Line 1's RT4/RT5;
- C7 → the `rt-%` count in Line 1 and §5;
- C8 → no live delete or overwrite of P objects;
- C10 → §5a;
- DV-IMG-9's expected `.jpg`/`ffd8ff`/`image/jpeg` → §6;
- sips brand → record the actual file's brand in Line 1.

**PC3 method (B's replay, checked by A):** PC3 compares **`md5(prosrc)` and `length(prosrc)`**, the method PF3 uses. `prosrc` is the migration text verbatim, whereas `pg_get_functiondef` is regenerated by the server and can differ without a code change; its md5 is recorded, but a difference in it alone is investigated, not a stop. Expected values: B's local replay at 259246e on PG 17.11, **matched independently by A's certified harness DB** (`snatchit_cand2_rehears`; `259246e..f412d10` changes 0 lines under `supabase/migrations`).

| Function | md5(prosrc) | length |
|---|---|---|
| `notify_transfer_event()` | `49146f9f3ba9a96aaaf09c3f21492c40` | 1361 |
| `notify_transfer_state_inbox()` | `203f7c7d88c6545a9c083e037a6aa5db` | 3442 |
| `enqueue_notification(uuid,text,text,text,text,text,jsonb)` | `1e11b92d7258ea66feebbac05cf9298b` | 518 |
| `guard_transfer_state_columns()` | `c423ef62372e43e5c4c91e5e83976782` | 1951 |
| `mark_transfer_sent(uuid,uuid,text)` | `17453329765e9e0787732fd61846a399` | 2560 |
| `mark_transfer_sent(uuid,uuid)` | `d816c53e9e1e77e7de8d432d7ecf9680` | 86 |
| `attach_transfer_evidence(uuid,text)` | `67615b89040a9f60dd6082d1cf54cbcd` | 2690 |
B's `pg_get_functiondef` md5s are recorded for reference: `3546027f…`, `37a46d03…`, `60516c25…`, `0b630eef…`, `d9addfdb…`, `f7a46322…`, `7d98e647…` (same order).
**C8 (behavioural test of the delete/update policies against a referenced object) stays a recorded gap for this candidate, by A as gate owner.** Storage tests are catalog-level only by design (`100_storage.sql:10-15`), because a `storage.objects` fixture depends on the storage-api shape and could break the gate on a runner upgrade. PC5 qual equality is the window's evidence; B's pinned-shape option (ii) remains a post-candidate option.

## 8. Final approval request (each line separate; none is granted by this document; the owner's 2026-09-17 message settled the test design but started nothing)
1. **Tag + build:** "Create `candidate/2026-09-18-build-c3` at `f412d10` and have C submit one sandbox preview build." (D's review of
   F-NAV-1, integration, A's reruns, CI 35237352892 and D's merge gate are all complete; a tag records a reviewed, CI-green tree, not a working
   image flow or a verified Keep editing on a handset.)
2. **Sandbox window W-C3:** "Apply 136 → 139 → 140 to the sandbox and deploy stripe-webhook and notify-report from the tag commit, A
   executing, D witnessing, per §4, with its pre-flight, stopping conditions and rollback."
3. **Staged notice (temporary):** "Execute the §3b staged-notice write for the DV buyer and delete it after DV-N-3."
4. **Image round trip (temporary; needs neither the build nor 140):** Line 1 of `SANDBOX_AUTHORIZATION_LINES_20260917.md`.
5. **Permanent device-test transfer writes and their reads:** Line 3 of the same document. It covers:
   - DV-IMG-4, -5, -9 (+3b) and -10 on the four named transfers, with synthetic ticket images;
   - probes N1–N4;
   - downloads of exactly those uploads as the seller and the buyer;
   - U2's and anon's denied reads;
   - PC1–PC8 and the close;
   - no N5, and no delete or overwrite of attached proof.
6. **Bid fixture: NOT REQUESTED.** Line 2's only purpose was DV-ST2b, and its premise ("0 rows, so the clause cannot be observed") was wrong: the Bids tab merges the buyer's transfers and held 21 rows. ST2b needs only a new revoke window, which is the owner's call.
**Dependencies:** 1 before any device row · 2 before 3 and 5 · 4 can run before the build 
**Open item for the owner (recorded after line 1 was authorized):** **F-BIDS-1 (C; A verified in `f412d10` source): Bids shows its empty state while purchases are still loading, and after a failed purchases read.** Owner-observed on Build 18 under Very Bad Network, 11:37–11:39 EDT, on the DV buyer with 21 purchases (exact wording not captured). Cause, identical at `aad5f75` and `f412d10`: (A) `fetchMyBids` clears `loading` right after the `public.bids` read (`app/(tabs)/bids.tsx:148`), before the transfers read, so with 0 bids the empty state renders until purchases arrive; (B) the transfers read's error is never checked (`const { data: txData } = …`), so a failed purchases read renders as "nothing", and a silent refresh whose transfers read fails would replace on-screen purchases with bids-only rows (source only). Reproduction: C's local branch `investigate/bids-empty-while-loading @ c07757e`, not pushed and not for integration: a control passes; R1 (empty while in flight) and R2 (empty after a failed read) fail; the causal probes separate (A) and (B). **Severity MEDIUM** (a purchase with an open dispute can look absent, briefly or indefinitely; no money action; pre-existing). **Release effect: does NOT block the c3 preview build** (identical code, no regression; c3 exists for F-NAV-1 and the image flow). **Owner's scope decision (2026-09-17): implement now on a separate branch for the NEXT candidate** (both premature empty states, purchase-load failures, loaded purchases kept on a failed refresh with a clear failure indication, behavioural tests, D review, reviewed head to A); **c3 stays unchanged.** DV-ST3's "not shown while a load is in flight" is recorded as FAILING on Bids. ST2b is unaffected: a refresh with bids revoked returns before the transfers read.
Off this candidate's critical path by the owner's ruling: cleanup scheduling, native issuance/scanning, the broader onboarding build
(138), the My Listings redesign (separate visual approval), 137, the venue window.

## 9. Review record carried verbatim (D asked these to survive any summarising)
**What that gate is, in D's words:** narrow by design — it asks whether the merge preserved what D passed at 9d01bad and 259246e, not whether what D passed was right; the substantive reviews were on those heads, and a chain of "D passed it" entries must not be read as more scrutiny than it was;

**Scope of the D entries, in D's words:** the substantive reviews were at 5e9c80b, 5e14a68, 9d01bad, 259246e, 251cda2 and the earlier heads; the gates on e9b52ce, 4331ea4, 759d3a0 and db16e1a are merge-preservation checks, not independent examinations — six "D passed" entries are not six reviews.

**A tag on db16e1a records a reviewed, CI-green tree; it does not record a working image flow on a handset.**

**D's closing confirmation (2026-09-17, after reading run 35188006272 independently): the candidate at db16e1a carries no open review item from D.** D's review record, in D's words: 136 (three revisions), 139 (three), aeb4081, 140 @ 251cda2, 050 @ 259246e, C's heads 577ec40, df5127c, cf94311, da1d11d, 296439c, c0281aa, 9d01bad, 5e9c80b, 5e14a68, and merge gates on e9b52ce, 4331ea4, 759d3a0, db16e1a; every substantive review re-ran the author's own evidence rather than accepting it. D's own errors, recorded at D's request: two defects in 138 (one made it inert, one left the two-person bypass unguarded on the only path that mattered), a prescribed fix that could not work, a device-failure attribution to the header when the surfaces were not using the helper, and a mutant set whose reverts silently did not revert — each on the registry row in D's words.

**The only device evidence that exists** — DV-S1 steps 1, 2, 3a, 3b and the DV-S2 failure (now fixed in source, unverified on a device) — **came from the owner holding a phone, not from anything in CI.**

*(A, after D wrote the line above: the owner's DV-S2 step 3 on Build 18 added a second device failure, F-NAV-1 — Keep editing leaves the edit screen — also observed on the owner's phone, time not captured.)*

**Lesson recorded beside B's mutation-fidelity note (D, 2026-09-17):** a test must be able to fail *for the reason it names*, which means reading the fixture, not only the assertion — the fix D and A first prescribed (retry on transfer A) would have hit 140's "use attach" refusal and never reached the branch it aimed at; a reviewer prescribing a fix owes the author's diligence.

**Recorded intention (D, not this candidate):** F-SELL-2 makes the top-inset contract uniform (every screen pays its own), which turns `SecurityNoticeBanner`'s interim `paddingTop: useTopInset()` into the single exception; when its DV-N row comes up the banner should become an overlay like `SandboxBadge` and drop the padding.

