# `ODR-4` SPLIT — consequence map for the owner rulings of 2026-08-28

**Status: CONSEQUENCE MAP ONLY. This document changes nothing.** No architecture contract, no
migration, no test, no CI file, no production object is edited, created, moved or contacted by it.
It is the enumeration a later remediation pass executes from, and the enumeration an owner reads to
know what the rulings actually cost.

**Produced:** 2026-08-28 · branch `docs/odr4-consequence-map`, cut from `phase2/consolidation` @ `c0d442f`.
**Corpus read at:** `c0d442f`. **Scope of the sweep:** `docs/architecture/**`, `supabase/migrations/**`,
`supabase/functions/**`.
**Predecessor:** `_governance/ODR4_OWNER_DECISION_ANALYSIS.md` (the four-reviewer pass that produced the
split). This document is its consequence side: it does not re-argue anything that document argued, and
it corrects it in three places, each marked.

**No `OFFLINE-VERIFY-v1` fenced block was touched — none appears in any file this pass created, and this
pass created exactly one file.** Verified rather than assumed, by extraction and hashing at `c0d442f`:
**four** blocks under `docs/architecture/**` (`PHASE_2_EDGE_FUNCTION_SPEC.md` §5.4.3 · `PHASE_2_DOOR_LIFECYCLE_SPEC.md`
· `PHASE_2_APPLE_WALLET_SPEC.md` ×2), **0 loose, 0 unterminated, one distinct body, 2017 bytes, 34 lines**,
`sha256 afb5184d58b62da5cb03cb8c4c7923953b4206c52f8afa23dee6403069fe6344` — **identical to the value `MP-1`
recorded and `D21`/`D22` re-verified**, so `C53`'s single-source claim still holds. **VERIFIED.**

**Evidence convention.** Every claim below is tagged **`VERIFIED`** (I read the cited text, or ran the cited
mechanical check, at `c0d442f`) or **`INFERENCE`** (a derivation from verified text, marked as mine).
**No count appears in this document without its enumeration beside it.** That rule is not stylistic: `F2`
of the predecessor analysis, and `DF-35` of the decision register, are both instances of a bare count
outliving the set it described.

---

## 0. The owner rulings, verbatim

Recorded here as the owner stated them, before any consequence is drawn. Nothing below reopens any of them.

> The original single `ODR-4` decision is **REJECTED AS MISFRAMED**. The specialist split is adopted:
>
> - **`ODR-4a` — GP-2 DELETE exception class: OWNER RULING = YES, IN PRINCIPLE.** Ratify the narrow DELETE
>   exception class required for genuine withdrawal/erasure of demographic answers. **This is NOT permission
>   to invent additional GP-2 exceptions.** The final architecture must **mechanically assert the exact closed
>   exception set catalog-wide** so a future exception cannot be added "by analogy."
> - **`ODR-4b` — `auth.users` CASCADE posture: DEFERRED / BLOCKED BY `ODR-16`.** Do not rule or implement
>   until `ODR-16` determines whether `auth.users` is actually deleted.
> - **`ODR-4c` — sentinel binding: ENGINEERING, NOT OWNER.** The prohibition must become a DB `CHECK` +
>   assertion on every correctly enumerated relation in scope, **before any of those relations can contain
>   production data.**
> - **`ODR-4d` — scope: MECHANICAL.** Correct the scope to the relations that actually carry each exception.
>   **Do not retain the unsupported "six-relation" statement.**
> - **Scheduling: Option 5 accepted in principle** — defer the demographic objects currently in `077` to the
>   appropriate `086`/`087` boundary, **provided the dependency proof remains valid.** This is a
>   package-placement action, **not** approval to build the demographic subsystem.
>
> **Standing blockers the owner has explicitly kept open** — these must appear in the map as blockers to
> shipping the affected objects: cascade blocked by append-only row triggers · missing `BEFORE DELETE`
> tombstone trigger from the package · tombstone UPSERT incompatible with its append-only/PK design ·
> unresolved tombstone retention window · no tombstone reaper · non-transactional / half-completing
> account deletion.

### 0.1 What this document does and does not do

| Does | Does not |
|---|---|
| Enumerate the GP-2 DELETE exception class and specify its closure assertion | Write the assertion into any package's Tests row |
| State the `ODR-4b` consequence under each `ODR-16` outcome | Rule `ODR-16`, or rule `ODR-4b` |
| Enumerate the relations needing the sentinel `CHECK` and specify the `CHECK` and its standing assertion | Add a `CHECK` to any migration or schema document |
| Replace the bare "six relations" with two enumerated scope sets and list every site carrying the bad count | Edit any of those sites |
| Prove or fail to prove the Option-5 package move on five limbs | Perform the move, or amend the registry |

---

# 1. `ODR-4a` — the GP-2 `DELETE` exception class

## 1.1 The rule being excepted

`PHASE_2_RLS_PERMISSION_SPEC.md` §1.3:138 — **`VERIFIED`**:

> **GP-2 — DELETE is DENY for every role on every table (no row deletion).** All FKs are `ON DELETE RESTRICT`;

Two clauses, and `ODR-4a` concerns **only the first**. The second clause is `ODR-4b` (§2 below). The
predecessor analysis is right that sharing one sentence is why they were filed as one decision and is not a
reason to rule them together.

A **third** rule is also excepted and no filing site names it — `SNATCH_IT_CANONICAL_DATA_MODEL.md` §10,
declared constitutional: rule 4 *"tombstone, don't erase"*; rule 9 *"Deletion is archive/anonymize, never a
dangling pointer"*; §43 *"Never hard-deleted (would orphan ledger references); deletion is anonymization to a
retained sentinel."* **`VERIFIED`** (`SNATCH_IT_CANONICAL_DATA_MODEL.md:43`). **`INFERENCE`:** ratifying
`ODR-4a` therefore ratifies a constitutional exception as well as an `RLS` one, and the ratification record
should say so, because the constitution is what an implementer reads when the RLS note is out of view.

## 1.2 The exception class — ENUMERATED. Exactly two members.

**`VERIFIED` — the class has exactly two members**, established by the sweep in §1.3 and not by counting
the corpus's own statements about it (six of which say "one").

| # | Definer body | Relation it `DELETE`s | Owner / posture | Package (today) | Grant site (verbatim) |
|---|---|---|---|---|---|
| **1** | `kernel.clear_my_demographics()` | `kernel.identity_demographic` | `SECURITY DEFINER`, owned by `postgres`, `search_path` pinned | **`077`** | RPC §0.5:168–172 · RPC §17.20:3233–3241 · DEMOG §10.2:1016–1018 · RLS §15.7 `MD-9`:2693 · RLS §16.5 n.¹:2882–2887 |
| **2** | `venue.remove_guest_entry(p_entry_id, p_reason_code, p_command_key)` | `venue.guest_entry` | `SECURITY DEFINER`, owned by `postgres` | **`086`** | RPC §20.5.5:5049–5072 · RPC §20.14 item 18:4007–4009 |

Member 1, verbatim — `PHASE_2_RPC_FUNCTION_CONTRACTS.md:168–172`:

> - **DELETE:** no RPC deletes rows (GP-2). **One named exception, granted once and not by analogy:**
>   `kernel.clear_my_demographics` (§17.20) hard-deletes the caller's own `kernel.identity_demographic` row
>   **inside the definer**; clients hold zero DELETE.

Member 2, verbatim — `PHASE_2_RPC_FUNCTION_CONTRACTS.md:5053–5058`:

> **This is the RPC that note 38 points at, and it is a real DELETE inside the definer** — the schema's
> `guest_entry.guest_list_id … on delete cascade` is the mechanism, and §0.5's no-DELETE rule (GP-2) is
> satisfied the same way it is for `kernel.clear_my_demographics`: **the client holds zero DELETE**, and the
> audit row carries the removed entry. **This is a second named GP-2 exception and it is granted narrowly, on
> the same reasoning as the first**

and its Writes row — `PHASE_2_RPC_FUNCTION_CONTRACTS.md:5066`:

> - **Writes.** DELETE one `venue.guest_entry`; `kernel.admin_audit` (`guest_entry.remove`, **`before` carries
>   the full removed row**, `reason_code`).

**The class has more than the one member six sites claim, and exactly two, not more.** The phrase *"on the
same reasoning as the first"* **is** grant-by-analogy; the owner's ruling — *"this is NOT permission to
invent additional GP-2 exceptions"* — is therefore a ruling that the analogy stops here, and §1.4's assertion
is the only thing that can make that stick.

### 1.2a One correction to the predecessor analysis

`ODR4_OWNER_DECISION_ANALYSIS.md:41` says *"Six sites say one exists."* **`VERIFIED` — the correct count of
sites asserting singularity is five**, and they are: `PHASE_2_RLS_PERMISSION_SPEC.md:2693` (`MD-9`) ·
`PHASE_2_RLS_PERMISSION_SPEC.md:2885` (§16.5 n.¹) · `PHASE_2_SCOPE_AMENDMENT_2026_08.md:166` ·
`PHASE_2_SCOPE_AMENDMENT_2026_08.md:352` (`HG-8`) / `:503` (`OD-19`) · `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md:492`,
plus the register's restatement at `PHASE_2_OWNER_DECISION_REGISTER.md:666` and `:701`, and RPC §0.5:168
itself. Counting §14.2-C `OD-19` and §11 `HG-8` as one document or two decides between five and six. **The
enumeration is what matters and it is given; the number is not load-bearing and is recorded here only so
this document does not repeat the defect it exists to close.**

## 1.3 The sweep that establishes closure — method, and every negative result

**Method (`VERIFIED`, run at `c0d442f`).** Four independent passes over `docs/architecture/**`:

1. **Every `DELETE FROM` occurrence**, excluding `ON DELETE …` referential actions and
   `REVOKE …, DELETE` privilege statements — 12 hits.
2. **Every RPC-contract `Writes.` line** mentioning a delete/remove/purge/prune verb — 2 hits.
3. **Every `GP-2` occurrence** across the corpus — 44 hits.
4. **Every delete-verb phrase** (`hard-delete`, `deletes the/one/a/its/every/all`, `removes the row`,
   `physically delete`) — 21 hits.

**Every candidate that is NOT a member, and why (`VERIFIED`):**

