# `WRITER` Owner Ruling — Consequence Map

**Owner ruling, 2026-08-28.** For the subject *"which functions write table T?"* the single normative
owner is **`docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md`**. Ratification row **`OR-7`**.
Mapping and derivation only — no contract was edited to produce this.

> ## THE COUNT IS **11**, NOT 10.
>
> ```
> X-6  kernel.tickets          DERIVED WRITERS: 11   (R-24 says "TEN")
> X-1  kernel.payment_native   DERIVED WRITERS:  2 unambiguous + 1 ambiguous-as-written
> ```
>
> **The eleventh is `kernel.sweep_expired_ticket_atoms` — a cron/sweep writer.** It is exactly the
> class the ruling says must not be omitted, and it is exactly the class the prior count omitted.
> **This is the ruling paying for itself on its first application:** had "10" been adopted because a
> prior reviewer said 10, the transcription would have produced an authority statement still wrong by
> one — and wrong about a function that silently expires tickets on a two-minute cron.

## X-6 — `kernel.tickets`: the canonical eleven

| # | function | kind | writes |
|:--|---|---|---|
| 1 | `kernel.issue_ticket_atoms` | helper (definer engine) | INSERT N, `state`, `credential_version`, `current_owner_id` |
| 2 | `kernel.transfer_ticket_ownership` | helper (definer engine) | `current_owner_id`, `credential_version += 1`, `resale_state`, `signing_key_id` |
| 3 | `kernel.void_ticket_atom` | helper (definer engine) | `state → voided`, `current_owner_id := SN-VOID` |
| 4 | `kernel.lock_ticket` | helper (not client-callable) | `resale_state` |
| 5 | `kernel.unlock_ticket` | helper (not client-callable) | `resale_state` |
| 6 | `kernel.mark_ticket_scanned` | helper, reached through the door-session edge fn (`verify_jwt=false`) — **webhook-facing in practice** | `state → scanned` |
| 7 | `kernel.request_order_refund` | rpc (edge-fronted) | `resale_state := refund_hold` |
| 8 | `kernel.approve_refund_request` | rpc (edge-fronted) | `resale_state := none` |
| 9 | `kernel.cancel_refund_request` | rpc | `resale_state := none` |
| 10 | `kernel.sweep_expired_refund_requests` | **cron/sweep** | `resale_state := none` |
| **11** | **`kernel.sweep_expired_ticket_atoms`** | **cron/sweep** (2-min heartbeat, actor `SN-SYSTEM`) | **`state → expired`** |

**Why `R-24` says ten.** `R-24` was written by the `MB-6` pass and enumerates exactly 1–10. §12.5 —
which creates writer 11 — was authored into **the same document** by a *later* pass under
`C109`/`S-22`/`MN-4`, and `R-24` was never re-derived. **The owner document contradicts itself about
the size of its own writer set.** Recorded below as an internal defect, not resolved by this ruling.

**`venue.record_scan` is a delegating caller, not a writer** — confirmed three ways: §0.7a lists it in
the *Delegating callers* column, §9.4's own Writes line says *"via `mark_ticket_scanned`"*, and §0.7
forbids any `venue.*` function from writing the table directly. Seven other delegating callers name
the table correctly under §0.7a standing rule 1 and are likewise not writers.

**No missing contracts on this table.** Checked and cleared: the custody-head constraint trigger
`kernel.tg_custody_head_is_ledger_tail` **asserts and raises — it writes nothing**, so its absence
from the writer set is correct, not an omission.

## X-1 — `kernel.payment_native`

| # | function | kind | status |
|:--|---|---|---|
| 1 | `venue.finalize_primary_order` | server-only definer, **webhook/edge-facing** | unambiguous |
| 2 | `kernel.transfer_ticket_ownership` | helper (definer engine) | unambiguous |
| 3 | `market.accept_p2p_transfer` | rpc | **AMBIGUOUS AS WRITTEN** — see internal defect 5 |

**`kernel.issue_ticket_atoms` does NOT write this table.** Its complete Writes line names
`kernel.tickets`, `kernel.ticket_ownership_log`, `venue.inventory_batch`, `venue.inventory_movement`
and nothing else. **Both derived documents name it and omit the actual writer of every primary-purchase
link.**

