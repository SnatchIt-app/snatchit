#!/usr/bin/env bash
# =============================================================================
# ASSEMBLED-MIGRATION INTEGRITY GATE  (G-4)
#
# THE INVARIANT
#   For every migration generated from reviewed slices:
#       committed migration  ==  committed_assembler(committed slices)
#   byte for byte, over EXACTLY the set of slices committed to git — no more,
#   no fewer. The SLICES ARE CANONICAL; the migration is a build artifact.
#
# WHY IT EXISTS
#   During the 093 train an agent ran the assembler mid-review and the committed
#   migration silently drifted from its slices. Nothing in CI proved
#   SLICES == ASSEMBLED.
#
# ---------------------------------------------------------------------------
# THE AUTHORITY RULE — read this before changing anything below.
#
#   THE GATE NEVER TAKES THE ASSEMBLER'S WORD FOR WHAT TO CHECK.
#
# An earlier revision read `--manifest` and treated it as the source of truth
# for which slices existed and where they lived. That is the same class of error
# as trusting a caller-supplied `acct_` id: a guard that asks the thing it is
# guarding what to check is not a guard. Four working bypasses came out of it,
# all exiting 0 while the slices and the artifact genuinely disagreed:
#
#   1. A MANIFEST THAT LIES. Omit one `part=` line and a whole reviewed slice
#      drops out of the comparison while the gate prints "byte-for-byte".
#   2. SMUGGLED INPUTS. The sandbox was seeded with `cp -R scripts/.`, so the
#      assembler could `cat` arbitrary SQL that was never a reviewed slice.
#   3. SYMLINKED SLICES. The bytes compared were not the bytes committed.
#   4. A DECOY parts_dir. The manifest pointed the build at a directory that
#      was not the reviewed one.
#
# So every fact the gate acts on is now derived independently:
#
#   * WHICH FILES EXIST  -> `git ls-files` (the index), never the manifest.
#   * WHAT KIND OF FILE  -> the git mode (100644/100755 only) AND an on-disk
#                           regular-file/not-a-symlink check. Both, because the
#                           index and the worktree can disagree.
#   * WHERE THEY LIVE    -> DERIVED from the assembler's own filename by
#                           convention, never declared:
#                             scripts/assemble_<TAG>.sh
#                               -> <SLICE_ROOT>/<TAG>_parts/*.sql   (inputs)
#                               -> supabase/migrations/<TAG>_*.sql  (output)
#   * WHAT THE BUILD SAW -> a HERMETIC sandbox holding the assembler and the
#                           git-inventoried slices and NOTHING ELSE, checked
#                           for stowaways after the run.
#   * THAT SQL SURVIVED  -> every slice's committed bytes must appear in the
#                           artifact exactly once. A manifest can list a slice
#                           the assembler never concatenates; this catches it.
#
# `--manifest` is still required, but only as a CROSS-CHECK: the gate compares
# it against the derived facts and FAILS on any disagreement. It is evidence,
# not authority.
#
# UNION PROOF. Across all assemblers: every committed slice under
# <SLICE_ROOT>/*_parts/ is consumed exactly once, and every consumed input is a
# committed slice. Neither direction may be empty.
#
# GENERIC BY CONSTRUCTION. Nothing here names 093. Adding an assembled 094
# means: add scripts/assemble_094.sh implementing --manifest and emitting the
# `-- @generated-by:` banner, put its slices in <SLICE_ROOT>/094_parts/, and
# name the migration 094_*.sql. No edit to this file or to the workflow.
#
# Usage:  scripts/ci/assembled_migration_integrity.sh [--require-committed]
#           --require-committed  every input's worktree bytes must equal its
#                                HEAD blob. Implied when $CI is set. Without it
#                                (local pre-commit use) a difference is a loud
#                                notice rather than an error.
# Exit:   0 = every assembled migration reproduces exactly; 1 = drift.
# Docs:   docs/phase2/_impl/G4_assembler_integrity.md
# =============================================================================
set -uo pipefail
export LC_ALL=C

# Repo root comes from THIS FILE's location, never from `git rev-parse`: the
# self-test runs a copy of this script inside a sandbox repo, and a bare
# `rev-parse` would walk up out of it and validate the real repo instead.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

