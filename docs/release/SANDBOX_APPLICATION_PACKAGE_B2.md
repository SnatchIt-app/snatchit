# Sandbox application package — production-gate candidate with b2 (DRAFT for the owner's approval, A, 2026-09-16)

**Scope requested:** apply the reviewed production-gate content to the shared sandbox `ofaidukbieeekqaboscm` only, so the
combined build can be verified on a handset. **Nothing here touches production.** The exact pinned commit is filled in when
D's Gate 3 and CI pass on the combined commit (`release/production-gate-20260918 @ 0e8de77` today); the content below does not
change with the pin. Execution is serialized through A with `scripts/release/apply_sandbox_migration.sh` (asserts the sandbox
ref twice, refuses production, records each ledger row from the pinned file's exact bytes, md5-verified); D witnesses.

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
phase (separate window, D's runbook); no build (the one authorized build is cut from the pin after Gate 3 + CI, and is a separate
action).

**Owner approval needed:** this package as written, the pinned commit once named, and the sandbox window. A stops on any
unexpected state or uncertain mutation outcome, as before.