| Candidate | Verdict | Evidence |
|---|---|---|
| `venue.claim_artifacts_for_purge` · `venue.confirm_artifact_purged` · `venue.reconcile_export_orphans` | **Not members.** They flip `artifact_state` on `venue.export_job`; the byte delete is the `crm-export-worker` `POST /purge` edge route. `DELETE FROM storage.objects` is explicitly **REJECTED** as the mechanism | CRM §11 `K-16`:2391 · RLS §16.4:2232 · EDGE §2:306 |
| `venue.unpublish_holder_mix` · `venue.unpublish_all_holder_mix` | **Not members.** *"Set `published_at = NULL` on the targeted snapshot(s); **delete nothing**"* — and the reason is stated: *"deleting destroys the evidence of what was shown"* | RPC §17.20:3264–3273 |
| `kernel.revoke_platform_role` / `revoke_org_role` / `venue.revoke_staff_role` | **Not members.** *"INSERT on approval / DELETE-free … the audit row carries the removed grant"* | RPC:4375–4377 · RPC:4783 |
| `catalog.set_platform_config` | **Not a member, and asserted so.** `T-RPC-CFG-04`: *"**zero UPDATE and zero DELETE paths on `platform_config`**, as `postgres` and as `service_role`"* | RPC §18:3885 · RPC:4488 |
| Every AO ledger (`kernel.admin_audit`, `ticket_ownership_log`, `identity_demographic_erasure`, both contact `_event` logs, `venue.scan`, `door_manifest*`, promoter ledgers) | **Not members.** `raise_append_only()` raises on UPDATE/DELETE; `REVOKE UPDATE, DELETE` | plan §8:489 · schema §1.15:1811/:1869 |
| `venue.door_manifest` / `door_manifest_entry` / `kernel.door_freeze_override` | **Not members.** *"`DELETE FROM …` raises"* asserted as door assertion 54 | DOOR §15:1826 |
| The four Wallet tables | **Not members.** *"`DELETE FROM` any of the four tables raises (GP-2)"* | WALLET §…:1588 |
| The sweeps — `kernel.sweep_expired_ticket_atoms`, `venue.sweep_expired_exports`, `sweep_expired_inventory_holds`, `sweep_expired_door_sessions`, `sweep_expired_door_overrides`, `catalog.sweep_implicit_door_freezes`, `market.sweep_expired_p2p_transfers`, `market.sweep_paid_pending_sales` | **Not members.** Every one is a state transition. `T-SCHEMA-PURGE-05` is explicit: *"`sweep_expired_exports` moves ZERO bytes"*; `venue.sweep_expired_door_sessions` *"NOT load-bearing — expiry is arithmetic inside the predicate"* | plan §8:1460 · plan §8:1429 · plan §8:1455 |
| `venue.decide_flagged_attribution` | **Not a member.** The *contract* is deleted (`AUTHZ-H10`), not rows | RPC:3088, :3136, :6591 |
| A tombstone reaper for `kernel.identity_demographic_erasure` | **Would be a third member if it existed. It does not exist anywhere in the sixteen packages** — see §6 blocker E. **This is the one place a third member is scheduled to appear**, and `ODR-4a`'s closure assertion must be written knowing it | §6.E |

**`INFERENCE` — the sweep's residual risk.** `plpgsql` bodies are not validated at `CREATE FUNCTION`
(registry §2.2), so no document-level sweep can see a `DELETE` that an implementer adds later, and no
catalog-level check can see one built by `EXECUTE format(...)`. That is precisely why the ruling asks for a
mechanical assertion rather than a documentation fix, and why §1.4 carries a dynamic-SQL limb.

## 1.4 The mechanical closure assertion

**Id.** `T-SCHEMA-GP2-01` / `-02` / `-03`. **`VERIFIED`** the family `T-SCHEMA-GP2` is free: the 21
`T-SCHEMA-*` domains in use at `c0d442f` are `APPR · ATTR-CAND · AUDIT · CFG · CRM · CUSTODY · DELTA · DEV ·
DOOR · EXPIRY · GRANT · ISSUE · MINT · OFFER · PAYOUT · PROMO · PURGE · REFUND · ROLE · SEAM · SENTINEL ·
SETTLE` — `GP2` is not among them. Naming follows `T-<LAYER>-<AREA>-<NN>` (X-6 assurance plan §2). **No
existing id is renumbered**, per `D22`'s standing rule.

**Where it runs.** Two placements, and the split is the whole point:

| Id | Runs | Form | Why there |
|---|---|---|---|
| `T-SCHEMA-GP2-01` | **every package's replay verify, `076`…`091`** | **⊆** (subset) | Catches the package that *adds* an unratified exception, at that package, not nine later |
| `T-SCHEMA-GP2-02` | **the terminal replay, after `091`** | **=** (set equality) | Equality is only true once the whole band has replayed; asserting it early fails on the members not yet created |
| `T-SCHEMA-GP2-03` | with `-01` and `-02` | **non-vacuity + poison pill** | Without it, a detector that sees nothing passes both |

**The check.**

```text
-- Ratified class (the literal enumeration; ONE copy, read by all three assertions):
--   ('kernel','identity_demographic')   <- kernel.clear_my_demographics
--   ('venue','guest_entry')             <- venue.remove_guest_entry

-- (a) OBSERVED SET. Every postgres-owned SECURITY DEFINER body in the four Phase-2
--     schemas whose source contains a DELETE, resolved to the relation deleted.
WITH definers AS (
  SELECT p.oid, n.nspname AS fn_schema, p.proname, p.prosrc
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_authid  a ON a.oid = p.proowner
   WHERE n.nspname IN ('kernel','catalog','venue','market')
     AND p.prosecdef                      -- SECURITY DEFINER
     AND a.rolname = 'postgres'           -- the O17=B ownership global
),
observed AS (
  SELECT DISTINCT
         lower((m)[1]) AS rel_schema,
         lower((m)[2]) AS rel_name,
         d.proname     AS by_function
    FROM definers d,
         LATERAL regexp_matches(
           d.prosrc,
           '\mDELETE\s+FROM\s+(?:ONLY\s+)?"?(\w+)"?\s*\.\s*"?(\w+)"?',
           'gi') AS m
)
-- (b) T-SCHEMA-GP2-01  (per package, SUBSET):
--     observed  MINUS  ratified_class   MUST be EMPTY.
--     Any row is an unratified GP-2 exception; the row names the function and the relation.
-- (c) T-SCHEMA-GP2-02  (terminal, EQUALITY, both directions):
--     observed  MINUS ratified_class = {}   AND   ratified_class MINUS observed = {}
--     The second direction is not decoration: a ratified member with no DELETE means the
--     withdrawal path was quietly re-implemented as an UPDATE, which is a change to what
--     ODR-4a ratified and must not pass silently.
-- (d) T-SCHEMA-GP2-03  (NON-VACUITY, three limbs, ALL required):
--     d1  the definer scan is not empty: count(*) FROM definers  >=  <the §20 floor>.
--         An empty scan makes (b) and (c) pass trivially, and an owner-role rename,
--         a schema rename or a prosecdef flip all produce exactly that.
--     d2  positive control: at or after the package creating the FIRST class member,
--         `observed` is NON-EMPTY and contains that member. A detector that finds the
--         DELETE that is really there is the only evidence it would find one that is not.
--     d3  poison pill: a scratch postgres-owned definer containing
--         `DELETE FROM kernel.__gp2_poison` is created, MUST be reported by (b), then
--         dropped in the same transaction. This is the limb T-VERIFY-X6-05 exists for,
--         applied here.
-- (e) DYNAMIC-SQL LIMB (mandatory, and the reason (a) is not sufficient alone):
--     no body in `definers` contains EXECUTE outside a declared allow-list, asserted the
--     way T-RPC-CRM-19 / T-VERIFY-X6-05 assert it. A regex over prosrc cannot see
--     EXECUTE format('DELETE FROM %I.%I', ...), and that is the one construction that
--     defeats (a) completely.
```

**Style provenance — the corpus already writes assertions this way (`VERIFIED`, all four):**

- **Set equality both directions, over `pg_proc`, with a non-vacuity guard** — `T-RPC-SET-01`,
  `PHASE_2_RPC_FUNCTION_CONTRACTS.md:4178–4182`: *"Enumerate `pg_proc` … assert the result equals … **in both
  directions** … Non-vacuity guard: the assertion must prove it can see at least the fifty functions §20
  names."*
- **Equality against a literal enumeration, with an explicit anti-empty-set clause** — `T-RLS-ROLE-06`,
  `PHASE_2_RLS_PERMISSION_SPEC.md:3389`: *"**Non-vacuity guard:** the assertion fails if the list it read is
  empty or shorter than ten, since an empty set equals an empty set."*