MIGRATIONS_DIR="${G4_MIGRATIONS_DIR:-supabase/migrations}"
SLICE_ROOT="${G4_SLICE_ROOT:-docs/phase2/_impl}"
BANNER_KEY="-- @generated-by: "
SLICE_MARK="-- ## SLICE: "
MIN_ASSEMBLERS="${G4_MIN_ASSEMBLERS:-1}"
MIN_GENERATED="${G4_MIN_GENERATED:-1}"
MIN_PARTS="${G4_MIN_PARTS:-2}"
DET_ALLOW='# det-allow:'

REQUIRE_COMMITTED=0
[ -n "${CI:-}" ] && REQUIRE_COMMITTED=1
for arg in "$@"; do
  case "$arg" in
    --require-committed) REQUIRE_COMMITTED=1 ;;
    *) echo "::error::unknown argument: $arg"; exit 2 ;;
  esac
done

fail=0
err()  { echo "::error::$*"; fail=1; }
note() { echo "$*"; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/g4gate.XXXXXX")" || { echo "::error::cannot create temp dir"; exit 1; }
trap 'rm -rf "$TMPROOT"' EXIT

note "== G-4 assembled-migration integrity =="
note "repo root:  $repo_root"

# --- 0. The git authority must BE this repository ---------------------------
# Without this, running the gate in a directory that is not a git repo would
# silently inherit the index of whatever repo lies above it — every "committed"
# fact below would then describe a different tree.
if ! command -v git >/dev/null 2>&1; then
  err "git is not available. Every fact this gate acts on comes from the git index; it cannot run without it."
  exit 1
fi
top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$top" ]; then
  err "$repo_root is not inside a git working tree. The slice inventory is taken from the git index and cannot be established here."
  exit 1
fi
# Resolved paths: macOS /tmp is a symlink to /private/tmp.
top_r="$(cd "$top" && pwd -P)"; root_r="$(pwd -P)"
if [ "$top_r" != "$root_r" ]; then
  err "the enclosing git repository is '$top_r' but this gate lives in '$root_r'. Refusing to validate one tree using another tree's index."
  exit 1
fi
if [ "$REQUIRE_COMMITTED" -eq 1 ]; then
  note "mode:       require-committed (every input must equal its HEAD blob)"
else
  note "mode:       local (worktree content may differ from HEAD; differences are reported)"
fi
note "slice root: $SLICE_ROOT"
if ! command -v python3 >/dev/null 2>&1; then
  err "python3 is not available. It is needed to prove each slice's bytes actually appear in the artifact; a skipped check is a hole."
  exit 1
fi

# --- helpers ----------------------------------------------------------------

# A repo-relative path safe to use: not absolute, no '..', conservative charset.
path_ok() {
  case "$1" in
    ""|/*) return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  case "/$1/" in */../*) return 1 ;; esac
  return 0
}

# A bare filename safe to use as a slice name.
name_ok() {
  case "$1" in
    ""|.|..|-*|*/*) return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

git_mode() { git ls-files -s -- "$1" 2>/dev/null | head -1 | awk '{print $1}'; }

# require_regular <relpath> <label> -> 0 if tracked, regular, in-tree
require_regular() {
  local p="$1" label="$2" mode dir_r
  if ! path_ok "$p"; then
    err "$label path '$p' is absolute, escapes the tree with '..', or uses characters outside [A-Za-z0-9._/-]. Refusing to read it."
    return 1
  fi
  mode="$(git_mode "$p")"
  if [ -z "$mode" ]; then
    err "$label '$p' is NOT TRACKED IN GIT. Every build input must be committed and reviewable; an untracked file has been through no review. Run: git add $p"
    return 1
  fi
  case "$mode" in
    100644|100755) ;;
    120000) err "$label '$p' is a SYMLINK in git (mode 120000). The bytes compared would not be the bytes committed here, and the link target is outside review. Replace it with a regular file."; return 1 ;;
    160000) err "$label '$p' is a gitlink/submodule (mode 160000). Its content is not in this repository."; return 1 ;;
    040000) err "$label '$p' is a directory, not a file."; return 1 ;;
    *)      err "$label '$p' has git mode $mode; only regular files (100644/100755) may be build inputs."; return 1 ;;
  esac
  if [ -L "$p" ]; then
    err "$label '$p' is a SYMLINK on disk even though git records a regular file. The index and the worktree disagree; refusing to read it."
    return 1
  fi
  if [ ! -f "$p" ]; then
    err "$label '$p' is tracked but is not a regular file on disk."
    return 1
  fi
  # Belt and braces against a symlinked ANCESTOR directory.
  dir_r="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || { err "$label '$p': its directory cannot be resolved."; return 1; }
  case "$dir_r/" in
    "$root_r"/*) ;;
    *) err "$label '$p' resolves to '$dir_r', outside the repository root. A symlinked parent directory would move the build off the reviewed tree."; return 1 ;;
  esac
  if [ "$REQUIRE_COMMITTED" -eq 1 ]; then
    if ! git diff --quiet HEAD -- "$p" 2>/dev/null; then
      err "$label '$p' differs from its committed content at HEAD. In --require-committed mode the build inputs must be exactly what was reviewed."
      return 1
    fi
  elif ! git diff --quiet HEAD -- "$p" 2>/dev/null; then
    note "  NOTE: $p differs from HEAD (uncommitted local edit). CI validates the committed bytes."
  fi
  return 0
}

# occurrences <haystack> <needle> -> count of exact byte-sequence occurrences
occurrences() {
  python3 - "$1" "$2" <<'PY'
import sys
h = open(sys.argv[1], 'rb').read()
n = open(sys.argv[2], 'rb').read()
c = 0; i = h.find(n)
while i != -1:
    c += 1; i = h.find(n, i + 1)
print(c)
PY
}

# split_sections <file> <outdir>; prints slice names in order (message polish only)
split_sections() {
  local f="$1" d="$2"
  mkdir -p "$d"
  awk -v d="$d" -v mark="$SLICE_MARK" '
    BEGIN { idx = 1; out = sprintf("%s/%03d", d, idx); printf "" > out; print "__preamble__" }
    index($0, mark) == 1 {
      idx++; out = sprintf("%s/%03d", d, idx); printf "" > out
      print substr($0, length(mark) + 1)
      next
    }
    { print > out }
  ' "$f"
}

# --- 1. Discover assemblers -------------------------------------------------
# An explicit, sorted glob. `find` is deliberately avoided: its traversal order
# is filesystem-dependent, and this gate lectures assemblers about determinism.
assemblers=""
for a in scripts/assemble_*.sh; do
  [ -e "$a" ] || continue
  assemblers="$assemblers$a"$'\n'
done
assemblers="$(printf '%s' "$assemblers" | sed '/^$/d' | sort)"
n_asm="$(printf '%s' "$assemblers" | grep -c . || true)"
note ""
note "assemblers discovered: ${n_asm:-0}"
printf '%s\n' "$assemblers" | sed '/^$/d;s/^/  - /'
if [ "${n_asm:-0}" -lt "$MIN_ASSEMBLERS" ]; then
  err "no scripts/assemble_*.sh found (floor $MIN_ASSEMBLERS). Either an assembler was deleted, or this gate is now checking nothing — both are failures, never a skip."
  exit 1
fi

# --- 2. Discover generated migrations (by banner) ---------------------------
if [ ! -d "$MIGRATIONS_DIR" ]; then
  err "$MIGRATIONS_DIR does not exist."
  exit 1
fi
generated="$(grep -l "^${BANNER_KEY}" "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort || true)"
n_gen="$(printf '%s' "$generated" | grep -c . || true)"
note "migrations carrying a generated-by banner: ${n_gen:-0}"
printf '%s\n' "$generated" | sed '/^$/d;s/^/  - /'
if [ "${n_gen:-0}" -lt "$MIN_GENERATED" ]; then
  err "no migration in $MIGRATIONS_DIR carries a '${BANNER_KEY}' banner (floor $MIN_GENERATED), yet ${n_asm} assembler(s) exist. Either the banner was stripped from a generated migration or the artifact was deleted."
  exit 1
fi

# --- 3. The committed slice universe ----------------------------------------
# Every tracked *.sql directly under <SLICE_ROOT>/<TAG>_parts/. This is the set
# that MUST be fully consumed, and it is what makes a decoy parts_dir fatal:
# redirecting the build elsewhere leaves the real slices unconsumed here.
universe="$(git ls-files -- "$SLICE_ROOT" 2>/dev/null \
            | grep -E "^${SLICE_ROOT}/[A-Za-z0-9]+_parts/[^/]+\.sql$" | sort || true)"
n_univ="$(printf '%s' "$universe" | grep -c . || true)"
note "committed slices under ${SLICE_ROOT}/*_parts/: ${n_univ:-0}"
if [ "${n_univ:-0}" -lt "$MIN_PARTS" ]; then
  err "only ${n_univ:-0} committed slice(s) found under ${SLICE_ROOT}/*_parts/ (floor $MIN_PARTS). The reviewed slice tree is missing; this gate would be comparing nothing."
  exit 1
fi
: > "$TMPROOT/consumed"
: > "$TMPROOT/pending"

claimed_outs=""

# --- 4. Per-assembler checks ------------------------------------------------
while IFS= read -r asm; do
  [ -n "$asm" ] || continue
  note ""
  note "---- $asm ----"
  # Anything still listed in $TMPROOT/pending at the end bailed before it could
  # contribute to the union sets below. Without this, one skipped assembler
  # makes sections 5 and 6 blame the slices ("no assembler consumes them") for a
  # failure that is really about the assembler.
  printf '%s\n' "$asm" >> "$TMPROOT/pending"

  # 4a. The assembler itself must be a committed regular file --------------
  require_regular "$asm" "assembler" || continue
  if [ ! -x "$asm" ]; then
    err "$asm is not executable. CI runs it directly."
    continue
  fi
  if ! bash -n "$asm" 2>"$TMPROOT/syn.txt"; then
    err "$asm is not valid bash: $(head -3 "$TMPROOT/syn.txt" | tr '\n' ' ')"
    continue
  fi

  # 4b. DERIVE the paths from the assembler's name. Nothing declared. ------
  tag="${asm#scripts/assemble_}"; tag="${tag%.sh}"
  if ! printf '%s' "$tag" | grep -qE '^[A-Za-z0-9]+$'; then
    err "$asm has an unusable tag '$tag'. An assembler must be named scripts/assemble_<TAG>.sh with TAG in [A-Za-z0-9], because TAG is what the slice directory and the migration are derived from."
    continue
  fi
  d_dir="$SLICE_ROOT/${tag}_parts"
  d_outs="$(git ls-files -- "$MIGRATIONS_DIR" 2>/dev/null | grep -E "^${MIGRATIONS_DIR}/${tag}_[A-Za-z0-9_]+\.sql$" || true)"
  n_outs="$(printf '%s' "$d_outs" | grep -c . || true)"
  if [ "${n_outs:-0}" -ne 1 ]; then
    err "expected exactly ONE committed migration matching ${MIGRATIONS_DIR}/${tag}_*.sql for $asm; found ${n_outs:-0}: $(printf '%s' "$d_outs" | tr '\n' ' ')"
    continue
  fi
  d_out="$d_outs"
  note "derived parts_dir: $d_dir"
  note "derived out:       $d_out"

  if [ ! -d "$d_dir" ] || [ -L "$d_dir" ]; then
    err "$d_dir is not a real directory (missing, or a symlink). The reviewed slices for $d_out are not where the convention says they are."
    continue
  fi
  require_regular "$d_out" "artifact" || continue
  claimed_outs="$claimed_outs$d_out"$'\n'

  # 4c. Slice inventory FROM GIT, not from the manifest --------------------
  git_slices=""
  bad_inv=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line#*	}"
    b="${p##*/}"
    if ! name_ok "$b"; then
      err "committed file '$p' has a name outside [A-Za-z0-9._-]; refusing to treat it as a slice."
      bad_inv=1; continue
    fi
    case "$b" in
      *.sql) ;;
      *) err "non-SQL file '$p' is committed in the slice directory. The slice tree must contain only reviewed .sql slices, so that 'every committed slice is consumed' is a statement about everything in it."
         bad_inv=1; continue ;;
    esac
    require_regular "$p" "slice" || { bad_inv=1; continue; }
    if [ ! -s "$p" ]; then
      err "slice $p is empty. An empty slice assembles cleanly and reviews as nothing."
      bad_inv=1; continue
    fi
    # A slice with no trailing newline fuses its last statement into the next
    # slice's header comment — silently commenting that statement out.
    if [ -n "$(tail -c 1 "$p")" ]; then
      err "slice $p does not end with a newline: concatenation would fuse its final line into the next slice's header comment."
      bad_inv=1; continue
    fi
    git_slices="$git_slices$b"$'\n'
  done <<EOF
