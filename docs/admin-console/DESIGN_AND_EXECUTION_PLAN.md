# Snatch It Operating Console — design and execution plan

Status: implementation baseline, 2026-09-06. Branch `admin/operating-console`
(base `origin/feature/venue-native-and-product-v2` @ aa74cc2, the branch whose
migration chain production is on — ledger numeric tip **109**; 110–114 are
rehearsal-only and unapplied).

Principle: **what needs attention, who owns it, and what can we safely do.**

## 1. What exists today (verified 2026-09-06)

| Surface | Reality |
|---|---|
| Live portal https://snatchit-admin.vercel.app | Separate repo `~/snatchit-admin` (Next 16.1, one commit, uncommitted work). Service-role key in Next server, authz = `profiles.is_admin` (user-adjacent column, not the trustworthy `public.admin_users`), only `/trust/*` gated by middleware — `/`, `/users`, `/listings`, `/payments` render with the service-role client **without any auth check**. No MFA. "Total GMV" labelled from `payments.status='succeeded'` sums. Trust auto-flag code writes `flag_type` values that violate `seller_flags_flag_type_check`. **Replaced**, not extended. |
| Product | External-ticket resale (Buy Now + auctions). `public.payments` → `public.transfers` (seller obligation) → risk-based release (039) → Stripe Transfer to connected account (`enforce-transfer-expiry`/`confirm-and-release`). No native issuance / scanning in use (Phase-2 rails dark, flags false). |
| Admin authority | `public.admin_users` (service_role-only, 1 row) ∪ `kernel.platform_role` (roles `platform_admin|platform_support|platform_risk`; grants fail closed under PFA-4 so the table is empty) via `kernel.is_platform(text[])`. `kernel.admin_audit` is append-only and requires `auth.uid()`. |
| Verified operator RPCs | `public.resolve_transfer_dispute` (DB-only, sets `refund_required`), `public.admin_release_held_payout` (DB-only; cron pays), `public.admin_relist_listing`, `public.get_payout_review_queue`, `public.get_disputes_awaiting_refund`, `public.get_incomplete_webhook_events` — all service_role-only, no HTTP caller. |
| Refund execution (legacy rail) | **Does not exist.** Buyer-win refunds are a Stripe-Dashboard SOP (`docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md`). Only expiry refunds are automated. |
| Restriction | `seller_risk_scores.is_listing_blocked` is read by `public.can_create_listing()`; clients call it before insert. No DB insert guard consults it. No "suspend account" mechanism. |
| Jobs | 23 `pg_cron` jobs, all succeeding in the last 48h; `refund-execute-tick`/`payout-execute-tick` gated on config flags (false); `crm-export-*` ticks post to an unauthored function. |
| Notifications | `notify.*` outbox/delivery exists but has no dispatch adapter (parked); legacy `notify-report` pushes to `admin_users` (email off by default). |
| PostgREST exposure | `public`, `kernel` only. |
| Prior audit (2026-09-05) | F01–F23 examined against current code; F02/F05/F06/F15 shape the reconciliation detectors below. The console never overwrites money state and never replays webhooks. |

## 2. Decisions

