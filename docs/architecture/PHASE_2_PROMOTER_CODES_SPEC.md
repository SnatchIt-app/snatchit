# Snatch It — Phase 2 Promoter / Referral Codes Spec

**Design-only.** No SQL files, no migrations, no implementation code. Illustrative snippets inside this file
are illustrative, not deliverables. Nothing here edits a frozen constitution; every correction to a
non-frozen spec is raised in §14 rather than applied silently.

**Owner requirement this file answers:** *human-entered promoter/referral **codes**, alongside links.
"Do not depend on links as the only attribution mechanism."*

---

## 0. Preamble

### 0.1 Binding inputs (authoritative)

| Doc | Short form | What it binds here |
|---|---|---|
| `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` | **DA** | §1.7 promoter engine, §5.2.1 cause registry, §7.2 roles, §2 ownership matrix (`promoter_link` IMMUTABLE, `attribution` APPEND-ONLY) |
| `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` | **CDM** | §1.3 Promoter, §2 aggregate boundaries, §8 promoter isolation, §11 cause registry, §15 C26/C28/C29–C31/C36 |
| `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` | **schema §x** | §1.6 ownership log (C26), §1.8 `payment_native`, §1.9 `payout`, §3.7 `order`, §3.14 `settlement_line`, §3.17 promoter engine |
| `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` | **RLS §x** | §1.1 role vocabulary, §1.3 GP-1/GP-2, §7.9 note 15, §9.17 promoter matrices |
| `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` | **RPC §x** | §0.4 lock discipline, §6.1 `create_primary_checkout`, §6.3 `finalize_primary_order`, §10.2 `close_settlement`, §14 SSCAS |
| `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` | **edge §x** | §3.1 `primary-checkout`, §7 cross-cutting (rate limit, idempotency) |
| `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` | **dash §x** | §10.5–§10.8 — **binding downstream commitments this file must satisfy** |
| `docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md` | **mig §x** | package boundaries, rollout order |
| `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` | **RAT** | C26, C28, C29/C30/C31 (Gate-M), C36, D3 |

`docs/architecture/_superseded/` is **not** binding.

### 0.2 Evidence discipline

- **`VERIFIED:`** — the cited document/file on this branch states it. Line-level citations given.
- **`INFERENCE:`** — a conclusion this file draws that no binding input states.
- **`OWNER DECISION:`** — a product/commercial call this file must not make alone. Collected in §13.
- **`CONTRADICTION:`** — two binding inputs disagree. Reported in §14, never silently resolved.

### 0.3 Package numbering — a discrepancy stated before anything is built

`VERIFIED:` the repo copy of **mig** at this baseline (`11ea2eb`) numbers Phase-2 packages **073–088**, and is
**internally inconsistent about the promoter package**: the §1 phase→package map and the §3 rollout table say
`086`, while the §-detail heading says `087_venue_promoter_engine`, the §2 DAG node says `D087`, and the
rollback paragraph inside that same section says `086_*`. `VERIFIED:` **dash** §0.1 cites a third range,
`071–089`.

`VERIFIED:` the instructing authority for this task states the ratified numbering is now **`076`–`091`**, with
the promoter engine at **`090`** and `071`–`075` reserved for the already-applied production security
migrations. That maps the repo numbering forward by **+3** and resolves the 086/087 collision in favour of
`087 + 3 = 090`.

**This file uses `076`–`091` throughout.** The correspondence used, stated once so no reader has to guess:

| Repo (`11ea2eb`) | This file | Contents |
|---|---|---|
| 078 | **081** | `venue.order`, `venue.order_item` |
| 081 | **084** | `kernel.payment_native`, `refund`, `payout` |
| 083 | **086** | `venue.settlement`, `venue.settlement_line` |
| 086/087 | **090** | `venue.promoter`, `promoter_link`, `attribution` — **and everything in this file** |
| 088 | **091** | `kernel.reserve` stub (Gate-M boundary) |

→ §14.1 raises the repo inconsistency as a documentation defect to be fixed by the renumber owner, not by this
file.

### 0.4 Role vocabulary — concepts, not enum labels

`VERIFIED:` RLS §1.1/§2.1 fixes the venue-plane enum at exactly four labels
(`venue_manager · venue_finance · venue_door · venue_promoter`), disjoint from the org and platform planes
(C36). `VERIFIED:` the owner-ratified O-2 list is eight roles
(`org_owner · org_admin · org_finance · venue_manager · box_office · marketing · promoter_manager · scanner`),
and a separate agent is finalising plane membership per C36.

This file therefore names **role concepts**, and gives the current physical label in brackets so an
implementer is never blocked:

| Concept used here | Current physical label (RLS §2.1) | O-2 label |
|---|---|---|
| **promoter-program manager** — recruits promoters, issues codes, sets terms, adjudicates flags | `venue_manager` | `promoter_manager` |
| **venue finance** — reads commission money, closes settlement | `venue_finance` / `org_finance` | `org_finance` |
| **promoter** — an *attribution identity*, not staff | `venue_promoter` | *(none — see §14.2)* |
| **org administration** | `org_owner` / `org_admin` | `org_owner` / `org_admin` |

**O-2's structural rule, restated because it drives §8:** *promoters and ambassadors are NOT automatically
organization administrators.* A promoter is an attribution/distribution identity. §14.2 reports that the
current physical model contradicts this by expressing "promoter" as a **`venue.staff_role` grant**.

### 0.5 What "ambassador" means here

`VERIFIED:` DA §1.7 puts `tier ∈ {professional_invited, public_ambassador}` **on the promoter object** — an
ambassador is a *tier of promoter*, inside the commercial engine. `VERIFIED:` DA §11.1 defines a separate
**`referral / ambassador`** object as "the *social* growth loop, kept distinct from the *commercial* promoter
engine (§1.7)". `VERIFIED:` production carries an unrelated `public.ambassador_applications` table (dash §0.1).

**Decision for this file:** "ambassador" = `venue.promoter.tier = 'public_ambassador'`. Codes are issued to
**promoters**; an ambassador gets codes because an ambassador *is* a promoter at a different tier and
(typically) different commission terms. The social referral object is out of scope and must never share the
`promoter_commission` cause. → §14.3 reports that `tier` is missing from schema §3.17.

---

## 1. Data model delta (additive)

Every element below is classified and assigned a package. **All are `ADDITIVE SCHEMA CHANGE` unless labelled
otherwise, and all land in `090`** — the promoter engine package — for one reason stated once: `090` is
applied inert (mig §3 seq 15, "promoter phase"), has no writers until the promoter phase opens, and is the
only package whose rollback is clean while empty. Splitting the code objects across packages would make the
feature un-revertible as a unit.

### 1.1 New: `venue.promoter_code` — `ADDITIVE SCHEMA CHANGE` · package `090`

The human-typed sibling of `venue.promoter_link`. One promoter may hold **many** codes (owner requirement 1).

| Column | Type | Notes |
|---|---|---|
| `code_id` | uuid PK | |
| `promoter_id` | uuid NOT NULL | FK→`venue.promoter` **ON DELETE RESTRICT** |
| `org_id` | uuid NOT NULL | FK→`kernel.organization` — **denormalized** from the promoter for RLS and index locality (§10.4); a trigger asserts it equals `promoter.org_id` |
| `code_display` | text NOT NULL | what the operator typed and what renders: `"JORDY"` |
| `code_normalized` | text NOT NULL | `GENERATED ALWAYS AS (venue.normalize_promoter_code(code_display)) STORED` — **the uniqueness key** (§1.3) |
| `status` | enum(`active`·`inactive`) NOT NULL DEFAULT `active` | the third of dash §10.5's three independent switches |
| `valid_from` | timestamptz NULL | NULL = no lower bound |
| `valid_until` | timestamptz NULL | NULL = no upper bound |
| `kind` | enum(`vanity`·`generated`) NOT NULL | drives the entropy floor (§9.3) and the availability UX |
| `created_by` | uuid NOT NULL | FK→`auth.users` — the issuing staff principal, server-derived (C35) |
| `created_at` / `updated_at` | timestamptz NOT NULL | |

**Constraints**

- `UNIQUE (code_normalized)` — **global**, see §1.3 and §10.2 for the decision and its defence.
- `CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)`.
- `CHECK (length(code_normalized) BETWEEN 4 AND 16)`.
- `CHECK (code_normalized ~ '^[0-9A-HJKMNP-TV-Z]+$')` — the Crockford alphabet (§1.3); a value outside it is
  by construction unreachable through the normalizer, so this is a belt-and-braces assertion that the
  generated column and the alphabet never drift apart.

**Immutability — `promoter_id`, `code_display`, `code_normalized`, `kind`, `org_id` are IMMUTABLE once
created**, enforced by a guard trigger that raises on any UPDATE touching them. Only `status`, `valid_from`,
`valid_until` are mutable.

*Why:* this is what makes dash §10.5's **"No reassignment"** a database fact rather than a UI convention.
There is no path — RPC, admin override, or direct DML — that moves a code from one person to another. It also
mirrors `promoter_link`'s ratified IMMUTABLE class (DA §2, schema §3.17): a code, like a slug, is a permanent
attribution key, and a mutable one silently rewrites the meaning of every historical attribution that cites it.

**Deliberately absent: a redemption counter / `max_redemptions`.** A per-code cap is a hot mutable counter on
the checkout path, and the platform already has a first-class object for "this promoter has N tickets to
sell": `inventory_batch.release_kind = 'promoter_hold'` (schema §3.2, DA §1.5). Adding a second, weaker
capacity mechanism beside it would put two answers in the system for one question — the failure C27 exists to
prevent. → **OWNER DECISION 5** (§13).

### 1.2 New: `venue.promoter_code_scope` — `ADDITIVE SCHEMA CHANGE` · package `090`

Event scoping for a code. Absence of rows is meaningful (see the eligibility rule).

| Column | Type | Notes |
|---|---|---|
| `code_id` | uuid | FK→`venue.promoter_code` ON DELETE RESTRICT; part of PK |
| `event_id` | uuid | FK→`catalog.event` ON DELETE RESTRICT; part of PK |
| `added_by` / `added_at` | uuid / timestamptz | audit |

