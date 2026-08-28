# Phase 2 — Subject-Matter Owner Map

**CANONICAL. Created 2026-08-28 as the artifact owner ruling `OR-6` (`ODR-7` / `O11`) requires.**

Ratified `C75` recorded that subject-matter ownership was *"correct but requiring an owner map the
corpus does not yet have."* This is that map.

> ## HOW TO USE IT
>
> Under `OR-6`, a disputed architecture statement is resolved by **finding its subject here and
> reading the normative owner**. The owner's statement wins; every derived document must agree.
>
> - **`CORRECTION_FALLBACK = NO`** — the owner covers the subject. A ratified correction row may
>   **not** override it, however new or however tagged. `OR-6` rule 2.
> - **`CORRECTION_FALLBACK = YES`** — the owner is genuinely silent on part of the subject, and only
>   there may a directly applicable ratified correction resolve a conflict.
> - **`AMBIGUOUS`** — no designated owner. Conflicts on this subject **FAIL CLOSED** under rule 4.
>   The implementer does not choose.
> - **Recency is never a resolver.** Not for anything, on any subject. `OR-6` rule 3.
>
> **Ownership is taken from the corpus's own declarations, never inferred** — from edit recency,
> document length, or which document is most convenient. Where no declaration exists, the subject is
> marked `AMBIGUOUS` rather than assigned.

```
TOTAL SUBJECTS : 39
AMBIGUOUS      :  4   (WRITER · PAY-STATE · RESALE-WRITER · EDGE-PKG)
FALLBACK=YES   :  2   (HELPER-SET · OUTBOX)
```

## The four AMBIGUOUS subjects — and why each is not an oversight

**`WRITER` — write authority. THREE candidate owners, all declared, none deferring.**
This is the most consequential entry in the map, and it is the one my two independent reviewers
disagreed about — which is itself the evidence.
1. **RLS claims it in the first person:** *"this table **is** the authority model for every money and
   custody write."*
2. **RLS's own binding-inputs section assigns it to the schema spec:** *"the authoritative table set,
   each table's stated RLS classification, **write authority**, and read authority."*
3. **RLS §11.0 assigns its own EXEC rows to `ROLE_MODEL` §5.3:** *"where the two disagree, §5.3
   governs and §11 is the defect."*
And the content is in dispute: RLS names **four** writers of `kernel.tickets`; RPC contracts **ten**
and says so in capitals. **Both sides carry ratified tags** (`GP-3a` vs `C89`). `OR-6` rule 4 names
this case exactly — *"two same-authority sources conflict … or both sides carry valid ratified tags"*
— so it **fails closed**, and contradictions `X-1` and `X-6` fail with it.
*Settled by:* one owner clause naming a single owner for "which functions write table T", or an
explicit statement that the schema spec's write-authority column governs and RLS §5/§7.x are its
roll-up (the shape `EXEC-DERIVED` already uses for grants).

**`PAY-STATE` — payment/refund/payout state machines.** Two label sets coexist with nothing ranking
them (`scheduled → processing → paid` in the domain architecture vs `pending · submitted · paid` in
the schema spec, and the same split for refunds). `OR-6`'s eight-subject list does not include it.
*Settled by:* the template already exists one section over — the schema spec reconciles the
`p2p_transfer` vocabulary explicitly (*"resolved in favor of the schema/RPC term"*). One equivalent
row for `kernel.payout.status` / `kernel.refund.status`, plus a ratified row, closes it.

**`RESALE-WRITER` — writers of `kernel.tickets.resale_state`.** RPC states outright *"This document
does not choose"*, and `ODR-38` is `OPEN — OWNER` with recommendation **None**.
*Settled by:* an owner ruling on `ODR-38`.

**`EDGE-PKG` — which package each edge function and cron ships with.** The edge spec *"states only
'these land at `076`+' and assigns no package."*
*Settled by:* an edge-function row in the schema spec's §13 placement record, or a registry clause
saying edge deploys follow their calling package.

## CONTESTED OWNERSHIP — reported, not resolved

Beyond the four above, five subjects have two texts each claiming authority. They are **assigned**
here because one claim is subordinate on its face, but the collisions are recorded so a future
conflict is not resolved by whichever document a reader opened first.

