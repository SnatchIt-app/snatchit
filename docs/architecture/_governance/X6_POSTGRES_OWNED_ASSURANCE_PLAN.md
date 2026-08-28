# X-6 assurance under a `postgres`-owned export builder

**Status.** Proposal. **Nothing in this document is implemented, and no existing architecture contract is
edited by it.** It specifies the assertions that must replace the rejected privilege wall, so that the
amendments to `PHASE_2_CRM_EXPORT_SPEC.md` §10, the `ci.yml` steps, the `087` verify block and the pgTAP file
can each be authored against a single agreed target.

**Trigger.** Owner ruling **`O17` = B** (`ODR-23`): `venue.build_export_rows` stays **`postgres`-owned**; the
`crm_export_builder` role is not built. The ruling was explicit that it does not weaken the prohibition —
*"we will strengthen `X-6` through structural/catalog assertions and behavioural fixtures rather than
maintaining a parallel grant/RLS policy matrix."* This document is the discharge of that sentence.

**What `X-6` requires, unchanged.** The export builder's SQL contains **zero references** to
`kernel.identity_demographic`, `kernel.identity_demographic_erasure`, `venue.holder_mix_snapshot`,
`venue.holder_mix_bucket`. **CI-checkable and must be a CI check.**

**Scope note on the corpus.** Sections referenced as §N.N without a filename are
`docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md`. `X-1 … X-9` are from
`PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §9. `T-RPC-CRM-*` / `T-RLS-CRM-*` / `T-SCHEMA-CRM-*` are from
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §17.22 and `PHASE_2_RLS_PERMISSION_SPEC.md` §17.

---

## 0. The one-paragraph version

Layer 0 made a violation **impossible**. Layers 1–3 make it **detectable**. Rejecting Layer 0 therefore does
not cost coverage of the *known* leak paths — it costs the enforcement of paths nobody enumerated, at the
instant of execution, against code that never passed through CI. This plan closes every gap that
enumeration *can* close: it replaces §10.3's stale nine-function list with the real thirteen, replaces two
independent shallow scans with one transitive closure computed to a fixed point, replaces "the export has 21
columns" as prose with a three-way-checked manifest, replaces "the consent gate passes" with a twelve-holder
fixture whose expected counts are stated per column, and replaces the one-column blank canary with an
**execution witness** that distinguishes a gate that denied from a gate that never ran without needing a
consenting holder to exist. It cannot close the residual in §9, and §9 says so plainly.

---

## 1. What exists today, and what is prose

`X-6`'s four layers are specified across §10.1–§10.4. **Exactly one automated corpus-level gate exists in
this repository today** — the `OFFLINE-VERIFY-v1` byte-identity step inside the `quality` job of
`.github/workflows/ci.yml`. It is the *pattern* every check below is modelled on. It is not an `X-6` check.

| Specified at | Artifact it names | Exists? |
|---|---|---|
| §10.1 | `crm_export_builder` role + grant set + policies | **Ruled out** by `O17` = B |
| §10.2 | `scripts/ci/assert-no-demographics-in-export.mjs` | **No.** `scripts/` holds three files, none of them a CI scanner |
| §10.2 | `scripts/ci/demographic-objects.json` (shared constants) | **No** |
| §10.3 | Layer-2 catalog assertion in the `087` verify step | **No.** `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `087`'s *Staging verification* line names settlement checks only and **does not mention `X-6` at all** |
| §10.4 | pgTAP assertions 25–28 | **No.** `supabase/tests/` ends at `132_replay_parity.sql`; there is no CRM file |
| — | `supabase/ci/*` | Three files exist (`assert_public_table_grant_decisions.sql`, `expected_grants.txt`, `parity_grants.sql`) — the precedent for a manifest that CI diffs against the database |

### 1.1 Four defects in the existing three layers, found while reading them

These are stated here because the replacement cannot be built on top of them unamended.

**D-X6-a — §10.3's entry-point list is stale, and its non-vacuity guard is arithmetically wrong.**
§10.3 enumerates **nine** functions and guards with `if count(*) <> 9, FAIL`. `PHASE_2_RPC_FUNCTION_CONTRACTS.md`
§17.22 contracts **twelve** (`NEW RPC ×12`), and §20.7.8 adds a thirteenth shared helper,
`venue.assert_may_request`. §10.3 omits `claim_artifacts_for_purge`, `confirm_artifact_purged`,
`reconcile_export_orphans` and `assert_may_request`. The RPC spec's own `T-RPC-CRM-06` already says
*"all twelve export functions."* **Two contracts state two different expected counts for the same guard.**
Written as `<> 9` the check hard-fails on a correct database; written as `IN (<the nine>)` it passes while
never looking at four functions. The second is the 073 shape exactly.

**D-X6-b — §10.4's mirror drops the trigger limb that the demographics spec's own assertion 27 carries.**
Demographics assertion 27 enumerates readers *"plus every function attached to it as a trigger"*, and says
why: *"a trigger function reaches the table without its body naming it, so a definition-text enumeration
alone has a blind spot exactly the size of a trigger."* §10.4's mirror for `venue.holder_mix_snapshot` /
`_bucket` has no trigger limb.

**D-X6-c — §10.2 rule 4 forbids dynamic SQL "inside a function whose name matches the export builder set",
and no document defines that set.** `T-RPC-CRM-02` binds the ban to `venue.build_export_rows` alone.
A `format()`-assembled query one call deeper is outside both.

**D-X6-d — the blank-column canary (§12 34f) covers 1 of the 21 catalogued columns.** It asserts
`contact_cells_emitted > 0`. Field 2 (`display_name`) is covered only indirectly, by the `emit_name :=
emit_email` biconditional (§12 13a). Fields 1 and 3–21 have no emission assertion at all.

---

## 2. Naming, and two new assertion families

The corpus names assertions `T-<LAYER>-<DOMAIN>-<NN>`. Existing layers are `RPC`, `RLS`, `SCHEMA`
(all pgTAP), plus `DOOR-PROJ`. **There is no family for a check that runs outside the database**, which is
why the `OFFLINE-VERIFY-v1` gate — the only one that exists — has no id at all and cannot be cited.

Two families are registered here:

