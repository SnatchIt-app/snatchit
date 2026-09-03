# KM2 — 097_settlement_scope_and_shortfall.sql implementation report

Implementer M2 · repo `snatchit-consol` @ branch `feature/venue-native-and-product-v2` · AUTHOR-ONLY (no DB
commands run; no rehearsal reset/test executed; no git commit). Written against DESIGN_097_099.md §M2 and
investigator reports KC, KG, KB, KD §4.4, KH §3 P1-6.

---

## 1. What was built

Four files, all new:
- `supabase/migrations/097_settlement_scope_and_shortfall.sql`
- `supabase/rollbacks/097_settlement_scope_and_shortfall_rollback.sql`
- `supabase/tests/163_settlement_scope_and_shortfall.sql` (pgTAP, `plan(74)`)
- `docs/phase2/_impl/KM2_097_implementation.md` (this file)

Nine objects re-created body-only (verified: exactly 9 `create or replace function` statements in the
migration, matching DESIGN's list precisely — no extra, no missing):

| Object | Source range re-created from | Change |
|---|---|---|
| `kernel.settlement_royalty_lines` | 093:1136-1216 | venue ring-fence (join to `catalog.event`/`e.venue_id = s.venue_id`) + refund-deferral mirror + unlined fence on `cb_candidate` |
| `kernel.settlement_primary_lines` | 093:435-560 | `scoped_order`'s deferral replaced with the "could still succeed" form; `refund_candidate` gets the unlined fence |
| `kernel.record_organization_obligation` | 094:320-413 | `settlement_shortfall` sets `venue_id`; `unlined_reversal` branch replaced: origin resolution, sale-arm refusal, post-payout proof, ledger-derived amount, venue derivation, richer audit `after` |
| `kernel.organization_obligation_guard` | 094:260-293 | `venue_id` added to the write-once column list |
| `kernel.close_settlement` | 094:544-790 | one added block in the `elsif v_net < 0` branch: the same-venue `shortfall_pending` payout hold |
| `kernel.settlement_payout_maturity` | 093:2076-2170 | ninth predicate `dispute_unabsorbed`, after `dispute_open` |
| `kernel.settlement_maturity_hold_codes` | 095:458-478 | ninth code added; ONE new comment |
| `kernel.record_dispute_native` | 088:758-867 | rail guard, empty-string refusal, replay-drift audit, currency-mismatch audit, corrected comment (088:753-757) |
| `kernel.mark_dispute_state` | 088:875-902 | `p_command_key` bound by record's regex |

Plus one column: `kernel.organization_obligation.venue_id uuid references catalog.venue(venue_id) on delete
restrict` (nullable — no NOT NULL added, per the FIXED DDL text; backfill: none, table is unapplied/empty).

Grants: **not touched anywhere**. Every re-created function keeps its existing ACL via `create or replace`
(verified against 087 PART 8 / 093:561 / 094 J7-5 / 095's own precedent — none of the nine objects has a grant
statement anywhere in 097). The new column carries no column-level privilege; the table's `REVOKE ALL` (094
J7-1) already covers it.

