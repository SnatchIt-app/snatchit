# Sandbox approval request for Build 19: four separate actions, one document (A, 2026-09-17). NOTHING HERE IS AUTHORIZED OR EXECUTED

**Context.** Build 19 (`candidate/2026-09-18-build-c3` → `f412d10`) is installed on the owner's iPhone. The owner's installation report authorizes none of the actions below. Each action has its own authorization line (§3), and each detailed scope lives in the documents cited, which stay authoritative. Sandbox `ofaidukbieeekqaboscm` only; nothing touches production, a build, a flag, a secret or an outbound notification. The sandbox push key stays DEFERRED.

## 1. Recommended execution order

| Step | Action | Needs first | Class | Who | Detailed scope |
|---|---|---|---|---|---|
| 0 | **Build 19 rows that need no sandbox change** (continuing now under C): sandbox badge and account, F-NAV-1 (swipe and in-screen Back arrow; report form; Preferences), F-SELL-2 at the largest text, Event name, F-DT-1, picker-only DV-IMG-1/-2/-3a/-6/-7 (never submitted), copy rows, the DV-611C-2 counting half | nothing | no write (except the owner's own preference toggle, restored) | C guides, the owner's handset | package §6 |
| 1 | **Storage round trip (Line 1)** | nothing (needs neither 140 nor the build) | **TEMPORARY**: three synthetic objects created and deleted in the same run; no table row | A executes, D witnesses | `SANDBOX_AUTHORIZATION_LINES_20260917.md` Line 1 |
| 2 | **W-C3**: apply 136 → 139 → 140, deploy stripe-webhook and notify-report from `f412d10` | Step 1 complete, or deliberately skipped | schema and edge change (reversible by the §4 rollback, which restores code, not data) | A executes, D witnesses (D's written census prediction before S1) | package §3 (pins), §4 (pre-flight, census 32|106|37|37 → 32|109|37|37, stopping conditions, rollback) |
| 3 | **Staged security notice** | Step 2's S1 (136) verified | **TEMPORARY**: one `notify.notification` row for the DV buyer, zero delivery rows, deleted after the test | A executes, D reads; C guides the handset | `NOTIFICATION_BATCH_1_PLAN.md` §3b (pre-counts re-read at execution) |
| 4 | **Permanent transfer-test writes (Line 3)** | Step 2's S3 (140) verified | **PERMANENT**: four named transfers marked sent or given proof; referenced proof objects retained; buyer inbox rows | the owner's handset (synthetic images, location off for the camera photo), A's probes and reads, D witnesses, C guides | `SANDBOX_AUTHORIZATION_LINES_20260917.md` Line 3; package §5, §5a, §6, §7; `IMAGE_ROUND_TRIP_EVIDENCE_CHECKLIST_20260917.md` |

**Why this order.**
- Step 1 proves the storage policies, the refusal of a same-name re-upload and byte integrity on synthetic files **before** anything permanent is written. A failure stops everything, with nothing to undo.
- Step 2 must precede Steps 3 and 4: the notice banner calls 136's functions, and Mark as sent and Add proof on Build 19 call 140's verbs. Against today's sandbox (void `mark_transfer_sent`, no `attach_transfer_evidence`), those Build 19 screens would report an unconfirmed or failed outcome and prove nothing.
- Step 3 is temporary and quick, so it runs before the long permanent sequence.
- Step 4 is last because it cannot be undone.

**Rules for every step.**
- No step overlaps another step or a DV-ST2b restriction window.
- B confirms its sandbox access is held.
- D's reads bracket each step.
- Any stopping condition in the detailed scope halts that step. The next step does not start until the owner is told.

## 2. Handset tests each step enables (on Build 19; C guides; every row UNTESTED until run)

| Step | Handset rows it enables | Rows it does NOT enable |
|---|---|---|
| 0 | F-NAV-1 re-check (swipe, Back arrow, report form, Preferences) · F-SELL-2 re-check · Event name · F-DT-1 · DV-IMG-1/-2/-3a/-6/-7 (picker only) · settings, copy and Tickets-label rows · DV-611C-2 counting half | anything that submits a transfer or reads a notice |
| 1 | **none on the handset** (API-only). Gives storage-policy evidence for true file types, and seller/buyer/anon access to **unreferenced** objects | HEIC conversion, buyer display of referenced proof, anything on a device |
| 2 | nothing by itself, but it is the prerequisite for Steps 3 and 4. 139 and the stripe-webhook preference read have **no handset row** while push stays deferred | push delivery (deferred) |
| 3 | **DV-N-1..3**: the security-notice banner shows the server title and body for the staged row; Dismiss sets `read_at` (A reads it back); after a relaunch it is not shown | any real device-rebound event; push delivery |
| 4 | **DV-IMG-4** (offline, then retry, Mark as sent) · **DV-IMG-5** (double tap) · **DV-IMG-9 + 3b** (HEIC camera photo arrives as JPEG and renders on the iPhone; the stale-image check) · **DV-IMG-10** (Add proof on a sent-without-proof transfer), plus A's N1–N4 probes, RT6 (buyer download of referenced proof), U1 (U2 denied), RT5-P (anon denied) | Android (DV-IMG-8), web receive-page render (UNTESTED: its host is fixed at build time), push delivery, payouts |

## 3. The four authorization lines (each separate; none is granted by this document)

1. **Storage round trip (temporary):** "Run RT1–RT5 and RT7 of the proof-docs round trip on the sandbox as scoped in Line 1, A executing as the DV seller, the DV buyer and an anonymous client, D witnessing; synthetic files only; no table writes; abort on the listed stopping conditions."
2. **W-C3:** "Apply 136 → 139 → 140 to the sandbox and deploy stripe-webhook and notify-report from `f412d10`, A executing, D witnessing, per package §4, with its pre-flight, census reconciliation, stopping conditions and rollback."
3. **Staged notice (temporary):** "After W-C3's 136 step is verified, execute the §3b staged-notice write for the DV buyer, guide DV-N-1..3 on Build 19, and delete the row afterwards with A and D read-backs."
4. **Permanent transfer-test writes:** "After W-C3's 140 step is verified, run Line 3: on Build 19 the owner's handset marks sandbox transfers `92ee5156…`, `bce07eef…` and `3118bd30…` sent with proof and adds proof to `8f59d37e…` using synthetic ticket images, as DV-IMG-4, -5, -9 (with 3b) and -10. A runs PC1–PC8, probes N1–N4, downloads exactly those uploads as the seller and the buyer, and has U2 and an anonymous client attempt one read each. D witnesses. These writes are permanent. N5 and any delete or overwrite of attached proof are not run."

**Standing constraints that hold whatever is authorized.**
- The four transfers' disposition rule (package §5a; manifest §13): no key, no executor flag and no payment state change; they are re-read before any future sandbox key or executor activation.
- The buyer never taps Confirm received or Report a problem on a Line 3 transfer.
- Line 2 (bid fixture) is withdrawn.
- DV-ST2b, the server-log settings reads and every production action remain separate and unauthorized.