| Family | Runs in | Numbering |
|---|---|---|
| **`T-CI-X6-NN`** | a step of the `quality` job, `.github/workflows/ci.yml` — no database | `01`… |
| **`T-VERIFY-X6-NN`** | the `087` package's staging `verify` step; `07` additionally on a production cron | `01`… |

pgTAP additions extend the **existing** families rather than starting a third: `T-RPC-CRM-14…19` (next free
number after `T-RPC-CRM-13`) and `T-SCHEMA-CRM-10…11` (next free after `T-SCHEMA-CRM-09`).

---

## 3. The three manifests — where the truth lives so it cannot drift

Every check below reads from one of three files. **No check may carry its own copy of any of these lists.**

| Manifest | Contents | Read by |
|---|---|---|
| `supabase/ci/x6_forbidden.json` | the four prohibited relations, their unqualified spellings, the demographic attribute names, and **every term from §2.3's never-exported list** | `T-CI-X6-01`, `T-VERIFY-X6-01`, `T-RPC-CRM-14` |
| `supabase/ci/x6_entry_points.json` | the **13** export entry points, as `schema.name(argtypes)` | `T-CI-X6-05`, `T-VERIFY-X6-02`, `T-RPC-CRM-15/19` |
| `supabase/ci/crm_export_columns.json` | the **21** catalogued fields, per template and `template_version`, each with class, grain, and the fixture's expected non-blank count | `T-CI-X6-02`, `T-VERIFY-X6-03`, `T-RPC-CRM-16/18` |

`x6_forbidden.json` replaces §10.2's `scripts/ci/demographic-objects.json` and **widens it**: §10.2's list is
demographics-only, but requirement 1 of this plan is the whole of §2.3. It is placed in `supabase/ci/`
alongside `expected_grants.txt` because that is where this repository already keeps a manifest that CI diffs
against the database, and because the demographics migration package must read the same file — a rename that
does not update it must fail at the rename, not at the leak.

### 3.1 The three-way agreement rule for the column manifest

`crm_export_columns.json` sits between two things that must both match it:

```text
  §2.2's markdown table  ≡  crm_export_columns.json  ≡  the emitted CSV header
        (the contract)          (the manifest)              (the artifact)
             |                        |                          |
        T-CI-X6-02 parses        T-CI-X6-02 diffs          T-VERIFY-X6-03
        the table from the       parsed vs manifest        T-RPC-CRM-16
        spec markdown                                      compare header vs manifest
```

Any **two** agreeing while the third differs must fail. A manifest written by reading the code, or a spec
table edited without the manifest, is the drift this structure exists to catch.

---

## 4. The eight requirements

Each entry gives: **id · where · exact check · fails on · non-vacuity guard · method (catalog / text / both)**.

---

### R1 — No direct reference to a prohibited object or a §2.3 never-exported field

#### `T-CI-X6-01` — forbidden-identifier scan, widened to §2.3

**Where.** `quality` job, a step immediately after the `OFFLINE-VERIFY-v1` step and **before `npm ci`**, for
the same reason that one runs there: a broken lockfile must not be able to take the gate offline.
**Method: text.** There is no database at this point in CI, and the sources being scanned are not yet
objects. This is the one place where text is not a second-best.

**Exact check.**

```bash
set -uo pipefail
# 1. Resolve the scan set and PROVE it is non-empty.
find_list="$RUNNER_TEMP/x6_files.txt"
: > "$find_list"
while IFS= read -r pat; do
  # shellcheck disable=SC2086
  ls -1 $pat 2>/dev/null >> "$find_list" || true
done < supabase/ci/x6_scanned_paths.txt
LC_ALL=C sort -u -o "$find_list" "$find_list"
files_n=$(wc -l < "$find_list" | tr -d ' ')
[ "${files_n:-0}" -ge "$X6_MIN_SCANNED_FILES" ] || {
  echo "::error::X-6 scan resolved ${files_n} file(s), floor is ${X6_MIN_SCANNED_FILES}. A grep over nothing passes forever."; exit 1; }
echo "X-6 scan set (${files_n} files):"; cat "$find_list"

# 2. Load the forbidden terms and PROVE the list is not empty or truncated.
terms_n=$(jq -r '.terms[]' supabase/ci/x6_forbidden.json | wc -l | tr -d ' ')
[ "${terms_n:-0}" -ge "$X6_MIN_FORBIDDEN_TERMS" ] || {
  echo "::error::x6_forbidden.json yields ${terms_n} term(s), floor is ${X6_MIN_FORBIDDEN_TERMS} — the manifest was truncated and this scan would be vacuous."; exit 1; }

# 3. The scan itself, allow-marked lines excluded.
hits=$(grep -n -F -f <(jq -r '.terms[]' supabase/ci/x6_forbidden.json) -- $(cat "$find_list") \
       | grep -v -F -- '-- x6-allow: naming-only' || true)
```

**Fails on.** any hit; an empty or short scan set; an empty or short term list; an allow-marker count that
differs from `X6_EXPECT_ALLOW_MARKERS`; **and** — §10.2 rule 3, retained verbatim in intent — any term in
`x6_forbidden.json` that appears **nowhere else in the repository**, because a term that matches nothing has
been renamed and the scan is now looking for a string that no longer exists.

**Scan set.** §10.2's `SCANNED_PATHS`, plus `supabase/migrations/*settlement_and_export*.sql`, plus
**this file** — `docs/architecture/_governance/X6_POSTGRES_OWNED_ASSURANCE_PLAN.md`. This document names the
prohibited objects in order to forbid them; it is therefore a new source of every forbidden string and must
carry allow markers and be counted in `X6_EXPECT_ALLOW_MARKERS` exactly as §2.4 and §10 are.

**Non-vacuity guard.** Three floors (`X6_MIN_SCANNED_FILES`, `X6_MIN_FORBIDDEN_TERMS`,
`X6_EXPECT_ALLOW_MARKERS` as an **equality**, not a ceiling) plus the printed file list, plus the
rename tripwire, plus the positive control in `T-CI-X6-03`.

#### `T-VERIFY-X6-01` / `T-RPC-CRM-14` — the same property, in the catalog

**Where.** `087` staging verify · `supabase/tests/140_crm_export_x6.sql`. **Method: both.**