Gate-2: unchanged by construction — no new table, no new function (all nine keep their existing signatures),
no new trigger (the guard's trigger already exists and rebinds to the same OID via `create or replace`), no
new policy.

The **exact deferral-predicate SQL fragment** (KC P0-2), copied verbatim into three places — `settlement_primary_lines.scoped_order`, `settlement_royalty_lines.cb_candidate`, and used as the arithmetic model (not copy-pasted, since the caller only has one refund in hand) inside `record_organization_obligation`'s headroom derivation:

```sql
not exists (
  select 1 from kernel.refund r0 where r0.payment_id = pn.payment_id and r0.status in ('pending','submitted')
    and r0.amount_minor
        + coalesce((select sum(r1.amount_minor) from kernel.refund r1
                     where r1.payment_id = pn.payment_id and r1.status = 'succeeded'), 0)
        + coalesce((select sum(d1.amount_minor) from kernel.dispute_native d1
                     where d1.payment_id = pn.payment_id and d1.status in ('lost','charge_refunded')), 0)
      <= (select p.total from public.payments p where p.id = pn.payment_id)
)
```
M3 (098): copy this fragment verbatim into `settlement_commission_lines`'s eligible-set predicate per
DESIGN §M3 3.1 ("identical text to M2's 2.2 'could still succeed' form").

---

## 2. Verification status — NOT EXECUTED (AUTHOR-ONLY constraint)

Per my task's hard boundary, I ran no rehearsal reset, no pgTAP, no psql, no git commit. Everything below is
**read-verified**, not execution-verified:
- Every column/table/function name, signature and constraint referenced was checked against the actual
  DDL in 076-095 (grepped and read, not assumed) — see file:line citations in the migration's own header and
  section comments.
- `$$`/`$f$`/`$m$` delimiter counts in all three SQL files are even and match the number of function bodies
  (18/20/20+38+4 respectively — verified with `grep -c`), so no dangling dollar-quote was left open.
- The nine re-created function names in the migration were extracted programmatically and match DESIGN's
  list exactly (no 10th object, nothing missing).
- Traced by hand, statement-by-statement, against the actual 088/093/094/095 bodies: the KC 2.d-i/2.d-ii
  arithmetic, the KG V1-V4/V8/V10 ring-fence behavior, the `record_organization_obligation` derivation
  formula, the O7 shortfall-hold loop's interaction with `settlement_maturity_hold_codes()`, and the
  `retry_held_payout`/`request_org_payout` re-evaluation chain in test section E (the highest-risk chain in
  163 — it depends on `request_org_payout`'s full body past line 1802, which I read only through the
  destination-bound check, not its final ~180 lines; if a predicate there I did not read refuses, test E6
  will show `status <> 'submitted'` rather than throwing, since the CLEAR-then-delegate happens inside one
  function call and either both succeed or the whole call raises and the earlier `is()` will fail — **the
  orchestrator should watch test E6 specifically on the first real run**).

**The orchestrator must run**: `scripts/rehearsal_reset.sh` + `scripts/rehearsal_test.sh` against a fresh
096-inclusive replay, files 000, 141-157 (unmodified, to catch any accidental Gate-2 drift), 160, 161, 153
(to prove the documented deltas below and nothing else), and 163 (mine, `plan(74)`).

---

## 3. Census deltas the orchestrator MUST apply (I did not touch any of these files)

1. **`supabase/tests/161_payout_state_machine.sql`** — A9 (`array_length(kernel.settlement_maturity_hold_codes(), 1)`) currently asserts `8`; must become `9`. A9a's `bool_and` check is unaffected in shape (it re-derives from the live function, so it self-updates) but will now also assert the ninth code, `'dispute_unabsorbed'`, is a literal in `settlement_payout_maturity` — true after 097, no edit needed to the query itself, only the `8`→`9` literal on A9.
2. **`supabase/tests/160_organization_obligation.sql`** — F8 and F9 assert `settlement_payout_maturity` and `get_payout_execution_context`'s bodies do **not** contain the string `'organization_obligation'` (`pg_get_functiondef(...) !~ 'organization_obligation'`). F8 is now **FALSE by construction**: `settlement_payout_maturity`'s ninth predicate reads `kernel.organization_obligation` directly (to check the `unlined_reversal` fence). F9 is unaffected — `get_payout_execution_context` (093/095) is not touched by 097 and still does not read the table. **F8 must be replaced**, not deleted — with an assertion of what is now true: the reference exists ONLY inside the ninth predicate's `unlined_reversal` check, never as a gate on the maturity verdict's other eight predicates or on any payout-advance function this file does not re-create. Suggested replacement text: `pg_get_functiondef(...) ~ 'organization_obligation' AND pg_get_functiondef(...) ~ 'unlined_reversal'` (the same pattern my own 163/G4 uses for `settlement_royalty_lines`).
3. **`supabase/tests/160_organization_obligation.sql`** — F10 (`settlement_royalty_lines`'s body `!~ 'organization_obligation'`) is also now **FALSE by construction** (the ring-fence's bidirectional fence reads the table). Per DESIGN §2.7's own instruction, replace with: *"the arm reads `organization_obligation` ONLY for `origin_kind='unlined_reversal'`"* — my 163/G4 assertion (`pg_get_functiondef(...) ~ 'organization_obligation' AND ~ 'unlined_reversal'`) is exactly this replacement text, written once already in my own test file; the orchestrator can lift it verbatim into 160/F10.
4. **Whole-schema relation/table census (141:A13/C1, 148:B1, 157:A43/A45)** — these currently read 29 kernel tables / 76 five-schema relations, which is the count **as of 094**, and **does not yet reflect 096's two new tables** (`kernel.payout_reversal`, `kernel.organization_obligation_recovery` — confirmed present in the already-authored `096_payout_reversal_and_obligation_recovery.sql`). This is **not a 097 delta** — 097 adds a column, not a relation, so these counts are unaffected by 097 itself — but the orchestrator should confirm M1's own report already flags this 096-vs-141/148/157 gap (my own G10/G11 in 163 deliberately avoid asserting an absolute whole-stack count for exactly this reason — see §1's table).
5. **`supabase/tests/141_phase2_identity_orgs_deletion.sql`, `144`, `154`, `156`** (the `kernel.record_organization_obligation` / function-body census lines, if any list its full signature or a hash of it) — none were found to assert on this function's BODY TEXT (only 141:499-515 lists it by NAME among a function-name census, unaffected by a body-only re-create). No delta needed there.

Nothing else in 141-157 was found to reference any of the nine re-created objects' bodies (grepped: only the
name-census and grant-census entries, all signature-based, all unaffected by a body-only `create or replace`).

---

## 4. Deviations from the FIXED spec

None required. Every point in DESIGN_097_099.md §M2 was implementable against shipped bytes exactly as
specified:
- The venue ring-fence used option **B / P1** (grain-agnostic, no event window on debits) exactly as DESIGN
  §2.1 names it.
- The refund-deferral mirror is the literal fragment DESIGN §2.1/§2.2 gives, copied verbatim into both arms.
- `record_organization_obligation`'s derivation formula matches DESIGN §2.3's prose exactly, including the
  "for a refund origin the refund IS the amount" special case (`v_exposure := case when v_dispute_found then
  <sum of succeeded refunds> else v_r.amount_minor end`).
- The shortfall hold (§2.4) fires immediately after `record_organization_obligation`, scopes to
  `payee_org_id = v_s.org_id and cause='settlement' and status='pending'` at settlements whose `venue_id =
  v_s.venue_id`, upgrades an existing maturity hold, leaves `submitted` untouched, and is audited with
  `submitted_unheld` — all as specified. `'shortfall_pending'` is deliberately absent from
  `settlement_maturity_hold_codes()`.
- The ninth maturity predicate (§2.5) sits after `dispute_open` in the `case` precedence, exactly as
  specified, and is added to the hold-codes list.
- The dispute-writer changes (§2.6) are all present: rail guard, empty-string refusal, replay-drift audit,
  currency-mismatch audit, corrected comment, and `mark_dispute_state`'s command-key regex.

One judgment call, not a deviation from a FIXED instruction (DESIGN left it open): the shortfall-hold's audit
row (`payout.shortfall_hold`) is written **once per triggering close**, summarizing every payout held plus
the submitted count — not once per held payout. DESIGN's wording ("audit `payout.shortfall_hold` (before/after,
settlement ids)") reads singular and is satisfied either way; one summary row per close was chosen to avoid N
audit rows for what is one economic event, matching `settlement.close`'s own one-row-per-close audit
convention immediately below it in the same function.

