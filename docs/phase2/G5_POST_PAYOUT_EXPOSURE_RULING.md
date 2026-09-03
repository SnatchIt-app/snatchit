# RULING G5 — POST-PAYOUT REFUND / DISPUTE / CHARGEBACK EXPOSURE

**Status: DRAFT. NOT APPROVED. NOT SIGNED.**

**Supersedes** the shorter G5 stub in `FINAL_ACTIVATION_BLOCKER_RULINGS.md`, which was written before the
loss behaviour was measured. Every figure below is from execution against a full local replay, not from
reasoning.

---

## 1. MEASURED CURRENT BEHAVIOUR

Fixture throughout: a buyer pays **23 000** = **19 000 face** + **4 000 buyer service fee**.

| Case | What happens today |
|---|---|
| **A** venue paid 19 000, later 6 000 refund | second settlement closes `net −6 000`, `payout_ids: []`. Durable facts: one `kernel.refund`, one `refund_void −6 000` line, one frozen negative header. **No payout, no obligation, no reserve row.** |
| **B** paid, then 23 000 dispute lost | `chargeback −19 000` — correctly capped at face, so the 4 000 fee slice is platform loss per A5. `payouts_held: 0`, because the freeze leg only touches `pending`/`submitted` payouts and only while the dispute is **open**. |
| **C** two partial refunds (6 000 + 13 000) | both lined, Σ capped exactly at face, net −19 000. |
| **D/E** paid, refund 12 000, then 5 000 of new revenue | next close `net −7 000`, **no payout at all** — the 5 000 is silently consumed. **The −7 000 residue does not carry.** The following close pays the venue its full 10 000. |
| **F** refund 12 000 and a 20 000 order in the *same* close | net 8 000, **8 000 paid**. Offset works — but only inside one `close_settlement` call. |
| **G** period-scoped pooling across two events | net −23 000, no payout. |
| **H** suspended organization | `request_org_payout` **never reads `organization.status`** and advanced to `submitted`. Only the edge refuses. A stranded payable with no hold, lease or timeout. |
| **I** venue never sells again | seven negative headers across one replay, all `closed`, all zero payouts, **−99 000 total**. Nothing aggregates, ages or alerts on them. |
| **J** destination changed while debt exists | probation holds the **full** 11 000, not 11 000 − 6 000. After release, 11 000 paid in full to the new destination. **Debt untouched.** |
| **K** `cancel_event` after payout | creates a `pending` refund at face only — the buyer loses the 4 000 fee — and touches `kernel.payout` nowhere. |

### The finding that defines the problem

**The conservation equations close only because `UNRECOVERED RECEIVABLE` is a quantity derived by hand
across two schemas. It corresponds to no table, no column, no row and no function.**

Set it to the 0 the database can actually represent, and cases A, B, C, D/E, G, J and K **fail to
close** — by 6 000 / 19 000 / 19 000 / 7 000 / 23 000 / 6 000 / 19 000 respectively. The gap is always
the same object: **`venue.settlement.net_minor < 0` on a permanently `closed` header.**

The money is real. The database has no name for it.

### The "accidental future offset" is weaker than previously reported

Earlier reports described a partial future-settlement offset. Measured, it is **not future-settlement
offset at all**: the residue does not carry between closes. Recovery happens only when reversing and
positive revenue land in the *same* `close_settlement` call, so the recovered fraction is decided by
accounting accident rather than by policy.

### Two writer gaps that bound the exposure today

- `record_dispute_native`, `mark_dispute_state` and `resolve_dispute_native` have **zero callers in any
  TypeScript**; the webhook's dispute branches write only the legacy tables. **The `chargeback` line arm
  cannot fire in production.**
- `kernel.payout` can never reach `reversed`: the executor emits only `'paid'`, and `transfer.reversed`
  routes to the legacy handler.

---

## 2. WHAT STRIPE CAN AND CANNOT DO

Separated deliberately from policy.

