# Candidate c3 — execution package and final approval request (A, 2026-09-17) — BUILD HELD for F-NAV-1; nothing here is tagged, built, applied or deployed

**Supersedes** the `4dbee98` version of this file, which is preserved byte-for-byte in git
(`4dbee98:docs/release/NEXT_CANDIDATE_PACKAGE_20260917.md`, sha256 `347bf5eb842d588d2361d9af08e834c2f160ee290d7b65f269c9bb425629c8c8`).
The layered status sentences of that version ("pending D", "still to join", "running") are gone: every status below was re-derived
from the stack, CI and the reviewers' own records on 2026-09-17, and it is stated only in §0. D's statements that D asked to
survive are carried verbatim in §9.

## 0. Status — the only place status is stated
| Item | State (2026-09-17, after the 14:35Z sandbox read) |
|---|---|
| **Build** | **HELD.** The owner's hold came first through C and then directly to A: no build until C's Keep editing fix (**F-NAV-1**) has passed D's review and been integrated. **C's head `2ba9e3a` was sent on 2026-09-17 and is with D for review;** A's static checks are in §1 |
| Reviewed, CI-green tree | `db16e1a` on `release/production-gate-20260918`, tree `aa93c03b`. CI 35188006272 succeeded on all five jobs; D's merge gate PASSED; D's closing statement: no open review item. **Every constituent review is closed (§1). No review is pending on this tree.** |
| Tag line | will name **`db16e1a` + `frontend/unsaved-guard-native-dismiss @ 2ba9e3a`** once D passes it and A integrates. `candidate/2026-09-18-build-c3` does not exist |
| What a tag will mean | a reviewed, CI-green tree, **not a working image flow on a handset** |
| Checks F-NAV-1 reruns (only what it can affect) | vitest, tsc and lint on the merged tree; CI on the new head (all five jobs); D's merge gate. **The DB evidence and the §3 pins carry over only if** `git diff --quiet db16e1a <new head> -- supabase/ scripts/ .github/` holds. If that diff is non-empty, A regenerates the pins and reruns replay, Gate-2, pgTAP and census before issuing line 1 |
| Sandbox | unchanged since the B2 window; read 14:35:00–14:35:40Z (§2) |
| Production | ledger 135; nothing applied since 2026-09-12. Nothing in this package reads or touches production |