$(git ls-files -s -- "$d_dir" 2>/dev/null)
EOF
  git_slices="$(printf '%s' "$git_slices" | sed '/^$/d' | sort)"
  n_slices="$(printf '%s' "$git_slices" | grep -c . || true)"
  note "committed slices:  ${n_slices:-0}"
  if [ "$bad_inv" -ne 0 ]; then
    err "the committed slice inventory for $asm is not usable; not attempting a rebuild."
    continue
  fi
  if [ "${n_slices:-0}" -lt "$MIN_PARTS" ]; then
    err "$d_dir holds ${n_slices:-0} committed slice(s); floor is $MIN_PARTS. An assembler over one or zero slices is a hand-edited file wearing a build system."
    continue
  fi

  # 4d. The manifest is CROSS-CHECKED against the derived facts ------------
  # It is evidence, never authority. Any disagreement is a failure in its own
  # right, not something to reconcile: an assembler that misdescribes its own
  # inputs is either broken or hostile, and both must stop the build.
  man="$TMPROOT/manifest.$$"
  if ! "./$asm" --manifest > "$man" 2>"$TMPROOT/manerr.txt"; then
    err "$asm --manifest failed: $(head -3 "$TMPROOT/manerr.txt" | tr '\n' ' '). Every assembler must implement --manifest (keys: assembler, out, parts_dir, part…)."
    continue
  fi
  m_asm="$(grep '^assembler=' "$man" | head -1 | cut -d= -f2-)"
  m_out="$(grep '^out=' "$man" | head -1 | cut -d= -f2-)"
  m_dir="$(grep '^parts_dir=' "$man" | head -1 | cut -d= -f2-)"
  m_parts="$(grep '^part=' "$man" | cut -d= -f2- | sed '/^$/d')"
  n_mparts="$(printf '%s' "$m_parts" | grep -c . || true)"

  mism=0
  [ "$m_asm" = "$asm"   ] || { err "$asm --manifest reports assembler='$m_asm'; it must name its own path."; mism=1; }
  [ "$m_dir" = "$d_dir" ] || { err "$asm --manifest declares parts_dir='$m_dir' but the convention derives '$d_dir' from the assembler's name. A declared parts directory is exactly how a build gets redirected away from the reviewed slices; the derived one wins and the disagreement fails."; mism=1; }
  [ "$m_out" = "$d_out" ] || { err "$asm --manifest declares out='$m_out' but the committed migration for tag '$tag' is '$d_out'."; mism=1; }
  dupes="$(printf '%s\n' "$m_parts" | sort | uniq -d)"
  [ -z "$dupes" ] || { err "$asm lists the same slice more than once — the migration would contain it twice: $(printf '%s' "$dupes" | tr '\n' ' ')"; mism=1; }
  bad_names=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    name_ok "$p" || bad_names="$bad_names $p"
  done <<EOF