```sql
-- Text limb: no entry point's definition mentions a forbidden term.
select p.oid::regprocedure::text, t.term
  from x6_entry_points e
  join pg_proc p on p.oid = e.oid
  cross join lateral jsonb_array_elements_text(:x6_terms) as t(term)
 where pg_get_functiondef(p.oid) ~* ('\m' || t.term || '\M')
   and position('-- x6-allow: naming-only' in pg_get_functiondef(p.oid)) = 0;
-- must return zero rows

-- Catalog limb: no entry point has a pg_depend edge to a prohibited relation.
select p.oid::regprocedure::text, c.oid::regclass::text
  from pg_depend d
  join pg_proc  p on p.oid = d.objid  and d.classid    = 'pg_proc'::regclass
  join pg_class c on c.oid = d.refobjid and d.refclassid = 'pg_class'::regclass
 where p.oid in (select oid from x6_entry_points)
   and c.oid = any(:prohibited_oids);
-- must return zero rows
```

**Fails on.** either limb returning a row. **Non-vacuity guard.** `select count(*) from x6_entry_points`
must equal `X6_MIN_ENTRY_POINTS` (**13**, not 9 — see `D-X6-a`) **and** every one of the 13 must resolve to a
live `pg_proc` oid; an unresolvable name is a hard failure, never a skip. `:prohibited_oids` must have
cardinality 4 and every element must be non-null — a `to_regclass()` that returned NULL because a relation
was renamed makes the intersection trivially empty.

---

### R2 — No indirect path through a helper, view, or nested function

**This is the requirement Layer 0 discharged for free and the one that costs the most to replace.** §10.3 is
right that text and catalog each catch what the other misses and that *"neither alone is sufficient"* — but
§10.3 applies both **only to the entry points**, one hop deep. A prohibited read placed in a helper the
builder calls, or in a view the builder selects from, is invisible to both limbs of §10.3.

#### `T-VERIFY-X6-02` / `T-RPC-CRM-15` — the transitive closure, computed to a fixed point

**Where.** `087` staging verify · `supabase/tests/140_crm_export_x6.sql`. **Method: both, unioned at every
hop.** The union is not belt-and-braces; it is forced by what Postgres records:

| Callee shape | `pg_depend` edge exists? | Only source |
|---|---|---|
| view / matview referenced by anything | **Yes** — `pg_rewrite` + `pg_depend` | catalog is authoritative |
| `LANGUAGE sql … BEGIN ATOMIC` body (PG14+) | **Yes** — body is parsed and tracked | catalog is authoritative |
| `LANGUAGE plpgsql` body | **No** — the body is an opaque string literal | **text only** |
| `LANGUAGE sql … AS $$ … $$` (quoted body) | **No** | **text only** |
| `EXECUTE` / `format()` assembled at runtime | **No** | text, and only if the fragment is a literal |

**The algorithm.**

```text
INPUT   E  := the 13 entry points from x6_entry_points.json, resolved to oids
        P  := the 4 prohibited relation oids
        MAXITER := 32

C := E              -- reachable procedures
R := {}             -- reachable relations
i := 0

repeat
  i := i + 1
  IF i > MAXITER THEN FAIL "closure did not converge"   -- fail closed; never report clean
  C_prev := C ; R_prev := R

  FOR each p in C:
      -- catalog hop (procedures)
      C := C ∪ { q : pg_depend edge  pg_proc(p) -> pg_proc(q) }
      -- catalog hop (relations)
      R := R ∪ { c : pg_depend edge  pg_proc(p) -> pg_class(c) }
      -- text hop, over pg_get_functiondef(p), with search_path PINNED
      FOR each identifier tok in tokens(definition of p):
          IF to_regprocedure(tok) IS NOT NULL THEN C := C ∪ { that oid }
          IF to_regclass(tok)      IS NOT NULL THEN R := R ∪ { that oid }
      -- trigger limb (D-X6-b): a trigger function reaches its table without naming it
      R := R ∪ { tgrelid : pg_trigger where tgfoid = p }

  FOR each r in R with relkind in ('v','m'):
      -- view expansion, through the rewrite rule, NOT through the view's text
      R := R ∪ { relations referenced by pg_rewrite(r) via pg_depend }
      C := C ∪ { functions referenced by pg_rewrite(r) via pg_depend }

until C = C_prev AND R = R_prev            -- fixed point

ASSERT R ∩ P = {}                          -- the property
```

**Fails on.** a non-empty intersection; non-convergence within `MAXITER`; any identifier in a definition that
resolves under a *different* `search_path` than the pinned one (resolution ambiguity is a failure, not a
tie-break).

**Non-vacuity guard — four parts, because a closure walk is the easiest check in this document to make
vacuous.**

1. **Cardinality floors.** `|C| >= X6_MIN_CLOSURE_PROCS` and `|R| >= X6_MIN_CLOSURE_RELS`. A walk that
   silently returns the seed set has `|C| = 13` and `|R| = 0`, which is exactly the shape that passes.
2. **Depth witness.** The fixture plants `venue.__x6_probe_l1` → `__x6_probe_l2` → `__x6_probe_l3`, where
   only `l3` selects from `venue.__x6_probe_target`, and one entry point is temporarily wrapped to call
   `l1`. The assertion **requires** `__x6_probe_target ∈ R`. A walk that stops at hop 1 or 2 fails here and
   nowhere else.
3. **View witness.** A second probe reaches its target only through a view, so a walk that expands
   procedures but not `pg_rewrite` fails.
4. **Positive control (poison pill).** In a subtransaction, a probe helper is created that *does* select from
   a prohibited relation and is called by an entry point. The assertion **must fail**; the test asserts the
   failure and rolls back. An assertion that cannot be made to fail has not been shown to work.

**Contract requirement this walk imposes on `087` (stated, not made — this document edits no contract).**
Every SQL-language function in the export closure should be authored `BEGIN ATOMIC` rather than with a quoted
body, so that the catalog limb sees it. Where PL/pgSQL is required, the text limb is the only cover and the
dynamic-SQL ban of `R8` becomes load-bearing rather than defence-in-depth.

---

### R3 — The export schema is closed-world

#### `T-CI-X6-02` — spec table ≡ manifest

**Where.** `quality` job. **Method: text**, necessarily — one operand is markdown.

