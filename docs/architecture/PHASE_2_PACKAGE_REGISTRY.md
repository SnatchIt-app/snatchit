# Phase 2 — Migration Package Registry (CANONICAL, machine-readable)

**Status:** canonical anti-collision reference for Phase-2 migration numbering.
**Ratified:** 2026-08-27 (owner). **Supersedes** every earlier numbering statement
in the corpus.

> ## ⚠ AMENDMENT PENDING RE-RATIFICATION — delta-spec integration
>
> Rule §6.5 says *"this registry is updated only by ratified amendment."* The
> integration of the eight ratified delta specs made **one structural change** and
> several scope changes. They are recorded here so the registry stays truthful,
> and they are **awaiting owner re-ratification**.
>
> **STRUCTURAL — `kernel.approval_request` was homeless.** It is the load-bearing
> table for *all* dual control (refund approval, above-threshold payout approval,
> money-namespace config change). It appeared **only** in
> `PHASE_2_MONEY_AUTHORITY_SPEC.md` — absent from this registry, from the physical
> schema spec, and from the migration plan. **Placed in `077`.** Full argument:
> `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.13.1. The short form: the table has
> three consumers and the earliest is **not** a money flow — it is
> `catalog.set_platform_config`'s money-key dual control, which must be authored in
> `078` because that is where `catalog.platform_config` and the feature-flag seeds
> live. Placing the table in `085` (where its money consumers live) would make
> `078` forward-reference `085`. `077` satisfies every hard FK the table has, is
> where the structurally identical `kernel.admin_audit` soft-subject pattern already
> lives, and is where `has_org_role`/`is_platform` are created.
>
> **SCOPE — two packages renamed** for what they now carry (numbers unchanged):
> `083_kernel_signing_key` → **`083_kernel_credential_infrastructure`**;
> `087_venue_settlement` → **`087_venue_settlement_and_export`**.
>
> **SCOPE — seven dependency edges added** (§2.1). No edge removed, no number
> changed, the DAG stays acyclic and topologically ordered by package number.
>
> **COUNT UNCHANGED at 16 — conditionally.** Two ratified-but-unscheduled items are
> marked conditional and are **not** counted: the **event outbox** (`DA:1253`
> promises Phase 2 builds it; no implementation spec schedules one) and the
> **`notify` schema** (ratified row **C7 is Gate P / MVP** and names it; all four
> implementation specs place it at Gate L / do-not-build). See §7.
> **If `notify` is ruled Gate P, the count becomes 17 (`076`–`092`) and §2's "no
> gaps, no duplicates" assertion below is falsified** — which is precisely why the
> ruling belongs to the owner and not to an integrator.

> ## ⚠ SECOND AMENDMENT PENDING RE-RATIFICATION — schema-security remediation
>
> Confirmed Critical/High/Medium schema defects, remediated design-only. **No
> package is added, renumbered or removed; no dependency edge is added; the DAG,
> the rollout order and the acceptance properties of the first amendment are
> preserved.** The changes are **additive to existing packages**:
>
> - **`077` — `kernel.approval_request` gains `required_approver_class`**
>   (`text NOT NULL`, CHECK ∈ `org_dual_control`/`platform_review`) and three
>   further CHECKs. The dual-control **tier was never stored**: `pending_approval`
>   and `pending_platform_review` are result statuses of the request function, and
>   the `state` CHECK is `pending · approved · denied · cancelled · expired ·
>   stale`. An implementer branching on the only stored discriminators reaches the
>   **org arm for every pending row**. The SoD CHECK was additionally **vacuously
>   satisfiable**. Schema §1.13.2/§1.13.3.
> - **`077` — `kernel.org_member` gains `role_granted_at`**, and `078` seeds
>   **`authn.money_role_grant_maturity_interval`**: both money SoD primitives
>   compare `auth.uid()`, and an `org_owner` holds the grant authority to mint the
>   counterparty. Schema §1.13.4.
> - **`077` — `kernel.org_member.role` and `kernel.org_invite.role` carry the
>   canonical SIX org labels**, `text` + `CHECK`. They still enumerated four, so
>   **`org_marketing` and `org_promoter_manager` were unstorable** and every
>   org-grain marketing or promoter grant failed closed forever. Schema §1.3/§1.3b.
> - **`078` — `catalog.platform_config` gains `visibility`** and is no longer
>   blanket world-readable. Schema §2.4.1.
> - **`086` — `venue.door_session` is ADDED.** The door predicate proved
>   *provisioning*, not *possession*, and no session object existed anywhere.
>   Schema §3.10a. **One new table; `086`'s dependency set already satisfies every
>   FK it takes.**
> - **`090` — `venue.promoter_link` gains `status`.** Schema §3.17.2.
> - **`081`/`086`/`088`/`090` and others gain Functions rows** for the 49 functions
>   §20 of the RPC contracts newly contracted, plus the two sweep ticks. A
>   contracted function absent from §8 is a function nobody builds.
>
> **Owner ratification required**, per rule §6.5. The full statement of each change
> and its argument is `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §1.13.2–§1.13.4,
> §2.4.1, §3.10a, §3.17.2 and §13.7.

