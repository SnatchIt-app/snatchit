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
>   (`text NOT NULL`, CHECK ∈ `org`/`platform`/`platform_admin`) and four
>   further CHECKs. The dual-control **tier was never stored**: `pending_approval`
>   and `pending_platform_review` are result statuses of the request function, and
>   the `state` CHECK is `pending · approved · denied · cancelled · expired ·
>   stale`. An implementer branching on the only stored discriminators reaches the
>   **org arm for every pending row**. The SoD CHECK was additionally **vacuously
>   satisfiable**. Schema §1.13.2/§1.13.3.
> - **`077` — `kernel.org_member` gains `granted_at`**, and `078` seeds
>   **`authn.money_role_maturity_hours`** plus the two **`comp.*`** step-up keys:
>   both money SoD primitives compare `auth.uid()`, and an `org_owner` holds the
>   grant authority to mint the counterparty. Schema §1.13.4. **Column name, key
>   names, the three approver-class labels and the `venue.attribution` scope
>   columns are RECONCILED to the concurrent RLS/RPC remediation** (RLS §17
>   X-10…X-13, RPC §20.14 R-16…R-18), so the corpus states one design rather than
>   two compatible ones.
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

> ## ⚠ THIRD AMENDMENT PENDING RE-RATIFICATION — final reconciliation pass
>
> Two changes, both to package **`087`**. **No package is added, renumbered or
> removed; no object moves between packages; no rollback posture, rollback order
> or rollout order changes; the DAG stays acyclic and topologically ordered by
> package number; the count stays 16 (`076`–`091`).**
>
> - **`087` gains a second deployed edge function — `crm-export-worker`.** The CRM
>   spec specified the export edge as *"three routes, one function"* with **two
>   different `verify_jwt` values**. `verify_jwt` is a per-**function** Supabase
>   setting fixed at deploy time, so that was not implementable, and the resolution
>   an implementer reaches for is the permissive one — deploy at
>   `verify_jwt: false` and check the JWT inside `/download` — which leaves the
>   venue's entire attendee contact list one forgotten `getUser()` away from an
>   unauthenticated endpoint. Resolved (edge §3.7 `EDGE-2`) as **`crm-export`**
>   (actor, `POST /download` only) and **`crm-export-worker`** (`POST /build` +
>   `POST /purge`), **both `verify_jwt: true`**, the worker authenticated by
>   `CRM_EXPORT_WORKER_SECRET` in the dedicated header `X-Crm-Export-Worker` —
>   **never** by comparison against `SUPABASE_SERVICE_ROLE_KEY` (`EDGE-3`).
>   **Registry consequence:** `087`'s two `pg_cron` schedules (`/build` at 1 min,
>   `/purge` at 15 min) **retarget to the worker's URL and must send that header**.
>   These are deploy artifacts, not SQL — recorded here because this package's
>   scheduled ticks point at them and a schedule left pointing at the old target is
>   a 404 every cycle on the only agent in the design that deletes a customer CSV.
>
> - **One dependency edge added: `086 → 087` (`†`, §2.1).** `venue.list_attendees`
>   and `venue.build_export_rows` read `venue.scan`. The migration plan's §8/`087`
>   prose already said so; **every declared set omitted it** — §3 seq 12, §2.1
>   above, and the JSON `depends_on`. **Declaration-only.** Ordering was never
>   wrong (`086 < 087`), so nothing about the rollout changes; what changes is that
>   the machine-readable graph now agrees with the human one. This is the **third**
>   instance of the shape rule §6.6 / SEAM-1 exists to catch, after `079 → 085` and
>   `085 → 088` — both function-body reads, both resolved by declaring the edge —
>   and it is resolved the same way for the same reason. Leaving it undeclared
>   would make §2.2's acceptance property checkable only against prose.
>
> **Owner ratification required**, per rule §6.5. Neither change is an owner
> *decision*: the first adopts a resolution already made in the edge spec, the
> second completes a declaration the corpus already contained in prose.

