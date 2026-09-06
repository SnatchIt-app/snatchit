# ops-refund-execute

The money leg of an **approved** admin-console refund
(`docs/admin-console/DESIGN_AND_EXECUTION_PLAN.md` §2 decision 8).

`ops.execute_action('refund_execute', …)` → second-founder approval →
`ops.action_dispatch` leaves the action in `processing` with
`result = {handoff:'ops-refund-execute', stripe_payment_intent_id, amount_cents}`.
Nothing in Postgres talks to Stripe. This function is the handoff target: it
re-verifies the caller and the action, issues `POST /v1/refunds` under the
deterministic idempotency key `ops_action_<action_id>`, and reports back
through `ops.record_action_outcome` (service_role only).

## Contract

`POST` with `Authorization: Bearer <founder JWT>` and body `{ "action_id": "<uuid>" }`.

`action_id` is the **only** accepted field. A body that names a payment,
PaymentIntent, charge, amount, currency, refund or destination is refused with
`400 client_supplied_payment_reference`; any other extra field is
`400 unexpected_field`. The payment, PI, amount and reason are read from
`ops.action` / `public.payments` inside the database.

Gate order (fail closed at every step):

1. `auth.getUser(token)` via the service client — `401` if not a live session.
2. `ops.whoami()` executed **as the caller** (anon key + caller `Authorization`
   header) — must return `role = platform_admin` **and** `aal = aal2`, and its
   `user_id` must equal the verified token's user; otherwise `403`.
3. `check_rate_limit(user, 'ops-refund-execute', 10, 60s)` — `429` on limit
   **or** limiter error.
4. `ops.action` must be `action_type = refund_execute`, `subject_kind = payment`,
   `state ∈ {processing, succeeded_at_provider, unknown}` (retries allowed) and
   have an `ops.approval` row in state `approved`; otherwise `409` with a
   precise `error` code (`not_approved`, `not_executable`, `already_succeeded`,
   `wrong_action_type`, `bad_subject`, `action_not_found`).
5. `public.payments` (by `action.subject_id`) must be `status = succeeded`
   with a `pi_…` id and `stripe_livemode` consistent with the mode of
   `STRIPE_SECRET_KEY` (`sk_live_`/`rk_live_` ⇢ `true`, `sk_test_`/`rk_test_` ⇢
   `false`; `null` is **not actionable**). Cross-mode / unclassified rows are
   recorded `failed` and paged (`422`). `status = refunded` is an idempotent
   success: outcome `succeeded` with `note: already refunded locally`, `200`.

Then, and only then: `record_action_outcome(processing, {stripe_request_started_at})`
→ `POST /v1/refunds` with

- `payment_intent`
- `amount` only when `action.result.amount_cents` is a positive integer strictly
  less than `payments.total` (otherwise omitted = full refund)
- `reason` = `action.params.reason_code` if it is one of
  `duplicate | fraudulent | requested_by_customer`, else `requested_by_customer`
- `metadata[ops_action_id]`, `metadata[payment_id]`, `metadata[source]=ops-refund-execute`
- `Idempotency-Key: ops_action_<action_id>` — identical on every retry, so a
  retry can only replay the same Stripe refund, never create a second one.

## Outcome mapping

| Stripe result | `ops.action.state` | HTTP | Notes |
|---|---|---|---|
| 2xx | `succeeded_at_provider` | 200 | `provider_ref` = `re_…`; result `{stripe_refund_id, refund_status, amount, currency}` |
| `charge_already_refunded` | `succeeded_at_provider` if `GET /v1/refunds?payment_intent=…` lists a refund (ours preferred), else `failed` | 200 / 422 | money is already back |
| other definite 4xx (`idempotency_error`, `charge_disputed`, `resource_missing`, invalid request) | `failed` | 422 | `error` = Stripe code + message; never the key |
| transport error, 5xx, `api_error`, 429, 409 `idempotency_key_in_use`, `balance_insufficient` | `succeeded_at_provider` if a listed refund carries `metadata.ops_action_id = action_id`, else `unknown` | 200 / 502 | `unknown` is shown as unresolved in the console; a founder may retry |
| payment already `refunded` locally | `succeeded` | 200 | nothing sent to Stripe |