Consult this file **before quoting, authoring, or reviewing any Phase-2 migration
number.** If another document disagrees with this table, this table wins and the
other document is stale — fix it, do not follow it.

---

## 1. The two bands — never confuse them

| Band | Numbers | What it is |
|---|---|---|
| **Applied production security migrations** | `071`–`075` | Real, applied, immovable SQL in `supabase/migrations/`. **NOT Phase-2 packages.** |
| **Phase-2 MVP packages** | `076`–`091` | Design-only specification. Sixteen packages. No SQL authored yet. |

### 1.1 Applied security migrations `071`–`075` (do not renumber, do not reuse)

| Version | File | Closes | Applied |
|---|---|---|---|
| `071` | `071_fix_guard_proof_status.sql` | DB-1 (HIGH) — `guard_proof_status()` keyed on the legacy singular `request.jwt.claim.role` GUC | 2026-08-27 |
| `072` | `072_fix_listing_insert_guards.sql` | H-1 (HIGH) — INSERT-side column custody on `public.listings` | 2026-08-27 |
| `073` | `073_storage_bucket_upload_constraints.sql` | SEC-3 — storage bucket MIME/size upload constraints | 2026-08-27 |
| `074` | `074_privilege_cleanup.sql` | SEC-1 + residual EXECUTE cleanup | 2026-08-27 |
| `075` | `075_replay_parity_storage_policies_and_cron.sql` | SEC-4 + D-5 — replay parity for storage policies and cron | 2026-08-27 |

**True applied max = `075`.** The next free migration number is `076`.

---

## 2. Phase-2 package registry `076`–`091`

`old` = the number in the **original ratified plan** (`071`–`086`), the scale most
of the corpus was written on. Two intermediate `+1` shifts (`072`–`087` and
`073`–`088`) existed only inside `PHASE_2_SUPABASE_MIGRATION_PLAN.md` and are
**dead** — they are recorded in §4 only so that stale quotations can be decoded.