**Exact check.** Parse the pipe table under the `### 2.2 The catalogue` heading of
`docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md`; extract `(#, field, class, grain)`; compare as an **ordered
set** against `supabase/ci/crm_export_columns.json`.

**Fails on.** any difference in membership, order, class or grain; a missing `### 2.2` anchor; a parse
yielding a row count other than `X6_EXPECT_COLUMNS` (**21**, an equality). **Non-vacuity guard.** The
equality on 21 is the guard — a parser that silently matches zero rows cannot pass an `= 21`. Additionally
the parser must find the `### 2.3 The never-exported list` anchor and feed its terms into
`x6_forbidden.json`'s expected content, so a §2.3 edit that adds a never-exported field and does not update
the manifest fails here.

#### `T-VERIFY-X6-03` / `T-RPC-CRM-16` — manifest ≡ emitted header

**Where.** `087` verify · pgTAP. **Method: both** — the header is text, the template definition is catalog.

**Exact check.** For each of `audience_v1` and `operations_v1`, at each grain (session / event / venue / org):
build a fixture export, read row 1 of the artifact, split on the delimiter, and assert **set equality *and*
order equality** against the manifest's column list for that `(template, template_version, grain)`. Separately,
assert from the catalog that the template's stored column list (the `catalog.platform_config` seed or the
`venue.export_template` row, whichever `087` authors) equals the manifest.

**Fails on.** an extra column (the closed-world violation), a missing column, a reordering, a
`template_version` whose manifest entry does not exist. **Non-vacuity guard.** the header must be non-empty
and its cardinality must equal the manifest's for that template — `audience_v1` **12** at holder grain, **15**
at org grain, `operations_v1` **21** at purchaser grain — asserted as equalities. A build that emitted a
zero-column header would otherwise trivially satisfy "no unexpected column".

**Why `promoter_name` / `promoter_code` matter here.** §6.4 makes them **absent, not blank**, until `090`.
The manifest is therefore keyed by `template_version`, and `T-RPC-CRM-16` at `audience_v1` must assert those
two columns are **absent from the header** — not present-and-empty. A test written against "the 21 fields"
without the version key passes at `090` and fails at `087`, or worse, is relaxed until it does neither.

---

### R4 — Behavioural consent tests, with counts

#### `T-RPC-CRM-17` — fixture `F-X6-CONSENT`

**Where.** `supabase/tests/140_crm_export_x6.sql`. **Method: behavioural** (neither catalog nor text — this
is the layer that tests what the SQL *does*, which is precisely what a reference scan cannot).

**The fixture.** One org (`Org1`), one venue, one session, **12 holders**, one build, one `gate_as_of`.

| # | Holder | Consent (Org1) | Master switch | Checked in | Promoter | `email` / `display_name` |
|---|---|---|---|---|---|---|
| H1 | purchaser | granted | `allow` | admitted | attributed | **emit** |
| H2 | purchaser | granted | `allow` | not_scanned | — | **emit** |
| H3 | purchaser | **no row** | `allow` | admitted | — | suppress |
| H4 | purchaser | granted → **withdrawn** before `gate_as_of` | `allow` | not_scanned | — | suppress |
| H5 | purchaser | withdrawn → **re-granted** before `gate_as_of` | `allow` | not_scanned | — | **emit** |
| H6 | **transferee**, never purchased | — (H1 consented) | `allow` | admitted | — | suppress |
| H7 | **comped** guest | no row | `allow` | not_scanned | — | suppress |
| H8 | purchaser | granted | **`block`** | admitted | — | suppress |
| H9 | purchaser | granted **to Org2 only** | `allow` | not_scanned | — | suppress |
| H10 | purchaser | granted | `allow` | not_scanned | — | suppress — **identity deactivated** |
| H11 | purchaser | granted; **withdrawn after `gate_as_of`** | `allow` | admitted | — | **emit** |
| H12 | purchaser | granted | `allow` | admitted | attributed | **emit** |

**The expected counts, stated as numbers.**

```text
row_count                 = 12
contact_cells_emitted     =  5      (H1, H2, H5, H11, H12)
contact_cells_suppressed  =  7
name_cells_emitted        =  5      -- emit_name := emit_email, per-row biconditional
name_cells_suppressed     =  7
gate_evaluations          = 12      -- see R5
checked_in = 'admitted'   =  6      (H1, H3, H6, H8, H11, H12)
is_purchaser = true       = 10      (all but H6, H7)
promoter_name non-blank   =  2 at audience_v2 (090+);  column ABSENT at audience_v1
```

**Fails on.** any count differing from the table. Each conjunct of §5.1's four-way conjunction is falsified
by at least one holder in isolation (H3 the per-org consent, H8 the master switch, H10 liveness, and the
role conjunct by re-running the same fixture as a `venue_finance` actor and asserting the CONTACT class is
**absent from the result shape**, not blank — §17.22).

**Non-vacuity guard.** `0 < contact_cells_emitted < row_count`, asserted as a **two-sided strict** bound
before any equality is checked. See R5 — this is the bound the current design is missing.

**A second fixture, `F-X6-XORG`**, re-runs `F-X6-CONSENT` under `Org2` at the same venue after an
operatorship change, and asserts `contact_cells_emitted = 0` there while `Org1`'s stays 5 — the `XO-1a`
interaction, kept adjacent to the consent matrix because it is the same predicate with a different org
binding.

---

### R5 — A consent regression fails loudly, not silently

**The failure shape, restated.** Every contact cell blank. It reads as *"nobody consented"*. Its own
invariant — §12 assertion 13, `contact_cells_emitted + contact_cells_suppressed = row_count` — **balances
perfectly at `(0, 12)`**. The existing canary (§12 34f) catches this on **1 of 21** columns and only when a
consenting holder happens to exist in the data.

Three assertions, in increasing order of what they cover.

#### `T-RPC-CRM-18` (a) — the two-sided strict bound

`0 < contact_cells_emitted < row_count` and `0 < name_cells_emitted < row_count` on `F-X6-CONSENT`. The
left bound fails a gate that never emits; the right bound fails a gate that never denies. The existing
sum-invariant fails neither.

#### `T-RPC-CRM-18` (b) — the execution witness, `gate_evaluations`

