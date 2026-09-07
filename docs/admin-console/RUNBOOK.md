# Operating console — deployment, migration, containment and recovery runbook

Scope: migrations `115_ops_console_foundation`, `116_ops_console_read_api`,
`117_ops_console_automation`, `118_ops_console_corrections`,
`119_listing_block_insert_guard`; the `admin/` Next.js app (Vercel project
`snatchit-admin`); edge function `ops-refund-execute` (optional, disabled by
default). Nothing here is applied or deployed by merging (AUTODEPLOY-1:
production auto-deploy is OFF — re-verify visually before every apply; record
`AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` in the PR).

**Blast radius, stated precisely.** The five migrations change no *existing*
`public.*` definition; 119 *adds* one `public` trigger function + trigger
(Gate-2 census 70→71 functions, 26→27 triggers). At runtime the console
intentionally writes public business data through the published domain
functions: `resolve_transfer_dispute`, `admin_release_held_payout`,
`admin_relist_listing`, `public.reports.status`,
`seller_risk_scores.is_listing_blocked`. "No public schema definitions changed"
is a structural statement; the runtime effect is operator actions on live
marketplace rows, each audited.

## 0. Preconditions (owner, read-only checks)

| Check | How | Last verified value (2026-09-07, read-only API) |
|---|---|---|
| Ledger numeric tip | `select max(version) from supabase_migrations.schema_migrations where version ~ '^[0-9]{3}$';` | **109**, 124 rows |
| 110–114 unapplied | same query lists no 110–114 | confirmed |
| Auto-deploy OFF | Dashboard → Integrations / Branching; `git_branch` on the production branch record | `git_branch: ""` (API); **visual confirmation still required** |
| Founder membership | `select count(*) from public.admin_users;` | **1** — second founder must be added first (`FOUNDER_BOOTSTRAP.md`) |
| Verified MFA factors | `select count(*) from auth.mfa_factors where status='verified';` | **0** — founders enrol on first console sign-in |
| PostgREST exposed schemas | Settings → API | `public, kernel`; **`ops` must be added** |
| Storage policies on `storage.objects` | `select polname from pg_policy where polrelid='storage.objects'::regclass;` | 11 (5 proof-docs); 118 adds `proof-docs operator read` |
| Rehearsal | `scripts/rehearsal_reset.sh` full chain **and** the exact production shape (`REHEARSAL_UPTO=109_… ` then the five timestamp files, then 115→119) — both green with pgTAP 181–185 | see FINAL_REPORT §2 |

## 1. Apply order (Path A — SQL editor, one file at a time)

Path A keeps 110–114 unapplied. `supabase db push` would apply every pending
file in filename order — 110–114 (door-plane, DARK, rehearsal-only) *and*
115–119 — so it is **not** the path for this package unless the door-plane
train is explicitly going live in the same window.

1. `115_ops_console_foundation.sql` → verify `select count(*) from information_schema.tables where table_schema='ops';` = 13.
2. `116_ops_console_read_api.sql` → `select to_regprocedure('ops.list_orders(jsonb,text,integer)') is not null;`
3. `117_ops_console_automation.sql` → `select jobname from cron.job where jobname like 'ops-%';` = 2 rows.
4. `118_ops_console_corrections.sql` → `select to_regprocedure('ops.executor_claim(uuid,integer)') is not null;` and `select polname from pg_policy where polrelid='storage.objects'::regclass and polname='proof-docs operator read';`
5. `119_listing_block_insert_guard.sql` → `select tgname from pg_trigger where tgname='trg_guard_listing_seller_not_blocked';`
6. **Ledger.** The SQL editor does not write `supabase_migrations.schema_migrations`. Insert one row per file so `supabase migration list` stays 1:1 with the repo, exactly as `docs/release/PHASE2_093_109_PRODUCTION_MIGRATION_EXECUTION.md` did for 093–109:
   ```sql
   insert into supabase_migrations.schema_migrations (version, name, statements)
   values ('115','ops_console_foundation','{}'), ('116','ops_console_read_api','{}'),
          ('117','ops_console_automation','{}'), ('118','ops_console_corrections','{}'),
          ('119','listing_block_insert_guard','{}');
   ```
   After this the ledger reads …109, 115, 116, 117, 118, 119 (+ timestamps).
   **110–114 stay listed as pending** by `supabase migration list`; that is the
   intended state. Until the door-plane train is applied under its own
   runbook, nobody may run `supabase db push` against production — `--dry-run`
   is the only allowed form, and it will show 110–114 as pending by design.
