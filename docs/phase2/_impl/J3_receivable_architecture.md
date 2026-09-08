# J3 — RECEIVABLE / NEGATIVE-OBLIGATION ARCHITECTURE

**Agent C, backend-only train · design analysis, no DDL written · branch `feature/venue-native-and-product-v2` @ `09e167f`**

Scope: determine the correct durable primitive for a realized, **organization-scoped** debt to the
platform — a post-payout refund or lost chargeback — or determine that none is needed. No migration
SQL is proposed here; the shape is settled here and implemented elsewhere.

Physical verification was performed read-only against the local rehearsal database
`snatchit_rehears_final`, which carries `093` (both `kernel.settlement_primary_lines` and
`kernel.settlement_payout_maturity` are present).

---

## 0. THE ONE-PARAGRAPH ANSWER

The debt is **already booked** — a settlement that nets negative is a closed, immutable, correct
ledger fact (`venue.settlement.net_minor` is signed and unconstrained; H4 executed a `-5000` close
and `settlement_waterfall_ck` held). **Netting is also already built** — the shipped chargeback arm
emits an automatic negative settlement line at every close (`088:351-362` / `093:1180-1196`), which
`A_venue_money.md:188` names "recovery by netting only". What does **not** exist is (a) a way for the
**platform** to book a debt without the debtor's cooperation, and (b) any durable record of what the
netting **failed** to recover. The correct primitive is therefore **not a balance**, **not
`kernel.reserve`**, and **not a new netting mechanism**: it is an **append-only, per-origin,
org-scoped obligation record — the structural twin of the already-shipped
`kernel.identity_obligation` (§1.10a) — that records the shortfall, funds nothing, nets nothing, and
resolves by an audited platform act.** Existing netting is left exactly as ratified; the new object
catches only what falls through it. **`kernel.reserve` stays empty; E-149's two preconditions do not
become due. A ratification row IS required** (§5-bis).

---

## 1. WHAT GATE-M ALREADY DECIDED (verified, with citations)

| # | Decision | Evidence |
|---|---|---|
| 1 | `kernel.reserve` is the **C29 MONEY reserve** — a *funding source* for instant payout / cancellation refunds / C25 auto-refund. Explicitly **not** an inventory reservation. | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1268-1277`; `091:15-19` |
| 2 | The stub is sealed: RLS on, **zero policies**, `REVOKE ALL` from `public/anon/authenticated/service_role`. **Physically confirmed:** `relrowsecurity=t`, `relacl={postgres=arwdDxtm/postgres}`, `0` policies. | `091:43-45`; live probe |
| 3 | `balance_minor` carries **NO CHECK** so "a Gate-M receivable posture — a negative balance — is not pre-empted". **Physically confirmed:** only two constraints exist, `reserve_pkey` and `reserve_org_id_fkey … ON DELETE RESTRICT`. | E-149 (`POST_FREEZE_AMENDMENTS.md:2497`); live probe |
| 4 | Two preconditions are **recorded so they are confronted, not inherited**: the Gate-M writer must state one-per-org vs one-per-(org, currency) and add the unique **before its first write**; and `integer` caps at 2,147,483,647, so **int8 widening is a Gate-M precondition**. | E-149 |
| 5 | A Gate-M writer **will be a definer path** (no dormant machine grant on a money table — the E-118/E-106 class). | E-150 |
| 6 | `091` asserts as a *checked property* that the table is "ALWAYS EMPTY and ALWAYS DROPPABLE; nothing may be added to it", and its rollback DROPs behind a guard that **refuses a non-empty stub**. | `091:13-15`; E-151 |
| 7 | **C30 (fan liability) was partially built and org debt was explicitly carved out of it.** `kernel.identity_obligation` ships in MVP under `F-P2-1`/`OR-21`, and its `origin_kind` enum note states: "Org-side negative-settlement carry is **deliberately excluded** — org debt is BP-11's org's (C31, Gate-M). Extending the enum requires a ratification row." | schema `§1.10a:1186`; `085:165-198` |
| 8 | Money spec §9.4 stands unamended — **"No reserve. No clawback. No instant payout."** `identity_obligation` and `dispute_native` "fund nothing, net nothing"; **recovery execution remains Gate-M**. | `PHASE_2_MONEY_AUTHORITY_SPEC.md:1486-1502` |
| 9 | The org-side chargeback debit is **org-scoped by design, with no venue or event predicate**: it lands "in the org's **NEXT** settlement to close". `093` reproduces this deliberately — "the deliberate absence of a scope predicate on the chargeback arm (088:311-316 … which is 088's design and **not 093's to change**)". | `088:310-316`; `093:1131-1133`; seam body `093:1180-1190` |
| 10 | The native-sale payout writer is **CLOSED-AS-GATED** (`R-38`/`C135`) — owed by the Gate-M amendment, and it "may not be closed by build-time invention". | `PHASE_2_RPC_FUNCTION_CONTRACTS.md:7358` |
| 11 | The domain architecture already **splits the problem in two**: "Negative balances from post-payout refunds **carry to the next payout**, never rewrite a paid settlement — and for a **dormant org with no next payout**, that 'carry' is a receivable the Gate-M double-entry money ledger (C31) names as a **first-class balance** rather than an implicit stranded value." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:411` |

**Row 11 is the most important thing Gate-M already decided, and it is the one the brief's framing
obscures.** The corpus does not ask for a receivable *instead of* a carry. It asks for a carry, and
for a first-class balance **only in the residual case where no carry is possible**. Everything below
follows from taking that split seriously.

---

## 2. WHAT IS ALREADY TRUE (so the design does not re-invent it)

