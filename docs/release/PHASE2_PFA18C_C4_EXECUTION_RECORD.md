# PFA-18C — C4 PRODUCTION EXECUTION RECORD: MIGRATIONS 110–114

**Authorization received:** 2026-09-09 — owner phrase **"AUTHORIZE PFA-18C MIGRATIONS 110-114"**, scoped to commit `562fda9aba261d7929ee772a4fd1ce50485c4294` and the five SHA-256 digests below; execution per `docs/release/PHASE2_PFA18C_C4_MIGRATIONS_110_114_EXECUTION_PACKAGE.md`. Not authorized: C2/CreateKey, C3 insert, edge deployment, issuance/scanning, payments/fees/Connect/PaymentIntent/charges/transfers/refunds/payouts, secret rotation, PFA-18A, any other migration. **C2 remains NOT BEGUN.** After C4, return to owner review — no CreateKey.

Evidence classes: **CLAUDE-OBSERVED** (coordinator reads/commands this session), **OWNER-RETURNED**, **NOT OBSERVED**.

---

## 1. Status

| Phase | Status |
|---|---|
| §6.1 preflight P1–P4, P6–P8 | **PASS** (2026-09-09T04:16–04:17Z) |
| §6.1 preflight **P5 — owner visual confirmation that production auto-deploy is OFF, dated today** | **PENDING OWNER** — the mechanical half passed (`git_branch: ""`, read 04:16Z); the visual dashboard confirmation is owner-only and was last recorded 2026-09-07 (RC3). The package requires today's confirmation and today's `AUTODEPLOY-VERIFIED-OFF` line on PR #55 (currently `2026-09-07`). **The apply is STOPPED at this gate until the owner confirms; nothing has been applied.** |
| §6.2 apply | **NOT RUN** |
| §6.3 post-apply verification | pending |

Rationale for stopping: the authorization directs "Confirm production auto-deploy is OFF according to the established procedure" and "Update/verify today's AUTODEPLOY-VERIFIED-OFF evidence as required by the execution package"; the established procedure (`docs/operations/DEPLOYMENT_PATHS.md`) requires the owner's visual confirmation in the Supabase dashboard, which the coordinator cannot perform or infer. On the owner's confirmation, the coordinator updates PR #55's line to `AUTODEPLOY-VERIFIED-OFF: 2026-09-09` and proceeds to §6.2.

---

## 2. Preflight evidence (CLAUDE-OBSERVED)

| # | Check | Result | Time (UTC) |
|---|---|---|---|
| P1 | HEAD of `/Users/josetascon/snatchit-admin-console`; `git status --porcelain` | `562fda9aba261d7929ee772a4fd1ce50485c4294`; 0 lines (clean) | 04:16:27 |
| P2 | `shasum -a 256 supabase/migrations/11[0-4]_*.sql` | `3134f6f63e4ff1b100120508152eb696d9acf101a5a109e37a8938ba3d1f7390  110_signing_key_insert_guard.sql` · `d13cf6cba2b08742f8d397d8d0a2b508a10df9544119e174d73b0990d0507ac1  111_signing_key_recovery_two_person.sql` · `97d33d0862a6c8daa3728fdf9935cf8239ba953ccaafd2d12a63d0c15f73f9b7  112_get_door_manifest_headers.sql` · `32d42324b2b21667a17a3b31a6ff98e9df2d2a8dfd9ff98c5bad7ca1466fd88d  113_get_door_manifest_door_machine_authority.sql` · `9974eb91fd51acba9786c60366460e53a304807129600f46a197740b21455cee  114_signing_key_door_delivery_and_manifest_signing_context.sql` — **all five equal the authorization** | 04:16:27 |
| P3 | `supabase --version` | `2.115.0` (= CI pin; 2.117.0 upstream not adopted) | 04:16:27 |
| P4 | production read (MCP, read-only) | ledger **130** · numeric tip **120** · 110–114 **absent** · `kernel.signing_key` **0** · guard absent · recovery table absent · kernel fns 149 · venue fns 83 · kernel tables 31 · tickets 0 · issuance `false` · scanning `false` · monitor `false` · fingerprint `null` | 04:16:32 |
| P5 (mechanical half) | Supabase branch record | `git_branch: ""` (`updated_at 2026-08-27T15:49:25Z`) | 04:16 |
| P5 (owner half) | visual dashboard confirmation, dated today; PR #55 line | **PENDING** (PR #55 body currently `AUTODEPLOY-VERIFIED-OFF: 2026-09-07`) | — |
| P6 | CI on `562fda9`; PR #55 head; origin tip | CI `34188504835` success, Migrations guard `34188507116` success; PR #55 OPEN at `562fda9…`; `origin/admin/operating-console` = `562fda9…` | 04:16 |
| P7 | AWS `kms list-keys` (read-only, `jose-admin`) | `[]` | 04:16:27 |
| P8 | **Dry run** `supabase db push --linked --include-all --dry-run` from the worktree | `DRY RUN: migrations will *not* be pushed` · **Would push these migrations: 110_signing_key_insert_guard.sql · 111_signing_key_recovery_two_person.sql · 112_get_door_manifest_headers.sql · 113_get_door_manifest_door_machine_authority.sql · 114_signing_key_door_delivery_and_manifest_signing_context.sql** · `seeds: []`, `roles: []` · "Finished supabase db push." — **exactly the five, nothing else** | 04:17:27 |

**Link-state note (local, non-secret, gitignored):** the first dry-run attempt returned `LegacyProjectNotLinkedError` because the admin worktree carried only the newer `supabase/.temp/linked-project.json` (written by a later CLI on 2026-09-08) and CLI 2.115.0 reads the legacy `supabase/.temp/project-ref`. The coordinator mirrored the legacy marker (`project-ref` = `hqycwntpfoztoinemqns`, identical to the consol worktree's, plus the non-secret `pooler-url` host file) into the admin worktree's gitignored `.temp/`; the repository tree is unchanged (`git status --porcelain` empty). No credential was written; the DB password resolves from the OS keychain as on 2026-09-04.

---

## 3. Apply — NOT RUN (awaiting P5 owner confirmation)

Planned command (unchanged from the package; `--yes` answers the CLI's push confirmation non-interactively, as the authorization directs execution once the gates pass):
```
cd /Users/josetascon/snatchit-admin-console && supabase db push --linked --include-all --yes
```

## 4. Post-apply verification — pending

## 5. Mutation ledger (this session so far)
AWS: **none** (read-only). Production DB: **none** (read-only reads; dry run is read-only). Migrations: **NOT applied.** KMS: **not created.** Repository: this record only; local gitignored link marker mirrored in the admin worktree.