$m_parts
EOF
  [ -z "$bad_names" ] || { err "$asm declares part name(s) that are not plain in-directory filenames:$bad_names"; mism=1; }

  # THE UNION, per assembler. Bypass 1: a slice committed and reviewed but
  # quietly dropped from the manifest.
  declared="$(printf '%s\n' "$m_parts" | sort -u)"
  omitted="$(comm -23 <(printf '%s\n' "$git_slices") <(printf '%s\n' "$declared"))"
  extra="$(comm -13 <(printf '%s\n' "$git_slices") <(printf '%s\n' "$declared"))"
  if [ -n "$omitted" ]; then
    err "slice(s) COMMITTED IN $d_dir but NOT declared by $asm: $(printf '%s' "$omitted" | tr '\n' ' ')"
    err "Reviewed SQL the build never sees is the quietest possible drift. Add it to the parts list in $asm and re-run the assembler, or delete the slice."
    mism=1
  fi
  if [ -n "$extra" ]; then
    err "$asm declares slice(s) that are NOT committed in $d_dir: $(printf '%s' "$extra" | tr '\n' ' ')"
    mism=1
  fi
  if [ "${n_mparts:-0}" -ne "${n_slices:-0}" ]; then
    err "$asm declares ${n_mparts:-0} part(s) but ${n_slices:-0} slice(s) are committed in $d_dir."
    mism=1
  fi
  [ "$mism" -eq 0 ] || { err "manifest/tree disagreement for $asm — not attempting a rebuild."; continue; }
  note "OK: manifest agrees with the committed tree (${n_slices} slices, derived paths)."

  # Record consumption for the cross-assembler union proof.
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    echo "$d_dir/$b" >> "$TMPROOT/consumed"
  done <<EOF
