# Writer-Parity Failure Triage

**2026-08-28.** Every failing row recomputed from HEAD and classified. **Nothing was repaired**
beyond defects in the governance artifacts themselves. Triage only.

> ## THE COUNTS DID NOT SURVIVE RECOMPUTATION — including my own
>
> | recorded | recomputed | what was wrong |
> |---|---|---|
> | tables in scope **80** | **82** | `kernel.tickets` and `kernel.payment_native` are in scope and were derived elsewhere; their parity never reached the column |
> | `DIVERGENT 22 · MISSING_CONTRACT 15` | **21 · 15** in this registry; **22 · 16** in true scope | one false positive corrected; `kernel.payment_native` is a missing contract the parity column never carried |
> | divergence records **48** | 41 over 80 tables, 48 over 82 | **the two figures were computed over different table sets, one line apart** |
> | missing contracts **18** | **17 bullets; 19 honest** | 18 was reachable only by splitting *"mint **and** rotation"* while not splitting *"the freeze RPC **and** the dispute table"* in the same list |
> | canonical writers **151** | **152** | 151 holds only if a placeholder name is silently excluded |
> | category references **12** | **2 in the registry** | 12 counts corpus-wide references, not registry entries — not derivable from the artifact |
>
> **Four rows were FALSE POSITIVES, and four more failed a check the gate did not yet have.**

## THE SIX ROOT CAUSES — they account for every failing row

**`RC-1` — the scope, the parity totals and the missing-contract list were computed over three
slightly different table sets.** Everything downstream inherited it.

**`RC-2` — a derived document restates a writer set instead of pointing at the registry, and the set
drifts. This is 20 of 22 divergences.** Every one is pure transcription; every canonical contract is
already right. The registry named this cause itself — *"the two RLS matrices that DO enumerate are
precisely the two that caught the schema spec's omissions"* — and then did not act on it.

**`RC-3` — RPC §20.0a excludes trigger functions from every set "by construction".** `OR-7` reverses
that; the sentence is still there. It explains `set_updated_at`'s total absence from ~50 writer sets,
and the erasure-tombstone trigger having no name, no contract, and an active denial in the plan.
**And the gate could not have caught it**: check `H` compares a row's writer count to its kind count,
so it sees a writer dropped from **one** column and is blind to one dropped from **both** — which is
exactly what this exclusion produces.

**`RC-4` — a placeholder that names no function.** *"native-sale payout path"* in two documents ·
*"the finalize sweep"* in two · *"the 088 sweep tick"* · *"a revoke RPC"* in three · four separate
webhook-table entries. The edge spec's own correction for `S-16` names the mechanism and blames it
for nine of twelve surviving gaps.

**`RC-5` — a contract exists, is granted EXEC, and no package builds it.** Four verified:
`kernel.mark_refund_state` (in the schema spec ×5 and the edge spec ×2, **zero** lines of the plan or
registry) and three holder-mix functions (the plan builds two of five).

**`RC-6` — a ratified correction landed in the DERIVED documents and not in the canonical one.**
`C110` re-routed the door-freeze drain through a hook and is carried by the registry, the plan and the
ratification record — while RPC §17.10 still describes `venue.open_door_manifest` writing `market.*`
**directly**, the pre-`C110` text. **This is the one shape `OR-7` cannot repair by transcription,
because transcription runs the other way.**

## CLASSIFICATION SUMMARY

| class | n | disposition |
|---|:--:|---|
| **A** stale derived restatement | **20** | MECHANICAL |
| **B** true missing function contract | **9** | ENGINEERING |
| **C** trigger/server writer omitted | **4** | ENGINEERING (one is OWNER-first) |
| **D** package-placement gap | **2** | ENGINEERING |
| **E** owner decision required | **2** | **OWNER** |
| **F** false positive / parser defect | **4** | corrected in this pass |

## THE BOUNDED MECHANICAL SET — 33 edit sites across 5 files

Safe in one pass because **no site changes a contract, an authority, or a placement** — each replaces
a stale writer list with the registry's. RLS §5 quick-reference ×10 · RLS §7.x/§9.x/§10.x ×16 · RLS
§16.5's closure set · schema spec ×8 · door spec ×2 · one additive `Writes` line in the RPC document ·
the `record_money_denial` transcription in RLS ×2 and the money spec ×2.