**This is the assertion that answers the question as asked**: it distinguishes *the gate ran and denied* from
*the gate never ran* **without needing a consenting holder to exist**, which means it works in production on
real data where no expected count is known.

A **fifth** counter, `gate_evaluations`, is accumulated on the job row by the predicate itself — incremented
where the cell verdict is computed, exactly as the four existing counters are (`AUTHZ-CRM2`(1) / §12 34e):
by the code that decides, never by code that is told the verdict.

| Assertion | Statement |
|---|---|
| `T-SCHEMA-CRM-10` | `venue.export_job` carries `gate_evaluations integer NOT NULL DEFAULT 0`, and `venue.finalize_export` has **no** `p_gate_evaluations` parameter — asserted over `pg_proc.proargnames`, the same structural form as `T-RPC-CRM-08` |
| `T-RPC-CRM-18` (b) | on **every** `ready` job: `gate_evaluations = row_count` **exactly**. A gate that never ran gives `0`. A gate that ran and denied every row gives `row_count`. The blank file no longer has two readings |
| `T-VERIFY-X6-04` | the same equality, plus the §10.1 canary condition, raised as a `platform_risk` signal in production rather than only in a fixture |

#### `T-RPC-CRM-18` (c) — per-column emission counts, all 21

The manifest carries, per column and per `template_version`, the **expected non-blank cell count** over
`F-X6-CONSENT`. The assertion compares all 21 (or 12/15 by grain) as equalities. This extends the canary
from one column to the whole catalogue: a regression that blanks `acquired_via`, or `checked_in`, or
`customer_ref` currently produces a plausible file and passes every assertion in §12.

**Non-vacuity guard for (c).** Every expected count in the manifest must be `> 0` for at least one grain, and
the manifest's column count must equal `X6_EXPECT_COLUMNS`; a manifest of 21 zeroes would otherwise be
satisfied by an entirely blank file.

---

### R6 — The detector cannot pass vacuously

**Precedent, cited because it is this repository's own.** Migration `073`: *"a bare UPDATE reports success
when it matches zero rows,"* and *"every audit that read the migration source concluded the limits were in
place. They were not."* The `OFFLINE-VERIFY-v1` gate was built with that lesson explicit — a block floor, a
minimum body size, clause anchors, and a normative-home requirement — and it is the model here.

#### `T-CI-X6-03` — the floor-and-control harness

**Where.** `quality` job, the same step group as `T-CI-X6-01/02/05`. **Method: text.**

Every scan in this plan declares, in `supabase/ci/x6_floors.env`, a floor and a positive control:

| Constant | Guards | Form |
|---|---|---|
| `X6_MIN_SCANNED_FILES` | `T-CI-X6-01` | floor — an empty scan set is a hard fail |
| `X6_MIN_FORBIDDEN_TERMS` | `T-CI-X6-01` | floor — a truncated manifest is a hard fail |
| `X6_EXPECT_ALLOW_MARKERS` | `T-CI-X6-01` | **equality** — a marker added to silence a real hit fails |
| `X6_EXPECT_COLUMNS` = 21 | `T-CI-X6-02`, `T-RPC-CRM-16/18` | equality |
| `X6_MIN_ENTRY_POINTS` = 13 | `T-VERIFY-X6-01/02`, `T-RPC-CRM-14/15/19` | equality (see `D-X6-a`) |
| `X6_MIN_CLOSURE_PROCS` | `T-VERIFY-X6-02` | floor |
| `X6_MIN_CLOSURE_RELS` | `T-VERIFY-X6-02` | floor |
| `X6_MAX_CLOSURE_ITERS` = 32 | `T-VERIFY-X6-02` | ceiling — non-convergence fails, never reports clean |

**The positive control, which no layer of §10 currently has.** `supabase/ci/x6_fixtures/poison/` holds
deliberately-violating files — a `.sql` naming `kernel.identity_demographic`, a `.ts` naming `holder_mix`, a
`.sql` naming `kyc_ref`, a markdown table with 22 columns. `T-CI-X6-03` runs the scanner **against the poison
directory** and requires a **non-zero exit and a specific message**. A scanner that has been broken — a bad
glob, a `|| true` swallowing the exit code, a `jq` filter returning empty — passes `T-CI-X6-01` on a clean
tree and fails here.

**Ratchet rule, in the words the repository already uses.** Raise these when coverage grows; **never lower
one to make a red build pass.** Lowering is a reviewed decision, in the same commit that removes what it was
counting, with the manifest amended in that commit.

#### `T-VERIFY-X6-05` — the database-side positive control

The poison-pill subtransaction of `R2`'s guard 4, promoted to a named assertion so it is separately citable
and separately reportable: in the `087` verify step, create a violating helper, assert the closure check
**fails**, roll back. **Fails on** the closure check passing. The verify step's summary must print
`positive control: FAILED as required` — a verify run that does not print that line is not a verify run.

---

### R7 — Catalog and dependency metadata over grep, wherever possible

| Assertion | Method | Why that method |
|---|---|---|
| `T-CI-X6-01` | **text** | runs before any database exists; the operands are source files, not objects. Text is not second-best here, it is the only representation |
| `T-CI-X6-02` | **text** | one operand is a markdown table. Unavoidable |
| `T-CI-X6-05` | **text** | source-level dynamic-SQL ban, pre-database |
| `T-CI-X6-03` | **text** | it is a harness over text scanners |
| `T-VERIFY-X6-01` / `T-RPC-CRM-14` | **both** | text catches a literal assembled for `EXECUTE` (no catalog edge); catalog catches a reference the outer body never spells |
| `T-VERIFY-X6-02` / `T-RPC-CRM-15` | **both, at every hop** | forced by the table in R2: views and `BEGIN ATOMIC` bodies are catalog-visible and text-opaque; PL/pgSQL bodies are the reverse |
| `T-VERIFY-X6-03` / `T-RPC-CRM-16` | **both** | template definition from the catalog, emitted header from the artifact |
| `T-RPC-CRM-17` / `18` | **behavioural** | asserts what the SQL does, which no static method reaches |
| `T-VERIFY-X6-04` | **catalog + counters** | production-observable, no fixture |
| `T-RPC-CRM-19` | **catalog** | `prosrc` over a catalog-derived closure, not a file glob |

