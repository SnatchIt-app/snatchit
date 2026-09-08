# Deployment record — operating console RC3 (non-refund portal), 2026-09-08

Owner approval received 2026-09-07 for release commit
`ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64` (PR #55 head, all six CI checks
green, six migration SHA-256 values re-verified against
`RELEASE_CHECKLIST_RC3.md` §2 before execution). Owner visually confirmed
Supabase GitHub "Deploy to production" is OFF on 2026-09-07. Refund execution
stays disabled: `ops.setting refund_execute_enabled=false`,
`ops-refund-execute` is not deployed (edge function list has no such slug;
`POST /functions/v1/ops-refund-execute` → 404).

## Executed (UTC times from the database clock)

| # | Step | Result |
|---|---|---|
| 1 | Old portal restricted | Production alias `snatchit-admin.vercel.app` re-pointed to a prebuilt static maintenance deployment (`snatchit-admin-ij7d1pvw4-…`, HTTP 503 on every path, `no-store`, `noindex`). Direct deployment URLs were already behind Vercel Authentication (Standard Protection, `ssoProtection.deploymentType=all_except_custom_domains`): every old URL answers 302 → `vercel.com/sso-api`. Verified `/`, `/users`, `/api/users`, `/orders` on the main domain → 503 maintenance body; no portal HTML served. Reversible: the maintenance deployment is superseded by step 5 and can be deleted with the old ones. |
| 2 | Privileged variables removed | `SUPABASE_SERVICE_ROLE_KEY` removed from Development, Preview and Production of project `prj_o17cASVVqqyGKPUtiklJRvAMVgNB`. No `ADMIN_SECRET*` variable existed. The key itself was not rotated (out of scope). `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` kept. |
| 3 | Migrations 115→120 applied | Executed one file at a time through the Supabase Management API query endpoint (`supabase db query --linked --project-ref hqycwntpfoztoinemqns -f …`, the same endpoint the SQL editor uses; `db push` not used). Post-apply checks: 115 → 13 `ops` tables; 116 → `ops.list_orders(jsonb,text,integer)` present; 117 → cron `ops-detect-tick */5 * * * *`, `ops-daily-summary 0 13 * * *`; 118 → `ops.executor_claim(uuid,integer)` present, storage policies 12, settings 9, `actions_enabled=true`, `refund_execute_enabled=false`; 119 → trigger `trg_guard_listing_seller_not_blocked` = 1 (0 blocked sellers immediately before apply); 120 → `ops.normalize_summary_body(jsonb)` present, 90 `ops` functions. Ledger: six rows `115…120` inserted with `on conflict do nothing`; duplicate versions 0; total rows 130; numeric tip 120; **110–114 remain unapplied by design**. |
| 4a | First detector sweep | `ops.run_all_detectors()` at 2026-09-08 00:27:10Z: 12 jobs succeeded, 0 failed, 0 skipped (the cron tick had already run successfully at 00:25:01Z). Open cases: `dispute_open` 5 (p1), `paid_unsettled` 9 (p1), `refund_pending` 2 (p1), `report_review` 3 (p3). `ops.job_state`: 12 detectors with a last success, `consecutive_failures=0`; `daily_summary` has not run yet (13:00 UTC). |
| 4b | Second founder bootstrapped | `auth.users` lookup for `contact@snatchitapp.com`: exactly one account (`3b7b50af-e9a2-41b6-89a3-b82a43dcae00`, confirmed 2026-09-03, last sign-in 2026-09-06, not banned, not SSO, not previously an operator). Inserted into `public.admin_users` with label `Founder — contact@snatchitapp.com`. Operators now 2; verified MFA factors 0 for both (G1 pending). |
| 5 | Console deployed | `vercel deploy --prod` from `admin/` of the clean worktree at `ab3e17f` (project root still `.`, so the upload root is `admin/`), meta `releaseCommit=ab3e17f…`, `releaseBranch=admin/operating-console`. Deployment `dpl_4Jvmh65zftTptKjBvknFCguGw54Z` = `https://snatchit-admin-uke2t8ftj-gnvprod-5449s-projects.vercel.app`, aliased to `https://snatchit-admin.vercel.app` at 2026-09-08 00:30Z. Env vars (names only): Production `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL=https://snatchit-admin.vercel.app`, `NEXT_PUBLIC_ENV_LABEL=production`; Preview `NEXT_PUBLIC_SITE_URL=<branch preview origin>`, `NEXT_PUBLIC_ENV_LABEL=staging`. Verified unauthenticated: `/`, `/system`, `/users`, `/orders`, `/mfa`, `/api/health` → 307 to `/login?next=…`; `/login` renders with the red `production` badge. No `.vercel` directory was written into the repo. Built on Node 24 (project setting; `engines >=22 <25` satisfied) — owner step below pins 22. |

