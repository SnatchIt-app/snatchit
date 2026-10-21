# venue_api read views: migration 20261021120000 (registry 159, pgTAP 226)

> **Registry 159 / pgTAP 226, allocated by A in PR #115 (`origin/a/registry-20261021`); A
> reviews before this leaves draft.** The registry draft is `origin/a/registry-20261021`.
> `b4b3df69` allocated 157–159, and the tip `eef30015` (2026-10-21 13:44) reserves 160–169 and
> allocates 170–172. Row 159 keeps the file `20261021120000_venue_api_read_views.sql` with the
> version unchanged. Only the pgTAP number moved, from the provisional 224 to 226, because 224
> and 225 belong to A's 157 and 158. D's old `20260910120000` / pgTAP 188 is retired.
>
> **Order, both directions:** 159 merges and applies only AFTER 157 (`20261021100000`) and 158
> (`20261021110000`), and only BEFORE 170–172 (`20261021130000`, `20261021131000`,
> `20261021132000`) and any 160–169 file (the registry reserves those with timestamps above
> `20261021120000`). Otherwise A must re-timestamp (§2).
>
> The doc's file name still says "provisional". It is kept so the migration header's references
> to it stay valid.
>
> **Applied nowhere.** It is not on production, the sandbox or any hosted project. Nothing in
> this branch applies it, exposes it or writes production data. A reviews it first because it
> touches the database.

Branch `venue/api-read-views-provisional`, based on `origin/fix/154-listing-visibility-20261015`
@ `bfc5cf97`. That base is the production migration chain through `20261015000200`. Files 154–156
are frozen and were not touched.

| File | Source on `origin/venue/dashboard-v2` (`ee1d90b7`) | Change |
|---|---|---|
| `supabase/migrations/20261021120000_venue_api_read_views.sql` | `20260910120000_venue_api_read_views.sql` (blob `80cf2762`) | Header only. The SQL from `BEGIN;` to `COMMIT;` is byte-identical (sha256 `fb3cf536…1199e70` on both). |
| `supabase/rollbacks/20261021120000_venue_api_read_views_rollback.sql` | `20260910120000_…_rollback.sql` (blob `114b94ed`) | Header only. The statements are byte-identical (sha256 `d191b761…27b7340`). |
| `supabase/tests/226_venue_api_read_views.sql` (provisionally `224`, renamed with `git mv`) | `188_venue_api_read_views.sql` (blob `7ed77132`, plan 47) | The 47 assertions are carried verbatim, fixture included. 25 assertions are new (plan 72): nine in the first round (§4.4), 15 after the first review (§4.5) and one after the second (§4.6). |

Header fixes in the migration:
- the registry banner (159 / 226, allocated by A, merge order) and a provenance paragraph
- "SELECT on the six views" now reads "eight"
- the rollback path
- the exposure note now points at this file, because `SLICE1_HANDOFF.md` is not on this branch
- a four-file-rule note

No new `;` was added to any header comment. The Supabase CLI ledger's statement count, which the
kit expects to be 24, is therefore computed from the same statements as before.

Why a new version: production's ledger tip is `20261015000200`. `migrations-guard.yml` rule 4
fails any added migration that does not sort above the base's latest version of the same
scheme, so `20260910120000` can no longer enter. That version was never applied anywhere, so
the immutability rule does not bind it. The precedent is 153 and FINAL_INTEGRATION_PLAN C6.

## 1. What it creates

Schema `venue_api` (comment set). The statements, in order:
1. `REVOKE ALL ON SCHEMA venue_api FROM PUBLIC, anon`
2. `GRANT USAGE … TO authenticated`
3. `ALTER DEFAULT PRIVILEGES IN SCHEMA venue_api REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated`

The `ALTER DEFAULT PRIVILEGES` statement stores no `pg_default_acl` row, because the built-in
table default already grants nothing. The rehearsal confirms this with V7 = 0 and F3.

**Correction to the body comment.** The body comment directly above
`ALTER DEFAULT PRIVILEGES IN SCHEMA venue_api REVOKE ALL ON TABLES …` says "Deny-by-default for
anything added to this schema later". That overstates it:
- A per-schema REVOKE stores nothing.
- A schema-scoped default can only add to the global defaults, never subtract from them (076's
  accuracy note and PFA-1 record the same point).
- So what a later object receives is decided by the role that creates it, through that role's
  global defaults and the built-in default.

The comment stays in place because the body is byte-identical to the original. The correction
lives in the migration header and here.

pgTAP 226 pins both halves for objects the owner creates:
- F3: no schema-scoped default-ACL row. Its label was reworded; it used to claim "a later object
  gets nothing implicitly".
- F7: no global table default of the owner that grants to PUBLIC, anon or authenticated.

Objects created by another role are outside F7. Whoever creates them, A2, A3, F1, F5 and F8
catch an added view, function, granted relation, relation with columns or type. Other object
kinds are not swept (§4.6).

It creates eight views, each `WITH (security_invoker = true, security_barrier = true)`:

