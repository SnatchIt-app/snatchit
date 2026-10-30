# R2 — THE VENUE-SIDE ECONOMIC COUNTERPARTY OF A PRIMARY SALE

**Question:** who is the deterministic settlement/obligation owner for a venue-direct primary sale?
**Method:** read-only static analysis of the frozen corpus `076`–`092` on `feature/venue-native-and-product-v2`.
No SQL executed, no file modified, no migration authored. Every claim carries `file:line`.
**Owner ruling governing this analysis (verbatim):** *"The settlement/obligation owner must be derived from the
actual venue-side economic counterparty defined by the primary-sale contract, not merely the requesting
organization. Any ambiguity must fail closed."*

---

## 0. NAMING CORRECTION (affects every citation downstream)

The function is **`venue.open_settlement`**, not `kernel.open_settlement`
(`supabase/migrations/087_venue_settlement_and_export.sql:227-228`; signature asserted at
`supabase/tests/151_phase2_venue_settlement_and_export.sql:61`). `kernel.close_settlement` (`087:289`) and
`kernel.request_org_payout` (`087:408`) are correctly named. All line numbers below are in
`supabase/migrations/` unless stated otherwise.

---

## 1. WHO IS THE SELLER, PER THE SHIPPED PRIMARY-SALE CONTRACT?

**Answer: `catalog.event.org_id`. One column, stamped once, immutable through every RPC, and propagated
unchanged into the order and into every minted atom.**

### 1.1 The propagation chain (all three hops verified)

| Hop | Column | Stamped from | Site | Ever updated? |
|---|---|---|---|---|
| 1 | `catalog.event.org_id` | `catalog.venue.org_id`, read server-side | `078:877-880` | **No** — see §1.3 |
| 2 | `venue."order".org_id` | the session's event: `select e.status, s.status, e.org_id … from catalog.event_session s join catalog.event e on e.event_id = s.event_id` | derived `082:369-372`, written `082:437-439` | **No** — see §1.4 |
| 3 | `kernel.tickets.org_id` | `v_order.org_id`, passed as `p_ctx->>'org_id'` | `085:2045-2050` → read `083:472` → written `083:557-559` | **No writer exists** |

`082:367-368` states the contract in the corpus's own words: *"org_id is server-derived from the session's
event; never client-trusted."*

### 1.2 `catalog.event.org_id` — who sets it, can it change?

- **Column:** `org_id uuid not null references kernel.organization(org_id) on delete restrict` — `078:137`.
  **NOT NULL**, so it is always set.
- **Sole inserter, corpus-wide:** `catalog.create_event`, `078:879-881`. Exhaustive grep of
  `supabase/migrations/` returns exactly one `insert into catalog.event (…)`. It is **server-derived**:

  ```
  878:  -- org_id is SERVER-DERIVED from catalog.venue.org_id (denormalised for the
  879:  --   authz hot path and kept consistent by THIS function); status := 'draft'.
  880:  insert into catalog.event (venue_id, org_id, title, status)
  881:  values (p_venue_id, v_org_id, trim(p_title), 'draft')
  ```
  where `v_org_id` was read from `catalog.venue` at `078:856-858`. **The caller cannot supply it.**
- **Updates:** `catalog.update_event` (`078:900`) rejects the key **before** authority is even evaluated:
  ```
  943:  -- The unwritable set is checked BEFORE authority so that a patch naming
  944:  --   venue_id / org_id / status raises invalid_input for every caller (T-RPC-CAT-01).
  945-950: for v_key in select jsonb_object_keys(p_patch) loop
             if v_key not in ('title','description','hero_image_ref','category','genre_tags','reason_code')
             then raise exception 'invalid_input: unwritable_key %', v_key; end if;
  ```
  Every other `update catalog.event` in the corpus touches `status` only (`081:955`, `088:1798`).
- **Is there any RPC that changes an event's org?** **No.** There is no re-book, re-assign, transfer-event,
  or set-event-org verb anywhere in `076`–`092`, nor in `supabase/functions/`.

