# Phase 2 — Venue CRM & Attendee Export Spec

**Status:** BUILD-READY DESIGN SPEC. **Design-only — NO SQL, NO migrations, NO implementation code.**
Illustrative fragments inside this document are prose aids, never files to copy.

**Scope.** Venues need useful attendee and customer data for the events they operate: a roster, check-in
state, order information, ticket type, promoter attribution, permitted contact information, a CSV export,
filtering, org-level CRM views where permitted, and the role, audit, privacy, retention and abuse controls
that make all of that safe to ship. This document specifies that surface end to end.

**The governing posture, stated once and applied everywhere below:**

> **An export is exfiltration.** Every other control in this system is reversible — a grant is revoked, a
> policy is tightened, a row is corrected. A CSV on a laptop is none of those things. Therefore the controls
> that matter are the ones that run **before the bytes leave**: who may ask, how often, over what scope, with
> which columns, and an audit row that outlives the file. Everything after the download is a promise, not a
> control, and this document is careful never to describe a promise as a control.

**Binding inputs (authority order).**

1. `docs/architecture/PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §9 — **X-1 … X-9 are hard constraints handed to
   this document, not advice.** Read at `design/feature-demographics@5a339fe`. Reproduced verbatim in §2.4
   and satisfied field-by-field in §3 and structurally in §10.
2. `docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md` — the canonical role labels, the 20 principals, the
   predicate helpers, and the H2/H3 audience-vs-money export split. Read at
   `design/o2-o4-role-model@0562cec`.
3. `docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md` (CDM) — §4 identity/erasure, §5 storage categories,
   §8 multi-tenancy (**"an org/venue reads … only the customers who transacted with it (its CRM slice)"**),
   §10 evolution rules, §11 naming constitution.
4. `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md` (DA) — §7.6 permission matrix incl. the
   "View buyer PII" row, §7.2 role catalog, §8.7 erasure/merge (C34/C38).
5. `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` — **C34** (provable erasure,
   RATIFIED-MODELED-ONLY **GATE-L**, not built in Phase 2), **C38** (identity-merge grant reconciliation,
   GATE-L), **C40** (`validation_callback` egress restricted to a static platform-controlled allowlist,
   GATE-L), C35, C36, C39, C46.
6. `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` — §9.1–§9.4 (attendee list), **§9.6 (CRM
   export, already ratified as binding on this agent)**, §16.6, §17 (activity), §21 Δ3, §22.6.
7. `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md`, `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §0 globals,
   `PHASE_2_EDGE_FUNCTION_SPEC.md` §2 placement discipline + §7 cross-cutting requirements,
   `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`, `PHASE_2_SUPABASE_MIGRATION_PLAN.md`,
   `PHASE_2_SPEC_FOUNDATION.md`.
8. Live Phase-0 precedent in `supabase/migrations/`: **042** (`get_my_profile()` definer own-row read),
   **052/062/068** (column-grant restriction on `public.profiles`), **005/021** (fail-closed
   `check_rate_limit`), **073** (storage bucket size + MIME constraints), **019/020** (anonymized-sentinel
   account deletion), **014/032/034** (`pg_cron` + `pg_net` → edge function).

**Evidence labelling.** `VERIFIED:` = read directly from this repository in this session, at
`phase2/consolidation@11ea2eb` unless another ref is named. `INFERENCE:` = a design conclusion drawn by this
document.

**What this document does not decide.** Money authority (OD-3/OD-4/OD-5 of the role-model spec), the door
state machine, the storage shape of the self-deal decision, migration package renumbering (packages are named
by **letter and number**, §11.1, so the spec survives a renumber), and any legal determination — where a
choice turns on one it is presented as options and flagged for counsel (§13).

---

## 0. The precedent this design is built on (VERIFIED)

`VERIFIED:` migration 062's own header states the structural fact that determines the whole contact design:

> *"Column privileges in Postgres are per-role, not per-row, so a column granted to `authenticated` is
> readable on ANY row, not just the caller's own."*

`VERIFIED:` 068 therefore reduced `authenticated`'s SELECT on `public.profiles` to eight public-safe columns
— `id, display_name, avatar_url, avatar_path, bio, created_at, is_verified_seller,
stripe_onboarding_complete` — explicitly removing `full_name`, `phone_number`, `stripe_connect_id` and
`wallet_balance`, whose exposure it names as *"BOLA / API3 broken object-property-level authorization."*
`VERIFIED:` 042 introduced `public.get_my_profile()` — `SECURITY DEFINER`, `search_path` pinned, **zero
parameters**, `WHERE p.id = auth.uid()` — as the only way an owner reads their own sensitive fields.

`INFERENCE:` this pattern is the ratified answer to "how does PII stay off a broad role", and this document
applies it at full strength to every object it introduces: **the new tables carry zero column grants to `anon`
and `authenticated` — not a reduced set, an empty set — and every read is a scope-checked `SECURITY DEFINER`
RPC.** There is no "public-safe subset" of a customer email.

