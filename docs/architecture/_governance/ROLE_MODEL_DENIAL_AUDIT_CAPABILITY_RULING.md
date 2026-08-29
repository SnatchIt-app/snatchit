# Denial-Audit Capability — owner ruling applied, and the one bit it does not settle

**2026-08-28.** Owner ruling: **`PHASE_2_ROLE_MODEL_SPEC.md` is the single normative owner of
capability existence, identifiers, semantics, and capability → RPC/function mapping.** Ratification
row **`OR-8`**.

> ## STATUS: `X-8` REMAINS **UNRESOLVED**, and the row was NOT written.
>
> ```
> CAPABILITY FORM      DETERMINISTIC      <BLOCK LETTER><next free ordinal>, no separator
> CAPABILITY BLOCK     NOT DETERMINISTIC  two rule-consistent options: A7 or B13
> ```
>
> The naming convention was induced mechanically from **69 existing capability ids with zero
> exceptions**. It fixes everything about the identifier **except the block letter**, and the corpus
> contains no tiebreaker. Per the instruction — *"if multiple names are equally valid, STOP … do not
> proceed by preference"* — **no row was added and `PHASE_2_ROLE_MODEL_SPEC.md` was not edited.**

## The security question, answered first and from the contract

**Call posture: `B` — INDIRECT. `NEW HUMAN EXECUTE AUTHORITY CREATED: NO`.**

