# Operating console — setup guide

## Layout

```
admin/                      Next.js 16 app (Vercel project snatchit-admin, Root Directory = admin)
  src/proxy.ts              session refresh + aal2 gate on every route
  src/lib/ops.ts            the only data path: ops.* RPCs with the founder's JWT
  src/lib/actions.ts        server actions → ops.execute_action / ops.approve_action
  scripts/                  Docker-free local harness (PostgREST + auth stub + fixtures)
supabase/migrations/115..118_ops_console_*.sql   schema `ops` (tables, read API, automation, corrections)
supabase/migrations/119_listing_block_insert_guard.sql   public listing guard (Gate-2 +1 fn/+1 trigger)
supabase/rollbacks/115..119_*                    mechanical reversals (rehearsal DBs only)
supabase/tests/181..185_*                        pgTAP (128 + 45 + 65 + 90 + 24 assertions)
supabase/functions/ops-refund-execute/           refund executor: handler.ts (Node-testable) + Deno index.ts (not deployed)
tests/ops-refund-{handler,classify}.test.ts      root vitest, 105 handler/classifier cases
docs/admin-console/                              this folder
```

## Environment (no secrets)

`admin/.env.example` is the contract. Four public-class variables:

| Name | Purpose |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | publishable key (same trust class as the mobile bundle) |
| `NEXT_PUBLIC_SITE_URL` | this deployment's origin (auth redirects) |
| `NEXT_PUBLIC_ENV_LABEL` | `production` / `staging` / `local` — header badge; production builds refuse any other label |

There is deliberately **no** service-role variable. `admin/src/lib/env.ts` fails
the build/boot in production when the four are missing or malformed.

## Local development (no Docker)

Prerequisites: Homebrew PostgreSQL 17 running on 127.0.0.1:5432 with pgTAP,
PostgREST 16 (`brew install postgrest`), Node 22+.

```bash
# 1. replay the migration chain (incl. 115–117) into a rehearsal database
export PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH
./scripts/rehearsal_reset.sh snatchit_rehearsal_admin

# 2. seed synthetic fixtures + start PostgREST (:3201) and the auth stub (:3202)
cd admin && npm install
bash scripts/local-stack.sh start        # runs scripts/fixtures.sql, exposes public,kernel,ops
bash scripts/local-stack.sh status

# 3. run the console
cp .env.local.example-harness .env.local
npm run dev                              # http://localhost:3200
```

Synthetic accounts (password `harness-pass-123`, MFA code `123456`):
`founder.a@example.test` (operator, must enrol MFA), `founder.b@example.test`
(operator, already aal2), `support@example.test` (not an operator → `/denied`),
`buyer1@example.test`. Fidelity limits are listed in `admin/scripts/README.md`
(no real GoTrue, no Stripe, cron/net are inert stand-ins — run detectors by hand
with `select ops.run_all_detectors();`).

## Checks

```bash
cd admin && npm run typecheck && npm run lint && npm test && npm run build
./scripts/rehearsal_test.sh snatchit_rehearsal_admin supabase/tests/000_helpers.sql \
  supabase/tests/181_ops_console_foundation.sql supabase/tests/182_ops_console_read_api.sql \
  supabase/tests/183_ops_console_automation.sql supabase/tests/184_ops_console_corrections.sql \
  supabase/tests/185_listing_block_insert_guard.sql
npm test -- tests/ops-refund-handler.test.ts tests/ops-refund-classify.test.ts   # repo root
# exact production shape (110–114 omitted):
REHEARSAL_UPTO=109_terminal_session_manifest_forceclose.sql ./scripts/rehearsal_reset.sh snatchit_rehears_prodpath
# then apply the five 2026* files and 115→119 with psql, and rerun the tests above
```
CI: job `Admin console (Next.js)` (non-required); the `db` job's pgTAP step picks
up 181–185 automatically; the `deno-check` job type-checks `ops-refund-execute`;
the root quality job runs the handler tests. What CI does NOT cover: real
GoTrue MFA, real Storage signing, live Stripe (see FINAL_REPORT §4).

## Production / staging

See `RUNBOOK.md` (apply order, PostgREST exposure of `ops`, Vercel cut-over,
rollback) and `FOUNDER_BOOTSTRAP.md` (who can sign in). Production and staging
are distinguished by `NEXT_PUBLIC_ENV_LABEL` and by the Supabase URL; there is
no staging Supabase project today (the single "main" branch record is
production), so a staging console would need its own project.
