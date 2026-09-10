# PFA-18C — MIGRATION 121 FORWARD FIX (114 L121) — REVIEW PACKAGE (NOT APPLIED · C5 PAUSED · C6 REVIEW-ONLY)

**Date:** 2026-09-10 · **Coordinator:** Claude B · **Owner instruction:** prepare the required 114 L121 forward fix for review on an isolated branch; do not apply to sandbox or production; no keys, secrets, deploys, or monitor arming.
**Result:** implemented, rehearsed locally, committed on an isolated branch, pushed, draft PR opened for CI evidence only. **Nothing applied anywhere.** Production ledger still 135 / tip 120; production function md5 still `b14d938eab69c94768578daf8b6d1c4f` (the 114 body).

## 1. The exact defect (applied migration 114, function `venue.get_manifest_signing_context()`, line 121)

The function counts active global rows (`v_n`), returns the stable `unavailable` codes when `v_n = 0` or `> 1`, then re-reads the row with a **non-STRICT** `select * into v_k`. Inside a `STABLE` PL/pgSQL function the two statements run under separate READ COMMITTED snapshots, so a status flip that commits between them — a revoke (106 sets `status='revoked'`), or any forward-only status change — makes the second read return **no row**. A non-STRICT `select into` does not raise on zero rows: `v_k` is NULL-filled; `v_k.not_before > now()` and `v_k.algorithm <> 'ES256'` evaluate to NULL (not true); the function returns **`{status:'ok', key_id:null, kms_handle_ref:null, public_key:null, …}`** instead of `{status:'unavailable', code:'no_active_global_key'}`. `too_many_rows` is unreachable (`signing_key_active_global_uq`) but is handled for the same fail-closed reason.

**Effect on the dark deployment (C6).** The `door-manifest` edge treats `status='ok'` as "sign with this identity". With NULL identity the E2 signer fails closed (config/scope/verify errors), so no bad manifest is served — but the failure surfaces as a signer error class instead of the stable `unavailable` code the edge maps to a clean 503, and logs carry `key_id=null`. The contract 114's own comment promises ("stable unavailable codes") is violated exactly during a revoke incident. Recorded in the C4 package (§5.2b D1) as "fix before C6".

## 2. Implementation (isolated branch; applied migration 114 untouched)