- **Writer-set closure on this very table** — `T-RPC-DEMO-01`, `PHASE_2_RPC_FUNCTION_CONTRACTS.md:3231`:
  *"the set of functions writing `kernel.identity_demographic` is **exactly** `{set_my_demographics,
  clear_my_demographics}`."*
- **Textual + structural + non-vacuity, in one block** — CRM §10.3 Layer 2,
  `PHASE_2_CRM_EXPORT_SPEC.md:1634–1651`, which is the only executable-shaped catalog assertion in the corpus
  and is the shape (a)–(d) above copies.

And the house rule the design of `-02` obeys — `PHASE_2_SPEC_FOUNDATION.md:68`, **`VERIFIED`**:
*"**A count assertion passes on the wrong set of the right size**."* Hence set equality, never `count(*) = 2`.

## 1.5 The three build defects that must be repaired first

The owner ruling is *"YES, IN PRINCIPLE"*. These three are what stands between the principle and a package
that can execute it. Each is stated with the two documents that disagree, so the repair is a reconciliation
and not a rewrite.

### Defect 1 — the cascade cannot execute: append-only row triggers abort it

**`VERIFIED`.** `kernel.identity_contact_pref_event` (`077`) and `kernel.org_contact_consent_event` (`082`)
each carry `identity_id` `FK→auth.users(id)` **`ON DELETE CASCADE`** *and* are declared
**AO — INSERT-only, `kernel.raise_append_only()` trigger, `REVOKE UPDATE, DELETE`**, in the same subsection.

- `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1800` — *"`identity_id` uuid — not null, FK→`auth.users(id)`
  **ON DELETE CASCADE** (rides the named exception **D-3**, below)."*
- `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1811` — *"**Immutability:** **AO** — INSERT-only;
  `kernel.raise_append_only()` trigger; `REVOKE UPDATE, DELETE`."*
- Same pair at `:1854` and `:1869` for the `082` sibling.
- `PHASE_2_SUPABASE_MIGRATION_PLAN.md:489` — `kernel.raise_append_only()` is *"the guard trigger function
  that raises on UPDATE/DELETE for AO tables"*, created once in `076`.

**A referential CASCADE is a `DELETE` on the referencing table and fires its row triggers.** `REVOKE DELETE`
does not stop a cascade; the trigger does. **`INFERENCE` (and the predecessor analysis's, which I confirm):**
from `077` onward, `auth.admin.deleteUser()` aborts for any identity with an event-log row — and
`kernel.set_my_contact_prefs` *"appends one row in the SAME transaction as its current-state upsert — that
append is the function's contract, not an optimization"* (`PHASE_2_SUPABASE_MIGRATION_PLAN.md:1282`,
**`VERIFIED`**), so that is every fan who has ever touched the master switch.

**Bearing on `4a`:** `clear_my_demographics`'s own `DELETE` is unaffected. **But the ratified justification
for the DELETE — that *every* removal path produces a tombstone, withdrawal and cascade alike — is false
while the cascade cannot run.** Ratifying the exception on that justification, before this is repaired,
ratifies a property the package does not have.

### Defect 2 — the compensating control is absent from the package it ships in

**`VERIFIED` — four documents, and the two that build things disagree with the two that specify them:**

| Document | What it says | Citation |
|---|---|---|
| demographics spec §8.2 / §10.2 / assertion 25, ratified `C64`/`J-12` | **exactly two** triggers: `set_updated_at` + the `BEFORE DELETE FOR EACH ROW` erasure-tombstone writer | `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md:776–790`, `:1032–1035`, `:965` |
| **migration plan `077` Triggers row** | *"**`identity_demographic` carries exactly one trigger — the `updated_at` maintainer — and nothing else** (no prior-value capture)."* | `PHASE_2_SUPABASE_MIGRATION_PLAN.md:1284` |
| package registry `077` (table row + JSON) | **no trigger, no trigger function** | `PHASE_2_PACKAGE_REGISTRY.md:393`, `:652` |
| physical schema spec | **no definition of `kernel.identity_demographic` at all** — one placement-table row pointing at the demographics spec, and nothing else | `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3913` (the only occurrence in that file) |

**`INFERENCE`:** built as the plan is written, **no removal path writes any tombstone** — not withdrawal, not
cascade — and it fails **silently**: the `DELETE` succeeds and nothing errors. `J-12` was ratified precisely
to move tombstone-writing *out of* the RPC and into the trigger; with the trigger absent, `J-12`'s repair has
removed the only writer that existed. **That is strictly worse than the defect `C64` was ratified to fix.**

**Bearing on `4a`:** the `DELETE` exception's entire justification (§8.2/§8.5) is that erasure is genuine and
re-appliable after a restore. The tombstone is the mechanism. **The exception cannot be ratified in a package
that does not contain its control.**

### Defect 3 — the tombstone is an UPSERT into an append-only table, with two incompatible PKs

**`VERIFIED`, three separate statements:**

- The write is an **upsert** — `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md:777`: *"a `BEFORE DELETE FOR EACH ROW`
  trigger … that **upserts** the value-free `kernel.identity_demographic_erasure` row."*
- The target is **AO** — `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md:1024` (*"AO, definer-only, value-free"*) with
  `raise_append_only` attached (`PHASE_2_SUPABASE_MIGRATION_PLAN.md:1284`).
- The PK is stated **two incompatible ways**:
  - `PHASE_2_SPEC_FOUNDATION.md:125` — PK **`id`** (surrogate), and the tuple it gives is
    `(identity_id, erased_at)` — **`purge_after` is absent from that row entirely.**
  - `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md:1028` — PK **`identity_id`**, *"bare uuid — deliberately NO foreign
    key to `auth.users`"*, plus `erased_at` and `purge_after`.

**`INFERENCE`:** answer → clear → answer again → clear. Under PK `identity_id`, `ON CONFLICT DO UPDATE`
performs an UPDATE, `raise_append_only()` raises, the exception propagates out of the `BEFORE DELETE`
trigger, **and the withdrawal RPC refuses to withdraw** — the failure mode being the exact opposite of what
the exception exists to deliver. `ON CONFLICT DO NOTHING` is silently wrong instead: `purge_after` never
advances, so the second erasure is dated by the first. Under PK `id` the table is append-many and AO is
coherent, but then assertion 29 (*"the trigger writes exactly one erasure row"*) needs restating as
one-per-removal rather than one-per-identity.

**Bearing on `4a`:** the exception ratifies a withdrawal that must be repeatable. **It is not expressible
until the PK and the AO class are settled, and the corpus states both ways.**

## 1.6 What `4a` ratifies, and what it does not

**Ratifies (`INFERENCE`, from the ruling text):** a **closed two-member class**, each member's `DELETE`
confined to a `postgres`-owned `SECURITY DEFINER` body, with clients holding zero table `DELETE`, on
relations that reference no ledger, draw no capacity and move no custody.

**Does not ratify:** (i) any third member, including a tombstone reaper — one is needed (§6.E) and it must be
added to the class **explicitly**, by amendment, not by the reaper simply appearing; (ii) the
`ON DELETE CASCADE` limb, which is `4b`; (iii) the constitutional exception going unrecorded (§1.1);
(iv) `clear_my_demographics` as the *only* possible design — the corpus never states the alternative, so it
is stated once here for the record: `UPDATE … SET gender_identity = NULL` erases the value with no GP-2
exception, no `BEFORE DELETE` trigger and no erasure table, at the cost that `first_answered_at` reveals the
person once answered. **`INFERENCE`:** that is the same fact the tombstone reveals, except the tombstone was
supposed to self-purge and (§6.E) has no reaper. The `DELETE` is still the cleaner design; it is not the only
one, and the owner is granting a precedent on a protected class.

---

# 2. `ODR-4b` — the `auth.users` CASCADE posture under each `ODR-16` outcome

**Ruling: DEFERRED / BLOCKED BY `ODR-16`. Nothing below rules it.**

## 2.1 `ODR-16`, verbatim

`_governance/PHASE_2_OWNER_DECISION_REGISTER.md:1050–1066`, **`VERIFIED`**:

> ### ODR-16 — How account deletion behaves for an identity holding custody · `079`
> **Status.** OPEN — OWNER.
> **Choice.** **(a) tombstone** — retain the `auth.users` row marked erased, revoke credentials, crypto-shred
> PII, keep an opaque dereferenceable uuid; **(b) refuse while custody is live** — deletion is refused, with a
> named reason, until every held atom is terminal or transferred; **(c) forced hand-off** — deletion voids or
> transfers the remaining atoms through the custody engine first.

The canonical option table is `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3602–3606` (§5.1). **The owner's
labels A/B/C map 1:1 onto the corpus's (a)/(b)/(c)** — **`VERIFIED`**, both spellings checked.

## 2.2 The consequence, per outcome

| `ODR-16` | Is the `auth.users` row deleted? | What the CASCADE does | `ODR-4b` status |
|---|---|---|---|
| **A — tombstone** | **NO.** *"the `auth.users` row is retained and marked erased … the row survives deletion"* (schema §5.1:3604) | **Never fires.** `ON DELETE CASCADE` is triggered by a `DELETE` on the referenced row; there is no such `DELETE` | **INERT** — the exception grants a behaviour that cannot occur |
| **B — refuse while custody is live** | **YES, eventually** — refused only *"until every atom held by the identity is terminal … or transferred"* (schema §5.1:3605) | **Fires, on every deletion that is permitted at all.** The cascade is the erasure mechanism | **LOAD-BEARING** — refusing it makes the permitted deletion fail on the contact/consent log |
| **C — forced hand-off** | **YES** — atoms are voided or transferred first, then the row is deleted (schema §5.1:3606) | **Fires, on every deletion.** Identical to B from the cascade's point of view | **LOAD-BEARING**, on exactly the same terms as B |

**So: A makes it inert; B and C make it load-bearing.** There is no `ODR-16` outcome under which the cascade
is *irrelevant* in the sense of harmless-either-way — under A it is not harmless, it is a control that reads
as present and is not, which §2.3 develops.

## 2.3 What outcome A means for erasure — and its compensating control is Gate L

Under **A**, five consequences follow, and none is stated anywhere in the corpus (**`INFERENCE`**, from
verified components):

1. **The demographic answer survives account deletion indefinitely.** No `DELETE` on `auth.users` means no
   cascade on `kernel.identity_demographic`.
2. **The tombstone trigger writes nothing on that path.** It is `BEFORE DELETE` on a row that is not deleted.
   `J-12`'s "every removal path produces one" is satisfied vacuously, because deletion stops being a removal
   path.
3. **The contact preference and every org consent row survive too** — including, verbatim from
   `PHASE_2_SUPABASE_MIGRATION_PLAN.md:1372`, the *"consent granted to 40 orgs"* shape the §5.1 export gate
   would keep evaluating.
4. **A's own compensating control is not built in Phase 2.** A names *"PII is crypto-shredded per C15"*
   (schema §5.1:3604). **`VERIFIED`:** `C15` is **Gate L** — `SNATCH_IT_CANONICAL_DATA_MODEL.md:693` records
   it as *"L (claim) · Ratified (superseded-in-part by C34)"*; `C34`, which *"replaces the bare 'crypto-shred
   solves GDPR' reading of C15"*, is `RATIFIED-MODELED-ONLY(GATE-L)`; and
   `PHASE_2_SUPABASE_MIGRATION_PLAN.md:1092` puts *"erasure crypto-shred / PII vault (C15)"* in the
   **Gate-L** list, alongside multi-currency and DR. **So under A there is neither a cascade nor a
   crypto-shred, in Phase 2.**
5. **The binding fan-facing copy ships false.** DEMOG §8.5's promise sentence tells the person their answer is
   removed *"right away"*. Under A, for account deletion, it is not removed at all. That is a copy defect with
   a legal surface, not a schema defect.

**`INFERENCE` — the consequence for `4b`'s sequencing.** Ruling `4b` before `ODR-16` risks granting an
irreversible-sounding exception to a mechanism a later ruling makes dead code. **And the reverse risk is
sharper and is not in the predecessor analysis:** ruling `ODR-16 = A` *without* revisiting `4b` leaves the
corpus asserting an erasure guarantee (DEMOG §8.2, CRM §9.2, assertion 30) whose only Phase-2 mechanism
never executes. **If `ODR-16` resolves A, `4b` does not become moot — it becomes a different decision**,
namely "what erases a demographic answer when the identity row is retained", and the corpus has no answer to
it.

## 2.4 What is inadmissible under all three, and therefore under `4b` regardless

**`VERIFIED`** — `PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:3608–3612` and register `:1059–1060`: reusing the
`019` anonymization sentinel as the new `current_owner_id` is inadmissible under (a), (b) and (c) alike
(record `C96`). **`INFERENCE`:** that prohibition and `ODR-4c` are the same rule applied to two different
column families — custody columns (`CUSTODY-DEL-1`, ratified `C95`) and demographic/contact columns
(`ODR-4c`, unbuilt). **`4c` is therefore executable today irrespective of `4b`**, which is exactly what the
owner ruled.

---

# 3. `ODR-4c` — the sentinel binding, as a `CHECK` and a standing assertion

**Ruling: ENGINEERING, NOT OWNER. The prohibition must become a DB `CHECK` + assertion on every correctly
enumerated relation in scope, before any of those relations can contain production data.**

## 3.1 What the prohibition currently is

**`VERIFIED` — it is prose in three places and a behavioural test in one, and it is a database constraint
nowhere:**

- `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md:801–804` — *"The demographic row **must never be repointed to that
  sentinel** — doing so would pile every deleted user's gender answer onto a single identity and create a
  'sentinel demographics' row … **This is an explicit constraint on whoever next edits 020.**"* (`D-11`).
- `PHASE_2_CRM_EXPORT_SPEC.md:2381` (`K-6`) / `:2349` (`D-3`) — *"never repoint a contact-preference or
  contact-consent row to the anonymized sentinel."*
- `PHASE_2_CRM_EXPORT_SPEC.md:1519` — *"a sentinel row holding 'consent granted to 40 orgs' would be an
  accumulating grant belonging to nobody, and the gate in §5.1 would evaluate it."*
- Demographics assertion **30** (`PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md:1373–1379`) is a **behavioural test of
  the cascade path only**: *"the row is **not** repointed to the … sentinel; the sentinel identity holds no
  demographic row after any account deletion."* It tests an outcome of one path; it does not constrain the
  column.

**What the live path actually does (`VERIFIED`, read from the applied migrations at `c0d442f`, not inferred):**
`supabase/migrations/020_delete_account_cleanup_rpc.sql` repoints **exactly five columns across three
`public.*` tables** — `public.listings.seller_id` (`020:49–51`), `public.payments.buyer_id` (`:57–59`),
`public.payments.seller_id` (`:61–63`), `public.transfers.buyer_id` (`:66–68`),
`public.transfers.seller_id` (`:70–72`) — to `00000000-0000-0000-0000-000000000000`
(`019_anonymized_sentinel_user.sql:24`, with the `'Deleted User'` profile row at `019:43`). **It touches no
`kernel.*`, `catalog.*`, `venue.*` or `market.*` relation.** It performs the `listings` repoint with
`alter table public.listings disable trigger trg_guard_listing_identity` (`020:47`/`:53`) — **so the house
pattern for "this column is guarded" is already known to be bypassable by the very routine that would be
extended.** That is the sharpest argument for a `CHECK`: a `CHECK` constraint is not a trigger and
`DISABLE TRIGGER` does not touch it.

## 3.2 The relations in scope — ENUMERATED, with the proof of each

A relation qualifies if it carries an identity column an account-deletion path could plausibly repoint.
**Six relations qualify. `venue.export_job` is examined and excluded, with its reason; `kernel.org_customer_key`
is examined and excluded, with its reason.** Both exclusions are recorded because both appear in the "six"
that `4d` corrects, and an unexplained absence is how a scope silently re-widens.

| # | Relation | Identity column | Created by | FK target + referential action | PK shape → repoint failure mode | Citation |
|---|---|---|---|---|---|---|
| **1** | `kernel.identity_demographic` | `identity_id` | `077` | `auth.users(id)` **CASCADE** | **PK = `identity_id`** (single column) → a repoint of a *second* identity collides on the PK and **fails loud (`23505`)**. The **first** repoint succeeds silently, welding one person's gender answer to "Deleted User" | DEMOG §10.2:1009, §10.1:964 |
| **2** | `kernel.identity_demographic_erasure` | `identity_id` | `077` | **NO FK — bare uuid, deliberately** | **CONTRADICTED.** DEMOG §10.2:1028 says PK `identity_id`; SPEC_FOUNDATION §6:125 says PK `id`. Under PK `identity_id` → loud on the second; under PK `id` → **silent accumulation, forever**. **The FK-free design means there is no referential action to fall back on and nothing else in the database constrains this column at all** | DEMOG §10.2:1024–1030 · SPEC_FOUNDATION §6:125 |
| **3** | `kernel.identity_contact_pref` | `identity_id` | `077` | `auth.users(id)` **CASCADE** | **PK = `identity_id`** → loud on the second repoint, silent on the first | CRM §11.2:1759 · registry §2:393 |
| **4** | `kernel.identity_contact_pref_event` | `identity_id` | `077` | `auth.users(id)` **CASCADE** | **PK = `id` (surrogate uuid); no unique on `identity_id`** → **NO TRIPWIRE. Accumulates silently, every deleted fan's switch history piling onto one identity** | schema §1.15.1:1800, :1806, :1808 |
| **5** | `kernel.org_contact_consent` | `identity_id` | `082` | `auth.users(id)` **CASCADE** | **PK = `(identity_id, org_id)` (composite)** → **NO TRIPWIRE unless two deleted fans consented to the same org. Accumulates silently — this is literally the "consent granted to 40 orgs" row CRM §9.5 names** | CRM §11.2:1767 |
| **6** | `kernel.org_contact_consent_event` | `identity_id` | `082` | `auth.users(id)` **CASCADE** | **PK = `id` (surrogate uuid)** → **NO TRIPWIRE. Accumulates silently** | schema §1.15.2:1854, :1857, :1866 |

**Examined and EXCLUDED, with reasons (`VERIFIED`):**

| Relation | Column | Why excluded |
|---|---|---|
| `kernel.org_customer_key` | — | **No identity column at all.** PK is `org_id` → `kernel.organization`; the only other columns are `key_material`, `created_at`, `rotated_at`. **There is nothing here an account-deletion path could repoint.** (CRM §11.2:1770–1775) |
| `venue.export_job` | `requested_by` | **In scope for a different rule.** `requested_by` is `uuid NOT NULL FK→auth.users` **ON DELETE RESTRICT** (CRM §11.2 · schema §3.18:3267) — the *opposite* referential action, so it carries no part of the `4b` CASCADE exception. **`INFERENCE`: the repoint *pressure* on it is higher, not lower** — under `RESTRICT` the deletion fails and the sentinel is the obvious house-pattern fix. It belongs in a `CUSTODY-DEL-1`-shaped ruling for RESTRICT-side identity columns, which the corpus has not written. **Recorded here as an open scope question, not resolved.** |
| `venue.holder_mix_snapshot` · `venue.holder_mix_bucket` | — | **No identity column, and asserted so.** Demographics assertion 28: *"`holder_mix_snapshot` and `holder_mix_bucket` have no `uuid` column referencing `auth.users`, and no FK to any identity-bearing table."* (DEMOG §13:1305) |
| `kernel.tickets.current_owner_id` · `kernel.ticket_ownership_log.{from_identity, to_identity, actor_identity}` | 4 columns | **Already ruled — `CUSTODY-DEL-1`, ratified `C95`**, and asserted as `T-SCHEMA-SENTINEL-05`. Out of `4c`'s scope because they are in someone else's. (schema §5.1:3577–3578) |

**`UNKNOWN` — none.** Every relation in the table above is proven from the corpus at the stated line. Two
sub-facts are marked as contradicted rather than unknown, and both are Defect 3 of §1.5:
`kernel.identity_demographic_erasure`'s PK, and whether `purge_after` is a column of it at all
(SPEC_FOUNDATION §6:125 omits it; DEMOG §10.2:1030 declares it `NOT NULL`).

**The per-relation urgency differs and no document says so (`INFERENCE`, and it is the operational point).**
Rows 4, 5 and 6 have **no PK tripwire at all**. A `020` extension that repoints them produces no error, no
duplicate-key, no log line — it produces a sentinel identity that accumulates the contact history of every
deleted fan, and the `§5.1` export gate evaluates it as a live grant. Row 1 fails loud, but only on the
*second* occurrence, after one real person's answer is already merged. **Row 2 is the worst case and the least
visible:** it has no FK, so no referential action exists to argue about, and its PK is stated two ways, so
whether it has a tripwire is currently undecidable from the corpus.

## 3.3 The `CHECK`

One constraint, six relations, identical text:

```sql
ALTER TABLE <relation>
  ADD CONSTRAINT <table>_identity_not_anon_sentinel
  CHECK (identity_id <> '00000000-0000-0000-0000-000000000000'::uuid);
