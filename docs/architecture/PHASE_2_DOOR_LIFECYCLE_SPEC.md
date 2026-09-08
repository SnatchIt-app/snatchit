# Phase 2 — Door Lifecycle Specification (Owner Ruling O-5)

**Status:** BUILD-READY DELTA SPEC. **Design-only — no SQL files, no migrations, no implementation code.**
SQL snippets appear inline only to pin the *shape* of a constraint or trigger; they are illustrative, not
deliverables. This document is a **delta** on the frozen Phase-2 specification set; it does not edit the
constitution documents (`SNATCH_IT_DOMAIN_ARCHITECTURE.md`, `SNATCH_IT_CANONICAL_DATA_MODEL.md`).
Integration into the six implementation specs happens in a later pass.

**Authority:** Owner ruling **O-5** (door lifecycle, RATIFIED) and **O-4** (door authority, RATIFIED).

**Binding inputs (authority order):**
1. `docs/architecture/PHASE_2_SPEC_FOUNDATION.md` — SSCAS + global lock order, C36 role model, D3 causes.
2. `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` — §0.6–§0.9, §1.5, §1.12, §2.3, §3.10–§3.12.
3. `docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md` — §0 conventions, §7, §8, §9, §12.4, §14.
4. `docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md` — §1.1, §4, §8.3, §9.10–§9.12, §11, §14.3.
5. `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` — §5.4, §5.5, §5.6.
6. `docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` §4.4/§4.5/§7/§10.2 ·
   `docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §12 (Δ1, §22.7).
7. `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` — C6, C23, C37, C41, C43.

> **Migration-numbering note — RESTATED ON THE CANONICAL SCALE.** The canonical numbering authority is
> `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md`. Two bands, never to be confused: **`071`–`075` are applied
> production security migrations** (real, applied, immovable SQL — *not* Phase-2 packages), and **Phase-2
> packages occupy `076`–`091`** (design-only; no SQL authored).
>
> The frozen specs (RPC §16.2, RLS §15.2, edge §9.6, review §5 A2/A3) cite migration **`073`** for
> `door_open_at`, and an earlier revision of this note named the PHASE-C package
> **`075_catalog_reference_data_and_flags`**. **Both are pre-renumber tokens and both are now wrong** — the
> first on the S0 scale (`071`–`086`, offset +5), the second on the S2 scale (`073`–`088`, offset +3). They
> decode to the same package, and its canonical identity is **`078_catalog_reference_data_and_flags`** —
> registry §2, PHASE C, the package that creates `catalog.event_session` (including `door_open_at`) and every
> feature-flag and config seed. On the canonical scale `073` and `075` name **applied production security
> migrations**, so quoting either for `door_open_at` now points at the wrong band, not merely at the wrong
> number.
>
> This document continues to name the **catalog migration package** in its body rather than repeating a
> number; where a number is unavoidable it is `078`, decoded via the registry and never by arithmetic on a
> stale token (registry §4: the plan carried three scales simultaneously, so arithmetic alone is not safe —
> decode by *package identity*, i.e. what the sentence says the package creates).
>
> The door substrate itself (`venue.door_pin`, `door_session`, `scan`, the manifest tables) is package
> **`086`**, and `venue.export_job` / settlement is **`087`**. (Unrelated to all of the above: *production*
> migration `075` — `075_replay_parity_storage_policies_and_cron.sql` — is the cron-job repair referenced in
> §0.)

**Change-class tags.** Every element below carries exactly one:
`NO SCHEMA CHANGE` · `ADDITIVE SCHEMA CHANGE` · `SPEC CORRECTION` · `NEW RPC` · `NEW EDGE FUNCTION` ·
`NEW RN SURFACE` · `NEW DASHBOARD SURFACE`.

**O-5 requirement traceability.**

| Req | Requirement (abbrev.) | Where discharged |
|:--:|---|---|
| 1 | only authorized server-side RPCs establish the boundary | §4 · §7.1 · §7.4 · §10A.7 |
| 2 | principals: `org_owner`, `org_admin`, `venue_manager` | §4 |
| 3 | `scanner` cannot set or alter it | §4 · §4.2 · §10A.1 · pgTAP 21–22 |
| 4 | opening atomically establishes the boundary | §6 (one txn) · §6.1 (isolation) |
| 5 | boundary cannot move backwards or be cleared | §2 · §10.2 · pgTAP 8–13 |
| 6 | override: explicit · elevated · audited · reason-coded · history preserved | §8 · §12.1 · pgTAP 46–51 |
| 7 | behaviour when NULL near event time; fail closed | §3 · §3.1 · §14 · pgTAP 14–18 |
| 8 | relationship of all eight concepts | §9.3 |
| 9 | close must not erase the boundary | §1 · §7.2 · pgTAP 10 |
| 10 | the missing open/close RPCs; clients never UPDATE directly | §7.1 · §7.2 · §7.4 · §10A.4 |
| 11 | RLS + trigger protections | §10.2 · §10A |
| 12 | audit events | §12.1 |
| 13 | pgTAP coverage (described, not authored) | §15 — 76 assertions |
| 14 | the Wallet stale-pass guarantee is **true** | §5.3 theorem + corollary · **§5.4 (its exact scope)** · §9.2 · §9.4 · §19.1 |


---

## 0. The gap, stated precisely

`catalog.event_session.door_open_at` is **read** in four places and **written by nothing**:

| Reader | Where | What it does |
|---|---|---|
| `kernel.is_transfer_frozen(p_ticket_atom_id)` | schema §2.3, catalog migration package | `door_open_at IS NOT NULL AND now() >= door_open_at` |
| custody RPC rechecks | RPC §12.4, RLS §14.3 | reject with `frozen` under the atom lock |
| RN client | RN §4.4.1/§4.5/§12(5) | disables Transfer / Sell |
| venue dashboard | VD §12.4, §6 session cards | renders "Door open — transfers closed" |

Review **R3** records the signal FIXED and addenda **A2/A3 CLOSED**. What was actually fixed is only the
*canonical form* — this column rather than a `kernel.tickets.transfer_frozen` boolean. **No RPC in the
contract set writes it.** The venue dashboard spec independently found the same hole (VD §12.4 "Gap", Δ1) and
left the authority question open (VD §22.7).

A nullable timestamp with no writer means `is_transfer_frozen()` returns **false forever**, the C6/C23/C43
offline-door transfer freeze **never engages**, and the Apple-Wallet / stale-pass safety property the design
claims is **false**. This is the precise failure shape of the production cron job that production migration `075` repaired:
present, correct, and called by nothing.

**This document closes it.** Along the way it surfaces five further defects in the frozen set that the same
mechanism exposes (§13). Four of them are load-bearing and one of them (§13.1) would deny admission to every
paying fan on the night doors open.

---

## 1. State model (the whole lifecycle in ten lines)

```
                       ┌─────────────────────────── implicit backstop (no operator action) ──────────┐
                       │                                                                             ▼
session created ──► [ NO EPISODE ]  door_open_at = NULL          now() >= COALESCE(doors_at, starts_at)
   (scheduled)          transfers: OPEN                                     ⇒ transfers FROZEN
                        offline door: UNAVAILABLE                             (boundary is implicit,
                        online door: gated only by session.status='live'       door_open_at still NULL)
                             │
        venue.open_door_manifest (org_owner | org_admin | venue_manager)
                             ▼
                      [ EPISODE OPEN ]  ── door_open_at := this episode's opened_at (FIRST open only, forever)
                        transfers: FROZEN (explicit)     offline door: ARMED (signed manifest, versions pinned)
                             │                                    online door: unchanged (live kernel read, C37)
        venue.close_door_manifest ──►  [ EPISODE CLOSED ]  offline door: DISARMED · transfers: STILL FROZEN
                             ▲                       │            door_open_at: UNCHANGED (history preserved)
                             └──── re-open (new episode, new manifest_version, door_open_at NOT moved) ◄──┘
                                                     │
        kernel.grant_door_freeze_override (platform_admin only, TTL-bounded, reason-coded, audited,
        requires NO open episode) ──────────────────► transfers TEMPORARILY permitted; door_open_at UNCHANGED
```

**Read as three orthogonal facts, not one flag:**

> **Deltas (§7.7).** An open episode's admissible set is `base_snapshot ⊕ deltas`. Atoms minted after the open
> (box-office sales, late comps) append `add`; atoms voided by an exempt path append `revoke`. Both narrow or
> extend the set safely and neither touches the boundary.

| Fact | Signal | Monotone? | Cleared by close? |
|---|---|---|---|
| *Has this session's custody been frozen?* | `effective_freeze_at(session) <= now()` | **yes, terminal** | no |
| *Is an offline manifest live right now?* | `EXISTS(venue.door_manifest WHERE status='open')` | no (episodic) | yes |
| *May this door admit?* | `catalog.event_session.status = 'live'` + atom state | no | no (close ends the *offline* path only) |

The single most important consequence: **the freeze is monotone and terminal for the session; the manifest is
episodic.** Conflating them is what makes a "single mutable column that must never move backwards" a smell.

---

## 2. Where the invariant actually lives (monotonicity — think-hard Q3)

**Ruling: neither an append-only-by-trigger `door_open_at`, nor a separate `freeze_engaged_at`.**

`catalog.event_session.door_open_at` becomes a **cached monotone head of an append-only episode ledger** —
structurally the same pattern the system already ratified for `kernel.tickets.current_owner_id` and
`credential_version` as heads of `kernel.ticket_ownership_log` (schema §1.5, C27/C28). The source of truth is
the ledger; the column is a projection maintained by a single writer, and monotonicity is a *derivation*, not
a rule someone has to remember.

```
door_open_at  ≡  (SELECT MIN(opened_at) FROM venue.door_manifest WHERE session_id = <s>)
```

Because episodes are stamped with the transaction's own `now()` and the ledger is INSERT-only, `MIN(opened_at)`
can only ever be the **first** open. No second open moves it; no close clears it; no UPDATE path exists.
"Cannot move backwards" stops being a rule and becomes arithmetic.

**Why not a separate `freeze_engaged_at` column:** it would create a *second* freeze signal, which is exactly
the duplication addenda A2/A3 closed. One signal, one source (RPC §12.4) survives intact — every existing
reader keeps reading `door_open_at` and the helper keeps its signature.

**Why the column is retained at all rather than making the helper read the ledger directly:** the helper is on
the custody hot path (every listing, transfer, accept, void). A single-row read on `catalog.event_session`,
already fetched for the session gate (§5), is one b-tree probe. An aggregate over the ledger is not. The head
is a performance projection with a trigger-enforced equality to its source — the C27 pattern verbatim.

---

## 3. The effective freeze boundary (req 7 — fail-closed at NULL)

`SPEC CORRECTION` to `kernel.is_transfer_frozen`, plus one new helper.

```
catalog.effective_freeze_at(p_session_id)  →  timestamptz NOT NULL          -- NEW RPC (STABLE helper)
  := LEAST(
       door_open_at,                                              -- explicit: first manifest open (nullable)
       COALESCE(doors_at, starts_at) + config('door.implicit_freeze_offset_interval')
     )                                                            -- implicit backstop: NEVER null
```

`starts_at` is `NOT NULL` (schema §2.3), so `effective_freeze_at` is **total** — there is no input for which it
returns NULL, and therefore no input for which the freeze silently never engages. That is the fail-closed
property req 7 demands, expressed as a type, not a promise.

```
kernel.is_transfer_frozen(p_ticket_atom_id) →
     now() >= catalog.effective_freeze_at(session_of(atom))
 AND NOT EXISTS (active, unexpired kernel.door_freeze_override covering this atom)     -- §8
```

`NO SCHEMA CHANGE` to the helper's signature or its call sites. `SPEC CORRECTION` to its body: the current
predicate `door_open_at IS NOT NULL AND now() >= door_open_at` is replaced. Every existing caller — RPC §12.4,
RLS §14.3, edge §9.6, RN §12(5), and the catalog migration package — is unaffected.

**Config key** (`ADDITIVE SCHEMA CHANGE` — a seed row, not a column): `catalog.platform_config` key
`door.implicit_freeze_offset_interval`, value interval, **default `'0 minutes'`** (freeze exactly at
`doors_at`). Positive values delay the implicit freeze; negative values pull it earlier. AO-per-version like
every other config (schema §2.4).

**Why `doors_at`, not `starts_at`, is the primary backstop:** `doors_at` is when humans physically arrive and
when a scanner is realistically armed. `starts_at` (the headline time) is often an hour later. Freezing at
`starts_at` would leave an hour of live-door / open-transfer overlap — the exact window C6 exists to close.

**Failure direction, deliberately asymmetric.** A wrong `doors_at` that is too early freezes transfers early:
an operational annoyance, recoverable by the §8 override. A wrong `doors_at` that is too late is bounded by
`starts_at` — `LEAST` also takes the explicit boundary, so an operator who opens the manifest at any time gets
the earlier of the two. There is no input that produces "never frozen."

### 3.1 What a NULL `door_open_at` at event time means, concretely

| Actor | Sees | Rationale |
|---|---|---|
| **Fan** | Transfer / Sell disabled from `doors_at`. Copy unchanged: *"Transfers are closed while the event is underway."* (RN §4.5 — no manifest vocabulary, product-language rule) | The fan cannot tell explicit from implicit, and must not need to. |
| **Online scanner** | **Admits normally.** Manifest state is irrelevant to it. | C37: the online door does a live authoritative per-scan kernel read at the decision point. It never consulted a manifest for liveness and must not start. |
| **Offline scanner** | **Cannot admit.** There is no manifest to verify against, because the manifest artifact is *produced by* the open RPC. Scanner state: *"Doors aren't open yet — this device needs a connection to admit."* (`NEW RN SURFACE`, §11.2) | No manifest ⇒ no offline authority. This is the pre-existing C6/C37 contract, not a new failure. |
| **Venue dashboard** | Session card shows **"Transfers closed — door manifest not opened"** with an inline Open control. | The operator must be able to tell the two apart; the fan must not. |

**Does an unopened manifest block admission? No — and this is a ruling, not an omission.** Admission is gated
by `catalog.event_session.status = 'live'` and the atom's own state (RPC §9.4 preconditions), never by manifest
state. Gating admission on the manifest would fail closed *against paying fans at the door* — a worse
real-world outcome than the stale-transfer risk it would mitigate, and one the online live-read (C37) already
covers. **The manifest gates offline scanning only.** That line is the load-bearing distinction of this spec.

---

## 4. Authority matrix (reqs 1–3; O-4/O-5 binding)

> **CORRECTED 2026-08-28 (reviewer condition 4 · `DL-X1`).** This section, §4.1, §4.2, §7.1, §7.2, §7.5,
> §10.1, §10A.1, §10A.2, **§10A.7**, §15 and §16 OQ-3 all carried the **abolished** label `venue_door` and, in
> two places, the **abolished door-PIN authorization arm**. Both were closed by ratified authority that this
> file is downstream of, and neither correction reached it:
> - **`venue_door` is renamed `venue_scanner`** (O-2 / ROLE_MODEL §4.5 / schema §0.6 / RLS §2.1). The rename is
>   substantive, not cosmetic: a label named `venue_door` asserts authority over *the door*; the principal's
>   real authority is over *scanning against an already-open manifest*. The abolished label is exactly what
>   §4's own argument is about, so carrying it here read as deliberate.
> - **The `door_pin` arm is closed by `AUTHZ-H3`.** A `door_pin` is a **provisioning** fact on a table with no
>   device column — it says a PIN was issued for a venue, never that *this device* holds it. Authorizing the
>   manifest read on the PIN alone is possession inferred from provisioning. The ratified predicate is
>   token-bound: `kernel.assert_door_session` **asserted with a token** and bound to that session.
>
> **The authority was already right — RLS §11.4 and the edge spec both carry the corrected token-bound form.
> This file is what a door implementer reads.** `T-RLS-EXEC-02` catches the abolished-label class on merge,
> but **it is scoped to predicates in RLS §11 and structurally cannot see this file**, which is why the
> residue survived here and nowhere else. See §20.

`SPEC CORRECTION` to VD Δ1, which proposed `has_venue_role([venue_manager, venue_scanner])` (Δ1 was written
against the pre-O-2 label `venue_door`). **O-4/O-5 remove the scanner from the manifest-administration set.**
VD §22.7 explicitly left this open and inferred the door principal was correct; the owner ruled otherwise, and
the ruling is right: a `door_pin` is a loginless, shared, deliberately weak device identity (domain §1.8) and
opening the manifest freezes custody for an entire session.

| Principal | Predicate | open | close | re-open | override | scan under open manifest |
|---|---|:---:|:---:|:---:|:---:|:---:|
| `org_owner` | `has_org_role(org_of_venue,[org_owner])` | ● | ● | ● | ✗ | — |
| `org_admin` | `has_org_role(org_of_venue,[org_admin])` | ● | ● | ● | ✗ | — |
| `venue_manager` | `has_venue_role(venue,[venue_manager])` | ● | ● | ● | ✗ | ● |
| `venue_scanner` (**scanner**) | `has_venue_role(venue,[venue_scanner])` **or the `service_role` edge path with `kernel.assert_door_session` asserted with a token and bound to that session** (`AUTHZ-H3`; **never a bare `door_pin`**) | ✗ | ✗ | ✗ | ✗ | ● |
| `box_office` | *no physical enum label* — see §4.1 | ✗ | ✗ | ✗ | ✗ | — |
| `venue_finance` · `venue_box_office` · `venue_marketing` · `venue_promoter_manager` · `org_finance` · `org_marketing` · `org_promoter_manager` · `org_member` | — | ✗ | ✗ | ✗ | ✗ | ✗ |
| `platform_admin` | `is_platform([platform_admin])` | ● | ● | ● | **●** | — |
| `platform_risk` · `platform_support` | — | ✗ | ✗ | ✗ | ✗ | ✗ |
| `service_role` | definer only | ● (sweeps) | ● (sweeps) | — | ✗ | — |

● = authorized · ✗ = denied (deny-by-default; `insufficient_privilege` 42501)

Org→venue inheritance follows RLS §2.4: expressed **inside the RPC predicate**
(`has_venue_role(venue,[venue_manager]) OR has_org_role(org_of_venue,[org_owner,org_admin])`), never by
widening venue RLS to org roles.

### 4.1 `box_office` does not inherit manifest administration (O-4, explicit)

> **CORRECTED 2026-08-28 (`DL-X2`) — this paragraph's premise expired.** It argued from a **four-label**
> venue enum in which no box-office label existed. The canonical venue set is **six** labels
> (schema §0.6 / ROLE_MODEL §3.1–§3.3 / RLS §2.1), and **`venue_box_office` is one of them.** The
> conclusion below is unchanged and remains correct — RLS §11.4 explicitly excludes `venue_box_office` from
> `open_door_manifest` / `close_door_manifest` — but the *reason* was wrong and the *remedy* ("a fifth enum
> label") was obsolete: the label exists, and it is already denied. What survives is the narrower
> over-provisioning problem, restated below.

The canonical C36 venue enum is exactly
`venue_manager | venue_finance | venue_box_office | venue_marketing | venue_promoter_manager | venue_scanner`
(schema §0.6/§3.9 — **six** labels; the four-label set that named `venue_door` and `venue_promoter` is
superseded). **`venue_box_office` exists and is explicitly excluded from manifest administration by RLS
§11.4** — so "box_office does not inherit manifest administration" is now true *structurally*, not merely by
the absence of a label to grant.

**The residual problem is narrower, and it is a grant-hygiene problem rather than a missing-label problem.**
VD §22.2 flags that a box-office seller may still be granted `venue_manager` in practice — because
`venue_box_office` does not yet carry the selling capabilities such a person needs — and a person granted
`venue_manager` *for box-office selling* thereby also gains the ability to open the door manifest. **This spec
does not create a role to fix that.** Narrowing it requires the `venue.staff_role.event_id` / per-capability
scoping delta (VD Δ8), **not** a new enum label — **owner decision, §16 OQ-3, restated.**

### 4.2 What the scanner may do (O-4)

`venue_scanner`, **or the `service_role` edge path under a token-bound door session** (`kernel.assert_door_session`,
`AUTHZ-H3` — **never a bare `door_pin`**): fetch and sync an **already-open** manifest, scan, admit, and queue
offline scans for reconciliation. It may **not** open, close, or re-open a manifest, and it holds no write path
to `catalog.event_session` at all (RLS §8.3 already gives `venue_scanner` `SEL` only — `NO SCHEMA CHANGE`,
`NO RLS CHANGE` for that row). The scanner UI must therefore render a *waiting* state, not a disabled button,
when no episode is open (§11.2).

---

## 5. The session gate — how open and transfer are serialized (think-hard Q1 & Q2)

This is the mechanism the entire specification rests on.

### 5.1 The lock

`SPEC CORRECTION` to RPC §0.4 / §14.2, additive to the lock-order proof.

Every RPC that can move custody, or that reads the freeze boundary to decide, acquires a **shared lock on the
session row first**:

```sql
-- illustrative shape only
SELECT session_id, door_open_at, doors_at, starts_at, status
  FROM catalog.event_session
 WHERE session_id = <resolved from the atom>
   FOR SHARE;                      -- Event/Session, global lock rank 1