| Item | Value |
|---|---|
| Branch | `fix/121-manifest-signing-context-strict`, cut from `origin/admin/operating-console @ 562fda9` (the lineage carrying 110–120; the `feature/venue-native-and-product-v2` branch does not carry 115–120) |
| Commit | **`29ad7f87ea11ed212eac32be7209bee515d6b01e`** (pushed) · draft PR **#58** into `admin/operating-console` — review-only, opened for CI evidence; **not for apply** |
| Migration | `supabase/migrations/121_get_manifest_signing_context_strict.sql` — body-only `create or replace` of the same function; the row read becomes `select * into strict v_k …` inside a nested block with `when no_data_found → {unavailable, no_active_global_key}` and `when too_many_rows → {unavailable, ambiguous_active_global_key}`; signature, STABLE, SECURITY DEFINER, `search_path=''`, count pre-checks, window/algorithm checks, ok payload, grants (service_role only) unchanged; comment extended with one sentence. **Census 0.** |
| Rollback | `supabase/rollbacks/121_get_manifest_signing_context_strict_rollback.sql` — restores the 114 body verbatim; verified: after rollback the definition md5 is **`b14d938e…` = production's current md5** (byte-identical), after re-apply `c321ad7e516ac91b57fb884013180061` |
| Test | `supabase/tests/189_get_manifest_signing_context_strict.sql` — 19 assertions: A definition (STRICT present, non-STRICT gone, both handlers), B shape/grants unchanged, C contract (0 rows → unavailable/no_active_global_key; 1 active global → ok with the row's key_id/handle/ES256/public_key; status flip → unavailable with the stable code, never an ok-of-NULLs), D census/identity. Limitation stated in the file: the inter-statement race cannot be interleaved in one pgTAP transaction; STRICT semantics are Postgres-guaranteed, so the suite pins the definition and the contract. |

Diff against 114 (verified): only the STRICT block (and the comment sentence) differ.

## 3. Numbering coordination (Claude A)

Reserved: **migration 121**, **rollback 121**, **test 189**. Basis (CLAUDE-OBSERVED across all remote branches): no branch carries a `121_`/`122_` migration; tests reach 186 on `admin/operating-console`, **187** is taken on `release/convergence-135` (`my_tickets_read`), **188** on `venue/read-adapters-slice-1` (`venue_api_read_views`) → 189 is the first free number everywhere. A direct session message to "Claude A Payments and release integration" could not be delivered (cross-session messaging is unavailable in this session), so this reservation is recorded here and in the PR body; Claude A should treat 121/189 as taken and renumber if a conflicting file is in flight.

## 4. Local rehearsal (REHEARSAL evidence; production untouched)

Fresh replica `snatchit_rehears_121` from the fix branch: **136** migrations replayed (`LC_ALL=C`), GATE-2 census = CI baseline (tables 27 / functions 71 / policies 37 / triggers 27). Post-121 definition: `strict=true`, `nonstrict=false`, md5 `c321ad7e…`. Census kernel fns **153** / venue fns **87** / kernel tables **32** / signing_key triggers **3** — identical to the pre-121 replica and to production. pgTAP: **176** (insert guard) + **180** (114 suite, unchanged) + **189** (new) = **112/112 ALL-PASS**. Rollback round-trip: rollback → md5 `b14d938e…` (production-identical) → re-apply → `c321ad7e…` → suite 189 PASS again. Coordinator scripting note: the first diff of the rollback text used mis-aligned line ranges; the functional md5 round-trip is the authoritative check.

## 5. Rollback considerations
- Body-only; no data, no grants, no dependency change → the rollback is a plain re-create (seconds), safe at any time; production policy remains forward-only, so applying the rollback in production needs its own authorization.
- If 121 is rolled back, the 114 race re-opens — acceptable only while the native edges stay undeployed (C6 not done).
- The rollback file must be applied **after** any later migration that also re-creates this function is itself rolled back (none exists today).

## 6. Integration dependencies and apply path (not authorized by this package)
1. Owner review of this package and PR #58 (draft). CI on the PR: the pgTAP job should pass; the **Migrations guard** job stays red until the `AUTODEPLOY-VERIFIED-OFF: <date>` acknowledgement is added on the day of apply (by design).
2. Apply only under its own phrase **`AUTHORIZE PFA-18C MIGRATION 121`**, from the fix branch (or after merging it into `admin/operating-console`), with the C4 discipline: dry run lists exactly `121_…`; `git_branch ""` (auto-deploy off) re-confirmed; ledger **135 → 136**, numeric tip **121**; read-backs: definition md5 `c321ad7e…` (expected to match if the file is byte-identical), `strict=true`, grants service_role-only, census unchanged, `get_manifest_signing_context()` still `ok`/`…b0` (post-C3), suites 180/189 green in CI.
3. **Must precede C6** (dark deploy). Does not interact with C5 (monitor) or the AWS side. No edge code change is needed (the edge already maps `unavailable` codes).
4. Sibling observation (not changed here): `kernel.get_ticket_signing_context` (102/103) uses non-STRICT `select … into` lists as well; recommend the same review before the `credential-sign` edge is deployed (C6) — tracked for Claude A / a follow-up migration (122 would be the next number).

## 7. C5 resumption pre-read findings (for tomorrow; no production change)
- Expiry is enforced by the **approver**, not the table: `kernel.approve_refund_request` raises `precondition_failed: request … has expired` when `expires_at < now()`; the request row stays `pending` (no automatic state change). `approval_request_expiry_check` only requires `expires_at > created_at`, so expiry cannot be simulated locally by back-dating; the approver branch was verified by definition review.
- **Re-proposal after expiry must use a NEW command key.** Re-running C5-1 with the same `pfa18c-c5-pin-1` fails with `duplicate key value violates unique constraint "approval_request_command_key_key" (requested_by, command_idempotency_key)` — a raw constraint error inside the setter, no partial write (rehearsed locally). With a new key (e.g. `pfa18c-c5-pin-2`) the setter returns `parked` with a fresh `request_id`; an expired pending request does not block it.
- Tomorrow's order: read request `05e0ff5d…` state + `expires_at` (2026-09-13T19:59:17Z) → if still pending and unexpired, proceed with C5-2 (founder B) exactly as in the pause handoff → else re-issue C5-1 with a new command key, read back, then C5-2 with the new request id.
