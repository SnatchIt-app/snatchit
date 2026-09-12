# AGENT B — What the frozen corpus normatively says about merchant of record, settlement, and the money model

**Scope:** textual authority only. Repo `/Users/josetascon/snatchit-consol`, branch
`feature/venue-native-and-product-v2`. Read-only except this file. No migration authored, nothing
committed, nothing touched in production.

**Method:** every sentence below was read in place. Line numbers are 1-based against the file as it
stands on this branch. Where a claim rests on the *absence* of text, the search that established the
absence is named, because silence is a finding and an unnamed silence is an assertion.

---

## 0. HEADLINE FINDINGS

1. **Both challenged quotes are verbatim accurate.** Neither is a paraphrase. `DOMAIN:142` and
   `DOMAIN:851` say exactly what the prior review said they say.
2. **`DOMAIN:851` is materially out of context.** It is one bullet in a list titled *"Hard cases,
   resolved explicitly"* whose subject is **which principal owns the order object as data**, not
   funds flow. Its causal clause ("because the venue is the merchant of record") is stated **once**,
   corpus-wide, and is **contradicted on its own face** by the ratified money matrix two thousand
   lines later, in the same file, which the corpus designates the normative owner of money authority.
3. **"merchant of record" occurs exactly TWICE in the entire `docs/architecture/` tree** — the two
   sentences under review. **"business of record" occurs ZERO times.** Both occurrences sit in
   *rationale* prose columns, not in any matrix, contract, predicate, invariant or ratification row.
4. **No subject in the corpus's own precedence machinery covers merchant-of-record.** The
   `PHASE_2_SUBJECT_MATTER_OWNER_MAP.md` registers **41 subjects**. None is merchant/business of
   record, settlement counterparty, funds custody or charge model.
5. **The corpus is SILENT on the Stripe charge model for primary sales.** Zero hits corpus-wide for
   `destination charge`, `transfer_data`, `direct charge`, `application_fee`, `on_behalf_of` (in the
   Stripe sense), `stripe_account`. One hit for `separate charge` — in the **lowest-tier Phase-0
   baseline document**, describing what production already does.
6. **The 085 refund implementation does NOT contradict the money spec.** It matches it verbatim. The
   alleged contradiction is between (implementation + money spec + `DOMAIN` §7.6) on one side and
   the single loose word "venue" in `DOMAIN:851` on the other.

---

## 1. THE TWO QUOTES, VERIFIED

### 1.1 `SNATCH_IT_DOMAIN_ARCHITECTURE.md:142` — ACCURATE

The prior review reported: *"A person is never a primary-sale merchant of record; an org is."*

**Verified verbatim.** The full cell, and the two sentences that carry it:

> The org, not the user, is the financial and contractual counterparty for primary sales. A person is
> never a primary-sale merchant of record; an org is.

**Context, stated because it changes the load the sentence bears.** Line 142 is a single table row in
**§1.1 Identity & actor objects (`core`)**, and the sentence sits in the **last column of that table,
whose header is *"Why it is a distinct object"***. It is the justification for modelling
`organization` as an object at all rather than as a `user_type` flag on `user`. The sibling row
(`user / profile`, line 141) carries the mirror rationale: *"Capabilities must come from
relationships, never a `user_type` flag."*

The same row's second column reads:

> The legal business that signs up to sell primary tickets — a venue LLC, a promoter collective, a
> venue group. The **payee** for primary sales.

**What the sentence actually binds: PERSON vs ORG.** It is a rule about which *kind of principal* can
be the counterparty. It is **not** a rule about **venue vs platform**, and it does not name the
venue: the objects it distinguishes are `user` and `organization`. Note also that the normative word
this row uses for the org's money role is **"payee"** — repeated at `DOMAIN:1427`
(*"holds the Stripe Connect account, and is the payee for primary sales"*) and `DOMAIN:2219`
(*"The legal payee … Money is paid to an org, never to a 'venue'"*). "Merchant of record" appears in
this cell and nowhere else in the money-model prose.

**Reading anything venue-vs-platform out of line 142 is an inference, not a quotation.**

### 1.2 `SNATCH_IT_DOMAIN_ARCHITECTURE.md:851` — ACCURATE AS TEXT, OUT OF CONTEXT AS AUTHORITY

The prior review reported: *"the venue holds refund authority because the venue is the merchant of
record for primary sales."*

**Verified verbatim.** The full bullet:

> - **An order.** The buyer owns it as data (it is about their purchase), but the venue holds refund
>   authority because the venue is the merchant of record for primary sales. The order itself never
>   changes hands; only the *tickets it issued* move, through the engine. This prevents "refund the
>   order but the ticket already sold on the marketplace" incoherence — the refund engine must check
>   ticket `resale_state` before voiding.

**Context.** Line 851 is the second bullet of **"### Hard cases, resolved explicitly"** (heading at
line 848), which immediately follows the **per-object ownership matrix** (header at line 835:
`Object | OWNS | MODIFY | ARCHIVE | TRANSFER ownership | VIEW | Permanent? | How ownership changes`).
Every bullet in that list answers the same question — *for this object, who owns the DATA, and who
holds the adjacent authorities that must not be collapsed into "owner"*. The parallel bullets are "A
ticket" (850), "An event" (852), "A listing" (853), "An organization" (854), "A promoter_link" (855).

**Three defects in treating this sentence as the corpus's merchant-of-record rule:**

