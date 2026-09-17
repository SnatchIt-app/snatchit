#!/usr/bin/env bash
# =============================================================================
# SELF-TEST for scripts/ci/assembled_migration_integrity.sh  (G-4)
#
# A guard nobody has watched fail is not a guard. This script builds a throwaway
# GIT REPOSITORY containing the real assembler and the real slices, breaks it in
# one specific way per scenario, runs the REAL gate against it, and asserts the
# gate exits non-zero with the message a human needs.
#
# WHAT THE FIRST VERSION OF THIS FILE GOT WRONG
#   Every scenario mutated a SLICE or the ARTIFACT, and the baseline was rebuilt
#   with the sandbox's own assembler. So any attack carried out IN THE ASSEMBLER
#   cancelled itself out: the assembler lied, the baseline was built by the same
#   lying assembler, the two agreed, and the self-test reported green. A
#   self-test that cannot catch a subverted assembler is testing the wrong half.
#
#   The B-series below therefore mutates the ASSEMBLER or its MANIFEST and
#   leaves the artifact perfectly consistent with the subverted build. Each of
#   those four passed the previous gate. They must all fail now.
#
# Sandboxes are real git repositories because the gate takes its facts from the
# git index, not from the assembler. Nothing here touches the real repository:
# every mutation happens inside $TMPDIR.
#
# Usage:  scripts/ci/assembled_migration_integrity_selftest.sh
# Exit:   0 = every scenario behaved as specified.
# Docs:   docs/phase2/_impl/G4_assembler_integrity.md
# =============================================================================
set -uo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

GATE_REL="scripts/ci/assembled_migration_integrity.sh"
MIG_DIR="${G4_MIGRATIONS_DIR:-supabase/migrations}"
SLICE_ROOT="${G4_SLICE_ROOT:-docs/phase2/_impl}"

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/g4self.XXXXXX")" || exit 1
trap 'rm -rf "$TMPROOT"' EXIT

# Scenarios are written against the FIRST assembler found, discovered the same
# way the gate discovers it. Nothing below names 093.
ASM=""
for a in scripts/assemble_*.sh; do [ -e "$a" ] && { ASM="$a"; break; }; done
[ -n "$ASM" ] || { echo "::error::self-test found no scripts/assemble_*.sh to exercise."; exit 1; }
TAG="${ASM#scripts/assemble_}"; TAG="${TAG%.sh}"
PARTS_DIR="$SLICE_ROOT/${TAG}_parts"
OUT="$(git ls-files -- "$MIG_DIR" | grep -E "^${MIG_DIR}/${TAG}_[A-Za-z0-9_]+\.sql$" | head -1)"
[ -n "$OUT" ] || { echo "::error::no committed ${MIG_DIR}/${TAG}_*.sql to exercise."; exit 1; }
SLICES="$(git ls-files -- "$PARTS_DIR" | sed 's#.*/##' | sort)"
P1="$(printf '%s\n' "$SLICES" | sed -n 1p)"
P2="$(printf '%s\n' "$SLICES" | sed -n 2p)"
PL="$(printf '%s\n' "$SLICES" | tail -1)"
# "../" repeated once per path component of $PARTS_DIR: how a slice reaches the
# sandbox root. Derived, so the B3 symlinks do not break if SLICE_ROOT moves.
UP="$(printf '%s' "$PARTS_DIR" | awk -F/ '{s=""; for (i=1; i<=NF; i++) s = s "../"; print s}')"

echo "== G-4 gate self-test =="
echo "assembler under test: $ASM   (tag $TAG)"
echo "artifact:             $OUT"
echo "slices:               $PARTS_DIR"
echo

passes=0; failures=0; n=0

# sandbox <name> — assembler + slices only. No artifact yet, no git yet, so a
# scenario can subvert the assembler BEFORE the baseline artifact is built.
sandbox() {
  local sb="$TMPROOT/$1" b
  mkdir -p "$sb/$(dirname "$ASM")" "$sb/$PARTS_DIR" "$sb/$MIG_DIR" "$sb/scripts/ci"
  cp "$ASM" "$sb/$ASM"; chmod +x "$sb/$ASM"
  cp "$GATE_REL" "$sb/$GATE_REL"; chmod +x "$sb/$GATE_REL"
  while IFS= read -r b; do
    [ -n "$b" ] && cp "$PARTS_DIR/$b" "$sb/$PARTS_DIR/$b"
  done <<EOF
$SLICES
EOF
  printf '%s' "$sb"
}

# sb_build <sb> — produce the baseline artifact with the SANDBOX's assembler.
sb_build() { ( cd / && "$1/$ASM" ) >/dev/null 2>&1; }