```

`venue.open_door_manifest` and `venue.close_door_manifest` acquire the **exclusive** lock on the same row:

```sql
SELECT ... FROM catalog.event_session WHERE session_id = p_session_id FOR UPDATE;   -- rank 1
```

**Lock-order legality (proof obligation discharged).** The global order is
`Event/Session(1) < Inventory(2) < Order(3) < Listing(4) < Ticket Atom(5) < Payment/Payout/Reserve/Settlement(6)`
(schema §0.9, RPC §14.2). Rank 1 is the **lowest** rank in the total order, so prefixing *any* acquisition
sequence with it is unconditionally ascending. Every affected member re-proves trivially:

| Member | Before | After | Ascending? |
|---|---|---|---|
| #2 native sale (`transfer_ticket_ownership`) | 4 → 5 → 6 | **1** → 4 → 5 → 6 | ✔ |
| #6 listing create (`create_listing` → `lock_ticket`) | 4 → 5 | **1** → 4 → 5 | ✔ |
| #7 p2p start (`create_p2p_transfer` → `lock_ticket`) | 4 → 5 | **1** → 4 → 5 | ✔ |
| #8 p2p accept (`accept_p2p_transfer`) | 4 → 5 → 6 | **1** → 4 → 5 → 6 | ✔ |
| #3 refund-void (`void_ticket_atom`, routine path) | 2 → 5 → 6 | **1** → 2 → 5 → 6 | ✔ |
| #12 C25 sweep (`sweep_paid_pending_sales`) | 4 → 5 → 6 / 5 → 6 | **1** → … | ✔ |
| #1 primary issuance (`issue_ticket_atoms`) | (Event/Session *read*-gate at 1) → 2 → 3 → 5 → 6 | **1 (now a lock)** → 2 → 3 → 5 → 6 | ✔ |
| **open / close door manifest** (new) | — | **1** (+ bounded batch of #6-/#7-reverse: 1 → 4 → 5) | ✔ |
| **`append_door_manifest_delta`** (new, §7.7) | — | none of its own — runs under the caller's rank-1 `FOR SHARE` | ✔ |

No back-edge is introduced anywhere. Cross-member deadlock-freedom (RPC §14.2, Coffman #4 broken by resource
ordering) is preserved by construction.

**Contention.** `FOR SHARE` is shared: arbitrarily many concurrent transfers hold it simultaneously and do not
block each other. Only `FOR UPDATE` — taken once per manifest episode, i.e. roughly twice per session per
night — conflicts. Cost per custody RPC is one extra single-row b-tree lock on a row it already needed to read
to resolve the freeze. RPC §14.1 already models an "Event/Session read-gate at 1" for member #1; this promotes
that read-gate to a real lock and extends it to the custody members.

### 5.2 Two managers press "Open doors" simultaneously (Q1)

**Lock:** `catalog.event_session` PK row, `FOR UPDATE`, rank 1.
**SSCAS position:** `SSCAS: n/a (single-aggregate — Event/Session)`. Open and close write
`venue.door_manifest` + `venue.door_manifest_entry` (children of the Session aggregate, keyed by `session_id`,
only ever reachable under the session lock), `catalog.event_session.door_open_at` (the Session aggregate's own
head), and `kernel.admin_audit` (audit plane, outside the six money/custody ranks — every privileged RPC does
this and is still tagged `SSCAS: n/a`, per RPC §14.3). The p2p/listing drain (§7.3) is a **bounded batch of the
existing member #7-reverse / #6-reverse (the unlock overlay)** — the same construction RPC §14.1 row 10 uses to
classify `catalog.cancel_event` as a bounded batch of member #3. **The set stays closed at fifteen; no
sixteenth member and no amendment are required.**

**Resolution of the race:** the first transaction to acquire `FOR UPDATE` wins. The second blocks, then on
acquisition re-reads the session and finds an episode with `status='open'` already present, and returns
`{ status: 'noop_replay', manifest_id: <the existing one>, … }`. It does **not** insert a second episode, does
**not** issue a new `manifest_version`, and does **not** touch `door_open_at`. Both operators see "Door open."
Two-layer idempotency per RPC §0.2: the state guard above, *plus* `UNIQUE(session_id, command_idempotency_key)`
on `venue.door_manifest` for literal double-taps of the same command.

### 5.3 A p2p transfer commits at the instant the manifest opens (Q2)

**Which wins:** whichever transaction acquires the session row first. This is a *total order* imposed by the
database, not a wall-clock coincidence, and it is the same total order every observer sees.

- Accept-then-open: the accept holds `FOR SHARE`; the open blocks on `FOR UPDATE` until the accept commits.
  When the open proceeds, its snapshot (§6) reads the **new owner's** bumped `credential_version`. The transfer
  won; the manifest is correct about it.
- Open-then-accept: the open holds `FOR UPDATE`; the accept blocks. When it proceeds it re-reads
  `effective_freeze_at` under its own `FOR SHARE`, finds `now() >= boundary`, and rejects with `frozen`. The
  open won; no version changed after the snapshot.

There is no third outcome, and no window between them.

**Is the answer the same for the online scanner and for a scanner holding a 90-second-old snapshot? Yes — but
for two different reasons, and both must hold:**

- **Online scanner:** trivially yes. It performs a live authoritative per-scan kernel read at the decision
  point (C37, RPC §9.3 + §9.4). It observes the committed outcome whichever it was. The manifest is not in its
  decision path at all.
- **Offline scanner, 90-second-old snapshot:** yes, **only because of two properties this spec adds.**
  1. **The snapshot and the boundary are one transaction** (§6). There is no interval in which the manifest
     has been read but the freeze is not yet in force — which is precisely the interval in which a transfer
     would strand a credential.
  2. **The manifest carries `credential_version` per atom**, and the offline door rejects on mismatch (§9).
     Without this the offline door *cannot detect a stale credential at all* — see §13.3, where the frozen edge
     spec's offline verify steps are enumerated and contain no version check.

  Given both, the snapshot cannot have gone stale, because nothing that could stale it can commit while the
  episode is open. 90 seconds old and 0 seconds old are the same snapshot.

**Door Safety Theorem (custody).** *For every atom in an open manifest episode, `current_owner_id` at scan
time equals the owner recorded in that episode's snapshot, and `credential_version` equals the snapshot value
for every atom that is still admissible.*
**Proof.** The snapshot is taken under `FOR UPDATE` on the session row, in the same transaction that writes the
boundary. Every RPC that can **move custody** for an atom of that session — `kernel.transfer_ticket_ownership`
(the sole custody engine, domain §9.4) and its callers `market.accept_p2p_transfer` / native checkout — first
acquires `FOR SHARE` on that same session row (§5.1) and rejects when `now() >= effective_freeze_at` (§3).
A transaction holding `FOR SHARE` before the open began commits before the open's `FOR UPDATE` is granted and
is therefore *in* the snapshot (READ COMMITTED gives the post-lock statement a fresh snapshot — §6.1). A
transaction requesting `FOR SHARE` after the open commits observes the boundary and is rejected. No third case
exists. ∎

**Corollary (req 14).** An offline door that verifies signature ∧ key-window ∧ session ∧ `exp` ∧
`credential_version == manifest[atom].credential_version` ∧ `manifest[atom]` is admissible admits exactly the
current owner's credential and rejects every stale one. **No two people are ever admitted on one atom, and the
wrong owner is never admitted.** The Apple-Wallet / cached-pass safety guarantee is **true**, not claimed.

### 5.4 The scope of the theorem — corrected, and confirmed for the Wallet proof

> This subsection exists because `PHASE_2_APPLE_WALLET_SPEC.md` §4.3(a) builds its stale-manifest denial on a
> stronger reading of the theorem than the theorem supports. **The correction below is mine, not theirs:** the
> theorem as first written quantified over "every RPC that can bump `credential_version`", which is **false** —
> §13.4 (also mine) exempts the C25 compensate branch, and `void_ticket_atom` bumps the version. The theorem is
> restated above over **custody moves**, which is both true and the dimension the Wallet non-negotiable
> actually needs.

**What is guaranteed, unconditionally, from the first open onward.** `door_open_at = MIN(opened_at)` is a
monotone, terminal head (§2) and `effective_freeze_at <= door_open_at` forever (§3). Therefore
`is_transfer_frozen` is true at **every instant at or after the first open**, closing an episode does not clear
it (§7.2), and re-opening does not move it (§7.1). Consequently **no custody move for any atom of the session
can commit at any time ≥ the first open** — so every episode's snapshot, however old, records the **same owner
and the same `credential_version` for every atom that is still admissible.** An older episode's manifest is not
stale in the dimension the Wallet guarantee depends on. *Wallet spec §4.3(a) is **confirmed** on this point.*

**What is NOT guaranteed — three exempt paths bump `credential_version` without moving custody.** All three
void the atom (`state → voided`, D2/§7.6):

| Exempt path | Elevated? | Audited? | Routine? |
|---|:--:|:--:|:--:|
| `catalog.cancel_event` | yes | yes | no — and DL-2 (§7.2) now closes the episode outright, so this case cannot reach an offline door that reconnects |
| `kernel.force_void_ticket` / `kernel.admin_refund` | yes (`platform_admin`/`platform_risk`) | yes | no — break-glass |
| **C25 compensate branch of `market.sweep_paid_pending_sales`** | **no** | no | **yes — an automatic sweep** |

The third is the one neither spec had named. A compensating sweep can void an atom that the open episode's
snapshot records as `active` at version `N`; a device holding that snapshot would then admit a **refunded**
ticket. This is a **revocation** failure, not a custody failure: no second person is admitted, and the wrong
owner is never admitted — the atom's own holder is admitted on a ticket that has been refunded. It is a
revenue leak of exactly the shape C23 names and C6 has always classified as *shrunk, not closed*.

**It is now bounded rather than merely conceded.** §7.7 adds an append-only **manifest delta log** carrying
`revoke` entries; every exempt void writes one when an episode is open, and a device applies deltas up to its
last synced sequence. A device that is online drops the atom immediately; a device that is offline carries the
residual, bounded by the `not_after` it downloaded — which is the same bound every offline decision already
has. **Wallet spec §4.3's residual list must be extended by this third path** (see §19, DL-3).

**Net effect on the Wallet spec's four scenarios.** Scenarios 1, 2 and 4 are unaffected. Scenario 3(a) is
confirmed as written for transfers. Scenario 3's "named residual" must gain the C25 compensate path and must
be described as a *revocation* residual rather than a custody one — in the case it currently describes (an
override between episodes) it would indeed admit the pre-override owner, and that part stands.

---

## 6. Atomic open (req 4) — the exact transaction

`venue.open_door_manifest` performs, in **one** transaction, in this order:

1. `SELECT … FROM catalog.event_session WHERE session_id = p_session_id FOR UPDATE` — rank 1.
2. Predicate check (§4) against live tables (C36/I-5). Deny → `insufficient_privilege`, zero writes.
3. Precondition check (§7.1). Deny → `precondition_failed`, zero writes.
4. Idempotency: an episode with `status='open'` exists → return it as `noop_replay`. Stop.
5. **Drain** open p2p transfers and open listings for this session (§7.3) — bounded batch of members
   #7-reverse / #6-reverse, locks Transfer(4) → Ticket Atom(5) ascending by `ticket_atom_id`.
6. INSERT `venue.door_manifest` — `opened_at := now()`, `manifest_version := next per-session`, `status='open'`,
   `opened_by := auth.uid()`, `reason_code`, `not_after := now() + config('door.manifest_ttl_interval')`.
7. **Snapshot** — INSERT `venue.door_manifest_entry` for **every** atom of the session (§9.2's completeness
   ruling), recording `(ticket_atom_id, serial_no, ticket_type_id, credential_version, signing_key_id,
   ticket_state, resale_state)` **as read after step 1's lock**. **`SPEC CORRECTION` (`MP-1`): this step
   previously omitted `resale_state`** — so the *writer* did not populate the column that §10.3 declares
   `not null` and that `OFFLINE-VERIFY-v1` conjunct 3b.v reads. The column list here, §10.3's column list and
   §7.5's projection are **the same list, deliberately**: this is the write, that is the store, and §7.5 is
   the read, and a field dropped from any one of the three is a conjunct the door cannot evaluate.
8. Compute and store `manifest_digest` over the ordered entry set. **The digest covers the full column list
   in step 7**, so a projection that returns less than the digest covers is detectable, and a snapshot that
   *writes* less is a failed INSERT rather than a quiet omission.
9. `catalog.engage_door_freeze(p_session_id, opened_at)` — definer-only primitive that owns the
   `catalog.event_session.door_open_at` write; a no-op when already set (§10.2).
10. INSERT `kernel.admin_audit` (`session.door_manifest_open`).
11. INSERT outbox envelopes `DoorManifestOpened` (+ `TransferFreezeEngaged` on first open only) (§12).

Commit. Steps 5–11 either all commit or none do.

### 6.1 Isolation requirement (load-bearing implementation note)

`open_door_manifest` **must run at READ COMMITTED** (the PostgreSQL default) and the snapshot SELECT of step 7
**must be issued after** the lock acquisition of step 1. Under READ COMMITTED each statement takes a fresh
snapshot, so step 7 observes every transfer that committed while the open was blocked on `FOR UPDATE`. Under
REPEATABLE READ the transaction snapshot is fixed at first statement and step 7 would read *pre-lock* state —
silently producing a manifest that is already stale at birth, which defeats the theorem. State this in the
function header; it is not inferable from the contract.

### 6.2 No client-supplied timestamp, ever

`open_door_manifest` accepts **no** boundary parameter. `opened_at := now()` is server-derived (C35). A future
boundary would reintroduce exactly the hazard this design removes: the manifest snapshot taken now, the freeze
in force later, and a transfer legally committing in between. A CHECK enforces it at rest:

```sql
-- illustrative
CHECK (opened_at <= now())                                   -- venue.door_manifest
```

Scheduled opens are a **scheduler calling this RPC at the scheduled time** (`ADDITIVE SCHEMA CHANGE` — nothing;
`NEW DASHBOARD SURFACE` — optional, §11.1), never a stored future timestamp.

---

## 7. RPC contracts

Naming follows the venue-dashboard delta (VD Δ1) so the two specs do not fork: **`venue.open_door_manifest` /
`venue.close_door_manifest`**. The ruling's conceptual names `open_event_door_manifest` /
`close_event_door_manifest` are recorded as documented aliases under the review §2.1 canonical-name registry
convention.

### 7.1 `venue.open_door_manifest(p_session_id, p_reason_code, p_command_key)` — `NEW RPC` — **DB-RPC**

- **Purpose:** open (or re-open) the session's offline door manifest and, on the first open ever, atomically
  engage the session's terminal transfer-freeze boundary.
- **Role:** `has_venue_role(venue_of_session,[venue_manager])` OR
  `has_org_role(org_of_venue,[org_owner,org_admin])` OR `is_platform([platform_admin])`. Live-table recheck
  (I-5). **`venue_scanner` and the door session denied** (O-4; the abolished `venue_door` label and the bare `door_pin` arm are both closed — `DL-X1`).
- **Params:** `p_session_id` uuid (untrusted, re-resolved), `p_reason_code` text from the closed set
  `{doors_open, reopen_device_failure, reopen_operator, drill}` (untrusted, validated), `p_command_key` text.
- **Server-derived (C35):** `auth.uid()`, `opened_at := now()`, `manifest_version`, `not_after`,
  `manifest_digest`, the entry snapshot. **No client timestamp is accepted** (§6.2).
- **Preconditions:**
  - session exists and `status ∈ {scheduled, live}` (never `completed` / `cancelled`);
  - the parent event `status ∈ {on_sale, live}` (never `draft` / `announced` / `cancelled`);
  - `now() >= COALESCE(doors_at, starts_at) - config('door.manifest_early_open_window')`
    (default `'12 hours'` — early opening is permitted and encouraged for pre-sync at soundcheck, §14.5, but
    not arbitrarily early);
  - no `kernel.door_freeze_override` is active for this session (§8) — an override and an open manifest are
    mutually exclusive by construction.
- **Locks & order:** `catalog.event_session` **FOR UPDATE** (rank 1) → [drain: `market.p2p_transfer` /
  `market.listing_native` FOR UPDATE (rank 4) → `kernel.tickets` FOR UPDATE ascending `ticket_atom_id`
  (rank 5)] → inserts. Ascending; no inversion (§5.1).
- **SSCAS:** `n/a (single-aggregate — Event/Session)`; the drain is a **bounded batch of members #7-reverse and
  #6-reverse** (§5.2).
- **Idempotency:** state guard (an `open` episode returns `noop_replay` with the existing `manifest_id`) +
  `UNIQUE(session_id, command_idempotency_key)` on `venue.door_manifest`.
- **Writes:** `venue.door_manifest` (INSERT), `venue.door_manifest_entry` (INSERT N),
  `catalog.event_session.door_open_at` (via `catalog.engage_door_freeze`, first open only),
  `market.p2p_transfer` / `market.listing_native` (drained → `cancelled` + `reason_code='door_freeze'`),
  `kernel.tickets.resale_state` (→ `none`, via `kernel.unlock_ticket` — the sanctioned overlay primitive),
  `kernel.admin_audit`.
- **Result:** `{ status, manifest_id, manifest_version, entry_count, opened_at, door_open_at,
  freeze_newly_engaged(bool), drained_transfers, drained_listings }`.
- **Errors:** `insufficient_privilege(42501)` · `not_found` · `precondition_failed`
  (`session_terminal` | `event_not_live` | `too_early` | `override_active`) · `idempotency_replay`
  (returns the original).
- **Retry:** safe and re-entrant.
- **Forbidden callers:** `venue_scanner`, any door-session principal (token-bound or not), `venue_box_office`,
  finance roles, marketing roles, promoter-manager roles, fans, `platform_support`, `platform_risk`.

### 7.2 `venue.close_door_manifest(p_session_id, p_reason_code, p_command_key)` — `NEW RPC` — **DB-RPC**

- **Purpose:** end the current offline manifest episode. **Does not unfreeze; does not touch `door_open_at`**
  (req 9).
- **Role:** as §7.1.
- **Params:** `p_session_id`, `p_reason_code` ∈ `{doors_closed, session_ended, operator_close, device_recall}`,
  `p_command_key`.
- **Preconditions:** an episode with `status='open'` exists for the session. None → `noop_replay` (terminal-
  state idempotency), never an error.
- **Locks & order:** `catalog.event_session` **FOR UPDATE** (rank 1) → `venue.door_manifest` row.
- **SSCAS:** `n/a (single-aggregate — Event/Session)`.
- **Writes:** `venue.door_manifest` (`status → 'closed'`, `closed_at := now()`, `closed_by`, `close_reason`),
  `kernel.admin_audit` (`session.door_manifest_close`). **Explicitly writes nothing to
  `catalog.event_session`.**
- **Result:** `{ status, manifest_id, closed_at, admitted_count, offline_pending_count }`.
- **Errors:** `insufficient_privilege(42501)` · `not_found`.
- **Note:** `offline_pending_count > 0` is surfaced, not blocking — close must never be prevented by devices
  that have not reconciled, or a lost device would pin a session open forever. Reconciliation of a closed
  episode remains legal (§9.3).

#### 7.2.1 `catalog.cancel_event` must close every open episode — `SPEC CORRECTION` (Wallet **DL-2**, accepted in full)

§7.6 exempts `catalog.cancel_event` from the freeze — correctly, since the session is being cancelled — but as
first written this spec never **closed the episode**. §14 failure #11 covered only the online path
(`record_scan` requires `status='live'`). **An offline scanner would keep admitting into a cancelled show until
it reconnected.** Accepted as stated; the Wallet spec is right and the gap was mine.

**Correction.** `catalog.cancel_event` must, inside its existing cancellation transaction and under the
Event/Session lock it already holds (rank 1, RPC §4.4):

1. call `venue.close_door_manifest(session_id, 'event_cancelled')` for **every** session of the event that has
   an open episode — a bounded batch, same-aggregate, **no new SSCAS member**;
2. set `not_after := now()` on those episodes, so any device that reconnects before its downloaded horizon
   still refuses;
3. write a `revoke` delta (§7.7) for every atom it voids, so a device that syncs once before going offline
   again drops them;
4. emit `DoorManifestInvalidated` (§12.2 #44) so online devices disarm immediately.

**Residual, stated in §14 #20 rather than glossed:** a device that never reconnects between the cancellation
and its manifest's downloaded `not_after` continues to admit offline. Nothing the server does reaches it. The
bound is the TTL it already holds, and the operational control is that cancelling an event with live synced
devices must warn the operator with the device count (§11.1). This is C6's window, named.

### 7.3 Drain semantics (part of §7.1; `SPEC CORRECTION`)

Without this step, the ratified set **locks paying fans out of the show.**

`kernel.mark_ticket_scanned` requires `resale_state = 'none'` — *"a `listed`/`locked` atom cannot be scanned —
'delist first'"* (RPC §7.5, verbatim). Once the freeze engages, `accept_p2p_transfer` is rejected as `frozen`
(§13.2), so a pending transfer's atom stays `locked` until its C43 TTL expires — which may be hours. A fan
whose ticket is mid-transfer or listed therefore arrives at the door and is refused, with no action available
to them and none to the door.

**Ruling:** on open, before the snapshot, the RPC drains the session's in-flight market overlays:

| Overlay | Action | Mechanism | Excluded |
|---|---|---|---|
| `market.p2p_transfer` `status='initiated'` | → `cancelled`, `reason_code='door_freeze'`; atom unlocked, returned to the sender | `market.cancel_p2p_transfer` (definer, sender-side path) — **cancel-back-to-self, which C43 explicitly exempts from the C6 freeze** because owner and `credential_version` do not change | none |
| `market.listing_native` `status='active'` | → `cancelled`, `reason_code='door_freeze'`; atom unlocked | `market.cancel_listing` (definer, platform-cancel branch) | any listing with a `market.market_sale` in `sale_state='paid_pending_transfer'` — **money is already taken; the C25 sweep owns that row** (§13.4) |

The drain moves no custody, appends no ownership-log row, and bumps no `credential_version` — it only clears
the `resale_state` overlay. The theorem is unaffected (nothing it protects changes), and the snapshot taken
immediately after records `resale_state='none'` for the drained atoms.

**Residual:** an atom whose sale is `paid_pending_transfer` at door-open stays `locked` and is refused at the
door with reason `listed_locked` (VD §12.5). §13.4 rules that such sales resolve as `compensated` (buyer
refunded), which is the correct outcome — the buyer was never going to get a working credential through an
offline door.

**Product consequence to sign off (§16 OQ-2):** a seller's active listing is cancelled when doors open. The
alternative — leave it listed and refuse the holder at the door — is strictly worse. Notification is a
`ListingCancelled` push with reason copy *"Your listing closed because doors opened."*

### 7.4 `catalog.engage_door_freeze(p_session_id, p_opened_at)` — `NEW RPC` — **DB-RPC, definer-only**

- **Purpose:** the **sole writer** of `catalog.event_session.door_open_at`. Sets it iff currently NULL;
  otherwise a no-op returning the existing value.
- **Actor:** `service_role`/definer only. `REVOKE EXECUTE FROM anon, authenticated, public`; **GRANT to
  `service_role` only.** Never client-callable, never in an RLS EXEC row.
- **Why it exists:** `venue.*` writing `catalog.*` directly would be a cross-schema write outside the
  single-writer discipline (schema §0.1). This mirrors `venue.record_scan → kernel.mark_ticket_scanned`
  exactly: the owning schema exposes a definer primitive; the calling schema calls it in the same transaction.
- **Preconditions:** caller holds `FOR UPDATE` on the session row (asserted, not assumed — the primitive
  re-takes it, which is a no-op re-entrant acquisition in the same transaction).
- **Writes:** `catalog.event_session.door_open_at` only. Never NULLs it. Never changes a non-NULL value.
- **Result:** `{ door_open_at, newly_engaged(bool) }`.

### 7.5 `venue.get_door_manifest(p_session_id, p_since_delta_seq)` — `NEW RPC` — **DB-RPC (read)**

> **`SPEC CORRECTION` — `MP-1`, the projection defect.** The shape this section previously returned —
> `entries[{ ticket_atom_id, serial_no, credential_version, signing_key_id, ticket_state }]` — **omits
> `resale_state`**, and RPC §20.6.1's independently-written shape for the same function omits **`ticket_state`**
> and, on its delta row, **`signing_key_id`**. `OFFLINE-VERIFY-v1` (edge §5.4.3) reads all four. **A conjunct
> whose input the wire never carries is not a check; it is a comment.** Conjunct 3b.v was therefore dead on
> this projection, 3b.iv dead on RPC §20.6.1's, and 3c dead for every atom supplemented after doors open —
> which is **H-2 reproduced at the client, failing in the admitting direction** (Wallet §10.2). The two
> documents also described **two different wire shapes** for one function, which is the drift mechanism, not
> just its instance. Both are reconciled below and in RPC §20.6.1 to **one** shape, and §7.5a states the
> superset rule that makes a recurrence mechanically detectable rather than a reading exercise.
>
> The parameter is also renamed. This section said `p_since_version`, §7.7 and §15 assertion 69 said
> `p_since_seq`, RPC §20.6.1 said `p_since_delta_seq` — **three names, and the first names the wrong
> quantity.** `manifest_version` counts *episodes* and `seq` counts *deltas within an episode*; a device
> passing its `manifest_version` where a delta cursor is expected re-downloads or skips silently. **Canonical:
> `p_since_delta_seq`**, the spelling RPC §20.6.1 contracted under `G-15`.
- **Purpose:** the scanner's manifest fetch/sync read. Returns the open episode's header + entries + deltas.
- **Actor:** `has_venue_role(venue,[venue_scanner, venue_manager])` OR the `service_role` edge path with
  `kernel.assert_door_session` **asserted with a token** and bound to that session (RLS §11.4, `AUTHZ-H3`).
  **Not a bare `door_pin`** — a `door_pin` is a provisioning fact on a table with no device column, so it
  cannot evidence that *this* device holds it. Reachable only via `door-session` `/manifest/sync`
  (edge §9 item 17, §16 OQ-7); **corrected `DL-X3`.**
- **Preconditions:** an episode with `status='open'` and `not_after > now()` exists. Otherwise returns
  **`{ open: false, status: 'no_open_manifest' }`** with empty `entries[]`/`deltas[]` — **not an error**, so
  the scanner can render the waiting state (§11.2). **Both keys are returned, deliberately:** §11.2 and RN §7
  branch on the `no_open_manifest` label, RPC §20.4.4 and §20.6.1 branch on the `open` boolean, and returning
  one of the two would have broken whichever consumer read the other.
- **Returns:** `{ open, manifest_id, manifest_version, session_id, opened_at, not_after, manifest_digest,
  max_delta_seq, entries[], deltas[] }` — the shape stated identically in RPC §20.6.1, where an entry is

  ```
  entry := { ticket_atom_id, serial_no, ticket_type_id,
             credential_version, signing_key_id, ticket_state, resale_state }
  ```

  and a delta row is **op-conditional** (§7.5a):

  ```
  delta(op='add')    := { seq, ticket_atom_id, op } ∪ entry     -- the FULL entry payload
  delta(op='revoke') := { seq, ticket_atom_id, op }              -- membership removal needs nothing more
  ```

  `session_id` is load-bearing, not header decoration: `OFFLINE-VERIFY-v1` conjunct 3 and its
  no-offline-authority clause both require the device to refuse *"an M2 for another session"*, which it
  cannot determine from a manifest that does not say which session it is for. RPC §20.6.1 omitted it.
  **`p_since_delta_seq` NULL ⇒ full snapshot + all deltas; non-NULL ⇒ deltas only** (the cheap reconnect poll).
  **No owner identity, no PII, no ticket-type price** — this is the door's only bulk read and the hard rule
  "door staff never receive a bulk attendee list" (domain §7.2, VD §5 note 11) binds: the manifest carries
  opaque atom ids and versions, never names. **`ticket_type_id` is a catalog reference, not an identity
  column**, and does not weaken that rule or pgTAP assertion 6 / `T-RPC-DOOR-17`, both of which assert over
  the *identity-bearing* column set; it is what lets the scanner show the tier on the admit banner.
- **Writes:** none. (The device's `last_sync_at`/`manifest_version` update stays on the existing manifest-sync
  RPC, RLS §9.11 note 33.)
- **SSCAS:** n/a (read).

#### 7.5a The projection superset rule — `SPEC CORRECTION` (`MP-1`), BINDING

**Every field `OFFLINE-VERIFY-v1` reads per atom MUST appear in the entry projection, and in the `op='add'`
delta projection.** The predicate is the single normative statement (edge §5.4.3) and is not editable from
here; this rule is its *delivery* obligation, and it is stated as a superset — not an equality — so a
projection may carry operator-facing extras (`serial_no`, `ticket_type_id`) without drifting.

Derived mechanically from the fenced block, **not transcribed from a prior list**:

| Block clause | Reads | Kind | Carrier |
|---|---|---|---|
| applied-set line | `manifest_id`, delta `seq` ordering, device-held `last_synced_seq` | header + delta | both |
| 1, 2 | `key_id`, `status`, `not_before`, `not_after`, `public_key` | **M1**, not M2 | edge §5.4.2 — out of scope here |
| 3 | the manifest's **`session_id`** | header | **was missing from RPC §20.6.1** |
| 3a | `token.exp` ± 2 time-buckets | token + a constant | **bucket size: RPC §9.3** |
| 3b.i | `ticket_atom_id` (membership in M2) | per-atom | both |
| 3b.ii | an applied `revoke` delta ⇒ delta `op` + `ticket_atom_id` | per-delta | both |
| 3b.iii | `credential_version` | per-atom | both |
| 3b.iv | **`ticket_state`** | per-atom | **was missing from RPC §20.6.1** |
| 3b.v | **`resale_state`** | per-atom | **was missing from §7.5** |
| 3c | **`signing_key_id`** | per-atom | **was missing from the delta row in both** |
| no-M2 clause | header `not_after`, header `session_id` | header | `session_id` was missing from RPC §20.6.1 |
| 4 | the device's local admitted set | device-local | no wire field |

So the per-atom read set is **five** fields — `ticket_atom_id · credential_version · ticket_state ·
resale_state · signing_key_id` — and the header read set adds **`session_id`** and **`not_after`**.

> **`MP1-READ-SET` — this table is the ONE literal enumeration, and §15 assertions 77/78 consume it
> (`R3-5`).** Named so it can be cited instead of re-typed. **Per atom (5):** `ticket_atom_id` ·
> `credential_version` · `ticket_state` · `resale_state` · `signing_key_id`. **Header (2):** `session_id` ·
> `not_after`. **Delta row (2, the 3b.ii linkage):** `op` · `ticket_atom_id`.
> **Four of the five per-atom names are the `M2[atom].<field>` references of 3b.iii, 3b.iv, 3b.v and 3c;
> the fifth, `ticket_atom_id`, is the membership key of 3b.i and carries no `.field` suffix.** That
> asymmetry is not incidental — a parse that looks only for `M2[atom].<field>` finds **four**, and an
> assertion demanding five from that one pattern is unsatisfiable against a correct block. §15 assertion 78
> therefore runs **four** patterns and compares each against its own enumeration.
> **Adding a conjunct to `OFFLINE-VERIFY-v1` (edge §5.4.3, and only there) requires updating this table in
> the same change**; assertion 78 fails until it is, in both directions, which is the intended coupling.

**Why the delta rule is op-conditional rather than "all fields always".** A `revoke` delta only removes an
atom from the admissible set; the device evaluates nothing against it beyond 3b.ii, so requiring a version or
a key on it would be ceremony that a writer would eventually fill with a placeholder. An `add` delta is the
*only* carrier for an atom that is not in the base snapshot, so every conjunct must be evaluable from it
alone. **This is the same asymmetry §10.3a's CHECKs already encode** — `(op='add') = (credential_version IS
NOT NULL)` and `(op='add') ⇒ signing_key_id IS NOT NULL` — and §10.3a is extended in the same shape rather
than restated loosely here: the rule is one sentence of prose *because* the database enforces it.

**The gap this closes, concretely.** §10.3a's `signing_key_id` CHECK exists because *"a supplemented atom with
no pinned key would be structurally unadmittable offline."* The column was made mandatory and then **not
projected** — so the value was stored, guaranteed present, and never sent. A door-sale atom minted after doors
open was unadmittable at every offline scanner for exactly the reason the CHECK was written to prevent.

### 7.6 Freeze recheck set — `SPEC CORRECTION` to RPC §12.4

RPC §12.4 names four rechecking functions. That set is **wrong in one direction and incomplete in two others.**

| RPC | §12.4 today | This spec | Why |
|---|:---:|:---:|---|
| `market.create_listing` | rechecks | rechecks | correct |
| `market.create_p2p_transfer` | rechecks | rechecks | correct |
| `kernel.lock_ticket` | rechecks | rechecks | correct |
| **`kernel.mark_ticket_scanned`** | **rechecks → rejects `frozen`** | **MUST NOT recheck** | **§13.1 — as written, no fan can be admitted after doors open** |
| **`kernel.transfer_ticket_ownership`** | absent | **rechecks (the enforcement point)** | sole custody engine; enforcing here makes bypass structurally impossible |
| **`market.accept_p2p_transfer`** | absent | **rechecks** | §13.2 — otherwise the freeze gates transfer *start* but not *completion* |
| **`kernel.void_ticket_atom`** (routine refund path only) | absent | **rechecks** | C23 extends the freeze to refund-voids |
| `market.cancel_p2p_transfer` (cancel-to-self) | — | **exempt** | C43, ratified: owner and version unchanged, nothing can strand |
| `market.cancel_listing` | — | **exempt** | delisting strands nothing |
| `catalog.cancel_event` | — | **exempt** | the session is being cancelled; no admission will occur |
| `kernel.force_void_ticket` / `kernel.admin_refund` | — | **exempt, audited** | platform break-glass; residual is the C6 reconcile window |
| `market.sweep_paid_pending_sales` — **compensate** branch | — | **exempt** | §13.4 — otherwise money gets stuck |
| `market.sweep_paid_pending_sales` — **complete** branch | — | **frozen** | it is a custody move |
| `kernel.issue_ticket_atoms` (door sale · comp · import) | — | **exempt — never frozen** | minting from ∅ is not a custody move; door-sale inventory (`release_kind='door'`, VD §8.5) exists precisely to be sold after doors open. See §7.7 |

**Every exempt path that voids an atom MUST write a `revoke` delta** when an episode is open (§7.7). This is
the obligation that turns §5.4's revocation residual from conceded into bounded, and it applies to all three
voiding exemptions: `catalog.cancel_event` (which also closes the episode outright, §7.2),
`kernel.force_void_ticket`/`admin_refund`, and the C25 compensate branch. Omitting it re-opens exactly the leak
§5.4 identifies.

**Defense in depth, deliberately:** the *enforcement* point is `kernel.transfer_ticket_ownership` (and
`kernel.lock_ticket`) — the choke-points nothing bypasses. The caller-level rechecks
(`create_listing`, `create_p2p_transfer`, `accept_p2p_transfer`) exist for **error quality**, so the fan sees
"Transfers are closed" rather than a generic engine failure. Both layers must hold, matching the edge spec's
"both layers must hold" idempotency discipline (§7 of that spec).

### 7.7 `venue.append_door_manifest_delta(p_session_id, p_atoms, p_op, p_cause_ref)` — `NEW RPC` — **DB-RPC, definer-only**

Closes Wallet **DL-1** (post-open issuance) and §5.4's revocation residual with **one** mechanism. Without it,
a fan who buys at the box office after doors open is refused by every offline scanner (§14 #19) — the same
lockout shape as §13.5, and the reason DL-1 is HIGH.

- **Purpose:** append to the current open episode's **delta log** so a synced device's admissible set tracks
  changes made after the base snapshot. Two operations only:

  | `p_op` | Written by | Meaning | Why it is safe |
  |---|---|---|---|
  | `add` | `kernel.issue_ticket_atoms` (door sale · comp · import) | a newly minted atom becomes admissible | the atom is **new**: `credential_version = 0`, it has never been transferred, and it cannot be transferred (the session is frozen). Its reference value cannot go stale, so it **can strand nobody** — the Wallet spec's DL-1 argument, which I have checked and accept. **It carries the full entry payload** (§7.5a), because an `add` delta is the only carrier for an atom absent from the base snapshot |
  | `revoke` | `kernel.void_ticket_atom` on any exempt path (§7.6) | an atom ceases to be admissible | strictly narrows the admissible set; a device that misses it is no worse off than today, a device that receives it is strictly safer |

  **Both operations are monotone in safety:** `add` can only admit an atom that is provably current, `revoke`
  can only refuse. Neither can cause an offline door to admit something it should not — which is why the delta
  log needs no freeze of its own and no new lock.
- **Actor:** `service_role`/definer only. `REVOKE EXECUTE FROM anon, authenticated, public`. Never in an RLS
  EXEC row, never client-callable — same posture as `catalog.engage_door_freeze` (§7.4).
- **Preconditions:** an episode with `status='open'` exists for the session. **If none exists, the call is a
  silent no-op, not an error** — issuance and voiding must never fail because the door happens to be shut.
- **Locks & order:** the caller already holds `FOR SHARE` on the session row (rank 1) — `issue_ticket_atoms`
  acquires it as the promoted form of the "Event/Session read-gate at 1" that RPC §14.1 already models for
  SSCAS member #1, and `void_ticket_atom` acquires it per §5.1. The delta insert takes no further lock.
- **SSCAS:** `n/a` — writes one aggregate class (Event/Session child). Member #1 and member #3 keep their
  existing numbers; this adds a same-aggregate write under a lock they already hold. **No sixteenth member.**
- **Idempotency:** PK `(manifest_id, seq)` plus `UNIQUE(manifest_id, ticket_atom_id, op)` — a replayed mint or
  void appends nothing.
- **Writes:** `venue.door_manifest_delta` (INSERT N), `venue.door_manifest.max_delta_seq` (advance).
- **Emits:** `DoorManifestSupplemented` (§12.2 #43) so online devices re-sync promptly.
- **Result:** `{ status, manifest_id, delta_seq, applied }`.

**Device semantics.** A device's admissible set is `base_snapshot ⊕ deltas[1 .. last_synced_seq]`. It advertises
`last_synced_seq` on sync; `venue.get_door_manifest(p_session_id, p_since_delta_seq)` returns only the deltas
beyond it. **A device that has never synced deltas is exactly as safe as it was before this section existed** — it
simply refuses the new atoms (DL-1's fallback) and keeps the revoked ones (the pre-existing residual).

**The honest limit, stated rather than glossed.** A door sale requires taking payment, which requires network,
so the *selling* device is online by construction and can admit its own sale immediately. A **different**
scanner that is offline will refuse that ticket until it syncs. This is an operational limit, not a safety
property: post-open issuance is **admissible online immediately, and offline only after the admitting device
syncs**. It must be in the door runbook and in the dashboard copy for door-release inventory (§11.1).

---

## 8. Administrative override (req 6) — `NEW RPC` + `ADDITIVE SCHEMA CHANGE`

The boundary cannot move and cannot be cleared. The only admissible exceptional act is therefore to **suspend
the freeze's effect for a bounded interval without altering the boundary.**

### 8.1 `kernel.door_freeze_override` — `ADDITIVE SCHEMA CHANGE` (new table, append-only)

- **Purpose:** an audited, TTL-bounded, reason-coded suspension of the transfer freeze. `AO` (append-only);
  revocation is a forward state transition, never a delete.
- **Schema:** `kernel` (this is a custody-authority object, not a venue-operations object).
- **PK:** `override_id` uuid.
- **Columns:** `override_id` uuid PK; `session_id` uuid not null FK→`catalog.event_session` on delete restrict;
  `ticket_atom_id` uuid **nullable** FK→`kernel.tickets` on delete restrict (NULL = whole session; non-NULL =
  single atom — the narrower grant, preferred); `granted_by` uuid not null FK→`auth.users`; `reason_code` text
  not null; `granted_at` timestamptz not null default now(); `expires_at` timestamptz not null;
  `revoked_at` timestamptz nullable; `revoked_by` uuid nullable FK→`auth.users`;
  `command_idempotency_key` text not null; `created_at`.
- **Unique:** `UNIQUE(granted_by, command_idempotency_key)`.
- **Check:** `expires_at > granted_at`;
  `expires_at <= granted_at + config('door.max_override_interval')` (default `'2 hours'` — **never unbounded**,
  the C25/C43 bounded-lifetime discipline);
  `reason_code` ∈ `{operator_error_reopen, ticket_stranded_at_door, fraud_investigation,
  platform_incident_recovery}`.
- **Immutability:** `AO` for the grant; `revoked_at`/`revoked_by` are the single permitted forward transition,
  guarded by a trigger that rejects every other UPDATE and every DELETE.
- **Index:** PK; partial index on `(session_id) WHERE revoked_at IS NULL AND expires_at > now()` — the hot-path
  read inside `is_transfer_frozen`.
- **RLS:** `audit-only` (deny-all to clients; read only via an `is_platform` RPC).
- **Write authority:** `kernel.grant_door_freeze_override` / `kernel.revoke_door_freeze_override`.
- **SoT/PROJ:** SoT.

### 8.2 `kernel.grant_door_freeze_override(p_session_id, p_ticket_atom_id, p_reason_code, p_expires_at, p_command_key)` — `NEW RPC` — **DB-RPC**

- **Role:** `is_platform([platform_admin])` **only.** Not `org_owner`, not `venue_manager`, not
  `platform_risk`, not `platform_support`. An override defeats a safety property; it requires authority
  strictly above the authority that engaged the freeze (req 6 "elevated authority").
- **Preconditions (hard):**
  1. **No episode with `status='open'` exists for the session.** If a manifest is live, the admin must close it
     first. This is what preserves the Door Safety Theorem: **no custody move can ever commit while an offline
     manifest is armed**, override or not.
  2. `p_expires_at` within `config('door.max_override_interval')`.
  3. `p_reason_code` in the closed set.
- **Locks:** `catalog.event_session` **FOR UPDATE** (rank 1) — serializes against a concurrent
  `open_door_manifest`, so an override and an open can never interleave.
- **SSCAS:** `n/a (single-aggregate)`.
- **Writes:** `kernel.door_freeze_override` (INSERT), `kernel.admin_audit`
  (`session.door_freeze_override_grant`, with `before/after` and the reason).
- **Result:** `{ status, override_id, expires_at }`.
- **Errors:** `insufficient_privilege(42501)` · `precondition_failed` (`manifest_open` | `ttl_too_long` |
  `bad_reason_code` | `unacknowledged_live_devices`).
- **Explicitly does NOT write `catalog.event_session`.** `door_open_at` is untouched, so the historical
  boundary survives verbatim — req 6, req 9.

#### 8.2.1 Break-glass forces a manifest re-sync — Wallet **DL-3**, accepted and strengthened

DL-3 asks that after any override or platform force-void, every scanner for the session re-sync M2 before
resuming offline admission. **Accepted — but re-sync alone is necessary and not sufficient, and the request as
phrased implies a guarantee the mechanism cannot deliver.** A device that is offline cannot be made to
re-sync, and nothing the server writes afterwards reaches it. Setting `not_after := now()` server-side does not
shorten the `not_after` the device already downloaded. The sound form has four parts:

1. **Force-close and invalidate.** `grant_door_freeze_override` already requires that no episode be open
   (§8.2 precondition 1). Extend the same requirement to the platform force-void path when it targets a
   session whose freeze is engaged: force-close the open episode first, and set `not_after := now()` on every
   prior episode of that session.
2. **Push.** Emit `DoorManifestInvalidated` (§12.2 #44). Online devices drop their cached M2 immediately and
   render `awaiting_manifest` (§11.2) until a new episode is opened.
3. **Acknowledge, before the act.** `grant_door_freeze_override` **counts devices whose last synced manifest
   for this session is still within its downloaded `not_after`** and refuses with
   `precondition_failed('unacknowledged_live_devices')` unless the caller passes `p_ack_live_devices := <that
   exact count>`. This is a deliberate speed bump: the admin must look at the number before defeating a safety
   property. The dashboard shows the same count (§11.1).
4. **Bound honestly.** The residual after all of the above is a device that was offline across the break-glass
   act, bounded by the `not_after` it downloaded — i.e. by `door.manifest_ttl_interval`, nothing more. **Say
   this; do not describe the residual as closed by the re-sync requirement.** It is not.

**Amendment to the Wallet spec's §4.3 residual list (their responsibility, flagged here):** the list names the
override and platform force-void. It must also name the **C25 compensate branch** (§5.4) — a *routine,
unelevated, unaudited* sweep that voids an atom and therefore leaks a *revocation* offline. It is a
lower-severity residual than the two they name (revenue, not custody) but it is the only one that fires
without a human.

### 8.3 `kernel.revoke_door_freeze_override(p_override_id, p_command_key)` — `NEW RPC` — **DB-RPC**

- **Role:** `is_platform([platform_admin, platform_risk])` — risk may *revoke* (tighten) but not *grant*
  (loosen), preserving the domain's freezer-≠-releaser separation of duties (domain §7.2, §12).
- **Writes:** `kernel.door_freeze_override` (`revoked_at`, `revoked_by`), `kernel.admin_audit`.
- **Idempotency:** terminal-state.

### 8.4 Expiry

Overrides expire by `expires_at` with no sweep required — `is_transfer_frozen` reads
`expires_at > now()`. A sweep is nevertheless specified for **notification and audit closure only**
(`kernel.sweep_expired_door_overrides()`, `NEW RPC`, definer batch, emits `DoorFreezeOverrideExpired`). It must
never be load-bearing for correctness: correctness that depends on a cron running is the failure class this
whole document exists to prevent.

---

## 9. Offline manifests, Wallet passes, and scanning (req 8, req 14)

### 9.1 Two manifests, currently conflated — `SPEC CORRECTION`

The frozen spec set uses "manifest" for two different artifacts and never distinguishes them:

| | **M1 — key manifest** | **M2 — door (ticket) manifest** |
|---|---|---|
| Defined in | edge §5.4 | *nowhere* (referenced by schema §3.11 `scan_device.manifest_version`, §3.12 `scan.manifest_version`, VD §12.3, RN §10.2 "manifest ready + **count**") |
| Contents | `{key_id, scope, public_key, not_before, not_after, status}` | per-session admissible atoms + their pinned `credential_version` |
| Scope | per event / per venue | **per session, per episode** |
| Opened by | nothing (a projection, always available) | `venue.open_door_manifest` — **this is what `door_open_at` refers to** |
| Purpose | verify a token's *signature* | verify a token's *currency* |

`venue.door_manifest` / `venue.door_manifest_entry` (§10.1) give M2 a physical home. Until now it had a
`manifest_version` column on two tables and no table to version.

### 9.2 Offline verify — `SPEC CORRECTION` to edge §5.4

Edge §5.4 enumerates the offline door's checks: (1) `key_id` in the cached key manifest and in window;
(2) signature verifies against that public key; (3) `session_id` matches and `exp` within the ±2-bucket skew;
(4) first-in-wins locally. **There is no `credential_version` check.** An offline door as specified therefore
*cannot detect a stale credential at all* — which is why the transfer freeze had to exist, and why the freeze
never engaging is a safety failure rather than a nuisance.

Add step (3b), evaluated against the device's applied set `M2 = base_snapshot ⊕ deltas[1 .. last_synced_seq]`
(§7.7):

> **(3b)** the atom is present in `M2`; `M2[atom]` is not `revoke`d; the token's `credential_version` equals
> `M2[atom].credential_version`; `M2[atom].ticket_state = 'active'`; and `M2[atom].resale_state = 'none'`.

**Where this predicate now lives — `SPEC CORRECTION` (H-2).** These five conjuncts were correct here and
**two** of them were missing from edge §5.4.3, the section labelled BINDING and the text a scanner SDK
implements: the integration adopted the older Wallet §11.9 wording *after* this section had corrected it. For
the interval that stood, **the offline door was strictly more permissive than the online one** — exactly the
asymmetry the paragraph below says must not exist. The predicate is therefore now stated **once**, in
**edge §5.4.3**, tagged `OFFLINE-VERIFY-v1` and CI-gated for byte-identity across its mirrors. This section
keeps the derivation above and the reject map below (both door-owned and normative), and reproduces the
predicate as a sanctioned mirror:

<!-- SANCTIONED MIRROR of OFFLINE-VERIFY-v1. Byte-identical to PHASE_2_EDGE_FUNCTION_SPEC.md §5.4.3. CI-gated. -->

```text
OFFLINE-VERIFY-v1 — offline door admission predicate (NORMATIVE)
Single source: PHASE_2_EDGE_FUNCTION_SPEC.md §5.4.3. Mirrors must be byte-identical.