1. **`GRANTS`** — RLS §11 self-asserts authority its own §11.0 denies it (*"this table is its
   roll-up"*). The corpus names this collision as the mechanism of a real over-grant.
2. **`MONEY-AUTH` vs `MONEY-MATRIX`** — the domain architecture says *"Where the two disagree on a
   **money** cell, this matrix wins"*, while `C75` says *"money authority → the money spec"* and RLS
   says its money sections are *"REPLACED WHOLESALE"* by the money spec. Split here along the domain
   architecture's own D6 line (cells → matrix, model → money spec); **the two are not co-extensive
   and neither defers.**
3. **`DOOR-AUTH`** — the D6 table assigns door authority to the matrix; RLS routes every door EXEC row
   to `ROLE_MODEL` §5.3. Two governing texts for the same predicates.
4. **`RLS`** — the schema spec says each delta spec is authoritative for *"the RLS matrix … of its own
   objects"*, while RLS §16 carries matrices for those same objects. A resolution direction exists for
   EXEC (`EXEC-DERIVED`) and for none of the read matrices.
5. **`ORG-ROLE`** — the D6 table names **two** governing texts in one cell with no tiebreak, while
   three other documents name `ROLE_MODEL` §3 alone.

## Assignments that are INFERRED rather than declared

Stated plainly, because `OR-6` forbids inventing ownership:

- **`SCAN`** — no sentence names an owner for online admission semantics. Assembled from RPC's
  contracting role plus the edge spec's disclaimer (*"does not own … the RPC signatures"*).
- **`ROLLBACK`** — transitive only: the registry delegates *"rollback posture"* to plan §8; no
  document claims it in the first person.
- **`RESALE`** — placed with the domain architecture because the spec foundation puts it above itself
  in its own source-authority order. **That step is mine.**
- **`DOOR`, `NOTIFY`** — `OR-6` names roles (*"the door authority"*, *"the notification authority"*),
  not paths. Resolving a role-name to a filename is corroborated by the schema spec's delta-spec
  clause and the dashboard's binding delegation, but **the mapping itself is written nowhere.**

**Documents that disclaim authority entirely, and are therefore never owners:** the traceability
matrix (*"Authority: none. This document decides nothing"*), the scope amendment (*"the cited spec
wins and this row is a defect"*), the owner decision register, and the G-25 event catalog.

## THE MAP

`SUBJECT_ID | SUBJECT | NORMATIVE_OWNER | NORMATIVE_SECTION | DERIVED_DOCS | CORRECTION_FALLBACK`

Parsed by `scripts/precedence_gate.py`. Every path is existence-checked by the gate; a typo fails CI.

```owner-map
PKG-NUM|Which migration package number a Phase-2 object or feature carries|docs/architecture/PHASE_2_PACKAGE_REGISTRY.md|§2 registry table; §4 decoding stale quotations; §6 rules 1-5|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_PROMOTER_CODES_SPEC.md;docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md;docs/architecture/PHASE_2_SCOPE_AMENDMENT_2026_08.md;docs/architecture/PHASE_2_SPEC_FOUNDATION.md;docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md;docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md|NO
PKG-PLACE|Which package each delta-spec object is placed in|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|§13 binding placement record; §13.1 placement index; §13.5 disagreements|docs/architecture/PHASE_2_PACKAGE_REGISTRY.md;docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_SCOPE_AMENDMENT_2026_08.md|NO
PKG-CONTENTS|The per-package specification: objects, functions, RLS, triggers, indexes, grants, flags, tests|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md|§8 THE FINAL PACKAGE TABLE (canonical; §8 wins over §5)|docs/architecture/PHASE_2_PACKAGE_REGISTRY.md;docs/architecture/PHASE_2_IMPLEMENTATION_TRACEABILITY_MATRIX.md|NO
DEP-DAG|The package dependency edge set and apply order|docs/architecture/PHASE_2_PACKAGE_REGISTRY.md|§2.1 apply order and dependencies; §3 machine-readable depends_on|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|NO
SEAM-RULE|Where a routine, policy or grant is authored - the placement derivation itself|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md|§8 acceptance property; §0.4b SEAM-1/2/2a/4|docs/architecture/PHASE_2_PACKAGE_REGISTRY.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|NO
SCHEMA-PHYS|Physical table and column definition: columns, PKs, FKs, CHECKs, indexes, AO and RLS posture|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|§0 global conventions; §1-§4 per-table sections|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md;docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md|NO
RPC-SIG|RPC signature, arity, parameter and return types, volatility, and the canonical function name|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|§0 conventions; §1-§19 contracts; §17 delta RPCs; §20.13 naming register|docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md;docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_PACKAGE_REGISTRY.md|NO
HELPER-SET|Membership of the kernel predicate-helper set|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|§1.1-§1.1e defining contracts (RLS §2.2 HELPER-DERIVED clause 1)|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md;docs/architecture/PHASE_2_SPEC_FOUNDATION.md|YES
WRITER|Write authority: which principal or RPC may write each table and column|AMBIGUOUS|THREE-WAY CONTESTED - see the AMBIGUOUS section||NO
RLS|Row-level security policies and their USING / WITH CHECK predicates|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md|§4 global write posture; §7-§10 per-table matrices; §16 delta-object matrices; §16.10 policy register|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md|NO
GRANTS|EXECUTE authority: which principal may execute which function|docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md|§5.3 capability matrix (RLS §11 is its roll-up per RLS §11.0 EXEC-DERIVED)|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md;docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md|NO
ORG-ROLE|The canonical stored role labels and the three disjoint plane enums|docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md|§3 canonical enum membership; §4 concept-to-label map; §5.1 twenty principals|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_SPEC_FOUNDATION.md;docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md|NO
ROLE-CAP|Non-money role-by-capability detail at twenty-principal grain|docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md|§5.3 sections A and C-I|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md|NO
MONEY-MATRIX|Role-by-action money authority cells|docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md|§7.6 permission matrix and its D6 precedence note|docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md;docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md|NO
MONEY-AUTH|The money-authority model: request-vs-execute, tiers, ceilings, dual control, SoD, step-up|docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md|§2.1/§2.2 read scoping; §5 request-vs-execute; §6.6 approval object; §7 thresholds; §8 control set|docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md|NO
AUTHZ-BRANCH|The authority branch a money RPC evaluates at run time|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|§17.1/§17.2/§17.7|docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md;docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md|NO
PAY-STATE|Payment, refund and payout state machines and their status label sets|AMBIGUOUS|no designated owner in the corpus||NO
CUSTODY|Ticket custody: the atom, the append-only ownership log, and who holds the admission right|docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md|§0 principle 1; §1.1 Ticket Atom and Ownership Log; §11 naming constitution|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md;docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_SPEC_FOUNDATION.md|NO
INVENTORY|Inventory counters: capacity, held, sold, remaining, and counter-versus-ledger authority|docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md|§15 C27; §1.3 operational counters; §5 storage categories|docs/architecture/PHASE_2_SPEC_FOUNDATION.md;docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|NO
RESALE|The two-rail resale model and the native-external listing bridge|docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md|Part 10 two-rail resale; §0.5 C8 native-sale boundary|docs/architecture/PHASE_2_SPEC_FOUNDATION.md;docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|NO
RESALE-WRITER|Which functions may write kernel.tickets.resale_state|AMBIGUOUS|no designated owner; open owner decision ODR-38||NO
DOOR|Door lifecycle: episode ledger, freeze boundary, manifest open and close, door session, PINs|docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md|§4-§10A (owner rulings O-5 lifecycle and O-4 authority)|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md;docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md;docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md|NO
DOOR-AUTH|Door authority: who may open or close a manifest, move door_open_at, hold security config|docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md|§7.6 door rows plus §1.8 (owner rulings O-4/O-5), per the §7.6 D6 precedence table|docs/architecture/PHASE_2_ROLE_MODEL_SPEC.md;docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md|NO
SCAN|Online scan and admission contract|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|§7.5 mark_ticket_scanned; §9.4/§9.5 scan and offline reconcile contracts|docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md;docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md;docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md|NO
SCAN-OFFLINE|The offline door admission predicate|docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md|§5.4.3 OFFLINE-VERIFY-v1 (BINDING, NORMATIVE, SINGLE SOURCE; mirrors byte-identical)|docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md;docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md;docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md|NO
REENTRY|Re-entry posture: MVP is no re-entry, first-in-wins|docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md|§15 C41 (Gate P), integrated at §1.1 and §1.3|docs/architecture/PHASE_2_SPEC_FOUNDATION.md;docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|NO
WALLET|Apple Wallet credential delivery|docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md|its own objects' full column list, RLS matrix and pgTAP set, per schema §13 preamble|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md;docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|NO
NOTIFY|Notification delivery: channels, preferences, enqueue and drain, notification centre|docs/architecture/PHASE_2_NOTIFICATIONS_SPEC.md|§1 reuse-extend-new; §2-§10 (dashboard §16.5 is a binding delegation to this spec)|docs/architecture/PHASE_2_VENUE_DASHBOARD_PRODUCT_SPEC.md;docs/architecture/PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md;docs/architecture/PHASE_2_SCOPE_AMENDMENT_2026_08.md|NO
CRM|Venue CRM and attendee export|docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md|§6 templates; §11.1-§11.5 (schema §11.2 names it the semantic source)|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md|NO
DEMO|Demographics capture and privacy|docs/architecture/PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md|§5 suppression; §7 access posture; §9 X-1 to X-9 export constraints; §10.1/§10.2 storage|docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md;docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|NO
PROMOTER|Promoter attribution: codes, links, attribution rows, commission accrual and payable|docs/architecture/PHASE_2_PROMOTER_CODES_SPEC.md|§6 where commission is authoritative; §7-§15|docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md;docs/architecture/PHASE_2_RLS_PERMISSION_SPEC.md;docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md|NO
EVENT-CAT|The canonical business-event catalog|docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md|§6.1 canonical business-event catalog, as trimmed by ratified C11 in §0.5|docs/architecture/_governance/G25_CANONICAL_EVENT_CATALOG.md;docs/architecture/PHASE_2_NOTIFICATIONS_SPEC.md|NO
OUTBOX|The transactional event outbox and its drainer|docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md|§6.2 transactional spine and §6.3 outbox to cron drainer (ruled BUILD by OR-4)|docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md;docs/architecture/PHASE_2_NOTIFICATIONS_SPEC.md;docs/architecture/_governance/ODR2_BUILD_CONSEQUENCE_MAP.md|YES
EVT-ENVELOPE|The event envelope and the closed SSCAS membership|docs/architecture/SNATCH_IT_CANONICAL_DATA_MODEL.md|§15 C12 (record row E-1: the fifteen-member list is canonical)|docs/architecture/PHASE_2_SPEC_FOUNDATION.md;docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md|NO
ROLLBACK|Per-package rollback posture and reversibility|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md|§8 per-package Rollback rows and the §8 rollback-posture vocabulary|docs/architecture/PHASE_2_PACKAGE_REGISTRY.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|NO
ROLLBACK-RULE|The standing rule that every migration ships a rollback script and a header|docs/architecture/SNATCH_IT_ENGINEERING_STANDARDS.md|§5|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md;docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md|NO
PROTECTED-SHAPES|The protected shapes of packages 084 and 091|docs/architecture/PHASE_2_PACKAGE_REGISTRY.md|§6 rule 7|docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md|NO
EDGE|Edge function contracts: routes, auth model, verify_jwt posture, secrets, boundary shape|docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md|§2-§8 (self-declared: this spec owns the edge contract)|docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md;docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md;docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md;docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md|NO
EDGE-PKG|Which migration package each edge function and its cron schedule is deployed alongside|AMBIGUOUS|no designated owner; the edge spec assigns no package||NO```

## Two secondary defects surfaced while building this map

- The package registry cites the outbox promise at a line number where the text is **not**; the
  sentence is ten lines further down and the cited line is blank.
- The owner decision register points the `resale_state` writer question at **`ODR-80`** (kill
  switches); the correct entry is **`ODR-38`**.

Neither is a precedence question. Both are filed here so they are not lost.
