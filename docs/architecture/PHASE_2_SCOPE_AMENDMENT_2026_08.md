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
| 15 | **Open decisions** | OQ-W1…OQ-W10 → deduplicated into §14 as **OD-20…OD-26**. OQ-W3 (sequencing) is promoted to a **hard gate**, not a decision | — | `WALLET` §15 | — |

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
| 13 | **Feature flag** | **NONE NAMED.** Capture is user-opt-in; the rollup is gated only by package application. The k/floor constants are recommended as **CHECK constants, not config** — deliberately not tunable ("a tunable privacy floor is a floor that gets tuned"). **Gap against this amendment's own flag rule — §12.2, decision OD-27** | — | `DEMOG` §14 D-5 · `PLAN` §4 (three flags only) | — |
| 14 | **Rollout gate** | `077` may apply immediately (`PLAN` §3 seq 2). The rollup is inert until answers exist; the card must not render below threshold | — | `PLAN` §3 · `DEMOG` §4.3 | — |
| 15 | **Open decisions** | D-1…D-11 → §14 as **OD-05, OD-15…OD-19, OD-28**. D-6 (backup-retention window) is **the same decision** as `CRM` D-10 and is carried once | — | `DEMOG` §14 | — |

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
| 13 | **Feature flag** | **NONE NAMED.** `PLAN` §4 defines exactly three boolean flags and none guards the promoter engine; the enumeration thresholds are config *values*, not a kill switch. **Gap against this amendment's flag rule — §12.2, decision OD-27** | — | `PLAN` §4 · `PROMO` §9.4, §13-10 | — |
| 14 | **Rollout gate** | `090` applies last, gated on the **promoter phase** (`PLAN` §3 seq 15). Commission cannot be real before `087` exists, because a commission line **is** a settlement line | — | `PLAN` §3 · `PROMO` §6.3 | — |
| 15 | **Open decisions** | The ten in `PROMO` §13 → §14 as **OD-29…OD-38**; the §14.x contradictions are recorded in §15, not resolved | — | `PROMO` §13, §14 | — |

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
| 13 | **Feature flag** | **NONE NAMED as a boolean kill switch.** `087` seeds limits/caps/retention, all read live so a change takes effect without a deploy — but there is no `crm.export.enabled`. **Gap against this amendment's flag rule — §12.2, decision OD-27** | — | `CRM` §7.1 · `PLAN` §4 | — |
| 14 | **Rollout gate** | `077`/`082` early; `087` after settlement (`PLAN` §3 seq 12). The **Layer-0 privilege wall (D-2) must be decided before `087`**, because it changes who owns the builder function | — | `PLAN` §3 · `CRM` §13 D-2 | — |
| 15 | **Open decisions** | D-1…D-11 → §14 as **OD-06, OD-09, OD-16, OD-19, OD-39…OD-43**. D-7 (marketing's CRM ceiling) is **one decision asked by three specs** and D-10 (backup window) is **the demographics D-6**; both are carried once | — | `CRM` §13 | — |

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
| 4 | **RLS** | Nine matrices, written **conditionally**: `notification`/`preference` owner-scoped, `announcement` venue-scoped read, the rest deny-all. Carries the **single named exception** to the "no INSERT/UPDATE/DELETE policy" rule in the whole model — `notify_notification_upd_owner` | `ADDITIVE` (conditional) | `RLS` §16.9, §16.10 · assertion `T-RLS-POL-03` | with `092` |
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
| 15 | **Open decisions** | O-N1…O-N15 → §14 as **OD-13, OD-14, OD-44…OD-52**. O-N1 and O-N2 are the two coupled scope questions and are stated in §13 rather than buried in the index | — | `NOTIF` §10 | — |

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
| 15 | **Open decisions** | Δ5–Δ12 and U-1…U-10 → §14 as **OD-53…OD-70**; §22.5, §22.8, §22.10–§22.16 → §14 and §15 | — | `VD` §21, §20A.3, §22 | — |