| View | Base object (migration) | Projected columns | Read policy that applies to the caller |
|---|---|---|---|
| `venues` | `catalog.venue` (078) | venue_id, org_id, name, neighborhood, approval_status, created_at, updated_at | `catalog_venue_sel_anon` 078:307, `_sel_org` 078:312, `_sel_venue` 080:367 |
| `events` | `catalog.event` (078) | event_id, venue_id, org_id, title, status, created_at, updated_at | `catalog_event_sel_anon` 078:323, `_sel_org` 078:328, `_sel_venue` 080:381 |
| `event_sessions` | `catalog.event_session` (078) | session_id, event_id, session_label, starts_at, ends_at, doors_at, door_open_at, status, created_at, updated_at | `_sel_anon` 078:336, `_sel_org` 078:343, `_sel_venue` 080:397 |
| `resale_policies` | `catalog.resale_policy` (078) | policy_id, scope_kind, venue_id, event_id, mode, price_cap_bps, royalty_bps, version, effective_from, created_at | `catalog_resale_policy_sel_public` 078:382 only |
| `ticket_types` | `venue.ticket_type` (081) | ticket_type_id, event_id, kind, name, price_minor, currency, visibility, created_at, updated_at | `venue_ticket_type_sel_public` 081:990, `_sel_venue` 081:999 |
| `inventory_batches` | `venue.inventory_batch` (081) | batch_id, ticket_type_id, event_session_id, release_kind, is_sharded, remaining, created_at, updated_at (no capacity/held/sold, per 081 E-29) | `_sel_public` 081:1020, `_sel_venue` 081:1026 |
| `my_staff_roles` | `venue.staff_role` (080) `WHERE identity_id = auth.uid()` | venue_id, role | `venue_staff_role_sel_venue` 080:343, `_sel_org` 080:351, `_sel_platform` 080:356 |
| `my_org_roles` | `kernel.org_member` (077) `WHERE identity_id = auth.uid()` | org_id, role | `kernel_org_member_sel_org` 077:526, `_sel_platform` 077:531 |

That is 55 columns in total. Every one is a column the base table already grants to
`authenticated`:
- catalog column grants: 078:124, :162, :204, :283
- inventory_batch column grant: 081:1016
- org_member column grant: 077:168
- table grants on staff_role and ticket_type: 080:338, 081:988

Checked on the rehearsal database with `has_column_privilege('authenticated', <base>, <col>, 'SELECT')`: 55 of 55 projected columns are granted.

All eight views are now read as callers.
- **Before (`3bf24c0b`, plan 56):** no assertion read `venues` or `resale_policies` as a
  caller. Both were checked by hand with `SELECT *` as an `authenticated` caller.
- **Review finding:** that left a REVOKE of a projected base column green in CI, while the view
  became unreadable to every caller.
- **Now:** pgTAP 226 reads both as callers in C22–C30 and D6–D9. The other six views are read
  in Sections C–E. See §4.5.

**Grants:** USAGE on the schema and SELECT on the eight views, to `authenticated` only. `anon`,
`service_role` and `PUBLIC` get nothing.

**Not here:**
- no function, trigger, policy, table or sequence
- nothing in `public`
- no write path
- no counters (capacity, held, sold)
- no door, order or scan data

**Predicate functions the base policies call:** `kernel.has_org_role`, `is_platform`,
`is_org_affiliate` (077:453/468/490), `kernel.has_venue_role`, `has_event_role`,
`has_org_role_over_venue`, `has_org_role_over_event` (080:60/78/93/105), and `auth.uid()`.

**Venue code that reads it:** `venue/src/lib/db/adapters.ts` on `venue/dashboard-v2` selects
only columns that are in this projection.

## 2. Dependencies and ordering

- **Needs:** 076 (schemas), 077, 078, 080 and 081, all applied in production since 2026-09-02.
  Nothing numbered 082 or later is needed.
- **Version:** `20261021120000` sorts after `20261015000200` (`LC_ALL=C`) and is prefix-free. On
  this branch it is the last of 172 files.
- **Numbers (registry 159, pgTAP 226):** A allocated both in PR #115
  (`origin/a/registry-20261021` @ `b4b3df69`). The registry tip is now `eef30015` (13:44), which
  adds rows above 159 and leaves 157–159 as they were:
  - 157 = `20261021100000_ops_money_action_unsettled_guard.sql` with pgTAP 224.
  - 158 = `20261021110000_ops_listing_relist_expected.sql` with pgTAP 225.
  - 159 = this file with pgTAP 226.
  - 160–169 (pgTAP 227–239) are reserved for D and F/C follow-ups, with "timestamps above
    `20261021120000`".
  - 170 = `20261021130000_listing_seller_integrity.sql` (240), 171 =
    `20261021131000_transfer_refusal_hints_and_evidence_path.sql` (241), 172 =
    `20261021132000_bid_created_at_server_owned.sql` (242), all A's.
  - The earlier line here said pgTAP 224 was "free on every local and `origin/*` ref". That was
    wrong when it was committed: A's registry, pushed about five minutes earlier, already gave
    224 to 157. The file is now `226_venue_api_read_views.sql`.
  - 220 is on `fix/153-detect-refunds-state-on`, and 221–223 are on this base.
- **What the registry gives (`eef30015`), row by row:**
  - 157 = `20261021100000`
  - 158 = `20261021110000` ("written on 157's bodies (stacked)")
  - 159 = `20261021120000`
  - 160–169 = reserved, "assigned by A on request; timestamps above `20261021120000`"
  - 170 = `20261021130000` ("not for apply before 2026-10-28 03:47Z")
  - 171 = `20261021131000`
  - 172 = `20261021132000` (the same note as 170)

  The registry states no merge sequence for these rows beyond their timestamps (its allocation
  protocol: "timestamp-named above the current tip"). It does not place 160–169 against
  170–172: a 160–169 timestamp only has to be above `20261021120000`, so it may sort below,
  between or above `20261021130000`, `20261021131000` and `20261021132000`.
