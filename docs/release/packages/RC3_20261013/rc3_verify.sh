#!/bin/bash
# rc3_verify.sh: RC3 candidate identity checks (read-only; git only). The RC3 counterpart of RC_20261012/rc_verify.sh.
#
# usage: rc3_verify.sh <rc3-sha> <a-fix-tip> <c-tip> <merge-sha>...
#   Per merge M: branch-file mismatches, unexpected changes and new blobs must all be 0 (as in rc_verify.sh).
#   Fixed surfaces: each must equal its owner's tip, and each "0" is printed with a positive control that must be
#   non-zero, so an empty diff cannot pass silently:
#     supabase/ .github/ admin/  == A's fix tip            (control: RC2 e2b9498b)
#     app/ src/ tests/           == C's tip                (control: RC2 e2b9498b)
#     web/                       == live web 0b389584      (control: 5450b348, as in rc_verify.sh)
#   Native-build inputs vs RC2 are counted (expected 0: RC3 changes no dependency, config or native file).
# Exit 1 on any failure.
set -u
C="$1"; A="$2"; CT="$3"; shift 3
RC2=e2b9498b
fail=0
for M in "$@"; do
  P1=$(git rev-parse "$M^1"); P2=$(git rev-parse "$M^2")
  B=$(git merge-base "$P1" "$P2"); fb=$(mktemp)
  git diff --name-only "$B" "$P2" | sort -u > "$fb"
  mism=0; while read -r f; do
    [ "$(git rev-parse -q --verify "${M}:${f}" 2>/dev/null)" = "$(git rev-parse -q --verify "${P2}:${f}" 2>/dev/null)" ] || mism=$((mism+1))
  done < "$fb"
  unexp=$(git diff --name-only "$P1" "$M" | sort -u | comm -23 - "$fb" | wc -l | tr -d ' ')
  blobs=$(git rev-list --objects "$M" --not "$P1" "$P2" | awk '{print $1}' | git cat-file --batch-check='%(objecttype)' | grep -c blob)
  echo "${M:0:8}: branch_files=$(wc -l < "$fb" | tr -d ' ') mismatches=$mism unexpected=$unexp new_blobs=$blobs"
  [ "$mism" -eq 0 ] && [ "$unexp" -eq 0 ] && [ "$blobs" -eq 0 ] || fail=1
  rm -f "$fb"
done
check() {  # label, reference, control-reference, paths...
  local label="$1" ref="$2" ctl="$3"; shift 3
  local n c; n=$(git diff --name-only "$ref" "$C" -- "$@" | wc -l | tr -d ' '); c=$(git diff --name-only "$ctl" "$C" -- "$@" | wc -l | tr -d ' ')
  echo "$label: differ=$n (control vs ${ctl:0:8}: $c)"; [ "$n" -eq 0 ] && [ "$c" -gt 0 ] || fail=1
}
check "supabase/ .github/ admin/ vs A's fix tip" "$A"  "$RC2"     supabase .github admin
check "app/ src/ tests/ vs C's tip"              "$CT" "$RC2"     app src tests
check "web/ vs live web"                         0b389584 5450b348 web
n=$(git diff --name-only "$RC2" "$C" -- package.json package-lock.json app.json 'app.config.*' eas.json ios android plugins assets babel.config.js metro.config.js scripts/patch-stripe-interop.mjs native tsconfig.json | wc -l | tr -d ' ')
echo "native-build inputs vs RC2: $n (expected 0)"; [ "$n" -eq 0 ] || fail=1
other=$(git diff --name-only "$RC2" "$C" | grep -v -E '^(supabase|\.github|admin|app|src|tests|web)/' | wc -l | tr -d ' ')
echo "files changed outside the owned surfaces: $other (expected 0)"; [ "$other" -eq 0 ] || fail=1
[ "$fail" -eq 0 ] && echo "RC3_VERIFY: PASS" || echo "RC3_VERIFY: FAIL"
exit $fail