> ## ⚠ FOURTH AMENDMENT PENDING RE-RATIFICATION — the K-2 / K-3 missing-object repair
>
> **No package is added, renumbered or removed. No object moves between packages. No
> rollback posture, rollback order or rollout order changes. The DAG stays acyclic and
> topologically ordered by package number. The count stays 16 (`076`–`091`).** Two
> tables gain a package contents row, one package's contents row is made specific, and
> two dependency edges are promoted from prose to declaration.
>
> **`K-2` — two contracted tables were in no package, because they were in no
> document that creates anything.** `kernel.identity_contact_pref_event` and
> `kernel.org_contact_consent_event` returned **zero hits** in this registry, in
> `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8, and in
> `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md`. They were asserted as existing by four
> documents: `PHASE_2_SPEC_FOUNDATION.md` §6 (which lists them in the canonical table
> inventory **and assigns them these package numbers**), `PHASE_2_CRM_EXPORT_SPEC.md`
> §5.1 / §11.1 elements `5a`/`5b`, `PHASE_2_RLS_PERMISSION_SPEC.md` §6/§16.6 and the
> **closed twelve-relation** `crm_export_builder` grant set of §16.10, and
> `PHASE_2_RPC_FUNCTION_CONTRACTS.md` §20, whose `set_my_contact_prefs` and
> `grant_`/`withdraw_org_contact_consent` **write a row into them in the same
> transaction**. This registry's own closing line on the second amendment — *"a
> contracted function absent from §8 is a function nobody builds"* — holds identically
> for tables. **Placed in `077` and `082`**, exactly where `PHASE_2_SPEC_FOUNDATION.md`
> §6 assigned them; the dependency graph permits both and independently **floors**
> `org_contact_consent_event` at `082`, because its `source_order_id` FK targets
> `venue.order`. No deviation was required. Full physical definition — columns, PK,
> FKs, CHECKs, indexes, AO posture, RLS posture, write authority — is
> `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` **§1.15**.
>
> **Why this one replays green and then fails in production.** `plpgsql` bodies are not
> validated at `CREATE FUNCTION`, so the whole chain applies clean with both writers
> referencing a relation nothing creates; the first fan who sets a contact preference
> gets a runtime `42P01`. **The silent direction is worse.** RLS §16.10 rules that
> omitting these two from the builder's relation set *"reproduces the zero-rows failure
> this ruling exists to close"* — `crm_export_builder` is a role **subject to RLS**, so
> a missing gate source yields no consent row for anybody, suppresses **every** contact
> cell, and emits a syntactically valid CSV whose contact column is uniformly blank.
> That reads as **"nobody consented,"** not as "denied", and `finalize_export`'s
> invariant `cells_emitted + cells_suppressed = holder row count` **balances perfectly
> at `cells_emitted = 0`**. Nothing detects it; the first signal is a venue asking why
> their audience list is empty.
>
> **`K-3` — the three purge definers had a plan row and nothing else.**
> `venue.claim_artifacts_for_purge`, `confirm_artifact_purged` and
> `reconcile_export_orphans` were added to plan §8/`087`'s Functions row by the final
> reconciliation pass, closing the plan half. **Two halves stayed open:** this registry
> named them nowhere (§2's `087` row said only *"the three purge-agent definers"*, and
> the JSON `scope` string the same), and the **physical objects they claim rows
> through were undefined** — `venue.export_job.artifact_state`, `purge_lease_until`,
> `purge_attempts`, and the **`(artifact_state, expires_at)`** index that is
> `claim_artifacts_for_purge`'s only access path, which CRM §11.2 specifies and plan
> §8/`087`'s Indexes row omitted. Both halves are closed: §2 and the JSON now **name**
> the three, and schema **§3.18** defines the substrate. **Additive to `087` only; no
> new object outside it, and no edge** — `max(087, 077) = 087` and `087` already
> declares `077`. CRM §11 calls `POST /purge` *"the only thing in this design that
> deletes bytes"*; without this substrate `revoke_export` and `sweep_expired_exports`
> only flip the **job**'s state while the CSV of attendee names and emails persists in
> the `crm-exports` bucket indefinitely. Filed as RPC §20.14 **`R-7`** and CRM `K-16`.
>
> **`087` additionally gains `venue.assert_may_request`** — the single request/download
> authorization predicate (RPC §17.22, §20; `AUTHZ-CRM2`), named by `R-7` in the same
> breath as the three definers and scheduled by nothing. Two independent
> implementations of one authorization predicate is how a download outlives the
> authority that granted it.
>
> **TWO DEPENDENCY EDGES ADDED — `077 → 082` and `078 → 082` (`‡`, §2.1).** Only the
> first is *forced* by this repair (`org_contact_consent_event.org_id` FK →
> `kernel.organization`); the second is a co-located pre-existing under-declaration
> corrected in the same pass. **Both were already named in plan §8/`082`'s own
> Dependencies prose** (*"`081` (ticket_type), `078`, `077`"*) while all four declared
> sets said `{081}` — §2 mermaid, §3 seq 7, §2.1 here and the JSON `depends_on`.
> **Declaration-only:** `077 < 078 < 081 < 082`, so ordering was never wrong and
> nothing about the rollout changes; what changes is that the machine-readable graph
> agrees with the human one. This is the **fourth** instance of the shape rule §6.6 /
> SEAM-1 exists to catch, after `079 → 085`, `085 → 088` and `086 → 087` — and it is
> resolved the same way, for the same reason. **Edge count `36 → 38`;** §2.2's
> acceptance property re-verified after the edit and reported below.
>
> **Owner ratification required**, per rule §6.5. **No change here is an owner
> *decision*:** every placement is the one `PHASE_2_SPEC_FOUNDATION.md` §6 already
> assigned or the one SEAM-1 derives, and both edges complete declarations the corpus
> already contained in prose. **One item IS an owner decision and is deliberately NOT
> taken here — `OWNER-DECISION-K2-D3`, below §7.**

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
| `077` | `072` | B | B — organizations + permissions | `077_kernel_identity_orgs_and_roles` | `kernel.identity_ext`, `organization`, `org_member` (**six** org labels, **+`granted_at`**), `org_invite` (**six** org labels), `platform_role`, `admin_audit` + org/platform role predicates · **Δ `approval_request` (**+`required_approver_class`**), `identity_demographic(_erasure)`, `identity_contact_pref`, **`identity_contact_pref_event` (AO — `K-2`)**, `org_customer_key`, `organization.payout_destination_set_by`, `identity_ext.locale`** |
| `078` | `073` | C | C — catalog | `078_catalog_reference_data_and_flags` | `catalog.venue`, `event`, `event_session` (incl. `door_open_at`), `platform_config` (**+`visibility`** — split read, not blanket public) + **all** feature-flag and config seeds, `resale_policy` · **Δ `event` marketing columns, `event_session.session_version`, `effective_freeze_at()`, `kernel.money_role_grant_matured` (SEAM-1: `max(077, 078)`)** |
| `079` | `074` | D | D — ticket kernel | `079_kernel_ticket_atom_and_ownership_log` | `kernel.tickets` (custody atom) + `kernel.ticket_ownership_log` (append-only custody ledger, C26 idempotency) · **Δ `door_freeze_override`, `is_transfer_frozen`, `lock_/unlock_ticket`, `mark_ticket_scanned`** · **`MB-4` `kernel.tg_custody_head_is_ledger_tail` — the *verify trigger* the constitution names three times and no package built** |
| `080` | `075` | E1 | E — inventory | `080_venue_staff_roles_and_predicates` | `venue.staff_role` (**six canonical labels**) + `has_venue_role`/`has_event_role` · **Δ `has_org_role_over_venue`/`_over_event`** |
| `081` | `076` | E2 | E — inventory | `081_venue_inventory` | `venue.ticket_type`, `inventory_batch`, `inventory_batch_shard`, `inventory_movement`, `inventory_hold` (oversell-safe counter) · **Δ `catalog.publish_event` authored here** |
| `082` | `077` | F | F — orders | `082_venue_orders` | `venue.order`, `venue.order_item` (primary-purchase container) · **Δ `kernel.org_contact_consent`, `kernel.org_contact_consent_event` (AO — `K-2`)** |
| `083` | `078` | G1 | G — credential infrastructure | `083_kernel_credential_infrastructure` | `kernel.signing_key` — public key + KMS handle reference only, **no private key material** · **Δ `pass_type_cert`, `wallet_pass`, `wallet_pass_device`, `wallet_pass_push_log`, `.pkpass` bucket** |
| `084` | `079` | G2 | G — credential infrastructure (ADOPT) | `084_kernel_tickets_late_binding_fks` | late-binding FKs `kernel.tickets` → `venue.ticket_type` + `kernel.signing_key` (`NOT VALID` + `VALIDATE`) — **and nothing else; the only unconditionally reversible package** |
| `085` | `080` | M | F/I bridge — kernel money-native | `085_kernel_money_native` | `kernel.payment_native`, `kernel.refund`, `kernel.payout` (link to frozen `public.payments`, never re-charge) · **Δ `void_ticket_atom` + `market.on_atom_voided` stub; the nine money-authority RPCs** · **`MB-2` `kernel.payout.hold_state`/`hold_reason_code`/`held_by`/`held_at`; `kernel.mark_payout_transfer_state`; the `venue.on_payout_settled` stub** |
| `086` | `081` | H | H — scan infrastructure | `086_venue_door_and_scan` | `venue.door_pin`, **`door_session`**, `scan_device`, `scan` (C41 re-entry hedge), `comp_allocation`, `guest_list`, `guest_entry` · **Δ `door_manifest(_entry/_delta)`, `holder_mix_snapshot`, `holder_mix_bucket`, `scan.actor_identity_id`, `assert_door_session` (token-bearing)** |
| `087` | `082` | I | I — settlement | `087_venue_settlement_and_export` | `venue.settlement`, `venue.settlement_line` (per-event money rollup → `kernel.payout`) · **Δ `export_job` + `crm-exports` bucket; `close_settlement` + its two hook stubs; the three purge-agent definers **`claim_artifacts_for_purge` · `confirm_artifact_purged` · `reconcile_export_orphans`** plus **`assert_may_request`** (`K-3`); the `export_job` purge substrate **`artifact_state` · `purge_lease_until` · `purge_attempts` + the `(artifact_state, expires_at)` claim index**; edge `crm-export` + `crm-export-worker` and their two `pg_cron` schedules** · **`MB-2b` the `venue.on_payout_settled` hook body (stub in `085`) — `venue.settlement.status='paid'` had no writer** |
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

**+** marks an edge added by the delta-spec integration; **†** marks the one edge added by the final
reconciliation pass; **‡** marks the two added by the K-2 repair. Every dependency precedes its dependent,
so the graph is a DAG and is topologically ordered by package number. **Total: 38 edges.**

| Seq | Pkg | Depends on |
|---|---|---|
| 1 | `076` | precondition (phase0 chain + `071`–`075`) |
| 2 | `077` | `076` |
| 3 | `078` | `077` |
| 4 | `079` | `077`, `078` |
| 5 | `080` | `077`, `078` |
| 6 | `081` | `078`, `080` |
| 7 | `082` | **‡`077`**, **‡`078`**, `081` |
| 8 | `083` | `078`, **+`079`** |
| 9 | `084` | `079`, `081`, `083` |
| 10 | `085` | `077`, **+`079`**, `082` |
| 11 | `086` | `079`, `080`, `081`, **+`083`** |
| 12 | `087` | `077`, `081`, `085`, **†`086`** |
| 13 | `088` | `078`, `079`, `081`, **+`085`** |
| 14 | `089` | `085`, `088` |
| 15 | `090` | `082`, **+`078`**, **+`085`**, **+`087`** |
| 16 | `091` | `077` |

Why each added edge exists:

| Edge | Because |
|---|---|
| `079 → 083` | `kernel.wallet_pass.ticket_atom_id` FK → `kernel.tickets` |
| `079 → 085` | `kernel.refund_primary_order` drives `void_ticket_atom` → `kernel.tickets` (previously undeclared) |
| `083 → 086` | `venue.door_manifest_entry.signing_key_id` FK → `kernel.signing_key` — **and `venue.door_manifest_delta.signing_key_id`, same target** (door §10.3a) |
| `085 → 088` | `market.sweep_paid_pending_sales` writes `kernel.refund` (previously undeclared) |
| `078 → 090` | `venue.promoter_code_scope.event_id` FK → `catalog.event` |
| `085 → 090` | `090` adds `kernel.payment_native.instrument_fingerprint` |
| `087 → 090` | `090` adds the cross-settlement commission unique on `venue.settlement_line` and replaces `kernel.settlement_commission_lines` |
| **‡`077 → 082`** | `kernel.org_contact_consent_event.org_id` FK → `kernel.organization` — the `K-2` table added to `082`. **The pre-existing `kernel.org_contact_consent.org_id` and `venue.order.org_id` carry the identical FK and were already under-declared**, so the edge was owed before this repair and is only *forced* by it. **Declaration-only.** |
| **‡`078 → 082`** | `venue.order.event_session_id` FK → `catalog.event_session`. Pre-existing, co-located, and named in plan §8/`082`'s own **Dependencies** prose (*"`081` (ticket_type), `078`, `077`"*) while all four declared sets said `{081}`. Corrected in the same pass because fixing one half of a two-edge under-declaration and leaving the other is worse than fixing neither. **Declaration-only.** Fourth instance of the SEAM-1 shape, after `079 → 085`, `085 → 088` and `086 → 087`. |
| **†`086 → 087`** | `venue.list_attendees` / `venue.build_export_rows` read `venue.scan` for the check-in columns (previously undeclared — named in the migration plan's §8/`087` prose, absent from every declared set). **Declaration-only:** no package added, renamed or reordered; no object moved; no rollback changed. Third instance of the SEAM-1 shape, after `079 → 085` and `085 → 088`, and resolved identically. |
| **†`077 → 078`** *(avoided, not declared)* | **`kernel.money_role_grant_matured` (RPC §1.1e, `AUTHZ-C1C`) is authored in `078`, not in `077` beside `has_org_role`.** It reads `kernel.org_member` (`077`) **and** `catalog.platform_config` together with the `authn.money_role_maturity_hours` seed (`078`), so SEAM-1 gives `max(077, 078) = 078`. Authoring it beside the other org-plane predicates — the intuitive placement, and the wrong one — would create a forward reference to a table and a seed row that do not exist yet, and the helper would return `false` for every caller during `077`'s own replay while looking correct. **Fourth instance of the SEAM-1 shape, after `079 → 085`, `085 → 088` and `086 → 087`; this one is *avoided at authoring time* rather than declared after the fact, which is what SEAM-1 is for.** `078` already depends on `077`, so **no edge is added, no package is added, renamed or reordered, and the canonical band stays `076`–`091`.** |

> **`MP-1` adds no edge, and that is a checked result rather than an assumption.** Door §10.3/§10.3a add
> `ticket_type_id` FK → `venue.ticket_type` to `venue.door_manifest_entry` **and** `venue.door_manifest_delta`.
> `venue.ticket_type` is created in **`081`**, and `086` already declares `depends_on: ["079","080","081","083"]`
> — so the edge `081 → 086` exists, and this is **not** a fourth instance of the SEAM-1 shape. Recorded
> explicitly because an undeclared FK across packages is exactly what SEAM-1 is for, and "we checked and it was
> already there" is worth writing down once so the next reviewer does not re-derive it. **No package is added,
> renamed or reordered; the `076`–`091` band is untouched.**

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

**Second acceptance property — the four declared edge sets are identical.** The dependency graph is written
down in **four** places: `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §2's mermaid DAG, that plan's §3 rollout
table, §2.1 above, and the JSON `depends_on` in §3. **They must be the same set, exactly** — not merely
compatible, and not merely "the mermaid is a superset". Three of the four instances found so far
(`079 → 085`, `085 → 088`, `086 → 087`) were caught only because someone read the prose; the fourth
(`077 → 082` / `078 → 082`) was caught because a new table's FK could not be declared without it.

