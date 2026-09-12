# Admin console — local integration harness (TEST HARNESS, synthetic)

Docker-free way to run the admin console (`admin/`, `next dev --port 3200`)
against a **real PostgREST** over the **local rehearsal Postgres**, with a
**stub** standing in for the Supabase Auth (GoTrue) gateway.

```
Next.js admin :3200 ──► auth-stub.mjs :3202 ──┬─ /auth/v1/*  emulated GoTrue subset
                                              └─ /rest/v1/*  ──► PostgREST 16 :3201 ──► Postgres 17 (127.0.0.1:5432)
                                                                                         db: snatchit_rehearsal_admin
```

Everything here is labelled **TEST HARNESS**. It never touches staging or
production and refuses to run against anything that is not a loopback
PostgreSQL whose database name contains `rehears` (same preamble as
`scripts/rehearsal_reset.sh`: remote connection variables are unset first,
Supabase platform roles on the server abort, replicas abort).

## Files

| File | Purpose |
|---|---|
| `local-stack.sh` | start/stop/restart/reload/status/fixtures/env/logs. Pidfiles, logs and the generated `postgrest.conf` live in `scripts/local/state/` (gitignored). |
| `auth-stub.mjs` | Zero-dependency Node (>=22) server on :3202. Proxies `/rest/v1/*` to PostgREST; emulates the GoTrue endpoints supabase-js v2 / `@supabase/ssr` use. Also mints the API-key JWTs (`--mint anon`). |
| `fixtures.sql` | Idempotent synthetic data (`ON CONFLICT DO NOTHING`, fixed UUIDs). Creates the harness-only schema `ops_harness` (`accounts`, `factors`). Applied on every `start` unless `LOCAL_STACK_SKIP_FIXTURES=1`. |
| `../.env.local.example-harness` | Env values for the admin app. Copy to `admin/.env.local`. |

## Prerequisites (this machine already has them)

- Homebrew PostgreSQL 17 running on 127.0.0.1:5432, role `postgres` (trust on loopback).
- Rehearsal DB replayed through the migration chain:
  `PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH scripts/rehearsal_reset.sh snatchit_rehearsal_admin`
- `/opt/homebrew/bin/postgrest` (16.x), `node` >= 22, `curl`.

## Start / stop

```bash
admin/scripts/local-stack.sh start      # fixtures -> postgrest :3201 -> auth-stub :3202, prints env block
admin/scripts/local-stack.sh status
admin/scripts/local-stack.sh logs
admin/scripts/local-stack.sh reload     # regenerate postgrest.conf + SIGUSR2/SIGUSR1 (after a migration adds `ops`)
admin/scripts/local-stack.sh fixtures   # re-apply fixtures.sql only
admin/scripts/local-stack.sh stop
# or from admin/: npm run local:stack -- start
```

Then in `admin/`: `cp .env.local.example-harness .env.local && npm run dev`.

### PostgREST schemas (`ops` may not exist yet)

PostgREST 16 **refuses to load its schema cache when any schema in
`db-schemas` is missing** (verified: `Failed to load the schema cache …
schema "ops" does not exist`, every request 503). So `local-stack.sh` exposes
`public, kernel` and adds `ops` only if `select 1 from pg_namespace where
nspname='ops'` finds it at start time. Override with
`LOCAL_STACK_SCHEMAS="public, kernel, ops"`. After migration 115 creates `ops`
in the rehearsal DB run `local-stack.sh reload` (or `restart`).

PostgREST config that is generated (`scripts/local/state/postgrest.conf`):
`db-uri` as role `authenticator` (login role from `scripts/rehearsal_bootstrap.sql`;
the script sets a local-only password if it has none), `db-anon-role = anon`,
`jwt-secret = snatchit-local-harness-jwt-secret-0000000000`, `jwt-aud = authenticated`,
`server-port = 3201`, `db-pre-request` unset.

## Env for the admin app

```
NEXT_PUBLIC_SUPABASE_URL=http://localhost:3202
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1oYXJuZXNzIiwicmVmIjoibG9jYWwtaGFybmVzcyIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzU2MDAwMDAwLCJleHAiOjIwNzEzNjAwMDB9.SOC2vWZoCh6gM7wQqixH9h3ZL6kwzNxZOZTxKTdEO0M
```

The anon key is an HS256 JWT `{role:"anon"}` signed with the dev secret
(fixed `iat`, so the string is stable; `node admin/scripts/auth-stub.mjs --mint anon`
reproduces it, `--mint service_role` mints a harness service key for curl
experiments — the admin app must never receive one). No real Supabase key
exists anywhere in this harness.

## Synthetic logins (password for all: `harness-pass-123`, MFA code: `123456`)

| Email | user_id | Authority | AAL at login |
|---|---|---|---|
| `founder.a@example.test` | `f0000000-0000-4000-8000-0000000000a1` | `public.admin_users` (platform_admin) | `aal1`, no factor → exercises in-app TOTP enrolment |
| `founder.b@example.test` | `f0000000-0000-4000-8000-0000000000a2` | `public.admin_users` (platform_admin) | `aal2` (verified factor pre-seeded) |
| `support@example.test`   | `f0000000-0000-4000-8000-0000000000a3` | **none** (not in admin_users) | `aal2` — denied-path testing |
| `buyer1@example.test`    | `b0000000-0000-4000-8000-000000000001` | none | `aal1` |

Other fixture users (no login): `buyer2/3@example.test`, `seller1/2/3@example.test`
(`5e11e000-…-000000000001..3`; seller3 is `is_listing_blocked`).

### What the fixtures cover

15 listings (`11570000-…`): active auction with bids, reserved buy-now with a
pending payment, 11 sold, one `auction_status='cancelled'`, one reported
suspicious. 13 payments (`9a900000-…`, `pi_test_…`): 10 succeeded, 1 refunded,
1 pending, 1 failed. 11 transfers (`7a000000-…`):

