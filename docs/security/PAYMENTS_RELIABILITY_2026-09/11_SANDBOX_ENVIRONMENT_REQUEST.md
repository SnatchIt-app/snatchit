# Isolated Supabase + Stripe test environment — inventory, minimum setup, exact owner request

Status 2026-09-06: **no suitable non-production environment exists.** Nothing below was created.

## 1. What exists (read-only inspection via the Supabase management API, 2026-09-06)

| Project | Ref | Region | Status | Suitable as sandbox? |
|---|---|---|---|---|
| Snatch It | `hqycwntpfoztoinemqns` | us-west-2 | ACTIVE_HEALTHY | **NO — production.** Never a substitute. |
| Pulse | `aihgejwdvkvngjwttxij` | us-east-1 | INACTIVE (paused) | NO — a different product's project; restoring it costs the same compute as a new project and mixes data/config. |

Organization: `zcxpqolueooqkslolfrt` ("gnvprod@gmail.com's Org"). A new project in this org costs **$10 / month**
(management API `get_cost`, type `project`, recurrence monthly). Supabase Branching on the production project is
NOT an option here: AUTODEPLOY-1 (branching once bound git `main` to production; `git_branch` must stay empty) and the
standing rule "never treat the existing Supabase project as staging".

Stripe: no Stripe CLI is installed on this host and no test-mode key exists locally (`~/.config/stripe` absent; the repo
carries only `web/.env.example` names). The live Stripe account already has a **test-mode webhook endpoint of unknown
target** (`08_STRIPE_WEBHOOK_SUBSCRIPTION.md` says not to touch it), so test-mode traffic on that account would also be
delivered there. Use a **Stripe Sandbox** (Dashboard → Sandboxes → create; an isolated test account with its own keys
and endpoints, free) with Connect enabled and the platform profile completed — never the live account's shared test mode.

## 1a. Findings from the readiness review that shape the setup (`rc/R4_sandbox_readiness.md`)

- **G1 — money-out gates refuse test-mode rows.** `payments.stripe_livemode` is recorded from the PaymentIntent; the
  attempt ledger (`PAYMENT_NOT_LIVE`), the payout pre-flight, the unsettled work list and the expiry sweep all require
  `stripe_livemode = true`. Without a switch a sandbox proves checkout → settlement → webhooks → refunds → disputes but
  never a real `POST /v1/transfers`. The RC therefore carries a **sandbox-only switch**, default OFF everywhere:
  database GUC `app.allow_test_mode_money = on` (set with `ALTER DATABASE postgres SET …` on the sandbox only) and edge
  secret `ALLOW_TEST_MODE_MONEY=1` (sandbox project only). Production sets neither; the release checklist asserts both
  are absent. With the switch on, the payout leg runs against real Connect **test** transfers.
- **G2 — cron jobs hard-code the production host** (migrations 032/033/099). The sandbox must re-point the
  `enforce-transfer-expiry` job (`cron.alter_job`) and create the Vault secret `service_role_key`, or it never sweeps
  (and POSTs to production, rejected 401). Scripted in the harness.
- **G8 — Connect event routing.** `account.updated` / `payout.*` for Express accounts arrive only through a Connect-typed
  endpoint. Owner check before mirroring: `stripe webhook_endpoints retrieve we_…` on the live endpoint shows
  `"connect": true|false`; the sandbox creates the same shape.
- **G9 — no grace window** in the deletion sweep: seed obligations BEFORE requesting deletion in the sandbox.
- **G12 — build 13 cannot be re-pointed** (its production profile hard-codes the production URL). "Existing client"
  rows are replayed with the exact request shapes (curl) and, optionally, a dev build from the build-13 source SHA.

## 2. Minimum isolated setup (what the sandbox pass needs, nothing more)

1. **Supabase project** `snatchit-sandbox`, region us-west-2, smallest compute (Micro), in org `zcxpqolueooqkslolfrt`.
   Cost $10/month; delete/pause after the pass. Database password is the owner's — never shared with the assistant.
2. **Schema**: `supabase link --project-ref <sandbox-ref>` then `supabase db push --include-all` from the RC checkout
   (`release/payments-converged-rc`), which applies production's 124 versions plus the four `20260906*` — the same
   sequence the production-order rehearsal proves locally (51/51). Then `supabase/ci/parity_grants.sql` is NOT applied
   (Supabase provisions the anon/authenticated roles itself).
