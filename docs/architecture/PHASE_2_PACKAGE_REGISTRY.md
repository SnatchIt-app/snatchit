# Phase 2 — Migration Package Registry (CANONICAL, machine-readable)

**Status:** canonical anti-collision reference for Phase-2 migration numbering.
**Ratified:** 2026-08-27 (owner). **Supersedes** every earlier numbering statement
in the corpus.

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
| `077` | `072` | B | B — organizations + permissions | `077_kernel_identity_orgs_and_roles` | `kernel.identity_ext`, `organization`, `org_member`, `org_invite`, `platform_role`, `admin_audit` + org/platform role predicates |
| `078` | `073` | C | C — catalog | `078_catalog_reference_data_and_flags` | `catalog.venue`, `event`, `event_session` (incl. `door_open_at`), `platform_config` + feature-flag seeds, `resale_policy` |
| `079` | `074` | D | D — ticket kernel | `079_kernel_ticket_atom_and_ownership_log` | `kernel.tickets` (custody atom) + `kernel.ticket_ownership_log` (append-only custody ledger, C26 idempotency) |
| `080` | `075` | E1 | E — inventory | `080_venue_staff_roles_and_predicates` | `venue.staff_role` + `has_venue_role`/`has_event_role` predicates |
| `081` | `076` | E2 | E — inventory | `081_venue_inventory` | `venue.ticket_type`, `inventory_batch`, `inventory_batch_shard`, `inventory_movement`, `inventory_hold` (oversell-safe counter) |
| `082` | `077` | F | F — orders | `082_venue_orders` | `venue.order`, `venue.order_item` (primary-purchase container) |
| `083` | `078` | G1 | G — credential infrastructure | `083_kernel_signing_key` | `kernel.signing_key` — public key + KMS handle reference only, **no private key material** |
| `084` | `079` | G2 | G — credential infrastructure (ADOPT) | `084_kernel_tickets_late_binding_fks` | late-binding FKs `kernel.tickets` → `venue.ticket_type` + `kernel.signing_key` (`NOT VALID` + `VALIDATE`) |
| `085` | `080` | M | F/I bridge — kernel money-native | `085_kernel_money_native` | `kernel.payment_native`, `kernel.refund`, `kernel.payout` (link to frozen `public.payments`, never re-charge) |
| `086` | `081` | H | H — scan infrastructure | `086_venue_door_and_scan` | `venue.door_pin`, `scan_device`, `scan` (C41 re-entry hedge), `comp_allocation`, `guest_list`, `guest_entry` |
| `087` | `082` | I | I — settlement | `087_venue_settlement` | `venue.settlement`, `venue.settlement_line` (per-event money rollup → `kernel.payout`) |
| `088` | `083` | J1 | J — native marketplace bridge | `088_market_native_rail` | `market.listing_native`, `auction`, `offer`, `market_sale` (C26 terminal SM), `p2p_transfer` |
| `089` | `084` | J2 | J — native marketplace bridge (ADOPT) | `089_market_bridge_view_and_late_fk` | `market.listing_unified` VIEW (external ∪ native, flag-gated) + adopt `payment_native.sale_id` FK |
| `090` | `085` | 2D | Phase 2D — promoter engine | `090_venue_promoter_engine` | `venue.promoter`, `promoter_link`, `attribution` (modeled now, activated in the promoter phase) |
| `091` | `086` | K | K — money-ledger extensions | `091_kernel_reserve_stub` | `kernel.reserve` **stub only** (empty shape, no writers); full Gate-M ledger is documented-only |

**Count: 16 packages, `076`–`091` inclusive, no gaps, no duplicates.**

### 2.1 Apply order and dependencies

| Seq | Pkg | Depends on |
|---|---|---|
| 1 | `076` | precondition (phase0 chain + `071`–`075`) |
| 2 | `077` | `076` |
| 3 | `078` | `077` |
| 4 | `079` | `077`, `078` |
| 5 | `080` | `077`, `078` |
| 6 | `081` | `078`, `080` |
| 7 | `082` | `081` |
| 8 | `083` | `078` |
| 9 | `084` | `079`, `081`, `083` |
| 10 | `085` | `077`, `082` |
| 11 | `086` | `079`, `080`, `081` |
| 12 | `087` | `077`, `081`, `085` |
| 13 | `088` | `078`, `079`, `081` |
| 14 | `089` | `085`, `088` |
| 15 | `090` | `082` |
| 16 | `091` | `077` |

---

## 3. Machine-readable