**Transfer reversal MOVES the problem; it does not solve it.** Stripe: *"It's only possible to reverse a
transfer if the connected account's available balance is greater than the reversal amount or has
connected reserves enabled."* Reversal is a balance-to-balance move that requires the money still to be
in the venue's Stripe balance — which is exactly what is gone in the case we fear. Stripe's own dispute
page says the platform may *"attempt* to recover funds."

- **No Stripe mechanism extracts money from an empty balance.** Account Debits share the same
  constraint: they cannot make a connected balance negative.
- **Liability is identical between separate charges and destination charges**, "with or without
  `on_behalf_of`". Changing charge model is **not** a recovery fix.
- **Reserves exist but are gated**: a genuine reserve product is in **private preview**, capped at 180
  days, and requires platform-owned negative-balance liability plus a terms disclosure.
- Two official Stripe pages **contradict each other** on whether a reversal can push an account
  negative. The correct engineering response is not to architect on reversal succeeding.
- At 180 days negative, `connect_collection_transfer` fires and **the platform pays**.

**Snatch It currently calls no reversal endpoint at all** — verified repo-wide.

---

## 3. OPTIONS

| | Option | Assessment |
|---|---|---|
| **1** | **Platform absorbs all post-payout losses** | This is today's behaviour plus a decision. Worst fraud posture: a venue that refunds after payout keeps the money with no record that it owes anything. Costs nothing to build. |
| **2** | **Organization obligation (durable record of what is owed)** | Records the fact. Nets nothing, funds nothing, gates no payout by itself — the ratified posture of the existing `kernel.identity_obligation`. Makes the equations close. Does **not** by itself recover a cent. |
| **3** | **Negative carry / automatic future-settlement offset** | Note this **already partially ships**: the `chargeback` arm nets org-scoped with no venue predicate. Extending it to carry across closes is a real option, and it is the one that actually recovers money. It is also the one that raises the cross-venue question in §5. |
| **4** | **Reserve / hold-back before payout** | Reduces exposure rather than recovering it. Changes payout timing, not venue entitlement — so it is compatible with A5. Needs an owner-set percentage and duration, neither of which exists. |
| **5** | **Stripe fixed reserves** | **Not currently available** — private preview, 180-day ceiling, requires platform-owned liability and a ToS disclosure. Cannot be relied on for launch. |
| **6** | **Hybrid: obligation now, offset next, reserve later** | Records the fact immediately, recovers automatically where revenue exists, and leaves the reserve decision until Stripe's product is generally available. |

---

## 4. RECOMMENDATION

**Option 6, in that order — but the owner must still choose whether recovery is automatic.**

The reasoning is that options 2 and 3 answer different questions and are being conflated. Option 2 makes
the loss *representable*; option 3 makes it *recoverable*. Only option 2 is unambiguously safe to build
without a policy decision, because recording a fact that is already true commits nobody to anything.
Deciding that a venue's future earnings are automatically seized to pay an old debt is a commercial
decision with a venue-relationship consequence, and it is not mine.

**What has been built in this train: option 2 only.** `kernel.organization_obligation` (migration 094)
is append-only, positive-magnitude, forward-only, org-scoped, `service_role`-definer-written, and
**nets nothing, funds nothing and gates no payout** — literally true, matching the ratified posture of
its identity-side twin. Its magnitude is re-derived from the closed settlement header, so no caller can
name an amount.

**Option 3 is NOT built.** The existing same-close netting is untouched.

---

## 5. THE QUESTIONS THAT ARE GENUINELY YOURS

**5.1 — Does one venue's debt offset another venue's earnings, inside the same organization?**

ORG A / Venue 1 loses 500. ORG A / Venue 2 earns 1 000. Should the 500 be taken from Venue 2?

This is **live whether or not anything from this train ships**, because the `chargeback` arm already nets
org-scoped with no venue predicate. It is not a question this design created. And because
`venue.settlement.venue_id` is NOT NULL and `venue_finance` can read it, it is a **disclosure** decision
as well as an economic one — a venue's finance role would see the other venue's loss in its own numbers.

**5.2 — Is recovery automatic or an explicit act?**

