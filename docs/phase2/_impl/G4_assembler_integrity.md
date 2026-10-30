# G-4 — Assembler integrity: the slices and the assembled migration cannot drift

**Status:** implemented, gated in CI, self-tested (24 scenarios), and hardened
after an adversarial pass found four bypasses in the first revision.
**Scope:** every migration in `supabase/migrations/` generated from reviewed
slices. Today that is 093; the mechanism is generic and 094/095 need no change.

---

## 1. The canonical-source rule (settled)

> **THE SLICES ARE CANONICAL. The assembled migration is a build artifact.**

| | |
|---|---|
| Canonical source | `docs/phase2/_impl/093_parts/*.sql` |
| Build tool | `scripts/assemble_093.sh` |
| Build artifact | `supabase/migrations/093_primary_ticketing.sql` |

**Determined, not assumed.** Four pieces of pre-existing evidence:

1. **The assembler's header** already said so: *"The parts stay in the repo as
   the review surface; the assembled file is what the chain applies"* and *"Edit
   the parts, not this file, then re-run the assembler."*
2. **Every slice header declares itself a fragment of a build.**
   `10_money_settlement.sql`: *"FRAGMENT, not a migration: no `begin;` /
   `commit;` here — 093 wraps the assembled parts in ONE transaction."*
   `40_config_privacy_freeze.sql`: *"the 093 assembler owns the transaction, so
   this file must remain safe to concatenate in place."* A slice is not
   independently applicable; the artifact is. That is input and output, not two
   peers.
3. **The assembler is a pure ordered concatenation** with a header it generates
   itself. Nothing can enter the artifact except through a slice or through the
   assembler, and no inverse tool exists that could decompose an edited 093 back
   into four owner-ruling-aligned slices.
4. **How the last train actually operated:** agents edited slices; the owner
   re-assembled. The reported failure — *"an agent ran the assembler mid-review
   and the committed migration had silently drifted"* — is a build-ordering
   failure, which only makes sense under rule (A).

Rule (B) — 093 canonical, slices as review aids — is rejected: it would demote
the reviewed artifacts (each tied to a specific owner ruling) to advisory, and
make a 4,000-line concatenation the review surface, which is the thing the slice
split exists to avoid.

### Enforced, not merely written down

* The artifact opens with a **generated-file banner** (§3), whose first line is
  machine-read.
* CI **regenerates the artifact from the committed slices with the committed
  assembler and compares it byte-for-byte** on every PR.
* **The banner cannot drift**, because it *is* assembler output: editing it in
  the migration fails the same byte comparison as any other hand-edit.
* **There is no workflow where a developer can edit both and have both "work".**
  Slice only → stale artifact → fail. Artifact only → hand-edit → fail. Both by
  hand → not the assembler's output → fail. The single passing path is: edit the
  slice, run `./scripts/assemble_093.sh`, commit both.

### Interaction with migration immutability

Once 093 merges, the artifact becomes immutable under invariant 1 of the
migrations guard. **The slices freeze at the same moment**, because any slice
edit forces an artifact change that invariant 1 rejects. Correct and intended: a
migration's reviewed source is history too. Later changes are a new migration
(and, if assembled, a new parts directory and a new assembler).

---

## 2. THE AUTHORITY RULE — the thing this gate gets right

> **THE GATE NEVER TAKES THE ASSEMBLER'S WORD FOR WHAT TO CHECK.**

The first revision of this gate read the assembler's own `--manifest` and
treated it as the source of truth for which slices existed and where they lived.
That is the same class of error as trusting a caller-supplied `acct_` id — which
this repo already fixed once by requiring platform-minted provenance instead of
a blocklist. An adversarial pass produced **four working bypasses**, each exiting
0 while the slices and the artifact genuinely disagreed.

Every fact the gate acts on is now derived independently:

| Fact | Old (trusted) | New (derived) |
|---|---|---|
| Which files are slices | `part=` lines in the manifest | `git ls-files` over the derived directory |
| What kind of file | nothing | git mode (100644/100755 only) **and** on-disk `-f` / `! -L` |
| Where the slices live | `parts_dir=` in the manifest | derived from the assembler's **filename** |
| Where the artifact is | `out=` in the manifest | derived: the one tracked `<TAG>_*.sql` |
| What the build could read | `cp -R scripts/.` into the sandbox | **hermetic** sandbox: assembler + git-inventoried slices, nothing else |
| That the SQL survived | assumed | each slice's committed bytes must occur in the artifact **exactly once** |
| That the assembler is the reviewed one | assumed | tracked, regular, and (in CI) equal to its HEAD blob |