```

Authored **with its relation**, in the package that creates it — `077` for rows 1–4, `082` for rows 5–6 —
so it exists before the table can hold a row. **`INFERENCE`, and it is why the owner made this
time-critical:** a `CHECK` added later requires `VALIDATE CONSTRAINT`, which **fails** if a single row has
already been repointed, and the repair is not a migration — it is a merged sentinel row with no recorded
pre-image. **Unlike the custody side, there is no ledger to reconstruct from**: `kernel.identity_demographic`
is declared *"not a ledger, no history"* (DEMOG §10.2:1005) and `identity_contact_pref` *"MUT, not a ledger"*
(CRM §11.2:1755). The `_event` logs are AO and would tell you a flip happened, not whose it was after the
merge.

Three properties worth stating because each is a reason a reviewer might wrongly think the `CHECK` is
redundant:

1. **It is not a trigger.** `020` already ships `alter table … disable trigger trg_guard_listing_identity`
   (`020:47`, **`VERIFIED`**). A future `020` extension written by the same hand would disable a guard trigger
   and would **not** be able to disable a `CHECK`.
2. **It is not implied by the FK.** `CASCADE` governs what happens when the *referenced* row is deleted. It
   says nothing about an `UPDATE` that repoints the referencing column to a different, extant `auth.users`
   row — and the sentinel **is** an extant `auth.users` row (`019:13–35`).
3. **It is not implied by assertion 30.** That assertion tests the cascade path. A `020` extension repoints
   *before* `deleteUser` is called, so the assertion's fixture never reaches the state it checks for.

## 3.4 The standing catalog assertion

**Modelled on `T-SCHEMA-SENTINEL-05`, the assertion the corpus already wrote for the custody columns.**
Verbatim, `PHASE_2_SUPABASE_MIGRATION_PLAN.md:1306` (package `078` Tests row) — **`VERIFIED`**:

> **`-05`, the anti-shortcut assertion: `00000000-…-000000000000` appears in ZERO rows of
> `kernel.tickets.current_owner_id` and of every ownership-log identity column** — a standing invariant over
> the custody tables rather than a test of one function, because the shortcut is taken at whichever call site
> the implementer happens to be looking at

**The justification applies verbatim to all six relations of §3.2, and is not restated.**

**Proposed id: `T-SCHEMA-SENTINEL-07`** — the family that already owns the all-zeroes-uuid invariant, next
free ordinal (**`VERIFIED`**: `-01`…`-06` are in use, `-07` is free), appended and renumbering nothing, per
`D22`'s standing rule.

```text
T-SCHEMA-SENTINEL-07 — the demographic/contact half of the anti-shortcut invariant.

(a) INVARIANT. '00000000-0000-0000-0000-000000000000' appears in ZERO rows of
    identity_id on all six relations of §3.2:
      kernel.identity_demographic
      kernel.identity_demographic_erasure
      kernel.identity_contact_pref
      kernel.identity_contact_pref_event
      kernel.org_contact_consent
      kernel.org_contact_consent_event
    Asserted as a standing invariant over the relations, not as a test of
    delete_account_cleanup, for the reason -05 already gives.

(b) STRUCTURAL LIMB — and this is the half -05 does not have. Assert over
    pg_constraint that each of the six carries a CHECK whose expression is
    exactly `identity_id <> '00000000-...'::uuid`, and that convalidated = true.
    Rationale: (a) alone passes on an empty table, which is the state every one
    of these relations is in at the package that creates it. A value assertion
    over an empty relation is not evidence of anything.

(c) NON-VACUITY, three limbs, ALL required:
    c1  relation floor: to_regclass() is NOT NULL for all six — six non-null
        oids, asserted by count, because a renamed or unbuilt relation makes
        (a) pass by finding nothing to look at.
    c2  positive control: a row with a NON-sentinel identity_id exists in at
        least one of the six at assertion time, so (a) is known to be reading
        rows and not an empty scan.
    c3  poison pill: an attempted INSERT/UPDATE setting identity_id to the
        sentinel MUST raise 23514 on each of the six, asserted per relation.
        This is the limb that proves the CHECK is attached and enabled rather
        than merely present in a migration file.

(d) WHERE IT RUNS. Rows 1-4 at `077` verify; rows 5-6 at `082` verify; all six
    at the terminal replay. NOT at a single earlier package.
