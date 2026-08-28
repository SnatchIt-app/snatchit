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