1. **A signed, append-only, immutable money ledger already exists.** `venue.settlement_line.amount_minor`
   is `integer not null` and deliberately **unconstrained in sign** (`087:100`, comment `-- signed`);
   `tg_settlement_line_append_only` raises on any UPDATE or DELETE (`087:110-112`); `REVOKE UPDATE,
   DELETE … FROM service_role` (`087:115`). The bucket derivation is sign-driven (`093:697-704` /
   `087:326-333`) and `settlement_waterfall_ck` makes a violating header unstorable (`087:61-66`).
2. **A negative net is already storable and already correct.** `close_settlement` computes
   `v_net := v_gross - v_fees - v_refunds` in `bigint`, range-guards it to the full signed-int32
   window **including negatives** (`093:715`, `v_net < -2147483648`), and writes it. H4's red team
   closed a `-5000` settlement and the waterfall identity held with 0 payouts minted.
3. **The debt therefore is not un-recorded. It is un-carried and un-collectable.**
   `close_settlement` mints a payout only `if v_net > 0` (`093:725`), and `093`'s own header states
   the consequence in the author's words: *"A negative net is NOT a receivable: this schema has no
   carry-forward object"* (`093:376`).
4. **Recovery-by-netting exists but is accidental and lossy.** Because the chargeback arm has no
   scope predicate, a later settlement for the same org absorbs the debit; when the later settlement
   has enough positive lines the org is silently underpaid with no line explaining it, and when it
   does not, the excess is destroyed. The activation matrix names this outcome exactly: *"silently
   confiscates a venue's later revenue while destroying the excess — a dispute with the venue waiting
   to happen"* (`PRIMARY_TICKETING_ACTIVATION_MATRIX.md:156`).
5. **A negative payout is physically unrepresentable.** Live probe: `payout_amount_minor_check CHECK
   ((amount_minor > 0))`. Bending `kernel.payout` into a debt object would require dropping that
   check — the single most load-bearing positivity invariant on the disbursement path, and the thing
   that makes `close_settlement` silently mint nothing rather than mint a negative instruction. **We
   do not touch it.** (The brief's warning is correct and is honoured.)
6. **The identity-side twin of this exact object is already built, shipped and tested** —
   `kernel.identity_obligation`, `085:165-198`: append-only, `amount_minor integer CHECK > 0`,
   closed `origin_kind` enum, forward-only `outstanding|recovered|written_off`,
   `UNIQUE(origin_kind, origin_ref)`, partial UNIQUE on `stripe_dispute_ref`, partial index
   `(debtor_identity_id) WHERE status='outstanding'`, `REVOKE DELETE … FROM service_role`, written by
   a definer RPC pair (`kernel.record_identity_obligation` / `kernel.resolve_identity_obligation`).

---

## 3. THE DECISIVE STRUCTURAL FACT — WHY THE LEDGER ALONE CANNOT CARRY THIS

**The platform cannot open a settlement.**

`venue.open_settlement`'s authority gate is (`087:237-239`):

```
if not (kernel.has_venue_role(p_venue_id, array['venue_finance'])
        or kernel.has_org_role(p_org_id, array['org_finance','org_owner'])) then
  raise exception 'insufficient_privilege: …' using errcode = '42501';
```

and `kernel.has_org_role` is **pure membership** — `select exists (select 1 from kernel.org_member m
where m.org_id = p_org_id and m.identity_id = auth.uid() and m.role = any(p_roles))` (`077:453-466`).
There is **no `kernel.is_platform` arm** anywhere in that check (contrast `venue.settlement`'s SELECT
policy, which *does* carry one, `087:79-81`).

Consequence: `venue.settlement_line.settlement_id` is `NOT NULL` FK to a header that only the
**debtor's own staff** (or its venue's finance staff) can create. A debt recorded solely as a
settlement line is a debt whose *booking depends on the debtor's cooperation*. An org that simply
stops opening settlements is an org whose chargeback losses can never be entered into the ledger at
all.

This is precisely why `kernel.identity_obligation`'s writer is a `service_role`/webhook definer path
(`085:1793`) and not a settlement line. **The org side needs the same property.** This single fact
eliminates candidate D-alone and is the strongest argument in this document.

---

## 4. CANDIDATE EVALUATION

Criteria: accounting correctness · ledger fit · append-only compatibility · operational complexity ·
migration complexity · auditability · honesty.

### A — new `kernel.organization_receivable` table
**Adopted, in a corrected form (A′, §5).** As literally named ("receivable", implying a running
balance) it is wrong for the same reason E is wrong (§4.5). As a **per-origin obligation record** it
is right, and the corpus already contains its blueprint. Migration complexity is moderate and fully
patterned: one table + two definer RPCs, both transcribable from `085:1793-1878`. Auditability is
excellent — every origin is a discrete, idempotency-keyed row with a resolution act and a
`kernel.admin_audit` row on both verbs.

### B — generalized obligation table (one table for identity + org debt)
**Rejected.** It requires reopening `OR-21`/`F-P2-1`: `kernel.identity_obligation.debtor_identity_id`
is `uuid NOT NULL REFERENCES auth.users(id)` (`085:167`) — an org id is unstorable and the FK cannot
be widened. Its `origin_kind` enum carries a **ratification requirement** to extend (schema §1.10a),
and it is the live operand of deletion predicate **BP-10** via
`kernel.has_outstanding_obligations` (RPC §20.7.12) and its partial index. Generalising it puts a
tombstone-safety predicate and a money predicate in one table for no accounting gain. Ruling C
reached the same conclusion from the other direction (`C_money_ledger_accounting.md:698`).