- **PK `(code_id, event_id)`** — idempotent scope-add by construction.
- Trigger: `event.org_id` must equal `promoter_code.org_id`. A code can never be scoped to another org's event.
- Rows may be **added and removed** (scope is Operational config, not a ledger). Removing a scope row changes
  *future* eligibility only; it never touches a recorded attribution (dash §10.5: "never deletes attribution
  already earned").

**The total eligibility rule** — evaluated server-side for a `(code, event_session)` pair. First match wins,
and the cases are exhaustive:

| # | Condition | Eligible? |
|---|---|---|
| E1 | `promoter.status <> 'active'` | **No** |
| E2 | `code.status <> 'active'` | **No** |
| E3 | `now()` outside `[valid_from, valid_until)` | **No** |
| E4 | `event.org_id <> code.org_id` | **No** |
| E5 | `promoter.event_id IS NOT NULL` and `<> event_id` | **No** — a single-event promoter's codes work on that event only |
| E6 | code has ≥1 scope row and none matches `event_id` | **No** |
| E7 | otherwise | **Yes** |

`INFERENCE:` E7 means *an unscoped code issued to an org-wide promoter is eligible across that org's whole
catalogue.* That is the right default: the common case is "Jordy sells for this club", not "Jordy sells for
this one Friday", and forcing a scope row per event would make a 200-event season a 200-row chore per code.
The narrow case is expressible two ways (a single-event promoter, or scope rows), and both are checked.

### 1.3 New: `venue.normalize_promoter_code(text) → text` — `ADDITIVE SCHEMA CHANGE` (IMMUTABLE function) · package `090`

The **case-fold decision the owner asked for: a normalized generated column, NOT `citext`.**

**Algorithm** (deterministic, `IMMUTABLE`, `STRICT`, `search_path` pinned):

1. Strip every character not in `[A-Za-z0-9]` — kills spaces, hyphens, zero-width joiners, emoji, and the
   invisible characters a copy-paste from Instagram carries.
2. `upper()` — safe now, because after step 1 the string is pure ASCII and `upper()` on ASCII is
   locale-independent.
3. **Confusable fold (Crockford Base32):** `O → 0`, `I → 1`, `L → 1`. Then reject `U` at issue time (it is
   excluded from the alphabet to avoid accidental obscenity in generated codes).

Result alphabet: `0-9` + `A-Z` minus `I L O U` = **32 symbols**.

**Consequence, and it is the point:** `JORDY`, `J0RDY`, `jordy`, `J-0-R-D-Y`, and `J0RDY ` all normalize to
`J0RDY`. `VERIFIED:` dash §10.5 states as binding — *"`J0RDY` is the same code as `JORDY`"*. Under this
design that is **true by the uniqueness key**, not merely warned about; the dashboard's confusable warning
(§11.2) then explains a fact rather than guessing at one.

**Why not `citext`:**

1. **`citext` solves the wrong half.** It case-folds. It cannot express `O ≡ 0`, which is the confusable
   class humans actually hit when reading a code off a phone screen in a dark room. The requirement is a
   *mapping*, and a collation is not a mapping.
2. **`citext` makes uniqueness semantics depend on `lc_collate`.** Its lower-casing is locale-driven; the
   Turkish dotless-i is the standard counterexample. A money key whose meaning depends on a cluster GUC is a
   key that can change under a restore into a differently-configured instance.
3. **The client cannot reproduce it.** The issuing UI must run a *live availability check* (dash §10.4/§10.5)
   and the checkout must show the buyer what their input resolved to. A pure-ASCII fold is trivially
   reimplemented in TypeScript, byte-identically. `citext` semantics are not.
4. **It is one fewer extension.** `VERIFIED:` no migration in `supabase/migrations/` enables `citext` today
   (grep, this branch). Every extension is attack surface and a restore-time dependency.
5. **`GENERATED ALWAYS ... STORED` makes it unbypassable.** Because the normalizer is `IMMUTABLE`, the
   normalized form can be a generated column — so no writer, not even `service_role`, can insert a normalized
   value inconsistent with its display value. With `citext` the display and match forms are the same column
   and the "what did the operator actually type" information is lost.

**Migration note:** changing the normalizer later is a **breaking change** — it would remap existing codes and
could collide. Treat `venue.normalize_promoter_code` as **frozen once `090` is applied with live codes**; a
future fold change requires a versioned second column and a reconciliation, not an edit. Stated here so nobody
discovers it during an incident.

### 1.4 Extended: `venue.promoter` — `ADDITIVE SCHEMA CHANGE` · package `090`

| Column | Why |
|---|---|
| `tier` enum(`professional_invited`·`public_ambassador`) NOT NULL DEFAULT `professional_invited` | `VERIFIED:` DA §1.7 specifies it; schema §3.17 omits it (→ §14.3). Ambassador programs and professional promoters carry different terms and different fraud posture (§9.5). |
| `commission_kind` enum(`bps`·`flat_per_ticket`) NOT NULL DEFAULT `bps` | `VERIFIED:` DA §1.7 — "flat-per-ticket or %"; schema §3.17 models only `commission_bps` (→ §14.3). Flat-per-head is the *dominant* nightlife term. |
| `commission_flat_minor` integer NULL | required iff `commission_kind='flat_per_ticket'`; CHECK enforces the XOR with `commission_bps`. |
| `party_kind` enum(`promoter`·`affiliate`) NOT NULL DEFAULT `promoter` | `VERIFIED:` DA §1.7 requires the discriminator so affiliates reuse one attribution ledger. Cheap now, structural later. |

### 1.5 Extended: `venue.attribution` — `ADDITIVE SCHEMA CHANGE` · package `090`

The ratified row (schema §3.17) is `(id, link_id, order_id, credited_amount_minor, currency, occurred_at,
created_at)` with `UNIQUE(order_id)` and AO. It cannot express a code-sourced attribution, cannot defend a
dispute, and cannot be read at scale under RLS. Additions:

| Column | Type | Why |
|---|---|---|
| `promoter_id` | uuid NOT NULL FK→`venue.promoter` | **The credit subject.** Today it is reachable only as `attribution → link → promoter`, which (a) breaks the moment the source is a code rather than a link and (b) is a 2-join RLS predicate on the hottest read. |
| `link_id` | uuid **NULL** (was NOT NULL) | now nullable — a code-sourced attribution has no link. `SPEC CORRECTION` to schema §3.17. |
| `code_id` | uuid NULL FK→`venue.promoter_code` | the winning code, when `method='code'`. |
| `method` | enum(`link`·`code`) NOT NULL | `VERIFIED:` dash §10.6 binding — *"`method` is always shown, never inferred from context."* |
| `touch_corroborated` | boolean NOT NULL | `VERIFIED:` dash §10.6 binding. Definition in §2.5. |
| `self_deal_flag` | boolean NOT NULL DEFAULT false | `VERIFIED:` dash §10.6/§10.7 binding; DA §1.7 requires self-deal detection. |
| `self_deal_reasons` | text[] NOT NULL DEFAULT '{}' | which detector fired (§9.5) — dash §10.6 requires the flag render "with its reason". |
| `displaced_promoter_id` | uuid NULL FK→`venue.promoter` | the promoter whose link *lost* to a code (§2.4). This is the hijack-detection column; without it a displaced promoter's complaint is unanswerable. |
| `terms_version` | integer NOT NULL | `VERIFIED:` dash §10.3 — *"a commission dispute is always about which terms were in force"*; dash §10.6 lists it as a column. |
| `commission_kind` / `commission_bps_applied` / `commission_flat_minor_applied` | snapshot | the terms **as applied**, frozen with the row (§6.2). |
| `basis_minor` | integer NOT NULL | the commissionable base the credit was computed from (§6.1). Storing only the result makes every dispute a re-derivation. |
| `org_id` / `event_id` | uuid NOT NULL | denormalized for RLS and index locality (§10.4). Triggers assert consistency with the order. |
| `resolution_reason` | enum (§2.3) NOT NULL | *why this winner won*. The precedence table is worthless in an argument if the row does not record which rule fired. |
| `order_paid_at` | timestamptz NOT NULL | the freeze timestamp (§3.3). |

`credited_amount_minor` keeps its ratified meaning: **the accrual at freeze**. It is *not* the payable — see
§6.3. Row class stays **AO**; `UNIQUE(order_id)` stays.

### 1.6 New: `venue.attribution_review` — `ADDITIVE SCHEMA CHANGE` · package `090`

This resolves **dash §22.4**, the collision the dashboard author correctly refused to resolve: Release/Deny is
a mutable adjudication and `venue.attribution` is append-only with `UNIQUE(order_id)`.

| Column | Type | Notes |
|---|---|---|
| `review_id` | uuid PK | |
| `attribution_id` | uuid NOT NULL FK→`venue.attribution` ON DELETE RESTRICT | |
| `seq` | integer NOT NULL | per-attribution monotonic, starts at 1 |
| `decision` | enum(`release`·`deny`) NOT NULL | |
| `reason_code` | enum(`legitimate_guest_purchase`·`self_purchase_confirmed`·`shared_instrument_explained`·`policy_violation`·`duplicate_account_suspected`·`other`) NOT NULL | dash §10.7 requires a reason code on both outcomes |
| `note` | text NULL | free text; never rendered to the promoter |
| `decided_by` | uuid NOT NULL FK→`auth.users` | server-derived (C35) |
| `decided_at` | timestamptz NOT NULL DEFAULT now() | |

- `UNIQUE (attribution_id, seq)`; **AO** (INSERT-only, guard trigger).
- **Effective decision = the row with `max(seq)`.** A wrong denial is corrected by appending `seq+1`, never by
  an edit — so the history dash §10.7 requires ("a denied flag is not removed, it is resolved") is the table
  itself.
- **Supersession is closed by settlement.** Once a `promoter_commission` settlement line exists for the
  attribution, `venue.review_attribution_flag` rejects with `attribution_settled` (§7.7). The money and the
  decision freeze together.

*Why a separate table rather than a mutable column:* the attribution is a **ledger** (DA §2, CDM §1.3) — it
records what happened. Whether the venue chose to *pay* on it is a different fact, made later, by a different
principal, and revisable until money moves. Two facts, two rows. Collapsing them would require making a ledger
mutable, which is the one thing the whole custody/attribution design refuses to do.

### 1.7 Extended: `venue.order` — `ADDITIVE SCHEMA CHANGE` · package `090`

The pending order needs somewhere to hold the *candidate* before the freeze (§3). Two nullable columns:

| Column | Type | Notes |
|---|---|---|
| `attribution_candidate_code_id` | uuid NULL FK→`venue.promoter_code` ON DELETE RESTRICT | the code bound to this checkout |
| `attribution_candidate_link_id` | uuid NULL FK→`venue.promoter_link` ON DELETE RESTRICT | the link touch the client presented |

- Both are **MUTABLE while `order.status='pending'`** and **frozen the instant it leaves `pending`** — a guard
  trigger raises on any UPDATE of either column when `OLD.status <> 'pending'`.
- `ADD COLUMN ... NULL` on `venue.order` is O(1) metadata-only in PG11+; still applied under a short
  `lock_timeout` per engineering standards, because `venue.order` will be hot by the time `090` lands.

*Why on the order and not in a new candidate table:* the candidate is 1:1 with the order, has the order's
exact lifetime, and dies with it. A separate table would add a join to the hottest write path and a second
row to keep in sync with a status guard.

### 1.8 Extended: `kernel.payment_native` — `ADDITIVE SCHEMA CHANGE` · package `090`

| Column | Type | Why |
|---|---|---|
| `instrument_fingerprint` | text NULL | Stripe `PaymentMethod.card.fingerprint` (or its non-card equivalent). **This is the only mechanism that implements DA §1.7's "same-payment-instrument" self-deal detector** (§9.5). |

`VERIFIED:` OBS-1 (RAT) forbids adding any column to `public.payments`. `kernel.payment_native` is a Phase-2
table and is the sanctioned home for native-side payment attributes — so this is the *correct* place, not a
workaround. Nullable because the fingerprint may be absent for some payment method types; the detector treats
NULL as "no signal", never as "no match".

**Privacy note:** a Stripe fingerprint is a stable pseudonymous instrument identifier. It is **never** exposed
to a promoter, a venue, or any client — it is read only inside the self-deal detector, which emits a boolean
and a reason string. It is in the C15/C34 PII-sink inventory. Stated so nobody surfaces it in a dashboard
column later.

### 1.9 New indexes and constraints — see §10 and §4

Collected there so the money invariant and the scale design each read as one argument.

### 1.10 What this file deliberately does NOT add

| Not added | Why |
|---|---|
| A **link/code touch table** (click log) | `VERIFIED:` dash §10.8 — *"click counts, link CTR, conversion rate, time-to-purchase… are Phase-3 analytics and none of them have a home in the frozen schema."* A touch table is the highest write-volume object the promoter engine could possibly have (every scroll-past of a shared link), and it buys nothing the money path needs. §2.6 explains how precedence works without it. |
| A **new SSCAS member** | §7.9 — attribution resolution adds no locked class, so C28's closed fifteen and its lock order stand unamended. |
| A **clawback / reserve object** | `VERIFIED:` C29/C30/C31 are `RATIFIED-MODELED-ONLY(GATE-M)` — *"NOT in the Phase-2 foundation"* (RAT). §5.5 gives the Phase-2-safe interim instead. |
| A **redemption counter** | §1.1. |
| A **promoter sub-link / sub-code tree** | DA §7.2 mentions promoter sub-links "where allowed"; nothing in the physical spec models a hierarchy, and a 2-level commission split is a money change, not a code change. → **OWNER DECISION 8**. |

---

## 2. The precedence decision table

### 2.1 Where precedence is evaluated — **the database, and only the database**

| Layer | Role in attribution | Authority |
|---|---|---|
| **Client (RN / web)** | Collects a typed code and at most one link slug. May call a preview RPC to show the buyer *"Credit Jordy?"*. | **None.** Its resolution is advisory and is discarded. |
| **Edge (`primary-checkout`, `promoter-code-preview`)** | Rate-limits, authenticates, forwards the raw strings. | **None.** It never resolves a promoter, never reads `venue.promoter_code` for a decision. |
| **DB RPC `venue.finalize_primary_order`** | Runs `venue.resolve_order_attribution` in the paid transaction. | **Total and sole.** |

*Why the DB and not the edge:* the same reasoning C35 applies to the buyer principal. The edge is a trusted
server component, but the resolution must be **in the same transaction as the money and the issuance**, or a
crash between "edge decided" and "DB wrote" produces an order with no attribution and no way to recover the
decision. Making it a DB function also means there is exactly one implementation — a second one written in
TypeScript is a second source of truth for money.

### 2.2 Normalization — every input collapses to one of three states per channel

Before the table is consulted, each channel is reduced by the §1.2 eligibility rule to:

- **`E` (eligible)** — resolves to exactly one `active` promoter, in scope, in window.
- **`X` (ineligible)** — a value was presented but fails E1–E6, or does not resolve at all.
- **`∅` (absent)** — nothing presented.

`X` and "unknown code" are **deliberately the same state**, for the reason in §9.4: distinguishing them in any
response turns the endpoint into a code-existence oracle.

### 2.3 The table

**Evaluated once, in `venue.resolve_order_attribution`, inside the paid transaction. First matching row wins.
The rows are exhaustive over `{code} × {link}` plus the multiplicity and freeze cases.**

| # | Precondition | Code | Link | Outcome | `method` | `touch_corroborated` | `resolution_reason` |
|---|---|---|---|---|---|---|---|
| **P0** | an attribution row already exists for `order_id` | any | any | **return it unchanged** | — | — | *(frozen; §3)* |
| **P1** | — | `E` | `E`, same promoter | attribute to that promoter | `code` | **true** | `code_corroborated_by_link` |
| **P2** | — | `E` | `E`, different promoter | attribute to the **code's** promoter; record the link's promoter in `displaced_promoter_id` | `code` | **false** | `code_over_link` |
| **P3** | — | `E` | `X` | attribute to the code's promoter; `displaced_promoter_id` = NULL | `code` | **false** | `code_only_link_ineligible` |
| **P4** | — | `E` | `∅` | attribute to the code's promoter | `code` | **false** | `code_only` |
| **P5** | — | `X` | `E` | attribute to the link's promoter | `link` | **true** | `link_after_code_ineligible` |
| **P6** | — | `∅` | `E` | attribute to the link's promoter | `link` | **true** | `link_only` |
| **P7** | — | `X` | `X` | **no attribution row.** Order completes normally. | — | — | `none_eligible` |
| **P8** | — | `X` | `∅` | **no attribution row.** | — | — | `none_eligible` |
| **P9** | — | `∅` | `X` | **no attribution row.** | — | — | `none_eligible` |
| **P10** | — | `∅` | `∅` | **no attribution row.** | — | — | `no_attribution_presented` |
| **M1** | binding request carries **>1 code** | — | — | **reject the binding call** `invalid_input`. Never silently pick. The order keeps its previous candidate. | — | — | — |
| **M2** | binding request carries **>1 link** | — | — | **reject the binding call** `invalid_input`. | — | — | — |
| **M3** | a *second* code is bound while `order.status='pending'` | — | — | **last write wins**, audited (`attribution.candidate_changed`). Not an error — a buyer correcting a typo is the common case. | — | — | — |
| **M4** | any binding attempted while `order.status <> 'pending'` | — | — | **reject** `attribution_frozen` (§3.3). | — | — | — |

**Self-deal never changes the winner.** It sets `self_deal_flag` + `self_deal_reasons` on whichever row P1–P6
produced, and withholds *payability* until adjudicated (§9.5). `VERIFIED:` DA §1.7 — *"flagged to the venue
rather than silently blocked"*; dash §10.7 — *"This flag is for you to look at, not an accusation."*

### 2.4 Why code beats link — the defence

P2 is the contested row. Four reasons, in order of weight:

1. **Affirmative-and-present beats passive-and-stale.** A typed code is a deliberate act performed at the
   moment of payment. A link reference may be days old, may have arrived via a browser prefetch, a group chat
   preview unfurl, or a shared device. When two signals conflict, the one the buyer *intended* is the one that
   is actually evidence of who sold the ticket.
2. **The owner's requirement forecloses the alternative.** *"Do not depend on links as the only attribution
   mechanism."* If links won, a code would be dead on every device that had ever touched any link — which is
   most of them — and the code feature would silently not work in exactly the cases anyone would notice.
3. **It is the better dispute record.** The code lives in the order's own command payload and in
   `attribution.code_id`. A link reference is a client-supplied string. When two promoters argue, the stronger
   evidence should win, and `resolution_reason` + `displaced_promoter_id` make the loser visible rather than
   erased.
4. **Support cost.** Promoters *will* say "use my code at checkout." A code that loses to an invisible cookie
   generates a support ticket the venue cannot answer.

**The risk this creates, named and mitigated:** promoter B can farm promoter A's traffic by broadcasting B's
code. Mitigations: `touch_corroborated=false` + `displaced_promoter_id` make it a visible pattern on the
venue's attribution view (dash §10.6), and E4–E6 mean a broadcast code only works where B is already
authorised. It is a *venue policy* problem with full evidence, not a silent money leak. → **OWNER DECISION 1**
records the alternative (link-wins) so the choice is deliberate.

### 2.5 `touch_corroborated` — the exact definition

> **`touch_corroborated` is TRUE iff the promoter credited by this attribution is also the promoter of the
> link reference presented with the order.**

- `method='link'` → trivially **true** (the link *is* the corroboration).
- `method='code'` + same-promoter link → **true** (P1).
- `method='code'` + no link, or a link belonging to someone else, or an ineligible link → **false**
  (P2, P3, P4).

Read plainly on the dashboard: *"true"* = the code and the click agree about who sent this buyer. *"false"* =
the code is the only evidence.

### 2.6 Multi-touch, and the honest limit

There is no touch table (§1.10), so **the client presents at most one link reference** — the last one it saw,
by ordinary client-side last-touch. The RPC rejects more than one (M2) rather than picking.

`INFERENCE:` this makes multi-touch arbitration **client-side and best-effort**, and this file states the
limits rather than implying a guarantee:

- A link touched on a phone and a checkout completed on a laptop **do not** connect. No cookie-based
  attribution system in the industry solves this without cross-device identity, which Phase 2 does not have.
- A cleared browser store loses the touch.
- **The code is the mechanism that survives all of it**, which is precisely the owner's point: the code is not
  a convenience layered on links, it is the *robust* channel and links are the lossy one.

The server-side guarantee is narrower and exact: **given the inputs presented, the winner is a pure,
deterministic function of server state.** That is the property the money needs.

### 2.7 Totality and tie-freedom — the argument

- The rows P0–P10 are a **partition** of `{E,X,∅} × {E,X,∅}` (nine cells) plus the frozen case P0 that
  short-circuits all nine. Nine cells, nine rows (P1 and P2 split the `E×E` cell on a promoter-identity
  predicate that is itself total — two promoter ids are either equal or not). **No input reaches the end of
  the table without matching a row, and no input matches two.**
- Multiplicity cannot create a tie because M1/M2 reject before the table is reached.
- Within a channel there is never an internal tie: the code channel is single-valued by column, and the link
  channel is single-valued by M2.
- Therefore precedence is a **total function** with no tiebreaker needed, no ordering over timestamps, and no
  dependence on client clocks. *(A last-touch tiebreaker would have required a trusted server timestamp,
  which is exactly the cost §1.10 declines to pay.)*

---

## 3. The attribution state machine and the economic-commitment freeze point

### 3.1 States

```
  UNBOUND ──bind code/link──► CANDIDATE ──rebind──► CANDIDATE   (order.status = 'pending')
     │                            │
     │                            │  order paid  ═══ FREEZE ═══
     ▼                            ▼
  (order paid, nothing        ATTRIBUTED (AO row written)
   presented)                      │
     │                             ├── self_deal_flag=false ──► ACCRUED ──settlement close──► SETTLED ──payout──► PAID
     ▼                             │
  UNATTRIBUTED (terminal)          └── self_deal_flag=true ───► HELD ──review release──► ACCRUED
                                                                 │
                                                                 └── review deny ──► DENIED (terminal)
```

| State | Where it lives | Mutable? |
|---|---|---|
| `UNBOUND` | `venue.order` with both candidate columns NULL | yes |
| `CANDIDATE` | `venue.order.attribution_candidate_*` | **yes** — freely rebindable while `pending` |
| `UNATTRIBUTED` | absence of a `venue.attribution` row on a non-pending order | terminal |
| `ATTRIBUTED` | the `venue.attribution` row | **no — AO, forever** |
| `HELD` / `ACCRUED` / `DENIED` | derived: `attribution.self_deal_flag` + latest `attribution_review.decision` | the *decision* is revisable until settled |
| `SETTLED` | `venue.settlement_line (cause='promoter_commission', cause_ref=attribution_id)` | **no — AO** |
| `PAID` | `kernel.payout` status machine | guarded transitions only |

### 3.2 The freeze point — stated exactly

> **Attribution freezes at the commit of the transaction that transitions `venue.order.status` from `pending`
> to `paid` — i.e. inside `venue.finalize_primary_order` (RPC §6.3), SSCAS member #1, in the same transaction
> that issues the ticket atoms.**

Before that commit, attribution is a *candidate* and is fully mutable. After it, the `venue.attribution` row
exists, is append-only, and no principal — promoter, venue manager, org owner, `platform_admin`, or
`service_role` — has a path to change who was credited.

### 3.3 Why *that* point and not another

Three candidates were considered; the reasoning matters more than the answer.

| Candidate freeze point | Rejected because |
|---|---|
| **Order creation** (`create_primary_checkout`) — *what RPC §6.1 and RLS §9.17 currently say* | A pending order is not an economic event. Most abandoned carts never pay. Writing an **append-only** ledger row for an event that may never happen pollutes the ledger with rows that must then be "ignored" by every reader — and an ignorable ledger row is a contradiction in terms. It also makes the promoter's dashboard show earnings that evaporate. → **§14.4 reports this as a live contradiction in the corpus.** |
| **Ticket issuance** (`kernel.issue_ticket_atoms`) | Same instant as order-paid (one transaction), but the wrong *aggregate*: attribution is a property of the **order** (the money event), not of the ticket (the asset). `VERIFIED:` DA §1.3 (order row) — *"Refunds, receipts, and attribution attach to the order; custody attaches to the ticket."* Binding it to issuance would also make a partially-issued order's attribution ambiguous. |
| **Settlement close** | Far too late. The promoter needs to see the sale the night it happens (DA §1.7: *"promoters run on cash flow"*), and settlement is days later. It would also mean the terms in force at settlement — not at sale — governed the commission, which inverts dash §10.3's whole point. |

**Order-paid is the point where the platform first has irreversible economic consequence** (money captured,
tickets minted, capacity consumed). That is what "economically committed" means, and it is where the freeze
belongs.

### 3.4 What the freeze forbids, concretely

| Attempt | Result |
|---|---|
| Rebind a code to a paid order | `attribution_frozen` (M4) |
| UPDATE `venue.attribution` (any column, any role) | AO guard trigger raises; `UPDATE` is REVOKEd |
| DELETE the attribution | GP-2: DELETE is denied to every role on every table |
| Deactivate the code, hoping to void the credit | Status is not retroactive — eligibility is evaluated at freeze only. `VERIFIED:` dash §10.5 — turning a switch off *"never deletes attribution already earned"* |
| Change the promoter's `commission_bps` after the sale | The attribution snapshotted `terms_version` + the applied rate (§1.5). New terms bind new sales only |
| Delete the promoter or the code | FK `ON DELETE RESTRICT` everywhere; GP-2 forbids the DELETE anyway |
| "Fix" a wrong attribution | **Not possible, by design.** The only remedy is an off-ledger commercial settlement between the org and the promoter, recorded (if the org wants it on-platform) as a Gate-M adjustment. → **OWNER DECISION 6** |

### 3.5 The race at the freeze boundary

A code is deactivated by a manager at the same moment a checkout commits.

**Resolution:** whichever state the resolver's snapshot saw is final. `venue.resolve_order_attribution` reads
`venue.promoter`, `promoter_code`, and `promoter_code_scope` **without locking them** (§7.9), so:

- The status flip commits first → the resolver sees `inactive` → the code is `X` → the table falls through.
- The checkout commits first → the resolver saw `active` → the attribution stands, and the later
  deactivation binds only future sales.

This is a benign sub-second race with a deterministic outcome in both directions, and it is *deliberately* not
serialized: taking a lock on the promoter/code rows during issuance would drag a low-value config row into
SSCAS member #1's lock set and create a deadlock class between "manager deactivates a code" and "buyer
checks out". A promoter engine must never be able to stall a checkout.

---

## 4. The no-double-commission invariant — as constraints, not policy

### 4.1 The invariant

> **For every paid `venue.order`, at most one promoter is credited, at most one commission is accrued, and at
> most one commission payout exists — for all time, across all settlements, under any sequence of retries,
> replays, webhook redeliveries, and concurrent transactions.**

### 4.2 The three constraints that make a second commission structurally impossible

Written the way they would actually appear:

```sql
-- (1) ONE ATTRIBUTION PER ECONOMIC EVENT.  Ratified (schema §3.17); restated here as the
--     first link of the chain.  The economic event is the paid order.
ALTER TABLE venue.attribution
  ADD CONSTRAINT attribution_one_per_order UNIQUE (order_id);

-- (2) ONE COMMISSION ACCRUAL PER ATTRIBUTION — ACROSS ALL SETTLEMENTS, EVER.
--     This is the constraint that does not exist today and without which the money
--     invariant is only a convention.  Partial, so it constrains exactly the one cause
--     whose cause_ref is an attribution id and leaves every other D3 cause alone.
CREATE UNIQUE INDEX attribution_one_commission_line_ever
  ON venue.settlement_line (cause_ref)
  WHERE cause = 'promoter_commission';

-- (3) ONE COMMISSION DISBURSEMENT PER ATTRIBUTION.  kernel.payout.idempotency_key is
--     already UNIQUE (schema §1.9) and is deterministic on (cause, cause_ref, payee)
--     per the Phase-0 payout discipline.  This spec pins the exact expression so two
--     call sites cannot derive it differently:
--        idempotency_key := 'promoter_commission:' || attribution_id || ':' || payee_identity_id
```

### 4.3 The proof

1. A commission can only exist as a `kernel.payout` row with `cause='promoter_commission'`. `VERIFIED:`
   schema §1.9 restricts `cause` to the D3 set, and D3 has exactly one commission cause (RAT D3). There is no
   second path to a promoter's money.
2. Every such payout carries `cause_ref = <attribution_id>` (schema §1.9: *"cause_ref … (settlement_line id,
   market_sale id, **attribution id**)"*) and a deterministic `idempotency_key` over
   `(cause, cause_ref, payee)`. `UNIQUE(idempotency_key)` ⇒ **at most one payout per (attribution, payee)**.
   The payee is functionally determined by the attribution (`attribution.promoter_id → promoter.identity_id`),
   so ⇒ **at most one payout per attribution**.
3. Constraint (2) ⇒ **at most one `promoter_commission` settlement line per attribution**, across every
   settlement of every venue for all time — so an attribution that slipped into a second settlement period
   (re-open, re-close, a period boundary bug, a manual re-run) aborts on the index instead of silently
   double-crediting the settlement's net.
4. Constraint (1) ⇒ **at most one attribution per order**.
5. Compose: paid order → ≤1 attribution → ≤1 accrual line → ≤1 payout. **∎**
6. **Redirection is impossible too**, which the three uniqueness constraints alone would not give: the freeze
   (§3) makes `attribution.promoter_id` immutable, so the single permitted commission cannot be moved to a
   different payee after the fact.

### 4.4 Relation to C26 `UNIQUE(cause, cause_ref, ticket_id)`

`VERIFIED:` C26's key is `(cause, cause_ref, ticket_atom_id)` and its whole point (schema §1.6.1 proof (b))
is that **the subject must be in the key** so one cause may legitimately affect N subjects — one order mints N
atoms, one refund voids K atoms.

The commission shape is **the same key with a degenerate subject**:

| | Ownership log (C26) | Commission accrual (this spec) |
|---|---|---|
| cause | `issue` / `market_sale` / `refund_void` … | `promoter_commission` |
| cause_ref | order / sale / refund id | **attribution id** |
| subject | `ticket_atom_id` — **N per cause** | the promoter — **exactly 1 per cause_ref, by (1) + the freeze** |
| key | `UNIQUE(cause, cause_ref, ticket_atom_id)` | `UNIQUE(cause_ref) WHERE cause='promoter_commission'` |

The subject column is omitted from constraint (2) **because it is functionally determined by `cause_ref`**,
not because the pattern differs. Including it would be harmless but would weaken the constraint: a bug that
wrote two lines for one attribution with two different promoter ids would then pass. Stated explicitly so a
future reviewer does not "restore consistency" with C26 by adding a column and quietly opening the hole.

Multiplicity, in one line each: **ownership** allows one cause → N tickets; **commission** allows one
attribution → exactly one credit. Both are enforced by the shape of the key, and neither by code discipline.

### 4.5 Idempotency keys, collected

| Operation | Key | Enforced by |
|---|---|---|
| Bind a candidate | `p_command_key` per RPC §0.x convention | command-key dedupe in the RPC |
| Create the order | `UNIQUE(buyer_id, command_idempotency_key)` | ratified, schema §3.7 (C16) |
| Write the attribution | `UNIQUE(order_id)` | (1) above |
| Accrue the commission | `cause_ref` partial unique | (2) above |
| Disburse | `payout.idempotency_key` | (3) above, ratified schema §1.9 |
| Issue a code | `UNIQUE(code_normalized)` + `p_command_key` | §1.1 |
| Adjudicate a flag | `UNIQUE(attribution_id, seq)` + `p_command_key` | §1.6 |

Every one of them is a **constraint**, so replay-safety survives a code path nobody remembered to guard.

---

## 5. Refunds, transfers, resale, cancellation — and the Gate-M clawback boundary

### 5.1 The decision that makes all of this tractable

> **Phase 2 pays promoter commission only at settlement close. There is no instant promoter payout in
> Phase 2.**

`VERIFIED:` DA §1.7 wants commissions *"instant-eligible where risk allows"*. `VERIFIED:` C29 —
*"First-class Reserve/Clawback object + payout-timing policy **gating instant payout**"* — is
`RATIFIED-MODELED-ONLY(GATE-M)`, *"NOT in the Phase-2 foundation"* (RAT). Instant payout without a reserve is
an unsecured advance against a refundable sale.

So the two are the same decision, and the constitution has already made it: **no reserve ⇒ no instant payout ⇒
settle-then-pay.** Everything below follows.

**The consequence, which is the whole answer to the clawback question:** settlement closes after the event.
Buyer-request refunds and cancellations land *before* close. Therefore **the ordinary refund case needs no
clawback at all — there is nothing to claw back, because nothing was paid.** The commission is simply computed
net at close (§6.3).

### 5.2 Refund of an attributed order — before settlement close

| Case | Attribution row | Commission effect |
|---|---|---|
| Full refund | **unchanged** (AO — the sale happened, then was reversed; the ledger records both) | The order's terminal money state is `refunded` ⇒ commissionable basis = 0 ⇒ **no `promoter_commission` line, no payout**. Constraint (2) is never exercised. |
| Partial refund | **unchanged** | Basis recomputed from the order's surviving, non-voided items (§6.3) ⇒ a smaller single line. Still one line, still one payout. |
| Refund *after* the commission line is written but before close | **unchanged** | The settlement is still `open`; `kernel.close_settlement` recomputes from live state at close. `INFERENCE:` this requires commission lines to be written **at close only**, never incrementally — pinned as a design rule in §6.3. |

`VERIFIED:` D2 — a refunded ticket goes to `voided` (there is no `refunded` ticket terminal); the *order* has
`partially_refunded` / `refunded` (schema §3.7). The basis calculation reads the order's money state and the
atoms' `voided` state, not a ticket "refunded" flag that does not exist.

### 5.3 Refund or chargeback *after* settlement close — the genuine clawback case

This is the case Phase 2 cannot represent, and the file says so rather than inventing a mechanism.

| | |
|---|---|
| **Is a clawback representable today?** | **No.** `VERIFIED:` C29 (reserve/clawback object), C30 (fan-side clawback liability), C31 (double-entry ledger that would host both) are all `RATIFIED-MODELED-ONLY(GATE-M)`. `VERIFIED:` schema §1.9 states it in the table itself: *"No reserve/clawback funding modeled in MVP — that is **Gate M** (C29/C31)."* `kernel.payout` has a `reversed` status but **no funding source for the reversal** — a status without money behind it is a label, not a clawback. |
| **Phase-2-safe interim behaviour** | The chargeback or late refund produces a **negative `venue.settlement_line`** in the org's **next open settlement**, with cause `chargeback` or `refund_void` and `cause_ref` = the dispute/refund id. **The org absorbs it; the promoter's already-paid commission is not pursued.** No new object, no new cause code (both are in D3), and it is exactly how the frozen platform already handles a post-payout reversal. |
| **Why the org absorbs it** | Because Phase 2 has no lever that could make the promoter absorb it. Pursuing a paid-out commission requires either a reserve balance to net against (C29) or a receivable/negative-balance object (C30) — both Gate-M. The alternative to "the org absorbs it" is not "the promoter absorbs it", it is "the system silently disagrees with itself about who is owed what". |
| **How exposure is bounded in the meantime** | Settle-then-pay (§5.1) already removes ~all buyer-request refunds from the window. What remains is the chargeback tail (up to ~120 days post-charge). The bound is: **exposure ≤ Σ commission on charged-back attributed orders whose settlement closed before the dispute arrived.** At a nightlife commission of 5–15% of face, that is 5–15% of the org's chargeback rate — a number the org can see and price. It is not zero and this file does not claim it is. |
| **What Gate M must add** | (a) C29 reserve with a promoter-scoped balance and a payout-timing policy; (b) a `commission_adjustment` object carrying a signed delta against a **frozen** attribution (so the AO ledger is never edited); (c) the C31 double-entry home for both. **Only then** may instant promoter payout be enabled — and this spec asks that the instant-payout switch be *gated on C29 landing*, not on a feature flag someone can flip. |

→ **OWNER DECISION 3** records the alternative (promoter bears the post-close reversal, requiring Gate-M).

### 5.4 Event cancellation

`VERIFIED:` SSCAS member #10 is the event-cancellation cascade (`catalog.cancel_event`), which refunds every
order. Every attributed order therefore reaches a terminal refunded state, every basis goes to 0, and **no
commission is due** — falling out of §5.2, with no cancellation-specific logic anywhere.

`INFERENCE:` the promoter's portal must say *"Event cancelled — commission reversed"* rather than showing an
accrual that quietly becomes zero. → §11.1.

### 5.5 P2P transfer of an attributed ticket

**No effect on commission. The promoter keeps it.**

The economic event was the **primary sale**; the commission is compensation for causing that sale. `VERIFIED:`
the ownership log records a `p2p_transfer` cause against the ticket, while attribution is bound to
`venue.order` — the two ledgers do not intersect. `VERIFIED:` DA §1.3 (order row) — attribution attaches to the order,
custody to the ticket. A buyer giving their ticket to a friend does not un-sell it.

### 5.6 Marketplace resale of an attributed ticket — **the original promoter earns nothing on the resale**

**Product answer: NO.** Defence:

1. **Structural.** `venue.attribution.order_id` FKs `venue.order`. A native resale is a `market.market_sale`,
   not an order. There is no column that could hold the credit, and manufacturing one would put a `venue`
   object in the resale money split — a `venue → market` coupling the aggregate rules forbid (CDM §2:
   *"`market`/`venue` reference `kernel`/`catalog`, never the reverse"*, and the resale payee set is already
   closed: seller proceeds + venue royalty + platform fee).
2. **Commercial.** Commission compensates *causing the primary sale*. The promoter did that once and was paid
   once. Paying again on a resale pays them for someone else's decision to sell.
3. **Incentive.** A promoter who earns on resale earns more when their allocation is scalped. `VERIFIED:` DA
   §2652 and the whole governed-secondary thesis exist to *suppress* that incentive. Building a commission
   that rewards it would be the single most self-defeating money rule in the platform.
4. **Consistency.** The venue's own recapture on a resale is the **royalty** (`venue_royalty` settlement
   line), which flows to the org. If the org chooses to share royalty with a promoter, that is an org policy
   with an org-level mechanism — not a per-ticket attribution chain.

