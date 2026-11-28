# ops-refund-execute

The money leg of an **approved** admin-console refund
(`docs/admin-console/DESIGN_AND_EXECUTION_PLAN.md` §2 decision 8).

`ops.execute_action('refund_execute', …)` → second-founder approval →
`ops.action_dispatch` leaves the action in `processing`. Nothing in Postgres
talks to Stripe. This function is the handoff target: it re-verifies the
caller, **claims** the action (`ops.executor_claim`, migration 118), issues
`POST /v1/refunds` under the deterministic idempotency key
`ops_action_<action_id>`, classifies the refund **object** Stripe returns, and
reports back through `ops.record_action_outcome` (service_role only).

## Layout

| File | Runs on | Purpose |
|---|---|---|
| `index.ts` | Deno (edge) | HTTP shell: auth, rate limit, real adapters (supabase-js RPCs, `_shared/stripe.ts`). No decisions. |
| `handler.ts` | Deno **and** Node | `runRefundExecution(input, deps)` — the flow: claim → list-before-POST → POST → classify object → record. Pure TS, no Deno globals. |
| `classify.ts` | Deno **and** Node | Pure decisions: request guard, idempotency key, mode boundary, request body, transport classification, **object** classification, identity validation. |

Tests: `tests/ops-refund-handler.test.ts` (flow, over fake adapters) and
`tests/ops-refund-classify.test.ts` (decisions). Both run in the root vitest
suite (`npm test`), on Node, with no Stripe or database.

## Contract

`POST` with `Authorization: Bearer <founder JWT>` and body `{ "action_id": "<uuid>" }`.

`action_id` is the **only** accepted field. A body that names a payment,
PaymentIntent, charge, amount, currency, refund or destination is refused with
`400 client_supplied_payment_reference`; any other extra field is
`400 unexpected_field`. Everything about the money comes out of
`ops.executor_claim` inside the database.

Gate order (fail closed at every step):

1. `auth.getUser(token)` via the service client — `401` if not a live session.
2. `ops.whoami()` executed **as the caller** (anon key + caller `Authorization`
   header) — must return `role = platform_admin` **and** `aal = aal2`, and its
   `user_id` must equal the verified token's user; otherwise `403`.
3. `check_rate_limit(user, 'ops-refund-execute', 10, 60s)` — `429` on limit
   **or** limiter error.
4. `ops.executor_claim(p_action_id, p_lease_seconds = 120)` (service_role) —
   in ONE transaction: action is `refund_execute`, state ∈ `{processing, unknown}`,
   `refund_execute_enabled` is true, the approval is `approved` and its hash
   still matches the action, and no live lease exists. Anything else is
   `409 {error:'claim_refused', reason, state?, claimed_until?}` with reason ∈
   `disabled | paused | not_found | wrong_type | terminal | not_executable |
   approval_missing | approval_stale | claim_busy | succeeded_at_provider |
   payment_missing | payment_not_refundable | already_refunded_locally` (any
   unlisted reason is still a 409). **No Stripe call is made on a refused
   claim.** `already_refunded_locally` is the one
   refusal that is a success: the webhook already settled the payment, the
   action is recorded `succeeded` (`note: already refunded locally`), `200`.

The enabled flag and the approval binding are therefore re-checked **at
execution and at every resume**, not only at dispatch; a flag flipped off or an
approval invalidated between approval and execution refuses the money leg.

### `executor_claim` payload the handler relies on

```
{ status:'claimed', action_id, payment_id, stripe_payment_intent_id,
  amount_cents, payment_total_cents, currency:'usd', reason_code,
  previously_sent:boolean, provider_ref:text|null, attempt:int,
  stripe_livemode?:boolean|null }
{ status:'refused', reason, state?, claimed_until?, detail? }
```

`payment_total_cents` (= `public.payments.total`) is **required**: it is what
the handler compares `amount_cents` against for the partial-refund guard. A
claim without it is `500 claim_invalid` and nothing is sent.

The handler validates the claimed payload again before acting (uuid action /
payment ids, `pi_…` shape, positive integer amounts, `usd`) and answers
`500 claim_invalid` — nothing sent — if it does not hold.

## Full refunds only

`amount_cents` **must equal** `payment_total_cents`. `executor_claim` rejects
partials server-side; the handler refuses again (`failed`,
`result.refused = partial_refund_unsupported`, `422`, nothing sent).