---

## 5. Open items for the owner/orchestrator (carried from the investigator reports, not decided here)

- **KG §5.3 / KC §5.1**: a dormant venue that never opens another settlement after the ring-fence still has
  no automatic route to a booked debt — `unlined_reversal` is fenced and derivable now, but still
  **operator-only** (no producer added by this migration, matching KH P1-6's instruction not to book from the
  webhook). Whether a platform arm on `venue.open_settlement` (KC 4.1 O3 / KG option C) is ever built is an
  owner decision, not made here.
- **KD §4.3 / KC §4.3 O6/O7**: this migration implements O7 (hold, don't net) as the FIXED spec required; the
  larger question — should a shortfall whose covered payout is still unpaid be a debt at all, and should
  recovery ever consume the same-venue hold rather than merely displaying it — is still open, exactly as
  DESIGN §M2's boilerplate says ("NOT an offset").
- **KC §2.i / P1-3**: the promoter-commission overstatement (a chargeback line still equals the FULL face,
  including the held commission slice) is untouched — 098 (M3) owns commission accounting; nothing in 097
  reaches `pay_promoter_commission` or `settlement_commission_lines`.
- **KB P1-2/P1-3/P1-4, KB P0-2 (`prevented`)**: none of these are in scope for 097 (DESIGN explicitly excludes
  them) and remain open exactly as KB left them.

---

## 6. Summary for the final chat message

Paths: the four files listed in §1. Objects, deltas, deviations: as above.