**⇒ `catalog.event.org_id` is write-once and immutable for the life of the event.**

### 1.3 The one column that IS mutable — and it is the venue's, not the event's

`catalog.venue.org_id` (`078:100`) is repointable by `catalog.update_venue`, `078:688-702`:
`platform_admin` only, reason-code required, target org validated, audited. **It performs no cascade to
`catalog.event.org_id`** (verified line-by-line, `078:623-742`; independently confirmed in
`docs/phase2/_decisions/C_operatorship_transfer.md` §1 and §5). `service_role`/`postgres` can also write the
column directly with no RPC, no reason and no audit (Decision C §2).

**This is the sole divergence generator in the shipped system.** See §3.

### 1.4 `venue."order".org_id` — stamped at creation, never updated

- **Column:** `082:78`, NOT NULL, FK to `kernel.organization`.
- **Sole inserter:** `venue.create_primary_checkout`, `082:437-439`.
- **Exhaustive census of `update venue."order"`:** `082:510` (status→cancelled), `085:602` (status→refunded/
  partially_refunded), `085:710` (same), `085:2056` (status→paid), `090:1029` (attribution candidate columns).
  **None of the five touches `org_id`.** The column is effectively append-only.

### 1.5 Corroborating normative text

`docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md:2220` and the paragraph immediately following it:

> A venue is *operated by* one org but may host events booked by *other* orgs (the touring-promoter-rents-the-room case).
> …`event.organization_id` (**who gets paid**, who set the resale policy) is distinct from `event.venue_id`.

The architecture document names the seller explicitly: **the event's org is who gets paid.** That is
`catalog.event.org_id`.

---

## 2. WHAT DOES THE SETTLEMENT ALREADY BIND TO?

`venue.settlement.org_id` (`087:46`) is **already the payee identity**, everywhere downstream. Confirmed on
four independent surfaces.

### 2.1 The payout is written from the settlement's org and is never re-resolved — CONFIRMED

`kernel.close_settlement`, `087:341-343`:

```sql
insert into kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, currency, status, idempotency_key)
values ('organization', v_s.org_id, 'settlement', p_settlement_id, v_net::integer, v_s.currency, 'pending',
        'settlement:' || p_settlement_id::text)
```

`v_s` is the `venue.settlement%rowtype` read under `for update` at `087:297`. **Exhaustive grep of
`payee_org_id` across `supabase/migrations/`** returns: the column definition (`085:114`), the payee XOR CHECK
(`085:140-141`), an index (`085:148`), three read-only predicates (`085:1466`, `087:480`, `088:840`,
`092:673`), and this one INSERT. **There is no `UPDATE … SET payee_org_id` anywhere.** The settlement's org
at close time is the final, permanent payee. It is then resolved to a Stripe destination through
`kernel.organization.stripe_connect_account_ref` for that org (`087:437-440`).

### 2.2 The settlement-line seams join on org — exact quotes

**Royalty/chargeback seam (`kernel.settlement_royalty_lines`, real body `088:319`):**

```
088:341       join kernel.tickets t on t.ticket_atom_id = ms.ticket_atom_id and t.org_id = s.org_id
088:357       join venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id
```

where `s` is the CTE `select st.settlement_id, st.org_id, st.venue_id, st.event_id, st.period_start,
st.period_end, st.currency from venue.settlement st where st.settlement_id = p_settlement_id`
(`088:332-336`). The payee emitted on both arms is `s.org_id` (`088:340`, `088:353`).

**Commission seam (`kernel.settlement_commission_lines`, real body `090:1511`):**

```
090:1527     where a.org_id = v_s.org_id
```
over `venue.attribution`, whose `org_id` is itself stamped from `v_o.org_id` — the **order's** org —
at `090:1129-1132`.

