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