Applied set:  M2 := base_snapshot(manifest_id) ⊕ deltas[1 .. last_synced_seq]   (door §7.7)
              The device MUST evaluate against the APPLIED set. Evaluating the base
              snapshot alone silently ignores every revocation and every supplement
              the device has already downloaded.

ADMIT(token) requires ALL of:

  1    token.key_id ∈ M1  ∧  M1[token.key_id].status ≠ 'revoked'
                         ∧  now() ∈ [M1[token.key_id].not_before, not_after]
  2    Verify(M1[token.key_id].public_key, token.claims, token.sig)
  3    token.session_id == the device's bound scanning session
  3a   now() <= token.exp, ± 2 time-buckets                                     (RPC §9.3)
  3b   FIVE conjuncts, ALL required — this is the W-3 fix:
         i    atom ∈ M2
         ii   M2[atom] carries no applied `revoke` delta
         iii  token.credential_version == M2[atom].credential_version
         iv   M2[atom].ticket_state  == 'active'
         v    M2[atom].resale_state  == 'none'
  3c   token.key_id == M2[atom].signing_key_id                                  (Wallet §8.3)
  4    first-in-wins against the device's local admitted set

  No M2, an M2 past its downloaded not_after, or an M2 for another session
  ⇒ the door has NO offline authority and MUST NOT admit.                       (door §3.1)