`--manifest` is still required, but only as a **cross-check**: the gate compares
it against the derived facts and fails on any disagreement. It is evidence, not
authority.

**Union proof.** Across all assemblers: every committed slice under
`<SLICE_ROOT>/*_parts/` is consumed exactly once, and every consumed input is a
committed slice. Neither direction may be empty.

**Path confinement.** Every input path must be repo-relative, free of `..`,
within `[A-Za-z0-9._/-]`, and must resolve (after following any symlinked parent)
to a location under the repository root.

---

## 3. The generated-file banner

Emitted by the assembler as the first 17 lines of the artifact:

```
-- @generated-by: scripts/assemble_093.sh
-- =============================================================================
-- !!  GENERATED FILE — DO NOT EDIT BY HAND  !!
--
-- Assembled from the reviewed slices in docs/phase2/_impl/093_parts/.
-- THE SLICES ARE CANONICAL. This file is a build artifact.
...
```

The first line does double duty: for a human it names the tool, for the gate it
is the **discovery key**. Every `supabase/migrations/*.sql` is scanned for
`^-- @generated-by: `, and each hit must be claimed by a discovered assembler
that reproduces it. That closes the "delete the inputs to make the gate green"
hole: deleting the slices makes the assembler exit non-zero; deleting the
assembler leaves an artifact whose own banner points at a file that is gone.

**The banner is the only change this work made to `093_primary_ticketing.sql`:
17 lines added, 0 removed, 0 modified**, verified by diff against the
pre-change file (`md5 6ab87362e3a6983d0ad1355758835402`, 4,038 lines). No SQL
was authored or edited.

---

## 4. The gate

| | |
|---|---|
| Gate | `scripts/ci/assembled_migration_integrity.sh` |
| Self-test | `scripts/ci/assembled_migration_integrity_selftest.sh` |
| CI home | `.github/workflows/migrations-guard.yml`, job `guard` (`Migrations guard / Immutability + ordering`), **first two steps** |
| New required checks added | **none** |

### Why that home

`Migrations guard / Immutability + ordering` is already the required status
check for `supabase/migrations/**`. A separate job would be a second required
context reporting nothing until it had run once — the *disappearing required
check* deadlock documented in `ci.yml` beside the pgTAP step. Two steps in one
job cost one check and block merge just as hard.

**The G-4 steps run FIRST, before the job's change detection.** The job
early-exits when nothing under `supabase/migrations/` changed, and the drift
this catches is most often a PR that edits *only slices*. Placed after the
early-exit the guard would be silent in exactly the case it exists for. It is
also before the AUTODEPLOY-1 acknowledgement, so a drifted PR reports the drift.

CI invokes it as `assembled_migration_integrity.sh --require-committed`.

### Modes

| Mode | When | Behaviour |
|---|---|---|
| `--require-committed` | CI (also implied by `$CI`) | every input must equal its HEAD blob; a difference is an **error** |
| default | local pre-commit use | inventory and modes still come from git; content is read from the worktree and any difference from HEAD is a loud **notice** |

### What it does, in order

0. **The git authority must BE this repository** — `git rev-parse --show-toplevel`
   must resolve to the gate's own root. Without this, running in a non-repo
   directory silently inherits the index of whatever repo lies above it.
1. **Discover assemblers** — `scripts/assemble_*.sh`, sorted under `LC_ALL=C`.
   Zero → fail (floor).
2. **Discover generated migrations** by banner. Zero → fail (floor).
3. **The committed slice universe** — tracked `*.sql` under
   `<SLICE_ROOT>/*_parts/`. Below the floor → fail.
4. Per assembler:
   - **4a** the assembler is tracked, a regular file, executable, `bash -n` clean;
   - **4b** `parts_dir` and `out` **derived** from `scripts/assemble_<TAG>.sh`;
   - **4c** slice inventory **from `git ls-files`**: each tracked, regular, not a
     symlink (index *and* disk), non-empty, path-confined, `.sql`, newline-terminated;
   - **4d** the manifest is **cross-checked** against 4b/4c — omissions, extras,
     duplicates, unsafe names, wrong paths all fail;
   - **4e** static non-determinism scan + required `export LC_ALL=C`;
   - **4f** **hermetic rebuild** into an empty migrations dir, then a
     **stowaway check** that the sandbox holds exactly assembler + slices + one artifact;
   - **4g** `cmp` byte-for-byte, with drift localised to a slice;
   - **4h** **consumption proof**: each slice's committed bytes occur in the
     artifact exactly once;
   - **4i** rebuild again under a different locale, collation, timezone, umask and cwd.