1. **Monorepo, separately deployable app** at `admin/` (sibling of `web/`), same Next 16 / `@supabase/ssr` conventions. Vercel project `snatchit-admin` gets Root Directory `admin` (owner step; token here lacks scope).
2. **New Postgres schema `ops`** — the console's own leaf context (cases, notes, actions, approvals, audit, job runs, summaries, metric snapshots). Cross-context *reads* are SECURITY DEFINER functions in `ops` (the console is inherently cross-context; no ad-hoc joins from the app). Cross-context *writes* only through the published domain functions above. No `public` objects → Gate-2 parity untouched. Requires adding `ops` to PostgREST exposed schemas (owner dashboard step, same as `kernel`).
3. **No service-role key in the admin app.** Every read/mutation is an RPC executed with the founder's own JWT; every `ops.*` entry point re-checks `kernel.is_platform(...)` and the `aal` claim server-side. Hidden navigation is not security; the DB is the wall.
4. **MFA (TOTP) mandatory.** Proxy requires an `aal2` session for every console route; DB mutations require `aal2` (the migration 085/096/106 idiom); reads require `aal2` too. Enrollment happens in-app on first login (Supabase Auth MFA).
5. **Roles:** `platform_admin` (founders, full), `platform_support` (cases/notes/moderation, no money), `platform_risk` (support + payout holds). Only `platform_admin` is grantable today (bootstrap via `admin_users`); others are wired but empty (PFA-4).
6. **Action integrity:** one entry point `ops.execute_action(...)` — durable `ops.action` row keyed by client idempotency key; server-side expected-state check; state machine `requested → (awaiting_approval) → processing → succeeded | failed | unknown | rejected`; audit row on request and on outcome; approvals bound to `sha256(action_type|subject|params)` and invalidated when terms change; approver ≠ requester.
7. **Approval required** (second founder): `payout_release` (risk-hold override), `refund_execute` (money leaves), `user_restrict` lift? no — restriction lift is ordinary. Ordinary work (assign, notes, dispute resolution recording, report triage, relist, restrict) needs no approval.
8. **Refund execution** = new edge function `ops-refund-execute` (service role inside, caller JWT verified as `platform_admin`+aal2, action must be `approved`), Stripe `POST /v1/refunds` with idempotency key `ops_action_<action_id>`, outcome recorded via `ops.record_action_outcome`. Local payment state is updated by the existing `charge.refunded` webhook, so the action shows `succeeded_at_provider` until the webhook lands; the reconciliation detector tracks the gap. **Shipped disabled by default** behind `ops.setting('refund_execute_enabled')`, because the edge function is not deployed by this PR; the UI labels it.
9. **Automation** = SQL detectors in `ops`, run by `pg_cron` every 5 min through `ops.run_job(name)` (durable `ops.job_run`, `ops.job_state` with consecutive-failure backoff, advisory lock against overlap, duplicate-safe case upsert by `dedupe_key`, auto-resolve when the condition clears). Daily summary at 13:00 UTC written to `ops.daily_summary` (portal-visible; no delivery channel configured → documented).
10. **Money vocabulary:** captured payment ≠ refund ≠ dispute ≠ connected-account transfer (`transfers.stripe_transfer_id`) ≠ bank payout (not tracked; labelled "not tracked"). No "revenue"; "gross captured volume" with definition, currency USD only (single-currency data), UTC date basis, refunds shown separately.
11. **Not built (honest labels):** webhook replay (Stripe Dashboard resend), account suspension (no mechanism), platform-role grants (PFA-4), email/SMS alerts (no adapter), kernel/native-rail money actions (rails dark).

## 3. Contracts (shared with all sub-work)

### 3.1 Authz helpers (`ops`)
- `ops.actor_role() returns text` — `platform_admin|platform_support|platform_risk|null` for `auth.uid()`.
- `ops.assert_reader()` — raises `42501` unless role ≠ null and `aal='aal2'`.
- `ops.assert_role(text[])` — as above plus role membership.

### 3.2 Tables (`ops`, RLS on, no policies, no grants to anon/authenticated; definer functions only)
`case`, `case_note` (append-only), `case_event` (append-only), `action`, `approval`, `audit` (append-only, trigger-protected), `user_restriction`, `job_state`, `job_run`, `alert`, `daily_summary`, `metric_snapshot`, `setting`.

`ops.case`: `id, case_type, subject_kind, subject_id uuid, subject_ref text, dedupe_key unique(partial where status not in (resolved,dismissed)), title, summary, status(open|in_progress|waiting|resolved|dismissed), priority(p1..p4), assignee, due_at, detector, detected_at, last_seen_at, resolved_at, resolved_by, resolution_note, version int, created_at, updated_at`.

`ops.action`: `id, idempotency_key unique, action_type, subject_kind, subject_id, params jsonb, expected jsonb, reason, requested_by, requested_at, state, approval_id, correlation_id, result jsonb, error, provider_ref, completed_at, version`.

### 3.3 Read API (all `security definer`, `assert_reader()`, `authenticated` EXECUTE)
- `ops.whoami() jsonb` — `{user_id, role, aal, email_masked}`
- `ops.search(p_q text, p_limit int default 20) jsonb` — hits `{kind, id, label, sub, status}` across payments (id, `pi_`), transfers, listings (id, event_name), users (id, display_name, email exact, phone exact), disputes (`dp_`), stripe transfer ids (`tr_`), refund ids (`re_`).
- `ops.list_orders(p_filters jsonb, p_cursor text, p_limit int) jsonb` — `{items, next_cursor}`; filters: `payment_status[]`, `transfer_status[]`, `payout_state`, `has_open_case bool`, `from/to`, `q`; sort `created_at desc, id desc` keyset.
- `ops.order_detail(p_payment_id uuid) jsonb` — payment, transfer, listing, buyer, seller (masked), disputes, dispute_resolutions, payout_decisions, refund facts, cases, actions, seller_funds_state.
- `ops.order_timeline(p_payment_id uuid) jsonb` — `[{at, source, kind, label, ref}]` sorted.
- `ops.list_cases(p_filters jsonb, p_cursor text, p_limit int) jsonb`, `ops.case_detail(p_case_id uuid) jsonb`.
- `ops.list_users(...)`, `ops.user_detail(p_user_id uuid) jsonb` (history, listings, orders, onboarding state, reports, flags, restrictions, notes, no raw phone — masked).
- `ops.list_listings(...)`, `ops.listing_detail(p_listing_id uuid) jsonb`, `ops.list_reports(...)`.
- `ops.money_overview(p_from date, p_to date) jsonb` — defined metrics (see §5), from snapshot + live, with `computed_at`.
- `ops.list_payouts(p_filters, p_cursor, p_limit) jsonb` — transfers with funds state.
- `ops.reconciliation_queue(p_cursor, p_limit) jsonb`.
- `ops.job_health() jsonb` — cron jobs + last run + ops job_state + webhook backlog + notify delivery counts.
- `ops.audit_log(p_cursor text, p_limit int) jsonb`, `ops.list_actions(...)`, `ops.today() jsonb` (attention queue + metrics + freshness), `ops.latest_summary() jsonb`.

