# PFA-18C — C4 PRODUCTION EXECUTION RECORD: MIGRATIONS 110–114 — **COMPLETED AND VERIFIED**

**Authorization:** 2026-09-09 — owner phrase **"AUTHORIZE PFA-18C MIGRATIONS 110-114"**, scoped to commit `562fda9aba261d7929ee772a4fd1ce50485c4294` and the five SHA-256 digests in §2; execution per `docs/release/PHASE2_PFA18C_C4_MIGRATIONS_110_114_EXECUTION_PACKAGE.md`. **Applied 2026-09-09T04:22:39–04:22:52Z.** Not authorized and not done: C2/CreateKey, C3 insert, edge deployment, issuance/scanning, payments/fees/Connect/PaymentIntent/charges/transfers/refunds/payouts, secret rotation, PFA-18A, any other migration. **C2 remains NOT BEGUN. Returned to owner review — no CreateKey.**

Evidence classes: **CLAUDE-OBSERVED** (coordinator commands/reads this session), **OWNER-RETURNED**.

---

## 1. Result

| Item | Result |
|---|---|
| Apply | **SUCCESS** — five migrations applied in order 110 → 114; `Finished supabase db push.`; no error |
| Ledger | **130 → 135**; rows `110…114` present (`created_by` NULL — CLI path); **numeric tip remains 120** (as predicted: 110–114 < 120) |
| Signing-key insert guard (110) | present; trigger `tg_signing_key_insert_guard` **enabled** (`tgenabled = 'O'`) |
| Recovery substrate (111) | table present, RLS **on**, **0 policies**, **0 client grants**, **0 rows**; `approve_/execute_signing_key_recovery` present, EXECUTE granted to `authenticated` only (in-function platform_admin + aal2) |
| Census | kernel fns **149 → 153**, venue fns **83 → 87**, kernel tables **31 → 32** (exactly the predicted +4/+4/+1) |
| Door RPCs (112–114) | `venue.get_door_manifest` delegates to `_get_door_manifest_core` (zero-grant); `get_door_manifest_door`, `get_signing_keys_door`, `get_manifest_signing_context` EXECUTE = **service_role only**; staff RPC still `authenticated` |
| `venue.get_manifest_signing_context()` | `{status: "unavailable", code: "no_active_global_key"}` |
| Guard refusal probe (V8) | INSERT of a non-`…b0` global ES256 row inside a transaction → **refused** `signing_key_insert_refused: bootstrap_key_id_required` (guard line 85); transaction aborted; `kernel.signing_key` count **0** after the probe |
| Darkness | `kernel.signing_key` **0**; tickets 0; issuance `false`; scanning `false`; monitor `false`; fingerprint `null`; max_not_after `null`; native edges **not deployed** (11 legacy edges only); AWS `kms list-keys` **`[]`** |
| **M2 / M1 / C1** | unchanged: satisfied / complete / closed |
| **C2** | **NOT BEGUN** — requires the separate exact owner authorization **"AUTHORIZE PFA-18C CREATEKEY"** |

---

## 2. Scope actually applied (CLAUDE-OBSERVED, P2 at 04:16:27Z — identical to the authorization)

```
3134f6f63e4ff1b100120508152eb696d9acf101a5a109e37a8938ba3d1f7390  supabase/migrations/110_signing_key_insert_guard.sql
d13cf6cba2b08742f8d397d8d0a2b508a10df9544119e174d73b0990d0507ac1  supabase/migrations/111_signing_key_recovery_two_person.sql
97d33d0862a6c8daa3728fdf9935cf8239ba953ccaafd2d12a63d0c15f73f9b7  supabase/migrations/112_get_door_manifest_headers.sql
32d42324b2b21667a17a3b31a6ff98e9df2d2a8dfd9ff98c5bad7ca1466fd88d  supabase/migrations/113_get_door_manifest_door_machine_authority.sql
9974eb91fd51acba9786c60366460e53a304807129600f46a197740b21455cee  supabase/migrations/114_signing_key_door_delivery_and_manifest_signing_context.sql
```
Checkout `/Users/josetascon/snatchit-admin-console` at `562fda9aba261d7929ee772a4fd1ce50485c4294`, clean before and after (`git status --porcelain` empty); `origin/admin/operating-console` = same SHA at 04:21:56Z. CLI `supabase 2.115.0` (= pin).

## 3. Preflight (all PASS)

| # | Check | Result | UTC |
|---|---|---|---|
| P1 | HEAD / clean | `562fda9…` / 0 lines | 04:16:27, re-checked 04:21:56 |
| P2 | five digests | equal to the authorization (§2) | 04:16:27 |
| P3 | CLI | 2.115.0 | 04:16:27 |
| P4 | production | ledger 130 · tip 120 · 110–114 absent · signing_key 0 · guard absent · recovery table absent · census 149/83/31 · tickets 0 · flags dark | 04:16:32; re-read 04:22:20 (130 / 120 / 0 / 0) |
| P5 | auto-deploy OFF | `git_branch: ""` (read 04:16 and 04:22); **owner visual confirmation "auto-deploy OFF confirmed 2026-09-09" (OWNER-RETURNED)**; PR #55 body updated by the coordinator to `AUTODEPLOY-VERIFIED-OFF: 2026-09-09 (owner visual confirmation 2026-09-09; C4 apply of 110–114)` | 04:21:56 |
| P6 | CI on `562fda9`; PR #55 | CI `34188504835` success, Migrations guard `34188507116` success; PR #55 OPEN at `562fda9…` | 04:16 |
| P7 | AWS `kms list-keys` | `[]` | 04:16:27 |
| P8 | dry run | `Would push these migrations:` **exactly** `110_…`, `111_…`, `112_…`, `113_…`, `114_…`; `seeds: []`, `roles: []` | 04:17:27 |