5. **Union proof** across all assemblers (with an explicit note when an assembler
   bailed earlier, so its consequences are not misreported as independent findings).
6. **Banner reconciliation** — no orphan artifacts.

### The failure message

```
::error::DRIFT: supabase/migrations/093_primary_ticketing.sql is NOT the output of
         ./scripts/assemble_093.sh over the committed slices in docs/phase2/_impl/093_parts.
::error::FIX: run  ./scripts/assemble_093.sh  and commit the regenerated
         supabase/migrations/093_primary_ticketing.sql (together with any slice change).
::error::Do NOT hand-edit ... — the slices in docs/phase2/_impl/093_parts are canonical
         and the next assembler run reverts any edit made here.
::error::drift is localised to: 30_connect_org.sql 40_config_privacy_freeze.sql
```

The artifact is split on its `-- ## SLICE: ` markers and compared section by
section, so the reviewer is told *which slice* to re-read rather than handed a
5,000-line diff. If the slice **sequence** differs, both orders are printed.
Both are optional refinements: an assembler emitting no slice markers still gets
the plain diff, byte counts, and checksums.

### Generic by construction

Nothing in the gate, self-test, or workflow names 093. To gate an assembled 094:
add `scripts/assemble_094.sh` implementing `--manifest` and the banner, put its
slices in `docs/phase2/_impl/094_parts/`, name the migration `094_*.sql`. The
path convention **is** the derivation, so there is nothing to register.

---

## 5. Scenarios and evidence

`scripts/ci/assembled_migration_integrity_selftest.sh` builds a throwaway **git
repository** per scenario containing the real assembler and the real slices,
applies one mutation, runs the **real gate**, and asserts a non-zero exit *and*
the message a human needs.

**What the first self-test got wrong:** every scenario mutated a slice or the
artifact, and the baseline was rebuilt with the sandbox's own assembler — so an
attack carried out *in the assembler* cancelled itself out. The B-series below
mutates the **assembler or its manifest** and leaves the artifact perfectly
consistent with the subverted build.

A **negative control** runs first: the untouched sandbox must PASS.

### B-series — the four adversarial bypasses (regression evidence)

Each was executed against **both** gate revisions in the same sandbox:

| Bypass | Old gate | New gate | Caught by |
|---|---|---|---|
| **1** manifest omits a committed slice (paired with a decoy dir) | **exit 0** | **exit 1** | git inventory vs manifest (4d) |
| **2** assembler concatenates a non-slice file smuggled via `scripts/` | **exit 0** | **exit 1** | hermetic sandbox (4f) |
| **3** slice committed as a symlink | **exit 0** | **exit 1** | git mode 120000 (4c) |
| **4** decoy `parts_dir` redirects the build | **exit 0** | **exit 1** | derived path vs declared (4b/4d) |

```
BYPASS 1+4 lying manifest + decoy dir       old-gate=0  NEW-gate=1
BYPASS 2 smuggled via cp -R scripts/.       old-gate=0  NEW-gate=1
BYPASS 3 slice is a symlink                 old-gate=0  NEW-gate=1
BYPASS 4 decoy parts_dir                    old-gate=0  NEW-gate=1
```

### The full 24-scenario run (identical in local and `CI=true` modes)