# sb_git <sb> — make it a real repository so `git ls-files` is meaningful.
sb_git() {
  local sb="$1"
  git -C "$sb" -c init.defaultBranch=main init -q
  git -C "$sb" -c core.excludesFile=/dev/null add -A -f
  git -C "$sb" -c user.name=g4 -c user.email=g4@example.invalid commit -q -m baseline
}

# check <pass|fail> <label> <sandbox> [required substring...]
check() {
  local expect="$1" label="$2" sb="$3"; shift 3
  local log="$sb/.gate.log" rc s ok=1 why=""
  n=$((n + 1))
  "$sb/$GATE_REL" > "$log" 2>&1; rc=$?
  [ "$expect" = "pass" ] && [ "$rc" -ne 0 ] && { ok=0; why="expected exit 0, got $rc"; }
  [ "$expect" = "fail" ] && [ "$rc" -eq 0 ] && { ok=0; why="expected NON-ZERO exit, got 0 — THE GATE DID NOT NOTICE"; }
  for s in "$@"; do
    grep -qF -- "$s" "$log" || { ok=0; why="$why; message missing: '$s'"; }
  done
  if [ "$ok" -eq 1 ]; then
    passes=$((passes + 1)); printf 'PASS  %-56s (gate exit %s)\n' "$label" "$rc"
  else
    failures=$((failures + 1)); printf 'FAIL  %-56s %s\n' "$label" "$why"
    echo "----- gate output -----"; sed 's/^/    /' "$log"; echo "-----------------------"
  fi
}

# edit_asm <sb> <sed expr...> — rewrite the sandbox's assembler in place.
edit_asm() {
  local sb="$1"; shift
  sed "$@" "$sb/$ASM" > "$sb/$ASM.new" && mv "$sb/$ASM.new" "$sb/$ASM" && chmod +x "$sb/$ASM"
}

# ===========================================================================
# CONTROL — an untouched sandbox must PASS. Without it, a gate that failed
# unconditionally would score 100% on every scenario below.
# ===========================================================================
sb="$(sandbox control)"; sb_build "$sb"; sb_git "$sb"
check pass "CONTROL untouched tree reproduces" "$sb" \
  "reproduces byte-for-byte" "each consumed exactly once" "G-4 PASS"

# ===========================================================================
# B-SERIES — the four adversarial bypasses. Each subverts the ASSEMBLER and
# leaves the artifact consistent with the subverted build, so the byte
# comparison alone cannot see it. All four exited 0 under the previous gate.
# ===========================================================================

# B1  A MANIFEST THAT LIES.
# One `part=` is dropped from the parts array, so the manifest omits it AND the
# build omits it. Artifact and manifest agree perfectly; the committed slice is
# simply gone from the migration. Caught only by taking the inventory from git.
sb="$(sandbox b1)"
edit_asm "$sb" -e "/^[[:space:]]*$PL\$/d"
sb_build "$sb"; sb_git "$sb"
check fail "B1 manifest omits a committed slice" "$sb" \
  "COMMITTED IN" "NOT declared by" "$PL"

# B2  SMUGGLED INPUT.
# The assembler concatenates a file that is not a reviewed slice. Under the old
# `cp -R scripts/.` sandbox it came along for the ride and the rebuild matched.
sb="$(sandbox b2)"
printf -- '-- payload that was never a reviewed slice\ncreate table public.smuggled();\n' > "$sb/scripts/payload.sql"
edit_asm "$sb" -e 's#^  done$#  done\n  cat "$repo_root/scripts/payload.sql"#'
sb_build "$sb"; sb_git "$sb"
check fail "B2 assembler concatenates a non-slice file" "$sb" \
  "exited non-zero when rebuilding" "not a reviewed input"

# B3  SYMLINKED SLICE (committed as a symlink).
# The bytes compared are not the bytes committed: review sees a one-line link.
sb="$(sandbox b3)"
printf -- '-- content living outside the reviewed slice tree\n' > "$sb/scripts/outside.sql"
rm -f "$sb/$PARTS_DIR/$P2"
( cd "$sb/$PARTS_DIR" && ln -s "${UP}scripts/outside.sql" "$P2" )
sb_build "$sb"; sb_git "$sb"
check fail "B3 slice committed as a symlink" "$sb" \
  "is a SYMLINK in git (mode 120000)"