- **The order for 159 that follows** from those timestamps and `migrations-guard.yml` rule 4:
  `20261021100000` < `20261021110000` < `20261021120000`, and `20261021120000` is below
  `20261021130000`, `20261021131000`, `20261021132000` and every 160–169 timestamp. So 159
  merges into any integration base, and applies to any project (sandbox or production), only
  after 157 and 158 and only before 170–172 and any 160–169 file. The order among 160–172 is
  not this file's to state. The four ways the order can break for 159:
  - **159 merges before 157 or 158.** `migrations-guard.yml` rule 4 (the monotonic ordering
    check) then fails 157 and 158, because neither is greater than the latest existing ts
    migration (`20261021120000`).
  - **170, 171, 172 or a 160–169 file merges before 159.** Rule 4 then fails 159, for example
    `20261021120000 … is not greater than the latest existing ts migration (20261021130000)`.
    159 would need a new timestamp.
  - **159 is applied before 157 or 158.** 157 and 158 would then enter the ledger below its tip.
    That is the ordering hazard the registry records for 125–128.
  - **170–172 or a 160–169 file is applied before 159.** 159 would then enter that project's
    ledger below its tip, the same hazard.

  If that order cannot hold, A must re-timestamp before anything merges.

## 3. Base objects re-checked on this chain (step 3)

The question: has any migration after 081 altered the eight base relations, their columns,
column grants, RLS policies, or the predicate functions? Three independent views were used.

**1. Catalog fingerprint, state at 081 against the tip.**
- The script fingerprints:
  - the 8 relations: kind, ACL, RLS/force flags, options, owner
  - their 74 columns: type, not-null, generated, column ACL
  - their 19 policies: command, roles, md5 of USING/WITH CHECK
  - their triggers
  - the ACLs of the catalog, venue, kernel and auth schemas
  - the closure of functions the policies call: `pg_depend` from the policies, then
    schema-qualified calls inside `prosrc`, iterated. That gives 8 functions, compared on md5 of
    source, definer flag, config, ACL and owner.
- Databases:
  - `f_venueapi_at081_rehears` (91 files, through 081): 120 lines
  - `f_venueapi_base_rehears` (171 files): 122 lines
- The full diff:
  ```
  nsp|kernel  acl gains service_role=U   (085_kernel_money_native.sql:2095)
  nsp|venue   acl gains service_role=U   (085_kernel_money_native.sql:2091)
  + trg catalog.event_session tg_door_open_at_is_ledger_head  (086:469, BEFORE UPDATE OF door_open_at)
  + trg catalog.event_session tg_session_terminal_force_close (109:114, AFTER UPDATE OF status)
  ```
- No column, column grant, relation ACL, RLS flag, policy or predicate function changed. The two
  triggers are write-path only. The views grant `service_role` nothing.
- A vacuous empty-versus-empty diff happened on the first run, because the script had a CTE
  error. It was caught by checking line counts, not the exit code.

**2. Statement scanner, comments and bodies stripped.**
- `scan_base_ddl.py` runs over the 80 files after 081. Its self-test catches 4 planted DDL
  statements and ignores DDL inside a function body, a comment, a near-name table and a plain call.
- It found 48 DDL statements that name a base object. All of them are one of these:
  - 40 `CREATE POLICY` on **other** tables (venue.order, order_item, door_*, scan*, promoter*,
    settlement*, comp_allocation, guest_*, market.*, notify.*) whose predicates call
    `has_venue_role`, `has_org_role`, `is_platform`, `auth.uid` or read catalog tables
  - the two `GRANT USAGE … TO service_role` statements (085)
  - the two drop/create trigger pairs above (086, 109)
  - `CREATE OR REPLACE VIEW market.listing_unified` (089:48), a reader
  - `ALTER TABLE kernel.organization_obligation ADD COLUMN venue_id … REFERENCES catalog.venue`
    (097:177), a referencing foreign key, not a change to catalog.venue
- None alters, renames, drops, re-grants or re-policies a base object or redefines a predicate.

**3. Raw multi-line pattern scan, bodies and comments included.**
- The pattern: ALTER TABLE, CREATE/ALTER/DROP POLICY, GRANT, REVOKE, RENAME, DISABLE ROW or
  NO FORCE, followed by ON or ALTER TABLE on a base table.
- Result: 1 hit, which is a comment (093:6275).
- Positive control on 077/078/080/081: 7/26/15/14 hits.

**Conclusion:** the base objects the views depend on are unchanged since 081, apart from the
read-irrelevant items above. View semantics were not changed.

## 4. Four-file rule (A's CI contract)

| File | Decision | Evidence | Diff |
|---|---|---|---|
| `supabase/ci/assert_public_table_grant_decisions.sql` | **Out of scope, no row.** Part A reads `pg_tables WHERE schemaname = 'public'` (A1, A2; the header comment at A1 says views are excluded deliberately). Part B reads `pronamespace = 'public'::regnamespace`. The migration creates no function. | Probe 1: a table **and** a PUBLIC-executable function planted in `venue_api` → the manifest still PASSES. Probe 2: a table planted in `public` → FAILS (`__planted_t`). Probe 3: a view planted in `public` → PASSES. The manifest PASSES on the full replay with the migration (8 notices, self-tests OK). | none |
| `.github/workflows/ci.yml` Gate-2 census | **Unchanged.** The four counters read `public` only (tables in `pg_tables`, functions, policies, non-internal triggers). | Before 35\|126\|37\|49 and after 35\|126\|37\|49, the same as `EXPECT_*` 35/126/37/49. They are also unchanged with a planted venue_api table and function. | none |
| `supabase/ci/expected_grants.txt` | **Unchanged.** The CI query is `information_schema.role_table_grants WHERE table_schema='public'` and the file format `grantee\|table\|privs` has no schema column. | Negative control: adding the 8 `authenticated\|<view>\|SELECT` lines makes the CI diff FAIL (8 expected-only lines). Without them it is IDENTICAL (72 rows) before and after apply. | none |
| rollback | Drops the 8 views, then the schema (not CASCADE). Restores the pre-apply catalog exactly and opens nothing. | §5.3: full-catalog fingerprint after rollback = pre-apply (3745 lines, md5 `65c5064b…`). | header only (statements byte-identical) |