→ **OWNER DECISION 2** — flagged because it is a commercial call, and because a "lifetime attribution" model
(promoter earns on every future movement of a ticket they originally sold) is a real product some competitors
market. This file's position is that it is wrong for Snatch It, and it is additive to build later (a
`market_sale`-grain attribution with its own cause) if the owner disagrees.

### 5.7 Summary

| Event | Attribution row | Commission | Mechanism |
|---|---|---|---|
| Full refund pre-close | unchanged (AO) | none | basis = 0 at close |
| Partial refund pre-close | unchanged | reduced | basis recomputed at close |
| Refund/chargeback post-close | unchanged | **already paid; not recovered in Phase 2** | negative settlement line against the org; §5.3 |
| Event cancelled | unchanged | none | cascade → all orders refunded |
| P2P transfer | unchanged | unchanged | different ledger |
| Marketplace resale | unchanged | **none on the resale** | §5.6 |
| Ticket voided by admin | unchanged | reduced/none at close | the atom is `voided`; basis excludes it |

---

## 6. Commission calculation, and where it is authoritative

### 6.1 The basis

> **`basis_minor` = Σ over the order's surviving items of `unit_price_minor × quantity`** — i.e. the **face
> subtotal**, excluding platform fees, buyer fees, taxes, and tips.

