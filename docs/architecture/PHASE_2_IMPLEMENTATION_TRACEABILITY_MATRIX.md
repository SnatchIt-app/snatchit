# Phase 2 — Implementation Traceability Matrix

**Status:** completeness instrument. Design-only. **Creates no SQL, no migration, no code, and edits no other file.**
**Baseline:** `phase2/consolidation` @ `64d2aac` — after all four integration passes (schema+plan, RLS+RPC, edge+RN+dashboard, constitutions+rulings).
**Authority:** none. This document *decides* nothing. It records where the corpus does and does not close, and names the spec that owes each fix.

---

## 0. What this document is for, and how to read a cell

> **The purpose is to prevent implementation from silently omitting a backend or security component.**

For every major Phase-2 capability this matrix maps:

`PRODUCT REQUIREMENT → ARCHITECTURE INVARIANT → TABLE → RPC → RLS → EDGE FUNCTION → RN/DASHBOARD SURFACE → EVENT → TEST → MIGRATION PACKAGE`

**The value of this instrument is entirely in the cells that are empty.** A capability with a dashboard
surface and no RLS row, an RPC with no test, a table with no package, an event nothing consumes — those are
the findings. A full row proves nothing that the source specs did not already prove.

### 0.1 Cell vocabulary — this is binding

| Marker | Meaning |
|---|---|
| a named artifact | **VERIFIED** — the named object exists in the cited spec at this baseline. Every artifact name in this document was read out of a spec, not invented. |
| **`—`** | **Genuinely not applicable.** Every `—` in this document carries a justification in the row's `why —` line. A `—` with no justification is a defect in *this* document. |
| **`GAP`** | A cell that **should** be filled and is not. Every `GAP` is registered in §1 with a severity and an owning spec. |
| **`COND`** | The cell's artifact is specified but its **carrier is not scheduled**. Distinct from `GAP`: the design exists, the transport does not. All `COND` cells are registered in §2. |
| `INFERENCE:` | A statement this document derives rather than cites. Everything not so marked is a citation. |

### 0.2 The one rule that keeps this honest

**A `—` used to hide a `GAP` defeats the instrument.** Where a cell is empty because the corpus never
addressed it, that is `GAP`, not `—`. `—` is reserved for cells where a *positive design decision* makes
the artifact inapplicable (a definer-only RPC has no RLS policy **by construction**, per RLS GP-3a; a
read-only surface emits no event).

### 0.3 The three structural facts that shape every row

1. **There are no write policies.** RPC §0.8 / RLS GP-3a: every Phase-2 write RPC is `SECURITY DEFINER`, so a
   table policy on the objects it writes **never runs**. The `RLS` column therefore holds a *read* policy name
   from RLS §16.10, or an **EXEC row** from RLS §11, or `—` (deny-all by design). An implementer who writes
   policies for the money or custody tables produces policies that are never evaluated **and believes they are
   protected** — RPC §19 names this as the single most likely way to build Phase 2 wrong.