Conjunct 3b.v is load-bearing, not defence in depth: a `paid_pending_transfer` atom is
`state='active', resale_state='locked'` and is excluded from the door-open drain, and a
`refund_hold` atom is `state='active'` too. Without 3b.v the offline door admits both —
atoms the ONLINE door refuses. Online and offline must reject for the same reasons, or the
offline door is not a shrunk version of the online one; it is a different one.

Reject reasons: door §9.2's map. No private key, no network, no DB.
```

With §5.3's theorem this is not merely a defence-in-depth check — it is *exact* for the custody dimension: the
manifest owner and version are provably current for the whole episode, so `version_stale` offline means the
same thing it means online. §5.4 states precisely where it is not exact (revocation).

**Reject-reason mapping — `SPEC CORRECTION`, and a counter-proposal to Wallet DL-5.** DL-5 observes, correctly,
that a **voided** atom rejected as `wrong_session` misdirects door staff into re-checking the night instead of
telling the holder their ticket was refunded, and proposes a new reason `not_admissible`. **The problem is
real; the proposed fix treats the symptom.** `wrong_session` is misleading only because the base snapshot was
specified to *exclude* terminal atoms (§10.3, `ticket_state ∈ {issued, active}`), so "absent from M2" was
overloaded with two unrelated meanings.

**Ruling: make M2 complete instead.** The snapshot carries **every atom of the session regardless of state**,
with `ticket_state` and `resale_state` recorded. "Absent from M2" then means exactly one thing — this atom does
not belong to this session — and `wrong_session` becomes accurate rather than misleading. No new vocabulary is
introduced, and every reason maps onto the five the venue dashboard already publishes (VD §12.5):

| `M2` state | Offline reject reason | Operator copy (VD §12.5, unchanged) |
|---|---|---|
| absent from M2 | `wrong_session` | *"Right event, wrong night."* — now literally true |
| `revoke`d by delta, or `ticket_state='voided'` | `voided` | *"This ticket was refunded or cancelled."* |
| `ticket_state='scanned'` at snapshot | `duplicate` | *"Already used"* |
| `resale_state ∈ {listed, locked}` | `listed_locked` | *"This ticket is listed for resale or mid-transfer."* |
| **`resale_state = 'refund_hold'`** | **`refund_hold`** | ***"A refund is being reviewed on this ticket, so it can't be used yet. If they don't want the refund, it has to be cancelled in the Snatch It app — then this ticket works again."*** |
| **`resale_state = 'dispute_hold'`** (`R-40`) | **`dispute_hold`** | ***"A payment dispute is open on this ticket, so it can't be used yet."*** *(the `refund_hold` arm's copy shape, mirrored; the overlay is set/released by RPC §20.7.13/§20.7.15. **Accepted residual, red-team B-F4: a dispute landing MID-EPISODE writes no manifest delta, so the offline door admits until the episode closes — the online recheck and the payout hold are the controls; a `revoke` delta would be irreversible for the episode and render the wrong copy.**)* |
| version mismatch | `version_stale` | *"This pass is out of date. Ask them to open the Snatch It app."* |
| `key_id` ≠ `M2[atom].signing_key_id` (3c) | `version_stale` | *"This pass is out of date. Ask them to open the Snatch It app."* — reuses the copy deliberately; from the holder's side it is the same situation |

**The `refund_hold` arm — `SPEC CORRECTION`, and the one place this ruling adds vocabulary.** The map above
originally enumerated only `{listed, locked}`. MONEY §12 ADDITIVE-2 added a **fourth** overlay label,
`refund_hold` (schema §1.5), and §10.3's CHECK already admits all five since `R-40` added `dispute_hold` (`088`'s CHECK amendment) — so under the five-conjunct predicate a
`refund_hold` atom is correctly **rejected**, but it was rejected with **no reason arm at all**. Door staff saw
an unmapped refusal of a paying customer and had nothing to say and nothing to offer.

**Why a sixth reason rather than reuse.** §9.2's ruling on DL-5 refused new vocabulary because the existing
five already carried every *meaning* — that argument does not hold here. Folding `refund_hold` into
`listed_locked` tells the holder their ticket is *"listed for resale or mid-transfer"*, which is false, and
sends door staff hunting a listing that does not exist. **The remedy is what makes the reason worth having:**
the holder (or org finance, or platform) can cancel the parked request — `kernel.cancel_refund_request`
(RPC §17.3) releases the overlay to `none` and the ticket admits — and if nobody acts,
`kernel.sweep_expired_refund_requests` (RPC §17.4) releases it at `expires_at`. A reason with a remedy behind
it is worth a word; a reason without one is not, which is why the other four were reused.

**Two sibling-owned changes this arm requires — reported, not made here:**
- **`PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` §12.5** — the *"five reasons"* table becomes **six**, with the
  row and copy above. The surrounding prose that says "five" changes with it.
- **`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §9.3** — `venue.validate_ticket_online`'s `reason` enum
  (`active|already_scanned|listed_locked|voided|wrong_session|version_stale`) gains **`refund_hold`**. Without
  it the **online** door has the same unmapped-refusal problem the offline door had: `mark_ticket_scanned`
  requires `resale_state='none'`, so a `refund_hold` atom is refused online today with no reason to render.

**This also closes a hole neither spec flagged.** A sale in `paid_pending_transfer` leaves its atom
`state='active', resale_state='locked'` (RPC §12.3), and §7.3 deliberately excludes it from the drain to
protect the money. Under the original §10.3 it would have entered M2 as a plain `active` atom with no
`resale_state`, so the **offline** door would have admitted an atom the **online** door refuses with
`listed_locked` (RPC §7.5). Recording `resale_state` makes the two doors agree. Online and offline must reject
for the same reasons or the offline door is not a shrunk version of the online one — it is a different one.

### 9.3 The full relationship (req 8)

| Concept | Role | Written by | Relationship |
|---|---|---|---|
| `doors_at` | **informational** — the marketing/ops time doors are announced for; also the **implicit freeze backstop input** | `catalog.create_event_session` / `update` (existing) | never the freeze boundary itself; only an input to `LEAST` |
| `door_open_at` | **the canonical freeze boundary**; cached monotone head of the episode ledger | `catalog.engage_door_freeze` **only** (§7.4) | `= MIN(door_manifest.opened_at)`; set once, never moved, never cleared |
| manifest generation / opening | produces the offline artifact **and** engages the freeze, atomically | `venue.open_door_manifest` | one transaction; §6 |
| transfer freeze | `is_transfer_frozen(atom)` | derived; no storage | `now() >= effective_freeze_at ∧ no active override` |
| refund-void freeze (C23) | routine refund path frozen; cancel/platform paths exempt | see §7.6 table | prevents a post-snapshot void stranding at an offline door |
| scanning | **never gated by the manifest or the freeze**; gated by `session.status='live'` + atom state | `venue.record_scan` → `kernel.mark_ticket_scanned` | §3.1, §13.1 |
| offline manifests | armed only while an episode is `open` and `not_after > now()` | `venue.get_door_manifest` (read) | manifest ⟺ episode; no episode ⇒ no offline authority |
| Wallet pass invalidation | `credential_version` bump kills the cached token | `transfer_ticket_ownership` / `void_ticket_atom` (existing) | the freeze guarantees **no bump can occur while an episode is open**, so the cached pass is provably current |

### 9.4 Wallet-pass stale-read, end to end

Today's cached-token contract (edge §5.5) is: token = `{atom_id, session_id, credential_version, key_id,
issued_at, exp}`, cacheable, TTL-bounded, invalidated by a version bump. The hazard it names is that an
**offline** door "admits on signature+window" and the mismatch is only caught at reconcile. §9.2 closes that
online-offline asymmetry, and §5.3's theorem is what makes closing it possible: a manifest that could go stale
would only move the problem.

Concretely, the four Wallet-pass scenarios:

| Scenario | Before this spec | After |
|---|---|---|
| A transfers to B **before** doors open; A shows a cached pass at an offline door | admitted (signature valid, version unchecked); caught at reconcile → fraud queue, B already admitted or denied | **rejected** — M2 has B's version; A's token has the old one |
| A tries to transfer to B **after** doors open | permitted — the freeze never engaged | **rejected `frozen`** |
| A's ticket refunded after doors open; A shows the cached pass offline | admitted; venue eats an admission | **rejected** — routine refund-void is frozen (C23, §7.6); a platform break-glass void is the audited residual |
| A's pass cached, no transfer, offline door | admitted (correct) | admitted (correct) — the common case is unchanged |

**Apple Wallet is now specified** — `docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md` (Wallet **DL-6**,
accepted). The paragraph that stood here said PassKit was "not built in Phase 2" and set the constraint that a
`.pkpass` must never carry a longer TTL than the token; both statements are superseded. The Wallet spec's §4
four-scenario proof consumes this document's M2 and step 3b; §5.4 above confirms exactly which part of the
theorem it may lean on and which part it may not, and §16 OQ-5 now carries the **ruling** on the token profile
rather than the open question.

---

## 10. Schema delta (additive only)

### 10.1 `venue.door_manifest` — `ADDITIVE SCHEMA CHANGE` (new table, AO-with-one-forward-transition)

- **Purpose:** the append-only ledger of door-manifest **episodes** per session. The source of truth behind
  `catalog.event_session.door_open_at`.
- **PK:** `manifest_id` uuid.
- **Columns:** `manifest_id` uuid PK; `session_id` uuid not null FK→`catalog.event_session(session_id)` on
  delete restrict; `venue_id` uuid not null FK→`catalog.venue(venue_id)` on delete restrict (denormalized for
  the authz hot path, kept consistent by the RPC — the same pattern as `catalog.event.org_id`);
  `manifest_version` integer not null (per-session monotonic, starts at 1);
  `status` enum(`open` · `closed`) not null default `open`;
  `opened_at` timestamptz not null default now(); `opened_by` uuid not null FK→`auth.users(id)`;
  `open_reason_code` text not null;
  `not_after` timestamptz not null (offline validity horizon);
  `closed_at` timestamptz nullable; `closed_by` uuid nullable FK→`auth.users(id)`; `close_reason` text nullable;
  `entry_count` integer not null; `manifest_digest` text not null;
  `max_delta_seq` integer not null default 0 (§10.3a — advanced by `append_door_manifest_delta`);
  `command_idempotency_key` text not null; `created_at`.
- **Unique:** `UNIQUE(session_id, manifest_version)`;
  `UNIQUE(session_id, command_idempotency_key)`;
  **partial `UNIQUE(session_id) WHERE status = 'open'`** — *at most one open episode per session, enforced by
  the database, not by the RPC.* This is the structural half of §5.2's idempotency.
- **Check:** `opened_at <= now()` (§6.2); `not_after > opened_at`;
  `closed_at IS NULL OR closed_at >= opened_at`;
  `(status='closed') = (closed_at IS NOT NULL)`; `entry_count >= 0`; enum coherence.
- **Immutability:** `AO` on insert; the **only** permitted UPDATE is the single forward transition
  `open → closed` writing `closed_at`/`closed_by`/`close_reason`. A guard trigger rejects every other UPDATE
  and every DELETE (schema §0.8 AO pattern).
- **Index:** PK; the partial unique doubles as the open-episode lookup; index on `(session_id, opened_at)`;
  index on `(venue_id, status)` (the dashboard's "which doors are open right now" tile).
- **Archival:** permanent (it is the evidence behind every freeze-boundary dispute); time-partitionable by
  session like `venue.scan`.
- **RLS:** venue-scoped read (`venue_manager`, `venue_scanner` own session, org owner/admin, platform);
  writes RPC-only.
- **Write authority:** `venue.open_door_manifest`, `venue.close_door_manifest`.
- **SoT/PROJ:** **SoT.** `catalog.event_session.door_open_at` is its projection head.

### 10.2 `catalog.event_session.door_open_at` — `NO SCHEMA CHANGE` + `ADDITIVE SCHEMA CHANGE` (constraints only)

The column keeps its name, type (`timestamptz`), and nullability (nullable — it is legitimately NULL for every
session whose doors have never opened). What is added is **enforcement**:

```sql
-- illustrative shapes only — no migration is authored here

-- (a) the column is a projection of the ledger, not an independent fact
CREATE OR REPLACE FUNCTION catalog.tg_door_open_at_is_ledger_head() RETURNS trigger AS $$
BEGIN
  IF NEW.door_open_at IS DISTINCT FROM OLD.door_open_at THEN
    -- never clear
    IF NEW.door_open_at IS NULL THEN
      RAISE EXCEPTION 'door_open_at may not be cleared (session %)', OLD.session_id
        USING ERRCODE = 'check_violation';
    END IF;
    -- never move once set
    IF OLD.door_open_at IS NOT NULL THEN
      RAISE EXCEPTION 'door_open_at is immutable once engaged (session %)', OLD.session_id
        USING ERRCODE = 'check_violation';
    END IF;
    -- may only ever equal the first episode's opened_at
    IF NEW.door_open_at IS DISTINCT FROM (
         SELECT min(opened_at) FROM venue.door_manifest WHERE session_id = NEW.session_id)
    THEN
      RAISE EXCEPTION 'door_open_at must equal MIN(door_manifest.opened_at) (session %)', NEW.session_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

-- (b) never in the future
ALTER TABLE catalog.event_session
  ADD CONSTRAINT event_session_door_open_at_not_future CHECK (door_open_at IS NULL OR door_open_at <= now());
--     NB: now() in a CHECK is not IMMUTABLE; if the implementer rejects it, the equivalent guard moves
--     into trigger (a) — an implementation choice, not an architectural one.
```

**Why the trigger and not just "the RPC is careful":** because "the RPC is careful" is exactly what was true of
`door_open_at` until this document — the specs said it was canonical, and nothing wrote it. The trigger is the
mechanism that makes a *future* RPC bug loud instead of silent. It is defense-in-depth against the failure mode
this whole ruling exists to prevent.

**Note on `starts_at` edits.** RLS §8.3 note 19 already flags that changing `starts_at` on an on-sale session is
a confirmed, money-adjacent operation *because it affects door-freeze*. Under §3 it now also moves the
**implicit** boundary. `SPEC CORRECTION`: `catalog.create_event_session`'s update path must reject a
`starts_at`/`doors_at` edit once `door_open_at IS NOT NULL` — the boundary is engaged and its inputs are
frozen with it.

### 10.3 `venue.door_manifest_entry` — `ADDITIVE SCHEMA CHANGE` (new table, AO)

- **Purpose:** the per-atom snapshot that makes the offline door able to detect a stale credential (§9.2), the
  evidence for reconciliation, and the future home of the C43 per-open-manifest-ticket narrowing.
- **PK:** composite `(manifest_id, ticket_atom_id)`.
- **Columns:** `manifest_id` uuid FK→`venue.door_manifest` on delete restrict; `ticket_atom_id` uuid
  FK→`kernel.tickets` on delete restrict; `serial_no` integer not null;
  **`ticket_type_id` uuid not null FK→`venue.ticket_type` on delete restrict** (`ADDITIVE`, `MP-1`);
  `credential_version` integer not null;
  `signing_key_id` uuid not null FK→`kernel.signing_key` on delete restrict;
  `ticket_state` text not null (the atom's `state` at snapshot);
  **`resale_state` text not null** (the atom's `resale_state` at snapshot — §9.2); `created_at`.
- **`ticket_type_id` — `ADDITIVE SCHEMA CHANGE` (`MP-1`).** RPC §20.6.1 contracted this column **in the entry
  projection of `get_door_manifest`** while this table did not carry it, so the read projected a value with no
  source and the `manifest_digest` — a hash over the ordered entry set — covered a column that did not exist.
  Added here rather than deleted there: the scanner shows the tier on the admit banner (RN §7.3), and it is a
  **catalog reference, not an identity column**, so §7.5's no-bulk-attendee-list rule, pgTAP 6 and
  `T-RPC-DOOR-17` are unaffected — all three assert over identity-bearing columns, and this is not one.
  *Alternative considered and rejected:* drop `ticket_type_id` from RPC §20.6.1's projection. Rejected because
  it removes a genuinely useful non-identity field to resolve a contradiction that an additive column resolves
  without loss, and because the digest would then cover strictly less than the door reads.
- **Check:** `credential_version >= 0`; `ticket_state` ∈ the atom state enum; `resale_state` ∈ the overlay enum.
  **The snapshot is COMPLETE — every atom of the session, in every state** (§9.2 ruling on DL-5). The earlier
  restriction `ticket_state ∈ {issued, active}` is **withdrawn**: it overloaded "absent from M2" with two
  meanings and made `wrong_session` misleading for voided tickets.
- **Immutability:** `AO`. Guard trigger rejects UPDATE and DELETE. A re-open produces a **new** `manifest_id`
  and a fresh entry set; entries are never edited.
- **Index:** PK; index on `ticket_atom_id` (the Gate-M narrowing lookup and the reconciliation join).
- **Volume:** one row per admissible atom per episode. Miami-scale: a 500-capacity room re-opened twice = 1,500
  rows per night. Negligible.
- **RLS:** venue-scoped read (door principal for its own session). **No owner identity, no PII** (§7.5).
- **Write authority:** `venue.open_door_manifest` only.
- **SoT/PROJ:** SoT (an immutable snapshot; not rebuildable after the fact, deliberately — that is the point).

> **Lighter alternative, considered and rejected:** store only `manifest_digest` on the episode and generate
> entries on the fly at fetch. Rejected because (a) the digest could not then be reproduced after a later
> transfer, destroying the reconciliation evidence, and (b) the C43 narrowing would have no membership to read.
> Recorded so the decision is not re-litigated.

### 10.3a `venue.door_manifest_delta` — `ADDITIVE SCHEMA CHANGE` (new table, AO)

The append-only change log applied on top of the base snapshot (§7.7). Serves Wallet **DL-1** (`add`) and
§5.4's revocation residual (`revoke`) with one mechanism.

- **PK:** composite `(manifest_id, seq)`.
- **Columns:** `manifest_id` uuid FK→`venue.door_manifest` on delete restrict; `seq` integer not null
  (per-manifest monotonic, starts at 1); `ticket_atom_id` uuid not null FK→`kernel.tickets` on delete restrict;
  `op` enum(`add` · `revoke`) not null; `serial_no` integer nullable; **`ticket_type_id` uuid nullable
  FK→`venue.ticket_type` on delete restrict** (`ADDITIVE`, `MP-1`); `credential_version` integer nullable
  (required for `add`, null for `revoke`); `signing_key_id` uuid nullable FK→`kernel.signing_key`;
  **`ticket_state` text nullable** (`ADDITIVE`, `MP-1`); **`resale_state` text nullable** (`ADDITIVE`, `MP-1`);
  `cause_ref` uuid nullable (the issuing order / refund driving the change); `occurred_at` timestamptz not null
  default now(); `created_at`.
- **Unique:** PK; **`UNIQUE(manifest_id, ticket_atom_id, op)`** — a replayed mint or void appends nothing
  (§7.7 idempotency).
- **Check:** `(op='add') = (credential_version IS NOT NULL)`; `credential_version >= 0`;
  **`(op='add') ⇒ signing_key_id IS NOT NULL`** (`ADDITIVE`, tightened) — offline check 3c is now **required**
  (edge §5.4.3), so a supplemented atom with no pinned key would be structurally unadmittable offline. A
  nullable `signing_key_id` on an `add` delta is a lockout waiting to happen, not a permissive default.
  **`op='add'` requires `credential_version = 0`** — a supplemented atom is by construction newly minted and
  never transferred; anything else would mean a custody move committed after the freeze, which §5.3's theorem
  forbids. This CHECK is the theorem made structural.
- **The `add` row carries the full entry payload — `ADDITIVE SCHEMA CHANGE` (`MP-1`), five CHECKs.** §7.5a
  requires every field `OFFLINE-VERIFY-v1` reads to be evaluable from an `add` delta alone, because an `add`
  delta is the **only** carrier for an atom that is not in the base snapshot. The existing CHECK set already
  encoded that asymmetry for `credential_version` and `signing_key_id`; it is completed here in the same
  shape rather than restated as prose:

  | CHECK | Why this value and not a nullable default |
  |---|---|
  | `(op='add') = (ticket_state IS NOT NULL)` | conjunct 3b.iv has no input otherwise |
  | **`(op='add') ⇒ ticket_state = 'active'`** | `kernel.issue_ticket_atoms` writes `state='issued'→'active'` in one transaction (RPC §7.1), so an `add` delta for an atom in any other state means issuance changed under the freeze — which must **fail loudly here**, not mint a row the door silently refuses or silently admits |
  | `(op='add') = (resale_state IS NOT NULL)` | conjunct 3b.v has no input otherwise |
  | **`(op='add') ⇒ resale_state = 'none'`** | a newly minted atom cannot be listed or locked: the session is frozen, so `create_listing`/`create_p2p_transfer`/`lock_ticket` all recheck and refuse (§7.6). Same theorem, same structural form as `credential_version = 0` |
  | `(op='add') = (serial_no IS NOT NULL)` · `(op='add') = (ticket_type_id IS NOT NULL)` | not predicate inputs — operator-facing, and required on `add` so the delta row is **exactly** the entry projection, which is what makes §7.5a checkable by column-list comparison instead of by reading |

  **On `revoke` all six stay NULL by the same CHECKs.** A `revoke` delta removes an atom from the admissible
  set and the device evaluates nothing against it beyond conjunct 3b.ii; carrying a version, a key or a state
  on it would be ceremony a writer eventually fills with a placeholder, and a placeholder in a field the door
  reads is worse than a NULL in a field it does not.

  *Why pin the values rather than snapshot whatever the atom holds:* both are correct at insert time and only
  the pinned form stays correct. A snapshot column records what was true; a CHECK records what must be true,
  and it is the second that catches a future issuance path minting something the offline door cannot classify.
- **Immutability:** `AO`. Guard trigger rejects UPDATE and DELETE.
- **Index:** PK (doubles as the `seq > p_since_delta_seq` sync scan); index on `ticket_atom_id`.
- **Volume:** door-release inventory plus late comps — tens of rows per session, not hundreds.
- **RLS:** venue-scoped read, identical posture to `venue.door_manifest_entry` (§10A.2). No identity column.
- **Write authority:** `venue.append_door_manifest_delta` only (definer-only, §7.7).
- **SoT/PROJ:** SoT.

### 10.4 `kernel.door_freeze_override` — `ADDITIVE SCHEMA CHANGE`

Specified in §8.1.

### 10.5 `venue.scan.manifest_id`, `venue.scan_device.manifest_id` — `ADDITIVE SCHEMA CHANGE` (recommended)

Both tables carry a `manifest_version` integer nullable (schema §3.11, §3.12) that today references nothing.
Add `manifest_id` uuid nullable FK→`venue.door_manifest(manifest_id)` on delete restrict, keeping
`manifest_version` for device-reported/diagnostic use. This turns "which manifest window admitted" (schema
§3.12, C23 reconciliation) from a number into a join, and lets `reconcile_offline_scans` verify that a device's
claimed manifest actually existed and covered the atom.

### 10.6 Config seeds — `ADDITIVE SCHEMA CHANGE` (rows only, AO-per-version)

| `catalog.platform_config` key | Type | Default | Meaning |
|---|---|---|---|
| `door.implicit_freeze_offset_interval` | interval | `'0 minutes'` | offset applied to `COALESCE(doors_at, starts_at)` for the implicit boundary |
| `door.manifest_ttl_interval` | interval | `'12 hours'` | episode `not_after` horizon |
| `door.manifest_early_open_window` | interval | `'12 hours'` | how far before doors an episode may be opened |
| `door.max_override_interval` | interval | `'2 hours'` | hard ceiling on an override's TTL |
| **`door.session_ttl_interval`** | interval | `'12 hours'` | door-session token lifetime, extended by `/refresh` (edge §3.9a). One door shift |
| **`door.session_absolute_max_interval`** | interval | `'24 hours'` | hard cap from `issued_at`; past it the device re-enters a PIN. A refresh loop may not turn a shift credential into a permanent one |
| **`door.session_post_session_grace`** | interval | `'4 hours'` | a token may not outlive the session it is bound to by more than this — covers late reconciliation of an offline batch without leaving a live credential for a finished show |

The three `door.session_*` keys are the H-3 fix's operational surface (edge §3.9a). They bound a **bearer
credential**, so they are tightening-only in the same sense as the money namespaces: **lowering any of them may
execute directly; raising one requires the second approver** (RLS §11's direction asymmetry). A security
control that is hard to tighten in an incident is a liability; one that is easy to loosen quietly is worse.

**Cross-config invariant (`SPEC CORRECTION`, load-bearing for §16 OQ-5).**

```
config('credential.wallet_default_span') + config('credential.wallet_exp_skew')
        <=  config('door.manifest_ttl_interval')