### C — settlement adjustment object
**Rejected as redundant.** `venue.settlement_line` **is** the adjustment ledger; the domain
architecture states the rule it enforces — "adjustments must append, not rewrite — Invariant 4"
(`SNATCH_IT_DOMAIN_ARCHITECTURE.md:411`). A second adjustment table would be a shadow of it with a
second set of append-only triggers, a second reconciliation surface, and a second way for the
waterfall identity to drift. Everything C would do, D does inside the existing conservation proof.

### D — extension of the existing ledger (a new `settlement_line.cause` + a scoped recovery seam)
**Rejected as the record, and — after the coordinator's evidence — rejected as the recovery too.**
As the *record* it fails §3: the platform cannot create the container. As the *recovery* it is
**redundant and actively harmful**, because the recovery it would add **already ships**: the
chargeback arm nets automatically at every close (`088:351-362` / `093:1180-1196`). Adding a second
netting cause double-counts the same dispute and forces a body change to SSCAS #4's seam — see
§5-bis.2, where I withdraw the earlier draft that proposed exactly this.

What survives from D is the observation that made it attractive: the netting is **invisible to the
venue** ("the venue lost 4000 with no line item explaining it", `H4_maturity_ledger.md:272`). That is
a real defect, but it is a defect **in the existing chargeback line's presentation**, not an argument
for a new cause — the line *is* written; nothing renders it. It belongs to the dashboard surface and
to Q1's disclosure half, not to this object.

### E — `kernel.reserve` used as the Gate-M architecture intended
**Evaluated seriously and rejected as the receivable — on four independent grounds, any one
sufficient.** Note that "the architecture reserved a money table" is not the same claim as "the
architecture reserved *this* money table for *this* purpose"; E-149 says a negative balance is *not
pre-empted*, which is permission, not designation.

1. **A balance decrement is not idempotent, and the writer is webhook-driven.** The debt's origin is
   `charge.dispute.closed` / a lost `public.disputes` row — at-least-once delivery, retried by
   Stripe and by `069_webhook_retries_table`. `kernel.identity_obligation` survives replay because
   of `UNIQUE(origin_kind, origin_ref)` (`085:180`) and the partial UNIQUE on `stripe_dispute_ref`
   (`085:185-186`). `UPDATE kernel.reserve SET balance_minor = balance_minor - X` has **no
   idempotency key that the database can enforce**; a duplicate delivery double-debits an org and
   the row itself carries no evidence that it happened. This alone disqualifies a mutable balance as
   the *system of record* for a debt on this rail.
2. **It conflates two economic objects in one signed field.** The corpus names `reserve` a *funding
   source* — money the platform **holds** (schema §1.11; `SNATCH_IT_DOMAIN_ARCHITECTURE.md:750`,
   the "money-reversal envelope" whose reserve *funds and gates* clawbacks). A receivable is money
   the org **owes**. Encoding "we hold their money" and "they owe us money" as the sign of one
   integer is the same dishonesty the brief flags for `kernel.payout` — and it makes the single most
   important operator question ("is this org in credit or in debt?") depend on a sign convention that
   nothing in the corpus states.
3. **It loses per-origin identity and the resolution act.** A balance cannot answer "which dispute",
   "when", "recovered or written off, by whom, under what reason code" — the columns
   `identity_obligation` carries precisely because a realized loss is an auditable event, not a
   number.
4. **Writing it retires 091's rollback.** `091`'s guard "refuses a non-empty stub (forward-fix, never
   drop money state)" (E-149/E-151). That is an acceptable price for a real need; it is not an
   acceptable price for a shape that is worse than the alternative on grounds 1-3.

**What happens to `kernel.reserve` under this recommendation: nothing. It stays empty, sealed and
droppable, and keeps its C29 funding-pool purpose for the day instant payout is actually built.**
Its stated purpose is untouched by anything here, and no part of this design needs it.

### F — something else: "no object is needed"
**Live, and it is the owner's to pick.** G5 option 3 (Stripe fixed reserves on connected accounts)
**prevents** the debt rather than recording it: if Stripe withholds the funds, the platform recovers
from the reserve and no receivable ever arises. That genuinely displaces this entire design for the
covered window. It does **not** close the tail — Stripe's reserve ceiling is 180 days, so a ticket
sold more than 180 days ahead is not fully covered, and the ToS requires the reserve policy be
disclosed to the connected account (`G2_settlement_maturity.md:381-385`). And it changes the venue
commercial relationship, which is an onboarding decision, not a schema one. **If the owner picks
option 3, the correct answer to this brief is "build nothing" for the covered window and a much
smaller object (or an accepted residual) for the >180-day tail.**

---

## 5. RECOMMENDED SHAPE — A′ (the record only; netting stays where it is)

**Two objects, one economics, mirroring what the corpus already built for identities.**

### 5.1 The record — `kernel.organization_obligation` (new)

The org-scoped structural twin of `kernel.identity_obligation` (§1.10a), transcribed rather than
invented. Properties that are load-bearing, not decorative:

- `org_id uuid NOT NULL REFERENCES kernel.organization(org_id) ON DELETE RESTRICT` — the house action
  for every FK to `kernel.organization` (`077`, `085:114`, `091:31`), and it buys the "a debt blocks
  org deletion" property for free, exactly as `identity_obligation`'s FK does for BP-10.
- `origin_kind text NOT NULL CHECK (…)` — a **closed, derived, minimal** enum. On the evidence the
  reachable origins today are exactly two: a lost/`charge_refunded` dispute on a primary order whose
  proceeds the org already holds, and a platform-funded refund issued after disbursement. Do **not**
  add a member for anything without a producer; extending the enum should carry the same ratification
  requirement §1.10a carries.
