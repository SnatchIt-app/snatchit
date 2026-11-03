# Release checklist — operating console RC3 (non-refund portal)

Prepared 2026-09-07 from read-only inspection. **Nothing here has been
executed.** Every step below needs explicit owner approval; refund execution
stays disabled throughout.

## 0. Release candidate

| Item | Value |
|---|---|
| PR | [#55](https://github.com/SnatchIt-app/snatchit/pull/55), draft, base `feature/venue-native-and-product-v2` |
| Reviewed commit | `051ebe7c1c9366aa1faa6cf75dcdadba10aeb2b5` — all six CI checks green (run 34141303192 / 34141328309) |
| Release commit | the PR head at approval time; the only commits after `051ebe7` are documentation and acceptance scripts (no migration, app or edge changes). The six migration files are byte-identical to `051ebe7` — checksums below. |
| Base movement | none since the PR base (`aa74cc2`) |
| Merge | **Not required to deploy**, and not recommended yet: the Vercel project is not git-linked, so the app is deployed by pointing Vercel at this branch/commit; migrations are applied from the files in this branch. Merging into `feature/venue-native-and-product-v2` triggers no Supabase apply (`git_branch: ""` — visual confirmation still required) and no Vercel deploy today (no project is linked to that branch). Merge after acceptance, as its own decision. |

## 1. Production facts (read-only, 2026-09-07)

| Fact | Value |
|---|---|
| Migration ledger | numeric tip **109**, 124 rows; **115–120 unapplied**; **110–114 unapplied (intentionally pending, door-plane)** |
| `ops` schema | absent |
| `storage.objects` policies | 11 (118 adds the 12th) |
| `admin_users` | **1** row (label "SNATCH IT APP ADMIN", `g***@gmail.com`, has signed in, **0 MFA factors**) |
| `kernel.platform_role` | 0 rows |
| MFA factors on the project | 0 |
| PostgREST exposed schemas | `public`, `kernel` (`ops` returns 406) |
| Supabase auto-deploy | production branch record `git_branch: ""` (API). **Owner must confirm visually in Dashboard → Integrations/Branching before any apply** and record `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD`. |
| Vercel `snatchit-admin` | project `prj_o17cASVVqqyGKPUtiklJRvAMVgNB`, owner `gnvprod-5449's projects`; **not git-linked**; Root Directory `.`; Node 24.x; Framework Next.js; last production deploy **152 days ago** (CLI); env vars `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, **`SUPABASE_SERVICE_ROLE_KEY`** in Development+Preview+Production |
| Live old portal | `https://snatchit-admin.vercel.app/users` renders (HTTP 200) **without authentication** today |
| Disputed transfers awaiting founders | 5 |
| Evidence available for G4 | 17 transfers with `transfer_evidence_path`, 35 listings with `proof_of_ownership_path` |

## 2. Migrations — exact order and checksums (SHA-256 of the files at `051ebe7`)

Apply via the Supabase SQL editor, one file at a time, in this order. Do **not**
use `supabase db push` (it would also apply 110–114).

| # | File | SHA-256 | Post-apply check |
|---|---|---|---|
| 1 | `115_ops_console_foundation.sql` | `8a33cc0017d25e39708266a52b4f15ab5cba737d35b55779d45e9537f08d090d` | `select count(*) from information_schema.tables where table_schema='ops';` → 13 |
| 2 | `116_ops_console_read_api.sql` | `a144964702b7b4c95ffe1b91854fca0b5a3aded7b0b420a505bf3ef3e9da9069` | `select to_regprocedure('ops.list_orders(jsonb,text,integer)') is not null;` → t |
| 3 | `117_ops_console_automation.sql` | `be9e22840a818c5fbc4e1d41a92bf19f4cf09c367f48bda68dba9578c846cdcf` | `select jobname from cron.job where jobname like 'ops-%';` → 2 rows |
| 4 | `118_ops_console_corrections.sql` | `616677c4b2e1245a9f2680da67bb1cdc4047babd6c4cb89ec631f868df5f2074` | `select to_regprocedure('ops.executor_claim(uuid,integer)') is not null;` → t; storage policies → 12 |
| 5 | `119_listing_block_insert_guard.sql` | `67736a4f4db31275ddb6dc736fb3b1e21d883d7516339ad60593919da4a72bc6` | `select tgname from pg_trigger where tgname='trg_guard_listing_seller_not_blocked';` → 1 |
| 6 | `120_ops_console_refund_semantics.sql` | `502cd7ba1073737964b0992f62bd2248b621d02931d8cf9c9f6170a4c7304b6e` | `select to_regprocedure('ops.normalize_summary_body(jsonb)') is not null;` → t |

Each file is one transaction; a failure leaves nothing partial. Expected
locks: DDL on new objects; 119 takes a brief SHARE ROW EXCLUSIVE lock on
`public.listings` for `CREATE TRIGGER`. No existing row is rewritten
(`pg_class.relfilenode` of `public.*` tables unchanged). Rehearsed: fresh
000→120 (pgTAP 4,316/4,320, the 4 = documented local deltas) and the exact
production shape 000→109 + timestamps + 115→120 with 110–114 omitted (pgTAP
181–186 green).

**Preflight (owner, before step 1):** `gates.sql` §G0 shows tip 109 and no
115–120; a Supabase backup/PITR point exists for the project (Dashboard →
Database → Backups — confirm the latest daily backup timestamp; PITR if
enabled); visual auto-deploy confirmation recorded.

**Ledger (after step 6):**
```sql
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('115','ops_console_foundation','{}'), ('116','ops_console_read_api','{}'),
       ('117','ops_console_automation','{}'), ('118','ops_console_corrections','{}'),
       ('119','listing_block_insert_guard','{}'), ('120','ops_console_refund_semantics','{}');
-- duplicate / inconsistency check (expect 0 rows and exactly six 115–120 rows):
select version, count(*) from supabase_migrations.schema_migrations group by 1 having count(*) > 1;
select string_agg(version, ',' order by version) from supabase_migrations.schema_migrations where version in ('115','116','117','118','119','120');
```
110–114 remain pending by design; `supabase migration list` will show them so.
**Stop condition:** any post-apply check differs → stop, do not continue to
the next file; the applied files are inert until `ops` is exposed.

## 3. PostgREST exposure (owner, Dashboard → Project Settings → API)

Add `ops` to Exposed schemas (keep `public, kernel`). Verify:
`curl -H "apikey: <anon>" -H "Accept-Profile: ops" https://hqycwntpfoztoinemqns.supabase.co/rest/v1/nonexistent` → 404 (not 406).
Reversal: remove `ops` (this is also containment §5.4).

## 4. First detector run (owner, SQL editor)
```sql
select ops.run_all_detectors();
select job_name, status, error from ops.job_run order by started_at desc limit 20;   -- expect succeeded, no error
select case_type, count(*) from ops."case" where status not in ('resolved','dismissed') group by 1;
```
Expected: cases for the 5 disputed transfers (`dispute_open`), any refund
pending / stuck release / webhook backlog present today; `job_failure` cases
are possible for the `crm-export-*` ticks (they post to an unauthored
function) — that is a true signal, not a fault of the console.

**Runtime effects from here on:**
- `ops-detect-tick` every 5 min (~12 partial-index queries) and `ops-daily-summary` at 13:00 UTC.
- 119: an insert into `public.listings` by a seller whose `seller_risk_scores.is_listing_blocked` is true fails with `listing_blocked`. **Today no seller is blocked** (read-only check 2026-09-07: 0 rows with `is_listing_blocked`), so the trigger changes nothing until a founder blocks someone from the console; re-check before apply.
- 118 storage policy: operators with aal2 gain SELECT on proof-docs objects that a transfer/listing references; buyers/sellers unchanged.

## 5. Founder bootstrap (owner)

Second founder = an **existing** `auth.users` account the owner names; never
guessed (there are 7 accounts on snatchit-owned domains and 18 in total — the
owner picks). Then, per `FOUNDER_BOOTSTRAP.md`:
```sql
select id, created_at from auth.users where email = '<owner-confirmed email>';
insert into public.admin_users (user_id, label) values ('<that id>', 'Founder — <name>') on conflict (user_id) do nothing;
select a.label, left(u.email,1)||'***@'||split_part(u.email,'@',2) from public.admin_users a join auth.users u on u.id=a.user_id;
```
MFA: both founders enrol TOTP on first console sign-in (G1). No factor exists today.

## 6. Vercel (owner — the automation token here cannot modify this project)

1. Settings → Git: connect `SnatchIt-app/snatchit`, production branch `admin/operating-console` (or the merge target after merge), **Root Directory `admin`**, Framework Next.js, Node **22.x** (`admin/package.json` engines `>=22 <25`; Node 24 also satisfies it — keep 22 to match CI).
2. Environment variables, **Production** scope (names only): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL=https://snatchit-admin.vercel.app`, `NEXT_PUBLIC_ENV_LABEL=production`. Preview scope: same URL/key, `NEXT_PUBLIC_SITE_URL` = the preview origin, `NEXT_PUBLIC_ENV_LABEL=staging`.
3. Deployment Protection: Vercel Authentication ON for Preview; Production relies on the app's own auth + MFA.
4. Deploy from the release commit; confirm the build log shows the `admin/` app (route list includes `/mfa`, `/system`).
5. Supabase Auth → URL Configuration: **add** `https://snatchit-admin.vercel.app/**` (keep existing entries). Verified origin: `https://snatchit-admin.vercel.app` (current project alias).

## 7. Retire the old deployment (owner, **after** G1–G8 pass)

1. `vercel env rm SUPABASE_SERVICE_ROLE_KEY` for Development, Preview and Production (the new app never reads it; the key itself stays valid for edge functions — rotate it separately if it may have leaked).
2. Delete the pre-cut-over deployments (`vercel rm <deployment-url>` for the 152-day-old production and preview deployments) so no unauthenticated build remains addressable.
3. Optionally archive `~/snatchit-admin` (no git remote; keep for history).
Until then the old build stays as-is: it is **not** a fallback (it exposes `/users` without auth) and must not be redeployed.

## 8. Containment / fallback (non-destructive; runbook §5)

`actions_enabled=false` (pause every mutation, reads work) → `detectors_enabled=false` or unschedule the two cron jobs → remove `ops` from exposed schemas (console fails closed, all `ops` data preserved) → revoke a founder's sessions if a device is suspect. Never drop `ops`; never redeploy the old portal.

## 9. Approval required for

A. Applying migrations 115→120 in the order above and inserting the six ledger rows.
B. Adding `ops` to PostgREST exposed schemas.
C. Inserting the owner-named second founder into `public.admin_users`.
D. Vercel: linking the repo, root `admin`, env vars, deploying the release commit; adding the Auth redirect URL.
E. After acceptance: removing `SUPABASE_SERVICE_ROLE_KEY` from the Vercel project and deleting the old deployments.

Explicitly **not** requested: merging the PR, deploying `ops-refund-execute`, changing `refund_execute_enabled`.