Why: the local model has no refunded-amount column. `payments.status` is the
whole ledger, and the `charge.refunded` webhook flips it to `refunded`
unconditionally — a partial refund would be recorded locally as a full one.
Until the model carries amounts, a partial is done from the Stripe Dashboard
under the SOP, never from here.

The request body sends `amount` **explicitly** (= the payment total) rather
than relying on Stripe's omit-means-full semantics: if the charge was partially
refunded by another route, omitting `amount` would refund only the remainder
and create a refund whose facts differ from the action. Sending the full
amount makes Stripe refuse (`amount_too_large` → `failed`) instead.

## State machine

```
                     claim refused ──────────────► (no change)          409
                     already_refunded_locally ───► succeeded            200
processing ── record processing {stripe_request_started_at, attempt}
           ── POST /v1/refunds  (Idempotency-Key ops_action_<id>, metadata.ops_action_id)
           ── classify the refund OBJECT (never the HTTP status):
                refund.status = succeeded ───────► succeeded_at_provider  200
                refund.status = pending ─────────► processing (in flight) 202
                refund.status = requires_action ─► processing {needs_action:true, next_action} 202
                refund.status = failed|canceled ─► failed {failure_reason} 422
                anything else / facts differ ───► unknown                502
           ── definite 4xx (invalid request, disputed, idempotency_error…) ► failed 422
           ── charge_already_refunded ► list; adopt OURS (validated) ► as object above
                                         nobody carries our metadata ► failed 422
           ── transport / 5xx / 429 / 409 in-use ► list; adopt OURS (validated) ► as object above
                                                    nothing / list failed ► unknown 502

succeeded_at_provider ── webhook charge.refunded sets payments.status = refunded
                      ── (detector, migration 117) ──────────────────► succeeded
processing (pending / requires_action) ── detector re-checks the refund at Stripe
```

`processing` after a `pending` / `requires_action` object is **not** success:
the console shows it in flight and the reconciliation detector re-checks the
provider. `failed` is terminal (`record_action_outcome` sets `completed_at`);
a new action is required. `unknown` is retryable.

**This function never writes `public.payments`.**

### Identity validation

Every refund object the executor acts on — the one it created **or** one it
adopts from `GET /v1/refunds` — must satisfy, or it is `unknown` with
`result.mismatch` and no `provider_ref` is recorded:

- `payment_intent` = the claimed PaymentIntent
- `amount` = `amount_cents`
- `currency` = `usd` (case-insensitive)
- `metadata.ops_action_id` = the action id

A refund created by another route (Dashboard, `refund-execute`) is never
adopted even when its facts coincide; the `charge.refunded` webhook settles
the local payment on its own and the next claim refuses
`already_refunded_locally`.

## Resume / retry semantics

- **Lease.** `executor_claim` holds a 120 s lease; a second call while the
  lease is live is refused `claim_busy` with no Stripe call. Concurrent
  requests therefore yield exactly one `POST`. A crashed executor frees the
  action by lease expiry.
- **Look before you POST.** When the claim says `previously_sent`, or carries a
  `provider_ref`, or `attempt > 1`, the handler lists refunds on the
  PaymentIntent **first** and adopts ours (validated) in whatever state it is:
  `succeeded` → `succeeded_at_provider`; `pending`/`requires_action` →
  `processing`; `failed`/`canceled` → `failed` (no second POST; a new action
  is required). Only when nothing carries our metadata does it POST again —
  under the same idempotency key, so Stripe replays or creates once.
- If the list itself fails on a resume, the outcome is `unknown` and **nothing
  is posted**: we do not send money we cannot see.
- If a `provider_ref` is recorded but Stripe does not list it on the intent,
  the outcome is `unknown` and nothing is posted (facts disagree).
- **Processing is recorded before the POST.** If that write fails (throws), no
  Stripe call is made (`500 outcome_unrecordable`). If it is refused (the
  action moved under us), nothing is sent (`409 outcome_refused`).
- **Outcome write after Stripe answered.** If it throws, the function returns
  `500 outcome_unrecorded` **with `provider_ref`** and pages; the next attempt
  reconciles by list — never a second POST. If the monotonic RPC refuses it
  (a terminal state already stands, or a different `provider_ref` is already
  recorded), the handler logs and returns `409 outcome_refused`; it never
  throws and never overrides the database.

### `record_action_outcome` payload the handler relies on