`VERIFIED:` the direction of travel in the live repo confirms it: commit `bbbba9c` ("read own profile via
`get_my_profile()`; **drop `full_name` from bid history**") removed a name column from a staff-adjacent read
rather than gate it.

`VERIFIED:` `supabase/migrations/` ends at `075`; `grep -rn "staff_role\|org_member\|platform_role"` returns
nothing. **None of the Phase-2 objects this document touches exists yet**, so every element below is a design
commitment, not a change to applied state. No production database was mutated in producing this document.

---

## 1. Roster data model

### 1.1 The modelling question, stated exactly

One buyer purchases six tickets and transfers five to friends. Who is on the roster? Whose email may the
venue contact?

Three candidate populations give materially different answers:

| Candidate | Definition | What it gets wrong |
|---|---|---|
| **purchaser set** | `DISTINCT venue.order.buyer_id` for the session | Six people are coming; the roster names one. A door list built from it cannot admit five of them. Every transfer and resale makes it staler. |
| **holder set** | `DISTINCT kernel.tickets.current_owner_id`, non-voided, for the session | Correct about who is coming. Says nothing about who paid, which the venue needs for refunds and service. |
| **admitted set** | identities holding at the moment of an `admitted` `venue.scan` | Empty until 11 p.m. Not a roster; a reconciliation. |

`INFERENCE:` the mistake is choosing one. The venue has two genuine questions — *who is coming* and *who
paid* — and they are different questions about the same ticket. A model that answers only one is wrong about
half the product.

### 1.2 The decision

> **CANONICAL: `session_roster` — one row per non-voided `kernel.tickets` atom for a
> `catalog.event_session`, carrying both the atom's current holder (`kernel.tickets.current_owner_id`) and
> the atom's originating purchaser (`venue.order.buyer_id`, reached through the issuance cause), evaluated
> live at a named instant `as_of`.**
>
> The atom is the grain because the atom is the only object that has exactly one holder and exactly one
> purchaser. Every roster surface in this document is a projection of `session_roster`, and there are
> exactly two:
>
> - **Holder view (DEFAULT).** One row per distinct `current_owner_id`, aggregating the atoms they hold.
>   **This is "who is coming" and it is what the Attendees tab shows.**
> - **Purchaser view.** One row per `venue.order`. **This is "who paid" and it is a money surface.**

**The purchaser-vs-holder rule, in one sentence:**

> **The roster is holder-keyed; the order surface is purchaser-keyed; and contactability follows neither —
> it follows consent (§5).**

### 1.3 Non-contradiction with the demographics spec (required, and provable)

The demographics spec chose `holder_mix` as its canonical population:

> *"the distinct identities that hold custody of at least one non-voided ticket for a given
> `catalog.event_session`, evaluated as of a named snapshot instant `as_of` … `DISTINCT
> kernel.tickets.current_owner_id` over the rows where `event_session_id = :session AND state <> 'voided'`."*

**Proof of identity of populations.** The holder view is defined as `DISTINCT current_owner_id` over
`kernel.tickets WHERE event_session_id = :session AND state <> 'voided'` at `as_of`. That is the same set
expression, over the same table, with the same filter, at the same kind of instant. Therefore:

> **`COUNT(holder view rows) ≡ holder_mix.holders_total`, always, for the same `(session, as_of)`.**

`INFERENCE:` this is worth more than tidiness. The demographics card renders *"Based on N of M ticket
holders"*, and `M` is now the same number the operator counts in the list above the card. Had the roster been
purchaser-keyed, the card would sit under a list whose length disagreed with its own denominator, and the
first operator to notice would conclude one of them was broken. **Assertion 3 of §12 pins this equality as a
test.**

The two rejected demographics semantics keep their reserved status here unchanged: `purchaser_mix` is **NOT
BUILT** and this document creates no demographic aggregate of any kind; `admitted_mix` is **NOT BUILT**. The
roster's `checked_in` column (§3.2 field 8) is a per-holder operational fact and **is never crossed with any
demographic axis** — there is no such axis to cross it with (§10).

### 1.4 The join path

Read only. The builder is a `SECURITY DEFINER` function; none of these tables is client-readable on this path.

```text
catalog.event_session (:session_id)          -- the scope anchor, and the admission grain
  └─ kernel.tickets                          -- WHERE event_session_id = :session AND state <> 'voided'
       │                                     --   AND org_id = :job_org_id   <-- XO-1a, MANDATORY AT EVERY
       │                                     --   GRAIN (§4.1). Not an optimisation, not an org-grain
       │                                     --   special case: catalog.venue.org_id is MUTABLE, so the
       │                                     --   traversal alone reaches a prior operator's sessions.
       ├─ current_owner_id  → auth.users     -- THE HOLDER (the roster key)
       ├─ ticket_type_id    → venue.ticket_type          -- ticket type name
       ├─ org_id            → kernel.organization        -- the tenant; carried on the atom itself
       ├─ kernel.ticket_ownership_log (head) -- acquisition cause → `acquired_via` (§3.2 field 7)
       │                                     --   counterparty identity is NEVER read out (§3.3)
       ├─ kernel.ticket_ownership_log (issue entry, cause ∈ issue|primary_sale|door_sale|comp)
       │    └─ cause_ref → venue.order_item → venue.order
       │                                     ├─ buyer_id → auth.users   -- THE PURCHASER
       │                                     ├─ status, total_minor, source
       │                                     └─ venue.attribution (UNIQUE(order_id))
       │                                          └─ promoter_link → promoter   -- promoter name / code
       └─ venue.scan          -- WHERE event_session_id = :session, latest per atom → checked_in
  └─ public.profiles (display_name only, for holder and purchaser)
  └─ kernel.org_contact_consent (identity_id, org_id = :job_org_id)  -- the email gate (§5); the JOB's org
  └─ kernel.identity_contact_pref (identity_id)         -- the master kill switch (§5)
  └─ kernel.org_customer_key (org_id = :job_org_id)     -- the pseudonym key; the JOB's org (§4.3)
```

**Three properties of this path that are load-bearing and easy to lose:**

1. **`kernel.tickets.org_id` is on the atom itself — and must actually be compared.** `VERIFIED:` schema
   §1.5 — `org_id uuid not null FK→kernel.organization(org_id)`. The tenant of a roster row is therefore
   established without traversing session → event → venue → org, which means the tenancy check is a direct
   predicate rather than a four-hop join whose middle can be tampered with. **XO-1a (§4.1) makes that
   predicate mandatory at every grain**, and the two org-parameterized lookups above — the consent `EXISTS`
   and the pseudonym key — bind to `:job_org_id`, the org frozen on the job row. `INFERENCE:` the original
   text presented the column's existence as the defence and invoked the comparison only for the org-grain
   aggregate; a column that exists and is never compared defends nothing.
2. **The purchaser is reached through the ownership log's issuance entry, not through a column on the atom.**
   There is no `purchased_by` column on `kernel.tickets` and this document does not ask for one. `INFERENCE:`
   adding one would duplicate a fact whose home is the ledger, violating CDM §10.6 ("one fact, one home"), and
   it would be wrong the moment an atom's issuance is compensated.
3. **`venue.attribution` is `UNIQUE(order_id)`** (`VERIFIED:` schema §3.17), so promoter attribution is a
   property of the **order**, i.e. of the purchase, not of the holder. A transferee's row carries the promoter
   who drove the *original sale*, and the file says so by putting `promoter_*` on the purchase facts, not the
   holder facts. This is stated because the alternative reading — "this promoter drove this attendee" — is
   false for every transferred ticket and would corrupt commission analysis if anyone built on it.

### 1.5 Guest-list and comp rows

Guest-list entries (`venue.guest_entry`) that never became a ticket atom are **not** part of `session_roster`
and are not exportable through this surface. `INFERENCE:` a guest-list name is a string the venue typed into
its own system; it is not platform-held customer data, it has no consent record, no identity, and no
`customer_ref`. Mixing it into a CRM export would produce a file whose rows have two incompatible
provenances and whose consent story is only true for half of them. The guest list stays on its own surface
(dashboard §11), where it already is.

A **comped ticket that was issued as an atom** (cause `comp`) *is* on the roster — it is a real admission
right with a real holder — with `acquired_via = 'comp'` and **no contact permission** (a comp is not a
transaction the recipient entered into; see §5.4).

---

## 2. Field catalogue

### 2.1 Column classes

Four classes, and a role holds a class, never an individual column. `INFERENCE:` per-column role grants are
how a permission matrix becomes unreviewable; four named bundles are checkable at a glance and map 1:1 to the
role-model spec's H2/H3 split.

| Class | Contents | Rationale |
|---|---|---|
| **IDENT** | pseudonymous customer reference, display name, holder/purchaser flags, counts | The minimum that makes a row a row. |
| **OPS** | ticket type, acquisition, check-in state, source, promoter attribution | Operating the room. Not money, not contact. |
| **CONTACT** | email (consent-gated) | The real payload and the real risk (§5). |
| **MONEY** | order ref, order status, totals, unit price, refund state | The H3 line. |

### 2.2 The catalogue

`as_of` is stamped on every export and every row set (§6.3). "Grain" says which projection the field appears
in.

| # | Field | Class | Grain | Source | Authorization |
|---|---|---|---|---|---|
| 1 | `customer_ref` | IDENT | holder | `HMAC(org_customer_key, identity_id)` — §4.3 | every role that may read the roster |
| 2 | `display_name` | IDENT **on screen** / **CONTACT** in an export | holder | `public.profiles.display_name` — the 068 public-safe set | **on screen:** every role that may read the roster, ungated. **In an export: emitted only where a contact relationship exists — the §5.1 gate, unchanged — and blank otherwise.** See §4.3: the name is a global string, identical across orgs, so an ungated name column is a cross-tenant join key on every row |
| 3 | `is_purchaser` | IDENT | holder | true iff this holder is the `buyer_id` of ≥1 of the atoms they hold | every role |
| 4 | `tickets_held` | IDENT | holder | count of non-voided atoms held for the session | every role |
| 5 | `ticket_types` | OPS | holder | `venue.ticket_type.name`, distinct, sorted | every role |
| 6 | `source` | OPS | holder | `venue.order.source` ∈ `app`·`web`·`door`·`promoter_link` | every role |
| 7 | `acquired_via` | OPS | holder | ownership-log head cause, mapped (§2.5) | every role |
| 8 | `checked_in` | OPS | holder | latest `venue.scan` for the atom: `not_scanned`·`admitted`·`already_used`·`other_non_admit` | every role except finance roles (they are `D` on `venue.scan`, RLS §9.12) |
| 9 | `admitted_at` | OPS | holder | `venue.scan.occurred_at` of the admitting scan | as field 8 |
| 10 | `promoter_name` | OPS | holder | `venue.attribution` → `promoter_link` → `promoter.name` | every role; **gated on package 090/2D** |
| 11 | `promoter_code` | OPS | holder | `venue.promoter_link.slug` | as field 10 |
| 12 | `email` | **CONTACT** | holder | `auth.users.email`, read inside the definer, **gated by §5** | audience roles only; blank when the gate fails |
| 13 | `first_seen_at` | IDENT | org CRM | earliest acquisition for this `(org, identity)` | org-grain roles only |
| 14 | `events_attended_count` | OPS | org CRM | distinct sessions **of this org only** where this identity was admitted | org-grain roles only |
| 15 | `sessions_held_count` | OPS | org CRM | distinct sessions **of this org only** where this identity held a non-voided atom | org-grain roles only |
| 16 | `order_ref` | **MONEY** | purchaser | `venue.order` display reference | money roles only |
| 17 | `order_status` | **MONEY** | purchaser | `venue.order.status` | money roles only |
| 18 | `order_total` | **MONEY** | purchaser | `venue.order.total_minor` + `currency` | money roles only |
| 19 | `unit_price` | **MONEY** | purchaser | `venue.order_item.unit_price_minor` (purchase snapshot) | money roles only |
| 20 | `refund_state` | **MONEY** | purchaser | derived: order status + atom `voided` cause `refund_void` (D2 — the ticket has no `refunded` terminal) | money roles only |
| 21 | `tickets_purchased` | **MONEY** | purchaser | count of atoms issued from this order, non-voided | money roles only |

**Fields 13–15 are the org-level CRM.** They are the answer to "who are my repeat customers", and they are
the *only* place a number is aggregated across events. §4.4 proves they cannot cross an org boundary.

### 2.3 The never-exported list

Nothing below appears as a column, a filter, a sort key, a hash, a code, a boolean, a segment name, a sheet
name, a filename component, a job parameter, or a header — **for any role, including `org_owner` and
`platform_admin`.**

| Never exported | Why not |
|---|---|
| **`identity_id` / `auth.users.id` / any global identity uuid** | It is a cross-org join key. Two orgs' CSVs union on it and reconstruct a person's cross-venue attendance graph — precisely what CDM §8 forbids ("never a customer's activity at other venues"). Replaced by the per-org `customer_ref` (§4.3). |
| **`phone_number`** | Binding already (dashboard §9.6: *"Phone is never exportable. Not as a column, not as a filter, not as a hash."*). Restated at full strength: also not as a search key, not as a match key, not as a suppression key. |
| **`full_name` / legal name** | `VERIFIED:` 068 removed it from the `authenticated` grant; `bbbba9c` removed it from bid history. No roster need reaches a legal name — a door verifies a government ID against a human, not against a CSV. |
| **Payment identifiers** — `stripe_payment_intent_id`, `stripe_charge_id`, `stripe_customer_id`, `stripe_connect_account_ref`, `payment_method_id`, `kernel.payment_native` / `kernel.refund` / `kernel.payout` ids, card brand/last4/expiry, bank details | A processor-side handle in a spreadsheet has moved a payment credential across a trust boundary for zero product value. There is no operator question a Stripe id answers that `order_ref` does not. |
| **Custody / credential internals** — `ticket_atom_id`, `ownership_log_id`, `credential_id`, `credential_version`, `signing_key_id`, any QR token or signed credential | A credential handle is a forgery input (C33). `serial_no` is also excluded: it is unique within a session and therefore an enumeration handle. |
| **Door internals** — `pin_hash`, any door PIN, `scan_device_id`, `device_boot_id` | `VERIFIED:` `pin_hash` is stripped from every client grant and never returned to any client (dashboard §5 note 17). |
| **The transfer counterparty** | Who transferred a ticket to this holder is a *relationship* disclosure — who knows whom. `VERIFIED:` `kernel.get_ticket_custody_chain` is the staff read and it already redacts counterpart PII (dashboard §9.4). The export inherits that redaction: `acquired_via` says *how*, never *from whom*. |
| **Platform-side fan state** — `wallet_balance`, `is_verified_seller`, `stripe_onboarding_complete`, seller onboarding status | The fan's commercial relationship with Snatch It is not a venue fact. |
| **Identity/compliance** — `residency_region`, `kyc_ref`, any government ID, any ID-verification media | `VERIFIED:` `kernel.identity_ext` carries only these two; neither has a roster purpose. |
| **Any other org's data about this person** | Fields 14/15 count **this org's** sessions only. See §4.4. |
| **Every demographic object, value, derivation or proxy** | X-1 … X-9. Enumerated separately below because it is a constraint set, not a field. |

### 2.4 X-1 … X-9, and how this document satisfies each

Reproduced from the demographics spec §9 and answered. **These are constraints handed to this design; they
are not re-litigated here.** §13 records the one place I would ask a question, and it is a question about
implementability, not about whether the constraint is right.

| # | Constraint | How this document satisfies it |
|---|---|---|
| **X-1** | No individual-level demographic data leaves the platform. Ever — not as column, code, hash, boolean, derived flag, segment name, filename, header, or job metadata. | The field catalogue (§2.2) is closed and contains no demographic field. The filter set (§6.5) is closed and contains no demographic member. The filename is `{job_id}.csv` under `{org_id}/` — **no venue name, no event title, no date, no segment, no bucket** (§6.6). The job's stored parameters are `(scope_kind, scope_id, template_id, template_version, filters, as_of)` and the filter grammar cannot express a demographic predicate (§6.5). |
| **X-2** | Demographic values may not be an export **filter** — the row set *is* the disclosure. | The filter set is a **closed enumerated set with a fixed grammar** (§6.5), not a predicate language. A demographic member cannot be added by configuration; it requires a schema change to the filter enum, which the CI check in §10 and pgTAP assertion 21 both reject. §6.5 also states the principled line: a filter is forbidden when the file **withholds** the value the filter selects on; that is why `email_present` **is** an allowed filter and a demographic one is not. |
| **X-3** | The aggregate mix is not an exportable object — no CSV, PDF, print view, image render, API, scheduled report, or email digest. | No template in §6.4 contains an aggregate. There is no print view, no scheduled export, and no email delivery of any export in this design (§6.2, §6.7). The only egress is a signed download to the requesting operator (§6.6). |
| **X-4** | No proxy fields — no "shared demographics: yes/no", no response-completeness score, no derived sort or row order. | The row order of every export is **deterministic and demographic-free**: `ORDER BY customer_ref` (a keyed hash of an identity id, which is uncorrelated with any demographic value). Stated as a contract and asserted (pgTAP 22). No completeness score exists anywhere in the field catalogue. |
| **X-5** | No third-party destination ever receives a demographic field. | Stronger, and stated as a rule of this document: **there is no third-party destination for a CRM export at all** (§6.7 / rule **EX-6**). No webhook, no CDP, no ESP property, no ad audience upload, no pixel, no warehouse sync, no scheduled email. Connected to **C40** in §6.7: a venue-configurable egress destination would be a C40-class change requiring a static platform-controlled allowlist and a CI-asserted REVOKE, and it is not built. |
| **X-6** | The export builder's SQL contains zero references to the four demographic objects. **CI-checkable and must be a CI check.** | §10, specified in four layers with the failure modes of each named, including the one that matters most: a check that scans an empty file set passes vacuously. |
| **X-7** | If a campaign needs audience composition, the answer is the on-screen aggregate, not data movement. | The dashboard §9.5 card is unchanged and remains a read on screen. This document adds nothing to it and takes nothing from it. `marketing` reads the card and exports the audience; the two never meet in a file. |
| **X-8** | A demographic-based send is not Phase 2. | Not built, not designed, not stubbed. There is no send of any kind in this design — the export produces a file for an operator, never a message to an attendee. Recorded as owner decision **D-9** so it is a decision and not a drift. |
| **X-9** | Every export authorization check is unaffected, but the export **audit record must record that the demographic constraint set applied.** | Every export audit row (§8.3) carries `constraint_set_version` — a monotonic identifier of the X-1…X-9 text in force, seeded in `catalog.platform_config` as `crm_export.constraint_set_version` and stamped by `venue.request_export` in the same transaction as the job row. §8.4 shows the auditor's query. |

### 2.5 `acquired_via` mapping

`VERIFIED:` the canonical cause registry (SPEC_FOUNDATION §4 D3) is
`issue · primary_sale · comp · door_sale · p2p_transfer · market_sale · auction_sale · admin_action ·
refund_void · import · promoter_commission · settlement · chargeback`.

| Ownership-log head cause | `acquired_via` |
|---|---|
| `issue`, `primary_sale`, `door_sale` | `purchase` |
| `comp` | `comp` |
| `p2p_transfer` | `transfer` |
| `market_sale`, `auction_sale` | `resale` |
| `admin_action` | `adjustment` |
| `import` | `import` |
| `refund_void` | *(not reachable — a `voided` atom is not on the roster)* |

The mapping is coarse on purpose. `INFERENCE:` the operator's question is "did this person buy it, get it, or
receive it", and the finer cause distinctions are ledger vocabulary that would put internal state into an
operator's spreadsheet for no operational gain.

---

## 3. Role × capability matrix

Canonical labels and the 20 principals from the role-model spec §5.1. Cells use that spec's vocabulary:
`·` deny · `A` direct read · `V` view-only through a scoped read RPC · `R` permitted inside a definer RPC ·
`◐` scoped subset. **Every non-`·` cell in this matrix is a definer-RPC path; there is no direct table read
of a roster object by any client role** (GP-1 + the empty-grant posture of §0).

| Capability | ANO | FAN | OMB | OOW | OAD | OFI | OMK | OPM | VMG | VFI | VBO | VMK | VPM | VSC | DOO | PRO | PSU | PRI | PAD | SVC |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| **X1** Read roster — IDENT + OPS (holder view) | · | · | · | V | V | V◐ᶠ | V | · | V | V◐ᶠ | · | V | · | · | · | · | V | V | V | R |
| **X2** Read roster — CONTACT column on screen | · | · | · | V | V | **·** | V | · | V | **·** | · | V | · | · | · | · | **·**ˢ | · | V | R |
| **X3** Read purchaser/order view — MONEY | · | · | · | V | V | V | **·** | · | V | V | · | **·** | · | · | · | · | V | V | V | R |
| **X4** Single-record service lookup (§7.2) | · | · | · | V | V | · | · | · | V | · | V | · | · | V◐ᵐ | V◐ᵐ | · | V | V | V | R |
| **X5** Request export — **audience** template | · | · | · | R | R | **·** | Rᵒ | · | R | **·** | · | Rᵛ | · | · | · | · | **·** | **·**ᵖ | **·**ᵖ | R |
| **X6** Request export — **operations** template (adds MONEY) | · | · | · | R | R | **·** | **·** | · | R | **·** | · | **·** | · | · | · | · | **·** | **·**ᵖ | **·**ᵖ | R |
| **X7** Org-grain CRM view (fields 13–15) | · | · | · | V | V | · | Vᵒ | · | **·** | · | · | **·** | · | · | · | · | · | V | V | R |
| **X8** Download an export | · | · | · | R◐ | R◐ | · | R◐ᵗ | · | R◐ | · | · | R◐ᵗ | · | · | · | · | · | · | · | R |
| **X9** Revoke an export | · | · | · | R | R | · | R◐ᵗ | · | R | · | · | R◐ᵗ | · | · | · | · | · | · | R | R |
| **X10** Read export history | · | · | · | V | V | · | V◐ | · | V | · | · | V◐ | · | · | · | · | V | V | V | R |
| **X11** Read the ticket-holder-mix card | · | · | · | V | V | · | V | V | V | · | · | V | V | · | · | · | · | · | V | R |
| **X12** Manage own contact permissions | · | **R◐** | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | R◐ | · | R◐ | R◐ | R◐ | R◐ | R |

> ᶠ **Finance roles see counts and money, never contact and never check-in.** `VERIFIED:` DA §7.6 "View buyer
> PII" gives Org Finance and Venue Mgr `◐(limited)`; RLS §9.12 makes finance roles `D` on `venue.scan`, so the
> check-in columns (fields 8/9) are **absent** from a finance read, not blank. Dashboard §5 note 10 says the
> same.
> ˢ **`platform_support` reads, and does not extract.** `VERIFIED:` dashboard §22.6 — *"read ≠ export …
> support can look, not extract."* Support reaches a single record through X4 for a support ticket; it holds
> no bulk contact read and no export.
> ᵒ `org_marketing` operates at **org grain** — all the org's venues. ᵛ `venue_marketing` at **venue grain**
> only. The plane of the grant is the export scope (role-model §4.2).
> ᵐ Door principals get the **minimal verification projection** only — name + validity — never contact
> detail. `VERIFIED:` DA §7.2 / role-model F11.
> ᵗ **`◐` on X8/X9 is scoped by `template_id`, not only by grain.** A role may download or revoke exactly the
> jobs whose template it may **request** — for both marketing labels, `audience_v1` only. Enforced by
> re-evaluating the request-time allow-list for `job.template_id` at download (EX-4, §11.4), which is the one
> predicate that keeps §3.1's "neither sees both" true. `org_marketing` legitimately *sees* an
> `operations_v1` job in the history panel (X10) and cannot download it.
> ᵖ **Platform roles do not use the venue CRM export.** See the conflict resolved in §3.2.
> **X12** is the fan's own control (§5.3) and is the only row where `FAN` is not `·`. A door session (`DOO`)
> has no `auth.uid()` and therefore no own-row anything (role-model §7.2).

### 3.1 The denials that are deliberate

**`venue_box_office` — no roster, no export, single-record lookup only.** `VERIFIED:` role-model F12 marks
`VBO` as `·` on bulk attendee list/export while F11 grants it the single-record read; O-2 gives box office
*"ticket issuance / permitted inventory-sale operations only."* `INFERENCE:` box office works one person at a
time, at a counter, in front of that person. The product consequence, stated honestly so nobody is surprised
at 9 p.m.: **a box office cannot print a paper list.** That is deliberate — a printed list is an
unaudited export with none of §6's controls and a longer life than any of them.

**`venue_promoter_manager` / `org_promoter_manager` — no roster, no export.** `VERIFIED:` role-model H2/H3
and F12 mark both `·`. They keep attribution and commission reporting (G1–G4) and the event-level holder-mix
card. `INFERENCE:` a promoter manager asking "who did my promoters bring, by name" is asking to cross the
two-tier wall (DA §1.7, dashboard §10.1). The commercial need — how many tickets, what commission — is fully
served by the attribution surface, which this document does not touch.

**`org_finance` / `venue_finance` — money and counts, never contact, never any export.** `VERIFIED:`
role-model H2 and H3 both mark them `·`, and dashboard §9.6 denies them explicitly. `INFERENCE:` CRM export is
a *contact* surface, not a money surface, and least privilege runs in both directions.

**The asymmetry worth naming.** Finance sees money and no contact. Marketing sees contact and no money.
**Neither sees both.** Only `venue_manager`, `org_owner` and `org_admin` hold the union — and that union is
the single most consequential grant in this document, which is why X6 (the operations template) is the
narrowest allow-list in the matrix and why §7.1's per-actor limit is the same for all of them.

**The invariant holds only if the download re-check reads the template.** `INFERENCE:` this asymmetry is
stated as a property of the *request* allow-lists, and the download path is where it was lost: re-checking
the role set alone let a marketing actor redeem a colleague's `operations_v1` job — money and contact in one
file, from one `job_id` the export-history panel legitimately showed them. **X8's `R◐` for `OMK`/`VMK` means
"jobs whose template that role may request", `audience_v1` only**, and it is enforced by re-evaluating the
request-time predicate at download (EX-4, §11.4). Without that one predicate this paragraph is a claim about
a matrix rather than about the system.

**`venue_scanner` and the door session — nothing.** `VERIFIED:` dashboard §9.3: *"Bulk attendee listing is
denied to door staff… A door principal hitting this route gets the permission-denied state"*, and the denial
names the alternative (X4). A door session has no `auth.uid()` at all.

**`promoter` — nothing, from any surface.** `VERIFIED:` RLS §9.17 note 40; DA §1.7. A promoter holds no row
in any of the three authz tables (role-model §9.1/§9.3), so every predicate in this matrix returns false for
them by construction, not by policy.

### 3.2 A conflict I found, and how I resolved it

`VERIFIED:` **role-model §5 F12 marks `PRI` and `PAD` as `A` on bulk attendee list/export.**
`VERIFIED:` **dashboard §5 note 13 says the opposite:** *"Agent B's allow-list is `venue_manager`,
`org_owner`, `org_admin` only; `platform_risk`/`platform_admin` are not on it, so the venue export surface
does not render for them… If platform staff need bulk extraction it must be a separately audited platform
path, not this one."*

**Resolution (`SPEC CORRECTION`):** both are right about different things. `platform_risk` and
`platform_admin` may **read** the roster (X1, X3, X7 — they are `A`/`V` there, and F12's grant is a read
grant). They may **not use the venue CRM export** (X5/X6 `·`). `INFERENCE:` the venue export is scoped,
templated and audited *as a venue action* — its audit row names a venue actor and lands in that venue's
activity feed. A platform bulk extraction has a different justification, a different retention, and needs
dual control; running it through the venue's own surface would file a platform action in a venue's history and
would give a compromised platform account the venue export's rate limits rather than a platform-grade one.
**Platform bulk extraction is not built in Phase 2.** Recorded as owner decision **D-8** and as edit
**K-3** in §11.7.

---

## 4. Cross-organization isolation

This is the highest-consequence property in this document. It is argued structurally, then proved for the
four required cases.

### 4.1 The two structural rules

> **XO-1 — The anchor rule.** Every CRM read is anchored on a **scope object the caller holds a role over**,
> and traverses only **downward**: `org → venue → event → session → ticket → holder`. There is no upward and
> no lateral traversal. **No CRM RPC accepts an identity as a parameter**, so "what else does this person
> hold" is not an expressible question at this surface — the same structural move `get_my_profile()` (042) and
> `get_my_demographics()` make by having no identity argument at all.

> **XO-1a — The atom-tenancy rule.** The downward traversal is **necessary, never sufficient**. Every roster
> and export query additionally ANDs `kernel.tickets.org_id = :job_org_id` — **the job's org, at every
> grain**, not only at org grain. `:job_org_id` is resolved once at request time from the scope object and
> frozen on the job row; the builder reads it from the job row, never re-derives it from the scope, and never
> takes it from the atom.

> **XO-2 — The pseudonym rule.** No export or roster read emits a global identity id. It emits
> `customer_ref = HMAC(org_customer_key(:job_org_id), identity_id)` — **stable within one org, unlinkable
> across orgs** (§4.3). The key's org and the consent gate's org are both the **job's** org, never the atom's
> and never the venue's current one.

`INFERENCE:` XO-1 stops a caller *reaching* another tenant's rows **through the graph**. XO-1a stops them
reaching another tenant's rows **because the graph moved**. XO-2 stops two tenants *combining* rows they each
legitimately hold. They defend three different attacks and none substitutes for another. The frozen corpus
specifies XO-1 in several places (dashboard §4.4; CDM §8) and specifies nothing like XO-1a or XO-2.

**Why XO-1a is a rule and not a detail — the finding it closes.** `VERIFIED:` `catalog.event.org_id` is
stamped at create, while **`catalog.venue.org_id` is mutable**: an operatorship change is *logged*, not
overwritten-and-forgotten, which means the same venue row can name Org 1 today and Org 2 tomorrow. The
isolation traversal is `org → venue → event → session → ticket → holder`, and the atom-level `org_id`
equality was invoked **only for the org-grain aggregate** (§4.4 case (c)). So a **venue-grain** export
requested at the new operator traversed `venue → event → session → ticket` and reached **every historic
session of that venue** — the previous operator's entire customer list, handed over by a legitimate request
from a legitimate role over a scope they legitimately hold. None of the four original proofs covered it:
(a) is about two orgs' *separate* atoms, (b) about a venue role not inheriting up, (c) about the org grain
where the predicate already ran, (d) about a promoter holding two grants.

Compounding it: with the HMAC key and the consent `EXISTS` both written as "org" without saying *whose*, an
implementer reading the atom's `org_id` would produce, for the two orgs' files, **the same pseudonym for the
same person** — the two files then join directly and the cross-tenant defence is gone outright, not
weakened. XO-1a and XO-2's "the job's org" clause remove the ambiguity by naming the operand, and §4.4 case
(e) proves the case.

### 4.2 Why XO-1 holds — the mechanics

1. **No unscoped route, no unscoped RPC.** `VERIFIED:` dashboard §4.4.1 — every route carries an org, venue or
   event id. Every RPC in §11.4 takes `(scope_kind, scope_id)` and rejects `scope_kind = 'all'`; there is no
   such member in the enum.
2. **Scope ids are untrusted parameters, re-checked in-body against live tables.** `VERIFIED:` RPC §0.1.
   A tampered id returns `insufficient_privilege(42501)`, never another org's rows.
3. **The predicates are point probes on grant tables.** `VERIFIED:` role-model §6.4 — `venue.staff_role`'s PK
   is `(venue_id, identity_id, role)`; **there is no wildcard row, no `venue_id IS NULL` grant, and no
   "all venues of org X" row.** The caller's venue list is never materialized; the question asked is always
   "does *this* venue grant me *this* role", never "which venues grant me roles".
4. **The tenant is on the atom, and the comparison is made — at every grain.** `kernel.tickets.org_id` is
   `not null`, so every roster row's tenancy is a column comparison rather than an inference from a join
   chain. **XO-1a requires that comparison to actually run**, against the job's frozen `org_id`, on the
   session grain and the event grain and the venue grain as well as the org grain. `INFERENCE:` the property
   "the tenant is on the atom" was stated as if it were self-executing. It is not: a column that exists and
   is never compared defends nothing, and the venue-grain query was exactly the query that did not compare
   it.
5. **Denials leak nothing.** `VERIFIED:` dashboard §4.4.5 — a deep link to another org's event renders the
   standard permission-denied state with no partial content, **no title, no count**. An export request for a
   scope the caller cannot reach fails identically whether the scope exists or not.
6. **No impersonation.** `VERIFIED:` dashboard §4.4.6 — there is no "view as venue" mode.

### 4.3 `customer_ref` — the per-org pseudonym

- `customer_ref = base32( HMAC-SHA256( org_customer_key(:job_org_id), identity_id )[0..9] )` — 80 bits,
  rendered as 16 characters. Collision probability across a 10⁶-customer org is ~10⁻¹²; a collision produces
  two customers merged in a CSV, not a security failure.
- **`:job_org_id` is the job's org, frozen at request — never the atom's `org_id`, never the venue's current
  `org_id` (XO-1a).** `INFERENCE:` this was written as `org_customer_key(org_id)` with no statement of which
  `org_id`, and the ambiguity is not cosmetic: because `catalog.venue.org_id` is mutable, "the atom's org" and
  "the job's org" are the same value in the common case and **different values in exactly the case the
  pseudonym exists to defend**. Keying on the atom's org would give two orgs the same `customer_ref` for the
  same person, so their two files would join on the pseudonym directly — a defence that inverts into an
  attack. XO-1a makes the two operands equal by construction (a row whose atom org differs from the job org is
  not in the result set at all), and this clause makes the code say so anyway, because "they are equal
  anyway" is how the next refactor reintroduces it.
- `org_customer_key` is a random per-org secret held in **`kernel.org_customer_key`** (§11.2), definer-only,
  **zero grants to every client role**, never returned by any RPC, never logged, never in an error message,
  never in the export.
- **It never rotates.** Rotation would silently break every CRM continuity claim a venue has built
  (`first_seen_at`, `events_attended_count`, their own downstream notes keyed on the ref). If it ever must
  rotate — a suspected key disclosure — the export template version bumps and the venue is told, in the export
  history panel, that their customer references changed on a date. Rotation is a `platform_admin`, step-up,
  audited action; it is not a routine.
- **It is not a C33/KMS-class key.** `INFERENCE:` its compromise re-links pseudonyms *within data the platform
  already holds*, which the platform can already do; it does not forge a credential or move custody. It is
  handled as a secret (no grant, no log, no return) but it does not need HSM custody, and saying otherwise
  would dilute what C33 means.

**Honest limit, stated plainly — and corrected, because the previous statement of it was false.**

The pseudonym removes the **platform-supplied *stable* join key**, and that is the whole of what it removes.
It does not remove a join key the customer supplied to both parties themselves: if a person consented to email
at Org A and at Org B, both CSVs carry the same email address and they join on it. That much was already
stated and is still true.

**What was false:** the claim that *"the non-consenting majority — every transferee, every comp, every
purchaser who left the box unticked — is unjoinable, which is exactly the population with no relationship to
either venue."* **That claim is deleted.** `display_name` was emitted on **every row of every export, at
every org, ungated by consent**, from the one global `public.profiles.display_name` string — the same value
for the same person everywhere on the platform. Two orgs union their files on it directly, and corroborate
with admission time, `first_seen_at`, ticket types and `acquired_via`. The non-consenting majority was
exactly as joinable as the consenting minority; the only difference was which column carried the key. The
proof in §4.4 case (d)'s sub-case rested on that claim, so **that proof was void as written** — it is
restated below against the corrected design.

**The fix: `display_name` is consent-gated *in the export*, and ungated *on screen*.**

| Surface | `display_name` | Why |
|---|---|---|
| **Roster on screen** (X1) | **always emitted** | The room has to be run. `VERIFIED:` §5.6 — after 068 `display_name` is one of eight columns `authenticated` may read on **any** row, so the screen discloses nothing a staff member could not already select. And a screen is not a file: it cannot be unioned with another org's screen. |
| **Single-record lookup** (X4) | **always emitted** | Same reasoning, narrower surface — one record, service context. |
| **Door verification projection** | **always emitted** | Name + validity is the whole projection. `VERIFIED:` DA §7.2 / role-model F11. |
| **Export file** (X5/X6) | **emitted only where a contact relationship exists** — i.e. exactly where `emit_email` (§5.1) emits; **blank otherwise** | An export is exfiltration (§0). Once a name is in a CSV it is a durable, unioning join key over a population that never chose to have a relationship with the org holding it. |

`INFERENCE:` the split is not a compromise, it is the actual shape of the risk. The harm is not that a venue
*learns* a name — §5.6 already established it can. The harm is that a name **leaves in a file**, where it
becomes the stable identifier the pseudonym exists to withhold. So the gate goes on the egress, not on the
knowledge, and the door operation the venue actually needs is untouched.

**Consequences, stated because someone will meet them at 9 p.m.:**

- An `audience_v1` export over a heavily transferred session is mostly `customer_ref` + ops columns, with
  name and email blank on the same rows. `INFERENCE:` that is the correct file — those rows describe people
  the org has an *admission* relationship with and no *contact* relationship with, and §5.2 already ruled
  that they are "on the roster and off the mailing list". The export now says the same thing the rule says.
- An `operations_v1` export for finance reconciliation identifies rows by `customer_ref` and `order_ref`
  rather than by name. Both are stable within the org and sufficient to reconcile; neither unions across
  orgs.
- The suppression legend and counters cover both columns: `name_cells_emitted` / `name_cells_suppressed`
  alongside the contact pair (§8.3), and the inline legend gains *"Name is blank for people who haven't
  agreed to share their details with this organization. They're still on your roster on screen."*
- **Owner decision D-13.** The operator-facing loss is real and the alternative — emitting the name to
  everyone — is what makes the cross-tenant proof false. This spec recommends the gate as written.

### 4.4 The five proofs

**Case (a) — a shared attendee holding tickets at Venue A (Org 1) and Venue B (Org 2).**

The person holds two atoms. Atom₁ carries `org_id = Org1`; Atom₂ carries `org_id = Org2`. Venue A's roster
read is anchored on a session of Org 1 and selects atoms whose `event_session_id` is that session; Atom₂ is
not in that set, in any filter, under any parameter, because no parameter selects on identity (XO-1). Venue A
therefore learns "a person holds tickets to my show" and nothing about Org 2. Symmetrically for B. **Neither
export contains a global identifier**, and `customer_ref` differs between them because the HMAC keys differ
(XO-2). The two files describe the same human and cannot be shown to. ∎

*Residual, stated:* if the person consented at **both** orgs, both files carry their email **and their
display name** (§4.3), and join on either. Bounded to the population that granted a contact relationship to
both organizations, and produced by the person's own two deliberate acts.

*What this proof used to over-claim.* Before `display_name` was gated (§4.3) the conclusion above was false
for **every** row: the name column carried the same global string in both files, so the two exports joined
directly whether or not anyone consented. The proof now holds because the only columns that survive in both
files for the same person are ones that person granted to both orgs.

**Case (b) — a multi-venue org.**

Org 1 operates V1…V40. A `venue_marketing` grant at V1 is a row `(V1, identity, venue_marketing)`. The
predicate `has_venue_role(V2, ['venue_marketing'])` probes `(V2, identity, venue_marketing)` — a different PK
— and returns false. There is no grant shape that means "all venues", so reaching V2 requires a second
deliberate grant. `org_marketing` on Org 1 reaches all forty by `has_org_role(Org1, ['org_marketing'])`, which
is the *intended* semantic (role-model §4.2: **the plane of the grant is the export scope**), and it stops at
Org 1 because the predicate takes the org id as a parameter and Org 2's id is a different parameter. **Venue
roles never inherit up** (RM-4), so `venue_marketing` at V1 never becomes org-grain access, and X7 marks
`VMK` as `·` for that reason. ∎

**Case (c) — an org-level CRM view.**

Fields 13–15 aggregate across the org's own venues and sessions. Their `FROM` is anchored on `org_id` and the
aggregation predicate is `kernel.tickets.org_id = :job_org_id` — a column equality on the atom, so no row from
another tenant can enter the aggregate even if a join were wrong. Within the org, all of a customer's rows
collapse onto one `customer_ref`, which is what makes the CRM a CRM. Across orgs they do not collapse, because
the refs are different strings. **The org CRM view is offered only to org-plane roles** (`org_owner`,
`org_admin`, `org_marketing`) — a venue-plane role has no org-grain read anywhere in this document. ∎

*Note, because this proof was the load-bearing one and was over-read:* this is the **only** case in which the
original design invoked the atom-level equality. Case (e) is the case where the same predicate had to run and
did not.

**Case (d) — a promoter working with two orgs.**

A promoter holds no `venue.staff_role` row (role-model §9.1 removed `venue_promoter`) and no
`kernel.org_member` row by virtue of promoting. Every predicate in §3 therefore returns false, and `PRO` is
`·` on X1–X11. They see their own links, attributions and commission in the promoter portal — objects keyed to
`promoter_link.identity_id = auth.uid()` — and no roster, at either org. ∎

*The harder sub-case, which is the one that actually matters.* A promoter is **separately granted**
`venue_marketing` at V_A (Org 1) **and** `venue_marketing` at V_B (Org 2) — two deliberate acts by two
different venue managers, both legitimate. They now hold two audience exports. XO-1 keeps each anchored to its
own venue; **XO-2 and the §4.3 name gate together keep the two customer lists unjoinable for everyone who did
not grant a contact relationship to both orgs**, so a person holding both files cannot tell that a
non-consenting customer of V_A is a customer of V_B. `VERIFIED:` role-model §9.3 flags exactly this union as
an accepted residual bounded by "the CRM export's live re-authorization at download and the money-column
exclusion". `INFERENCE:` those two controls bound the *authority*; the per-org pseudonym **and the name gate**
are what bound the *correlation*, and without both the residual is larger than that paragraph implies. ∎

*This is the sub-case that failed hardest before the correction, and it is worth saying why.* The pseudonym
was doing the work the design credited it with — it is genuinely per-org and unreadable by any principal —
but it was not the only join key in the file. `display_name` sat in every row of both exports, ungated,
carrying the same global string, so the promoter holding both files unioned them on the name column in one
step and corroborated with admission time, `first_seen_at`, ticket types and acquisition route. XO-2 removed
the *stable* platform-supplied key and nothing else; the design read it as removing *the* key. The name gate
is what makes this proof true rather than reassuring.

**Case (e) — a venue whose operator changed. (The case none of (a)–(d) covered.)**

Venue V is operated by Org 1 through August and by Org 2 from September. `VERIFIED:` `catalog.event.org_id` is
stamped at create, so August's events keep `org_id = Org1`; `catalog.venue.org_id` is **mutable** — the change
of operatorship is logged rather than overwritten-and-lost — so `catalog.venue(V).org_id = Org2` from
September.

*Without XO-1a.* A `venue_manager` at V under Org 2 requests a **venue-grain** export with a 180-day window.
The traversal is `venue V → its events → their sessions → their tickets → their holders`, every hop
legitimate, every id inside a scope the caller holds a role over. August's sessions hang off V, so August's
atoms — carrying `org_id = Org1` — enter the result set. **Org 2 receives Org 1's customer list**, complete
with consent-gated email for everyone who consented *to Org 1*, and with `first_seen_at` and
`sessions_held_count` computed over a period Org 2 did not operate. The four original proofs are all silent:
this is one venue, one traversal, one legitimately-held scope, and no cross-org union of files.

*With XO-1a.* The builder ANDs `kernel.tickets.org_id = :job_org_id` at **venue grain** as well as org grain.
`:job_org_id = Org2`, August's atoms carry `Org1`, and the equality fails on the atom itself — before any
join, any filter, or any template. August's rows are not in the result set, so they are not in the file, not
in `row_count`, and not in fields 13–15's aggregates.

*The consent limb.* The gate's `EXISTS kernel.org_contact_consent(identity, org)` binds `org := :job_org_id`
(§5.1). Consent granted to Org 1 therefore does not emit under a job whose org is Org 2 — which is the
correct answer independently of XO-1a, because consent is a fact about a person and **an organization**
(§5.2), and Org 2 is a different organization that this person has never met. A venue changing hands does not
transfer the audience's permission along with the lease.

*The pseudonym limb.* `customer_ref` keys on `org_customer_key(:job_org_id)`, so a person who genuinely
attended under both operators gets two unlinkable refs. Had the key been taken from the atom, the two orgs'
files would have carried **identical** refs for that person and would have joined on the pseudonym — the
defence inverted. ∎

*Residual, stated:* Org 2 loses the venue's history for its own venue. A new operator sees an empty CRM on
day one and will ask why. That is the correct answer — the prior audience is the prior operator's, not the
building's — and it is a real product consequence someone should say out loud before a venue changes hands.
**Owner decision D-12.**

### 4.5 What these proofs do not cover

- **A person who is genuinely a member of two orgs** and is deliberately trusted by both. They can read both
  CRMs. Nothing here prevents that, and nothing should — two organizations chose them.
- **Manual correlation on a small room.** A venue that knows its regulars can recognise a display name. The
  pseudonym defends bulk correlation, not recognition.
- **Collusion using out-of-band data.** Two orgs that already share a mailing list can join on email. Out of
  scope for a data-access control.

---

## 5. Contact information and the opt-out model

### 5.1 What a venue may see — the answer

| | On screen (audience roles) | In an export (audience roles) | Finance / box office / door / promoter / support |
|---|---|---|---|
| **Display name** | ✔ | ✔ **only through the gate**, blank otherwise (§4.3) | box office ✔ (single record); door ✔ (name + validity only); finance ✔ **on screen**; promoter ✗ |
| **Email** | ✔ **only through the gate** | ✔ **only through the gate**, blank otherwise | **✗ for all of them** |
| **Phone** | **✗ — never, for anyone** | **✗ — never, for anyone** | ✗ |
| **Legal name** | ✗ | ✗ | ✗ |
| **Postal address** | not collected | not collected | — |

**The gate, stated as a single fail-closed conjunction.** An email cell is emitted **iff all four hold**;
anything unknown, missing, stale or erroring suppresses:

```text
emit_email(identity, :job_org_id) :=
      kernel.identity_contact_pref(identity).venue_email_contact = 'allow'      -- the master switch
  AND EXISTS kernel.org_contact_consent(identity, :job_org_id)
        WHERE state = 'granted'                          -- THE JOB'S org, specifically (XO-1a / §4.4 case e)
  AND identity is live (not deactivated, not erased, not the anonymized sentinel)
  AND the reading role holds the CONTACT class for this scope                   -- §3
```

**The org in conjunct 2 is the job's org — never the atom's, never the venue's current one.** `INFERENCE:`
the previous wording said "this org, specifically" without saying which `org` the free variable bound to,
and because `catalog.venue.org_id` is mutable the two candidate bindings differ in exactly the case that
matters: a venue that changed operator. Consent is a fact about a person and **an organization** (§5.2), so
consent granted to the prior operator must not emit under the new one — the audience's permission does not
transfer with the lease. Pinning the binding here makes that true by construction rather than by the
happy accident that the two values usually coincide.

**The same gate governs `display_name` in an export** (§4.3, finding: an ungated name column is a global
cross-tenant join key on every row). `emit_name(identity, :job_org_id) := emit_email(identity, :job_org_id)`
— **one predicate, evaluated once per holder row, driving both cells**, so the two can never disagree and a
future engineer cannot gate one and forget the other. On screen, in the single-record lookup, and in the door
projection, `display_name` is **ungated** — §5.6 establishes it is already readable there, and a screen
cannot be unioned with another org's screen.

Suppression is **visible, not silent**. `VERIFIED:` dashboard §9.6 already requires this: an inline legend
*"Email is blank when the buyer didn't agree to share it with this organization."* plus a count of suppressed
cells in the export summary. This document keeps both, extends the legend to cover the name column
(*"Name is blank for people who haven't agreed to share their details with this organization. They're still
on your roster on screen."*), and adds the counts to the audit row (`contact_cells_emitted` /
`contact_cells_suppressed` and `name_cells_emitted` / `name_cells_suppressed`, §8.3) — `INFERENCE:` those
numbers are the only evidence a later auditor has that the gate actually ran on a given export, and they cost
four integers.

### 5.2 Purchaser vs transferee — the contact rule

> **Contact permission is a fact about a person and an organization. It is never a property of a ticket, so
> it never moves when a ticket moves.**

| Situation | May the org email them? | Why |
|---|---|---|
| Purchaser who ticked the box at checkout | **Yes** | They transacted with that org and said so. |
| Purchaser who left the box unticked | **No** | Default is off. Buying is not consenting. |
| Purchaser who ticked the box, then transferred all six tickets away | **Yes, still** | The consent is theirs, about that org; it does not leave with the ticket. |
| Recipient of a p2p transfer | **No — never, from the transfer alone** | They never interacted with that org. They are on the roster as a holder, with a display name, so the room can be run; they are not a customer. |
| Recipient who later buys their own ticket and ticks the box | **Yes, from then on** | Their own act. |
| Buyer of a **resold** ticket on the native rail | **No, unless they tick the box at resale checkout** | §5.5 — an owner decision with a recommendation. |
| Comped guest | **No** | A comp is not a transaction the recipient entered into. |
| Purchaser who later withdraws | **No, from the next build onward** | §5.3. |
| Anyone, when the master switch is `block` | **No** | The kill switch overrides every per-org consent. |

`INFERENCE:` the five friends in the opening scenario are the whole point. They never met this venue. The
venue's legitimate interest in them is *admission* — get them through the door, count them, know which table
they are on — and this design serves all of that with a display name and no contact channel. The venue's
*marketing* interest in them is an interest in a stranger's inbox, and the person whose inbox it is has not
been asked. **The transferee is on the roster and off the mailing list, and that is the correct place for
them.**

### 5.3 The opt-out model — three layers, and what each is for

**Layer 1 — per-(identity, org) consent (`kernel.org_contact_consent`).** The primary gate. Default: **no row
exists**, i.e. no consent. Captured at checkout as an **unchecked** control naming the org:

> ☐ **Let {Org} email me about their events.**
> They only get your email if you tick this. You can undo it any time in Settings.

**The dark-pattern ban list of the demographics spec §2.3 is adopted here by reference and applies to this
control unchanged**: no pre-selected default, no asymmetric affordances, no burying, no reward or discount for
ticking, no penalty or degraded checkout for not ticking, no completeness nag, no social-proof framing, no
re-asking after a withdrawal, no interstitial. `INFERENCE:` adopting it by reference rather than restating it
is deliberate — two copies of a rule diverge.

**Layer 2 — the master switch (`kernel.identity_contact_pref.venue_email_contact`).** One control in
Settings: *"Stop all venue email."* Default `allow`. `INFERENCE:` this is not a consent — it is a
**revocation channel** over consents the person actively gave, which is why its default is permissive while
Layer 1's is not. It exists because a person who wants out should not have to find and untick eleven
organizations at 2 a.m.

**Layer 3 — the per-org withdrawal list.** Settings → *"Venues you've allowed to email you"* → one row per
granted org with a one-tap **Remove**, plus the master switch above it. `NEW RN SURFACE`.

**Withdrawal semantics and the honest copy.** Withdrawal sets `state = 'withdrawn'` and takes effect at the
**next export build** and immediately on every on-screen read. The confirmation says what is true:

> *"Removed. {Org} won't get your email in anything new. If they've already downloaded a list with it, we
> can't take that back."*

**Why withdrawal is a state change and not a delete — a named divergence from the demographics spec.** The
demographics spec hard-deletes a withdrawn gender answer, and is right to: a retained history of a person's
gender answers is a worse artefact than the answer. `INFERENCE:` a consent record is the opposite. It carries
no sensitive attribute — it says "this person allowed this org to email them, from this date to that date" —
and it is the **only** evidence that protects the person in the dispute they are most likely to have
("this venue emailed me and I never agreed"). Deleting it destroys the person's own evidence along with the
platform's. So: `state ∈ granted|withdrawn` with `granted_at` / `withdrawn_at`, never a row deletion, and the
row cascades away with the account. Flagged as **D-4** for acknowledgment so it reads as a considered
divergence rather than an inconsistency.

### 5.4 Does the opt-out survive a transfer?

The question dissolves once §5.2's rule is stated: **there is nothing to survive, because consent was never
attached to the ticket.** But both directions are worth stating explicitly, because both are the kind of thing
an implementer gets backwards under deadline:

- A **sender's consent does not travel** to the recipient. The recipient is not contactable.
- A **recipient's non-consent cannot be overridden** by the sender's consent. There is no code path in which
  the sender's tick-box causes the recipient's email to be emitted — the gate (§5.1) evaluates
  `(holder_identity, org)`, and the holder is the recipient.
- A **withdrawal by a purchaser** stops their own email at the next build, whether or not the tickets they
  bought are still in the room.

### 5.5 Resale — the ruling a venue will push back on

A person buys a resold ticket on the native rail. The org receives settlement from that sale. Did they become
a customer of the org?

**Recommended answer: no consent by default, and put the same unchecked opt-in on the native resale
checkout, naming the org whose event it is.** `INFERENCE:` a flat "resale grants nothing" ruling is defensible
but leaves a venue permanently unable to contact a growing share of its actual audience, which is a real
product loss that will be relitigated. Offering the same tick-box at resale checkout resolves it properly: the
default stays off, the person is asked once, in a moment where naming the venue makes sense, and consent
arrives by their own act rather than by a legal inference from a money flow. **Owner/counsel decision D-1.**

### 5.6 Reconciliation with the `public.profiles` column-grant boundary

`VERIFIED:` after 068, `authenticated` may read exactly eight public-safe columns of `public.profiles` on
**any** row, and `display_name` is one of them. So a venue staff member could already read any display name
by direct select. `INFERENCE:` this is why `display_name` is the roster's identity field and why putting a
name in a roster is not a new exposure: **the roster tells the venue *which* names are in its room, which is
the venue's own operational fact; it does not disclose a name they could not already read.**

Email is different in kind. `auth.users.email` is not in `public.profiles` at all and no client role holds any
grant on `auth.users`. The gate in §5.1 therefore runs inside a definer, and the email value **never lands in
a table a venue role can read** — it exists in exactly two places: the CSV artifact, and the on-screen cell
rendered for an audience role. There is no `venue.customer_email` table in this design, and there must never
be one: per 062's rule, a column granted to a role is readable on every row, so a materialized venue-side
email column would be an org-wide email dump the moment any grant on it existed.

The new objects follow §0 exactly: `kernel.identity_contact_pref`, `kernel.org_contact_consent`,
`kernel.org_customer_key`, `venue.export_job` all carry **zero column grants** to `anon` and `authenticated`,
with RLS enabled and no policy admitting a client role — belt and braces behind the empty grant set.

---

## 6. Export mechanics

### 6.1 Sync vs async — async always, including for sixty people

`VERIFIED:` dashboard §9.6 is binding: *"Asynchronous job, never a synchronous download."* This document
adopts it and gives the reason, because the reason determines what must not be added later:

`INFERENCE:` **uniformity is the control.** One path means one audit shape, one rate limiter, one revoke
control, one retention sweep, one re-authorization at download. A synchronous small-export path would be a
second extraction route with weaker versions of all five, and the first thing anyone would do is find the row
count that stays under it.

**Where synchronous would actually break, quantified, so the boundary is on record.** A 5,000-attendee
festival roster is ~5,000 atoms joined to orders, order items, latest scan per atom, attribution, profiles,
and a consent probe per distinct holder. At the field catalogue's widths that is roughly 600 KB–1 MB of CSV —
trivial as a file. The cost is the build: the per-atom latest-scan lookup and the per-holder consent
evaluation. Under the platform's own budgets — `VERIFIED:` the edge spec's stated wall-clock targets are
2–15 s per function — a 5,000-row build is plausible and a 50,000-row org-grain build across sixty sessions is
not, and neither is holding the result in an edge function's memory while a JWT stays alive. **The honest
threshold is a few thousand rows and a couple of seconds.** We never approach it, because we never take the
synchronous path at any size.

### 6.2 The job model

Lifecycle, exactly as the dashboard ratified it: `queued → running → ready → failed`, plus `revoked`,
`expired`, `purged`. `ready` is the only state with a download control.

| Stage | Where it runs | What it does |
|---|---|---|
| **request** | `venue.request_export` — **DB-RPC, definer** | Authorizes (in-body predicate re-check), rate-limits (fail-closed), validates the filter set against the closed grammar, resolves and **freezes `as_of` = `now()`**, writes the `venue.export_job` row as `queued`, writes the `crm_export.request` audit row **in the same transaction**. Returns `job_id`. **Builds no data.** |
| **build** | `crm-export` — **NEW EDGE FUNCTION**, `service_role` | Claims the job (`queued → running` with a lease, the 064 `webhook_event` claim-lease pattern), calls `venue.build_export_rows(job_id, cursor)` in bounded pages, serialises CSV, streams to the private bucket, computes SHA-256 as it writes. Never logs a row. |
| **finalize** | `venue.finalize_export` — **DB-RPC, definer, `service_role` only** | Records `row_count`, `byte_count`, `sha256`, `object_path`, `contact_cells_emitted/suppressed`; sets `ready`; writes the `crm_export.generate` audit row. |
| **download** | `venue.authorize_export_download` — **DB-RPC** + `crm-export` `/download` route | **Re-authorizes live, against the job's `template_id`**: re-evaluates the **request-time allow-list for that template** (§6.4) — not merely "does the caller still hold a role over the job's scope". Writes the `crm_export.download` audit row. Returns the object path; the edge mints a **300-second** signed URL. |
| **revoke** | `venue.revoke_export` — **DB-RPC, definer** | `ready → revoked` **immediately** (no further download is authorized from this instant), and sets `artifact_state = 'delete_pending'`. Writes the audit row. **It does not delete the object — a Postgres function cannot.** The object is removed by the purge route within one purge cycle (§6.6). |
| **expire / purge** | `venue.sweep_expired_exports` — **DB-RPC, definer, `pg_cron`** | Marks artifacts past retention `delete_pending` and `ready → expired`, then `expired → purged` once the purge route confirms the object is gone and the job row's own retention lapses. Each writes an audit row. **Marks; does not delete.** |
| **purge** | `crm-export` **`POST /purge` route** — `service_role`, driven by `pg_cron` + `pg_net` | **The agent that actually deletes.** Claims `delete_pending` rows, calls the Storage API `remove()`, and calls `venue.confirm_artifact_purged` on success. Also runs the orphan reconciliation pass (§6.6). |

**Why the build is an edge function and the rows are a DB-RPC.** `VERIFIED:` the edge spec's placement rule —
external I/O and secrets are edge work; pure atomic DB transitions stay in Postgres, and *"rejections are the
high-value output."* Writing an object to Storage and minting a signed URL are external I/O. Selecting rows is
not. `INFERENCE:` this split is also what makes §10 layer 2 possible: the entire SQL that touches customer data
is one named function in the catalog, inspectable by `pg_get_functiondef`, rather than a query string
assembled in TypeScript where no catalog assertion can see it.

**Scheduling.** `VERIFIED:` `pg_cron` + `pg_net` are already the house pattern (migrations 014, 032, 034 —
`cron.schedule(... net.http_post(...))` into an edge function). The build is driven the same way: a
one-minute cron drains `queued` jobs. `INFERENCE:` a cron drain rather than a direct call from the request RPC
means a crashed build is retried without an operator noticing, and it is the same claim-lease discipline that
migration 064 introduced for webhook retries after they were *"silently dropped"* (`VERIFIED:` commit
`a16a16d`). Optimistic direct invocation on request is permitted as a latency optimisation **only if** the
cron drain remains the authority — never as the only trigger.

### 6.3 `as_of` and the replayable-audit property

`as_of` is frozen at **request** time, not at build time, and is stored on the job and in the audit row.
Consequences, all of them wanted:

1. Two identical requests one second apart produce identical files (the same `as_of`, the same deterministic
   order) — so a duplicate request is diagnosable rather than mysterious.
2. A file's contents are a **deterministic function of `(scope, filters, template_version, as_of)`** plus the
   retained ledger. Therefore **the export is reproducible from its audit row**, which is what makes §9's
   erasure answer possible **without storing per-export membership**. See §9.2 — this is the single most
   important structural decision in the retention design.
3. The file is honestly stale-stamped: the CSV's first line and the download UI both name `as_of`, so nobody
   reads a Tuesday file as a Friday door list.

### 6.4 Templates

Two, closed, versioned. A template is a **fixed column list**, not a picker. `VERIFIED:` dashboard §9.6:
*"The column set is fixed per export type"*, *"No SQL box. No arbitrary column picker."*

| Template | Columns | Who (§3) |
|---|---|---|
| `audience_v1` | fields 1–12 (IDENT + OPS + CONTACT); org grain adds 13–15 | X5 — `org_owner`, `org_admin`, `org_marketing` (org grain), `venue_manager`, `venue_marketing` (venue grain) |
| `operations_v1` | `audience_v1` + fields 16–21 (MONEY), purchaser view appended as a second section | X6 — `org_owner`, `org_admin`, `venue_manager` only |

`template_version` is stamped on the job, the audit row, and the file's header comment. Adding a column bumps
it. **Removing the demographic constraint set cannot bump it — there is no template that could carry a
demographic column, because no such column exists in the catalogue.**

`promoter_name` / `promoter_code` are gated on package **090 (Phase 2D)**; until then they are **absent from
the file, not blank**, and the template version reflects it (`audience_v1` → `audience_v2` when 090 lands).
`INFERENCE:` absent-not-blank matters because a blank column in a CSV reads as "this attendee had no
promoter", which is a false operational claim.

### 6.5 Filters — a closed grammar, and the principled line on X-2

`VERIFIED:` dashboard §9.2/§9.6 — the filter set is *"a closed enumerated set … No SQL box, no arbitrary
column picker, no free-form query builder anywhere in this product."*

| Filter | Values |
|---|---|
| `session` | one or more session ids **within the anchored scope** |
| `ticket_type` | ids within the scope |
| `order_status` | `pending`·`paid`·`partially_refunded`·`refunded`·`cancelled` |
| `check_in_status` | `not_scanned`·`admitted`·`already_used`·`other_non_admit` |
| `source` | `app`·`web`·`door`·`promoter_link` |
| `promoter` | promoter ids within the scope (gated on 090) |
| `refund_state` | derived enum |
| `acquired_via` | `purchase`·`comp`·`transfer`·`resale`·`adjustment`·`import` |
| `email_present` | `true`·`false` — **allowed; see below** |
| `date_window` | a bounded `[from, to]` for venue/org grain (§7.2 caps) |

**The grammar is conjunctive only** — a set of `(field ∈ values)` clauses ANDed together. No OR, no NOT, no
nesting, no comparison operators, no free text. `INFERENCE:` a predicate *language* is how a closed filter set
stops being closed; a fixed conjunction of enumerated memberships cannot express anything its enum does not
already contain.

**Why `email_present` is permitted while a demographic filter is not — the line, stated because it shows the
constraint was understood rather than pattern-matched.** X-2's reasoning is that "export where gender = X"
discloses by construction: **the file withholds the value, so the row set becomes the value.** `email_present`
withholds nothing — the file already shows, cell by cell, whether an email was emitted. Filtering on it
reveals no fact the unfiltered file does not already state. **The rule, generalised: a filter is forbidden
exactly when the template withholds the field it selects on.** By that rule every demographic filter is
forbidden forever (no template can ever carry the field), and `email_present` is permitted, and a future
engineer has a test to apply rather than a list to memorise.

### 6.6 Storage, signed URLs, and what expiry actually buys

**No existing bucket is usable.** `VERIFIED:` from migration 073's production census — `auction-media`
(`public = true`, 134 objects), `avatars` (`public = true`, 9 objects), `proof-docs` (`public = false`, 29
objects). The two public buckets are world-readable by URL forever, and 073 says so in those words.
`proof-docs` is private but `VERIFIED:` its 033/049/053 policies grant `authenticated` folder-scoped
read/write keyed to `(storage.foldername(name))[1] = auth.uid()::text` — per-person folders, which is exactly
wrong for an artifact that belongs to an **organization** rather than to whoever clicked the button.

**`ADDITIVE SCHEMA CHANGE` — a new bucket `crm-exports`**, created **with its constraints in the same
statement and a fail-closed self-verification block**. `VERIFIED:` 073's root cause was that
`000_baseline_schema.sql` declared correct limits under `ON CONFLICT (id) DO NOTHING` against buckets that had
been created in the Storage UI first, so *"the restrictions were never applied to the live project"* and
*"every audit that read the migration source concluded the limits were in place. They were not."* This bucket
must not repeat that: no `DO NOTHING`, and a `DO $$ … $$` block that raises if the row does not hold exactly
the intended values.

| Property | Value | Why |
|---|---|---|
| `public` | **false** | Non-negotiable. |
| `file_size_limit` | **33 554 432** (32 MB) | Above any legitimate export (50 000 rows × ~200 B ≈ 10 MB), below anything worth abusing. |
| `allowed_mime_types` | **`ARRAY['text/csv']`** — exactly one | 073's own reasoning: an unrestricted MIME bucket on the platform origin hosts phishing and executes script; `text/html` and `image/svg+xml` are the named hazards. An export bucket needs exactly one type. |
| Policies for `anon` / `authenticated` | **none — zero, of any verb** | The demographics spec's *"the absence of a grant is the enforcement"*, applied to Storage. The only principal that touches this bucket is `service_role` inside the edge function. |
| Object path | `{org_id}/{job_id}.csv` | Owned by the org, not the requester — so revoking a person's role does not orphan the file and granting a new person a role does not move it. **The path carries no venue name, no event title, no date, no filter, no segment** (X-1: "not in a filename"). |

**A caveat 073 already documented and this design inherits.** `VERIFIED:` `file_size_limit` and
`allowed_mime_types` are enforced by the **Storage API**, not by Postgres — no trigger or constraint on
`storage.objects` consults them, so a direct SQL insert bypasses both. That is acceptable here for the same
reason 073 gave (client roles reach `storage.objects` only through the Storage API) **and** for a stronger
one specific to this bucket: no client role holds any policy on it at all, so there is no client SQL path to
bypass. The bucket's safety rests on the empty policy set, with size and MIME as defence in depth.

**Signed URLs — the honest answer.**

> **A 300-second signed URL bounds the window in which the *link* is redeemable. It buys nothing whatsoever
> about the *data*.** Once the CSV is on a laptop it is outside every control this platform has: revoke does
> not reach it, expiry does not reach it, erasure does not reach it, and role revocation does not reach it.
> Anyone who describes a signed URL as a privacy control for exported data is describing a promise as a
> control.

What the short expiry **does** buy, precisely — three real things, worth having:

1. **A leaked link dies fast.** URLs end up in Slack, browser history, corporate proxy logs, screenshots and
   bug reports. Five minutes bounds all of that.
2. **It makes live re-authorization meaningful.** `VERIFIED:` dashboard §9.6 requires the download to
   *"re-check authority server-side before the URL is honoured. An export prepared while the user held
   `venue_manager` and downloaded after revocation must fail."* That guarantee only holds if the check and the
   byte transfer are close together in time; a one-hour URL would let a revoked staff member redeem a
   pre-authorized link for an hour.
3. **It bounds the revocation race** to five minutes — and to `min(300 s, time-to-purge)` once the purge
   route exists, since revoke authorizes no further download from its own instant. **It does not reduce that
   race to zero**, and the earlier text implied otherwise by pairing "revoke deletes the artifact, effective
   immediately" with the correct observation that a signed URL cannot be invalidated.

What it does not buy: confidentiality of the file, deletion of the file, revocation of the file, or any
control over redistribution. **Therefore the controls that matter are all upstream of the click** — §3 (who),
§7 (how often, how much), §6.4/§6.5 (which columns, which rows), §8 (the record that outlives the file).

**Retention — and how this does not become a permanent PII lake.**

| Object | Retention | Reason |
|---|---|---|
| **The artifact** (the CSV in the bucket) | **24 hours** from `ready`, or immediately on `revoke` | The artifact is the highest-value target in the system — a bucket holding every venue's customer list. Its half-life should be an operator's attention span, not their convenience. At 24 h the bucket at steady state holds **one day** of exports, not a year of them. Extending to 7 days is **owner decision D-6**, with this document recommending against. |
| **The job row** (`venue.export_job`) | **13 months** | Long enough that a venue can answer a year-over-year question about its own export history from the panel; short enough that it is not a permanent index of who exported what. Carries **no customer rows** — only scope, filters, counts and hashes. |
| **The audit rows** (`kernel.admin_audit`) | **permanent, immutable** | §8. |

The three-line answer to "how is this not a PII lake": **the lake is bounded by a 24-hour sweep, a 32 MB
per-object cap, and a per-actor daily export cap (§7.1). No CSV older than a day exists. No table anywhere
in this design materializes a customer email.** The artifact is named as a PII sink for C34's future
inventory (§9.3), and it is deliberately the shortest-lived one on that list.

**The agent that performs the delete — because until now there was none.** `INFERENCE:` revoke said it
*"deletes the artifact, effective immediately"*, the sweep said it *"deletes artifacts past retention"*, and
`venue.revoke_export` said it *"signals the edge to delete"* — three sentences describing a mechanism that
did not exist. Both are `SECURITY DEFINER` **Postgres** functions, and a Postgres function cannot call the
Storage API. Its only in-database option is `DELETE FROM storage.objects`, which removes the metadata row and
**orphans the bytes in the backing store** — strictly worse than doing nothing, because the object survives
while every accounting says it is gone. And the `crm-export` edge function had exactly two routes, `/build`
and `/download`, **neither of which is a delete**. So retention, sweep and revoke all had **no agent**: the
"bounded by a 24-hour sweep" defence was unimplementable as specified, and revoke could not remove the file
it claimed to remove.

**The purge route.** `crm-export` gains a third route, **`POST /purge`**, `service_role`, driven the way the
build is and the way `VERIFIED:` migrations 014/032/034 already drive edge work —
`cron.schedule(... net.http_post(...))`. It is the only thing in this design that deletes bytes.

| | `POST /purge` |
|---|---|
| **Trigger** | `pg_cron`, every 15 minutes, via `pg_net` — the same in-database HTTP pattern the build uses |
| **Claims** | `venue.claim_artifacts_for_purge(p_limit int)` — definer, `service_role` only. Returns a bounded page of `(job_id, object_path)` for jobs in `artifact_state = 'delete_pending'`, taking the 064 claim lease so two overlapping runs cannot double-work |
| **Acts** | Storage API `remove([object_path])` per claimed row. **A 404 from Storage is success**, not an error — the object is gone, which is the goal |
| **Confirms** | `venue.confirm_artifact_purged(p_job_id, p_outcome)` — definer, `service_role` only. Sets `artifact_state = 'deleted'`, advances `ready → expired → purged` where retention allows, writes `crm_export.purge` |
| **Fails** | leaves the row `delete_pending` with the lease expired, so the next cycle retries. **A delete that never succeeds is an alarm, not a silent gap** — a job `delete_pending` for more than 3 cycles raises a `platform_risk` signal |
| **Logging** | job ids, counts, durations. Never a path with a customer's data in it — the path is `{org_id}/{job_id}.csv` by design (§6.6), which is why it is loggable at all |

**The orphan reconciliation pass**, run by the same route once per day. `INFERENCE:` a mark-then-delete design
has exactly one new failure mode — the mark is lost while the object is not — and it is the failure mode
whose symptom is *a customer list nobody knows about*. The pass lists `crm-exports` objects under each
`{org_id}/` prefix and compares them against `venue.export_job`:

| Condition | Action |
|---|---|
| Object exists, no job row (job purged, or the row was never written) | **Delete the object.** Write `crm_export.purge` with `reason_code = 'orphan_no_job'` |
| Object exists, job row says `artifact_state ∈ {deleted, absent}` | **Delete the object.** `reason_code = 'orphan_state_mismatch'` — the accounting said gone and it was not |
| Object exists, job row is `ready` and inside retention | Leave it. This is the normal case |
| Job row says the artifact is present, no object | Set `artifact_state = 'deleted'`; alarm if the job is `ready` (a `ready` job with no bytes will fail a download) |

The pass is **the only reason the 24-hour bound is a statement about the bucket rather than about the job
table.** Without it the retention claim is a claim about rows, and rows are not what leaks.

**What revoke can and cannot do, restated honestly.** Revoke is `ready → revoked` **in the same transaction**,
so **no further download is authorized from that instant** — that part is immediate and is the part that
matters. The **object** is removed within one purge cycle (≤ 15 minutes), not instantly. And a signed URL
already minted **remains redeemable until the object is actually deleted**, for at most its 300-second life:
§6.6 says correctly that a signed URL cannot be invalidated, then relied on a delete the design could not
perform. So the honest bound on the revocation race is **min(300 s, time-to-purge)**, not zero, and the
operator-facing copy must not say "effective immediately" about the file.

### 6.7 EX-rules (standing rules for this surface)

> **EX-1** — Every export is **anchored on one scope object** (`session` · `event` · `venue+window` ·
> `org+window`). `scope_kind = 'all'` is not a member of the enum.
> **EX-2** — Every export is **asynchronous**, at every size. There is no synchronous download path and none
> may be added.
> **EX-3** — The column set is a **versioned template**, never a picker. The filter set is a **closed
> conjunctive grammar over enumerated memberships**, never a predicate language.
> **EX-4** — The download **re-authorizes live**, on every download, against live grant tables — **and it
> re-evaluates the request-time allow-list for the job's `template_id`, not just the role set.** Whoever may
> download a job is exactly whoever may have requested it, evaluated now. `INFERENCE:` a role set is not an
> authorization; the pair `(role set, template)` is. The two allow-lists differ — X6's is the narrowest in
> the matrix — so re-checking only the role set authorizes the wrong thing and does it convincingly.
> **EX-5** — Every state transition writes `kernel.admin_audit` **in the same transaction**.
> **EX-6** — **There is no third-party destination.** No webhook, no CDP, no ESP, no ad platform, no
> warehouse, no scheduled email, no venue-configurable URL of any kind. The only egress is a signed download
> to the requesting operator. `INFERENCE:` this is the same posture **C40** takes for `validation_callback`
> egress — *"restricted to a static, platform-controlled allowlist (never provider/venue-supplied); CI
> asserts the adapter's kernel REVOKE."* Adding an egress destination to CRM export is a **C40-class change**
> and inherits C40's requirements in full: a static platform-controlled allowlist and a CI-asserted revoke.
> It is not built, not designed, not stubbed.
> **EX-7** — Over a cap, a job **fails with `too_large` and names the narrower scope**. It never truncates
> silently. `INFERENCE:` a silently truncated export is worse than a failed one — the operator acts on a
> partial list believing it complete.

---

## 7. Rate limits and abuse controls

`VERIFIED:` the platform already has the primitive — `public.check_rate_limit(user, action, max, window)`,
**fail-closed** (migration 021 replaced a fail-open implementation; the edge spec requires 503 on limiter
error, 429 on over-limit, both with `Retry-After`, and *"never silently disable abuse protection"*).

### 7.1 Per-actor and per-org limits

| Action | Limit | Window | Reasoning |
|---|---|---|---|
| `crm_export_request` **per actor** | **5** | 24 h | An operator legitimately exports a guest list once, maybe twice, per night. Five is generous, and it makes "paginate the org by re-scoping repeatedly" cost five requests a day. |
| `crm_export_request` **per org** | **25** | 24 h | Bounds a compromised org with many staff accounts — the per-actor limit alone is defeated by five accounts. |
| `crm_export_download` **per actor per job** | **3** | job lifetime | A download that fails twice is a bug; a job downloaded forty times is a redistribution channel. |
| `crm_export_download` **per actor** | **10** | 24 h | |
| `attendee_list_page` **per actor** | **240** | 1 h | The on-screen list is paginated at 50; 240 pages/h is 12 000 rows/h — above any human reading, below a scraper. `INFERENCE:` without this, the screen is an unaudited export with extra steps. |
| **`attendee_lookup_by_email`** **per actor** | **40** | 24 h | **The sharpest limit in this document.** See §7.2. |
| **`attendee_lookup_by_email`** **per org** | **120** | 24 h | **Added.** The per-actor cap alone is defeated by three accounts, and this is the table that says so two rows above about exports: *"the per-actor limit alone is defeated by five accounts."* The same reasoning had not been applied to the lookup. |
| **`attendee_lookup_by_name_prefix`** **per actor** | **20** | 24 h | **Added — there was no row at all.** See §7.2. |
| **`attendee_lookup_by_name_prefix`** **per org** | **60** | 24 h | **Added**, same reasoning. |
| `attendee_lookup_by_order_ref` per actor | 200 | 24 h | Order refs are opaque and possessed by the customer; the probe is not a harvest oracle. |
| `attendee_lookup_by_order_ref` **per org** | **600** | 24 h | **Added** for uniformity — every lookup kind has both caps, so a new kind added later has an obvious shape to copy rather than a choice to make. |
| `contact_consent_write` per identity | 60 | 24 h | Fan-side; prevents a consent-flapping loop. |

**Every lookup kind is limited per actor *and* per org.** `INFERENCE:` the per-org cap is not a second-order
refinement — the downstream RPC contract scoped the limit to `email_exact` **explicitly**, so both other
kinds were unlimited in the contract even where the table implied otherwise, and the whole family shared one
per-actor ceiling that three colluding or compromised accounts walk straight through. The rule is stated as a
rule so the next kind inherits it: **no lookup kind ships without both caps and an audit-by-kind row.**

All limits live in `catalog.platform_config` (seeded in package **087/I**) and are **read live**, so a limit
can be tightened without a deploy. `INFERENCE:` they are readable-tunable in one direction by intent — a
loosening is an audited config change with an actor on it, which is exactly the visibility a loosening
deserves. `VERIFIED:` `catalog.set_platform_config` is already an audited RPC.

### 7.2 The email-lookup oracle — named, because it is the real hole

`VERIFIED:` dashboard §9.2 already ratified exact-match email search on the attendee surface and already
refused substring search: *"No email substring search — substring search over emails is a directory-harvesting
affordance and this surface will not have one."*

`INFERENCE:` exact-match search is still an **existence oracle**. A venue that types `alice@example.com` and
gets a hit has learned that Alice holds a ticket to their show — about a person who may be a transferee with
no relationship to that venue and no contact consent. At one query it is a box-office service action ("I'm on
the list under this email"). At four thousand queries a day it is a directory attack that confirms attendance
for an arbitrary email list.

**The resolution: split the surface by what it is used for.**

- **Permitted:** `venue.lookup_attendee(session, query_kind ∈ {email_exact, order_ref, name_prefix}, value)`
  — **one record**, service context, for `venue_manager`, `venue_box_office`, `org_owner`, `org_admin`,
  `platform_support`. Every call is **audited with the query kind** (never the query value for `email_exact`
  or `name_prefix` — logging the probed string would create the harvest list inside our own audit) and
  rate-limited **per actor and per org, for every kind** (§7.1).
- **Forbidden:** email is **not** an export filter, **not** a bulk match key, and **not** a suppression key.
  There is no "upload a list and tell me who's coming" surface, in any form, ever.
- **Denied to marketing.** X4 marks `OMK`/`VMK` as `·`. `INFERENCE:` the probe is a *service* tool for a
  person standing at a counter with a customer in front of them. Marketing has no such moment, and marketing
  is the role with the standing incentive to run a list.

**Flagged as owner decision D-5** — the numbers are a judgement, and the owner may want them lower for
marketing-heavy orgs or higher for a large festival box office. Whatever the numbers, the *shape* (per actor
**and** per org, fail-closed, audited by kind, denied to marketing) should not change.

### 7.2a `name_prefix` — the same oracle with no limit at all

`INFERENCE:` §7.2 named the email probe as "the real hole" and then left the sharper one open. The limit
table had rows for `attendee_lookup_by_email` and `attendee_lookup_by_order_ref` and **none for
`name_prefix`**, and the RPC contract scoped its limit to `email_exact` **explicitly** — so the prefix probe
was rate-limited by nothing, in a design whose own §3.1 states, deliberately, that *"a box office cannot
print a paper list. That is deliberate."*

`venue_box_office` holds X4. Iterating `a…z`, then `aa…zz`, then `aaa…zzz` against one session returns the
roster **one record at a time at no rate cost** — the printed list §3.1 refuses, reassembled from the surface
that was supposed to replace it, by the exact role that was denied it. Three rules close it, and all three
are needed:

**1. Rate limits.** `attendee_lookup_by_name_prefix` at **20 per actor per 24 h** and **60 per org per
24 h** (§7.1). Deliberately below the email cap: an email probe needs an address the prober already has,
while a prefix probe needs nothing but the alphabet, so the cheaper attack gets the tighter budget. The same
fail-closed `check_rate_limit` primitive (005/021): **429 over limit, 503 on limiter error, never a silent
pass**.

**2. A minimum prefix length of 3 characters.** Shorter raises `prefix_too_short`, before any lookup and
without consuming the rate budget — `INFERENCE:` charging for a rejected call would turn the limiter into a
denial-of-service against the box office, and the call reached no data. Three characters means the
26-letter sweep is 17 576 probes rather than 26, against a budget of 20, and it also matches the real service
moment: a customer at a counter says a name, not a letter.

**3. Multi-match is an explicit error carrying no rows and no count.** More than one match raises
`ambiguous_query` — **no rows, no count, no "3 matches, please refine", no partial list, no first result.**
`INFERENCE:` a count *is* the harvest. `"sm" → 14` and `"smi" → 9` reconstruct the roster's name distribution
without ever returning a record, and a design that returns rows only for unique matches while returning
counts for the rest has simply changed the units the attacker collects in. The error names the *kind* of
failure and nothing about the data. The operator's path is to ask the customer for more of their name, which
is what they were going to do anyway.

**Audited by kind, never by value.** `crm_lookup.attendee` records `(actor, session, query_kind, outcome ∈
{hit, no_match, ambiguous, rate_limited, prefix_too_short})` and **never the probed string** — for
`name_prefix` for the same reason as for `email_exact`: storing the probes builds the harvest list inside
`kernel.admin_audit`, the one table nobody can ever purge. The `ambiguous` and `rate_limited` outcomes are
the interesting ones: **a run of them is what an alphabet sweep looks like**, and they feed the §7.4 anomaly
signal.

### 7.3 Volume caps

| Cap | Value | Over-cap behaviour |
|---|---|---|
| Max rows per export | **50 000** | `failed` with `too_large`; the message names the narrower scope (EX-7) |
| Sessions per export — session grain | 1 | rejected at request |
| Sessions per export — venue/org grain | **60** | rejected at request |
| Date window — venue grain | **180 days** | rejected at request |
| Date window — org grain | **365 days** | rejected at request |
| Concurrent `running` jobs per org | **2** | queued behind |

### 7.4 The rest of the abuse surface

| Vector | Defence |
|---|---|
| **Paginating a whole org through repeated narrow exports** | Per-actor 5/day and per-org 25/day. At 50 000 rows × 5 = 250 000 rows/day/actor, a large org is still weeks of work, every request audited and visible in its own activity feed. |
| **Scraping the on-screen list instead** | `attendee_list_page` 240/h, audited. The screen is not a cheaper export. |
| **Confirming attendance for a supplied email list** | §7.2 — 40/day per actor, 120/day per org, audited by kind, denied to marketing, and no bulk match surface exists. |
| **Reassembling the roster by iterating name prefixes** | §7.2a — 20/day per actor and 60/day per org (there was **no limit row at all**, and the RPC scoped its limit to `email_exact` explicitly), a 3-character minimum, and multi-match as an explicit `ambiguous_query` carrying **no rows and no count**. This is the surface that would otherwise have handed `venue_box_office` the printed list §3.1 denies it, one record at a time, at no rate cost. |
| **A run of `ambiguous` / `rate_limited` lookup outcomes** | The signature of an alphabet sweep, and the only evidence of one — the probed strings are deliberately never stored. Feeds the volume-anomaly signal below. |
| **A revoked staff member downloading a pending job** | EX-4 live re-authorization at download (already binding). |
| **A marketing actor downloading a colleague's *operations* export** | EX-4 re-evaluates the **request-time allow-list for the job's `template_id`**, not just the role set (§11.4). `org_marketing` holds X10 and can see the `job_id`; without the template limb the role-set re-check passed and handed it order totals, unit prices and refund state alongside the contact column it already had. |
| **A staff member exporting on their last day** | Not preventable, and saying otherwise would be dishonest. What exists: the audit row is permanent and names them, the anomaly signal below fires, and the artifact dies in 24 h. This is a *detection* control, and it is labelled as one. |
| **Volume anomaly** | An actor whose 7-day export volume exceeds **3× their trailing 90-day median** raises a `platform_risk` signal. `INFERENCE:` a **signal, not a block** — blocking a venue's guest list at 10 p.m. on a false positive is worse than the risk it prevents. |
| **A compromised finance / door / promoter / box-office / support account** | Those roles hold no export and no contact read (§3). The blast radius of the most commonly compromised accounts is zero contact rows. |
| **A future engineer adding a filter or a column** | The template and filter grammar are versioned contracts asserted by pgTAP (§12 assertions 20–22); the demographic case is additionally caught by §10. |
| **PII escaping through logs or observability** | The builder never logs a row. `VERIFIED:` the edge spec's standing rule — *"never log secrets, tokens, client_secrets, key material, card/bank data, or PII."* Restated for this function as: the only loggable quantities are counts, ids and durations. |
| **Demographic data escaping through the export** | X-1…X-9 (§2.4) with §10 as the enforcement. |

---

## 8. Audit model

### 8.1 Where audit lives, and why not with the venue

Every export event writes to **`kernel.admin_audit`**. `VERIFIED:` schema §1.12 — append-only, guard trigger,
`REVOKE UPDATE, DELETE`, permanent, tamper-evident (Audit Storage per CDM §5), readable only by `is_platform`.

`INFERENCE:` the audit must not live in a venue-owned table, because the actor most likely to want an export
record gone is the venue. `kernel.admin_audit` is the only object in the corpus a venue can neither read
directly nor modify at all, and that is precisely the property required.

The venue's own **export history panel** reads a **projection** of those rows through the dashboard's Δ2
`venue.list_activity` RPC — `VERIFIED:` dashboard §17.3 already lists *"export requested / generated /
downloaded / revoked"* among the covered actions, and §17.2 already forbids that surface from rendering
`before`/`after` payloads or anything from the security plane. Nothing new is needed on the venue side.

### 8.2 The actions

`crm_export.request` · `crm_export.generate` · `crm_export.download` · `crm_export.revoke` ·
`crm_export.expire` · `crm_export.purge` · `crm_export.fail` · `crm_export.denied` ·
`crm_contact.consent_granted` · `crm_contact.consent_withdrawn` · `crm_contact.pref_changed` ·
`crm_lookup.attendee`

`crm_export.denied` is included deliberately: `INFERENCE:` a refused export attempt is more interesting than a
successful one, and an audit that only records successes cannot show an attacker probing scopes.

### 8.3 What each row records

`actor_identity` (server-derived, C35), `action`, `subject_kind = 'crm_export'`, `subject_id = job_id`,
`reason_code`, `occurred_at`, plus in the `after` payload:

| Field | Why |
|---|---|
| `scope_kind`, `scope_id` | What was reachable. |
| `template_id`, `template_version` | Which columns existed at the time. |
| `filters` — **normalized and sorted** | So two audit rows are comparable and a replay is deterministic. |
| `as_of` | With the above, makes the file reproducible (§6.3). |
| `row_count`, `byte_count` | Volume, for the anomaly signal and for the operator's own history. |
| `artifact_sha256` | So a file produced later in a dispute can be proven to be — or **not** be — the one this venue exported. `INFERENCE:` this is the cheapest useful forensic artefact available and it costs 32 bytes. |
| `contact_cells_emitted`, `contact_cells_suppressed`, `name_cells_emitted`, `name_cells_suppressed` | **The only evidence the consent gate ran** on this export (§5.1). Four integers, not two: the gate governs the name column as well as the email column (§4.3), and a per-column pair is what shows *which* limb ran. **Accumulated in the database by `venue.build_export_rows`, never supplied by the worker** — see §11.4. |
| `constraint_set_version` | **X-9.** The identifier of the X-1…X-9 constraint text in force, from `catalog.platform_config['crm_export.constraint_set_version']`, e.g. `demographics-constraints/X1-X9@v1`. |

**Never in an audit row:** a customer row, a name, an email, a `customer_ref`, a probed email value, an
`org_customer_key`, or any signed URL.

### 8.4 The auditor's query

X-9 exists so a future auditor can show the constraint was live at the time of every export. Concretely:

```text
-- "Show me every CRM export, who took it, how big it was, and which
--  demographic constraint text was in force when they took it."
select occurred_at, actor_identity,
       after->>'scope_kind', after->>'scope_id',
       after->>'template_version', (after->>'row_count')::int,
       after->>'constraint_set_version'
  from kernel.admin_audit
 where action = 'crm_export.generate'
 order by occurred_at;
-- Zero rows with a NULL constraint_set_version is the assertion. (pgTAP 24.)
```

### 8.5 Immutability, and one honest over-report

The audit row survives everything else: the artifact being deleted, the job row being purged, the staff member
being revoked, the venue being archived, the event ending. `VERIFIED:` `kernel.admin_audit` is AO with a guard
trigger and revoked UPDATE/DELETE, and CDM §10.1 makes ledger deletion constitutionally illegal.

**The one honest over-report.** The `download` audit row is written in the same transaction that authorizes
the URL, **before** the URL is returned. If the network then fails, the audit says a download happened when no
bytes arrived. `INFERENCE:` this is the correct direction for an audit to be wrong — it over-reports access
rather than under-reporting it — and the alternative (a client-confirmed download callback) would be an
attacker-controlled audit, which is worse than an imprecise one. **The audit records that a URL was issued,
not that bytes reached a laptop.** Say so in the history panel's tooltip rather than letting an operator infer
a precision that is not there.

---

## 9. Erasure, and the honest Phase-2 promise

### 9.1 The situation

A user deletes their account. A venue exported them last month. `VERIFIED:` **C34 (provable erasure) is
RATIFIED-MODELED-ONLY (GATE-L), spec at Gate P, and is not built in Phase 2.** `VERIFIED:` CDM §4: *"No
GDPR/CCPA erasure claim is made before C34 is implemented."*

### 9.2 What Phase 2 can actually do, and what it cannot

| Can | Cannot |
|---|---|
| Remove the person's contact rows and preferences (cascade from `auth.users`) | Reach a CSV on someone's laptop |
| Stop emitting them in anything built from now on | Prove a venue deleted them from a file |
| Say **which venues exported a list they were on, and when** — reconstructed from the audit row + the retained ledger, **without ever having stored per-export membership** (§6.3) | Answer that question **after** erasure — see below |
| Delete the artifact from our own bucket **within one purge cycle** — ≤ 15 min on revoke, ≤ 24 h + one cycle otherwise (§6.6) | Undo a redistribution |
| Prove the artifact is gone from **our** bucket, via the orphan reconciliation pass (§6.6) | Delete it *instantly* — a Postgres function cannot call Storage, so the delete is a route, not a transaction |

**Why membership is not stored, and what that costs.** The obvious design is
`export_job_member(job_id, identity_id)` — a precise answer to "which exports contained me". It is rejected.
`INFERENCE:` it would create a permanent, growing map of identities to extractions — a new PII sink, a
retained re-identification graph (exactly C34's third mandatory part), and an artefact that outlives the
export it describes. The replayable-audit property (§6.3) gets the same answer from data we are already
required to keep: the ledger is retained for financial reasons, the audit row pins
`(scope, filters, template_version, as_of)`, and the builder is deterministic — so **the membership question
is answered by replaying the builder, not by having stored the answer.**

**The cost, stated honestly.** After erasure, the replay no longer produces the erased person's row.
`VERIFIED:` the live account-deletion path (migrations 019/020) repoints ledger-referenced rows to the
anonymized sentinel `00000000-0000-0000-0000-000000000000`; once `current_owner_id` is the sentinel, "was I in
that file" is unanswerable. **That is not a bug and it should not be fixed.** Being able to answer it forever
would mean we had kept the link we just promised to remove. The product answer is to **offer the disclosure
before deletion**, not to keep the data after it:

> `NEW RN SURFACE` — in the account-deletion flow, before the confirm step: *"Before you go: some venues have
> downloaded lists that included you. See which ones."* One screen, listing `(org, date)` pairs, generated on
> demand, never stored. After deletion this screen is gone, and the copy says so.

`INFERENCE:` this is a small surface that converts an unanswerable post-hoc question into an answerable
pre-hoc one, which is the only honest way to serve it.

### 9.3 The honest Phase-2 promise (plain language, binding copy)

Written in the same register the demographics spec used for its own erasure promise, and deliberately making
**no** claim C34 has not earned. No regime names, no "GDPR-compliant", no "erased forever".

> **"When you delete your account, we remove your personal details from Snatch It and stop including you in
> anything new. We can't reach into a file a venue already downloaded. Once a spreadsheet is on someone's
> computer it's theirs — the same as if they'd written your name down at the door. Here's what we do instead:
> we keep a permanent record of every list a venue exports, so before you delete your account we can show you
> which venues downloaded a list that included you and when. Our terms require them to delete you from those
> files, and we'll pass your request on, but we can't prove they did it — anyone who tells you otherwise is
> guessing. Files we generate are deleted from our own systems within a day. Encrypted backups of our database
> are kept for {N} days for disaster recovery; we don't read them, and your details age out of them. If we
> ever restored from one, we re-apply deletions as part of the restore."**

`{N}` is the same backup-retention window the demographics spec left as its **D-6**; this document does not
create a second one. **The copy cannot ship with a placeholder.**

**Phase-2 posture toward C34, for the record.** This feature is designed to make C34 easier at Gate L:

| C34 part | This design's contribution |
|---|---|
| Per-identity DEK lifecycle | Contact data lives in two small tables keyed on `auth.users(id)` with one owner-scoped read path each — a trivially enumerable encryption target. Email is **never materialized** in a venue-side table at all. |
| **PII-sink inventory + purge** | The sink list is **closed, short, and written down here**: `kernel.identity_contact_pref`, `kernel.org_contact_consent`, the `crm-exports` bucket artifact (24 h), and the on-screen render. No third-party destination (EX-6), no notification payload, no search index, no cache, no warehouse. |
| Retained-graph re-identification | The export stores **no membership** (§9.2) and emits **no global identity id** (XO-2), so no retained identity↔export edge exists in the graph. |
| 7-year financial retention | Contact consent is not a money object and appears in no settlement, payout, refund or order-money row, so the retention obligation and contact erasure never conflict. |

### 9.4 Interaction with C38 (identity merge, GATE-L)

`VERIFIED:` C38 is GATE-L and not built. Its contact rule is fixed here so it is not decided ad hoc, mirroring
C38's own *"conflicts fail closed to the narrower capability"*:

> **A merge never unions contact permissions upward.** For each org, the survivor's consent is `granted` only
> if **both** identities held `granted`; if either was `withdrawn` or absent, the survivor is `withdrawn` or
> absent. The master switch resolves to the **more restrictive** of the two (`block` wins). `customer_ref` is
> recomputed for the survivor, and the non-survivor's ref is **not** aliased forward — `INFERENCE:` aliasing
> it would hand every org that ever exported the non-survivor a stable link between two pseudonyms they were
> never meant to connect, which is the one thing XO-2 exists to prevent.

**Consequence, accepted:** a merged customer looks like a new customer to every org's CRM. That is a real loss
of continuity and it is the correct trade against re-linking.

### 9.5 Constraint on whoever next edits migration 020

`VERIFIED:` `delete_account_cleanup` repoints ledger-referenced rows to the anonymized sentinel.
`kernel.identity_contact_pref` and `kernel.org_contact_consent` must **cascade** from `auth.users`, never be
repointed to the sentinel — a sentinel row holding "consent granted to 40 orgs" would be an accumulating
grant belonging to nobody, and the gate in §5.1 would evaluate it. Same shape as the demographics spec's
D-11. Recorded as **D-3** and as edit **K-6** in §11.7.

---

## 10. The X-6 CI check

**The requirement (X-6, verbatim):** *"The export builder's SQL contains zero references to
`kernel.identity_demographic`, `kernel.identity_demographic_erasure`, `venue.holder_mix_snapshot`, or
`venue.holder_mix_bucket`. This is CI-checkable and must be a CI check (grep the export builder + a catalog
assertion, pgTAP assertion 27)."*

Specified in four layers. **Each layer catches something the others miss, and each is named with its own
failure mode** — `INFERENCE:` a check whose blind spot is undocumented is a check people trust past its edge.

### 10.1 Layer 0 (structural, recommended) — a privilege wall

Make the reference **impossible**, not merely detectable.

`venue.build_export_rows` is `SECURITY DEFINER` owned by a narrow role **`crm_export_builder`** rather than by
`postgres`. That role is granted `SELECT` on exactly the enumerated roster relations (§1.4) and on
`kernel.identity_contact_pref` / `kernel.org_contact_consent` / `kernel.org_customer_key`, and holds **zero
grant of any kind on the four demographic objects**. A reference to them is then a **runtime permission
error**, discovered by the first test that runs the builder — no CI check required to find it, and no future
engineer can add one that works.

**Cost, stated honestly, because it is a real deviation.** `VERIFIED:` the RPC spec's §0 global is
`SECURITY DEFINER` owned by `postgres`. A second definer owner is a deviation, and it needs plumbing: the
roster relations are owned by `postgres`, so `crm_export_builder` is subject to their RLS and needs an
explicit permissive policy naming that role on exactly those relations. That is a handful of extra policy
lines and a second owner to keep track of. `BYPASSRLS` on the role is **not** an acceptable shortcut — it
would restore access to everything and delete the entire benefit.

**Recommendation: adopt Layer 0.** `INFERENCE:` it converts X-6 from a rule that is checked into a rule that
cannot be broken, which is the same upgrade C36 made for role scoping ("a type error, not a lint finding") and
which the demographics spec made for its bucket floor (a CHECK constraint rather than a render rule).
Flagged as **D-2** because it edits a frozen global. If rejected, layers 1–3 stand alone and §10.2's
empty-file-set guard becomes load-bearing rather than merely important.

### 10.2 Layer 1 — the source grep (CI, every PR)

A script, `scripts/ci/assert-no-demographics-in-export.mjs`, wired into the existing CI workflow as a
required check.

**Inputs, all from one shared constants module** (`scripts/ci/demographic-objects.json`) that the demographics
migration package **also** reads, so a rename cannot silently defeat the grep:

```text
FORBIDDEN_IDENTIFIERS = [
  "kernel.identity_demographic", "identity_demographic",
  "kernel.identity_demographic_erasure", "identity_demographic_erasure",
  "venue.holder_mix_snapshot", "venue.holder_mix_bucket", "holder_mix",
  "gender_identity", "another_gender_identity", "prefer_not_to_say",
  "non_binary", "holders_responded", "holder_count", "suppression_reason"
]

SCANNED_PATHS = [
  "supabase/migrations/*crm_export*.sql",
  "supabase/migrations/*attendee*.sql",
  "supabase/migrations/*contact_consent*.sql",
  "supabase/functions/crm-export/**/*.ts",
  "supabase/functions/crm-export/**/*.sql",
  "docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md"    -- self-check, see below
]
```

**Rules, in order of importance:**

1. **FAIL if `SCANNED_PATHS` resolves to an empty file set.** `INFERENCE:` **this is the most important line
   in the check.** A grep over nothing passes, silently, forever — and this repository has already been bitten
   by exactly that class of bug: `VERIFIED:` migration 073's root cause was *"a bare UPDATE reports success
   when it matches zero rows,"* and *"every audit that read the migration source concluded the limits were in
   place. They were not."* The check must assert it scanned something, and print the file list it scanned, on
   every run.
2. **FAIL if any `FORBIDDEN_IDENTIFIERS` entry appears in any scanned file**, printing `file:line:match`. The
   one permitted exemption is this document's own §2.4 and §10 (which must name the objects to forbid them) —
   handled by an explicit `-- x6-allow: naming-only` marker on those lines, and the marker itself is counted:
   more than the expected number of markers fails.
3. **FAIL if the `FORBIDDEN_IDENTIFIERS` list does not appear anywhere else in the repository.** `INFERENCE:`
   if the demographic objects have been renamed, the grep is now looking for strings that no longer exist and
   would pass vacuously. This rule makes the check fail loudly at the rename instead of quietly at the leak.
4. **FAIL if any scanned SQL file contains dynamic SQL** — `EXECUTE`, `format(`, `quote_ident(` — inside a
   function whose name matches the export builder set. `INFERENCE:` **dynamic SQL is the actual hole.** A
   `format()`-assembled query has no catalog dependency for Layer 3 to see and can be assembled from fragments
   that Layer 1's literal match misses. Forbidding it outright in the builder is cheaper than trying to
   analyse it, and the builder has no need for it: the template is fixed and the filter grammar is a closed
   conjunction that a static query with parameter arrays expresses fine.

### 10.3 Layer 2 — catalog assertion (staging verification, per package)

Run in the export package's `verify` step, per the migration plan's expand → verify → adopt → contract
discipline.

```text
-- (a) Textual: no export function's definition mentions a demographic object.
select p.proname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('venue','kernel')
   and p.proname in ('request_export','build_export_rows','finalize_export',
                     'authorize_export_download','revoke_export','list_attendees',
                     'lookup_attendee','list_export_jobs','sweep_expired_exports')
   and pg_get_functiondef(p.oid) ~* '(identity_demographic|holder_mix|gender_identity)';
-- must return zero rows

-- (b) Structural: no export function has a catalog dependency on a demographic relation.
--     Resolve pg_depend from the export pg_proc oids to pg_class, intersect with the four
--     demographic relations. Must be empty.

-- (c) Non-vacuity: assert that (a) and (b) actually saw the nine functions.
--     If count(*) <> 9, FAIL — the same empty-set guard as Layer 1 rule 1.
```

**Why (a) and (b) are both required, stated because it is the crux:** (a) catches a reference built through
dynamic SQL, which has **no** catalog dependency for (b) to find. (b) catches a reference reached through a
**view** or a nested function, which (a)'s regex on the outer function body never sees. **Neither alone is
sufficient**, and a reviewer who drops one because "the other covers it" has reopened the hole.

### 10.4 Layer 3 — pgTAP

The demographics spec's assertion 27 is a **reader enumeration**: the set of functions/views/matviews
referencing `kernel.identity_demographic` is exactly
`{get_my_demographics, set_my_demographics, clear_my_demographics, refresh_holder_mix}`. This document adds
the mirror for the rollup objects: the set referencing `venue.holder_mix_snapshot` / `_bucket` is exactly
`{refresh_holder_mix, get_holder_mix, <the nightly reconciliation job>}`. **Any export function appearing in
either set fails the suite.** Listed as assertions 25–27 in §12.

### 10.5 What the four layers do and do not guarantee

**Do:** no export function reads a demographic object, by any route the catalog or the source can see; a
rename cannot silently defeat the check; an empty scan cannot pass.

**Do not:** stop a human from typing a demographic value into a spreadsheet by hand after reading the
on-screen card. Nothing can. That path is bounded by the card itself never showing an individual value
(demographics §7.1) and by the aggregate being suppressed below k = 25 — which is a property of that spec, not
of this one, and is exactly why it is a property of that spec.

---

## 11. Deltas — classification, packages, schema, RLS, RPC, Edge

### 11.1 Package map and classification

`VERIFIED:` the migration plan's own headings are `073–088`, but production hotfixes consumed `073/074/075` on
`main` (`VERIFIED:` `supabase/migrations/` ends at `075_replay_parity_storage_policies_and_cron.sql`), and a
renumber is in flight on `phase2/renumber`. This document therefore uses the **+3 map the demographics spec
adopted** and, per the role-model spec's OD-10 warning, **names every package by its mandated phase letter as
well as its number** so it survives the renumber.

| # | Letter | Package content |
|---|---|---|
| 076 | **A / B-1** | schemas + GRANT boundary + shared helpers |
| 077 | **B** | `kernel.identity_ext`, `organization`, `org_member`, `platform_role`, `admin_audit` + org/platform predicates |
| 078 | **C** | `catalog.venue`, `event`, `event_session`, `platform_config`, `resale_policy` |
| 079 | **D** | `kernel.tickets`, `kernel.ticket_ownership_log` |
| 080 | **E-1** | `venue.staff_role` + venue/event predicates |
| 081 | **E-2** | venue inventory |
| 082 | **F** | `venue.order`, `venue.order_item` |
| 083 | **G-1** | `kernel.signing_key` |
| 084 | **G-2** | late-binding FK adopt |
| 085 | **F/I bridge** | `kernel.payment_native`, `refund`, `payout` |
| 086 | **H** | `venue.door_pin`, `scan_device`, `scan`, comps, guest lists |
| 087 | **I** | `venue.settlement`, `settlement_line` |
| 088 | **J-1** | market native rail |
| 089 | **J-2** | bridge view + late FK |
| 090 | **2D** | `venue.promoter`, `promoter_link`, `attribution` |
| 091 | **K** | `kernel.reserve` stub |

| # | Element | Classification | Package |
|---|---|---|---|
| 1 | `kernel.identity_contact_pref` | `ADDITIVE SCHEMA CHANGE` | **077 / B** |
| 2 | `kernel.org_customer_key` | `ADDITIVE SCHEMA CHANGE` | **077 / B** |
| 3 | `kernel.get_my_contact_prefs()` | `NEW RPC` | **077 / B** |
| 4 | `kernel.set_my_contact_prefs(...)` | `NEW RPC` | **077 / B** |
| 5 | `kernel.org_contact_consent` | `ADDITIVE SCHEMA CHANGE` | **082 / F** |
| 6 | `kernel.grant_org_contact_consent(...)` | `NEW RPC` | **082 / F** |
| 7 | `kernel.withdraw_org_contact_consent(...)` | `NEW RPC` | **082 / F** |
| 8 | `kernel.list_my_org_contact_consents()` | `NEW RPC` | **082 / F** |
| 9 | `venue.list_attendees(...)` — holder-grain, column-scoped | `NEW RPC` (satisfies dashboard Δ3) | **087 / I** |
| 10 | `venue.lookup_attendee(...)` | `NEW RPC` | **087 / I** |
| 11 | `venue.export_job` | `ADDITIVE SCHEMA CHANGE` | **087 / I** |
| 12 | `storage.buckets` row `crm-exports` + zero client policies | `ADDITIVE SCHEMA CHANGE` | **087 / I** |
| 13 | `venue.request_export(...)` | `NEW RPC` | **087 / I** |
| 14 | `venue.build_export_rows(...)` | `NEW RPC` (definer/`service_role` only) | **087 / I** |
| 15 | `venue.finalize_export(...)` | `NEW RPC` (`service_role` only) | **087 / I** |
| 16 | `venue.authorize_export_download(...)` | `NEW RPC` | **087 / I** |
| 17 | `venue.revoke_export(...)` | `NEW RPC` | **087 / I** |
| 18 | `venue.list_export_jobs(...)` | `NEW RPC` | **087 / I** |
| 19 | `venue.sweep_expired_exports()` | `NEW RPC` (definer, `pg_cron`) | **087 / I** |
| 19a | `venue.claim_artifacts_for_purge(...)` · `venue.confirm_artifact_purged(...)` · `venue.reconcile_export_orphans(...)` (definer, `service_role`) | `NEW RPC` | **087 / I** |
| 19b | `crm-export` **`POST /purge`** route + its 15-min `pg_cron`/`pg_net` schedule and the daily orphan pass | part of element 21 — **the only Storage delete agent in this design** | gated on **087 / I** |
| 20 | `catalog.platform_config` seeds (limits, caps, retention, `constraint_set_version`) | `ADDITIVE SCHEMA CHANGE` (data) | **087 / I** |
| 21 | `crm-export` (build + `/download` route) | `NEW EDGE FUNCTION` | gated on **087 / I** |
| 22 | X-6 CI check (§10.2) + constants module | `NO SCHEMA CHANGE` | CI, lands with **087 / I** |
| 23 | `crm_export_builder` role + policies (Layer 0) | `ADDITIVE SCHEMA CHANGE` — **D-2** | **087 / I** |
| 24 | `promoter_name` / `promoter_code` columns → `audience_v2` | `NO SCHEMA CHANGE` (template version bump) | **090 / 2D** |
| 25 | Checkout contact opt-in control | `NEW RN SURFACE` | gated on **082 / F** |
| 26 | Settings → "Venues you've allowed to email you" + master switch | `NEW RN SURFACE` | gated on **082 / F** |
| 27 | Pre-deletion "which venues exported a list with you" screen (§9.2) | `NEW RN SURFACE` | gated on **087 / I** |
| 28 | Resale-checkout contact opt-in (if D-1 = yes) | `NEW RN SURFACE` | gated on **088 / J-1** |
| 29 | Attendees tab → holder-grain list + suppression legend | `NEW DASHBOARD SURFACE` | gated on **087 / I** |
| 30 | Export request / history / revoke panel (§9.6, §16.6) | `NEW DASHBOARD SURFACE` | gated on **087 / I** |
| 31 | Dashboard §9.1 attendee list is purchaser-keyed | **`SPEC CORRECTION`** — §11.7 K-1 | doc |
| 32 | Dashboard §9.6 allow-list predates `marketing` | **`SPEC CORRECTION`** — §11.7 K-2 | doc |
| 33 | Role-model F12 vs dashboard note 13 on platform export | **`SPEC CORRECTION`** — §3.2, §11.7 K-3 | doc |
| 34 | RLS spec §6 column-scoped table — add 4 deny-all rows | **`SPEC CORRECTION`** | doc |
| 35 | SPEC_FOUNDATION §6 table inventory — add 4 tables | **`SPEC CORRECTION`** | doc |
| 36 | `kernel.tickets`, `venue.order`, `order_item`, `scan`, `attribution`, `public.profiles`, `kernel.admin_audit` | **`NO SCHEMA CHANGE`** | — |
| 37 | Every demographic object | **`NO SCHEMA CHANGE`** — untouched, unreferenced | — |

### 11.2 Schema delta (additive)

**`kernel.identity_contact_pref`** — MUT, not a ledger.

| Column | Notes |
|---|---|
| `identity_id` | PK, `→ auth.users(id)` **ON DELETE CASCADE** (the named exception, §9.5) |
| `venue_email_contact` | text, `CHECK IN ('allow','block')`, NOT NULL, **DEFAULT `'allow'`** — a kill switch, not a consent (§5.3) |
| `updated_at` | timestamptz NOT NULL |

**`kernel.org_contact_consent`** — MUT current-state; **withdrawal is a state change, never a delete** (§5.3).

| Column | Notes |
|---|---|
| `identity_id`, `org_id` | composite PK; `identity_id → auth.users` **ON DELETE CASCADE**; `org_id → kernel.organization` ON DELETE RESTRICT |
| `state` | text, `CHECK IN ('granted','withdrawn')`, NOT NULL |
| `granted_at`, `withdrawn_at` | timestamptz; `CHECK (state='withdrawn') = (withdrawn_at IS NOT NULL)` |
| `notice_version` | text NOT NULL — which consent copy they saw |
| `source_order_id` | uuid nullable `→ venue.order` — where consent was first given; nullable because a Settings-side grant has no order |
| `updated_at` | timestamptz NOT NULL |
| | index on `(org_id, state)` for the build-time gate |

**`kernel.org_customer_key`** — secret, definer-only.

| Column | Notes |
|---|---|
| `org_id` | PK `→ kernel.organization` |
| `key_material` | bytea, random 32 B, **never returned by any RPC, never logged, never exported** |
| `created_at`, `rotated_at` | timestamptz; rotation is `platform_admin` + step-up + audited, and is not a routine (§4.3) |

**`venue.export_job`** — MUT lifecycle; **contains no customer rows**.

| Column | Notes |
|---|---|
| `job_id` | PK |
| `scope_kind` | text, `CHECK IN ('session','event','venue','org')` — **no `'all'` member** (EX-1) |
| `scope_id` | uuid |
| `org_id` | uuid `→ kernel.organization` — **the job's org, resolved once at request time from the scope object and frozen here.** This is `:job_org_id`: the operand of XO-1a's atom-level equality, of the `customer_ref` HMAC key (§4.3), and of the consent gate's `EXISTS` (§5.1) — at **every** grain, not only org grain. It is also used for the bucket path and the per-org rate limit. The builder reads it from this row and never re-derives it from the scope object, because `catalog.venue.org_id` is mutable and a re-derivation at build time could differ from the one the request was authorized against |
| `template_id`, `template_version` | text / int |
| `filters` | jsonb, **normalized and sorted at write** (§8.3) |
| `as_of` | timestamptz NOT NULL — frozen at request (§6.3) |
| `state` | text, `CHECK IN ('queued','running','ready','failed','revoked','expired','purged')` |
| `requested_by` | uuid `→ auth.users` ON DELETE RESTRICT |
| `command_key` | text NOT NULL; `UNIQUE (requested_by, command_key)` (C16 idempotency pattern) |
| `lease_until` | timestamptz nullable — the 064 claim-lease pattern for the build worker |
| `row_count`, `byte_count` | int nullable |
| `artifact_sha256` | text nullable |
| `object_path` | text nullable |
| `contact_cells_emitted`, `contact_cells_suppressed`, `name_cells_emitted`, `name_cells_suppressed` | int NOT NULL DEFAULT 0 — **accumulated by `venue.build_export_rows` page by page inside the definer**, never written by the worker (§11.4). Not nullable: a null would be indistinguishable from a gate that ran and emitted nothing |
| `artifact_state` | text NOT NULL, `CHECK IN ('absent','present','delete_pending','deleted')`, DEFAULT `'absent'` — **the object's lifecycle, tracked separately from the job's**, because the two genuinely diverge: a job is `revoked` the instant the RPC commits while its object survives until the purge route runs. Without this column "is the file gone" was unanswerable and the retention claim was a claim about rows |
| `purge_lease_until` | timestamptz nullable — the 064 claim lease for the purge route, distinct from `lease_until` (the build's) |
| `purge_attempts` | int NOT NULL DEFAULT 0 — > 3 raises a `platform_risk` signal (§6.6) |
| `failure_code` | text nullable — `too_large` · `scope_unreachable` · `build_error` · `limit_exceeded` |
| `requested_at`, `ready_at`, `expires_at`, `purge_after` | timestamptz |
| | index on `(state, requested_at)` for the cron drain; index on `(artifact_state, expires_at)` for the purge claim; index on `(org_id, requested_at)` for the history panel |

**Named exception requiring acknowledgment.** `ON DELETE CASCADE` from `auth.users` on the two contact tables
departs from the corpus's `ON DELETE RESTRICT` default. Justification: an orphaned contact permission
belonging to a deleted account is the worst possible residue — it is a live grant with no grantor —
and `VERIFIED:` cascade-from-`auth.users` is already the house pattern (migrations 012/023/033). Needs the
schema and RLS spec owners' sign-off. **D-3.**

### 11.3 RLS delta

Following 068 (column grants) + 042 (definer own-row read), at its strongest setting — identical in shape to
the demographics spec's §10.3:

```text
REVOKE ALL ON kernel.identity_contact_pref  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON kernel.org_contact_consent    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON kernel.org_customer_key       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON venue.export_job              FROM PUBLIC, anon, authenticated;
-- and NO re-GRANT of any column to any client role. The grant set is EMPTY, not reduced.
ENABLE ROW LEVEL SECURITY on all four, with no policy admitting anon or authenticated.
```

`INFERENCE:` per 062's rule, any column grant on `kernel.org_contact_consent` to `authenticated` would make
**every** consent row readable by **every** signed-in user — i.e. a public map of who allows which venue to
email them. There is no public-safe subset of that, so the grant set is empty and **the absence of a grant is
the enforcement**, exactly as 052/062/068 established.

**RLS spec §6 additions (`SPEC CORRECTION`), four deny-all rows:**

| Table | Broad-readable columns | RESTRICTED |
|---|---|---|
| `kernel.identity_contact_pref` | **none** | entire table → `kernel.get_my_contact_prefs()` (own row) |
| `kernel.org_contact_consent` | **none** | entire table → `kernel.list_my_org_contact_consents()` (own rows); the build-time gate is definer-internal |
| `kernel.org_customer_key` | **none** | definer / `service_role` only; **no human role, including `platform_admin`** |
| `venue.export_job` | **none** | entire table → `venue.list_export_jobs()` (role- and scope-checked) |

**`storage` policies for `crm-exports`:** none. Not a reduced set — none.

### 11.4 RPC contracts

Every contract inherits RPC-spec §0 globals: `SECURITY DEFINER`, `search_path` pinned (066), `REVOKE EXECUTE
FROM PUBLIC, anon` then a narrow `GRANT` (067), actor **always** `auth.uid()` server-derived (C35), role tests
only via the C36/role-model predicate helpers, **no client actor parameter**.

---

**`kernel.get_my_contact_prefs()`** — read. **Params: none** (parameterless is load-bearing — "read someone
else's preferences" is unexpressible, per 042). Actor `auth.uid()`, raises `insufficient_privilege(42501)` on
NULL. Returns `{ venue_email_contact, updated_at }` or the default. EXEC: `authenticated`.

**`kernel.set_my_contact_prefs(p_venue_email_contact text)`** — write. Upserts one row keyed on `auth.uid()`.
Value re-validated against the CHECK set in-body. Writes `crm_contact.pref_changed` audit. Idempotent.
**No identity parameter exists.** EXEC: `authenticated`.

**`kernel.list_my_org_contact_consents()`** — read. **Params: none.** Returns
`[{ org_id, org_display_name, state, granted_at }]` for `auth.uid()`. EXEC: `authenticated`.

**`kernel.grant_org_contact_consent(p_org_id uuid, p_notice_version text, p_source_order_id uuid)`** — write.
`p_org_id` untrusted, re-validated as a live org. `p_notice_version` validated against the known list. Sets
`state='granted'`. Idempotent (re-granting is a no-op update). Audited. Rate-limited. EXEC: `authenticated`.
**Forbidden: there is no staff-side write path — no `admin_set_contact_consent`, no `p_identity_id`
parameter anywhere.** A venue can never record a consent on a fan's behalf.

**`kernel.withdraw_org_contact_consent(p_org_id uuid)`** — write. Sets `state='withdrawn'`, stamps
`withdrawn_at`. Idempotent (`{status:'noop_replay'}` if already withdrawn). Audited. EXEC: `authenticated`.

---

**`venue.list_attendees(p_session_id uuid, p_filters jsonb, p_cursor text)`** — read. Satisfies dashboard Δ3
with the §1.2 holder-grain correction. Actor `auth.uid()`; resolves session → event → venue → org and requires
`has_venue_role(venue,[venue_manager, venue_marketing])` **or**
`has_org_role_over_event(event,[org_owner, org_admin, org_marketing])` **or**
`has_venue_role(venue,[venue_finance])` / `has_org_role(org,[org_finance])` for the money-only projection
**or** `is_platform([platform_support, platform_risk, platform_admin])`. **Column-scoped by role per §3** —
denied classes are **absent from the result shape, not null** (`VERIFIED:` dashboard §16.8's rule: *"fields
are absent rather than blank"*). `p_filters` validated against the §6.5 grammar; anything outside it raises.
Rate-limited (`attendee_list_page`). Audited on every page. EXEC: `authenticated` with the in-body re-check.

**XO-1a applies here too.** The org resolved during authorization is the operand of
`kernel.tickets.org_id = :org_id`, of the `customer_ref` key, and of the consent gate — resolved **once**, in
the same statement that authorized, and used for all three. A roster read at a re-operated venue therefore
shows the current operator's own sessions and none of the prior operator's, exactly as the export does; the
two surfaces must agree or the export becomes the narrow one and the screen becomes the leak.

**`venue.lookup_attendee(p_session_id uuid, p_query_kind text, p_query_value text)`** — read, **one record**.
`p_query_kind ∈ {email_exact, order_ref, name_prefix}`. Authority: `venue_manager`, `venue_box_office`, org
owner/admin, `platform_support`; **denied to both marketing labels** (§7.2). Returns the minimal service
projection. EXEC: `authenticated`.

**Rate-limited per actor *and* per org, for every `query_kind`** (§7.1) — not "40/day for `email_exact`",
which is what the previous contract said and which left `name_prefix` limited by nothing at all. Limits are
looked up by `(action = 'attendee_lookup_by_' || p_query_kind, actor)` and `(…, org)`, so **a `query_kind`
with no configured limit raises rather than passes** — the same fail-closed posture 021 established for the
limiter itself, applied to the limiter's own configuration.

**`name_prefix` additionally (§7.2a):**
- `length(trim(p_query_value)) >= 3`, else `prefix_too_short` — raised **before** the lookup and **without
  consuming the rate budget**, since the call reached no data and charging for it would make the limiter a
  denial-of-service against the box office.
- **More than one match raises `ambiguous_query`, returning no rows and no count.** Not a count, not a
  truncated list, not the first result, not "3 matches — refine your search". A count is the harvest: `"sm"`
  → 14 and `"smi"` → 9 reconstruct the roster's name distribution without ever returning a record.

**Audited with the query kind and outcome, never the value.** `crm_lookup.attendee` records
`(actor, session, query_kind, outcome ∈ {hit, no_match, ambiguous, rate_limited, prefix_too_short})`.
`INFERENCE:` `ambiguous` and `rate_limited` are the load-bearing outcomes — a run of them is the signature of
an alphabet sweep, and they are the only evidence of one, since the probed strings are deliberately never
stored.

**`venue.request_export(p_scope_kind text, p_scope_id uuid, p_template_id text, p_filters jsonb,
p_command_key text)`** — write. Authorizes per §3 X5/X6; rejects `scope_kind='all'` (not a member); validates
filters against §6.5 and template against §6.4; enforces §7.3 caps at request (so a too-large job fails
immediately, not after a five-minute build); rate-limits fail-closed; **freezes `as_of = now()`**;
**resolves and freezes `org_id` — the job's org — from the scope object, in the same transaction that
authorized against it (XO-1a)**; writes the job row `queued` and the `crm_export.request` audit row **with
`constraint_set_version`** in the same txn. Idempotent on `(auth.uid(), p_command_key)`. Returns
`{ job_id, state, as_of }`. EXEC: `authenticated`.

`INFERENCE:` freezing `org_id` here rather than resolving it at build time is not tidiness. Authorization
resolved the scope's org at request; a build-time re-resolution could read a **different** org for the same
venue, because `catalog.venue.org_id` is mutable. A job must be built against the org it was authorized
against, or the authorization proved something about a tenancy that no longer holds.

**`venue.build_export_rows(p_job_id uuid, p_cursor text, p_limit int)`** — read, **definer / `service_role`
only**. `REVOKE EXECUTE FROM anon, authenticated` — no human path. Re-derives authority **from the job row's
recorded actor and scope**, not from the caller. Returns one bounded page of rows for the job's template, at
the job's `as_of`, in the deterministic order (§2.4 X-4). **This function is the entire SQL surface that
touches customer data**, contains **no dynamic SQL** (§10.2 rule 4), and is the object §10.3 asserts on.

**XO-1a is this function's first predicate, on every branch.** Every grain — `session`, `event`, `venue`,
`org` — ANDs `kernel.tickets.org_id = job.org_id`, read from the job row, never re-derived. The
`customer_ref` HMAC key is `org_customer_key(job.org_id)` and the consent gate's `EXISTS` binds
`org_id = job.org_id`. `INFERENCE:` these three are stated together because they must move together: if a
future refactor takes any one of them from the atom instead of the job, the venue-grain export at a
re-operated venue leaks the prior operator's list (§4.4 case (e)) and — for the HMAC — the two orgs' files
join on the pseudonym. Asserted as assertions 18a–18c.

**`venue.finalize_export(p_job_id, p_row_count, p_byte_count, p_sha256, p_object_path,
p_cells_emitted, p_cells_suppressed)`** — write, **`service_role` only**. `running → ready`; writes
`crm_export.generate` audit. Idempotent.

**`venue.authorize_export_download(p_job_id uuid)`** — write. **Re-checks the caller's authority live against
the grant tables at this instant** (EX-4). Rate-limits. Writes `crm_export.download` audit in-txn. Returns
`{ object_path, ttl_seconds: 300 }` for the edge to sign. Raises on any state other than `ready`.
EXEC: `authenticated`.

**The re-check is over `(scope, template_id)`, not over the role set — one predicate, and it is the whole
finding.** The function reads `job.template_id` and re-evaluates **the §6.4 allow-list for that template**,
the same predicate `venue.request_export` would apply to a fresh request for the same
`(scope_kind, scope_id, template_id)`:

```text
-- WRONG (what the previous contract specified):
--   caller still holds one of {org_owner, org_admin, org_marketing,
--                              venue_manager, venue_marketing} over job.scope
-- RIGHT:
   assert_may_request(auth.uid(), job.scope_kind, job.scope_id, job.template_id)
   -- audience_v1   → org_owner, org_admin, org_marketing (org grain),
   --                 venue_manager, venue_marketing (venue grain)
   -- operations_v1 → org_owner, org_admin, venue_manager  ONLY
```

`INFERENCE:` the previous contract mentioned no `template_id` at all, and the two allow-lists are not the
same set — X6's is the narrowest in the matrix (§3). The concrete break: `org_marketing` is granted X10
(read export history), so it can see a colleague's `job_id`; it holds a `venue_marketing`-class role over the
scope, so the role-set re-check passes; and it downloads an **`operations_v1`** file — order refs, order
totals, **unit prices**, refund state. §3.1's stated invariant — *"Finance sees money and no contact.
Marketing sees contact and no money. Neither sees both."* — is then defeated by any org that ever runs one
operations export, without a single grant being wrong.

Two supporting rules, so the fix cannot be undone from the side:

- **X8 `R◐` is defined, not decorative.** The `◐` on `OMK`/`VMK` in the §3 matrix means *"jobs whose
  `template_id` that role may request"* — for both marketing labels that is `audience_v1` only. The same
  reading applies to X9 (revoke): `◐` is template-scoped there too.
- **`venue.list_export_jobs` returns `template_id` and a `downloadable` boolean** computed with the same
  predicate, so the panel does not render a download control the RPC will refuse. The list itself stays
  role-scoped rather than template-scoped — seeing *that* an operations export happened is export-history
  transparency (X10) and is deliberate; downloading it is not.

**`venue.revoke_export(p_job_id uuid, p_reason_code text)`** — write. Authority: the requester, plus
`venue_manager` / org owner/admin over the job's scope, plus `platform_admin` — and, per H-12, template-scoped
for both marketing labels. `ready → revoked` **in the same transaction**, so no further download is authorized
from that instant; sets `artifact_state = 'delete_pending'`; audited. Idempotent. EXEC: `authenticated`.
**It does not delete the object** — see `POST /purge` (§6.6, §11.5). The previous contract said it *"signals
the edge to delete"*, which named no mechanism; there was no delete route to signal.

---

**`venue.claim_artifacts_for_purge(p_limit int)`** — write, **definer / `service_role` only**.
`REVOKE EXECUTE FROM anon, authenticated`. Takes the 064 claim lease over a bounded page of jobs in
`artifact_state = 'delete_pending'` and returns `(job_id, object_path)` for the purge route. Returns nothing
else — no scope, no counts, no actor.

**`venue.confirm_artifact_purged(p_job_id uuid, p_outcome text)`** — write, **definer / `service_role` only**.
`p_outcome ∈ {deleted, not_found}` — **both are success**; a 404 from Storage means the object is gone, which
is the goal. Sets `artifact_state = 'deleted'`, advances `ready → expired → purged` where retention allows,
writes `crm_export.purge`. Idempotent.

**`venue.reconcile_export_orphans(p_org_id uuid, p_object_paths text[])`** — write, **definer /
`service_role` only**. Given the paths the purge route listed under one `{org_id}/` prefix, returns the ones
with no live job row or with a job row claiming the artifact is already gone (the route deletes those), and
marks `artifact_state = 'deleted'` for job rows whose object is absent — alarming when such a job is still
`ready`, because a `ready` job with no bytes fails at download. §6.6 gives the full table.

**`venue.list_export_jobs(p_scope_kind, p_scope_id, p_cursor)`** — read. Scope-checked per X10. Returns job
metadata only — never a row, never an object path, never a signed URL — **including `template_id` and a
`downloadable` boolean computed with `authorize_export_download`'s own predicate**, so the panel never
renders a download control the RPC will refuse. EXEC: `authenticated`.

**`venue.sweep_expired_exports()`** — write, **definer / `service_role` only**, `pg_cron` (hourly). **Marks**
artifacts past `expires_at` as `artifact_state = 'delete_pending'` and moves `ready → expired`;
`expired → purged` once `artifact_state = 'deleted'` and `purge_after` has passed. Writes one audit row per
transition. **It deletes no bytes** — the purge route does (§6.6). The previous contract said "deletes
artifacts", which a Postgres function cannot do; its only in-DB option, `DELETE FROM storage.objects`, removes
the metadata row and leaves the bytes orphaned in the backing store — worse than doing nothing, because the
object survives while every accounting says it is gone. **SSCAS: n/a** — no money, custody or inventory row is
touched by anything in this document, so **no RPC here is a member of the closed set**, and none takes an
SSCAS lock.

### 11.5 Edge function contracts

**`crm-export`** — `NEW EDGE FUNCTION`. **Three** routes, one function, per the edge spec's §7 cross-cutting
rules (CORS whitelist + `getSecurityHeaders()` on every response including errors and OPTIONS; structured JSON
logging; Sentry on unexpected 500s).

| | `POST /build` (worker) | `POST /download` (actor) | `POST /purge` (worker) |
|---|---|---|---|
| **verify_jwt** | `false` — invoked by `pg_cron` via `net.http_post` with a service-role bearer, constant-time compared (I-9) | **`true`** — actor re-derived via `auth.getUser` (C35) | `false` — same cron + shared-secret path as `/build` |
| **Authz** | in the wrapped RPC (`service_role` only) | in the wrapped RPC (`venue.authorize_export_download`, live re-check **including the job's `template_id`**) | in the wrapped RPCs (`service_role` only) |
| **Wraps** | `venue.build_export_rows` (paged) → `venue.finalize_export` | `venue.authorize_export_download` | `venue.claim_artifacts_for_purge` → `venue.confirm_artifact_purged`; daily, `venue.reconcile_export_orphans` |
| **External I/O** | Storage upload to `crm-exports` | Storage `createSignedUrl(path, 300)` | **Storage `remove()` and `list()`** — the only delete agent in this design |
| **Secrets (names only)** | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `CRM_EXPORT_WORKER_SECRET`, `SENTRY_DSN` | same | same |
| **Rate limit** | n/a (cron-paced, plus the per-org concurrency cap) | `check_rate_limit`, fail-closed: 429 over-limit, **503 on limiter error** | n/a (cron-paced) |
| **Idempotency** | the job's claim lease + `UNIQUE (requested_by, command_key)`; a re-driven build overwrites the same `{org_id}/{job_id}.csv` | none needed — a signed URL is not a side effect | the claim lease; **a 404 from `remove()` is success**, so a repeat is a no-op |
| **Logging** | **counts, ids and durations only.** Never a row, never a cell, never an email, never a `customer_ref`, never a signed URL | same | same — the path is `{org_id}/{job_id}.csv` by design, which is why it is loggable |
| **Failure** | validation 400 · authz 403 · state 409 · limiter 429/503 · storage 500/503 with the job left reclaimable by the lease | same | leaves the row `delete_pending` with the lease expired; the next cycle retries; **> 3 failed cycles raises a `platform_risk` signal** — a delete that never succeeds is an alarm, not a silent gap |
| **Timeout** | 15 s per page-batch; the lease is longer than the timeout so a crashed worker is reclaimed, never double-run to a second artifact | 3 s | 15 s per claimed page; lease longer than the timeout |
| **Cadence** | one-minute cron drain of `queued` | on demand | **15-minute cron**; orphan reconciliation once per day |

**Rejected placements, recorded because the edge spec says rejections are the high-value output:**

| Candidate | Verdict | Why |
|---|---|---|
| Row selection in TypeScript | **REJECTED → RPC** | A query assembled in the edge is invisible to §10.3's catalog assertions and to pgTAP. The SQL must be one named catalog object. |
| A `crm-export-deliver` function emailing the CSV | **REJECTED — never build it** | EX-6. It is a third-party destination with extra steps, and it puts the file in an inbox that outlives every control here. |
| A webhook/CDP sync route | **REJECTED — never build it** | X-5 / EX-6 / C40. |
| A synchronous `GET /attendees.csv` | **REJECTED** | EX-2, and §6.1's reasoning. |
| Sweep/expiry **state transitions** as an edge function | **REJECTED → RPC via `pg_cron`** | Pure DB batch. But **the Storage delete cannot ride an RPC**, which is what the original phrasing obscured — see the row below. |
| Sweep/expiry/revoke performing the Storage delete **in Postgres** | **REJECTED — it is not possible** | A `SECURITY DEFINER` Postgres function cannot call the Storage API. Its only in-DB option is `DELETE FROM storage.objects`, which drops the metadata row and **orphans the bytes**. The delete is therefore its own route (`POST /purge`), driven by the `pg_cron` + `pg_net` pattern migrations 014/032/034 already use. `INFERENCE:` this is recorded as a rejected placement because the previous design's revoke, sweep and retention text all described a delete with **no agent at all**, and the missing agent is exactly the kind of thing a placement table exists to make visible. |

---

## 12. pgTAP assertion list (described; no SQL files written)

**Grants and RLS**
1. `anon` holds **zero** rows in `information_schema.role_column_grants` for all four new tables.
2. `authenticated` holds **zero** rows in `role_column_grants` for all four new tables. *(The assertion that
   would have caught the pre-068 `public.profiles` exposure.)*

**Roster semantics**
3. **The non-contradiction assertion:** for a fixture session, `COUNT(DISTINCT holder)` from
   `venue.list_attendees` equals `holder_mix.holders_total` from the demographics rollup at the same `as_of`.
4. Six atoms from one order, five transferred: the holder view returns **six** rows; the purchaser view
   returns **one**; and the purchaser's holder row shows `tickets_held = 1`, `is_purchaser = true`.
5. A `voided` atom appears in neither view.
6. `acquired_via` maps every cause in the D3 registry to exactly one display value, and `refund_void` is
   unreachable.
7. **No counterparty leak:** no column of any roster projection resolves to the identity of a previous holder.

**Contact gate**
8. Email is emitted iff all four conjuncts of §5.1 hold; each conjunct falsified independently suppresses.
9. A transferee who never purchased gets a **blank** email cell even when the *purchaser* consented.
10. A purchaser who consented and then transferred every ticket away still gets an email cell **on their own
    row**, if they hold one; if they hold none they are not on the holder view at all.
11. The master switch set to `block` suppresses every org's cell for that identity in one call.
12. Withdrawal suppresses from the next build; a build whose `as_of` precedes the withdrawal is unaffected
    (and this is the *documented* semantic, not an accident).
13. `contact_cells_emitted + contact_cells_suppressed` equals the holder row count on every `ready` job, and
    so does `name_cells_emitted + name_cells_suppressed`.
13a. **The name gate is the contact gate (§4.3).** For every holder row of an export, the `display_name` cell
    is non-blank **iff** the `email` cell is non-blank — asserted as a per-row biconditional over a fixture
    covering all four combinations of the master switch and the per-org consent, so gating one column and
    forgetting the other fails.
13b. **On screen the name is ungated.** The same non-consenting transferee whose export row is nameless
    appears **with their display name** in `venue.list_attendees`, in `venue.lookup_attendee`, and in the
    door verification projection. *(Asserted as a pair with 13a: a fix that gates the name everywhere breaks
    door operations and must also fail.)*
13c. **No other column reintroduces the join key.** No export column of any template resolves to
    `public.profiles.display_name`, `full_name`, an email local-part, or any other value that is identical
    for the same identity across two orgs — asserted by generating exports for the same identity at two orgs
    and requiring the **intersection of their non-blank IDENT/OPS cell values to be empty** where that
    identity consented at neither org. *(This is the assertion that would have caught the ungated name
    column: it tests the property the proof claims — unjoinability — rather than the mechanism the proof
    credits it to.)*
14. **No staff write path:** the set of functions writing `kernel.org_contact_consent` is exactly
    `{grant_org_contact_consent, withdraw_org_contact_consent}`, and neither has a `uuid` parameter that could
    denote an identity.

**Cross-org isolation**
15. A `venue_manager` of venue X is denied `list_attendees` and `request_export` on a session of venue Y.
16. A `venue_marketing` at V1 of Org 1 is denied at V2 of the same org.
17. `org_marketing` at Org 1 reaches all of Org 1's venues and none of Org 2's.
18. **The pseudonym assertion:** the same identity in two orgs yields two different `customer_ref` values, and
    the same identity in the same org yields the same value across two sessions and two exports.
18a. **XO-1a, the operatorship-change fixture (§4.4 case (e)).** Venue V has August sessions whose atoms carry
    `org_id = Org1` and September sessions whose atoms carry `Org2`; `catalog.venue(V).org_id` is updated to
    `Org2`. A `venue_manager` at V under Org 2 requesting a **venue-grain** export with a 180-day window
    receives **zero August rows** — asserted at session, event and venue grain independently, because the
    predicate has to be present on each branch and a single-grain test passes while three branches leak.
    `row_count` and fields 13–15 exclude them too.
18b. **The HMAC operand.** In the same fixture, an identity who held atoms under both operators receives
    **two different** `customer_ref` values across the two orgs' exports. *(Asserted as an inequality: keying
    on the atom's org rather than the job's would make them equal, and the two files would join on the
    pseudonym — the defence inverted.)*
18c. **The consent operand.** In the same fixture, an identity who granted consent to Org 1 and not to Org 2
    gets a **blank** email cell in Org 2's export and a populated one in Org 1's, at every grain.
19. `promoter`, `venue_scanner`, a valid door session, `venue_box_office`, `org_finance`, `venue_finance`,
    `org_member`, `fan` and `anon` are each denied `request_export` and `list_attendees`.

**Export mechanics**
20. `scope_kind = 'all'` is rejected — it is not a member of the CHECK set.
21. A filter outside the §6.5 grammar raises; a demographic filter name raises; an OR/NOT/nested filter
    raises.
22. **Deterministic order:** two builds of the same `(scope, filters, template_version, as_of)` produce
    byte-identical output and the same `artifact_sha256`.
23. A job exceeding 50 000 rows ends `failed` with `too_large` and **writes no artifact** (never truncates).
24. Every `crm_export.generate` audit row has a non-null `constraint_set_version` (**X-9**).
    Every `crm_export.download` row exists before its signed URL is minted.
24a. **The download re-check reads the template (H-12).** With `org_marketing` and `venue_marketing` holding
    live, valid roles over the job's scope, `venue.authorize_export_download` on a **`operations_v1`** job
    raises `insufficient_privilege(42501)` and writes `crm_export.denied`; on an `audience_v1` job at the
    same scope, by the same actor, in the same test, it succeeds. *(Asserted as a pair, so a fix that denies
    marketing all downloads also fails.)* The same pair holds for `venue.revoke_export`.
24b. **Symmetry with request.** For every `(actor, scope, template)` triple in a fixture matrix covering all
    20 principals × both templates, `authorize_export_download` allows exactly the triples
    `request_export` allows. *(Stated as an equality between two predicates rather than as two lists, so the
    two cannot drift.)*

**X-6**
25. **Reader enumeration (mirrors demographics assertion 27):** the set of functions/views/matviews
    referencing `kernel.identity_demographic` is exactly the four demographic functions — **no export
    function appears.**
26. The set referencing `venue.holder_mix_snapshot` / `_bucket` is exactly
    `{refresh_holder_mix, get_holder_mix, <reconciliation job>}`.
27. No export function's `pg_get_functiondef` matches `identity_demographic|holder_mix|gender_identity`, and
    no export function has a `pg_depend` edge to a demographic relation, **and the assertion sees all nine
    export functions** (the non-vacuity guard).
28. `venue.build_export_rows` contains no `EXECUTE` / `format(` / `quote_ident(` (no dynamic SQL).

**Storage**
29. The `crm-exports` bucket exists with `public = false`, `file_size_limit = 33554432`,
    `allowed_mime_types = {text/csv}` — asserted as **values**, not existence (the 073 lesson).
30. **Zero `storage.objects` policies** name `crm-exports` for `anon` or `authenticated`.
31. An artifact past `expires_at` is absent from the bucket and its job is `expired` **with
    `artifact_state = 'deleted'`** — asserted after running the purge route, **and asserted against
    `storage.objects`, not against the job row**, because the job row is the accounting and the object is the
    exposure.
31a. **Revoke does not delete, and says so.** `venue.revoke_export` leaves the object **present** and the job
    `revoked` / `delete_pending`; `authorize_export_download` refuses from that instant; after one purge
    cycle the object is absent and `artifact_state = 'deleted'`. *(Asserted as a sequence, because the
    previous design claimed the delete was immediate and had no agent to perform it at all.)*
31b. **A 404 is success.** `confirm_artifact_purged(job, 'not_found')` reaches `deleted` and writes
    `crm_export.purge`; a second call is a no-op.
31c. **Orphan reconciliation.** An object placed in `crm-exports` with no job row is deleted by the daily
    pass and audited with `reason_code = 'orphan_no_job'`; an object whose job row says
    `artifact_state = 'deleted'` is deleted with `'orphan_state_mismatch'`; an object whose job is `ready`
    and inside retention is **not** touched.
31d. **The purge route is the only delete agent.** No `pg_proc` in `venue` or `kernel` contains
    `DELETE FROM storage.objects` (the metadata-only delete that orphans bytes), and the `crm-export`
    function's route table has exactly three members.

**Audit**
32. Every state transition of `venue.export_job` has a corresponding `kernel.admin_audit` row in the same
    transaction; `UPDATE`/`DELETE` on `kernel.admin_audit` are denied to every role.
33. No audit row's payload contains an `@` character in a value position, an `org_customer_key`, or a
    `customer_ref` *(content scan)*.
34. A denied export attempt writes `crm_export.denied`.
34a. **Every lookup kind is limited, per actor and per org.** For each of `email_exact`, `order_ref`,
    `name_prefix`: the per-actor cap and the per-org cap both bind independently (the org cap fires with the
    actor cap unspent, across three distinct actors), and both fail closed — **503 on limiter error, never a
    pass**. A `query_kind` whose limit row is missing from `catalog.platform_config` **raises**; it does not
    default to unlimited.
34b. **`name_prefix` minimum length.** A 2-character prefix raises `prefix_too_short`, reaches no data,
    **and does not consume the rate budget** (asserted by checking the remaining budget after the call).
34c. **Multi-match returns nothing at all.** A prefix matching 2+ holders raises `ambiguous_query` with
    **zero rows and no count field in the payload** — asserted structurally on the error's shape, not by
    reading a value, so a later "helpfully" added match count fails the suite. A prefix matching exactly one
    returns that one record.
34d. **The sweep is bounded and visible.** 21 `name_prefix` calls by one actor in 24 h: the 21st is
    `rate_limited`. The audit rows for all 21 carry `query_kind` and `outcome` and **contain none of the
    probed strings** (content scan).

**Erasure / merge**
35. Deleting the `auth.users` row cascades both contact tables away, and neither is repointed to the
    `00000000-0000-0000-0000-000000000000` sentinel; the sentinel identity holds **no** contact rows after any
    account deletion.
36. C38 merge rule: survivor consent is `granted` only where **both** identities held `granted`; the master
    switch resolves to the more restrictive; the non-survivor's `customer_ref` is not aliased forward.

---

## 13. Open questions — owner, counsel, and architecture decisions

| ID | Decision | Owner | Blocking? |
|---|---|---|---|
| **D-1** | **Does a native-rail resale purchase create a contact relationship with the event's org?** This spec says **no by default** and recommends offering the same unchecked opt-in at resale checkout so consent arrives by the buyer's own act (§5.5). The alternative — treating settlement flow as a customer relationship — is a legal characterisation, not a product one. | Owner + **Counsel** | No — the recommended design ships either way |
| **D-2** | **Adopt the Layer-0 privilege wall (§10.1)?** A dedicated `crm_export_builder` definer owner with zero grant on the demographic objects, making an X-6 violation a runtime error rather than a CI finding. Costs a deviation from the "`SECURITY DEFINER` owned by `postgres`" global plus a handful of policy lines. **Recommend adopt.** | Architecture (schema + RLS owners) | **Yes — before 087 / I** |
| **D-3** | **Acknowledge the `ON DELETE CASCADE` exception** on the two contact tables against the `RESTRICT` default (§11.2), and the constraint on whoever next edits migration 020: contact rows must **never** be repointed to the anonymized sentinel (§9.5). | Architecture + account-deletion owner | **Yes — before 077 / B** |
| **D-4** | **Acknowledge the consent-record divergence from the demographics spec:** withdrawal is a **state change**, not a hard delete, because a consent record is evidence about a relationship rather than a sensitive attribute, and it is the person's own evidence in the dispute they are most likely to have (§5.3). | Architecture + Counsel | No |
| **D-5** | **Confirm the lookup limits — all three kinds, both planes.** `email_exact` 40/actor + 120/org; `name_prefix` **20/actor + 60/org** (there was no limit at all); `order_ref` 200/actor + 600/org. Plus the `name_prefix` **3-character minimum** and **`ambiguous_query` carrying no rows and no count** (§7.2a). The *shape* (per actor **and** per org, fail-closed, audited by kind and outcome but never by value, denied to marketing) should not change; the **numbers** are a judgement the owner should own, because these are the sharpest anti-harvest controls in the document — and because a festival box office on a busy door may legitimately need the prefix number higher, which is exactly the request that should arrive as a config change with an actor on it rather than as a code change. | Owner | No |
| **D-6** | **Artifact retention: 24 hours (recommended) or 7 days?** (§6.6.) 24 h means the bucket holds one day of exports at steady state; 7 days is an operator convenience that multiplies the standing exposure sevenfold. **Recommend 24 h.** | Owner | **Yes — the sweep constant** |
| **D-7** | **Confirm `marketing`'s CRM ceiling.** This spec gives both marketing labels the audience template (contact + ops, no money) at their plane's grain, denies them the money template, denies them the email-lookup probe, and denies `venue_marketing` the org-grain CRM. `VERIFIED:` this is exactly role-model H2/H3, made concrete at column level — but role-model **OD-8** asked the owner to confirm the scope, and the demographics spec's **D-8** asked the same about the mix card. Both should be answered once, together. | Owner | No |
| **D-8** | **Is a platform-plane bulk extraction path wanted at all?** This spec resolves the role-model F12 / dashboard note-13 conflict by giving platform roles **read** and **not** the venue export (§3.2), and does not build a platform path. If one is wanted it needs dual control, its own retention, and its own audit action. | Owner | No |
| **D-9** | **Confirm X-8 stays closed:** no demographic-based send, and no send of any kind from this surface. This spec builds none and recommends it stay that way; recording it so the absence is a decision, not a gap. | Owner | No |
| **D-10** | **`{N}` — the backup-retention window** in the §9.3 erasure copy. This is the demographics spec's **D-6**, not a second decision; it is listed only because the copy in §9.3 cannot ship with a placeholder either. | Owner / ops | **Yes — before the copy ships** |
| **D-11** | **Does an operator ever need a printed door list?** §3.1 denies `venue_box_office` the roster on purpose, so the answer today is "no, box office looks people up one at a time." If the answer is yes, it needs its own template, its own retention, and an honest acknowledgment that a printed list has none of §6's controls. | Owner | No |
| **D-12** | **Operatorship change: the new operator's CRM starts empty (§4.4 case (e)).** XO-1a pins tenancy to the atom's `org_id` at every grain, so a venue that changes hands does not hand the prior operator's customer list, consent, or `first_seen_at` history to the new one. That is the correct answer — the audience belongs to the organization the person transacted with, not to the building — and it is a real product consequence the incoming operator will contest. Confirm, and decide who tells them. A "the prior operator may share its own list with you, out of band, under its own terms" answer is a commercial arrangement between two orgs, **not** a platform feature, and this spec builds nothing for it. | Owner + **Counsel** | **Yes — before 087 / I** |
| **D-13** | **`display_name` is consent-gated in the export and ungated on screen (§4.3).** The operator-facing loss is real: an `audience_v1` export over a heavily transferred session is mostly `customer_ref` and ops columns with name and email blank on the same rows, and an `operations_v1` file identifies rows by `customer_ref` + `order_ref` rather than by name. The alternative — emitting the global name string to every org on every row — is what made the cross-tenant proof false, because two orgs union on it in one step. **Recommend the gate as written.** If rejected, §4.3, §4.4 case (a) and case (d)'s sub-case must be restated to claim only what an ungated name column leaves true, which is very little. | Owner | **Yes — it changes what every export file looks like** |

**Where I would push back on an inherited constraint — one place, and it is not a disagreement.** X-6 as
written ("the export builder's SQL contains zero references") is correct and I have implemented it, but its
stated method — *"grep the export builder"* — is the weakest of the four layers on its own, for a reason the
demographics spec could not have known: a grep over a file set that does not exist yet passes vacuously, and
this repository has already shipped that exact failure once (073). **I am not relaxing X-6; §10 makes it
stricter.** If the demographics spec's owner wants one sentence changed, it is to require the non-vacuity
guard by name. That is the only amendment I would ask for, and it strengthens their constraint rather than
weakening it.

---

## 14. Correction index for this document

| Tag | Applies to | Effect |
|---|---|---|
| **K-1** | Venue dashboard §9.1 attendee list | **Correction.** The list is currently purchaser-keyed (*"Name — from the buyer's `public.profiles` record via `venue.order.buyer_id`"*), which names one person for a six-ticket table and omits the five who hold the tickets. The list becomes **holder-keyed** (§1.2) with the purchaser exposed as `is_purchaser` and through the purchaser/order view. §9.2's search and §9.4's drawer are unchanged. |
| **K-2** | Venue dashboard §9.6 export allow-list | **Correction.** The allow-list (`venue_manager`, `org_owner`, `org_admin`) predates the `marketing` role. It gains `org_marketing` (org grain) and `venue_marketing` (venue grain), **audience template only**; the deny-list gains `venue_box_office`, `venue_scanner`, `venue_promoter_manager`, `org_promoter_manager`, and `venue_door` → `venue_scanner`. This matches role-model V-5 exactly. |
| **K-3** | Role-model §5 F12 vs dashboard §5 note 13 | **Conflict resolved (§3.2).** Platform roles **read** the roster and **do not use the venue CRM export**. Platform bulk extraction is not built in Phase 2 (**D-8**). |
| **K-4** | Venue dashboard §9.6 `UNVERIFIED` note (*"the export job, its lifecycle table, and the opt-in record are Agent B's delta"*) | **Resolved.** §11.2 supplies the job table, §5 the opt-in record, §6 the lifecycle. §9.6's ratified behaviour — async, 300-second signed URL re-authorized at download, audited request/generate/download/revoke, closed filter set, fixed columns, phone never exportable, email only on opt-in with an explaining legend, revoke on any `ready` export, `lg`+ only — is **unchanged and remains binding**. |
| **K-5** | Venue dashboard §21 Δ3 `venue.list_attendees` | **Resolved and amended.** The contract is in §11.4, with the holder-grain correction (K-1), the column-scoping per §3, and the §9.5-flagged display-name source pinned to `public.profiles.display_name` (the 068 public-safe set). |
| **K-6** | Migration 020 / account deletion | **Constraint recorded (§9.5, D-3):** never repoint a contact-preference or contact-consent row to the anonymized sentinel. |
| **K-7** | RLS spec §6 + §7/§9 | Four deny-all rows and four role matrices added (§11.3). |
| **K-8** | SPEC_FOUNDATION §6 canonical table inventory | Four tables added (§11.2). |
| **K-9** | RPC contracts spec | Fifteen contracts added (§11.4). |
| **K-10** | Edge function spec §2 placement table + §8 summary matrix | One function added (`crm-export`), four candidate placements rejected on the record (§11.5). |
| **K-11** | CDM §4 / DA §8.7 (C34), C38, C40 | **No constitution edit.** This document records the Phase-2-safe interim erasure promise (§9.3), the C38 contact-merge rule (§9.4), and the C40-class posture toward any future egress destination (EX-6) — all consistent with their GATE-L status. **The frozen constitutions are not modified by this document.** |
| **K-12** | Demographics spec | **No edit requested**, except the optional strengthening of X-6's stated method noted in §13. Its X-1…X-9 are satisfied as written (§2.4). |
| **K-13** | Role-model spec | **No edit requested.** Its labels, predicates and H2/H3 split are used verbatim; §3.2 resolves a conflict *between* it and the dashboard spec rather than within it. |
| **K-14** | **This document, §1.4 · §4.1 · §4.2 · §4.3 · §4.4 · §5.1 · §11.2 · §11.4 · §12** | **H-11 remediation.** The export's tenant predicate was bound at org grain only. `catalog.venue.org_id` is **mutable** while `catalog.event.org_id` is stamped at create, and the isolation traversal is downward `org → venue → event → session → ticket → holder`, so a **venue-grain export at a new operator reached every historic session of that venue** — the previous org's customer list. Added **XO-1a**: `kernel.tickets.org_id = :job_org_id` at **every** grain, with `:job_org_id` resolved once at request time and frozen on the job row. The `customer_ref` HMAC key and the consent gate's `EXISTS` are both pinned to the **job's** org, not the atom's — the previous text left both ambiguous, and the atom binding would have given two orgs the **same** pseudonym for the same person, joining their files directly. New proof **case (e)** and assertions **18a–18c** (asserted per grain, because a single-grain test passes while three branches leak). Product consequence recorded as **D-12**. |
| **K-15** | **This document, §3 (X8/X9 + note ᵗ) · §3.1 · §6.2 · §6.7 EX-4 · §7.4 · §11.4 · §12** | **H-12 remediation.** The download re-check read the role set and never the template — `template_id` was not mentioned in the contract at all. But the operations template's request-time allow-list is the narrowest in the matrix, so a `marketing` role could read a `job_id` from the job list (it holds X10) and download a colleague's **operations** export: order refs, order totals, unit prices, refund state. §3.1's own invariant — *"Finance sees money and no contact. Marketing sees contact and no money. Neither sees both."* — was defeated by any org that ever ran one operations export, with no grant being wrong. Fix: `venue.authorize_export_download` re-evaluates `assert_may_request(actor, job.scope, job.template_id)` — the same predicate a fresh request would face. `◐` on X8/X9 is now defined as template-scoped. Assertions 24a/24b, the second stated as an **equality between the request and download predicates** so the two cannot drift. |
| **K-16** | **This document, §6.2 · §6.6 · §9.2 · §11.1 · §11.2 · §11.4 · §11.5 · §12** | **H-13 remediation.** Nothing in the design could delete a Storage object. Revoke said it *"deletes the artifact, effective immediately"*; `venue.revoke_export` said it *"signals the edge to delete"*; the sweep said it *"deletes artifacts past retention"* — and the `crm-export` edge function had exactly two routes, **neither a delete**. A `SECURITY DEFINER` Postgres function cannot call the Storage API, and its only in-DB option (`DELETE FROM storage.objects`) drops the metadata row and **orphans the bytes**. So retention, sweep and revoke all had **no agent**: *"the lake is bounded by a 24-hour sweep"* was unimplementable and revoke could not remove the file it claimed to remove. Added: `POST /purge` on `crm-export`, driven by the `pg_cron` + `pg_net` pattern of migrations 014/032/034 this spec already cites; `artifact_state` / `purge_lease_until` / `purge_attempts` on `venue.export_job`; three definer `service_role` RPCs; and a **daily orphan reconciliation pass** that reconciles the bucket against the job table in both directions — without which the 24-hour bound is a statement about rows, and rows are not what leaks. Revoke's honest bound restated as `min(300 s, time-to-purge)`, not zero. |
| **K-17** | **This document, §7.1 · §7.2 · new §7.2a · §7.4 · §11.4 · §12** | **H-14 remediation.** The name-prefix lookup had **no rate limit** — the limit table carried rows for `email_exact` and `order_ref` and none for `name_prefix`, and `venue.lookup_attendee`'s contract scoped its limit to `email_exact` **explicitly**. `venue_box_office` holds X4, so iterating `a…z`, `aa…zz` against one session returned the roster one record at a time at no rate cost: the printed list §3.1 refuses (*"a box office cannot print a paper list. That is deliberate."*) reassembled from the surface meant to replace it, by the role denied it. Added: `attendee_lookup_by_name_prefix` at 20/actor + 60/org per 24 h; a **3-character minimum** raised before the lookup and without consuming budget; and **multi-match as an explicit `ambiguous_query` carrying no rows and no count** — a count is the harvest (`"sm"`→14, `"smi"`→9 reconstruct the name distribution without returning a record). **Per-org caps added for every lookup kind**, closing the medium that the export explains per-actor-alone is insufficient two rows above in the same table. Audit records kind **and outcome**, never the probed string; a run of `ambiguous`/`rate_limited` is the sweep signature and the only evidence of one. |
| **K-18** | **This document, §2.2 field 2 · §4.3 · §4.4 (a) and (d) · §5.1 · §8.3 · §11.2 · §12** | **Known finding 6 — the cross-tenant defence works, the claim did not.** The per-org HMAC pseudonym is genuinely per-org and unreadable by any principal; that part holds. But `display_name` was emitted **on every row of every export at every org, ungated by consent**, from the one global `public.profiles.display_name` string, so two orgs union their files on it directly and corroborate with admission time, `first_seen_at`, ticket types and acquisition route. **Claim deleted verbatim:** *"the **non-consenting majority — every transferee, every comp, every purchaser who left the box unticked — is unjoinable**, which is exactly the population with no relationship to either venue."* The proof resting on it (case (d)'s sub-case) was void as written. **The pseudonym removes the platform-supplied *stable* join key and nothing else** — that is the corrected claim. Fix: `emit_name := emit_email`, one predicate driving both cells in the **export**; `display_name` stays **ungated on screen**, in the single-record lookup and in the door projection, where §5.6 already establishes it is readable and where a surface cannot be unioned with another org's. `name_cells_emitted/suppressed` join the audit pair; the legend covers both columns. Assertion **13c** tests unjoinability itself — the intersection of two orgs' non-blank cell values for a doubly-non-consenting identity must be empty — rather than testing the mechanism the proof credited. **D-13.** |

---

*This document is design-only. No SQL file, migration, rollback, or implementation code was written or applied
in producing it, and no production database was mutated. The frozen constitutions, the demographics spec, and
the role-model spec are unedited.*