### 3.4 Mutations (all require `aal2`; return jsonb `{status, ...}`; never throw for expected outcomes except authz)
- `ops.execute_action(p_idempotency_key text, p_action_type text, p_subject_kind text, p_subject_id uuid, p_params jsonb, p_reason text, p_expected jsonb) jsonb`
  - action types: `case_assign, case_status, case_priority, case_due, case_note, dispute_resolve, payout_release, listing_relist, report_resolve, user_restrict, user_unrestrict, refund_execute, job_retry, approval_decide, case_create`
  - statuses: `succeeded | idempotent_replay | awaiting_approval | rejected(stale_state|precondition|not_allowed|disabled) | failed | processing`
- `ops.approve_action(p_action_id uuid, p_decision text, p_reason text) jsonb` (≠ requester; binds hash; then executes if approve).
- `ops.record_action_outcome(p_action_id uuid, p_state text, p_result jsonb, p_error text, p_provider_ref text) jsonb` — service_role only (edge function).
- `ops.run_job(p_job_name text) jsonb` — service_role (cron) and `platform_admin` (manual retry).

### 3.5 Detectors (each idempotent, dedupe by `case_type:subject`)
paid_unsettled · transfer_deadline_soon (<6h) · transfer_overdue · release_stuck (auto_released/buyer_confirmed w/o `stripe_transfer_id` >30m) · refund_pending (dispute buyer-win/expired w/ succeeded payment) · refund_failed (`ops.action` refund unknown/failed) · dispute_open (SLA 72h) · dispute_evidence_due (Stripe `disputes.evidence_due_by`) · payout_review (`manual_review`) · report_review · webhook_stuck (>15m unprocessed / failed_at) · job_failure (cron failed ≥2 consecutive or no success in 3× interval) · notification_failure (notify.delivery failed/dead) · reconciliation_mismatch (refunded payment with released payout; total ≠ amount+fee).

## 4. Execution plan
1. Migrations `115_ops_console_foundation.sql` (schema, tables, authz, audit, action engine, case RPCs), `116_ops_console_read_api.sql`, `117_ops_console_automation.sql` (+ cron). Rollbacks 115–117. pgTAP `181_`,`182_`,`183_`.
2. `admin/` app: login, MFA enroll/verify, Today, Cases, Orders (+detail/timeline), Money, Users, Marketplace, Reports, System (jobs/notifications/audit/actions).
3. Edge function `ops-refund-execute` (not deployed by this PR).
4. Local integration harness: rehearsal DB + PostgREST + minimal auth stub (`admin/scripts/local-stack.sh`), synthetic fixtures. Browser verification against it.
5. CI: non-required `admin` job (typecheck/lint/test/build).
6. Docs: architecture decisions, setup + env template, founder bootstrap, operating guide, deploy/migrate/rollback runbook, final report.

## 5. Metric definitions (Money page)
| Metric | Definition | Source | Basis |
|---|---|---|---|
| Gross captured volume | Σ `payments.total` where status ∈ (succeeded, refunded) | `public.payments` | `paid_at` UTC date, USD |
| Refunded volume | Σ `payments.total` where status = refunded | `public.payments` | `refunded_at` UTC |
| Platform fees (gross, pre-refund) | Σ `buyer_fee + seller_fee` on succeeded | `public.payments` | `paid_at` |
| Seller funds released to connected account | count/Σ `payments.amount - seller_fee` where `transfers.stripe_transfer_id` not null | `public.transfers`+`payments` | `payout_released_at` |
| Seller funds pending | transfers seller_sent/buyer_confirmed/auto_released without `stripe_transfer_id` | `public.transfers` | now |
| Bank payouts | not tracked (`payout.paid` webhook only logged) | — | — |
