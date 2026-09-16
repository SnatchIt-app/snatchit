# KW — stripe-webhook native wiring (dispute arms, `transfer.reversed`) + payout-execute reconcile pass

Implementer W. `supabase/functions/stripe-webhook/native-dispute.ts` and the native dispute /
`transfer.reversed` branches in `supabase/functions/stripe-webhook/index.ts` were ALREADY WRITTEN and
typechecking before this task began. Nothing in those two files was rewritten — the legacy arms were
verified byte-identical (evidence below) and no bug was found that required touching them. This note
covers the REMAINING pieces this task owned: the `payout-execute` failed-payout reconcile pass, and the
tests, and this report.

Repo: `/Users/josetascon/snatchit-consol` @ branch `feature/venue-native-and-product-v2`. No production
access, no Supabase MCP calls, no Stripe API calls, no deploy, no git commit — per the task's hard boundary.

---

## 1. What was wired

### 1.1 stripe-webhook native dispute arms (pre-existing, verified not modified)

`index.ts` carries native-arm-first branches for `charge.dispute.created` (:1320), `charge.dispute.updated`
/ `.funds_withdrawn` / `.funds_reinstated` (:1426-1428), and `charge.dispute.closed` (:1440), each importing
the pure decision functions from `native-dispute.ts` (`resolveDisputeRail`, `planDisputeVerb`,
`disputeRecordArgs`, `disputeMarkArgs`, `classifyDisputeError`, `interpretRecordResult`,
`interpretMarkResult`, `buildDisputeCommandKey`). The native arm runs FIRST; the legacy arm — unchanged —
runs after, exactly as DESIGN_096 §2.1 specifies.

### 1.2 stripe-webhook `transfer.reversed` native routing (pre-existing, verified not modified)