**This is decisive.** Both live seams filter candidate rows by `<row>.org_id = settlement.org_id`, and every
`<row>.org_id` in that comparison is a member of the §1.1 chain rooted at `catalog.event.org_id`. **None of
them is ever `catalog.venue.org_id`.** A settlement whose `org_id` is the venue operator rather than the
selling org therefore matches **zero** lines and closes at `net = 0` — the money is not merely unpayable, it
is invisible.

### 2.3 The export/roster surface resolves the scope's org the same way

`venue.assert_may_request`, `087:605-607` (its own comment):

> XO-1a: the scope's org is resolved HERE from the scope object (session/event → **`catalog.event.org_id`,
> stamped at create**; venue → `catalog.venue.org_id`, the current operator; org → itself).

Implemented at `087:637-648`; the roster row cap reads `t.org_id = v_org` (`087:818`) and the session cap
reads `e.org_id = v_org` (`087:794`).

### 2.4 Refunds already treat the order's org as the money owner

`kernel.refund` evaluates money authority as `kernel.has_org_role(v_order.org_id, ['org_owner','org_finance'])`
(`085:909`), parks approvals with `org_id := v_order.org_id` (`085:1026`, `085:1051`), and matures the money
grant against the same org (`085:917`).

---

## 3. IS `event.org_id` ALWAYS SET, AND IS THE "BOOKED EVENT" CASE REACHABLE TODAY?

**`event.org_id` is NOT NULL (`078:137`) and is derived server-side from `catalog.venue.org_id`
(`078:877-881`). It is never client-supplied.**

### 3.1 The product scenario in the brief is NOT reachable today

There is **no write path in the shipped corpus that creates an event whose `org_id` differs from its venue's
`org_id` at creation time.** The single inserter derives it (`078:879-881`); the updater forbids it
(`078:943-950`); no booking/assignment RPC exists. The corpus states the identity as an assumption in its own
comments — `081:216-219`:

> RM-3: org->venue inheritance is expressed ONLY through the sanctioned helper, never a direct
> `has_org_role` on the denormalised **`event.org_id` (which IS the venue's org)**.

**So "a promoter organization sells an event in another organization's room" cannot be produced by any RPC
today.** It is a documented *product intention* (`SNATCH_IT_DOMAIN_ARCHITECTURE.md:2220` and §1.2) that the
physical schema supports (two independent NOT NULL FK columns, `078:100` and `078:137`) but that no verb
creates. The 090 promoter engine is **not** this case: `venue.promoter` is an *identity* scoped to an org
(`090:68-73`), not a counterparty organization, and `venue.attribution.org_id` is copied from the order
(`090:1132`).

### 3.2 …but the divergence IS reachable today, by a different door — and the consequence is permanent

`catalog.update_venue`'s operatorship arm (`078:688-702`) repoints `catalog.venue.org_id` from Org A to Org B
with **no cascade** to the events already stamped `org_id = A`. Immediately after that call:

| Caller passes | `087:254` (`venue.org_id = p_org_id`) | `087:258` (`event.org_id = p_org_id`) | Result |
|---|---|---|---|
| `p_org_id = A` (the seller of the legacy events) | **FAILS** (venue is now B) | passes | `not_found` |
| `p_org_id = B` (the new operator) | passes | **FAILS** (events are still A) | `not_found` |

**Neither organization can ever open an event-scoped settlement for those events. The state is terminal:**
`catalog.event.org_id` is unwritable (`078:943-950`) and `catalog.venue.org_id` cannot be moved back without a
second platform-admin tenancy move that would strand Org B's own events symmetrically.

This is independently recorded in `docs/phase2/_decisions/C_operatorship_transfer.md` §5.10, which also notes
the transfer is `platform_admin`-only and additionally performable by any `service_role`/`postgres` holder with
no RPC at all (§2).

### 3.3 Severity ruling

- **The conjunction bug at `087:254`+`087:258` is real and reachable today** — via operatorship transfer, not
  via a promoter booking. Reaching it requires a `platform_admin` (or direct SQL), so it is **not
  attacker-initiated**; it is a *self-inflicted permanent data state* produced by a legitimate, audited,
  staff-initiated business operation (a room changes hands).
- **It is not, today, a money-loss defect on its own**, because a *correctly* opened settlement is equally
  worthless: there is no primary-sale line seam at all. The only `insert into venue.settlement_line` in the
  repository is `087:318`, fed by exactly two seams (`088:319` royalty/chargeback, `090:1511` commission);
  **neither emits a primary-sale revenue line**, and `venue.finalize_primary_order` (`085:1881-2078`) writes no
  settlement, no line and no payout. See `docs/phase2/_decisions/A_venue_money.md` §1.1-1.2. **R2's predicate
  is a prerequisite for Decision A's fix, not a substitute for it, and neither is sufficient alone.**
- **It is a correctness prerequisite that must ship in the same package as Decision A's
  `kernel.settlement_primary_lines`.** Decision A's proposed seam emits `payee = settlement.org_id`
  (`A_venue_money.md:454`) and selects orders in the settlement's scope; with the current predicate that seam
  can never be reached for an operatorship-transferred venue, and would attribute revenue to the wrong org if
  the predicate were "fixed" by relaxing `087:258` instead of `087:254`.

---

## 4. WHO SHOULD OWN THE SETTLEMENT?

### 4.1 Are (a) `catalog.event.org_id` and (c) `venue."order".org_id` always identical by construction?

**YES — identical by construction, not by convention, and provably so.**

`venue."order".org_id` has exactly one writer, `venue.create_primary_checkout` (`082:437-439`), whose value
comes from `082:369-372`:

```sql
select e.status, s.status, e.org_id
  into v_evt_status, v_sess_status, v_org_id
  from catalog.event_session s
  join catalog.event e on e.event_id = s.event_id
 where s.session_id = p_session_id;
```

and no `UPDATE` anywhere writes the column (§1.4 census). `catalog.event_session.event_id` is NOT NULL with an
`on delete restrict` FK (`078:172`) and is not in `catalog.update_event_session`'s writable set. Therefore for
every order row, at every instant:

```
venue."order".org_id ≡ catalog.event.org_id  (of the event owning the order's session)
```

**This makes the fix much smaller: (a) and (c) are the same fact expressed at two grains, so the predicate
needs only ONE of them, and the event-grain one is already in the function at `087:258`.**

### 4.2 Verdict on the three candidates

| Candidate | Verdict | Reason |
|---|---|---|
| **(a) `catalog.event.org_id`** | **THE OWNER** | Write-once (`078:879-881`), NOT NULL (`078:137`), unwritable by any RPC (`078:943-950`), the root of the entire seller chain (§1.1), what every live seam joins on (§2.2), what the export surface resolves (§2.3), and what the architecture names as "who gets paid" (`SNATCH_IT_DOMAIN_ARCHITECTURE.md:2220`). Available at both settlement grains — directly for `p_event_id`, and via `catalog.event.venue_id` for the period grain. |
| **(b) `catalog.venue.org_id`** | **REJECTED** | It is the *operator of the room*, not the counterparty of the sale. It is **mutable** (`078:701`) and its mutation is exactly what breaks the current predicate (§3.2). Binding money to a mutable tenancy pointer means a room sale silently re-assigns the prior operator's receivables. **No settlement line seam joins on it.** |
| **(c) `venue."order".org_id`** | **Equivalent to (a), but wrong grain for the header** | Identical by construction (§4.1) and correct as the *line-level* filter (`088:357`, `090:1527` via `attribution.org_id`). But the header must exist **before** any order is settled, and a period settlement may legitimately hold zero orders — so the header cannot derive its owner from orders without failing on the empty case. Use (a) for the header; (c) stays the line filter it already is. |

**Deterministic economic owner: `catalog.event.org_id`.**

---

## 5. THE MINIMAL CORRECT PREDICATE

### 5.1 Statement (body-only replacement for `venue.open_settlement`, `087:237-240` and `087:253-260`)

Two edits, both inside the function body. No DDL. No signature change. No new table, column or index.

**Edit 1 — bind the venue-role authority arm to the current operator (`087:237-240`).**
Today the arm is `kernel.has_venue_role(p_venue_id, ['venue_finance']) OR kernel.has_org_role(p_org_id,
['org_finance','org_owner'])`. Once the scope binding stops requiring `venue.org_id = p_org_id`, that first
arm would let a room's `venue_finance` open a header **payable to a different org**. Conjoin the E-76
current-operator clause onto the venue arm, in the identical shape already used by `kernel.close_settlement`
at `087:299-300` and by `venue.assert_may_request` at `087:657`:

> The caller is authorized iff **either** (i) the caller holds `venue_finance` on `p_venue_id` **and** the
> venue's current operator org equals `p_org_id`, **or** (ii) the caller holds `org_finance` or `org_owner` on
> `p_org_id`. Otherwise `42501`.

The promoter path travels arm (ii), which is correct: the selling org's own finance opens the selling org's
own settlement.

**Edit 2 — replace the two scope-binding checks (`087:253-260`) with a grain-split binding.**

> **Always:** the venue must exist. `if not exists (select 1 from catalog.venue v where v.venue_id =
> p_venue_id)` → raise `not_found: venue %` with `P0002`. (Existence only; drop the `and v.org_id = p_org_id`
> conjunct from this check.)
>
> **Event-scoped (`p_event_id is not null`) — the deterministic arm:** the event must exist, must sit in this
> room, and **its own `org_id` must equal `p_org_id`**:
> `exists (select 1 from catalog.event e where e.event_id = p_event_id and e.venue_id = p_venue_id and
> e.org_id = p_org_id)`; otherwise raise `not_found: event % for venue % / org %` with `P0002`.
> **This is byte-identical to today's `087:257-259`.** The entire event-scoped fix is the *removal* of the
> venue∈org conjunct from the always-check — the event conjunct was already exactly right.
>
> **Period-scoped (`p_event_id is null`) — fail closed, unchanged:** `p_org_id` must be the venue's **current
> operator**: `exists (select 1 from catalog.venue v where v.venue_id = p_venue_id and v.org_id = p_org_id)`;
> otherwise `not_found: venue % for org %` with `P0002`. This is today's `087:254-255` verbatim, retained for
> this grain only.

Every raise stays `P0002 not_found` (never `insufficient_privilege`), preserving the frozen AUTHZ-C1C
non-disclosure posture stated at `087:222-224`.

### 5.2 The four required behaviours, each discharged

| Requirement | Discharged by | Why |
|---|---|---|
| **Venue org selling at its own venue works exactly as today** | both grains | When `event.org_id = venue.org_id = p_org_id` (the only state any RPC can create today, §3.1), the event arm passes exactly as `087:258` does now and the period arm is untouched. **Zero behaviour change on every state reachable through the shipped write paths.** |
| **Promoter org at another org's venue can open a settlement owned by the correct counterparty** | event-scoped arm | `e.org_id = p_org_id` binds the header's `org_id` to the seller. `venue.settlement` already permits `org_id ≠ venue's org` — its two FKs are independent (`087:46-47`), with no cross-constraint. The seams then match: `t.org_id = s.org_id` (`088:341`), `o.org_id = s.org_id` (`088:357`), `a.org_id = v_s.org_id` (`090:1527`). |
| **An unrelated org is refused** | both grains | Event grain: `e.org_id ≠ p_org_id` ⇒ `P0002`. Period grain: `v.org_id ≠ p_org_id` ⇒ `P0002`. Authority arm (i) additionally requires operatorship, and arm (ii) requires org membership on `p_org_id`. |
| **An ambiguous case fails closed** | period grain | A venue+period window can span events sold by several orgs; the window has **no unique economic counterparty**. The predicate therefore admits only the venue's current operator at that grain and refuses everyone else. Widening it (e.g. "any org with an event at this venue in the window") is **deliberately NOT part of this fix** — it is a separate owner decision, and until taken, the promoter's grain is the event. |

### 5.3 Regression posture against the shipped pgTAP suite

Both existing scope-binding assertions in `supabase/tests/151_phase2_venue_settlement_and_export.sql` stay
green without edit:

- **C2b** (`151:215-216`) — `org1 + venue1 + event2`: `event2.venue_id = venue2 ≠ venue1` (fixture
  `151:179-187`), so the retained `e.venue_id = p_venue_id` conjunct still raises `P0002`.
- **C2c** (`151:219-220`) — `org2 + venue1 + NULL event`: a **period** settlement, and `org2` is not `venue1`'s
  operator, so the retained period arm still raises `P0002`. The test's stated rationale — *"the payee would
  otherwise be caller-chosen"* — is precisely the property the fix preserves.

### 5.4 Every other `org_id = p_org_id` check in 087, adjudicated

| Site | Check | Correct under the new model? |
|---|---|---|
| `087:247-249` — idempotency-replay conflict | `s.org_id = p_org_id and s.venue_id = p_venue_id and s.event_id is not distinct from p_event_id` | **Yes, unchanged.** Pure parameter-equality against the header this key already created. Independent of who owns what. |
| `087:299-302` — `kernel.close_settlement` authority | `(has_venue_role(v_s.venue_id,['venue_finance']) AND catalog.venue.org_id = v_s.org_id) OR has_org_role(v_s.org_id,['org_finance']) OR is_platform(['platform_admin'])` | **Yes, unchanged — and it is already the model's exemplar.** For a promoter-owned settlement the E-76 conjunct at `087:300` makes the venue arm **fail** (room operator ≠ settlement org), so the room's `venue_finance` cannot close another org's settlement; the promoter's `org_finance` can, via `087:301`. This is the desired semantics with **no edit**. |
| `087:341-343` — payout mint | `payee_org_id := v_s.org_id` | **Yes, unchanged.** Now names the seller. Never re-resolved (§2.1). |
| `087:417-423` — `kernel.request_org_payout` | `has_org_role(p_org_id,['org_owner','org_finance'])` then `v_s.org_id <> p_org_id ⇒ not_found` under the header's `for update` | **Yes, unchanged.** No venue arm exists at all, so a room role never reaches it. All four money controls (SoD-1 setter `087:429-431`, grant maturity `087:432-434`, AAL2 step-up `087:437-444`, destination probation) read `kernel.organization` for `p_org_id` — the **promoter's** Connect destination, which is correct. |
| `087:637-659` — `venue.assert_may_request` | session/event scope org ← `catalog.event.org_id`; venue arm E-76-bound at `087:657` | **Yes, unchanged — already correct.** A promoter's export is authorized by the promoter's org roles; the room's venue roles are excluded because `venue.org_id ≠ event.org_id`. |
| `087:794`, `087:818` — export session cap / row cap | `e.org_id = v_org`, `t.org_id = v_org` | **Yes, unchanged.** Both on the event/ticket chain. |
| `087:1299`, `087:1370`, `087:1425-1428` — `list_export_jobs`, `list_attendees`, `lookup_attendee` | E-76 conjunct on the venue arm | **Yes, unchanged.** |
| `087:1232`, `087:1248` — `reconcile_export_orphans` | `j.org_id = p_org_id` on `venue.export_job` | **Yes, unchanged.** Storage-prefix scoping; orthogonal. |
| `088:341`, `088:357` — royalty & chargeback seams | `t.org_id = s.org_id`, `o.org_id = s.org_id` | **Yes** — and they only start matching rows once the header carries the seller's org. |
| `090:1527` — commission seam | `a.org_id = v_s.org_id` | **Yes, unchanged.** |

**Net: `venue.open_settlement` is the only function whose org checks change. Every downstream org check is
already written against `settlement.org_id` or the event chain and is correct — or more correct — under the
new model.**

### 5.5 One economic ambiguity the fix SURFACES but must not silently resolve

`kernel.settlement_royalty_lines` emits `market_sale.venue_royalty_minor` with `payee_id = s.org_id`
(`088:339-340`). Under the corrected model, for a promoter-sold event the **"venue royalty" on a resale would
be credited to the promoter's settlement, not to the room operator** — while `royalty_bps` itself is settable
at venue *or* event scope (`catalog.set_resale_policy`, `078:1318`, venue arm `078:1377-1379`). Today this is
invisible because the two orgs are always the same entity (§3.1). **Per the owner's fail-closed instruction,
this is flagged, not resolved:** it is an owner policy question ("does a resale royalty belong to the room or
to the seller when they differ?") and it must be answered before any RPC is created that lets a promoter book
another org's room. It does **not** block the predicate fix, because no such booking path exists.

---

## 6. RLS IMPLICATIONS — A CONFIRMED CROSS-TENANT FINANCIAL DISCLOSURE

### 6.1 What the policies say

```
087:74  revoke all on venue.settlement from anon, authenticated;
087:75  grant select on venue.settlement to authenticated;          -- NOT column-scoped
087:78-81  create policy venue_settlement_sel_org … using (kernel.has_org_role(org_id,
             array['org_owner','org_admin','org_finance'])
             or kernel.is_platform(array['platform_admin','platform_support','platform_risk']));
087:82-84  create policy venue_settlement_sel_venue … using (
             kernel.has_venue_role(venue_id, array['venue_manager','venue_finance']));
```
```
087:116     grant select on venue.settlement_line to authenticated;  -- NOT column-scoped
087:117-121 create policy venue_settlement_line_sel_org … has_org_role(s.org_id, …) or is_platform(…)
087:122-125 create policy venue_settlement_line_sel_venue … using (exists (select 1 from venue.settlement s
              where s.settlement_id = venue.settlement_line.settlement_id
                and kernel.has_venue_role(s.venue_id, array['venue_manager','venue_finance'])));
```

`kernel.has_venue_role` (`080:60-73`) probes `venue.staff_role` on `(venue_id, auth.uid(), role)` **and
nothing else**. It has no knowledge of who operates the venue and no knowledge of the settlement's org.

### 6.2 The finding

**Yes — this is a privacy leak, and it is confirmed.** Under the corrected model, where
`settlement.org_id` may be a PROMOTER org while `settlement.venue_id` points at a room operated by a different
org, **any holder of `venue_manager` or `venue_finance` at the ROOM reads the PROMOTER's settlement in full**:

- **Header (`087:83-84`):** `org_id`, `event_id`, `period_start/end`, `status`, and **all four money columns
  `gross_minor`, `fees_minor`, `refunds_minor`, `net_minor`** plus `currency`. The `grant select` at `087:75`
  is whole-table, so no column-level backstop exists.
- **Lines (`087:123-125`):** every `cause`, signed `amount_minor`, and `cause_ref` — i.e. the promoter's
  individual `order_id`s, `sale_id`s, `dispute_id`s and `attribution_id`s, with amounts. Finer-grained than
  the header, and equally exposed.

That is the promoter's complete revenue, fee load, refund exposure and per-transaction ledger, disclosed to a
commercial counterparty who merely rents them the room.

### 6.3 It is not a new leak — the fix makes an existing one routine

**These two policies are the only settlement surfaces in 087 that lack the E-76 current-operator conjunct
their sibling RPCs carry** (`087:299-300`, `087:657`, `087:1299`, `087:1370`, `087:1425-1428`).
`docs/phase2/_decisions/C_operatorship_transfer.md` §4 explains why: E-76 was raised late, as a local
amendment to 087's *verbs*, and was never promoted into the shared predicate `kernel.has_venue_role`
(`080:60-73`); §5.10 already records these two policies as **REACHABLE** for a stale-staff holder after an
operatorship transfer. The predicate fix changes the leak from *"reachable only after a platform-admin tenancy
move"* to *"reachable on every promoter-booked event"*, so it **must be closed in the same package**.

### 6.4 Required accompanying change

Conjoin the E-76 clause onto both venue-arm policies, in the shape already proven at `087:299-300`:

> `venue_settlement_sel_venue` — additionally require that the settlement's venue's **current operator org
> equals the settlement's own `org_id`**: `(select v.org_id from catalog.venue v where v.venue_id =
> venue.settlement.venue_id) = venue.settlement.org_id`.
>
> `venue_settlement_line_sel_venue` — the same clause inside the existing `exists (… venue.settlement s …)`
> sub-select, against `s.venue_id` and `s.org_id`.

Effects: a venue operator keeps full venue-arm visibility of **its own** settlements at **its own** room (no
behaviour change on any state the shipped RPCs can create); a promoter's settlement at a foreign room becomes
invisible to that room's staff; and, as a correct side-effect, a departing operator's staff lose the venue arm
over legacy settlements after a transfer — the intended E-76 semantics. Reads by the settlement's true owner
are unaffected: they travel `venue_settlement_sel_org` (`087:79-81`), which already keys on `org_id`.

Two further hardening items, noted but **not** required for this fix:
- `grant select` on both tables is whole-table (`087:75`, `087:116`), so there is no column-level backstop if a
  policy is ever mis-edited. Column-scoping the money columns would be defence in depth.
- The clean structural fix is to promote E-76 into `kernel.has_venue_role` itself (`080:60-73`), which would
  close this class everywhere at once — but that predicate is called from 15+ frozen sites across `078`–`090`
  and changing it is a far larger blast radius than 093 should carry.

---

## 7. SUMMARY

1. **The deterministic venue-side economic counterparty is `catalog.event.org_id`** — NOT NULL (`078:137`),
   server-derived once (`078:877-881`), unwritable by every RPC (`078:943-950`), propagated immutably into
   `venue."order".org_id` (`082:369-372`, `082:437-439`) and `kernel.tickets.org_id` (`085:2047` → `083:557`),
   joined by every live settlement-line seam (`088:341`, `088:357`, `090:1527`), and named "who gets paid" by
   `SNATCH_IT_DOMAIN_ARCHITECTURE.md:2220`.
2. **`catalog.event.org_id` and `venue."order".org_id` are identical by construction**, so the header needs
   only the event-grain fact — which `087:258` already checks correctly.
3. **The bug is the *conjunction*, not the event check.** `087:254`'s `venue.org_id = p_org_id` is a second,
   independent requirement that is correct only for the period grain and wrong for the event grain.
4. **The minimal fix is body-only, two edits, no DDL:** conjoin E-76 onto the venue-role authority arm
   (`087:237-240`), and split the scope binding by grain — event-scoped binds to `event.org_id` alone
   (`087:257-259` verbatim), period-scoped keeps `venue.org_id = p_org_id` (`087:254-255` verbatim) and fails
   closed for everyone else.
5. **No downstream org check needs to change.** `close_settlement` (`087:299-302`) and `request_org_payout`
   (`087:417-423`) are already correct — indeed already correct *only* under this model.
6. **The RLS leak is real and must ship in the same package:** `087:83-84` and `087:123-125` are the only
   settlement surfaces in 087 without the E-76 conjunct their sibling RPCs carry.
7. **Severity:** the promoter-booking scenario is unreachable through any shipped write path; the divergence is
   reachable today only via the `platform_admin` operatorship transfer (`078:688-702`) — where it renders the
   affected events **permanently unsettleable by either org**. The predicate fix is a **prerequisite** for
   Decision A's missing `primary_sale` seam, not a substitute: today a correctly-opened settlement still closes
   at `net = 0` because no seam emits primary revenue (`A_venue_money.md` §1.1-1.2).