1. **The subject is data ownership, not funds flow.** The bullet's contribution to the design is its
   *second* half — that an order never changes hands and that the refund engine must check
   `resale_state`. The merchant-of-record clause is a one-line motivation for a custody rule.

2. **It says "venue" where every normative money text says "org".** The corpus is explicit and
   repeated that money is an **org**-grain fact and that "venue" is the wrong noun for it —
   `DOMAIN:2219`: *"Money is paid to an org, never to a 'venue' — because the room and the business
   that runs it are different things"*; `CDM:104` / O-3: *"a payout is **org-grain — it has no
   venue**"*. `DOMAIN:851` uses the operator-shorthand "venue". Under the money model, that word is
   simply wrong; under a merchant-of-record reading, it is load-bearing. That is the whole dispute.

3. **Its refund claim is contradicted by the ratified money matrix in the same file.** See §4.

---

## 2. THE AUTHORITY ORDER

### 2.1 There are TWO live freeze records, not one

| File | Date / baseline | What it carries |
|---|---|---|
| `/ARCHITECTURE_FREEZE.md` (repo root) | 2026-08-24, baseline `dd960c4` | **Rules 1–6**, the tiered **authority order (Rule 3)**, and the **covered-document list** |
| `docs/architecture/_governance/PHASE_2_ARCHITECTURE_FREEZE.md` | 2026-08-30, baseline `06fd5ec`, tag `phase2-architecture-v2` | The v2 freeze signature, §2 meaning, §3 verified state, **§4 the POST-FREEZE AMENDMENT procedure** |