#### `T-VERIFY-X6-06` — the two methods must cover the same entry set

**Where.** `087` verify. **Method: both.** The text limb and the catalog limb of `T-VERIFY-X6-01` each
produce the set of entry points they actually examined. **Assert the two sets are equal, and equal to
`x6_entry_points.json`.** §10.3's own crux — *"a reviewer who drops one because 'the other covers it' has
reopened the hole"* — is only true while both limbs look at the same things. A catalog limb that silently
examined 9 of 13 while the text limb examined all 13 satisfies §10.3 as written and covers four functions
once.

**Non-vacuity guard.** three-way equality, all cardinalities `= 13`.

---

### R8 — Dynamic SQL, views and nested calls cannot trivially bypass it

**Verification of the claim in the brief.** `T-RPC-CRM-02` does exist and does say what was reported —
`PHASE_2_RPC_FUNCTION_CONTRACTS.md` §17.22: *"it **contains no dynamic SQL** (`T-RPC-CRM-02`: no `EXECUTE`, no
`format(`, no `quote_ident(`)"* — but it is scoped to **`venue.build_export_rows` alone**, described there as
*"the entire SQL surface that touches customer data."* §10.2 rule 4 is scoped to *"a function whose name
matches the export builder set"*, and **no document defines that set** (`D-X6-c`).

**It is not sufficient.** Under a `postgres` owner, a helper called by the builder runs with the same
authority as the builder. A `format()`-assembled query one hop deeper has no catalog dependency for the
catalog limb, is not `build_export_rows` for `T-RPC-CRM-02`, and need not appear in any file the §10.2 glob
resolves. It is the exact intersection of all three blind spots.

**It must be widened to the transitive callee set.**

#### `T-RPC-CRM-19` — no dynamic SQL anywhere in the export closure

**Where.** `supabase/tests/140_crm_export_x6.sql` and the `087` verify. **Method: catalog** — the closure is
computed by `T-VERIFY-X6-02`, then `prosrc` is scanned over it. Deliberately not a file glob: the property is
about what is *in the database*, and a file the glob missed is exactly the case that matters.

```sql
select p.oid::regprocedure::text
  from pg_proc p
 where p.oid in (select oid from x6_closure_procs)          -- the R2 fixed point, not a name list
   and (p.prosrc ~* '\mEXECUTE\M'
     or p.prosrc ~* '\mformat\s*\('
     or p.prosrc ~* '\mquote_ident\s*\('
     or p.prosrc ~* '\mquote_literal\s*\('
     or p.prosrc ~* '\mquote_nullable\s*\('
     or p.prosrc ~* '\mto_regclass\s*\('
     or p.prosrc ~* '\mto_regprocedure\s*\(');
-- must return zero rows
```

**Fails on.** any hit. The four `quote_*` / `to_reg*` additions beyond §10.2's three are deliberate:
`quote_literal`/`quote_nullable` are the other halves of the same assembly idiom, and `to_regclass` /
`to_regprocedure` are how a name is turned into an object at runtime — the shape that defeats a static
identifier scan completely.

**Non-vacuity guard.** `x6_closure_procs` must be non-empty and `>= X6_MIN_CLOSURE_PROCS`; a positive control
plants a helper containing `EXECUTE` inside the closure and requires the assertion to fail.

#### `T-CI-X6-05` — the same ban at source level

**Where.** `quality` job. **Method: text.** Scans the migration and edge sources for the same seven tokens,
restricted to function bodies whose names appear in `x6_entry_points.json` **or** in the recorded closure
from the last verify run (`supabase/ci/x6_closure.lock`, refreshed by `T-VERIFY-X6-02` and committed).
**Fails on** any hit; on `x6_closure.lock` being absent or older than the newest export migration; and on the
lock containing fewer than `X6_MIN_CLOSURE_PROCS` entries.

**Why a lock file.** CI has no database. Without a recorded closure, the source-level ban can only be applied
to names a human typed into a glob — which is `D-X6-c` reintroduced. The lock makes the database-derived
closure available to the pre-database gate, and its staleness check is what stops it becoming a fossil.

---

## 5. Assertion inventory

| Id | Where | Method | Property | Non-vacuity guard |
|---|---|---|---|---|
| `T-CI-X6-01` | `quality` | text | no forbidden term in export sources — §2.3 in full, not demographics only | file floor · term floor · marker equality · rename tripwire |
| `T-CI-X6-02` | `quality` | text | §2.2 table ≡ column manifest | `= 21` equality · anchor required |
| `T-CI-X6-03` | `quality` | text | floors + positive controls for every text scan | poison directory must fail the scanner |
| `T-CI-X6-05` | `quality` | text | no dynamic SQL in export sources, closure-scoped | lock present · lock fresh · lock floor |
| `T-VERIFY-X6-01` | `087` verify | both | no direct reference from any of the 13 entry points | `= 13` · 4 non-null prohibited oids |
| `T-VERIFY-X6-02` | `087` verify | both | **transitive closure disjoint from prohibited set** | proc/rel floors · depth witness · view witness · poison pill · `MAXITER` |
| `T-VERIFY-X6-03` | `087` verify | both | emitted header ≡ manifest, per template & version | header cardinality equalities |
| `T-VERIFY-X6-04` | `087` verify **+ production cron** | catalog + counters | `gate_evaluations = row_count`; canary raises `platform_risk` | equality on live jobs |
| `T-VERIFY-X6-05` | `087` verify | both | the closure check can be made to fail | it *is* the positive control |
| `T-VERIFY-X6-06` | `087` verify | both | text limb and catalog limb examined the same 13 | three-way set equality |
| `T-RPC-CRM-14` | pgTAP | both | `T-VERIFY-X6-01` in-suite | as above |
| `T-RPC-CRM-15` | pgTAP | both | `T-VERIFY-X6-02` in-suite | as above |
| `T-RPC-CRM-16` | pgTAP | both | `T-VERIFY-X6-03` in-suite; promoter columns **absent** at `audience_v1` | as above |
| `T-RPC-CRM-17` | pgTAP | behavioural | the 12-holder consent matrix, exact counts | two-sided strict bound |
| `T-RPC-CRM-18` | pgTAP | behavioural | (a) strict bound · (b) `gate_evaluations` witness · (c) all 21 per-column counts | manifest counts `> 0` somewhere · `= 21` |
| `T-RPC-CRM-19` | pgTAP + verify | catalog | no dynamic SQL anywhere in the closure | closure floor · `EXECUTE` poison pill |
| `T-SCHEMA-CRM-10` | pgTAP | catalog | `gate_evaluations` exists and is not a parameter of `finalize_export` | structural over `proargnames` |
| `T-SCHEMA-CRM-11` | pgTAP | catalog | the template column seed equals the manifest | `= 21` |

