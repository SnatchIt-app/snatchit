# KM1 — migration 096 implementation note (payout reversal + obligation recovery)

Implementer M1. Migration `supabase/migrations/096_payout_reversal_and_obligation_recovery.sql` was
ALREADY WRITTEN and verified to apply before this task began (per the task brief: "full-chain replay
green, Gate-2 27/70/37/26, +9 kernel functions, +2 kernel tables"). This note does not modify 096. It
adds the two files 096 itself specifies as owed (`supabase/rollbacks/096_..._rollback.sql`,
`supabase/tests/162_...sql`) and reports on both, plus the deltas 096 forces and any deviation between
[`DESIGN_096.md`](../../../../private/tmp) §1 (the orchestrator's spec) and what 096 actually shipped.

Repo: `/Users/josetascon/snatchit-consol` @ branch `feature/venue-native-and-product-v2`. Verification ran
on a private rehearsal database (`snatchit_rehears_m1f`, created via `scripts/rehearsal_reset.sh`), never
against production, never via the Supabase MCP tools, no deploy, no commit.

---

## 1. What 096 built (objects, signatures, refusal codes)

| Ref | Object | Signature | Grant class |
|---|---|---|---|
| R-1 | `kernel.payout_reversal` (table) | `reversal_id, payout_id, stripe_transfer_ref, stripe_reversal_ref, amount_minor, currency, source, observed, command_key, created_at` | RLS on, zero policies, deny-all incl. service_role |
| R-1 | `kernel.payout_reversal_guard()` (trigger fn) | BEFORE INSERT/UPDATE/DELETE | nobody |
| R-1 | `kernel.payout_reversed_minor(uuid)` | returns `bigint`, STABLE definer | service_role |
| R-2 | `payout_stripe_transfer_ref_uq` | partial unique index on `kernel.payout(stripe_transfer_ref) WHERE NOT NULL` | n/a (index) |
| R-3 | `kernel.record_payout_reversal(uuid, text, text, integer, jsonb, text)` | `(payout_id, tr_, trr_, amount_minor, observed, command_key)` → jsonb | service_role only |
| R-4 | `kernel.organization_obligation_recovery` (table) | `recovery_id, obligation_id, amount_minor, currency, source_kind, source_ref, recorded_by, command_key, created_at` | RLS on, zero policies, deny-all incl. service_role |
| R-4 | `kernel.organization_obligation_recovery_guard()` (trigger fn, BEFORE) | append-only + Σ-cap + org/currency checks | nobody |
| R-4 | `kernel.organization_obligation_recovery_settle()` (trigger fn, AFTER INSERT) | flips obligation to `recovered` when Σ = amount | nobody |
| R-4 | `kernel.obligation_outstanding_minor(uuid)` | returns `bigint` | service_role |
| R-4 | `kernel.org_outstanding_obligation_minor(uuid)` | **re-created, body only** — now nets Σ recoveries | service_role (ACL preserved by `create or replace`, not restated) |
| R-5 | `kernel.record_obligation_recovery(uuid, integer, text, text, text, text)` | `(obligation_id, amount_minor, source_kind, source_ref, reason_code, command_key)` → jsonb | **authenticated only**, service_role explicitly revoked |
| R-6 | `kernel.resolve_organization_obligation(uuid, text, text, text)` | **re-created** — same signature | **authenticated only** (was service_role-only in 094 — KD P1-1 fix), service_role explicitly revoked |
| R-7 | `kernel.claim_failed_payouts_for_reconcile(integer, integer)` | `(limit, lease_seconds)` → jsonb work list | service_role only |
| R-7 | `kernel.reconcile_payout_transfer(uuid, text, jsonb, text)` | `(payout_id, stripe_transfer_ref, observed, command_key)` → jsonb | service_role only |

**Refusal codes, as shipped (quoted from the bodies, not the design memo):**

- `kernel.payout_reversal_guard`: `append_only`; `not_found: payout %` (P0002); `precondition_failed: not an organization settlement payout — cause=% payee_kind=%`; `conflict_locked: transfer_ref_mismatch`; `precondition_failed: payout_state_not_reversible`; `precondition_failed: currency_mismatch`; `precondition_failed: reversal_exceeds_transfer`.
- `kernel.record_payout_reversal`: shape errors (`invalid_input: …`); `not_found: payout %` (P0002); `precondition_failed: not an organization settlement payout`; `conflict_locked: reversal_ref_bound_elsewhere`; `precondition_failed: payout_failed_reconcile_required`; `precondition_failed: payout_not_executed`; statuses returned: `noop_replay`, `held`, `ok` (with `payout_status` ∈ `paid|reversed`).
- `kernel.organization_obligation_recovery_guard`: `append_only`; `not_found: obligation %` (P0002); `precondition_failed: obligation_written_off`; `precondition_failed: currency_mismatch`; `precondition_failed: recovery_exceeds_debt`; `invalid_input: … trr_… reference`; `not_found: reversal_not_found` (P0002); `precondition_failed: reversal_org_mismatch`; `precondition_failed: recovery_exceeds_reversal`; `invalid_input: … receipt/ticket reference of 1-128 characters`.
- `kernel.record_obligation_recovery`: `insufficient_privilege: authenticated actor required` (42501, `v_uid is null`); `insufficient_privilege: platform_risk or platform_admin required` (42501); `step_up_unavailable`; `step_up_required`; `invalid_input: bad_amount` / `source_kind must be transfer_reversal|manual` / `source_ref is mandatory` / `command_key must match …`; `precondition_failed: bad_reason_code`; `not_found: obligation %` (P0002); `conflict_locked: command_key_bound_elsewhere`; `conflict_locked: recovery_source_already_linked`.
- `kernel.resolve_organization_obligation` (re-created): `insufficient_privilege: …` (42501); `step_up_unavailable`; `step_up_required`; `invalid_input: resolution must be recovered|written_off`; `not_found: obligation %` (P0002); `state_conflict: obligation % already % — terminals are exclusive`; **new** `precondition_failed: recovery_facts_required — record recoveries via kernel.record_obligation_recovery; status becomes recovered when Σ = amount (% of % recorded)`.
- `kernel.reconcile_payout_transfer`: `invalid_input: …`; `not_found: payout %` (P0002); `precondition_failed: not an organization settlement payout`; `precondition_failed: no_transfer_recorded`; `precondition_failed: payout_not_failed` (or `noop_replay` if already paid/reversed with the same ref); `precondition_failed: payout_held` (structurally unreachable); refusal codes returned in the JSON (`status:'refused', refusal_code:`): `ref_unresolvable`, `ref_mismatch`, `transfer_unresolvable`, `amount_ledger_mismatch`, `currency_mismatch`, `destination_mismatch`, `transfer_group_mismatch`, `reconcile_ambiguous`, `reversal_malformed`, `reversals_incomplete`, `reversals_inconsistent`, `reversal_exceeds_transfer`.

---

## 2. Files added this task (disjoint from other agents' 097/098/099/edge work)

1. `supabase/rollbacks/096_payout_reversal_and_obligation_recovery_rollback.sql` — break-glass, forward-fix
   posture (095's own house pattern): refuses to run while any row exists in either new table
   (`kernel.payout_reversal` or `kernel.organization_obligation_recovery`) — both are append-only evidence
   of money already observed or a receipt already declared, and the rollback has no way to preserve either
   once the tables are gone. `set local row_security = off` before the count, matching 095's rollback
   comment verbatim (both tables are RLS-on/deny-all so a non-owner runner would otherwise count 0 and the
   guard would fail open). Drop order: (a) restore `kernel.resolve_organization_obligation` and
   `kernel.org_outstanding_obligation_minor` to their 094 bodies FIRST (094:431-476 / 094:504-514,
   byte-for-byte — the same text 096's own header calls "094 J7-3/J7-3b RE-CREATED"), including restoring
   094's grant class (service_role only, authenticated revoked); (b) R-7 pair (reconcile calls R-3,
   dropped first); (c) R-3 (calls the projection + 095's `hold_payout_transfer_reversed`, untouched);
   (d) R-5 (calls the obligation projection); (e) the two projections; (f) triggers before their functions
   on both tables; (g) the unique partial index; (h) the two tables, last, confirmed empty by the guard.

2. `supabase/tests/162_payout_reversal_and_obligation_recovery.sql` — pgTAP, `BEGIN…plan(86)…finish()…
   ROLLBACK`, the 161 fixture idiom (own `tap.memo_162`/`tap._aal2_162` helpers, org1/venue1/event1/sessOld
   + a second org2 for the cross-org proof). 86/86 assertions pass. Sections: A (shape/grants/RLS/triggers
   of every new object, 11 assertions) · B-D (partial→partial→full via the SAME two-call sequence on one
   payout: stays paid at Σ<amount with correct projection, moves to `reversed` at Σ=amount through the
   EXISTING `mark_payout_transfer_state` edge, trr_ replay is a no-op) · E (over-sum refused) · F
   (wrong-payout trr_ conflict) · G (the submitted-ref-not-yet-stored race → held, fact still recorded)
   · H (failed refuses) · I (the new unique index live) · J (all seven `reconcile_payout_transfer` outcomes:
   clean, full-reversed, partial, 404, ref-mismatch-never-adopts, amount/destination/ambiguous mismatch,
   replay convergence) · K-L (obligation recovery: 2000-of-6000 partial, 6000-completes via a
   `transfer_reversal` receipt citing the SAME trr_ the payout side wrote, >debt refused, write-off,
   late-receipt-after-write-off refused, resolve('recovered') refused without facts) · M (authority:
   authenticated+platform+aal2 required, service_role refused at the GRANT for both `record_obligation_
   recovery` and `resolve_organization_obligation`) · N (the KE §4.4 conservation case with real numbers:
   an unlinked full reversal moves the payout to reversed while the obligation stays completely untouched
   — no double count, but both facts coexist rather than one silently discharging the other) · O (the
   160/F5 grep idiom: no 096 verb body names "promoter" or `release_payout`) · P (Gate-2 public-schema
   census unchanged, with the pgtap-extension-function exclusion the in-transaction count needs).

---

## 3. Verification run (rehearsal DB `snatchit_rehears_m1f`)

```
scripts/rehearsal_reset.sh snatchit_rehears_m1f        → 111/111 (then 112/112 once 098/099 landed
                                                            concurrently from other agents) migrations
                                                            replayed clean; GATE-2 tables=27 functions=70
                                                            policies=37 triggers=26 == CI baseline, BOTH
                                                            times (096 included in the chain either way)
scripts/rehearsal_test.sh snatchit_rehears_m1f supabase/tests/162_...sql
                                                          → plan=86 ok=86 not_ok=0 psql_err=0  PASS
psql -f supabase/rollbacks/096_..._rollback.sql          → clean apply (BEGIN…21 DDL statements…COMMIT),
                                                            both tables confirmed empty first; kernel
                                                            function count 145→136; grants back to 094
                                                            shape (service_role=t, authenticated=f on
                                                            resolve_organization_obligation)
psql -f supabase/rollbacks/096_..._rollback.sql (2nd)    → NOTICE "already rolled back — no-op" from the
                                                            guard, then idempotent create-or-replace/
                                                            drop-if-exists statements re-run harmlessly
                                                            (same shape as 095's own rollback house style)
scripts/rehearsal_reset.sh snatchit_rehears_m1f (fresh)  → 096 re-applies cleanly from a full reset
                                                            (confirmed twice: before and after 098/099
                                                            appeared in the migrations directory)
```

Checked `supabase/migrations/098_promoter_prorata_funding.sql` and `099_signing_monitor_and_executor_
invokers.sql` (landed concurrently from other agents mid-task) for any reference to 096's objects —
none found (`grep` for `payout_reversal|organization_obligation_recovery|record_payout_reversal|
reconcile_payout_transfer|claim_failed_payouts_for_reconcile|record_obligation_recovery|
payout_reversed_minor|obligation_outstanding_minor` returns nothing in either file), so the rollback's
isolation from later packages holds as designed.

---

## 4. Census deltas 096 forces (bump is the ORCHESTRATOR's job — `supabase/tests/141-157` NOT touched here)

- **Kernel functions: 136 → 145 (+9).** Confirmed by direct count (`pg_proc` in schema `kernel`) on a
  chain ending at 095 (136) vs. one ending at 096 (145). The 9 new functions are exactly R-1's guard +
  projection, R-3, R-4's guard + settle + projection, R-5, R-7's two verbs (9 total); `resolve_organization_
  obligation` and `org_outstanding_obligation_minor` are **re-created** (same signature, same OID identity
  via `create or replace`), so they do not add to the count.
- **Kernel tables: +2** (`kernel.payout_reversal`, `kernel.organization_obligation_recovery`).
- **Kernel triggers: +3** (`tg_payout_reversal_guard`, `tg_organization_obligation_recovery_guard`,
  `tg_organization_obligation_recovery_settle`).
- **Cron / config: NONE.** 096 schedules nothing and adds no `catalog.platform_config` key.
- **Gate-2 (public schema census): UNCHANGED** — tables=27, functions=70 (pgtap-extension functions
  excluded from the in-test count), policies=37, triggers=26, verified before and after 096 in the replay
  chain, matching the CI baseline both times. 096 touches nothing outside `kernel`.
- Whoever owns the next census bump (`supabase/tests/141/142/143/144/148/154/156/157`, per DESIGN_096 §0,
  "as 095 did — see J5 §9") should target 136→145 for the kernel function count and add the two tables /
  three triggers to whichever of those files enumerate the kernel schema. **Not done here** — the task
  brief for this file explicitly reserves it for the orchestrator.

MD5 of `supabase/migrations/096_payout_reversal_and_obligation_recovery.sql`: `466e0f605e20748e7ddd7e53889fbf5d`
(1247 lines).

---

## 5. Deviation between DESIGN_096.md §1 and what 096 actually implemented

Read 096 in full against the memo. Two honest deviations, both **additive/stricter than spec, never a
contradiction of it**:

1. **§1.7's refusal-code enumeration is a subset of what 096 ships.** The memo names `ref_mismatch`,
   `ref_unresolvable`, `transfer_unresolvable`, `amount_ledger_mismatch`/`destination_mismatch`,
   `reconcile_ambiguous`, `reversals_incomplete`. The shipped `kernel.reconcile_payout_transfer` (096:1099-
   1120) adds three refusal codes the memo never named: `currency_mismatch` (checked as its own predicate,
   not folded into "amount_ledger_mismatch" as the memo's prose suggested), `transfer_group_mismatch`
   (checked before the `group_count<>1` ambiguity check — the memo's `p_observed` shape lists
   `transfer_group` as an evidence field but never specifies a predicate on it), `reversal_malformed` (a
   per-element shape check on `reversals[]`, folded in causally after `group_count`), and
   `reversals_inconsistent` / `reversal_exceeds_transfer` (guards against a reversals[] list whose Σ
   EXCEEDS `amount_reversed` or the payout's own amount — the memo's §1.7 only worried about a list falling
   SHORT, "reversals_incomplete", never about one running long). None of these loosen anything the memo
   asked for; they close gaps the memo's own prose implies ("Absent operands fail CLOSED… a missing group
   count is ambiguous") but did not spell out as named codes. Reported so the pgTAP suite (162 §J) tests
   the CODES AS SHIPPED, not the memo's shorter list — verified directly against the migration body, not
   assumed from DESIGN_096.

2. **§1.5's "source links at most once" note is enforced twice, redundantly but consistently.** The memo
   says the recovery table's `UNIQUE(source_kind, source_ref)` constraint is "the at-least-once key."
   096:753-757 ALSO pre-checks the same condition inside `kernel.record_obligation_recovery` with a named
   `conflict_locked: recovery_source_already_linked` error, ahead of the INSERT that would otherwise
   surface a bare `23505`. This mirrors the KD P2-1 style used elsewhere in the corpus ("say by name rather
   than as a bare 23505") and does not change behavior a client can observe differently — it is a nicer
   error message for the identical refusal, not a new refusal path.

Everything else — the R-1 through R-8 shapes, the replay-first-before-state-gate ordering in
`record_payout_reversal`, the AFTER-trigger-not-an-act honesty fix on `organization_obligation_recovery`,
the `resolve_organization_obligation` reachability + honesty fix, the grant classes (R-8's `v_defs`/`v_svc`/
`v_auth`/`v_nobody` arrays) — matches DESIGN_096 §1 exactly as written, confirmed by reading the migration
in full rather than trusting the memo's paraphrase.

## 6. Open items (not this file's to close)

- Whether an unlinked reversal (§N of 162 — the KE §4.4 case where the venue is owed again and nothing
  re-mints) gets a re-mint verb is explicitly out of scope for 096 (its own header: "It does not decide
  whether a reversal that is not a recovery re-owes the venue — KE Q1, owner item"). 162's Section N proves
  the current honest-but-incomplete behavior; it does not propose a fix.
- The kernel census bump (141-157) and the settlement-seam package (097, chargeback arm venue scope /
  refund deferral mirror / unlined_reversal fence / shortfall hold) are both explicitly reserved to other
  owners per DESIGN_096 §0 and were not touched.
