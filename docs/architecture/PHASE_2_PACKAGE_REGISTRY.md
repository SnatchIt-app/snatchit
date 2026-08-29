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
> **COUNT 17, `076`–`092` — RATIFIED `OR-12` (2026-08-29; OR-4 outbox → `076`, OR-5 notify → `092`).** *(This block previously read "COUNT UNCHANGED at 16 — conditionally"; the conditionals are ruled.)* Two formerly ratified-but-unscheduled items are now scheduled:
> marked conditional and are **not** counted: the **event outbox** (`DA:1253`
> promises Phase 2 builds it; no implementation spec schedules one) and the
> **`notify` schema** (ratified row **C7 is Gate P / MVP** and names it; all four
> implementation specs place it at Gate L / do-not-build). See §7.
> **`notify` IS ruled Gate P REDUCED (`OR-5`) and the count IS 17 (`076`–`092`) — `OR-12`.** *(Formerly conditional: "If `notify` is ruled Gate P, the count becomes 17 … and §2's "no
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
> package number; the count stays 16 (`076`–`091`) *(historical — superseded by `OR-12`: 17, `076`–`092`)*.**
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
> topologically ordered by package number. The count stays 16 (`076`–`091`) *(historical — superseded by `OR-12`: 17, `076`–`092`)*.** Two
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
> *(`OR-1`, 2026-08-28: `MD-2` has since resolved `postgres`-owned — the `crm_export_builder` role is
> not created and the zero-rows narrative above is historical rationale. `K-2`'s placement of the two
> `_event` tables stands unaffected.)*
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

> ## ⚠ FIFTH AMENDMENT PENDING RE-RATIFICATION — the reviewer-conditions pass (`AUTHZ-PKG1`)
>
> **No package is added, renumbered or removed; the count stays 16 (`076`–`091`) *(historical amendment record — superseded by `OR-12`)*.** Four
> ratified venue-plane read policies — `catalog_venue_sel_venue`, `catalog_event_sel_venue`,
> `catalog_event_session_sel_venue`, `kernel_tickets_sel_venue` — were created in `078`/`079`
> while the predicate they call, `has_venue_role`, is created in `080`. **The helpers cannot
> move earlier**: `has_venue_role` reads `venue.staff_role`, which `080` creates, and SEAM-1
> binds the function there — moving it means moving the table, which renumbers the band. The
> policies therefore move to `080`, so the forward reference **ceases to exist** rather than
> being declared and tolerated. **One declaration-only edge is added, `‡079 → 080`**;
> `declared_edge_count` 38 → **39**, re-verified identical across all four surfaces.
> Ratification rows **C86**, **C87** (and `SEAM-3`).
>
> ## ⚠ SIXTH AMENDMENT PENDING RE-RATIFICATION — the unwritable-control pass (`MB-2` … `MB-5`)
>
> **No package is added, renamed or renumbered; no dependency edge is added; the count stays
> 16.** Five controls that the corpus specifies, ratifies and relies on had no physical
> substrate or no writer: `kernel.payout` gains `hold_state`/`hold_reason_code`/`held_by`/
> `held_at` (`085`); `kernel.mark_payout_transfer_state` (`085`) and the `venue.on_payout_settled`
> SEAM-2 hook (stub `085`, body `087`); `kernel.tg_custody_head_is_ledger_tail` (`079`);
> the two platform sentinel identities `SN-VOID` and `SN-SYSTEM` seeded in `078`; and
> `kernel.sweep_expired_ticket_atoms` (`079`). Ratification rows **C91**–**C98**.

> ## ⚠ SEVENTH AMENDMENT PENDING RE-RATIFICATION — the replay-ordering pass (`R2B`)
>
> **No package is added, renamed or renumbered; the band stays `076`–`091`, sixteen, each number used
> once; the count stays 16** *(historical amendment record — superseded by `OR-12`: `092` added, 17)*.** Objects move **between** packages, which rule §6.6 requires whenever
> `SEAM-1` says so.
>
> **The class.** `plpgsql` bodies are not validated at `CREATE FUNCTION`. Every defect in this pass
> therefore **replays green and fails at runtime** — the same shape as `K-2`, one layer up: `K-2` was a
> body naming a *relation* nothing created; this is a body naming a *relation or a routine that a LATER
> package creates*. The DDL layer was clean and stayed clean; the routine layer was not.
>
> **`R2B`-1 (`C116`, `S2-A`) — a composite type used by two routine signatures and created by nothing.**
> `venue.settlement_line_candidate` occurs **exactly once in the repository** (RPC §20.11.1), as the
> declared `RETURNS SETOF` type of `kernel.settlement_royalty_lines`, inherited by
> `kernel.settlement_commission_lines`. Scheduled as **`kernel.settlement_line_candidate` in `087`**,
> created immediately before the two stubs. Without it `087` fails `42704`; with two hand-written
> `RETURNS TABLE(…)` lists instead, `088`/`090` fail *"cannot change return type of existing function"*.
> Physical definition filed to the schema-spec owner.
>
> **`R2B`-2 (`C117`, `S2-B`) — `market.on_atom_voided` had two arities and a `CREATE OR REPLACE`.**
> Two-parameter `(atom_id, refund_id)` in plan §0.4b and schema §13.2 (twice) against RPC §20.11.3's
> three-parameter `(p_atom_id, p_refund_id, p_cause)`. Canonical is the **three**-parameter form. New
> binding rule **`SEAM-2a`**: a hook's parameter list, parameter **names** and return type are frozen at
> the stub; `CREATE OR REPLACE` may change only the body, and the replacing package asserts
> **`COUNT(*) = 1` over `pg_proc`** for the hook name.
>
> **`R2B`-3 (`C114`, `V5`) — `kernel.issue_ticket_atoms` reads `kernel.signing_key` (`083`) from `081`.**
> **`FR-3` used exactly this criterion to move `kernel.transfer_ticket_ownership` out of `079`**, and the
> sibling mint engine — which reads the same table and pins `signing_key_id` on every atom it creates —
> was left where it was. Moved to **`083`** by the same rule; `max(078, 079, 081, 083) = 083`. **New
> declared edge `081 → 083`.** SEAM-2 was considered and is inadmissible (no *correct* neutral result for
> "no signing key"); moving the table instead was rejected because it changes `084`'s object list, which
> rule §6.7 protects.
>
> **`R2B`-4 (`C113`, `V4` + `V6`) — `venue.append_door_manifest_delta` (`086`) is called from three
> earlier packages.** `kernel.issue_ticket_atoms` (`083`) for the `op='add'` supplement, and
> `kernel.void_ticket_atom`/`admin_refund`/`force_void_ticket` (`085`) for the `op='revoke'` obligation
> RPC §12.4c makes **mandatory** on every freeze-exempt void. Closed by **one SEAM-2 hook**: stub in
> `083` (the earliest caller's package), body in `086`. **No `085 → 086` edge — which is what makes the
> repair admissible, since that edge would run backwards.**
>
> **`R2B`-5 (`C111`, `V2`) — the primary money path forward-referenced two packages, one of them eight
> ahead.** `venue.finalize_primary_order` (`082`) writes `kernel.payment_native` (`085`) **and calls
> `venue.resolve_order_attribution` (`090`)**. Repair is split because the two arms are different
> problems: the `085` write is closed by **moving the function to `085`** (`SEAM-1`; nothing in
> `082`–`084` calls it, and `FR-9` already rules an edge-function caller is not a DDL forward
> reference), and the `090` call is closed by a **SEAM-2 hook** — `venue.resolve_order_attribution`
> stubbed in `085`, body in `090` — because moving to `090` would author the primary purchase path
> inside the promoter package. **The `090` arm is the severe one:** RPC §17.14 rules that the callee
> **never raises** *"because a raise here would roll back the money and the tickets"*, and `42883` is
> exactly a raise. **Three declared edges: `078 → 085` (already owed), `081 → 085`, `083 → 085`.**
>
> **`R2B`-6 (`C112`, `V3`) — a body writing a column a later package adds.** `venue.create_primary_checkout`
> (`082`) writes `venue.order.attribution_candidate_code_id` / `_link_id` (RPC §6.1's Writes row), and both
> columns were scheduled in **`090`**. `42703` is the same defect as `42P01`, one SQLSTATE over. **It was
> invisible to the placement record because that record checked the FK targets** — schema §13.2's `090`
> row reads *"✓ — FK targets are `090`"*, correctly, about the wrong end of the edge; the **writer** was
> never asked. Repair is **move the dependency earlier**: the columns are born in `082` as plain
> `uuid NULL`, and `090` keeps the **ADOPT** of both FK constraints (`NOT VALID` + `VALIDATE`) — the
> construction `084` and `089` already use and §0.4 names. The freeze guard moves with the columns
> (`max(082) = 082`). **No edge** — `090` already declares `082`. **Filed to the promoter-spec owner:**
> `090`'s *"reverts as one unit"* property is preserved for every promoter-owned object; the two order
> columns are order-aggregate columns by RPC §6.1's own ruling (*"1:1 with the order … which is why it
> lives on the order row"*) and are inert (NULL) without `090`.
>
> **`R2B`-7 (`C110`, `V1` + `V7`) — the open-doors drain and its preview reach the native resale rail.**
> `venue.open_door_manifest` (`086`) **writes** `market.p2p_transfer` and `market.listing_native` (`088`)
> — the drain — **inside the transaction that engages the session's terminal transfer-freeze**, so the
> first "Open doors" raises `42P01`, the freeze does not engage and `door_open_at` is not written. And
> `venue.preview_door_open_impact` (`086`) **reads three `088` relations** for the confirm dialog the
> open requires, so it fails first (**`V7`, found by this pass**). Closed by **two `market`-owned SEAM-2
> hooks**, `on_door_freeze_engaged` (write) and `door_freeze_drain_preview` (read), stubbed in `086` and
> replaced in `088`. **Moving `open_door_manifest` to `088` was rejected**: it would make the Phase-2B
> door gate depend on a rail gated behind Gate-M + Phase 2C. **And the hook is not a workaround** — §0.7
> already forbids a `venue` function writing `market` tables, and RPC §17.12 names this exact
> construction. **New declared edge `086 → 088`.**
>
> **`R2B`-8 (`C118`) — two pre-existing undeclared direct edges, surfaced not created.** **`087 → 088`**:
> `088` `CREATE OR REPLACE`s `kernel.settlement_royalty_lines`, stubbed in `087`, and no declared set
> said so. **A stub-replacement edge left undeclared is a silent inversion, not a missing name** — run
> the replacement first and the stub overwrites the real body with the neutral one, green replay and
> all. **`078 → 085`** (applied with `C111`): `085` reads `catalog.platform_config` for the
> `refund.*`/`payout.*`/`authn.*` tiers and calls `kernel.money_role_grant_matured`, authored in `078`.
> **Fifth and sixth instances of the shape** after `079 → 085`, `085 → 088`, `086 → 087` and
> `077`/`078 → 082`. Both **declaration-only**.
>
> **`R2B`-9 (`C115`) — a twelve-relation GRANT set that no package's Grants row contained.**
> `GRANT … TO crm_export_builder` appears in **no** package anywhere, across the closed twelve-relation
> set RLS §16.10 names, spanning `077`–`087`, while the **role** was scheduled in `087`. The house
> convention puts a table's grants with the table, so the first one written lands in `077` and **dies at
> `42704`** — a `GRANT` resolves its grantee immediately, so this one is a hard replay failure rather
> than a runtime one. Repair by new rule **`SEAM-4`**: the role moves to **`076`**, the GRANT-boundary
> package, and each grant is authored with its relation — `076` ×1 (`auth.users`, column-scoped),
> `077` ×4, `078` ×2, `079` ×1, `082` ×4, `087` ×1 = **twelve** plus the `auth.users` grant. **No edge**
> (every package reaches `076` transitively and the corpus does not declare transitive edges). **The
> whole set is contingent on RLS `MD-2`, which is recorded and NOT taken here.**
>
> *(`OR-1`, 2026-08-28: `MD-2` is now taken — `postgres`-owned. `C115` reverted as one unit: no
> `CREATE ROLE`, no grants, no `_sel_svc_export` policies. See the §3 `grants` tombstone and
> `_governance/O17_RULING_IMPACT_MAP.md`.)*
>
> **The condition, now closed.** Both DDL-authoritative documents said *"SEAM-2 is used exactly three
> times"* and listed three; this registry's JSON `hooks` array has held **four** since the unwritable-control
> pass. The fourth is **`venue.on_payout_settled`** (`MB-2b`, ratified row **`C92`**), and its absence from
> the two prose enumerations reopened `C92` in exactly the documents an implementer reads to know what to
> build. Plan §0.4b now enumerates four; schema §13.2's two occurrences are reported to its owner.
>
> **Edge tally for this amendment: `declared_edge_count` 39 → 45, six added, enumerated** —
> `081 → 083` (`C114`), `078 → 085`, `081 → 085`, `083 → 085` (`C111`, the first of the three already
> owed), `086 → 088` (`C110`), `087 → 088` (`C118`, already owed). **`C112`, `C115`, `C116` and `C117` add
> none.** Every added edge strictly increases the package number, so the DAG stays acyclic and
> topologically ordered by number; **all four surfaces were re-verified by parser after every commit of
> this pass**, not by reading. **Objects moved between packages: three** — `kernel.issue_ticket_atoms`
> (`081 → 083`), `venue.finalize_primary_order` (`082 → 085`), and the pair
> `venue.order.attribution_candidate_code_id`/`_link_id` with their freeze guard (`090 → 082`, FKs
> adopted back in `090`) — **plus the role `crm_export_builder` (`087 → 076`)**. **Objects added: four
> SEAM-2 hooks and one composite type**, enumerated in §3. **No package number changed.**
>
> *(`OR-1`: the appended fourth move — the role `crm_export_builder` (`087 → 076`) — was subsequently
> voided; the role is not created at all. The three object moves stand and the count "three" is again
> exact.)*
>
> **Owner ratification required**, per rule §6.5. **No change here is an owner decision** — every
> placement is `SEAM-1`, `SEAM-2` or the new `SEAM-4` applied to a fact already in the corpus; the arity
> is RPC §20's contracted signature under §8's own precedence rule; and the hook count is a transcription
> of `C92`. **Three questions ARE owner decisions and NONE is taken here:** (1) **`p_cause`'s admissible
> values and effect** are contracted nowhere (filed to the RPC owner as `R2B-1`) — and because `SEAM-2a`
> freezes the parameter list, a ruling that drops it must land **before `085` is authored**; (2) the whole
> `crm_export_builder` grant set is contingent on RLS **`MD-2`**, which stays open under its existing id;
> (3) `090`'s *"reverts as one unit"* property with the two order columns now born in `082` is filed to
> the promoter-spec owner. **None is re-numbered into a new `O` row** — each already has a home.
>
> *(`OR-1`, 2026-08-28: question (2) is now taken — `MD-2` ruled `postgres`-owned and the grant set is
> not built. Questions (1) and (3) remain open.)*

Consult this file **before quoting, authoring, or reviewing any Phase-2 migration
number.** If another document disagrees with this table, this table wins and the
other document is stale — fix it, do not follow it.

---

## 1. The two bands — never confuse them

| Band | Numbers | What it is |
|---|---|---|
| **Applied production security migrations** | `071`–`075` | Real, applied, immovable SQL in `supabase/migrations/`. **NOT Phase-2 packages.** |
| **Phase-2 MVP packages** | `076`–`092` | Design-only specification. **Seventeen packages** (`OR-12`, 2026-08-29). No SQL authored yet. |

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

## 2. Phase-2 package registry `076`–`092`

`old` = the number in the **original ratified plan** (`071`–`086`), the scale most
of the corpus was written on. Two intermediate `+1` shifts (`072`–`087` and
`073`–`088`) existed only inside `PHASE_2_SUPABASE_MIGRATION_PLAN.md` and are
**dead** — they are recorded in §4 only so that stale quotations can be decoded.

| New | Old | Pkg | Phase | Purpose | Scope (one line) |
|---|---|---|---|---|---|
| `076` | `071` | A | A — schema skeleton | `076_create_phase2_schemas_and_grants` | 4 schemas (`kernel`/`catalog`/`venue`/`market`) + GRANT boundary + shared helper functions/triggers · **`OR-12`/`OR-4`: `CREATE SCHEMA notify`; `notify.outbox` (C12 envelope, zero FK deps); `notify.emit_event` — the outbox primitive, placed here by its own SEAM-1 + the `C76` forward-reference test (B-7 derivation)** |
| `077` | `072` | B | B — organizations + permissions | `077_kernel_identity_orgs_and_roles` | `kernel.identity_ext`, `organization`, `org_member` (**six** org labels, **+`granted_at`**), `org_invite` (**six** org labels), `platform_role`, `admin_audit` + org/platform role predicates · **Δ `approval_request` (**+`required_approver_class`**), `identity_demographic(_erasure)`, `identity_contact_pref`, **`identity_contact_pref_event` (AO — `K-2`)**, `org_customer_key`, `organization.payout_destination_set_by`, `identity_ext.locale`** · **`OR-17` deletion machine (F-P0-1/A): `identity_ext` +`deletion_state`/`deletion_requested_at`/`deletion_block_reason` (+ OPEN-3 marker cell) + pending partial index; `request_account_deletion`/`withdraw_account_deletion`/`is_deletion_pending`/`sweep_deletion_pending` (+ its own `cron.schedule`, P0-1); the TEN deletion SEAM-2 stubs (5 `deletion_blockers_*` evaluators, 4 `on_identity_erased_*` cleaners, + `has_outstanding_obligations` — the `OR-21` BP-10 predicate); F-6 clauses; cutover deploy artifacts (delete-account edge switch, F-5 live-rail guards)** |
| `078` | `073` | C | C — catalog | `078_catalog_reference_data_and_flags` | `catalog.venue`, `event`, `event_session` (incl. `door_open_at`), `platform_config` (**+`visibility`** — split read, not blanket public) + **all** feature-flag and config seeds, `resale_policy` · **Δ `event` marketing columns, `event_session.session_version`, `effective_freeze_at()`, `kernel.money_role_grant_matured` (SEAM-1: `max(077, 078)`)** · **`MB-5` the two platform sentinel identities `SN-VOID`/`SN-SYSTEM` (seed rows, not a table) — `ticket_ownership_log.to_identity`/`actor_identity` are `NOT NULL FK→auth.users` and nothing seeded them** |
| `079` | `074` | D | D — ticket kernel | `079_kernel_ticket_atom_and_ownership_log` | `kernel.tickets` (custody atom) + `kernel.ticket_ownership_log` (append-only custody ledger, C26 idempotency) · **Δ `door_freeze_override`, `is_transfer_frozen`, `lock_/unlock_ticket`, `mark_ticket_scanned`** · **`MB-4` `kernel.tg_custody_head_is_ledger_tail` — the *verify trigger* the constitution names three times and no package built** |
| `080` | `075` | E1 | E — inventory | `080_venue_staff_roles_and_predicates` | `venue.staff_role` (**six canonical labels**) + `has_venue_role`/`has_event_role` · **Δ `has_org_role_over_venue`/`_over_event`** |
| `081` | `076` | E2 | E — inventory | `081_venue_inventory` | `venue.ticket_type`, `inventory_batch`, `inventory_batch_shard`, `inventory_movement`, `inventory_hold` (oversell-safe counter) · **Δ `catalog.publish_event` authored here** · **`R2B` `kernel.issue_ticket_atoms` is NO LONGER authored here — moved to `083` (`C114`)** |
| `082` | `077` | F | F — orders | `082_venue_orders` | `venue.order`, `venue.order_item` (primary-purchase container) · **Δ `kernel.org_contact_consent`, `kernel.org_contact_consent_event` (AO — `K-2`)** · **`R2B` `venue.finalize_primary_order` is NO LONGER authored here — moved to `085` (`C111`); the two `venue.order` attribution-candidate columns and their freeze guard are moved IN from `090` (`C112`), their FKs adopted in `090`** |
| `083` | `078` | G1 | G — credential infrastructure | `083_kernel_credential_infrastructure` | `kernel.signing_key` — public key + KMS handle reference only, **no private key material** · **Δ `pass_type_cert`, `wallet_pass`, `wallet_pass_device`, `wallet_pass_push_log`, `.pkpass` bucket** · **`R2B` `kernel.issue_ticket_atoms` (moved from `081`; `C114`) + the `venue.append_door_manifest_delta` SEAM-2 stub (`C113`)** |
| `084` | `079` | G2 | G — credential infrastructure (ADOPT) | `084_kernel_tickets_late_binding_fks` | late-binding FKs `kernel.tickets` → `venue.ticket_type` + `kernel.signing_key` (`NOT VALID` + `VALIDATE`) — **and nothing else; the only unconditionally reversible package** |
| `085` | `080` | M | F/I bridge — kernel money-native | `085_kernel_money_native` | `kernel.payment_native`, `kernel.refund`, `kernel.payout` (link to frozen `public.payments`, never re-charge) · **Δ `void_ticket_atom` + `market.on_atom_voided` stub; the nine money-authority RPCs** · **`MB-2` `kernel.payout.hold_state`/`hold_reason_code`/`held_by`/`held_at`; `kernel.mark_payout_transfer_state`; the `venue.on_payout_settled` stub** · **`S-24`/`S-25` `kernel.mark_refund_state` + the `kernel.refund.stripe_refund_ref` partial unique + its pairing CHECK (schema §1.10.1; `C101`/`C102`; SEAM-1 `max(077,085)=085`, no edge added — the refund table's sibling of `mark_payout_transfer_state`)** · **`F-P2-1`/`OR-21` `kernel.identity_obligation` + `record_/resolve_identity_obligation` + `has_outstanding_obligations` (BP-10 operand; SEAM-1 `max(077,085)=085`, no edge added)** · **`R2B` `venue.finalize_primary_order` (moved from `082`; `C111`) + the `venue.resolve_order_attribution` SEAM-2 stub (`C111`)** |
| `086` | `081` | H | H — scan infrastructure | `086_venue_door_and_scan` | `venue.door_pin`, **`door_session`**, `scan_device`, `scan` (C41 re-entry hedge), `comp_allocation`, `guest_list`, `guest_entry` · **Δ `door_manifest(_entry/_delta)`, `holder_mix_snapshot`, `holder_mix_bucket`, `scan.actor_identity_id`, `assert_door_session` (token-bearing)** · **`R2B` the two `market.*` door-drain SEAM-2 stubs `on_door_freeze_engaged` / `door_freeze_drain_preview` (`C110`) + the `venue.append_door_manifest_delta` body (`C113`)** · **`R-7a` `venue.unpublish_holder_mix` + `unpublish_all_holder_mix` + `reconcile_holder_mix` (RPC §17.20; SEAM-1 max=086; scheduled 2026-08-29 — contracted, previously built by nothing, `RC-5`)** |
| `087` | `082` | I | I — settlement | `087_venue_settlement_and_export` | **`R2B` TYPE `kernel.settlement_line_candidate` (`C116`)** · `venue.settlement`, `venue.settlement_line` (per-event money rollup → `kernel.payout`) · **Δ `export_job` + `crm-exports` bucket; `close_settlement` + its two hook stubs; the three purge-agent definers **`claim_artifacts_for_purge` · `confirm_artifact_purged` · `reconcile_export_orphans`** plus **`assert_may_request`** (`K-3`); the `export_job` purge substrate **`artifact_state` · `purge_lease_until` · `purge_attempts` + the `(artifact_state, expires_at)` claim index**; edge `crm-export` + `crm-export-worker` and their two `pg_cron` schedules** · **`MB-2b` the `venue.on_payout_settled` hook body (stub in `085`) — `venue.settlement.status='paid'` had no writer** |
| `088` | `083` | J1 | J — native marketplace bridge | `088_market_native_rail` | `market.listing_native`, `auction`, `offer`, `market_sale` (C26 terminal SM), `p2p_transfer` · **Δ `transfer_ticket_ownership`, `catalog.cancel_event`, replaces two hooks** · **`R2B` replaces the two `market.*` door-drain hooks stubbed in `086` (`C110`) — four hook replacements in total** · **R-37/`OR-22`: the buy-now checkout set (§20.8.8–§20.8.12) + `reserved`/`cancelled` labels + the `resale-checkout` edge and its sweep cron — zero `depends_on` change** |
| `089` | `084` | J2 | J — native marketplace bridge (ADOPT) | `089_market_bridge_view_and_late_fk` | `market.listing_unified` VIEW (external ∪ native, flag-gated) + adopt `payment_native.sale_id` FK |
| `090` | `085` | 2D | Phase 2D — promoter engine | `090_venue_promoter_engine` | `venue.promoter`, `promoter_link` (**+`status`**), `attribution` (modeled now, activated in the promoter phase) · **Δ commercial-terms columns, `promoter_code(_scope)`, `attribution_review`, the cross-settlement commission unique, *(`payment_native.instrument_fingerprint` MOVED OUT to `085`, 2026-08-29, `C112` column-follows-writer)*** · **`R2B` ADOPT of the two `venue.order` candidate FKs (`NOT VALID` + `VALIDATE`); their columns are born in `082` (`C112`)** |
| `091` | `086` | K | K — money-ledger extensions | `091_kernel_reserve_stub` | `kernel.reserve` **stub only** (empty shape, no writers); full Gate-M ledger is documented-only |

**Count: 17 packages, `076`–`092` inclusive, no gaps, no duplicates** (`OR-12` — COND-A/COND-B RULED, `OR-4`/`OR-5`).

`Δ` marks objects added by the eight ratified delta specs. The binding placement record, including the
argument for every disagreement with a delta spec's own proposal, is
`PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md` **§13**. The full per-package specification (purpose · tables ·
functions · RLS · triggers · indexes · grants · flags · dependencies · rollback posture · tests) is
`PHASE_2_SUPABASE_MIGRATION_PLAN.md` **§8**.

### 2.1 Apply order and dependencies

**+** marks an edge added by the delta-spec integration; **†** marks the one edge added by the final
reconciliation pass; **‡** marks the two added by the K-2 repair and the one added by the reviewer-conditions
pass; **§** marks those added by the replay-ordering pass (`R2B`). Every dependency precedes its dependent,
so the graph is a DAG and is topologically ordered by package number. **Total: 66 edges** *(was stated "45" — stale since `OR-12`'s 62; corrected with `OR-17`'s +4)*.

| Seq | Pkg | Depends on |
|---|---|---|
| 1 | `076` | precondition (phase0 chain + `071`–`075`) |
| 2 | `077` | `076` |
| 3 | `078` | `077` |
| 4 | `079` | **+`076`** *(OR-12: emit_event caller)*, `077`, `078` |
| 5 | `080` | **+`076`** *(OR-12: emit_event caller)*, `077`, `078`, **‡`079`** |
| 6 | `081` | **+`077`** *(OR-17: F-1 freeze clause calls the 077 deletion predicate)*, `078`, `080` |
| 7 | `082` | **‡`077`**, **‡`078`**, `081` |
| 8 | `083` | **+`076`** *(OR-12: emit_event caller)*, **+`077`** *(OR-17: replaces the deletion-wallet stub)*, `078`, **+`079`**, **§`081`** |
| 9 | `084` | `079`, `081`, `083` |
| 10 | `085` | **+`076`** *(OR-12: emit_event caller)*, `077`, **§`078`**, **+`079`**, **§`081`**, `082`, **§`083`** |
| 11 | `086` | **+`076`** *(OR-12: emit_event caller)*, **+`077`** *(OR-17: replaces the erased-door cleanup stub)*, **+`078`** *(B-4, 2026-08-29)*, `079`, `080`, `081`, **+`083`** |
| 12 | `087` | `077`, `081`, `085`, **†`086`** |
| 13 | `088` | **+`076`** *(OR-12: emit_event caller)*, **+`077`** *(OR-17: F-2/F-3/F-4 clauses + replaces the deletion-market stubs)*, `078`, `079`, `081`, **+`085`**, **§`086`**, **§`087`** |
| 14 | `089` | `085`, `088` |
| 15 | `090` | **+`076`** *(OR-12: emit_event caller)*, **+`077`** *(B-4, 2026-08-29)*, `082`, **+`078`**, **+`085`**, **+`087`** |
| 16 | `091` | `077` |
| 17 | `092` | **`076`, `077`, `078`, `079`, `080`, `082`, `085`, `090`** *(OR-12 — the B-7 derived eight)* |

Why each added edge exists:

| Edge | Because |
|---|---|
| `079 → 083` | `kernel.wallet_pass.ticket_atom_id` FK → `kernel.tickets` |
| `079 → 085` | `kernel.refund_primary_order` drives `void_ticket_atom` → `kernel.tickets` (previously undeclared) |
| `083 → 086` | `venue.door_manifest_entry.signing_key_id` FK → `kernel.signing_key` — **and `venue.door_manifest_delta.signing_key_id`, same target** (door §10.3a) |
| `085 → 088` | `market.sweep_paid_pending_sales` writes `kernel.refund` (previously undeclared) |
| `078 → 090` | `venue.promoter_code_scope.event_id` FK → `catalog.event` |
| `085 → 090` | `090`'s resolver body READS `kernel.payment_native.instrument_fingerprint` *(column moved to `085` 2026-08-29, `C112` — `venue.finalize_primary_order` writes it)* |
| `087 → 090` | `090` adds the cross-settlement commission unique on `venue.settlement_line` and replaces `kernel.settlement_commission_lines` |
| **‡`077 → 082`** | `kernel.org_contact_consent_event.org_id` FK → `kernel.organization` — the `K-2` table added to `082`. **The pre-existing `kernel.org_contact_consent.org_id` and `venue.order.org_id` carry the identical FK and were already under-declared**, so the edge was owed before this repair and is only *forced* by it. **Declaration-only.** |
| **‡`078 → 082`** | `venue.order.event_session_id` FK → `catalog.event_session`. Pre-existing, co-located, and named in plan §8/`082`'s own **Dependencies** prose (*"`081` (ticket_type), `078`, `077`"*) while all four declared sets said `{081}`. Corrected in the same pass because fixing one half of a two-edge under-declaration and leaving the other is worse than fixing neither. **Declaration-only.** Fourth instance of the SEAM-1 shape, after `079 → 085`, `085 → 088` and `086 → 087`. |
| **§`086 → 088`** | **`R2B`/`C110`.** `088` `CREATE OR REPLACE`s the two `market.*` door-drain hooks — `on_door_freeze_engaged` and `door_freeze_drain_preview` — whose names and signatures `086` creates. **The edge is required, not cosmetic:** a replacement that ran before its stub would be silently **overwritten** by the stub's neutral body, with a green replay. |
| **§`087 → 088`** | **`R2B`/`C118` — pre-existing and undeclared, the SIXTH instance of the under-declaration shape.** `088` `CREATE OR REPLACE`s `kernel.settlement_royalty_lines`, whose stub is created in `087`, and no declared set said so. Same silent-inversion consequence as above: `087`'s zero-row body would overwrite `088`'s royalty arm and every settlement would close with no royalty lines. **Declaration-only** (`087 < 088`). |
| **§`083 → 085`** | **`R2B`/`C111`.** `venue.finalize_primary_order` moves from `082` to `085` and **calls `kernel.issue_ticket_atoms`, authored in `083` by `C114`.** A called routine contributes its own package to the `max()` in its own right — this is the edge class the uncorrected `SEAM-1` structurally could not see, because `085`'s own statement list names no `083` table. |
| **§`081 → 085`** | **`R2B`/`C111`.** `venue.finalize_primary_order` writes `venue.inventory_batch(_shard)` and `venue.inventory_movement` (RPC §6.3's Writes row); both are `081` and they came with the function. |
| **§`078 → 085`** | **`R2B`/`C111` — pre-existing, surfaced not created, and the FIFTH instance of the under-declaration shape** after `079 → 085`, `085 → 088`, `086 → 087` and `077`/`078 → 082`. `085` reads `catalog.platform_config` for the `refund.*`/`payout.*`/`authn.*` tiers (plan §8/`085`'s own Feature-flags row says so), its money RPCs call `kernel.money_role_grant_matured` (authored in `078`), and `finalize_primary_order` takes its rank-1 Event/Session read on `catalog.event_session`. **Declaration-only:** `078 < 085` was always true. |
| **§`081 → 083`** | **`R2B`/`C114`.** `kernel.issue_ticket_atoms` moves from `081` to `083` and takes its inventory writes with it. The mint **reads `kernel.signing_key` (`083`)** — RPC §7.1's precondition and the `signing_key_id` it pins on every atom — and writes `venue.inventory_batch(_shard)`/`inventory_movement` (`081`) and `kernel.tickets`/`ticket_ownership_log` (`079`): `max(078, 079, 081, 083) = 083`. **This is `FR-3`'s criterion applied to the other kernel engine** — `FR-3` moved `kernel.transfer_ticket_ownership` out of `079` for reading the same table, and the sibling mint was left behind. **The two alternatives were rejected on mechanics, not preference:** a SEAM-2 `resolve_active_signing_key` hook has no *correct* neutral result at `081` (fail-open mints a credential-less atom, fail-closed makes the mint impossible), and moving `kernel.signing_key` earlier changes `084`'s object list, which rule §6.7 protects. **Declaration-only for ordering** (`081 < 083`); the *placement* is what changed. |
| **‡`079 → 080`** | **`AUTHZ-PKG1`.** `080` creates `kernel_tickets_sel_venue`, a read policy on `kernel.tickets` (`079`). The four venue-plane read policies named in RLS §16.10 can only be written with `kernel.has_venue_role` / `kernel.has_event_role`, which ship in `080`, and **`RM-3` forbids re-inlining the join** — so they are created in `080` rather than in `078`/`079` (ruling and full `USING` clauses: RLS **§16.10a**). **Declaration-only:** `079 < 080` already, so no rollout order changes; what changes is that the edge is declared rather than true by luck. **The alternative — moving the helpers earlier — is structurally unavailable**: `has_venue_role` reads `venue.staff_role`, created in `080`, and `SEAM-1` binds it there |
| **†`086 → 087`** | `venue.list_attendees` / `venue.build_export_rows` read `venue.scan` for the check-in columns (previously undeclared — named in the migration plan's §8/`087` prose, absent from every declared set). **Declaration-only:** no package added, renamed or reordered; no object moved; no rollback changed. Third instance of the SEAM-1 shape, after `079 → 085` and `085 → 088`, and resolved identically. |
| **†`077 → 078`** *(avoided, not declared)* | **`kernel.money_role_grant_matured` (RPC §1.1e, `AUTHZ-C1C`) is authored in `078`, not in `077` beside `has_org_role`.** It reads `kernel.org_member` (`077`) **and** `catalog.platform_config` together with the `authn.money_role_maturity_hours` seed (`078`), so SEAM-1 gives `max(077, 078) = 078`. Authoring it beside the other org-plane predicates — the intuitive placement, and the wrong one — would create a forward reference to a table and a seed row that do not exist yet, and the helper would return `false` for every caller during `077`'s own replay while looking correct. **Fourth instance of the SEAM-1 shape, after `079 → 085`, `085 → 088` and `086 → 087`; this one is *avoided at authoring time* rather than declared after the fact, which is what SEAM-1 is for.** `078` already depends on `077`, so **no edge is added, no package is added, renamed or reordered, and the canonical band stays `076`–`091`.** |

| **`077 → 081`** | **`OR-17`.** `venue.reserve_primary_inventory` gains the F-1 acquisition-freeze precondition, which calls `kernel.is_deletion_pending` (`077`). Corrected SEAM-1: a called routine contributes its own package. **Declaration-only for ordering** (`077 < 081`). |
| **`077 → 083`** | **`OR-17`.** `083` `CREATE OR REPLACE`s `kernel.deletion_blockers_wallet` (BP-2), stubbed in `077`. Third acceptance property: a stub-replacement edge must be declared or a mis-ordered replay silently restores the neutral body. |
| **`077 → 086`** | **`OR-17`.** `086` replaces `kernel.on_identity_erased_door`, stubbed in `077`. Same property. |
| **`077 → 088`** | **`OR-17`.** `088` replaces `kernel.deletion_blockers_market` (BP-3/BP-4) and `kernel.on_identity_erased_market`, both stubbed in `077`, and hosts the F-2/F-3/F-4 freeze clauses calling the `077` predicate. |

> **`MP-1` adds no edge, and that is a checked result rather than an assumption.** Door §10.3/§10.3a add
> `ticket_type_id` FK → `venue.ticket_type` to `venue.door_manifest_entry` **and** `venue.door_manifest_delta`.
> `venue.ticket_type` is created in **`081`**, and `086` already declares `depends_on: ["079","080","081","083"]`
> — so the edge `081 → 086` exists, and this is **not** a fourth instance of the SEAM-1 shape. Recorded
> explicitly because an undeclared FK across packages is exactly what SEAM-1 is for, and "we checked and it was
> already there" is worth writing down once so the next reviewer does not re-derive it. **No package is added,
> renamed or reordered; the `076`–`091` band is untouched *(historical — the band is `076`–`092` since `OR-12`)*.**

### 2.2 The seam rule that keeps the DAG honest

Dependency edges between *tables* are visible in the FK graph. Dependency edges created by a **function
reading a table in a later package** are not, and a systematic sweep found **nine** of them (schema §13.2).
**A second class was found by an external reviewer on 2026-08-28 and adds four more — `FR-10`…`FR-13`,
thirteen in total: an RLS POLICY whose `USING` clause CALLS a function created in a later package.** The
§13.2 sweep was **function-scoped by definition** (*"a **function** authored in package N"*) and therefore
**structurally could not see a policy→function edge**, no matter how carefully it was run. Its scope, method
and artifact set are widened in schema §13.2. Three rules now prevent recurrence:

> **SEAM-1 (CORRECTED by `R2B`)** — a function is authored in the package equal to `max()` of the packages
> creating every table it reads, every table it writes, **and every table it reaches through a call**. **A
> called routine contributes its own package in its own right**, and **a column is a table for this
> purpose**. The uncorrected form — `max()` over the directly-named tables only — is what `V1`…`V7` walked
> through: each offender's own statement list scored clean and the forward reference was one call away.
> **SEAM-2** — where an earlier artifact must resolve the name, the earlier package ships a **hook stub**
> returning the neutral result and the later package `CREATE OR REPLACE`s **only that hook**.
> **SEAM-4 (NEW, `R2B`)** — a **`GRANT`** is authored in the package equal to `max()` of the package
> creating the **relation** and the package creating the **grantee role**. Unlike a function body, a
> `GRANT` resolves its grantee **immediately**, so a grantee defined later is a hard `42704` at replay,
> not a runtime surprise. **The corollary is that a role with grants owed from package N must be created
> at or before N.** *(Standing rule with no current subject — its original subject, the `C115`
> `crm_export_builder` grant set, was retired by owner ruling `OR-1`.)*
> **SEAM-2a (NEW, `R2B`)** — a hook's **parameter list, parameter NAMES and return type are frozen at the
> stub**; `CREATE OR REPLACE` may change only the body. Postgres cannot add a parameter by replacement (it
> creates an **overload**, leaving the stub live and every call site bound to it — silent) and cannot rename
> one (`42P13` — loud). The replacing package asserts **`COUNT(*) = 1` over `pg_proc` for the hook name**,
> plus `proargnames`/`proargtypes`/`prorettype` identity with the stub.
> **SEAM-3 (NEW, `AUTHZ-PKG1`)** — an **RLS policy** is created in the package equal to `max()` of the
> packages creating every table it reads **and every function its predicate calls** — *not* the package of
> the table it protects. Where those differ the policy is **deferred** to the later package and the deferral
> is stated in **both** packages' plan §5 entries. It is never re-implemented inline to avoid the wait;
> `RM-3` forbids that separately, and `SEAM-3` is what makes it unnecessary. **A deferred policy fails closed
> (`I-1`) for the packages it is deferred across** — which is safe, and is why deferral is preferred to any
> reordering of the ratified band.

**Third acceptance property, added by `R2B` (`C118`).** *For every SEAM-2 hook, the edge
`stub_package → replacement_package` must be a **declared** edge.* It is not implied by the numbering,
and the failure it prevents is silent: `CREATE OR REPLACE` succeeds whether or not the routine exists, so
a replacement running before its stub is **overwritten by the stub's neutral body**, green replay and all.
**Verified for all eighteen hooks:** `083 → 086`, `085 → 087`, `085 → 088`, `085 → 090`, `086 → 088` (×2),
`087 → 088`, `087 → 090`, the nine `OR-17` deletion pairs — `077 → 079`, `077 → 080`, `077 → 082`,
`077 → 083`, `077 → 085`, `077 → 086`, `077 → 088` (×2), `077 → 090` — and the `OR-21` BP-10 predicate pair
`077 → 085` (`has_outstanding_obligations`) — eighteen pairs, every one present in all four surfaces
(`077 → 083`, `077 → 086`, `077 → 088` added by `OR-17`; the rest already declared).

**Acceptance property (WIDENED by `R2B` — the old form is what `V1`…`V7` walked through):** *no routine
reads, writes, or **reaches through a call** any relation or column created in a later package.* Mechanically
checkable from `pg_depend`/`pg_proc` after each package's replay — **and the walk must be TRANSITIVE over
routine→routine edges.** A walk over a routine's direct table dependencies alone cannot see a forward
reference that is one call away, and four of `R2B`'s seven findings (`V1`, `V2`, `V4`, `V6`) were exactly
that. **Placement is therefore a DERIVED set, re-derived from each routine's contract — its Reads line, its
Writes line, its Preconditions line, and every routine named in its prose — and never inherited from where
the object list happens to sit.** The full statement, its three admissible repairs, and the two forms of the
check are `PHASE_2_SUPABASE_MIGRATION_PLAN.md` **§8 acceptance property**.

**Second acceptance property — the four declared edge sets are identical.** The dependency graph is written
down in **four** places: `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §2's mermaid DAG, that plan's §3 rollout
table, §2.1 above, and the JSON `depends_on` in §3. **They must be the same set, exactly** — not merely
compatible, and not merely "the mermaid is a superset". Three of the four instances found so far
(`079 → 085`, `085 → 088`, `086 → 087`) were caught only because someone read the prose; the fourth
(`077 → 082` / `078 → 082`) was caught because a new table's FK could not be declared without it.

> **Verified mechanically by the replay-ordering pass (`R2B`, 2026-08-28), after every commit.** All four
> sets enumerate the **same 45 edges**. Every declared dependency **strictly precedes** its dependent by
> package number, so the graph is acyclic and topologically ordered by number. The mermaid edge set
> **equals** the declared edge set — no edge is in one and not the others. **The check is a parser over the
> four surfaces, not a reading**: it extracts the mermaid `-->` pairs, the §3 rollout table's *Depends on*
> column, §2.1's table and the JSON `depends_on`, asserts set equality four ways, asserts
> `declared_edge_count` equals the set size, asserts every edge increases the package number, **and greps
> both documents for any prose statement of an edge count that disagrees** — which is the check the K-2
> repair lacked when it left four stale *"38"* statements behind, one of them the JSON's own parity
> attestation.

---

## 3. Machine-readable

```json
{
  "schema_version": 2,
  "ratified": "2026-08-27",
  "amended": "2026-08-27",
  "amendment_status": "PENDING_RE_RATIFICATION",
  "amendment_count": 7,
  "declared_edge_count": 66,
  "edge_set_parity_verified": "66 edges, four surfaces identical (OR-17 applied 2026-08-29; re-verify by chain-parse on application)",
  "amendment_summary": "Delta-spec integration. Structural: kernel.approval_request placed in 077 (it had no package and no home). Scope: 083 and 087 renamed; seven dependency edges added (an eighth, 086 -> 087, added later by the final reconciliation pass as a declaration-only correction); per-package object sets extended. FOURTH AMENDMENT (K-2/K-3): kernel.identity_contact_pref_event placed in 077 and kernel.org_contact_consent_event placed in 082 — both were contracted by four documents and created by none; 087 names the three purge definers and assert_may_request explicitly and gains the export_job purge substrate; two declaration-only edges added, 077 -> 082 and 078 -> 082, bringing the declared edge count to 38. Count unchanged at 16 unless COND-B (notify) is ruled Gate P. FIFTH AMENDMENT (AUTHZ-PKG1 — the reviewer-conditions pass): the four venue-plane read policies move from 078/079 into 080 so the forward reference to has_venue_role ceases to exist rather than being declared; one declaration-only edge 079 -> 080; declared_edge_count 38 -> 39. SIXTH AMENDMENT (MB-2…MB-5, MN-2, MN-4 — the unwritable-control pass): six controls that were specified, ratified and relied on had no physical substrate or no writer. kernel.payout gains hold_state/hold_reason_code/held_by/held_at (085) because status='held' never existed and adding it is lossy; kernel.mark_payout_transfer_state (085) and the venue.on_payout_settled SEAM-2 hook (stub 085, body 087) because paid/failed/reversed, stripe_transfer_ref and venue.settlement.status='paid' had no writer; kernel.tg_custody_head_is_ledger_tail (079) because the verify trigger the constitution names three times existed in no package; the two platform sentinel identities SN-VOID and SN-SYSTEM seeded in 078 because two NOT NULL FK->auth.users columns were satisfied by rows nothing created; kernel.sweep_expired_ticket_atoms (079) because tickets.state='expired' had no writer. NO package added, renamed or renumbered; NO dependency edge added — declared_edge_count is 39 after the merge -- the unwritable-control pass added none, and the single addition is the conditions pass's AUTHZ-PKG1 edge 079 -> 080; all four surfaces re-verified identical at merge. SEVENTH AMENDMENT (R2B -- the replay-ordering pass): plpgsql bodies are not validated at CREATE FUNCTION, so the routine layer replayed green and failed at runtime. C116/S2-A: the composite kernel.settlement_line_candidate, declared as the RETURNS SETOF type of two SEAM-2 stubs and created by nothing anywhere, is scheduled in 087 immediately before them (42704 otherwise). C117/S2-B: market.on_atom_voided had a two-parameter summary in plan 0.4b and schema 13.2 against RPC 20.11.3's three-parameter contract under a CREATE OR REPLACE that can neither add nor rename a parameter; the three-parameter form is canonical and new rule SEAM-2a freezes every hook's parameter list, parameter names and return type at the stub. SEAM-1 is corrected to take max() over reads, writes AND calls. The hook count is corrected from three to four in plan 0.4b -- venue.on_payout_settled (C92) was in this JSON and in neither prose enumeration. NO package added, renamed or renumbered; R2B/C111 moves venue.finalize_primary_order from 082 to 085 (it writes kernel.payment_native) and stubs venue.resolve_order_attribution there as a SEAM-2 hook replaced in 090 (moving to 090 would author the primary purchase path inside the promoter package, and RPC 17.14 requires that callee never raise); R2B/C114 moves kernel.issue_ticket_atoms from 081 to 083 (it reads kernel.signing_key -- FR-3's criterion applied to the other kernel engine), adding the declared edge 081 -> 083; R2B/C113 adds the venue.append_door_manifest_delta SEAM-2 hook (stub 083, body 086) so that four call sites in three earlier packages resolve the name. Count unchanged at 16. EIGHTH AMENDMENT (OR-17 -- F-P0-1 Option A, the deletion state machine folded into the ratified band): 077 gains the substrate (3 identity_ext columns + pending index), the request/withdraw RPCs, the freeze predicate, the completion sweep + its own cron entry, and NINE deletion SEAM-2 stubs whose bodies land in 079/080/082/083/085/086/088/090; F-clauses authored in their host RPCs' packages; the two deletion notice seeds stay in 092 (BE emit + durable FK-free 076 outbox make that compose with the <=077 cutover); four declared edges added (077->081, 077->083, 077->086, 077->088), declared_edge_count 62 -> 66; seed count 29 -> 31 (OR-15 corrigendum, owner-stamped with OR-17). NINTH AMENDMENT (OR-21 -- F-P2-1 obligation record): kernel.identity_obligation + record_/resolve_identity_obligation + has_outstanding_obligations in 085 (SEAM-1 max(077,085)=085, edge pre-declared, NONE added); the BP-10 predicate stub joins the 077 stub set -- hook_count 8 -> 18 total. NO package added, renamed or renumbered; 084 and 091 untouched; band 076-092, count 17.",
  "canonical_source": "docs/architecture/PHASE_2_PACKAGE_REGISTRY.md",
  "placement_record": "docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md#13",
  "package_specification": "docs/architecture/PHASE_2_SUPABASE_MIGRATION_PLAN.md#8",
  "applied_max": "075",
  "phase2_range": { "first": "076", "last": "092", "count": 17 },
  "seam_rules": {
    "SEAM-1": "A function is authored in the package equal to max() of the packages creating every table it reads, every table it writes, AND every table it reaches through a call. A called routine contributes its own package in its own right; a column counts as a table. CORRECTED by R2B: the pre-R2B form took max() over directly-named tables only, which cannot see a forward reference one call away.",
    "SEAM-2": "Where an earlier artifact must resolve the name, the earlier package ships a hook stub returning the neutral result and the later package CREATE OR REPLACEs only that hook.",
    "SEAM-2a": "A hook's parameter list, parameter NAMES and return type are frozen at the stub; CREATE OR REPLACE may change only the body. Adding a parameter creates a silent overload that leaves the stub bound to every call site; renaming one is a hard 42P13. The replacing package asserts COUNT(*)=1 over pg_proc for the hook name and proargnames/proargtypes/prorettype identity with the stub.",
    "acceptance_property": "No function reads, writes, or reaches through a call any table created in a later package. The pg_depend walk that proves it must be transitive over routine->routine edges.",
    "hook_count": 18,
    "hooks": [
      { "name": "kernel.settlement_royalty_lines", "signature": "(p_settlement_id uuid) RETURNS SETOF kernel.settlement_line_candidate", "stub_in": "087", "replaced_in": "088", "neutral_result": "zero rows" },
      { "name": "kernel.settlement_commission_lines", "signature": "(p_settlement_id uuid) RETURNS SETOF kernel.settlement_line_candidate", "stub_in": "087", "replaced_in": "090", "neutral_result": "zero rows" },
      { "name": "market.on_atom_voided", "signature": "(p_atom_id uuid, p_refund_id uuid, p_cause text) RETURNS void", "stub_in": "085", "replaced_in": "088", "neutral_result": "no-op", "r2b_note": "S2-B/C117: plan 0.4b and schema 13.2 (twice) carried a two-parameter (atom_id, refund_id) summary against RPC 20.11.3's three-parameter contract. Canonical is the three-parameter form. Stub-at-two/replacement-at-three is a silent overload that leaves the C26 compensate arm dead in production; same-arity/different-names is a hard 42P13 at 088 replay. p_cause's admissible values are contracted nowhere -- filed to the RPC owner as R2B-1, and SEAM-2a means a ruling that drops it must land before 085 is authored." },
      { "name": "venue.append_door_manifest_delta", "signature": "(p_session_id uuid, p_atoms uuid[], p_op text, p_cause_ref uuid) RETURNS void", "stub_in": "083", "replaced_in": "086", "neutral_result": "no-op", "added_by": "R2B/C113", "seam1": "real body appends to venue.door_manifest_delta (086) -> body is 086; the stub sits in 083 because SEAM-2 places a stub in the package of the EARLIEST caller, and that is kernel.issue_ticket_atoms (083 after C114)", "callers": ["kernel.issue_ticket_atoms (083, op=add, RPC 6.3)", "kernel.void_ticket_atom / kernel.admin_refund / kernel.force_void_ticket (085, op=revoke, RPC 12.4c)", "venue.issue_comp and the manifest RPCs (086)", "catalog.cancel_event and market.sweep_paid_pending_sales compensate (088)"], "safety_note": "This is the one hook whose neutral result would be UNSAFE if it outlived its replacement: a missed op=add fails closed, a missed op=revoke fails OPEN (an offline scanner admits a voided atom). It is correct at 083-085 only because no manifest episode, no scanner and no offline window can exist before 086, which is why 086 asserts the replaced body is live." },
      { "name": "venue.resolve_order_attribution", "signature": "(p_order_id uuid) RETURNS void", "stub_in": "085", "replaced_in": "090", "neutral_result": "writes no venue.attribution row and NEVER raises", "added_by": "R2B/C111", "seam1": "real body reads venue.promoter_code/_scope/promoter_link/promoter and writes venue.attribution, all 090 -> body is 090; the stub sits in 085 because its only caller, venue.finalize_primary_order, is authored there by C111", "neutral_result_source": "RPC 17.14, verbatim: every non-happy path resolves to no attribution row, and the function never raises because a raise here would roll back the money and the tickets. The stub IS the contract, not an approximation of it.", "why_not_a_move": "max() taken literally would author venue.finalize_primary_order -- SSCAS member #1, the function that mints every atom in the system -- inside the promoter package, eight packages from the order it finalizes." },
      { "name": "market.on_door_freeze_engaged", "signature": "(p_event_session_id uuid, p_cause_ref uuid) RETURNS TABLE (drained_transfers integer, drained_listings integer, atoms_unlocked integer)", "stub_in": "086", "replaced_in": "088", "neutral_result": "drains nothing, returns (0,0,0)", "added_by": "R2B/C110", "seam1": "real body writes market.p2p_transfer and market.listing_native (088) and unlocks through kernel.unlock_ticket (079) -> body is 088; the stub sits in 086 because venue.open_door_manifest is authored there and moving IT to 088 would make the Phase-2B door gate depend on the native-resale rail, which is gated behind Gate-M + Phase 2C", "boundary_note": "A venue function writing market tables directly was already a section 0.7 modular-monolith violation before it was an ordering one. RPC 17.12 names the sanctioned construction -- the owning schema exposes a definer primitive and the calling schema invokes it in the same transaction -- citing record_scan -> mark_ticket_scanned and open_door_manifest -> engage_door_freeze. market.on_atom_voided is the same construction one direction over.", "lock_order_note": "Runs in the caller's transaction; takes rank 4 inside the caller's rank-1 session lock, exactly as on_atom_voided takes rank 4 inside void_ticket_atom. SSCAS classification unchanged: a bounded batch of members #6-reverse and #7-reverse. No sixteenth member." },
      { "name": "market.door_freeze_drain_preview", "signature": "(p_event_session_id uuid) RETURNS TABLE (pending_transfers integer, active_listings integer, excluded_paid_pending integer, atoms_to_unlock integer)", "stub_in": "086", "replaced_in": "088", "neutral_result": "four zeroes", "added_by": "R2B/C110 (defect V7, found by this pass and not previously filed)", "seam1": "venue.preview_door_open_impact (086, RPC 20.6.3) returns counts over market.p2p_transfer, market.listing_native and market.market_sale.sale_state=paid_pending_transfer -- three 088 relations read from 086. It is the confirm dialog's prerequisite, so it raises BEFORE the open the operator is trying to reach." },
      { "name": "venue.on_payout_settled", "signature": "(p_payout_id uuid) RETURNS void", "stub_in": "085", "replaced_in": "087", "neutral_result": "no-op", "added_by": "MB-2b", "seam1": "real body reads kernel.payout (085) and writes venue.settlement (087) -> max(085,087)=087; 085 -> 087 already declared, no edge added", "r2b_note": "This is the FOURTH hook. Plan 0.4b and schema 13.2 both said 'SEAM-2 is used exactly three times' and listed three, omitting this one -- reopening ratified row C92 in the two DDL-authoritative documents. Plan 0.4b corrected by R2B; schema 13.2 reported to its owner." },
      { "name": "kernel.deletion_blockers_custody", "signature": "(p_identity uuid) RETURNS text", "stub_in": "077", "replaced_in": "079", "neutral_result": "NULL (no blocker)", "added_by": "OR-17", "predicate": "BP-1", "safety_note": "Neutral-if-outlived is UNSAFE (an account with live custody could tombstone); correct at 077-078 only because kernel.tickets does not exist; 079 asserts the real body is live." },
      { "name": "kernel.deletion_blockers_orders", "signature": "(p_identity uuid) RETURNS text", "stub_in": "077", "replaced_in": "082", "neutral_result": "NULL", "added_by": "OR-17", "predicate": "BP-12 pending-order arm" },
      { "name": "kernel.deletion_blockers_wallet", "signature": "(p_identity uuid) RETURNS text", "stub_in": "077", "replaced_in": "083", "neutral_result": "NULL", "added_by": "OR-17", "predicate": "BP-2" },
      { "name": "kernel.deletion_blockers_money", "signature": "(p_identity uuid) RETURNS text", "stub_in": "077", "replaced_in": "085", "neutral_result": "NULL", "added_by": "OR-17", "predicate": "BP-5 + BP-6 kernel arm + BP-12 refund/paid-window arm; live public.transfers analog stays in the sweep body" },
      { "name": "kernel.deletion_blockers_market", "signature": "(p_identity uuid) RETURNS text", "stub_in": "077", "replaced_in": "088", "neutral_result": "NULL", "added_by": "OR-17", "predicate": "BP-3 + BP-4" },
      { "name": "kernel.on_identity_erased_staff", "signature": "(p_identity uuid) RETURNS void", "stub_in": "077", "replaced_in": "080", "neutral_result": "no-op", "added_by": "OR-17", "cleanup": "INV #23/#24" },
      { "name": "kernel.on_identity_erased_door", "signature": "(p_identity uuid) RETURNS void", "stub_in": "077", "replaced_in": "086", "neutral_result": "no-op", "added_by": "OR-17", "cleanup": "INV #29-#31" },
      { "name": "kernel.on_identity_erased_market", "signature": "(p_identity uuid) RETURNS void", "stub_in": "077", "replaced_in": "088", "neutral_result": "no-op", "added_by": "OR-17", "cleanup": "16d hard-delete allowance: draft/cancelled listings + non-accepted offers ONLY; sold/completed retained" },
      { "name": "kernel.on_identity_erased_promoter", "signature": "(p_identity uuid) RETURNS void", "stub_in": "077", "replaced_in": "090", "neutral_result": "no-op", "added_by": "OR-17", "cleanup": "INV #36 only; venue.promoter row SURVIVES (16d)" },
      { "name": "kernel.has_outstanding_obligations", "signature": "(p_identity_id uuid) RETURNS boolean", "stub_in": "077", "replaced_in": "085", "neutral_result": "false (true-not-inert: no origin object exists before 085)", "added_by": "OR-21", "predicate": "BP-10 operand (kernel.identity_obligation.status=outstanding)" }
    ],
    "grants": {
      "note": "crm_export_builder grant map REMOVED by owner ruling OR-1 (O17/MD-2 ruled B: postgres-owned, 2026-08-28): the role is not created, the thirteen grants are not authored, and zero _sel_svc_export policies exist. The full thirteen-grant enumeration and its SEAM-4 derivation are preserved in _governance/PHASE_2_RATIFICATION_RECORD.md row C115 and _governance/O17_RULING_IMPACT_MAP.md (C-20). edges_added was 0 -- the evidence that the revert adds or removes no DAG edge (class E empty)."
    },
    "types": [
      { "name": "kernel.settlement_line_candidate", "created_in": "087", "kind": "composite", "columns": "cause text, cause_ref uuid, amount_minor bigint, currency text, payee_kind text, payee_id uuid", "source": "PHASE_2_RPC_FUNCTION_CONTRACTS.md#20.11.1", "r2b_note": "S2-A/C116: declared as the RETURNS SETOF type of settlement_royalty_lines and inherited by settlement_commission_lines, and created by nothing anywhere -- exactly one occurrence in the repository. 087 fails 42704 without it. A named composite rather than two RETURNS TABLE lists because the shape is the return type of four routine definitions across three packages and CREATE OR REPLACE cannot change a return type. Physical definition filed to the schema-spec owner." }
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
      "unaffected": ["crm_export", "demographics", "money_authority"], "unaffected_note": "promoter_codes removed 2026-08-29 (B-5): OR-3 ruled #31 KEEP and #32 CARRIER-RELEVANT",
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
    { "new": "076", "old": "071", "package": "A", "phase": "A", "name": "076_create_phase2_schemas_and_grants", "purpose": "schema skeleton", "scope": "4 schemas + GRANT boundary + shared helper functions/triggers; OR-12/OR-4: CREATE SCHEMA notify + notify.outbox (C12 envelope, zero FK deps) + notify.emit_event (best-effort) + notify.emit_event_required (raising, OR-14 R2)", "depends_on": [], "rollback_posture": "REVERSIBLE" },
    { "new": "077", "old": "072", "package": "B", "phase": "B", "name": "077_kernel_identity_orgs_and_roles", "purpose": "organizations + permissions + dual-control substrate", "scope": "identity_ext (+locale), organization (+payout_destination_set_by), org_member (six org labels, +granted_at), org_invite (six org labels), platform_role, admin_audit, approval_request (+required_approver_class), identity_demographic(_erasure), identity_contact_pref, identity_contact_pref_event (AO), org_customer_key + role predicates; OR-17: identity_ext +deletion_state/+deletion_requested_at/+deletion_block_reason (+OPEN-3 marker cell) + pending partial index, request/withdraw_account_deletion, is_deletion_pending, sweep_deletion_pending + cron entry, the TEN deletion SEAM-2 stubs (incl. the OR-21 BP-10 predicate), F-6 clauses; cutover deploy artifacts: delete-account edge switch + F-5 live-rail guards (FR-9) — TWELVE tables", "depends_on": ["076"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["kernel.approval_request", "kernel.approval_request.required_approver_class", "kernel.org_member.granted_at", "kernel.identity_demographic", "kernel.identity_demographic_erasure", "kernel.identity_contact_pref", "kernel.org_customer_key", "kernel.organization.payout_destination_set_by", "kernel.identity_ext.locale", "kernel.identity_contact_pref_event"], "k2_added": ["kernel.identity_contact_pref_event"] },
    { "new": "078", "old": "073", "package": "C", "phase": "C", "name": "078_catalog_reference_data_and_flags", "purpose": "catalog + all config/flag seeds", "scope": "catalog.venue/event/event_session/platform_config (+visibility, split read)/resale_policy + every feature-flag and config seed in the chain", "depends_on": ["077"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["catalog.platform_config.visibility", "catalog.event.description", "catalog.event.hero_image_ref", "catalog.event.category", "catalog.event.genre_tags", "catalog.event_session.session_version", "catalog.effective_freeze_at", "kernel.money_role_grant_matured"], "mb5_added": ["SN-VOID auth.users seed 00000000-0000-0000-0000-0000000000f0", "SN-SYSTEM auth.users seed 00000000-0000-0000-0000-0000000000f1", "matching public.profiles and kernel.identity_ext rows"], "mb5_note": "kernel.ticket_ownership_log.to_identity and .actor_identity are NOT NULL FK->auth.users and are relied on by void_ticket_atom and every custody sweep; no package seeded either row, so the first refund and every sweep failed 23503. TWO sentinels, not one (a custody destination and an actor answer different questions) and not three. The applied 019 anonymization sentinel 00000000-...-000000000000 is NOT reusable: different meaning, renders as 'Deleted User' on the dispute surface, owned by a public-schema deletion path, and person-shaped. Seeded in 078 because 078 is the every-seed-row package; SEAM max(precondition,077,078)=078; 078->077 and 078->079 already declared, no edge added. Schema §1.16.", "seam1_note": "kernel.money_role_grant_matured is authored HERE, not in 077 beside has_org_role: it reads kernel.org_member (077) AND catalog.platform_config plus its authn.money_role_maturity_hours seed (078), so max(077,078)=078. 078 already depends on 077, so no edge is added. RPC contract §1.1e (AUTHZ-C1C)." },
    { "new": "079", "old": "074", "package": "D", "phase": "D", "name": "079_kernel_ticket_atom_and_ownership_log", "purpose": "ticket kernel", "scope": "kernel.tickets + kernel.ticket_ownership_log (C26 idempotency) + the complete transfer-freeze input set", "depends_on": ["076", "077", "078"], "rollback_posture": "FORWARD_FIX_ONLY", "delta_added": ["kernel.door_freeze_override", "kernel.is_transfer_frozen", "kernel.tickets.resale_state:refund_hold"], "mb4_added": ["kernel.tg_custody_head_is_ledger_tail"], "mb4_note": "The head-equals-log-tail verify trigger named three times in SNATCH_IT_DOMAIN_ARCHITECTURE.md and cited by door §7.6 as what makes bypass structurally impossible existed in no package. CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED on kernel.tickets; asserts to_identity and credential_version_after of the greatest-sequence log row equal the head. state is deliberately outside the clause set. SEAM-1 max(079,079)=079; no edge, no package change. Schema §1.6.2. Also carries kernel.sweep_expired_ticket_atoms (MN-4, schema §1.5.1), SEAM-1 max(078,079)=079.", "mn4_added": ["kernel.sweep_expired_ticket_atoms"] },
    { "new": "080", "old": "075", "package": "E1", "phase": "E", "name": "080_venue_staff_roles_and_predicates", "purpose": "inventory (roles)", "scope": "venue.staff_role (six canonical labels, text+CHECK) + has_venue_role/has_event_role/has_org_role_over_venue/has_org_role_over_event + the four venue-plane READ POLICIES deferred from 078/079 (catalog_venue_sel_venue, catalog_event_sel_venue, catalog_event_session_sel_venue, kernel_tickets_sel_venue) -- AUTHZ-PKG1", "depends_on": ["076", "077", "078", "079"], "rollback_posture": "CLEAN_WHILE_EMPTY" },
    { "new": "081", "old": "076", "package": "E2", "phase": "E", "name": "081_venue_inventory", "purpose": "inventory (capacity)", "scope": "ticket_type, inventory_batch, inventory_batch_shard, inventory_movement, inventory_hold + catalog.publish_event; kernel.issue_ticket_atoms MOVED OUT to 083 by R2B/C114", "depends_on": ["077", "078", "080"], "rollback_posture": "CLEAN_WHILE_EMPTY" },
    { "new": "082", "old": "077", "package": "F", "phase": "F", "name": "082_venue_orders", "purpose": "orders", "scope": "venue.order (+attribution_candidate_code_id/_link_id, moved IN from 090 by R2B/C112, FKs adopted in 090) + venue.order_item + kernel.org_contact_consent + kernel.org_contact_consent_event (AO); venue.finalize_primary_order MOVED OUT to 085 by R2B/C111", "depends_on": ["077", "078", "081"], "depends_on_added_by_k2_repair": ["077", "078"], "depends_on_note": "077 is FORCED by kernel.org_contact_consent_event.org_id -> kernel.organization; 078 is a co-located pre-existing under-declaration (venue.order.event_session_id -> catalog.event_session). Both were already named in migration plan section 8/082 Dependencies prose while all four declared sets said [081]. Declaration-only: 077 < 078 < 081 < 082, so ordering was never wrong.", "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["kernel.org_contact_consent"], "k2_added": ["kernel.org_contact_consent_event"] },
    { "new": "083", "old": "078", "package": "G1", "phase": "G", "name": "083_kernel_credential_infrastructure", "purpose": "credential infrastructure", "scope": "kernel.signing_key + pass_type_cert + wallet_pass + wallet_pass_device + wallet_pass_push_log + .pkpass bucket (public key / KMS handle refs only, no key material) + kernel.issue_ticket_atoms (R2B/C114, moved from 081) + the venue.append_door_manifest_delta SEAM-2 stub (R2B/C113)", "depends_on": ["076", "077", "078", "079", "081"], "r2b_added": ["kernel.issue_ticket_atoms", "venue.append_door_manifest_delta (stub)"], "r2b_note": "C114/V5: issue_ticket_atoms reads kernel.signing_key (083) per RPC 7.1 and pins signing_key_id on every minted atom, and writes venue.inventory_batch(_shard)/inventory_movement (081) and kernel.tickets/ticket_ownership_log (079) -> max(078,079,081,083)=083. This is FR-3's decided criterion applied to the other kernel engine. New declared edge 081 -> 083. C113/V4+V6: the append_door_manifest_delta stub lives here because SEAM-2 puts a stub in the package of the earliest caller, and the earliest caller is issue_ticket_atoms in this package.", "rollback_posture": "CLEAN_WHILE_EMPTY", "renamed_from": "083_kernel_signing_key", "delta_added": ["kernel.pass_type_cert", "kernel.wallet_pass", "kernel.wallet_pass_device", "kernel.wallet_pass_push_log"] },
    { "new": "084", "old": "079", "package": "G2", "phase": "G", "name": "084_kernel_tickets_late_binding_fks", "purpose": "credential infrastructure (ADOPT)", "scope": "late-binding FKs kernel.tickets -> ticket_type + signing_key, and nothing else", "depends_on": ["079", "081", "083"], "rollback_posture": "REVERSIBLE", "invariant": "Creates zero relations and zero routines. This purity is what makes its rollback unconditionally reversible; nothing may be added to it." },
    { "new": "085", "old": "080", "package": "M", "phase": "F/I bridge", "name": "085_kernel_money_native", "purpose": "kernel money-native + money authority", "scope": "kernel.payment_native, kernel.refund, kernel.payout (+hold_state/hold_reason_code/held_by/held_at), void_ticket_atom + on_atom_voided stub, the nine money-authority RPCs, mark_payout_transfer_state + the venue.on_payout_settled stub; S-24/S-25: kernel.mark_refund_state + the stripe_refund_ref partial unique + its pairing CHECK; R2B/C111: venue.finalize_primary_order (moved from 082) + the venue.resolve_order_attribution SEAM-2 stub; C112 move 2026-08-29: kernel.payment_native.instrument_fingerprint (writer venue.finalize_primary_order authored here; RPC 6.3; the 090 detector reads it)", "depends_on": ["076", "077", "078", "079", "081", "082", "083"], "depends_on_added_by_r2b": ["078", "081", "083"], "depends_on_note": "081 and 083 are FORCED by C111 moving venue.finalize_primary_order here (it writes venue.inventory_batch(_shard)/inventory_movement, and calls kernel.issue_ticket_atoms authored in 083 by C114). 078 was ALREADY OWED before R2B: this package reads catalog.platform_config for the refund/payout/authn thresholds (its own Feature-flags row says so) and calls kernel.money_role_grant_matured, authored in 078 -- the fifth instance of the under-declaration shape after 079->085, 085->088, 086->087 and 077/078->082. All three are declaration-only for ordering; 078 < 081 < 083 < 085.", "rollback_posture": "FORWARD_FIX_ONLY", "mb2_added": ["kernel.payout.hold_state", "kernel.payout.hold_reason_code", "kernel.payout.held_by", "kernel.payout.held_at", "kernel.mark_payout_transfer_state", "venue.on_payout_settled (stub)"], "mb2_note": "MB-2a: kernel.payout.status='held' was relied on by MONEY §8.4/§12, ratification O-3, RPC §17.7 and dashboard §14.5, and was never a member of the status set. It is NOT added to status (that is lossy and makes RPC §11.3 release unimplementable); a hold is an orthogonal column, the same shape as the frozen public.transfers.payout_review_status discipline hold_payout is contracted to extend. MB-2b: paid/failed/reversed and stripe_transfer_ref had no writer; mark_payout_transfer_state (SEAM-1 max(077,085)=085) is the writer. No package, edge or renumbering added. Schema §1.9.1/§1.9.2.", "s24_added": ["kernel.mark_refund_state", "kernel.refund partial UNIQUE (stripe_refund_ref) WHERE stripe_refund_ref IS NOT NULL", "kernel.refund CHECK (status = 'pending' OR stripe_refund_ref IS NOT NULL)"], "s24_note": "S-24 (plan, 2026-08-29) / S-25 (this registry, same day): three of kernel.refund.status's four labels and the Stripe join key had no writer in the scheduled chain. Contract RPC 20.7.7; ratifications C101 (status writers) and C102 (stripe_refund_ref); schema 1.10.1. SEAM-1: writes kernel.refund (085) and kernel.admin_audit (077) -> max(077,085)=085; 077 already in depends_on, NO edge added. Package-registry transcription of a placement the schema settled; no semantics, grants, RLS or dependency change.", "fp21_added": ["kernel.identity_obligation", "kernel.record_identity_obligation", "kernel.resolve_identity_obligation", "kernel.has_outstanding_obligations"], "fp21_note": "F-P2-1/OR-21 obligation record: one table + two verbs + the BP-10 read predicate. SEAM-1 max(077,085)=085 (writes identity_obligation 085 + admin_audit 077; 077 already in depends_on, NO edge added). has_outstanding_obligations is SEAM-2: stub in 077 (deletion machine, OR-17 fold) returning false -- true-not-inert, no origin object exists before 085 -- CREATE OR REPLACEd here, signature frozen SEAM-2a. No package, edge, or renumbering added; 091 remains stub-only." },
    { "new": "086", "old": "081", "package": "H", "phase": "H", "name": "086_venue_door_and_scan", "purpose": "scan infrastructure + door manifest + holder mix", "scope": "door_pin, door_session, scan_device, scan (+actor_identity_id, +manifest_id), comp_allocation, guest_list, guest_entry, door_manifest(_entry/_delta), holder_mix_snapshot, holder_mix_bucket; R-7a: venue.unpublish_holder_mix + unpublish_all_holder_mix + reconcile_holder_mix (RPC 17.20; SEAM-1 max(077,086)=086; scheduled 2026-08-29 -- RC-5 contracted-never-built closed)", "depends_on": ["076", "077", "078", "079", "080", "081", "083"], "rollback_posture": "CLEAN_WHILE_EMPTY", "delta_added": ["venue.door_session", "venue.door_manifest", "venue.door_manifest_entry", "venue.door_manifest_delta", "venue.holder_mix_snapshot", "venue.holder_mix_bucket", "venue.scan.actor_identity_id", "venue.scan.manifest_id", "venue.scan_device.manifest_id"] },
    { "new": "087", "old": "082", "package": "I", "phase": "I", "name": "087_venue_settlement_and_export", "purpose": "settlement + CRM export", "scope": "TYPE kernel.settlement_line_candidate (R2B/C116) + venue.settlement + venue.settlement_line + venue.export_job (incl. the purge substrate artifact_state / purge_lease_until / purge_attempts and the (artifact_state, expires_at) claim index) + crm-exports bucket + close_settlement and its two hook stubs + the three purge-agent definers + assert_may_request", "depends_on": ["077", "081", "085", "086"], "depends_on_added_by_reconciliation": ["086"], "edge_functions": [ { "name": "crm-export", "routes": ["POST /download"], "class": "A", "verify_jwt": true, "worker_secret_in_env": false }, { "name": "crm-export-worker", "routes": ["POST /build", "POST /purge"], "class": "B", "verify_jwt": true, "worker_secret_in_env": true, "worker_header": "X-Crm-Export-Worker", "secret_name": "CRM_EXPORT_WORKER_SECRET", "never_compared_against": "SUPABASE_SERVICE_ROLE_KEY" } ], "cron_schedules": [ { "target": "crm-export-worker", "route": "POST /build", "cadence": "1 minute", "header": "X-Crm-Export-Worker" }, { "target": "crm-export-worker", "route": "POST /purge", "cadence": "15 minutes", "header": "X-Crm-Export-Worker", "note": "daily orphan reconciliation rides this route" } ], "mb2_added": ["venue.on_payout_settled (real body; stub in 085)", "venue.settlement.status='paid' writer"], "rollback_posture": "CLEAN_WHILE_EMPTY", "renamed_from": "087_venue_settlement", "delta_added": ["venue.export_job", "storage.buckets:crm-exports"], "k3_named": ["venue.claim_artifacts_for_purge", "venue.confirm_artifact_purged", "venue.reconcile_export_orphans", "venue.assert_may_request", "venue.export_job.artifact_state", "venue.export_job.purge_lease_until", "venue.export_job.purge_attempts", "index:venue.export_job(artifact_state, expires_at)"], "k3_note": "The three purge definers reached migration plan section 8/087 by the final reconciliation pass but were named nowhere here and had no physical substrate in the schema spec. max(087 venue.export_job, 077 kernel.admin_audit) = 087 by SEAM-1; 087 already declares 077, so no edge is created. This is the only agent in the design that deletes bytes." },
    { "new": "088", "old": "083", "package": "J1", "phase": "J", "name": "088_market_native_rail", "purpose": "native marketplace rail + custody engine", "scope": "listing_native, auction, offer, market_sale, p2p_transfer, transfer_ticket_ownership, catalog.cancel_event; R-37/OR-22: checkout_buy_now, bind_checkout_payment_ref, finalize_market_sale, cancel_buy_now_sale, list_lapsed_checkouts, listing_native.status+reserved, market_sale.sale_state+cancelled, market_sale.reservation_expires_at, market_sale.payment_intent_ref, uq(listing_id) WHERE initiated, resale-checkout edge (verify_jwt true; /begin /release Class A, /sweep-lapsed B-i) + its 2-min pg_net cron. No depends_on change (every read/write/call inside the declared closure; the 20.8.7 max arithmetic)", "depends_on": ["076", "077", "078", "079", "081", "085", "086", "087"], "depends_on_added_by_r2b": ["086", "087"], "depends_on_note": "086 is added by C110 (this package CREATE OR REPLACEs market.on_door_freeze_engaged and market.door_freeze_drain_preview, stubbed in 086). 087 is added by C118 and was ALREADY OWED: this package CREATE OR REPLACEs kernel.settlement_royalty_lines, whose stub is created in 087. A stub-replacement edge left undeclared is not a missing name -- run the replacement first and the stub silently overwrites the real body with the neutral one, green replay and all. Both declaration-only for ordering (086 < 087 < 088).", "rollback_posture": "CLEAN_WHILE_EMPTY", "restores_hooks": ["kernel.settlement_royalty_lines", "market.on_atom_voided", "market.on_door_freeze_engaged", "market.door_freeze_drain_preview"] },
    { "new": "089", "old": "084", "package": "J2", "phase": "J", "name": "089_market_bridge_view_and_late_fk", "purpose": "native marketplace bridge (ADOPT)", "scope": "market.listing_unified VIEW + adopt payment_native.sale_id FK", "depends_on": ["085", "088"], "rollback_posture": "REVERSIBLE" },
    { "new": "090", "old": "085", "package": "2D", "phase": "2D", "name": "090_venue_promoter_engine", "purpose": "promoter engine", "scope": "venue.promoter (+tier/party_kind/commission_kind/commission_flat_minor), promoter_link (+status), attribution (+15 cols), promoter_code, promoter_code_scope, attribution_review, the cross-settlement commission unique (instrument_fingerprint MOVED to 085, C112, 2026-08-29)", "depends_on": ["076", "077", "078", "082", "085", "087"], "rollback_posture": "CLEAN_WHILE_EMPTY", "restores_hooks": ["kernel.settlement_commission_lines"], "delta_added": ["venue.promoter_link.status", "venue.promoter_code", "venue.promoter_code_scope", "venue.attribution_review", "venue.settlement_line:uq_promoter_commission_cause_ref", "venue.order:fk_order_attr_cand_code (ADOPT)", "venue.order:fk_order_attr_cand_link (ADOPT)"], "r2b_note": "C112/V3: the two venue.order candidate COLUMNS move to 082 because venue.create_primary_checkout (082) writes them -- a body writing a column a later package ADD COLUMNs is 42703, the same defect one SQLSTATE over. This package keeps the ADOPT step for both FK constraints, NOT VALID + VALIDATE, exactly as 084 and 089 do. No edge: 090 already declares 082." },
    { "new": "091", "old": "086", "package": "K", "phase": "K", "name": "091_kernel_reserve_stub", "purpose": "money-ledger stub", "scope": "kernel.reserve stub only (no writers)", "depends_on": ["077"], "rollback_posture": "REVERSIBLE", "invariant": "Always empty; no routine in the database references it." },
    { "new": "092", "old": null, "package": "N", "phase": "Gate P (reduced)", "name": "092_notify_reduced", "purpose": "reduced notification plane + outbox drainer (OR-5 [C]; OR-12)", "scope": "notify.notification_type, notification, delivery, preference, template, identity_channel_state (six tables; notify.outbox lives in 076 per OR-4); public.push_tokens +4 cols; the 16 reduced RPCs + notify.drain_outbox; edge notify-dispatch (1 min) + notify-receipts (15 min) cron; 31 notification_type seed rows (N3 closed + OR-15 + OR-17: account_deletion_pending, account_deletion_completed)", "depends_on": ["076", "077", "078", "079", "080", "082", "085", "090"], "depends_on_note": "B-7 derivation, adopted OR-12: 076 drain_outbox reads notify.outbox directly; 077 identity_ext.locale + org_member scope-roles; 078 catalog event/session + session_version + platform_config lease read; 079 kernel.tickets custody expansion; 080 venue.staff_role security-pair recipient derivation; 082 venue.order.buyer_id; 085 payout/refund; 090 promoter_link (#32 KEEP). Invariant across R1-R5 (R2 ruled, OR-14).", "rollback_posture": "CLEAN_WHILE_EMPTY" }
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
| **CANONICAL** | `076`–`092` | everywhere, after `OR-12` 2026-08-29 (`076`–`091` from 2026-08-27 until then) | — |

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
2. **Phase-2 packages occupy `076`–`092`** (`OR-12`)**.** No non-Phase-2 migration may claim a
   number in that band without a ratified amendment recorded in
   `docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md` and an update to
   this registry.
3. **New security hotfixes go above `091`**, or — if authored before Phase 2
   starts — require this registry to be re-ratified with a new shift. Do not
   silently consume a reserved number; that is precisely what produced the four
   competing scales in §4.
4. **One package, one version.** Verify against §2 before authoring.
5. This registry is updated **only** by ratified amendment.
6. **Function placement is derived, not chosen** (§2.2 SEAM-1/SEAM-2/SEAM-2a,
   SEAM-3, SEAM-4). A package that contains a routine reading, writing, **or
   reaching through a call** a relation or column created in a later package is
   malformed, regardless of how the object list looks. **The `max()` is over the
   REACHABLE set, not the named set** — that distinction is `R2B`'s whole
   finding, and the derivation must be re-run from each routine's **contract**
   (Reads · Writes · Preconditions · every routine named in its prose), never
   inherited from where the object list already sits. Full statement and the two
   forms of the mechanical check:
   `PHASE_2_SUPABASE_MIGRATION_PLAN.md` **§8 acceptance property**.
6b. **A hook's signature is frozen at its stub** (`SEAM-2a`). `CREATE OR REPLACE`
   may change only the body. The replacing package asserts `COUNT(*) = 1` over
   `pg_proc` for the hook name — an **overload count**, because the failure mode
   of adding a parameter is a second routine and a live stub, not an error.
6c. **A role with grants owed from package `N` is created at or before `N`**
   (`SEAM-4`). A `GRANT` resolves its grantee immediately, so a late role is a
   hard `42704` at replay rather than a runtime surprise.
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
envelopes); scanner push-to-sync; every notification. **Unaffected** *("promoter codes" struck 2026-08-29 — falsified by `OR-3` `#31`/`#32`; `B-5`)*: CRM export
(`pg_cron` + `pg_net` + a claim-lease), demographics, and money
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
