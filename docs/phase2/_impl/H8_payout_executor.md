# H8 — the venue payout executor

**Status:** implemented, **NOT DEPLOYED**, **NOT SHIPPABLE YET** (see §9). **Scope:** backend only.
**No Stripe API call, no production mutation, no deploy, no config change and no money movement was
performed to produce this.** Every DB result below comes from a local rehearsal database
(`snatchit_rehears_payout`, 108 migrations replayed, my slice changes applied on top).

Implements ruling **H3** (`H3_transfer_cardinality.md`), agent **F**'s destination findings (**H6**)
and agent **D**'s maturity findings (**D-1/D-2**), relayed to me mid-task.

---

## 1. The executor contract

`supabase/functions/payout-execute/` — `executor.ts` (pure, vitest-testable) + `index.ts` (Deno I/O
shell). Machine-only: cron secret or service-role key, no human arm, one Supabase client.

```
1. CLAIM        kernel.claim_payouts_for_execution(limit, lease_seconds)
                → [{payout_id, execution_mode, attempt, command_key}]
2. CONTEXT      kernel.get_payout_execution_context(payout_id)
                → {execution_eligible, refusal_code, amount_minor, destination(pinned),
                   org_connect_ref_current, transfer_group, …}
3. PREFLIGHT A  GET /v1/accounts/{dest}     — capabilities.transfers must be 'active'
4. PREFLIGHT B  GET /v1/balance             — MANDATORY, H3 §3.5
5. RECONCILE    GET /v1/transfers?transfer_group=payout_<id>   (execution_mode='reconcile' only)
6. CREATE       POST /v1/transfers          — Idempotency-Key: payout_<id>_<dest>_v1
                amount/currency/destination/transfer_group/metadata; NO source_transaction
7. RECORD       kernel.mark_payout_transfer_state(id,'paid',tr.id,null,command_key)
                → fires venue.on_payout_settled → settlement closed→paid
```

Steps 1–5 are side-effect-free at Stripe. **That ordering is enforced by the types, not by
discipline:** `planPayoutTransfer` cannot produce an idempotency key; only `authorizeTransfer` can,
and it takes both preflight verdicts as required arguments.

**The worker chooses nothing.** No request field names an amount, destination, org, settlement,
currency or key — `assertNoClientMoneyReference` refuses a request that contains one. The amount is
`kernel.payout.amount_minor` (the waterfall `close_settlement` already computed; never recomputed
here); the destination is `kernel.payout.destination_ref`; the command key is DB-derived
(`payout.execute:<payout_id>`); eligibility is the DB's `execution_eligible` verdict.

## 2. The claim model

`kernel.claim_payouts_for_execution(p_limit, p_lease_seconds)` mirrors Agent A's
`claim_refunds_for_execution` line for line (same house pattern: clamped operands, `for update skip
locked`, lease = an immutable `kernel.admin_audit` row, no subject parameter at all).

Eligible set: `cause='settlement'` ∧ `payee_kind='organization'` ∧ `status='submitted'` ∧
`hold_state='none'` ∧ `stripe_transfer_ref is null` ∧ `destination_ref is not null`.

