# Phase 2 — Implementation Traceability Matrix

**Status:** completeness instrument. Design-only. **Creates no SQL, no migration, no code, and edits no other file.**
**Baseline:** `phase2/consolidation` @ `64d2aac` for the body — after all four integration passes (schema+plan,
RLS+RPC, edge+RN+dashboard, constitutions+rulings) — **reconciled forward to `cbf8926` for RLS §16.10 only, by
the 2026-08-28 reviewer-conditions pass (§14).** The rest of this document has **not** been re-verified against
`cbf8926`. **Read §14 before trusting any cell:** the four remediation passes that landed after `64d2aac`
changed RLS, and this instrument has no mechanism that fails when its baseline goes stale.
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
| **G-8** | **S2** | **The corpus has two disjoint test surfaces and the spine sits only in the weaker one.** (a) The **named, citable** registers — RPC §18 (70 `T-RPC-*` ids) and RLS §16.11 (35 `T-RLS-*` ids) — cover the *delta-spec* surfaces (door, money, role, attribution, promoter, demographics, CRM, wallet, notify) plus global posture, and **nothing else**. (b) The migration plan §8 carries **per-package prose acceptance criteria**, and these are substantial — the C26 proof rig (`079`), the oversell proof rig (`081`), the `market_sale` terminal XOR (`088`), the C41 partial unique and the three `door_open_at` raises (`086`), the commercial-terms XOR and the cross-settlement commission unique (`090`). **The spine is tested; its assertions just cannot be cited.** RLS §16.11's own header says ids exist *"so they can be written, run and cited"* — the spine's cannot be named in a review, a CI job name, or a regression ticket. **Correction of record:** an earlier reading of this matrix asserted the spine had *no* test. That was wrong, and the error is left visible rather than silently repaired. | RPC §18 should absorb the plan §8 assertions as ids, or §16.11's citability rationale should state why the spine is exempt | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** §18 | `TEST` |
| **G-8b** | **S2** | **Four things are asserted by neither surface.** (i) **Comps and guest lists** — `086`'s Tests row covers scans, PINs, manifests and holder mix and is **silent on comps and guest lists entirely**, and no `T-*` group exists; the C39 threshold and the box-office allocate/issue asymmetry are *named insider-fraud controls* with no assertion anywhere. (ii) **`venue.read_operational_audit`'s security-plane exclusion** — the entire security property of the read. (iii) **OBS-1** — no assertion anywhere states that no migration adds a column to `public.payments`; `§0.5`'s "additive-only" global is adjacent but not the property. (iv) The **six uncontracted `market.*` writers** (G-5) — `088` tests the tables' constraints, not the functions. | plan §8 rows `082`, `086`, `088`; RPC §18 | **`PHASE_2_SUPABASE_MIGRATION_PLAN.md`** §8 + **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** §18 | `TEST` |
| **G-24** | **S1** | **The inventory-hold expiry sweep is referenced, indexed for, and named nowhere.** Schema §1116 lists *"the expiry sweep"* among package `081`'s objects; the plan builds a partial index `expires_at WHERE status='active'` **precisely so the sweep can use it**; and `081`'s own **Functions** row lists `create_inventory_hold` and `release_inventory_hold` and **no sweep**, its **Tests** row is silent, RPC §12's sweeps are the two `market.*` ones only, and RLS §11 grants no such EXEC. **Consequence:** a `venue.inventory_hold` row never leaves `active` on its own, so held capacity is never returned to the counter — an abandoned checkout removes inventory from sale permanently. It is the exact shape of `sweep_expired_refund_requests`, which the money spec calls *"not optional"* and which **is** contracted. | RPC contracts §12 (sweeps); plan §8 `081` Functions | **`PHASE_2_RPC_FUNCTION_CONTRACTS.md`** | `RPC`, `TEST` |
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
| **G-25** | **S2** | **The event catalog says 36 and the ratification says ~16, and nothing reconciles them.** Ratified row **C11** states the catalog *"is trimmed to the ~10 invariant-bearing sync calls + ~6 real outbox events"*. **DA §6.1 still lists all 36 rows and no document says which sixteen survive.** Under COND-A the only question that matters is *which events need a carrier*, and the ratified answer is "about six" while the catalog presents thirty-six unmarked. **An owner pricing the O7 ruling is reading a list a ratified correction already cut by more than half.** Full analysis in §8.3. | DA §6.1 (mark the surviving set) | **`SNATCH_IT_DOMAIN_ARCHITECTURE.md`** | `EVENT` |