```json
{
  "schema_version": 1,
  "ratified": "2026-08-27",
  "canonical_source": "docs/architecture/PHASE_2_PACKAGE_REGISTRY.md",
  "applied_max": "075",
  "phase2_range": { "first": "076", "last": "091", "count": 16 },
  "applied_security_migrations": [
    { "version": "071", "file": "071_fix_guard_proof_status.sql", "closes": "DB-1", "applied": "2026-08-27" },
    { "version": "072", "file": "072_fix_listing_insert_guards.sql", "closes": "H-1", "applied": "2026-08-27" },
    { "version": "073", "file": "073_storage_bucket_upload_constraints.sql", "closes": "SEC-3", "applied": "2026-08-27" },
    { "version": "074", "file": "074_privilege_cleanup.sql", "closes": "SEC-1", "applied": "2026-08-27" },
    { "version": "075", "file": "075_replay_parity_storage_policies_and_cron.sql", "closes": "SEC-4,D-5", "applied": "2026-08-27" }
  ],
  "packages": [
    { "new": "076", "old": "071", "package": "A", "phase": "A", "name": "076_create_phase2_schemas_and_grants", "purpose": "schema skeleton", "scope": "4 schemas + GRANT boundary + shared helper functions/triggers", "depends_on": [] },
    { "new": "077", "old": "072", "package": "B", "phase": "B", "name": "077_kernel_identity_orgs_and_roles", "purpose": "organizations + permissions", "scope": "identity_ext, organization, org_member, org_invite, platform_role, admin_audit + role predicates", "depends_on": ["076"] },
    { "new": "078", "old": "073", "package": "C", "phase": "C", "name": "078_catalog_reference_data_and_flags", "purpose": "catalog", "scope": "catalog.venue/event/event_session/platform_config/resale_policy + feature-flag seeds", "depends_on": ["077"] },
    { "new": "079", "old": "074", "package": "D", "phase": "D", "name": "079_kernel_ticket_atom_and_ownership_log", "purpose": "ticket kernel", "scope": "kernel.tickets + kernel.ticket_ownership_log (C26 idempotency)", "depends_on": ["077", "078"] },
    { "new": "080", "old": "075", "package": "E1", "phase": "E", "name": "080_venue_staff_roles_and_predicates", "purpose": "inventory (roles)", "scope": "venue.staff_role + has_venue_role/has_event_role predicates", "depends_on": ["077", "078"] },
    { "new": "081", "old": "076", "package": "E2", "phase": "E", "name": "081_venue_inventory", "purpose": "inventory (capacity)", "scope": "ticket_type, inventory_batch, inventory_batch_shard, inventory_movement, inventory_hold", "depends_on": ["078", "080"] },
    { "new": "082", "old": "077", "package": "F", "phase": "F", "name": "082_venue_orders", "purpose": "orders", "scope": "venue.order + venue.order_item", "depends_on": ["081"] },
    { "new": "083", "old": "078", "package": "G1", "phase": "G", "name": "083_kernel_signing_key", "purpose": "credential infrastructure", "scope": "kernel.signing_key (public key + KMS handle ref only)", "depends_on": ["078"] },
    { "new": "084", "old": "079", "package": "G2", "phase": "G", "name": "084_kernel_tickets_late_binding_fks", "purpose": "credential infrastructure (ADOPT)", "scope": "late-binding FKs kernel.tickets -> ticket_type + signing_key", "depends_on": ["079", "081", "083"] },
    { "new": "085", "old": "080", "package": "M", "phase": "F/I bridge", "name": "085_kernel_money_native", "purpose": "kernel money-native", "scope": "kernel.payment_native, kernel.refund, kernel.payout", "depends_on": ["077", "082"] },
    { "new": "086", "old": "081", "package": "H", "phase": "H", "name": "086_venue_door_and_scan", "purpose": "scan infrastructure", "scope": "door_pin, scan_device, scan, comp_allocation, guest_list, guest_entry", "depends_on": ["079", "080", "081"] },
    { "new": "087", "old": "082", "package": "I", "phase": "I", "name": "087_venue_settlement", "purpose": "settlement", "scope": "venue.settlement + venue.settlement_line", "depends_on": ["077", "081", "085"] },
    { "new": "088", "old": "083", "package": "J1", "phase": "J", "name": "088_market_native_rail", "purpose": "native marketplace rail", "scope": "listing_native, auction, offer, market_sale, p2p_transfer", "depends_on": ["078", "079", "081"] },
    { "new": "089", "old": "084", "package": "J2", "phase": "J", "name": "089_market_bridge_view_and_late_fk", "purpose": "native marketplace bridge (ADOPT)", "scope": "market.listing_unified VIEW + adopt payment_native.sale_id FK", "depends_on": ["085", "088"] },
    { "new": "090", "old": "085", "package": "2D", "phase": "2D", "name": "090_venue_promoter_engine", "purpose": "promoter engine", "scope": "venue.promoter, promoter_link, attribution", "depends_on": ["082"] },
    { "new": "091", "old": "086", "package": "K", "phase": "K", "name": "091_kernel_reserve_stub", "purpose": "money-ledger stub", "scope": "kernel.reserve stub only (no writers)", "depends_on": ["077"] }
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