| Transfer | State | Detector it should trip |
|---|---|---|
| `…0003` | pending, `expires_at` in 2h | transfer_deadline_soon |
| `…0004` | pending, `expires_at` 1h ago | transfer_overdue |
| `…0005` | seller_sent, `payout_review_status='manual_review'`, high | payout_review |
| `…0006` | seller_sent, `'held'`, `payout_hold_until` +2d | (held; auto-releases) |
| `…0007` | buyer_confirmed, `stripe_transfer_id='tr_test_000007'` | released (healthy) |
| `…0008` | buyer_confirmed 2h ago, no stripe_transfer_id | release_stuck |
| `…0009` | disputed (open, never_received) + Stripe dispute `needs_response`, evidence due +2d | dispute_open, dispute_evidence_due |
| `…0010` | disputed, resolved `resolved_buyer_refunded` 6h ago, payment still succeeded | refund_pending (`get_disputes_awaiting_refund` returns it) |
| `…0011` | expired, payment succeeded not refunded | refund_pending |
| `…0012` | auto_released 2h ago, no stripe_transfer_id | release_stuck |
| `…0013` | expired, payment refunded | healthy reference |

Plus: 2 `disputes` (`dp_test_…`), 3 pending + 1 dismissed `reports`, 4
`seller_flags` (valid `flag_type`s), 1 `dispute_resolutions`, 4
`payout_decisions`, 3 `stripe_webhook_events` (one unprocessed 2h old with
`last_error`, one `failed_at`), 3 `seller_risk_scores`.

Rows are inserted in their final state as `postgres` with no request claims,
which is the "direct admin connection" ALLOW path of the listings guards; the
transfer state guard only fires on UPDATE. The bypass GUCs
(`app.bypass_transfer_guard` / `app.bypass_listing_guard`) are still armed in
the transaction for parity with `supabase/tests`.

## Fidelity limits — read before trusting a result

- **Not GoTrue.** Only these endpoints exist: `POST /auth/v1/token?grant_type=password|refresh_token`,
  `GET|PUT(501) /auth/v1/user`, `POST /auth/v1/logout`, `GET /auth/v1/settings`,
  `GET /auth/v1/.well-known/jwks.json` (empty keys), `GET /auth/v1/health`,
  `GET|POST /auth/v1/factors`, `DELETE /auth/v1/factors/:id`,
  `POST /auth/v1/factors/:id/challenge|verify`, and a convenience
  `GET /auth/v1/authenticator-assurance-level`. No signup, magic link, OAuth,
  PKCE, password reset, admin API, storage, realtime, functions, graphql.
- **supabase-js compatibility, verified against the installed v2.115 source:**
  `getClaims()` sees `alg=HS256` and falls back to `getUser()` → `GET /auth/v1/user`
  (the JWKS is intentionally empty). `mfa.getAuthenticatorAssuranceLevel()` is
  computed client-side from the JWT `aal`/`amr` plus `user.factors[].status === 'verified'`
  from `/user`; `mfa.listFactors()` also reads `user.factors`. The stub returns
  exactly those shapes. Error bodies use the 2024-01-01 envelope
  (`{code, error_code, msg}` + `X-Supabase-Api-Version`), so `error.code` is populated.
- **MFA is fake.** Any challenge verifies with `123456`; the QR is a placeholder
  SVG; the secret is a constant. Verify mints an `aal2` token with
  `amr:[{method:"totp"},{method:"password"}]` on the same `session_id`.
  Founder B / support log in **directly at aal2** (fixture `aal`), which real
  GoTrue never does — use founder A to exercise the true enrol→challenge→verify path.
- **Sessions are stateless HS256 JWTs (TTL 3600s, `HARNESS_JWT_TTL`).** Logout
  revocation and pending challenges are in the stub's memory only: a stub
  restart forgets revocations (tokens stay valid until `exp`) and challenges.
  Refresh tokens are signed self-describing blobs; rotation does not invalidate
  the previous token.
- **Passwords are plain text** in `ops_harness.accounts`. Emails are `*.example.test`.
- **No Stripe, no edge functions, no cron execution, no notifications.** The
  rehearsal DB's `net.http_post`/`vault`/`cron.schedule` are inert stand-ins
  (see `scripts/rehearsal_bootstrap.sql` fidelity ledger), so triggers that
  would notify or post do nothing here.
- **RLS is real.** `authenticated` requests run under the real policies and
  grants of the rehearsal schema (e.g. founders see 0 `transfers` rows
  directly; `admin_users` is 403). Anything the console can read must come from
  the `ops.*` SECURITY DEFINER functions, exactly as in production.
- `authenticator` gets a **local-only password** (`harness-authenticator-local-only`);
  pg_hba is `trust` on loopback so it is cosmetic.

## Verifying by hand

```bash
ANON=$(cat admin/scripts/local/state/anon.jwt)
TOK=$(curl -s -X POST 'http://localhost:3202/auth/v1/token?grant_type=password' -H 'Content-Type: application/json' \
  -d '{"email":"founder.b@example.test","password":"harness-pass-123"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -s http://localhost:3202/auth/v1/user -H "apikey: $ANON" -H "Authorization: Bearer $TOK"
curl -s 'http://localhost:3202/rest/v1/listings?select=id&limit=1' -H "apikey: $ANON" -H "Authorization: Bearer $TOK"
curl -s -X POST http://localhost:3202/rest/v1/rpc/is_platform -H 'Content-Profile: kernel' -H 'Content-Type: application/json' \
  -H "apikey: $ANON" -H "Authorization: Bearer $TOK" -d '{"p_roles":["platform_admin"]}'     # -> true
```