The ratified pattern for realized loss (`kernel.identity_obligation`) records debt and resolves it *by an
audited platform act*, `recovered` or `written_off`. It nets nothing. If organization debt should behave
differently and seize future revenue automatically, that is a departure that should be chosen
deliberately.

**5.3 — Do you accept the residual that cannot be recovered at all?**

A venue that never sells again cannot be offset against anything, and Stripe cannot reach an empty
balance. Some portion of post-payout loss is **structurally unrecoverable**. The only real levers are a
longer maturity hold (already 7 days under G2) or a reserve.

---

## 6. RESIDUAL RISK

- Recovery is impossible where the organization has no future revenue and an empty Stripe balance.
- The obligation is **inert for the chargeback origin** until the dispute writers have callers — that
  wiring is a separate train.
- The maturity hold reduces but does not eliminate the window: a dispute can arrive up to ~120 days
  after the event, and no commercially viable hold covers that.
- Option 3, if later adopted, silently confiscates a venue's later revenue unless it is disclosed.

---

## 7. OWNER APPROVAL TEXT

> **G5 — POST-PAYOUT EXPOSURE**
>
> The organization obligation object recorded in migration 094 is approved as the durable record of money
> owed to Snatch It after a settlement has been paid. It records a fact and nothing more: it nets
> nothing, funds nothing and gates no payout.
>
> Recovery policy is ruled as: ______________________________
> (2 record only, resolved by an explicit audited act / 3 automatic future-settlement offset / 6 record
> now and decide offset separately).
>
> Cross-venue netting inside one organization is ruled as: **not permitted (owner direction
> 2026-09-03)**. It is recorded that the existing chargeback arm already nets org-scoped today, so this
> answer requires a change to shipped behaviour, and that a venue's finance role can see another venue's
> settlement, making this a disclosure decision as well as an economic one. Migration 097 (see the OWNER
> DIRECTION note below) implements the ring-fence this line pre-fills, pending the owner's signature on
> the ruling as a whole.
>
> It is recorded that some post-payout loss is structurally unrecoverable, that Stripe reversal requires
> funds still to be in the venue's balance and therefore fails in exactly the case we fear, and that
> Stripe fixed reserves are in private preview and unavailable for launch.
>
> **The venue payout executor may not be deployed until this ruling is signed.**

---