```

**`INFERENCE` — one defect in the model assertion that must NOT be copied.**
`T-SCHEMA-SENTINEL-05` is filed in package **`078`**'s Tests row (`PHASE_2_SUPABASE_MIGRATION_PLAN.md:1292`
is the `078` heading; `:1306` is its Tests row) and asserts over **`kernel.tickets.current_owner_id`** — a
column on a relation package **`079`** creates (registry §2:396). At `078` the relation does not exist, so
the assertion either errors or, if written defensively, passes on nothing. **It also carries no non-vacuity
guard**, unlike its siblings `T-SCHEMA-CFG-01` and `T-SCHEMA-CUSTODY-04`, both of which have explicit ones.
`T-SCHEMA-SENTINEL-07` is specified above with the guard and with a per-package placement precisely so it does
not inherit either problem. **Filed as a separate observation for the plan owner: `T-SCHEMA-SENTINEL-05`'s
placement should move to `079`.** Not corrected here.

## 3.5 Why `4c` is genuinely not an owner decision

**`VERIFIED`** — all four reviewers of the predecessor pass agreed, and the mechanism is checkable: the
prohibition is already ratified prose (`D-11`, `D-3`/`K-6`), the `CHECK` implements exactly that prose and
nothing more, and the assertion is an extension of an already-ratified standing invariant. Nothing here
chooses between options; it converts a sentence into a constraint. **The only thing the owner has to supply
is the instruction to do it before the tables can hold rows, which the ruling supplies.**

---

# 4. `ODR-4d` — scope, enumerated

**Ruling: MECHANICAL. Correct the scope to the relations that actually carry each exception. Do not retain
the unsupported "six-relation" statement.**

## 4.1 Where the "six" actually came from — solved

The predecessor analysis (§8, *"What could not be verified"*) says: *"**The sixth relation in the 'widened
scope' is enumerated in no document.** Five are nameable with citations."* **That is now solved, and the
answer is that the six is a real, enumerable set — of the wrong thing.** **`VERIFIED`:**

**The six is the CRM spec's own RLS/inventory tally, not a cascade scope.** `PHASE_2_CRM_EXPORT_SPEC.md` §11.3
REVOKE block lists exactly six relations:

```text
REVOKE ALL ON kernel.identity_contact_pref        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON kernel.identity_contact_pref_event  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON kernel.org_contact_consent          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON kernel.org_contact_consent_event    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON kernel.org_customer_key             FROM PUBLIC, anon, authenticated;
REVOKE ALL ON venue.export_job                    FROM PUBLIC, anon, authenticated;
```

The same six, by name, three more times:

- CRM §11.1 element **34** — *"RLS spec §6 column-scoped table — add **6** deny-all rows"*.
- CRM §11.1 element **35** — *"SPEC_FOUNDATION §6 table inventory — add **6** tables"*.
- `PHASE_2_RLS_PERMISSION_SPEC.md:3377` (`T-RLS-POL-02`) — *"one of the **six** zero-policy relations …
  `kernel.identity_contact_pref` · `kernel.identity_contact_pref_event` · `kernel.org_contact_consent` ·
  `kernel.org_contact_consent_event` · `kernel.org_customer_key` · `venue.export_job`."*
- `PHASE_2_SPEC_FOUNDATION.md:183` states the arithmetic explicitly: *"**K-19** added the two consent event
  logs, taking the CRM set from four to six (**K-8** says *six*, and the CRM spec's own RLS delta lists six
  deny-all rows)."*

**So the "four to six" is the CRM *table-inventory* count going from four tables to six with the two `_event`
logs added. It was silently relabelled as the `D-3` cascade sign-off scope.** Two of the six carry no cascade
at all: `kernel.org_customer_key` has **no `auth.users` FK** (PK `org_id`), and `venue.export_job.requested_by`
carries **`ON DELETE RESTRICT`** — the opposite of the exception. **This is why the owner brief's option [2]
(*"acknowledge with the widened six-relation scope re-signed"*) was withdrawn as unsignable, and this section
is the proof of why.**

## 4.2 Scope set 1 — the `DELETE` exception (`ODR-4a`)

**Two relations. Enumerated:**

| Relation | Deleted by | Package | Citation |
|---|---|---|---|
| `kernel.identity_demographic` | `kernel.clear_my_demographics()` | `077` | RPC §0.5:168 · RPC §17.20:3233 · DEMOG §10.2:1016 |
| `venue.guest_entry` | `venue.remove_guest_entry(...)` | `086` | RPC §20.5.5:5053, :5066 |

**This is a different set from §4.3's, and the overlap is exactly one relation.** Stated as sets:

```
DELETE-exception scope  = { kernel.identity_demographic , venue.guest_entry }
CASCADE-exception scope = { kernel.identity_demographic , kernel.identity_contact_pref ,
                            kernel.identity_contact_pref_event , kernel.org_contact_consent ,
                            kernel.org_contact_consent_event }
intersection            = { kernel.identity_demographic }
DELETE-only             = { venue.guest_entry }
CASCADE-only            = { identity_contact_pref , identity_contact_pref_event ,
                            org_contact_consent , org_contact_consent_event }
```

**`VERIFIED`:** `venue.guest_entry` carries **no `auth.users` FK at all** — its FK is
`guest_list_id → venue.guest_list on delete cascade` (schema §3.10:3082) — so it can never be in the CASCADE
set, and the four contact/consent relations host no definer `DELETE`, so they can never be in the DELETE set.
**A single count can therefore never describe both, which is the structural reason `ODR-4` was misframed and
why `4d`'s correction is a pair of enumerations rather than a better number.**

## 4.3 Scope set 2 — the `ON DELETE CASCADE` exception (`ODR-4b`)

**Five relations. Enumerated. Not four, and not six.**

| # | Relation | Column | Referential action | Package | Citation |
|---|---|---|---|---|---|
| 1 | `kernel.identity_demographic` | `identity_id` (PK) | `auth.users(id)` CASCADE | `077` | DEMOG §10.2:1009 · §5.1:84 |
| 2 | `kernel.identity_contact_pref` | `identity_id` (PK) | `auth.users(id)` CASCADE | `077` | CRM §11.2:1759 |
| 3 | `kernel.identity_contact_pref_event` | `identity_id` | `auth.users(id)` CASCADE | `077` | schema §1.15.1:1800, :1806 |
| 4 | `kernel.org_contact_consent` | `identity_id` (PK part) | `auth.users(id)` CASCADE | `082` | CRM §11.2:1767 |
| 5 | `kernel.org_contact_consent_event` | `identity_id` | `auth.users(id)` CASCADE | `082` | schema §1.15.2:1854, :1866 |

**How the three live numbers arise (`INFERENCE`, from the verified citations above):**

- **Two** — the original `D-3` as CRM §11.2 filed it: *"`ON DELETE CASCADE` from `auth.users` on the two
  contact tables"* (`PHASE_2_CRM_EXPORT_SPEC.md:1810`). Rows 2 and 4.
- **Four** — `D-3` plus the two `_event` ledgers that mechanically inherit it (`K-2`). Rows 2, 3, 4, 5. This
  is the true "four to six" delta's *lower* term, and it is correct.
- **Five** — the scope `ODR-4b` actually covers, because the register's own question includes the demographic
  table: *"the demographic **and** contact/consent relations carry `ON DELETE CASCADE` from `auth.users`"*
  (`PHASE_2_OWNER_DECISION_REGISTER.md:666–668`). Rows 1–5. **The demographic table's cascade is filed
  separately as DEMOG `D-9` and RLS `MD-9`, which is why it never entered `D-3`'s arithmetic.**
- **Six** — §4.1. Not a cascade scope at all.

**`VERIFIED` — the house-pattern claim that justifies the exception holds.** The corpus's `VERIFIED:` badge
on *"cascade-from-`auth.users` is already the house pattern (012/023/033)"* was re-checked against the applied
migrations at `c0d442f`: `012_*.sql:16` and `:79`, `0230_user_reports_and_blocks.sql:29`, `:76`, `:77`, and
`033_marketplace_expansion.sql:103` all carry `REFERENCES auth.users(id) ON DELETE CASCADE`. Note the file is
`0230_`, not `023_` — the corpus's citation is to the migration *number as spoken*, and a reader globbing
`023_*` finds nothing.

## 4.4 Every document site carrying the unsupported count

**Five sites. Enumerated. None is edited by this document.**

| # | File | Line | Text carrying the count | What it should say |
|---|---|---|---|---|
| 1 | `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` | **1900** | *"**`D-3` scope note — NOT a new decision, but D-3 is now SIX relations, not four.**"* | `D-3` proper is **four** (§4.3 rows 2–5); the decision `ODR-4b` puts to the owner is **five** (rows 1–5). Enumerate, do not count. |
| 2 | `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` | **1908** | *"The outstanding sign-off D-3 already requires from the schema and RLS spec owners now covers six relations rather than four."* | as above |
| 3 | `docs/architecture/PHASE_2_PACKAGE_REGISTRY.md` | **794** (`§7.1 OWNER-DECISION-K2-D3`) | *"**`D-3`'s outstanding sign-off now covers SIX relations, not four.**"* … *"silently widening its scope from four relations to six is exactly the shape of change rule §6.5 exists to stop"* | The observation about §6.5 is right; the number it is attached to is wrong. Replace with §4.3's enumeration. |
| 4 | `docs/architecture/_governance/PHASE_2_OWNER_DECISION_REGISTER.md` | **686** | quotes site 3 verbatim under `ODR-4`'s *"Scope has changed since the sign-off was first requested"* | inherits the correction |
| 5 | `docs/architecture/_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` | **281** and **284** | *"the sign-off scope **widened from four relations to six** without being re-taken"* · option *"acknowledge with the widened six-relation scope explicitly re-signed"* | Option [2] is **WITHDRAWN — unsignable** (§4.1). The line stating the widening inherits the correction. |

**One further site is correct and must NOT be swept up in the correction (`VERIFIED`):**
`PHASE_2_RLS_PERMISSION_SPEC.md:3115` and `:3377` say *"six relations"* about the **zero-policy /
`_sel_svc_export`** set, which genuinely is six and is enumerated in place. Likewise
`PHASE_2_SPEC_FOUNDATION.md:183`, whose six is the CRM table inventory and is explicitly reconciled there.
**A find-and-replace on the string "six relations" would break two correct statements.**

---

# 5. Option 5 — the package move. The five-limb proof.

**Ruling: accepted in principle, *provided the dependency proof remains valid*. This section is that proof.
The move is NOT performed.**

## 5.0 Every object that would move, with its target and its SEAM-1 `max()`

**Eleven objects, plus the doc-level artifacts. Enumerated.** *(Object counts below are each followed by
their enumeration, per the standing rule.)*

**What is NOT in this list, because it is already at `086` (`VERIFIED`, and this is the load-bearing fact of
the whole proof):** `venue.holder_mix_snapshot`, `venue.holder_mix_bucket`, `venue.refresh_holder_mix` and
`venue.get_holder_mix` were **already moved from `087` to `086`** by ratified placement ruling
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.5-A (`:4193–4200`), and the registry (`§2:402`, JSON `:661`)
and the migration plan (`§8/086` Tables `:1428`, Functions `:1429`, RLS `:1430`, Indexes `:1432`) all agree.
**`PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §10.1:964–976 still says `087` for all four and is stale.**

| # | Object | Kind | Today | Target | SEAM-1 `max()` | Citation |
|---|---|---|---|---|---|---|
| 1 | `kernel.identity_demographic` | table | `077` | **`086`** | `max(076) = 076`; **bounded above by its reader** `venue.refresh_holder_mix` at `086` → placed at `086` | DEMOG §10.1:964 · plan §8/077:1281 |
| 2 | `kernel.identity_demographic_erasure` | table (AO) | `077` | **`086`** | `max(076) = 076` — **no FK at all**; travels with the trigger that writes it | DEMOG §10.1:965 · §10.2:1024 |
| 3 | erasure-tombstone `BEFORE DELETE FOR EACH ROW` trigger on `kernel.identity_demographic` | trigger + its trigger function | `077` **as specified** / **absent from the plan and registry** (§1.5 Defect 2) | **`086`** | `max(086 [tbl 1], 086 [tbl 2]) = 086` | DEMOG §10.1:966 · §8.2:776 |
| 4 | `kernel.raise_append_only` trigger on `kernel.identity_demographic_erasure` | trigger attachment | `077` | **`086`** | `max(076 [fn], 086 [tbl 2]) = 086` | plan §8/077 Triggers:1284 |
| 5 | `kernel.set_updated_at` trigger on `kernel.identity_demographic` | trigger attachment | `077` | **`086`** | `max(076 [fn], 086 [tbl 1]) = 086` | plan §8/077 Triggers:1284 |
| 6 | `kernel.get_my_demographics()` | RPC (definer, arity 0) | `077` | **`086`** | `max(086) = 086` | plan §8/077 Functions:1282 · RPC §17.20:3200 |
| 7 | `kernel.set_my_demographics(...)` | RPC (definer) | `077` | **`086`** | `max(086) = 086` | plan §8/077 Functions:1282 |
| 8 | `kernel.clear_my_demographics()` | RPC (definer) | `077` | **`086`** | `max(086 [tbl 1], 086 [trigger 3 → tbl 2]) = 086` | plan §8/077 Functions:1282 |
| 9 | `REVOKE ALL ON kernel.identity_demographic FROM PUBLIC, anon, authenticated` | grant | `077` | **`086`** | SEAM-4: `max(086 [relation], 076 [grantee]) = 086` | DEMOG §10.3:1068 · plan §8/077 Grants:1286 |
| 10 | `REVOKE ALL ON kernel.identity_demographic_erasure FROM PUBLIC, anon, authenticated` | grant | `077` | **`086`** | SEAM-4: `max(086, 076) = 086` | DEMOG §10.3:1070 |
| 11 | `ENABLE ROW LEVEL SECURITY` on both, with **zero** policies | RLS posture | `077` | **`086`** | SEAM-3: `max()` over tables read + functions the predicate calls — **there is no predicate**, so `max(086) = 086` | DEMOG §10.3 · plan §8/077 RLS:1283 |