```

A Wallet token may never outlive the offline window that any manifest could authorise. `catalog.set_platform_config`
must validate this whenever either side changes and reject the write otherwise; CI asserts it over the seeded
values.

> **`SPEC CORRECTION` — this invariant constrains the wrong thing on its own.** `wallet_default_span` applies
> **only when `session.ends_at IS NULL`**. On every session that *has* an `ends_at`, the invariant above binds
> nothing, and a long or mistyped `ends_at` produces an **unbounded `exp`** — so the OQ-5 item 1 guarantee
> (*"cannot outlive the offline window any manifest could authorise"*) did not hold on the common branch.
> **The binding control is a clamp on the computed value**, specified in Wallet **§5.2a**:
> `exp := LEAST( session_ref_end + wallet_exp_skew, session_ref_start + door.manifest_ttl_interval +
> wallet_exp_skew, signing_key.not_after )`, applied by `credential-sign` at sign time and asserted in CI over
> the **computed** value with adversarial `ends_at` fixtures. The constants invariant above **stays as an early
> warning on the operator and is explicitly necessary-but-not-sufficient.** OQ-5 item 1 is discharged by the
> clamp, not by this line.

### 10.7 What is **not** added

- No `freeze_engaged_at` column (§2).
- No `kernel.tickets.transfer_frozen` column — A2/A3 remain closed.
- No change to `kernel.tickets`, `kernel.ticket_ownership_log`, `market.*`, or any `public.*` object.
- No new SSCAS member (§5.2).
- No new role label (§4.1).

---

## 10A. RLS delta

Everything below inherits RLS §1.3's two global postures: **GP-1** (no client principal holds direct
INSERT/UPDATE/DELETE on any Phase-2 table — every write is `R`, RPC-only) and **GP-2** (DELETE is `D` for every
role on every table). Cell vocabulary is RLS §1.2: `A` allow · `D` deny · `R` RPC-only · `V` scoped-read-only.

### 10A.1 `venue.door_manifest` — venue-scoped (NEW MATRIX)

Class: **venue-scoped** (schema §0.7). Write RPCs *(restates the canonical registry — `OR-7`)*: `venue.open_door_manifest`, `venue.close_door_manifest`, `venue.append_door_manifest_delta` (§17.13 — the head-version bump on every delta append).

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | **D** | D | D | D | — |
| org_member | D | D | D | D | — |
| org_owner / org_admin | A (own-org venues) | R | R | D | `open_door_manifest` · `close_door_manifest` |
| org_finance | A (own-org, status only)ᴬ | D | D | D | — |
| venue_manager | A (own-venue) | R | R | D | `open_door_manifest` · `close_door_manifest` |
| **venue_scanner** | **A (own session only)ᴮ** | **D** | **D** | D | **—** (O-4) |
| venue_finance / venue_box_office / venue_marketing / venue_promoter_manager | D | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | A (all) | D | D | D | — |
| platform_admin | A (all) | R | R | D | override |
| service_role | A (machine) | R (def) | R (def) | D | definer |

ᴬ finance sees only `status`/`opened_at`/`closed_at` (settlement timing context), never `manifest_digest`.
ᴮ the door principal reads only the episode for the session its `venue_scanner` grant — **or its token-bound
door session (`kernel.assert_door_session`, `AUTHZ-H3`), never a bare `door_pin`** — covers (RLS §11.4,
VD §5 note 3), and only via `venue.get_door_manifest`, not by table scan.

**A fan cannot read this table at all.** The freeze reaches the client exclusively as the
`kernel.is_transfer_frozen` boolean (RLS §14.3, unchanged). Exposing episode timings to fans would leak venue
operations and invite gaming the boundary.

### 10A.2 `venue.door_manifest_entry` — venue-scoped, AO (NEW MATRIX)

Class: **venue-scoped**, append-only. Write RPC: `venue.open_door_manifest` only.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| anon / fan / owner | D | D | D | D | — |
| org_owner / org_admin / venue_manager | A (own-venue) | R | D | D | — |
| **venue_scanner** · door session | **V** (own session, via `venue.get_door_manifest` only) | D | D | D | — |
| all other venue/org roles | D | D | D | D | — |
| platform_risk / platform_admin | A | R (def) | D | D | — |
| service_role | A (machine) | R (def) | D | D | definer |

**Column discipline (I-4).** The table carries **no identity column by construction** — no
`current_owner_id`, no buyer reference, no name. The door's bulk read is `(ticket_atom_id, serial_no,
ticket_type_id, credential_version, signing_key_id, ticket_state, resale_state)` and nothing else
(§7.5, `SPEC CORRECTION` `MP-1` — `resale_state` was the input to conjunct 3b.v and was omitted here, and
`ticket_type_id` is the catalog reference RPC §20.6.1 already projected). This is what keeps the hard rule
*"door staff never receive a bulk attendee list"* (domain §7.2, VD §5 note 11) true even though the door now
legitimately holds a bulk read: **the list grew by two non-identity columns and the identity-bearing set is
still empty**, which is the property pgTAP 6 / 83 and `T-RPC-DOOR-17` assert — not the list's length. Manual
single-record lookup stays on `venue.validate_ticket_online` (RPC §9.3, VD §12.6).

### 10A.3 `kernel.door_freeze_override` — audit-only (NEW MATRIX)

Class: **audit-only** (RLS §4): RLS **on, zero policies**, `REVOKE ALL FROM anon, authenticated`.
Read only through an `is_platform` RPC. Write RPCs: `kernel.grant_door_freeze_override`,
`kernel.revoke_door_freeze_override`.

| Role | SEL | INS | UPD | DEL | EXEC |
|---|---|---|---|---|---|
| every role except platform + service_role | **D** | D | D | D | — |
| platform_support | V | D | D | D | — |
| platform_risk | V | D | R | D | `revoke_door_freeze_override` **only** (may tighten, never loosen — SoD) |
| platform_admin | V | R | R | D | `grant_…` · `revoke_…` |
| service_role | A (machine) | R (def) | R (def) | D | definer |

The freezer-≠-releaser separation (domain §7.2, §12) is realised here as **grant is `platform_admin`-only;
revoke is `platform_admin` or `platform_risk`.** The role that can loosen a safety property is strictly
narrower than the role that can restore it.

### 10A.4 `catalog.event_session` — **matrix unchanged, write authority narrowed** (`SPEC CORRECTION`)

RLS §8.3 keeps its cells exactly as written. Two clarifications are added to it:

- Note 19 (*"`starts_at` change on an on-sale session is a confirmed op — money-adjacent, affects door-freeze"*)
  is **strengthened**: once `door_open_at IS NOT NULL`, a `starts_at`/`doors_at` edit is **rejected**
  (§10.2), because those columns are inputs to the engaged boundary.
- New note 19b: **`door_open_at` is not writable by any RPC in the §11 EXEC table.** Its sole writer is
  `catalog.engage_door_freeze` (§7.4), which is definer-only and appears in **no** EXEC row. A trigger enforces
  this independently of grants (§10.2). `venue_manager` and `org_owner/admin` retain `R` on the row's other
  columns via `create_event_session`; that grant now cannot reach `door_open_at`.

### 10A.5 `venue.scan` · `venue.scan_device` — `manifest_id` column (`ADDITIVE`)

No matrix change. The new `manifest_id` column inherits each table's existing cells: `venue.scan` is
venue-scoped AO (RLS §9.12); `venue.scan_device` is venue-scoped with the door updating only its own device's
sync columns (RLS §9.11 note 33) — `manifest_id` joins `last_sync_at`/`manifest_version` in that narrow
device-writable set.

### 10A.6 `catalog.platform_config` — four new keys (`ADDITIVE`, rows only)

No matrix change. The four `door.*` keys (§10.6) are public-read like every other config value and writable
only by `catalog.set_platform_config` (`is_platform([platform_admin])`, dual-control, AO-per-version,
RLS §8.4). They are **operational thresholds, not secrets** — a fan learning that the implicit freeze offset is
zero learns nothing they could not infer from the event page.

### 10A.7 EXECUTE-authority additions to RLS §11

> **CORRECTED 2026-08-28 (reviewer condition 4 · `DL-X3`).** This table is titled *"additions to RLS §11"* and
> **disagreed with RLS §11.4, the thing it claims to extend**, on both rows below. It named the abolished label
> `venue_door` and kept **a bare `door_pin` as a first-class OR-arm of the predicate** — the
> provisioning-not-possession form closed by `AUTHZ-H3`. The prose that followed conceded the arm should not be
> reachable on a PIN alone, which made the row **self-contradicting rather than merely stale**: an implementer
> building from the predicate would have written the PIN arm, and the caveat sat *after* the code-shaped part.
> A caveat is not a predicate. **Rule `EXEC-DERIVED` (RLS §11.0) governs: where this file and the RLS spec
> disagree, the RLS spec is the authority and this table is the defect.** The corrected rows below are copied
> from RLS §11.4 rather than re-derived. `T-RLS-EXEC-02` would have caught the label — but it is scoped to
> predicates *in RLS §11* and cannot see this file (§20).

| RPC | May invoke (predicate, live-rechecked) |
|---|---|
| `venue.open_door_manifest` · `venue.close_door_manifest` | `has_venue_role(venue,[venue_manager])` OR `has_org_role_over_venue(venue,[org_owner, org_admin])` OR `is_platform([platform_admin])`. **`venue_scanner`, the door session, `venue_box_office`, every finance / marketing / promoter-manager role, `platform_support` and `platform_risk` explicitly excluded (O-4).** Opening the manifest freezes custody for the whole session — a scanner may not create the security boundary it works inside |
| `venue.get_door_manifest` | `has_venue_role(venue,[venue_scanner, venue_manager])` OR the `service_role` edge path with `kernel.assert_door_session` **asserted with a token** and bound to that session (`AUTHZ-H3`). **There is no `door_pin` arm.** A `door_pin` is a *provisioning* fact on a table with no device column — it evidences that a PIN was issued for a venue, never that *this device* holds it. The only door path is `door-session` `/manifest/sync` behind the token-bound assertion (edge §9 item 17, §16 OQ-7) |
| `catalog.engage_door_freeze` | **`service_role`/definer only** — `REVOKE EXECUTE FROM anon, authenticated, public`; never granted to `authenticated`; never a UI path |
| `catalog.effective_freeze_at` · `kernel.is_transfer_frozen` | `authenticated` (STABLE reads; `is_transfer_frozen` is already the RN eligibility boolean, RLS §14.3) |
| `kernel.grant_door_freeze_override` | `is_platform([platform_admin])` **only** |
| `kernel.revoke_door_freeze_override` | `is_platform([platform_admin, platform_risk])` |
| `kernel.sweep_expired_door_overrides` · `catalog.sweep_implicit_door_freezes` | `service_role`/definer only (cron/heartbeat) |

### 10A.8 Deny-by-default conformance

Every new object is `REVOKE ALL FROM anon, authenticated, public` first, then GRANT only the exact SELECT
columns / EXECUTE the tables above authorise (I-7). Absence of a policy is denial (I-1). No new object uses
`USING (true)` (I-2). No new object exposes an identity or money column to a broad role (I-4). Every predicate
is a live-table read via `has_org_role` / `has_venue_role` / `is_platform`, never a JWT claim (I-5, C36) — and
no new bare-string role comparison is introduced anywhere.

---

## 11. Surfaces

### 11.1 Venue dashboard — `NEW DASHBOARD SURFACE`

Closes VD §12.4's "Gap" and VD Δ1; the surface's copy is already written there and is adopted verbatim.

- **Manifest control (§12.4).** Read-only status becomes an **Open door manifest** / **Close door manifest**
  control, gated to the §4 roles. Blast-radius confirm before the control enables (VD §2 principle 7):
  > *"Opening the door manifest stops ticket holders sending or reselling tickets for this session. Do it when
  > doors open."*
  Extended with the drain consequence (§7.3):
  > *"N pending transfers and M active listings will be cancelled and returned to their owners."*
  — with the real counts, computed by a dry-run read before the confirm enables.
- **Freeze status card (new).** Shows `effective_freeze_at`, and **which input produced it**:
  *"Transfers close at 10:00 PM (door manifest opened)"* vs *"Transfers close at 10:00 PM (scheduled doors —
  manifest not opened)"*. Operators must be able to distinguish; fans must not.
- **Session cards (§6, §7.6).** After open: **"Door open — transfers closed."** After close: **"Doors closed —
  transfers remain closed."** — the second half is new and is required, or an operator will read "closed" as
  "back to normal."
- **Episode history.** The `venue.door_manifest` rows for the session: opened/closed times, who, reason, entry
  count, admitted count. This is the audit surface for "when exactly did transfers stop."
- **Override.** **Not on this surface.** Overrides are `platform_admin`-only and live in the internal admin
  plane (RN §8 / admin).
- **Scheduled open (optional).** A scheduler calling the RPC at `doors_at`. Marked optional because the
  implicit boundary (§3) already makes the freeze fail-closed without it; a scheduled open only adds the
  *offline capability*, not the safety.

### 11.2 Scanner (RN §7) — `NEW RN SURFACE`

- **New state: `awaiting_manifest`.** When `venue.get_door_manifest` returns `no_open_manifest`:
  > *"Doors aren't open yet. A manager needs to open the door manifest before this device can work offline."*
  Online scanning **continues to work** in this state (C37) — the banner must say so:
  > *"You can still scan while you have a connection."*
  This is the difference between fail-closed against fraud and fail-closed against paying customers, and the
  copy must carry it.
- **Manifest state row** in the existing §10.2 device-status matrix: `no manifest` · `syncing` ·
  `fresh (v N, synced Xm ago)` · `stale (past not_after — offline admits disabled)` · `episode closed`.
- **No Open control anywhere in the scanner** (O-4). Not disabled — **absent**, per VD §5's rule that surfaces
  a role cannot use are absent rather than disabled, so a door operator never learns the control exists.
- **New reject reason surfacing:** `version_stale` offline (§9.2) reuses the existing operator copy
  *"This pass is out of date. Ask them to open the Snatch It app."* — no new vocabulary.
- **One new reject reason, `refund_hold`** (§9.2), online and offline, with its own copy:
  > *"A refund is being reviewed on this ticket, so it can't be used yet. If they don't want the refund, it has
  > to be cancelled in the Snatch It app — then this ticket works again."*
  It must render as a deny banner in the same weight as `listed_locked`, and **must not** be worded to imply
  fraud: the holder in front of the door is a paying customer whose own refund request is parked, and the
  action available to them is a real one (RPC §17.3).

### 11.3 Consumer RN — `NO CHANGE`

RN §4.4.1 / §4.5 / §12(5) already disable Transfer and Sell on the freeze boolean with the copy *"Transfers are
closed while the event is underway."* That copy is correct for both the explicit and the implicit boundary and
must not be changed to mention doors, manifests, or times — the product-language rule (RN §0) binds. The client
keeps reading `kernel.is_transfer_frozen` as an owner-scoped boolean; only its body changes (§3).

One addition (`NEW RN SURFACE`, small): a drained transfer or listing (§7.3) produces a notification
> *"Your transfer was cancelled because doors opened — the ticket is back in your account."*
> *"Your listing closed because doors opened."*

---

## 12. Audit events and event-envelope messages

### 12.1 `kernel.admin_audit` rows (req 12) — `NO SCHEMA CHANGE`

Every row is INSERTed **in the same transaction** as the action (RPC §0.3).

| `action` | `subject_kind` / `subject_id` | `reason_code` | `before` → `after` |
|---|---|---|---|
| `session.door_manifest_open` | `event_session` / `session_id` | `doors_open` \| `reopen_device_failure` \| `reopen_operator` \| `drill` | `{door_open_at, open_episodes}` → `{door_open_at, manifest_id, manifest_version, entry_count, digest, freeze_newly_engaged}` |
| `session.door_manifest_close` | `event_session` / `session_id` | `doors_closed` \| `session_ended` \| `operator_close` \| `device_recall` | `{manifest_id, status:'open'}` → `{status:'closed', closed_at, admitted_count, offline_pending_count}` |
| `session.door_freeze_engaged` | `event_session` / `session_id` | `explicit_open` \| `implicit_doors_time` | `{door_open_at: null}` → `{effective_freeze_at, source}` |
| `session.door_manifest_drain` | `event_session` / `session_id` | `door_freeze` | `{pending_transfers, active_listings}` → `{cancelled_transfers[], cancelled_listings[]}` |
| `session.door_freeze_override_grant` | `event_session` **or** `ticket_atom` | closed set, §8.1 | `null` → `{override_id, scope, expires_at, granted_by}` |
| `session.door_freeze_override_revoke` | as above | `revoked_by_admin` \| `revoked_by_risk` | `{active}` → `{revoked_at, revoked_by}` |

`session.door_freeze_engaged` for the **implicit** case has no transaction of its own; it is emitted by the
notification sweep (§12.3), at-most-once by its idempotency key. It is an observability record, never a
correctness dependency.

### 12.2 Event-envelope messages — `ADDITIVE` (new domain events)

Envelope guarantees per CDM C12: per-aggregate monotonic `sequence`, `causation_id`, `correlation_id`,
at-least-once delivery, every consumer idempotent by a persisted dedup key or expressing its effect as an
upsert/set-operation (never a naked increment).

| # | Event | Origin | Payload | Consumers | Sync/Async | Idempotency key |
|---|---|---|---|---|---|---|
| 37 | **DoorManifestOpened** | venue | `manifest_id, session_id, event_id, venue_id, manifest_version, opened_at, entry_count, manifest_digest, not_after, freeze_newly_engaged` | notify (fan "transfers closed"), analytics, risk, scanner push-to-sync | **Sync** — written to the outbox inside the open txn | `manifest_id` |
| 38 | **DoorManifestClosed** | venue | `manifest_id, session_id, closed_at, close_reason, admitted_count, offline_pending_count` | notify, analytics, reconciliation monitor | **Sync** | `manifest_id + 'closed'` |
| 39 | **TransferFreezeEngaged** | catalog | `session_id, event_id, effective_freeze_at, source ∈ {explicit_open, implicit_doors_time}` | notify (pre-freeze warning + freeze notice), market (invalidate cached eligibility), analytics | **Sync** for `explicit_open`; **Async (sweep)** for `implicit_doors_time` | `session_id + 'freeze'` — at most once per session, ever |
| 40 | **DoorManifestDrained** | market | `session_id, manifest_id, cancelled_transfer_ids[], cancelled_listing_ids[]` | notify (per affected party), analytics | **Sync** (same txn as the drain) | `manifest_id + 'drain'` |
| 41 | **DoorFreezeOverrideGranted** | kernel | `override_id, session_id, ticket_atom_id?, expires_at, reason_code, granted_by` | risk, notify (platform ops), analytics | **Sync** | `override_id` |
| 42 | **DoorFreezeOverrideEnded** | kernel | `override_id, ended_at, ended_by ∈ {revoke, expiry}` | risk, analytics | Async | `override_id + 'ended'` |
| 43 | **DoorManifestSupplemented** | venue | `manifest_id, session_id, delta_seq, op, ticket_atom_ids[]` | scanner push-to-sync, analytics | **Sync** (same txn as §7.7) | `manifest_id + delta_seq` |
| 44 | **DoorManifestInvalidated** | venue | `manifest_id, session_id, reason ∈ {event_cancelled, freeze_override, force_void, key_revoked}, invalidated_at` | scanner (drop M2, disarm), dashboard alert, risk | **Sync** | `manifest_id + reason` |

Numbering continues the domain-architecture §6.1 catalog (which ends at 36). None of these are money or
custody events; none ride the transactional spine (§6.2 of that document) except as outbox rows written inside
their own transaction.

### 12.3 The notification sweep — `NEW RPC`

`catalog.sweep_implicit_door_freezes()` — definer batch, `service_role` only. Finds sessions where
`now() >= effective_freeze_at` and no `TransferFreezeEngaged` has been emitted, emits it once, writes the
`session.door_freeze_engaged` audit row, and stops. **It is not load-bearing:** `is_transfer_frozen` computes
the implicit boundary arithmetically and is correct whether or not this sweep ever runs. That property is
stated here explicitly because the failure this document exists to close was a correct thing that nothing
called; nothing in this design may reproduce it.

---

## 13. Defects found in the frozen set (`SPEC CORRECTION` — all five)

These are not new design; they are contradictions the door lifecycle exposes. Each is stated with its verbatim
source so a reviewer can check it without re-deriving.

### 13.1 `mark_ticket_scanned` rejecting on `frozen` denies admission to every fan — **CRITICAL**

RPC §12.4, verbatim: *"`market.create_listing`, `market.create_p2p_transfer`, `kernel.lock_ticket`, and
`kernel.mark_ticket_scanned` **re-check `kernel.is_transfer_frozen` under the atom lock** … and reject with
`frozen`."* (RLS §14.3 repeats it.)

As written: opening the manifest sets `door_open_at`; `is_transfer_frozen` then returns true for every atom of
the session; `mark_ticket_scanned` therefore rejects **every scan** for the rest of the night. Nobody gets in.

The intent was presumably that a mid-transfer atom must not be scanned — but that is already enforced by
`mark_ticket_scanned`'s own precondition `resale_state = 'none'` (RPC §7.5), and by the same document's
statement that *"scan is not a custody change."* The freeze is a **custody-move** guard; scanning is not a
custody move.

**Correction:** remove `kernel.mark_ticket_scanned` from the recheck set (§7.6). It must never consult
`is_transfer_frozen`.

### 13.2 The freeze gates transfer *start* but not *completion*

`market.create_p2p_transfer` rechecks (RPC §12.4); `market.accept_p2p_transfer` and
`kernel.transfer_ticket_ownership` do **not** appear in the recheck set. A transfer initiated at 21:00 and
accepted at 23:30 — with doors open at 22:00 — moves custody and bumps `credential_version` after the manifest
snapshot: precisely the stranding C6 exists to prevent. C43's TTL auto-unlock mitigates but does not close it
(the TTL may be many hours).

**Correction:** add both to the recheck set, with `transfer_ticket_ownership` as the enforcement point (§7.6).

### 13.3 The offline door cannot detect a stale credential

Edge §5.4's four offline-verify steps contain no `credential_version` check, and the only manifest the edge
spec defines (§5.4) is a **public-key** manifest. The offline door therefore verifies that a token was validly
signed, not that it is current.

**Correction:** §9.1 (name and home the ticket manifest) + §9.2 (add verify step 3b). Without this, requirement
14's guarantee cannot be true no matter how the freeze is implemented.

### 13.4 A frozen `paid_pending_transfer` sale would strand money

`market.sweep_paid_pending_sales` (RPC §12.3) resolves a stuck sale by *either* completing the transfer *or*
auto-compensating (refund-void). If the freeze applied to both branches, a sale caught by doors-open could do
neither: complete is a custody move (frozen) and compensate is a refund-void (frozen under C23). The money sits
in `paid_pending_transfer` forever — the exact unbounded-dwell failure C25 exists to forbid.

**Correction (§7.6):** the **complete** branch is frozen; the **compensate** branch is exempt. A sale caught by
doors-open therefore resolves as `compensated` — the buyer is refunded, which is the correct outcome, because a
buyer who cannot receive a credential before an offline door opens was never going to be admitted.

### 13.5 In-flight overlays lock fans out of the show

Covered in full at §7.3. `mark_ticket_scanned` requires `resale_state='none'`; a frozen session leaves
`locked`/`listed` atoms unresolvable until TTL; the holder is refused at the door with no remedy.
**Correction:** the drain (§7.3).

---

## 14. Failure modes and fail-closed behaviour

| # | Failure | Behaviour | Direction |
|---|---|---|---|
| 1 | Nobody ever opens the manifest | Freeze engages at `COALESCE(doors_at, starts_at)` (§3). Online scanning works; offline scanning unavailable. | **fail-closed on custody, fail-open on admission** — deliberate |
| 2 | `doors_at` NULL | Backstop falls to `starts_at` (`NOT NULL`). Boundary is total. | fail-closed |
| 3 | `doors_at` set wrong (too early) | Transfers freeze early. Recoverable via §8 override. | fail-closed, recoverable |
| 4 | `doors_at` set wrong (too late) | Bounded by `LEAST` with any explicit open; if neither, by `starts_at`. | fail-closed |
| 5 | Two managers open simultaneously | Second returns `noop_replay`; one episode, one boundary (§5.2). | deterministic |
| 6 | Manager opens, then re-opens after a scanner crash | New episode, new `manifest_version`, fresh snapshot; `door_open_at` unchanged; audited with `reopen_device_failure`. | monotone |
| 7 | Device never syncs | Device has no manifest ⇒ online-only. Dashboard shows it as *not synced*, not *offline-ready*. | fail-closed |
| 8 | Device offline past `not_after` | Device refuses offline admits, falls back to *"needs a connection"*. Bounded by `door.manifest_ttl_interval`. | fail-closed |
| 9 | Device clock skewed | Existing ±2-time-bucket tolerance (edge §5.4) applies to `exp`; `not_after` carries the same allowance. | bounded |
| 10 | Venue network dies at doors time | Manifest cannot be opened ⇒ no offline capability. **Mitigation: open early** (§14.5). Freeze still engages implicitly at `doors_at`, so custody is safe regardless. | fail-closed on custody |
| 11 | Session cancelled after open | `record_scan` requires `status='live'` ⇒ admission stops. Freeze remains (boundary preserved). | fail-closed |
| 12 | `door_open_at` somehow written directly | Trigger (§10.2) raises. GP-1 already denies client DML; the trigger catches a *future RPC bug*. | fail-loud |
| 13 | Attempt to set `door_open_at` in the future | CHECK / trigger rejects; the RPC accepts no timestamp (§6.2). | fail-loud |
| 14 | Close called with unreconciled offline scans | Close succeeds; count is surfaced. Blocking close on a lost device would pin a session open forever. | fail-open, observable |
| 15 | Override requested while an episode is open | `precondition_failed('manifest_open')` — close first (§8.2). | fail-closed |
| 16 | Override expires mid-transfer | The transfer's own `FOR SHARE` recheck under lock re-evaluates; an in-flight txn that already passed the check commits (it holds the atom lock and cannot strand — the boundary is about *new* moves). | bounded |
| 17 | The notification sweep never runs | `is_transfer_frozen` is arithmetic and unaffected; only the pre-freeze warning push is lost. | **not load-bearing, by construction** |
| 18 | Manifest fetched, then the episode is closed | Device's `not_after` still holds, but the dashboard shows the episode closed and the device stale. `reconcile_offline_scans` accepts the batch (it references the closed `manifest_id`). | reconcilable |
| 19 | **Box-office sale or late comp after the manifest opened** (Wallet DL-1) | The atom is absent from the base snapshot. `append_door_manifest_delta('add')` appends it (§7.7); the **selling** device is online by construction and admits immediately; **other** devices admit only after they sync the delta. Without a sync they refuse a paying fan — an operational limit, in the runbook (§7.7). | fail-closed against the fan on un-synced devices — **named, not silent** |
| 20 | **Event cancelled while a device is offline** (Wallet DL-2) | `cancel_event` force-closes the episode, sets `not_after := now()`, writes `revoke` deltas and emits `DoorManifestInvalidated` (§7.2.1). Online devices disarm at once. A device that never reconnects keeps admitting until its **downloaded** `not_after`. | bounded by the TTL the device holds — C6's window, named |
| 21 | **Break-glass override or force-void between episodes** (Wallet DL-3) | Force-close + invalidate + push + live-device acknowledgement (§8.2.1). An offline device would admit the pre-override owner and refuse the post-override one. | shrunk, not closed — the only *custody* residual in the design |
| 22 | **C25 compensate voids an atom while an episode is open** (§5.4) | `void_ticket_atom` writes a `revoke` delta (§7.6). A synced device drops the atom; an offline device admits a refunded ticket. **Revenue leak, not a double-admit** — no second person is admitted and the wrong owner is never admitted. | bounded by the device's TTL; the only residual that fires **without a human** |

### 14.5 The one operationally painful case, named

Failure #10 — the venue's network is down at exactly doors time — is the only case where fail-closed costs the
operator real capability: no manifest can be opened, so no offline scanning is available on the night it is
most needed. **The mitigation is procedural and must be in the runbook and the dashboard copy: open the
manifest and sync every device at soundcheck, hours before doors.** Opening early is safe (it only freezes
transfers early, and the implicit boundary was going to freeze them at `doors_at` anyway) and is explicitly
permitted by `door.manifest_early_open_window`. The dashboard's Open control should say so:
> *"Open early. Devices sync while you have signal; transfers close now instead of at doors."*

---

## 15. pgTAP assertion list (req 13 — assertions described, no SQL authored)

Grouped by the property each group defends. All are DB-level; none require the app.

> **Naming: THIS LIST'S ORDINALS ARE ITS PRIMARY IDS, AND THE ALIASING IS DELIBERATE — stated 2026-08-28
> (`R3-5`), because it was not stated anywhere before and an unremarked second name reads as a duplicate.**
>
> An assertion here may be cited by up to **three** names, and all three refer to **one** assertion, not to
> two that happen to agree:
> 1. **the ordinal** — *"door §15 assertion 77"* — the primary id, stable, and the form the totals and the
>    group sizes count;
> 2. **a `T-DOOR-*` id**, carried by assertions whose property a sibling document needs to cite by name.
>    **There are exactly two in this list: `T-DOOR-PROJ-01` (= 77) and `T-DOOR-PROJ-02` (= 78);**
> 3. **a sibling register's id**, where the same property is also scheduled in another document's register —
>    for the `MP-1` pair that is **`T-RPC-DOOR-33` (= 77 = `T-DOOR-PROJ-01`)** and **`T-RPC-DOOR-34`
>    (= 78 = `T-DOOR-PROJ-02`)** in `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §18/§20.6.1.
>
> **So the `MP-1` pair carries three names each, across three schemes.** That is intentional — a
> door-owned property that an RPC contract must also schedule needs a name in both registers — but it was
> nowhere declared, and **two names with no declared relation are indistinguishable from two assertions**,
> which is how a corpus ends up implementing one of them. **Where the two documents' wordings ever differ,
> this list governs the property and the sibling register governs the scheduling.** `R3-5` rewrote 77/78
> here; **the `T-RPC-DOOR-33`/`-34` twin still carries the superseded "derived read set" / count-floor
> wording and must be brought into line by the RPC owner** — filed as `DR-1` in §21.
>
> **The remaining cross-scheme aliases are NOT enumerated here**, because the sibling ids
> (`T-RPC-DOOR-*`, `T-SCHEMA-DOOR-30`…`-35`, `T-RLS-DOOR-11`…`-13`) live in three other owners' registers
> and an inventory written from this side would be a fourth copy going stale. **Filed as `DR-2` in
> §21**: each register states its own aliases, and the traceability matrix §9 holds the join.