## Not executed — needs the owner (no CLI/API path with the available session)

| Step | Exact action | Verification |
|---|---|---|
| 4c | Supabase Dashboard → Project Settings → Data API → **Exposed schemas**: add `ops` (keep `public`, `graphql_public`, `kernel`). Save. | `curl -H "apikey: <anon>" -H "Accept-Profile: ops" https://hqycwntpfoztoinemqns.supabase.co/rest/v1/nonexistent` → 404 (currently 406 `PGRST106`). Until then the console fails closed: sign-in works, every `ops.*` call is refused. |
| 5b | Supabase Dashboard → Authentication → URL Configuration → **Redirect URLs**: add `https://snatchit-admin.vercel.app/**` (keep existing entries). | Entry visible in the list. Password sign-in and TOTP enrolment do not depend on it. |
| 5c | Vercel → snatchit-admin → Settings → General: **Root Directory** `admin`, **Node.js Version** `22.x`. Settings → Git → Ignored Build Step → Custom: `test "$VERCEL_GIT_COMMIT_SHA" != "ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64"` (exit 0 = skip, so only the approved commit builds). Then Settings → Git → Connect `SnatchIt-app/snatchit`, **Production Branch** `admin/operating-console`. Order matters: root, Node and the ignore step first, then connect; connecting first would make pushes to the repo's default branch build the repo root. | After connecting, a push to `admin/operating-console` with any other SHA shows "Build skipped" in Vercel; the production alias stays on `dpl_4Jvmh65zftTptKjBvknFCguGw54Z`. Update the pinned SHA per release. |

## Acceptance gates (§6) — status

G8 evidence taken: endpoint absent (404), `refund_execute_enabled=false`, no
`refund_execute` action rows. G0 evidence: see step 3. G1–G7 need the founders
(`ACCEPTANCE_GATES.md`, `admin/scripts/acceptance/gate-probe.mjs`) and can
only pass after 4c. Founder operations do not switch to the portal until all
eight pass.

## Step 7 — retirement list (execute only after G1–G8 pass)

Delete exactly these snatchit-admin deployments (`vercel rm <url> --yes`):
`snatchit-admin-ge76xzu3b`, `snatchit-admin-osk87b046`, `snatchit-admin-hwnjj2d3b`,
`snatchit-admin-oprryrb0r`, `snatchit-admin-ceqjqctlo`, `snatchit-admin-js7xrjfi1`,
`snatchit-admin-m2bdy376k`, `snatchit-admin-m5zlbqa4x` (all `…-gnvprod-5449s-projects.vercel.app`),
plus the maintenance deployment `snatchit-admin-ij7d1pvw4`. Keep `snatchit-admin-uke2t8ftj`
(current production). Nothing else in the account is touched.

## Containment (if a gate fails)

`RUNBOOK.md` §5: `actions_enabled=false` → detectors off → remove `ops` from
exposed schemas (or simply never add it). The old portal is not a fallback and
its maintenance page stays in place; no deployment is promoted back.