**Register totals: 26 entries** — **`S1` 8** (G-1…G-7, G-24) · **`S2` 14** (G-8, G-8b, G-9…G-19, G-25) ·
**`S3` 4** (G-20…G-23). **Nine appear in no prior spec's reconciliation list and were found by this pass**:
G-4, G-5, G-6, G-7, G-8b, G-20, G-22, G-24, G-25. The other seventeen were filed by a sibling integrator
(dashboard §20A.3 `U-1`…`U-10` and Δ11/Δ12; edge §9 recon #10/#12; registry §7 COND-A/COND-B) and are
carried here so that a single document answers *"what is missing"* without a reader assembling four.

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

**A fourth `TEST` value is needed and is load-bearing:** `✓ᵖ` = **prose-only** — the assertion exists in the
migration plan §8's per-package Tests row and has **no citable id** in RPC §18 or RLS §16.11. It is not a
`GAP` (the property *is* asserted) and it is not `✓` (it cannot be named in a review, a CI job name or a
regression ticket). See **G-8**.

| # | Capability | TBL | RPC | RLS | EDGE | SURFACE | EVENT | TEST | PKG |
|---|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| **A1** | Schemas + GRANT boundary | — | ✓ | ✓ | — | — | — | ✓ᵖ | `076` |
| **A2** | Organizations + permissions | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `077` |
| **A3** | Catalog (venue · event · session · config) | ✓ | **GAP** | ✓ | — | ✓ | **COND-A** | ✓ᵖ | `078` |
| **A4** | Ticket kernel (custody atom + ownership log) | ✓ | ✓ | ✓ | — | ✓ | **COND-A** | ✓ᵖ | `079` |
| **A5** | Inventory (roles + capacity) | ✓ | **GAP** | ✓ | — | ✓ | **COND-A** | ✓ᵖ | `080`·`081` |
| **A6** | Orders (primary purchase) | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | ✓ᵖ | `082` |
| **A7** | Credential infrastructure (C33) | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `083`·`084` |
| **A8** | Kernel money-native + money authority | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `085` |
| **A9** | Scan infrastructure + door | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `086` |
| **A10** | Settlement | ✓ | ✓ | ✓ | ✓ | ✓ | **COND-A** | ✓ᵖ | `087` |
| **A11** | Native marketplace bridge | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ᵖ | `088`·`089` |
| **A12** | Promoter engine | ✓ | **GAP** | ✓ | ✓ | ✓ | **COND-A** | ✓ | `090` |
| **A13** | Money-ledger stub (`kernel.reserve`) | ✓ | — | ✓ | — | — | — | ✓ᵖ | `091` |
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

**Column totals.** `GAP` by cell kind: `TBL` 1 · `RPC` **12** · `RLS` 1 · `EDGE` **0** · `SURFACE` **0** ·
`EVENT` 1 (plus **20** `COND-A`) · `TEST` 4 · `PKG` 2 — **21 `GAP` marks over 26 register entries**, the
difference being entries that describe a divergence rather than an empty cell. `TEST` additionally carries
**8 `✓ᵖ`**.
`—` by cell kind: `TBL` 1 · `RPC` 1 · `RLS` 1 · `EDGE` 11 · `SURFACE` 3 · `EVENT` 7 · `TEST` 0 · `PKG` 0
— **24 in total, and all 24 are justified in their capability block. Zero unjustified `—` exist in this
document**, which is the property §0.2 makes binding on itself.

**The shape of the corpus, read off that row:** the **EDGE** and **SURFACE** columns are complete — every
edge function is specified and classified (edge §0.4), and every RN/dashboard surface has a spec. The
**RPC** column has twelve holes. This is the signature of a corpus written **outside-in**: the product
surface and the service boundary are finished, the authority table is finished, and the layer between them —
the function contracts — is a proper subset of what the other two demand.

**Why an implementer will not notice.** The migration plan §8 lists **objects**, and a missing function
*contract* is not a missing object. Nine of the twelve `RPC` gaps name functions the plan **does** schedule:
`086`'s Functions row lists `allocate_comp`, `issue_comp`, `register_scan_device`, `get_door_manifest` and
`sweep_implicit_door_freezes`; `081`'s lists `set_ticket_type_price`. An engineer working package-by-package
sees the object, finds no signature, and writes one — which is exactly how two functions with one purpose,
or one function with the wrong predicate, gets built. **This is the single most actionable finding in the
document**, and it is invisible from any one spec.

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
| **Test id** | `T-RLS-FORCE-01..03` (the I-12 catalog equality) · `T-RLS-FORCE-04` · `T-RLS-ROLE-01` · `T-RLS-ROLE-02` · `T-RPC-ROLE-01..05` · `T-RLS-POL-01/02`. Plan §8 `077` adds: adversarial RLS (anon and non-member cannot read an org row, a member can), **self-grant rejected**, the disjoint-role CHECK asserting the full 15-label enumeration, **INV-NOFORCE asserted positively for `org_member` and `platform_role`**, the `approval_request` SoD CHECK rejecting `approved_by = requested_by`, and `set_my_demographics` writing no value into any audit row. **`GAP` G-8b (narrow):** the *keep-≥1-owner* rule lives in the EXEC row and is asserted nowhere. |
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
| **Test id** | `T-RLS-DOOR-08` / `T-RPC-DOOR-08` (`effective_freeze_at` NOT NULL over every status × nullability combination — the totality property) · `T-RPC-DOOR-14` · `T-RLS-POL-01`. **`✓ᵖ` (G-8):** plan §8 `078` asserts anon can read an approved venue/event but **not** a draft, all flags present and `false`, `resale_policy` default `off`, and **a cross-config invariant over the seeded values — `credential.wallet_default_span + credential.wallet_exp_skew <= door.manifest_ttl_interval`, so a Wallet token may never outlive the offline window any manifest could authorise**. `081` asserts `publish_event` refuses an event with no ticket type or no batch. **`GAP` G-8b (narrow):** `cancel_event`'s bounded SSCAS-#3 batch is asserted nowhere. |
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
| **Test id** | `T-RPC-DOOR-01` / `T-RLS-DOOR-01` — **the structural assertion that `mark_ticket_scanned` does not reference `is_transfer_frozen`** (the CRITICAL defect; admission must never be gated on the transfer freeze) · `T-RLS-DOOR-05` · `T-RPC-DOOR-05`. **`✓ᵖ` (G-8)** for C26 itself: plan §8 `079` runs **the C26 proof rig against the real constraints** — (a) a second `(market_sale, sale_id, atom)` rejected; (b) N `(issue, order_id, atom_k)` all succeed; (c) N `(refund_void, refund_id, atom_k)` all succeed; (d) a replayed `command_idempotency_key` rejected — plus **`is_transfer_frozen` returns TRUE for an unknown atom id** (the fail-open escape hatch asserted *absent*). **The single most load-bearing invariant in Phase 2 is asserted and cannot be cited by id.** |
| **Package** | **`079_kernel_ticket_atom_and_ownership_log`** — **FORWARD-FIX ONLY from the first row** |

---

### A5 · Inventory — staff roles, predicates, capacity

| Cell | Value |
|---|---|
| **Product requirement** | Six kinds of venue staff, and a capacity counter that cannot oversell. |
| **Architecture invariant** | **C36** + **O-2** (six canonical venue labels; `venue_door` → `venue_scanner`; `venue_promoter` **removed** — a promoter is a `promoter_link` row-ownership relationship, never a staff-role label) · **C27** (`remaining` single truth: the **locked counter is authoritative**, the movement ledger is the audit stream, a reconciliation job asserts equality) · **C28** (global lock order includes ascending-batch-id) · **RM-1** · **I-12** (`venue.staff_role`) |
| **Table(s)** | `venue.staff_role` (text + CHECK per OD-6/X-3, six labels) · `venue.ticket_type` · `venue.inventory_batch` · `venue.inventory_batch_shard` · `venue.inventory_movement` · `venue.inventory_hold` · `venue.inventory_unit` (C42 hedge — **DO NOT BUILD/POPULATE in MVP**) |
| **RPC(s)** | `has_venue_role` · `has_event_role` · `has_org_role_over_venue`/`_over_event` · `create_ticket_type` · `create_inventory_batch` · `reserve_primary_inventory` · `create_inventory_hold` · `release_inventory_hold` · `catalog.publish_event` (authored here, FR-2) — **`GAP` G-24** (**the hold-expiry sweep: named in the schema spec's object list, given a dedicated partial index, and contracted, scheduled and tested nowhere. Held capacity never returns to the counter**), **G-12** (`U-8`: no capacity-change RPC on an existing batch, though dashboard §8.4 specifies the guarded behaviour and the refusal floor **in detail**), **G-20** (`set_ticket_type_price` is in `081`'s Functions row and has no contract) |
| **RLS / EXEC** | `venue_staff_role_sel_venue`/`_sel_org`/`_sel_platform` (**I-12**) · `venue_ticket_type_sel_public`/`_sel_venue` · `venue_inventory_batch_sel_public` (the `remaining` projection) / `_sel_venue` (full counters) · `venue_inventory_hold_sel_owner`/`_sel_venue`. Zero policies by design on `inventory_batch_shard`, `inventory_movement`, `inventory_unit` |
| **Edge function** | **`—`** *why:* the hold is taken inside `create_primary_checkout`, which `primary-checkout` (A6) fronts. No inventory function needs a secret or a provider. |
| **RN / dashboard surface** | RN §4.2 Event Page (available / low / sold-out from `remaining`) · §4.3 Checkout hold timer · Dashboard **C** §8 (types, batches, door-vs-public, windows, holds, sold-out vs held-out) · **J** §15.2 venue staff |
| **Event** | **COND-A** — #5 `TicketTypeOpened/TierUnlocked` · #6 `InventoryHeldExpired` · #11 `TicketReserved`. **#5 has no producer**: no tier concept exists in `venue.ticket_type` in any package. **#6 has no producer either — G-24.** |
| **Test id** | `T-RLS-FORCE-01..03` (`venue.staff_role`) · `T-RLS-ROLE-01` · `T-RPC-ROLE-01` (`has_venue_role` does not reference `door_pin` — FR-1's closure) · `T-RPC-ROLE-04` · `T-RLS-ROLE-04`. **`✓ᵖ` (G-8)** for C27 itself: plan §8 `081` runs **the oversell proof rig** — concurrent decrements cannot drive `remaining < 0`; the sharded draw plus single-shard last-unit fallback sells the final unit **exactly once**; the movement ledger reconciles to the counter (`Σ shards == batch`). Substantial, and un-citable. **`GAP` G-24:** nothing asserts that held capacity is ever returned. |
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
| **Test id** | `T-RLS-ATTR-01` (**no `venue.attribution` row exists while the order is `pending`, even with both candidates set** — the D7 property) · `T-RPC-ATTR-01..04` · `T-RPC-GLOBAL-03` (no RPC accepts a client-supplied `buyer_id` as authority). **`✓ᵖ`** for the rest: plan §8 `082` asserts the C16 replay rejection, that `order_item` UPDATE after `paid` raises, that a non-buyer cannot read, and the full consent property (*withdrawal is a state change, never a row deletion; the FK cascades from `auth.users` and `delete_account_cleanup` (020) does not repoint it to the anonymized sentinel — a sentinel row holding "consent granted to 40 orgs" would be an accumulating grant belonging to nobody*). **`GAP` G-8b:** nothing asserts the SSCAS-#1 capture/issuance same-transaction property, and nothing anywhere asserts **OBS-1** — that no migration adds a column to `public.payments`. |
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
| **Test id** | `T-RLS-MONEY-04` (`venue_finance` reads only `cause='settlement'` payouts for its own venue and **zero rows of every other cause**) · `T-RPC-CRM-01..07` for the export half. **`✓ᵖ` (G-8)** for the settlement half: plan §8 `087` asserts `settlement_line` unique per `(settlement, cause, cause_ref)`, the AO guard, that a close writes a `kernel.payout` row, and that **both hook stubs exist and return zero rows — so a close at `087` is arithmetically complete without them**; `090` adds that **the cross-settlement commission unique rejects lining the same attribution into a second settlement — the constraint whose absence made double-payment possible.** `close_settlement` is SSCAS #4 and the single point where money leaves the platform, and **not one of those assertions has an id.** |
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
| **Test id** | `T-RLS-DOOR-05` (transfer and p2p-accept ⇒ `frozen` on a frozen session) · `T-RLS-DOOR-07` (`sweep_paid_pending_sales` **compensate** succeeds on a frozen session; **complete** is refused) · `T-RPC-DOOR-07` · `T-RPC-DOOR-12` (a `paid_pending_transfer` listing is not drained). **`✓ᵖ` (G-8)**: plan §8 `088` asserts the two partial uniques (one active listing / one open p2p per atom), the C16 uniques, **the `market_sale` terminal state machine — a sale reaches exactly one of `completed`/`compensated`, never both** — that discovery RLS surfaces native listings to anon **only when the flag is ON**, that `settlement_royalty_lines` **now returns rows** (the stub was replaced, not merely present), that `on_atom_voided` flips a seeded sale to `compensated`, and that **no write path into `public.*` custody exists**. **`GAP` G-8b:** nothing asserts the C8 same-transaction pin, and nothing tests the six uncontracted writers (G-5) — `088` tests the tables, not the functions. |
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

## 5. THE SIX NEW FEATURES — capabilities `B1`–`B6`

---

### B1 · Apple Wallet

| Cell | Value |
|---|---|
| **Product requirement** | "Add to Apple Wallet" on a ticket, a pass that updates itself when custody moves, and a recovery path when it will not scan. |
| **Architecture invariant** | **C33** (the pass is signed by a key whose private half never leaves KMS) · **C35** (`mint_wallet_pass` authorizes the atom's current owner via `auth.uid()` in-body, live-read — the wallet spec was self-contradictory here and edge §0.4 resolved it to Class A) · **C27** (`credential_version`: a custody transfer supersedes the pass) · **GP-2** · **RN §5.1** (the Wallet pass displays **no validity assertion** while the in-app Entry Pass keeps its live one — the asymmetry is deliberate; and **no visual admission, ever**) · **RN §5.2** (no holder name on the pass) |
| **Table(s)** | `kernel.pass_type_cert` · `kernel.wallet_pass` · `kernel.wallet_pass_device` · `kernel.wallet_pass_push_log` · the `.pkpass` storage bucket |
| **RPC(s)** | `kernel.mint_wallet_pass` + twelve (§17.23), incl. `revoke_wallet_pass`, `supersede_wallet_passes_for_atom` (`DEF`), `touch_wallet_pass`, `get_wallet_pass_build_context`, `register/unregister_wallet_pass_device`, `list_updated_wallet_passes`, `record_wallet_push_result`, `sweep_wallet_pass_lifecycle`, and the three `*_pass_type_cert` lifecycle RPCs |
| **RLS / EXEC** | **Zero policies on all four tables.** `wallet_pass` is read by the owner **through an RPC only**, projected to `{wallet_pass_id, ticket_atom_id, status, built_at, last_updated_at}`. **No venue role and no org role reads any wallet table at all** — a pass registry is not venue-operations data; the door's bulk read is the manifest and nothing else. **No client, venue role or org role ever reads a push token.** |
| **Edge function** | **`wallet-pass-issue`** (Class **A**) · **`wallet-pass-webservice`** (Class **B-i/B-iii**, `verify_jwt=false` — **the second and last such surface in the system**; Apple devices present `Authorization: ApplePass <token>`, compared **constant-time** against `auth_token_hash`, authorizing **one serial only**) · **`wallet-pass-push`** (Class **B-i** outbox drain · Class **A** for the `is_platform` manual re-drive) · **`pass-cert-provision`** (Class **A**, dual control) |
| **RN / dashboard surface** | RN §5 in full (§5.3 the surfaces, §5.4 failure and recovery, §5.5 the secrets that may never be in the app, §5.6 scanner impact: none). Dashboard: **`—`** *why:* a pass is a fan artifact; no operator control exists, and RLS denies every venue and org role a read. |
| **Event** | **COND-A, and this is the blocking case.** `supersede_wallet_passes_for_atom` is called **from the outbox consumer, not inside the custody transaction**, *specifically so a Wallet outage can never roll back or block a transfer*. The two alternatives — moving it into the custody transaction, or leaving a superseded pass live — are **both prohibited by ratified invariants**. Without COND-A the push path does not merely degrade; **it has no admissible design.** Separately, edge §9 **FR-9**: `wallet-pass-push` drains "the market outbox" and "the catalog outbox", an ordering dependency the Wallet spec never flags. |
| **Test id** | `T-RPC-WALLET-01..03` · `T-RLS-COL-03` (`authenticated` holds no SELECT on `auth_token_enc` / `auth_token_hash` / `serial_no_opaque`; no `venue_*` or `org_*` role holds SELECT on any wallet table) |
| **Package** | **`083`** (tables + bucket) · **`084`** (the edge functions' `Pkg` column in edge §8) |

---

### B2 · Notifications

| Cell | Value |
|---|---|
| **Product requirement** | A fan is told when something happens to their ticket and can turn categories off; a venue can send an update to an audience. |
| **Architecture invariant** | **C7** (`notify` is one of the seven bounded contexts — **RATIFIED, Gate P, MVP**) · **C52 / decision O8** (all four implementation specs place it at Gate L / do-not-build; **the contradiction is the row**) · **C12** (event envelope: per-aggregate monotonic `sequence`, `causation_id`, `correlation_id`, at-least-once + idempotent consumers) · **GP-2** (a "cleared" notification is a `dismissed_at` column, never a row removal) · **SoD** (drafting and releasing an announcement are distinct acts; above the blast-radius threshold, release needs a **second distinct** approve-authorized principal, so one compromised credential cannot blast a stadium) |
| **Table(s)** | `notify.notification` · `preference` · `notification_type` · `template` · `delivery` · `outbox` · `schedule` · `identity_channel_state` · `announcement` — **nine tables, and `notify.outbox` is the same object COND-A is about** |
| **RPC(s)** | 23 `notify.*` RPCs (§17.24). `claim_deliveries` and `record_delivery_result` (§17.25) are **wholly AUTHORED, not transcribed** — their source names them and supplies **no contract body at all**; the claim predicate, lease semantics, batch bound, outcome mapping, return shapes and idempotency rule are derived. `INFERENCE:` flagged in RPC §19 item 1 |
| **RLS / EXEC** | `notify_notification_sel_owner` · `notify_notification_upd_owner` — **the only UPDATE policy in the entire Phase-2 register**, column-restricted to `read_at` · `notify_preference_sel_owner`/`_ins_owner`/`_upd_owner` · `notify_announcement_sel_venue`. **The mandatory-type guard is DDL, never RLS** — a composite FK plus `CHECK (delivery_class <> 'mandatory')`, because *a policy could be misconfigured and a CHECK cannot*. Zero policies on `notification_type`, `template`, `delivery`, `outbox`, `schedule`, `identity_channel_state` |
| **Edge function** | **`notify-dispatch`** (Class **B-i**, `INTERNAL_CRON_SECRET` **or** service-role, constant-time; no human caller) · **`notify-receipts`** (Class **B-i**, provider receipt poll + dead-token revocation) |
| **RN / dashboard surface** | RN §6 (notification centre, the eight requirements, deep links, §6.3 door-drain notifications, §6.4 what a fan is never asked). Dashboard §16.5 preferences · **§16.5a the announcement composer**. **RN §12 item 12 records that notification permission priming is specified by nobody** — `INFERENCE:` one is needed, since a cold OS prompt with no context is the classic way to lose the permission permanently; it is not invented in the RN spec either |
| **Event** | **COND-A + COND-B, and COND-D binds them.** `NOTIFICATIONS §4` **is** the outbox pipeline: `notify.emit_event` → `notify.outbox` → `drain_outbox` → `delivery`. `notify`-in with outbox-out is **not coherent**. |
| **Test id** | `T-RPC-NOTIFY-01..04` — **conditional on MD-10.** `-02` is notable: a mandatory type cannot be suppressed, asserted as `service_role` **and** as `postgres`. `-04`: `emit_event`/`enqueue` never raise — an injected constraint violation leaves the caller's transaction committed |
| **Package** | **`GAP` G-2.** Edge §8 assigns `076+`ᵃ, and its own footnote admits the spec "states only *these land at `076`+* and assigns no package". If Gate P: `092` — **not** `091` (a droppable stub, rule §6.7) and not earlier, because `notify.drain_outbox` reads `venue.promoter_link` and SEAM-1 floors it at `090`. **Count becomes 17 and the registry's "no gaps, no duplicates" assertion is falsified**, which is precisely why the ruling belongs to the owner |

---

### B3 · CRM export

| Cell | Value |
|---|---|
| **Product requirement** | A venue exports its own attendees to work them as a customer list, without that becoming a general extraction primitive. |
| **Architecture invariant** | **GP-3a** + the **one Layer-0 exception** (if the builder runs as `crm_export_builder` rather than `postgres`, that role is *subject to* the roster tables' RLS and needs explicit `<schema>_<table>_sel_svc_export` policies — **`BYPASSRLS` on that role is NOT an acceptable shortcut**; it would restore access to everything and delete the entire benefit. Owner decision **MD-2**) · **EX-4** (authority re-checked **live at download**: an export prepared before a revocation fails after it) · **C34** (Gate-L: provable erasure, PII-sink inventory) · **MD-8** (**platform roles read the roster; they do not use the venue CRM export** — a platform bulk extraction has a different justification, a different retention, and needs dual control; running it through the venue's surface would file a platform action in a venue's history) |
| **Table(s)** | `venue.export_job` · the `crm-exports` storage bucket (`public=false`, 32 MB, `allowed_mime_types={text/csv}`, path `{org_id}/{job_id}.csv` carrying **no venue name, no event title, no date, no filter, no segment**) · `kernel.org_customer_key` · `kernel.org_contact_consent` · `kernel.identity_contact_pref` |
| **RPC(s)** | `request_export` · `build_export_rows` (`DEF`) · `finalize_export` (`DEF`) · `authorize_export_download` · `revoke_export` · `list_export_jobs` · `sweep_expired_exports` (`DEF`) · `list_attendees` · `lookup_attendee` — nine (§17.22). `INFERENCE:` result shapes for five of them are authored in RPC §19 item 3; the CRM spec describes behaviour and idempotency and **no return shape** |
| **RLS / EXEC** | **Zero policies** on `export_job`, `org_customer_key`, `org_contact_consent`, `identity_contact_pref`, and **zero `storage.objects` policies for `anon` or `authenticated`** — *not a reduced set, none*. Authority is RLS §11.6 in full, including the two-template split: the **operations** template (money columns) is the narrowest allow-list in the document — `org_owner`, `org_admin`, `venue_manager` **only**; finance sees money and no contact, marketing sees contact and no money, **only these three hold the union** |
| **Edge function** | **`crm-export`** `/download` (Class **A**, live re-check at download, 300 s signed URL) and `/build` (**Class B-i/B-iii**, `verify_jwt=false`, `service_role` only, **authority re-derived from the job row's actor and scope, not from the caller**, claim lease + `UNIQUE(requested_by, command_key)`) |
| **RN / dashboard surface** | RN §4.8 contact opt-in at checkout + the venues list in Settings · Dashboard **D** §9.1 attendees list (**holder-keyed**, CRM K-1) · §9.2 search/filters · §9.4 detail drawer · §9.6 export · **K** §16.6 CRM/export controls |
| **Event** | **`—`** *why:* CRM export is explicitly listed in registry §7 as **unaffected by COND-A** — it carries its own scheduler (`pg_cron` + `pg_net` + a claim lease). It publishes no business fact in DA §6.1 and consumes none. This is a genuine `—`, not a hidden gap. |
| **Test id** | `T-RPC-CRM-01..07` · `T-RLS-CRM-01` (**no platform role can call `venue.request_export`** — the MD-8 boundary) · `T-RLS-CRM-02` (a `venue_marketing` at V1 of Org 1 is denied at V2 of the same org; `org_marketing` at Org 1 reaches all Org 1 venues and no Org 2 venue — the grain assertion) · `T-RLS-COL-01/02` |
| **Package** | **`087_venue_settlement_and_export`** (renamed for what it now carries) |

---

### B4 · Demographics and holder mix

| Cell | Value |
|---|---|
| **Product requirement** | A fan may optionally say something about themselves; a venue may see who is in the room in aggregate — and neither may become the other. |
| **Architecture invariant** | **C34** (Gate-L provable erasure; the erasure ledger is here at Gate P) · **RN §4.9 / the third un-challengeable rule**: **no demographic question at signup, at first launch, at onboarding, or anywhere in a purchase flow** · **GP-2 named exception (MD-9)** — `DELETE` on `kernel.identity_demographic` is permitted **inside the definer `clear_my_demographics` only**, because keeping a withdrawn gender answer as a tombstoned row would defeat the withdrawal; **the single GP-2 exception in the model, and a second must not be granted by analogy** · **the differencing-attack contract**: `get_holder_mix` has **exactly two parameters — adding a third is a design change requiring privacy re-review, not a routine enhancement** |
| **Table(s)** | `kernel.identity_demographic` · `kernel.identity_demographic_erasure` · `venue.holder_mix_snapshot` · `venue.holder_mix_bucket` |
| **RPC(s)** | `get_my_demographics` · `set_my_demographics` · `clear_my_demographics` (all three **parameterless or carrying no identity parameter of any type** — reading someone else's row must be *inexpressible*, not merely denied; **there is no staff write path and no `admin_set_demographics`**) · `venue.refresh_holder_mix` (`DEF`) · `venue.get_holder_mix` · `venue.reconcile_holder_mix()` — **`INFERENCE:` the last name is authored in RPC §19 item 4**; its source classifies it as a `NEW RPC` and never names it, and that source's own assertion list says *"all five RPCs"* while listing six |
| **RLS / EXEC** | **The grant set is EMPTY, not reduced**, and RLS is on with **no policy admitting `anon` or `authenticated`**. Denied on holder mix: `org_finance`, `venue_finance`, `venue_box_office`, `venue_scanner`, the door session, `promoter`, `platform_support`, `platform_risk`, `fan`, `anon` |
| **Edge function** | **`—`** *why:* no external provider, no secret, no non-JWT credential; edge §2's placement table admits none of these. |
| **RN / dashboard surface** | RN §4.9 "About you (optional)" · Dashboard **D** §9.5 the holder-mix breakdown card |
| **Event** | **`—`** *why:* registry §7 lists demographics as **unaffected by COND-A**; the rollup runs on its own `pg_cron` job. No DA §6.1 event names it as producer or consumer. Genuine `—`. |
| **Test id** | `T-RPC-DEMO-01` (**exactly two writer functions**) · `T-RPC-DEMO-02` (`get_holder_mix` arity is 2 — the differencing contract made mechanical). Plus the **reader-enumeration rule**: the set of functions/views/matviews referencing `kernel.identity_demographic` must be **exactly** `{get_my_demographics, set_my_demographics, clear_my_demographics, refresh_holder_mix}` — *and the assertion must carry a non-vacuity guard (it must be able to see all nine export functions), or an empty match set passes trivially.* |
| **Package** | **`077`** (the three `kernel.*` tables) · **`086`** (`holder_mix_snapshot`/`_bucket`) |

---

### B5 · Promoter codes

| Cell | Value |
|---|---|
| **Product requirement** | A promoter hands out a code; the buyer types it at checkout; the right promoter gets credited. |
| **Architecture invariant** | **D7** (the attribution row is written when the order is **paid**, never at creation) · **D8** (flat-per-ticket **or** %, `tier`, `party_kind` — the constitution's terms, not the schema's narrower `commission_bps`) · **O-2** (a promoter is never a staff-role label) · **the immutability rule**: **a promoter is explicitly forbidden from minting their own codes** — a self-minted code is a self-minted *distribution surface* over the org's global namespace, and codes are immutable, so a grab of `CLUBSPACE` or a rival's brand is permanent · **SoD** (`decide_flagged_attribution` denies **both** promoter-manager labels — a promoter manager adjudicating a flag against a promoter they recruited and are measured on is the fox at the henhouse) |
| **Table(s)** | `venue.promoter_code` · `venue.promoter_code_scope` · `venue.attribution_review` (**AO — `UPD` is `D` for every role including `platform_admin`; a wrong decision is corrected by appending `seq+1` and the effective decision is `max(seq)`**) · `venue.order.attribution_candidate_code_id` |
| **RPC(s)** | `create_promoter_code` · `create_promoter_codes_bulk` · `set_promoter_code_status` · `set_promoter_code_scope` · `set_promoter_code_window` · `preview_promoter_code` · `bind_order_attribution` · `review_attribution_flag` · `decide_flagged_attribution` |
| **RLS / EXEC** | `venue_promoter_code_sel_org`/`_sel_venue`/`_sel_promoter` and the `_scope` / `attribution_review` equivalents. **A code is a link's sibling and must not acquire a wider grant by being newer** — the matrix mirrors §9.17 exactly. The promoter reads `decision` + `reason_code` on their **own** attribution and **never** the reviewer's `note` (the venue's internal deliberation) or `displaced_promoter_id` (another promoter's identity) — **enforced by the read RPC's projection, not by hoping the client omits columns** |
| **Edge function** | **`promoter-code-preview`** — and the rate-limit adaptation recorded in RLS §11.8 as an adaptation of a frozen function's contract, **not a change to it** (10/min authenticated, 5/min anonymous per derived principal, **fail-closed**: 503 on limiter error, 429 over-limit) |
| **RN / dashboard surface** | RN §4.7 (the field is **advisory only, never a checkout gate**; `eligible` / `not_applicable`) · Dashboard **E** §10.5 codes · §10.6 attribution view (*must be sufficient to defend a dispute without engineering*) · §10.7 self-deal flag queue |
| **Event** | **COND-A** — DA §6.1 #31 `AttributionRecorded` (**Sync**, survives) and #32 `PromoterCommissionAccrued` (Async, does not). |
| **Test id** | `T-RPC-PROMO-01..11` · `T-RLS-ATTR-02` (a code-sourced attribution with `link_id IS NULL` **is** visible to its own promoter) |
| **Package** | **`090_venue_promoter_engine`** |

---

### B6 · Door manifest and offline verify

| Cell | Value |
|---|---|
| **Product requirement** | A door with no network still admits the right people and rejects a pass that was transferred away five minutes ago. |
| **Architecture invariant** | **O-4** (the scanner may sync an already-open manifest, scan and admit, and may **never** create, move or clear the boundary; **admission is never gated on manifest state**) · **O-5** (`door_open_at` is the cached monotone head of an append-only episode ledger; the effective boundary is **total and fail-closed** — `LEAST(door_open_at, COALESCE(doors_at, starts_at) + configured offset)` — so a NULL `door_open_at` can no longer mean "never frozen") · **C37** (offline is honestly *shrunk*, not closed) · **C33** (public-key-only door distribution) · **W-3 closure** (edge §5.4's offline verify performed **no `credential_version` comparison** and defined only a public-key manifest, so an offline door could not detect a stale pass at all — closed by §5.4.3 step 3b against **M2**) |
| **Table(s)** | `venue.door_manifest` · `venue.door_manifest_entry` (pinning per-atom `credential_version`, `signing_key_id`, `ticket_state`, `resale_state`) · `venue.door_manifest_delta` · `catalog.event_session.door_open_at` · `kernel.door_freeze_override` |
| **RPC(s)** | `open_door_manifest` · `close_door_manifest` · `append_door_manifest_delta` (`DEF`) · `engage_door_freeze` (`DEF`, **sole writer**) · `grant/revoke_door_freeze_override` · `sweep_expired_door_overrides` — **`GAP` G-15** (`get_door_manifest`, the read that delivers M2 to every scanner, is uncontracted), **G-14** (`set_door_open_at` / `set_event_security_config` have EXEC rows, no contracts, **and the first contradicts O-5's sole-writer property**), **G-16/G-17** (`U-5`/Δ11 dry-run, `U-6`/Δ12 device count), **G-21** (`sweep_implicit_door_freezes`) |
| **RLS / EXEC** | `venue_door_manifest_sel_venue` (+`_sel_platform`) · `venue_door_manifest_entry_sel_venue` · `venue_door_manifest_delta_sel_venue`. `kernel.door_freeze_override` is **audit-only: RLS on, ZERO policies**. `catalog.engage_door_freeze` **appears in no other EXEC row**, and *a trigger enforces this independently of grants* |
| **Edge function** | **`door-manifest`** (dual route) · **`door-session`** (Class **B-iii**, and **X-5**: it must derive `p_actor_device_id` server-side and never accept an attested human actor) |
| **RN / dashboard surface** | RN §7.1 step 3 (offline verify against **M2**) · §7.3 `awaiting_manifest` · Dashboard **G** §12.4 manifest status and the transfer freeze · §12.5 live scan board · §12.8 offline |
| **Event** | **COND-A, blocking.** Registry §7 names *"the door-manifest open transaction as specified"* among the four things that break under COND-A = NO: its steps are all-or-nothing and **the last one writes the envelopes**. Scanner push-to-sync is on the same list. |
| **Test id** | `T-RPC-DOOR-09..16` · `T-RLS-DOOR-09` (a drained atom then scans — the end-to-end lockout regression) · `-10` (six named principals refused ⇒ `42501`, `door_open_at` unchanged) · `T-RPC-DOOR-11` (a re-open leaves `door_open_at` **byte-identical**) · `-13` (an override expires **with no sweep having run** — the assertion that proves the arithmetic, not the cron, is load-bearing) · `-14` (direct writes to `door_open_at` raise) · `T-RLS-COL-04` |
| **Package** | **`086_venue_door_and_scan`** (with the O-5 trigger created here and attached to the `078` table, FR-6) |

---

## 6. THE FIVE OWNER RULINGS — capabilities `C1`–`C5`

These are not separate build items; they are **properties** the rows above must exhibit. They get their own
blocks because a ruling that is designed-to but never asserted is indistinguishable from a ruling that was
ignored.

---

### C1 · O-1 — refund authority is a request door

| Cell | Value |
|---|---|
| **Product requirement** | An operator can start a refund for their own org's order; a person other than the requester approves it above a threshold; nobody executes the money writer directly. |
| **Architecture invariant** | **O-1** · **R7** (no new object writes a money row) · **C36** (`kernel.org_member.role` is single-valued, so no `org_owner` row can ever satisfy `has_org_role([org_finance])` — which is why DA §7.2's *"Inherits: Org Admin, Org Finance"* is **deleted as a money mechanism** and the authority moves to the `org_owner` label explicitly) |
| **Table(s)** | `kernel.approval_request` (`077`) · `kernel.refund` (`085`) · `venue.order` · `kernel.tickets.resale_state = refund_hold` |
| **RPC(s)** | `request_order_refund` · `approve_refund_request` · `cancel_refund_request` · `sweep_expired_refund_requests` (`DEF` — **"not optional: without it a parked request is an unbounded denial-of-admission on a paying customer's ticket"**) · `list_org_refunds` · `refund_primary_order` (narrowed to `DEF` + platform) |
| **RLS / EXEC** | RLS §11.3. **`org_admin` and every venue role are forbidden callers.** `approve_refund_request` requires `auth.uid() <> request.requested_by` **and self-approval is its own named failure**, so the UI can say *"a different person must approve this"* rather than returning a bare 403 |
| **Edge function** | **`refund-execute`** (Class **A** — second-approver SoD named explicitly by money §8.3(c)) |
| **RN / dashboard surface** | RN §4.10 refund states on a ticket · Dashboard **H** §13.3/§13.3a (**"authority is tiered, not blanket — and the operator must learn the tier from the product"**) · §13.7 the approval queue |
| **Event** | **COND-A** — #27 `RefundIssued` (**Sync** with ticket void if full; the async notification consumers do not survive) |
| **Test id** | `T-RPC-MONEY-01..14` · `T-RLS-MONEY-01` · `T-RLS-MONEY-02` |
| **Package** | **`077`** (`approval_request`) · **`085`** (the nine money-authority RPCs). **Note the placement argument:** `approval_request` is in `077` and not `085` because its *earliest* consumer is not a money flow — it is `catalog.set_platform_config`'s money-key dual control, which must be authored in `078`; putting the table in `085` would make `078` forward-reference `085` |

---

### C2 · O-2 — the canonical role model

| Cell | Value |
|---|---|
| **Product requirement** | Eight role concepts an operator can name, backed by fifteen stored labels no code can confuse across planes. |
| **Architecture invariant** | **O-2** + **C36** + **RM-1** (every role label MUST begin with its plane token) · **RM-2** (no bare role-string comparison, no display name, in any policy or RPC body) · **D5** (the four pre-C36 bare-label lists are purged from the constitution itself) · **D6** (DA §7.6 keeps **one** money matrix; ROLE_MODEL §5 governs non-money capability detail and §7.6's money rows govern over it) |
| **Table(s)** | `kernel.org_member.role` (6 labels) · `venue.staff_role.role` (6) · `kernel.platform_role.role` (3) — all **`text` + `CHECK`, not native enums**, so the fifteen-label commitment stays correctable while the tables are empty (OD-6 / RLS X-3) |
| **RPC(s)** | The nine predicate helpers — **the ONLY sanctioned way to test a role**: `has_org_role` · `has_venue_role` · `has_event_role` · `is_platform` · `has_org_role_over_venue` · `has_org_role_over_event` · `is_org_affiliate` · `is_promoter_for_event` · `assert_door_session` |
| **RLS / EXEC** | `kernel_org_member_sel_*` · `venue_staff_role_sel_*` · `kernel_platform_role_sel_*`, all three under **I-12** |
| **Edge function** | **`—`** *why:* edge §0.5 — EA-1 does not move authority into the edge; it makes the edge stop *destroying* the authority the RPC was written to check. No edge function tests a role. |
| **RN / dashboard surface** | Dashboard §5 role × surface matrix · §5.1 (**the four new labels are an amendment, not an extension**) · §15.2 (the venue role picker **must now offer six labels**) |
| **Event** | **`—`** *why:* a role model is a predicate substrate, not a business fact. DA §6.1 names no role event. Genuine `—`. |
| **Test id** | `T-RLS-ROLE-01` (the three columns admit **exactly** the fifteen labels and **reject every `org_*` label on the venue enum and vice-versa**) · `T-RLS-ROLE-02` (**RM-2**, asserted over policy *and* function bodies) · `T-RLS-ROLE-03`/`T-RPC-ROLE-05` (`assert_door_session` in no `pg_policy` — **RM-5**) · `T-RPC-ROLE-01..04` · `T-RLS-FORCE-01..04` |
| **Package** | **`077`** (org + platform) · **`080`** (venue) |

---

### C3 · O-3 — payout visibility and requests

| Cell | Value |
|---|---|
| **Product requirement** | An owner can see what they are owed and ask for it. Changing where the money goes is a different, stronger act. |
| **Architecture invariant** | **O-3**, ratified **with** its compensating controls and not as an unqualified grant. **The ruling collapses SoD-1 by construction** — before it, `org_owner`-only destination change satisfied separation of duties *automatically*, because owners could not disburse; O-3 puts both halves of the named fraud primitive ("redirect the bank account, then release funds to it") in one identity. The compensations: a **permanent** requester-vs-setter identity split (**explicitly not a cool-down, which an attacker simply waits out**), **destination probation** (the first payout after a change is created `held`, released only by platform risk/admin), and **out-of-band notification to every `org_owner`/`org_finance` including the actor**. The existing cool-down is **retained but demoted to a detection window, the weakest control in the set** |
| **Table(s)** | `kernel.payout` · `kernel.organization.payout_destination_set_by` · `kernel.approval_request` · `venue.settlement` |
| **RPC(s)** | `list_org_payouts` · `request_org_payout` · `set_org_payout_destination` (**`org_owner` ONLY; `org_finance` excluded entirely**) · `hold_payout` / `release_payout` (**`is_platform` only, SoD-3, no org role ever** — DA §7.6 previously marked Org Finance ✔ on *Release held funds*, which is the control inverted; corrected to blank) |
| **RLS / EXEC** | `kernel.payout` carries **zero policies**; authority is RLS §11.3. `venue_finance` is narrowed to **settlement-caused** payouts for its own venue, because `kernel.payout` has no `venue_id` and an unqualified "own-venue payouts" **was never expressible** |
| **Edge function** | **`payout-execute`** (Class **A** — SoD refusal and step-up `aal`/`amr` named explicitly by money §8.3(c)) |
| **RN / dashboard surface** | Dashboard **I** §14.5 payouts · **K** §16.3 payout account · §16.9 re-authenticate for a money action · §15.4 finance permissions written out |
| **Event** | **COND-A** — #25 `PayoutReleased` (Async **by design**) · #26 `PayoutFailed`. **The out-of-band notification O-3 requires as a compensating control is itself COND-A + COND-B dependent** — `INFERENCE:` if both rulings land negative, one of the three named mitigations for the SoD-1 collapse has no carrier. |
| **Test id** | `T-RLS-MONEY-03` — **`request_org_payout` by the destination-setter raises `sod_violation` *after* the cool-down has elapsed.** That "after" is the whole assertion: it is what distinguishes the ratified permanent split from the demoted cool-down · `T-RLS-MONEY-04` · `T-RLS-MONEY-01` |
| **Package** | **`077`** (`payout_destination_set_by`) · **`085`** (`kernel.payout` + the RPCs) |

---

### C4 · O-4 — door-manifest authority

| Cell | Value |
|---|---|
| **Product requirement** | The person who opens the door is not the person scanning at it. |
| **Architecture invariant** | **O-4** — authority is expressed **inside the RPC predicate (org→venue inheritance, never by widening venue RLS)**. The consequence is stated rather than left implicit: *a person granted `venue_manager` for box-office selling thereby also gains manifest-open authority until per-capability scoping ships.* **Admission is never gated on manifest state** — the manifest gates offline scanning only |
| **Table(s)** | `venue.door_manifest` · `catalog.event_session` · `venue.staff_role` · `venue.door_pin` |
| **RPC(s)** | `open_door_manifest` · `close_door_manifest` — **`GAP` G-14** (`set_door_open_at` O4-3 and `set_event_security_config` O4-4 are named in the O-4 authority row and contracted nowhere), **G-15** (`get_door_manifest`) |
| **RLS / EXEC** | RLS §11.4. **`venue_scanner`, the door session, `venue_box_office`, every finance / marketing / promoter role, `platform_support` and `platform_risk` are explicitly excluded.** Disabling a transfer freeze is `platform_admin` under step-up |
| **Edge function** | **`door-manifest`** (the staff-JWT route is Class **A**; the PIN route is Class **B-iii** — and *the door PIN is deliberately weaker than a JWT, which is why O-4 denies the door principal the manifest-open authority*) |
| **RN / dashboard surface** | Dashboard **G** §12.4 (Δ1's door-manifest role list **drops the door principal** — RLS X-6) · RN §7 scanner |
| **Event** | **COND-A** — the open transaction's last step writes the envelopes |
| **Test id** | `T-RLS-DOOR-10` — six named principals may not `open_door_manifest` ⇒ `42501` **and `door_open_at` is unchanged**. The second half is the real assertion: a refusal that still moved the boundary would be worse than an allow · `T-RPC-DOOR-10` · `T-RLS-DOOR-04` (admission gated by **session status, not manifest state**) |
| **Package** | **`086`** |

---

### C5 · O-5 — the `door_open_at` lifecycle

| Cell | Value |
|---|---|
| **Product requirement** | Transfers close when the doors open, and stay closed. |
| **Architecture invariant** | **O-5** — the column was **written by nothing** in the frozen contract set, *which makes the C6/C23/C43 transfer freeze and the stale-pass safety property the design claims false.* Ratified form: the cached monotone head of an append-only door-episode ledger (`MIN(opened_at)`), **the same head-of-ledger pattern already ratified for `current_owner_id` and `credential_version` under C27**. Never cleared by close, never moved backwards — **monotonicity becomes arithmetic, not a rule someone must remember**. The effective boundary is **total and fail-closed**. Override is explicit, elevated, TTL-bounded, reason-coded, audited, **and never moves the boundary** |
| **Table(s)** | `catalog.event_session.door_open_at` · `venue.door_manifest` (the episode ledger) · `kernel.door_freeze_override` |
| **RPC(s)** | `catalog.engage_door_freeze` (`DEF`, **the sole writer**) · `catalog.effective_freeze_at` · `kernel.is_transfer_frozen` · `grant/revoke_door_freeze_override` · `sweep_expired_door_overrides` — **`GAP` G-14: `venue.set_door_open_at` has an EXEC row and directly contradicts the sole-writer property.** |
| **RLS / EXEC** | RLS §11.4. `engage_door_freeze` **appears in no other EXEC row** and *a trigger enforces this independently of grants* (`catalog.tg_door_open_at_is_ledger_head`, created in `086` and attached to the `078` table per FR-6) |
| **Edge function** | **`—`** *why:* edge §9 recon #6 (CLOSED): *the edge layer never decides freeze independently* — it, the client, and every RPC recheck all target `kernel.is_transfer_frozen`. No stored `transfer_frozen` column exists. |
| **RN / dashboard surface** | RN §4.4.1/§4.5 (Transfer/Sell gating; copy *"Transfers are closed while the event is underway"*) · Dashboard **G** §12.4 |
| **Event** | **COND-A** — the freeze engagement rides on the manifest-open transaction |
| **Test id** | `T-RLS-DOOR-08` / `T-RPC-DOOR-08` (**NOT NULL over every status × nullability combination** — the totality property that makes fail-closed real) · `T-RPC-DOOR-11` (a re-open leaves `door_open_at` **byte-identical**) · `T-RPC-DOOR-13` (an override expires **with no sweep having run**) · `T-RPC-DOOR-14` (direct writes raise) |
| **Package** | **`078`** (the column) · **`079`** (`is_transfer_frozen` + `door_freeze_override`, resolved from FR-7) · **`086`** (the ledger, the writer and the trigger) |

---

## 7. CROSS-CUTTING — capabilities `D1`–`D4`

---

### D1 · Guest list and comps

| Cell | Value |
|---|---|
| **Product requirement** | "Maya's list" at the door, and comped tickets that are accountable to the staff member who issued them. |
| **Architecture invariant** | **C39** (comp/guest-list issuance above a per-staff threshold requires step-up + a **C9 live-table grant re-check**) — `RATIFIED-MODELED-ONLY(GATE-L)` · **O-2** (the allocate/issue split: allocating comp *capacity* is an inventory decision and `venue_box_office` is **denied**; issuing **one** comp against an already-allocated batch is an issuance operation, which is exactly what O-2 grants box office *and nothing more*) · **the insider-fraud control**: per-staff comp totals stay visible to `venue_manager` and above — *hiding them defeats the control* |
| **Table(s)** | `venue.comp_allocation` · `venue.guest_list` · `venue.guest_entry` |
| **RPC(s)** | **`GAP` G-4** (`allocate_comp`, `issue_comp` — EXEC rows with a fully argued split authority model and **no contracts**) · **`GAP` G-10** (`U-1`: create list · add guest · remove entry — *"guest-list CRUD RPCs"* and nothing else) · **`GAP` G-9** (`U-2`: mark a guest arrived — **a door hits this a thousand times a night and RLS §9.16 note 39 already grants exactly that narrow update**) |
| **RLS / EXEC** | `venue_comp_allocation_sel_venue` · `venue_guest_list_sel_venue` · `venue_guest_entry_sel_venue`. Authority: RLS §11.1 (allocate vs issue) and §9.16 note 39 (the door's narrow guest-entry update) |
| **Edge function** | **`—`** *why:* the door reaches these through `door-session`; no separate function is needed and edge §2 proposes none. |
| **RN / dashboard surface** | Dashboard **F** §11 in full (§11.1 the distinction that must be on screen, §11.2 lists, §11.3 comp allocation, §11.4 comp accountability, §11.5 door state) |
| **Event** | **`—`** *why:* DA §6.1's 36-event catalog names no comp or guest-list event, and C11 trimmed the catalog deliberately. A guest arriving is a `ScanAdmitted` (#22) when it is a ticket; a guest-list check-in is not a custody fact. Genuine `—`. |
| **Test id** | **`GAP` G-8b(i)** — **asserted by neither surface.** No `T-*` group covers comps or guest lists, and plan §8 `086`'s Tests row — which is long and detailed on scans, PINs, manifests and holder mix — **does not mention them at all**. The C39 threshold and the box-office allocate/issue asymmetry are *named insider-fraud controls* with no assertion anywhere in the corpus. |
| **Package** | **`086`** |

**This is the worst single row in the matrix**: three `GAP`s in `RPC`, one in `TEST`, against a surface the
dashboard specifies in five subsections and an authority model RLS argues in detail. It is the clearest
instance of the corpus's outside-in shape.

---

### D2 · Operational activity feed

| Cell | Value |
|---|---|
| **Product requirement** | A venue can see its own operational history without asking an engineer. |
| **Architecture invariant** | **OBS-1**-adjacent audit discipline · **RPC §0.3** (every privileged mutation writes an audit row) · the read's own constraint: it must **exclude the security plane** — key rotation, platform overrides, risk actions, auth events, RLS denials — and return **plain verbs with no `before`/`after` payloads** |
| **Table(s)** | `kernel.admin_audit` (AO) |
| **RPC(s)** | `venue.read_operational_audit(p_scope_kind, p_scope_id, p_filters, p_cursor)` (§17.26, dashboard Δ2) |
| **RLS / EXEC** | `kernel.admin_audit` carries **zero policies**; RLS §7.12 makes it `is_platform`-readable only, which is *precisely why* the definer read exists — **a venue principal otherwise has no path to its own operational history** |
| **Edge function** | **`—`** *why:* a scoped read with no provider and no secret. |
| **RN / dashboard surface** | Dashboard **L** §17 in full, including §17.2 *"what this is explicitly NOT"* |
| **Event** | **`—`** *why:* DA §6.1 #36 `AdminActionPerformed` exists, but its own payload note says **"audit is the source"** — the audit table is the system of record and the event is a derived analytics copy. Reading it emits nothing. Genuine `—`. |
| **Test id** | **`GAP` G-8b(ii)** — no test in either surface asserts the security-plane exclusion, and **that exclusion is the entire security property of the read**. A `read_operational_audit` that leaks key rotations, platform overrides, risk actions or RLS denials into a venue's activity feed would look correct to every other assertion in the corpus. |
| **Package** | **`077`** (`kernel.admin_audit`) |

---

### D3 · Stripe Connect onboarding

| Cell | Value |
|---|---|
| **Product requirement** | An org connects a Stripe account so it can be paid. **Nothing in the money plane works until this completes.** |
| **Architecture invariant** | **R7** · **OBS-1** (the frozen `public.payments` boundary) · **O-3** (the destination the payout targets) |
| **Table(s)** | `kernel.organization` (the connect reference + capability flags) |
| **RPC(s)** | **`GAP` G-3 — `kernel.set_org_connect_ref` is contracted nowhere.** Edge §9 recon #12 states it plainly: *"§3.3 wraps it; it appears in neither `PHASE_2_RPC_FUNCTION_CONTRACTS.md` nor RLS §11's EXEC table. RPC-spec owner to contract it (role: `has_org_role([org_owner, org_finance])`), or §3.3 has no write path."* |
| **RLS / EXEC** | **`GAP` G-3** — no EXEC row exists either. `kernel_organization_sel_org` covers the *read* of the connect reference (column-scoped per RLS §7.2); nothing covers the write |
| **Edge function** | **`connect-onboarding`** (Class **A**, `has_org_role([org_owner,org_finance])`, idempotency `connect_org_${org_id}`) — **specified in full, wrapping a function that does not exist** |
| **RN / dashboard surface** | Dashboard **K** §16.3 payout account |
| **Event** | **COND-A**, and **additionally has no producer**: DA §6.1 #2 `ConnectOnboardingCompleted` (consumers `venue`, `market`, `analytics`; idempotency key `connect_account_id + capabilities_hash`). The fact it publishes is written by the missing RPC. |
| **Test id** | **`GAP`** — there is nothing to test. `077`'s Tests row asserts the org tables' RLS and the role predicates; **no assertion anywhere names a connect reference, a capability flag, or the write that sets them.** |
| **Package** | **`077`** for the table; the RPC has no package because it has no contract |

**Severity note:** this is the only capability in the matrix where the **edge function is fully specified and
classified** and the DB write it wraps **does not exist in any spec**. Every other `GAP` leaves a surface
under-specified; this one leaves a payment-infrastructure precondition unimplementable.

---

### D4 · The event outbox — the carrier itself

| Cell | Value |
|---|---|
| **Product requirement** | None directly. It is the transport on which four other capabilities depend. |
| **Architecture invariant** | **C51 / decision O7** · **C12** (the event envelope: per-aggregate monotonic `sequence`, `causation_id`, `correlation_id`, at-least-once + idempotent consumers) · **C48** (projection-rebuild retention floors — outbox compaction respects canonical-input retention) · **C49** (poison-quarantine, partitioned/multi-drainer, specified region hand-off — both Gate L) · **DA Principle 20** (*"transactional only where an invariant demands it"*; the same-tx set is the closed, enumerated SSCAS) · **the anti-over-engineering guarantee**: *"the only new infrastructure Phase 2 introduces is one outbox table and a drainer on the cron that already runs"* |
| **Table(s)** | **`GAP`** — `notify.outbox` under COND-B Gate P, `kernel.event_outbox` otherwise. The sole occurrence of the word "outbox" in the physical schema spec sits **inside the Gate-L list** ("projection checkpoints … + outbox retention/compaction") |
| **RPC(s)** | **`GAP`** — a drainer on the existing 2-minute `pg_cron` heartbeat. `notify.emit_event` / `enqueue` / `drain_outbox` exist as contracts, and are themselves unscheduled under COND-B |
| **RLS / EXEC** | **`—`** *why:* zero policies, `REVOKE ALL` — it is a machine table with no human reader, exactly like `notify.delivery` and `notify.schedule`. This cell would be `—` even after the ruling. |
| **Edge function** | **`—`** *why:* a `pg_cron` + in-process drainer by design; DA §6.3 is explicit that no broker, queue service or saga framework ships until real load justifies it, and *"the drainer's target swaps to a real bus later — the event catalog and idempotency keys do not change."* |
| **RN / dashboard surface** | **`—`** *why:* infrastructure. |
| **Event** | **`GAP`** — **all 36 events in DA §6.1 name this as their carrier.** ~10 are `Sync` and survive without it (they are same-transaction calls, not messages); the rest do not. |
| **Test id** | **`GAP`** — no test id anywhere in the corpus references an outbox, an envelope column, `sequence`, `causation_id` or `correlation_id` |
| **Package** | **`GAP`** — `076` if ratified (zero FK dependencies, so no producer package gains an edge) |

---

## 8. EVENT REGISTER — producer, consumer, carrier, for all 36

**All 36 events lack a carrier (COND-A).** Roughly nineteen carry a `Sync` arm and survive without one — a
`Sync` event is a same-transaction call, not a message. The rest do not exist at MVP under COND-A = NO.

**Which contexts exist in Phase 2:** `kernel`(core) · `catalog` · `venue` · `market` are built.
**`social` and `analytics` are deferred schemas (C11)**, `notify` is COND-B, and **no `risk` table exists in
any of the sixteen packages**. A consumer in a context that is not built is not a consumer.

| # | Event | Producer status | Consumer status | Carrier |
|---|---|---|---|---|
| 1 | `OrganizationCreated` | ✓ `kernel.create_organization` | **NONE BUILT** — `analytics`, `(social)` only | COND-A |
| 2 | `ConnectOnboardingCompleted` | **NO PRODUCER — G-3** (`set_org_connect_ref` is uncontracted) | ✓ `venue`, `market` | COND-A |
| 3 | `VenueApproved` | ✓ `catalog.approve_venue` | ✓ `venue` (`social`/`analytics` not built) | COND-A |
| 4 | `EventPublished` | ✓ `catalog.publish_event` | ✓ `venue`, `market` | COND-A |
| 5 | `TicketTypeOpened / TierUnlocked` | **PARTIAL — no tier concept exists** in `venue.ticket_type` in any package, so the `TierUnlocked` arm has no producer | ✓ `market` (eligibility) | COND-A |
| 6 | `InventoryHeldExpired` | **NO PRODUCER — G-24** (the hold-expiry sweep is named nowhere) | ✓ `venue` (counters) | COND-A |
| 7 | `OrderPlaced (pending)` | ✓ `venue.create_primary_checkout` | ✓ `kernel` | **Sync — survives** |
| 8 | `PaymentAuthorized` | ✓ `stripe-webhook` | ✓ `venue`/`market` | **Sync / webhook-idempotent — survives** |
| 9 | `PaymentCaptured` | ✓ `stripe-webhook` | ✓ `venue`, `market` | **Sync — survives** |
| 10 | `TicketIssued` | ✓ `kernel.issue_ticket_atoms` | ✓ `venue`, `market` | **Sync — survives** |
| 11 | `TicketReserved` | ✓ `venue.reserve_primary_inventory` | ✓ `venue` | COND-A |
| 12 | `ListingCreated` | **NO CONTRACTED PRODUCER — G-5** (`market.create_listing`) | ✓ `kernel` (lock, native only) | **Sync (native) — survives *if* the writer is contracted** |
| 13 | `BidPlaced` | **NO NAMED PRODUCER — G-5** (RLS §11.1 says *"bid RPC"*) | ✓ `market` | **Sync — same condition** |
| 14 | `OfferMade / OfferAccepted` | **NO CONTRACTED PRODUCER — G-5** | ✓ `market`, `kernel` | **Sync on accept — same condition** |
| 15 | `AuctionWon` | **PARTIAL** — the existing `auto-finalize-auctions` edge function is external-rail and edge §8 states it is **untouched by this spec**; no native auction finalizer is contracted | ✓ `kernel` | **Sync — same condition** |
| 16 | `ListingSold (buy-now)` | **NO CONTRACTED PRODUCER — G-5** | ✓ `kernel` | **Sync — same condition** |
| 17 | `OwnershipTransferred` | ✓ `kernel.transfer_ticket_ownership` | ✓ `venue`, `market` | **Sync — survives** |
| 18 | `TransferStarted (p2p)` | ✓ `market.create_p2p_transfer` | ✓ `kernel`; **`notifications` is COND-B** | Sync lock survives; Async notify does not |
| 19 | `TransferAccepted` | ✓ `market.accept_p2p_transfer` | ✓ `kernel` | **Sync — survives** |
| 20 | `TransferExpired` | ✓ `market.sweep_expired_p2p_transfers` | ✓ `kernel`; `notifications` COND-B | **Cron-swept — survives** (a DB sweep, not an outbox consumer) |
| 21 | `CredentialInvalidated` | ✓ (rides on #17) | ✓ `venue` (scan manifests) | **Sync — survives** |
| 22 | `ScanAdmitted` | ✓ `venue.record_scan` | ✓ `kernel`; **`risk` NOT BUILT**; `analytics` not built | **Sync online survives; the offline arm is outbox-reconciled and does not** |
| 23 | `ScanRejected` | ✓ `venue.record_scan` | **NONE BUILT** — `risk`, `analytics` only | COND-A |
| 24 | `SettlementClosed` | ✓ `kernel.close_settlement` | ✓ `kernel` (payout generation) | **Sync — survives** |
| 25 | `PayoutReleased` | ✓ `kernel.release_payout` | ✓ `venue`, `market`; `notifications` COND-B | COND-A (**Async by design** — deferred deliberately) |
| 26 | `PayoutFailed` | ✓ `payout-execute` | ✓ `venue`/`market`; `notifications` COND-B; `risk` not built | COND-A |
| 27 | `RefundIssued` | ✓ `kernel.refund_primary_order` | ✓ `venue`/`market`; `notifications` COND-B; `risk` not built | **Sync with ticket void (if full) — survives** |
| 28 | `TicketVoided` | ✓ `kernel.void_ticket_atom` | ✓ `venue`, `market` | **Sync — survives** |
| 29 | `DisputeOpened (chargeback)` | **NO PRODUCER — no dispute or chargeback table exists in any of the sixteen packages** (C30 is Gate-M, modeled only) | ✓ `kernel` (freeze payout) | Sync freeze would survive — **if the producer existed** |
| 30 | `DisputeResolved` | **NO PRODUCER** — same | ✓ `kernel` | same |
| 31 | `AttributionRecorded` | ✓ `venue.resolve_order_attribution` | ✓ `kernel` (commission payout) | **Sync, same tx as OrderPaid (D7) — survives** |
| 32 | `PromoterCommissionAccrued` | **NO CONTRACTED PRODUCER — G-7** (`kernel.pay_promoter_commission`) | ✓ `venue` | COND-A |
| 33 | `FriendJoinedEvent` | **NO PRODUCER** — `social` is a deferred schema | **NONE BUILT** | COND-A |
| 34 | `ReferralCompleted` | **NO PRODUCER** — `social` deferred | ✓ `venue`/`kernel` (credit) | COND-A |
| 35 | `RiskFlagRaised` | **NO PRODUCER — no risk-plane table exists in any package** | ✓ `market`/`venue` (gating), admin | COND-A |
| 36 | `AdminActionPerformed` | ✓ every privileged mutation (RPC §0.3) | **NONE BUILT** — `analytics` only; the row's own payload note says *"audit is the source"*, so the audit table is the system of record and the event is a derived copy | COND-A |

### 8.1 Events with no producer — thirteen

**#2** (G-3) · **#5** tier arm · **#6** (G-24) · **#12 · #13 · #14 · #16** (G-5) · **#15** (partial) ·
**#29 · #30** (no dispute plane) · **#32** (G-7) · **#33 · #34** (`social` deferred) · **#35** (no risk
plane). **Seven of the thirteen are downstream of a `GAP` already in §1** — the missing producer *is* the
missing RPC. The other six are contexts Phase 2 deliberately does not build, and are honest `—`s **provided
the catalog says so**, which it does not (see G-25).

### 8.2 Events with no consumer in Phase 2 — four, plus a systematic one

**#1 · #23 · #33 · #36** have **zero** built consumers. Beyond those, **every event whose consumer list is
`analytics` and/or `social` loses that consumer**, because C11 ships both as deferred schemas — that is
**28 of the 36 rows**. And every `notifications` consumer is COND-B.

### 8.3 G-25 — the catalog says 36 and the ratification says ~16, and nothing reconciles them

**`S2`, owner: `SNATCH_IT_DOMAIN_ARCHITECTURE.md` §6.1.** Ratified row **C11** states the 36-event catalog
*"is trimmed to the ~10 invariant-bearing sync calls + ~6 real outbox events"*. **DA §6.1 still lists all
36 rows**, and **no document anywhere says which sixteen survive the trim.** The consequence is not
cosmetic: under COND-A the only question that matters is *which events must have a carrier*, and the
ratified answer is "about six" while the catalog presents thirty-six with no marking. An implementer sizing
the outbox, or an owner pricing the O7 ruling, is reading a list that a ratified correction already
reduced by more than half.

---

## 9. TEST-ID REGISTER — every id, and the capability that claims it

Discharges **RLS §17 X-9** (*"Every `T-RLS-*` id of §16.11 and every policy name of §16.10 needs a matrix
row"*). **Every id below is claimed by at least one capability. There are no orphan test ids.**

### 9.1 `T-RLS-*` — 35 ids in 33 register rows

| ID | Capability |
|---|---|
| `T-RLS-FORCE-01..03` (3 ids) | **A2**, **A5**, **C2** |
| `T-RLS-FORCE-04` | **C2** |
| `T-RLS-DOOR-01` | **A4** (the CRITICAL regression) |
| `T-RLS-DOOR-02`, `-03`, `-04` | **A9**, **C4** |
| `T-RLS-DOOR-05` | **A4**, **A11** |
| `T-RLS-DOOR-06` | **A3**, **A8** |
| `T-RLS-DOOR-07` | **A11** |
| `T-RLS-DOOR-08` | **A3**, **C5** |
| `T-RLS-DOOR-09` | **A9**, **B6** |
| `T-RLS-DOOR-10` | **C4**, **B6** |
| `T-RLS-EDGE-01`, `-02` | **A8** (and every Class-A edge row) |
| `T-RLS-POL-01`, `-02`, `-03` | **A1**–**A13** globally; `-03` is the one that names `notify_notification_upd_owner` as the single exception (**B2**) |
| `T-RLS-COL-01`, `-02` | **B3** (and §6 tier-2 tables globally) |
| `T-RLS-COL-03` | **A7**, **B1** |
| `T-RLS-COL-04` | **A9**, **B6** |
| `T-RLS-ROLE-01`, `-02` | **C2** |
| `T-RLS-ROLE-03` | **C2**, **A9** |
| `T-RLS-ROLE-04` | **A5**, **C2** |
| `T-RLS-ATTR-01` | **A6**, **A12** |
| `T-RLS-ATTR-02` | **A12**, **B5** |
| `T-RLS-MONEY-01` | **A8**, **C1**, **C3** |
| `T-RLS-MONEY-02` | **C1** |
| `T-RLS-MONEY-03` | **C3** |
| `T-RLS-MONEY-04` | **A10**, **C3** |
| `T-RLS-CRM-01`, `-02` | **B3** |

### 9.2 `T-RPC-*` — 70 ids in 12 group rows

| ID range | Capability | Note |
|---|---|---|
| `T-RPC-DOOR-01..04` | **A4**, **A9** | `-01` is the structural guard against the CRITICAL defect recurring |
| `T-RPC-DOOR-05..08` | **A9**, **C5** | the freeze set. **`-05` and `-06` exist only as bare suffixes in §18 — G-23** |
| `T-RPC-DOOR-09..16` | **B6**, **C4**, **C5** | the lifecycle set |
| `T-RPC-MONEY-01..14` | **A8**, **C1**, **C3** | |
| `T-RPC-ROLE-01..05` | **C2**, **A5**, **A9** | |
| `T-RPC-ATTR-01..04` | **A6**, **A12** | |
| `T-RPC-PROMO-01..11` | **A12**, **B5** | |
| `T-RPC-DEMO-01..02` | **B4** | `-02` is the differencing-attack contract made mechanical |
| `T-RPC-CRM-01..07` | **B3** | |
| `T-RPC-WALLET-01..03` | **A7**, **B1** | |
| `T-RPC-NOTIFY-01..04` | **B2** | **conditional on MD-10. `-02`, `-03`, `-04` exist only as bare suffixes — G-23** |
| `T-RPC-GLOBAL-01..04` | **A1**–**D3** globally | structural posture, not behaviour. **`-02`, `-03`, `-04` exist only as bare suffixes — G-23** |

**Orphan check — the instrument's own null result:** every `T-RLS-*` and every `T-RPC-*` id in the corpus
maps to at least one capability. **The traffic runs the other way**: capabilities without ids (§3's eight
`✓ᵖ` rows and four `GAP` rows), not ids without capabilities.

---

## 10. POLICY-NAME REGISTER — every name in RLS §16.10, and its capability

Also discharges **X-9**. **No policy in §16.10 is unclaimed.**

| Policy family | Capability |
|---|---|
| `catalog_venue_sel_anon` · `_sel_org` · `_sel_venue` | **A3** |
| `catalog_event_sel_anon` · `_sel_org` · `_sel_venue` | **A3** |
| `catalog_event_session_sel_anon` · `_sel_org` · `_sel_venue` | **A3**, **C5** |
| `catalog_platform_config_sel_public` · **`catalog_platform_config_sel_restricted`** (`AUTHZ-CFG1` / **C71**) | **A3**, **A8**. **TWO classes, not one — and COND-C's premise is corrected, not preserved.** `_sel_public` is `USING (visibility = 'public')`; `_sel_restricted` requires `is_platform([platform_admin, platform_risk])`. The table is **not** world-readable: money, `authn.*`, `comp.*`, `crm.*` and `door.*` keys are `restricted`. The blanket public-read this row previously asserted is the exact defect **C71** was raised against — it published every dual-control ceiling, step-up window and export cap to `anon`. Any `COND-C` reasoning resting on world-readability must be re-derived |
| `catalog_resale_policy_sel_public` | **A3**, **A11** |
| `kernel_identity_ext_sel_owner` | **A2** |
| `kernel_organization_sel_org` · `_sel_platform` | **A2**, **D3** |
| `kernel_org_member_sel_org` · `_sel_platform` | **A2**, **C2** (**I-12**) |
| `kernel_org_invite_sel_invitee` · `_sel_org` | **A2** |
| `kernel_platform_role_sel_platform` | **A2**, **C2** (**I-12**) |
| `kernel_signing_key_sel_public` | **A7** |
| `kernel_tickets_sel_owner` · `_sel_venue` · `_sel_platform` | **A4** |
| `venue_staff_role_sel_venue` · `_sel_org` · `_sel_platform` | **A5**, **C2** (**I-12**) |
| `venue_ticket_type_sel_public` · `_sel_venue` | **A5** |
| `venue_inventory_batch_sel_public` · `_sel_venue` | **A5** |
| `venue_inventory_hold_sel_owner` · `_sel_venue` | **A5** |
| `venue_order_sel_owner` · `_sel_org` · `_sel_venue` (+ the `_item` triple) | **A6** |
| `venue_settlement_sel_org` · `_sel_venue` (+ the `_line` pair) | **A10** |
| `venue_comp_allocation_sel_venue` · `venue_guest_list_sel_venue` · `venue_guest_entry_sel_venue` | **D1** |
| `venue_scan_device_sel_venue` · `venue_scan_sel_venue` · `venue_scan_sel_platform` | **A9** |
| `venue_door_manifest_sel_venue` · `_entry_sel_venue` · `_delta_sel_venue` · `venue_door_manifest_sel_platform` | **B6**, **C4** |
| `venue_promoter_sel_org`/`_venue`/`_promoter` and the `promoter_link` · `promoter_code` · `promoter_code_scope` equivalents | **A12**, **B5** |
| `venue_attribution_sel_org` · `venue_attribution_sel_venue` · `venue_attribution_sel_platform` — **`venue_attribution_sel_promoter` is DROPPED** (`AUTHZ-M9`; a promoter reads own attributions **only** through `venue.list_my_attributions` / `get_my_promoter_summary`, never by table SELECT) | **A12**, **B5** |
| `venue.attribution_review` — **NO POLICIES**; it is in the zero-policy set (`AUTHZ-M9`), because it carries the reviewer's private `note`. Every reader goes through an RPC | **A12**, **B5** |
| `market_listing_native_sel_public` · `_sel_owner` | **A11** |
| `market_auction_sel_public` · `market_offer_sel_owner` | **A11** |
| `market_p2p_transfer_sel_owner` | **A11** |
| `market.listing_unified` — **none**, `security_invoker` | **A11** (the bridge creates no new authority) |
| `notify_notification_sel_owner` · `notify_notification_upd_owner` | **B2** — **the only UPDATE policy in the register**, column-restricted to `read_at` |
| `notify_preference_sel_owner` · `_ins_owner` · `_upd_owner` | **B2** |
| `notify_announcement_sel_venue` | **B2** |
| `<schema>_<table>_sel_svc_export` (the Layer-0 exception, **MD-2**) | **B3** |

> **CORRECTED 2026-08-28 (`TM-X3`). The denominator was wrong, which made the completeness claim vacuous.**
> This paragraph said *"The 31 zero-policy objects … **All 31 are claimed**"*. RLS §16.10 lists **35** (34
> named relations + the `crm-exports` storage bucket). **A completeness assertion over the wrong denominator
> is not a weak assertion — it is a false one**, and it reported `PASS` while four objects went unclaimed.
> The count was **correct at this document's `64d2aac` baseline**; the four objects were added to the
> zero-policy set afterwards, by the remediation passes. See §14.

**The 35 zero-policy objects** of §16.10 are claimed by **A4** (`ticket_ownership_log`), **A8**
(`payment_native`, `payout`, `refund`), **A13** (`reserve`), **A2**/**D2** (`admin_audit`,
`approval_request`), **B6** (`door_freeze_override`), **B4** (`identity_demographic(_erasure)`,
`holder_mix_snapshot`, `_bucket`), **B3** (`identity_contact_pref`, `org_contact_consent`,
**`org_contact_consent_event`**, **`identity_contact_pref_event`**, `org_customer_key`, `export_job`, the
`crm-exports` bucket), **B1** (the four wallet tables), **A5** (`inventory_batch_shard`,
`inventory_movement`, `inventory_unit`), **A11** (`market_sale`), **B2** (the six machine `notify.*`
tables), **C4**/**B6** (**`venue.door_session`** — `AUTHZ-H3`), and **A12**/**B5**
(**`venue.attribution_review`** — `AUTHZ-M9`). **All 35 are claimed.**

**The four added since `64d2aac`**, listed separately so the delta is auditable rather than absorbed:
`kernel.org_contact_consent_event` · `kernel.identity_contact_pref_event` · **`venue.door_session`**
(`AUTHZ-H3` — the door session is a possession fact and no principal table-reads it) ·
**`venue.attribution_review`** (`AUTHZ-M9` — it carries the reviewer's private `note`).

---

## 11. PACKAGE REGISTER — every package to a capability, and back

| Pkg | Capability owning it | Rollback posture |
|---|---|---|
| `076` | **A1** (and **D4** if O7 rules for the constitution) | REVERSIBLE |
| `077` | **A2**, **C1**, **C3**, **B4**, **D2**, **D3** | CLEAN-WHILE-EMPTY |
| `078` | **A3**, **C5** | CLEAN-WHILE-EMPTY |
| `079` | **A4**, **C5** | **FORWARD-FIX ONLY from the first row** |
| `080` | **A5**, **C2** | CLEAN-WHILE-EMPTY |
| `081` | **A5** | CLEAN-WHILE-EMPTY |
| `082` | **A6** | CLEAN-WHILE-EMPTY |
| `083` | **A7**, **B1** | CLEAN-WHILE-EMPTY |
| `084` | **A7**, **B1** | **REVERSIBLE — protected shape (rule §6.7): zero relations, zero routines** |
| `085` | **A8**, **C1**, **C3** | **FORWARD-FIX ONLY from the first row** |
| `086` | **A9**, **B4**, **B6**, **C4**, **C5**, **D1** | CLEAN-WHILE-EMPTY |
| `087` | **A10**, **B3** | CLEAN-WHILE-EMPTY |
| `088` | **A11** | CLEAN-WHILE-EMPTY |
| `089` | **A11** | REVERSIBLE |
| `090` | **A12**, **B5** | CLEAN-WHILE-EMPTY |
| `091` | **A13** | **REVERSIBLE — protected shape (rule §6.7): always empty, referenced by no routine** |

**Every one of the sixteen packages is claimed by at least one capability.** No package is orphaned.

### 11.1 Capabilities that cannot be traced to a package — two

| Capability | Why |
|---|---|
| **B2 Notifications** | **G-2 / COND-B.** Nine tables, 23 RPCs, two crons, two edge functions. Edge §8's `Pkg` column reads `076+`ᵃ and its own footnote admits no package is assigned. If Gate P it is `092`, floored there by SEAM-1 because `notify.drain_outbox` reads `venue.promoter_link` (`090`) |
| **D4 Event outbox** | **G-1 / COND-A.** `076` if ratified — zero FK dependencies, so no producer package gains an edge |

**No third exists.** Every other capability in §3 resolves to a numbered package.

### 11.2 The seam discipline, and why it is a completeness property and not a style rule

Nine forward references were found by the systematic sweep (schema §13.2), all now closed:

| FR | Closure |
|---|---|
| **FR-1** `has_venue_role` → `door_pin` | closed by ROLE_MODEL §7.5 deleting the branch (**and RPC §1.1 is now stale on this point**) |
| **FR-2** `publish_event` | moved `078` → `081` |
| **FR-2b** `cancel_event` | moved `078` → `088` — **four packages ahead, the worst offender** |
| **FR-3** `transfer_ticket_ownership` | moved `079` → `088` |
| **FR-4** `void_ticket_atom` | authored in `085` + the `market.on_atom_voided` no-op stub replaced in `088` |
| **FR-5** `close_settlement` | **the known defect plus a second arm nothing had named** — the royalty read was forward too. Two hook stubs: `settlement_royalty_lines` (`087`→`088`) and `settlement_commission_lines` (`087`→`090`) |
| **FR-6** the `door_open_at` ledger-head trigger | created in `086`, attached to the `078` table |
| **FR-7** `is_transfer_frozen` | resolved to `079`; **and the plan's "the helper tolerates a not-yet-existing atom id" escape hatch is withdrawn — a predicate that silently returns `false` for an unknown atom fails open on the transfer path** |
| **FR-8** `build_export_rows` / `list_attendees` | accepted as-is; the promoter columns are *absent from the file, not blank*, until `090`, carried by the template version |
| **FR-9** `wallet-pass-push` | **not a DDL forward reference** (an edge function is deployed, not migrated) but a real ordering dependency the Wallet spec never flags — **subsumed by COND-A** |
| **DAG-1 / DAG-2** | two declared dependency sets were missing an edge (`088`→`085`, `085`→`079`); both added |

**Acceptance property, mechanically checkable from `pg_depend`/`pg_proc` after each package's replay:**
*no function reads or writes a table created in a later package.* This is the completeness instrument the
package layer already has — **and the RPC layer has no equivalent**, which is exactly why the twelve `RPC`
gaps in §3 went unnoticed for four integration passes.

---

## 12. WHAT THIS DOCUMENT COULD NOT CLOSE

Recorded so the next reader does not mistake absence for coverage.

1. **Nothing in §1 is fixed here.** This document has no authority to contract an RPC, assign a package, or
   rule on O7/O8. Every `GAP` names an owner.
2. **The `—` justifications are arguments, not proofs.** Where a cell reads `—` because "no external
   provider or secret is involved", that is a reading of edge §2's placement table applied by this document.
   A reviewer who disagrees with one should say so; there are 28 of them and they are individually stated.
3. **`INFERENCE:` markers inherited from the source specs are carried, not resolved.** RPC §19 lists seven
   things authored rather than transcribed — including two wholly-authored `notify` contracts, locks and
   lock order for 22 RPCs, result shapes for eight, and **every `T-RPC-*` id**. That last one matters here:
   *the test register this matrix cross-references is itself authored*, so §9's completeness is completeness
   against an authored artifact.
4. **This document did not read the pgTAP suite.** Whether an assertion is *implemented* is out of scope;
   whether it is *named* is what was checked.
5. **Two rows in §3 are marked `✓` on the strength of a single spec's word.** `B1`'s `EDGE` and `B2`'s
   `RLS` rest on the Wallet and notifications specs respectively, both of which carry their own open items
   (OQ-W1…OQ-W9, MD-10). They are not independently corroborated by a sibling spec the way the spine rows
   are.

---

## 13. JUDGEMENT — is the corpus complete enough to implement package-by-package?

**Yes for `076`–`082`, `084`, `089` and `091`. No for `086`, and conditionally no for the rest.**

**What is genuinely ready.** The schema layer, the package DAG, the seam discipline, the RLS authority model
and the edge classification are of a standard that makes the remaining holes *findable*. The forward-reference
sweep (§11.2) and the policy-name register are real completeness instruments and they work. Nothing in the
matrix suggests the architecture is wrong; the holes are omissions, not errors.

**Why `086` specifically is not ready.** It is the package with the most capabilities attached (**six**), and
it carries `GAP`s in six of the twenty-six registered: **G-4** (comp allocate/issue — scheduled as objects
in the plan, contracted nowhere), **G-9** and **G-10** (`U-2`, `U-1` — the guest-list writes a door hits all
night), **G-13** (`register_scan_device` + the unnamed *"manifest-sync"*), **G-15** (`get_door_manifest`, the
read that delivers M2 to every scanner), **G-21**. Its Tests row is silent on comps and guest lists entirely.
An engineer handed `086` would be authoring signatures for six functions the plan tells them to build.

**The two rulings gate more than they appear to.** O7 and O8 are coupled (COND-D) and between them determine
whether four capabilities are implementable *as designed* — Apple Wallet push (which has **no admissible
alternative design**, since both fallbacks are prohibited by ratified invariants), the door-manifest open
transaction, scanner push-to-sync, and all notifications. **Neither ruling can be deferred past `083`**,
because `083`/`084` build the Wallet tables whose push path is the thing in question.

**The one thing to do before writing any SQL.** Reconcile
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` against `PHASE_2_RLS_PERMISSION_SPEC.md` §11 as sets. §11 is the complete
statement of Phase-2 write authority; the contracts document is a proper subset of it, and **every element of
the difference is a function an engineer will otherwise invent**. That single reconciliation closes twelve of
the twenty-five gaps in §1's twenty-six and is the highest-value hour available to this program.

---

## 14. Correction index — reviewer-conditions pass (2026-08-28)

An adversarial review taken at `cbf8926` filed **§10's `AUTHZ-M9` policy assertion** as its **condition 3**.
It is confirmed. Verification found **two more defects in the same register, from the same single root cause.**

| ID | Defect | Fix |
|---|---|---|
| **`TM-X1`** | §10 asserted the `_sel_org`/`_sel_venue`/`_sel_promoter` triple for **`venue.attribution`** and **`venue.attribution_review`**. RLS §16.10 **drops `venue_attribution_sel_promoter`** and moves `attribution_review` to the **zero-policy** set, because it carries the reviewer's private `note` (`AUTHZ-M9`) | Row split; the drop and the zero-policy move stated explicitly, with the RPC-only read path named |
| **`TM-X2`** | §10 listed **only** `catalog_platform_config_sel_public` and glossed it *"it is world-readable"*. RLS §8.4 is a **two-class** model on `visibility` (`AUTHZ-CFG1` / ratification **C71**); `_sel_restricted` was missing. **This is the unsafe direction** — the row told an implementer a table holding every dual-control ceiling, step-up window and export cap is world-readable, which is precisely the defect C71 was raised against | Both policies listed; the two-class predicate stated; `COND-C`'s premise flagged for re-derivation |
| **`TM-X3`** | *"The **31** zero-policy objects … **All 31 are claimed**"*. RLS §16.10 lists **35**. **A completeness assertion over the wrong denominator is false, not weak** — it reported `PASS` while four objects went unclaimed: `kernel.org_contact_consent_event`, `kernel.identity_contact_pref_event`, **`venue.door_session`** (`AUTHZ-H3`), **`venue.attribution_review`** (`AUTHZ-M9`) | Count corrected to 35; all four claimed; the delta listed separately so it stays auditable |

### 14.1 The root cause is one fact, and it is not carelessness

**Every one of the three claims above was TRUE at this document's stated baseline, `64d2aac`.** Verified
against that commit rather than assumed:

| Claim | At `64d2aac` | At `cbf8926` |
|---|---|---|
| `attribution` / `attribution_review` carry the `_sel_org`/`_sel_venue`/`_sel_promoter` triple | **stated verbatim** by RLS §16.10 | dropped / zero-policy (`AUTHZ-M9`) |
| `catalog.platform_config` is world-readable, one policy | **true** — `sel_restricted` did not exist | two-class (`AUTHZ-CFG1`, **C71**) |
| the zero-policy set has **31** members | **exactly 31** (30 named + the bucket) | **35** |

The matrix did not misread its sources. **The four remediation passes changed RLS underneath it**, and
nothing carried the change forward. `AUTHZ-M9` did not exist in the RLS spec at `64d2aac` at all.

### 14.2 Why this is the more serious finding, and it is about *this* document's design

Under RLS ruling **GP-3** the RLS spec is the authority and this matrix is derived, so on the merits the fix
is trivial: copy the authority. **The danger is the direction of consumption.** This document's own §0 states
its purpose as *"to prevent implementation from silently omitting a backend or security component"*, and §11's
package register is what an implementer works down package by package. **An implementer reads the register,
not the authority it was derived from.** `TM-X2` in particular would have been read as permission.

**This document's §0.1 cell vocabulary is binding, and it is where the mechanism is missing.** It defines a
named artifact as *"**VERIFIED** — the named object exists in the cited spec **at this baseline**."* The
qualifier is load-bearing and invisible: `venue_attribution_sel_promoter` satisfied it at `64d2aac` and names
a policy that **exists in no spec today**. **There is no marker in the vocabulary for "verified against a
baseline that has since moved", and no assertion anywhere that fails when the baseline goes stale.** A
completeness instrument pinned to a stale baseline does not degrade into a merely incomplete one — it degrades
into one that reports `PASS` with authority, which is worse than having no instrument, because the empty cells
are the entire value and a stale full cell hides one.

**`TM-X4` — filed, not built.** The general fix is mechanical and belongs with the CI-gate owner: assert that
every policy name appearing in this document exists in RLS §16.10, that the zero-policy **count** here equals
the count there, and that this document's stated baseline is an ancestor of `HEAD` with the intervening commits
touching no register it mirrors. It is the same shape as the `OFFLINE-VERIFY-v1` byte-identity gate — a
property currently held by review that is buildable as a scan — and the same shape as `DL-X4` (door §20.2).
**Three independent findings in this pass now converge on one missing class of gate: a derived register with
no assertion binding it to its authority.**

### 14.3 Scope of this reconciliation — stated so it is not over-read

**Only RLS §16.10 was reconciled forward to `cbf8926`.** §8 (events), §9 (test ids), §11 (packages), §12 and
§13 were **not** re-verified and remain at `64d2aac`. §9.1's *"35 ids in 33 register rows"* and §11's package
rows are unaudited against current RLS §16.11 and the ratified package registry. **Do not read this section as
"the matrix is now current."** It is current in one register and explicitly stale elsewhere.

---

*End of `docs/architecture/PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md`. Completeness instrument, design-only.
Creates no SQL, no migration and no code; edits no other file. Fixes nothing and decides nothing — every
`GAP` names the spec that owns it. Companion to the package registry (numbering), the migration plan §8
(per-package specification), RLS §16.10/§16.11 (policy and test registers) and RPC §18 (test register).
**Baseline `64d2aac`, with RLS §16.10 alone reconciled forward to `cbf8926` (§14). Under RLS ruling GP-3 the
RLS spec is the authority and this document is derived: where they disagree, this document is the defect.**
Read §14.1 before trusting any cell — every defect it corrects was **true when written** and was overtaken by
a later pass, and nothing here fails when the baseline goes stale (`TM-X4`).*
