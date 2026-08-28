# Phase 2 — Scope Amendment (2026-08)

**Status:** INTEGRATION LAYER. Design-only — **no SQL, no migrations, no code.**
**Baseline:** `phase2/consolidation` @ `64d2aac` (post four integration passes).
**Scope:** the six owner-approved Phase-2 additions — Apple Wallet · attendee demographics · promoter codes · venue CRM / attendee export · notifications · venue dashboard.

> ## What this document is, and what it deliberately is not
>
> It is a **map**. For each of the six features it says, per layer, **what changes · what class of change it is · which spec section owns it · which migration package carries it.**
>
> It is **not** a restatement. Every implementation detail already lives in a spec that owns it; that spec stays the single source of truth. **Where a row here and the cited spec disagree, the cited spec wins and this row is a defect** — report it, do not follow it.
>
> It **decides nothing that belongs to the owner.** §14 is an index of open decisions, not a set of answers. Where two specs contradict each other, §15 records the contradiction and names the pass that owns the reconciliation; it does not pick a side.

**Authority order for every citation below.**

1. `_governance/PHASE_2_RATIFICATION_RECORD.md` — the 44 ratified rows (C26–C52 · O6–O8 · O-1…O-5 · D1–D8).
2. `SNATCH_IT_DOMAIN_ARCHITECTURE.md` (**DA**) and `SNATCH_IT_CANONICAL_DATA_MODEL.md` (**CDM**) — the constitutions.
3. `PHASE_2_PACKAGE_REGISTRY.md` — **canonical** for every migration number. Never re-derive a number; cite the registry.
4. The implementation specs — physical schema · migration plan · RLS · RPC · edge · RN · venue dashboard.
5. The eight delta specs — door lifecycle · money authority · role model · demographics/privacy · promoter codes · notifications · CRM export · Apple Wallet.

**Short names used in every table below.**

