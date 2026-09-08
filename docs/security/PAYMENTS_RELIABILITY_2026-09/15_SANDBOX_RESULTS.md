# Sandbox run — environment verification, real Stripe test-mode results, parity differences

Sandbox: Supabase project `ofaidukbieeekqaboscm` (org `snatchit-sandbox`, plan Free, $0), Stripe **Sandbox** "SNATCH IT
sandbox" (`acct_1T6Fb1GlD5aqtxIw`, an existing account sandbox — no new one created). Production
(`hqycwntpfoztoinemqns`, live Stripe account `acct_1T6FarGdOzCmGbHw`) untouched. Code under test: PR #54 head.

## 1. Environment adaptations — verified before the matrix

| Adaptation | Sandbox | Production (read-only check, 2026-09-07) | Evidence |
|---|---|---|---|
| Money switch `app.allow_test_mode_money` | set per API request by `public.sandbox_pre_request()` through `pgrst.db_pre_request` on role `authenticator` (`ALTER DATABASE/ROLE SET` of custom parameters is refused by the platform) | `authenticator` has no `pgrst.db_pre_request`; no `sandbox_pre_request` function; no `allow_test_mode_money` setting anywhere | `pg_roles.rolconfig`, `pg_db_role_setting`, `pg_proc` on both projects |
| Can an untrusted caller control the switch? | No. The hook is a role setting (needs `ALTER ROLE` — anon/authenticated cannot CREATE in `public` nor alter roles); `set_config(..., true)` is transaction-local; no exposed RPC sets arbitrary GUCs. A plain database session (no hook) sees the switch unset. | n/a | probes in this document's §1a |
| `kernel` exposed to PostgREST | `pgrst.db_schemas = public, graphql_public, kernel` (role setting) | exposed via the platform setting (the deployed `delete-account` requires it); production's `rolconfig` carries no schema list because the platform manages it | REST probes |
| Unintended access through `kernel`? | anon: `identity_ext` → 401, `request_account_deletion` → 401. Authenticated buyer calling money RPCs with their real parameter names: `hold_payout`, `release_payout`, `admin_refund` → 403 `platform_risk or platform_admin required`; `request_org_payout` → 403 `org_owner or org_finance required`; `admin_set_identity_ext`, `grant_platform_role` → 403 `platform_admin required`; `approve_refund_request` with a NULL id → `not_found` before the role check (exists-check first; a real id is role-gated inside). Public money RPCs (`claim_payout_attempt`, `record_payment_refund`, `settle_verified_payment`, `account_deletion_block_reason`) are invisible to authenticated (404 PGRST202: no EXECUTE). `identity_ext`/`platform_role` readable by authenticated under RLS only. Same grants as production (they come from the migrations). | identical grants | probes |
| Production destinations in the sandbox | 0 function bodies, 0 cron commands, 0 platform_config values mention the production host (four function bodies from 033/099 re-pointed) | n/a | `pg_proc.prosrc`, `cron.job` |
| `verify_jwt` | false on all nine functions (they authenticate in code) | same for the six release edges | `supabase functions list` |
| Expiry cron | **unscheduled** (no Vault bearer in the sandbox); the harness invokes `enforce-transfer-expiry` directly with `INTERNAL_CRON_SECRET` | scheduled every 2 min | §1b |

### 1b. Scheduled execution vs direct harness invocation

| Job | Sandbox | Notes |
|---|---|---|
| `sweep-deletion-pending` (kernel, in-DB, every 2 min) | **real schedule** | S9 waits for a real tick |
| `auto-finalize-auctions` (in-DB, every 2 min) | real schedule | not exercised by the matrix (buy-now only) |
| Phase-2 kernel/venue/market sweeps (in-DB) | real schedule | dark rails, no rows |
| `enforce-transfer-expiry` (HTTP → edge) | **direct invocation** by the harness (`curl … -H "Authorization: Bearer $INTERNAL_CRON_SECRET"`) | the edge's own bearer path is what production's cron uses too; only the trigger differs |
| `refund-execute-tick` / `payout-execute-tick` (HTTP, flags false) | scheduled but gated off (parity) | re-pointed to the sandbox host |
| `notify-report` trigger (HTTP from a trigger function) | re-pointed to the sandbox host | `notify-report` is deployed; email disabled |

## 2. Real Stripe test-mode results (provider results — NOT mocked)

Run `RESULTS_20260907_205044.md` (`scripts/sandbox/20_matrix.sh`) against Stripe Sandbox `acct_1T6Fb1GlD5aqtxIw`
(`livemode=false` asserted on every object) and Supabase `ofaidukbieeekqaboscm`. Every row below was produced by a real
Stripe API call and a real webhook delivery to the deployed edge, verified by SQL on the sandbox database.