$git_slices
EOF
  grep -vxF "$asm" "$TMPROOT/pending" > "$TMPROOT/pending.n" 2>/dev/null || true
  mv "$TMPROOT/pending.n" "$TMPROOT/pending" 2>/dev/null || : > "$TMPROOT/pending"

  # 4e. Static non-determinism scan ---------------------------------------
  code="$TMPROOT/code.$$"
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*--/d' "$asm" | grep -v -F "$DET_ALLOW" > "$code"
  bad_det=""
  scan() {
    local hit; hit="$(grep -nE "$2" "$code" || true)"
    [ -n "$hit" ] && bad_det="$bad_det
  [$1] $(printf '%s' "$hit" | head -3 | tr '\n' ' ')"
    return 0
  }
  scan "timestamp"     '(\$\(date|`date|[^a-zA-Z_]date[[:space:]]+\+|EPOCHSECONDS|SECONDS)'
  scan "find-order"    '(^|[^a-zA-Z_])find[[:space:]]'
  scan "ls-order"      '(^|[^a-zA-Z_])ls[[:space:]]+[^|]*\$'
  scan "unstable-glob" '(cat|for[[:space:]]+[a-zA-Z_]+[[:space:]]+in)[^#]*\*'
  scan "randomness"    '(\$RANDOM|shuf|uuidgen|openssl[[:space:]]+rand)'
  scan "environment"   '(hostname|whoami|\$USER|\$HOSTNAME|uname)'
  scan "vcs-state"     'git[[:space:]]+(rev-parse|describe|log|status|show)'
  if [ -n "$bad_det" ]; then
    err "$asm contains construct(s) whose output can vary between runs or machines:$bad_det"
    err "An assembler's output must be a pure function of its slices. Remove the construct, or annotate the line with '$DET_ALLOW <reason>' if it provably cannot reach the output."
  else
    note "OK: no non-deterministic construct in executable lines."
  fi
  if ! grep -qE '^[[:space:]]*export[[:space:]]+LC_ALL=C[[:space:]]*$' "$asm"; then
    err "$asm does not pin the locale. Add 'export LC_ALL=C' so no present or future sort/collation can make the output environment-dependent."
  else
    note "OK: locale pinned (export LC_ALL=C)."
  fi

  # 4f. HERMETIC rebuild ---------------------------------------------------
  # The sandbox holds the assembler and the git-inventoried slices and NOTHING
  # ELSE. Bypass 2: the old sandbox was seeded with `cp -R scripts/.`, so an
  # assembler could `cat` any file that happened to live in scripts/ and pass
  # it off as reviewed SQL. Here, anything it reaches for outside its slices
  # simply is not there and the build fails loudly. The migrations directory
  # starts EMPTY, so the committed artifact cannot influence the rebuild and
  # whatever appears is unambiguously this assembler's output.
  build() {
    local sb="$1" b
    mkdir -p "$sb/$(dirname "$asm")" "$sb/$d_dir" "$sb/$MIGRATIONS_DIR" || return 1
    cp "$asm" "$sb/$asm" || return 1
    chmod +x "$sb/$asm"
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      cp "$d_dir/$b" "$sb/$d_dir/$b" || return 1
    done <<EOF
$git_slices
EOF
    ( cd / && "$sb/$asm" ) >"$sb/.stdout" 2>"$sb/.stderr"
  }
  sb1="$TMPROOT/sb1.$$"
  if ! build "$sb1"; then
    err "$asm exited non-zero when rebuilding $d_out from the committed slices alone: $(head -3 "$sb1/.stderr" 2>/dev/null | tr '\n' ' ')"
    err "If it is reaching for a file that is not one of its committed slices, that file is not a reviewed input and must not be in the build."
    continue
  fi

  # Stowaway check: the sandbox must hold exactly what we put there plus the
  # single artifact. An assembler that writes anything else is out of contract.
  ( cd "$sb1" && find . -type f ! -name .stdout ! -name .stderr | sed 's#^\./##' | sort ) > "$TMPROOT/after.$$"
  {
    echo "$asm"
    while IFS= read -r b; do [ -n "$b" ] && echo "$d_dir/$b"; done <<EOF
$git_slices
EOF
    echo "$d_out"
  } | sort > "$TMPROOT/expect.$$"
  if ! cmp -s "$TMPROOT/after.$$" "$TMPROOT/expect.$$"; then
    err "the hermetic sandbox does not hold exactly (assembler + committed slices + one artifact) after running $asm:"
    diff -u "$TMPROOT/expect.$$" "$TMPROOT/after.$$" | sed 's/^/  /' | head -20
    continue
  fi
  rebuilt="$sb1/$d_out"
  note "OK: hermetic rebuild produced exactly $d_out and nothing else."

  if ! grep -q "^${BANNER_KEY}${asm}\$" "$d_out"; then
    err "$d_out does not carry the banner line '${BANNER_KEY}${asm}'. Generated migrations must announce themselves so this gate can find them without a hardcoded list."
  fi

  # 4g. Byte comparison ----------------------------------------------------
  if cmp -s "$rebuilt" "$d_out"; then
    note "OK: $d_out reproduces byte-for-byte from ${n_slices} committed slice(s) in $d_dir."
    note "    bytes=$(wc -c < "$d_out" | tr -d ' ')  lines=$(wc -l < "$d_out" | tr -d ' ')"
  else
    err "DRIFT: $d_out is NOT the output of ./$asm over the committed slices in $d_dir."
    err "FIX: run  ./$asm  and commit the regenerated $d_out (together with any slice change)."
    err "Do NOT hand-edit $d_out to make this pass — the slices in $d_dir are canonical and the next assembler run reverts any edit made here."
    if grep -q "^${SLICE_MARK}" "$d_out" && grep -q "^${SLICE_MARK}" "$rebuilt"; then
      split_sections "$d_out"   "$TMPROOT/secA.$$" > "$TMPROOT/nA.$$"
      split_sections "$rebuilt" "$TMPROOT/secB.$$" > "$TMPROOT/nB.$$"
      if ! cmp -s "$TMPROOT/nA.$$" "$TMPROOT/nB.$$"; then
        err "the artifact's SLICE SEQUENCE differs from what the assembler now produces (a slice was added, removed, or reordered):"
        echo "  committed order: $(tr '\n' ' ' < "$TMPROOT/nA.$$")"
        echo "  rebuilt   order: $(tr '\n' ' ' < "$TMPROOT/nB.$$")"
      else
        drifted=""; i=0
        while IFS= read -r sname; do
          i=$((i + 1))
          cmp -s "$TMPROOT/secA.$$/$(printf '%03d' "$i")" "$TMPROOT/secB.$$/$(printf '%03d' "$i")" || drifted="$drifted $sname"
        done < "$TMPROOT/nA.$$"
        if [ -n "$drifted" ]; then
          err "drift is localised to:$drifted"
        else
          err "the slice bodies all match — the drift is in the assembler's own header/banner output."
        fi
      fi
    fi
    echo "--- committed (a) vs rebuilt-from-slices (b), first 40 diff lines ---"
    diff -u "$d_out" "$rebuilt" 2>/dev/null | head -40 | sed 's/^/  /'
    echo "  (a=committed $d_out   b=rebuilt from $d_dir)"
    echo "--- byte/line counts ---"
    echo "  committed: $(wc -c < "$d_out" | tr -d ' ') bytes, $(wc -l < "$d_out" | tr -d ' ') lines, cksum $(cksum < "$d_out" | awk '{print $1}')"
    echo "  rebuilt:   $(wc -c < "$rebuilt" | tr -d ' ') bytes, $(wc -l < "$rebuilt" | tr -d ' ') lines, cksum $(cksum < "$rebuilt" | awk '{print $1}')"
  fi

  # 4h. Consumption proof --------------------------------------------------
  # A manifest can list a slice the assembler never concatenates. Set equality
  # cannot see that; this can. Each slice's committed bytes must occur in the
  # artifact exactly once.
  missing_body=""
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    c="$(occurrences "$d_out" "$d_dir/$b")"
    case "$c" in
      1) ;;
      0) missing_body="$missing_body
  $b: its committed bytes do not appear in $d_out at all" ;;
      *) missing_body="$missing_body
  $b: its committed bytes appear $c times in $d_out (expected exactly 1)" ;;
    esac
  done <<EOF