`index.ts:665-746` is the native arm: `resolveTransferRail(tr)` discriminates the rail off the Transfer
object's own metadata/`transfer_group` (a Dispute carries none, a Transfer does — KH §4.3); on `route:
'native'` it reads the inline `reversals.data[]` via `readInlineReversals`, pages
`GET /v1/transfers/{id}/reversals` when `has_more`, merges with `mergeReversals`, builds one
`record_payout_reversal` call per reversal fact via `planReversalRecording`, and folds every per-reversal
`Decision` into one response via `aggregateDecisions`. `index.ts:1531` (legacy `mark_transfer_reversed`)
is untouched and still runs for anything `resolveTransferRail` routes `legacy`.

**Deviation from KH §4.6's table, and why it is not a bug.** KH's table names `mark_payout_transfer_state`
and `hold_payout_transfer_reversed` as the verbs the native arm calls. The SHIPPED code calls neither —
it calls `kernel.record_payout_reversal` for every reversal fact, per DESIGN_096 §2.2, which supersedes KH
here (096 R-3 is the ONE writer of a reversal fact and internally handles the `held` outcome for the
submitted-ref-not-yet-stored race, KE §4.3). My dispute test file pins the code AS SHIPPED, not KH's
pre-096 table rows; the file header says so explicitly.

### 1.3 payout-execute failed-payout reconcile pass (NEW — this task)

`supabase/functions/payout-execute/executor.ts` gained the pure planner `planFailedReconcile`
(`observedTransfer, reversals, groupRows, claim`) → `{ observed, refusalCode, outcome }`. It builds the
exact `p_observed` shape `kernel.reconcile_payout_transfer` reads and mirrors the verb's own
first-failing-predicate-wins derivation (096:1101-1120) LOCALLY, in the same order:
`ref_unresolvable → transfer_unresolvable → ref_mismatch → amount_ledger_mismatch → currency_mismatch →
destination_mismatch → transfer_group_mismatch → reconcile_ambiguous → reversal_malformed →
reversals_incomplete → reversals_inconsistent → reversal_exceeds_transfer`, else `clean` /
`full_reversed` / `partial_reversed`. It writes nothing and produces no Stripe request body under any
input — asserted directly in a test (`the plan carries no idempotency key and no request body`).

`supabase/functions/payout-execute/index.ts` gained a SECOND phase, run after the main
create/reconcile batch and independent of it: `claim_failed_payouts_for_reconcile(limit, lease_seconds)`
→ for each claimed row, `readTransfer` (`GET /v1/transfers/{stored_ref}`, 404 ⇒ `found:false`, any other
non-2xx ⇒ transient — logged via `note()`, no verb call, retried next tick once the lease expires),
`readAllReversals` (pages `GET /v1/transfers/{id}/reversals` up to 20 pages / 2000 reversals, a hard cap
against a runaway loop), `probeTransferGroup` (reused from the main pass, `GET /v1/transfers?transfer_
group=payout_<id>`) → `planFailedReconcile` → `kernel.reconcile_payout_transfer(...)`. The pass NEVER
writes `'failed'`, NEVER calls `POST /v1/transfers` (no idempotency key is ever built in this path), and
NEVER calls `mark_payout_transfer_state` directly — `reconcile_payout_transfer` is the sole writer of the
failed→paid edge. Every outcome is logged via the existing `note()` RPC; a `refused` result from the verb
(`transfer_unresolvable`, any `*_mismatch`, `reconcile_ambiguous`, any `reversals_*`) is paged via
`captureException('payout-execute:reconcile-refused', ...)`, matching 096's own comment that a terminal row
cannot be held, so the audit + page together ARE the operator hold (096:926-929). The main handler's JSON
response now carries a `reconciled: { claimed, results }` field alongside the existing `attempted/counts/
results`, and one failure in this phase never blocks the reply (`try { reconciled = await
runReconcilePass(...) } catch { await captureException(...) }`).

---

## 2. Exact RPC call shapes (cross-check against 096)

**`kernel.claim_failed_payouts_for_reconcile(p_limit integer, p_lease_seconds integer)`** — called as
`service.rpc('claim_failed_payouts_for_reconcile', { p_limit: limit, p_lease_seconds: leaseSeconds })`.
Response consumed: `{ payouts: [{ payout_id, stripe_transfer_ref, transfer_group, amount_minor, currency,
destination_ref, command_key }] }` — matches 096:992-1000 field-for-field. The edge additionally filters
the returned rows on `isUuid(payout_id) && typeof stripe_transfer_ref === 'string'` before using them
(defence against a malformed row, never a re-decision of eligibility).

**`kernel.reconcile_payout_transfer(p_payout_id uuid, p_stripe_transfer_ref text, p_observed jsonb,
p_command_key text)`** — called as:
```ts
service.rpc('reconcile_payout_transfer', {
  p_payout_id: claim.payout_id,
  p_stripe_transfer_ref: claim.stripe_transfer_ref,
  p_observed: plan.observed,
  p_command_key: claim.command_key,
});
```
`plan.observed` (from `planFailedReconcile`) is exactly: `{ found, id, amount, currency, destination,
transfer_group, reversed, amount_reversed, reversals: [{id, amount}], group_count }` — matches 096:941-944
field-for-field. `p_command_key` is the claim's own `command_key` (`payout.reconcile:<payout_id>`,
096:1000) — the edge never mints its own key for this verb, only for the `record_payout_execution_note`
audit calls it makes alongside (`claim.command_key`, unchanged shape). Response consumed:
`{ status, refusal_code?, payout_status? }` — matches the verb's `jsonb_build_object` returns at
096:1063-1065 (`noop_replay`), 096:1141-1143 (`refused`), 096:1180-1184 (`ok`).

Both RPCs are called against `kernelServiceClient()` — the SAME service-role, `db.schema: 'kernel'` client
the main batch already uses. Confirmed against 096's own grants block (096:1211-1219): both are
`service_role` only, consistent with every other RPC this function calls.

---

## 3. Legacy non-regression — git diff evidence

```
$ git diff --stat supabase/functions/stripe-webhook/index.ts
 supabase/functions/stripe-webhook/index.ts | 404 +++++++++++++++++++++++++++++
 1 file changed, 404 insertions(+)
