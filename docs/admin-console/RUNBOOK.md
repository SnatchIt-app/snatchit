# Operating console — deployment, migration and rollback runbook

Scope: migrations `115_ops_console_foundation`, `116_ops_console_read_api`,
`117_ops_console_automation`; the `admin/` Next.js app (Vercel project
`snatchit-admin`); edge function `ops-refund-execute` (optional, disabled by
default). Nothing in this PR is applied or deployed by merging
(AUTODEPLOY-1: production auto-deploy is OFF — re-verify visually before every
apply; record `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` in the PR).

## 0. Preconditions (owner)

| Check | How |
|---|---|
| Production ledger tip | `select version from supabase_migrations.schema_migrations order by version desc limit 3;` — expected numeric tip **109** on 2026-09-06. |
| Unapplied 110–114 | This package is numbered after them. `supabase db push` applies **every** pending file in order, so pushing 115–117 also applies 110–114 (door-plane, DARK, rehearsal-only). Decide explicitly: either apply 110–114 first under their own runbook, or apply 115–117 one file at a time via the SQL editor (path A below) so the door-plane files stay unapplied. Do not let a convenience push decide this. |
| PostgREST exposed schemas | Dashboard → Project Settings → API → Exposed schemas: currently `public, kernel`. **Add `ops`.** Without it every console call returns `PGRST106`. Reversible in one click. |
| Second founder bootstrapped | `docs/admin-console/FOUNDER_BOOTSTRAP.md` — approvals need two founders. |
| Rehearsal green | `scripts/rehearsal_reset.sh`, apply 115→117, `scripts/rehearsal_test.sh … 000 181 182 183` all planned == ran. |

## 1. Apply order

Path A — SQL editor, one file at a time (recommended; keeps 110–114 unapplied):

1. Paste `supabase/migrations/115_ops_console_foundation.sql`. Run. Verify:
   `select count(*) from information_schema.tables where table_schema='ops';` → 13.
2. Paste `116_ops_console_read_api.sql`. Verify:
   `select to_regprocedure('ops.list_orders(jsonb,text,integer)') is not null;` → true.
3. Paste `117_ops_console_automation.sql`. Verify:
   `select jobname, schedule, active from cron.job where jobname like 'ops-%';` → 2 rows.
4. Insert the ledger rows so `supabase migration list` stays 1:1 with the repo
   (the SQL editor does not do this): for each of 115/116/117
   `insert into supabase_migrations.schema_migrations(version, name, statements) values ('115','ops_console_foundation', '{}');` (mirror the exact form used in `docs/release/PHASE2_093_109_PRODUCTION_MIGRATION_EXECUTION.md`).
5. First detector run, manually, as `postgres`: `select ops.run_all_detectors();` and inspect `select * from ops.job_run order by started_at desc limit 20;`.

Path B — `supabase db push --include-all` from the merged commit with CLI 2.115.0 — only if 110–114 are meant to go live in the same window.

## 2. Post-apply verification (production)

```sql
select count(*) from ops."case" where status not in ('resolved','dismissed');   -- expect > 0 (5 disputed transfers alone)
select job_name, last_success_at, consecutive_failures from ops.job_state;
select * from ops.metric_snapshot;
```
As a founder (from the console): Today shows the queue; `System` shows the two
cron jobs and last success within 5 minutes.

## 3. App deployment (Vercel `snatchit-admin`)

Current state: the project deploys from the separate `~/snatchit-admin` repo via
CLI (`.vercel/` link, one commit). Cut over:

1. Project → Settings → Git: connect `SnatchIt-app/snatchit`, production branch = the branch this PR merges into. Root Directory = `admin`. Framework Next.js. Node 22.
2. Environment variables (Production scope): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL=https://snatchit-admin.vercel.app`, `NEXT_PUBLIC_ENV_LABEL=production`. **Delete** `SUPABASE_SERVICE_ROLE_KEY` and `ADMIN_SECRET` from the project — the new app must not have them.
3. Deployment Protection: Vercel Authentication ON for previews; production is protected by the app's own auth + MFA.
4. Supabase Auth → URL configuration: add `https://snatchit-admin.vercel.app/**` to redirect URLs (do not remove existing entries).
5. Deploy; sign in as a founder; enrol MFA; confirm `/` renders the queue and `/denied` renders for a non-admin test account.
6. Retire the old repo's deployment (it holds a service-role key in Vercel env). Keep the repo for history.

## 4. Edge function `ops-refund-execute` (optional, later)

Not deployed by this PR. `ops.setting.refund_execute_enabled` is `false`; the
console shows refund execution as disabled with the Stripe-Dashboard SOP link.
To enable: deploy per `supabase/functions/ops-refund-execute/README.md`, then a
founder flips the setting from System → Settings (`setting_set`, audited). Both
founders must approve every refund.

## 5. Rollback

Order matters (schema dependencies): `supabase/rollbacks/117_…_rollback.sql`
(unschedules `ops-detect-tick`, `ops-daily-summary`, drops automation
functions) → `116_…_rollback.sql` (drops read API) → `115_…_rollback.sql`
(drops schema `ops`; **refuses** while 116/117 objects exist; destroys the
console's audit/cases — export `ops.audit` first if it has been used in
production). Remove `ops` from Exposed schemas. Redeploy the previous Vercel
deployment or unlink the project. No public.* object is touched by any of the
three migrations, so the marketplace apps are unaffected in either direction.

## 6. Blast radius

Additive schema only; no change to any existing table, policy, trigger or
function. New cron load: one 5-minute tick running ~12 small partial-index
queries, one daily summary. New PostgREST surface: `ops` schema, functions
granted to `authenticated` but every one raises `42501` for non-operators.