```
PASS  CONTROL untouched tree reproduces                        (gate exit 0)
PASS  B1 manifest omits a committed slice                      (gate exit 1)
PASS  B2 assembler concatenates a non-slice file               (gate exit 1)
PASS  B3 slice committed as a symlink                          (gate exit 1)
PASS  B3b slice replaced by a symlink after commit             (gate exit 1)
PASS  B4 decoy parts_dir redirects the build                   (gate exit 1)
PASS  B5 declared slice silently not concatenated              (gate exit 1)
PASS  B6 slice concatenated twice                              (gate exit 1)
PASS  B7 assembler writes a stowaway file                      (gate exit 1)
PASS  S1 missing slice                                         (gate exit 1)
PASS  S2 duplicated slice                                      (gate exit 1)
PASS  S3 changed slice order                                   (gate exit 1)
PASS  S4 stale artifact (slice edited, not rebuilt)            (gate exit 1)
PASS  S5 hand-edit to the artifact                             (gate exit 1)
PASS  S6 whitespace drift (one trailing space)                 (gate exit 1)
PASS  A1 slice directory deleted                               (gate exit 1)
PASS  A2 assembler deleted, artifact kept                      (gate exit 1)
PASS  A3 banner stripped from the artifact                     (gate exit 1)
PASS  A4 slice committed but never assembled in                (gate exit 1)
PASS  A5 artifact deleted (assembler and slices kept)          (gate exit 1)
PASS  A6 untracked slice declared by the assembler             (gate exit 1)
PASS  A7 sandbox is not a git repository                       (gate exit 1)
PASS  D1 timestamp introduced into the assembler               (gate exit 1)
PASS  D2 environment leaks into the output                     (gate exit 1)

scenarios: 24   behaved as specified: 24   misbehaved: 0
```

### The six drift scenarios from the original brief

| # | Scenario | Detector | Message |
|---|---|---|---|
| 1 | Missing slice | manifest vs git inventory | `declares slice(s) that are NOT committed` |
| 2 | Duplicated slice | duplicate check | `lists the same slice more than once` |
| 3 | Changed slice order | byte compare + sequence localisation | `SLICE SEQUENCE differs`, both orders printed |
| 4 | Stale artifact | byte compare | `DRIFT:` + `drift is localised to: <slice>` + `run ./scripts/assemble_093.sh` |
| 5 | Hand-edit to the artifact | byte compare | `DRIFT:` + `Do NOT hand-edit` |
| 6 | Whitespace drift (one trailing space) | byte compare | `DRIFT:` + `drift is localised to: __preamble__` |

### Beyond the brief

| # | Scenario | Detector |
|---|---|---|
| B5 | Declared slice never concatenated | consumption proof: `do not appear in … at all` |
| B6 | Slice concatenated twice | consumption proof: `appear 2 times` |
| B7 | Assembler writes a second file | stowaway check |
| B3b | Symlink swapped in after commit | on-disk `-L` check (index says regular) |
| A1–A5 | Inputs deleted, banner stripped, slice never assembled in | floors and inventory |
| A6 | Untracked slice declared as an input | `NOT TRACKED IN GIT` |
| A7 | Run outside a git repository | toplevel assertion |
| D1/D2 | Timestamp in the assembler; environment leaking into the output | static scan; perturbed rebuild |

---

## 6. Assembler determinism

`scripts/assemble_093.sh` was already deterministic in substance — explicit part
array, no `find`, no glob, no timestamp, no `git` call — and repeated runs were
byte-identical before any change. **No non-determinism had to be fixed.** Three
changes, all hardening:

* **`export LC_ALL=C`**, so no future `sort` or collation-sensitive comparison
  can make the output machine-dependent. The gate now *requires* the pin.
* **`--manifest` mode**, for cross-checking (not authority).
* **Header rewritten** to state the canonical rule and the determinism contract.

The gate proves determinism on every run by rebuilding twice under different
locale, collation, timezone, umask and working directory; D2 confirms that
comparator fires.

---

## 7. Operational note

While this gate was being built it caught **live drift in the working tree**
twice — concurrent slice edits to `10_money_settlement.sql`,
`30_connect_org.sql` and `40_config_privacy_freeze.sql` landing after the
artifact had been assembled — reporting, correctly,
`drift is localised to: 30_connect_org.sql 40_config_privacy_freeze.sql`.

That is the exact failure mode from the last train, observed live, before a
reviewer had to notice it by hand. It was resolved the only legitimate way, by
re-running the official assembler. Final verified state:

```
OK: manifest agrees with the committed tree (4 slices, derived paths)
OK: hermetic rebuild produced exactly supabase/migrations/093_primary_ticketing.sql and nothing else
OK: every committed slice's bytes appear in the artifact exactly once
G-4 PASS   (5226 lines, md5 e139aeb5bb48df63393dd93cb116bbb2)
```

**Whoever lands the 093 slice train must run `./scripts/assemble_093.sh` as the
last step before committing.** While several agents edit slices in one working
tree, any earlier rebuild is stale the moment the next slice edit lands. CI now
says so if it is forgotten, and names the slice.
