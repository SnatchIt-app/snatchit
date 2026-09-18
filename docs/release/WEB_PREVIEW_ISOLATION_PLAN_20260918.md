# Web preview isolation — plan and APPLIED interim (A, 2026-09-18). Two owner-approved setting changes applied; see §6

**Owner's decision (2026-09-18):** *"website previews should not connect to the production database."*

**Ground rules:**
- This is a plan with an exact proposed change, for approval before anything is applied.
- Production settings are preserved.
- PRs #72–#76 stay unmerged until this is settled.
- No production database work.

Every fact below comes from **read-only** reads made on 2026-09-18:
- Vercel API through the installed CLI (`vercel api`);
- the Supabase connector and CLI;
- the repo at `release/production-gate-20260918`.

§§1–5 describe the state **before** the changes. §6 records the two owner-approved changes applied afterwards, and their verification.

## 1. Affected Vercel projects (team `gnvprod-5449s-projects`, 8 projects)

| Project | Linked to this repo | Production branch | Preview → database | New previews today |
|---|---|---|---|---|
| **`snatchit-web`** (`prj_UjnX…`, root `web/`) | yes | `feature/web-accounts-foundation` | **production** `hqycwntpfoztoinemqns` | **built on every push to any other branch**, with no ignored-build step |
| **`snatchit-admin`** (`prj_o17c…`, root `admin/`) | yes | `admin/operating-console` (the live console, which must keep production) | **production** | effectively none: the ignored-build step builds only `ab3e17f` |
| `snatchitwebapp` | no | — | no preview-targeted variables | none |
| 5 others | other repos, or unlinked | — | — | not affected |

**`snatchit-web`'s Preview-targeted variables** (values shown only where they are public-class):