- `origin_ref uuid NOT NULL`, **no hard FK** — the `kernel.payout.cause_ref` soft-reference discipline
  (points across schemas/rails without an ordering cycle), existence-verified by the writer.
- `amount_minor integer NOT NULL CHECK (> 0)` — **a positive magnitude, never a negative number.**
  Direction is carried by the object's identity, not by a sign. This keeps every positivity invariant
  on the money layer intact and matches `identity_obligation:171` and `dispute_native`'s deliberate
  `>= 0` contrast.
- `currency text NOT NULL DEFAULT 'USD'` — per-row, per-origin (see §8).
- `status text NOT NULL DEFAULT 'outstanding' CHECK IN ('outstanding','recovered','written_off')`,
  forward-only, single transition, terminal XOR, guarded single-writer under `FOR UPDATE`; plus the
  `resolution_reason_code`/`resolved_by`/`resolved_at` triple with the §1.9/§1.10 pairing CHECK.
- `UNIQUE(origin_kind, origin_ref)` and a partial UNIQUE on `stripe_dispute_ref` — **the idempotency
  the webhook path requires** (§4.5 ground 1).
- Partial index `(org_id) WHERE status = 'outstanding'` — this index **is** the "what does this org
  owe us" read and the recovery seam's driving scan.
- Append-only in the shipped sense: origin columns write-once (INSERT-only); no UPDATE except the
  guarded transition + resolution triple; **`REVOKE DELETE` outright** (GP-2).
- RLS money-custody-RPC-only, DENY-ALL to every client role; written by a definer RPC pair
  (`record_*` service_role/webhook, `resolve_*` edge-fronted `platform_risk`/`platform_admin`), each
  writing a `kernel.admin_audit` row in the same transaction. E-150's "a Gate-M writer will be a
  definer path" is satisfied by construction.

### 5.2 The origin set — the SHORTFALL, not the dispute (corrected)