Defence: fees are not the org's revenue, and paying a percentage of the platform's own fee would make the
promoter's commission move when the platform reprices. `VERIFIED:` schema §3.8 — `order_item.unit_price_minor`
is the **immutable snapshot at purchase**, frozen after issuance, which makes the basis reproducible forever.
→ **OWNER DECISION 4** (gross-of-fees is the alternative; it is a rate conversion, not a redesign).

### 6.2 The formula, and its snapshot

At **freeze** (§3.2), the resolver snapshots the promoter's terms onto the attribution row and computes:

```
  commission_kind = 'bps':
      credited_amount_minor = floor(basis_minor * commission_bps_applied / 10000)

  commission_kind = 'flat_per_ticket':
      credited_amount_minor = commission_flat_minor_applied * (Σ order_item.quantity over surviving items)
```

- **Rounding: `floor`, always.** The residual stays with the org. `VERIFIED:` C31 requires a *named* rounding
  bearer and schema §3.14 provides `settlement_line.is_rounding_bearer`; commission never claims the residual,
  so the bearer designation is unambiguous and unchanged by this feature.
- **`terms_version` is snapshotted**, not referenced. `VERIFIED:` dash §10.3 — the terms in force at the sale
  are the terms that govern, and the surface must show which version each attribution was earned under.
  Referencing a mutable `venue.promoter` row would make every historical commission change when someone edits
  a rate.
- **Currency:** single-currency in Phase 2 (`USD`). C32 multi-currency is Gate-L; the column exists for
  forward compatibility, and the resolver asserts `order.currency = 'USD'`.

### 6.3 Two numbers, and which is authoritative

| Number | Where | When | Authority |
|---|---|---|---|
| **Accrual** — `attribution.credited_amount_minor` | the AO attribution row | at freeze | **Authoritative for "what this sale earned at the moment it happened."** Frozen forever. Drives the promoter's "earned tonight" view. |
| **Payable** — the `promoter_commission` `settlement_line.amount_minor` | the AO settlement line | at `kernel.close_settlement` | **Authoritative for money.** Recomputed at close from (a) the frozen terms on the attribution, (b) the order's *terminal* money state, (c) the effective `attribution_review` decision. |

> **`kernel.close_settlement` is the sole authority for commission money.** Nothing else may write a
> `promoter_commission` settlement line or payout.

**Pinned design rule:** commission lines are written **at close, once**, never incrementally as sales land.
Incremental accrual lines would require mutation when a refund arrives, and settlement lines are AO
(schema §3.14). This is what makes §5.2 work without a clawback.

**Payable at close** — the exact rule:

```
  payable = 0                      if the order is fully refunded / all atoms voided
  payable = 0                      if effective attribution_review decision = 'deny'
  payable = 0                      if self_deal_flag AND no review decision exists   ← withheld, not lost
  payable = recompute(basis over surviving items, snapshotted terms)   otherwise
```

**`payable = 0` for an unreviewed flag is a hold, not a forfeiture.** Because constraint (2) writes at most one
line *ever* per attribution, a hold must not write a zero line — it must **write no line at all**, leaving the
attribution eligible for a later settlement once adjudicated. `INFERENCE:` this makes "unreviewed flags roll
to the next settlement" the behaviour, and the venue's incentive to clear the queue before close is exactly
right: the promoter is not paid until someone looks. → this must be visible on the close dialog (§11.2).

### 6.4 Where the number is displayed vs. where it is decided

| Surface | Shows | Reads |
|---|---|---|
| Promoter portal "earned" | **accrual** | `attribution.credited_amount_minor` |
| Promoter portal "paid" | **payout** | `kernel.payout` (own, scoped RPC — §8.3) |
| Venue dashboard "commission accrued" | accrual sum | `venue.attribution` |
| Venue dashboard "commission paid" | payout sum | `kernel.payout` cause `promoter_commission` |
| Settlement detail | **payable** | `venue.settlement_line` |

`VERIFIED:` dash §10.9 — when the paid column cannot be read it renders `"—"`, **never zero**. This file
endorses that as a hard rule for every commission surface: a zero where a number is unavailable reads as
*"we decided you get nothing"*.

---

## 7. RPC contracts

House conventions (RPC §0.x, restated once): all are `SECURITY DEFINER`, owned by `postgres`, `search_path`
pinned, params **untrusted**, actor `auth.uid()` **server-derived** (C35), direct client DML denied (GP-1),
`p_command_key` dedupes. Error codes below are the RPC spec's vocabulary: `unauthorized`,
`precondition_failed`, `invalid_input`, `not_found`, `rate_limited`, `idempotency_replay`, plus the
feature-specific ones named.

All are **`NEW RPC` · package `090`** unless stated.

### 7.1 `venue.create_promoter_code(p_promoter_id, p_code_display, p_event_ids uuid[], p_valid_from, p_valid_until, p_kind, p_command_key)`

- **Role:** promoter-program manager `has_venue_role([venue_manager])` OR `has_org_role([org_owner, org_admin])`, scoped to the promoter's org. **`venue_promoter` is explicitly forbidden** — a promoter cannot mint their own codes (§8.2).
- **Pre:** promoter exists, `status='active'`, in caller's org; `normalize(p_code_display)` passes the length/alphabet CHECKs; every `p_event_id` belongs to the promoter's org; `p_valid_until > p_valid_from`; for `p_kind='generated'`, the display form meets the §9.3 entropy floor.
- **Post:** one `venue.promoter_code` + N `promoter_code_scope` rows + `kernel.admin_audit('promoter_code.issue')`.
- **Locks:** none cross-aggregate. **SSCAS:** n/a (single aggregate).
- **Idempotency:** `p_command_key`; a replay returns the same `code_id`. A *different* command key with the same normalized code returns `code_taken` — never a silent second code.
- **Errors:** `code_taken` (23505 on `code_normalized`, mapped), `invalid_code_format`, `promoter_inactive`, `event_out_of_org`, `entropy_below_floor`, `unauthorized`.
- **Returns:** `{ status, code_id, code_display, code_normalized, confusable_with[] }` — `confusable_with` lists existing codes whose normalized form is within edit-distance 1, for the dashboard's warning (§11.2).

### 7.2 `venue.create_promoter_codes_bulk(p_promoter_id, p_count, p_kind, p_event_ids, p_valid_from, p_valid_until, p_command_key)`

- **Purpose:** the 5,000-code case (§10.1) in one audited call.
- **Role:** as §7.1. **`p_count` capped at 1,000 per call**; a larger program is multiple calls (bounded transaction, bounded lock time, bounded audit row).
- **Generation:** server-side CSPRNG over the 32-symbol alphabet, at the §9.3 entropy floor. On a unique-violation, retry that one code up to 5 times, then fail the call — never silently emit fewer codes than requested.
- **Post:** N codes + one audit row recording `(promoter_id, count, kind, scope)` — **not** N audit rows.
- **Errors:** `count_exceeds_cap`, `generation_exhausted`, + §7.1's set.

### 7.3 `venue.set_promoter_code_status(p_code_id, p_status, p_command_key)`