2. **Every `EVENT` cell is conditional.** `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.3 promises *"one outbox table
   and a drainer on the cron that already runs"*; **no implementation spec schedules one** (ratified row
   **C51**, open decision **O7**, registry **COND-A**). The 36-event catalog in DA §6.1 has producers and
   consumers named and **no carrier**. Cells are marked `COND-A` rather than filled.
3. **`notify` has no package.** Ratified row **C7** places it at Gate P / MVP; all four implementation specs
   place it at Gate L / do-not-build (row **C52**, decision **O8**, registry **COND-B**). Its nine tables, 23
   RPCs, two crons and two edge functions are specified and unscheduled.

---

## 1. GAP REGISTER — every empty cell that should be full, most severe first

**Severity scale.** `S1` = a capability cannot be built as specified, or a security/money component is
missing. `S2` = a surface has authority but no signature (an implementer has permission and no contract).
`S3` = a naming or coverage divergence that will produce two objects, or none.

| # | Sev | The hole | Where it should be | Owning spec (owes the fix) | Cell |
|---|:--:|---|---|---|---|
| **G-1** | **S1** | **The event outbox is promised by the constitution and scheduled by no package.** Every eventual-consistency flow, CDM C12's whole event envelope, the Apple Wallet push path, the door-manifest open transaction and scanner push-to-sync are unimplementable as specified without it. | `076` (COND-A: zero FK deps, so no producer package gains an edge) | **Owner ruling O7** (row C51). Then `PHASE_2_PACKAGE_REGISTRY.md` §7 + `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 COND-A | `EVENT` (all rows) |
| **G-2** | **S1** | **The `notify` schema has no package** — 9 tables, 23 RPCs, 2 cron jobs, 2 edge functions (`notify-dispatch`, `notify-receipts`). Edge §8 assigns them `076+`ᵃ, which is not a package number. | `092` if Gate P (count becomes 17, falsifying the registry's "no gaps, no duplicates" assertion) | **Owner ruling O8** (row C52). Then registry §7 COND-B | `PACKAGE` |
| **G-3** | **S1** | **`kernel.set_org_connect_ref` is wrapped by an edge function and contracted nowhere** — it appears in neither `PHASE_2_RPC_FUNCTION_CONTRACTS.md` nor RLS §11's EXEC table. `connect-onboarding` (edge §3.3) therefore **has no write path**, and Stripe Connect onboarding — the precondition for every payout — cannot complete. | RPC contracts §2 (organization); RLS §11.1 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** (edge §9 recon #12 already files the request) | `RPC`, `RLS` |
| **G-4** | **S1** | **`venue.allocate_comp` and `venue.issue_comp` have an EXEC row and no contract.** RLS §11.1 gives them a fully argued split authority model (R-15/E6/E7, C39 step-up gating, `venue_box_office` denied on allocate and permitted on issue) — and the RPC contracts document contracts neither. Dashboard §20A.1 lists them under *"mapped — write controls with a named RPC"*, which is **wrong**: the name exists, the contract does not. | RPC contracts §5 or §9 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`**; and dashboard §20A.1 should move the row to §20A.2 | `RPC` |
| **G-5** | **S1** | **The entire native-marketplace write surface is authorized and uncontracted.** RLS §11.1 carries EXEC rows for `market.create_listing`, `cancel_listing`, `create_auction`, **"bid RPC"** (literally unnamed), `make_offer` and `respond_offer`. The RPC contracts document contracts **none** of the six; its §8 covers p2p only. Package `088` creates `market.listing_native`, `auction` and `offer` — tables whose only writers are these uncontracted functions. | RPC contracts (a new section beside §8) | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `RPC` |
| **G-6** | **S1** | **`catalog.set_platform_config` is uncontracted** — while RLS §11.3 makes it the *mandatory dual-control* writer for every `refund.*` / `payout.*` / `authn.*` key, creating a `kernel.approval_request` a second `platform_admin` must approve, with a direction asymmetry (lowering executes, raising needs the approver). **Every money threshold in the system is set through a function with no signature.** | RPC contracts §11 (admin) | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `RPC` |
| **G-7** | **S1** | **`kernel.admin_refund`, `kernel.pay_promoter_commission` and `kernel.provision/rotate/revoke_signing_key` are uncontracted.** All have EXEC rows (RLS §11.1); `refund-execute` (edge §3.5) and `signing-key-provision` (edge §3.6) wrap them. The signing-key trio is the **C33 key-lifecycle surface — the security linchpin of the credential design.** | RPC contracts §11 (admin) | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `RPC` |
| **G-8** | **S1** | **No named behavioural test exists for the custody and money spine.** RPC §18's twelve groups are Door, Money, Role, Attribution, Promoter, Demographics, CRM, Wallet, Notify and Global. There is **no group** for `issue_ticket_atoms`, `transfer_ticket_ownership`, `void_ticket_atom`, `lock/unlock_ticket`, `create_primary_checkout`, `finalize_primary_order`, the three p2p RPCs, `open_settlement`, `close_settlement`, `cancel_event`, `force_void_ticket`, `hold/release_payout`, or either sweep. `T-RPC-GLOBAL-01..04` are **structural** assertions over `pg_proc` and prove nothing about behaviour. **The SSCAS members — the flows C26/C28 exist to protect — have no named test.** | RPC contracts §18 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `TEST` |
| **G-9** | **S2** | **`U-2` — "mark a guest arrived" has no RPC.** RLS §9.16 note 39 grants the door principal exactly this narrow update (`status` + `checked_in_at`); no function is named anywhere. **This is hit a thousand times a night by a door.** | RPC contracts (venue, door) | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** (dashboard §20A.3 U-2 filed it) | `RPC` |
| **G-10** | **S2** | **`U-1` — guest-list CRUD has no RPC.** RLS §9.16 says only *"guest-list CRUD RPCs"*. Three distinct writes (create list · add guest · remove entry), zero signatures. | RPC contracts (venue) | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `RPC` |
| **G-11** | **S2** | **`U-3`/`U-4` — promoter-record and promoter-link writes have no RPC.** RLS §9.17 says only *"promoter CRUD"*. The promoter spec contracts *code* RPCs and not promoter-record RPCs. `U-4` additionally needs a **live slug-availability read that does not exist** — the UI is required to check a global namespace against nothing. | RPC contracts §17.15–§17.19 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** / `PHASE_2_PROMOTER_CODES_SPEC.md` | `RPC` |
| **G-12** | **S2** | **`U-8`/`U-9`/`U-10` — the update half of catalog and org is missing.** No capacity-change RPC on an existing batch (`U-8`), no update RPC for `catalog.event` or `catalog.event_session` (`U-9`), no `kernel.update_organization` (`U-10`) though `catalog.update_venue` exists for the venue. **Creation is contracted; editing is not.** | RPC contracts §2, §4, §5 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `RPC` |
| **G-13** | **S2** | **`venue.grant_staff_role` / `revoke_staff_role` and `venue.register_scan_device` have EXEC rows and no contracts**, and the second half of that same EXEC row — *"manifest-sync"* — **is never given a name at all**. Granting a venue staff role is the primary authority-conferring write in the venue plane. | RPC contracts (venue) | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** (dashboard §20A.2 filed all three) | `RPC` |
| **G-14** | **S2** | **`venue.set_door_open_at` (O4-3) and `venue.set_event_security_config` (O4-4) have EXEC rows in RLS §11.4 and no contracts** — and `venue.set_door_open_at` **contradicts O-5**, which makes `catalog.engage_door_freeze` the *sole* writer of `door_open_at`, enforced by a trigger independent of grants. Either the EXEC row is stale or O-5's sole-writer property is false. | RLS §11.4 vs RPC §17.12 | **`PHASE_2_RLS_PERMISSION_SPEC.md`** (reconcile against O-5) | `RPC`, `RLS` |
| **G-15** | **S2** | **`venue.get_door_manifest` is uncontracted.** It has an EXEC row (RLS §11.4, dual-path: staff role OR `assert_door_session`), it is the DB-RPC wrapped by both the `door-manifest` and `door-session` edge functions, and it is the read that delivers **M2** to every scanner. No contract states its params, its result shape or its digest. | RPC contracts §17.10–§17.13 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `RPC` |
| **G-16** | **S2** | **`U-5` (Δ11) — the door-open blast-radius dry-run read does not exist.** Dashboard §12.4's confirm must show the pending transfers and active listings the drain will cancel **before** the confirm enables; the open RPC returns those counts only *after* it commits. **The most consequential door control in the product asks for a confirmation the operator cannot evaluate.** | door spec / RPC contracts | **`PHASE_2_DOOR_LIFECYCLE_SPEC.md`** | `RPC` |
| **G-17** | **S2** | **`U-6` (Δ12) — the live-device count read does not exist**, though the break-glass override requires the operator to acknowledge that exact number and the door spec says the dashboard shows it. | door spec / RPC contracts | **`PHASE_2_DOOR_LIFECYCLE_SPEC.md`** | `RPC` |
| **G-18** | **S2** | **`U-7` — `venue.get_dashboard_summary` was asked for by the dashboard and adopted by no delta spec.** Home degrades to N queries rather than failing, so this is the least severe of the ten. | dashboard Δ3 | **owner** (accept N queries, or schedule the RPC) | `RPC` |
| **G-19** | **S2** | **The `notification_preferences` toggles are read by no sender** — a live production defect. The Phase-2 design must not inherit it: `notify.channel_enabled` exists as a `DEF` RPC in RLS §11.7, but under **G-2** it has no package, so at MVP the preference surface (RN §6.1 item 8, dashboard §16.5) would again render toggles that gate nothing. | notifications spec §4 / the MVP carrier decision | **owner ruling O8**, then `PHASE_2_NOTIFICATIONS_SPEC.md` | `RPC`, `EDGE` |
| **G-20** | **S3** | **Six RPC names diverge between RLS §11 / dashboard §20A and the RPC contracts.** `grant_org_role`/`revoke_org_role` vs contracted `change_org_role`/`remove_org_member`; `catalog.set_venue_approval` vs `catalog.approve_venue`; `catalog.set_event_status` vs `catalog.publish_event`; `venue.record_offline_scans` vs `venue.reconcile_offline_scans`; plus `venue.set_ticket_type_price` and `catalog.set_resale_policy` (EXEC rows, no contract at all). **Two names for one function produces two functions or none.** | RLS §11.1 ↔ RPC §2/§3/§4/§5/§9 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** (canonical namer) | `RPC` |
| **G-21** | **S3** | **`catalog.sweep_implicit_door_freezes` has an EXEC row (RLS §11.4) and no contract**, while its sibling `kernel.sweep_expired_door_overrides` is contracted (RPC §17.11). RLS notes neither is load-bearing for correctness, which is why this is S3 and not S2. | RPC §17.11 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `RPC` |
| **G-22** | **S3** | **Test-id counts are stated as rows, not ids.** RPC §18 enumerates **70** distinct `T-RPC-*` ids across 12 group rows (4+4+8+14+5+4+11+2+7+3+4+4); RLS §16.11 enumerates **35** distinct `T-RLS-*` ids across **33** register rows (`T-RLS-FORCE-01..03` is one row, three ids). A CI plan provisioned from the row counts under-provisions by 37 assertions. | RPC §18 / RLS §16.11 | **both** — state ids, not rows | `TEST` |
| **G-23** | **S3** | **`T-RPC-DOOR-05`, `-06`, `T-RPC-GLOBAL-02..04` and `T-RPC-NOTIFY-02..04` exist only as bare suffixes** (`-05`, `-02`) inside §18's group cells and never as full ids anywhere in the corpus. A harness that greps for `T-RPC-` misses all nine. | RPC §18 | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `TEST` |

### 1.1 Holes of the `U-*` shape found by this pass, that §20A.3 did not list

§20A.3's own diagnosis — *"create-but-never-update, or authorize-but-never-name"* — is correct and
**incomplete**, because the integrator found the ten by walking the **dashboard**. Walking the **RLS EXEC
table** instead finds the same pattern in places the dashboard never renders:

| New | Same shape as | The instance |
|---|---|---|
| **G-4** | authorize-but-never-name | `venue.allocate_comp` / `venue.issue_comp` — a *fully argued* split authority model (who may allocate vs who may issue, and why box office gets one and not the other) attached to no signature |
| **G-5** | authorize-but-never-name | the six `market.*` listing/auction/offer writers — including one, *"bid RPC"*, that the authority table declines to name **even while granting it** |
| **G-6**, **G-7** | authorize-but-never-name | `catalog.set_platform_config` (every money threshold), `kernel.admin_refund`, `kernel.pay_promoter_commission`, the three `*_signing_key` RPCs |
| **G-13**, **G-15** | authorize-but-never-name | `venue.grant_staff_role` (the primary authority-conferring venue write), the unnamed *"manifest-sync"*, `venue.get_door_manifest` |
| **G-12** | create-but-never-update | confirmed at the source: `create_organization` / `create_event` / `create_event_session` / `create_inventory_batch` all exist; not one has an update counterpart |

**The generalization, stated so the next reviewer can apply it mechanically:** the corpus contracted the
functions a **product surface** demanded. It did not contract the functions an **authority table** granted.
`PHASE_2_RLS_PERMISSION_SPEC.md` §11 is the complete list of Phase-2 write authority;
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` is a **proper subset** of it. Every difference is a `GAP`, and the
difference is not small.

---

## 2. CONDITIONAL REGISTER — cells whose artifact exists and whose carrier does not

| ID | The dependency | What is conditional on it | If unresolved |
|---|---|---|---|
| **COND-A** | **event outbox + drainer** — DA §6.3 promises it, no package schedules it (row C51, decision **O7**, registry §7) | **Every `EVENT` cell in §4 and §5.** Plus: the Apple Wallet push path in full (pass supersession runs in the outbox consumer *specifically* so Wallet can never block or roll back a custody transfer — the two alternatives are both prohibited by ratified invariants); the door-manifest open transaction as specified; scanner push-to-sync; every notification | Those four capabilities are **unimplementable as designed**, not merely degraded. `crm_export`, `demographics`, `promoter_codes` and `money_authority` are **unaffected** — each carries its own scheduler |
| **COND-B** | **`notify` schema** — C7 says Gate P / MVP, four specs say Gate L / do-not-build (row C52, decision **O8**) | The whole notifications capability (§5.2): 9 tables, 23 RPCs, 2 crons, `notify-dispatch`, `notify-receipts`, RN §6, dashboard §16.5/§16.5a, the four `notify_*` policy families of RLS §16.10, and `T-RPC-NOTIFY-01..04` | MVP notifications continue on `public.notifications` + the existing `send-push`/`notify-*` edge functions, and **every Phase-2 design that names a `notify` consumer must say which carrier it actually means** (money §10.3, door §12.2, promoter, notifications spec) |
| **COND-C** | **`kernel.org_money_policy`** — money spec §7.4 specifies it and explicitly does not propose it; owner decision **D-2** | Per-org money thresholds. Recommendation on record: **No** | Money thresholds stay in the world-readable `catalog.platform_config`, which is precisely why the question exists |
| **COND-D** | **the coupling rule** (registry §7) | Outbox-in with `notify`-out is coherent. **`notify`-in with outbox-out is not** — the notifications design *is* the outbox pipeline | **O7 and O8 must be ruled together.** A ruling on one alone is not implementable |

---

## 3. THE HOLE MAP — the scannable instrument

One row per capability, one column per cell kind. **Read the `GAP` and `COND` marks; the ticks are not the
point.** `✓` = at least one named artifact exists. `—` = not applicable, justified in the capability's block
in §4/§5/§6. `GAP` = registered in §1. `COND` = registered in §2.

| # | Capability | TBL | RPC | RLS | EDGE | SURFACE | EVENT | TEST | PKG |
|---|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| **A1** | Schemas + GRANT boundary | — | ✓ | ✓ | — | — | — | ✓ | `076` |
| **A2** | Organizations + permissions | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | **GAP** | `077` |
| **A3** | Catalog (venue · event · session · config) | ✓ | **GAP** | ✓ | — | ✓ | **COND-A** | **GAP** | `078` |
| **A4** | Ticket kernel (custody atom + ownership log) | ✓ | ✓ | ✓ | — | ✓ | **COND-A** | **GAP** | `079` |
| **A5** | Inventory (roles + capacity) | ✓ | **GAP** | ✓ | — | ✓ | **COND-A** | **GAP** | `080`·`081` |
| **A6** | Orders (primary purchase) | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | **GAP** | `082` |
| **A7** | Credential infrastructure (C33) | ✓ | **GAP** | ✓ | ✓ | ✓ | ✓ | `083`·`084` |
| **A8** | Kernel money-native + money authority | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `085` |
| **A9** | Scan infrastructure + door | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `086` |
| **A10** | Settlement | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | **GAP** | `087` |
| **A11** | Native marketplace bridge | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | **GAP** | `088`·`089` |
| **A12** | Promoter engine | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `090` |
| **A13** | Money-ledger stub (`kernel.reserve`) | ✓ | — | ✓ | — | — | — | ✓ | `091` |
| **B1** | Apple Wallet | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | ✓ | `083`·`084` |
| **B2** | Notifications | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | ✓ | **GAP** |
| **B3** | CRM export | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | `087` |
| **B4** | Demographics + holder mix | ✓ | ✓ | ✓ | — | ✓ | — | ✓ | `077`·`086` |
| **B5** | Promoter codes | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | ✓ | `090` |
| **B6** | Door manifest + offline verify | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `086` |
| **C1** | O-1 refund authority | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | ✓ | `077`·`085` |
| **C2** | O-2 canonical role model | ✓ | ✓ | ✓ | — | ✓ | — | ✓ | `077`·`080` |
| **C3** | O-3 payout visibility + requests | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | ✓ | `077`·`085` |
| **C4** | O-4 door-manifest authority | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `086` |
| **C5** | O-5 `door_open_at` lifecycle | ✓ | ✓ | ✓ | — | ✓ | **COND-A** | ✓ | `078`·`086` |
| **D1** | Guest list + comps | ✓ | **GAP** | ✓ | — | ✓ | — | **GAP** | `086` |
| **D2** | Operational activity feed | ✓ | ✓ | ✓ | — | ✓ | — | **GAP** | `077` |
| **D3** | Stripe Connect onboarding | ✓ | **GAP** | **GAP** | ✓ | ✓ | **COND-A** | **GAP** | `077` |
| **D4** | Event outbox (the carrier itself) | **GAP** | **GAP** | — | — | — | **GAP** | **GAP** | **GAP** |

**Column totals — `GAP` count by cell kind:** `TBL` 1 · `RPC` 12 · `RLS` 2 · `EDGE` 0 · `SURFACE` 0 ·
`EVENT` 1 (plus 19 `COND-A`) · `TEST` 9 · `PKG` 2.

**The shape of the corpus, read off that row:** the **EDGE** and **SURFACE** columns are complete — every
edge function is specified and classified (edge §0.4), and every RN/dashboard surface has a spec. The
**RPC** column has twelve holes and the **TEST** column has nine. This is the signature of a corpus written
**outside-in**: the product surface and the service boundary are finished, the authority table is finished,
and the layer between them — the function contracts — is a proper subset of what the other two demand.
`INFERENCE:` an implementer working package-by-package from the migration plan will not notice, because the
migration plan lists *objects*, and a missing function contract is not a missing object.

---

## 4. THE SPINE — capabilities `A1`–`A13`

Each block is one matrix row rendered vertically so that no cell can be omitted silently.

---

### A1 · Schemas, GRANT boundary and shared helpers

| Cell | Value |
|---|---|
| **Product requirement** | Nothing a user sees. The modular-monolith boundary that makes every later row's deny-by-default true *before* its own RLS lands. |
| **Architecture invariant** | **GP-1** (deny-by-default at table birth) · **GP-2** (explicit REVOKE-then-GRANT, migration `067`) · **C7** (the seven bounded contexts; four schemas built, three deferred) · **I-1/I-2** (no `USING (true)`) |
| **Table(s)** | **`—`** — the package creates zero relations. *why `—`:* it creates schemas and two trigger *functions* (`kernel.set_updated_at()`, `kernel.raise_append_only()`); a schema is not a table and the plan states "no product tables". **COND-A would add `kernel.event_outbox` here** (registry §7). |
| **RPC(s)** | `kernel.set_updated_at()` · `kernel.raise_append_only()` (trigger functions, attached by later packages) |
| **RLS / EXEC** | `ALTER DEFAULT PRIVILEGES` in `kernel`/`venue`/`market` revoking table rights from `anon`/`authenticated`; `REVOKE ALL ON SCHEMA … FROM PUBLIC, anon, authenticated`; `GRANT USAGE ON SCHEMA catalog TO anon, authenticated` |
| **Edge function** | **`—`** *why:* no runtime surface exists yet; the first edge function (`primary-checkout`) targets `082`. |
| **RN / dashboard surface** | **`—`** *why:* infrastructure. No product surface reads a schema. |
| **Event** | **`—`** *why:* DDL is not a business event. DA §6.1's catalog is business facts only. **But see D4** — this is where the outbox table lands if O7 rules for the constitution. |
| **Test id** | Migration-plan §8 prose: replay `000→076` green · `\dn` shows four schemas · `has_schema_privilege('anon','kernel','USAGE') = false` · `catalog` USAGE `= true` · helpers `postgres`-owned with pinned `search_path` · no default table privilege for `anon`/`authenticated`. Structurally covered by `T-RPC-GLOBAL-01`. |
| **Package** | **`076_create_phase2_schemas_and_grants`** — REVERSIBLE |

---

### A2 · Organizations, permissions and the dual-control substrate

| Cell | Value |
|---|---|
| **Product requirement** | A venue operator creates an organization, invites staff, assigns roles, and every money-consequential change above a threshold requires a second person. |
| **Architecture invariant** | **C36** (scope-qualified roles are structural — three disjoint per-plane label sets, not a lint convention) · **O-2** (fifteen plane-prefixed labels; **RM-1** every label begins with its plane token) · **I-12/INV-NOFORCE** (`relforcerowsecurity = false` on `kernel.org_member` and `kernel.platform_role`, so the owner-bypass terminates the policy recursion) · **C11/Security R2** (the dual-control threshold is itself under dual control) |
| **Table(s)** | `kernel.identity_ext` (+`locale`) · `kernel.organization` (+`payout_destination_set_by`) · `kernel.org_member` · `kernel.org_invite` · `kernel.platform_role` · `kernel.admin_audit` · **`kernel.approval_request`** (Δ — was homeless; placed here by the integration amendment) · `kernel.identity_demographic(_erasure)` · `kernel.identity_contact_pref` · `kernel.org_customer_key` |
| **RPC(s)** | `create_organization` · `invite_org_member` · `accept_org_invite` · `change_org_role` · `remove_org_member` · `has_org_role`/`is_platform`/`has_org_role_over_venue`/`_over_event`/`is_org_affiliate` · `list_approval_requests` · `record_money_denial` (`DEF`) — **`GAP` G-3** (`set_org_connect_ref`), **G-12** (`update_organization`), **G-20** (`grant_org_role`/`revoke_org_role` vs `change_org_role`/`remove_org_member`; `set_org_status`, `grant/revoke_platform_role` and `upsert_identity_ext` have EXEC rows and no contract) |
| **RLS / EXEC** | `kernel_identity_ext_sel_owner` · `kernel_organization_sel_org` · `_sel_platform` · `kernel_org_member_sel_org` · `_sel_platform` (**I-12**) · `kernel_org_invite_sel_invitee` · `_sel_org` · `kernel_platform_role_sel_platform` (**I-12**). Zero policies by design on `admin_audit`, `approval_request`, `identity_demographic(_erasure)`, `identity_contact_pref`, `org_customer_key` |
| **Edge function** | `connect-onboarding` (Class **A**, `has_org_role([org_owner,org_finance])`) — **but see D3/G-3: it wraps an uncontracted RPC** |
| **RN / dashboard surface** | Dashboard **J** §15.1 (org members) · **K** §16.1 (org profile — `U-10`/G-12) · **H** §13.7 (refund approval queue, reading `approval_request`) |
| **Event** | **COND-A** — DA §6.1 #1 `OrganizationCreated` (consumers `analytics`, `social`) and #2 `ConnectOnboardingCompleted` (consumers `venue`, `market`, `analytics`). **Both have no carrier**, and #2 additionally has **no producer** (G-3). |
| **Test id** | `T-RLS-FORCE-01..03` (the I-12 catalog equality) · `T-RLS-FORCE-04` · `T-RLS-ROLE-01` (exactly fifteen labels, cross-plane rejected) · `T-RLS-ROLE-02` (no bare role string, no display name) · `T-RPC-ROLE-01..05` · `T-RLS-POL-01/02` — **`GAP` G-8:** no behavioural test for `create_organization`, `invite_org_member`, `accept_org_invite`, the ≥1-owner rule, or the no-self-grant rule. |
| **Package** | **`077_kernel_identity_orgs_and_roles`** — CLEAN-WHILE-EMPTY |

---

### A3 · Catalog — venue, event, session, platform config, resale policy

| Cell | Value |
|---|---|
| **Product requirement** | A venue is approved, an event is created and published, sessions carry door times, and every feature flag and money threshold has a home. |
| **Architecture invariant** | **O-5** (`door_open_at` is the cached monotone head of an append-only door-episode ledger — never client-written, never cleared by close, never moved backwards) · **C7** (`catalog` is a bounded context; world-readable by design) · **GP-1** · **COND-C** (`platform_config` is world-readable, which is exactly why a per-org money threshold cannot live in it) |
| **Table(s)** | `catalog.venue` · `catalog.event` (+`description`, `hero_image_ref`, `category`, `genre_tags`) · `catalog.event_session` (+`door_open_at`, `session_version`) · `catalog.platform_config` + **all** feature-flag and config seeds · `catalog.resale_policy` |
| **RPC(s)** | `create_venue` · `approve_venue` · `update_venue` · `create_event` · `create_event_session` · `cancel_event` (authored in `088`, FR-2b) · `publish_event` (authored in `081`, FR-2) · `effective_freeze_at` · `engage_door_freeze` (`DEF`, sole writer of `door_open_at`) — **`GAP` G-6** (`set_platform_config`), **G-12** (`U-9`: no update RPC for `event` or `event_session`), **G-20** (`set_resale_policy`, `set_event_status`/`publish_event`, `set_venue_approval`/`approve_venue`) |
| **RLS / EXEC** | `catalog_venue_sel_anon`/`_sel_org`/`_sel_venue` · `catalog_event_sel_anon`/`_sel_org`/`_sel_venue` · `catalog_event_session_sel_anon`/`_sel_org`/`_sel_venue` · `catalog_platform_config_sel_public` · `catalog_resale_policy_sel_public` |
| **Edge function** | **`—`** *why:* every catalog write is a plain DB-RPC; none touches an external provider, and edge §2's placement table admits a function only where a secret, a provider or a non-JWT credential is involved. |
| **RN / dashboard surface** | RN §4.1 Home/Discovery · §4.2 Event Page · Dashboard **B** §7 (events, wizard, publish, cancel) · **K** §16.2 (venue profile) · §16.7 (venue-scope resale default) |
| **Event** | **COND-A** — #3 `VenueApproved` · #4 `EventPublished`. Consumers named (`venue`, `market`, `social`, `analytics`); **`social` and `analytics` are deferred schemas under C11**, so even with the outbox two of the four named consumers do not exist in Phase 2. |
| **Test id** | `T-RLS-DOOR-08` (`effective_freeze_at` NOT NULL over every status × nullability combination — the totality property) · `T-RPC-DOOR-08` · `T-RPC-DOOR-14` (direct writes to `door_open_at` raise) · `T-RLS-POL-01` — **`GAP` G-8:** no test for `create_event`, `publish_event`'s "no empty on-sale" precondition, or `cancel_event`'s bounded SSCAS-#3 batch. |
| **Package** | **`078_catalog_reference_data_and_flags`** — CLEAN-WHILE-EMPTY |

---

### A4 · Ticket kernel — the custody atom and the ownership log

| Cell | Value |
|---|---|
| **Product requirement** | A ticket exists, has exactly one owner at a time, and every change of hands is permanently recorded. |
| **Architecture invariant** | **C26** (ownership-log idempotency key `UNIQUE(cause, cause_ref, ticket_id)` + the per-`market_sale` terminal machine `pending → completed XOR compensated` under the sale-row lock — the double-transfer-impossible proof) · **C27** (`credential_version` pinned to the ownership log; head-of-ledger pattern) · **C35** (the kernel authorizes the buyer principal itself; a market-supplied buyer id is never trusted) · **C41** (terminal `scanned`; `direction` is the reserved re-entry hedge) · **C42** (optional-nullable `seat_ref`/`unit_row` hedge) · **D2** (no `refunded` terminal — money reversal is `voided` with cause `refund_void`) · **D3** (the one canonical 13-value cause-code registry) |
| **Table(s)** | `kernel.tickets` (custody atom) · `kernel.ticket_ownership_log` (append-only) · `kernel.door_freeze_override` (moved here with `is_transfer_frozen`, FR-7) |
| **RPC(s)** | `issue_ticket_atoms` (SSCAS #1 mint leg) · `transfer_ticket_ownership` (SSCAS #2, authored in `088` per FR-3) · `void_ticket_atom` (SSCAS #3, authored in `085` per FR-4) · `lock_ticket`/`unlock_ticket` (SSCAS #6/#7 overlays) · `mark_ticket_scanned` · `is_transfer_frozen` · `get_ticket_custody_chain` · `market.get_ticket_history` (redacted) |
| **RLS / EXEC** | `kernel_tickets_sel_owner` · `_sel_venue` · `_sel_platform`. `kernel.ticket_ownership_log` and `kernel.door_freeze_override` carry **zero policies by design** (`REVOKE ALL`, RLS on) — the raw log is deny-all to clients and reachable only through the redacted read. |
| **Edge function** | **`—`** *why:* custody writes are the one surface edge §0.5 forbids from holding authority. `credential-sign` (A7) *reads* `kernel.tickets`; it writes nothing here. |
| **RN / dashboard surface** | RN §4.4 My Tickets · §4.5 Transfer · §4.10 refund states (`resale_state = refund_hold`) · RN §11 state index (`issued → active → scanned`, `voided`, `expired`; overlay `none/listed/locked`) |
| **Event** | **COND-A** — #10 `TicketIssued` · #17 `OwnershipTransferred` (**Sync**, the transfer itself) · #21 `CredentialInvalidated` (rides on #17) · #28 `TicketVoided`. The three `Sync` members are same-transaction and therefore **survive COND-A**; their *notification* and *analytics* consumers do not. |
| **Test id** | `T-RPC-DOOR-01` / `T-RLS-DOOR-01` — **the structural assertion that `mark_ticket_scanned` does not reference `is_transfer_frozen`** (the CRITICAL defect; admission must never be gated on the transfer freeze) · `T-RLS-DOOR-05` · `T-RPC-DOOR-05` — **`GAP` G-8:** **C26's idempotency key and its terminal state machine — the single most load-bearing invariant in Phase 2 — have no named test.** |
| **Package** | **`079_kernel_ticket_atom_and_ownership_log`** — **FORWARD-FIX ONLY from the first row** |

---

### A5 · Inventory — staff roles, predicates, capacity

| Cell | Value |
|---|---|
| **Product requirement** | Six kinds of venue staff, and a capacity counter that cannot oversell. |
| **Architecture invariant** | **C36** + **O-2** (six canonical venue labels; `venue_door` → `venue_scanner`; `venue_promoter` **removed** — a promoter is a `promoter_link` row-ownership relationship, never a staff-role label) · **C27** (`remaining` single truth: the **locked counter is authoritative**, the movement ledger is the audit stream, a reconciliation job asserts equality) · **C28** (global lock order includes ascending-batch-id) · **RM-1** · **I-12** (`venue.staff_role`) |
| **Table(s)** | `venue.staff_role` (text + CHECK per OD-6/X-3, six labels) · `venue.ticket_type` · `venue.inventory_batch` · `venue.inventory_batch_shard` · `venue.inventory_movement` · `venue.inventory_hold` · `venue.inventory_unit` (C42 hedge — **DO NOT BUILD/POPULATE in MVP**) |
| **RPC(s)** | `has_venue_role` · `has_event_role` · `has_org_role_over_venue`/`_over_event` · `create_ticket_type` · `create_inventory_batch` · `reserve_primary_inventory` · `create_inventory_hold` · `release_inventory_hold` · `catalog.publish_event` (authored here, FR-2) — **`GAP` G-12** (`U-8`: no capacity-change RPC on an existing batch, though dashboard §8.4 specifies the guarded behaviour and the refusal floor **in detail**), **G-20** (`set_ticket_type_price` has an EXEC row and no contract) |
| **RLS / EXEC** | `venue_staff_role_sel_venue`/`_sel_org`/`_sel_platform` (**I-12**) · `venue_ticket_type_sel_public`/`_sel_venue` · `venue_inventory_batch_sel_public` (the `remaining` projection) / `_sel_venue` (full counters) · `venue_inventory_hold_sel_owner`/`_sel_venue`. Zero policies by design on `inventory_batch_shard`, `inventory_movement`, `inventory_unit` |
| **Edge function** | **`—`** *why:* the hold is taken inside `create_primary_checkout`, which `primary-checkout` (A6) fronts. No inventory function needs a secret or a provider. |
| **RN / dashboard surface** | RN §4.2 Event Page (available / low / sold-out from `remaining`) · §4.3 Checkout hold timer · Dashboard **C** §8 (types, batches, door-vs-public, windows, holds, sold-out vs held-out) · **J** §15.2 venue staff |
| **Event** | **COND-A** — #5 `TicketTypeOpened/TierUnlocked` · #6 `InventoryHeldExpired` · #11 `TicketReserved`. **#5 additionally has no producer**: no tier concept exists in `venue.ticket_type` in any package. |
| **Test id** | `T-RLS-FORCE-01..03` (`venue.staff_role`) · `T-RLS-ROLE-01` · `T-RPC-ROLE-01` (`has_venue_role` does not reference `door_pin` — FR-1's closure) · `T-RPC-ROLE-04` (no grant RPC accepts a promoter artifact) · `T-RLS-ROLE-04` — **`GAP` G-8:** **no test asserts the oversell-safe counter.** C27 is the reason the counter exists and nothing named checks it under concurrency. |
| **Package** | **`080_venue_staff_roles_and_predicates`** + **`081_venue_inventory`** — both CLEAN-WHILE-EMPTY |

---

### A6 · Orders — the primary-purchase container

| Cell | Value |
|---|---|
| **Product requirement** | A fan buys tickets; the money is taken once; the tickets appear. |
| **Architecture invariant** | **C35** (buyer re-verified against the payment at the seam) · **C26** (SSCAS #1: order+intent same tx; capture+issuance same tx) · **OBS-1** (**no column is ever added to `public.payments`** — native resolution is PI `metadata` + a `kernel.payment_native` join) · **D7** (the attribution row is written **in the same transaction that marks the order paid — never at order creation**) · **R7** (money single path) |
| **Table(s)** | `venue.order` (+`attribution_candidate_code_id`, `_link_id` — RLS X-1) · `venue.order_item` · `kernel.org_contact_consent` |
| **RPC(s)** | `venue.create_primary_checkout` (schema `create_order`) · `venue.finalize_primary_order` (SSCAS #1) · `confirm_primary_payment_server_side` (EDGE-FRONTED) · `venue.resolve_order_attribution` (`DEF`, called only from `finalize_primary_order`, **never raises for an attribution problem**) · `venue.bind_order_attribution` |
| **RLS / EXEC** | `venue_order_sel_owner`/`_sel_org`/`_sel_venue` and the `_item` triple. Money columns are RPC-only; `order_item` is IMM after issuance |
| **Edge function** | **`primary-checkout`** (Class **A** — `create_primary_checkout` binds the hold and the order to `auth.uid()`; the on-behalf door path resolves the buyer from the *principal*, not the body). Idempotency `pi_native_${order_id}_${total}_c${cust}[_r${n}]`. Also **`stripe-webhook`** (extended, Class B-i/B-iii, HMAC + `claim_stripe_webhook_event` lease) |
| **RN / dashboard surface** | RN §4.3 Checkout (three variants) · §4.7 promoter code · §4.8 contact opt-in · Dashboard **H** §13.1 orders list |
| **Event** | **COND-A** — #7 `OrderPlaced` (**Sync**, order+intent same tx) · #8 `PaymentAuthorized` · #9 `PaymentCaptured` · #31 `AttributionRecorded` (**Sync**, same tx as OrderPaid — the D7 timing). The `Sync` set survives; the async consumers do not. |
| **Test id** | `T-RLS-ATTR-01` (**no `venue.attribution` row exists while the order is `pending`, even with both candidates set** — the D7 property) · `T-RPC-ATTR-01..04` · `T-RPC-GLOBAL-03` (no RPC accepts a client-supplied `buyer_id` as authority) — **`GAP` G-8:** no test for the SSCAS-#1 capture/issuance same-transaction property, nor for the OBS-1 frozen-boundary rule (that no migration adds a column to `public.payments`). |
| **Package** | **`082_venue_orders`** — CLEAN-WHILE-EMPTY |

---

### A7 · Credential infrastructure — signing keys and the asymmetric credential

| Cell | Value |
|---|---|
| **Product requirement** | A ticket presents a credential a door can verify — including a door with no network. |
| **Architecture invariant** | **C33** (per-event default scope · KMS/HSM custody · audited rotation with **one active signer per scope** · compromise runbook · signer HA/throughput · **public-key-only door distribution**) · **C37** (online door performs a live authoritative per-scan kernel read; the "dispute-free by construction" claim is dropped and offline is honestly *shrunk*, not closed) · **C27** (`credential_version` pinned to the ownership log, so a transfer fails the cached token closed) |
| **Table(s)** | `kernel.signing_key` (**public key + KMS handle reference only — no private key material**) · `kernel.pass_type_cert` · `kernel.wallet_pass` · `kernel.wallet_pass_device` · `kernel.wallet_pass_push_log`; `084` adds the late-binding FKs `kernel.tickets → venue.ticket_type` + `kernel.signing_key` (`NOT VALID` + `VALIDATE`) **and nothing else** |
| **RPC(s)** | `kernel.mint_wallet_pass` + the twelve Wallet RPCs (§17.23) — **`GAP` G-7:** `kernel.provision_signing_key` / `rotate_signing_key` / `revoke_signing_key` have EXEC rows (RLS §11.1) and **no contract**, though `signing-key-provision` wraps all three and they *are* the C33 lifecycle. |
| **RLS / EXEC** | `kernel_signing_key_sel_public` — **`public_key` + window columns only**. `kernel.wallet_pass`, `wallet_pass_device`, `pass_type_cert`, `wallet_pass_push_log` carry **zero policies by design** |
| **Edge function** | **`credential-sign`** (Class **A**, `current_owner_id = auth.uid()` is the entire authorization; KMS sign; version-deterministic, no dedup row) · **`signing-key-provision`** (Class **A**, `is_platform([platform_admin])`, KMS keygen) · **`pass-cert-provision`** (Class **A**, dual control) |
| **RN / dashboard surface** | RN §4.4 Entry Pass (keeps its **live** validity assertion) · §5 Apple Wallet · RN §11 (`signing_key.status ∈ active/rotating/revoked`, never shown to a fan) · Scanner §7.1 step 3 offline verify against **M2** |
| **Event** | **COND-A** — #21 `CredentialInvalidated` (**Sync**, rides on `OwnershipTransferred`). The Wallet *push* consumer of the same fact is **COND-A-blocking**: supersession runs in the outbox consumer *specifically* so Wallet can never block or roll back a custody transfer, and both alternatives are prohibited by ratified invariants. |
| **Test id** | `T-RLS-COL-03` (`authenticated` holds no SELECT on `wallet_pass.auth_token_enc` / `.auth_token_hash` / `.serial_no_opaque`; no `venue_*` or `org_*` role holds SELECT on any wallet table) · `T-RPC-WALLET-01..03` · `T-RLS-POL-02` |
| **Package** | **`083_kernel_credential_infrastructure`** (CLEAN-WHILE-EMPTY) + **`084_kernel_tickets_late_binding_fks`** (**REVERSIBLE — the only unconditionally reversible package; it creates zero relations and zero routines and rule §6.7 protects that shape**) |

---

### A8 · Kernel money-native and the money-authority surface

| Cell | Value |
|---|---|
| **Product requirement** | Money in, money back, money out — with a second pair of eyes above a threshold and no path by which one person can both redirect the bank account and release funds to it. |
| **Architecture invariant** | **R7** (money single path — no new object writes a money row) · **O-1** (refund authority is a **request door**, never direct execution of the money writer; three server-side tiers from `catalog.platform_config`; `org_admin` holds **no** refund authority at all) · **O-3** (payout visibility + requests; **the ruling collapses SoD-1 by construction** and is ratified **with** its compensating controls — a *permanent* requester-vs-setter identity split, destination probation, out-of-band notification; the cool-down is demoted to a detection window and named the weakest control in the set) · **OBS-1** · **C29/C30/C31** (Gate-M, modeled only) · **D6** (DA §7.6 carries **one** money matrix, and its money rows govern over ROLE_MODEL §5's) |
| **Table(s)** | `kernel.payment_native` (+`instrument_fingerprint`, added by `090`) · `kernel.refund` · `kernel.payout`; reads `kernel.approval_request` (`077`) |
| **RPC(s)** | `request_order_refund` · `approve_refund_request` · `cancel_refund_request` · `sweep_expired_refund_requests` (`DEF`) · `list_org_payouts` · `list_org_refunds` · `set_org_payout_destination` · `list_approval_requests` · `record_money_denial` (`DEF`) · `refund_primary_order` (`DEF`, narrowed) · `request_org_payout` · `hold_payout` · `release_payout` · `force_void_ticket` · `void_ticket_atom` + the `market.on_atom_voided` stub — **`GAP` G-7** (`admin_refund`, `pay_promoter_commission`), **G-6** (`set_platform_config`, which sets every threshold these RPCs read) |
| **RLS / EXEC** | **Zero policies by design** on `payment_native`, `refund`, `payout` (`REVOKE ALL`, RLS on). Authority is RLS §11.3 in full — including `kernel.request_org_payout` rejecting `auth.uid() = organization.payout_destination_set_by` **permanently for that destination**, with `sod_violation`, *not merely during the cool-down* |
| **Edge function** | **`payout-execute`** (Class **A** — SoD + step-up `aal`/`amr`, named explicitly by money §8.3(c)) · **`refund-execute`** (Class **A** — buyer-capped / `org_owner` / `org_finance` / `is_platform`, second-approver SoD) · **`stripe-webhook`** (extended) |
| **RN / dashboard surface** | RN §4.10 refund states · Dashboard **H** §13.3/§13.3a (tiered authority, *learned from the product*) · §13.7 refund approval queue · **I** §14.5 payouts · **K** §16.3 payout account · §16.6/§16.9 re-authenticate for a money action |
| **Event** | **COND-A** — #25 `PayoutReleased` (Async **by design**) · #26 `PayoutFailed` · #27 `RefundIssued` (**Sync** with ticket void if full) · #29 `DisputeOpened` · #30 `DisputeResolved`. **#29 and #30 have no producer**: no dispute or chargeback table exists in any of the sixteen packages (C30 is Gate-M, modeled only), yet SSCAS members #11 (dispute-resolution reversal) and the payout-freeze path both name them. |
| **Test id** | `T-RPC-MONEY-01..14` · `T-RLS-MONEY-01` (`org_admin` denied SELECT **and** EXECUTE on every payout/refund path) · `T-RLS-MONEY-02` (`approve_refund_request` by the requester raises **`self_approval`**, distinctly from a generic `42501`, so the UI can say *"a different person must approve this"*) · `T-RLS-MONEY-03` (`request_org_payout` by the destination-setter raises `sod_violation` **after** the cool-down has elapsed — the assertion that proves the control is permanent, not a wait) · `T-RLS-MONEY-04` · `T-RLS-EDGE-01` · `T-RPC-GLOBAL-04` |
| **Package** | **`085_kernel_money_native`** — **FORWARD-FIX ONLY from the first row** |

---

### A9 · Scan infrastructure — the door plane

| Cell | Value |
|---|---|
| **Product requirement** | A person at a door is admitted once, fast, and the record survives a dead network. |
| **Architecture invariant** | **C41** (MVP is no-re-entry GA; terminal `scanned` stands; the scan `direction` column is the reserved hedge) · **C37** (online door live-verifies at the decision point) · **O-4** (a scanner may sync, scan and admit, and may **never** create, move or clear the boundary; **admission is never gated on manifest state** — gating it would fail closed against paying fans at the door) · **RM-5** (`assert_door_session` appears in no RLS predicate) · **R-8** (`has_venue_role` never tests a `door_pin`) · **X-2** (`scan.actor_identity_id` — without it a `venue_scanner` grant is indistinguishable from a `venue_manager` grant in the ledger, and the insider-fraud trail has a hole exactly where O-2 asks for least privilege) |
| **Table(s)** | `venue.door_pin` · `venue.scan_device` · `venue.scan` (+`actor_identity_id`, +`manifest_id`) · `venue.comp_allocation` · `venue.guest_list` · `venue.guest_entry` · `venue.door_manifest(_entry/_delta)` · `venue.holder_mix_snapshot` · `venue.holder_mix_bucket` |
| **RPC(s)** | `create_door_pin` · `revoke_door_pin` · `validate_ticket_online` · `record_scan` · `reconcile_offline_scans` · `mark_ticket_scanned` · `assert_door_session` (`DEF`) · `open_door_manifest` · `close_door_manifest` · `append_door_manifest_delta` (`DEF`) — **`GAP` G-9** (`U-2` mark a guest arrived), **G-10** (`U-1` guest-list CRUD), **G-4** (`allocate_comp`/`issue_comp`), **G-13** (`register_scan_device` + the unnamed *"manifest-sync"*), **G-15** (`get_door_manifest`), **G-20** (`record_offline_scans` vs `reconcile_offline_scans`) |
| **RLS / EXEC** | `venue_scan_device_sel_venue` · `venue_scan_sel_venue` + `venue_scan_sel_platform` · `venue_comp_allocation_sel_venue` · `venue_guest_list_sel_venue` · `venue_guest_entry_sel_venue` · `venue_door_manifest_sel_venue` (+`_sel_platform`) · `venue_door_manifest_entry_sel_venue` · `venue_door_manifest_delta_sel_venue`. `venue.door_pin.pin_hash` is **never client-readable**. Zero policies on `holder_mix_snapshot`/`_bucket` |
| **Edge function** | **`door-session`** (Class **B-iii** — a `door_pin` is a **loginless device credential with no `auth.uid()`**; `assert_door_session` is the entire authority; **X-5**: it must derive `p_actor_device_id` server-side and never accept an attested human actor) · **`door-manifest`** (dual route: Class **A** staff-JWT · Class **B-iii** PIN) |
| **RN / dashboard surface** | RN §7 Scanner (flows, the seven result banners, `awaiting_manifest`, the two training rules) · Dashboard **G** §12 (staff+PINs, devices, manifest status, live scan board, manual lookup, reconciliation, offline) · **F** §11 guest list & comps |
| **Event** | **COND-A** — #22 `ScanAdmitted` (**Sync** online; **outbox-reconciled** offline — so the *offline* arm is COND-A-blocking) · #23 `ScanRejected` (Async) |
| **Test id** | `T-RPC-DOOR-01..16` · `T-RLS-DOOR-01..10`. Notably `T-RLS-DOOR-02` (admit succeeds **with the freeze engaged**), `-03` (second scan ⇒ `duplicate`, atom stays `scanned` — C41 first-in-wins holds under freeze), `-04` (`status='completed'` ⇒ `precondition_failed` — **admission gated by session status, not manifest state**), `-09` (a drained atom then scans — the end-to-end lockout regression), `-10` (six named principals may not open a manifest ⇒ `42501` and `door_open_at` unchanged) · `T-RPC-ROLE-05` / `T-RLS-ROLE-03` (`assert_door_session` in no `pg_policy`) · `T-RLS-COL-04` (`door_manifest_entry` exposes **no** owner/identity column) |
| **Package** | **`086_venue_door_and_scan`** — CLEAN-WHILE-EMPTY |

---

### A10 · Settlement

| Cell | Value |
|---|---|
| **Product requirement** | An event closes; the venue sees what it earned and what it is owed; the payout is generated from that, not from a spreadsheet. |
| **Architecture invariant** | **C8** (the `venue.settlement` ↔ `market` royalty fact crosses contexts via **a named `core`/`catalog` function or an outbox event, never a cross-schema join**) · **C28** (SSCAS #4 close, + member #5 commission) · **O-3** (`org_owner` reads the ledger and requests; `venue_finance` is narrowed to **settlement-caused** payouts for its own venue, because `kernel.payout` has no `venue_id` and an unqualified "own-venue payouts" was never expressible) · **SEAM-2** |
| **Table(s)** | `venue.settlement` · `venue.settlement_line` (incl. the **partial unique index that stops the same attribution being settled twice** — `uq_promoter_commission_cause_ref`, added by `090`) · `venue.export_job` · the `crm-exports` bucket |
| **RPC(s)** | `venue.open_settlement` · `kernel.close_settlement` (SSCAS #4) + its **two hook stubs** — `kernel.settlement_royalty_lines` (stub `087` → replaced `088`) and `kernel.settlement_commission_lines` (stub `087` → replaced `090`), both returning zero rows in the stub · `kernel.request_org_payout` — **`GAP` G-7** (`pay_promoter_commission` is the definer that the settlement path calls and it has no contract) |
| **RLS / EXEC** | `venue_settlement_sel_org` · `venue_settlement_sel_venue` and the `_line` pair. `venue.export_job` carries **zero policies by design**; the `crm_export_builder` Layer-0 exception is the **one** named deviation (owner decision **MD-2**) and **`BYPASSRLS` on that role is explicitly not an acceptable shortcut** |
| **Edge function** | **`payout-execute`** (settlement-close disbursement leg) · **`crm-export`** `/build` + `/download` |
| **RN / dashboard surface** | Dashboard **I** §14 (settlement list, open, detail, close, payouts) · **D** §9.6 CRM export |
| **Event** | **COND-A** — #24 `SettlementClosed` (**Sync**: close → request payouts, same tx) · #32 `PromoterCommissionAccrued` (Async). **The C8 royalty fact survives COND-A** — C8 admits *"a named function **or** an outbox event"*, and the §13.2 hook satisfies the named-function arm. This is the **only** cross-context channel in the corpus that is not outbox-dependent. |
| **Test id** | **`GAP` G-8** — `close_settlement` is SSCAS #4, it had **two** forward references (`088` royalty and `090` commission), it is the single point where money leaves the platform, and **RPC §18 names no test for it.** `T-RLS-MONEY-04` covers `venue_finance`'s read narrowing only. |
| **Package** | **`087_venue_settlement_and_export`** — CLEAN-WHILE-EMPTY (renamed from `087_venue_settlement`) |

---

### A11 · Native marketplace bridge

| Cell | Value |
|---|---|
| **Product requirement** | A fan resells a ticket on the platform, and the buyer gets custody or their money back — never neither, never both. |
| **Architecture invariant** | **C8** (the native-sale transaction boundary is pinned: `market` writes the `market_sale` row then calls the kernel transfer **in the same DB transaction**; **the kernel NEVER writes `market` tables**) · **C26** (terminal SM `pending → completed XOR compensated` under the sale-row lock) · **C35** (buyer authorized by the kernel itself at the seam) · **C43** (p2p `locked` overlay hard-TTL auto-unlocks; physical `expired` terminal; `requested ≡ initiated`; **no `failed` state**; cancel-to-self exempt from the C6 freeze) — **`RATIFIED-MODELED-ONLY(GATE-M)`, and RLS X-7 records that four documents describe its narrowing as implemented when nothing implements it** · **C50/O6** (the cross-region form is undecided; **Miami single-region builds neither**) |
| **Table(s)** | `market.listing_native` · `market.auction` · `market.offer` · `market.market_sale` · `market.p2p_transfer`; `089` adds `market.listing_unified` (VIEW, flag-gated) and adopts the `payment_native.sale_id` FK |
| **RPC(s)** | `create_p2p_transfer` · `accept_p2p_transfer` · `cancel_p2p_transfer` · `transfer_ticket_ownership` (authored here, FR-3) · `catalog.cancel_event` (authored here, FR-2b) · `sweep_expired_p2p_transfers` · `sweep_paid_pending_sales` (C25 auto-compensation) · `get_market_sale_status` — **`GAP` G-5: `create_listing`, `cancel_listing`, `create_auction`, the unnamed "bid RPC", `make_offer` and `respond_offer` are authorized in RLS §11.1 and contracted nowhere.** `088` creates three tables whose only writers are those six functions. |
| **RLS / EXEC** | `market_listing_native_sel_public` (`status='active'` discovery columns) · `_sel_owner` (seller full) · `market_auction_sel_public` · `market_offer_sel_owner` · `market_p2p_transfer_sel_owner`. `market.market_sale` carries **zero policies by design**. `market.listing_unified` carries **none** — it is `security_invoker` and inherits the base-table policies, which is what makes the bridge create no new authority |
| **Edge function** | **`stripe-webhook`** native branches. **`—`** for the listing/auction/offer writes themselves *why:* they touch no provider and hold no secret; edge §2's placement table admits none of them. |
| **RN / dashboard surface** | RN §4.5 Transfer UX · §4.6 Sell · §4.2 Event Page resale block · RN §11 (`market_sale`: `pending → completed \| compensated`, bounded transient `paid_pending_transfer`; `p2p_transfer`: `initiated → accepted → completed \| declined \| cancelled \| expired`) |
| **Event** | **COND-A** — #12 `ListingCreated` (**Sync** for native, it locks the ticket) · #13 `BidPlaced` · #14 `OfferMade/Accepted` · #15 `AuctionWon` · #16 `ListingSold` · #18 `TransferStarted` · #19 `TransferAccepted` · #20 `TransferExpired` (Async, cron-swept). The `Sync` arms survive COND-A; #20's cron sweep does too (`sweep_expired_p2p_transfers` is a DB function, not an outbox consumer). |
| **Test id** | `T-RLS-DOOR-05` (transfer and p2p-accept ⇒ `frozen` on a frozen session) · `T-RLS-DOOR-07` (`sweep_paid_pending_sales` **compensate** succeeds on a frozen session; **complete** is refused) · `T-RPC-DOOR-07` · `T-RPC-DOOR-12` (a `paid_pending_transfer` listing is not drained) — **`GAP` G-8:** no test for **C26's terminal XOR**, none for the C8 same-transaction pin, none for the six uncontracted market writers. |
| **Package** | **`088_market_native_rail`** (CLEAN-WHILE-EMPTY) + **`089_market_bridge_view_and_late_fk`** (REVERSIBLE) |

---

### A12 · Promoter engine

| Cell | Value |
|---|---|
| **Product requirement** | A promoter brings people, is credited for exactly the orders they brought, and is paid out of the settlement. |
| **Architecture invariant** | **D7** (**the attribution row is written in the same transaction that marks the order paid — never at order creation.** Attribution is an *immutable Ledger* carrying a commission claim: writing it at creation credits a promoter for an order that may never be paid, and the credit then cannot be deleted, only superseded. **The constitutions are the side that is right; RPC §6.1 and RLS §9.17 are wrong and must move**) · **D8** (`venue.promoter` could not express DA §1.7's ratified commercial terms — flat-per-ticket **or** %, a `tier`, a `party_kind` discriminator; it carried only `commission_bps`. The schema integrator adds the columns; **nothing in the constitutions changes to match the narrower schema**) · **O-2** (`venue_promoter` removed from the enum — a promoter is a row-ownership relationship) |
| **Table(s)** | `venue.promoter` (+`tier`, `party_kind`, `commission_kind`, `commission_flat_minor`) · `venue.promoter_link` · `venue.attribution` (+15 columns) · `venue.promoter_code` · `venue.promoter_code_scope` · `venue.attribution_review`; also adds `uq_promoter_commission_cause_ref` on `venue.settlement_line` and `kernel.payment_native.instrument_fingerprint` |
| **RPC(s)** | `create_promoter_code` · `create_promoter_codes_bulk` · `set_promoter_code_status` · `set_promoter_code_scope` · `set_promoter_code_window` · `preview_promoter_code` · `resolve_order_attribution` (`DEF`) · `bind_order_attribution` · `review_attribution_flag` · `decide_flagged_attribution` · `get_my_promoter_summary` · `list_my_attributions` · `list_promoter_attributions` · `is_promoter_for_event` — **`GAP` G-11:** `U-3`/`U-4` — promoter-record and promoter-link writes have only an unnamed *"promoter CRUD"* row, and the live slug-availability read the UI is required to run **does not exist**. |
| **RLS / EXEC** | `venue_promoter_sel_org`/`_sel_venue`/`_sel_promoter` and the same triple for `promoter_link`, `promoter_code`, `promoter_code_scope`, `attribution`, `attribution_review` — **promoter own-row via `promoter_id = auth.uid()`, never a join through `link_id`** (§9.17) |
| **Edge function** | **`promoter-code-preview`** (Class **A** when a JWT is present; `verify_jwt=false`; read-only advisory that grants nothing). Carries **the one rate-limit adaptation**: `public.check_rate_limit`'s first parameter is a `uuid`, so it cannot key an unauthenticated principal; the wrapper derives `uuidv5(NS_PROMOCODE, ip || ':' || sha256(user_agent))`, **a rate-limiting key only — never persisted as an identity, never joined to `auth.users`, never used in an authorization predicate** |
| **RN / dashboard surface** | RN §4.7 promoter code at checkout (**advisory only, never a checkout gate**) · Dashboard **E** §10 (two-tier wall, list, invite/assign, links, codes, attribution view, self-deal flag queue, performance) |
| **Event** | **COND-A** — #31 `AttributionRecorded` (**Sync**, same tx as OrderPaid) · #32 `PromoterCommissionAccrued` (Async). #31 survives COND-A as a same-transaction write; #32 does not. |
| **Test id** | `T-RPC-PROMO-01..11` · `T-RPC-ATTR-01..04` · `T-RLS-ATTR-01` (no attribution row while the order is `pending`, **even with both candidates set**) · `T-RLS-ATTR-02` (a **code-sourced** attribution with `link_id IS NULL` **is** visible to its own promoter — the §9.17 predicate correction) · `T-RPC-ROLE-04` |
| **Package** | **`090_venue_promoter_engine`** — CLEAN-WHILE-EMPTY |

---

### A13 · Money-ledger stub

| Cell | Value |
|---|---|
| **Product requirement** | None. This capability has no user-visible behaviour in Phase 2 **by design**, and saying otherwise would be the over-build C11 warns against. |
| **Architecture invariant** | **C29** (first-class Reserve/Clawback object + payout-timing policy gating instant payout) · **C30** (fan-side chargeback liability representable) · **C31** (additive double-entry ledger beside the frozen Stripe core) — **all three `RATIFIED-MODELED-ONLY(GATE-M)`**. Registry rule **§6.7**: `091` is a protected shape — always empty, referenced by no routine, which is what makes its rollback unconditionally reversible |
| **Table(s)** | `kernel.reserve` — **stub only: empty shape, no writers** |
| **RPC(s)** | **`—`** *why:* the package's stated invariant is *"no routine in the database references it."* A contracted RPC would break the protected shape and require a ratified amendment. |
| **RLS / EXEC** | RLS enabled, **zero policies**, `REVOKE ALL` — DENY-ALL |
| **Edge function** | **`—`** *why:* no writers exist to front. |
| **RN / dashboard surface** | **`—`** *why:* Gate-M. Rendering a reserve balance from an always-empty table would be a false statement to an operator. |
| **Event** | **`—`** *why:* no writer, therefore no fact to publish. Not COND-A: this cell would be empty even with an outbox. |
| **Test id** | Migration-plan §8 prose: the relation exists, is empty, and **no routine references it** (mechanically checkable from `pg_depend`) |
| **Package** | **`091_kernel_reserve_stub`** — REVERSIBLE |

---