**Compensating control.** `venue_api` sits outside all three CI manifests, so pgTAP 226 is its CI
gate:
- A10 (no grantee other than authenticated or the owner)
- F1: the exact relation and column ACL, 8 × `authenticated:SELECT`
- F2: the exact schema ACL `authenticated:USAGE`
- F3: no schema-scoped default-ACL row in the schema grants anything
- F7: no global table default of the schema owner grants to PUBLIC, anon or authenticated
- F4: security_barrier on every view
- F5: the exact 55-column projection
- F6: each view's definition equals the migration's SELECT (§4.5)
- F8: no type in the schema other than the eight views' row types and their array types (§4.6)
- A2/A3: eight views, zero functions
- Sections C–E and D6–D9: every view read as a caller, so a base-column REVOKE that makes a view
  unreadable fails the file

Probe 1 shows that a function added to `venue_api` would not be caught by the manifest. A3
catches it, and so does mutant m14 below.

### 4.4 Why the suite has nine more assertions than 188 (first round)

The 47 assertions of 188 were run against 14 planted migration mutants. Six survived. The suite
was numbered 224 at the time and is now 226:

| Mutant | 188 (47) | 224 (56), now 226 |
|---|---|---|
| m01 GRANT USAGE + SELECT on events to anon | killed (A6, A8, A10, C21) | killed (+F1, F2) |
| m02 events without security_invoker | killed (A4, C15, C17, D1, D4) | killed |
| m03 inventory_batches projects capacity | killed (B1 + 54 errors) | killed (B1 + 70 errors) |
| m04 my_staff_roles without `identity_id = auth.uid()` | **survived** | killed (E9) |
| m05 my_org_roles without `identity_id = auth.uid()` | **survived** | killed (E11) |
| m06 `ALTER DEFAULT PRIVILEGES … GRANT SELECT ON TABLES TO authenticated` | **survived** | killed (F3) |
| m07 GRANT INSERT, UPDATE on ticket_types to authenticated | **survived** | killed (F1) |
| m08 GRANT SELECT on events to service_role | killed (A10) | killed (A10, F1) |
| m09 GRANT USAGE on schema to PUBLIC | killed (A6) | killed (A6, F2) |
| m10 events projects one extra (granted) column | **survived** | killed (F5) |
| m11 venues without security_barrier | **survived** | killed (F4) |
| m12 my_staff_roles projects identity_id | killed (E1) | killed (E1, F5) |
| m13 a ninth view | killed (A2) | killed (A2, F4, F5) |
| m14 a SECURITY DEFINER function in venue_api | killed (A3) | killed (A3) |
| **total** | **8 killed / 6 survived** | **14 killed / 0 survived** |

m04 and m05 are the ones that matter for security. Every staff label can read its whole venue's
roster (080:343), and every org member can read its org's roster (077:526). Without the view's
identity filter, a `venue_scanner` would see the manager's row in `my_staff_roles`.
`derivePrincipal` would then pick the widest grant, and the app would present the scanner as a
manager. 188's fixture had one person per roster, so the filter was never exercised.

E8 and E10 are controls: they show that the base table does return the other person's row. E9
and E11 assert that the view does not.

### 4.5 Review round (2026-10-21): plan 56 to 71

The reviewer ran r1–r4 on a scratch copy against plan 56, and all four survived with 56/56 PASS.
r5 is the reviewer's reasoning case and was not run. The last column is what plan 71 is
**expected** to do. It is **not run**, because this
revision was written in a wave with no database (§8).