**This function never writes `public.payments`.** `payments.status → refunded`
(and `stripe_refund_id`) is set by the existing `charge.refunded` handler in
`stripe-webhook/index.ts`, exactly as for a Dashboard refund. The action
therefore rests at `succeeded_at_provider` until the webhook lands; the
`reconciliation_mismatch` / `refund_failed` detectors (migration 117) track
the gap. `failed` is terminal (`record_action_outcome` sets `completed_at`);
a new action is required. `unknown` and `succeeded_at_provider` are retryable.

If `record_action_outcome` itself fails **after** Stripe answered, the function
returns `500 outcome_unrecordable` **with `provider_ref`** in the body and pages
Sentry with the ref — the money moved and the ledger did not follow.

Response body: `{ action_id, state, provider_ref?, message }`; error paths use
`{ error, detail | message }`.

## Secrets (names only; values live in Supabase secrets)

- `STRIPE_SECRET_KEY` — used by `_shared/stripe.ts`; this function reads it
  only to derive live/test from the prefix. Never logged or returned.
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- optional `SENTRY_SERVER_DSN` (shared), optional `OPS_CONSOLE_ORIGIN` (CORS
  for a browser-originated call; unset = no CORS headers, server-to-server only).

## `verify_jwt`

**Leave ON** (the default). The caller is always a Supabase Auth user JWT, so
the gateway check is a free first filter; the function then performs its own
`getUser` + `ops.whoami()` gate regardless. Do **not** deploy with
`--no-verify-jwt` — unlike `stripe-webhook`, there is no signature scheme here
to compensate.

## Deploy (owner step — not run by the author of this file)

```
supabase functions deploy ops-refund-execute --project-ref hqycwntpfoztoinemqns
```

Preconditions, in order:

1. Migration `115_ops_console_foundation.sql` applied.
2. `ops` added to the project's PostgREST exposed schemas (Dashboard → API →
   Exposed schemas; same owner step as `kernel`), or every `.schema('ops')`
   call 404s.
3. `service_role` can read the two `ops` tables this function loads. Migration
   115 grants `usage on schema ops to service_role` but no table privileges,
   and the project's default privileges (verified live: `pg_default_acl`) cover
   only `public` and `storage`. Until a migration adds
   `grant select on ops.action, ops.approval to service_role;` the function
   answers `500 action_unreadable` before touching Stripe (fail closed).

## Enablement

The action is shipped **disabled**: `ops.action_dispatch` rejects
`refund_execute` with `reject_reason = disabled` while
`ops.setting('refund_execute_enabled') = false`. After the deploy above
succeeds and a smoke call returns `403`/`409` (not `404`/`500`), flip the flag
**from the console** via a `setting_set` action
(`subject_ref = 'refund_execute_enabled'`, `params = {"value": true}`), which
is audited like every other action. Flip it back the same way to pause.

## Retry semantics for operators

- `unknown` → the console shows the action unresolved. Retry from the console:
  same `action_id`, same idempotency key, so Stripe returns the original refund
  if it was created, or creates it once if it was not.
- `succeeded_at_provider` for a long time with the payment still `succeeded`
  → the webhook has not landed; check `stripe_webhook_events`, or resend from
  the Stripe Dashboard. Calling this function again is harmless (replay).
- `failed` → read `ops.action.error`; fix the cause (e.g. dispute, wrong
  amount) and raise a **new** action.

## Tests

Pure logic lives in `classify.ts` (no Deno globals) and is covered by
`tests/ops-refund-classify.test.ts` (`npm test -- tests/ops-refund-classify.test.ts`
at the repo root). Type-check the edge with
`deno check supabase/functions/ops-refund-execute/index.ts`.
