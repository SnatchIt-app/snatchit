# 212 local console money coordination candidate

Base: main `e250305d2532a7436c2258bbdd72cde16bbb56bf`. Migration 212 is a local draft, applied only to disposable PostgreSQL databases. No hosted query, migration application, flag change, provider request, deployment or merge was performed.

## Scope and lock order

The shared transaction key is `hashtextextended('ops_money_order:' || payment_id, 0)`. These are the participating writers:

| Entry | Current predecessor | New order |
|---|---|---|
| ops.execute_action | 144 | Validate/authenticate, resolve payment, advisory key, key replay, action insert, precheck |
| ops.approve_action | 118 | Unlocked identity read, advisory key, action row, validate identity/payment binding, approval row, action_run |
| ops.action_run | 115 | Unlocked identity read, advisory key, action row, validate identity/payment binding, dispatch |
| ops.action_dispatch | 154 marketplace safety | Advisory key before payment/transfer row locks; same key reentrant through action_run |
| ops.executor_claim | 199 | Service authentication, unlocked identity read, advisory key, action row, validate identity/payment binding, original gates |
| public.claim_payout_attempt | 210 | Unlocked payment lookup, advisory key, transfer row, validate payment binding, open attempt reconciliation, fresh-refund guard, original eligibility/cooldown/insert |
| ops.action_precheck | 118 | Read-only guard called inside execute_action's key; remains STABLE |

Console money entries accept only READ COMMITTED, since statements after waiting must see the previous holder's committed action. Both same-type and cross-type unsettled console actions are refused as `duplicate_unsettled`, before the released-payout refusal. The unsettled states are requested, awaiting_approval, processing, unknown, succeeded_at_provider. Terminal succeeded/failed/rejected actions do not block. No automatic expired-approval sweep or index is added; an expired pending approval continues to block until its existing approval/denial path settles it.

A console refund is refused when its transfer carries payout_released_at or stripe_transfer_id, a release decision (buyer_confirmed, auto_released or reversed), or a payout attempt in claimed/requested/unknown/succeeded/reversal_required. Failed-not-created payout attempts alone are not a payout marker; the independent transfer release decision still applies. No cancelled payout-attempt state exists in the current state constraint. Previously-sent executor_claim actions keep 199's list-before-POST reconciliation path; a fresh historical action is checked. Open marketplace payout reconciliation always precedes the new REFUND_IN_FLIGHT check. The hourly funding cooldown and seller-win/buyer-confirmed policies are preserved.

## Explicit release dependency and writers outside this package

This is console-refund/marketplace-payout coordination, not universal exclusion. kernel.admin_refund accepts payment-scoped fee refunds with empty atoms; kernel.claim_refunds_for_execution and native refund-execute can therefore operate on the same legacy payment without ops.action. The native kernel producers/executor do not share 212's key or released-payout guard. A separate coherent 214 package must review the frozen architecture and close that overlap before a universal money-release verdict. Native 199 bodies are unchanged; only its ops.executor_claim body is adapted.

public.record_payment_refund / record_refund_state, payout outcome/reconciliation writers, Stripe Dashboard actions, and legacy record_transfer_payout remain outside the shared key. A database transaction lock cannot cover the network wait after an RPC commits, nor an unobserved Dashboard refund. Existing provider idempotency and reconciliation remain essential. Direct privileged DML can bypass the RPC protocol. Rollout needs a quiescent owner-reviewed window, since already-running predecessor functions finish with their original bodies.

## Evidence

Fresh local plain PostgreSQL replay: 206 migration files, including 212, with the repository's local scaffolding. This is not evidence from the pinned Supabase CLI/real Supabase stack. Six targeted suites pass 271 assertions: 280 (16), 279 (9), 268 (103), 122 (74), 215 (43), 216 (26). Version-agnostic 280 on exact rolled-back predecessor bodies fails 9/16 assertions with zero SQL errors, including duplicate priority, inverse payout blocking, approval recheck and fresh historical executor guard. The edge regression first failed with db_error, then payout-attempts and payout-races passed 42 tests after expected-refusal mapping was added.

The six-entrypoint real PostgreSQL concurrency probe holds the shared key in one transaction, observes a second transaction waiting on advisory, and proves a third transaction can NOWAIT-lock the relevant action/transfer/payment rows. All six pass. Removing only the advisory-lock call from the candidate makes all six fail. This proves shared entry serialization and row-before-advisory inversion detection; it does not simulate Stripe network races or prove the excluded native writers.

Rollback has exact candidate preflight hashes, restores all seven immediate predecessor bodies (including 199 and 210), and checks their exact hashes. Reapplication restores the exact candidate snapshot. Seven OIDs, ACLs, owner, security-definer flags, search_path, volatility and argument names match across candidate/rollback/reapply. Candidate preflight and postflight pin all seven function bodies. No object or grant is added, so public census/grant manifests remain unchanged. Test 268's executor hash is updated to 212; its seven native kernel hashes remain exact.

Local receipts: `/Users/josetascon/.codex/visualizations/2026/09/05/01a072ba-18ad-7dd0-839c-49d717ea7d24/a212-payment-order-20261118/` (pgTAP green/red, edge green, concurrency green/lock-removed red, rollback/reapply logs, body/ACL/OID snapshots).
