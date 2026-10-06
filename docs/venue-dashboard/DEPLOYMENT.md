# Venue dashboard demo — deployment record

| | |
|---|---|
| **URL** | **https://snatchit-venue-demo.vercel.app** |
| **Deployed commit** | `512e01e3a4f2eebdb8446c2f0c6e278fa8304e06` on `venue/demo-integration` |
| Immutable deployment URL | `https://snatchit-venue-demo-6d3o29igc-gnvprod-5449s-projects.vercel.app` |
| Vercel project | `snatchit-venue-demo`, scope `gnvprod-5449s-projects` |
| Deployed | 2026-10-06 |
| Project root | `venue/` |
| Framework | Next.js, declared in `venue/vercel.json` |

## Access

**Vercel Authentication is enabled on every deployment of this project**
(`ssoProtection.deploymentType = "all"`), so the URL asks whoever opens it to sign in to
Vercel first. Verified: an unauthenticated request to both the alias and the immutable
deployment URL answers `302` to the Vercel sign-in page.

- **As the account owner you can open it directly** — you are already signed in to Vercel as
  this account, so the sign-in step passes through.
- **Anyone else — a venue, an investor — cannot open it as it stands.** Letting them in is a
  decision, not a default, so it has not been made here. The options, when you want one:
  1. invite them to the Vercel team (they get an account and the URL works);
  2. turn on a shareable link for the deployment in the Vercel dashboard;
  3. switch the project to public and accept that anyone with the link can read it.
  (3) is the simplest for a demo and carries no credential risk — the build has no Supabase
  URL, no key, and a self-only CSP — but it is still a public page with Snatch It branding on
  it, so it is yours to decide.

## Why it is not Git-connected

The Vercel API token available to this session can read projects under this team but cannot
create one (`403: Trying to access resource under scope "gnvprod-5449s-projects". You must
re-authenticate to this scope`). The project was therefore created and deployed with the
locally authenticated Vercel CLI, which uploads the build from `venue/`. Consequences:

- Pushing to `venue/demo-integration` does **not** redeploy. Each update is an explicit
  `vercel deploy --prod` from `venue/`, and this record names the commit that is actually
  live.
- Branch-scoped Preview environment variables cannot be set (the API refuses them without a
  connected repository). `NEXT_PUBLIC_VENUE_DATA_SOURCE=fixtures` is set on **Production** and
  **Development**; the Preview scope is empty.
- That last point is safe rather than merely unlikely: `lib/env.ts` resolves anything other
  than the literal `database` to `fixtures`, so a missing variable means fixtures, and the
  project has no `NEXT_PUBLIC_SUPABASE_URL` or key in any scope for database mode to use.

Connecting the repository later (dashboard → Project → Git) would give push-to-deploy. If you
do, set the ignored-build-step command so only this branch builds, otherwise every push to
`snatchit` by any session starts a build here.

## What is deployed

Verified against the live URL on 2026-10-06, through a temporary automation-bypass key that
was **revoked immediately afterwards** (confirmed: 0 keys remaining, unauthenticated requests
back to `302`):

| Check | Result |
|---|---|
| `/`, the Tonight overview, and the door screen | `200` |
| "Demo — sample data" strip, with its consequence sentence | present on every page checked |
| Tonight overview is live | "What needs you", "scanners are out of sync", "People inside", "Counted at this moment" all render |
| Database mode | absent — no "Database (…)" banner |
| Raw backend identifier in a heading | absent |
| The string `supabase` anywhere in the served HTML | **0 occurrences** |
| Response headers | self-only CSP with no `connect-src` for Supabase or Stripe; `X-Robots-Tag: noindex, nofollow` |

Nothing in Snatch It production changed to produce this. No migration was applied, no
production database was read, and the `snatchit-web` and `snatchit-admin` Vercel projects were
not touched.