- **Role:** as §7.1. **Pre:** code exists, in caller's org. **Post:** `status` updated + audit (`promoter_code.activate` / `.deactivate`).
- **Explicitly NOT possible:** changing `promoter_id`, `code_display`, `code_normalized`, or `kind` — the immutability trigger (§1.1) raises regardless of caller, and **no RPC accepts those params**. This is dash §10.5's "no reassignment", enforced twice.
- **Errors:** `not_found`, `unauthorized`.

### 7.4 `venue.set_promoter_code_scope(p_code_id, p_add_event_ids[], p_remove_event_ids[], p_command_key)` / `venue.set_promoter_code_window(p_code_id, p_valid_from, p_valid_until, p_command_key)`

- **Role:** as §7.1. Both audited. Neither is retroactive: **no recorded attribution is affected** (§3.4).
- **Errors:** `event_out_of_org`, `invalid_window`, `not_found`, `unauthorized`.

### 7.5 `venue.preview_promoter_code(p_code_display, p_session_id)` — read-only, advisory

- **Role:** any `authenticated`; also reachable unauthenticated **only** via the edge wrapper (§7.10).
- **Returns exactly one of:**
  - `{ status:'eligible', promoter_display_name, method_hint:'code' }`
  - `{ status:'not_applicable' }` — **for every failure**: unknown code, inactive, out of window, wrong org, out of scope, inactive promoter.
- **The single response for all failures is the design** (§9.4): any distinction turns this into a code-existence oracle. The client's copy is *"That code isn't valid for this event"* — true in every branch.
- **Writes:** none. **Locks:** none. **SSCAS:** n/a. **Rate-limited by its edge wrapper**, not here (`check_rate_limit` is `service_role`-only — VERIFIED, `005_rate_limits.sql`).
- **Advisory only.** A code that previews eligible may still lose at commit (a link cannot beat it, but a deactivation can — §3.5). The client must never persist the preview as the answer.

### 7.6 `venue.bind_order_attribution(p_order_id, p_code_display, p_link_slug, p_command_key)`

- **Purpose:** attach or replace the candidate on a pending order — the "I forgot to enter the code" path, and the path the RN checkout uses when the code is typed after the order is created.
- **Role:** the order's buyer (`auth.uid() = order.buyer_id`), OR a door/box-office principal for an on-behalf order.
- **Pre:** `order.status = 'pending'`. Exactly ≤1 code and ≤1 link (M1/M2 → `invalid_input`).
- **Post:** `attribution_candidate_code_id` / `_link_id` set; audit `attribution.candidate_changed` with old/new. **Does not** write `venue.attribution`.
- **Locks:** the order row `FOR UPDATE` (class **Order**, rank 3 — inside the ratified order; no new class).
- **Idempotency:** `p_command_key`. **Errors:** `attribution_frozen` (order not pending — M4), `invalid_input`, `not_found`, `unauthorized`.
- **Never fails the order.** An unresolvable code sets the candidate to NULL and returns `{ status:'ok', bound:false, reason:'not_applicable' }` — see §7.11.

### 7.7 `venue.review_attribution_flag(p_attribution_id, p_decision, p_reason_code, p_note, p_command_key)`

Satisfies **dash Δ4 / §21.4** and resolves **dash §22.4**.

- **Role:** promoter-program manager `has_venue_role([venue_manager])` OR `has_org_role([org_owner, org_admin])`; `is_platform([platform_risk])` from the admin plane.
- **Pre:** attribution exists, in caller's scope, `self_deal_flag = true`; **no `promoter_commission` settlement line exists for it** → else `attribution_settled`.
- **Post:** one `venue.attribution_review` row at `seq = coalesce(max(seq),0)+1` + audit (`attribution.review`). **The attribution row is not touched.**
- **Locks:** none cross-aggregate. **SSCAS:** n/a.
- **Errors:** `attribution_settled`, `not_flagged`, `not_found`, `unauthorized`, `invalid_reason_code`.

### 7.8 `venue.resolve_order_attribution(p_order_id)` — **INTERNAL. Not client-callable.**

The precedence engine. `REVOKE EXECUTE FROM anon, authenticated`; called only from
`venue.finalize_primary_order` **inside the paid transaction**.

- **Pre:** called with the order row already locked `FOR UPDATE` by the caller, in the transaction that is
  setting `status='paid'`.
- **Reads (no locks taken):** `venue.order` (candidates), `order_item`, `venue.promoter_code`,
  `promoter_code_scope`, `promoter_link`, `venue.promoter`, `catalog.event_session`→`event`,
  `kernel.payment_native` (instrument fingerprint, for §9.5).
- **Logic:** eligibility (§1.2 E1–E7) per channel → the §2.3 table → self-deal detectors (§9.5) → basis and
  commission (§6.1/§6.2) → **INSERT one `venue.attribution`** (or none).
- **Post:** 0 or 1 attribution row. **Never raises for an attribution problem** (§7.11).
- **Idempotency:** `UNIQUE(order_id)`; a replayed finalize hits the constraint and the function returns the
  existing row (P0).
- **Emitted facts:** `AttributionRecorded` (DA §6.1 event 31, keyed `order_id + link_id` — this spec widens
  the key to `order_id`, since the source may now be a code; see §14.5).

### 7.9 Lock order — and why C28 needs no amendment

`VERIFIED:` the global order is
`Event/Session(1) < Inventory(2) < Order(3) < Listing(4) < Ticket Atom(5) < money-plane(6)`, and C28 requires
**every locked class to be placed** (RAT C28).

**This feature introduces no new locked class.** Precisely:

| Object | Access in the paid transaction | Lock |
|---|---|---|
| `venue.order` | already locked by `finalize_primary_order` | class 3 — **existing** |
| `venue.promoter`, `promoter_code`, `promoter_code_scope`, `promoter_link` | **read-only, unlocked** | **none** |
| `venue.attribution` | **INSERT only** | none (the unique index arbitrates) |
| `kernel.payment_native` | read (fingerprint) | none |

- An INSERT into an empty-of-that-key table takes no row lock that another transaction can be waiting on
  *except* via the unique index, and index-conflict waits are on a single key with an immediate winner — not
  a cycle.
- The config rows are read at the transaction's snapshot; §3.5 shows both race outcomes are correct.

**Therefore SSCAS member #1's lock sequence is unchanged** (`2 → 3 → 5 → 6`), member **#5 (Attribution →
commission)** keeps its ratified shape — `VERIFIED:` RPC §14.1 already writes it as *"(Attribution read) →
Settlement → Payout"*, i.e. attribution is read, not locked, at close — and **C28's closed fifteen and its
lock order stand unamended.** This is a deliberate constraint on the design, not a lucky outcome: any version
of this feature that locked a promoter or code row during checkout would have required a constitutional
amendment and would have created a deadlock class between config edits and checkout.

### 7.10 `promoter-code-preview` — **`NEW EDGE FUNCTION`** · package `090` (function deploy, not a migration)

- **Method:** `POST` (+ `OPTIONS`). **verify_jwt:** `false` — a buyer may type a code before signing in.
- **Body:** `{ code: string, session_id: uuid }`.
- **Rate limit — the reason this must be an edge function:** `VERIFIED:` `public.check_rate_limit` is
  `GRANT EXECUTE ... TO service_role` only (`supabase/migrations/005_rate_limits.sql`), so a rate-limited
  preview cannot be a plain PostgREST RPC call.
  - authenticated: `check_rate_limit(user.id, 'promoter-code-preview', 10, 60)`
  - anonymous: `check_rate_limit(uuidv5(NS_PROMOCODE, ip || ':' || sha256(user_agent)), 'promoter-code-preview-anon', 5, 60)` — `VERIFIED:` the function's first parameter is `uuid`, so an anonymous principal must be *derived* as a uuid; that derivation is this spec's adaptation and is called out in §14.6.
  - **fail-closed**: 503 on limiter error, 429 over-limit (edge §7).
- **Calls:** `venue.preview_promoter_code`. **Returns** its two-valued result verbatim.
- **Logging:** never log the submitted code string at info level (it is a shared secret of sorts); log only the outcome class.

### 7.11 Cross-cutting rule: **an attribution failure never fails a sale**

Stated once and binding on every RPC above:

> No attribution condition — unknown code, deactivated code, out-of-scope code, malformed input, missing
> promoter, rate-limited preview, or resolver error — may abort a checkout, refuse a payment, or roll back an
> issuance.

`venue.resolve_order_attribution` runs inside `finalize_primary_order`, so a raise there **would** roll back
the money and the tickets. It therefore never raises: every non-happy path resolves to "no attribution row",
and an *unexpected* internal error is caught, recorded to `kernel.admin_audit` as
`attribution.resolver_error` with the order id, and swallowed. A missing commission is a support ticket; a
failed checkout on a sold-out Friday is a business incident. `INFERENCE:` this asymmetry is not stated in any
binding input, and it is the single most important operational rule in this file.

---

## 8. RLS delta and the promoter's own-attribution read path

Global postures GP-1 (no direct client DML anywhere) and GP-2 (DELETE denied for every role on every table)
apply unchanged; every write below is `R` (RPC-only).

