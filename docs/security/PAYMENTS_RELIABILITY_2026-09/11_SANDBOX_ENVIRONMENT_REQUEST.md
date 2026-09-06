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
carries only `web/.env.example` names). The live Stripe account's **test mode** is free and already exists; Connect
must be usable in test mode (Express test accounts are created by the API with no real onboarding).

## 2. Minimum isolated setup (what the sandbox pass needs, nothing more)

1. **Supabase project** `snatchit-sandbox`, region us-west-2, smallest compute (Micro), in org `zcxpqolueooqkslolfrt`.
   Cost $10/month; delete/pause after the pass. Database password is the owner's — never shared with the assistant.
2. **Schema**: `supabase link --project-ref <sandbox-ref>` then `supabase db push --include-all` from the RC checkout
   (`release/payments-converged-rc`), which applies production's 124 versions plus the four `20260906*` — the same
   sequence the production-order rehearsal proves locally (51/51). Then `supabase/ci/parity_grants.sql` is NOT applied
   (Supabase provisions the anon/authenticated roles itself).
3. **Edge secrets** (owner sets them in Dashboard → Edge Functions → Secrets; the assistant never handles values):
   `STRIPE_SECRET_KEY` = a **test-mode restricted key** `rk_test_…` with: PaymentIntents write, Charges read, Refunds
   write, Transfers write, Connect Accounts write, Balance read, Events read, Webhook Endpoints read;
   `STRIPE_WEBHOOK_SECRET` = signing secret of the test endpoint created in step 5; `SENTRY_DSN` may stay unset;
   `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform;
   push/Twilio secrets unset (notify-* paths log and continue).
4. **Deploy the seven release edges** to the sandbox: `supabase functions deploy <fn> --project-ref <sandbox-ref>` for
   create-payment-intent, confirm-payment, stripe-webhook, enforce-transfer-expiry, confirm-and-release, delete-account,
   notify-report. Cron: the sandbox's `cron.job` rows come from the migrations; they call the sandbox's own URLs only
   if the `app.settings.*` GUCs point at it — verify with `select jobname, command from cron.job`.
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
   (Micro, us-west-2) via the management API with the cost confirmation, links the RC checkout, pushes the schema and
   deploys the seven edges. (Or create it yourself in the Dashboard and give the project ref.)
2. In Stripe **test mode**: create the restricted key described in §2.3 and the webhook endpoint of §2.5 (once the
   project exists and the URL is known), and paste both secrets into the sandbox project's Edge Function secrets.
   Confirm "secrets set" — no values in chat.
3. On this Mac: `brew install stripe/stripe-cli/stripe && stripe login` (browser approval, test mode).

After (1)–(3) the sandbox pass runs without further owner action and never touches production or live mode.