**Two of these are removals, not additions, and they matter more than the rest:** `kernel.issue_ticket_atoms`
must come **out** of `venue.order`'s writer set in three places (its Writes line does not name the
table), and *"+ door_pin path"* must come out of `venue.scan`'s — **a PIN is a credential, not a
writer.**

## THE OWNER-DECISION SET — two, and I did not choose either

**`E-1` — `catalog.event_session.session_version`: who bumps the counter.**
*Meaning 1:* the RPC contract lists it among the **three columns the session-update RPC must never
touch** — *"a monotone counter owned by the notification plane"*. But no notify function is contracted
to write it, so under this reading **the column has zero writers** and a Gate-L build ships a
permanently-`1` counter. *Meaning 2:* the schema spec is equally explicit and opposite — *"advanced
**only** by the session-update RPC, inside the same transaction … no other writer touches it"* — and
argues it is **correctness-blocking**: three notification dedupe keys embed it, so **a venue that
moves the door time twice cannot notify twice**, and *"the failure is silent by construction, so it
would never surface in testing."* Both are coherent. Choosing Meaning 1 means naming a notify writer
and accepting an inert counter at Gate L; choosing Meaning 2 means the RPC document deletes a line it
states as a hard prohibition.

**`E-2` — `market.bid`: the bid ledger's home** (already registered as `R-9`).
*Meaning 1:* native-only auctions are not offered in MVP — `public.bids` stays the ledger, the frozen
finalizer stays the finalizer, and a native-only auction fails **at `create_auction`, not at bid
time**, *"failing at the first door rather than after a seller has collected bids."* Under this
reading `market.bid` never exists and its registry row should not either. *Meaning 2:* schedule the
extension-point table into `088` — a new table, a contracted writer, an RLS matrix and a finalizer.
The RPC document states the stakes and stops: *"it must be decided before `088` is written, because
an implementer facing this silence will create a `market.bid` table that no package specifies."*
**`market.auction`'s missing finalize sweep is downstream of this and cannot close before it.**

## THE FOUR FALSE POSITIVES — defects in the governance artifact, not the architecture

**`F-1` — `venue.door_manifest_entry` was marked DIVERGENT with no divergent site anywhere.** All
three documents that state its write authority say exactly `venue.open_door_manifest`. The only
candidate was a **merged matrix covering two tables**, whose service-role cell names the function that
writes the *other* one. Reading a two-table merged matrix as a per-table writer list is a derivation
artefact. **Corrected to `OK` in this pass.**

**`F-2` — *"an executable writer of the money-denial audit row"* is not missing.** RPC §17.9 is
already repaired under `S-17`/`C106` and is executable as written. What remains is a **class-A
transcription** failure in five documents at six places. **This inflated the missing-contract count by
one and misdirected the repair at the wrong document.**

**`F-3` — the registry adds `kernel.admin_refund` as a `venue.order` writer; the canonical contract
does not.** Its complete Writes line does not name the table, and the contrast is instructive:
`kernel.refund_primary_order` **does**, and the dispute path deliberately does not touch the order
aggregate. **The registry committed the same extra-writer error it correctly diagnoses one column
over.** Flagged, not corrected — the triage itself asks for intent verification against the dispute
path first.

**`F-4` — *"a phrase appearing once corpus-wide"* is false; it appears three times.** The **finding**
is correct and in fact **understated**: three of the five `kernel.org_invite.status` labels have no
writer, not one. Only the rhetoric was wrong, and it argued for lower priority than the evidence
supports.

## THE GATE DEFECT THIS TRIAGE FOUND — now fixed

Check `H` validated `len(writers) == len(kinds)` and **never the section field**. Two rows were
already inconsistent under the unchecked column. **Adding the check caught four**, not two.

The section column is the **second witness**: the kind column catches a writer dropped from one
column, and the section column catches one dropped from both. The registry's own prose claimed the
kind column was *"how a trigger or cron writer would otherwise vanish silently"* — **it was half a
mechanism.** Negative fixtures: **15 → 16**.
