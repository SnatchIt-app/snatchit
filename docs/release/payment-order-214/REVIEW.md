# Cross-rail fresh-money fence — registry 214

Candidate only. Depends on registry 212 / PR #272. No hosted apply or service deployment is implied.

A supported payment-scoped native admin refund could coexist with a marketplace payout allocation. Console-only 212 did not cover that native path. This package serializes fresh allocations at the existing payment row and uses persisted refund/action/payout intents across provider awaits. No database lock spans a network request.

- Payouts reconcile existing attempts before considering a new allocation. Fresh allocations refuse native refund intent.
- Fresh console refund claims refuse native intent and positive provider exposure, even when a later observation changes a native row to failed. Existing full-refund, chargeback and unresolved-state refusal precedence stays intact.
- Native refunds authorize immediately before both provider POST sites, including after a completed search found no refund. Existing provider GET, adoption and state sync remain available under a conflict.
- Payment-scoped empty-atom refunds remain valid. A payout-eligible but unpaid transfer is not treated as money already sent. Earlier bound native partial refunds are not double-counted against themselves.
- The service-only native gate adds one kernel function: kernel 161→162, five-schema routines 336→337. Exact named permission checks remain exhaustive; public Gate-2 counts do not change.

## Verification

Root ran 799 assertions across ten targeted SQL suites, including unchanged money-ledger behavior, exact ACL/census checks, funding cooldown, eligible-unpaid console controls and 23 cross-rail assertions. Four real two-session controls observed payment-row waits, rejected the committed opposite allocation and kept a different payment free. Removing the positive-provider guard makes assertion 23 fail. Earlier paired baseline and lock-removal controls are retained outside git.

Root also ran 60 edge/helper/payout tests, TypeScript checking, targeted lint and diff checks. Handler tests use the actual edge source with mocked provider transport: no Stripe call. The earlier independent review reproduced and corrected a paid-transfer/webhook deadlock; paid transfers now exit before taking the new payment lock.

The local database uses the existing plain PostgreSQL rehearsal bootstrap. It is not Supabase-stack certification. The full pinned-stack CI run, fresh exact integration review and approved sandbox/production rehearsal/readback remain required. Camera and App Store work are deferred.

## Recovery boundary

Do not remove an established financial fence. The 214 rollback file deliberately refuses on an applied candidate and succeeds only as a no-op on the exact unapplied 212 predecessor. Its deployed recovery is forward-only: stop new execution through the reviewed operating controls, retain this schema and reconciliation, and apply a reviewed correction. Historical 210 and 212 inverses refuse over 214. No rollback or setting change was performed on a hosted project.

Merge/application sequencing remains reviewed 212 → 213 → 214. Do not apply 212 alone: 214 also removes its unratified eligibility-only refund restriction. All migration-bearing merges require current deployment-setting evidence; the draft has no such claim.