> **Verified after the K-2 repair (2026-08-28).** All four sets enumerate the **same 38 edges**. Every
> declared dependency **strictly precedes** its dependent by package number, so the graph is acyclic and
> topologically ordered by number. The mermaid edge set **equals** the declared edge set — no edge is in
> one and not the others.

---

## 3. Machine-readable

```json
{
  "schema_version": 2,
  "ratified": "2026-08-27",
  "amended": "2026-08-27",
  "amendment_status": "PENDING_RE_RATIFICATION",
  "amendment_count": 4,
  "declared_edge_count": 38,
  "edge_set_parity_verified": "2026-08-28",
  "amendment_summary": "Delta-spec integration. Structural: kernel.approval_request placed in 077 (it had no package and no home). Scope: 083 and 087 renamed; seven dependency edges added (an eighth, 086 -> 087, added later by the final reconciliation pass as a declaration-only correction); per-package object sets extended. FOURTH AMENDMENT (K-2/K-3): kernel.identity_contact_pref_event placed in 077 and kernel.org_contact_consent_event placed in 082 — both were contracted by four documents and created by none; 087 names the three purge definers and assert_may_request explicitly and gains the export_job purge substrate; two declaration-only edges added, 077 -> 082 and 078 -> 082, bringing the declared edge count to 38. Count unchanged at 16 unless COND-B (notify) is ruled Gate P.",
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
      { "name": "market.on_atom_voided", "stub_in": "085", "replaced_in": "088", "neutral_result": "no-op" },
      { "name": "venue.on_payout_settled", "stub_in": "085", "replaced_in": "087", "neutral_result": "no-op", "added_by": "MB-2b", "seam1": "real body reads kernel.payout (085) and writes venue.settlement (087) -> max(085,087)=087; 085 -> 087 already declared, no edge added" }
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
    { "new": "077", "old": "072", "package": "B", "phase": "B", "name": "077_kernel_identity_orgs_and_roles", "purpose": "organizations + permissions + dual-control substrate", "scope": "identity_ext (+locale), organization (+payout_destination_set_by), org_member (six org labels, +granted_at), org_invite (six org labels), platform_role, admin_audit, approval_request (+required_approver_class), identity_demographic(_erasure), identity_contact_pref, identity_contact_pref_event (AO), org_customer_key + role predicates — TWELVE tables", "depends_on": ["076"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["kernel.approval_request", "kernel.approval_request.required_approver_class", "kernel.org_member.granted_at", "kernel.identity_demographic", "kernel.identity_demographic_erasure", "kernel.identity_contact_pref", "kernel.org_customer_key", "kernel.organization.payout_destination_set_by", "kernel.identity_ext.locale", "kernel.identity_contact_pref_event"], "k2_added": ["kernel.identity_contact_pref_event"] },
    { "new": "078", "old": "073", "package": "C", "phase": "C", "name": "078_catalog_reference_data_and_flags", "purpose": "catalog + all config/flag seeds", "scope": "catalog.venue/event/event_session/platform_config (+visibility, split read)/resale_policy + every feature-flag and config seed in the chain", "depends_on": ["077"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["catalog.platform_config.visibility", "catalog.event.description", "catalog.event.hero_image_ref", "catalog.event.category", "catalog.event.genre_tags", "catalog.event_session.session_version", "catalog.effective_freeze_at", "kernel.money_role_grant_matured"], "seam1_note": "kernel.money_role_grant_matured is authored HERE, not in 077 beside has_org_role: it reads kernel.org_member (077) AND catalog.platform_config plus its authn.money_role_maturity_hours seed (078), so max(077,078)=078. 078 already depends on 077, so no edge is added. RPC contract §1.1e (AUTHZ-C1C)." },
    { "new": "079", "old": "074", "package": "D", "phase": "D", "name": "079_kernel_ticket_atom_and_ownership_log", "purpose": "ticket kernel", "scope": "kernel.tickets + kernel.ticket_ownership_log (C26 idempotency) + the complete transfer-freeze input set", "depends_on": ["077", "078"], "rollback_posture": "FORWARD_FIX_ONLY", "delta_added": ["kernel.door_freeze_override", "kernel.is_transfer_frozen", "kernel.tickets.resale_state:refund_hold"], "mb4_added": ["kernel.tg_custody_head_is_ledger_tail"], "mb4_note": "The head-equals-log-tail verify trigger named three times in SNATCH_IT_DOMAIN_ARCHITECTURE.md and cited by door §7.6 as what makes bypass structurally impossible existed in no package. CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED on kernel.tickets; asserts to_identity and credential_version_after of the greatest-sequence log row equal the head. state is deliberately outside the clause set. SEAM-1 max(079,079)=079; no edge, no package change. Schema §1.6.2. Also carries kernel.sweep_expired_ticket_atoms (MN-4, schema §1.5.1), SEAM-1 max(078,079)=079.", "mn4_added": ["kernel.sweep_expired_ticket_atoms"] },
    { "new": "080", "old": "075", "package": "E1", "phase": "E", "name": "080_venue_staff_roles_and_predicates", "purpose": "inventory (roles)", "scope": "venue.staff_role (six canonical labels, text+CHECK) + has_venue_role/has_event_role/has_org_role_over_venue/has_org_role_over_event", "depends_on": ["077", "078"], "rollback_posture": "CLEAN_WHILE_EMPTY" },
    { "new": "081", "old": "076", "package": "E2", "phase": "E", "name": "081_venue_inventory", "purpose": "inventory (capacity)", "scope": "ticket_type, inventory_batch, inventory_batch_shard, inventory_movement, inventory_hold + catalog.publish_event", "depends_on": ["078", "080"], "rollback_posture": "CLEAN_WHILE_EMPTY" },
    { "new": "082", "old": "077", "package": "F", "phase": "F", "name": "082_venue_orders", "purpose": "orders", "scope": "venue.order + venue.order_item + kernel.org_contact_consent + kernel.org_contact_consent_event (AO)", "depends_on": ["077", "078", "081"], "depends_on_added_by_k2_repair": ["077", "078"], "depends_on_note": "077 is FORCED by kernel.org_contact_consent_event.org_id -> kernel.organization; 078 is a co-located pre-existing under-declaration (venue.order.event_session_id -> catalog.event_session). Both were already named in migration plan section 8/082 Dependencies prose while all four declared sets said [081]. Declaration-only: 077 < 078 < 081 < 082, so ordering was never wrong.", "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["kernel.org_contact_consent"], "k2_added": ["kernel.org_contact_consent_event"] },
    { "new": "083", "old": "078", "package": "G1", "phase": "G", "name": "083_kernel_credential_infrastructure", "purpose": "credential infrastructure", "scope": "kernel.signing_key + pass_type_cert + wallet_pass + wallet_pass_device + wallet_pass_push_log + .pkpass bucket (public key / KMS handle refs only, no key material)", "depends_on": ["078", "079"], "rollback_posture": "CLEAN_WHILE_EMPTY", "renamed_from": "083_kernel_signing_key", "delta_added": ["kernel.pass_type_cert", "kernel.wallet_pass", "kernel.wallet_pass_device", "kernel.wallet_pass_push_log"] },
    { "new": "084", "old": "079", "package": "G2", "phase": "G", "name": "084_kernel_tickets_late_binding_fks", "purpose": "credential infrastructure (ADOPT)", "scope": "late-binding FKs kernel.tickets -> ticket_type + signing_key, and nothing else", "depends_on": ["079", "081", "083"], "rollback_posture": "REVERSIBLE", "invariant": "Creates zero relations and zero routines. This purity is what makes its rollback unconditionally reversible; nothing may be added to it." },
    { "new": "085", "old": "080", "package": "M", "phase": "F/I bridge", "name": "085_kernel_money_native", "purpose": "kernel money-native + money authority", "scope": "kernel.payment_native, kernel.refund, kernel.payout (+hold_state/hold_reason_code/held_by/held_at), void_ticket_atom + on_atom_voided stub, the nine money-authority RPCs, mark_payout_transfer_state + the venue.on_payout_settled stub", "depends_on": ["077", "079", "082"], "rollback_posture": "FORWARD_FIX_ONLY", "mb2_added": ["kernel.payout.hold_state", "kernel.payout.hold_reason_code", "kernel.payout.held_by", "kernel.payout.held_at", "kernel.mark_payout_transfer_state", "venue.on_payout_settled (stub)"], "mb2_note": "MB-2a: kernel.payout.status='held' was relied on by MONEY §8.4/§12, ratification O-3, RPC §17.7 and dashboard §14.5, and was never a member of the status set. It is NOT added to status (that is lossy and makes RPC §11.3 release unimplementable); a hold is an orthogonal column, the same shape as the frozen public.transfers.payout_review_status discipline hold_payout is contracted to extend. MB-2b: paid/failed/reversed and stripe_transfer_ref had no writer; mark_payout_transfer_state (SEAM-1 max(077,085)=085) is the writer. No package, edge or renumbering added. Schema §1.9.1/§1.9.2." },
    { "new": "086", "old": "081", "package": "H", "phase": "H", "name": "086_venue_door_and_scan", "purpose": "scan infrastructure + door manifest + holder mix", "scope": "door_pin, door_session, scan_device, scan (+actor_identity_id, +manifest_id), comp_allocation, guest_list, guest_entry, door_manifest(_entry/_delta), holder_mix_snapshot, holder_mix_bucket", "depends_on": ["079", "080", "081", "083"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["venue.door_session", "venue.door_manifest", "venue.door_manifest_entry", "venue.door_manifest_delta", "venue.holder_mix_snapshot", "venue.holder_mix_bucket", "venue.scan.actor_identity_id", "venue.scan.manifest_id", "venue.scan_device.manifest_id"] },
    { "new": "087", "old": "082", "package": "I", "phase": "I", "name": "087_venue_settlement_and_export", "purpose": "settlement + CRM export", "scope": "venue.settlement + venue.settlement_line + venue.export_job (incl. the purge substrate artifact_state / purge_lease_until / purge_attempts and the (artifact_state, expires_at) claim index) + crm-exports bucket + close_settlement and its two hook stubs + the three purge-agent definers + assert_may_request", "depends_on": ["077", "081", "085", "086"], "depends_on_added_by_reconciliation": ["086"], "edge_functions": [ { "name": "crm-export", "routes": ["POST /download"], "class": "A", "verify_jwt": true, "worker_secret_in_env": false }, { "name": "crm-export-worker", "routes": ["POST /build", "POST /purge"], "class": "B", "verify_jwt": true, "worker_secret_in_env": true, "worker_header": "X-Crm-Export-Worker", "secret_name": "CRM_EXPORT_WORKER_SECRET", "never_compared_against": "SUPABASE_SERVICE_ROLE_KEY" } ], "cron_schedules": [ { "target": "crm-export-worker", "route": "POST /build", "cadence": "1 minute", "header": "X-Crm-Export-Worker" }, { "target": "crm-export-worker", "route": "POST /purge", "cadence": "15 minutes", "header": "X-Crm-Export-Worker", "note": "daily orphan reconciliation rides this route" } ], "mb2_added": ["venue.on_payout_settled (real body; stub in 085)", "venue.settlement.status='paid' writer"], "rollback_posture": "CLEAN_WHILE_EMPTY", "renamed_from": "087_venue_settlement", "delta_added": ["venue.export_job", "storage.buckets:crm-exports", "crm_export_builder role"], "k3_named": ["venue.claim_artifacts_for_purge", "venue.confirm_artifact_purged", "venue.reconcile_export_orphans", "venue.assert_may_request", "venue.export_job.artifact_state", "venue.export_job.purge_lease_until", "venue.export_job.purge_attempts", "index:venue.export_job(artifact_state, expires_at)"], "k3_note": "The three purge definers reached migration plan section 8/087 by the final reconciliation pass but were named nowhere here and had no physical substrate in the schema spec. max(087 venue.export_job, 077 kernel.admin_audit) = 087 by SEAM-1; 087 already declares 077, so no edge is created. This is the only agent in the design that deletes bytes." },
    { "new": "088", "old": "083", "package": "J1", "phase": "J", "name": "088_market_native_rail", "purpose": "native marketplace rail + custody engine", "scope": "listing_native, auction, offer, market_sale, p2p_transfer, transfer_ticket_ownership, catalog.cancel_event", "depends_on": ["078", "079", "081", "085"], "rollback_posture": "CLEAN_WHILE_EMPTY", "restores_hooks": ["kernel.settlement_royalty_lines", "market.on_atom_voided"] },
    { "new": "089", "old": "084", "package": "J2", "phase": "J", "name": "089_market_bridge_view_and_late_fk", "purpose": "native marketplace bridge (ADOPT)", "scope": "market.listing_unified VIEW + adopt payment_native.sale_id FK", "depends_on": ["085", "088"], "rollback_posture": "REVERSIBLE" },
    { "new": "090", "old": "085", "package": "2D", "phase": "2D", "name": "090_venue_promoter_engine", "purpose": "promoter engine", "scope": "venue.promoter (+tier/party_kind/commission_kind/commission_flat_minor), promoter_link (+status), attribution (+15 cols), promoter_code, promoter_code_scope, attribution_review, the cross-settlement commission unique, payment_native.instrument_fingerprint", "depends_on": ["078", "082", "085", "087"], "rollback_posture": "CLEAN_WHILE_EMPTY", "restores_hooks": ["kernel.settlement_commission_lines"], "delta_added": ["venue.promoter_link.status", "venue.promoter_code", "venue.promoter_code_scope", "venue.attribution_review", "venue.settlement_line:uq_promoter_commission_cause_ref", "kernel.payment_native.instrument_fingerprint", "venue.order.attribution_candidate_code_id", "venue.order.attribution_candidate_link_id"] },
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

---

### 7.1 Owner decisions surfaced by the K-2 / K-3 repair — recorded, NOT taken

The repair placed every object by a rule (`PHASE_2_SPEC_FOUNDATION.md` §6's assignment, or SEAM-1's
`max()`), so **no placement is a decision.** Two questions it hit **are** decisions about who may do what,
and neither is answerable from the corpus. They are recorded here so a ruling is an apply rather than a
design exercise, and **left with the owner.**

| ID | Question | Why the repair could not answer it | Consequence of each answer |
|---|---|---|---|
| **`OWNER-DECISION-K2-D3`** | **`D-3`'s outstanding sign-off now covers SIX relations, not four.** `PHASE_2_CRM_EXPORT_SPEC.md` §11.2 files `ON DELETE CASCADE` from `auth.users` on the contact tables as *"a named exception requiring acknowledgment"* — the corpus default is `ON DELETE RESTRICT` — still owed from the **schema and RLS spec owners**. The two `_event` ledgers inherit the cascade. | The inheritance is mechanical (an append-only history of a grant belonging to nobody is the same residue with a timestamp on it, and `RESTRICT` here would make an **account deletion fail** on the log of a permission the account already withdrew) — **but `D-3` is an unresolved sign-off, and silently widening its scope from four relations to six is exactly the shape of change rule §6.5 exists to stop.** | **CASCADE (recommended, and what §1.15 specifies):** deletion is clean; the fan's evidence dies with the account, consistent with `§9.2`. **RESTRICT:** account deletion blocks on consent history, which contradicts `020`'s `delete_account_cleanup` — this answer needs an erasure path designed, and none exists. |
| **`OWNER-DECISION-K2-READ`** | **May the SUBJECT read their own consent *history*, or only their current state?** `kernel.list_my_org_contact_consents` returns current state. `PHASE_2_CRM_EXPORT_SPEC.md` §9.2's pre-deletion screen shows *which venues exported a list with you* — that is **export** history, not **consent** history. Whether a fan may see *"you allowed this venue on 3 March and withdrew on 9 May"* is stated by **no document**. | §1.15 specifies both ledgers **deny-all with an empty grant set**, reachable only by the export gate — the strictest posture, and the one every cited document already assumes. That is the safe default, **but it is a default this repair chose by inheritance, not a ruling.** CRM §5.3 argues at length that *"a consent record is the person's own evidence in the dispute they are most likely to have"* — which is an argument **for** a read path, and no read path exists. | **NO (current, safe):** nothing changes; the §5.3 evidence argument stands unimplemented. **YES:** one new definer RPC, own-`identity_id` only, on `082` (SEAM-1 `max()`), and the `_event` tables' grant set stays empty because the RPC is a definer — **no RLS posture changes either way.** The cost is one function, not a permission model. |

**Neither blocks the fourth amendment.** `K-2` and `K-3` close with the strict posture in both cases; a
later ruling on `OWNER-DECISION-K2-READ` is **additive** (one RPC) and a ruling on `OWNER-DECISION-K2-D3`
either confirms what is written or opens an erasure-path design that `D-3` already owed.