$git_slices
EOF
  if [ -n "$missing_body" ]; then
    err "slice content is declared but not correctly present in the artifact:$missing_body"
    err "The manifest can list a slice the assembler never concatenates. Rebuild with ./$asm and check the assembler's loop."
  else
    note "OK: every committed slice's bytes appear in $d_out exactly once."
  fi

  # 4i. Reproducibility under a perturbed environment ---------------------
  sb2="$TMPROOT/sb2.$$"
  if ( umask 077; LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LC_COLLATE=en_US.UTF-8 TZ=Pacific/Kiritimati build "$sb2" ); then
    if cmp -s "$sb1/$d_out" "$sb2/$d_out"; then
      note "OK: reproducible across locale/timezone/umask/cwd perturbation."
    else
      err "$asm is NON-DETERMINISTIC: two runs over identical slices differed only in environment (locale, TZ, umask, cwd)."
      diff -u "$sb1/$d_out" "$sb2/$d_out" 2>/dev/null | head -20 | sed 's/^/  /'
    fi
  else
    err "$asm failed under a perturbed environment (locale/TZ/umask/cwd): $(head -3 "$sb2/.stderr" 2>/dev/null | tr '\n' ' ')"
  fi
done <<EOF
$assemblers
EOF

# --- 5. Union proof across all assemblers -----------------------------------
note ""
note "== union proof =="
skipped="$(sed '/^$/d' "$TMPROOT/pending" 2>/dev/null | tr '\n' ' ')"
if [ -n "$skipped" ]; then
  err "assembler(s) failed their own checks above and were NOT evaluated: $skipped"
  err "The union and banner findings below are a CONSEQUENCE of that, not independent problems. Fix the assembler error(s) first and re-run."