**A governance note that must not be lost.** The org-side carry this object represents is assigned by
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1186` to C31 / Gate-M, and `PHASE_2_MONEY_AUTHORITY_SPEC.md:67`
ratifies Gate-M as "not required" for MVP — on the premise that no reserve or clawback is needed because
payout is settlement-cadenced. That premise was written when **no venue could be paid at all**. It should
be **re-attested rather than obeyed or overridden**. Migration 094 therefore records a **ratification row
as a deploy precondition, not a build precondition**: the file exists and is dark, and applying it
requires the owner's signature here. **See the new "GATE-M RE-ATTESTATION" section in
`docs/phase2/FINAL_ACTIVATION_BLOCKER_RULINGS.md`, added this train, for the exact attestation text.**

---

## OWNER DIRECTION RECEIVED 2026-09-03 (unsigned) — and what this train built

**This ruling is still unsigned.** The direction below is owner guidance for what to build against §3's
options, not a signature on §7's approval text — §5.1's cross-venue question is the one exception,
pre-filled above at the owner's direction; every other blank in §7 remains open.

**Direction received.** The organization obligation stays **the durable record of post-payout debt** —
§3 option 2's posture, now sharpened: recovery must eventually be **deterministic and auditable, not
accidental** (ruling out option 3's accidental same-close netting as a permanent answer, without yet
choosing between "record only" and "automatic offset" for §7's first blank). And **no default
cross-venue netting**: Venue A's debt must not silently consume Venue B's payout inside the same
organization (§5.1, now answered "not permitted" above). The legal debtor may remain the organization;
the recovery source may be venue-scoped — the obligation's *header* stays org-level while its recovery
is fenced to where the loss actually occurred.

**Migration 096 — recovery facts.** Adds `kernel.organization_obligation_recovery`, an append-only
ledger of recovery events against an `organization_obligation` row: `source_kind` constrained to
`transfer_reversal | manual` (closing the "how was this recovered" gap §1/§6 leave open — a Stripe
transfer reversal reaching the platform, or a platform-initiated manual act); every row's amount is
constrained so that Σ(recovery rows for one obligation) never exceeds that obligation's `amount`;
`status = 'recovered'` on the parent obligation is **derived**, not settable, and only becomes true when
the sum reaches the full amount — a partial recovery leaves the obligation `outstanding` with the
partial credited, rather than either overstating or silently closing it. `written_off` remains an
**explicit**, separate terminal state — recovery rows and a write-off are mutually exclusive ways an
obligation stops being outstanding, never inferred from each other. `resolve_organization_obligation('recovered', …)`
is **refused without at least one recovery row backing it** — closing the "trust me" gap in the
`identity_obligation` precedent (§3 option 2's own text: "resolved by an audited platform act", which
previously meant a status flip with no receipts). The resolver's grant was fixed to
**`authenticated` + `is_platform()` + aal2** — narrower than a bare role check — so a step-up session is
required to resolve any obligation, recovered or written off.

**Migration 097 — the ring-fence.** Two changes: (1) the chargeback recovery arm is fenced to the
**originating venue** — a chargeback against Venue 1's sale can only ever be recorded as recovered
against Venue 1's future settlements, never Venue 2's, closing §5.1 as directed; (2) the **unlined
origin** (post-payout loss with no `origin_kind` row backing it — the gap §1's finding describes,
"UNRECOVERED RECEIVABLE… corresponds to no table, no column, no row") is fenced to **post-payout
ledger-derived amounts only** — an obligation cannot be opened, or recovery attempted, for any amount
that does not trace to a closed settlement's own negative `net_minor`, so the object cannot be used to
assert a debt the ledger itself does not already show. A new `shortfall_pending` hold state is added
to the payout maturity conjunction (this is G2's ninth predicate, `dispute_unabsorbed` — see the
OWNER DIRECTION note under G2 in `FINAL_ACTIVATION_BLOCKER_RULINGS.md`): it **nets nothing** — it holds
a payout from advancing while recovery against that venue is outstanding, the same fail-closed shape
G2 already uses, not a netting mechanism dressed differently.

**What neither migration does.** Neither 096 nor 097 deploys the payout executor, changes today's
"platform absorbs" default, or answers §7's "record only vs. automatic offset" blank — that remains the
owner's choice. Neither builds §3 option 4 (reserve/hold-back) or option 5 (Stripe fixed reserves).
Neither is Gate-M's C29/C30/C31 (see the new GATE-M RE-ATTESTATION section, above).

**Remaining owner questions, sharpened by what 096/097 make possible:**

1. **A late receipt after write-off.** If an obligation is `written_off` and a recovery source (e.g. a
   delayed transfer reversal) later actually lands, 096 has no path back from `written_off` — is a
   write-off meant to be terminal even against money that later shows up, or does the resolver need a
   reopen verb?
2. **Same-venue unpaid-payout cancellation.** 097's ring-fence permits recovery only against the
   *originating* venue's future settlements — but if that venue's organization cancels operations or its
   Connect account is deactivated before any future settlement exists, is the obligation simply
   unrecoverable by design (§6's residual), or should a same-venue *unpaid, matured* payout be eligible
   for offset even though it has not yet been requested?
3. **An org-level netting agreement object.** §5.1 is answered "not permitted" as the *default*. Is there
   ever a contractual case (a multi-venue operator agreement) where the org and Snatch It could agree to
   cross-venue netting explicitly, and if so does that need its own durable, auditable object rather than
   a policy exception buried in code?
4. **Automated reversal initiation is not built.** 096/097 record and fence recovery; nothing calls
   Stripe to *initiate* a transfer reversal or any other recovery action — `source_kind='transfer_reversal'`
   rows are written when a reversal is *observed*, not caused. Is initiating recovery (vs. only recording
   it when it happens) in scope for a future train, and if so, by what trigger?