### 8.1 `venue.promoter_code` / `venue.promoter_code_scope` — `ADDITIVE` · package `090`

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner / org_admin | A(own-org) | R | R | D | create/bulk/status/scope/window |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager *(= promoter-program manager)* | A(own-venue's org) | R | R | D | create/bulk/status/scope/window |
| venue_finance | A(own-org) | D | D | D | — |
| venue_door | D | D | D | D | — |
| **promoter** | **A(own codes only)** | **D** | **D** | D | — |
| platform_support / platform_risk | A | D | D | D | — |
| platform_admin | A | R | R | D | override (audited) |
| service_role | A(machine) | R(def) | R(def) | D | definer |

Mirrors RLS §9.17's promoter/link matrices exactly, which is the point: a code is a link's sibling and must
not acquire a wider grant by being newer.

### 8.2 The promoter cannot mint their own codes — and why that is not arbitrary

`VERIFIED:` RLS §9.17 gives `promoter` **no** INSERT/EXEC on `venue.promoter` or `promoter_link`; DA Part 2 (data-ownership-vs-custody) —
*"the **promoter owns the link** … but the **org owns the terms** … the promoter cannot rewrite their own
commission."*

A self-minted code is a self-minted *distribution surface* over the org's namespace: the promoter could seize
`CLUBSPACE`, `NYE`, or a rival's brand, and the global namespace (§10.2) means those grabs are permanent
(codes are immutable, §1.1). The org must be the issuer. This also directly serves **O-2**: a promoter is an
attribution identity, not an administrator of anything.

`INFERENCE:` the *request* path is a legitimate product need — a promoter asking for `JORDY` — and it is a
notification/inbox flow, not a grant. Out of scope here; noted so nobody implements it as a permission.

### 8.3 `venue.attribution` — `SPEC CORRECTION` to RLS §9.17 · package `090`

The matrix is unchanged (promoter reads **own** only; org/venue-scoped for the back office; AO for everyone).
Two corrections the new columns force:

1. **The promoter's own-row predicate must be `attribution.promoter_id = auth.uid()`-resolved**, not
   `attribution → link_id → promoter_link → promoter`. With `link_id` now nullable (§1.5) the old join
   silently returns **zero rows for every code-sourced attribution** — a promoter would see none of their
   code earnings. This is the concrete reason `promoter_id` is denormalized onto the row.
2. **Column-scoping for the promoter's own read.** A promoter may read `self_deal_flag` and
   `self_deal_reasons` on their own rows (they must know why a payment is held) but **never** `note` on
   `attribution_review` (the venue's internal deliberation) and **never** `displaced_promoter_id` (another
   promoter's identity). Enforced by the read RPC's projection (§8.5), not by hoping the client omits columns.

### 8.4 `venue.attribution_review` — `ADDITIVE` · package `090`

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner / org_member | D | D | D | D | — |
| org_owner / org_admin | A(own-org) | R | D | D | `review_attribution_flag` |
| org_finance | A(own-org) | D | D | D | — |
| venue_manager | A(own-venue's org) | R | D | D | `review_attribution_flag` |
| venue_finance | A(own-org) | D | D | D | — |
| venue_door | D | D | D | D | — |
| **promoter** | **V**(own attribution's `decision` + `reason_code` **only**, via §8.5) | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A | R | D | D | `review_attribution_flag` |
| platform_admin | A | D | D | D | — |
| service_role | A(machine) | R(def) | D | D | definer |

UPD is `D` for **every** role including `platform_admin` — the table is AO; corrections are a new `seq`.

### 8.5 The promoter's own-attribution read path — **footnote 15, made real**

`VERIFIED:` RLS §7.9 note 15 — *"`promoter` reads own `promoter_commission` payout **only** via a scoped RPC
(own attribution), not the org payout ledger (CDM §8)."* No such RPC is contracted anywhere. Two are specified
here.

**`venue.get_my_promoter_summary(p_org_id, p_event_id, p_window)` — `NEW RPC` · package `090`**

- **Role:** the caller must own a `venue.promoter` row in `p_org_id` — checked **in-body against the live
  table**, never from a JWT claim (C9).
- **Returns:** per-event and total: tickets attributed · gross attributed (`Σ basis_minor`) · commission
  accrued (`Σ credited_amount_minor`) · commission **held** (flagged, unreviewed) · commission **paid** (from
  `kernel.payout`) · code count · link count.
- **Reads:** `venue.attribution` filtered to `promoter_id ∈ (caller's own promoter rows)`; `kernel.payout`
  filtered to `cause='promoter_commission' AND cause_ref IN (those attribution ids)`. **This filter is the
  entirety of footnote 15's "scoped RPC"** — the promoter never touches the payout table, never sees an org
  aggregate, and cannot widen the filter by passing a parameter, because the promoter id set is derived from
  `auth.uid()` and not accepted as input.
- **Never returns:** buyer identity, buyer contact, order ids belonging to other promoters, org totals, other
  promoters' anything, `instrument_fingerprint`.

**`venue.list_my_attributions(p_org_id, p_filters, p_cursor)` — `NEW RPC` · package `090`**

- Same authority derivation. Keyset pagination on `(order_paid_at DESC, id DESC)`.
- **Projection (exact):** `occurred_at · event title · ticket type · qty · basis_minor · credited_amount_minor
  · method · terms_version · self_deal_flag · self_deal_reasons · review decision + reason_code · payout
  status`.
- **Redacted:** buyer name, buyer email, buyer id, order ref, `displaced_promoter_id`, `note`,
  `touch_corroborated` *(the venue's hijack-detection signal; showing it to the promoter turns a fraud control
  into a coaching tool for gaming it)*, `instrument_fingerprint`.
- `VERIFIED:` CDM §8 / RLS §9.17 note 40 — promoter isolation: own links/attributions/commission only, never
  buyer PII, never the back office.

### 8.6 Venue-side read — `NEW RPC` · package `090`

**`venue.list_promoter_attributions(p_scope_kind, p_scope_id, p_filters, p_cursor)`** — the dash §10.6 view.

- **Role:** `has_venue_role([venue_manager, venue_finance])` OR `has_org_role([org_owner, org_admin, org_finance])`.
- Projection is dash §10.6's exact column list, plus `displaced_promoter_id` resolved to a display name.
- **No buyer PII in any projection.** `VERIFIED:` dash §10.6 — *"the promoter dimension never becomes a back
  door into the attendee list."* This RPC returns an order **reference**, not an attendee.
- Export only through the audited export path (dash §9.6); `venue_door`, `org_member`, and `promoter` are
  denied outright, per dash §9.6's allow-list.

---

## 9. Fraud and abuse controls, quantified

### 9.1 The threat list

| # | Threat | Attacker gains | Control |
|---|---|---|---|
| T1 | Enumerate the code namespace | the venue's promoter roster; a target list for T2/T3 | §9.4 |
| T2 | Bind purchases to a promoter you do not control | grief (chargeback exposure attached to a real promoter); noise in a rival's numbers | §9.4 + the fact that the attacker must *pay for a real ticket* per probe |
| T3 | Self-referral: promoter buys through own code | commission on their own spend | §9.5 |
| T4 | T3 via a second account | same, evading identity match | §9.5 — **partially undetectable in Phase 2, stated** |
| T5 | Promoter mints a vanity code they should not own | namespace seizure, brand impersonation | §8.2 — promoters cannot mint |
| T6 | Code hijack: promoter B broadcasts a code that outranks A's link | A's traffic, B's commission | §2.4 — visible via `touch_corroborated` + `displaced_promoter_id` |
| T7 | Confusable substitution: register `J0RDY` to intercept `JORDY` | interception of a rival's typed traffic | §1.3 — **impossible**: they are the same key |
| T8 | Replay a checkout to double-credit | duplicate commission | §4 — impossible by constraint |
| T9 | Deactivate/reactivate to retro-credit or retro-void | rewrite history | §3.4 — eligibility is evaluated at freeze only |

### 9.2 The structural controls (no runtime cost)

- **Confusable collapse** (§1.3) kills T7 outright — not "warns about", *kills*.
- **Immutability of `promoter_id` on a code** (§1.1) means a code can never become someone else's.
- **Freeze** (§3) means no post-hoc rewrite (T9).
- **Uniqueness chain** (§4) means no double credit (T8).
- **Issuer separation** (§8.2) means no self-minting (T5).

### 9.3 Entropy floor — quantified

| Code kind | Floor | Namespace | Live codes assumed | P(one random guess hits a live code) |
|---|---|---|---|---|
| `generated` | **8 symbols** over the 32-symbol alphabet | 32⁸ ≈ **1.10 × 10¹²** | 5 × 10⁶ (1,000 orgs × 5,000) | **≈ 4.5 × 10⁻⁶** |
| `vanity` | 4 symbols (`"JORDY"` is 5) | — | — | **not entropy-defensible** |

- At the generated floor, with the §9.4 budget of **10 probes/minute**, the expected number of probes to a
  single hit is ≈ 2.2 × 10⁵ ⇒ **≈ 15 days of continuous, undetected, per-principal abuse per hit**, against
  a control that also fails closed and audits bursts. That is a sufficient floor.
- **6 symbols would not be**: 32⁶ ≈ 1.07 × 10⁹, giving ≈ 4.7 × 10⁻³ per guess — one hit per ~213 probes,
  i.e. ~21 minutes at the budget. The floor is 8 precisely because 6 fails this arithmetic.
- **Vanity codes are not protected by entropy and this file does not pretend otherwise.** Their protection is
  **scope** (§1.2 E4–E6: a guessed code only works where its promoter is already authorised) and the fact that
  the only thing a correct guess achieves is *giving away commission on a ticket the attacker paid for*.

### 9.4 Anti-enumeration — quantified

1. **No existence oracle.** `venue.preview_promoter_code` returns `not_applicable` for *every* failure
   (§7.5) — unknown, inactive, expired, wrong org, out of scope are indistinguishable. Only an
   `active + eligible + in-scope` code returns a promoter display name.
   - **Accepted residual:** a successful probe confirms existence and reveals a display name. That is
     unavoidable — the buyer must be able to confirm *"Credit Jordy?"* before paying. The leak is bounded to
     the roster of the single event the prober is already looking at, which is largely public anyway (a
     promoter's whole job is telling people they are selling that event).
2. **Rate limits** (§7.10), fail-closed: **10/min** authenticated, **5/min** anonymous per derived principal.
3. **Burst audit:** ≥ 30 `not_applicable` results from one principal in 5 minutes writes
   `kernel.admin_audit('promoter_code.enumeration_suspected')` and disables code entry for that principal's
   session. `INFERENCE:` the threshold is a starting value, tunable via `catalog.platform_config`.
4. **No listing endpoint.** No RPC returns a set of codes to anyone who is not org staff or the owning
   promoter (§8.1). There is no public "all codes for this event".
5. **Codes are not secrets and are not treated as such.** They are broadcast on Instagram by design. The
   security model does not assume confidentiality; it assumes **scoped, low-value, auditable** binding.

### 9.5 Self-deal — detection, and the position

**Position: detect and flag; withhold payment until adjudicated; never block the sale.** `VERIFIED:` DA §1.7 —
*"flagged to the venue rather than silently blocked (audit edge case 10 — a promoter legitimately buying for
guests)"*; `VERIFIED:` dash §10.7 copy — *"A promoter buying for their own guests is normal."*

**Detectors** (evaluated in the resolver; each appends to `self_deal_reasons`):

| Code | Signal | Data source | Available in Phase 2 |
|---|---|---|---|
| `same_identity` | `order.buyer_id = promoter.identity_id` | `venue.order`, `venue.promoter` | **Yes** |
| `same_instrument` | the order's payment instrument fingerprint has previously been used by the promoter's identity | `kernel.payment_native.instrument_fingerprint` (§1.8) | **Yes** — this is the whole reason for §1.8 |
| `shared_device` | device/session fingerprint match | **C20 fingerprint object** | **No — Gate L.** Named so its absence is deliberate |

**Why flag-not-block is right, and why it has teeth anyway:** blocking would break the legitimate dominant
case (a promoter buying their own table for their own guests is *the* nightlife pattern), and a blocked sale
is a lost sale. The teeth are on the *money*, not the sale: a flagged attribution is **not payable until a
human releases it** (§6.3), and an unreviewed flag simply does not settle. The promoter can self-deal all
they like; they cannot get paid for it without a named person in the org saying so, with a reason code, in an
append-only record (§1.6).

**T4 — the second account.** A promoter with a second identity **and** a second payment instrument defeats
both available detectors. Stated plainly:

- `same_identity` fails (different uuid). `same_instrument` fails (different card). `shared_device` would
  catch it and is **Gate L (C20)**.
- **Phase-2 compensating controls, honestly weaker:** (a) settle-then-pay (§5.1) means the venue sees the
  ranked promoter list *before* money moves and an outlier is visible; (b) `platform_risk` holds
  `review_attribution_flag` from the admin plane; (c) `VERIFIED:` C20 (fingerprint + risk-signal ledger) is
  already ratified as the designed answer — this file requests **no new fraud substrate**, it requests that
  C20's arrival be the trigger to add the third detector.
- **This is a known, accepted, bounded gap.** It is bounded by the commission rate: the maximum a
  perfectly-executing self-dealer extracts is their commission percentage of purchases they actually paid for
  in full. It is a discount, not a theft, and it costs them the float.

### 9.6 What is deliberately not built

| Not built | Why |
|---|---|
| Velocity/behavioural scoring on codes | That is C20's risk-signal ledger. A second, bespoke scorer beside it is the "two answers to one question" failure. |
| Blocking self-purchases | Contradicts DA §1.7 and dash §10.7. |
| CAPTCHA on code entry | Adds friction to a checkout to protect a low-value binding. The rate limit is the proportionate control. |
| Code expiry-by-default | Codes are printed on flyers and live in Instagram bios; auto-expiry would silently kill live campaigns. Expiry is opt-in (`valid_until`). |

---

## 10. Scale and index design

### 10.1 The two shapes that must both work

| | 5 codes | 5,000+ codes per org |
|---|---|---|
| Issuance | one at a time, vanity, via §7.1 | bulk, generated, via §7.2 (capped 1,000/call) |
| Lookup | index seek | **identical index seek** — the whole point |
| Dashboard | a list | a paginated, filterable list; a "codes" **count** on the promoter row, never an inline list |
| Scope rows | 0 | up to 5,000 × (events in scope) — see §10.5 |

**The lookup does not care.** It is a single equality probe on a unique btree over `code_normalized`. At
5 × 10⁶ rows that index is ~3–4 levels deep and the probe is ~4 buffer reads, essentially all cached. There
is no version of this that needs a cache, a materialized view, or a separate lookup service — and this file
explicitly declines to add one.

### 10.2 Code uniqueness scope — **GLOBAL**, and the defence

**Decision: `UNIQUE (code_normalized)` across the entire platform. Eligibility is event-scoped (§1.2).**

The three candidates, and why the other two lose:

| Scope | The failure that kills it |
|---|---|
| **Per-event** `UNIQUE(event_id, code_normalized)` | A code is a *person's* handle, used across a season. Per-event uniqueness means "JORDY" is a different person's code at different shows, so a flyer, an Instagram bio, or a printed card is ambiguous — and the ambiguity resolves **silently**, crediting a stranger. It also makes the org-wide promoter (the common case) require one code row per event. |
| **Per-org** `UNIQUE(org_id, code_normalized)` | Superficially attractive: checkout always knows the event, hence the org. But it makes **cross-org mis-attribution silent and undetectable**. Jordy promotes for Club A. A buyer sees his code, buys a ticket at Club B (which also has a "JORDY"), and Club B's Jordy is credited. Nobody — not the buyer, not either Jordy, not either venue — ever learns this happened. It also makes "who owns JORDY?" a question with N answers, which is unanswerable in a support conversation and unanswerable in a dispute. |
| **Global** ✅ | One code, one owner, one answer, forever. A code typed at the wrong org's event fails E4 and returns `not_applicable` — a **visible** failure the buyer can act on, instead of a silent wrong credit. |

**Defence of the cost.** Global uniqueness means cross-org namespace contention. Quantified:

- 32-symbol alphabet, minimum length 4 ⇒ the reachable namespace at length ≤ 8 is Σ 32ⁿ (n=4..8) ≈ **1.14 ×
  10¹²**.
- 1,000 orgs × 5,000 codes = 5 × 10⁶ live codes ⇒ **occupancy ≈ 0.0004%**.
- Contention is therefore **not** a capacity problem. It is a *vanity* problem: two people both want "JORDY".
- Three mitigations already in the design: (a) `code_display` may be humanised while `code_normalized` is the
  key, (b) a promoter may hold **many** codes (owner requirement 1), so the loser takes `JORDY305` or
  `JORDYNYE`, (c) the issuing form runs a **live availability check** before enabling create (dash §10.4/§10.5)
  so contention is discovered at issue time, never at checkout time.

**And it is already a downstream commitment.** `VERIFIED:` dash §10.5, written against this deliverable, states
as binding: *"**Globally unique; eligibility is event-scoped.** The issuing form checks availability **live**
against the global namespace, and separately shows which events the code is eligible for."* This file
confirms rather than contradicts it. It is also symmetric with `promoter_link.slug`, which `VERIFIED:`
schema §3.17 and mig already make **globally unique** — one namespace discipline for both attribution
channels, not two.

### 10.3 Indexes on `venue.promoter_code`

| Index | Shape | Serves |
|---|---|---|
| PK | `(code_id)` | FK targets |
| **`UNIQUE (code_normalized)`** | btree | **the checkout probe** — the only index on the hot path |
| `(promoter_id, status)` | btree | promoter portal "my codes"; the dashboard's per-promoter code count |
| `(org_id, status, created_at DESC)` | btree | the dashboard's org code list, paginated |
| `(code_normalized text_pattern_ops)` | btree | the confusable/edit-distance-1 warning at issue time (§7.1) — **issue-time only, never checkout** |

`INFERENCE:` no `pg_trgm`. Edit-distance-1 candidates for a ≤16-char code can be generated client-side and
probed as an `IN` list against the unique index — 32 × 16 ≈ 512 probes worst case, at issue time only, at
human speed. A trigram index would be a whole extension for a form warning.

### 10.4 Indexes on `venue.attribution` — and why the denormalized columns exist

| Index | Serves |
|---|---|
| `UNIQUE (order_id)` | the money invariant (§4) + the P0 replay check |
| `(promoter_id, order_paid_at DESC, id DESC)` | **the promoter portal's keyset page** and the promoter's own-row RLS predicate |
| `(org_id, event_id, order_paid_at DESC)` | the venue dashboard's per-event attribution view |
| `(code_id) WHERE code_id IS NOT NULL` | "how did this code perform" — partial, so link-sourced rows cost nothing |
| `(link_id) WHERE link_id IS NOT NULL` | ratified index, now partial for the same reason |
| `(org_id) WHERE self_deal_flag AND NOT reviewed` | the self-deal queue (dash §10.7). **Partial** — the queue is a tiny fraction of the table and must never trigger a scan of it |

The `WHERE ... NOT reviewed` predicate cannot reference another table, so `INFERENCE:` the partial index is
`WHERE self_deal_flag` and the "unreviewed" filter is an anti-join against `attribution_review` — still
bounded, because `self_deal_flag` rows are the minority.

**Why `org_id` / `event_id` / `promoter_id` are denormalized onto the attribution row** (§1.5): without them,
every RLS policy and every dashboard filter is a 2–3 table join per row
(`attribution → link → promoter → org`), evaluated **inside an RLS predicate**, on the largest table the
promoter engine has. RLS predicates that join are the classic Postgres scale trap. `VERIFIED:` C9 requires
live-table role re-checks, which already costs a lookup; adding two more joins per row on top is the
difference between a 40 ms page and a 4 s page. The consistency cost is paid by triggers at insert, once.

### 10.5 `venue.promoter_code_scope` at scale

Worst case: 5,000 codes × a 200-event season, all explicitly scoped = 10⁶ rows. That is a small table, but the
shape matters:

- PK `(code_id, event_id)` serves the eligibility probe directly (it is an existence check on a known
  `code_id`).
- Secondary `(event_id)` for "which codes work tonight" on the dashboard.
- **The design pressure is to not need it.** E7 (unscoped = whole org) means the 5,000-code bulk program
  normally creates **zero** scope rows. Scope rows are for the exception (a code for one show), and the
  exception is small. A design where the common case needs 10⁶ rows would be the wrong design.

### 10.6 What does *not* scale, and is therefore not built

- A touch/click table (§1.10) — the only genuinely high-volume object in this domain, and it buys nothing the
  money needs.
- Per-code redemption counters (§1.1) — a hot mutable row per code on the checkout path.
- Real-time commission aggregates — the portal reads its own attributions with a keyset page and sums a
  bounded window; org-wide rollups are settlement's job, run once per period.

---

## 11. Dashboard and portal surfaces

### 11.1 Promoter portal — `NEW RN SURFACE` (checkout) + surface-platform decision (portal)

**`NEW RN SURFACE` — code entry at checkout.** One optional field in the RN checkout, labelled *"Promoter
code"*, above the pay button.

- Debounced call to `promoter-code-preview` (§7.10).
- Eligible → *"Jordy will be credited for this order."*
- Anything else → *"That code isn't valid for this event."* — **the same message for every failure** (§9.4),
  and it never blocks the pay button (§7.11).
- If a link brought the buyer in and a code is typed, the field shows the code's promoter — because the code
  will win (§2.4) and the buyer should see the truth before paying, not discover it in a receipt.
- Operator/consumer vocabulary: *"Promoter code"*. Never "attribution", "referral code", "affiliate", or any
  `venue.*` object name (dash §1 leakage rules apply to RN too).

**The promoter portal itself** — links, codes, attributed sales, commission, payout. `VERIFIED:` dash §10.1
requires it to exist and to be *separate* from the venue dashboard; `VERIFIED:` RN §53/§294 puts venue
management on web and out of the RN app.

`INFERENCE:` **recommend web, mobile-first responsive** — not an RN surface. Reasons: it is a money surface
with an audit table; shipping it inside the consumer app couples promoter releases to App Store review; and
promoters are not a subset of app users (an off-platform affiliate has no app). → **OWNER DECISION 7.**

Portal surfaces, whatever the platform: **My codes** (code, status, scope, sales) · **My links** ·
**My sales** (§8.5's projection, keyset) · **Commission** (accrued / held / paid, with the §6.4 rules —
`"—"` never `0`) · **Held** (*"Waiting on the venue to review"* — never the word "fraud", never the reason
detail).

### 11.2 Venue dashboard — `NEW DASHBOARD SURFACE`

Slots into dash §10; every item below answers a binding requirement already written there.

| Surface | Satisfies | Reads / writes |
|---|---|---|
| **Codes tab** on the promoter detail — code · normalized form · status · scope · window · attributed count | dash §10.5 | `venue.promoter_code` (+ scope); W §7.1/§7.3/§7.4 |
| **Issue code form** — live availability against the global namespace; **confusable acknowledgement**; scope picker; window picker | dash §10.5 | W §7.1; `confusable_with[]` from its result |
| **Bulk issue** — count, kind, scope, window; downloads the generated set through the audited export path | §7.2 | W §7.2 |
| **No reassignment affordance anywhere** — not a disabled button, not a menu item | dash §10.5 verbatim | enforced at §1.1 and §7.3 |
| **Attribution view** — dash §10.6's exact columns, plus `displaced promoter` where set | dash §10.6 | R §8.6 |
| **Self-deal queue** — Release / Deny with reason code; flagged rows never hidden; history preserved | dash §10.7, **resolves dash §22.4** | R `venue.attribution_review`; W §7.7 |
| **Settlement close dialog — held-commission warning**: *"N flagged commissions have not been reviewed. Closing now will not pay them; they will roll to the next settlement."* | §6.3's hold semantics; dash §14 says close is irreversible | R the §10.4 partial index |

**The confusable warning's copy must state the fact, not the risk:** *"`J0RDY` is the same code as `JORDY` —
they cannot both exist. This code is available."* / *"…is already taken."* Because under §1.3 that is
literally true, the warning is an explanation, not a caution.

### 11.3 Language

| Object | Operator word | Consumer word |
|---|---|---|
| `venue.promoter_code` | **Promoter code** | **Promoter code** |
| `venue.attribution` | **Attributed sale** | *(never shown)* |
| `attribution.self_deal_flag` | **Flagged for review** | **Waiting on the venue** |
| `attribution.method` | **Credited via** (Code / Link) | *(never shown)* |
| `attribution.touch_corroborated` | **Click matched** (yes/no) | *(never shown — §8.5)* |

`VERIFIED:` dash §1 already maps `venue.promoter_link` → **Promoter link** and reserves *"promoter code
(Agent C)"* → **Promoter code**. Forbidden in all copy, unchanged: kernel · rail · atom · SSCAS · cause-code ·
RLS · definer · attribution *(as a noun to a promoter)*.

---

## 12. pgTAP assertion list (described; **no SQL files written**)

Grouped by the invariant each group defends. `VERIFIED:` mig §-per-package requires staging verification
assertions; these are that list for `090`.

**A. Normalization and uniqueness (§1.3, §10.2)**
1. `normalize('JORDY')`, `normalize('jordy')`, `normalize('J0RDY')`, `normalize('J-0-R-D-Y ')` all equal.
2. `normalize` is `IMMUTABLE` (catalog check) — otherwise the generated column is illegal.
3. `normalize` output always matches the Crockford alphabet, over a fuzz corpus including emoji, RTL marks, and zero-width joiners.
4. Inserting `JORDY` then `J0RDY` **raises unique violation** — the confusable pair is one code.
5. The same normalized code in **two different orgs** raises unique violation (global scope proven, not assumed).
6. `code_normalized` cannot be written directly (generated column), including as `service_role`.
7. Length and alphabet CHECKs reject 3-char and 17-char inputs.

**B. Immutability and no-reassignment (§1.1, §3.4)**
8. UPDATE of `promoter_id` on a code raises — as `postgres`, as `service_role`, and via every RPC in §7.
9. UPDATE of `code_display` / `code_normalized` / `kind` / `org_id` raises.
10. UPDATE of `status` / `valid_from` / `valid_until` succeeds for an authorized RPC.
11. UPDATE of any `venue.attribution` column raises (AO guard) for every role including `platform_admin`.
12. DELETE on `promoter_code`, `promoter_code_scope`, `attribution`, `attribution_review` raises for all 15 roles (GP-2).
13. Order candidate columns are mutable while `pending` and raise once `status <> 'pending'` (M4).

**C. Eligibility (§1.2)** — one assertion per row E1–E7, plus:
14. A code scoped to event X is ineligible for event Y in the same org.
15. A code scoped to an event in **another org** cannot be created (trigger raises).
16. A single-event promoter's code is ineligible for a second event even with a scope row for it (E5 precedes E6).
17. Boundary: `valid_from = now()` eligible; `valid_until = now()` ineligible (half-open interval, asserted explicitly so the boundary is not folklore).

**D. Precedence (§2.3)** — **eleven assertions, one per P0–P10**, each checking `promoter_id`, `method`, `touch_corroborated`, and `resolution_reason` on the produced row (or its absence). Plus:
28. M1 (two codes) and M2 (two links) raise `invalid_input`, and the order's existing candidate is unchanged.
29. M3 (rebind while pending) leaves exactly one candidate and writes one audit row.
30. P0: finalizing twice produces exactly one attribution and the second call returns the first row.
31. Exhaustiveness harness: for the full cross-product of {code ∈ E,X,∅} × {link ∈ E,X,∅} × {same,different promoter}, **exactly one** P-row fires — asserted by instrumenting `resolution_reason`, so totality is a test, not a claim.

**E. The money invariant (§4)**
32. Two `promoter_commission` settlement lines for one attribution — **in the same settlement** — raise.
33. Two `promoter_commission` settlement lines for one attribution — **in two different settlements** — raise. *(This is the assertion that would fail today; it is the reason constraint (2) exists.)*
34. Two payouts with `cause='promoter_commission'` and the same `cause_ref` raise on `idempotency_key`.
35. Two attributions for one `order_id` raise.
36. Concurrency: two sessions finalizing the same order — exactly one attribution, no deadlock, the loser returns the winner's row.
37. Concurrency: two sessions closing the same settlement — exactly one commission line and one payout.
38. The payout `idempotency_key` produced by the settlement path matches the §4.2 expression **byte for byte**.

**F. Freeze and state machine (§3)**
39. Attribution row does **not** exist while the order is `pending`, even with both candidates set. *(Asserts the §14.4 correction is actually implemented.)*
40. Attribution row exists after `finalize_primary_order` and `order_paid_at` equals the order's paid timestamp.
41. Deactivating the code after freeze changes nothing about the recorded attribution.
42. Changing `promoter.commission_bps` after freeze changes neither `credited_amount_minor` nor `terms_version` on the frozen row.
43. §3.5 race, both orderings: deactivate-then-commit ⇒ no attribution; commit-then-deactivate ⇒ attribution stands.

**G. Refund / cancel / resale (§5)**
44. Fully refunded attributed order ⇒ **no** `promoter_commission` line at close.
45. Partially refunded ⇒ one line, amount = recomputed basis, and the attribution row is byte-identical to before the refund.
46. Cancelled event ⇒ no commission for any attributed order in it.
47. P2P transfer of an issued atom ⇒ the attribution and the commission are unchanged.
48. A `market.market_sale` of an attributed ticket produces **no** attribution row and **no** commission payout (§5.6 asserted, not assumed).

**H. RLS isolation (§8)** — the highest-value group.
49. Promoter A cannot SELECT promoter B's attribution — direct table, and through every read RPC.
50. Promoter A cannot SELECT promoter B's codes.
51. A **code-sourced** attribution (`link_id IS NULL`) **is** visible to its own promoter. *(The regression the §8.3 correction prevents; without it the promoter sees none of their code earnings.)*
52. `venue.get_my_promoter_summary` returns zero rows for a caller with no promoter row, and cannot be widened by passing another org's id.
53. The promoter's payout read returns only `cause='promoter_commission'` rows whose `cause_ref` is one of their own attributions — never an org settlement payout (footnote 15, asserted).
54. No read RPC on this feature returns buyer name, buyer email, buyer id, or `instrument_fingerprint` — asserted by column-list comparison, not by inspection.
55. `venue_door` and `org_member` are denied on every object in this feature.
56. A promoter cannot EXECUTE `create_promoter_code`, `set_promoter_code_status`, or `review_attribution_flag`.
57. `venue.resolve_order_attribution` has no EXECUTE grant to `anon` or `authenticated`.
58. `displaced_promoter_id` and `touch_corroborated` are absent from the promoter's own projection (§8.5).

**I. Fraud controls (§9)**
59. `self_deal_flag` set when `buyer_id = promoter.identity_id`, with reason `same_identity`.
60. `self_deal_flag` set on instrument-fingerprint match, with reason `same_instrument`.
61. A flagged attribution produces **no** settlement line while unreviewed (hold, §6.3).
62. `release` ⇒ the next close pays it; `deny` ⇒ no line, ever, and the attribution stays visible.
63. `review_attribution_flag` after the commission line exists raises `attribution_settled`.
64. `attribution_review` supersession: `seq` 2 overrides `seq` 1; both rows survive.
65. Generated codes meet the 8-symbol floor; bulk generation of 1,000 yields 1,000 distinct codes.
66. `preview_promoter_code` returns `not_applicable` — **identical payload** — for unknown, inactive, expired, out-of-org, and out-of-scope inputs. *(Asserted by payload equality, so an oracle cannot creep back in via a field.)*

**J. Never-fail-the-sale (§7.11)**
67. Finalize succeeds and issues atoms when the bound code was deactivated mid-flight.
68. Finalize succeeds when the candidate code row was deleted-by-restrict-failure / is unresolvable.
69. A deliberately-faulted resolver (injected error) still commits the order, the payment link, and the atoms, and writes `attribution.resolver_error` to the audit.

**K. Scale (§10)**
70. `EXPLAIN` on the checkout code lookup shows an **Index Scan** on `UNIQUE(code_normalized)` with 5 × 10⁶ seeded rows — asserted as a plan-shape test, not a timing test.
71. The self-deal queue query uses the partial index and does not scan `venue.attribution`.
72. The promoter portal page query is a keyset seek, and page 500 costs the same as page 1.

---

## 13. Open questions and owner decisions

| # | Question | This file's default | Why it is the owner's call |
|---|---|---|---|
| **1** | **Code beats link** when they name different promoters (§2.4). | **Code wins**, link recorded in `displaced_promoter_id`. | It decides whose commission it is. The alternative (link wins, code is a fallback) is coherent and is what a strict last-touch shop would do — but it makes codes near-useless and contradicts *"do not depend on links"*. Reversing it later is a **breaking change** to already-frozen attributions. |
| **2** | **Does the original promoter earn on a marketplace resale?** (§5.6) | **No.** | Commercial. A "lifetime attribution" model is a real product some competitors sell. This file's position is that it rewards scalping the promoter's own allocation and is structurally foreign to the resale payee set — but it is additive later (a `market_sale`-grain attribution with its own cause). |
| **3** | **Who bears a post-settlement chargeback on a commissioned sale?** (§5.3) | **The org**, via a negative settlement line. | The alternative — the promoter bears it — is **not buildable in Phase 2**: it requires C29 reserve + C30 liability, both Gate-M. Choosing "promoter bears it" is therefore a decision to **gate the promoter program on Gate M**, which is a schedule decision. |
| **4** | **Commission basis: face subtotal, or gross including fees?** (§6.1) | **Face subtotal.** | Pure commercial. It changes every promoter's effective rate; deciding it after codes are live means renegotiating terms. |
| **5** | **Do codes need redemption caps / expiry-by-default?** (§1.1) | **No cap, opt-in expiry.** | If "Jordy has 60 tickets" must be enforced by the *code*, this file's answer changes and a hot counter enters the checkout path. The platform's existing answer is `inventory_batch.release_kind='promoter_hold'`. |
| **6** | **What is the remedy for a genuinely wrong attribution?** (§3.4) | **None on-ledger** — the freeze is absolute; remedy is a commercial settlement off-ledger. | Support will ask for an override within the first month. The answer must be decided *before* someone builds one, because an override that mutates an AO ledger destroys every guarantee in §4. |
| **7** | **Promoter portal: web or in the RN app?** (§11.1) | **Web, mobile-first responsive.** | Roadmap and headcount. It also determines whether an off-platform affiliate (no app account) can be served at all. |
| **8** | **Sub-promoters / sub-codes with a split commission?** (§1.10) | **Not in Phase 2.** | DA §7.2 mentions promoter sub-links "where allowed". A split is a money change (two payees per attribution), which breaks the one-payee-per-attribution shape in §4.3 step 2 and would need its own design. |
| **9** | **May a promoter *request* a vanity code?** (§8.2) | Out of scope; it is an inbox flow, not a grant. | Only flagged so nobody implements it as an RLS permission. |
| **10** | **Enumeration thresholds** (§9.4 item 3): 30 failures / 5 min. | Starting value, tunable via `catalog.platform_config`. | Needs a real traffic baseline; a wrong value locks out legitimate buyers who mistype. |

---

## 14. Contradictions with ratified / binding inputs — **reported, not resolved**

Per the boundary: these are raised for their owners. This file designs *around* them and says so; it does not
edit a frozen constitution and does not quietly pick a side.

### 14.1 Package numbering is inconsistent in three places (documentation defect)

`VERIFIED:` **mig** at `11ea2eb` calls the promoter engine `086` in its §1 map and §3 rollout table, `087` in
its §-detail heading and §2 DAG, and `086_*` again in that section's own rollback paragraph. `VERIFIED:`
**dash** §0.1 cites the Phase-2 range as `071–089`, while **mig** §1's title says `073–088`. → **Owner: the
renumber author.** This file uses `076–091` / promoter = `090` per §0.3 and is agnostic to the fix.

### 14.2 O-2 says a promoter is not an administrator; the physical model makes them venue staff

`VERIFIED:` RLS §1.1 row 11 and §2.1 express "promoter" as `venue.staff_role.role = 'venue_promoter'`, tested
by `has_venue_role(venue_id, [venue_promoter])` — i.e. **a promoter is a row in the venue's staff table.**
`VERIFIED:` O-2 states promoters are *"attribution/distribution identities unless explicitly invited into an
org with an administrative role"*, and DA §8.2 says a promoter is *"**Not an account** … a relationship +
links"*, housed in `venue.promoters`/`promoter_links`.

Two problems, both structural:

1. **Wrong table.** A promoter's capability should derive from an **active `venue.promoter` row**, not from a
   staff grant. As written, onboarding a promoter requires granting them venue staff — the exact
   over-provisioning C36 and O-2 both exist to prevent.
2. **O-2's list has no promoter label at all** — it has `promoter_manager` (the internal counterpart) and no
   external-seller role, which is *consistent* with "a promoter is not staff" and *inconsistent* with the
   current four-label venue enum.

**How this file designs around it:** every promoter-facing read path here (§8.5) derives authority from
**`venue.promoter.identity_id = auth.uid()` on a live row**, never from `has_venue_role([venue_promoter])`.
That is correct under either resolution and does not depend on the enum. → **Owner: the C36 plane-membership
agent** (already assigned). Also raised as dash §22.2's open ruling.

### 14.3 `venue.promoter` cannot express the terms DA §1.7 ratifies

`VERIFIED:` DA §1.7 — commission terms are *"flat-per-ticket or %"* and the promoter carries
*"`tier ∈ {professional_invited, public_ambassador}`"*. `VERIFIED:` schema §3.17 models only `commission_bps`
and has no `tier` and no `party_kind` (though DA §1.7 also ratifies the `promoter | affiliate` discriminator).
Flat-per-head is the **dominant** nightlife term, so the physical model cannot express the common case.
→ §1.4 proposes the additive columns; **owner: the schema-spec author**, to confirm they belong in `090`
rather than being a correction to §3.17's own text.

### 14.4 **Attribution is specified to be written at order *creation*, which contradicts "written when paid"**

The sharpest one.

- `VERIFIED:` RPC §6.1 (`create_primary_checkout`) — *"**Writes:** … optionally `venue.attribution` (in-txn if
  `source='promoter_link'`, AO)"*.
- `VERIFIED:` RLS §9.17 — *"attribution recorded in-txn by `create_order` (AO)"*.
- `VERIFIED:` DA §1.7 — attribution is *"Written when an attributed order is **paid**"*.
- `VERIFIED:` CDM §1.3 — *"attribution = an append-only record of a **sale** credited to a link"*.

An append-only ledger row written for a **pending** order is a row recording a sale that has not happened and
may never happen. It also makes the owner's *"immutable once economically committed"* requirement
unsatisfiable, because the row would be frozen **before** the economic commitment.

**Resolution taken here (declared, not silent):** §3.2 freezes at **order-paid**, inside
`venue.finalize_primary_order`, and the pre-pay candidate lives in the mutable `venue.order` columns of §1.7.
→ **Owner: the RPC-contracts author and the RLS author** — both documents need the write moved from
`create_order` to `finalize_primary_order`. This is `SPEC CORRECTION` to RPC §6.1 and RLS §9.17.

### 14.5 `AttributionRecorded`'s idempotency key assumes a link exists

`VERIFIED:` DA §6.1 event 31 keys `AttributionRecorded` on `order_id + promoter_link_id`. A code-sourced
attribution has no link, so the key is null-bearing and the consumer's dedup breaks. → the key must widen to
**`order_id`** (which is already unique per §4.2 constraint (1), so it is strictly stronger). `SPEC
CORRECTION` to DA §6.1 — **owner: the domain-architecture author.**

### 14.6 `check_rate_limit` cannot rate-limit an unauthenticated principal

`VERIFIED:` `public.check_rate_limit(p_user_id **uuid**, …)` (`supabase/migrations/005_rate_limits.sql`, and
`GRANT EXECUTE … TO service_role` only). Pre-login code preview (§7.10) has no user uuid. §7.10 derives one
(`uuidv5` over IP + UA hash), which is an **adaptation of a frozen Phase-0 function's contract**, not a change
to it. Flagged so it is a reviewed decision rather than a clever workaround. → **owner: the edge-spec author**
(also affects any future anonymous-callable edge function).

### 14.7 `close_settlement` is specified in a package that precedes the table it reads

`VERIFIED:` RPC §10.2 says `kernel.close_settlement` **reads `venue.attribution`** and writes payouts with
cause `promoter_commission`. `VERIFIED:` mig places settlement at `086` and the promoter engine (which
*creates* `venue.attribution`) at `090`. A function defined in `086` cannot reference a table created in
`090`; the migration would fail to apply, or the function would be created with a dangling reference.

**Resolution taken here:** `086` defines `close_settlement` **promoter-agnostic**, and `090` issues a
`CREATE OR REPLACE` adding the commission leg. Consequently the §4.2 constraint (2) partial unique index also
belongs in **`090`** — it must land with the writer that first emits the cause, not before it. → **owner: the
migration-plan author.** `SPEC CORRECTION`.

### 14.8 Non-contradictions, checked and cleared

Recorded so a later reviewer does not re-litigate them:

- **C26** — not contradicted; §4.4 shows the commission key is C26's shape with a functionally-determined
  subject.
- **C28 / SSCAS** — not contradicted; §7.9 shows no new locked class and no new member, so the closed fifteen
  and the lock order stand.
- **D3 cause registry** — **no new cause code is proposed.** Everything uses `promoter_commission`,
  `refund_void`, `chargeback`, `settlement` — all already in D3.
- **GP-1 / GP-2** — every write here is RPC-only; DELETE is denied everywhere.
- **OBS-1** — no column added to `public.payments`; the fingerprint goes on `kernel.payment_native` (§1.8).
- **C29/C30/C31 Gate-M** — no reserve, clawback, receivable, or double-entry object is proposed; §5.3 states
  the boundary and gives the interim.
- **dash §10.5 / §10.6 / §10.7 / §22.4** — all four binding downstream commitments are satisfied
  (§1.3, §1.5, §1.6, §2.5, §7.7, §11.2), none contradicted.

---

## 15. Classification index

| Element | Classification | Package | Why that package |
|---|---|---|---|
| `venue.promoter_code` | `ADDITIVE SCHEMA CHANGE` | **090** | the promoter engine; inert until the promoter phase; clean rollback while empty |
| `venue.promoter_code_scope` | `ADDITIVE SCHEMA CHANGE` | **090** | child of the above |
| `venue.normalize_promoter_code()` | `ADDITIVE SCHEMA CHANGE` | **090** | the generated column depends on it; must exist in the same package |
| `venue.attribution_review` | `ADDITIVE SCHEMA CHANGE` | **090** | resolves dash §22.4; references `venue.attribution` |
| `venue.promoter` +`tier`/`commission_kind`/`commission_flat_minor`/`party_kind` | `ADDITIVE SCHEMA CHANGE` (+ `SPEC CORRECTION` to schema §3.17) | **090** | same package creates the table |
| `venue.attribution` +11 columns, `link_id` → nullable | `ADDITIVE SCHEMA CHANGE` (+ `SPEC CORRECTION`) | **090** | same package creates the table |
| `venue.order` + 2 candidate columns + freeze trigger | `ADDITIVE SCHEMA CHANGE` | **090** | `ALTER` on `081`'s table; kept in 090 so the feature reverts as a unit |
| `kernel.payment_native.instrument_fingerprint` | `ADDITIVE SCHEMA CHANGE` | **090** | `ALTER` on `084`'s table; only the self-deal detector reads it |
| `settlement_line (cause_ref) WHERE cause='promoter_commission'` | `ADDITIVE SCHEMA CHANGE` | **090** | must land with the writer that emits the cause — see §14.7 |
| Attribution / code indexes (§10.3, §10.4, §10.5) | `ADDITIVE SCHEMA CHANGE` | **090** | with their tables |
| Attribution written at **paid**, not at order-create | **`SPEC CORRECTION`** (RPC §6.1, RLS §9.17) | **090** | §14.4 |
| `close_settlement` split promoter-agnostic / `CREATE OR REPLACE` | **`SPEC CORRECTION`** (mig, RPC §10.2) | **086** + **090** | §14.7 |
| `AttributionRecorded` key → `order_id` | **`SPEC CORRECTION`** (DA §6.1 event 31) | doc | §14.5 |
| Promoter authority from `venue.promoter`, not `has_venue_role` | **`SPEC CORRECTION`** (RLS §1.1/§9.17) | **090** | §14.2 |
| `venue.create_promoter_code` | **`NEW RPC`** | **090** | |
| `venue.create_promoter_codes_bulk` | **`NEW RPC`** | **090** | the 5,000-code case |
| `venue.set_promoter_code_status` | **`NEW RPC`** | **090** | |
| `venue.set_promoter_code_scope` / `venue.set_promoter_code_window` | **`NEW RPC`** | **090** | |
| `venue.preview_promoter_code` | **`NEW RPC`** (read) | **090** | |
| `venue.bind_order_attribution` | **`NEW RPC`** | **090** | writes `081`'s table; ships with the feature |
| `venue.resolve_order_attribution` | **`NEW RPC`** (internal, no client grant) | **090** | the precedence engine |
| `venue.review_attribution_flag` | **`NEW RPC`** | **090** | satisfies dash Δ4 / §21.4 |
| `venue.get_my_promoter_summary` | **`NEW RPC`** (read) | **090** | implements RLS §7.9 footnote 15 |
| `venue.list_my_attributions` | **`NEW RPC`** (read) | **090** | promoter portal |
| `venue.list_promoter_attributions` | **`NEW RPC`** (read) | **090** | dash §10.6 |
| `promoter-code-preview` | **`NEW EDGE FUNCTION`** | **090** (deploy) | `check_rate_limit` is service_role-only — §7.10, §14.6 |
| `primary-checkout` carries `code` + `link_slug` | edge change to an existing spec'd function (`SPEC CORRECTION` to edge §3.1) | **090** (deploy) | the code must reach `create_primary_checkout` |
| Checkout code-entry field | **`NEW RN SURFACE`** | **090** | §11.1 |
| Promoter portal | **`NEW RN SURFACE`** *or* **`NEW DASHBOARD SURFACE`** — **OWNER DECISION 7** | **090** | §11.1 |
| Codes tab · issue form · bulk issue · attribution view · self-deal queue · close-dialog held warning | **`NEW DASHBOARD SURFACE`** | **090** | §11.2 |
| Rate limiting via `public.check_rate_limit` | **`NO SCHEMA CHANGE`** | — | existing Phase-0 primitive (migration `005`) |
| Cause codes used (`promoter_commission`, `refund_void`, `chargeback`, `settlement`) | **`NO SCHEMA CHANGE`** | — | all already in the D3 registry |
| Payout path, payout idempotency, settlement mechanics | **`NO SCHEMA CHANGE`** | — | reuses `kernel.payout` and `close_settlement` unchanged |
| SSCAS membership and the C28 lock order | **`NO SCHEMA CHANGE`** | — | §7.9 — no new locked class, no amendment |

---

*End of Phase 2 Promoter / Referral Codes Spec. Design-only. Precedence is server-authoritative, total, and
tie-free (§2). No double commission is enforced by three uniqueness constraints, not by policy (§4).
Attribution freezes at order-paid and is append-only thereafter (§3). Clawback is Gate-M and the Phase-2
interim is settle-then-pay (§5). Code uniqueness is global with event-scoped eligibility (§10.2). The original
promoter does not earn on a resale (§5.6, owner decision 2). Seven contradictions with binding inputs are
reported in §14 and none is silently resolved.*
