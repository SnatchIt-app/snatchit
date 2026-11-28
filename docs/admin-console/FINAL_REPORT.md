# Operating console — final report (release candidate 3, 2026-09-07)

Branch `admin/operating-console` → draft PR #55 (base
`feature/venue-native-and-product-v2` @ aa74cc2, the lineage production's
migration chain is on; production ledger numeric tip **109**, 124 rows,
read-only verified 2026-09-07). Nothing in this branch has been applied to or
deployed on production. Refund execution remains **disabled**. RC3 closes the
two findings of the focused re-review (§1a).

## 1a. Focused re-review findings — status

| # | Finding | Status | Evidence |
|---|---|---|---|
| R1 | Daily summary summed `payments.total` over refunded rows and the view rendered it as "Refunded"; a $10 external partial refund on a $100 payment reported $100 refunded | **Fixed** (migration 120 + UI adapter) | `ops.build_daily_summary` → `refunded_cents: null`, `refunded_count`, `refunded_upper_bound_cents`, `certainty: uncertain`; legacy stored summaries normalised on read (`ops.latest_summary`) and rewritten in place; `SummaryView` renders through `refundSummary()` which never formats an unknown amount as $0 or as the total. pgTAP 186 (27): the $100/refunded row yields null amount, count 1, bound 10000; empty window; mixed statuses; legacy row normalised; dashboard, snapshot and summary agree; payment row untouched. Admin vitest `summary-money.test.ts` (7). Browser: a legacy summary shows "amount not available locally · count not recorded (legacy summary) · upper bound $100.00 USD · legacy summary normalised". |
| R2 | Refund executor skipped the live/test check when key mode or payment mode was missing | **Fixed** | `handler.ts` requires `deps.stripeKeyMode ∈ {live,test}` and a boolean `claim.stripe_livemode` via the shared `checkModeConsistency` BEFORE the reconciliation list; missing/null/malformed on either side and both mismatch directions → `failed` (422) with the failure recorded and **zero** Stripe calls (create and list); live/live and test/test proceed. `Deps.stripeKeyMode` is now a required field so the Deno adapter cannot omit it. Handler vitest 113 (8 invalid cases + 2 valid). |

Cross-check of adjacent flows after these fixes: approve/deny strictness, evidence access + MFA, listing guard, full-refund-only, lifecycle classification, approval binding/pause/lease/recovery and containment were re-run through pgTAP 181–186 and the handler suite with no regressions.

## 1. Independent review findings — status