```

Zero deletions, zero modifications to any existing line — the entire native dispute/`transfer.reversed`
wiring (and the pre-existing legacy arms it sits beside) is additive against the working tree's prior
state. `supabase/functions/stripe-webhook/native-dispute.ts` is a wholly new, untracked file (828 lines) —
nothing in it replaces or edits an existing module. I made NO changes to either file in this task.

My own changes are confined to `supabase/functions/payout-execute/executor.ts` (additive: one new
section, `planFailedReconcile` and its supporting types — no existing export's signature or behavior
changed) and `supabase/functions/payout-execute/index.ts` (additive: two new RPC name constants, five new
functions for the reconcile pass, one new phase appended after the existing batch loop, and one new
`reconciled` field added to the JSON response — no existing line in `executeOne`, the main `serve(...)`
claim loop, or any preflight function was altered).

---

## 4. Tests

**`tests/stripe-webhook-dispute.test.ts` (NEW, 89 tests).** Every row of KH §4.5 (the dispute decision
table: created/updated/closed × prior state → verb → response) and KH §4.6 (`transfer.reversed`, walked
through the AS-SHIPPED `record_payout_reversal`-based implementation rather than the superseded verb names
— see §1.2 above) as `it` cases, importing the pure helpers directly from `native-dispute.ts`:
`resolveDisputeRail` (null PI, absent row, legacy mode, native mode, livemode false on either side),
`disputeStatusKnown` (`'prevented'` → false, the full 8-label CHECK set), `planDisputeVerb`,
`classifyDisputeError` (`state_conflict` → ack+alert, differentiated `native_dispute_stale_update` vs
`native_dispute_terminal_conflict` by event kind; `not_found`/P0002 → ack+alert, differentiated
`native_dispute_payment_not_found` (verb=record) vs `native_dispute_race_unresolved` (verb=mark);
`invalid_input` → ack+alert; `42501`/`PGRST202` → retry+alert; transient `40001`/`53300`/`57P01`/`08006`/
`40P01`/`55P03`/`XX000` → retry, no alert; unclassified → retry+alert), `buildDisputeCommandKey` (exact
shape, ≤64 chars and regex-safe even against a 200-char foreign event id, sanitizes rather than throws),
`resolveTransferRail` (native metadata, legacy metadata, group-only, group+metadata agreeing, group+
metadata naming different payouts, both rails claiming the object, neither claiming it, partial native
metadata, a non-uuid `metadata.payout_id`, null/undefined input), `planReversalRecording` (one call per
reversal fact in order, multi-reversal events, malformed transfer id, non-uuid payout id, unreadable
`amount_reversed`, the empty-list-while-money-came-back case that must ACK+alert rather than invent a
`trr_`), plus `interpretReversalResult`, `classifyReversalError`, `aggregateDecisions`, `readInlineReversals`,
and `mergeReversals`.

**`tests/payout-executor.test.ts` (EXTENDED, +25 tests).** `planFailedReconcile`'s full derivation table:
`p_observed` shape for `found:false` and for a clean found transfer; every refusal code in the verb's own
order (`ref_unresolvable` on a malformed STORED ref, `transfer_unresolvable` on a 404, `ref_mismatch` when
Stripe answers for a different id, `amount_ledger_mismatch` including a MISSING amount failing closed,
`currency_mismatch` — and that the comparison is case-insensitive, `destination_mismatch` — and that a
null observed destination is skipped rather than refused, `transfer_group_mismatch`, `reconcile_ambiguous`
for both `group_count > 1` and `group_count = 0`, `reversal_malformed`, `reversals_incomplete` (both a
short list and a wholly empty one while `amount_reversed > 0`), `reversals_inconsistent` (sum exceeds
`amount_reversed`), `reversal_exceeds_transfer`); the three non-refused outcomes (`clean`, `full_reversed`
via a single reversal and via two partials summing to the full amount, `partial_reversed`, and the
`reversed:true`-with-no-amount fallback mirroring 096:307's own SQL fallback); and a structural assertion
that the plan never carries an idempotency key or a request body.

---

## 5. Verification (verbatim)

```
$ npm run typecheck
> snatchit@1.0.0 typecheck
> tsc --noEmit -p .
(no output — clean)

$ npm run lint
> snatchit@1.0.0 lint
> expo lint
✖ 45 problems (0 errors, 45 warnings)
```
All 45 lint warnings are pre-existing, in files this task never touched (`app/(tabs)/home.tsx`,
`app/(tabs)/profile.tsx`, `app/checkout/[id].tsx`, `src/screens/ListingDetailScreen.tsx`, etc. — mostly
`react-hooks/exhaustive-deps` and a few unused-eslint-disable directives). Zero errors, zero warnings in
`supabase/functions/payout-execute/*`, `tests/payout-executor.test.ts`, or
`tests/stripe-webhook-dispute.test.ts`.

```
$ npx vitest run
 Test Files  11 passed (11)
      Tests  489 passed (489)
```
Baseline (before this task's test additions) was 375 tests. New total is 489 — a delta of 114, matching
89 (new `stripe-webhook-dispute.test.ts`) + 25 (extended `payout-executor.test.ts`) exactly. All 489 pass;
none skipped, none weakened.

---

## 6. What this task did NOT do (recorded per DESIGN_096 §3, unchanged)

No booking of `unlined_reversal` from the webhook; no `prevented` in the kernel CHECK; no late-win
(lost→won) representation; no promoter payout/hold/destination change; no change to
`mark_payout_transfer_state`, `rearm_failed_payout`, `request_org_payout`, or
`hold_payout_transfer_reversed`. `supabase/migrations`, `supabase/rollbacks`, `supabase/tests`, and every
other agent's `docs/phase2/_impl/K*.md` were not touched. No git commit was made.
