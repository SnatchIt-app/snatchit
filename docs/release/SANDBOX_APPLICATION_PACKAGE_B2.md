# Sandbox application package — production-gate candidate with b2 (DRAFT for the owner's approval, A, 2026-09-16)

**Scope requested:** apply the reviewed production-gate content to the shared sandbox `ofaidukbieeekqaboscm` only, so the
combined build can be verified on a handset. **Nothing here touches production.** Execution is serialized through A with
`scripts/release/apply_sandbox_migration.sh` (asserts the sandbox ref twice, refuses production, records each ledger row from
the pinned file's exact bytes, md5-verified); D witnesses.

**Pinned commit: `candidate/2026-09-18-pin-b2` = `release/production-gate-20260918 @ 9bef640`** (annotated tag, pushed
2026-09-16; the earlier `candidate/2026-09-18-pin` = `aabe029` is kept, untouched, and stays identifiable as the source of the
SBX-2 window and Build 17). Every migration, rollback, test and edge in §3–§4 is taken from this tree.

**Evidence at the pin.** GitHub CI run 35053607616 at `9bef640`: 5/5 jobs green; pgTAP files=85, tests_ran=5186, result PASS,
masking gate 0/0/0. D Gate 3 PASS at `9bef640` (D's log `26d69d9`): the merge chain checked byte-for-byte against the heads D
passed (`cd996df` = 135 + rollback + 202 + send-push identical, nothing else under `supabase/migrations`; `0e8de77` = C's four
client files identical to `e8114df`, SQL unchanged; `9bef640` = one new 74-line test file only); full-chain rehearsal at
`0e8de77` PASS 27 / FAIL 0 / WARN 3 (the two pre-existing rollback WARNs on 20260906120000 and 128), census 32|105|37|38, both
orders converge; reverse-order rollback 20260916000000 → 135 → 133 → 132 → 131 leaves 0 lines differing from the candidate,
census back to 31|96|37|35; C1–C6 matrix 0 errors with all four negative controls flipping; push/auth suites 97/97; every string
the client keys on verified against the migrations' `raise exception` sites with comments stripped (twelve raised; `nonce
mismatch` is a dead v2 branch); C's classifier guard fails by name on each of three mutations of 135.

## 1. Pre-flight (read-only, immediately before)
Ledger 136 and versions >109 = 123,124,125,127,128,129,130; native flags all false; `kernel.tickets` 0, `signing_key` 0;
counts as manifest §10; L-1 = 0; the two production-host drift counts (`pg_proc` 4, `cron.job` 5) — 133's proof aborts on any
unrecorded site; push_tokens: exactly one row (`140fcb44…`, the buyer's after Path B). Stop on any difference.

## 2. Vault ceremony (sandbox, before 133) — A runs, D witnesses
Insert Vault secret `project_url` = `https://ofaidukbieeekqaboscm.supabase.co` (no trailing slash). 133 refuses to apply on an
environment carrying `service_role_key` without it. Verify `select count(*) from vault.decrypted_secrets where name='project_url'`
= 1. **Consequence on this sandbox (recorded):** 133 creates the `enforce-transfer-expiry` cron that the sandbox lacks today, so
transfer expiry and Phase 0 refunds start running against sandbox test data every 2 min; the out-of-band notify bodies are
replaced by the Vault form.

## 3. Migrations, in order, each `preflight → apply → verify` (ORDER_GUARD_SKIP=126 stays declared)
`131` (session-bound bindings) → `132` (pre-mint group record) → `133` (config-driven functions URL) → `134` =
`20260916000000_processing_sweep_arm` → `135` (proof of possession). Expected ledger 136 → 141. After each: the object
spot-check from the registry row; census after 135: public 32 | 105 | 37 | 38 (the sandbox will differ by its known deltas —
no 119 guard, +`sandbox_gucs`, +`sandbox_pre_request` — D records the explained numbers).

## 4. Edges, from the pinned tree, `--project-ref ofaidukbieeekqaboscm --no-verify-jwt` (parity with today's sandbox)
After 132: `create-payment-intent` (132's edge; 503 fail-closed without 132). After 20260916000000: `enforce-transfer-expiry`
(134's Phase 0 branch). After 135: `send-push` (challenge kind). `stripe-webhook` (already v4 from the candidate pin; redeploy
from the new pin for byte parity). Parity check after each: `supabase functions download` into a scratch dir, `cmp` against the
pin (A and D independently).

## 5. Verification and read-backs (documented; the DV rows of the combined build)
DV-V1..V4 (silent challenge, 60 s fallback with a visible code, wrong-then-right code, staged stale echo), DV-P1..P5 (K-2 and
131 rows), F-SELL-1 create/edit incl. large text, DV-ST1..ST4 (state views), Blocks 2/2b (checkout previews, 132 on the sandbox),
DV-134 (a processing row resolved by the sweep, staged). A stages fixtures and does the read-backs; D witnesses and reviews.

## 6. Cleanup and closing read-back
Fixture rows deleted by exact id; DV users' push rows left as the session ends them; counts back to baseline (+ledger rows, +the
new cron, +Vault `project_url`); closing census recorded in manifest §10.

## 7. What this package does NOT include
No production change of any kind; no native activation; no signing; no `ops` migrations (126 stays deferred here); no venue
phase (separate window, D's runbook); no build. The one authorized build (owner ruling 2026-09-16: "one additional build after
the combined commit passes required reviews and CI") has its conditions met at the pin; A recommends C cuts it from
`candidate/2026-09-18-pin-b2` only after §3–§4 complete on the sandbox, so the single build is not spent before the server side
it depends on is confirmed applied. Cutting it earlier is the owner's call.

## 8. Carried for the owner's decision or acknowledgement (from D's Gate 3)
1. **Notice channel (decision):** `security_device_rebound` is in-app only. A previous owner of a device who never opens the
   notification centre is never told that another account claimed their device. Accept as is, or authorize an email row (an N1
   exception). Either way the package applies unchanged; an email row would be a later migration.
2. **Evidence limit (acknowledgement):** every result above is local. `net.http_post` and `vault.decrypted_secrets` are stand-ins
   in the harness, so no real pg_net, Vault, APNs or FCM behaviour is proven, and there is no device evidence yet. The device
   matrix on the one build is the whole remaining risk of b2.
3. **D-135-5 (LOW, B's file, not blocking the pin):** `docs/operations/SUPPORT_RUNBOOK_PUSH_TOKEN_UNBIND.md` at the pin still
   says `unbind_push_token` DELETEs the row and lists RB-1 as open; on this stack it tombstones (`support_unbound`), which D
   verified in a replayed database. B corrects it as a docs-only commit, D reviews, A integrates on top of the pin. It changes no
   applied bytes, so the pin stands; it should land before this package is executed because the package cites that runbook.

**Owner approval needed:** this package as written, the pinned commit `candidate/2026-09-18-pin-b2` (`9bef640`), and the sandbox
window. A stops on any unexpected state or uncertain mutation outcome, as before.