| # | Finding | Status | Evidence |
|---|---|---|---|
| 1 | Deny sent `reject`; RPC accepts `approve\|deny` → denial failed | **Fixed** | `admin/src/lib/types.ts` `ApprovalDecision` + strict `parseApprovalDecision`; forms send `deny`; malformed → `invalid decision`, never approve. Verified through the real form in the browser: action `rejected/denied`, approval `denied` by the other founder, transfer untouched (no `payout_decisions` row), audit `approval.denied`; afterwards `executor_claim` → `wrong_type`, re-approve → `stale_state`, literal `reject` → `invalid_input`. pgTAP 184 §A; vitest `approval-decision.test.ts` drives `submitActionForm` with a recording fake. |
| 2 | Founder evidence access had no storage authorization | **Fixed (DB + app); real Storage verification outstanding** | 118: storage policy `proof-docs operator read` (operator role + aal2 + path referenced by a transfer/listing) and `ops.evidence_access` (resolves path from the record, audits `evidence.viewed`). App never signs a caller-supplied path. pgTAP 184 §H: founder aal2 sees only referenced objects, aal1 sees none, unrelated user sees none, buyer/seller policies unchanged; test 132's production policy fixture updated (12 policies). Browser: button resolves + audits; signing fails on the harness (no Storage API) — see §4. |
| 3 | Listing block was client-advisory | **Fixed** | 119: `public.guard_listing_seller_not_blocked()` BEFORE INSERT on `listings` (FOR SHARE against a concurrent block; service_role / no-context paths pass; INSERT only). Direct authenticated insert by a blocked seller → `listing_blocked`; relist path already refuses non-admin sellers; state columns already guarded. pgTAP 185 (24) incl. console `user_restrict` → insert refused → `user_unrestrict` → allowed. Gate-2 counters 70→71 / 26→27; SEC-2 decision recorded. |
| 4A | Partial refunds mis-accounted | **Fixed by restriction + honest reporting** | Full refunds only: rejected in `ops.action_precheck` and `action_dispatch` (`not_supported`), in the handler (defence in depth), and the UI has no amount field. `refunded_volume` reports `value_cents: null`, `upper_bound_cents`, `certainty: uncertain` (local model stores refund status only; `charge.refunded` also fires for partials); the tile says "not available locally". Existing partial refunds from other routes remain indistinguishable locally — stated, not hidden. |
| 4B | Refund objects classified as success regardless of status | **Fixed** | `classifyRefundObject` reads `status` (succeeded / pending / requires_action / failed / canceled / unknown); identity (payment_intent, amount, currency, `metadata.ops_action_id`) validated for created and adopted objects; `ops.executor_claim` re-checks enabled flag, pause, approval + hash and takes a lease; reconcile-before-retry via `GET /v1/refunds`; `ops.record_action_outcome` is monotonic and pins `provider_ref`; stale `processing` opens a case; webhook completion moves `succeeded_at_provider → succeeded`. 105 handler/classifier vitest cases; pgTAP 184 §C–F. |
| 5 | Deno CI did not check the new endpoint; report overstated | **Fixed** | `ci.yml` deno-check now lists `ops-refund-execute/{classify,handler,index}.ts`; handler tests run in the root `npm test` (quality job). This report separates evidence classes (§2). |
| 6 | Rollback plan dropped `ops` and restored the insecure portal | **Fixed** | `RUNBOOK.md` §5: non-destructive containment (pause switch `actions_enabled`, detector pause, in-flight action triage, PostgREST un-expose, known-safe authenticated build); destructive rollback confined to rehearsal DBs (§6); old portal explicitly never a fallback; §7 go-live now lives in the runbook; blast radius distinguishes definitions vs runtime writes. |
| 7 | Proposed path 000→109 + 115→117 never rehearsed | **Rehearsed** | Isolated DB: `REHEARSAL_UPTO=109_…`, then the five timestamp files, then 115→119, 110–114 omitted (kernel `signing_key` at its 109 shape). pgTAP 181–185 pass there; reads, a mutation, `run_all_detectors` and metric snapshots work. Ledger procedure for 115–119 and the pending-by-design 110–114 in `RUNBOOK.md` §1. |
| 8 | Real Supabase Auth not exercised | **Blocked locally — outstanding** | No Docker on this host; the only Supabase project is production (no staging). MFA/aal2 enforcement is verified at the database (pgTAP, `aal` claim) and in the proxy unit tests; browser flows ran against the auth stub. See §4 for the exact owner verification list. |

## 2. Verification — by evidence class

**Unit tests (no I/O).** `admin/`: 15 files, **96** vitest cases (proxy decisions, decision parser + real `submitActionForm` branch with a recording fake, evidence slot allowlist, labels, metric rendering, idempotency helper). Root: `tests/ops-refund-handler.test.ts` + `tests/ops-refund-classify.test.ts`, **113** cases (incl. the mode-guard matrix).

