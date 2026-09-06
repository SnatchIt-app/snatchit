# Account deletion with live-rail money obligations — option B (accept, communicate pending, block the terminal)

Preferred implementation for the draft (owner direction 2026-09-06). Code commit `972619f`; migration
`20260906130000_deletion_sweep_live_rail_obligations.sql`; edge `supabase/functions/delete-account/index.ts`;
governance filing `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` (PFA-32, owner signature pending).

## 1. Does option B preserve the ratified deletion policy? — YES, clause by clause

| Ratified clause (`DELETION_STATE_MACHINE_SPEC.md`) | Option B behaviour | Where |
|---|---|---|
| §1.2 entry: a request from ACTIVE is **accepted**; entry writes `DELETION_PENDING`, `deletion_requested_at`, operator-legible `deletion_block_reason` | unchanged — `kernel.request_account_deletion` (077) is not modified; the edge always calls it and returns `{success:true, …}` | `delete-account/index.ts:236`, tests `tests/delete-account.test.ts` |
| §1.2 "the account must remain usable while pending" | unchanged — no new refusal anywhere on sign-in or disposal paths | no edge/RPC other than the sweep changed |
| §1.2 acquisition freeze F-1..F-7 | unchanged — F-5 guards in `create-payment-intent` / `confirm-and-release` kept verbatim from production | `09_CONVERGENCE.md` §2 |
| §1.2 payout processing **preserved** ("PAY if payable else HOLD — never silent forfeiture") | strengthened: payable payouts to a pending-deletion seller are paid through the attempt ledger; unpaid ones BLOCK the terminal (BP-13 `unpaid_seller_obligation`) instead of being forfeited by erasure | 120000 `claim_payout_attempt` has no deletion refusal; 130000 BP-13 |
| §1.2 dispute/refund processing **preserved** | unchanged; refunds in flight block the terminal (`pending_refund`), never the request | 120000 `account_deletion_blockers` |
| §1.2 exit 1: user **withdrawal** | unchanged — `action:'withdraw'` path and the client's Withdraw button | `delete-account/index.ts`, `app/settings/index.tsx:167` |
| §1.2 exit 2: the sweep tombstones only when **every predicate is false**; resolution is "event, scan, or settlement — never the user"; "nothing is silently discarded" | BP-13 appended AFTER BP-12 in `kernel.sweep_deletion_pending` (078 body verbatim + one call site); every BP-13 token resolves by settlement/refund/payout/review, never by user action | 130000; `supabase/tests/125` (28) |
| §2 closed-world predicate set | AMENDED by one arm — filed as a post-freeze amendment requiring owner signature (the set is ratified) | `POST_FREEZE_AMENDMENTS.md` PFA-32 |
| §4.7 completion notice | unchanged (emitted at ERASED by the existing terminal effects) | 078 |

Deviation from the ratified text: **none in behaviour**; one **addition** to the predicate set (BP-13), which is exactly
the kind of change the amendment register exists for. Option A (409 at request) would have deviated from §1.2's
acceptance rule; it is not implemented.

## 2. How each obligation is resolved (what clears BP-13, and who acts)

`public.account_deletion_block_reason(identity)` returns `NULL` or `BP-13: unsettled live-rail money obligation (<tokens>)`.
Tokens (120000 `account_deletion_blockers`):

| Token | Meaning | Resolves by | Actor / path |
|---|---|---|---|
| `pending_payment` | a `pending` capture younger than 24 h (buyer) | success → settlement; failure/cancel → row `failed` | webhook / `pending_stale` sweep / `confirm-payment`; nothing to do manually inside 24 h |
| `paid_no_transfer` | `succeeded` capture with no transfer row (buyer or seller) | `settle_verified_payment` creates the transfer, or the capture is refunded (unfulfillable) | sweep `paid_unsettled` (automatic, 5-min age) or operator: Part 1 of `DAY5_MANUAL_REFUND_PLAYBOOK.md` |
| `active_transfer` / `unsettled_transfer` | transfer not terminal (pending / seller_sent / disputed / released-unpaid) | seller sends → buyer confirms or auto-release → payout; dispute resolves; expiry refunds | transfer lifecycle (`confirm-and-release`, `enforce-transfer-expiry`); dispute ruling (playbook Part 1/2) |
| `unpaid_seller_obligation` | released transfer, `payout_released_at IS NULL` | payout attempt succeeds (or dispute/refund closes it) | automatic (`confirm-and-release`, sweep); operator: playbook Part 2 (attempt protocol) |
| `pending_refund` | refund started at Stripe, not yet landed / a compensation refund in progress | `charge.refunded` → `record_payment_refund` | webhook; operator SQL fallback in playbook Part 1 |
| `reversal_required` | an attempt paid money that must come back (duplicate / paid during dispute / refunded after payout) | Stripe transfer reversal → `mark_transfer_reversed`, or operator `release` decision after review | `transfer.reversed` webhook; operator: playbook EMERGENCY section |
| `open_manual_review` | a `payout_decisions.manual_review` row without a later decision | operator records the resolving decision (release / hold lapse / refund) | admin: `admin_release_held_payout` (039) or refund path |

Ratified arms BP-1..BP-12 are evaluated first and keep their own clearing paths (spec §2); BP-13 only ever adds a reason.

## 3. Operational path for stuck requests

Monitoring (service_role / SQL editor), run daily:
```sql
select e.identity_id, e.deletion_requested_at, now() - e.deletion_requested_at as pending_for, e.deletion_block_reason
  from kernel.identity_ext e
 where e.deletion_state = 'DELETION_PENDING'
 order by e.deletion_requested_at;
-- live-rail detail for one identity:
select * from public.account_deletion_blockers('<identity_id>');
```
Alert threshold (recommended): any request pending > 14 days, or any `deletion_block_reason` unchanged for 7 days.

Runbook per reason: §2 above — the operator performs the **platform act that settles the obligation** (settle, refund,
pay, reverse, resolve the review). Two rules:
1. **Never edit `kernel.identity_ext` or force the terminal.** There is deliberately no force-erase; the guards refuse
   direct writes to money columns, and a tombstone with money outstanding would violate "nothing is silently discarded".
2. **The person always keeps the exit they control**: withdrawal (Settings → Withdraw request), which returns the account
   to ACTIVE with nothing lost. Support may tell them exactly what is pending (`pending_obligations`) and that completion
   follows automatically once it settles.

Escalation: an obligation that cannot be settled by any of the paths in §2 (e.g. a seller with no payout account for an
unpaid obligation and no reply) is an **owner decision** recorded in the incident log: refund the buyer / write off via
the refund path, or hold — never a manual erase. The daily report above is the queue.

## 4. Communication that completion is pending

- Edge: `delete-account` returns `pending_obligations: [...]` (or `obligations_check: 'unavailable'`) alongside
  `success:true` — additive, so build 13 keeps working.
- Client (this RC, next build): the settings screen now shows the acceptance message BEFORE signing the user out, listing
  what must settle when the response carries obligations, and the pending-state view (already in build 13) exposes
  Withdraw. Build 13 users receive the accepted request and see the pending state on next sign-in; the obligation list
  is visible to support via the SQL above until the client update ships.