| New | Old | Pkg | Phase | Purpose | Scope (one line) |
|---|---|---|---|---|---|
| `076` | `071` | A | A — schema skeleton | `076_create_phase2_schemas_and_grants` | 4 schemas (`kernel`/`catalog`/`venue`/`market`) + GRANT boundary + shared helper functions/triggers |
| `077` | `072` | B | B — organizations + permissions | `077_kernel_identity_orgs_and_roles` | `kernel.identity_ext`, `organization`, `org_member` (**six** org labels, **+`role_granted_at`**), `org_invite` (**six** org labels), `platform_role`, `admin_audit` + org/platform role predicates · **Δ `approval_request` (**+`required_approver_class`**), `identity_demographic(_erasure)`, `identity_contact_pref`, `org_customer_key`, `organization.payout_destination_set_by`, `identity_ext.locale`** |
| `078` | `073` | C | C — catalog | `078_catalog_reference_data_and_flags` | `catalog.venue`, `event`, `event_session` (incl. `door_open_at`), `platform_config` (**+`visibility`** — split read, not blanket public) + **all** feature-flag and config seeds, `resale_policy` · **Δ `event` marketing columns, `event_session.session_version`, `effective_freeze_at()`** |
| `079` | `074` | D | D — ticket kernel | `079_kernel_ticket_atom_and_ownership_log` | `kernel.tickets` (custody atom) + `kernel.ticket_ownership_log` (append-only custody ledger, C26 idempotency) · **Δ `door_freeze_override`, `is_transfer_frozen`, `lock_/unlock_ticket`, `mark_ticket_scanned`** |
| `080` | `075` | E1 | E — inventory | `080_venue_staff_roles_and_predicates` | `venue.staff_role` (**six canonical labels**) + `has_venue_role`/`has_event_role` · **Δ `has_org_role_over_venue`/`_over_event`** |
| `081` | `076` | E2 | E — inventory | `081_venue_inventory` | `venue.ticket_type`, `inventory_batch`, `inventory_batch_shard`, `inventory_movement`, `inventory_hold` (oversell-safe counter) · **Δ `catalog.publish_event` authored here** |
| `082` | `077` | F | F — orders | `082_venue_orders` | `venue.order`, `venue.order_item` (primary-purchase container) · **Δ `kernel.org_contact_consent`** |
| `083` | `078` | G1 | G — credential infrastructure | `083_kernel_credential_infrastructure` | `kernel.signing_key` — public key + KMS handle reference only, **no private key material** · **Δ `pass_type_cert`, `wallet_pass`, `wallet_pass_device`, `wallet_pass_push_log`, `.pkpass` bucket** |
| `084` | `079` | G2 | G — credential infrastructure (ADOPT) | `084_kernel_tickets_late_binding_fks` | late-binding FKs `kernel.tickets` → `venue.ticket_type` + `kernel.signing_key` (`NOT VALID` + `VALIDATE`) — **and nothing else; the only unconditionally reversible package** |
| `085` | `080` | M | F/I bridge — kernel money-native | `085_kernel_money_native` | `kernel.payment_native`, `kernel.refund`, `kernel.payout` (link to frozen `public.payments`, never re-charge) · **Δ `void_ticket_atom` + `market.on_atom_voided` stub; the nine money-authority RPCs** |
| `086` | `081` | H | H — scan infrastructure | `086_venue_door_and_scan` | `venue.door_pin`, **`door_session`**, `scan_device`, `scan` (C41 re-entry hedge), `comp_allocation`, `guest_list`, `guest_entry` · **Δ `door_manifest(_entry/_delta)`, `holder_mix_snapshot`, `holder_mix_bucket`, `scan.actor_identity_id`, `assert_door_session` (token-bearing)** |
| `087` | `082` | I | I — settlement | `087_venue_settlement_and_export` | `venue.settlement`, `venue.settlement_line` (per-event money rollup → `kernel.payout`) · **Δ `export_job` + `crm-exports` bucket; `close_settlement` + its two hook stubs** |
| `088` | `083` | J1 | J — native marketplace bridge | `088_market_native_rail` | `market.listing_native`, `auction`, `offer`, `market_sale` (C26 terminal SM), `p2p_transfer` · **Δ `transfer_ticket_ownership`, `catalog.cancel_event`, replaces two hooks** |
| `089` | `084` | J2 | J — native marketplace bridge (ADOPT) | `089_market_bridge_view_and_late_fk` | `market.listing_unified` VIEW (external ∪ native, flag-gated) + adopt `payment_native.sale_id` FK |
| `090` | `085` | 2D | Phase 2D — promoter engine | `090_venue_promoter_engine` | `venue.promoter`, `promoter_link` (**+`status`**), `attribution` (modeled now, activated in the promoter phase) · **Δ commercial-terms columns, `promoter_code(_scope)`, `attribution_review`, the cross-settlement commission unique, `payment_native.instrument_fingerprint`** |
| `091` | `086` | K | K — money-ledger extensions | `091_kernel_reserve_stub` | `kernel.reserve` **stub only** (empty shape, no writers); full Gate-M ledger is documented-only |

**Count: 16 packages, `076`–`091` inclusive, no gaps, no duplicates** — subject to §7 COND-B.