The only callers in the entire corpus are two **edge functions**, `payout-execute` and
`refund-execute`, each invoking it *"in a separate transaction"*, on the **caller's own
`Authorization` client**, after catching a money-RPC denial. It is an **EA-1 call**, explicitly
**removed** from the service-role list. It is not service-only (*"never `service_role`… It RAISES when
`auth.uid()` IS NULL"*), not a trigger (*"Locks: none. SSCAS: n/a"*), and has **no client route in any
product spec** — zero occurrences in the RN and dashboard specs, and **no role predicate of any kind**
in its contract.

**Why a capability row creates nothing.** The `GRANT EXECUTE TO authenticated` is already ratified
**twice** (`C93` RATIFIED, `C106` DOC-FIX-APPLIED) and already written into the canonical contract.
The ratification record says it outright: the grant *"moves to the design schema §1.12.1 already
ratified as `C93`, **resolving a contradiction rather than making a choice**."* The row transcribes a
ratified grant into the document that was silent about it.

**And the change is a net narrowing, not a widening.** The row would make `SVC` = `·` — **the first
denial of `service_role` anywhere in the 69-row matrix.** The `service_role`-only configuration is
provably unbuildable; both grantees is barred by construction.

## The naming convention, induced from 69 ids with zero exceptions

| property | rule |
|---|---|
| form | `<BLOCK LETTER><ORDINAL>` — one uppercase letter, then a 1-based integer |
| separator | **none** — no dot, dash, underscore, colon or space |
| plane prefix | **none, ever** — the plane is carried by the *column* (principal), never the id |
| block letter | the §5.3 subject-block heading the row sits under |
| ordinal | next free integer in that block; blocks are contiguous, no gaps, no reuse |
| internal/server capabilities | **there is no distinct form, because none exist** — verified mechanically: `SVC` is `R` or `A` on all 69 rows and `·` on none, and no row is SVC-only |

## `OWNER NAMING DECISION REQUIRED` — two options, and they are the smallest set

| | id | the rule-consistent case |
|:--|:--|---|
| **(a)** | **`A7`** | Block **A. Platform governance** is where the **object** lives — `A5 Read kernel.admin_audit (security plane)` is the only other `kernel.admin_audit` capability, and this function's sole write is `kernel.admin_audit`. Block A is wholly inside subject `ROLE-CAP`, where `ROLE_MODEL` is the **sole** owner. |
| **(b)** | **`B13`** | Block **B. Money, custody & settlement** is where the **subject matter** lives — the function is one of *"the nine money-authority RPCs"* of package `085`, is contracted in RPC §17 (money), and its allow-list is closed over money-`*.denied` actions. |

> **One consequence you should see before choosing — stated as fact, not as a recommendation.**
> §5.3's money block is **not** governed by `ROLE_MODEL` alone: the domain architecture's §7.6 sits
> above §5.3 **B**, and `ROLE_MODEL` §15 records that the money block is *"transcribed from the frozen
> corpus, not decided."* So **`B13` would create a §5.3 cell with no upstream row in DA §7.6 —
> reproducing the exact two-owners-one-cell shape that `X-8` IS.** `A7` sits entirely inside
> `ROLE-CAP`, uncontested.

A third candidate — block **I**, the derived consumer plane — was considered and **rejected on the
heading's domain word**: denial audit is not consumer commerce, and no other block is chosen
structurally. A new block **J** has no precedent. The option set is therefore provably two.

## The row, fully derived except the id — ready to paste once the block is chosen

| field | value |
|---|---|
| id | `A7` **or** `B13` — pending |
| description | `Record own money-action denial (kernel.admin_audit)` (A-block phrasing) / `Record a denied money action` (B-block phrasing) |
| governed function | `kernel.record_money_denial(p_action, p_subject_kind, p_subject_id, p_error_code)` |
| **call posture** | **INDIRECT** |
| security relevance | the only audit path for a failed money predicate — a failed predicate `RAISE`s and takes the in-txn audit row with it, and Postgres has no autonomous transactions. The fact it must carry is **denials grouped by actor**, which is why no sentinel and no actor parameter is admissible |
| any human/product role directly possesses it? | **NO — none** |

**Cell values are forced by the contract, not chosen:** `ANO` `·` (never anon) · `DOO` `·` (door
session has no `auth.uid()`, and the function raises on NULL) · **`SVC` `·`** (never service_role; a
service-role invocation raises and writes no row) · all 17 authenticated principals `R◐`.

**Why that shape grants nothing.** `R` means *"permitted exclusively inside a `SECURITY DEFINER` RPC"*
— the matrix has **no direct-write grant vocabulary at all**. `◐` means *own rows*, and the scope is
**self, always**, because `actor_identity := auth.uid()` is server-derived and an assertion pins that
**no parameter can change it**. **The cell is identical for `FAN` and for `PAD`** — holding any role
adds nothing, which is the proof that no role possesses it.

**Flag for the block footnote:** this row would carry the **first `·` in the `SVC` column in the whole
matrix**. That is forced by the contract, but it is first-of-kind and must be annotated so no reader
reads it as an omission.

## TWO BLOCKERS THAT SURVIVE THE NAMING DECISION

**1. The mapping has no home that exists.** The ruling gives `ROLE_MODEL` the capability→RPC mapping.
**`ROLE_MODEL` carries no such map in any form** — §5.3 has two column groups, Capability and the 20
principals, and the only RPC names in the file are in footnotes. The map lives today in the RLS spec,
which under the ruling becomes **derived**. So the normative entry needs either a new mapping column
on §5.3 or a new `ROLE_MODEL` §5.4, with the RLS section restated as its roll-up. **This is an
ownership defect the ruling creates and the corpus does not yet reflect.**

**2. `ID-5` blocks the mapping outright.** The RLS map states: *"**Every `DEF` RPC is deliberately
absent from this map:** a definer-only primitive implements no principal's capability, and mapping one
to a §5.3 cell would reintroduce the human grant the `DEF` class exists to deny."* **
`record_money_denial` is still labelled `DEF` in two places** — the §17.9 heading and §0.1a — while
its own body contracts `authenticated`. **The RPC owner must repair `ID-5` first**, or the map's
exclusion rule contradicts the new entry on the day it is written.

## PRE-EXISTING DEFECTS IN THE CAPABILITY REGISTRY — found while verifying the join

Not created by this work, not resolved by it, and each is the same failure shape as `X-8`:

**Two orphan capabilities — an EXEC cell with no RPC anywhere.**
**`B7` "Resolve dispute (escrow)"** carries **dual control and step-up** for three platform principals
— and **no RPC in the corpus implements it.** The map's money rows jump `B6 → B8`. A ratified capability
with real security machinery, implemented by nothing. `I4` "Referral / ambassador program" is likewise
unmapped.

**Three duplicate semantic mappings** — one RPC in two or more capability cells (`approve_refund_request`
in two, `update_event` in **three**, `review_attribution_flag` in two). Each is annotated as a
deliberate arm-split, but **none is expressed as a distinct mapping key, so a mechanical join cannot
tell an intentional split from drift.**

**Four uncontracted or aliased targets** — `admin_refund`, `update_organization`, `set_org_status` /
`grant_platform_role` (all mapped, never contracted — gaps `G-7`, `G-12`, `G-20`), and
**`venue.record_scan`, which `X-6` established is a delegating wrapper, not the writer.** `X-6` was
ruled to RPC by `OR-7` and **the map row was never re-derived.**