**Database integration (pgTAP on Homebrew PG 17 with the repo's rehearsal harness).** 181 (128), 182 (45), 183 (65), 184 (90), 185 (24), 186 (27) = **379** assertions for this package. Full suite on a fresh 000→120 replay (**4,320 planned / 4,316 ok**, the 4 = documented local deltas 060/132) and on the exact production shape (000→109, timestamps, 115→120): see the run tails in the PR description; Gate-2 parity `tables=27 functions=71 policies=37 triggers=27` matches `ci.yml`.

**Handler tests with mocked external services.** `runRefundExecution` with fake DB/Stripe adapters: full success; partial refused; pending / requires_action / failed / canceled / unknown objects; duplicate and concurrent requests (one POST); crash before the provider call; provider success with a lost local write and recovery by list-adopt; mismatched adoption; disabled / paused / stale / missing approval; refused outcome after a terminal state treated as a no-op; secret redaction.

**Browser (local harness: PostgREST 16 + auth stub + synthetic fixtures, real migrations).** Login → TOTP enrol/verify → Today; non-operator → `/denied`; case assign + stale-version rejection; two-founder approval (approve) executed; **deny** executed through the real form (finding 1); pause via the settings form → banner + refused mutation → un-pause via the same form; evidence button → `ops.evidence_access` + `evidence.viewed` audit (signing fails: no Storage in the harness). Screenshots were not captured (standing project rule).

**Real service integration.** **None.** No live Stripe, no real GoTrue MFA, no real Storage signing. These are the outstanding items in §4 and the acceptance gates in `RUNBOOK.md` §6b (G1–G8), which must pass on the deployed console before founder operations switch to it.

**Production verification.** Read-only only: ledger tip 109 / 124 rows, `admin_users` = 1, `platform_role` = 0, verified MFA factors = 0, 11 storage policies, 7 refunded payments, `git_branch: ""` on the production branch record. Nothing changed.

## 3. Reused vs replaced (unchanged from RC1)

Reused: `resolve_transfer_dispute`, `admin_release_held_payout`, `admin_relist_listing`, `can_create_listing`, `kernel.is_platform`, `public.admin_users`, Supabase Auth MFA, `pg_cron`, web app conventions, `_shared/stripe.ts`. Replaced: the separate `~/snatchit-admin` portal. New: schema `ops` (115–118), listing guard (119), `ops-refund-execute` (not deployed), `admin/`, local harness.

## 4. Remaining real-service gaps and owner verification

1. **Real Supabase Auth**: first-founder TOTP enrolment, returning-founder challenge, session refresh/expiry, lower-assurance rejection, direct RPC without role/MFA — to be exercised by the founders on the deployed console (§7 of the runbook) or on a non-production Supabase project if one is created. Database-side enforcement is tested; the GoTrue side is not.
2. **Real Storage**: a founder who is neither buyer nor seller opens referenced evidence; an unrelated user cannot; expired links stop working. The policy and RPC are tested at the database; the Storage API call is not.
3. **Stripe**: nothing executes until `ops-refund-execute` is deployed and `refund_execute_enabled` is flipped; the handler is verified only against fake adapters. Refunds must remain disabled until an owner-approved test-mode exercise of the deployed function has been done.
4. **Vercel `snatchit-admin`** cut-over (root `admin`, four public vars, delete the old privileged vars) — token here lacks scope.
5. **Second founder** bootstrap and **`ops` in PostgREST exposed schemas** (owner dashboard steps).
6. **`deno check` locally**: Deno is not installed on this host; the CI job covers it on the PR head.

## 5. Readiness

- **Non-refund portal**: ready for **controlled, owner-approved deployment verification** — i.e. deploy behind the runbook §0 checks and run the §6b acceptance gates (G1–G8) before it becomes the system of action. This focused pass does not certify the whole portal; it closes the reviewed defects with regression coverage.
- **Refunds**: **must remain disabled** (`refund_execute_enabled=false`, edge function not deployed). The console rejects refund requests up front; the executor refuses claims while disabled.

## 6. Exact owner actions to go live

See `RELEASE_CHECKLIST_RC3.md` (checksummed migration order, ledger rows, exposure, bootstrap, Vercel, retirement of the old deployment, containment) and `ACCEPTANCE_GATES.md` (G1–G8 procedures with `admin/scripts/acceptance/gates.sql` and `gate-probe.mjs`). Read-only production facts were re-taken on 2026-09-07 for that checklist; the Vercel project was inspected with the local CLI session (not git-linked, root `.`, service-role key present in all scopes, last production deploy 152 days old, `/users` renders unauthenticated).


`RUNBOOK.md` §7 (bootstrap second founder → confirm auto-deploy OFF → apply 115→119 via SQL editor + ledger rows → expose `ops` → first detector run → Vercel cut-over → founder sign-in/MFA/denied check). Refund enablement is a separate, later decision (§4).
