# Web preview isolation — plan (A, 2026-09-18). NOTHING APPLIED

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

No setting was changed.

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

- `snatchit-admin`: the same split for Preview only. Development and production stay as they are.
- New previews only; existing deployments are unchanged (§1).

## 3. Interim: stop automatic previews now (the owner's fallback, because phase 2 needs setup)

**Safety property, from source:** `web/src/lib/env.ts` throws at module load in any `NODE_ENV=production` build that lacks the Supabase URL, anon key or site URL. A preview can fail to build, but it can never silently serve without a database.

| Option | Mechanism | Effect | Assessment |
|---|---|---|---|
| **I1: the release branch only** (as the owner framed it) | `snatchit-web` ignored-build step: `if [ "$VERCEL_GIT_COMMIT_REF" = "release/production-gate-20260918" ]; then exit 0; else exit 1; fi` | pushes to the release branch build no preview | **Leaves every other branch's previews connected to production**, including #72–#76's own branches |
| **I2: every preview (A recommends)** | `snatchit-web` ignored-build step: `if [ "$VERCEL_ENV" = "production" ]; then exit 1; else exit 0; fi` | **no new preview builds on any branch.** Production builds proceed | Matches the decision for all previews. The same mechanism `snatchit-admin` already uses |
| I3: fail-closed alternative | remove `preview` from the three shared entries (values untouched) | preview builds **fail** at `env.ts` | Also isolates, but every PR shows a failed Vercel build and Vercel still spends build minutes |

**Semantics, per Vercel's documented behaviour (not tested here):** exit 0 skips the build, exit 1 builds. **I2 returns 1 for production**, so production deploys are unaffected.

**Precisely what I2 changes:** `commandForIgnoringBuildStep` is a project-level field, currently **null**. It is evaluated for every build, including production's, where it evaluates to "build". **No environment variable, domain, production branch or protection setting changes.**

## 4. Exact proposed change: interim I2, `snatchit-web` only. Awaiting approval; NOT applied

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