| Env id | Key | Targets now | Value |
|---|---|---|---|
| `uZFQ2V71TmlPwYyH` | `NEXT_PUBLIC_SUPABASE_URL` | preview **+ production** (one shared entry) | production project URL |
| `vGsy3JDH4VbsSDsI` | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | preview **+ production** (shared) | production anon key |
| `g1sXR4sgrlml3IHF` | `NEXT_PUBLIC_SITE_URL` | preview **+ production** (shared) | `https://snatchti.com`. Preview sign-up and reset emails and the Stripe return URL therefore point at the production site |
| `VyqS0isRNtsJkZZT` | `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | preview only | type *sensitive*, so the value is **unreadable**. **Whether it is `pk_test_` is UNVERIFIED** |
| `OVfpZfpUNduQeTZh` | `NEXT_PUBLIC_SENTRY_DSN` | preview + production | not database-related |

**`snatchit-admin`:** `NEXT_PUBLIC_SUPABASE_URL` (`cvjeZn6set15JAIE`) and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (`J8FLFxAVGXWTwqm1`) are single entries covering development, preview and production, all pointing at production.

**Existing preview deployments keep the production URL and key baked in at build time:**
- `snatchit-web`: **at least 100 READY** preview deployments (the API has more pages), across at least 12 branches, including 2 of the release branch.
- `snatchit-admin`: 2 READY previews.
- All are behind Vercel SSO: previews need a Vercel login, except on custom domains.
- A settings change does not alter them. Removing them is a deletion, which is **not proposed here** and would be the owner's separate decision.

## 2. Is there a suitable test database? **No. More setup is required.**

| Candidate | Verdict |
|---|---|
| `Snatch It` `hqycwntpfoztoinemqns` | Production. It is the thing to isolate from |
| `Pulse` `aihgejwdvkvngjwttxij` | INACTIVE, and a different product |
| **`snatchit-sandbox` `ofaidukbieeekqaboscm`** (its own org) | **Not suitable, as the owner cautioned.** It is the mobile acceptance sandbox, and every write to it is owner-authorized per window. Previews would write without control: sign-ups, favorites, bids. It holds objects under standing restrictions (the retained Line 3 proof files and Sandbox L7), the carried 72-hour auto-release tail, and fixtures whose state the device records depend on (S8only, D6, D7). |
| Supabase Branching (per-PR preview branches on production) | **Not recommended.** It needs the GitHub integration's branch configuration on the **production** project, the AUTODEPLOY-1 surface that is deliberately unbound (`git_branch ""`). It is also billed per branch and replays the whole chain for each PR. |

**Proposed target (phase 2, after approval):** a new, dedicated Supabase project, e.g. `snatchit-web-preview`, **outside the production org**.
- **Cost:** in the production org (Pro plan) a new project is **$10/month** (Supabase cost query). The sandbox org's plan and cost were not readable from here.
- **Schema:** built from the release branch's migrations with the pinned CLI 2.115.0, the same replay CI proves.
- **Data:** synthetic seed data only. **No copy of production data.**
- **Auth:** the new project's Site URL and redirect allow-list are set for the preview host. That is a Supabase auth/URL configuration, a stop-and-ask item, on the new project only.
- **No edge functions or Stripe secrets at first,** so checkout in previews does not work. That is acceptable for previews.
- Creating the project, applying its schema, and the auth settings each need the owner's approval.

**Phase-2 Vercel change (Preview-only; production values untouched):** in `snatchit-web`, split each shared entry.
- Keep the existing entry with **its value unchanged**, targeting **production only**.
- Add a new Preview-only entry pointing at the isolated project.

| Key | Existing entry becomes | New Preview-only entry |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `uZFQ…` → `[production]`, same value | isolated project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `vGsy…` → `[production]`, same value | isolated project anon key |
| `NEXT_PUBLIC_SITE_URL` | `g1sX…` → `[production]`, same value | a preview host, so auth and return links stop pointing at `snatchti.com` |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | preview only: **owner confirms in the dashboard that it is `pk_test_`** | — |

- ~~`snatchit-admin`: the same split for Preview only.~~ **Replaced by D's correction (admin lane), approved and APPLIED 2026-09-18 (§6): FAIL CLOSED, with no admin Preview entries at all.**
  - The console reads **four** keys, not two: URL, anon key, `NEXT_PUBLIC_SITE_URL` (required at boot in any production-mode build, previews included) and `NEXT_PUBLIC_ENV_LABEL`, the operator's red "production" badge.
  - `admin/src/lib/env.ts` at `ab3e17f` checks that badge **only** when `NEXT_PUBLIC_VERCEL_ENV === "production"`, so previews were unguarded.
  - No isolated database has the `ops` schema, the roles or MFA-enrolled operators, so an admin preview against one would be an empty shell.
- New previews only; existing deployments are unchanged (§1).

## 3. Interim: stop automatic previews now (the owner's fallback, because phase 2 needs setup)

~~**Safety property, from source:** `web/src/lib/env.ts` throws … A preview can fail to build, but it can never silently serve without a database.~~ **CORRECTED (owner, 2026-09-18): that is no fallback for `snatchit-web`.** Its Preview-scoped Supabase URL, anon key and site URL are still **present**. So a build that bypasses the ignore setting **succeeds and connects to production**. `env.ts` protects only when the variables are *missing*, which is true today for `snatchit-admin` (§6) but not for the website.

| Option | Mechanism | Effect | Assessment |
|---|---|---|---|
| **I1: the release branch only** (as the owner framed it) | `snatchit-web` ignored-build step: `if [ "$VERCEL_GIT_COMMIT_REF" = "release/production-gate-20260918" ]; then exit 0; else exit 1; fi` | pushes to the release branch build no preview | **Leaves every other branch's previews connected to production**, including #72–#76's own branches |
| **I2: every preview (A recommends)** | `snatchit-web` ignored-build step: `if [ "$VERCEL_ENV" = "production" ]; then exit 1; else exit 0; fi` | **no new preview builds on any branch.** Production builds proceed | Matches the decision for all previews. The same mechanism `snatchit-admin` already uses |
| I3: fail-closed alternative | remove `preview` from the three shared entries (values untouched) | preview builds **fail** at `env.ts` | Also isolates, but every PR shows a failed Vercel build and Vercel still spends build minutes |

**Semantics, per Vercel's documented behaviour (not tested here):** exit 0 skips the build, exit 1 builds. **I2 returns 1 for production**, so production deploys are unaffected.

**Precisely what I2 changes:** `commandForIgnoringBuildStep` is a project-level field, currently **null**. It is evaluated for every build, including production's, where it evaluates to "build". **No environment variable, domain, production branch or protection setting changes.**

## 4. Exact change: interim I2, `snatchit-web` only. **APPROVED AND APPLIED 2026-09-18T22:26:43Z (§6)**

```
PATCH /v9/projects/prj_UjnXiY7r3PV4NCMH70UpdWT9rvfL?teamId=team_rld7LG9DKzgaph97l4H4jl9d
{"commandForIgnoringBuildStep": "if [ \"$VERCEL_ENV\" = \"production\" ]; then exit 1; else exit 0; fi"}
```

- **Before:** `commandForIgnoringBuildStep: null`.
- **Rollback:** the same call with `null`.
- **Verification after applying (read-only):** re-read the project and confirm only that field changed:
  - production branch still `feature/web-accounts-foundation`;
  - the 5 env entries' ids, targets and types identical to §1;
  - `gitProviderOptions.createDeployments` still `enabled`.
  - The next push to any non-production branch shows the build **skipped by the ignored-build step**.
- **Not included:** `snatchit-admin`, whose new previews are already off; deletion of existing previews; any Supabase change.

## 5. PR #76 checks, separated

**Code checks: all pass.**
- `Typecheck / Lint / Unit tests`, `Migrations apply cleanly (fresh DB)`, `Deno type-check (edge functions)`, `Web build (Next.js)` and `Admin console (Next.js)` pass. They come from the branch-push CI run on the **same commit** `f3cff27` (04:20Z). `ci.yml` runs pull-request events only for PRs into `main`, and that is equally true of #72–#75.
- `Immutability + ordering` passes (the PR run, 22:11Z).
- `Supabase Preview` is skipped (no migrations; the integration is unbound).

**Deployment check: not a code result.**
- `Vercel – snatchit-web` failed with *"Deployment rate limited — retry in 24 hours"*. **No build was attempted.**
- Under the owner's decision a retry would create another production-connected preview, so **it will not be retried.** The check stays red until previews are isolated, or disabled by I2.
- The release branch has **no branch protection or rulesets**, so this check does not block a merge mechanically.

## 6. APPLIED 2026-09-18 — consolidated verification (A; D to review)

**Authority, owner directly to A:**
- *"Approve the interim change: stop all new snatchit-web preview builds, across all branches, while preserving production builds and settings."*
- *"remove Preview scope from the admin console's four relevant settings … while preserving Production and Development values and scopes exactly. Preserve the existing preview-build suppression."*

### 6.1 Checked before applying
- **Vercel docs, current:**
  - *Project settings → Ignored Build Step*, last updated 2026-09-16: exit **0 → build aborted, deployment `CANCELED`**; exit **1 → build continues**. The command "can access all System Environment Variables".
  - The KB guide says `VERCEL_ENV` is available when "Automatically Expose System Environment Variables" is on, and gives essentially this command as its own example.
  - *vercel.json → `ignoreCommand`*: it **"overrides the Ignored Build Step in Project Settings"** for a given deployment.
  - *Ignore Build Step on redeploy*: a manual Redeploy can **untick** "Use project's Ignore Build Step".
  - **Canceled builds still count toward deployment quotas.**
- **The project:** `autoExposeSystemEnvs = true`.
- **Local test of the command, in `sh` and `bash`:**
  - `VERCEL_ENV=production` → exit 1, BUILD.
  - `preview` → exit 0, SKIP.
  - `development` → exit 0, SKIP.
  - **unset → exit 0, SKIP.** So production depends on `VERCEL_ENV` being exposed (see 6.4).

### 6.2 `snatchit-web`: one setting changed
- **Snapshot before:** 46 project fields, with no env values stored. Saved at `scratchpad/preview_iso/web_project_before.json` (mode 0600).
- **Change:** `commandForIgnoringBuildStep` went from `null` to `if [ "$VERCEL_ENV" = "production" ]; then exit 1; else exit 0; fi`.
- **Read back:**
  - Of all 46 fields, **only `commandForIgnoringBuildStep` and `updatedAt` differ.**
  - Production branch is still `feature/web-accounts-foundation`.
  - `gitProviderOptions`, `autoExposeSystemEnvs`, `ssoProtection`, framework, root directory and build, install and output settings are unchanged.
  - All 20 env entries are unchanged in id, target and type.
  - **0 deployments were created** since the change.
- **Rollback:** set the field back to `null`.

### 6.3 `snatchit-admin`: Preview scope removed from the four settings, fail closed
- **Capture before:** all 6 env entries, including values of the four public-class keys, saved at `scratchpad/preview_iso/admin_env_capture_before.json`. The file is 0600 in a 0700 directory, is not in the repo, and no value was printed.

| Entry | Before | After | Value |
|---|---|---|---|
| `cvjeZn6set15JAIE` `NEXT_PUBLIC_SUPABASE_URL` | development, preview, production | **development, production** | fingerprint unchanged |
| `J8FLFxAVGXWTwqm1` `NEXT_PUBLIC_SUPABASE_ANON_KEY` | development, preview, production | **development, production** | fingerprint unchanged |
| `GAFjr9xVsarpSWxC` `NEXT_PUBLIC_SITE_URL` | preview **only** | **removed** (the only way to remove its Preview scope) | captured for restore |
| `7Xkqe7M7QqoOlpUQ` `NEXT_PUBLIC_ENV_LABEL` | preview **only** (`staging`) | **removed** | captured for restore |
| `jx7ckWGTwRwZFif2` `NEXT_PUBLIC_SITE_URL` | production | production | untouched, fingerprint unchanged |
| `cafaHvuWsWvV3U72` `NEXT_PUBLIC_ENV_LABEL` | production | production | untouched, fingerprint unchanged |

- **Method:**
  - The two shared entries were changed with `PATCH` on `target` only.
  - The two Preview-only entries were removed with `vercel env rm <key> preview --yes`, run against the admin project. The generic `vercel api` DELETE asked for an override flag, which A did not use.
- **Verified:**
  - No entry targets Preview.
  - Every kept entry has the same value fingerprint, the same type, and its targets minus Preview.
  - The admin ignored-build step (`test "$VERCEL_GIT_COMMIT_SHA" != "ab3e17f…"`) and production branch `admin/operating-console` are unchanged.
  - **No deployment was triggered.** The newest admin deployment is still 2026-09-08.

### 6.4 What these settings do NOT cover. Neither safeguard is absolute
1. **A branch can override the suppression.** A `vercel.json`, `vercel.toml` or `vercel.ts` with `ignoreCommand` in a project's root directory (`web/`, `admin/`) overrides the project setting for that branch's deployments. D found none on any remote branch today.
2. **A manual Redeploy** with "Use project's Ignore Build Step" unticked builds anyway.
3. **CLI (`vercel deploy`), API-created deployments and deploy hooks:** the docs do not say whether the ignore step applies. **UNVERIFIED, so treat them as not covered.** No deploy hooks are configured today.
4. **For `snatchit-web`, any build that gets past suppression connects to PRODUCTION.** Its Preview variables still point there (the corrected claim in §3). Phase 2, or D's fail-closed layer for the website (removing Preview scope from its three shared entries, awaiting approval), would change that.
5. **For `snatchit-admin`,** a build that gets past suppression **fails at build.**
   - **D verified it:** a local `next build` at `ab3e17f` with `VERCEL_ENV=preview` and no Supabase, site or label variables exits 1 ("Missing required environment variables…"). A positive control with dummy values exits 0.
   - D also confirmed statically that **all 6 remote `admin/*` branches** have the same `env.ts` throw, imported by the layout and the middleware.
   - **Vercel's own build was not exercised.**
   - It stops holding if a Preview variable is added later, or if a deployment injects build env (see 9).
6. **Failed-check noise is still possible.** For admin, D confirmed the failure happens at build, not at request time, so it would show as a failed build.
   - Canceled (ignored) builds count toward the Hobby deployment quota, so **"Deployment rate limited" failures can still appear on commits.**
   - A build that gets past suppression and fails at `env.ts` would also show as a failed check.
   - How GitHub displays an ignored (canceled) build was not verified.
7. **If `autoExposeSystemEnvs` were turned off,** `VERCEL_ENV` would be unset and the web command would skip **production** builds too. That fails in the safe direction for data, but it would block web releases.
8. **Existing deployments are unaffected** (6.6).
9. **`vercel pull` / `vercel build` + `vercel deploy --prebuilt`** (D). The build runs **locally** with the pulled environment, so it skips **both** the ignore step and Preview scoping. `snatchit-admin`'s **Development** target still holds the production URL and anon key; that was preserved as the owner required. So `vercel pull --environment=development` puts production values on disk. For `snatchit-web`, the Preview values still point at production. **So neither change covers CLI deploys.**
10. **Local files uploaded by CLI deploys** (D). A CLI upload can carry gitignored files. The April admin previews' upload included `supabase/.temp/*`, and a `.env.local` would travel the same way, where Next loads it at build.
    - **By file name, neither April upload contained any `.env*` file.** The only dot-directory was `supabase/.temp`.
    - D reports that no admin worktree on this machine has production- or sandbox-ref lines in `.env.local`, or a `.vercel` link, so this route is not live from here today.
11. **Phase-2 note, defence in depth (D):** admin's CSP (`next.config.ts:4`, the same on all 7 refs) always allows the **production** host in `connect-src` and `img-src`. An admin preview pointed at an isolated database would still let the browser reach production. Phase 2 should derive that host from the configured URL.

### 6.5 The two existing admin previews (read-only: deployment metadata and uploaded source listing; no page loaded, no operator action, no data read)

| Deployment | Built | Source | vs approved console `ab3e17f` |
|---|---|---|---|
| `dpl_6Ax3FuXf2wuGeq3SXbrdMAftRXnH` | 2026-04-08T03:30Z via **CLI** | git meta sha `1cae7cba…` "Initial commit from Create Next App", ref `main`, **dirty working tree**. **That commit is not in any fetched ref** (A and D both checked the local object store after a fetch; a commit that was never pushed cannot be ruled out elsewhere) | **0** of its 46 source files byte-identical. It predates `ab3e17f` (2026-09-07) by five months |
| `dpl_V9Hhhvis8Dmpnsg6JFqVx8opVHut` | 2026-04-09T01:50Z via **CLI** | the same sha, ref and dirty tree | **0** of 55 byte-identical |

- **Unreviewed code, not the approved console.**
- **Badge:** neither has `src/lib/env.ts`, the file that implements the badge. Both environment-label entries were created 2026-09-08, after these builds. So they carry **no environment badge from the current mechanism**. **Whether they show any environment indication at all is UNVERIFIED**, because no page was rendered.
- **Database:** the admin Supabase URL variable (created 2026-03-20, Preview-scoped until today) existed before both builds. So they were **most likely built against production**. **UNVERIFIED**: the bundles were not inspected.
- The uploaded source also includes `supabase/.temp/*` CLI metadata files, which were not opened.
- **Reachability:** behind Vercel Authentication. The alias `snatchit-admin-gnvprod-5449-gnvprod-5449s-projects.vercel.app` points at one of them.

### 6.6 Existing previews: a reversible restriction before any deletion
- **Access today, verified:**
  - Both projects have Vercel Authentication on every deployment except custom domains.
  - The Vercel team is **Hobby with exactly 1 member (OWNER)**.
  - There are **0 protection-bypass tokens** on either project.
  - So only the owner's Vercel login can open any of the 100+ web previews or the 2 admin previews.
- **Recommended, reversible:**
  - **(a)** Keep that state, and create no share links or bypass tokens.
  - **(b)** Remove the stable aliases that point at old previews, starting with the admin alias above (`vercel alias rm`, restored with `vercel alias set`). The unique URLs stay behind the login.
- **Deletion**, or a retention policy that deletes, is irreversible and stays the owner's separate decision.

### 6.7 Stripe preview key: NOT determined; nothing was exposed
- The Preview entry `VyqS0isRNtsJkZZT`, last set 2026-08-04, is **Sensitive**, so its value is write-only.
- Git-built previews' output is not available through the files API ("File tree not found", 404).
- Loading a preview page would run code against production, so A did not.
- **Where the owner can check, without the value leaving the dashboard:** Vercel → `snatchit-web` → **Deployments** → any Preview built after 2026-08-04 (e.g. `dpl_41nEd3FG…`, 2026-09-18) → **Source** → **Output** → search the built JavaScript for `pk_test_` or `pk_live_`. The prefix alone answers it.
- *A has not verified that the Output view lists files for Git-built deployments.* If it does not, the definitive route is phase 2's re-setting of the Preview key to a known test key, which needs approval.

### 6.8 PR #76
- The **historical** `Vercel – snatchit-web` status on `f3cff27` is **"failure — Deployment rate limited — retry in 24 hours"** (04:20:22Z). It stays recorded as that.
- It is **not a code result**, and it was **not retried.** A retry would be a production-connected preview, and I2 would now cancel it anyway.
- All code checks pass (§5).
- PRs #72–#76 remain **unmerged**.

**D's review of §6 (2026-09-18), applied above:**
- **(a)** Admin fail-closed holds: verified by a local build with a positive control, and statically on all 7 refs.
- **(b)** Three routes added to §6.4 (items 9–11).
- **(c)** Wording tightened.
- D found nothing contradicting the §6.2/6.3 read-backs, §6.6 or §6.7, which D did not re-read. D read and changed nothing hosted.