`execution_mode` is the load-bearing part: `'create'` while the first claim is inside a 20-hour
window (4h of margin on Stripe's 24h key retention), `'reconcile'` after. In reconcile mode the
executor **must** read the transfer group before it is permitted to create — and
`authorizeTransfer` fails closed if that read is missing. Test
`WITHOUT reconcile mode, a >24h retry WOULD double-pay` demonstrates the hazard the mode removes.

## 3. Dangerous failure modes and how each is handled

| Mode | Handling | Row ends |
|---|---|---|
| Stripe timeout after create | write nothing; same key replays and returns the same object; >24h the `transfer_group` read adopts it | `submitted` |
| Success then DB write fails | write nothing, don't compensate; next tick replays same key, `mark_..._state` noop-replays | `submitted` |
| Concurrent workers | claim lease + one deterministic key ⇒ one transfer; the state-sync loser classifies `payout_state_backwards` as **converged**, not an error | one ref |
| Stale claim | lease expires, row returns in `reconcile` mode, orphan adopted | `submitted`→`paid` |
| Balance insufficient | **refused at preflight; the key is never spent**; note written; later attempt with the same key succeeds | `submitted` |
| Disconnected/deleted account | account probe → `destination_deleted`, no Stripe write | `submitted` |
| Transfers disabled | `capabilities.transfers ≠ 'active'` → refuse, key unspent (`payouts.ts:96` precedent) | `submitted` |
| Destination changed mid-flight | **de-authorize** (§4) | `pending` + `held` |
| Wrong organization | `settlement.org_id ≠ payout.payee_org_id` refused in DB *and* in the plan | `submitted` |
| Amount tampering | DB requires `payout.amount_minor = settlement.net_minor`; executor asserts the same; a mutated amount under a spent key returns `idempotency_error` (never retried blind) | `submitted` |
| Personal-seller Connect account | DB checks `profiles.stripe_connect_id` + the 044 archive | `submitted` |
| `failed`-state attempt | **structurally impossible** (§5) | n/a |

Every non-success writes `kernel.record_payout_execution_note` — an immutable audit row, no state
change — so a repeatedly-refused payout is visible rather than indistinguishable from an
un-attempted one.

## 4. Destination: bind at claim, re-verify at execution (H6)

`kernel.payout` gained **one column, `destination_ref`** (+ an `acct_…` shape CHECK), written by the
two `pending→submitted` arms of `request_org_payout` — verified to be the *only* writers of that
status. The executor sends the **pinned** value, never a fresh read, because the payee was approved
behind SoD-1, maturity, aal2 and (above threshold) a second approver; a later re-point passed none
of those. It then asserts, fail-closed: pinned == current ref, `connect_transfers_active`,
`organization.status ∈ (approved, active)`, cool-down not active, plus Stripe's live capability.

On divergence the executor calls `kernel.hold_payout_destination_changed`, which **re-derives the
fault itself** (a worker cannot demote a healthy payout — it raises `no_destination_fault`) and
moves the row `submitted → pending` + `held/destination_changed`. That is the only backward status
edge in the system and it is safe because it moves *away* from executability and is released by the
existing `kernel.release_payout` path. It is **not** `failed`.

> **This overrides H3 §4 ("kernel.payout columns: NONE") and the 093 header's "0 DDL on any
> money-ledger table" / "2 new columns, both on kernel.organization".** Those were written before F
> executed the race. **Someone must update the header text in `scripts/assemble_093.sh`** — I did
> not, because the assembler is yours and the G4 integrity gate compares its output byte-for-byte.

## 5. What I verified about the absorbing `failed` state

Executed against the **shipped** `kernel.mark_payout_transfer_state` on the rehearsal DB:

```
submitted → failed    ok
failed → paid         ERROR precondition_failed: payout_state_backwards (failed → paid)
failed → reversed     ERROR precondition_failed: payout_state_backwards (failed → reversed)
failed → submitted    ERROR invalid_input: ... takes paid|failed|reversed
```
Functions whose bodies UPDATE `kernel.payout`: `hold_payout`, `release_payout`,
`record_dispute_native` (all `hold_state` only), `mark_payout_transfer_state`, `request_org_payout`.
`request_org_payout` selects only `status in ('pending','submitted')` (0 rows for a failed payout);
re-mint is blocked by `on conflict (idempotency_key) do nothing`. **Confirmed: no exit from
`failed`; D-2's HIGH rating is correct.**

Two things I found beyond H3: `kernel.hold_payout` is **not granted to service_role at all**
(`has_function_privilege('service_role', …) = false`), so escalation genuinely cannot be a hold; and
a held row refuses the state sync with **both columns untouched**, so a hold racing the callback
cannot half-write.

The executor's guarantee is structural, not stylistic: `PAYOUT_STATE_SYNC_TARGETS === ['paid']` and
`PayoutStateSyncStep.new_status` is that single-member type. A test drives every Stripe outcome
(success, 8 error codes, transport failure, reversed-on-arrival, malformed id) and asserts the
attempted target set contains only `'paid'`.

## 6. Maturity is now an invariant, not a snapshot (D-1)

The eight G2 predicates moved verbatim into **`kernel.settlement_payout_maturity(uuid)`**, called
from **three** sites: `close_settlement` (the mint), `request_org_payout` (immediately before the
advance *and* before the park — new result member `maturity_held`), and
`get_payout_execution_context` (immediately before the transfer). One definition, three calls, so
the evaluations cannot drift. `10d` keeps its full commentary; its inline block is now four lines.

I added one predicate the mint cannot carry: **`refund_exposure_stale`** — per covered order,
`least(Σ succeeded refunds, order face) − Σ lined refund_void`. **The face cap is load-bearing**: a
raw refund sum vs `refunds_minor` would fire on every ordinary fee-bearing refund (refunds are
measured against `payments.total = amount + buyer_fee`, `refund_void` is capped at face under A5)
and strand the venue's money — a false positive here is the same permanent loss by another route.

Not duplicated, per D: settlement-closed, destination-non-null, obligation-positive, no-prior-payout.

## 7. Files

| Path | Change |
|---|---|
| `docs/phase2/_impl/093_parts/10_money_settlement.sql` | **10d** rewired onto 10m (4-line splice, declares trimmed); **10j** `kernel.payout.destination_ref` + CHECK; **10k** `request_org_payout` CREATE OR REPLACE (pin + maturity guard); **10l** `settlement_covered_payments`; **10m** `settlement_payout_maturity`; **10n** `get_payout_execution_context`; **10o** `hold_payout_destination_changed`; **10p** `claim_payouts_for_execution`; **10q** `record_payout_execution_note`. All new verbs `revoke all … from public, anon, authenticated` + `grant … to service_role`. |
| `supabase/functions/payout-execute/executor.ts` | pure logic |
| `supabase/functions/payout-execute/index.ts` | Deno shell (not deployed) |
| `tests/payout-executor.test.ts` | 57 tests |

`supabase/migrations/093_primary_ticketing.sql` was **not** touched — re-assemble it.

## 8. Test results

- `npx vitest run tests/payout-executor.test.ts` → **57 passed**.
- `npx vitest run` (full suite) → **375 passed, 10 files**, no regression.
- `tsc --noEmit --strict` on `executor.ts` → clean.
- DB probe on the rehearsal database → the full refusal ladder, one code each, first-failing-wins:
  `destination_changed`, `org_not_active`, `connect_transfers_inactive`, `destination_cooldown`,
  `amount_ledger_mismatch`, `org_mismatch`, `destination_individual_plane`, `maturity_not_elapsed`,
  `event_cancelled`, `refund_in_flight`, `refund_exposure_stale`, `unbounded_refund_exposure`,
  `payout_held`, `transfer_already_recorded`, `destination_not_bound`, and a promoter-commission
  payout **not claimed**. Plus: unknown payout id → SQL NULL (non-enumerable); claim exclusivity
  (second claim inside the lease returns 0); de-authorization → `pending/held/destination_changed`,
  then unclaimable and refused by `mark_payout_transfer_state`; `no_destination_fault` on a healthy
  payout; the note verb changes no state; grants are `service_role`-only on all five verbs.

## 9. What I could not verify without deployment — and the shipping gate

- **No Stripe call was made.** Transfer/account/balance/transfer-group behaviour is mocked from the
  documented API. Real `/v1/balance` shape, `capabilities.transfers` timing and Stripe's actual key
  retention are unverified.
- **The rail is untestable end-to-end today:** `kernel.set_org_payout_destination` still has zero
  callers, so no org has a destination (H3 §8).
- **Fresh-chain replay:** my changes were applied on top of an already-replayed DB, not through a
  regenerated 093. Re-assemble and re-run `rehearsal_reset.sh`.
- **Concurrency is simulated.** `skip locked` exclusivity was probed single-session.

**SHIPPING GATE — say this to the owner plainly.** D is right that post-payout loss is currently
tolerable *only because no payout executor exists*: nothing calls `request_org_payout`,
`mark_payout_transfer_state` or `release_payout`, and no cron does either. This function is what
removes that protection. D executed the loss (sold 23000, paid 19000, entitled 13000, platform loss
6000); of six possible accounting outcomes only "platform absorbs" is implemented, and "future
payout offset" exists only accidentally — silently confiscating the venue's later revenue while
destroying the excess. **Therefore: the D-1 fix (done here) *and* a receivable/reserve object (NOT
done — it is a 094 schema question) are preconditions of SHIPPING an executor, distinct from writing
one. Deploying this without the receivable object is not safe.** Two further preconditions:
`destination_ref` must land **before** `payout.dual_control_min_minor` is ever set (X-12 currently
parks every payout, and the approval row is the only thing pinning the destination today — setting
that key creates the exposure), and the `failed → submitted` re-arm from H3 §8.1 should land in 094
so a future operator is not one bad write away from destroying an obligation.
