# Branch topology

Consolidated 2026-08-06. Tag `consolidated/pre-cleanup-2026-08-06` marks the
commit where a single branch first held the mobile app, the web app, all
migrations, the deployed edge functions and the shared packages together.

## Long-lived

### `main` — the source of truth
Everything: `app/` + `src/` (Expo mobile), `web/` (Next.js), `packages/`
(shared, vendored into web as tarballs), `supabase/` (migrations, rollbacks,
edge functions).

Kept as one repo on purpose. Migrations and edge functions are consumed by
**both** clients, so splitting web into its own repo would fracture them, and
two permanent branches is exactly the arrangement that produced the drift this
consolidation cleaned up: `main` had the newest edge functions but not the
migrations defining the RPCs they call, while the web branch had the migrations
but pre-July functions. Neither was self-consistent.

### `feature/web-accounts-foundation` — Vercel production branch
Currently identical to `main`. Vercel's Production Branch setting still points
here, so **pushing to it deploys snatchti.com immediately**.

The name is a leftover from when it was a feature branch. The intended end
state is to repoint Vercel's Production Branch to `main` (a dashboard change)
and retire this. Until then keep the two in lockstep — never let this branch
lead or lag `main`.

## Retained, superseded — safe to delete once you accept the loss of their SHAs

Both are content-complete in `main`; only their commit objects are unique, so
they are kept rather than deleted.

### `fix/edge-transfer-rpcs` (2 unique commits)
Was the deployed source for `stripe-webhook` and `create-connect-account`
during the security work. Its content is byte-identical to `main`'s
`supabase/functions/` — verified line-for-line (902 / 370 / 632 / 926).

### `mobile/profile-rpc-compat` (3 unique commits)
Duplicate work. The web line had already made the same migration-043 compat
changes (`a860505`, `d28a0f8`); the only difference is line-wrapping of the
same `.rpc('get_my_profile').returns<MyProfileRPC[]>().maybeSingle()` chain and
import ordering.

## Deleted 2026-08-06 — all tips proven reachable from `main` first

`feature/web-transfers` (7a7e967) · `feature/web-seller-management` (be51219) ·
`feature/web-brand-alignment` (8c96916) · `feature/web-platform-foundation`
(9c01fd9) · `feat/risk-payouts-allin-pricing` (6219fa4)

## Releases

- **Web** — push to the Vercel production branch. See `web/DEPLOYMENT.md`.
- **Mobile** — cut from a tag, built via EAS (`eas.json` uses
  `appVersionSource: remote`, so the real build number lives on EAS, not
  `app.json`). Tag pattern `mobile/v<version>-build<n>-<purpose>`.
  Latest: `mobile/v1.0-build9-apple-review` (the repo tag lags; App Store
  metadata records Build 13 as the current binary).

## Rules

- Never force-push `main` or the production branch.
- Migrations are append-only. `supabase/migrations-pending/` and
  `supabase/one-off/` sit outside every replay path on purpose — read their
  READMEs before moving anything into `supabase/migrations/`.