**Indexes: none move, because none exist.** **`VERIFIED`** — plan §8/`077`'s Indexes row (`:1285`) names
`org_member`, `organization`, `org_invite`, `admin_audit`, `approval_request` and
`identity_contact_pref_event(identity_id, occurred_at DESC)`. **No demographic index is scheduled anywhere**,
including the `(purge_after)` index the tombstone reaper would need (§6.E).

**Seeds: none move — and the one that exists is scheduled nowhere.** **`VERIFIED`** — the demographic kill
switch `catalog.platform_config['demographics.holder_mix_enabled']` is assigned to `087` by DEMOG §10.1:974,
and ratified placement ruling schema §13.5-D consolidates **all** `platform_config` seeds into `078`
(`:4225–4232`, `:3922`). **But `grep` for `demographics.` across `PHASE_2_SUPABASE_MIGRATION_PLAN.md` and
`PHASE_2_PACKAGE_REGISTRY.md` returns ZERO hits** — plan §8/`078`'s Feature-flags row (`:1303`) enumerates
`feature.*` ×3, `door.*` ×4, wallet/credential ×6, money ×15, `comp.*` ×2, `notify.*` ×5 and the CRM
limits/caps/retention keys, and **no `demographics.*` key**; `086`'s row (`:1434`) names only
`feature.native_scanning_enabled`; `087`'s (`:1457`) names none. **The kill switch that `venue.get_holder_mix`
reads live on every call (RPC §17.20:3300–3303) is seeded by no package.** It is not in `077`, so it does not
move — but the move is the moment this becomes visible, and it is listed in §5.6 as a prerequisite.

