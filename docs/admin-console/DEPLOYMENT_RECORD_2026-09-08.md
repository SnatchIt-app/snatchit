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

---

# Addendum — configuration, redeploy and real-service acceptance (2026-09-08, 00:45–02:00 UTC)

Owner approval received 2026-09-08 for the remaining configuration, redeploy
and acceptance work; executed through the owner's authenticated Chrome
sessions (Supabase dashboard, Vercel dashboard) plus the local CLIs for
verification. Release commit unchanged: `ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64`.

## Supabase (verified)

| Item | Result |
|---|---|
| Data API exposed schemas | `public, graphql_public, kernel, ops` (was 3 of 8, now 4 of 8; saved via Integrations → Data API → Settings, toast "Successfully saved settings"). Verified from outside: `Accept-Profile: ops` on a nonexistent table → 404 (was 406 PGRST106); anon `POST rpc/whoami` with `Content-Profile: ops` → 42501 "permission denied for schema ops" (fail-closed, anon has no usage); `public`/`kernel` unchanged (404). |
| Auth redirect URLs | `https://snatchit-admin.vercel.app/**` added (10 entries total, 9 pre-existing preserved). Site URL unchanged (`https://snatchti.com`). |
| GitHub integration | Read-only re-check: "Deploy to production" **off**, "Automatic branching" off. Not touched. |

## Vercel `snatchit-admin` (verified through the project API after each save)

| Item | Result |
|---|---|
| Root Directory | `admin` (PATCH 200, toast "Root directory updated"). |
| Node.js Version (project setting) | `22.x`. **Effective build runtime is 24.x** for this commit: `admin/package.json` declares `engines.node ">=22.0.0 <25.0.0"`, and Vercel documents that `engines.node` overrides the project setting (a range resolves to the highest available major, 24). Every deployment of `ab3e17f` therefore reports `nodeVersion: 24.x`. Pinning 22 requires a one-line `engines` change = a new commit; not done (exact approved commit deployed). |
| Ignored Build Step | Behavior "Custom", command `test "$VERCEL_GIT_COMMIT_SHA" != "ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64"` (Vercel UI states: exit 1 = build, exit 0 = skip → only the approved SHA builds from Git). Saved and read back as `commandForIgnoringBuildStep` **before** connecting Git. |
| Git | Connected `SnatchIt-app/snatchit` (GitHub) after the guard; Production branch changed from the default `main` to `admin/operating-console` (Environments → Production → Branch Tracking, toast "Branch tracking saved"). No Git-triggered deployment was created by the connection. |
| Environment variables | Development/Preview/Production: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`; Production: `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_ENV_LABEL`; Preview (all branches): `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_ENV_LABEL`. **No** `SUPABASE_SERVICE_ROLE_KEY`, **no** `ADMIN_SECRET*` in any scope. |
| Deployment protection | Unchanged (`ssoProtection.deploymentType = all_except_custom_domains`): every old deployment URL still answers 302 → Vercel SSO. |
| Redeploy | `vercel deploy --prod` from a detached worktree at `ab3e17f` (clean tree, `git rev-parse HEAD` verified) → production deployment `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr` (`snatchit-admin-jhe92fpqv-…`), `meta.gitCommitSha = ab3e17f…`, `gitCommitMessage` = the RC3 checklist commit, `readyState READY`, `target production`, aliased to `https://snatchit-admin.vercel.app` (CLI `vercel inspect snatchit-admin.vercel.app` → that deployment). Build log: Next.js 16.3.3, `npm run build`, Build Completed. Two earlier same-commit deployments from this session (`…-q6mhr48m7`, `…-a7t1i7zi6`) are superseded, not deleted. |

## Real-service acceptance — results

