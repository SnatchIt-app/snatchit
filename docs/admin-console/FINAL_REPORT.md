# Operating console — final report (first release, 2026-09-06)

Branch `admin/operating-console` (base `feature/venue-native-and-product-v2` @ aa74cc2 —
the lineage production's migration chain is on; production ledger numeric tip **109**).
Nothing in this branch has been applied to or deployed on production.

## 1. What works

| Area | Delivered |
|---|---|
| Founder access | Individual accounts; `public.admin_users` ∪ `kernel.platform_role` via `kernel.is_platform()`; TOTP MFA enrol/verify in-app; every route needs `aal2` (proxy) and every RPC re-checks role + `aal2` server-side; non-operators land on `/denied`. No service-role key anywhere in the app. |
| Search & investigation | `/search` over payment/transfer/listing/user ids, `pi_ tr_ re_ dp_`, exact email/phone, event name. `/orders` server-side filters + keyset pagination. `/orders/:paymentId` unified detail (payment, transfer, parties masked, disputes, resolutions, payout decisions, refund facts, evidence via signed URLs, seller-funds state) + merged chronological timeline. |
| Exception queues & ownership | 14 case types detected every 5 min (pg_cron) with dedupe, auto-resolve and priority escalation; Today queue with All/Mine/Unassigned; cases with assign/status/priority/due/notes; optimistic versioning rejects conflicting founder edits. |
| Verified interventions | Resolve dispute (`resolve_transfer_dispute`), release held payout (`admin_release_held_payout`, second-founder approval), relist listing (`admin_relist_listing`), report triage, block/unblock listing creation (`seller_risk_scores.is_listing_blocked`), manual case, run console job, settings — all through `ops.execute_action` with reason, idempotency key, expected-state check, durable action row and append-only audit. |
| Money | `/money`: six defined metrics (definition/source/basis/currency on each tile), payouts table with explicit funds vocabulary (connected-account transfer ≠ bank payout, which is labelled *not tracked*), reconciliation queue of live mismatches. Refunds, disputes, transfers and captures are never conflated. |
| Users & trust | `/users/:id` history, listings, orders, onboarding booleans (never the Connect id), reports, flags, risk score, restriction history. Contact data masked. No impersonation. |
| Marketplace | Listings/auctions with filters and detail; reported-content queue; no price/fee editing; relist only for admin-owned never-transacted cancelled inventory (domain rule). |
| System | Cron job health (with honest "not available" when `cron.job_run_details` is absent), console job runs/backoff/last success, webhook backlog, notify delivery counts, alerts, approvals inbox, settings (typed, audited), audit log, actions list, latest daily summary (portal-only). |
| Automation | Detectors, metric snapshots and a daily summary as SQL jobs under `ops.run_job` (advisory-lock overlap guard, exception-isolated bodies, consecutive-failure backoff, durable `ops.job_run`), scheduled by two cron entries. Alerts dedupe (`ops.alert`) and recover. |

## 2. What was verified (evidence in this session)

- **Fresh full-chain replay** (`scripts/rehearsal_reset.sh`, 000→117) → Gate-2 parity `tables=27 functions=70 policies=37 triggers=26` unchanged; complete pgTAP suite **4179 planned / 4175 ok**, the 4 not-ok being the documented local-only deltas in 060/132. New tests: `181` (128), `182` (45), `183` (65).
- **Admin app**: `tsc` clean, `eslint` clean, vitest **59/59**, `next build` green. Root vitest `tests/ops-refund-classify.test.ts` **46/46**.
- **Browser, against the local harness** (PostgREST + auth stub on the rehearsal DB, synthetic fixtures): password login → MFA enrol (QR) → verify → Today; returning founder → verify-only path; `support@example.test` (not in `admin_users`) → "Your account is not an operator"; case assign (status→in progress, v2); stale submission with the old version → rejected "version 2, you had 1"; founder A requests payout release → "awaiting a second operator's approval"; founder B approves from System → action `succeeded`, transfer `auto_released`, `payout_decisions` actor = requester, approval `approved` by B, `payout_review` case auto-resolved, audit rows written; report `pending → reviewing`.
- **Direct authz probes through the gateway**: founder `ops.whoami()` 200; non-operator `42501`; anon on `admin_users` `42501`; `is_platform` true/false as expected.
- **Duplicate-safety**: detectors run twice on 6,000 synthetic orders → 547 cases, zero duplicates (pgTAP 183 also pins this); same idempotency key twice → `idempotent_replay`, one action row (181).
- **Performance** (local Postgres 17, 6,000 payments / 2,000 transfers / 6,000 listings, 547 open cases): `today` 56 ms (192 KB), `list_orders` 16 ms, filtered 13 ms, `search` 3 ms, `order_detail` 1 ms, `list_cases` 14 ms, `money_overview` 2 ms, full detector sweep 108 ms first run / 53 ms second. On the 13-payment fixture set every call is under 33 ms. These are single-node local numbers, not a production capacity claim.

## 3. Reused vs replaced

**Reused (verified domain functions and infrastructure):** `public.resolve_transfer_dispute`, `public.admin_release_held_payout`, `public.admin_relist_listing`, `public.can_create_listing` + `seller_risk_scores.is_listing_blocked`, `kernel.is_platform`, `public.admin_users` bootstrap, Supabase Auth MFA, `pg_cron`, web app conventions (`@supabase/ssr` proxy/server clients, `getClaims`, env fail-fast, CSP), the migration/rollback/pgTAP/CI conventions, `_shared/stripe.ts` transport.

**Replaced:** the separate `~/snatchit-admin` portal (service-role key in the Next server, `profiles.is_admin` as authority, unauthenticated `/`, `/users`, `/listings`, `/payments`, no MFA, "Total GMV" from succeeded sums, trust auto-flag code violating `seller_flags` CHECKs). Its useful ideas (payout review queue, dispute list, seller status) live on as detectors and detail panels.

**New:** schema `ops` (migrations 115–117), edge function `ops-refund-execute`, `admin/` app, local harness.

## 4. Intentionally disabled / unsupported, with exact dependency

| Capability | State | Dependency |
|---|---|---|
| Execute refund | Requestable and approvable; execution **rejected as `disabled`** by `ops.action_precheck` | Deploy `supabase/functions/ops-refund-execute`, then flip `ops.setting.refund_execute_enabled` (audited `setting_set`). Until then: Stripe-Dashboard SOP. |
| Stripe webhook replay | Not offered | Stripe Dashboard re-send is the only safe path; the console shows the stuck event and its error. |
| Account suspension | Not offered | No backend mechanism exists; only listing-creation block is enforced (`can_create_listing`, checked by clients before insert — not by a DB insert guard). |
| Support/risk roles | Wired in the role matrix, ungrantable | `kernel.grant_platform_role` fails closed pending owner signature on PFA-4. |
| Email/SMS/push alerts | Summaries and alerts are portal-only | No delivery adapter is configured (`notify` dispatch parked; `notify-report` email off). |
| Native-rail money actions (kernel refunds/payouts) | Not surfaced | Rails are dark (`feature.*` false); nothing to operate yet. |

## 5. Remaining blockers / open items

1. **Second founder not bootstrapped in production** (`admin_users` has one row) — approvals cannot complete until `FOUNDER_BOOTSTRAP.md` is executed for the second founder.
2. **PostgREST exposed schemas** must include `ops` (owner dashboard step).
3. **Migrations 110–114 are unapplied**; `supabase db push` would apply them together with 115–117. Use the SQL-editor path in `RUNBOOK.md` or decide deliberately.
4. **Vercel `snatchit-admin`**: the automation token here lacks scope for that project; cut-over (root directory `admin`, env vars, deleting the service-role/`ADMIN_SECRET` vars) is an owner step.
5. **Edge function not deployed** (by design for this PR); `deno check` could not run locally (Deno not installed) — CI's `deno-check` job covers it.
6. Harness fidelity: no real GoTrue, no Stripe, cron/net inert — MFA enforcement is verified by pgTAP (`aal` claim) and the proxy unit tests, not against live GoTrue.
7. Recommended indexes not added (justified only at scale): `payments(paid_at)`, `payments(refunded_at)`, `transfers(payout_released_at) where stripe_transfer_id is null`, `payments(stripe_refund_id)`, `transfers(stripe_transfer_id)`.
8. Screenshots were not captured (standing project rule: text-only verification unless explicitly asked).

## 6. How to open and use

Local: `SETUP.md`. Production: `RUNBOOK.md` §1–3 then `FOUNDER_BOOTSTRAP.md`; day-to-day: `OPERATING_GUIDE.md`.

## 7. Exact steps to go live (owner)

1. Bootstrap the second founder (`FOUNDER_BOOTSTRAP.md`).
2. Confirm auto-deploy is OFF in the Supabase dashboard; record the date in the PR.
3. Apply 115, 116, 117 via the SQL editor (or `db push --include-all` if 110–114 are meant to go too); insert the three ledger rows; run the verification queries in `RUNBOOK.md` §1–2.
4. Add `ops` to PostgREST exposed schemas.
5. `select ops.run_all_detectors();` once by hand; check `ops.job_run`.
6. Vercel: connect `snatchit-admin` to this repo, root `admin`, Node 22, the four public env vars, delete the old privileged vars; add the console origin to Supabase Auth redirect URLs.
7. Sign in as each founder, enrol MFA, confirm Today renders and `/denied` renders for a non-admin.
8. Later, optionally: deploy `ops-refund-execute`, then enable `refund_execute_enabled`.