**Tests that move with the objects (`VERIFIED`, from plan §8/`077`'s Tests row, `:1290`):** the clause
*"Demographic tables: grant set is **empty** (not reduced); `get_my_demographics` has arity 0;
`set_my_demographics` writes no value into any audit row."* Plus the demographics-spec pgTAP assertions that
bind these objects: **1, 2, 3, 4, 5, 25, 27, 29, 30, 31** — ten, enumerated (DEMOG §13:1290–1310). Plus
`T-RPC-DEMO-01` (writer-set closure). **And a gap the move surfaces (`VERIFIED`): `T-RPC-DEMO-03`, `-04` and
`-05` are defined in RPC §18:3860 and scheduled by no matrix row** — the traceability matrix schedules only
`-01`/`-02` (`:868`, `:499`). Three defined, unscheduled tests moving with objects whose package is being
changed is the moment to schedule them.

**Objects that would NOT move and are affected anyway — enumerated, three:**

| Object | Effect |
|---|---|
| The RN *"About you (optional)"* card + screen + remove control | **`VERIFIED`** gated on `077` (DEMOG §10.1:982). Re-gates to `086` — **nine packages later** |
| `venue.reconcile_holder_mix()` | **UNSCHEDULED — package UNKNOWN.** Contracted at RPC §17.20:3305 and §19 item 4:3955, granted `DEF`/`pg_cron` at RLS §11:2311, assigned `087` by DEMOG §10.1:975 — and named in **no** package's Functions row in plan §8. **`R-7` (RPC §20.14:6629) ordered it scheduled and the order is unapplied for this function** |
| `venue.unpublish_holder_mix()` · `venue.unpublish_all_holder_mix()` | **UNSCHEDULED — package UNKNOWN.** Same shape: contracted RPC §17.20:3264, assigned `087` by DEMOG §10.1:973, named in no Functions row. `R-7` explicitly says *"**Also `unpublish_holder_mix` / `unpublish_all_holder_mix`** in the demographics package"* — unapplied |

## 5.1 Limb 1 — no forward reference. **PASSES for `086`. FAILS for `087`.**

**Method (`VERIFIED`).** SEAM-1 as corrected by `R2B` (registry §2.2:479–486): *"a function is authored in the
package equal to `max()` of the packages creating every table it reads, every table it writes, **and every
table it reaches through a call**"*, re-derived from each routine's **contract** — Reads, Writes,
Preconditions, and every routine named in its prose — *"never inherited from where the object list already
sits."*

**The complete reader set of `kernel.identity_demographic` is closed and asserted.** DEMOG assertion 27
(`:1298–1304`), **`VERIFIED`**: the set of functions, views and matviews whose definition references it,
**plus every function attached to it as a trigger**, is exactly

`{get_my_demographics, set_my_demographics, clear_my_demographics, refresh_holder_mix, <the updated_at
maintainer>, <the erasure-tombstone writer>}` — **six**, enumerated.

| Reader | Package after the move to `086` | Forward reference? |
|---|---|---|
| `kernel.get_my_demographics` | `086` (moves) | no |
| `kernel.set_my_demographics` | `086` (moves) | no |
| `kernel.clear_my_demographics` | `086` (moves) | no |
| **`venue.refresh_holder_mix`** | **`086`** (already there — plan §8/086 Functions:1429) | **no — same package** |
| `kernel.set_updated_at` | `076` (shared helper, plan §8:487–490) | no — it is called *by* the trigger, and `076 < 086` |
| erasure-tombstone writer | `086` (moves) | no |

Readers of `kernel.identity_demographic_erasure`: **none.** *(It is definer-only, written by one trigger and
read by nothing — because the reaper that would read it does not exist, §6.E.)*

**Preconditions and calls, checked (`VERIFIED`, RPC §17.20:3200–3245).** `get_my_demographics` is arity 0 and
reads one table. `set_my_demographics` writes one table, **writes no audit row of any kind** (`AUTHZ-DEM1`(1),
`J-11`), and calls nothing. `clear_my_demographics` deletes one row, **writes no audit row**, and calls
nothing — the tombstone is written by the trigger, not by it. **No demographic RPC calls any other routine,
reads any other relation, or names any routine in its prose.** That is unusually clean and it is what makes
this limb decidable at all.

### Why `087` fails

**`VERIFIED`, and it is the decisive result of this whole section.** `venue.refresh_holder_mix` is authored
in **`086`** (plan §8/`086` Functions row, `PHASE_2_SUPABASE_MIGRATION_PLAN.md:1429`, final clause:
*"`venue.refresh_holder_mix`, `venue.get_holder_mix`"*), and it **reads `kernel.identity_demographic`** (its
declared read set, RPC §17.20:3242–3245).

Place `kernel.identity_demographic` in `087` and one of two things must happen:

1. **`refresh_holder_mix` stays at `086` and forward-references `087`** — `42P01` at first cron tick, replay
   green (`plpgsql` bodies are not validated at `CREATE FUNCTION`). **This is exactly the `K-2`/`R2B` defect
   class the corpus has now repaired four times.** Inadmissible.
2. **SEAM-1 re-derives `refresh_holder_mix` to `max(078, 079, 082, 087) = 087` and it moves too** — dragging
   `get_holder_mix`, and with them the two `holder_mix` tables, **back to `087`**, which **reverses ratified
   placement ruling §13.5-A** and reintroduces the edge that ruling was made to avoid (see limb 5).

A SEAM-2 hook is the third theoretical repair and is inadmissible here for the reason §13.5-A already gives
for the sibling case: there is **no correct neutral result** for "read this session's demographic answers" —
a stub returning zero rows makes every session look unanswered and the suppression floor silently swallows
it, which is precisely the *"reads as 'nobody consented'"* failure shape the corpus has ruled against twice
(RLS §16.10, CRM `K-2`).

**`086` is therefore not one of two acceptable targets. It is the only one.** The owner's *"`086`/`087`
boundary"* resolves to **`086`**, and the proof is what resolves it.

## 5.2 Limb 2 — no broken FK. **PASSES.**

**Every FK on every moving object, enumerated (`VERIFIED`):**

| Object | FK | Target | Target's package | Precedes `086`? |
|---|---|---|---|---|
| `kernel.identity_demographic.identity_id` | `→ auth.users(id)` CASCADE | `auth.users` | **precondition relation, not a Phase-2 package** | n/a — always satisfied |
| `kernel.identity_demographic_erasure.identity_id` | **NONE — bare uuid, deliberately** | — | — | n/a |

**That is the entire FK surface: one FK, to a precondition relation, plus one deliberate non-FK.** The corpus
has already made this exact argument for the sibling table — schema §1.15.1:1839–1841, **`VERIFIED`**:
*"**No dependency edge is created:** this table's only FK is to `auth.users`, which is a precondition
relation, not a Phase-2 package (§0.1 — the frozen core references nothing upward)."*

Nothing FKs *into* either table (**`VERIFIED`** — `grep` for `identity_demographic` across the schema spec,
plan and registry returns no inbound FK; assertion 28 independently asserts the holder-mix tables carry no FK
to any identity-bearing table).

## 5.3 Limb 3 — no broken RPC. **PASSES.**

**Callers of the three moving RPCs, enumerated (`VERIFIED`):**

| RPC | Callers |
|---|---|
| `kernel.get_my_demographics()` | The RN client, over PostgREST. **No database routine calls it.** |
| `kernel.set_my_demographics(...)` | The RN client. **No database routine calls it.** |
| `kernel.clear_my_demographics()` | The RN client. **No database routine calls it.** |

**Callees of the three, enumerated: none.** Each reads/writes exactly one table and calls no routine
(§5.1). `clear_my_demographics` reaches `kernel.identity_demographic_erasure` **only through the trigger**,
which moves with it.

**`FR-9` covers the client caller (`VERIFIED`, registry §2.1 `R2B`-5 rationale):** *"`FR-9` already rules an
edge-function caller is not a DDL forward reference."* **`INFERENCE`:** a PostgREST client caller is the same
class — it is not a DDL dependency and does not enter SEAM-1's `max()`. The RN surface's gate changes from
`077` to `086`; that is a product consequence (§5.6), not a broken RPC.

**Every caller and callee still resolves in order.** Nothing in packages `077`–`085` names any demographic
object — **`VERIFIED`** by `grep` for `get_my_demographics` across `PHASE_2_SUPABASE_MIGRATION_PLAN.md`,
which returns exactly **two** hits, both in `077`'s own rows (`:1282` Functions, `:1290` Tests), and **zero**
in `078`–`085`.

## 5.4 Limb 4 — no RLS dependency violation. **PASSES, trivially and provably.**

**`VERIFIED`.** Both moving tables carry **`ENABLE ROW LEVEL SECURITY` with zero policies and an EMPTY grant
set** — DEMOG §10.3:1068–1080: *"RLS itself: `ENABLE ROW LEVEL SECURITY` on all four, **with no policy
admitting `anon` or `authenticated`** … the grant set is EMPTY, not reduced"*, and *"RLS policies are
therefore not the enforcement here — **the absence of a grant is**."*

Independently corroborated by the RLS spec's own register — `PHASE_2_RLS_PERMISSION_SPEC.md:3089–3098`,
**`VERIFIED`**: *"**Objects with ZERO policies, by design (RLS enabled, `REVOKE ALL`)**"* names
`kernel.identity_demographic` and `kernel.identity_demographic_erasure` in its enumeration, and DEMOG §10.3
adds the reason the absence is the enforcement: *"RLS policies are therefore not the enforcement here — **the
absence of a grant is**."*

**SEAM-3** (registry §2.2:498–505) places a policy at `max()` of the tables it reads and **every function its
predicate calls**. **There is no policy, therefore no predicate, therefore no helper function.** The limb is
satisfied by construction — and it is the only one of the five that cannot be broken by a future edit to the
moving objects, because breaking it would require adding a policy to a table the corpus has registered as
permanently policy-free.

**One adjacent risk, checked and cleared (`VERIFIED`).** The `crm_export_builder` `_sel_svc_export` policy
family would have been the one way an RLS predicate reached these tables. It does not: RLS §16.10 clause 1
closes the set at twelve relations and states *"**No demographic relation appears, and none may be added** —
that is the property `T-RPC-CRM-06`'s reader enumeration asserts."* And under **`O17`/`MD-2`/`ODR-23` = OWNER
RULING B** (2026-08-28) the role is **not created at all** and **zero `_sel_svc_export` policies exist**
(`_governance/O17_RULING_IMPACT_MAP.md:14–18`). Plan §8/`077`'s Grants row confirms the four
`crm_export_builder` grants owed from `077` are on `identity_ext`, `identity_contact_pref`,
`identity_contact_pref_event` and `org_customer_key` — **no demographic table** (`:1286`).

## 5.5 Limb 5 — no package DAG cycle. **PASSES for `086`, with zero edge change. FAILS for `087`.**

### The edge set BEFORE — 45 edges, enumerated, four-surface parity verified mechanically

**`VERIFIED` by a parser I ran over the four declared surfaces at `c0d442f`**, not by reading them:

| Surface | Edges parsed |
|---|---|
| `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §2 mermaid DAG | **45** |
| `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §3 rollout table, *Depends on* column | **45** |
| `PHASE_2_PACKAGE_REGISTRY.md` §2.1 table | **45** |
| `PHASE_2_PACKAGE_REGISTRY.md` §3 JSON `depends_on` | **45** |

**All four sets are IDENTICAL — set equality holds pairwise across all four, zero symmetric difference.**
This is the second acceptance property of registry §2.2 (*"the four declared edge sets are identical … not
merely compatible"*), re-verified independently here.

The 45 edges, enumerated by dependent:

```
077 ← {076}                                              (1)
078 ← {077}                                              (1)
079 ← {077,078}                                          (2)
080 ← {077,078,079}                                      (3)
081 ← {078,080}                                          (2)
082 ← {077,078,081}                                      (3)
083 ← {078,079,081}                                      (3)
084 ← {079,081,083}                                      (3)
085 ← {077,078,079,081,082,083}                          (6)
086 ← {079,080,081,083}                                  (4)
087 ← {077,081,085,086}                                  (4)
088 ← {078,079,081,085,086,087}                          (6)
089 ← {085,088}                                          (2)
090 ← {078,082,085,087}                                  (4)
091 ← {077}                                              (1)
                                                  total = 45
```

### The edge set AFTER the move to `086` — 45 edges, unchanged

**`INFERENCE`, from limbs 2–4 above.** The moving objects introduce **no cross-package reference of any
kind**: one FK to a precondition relation (limb 2), no inbound FK, no routine caller or callee outside the
moving set (limb 3), no RLS predicate (limb 4), and two shared trigger functions in `076` which every package
reaches transitively (registry `R2B`-9: *"every package reaches `076` transitively and the corpus does not
declare transitive edges"*).

**Edge count `45 → 45`. No edge added, none removed, none reversed. No package added, renamed or renumbered;
the band stays `076`–`091`, sixteen, each number used once. The DAG remains acyclic and topologically ordered
by package number** — every dependency continues to strictly precede its dependent, because no dependency
changed.

**One check that could have gone the other way and does not (`VERIFIED`):** `086`'s declared set is
`{079, 080, 081, 083}` and does **not** include `077`. Had any moving object needed a `077` relation, the move
would have required a new `086 → 077`… which is not even expressible, since `077 < 086` — the edge would be
`077 → 086`, and it is reached transitively via `079 ← 077`. It is moot: **no moving object references a `077`
relation.** The `kernel` schema itself and both shared trigger functions are `076`.

### `087` on this limb — and a correction to the ratified argument against it

The ratified argument that placed the holder-mix objects at `086` is
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` §13.5-A:4196–4199, **`VERIFIED`**:

> The objective argument: `venue.refresh_holder_mix` reads **`kernel.tickets` (`079`)**, and **`087`'s
> declared dependency set is `077`/`081`/`085` — it does not depend on `079`.** Placing the rollup in `087`
> therefore *adds* a `079 → 087` edge. `086` already depends on `079`, `080` and `081` — every input the
> rollup has. **`086` is the placement that requires no DAG change at all.**

**That argument's premise has since gone stale, and this document will not repeat a bare claim past its
premise.** **`VERIFIED`:** `087`'s declared set is now `{077, 081, 085, 086}` — the third amendment added
**`086 → 087`** (registry §2.1 seq 12, `†`) — and `086` declares `079`. Registry `R2B`-9 states the corpus's
own rule on transitive reach: *"**No edge** (every package reaches `076` transitively and the corpus does not
declare transitive edges)."* **So a `079 → 087` edge would not, today, be required.** §13.5-A's *objective*
argument is therefore no longer objective; what survives of it is the *subject-matter* argument (*"`087` is
the **settlement** package … a privacy-gated audience-composition projection has no relationship to it"*),
which is a judgement, not a mechanism.

**Limb 5 for `087` is therefore ARGUABLE, not failed — and it does not matter, because limb 1 fails
decisively and independently.** Stated precisely, so no one repairs the wrong thing:

| Question | Answer |
|---|---|
| Does a move to `087` add a declared edge? | **No, on today's edge set** — `087 → 086 → 079` reaches `079` transitively, and the corpus does not declare transitive edges. **The ratified §13.5-A sentence saying otherwise is stale.** |
| Does a move to `087` therefore work? | **No.** Limb 1: `venue.refresh_holder_mix` is authored in `086` and reads the table. Either it forward-references `087` (`42P01`, green replay) or SEAM-1 drags it, `get_holder_mix` and both `holder_mix` tables to `087` with it. |
| What does dragging them cost? | **Reversal of ratified placement ruling §13.5-A**, which is a registry amendment under rule §6.5 — not a scheduling action, and far more than Option 5 asked for. |

**Filed as a separate observation for the schema-spec owner: §13.5-A's objective argument should be restated,
because its factual premise (`087` does not depend on `079`) was made true by the absence of an edge the
third amendment has since added.** Not corrected here. **The ruling it supports is unaffected** — `086`
remains right, on the subject-matter argument and on limb 1.

## 5.6 Verdict, and what the move actually costs

**PROVEN, for target `086`, on all five limbs.** **DISPROVEN, for target `087`, on limbs 1 and 5.**

| Limb | `086` | `087` |
|---|---|---|
| 1 — no forward reference | **PASS** | **FAIL** — `refresh_holder_mix` (`086`) reads the table |
| 2 — no broken FK | **PASS** | pass |
| 3 — no broken RPC | **PASS** | pass, only after dragging two functions and two tables |
| 4 — no RLS dependency violation | **PASS** | pass |
| 5 — no DAG cycle / edge change | **PASS**, 45 → 45, all four surfaces re-verified | **ARGUABLE** — no edge is added on today's set; but it reverses ratified §13.5-A, a §6.5 amendment |

### Four consequences the move creates, which the ruling should be taken with open eyes about

1. **The accumulation window collapses from nine packages to zero (`INFERENCE`, and this is the real cost).**
   Schema §13.5-E accepted the `077` placement *for a stated reason* — **`VERIFIED`**, `:4245–4249`:
   *"demographics fan-side → `077` (correct — keyed by `auth.users`, no other dependency, and **it unblocks
   the RN surface at the earliest point so answers accumulate before any venue can read a threshold-clearing
   aggregate**)."* At `086` the capture surface and the rollup ship in the **same package**. The first
   `refresh_holder_mix` tick therefore runs against a near-empty response population, every session fails the
   `holders_responded >= 25` floor (R1) and the `min(holder_count) >= 5` floor (R2), and every card returns
   `{ suppressed: true }`. **That fails closed and is safe — and it means the feature ships visibly broken to
   every venue on day one.** Option 5 is a scheduling decision that silently reverses a ratified
   product-sequencing decision, and no document currently says so.
2. **The RN surface re-gates from `077` to `086`** (DEMOG §10.1:982) — nine packages later, behind the door
   gate.
3. **The `HG-8` hard gate leaves `077`** (`PHASE_2_SCOPE_AMENDMENT_2026_08.md:352`), which is the point of
   Option 5. **But it does not disappear — it re-attaches to `086`.** And `4a`/`4b` are still owed, exactly as
   the owner's ruling says: the move removes the deadline, not the decision.
4. **`086` becomes the package that contains `kernel.*` identity tables.** The registry's own rule against
   overloading an unrelated package (invoked in §13.5-A against `087`) applies here in reverse and should be
   answered in the amendment rather than left for a reviewer to notice. **`INFERENCE`:** the answer available
   is the one §13.5-A already gives — *"`086` is already the venue's per-session audience package
   (`guest_list`, `guest_entry` and `comp_allocation` are not scan objects either)"* — and a demographic
   answer is an audience fact. It is a defensible answer; it is not currently written down for these objects.

### What must be true before the move can be executed

1. **Defect 2 of §1.5 is repaired first.** Moving an object list that is already inconsistent across four
   documents moves the inconsistency and makes it harder to see. The `BEFORE DELETE` trigger must exist in
   the plan, the registry and the schema spec **before** any of them is re-pointed at `086`.
2. **The demographic tables gain physical definitions in the schema spec.** **`VERIFIED` — it defines none of
   the four.** The kernel sections run §1.1–§1.16 and the venue sections §3.1–§3.18, and there is no section
   for `kernel.identity_demographic`, `kernel.identity_demographic_erasure`, `venue.holder_mix_snapshot` or
   `venue.holder_mix_bucket`. The file's only demographic occurrences are placement/ruling rows at `:3913`,
   `:3944` and `:4193`. **The contrast is instructive: the sibling `K-2` tables were given full physical
   definitions in the same pass (§1.15 at `:1754`, §3.18 at `:3231`) precisely because a table asserted by
   four documents and defined by none is the defect `K-2` was.** A move re-writes placement rows; a table with
   no definition has nothing for the move to be made consistent with.
3. **The stale `087` assignments for the holder-mix half are corrected to `086` first.** **Three documents
   still say `087` (`VERIFIED`, enumerated):** `PHASE_2_SPEC_FOUNDATION.md:162` and `:163` (*"Pkg `087`"* for
   `holder_mix_snapshot` and `holder_mix_bucket` — **and §6 is the canonical table inventory**);
   `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md:972–976` (all four objects, plus §10.1:986–995's *"Why package 087
   and not 086"* rationale, still live); `PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md:700`. **Four documents say
   `086`:** registry §2:402 and JSON `:661`, plan §8:1428/:1429, schema §13.5-A:4193 and the placement record
   `:3944` (marked `▲ spec said 087`), scope amendment `:115`/`:164`, matrix `:500`. **A move executed while
   the canonical inventory disagrees will produce a fifth version of the placement, not a correction.**
4. **The three unscheduled functions are scheduled or ruled out** — `venue.reconcile_holder_mix`,
   `venue.unpublish_holder_mix`, `venue.unpublish_all_holder_mix` (§5.0). `R-7` ordered it; it is unapplied.
   **A function with no package is a function nobody builds**, and the move is the moment it would be noticed.
5. **The kill-switch seed is scheduled** — `demographics.holder_mix_enabled` appears in no package's seed row
   anywhere (§5.0). `venue.get_holder_mix` reads it **live on every call** and DEMOG §5.5 makes it the
   feature's only runtime control. Unseeded, the read resolves to a missing key on the one control that can
   stop the feature without a deploy.
6. **All four declared edge surfaces are re-parity-checked after the amendment**, even though the expected
   result is 45 = 45. The check is cheap and the corpus has been bitten six times by an under-declared edge —
   **and `086`'s own Dependencies prose already carries a seventh instance, unremarked: plan §8/`086`:1437
   names `078` while all four declared sets say `{079, 080, 081, 083}`** (**`VERIFIED`**). It is
   declaration-only (`078 < 086`) and pre-existing, but the parity check after this amendment is where it
   should be closed rather than carried forward.

---

# 6. The standing blockers, mapped to the objects they block

The owner kept six open. Each is stated here with what it blocks, so no affected object ships while its
blocker stands.

| | Blocker | Status | Blocks shipping |
|---|---|---|---|
| **A** | **Cascade blocked by append-only row triggers.** `kernel.identity_contact_pref_event` (`077`) and `kernel.org_contact_consent_event` (`082`) carry `raise_append_only()` **and** `identity_id → auth.users ON DELETE CASCADE` in the same subsection. A referential cascade fires row triggers. **`VERIFIED`** schema §1.15.1:1800/:1811, §1.15.2:1854/:1869 · plan §8:489 | **OPEN** | **Both `_event` ledgers, and with them the `4b` CASCADE exception on all five relations of §4.3** — `auth.admin.deleteUser()` aborts for any identity with an event row, and `set_my_contact_prefs` *"appends one row … that append is the function's contract"* (plan §8/077:1282), so that is every fan who touched the switch |
| **B** | **Missing `BEFORE DELETE` tombstone trigger.** Four documents; two say two triggers, two say one-or-none. **`VERIFIED`** DEMOG §8.2:776–790 and assertion 25:1348 vs plan §8/077 Triggers:1284 vs registry `:393`/`:652` vs schema `:3913`. **The trigger function is also unnamed everywhere** — the corpus refers to it only as *"`<the erasure-tombstone writer>`"* (DEMOG §13 assertion 27:1301), so there is no identifier for a `pg_trigger` assertion to bind to | **OPEN** | **`kernel.identity_demographic`, `kernel.identity_demographic_erasure`, `kernel.clear_my_demographics` — i.e. every object `4a` ratifies.** Built as the plan is written, no removal path writes any tombstone, and it fails silently |
| **C** | **Tombstone UPSERT incompatible with its AO/PK design.** *"upserts"* into an AO table with `raise_append_only`, and the PK is declared two incompatible ways. **`VERIFIED`** DEMOG §8.2:777, §10.2:1024/:1028 vs SPEC_FOUNDATION §6:125 | **OPEN** | **`kernel.identity_demographic_erasure` and the second withdrawal by any identity.** Under `ON CONFLICT DO UPDATE` the RPC refuses to withdraw; under `DO NOTHING` `purge_after` never advances |
| **D** | **Unresolved tombstone retention window.** `purge_after` is `timestamptz NOT NULL` = `erased_at + {N} + margin`, and `{N}` is open decision **`D-6`** / `ODR-67`. **`VERIFIED`** DEMOG §10.2:1030, §14 `D-6`:1426, §8.5:885 · register `ODR-67`:1997 | **OPEN — no default; register records `Recommendation: None`** | **`kernel.identity_demographic_erasure` cannot be authored at all** — a `NOT NULL` column whose value is an undecided constant has no expression. **And the fan-facing §8.5 copy cannot ship** with a placeholder |
| **E** | **No tombstone reaper.** **`VERIFIED`** — no purge job, cron entry, function or index for `purge_after` exists in any of the sixteen packages. Plan §8 has `Scheduled ticks` rows only at `079`, `081`, `087`, `088`, none touching this table; `077` has no such row; no `(purge_after)` index is scheduled | **OPEN** | **The self-purge, which is one of exactly three mitigations §8.5 offers for the tombstone's acknowledged privacy cost** (definer-only · value-free · purged at `purge_after`). **One of the three has no writer, so as specified the tombstone is permanent.** **`INFERENCE`: when the reaper is built it will be a `DELETE` in a `postgres`-owned definer — a THIRD member of the `4a` class.** It must be added by amendment, and `T-SCHEMA-GP2-02` will fail loudly the day it appears un-ratified, which is the correct behaviour |
| **F** | **Non-transactional / half-completing account deletion.** **`VERIFIED`, read in full at `c0d442f`** — `supabase/functions/delete-account/index.ts` has **no `BEGIN`/`COMMIT` and no transactional wrapper anywhere**. Four mutation stages, in order: cleanup RPC (`:171`, commits) → bids delete (`:185`, **its error is not even destructured**) → storage ×2 (`:192`, `:204`, both `try/catch`, non-fatal) → `auth.admin.deleteUser` (`:219`). Only the last fires any cascade (`:217–218`, *"CASCADE handles: profiles, push_tokens, notification_preferences"*). On failure of the last: `500` *"contact support"* and stop (`:223`) | **OPEN** | **Every erasure guarantee that depends on the cascade — the `4b` exception's entire value.** If `deleteUser` fails: financial rows anonymized, bids gone, avatars gone, account still live, no retry, no reconciliation, no tombstone, **and nothing anywhere queries for "cleanup ran but the user still exists."** From `079` this worsens: every identity column is `ON DELETE RESTRICT`, so the final call raises `23503` **after** the cleanup already committed. Deletion does not stop working — **it half-works, irreversibly, on every attempt.** Two further defects visible in the quoted lines: the pending-transfer probe at `:150` does not destructure `error`, so a failed probe yields `data === null` and the **409 guard fails open** (`:157`); and `:153` interpolates `userId` directly into the PostgREST `.or()` filter string |

---

# 7. What could not be verified

1. **No database was contacted.** `rolbypassrls` on `postgres` and `relrowsecurity` on `auth.users` remain
   unchecked. Both are single queries and both are load-bearing for §1.4's ownership predicate.
2. **Whether the pgTAP suites will exist.** DEMOG §13 opens *"described; no SQL files written"*. Every
   assertion this document specifies or cites is prose in a Tests row, including the model
   `T-SCHEMA-SENTINEL-05`, for which **no SQL body exists anywhere in the corpus**.
3. **`venue.export_job.requested_by`'s correct treatment** (§3.2 exclusions). It carries a repoint pressure
   *higher* than the six in scope, and the corpus has no rule for RESTRICT-side identity columns outside
   custody. **Recorded as an open scope question, deliberately not resolved here.**
4. **The regex in §1.4(a) is a specification, not a tested artifact.** It has not been run against a database.
   `DELETE` inside a string literal or a comment would be a false positive; unqualified relation names and
   `EXECUTE format(...)` are false negatives — which is why limb (e) exists.
5. **`DOOR §7.6` is named as a filing site for `O15`/`ODR-16`** (register `:1065`) and a grep of
   `PHASE_2_DOOR_LIFECYCLE_SPEC.md` for `O15`, `ODR-16`, `CUSTODY-DEL-1` and *"account deletion"* returns
   **zero hits**. The filing appears to be a citation *from* schema §5.1, not a record in the door spec.
   Reported, not corrected.
6. **Legal questions** — which regimes apply, and whether gender identity is special-category — are legal, not
   technical, and are untouched.

---

# 8. Provenance

**Files read in full or in the cited ranges (`docs/architecture/**`):** `PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` ·
`PHASE_2_CRM_EXPORT_SPEC.md` · `PHASE_2_RPC_FUNCTION_CONTRACTS.md` · `PHASE_2_RLS_PERMISSION_SPEC.md` ·
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` · `PHASE_2_SUPABASE_MIGRATION_PLAN.md` · `PHASE_2_PACKAGE_REGISTRY.md` ·
`PHASE_2_SPEC_FOUNDATION.md` · `PHASE_2_SCOPE_AMENDMENT_2026_08.md` · `PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md` ·
`PHASE_2_DOOR_LIFECYCLE_SPEC.md` · `PHASE_2_APPLE_WALLET_SPEC.md` · `PHASE_2_EDGE_FUNCTION_SPEC.md` ·
`SNATCH_IT_CANONICAL_DATA_MODEL.md` · `_governance/PHASE_2_OWNER_DECISION_REGISTER.md` ·
`_governance/PHASE_2_RATIFICATION_RECORD.md` · `_governance/ODR4_OWNER_DECISION_ANALYSIS.md` ·
`_governance/PHASE_2_FINAL_OWNER_DECISION_BRIEF.md` · `_governance/O17_RULING_IMPACT_MAP.md` ·
`_governance/X6_POSTGRES_OWNED_ASSURANCE_PLAN.md`.

**Repository artifacts read (not documents):** `supabase/migrations/012_*.sql` · `019_anonymized_sentinel_user.sql`
(45 lines, in full) · `020_delete_account_cleanup_rpc.sql` (in full) · `0230_user_reports_and_blocks.sql` ·
`033_marketplace_expansion.sql` · `supabase/functions/delete-account/index.ts` (235 lines, in full).

**Mechanical checks run at `c0d442f` (results reported inline as `VERIFIED`):**

1. `OFFLINE-VERIFY-v1` fenced-block extraction and hashing over `docs/architecture/**` — 4 blocks, 0 loose,
   0 unterminated, 1 distinct body, 2017 bytes, 34 lines,
   `sha256 afb5184d58b62da5cb03cb8c4c7923953b4206c52f8afa23dee6403069fe6344`.
2. Four-surface dependency-edge parser over the plan's §2 mermaid, the plan's §3 rollout table, registry §2.1
   and registry §3 JSON — **45 edges on each, all four sets identical, zero symmetric difference.**
3. Four-pass `DELETE`-bearing-definer sweep over `docs/architecture/**` (§1.3).
4. `T-SCHEMA-*` family enumeration to establish `T-SCHEMA-GP2` free and `T-SCHEMA-SENTINEL-07` next.

**What this pass changed:** one new file — this one. **No architecture contract, no governance record, no
migration, no test, no CI file, no package registry entry and no production object was edited, created,
moved or contacted.** No owner decision is resolved. No package move is performed. **No `OFFLINE-VERIFY-v1`
fenced block was touched, and the hash above is the evidence.**