| Short | File (all under `docs/architecture/`) |
|---|---|
| `SCHEMA` | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` |
| `PLAN` | `PHASE_2_SUPABASE_MIGRATION_PLAN.md` |
| `REGISTRY` | `PHASE_2_PACKAGE_REGISTRY.md` |
| `RLS` | `PHASE_2_RLS_PERMISSION_SPEC.md` |
| `RPC` | `PHASE_2_RPC_FUNCTION_CONTRACTS.md` |
| `EDGE` | `PHASE_2_EDGE_FUNCTION_SPEC.md` |
| `RN` | `PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md` |
| `VD` | `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md` |
| `WALLET` · `DEMOG` · `PROMO` · `CRM` · `NOTIF` · `DOOR` · `MONEY` · `ROLE` | the eight delta specs |
| `RATIFY` | `_governance/PHASE_2_RATIFICATION_RECORD.md` |

**The reading rule for the two spec families.** The implementation specs now *contain* the deltas — four integration passes folded them in. So: **cite the integrated spec for where a thing now lives; cite the delta spec for why it is shaped that way.** A delta spec's own package assignment is superseded wherever `SCHEMA` §13.1/§13.5 disagrees with it (four such moves exist; each is listed in §15).

---

## 1. Scope statement

### 1.1 What this amendment adds

Six features, **all additive**, all landing inside the already-ratified sixteen-package chain `076`–`091` (`REGISTRY` §2). **No new package number is created by any of the six.** The only thing that could add a seventeenth package is the `notify` ruling — §13, and that ruling is the owner's.

| # | Feature | One-line scope | Primary packages |
|---|---|---|---|
| 1 | **Apple Wallet** | `.pkpass` as a *second delivery vehicle* for the credential the platform already signs; pass registry, device registry, PassKit web service, APNs push | `083` (+ seeds `078`) |
| 2 | **Attendee demographics** | one optional self-declared field, per-identity; a k-anonymised per-session **holder-mix** rollup for operators | `077` (fan side) · `086` (rollup) |
| 3 | **Promoter codes** | code-based attribution alongside links, a precedence rule, an append-only attribution + review ledger, commission at settlement | `090` |
| 4 | **Venue CRM / attendee export** | holder-keyed roster read, contact-preference and per-org consent model, async export job to a signed artifact | `077` · `082` · `087` |
| 5 | **Notifications** | a type registry, preference model, mandatory class, and a five-hop delivery pipeline extending the production notifier | **UNSCHEDULED — §13** |
| 6 | **Venue dashboard** | the operator web surface; twelve areas, role × surface matrix, every control mapped to a named backend capability | no package of its own — it is a **consumer** of `077`–`090` |

### 1.2 What this amendment does **not** change

Every item below is ratified constitution or frozen implementation contract. **No row of this document may be read as amending one.** If a feature appears to need one changed, that is a stop-and-ask, not a design choice.

| Invariant | Stated at | How the six stay inside it |
|---|---|---|
| **The ticket atom** is the single custody object | `SCHEMA` §1.5 · CDM §1.1 · DA §1.3 | No feature adds a second atom or a parallel entitlement. Wallet is a *rendering* of the atom's credential (`WALLET` §2.1); the holder-mix rollup *reads* `current_owner_id` and writes nothing (`DEMOG` §4.1). |
| **Append-only ownership history** | `SCHEMA` §1.6 · C26 (`RATIFY`) | Nothing in the six writes `kernel.ticket_ownership_log` outside the transfer engine. `venue.attribution` and `venue.attribution_review` are separate append-only ledgers, not custody (`PROMO` §1.6, VD §22.4). |
| **One transfer engine — the sole custody writer** | DA §9.4 · `RPC` §7.2 · `SCHEMA` §13.2 FR-3 | `kernel.transfer_ticket_ownership` stays the only mover; Wallet supersession runs *after* it, deliberately outside the custody transaction (`WALLET` §7.1; `REGISTRY` §7 COND-A). |
| **Credential-as-delivery** — authority is server-side, the credential is a bearer artifact | `WALLET` §2.1/§2.5 · `EDGE` §5 (C33) | The `.pkpass` carries the same token profile family; the scanner's decision logic is unchanged (`WALLET` §10.1 — `NO CHANGE`). |
| **Two-rail honesty** — native and external never share the custody path | DA §0.3, §10.1 · `SCHEMA` §4.6 | No feature blurs the rails. CRM export's `acquired_via` mapping (`CRM` §2.5) *reports* the rail; it does not merge them. |
| **Additive modular monolith on Postgres schemas** | DA §0.1, §5.0 | All six live in the existing `kernel`/`catalog`/`venue`/`market` contexts. The only proposed new context is `notify` — **unresolved, §13.** |
| **Frozen Stripe core** — no column is ever added to `public.payments` | `RATIFY` OBS-1 · `SCHEMA` §5 · DA §5.6 | Promoter codes reach money via `kernel.payment_native.instrument_fingerprint` (`PROMO` §1.8, pkg `090`), never `public.payments`. |
| **SSCAS discipline** — the closed set of cross-aggregate transactions | C28 (`RATIFY`) · `RPC` §14 | No feature claims a new SSCAS member. The one candidate — `kernel.approval_request` — is named as an open question, **not decided here** (§14 OD-01). |
| **Global lock ordering** | `SCHEMA` §0.9 · `RPC` §14.2 | `PROMO` §7.9 argues C28 needs no amendment for attribution; `DOOR` §5 serialises manifest-open against transfer under the existing order. |
| **The event envelope (C12)** | CDM §15 C12 · DA §6.2/§6.3 | Every feature that emits one assumes a carrier that **nothing schedules** — §13. This is the amendment's largest unresolved dependency. |
| **Authoritative risk gates and flag discipline** | `PLAN` §4 · A8 | Every flag ships **`false`**, seeded by `078`, flipped only by an audited `catalog.set_platform_config`. **Seeding is a migration; flipping is never a migration.** (`SCHEMA` §13.5-D.) |
| **Server-authoritative money and custody** | `RLS` §5 · `RPC` §0.7 | Every money/custody table stays RPC-only-write. No feature grants a client write. GP-1 holds across all six (`RLS` §16). |

**Two further disciplines this amendment inherits rather than restates:** the SEAM-1/SEAM-2 function-placement rules (`REGISTRY` §2.2) and the seven-way change classification (§2.2 below). Both are binding on every row here.

---

## 2. How to read the per-feature maps

### 2.1 The fifteen layers

Each feature gets one section with the same fifteen rows, in this order. A row that genuinely has no content says **`—`** and says why; it is never omitted.

`canonical data model` · `physical schema` · `migration package` · `RLS` · `RPC` · `Edge Function` · `event envelope` · `RN UI` · `venue dashboard` · `audit` · `privacy` · `tests` · `feature flag` · `rollout gate` · `open decisions`

### 2.2 The seven classifications

Every backend change carries exactly one, per the legend the delta specs share (`NOTIF` §0.1; `WALLET` §11.10; `PROMO` §15).

| Tag | Meaning |
|---|---|
| `NO SCHEMA CHANGE` | uses an object that exists (or is already scheduled) unchanged |
| `ADDITIVE SCHEMA CHANGE` | new table/column/index/constraint/seed row; nothing dropped, nothing re-typed |
| `SPEC CORRECTION` | a frozen spec says something wrong or unbuildable; the correction is documentation, not DDL |
| `NEW RPC` | a new `SECURITY DEFINER` Postgres function |
| `NEW EDGE FUNCTION` | a new Supabase Edge Function (deployed, never migrated) |
| `NEW RN SURFACE` | a new React Native screen or behaviour |
| `NEW DASHBOARD SURFACE` | a new `web/` venue-dashboard screen or behaviour |

### 2.3 Citation convention

`SPEC §n` is a section reference in the file named by §0's short-name table. A row with no citation is a defect in this document. **Package numbers are cited from `REGISTRY` §2 only** — never re-derived, never shifted, never inferred from a delta spec's own text (`REGISTRY` §4 records the four competing scales that produced last time).

---

## 3. Package placement — the six features at a glance

Every feature is placed inside `076`–`091`. Nothing else is claimed.

| Feature | Packages carrying it | Registry row | Note |
|---|---|---|---|
| **Apple Wallet** | **`083`** (pass registry, device registry, push log, `.pkpass` bucket, `pass_type_cert`) · `078` (six config seeds) | `REGISTRY` §2 `083_kernel_credential_infrastructure` | `WALLET` §11.10 said `084`; moved to `083` by `SCHEMA` §13.5-C so the adopt package stays unconditionally reversible |
| **Attendee demographics** | **`077`** (`identity_demographic`, `_erasure`, three fan RPCs) · **`086`** (`holder_mix_snapshot`, `holder_mix_bucket`, `refresh_`/`get_holder_mix`, R4 job) | `REGISTRY` §2 rows `077`, `086` | `DEMOG` §10.1 said `087` for the rollup; moved to `086` by `SCHEMA` §13.5-A — `086` already depends on every input, `087` does not depend on `079` |
| **Promoter codes** | **`090`** — every object, without exception | `REGISTRY` §2 `090_venue_promoter_engine` | Accepted whole, including the spec's refusal to split the feature (`SCHEMA` §13.5-E): `090`'s rollback is clean while empty, so splitting would make the feature un-revertible as a unit |
| **Venue CRM / export** | **`077`** (`identity_contact_pref`, `org_customer_key` + 2 RPCs) · **`082`** (`org_contact_consent` + 3 RPCs) · **`087`** (`export_job`, `crm-exports` bucket, 8 export RPCs, `crm_export_builder`) · `078` (config seeds) · `090` (template bump to `audience_v2`) | `REGISTRY` §2 rows `077`, `082`, `087`, `090` | `CRM` §11.1-20 put its seeds in `087`; consolidated into `078` by `SCHEMA` §13.5-D |
| **Notifications** | **NONE — unscheduled.** Would be **`092`** if `notify` is ruled Gate P | `REGISTRY` §7 COND-B | Two additive columns it needs are already scheduled independently: `catalog.event_session.session_version` → `078` (Δ-N1) and `kernel.identity_ext.locale` → `077` (Δ-N2), both `SCHEMA` §13.1 |
| **Venue dashboard** | **none of its own.** Consumes `077`–`090` | VD §20 read index; VD §20A control map | It is a client. Its only *backend* asks are Δ5–Δ12 and U-1…U-10, all open (§14) |

**Consequence worth stating once.** Five of the six features are fully placed. **The sixth — notifications — is the only one with no package**, and the dashboard's §16.5 carries a *binding* dependency on it (`RLS` MD-10). That is not a gap in this document; it is open decision **OD-13/OD-14** (§13, §14).

---

## 4. Feature 1 — Apple Wallet

**One sentence.** A `.pkpass` is a **second delivery vehicle** for a credential the platform already mints and already verifies; authority stays in the atom, and the scanner is not told Wallet exists.

**Why it is shaped this way:** `WALLET` §2.1–§2.5 (where authority actually lives) and §0.2 (defect **W-3** — the offline door cannot detect a stale pass; VERIFIED, and *not* fixed by this feature alone).

| # | Layer | What changes | Class | Owning spec § | Pkg |
|---|---|---|---|---|---|
| 1 | **Canonical data model** | No new canonical object. The pass is a *rendering* of the Issued Credential CDM already defines; `credential_version` stays the one counter that invalidates | `NO SCHEMA CHANGE` | CDM §1.1 (Issued Credential) · `WALLET` §3.3 (pass generation ≠ `credential_version`) | — |
| 2 | **Physical schema** | `kernel.pass_type_cert`; `kernel.wallet_pass` (partial `UNIQUE(ticket_atom_id) WHERE status='issued'`); `kernel.wallet_pass_device`; `kernel.wallet_pass_push_log` (AO); private `.pkpass` bucket. **No secret on any row** | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1 (`083` rows) · `WALLET` §11.1–§11.4 | `083` |
| 2b | | Six `catalog.platform_config` seed keys | `ADDITIVE SCHEMA CHANGE` (rows) | `WALLET` §11.5 · `SCHEMA` §13.5-D | `078` |
| 3 | **Migration package** | All five objects in `083_kernel_credential_infrastructure`; seeds in `078`. Adds DAG edge `079 → 083` | — | `REGISTRY` §2, §2.1 · `SCHEMA` §13.5-C, §13.6 | `083` |
| 4 | **RLS** | Four new matrices; deny-all / column-scoped. `authenticated` holds **no** SELECT on `auth_token_enc`, `auth_token_hash`, `serial_no_opaque`; no `venue_*`/`org_*` role reads any wallet table | `ADDITIVE SCHEMA CHANGE` (policies) | `RLS` §16.8 · policy names `RLS` §16.10 | `083` |
| 5 | **RPC** | **13 new**: `mint_wallet_pass` (EDGE-FRONTED, `authenticated`) · `revoke_wallet_pass` · `provision`/`rotate`/`revoke_pass_type_cert` (platform-only, dual-controlled) · `supersede_wallet_passes_for_atom` · `touch_wallet_pass` · `get_wallet_pass_build_context` · `register`/`unregister_wallet_pass_device` · `list_updated_wallet_passes` · `record_wallet_push_result` · `sweep_wallet_pass_lifecycle` — the last eight `EXEC: DEF` | `NEW RPC` ×13 | `RPC` §17.23 · EXEC authority `RLS` §11.7 | `083` |
| 5b | | **SSCAS: n/a.** No wallet RPC takes a lock in the six money/custody ranks — that property is what lets Wallet be added **without re-proving** `RPC` §14.2, and it must be preserved by any future Wallet RPC | `NO SCHEMA CHANGE` | `RPC` §17.23 (locks paragraph) · `WALLET` §11.10 (SSCAS `NO CHANGE`) | — |
| 6 | **Edge Function** | `wallet-pass-issue` (build + sign the `.pkpass`) · `wallet-pass-webservice` (PassKit device web service, `verify_jwt=false`) · `wallet-pass-push` (APNs) · `pass-cert-provision` | `NEW EDGE FUNCTION` ×4 | `EDGE` §3.10–§3.13 · `WALLET` §6.1, §8.4 | deploy, gated on `083` |
| 7 | **Event envelope** | Pass supersession runs **in the outbox consumer**, deliberately outside the custody transaction, so a Wallet failure can never roll back or block a transfer. **The carrier does not exist**: `wallet-pass-push` is contracted to drain an outbox nothing schedules | **BLOCKED — §13** | `RPC` §17.23 (`supersede_…`) · `WALLET` §6.3 · `SCHEMA` §13.2 **FR-9**, §13.3 | COND-A |
| 8 | **RN UI** | "Add to Apple Wallet" control · re-add · transfer-in add · the failure/recovery states · **no holder name on the pass** | `NEW RN SURFACE` | `RN` §5.1–§5.6 · `WALLET` §9.1–§9.3 | client, gated on `083` |
| 8b | | Scanner: **no change at all** — the scanner must not know Wallet exists | `NO CHANGE` | `WALLET` §10.1 · `RN` §5.6 | — |
| 9 | **Venue dashboard** | Pass-registry / certificate-expiry operations view | `NEW DASHBOARD SURFACE` | `WALLET` §11.10, §13 | client |
| 10 | **Audit** | `kernel.admin_audit` rows for pass revocation (in-txn) and for every certificate provision/rotate/revoke (dual-controlled). `kernel.wallet_pass_push_log` is the AO delivery trail | `NO SCHEMA CHANGE` (uses `077`'s `admin_audit`) | `RPC` §17.23 · `RLS` §11.7 | `083` |
| 11 | **Privacy** | No holder name on a lock screen (physical-safety ruling); `get_wallet_pass_build_context` returns an **identical shape for "not found" and "bad token"**, so it is not an enumeration oracle; constant-time token comparison (I-9) | — | `WALLET` §9.1 · `RPC` §17.23 · assertion `RLS` `T-RLS-COL-03` | `083` |
| 12 | **Tests** | `T-RPC-WALLET-01..03` (structural: references neither `market.*` nor the ownership log; the kill switch is not role-bypassable; constant-time compare with no bare `=` on `auth_token_hash`) · `T-RLS-COL-03` · the pgTAP list in `WALLET` §12 | — | `RPC` §18 · `RLS` §16.11 · `WALLET` §12 | — |
| 13 | **Feature flag** | **`wallet.apple.enabled` — boolean, seeded `false` by `078`.** Kill switch, **not role-bypassable**: `platform_admin` also receives `wallet_disabled`. Flipped only by an audited `catalog.set_platform_config` — never by a migration | `ADDITIVE SCHEMA CHANGE` (seed) | `WALLET` §11.5 · `PLAN` §4 · `RPC` §17.23 | `078` |
| 14 | **Rollout gate** | `083` may apply while the flag is OFF (`PLAN` §3 seq 8). The flag may not be flipped until **§11 HG-1** is satisfied and the `WALLET` §13 operational checklist is green | — | `PLAN` §3, §4 · `WALLET` §13 · **§11 HG-1** | — |
| 15 | **Open decisions** | OQ-W1…OQ-W10 → deduplicated into §14 as **OD-23…OD-29** (OQ-W4 merges with `DOOR` OQ-5 → OD-25; OQ-W5 merges with `EDGE` §12.2 → OD-26). OQ-W3 (sequencing) is promoted to a **hard gate**, not a decision | — | `WALLET` §15 | — |

---

## 5. Feature 2 — Attendee demographics

**One sentence.** One optional self-declared field per identity, plus one k-anonymised per-session **holder-mix** rollup — and no individual-level staff read exists anywhere, by construction rather than by permission.

**Why it is shaped this way:** `DEMOG` §4.1 (the `holder_mix` semantic, decided and defended against each alternative), §5.2–§5.3 (suppression and the differencing defence), §7.1 (no individual access, ever).

| # | Layer | What changes | Class | Owning spec § | Pkg |
|---|---|---|---|---|---|
| 1 | **Canonical data model** | A fan-side attribute on the Identity object, and a new **projection** at (session × bucket) grain. No change to Ticket, Order, Scan or any money object | `ADDITIVE SCHEMA CHANGE` | CDM §4 (identity) · `DEMOG` §1.1, §4.1 | — |
| 2 | **Physical schema** | `kernel.identity_demographic` (MUT — **no history, ever**) · `kernel.identity_demographic_erasure` (tombstone with `purge_after`) | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1 (`077` rows) · `DEMOG` §10.2 | `077` |
| 2b | | `venue.holder_mix_snapshot` · `venue.holder_mix_bucket` (k = 25, cell floor = 5) | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1, **§13.5-A** · `DEMOG` §5.2 | `086` |
| 3 | **Migration package** | Fan side `077`; rollup **`086`, not `087`** — `086` already depends on `079`/`080`/`081`, every input the rollup has, so the move **adds no DAG edge**, while `087` does not depend on `079` and would have gained one | `SPEC CORRECTION` (to `DEMOG` §10.1) | `SCHEMA` §13.5-A · `REGISTRY` §2 | `077`, `086` |
| 4 | **RLS** | Four matrices. `identity_demographic` is owner-scoped and carries the **single named GP-2 `DELETE` exception** in the entire model — "a second must not be granted by analogy"; buckets are reachable only through the RPC | `ADDITIVE SCHEMA CHANGE` (policies) | `RLS` §16.5 (note ¹ is the GP-2 exception) · `RLS` §15.7 MD-9 | `077`, `086` |
| 5 | **RPC** | **6 new**: `kernel.get_my_demographics` · `set_my_demographics` · `clear_my_demographics` — all three **carry no identity parameter of any type**, so "read someone else's row" is *inexpressible* rather than denied; `venue.refresh_holder_mix` (DEF/cron) · `venue.get_holder_mix` (**exactly two parameters** — a third is a privacy re-review, not a routine enhancement) · the nightly R4 reconciliation job | `NEW RPC` ×6 | `RPC` §17.20 · EXEC authority `RLS` §11.7 | `077`, `086` |
| 6 | **Edge Function** | **none.** Every path is a DB RPC; the feature has no edge surface | `NO SCHEMA CHANGE` | `DEMOG` §10.1 (edge row = none) | — |
| 7 | **Event envelope** | **none.** No demographic event is emitted; the rollup runs on its own cron. Named in `REGISTRY` §7 as **unaffected** by the outbox ruling | — | `REGISTRY` §7 COND-A (`unaffected` list) | — |
| 8 | **RN UI** | "About you (optional)" card + screen + one-tap remove; the banned dark patterns are enumerated and binding | `NEW RN SURFACE` | `RN` §4.9 · `DEMOG` §2.2–§2.4 | client, gated on `077` |
| 9 | **Venue dashboard** | "Ticket holder mix" aggregate card, with the suppression legend on screen | `NEW DASHBOARD SURFACE` | `VD` §9.5 · `DEMOG` §4.3 | client, gated on `086` |
| 9b | | Attendee list carries **no** demographic column, **no** answered-flag and **no** derived sort | `SPEC CORRECTION` | `DEMOG` §10.1 · `VD` §9.1 | doc |
| 10 | **Audit** | Aggregate reads by `platform_admin` are audited. There is no staff individual read to audit, because none exists | `NO SCHEMA CHANGE` | `DEMOG` §7.1, §14 D-7 | — |
| 11 | **Privacy** | The feature *is* its privacy layer: pre-computed fixed rollups at k = 25 / floor = 5 (differencing defence), `prefer_not_to_say` stored but never published, erasure tombstone, and X-1…X-9 handed to CRM as **binding** export constraints | — | `DEMOG` §5.2, §5.3, §1.3, §8.2, **§9** | `077`, `086` |
| 12 | **Tests** | `T-RPC-DEMO-01` (**exactly two writer functions exist**) · `-02` (`get_holder_mix` arity is 2) · the pgTAP list in `DEMOG` §13 · the four X-6 CI layers in `CRM` §10 | — | `RPC` §18 · `DEMOG` §13 · `CRM` §10 | — |
| 13 | **Feature flag** | **NONE NAMED.** Capture is user-opt-in; the rollup is gated only by package application. The k/floor constants are recommended as **CHECK constants, not config** — deliberately not tunable ("a tunable privacy floor is a floor that gets tuned"). **Gap against this amendment's own flag rule — §12.2, decision OD-78** | — | `DEMOG` §14 D-5 · `PLAN` §4 (three flags only) | — |
| 14 | **Rollout gate** | `077` may apply immediately (`PLAN` §3 seq 2). The rollup is inert until answers exist; the card must not render below threshold | — | `PLAN` §3 · `DEMOG` §4.3 | — |
| 15 | **Open decisions** | D-1…D-11 → §14 as **OD-15…OD-20, OD-22, OD-30…OD-32**. D-6 (backup-retention window) is **the same decision** as `CRM` D-10 and D-8 (marketing's ceiling) the same as `CRM` D-7; each is carried once | — | `DEMOG` §14 | — |

---

## 6. Feature 3 — Promoter codes

**One sentence.** Code-based attribution beside link-based attribution, with a total precedence rule evaluated **in the database and only in the database**, an append-only attribution ledger, an append-only review ledger, and a commission that becomes real at settlement close.

**Why it is shaped this way:** `PROMO` §2.1 (where precedence is evaluated), §3.2 (the economic-commitment freeze point), §4 (no double commission — as constraints, not policy).

| # | Layer | What changes | Class | Owning spec § | Pkg |
|---|---|---|---|---|---|
| 1 | **Canonical data model** | Promoter gains the commercial terms the constitution ratifies (`tier`, `party_kind`, flat-per-ticket **or** %); Attribution is an immutable ledger written **when the order is paid**, not at creation | `ADDITIVE SCHEMA CHANGE` | DA §1.7 · CDM §1.3 · `RATIFY` **D7**, **D8** | — |
| 2 | **Physical schema** | `venue.promoter_code` · `promoter_code_scope` · `attribution_review` · `normalize_promoter_code()` (IMMUTABLE); `venue.promoter` +5 columns with an XOR CHECK; `venue.attribution` +15 columns, `link_id` becomes **nullable**; `venue.order.attribution_candidate_code_id`/`_link_id` + freeze trigger; `kernel.payment_native.instrument_fingerprint`; the partial `UNIQUE ON venue.settlement_line (cause_ref) WHERE cause='promoter_commission'` | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1 (`090` rows), §3.14.1 · `PROMO` §1.1–§1.8 | `090` |
| 3 | **Migration package** | **Everything in `090`, unsplit** — `090`'s rollback is clean while empty, so splitting the feature across packages would make it un-revertible as a unit. Adds edges `078 → 090`, `085 → 090`, `087 → 090` | — | `SCHEMA` §13.5-E, §13.6 · `REGISTRY` §2, §2.1 | `090` |
| 4 | **RLS** | Matrices for the three new tables, plus a **`SPEC CORRECTION`** to `RLS` §9.17 so a **code-sourced** attribution (`link_id IS NULL`) is visible to its own promoter — the pre-correction predicate joined through `promoter_link` and hid exactly the rows this feature creates | `ADDITIVE` + `SPEC CORRECTION` | `RLS` §16.7, §9.17 · `PROMO` §8.3, §8.5 | `090` |
| 5 | **RPC** | **14 new**: `resolve_order_attribution` (DEF) · five code-management RPCs · `preview_promoter_code` (EDGE-FRONTED read) · `bind_order_attribution` · `review_attribution_flag` · `decide_flagged_attribution` · three promoter reads · `kernel.is_promoter_for_event` | `NEW RPC` | `RPC` §17.14–§17.19, §1.1c · EXEC authority `RLS` §11.5 | `090` |
| 5b | | `kernel.settlement_commission_lines` — **SEAM-2 hook**: stubbed in `087` returning zero rows, `CREATE OR REPLACE`d in `090`. `kernel.close_settlement` is authored **once, in `087`**, and is never rewritten by a later package | `NEW RPC` (hook) | `SCHEMA` §13.2 (FR-5 + seam table) · `REGISTRY` §2.2 | `087`→`090` |
| 6 | **Edge Function** | `promoter-code-preview` — needed because `public.check_rate_limit` is `service_role`-only (unreachable from `authenticated`) **and** its first parameter is a `uuid`, so an unauthenticated typist cannot be keyed at all. The wrapper derives a **rate-limiting-only** principal `uuidv5(NS, ip‖sha256(ua))`, never an identity | `NEW EDGE FUNCTION` | `EDGE` §3.8 · `PROMO` §7.10 · the recorded adaptation `RLS` §11.8 / `RPC` §17.17 | deploy, gated on `090` |
| 7 | **Event envelope** | `AttributionRecorded` sits in the constitution's Async class. Named in `REGISTRY` §7 as **unaffected** by the outbox ruling — commission accrual has its own scheduler at settlement close | — | `REGISTRY` §7 COND-A (`unaffected`) · DA §6.1 | — |
| 8 | **RN UI** | Promoter-code field at checkout with an advisory preview. **An attribution failure never fails a sale** | `NEW RN SURFACE` | `RN` §4.7 · `PROMO` §11.1, §7.11 | client, gated on `090` |
| 9 | **Venue dashboard** | Codes surface · attribution view sufficient to defend a dispute without engineering · self-deal flag queue | `NEW DASHBOARD SURFACE` | `VD` §10.5–§10.7 · `PROMO` §11.2 | client, gated on `090` |
| 9b | | Promoter *record* and *link* CRUD — **no RPC is named anywhere.** Those controls stay read-only or do not render | **UNBACKED** | `VD` §20A.3 **U-3, U-4** | — |
| 10 | **Audit** | Code create/status/scope/window changes and every attribution decision are audited; the review ledger is itself append-only (`UNIQUE(attribution_id, seq)`, effective decision = highest `seq`), so a denial is resolved rather than removed | `NO SCHEMA CHANGE` | `PROMO` §1.6, §7.7 · `VD` §22.4 | `090` |
| 11 | **Privacy** | `instrument_fingerprint` is a self-deal signal, not a payment credential, and never touches `public.payments`; a promoter reads **only their own** attributions; anti-enumeration is quantified (entropy floor + failure thresholds) | — | `PROMO` §1.8, §8.5, §9.3, §9.4 | `090` |
| 12 | **Tests** | `T-RPC-PROMO-01..11` · `T-RPC-ATTR-01..04` · `T-RLS-ATTR-01` (no attribution row while the order is `pending`) · `T-RLS-ATTR-02` (code-sourced attribution visible to its promoter) · the pgTAP list in `PROMO` §12 | — | `RPC` §18 · `RLS` §16.11 · `PROMO` §12 | — |
| 13 | **Feature flag** | **NONE NAMED.** `PLAN` §4 defines exactly three boolean flags and none guards the promoter engine; the enumeration thresholds are config *values*, not a kill switch. **Gap against this amendment's flag rule — §12.2, decision OD-78** | — | `PLAN` §4 · `PROMO` §9.4, §13-10 | — |
| 14 | **Rollout gate** | `090` applies last, gated on the **promoter phase** (`PLAN` §3 seq 15). Commission cannot be real before `087` exists, because a commission line **is** a settlement line | — | `PLAN` §3 · `PROMO` §6.3 | — |
| 15 | **Open decisions** | The ten in `PROMO` §13 → §14 as **OD-33…OD-42**; the §14.x contradictions are recorded in §15, not resolved | — | `PROMO` §13, §14 | — |

---

## 7. Feature 4 — Venue CRM / attendee export

**One sentence.** A **holder-keyed** roster (not purchaser-keyed), a three-layer contact-consent model, and an asynchronous export job that produces a signed, expiring artifact — with the demographics spec's X-1…X-9 as a hard wall the export builder may not cross.

**Why it is shaped this way:** `CRM` §1.2 (the roster-grain decision), §4 (cross-organization isolation and its four proofs), §5.3 (the three opt-out layers), §10 (the four-layer X-6 enforcement).

| # | Layer | What changes | Class | Owning spec § | Pkg |
|---|---|---|---|---|---|
| 1 | **Canonical data model** | A per-org pseudonym (`customer_ref`) and a consent relationship between Identity and Organization. **No new roster object** — the roster is a *read* over existing objects | `ADDITIVE SCHEMA CHANGE` | `CRM` §1.4 (join path), §4.3 | — |
| 2 | **Physical schema** | `kernel.identity_contact_pref` (MUT) · `kernel.org_customer_key` | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1 (`077` rows) · `CRM` §11.2 | `077` |
| 2b | | `kernel.org_contact_consent` — carries `source_order_id → venue.order`, which is why it lands in `082` and not earlier | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1, §13.5-E · `CRM` §11.1-5 | `082` |
| 2c | | `venue.export_job` · the private `crm-exports` bucket (zero client policies) · the `crm_export_builder` definer role | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1 (`087` rows) · `CRM` §11.2, §10.1 | `087` |
| 2d | | Config seeds — limits, caps, retention, `crm_export.constraint_set_version` | `ADDITIVE SCHEMA CHANGE` (rows) | `CRM` §11.1-20, §7.1 · **moved** by `SCHEMA` §13.5-D | `078` |
| 3 | **Migration package** | `077` · `082` · `087` (+ seeds in `078`, + the `audience_v2` template bump at `090`). The seed move is the only disagreement with `CRM`'s own map | `SPEC CORRECTION` (seeds only) | `REGISTRY` §2 · `SCHEMA` §13.5-D, §13.5-E | `077`,`082`,`087` |
| 4 | **RLS** | Matrices for the four new tables; the `_sel_svc_export` policies that make the `crm_export_builder` owner work; **`T-RLS-CRM-01`: no platform role can call `venue.request_export`** | `ADDITIVE SCHEMA CHANGE` (policies) | `RLS` §16.6, §16.10 · EXEC authority `RLS` §11.6 | `077`,`082`,`087` |
| 5 | **RPC** | **14 new**: `get_my_contact_prefs` · `set_my_contact_prefs` (`077`); `grant_`/`withdraw_org_contact_consent` · `list_my_org_contact_consents` (`082`); `request_export` · `build_export_rows` · `finalize_export` · `authorize_export_download` · `revoke_export` · `list_export_jobs` · `sweep_expired_exports` · `list_attendees` · `lookup_attendee` (`087`). **No `p_identity_id` parameter exists on any consent RPC** — a venue can never record consent on a fan's behalf | `NEW RPC` ×14 | `RPC` §17.21, §17.22 · EXEC authority `RLS` §11.7, §11.6 | `077`,`082`,`087` |
| 5b | | `build_export_rows` / `list_attendees` read `venue.attribution → promoter_link → promoter` (`090`). **Not a forward-reference defect**: the promoter columns are *absent from the file, not blank*, until `090`, and the template version carries it (`audience_v1` → `audience_v2`) | `NO SCHEMA CHANGE` | `SCHEMA` §13.2 **FR-8** · `CRM` §6.4 | `090` |
| 6 | **Edge Function** | `crm-export` — build + signed `/download` route | `NEW EDGE FUNCTION` | `EDGE` §3.7 · `CRM` §11.5 | deploy, gated on `087` |
| 7 | **Event envelope** | **none.** The export pipeline runs on `pg_cron` + `pg_net` with a claim-lease and is named in `REGISTRY` §7 as **unaffected** by the outbox ruling | — | `REGISTRY` §7 COND-A (`unaffected`) · `CRM` §6.1 | — |
| 8 | **RN UI** | Checkout contact opt-in (unchecked by default) · Settings → "Venues you've allowed to email you" + master switch · the pre-deletion "which venues exported a list with you" screen | `NEW RN SURFACE` ×3 | `RN` §4.8 · `CRM` §5.3, §9.2, §11.1-25/26/27 | client, gated on `082`/`087` |
| 9 | **Venue dashboard** | Attendees tab → **holder-grain** list + suppression legend · export request/history/revoke panel · CRM controls in Settings | `NEW DASHBOARD SURFACE` | `VD` §9.1, §9.6, §16.6 · `CRM` §11.1-29/30 | client, gated on `087` |
| 9b | | `VD` §9.1's attendee list was **purchaser-keyed**; it is holder-keyed | `SPEC CORRECTION` (**K-1**) | `CRM` §11.7 K-1 · `VD` §9.1 | doc |
| 10 | **Audit** | Export audit lives on the **platform** plane, not with the venue; every row stamps `constraint_set_version`, so an auditor can prove which X-1…X-9 text was in force. `venue.request_export` writes it in the same transaction as the job row | `NO SCHEMA CHANGE` | `CRM` §8.1–§8.4, §2.4 X-9 | `087` |
| 11 | **Privacy** | Cross-org isolation XO-1/XO-2 with four proofs; per-org pseudonym so two orgs cannot join rosters; opt-out survives transfer; the **email-lookup oracle** is named as the real hole and rate-limited fail-closed; **read ≠ export** — `platform_support` may look, never extract | — | `CRM` §4, §4.3, §5.4, §7.2, §3.2 (**K-3**) | `087` |
| 12 | **Tests** | `T-RPC-CRM-01..07` · `T-RLS-CRM-01` (no platform role may `request_export`) · `T-RLS-CRM-02` (venue-grain vs org-grain marketing) · the pgTAP list in `CRM` §12 · the four X-6 layers in `CRM` §10, including the **non-vacuity guard** (a grep over a not-yet-existing file set passes vacuously — this repo shipped that exact failure once) | — | `RPC` §18 · `RLS` §16.11 · `CRM` §10, §12 | — |
| 13 | **Feature flag** | **NONE NAMED as a boolean kill switch.** `087` seeds limits/caps/retention, all read live so a change takes effect without a deploy — but there is no `crm.export.enabled`. **Gap against this amendment's flag rule — §12.2, decision OD-78** | — | `CRM` §7.1 · `PLAN` §4 | — |
| 14 | **Rollout gate** | `077`/`082` early; `087` after settlement (`PLAN` §3 seq 12). The **Layer-0 privilege wall (D-2) must be decided before `087`**, because it changes who owns the builder function | — | `PLAN` §3 · `CRM` §13 D-2 | — |
| 15 | **Open decisions** | D-1…D-11 → §14 as **OD-09, OD-16, OD-19…OD-22, OD-43…OD-47**. D-7 (marketing's CRM ceiling) is **one decision asked by three specs** and D-10 (backup window) is **the demographics D-6**; both are carried once | — | `CRM` §13 | — |

---

## 8. Feature 5 — Notifications

**One sentence.** A versioned type registry, a sparse-override preference model with a structurally undisableable mandatory class, and a five-hop delivery pipeline that **extends** the production notifier — and which **has no migration package**, because its schema's gate is an unresolved contradiction between the constitution and every implementation spec.

**Why it is shaped this way:** `NOTIF` §1.1 (two parallel notification systems that share nothing, today), §3.3 (the mandatory class made structurally impossible to disable), §4.1–§4.3 (the five hops and the C12 envelope).

> **Read §13 before this table.** Rows 3, 5, 6, 7 and 14 are all conditional on the same unresolved ruling. Nothing here is a recommendation on that ruling.

| # | Layer | What changes | Class | Owning spec § | Pkg |
|---|---|---|---|---|---|
| 1 | **Canonical data model** | CDM §1.6 already gives Notification a canonical object and a `NotificationID`; C7 already names `notify` as one of the seven contexts. **The model is not the problem — the schedule is** | `NO SCHEMA CHANGE` | CDM §1.6, §15 C7 · `RATIFY` **C52** | — |
| 2 | **Physical schema** | New schema `notify`, **9 tables**: `notification_type` (C18 registry) · `notification` · `delivery` · `preference` · `identity_channel_state` · `outbox` · `schedule` · `announcement` · `template` | `ADDITIVE SCHEMA CHANGE` | `NOTIF` §6.1 · `SCHEMA` §13.4 | **unscheduled** |
| 2b | | Additive columns on existing tables: `public.push_tokens` +4 (`revoked_at` becomes the authoritative predicate; `is_active` untouched, no backfill) | `ADDITIVE SCHEMA CHANGE` | `NOTIF` §6.1 · defect D-3 `NOTIF` §1.6 | with the schema |
| 2c | | `catalog.event_session.session_version` (**Δ-N1**) — a **correctness** requirement: without it a second door-time change collides with the first notification's dedupe key and is silently swallowed | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1 · `NOTIF` §2.2 Group E | **`078`** |
| 2d | | `kernel.identity_ext.locale` (**Δ-N2**) | `ADDITIVE SCHEMA CHANGE` | `SCHEMA` §13.1 · `NOTIF` §5.4 | **`077`** |
| 3 | **Migration package** | **NONE.** If `notify` is ruled Gate P it is package **`092`** — not `091` (a droppable writer-less stub, registry rule §6.7) and not earlier, because `notify.drain_outbox` reads `venue.promoter_link` (`090`) and SEAM-1 floors it there. **Count becomes 17 and the registry's own "no gaps, no duplicates" assertion is falsified** | **BLOCKED — §13** | `REGISTRY` §7 **COND-B** · `SCHEMA` §13.4 · `PLAN` §8 COND-B | `092`? |
| 4 | **RLS** | Nine matrices, written **conditionally**: `notification`/`preference` owner-scoped, `announcement` venue-scoped read, the rest deny-all. Carries the **single named exception** to the "no INSERT/UPDATE/DELETE policy" rule in the whole model — `notify_notification_upd_owner` | `ADDITIVE` (conditional) | `RLS` §16.9, §16.10 · assertion **`T-RLS-POL-05`** (**renumbered from `T-RLS-POL-03` 2026-08-28, `R3-1`** — that id named two different assertions in RLS §16.11 and the venue-plane `AUTHZ-PKG1` control keeps it) | with `092` |
| 5 | **RPC** | **23 new `notify.*`**: 9 fan-facing (`get_inbox`, `get_unread_count`, `mark_read`, `mark_all_read`, `dismiss`, `get_preference_matrix`, `set_preference`, `register_push_token`, `revoke_push_token`) · 5 announcement (`draft`, `approve`, `cancel`, `revoke`, `preview_announcement_audience` — **count only, never an enumeration**) · `report_announcement` · 8 `DEF` pipeline functions (`emit_event`, `enqueue`, `channel_enabled`, `drain_outbox`, `sweep_scheduled`, `claim_deliveries`, `record_delivery_result`, `resolve_web_link`) | `NEW RPC` ×23 | `RPC` §17.24, §17.25 · EXEC authority `RLS` §11.7 | with `092` |
| 5b | | `claim_deliveries` and `record_delivery_result` are **wholly authored** by the RPC integrator — the source spec names them and supplies no contract body. Marked `INFERENCE`, to be reviewed as design, not absorbed as citation | `NEW RPC` (authored) | `RPC` §17.25, §19-1 | — |
| 6 | **Edge Function** | `notify-dispatch` (the delivery pipeline) · `notify-receipts` (provider receipt poll + dead-token revocation) | `NEW EDGE FUNCTION` ×2 | `EDGE` §3.14, §3.15 · `NOTIF` §4.6 | deploy |
| 7 | **Event envelope** | **This feature *is* the envelope pipeline.** `notify.outbox` carries the C12 envelope (per-aggregate monotonic `sequence` allocated under the aggregate's existing row lock, `causation_id`, `correlation_id`, at-least-once + idempotent consumers). Payload rule: **ids and scalars only — never a recipient list, never rendered copy** | `ADDITIVE SCHEMA CHANGE` | `NOTIF` §4.3 · CDM §15 C12 · `SCHEMA` §13.3 | COND-A/B |
| 8 | **RN UI** | Notification centre · preference screen · deep-link handling · the eight binding requirements · door-drain notifications | `NEW RN SURFACE` | `RN` §6.1–§6.4 · `NOTIF` §6.5, §3.7 | client |
| 9 | **Venue dashboard** | Notification preferences (§16.5, **binding delegation** to `NOTIF`) · "Send an update" announcement composer (§16.5a) | `NEW DASHBOARD SURFACE` ×2 | `VD` §16.5, §16.5a · `NOTIF` §7 | client |
| 9b | | **The load-bearing consequence:** `VD` §16.5 is a *binding* dependency on `notify`, **and no Gate-L object may have one**. This is the strongest argument on the record for the Gate-P reading, and it is recorded, not acted on | — | `RLS` §15.7 **MD-10** · `NOTIF` §10 O-N1 | — |
| 10 | **Audit** | Announcements carry a hold window, a dual-control threshold above a blast radius, and a revocation record; **drafting and releasing are distinct acts (SoD) — never a marketing label for release** | `NO SCHEMA CHANGE` | `NOTIF` §7.3, §7.5 · `RLS` §11.7 | with `092` |
| 11 | **Privacy** | The account-existence oracle is named and closed; lock-screen exposure to a third-party reader is bounded; a payload may never carry PII or rendered money amounts; staff notifications never leak attendee identity | — | `NOTIF` §8.3, §8.4, §8.5, §8.6 | — |
| 12 | **Tests** | `T-RPC-NOTIFY-01..04` (**conditional on MD-10**) — recipient derivation; a mandatory type cannot be suppressed, asserted as `service_role` **and** as `postgres`; a claimed delivery inside its lease is not re-claimable; `emit_event`/`enqueue` never raise, so an injected constraint violation leaves the caller's transaction committed. Plus the pgTAP groups A–I in `NOTIF` §9 | — | `RPC` §18 · `NOTIF` §9 | — |
| 13 | **Feature flag** | `notify.announcements_enabled` + four announcement tuning keys, seeded by `078`. **The pipeline itself has no kill switch** because it has no package | `ADDITIVE SCHEMA CHANGE` (seeds) | `NOTIF` §6.1, §7 · `SCHEMA` §13.1 | `078` |
| 14 | **Rollout gate** | **Cannot be scheduled at all until §13 is ruled.** Δ-N1/Δ-N2 are already scheduled independently (`078`/`077`) and are safe to ship regardless of the ruling | **BLOCKED — §13** | `REGISTRY` §7 COND-A/COND-B | — |
| 15 | **Open decisions** | O-N1…O-N15 → §14 as **OD-13, OD-14, OD-48…OD-56**, plus O-N7 (numbering) into **OD-79**. O-N1 and O-N2 are the two coupled scope questions and are stated in §13 rather than buried in the index | — | `NOTIF` §10 | — |

---

## 9. Feature 6 — Venue dashboard

**One sentence.** The operator web surface — twelve areas, a role × surface matrix **derived** from `RLS` §9.x rather than extending it, and the standing rule that **a control with no named backend capability is read-only or does not render.**

**Why it is shaped this way:** `VD` §4.4 (cross-organization access impossible by construction), §20A (the acceptance rule that every control names a backend capability), §5.1 (the four new labels are an amendment, not an extension).

| # | Layer | What changes | Class | Owning spec § | Pkg |
|---|---|---|---|---|---|
| 1 | **Canonical data model** | **none.** The dashboard introduces no canonical object. It consumes them | `NO SCHEMA CHANGE` | `VD` §20 (read index) | — |
| 2 | **Physical schema** | **none of its own.** Its outstanding asks are Δ5–Δ10 (columns on existing tables) and Δ11–Δ12 (reads); **no new table is proposed by this spec** | — (all **OPEN**) | `VD` §21 | — |
| 3 | **Migration package** | **none.** The dashboard is a client of `077`–`090`. Its Δ asks, if granted, would attach to the package owning each table (`078` for the `catalog.event` marketing columns, already landed via `ROLE` S-5) | — | `REGISTRY` §2 · `SCHEMA` §13.1 (`078` row) | — |
| 4 | **RLS** | The §5 role × surface matrix is **derived from** `RLS` §9.x and the role model, and extends neither. Six venue labels + six org labels + three platform labels = the fifteen of C36 | `NO SCHEMA CHANGE` | `VD` §5, §5.1, §5.2 · `RLS` §2.1 · `RATIFY` **O-2** | — |
| 5 | **RPC** | Consumes the whole surface. Its own asks: **Δ2 `venue.list_activity` SATISFIED** as `venue.read_operational_audit`; **Δ3 satisfied ×3** (`list_attendees` holder-keyed per K-1, `list_org_payouts` naming `org_owner` per O-3, and `get_dashboard_summary` **still only an ask**); **Δ4 satisfied** as `review_attribution_flag` | `NEW RPC` (via siblings) | `VD` §21.0 · `RPC` §17.26, §17.22, §17.5, §17.18 | `087`, `085`, `090` |
| 5b | | **Ten controls map to nothing: U-1…U-10.** Guest-list CRUD (3 writes, 0 signatures) · **mark a guest arrived** (the most-used control at a door, no contract) · promoter record/link CRUD · door-open blast-radius dry run · live-device count · one-round-trip home summary · batch capacity change · draft-event edit · `kernel.update_organization`. **The pattern is create-but-never-update / authorize-but-never-name** | **UNBACKED** | `VD` §20A.3 | — |
| 6 | **Edge Function** | Consumes `door-session`/`door-manifest`, `crm-export`, `promoter-code-preview`, `payout-execute`, `refund-execute`. Adds none | `NO SCHEMA CHANGE` | `EDGE` §3.7–§3.9, §3.4, §3.5 | — |
| 7 | **Event envelope** | Emits none. **Requests none** — the four emitters its notification rules imply (low-inventory threshold crossed, daily digest window closed, payout failed, door anomaly) belong to `NOTIF`, and if that spec did not request them they are deltas on it, not on the dashboard | — | `VD` §21 (closing note) · DA §6.1 | — |
| 8 | **RN UI** | **none.** The surface split is settled: consumer RN, operator web, scanner as its own mode | `NO CHANGE` | `VD` §3.1 (adopted from `RN` §2) | — |
| 9 | **Venue dashboard** | Twelve areas A–L. **Four new surfaces arrive from sibling specs**: refund approval queue (money §10.1) · re-authenticate for a money action (money §8.3) · announcement composer (`NOTIF` §7) · holder-mix card (`DEMOG`) and CRM export panel (`CRM`) | `NEW DASHBOARD SURFACE` | `VD` §13.7, §16.9, §16.5a, §9.5, §9.6 | client |
| 9b | | Door surface §12.4: the manifest and the transfer freeze — **the freeze is monotone and terminal; closing an episode does not clear it**, and the door principal may not open it (O-4) | `SPEC CORRECTION` (applied) | `VD` §12.4, §22.7 · `RATIFY` **O-4** | — |
| 10 | **Audit** | Reads `kernel.admin_audit` **only** through `venue.read_operational_audit`, which excludes the security plane, returns plain verbs with no before/after payloads, and scopes the finance subset | `NEW RPC` (satisfied) | `VD` §17, §21 Δ2 · `RPC` §17.26 · `RLS` §11.7 | `087` |
| 11 | **Privacy** | Cross-organization access impossible **by construction**, not by policy; column-scoping by role on every roster read; `platform_support` reads and does not extract | — | `VD` §4.4, §9.3 · `CRM` §3.2 | — |
| 12 | **Tests** | `T-RLS-ROLE-01..04` (the fifteen labels; no bare role-string or display name in any policy or RPC body) · `T-RLS-DOOR-10` (denied principals cannot open the manifest and `door_open_at` is unchanged) · `T-RLS-MONEY-01..04` · `T-RLS-CRM-02` | — | `RLS` §16.11 | — |
| 13 | **Feature flag** | **none of its own.** Each surface renders on the flag of the capability it consumes; a surface whose capability is OFF must state that honestly rather than render a dead control | — | `PLAN` §4 · `VD` §20A (the standing rule) | — |
| 14 | **Rollout gate** | Area-by-area, following its packages: A/B/C after `081`; D after `087`; E after `090`; G after `086`; H/I after `085`/`087`; §16.5 **blocked on §13** | — | `PLAN` §3 · `VD` §20 | — |
| 15 | **Open decisions** | Δ6–Δ12 and U-1…U-10 → §14 as **OD-62…OD-77** (Δ5 is satisfied; U-3+U-4 and U-5+U-6 each merge to one); §22.13 → **OD-05**; §22.5/§22.8/§22.10/§22.12 → OD-76, OD-77, OD-75; §22.11/§22.15/§22.16 → OD-59, OD-79, OD-14 | — | `VD` §21, §20A.3, §22 | — |

---

## 10. The cross-feature dependency graph

The six features are **not** independent. Six real couplings exist; each is a place where shipping one feature without the other produces a wrong answer rather than a missing one.

```
                     door manifest (086)  ─────────────┐
                              ▲                        │ D1: offline safety
        D6: FK signing_key    │                        ▼
   credential infra (083) ────┘              APPLE WALLET (083)
        ▲                                              │
        │ credential_version comparison ───────────────┘
   ticket atom (079)

   DEMOGRAPHICS (077 + 086) ──D2: X-1…X-9 (binding)──▶ CRM EXPORT (087)
        ▲                                                   │
        └────────── D3: denominator ≡ holder count ──────────┘

   PROMOTER CODES (090) ──D4: commission line──▶ SETTLEMENT (087)
                              (SEAM-2 hook, stub in 087, replaced in 090)

   NOTIFICATIONS (unscheduled) ──D5: binding dependency──▶ VENUE DASHBOARD §16.5
                              (no Gate-L object may carry one)