| Mutant | 56 (reviewer, run) | 71 (expected, not run) |
|---|---|---|
| r1 `REVOKE SELECT (neighborhood) ON catalog.venue FROM authenticated` and `REVOKE SELECT (royalty_bps) ON catalog.resale_policy FROM authenticated`. The views stay, but every caller read raises `permission denied for table venue`. | survived | C22 raises 42501, the run stops and the plan does not match. The file FAILS. |
| r2 venues `WHERE false` | survived | C22, C25, C26, C28 (NULL value), D6, D8, F6 |
| r3 resale_policies `WHERE false` | survived | C24, C27, C29 (NULL value), D7, D9, F6 |
| r4 `s.ends_at AS starts_at, s.starts_at AS ends_at` in event_sessions (188 also 47/47) | survived | C30 (starts 23:30 / ends 20:00 against the fixture's 20:00 / 23:30), F6 |
| r5 `ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT SELECT ON TABLES TO authenticated` (global, not in the schema). The reviewer's "future" case. | F3 stays green (reviewer, by reading) | F7 |

**How an uncaught error shows up.** CI runs 226 through `supabase test db`, that is pg_prove,
which runs psql with `ON_ERROR_STOP=1`. An uncaught error (42501 for r1 at C22, for m03 at C4)
stops the script there. The later assertions never run, so they neither pass nor fail, and the
file FAILS on the plan mismatch. The local runner `scripts/local/runtests.sh` uses
`ON_ERROR_STOP=0` instead. It keeps going inside the aborted transaction and reports each later
statement as a psql error, which is where §4.4's "B1 + 70 errors" for m03 comes from. Both
runners give the same verdict, FAIL. Only the per-assertion detail differs.

**The new fixture** is added in its own block after E11. The 47 carried assertions keep their
fixture byte for byte. It adds:
- `Room C 226`, a draft venue of org A
- a session `Late 226` of e1 whose starts_at, ends_at and doors_at all differ
- a venue-scoped policy on Room A: `fixed_cap`, cap 10000, royalty 500, version 1,
  effective_from 2026-01-01
- an event-scoped policy on the draft event e2

Same-typed columns hold different values, so a view that maps one base column to another
name returns a wrong value.

**New caller assertions:**
- C22–C24, manager A: both approved rooms; not Room C, because the 080 venue arm is per venue;
  Room A's policy but not the draft event's policy, because only 078's `sel_public` applies.
- C25, org owner A: Room A and draft Room C, through the 078 org arm.
- C26–C27, outsider: the approved rooms only, and the venue policy only.
- C28–C30, outsider: value checks on the venue, policy and session rows.
- D6–D9: view-equals-base counts for venues and resale_policies, as finance B and as outsider.

**F6 pins the definitions.**
- The eight SELECTs are copied verbatim from the migration body into transaction-local temp
  views named `exp_<view>`. F6 then compares `md5(pg_get_viewdef(...))` per view name between
  `venue_api` and the temp schema (`set_eq`).
- Both sides are deparsed in the same session, so no hash is stored. A hash would have to be
  computed on a database, and deparser output can differ between the CI image's PostgreSQL and
  a local 17.11.
- A static check confirms that the eight temp-view SELECTs are byte-identical to the
  migration's. A planted swap in a copy of the migration makes that check report DIFFERENT.
- F6 is expected to fail for every mutant that changes a view's SELECT and lets the run reach
  F6: r2–r4, and m04, m05, m10, m12 and m13.
- m03 changes a SELECT too, but it is killed earlier and F6 never runs: B1 fails, then C4 (the
  first caller read of `inventory_batches`) raises 42501 because `capacity` is not granted, and
  the run stops.
- F6 does not cover reloption, grant, default-ACL or function mutants (m01, m02, m06–m09, m11,
  m14). A4, A10, F1–F4 and A3 keep those.
- A later migration that legitimately redefines a view must update F6's temp-view text in the
  same change.

### 4.6 Second review round (2026-10-21): plan 71 to 72

The review of `3d2b0bf5` found an overclaim. The doc, the migration header and 226 all said
that A1–A3 and F1 catch any object added to the schema. They do not:
- A2 counts `pg_views` only, and A3 counts `pg_proc` only.
- F1 lists only relations with a non-owner ACL entry. The owner is excluded and `acldefault`
  grants clients nothing, so a relation with no grant never appears in it.
- An ungranted table, sequence or composite type was caught only by F5, through its
  `pg_attribute` rows.
- An enum, domain or range type exists only in `pg_type`, so no assertion saw it.

There is no security impact, because none of these carries a client grant. The text promised
coverage that did not exist. The claim is reworded in all three files, and **F8** closes the type
gap: no `pg_type` row in `venue_api` other than the eight views' row types
(`pg_class.reltype`) and their array types (the `typarray` of each row type).

What each kind of added object is caught by:

| Added to `venue_api` | Caught by |
|---|---|
| a view | A2, F5, F6 (its row type is a view's, so F8 lets it through) |
| a function, procedure or aggregate | A3 |
| a table, materialized view, foreign table or composite type with columns | F5 and F8, plus F1 if it carries a client grant |
| a sequence | F5 (a sequence has no row type), plus F1 if granted |
| a table with no columns | F8, plus F1 if granted |
| an enum, domain, range or multirange type | F8 |
| an operator, collation, text-search object or statistics object, or a trigger or rule on a view | not swept |

**Expected, not run** (no database in this wave, §8):

| Mutant (planted in a copy of the migration) | 71 (by reading) | 72 (expected) |
|---|---|---|
| r6 `CREATE TYPE venue_api.r6 AS ENUM ('a')` | survives: A2, A3, F1 and F5 read no `pg_type` | F8 |
| r7 `CREATE TABLE venue_api.r7 ()` (no columns, no grant) | survives: not a view or function, no ACL entry, no columns | F8 |
| control: the migration unchanged | — | F8 green: the only types are the eight row types and their eight array types |

F8 changes none of the §4.5 predictions. It is green for r2–r5, and for r1 it is never reached,
like every assertion after C22.

## 5. Local rehearsal evidence (2026-10-21, Homebrew PostgreSQL 17.11, localhost:5432)

**This evidence is from commit `460d85f9`.** At that commit the suite was numbered 224, with
plan 56. Every "224" below means that file, which is now `226_venue_api_read_views.sql`. The
rename itself changes no SQL. The renamed file has not been re-run.

**Environment and scope**
- The local CI-equivalent replay is `scripts/local/replay.sh`:
  - the shim and supplements (auth, storage, cron, net, vault; roles anon, authenticated,
    service_role and authenticator)
  - then every migration in `LC_ALL=C` order, which is the order the CLI applies
  - then `supabase/ci/parity_grants.sql`
- pgTAP runs through `scripts/local/runtests.sh`:
  - `000_helpers.sql` runs `CREATE EXTENSION IF NOT EXISTS pgtap`, as CI does
  - pg_prove is not installed locally
- CI's own path, `supabase start` on CLI 2.115.0, was **not** run. There is no Docker on this Mac.
- Only databases named `f_venueapi_*_rehears` were created. No hosted database was contacted.
- Logs are in the session scratchpad (`wf-impl/venue-api/logs/`).

### 5.1 Replays and CI gates

| Database | Chain | Result |
|---|---|---|
| `f_venueapi_base_rehears` | 171 files (base) | `REPLAY OK: 171`, 43.9 s. Gate-2 35\|126\|37\|49. venue_api absent. |
| `f_venueapi_full_rehears` | 172 files, last = `20261021120000_venue_api_read_views.sql` | `REPLAY OK: 172`, 11.7 s. 0 duplicate versions. Gate-2 35\|126\|37\|49 (= EXPECT). expected_grants.txt IDENTICAL (72 rows). Grant-decision manifest PASS. 8 views. |

Local equivalents of the quality-job gates on this tree: X-6 gate PASS, and precedence gate OK
(self-test 25/25).

**Migrations guard.** The `Check migrations` step of `migrations-guard.yml` was extracted and run
against base `bfc5cf97`. The AUTODEPLOY-1 PR-body check is skipped outside a `pull_request`
event, and that line belongs to the owner. Result: no existing file modified or removed, the name
is well-formed, versions are unique and prefix-free, and `20261021120000 > 20261015000200 (ts)`;
rc=0. Negative control with the same comparator: `20260910120000` is rejected as not greater
than `20261015000200`.

**Committed tree.** Everything in §5.1–5.3 was re-run on the committed tree (`460d85f9`), and the
fingerprints, verdicts and mutant results were identical:
- replay 172 files in 9.1 s
- Gate-2 35|126|37|49
- expected_grants IDENTICAL, manifest PASS
- sequence fail=0, same md5s
- mutants 14/14 killed

### 5.2 RED → GREEN (pgTAP 224, plan 56)

| Run | Database state | Result |
|---|---|---|
| RED | base chain, no migration (`to_regnamespace('venue_api') is null` = t) | FAIL: ok=2, not ok=2 (A1, A2), 84 psql errors after `schema "venue_api" does not exist`, runner rc=1 |
| GREEN | base + migration (clone) | PASS 56/56 |
| GREEN (after apply3, replay on top) | seq DB | PASS 56/56 |
| RED again | after rollback2 | FAIL: ok=2, not ok=2, 84 errors |
| GREEN | re-apply after rollback (apply4) | PASS 56/56 |
| Verbatim 188 port (47) | base / base + migration | FAIL (ok=2, not ok=2, 68 errors) / PASS 47/47 |

### 5.3 Apply, rollback and re-apply on `f_venueapi_seq_rehears`

The database holds the base chain plus parity_grants, with no pgTAP objects. Fingerprints are
the full catalog, OID-free:
- schemas, relations, columns, view definitions and functions
- policies, triggers, constraints and indexes
- default ACLs, publications and extensions

| Step | Timing | Fingerprint | Check |
|---|---|---|---|
| pre-apply | — | 3745 lines, `65c5064b183004c8464a18a486e5f10d` | census 35\|126\|37\|49, grants IDENTICAL, manifest PASS |
| apply1 | 47 ms | 3817 lines, `862c74234b284f81fddeb777a22fd904` (+72 = 1 schema + 8 views + 55 columns + 8 view definitions; no defacl line) | census, grants and manifest unchanged |
| rollback1 | 51 ms | 3745 lines, `65c5064b…` | **IDENTICAL to pre-apply** |
| apply2 | 45 ms | `862c7423…` | IDENTICAL to apply1 |
| apply3 (applied again on top, no rollback) | 46 ms | `862c7423…` | IDENTICAL: the migration is idempotent |
| pgTAP 224 and neighbours | — | — | 224 56/56; 140 59/59; 141 213/213; 142 261/261; 144 118/118; 145 96/96; 154 64/64 |
| rollback2 (helpers present) | 40 ms | 4970 → 4898 lines | 72 lines removed, all venue_api, 0 added, 0 others removed |
| rollback3 (idempotent) | 42 ms | `5369ac65…` = after rollback2 | IDENTICAL |
| apply4 (re-apply) | 44 ms | — | pgTAP 224 56/56 |

**Rollback negative controls:**
- A rollback without `DROP SCHEMA` → the fingerprint differs by 1 line
  (`nsp|venue_api…`). The rollback check is not vacuous.
- Mutant m06 (a real default-ACL row in venue_api), then the real rollback → IDENTICAL to
  pre-apply. The default-ACL row goes with the schema.
- A foreign table created in venue_api, then the rollback → `cannot drop schema venue_api
  because other objects depend on it`. The transaction aborts, all 8 views stay, and nothing is
  dropped silently.

### 5.4 Full local suite (every `supabase/tests/*.sql`)

Both runs started 16:28:36Z and took 199 s each.

| Database | Files | Result |
|---|---|---|
| `f_venueapi_full_rehears` (172 migrations) | 102 (+ `000_helpers`) | **TOTAL plan=5938 ok=5938 not_ok=0 ALL-PASS**. 224: 56/56 |
| `f_venueapi_base_rehears` (171, no migration) | 102 (224 included, RED) | TOTAL plan=5938 ok=5884 not_ok=2. The only failing file is 224 (RED: ok=2, not ok=2, 84 errors) |

Re-run on the committed tree (`f_venueapi_final_rehears`, `460d85f9`): TOTAL plan=5938 ok=5938 not_ok=0 ALL-PASS in 171 s, with per-file lines identical to the run above.

The per-file lines of the other 101 files are identical between the two runs, so adding the
schema changes no other suite. That includes the closed-world suites 140/141/154 and
131/132 replay parity.

On-disk totals for CI (`ls supabase/tests/*.sql`): 103 files and 5944 planned assertions (5938 + `000_helpers`' 6), up from
102 / 5888 on the base. The floors are `MIN_FILES=59` and `MIN_ASSERTIONS=4053`. 224 uses no `todo()` or
`skip()`, so the masking ratchets do not move.

**After the review rounds (plan 72):** 103 files and 5960 planned. That figure is the sum of every
file's `plan(N)` line. The same count gives 5944 at `3bf24c0b`, which matches the run above, and
5959 at `3d2b0bf5` (plan 71). It was **not** run. 226 still uses no `todo()` or `skip()`.

## 6. Rollback procedure

Run these in order. Each step is owner-authorised on any hosted project.
1. Remove `venue_api` from the Data API exposed schemas. That alone stops all API access. It is
   the fast reversal.
2. Run `supabase/rollbacks/20261021120000_venue_api_read_views_rollback.sql`. It is one transaction:
   all or nothing.
3. Delete the ledger row: `delete from supabase_migrations.schema_migrations where version = '20261021120000';`.
   This is a production write and is authorised separately.
4. Run read-only checks R1–R3 (§7.6). Expected: `venue_api_absent = t`; views, grants,
   default_acl_rows all 0; base_policies 19.

## 7. Owner and A steps (nothing here is authorised by this branch)

1. **Numbers: done by A, renamed here.** In PR #115 (`origin/a/registry-20261021` @
   `b4b3df69`), A allocated registry 159 to `20261021120000_venue_api_read_views.sql`, with the
   version unchanged, and pgTAP 226. This branch then did the rename (`git mv` of
   `supabase/tests/224_…` to `226_…`) and updated the three header banners. Nothing else was
   renamed: the migration and rollback keep their names.
   - Still open for A: when PR #115 lands, mark the `20260910120000` / 188 row superseded. Row
     159 already says "pgTAP 188 retired".
   - Every reference on `venue/dashboard-v2` and in the kit still names `20260910120000` and
     must follow `20261021120000`. That work is outside this branch's paths. There are 17 files,
     and these break if they are not updated:
   - `venue/scripts/acceptance/sql/preflight.sql` (`ledger_has_venue_api`)
   - `verify-apply.sql` (ledger row name and statement count)
   - `accept.mjs:150-169`, which reads the migration path and expects 24 statements
   - `venue/src/lib/db/read-result.ts:25` (error text)
   - `adapters.ts:14` (comment)
   - `venue/tests/db-adapters.test.ts`
2. **A reviews this branch before it leaves draft.** Then a draft PR goes against the
   integration base A names. A migration-bearing PR needs `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD`
   in its description, and only the owner can attest to that.
   - **Merge order for 159** (from the registry `eef30015` timestamps, §2): after 157 and 158,
     before 170–172 and any 160–169 file. This PR merges only after A's 157 and 158 PRs are in
     the same base, and before any 160–172 PR is. Otherwise
     migrations-guard rule 4 fails 157 and 158, or 159 (§2), and A must re-timestamp.
3. **The owner authorises the apply.** It is a targeted single-file apply of
   `20261021120000_venue_api_read_views.sql` plus its ledger row, never `db push`. The sandbox
   window (D's kit) comes first, then production.
   - **Apply order for 159 on every project:** after 157 and 158, before 170–172 and any
     160–169 file. 159 applies only after
     `20261021100000` and `20261021110000` are in that project's ledger, and only while none of
     `20261021130000`, `20261021131000`, `20261021132000` or a 160–169 version is. If 159 were
     applied first, 157 and 158 would land below the ledger tip. If a 160–172 row were applied
     first, 159 would. In either case A must re-timestamp.
   - Re-run D's order probe against the target ledger before the apply.
   - **Pre-apply go/no-go read P1 (below).** Run it on the target project immediately before
     the apply, as the role that will run the apply. Expected: `t | postgres | 0 | 0`. Any other
     result means **do not apply**: report it to A and the owner. If `applying_role` is not the
     role that will run the apply, re-run P1 as that role.
   - Why it must be read before, not after: a GLOBAL table default-ACL row
     (`defaclnamespace = 0`, type `r`) of the creating role is applied when each view is created.
     The eight views are created by that role in this migration, so they would inherit the row,
     and the migration's per-schema REVOKE cannot subtract it (§1). After an apply the grant could
     only be removed by revoking it on the views by hand, which is a patch in place and a STOP
     under step 6. V4 after the apply stays the proof.

```sql
-- P1 PRE-APPLY go/no-go (read-only), as the role that will run the apply.
-- Expected: t | postgres | 0 | 0. Anything else: do not apply.
-- Column 3: global table defaults of the applying role that grant PUBLIC, anon or authenticated
--   (what pgTAP 226 F7 asserts in CI). Column 4: the same rows granting any other role except the
--   applying role itself. Either is inherited by the eight views at CREATE time, and V4 then shows
--   every such grant except a SELECT to authenticated, which the views get anyway.
select to_regnamespace('venue_api') is null as venue_api_absent,
       current_user as applying_role,
       (select count(*) from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
         where d.defaclnamespace = 0 and d.defaclobjtype = 'r'
           and d.defaclrole = (select oid from pg_roles where rolname = current_user)
           and (a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated'))))
         as global_table_default_client_grants,
       (select count(*) from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
         where d.defaclnamespace = 0 and d.defaclobjtype = 'r'
           and d.defaclrole = (select oid from pg_roles where rolname = current_user)
           and a.grantee <> 0 and a.grantee <> d.defaclrole
           and a.grantee not in (select oid from pg_roles where rolname in ('anon', 'authenticated')))
         as global_table_default_other_grants;
```

   P1 replaces the former post-apply V12. V12 was the same count keyed on the owner of
   `venue_api`, which does not exist before the apply, so P1 keys on the applying role instead
   (the role that becomes the owner, `postgres` in V1). Its old comment said a non-zero count
   "does not change the eight views". That was wrong, for the reason above.
4. **The owner adds `venue_api` to the Data API exposed schemas** (Dashboard → Settings → API →
   Exposed schemas), as a separate step after the apply. Reversal: remove it. The last recorded
   production list is `public, graphql_public, kernel, ops` (2026-09-08). It has not been re-read
   since.
5. **Data is out of scope.** Production has no venue, org or staff rows (2026-09-12 record), and
   the PFA-18C zero-data restriction still stands. Whether to create any is a separate owner
   and B decision.
6. **Read-only verification after apply.** Run these as `postgres` in the SQL editor. Expected
   values are from the local rehearsal (`verify_after_apply1.txt`). On a hosted project, any
   extra grantee in V4 or V5 is a STOP: report it, do not patch it in place.

```sql
-- V1 schema, owner, ACL
select n.nspname, n.nspowner::regrole as owner, n.nspacl from pg_namespace n where n.nspname = 'venue_api';
--  venue_api | postgres | {postgres=UC/postgres,authenticated=U/postgres}

-- V2 views (8 rows)
select table_name from information_schema.views where table_schema = 'venue_api' order by 1;
--  event_sessions, events, inventory_batches, my_org_roles, my_staff_roles, resale_policies, ticket_types, venues

-- V3 view options (8 rows, each {security_invoker=true,security_barrier=true})
select c.relname, c.reloptions from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'venue_api' and c.relkind = 'v' order by 1;

-- V4 table grants other than the owner (8 rows: <view> | authenticated | SELECT)
select table_name, grantee, privilege_type from information_schema.role_table_grants
 where table_schema = 'venue_api' and grantee <> 'postgres' order by 1, 2, 3;

-- V5 role matrix
select r.rolname, has_schema_privilege(r.rolname, 'venue_api', 'USAGE') as usage,
       has_table_privilege(r.rolname, 'venue_api.events', 'SELECT') as select_events,
       has_table_privilege(r.rolname, 'venue_api.events', 'INSERT,UPDATE,DELETE') as write_events
  from pg_roles r where r.rolname in ('anon', 'authenticated', 'service_role') order by 1;
--  anon f f f | authenticated t t f | service_role f f f

-- V6 functions in venue_api: 0
select count(*) as functions from pg_proc where pronamespace = 'venue_api'::regnamespace;

-- V7 default ACL rows in venue_api: 0
select count(*) as default_acl_rows from pg_default_acl where defaclnamespace = 'venue_api'::regnamespace;

-- V8 public census: must equal the same query run BEFORE the apply (35|126|37|49 on this chain)
select (select count(*) from pg_tables where schemaname = 'public') as tables,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public') as functions,
       (select count(*) from pg_policies where schemaname = 'public') as policies,
       (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and not t.tgisinternal) as triggers;

-- V9 base-table policies: 19, before and after
select count(*) as base_policies from pg_policies where (schemaname, tablename) in
 (('catalog','venue'),('catalog','event'),('catalog','event_session'),('catalog','resale_policy'),
  ('venue','ticket_type'),('venue','inventory_batch'),('venue','staff_role'),('kernel','org_member'));

-- V10 smoke as a signed-in identity with no grants (rolled back; no write): 0 | 0
begin;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000f00d","role":"authenticated"}', true) is not null as claims_set;
set local role authenticated;
select (select count(*) from venue_api.my_staff_roles) as my_staff_roles, (select count(*) from venue_api.my_org_roles) as my_org_roles;
rollback;

-- V11 (hosted only) ledger row present under version 20261021120000: 1 row
select version, name from supabase_migrations.schema_migrations where version = '20261021120000';

-- (V12, the global default-ACL count, is now the PRE-apply go/no-go read P1 in step 3.
--  After the apply, V4 shows any grant the eight views inherited.)
```

After a rollback (§6), these checks must return `t`, then `0 | 0 | 0`, then `19`:

```sql
-- R1
select to_regnamespace('venue_api') is null as venue_api_absent;
-- R2
select (select count(*) from information_schema.views where table_schema = 'venue_api') as views,
       (select count(*) from information_schema.role_table_grants where table_schema = 'venue_api') as grants,
       (select count(*) from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace where n.nspname = 'venue_api') as default_acl_rows;
-- R3 = V9
```

R2 used to have a fourth column, `same_named_views_anywhere`. It counted views named `venues`,
`events` and so on in **every** schema, so an unrelated later `public.events` view would make a
correct rollback look failed. It was dropped. R1 already proves the schema is gone, and with it
every view in it.

After exposure, the expected API behaviour was not rehearsed against PostgREST here:
- an `anon` request with `Accept-Profile: venue_api` is refused, because anon has no USAGE on
  the schema
- a signed-in request sees only what base RLS already allows

D's acceptance kit (V0–V10) is the instrument for this, in the sandbox window.

## 8. Limits

- **pgTAP 226 after the review rounds has not been run.** That covers the rename, the new fixture
  block, C22–C30, D6–D9, F6, F7, F8 and the reworded F3. It was written in a wave with no database access, so all
  numbers in §5 are from the plan-56 file at `460d85f9`. The checks that did run were static:
  - the migration body hash is unchanged
  - the eight F6 temp-view SELECTs are byte-identical to the migration's
  - the plan equals the assertion count

  Owed before A's review counts it:
  - a full-chain replay
  - 226 RED without the migration and GREEN with it
  - mutants r1–r7 FAILING, and the unchanged migration green on F8
  - rollback and re-apply
  - the neighbouring suites

  F7 also rests on a record. The `supabase/ci/parity_grants.sql` header (2026-08-27) says the CI
  stack carries no TABLE default-ACL entries. If the CI image does carry a global TABLE row for
  the owner granting anon or authenticated, F7 fails in CI. F1 fails with it for any grant beyond
  the SELECT to authenticated the views carry anyway (and A8, A9 or A10, depending on the grantee
  and privilege). The eight views are created by that owner in this
  migration, so they inherit the row at CREATE time, and the per-schema REVOKE cannot subtract it
  (§1). That would be a true finding about the eight views themselves, and about later objects
  too. F1 shows the inherited grant, and F7 says where it came from.

- CI's own replay (`supabase start` on CLI 2.115.0 in Docker) and `pg_prove` were not run
  locally. The evidence is the documented local equivalent. GitHub CI runs when a PR exists.
- Hosted default privileges are taken from the records (074/076: production's permissive
  default-ACL rows are all in `public`), not read. P1 before the apply is the go/no-go (§7 step 3:
  a non-zero count means do not apply). V4, V5 and V7 after the apply are the proof. F7 covers the
  CI stack only.
- The exposure step and the PostgREST behaviour are not testable locally.