7. `select ops.run_all_detectors();` once by hand; inspect `select job_name, status, error from ops.job_run order by started_at desc limit 20;`.

## 2. Post-apply verification (production)

```sql
select count(*) from ops."case" where status not in ('resolved','dismissed');       -- > 0 (5 disputed transfers alone)
select job_name, last_success_at, consecutive_failures from ops.job_state;
select key, value from ops.setting;                                                  -- refund_execute_enabled=false, actions_enabled=true
select * from ops.metric_snapshot where key = 'money.refunded';                      -- certainty=uncertain
```
Add `ops` to exposed schemas, then as a founder: Today renders; `/denied`
renders for a non-admin; System shows two cron jobs with a success ≤ 5 min old.
Direct-API check of 119: as a blocked seller's session, an `INSERT` into
`listings` returns `listing_blocked` (P0001).

## 3. App deployment (Vercel `snatchit-admin`)

1. Settings → Git: connect `SnatchIt-app/snatchit`, production branch = the branch this PR merges into, Root Directory `admin`, Framework Next.js, Node 22.
2. Environment (Production): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL=https://snatchit-admin.vercel.app`, `NEXT_PUBLIC_ENV_LABEL=production`. **Delete** `SUPABASE_SERVICE_ROLE_KEY` and `ADMIN_SECRET` — the new app must not have them.
3. Deployment Protection: Vercel Authentication ON for previews; production is protected by the app's own auth + MFA.
4. Supabase Auth → URL configuration: add `https://snatchit-admin.vercel.app/**` (do not remove existing entries).
5. Deploy; sign in as each founder; enrol MFA; confirm Today and `/denied`.
6. The previous deployment of this project served pages without authentication and held a service-role key in its environment. **It is never a fallback** (see §5). Once the new build is live, delete the old deployment and its env vars.

## 4. Edge function `ops-refund-execute` (optional, later)

Not deployed by this PR. `ops.setting.refund_execute_enabled` is `false`; the
console rejects refund requests as `disabled` before any approval is parked.
To enable: deploy per `supabase/functions/ops-refund-execute/README.md`, run
its handler tests in CI (they are part of the root `npm test`), then a founder
flips the setting from System → Settings (`setting_set`, audited). Full
refunds only; both founders must approve every refund. `ops.executor_claim`
re-checks the flag, the pause and the approval hash at execution time, so
flipping the setting back to `false` stops in-flight resumptions too.

## 5. Production containment and recovery (non-destructive)

The `ops` schema holds cases, notes, events, actions, approvals and the
append-only audit. **None of it is ever dropped in production.** The rollback
scripts under `supabase/rollbacks/115…119_*` are mechanical reversals for
disposable rehearsal databases only (their headers say so); `115`'s script
refuses while 116/117 objects exist precisely so it cannot be run casually.

### 5.1 Stop new actions (seconds, reversible)
As a founder in System → Settings, or in the SQL editor:
```sql
update ops.setting set value = 'false'::jsonb, updated_at = now() where key = 'actions_enabled';
```
Every `ops.execute_action` / `ops.approve_action` / `ops.executor_claim` call
now fails with `console_actions_paused`; reads, search and the queue keep
working; nothing is lost. Re-enable with `'true'`.