**An earlier draft of this document proposed a new `venue.settlement_line.cause` that would net the
obligation. That is withdrawn — it was wrong, and §5-bis explains why (it double-counts against the
netting that already ships, and it would require a body change to SSCAS #4's seam).** The corrected
origin set attaches the obligation to what netting *failed* to do:

- **`settlement_shortfall`** — `origin_ref = settlement_id`. Booked when a settlement closes with
  `net_minor < 0`. This is the branch `close_settlement` reaches at `093:725` (`if v_net > 0`) and
  today does **nothing** on. Idempotent by construction: `UNIQUE(origin_kind, origin_ref)` over a
  settlement that can close only once (`093:673`, `noop_replay`). This origin **is** DA:411's
  "implicit stranded value" made into a first-class fact, and it is the direct repair of "destroying
  the excess" — the residual stops vanishing.
- **`unlined_reversal`** — for the dormant-org case, where the debit is never even *offered* because
  no settlement is ever opened (§3). Recorded by an audited platform act on the
  `resolve_identity_obligation` pattern, `origin_ref = dispute_id` or `refund_id`, with a guard that
  the origin carries no `chargeback`/`refund_void` line in any settlement (otherwise it is already
  netted and booking it would double-count). **Whether this is swept automatically after N days or
  raised by an operator is a policy question, not an architectural one — filed as Q9.**

No other origin has a producer, and none should be invented. Note that these two origins are
**disjoint by construction**: the first exists only where a close happened, the second only where it
did not.

### 5.3 Where the write happens

`settlement_shortfall`'s natural writer is `kernel.close_settlement` itself — one INSERT in an
existing dead branch, deterministic, impossible to forget. The cost is a body change to SSCAS #4.
The alternative is a separate platform-invoked definer RPC that books shortfalls from already-closed
headers, which touches nothing and is idempotent on the same key, but can be *not run*.

**Recommendation: the in-close INSERT**, because a debt record that depends on someone remembering to
run a sweep reproduces the failure mode it exists to fix. The change is additive, sits in a branch
that currently has no statements, and writes a table with no other writer — so R7's money-single-path
reading is unaffected (`close_settlement` already writes `settlement_line` and `payout`).
**Flagged for the implementing agent as the one place where this design touches a
safety-critical function** (§10, Q10).

### 5.4 What this does NOT do — stated so it is not over-claimed

It does **not** build C31 (no double-entry journal, no balanced entries, no `kernel.ledger_entry`).
It does **not** build C29 (no reserve math, no funding pool, no instant payout). It does **not**
amend MONEY §9.4 — like `identity_obligation` and `dispute_native` before it, it **records** a debt
and resolves it by an audited platform act; **it funds nothing, it nets nothing, it gates no
payout**, and it executes no collection against an unwilling org. **It changes no existing money
behaviour whatsoever**: the chargeback and `refund_void` arms keep their exact shipped semantics, and
every number the system pays today it still pays. It does **not** touch
`kernel.identity_obligation`, `OR-21`, or BP-10. It does **not** unblock native resale, which stays
dark behind `feature.native_resale_enabled` + A-GATEM regardless.

---

## 5-bis. THE NETTING QUESTION, AND THE GOVERNANCE ANSWER

*(Added in response to the coordinator's mid-task evidence. All three citations verified.)*

### 5-bis.1 "Auto-offset is a departure from the established pattern" — TRUE for identities, FALSE for orgs

The coordinator is right that `kernel.identity_obligation` **"records debt and resolves it by an
audited platform act (`recovered`/`written_off`); it funds nothing, nets nothing, gates no payout"**
(`PHASE_2_MONEY_AUTHORITY_SPEC.md:1493-1496` — verified verbatim). But that posture does **not**
generalise to the org rail, for a structural reason rather than a policy one: **an identity has no
settlement ledger to net into.** There is no `identity.settlement`, no periodic identity close, no
identity waterfall. `identity_obligation` nets nothing because on the identity rail there is nothing
to net against — not because netting was weighed and rejected.

On the org rail the opposite is true, and it is **already shipped and already automatic**:

- `kernel.settlement_royalty_lines`'s chargeback arm emits a **negative** `settlement_line` for every
  terminal-lost dispute on this org's primary orders, at **every close**, with **no human act, no
  obligation row and no gate** (`088:351-362`, reproduced with a headroom cap at `093:1180-1196`).
- `088:310-316` states this as design: the debit lands "in the org's **NEXT** settlement to close".
- `093:1131-1133` reaffirms it deliberately: the absence of a scope predicate is "088's design and
  **not 093's to change**".
- `A_venue_money.md:188` names the resulting posture exactly: **"recovery by netting only"**.

**So org-side auto-netting is the status quo, not the proposal.** The genuine departure would be to
*stop* netting — which would require a body change to the seam and would leave the platform with no
recovery mechanism at all. Nobody is proposing that, and this document does not.

### 5-bis.2 What this means for the recommended shape — a correction I am making, not defending

The consequence is that my earlier §5.2 (a new `obligation_recovery` cause that nets the obligation)
was **wrong, and I withdraw it.** Two defects, either fatal:

1. **Double-count.** The dispute would be netted twice — once by the shipped chargeback arm, once by
   the new recovery cause. That is precisely the double-debit defect `093`'s 10h was written to fix
   between `refund_void` and `chargeback` (`093:1091-1098`), reintroduced one cause over.
2. **It would force a body change to the chargeback seam** to suppress the existing arm — SSCAS #4's
   candidate producer, the function `087:204-207` requires to never raise.

The corrected shape (§5.2 as it now stands) attaches the obligation to the **shortfall** instead: the
netting keeps its shipped semantics untouched, and the obligation records only what netting could not
recover. Under that shape the new object's attestation is **identical to `identity_obligation`'s and
literally true** — it funds nothing, nets nothing, gates no payout. **The corpus's ratified posture is
therefore adopted, not departed from.**

This is a smaller, safer and more honest design than the one I first wrote, and the coordinator's
evidence is what produced it.

### 5-bis.3 The MONEY §67 premise — examined, and it has partially expired

`PHASE_2_MONEY_AUTHORITY_SPEC.md:67` reads **"Gate M (C29 reserve / C31 double-entry) not required —
CONFIRMED. Nothing here needs a reserve, a clawback, or instant payout. MVP payout stays
settlement-cadenced."** Verified verbatim — and the context matters: it is a row in an **invariant
attestation table** whose header states it was *"checked before anything below was written"*, and
whose subject is O-1/O-3, the refund-authority and payout-visibility design. The scope word is
**"here"**. It attests that *that design* needs no reserve. It is not a finding that post-payout
reversal is a solved problem.

Two independent confirmations that the reachable world has changed underneath it:

1. **The protection was an absence, and this train removed it.** `FINAL_ACTIVATION_BLOCKER_RULINGS.md`
   (G5): *"It is tolerable right now for exactly one reason: **no payout executor exists**, so no
   venue can be paid at all… **This train wrote the executor.**"* And `H8_payout_executor.md:184-186`:
   *"Deploying this without the receivable object is not safe."*
2. **The corpus never claimed the tail was closed.** §9.4 says in the same breath that
   *"recovery execution remains Gate-M"* (`:1496`, `:1502`) — i.e. §67 and §9.4 together assert
   "MVP needs no reserve **because MVP does not recover**", which is consistent, and is exactly the
   posture that stops being tenable once money can leave.

**Honest verdict: §67 is still true as written and still true of what it attests. It did not
anticipate post-payout reversal because, when it was written, post-payout was unreachable. It should
be re-attested rather than either obeyed or overridden — and re-attesting it is the owner act this
document exists to prepare.**

### 5-bis.4 Does the recommended shape require a RATIFICATION ROW? **YES.**

Answered explicitly, because it is a governance question.

**It does NOT extend `kernel.identity_obligation.origin_kind`.** The design creates a separate table
with its own closed enum and touches neither `identity_obligation`, nor its enum, nor BP-10, nor
`OR-21`. So the specific trigger in `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1186` — *"Extending the
enum requires a ratification row"* — is **not** fired.

**But a ratification row is required anyway, on two independent grounds:**

1. **The same sentence assigns this work elsewhere.** `:1186` reads: *"Org-side negative-settlement
   carry is **deliberately excluded** — org debt is BP-11's org's (C31, Gate-M)."* An object whose
   entire purpose is to record org-side negative-settlement carry is the thing that sentence excludes
   and assigns to C31/Gate-M. Building it in MVP is a **Gate-M amendment or an explicitly ratified
   additive exception**, and it may not be inherited from the fact that E-149 left `balance_minor`
   unconstrained. E-149 is permission for a *shape*; it is not authority for a *scope change*.
2. **It re-attests MONEY §67 and touches §9.4's neighbourhood.** §67's "not required — CONFIRMED" is a
   signed invariant row (§5-bis.3). An object that exists because post-payout recovery is now
   reachable changes the premise of that row, and the owner should sign the new premise rather than
   have it changed by a migration.

**The precedent is exact and the corpus has walked it twice.** `kernel.identity_obligation` was built
in MVP as an additive record under **`F-P2-1` / `OR-21`**, and `kernel.dispute_native` under
**`R-40`** — both ratified by their own owner rulings, both explicitly stated as **not** amending
§9.4 (`MONEY:1493-1502`). **This object should ship the same way: a numbered owner ruling, an entry in
the amendment record, and a "funds nothing, nets nothing, gates no payout" attestation that is
literally true of it** — which, under the corrected §5.2 shape, it is.

**What the coordinator should put in front of the owner is therefore one ratification carrying three
bits:** (i) build the org-side record now vs. take G5 option 1 or 3; (ii) Q1's cross-venue economics
(which, note, is a question about the **existing** netting, and is live whether or not this object is
built); and (iii) re-attest MONEY §67 for the post-executor world.

---

## 6. THE APPEND-ONLY VERDICT

**Event-sourced, and the reason is mechanical rather than stylistic.**

The house style is append-only, but style alone would not settle this — `kernel.reserve` is the
architecture's own reserved object and it is a mutable balance with `tg_reserve_set_updated_at`. The
tension is real and the brief is right to press it. It resolves on the nature of the **writer**, not
the taste of the schema:

**the debt's producer is an at-least-once webhook.** Stripe retries `charge.dispute.closed`;
`069_webhook_retries_table` retries locally. Under at-least-once delivery, `balance = balance - X`
is unsafe with no database-enforceable remedy, while `INSERT … UNIQUE(origin_kind, origin_ref)` is
safe with a remedy the database enforces for free. Every idempotent money writer in this codebase is
built the second way — `payout_idempotency_uq` (`085:138`), `refund_idempotency_uq` (`085:93`),
`identity_obligation_origin_uq` (`085:180`), `order_buyer_command_uq` (`082:93`),
`market_sale_buyer_command_uq` (`088:131`). A mutable balance is the one shape in the money layer
with no member of that family.

Two consequences worth stating:

1. **The projection is derivable and needs no stored balance.** "What does org X owe us" is
   `SELECT sum(amount_minor) FROM kernel.organization_obligation WHERE org_id = X AND status =
   'outstanding'` minus the recoveries already lined — served by the partial index in §5.1. No
   materialisation is required for MVP, and none should be built until an operator surface actually
   demands one. (The traceability matrix already refuses a dashboard reserve balance on the honest
   ground that "rendering a reserve balance from an always-empty table would be a false statement to
   an operator" — `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md:425`.)
2. **Append-only sidesteps E-149's int8 precondition entirely** (§9).

**And it does not settle `kernel.reserve` against the ledgers, because it does not have to.** The two
objects are not competitors: an append-only obligation records a *debt event*; a mutable reserve
holds a *pool*. A pool legitimately has a running balance because a pool is not a fact about the
past. `091`'s mutability is correct for what `091` is, and irrelevant to what this is.

---

## 7. SCOPE — AND THE OWNER QUESTION I AM NOT ANSWERING

### 7.1 The recommendation: ORGANIZATION

The obligation is **org-scoped**, on four independent pieces of evidence:

1. Payout ownership is established at org level and has no venue equivalent — `kernel.payout.
   payee_org_id` (`085:114`), `payout_payee_xor_ck` (`085:139-142`), `payout_org_status_idx`
   (`085:148`).
2. The existing chargeback debit is **already** attached at org grain with **no venue or event
   predicate** — `join venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id`
   (`093:1188` / `088:357`) — and `088:310-316` states this as design: the debit lands "in the org's
   **NEXT** settlement to close".
3. `R2` ratified the deterministic economic owner as `catalog.event.org_id`, and explicitly
   **rejected** `catalog.venue.org_id` because it is a mutable tenancy pointer and "binding money to
   a mutable tenancy pointer means a room sale silently re-assigns the prior operator's receivables"
   (`R2_settlement_economic_owner.md:256`).
4. `kernel.organization` is the only party object with a Connect destination
   (`stripe_connect_account_ref`, `077:110`), so it is the only party money can actually be recovered
   from.

Venue, event, payout-destination and settlement scopes are all **rejected as the obligation's owner**
— they are attributes of the *origin* and of the *recovery*, not of the debt. (The origin's venue and
event remain fully recoverable through `origin_ref → payment_native → order → event_session → event`;
nothing is lost by not denormalising them onto the row.)

### 7.2 ORG A / Venue 1 loses 500; ORG A / Venue 2 earns 1000 — **OWNER ECONOMIC DECISION, NOT MINE**

I searched for a ratified answer and found a **split** result, which I record precisely:

- **The mechanism is ratified.** Cross-venue netting for chargebacks is not accidental at the
  mechanism level: `088:310-316` designs the debit to land in the org's *next* settlement with no
  scope predicate, and `093` explicitly declines to change it ("not 093's to change", `093:1132`).
  Under that mechanism, **today, the 500 does offset Venue 2's 1000** — Venue 2's settlement pays 500.
- **The economics is NOT ratified, and the corpus says so in its own voice.** The same behaviour is
  described by this train's own documents as *"future payout offset exists only **accidentally** …
  silently confiscates a venue's later revenue while destroying the excess — a dispute with the venue
  waiting to happen"* (`PRIMARY_TICKETING_ACTIVATION_MATRIX.md:156`;
  `H4_maturity_ledger.md:272`), and **G5 is unsigned** ("This document is NOT approved. No ruling
  below is in force." — `FINAL_ACTIVATION_BLOCKER_RULINGS.md`, signature block).

So the question the brief asks is live and it is an owner economic decision. **I refuse it and file
it** (§10, Q1). What I will state is the engineering consequence of each answer, because that part is
mine:

**Note the question is about the netting that ALREADY SHIPS**, not about anything this document
proposes — the recommended object nets nothing (§5-bis). Q1 is therefore live and needs an answer
whether or not the obligation table is ever built.

| Owner answer | Engineering consequence |
|---|---|
| **Yes — org-wide netting** (the status quo, now made explicit rather than accidental) | **Zero code change.** The chargeback arm already has no scope predicate and `093` declined to add one. Cost is presentational only: the line must become **visible** on the settlement surface or it reproduces the "silent confiscation" defect verbatim. |
| **No — venue-ring-fenced** | A **body change to `kernel.settlement_royalty_lines`'s chargeback arm** to add the event-or-venue+period predicate the royalty/commission/primary arms already carry (`093:1163-1167`, `093:465-469`) — i.e. an explicit reversal of `088:310-316`, which `093` deliberately preserved. Also strictly *increases* platform loss (fewer debits recoverable), which pushes more volume into the obligation table. |
| **Yes, but disclosed and capped** | Status quo plus a per-settlement recovery cap (a `payout.%` config key, dual-controlled like the other four) and a surfaced line item. Most operationally defensible, most work. |

**A second, smaller owner question is forced by the same mechanics and is easy to miss:**
`venue.settlement.venue_id` is `NOT NULL` (`087:46`), so an org-wide recovery line **must** land
inside some particular venue's settlement, and that venue's `venue_finance` role can read it
(`087:80-81`). Cross-venue netting is therefore also a **disclosure** decision, not only an economic
one (§10, Q2).

---

## 8. CURRENCY

**Finding: the rail is effectively USD-only, and the proof is from columns and comparisons.**

- `venue.open_settlement(p_org_id, p_venue_id, p_event_id, p_period, p_command_key)` takes **no
  currency parameter**, and its INSERT names `(org_id, venue_id, event_id, period_start, period_end,
  status)` (`087:261-263`) — so `venue.settlement.currency` is **always** the column default `'USD'`.
  There is no code path that produces a non-USD settlement header.
- `venue.create_primary_checkout` writes the **literal** `'USD'` into `venue."order"` and
  `venue.order_item` (`082:439`, `082:445`) and returns the literal `'USD'` (`082:458`).
- `kernel.payout.currency` is written as `v_s.currency` from the settlement header (`087:342` /
  `093:830`) — therefore always `'USD'`.
- Every seam filters on equality, never converts: `ms.currency = s.currency` (`093:1161`),
  `d.currency = s.currency` (`093:1188`), `o.currency = s.currency` (`093:466`),
  `r.currency = so.currency` (`093:528`), `a.currency = v_s.currency` (`093:917`);
  `close_settlement` raises on a divergent candidate and re-scans after insert (`093:694-695`).
- **There is no FX model anywhere** — no rate table, no conversion, no ISO-4217 CHECK, no currency
  domain on any column in the money layer.
- **The only non-USD injection point in the entire money layer** is `venue.promoter.currency`, set
  from `p_terms ->> 'currency'` and validated only by `v_ccy !~ '^[A-Z]{3}$'` (`090:436`, `090:445`).
  Its blast radius is bounded and silent rather than dangerous: the commission seam filters
  `a.currency = v_s.currency` (`093:917`), so a `EUR` promoter's attributions simply **never line**.
  That is a latent silent-non-payment bug worth a separate note; it is **not** an FX exposure.
- Live probe on the rehearsal DB: `venue.settlement` and `kernel.payout` hold zero rows, so no
  non-USD money row exists to migrate.

**Verdict on the risk:** a USD receivable netting a non-USD payout is **hypothetical, not live** —
and the recommended shape makes it *structurally* impossible without any new policy, because the
obligation carries its own `currency` per row and the recovery seam filters
`obligation.currency = settlement.currency` in the identical shape the five existing seams use. A
foreign-currency debt would simply never be offered as a candidate.

**Is E-149's one-per-org vs one-per-(org, currency) question therefore forced? No — and that is a
property of the shape, not an evasion.** The question is forced only for a **single-row balance**,
where the row *is* the key and multi-currency would silently commingle. A per-origin append-only
table has no such row and no such key: it is naturally one-obligation-per-origin-fact, in whatever
currency that fact occurred. **This is the second independent argument for the append-only shape**
(the first is §6): it dissolves an open Gate-M precondition rather than answering it.

---

## 9. E-149 / E-150 PRECONDITIONS — MY ANSWERS

| Precondition | Answer |
|---|---|
| **Uniqueness — is a reserve one-per-org or one-per-(org, currency)?** | **Not due, because I do not recommend writing `kernel.reserve`.** The precondition binds "the Gate-M writer … before its first write"; under this recommendation there is no first write and `091` keeps its always-empty checked property and its droppable rollback. **If the owner overrides §4.5 and makes `reserve` the receivable anyway, the answer is one-per-(org, currency)** — `currency` is already a column on the stub (`091:33`), a single-row-per-org design would have to either drop it or lie about it, and the whole money layer's discipline is currency-equality comparison rather than commingling (§8). The unique must be added in the same migration as the writer, before its first write, exactly as E-149 requires. |
| **`integer` caps at 2,147,483,647 — is int8 widening a Gate-M precondition?** | **For `kernel.reserve`, yes and unchanged — a pool is an accumulator and accumulators outgrow int32.** For the recommended object, **no**: `amount_minor` is per-origin, one row per dispute or refund, and is bounded above by the payment it derives from, which is bounded by `venue."order".total_minor integer CHECK > 0` (`082:83`). `integer` is therefore correct, and it matches `kernel.identity_obligation.amount_minor integer CHECK > 0` (`085:171`) — divergence would be the anomaly. **The aggregate (Σ outstanding) must be computed in `bigint`**, per the `settlement_line_candidate.amount_minor bigint` / `close_settlement` `v_gross bigint` discipline (`087:29`, `093:645`, `093:715`). The recovery line inherits `settlement_line.amount_minor integer` and `close_settlement`'s existing `22003`-avoiding range guard, so it needs no new width work. |
| **E-150 — a Gate-M writer will be a definer path.** | **Satisfied and adopted verbatim.** Both verbs are `security definer set search_path = ''`, table is deny-all with `REVOKE ALL` from client roles, `record_*` reachable by `service_role`/webhook and `resolve_*` edge-fronted to `platform_risk`/`platform_admin` — the `085:1793-1878` pattern, unchanged. No dormant machine grant is added to any money table. |
| **E-151 — rollback discipline.** | A new table's rollback should carry `set local row_security = off` before its empty-guard count (the 081-087 house pattern E-151 identifies), and should refuse to drop when any row exists — forward-fix, never drop money state. |

---

## 10. OWNER QUESTIONS I REFUSED TO ANSWER

**Q1 — Should an obligation incurred at ORG A / Venue 1 offset ORG A / Venue 2's earnings?**
Economic, not architectural (§7.2). The mechanism is ratified (`088:310-316`); the economics is not,
and this train's own documents call the resulting behaviour a dispute waiting to happen. Three
engineering paths costed in §7.2.

**Q2 — Is a cross-venue recovery line a disclosure event?** `venue.settlement.venue_id` is NOT NULL
and `venue_finance` can read the settlement (`087:80-81`), so Venue 2's finance staff would see a
line item for a loss originating at Venue 1. That may be exactly right (transparency) or exactly
wrong (inter-venue confidentiality). Owner's call.

**Q3 — May an obligation ever be recovered by netting at all, or only by an off-platform act?** Under
the recommended shape the obligation itself nets nothing, so recovery is either (a) an audited
`recovered` transition after an off-platform payment, or (b) nothing, ending in `written_off`. Adding
platform-side netting *of the obligation* would reopen §5-bis.2's double-count and is deliberately
not designed here.

**Q4 — Who may `write_off`, and against what threshold?** On the identity side this is an audited
`platform_risk`/`platform_admin` act with no monetary threshold. Whether org write-offs need dual
control (and at what `payout.%`-style key) is a controls decision of the same family as
`payout.dual_control_min_minor`.

**Q5 — Should an outstanding org obligation *hold* that org's payouts?** `kernel.payout` already has
`hold_state`/`hold_reason_code` and a dispute-freeze precedent (`088:846-847`). Adding an
`outstanding_obligation` hold reason would be mechanically trivial and economically aggressive — it
converts a receivable into a freeze on unrelated revenue. **Deliberately not designed here.**

**Q6 — G5 itself: object, risk acceptance, or Stripe reserves?** §4.6 records that option 3 genuinely
displaces most of this design. G5 is unsigned; the payout executor must not deploy until it is.

**Q7 — Seed the backlog?** Closed settlements with `net_minor < 0` are pre-existing debt facts. Should
a migration seed obligations from them, or does the object start empty and apply forward-only? (Today
the population is zero — the rehearsal DB holds no settlements or payouts — so this is cheap to
decide now and expensive to decide later.) Note the schema spec's parallel instruction on the fan
side: outstanding `identity_obligation` rows "seed the receivable/Fan-Liability home … no row is
rewritten or deleted" (`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3960`).

**Q8 (raised in passing, not mine to fix)** — `venue.promoter.currency` accepts any `^[A-Z]{3}$`
(`090:445`) and a non-USD promoter's commissions then silently never line (§8). Separate defect,
separate owner.

**Q9 — For the dormant-org case (`unlined_reversal`, §5.2), is the debt swept automatically after N
days or raised by an operator?** A sweep books every uncollectable loss without anyone deciding to;
an operator act keeps the ledger free of noise but can silently not happen. Policy.

**Q10 — Is the `settlement_shortfall` INSERT allowed inside `kernel.close_settlement` (SSCAS #4)?**
§5.3 recommends yes (additive, in a currently-empty branch) and states the alternative. This is a
change-control question about the corpus's most safety-critical function, so it is the coordinator's
to route, not mine to assume.

**Q11 — Governance: this design requires a ratification row (§5-bis.4).** Not a question I can close.

---

## 11. WHAT THE IMPLEMENTING AGENT SHOULD BE TOLD

1. **Do not touch `kernel.reserve`.** It stays empty, sealed, droppable. `091`'s checked property
   survives this work intact.
2. **Do not touch `kernel.payout.amount_minor CHECK (> 0)`**, and do not add a negative payout cause.
3. **Do not touch `kernel.identity_obligation`**, its enum, or BP-10.
4. **Do not add a netting cause and do not touch `kernel.settlement_royalty_lines`.** The chargeback
   arm's semantics, including its deliberate absence of a scope predicate, are preserved exactly
   (§5-bis.2). Q1 is a question about that existing arm and is **independent** of this object — the
   table in §5.1 is answer-independent and can ship before Q1 is signed.
5. **Do not write any migration until the ratification row exists** (§5-bis.4). This object is the
   org-side negative-settlement carry that `schema:1186` assigns to C31/Gate-M; it ships the way
   `identity_obligation` (`OR-21`) and `dispute_native` (`R-40`) shipped — under its own numbered
   owner ruling — or it does not ship.
6. G5 remains the deployment gate for `payout-execute` regardless of what ships here; building §5.1
   is what makes G5 option 2 *selectable*, not what closes G5.