Arguments `(p_action_id, p_state, p_result, p_error, p_provider_ref)` with
`p_state` ∈ `processing | succeeded_at_provider | failed | unknown | succeeded`.
Return shapes consumed: `{status:'ok'}`, `{status:'idempotent_replay'}`
(treated as ok), `{status:'refused', reason, state?}` (log, no throw).
`p_result` written by this executor, by state:

- `processing` (before POST): `{stripe_request_started_at, attempt, partial:false}`
- `processing` (in flight): `{stripe_refund_id, refund_status, amount, currency, charge, payment_intent, provider_ref, needs_action, next_action?}`
- `succeeded_at_provider`: `{stripe_refund_id, refund_status, amount, currency, charge, payment_intent, adopted_existing_refund?, resolved_after?}`
- `failed`: `{failure_reason}` or `{stripe_error_class, stripe_error_code}` or `{refused:'partial_refund_unsupported', …}` or `{mode_check:'cross_mode'}`
- `unknown`: `{mismatch:{field:{expected,actual}}}` or `{stripe_error_class}` or `{reconcile:'list_failed'|'provider_ref_not_listed'}`
- `succeeded`: `{note:'already refunded locally'}`

## HTTP mapping

| Result | HTTP |
|---|---|
| `succeeded`, `succeeded_at_provider` | 200 |
| `processing` (pending / requires_action at Stripe) | 202 |
| `failed` | 422 |
| `unknown` | 502 |
| claim refused | 409 `{error:'claim_refused', reason}` |
| outcome refused by the monotonic RPC | 409 `{error:'outcome_refused', reason}` |
| processing write threw before the POST | 500 `outcome_unrecordable` (nothing sent) |
| outcome write threw after Stripe answered | 500 `outcome_unrecorded` + `provider_ref` |

Response body: `{ action_id, state, provider_ref?, message }`; error paths use
`{ error, reason | detail | message }`. Every message passes
`sanitizeErrorMessage` (Stripe keys and bearer tokens redacted, 500 chars).

## Secrets (names only; values live in Supabase secrets)

- `STRIPE_SECRET_KEY` — used by `_shared/stripe.ts`; this function reads it
  only to derive live/test from the prefix. Never logged or returned.
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`
- optional `SENTRY_SERVER_DSN` (shared), optional `OPS_CONSOLE_ORIGIN` (CORS
  for a browser-originated call; unset = no CORS headers, server-to-server only).

## `verify_jwt`

**Leave ON** (the default). The caller is always a Supabase Auth user JWT, so
the gateway check is a free first filter; the function then performs its own
`getUser` + `ops.whoami()` gate regardless. Do **not** deploy with
`--no-verify-jwt`.

## Deploy (owner step — not run by the author of this file)

```
supabase functions deploy ops-refund-execute --project-ref hqycwntpfoztoinemqns
```

Preconditions, in order:

1. Migrations `115_ops_console_foundation.sql` and `118` (executor_claim,
   monotonic record_action_outcome) applied.
2. `ops` added to the project's PostgREST exposed schemas, or every
   `.schema('ops')` call 404s.
3. Smoke call returns `403`/`409` (not `404`/`500`) before the flag is flipped.

## Enablement

The action is shipped **disabled**: both `ops.action_dispatch` and
`ops.executor_claim` refuse `refund_execute` while
`ops.setting('refund_execute_enabled') = false`. Flip it **from the console**
via a `setting_set` action (`subject_ref = 'refund_execute_enabled'`,
`params = {"value": true}`), which is audited. Flip it back the same way to
pause — a paused flag stops in-flight resumes too, since the claim re-reads it.

## What is verified, and what is not

- `npm test` (Node, vitest): the full flow over fake adapters —
  ordering of writes vs. Stripe calls, claim fencing, list-before-POST,
  object classification, identity validation, redaction. `classify.ts` and
  `handler.ts` also pass `tsc --strict`.
- CI `deno-check` (`.github/workflows/ci.yml`): `deno check` type-checks edge
  entrypoints against the Deno toolchain, including remote module resolution
  (`deno.land`, `esm.sh`). **This function's `index.ts` must be added to that
  job's list** for the Deno shell — the only file with Deno globals — to be
  type-checked; `handler.ts`/`classify.ts` are checked by both.
- **Not verified anywhere in CI:** live Stripe behaviour (real refund
  statuses, idempotency replay, `charge_already_refunded` wording), the real
  `executor_claim` / `record_action_outcome` responses (owned by
  `supabase/tests`), and the deployed function's auth path. The first live
  refund must be a test-mode payment with the flag flipped only for that run.