| # | Scenario | Real-provider evidence | Result |
|---|---|---|---|
| S1.1 | `reserve_buy_now` with the shipped client's `p_minutes` | HTTP 204; window server-fixed to 10 min regardless of the argument | PASS |
| S1.2 | `create-payment-intent` | real PI minted; row `pending`, total 11000, `stripe_livemode=false`; re-mint within the window returns the SAME PI | PASS |
| S1.3 | confirm + webhook settlement | real `payment_intent.succeeded` delivered → payment `succeeded`, listing `sold`, exactly ONE transfer | PASS |
| S1.3 | `confirm-payment` (build-13 shape) after settlement | 200 | PASS |
| S1.3 | old-client `mark_listing_sold` after settlement | refused with the benign `This listing has already been sold.` — the exact text the shipped client tolerates (`src/lib/payments.ts` `/already sold/i`) and pgTAP 120 asserts | PASS (expected refusal) |
| S1.4 | `confirm-payment` by a different user | 403 | PASS |
| S4 | abandoned checkout | reservation lapsed → re-mint 409, prior PI **canceled at Stripe**, row `failed`, and the real `payment_intent.canceled` event was delivered and processed | PASS |
| S5.1 | duplicate delivery (`stripe events resend`) | `attempt_count` unchanged (already_processed); no double settlement | PASS |
| S6.1 | real partial refund (500) | `succeeded`, `amount_refunded_cents=500`, one `payment_refunds` row | PASS |
| S6.2 | real full remainder refund | `refunded`, `amount_refunded_cents=11000`, TWO ledger rows, first `re_` retained (monotonic) | PASS |
| S7 | real dispute (`pm_card_createDispute`) | transfer `disputed`, `disputes` row `needs_response` | PASS |
| S7 | dispute **lost** | payment `refunded` via the chargeback ledger: `payment_refunds` row carries the `dp_` id and NO refund id | PASS |
| S8.0 | payout leg settlement | real charge settled, transfer row created | PASS |
| S8.x | payout POST with an underfunded sandbox platform balance (8 802 c available vs 9 000 c needed) | Stripe refused (`insufficient available funds`); the ledger recorded attempt `failed`, filed ONE `manual_review` decision `BUYER_CONFIRMED,PAYOUT_TRANSFER_FAILED`, released nothing, moved no money | PASS (correct failure path; environmental, not a code defect) |
| S8.retry | after topping up the sandbox balance with Stripe's designated test card | Phase 2b deliberately waits **15 minutes** after `buyer_confirmed` before sweeping, so the immediate retry was correctly skipped; the timed self-heal run is recorded in §2a | see §2a |
| S9 | deletion request while an obligation is open | accepted (OR-17), `pending_obligations=["active_transfer"]`, state `DELETION_PENDING` | PASS |
| S9.2 | F-5 acquisition guard while pending | `create-payment-intent` → 403 | PASS |
| S9.3 | real scheduled sweep tick | identity held (BP-7 precedes BP-13), not tombstoned | PASS |
| S9.4 | withdraw | back to `ACTIVE` | PASS |
| S12 | run-scoped audit | no unresolved review rows, every webhook event of the run processed, no open attempts, and **no live-mode payment row exists in the sandbox** | PASS |

Two failures in the first corrected run were defects in the harness, not the product, and are fixed in
`scripts/sandbox/20_matrix.sh`: the old-client `mark_listing_sold` assertion expected 200 where the documented,
client-tolerated refusal is correct; and the payout leg had no balance precondition. Earlier runs also failed for three
environment reasons now fixed in the harness: `listings.buy_now_price` is denominated in DOLLARS (payments are cents),
PostgREST returns 204 for void RPCs, and the Stripe CLI prints a context banner that broke JSON parsing.

## 3. Mocked coverage relied on (not sandbox evidence)
pgTAP 4047, vitest 856, rehearsal 63/63 — see `05_VERIFICATION.md` §7.

## 4. Device-only flows (not run)
PaymentSheet 3DS challenge, in-sheet decline-then-retry, Apple Pay, the build-13 binary itself (production-pinned).

## 5. Sandbox-specific differences that limit production parity
- Money switch on (test-mode rows admitted) — production never sets it; the switch admits only `stripe_livemode = false`
  rows, never NULL, so a live key on a test row is impossible by construction.
- Expiry cron unscheduled (direct invocation); Nano compute; 1-day logs; Free-plan inactivity pause.
- `notify-report`/tick functions re-pointed; email disabled; no Sentry DSN.
- Stripe: an account **sandbox**, not the live account's shared test mode; Connect test accounts onboard with synthetic data.
