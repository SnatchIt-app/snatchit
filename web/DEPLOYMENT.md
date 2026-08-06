# Deployment contract — Snatch It web

## Vercel project settings

| Setting | Value | Why |
|---|---|---|
| Root Directory | `web` | The Next app is not at the repo root. |
| Production Branch | `feature/web-accounts-foundation` | Pushing to it **deploys to production immediately**. Use a child branch for anything not ready to be live. |
| Framework preset | Next.js (auto) | — |
| Node version | 22.x | Pinned by `engines` in `package.json`. |
| Package manager | npm | `package-lock.json` is the lockfile. |
| `enableAffectedProjectsDeployments` | on | Skips the build when a push touches no `web/` path — which is why SQL-only commits do not redeploy. |
| Deployment Protection | `all_except_custom_domains` | Previews are SSO-gated; the custom domain is public. |

## There is deliberately no `vercel.json`

Security headers (CSP, HSTS, X-Frame-Options, X-Content-Type-Options,
Referrer-Policy, Permissions-Policy) are set in `next.config.ts` via
`headers()`, so they live next to the CSP source list that generates them and
are covered by the same type-checking and review as the rest of the app.
Duplicating them into `vercel.json` would create two sources of truth for the
same headers, and the file's `builds`/`routes` keys can silently override the
Root Directory configured in the dashboard. Add one only if a genuinely
platform-level concern appears (cron, rewrites, per-route `maxDuration`).

Do **not** use `vercel deploy` or prebuilt CLI deployments — git push is the
only supported path, so the deployed commit is always traceable.

## Environment variables

See `.env.example` for the full contract. The two Supabase variables are
required: `src/lib/env.ts` throws at module load in production if either is
missing, which fails the build rather than serving fixture listings as if they
were real inventory.

## Pre-promotion checklist

Run from `web/`:

```
npx tsc --noEmit -p tsconfig.json     # must be clean
npx vitest run                        # must be green
npx next build                        # must succeed
```

Then fast-forward the production branch. Never force-push it.

Never run `next build` while `next dev` is running against the same directory —
they contend over `.next/` and the dev server ends up serving a broken tree.

## Rollback

Redeploy the previous deployment from the Vercel dashboard (instant, no
rebuild). For a database change, apply the matching file in
`supabase/rollbacks/` — every migration has one. Where ordering matters the
rollback file says so in its header; `064` in particular requires rolling the
`stripe-webhook` edge function back to v38 **first**, or webhook processing
fails closed.
