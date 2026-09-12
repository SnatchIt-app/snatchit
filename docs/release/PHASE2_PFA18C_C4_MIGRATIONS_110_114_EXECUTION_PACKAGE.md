# PFA-18C — C4 PRODUCTION EXECUTION PACKAGE: MIGRATIONS 110–114 (pre-authorization audit)

**Date:** 2026-09-09 (coordinator, Claude A; repository analysis + read-only production/AWS reads only) · **Nothing was applied, pushed, created, or mutated.** C2 not begun; no KMS key; production dark.
**Authoritative inputs:** PFA-18C ratification (`docs/architecture/_governance/PFA_18C_OWNER_RATIFICATION.md`), readiness packet (`docs/release/PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md`), execution record (sessions 5–14), C1 Phase-1 Gate Report rev 3 (`93dc8bd9…`), dark pre-ceremony audit (`1f3fc19`), `docs/operations/DEPLOYMENT_PATHS.md`, `AGENTS.md`/`CLAUDE.md`, the frozen constitutions and PFAs (18A parked, 18B available, 18C consumed-once, PT-6, PT-8).

---

## 0. Verdict

**READY FOR OWNER AUTHORIZATION** — the exact phrase **"AUTHORIZE PFA-18C MIGRATIONS 110-114"** is sufficient and safe to execute C4 **when scoped to the commit and hashes in §1 and subject to the day-of preflight in §6 (fresh `AUTODEPLOY-VERIFIED-OFF` date, owner visual confirmation that auto-deploy is OFF, and a dry run listing exactly the five migrations).** Nothing is executed by this package; the coordinator never runs the push. **Adversarial reviews (coordinator + two independent reviewers, §5): no blocking defect; four minor findings recorded with forward fixes (none alters the reviewed bytes): 114 L121 non-STRICT select (edge fails closed; body-only fix before C6), 086↔112/113 expired-episode drift (fix before scanning activation), 111 trigger-existence assumption (rollback ordering rule), ceremony-doc rotation artifact stale (doc note).**

Authorization is cryptographically scoped to:
- **Checkout/commit:** `admin/operating-console @ 562fda9aba261d7929ee772a4fd1ce50485c4294` (worktree `/Users/josetascon/snatchit-admin-console`, HEAD = that SHA, clean).
- **Migration bytes (SHA-256):**
```
3134f6f63e4ff1b100120508152eb696d9acf101a5a109e37a8938ba3d1f7390  supabase/migrations/110_signing_key_insert_guard.sql
d13cf6cba2b08742f8d397d8d0a2b508a10df9544119e174d73b0990d0507ac1  supabase/migrations/111_signing_key_recovery_two_person.sql
97d33d0862a6c8daa3728fdf9935cf8239ba953ccaafd2d12a63d0c15f73f9b7  supabase/migrations/112_get_door_manifest_headers.sql
32d42324b2b21667a17a3b31a6ff98e9df2d2a8dfd9ff98c5bad7ca1466fd88d  supabase/migrations/113_get_door_manifest_door_machine_authority.sql
9974eb91fd51acba9786c60366460e53a304807129600f46a197740b21455cee  supabase/migrations/114_signing_key_door_delivery_and_manifest_signing_context.sql
```
- **Rollbacks (SHA-256, reverse order 114 → 110, separate authorization if ever used):**
```
f61fee26fad6c378c263b8be2fd458c0ac30a67ecd99007bbc32c60a7bec3cb1  supabase/rollbacks/114_signing_key_door_delivery_and_manifest_signing_context_rollback.sql
4b9551535ed03f6e838a042a9f9269c95b0c12ee883f1e43cea9c86304c5dc6e  supabase/rollbacks/113_get_door_manifest_door_machine_authority_rollback.sql
ba1061893c18cb1ad43280d94482d074260795bae4d80be28b8989b37d1ef06e  supabase/rollbacks/112_get_door_manifest_headers_rollback.sql
1c4a282779467225629e357cbb32279659dea6badd00d95ea2c50d814010bd1e  supabase/rollbacks/111_signing_key_recovery_two_person_rollback.sql
933a2941cdc14070ac4b99846f0faa22e403e447d6eba851e1ea0881c1f6e798  supabase/rollbacks/110_signing_key_insert_guard_rollback.sql
```

---