### 5.2 Pause automation (reversible)
```sql
update ops.setting set value = 'false'::jsonb where key = 'detectors_enabled';   -- ticks run and record status 'skipped'
-- or, to stop the ticks entirely:
select cron.unschedule('ops-detect-tick'); select cron.unschedule('ops-daily-summary');
```
Re-register by re-running the cron block at the end of migration 117 (idempotent).

### 5.3 Address in-flight financial actions before changing exposure
```sql
select id, action_type, state, provider_ref, claimed_until, requested_by
  from ops.action where state in ('awaiting_approval','processing','unknown','succeeded_at_provider');
```
- `awaiting_approval`: harmless; deny or let expire (72 h).
- `processing` / `unknown` (refund only): reconcile at the provider by the
  `metadata.ops_action_id` on the Stripe refund; record the truth with
  `ops.record_action_outcome` as service_role (`failed` / `succeeded_at_provider`
  with the refund id). Never POST a new refund by hand while an action is in
  these states.
- `succeeded_at_provider`: wait for `charge.refunded`; the refund detector
  completes the action when `payments.status` becomes `refunded`.
- Payout releases are DB-only (`admin_release_held_payout`); the payout worker
  moves funds on its next run — releases already recorded cannot be "unreleased"
  from the console; a wrong release is handled per `DAY5_MANUAL_REFUND_PLAYBOOK`.

### 5.4 Take the console offline (reversible, data preserved)
Choose one, in this order of preference:
1. **PostgREST exposure**: remove `ops` from exposed schemas. Every console
   read and write returns `PGRST106`; the app shows "RPC not available"; no
   data changes. Reverse by re-adding `ops`.
2. **Vercel**: point the project at a known-safe authenticated build (the
   current one with `actions_enabled=false`, or a maintenance page deployment
   that renders a static "console paused" response behind the same
   authentication). Never redeploy the pre-PR build.
3. **Auth**: revoke a founder's sessions (Authentication → Users → sign out) if
   a device is suspect; membership revocation is `delete from public.admin_users where user_id = …`.

### 5.5 Undo a specific migration effect without data loss
- 119 (listing guard): `supabase/rollbacks/119_…_rollback.sql` is safe in
  production (drops a trigger + function; no data); the block reverts to
  advisory. Record the reason in the runbook and PR.
- 118 storage policy: `drop policy "proof-docs operator read" on storage.objects;` removes founder evidence access only.
- 117 cron: §5.2.
- 115/116/118 functions: leave in place; with `ops` unexposed and actions
  paused they are inert. Do not drop the schema.

### 5.6 Verification and re-enable
1. `select key, value from ops.setting;` shows the intended switches.
2. `select count(*) from ops.action where state in ('processing','unknown');` = 0 before re-enabling refunds.
3. Re-add `ops` to exposed schemas; `actions_enabled` → `true`; `detectors_enabled` → `true` (or re-register cron).
4. As a founder: Today renders, one harmless action (add a case note) succeeds and appears in the audit log.

## 6. Disposable-environment rollback (rehearsal databases only)
`supabase/rollbacks/119_…` → `118_…` → `117_…` → `116_…` → `115_…` (refuses while
116/117 remain). Destroys the console's operational history — that is why it is
confined to rehearsal databases.

## 7. Go-live sequence (owner)
1. Bootstrap the second founder (`FOUNDER_BOOTSTRAP.md`).
2. Visually confirm auto-deploy is OFF; record the date in the PR description.
3. Apply 115→119 per §1 (SQL-editor path) and insert the five ledger rows.
4. Add `ops` to PostgREST exposed schemas.
5. Run `select ops.run_all_detectors();` and the §2 checks.
6. Vercel cut-over per §3; delete the old deployment's privileged variables.
7. Each founder signs in, enrols MFA, sees Today; a non-admin account sees `/denied`.
8. Later, optionally: deploy `ops-refund-execute`, then enable `refund_execute_enabled` (§4).