fi
consumed_sorted="$(sort -u "$TMPROOT/consumed" 2>/dev/null || true)"
n_cons="$(printf '%s' "$consumed_sorted" | grep -c . || true)"
n_cons_raw="$(grep -c . "$TMPROOT/consumed" 2>/dev/null || echo 0)"
if [ "${n_cons_raw:-0}" -ne "${n_cons:-0}" ]; then
  err "a committed slice is consumed by more than one assembler; ownership of a reviewed slice must be unambiguous."
fi
unconsumed="$(comm -23 <(printf '%s\n' "$universe") <(printf '%s\n' "$consumed_sorted"))"
foreign="$(comm -13 <(printf '%s\n' "$universe") <(printf '%s\n' "$consumed_sorted"))"
if [ -n "$unconsumed" ]; then
  err "committed slice(s) that NO assembler consumes: $(printf '%s' "$unconsumed" | tr '\n' ' ')"
  err "Either an assembler was redirected away from them, or they were reviewed and then abandoned. Both mean reviewed SQL is not reaching a migration."
fi
if [ -n "$foreign" ]; then
  err "assembler input(s) from outside the reviewed slice tree ${SLICE_ROOT}/*_parts/: $(printf '%s' "$foreign" | tr '\n' ' ')"
fi
if [ -z "$unconsumed" ] && [ -z "$foreign" ]; then
  note "OK: ${n_cons} committed slice(s), each consumed exactly once; no build input from outside the reviewed tree."
fi

# --- 6. Reconcile banners against assemblers --------------------------------
note ""
note "== banner reconciliation =="
claimed_sorted="$(printf '%s' "$claimed_outs" | sed '/^$/d' | sort -u)"
orphans="$(comm -23 <(printf '%s\n' "$generated" | sed '/^$/d') <(printf '%s\n' "$claimed_sorted"))"
if [ -n "$orphans" ]; then
  err "migration(s) carry a '${BANNER_KEY}' banner but no discovered assembler claims them: $(printf '%s' "$orphans" | tr '\n' ' ')"
  err "Restore the assembler named in the banner, or the file is an unreproducible artifact with no reviewable source."
else
  note "OK: every generated migration is claimed by a discovered assembler."
fi

note ""
if [ "$fail" -eq 0 ]; then
  note "G-4 PASS: every assembled migration is exactly its committed assembler's output over exactly the committed slices."
else
  note "G-4 FAIL."
fi
exit "$fail"