Link-state note (local, gitignored, non-secret): the first dry-run attempt returned `LegacyProjectNotLinkedError` because the admin worktree carried only the newer `linked-project.json`; the coordinator mirrored the legacy `project-ref` (`hqycwntpfoztoinemqns`) and the non-secret `pooler-url` host file from the consol worktree into `supabase/.temp/` of the admin worktree. No credential written; the DB password resolved from the OS keychain.

## 4. Apply (§6.2) — CLAUDE-OBSERVED, executed by the coordinator under the owner's explicit scoped authorization (precedent: 093–109 on 2026-09-04)

```
cd /Users/josetascon/snatchit-admin-console && supabase db push --linked --include-all --yes
```
Output (verbatim, 04:22:39–04:22:52Z): `Initialising login role...` · `Connecting to remote database...` · `Do you want to push these migrations to the remote database? • 110_signing_key_insert_guard.sql • 111_signing_key_recovery_two_person.sql • 112_get_door_manifest_headers.sql • 113_get_door_manifest_door_machine_authority.sql • 114_signing_key_door_delivery_and_manifest_signing_context.sql [Y/n] y` · `Applying migration 110_signing_key_insert_guard.sql...` · `Applying migration 111_signing_key_recovery_two_person.sql...` · `Applying migration 112_get_door_manifest_headers.sql...` · `Applying migration 113_get_door_manifest_door_machine_authority.sql...` · `Applying migration 114_signing_key_door_delivery_and_manifest_signing_context.sql...` · `{"upToDate":false,"dryRun":false,"migrations":[110…,111…,112…,113…,114…],"seeds":[],"roles":[],"message":"Finished supabase db push."}`. No error. (The CLI's "new version 2.117.0 available" notice is informational; the pin stays 2.115.0.)

## 5. Post-apply verification (§6.3) — CLAUDE-OBSERVED, read-only

| # | Check | Observed | UTC |
|---|---|---|---|
| V1 | ledger; rows; tip | **135**; `110 signing_key_insert_guard`, `111 signing_key_recovery_two_person`, `112 get_door_manifest_headers`, `113 get_door_manifest_door_machine_authority`, `114 signing_key_door_delivery_and_manifest_signing_context` (all `created_by` NULL); numeric tip **120** | 04:23:14 |
| V2 | guard | `kernel.guard_signing_key_insert()` present; `tg_signing_key_insert_guard` on `kernel.signing_key` `tgenabled = 'O'` | 04:23:14 |
| V3 | recovery table | exists; `relrowsecurity = true`; policies 0; grants to anon/authenticated/service_role/PUBLIC 0; rows 0 | 04:23:14 |
| V4 | recovery functions | `approve_signing_key_recovery(uuid,text,text,text)` and `execute_signing_key_recovery(uuid,text,text,text,text)` present; client-class EXECUTE grantees = `authenticated` only | 04:23:14 |
| V5 | census | kernel fns 153 · venue fns 87 · kernel tables 32 | 04:23:14 |
| V6 | door RPC grants | staff `get_door_manifest` delegates to core (true), grantees `authenticated`; `_get_door_manifest_core` (none); `get_door_manifest_door` `service_role`; `get_signing_keys_door` `service_role`; `get_manifest_signing_context` `service_role` | 04:23:22 |
| V7 | `venue.get_manifest_signing_context()` | `{"status":"unavailable","code":"no_active_global_key"}` | 04:23:22 |
| V8 | guard probe (transaction, throwaway P-256 SPKI PEM generated locally, key_id `11111111-1111-4111-8111-111111111111`, global/active/ES256/full ARN/`now()`/null) | **refused** `P0001: signing_key_insert_refused: bootstrap_key_id_required — the initial global trust root must carry the sanctioned bootstrap key_id (ruling B, ceremony §6.1)…` (`kernel.guard_signing_key_insert()` line 85); `kernel.signing_key` count after the probe **0**; recovery rows 0 | 04:24:29 |
| V9 | darkness | signing_key 0; tickets 0; issuance `false`; scanning `false`; monitor `false`; fingerprint `null`; max_not_after `null`; edges: only the 11 legacy functions (`list_edge_functions`); AWS `kms list-keys` `[]` | 04:23:22 / 04:23:49 |

Every expected final state in the authorization is met. No discrepancy; no rollback; §6.5 not triggered.

## 6. Mutation ledger (this session)
Production DB: **migrations 110–114 applied** (schema/functions/grants only; no data rows written; the V8 probe was refused and rolled back). AWS: **none** (read-only). KMS: **not created.** Secrets/keys/IAM/S3/CloudTrail/Organizations: **none.** Edges: **not deployed.** Flags: **unchanged (dark).** Repository: this record, execution record session 16, packet C4 row; PR #55 body line updated (AUTODEPLOY-VERIFIED-OFF 2026-09-09). Local gitignored link marker mirrored in the admin worktree.

## 7. Next (owner review; nothing implied)
- **C2 — CreateKey + §5.3 binding proof + P3′** requires **"AUTHORIZE PFA-18C CREATEKEY"** (ceremony-role session; Device 2 verifies).
- Forward fixes noted in the package (114 L121 non-STRICT select — before C6; 086↔112/113 expired-episode drift — before scanning activation; ceremony-doc rotation note) — separate, non-urgent.
- Governance carried forward: C7/M5 pending clarification; Model A before T3.