3. **Edge secrets** (owner sets them in Dashboard → Edge Functions → Secrets; the assistant never handles values):
   `STRIPE_SECRET_KEY` = the Stripe **Sandbox** secret key (`sk_test_…` of the sandbox, or a restricted key with:
   PaymentIntents write, Charges read, Refunds write, Transfers write, Connect Accounts write, Balance read, Events read);
   `STRIPE_WEBHOOK_SECRET` = signing secret of the endpoint created in step 5; `ALLOW_TEST_MODE_MONEY=1` (sandbox only);
   `INTERNAL_CRON_SECRET` = any random 32-byte hex; `STRIPE_CONNECT_REFRESH_URL` / `STRIPE_CONNECT_RETURN_URL` =
   `https://snatchitapp.com/payout-refresh` / `…/payout-return`; `SENTRY_ENV=sandbox` (DSN may stay unset);
   `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform; `EMAIL_ENABLED`
   unset; push/Twilio secrets unset (notify-* paths log and continue).
4. **Deploy the release edges plus the two the matrix needs** (`create-connect-account`, `send-push`) with
   `--no-verify-jwt` (no `supabase/config.toml` exists; confirm-payment, confirm-and-release, delete-account, stripe-webhook
   and enforce-transfer-expiry authenticate in code). Database side: `ALTER DATABASE postgres SET app.allow_test_mode_money = 'on'`;
   PostgREST exposed schemas must include `kernel`; `cron.alter_job` re-points `enforce-transfer-expiry` to the sandbox
   host and `vault.create_secret(<sandbox service_role key>, 'service_role_key')` gives it a bearer. All scripted in
   `scripts/sandbox/` except the two secret-bearing statements, which the owner runs in the SQL editor.
5. **Stripe test webhook endpoint** → `https://<sandbox-ref>.functions.supabase.co/stripe-webhook`, subscribed to the
   eleven events in `08_STRIPE_WEBHOOK_SUBSCRIPTION.md` (test mode has its own endpoint list; production untouched).
6. **Stripe CLI** on this host (`brew install stripe/stripe-cli/stripe`, then `stripe login` — interactive OAuth the owner
   completes in the browser; the CLI then acts in test mode under the owner's account). Used for `stripe trigger`,
   `stripe events resend`, `stripe payment_intents confirm` with test payment methods, `stripe transfers list`.
7. **Fixtures**: two auth users (buyer, seller) created in the sandbox via `supabase auth` admin API or the Dashboard;
   the seller's Connect **test** Express account (`stripe accounts create --type express` under the platform test
   key; `capabilities[transfers][requested]=true`) written to `profiles.stripe_connect_id`; one active buy-now
   listing. The harness `scripts/sandbox/` (prepared with this release) seeds these idempotently.
8. **Client**: build 13 is pinned to production; the "existing client" rows of the matrix are exercised by replaying
   its exact request shapes with `curl` against the sandbox edges (recorded in the harness), and — optionally — a dev
   build pointed at the sandbox via `EXPO_PUBLIC_SUPABASE_URL` / anon key for PaymentSheet 3DS on a simulator.

## 3. The exact minimum request (owner action; nothing else is needed from you)

1. **Approve $10/month** and say "create the sandbox project" — the assistant then creates `snatchit-sandbox`
   (Micro, us-west-2) via the management API with the cost confirmation, links the RC checkout, pushes the schema,
   deploys the edges and runs the non-secret provisioning. (Or create it yourself in the Dashboard and give the ref.)
2. In Stripe: create a **Sandbox** with Connect enabled (platform profile completed). Create its webhook endpoint
   (`scripts/sandbox/10_provision.sh` prints the exact `stripe webhook_endpoints create` command once the project URL
   is known — you run it after `stripe login`). Paste `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
   `ALLOW_TEST_MODE_MONEY=1` and the other §2.3 secrets into the sandbox project's Edge Function secrets; run the two
   Vault/GUC statements the script prints in the sandbox SQL editor. Confirm "secrets set" — no values in chat.
3. On this Mac: `brew install stripe/stripe-cli/stripe jq && stripe login` (browser approval; select the Sandbox).
4. Create three auth users (buyer, seller, second buyer) in the sandbox Dashboard with known passwords and tell me their
   emails (the harness signs them in to obtain JWTs; passwords go in a local untracked env file you create).

After (1)–(3) the sandbox pass runs without further owner action and never touches production or live mode.