**Confirmed by catalog, not by reading a name:** `git ls-tree -r 06fd5ec` shows
`ARCHITECTURE_FREEZE.md` at the repo root inside the frozen tree, and shows **no**
`docs/architecture/_governance/PHASE_2_ARCHITECTURE_FREEZE.md` — the v2 record was committed after
the baseline and says so itself (v2 §, lines 8–10: *"This record refers TO the frozen SHA. It is
committed AFTER it, and is not itself part of the frozen architecture baseline."*). Every citation in
the corpus to *"`ARCHITECTURE_FREEZE.md` Rule 1 / Rule 3 / the covered set"* (money spec §13.3, `C75`,
`C126`) resolves to the **root** file, not the v2 record. Any review that reads only the v2 file will
not find Rule 3 and may wrongly conclude the tier order was dropped.

### 2.2 The tier order (root `ARCHITECTURE_FREEZE.md:118`, Rule 3) — verbatim

> Authority order: live production reality (deployed-state questions) → this freeze + constitutions →
> implementation specs → `docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md` → current
> implementation → old audits/stale branches.

And, immediately following (lines 120–122), the limit of that rule, verbatim:

> **This order ranks TIERS, and every delta specification sits in ONE of them.** … so **when two
> documents inside that tier contradict each other, this rule decides nothing**

The **constitutions** are named at root `ARCHITECTURE_FREEZE.md:21–22`:
`SNATCH_IT_DOMAIN_ARCHITECTURE.md` · `SNATCH_IT_CANONICAL_DATA_MODEL.md` ·
`_governance/PHASE_2_RATIFICATION_RECORD.md`, with the qualifier *"consolidated — the body is
authoritative; no precedence algorithm needed"*.

A second, narrower order exists in `PHASE_2_SPEC_FOUNDATION.md:8`:

> Source authority order: `…SNATCH_IT_CANONICAL_DATA_MODEL.md` (§11 naming constitution binds) >
> `…SNATCH_IT_DOMAIN_ARCHITECTURE.md` > `…_superseded/PHASE_2_FINAL_ARCHITECTURE_AUDIT.md` /
> `…ARCHITECTURAL_RISK_REGISTER.md` / `…CTO_DECISION_MEMO.md` (Gate decisions) > roadmap. Phase-0 docs
> (`docs/architecture/PHASE_1_FOUNDATION.md`, `…SNATCH_IT_ENGINEERING_STANDARDS.md`,
> `docs/security/SNATCH_IT_PHASE_0_COMPLETION_REPORT.md`) now live in this repository at those paths.

**This places `PHASE_1_FOUNDATION.md` at the bottom** — the only file in the tree that names a Stripe
charge model (§6).

### 2.3 Intra-tier conflicts are resolved by SUBJECT-MATTER OWNERSHIP, not by recency

`O11` was ruled as `OR-6` (`RATIFICATION_RECORD:307`, and the map's own preamble). The map's rules,
verbatim from `PHASE_2_SUBJECT_MATTER_OWNER_MAP.md:11–19`:

> - **`CORRECTION_FALLBACK = NO`** — the owner covers the subject. A ratified correction row may
>   **not** override it, however new or however tagged. `OR-6` rule 2.
> - **`AMBIGUOUS`** — no designated owner. Conflicts on this subject **FAIL CLOSED** under rule 4.
>   The implementer does not choose.
> - **Recency is never a resolver.** Not for anything, on any subject. `OR-6` rule 3.

And line 21:

> **Ownership is taken from the corpus's own declarations, never inferred**

### 2.4 What counts as a POST-FREEZE AMENDMENT vs an implementation choice

From `_governance/PHASE_2_ARCHITECTURE_FREEZE.md` §2 (lines 33–44), verbatim:

> 4. **Normative architecture changes after this freeze require a formal POST-FREEZE AMENDMENT** (§4
>    below) carrying an owner signature. No pass, agent, or implementer may make, reopen, or soften a
>    normative decision without one.
> 5. **Implementation fixes that do NOT change normative behavior do not reopen the architecture.**
>    Typos in non-normative prose, build tooling, test scaffolding, CI wiring …, and **engineering
>    choices the corpus already uniquely determines** are implementation work.
> 6. **Implementation discoveries that contradict the corpus MUST STOP and file a POST-FREEZE
>    AMENDMENT.** Building around the contradiction, or building the contradiction, are both defects.
> 7. **Implementers may not silently reinterpret ambiguity.** If the corpus admits two readings of a
>    normative question, that is a discovered defect: stop, file the amendment, cite both readings.

§4 (lines 73–96) fixes the required PFA fields (`ID` · `FROZEN RULE` — *"the exact frozen text, file +
§, at 06fd5ec"* · `IMPLEMENTATION CONFLICT` · `WHY IMPLEMENTATION CANNOT CONFORM` · `OPTIONS` ·
`RECOMMENDATION` · `PACKAGE IMPACT` · `DAG IMPACT` · `SECURITY/MONEY IMPACT` ·
`OWNER SIGNATURE REQUIRED`), and closes:

> the freeze baseline SHA never moves; the amendment trail is the delta. **No architecture file may be
> silently edited around a conflict.**

**Operative test for the downstream ruling.** A choice is a **post-freeze amendment** only if it
changes a rule the frozen text actually states. A choice the frozen text does not state, and which
the frozen text does not uniquely determine, is neither an amendment nor free-form: by §2 clause 7 it
is a **discovered ambiguity that must be surfaced**, and by owner-map rule 4 an *unowned* subject
**fails closed**. A choice the corpus **uniquely determines** is implementation work (clause 5).

---

## 3. QUOTATION TABLE — every load-bearing statement found

Searched across the whole of `docs/architecture/` (24 spec files + 47 `_governance` files) for:
`merchant of record`, `business of record`, `merchant`, `settle`, `distributable`, `proceeds`,
`on behalf`, `platform balance`, `custodian`, `funds`, plus the Stripe terms of §6.

| # | QUOTE (verbatim) | FILE:LINE | CLASS | WHAT IT BINDS |
|---|---|---|---|---|
| 1 | "The org, not the user, is the financial and contractual counterparty for primary sales. A person is never a primary-sale merchant of record; an org is." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:142` | **NORMATIVE (narrow)** — but it is the *rationale* column of an object-catalog row | That the primary-sale counterparty is an **organization, not a natural person**. Binds person-vs-org. Says nothing about venue-vs-platform, and names no funds-flow mechanism. |
| 2 | "The **payee** for primary sales." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:142` (same row, attribute column) | **NORMATIVE** | The org is the **payee**. "Payee" is a settlement-destination claim, strictly weaker than merchant-of-record. |
| 3 | "the venue holds refund authority because the venue is the merchant of record for primary sales" | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:851` | **DESCRIPTIVE / superseded aside** | Nothing that survives. Its refund half is overridden by the O-1 money matrix (§4); its merchant-of-record half is unique in the corpus and is a motivation clause, not a rule. |
| 4 | "A business entity (venue group, promoter collective, single-venue LLC) that signs up for the platform, holds the Stripe Connect account, and is the payee for primary sales." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1427` | **NORMATIVE** | Org holds the Connect account and is the payee. Still no charge-model claim. |
| 5 | "The legal payee. A club's LLC, a promoter collective, or a venue group. It holds the Stripe Connect account, the settlement schedule, and tax registration. **Money is paid to an org, never to a \"venue\"** — because the room and the business that runs it are different things, and the same LLC often runs three rooms." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:2219` | **NORMATIVE** | Money grain is **org**, explicitly not venue. This is the sentence that makes `DOMAIN:851`'s word "venue" a defect. |
| 6 | "This one split is what lets a promoter collective run a night at a room they don't own, settle to *their* Connect account, while the venue's capacity and door rules still govern." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:2225-2226` | **NORMATIVE (consequence)** | The **booking org**, not the room's operator, receives settlement. Directly refutes "the venue is the merchant of record": for a rented room the venue is not even the payee. |
| 7 | "**R7 — money single-path** \| `core.payouts`/`refunds`/`payments` are written only by `core` money functions. `venue.settlements` and `market.market_sales` *request*; they never write money rows." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1102` | **NORMATIVE (invariant)** | Single writer path for money rows. A ledger-integrity rule; carries no merchant-of-record content. |
| 8 | "**Payments never determine ownership** (native rail). … Settlement never modifies ticket history." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:35` (Invariant 3) | **NORMATIVE (invariant)** | Firewall between money and custody. Neutral on who the merchant is. |
| 9 | "The frozen Stripe charge record (integer-cents, deterministic idempotency, signed+replay-protected webhooks). … The money-in event. Frozen core; links to whatever business object caused it (order or market_sale), never to a ticket directly." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:200` | **DESCRIPTIVE** | Describes the existing `payments` object. Names **no** Stripe charge topology. |
| 10 | "**Sole money-in event.** `kernel.payment_native.payment_id` FKs here; native orders/sales **link**, never re-charge. Integer-cents math preserved." | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3677` | **NORMATIVE** | Money-in is recorded once, in `public.payments`, and Phase 2 links to it. A *recording* rule, not a *custody-of-funds* rule. |
| 11 | "money-in recorded **only** as a `public.payments` row via this frozen path — never re-implemented" | `PHASE_2_EDGE_FUNCTION_SPEC.md:1249` | **NORMATIVE** | Same. Path, not topology. |
| 12 | "the org payout ledger is **readable** by `org_owner` and `org_finance` for their own org … a payout is **org-grain — it has no venue**" | `SNATCH_IT_CANONICAL_DATA_MODEL.md:104` (O-3) | **NORMATIVE (owner ruling)** | Payout grain is the org. Reinforces #5. |
| 13 | "an org has ≥1 owner at all times; payout destination changes are audited and cool-down-gated (dual-control seam)." | `SNATCH_IT_CANONICAL_DATA_MODEL.md:68` | **NORMATIVE** | Control on where org money goes. |
| 14 | "the platform *is* the custodian, holding and owning cannot diverge" | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:536` | **DESCRIPTIVE — and about TICKETS, not money** | Custody of the **credential**. The only corpus use of "custodian" is ticket custody. Do not read it as fund custody. |
| 15 | "there is no gap between holding and owning because the platform is the sole custodian of native tickets" | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:578` | **DESCRIPTIVE — tickets** | As above. |
| 16 | "`create_order` (door/staff on behalf)" | `PHASE_2_RLS_PERMISSION_SPEC.md:1326` | **DESCRIPTIVE** | The only "on behalf" in a money-adjacent table, and it is about a **door principal creating an order for a walk-up**, not about a Stripe `on_behalf_of`. |
| 17 | "The chargeback or late refund produces a **negative `venue.settlement_line`** in the org's **next open settlement** … **The org absorbs it; the promoter's already-paid commission is not pursued.**" | `PHASE_2_PROMOTER_CODES_SPEC.md:700` | **NORMATIVE** | The **org** bears chargeback loss. Consistent with org-as-counterparty; still says nothing about who Stripe treats as merchant. |
| 18 | "commission funded from primary ticket revenue before venue distributable settlement money leaves the system" | `_governance/POST_FREEZE_AMENDMENTS.md:2482` | **NORMATIVE (owner ruling, policy closed / implementation open)** | Ordering of the commission deduction. See §5. |
| 19 | "**`org_admin` and every venue role are forbidden callers.**" | `PHASE_2_MONEY_AUTHORITY_SPEC.md:673` | **NORMATIVE** | Who may call the refund door. Directly contradicts the "venue holds refund authority" reading of #3. |
| 20 | "**A refund cell is authority to *request*, not to execute.**" | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1916` | **NORMATIVE** | Even the org roles that hold refund cells hold a **request**, resolved server-side into a tier. |
| 21 | "Where the two disagree on a **money** cell, this matrix wins." | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1958` | **NORMATIVE (precedence)** | §7.6 is the governing text for money authority — not §2's ownership prose, and not §851. |
| 22 | "**Payments:** Stripe + Stripe Connect Express, separate charges & transfers, `source_transaction`-funded payouts." | `PHASE_1_FOUNDATION.md:47` | **DESCRIPTIVE (verified production state, lowest tier)** | The **only** charge-model sentence in the tree. It reports what the live Phase-0 marketplace does; it prescribes nothing for primary sales. |
| 23 | "create a PaymentIntent for `total_minor`, `currency='usd'`, `automatic_payment_methods`, metadata `{ rail:'native_primary', order_id, buyer_id, org_id, session_id }`. Records the `public.payments` row (frozen table) with the new `order_id` linkage column" | `PHASE_2_EDGE_FUNCTION_SPEC.md:372-374` | **NORMATIVE as to the RECORD, SILENT as to the TOPOLOGY** | The frozen primary-sale checkout contract. It names **no** `transfer_data`, `on_behalf_of`, `application_fee_amount`, or `stripeAccount` header. See §6. |
| 24 | "TOTAL SUBJECTS : 41 / AMBIGUOUS : 2 (PAY-STATE · EDGE-PKG)" | `PHASE_2_SUBJECT_MATTER_OWNER_MAP.md:26-27` | **NORMATIVE (registry)** | The closed subject list. **Merchant-of-record is not among the 41.** |
| 25 | "MONEY-AUTH\|The money-authority model: request-vs-execute, tiers, ceilings, dual control, SoD, step-up\|docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md" | `PHASE_2_SUBJECT_MATTER_OWNER_MAP.md:191` | **NORMATIVE (registry)** | The money spec owns **authority**, and the subject is defined by enumeration — it does not extend to funds custody or charge topology. |
| 26 | "MONEY-MATRIX\|Role-by-action money authority cells\|docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md\|§7.6 permission matrix and its D6 precedence note" | `PHASE_2_SUBJECT_MATTER_OWNER_MAP.md:190` | **NORMATIVE (registry)** | §7.6 owns the cells. `DOMAIN` §2/§851 is not the owner of any money subject. |

**Absence findings, each with the search that established it:**

- `grep -rn -i "merchant" docs/architecture/` → **2 hits**, both above (#1, #3).
- `grep -rn -i "business of record" docs/architecture/` → **0 hits**.
- `grep -rn -i "platform balance" docs/architecture/` → **0 hits**.
- `grep -rn -i "custodian" docs/architecture/` → **2 hits**, both about **ticket** custody (#14, #15).
- `grep -rn -i "distributable" docs/architecture/` → **2 hits**, both in the Option-B ruling
  (`POST_FREEZE_AMENDMENTS.md:2469`, `:2482`) — the word enters the corpus only on 2026-09-02.

---

## 4. WHAT THE MONEY SPEC MANDATES — and what it does not

`PHASE_2_MONEY_AUTHORITY_SPEC.md` (1907 lines) was read in full at the section level and in full text
for §§1–3, §6.1, §6.1a, and the §13 correction indices.

### 4.1 Its self-declared scope

Header, line 1: **"Money Authority Specification (Refund + Payout)"**. Line 37:

> **Purpose.** Resolve the ratified owner rulings **O-1 (refund authority)** and **O-3 (payout
> visibility / requests)** against the frozen constitutions, and produce the exact corrected text that
> a later integration pass drops into `PHASE_2_RLS_PERMISSION_SPEC.md` §7.9/§7.10/§11 and
> `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §7.6.

Line 3: **"Design-only — no SQL, no migrations, no implementation code."**

**It is a document about WHO MAY ACT, not about WHERE MONEY SITS.** Its own invariant attestation
(lines 61–62) confirms it deliberately adds no funds-flow surface:

> | **OBS-1 — no column ever added to `public.payments`** | **HONORED.** Zero changes to `public.*`. |
> | **Frozen Stripe core** | **UNTOUCHED.** No new Stripe API surface; `refund-execute` /
> `payout-execute` gain actions, not integrations.

**Finding: the money spec mandates nothing about where funds land or who may hold money.** It
mandates who may *request*, who may *approve*, at what tier, with what separation of duties. On the
question the downstream ruling turns on, the designated owner of `MONEY-AUTH` is **silent**.

### 4.2 What it does bind — verbatim

- **Obligation recognition (refund).** §6.1 line 700: *"**Tier decision (server-side, from config —
  §7.2). Every row's operand is `cumulative`, defined in §6.1a — never `p_amount_minor` alone.**"*
  and §6.1 Writes (line 732): *"that function alone writes `kernel.refund`, drives
  `kernel.void_ticket_atom` per voidable atom … **This function writes no money row.**"*
- **Who may hold the money-out authority.** §3.1's matrix (lines 290–305). Reproduced in the
  constitution as `DOMAIN` §7.6 by ratified row `D6`.
- **The settlement writer.** Attestation line 60: *"`kernel.payout` is still written only by
  `kernel.close_settlement` / native-sale path / `kernel.pay_promoter_commission` /
  `request_org_payout`+`hold`/`release` state advances."*
- **What is deliberately not built.** §9.4 heading: *"What is deliberately NOT built"*; attestation
  line 67: *"**Gate M (C29 reserve / C31 double-entry) not required** … Nothing here needs a reserve,
  a clawback, or instant payout. MVP payout stays settlement-cadenced."*

That last line matters: **the corpus explicitly declines to build a platform-held reserve or a
double-entry ledger for MVP.** Anyone arguing the frozen design *requires* the platform to hold funds
must reckon with the fact that the frozen design says it builds no reserve.

---

## 5. REFUND AUTHORITY — spec vs implementation

### 5.1 Is the causal link "venue holds refund authority BECAUSE it is merchant of record" stated?

**Once, at `DOMAIN:851`, and nowhere else.** No other file states it; no ratification row derives
anything from it; no RPC contract, RLS matrix or capability row cites it. `O-1` — the ratified owner
ruling that actually decides refund authority — does not mention merchant of record.

### 5.2 The ratified refund authority (which contradicts the "venue" half of `DOMAIN:851`)

`DOMAIN` §7.6, lines 1889–1892. Column order: `Plat Admin | Support | Risk Ops | Org Owner | Org
Admin | Org Finance | Venue Mgr | Box Office | Marketing | Door | Promoter Mgr | Promoter | Seller |
Buyer | Ambassador`.

```
1889 | Issue refund (≤ auto-execute threshold)      | ✔ | ✔(capped) | ✔  | ✔✱  |  | ✔✱  | | | | | | | | ◐(own, capped) | |
1890 | Issue refund (> auto-execute threshold)      | ✔ᴰ✱ | ✔ᴾ    | ✔ᴾ | ✔ᴰ✱ |  | ✔ᴰ✱ | | | | | | | | | |
1891 | Issue refund (> org ceiling / exceptional)   | ✔ᴰ✱ | ✔ᴾ    | ✔ᴰ✱| ✔ᴾ  |  | ✔ᴾ  | | | | | | | | | |
1892 | Approve someone else's refund request        | ✔ | ✔(tiered) | ✔  | ✔ᔆ  |  | ✔ᔆ  | | | | | | | | | |
```

**Every venue-plane column (Venue Mgr, Box Office, Marketing, Door, Promoter Mgr) is BLANK on every
refund row.** `Org Admin` is blank. And `DOMAIN:1916`, verbatim:

> 1. **A refund cell is authority to *request*, not to execute.** `Issue refund` ✔ for
>    `org_owner`/`org_finance` means the org may open **one** door — a refund *request* — and the
>    server decides its tier from configured thresholds … The caller never chooses the tier, and **no
>    org role ever invokes the money writer directly.**

**So: the venue does not hold refund authority. The venue-plane roles hold none at all, and the org
roles that hold a cell hold a request, not an execution.** `DOMAIN:851` is pre-`O-1` prose that the
ratified matrix in the same file overtook. Per `DOMAIN:1958` (*"Where the two disagree on a money
cell, this matrix wins"*) and owner-map row `MONEY-MATRIX`, §7.6 governs and §851 does not.

### 5.3 The implementation — `085_kernel_money_native.sql`

The prior review cited `085:908-911`. **Off by one on the comment line; substantively correct.**
Verbatim, `supabase/migrations/085_kernel_money_native.sql:907-914`:

```sql
907    -- caller class (org_admin + every venue role FORBIDDEN — MONEY §6.1)
908    v_is_buyer   := (v_order.buyer_id = v_uid);
909    v_is_orgrole := kernel.has_org_role(v_order.org_id, array['org_owner','org_finance']);
910    v_is_admin_risk := kernel.is_platform(array['platform_risk','platform_admin']);
911    v_is_plat    := v_is_admin_risk or kernel.is_platform(array['platform_support']);
912    if not (v_is_buyer or v_is_orgrole or v_is_plat) then
913      raise exception 'insufficient_privilege: buyer, org money role, or platform required' using errcode = '42501';
914    end if;
```

The predicate is a positive allowlist — buyer of the order, `org_owner`/`org_finance` on the order's
org, or a platform role. `org_admin` and every `venue_*` label are excluded because they appear in no
arm, exactly as the comment says.

The other refund verbs in the same file:

| Verb | Line | Authority predicate |
|---|---|---|
| `kernel.refund_primary_order` (direct arm) | 514–517 | `is_platform(['platform_admin'])` or `is_platform(['platform_support'])` (capped); otherwise *"platform (direct) or dual-control-delegated only"* |
| `kernel.approve_refund_request` — org arm | 1174–1175 | `has_org_role(ar.org_id, ['org_owner','org_finance'])` |
| `kernel.approve_refund_request` — platform arm | 1181–1204 | `platform_risk`/`platform_admin`, or `platform_support` under a cumulative cap |
| `kernel.cancel_refund_request` | 1368–1370 | requester, org money role, or platform |
| `kernel.admin_refund` | 749–750 | `is_platform(['platform_admin','platform_risk'])` |
| `kernel.set_org_payout_destination` | 1618–1619 | `has_org_role(p_org_id, ['org_owner'])` — *"org_owner only (SoD-1)"* |

**No venue-plane label appears in any refund or payout predicate in 085.**

### 5.4 Verdict: spec and implementation AGREE

`PHASE_2_MONEY_AUTHORITY_SPEC.md:673`, verbatim:

> **`org_admin` and every venue role are forbidden callers.**

and again at line 750 under **Forbidden**:

> Any client writing `kernel.refund` directly; `org_admin`; venue roles; a buyer refunding another
> buyer's order; any caller supplying an `org_id` or an actor.

The migration comment is a near-quotation of the spec, and the predicate implements it.
**There is no spec/implementation contradiction.** The prior review's framing —
*"the deployed code contradicts the spec"* — is **incorrect**. What the code contradicts is the single
sentence at `DOMAIN:851`, which the ratified money matrix had already superseded before 085 was
written.

**Deployment status, stated precisely because the claim was "deployed":** `085` is a repository
migration on the Phase-2 branch. Per the production migration ledger it is **not applied to
production**; the applied chain ends at `075`. Calling 085 "the deployed code" overstates its status.

---

## 6. DOES THE CORPUS SPECIFY A STRIPE CHARGE MODEL? — NO

Searches across `docs/architecture/`:

| Term | Hits | Where |
|---|---|---|
| `destination charge` | **0** | — |
| `transfer_data` | **0** | — |
| `direct charge` | **0** | — |
| `application_fee` / `application_fee_amount` | **0** | — |
| `on_behalf_of` (Stripe sense) | **0** | (2 hits are `admin_audit` actor columns: `DOMAIN:1534`, `DOMAIN:2021`) |
| `stripe_account` / `Stripe-Account` header | **0** | — |
| `Custom account` | **0** | — |
| `separate charge` | **1** | `PHASE_1_FOUNDATION.md:47` |
| `connected account` | 6 | all six are about **`payout.paid`/`payout.failed` webhook join keys** (`po_…` aggregates many transfers), never about how the buyer's charge is created |

**The single charge-model sentence, verbatim (`PHASE_1_FOUNDATION.md:47`):**

> - **Payments:** Stripe + Stripe Connect Express, separate charges & transfers,
>   `source_transaction`-funded payouts.

Its status, from the same file's header (lines 3–9): *"Authoritative post–Phase 0 baseline … every
claim here was verified against **live production** … **Purpose:** the reference baseline Phase 2
(venue / primary ticketing) must build on."* It is a **verified description of the existing resale
marketplace**, filed by `PHASE_2_SPEC_FOUNDATION.md:8` among the **Phase-0 docs at the bottom of the
source-authority order**, and it speaks to the *external-rail resale* money machine, not to
venue-direct primary sales, which did not exist when it was written.

**The frozen primary-sale checkout contract is `PHASE_2_EDGE_FUNCTION_SPEC.md` §3.1 (lines
355–397).** Its Stripe bullet (371–374) creates a PaymentIntent with amount, currency,
`automatic_payment_methods` and metadata — **and no Connect parameter of any kind**. Read as a
specification it is a plain platform-account PaymentIntent; read as authority it **prescribes a
recording obligation** (`public.payments`, the frozen table, plus the `order_id` linkage) and is
**silent on charge topology**. The corpus's normative money-in rule is stated as a *path*
(`EDGE:1249` — *"money-in recorded **only** as a `public.payments` row via this frozen path — never
re-implemented"*), never as a Stripe object shape.

**Finding: the charge model for venue-direct primary sales is UNSPECIFIED in the frozen corpus.**
It is not owned by any of the 41 subjects. Under freeze §2 clause 5 it is an implementation choice
**only to the extent the corpus uniquely determines it**; where two topologies would both satisfy
every frozen sentence, clause 7 and owner-map rule 4 apply — surface it, do not pick silently.

---

## 7. THE PROMOTER RULING — `COMMISSION_FUNDING_SOURCE`, Option B

Location: `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md`. Two entries carry it.

**(a) The ruling as recorded on the erratum that raised it — `E-138`, line 2469, verbatim (ruling
clause only):**

> **OWNER RULING (2026-09-02) — POLICY CLOSED / OWNER-RATIFIED · IMPLEMENTATION OBLIGATION OPEN:**
> OPTION B — promoter commissions are funded FROM PRIMARY TICKET REVENUE THROUGH THE VENUE SETTLEMENT
> ACCOUNTING MODEL (primary ticket revenue → promoter commission liability → venue distributable
> settlement): a commission is an economic deduction from the venue's primary-sale proceeds before the
> corresponding distributable venue money leaves the settlement system. NOT chosen: (A) generic
> carry-forward of an unfunded negative settlement as the primary mechanism, (C) arbitrary collection
> from the org's Stripe balance as the normal mechanism, (D) platform-funded commissions / platform
> absorption. FUNDING IS NOT ACTIVATED by this ruling: until the primary-revenue settlement funding leg
> is mechanically implemented, tested and authorized, ALL promoter commission payouts REMAIN HELD
> (`unfunded_settlement`) — 090's behaviour stands; nothing is advanced or released on the strength of
> the policy.

**(b) The forward-obligation entry — `COMMISSION_FUNDING_SOURCE`, line 2482, verbatim:**

> - **`COMMISSION_FUNDING_SOURCE`** (E-138) — **OWNER POLICY: RESOLVED (2026-09-02, OPTION B) ·
>   IMPLEMENTATION: OPEN.** TARGET ECONOMICS: commission funded from primary ticket revenue before
>   venue distributable settlement money leaves the system (primary ticket revenue → promoter
>   commission liability → venue distributable settlement). Rejected as the normal mechanism:
>   carry-forward of an unfunded negative net (A), arbitrary org Stripe-balance debit (C), platform
>   advance/absorption (D). The implementation must eventually prove: the exact primary revenue source
>   · the exact settlement-line representation · the commission deducted ONCE · conservation · no
>   duplicate funding · refund behaviour · chargeback behaviour · cancellation behaviour · the
>   held-payout release condition · payout destination readiness · settlement-close concurrency · no
>   platform advance · no arbitrary Stripe-balance debit. Until that leg is implemented, tested and
>   authorized, every commission payout is minted and REMAINS HELD `unfunded_settlement` (no automatic
>   release; `kernel.release_payout` is a per-payout Control-5 action, not a funding rail). NOT
>   assigned to any package unless frozen package bytes assign it.

**Order-of-operations wording, isolated because the downstream ruling turns on it.** Three distinct
formulations, all ratified:

1. `primary ticket revenue → promoter commission liability → venue distributable settlement`
   (an ordered pipeline, stated twice — 2469 and 2482);
2. *"an economic deduction from the venue's primary-sale proceeds **before the corresponding
   distributable venue money leaves the settlement system**"* (2469);
3. *"funded from primary ticket revenue **before venue distributable settlement money leaves the
   system**"* (2482).

**What the ordering constrains, read literally.** The barrier is placed at the moment **distributable
venue money LEAVES the settlement system** — not at the moment the buyer is charged, and not at the
moment funds arrive anywhere. The commission must be recognised and deducted **upstream of that
exit**. The ruling also expressly rejects **(C) arbitrary org Stripe-balance debit** and **(D)
platform advance/absorption** *as the normal mechanism*, and names *"no platform advance · no
arbitrary Stripe-balance debit"* among the properties the implementation must prove.

**Status caveats, both explicit:** policy is CLOSED, **implementation is OPEN**; funding is **NOT
ACTIVATED**; all commission payouts **REMAIN HELD**; and the obligation is **not assigned to any
package**. The register's own maintenance line (2446) reads: *"(register maintained per
PHASE_2_ARCHITECTURE_FREEZE.md §4)"*.

**One structural note, reported not resolved.** The two Option-B entries are recorded under
`## ERRATA recorded by package 090` and `## Forward obligations opened / re-scoped by package 090` —
**not** as a numbered `PFA-n` section with the §4 field set (`FROZEN RULE` / `IMPLEMENTATION
CONFLICT` / `WHY IMPLEMENTATION CANNOT CONFORM` / `OPTIONS` / `PACKAGE IMPACT` / `DAG IMPACT` /
`SECURITY/MONEY IMPACT` / `OWNER SIGNATURE REQUIRED`), as `PFA-20`…`PFA-31` are. They carry an owner
ruling and a dated countersignature in their body text. Whether an owner ruling recorded in an ERRATA
section has the same standing as a numbered PFA is a **governance question the corpus does not
answer**, and it is flagged here rather than assumed either way.

---

## 8. VERDICT

### 8.1 Is "the venue is merchant of record for primary sales" a binding normative requirement?

**NO. It is a descriptive aside, and the venue-specific reading of it is an inference someone made.**

The reasoning, in the corpus's own terms:

1. **Textual weight.** "Merchant of record" appears **twice**, both in the *rationale* column of an
   object-catalog row (`:142`) and in a *hard-cases* explanatory bullet (`:851`). It appears in no
   matrix, no invariant (§0.2's four invariants do not mention it), no ratification row, no owner
   ruling, no RPC contract, no RLS predicate, no capability row. "Business of record" appears zero
   times.

2. **Ownership.** The corpus resolves disputed statements by **finding the subject in the owner map
   and reading the normative owner** (`OWNER_MAP:11`). The map registers **41 subjects**, and
   merchant-of-record is not one. The two money subjects are `MONEY-AUTH` (the money-*authority*
   model — request-vs-execute, tiers, ceilings, dual control, SoD, step-up) and `MONEY-MATRIX` (role×
   action cells). Neither covers who the merchant is. **Ownership may not be inferred**
   (`OWNER_MAP:21`), so the statement has no normative home.

3. **The one venue-specific occurrence is defective on its face.** `:851` says *venue*; `:2219` says
   *"Money is paid to an org, never to a 'venue'"*; `:2225-2226` says a promoter collective renting a
   room settles to *their own* Connect account while the venue governs capacity and door. Under the
   frozen model the venue may not be the payee at all.

4. **Its stated consequence is false in the ratified design.** `:851`'s only operative claim — that
   the venue holds refund authority — is denied by `DOMAIN` §7.6 (every venue column blank on every
   refund row), by `DOMAIN:1916` (org cells are *requests*), by `MONEY:673` (*"every venue role
   are forbidden callers"*) and by `085:907-914`. A premise offered to explain a conclusion the
   corpus rejects is not a rule the corpus holds.

**What IS binding, and it is narrower than the claim:**

- **`DOMAIN:142` — the primary-sale counterparty is an ORGANIZATION, never a natural person.** This
  is a real constraint and it is normative.
- **`DOMAIN:142` / `:1427` / `:2219` — the org is the PAYEE for primary sales, holds the Stripe
  Connect account, the settlement schedule and tax registration; money is paid to an org, never to a
  venue.**
- **`DOMAIN:2225-2226` — the payee is the BOOKING org (`event.organization_id`), which may differ
  from the room's operator.**
- **`PROMOTER:700` — the org absorbs chargebacks and late refunds via a negative settlement line.**
- **`POST_FREEZE:2469/2482` — commission is deducted from primary-sale proceeds before distributable
  venue money leaves the settlement system.**

That set is a **payee-and-liability** model. It is strictly weaker than a merchant-of-record mandate:
it says where money must end up and who bears loss, not whose name is on the transaction with the
card networks.

### 8.2 If it were binding, which charge models would satisfy it — purely as a matter of text?

Answered conditionally, and without recommending anything. Testing candidate topologies against only
the sentences quoted above:

- **Any model in which a natural person is the counterparty** — refuted by `:142` outright.
- **Any model in which funds settle to a *venue* rather than to the booking *org*** — refuted by
  `:2219` and `:2225-2226`.
- **Any model in which the platform advances or absorbs commission as the normal mechanism, or debits
  the org's Stripe balance arbitrarily** — refuted by `POST_FREEZE:2469` options (C) and (D).
- **Any model in which distributable venue money can exit settlement before the commission deduction
  is recognised** — refuted by the Option-B ordering.

Every remaining topology — a platform charge with a subsequent transfer to the org's connected
account (the Phase-0 shape `PHASE_1_FOUNDATION:47` describes), a charge that routes to the org's
connected account at capture, or a charge that names the org as the settlement counterparty at the
network layer — **satisfies every quoted sentence equally**, because no quoted sentence speaks to the
Stripe object shape. The frozen corpus's only Stripe-level requirements on the primary path are
recording obligations: one `public.payments` row via the frozen webhook path, `order_id` linkage, no
column added to `public.payments`, and integer-cents math preserved.

**Therefore: merchant-of-record, as a venue-vs-platform proposition, does not discriminate between
charge models in this corpus — because the corpus never states it as a rule and never states a charge
model at all.** The constraint that *does* discriminate is the payee/ordering set in §8.1, and it is
satisfiable by more than one topology.

### 8.3 Consequences for the downstream ruling

1. Citing `DOMAIN:851` as authority for "the venue must be merchant of record" **misreads a
   superseded aside as a rule**, and imports a word ("venue") that three other normative sentences
   correct to "org".
2. Choosing a Stripe charge model is **not** a post-freeze amendment under §2 clause 4, because it
   changes no rule the frozen text states. But it is also not free: clause 5 licenses only
   *"engineering choices the corpus already uniquely determines"*, and this one is **not uniquely
   determined**. By clause 7 and owner-map rule 4, the honest disposition is to **surface it as an
   unowned subject and put it to the owner**, not to derive it from `:851`.
3. If the owner wants merchant-of-record to be normative, that is a **new** decision requiring an
   owner signature — a `PFA-n` under §4, or a new owner-map subject with a designated normative owner
   — and not a re-reading of two rationale sentences.
4. `085`'s refund authority requires **no** change. It matches `MONEY §6.1` verbatim and matches
   `DOMAIN` §7.6. The stale text is `DOMAIN:851`, whose correction is a documentation act under the
   `C121`-class procedure (a ratified row, not a silent edit — root freeze Rule 1).

---

*Prepared by Agent B. Read-only review; no migration authored, nothing committed or pushed, no
production access. Every quotation was copied from the file, not reconstructed.*