**A. Structure and grants (7)**
1. `venue.door_manifest`, `venue.door_manifest_entry`, `kernel.door_freeze_override` exist with RLS **enabled**.
2. `anon` and `authenticated` hold **no** INSERT/UPDATE/DELETE on any of the three (GP-1).
3. The partial `UNIQUE(session_id) WHERE status='open'` exists on `venue.door_manifest`.
4. `catalog.engage_door_freeze` has **no** EXECUTE grant to `anon` or `authenticated` (definer-only, §7.4).
5. Every new function is owned by `postgres`, is `SECURITY DEFINER`, and has a pinned `search_path`
   (Standards §8).
6. `venue.door_manifest_entry` exposes no owner/identity column (the door's bulk read carries no PII, §7.5).
7. `kernel.door_freeze_override` has RLS on with **zero** policies (audit-only class).

**B. Monotonicity of the boundary (6)**
8. First `open_door_manifest` sets `door_open_at = opened_at`; `freeze_newly_engaged = true`.
9. Second `open_door_manifest` after a close creates a new episode with `manifest_version = 2` and leaves
   `door_open_at` **byte-identical**; `freeze_newly_engaged = false`.
10. `close_door_manifest` leaves `door_open_at` **byte-identical** (req 9).
11. A direct `UPDATE catalog.event_session SET door_open_at = NULL` raises (trigger §10.2).
12. A direct `UPDATE … SET door_open_at = door_open_at - interval '1 hour'` raises.
13. A direct `UPDATE … SET door_open_at = now() + interval '1 hour'` on a session with no episode raises
    (ledger-head mismatch **and** not-future).

**C. Fail-closed at NULL (5)**
14. Session with `door_open_at IS NULL`, `doors_at = now() - 1 minute` ⇒ `is_transfer_frozen(atom) = true`.
15. Same session with `doors_at IS NULL` and `starts_at = now() - 1 minute` ⇒ `true`.
16. Same session with `doors_at = now() + 1 hour` ⇒ `false`.
17. `catalog.effective_freeze_at` returns **NOT NULL** for every row in `catalog.event_session`
    (a set-level assertion, run over a seeded fixture of every status × nullability combination).
18. Changing `door.implicit_freeze_offset_interval` to `'+30 minutes'` moves case 14 to `false` and case
    `now() - 31 minutes` to `true` (config is read, not hard-coded).

**D. Authority (7)**
19. `venue_manager` of the venue may open; result `ok`.
20. `org_owner` and `org_admin` of the operating org may open (inheritance expressed in the RPC, RLS §2.4).
21. **`venue_scanner` may not open** → `insufficient_privilege(42501)`, and `door_open_at` is unchanged (O-4).
22. A token-bound door-session principal may not open → `42501`; and **no bare `door_pin` authorizes anything** — `venue.get_door_manifest` presented a `door_pin` without a `kernel.assert_door_session` token raises `42501` (`AUTHZ-H3`, `DL-X3`).
23. `venue_finance`, `venue_box_office`, `venue_marketing`, `venue_promoter_manager`, `org_finance`, `org_marketing`, `org_promoter_manager`, `platform_support`, `platform_risk` may not open → `42501`.
24. A `venue_manager` of a **different** venue may not open → `42501` (cross-tenant).
25. `venue_scanner` **may** call `venue.get_door_manifest` for its own session and **may not** for another
    session of the same venue.
25a. **No label outside the fifteen canonical labels of RLS §2.1 appears in any predicate in this file** — the
    `T-RLS-EXEC-02` rule class, asserted **over this document** rather than only over RLS §11, which is the gap
    `DL-X4` closes (§20).

**E. Idempotency and concurrency (6)**
26. Two `open_door_manifest` calls with the same `p_command_key` ⇒ one episode; second returns
    `noop_replay` with the same `manifest_id`.
27. Two calls with **different** command keys while an episode is open ⇒ one episode; second returns
    `noop_replay` (state guard, not just the key).
28. Two concurrent sessions (`pg_background`/two connections) racing `open_door_manifest` ⇒ exactly one row in
    `venue.door_manifest`; the partial unique is the backstop even if the state guard is bypassed.
29. `close_door_manifest` on a session with no open episode ⇒ `noop_replay`, not an error.
30. A transfer holding `FOR SHARE` on the session blocks a concurrent `open_door_manifest` until it commits
    (a lock-wait assertion, `pg_locks` inspected from a third connection).
31. After the open commits, a transfer that was waiting on `FOR SHARE` returns `frozen`.

**F. The Door Safety Theorem (5)**
32. Open a manifest; assert every `venue.door_manifest_entry.credential_version` equals the live
    `kernel.tickets.credential_version` for that atom.
33. Attempt `transfer_ticket_ownership` for an atom of the session ⇒ `frozen`; the entry's version still
    matches live.
34. Attempt `accept_p2p_transfer` for an atom of the session ⇒ `frozen` (§13.2 regression test).
35. Attempt the routine `refund_primary_order` → `void_ticket_atom` path ⇒ `frozen` (C23).
36. `catalog.cancel_event` on the same session **succeeds** despite the freeze (exempt), and voids the atoms.

**G. Admission is never blocked by the freeze (4) — the §13.1 regression suite**
37. With an episode open and `is_transfer_frozen = true`, `venue.record_scan` on an `active`,
    `resale_state='none'` atom ⇒ `result='admitted'`, atom `state='scanned'`.
38. The same on a **second** scan ⇒ `result='duplicate'`, atom stays `scanned` (C41 first-in-wins holds under
    freeze).
39. `kernel.mark_ticket_scanned` does **not** reference `kernel.is_transfer_frozen` — asserted by
    `pg_get_functiondef` not matching `is_transfer_frozen` (a structural test, so a future edit re-breaking
    §13.1 fails CI).
40. With the session `status='completed'`, `record_scan` ⇒ `precondition_failed` (admission is gated by
    session status, not by manifest state).

**H. Drain (5) — §7.3 / §13.5**
41. An `initiated` p2p for the session becomes `cancelled` + `reason_code='door_freeze'` on open; the atom's
    `resale_state = 'none'`; the **sender** is still `current_owner_id`.
42. The drain appends **no** `kernel.ticket_ownership_log` row and does **not** bump `credential_version`.
43. An `active` listing is cancelled; its atom unlocks.
44. A listing whose sale is `paid_pending_transfer` is **not** cancelled (money protected, §13.4).
45. The drained atom then scans successfully (the end-to-end lockout regression).

**I. Override (6)**
46. `platform_admin` may grant; `org_owner`, `venue_manager`, `platform_risk`, `platform_support` may not
    (`42501`).
47. A grant while an episode is `open` ⇒ `precondition_failed('manifest_open')`.
48. A grant with `expires_at > granted_at + door.max_override_interval` ⇒ `check_violation`.
49. With an active override, `is_transfer_frozen` returns `false` for the covered scope and `true` for an atom
    of the same session outside an atom-scoped override.
50. `door_open_at` is **byte-identical** before and after grant, revoke, and expiry (req 6's history
    preservation).
51. Past `expires_at`, `is_transfer_frozen` returns `true` again with **no sweep having run**.

**J. Append-only guards (4)**
52. `UPDATE venue.door_manifest SET opened_at = …` raises.
53. `UPDATE venue.door_manifest SET status='open'` on a closed row raises (no reverse transition).
54. `DELETE FROM venue.door_manifest` / `venue.door_manifest_entry` / `kernel.door_freeze_override` raises
    (GP-2).
55. `UPDATE venue.door_manifest_entry SET credential_version = …` raises.

**K. Audit (3)**
56. Every one of open / close / drain / override-grant / override-revoke writes exactly one
    `kernel.admin_audit` row in the same transaction, with a non-null `reason_code` and a server-derived
    `actor_identity` equal to the test's `auth.uid()`.
57. A rolled-back open writes **no** audit row (same-transaction property).
58. `kernel.admin_audit` remains unreadable by `authenticated` (audit-only class).

**L. Manifest completeness and reject mapping (5) — §9.2 / DL-5**
59. The base snapshot contains **every** atom of the session, including `voided` and `scanned` ones
    (`count(door_manifest_entry) = count(kernel.tickets WHERE event_session_id = S)`).
60. A `voided` atom appears in M2 with `ticket_state='voided'` — so the offline reject maps to `voided`, not
    `wrong_session`.
61. An atom of a **different** session is absent from M2 — so `wrong_session` is reachable and means only that.
62. A `paid_pending_transfer` atom appears with `resale_state='locked'` — the offline door refuses it for the
    same reason the online door does (`listed_locked`), and the two doors agree.
63. `venue.door_manifest_entry` still exposes no identity column after the completeness change (re-asserts
    pgTAP 6 against the widened row set).

**M. Delta log (7) — §7.7 / DL-1 / §5.4**
64. `issue_ticket_atoms` with an open episode appends one `op='add'` delta per minted atom, each with
    `credential_version = 0`.
65. The `CHECK` rejects an `op='add'` delta with `credential_version <> 0` (the theorem made structural).
66. `issue_ticket_atoms` with **no** open episode appends nothing and does **not** error (silent no-op).
67. A replayed `issue_ticket_atoms` (same command key) appends no second delta
    (`UNIQUE(manifest_id, ticket_atom_id, op)`).
68. An exempt `void_ticket_atom` (C25 compensate branch) with an open episode appends one `op='revoke'` delta.
69. `venue.get_door_manifest(S, p_since_delta_seq := k)` returns exactly the deltas with `seq > k` and no base rows.
70. `UPDATE`/`DELETE` on `venue.door_manifest_delta` raises (AO guard).

**N. Cancellation and break-glass invalidation (6) — §7.2.1 / §8.2.1 / DL-2 / DL-3**
71. `catalog.cancel_event` on an event with an open episode closes it with `close_reason='event_cancelled'`.
72. …and sets that episode's `not_after <= now()`.
73. …and emits `DoorManifestInvalidated` with `reason='event_cancelled'`.
74. …and leaves `door_open_at` byte-identical (cancellation is not an unfreeze).
75. `grant_door_freeze_override` without `p_ack_live_devices` matching the live synced-device count raises
    `precondition_failed('unacknowledged_live_devices')`.
76. A platform force-void on a session with an open episode force-closes that episode before voiding.

**P. Projection completeness (7) — §7.5a / `MP-1`. This group is the acceptance property, not a sample.**

The defect these defend is not a wrong value; it is a **missing column**, which every value-based test passes.
So 77 is written **structurally** — over the projection's column list — and the rest are the behavioural
consequences that would have been silent.

> **`R3-5` — 77 AND 78 CONTRADICTED EACH OTHER, AND 78 WAS RED AGAINST THE CORRECT FENCE ON DAY ONE.
> REWRITTEN 2026-08-28. The fenced block is untouched.**
>
> **Three defects, in one pair of assertions.**
> **(i) Unsatisfiable.** 78 said the parse *"fails if that parse yields fewer than **five** distinct
> fields"*. The pattern it parses for is `M2[atom].<field>`, and the block contains **exactly four** such
> references — `M2[atom].credential_version` (3b.iii) · `M2[atom].ticket_state` (3b.iv) ·
> `M2[atom].resale_state` (3b.v) · `M2[atom].signing_key_id` (3c). **The fifth per-atom field,
> `ticket_atom_id`, comes from `atom ∈ M2` (3b.i), which is a membership test and carries no `.field`
> suffix**, so no correct fence can ever satisfy a `≥ 5` floor on that pattern. **The gate was red against
> the right document**, and the only ways to make it green were to weaken the floor or to edit the fence —
> the second being CI-gated and the first being the failure it exists to prevent.
> **(ii) Contradiction.** 77 compared against a **hard-coded** set written out beside it; 78 said that set
> is **derived**. Both cannot be true, and the corpus cited each version in a different place.
> **(iii) A count floor is not the property.** Even satisfiable, `≥ n distinct fields` is the exact shape
> **`AUTHZ-C1C`** ruled against for `T-RLS-ROLE-02`: *a count assertion passes on the wrong set of the right
> size*. A sixth conjunct reading a **new** field, added while an old one is dropped, keeps the count and
> leaves 77 green against a stale list — the drift 78 exists to catch.
>
> **The fix is the one `T-RLS-ROLE-02` / `T-RLS-ROLE-06` already model:** one **literal enumeration** stated
> in exactly one place (§7.5a's derivation table), 77 consuming that literal list, and 78 asserting **set
> equality** between that list and what the fence actually yields — **in both directions, per pattern, with a
> non-vacuity guard** — never a count.

77. **`T-DOOR-PROJ-01` (structural, the acceptance property).** Every field of the **`MP1-READ-SET`** —
    §7.5a's derivation table, which is the single literal enumeration and is consumed, not re-typed —
    appears in `venue.get_door_manifest`'s entry projection **and** in its `op='add'` delta projection.
    **`MP1-READ-SET` is, per atom: `ticket_atom_id` · `credential_version` · `ticket_state` ·
    `resale_state` · `signing_key_id` (five); on the header: `session_id` · `not_after` (two); on a delta
    row: `op` · `ticket_atom_id` (two, the 3b.ii linkage).** Asserted by **column-list comparison** as a
    **subset** in the projection direction — §7.5a's rule is a superset rule, so operator-facing extras
    (`serial_no`, `ticket_type_id`) are legal — and **never by scanning a returned row**, since a row proves
    only that one atom had those columns populated. **Fails if any field of `MP1-READ-SET` is absent from
    either projection**, which is the exact regression `MP-1` was. **Set equality between the two
    projections is assertion 79**, so the pair together forbids one projection gaining a field the other
    lacks.
78. **`T-DOOR-PROJ-02` (structural, the anti-vacuity half of 77) — SET EQUALITY, NOT A COUNT.** The
    assertion extracts the `OFFLINE-VERIFY-v1` block and asserts that what the block yields **equals**
    `MP1-READ-SET`, **in both directions**, by running each of the four extraction patterns separately and
    comparing each result against its own literal expectation:
    - **`M2[atom].<field>`** ⇒ must equal **exactly** `{credential_version, ticket_state, resale_state,
      signing_key_id}` — **four**, and the enumeration is the assertion, not the number;
    - **`atom ∈ M2`** (3b.i, membership) ⇒ must be **present**, and contributes `ticket_atom_id`. **This is
      the conjunct the old `≥ 5` floor could not see**, and it is why the pattern set is four patterns
      rather than one;
    - **the applied-`revoke`-delta clause** (3b.ii) ⇒ must be **present**, and contributes delta `op` +
      `ticket_atom_id`;
    - **conjunct 3 and the no-M2 clause** ⇒ must yield **exactly** `{session_id, not_after}` on the header.

    **Failure is symmetric and that is the whole value:** a field in the block and not in `MP1-READ-SET` is
    a conjunct the wire does not carry (the `MP-1` regression); a field in `MP1-READ-SET` and not in the
    block is a stale list still being enforced. **A sixth conjunct therefore fails 78 immediately**, whether
    or not it changes the field count.

    **Non-vacuity guard, four parts, because every one of them is a way this assertion silently passes:**
    (a) the extraction must find **at least one** `OFFLINE-VERIFY-v1` block under `docs/architecture/**` —
    zero blocks is a hard fail, never a pass (this is the same floor the CI gate states as
    `OFFLINE_VERIFY_MIN_BLOCKS`, and 78 **reuses that gate's extractor rather than reimplementing it**, so a
    fence that stops being recognised fails both or neither); (b) the block it read must be the
    byte-identical body the gate certifies, so 78 cannot be satisfied by a divergent copy; (c) **each** of
    the four patterns must return a **non-empty** result — a broken parser returning nothing everywhere
    would otherwise satisfy every equality vacuously; (d) `MP1-READ-SET` as read from §7.5a must be
    non-empty and must contain the five per-atom names, so an emptied derivation table cannot make the
    comparison trivial. **This assertion reads the fenced block; it never edits one.**
79. The entry projection and the `op='add'` delta projection have **identical column lists** (§7.5a), asserted
    as set equality in both directions, so neither can gain a field the other lacks.
80. The `CHECK` rejects an `op='add'` delta with `ticket_state <> 'active'`, and one with
    `resale_state <> 'none'` (§10.3a).
81. The `CHECK` rejects an `op='add'` delta with any of `ticket_state`, `resale_state`, `serial_no`,
    `ticket_type_id` NULL; and rejects an `op='revoke'` delta with any of them **non**-NULL.
82. An atom supplemented by an `add` delta is admissible **offline** by the full predicate from the delta row
    alone — evaluated with the base snapshot excluded from the fixture, so a field silently inherited from a
    base entry cannot mask a missing delta column. This is the DL-1 door-sale case and the one
    `signing_key_id`'s CHECK was written for.
83. `venue.door_manifest_entry` and `venue.door_manifest_delta` still expose no identity column after the
    `ticket_type_id` addition (re-asserts pgTAP 6 and `T-RPC-DOOR-17` against the widened row set —
    `ticket_type_id` is a catalog reference and must not be mistaken for one).

**Total: 83 assertions.** Groups **G** and **B** are the regression suites for the two defects that would
otherwise recur silently (§13.1 and req 5). Group **F** is the machine-checkable form of the Door Safety
Theorem; group **M** assertion 65 is the theorem enforced as a `CHECK` rather than as prose. Group **P** is
the **acceptance property for `MP-1`**: it is the only group asserted over a *column list* rather than over
values, because the defect it defends against — a field the predicate reads and the wire never carries — is
invisible to every value-based test.

---

## 16. Open questions (owner decisions)

**OQ-1 — Does opening the manifest early bother anyone commercially?**
§14.5 recommends opening at soundcheck. That freezes transfers hours before doors, which is safe but removes a
window in which a fan might legitimately still want to send a ticket to a friend who is running late. The
alternative is to decouple: open the *manifest* early (offline capability) but engage the *freeze* at
`doors_at`. **This spec deliberately does NOT decouple them**, because the decoupled form reintroduces exactly
the snapshot-then-freeze window §5.3 closes — a transfer committing between manifest generation and freeze
would strand a credential at an already-armed offline door. If the commercial cost of the early freeze is
judged too high, the only safe alternative is to **re-snapshot the manifest at the freeze moment**, which means
devices must re-sync at doors, which reintroduces failure #10. Recommend: keep them coupled; accept the early
freeze. **Owner call.**

**OQ-2 — Draining active listings at door-open (§7.3).**
Cancelling a seller's live listing when doors open is a product act, not just a technical one. The alternative
(leave it listed, refuse the holder at the door with `listed_locked`) is worse but is *visible* to the seller,
whereas cancellation is a surprise. Recommend: drain, with the notification in §11.3. **Product sign-off.**

**OQ-3 — `venue_box_office` over-provisioning (§4.1). RESTATED 2026-08-28 (`DL-X2`) — the "fifth enum label"
half is CLOSED; the grant-hygiene half is still open.**
This question was posed against a **four-label** venue enum in which no box-office label existed, and offered
"a fifth enum label" as one of two remedies. **The canonical venue enum is six labels and `venue_box_office`
is one of them** (schema §0.6, ROLE_MODEL §3.1–§3.3, RLS §2.1), and RLS §11.4 **already excludes it** from
`open_door_manifest` / `close_door_manifest`. So "box_office does not inherit manifest administration" is now
true **structurally**, not merely for want of a label — that half needs no owner call and must not be
re-litigated as one.

**What remains open is narrower and is a grant-hygiene question, not a schema question.** `venue_box_office`
does not yet carry the selling capabilities a box-office seller needs, so in practice such a person may still
be granted `venue_manager` — which **does** grant manifest open/close. Closing that requires VD Δ8's
per-event / expiring / per-capability grants, which is not in scope here. **Owner call — and until it is made,
"box_office does not inherit" is true of the label and of the enum, and can still be false of the human,
through a `venue_manager` grant issued for an unrelated reason.**

**OQ-4 — C43's per-open-manifest-ticket narrowing is Gate-M and the current helper does not implement it.**
Schema §2.3, RPC §12.4, RLS §14.3 and the catalog migration package all say the freeze is *"narrowed per-open-manifest-ticket
per C43"*, but the specified predicate (`door_open_at IS NOT NULL AND now() >= door_open_at`) is **session-
wide**, and C43 is `RATIFIED-MODELED-ONLY(GATE-M)` — not MVP. This spec keeps the session-wide predicate for
MVP and makes the narrowing a pure additive conjunct once `venue.door_manifest_entry` is populated:
```
AND EXISTS (SELECT 1 FROM venue.door_manifest_entry e JOIN venue.door_manifest m USING (manifest_id)
             WHERE e.ticket_atom_id = p_ticket_atom_id AND m.status = 'open')
```
No signature change, no caller change. **Flagged because the four documents currently describe a narrowing
nothing implements** — the same class of claim-without-mechanism this ruling was issued to eliminate. Owner
should confirm the MVP predicate is session-wide.

**OQ-5 — PassKit token TTL. RULED (Wallet DL-4 / OQ-W4) — GRANTED, with a corrected rationale and a tighter
bound than requested. Owner sign-off still required to ratify the relaxation itself.**

*The constraint as originally recorded:* a `.pkpass` "must never carry a longer TTL than the token." That was
circular (the pass carries *the* token) and, taken literally, makes Wallet impossible — a short-TTL barcode
baked into `pass.json` expires on an offline phone and locks a paying fan out. That is the §13.1 failure class,
and I ruled against it twice already in this document. **The outcome the Wallet spec asks for is right.**

*Their rationale is not, and I decline to adopt it.* Wallet §5.3 argues the short TTL "was compensating for
W-3" and that once step 3b exists it "bounds nothing that isn't already bounded." Checked against each threat,
that is too strong in two rows of their own table:

| Threat | Their claim | My finding |
|---|---|---|
| stale token after transfer / routine void | `exp` bounds nothing post-3b | **agreed** — this is the W-3 row and they are right |
| screenshot resale | bounded by first-in-wins, not `exp` | **partly wrong.** First-in-wins bounds *double-admission*, not the fraud: the buyer of a screenshot can beat the legitimate owner to the door, who is then refused. A multi-hour `exp` does kill the sell-it-this-afternoon variant. The close-to-door variant is unaffected by either TTL |
| token signed by a **revoked key** | residual is the M1 refresh window, which a shorter `exp` does not shorten | **wrong as stated.** The residual is `min(exp remaining, M1 refresh)`; a shorter `exp` shortens it directly. Edge §5.6 says so in its own words |

*The ruling.* Grant the session-bounded wallet profile, and make their claim **true** rather than assuming it,
by binding the token to the offline window instead of to a clock:

1. **Adopt the cross-config invariant** `wallet_default_span + wallet_exp_skew <= door.manifest_ttl_interval`
   (§10.6), validated in `set_platform_config` and asserted in CI. A Wallet token then **cannot outlive the
   offline window any manifest could authorise.** Since offline admission is impossible past `not_after`, an
   `exp` inside that bound genuinely constrains nothing extra — which is what their argument needed and did
   not have.
2. **Couple key revocation to episode invalidation.** Revoking a signing key for a scope with an open episode
   MUST force-close and invalidate it (§8.2.1 mechanism, `reason='key_revoked'`, envelope #44). This collapses
   the revocation window to the device's offline duration rather than the token's life. **Without this I would
   reject DL-4**, because item 1 alone leaves a 12-hour token against a revoked key.
   > **`SPEC CORRECTION` — this condition had a mechanism and no caller.** §8.2.1 defines the force-close, and
   > envelope #44's enum already carries `key_revoked`, but **`kernel.revoke_signing_key` was specified nowhere
   > as invoking either** — it was a key-table update and nothing more (edge §5.6, RPC §13). A granted ruling
   > whose condition nothing satisfies is the "correct thing that nothing called" failure class §8.4 exists to
   > refuse. The normative obligation is now written into **edge §5.6** (same-transaction force-close, episode
   > `not_after := now()`, `DoorManifestInvalidated`, audit row) and reported to the RPC-contract owner for
   > `kernel.revoke_signing_key`'s write set and lock order. **Until that lands, this ruling's item 2 is
   > unmet.**
3. Their three mitigations stand and are mandatory: the CI structural test that offline step 3b exists, the
   `wallet.apple.enabled` kill switch, and no-manifest-no-admit. The third is consistent with §3.1 — it
   constrains **offline** admission, which already requires a manifest by construction, and does not touch
   online admission, which §3.1 rules must never be gated on the manifest.
4. Screenshot resale is **not** closed by any of this and must not be described as closed. It is bounded by
   first-in-wins plus the fraud queue (C41, RPC §9.4) — the ratified position — and the freeze makes it the
   only remaining resale channel for a frozen session, so the fraud queue should expect it.

*What is genuinely given up:* the defence-in-depth layer their §5.3 names, honestly. I accept the trade because
item 1 converts it from "a shorter clock" into "the same clock the offline door already runs on."

**Owner sign-off is still required** — this relaxes a constraint recorded in a ratified document, and the
Wallet spec was right to refuse to settle it alone.

**OQ-6 — Is `record_scan` required to take the session `FOR SHARE`?**
Not needed for the theorem (scans do not move custody). It is *recommended* so a scan's recorded
`manifest_id` is provably the live episode rather than a racing one. Cost: scans briefly block during
open/close (milliseconds, twice a night). Recommend yes. **Implementer/owner preference.**

**OQ-8 — Should the C25 compensate branch void the seller's atom at all? (surfaced, not resolved.)**
§5.4's only unelevated residual exists because `sweep_paid_pending_sales`'s compensate branch calls
`void_ticket_atom` (RPC §12.3), killing the **seller's** ticket because a **buyer's** resale failed to
complete. Refunding the buyer and merely unlocking the seller's atom would remove the residual entirely and
looks more correct on its face. **I have not changed it:** it is ratified behaviour in a document I do not own,
D2 makes `voided` the only money-reversal terminal, and the change would ripple into the C26 terminal state
machine. Flagged for whoever owns RPC §12.3. If it is changed, §5.4's third row and failure #22 disappear.

**OQ-7 — Manifest signing. RESOLVED on the auth model (edge `EDGE-2`); the signing recommendation stands.**
§7.5 returns the manifest from a DB read RPC. Edge §5.4 signs the *key* manifest (M1) with a KMS manifest key.
For parity the ticket manifest (M2) should also be signed — a `NEW EDGE FUNCTION` `door-manifest` that calls
`venue.get_door_manifest`, KMS-signs `{manifest_id, manifest_version, session_id, not_after, manifest_digest}`,
and returns the artifact. The signature is deterministic over the digest, so re-signing is free and needs no
stored signature and no unsigned window. **Recommend building it**; the TLS-only fallback is acceptable for
MVP if KMS budget is constrained — noting that M2's *integrity* then rests on transport alone while M1's does
not. Marked `NEW EDGE FUNCTION` (optional). **Package `086`.**

**What this open question left unstated, and how the edge spec closed it.** This section specified the
function's behaviour and payload but named **no `verify_jwt` value and no env list**, while
`venue.get_door_manifest` authorizes on *either* a staff role *or* a valid non-expired `venue.door_pin` bound
to the session (§11 EXEC table). Edge §3.9b first read that as **two routes with two `verify_jwt` values** —
staff at `true`, PIN at `false`. `verify_jwt` is a per-**function** Supabase setting fixed at deploy time, so
one function cannot hold two, and the permissive resolution is forbidden outright because the staff route's
authority **is** a human JWT.

**Resolved: `door-manifest` is a single staff-JWT route at `verify_jwt: true`, and the PIN route is DELETED —
not split into a second function.** Two independent reasons, and the second is the one that matters here:

1. **It was redundant.** `door-session` (edge §3.9a) already exposes **`/manifest/sync`** as a relay route
   wrapping `venue.get_door_manifest`, already at `verify_jwt: false`, already gated on
   `kernel.assert_door_session` on **every** call. The door's manifest fetch already had a home; the PIN route
   was a **second, weaker door to the same room**. Net effect on the edge spec's `verify_jwt=false` budget is
   **zero** — the door's unauthenticated traffic moves onto a surface already enumerated.
2. **It was weaker in exactly the way `AUTHZ-H3` was raised about.** The deleted route authorized on *"a valid
   non-expired `venue.door_pin` bound to the session"* — a **provisioning** fact, not a possession one.
   `venue.door_pin` has **no device column** (schema §3.10), so the check was satisfied by *any* live PIN for
   that session, including one issued to a different device, and it consulted **nothing the requesting device
   actually holds**. §3.9a fixed precisely this for `/scan`, `/offline-batch` and `/manifest/sync` by requiring
   possession of the door session token (H-3). Keeping the PIN route would have **reintroduced the
   provisioning-not-possession gate one section after closing it — on the artifact that tells the door which
   tickets to admit.** A route deleted is a route that cannot drift back.

> **CORRECTED 2026-08-28 (`DL-X3`).** The paragraph below said *"the RPC is unchanged … §11's EXEC row stands
> as written"*, quoting a PIN arm. **RLS §11.4 no longer contains that arm** — it now reads
> `has_venue_role(venue,[venue_scanner, venue_manager])` OR the `service_role` edge path with
> `assert_door_session` **asserted with a token** and bound to that session (`AUTHZ-H3`). The reachability
> argument below is right and is kept; the claim that the predicate was left intact is not. **Deleting the
> route while leaving the arm in the predicate is exactly the "reachable only by convention" posture
> `AUTHZ-H3` was raised against** — a route deleted cannot drift back, but an arm left in the predicate can be
> re-exposed by the next function that reads the predicate and builds to it.

**The RPC's predicate changed too, and that is the stronger fix.** `venue.get_door_manifest` **no longer has a
PIN branch**: RLS §11.4 replaced it with the token-bound `service_role` edge path under
`kernel.assert_door_session`. The reachability argument still holds and is what makes the change safe to
land — the door's manifest fetch is reachable **only** through `door-session` `/manifest/sync`, behind that
assertion. **No edge function exposes it on a PIN alone**, and none may — an edge that authorized the manifest
on a PIN by itself would re-open H-3 on M2 regardless of which function it lived in — **and now none can,
because there is no longer a predicate arm for it to satisfy.**

**Status.** Edge §9 recon #9 filed this to the door-spec owner as *"door-spec owner to confirm."* **This
section adopts the resolution** rather than re-litigating it, and records it here because OQ-7 is where an
implementer looks for this function's auth model and would otherwise find the silence that produced the
two-value reading. **`OWNER DECISION — RECORDED, NOT MADE`:** the adoption is an editorial reconciliation of
two documents that already agree on the mechanism; the *ratification* of the deletion is the owner's, and it
is cheap to rule on because the change **removes** an authorization surface and adds none. Nothing further is
owed by any other owner on this item.

---

## 17. Change-class index

| Element | Class |
|---|---|
| `venue.open_door_manifest` | `NEW RPC` |
| `venue.close_door_manifest` | `NEW RPC` |
| `catalog.engage_door_freeze` (definer-only) | `NEW RPC` |
| `venue.get_door_manifest` | `NEW RPC` |
| `venue.append_door_manifest_delta` (definer-only) | `NEW RPC` (§7.7 — DL-1) |
| `catalog.effective_freeze_at` | `NEW RPC` |
| `kernel.grant_door_freeze_override` / `revoke_door_freeze_override` | `NEW RPC` |
| `kernel.sweep_expired_door_overrides` | `NEW RPC` |
| `catalog.sweep_implicit_door_freezes` | `NEW RPC` |
| `door-manifest` (signed manifest distribution) — **single staff-JWT route, `verify_jwt: true`; the PIN route is DELETED (edge `EDGE-2`)** | `NEW EDGE FUNCTION` (optional, OQ-7) |
| `venue.get_door_manifest`'s PIN branch reachable **only** via `door-session` `/manifest/sync` behind `kernel.assert_door_session` | `SPEC CORRECTION` (§16 OQ-7 → edge §3.9a/§3.9b) — **RPC unchanged; reachability narrowed** |
| `venue.door_manifest` | `ADDITIVE SCHEMA CHANGE` |
| `venue.door_manifest_entry` | `ADDITIVE SCHEMA CHANGE` |
| `venue.door_manifest_entry.resale_state` + snapshot completeness | `SPEC CORRECTION` (§9.2 — DL-5) |
| `venue.door_manifest_delta` | `ADDITIVE SCHEMA CHANGE` (§10.3a — DL-1) |
| `venue.door_manifest.max_delta_seq` | `ADDITIVE SCHEMA CHANGE` |
| `kernel.door_freeze_override` | `ADDITIVE SCHEMA CHANGE` |
| `venue.scan.manifest_id` · `venue.scan_device.manifest_id` | `ADDITIVE SCHEMA CHANGE` (recommended) |
| four `catalog.platform_config` seed keys | `ADDITIVE SCHEMA CHANGE` (rows) |
| three `door.session_*` config seed keys (§10.6) | `ADDITIVE SCHEMA CHANGE` (rows) — H-3 |
| `venue.door_manifest_delta` CHECK `(op='add') ⇒ signing_key_id IS NOT NULL` (§10.3a) | `ADDITIVE` (constraint) — H-2/3c |
| Offline predicate stated once as `OFFLINE-VERIFY-v1` in edge §5.4.3; §9.2 is a verbatim mirror | `SPEC CORRECTION` (§9.2 — **H-2**) |
| **`get_door_manifest`'s result shape reconciled with RPC §20.6.1 to one wire shape; `resale_state` added to the entry projection, `session_id` to the header, the full entry payload to the `op='add'` delta** | **`SPEC CORRECTION` (§7.5/§7.5a — `MP-1`)** |
| **The atomic open's snapshot INSERT list gains `resale_state` + `ticket_type_id`** — the *writer* omitted a column §10.3 declares `not null` | **`SPEC CORRECTION` (§6 step 7 — `MP-1`)** |
| **The §7.5a projection superset rule + pgTAP group **P** (assertions 77–83)** | **`SPEC CORRECTION` (§7.5a — `MP-1`)** |
| **`p_since_version` / `p_since_seq` / `p_since_delta_seq` unified to `p_since_delta_seq`** | **`SPEC CORRECTION` (§7.5, §7.7, §15 #69 — `MP-1`)** |
| **`no_open_manifest` and `{open:false}` reconciled — both keys returned** | **`SPEC CORRECTION` (§7.5 — `MP-1`)** |
| **`venue.door_manifest_entry.ticket_type_id`** (RPC §20.6.1 projected a column the table did not carry) | **`ADDITIVE SCHEMA CHANGE` (§10.3 — `MP-1`)** |
| **`venue.door_manifest_delta.ticket_state` · `.resale_state` · `.ticket_type_id` + the five `op='add'` CHECKs** | **`ADDITIVE SCHEMA CHANGE` (§10.3a — `MP-1`)** |
| `refund_hold` reject arm + operator copy (§9.2, §11.2) | `SPEC CORRECTION` (Finding-7 residual) |
| `exp` clamp on the **computed** value; §10.6's constants invariant demoted to necessary-not-sufficient | `SPEC CORRECTION` (§10.6 → Wallet §5.2a) |
| `kernel.revoke_signing_key` force-closes open episodes (OQ-5 grant condition 2 — mechanism existed, caller did not) | `SPEC CORRECTION` (§16 OQ-5 → edge §5.6) |
| **`venue.door_session`** (H-3 — the bearer artifact the door actually holds) | **`ADDITIVE SCHEMA CHANGE` — reported to the schema/plan owners, specified in edge §3.9a** |
| `catalog.event_session.door_open_at` triggers + CHECK | `ADDITIVE SCHEMA CHANGE` (constraints only) |
| `catalog.event_session.door_open_at` column itself | `NO SCHEMA CHANGE` |
| `kernel.is_transfer_frozen` signature + all call sites | `NO SCHEMA CHANGE` |
| `kernel.is_transfer_frozen` body (effective boundary + override) | `SPEC CORRECTION` |
| Remove `mark_ticket_scanned` from the recheck set | `SPEC CORRECTION` (§13.1) |
| Add `transfer_ticket_ownership` · `accept_p2p_transfer` · routine `void_ticket_atom` to the recheck set | `SPEC CORRECTION` (§13.2) |
| Offline verify step 3b (`credential_version`) | `SPEC CORRECTION` (§13.3) |
| C25 sweep: complete frozen, compensate exempt | `SPEC CORRECTION` (§13.4) |
| Drain of in-flight p2p / listings at open | `SPEC CORRECTION` (§13.5 / §7.3) |
| Session `FOR SHARE` gate in custody RPCs | `SPEC CORRECTION` (§5.1) |
| `venue_scanner` (ex-`venue_door`) removed from VD Δ1's proposed role set | `SPEC CORRECTION` (§4) |
| Abolished `venue_door` label + bare `door_pin` arm purged from §4/§4.1/§4.2/§7.1/§7.2/§7.5/§10.1/§10A.1/§10A.2/**§10A.7**/§15/§16 | `SPEC CORRECTION` (§20 — `DL-X1`…`DL-X4`) |
| `starts_at`/`doors_at` edits rejected once engaged | `SPEC CORRECTION` (§10.2) |
| M1/M2 manifest disambiguation | `SPEC CORRECTION` (§9.1) |
| Domain events 37–44 | `ADDITIVE` (envelope) |
| Door Safety Theorem restated over **custody**, not `credential_version` | `SPEC CORRECTION` (§5.3–§5.4 — my own error) |
| `catalog.cancel_event` force-closes open episodes | `SPEC CORRECTION` (§7.2.1 — DL-2) |
| Break-glass forces invalidation + live-device acknowledgement | `SPEC CORRECTION` (§8.2.1 — DL-3) |
| Exempt voids must write a `revoke` delta | `SPEC CORRECTION` (§7.6) |
| Offline reject-reason mapping to the five VD §12.5 reasons | `SPEC CORRECTION` (§9.2 — DL-5) |
| Wallet/manifest cross-config invariant | `SPEC CORRECTION` (§10.6 — DL-4) |
| Key revocation force-closes an open episode | `SPEC CORRECTION` (§16 OQ-5 item 2 — DL-4) |
| OQ-5 replaced by a ruling | `SPEC CORRECTION` (§16 — DL-4) |
| six `kernel.admin_audit` action names | `NO SCHEMA CHANGE` |
| RLS matrices for the three new tables (§10A.1–§10A.3) | `ADDITIVE` (new matrices) |
| RLS §8.3 notes 19 / 19b — `door_open_at` unreachable from any EXEC row | `SPEC CORRECTION` (§10A.4) |
| RLS §11 EXECUTE-authority rows for the seven new RPCs | `ADDITIVE` (§10A.7) |
| Dashboard manifest control · freeze-status card · episode history · session-card copy | `NEW DASHBOARD SURFACE` |
| Scanner `awaiting_manifest` state · manifest status row | `NEW RN SURFACE` |
| Drain notifications | `NEW RN SURFACE` |
| Consumer Transfer/Sell gating + copy | `NO CHANGE` |
| `kernel.tickets`, `kernel.ticket_ownership_log`, `market.*`, `public.*` | `NO SCHEMA CHANGE` |
| SSCAS membership | `NO CHANGE` — set stays closed at fifteen (§5.2) |

---

## 18. Ratified-invariant conformance

| Invariant | Interaction | Verdict |
|---|---|---|
| **Ticket atom** | untouched — no column added, no state added | ✔ preserved |
| **Append-only ownership log** | the freeze gates *writes*; the drain appends nothing | ✔ preserved |
| **Single transfer engine** | **strengthened** — the freeze is enforced in `transfer_ticket_ownership`, so no path bypasses it | ✔ reinforced |
| **Credential-as-delivery** | **strengthened** — the manifest pins `credential_version`, making the offline door able to honour the credential's currency | ✔ reinforced |
| **Two-rail honesty** | the freeze binds native custody only; `public.transfers` / `public.listings` are untouched — an external-rail transfer is not a custody move of an atom | ✔ preserved |
| **Modular monolith** | `venue.*` never writes `catalog.*` directly; `catalog.engage_door_freeze` is the owning schema's definer primitive, mirroring `record_scan → mark_ticket_scanned` | ✔ preserved |
| **Frozen Stripe core** | no `public.payments` column, no fee-application change, no new charge path | ✔ preserved |
| **SSCAS membership + global lock ordering** | open/close are single-aggregate (Event/Session); the drain is a bounded batch of existing members #6-/#7-reverse; `cancel_event`'s episode close (§7.2.1) is a same-aggregate write under the Event/Session lock it already holds; `append_door_manifest_delta` (§7.7) takes no lock of its own and writes one aggregate class; the session gate is rank 1, the lowest, so every prefixed sequence stays ascending (§5.1 proof table) | ✔ preserved, **no sixteenth member** |
| **Event envelope** | six new events, all carrying `sequence`/`causation_id`/`correlation_id`, all with dedup keys | ✔ preserved |
| **Server-authoritative money/custody** | no client timestamp, no client actor, no client-writable path to `door_open_at` | ✔ preserved |
| **C6** (offline door = reconcile window + transfer freeze) | this document is C6's missing writer | ✔ implemented |
| **C23** (ordered offline reconciliation; freeze covers refund-voids) | routine refund-void frozen (§7.6); the three **exempt** voids now write a `revoke` delta so a synced device drops the atom (§7.7); `manifest_id` on scan/device makes reconciliation joinable (§10.5) | ✔ implemented |
| **C37** (live authoritative per-scan read online; offline honestly shrunk) | the manifest gates **offline only**; the online path is untouched; §5.3's corollary shrinks the offline **custody** window to the audited break-glass residual, and §5.4 states the **revocation** residual the corollary does *not* cover — including the one unelevated path (C25 compensate). Four residuals are named in §14 #19–#22 rather than claimed closed | ✔ preserved, claim still honest — **and now honest in one more dimension than before** |
| **C41** (no re-entry; `scanned` terminal; `direction` hedge) | close does not resurrect a terminal atom; the drain does not touch `state`; first-in-wins asserted under freeze (pgTAP 38) | ✔ preserved |
| **C43** (p2p hard TTL; cancel-to-self exempt; per-open-manifest narrowing) | the drain uses **only** the ratified cancel-to-self exemption; the TTL sweep is unchanged; the narrowing is a Gate-M additive conjunct with a physical home ready (OQ-4) | ✔ preserved |

**No ratified invariant is violated by this design, and none had to be bent.** The three places where the
frozen specs were internally inconsistent (§13.1, §13.2, §13.4) are corrected *toward* the invariants, not away
from them.

---

## 19. Disposition of the Apple Wallet spec's requests (DL-1 … DL-6)

`PHASE_2_APPLE_WALLET_SPEC.md` §14 raised six changes against this document. All six are answered; four are
accepted as stated, one is accepted with a different and better fix, one is granted with a corrected rationale.
**One further defect — mine — was found while checking their proof (§5.4).**

| ID | Sev | Disposition | Where |
|:-:|:-:|---|---|
| **DL-1** post-open issuance invisible to offline scanners | HIGH | **ACCEPTED IN FULL.** Real, and correctly absent from my §14. Their safety argument — a newly minted atom has `credential_version = 0`, has never been transferred, and cannot be transferred while frozen, so it can strand nobody — is sound; I checked it and made it structural as a `CHECK` (pgTAP 65). Implemented as a **delta log** rather than an "append-only supplement", so the same mechanism also carries `revoke` and closes §5.4 | §7.7 · §10.3a · §14 #19 |
| **DL-2** `cancel_event` must close open episodes | HIGH | **ACCEPTED IN FULL.** My §14 #11 covered only the online path; an offline scanner would keep admitting into a cancelled show. Their diagnosis is exactly right. Added force-close + `not_after := now()` + `revoke` deltas + `DoorManifestInvalidated`, with the never-reconnects residual stated rather than glossed | §7.2.1 · §14 #20 |
| **DL-3** mandatory re-sync after break-glass | MED | **ACCEPTED, STRENGTHENED, AND ITS FRAMING CORRECTED.** Re-sync is necessary and **not sufficient** — an offline device cannot be made to re-sync, and setting `not_after := now()` server-side does not shorten the `not_after` the device already downloaded. Replaced with force-close + invalidate + push + a **live-device acknowledgement** the admin must pass before the override is permitted, and the residual bounded honestly | §8.2.1 · §14 #21 |
| **DL-4** amend OQ-5 for a session-bounded wallet token | BLOCKING | **GRANTED — outcome accepted, rationale rejected, bound tightened.** Their §5.3 claim that the short TTL "bounds nothing that isn't already bounded" is too strong in two rows of their own threat table (screenshot resale; revoked-key window). Granted anyway, because a short-TTL Wallet barcode locks out fans in dead zones — the §13.1 class. Made *safe* rather than *asserted* by a cross-config invariant binding the token to the manifest TTL, plus a new requirement that key revocation force-close the episode. **Without that second item I would have rejected it.** Owner sign-off still required | §16 OQ-5 · §10.6 |
| **DL-5** reject-reason vocabulary | LOW | **PROBLEM ACCEPTED; PROPOSED FIX DECLINED.** A new `not_admissible` reason treats the symptom. The cause was my §10.3 excluding terminal atoms from the snapshot, which overloaded "absent from M2" with two meanings. Fixed at the cause: **M2 is now complete** and every reject maps onto the five reasons VD §12.5 already publishes — zero new vocabulary. This also closed a hole neither spec had flagged: a `paid_pending_transfer` atom would have been admitted offline and refused online | §9.2 · §10.3 |
| **DL-6** §9.4 "not built in Phase 2" is stale | LOW | **ACCEPTED IN FULL** | §9.4 · §16 OQ-5 |

### 19.1 The confirmation the Wallet proof asked for — and the correction it exposed

Their §4.3(a) rests on: *`door_open_at = MIN(opened_at)` is monotone and terminal, therefore no transfer can
commit at or after the first open, therefore an older episode's manifest carries identical `credential_version`
values.*

- **The custody half is CONFIRMED, unconditionally.** `effective_freeze_at <= door_open_at` forever, close does
  not clear it, re-open does not move it — so no custody move for any atom of the session can commit at any
  instant ≥ the first open, and every episode's snapshot records the same owner and version for every atom
  that remains admissible. Their stale-manifest denial for a **transfer** stands exactly as written.
- **The `credential_version` half is NOT unconditionally true, and the error was mine.** My theorem originally
  quantified over "every RPC that can bump `credential_version`", which my own §13.4 falsifies: the C25
  compensate branch is exempt and `void_ticket_atom` bumps the version. The theorem is now stated over
  **custody moves** (§5.3) and the three exempt voiding paths are enumerated (§5.4).
- **Consequence for their document:** their §4.3 residual list names the override and platform force-void.
  It must also name the **C25 compensate branch** — the only residual that fires with no human involved. Its
  severity is lower than theirs (a refunded ticket admitted offline: revenue, not custody — no second person is
  admitted and the wrong owner never is), and §7.7's `revoke` delta now bounds it for any device that syncs.
  **Their scenarios 1, 2 and 4 are unaffected.** I have not edited their spec.

---

## 20. Correction index — reviewer-conditions pass (2026-08-28)

An adversarial review of the Phase 2 corpus taken at `cbf8926` filed this file's **abolished-label and
door-PIN residue** as its **condition 4**. Verification confirmed it and found it wider than filed.

| ID | Defect | Where | Fix |
|---|---|---|---|
| **`DL-X1`** | The **abolished** label `venue_door` — renamed `venue_scanner` by O-2 / ROLE_MODEL §4.5 / schema §0.6 / RLS §2.1 — survived in predicates, matrices, deny-lists and assertions | §4, §4.2, §7.1, §7.2, §10.1, §10A.1, §10A.2, §15 | Renamed to `venue_scanner` throughout; deny-lists rebuilt on the **six** canonical venue labels |
| **`DL-X2`** | §4.1 and §16 OQ-3 argued from a **four-label** venue enum with no box-office label, and offered "a fifth enum label" as a remedy. **`venue_box_office` exists** and RLS §11.4 already excludes it | §4.1, §16 OQ-3 | Premise corrected; conclusion **unchanged and still correct**; the open question restated as the narrower grant-hygiene problem (VD Δ8), with the schema half **closed** |
| **`DL-X3`** | The **provisioning-not-possession** door-PIN arm closed by `AUTHZ-H3` survived as a first-class `OR` arm of the `venue.get_door_manifest` predicate — including in **§10A.7, a table titled "additions to RLS §11" that contradicted RLS §11.4**. §16 OQ-7 separately asserted *"the RPC is unchanged … §11's EXEC row stands as written"*, which is no longer true | §4, §4.2, §7.5, §10A.1, **§10A.7**, §15, §16 OQ-7 | Arm deleted; rows copied from RLS §11.4 rather than re-derived; token-bound `kernel.assert_door_session` form stated everywhere |
| **`DL-X4`** | **The structural gap.** `T-RLS-EXEC-02` — *"no label in any §11 predicate is outside the fifteen canonical labels of §2.1"* — is the assertion designed to catch exactly `DL-X1`, and it caught nothing here | §15 (new assertion 25a) | Assertion added over **this document's** predicates |

### 20.1 Why the authority was right and this file was wrong — and why that is the dangerous direction

**Nothing above is a defect in the authority.** RLS §11.4 and `PHASE_2_EDGE_FUNCTION_SPEC.md` both carried the
corrected, token-bound, `venue_scanner` form throughout. Rule **`EXEC-DERIVED`** (RLS §11.0) already says that
where this file and RLS §11 disagree, **RLS §11 governs and this file is the defect**. That rule was in force
and the disagreement still persisted for a full remediation cycle.

**A door implementer does not read RLS §11.4. They read this file** — it is the document named "door
lifecycle", it contains the RPC contracts, and its §10A.7 advertises itself as *the* EXECUTE-authority table
for the door. A stale predicate here is not a documentation inconsistency waiting for a reconciliation pass;
it is **build instructions**. The `door_pin` arm in particular was code-shaped — an `OR` clause an implementer
transcribes — while the caveat that it must not be reachable sat in prose *after* it. **A caveat is not a
predicate**, and the implementer who writes the `OR` and skips the paragraph has re-opened `AUTHZ-H3` on the
artifact that tells the door which tickets to admit.

### 20.2 `T-RLS-EXEC-02` is scoped to RLS §11 and cannot see this file — `DL-X4`

`T-RLS-EXEC-02` is stated in RLS §11.0 as: *"No label appearing in a §11 predicate may be absent from the
fifteen canonical labels of §2.1."* Its subject is **§11 of the RLS spec**. Every occurrence of `venue_door`
corrected above lives in **this** document, in predicates that are *downstream copies* of §11 rows rather than
§11 rows themselves. The assertion is not weak here — **it is not evaluated here at all.**

This is the same defect class as the `T-RLS-EXEC-02` guard's own origin story: ROLE_MODEL edit `R-14` renamed
`venue_door → venue_scanner` **lexically** across RLS §11, and nothing in the corpus could tell a lexical
rename from a re-derivation. The guard was added so §11 could tell the difference. **It was scoped to the one
table that had already been fixed, and not to the downstream copies that had not.** A guard that covers only
the site of the last incident is a guard against the last incident.

**Assertion `25a` (§15) closes the gap for this file.** The general form — enforcing the canonical-label set
over **every** predicate in `docs/architecture/**` rather than over RLS §11 alone — is a corpus-wide change
that belongs with the CI-gate owner, and is filed as `DL-X4` rather than made here. It is the same shape as
the `OFFLINE-VERIFY-v1` byte-identity gate: a property currently held by review, buildable as a scan.

### 20.3 What did NOT change

No RPC signature, no table, no column, no state machine, no lock order, no invariant, no theorem, no package
number, and **no `OFFLINE-VERIFY-v1` block** (§9.2 is a sanctioned byte-identical mirror and is untouched).
Every fix above either replaces an abolished label with its ratified successor or deletes an authorization arm
that the ratified authority had already deleted. **Every change narrows authority or leaves it unchanged;
none widens it.**

---

## 21. Requests to sibling owners — recorded 2026-08-28 (`R3-5`), not applied here

The register-integrity pass rewrote §15 assertions **77** and **78** (`T-DOOR-PROJ-01`/`-02`). Three
consequences land in documents this file does not own. **Nothing below is edited by this pass**; each is
carried in ratification row **`C134`**.

| # | To | What | Why it cannot be done here |
|---|---|---|---|
| **`DR-1`** | **RPC owner** — `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §18 (door set-closure row) and §20.6.1 | **`T-RPC-DOOR-33`/`-34` is the twin of assertions 77/78 and still carries the superseded wording.** §18 reads *"with `-34` deriving the compared read set **from the fenced block** so `-33` cannot pass against a stale hard-coded list"*, and §20.6.1 states the same. That is the half of the old pair that **contradicted** the other half: 77 compared against a hard-coded set, 78 said the set was derived, and **78's concrete rule — *"fail if that parse yields fewer than five distinct fields"* — is unsatisfiable against a correct fence, which yields four `M2[atom].<field>` references.** Bring `-33`/`-34` into line with the rewritten 77/78: one literal enumeration (**`MP1-READ-SET`**, §7.5a), 77/`-33` consuming it, 78/`-34` asserting **set equality** between it and the block across **four** extraction patterns, with the four-part non-vacuity guard. **Do not edit any `OFFLINE-VERIFY-v1` block to satisfy it** — the block is correct; the assertion was wrong | the RPC contracts are another owner's file, and a one-sided edit would leave the two twins disagreeing in a new way rather than the old one |
| **`DR-2`** | **RPC owner** · **schema owner** · **RLS owner (this pass)** | **State each register's own cross-scheme aliases.** The `MP-1` pair carries **three** names — ordinal `77`/`78`, `T-DOOR-PROJ-01`/`-02`, `T-RPC-DOOR-33`/`-34` — and nothing declared the aliasing, so a second name is indistinguishable from a second assertion. §15's preamble now declares it **from this side only**. The sibling ids (`T-RPC-DOOR-*`, `T-SCHEMA-DOOR-30`…`-35`, `T-RLS-DOOR-11`…`-13`) should each declare theirs, with `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` §9 holding the join | an alias inventory written from one side is a fourth copy of a mapping and goes stale exactly as `C84` describes |
| **`DR-3`** | **RPC owner** — §18 `G-23` | **`G-23`'s closure claim is false and is reported in full in ratification row `D35`.** It reads *"every suffix above is written as a full id, so a harness grepping for `T-RPC-` finds all of them"*, while the row immediately above it writes `T-RPC-ROLE-02/-03/-04/-05` as bare suffixes — and those four are cited **by name 17 times across five documents** | §18 is the RPC owner's register |

---

*End of `docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md`. Design-only; no SQL files, no migrations, no
implementation code. Delta on the Phase-2 implementation specs; closes venue-dashboard Δ1 and §22.7, gives
`catalog.event_session.door_open_at` the writer it never had, and answers `PHASE_2_APPLE_WALLET_SPEC.md`
§14 (DL-1 … DL-6) in §19. The abolished `venue_door` label and the `AUTHZ-H3` door-PIN arm are purged in §20
(`DL-X1`…`DL-X4`); where this file and `PHASE_2_RLS_PERMISSION_SPEC.md` §11 disagree, §11 governs and this
file is the defect (rule `EXEC-DERIVED`). §15 assertions 77/78 were rewritten by the register-integrity pass
(`R3-5`) and the three consequences for sibling owners are filed in §21.*