## 1. Candidate checkout — re-verified 2026-09-09 (CLAUDE-OBSERVED)

| Item | Finding |
|---|---|
| Prior reference `admin/operating-console @ 2459bdc` | **stale** — the branch advanced to **`562fda9aba261d7929ee772a4fd1ce50485c4294`** (2026-09-08T04:51:54Z, "docs(admin): record the preview-failure root cause …"); docs-only since `ab3e17f`: `git diff --stat ab3e17f 562fda9 -- supabase/` is empty |
| CI on `562fda9` | green — CI run `34188504835`, Migrations guard run `34188507116` |
| PR carrying the tree | #55 (`admin/operating-console` → `feature/venue-native-and-product-v2`), OPEN, head `562fda9…`, body `AUTODEPLOY-VERIFIED-OFF: 2026-09-07` (**stale for apply day**) |
| Same bytes on the venue-native lineage | 110–114 identical on `feature/venue-native-and-product-v2 @ 93dc8bd9…` (PR #52, `AUTODEPLOY-VERIFIED-OFF: 2026-09-02`, stale); that tree lacks 115–120 and is therefore **not** usable for `db push` (the CLI would refuse: remote versions 115–120 not found locally) |
| Local worktree | `/Users/josetascon/snatchit-admin-console` at `562fda9…`, `git status` clean; linked project present (`supabase/.temp/linked-project.json`); no `supabase/config.toml` (none needed for `db push --linked`) |
| CLI | local `supabase` **2.115.0** = the CI pin (`ci.yml` `SUPABASE_CLI_VERSION: 2.115.0`); upstream 2.117.0 exists and is **not** adopted |
| Migration tree | 135 files; tail `110…114, 115…120, 2026…` (LC_ALL=C order); pgTAP suites 176–180 present |

## 2. Migrations 110–114 — filenames, hashes, order, dependencies

| # | File | SHA-256 (full above) | Creates / changes | Depends on | Census delta |
|---|---|---|---|---|---|
| 110 | `110_signing_key_insert_guard.sql` | `3134f6f6…` | `kernel.guard_signing_key_insert()` + BEFORE INSERT trigger on `kernel.signing_key`; `REVOKE ALL` on the function from public/anon/authenticated/service_role (L204) | 083 (DDL, immutable UPDATE guard), 103 (algorithm column), 093 resolver | kernel fns +1 |
| 111 | `111_signing_key_recovery_two_person.sql` | `d13cf6cb…` | table `kernel.signing_key_recovery_approval` (RLS on, **zero policies, zero grants**, append-only trigger via 076 `raise_append_only`); `kernel.signing_key_p256_pem_fingerprint(text)` (zero-grant); `kernel.approve_signing_key_recovery(uuid,text,text,text)` and `kernel.execute_signing_key_recovery(uuid,text,text,text,text)` — **granted to `authenticated`** (in-function authz: `kernel.is_platform(['platform_admin'])` + `aal2`, L166–179), revoked from public/anon/service_role; re-creates the 110 guard with rule 10 = two approvals | 110 (guard body), 077 idiom, 076, 106 idiom | kernel tables +1, kernel fns +3 |
| 112 | `112_get_door_manifest_headers.sql` | `97d33d08…` | body-only re-create of `venue.get_door_manifest(uuid, integer)` (086) adding `open/session_id/opened_at/not_after` header fields; no grant change | 086 | none |
| 113 | `113_get_door_manifest_door_machine_authority.sql` | `32d42324…` | `venue._get_door_manifest_core(uuid,integer)` (zero-grant, L93); `venue.get_door_manifest_door(uuid,uuid,text,uuid,integer)` (service_role only, L141–142; authorizes via `kernel.assert_door_session`); staff RPC body-only re-create delegating to the core | 112, 108 (`assert_door_session`) | venue fns +2 |
| 114 | `114_signing_key_door_delivery_and_manifest_signing_context.sql` | `9974eb91…` | `venue.get_signing_keys_door(uuid,uuid,text,uuid)` (service_role only, L101–102); `venue.get_manifest_signing_context()` (service_role only, L136–137) — both read `kernel.signing_key` only | 108, 083/103 projection | venue fns +2 |

**Apply order:** 110 → 111 → 112 → 113 → 114 (CLI = `LC_ALL=C` filename order). **Rollback order:** 114 → 113 → 112 → 111 → 110 (111's rollback re-creates the 110 guard body; 113's restores the 112 body). **No DML at apply time:** every statement is DDL/grant; the `INSERT`s inside 111 are function bodies executed only when the recovery functions are called (never during the migration). **No config or flag is touched.**

**115–120 (already in production) vs 110–114:** no cross-references either way (grep at `562fda9`: 115–120 mention none of `signing_key`, `get_door_manifest`, `_get_door_manifest_core`, `get_signing_keys_door`, `get_manifest_signing_context`, `signing_key_recovery`, `guard_signing_key_insert`; 110–114 mention no `ops.` object). Applying 110–114 **after** 115–120 was rehearsed (session 8): replay without 110–114 → census 149/83/ops 90/31 (= production), then 110→114 → 153/87/90/32 with guard + recovery present; canonical-order replay identical; **682-line dump of every function/trigger/policy definition and routine grant across seven schemas identical between the two orders**; full pgTAP on the production-order DB `plan 4320 · ok 4316 · not_ok 4` (the four documented local-only deltas). **Applying exactly 110–114 from the current production tip is supported.**

## 3. Selection guarantee — only 110–114 can be applied

- Production ledger (read-only, 2026-09-09): **130 versions**; numeric tip **120**; contains `115 116 117 118 119 120` and the five timestamped web-form/admin migrations; **110–114 absent**.
- Candidate tree (`562fda9`): 135 migration files. **Set difference tree − ledger = exactly `{110, 111, 112, 113, 114}`; ledger − tree = ∅.** Therefore `supabase db push --linked --include-all` from this checkout can select nothing else, and nothing in the ledger is missing locally (no "remote versions not found" refusal).
- `--include-all` is **required**: without it the CLI skips local versions lower than the remote tip (120), i.e. it would apply nothing.
- The **dry run is the binding gate**: `supabase db push --linked --include-all --dry-run` must print exactly the five filenames (`110_…`, `111_…`, `112_…`, `113_…`, `114_…`) and nothing else. Any other line ⇒ STOP.
- Ledger after apply: **135 rows**; new rows `110…114` (`name` = file basenames, `created_by` NULL for the CLI path); **numeric tip remains 120** (110–114 < 120) — record this explicitly so the next preflight is not misread.

## 4. Reconciliation with governance and the frozen architecture

| Source | Requirement | Reconciliation |
|---|---|---|
| PFA-18C ratification (owner signature, 2026-09-04) | M6 BEFORE INSERT guard "REQUIRED AFTER THE BOOTSTRAP BUT BEFORE ANY NATIVE ISSUANCE"; "a compliant gated two-person post-revoke re-bootstrap mechanism" required before issuance; the signature "authorizes NO … migration 110" | 110 = M6, 111 = the gated recovery (E4). The ratification does **not** authorize applying them; a **separate production-migration authorization** is required — the phrase in §0. Applying them **before** the bootstrap is permitted (M6 "does not block the initial dark bootstrap") and was **confirmed by the owner** as the ordering (C4 before C3, 2026-09-08). |
| Readiness packet / gate report rev 3 | C4 before C3; apply tree must contain 115–120; dry run exactly 110–114; fresh `AUTODEPLOY-VERIFIED-OFF`; owner visual OFF; CLI 2.115.0 | all embodied in §6 |
| Execution record | sessions 5–7 (110–114 written, rehearsal-tested, CI-green at `1f3fc19`); session 8 production-order rehearsal; session 14 gate closed | consistent; bytes unchanged since `1f3fc19` |
| Frozen architecture / `AGENTS.md` | migrations append-only; never modify/rename existing; one package per PR; migrations-guard rules (immutability, naming, unique prefix-free versions, monotonic ordering, G-4) | 110–114 are new files at the numeric tail of the venue-native lineage; guard green on `562fda9`; nothing existing is modified. The ledger's numeric gap (115–120 applied before 110–114) is the consequence of the owner-approved RC3 release and is closed by C4; the guard's monotonic rule concerns repository order (110–114 sort before 115–120 in the tree, as they did when the guard passed). |
| `DEPLOYMENT_PATHS.md` required sequence | reviewed PR · owner visual OFF confirmation · merge · explicit owner-authorized apply · live verification; approved apply path 2 = `supabase db push` by the owner from a checkout of the merged commit with the pinned CLI | Established venue-native lineage practice (093–109 on 2026-09-04, 115–120 on 2026-09-08): apply from the reviewed, CI-green branch commit while PR #52/#55 stay open, with `AUTODEPLOY-VERIFIED-OFF` in the carrying PR + owner visual confirmation. **No merge-to-main is imposed** (owner instruction). Path B (`git_branch`) read `""` on 2026-09-09 (fresh). |
| PFAs | 18A parked (provision/rotate untouched); 18B revoke (106) untouched; PT-8 algorithm pin (ES256 enforced by 110 rule); PT-6 wire format unaffected | 110 rule "algorithm_not_es256" enforces PT-8 at INSERT; 111 preserves 18A/18B; no PFA wording changes |
| Current production ledger | 130 / tip 120 / 110–114 absent / 0 keys / guard absent | matches (re-read 2026-09-09) |

## 5. Adversarial review

### 5.1 Coordinator findings (from the bytes at `562fda9`; line numbers from the files)

- **Security / grants / RLS.** 110: guard function revoked from all client roles (L204); the trigger fires regardless of caller. 111: recovery-approval table RLS **on**, **no policies**, **all grants revoked** (L132–134) ⇒ no client or service_role read/write; the fingerprint helper zero-grant (L106); `approve_/execute_signing_key_recovery` **granted to `authenticated`** (L257, L372) with in-function authorization `platform_admin` (`kernel.is_platform`, L170–171) **and** `aal2` (L178–179) — the 106 idiom; a non-admin or non-aal2 caller is refused `42501`/`step_up_required`. 113: `_get_door_manifest_core` **zero-grant** (L93); `get_door_manifest_door` **service_role only** (L141–142) and it authorizes nothing itself — it calls `kernel.assert_door_session` and fetches the manifest for the **bound** session (108 pattern). 114: both functions **service_role only** (L101–102, L136–137); `get_signing_keys_door` projects `key_id, scope, event_id, venue_id, public_key, algorithm, status, not_before, not_after` — **never `kms_handle_ref`**; `get_manifest_signing_context` returns the single active global row including `kms_handle_ref` **to service_role only** (the door-manifest edge's DB-derived identity, per the ratified design). **No grant to anon or authenticated is added anywhere; the 140 anon/PUBLIC/authenticated sweep is unmoved (audit §1).**
- **Signing invariants / algorithm pinning / lifecycle / guard / fail-closed.** 110 rules (L115–187): scoped key parked (rule 1), status must be active, **algorithm must be ES256 (no bypass)**, `kms_handle_ref` must be a full KMS key ARN, public key must not contain PRIVATE KEY material, must be exactly one SPKI PEM block, must decode to the 91-byte uncompressed P-256 SPKI, no duplicate `key_id`, **exactly one active global**, post-revoke recovery parked (rule 10 — replaced by 111's two-approval rule), **first row must be the ruling-B `…b0` key_id** (rule 11). The intended C3 bootstrap row (`…b0`, global, active, ES256, full ARN, P-256 SPKI PEM) satisfies every rule; every deviation raises and writes nothing. 111 preconditions: exactly one revoked global and zero active, unused key_id, two **distinct** platform_admin+aal2 approvals within **30 minutes** (L126, L154), executor must be an approver, fingerprint-bound. All paths fail closed; nothing un-parks 18A provision/rotate; 106 revoke untouched.
- **Rollback / forward-only.** Rollbacks exist, were rehearsed to invert census and definition hashes exactly (audit §1), and are **not** part of C4 (production is forward-only by policy; any rollback needs its own authorization). 111's rollback must precede 110's.
- **Economic / payment / activation effects.** None: no table in `market`/`venue."order"`/payments is touched; no flag, config, cron, edge, or PostgREST exposure changes; `feature.native_issuance_enabled` / `feature.native_scanning_enabled` stay `false`; `kernel.issue_ticket_atoms`, checkout, refunds, payouts, Connect are untouched. The new door RPCs are callable only by service_role (i.e. only by edges that are **not deployed**); the staff RPC keeps its authorization and grants.
- **credential-sign runtime implications.** None at C4: `credential-sign` reads `kernel.get_ticket_signing_context` (102/103, untouched); `door-manifest` will read `venue.get_manifest_signing_context()` (114) only once deployed (C6); with 0 keys it returns the stable `unavailable`/`no_active_global_key` shape.
- **Data mutation beyond schema/config registration.** **None** — no row is inserted, updated or deleted by 110–114 at apply time; the only rows written are the five ledger rows by the CLI.
- **Conflict with PFA-18C.** None found: 110 enforces the ratified lineage (global/ES256/`…b0`); 111 implements the ratified "gated two-person post-revoke re-bootstrap" and returns lifecycle to two-person control; the single-founder §6.1 artifact still inserts exactly one row under the guard.
- **Idempotency / re-run.** `create or replace function`, `drop trigger if exists` + `create trigger`, `create table if not exists`/guarded DDL; double-apply of 112/113/114 produced identical hashes in rehearsal (audit §1). A partially failed push is handled per §6.5, never by blind re-run.

### 5.2 Independent adversarial subagent reports

#### 5.2a — Independent adversarial review of 110–111 (+ rollbacks) — completed 2026-09-09

**Objects (confirmed):** 110: `kernel.guard_signing_key_insert()` SECURITY DEFINER, `search_path=''` (L103–193); trigger `tg_signing_key_insert_guard` BEFORE INSERT FOR EACH ROW (L198–201); EXECUTE revoked from public/anon/authenticated/service_role (L204); no grants/RLS/drops; the 083 UPDATE guard untouched. 111: `signing_key_p256_pem_fingerprint(text)` IMMUTABLE STRICT SECDEF zero-grant (L82–106); table `kernel.signing_key_recovery_approval` + index (L113–130), RLS on, ALL revoked incl. service_role, 0 policies (L132–136), append-only trigger via 076 (L138–141); `approve_/execute_signing_key_recovery` revoked from public/anon/service_role and **granted to `authenticated`** (L256–257, L371–372); guard re-created with `CREATE OR REPLACE` (L380–472). No public-schema object; no ALTER on `kernel.signing_key`.
**Data mutation at apply time:** none (table created empty; DML exists only inside the runtime functions).
**Guard rules (L114–189) — all fail closed (P0001, BEFORE ROW):** NULL scope/status/algorithm refused (`is distinct from`); the 103 default `'EdDSA'` dies at rule 3; ARN regex accepts exactly `arn:aws:kms:us-east-1:652872010073:key/<lowercase-uuid>` (alias/bare id/uppercase refused; a NULL handle is stopped by the 083 NOT NULL); PEM rules require exactly one `PUBLIC KEY` block decoding to the 91-byte uncompressed P-256 SPKI (bare DER-base64 as emitted by `aws kms get-public-key` is refused — the ceremony PEM-armors, per D3; tested 176:95); advisory transaction lock after content checks; with 0 rows: no duplicate, no active, no revoked, key_id must be `…b0`. **The intended bootstrap row passes** (identical shape tested 176:37, 176:120–123); the §6.1 artifact supplies `algorithm` explicitly with the ES256 pre-flight and is re-run-safe (`where not exists`).
**111 correctness (confirmed):** rules 1–9, 11 textually identical to 110; rule 10: 0 revoked → fall through to rule 11; >1 → `recovery_lineage_exceeded`; =1 → requires ≥ 2 DISTINCT unexpired platform_admin+aal2 approvals bound to (key_id, D5 fingerprint), then skips rule 11 (rule 8 blocks key_id reuse). `approve`: `auth.uid` → `is_platform(['platform_admin'])` → aal2 (106 idiom; `step_up_unavailable`/`step_up_required`); lock only after authz (no lock-DoS by non-admins); replay by (identity, command_key) with a UNIQUE index; preconditions exactly-one-revoked/zero-active/unused key_id; `duplicate_approver` by identity; `expires_at = now()+30 min` consistent with the CHECK. `execute`: same authz; fingerprint via helper; ARN re-check; replay via a matching `admin_audit` row; ≥ 2 distinct approvers and caller ∈ approvers; INSERT explicit ES256/global/active/`not_before=now()`; the guard re-validates everything. Effective window: execute within 30 min of the first approval. `admin_audit` vocabularies are open (no CHECK collision); FK `approver_identity → auth.users ON DELETE RESTRICT` matches the 077 precedent (account deletion never deletes `auth.users`).
**Dependencies/ordering:** 110 needs 083 + 103 (live in production); **111 needs 110's trigger** (111 replaces the function body only and never creates the trigger) — satisfied by the canonical order 110 → 111. Zero references to 112–114 or 115–120; 115–120 touch no `kernel.signing_key`, `admin_audit` constraints, `is_platform`, `raise_append_only` or kernel default privileges (only a different `hashtext` advisory-lock string in 117). Safe after 115–120; `--include-all` required.
**Activation/economic paths:** none — no flag touched; issuance still gated by `feature.native_issuance_enabled` (093); resolver unchanged; `kernel.approval_request` untouched. New surface = two `authenticated`-callable RPCs that refuse before any write unless platform_admin + aal2.
**Rollbacks:** 110's correct/idempotent; 111's drops the three functions + table (cascading its trigger) and re-creates the 110 guard verbatim (diff-clean; `CREATE OR REPLACE` keeps the function OID so the trigger stays bound). **Order matters:** 111's rollback must precede 110's (rolling back 110 while 111 remains would leave bare INSERTs unguarded). 111's rollback destroys approval evidence (admin_audit survives). Production is forward-only.
**Single-founder bootstrap:** no conflict — an empty keyring ignores approvals; rule 11 requires `…b0`; `approve()` refuses `recovery_not_applicable`. One founder can bootstrap; one founder with one identity cannot recover after a revoke; two admin identities controlled by one human can (disclosed residual, 111 L57–66). **Idempotency:** both re-runnable; suite 177 exercises replay.

**Confirmed defects (minor, none blocking C4):**
- **D1 (111):** 111 does not assert or create the trigger; on a database where 110 was never applied or was rolled back, the guard function exists but never fires. Irrelevant under the canonical order and the forward-only policy; recorded as a rollback-ordering rule (111 before 110) and a runbook note.
- **D2 (doc only):** the ceremony document's rotation artifact (`PRODUCTION_SIGNING_KMS_CEREMONY.md` L972–975) omits `algorithm` and inserts beside an active key — dead under 110 (rotation is parked, PFA-18A). Dated doc note to add; not a migration change.
**Residual risks (runbook items, not defects):** R1 a table owner/superuser can disable triggers or set `session_replication_role=replica` — inherent; the 099 monitor is the compensating control. R2 a logical dump/restore or branch seed of a 2-row lineage (revoked + active) is refused by rules 9/10 during COPY unless triggers are disabled — runbook item. R3 lineage ceiling: after one recovery and a further revoke the keyring is unmanageable until a new migration (`recovery_lineage_exceeded`) — by design, must be in the runbook. R4 the guard does not check `not_before <= now()`; a future-dated row is accepted but does not resolve at mint (`no_active_signing_key`) — the ceremony uses `now()`. R5 approvals still count if an approver loses `platform_admin` inside the 30-minute window; `approver_session` may be NULL when the JWT lacks `session_id` (evidence only). R6 FK RESTRICT + append-only means an approver's `auth.users` row can never be hard-deleted — same as `admin_audit` today.


#### 5.2b — Independent adversarial review of 112–114 (+ rollbacks) — completed 2026-09-09

**Objects/grants/RLS (confirmed):** 112 body-only re-create of `venue.get_door_manifest` (no ACL change; 086 `authenticated` EXECUTE preserved, service_role none). 113: `_get_door_manifest_core` zero-grant (L93); `get_door_manifest_door` service_role only (L141–142); staff RPC delegates. 114: both functions service_role only (L101–102, L136–137). No table/index/trigger/policy/RLS change; `kernel.signing_key` ACL untouched. All new functions `security definer set search_path=''`, schema-qualified.
**Data/config mutation at apply time:** none. (At runtime the door RPCs update `venue.door_session.last_seen_at` via `kernel.assert_door_session`, throttled — the same as 108.)
**Authorization model (confirmed):** door RPCs' sole gate is `kernel.assert_door_session`; scope comes from the returned bound session, never from a body field (`is distinct from` cross-checks refuse NULL too); no generic service_role bypass. `get_manifest_signing_context()` has no in-body gate — any service_role holder can read `kms_handle_ref` — **not a widening** (service_role could already read the column; 083 never revoked it). `_get_door_manifest_core` reachable only through the two gated definers.
**Signing context/keyring:** empty table ⇒ `{status:'unavailable', code:'no_active_global_key'}`; ambiguous branch unreachable under the 083 partial unique index; window/algorithm branches correct (a default-`EdDSA` row is refused). `get_signing_keys_door` projects exactly the 083/103 public columns; `kms_handle_ref` never selected; no private material exists in the table.
**Dependencies/ordering:** 086, 083, 103, 078, 108; no object dependency on 110/111; 115–120 touch only `ops` (115 default privileges limited to `ops`) — safe after 115–120. 113 must follow 112, 114 after 113 (re-applying 112 after 113 would revert the delegation — functionally equivalent).
**Activation/economic paths:** none (no flag reads, no `kernel.tickets`/money/custody/outbox/scan writes).
**Rollbacks:** R112 body byte-identical to 086; R113 body byte-identical to 112; correct drop order; idempotent. **Grant widening:** none. **Idempotency:** all `create or replace`/`comment`/`revoke`/`grant`; each file one transaction.

**Confirmed minor defects (not C4 blockers — recorded for forward fixes):**
- **D1 (114 L121):** `select * into v_k` is non-STRICT with no `if not found`; a revoke committing between the count and the select (read-committed snapshots) could return `{status:'ok', key_id:null, kms_handle_ref:null, …}` instead of a stable `unavailable` code. **Mitigation in force:** the `door-manifest` edge re-classifies the context (`classifyManifestSigningContext`: algorithm/status/window/handle) and refuses malformed contexts before any KMS call — fail closed; the window is a single revoke racing a manifest signature. **Disposition:** forward body-only fix (`if not found then return unavailable`) in a later migration **before C6 (dark deploy of `door-manifest`)**; do not modify the reviewed 114 bytes.
- **D2 (086 vs 112/113 drift):** `venue.sync_scan_device_manifest` (086) still binds a device to an expired-but-open episode while 112/113 report `open:false/no_open_episode` for it — a latent inconsistency, dark today (native scanning off). **Disposition:** forward fix before scanning activation (C8 precondition); not a C4 blocker.
- **Observability gap:** `get_manifest_signing_context` writes no audit row (102 does); not a security defect.
**Residual risks:** wire-shape change of `get_door_manifest` (adds header fields; expired-open episodes now `open:false` — fail-closed behaviour change on an existing authenticated RPC); `get_signing_keys_door` returns revoked/rotating rows by design (consumers pin `status`); census/suite expectations verified by CI, not by this review.


## 6. Production execution plan (owner-executed; coordinator reads back; nothing here is authorized until the phrase is given)

### 6.1 Preflight (read-only; all must pass on apply day)
| # | Check | Expected |
|---|---|---|
| P1 | `git -C /Users/josetascon/snatchit-admin-console rev-parse HEAD && git -C /Users/josetascon/snatchit-admin-console status --porcelain` | `562fda9aba261d7929ee772a4fd1ce50485c4294`, no output |
| P2 | `cd /Users/josetascon/snatchit-admin-console && shasum -a 256 supabase/migrations/11[0-4]_*.sql` | the five digests in §0 |
| P3 | `supabase --version` | `2.115.0` |
| P4 | production read (coordinator via MCP, read-only, or owner `psql`): ledger count, numeric tip, presence of 110–114, `kernel.signing_key` count, `guard_110_present`, flags | `130` · `120` · none · `0` · `false` · dark |
| P5 | `git_branch` of the production branch record | `""` (read-only API), **plus** the owner's visual confirmation in Supabase → Settings → Integrations → GitHub that "deploy to production" is OFF, dated today |
| P6 | PR #55 body updated by the owner to `AUTODEPLOY-VERIFIED-OFF: <today>`; CI runs green on `562fda9` (`34188504835`, `34188507116`) | present / green |
| P7 | AWS side (coordinator, read-only): `kms list-keys` `[]` | `[]` |
| P8 | **Dry run** (owner, from the worktree): `cd /Users/josetascon/snatchit-admin-console && supabase db push --linked --include-all --dry-run` | prints exactly `110_signing_key_insert_guard.sql`, `111_signing_key_recovery_two_person.sql`, `112_get_door_manifest_headers.sql`, `113_get_door_manifest_door_machine_authority.sql`, `114_signing_key_door_delivery_and_manifest_signing_context.sql` — **nothing else, no error** |

`supabase link` is already established in that worktree (linked-project present; the DB password resolves from the OS keychain, as on 2026-09-04 and 2026-09-08 — never typed in chat). If the CLI asks to re-link, the owner runs `supabase link --project-ref hqycwntpfoztoinemqns` locally and repeats P8.

### 6.2 Apply (owner; one command; the CLI applies the five files in order, each in its own transaction, inserting the ledger row per file)
```bash
cd /Users/josetascon/snatchit-admin-console && supabase db push --linked --include-all
```
Expected: the same five filenames, the confirmation prompt answered by the owner, then `Finished supabase db push.` with exit 0.

### 6.3 Post-apply verification (read-only)
| # | Check | Expected |
|---|---|---|
| V1 | ledger count; versions `110…114` with `name`; numeric tip | **135**; five rows present (`created_by` NULL); tip **120** (unchanged — record) |
| V2 | `to_regprocedure('kernel.guard_signing_key_insert()')`; trigger on `kernel.signing_key` enabled | present; `tgenabled = 'O'` |
| V3 | `kernel.signing_key_recovery_approval`: exists, `relrowsecurity = true`, `count(pg_policy) = 0`, no grants to anon/authenticated/service_role, row count 0 | as stated |
| V4 | `approve_/execute_signing_key_recovery` exist; `routine_privileges` show EXECUTE for `authenticated` only (plus owner) | as stated |
| V5 | census: kernel fns **153**, venue fns **87**, kernel tables **32** (production was 149/83/31) | +4 / +4 / +1 |
| V6 | `venue.get_door_manifest` definition references `_get_door_manifest_core`; `_get_door_manifest_core` has no grants; `get_door_manifest_door`, `get_signing_keys_door`, `get_manifest_signing_context` EXECUTE = service_role only | as stated |
| V7 | `select venue.get_manifest_signing_context()` (read-only call) | `status: 'unavailable'`, code `no_active_global_key` (0 keys) |
| V8 | guard probe inside a rolled-back transaction: `begin; insert into kernel.signing_key(...) values (<a key_id ≠ …b0>, 'global', 'active', 'ES256', 'arn:aws:kms:us-east-1:652872010073:key/00000000-0000-0000-0000-000000000000', <a valid P-256 SPKI PEM>, now(), null); rollback;` | refused `signing_key_insert_refused: bootstrap_key_id_required`; `count(*)` still 0 |
| V9 | darkness: flags unchanged (`false`/`false`/`false`, fingerprint null), `kernel.signing_key` 0, `kernel.tickets` 0, edges still not deployed, AWS `kms list-keys` `[]` | as stated |

### 6.4 Stop conditions (do not run 6.2 if any holds; if discovered after 6.2, stop and record)
HEAD ≠ `562fda9…` or a dirty worktree · any digest ≠ §0 · CLI ≠ 2.115.0 · ledger ≠ 130 or tip ≠ 120 or any of 110–114 already present · `kernel.signing_key` ≠ 0 or guard already present · `git_branch` ≠ `""` or no dated owner visual confirmation · PR body without today's `AUTODEPLOY-VERIFIED-OFF` · CI not green on `562fda9` · **dry run lists anything other than exactly the five files** · any error during the push · any post-apply value differing from §6.3.

### 6.5 Failure handling
- Push error at file *N*: files < *N* are applied (each is its own transaction; the ledger row for a failed file is not written). **Do not re-run.** Read the ledger and the catalog, record the exact error, and report. Resume only by explicit owner decision: either re-run `db push --include-all --dry-run` (which must then list exactly the remaining files) or roll back the applied files in reverse order with `supabase/rollbacks/*` under a separate authorization.
- Post-apply discrepancy: no automatic rollback (forward-only policy); record, report, decide.

### 6.6 Evidence to record (execution record, C4 section)
Commit SHA and the five digests; CLI version; dry-run output verbatim; push output verbatim (no secrets appear); ledger rows `version,name,created_by` for 110–114 and the count; V2–V9 outputs; timestamps (UTC); CI run IDs; PR #55 `AUTODEPLOY-VERIFIED-OFF` date and the owner's visual-confirmation statement; AWS `kms list-keys` `[]`.

## 7. What C4 does not do
No KMS key, no signing-key row (C3 follows under its own authorization), no secret, no edge deployment, no flag flip, no Organizations/accounts, no payments/fees/Connect/transfers/refunds/payouts, no PFA-18A un-parking, no rotation. Issuance and scanning stay dark.