**Counts.** 4 CI · 6 verify · 8 pgTAP (6 `T-RPC-CRM`, 2 `T-SCHEMA-CRM`). **Catalog-based or catalog+text: 11.
Text-only: 4. Behavioural: 2. Catalog+counters: 1.**

---

## 6. Where each assertion runs, and what it costs

| Assertion | Host | Added wall-clock | Needs a database? | Blocks merge today? |
|---|---|---|---|---|
| `T-CI-X6-01/02/03/05` | `quality` job, before `npm ci` | < 5 s total | no | **yes** — `quality` is the check name branch protection already requires, so a step added there gates without a branch-protection change, exactly as the `OFFLINE-VERIFY-v1` step does |
| `T-VERIFY-X6-01/03/05/06` | `087` staging verify | seconds | staging | no — verify is not a CI job |
| `T-VERIFY-X6-02` | `087` staging verify | seconds; the closure is tens of objects, not thousands | staging | no |
| `T-VERIFY-X6-04` | `087` verify **and** a daily production pass | milliseconds per job | production | no |
| `T-RPC-CRM-14…19`, `T-SCHEMA-CRM-10/11` | `db` job, pgTAP suite, `supabase/tests/140_crm_export_x6.sql` | the fixtures dominate; `F-X6-CONSENT` is 12 holders | ephemeral CI database | **yes**, once the file exists |

**Do not put the CI checks in a new workflow.** The repository's own comment on the existing gate is the
reason: the check name `Typecheck / Lint / Unit tests` is load-bearing in branch protection, and a gate added
as a step inside it blocks merge today with no rename and no settings change.

### 6.1 Floors that must move

| Constant | File | Today | Must become | When |
|---|---|---|---|---|
| `MIN_FILES` | `.github/workflows/ci.yml` | `17` | **`18`** | the commit that adds `supabase/tests/140_crm_export_x6.sql` |
| `MIN_ASSERTIONS` | `.github/workflows/ci.yml` | `305` | **`357`** | same commit — the new file plans **52**: `T-RPC-CRM-14` 4 · `15` 8 · `16` 6 · `17` 14 · `18` 9 · `19` 5 · `T-SCHEMA-CRM-10` 3 · `11` 3 |
| `OFFLINE_VERIFY_MIN_BLOCKS` | `.github/workflows/ci.yml` | `4` | **`4` — unchanged** | this document adds no sanctioned mirror and must not; it is scanned by that gate because the scan is recursive over `docs/architecture/**`, and it contains no tagged fence |
| `MASK_MAX_TODO_CALLS` / `MASK_MAX_TODO_FAILURES` / `MASK_MAX_MASKED_ASSERTIONS` | `.github/workflows/ci.yml` | ratchets | **unchanged** | no `X-6` assertion may ever land under `todo()`. If one cannot pass, it does not land |
| `X6_*` (eight constants, §R6) | `supabase/ci/x6_floors.env` | — | new | with the first check that reads each |

**The `MIN_ASSERTIONS` move is the load-bearing one.** A pgTAP file that is added without raising the floor
can later be deleted and the suite still passes — which is the entire reason the floor exists.

---

## 7. Sequencing — before `087`, and after

### Must be true **before** `087` is authored

1. **`D-X6-a` resolved.** §10.3's nine-function list corrected to the thirteen of RPC §17.22 + §20.7.8, and
   `x6_entry_points.json` written **from the contract**, not from the code. A manifest written after the
   function exists is a manifest written to match it.
2. **The three manifests exist and are populated** (§3). `crm_export_columns.json` in particular: `087`
   authors the templates, and the template seed must be generated from the manifest rather than the reverse.
3. **`T-CI-X6-01`, `02`, `03` are live and required.** All three are text-only, need no database, and can run
   against the corpus **today**. There is no reason for them to wait for `087`, and one strong reason not to:
   they are what stops the spec drifting between now and then.
4. **The closure algorithm (§R2) is agreed**, including `X6_MAX_CLOSURE_ITERS` and the two probe shapes,
   because `087` must author its functions to suit it — `BEGIN ATOMIC` where the language allows, so the
   catalog limb sees the body.
5. **`gate_evaluations` is in the `087` schema delta.** It is a column on `venue.export_job` and a counter
   incremented inside the builder. Adding it later means editing the builder and the finalize contract in a
   package that has already shipped.
6. **`087`'s *Staging verification* line in `PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 names `X-6`.** It
   currently names settlement checks only. A verify step that does not mention the check is a verify step
   that will not run it.

### May land with or after `087`

- `T-VERIFY-X6-01…06` — they need a staging database with `087` applied.
- `T-RPC-CRM-14…19`, `T-SCHEMA-CRM-10/11` and `supabase/tests/140_crm_export_x6.sql` — they need the objects.
  **Same commit as the `MIN_FILES` / `MIN_ASSERTIONS` raise**, never a later one.
- `T-CI-X6-05` — it needs `x6_closure.lock`, which only a verify run can produce.
- `T-VERIFY-X6-04`'s production cron — after `087` reaches production.
- `T-RPC-CRM-16`'s `audience_v2` limb — at `090`, when the promoter columns appear.

### Not deferrable, stated because deferral is how this fails

`T-VERIFY-X6-02` — the transitive closure — is the assertion that replaces what Layer 0 did. Landing
`T-VERIFY-X6-01` alone and calling `X-6` covered would leave `X-6` exactly where §10.3 already leaves it: one
hop deep, with the helper and the view uncovered.

---

## 8. Two corrections this plan depends on

Neither is made here.