`Δ` marks objects added by the eight ratified delta specs. The binding placement record, including the
argument for every disagreement with a delta spec's own proposal, is
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` **§13**. The full per-package specification (purpose · tables ·
functions · RLS · triggers · indexes · grants · flags · dependencies · rollback posture · tests) is
`PHASE_2_SUPABASE_MIGRATION_PLAN.md` **§8**.

### 2.1 Apply order and dependencies

**+** marks an edge added by the delta-spec integration. Every dependency precedes its dependent, so the
graph is a DAG and is topologically ordered by package number.

| Seq | Pkg | Depends on |
|---|---|---|
| 1 | `076` | precondition (phase0 chain + `071`–`075`) |
| 2 | `077` | `076` |
| 3 | `078` | `077` |
| 4 | `079` | `077`, `078` |
| 5 | `080` | `077`, `078` |
| 6 | `081` | `078`, `080` |
| 7 | `082` | `081` |
| 8 | `083` | `078`, **+`079`** |
| 9 | `084` | `079`, `081`, `083` |
| 10 | `085` | `077`, **+`079`**, `082` |
| 11 | `086` | `079`, `080`, `081`, **+`083`** |
| 12 | `087` | `077`, `081`, `085` |
| 13 | `088` | `078`, `079`, `081`, **+`085`** |
| 14 | `089` | `085`, `088` |
| 15 | `090` | `082`, **+`078`**, **+`085`**, **+`087`** |
| 16 | `091` | `077` |

Why each added edge exists:

| Edge | Because |
|---|---|
| `079 → 083` | `kernel.wallet_pass.ticket_atom_id` FK → `kernel.tickets` |
| `079 → 085` | `kernel.refund_primary_order` drives `void_ticket_atom` → `kernel.tickets` (previously undeclared) |
| `083 → 086` | `venue.door_manifest_entry.signing_key_id` FK → `kernel.signing_key` |
| `085 → 088` | `market.sweep_paid_pending_sales` writes `kernel.refund` (previously undeclared) |
| `078 → 090` | `venue.promoter_code_scope.event_id` FK → `catalog.event` |
| `085 → 090` | `090` adds `kernel.payment_native.instrument_fingerprint` |
| `087 → 090` | `090` adds the cross-settlement commission unique on `venue.settlement_line` and replaces `kernel.settlement_commission_lines` |

### 2.2 The seam rule that keeps the DAG honest

Dependency edges between *tables* are visible in the FK graph. Dependency edges created by a **function
reading a table in a later package** are not, and a systematic sweep found **nine** of them (schema §13.2).
Two rules, ratified with this amendment, prevent recurrence:

> **SEAM-1** — a function is authored in the package equal to `max()` of the packages creating every table
> it reads or writes.
> **SEAM-2** — where an earlier artifact must resolve the name, the earlier package ships a **hook stub**
> returning the neutral result and the later package `CREATE OR REPLACE`s **only that hook**.

**Acceptance property:** *no function reads or writes a table created in a later package* — mechanically
checkable from `pg_depend`/`pg_proc` after each package's replay.

---

## 3. Machine-readable

```json
{
  "schema_version": 2,
  "ratified": "2026-08-27",
  "amended": "2026-08-27",
  "amendment_status": "PENDING_RE_RATIFICATION",
  "amendment_summary": "Delta-spec integration. Structural: kernel.approval_request placed in 077 (it had no package and no home). Scope: 083 and 087 renamed; seven dependency edges added; per-package object sets extended. Count unchanged at 16 unless COND-B (notify) is ruled Gate P.",
  "canonical_source": "docs/architecture/PHASE_2_PACKAGE_REGISTRY.md",
  "placement_record": "docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md#13",
  "package_specification": "docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md#8",
  "applied_max": "075",
  "phase2_range": { "first": "076", "last": "091", "count": 16 },
  "seam_rules": {
    "SEAM-1": "A function is authored in the package equal to max() of the packages creating every table it reads or writes.",
    "SEAM-2": "Where an earlier artifact must resolve the name, the earlier package ships a hook stub returning the neutral result and the later package CREATE OR REPLACEs only that hook.",
    "acceptance_property": "No function reads or writes a table created in a later package.",
    "hooks": [
      { "name": "kernel.settlement_royalty_lines", "stub_in": "087", "replaced_in": "088", "neutral_result": "zero rows" },
      { "name": "kernel.settlement_commission_lines", "stub_in": "087", "replaced_in": "090", "neutral_result": "zero rows" },
      { "name": "market.on_atom_voided", "stub_in": "085", "replaced_in": "088", "neutral_result": "no-op" }
    ]
  },
  "conditionals": [
    {
      "id": "COND-A",
      "name": "event outbox + drainer",
      "status": "SPECIFIED_NOT_SCHEDULED",
      "source": "SNATCH_IT_DOMAIN_ARCHITECTURE.md:1253",
      "conflict": "DA:1253 promises Phase 2 builds one outbox table and a drainer on the existing cron; no implementation spec schedules one.",
      "package_if_ratified": "076",
      "schema_if_notify_gate_p": "notify.outbox",
      "schema_if_notify_gate_l": "kernel.event_outbox",
      "unimplementable_without": ["apple_wallet_push_path", "door_manifest_open_transaction", "scanner_push_to_sync", "all_notifications"],
      "unaffected": ["crm_export", "demographics", "promoter_codes", "money_authority"],
      "owner_ruling_required": true
    },
    {
      "id": "COND-B",
      "name": "notify schema",
      "status": "SPECIFIED_NOT_SCHEDULED",
      "conflict": "Ratified row C7 is Gate P / MVP and names notify; all four implementation specs place it at Gate L / do-not-build.",
      "package_if_gate_p": "092",
      "count_if_gate_p": 17,
      "range_if_gate_p": { "first": "076", "last": "092" },
      "note_if_gate_p": "Not folded into 091, which is a droppable writer-less stub. Independently floored at 090 by SEAM-1 because notify.drain_outbox reads venue.promoter_link. Falsifies the 'no gaps, no duplicates' count assertion; requires re-ratification.",
      "coupled_to": "COND-A",
      "coupling_rule": "Outbox-in with notify-out is coherent. Notify-in with outbox-out is not: NOTIFICATIONS section 4 is the outbox pipeline.",
      "owner_ruling_required": true
    },
    {
      "id": "COND-C",
      "name": "kernel.org_money_policy",
      "status": "SPECIFIED_NOT_PROPOSED",
      "source": "PHASE_2_MONEY_AUTHORITY_SPEC.md#7.4",
      "gate": "owner decision D-2",
      "recommendation": "No — catalog.platform_config is world-readable, so per-org limits need a non-public home, and nothing in O-1/O-3 asks for one.",
      "package_if_ratified": "077",
      "owner_ruling_required": true
    }
  ],
  "applied_security_migrations": [
    { "version": "071", "file": "071_fix_guard_proof_status.sql", "closes": "DB-1", "applied": "2026-08-27" },
    { "version": "072", "file": "072_fix_listing_insert_guards.sql", "closes": "H-1", "applied": "2026-08-27" },
    { "version": "073", "file": "073_storage_bucket_upload_constraints.sql", "closes": "SEC-3", "applied": "2026-08-27" },
    { "version": "074", "file": "074_privilege_cleanup.sql", "closes": "SEC-1", "applied": "2026-08-27" },
    { "version": "075", "file": "075_replay_parity_storage_policies_and_cron.sql", "closes": "SEC-4,D-5", "applied": "2026-08-27" }
  ],
  "packages": [
    { "new": "076", "old": "071", "package": "A", "phase": "A", "name": "076_create_phase2_schemas_and_grants", "purpose": "schema skeleton", "scope": "4 schemas + GRANT boundary + shared helper functions/triggers", "depends_on": [], "rollback_posture": "REVERSIBLE" },
    { "new": "077", "old": "072", "package": "B", "phase": "B", "name": "077_kernel_identity_orgs_and_roles", "purpose": "organizations + permissions + dual-control substrate", "scope": "identity_ext (+locale), organization (+payout_destination_set_by), org_member (six org labels, +role_granted_at), org_invite (six org labels), platform_role, admin_audit, approval_request (+required_approver_class), identity_demographic(_erasure), identity_contact_pref, org_customer_key + role predicates", "depends_on": ["076"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["kernel.approval_request", "kernel.identity_demographic", "kernel.identity_demographic_erasure", "kernel.identity_contact_pref", "kernel.org_customer_key", "kernel.organization.payout_destination_set_by", "kernel.identity_ext.locale"] },
    { "new": "078", "old": "073", "package": "C", "phase": "C", "name": "078_catalog_reference_data_and_flags", "purpose": "catalog + all config/flag seeds", "scope": "catalog.venue/event/event_session/platform_config (+visibility, split read)/resale_policy + every feature-flag and config seed in the chain", "depends_on": ["077"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["catalog.event.description", "catalog.event.hero_image_ref", "catalog.event.category", "catalog.event.genre_tags", "catalog.event_session.session_version", "catalog.effective_freeze_at"] },
    { "new": "079", "old": "074", "package": "D", "phase": "D", "name": "079_kernel_ticket_atom_and_ownership_log", "purpose": "ticket kernel", "scope": "kernel.tickets + kernel.ticket_ownership_log (C26 idempotency) + the complete transfer-freeze input set", "depends_on": ["077", "078"], "rollback_posture": "FORWARD_FIX_ONLY", "delta_added": ["kernel.door_freeze_override", "kernel.is_transfer_frozen", "kernel.tickets.resale_state:refund_hold"] },
    { "new": "080", "old": "075", "package": "E1", "phase": "E", "name": "080_venue_staff_roles_and_predicates", "purpose": "inventory (roles)", "scope": "venue.staff_role (six canonical labels, text+CHECK) + has_venue_role/has_event_role/has_org_role_over_venue/has_org_role_over_event", "depends_on": ["077", "078"], "rollback_posture": "CLEAN_WHILE_EMPTY" },
    { "new": "081", "old": "076", "package": "E2", "phase": "E", "name": "081_venue_inventory", "purpose": "inventory (capacity)", "scope": "ticket_type, inventory_batch, inventory_batch_shard, inventory_movement, inventory_hold + catalog.publish_event", "depends_on": ["078", "080"], "rollback_posture": "CLEAN_WHILE_EMPTY" },
    { "new": "082", "old": "077", "package": "F", "phase": "F", "name": "082_venue_orders", "purpose": "orders", "scope": "venue.order + venue.order_item + kernel.org_contact_consent", "depends_on": ["081"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["kernel.org_contact_consent"] },
    { "new": "083", "old": "078", "package": "G1", "phase": "G", "name": "083_kernel_credential_infrastructure", "purpose": "credential infrastructure", "scope": "kernel.signing_key + pass_type_cert + wallet_pass + wallet_pass_device + wallet_pass_push_log + .pkpass bucket (public key / KMS handle refs only, no key material)", "depends_on": ["078", "079"], "rollback_posture": "CLEAN_WHILE_EMPTY", "renamed_from": "083_kernel_signing_key", "delta_added": ["kernel.pass_type_cert", "kernel.wallet_pass", "kernel.wallet_pass_device", "kernel.wallet_pass_push_log"] },
    { "new": "084", "old": "079", "package": "G2", "phase": "G", "name": "084_kernel_tickets_late_binding_fks", "purpose": "credential infrastructure (ADOPT)", "scope": "late-binding FKs kernel.tickets -> ticket_type + signing_key, and nothing else", "depends_on": ["079", "081", "083"], "rollback_posture": "REVERSIBLE", "invariant": "Creates zero relations and zero routines. This purity is what makes its rollback unconditionally reversible; nothing may be added to it." },
    { "new": "085", "old": "080", "package": "M", "phase": "F/I bridge", "name": "085_kernel_money_native", "purpose": "kernel money-native + money authority", "scope": "kernel.payment_native, kernel.refund, kernel.payout, void_ticket_atom + on_atom_voided stub, the nine money-authority RPCs", "depends_on": ["077", "079", "082"], "rollback_posture": "FORWARD_FIX_ONLY" },
    { "new": "086", "old": "081", "package": "H", "phase": "H", "name": "086_venue_door_and_scan", "purpose": "scan infrastructure + door manifest + holder mix", "scope": "door_pin, door_session, scan_device, scan (+actor_identity_id, +manifest_id), comp_allocation, guest_list, guest_entry, door_manifest(_entry/_delta), holder_mix_snapshot, holder_mix_bucket", "depends_on": ["079", "080", "081", "083"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["venue.door_manifest", "venue.door_manifest_entry", "venue.door_manifest_delta", "venue.holder_mix_snapshot", "venue.holder_mix_bucket", "venue.scan.actor_identity_id", "venue.scan.manifest_id", "venue.scan_device.manifest_id"] },
    { "new": "087", "old": "082", "package": "I", "phase": "I", "name": "087_venue_settlement_and_export", "purpose": "settlement + CRM export", "scope": "venue.settlement + venue.settlement_line + venue.export_job + crm-exports bucket + close_settlement and its two hook stubs", "depends_on": ["077", "081", "085"], "rollback_posture": "CLEAN_WHILE_EMPTY", "renamed_from": "087_venue_settlement", "delta_added": ["venue.export_job", "storage.buckets:crm-exports", "crm_export_builder role"] },
    { "new": "088", "old": "083", "package": "J1", "phase": "J", "name": "088_market_native_rail", "purpose": "native marketplace rail + custody engine", "scope": "listing_native, auction, offer, market_sale, p2p_transfer, transfer_ticket_ownership, catalog.cancel_event", "depends_on": ["078", "079", "081", "085"], "rollback_posture": "CLEAN_WHILE_EMPTY", "restores_hooks": ["kernel.settlement_royalty_lines", "market.on_atom_voided"] },
    { "new": "089", "old": "084", "package": "J2", "phase": "J", "name": "089_market_bridge_view_and_late_fk", "purpose": "native marketplace bridge (ADOPT)", "scope": "market.listing_unified VIEW + adopt payment_native.sale_id FK", "depends_on": ["085", "088"], "rollback_posture": "REVERSIBLE" },
    { "new": "090", "old": "085", "package": "2D", "phase": "2D", "name": "090_venue_promoter_engine", "purpose": "promoter engine", "scope": "venue.promoter (+tier/party_kind/commission_kind/commission_flat_minor), promoter_link (+status), attribution (+15 cols), promoter_code, promoter_code_scope, attribution_review, the cross-settlement commission unique, payment_native.instrument_fingerprint", "depends_on": ["078", "082", "085", "087"], "rollback_posture": "CLEAN_WHILE_EMPTY", "restores_hooks": ["kernel.settlement_commission_lines"], "delta_added": ["venue.promoter_code", "venue.promoter_code_scope", "venue.attribution_review", "venue.settlement_line:uq_promoter_commission_cause_ref", "kernel.payment_native.instrument_fingerprint", "venue.order.attribution_candidate_code_id", "venue.order.attribution_candidate_link_id"] },
    { "new": "091", "old": "086", "package": "K", "phase": "K", "name": "091_kernel_reserve_stub", "purpose": "money-ledger stub", "scope": "kernel.reserve stub only (no writers)", "depends_on": ["077"], "rollback_posture": "REVERSIBLE", "invariant": "Always empty; no routine in the database references it." }
  ]
}
```

---

## 4. Decoding stale quotations

Four numbering scales exist in the historical record. Use this table to decode a
number found in an old document, then restate it on the canonical scale.

| Scale | Range | Where it appeared | Offset to canonical |
|---|---|---|---|
| **S0** original ratified plan | `071`–`086` | most of the corpus (schema spec, RLS, RPC, edge, RN, governance docs) | **+5** |
| **S1** first `+1` shift | `072`–`087` | only inside `PHASE_2_SUPABASE_MIGRATION_PLAN.md` (rollback filenames, §3 columns, most §5 dependency bullets) | **+4** |
| **S2** second `+1` shift | `073`–`088` | only inside `PHASE_2_SUPABASE_MIGRATION_PLAN.md` (§1 map, §2 mermaid, §5 headings) | **+3** |
| **CANONICAL** | `076`–`091` | everywhere, after 2026-08-27 | — |

Arithmetic alone is **not** safe: the plan document carried S0, S1 and S2
simultaneously in different sections, and §1 assigned packages A and B the same
version. Always decode by **package identity** (what the sentence says the
package *creates*), then look the package up in §2.

### 4.1 Defects repaired by this ratification (do not resurrect)

- **A/B version collision.** `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §1 assigned
  package **A** (schema skeleton) and package **B** (organizations + permissions)
  the *same* version. Two packages cannot share a migration version. A = `076`,
  B = `077`.
- **Heading/body disagreement.** §1's heading read `(073–088)` over a table whose
  last row was `087`; §5's title read `(071–087)`. Both now read `076–091`.
- **Off-by-one rollback filenames.** Every §5 package after A named the *previous*
  package's rollback script. Each package's rollback is now `rollbacks/<its own
  number>_*.sql`.
- **`071` dependency error.** Package B's dependency bullet cited `071`
  ("schemas/helpers"), an S0 token, while its own heading was on S2. It is `076`.

---

## 5. Namespace note (not a collision)

`supabase/tests/*.sql` uses its own independent `NNN_` sequence (`000`–`132`),
which includes files named `080_admin.sql` and `090_webhooks.sql`. Those numbers
are **pgTAP test-file ordinals**, unrelated to migration versions. A number in
`supabase/tests/` never denotes a migration or a Phase-2 package.

---

## 6. Rules

1. **`071`–`075` are immovable.** Never edit, rename, renumber or reuse them.
2. **Phase-2 packages occupy `076`–`091`.** No non-Phase-2 migration may claim a
   number in that band without a ratified amendment recorded in
   `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` and an update to
   this registry.
3. **New security hotfixes go above `091`**, or — if authored before Phase 2
   starts — require this registry to be re-ratified with a new shift. Do not
   silently consume a reserved number; that is precisely what produced the four
   competing scales in §4.
4. **One package, one version.** Verify against §2 before authoring.
5. This registry is updated **only** by ratified amendment.
6. **Function placement is derived, not chosen** (§2.2 SEAM-1/SEAM-2). A package
   that contains a function reading a table created in a later package is
   malformed, regardless of how the object list looks.
7. **`084` and `091` are protected shapes.** `084` creates zero relations and
   zero routines; `091` is always empty and referenced by no routine. Those
   properties are what make their rollbacks unconditionally reversible. Adding
   anything to either requires a ratified amendment, not a judgement call.

---

## 7. Conditionals — ratified but unscheduled, NOT counted in the 16

Three items are specified in the corpus, referenced by ratified documents, and
scheduled by **nothing**. They are recorded here so that a ruling is an apply
rather than a design exercise, and so that no reader mistakes their absence from
§2 for a decision. **Each requires an owner ruling.**

| ID | Item | The contradiction | If ratified |
|---|---|---|---|
| **COND-A** | **event outbox + drainer** | `SNATCH_IT_DOMAIN_ARCHITECTURE.md:1253` promises *"the only new infrastructure Phase 2 introduces is one outbox table and a drainer on the cron that already runs"*, and DA §6.1 classifies every notification, rollup, commission accrual and transfer-expiry as Async/outbox. **No implementation spec schedules one.** | Package **`076`** — the table has zero FK dependencies, so no producer package gains an edge. Schema is `notify.outbox` under COND-B Gate P, `kernel.event_outbox` otherwise. Drainer on the existing 2-minute `pg_cron` heartbeat. |
| **COND-B** | **`notify` schema (9 tables)** | Ratified row **C7 is `Gate P / MVP`** and names `notify`; **all four** implementation specs place it at Gate L / do-not-build. | Package **`092`** — not `091` (a droppable stub, rule §6.7) and not earlier, because `notify.drain_outbox` reads `venue.promoter_link` (`090`) and SEAM-1 floors it there. **Count becomes 17, range `076`–`092`, and §2's "no gaps, no duplicates" assertion is falsified.** |
| **COND-C** | **`kernel.org_money_policy`** | `PHASE_2_MONEY_AUTHORITY_SPEC.md` §7.4 specifies it but explicitly does **not** propose it for MVP; owner decision **D-2**. Trigger: `catalog.platform_config` is world-readable, so a per-org money threshold cannot live there. | Package **`077`**. Recommendation on record: **No** — nothing in O-1/O-3 asks for per-org limits and it doubles the resolution logic at every money decision point. |

**COND-A and COND-B are coupled and must be ruled on together.** Outbox-in with
`notify`-out is coherent — Apple Wallet push and the door-manifest events get
their carrier, notifications do not. `notify`-in with outbox-out is **not**
coherent: the notifications design *is* the outbox pipeline.

**What breaks under COND-A = NO**, stated precisely so the ruling is priced: the
entire Apple Wallet push path (pass supersession runs in the outbox consumer
specifically so Wallet can never block or roll back a custody transfer — the two
alternatives, moving it into the custody transaction or leaving a superseded pass
live, are both prohibited by ratified invariants); the door-manifest open
transaction as specified (its steps are all-or-nothing and the last one writes the
envelopes); scanner push-to-sync; every notification. **Unaffected:** CRM export
(`pg_cron` + `pg_net` + a claim-lease), demographics, promoter codes, and money
authority — each carries its own scheduler.

Full treatment: `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.3/§13.4 and
`PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 COND-A/COND-B.