**Evidence limits (the owner's words, unsoftened):** "database outcomes 1 and 2 passed; image conversion and buyer display remain
unverified until a real iPhone round trip, and the remaining device behavior needs a build. Do not describe the whole image issue as
fixed yet." "A MIME allow-list match does not establish that the bytes render correctly." Current statuses: outcome 3 UNVERIFIED
(DV-IMG-9) · outcome 4's device half unrun · **DV-S2 on Build 18 is not a full pass:** header clearance FAILS at the largest text
(F-SELL-2, fixed in source at 9d01bad, device re-check on the next build), and **Keep editing returns to My Listings instead of
keeping the edit screen open (F-NAV-1, fix in progress; the owner: do not infer that unsaved text survived)**; Discard PASSED;
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
| **F-NAV-1** | `frontend/unsaved-guard-native-dismiss @ 2ba9e3a` (C; one commit on `db16e1a`; 4 files: `src/hooks/useUnsavedChangesGuard.ts`, `tests/helpers/nav-stack-harness.ts` (new), `tests/unsaved-guard-native-dismiss.test.ts` (new), `tests/premium-reversible-and-forms.test.ts` (pin)) | **with D**; A static checks done (below) | the guard moves from a bare `beforeRemove` listener to `usePreventRemove(opts.when, …)`, so native-stack sets `preventNativeDismiss` and an iOS swipe is cancelled natively; the same dialog decides; Discard replays the action once. It also covers the other two screens that use the hook (the report form and Settings → Preferences) |

**F-NAV-1 — C's evidence, and A's static checks (2026-09-17):** *Root cause (C):* the guard held the pop in navigation state only. On iOS, native-stack 7.14.4 prevents a swipe natively only for routes registered through `usePreventRemove`, so UIKit completed the swipe, `onDismissed` dispatched a pop the guard refused, and the dialog appeared over My Listings. Discard replayed the pop, so state caught up with the screen and it *looked* right; Keep editing did nothing, which left the edit route in state but off screen. The in-screen Back arrow (`router.back` → GO_BACK) starts in JavaScript, is refused before anything moves, and **by source already held on Build 18. No device has checked that.** *A verified from installed source:* versions native-stack 7.14.4, core 7.16.1, native 7.1.33, react-native-screens 4.16.0; `NativeStackView.native.tsx:278/410` sets `preventNativeDismiss` from `preventedRoutes[route.key]?.preventRemove` only; `usePreventRemove` calls the latest callback (`useLatestCallback`); a replayed action carries `VISITED_ROUTE_KEYS` (`useOnPreventRemove.tsx`), so Discard is not asked twice; one guard per screen (`app/listing/edit/[id].tsx:64`, `app/report/[type]/[id].tsx:53`, `app/settings/preferences.tsx:79`); `git diff db16e1a 2ba9e3a -- supabase/ scripts/ .github/` plus the gated client surface: **0 lines**, so the §3 pins and the DB evidence carry over. *Tests (C):* 17, rendering the real Edit listing screen and hook with real React Navigation core + StackRouter. **The native-stack/RNS iOS layer is a model** pinned to the installed source and versions, so the tests prove behaviour against that model and only the device row proves UIKit. RED on the `db16e1a` hook: 3/17, all swipe rows, with the owner's symptom (`['my-listings']` instead of `['my-listings','listing/edit/[id]']`). **Deviation accepted:** the Back-arrow rows cannot be RED because that path has no defect in source; they are regression guards proven able to fail by M2. Mutants 6/6 killed as predicted (M1 swipe = the db16e1a hook → 3; M2 Back arrow skips the prompt → 4; M3 Keep editing dispatches → 4; M4 Discard no-op → 2; M5 `usePreventRemove(true)` → the 4 clean/undone rows; M6 dirty ignores Event name → 8), with a clean baseline, an anchor matched once, and a digest-verified restore. **Gap (C's own):** no mutant targets the typed-text assertion alone, so its ability to fail is not yet shown; A asked for one (a Keep editing that keeps the route but resets the form). *Counts (C, on 2ba9e3a):* tsc 0; lint 0 errors / 29 warnings; vitest 2221 in 105 files, not run concurrently. A reruns these on the integrated head.

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
The mapping is A's proposal; C confirms it against the rows. There is no pending spare: if a named transfer is not in its §2 state at
the pre-read, A stops and reports. There is no silent switch and no new fixture. (Option for C: run DV-IMG-5's double tap as
DV-IMG-4's second attempt, which frees `bce07eef…` as a spare at the cost of attributing a failure to one of two causes.)

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
| Close | A and D closing reads | zero drift on business counts; queue 0; no 2xx in `net._http_response`; Vault `project_url` only; executors false | any drift, any 2xx, any production ref or `*.supabase.co` literal introduced |
A step never proceeds while one of D's reads is unexplained.

**Rollback (only on the owner's order; never automatic):** edges first: notify-report is redeployed from the PF6 capture, and
stripe-webhook from `9bef640` (tag `candidate/2026-09-18-pin-b2`). Then migrations 140 → 139 → 136 from the exec tree's
`supabase/rollbacks/` (sha256 §3), each followed by deleting its ledger row and re-reading the pre-state (for 140, the PF3 md5s). **A
rollback restores code, not data:** a sent status, an attached path and a referenced object written by the P rows stay, and the void
bodies still read them. S5's notice row is deleted at its own cleanup, before any 136 rollback.

## 5. Shared-environment effects by class — temporary versus permanent
| Class | Tests | Records touched | Removal |
|---|---|---|---|
| **T1 temporary** | image round trip RT1–RT5, RT7 (Line 1) | three `storage.objects` rows under `…/transfer-evidence/rt-20260917-*` | deleted at RT7; folder count back to 0; nothing retained |
| **T2 temporary** | staged security notice (S5, batch plan §3b) → DV-N-1..3 | one `notify.notification` row for the DV buyer (`read_at` set by DV-N-2); 0 delivery rows | deleted by id after DV-N-3; buyer pre-count restored; `notify.delivery` total unchanged |
| **T3 temporary** | DV-ST2a (standing authorization, C's trigger) | `public.bids` relacl | restored and verified immediately |
| **N no write** | F-NAV-1, F-SELL-2, Event name, F-DT-1, DV-IMG-1, -2, -3, -6, -7 (picker only: Transfer send and the Sell form are **never submitted**), copy rows, the DV-611C-2 counting half; Line no-write probe NP | none | — |
| **P permanent** (Line 3) | DV-IMG-4, -5, -9 Mark as sent with proof; DV-IMG-10 Add proof; RT6 reads the attached object | `public.transfers` status, `seller_sent_at`, `auto_release_at` (+72 h), `transfer_evidence_path`; the referenced `proof-docs` object; buyer inbox rows from `trg_notify_transfer_sent` / `trg_notify_transfer_state_inbox` | **none possible or proposed.** The state guard and the append-only guard make these one-way, referenced objects are evidence and stay, and orphans left by refused or failed attempts are retained under the owner's 30-day direction |
| **P permanent** (Line 2) | cached-bids fixture | `public.bids` +1, D8's counters, seller inbox +1 | not removable; seller cancel (R) or let it end (R′) |
| authorized write | DV-131-1 epoch bump | as already authorized for session 2 | — |
**What outlives the P rows:** after Mark as sent, `auto_release_at` = now + 72 h. `8f59d37e…`'s deadline has already passed, and Add
proof removes its `EVIDENCE_MISSING` reason. **No release or payout can follow on the sandbox while both of these hold:**
`payout.executor_enabled` = false, and the Vault has no `service_role_key` (so `enforce-transfer-expiry`'s cron post is refused).
This is recorded so that a later change to either makes these four transfers expected release candidates, not a surprise. **During
these tests, the buyer never taps Confirm received or Report a problem on a P transfer** (`confirm-and-release` v3 is deployed and
is outside this scope).
**DV-IMG-3 wording to confirm with C:** "no stale image sent" must be observable without a send. If it needs one, the row moves to
P and needs a named transfer, which does not exist without giving up a spare.

## 6. Targeted device tests on the next build (C guides; owner's handset; A reads back; D witnesses; all UNTESTED until run)
| Row | Class | Exactly |
|---|---|---|
| **F-NAV-1 re-check** | N | Edit listing on a bid-free listing (Phone P1 `c343406e-be85-49c1-9951-ac08bb1daab2`; Save changes is never tapped): change Event name → swipe back → **Keep editing** → still on Edit listing **with the change visible**; leave again → asked again; repeat with the **in-screen Back arrow** (there is no native header); then Discard → My Listings after one prompt; with no edit, or with an edit typed and undone → leaves at once. The Back-arrow half is also Build 18's first device observation of that path |
| F-NAV-1 same hook: report form | N | type in a report → swipe back → **Keep writing** → still on the form with the text; the report is **never submitted** |
| F-NAV-1 same hook: Settings → Preferences | reversible own-preference write | toggle a preference and swipe back while it is saving → "Still saving" → **Wait** → stays; then restore the toggle (A reads back the value before and after). Observable only while the save is in flight; if it completes too fast to catch, the row is UNTESTED, not passed |
| F-SELL-2 re-check | N | the badge clears every header at normal and largest text; no doubled spacing. My Listings, one SettingsHeader screen and the security banner are checked at the largest text in one look |
| Event name "mostly visible" | N | UNRESOLVED until directly confirmed |
| F-DT-1 | N | does a text-size change apply without a relaunch |
| DV-IMG-1, -2, -3, -6, -7 | N | picker behaviour, never submitted |
| DV-IMG-4 | P | `92ee5156…`: airplane mode on after picking → Mark as sent (offline wording, Retry, no success) → off → Mark as sent; A reads back one object, one transition, success only after the verb answers |
| no-write probe NP | N | after DV-IMG-4, A as the DV seller via the API: 3-arg `mark_transfer_sent` on `92ee5156…` with the same path, then a different path → `already_sent`, row unchanged (md5 of the row), no new inbox row; 3-arg with a path on `8f59d37e…` **before** DV-IMG-10 → `precondition_failed`, row unchanged. This is the only lost-response retry evidence on a real applied database; a handset cannot force a lost response |
| DV-IMG-5 | P | `bce07eef…`: two quick taps → one upload, one verb call, one success |
| DV-IMG-9 | P | `3118bd30…`: a HEIC **camera photo** (not a screenshot). A reads back the stored object: magic bytes (`FF D8 FF` JPEG versus `ftyp` HEIC), name extension, Content-Type, sha256. The render is observed by the owner on the iPhone. **The operator console is bound to production and is not a render surface for a sandbox object;** the web receive page counts only if C shows it points to the sandbox, otherwise that half stays UNTESTED. If the bytes are HEIC, the label must say HEIC and the row FAILS outcome 3 |
| DV-IMG-10 | P | `8f59d37e…`: the Add proof section shows only here → Add proof → `attached` (A reads back the path) → same photo again → `already_attached`, no second object → a different photo → "can't be replaced" (guard refusal; its uploaded object stays as a retained orphan) |
| RT6 | read | after DV-IMG-10: the buyer signs and downloads the attached object → 200, sha256 = the seller's upload; an unrelated account and anon → denied |
| DV-IMG-8 Android | — | UNTESTED: no device |
| DV-N-1..3 | T2 | banner shows the server title/body; Dismiss → `read_at` (A); relaunch → not shown; unknown type → Dismiss only |
| DV-611C-2 | N | register-call counting half; push half DEFERRED |
| DV-131-1 | authorized write | the epoch bump within 2 s of a sign-in on C's trigger |
| Settings truth (cf94311) · F-2S-1 wording (df5127c) · Tickets label ABSENT in the preview build (ac70643) | N | copy and visibility |
| DV-ST2a / ST2b | T3 / Line 2 | as authorized / after the fixture |
| Carried at true status | — | two-session K-2 UNTESTED · row 18 DEFERRED · A11Y-1 UNTESTED · every push-delivery row DEFERRED · HEIC conversion UNVERIFIED until DV-IMG-9 · F-AUTH-2 open (LOW, not blocking) |
**Order:** N rows first. DV-IMG-4 before probe NP; probe NP before DV-IMG-10; DV-IMG-10 before RT6. No P row, bid fixture or
round trip ever overlaps a DV-ST2 revoke window. The bid fixture comes only after C confirms DV-S2 complete.

## 7. Image round-trip verification and evidence checklist (B with A)
B was sent the anchors (the T/N/P split, the transfer ids, the pre-counts, and the trigger-path question) on 2026-09-17. B's
checklist lands here under B's name when handed off; until then Line 1's scope in `SANDBOX_AUTHORIZATION_LINES_20260917.md` is the
exact scope.

## 8. Final approval request (each line separate; none is granted by this document)
1. **Tag + build — HELD:** "Create `candidate/2026-09-18-build-c3` at `<db16e1a + F-NAV-1>` and have C submit one sandbox preview
   build." Issued with the head filled in only after D's review of F-NAV-1, integration, the §0 reruns and green CI.
2. **Sandbox window W-C3:** "Apply 136 → 139 → 140 to the sandbox and deploy stripe-webhook and notify-report from the tag commit, A
   executing, D witnessing, per §4, with its pre-flight, stopping conditions and rollback."
3. **Staged notice (temporary):** "Execute the §3b staged-notice write for the DV buyer and delete it after DV-N-3."
4. **Image round trip (temporary; does not need the build or 140):** Line 1 of `SANDBOX_AUTHORIZATION_LINES_20260917.md`.
5. **Permanent transfer writes by the device tests:** Line 3 of the same document (with the no-write probe NP).
6. **Bid fixture:** Line 2 of the same document.
**Dependencies:** 1 before any device row · 2 before 3, 5 and RT6 · 4 can run before the build · 6 after C confirms DV-S2 complete.
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