**`D-X6-b`** — §10.4's mirror needs the trigger limb demographics assertion 27 already carries. The R2
closure includes it (`pg_trigger.tgfoid → tgrelid`), but the pgTAP mirror in §10.4 should say so in the same
words, for the same reason: *"a trigger function reaches the table without its body naming it."*

**`D-X6-c`** — §10.2 rule 4's "export builder set" must be defined as `x6_entry_points.json` ∪ the recorded
closure, and `T-RPC-CRM-02`'s scope widened from `build_export_rows` to that set (which is `T-RPC-CRM-19`).

---

## 9. Residual risk — what Layer 0 bought that no test here replicates

Stated as a residual, not as reassurance. Five things are genuinely lost, and the plan above recovers none of
them.

**1. Enforcement outside the repository.** Every assertion in this document is a statement about a tree that
CI read, or a database that a verify step connected to. **The privilege wall was a statement about the
database at every instant, including instants no pipeline observed.** This repository has a live path that
bypasses CI entirely: `ci.yml`'s own header records that the Supabase GitHub integration *"applies pending
`supabase/migrations/**` to the PRODUCTION database on every merge to main"* and *"put migration 071 into
production on 2026-08-27 with no approval gate."* A `CREATE OR REPLACE venue.build_export_rows` applied by
hand, or through a path CI never sees, reads `kernel.identity_demographic` successfully and **nothing in this
plan fires until the next verify run — and verify runs against staging.** `T-VERIFY-X6-04`'s daily production
pass narrows the window from "until someone re-runs verify" to "24 hours". It does not close it, and 24 hours
is enough time to build and download an export.

**2. Enforcement against paths nobody enumerated.** The closure walk is exhaustive over what the catalog and
`prosrc` can express. Layer 0 needed no enumeration at all — it constrained the *authority*, and authority is
closed under every route, including the ones the walk cannot see: a `search_path` re-resolution at runtime, a
name assembled from `catalog.platform_config`, a foreign table, a function created after the check ran and
dropped before the next. `T-RPC-CRM-19` forbids the idioms that make those reachable; a ban is not a wall.

**3. Failure at the first execution, including in tests nobody wrote.** Under Layer 0, a violation surfaced as
`permission denied` the first time *any* code path ran the builder — a developer's fixture, a smoke test, an
operator's export. Every assertion here fires only when *its own* check runs. Coverage is now a function of
what someone remembered to assert.

**4. A control with no maintainer.** A grant cannot go vacuous. It has no floor to raise, no expected count
to keep current, no positive control to keep honest, and no glob to keep resolving. **Every check in this
document can be made vacuous by a well-meaning edit**, which is why §R6 exists — and §R6 is itself a set of
constants that a human can lower. The repository's own precedent is exactly this: migration `073`, where
*"every audit that read the migration source concluded the limits were in place. They were not."* The floors
here are the best available answer to that, and they are strictly weaker than not needing them.

**5. Blast radius under a compromised body.** If an attacker can write the builder's body — a compromised CI
token, a malicious migration, a confused-deputy edit — Layer 0 still denied the read, because the grant was
not in the body's gift. Every assertion here would be authored, reviewed and merged by the same pipeline the
attacker just used.

**The honest one-line residual.** *After `O17` = B, `X-6` is a property of this repository's checks rather
than a property of the database. `venue.build_export_rows` holds implicit read on all four demographic
objects at all times; what stands between that authority and its use is a set of assertions whose enforcement
window is "whenever CI or verify last ran", and whose completeness is bounded by an enumeration a human
maintains.*

### 9.1 The one compensating control worth adding, since it is not a grant

`T-VERIFY-X6-04`'s **daily production pass** is the only item in this plan that changes the *class* of the
residual rather than its size: it moves the closure and counter checks from "CI-time, staging" to "daily,
production". It reuses an agent `087` already builds — the daily orphan reconciliation of `T-RPC-CRM-11` —
and it raises `platform_risk` rather than failing a build, because there is no build to fail. It is
recommended, and it is not a substitute for anything in §9.

### 9.2 What was never in Layer 0's gift either

§10.5's own limit is unchanged and is restated so the residual is not read as larger than it is: nothing here
or in Layer 0 stops a human reading the on-screen aggregate card and typing values into a spreadsheet. That
path is bounded by the demographics spec — the card never shows an individual value, and the aggregate is
suppressed below k = 25 — which is a property of that document, not this one.

---

## 10. Open items for the owner

| # | Item | Recommendation |
|---|---|---|
| `X6-Q1` | Does `T-VERIFY-X6-04`'s daily production pass get built at `087`, or deferred? | **Build at `087`.** It is the only control that narrows residual **1**, and it rides an agent `087` already creates |
| `X6-Q2` | `gate_evaluations` — a fifth counter on `venue.export_job`, decided now or after `087` | **Now.** It is one column and one increment at authoring time; afterwards it is an edit to a shipped builder and a shipped finalize contract |
| `X6-Q3` | `D-X6-a`: nine or thirteen entry points | **Thirteen.** RPC §17.22 is the contract; §10.3 is stale. This must be settled before anything hard-codes a count |
| `X6-Q4` | Do `T-CI-X6-01/02/03` land now, ahead of `087`? | **Yes.** They need no database and they are what keeps the spec from drifting between now and `087` |

---

## 11. Provenance

Read while authoring: `PHASE_2_CRM_EXPORT_SPEC.md` §2.2, §2.3, §2.4, §5.1, §6.4, §6.5, §10.1–§10.5, §12 ·
`PHASE_2_DEMOGRAPHICS_PRIVACY_SPEC.md` §9 (`X-1…X-9`), assertion 27 · `PHASE_2_RPC_FUNCTION_CONTRACTS.md`
§17.21, §17.22, §20.7.8 · `PHASE_2_RLS_PERMISSION_SPEC.md` §16.10, §17 ·
`PHASE_2_SUPABASE_MIGRATION_PLAN.md` §8 `087` · `_governance/PHASE_2_OWNER_DECISION_REGISTER.md` `ODR-23` ·
`.github/workflows/ci.yml` (the `quality` and `db` jobs in full) · `supabase/tests/` (17 files) ·
`supabase/ci/` (3 files).

**This document creates no object, edits no contract, and asserts nothing on its own.** It is the target the
`X-6` implementation should be written against.
