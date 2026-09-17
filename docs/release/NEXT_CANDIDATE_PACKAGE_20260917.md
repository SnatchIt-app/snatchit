# Next-candidate package (A, owner's sprint 2026-09-17) — FOR APPROVAL; nothing here is tagged, built, applied or deployed

**What this is:** the one package the owner asked for — code, required sandbox updates, targeted device tests, and the exact
image round-trip scope — brought once reviews and combined CI are complete. **Status: FINAL for the current candidate tree `4331ea4` (D PASS on the head; CI 35186869113 green on five jobs). Since then two of the three pending heads have joined: C's F-SELL-2 (`9d01bad`, D PASS) and B's test-only 050 follow-up (`259246e`, D confirmed). **Current stack head `759d3a0`** (= 4331ea4 + 9d01bad + 259246e), **CI 35187366429 success on all five jobs**; local vitest 2176/2176 (103 files), tsc 0, lint 0 errors; 050 21/21 on the candidate DB. **One head still joins before any tag:** C's client adaptation to 140's outcome codes plus the attach entry point (branched from 759d3a0). The tag line names the head at that time. The approval lines in §5 can be given now; the tag line names the head at that time.**

**Evidence limits (the owner's words, carried unsoftened):** database outcomes 1 and 2 pass; **outcome 3 does not** — image conversion and buyer display are unverified until a real iPhone round trip (DV-IMG-9); outcome 4's device half (DV-IMG-1..8) is unrun; **the whole image issue is not fixed**; DV-S2 header clearance FAILS at the largest accessibility text size on Build 18 (F-SELL-2, fix at 9d01bad pending D; device re-check on the next build); the sandbox push key stays deferred, so every push-delivery row remains UNTESTED, not passing; the one known-vacuous test line (050's first evidence-path assertion, which compared a null path to itself through the 2-arg fixture) is **closed by B's follow-up 259246e**: the custody assertion now runs the 3-arg retry with a different path on the seeded transfer that holds an original, and fails under the writing mutant (B and D each ran it: 051→21/21 baseline, `not ok 19` under the mutant, 0 on restore). **Lesson recorded beside B's mutation-fidelity note (D, 2026-09-17):** a test must be able to fail *for the reason it names*, which means reading the fixture, not only the assertion — the fix D and A first prescribed (retry on transfer A) would have hit 140's "use attach" refusal and never reached the branch it aimed at; a reviewer prescribing a fix owes the author's diligence.

**D's post-integration PASS on 4331ea4 (tree and client only; not a deployment-readiness statement):** ancestry of e9b52ce, 251cda2, 912a7d6, c0281aa, 7612c8b, ae09f5b; load-bearing content present (140's `already_sent` writing nothing, the backfill refusal, the 2-arg delegation; the 050/207 additions; c0281aa's `sniffImageType`, `settleUpload`, recall guard, `statusAfterUnpicked`; 136 rev3's unread-only termination); tsc 0; vitest 2157/2157 in 102 files measured by D independently; 207 37/37 and 050 20/20 on D's own replay at 251cda2. The replay, Gate-2, full pgTAP and census figures are A's, from A's certified harness. No production change, no shared-environment application, no build submission and
no outbound notification is proposed as already authorized; each is a line for the owner below.

## 1. Code — the candidate tree
| Layer | Head | Review | Contents |
|---|---|---|---|
| Base | `e9b52ce` (stack, batch 1) | D PASS; CI 35181982625 | 136 security-notice read/ack + template v2 · 139 notify-report delivery claims (+ G16) · aeb4081 webhook honours `notify_listing_sold` · C: cf94311 hide five switches, df5127c neutral challenge copy, da1d11d security-notice surface, 296439c F-611C-2, ac70643 dev-only tickets label |
| Server | `fix/140-proof-upload-repair @ 251cda2` | A PASS (912a7d6, from source); D PASS on substance (912a7d6); **D delta review of 251cda2 pending**; CI 35186394898 | 140: idempotent `mark_transfer_sent` (jsonb, both overloads), `attach_transfer_evidence`, rollback = applied 0550/0553 bodies; 207; 050 pins both halves |
| Client | `frontend/proof-image-flow @ c0281aa` | D PASS (client half); gated surface unchanged | byte-sniffed type, HEIC via picker compatible mode, 120 s bounded upload + 30 s exists-check, status read before/after mark-sent, recall-guard test, 33 tests / 21 mutants |
| Client | `frontend/sandbox-header-inset @ 9d01bad` (C; F-SELL-2) | **D PASS** (19/19; D's own sweep: only the badge and the helper still read `insets.top`; no doubling in the settings nesting; three mutants fatal incl. D's badge-scaling one) — **INTEGRATED on the stack** (see candidate head) | `useTopInset()` on eleven surfaces + the outbid toast; production spacing identical; no doubled insets; sandbox builds only |
| Rehearsal | `c3461a0` = e9b52ce + 251cda2 + c0281aa (clean merge; tree `82872cf6`) | A, 05:40–05:41Z | **replay clean; Gate-2 32/108/37/38; pgTAP 5296/5296 (050 20/20, 157 294/294, 162 86/86, 203 36/36, 204 41/41, 207 37/37); census notify 22 / five-schema 305 / mark-sent overloads 2 (jsonb) / attach 1; vitest 2157/2157 (102 files); typecheck 0; lint 0 errors** |
| Candidate head | **`4331ea4`** on `release/production-gate-20260918` (0523793 = 140 @ 251cda2; 4331ea4 = c0281aa); tree `82872cf6` = the rehearsal; F-SELL-2 and B's 050 follow-up still to join | **CI 35186869113 success on all five jobs** (Typecheck/Lint/Unit tests; Admin console; Web build; Deno type-check; Migrations apply cleanly on a fresh DB) | build-source tag proposed: `candidate/2026-09-18-build-c3` — **not created until the owner's word** |

**Recovery behaviour verified on the combined tree (owner item 2):** server — 207 R3/R4/R5/R6/R7/R9 (same-path, different-path and 2-arg retries answer `already_sent`, write nothing, notify nothing, replace nothing), S1–S13 (attach eligibility, guard-armed write, dangling path refused); 050 pins `seller_sent_at` and `transfer_evidence_path` unchanged across a retry. Client — `tests/proof-image-flow.test.ts` + C's mark-sent suite in the 2157: status read before and after, success only on a sent read-back, the already-sent answer never shown as failure, timeout treated as uncertain then decided by `storage.exists`. **Not verified anywhere yet:** the client's handling of 140's actual jsonb outcomes end to end against a database (C adapts `runMarkSent` to `transitioned | already_sent`; today the client reads status, not the outcome) — a device row on the next build with 140 applied on the sandbox.

## 2. Required sandbox updates (each needs the owner's application authorization; none is applied by this package)
Sandbox today: pin `9bef640` + 131, 132, 133, 135, 20260916000000 (ledger 141); Vault `project_url` only; edges create-payment-intent v5 / send-push v4 / enforce-transfer-expiry v4 / stripe-webhook v4; push key DEFERRED.
| # | Update | Why the device tests need it | Order / pre-flight / rollback |
|---|---|---|---|
| S1 | apply **136** | the security-notice banner (da1d11d) reads `get_my_security_notices()`; without 136 the surface has nothing to call | after CS-1 identity assertion; ledger 141 → 142; rollback `136_..._rollback.sql` (drops both wrappers + v2 row) |
| S2 | apply **139** | server-only (notify-report claims); no device row; applied to keep the sandbox = candidate chain | 142 → 143; rollback file in `supabase/rollbacks/` |
| S3 | apply **140** | DV-IMG rows for mark-sent retry and attach need the jsonb verbs and `attach_transfer_evidence` | 143 → 144; rollback restores the applied 0550/0553 bodies byte-identically (hash-verified) |
| S4 | deploy **notify-report** (139's edge) and **stripe-webhook** (aeb4081) to the sandbox | 139's claim release; the `notify_listing_sold` preference read (test-only until push is testable) | `verify_jwt` posture read BEFORE deploy (not inferred — the B2 near-miss); no other edge changes |
| S5 | **staged security notice** (batch plan §3b): one `notify.enqueue(...)` row for the DV buyer | the only way to see the banner on a handset without push delivery | its own authorization line (write) |
| S6 | **no push key** | push-delivery rows stay DEFERRED | — |
Apply order S1 → S2 → S3 → S4 → S5, in one owner-authorized window, A executing, D witnessing, with the B2-window pre-flight (drift 0/0, ledger count, census before/after) and per-step md5s recorded in the manifest.

## 3. Targeted device tests on the next build (C guides; owner's handset; A read-backs; D witnesses; all UNTESTED until run)
| Row | What | Needs |
|---|---|---|
| DV-IMG-1..9 (C) | proof image selection → upload → download → render for iPhone HEIC/HEIF, JPEG, PNG; picker cancel, replace, remove; upload timeout → exists-check; mark-sent retry after a lost response shows the sent state; attach on a sent-without-proof transfer; **DV-IMG-9: an iPhone HEIC arrives as JPEG and renders for the buyer (the conversion claim)** | S3 on the sandbox; a seller transfer in `pending` and one in `seller_sent` with a null path (fixtures: the sandbox already has 12 non-pending null-path rows; A names the exact ids before the window) |
| F-SELL-2 re-check | badge clears every header at normal and largest text; no doubled spacing where a header already had an inset | C's F-SELL-2 head in the build; **one bid-free seller listing** (Phone P1) for Edit listing |
| DV-N-1..3 | security-notice banner renders the server title/body for the staged row; Dismiss → `read_at` set (A read-back); relaunch → not shown; unknown type → Dismiss only | S1 + S5 |
| DV-611C-2 rows (296439c) | `inactive→active` during an open challenge → no second register call; a real background→foreground → exactly one re-issue; both limit texts show the visible remedy | push delivery for the full path — **DEFERRED**; the register-call counting half is observable in the API log |
| DV-131-1 | the two-second window: A bumps the epoch within 2 s of a sign-in on C's trigger | sandbox write on trigger (already in the session-2 authorization) |
| Settings truth (cf94311) · F-2S-1 wording (df5127c) · tickets label ABSENT in the preview build (ac70643 exclusion) | copy and visibility rows | none |
| DV-ST2b | cached rows stay under a server error | the bid fixture (owner's line 2) + the ST2 mechanism |
| Carried at true status | two-session K-2 case UNTESTED · row 18 DEFERRED · A11Y-1 UNTESTED · every push-delivery row DEFERRED · Event name "mostly visible" UNRESOLVED · F-DT-1 open · HEIC conversion UNVERIFIED until DV-IMG-9 | — |

## 4. The exact image round-trip scope (sandbox storage; A executes, D witnesses) — from `SANDBOX_AUTHORIZATION_LINES_20260917.md` line 1
Actors: DV seller `2f5844b4…`, DV buyer `919d511e…` (password grant; credentials by NAME only), one anonymous client. Files: three synthetic
files under 10 KiB — a 1×1 PNG, a minimal JPEG, a HEIC made from the PNG with `sips` — named `rt-20260917-{1,2,3}.{png,jpg,heic}`, sha256 recorded.
Affected records: **only** three `storage.objects` rows in `proof-docs` at `<seller uid>/transfer-evidence/rt-…`, created at RT1, deleted at RT7; no
`public.*`/`notify.*`/`net.*` row. Steps: RT1 seller uploads (byte-derived type, `upsert:false`) → 200 ×3 · RT2 same-name re-upload → 409 ·
RT3 seller signs + downloads → 200, sha256 equal, Content-Type equal · RT4 buyer → denied · RT5 anon → denied · RT6 (buyer access to a
REFERENCED object) DEFERRED to after S3 + one attach · RT7 seller deletes → 200, folder count back to pre-count. Read-backs: folder count 0 → 3 → 0;
per-step status, object id, sha256 as values. Stopping: pre-count ≠ 0, any status differs, bytes/type differ, any object survives RT7, a DV-ST2 window
open, CS-1 fails, any credential in an error. Proves policy and allow-list behaviour for true types and unrelated-user denial; **does not** prove
HEIC conversion or buyer display of a referenced proof.

## 5. Approval lines (each separate; none granted by this document)
1. **Tag + build:** "Create `candidate/2026-09-18-build-c3` at <candidate head> and have C submit one sandbox preview build."
2. **Sandbox window:** "Apply 136 → 139 → 140 to the sandbox and deploy notify-report + stripe-webhook, A executing, D witnessing, per §2."
3. **Staged notice:** "Execute the §3b staged-notice write for the DV buyer."
4. **Image round-trip:** line 1 of `SANDBOX_AUTHORIZATION_LINES_20260917.md`.
5. **Bid fixture:** line 2 of the same document (after DV-S2 completes; D7 never).
**Recorded intention (D, not this candidate):** F-SELL-2 makes the top-inset contract uniform (every screen pays its own), which turns `SecurityNoticeBanner`'s interim `paddingTop: useTopInset()` into the single exception; when its DV-N row comes up the banner should become an overlay like `SandboxBadge` and drop the padding.
Off this candidate's critical path by the owner's ruling: cleanup scheduling, native issuance/scanning, the broader onboarding build (138), the My Listings redesign (separate visual approval), 137, the venue window.