```

| # | Coupling | What it actually is | Cited at | If ignored |
|---|---|---|---|---|
| **D1** | **Wallet ⟵ door manifest + `credential_version`** | Wallet's entire offline guarantee is *"the door compares the pass's `credential_version` against the manifest's"*. The manifest tables (M2) and offline-verify **step 3b** are the mechanism; defect **W-3** is the finding that they do not exist yet | `WALLET` §0.2, §4.2–§4.4, §2.4 · `DOOR` §9.1, §9.2 · `EDGE` §5.4 | A stale pass admits at an offline door. **Hard gate HG-1** |
| **D2** | **CRM export ⟵ demographics X-1…X-9** | The demographics spec hands the export agent **nine binding constraints**, the sharpest being X-6: the export builder's SQL contains **zero** references to any demographic object. `CRM` §10 implements it in four layers and makes it stricter, adding the **non-vacuity guard** (a grep over a file set that does not yet exist passes vacuously — this repo shipped that exact failure once, at `073`) | `DEMOG` §9 · `CRM` §2.4, §10 | A demographic column reaches a venue CSV. The wall is the whole privacy argument |
| **D3** | **Demographics card ⟶ CRM roster denominator** | The mix card renders *"Based on N of M ticket holders"*. **M ≡ `holder_mix.holders_total` ≡ `COUNT(holder view rows)`** for the same `(session, as_of)` — same table, same filter, same instant. This equality only holds because K-1 made the roster **holder-keyed** rather than purchaser-keyed | `CRM` §1.3 (proof + assertion 3 of §12) · `DEMOG` §4.3 | The card sits above a list whose length disagrees with the card's own denominator, and an operator correctly concludes one is broken. **Hard gate HG-5** |
| **D4** | **Promoter attribution ⟶ settlement** | A commission **is** a settlement line. `kernel.close_settlement` is authored once in `087`; `090` replaces only the `settlement_commission_lines` hook. The cross-settlement `UNIQUE (cause_ref) WHERE cause='promoter_commission'` is what makes a second commission structurally impossible | `PROMO` §4.2, §6.3 · `SCHEMA` §13.2 FR-5, §3.14.1 · `REGISTRY` §2.2 | Either a forward reference that will not apply, or two packages rewriting one another's function body |
| **D5** | **Venue dashboard ⟶ notifications** | `VD` §16.5 is a **binding delegation** to `NOTIF`, and no Gate-L object may carry a binding dependency. This is the load-bearing argument in the `notify` ruling — recorded, not acted on | `VD` §16.5 · `RLS` §15.7 MD-10 · `NOTIF` §10 O-N1 | A shipped dashboard surface with no backend. See §13 |
| **D6** | **Door manifest ⟵ credential infrastructure** | `venue.door_manifest_entry.signing_key_id` is an FK to `kernel.signing_key`. This is the DAG edge `083 → 086` added by the integration — a **package-order** dependency, not a product one | `SCHEMA` §13.6 · `REGISTRY` §2.1 | `086` will not apply |

**Two couplings that look real and are not, stated so nobody re-derives them.** Demographics does **not** read `venue.scan`, because `admitted_mix` is not built (`DEMOG` §4.1) — so the rollup has no dependency on the door. And the CRM roster's `checked_in` column is **never crossed with any demographic axis**; there is no such axis to cross it with (`CRM` §1.3).

---

## 11. Hard gates — what must not ship before what

A hard gate is stronger than a dependency: it is an ordering whose violation deploys a known defect, not merely an incomplete feature. **None of these is a judgement call at implementation time.**

| ID | Gate | Why it is hard, not soft | Authority |
|---|---|---|---|
| **HG-1** | **Apple Wallet must not ship before the door-manifest tables and the offline `credential_version` check exist and have been drilled.** | Wallet's whole guarantee rests on offline-verify **step 3b** and the **M2** manifest tables, neither of which exists (defect **W-3**, VERIFIED). Shipping first deploys W-3 **at scale onto devices we do not control** — a stale pass on an airplane-mode phone admits at an offline door, and the platform cannot recall it | `WALLET` §15 **OQ-W3** (*"Hard gate"*, owner acknowledgement required) · `WALLET` §0.2 · `DOOR` §9.2 · `EDGE` §5.4 |
| **HG-2** | **No Wallet push path, no door-manifest open transaction as specified, no scanner push-to-sync and no notification may ship before the outbox ruling (§13) is made.** | Pass supersession runs in the outbox consumer **specifically** so Wallet can never block or roll back a custody transfer; the two alternatives — moving it inside the custody transaction, or leaving a superseded pass live — are **both prohibited by ratified invariants**. The door-manifest open transaction is all-or-nothing and its last step writes the envelopes | `REGISTRY` §7 COND-A (*"What breaks under COND-A = NO"*) · `SCHEMA` §13.3 · `RATIFY` **C51** |
| **HG-3** | **`083` before `086`; `087` before `090`; `079` before `083` and `085`.** | Each is an FK or a function-body dependency added by the integration, not a preference. `086` will not apply without `kernel.signing_key`; a promoter commission cannot exist before the settlement line it is | `SCHEMA` §13.6 · `REGISTRY` §2.1 |
| **HG-4** | **The Layer-0 privilege-wall decision (CRM D-2) must be made before `087` is authored.** | It changes **who owns** `venue.build_export_rows`. Deciding after authoring means rewriting the function's ownership and its policy set, in the package that also creates the bucket | `CRM` §13 D-2 (*"Yes — before 087 / I"*) · `RLS` §15.7 **MD-2** |
| **HG-5** | **The holder-mix card must not render before the roster read is holder-keyed.** | The card's denominator is pinned by proof to `COUNT(holder view rows)`. The card lands at `086` and `venue.list_attendees` at `087`; rendering in between shows a denominator with nothing to agree with | `CRM` §1.3 · `DEMOG` §4.3 · `VD` §9.1 (K-1) |
| **HG-6** | **Nothing may be added to `084` or `091`.** | `084` creates zero relations and zero routines and `091` is always empty; those properties are exactly what make their rollbacks unconditionally reversible. Adding an object silently converts a reversible rollback into one valid only in the empty window — which is why the Wallet registry was moved out of `084` | `REGISTRY` §6.7 · `SCHEMA` §13.5-C |
| **HG-7** | **The step-up predicate must be checked against a real access token before the money surfaces are built.** | The money spec flags `UNVERIFIED:` that this project's tokens carry `amr` with per-factor timestamps. If the claim is absent the step-up either never fires or always fires — **both failure modes are silent** | `VD` §22.14 · `MONEY` §11 (verification owed) · `RLS` §15.7 **MD-7** |
| **HG-8** | **`kernel.identity_demographic`'s two global-posture exceptions must be acknowledged before `077`.** | The definer-scoped `DELETE` (the single GP-2 exception in the model) and the `ON DELETE CASCADE` from `auth.users` against the `RESTRICT` default. Both are in the package; neither is reversible once data exists | `DEMOG` §14 **D-9, D-11** (*"Yes — before 077"*) · `CRM` §13 D-3 · `RLS` §15.7 **MD-9** |

**One gate deliberately *not* asserted.** Nothing here gates a feature on a *product* decision (naming, thresholds, commercial terms). Those block value, not correctness, and they live in §14.

---

## 12. Feature flags and rollout gates

### 12.1 The discipline (inherited, restated once because every row below depends on it)

- Flags are **VALUES in `catalog.platform_config`**, seeded by **`078`**, read live by the engine RPCs.
- **Every flag ships `false`.** The table is applied; the **behaviour** is gated. Deferring the *migration* instead would fork the chain and break Gate-2 reproducibility.
- **Seeding is a migration. Flipping is never a migration** — it is an audited `catalog.set_platform_config` call, dual-controlled on money keys.
- Config is world-readable; these are operational thresholds, **not secrets**.

`PLAN` §4 · `SCHEMA` §13.5-D · `RLS` §8.4 · `WALLET` §11.5.

### 12.2 Per-feature flag status — and the three that have none

| Feature | Flag key(s) | Default | Guards | Flip mechanism | Status |
|---|---|---|---|---|---|
| **Apple Wallet** | `wallet.apple.enabled` (+5 tuning keys) | **`false`** | `kernel.mint_wallet_pass` and the whole issue path; **not role-bypassable** — `platform_admin` also gets `wallet_disabled` | audited `catalog.set_platform_config` | **COMPLIANT** (`WALLET` §11.5) |
| **Notifications** | `notify.announcements_enabled` (+4 announcement keys) | **`false`** | the announcement surface only | same | **PARTIAL** — the delivery pipeline itself has no flag because it has no package (`NOTIF` §6.1) |
| **Demographics** | — | — | — | — | **NO FLAG.** Capture is user-opt-in; the k/floor constants are recommended as **CHECK constants precisely so they cannot be tuned** (`DEMOG` §14 D-5) |
| **Promoter codes** | — (enumeration thresholds are values, not a switch) | — | — | — | **NO FLAG** (`PROMO` §9.4, §13-10) |
| **CRM export** | — (limits/caps/retention are values, not a switch) | — | — | — | **NO FLAG** (`CRM` §7.1, §11.1-20) |
| **Venue dashboard** | none of its own | — | each surface renders on the flag of the capability it consumes | — | **BY DESIGN** (`VD` §20A) |
| *(chain-wide, pre-existing)* | `feature.native_issuance_enabled` · `feature.native_scanning_enabled` · `feature.native_resale_enabled` | **`false`** ×3 | issuance, scanning, native resale | same | `PLAN` §4 |

> **Recorded, not decided — OD-78.** The amendment brief asks for a flag **per feature**, defaulting off, flipped by audited runtime config. **Three of the six have none.** `PLAN` §4 defines exactly three boolean flags and none of them guards demographics, promoter codes or CRM export; those three are gated only by *package application*, which is a deploy, not a runtime control — and which cannot be reversed without a rollback. Adding three keys is small and additive (they are rows in a table `078` already creates), but **naming a new flag is a scope decision and this document does not make one.** See §14 OD-78.

### 12.3 Rollout gate per feature

| Feature | Package applies | Gate that must clear before the behaviour is enabled |
|---|---|---|
| **Apple Wallet** | `083` at `PLAN` §3 seq 8, flag OFF | **HG-1** (door manifest + step 3b, drilled) · `WALLET` §13 operational checklist green · OQ-W6 security sign-off on `verify_jwt=false` |
| **Demographics** | `077` seq 2 (fan side); `086` seq 11 (rollup) | **HG-8** acknowledgements before `077` · the card must not render below threshold, and not before **HG-5** |
| **Promoter codes** | `090` seq 15 | the **promoter phase** gate; `087` must exist (**HG-3**); the commission basis and code-vs-link precedence are commercial decisions that should be settled **before** codes are live, because attributions freeze |
| **CRM export** | `077` seq 2 · `082` seq 7 · `087` seq 12 | **HG-4** (Layer-0 decision before `087`) · the X-6 four-layer check green, including the non-vacuity guard |
| **Notifications** | **cannot be scheduled — §13** | the coupled ruling. Δ-N1/Δ-N2 ride `078`/`077` and are safe either way |
| **Venue dashboard** | n/a (client) | area-by-area, on the packages it reads; §16.5 blocked on §13; every U-1…U-10 control stays read-only or unrendered until an owner closes it |

---

## 13. The two coupled unresolved scope questions

> **This document does not decide either one, and does not lean.** Both are recorded in the ratification record as `OPEN-GATED`, each with a ratified constitutional statement on one side and four implementation specs on the other. They are stated here together because **they are coupled**, and because five of the six features' schedules depend on the answer.

### 13.1 Question A — the event outbox (`RATIFY` **C51** / decision **O7**; `REGISTRY` **COND-A**)

**The contradiction.** DA §6.3 states the anti-over-engineering guarantee as *"the only new infrastructure Phase 2 introduces is one outbox table and a drainer on the cron that already runs"*, and DA §6.1/§6.2 route **every** notification, analytics rollup, social update, promoter-commission accrual and transfer-expiry through it. CDM §15 **C12**'s envelope guarantees, and C28/C48/C49, all presuppose it.

**And nothing schedules it.** The word "outbox" appears **exactly once** across the implementation specs before this pass — inside the **Gate-L** deferral list. No package allocates it. So the one piece of infrastructure the constitution promises Phase 2 *will* build is the one piece nothing schedules.

**Consequence, priced.**

| Ruling | What follows |
|---|---|
| **(a) the constitution is right** | An outbox package is Gate-P/MVP work missing from the plan. Placement is **`076`** — the table has zero FK dependencies, so no producer package gains an edge; drainer on the existing 2-minute `pg_cron` heartbeat |
| **(b) the implementation specs are right** | DA §6.2/§6.3 must stop claiming an outbox exists in Phase 2; C12's envelope guarantees have **no carrier** at MVP; and every design that emits an envelope — door manifest, promoter attribution, notifications, Wallet supersession — needs a **stated alternative transport** |

**What breaks under (b), precisely** (`REGISTRY` §7): the entire Apple Wallet push path — supersession runs in the outbox consumer *specifically* so Wallet can never block or roll back a custody transfer, and **both alternatives are prohibited by ratified invariants**; the door-manifest open transaction as specified (all-or-nothing, last step writes the envelopes); scanner push-to-sync; every notification. **Unaffected:** CRM export, demographics, promoter codes, money authority — each carries its own scheduler.

### 13.2 Question B — the `notify` schema (`RATIFY` **C52** / decision **O8**; `REGISTRY` **COND-B**)

**The contradiction.** Ratified row **C7 is `RATIFIED · Gate P · MVP`** and names `notify` as one of the seven contexts; CDM §1.6 gives Notification a canonical object and identity. **All four** implementation specs place `notify` at **Gate L / DO-NOT-BUILD**.

**The load-bearing argument on the record** (not this document's): the venue dashboard already carries a **binding** dependency on `notify` (`VD` §16.5), and **no Gate-L object may carry one** (`RLS` MD-10).

**Consequence, priced.** If ruled Gate P, `notify` is package **`092`** — not folded into `091` (a droppable, writer-less stub protected by registry rule §6.7) and not earlier, because `notify.drain_outbox` reads `venue.promoter_link` (`090`) and SEAM-1 floors it there. **The count becomes 17, the range `076`–`092`, and `REGISTRY` §2's own "no gaps, no duplicates" assertion is falsified** — which requires re-ratification of the registry, not an edit to it.

### 13.3 Why they are coupled, and the one incoherent combination

The schema integrator established the coupling and it is binding on how the ruling may be phrased:

| Outbox | `notify` | Coherent? |
|:-:|:-:|---|
| IN | OUT | **Yes.** Wallet push and the door-manifest events get their carrier; notifications do not |
| IN | IN | **Yes.** The full design as written; outbox lives as `notify.outbox` |
| OUT | OUT | **Yes, but expensive.** Every envelope emitter needs a named alternative transport, and DA §6.2/§6.3 must be corrected |
| OUT | IN | **No.** `NOTIF` §4 *is* the outbox pipeline. Ruling `notify` in while ruling the outbox out ratifies a schema whose central table is the thing that was just refused |

**Therefore: rule on them together, in that order — outbox first.** The schema home follows from the pair: `notify.outbox` under Gate-P `notify`, `kernel.event_outbox` otherwise (`SCHEMA` §13.3).

**Neither is decided here.** They appear in §14 as **OD-13** (outbox) and **OD-14** (`notify`), each marked as blocking, and they are the only two entries in this document that block more than one feature.

---

## 14. Consolidated owner-decision index

### 14.1 What was collapsed, and on what rule

**133 raised items across 17 sources** — the three ratified open rows, the eight delta specs, the four integration passes, and this document — collapse to **81 distinct decisions**, of which **54 block a package or a named implementation item.**

The merge rule: two items are **one decision** when a single answer settles both, even where the words differ. Two items stay **separate** when the same owner could coherently answer one yes and the other no. Where a merged pair carried two recommendations, both are shown.

| Merged into | From | Because |
|---|---|---|
| **OD-01** | MONEY D-1 · RLS MD-1 · RLS X-8 | One question — is `approval_request` an aggregate class? — asked as a design question, as an RLS note, and as a C28-amendment request |
| **OD-03** | MONEY D-3 · RLS MD-3 · RLS §15 item 4 | The `platform_support` ceiling is one of the six numbers, not a seventh decision |
| **OD-13** | RATIFY C51/O7 · REGISTRY COND-A · NOTIF O-N2 · RLS MD-11 · SCHEMA §13.3 | Five statements of the same missing outbox |
| **OD-14** | RATIFY C52/O8 · REGISTRY COND-B · RLS MD-10 · NOTIF O-N1 · VD §22.16 | Five statements of the same `notify` gate |
| **OD-16** | DEMOG D-6 · CRM D-10 | **The backup-retention window is one number**; `CRM` D-10 says so itself and is listed only because its own copy also cannot ship with a placeholder |
| **OD-19** | DEMOG D-9 · DEMOG D-11 · CRM D-3 · RLS MD-9 | One acknowledgement of the named global-posture exceptions and the one constraint on whoever next edits migration `020` |
| **OD-20** | CRM D-7 · DEMOG D-8 · ROLE §5 H2/H3 | **Marketing's CRM ceiling, asked by three specs. It must be answered once**, for the export template and the mix card together |
| **OD-21** | RLS MD-8 · CRM D-8 · VD §22.6 | One question — is a platform bulk-extraction path wanted at all? |
| **OD-22** | DEMOG D-4 · CRM D-9 | "Is a demographic-based send wanted" and "confirm X-8 stays closed" are the same question from the two ends |
| **OD-25** | WALLET OQ-W4 · DOOR OQ-5 | Already *ruled* between the two specs; what remains is one owner sign-off on the relaxation |
| **OD-59** | DOOR OQ-4 · VD §22.11 · RLS X-7 | One question — is the MVP freeze predicate session-wide, and do the four stale documents get corrected or does the board want the C43 narrowing in MVP (a **new** ratification, not a clarification)? |
| **OD-64** | VD U-3 · U-4 | `VD` §20A.3 itself calls both "the same unnamed promoter CRUD" |
| **OD-65** | VD U-5/Δ11 · U-6/Δ12 | Two reads on one confirm dialog, same surface, same role set, one grant |
| **OD-79** | REGISTRY header · ROLE OD-10 · PROMO §14.1 · NOTIF O-N7 · VD §22.15 | Five reports of one numbering problem, now answered by the registry — which is itself **pending re-ratification** |

**Closed, and listed so nobody re-opens them:** `ROLE` OD-2 (`venue_scanner` rename) and OD-3 (`set_org_payout_destination`) — closed by **O-2**/**O-3**; `ROLE` OD-6 (`text` + CHECK) — closed by `SCHEMA` §12.3; `DOOR` OQ-3 (`box_office` label) — superseded by **O-2**; `VD` Δ1–Δ4 — satisfied (`VD` §21.0); `VD` Δ5 — satisfied by `ROLE` S-5's marketing columns in `078`; `VD` §22.1/§22.2/§22.3/§22.4/§22.6/§22.7/§22.9 — closed by O-1…O-4 and CRM K-3/K-5.

### 14.2 The index

`Blocks` = **the named item cannot be implemented until this is answered.** "no" means the decision affects value or consistency, not correctness.

#### A. Money, authority and dual control

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-01** | Is `kernel.approval_request` an aggregate class (⇒ a 16th SSCAS member ⇒ a C28 amendment) or an intent record? | MONEY §11 D-1 · RLS §15.7 MD-1 · RLS §17 X-8 | **the parked refund branch** | **Intent record** — it is lock-ordered either way, so an amendment is a one-line ratification |
| **OD-02** | Per-org refund/payout thresholds at launch — build `kernel.org_money_policy`? | MONEY §11 D-2 · REGISTRY §7 COND-C · SCHEMA §1.14 | **`077` scope** | **No** — `platform_config` is world-readable so per-org limits need a non-public home, and nothing in O-1/O-3 asks for one |
| **OD-03** | The six threshold **values**, including `refund.platform_support_max_minor` | MONEY D-3 · RLS MD-3 · RLS §15 item 4 | **tier behaviour** | Commercial + risk call; the keys ship, values set by an audited `set_platform_config` |
| **OD-04** | `org_admin` reads `venue.settlement` while denied the payout and refund ledgers — keep or deny? | MONEY D-4 · RLS MD-4 | no (consistency) | **Keep** — settlement is reconciliation, payout is money-out; the inconsistency is named rather than smoothed |
| **OD-05** | `org_admin` on the money plane: `VD` §5.2 row 35 shows `●` on the refunds order list; the corrected money matrix denies the refund read. **Both cannot hold** | VD §22.13 | **the Refunds surface** | none — O-1/O-3 are silent on `org_admin` and the denial is an inference |
| **OD-06** | A single-money-principal org is blocked from payouts after a destination change by SoD-1 — escalate or relax? | MONEY D-5 · RLS MD-5 | **`release_payout` path** | **Escalate** — relaxing reintroduces the exact named fraud primitive |
| **OD-07** | `refund.scanned_atom_policy` default: `refuse` or `platform_review`? | MONEY D-6 · RLS MD-6 | **the consumed-atom refund path** | **`platform_review`** — legitimate, but also the insider-collusion shape, so it should be *seen* |
| **OD-08** | Ship step-up at `aal1` freshness now and flip to `aal2` on staff MFA enrolment? | MONEY D-7 · RLS MD-7 | **`RLS` §11.3 step-up** | **`aal1` with the level in config**, so `aal2` is a config change not a code change. Paired with **HG-7** |
| **OD-09** | Who may **disable** a transfer freeze? O-4 says not the scanner; it does not say who | RLS MD-12 · ROLE OD-7 | **the override RPC** | `platform_admin` under step-up, placed there provisionally |
| **OD-10** | Door break-glass: if `door_open_at` is mis-set and no manager is reachable, the door cannot open under O-4 | RLS MD-13 · ROLE OD-8 · DOOR §8.2 | no (ops risk) | Ship without it — but the risk is real and should be seen here, not at 11 p.m. |
| **OD-11** | Settlement close — `org_finance`, `venue_finance`, or both? | ROLE OD-4 · RLS §15 item 3 · MONEY open reconciliation | **`close_settlement` authority** | none — O-1/O-3 do not reach it |
| **OD-12** | The platform sub-role read boundary | RLS §15 item 1 | **the platform matrices** | none |

#### B. The two coupled scope questions (§13)

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-13** | **Is the event outbox in Phase 2?** The constitution promises exactly one outbox table and a drainer; no implementation spec schedules one | RATIFY **C51/O7** · REGISTRY COND-A · NOTIF O-N2 · RLS MD-11 · SCHEMA §13.3 | **the Wallet push path · the door-manifest open transaction as specified · scanner push-to-sync · every notification** | `NOTIF` §10 recommends **build it** — one table plus one RPC on a cron that already runs. **`REGISTRY` and `SCHEMA` decline to recommend.** Not decided here |
| **OD-14** | **What gate is the `notify` schema at?** C7 is `RATIFIED · Gate P · MVP` and names it; all four implementation specs place it at Gate L | RATIFY **C52/O8** · REGISTRY COND-B · RLS MD-10 · NOTIF O-N1 · VD §22.16 | **everything in `RLS` §16.9 · `VD` §16.5 · package count and range** | `NOTIF` §10 recommends Gate P on the dashboard-dependency argument. `RLS` MD-10 explicitly declines: *"a stop-and-ask."* Not decided here. **Must be ruled together with OD-13, outbox first** |

#### C. Privacy and data protection

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-15** | Which privacy regimes apply (GDPR/UK GDPR, CPRA, other US state regimes)? | DEMOG §14 D-1 | no | Counsel. The design survives the strictest answer with no redesign |
| **OD-16** | **The backup-retention window `{N}` days** — needed for the erasure promise sentence and the tombstone's `purge_after` | DEMOG D-6 · CRM D-10 | **the user-facing copy** (cannot ship with a placeholder) | Owner / ops |
| **OD-17** | Confirm k = 25 and cell floor = 5, and whether they are CHECK constants or config | DEMOG D-5 | **the CHECK constant** | **CHECK constant** — *"a tunable privacy floor is a floor that gets tuned"*; may be raised, never lowered |
| **OD-18** | Is gender identity special-category / sensitive personal information? | DEMOG D-2 | no | Counsel. A "yes" requires no change — the capture is already explicit-consent shaped |
| **OD-19** | Acknowledge the two named global-posture exceptions **and** the constraint on migration `020` (contact and demographic rows must never be repointed to the anonymized sentinel) | DEMOG D-9 · D-11 · CRM D-3 · RLS MD-9 | **`077`** (**HG-8**) | Accept as the single GP-2 exception in the model; a second must not be granted by analogy |
| **OD-20** | **Confirm marketing's CRM / analytics ceiling — once, for all three specs** | CRM D-7 · DEMOG D-8 · ROLE §5 H2/H3 | **the export template and the mix-card grant** | Audience template only, at each label's plane grain; no money columns; no email-lookup probe; the demographic mix is **outside** the export authorization |
| **OD-21** | Is a platform-plane bulk extraction path wanted at all? | RLS MD-8 · CRM D-8 · VD §22.6 | **platform export** | **Not built in Phase 2.** If wanted it needs dual control, its own retention and its own audit action — not the venue surface |
| **OD-22** | Confirm X-8 stays closed — no demographic-based send, and no send of any kind from that surface | DEMOG D-4 · CRM D-9 | no | Stays closed; recorded so the absence is a decision, not a gap |

#### D. Apple Wallet

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-23** | Holder name on the pass? | WALLET §15 OQ-W1 | **the pass template** | **No name** — lock-screen physical safety for a nightlife product; ID matching goes behind the scanner's authenticated lookup |
| **OD-24** | Who owns the Apple Developer account, and who can renew the Pass Type ID certificate? | WALLET OQ-W2 | **`pass-cert-provision` operations** | Name a primary **and a backup** with portal access and KMS import authority; calendar the renewal independently of alerting |
| **OD-25** | Ratify the session-bounded wallet token profile (the one place a recorded constraint is relaxed) | WALLET OQ-W4 · DOOR OQ-5 (ruled between the specs; sign-off owed) | **the `credential.wallet_*` seeds** | Grant, with the cross-config invariant `wallet_default_span + wallet_exp_skew <= door.manifest_ttl_interval` and the three mandatory mitigations |
| **OD-26** | Offer a Wallet pass while `resale_state ∈ {listed, locked}`? | WALLET OQ-W5 · EDGE §12.2 (same question for `credential-sign`) | **the RN control** | **Hide/refuse while listed or locked** — answer both together |
| **OD-27** | `wallet-pass-webservice` runs `verify_jwt=false`, the second such function after `stripe-webhook` — security sign-off | WALLET OQ-W6 | **deploy** | Accept with the §6.1 compensating controls, subject to explicit sign-off |
| **OD-28** | DL-1 post-open issuance — build the manifest supplement, or accept "door sales after manifest open are online-only"? | WALLET OQ-W7 · DOOR §7.7 | **door sales after manifest open** | **Build the supplement** — small, provably safe; the alternative silently refuses paying fans |
| **OD-29** | Budget (KMS · APNs · storage) · rotating barcodes later? · Google Wallet? | WALLET OQ-W8, OQ-W9, OQ-W10 | no | Deferred; Google Wallet revisited after Apple ships and is measured |

#### E. Demographics — residue

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-30** | Add `age_band` in a later wave? | DEMOG D-3 | no | Value set pre-specified; needs a new `notice_version` and a separate opt-in. **Not Phase 2** |
| **OD-31** | Does `platform_admin` get aggregate access at all? | DEMOG D-7 | no | Default yes, any session, audited; zero platform access is also coherent and slightly stronger |
| **OD-32** | Owner for the compelled-disclosure runbook | DEMOG D-10 | no | Out-of-band, dual-controlled, audited; never a product feature |

#### F. Promoter codes

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-33** | **Code beats link** when they name different promoters? | PROMO §13-1 | **the precedence table** | **Code wins**, link recorded in `displaced_promoter_id`. Reversing later is a **breaking change** to frozen attributions |
| **OD-34** | Does the original promoter earn on a marketplace resale? | PROMO §13-2 | **§5.6** | **No.** Additive later as a `market_sale`-grain attribution with its own cause |
| **OD-35** | Who bears a post-settlement chargeback on a commissioned sale? | PROMO §13-3 | **the promoter program's gate** | **The org**, via a negative settlement line. "Promoter bears it" needs C29+C30 and is therefore a decision to **gate the program on Gate M** |
| **OD-36** | Commission basis: face subtotal or gross including fees? | PROMO §13-4 | **terms** | **Face subtotal.** Deciding after codes are live means renegotiating every promoter's terms |
| **OD-37** | Do codes need redemption caps / expiry by default? | PROMO §13-5 | **§1.1** | No cap, opt-in expiry. Enforcing "Jordy has 60" via the code puts a hot counter in the checkout path |
| **OD-38** | What is the remedy for a genuinely wrong attribution? | PROMO §13-6 | **must be settled before anyone builds an override** | **None on-ledger** — the freeze is absolute; remedy is a commercial settlement off-ledger. An override that mutates an AO ledger destroys every §4 guarantee |
| **OD-39** | Promoter portal: web, or in the RN app? | PROMO §13-7 | no | Web, mobile-first responsive |
| **OD-40** | Sub-promoters / sub-codes with a split commission? | PROMO §13-8 | no | Not in Phase 2 — two payees per attribution breaks the one-payee shape |
| **OD-41** | May a promoter *request* a vanity code? | PROMO §13-9 | no | Out of scope; an inbox flow, not a grant. Flagged so nobody implements it as an RLS permission |
| **OD-42** | Enumeration thresholds (30 failures / 5 min) | PROMO §13-10 | no | Starting value, tunable via config; needs a real traffic baseline |

#### G. CRM export — residue

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-43** | Does a native-rail resale purchase create a contact relationship with the event's org? | CRM §13 D-1 | no | **No by default**; offer the same unchecked opt-in at resale checkout |
| **OD-44** | Acknowledge that consent **withdrawal is a state change, not a hard delete** — divergence from the demographics spec | CRM D-4 | no | Adopt — a consent record is evidence about a relationship, and it is the person's own evidence in the dispute they are most likely to have |
| **OD-45** | Confirm the email-lookup limit — 40/day per actor for `email_exact` | CRM D-5 | no | The *shape* must not change; the **number** should be the owner's, because it is the sharpest anti-harvest control |
| **OD-46** | Export artifact retention: **24 hours or 7 days**? | CRM D-6 | **the sweep constant** | **24 h** — 7 days multiplies the standing exposure sevenfold for operator convenience |
| **OD-47** | Does an operator ever need a printed door list? | CRM D-11 | no | Today "no" — box office looks people up one at a time. A yes needs its own template, retention, and an honest note that print has none of §6's controls |

#### H. Notifications

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-48** | **Does transactional email exist in Phase 2?** Requires a provider account and SPF/DKIM/DMARC on the domain | NOTIF §10 O-N3 | **19 of the 24 mandatory types name `E`** | Decide before build. The design degrades safely, but a mandatory money notice with **push as its only channel** is one revoked permission from unreachable |
| **OD-49** | Which of the 24 mandatory types are *legally* compulsory, and where? | NOTIF O-N4 | **whether the class is policy or compliance** | Counsel. The design is built so the answer changes one registry column |
| **OD-50** | Announcement hold-window length, dual-control threshold, and whether a step-up primitive exists to gate release | NOTIF O-N5 | **§7** | 300 s hold, 500-recipient threshold; step-up depends on OD-08 |
| **OD-51** | May the marketing concept **release** announcements, or only draft? | NOTIF O-N6 | **composer authority** | **Draft only** — a product-authority call, needing owner ratification |
| **OD-52** | Do venue-staff notifications share the consumer inbox table or get a separate surface? | NOTIF O-N8 | **the schema shape** | One table with `org_id`/`venue_id`; two would double every RLS and dedupe assertion |
| **OD-53** | Retention for `notification` / `delivery` / `outbox`, and the C48 retention floor | NOTIF O-N9 | **retention + the C48 floor** | 24 months / 90 days / 30 days, **both projections marked NON-REBUILDABLE** |
| **OD-54** | Migrate the 12 legacy inbox types into the registry, or leave them alongside? | NOTIF O-N10 | no | Leave them; register as `legacy=true`; do not touch working producers |
| **OD-55** | `notify.push_token` as a new table, or additive columns on `public.push_tokens`? | NOTIF O-N11 | **the token model** | **Extend `public.push_tokens`** — a second table creates split-brain during migration. Flagged because C7 literally says *"into their own schema"* |
| **OD-56** | Quiet hours · `security_email_changed` mirror sweep · promoter digest · **Universal Links / App Links** | NOTIF O-N12, O-N13, O-N14, O-N15 | **O-N15 blocks any deep-link target more sensitive than navigation** | First three: not in MVP. AASA/`assetlinks.json` required before a sensitive target |

#### I. Door lifecycle

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-57** | Does opening the manifest early bother anyone commercially? (the early freeze) | DOOR §16 OQ-1 | **the operating recommendation** | Keep manifest-open and freeze **coupled**; accept the early freeze. Decoupling reintroduces the snapshot-then-freeze window |
| **OD-58** | Draining active listings at door-open — a product act, not just a technical one | DOOR OQ-2 | **§7.3 sign-off** | Drain, with the notification. The alternative is worse but *visible* to the seller |
| **OD-59** | **Confirm the MVP freeze predicate is session-wide** — and correct the four documents that describe a C43 narrowing nothing implements. If the board wants the narrowing in MVP it is a **new ratification, not a clarification** | DOOR OQ-4 · VD §22.11 · RLS X-7 | **four documents' correctness** | Keep the session-wide predicate; the narrowing is a pure additive conjunct once `door_manifest_entry` is populated |
| **OD-60** | Is `record_scan` required to take the session `FOR SHARE`? · Manifest signing | DOOR OQ-6, OQ-7 | **the door transaction shape** | — |
| **OD-61** | Should the C25 compensate branch void the seller's atom at all? | DOOR OQ-8 | **C25 semantics** | Surfaced, not resolved |

#### J. Venue dashboard — unbacked controls and column asks

`U-*` = a control with **no named backend capability**. Until each is closed, `VD`'s standing rule holds: **the control is read-only or it does not render.**

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-62** | Name the guest-list write RPCs — create list · add guest · remove entry. Three writes, **zero signatures** | VD §20A.3 **U-1** | **surface F** | — |
| **OD-63** | Name the **mark-a-guest-arrived** RPC. RLS grants the door principal exactly this narrow update; **no contract exists** | VD **U-2** | **the door** — *"the single most-used control at a door"* | — |
| **OD-64** | Name the promoter record + link RPCs, and a live slug-availability read (the UI must check a global namespace against nothing) | VD **U-3, U-4** | **surface E** | — |
| **OD-65** | Grant the two door pre-confirm reads: blast-radius dry run, and live-device count | VD **U-5/Δ11, U-6/Δ12** | **the door-open confirm** | Small, read-only, same role set as the open RPC. Without them the most consequential door control asks for a confirmation the operator cannot evaluate |
| **OD-66** | `venue.get_dashboard_summary` — the home tiles in one round trip | VD **U-7** / Δ3c | no | Home works at N queries |
| **OD-67** | Name a capacity-change RPC for an existing batch | VD **U-8** | **§8.4** | The guarded behaviour and refusal floor are already specified in detail |
| **OD-68** | Name an update RPC for `catalog.event` / `event_session` — creation is contracted, editing is not | VD **U-9** | **§7.3** | — |
| **OD-69** | Name `kernel.update_organization` — `catalog.update_venue` exists; the org has no counterpart | VD **U-10** | **§16.1** | — |
| **OD-70** | Δ6 — `catalog.event.announce_at` / `on_sale_at` for a scheduled on-sale | VD §21 Δ6 | no (degrades §7.4) | Two nullable timestamps plus a sweep. **Explicitly not a virtual queue or bot defence (C44)** |
| **OD-71** | Δ7 — `venue.ticket_type` sale windows and per-order min/max | VD Δ7 | no (degrades §8.6) | "Tables sell 1 per order" is currently unexpressible |
| **OD-72** | Δ8 — `venue.staff_role.event_id` / `expires_at` (event-scoped, auto-expiring grants) | VD Δ8 | no (degrades §15.3) | **Urgency raised by O-2**: a one-night `venue_box_office` lead now gets a permanent venue-wide grant |
| **OD-73** | Δ9 — `venue.guest_list.promoter_id` | VD Δ9 | no | Low priority; today it is string matching |
| **OD-74** | Δ10 — org/venue `brand_logo_ref` | VD Δ10 | no | Only if venue branding is a product commitment; otherwise drop the delta |
| **OD-75** | Re-map legacy `venue_manager` grants when the six-label enum lands — anyone granted it *for box-office work* retains manifest open/close | VD §22.12 | **grant hygiene at cutover** | Under-provisioning is safe here; over-provisioning is not |
| **OD-76** | Inventory warning thresholds — no config key is named and no per-venue override exists | VD §22.8 · NOTIF low-inventory rule | **§6.1 and the low-inventory notification** | Left unresolved rather than invented |
| **OD-77** | Label reconciliation: `duplicate` / `already_scanned` / "Already used"; and the undefined `ˢᵒᵈ` legend symbol | VD §22.5, §22.10 | no | Not behavioural — a naming reconciliation for the RPC author, and a one-line confirmation from the money-spec owner |

#### K. Governance and process

| ID | Question (one line) | Raised by | Blocks | Recommendation on record |
|---|---|---|:-:|---|
| **OD-78** | **Three of the six features have no boolean kill switch** — demographics, promoter codes and CRM export are gated only by package application, which is a deploy and not a runtime control | **this document, §12.2** | **the amendment's own flag rule** | none — naming a new flag is a scope decision. The keys would be rows in a table `078` already creates |
| **OD-79** | **Re-ratify the amended package registry.** Its header reads `AMENDMENT PENDING RE-RATIFICATION`: `kernel.approval_request` placed in `077`, two packages renamed, seven dependency edges added | REGISTRY header · ROLE OD-10 · PROMO §14.1 · NOTIF O-N7 · VD §22.15 | **authoring any package** — rule §6.5 says the registry is updated only by ratified amendment | Ratify as amended; the count changes to 17 only if OD-14 is Gate P |
| **OD-80** | **O6** — cross-region native resale: saga/escrow over the `paid_pending_transfer` window, or explicit intra-region-only scoping | RATIFY C50/**O6** | no for MVP (blocks Gate M / multi-region) | Miami single-region builds neither; carried so it is not lost |
| **OD-81** | Retain `venue_finance` though O-2 does not list it; and do **not** rename `org_member` → `org_affiliate` | ROLE OD-1, OD-9 | no | Retain (`RLS` §9.13/§11 both depend on it, and deleting it would silently close `RLS` §15 item 3); do not rename |

### 14.3 Counts

| | Count |
|---|---|
| Items raised across all sources | **133** |
| Distinct decisions after deduplication | **81** |
| **Of which block a package or a named implementation item** | **54** |
| Block **more than one feature** | **2** (OD-13, OD-14) |
| Needing **counsel**, not the owner alone | 4 — OD-15, OD-18, OD-49, and OD-16 jointly with ops |
| Needing an **architecture** sign-off | 4 — OD-01, OD-19, OD-52, OD-55 |
| Needing a **security** sign-off | 1 — OD-27 (`verify_jwt=false`) |
| Decisions carrying a recommendation on record | **71 of 81.** The ten with none: OD-05, OD-11, OD-12, OD-13, OD-14, OD-60, OD-62, OD-63, OD-64, OD-69 |

**The four to answer first**, because each unblocks the most downstream work per answer: **OD-13** and **OD-14** (five features' schedules), **OD-19** (blocks `077`, the second package in the chain), **OD-79** (blocks authoring any package at all).

---

## 15. Contradictions between specs — recorded, not resolved

**This document resolves none of these.** Each is a place where two documents in the corpus say different things about the same object. The `Owns the reconciliation` column names who must fix it; where that is an owner decision it points at §14.

| # | The contradiction | Side A | Side B | Owns the reconciliation |
|---|---|---|---|---|
| **X-01** | **Wallet registry package.** The Wallet spec assigns `kernel.wallet_pass`, `wallet_pass_device`, `wallet_pass_push_log`, the `.pkpass` bucket and ten of its RPCs to **`084`**, and still does so in its own §11.1/§11.2/§11.4/§6.1 headers and its §11.10 change-class index | `WALLET` §11.10 (`084`) | `SCHEMA` §13.5-C + `REGISTRY` §2 (`083`) | `SCHEMA` §13 is the binding placement record. **The Wallet spec's own numbers are stale and should cite the registry.** Owner: `WALLET` |
| **X-02** | **Holder-mix package.** | `DEMOG` §10.1 (`087`) | `SCHEMA` §13.5-A + `REGISTRY` §2 (`086`) | Same. Owner: `DEMOG` |
| **X-03** | **CRM config-seed package.** | `CRM` §11.1-20 (`087`) | `SCHEMA` §13.5-D + `REGISTRY` §2 (`078`) | Same. Owner: `CRM` |
| **X-04** | **Settlement package.** The promoter spec maps `venue.settlement`/`settlement_line` to `086`; the demographics and CRM specs map it to `087` | `PROMO` §0.3 (`086`) | `REGISTRY` §2 + `DEMOG`/`CRM` (`087`) | The registry wins; `PROMO` is stale. Already reported as `VD` §22.15. Owner: `PROMO` · closes with **OD-79** |
| **X-05** | **`refund_hold` has no offline reject mapping.** `MONEY` §12-2 adds `refund_hold` to the atom's overlay set. `DOOR` §9.2's offline reject map enumerates only `{listed, locked}`, and `venue.door_manifest_entry.resale_state` CHECKs the overlay set. **A `refund_hold` atom would snapshot into the manifest with no reject mapping and no defined offline behaviour** | `MONEY` §12-2 | `DOOR` §9.2, §10.3 | `SCHEMA` §13.1 reports it to the RLS/RPC integrator — *"the reject vocabulary is theirs."* `086`'s CHECK must admit all four labels. **Still open** |
| **X-06** | **A freeze narrowing four documents describe and nothing implements.** `SCHEMA` §643, `RPC` §748, `RLS` §1150 and `PLAN` §414 all say the freeze is *"narrowed per-open-manifest-ticket per C43"*. It is not — the predicate is session-wide, and C43 is `RATIFIED-MODELED-ONLY(GATE-M)` | four implementation specs | `DOOR` §16 OQ-4 · `VD` §22.11 · `RLS` §17 X-7 | **OD-59.** If the board wants the narrowing in MVP it is a **new ratification, not a clarification** |
| **X-07** | **`org_admin` on the money plane.** `VD` §5.2 row 35 shows `org_admin` at `●` on the refunds order list; the corrected money matrix denies `org_admin` the refund read | `VD` §5.2 row 35 | `MONEY` §2/§3 corrected matrix | **OD-05.** O-1/O-3 are silent on `org_admin`; the denial is an inference and the two cannot both hold |
| **X-08** | **The `notify` gate.** C7 is `RATIFIED · Gate P · MVP` and names `notify` | CDM/DA (**C7**) | `SPEC_FOUNDATION`, `RLS`, `SCHEMA`, `PLAN` (Gate L / do-not-build) | **OD-14** (§13). Ratified as `OPEN-GATED(O8)` |
| **X-09** | **The event outbox.** DA §6.3 promises one outbox table and a drainer as *the only* new infrastructure Phase 2 introduces | DA §6.2/§6.3 · CDM C12 | every implementation spec (no package, one Gate-L mention) | **OD-13** (§13). Ratified as `OPEN-GATED(O7)` |
| **X-10** | **`has_venue_role`'s door-PIN branch.** `RPC` §1.1 gives the predicate a caller-dependent door-PIN branch; `ROLE` §7.5 deletes it and moves door authority to `kernel.assert_door_session` | `RPC` §1.1 | `ROLE` §7.5 · `SCHEMA` §13.2 FR-1 | `SCHEMA` §13.2 states plainly: **"RPC §1.1 is now stale."** Owner: `RPC`. Asserted by `T-RPC-ROLE-01` / `T-RLS-ROLE-04` |
| **X-11** | **Attribution write point.** `RPC` §6.1 writes `venue.attribution` inside `create_order`; the constitutions say it is written when the order is **paid**, and ratified row **D7** rules the constitutions right | `RPC` §6.1 | DA §1.7 · CDM §1.3 · `RATIFY` **D7** | `RLS` §9.17 is already corrected to `finalize_primary_order`. **The `RPC` §6.1 correction is still owed** — named by `RATIFY` D7 and `PROMO` §14.4 |
| **X-12** | **The registry's own count assertion.** `REGISTRY` §2 asserts *"16 packages, no gaps, no duplicates"*; §7 COND-B states that a Gate-P `notify` makes it 17 and **falsifies that assertion** | `REGISTRY` §2 | `REGISTRY` §7 COND-B | Self-flagged by design — *"which is precisely why the ruling belongs to the owner."* Closes with **OD-14** + **OD-79** |
| **X-13** | **A mis-citation that sends the reader to the wrong decision.** `CRM` §13 D-7 says *"role-model **OD-8** asked the owner to confirm the scope"* of marketing. `ROLE` §13 **OD-8 is door break-glass**; the marketing ceiling in the role model is §5 rows **H2/H3** | `CRM` §13 D-7 | `ROLE` §13 OD-8 vs `ROLE` §5 H2/H3 | Citation defect. Owner: `CRM`. Does not change **OD-20**'s substance |
| **X-14** | **Two spec inventories are missing eight tables.** Both `DEMOG` §10.1 and `CRM` §11.1 record a `SPEC CORRECTION` adding four tables each to `SPEC_FOUNDATION` §6's canonical inventory and four deny-all rows each to `RLS` §6. **Neither correction is applied** | `SPEC_FOUNDATION` §6 · `RLS` §6 | `DEMOG` §10.1 · `CRM` §11.1-34/35 | Owner: `SPEC_FOUNDATION` and `RLS` |
| **X-15** | **A trap rather than a contradiction, recorded because it will bite.** `PLAN` §5 is the **pre-delta** package record and is deliberately not updated in place; `PLAN` §8 is canonical. A reader quoting §5's object list gets a package that is missing up to a dozen objects | `PLAN` §5 | `PLAN` §8 | Stated by `PLAN` §5's own preamble. No fix owed — but no reader may quote §5 |

**Two things this list is not.** It is not a defect backlog for this document to work — every row belongs to another owner. And it is not evidence that the corpus is inconsistent in a way that blocks work: **eleven of the fifteen are already named by the document that would have to change**, which is the property that makes them cheap to close.

---

## 16. Requests to other integrators (recorded, not applied here)

This document edits no file but its own. Each item is a change another owner must make.

| # | To | Request |
|---|---|---|
| **R-1** | **traceability integrator** (concurrent) | Every `OD-*` id in §14 needs a matrix row, keyed to the source ids in the `Raised by` column so a reader arriving from any of the eight delta specs lands on the same row. This is the same ask `RLS` §17 X-9 makes for `T-RLS-*` and the §16.10 policy names |
| **R-2** | **amendment / registry owner** | **OD-79**: the registry is `PENDING_RE_RATIFICATION`. Record in the same amendment that **the six features add no package** — five are placed inside `076`–`091` and the sixth is unscheduled pending OD-14 |
| **R-3** | **RLS + RPC integrator** | **X-05**: `DOOR` §9.2's offline reject map needs a `refund_hold` arm and `086`'s `door_manifest_entry.resale_state` CHECK must admit all four labels. `SCHEMA` §13.1 already routed this to you; it is still open |
| **R-4** | **RPC integrator** | **X-10**: `RPC` §1.1's door-PIN branch is stale (`SCHEMA` §13.2 FR-1 says so). **X-11**: `RPC` §6.1's attribution write point is owed a correction under ratified **D7** |
| **R-5** | **`WALLET` · `DEMOG` · `CRM` · `PROMO` owners** | **X-01…X-04**: each spec still cites its own package number. Replace every number with a citation to `PHASE_2_PACKAGE_REGISTRY.md` §2 — *"several delta specs re-derive a numbering shift rather than citing the registry, which is exactly how four competing scales were produced last time"* (`VD` §22.15) |
| **R-6** | **`SPEC_FOUNDATION` + `RLS` owners** | **X-14**: eight tables are missing from `SPEC_FOUNDATION` §6's canonical inventory and eight deny-all rows from `RLS` §6 |
| **R-7** | **edge integrator** | **OD-26**: `EDGE` §12.2 (credential-sign on a listed atom) and `WALLET` OQ-W5 (Wallet pass on a listed atom) are **one question**. Answer them together or they will diverge |
| **R-8** | **dashboard / RN integrator** | **OD-62…OD-69**: U-1…U-10 remain unbacked. Until each is closed the standing rule holds — **the control is read-only or it does not render.** Do not soften it to "hidden behind a flag" |
| **R-9** | **`CRM` owner** | **X-13**: the D-7 citation points at `ROLE` OD-8 (door break-glass) rather than `ROLE` §5 H2/H3 |

---

*End of `docs/architecture/PHASE_2_SCOPE_AMENDMENT_2026_08.md`. Integration layer — design-only; no SQL, no migrations, no code, no production access. This document creates no new specification: every row cites the spec that owns it, and where a row and its cited spec disagree, **the cited spec wins and the row is a defect.** It decides nothing reserved to the owner: §14's 81 entries are an index, and §15's fifteen contradictions are recorded for the owners named in each row, not resolved here.*
