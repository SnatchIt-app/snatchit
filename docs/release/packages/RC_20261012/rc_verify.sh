#!/bin/bash
# rc_verify.sh: the candidate checks A ran by hand for RC1, as one reproducible command (read-only; git only).
#
# usage: rc_verify.sh <candidate-sha> <first-merge-sha>...
#   For each listed merge commit M (parents P1 = previous line, P2 = merged branch), it reports:
#   - branch files and both-sided files at every merge-base;
#   - branch-file mismatches (M's file != P2's);
#   - unexpected changes (files M changes vs P1 that the branch did not change);
#   - new blobs (objects in M reachable from neither parent).
#   Then the surface identities against the fixed references below. Each "0" is printed together with a positive
#   control that must be non-zero, so an empty diff cannot pass silently.
# Exit 1 if any merge has mismatches, unexpected changes or new blobs, if a fixed surface differs, or if a control
# reads 0.
set -u
C="$1"; shift
fail=0
for M in "$@"; do
  P1=$(git rev-parse "$M^1"); P2=$(git rev-parse "$M^2")
  bases=$(git merge-base --all "$P1" "$P2")
  fb=$(mktemp); fg=$(mktemp)
  for B in $bases; do
    git diff --name-only "$B" "$P2" | sort -u > "$fb"; git diff --name-only "$B" "$P1" | sort -u > "$fg"
    echo "${M:0:8} @base ${B:0:8}: branch_files=$(wc -l < "$fb" | tr -d ' ') both_sided=$(comm -12 "$fb" "$fg" | wc -l | tr -d ' ')"
  done
  B=$(echo "$bases" | head -1); git diff --name-only "$B" "$P2" | sort -u > "$fb"
  mism=0; while read -r f; do
    [ "$(git rev-parse -q --verify "${M}:${f}" 2>/dev/null)" = "$(git rev-parse -q --verify "${P2}:${f}" 2>/dev/null)" ] || mism=$((mism+1))
  done < "$fb"
  unexp=$(git diff --name-only "$P1" "$M" | sort -u | comm -23 - "$fb" | wc -l | tr -d ' ')
  blobs=$(git rev-list --objects "$M" --not "$P1" "$P2" | awk '{print $1}' | git cat-file --batch-check='%(objecttype)' | grep -c blob)
  echo "${M:0:8}: mismatches=$mism unexpected=$unexp new_blobs=$blobs"
  [ "$mism" -eq 0 ] && [ "$unexp" -eq 0 ] && [ "$blobs" -eq 0 ] || fail=1
  rm -f "$fb" "$fg"
done
# Fixed surfaces: the candidate must equal these references.
check() {  # label, reference, control-reference, paths...
  local label="$1" ref="$2" ctl="$3"; shift 3
  local n c; n=$(git diff --name-only "$ref" "$C" -- "$@" | wc -l | tr -d ' '); c=$(git diff --name-only "$ctl" "$C" -- "$@" | wc -l | tr -d ' ')
  echo "$label: differ=$n (control vs ${ctl:0:8}: $c)"; [ "$n" -eq 0 ] && [ "$c" -gt 0 ] || fail=1
}
check "supabase/ vs gate"        abef9506 refs/remotes/origin/main supabase
check "web/ vs live web"         0b389584 5450b348 web
check "admin/ vs live console"   f7e7e85f 5450b348 admin
check ".github/ vs gate"         abef9506 d27aa449 .github
echo "app/src vs d27aa449: $(git diff --name-only d27aa449 "$C" -- app src | wc -l | tr -d ' ') files (expected non-zero for RC2: the fix branches)"
echo "native-build inputs vs d27aa449: $(git diff --name-only d27aa449 "$C" -- package.json package-lock.json app.json 'app.config.*' eas.json ios android plugins assets babel.config.js metro.config.js scripts/patch-stripe-interop.mjs native tsconfig.json | wc -l | tr -d ' ')"
[ "$fail" -eq 0 ] && echo "RC_VERIFY: PASS" || echo "RC_VERIFY: FAIL"
exit $fail
