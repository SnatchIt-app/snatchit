# Payments reliability program — verified baseline (2026-09-06)

Program scope: secure and stabilize the existing Stripe/Supabase resale marketplace against the
September 5 audit (`SNATCH_IT_TECHNICAL_AUDIT_2026-09-05.md`, F01–F10 / F18 as they bear on money flow).
Out of scope by owner direction: the $0.90 fee (F11), processor change, AWS, native issuance/scanning.
Fee model preserved: 10% buyer + 10% seller (`_shared/money.ts`).

## Repository state (verified by command output in this session)

| Item | Value | Evidence |
|---|---|---|
| GitHub `main` | `eadd456ae4e77d93da18101eef62648ae4ab5354` | `git ls-remote origin refs/heads/main` |
| Local `/Users/josetascon/snatchit` | `94b3be7` on `mobile/profile-rpc-compat`, **4 ahead / 123 behind** main; only tracked change `.claude/launch.json` (+46 untracked artifacts) — left untouched | `git rev-list --left-right --count HEAD...origin/main` |
| Other worktrees | 13 sibling + 8 nested worktrees inspected by `git worktree list`; none modified | — |
| Program worktree | `/Users/josetascon/snatchit-pay`, branch `fix/payments-reliability` created from `origin/main` at `eadd456` | `git worktree add` |
| Commit being changed | **`eadd456ae4e77d93da18101eef62648ae4ab5354`** | — |

Local test baseline in the program worktree (fresh `npm ci --ignore-scripts`):

| Suite | Result |
|---|---|
| root `npx vitest run` | 5 files, **116 passed** |
| root `npm run typecheck` | clean |
| web `npx vitest run` | 12 files, **165 passed** |
| web `npm run typecheck` / `lint` | clean / 0 errors, 4 warnings |
| `packages/core` + `packages/design-tokens` parity | 3 files, **108 passed** |
| pgTAP on a fresh replay of main's 89-migration chain (loopback Postgres 17, `scripts/rehearsal_*` harness copied from the Phase-2 branch; not Docker/CI) | plan 299 · ok 295 · not_ok 4 — the 4 are the documented local-only deltas (060 TODO markers ×2, 132 cron-parity ×2) |
| Migration replay | `REPLAY OK: 89/89` |

## Deployed state (read-only, Supabase project `hqycwntpfoztoinemqns`, 2026-09-06)

**Production is ahead of `main`.** The migration ledger holds every `main` migration **plus** the Phase-2
chain `076`–`109` and `20260902003623_admin_relist_listing_rpc` (129 rows). Those migrations live on
`feature/venue-native-and-product-v2` (PR #52 → `phase2/consolidation`), not on `main`.

Edge functions (deployed source fetched and diffed against `main`):

| Function | Deployed | vs `main` |
|---|---|---|
| create-payment-intent | v45 (2026-09-02) | **differs**: adds a `kernel.is_deletion_pending` guard (403 `account_deletion_pending`, fail-open on RPC error); otherwise identical |
| confirm-payment | v34 (2026-08-04) | identical |
| stripe-webhook | v39 (2026-08-05) | identical |
| confirm-and-release | v34 (2026-09-02) | **differs**: adds a `kernel.identity_ext` deletion-pending guard (fail-open); payout path otherwise identical |
| enforce-transfer-expiry | v36 (2026-08-04) | identical |
| delete-account | v19 (2026-09-02) | **rewritten**: OR-17 tombstone flow (`kernel.request_account_deletion` / `withdraw_account_deletion`); no physical delete, no `delete_account_cleanup`, no storage removal |
| all `_shared/*.ts` | — | identical |

Money RPC bodies (`md5(prosrc)`), production vs fresh local replay of `main`: `mark_listing_sold`,
`complete_auction_payment`, `reserve_buy_now`, `release_reservation`, `ensure_transfer_exists`,
`mark_transfer_sent` (both overloads), `confirm_transfer_received`, `freeze_transfer_for_dispute`,
`get_incomplete_webhook_events`, `delete_account_cleanup`, `mark_transfer_reversed` — **identical**.
`claim/complete/fail_stripe_webhook_event` and `record_transfer_payout` — md5 differs, but the
production definitions were fetched verbatim and are the same text as migrations 064 / 0564
(formatting-level difference only; no semantic drift). Grants match the migrations: sale/reserve RPCs are
EXECUTE for `authenticated` + `service_role`, never `anon`; lease/payout/freeze RPCs are `service_role`-only.

Indexes/constraints relevant to the invariants: `payments` UNIQUE(`stripe_payment_intent_id`) + partial UNIQUE
one-`succeeded`-per-listing; `transfers` UNIQUE(`listing_id`), UNIQUE(`payment_id`); **no** unique index on
`transfers.stripe_transfer_id`; no reservation/attempt table; `webhook_retries` exists with no client grants.

## Consequences for this program

1. Fixes are authored on `main` (the resale-marketplace code), in a worktree; but **deploying `main`'s
   edge functions as-is would regress the Phase-2 guards** in create-payment-intent, confirm-and-release
   and would replace the tombstone delete-account with the physical-delete handler. Release therefore
   requires either merging the Phase-2 branch to `main` first or forward-porting these packages onto it.
   Recorded as a launch dependency, not solved here.
2. F10 (account deletion) must be evaluated against the **deployed** tombstone flow: `kernel.sweep_deletion_pending`
   (078) already blocks BP-6..BP-11 (payout holds, open/disputed transfers, live reservations, unsettled
   auction wins, outstanding kernel obligations). Remaining legacy gaps are narrower than the audit states
   (see tracker).
3. New migrations use 14-digit timestamp versions (`20260906HHMMSS_*.sql`) so they sort after both `main`'s
   `075` and production's `109`/`20260902003623`; each ships with a rollback under `supabase/rollbacks/`, an
   entry in `supabase/ci/assert_public_table_grant_decisions.sql`, and a deliberate Gate-2 count update.
4. No production write of any kind is performed by this program. Production reads were limited to catalog
   metadata (function bodies, grants, indexes, columns, ledger, edge versions) — no customer rows.