# B3b SYMLINK SWAPPED IN AFTER COMMIT.
# git still records a regular file; only the worktree is a link. The index and
# the worktree disagree, which is why the gate checks BOTH.
sb="$(sandbox b3b)"; sb_build "$sb"; sb_git "$sb"
printf -- '-- swapped in after review\n' > "$sb/scripts/outside.sql"
rm -f "$sb/$PARTS_DIR/$P2"
( cd "$sb/$PARTS_DIR" && ln -s "${UP}scripts/outside.sql" "$P2" )
check fail "B3b slice replaced by a symlink after commit" "$sb" \
  "is a SYMLINK on disk even though git records a regular file"

# B4  DECOY parts_dir.
# The manifest and the build both point at a directory that is not the reviewed
# one. The reviewed slices are untouched, and simply stop being used.
sb="$(sandbox b4)"
mkdir -p "$sb/$SLICE_ROOT/decoy_parts"
cp "$sb/$PARTS_DIR"/*.sql "$sb/$SLICE_ROOT/decoy_parts/"
printf -- '\n-- decoy addition nobody reviewed\n' >> "$sb/$SLICE_ROOT/decoy_parts/$P1"
edit_asm "$sb" -e "s#^parts_rel=\"$PARTS_DIR\"\$#parts_rel=\"$SLICE_ROOT/decoy_parts\"#"
sb_build "$sb"; sb_git "$sb"
check fail "B4 decoy parts_dir redirects the build" "$sb" \
  "declares parts_dir=" "the convention derives"

# ===========================================================================
# B-SERIES, deeper: the assembler declares the truth but does not DO it.
# Set equality between the manifest and the git inventory cannot see these;
# only proving each slice's bytes are present in the artifact can.
# ===========================================================================

# B5  A DECLARED SLICE THAT IS NEVER CONCATENATED.
sb="$(sandbox b5)"
edit_asm "$sb" -e "s#^  for p in \"\\\${parts\[@\]}\"; do\$#  for p in \"\${parts[@]}\"; do\n    [ \"\$p\" = \"$PL\" ] \&\& continue#"
sb_build "$sb"; sb_git "$sb"
check fail "B5 declared slice silently not concatenated" "$sb" \
  "do not appear in" "$PL"

# B6  A SLICE CONCATENATED TWICE.
sb="$(sandbox b6)"
edit_asm "$sb" -e "s#^  done\$#  done\n  cat \"\$parts_dir/$P1\"#"
sb_build "$sb"; sb_git "$sb"
check fail "B6 slice concatenated twice" "$sb" \
  "appear 2 times" "$P1"

# B7  THE ASSEMBLER WRITES A SECOND FILE.
sb="$(sandbox b7)"
printf 'printf "select 1;\\n" > "$repo_root/%s/999_stowaway.sql"\n' "$MIG_DIR" >> "$sb/$ASM"
sb_build "$sb"; sb_git "$sb"
check fail "B7 assembler writes a stowaway file" "$sb" \
  "does not hold exactly"

# ===========================================================================
# S-SERIES — the six drift scenarios in the original brief.
# ===========================================================================

# S1  MISSING SLICE.
sb="$(sandbox s1)"; sb_build "$sb"; rm -f "$sb/$PARTS_DIR/$P1"; sb_git "$sb"
check fail "S1 missing slice" "$sb" \
  "declares slice(s) that are NOT committed" "$P1"

# S2  DUPLICATED SLICE (listed twice in the parts array).
sb="$(sandbox s2)"
awk -v p="$P1" '{print} $0 ~ "^[[:space:]]*"p"$" {print}' "$sb/$ASM" > "$sb/$ASM.new"
mv "$sb/$ASM.new" "$sb/$ASM"; chmod +x "$sb/$ASM"
sb_build "$sb"; sb_git "$sb"
check fail "S2 duplicated slice" "$sb" \
  "lists the same slice more than once"

# S3  CHANGED SLICE ORDER (order is load-bearing; artifact not rebuilt).
sb="$(sandbox s3)"; sb_build "$sb"
edit_asm "$sb" \
  -e "s#^\([[:space:]]*\)$P1\$#\1@@SWAP@@#" \
  -e "s#^\([[:space:]]*\)$P2\$#\1$P1#" \
  -e "s#^\([[:space:]]*\)@@SWAP@@\$#\1$P2#"
sb_git "$sb"
check fail "S3 changed slice order" "$sb" \
  "DRIFT:" "SLICE SEQUENCE differs"

# S4  STALE ARTIFACT — a slice edited, the assembler not re-run.
#     This is the exact failure that happened during the 093 train.
sb="$(sandbox s4)"; sb_build "$sb"
printf -- '-- a reviewer added this line to the slice\n' >> "$sb/$PARTS_DIR/$P2"
sb_git "$sb"
check fail "S4 stale artifact (slice edited, not rebuilt)" "$sb" \
  "DRIFT:" "drift is localised to: $P2" "run  ./$ASM"

# S5  HAND-EDIT TO THE ARTIFACT, not reflected in the slices.
sb="$(sandbox s5)"; sb_build "$sb"
printf -- '-- hand-edited straight into the migration\n' >> "$sb/$OUT"
sb_git "$sb"
check fail "S5 hand-edit to the artifact" "$sb" \
  "DRIFT:" "Do NOT hand-edit"

# S6  WHITESPACE DRIFT — one trailing space, invisible in review.
sb="$(sandbox s6)"; sb_build "$sb"
awk 'NR==30 {print $0 " "; next} {print}' "$sb/$OUT" > "$sb/$OUT.new"
mv "$sb/$OUT.new" "$sb/$OUT"
sb_git "$sb"
check fail "S6 whitespace drift (one trailing space)" "$sb" \
  "DRIFT:" "drift is localised to: __preamble__"

# ===========================================================================
# A-SERIES — anti-vacuity. The gate must fail loudly, never skip.
# ===========================================================================

sb="$(sandbox a1)"; sb_build "$sb"; rm -rf "$sb/$PARTS_DIR"; sb_git "$sb"
check fail "A1 slice directory deleted" "$sb" \
  "committed slice(s) found under"

sb="$(sandbox a2)"; sb_build "$sb"; rm -f "$sb"/scripts/assemble_*.sh; sb_git "$sb"
check fail "A2 assembler deleted, artifact kept" "$sb" \
  "no scripts/assemble_*.sh found"

sb="$(sandbox a3)"; sb_build "$sb"
grep -v '^-- @generated-by: ' "$sb/$OUT" > "$sb/$OUT.new"; mv "$sb/$OUT.new" "$sb/$OUT"
sb_git "$sb"
check fail "A3 banner stripped from the artifact" "$sb" \
  "banner"

sb="$(sandbox a4)"; sb_build "$sb"
cp "$sb/$PARTS_DIR/$P1" "$sb/$PARTS_DIR/99_never_referenced.sql"
sb_git "$sb"
check fail "A4 slice committed but never assembled in" "$sb" \
  "COMMITTED IN" "99_never_referenced.sql"

sb="$(sandbox a5)"; sb_build "$sb"; rm -f "$sb/$OUT"; sb_git "$sb"
check fail "A5 artifact deleted (assembler and slices kept)" "$sb" \
  "no migration in $MIG_DIR carries"

# An untracked slice is not a reviewed input, and must not become one.
# The assembler edit is COMMITTED and only the slice file is left untracked, so
# the scenario still isolates "untracked input" under --require-committed mode
# (where an uncommitted assembler would otherwise bail first).
sb="$(sandbox a6)"; sb_build "$sb"
edit_asm "$sb" -e "s#^\([[:space:]]*\)$P1\$#\1$P1\n\198_untracked.sql#"
sb_git "$sb"
cp "$sb/$PARTS_DIR/$P1" "$sb/$PARTS_DIR/98_untracked.sql"
check fail "A6 untracked slice declared by the assembler" "$sb" \
  "NOT committed in" "98_untracked.sql"

# The gate must never validate one tree using another tree's git index.
sb="$(sandbox a7)"; sb_build "$sb"   # deliberately NOT a git repository
check fail "A7 sandbox is not a git repository" "$sb" \
  "not inside a git working tree"

# ===========================================================================
# D-SERIES — determinism.
# ===========================================================================

sb="$(sandbox d1)"
edit_asm "$sb" -e "s#^export LC_ALL=C\$#export LC_ALL=C\nbuilt_at=\$(date +%s)#"
sb_build "$sb"; sb_git "$sb"
check fail "D1 timestamp introduced into the assembler" "$sb" \
  "whose output can vary between runs or machines" "timestamp"

sb="$(sandbox d2)"
edit_asm "$sb" \
  -e 's#^export LC_ALL=C$##' \
  -e "s#^  cat <<'BANNER'\$#  printf -- '-- env: %s\\\\n' \"\${LC_ALL:-none}\"\n  cat <<'BANNER'#"
sb_build "$sb"; sb_git "$sb"
check fail "D2 environment leaks into the output" "$sb" \
  "NON-DETERMINISTIC"

echo
echo "scenarios: $n   behaved as specified: $passes   misbehaved: $failures"
if [ "$failures" -ne 0 ]; then
  echo "::error::the G-4 gate did not behave as specified in $failures scenario(s) — the drift guard cannot be trusted."
  exit 1
fi
echo "G-4 SELF-TEST PASS: the gate passes a clean tree and rejects every simulated drift and every assembler-level bypass."
exit 0