> ### MISSING CONTRACT — and it fails OPEN
>
> **`kernel.payment_native.instrument_fingerprint` has ZERO contracted writers.**
>
> The column is scheduled in `090` by the schema spec, the migration plan and the registry. It is
> **read** by `venue.resolve_order_attribution`. It is the **only** mechanism implementing the
> promoter self-deal detector — the promoter spec says *"this is the whole reason for §1.8"*. **No
> Writes line anywhere in the owner document names it.** The two contracted writers of the row both
> describe their write as a bare *link*.
>
> **A NULL fingerprint means the self-deal detector never fires.** It fails open, silently, on the
> fraud path.
>
> Under the ruling this is a **MISSING CONTRACT and readiness fails**. It may **not** be repaired by
> adding the writer to the schema spec, the plan or the registry — all three of which already mention
> the column, which is precisely how it got this far.

## The losing sites — what must be transcribed

**`X-6`** — RLS §7.5 and §5 (four named, eight missing, and the fourth is a `venue.*` wrapper that
asserts a §0.7 violation as design); schema spec §1.5 **and §1.5.1** — the latter matters because the
wrong writer set is the *premise* of the `MN-4` finding whose own conclusion then added writer 11;
schema §1.5's `current_owner_id` claim *"written only by the transfer engine"*, false on two paths
(mint, and void-to-`SN-VOID`); RLS §7.5 note ⁹, where the EXEC grant stands but the writer attribution
is the `G-20` naming collision.

**`X-1`** — RLS §7.8 and §5; schema §1.8, whose *"only"* makes it a competing definition rather than a
restatement; schema §1.8's *"written by issuance / native-sale engines"*, when the primary-order link
is written by a **`venue.*`** function.

**The placement owner already agrees with the derivation.** The migration plan's `079` rows carry
`lock_ticket`/`unlock_ticket`/`mark_ticket_scanned`/`sweep_expired_ticket_atoms`, and its `085` row
records `venue.finalize_primary_order … writes kernel.payment_native`. **Only RLS and the schema spec
dissent** — which is exactly the shape the ruling predicts once membership has one owner.

**`X-1` still has no filed `R-` request.** Every other row is covered by `R-24`, `R-29`, `R-31` or
`R-33`. Filing it is a prerequisite to transcription under the corpus's own discipline.

## INTERNAL CONTRADICTIONS IN THE OWNER DOCUMENT — the ruling does NOT resolve these

The ruling makes one document authoritative. It does not make that document self-consistent, and
**hiding these behind the ruling would be the failure mode the ruling exists to end.** Seven:

1. **§20.14 `R-24` says "THIS DOCUMENT CONTRACTS TEN"; it contracts eleven.** Applied verbatim, the
   request it files on RLS would produce an authority statement still wrong by one.
2. **§0.7a's prose says "six kernel functions are contracted as writers"; the same subsection then
   names four more.** Six, then four, in one subsection.
3. **§0.7a's *"Nothing is added to it"* is falsified by §12.5** — a writer added with no row in the
   §0.7a table, by a later pass on the same document. Standing rule 2 warned about exactly this: *"a
   sixth writer added without a row here would be invisible to the same assertion."*
4. **§7's preamble says *"No other code writes custody."*** Eight functions in the same document do.
5. **§8.2 vs §20.8.6 — the same delegation written two ways.** One says *"via the kernel engine …
   `kernel.payment_native`"*; the other lists the table as a separate, undelegated item. Under §0.7a's
   own stated logic that reads as a `market.*` function writing a `kernel.*` money table — **and
   `X-1`'s count is 2 or 3 depending on which reading an implementer takes.**
6. **§17.4 vs §12.5 — two cron writers of one table, classified as *"the opposite"* posture**, only
   one acknowledged in §0.7a's carve-out, with nothing saying whether that carve-out is closed.
7. **`R-25` / `ODR-38` is open on top of all of it** — four money RPCs write `resale_state` beside the
   `lock`/`unlock` pair that exists so the column has one writer pair, and the document says *"This
   document does not choose."*

**Defects 1–6 are intra-document and belong to the RPC owner. Defect 7 is a registered open owner
decision.** None is resolved here, and the derived count of 11 is stable under all of them.