| Gate | Result | Evidence |
|---|---|---|
| G1 founder A (`g***@gmail.com`) | **PASS** | Signed in with own password, enrolled TOTP in own authenticator, Today loaded with live queue (19 open items). DB: `verified_factors = 1`, session `aal = aal2`. Signed out afterwards (0 sessions). |
| G1 founder B (`c***@snatchitapp.com`) | **PASS** | Same flow. DB: `verified_factors = 1`, session `aal2`. Console header shows the account as ADMIN; Today, Cases, System, Orders pages render → authorised `ops.*` reads succeed at aal2 (`ops.whoami` drives the operator header). |
| G2 non-operator denied | **awaiting test account** (owner creating a plain account; probe run as that account). DB-side proof: pgTAP 181/184; anon at the REST layer → 42501. |
| G3 lower-assurance denied | **PASS** | Founder B ran `gate-probe.mjs` locally (credentials typed in a Terminal window, never echoed or recorded). Before TOTP (session aal1): `list_cases` → 400 step-up refusal, `execute_action` → 400 refusal. After the real TOTP challenge: `G1-verify aal=aal2`, `G1-operator` recognised. The probe originally looked for factors at `/auth/v1/factors` (no GET there); fixed to read `GET /auth/v1/user → factors[]` (commit `4b3acbe`, script only). |
| G4 founder opens eligible evidence | **PASS (proof-docs objects)** | Founder B (not a party) on order `7f0b099e…` / transfer `80180da9…` ("Stripe test 3"): `Open evidence · audited` → `ops.evidence_access` ok → signed URL → the 2048×1152 PNG rendered in the tab. Audit row `evidence.viewed` (actor 3b7b50af…, platform_admin, slot transfer_evidence). Storage logs: `POST /object/sign/proof-docs/… 200`, `GET … 200`. |
| G4 — **finding** | **FAIL-CLOSED for legacy objects** | First attempt on transfer `b6e57049…` ("Beta test 4"): RPC ok + audited, but signing returned 400 and the page showed "evidence not accessible". Cause: the object lives in bucket **`auction-media`**, while `ops.evidence_access` and the policy `proof-docs operator read` assume `proof-docs`. Production census: transfer evidence 11 of 17 in `auction-media`, 6 in `proof-docs`; proof-of-ownership 16 of 35 in `auction-media`, 19 in `proof-docs`. Nothing was exposed (the console refuses). **Pre-existing exposure noted:** `auction-media` is a *public* bucket with policy `public read public buckets`, so those legacy evidence files are already world-readable by URL — unrelated to this package, needs an owner decision (move them into `proof-docs` and teach `evidence_access` the real bucket; a new migration, not authorised in this phase). |
| G5 bad slot / arbitrary path (operator) | **PASS** | Probe as founder B at aal2: `evidence_access` with an invalid slot → 400; signing an arbitrary path in another bucket → 400; `proof-docs` listing as operator shows only referenced objects (2 visible). |
| G5 unrelated user (non-operator) | **awaiting test account** (owner is creating one; no founder or role change). |
| G6 signed links expire | **PASS** | Same signed URL: 01:52:04Z → 200 image/png; 01:56:18Z (after the 300 s TTL, `exp` in the token) → 400 `InvalidJWT: "exp" claim timestamp check failed`. |
| G7 pause / recovery | **PASS** | Synthetic manual case `650e7344…` created by founder B (action 1b67e578; audit `action.requested` + `action.case_create succeeded`). `actions_enabled → false` with reason (action c08081fd; audit `action.setting_set succeeded false`); banner "ACTIONS PAUSED" on every page; adding a note on the synthetic case refused with "Nothing was changed … every mutation is refused" and **no action row written**; Today still rendered. `actions_enabled → true` (action b96c1739); note then recorded (`case_note succeeded`, 1 note on the case). Final state: `actions_enabled = true`. |
| G8 refunds disabled | **PASS** | `refund_execute_enabled = false` (System → Settings shows the warning; probe `G8-setting` PASS); `ops-refund-execute` absent from the edge-function list and → 404 (probe `G8-endpoint-absent` PASS); no `refund_execute` action rows. |

**Defect found (not a gate):** System → Jobs panel shows "Request failed — canceling statement due to statement timeout (57014)". `ops.job_health()` runs correlated 24-hour counts over `cron.job_run_details` (454,675 rows, only the primary-key index; `crm-export-build-tick` runs every minute) and exceeds the 8 s statement timeout. Other System sections (settings, approvals, actions, audit, summary) and every other page work. Fix = new migration (index on `cron.job_run_details(jobid, start_time)` or a bounded query) — **not applied** (no additional migrations in this phase).

## Retirement — not yet executed

Blocked on G2/G3/G5 (founder probe). The retirement list in the main record stands; add the two superseded same-commit deployments `snatchit-admin-q6mhr48m7-…` and `snatchit-admin-a7t1i7zi6-…` only if the owner wants them gone (they are authenticated builds of the approved commit, protected by SSO on their URLs).

**Git guard proven live:** the docs push `2459bdc` to `admin/operating-console` created Git deployment `dpl_BEGD13gGY1zZLswR76xsU4UpCAMs`, which Vercel canceled: "The deployment was canceled because the Ignored Build Step command returned exit code 0"; the production alias stayed on `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr`. Side effect: pushes to other branches now create *errored* preview deployments (`NOW_SANDBOX_WORKER_ROOTDIR_NOT_EXIST`, no `admin/` there) — inert and SSO-gated, but they consume Hobby build minutes; Preview → Branch Tracking can be disabled (owner decision, not changed).

