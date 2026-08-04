# Web deployment (Vercel)

The Vercel project `snatchit-web` (team `gnvprod-5449s-projects`) builds **only
this `web/` directory**. The repo root is the Expo/React Native mobile app, so
the two ship on completely independent cadences out of one repository.

## Settings that must stay in sync with the repo

| Setting | Value | Why |
|---|---|---|
| Root Directory | `web` | The Next.js app lives here, not at the repo root. |
| Production Branch | `feature/web-accounts-foundation` | **The branch that actually contains `web/`.** See below. |
| Skip unchanged root directory | **on** (`enableAffectedProjectsDeployments`) | Commits that touch no `web/` file are skipped before a build machine is provisioned. |
| Framework | Next.js | |
| Install / Build | `npm install` / `npm run build` | Matches local; `web/` is self-contained (shared packages vendored as tarballs in `web/vendor/`). |
| Node | 24.x | |
| Deployment protection | SSO on all deployment URLs, **except** custom domains | Preview URLs require Vercel auth; `snatchti.com` is public. |

### Why Production Branch is not `main`

`web/` has never been merged into `main` — `main` carries the mobile app, which
has been frozen for App Store review. With Production Branch set to `main`,
every mobile/docs commit triggered a Production build that failed immediately
with:

```
The specified Root Directory "web" does not exist. Please update your Project Settings.
```

16 consecutive Production deployments failed this way, and `snatchti.com` was
kept alive only by manually promoting feature-branch Preview builds. Pointing
Production Branch at the branch that actually contains `web/` makes the config
match reality: pushes to that branch deploy to `snatchti.com` from Git, and
`main` pushes are skipped rather than failed.

**Follow-up worth doing:** consolidate — either merge the web app into `main`
once mobile is out of review, or split `web/` into its own repository. Either
removes the branch/directory mismatch permanently. Until then, do not point
Production Branch back at a branch without a `web/` directory.

## Environment variables

`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
`NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` — all four must
exist in **both** Production and Preview. Missing `NEXT_PUBLIC_*` vars in the
Preview scope caused an earlier round of Preview build failures.

Do **not** pin an env var to a specific git branch: Vercel refuses to set a
branch as Production Branch while any env var is scoped to it
(`branch_used_for_env_variable`). Publishable/anon keys only — no secret ever
belongs in a `NEXT_PUBLIC_*` var.

## Deploying

Push to the Production Branch. Do not use `vercel deploy` or prebuilt CLI
deployments; Git is the only deployment path, so what is live always
corresponds to a commit.