---

# Addendum 2 — stopping the failed automatic preview deployments (2026-09-08 04:40–04:55 UTC)

**Symptom.** Every push to `feature/venue-native-and-product-v2` (and other non-admin branches) created a `snatchit-admin` preview deployment that failed within seconds: `NOW_SANDBOX_WORKER_ROOTDIR_NOT_EXIST` — "The specified Root Directory "admin" does not exist." (e.g. `c4f562d` at 04:40:30Z), one failure e-mail per push.

**Confirmed root cause.** The project's Root Directory is `admin` (correct for the console). The `admin/` tree exists only on `admin/operating-console`; PR #55 is unmerged, so every other branch lacks it. Vercel validates the Root Directory right after cloning and **before** running the Ignored Build Step, so the SHA-pinned guard (`test "$VERCEL_GIT_COMMIT_SHA" != …`) never executes on those branches — it only governs branches where the root exists (it did cancel the docs pushes on `admin/operating-console`, e.g. `dpl_BEGD13gGY1zZLswR76xsU4UpCAMs`, `dpl_GhWUeMBrP2zW8dMcmceJvpB4qtCk`). A `vercel.json` rule cannot help either: it would have to live under the missing `admin/` directory, and a repo-root `vercel.json` would affect `snatchit-web`.

**Change (project-scoped, reversible).** Vercel → snatchit-admin → Settings → Environments → **Preview → Branch Tracking: disabled** (was enabled, matching "All unassigned branches"). Vercel's own description: "If disabled, you can still create deployments using the CLI or the Vercel API." Nothing else changed — re-read after save: Git link `SnatchIt-app/snatchit`, Production branch `admin/operating-console`, Root Directory `admin`, Node 22.x, Ignored Build Step unchanged, `ssoProtection.deploymentType = all_except_custom_domains`, no deployments deleted, notifications untouched.

**Verification.**
- Saved state re-read after a full page reload: Branch Tracking checkbox off, the branch-pattern input no longer rendered.
- Authorized trigger: a throwaway branch `chore/vercel-preview-probe-20260908` was pushed at 04:49:44Z pointing at the same commit as the failing branch (`c4f562d`, no `admin/` directory). At 04:51:04Z the newest `snatchit-admin` deployment was still the 11-minute-old error (`…-psgvex81a`); no deployment was created. Before the change the same kind of push produced an ERROR deployment within ~5 s. The probe branch was deleted at 04:51:08Z (GitHub returns 404 for it).
- Next real push to `feature/venue-native-and-product-v2` itself: not yet observed at the time of writing (last commit `c4f562d` 04:40:01Z); a watcher was left running and its outcome, if it lands during this session, is reported in chat. "Configuration verified" therefore rests on the saved state plus the equivalent probe push.
- Production preserved: `snatchit-admin.vercel.app` → `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr` (Ready, commit `ab3e17f`); `/`, `/system`, `/users`, `/cases` → 307 to `/login`; login page title "Sign in · Console · production"; old deployment URLs still 302 → Vercel SSO.

**How approved admin releases work from here.**
1. Production branch pushes (`admin/operating-console`) still reach Vercel and are canceled unless the commit SHA equals the pinned one in the Ignored Build Step. To release a newly approved commit from Git: update the pinned SHA in Settings → Build and Deployment → Ignored Build Step, then push or "Redeploy" that commit.
2. Alternatively (the path used for this release): from a clean checkout of the approved commit, `vercel deploy --prod` with `VERCEL_ORG_ID=team_rld7LG9DKzgaph97l4H4jl9d VERCEL_PROJECT_ID=prj_o17cASVVqqyGKPUtiklJRvAMVgNB` — CLI deployments ignore the Ignored Build Step and branch tracking.
3. Preview builds of the console are on demand only: `vercel deploy` (no `--prod`) from a checkout that contains `admin/`. Nothing deploys automatically from feature branches any more.

**Remaining limitation.** Pushes to `admin/operating-console` with a non-pinned SHA still create a *canceled* production-target deployment (silent, no failure e-mail, nothing promoted). Once PR #55 is merged into `feature/venue-native-and-product-v2`, that branch will contain `admin/`; automatic previews for it stay off unless Branch Tracking is re-enabled.
