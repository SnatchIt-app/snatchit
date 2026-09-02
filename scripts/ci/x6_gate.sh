#!/usr/bin/env bash
# ============================================================================
# X-6 export-source gate — T-CI-X6-01 (forbidden-identifier scan), T-CI-X6-02
# (spec §2.2 table ≡ column manifest), T-CI-X6-03 (floors + positive controls).
# Runs in the `quality` job BEFORE `npm ci` (no database). Sources of truth:
#   supabase/ci/x6_forbidden.json · x6_scanned_paths.txt · crm_export_columns.json
#   · x6_floors.env — no check carries its own copy of any list.
# Spec: docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md §10.2 (rules 1-3) and
# _governance/X6_POSTGRES_OWNED_ASSURANCE_PLAN.md §R1/§R3/§R6.
# Usage: scripts/ci/x6_gate.sh            (gate)
#        scripts/ci/x6_gate.sh --emit-columns   (regenerate the column manifest from the spec)
# ============================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MODE="${1:-gate}"
FLOORS=supabase/ci/x6_floors.env
FORBIDDEN=supabase/ci/x6_forbidden.json
PATHS=supabase/ci/x6_scanned_paths.txt
COLUMNS=supabase/ci/crm_export_columns.json
SPEC=docs/architecture/PHASE_2_CRM_EXPORT_SPEC.md
POISON=supabase/ci/x6_fixtures/poison
ALLOW_MARK='-- x6-allow: naming-only'
for f in "$FLOORS" "$FORBIDDEN" "$PATHS" "$SPEC"; do
  [ -f "$f" ] || { echo "::error::X-6 gate input missing: $f"; exit 1; }
done
# shellcheck disable=SC1090
. "$FLOORS"
command -v jq >/dev/null || { echo "::error::jq is required by the X-6 gate"; exit 1; }
TMP="${RUNNER_TEMP:-$(mktemp -d)}"

# ── the scanner (a function, so the positive control can point it at poison) ──
# args: <path-list-file> <term-list-file> <expected-allow-markers> ; prints hits; returns 1 on any failure
x6_scan() {
  local plist="$1" terms="$2" expect_markers="$3" find_list="$TMP/x6_files.$$" hits markers files_n terms_n
  : > "$find_list"
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    # shellcheck disable=SC2086
    ls -1 $pat 2>/dev/null >> "$find_list" || true
  done < "$plist"
  LC_ALL=C sort -u -o "$find_list" "$find_list"
  files_n=$(wc -l < "$find_list" | tr -d ' ')
  [ "${files_n:-0}" -ge "$X6_MIN_SCANNED_FILES" ] || {
    echo "::error::X-6 scan resolved ${files_n} file(s), floor is ${X6_MIN_SCANNED_FILES}. A grep over nothing passes forever."; return 1; }
  echo "X-6 scan set (${files_n} files):"; sed 's/^/  /' "$find_list"
  terms_n=$(wc -l < "$terms" | tr -d ' ')
  [ "${terms_n:-0}" -ge "$X6_MIN_FORBIDDEN_TERMS" ] || {
    echo "::error::forbidden-term list yields ${terms_n} term(s), floor is ${X6_MIN_FORBIDDEN_TERMS} — truncated manifest, vacuous scan."; return 1; }
  # shellcheck disable=SC2046
  hits=$(grep -n -F -f "$terms" -- $(cat "$find_list") | grep -v -F -- "$ALLOW_MARK" || true)
  # shellcheck disable=SC2046
  markers=$(grep -c -F -- "$ALLOW_MARK" $(cat "$find_list") 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
  if [ -n "$hits" ]; then
    echo "::error::X-6 forbidden identifier(s) in export sources:"; printf '%s\n' "$hits" | sed 's/^/  /'; return 1
  fi
  if [ "${markers:-0}" -ne "$expect_markers" ]; then
    echo "::error::X-6 allow-marker count ${markers} != expected ${expect_markers} — a marker added to silence a real hit fails, as does a stale expectation."; return 1
  fi
  echo "X-6 scan: 0 hits over ${terms_n} terms, ${markers} allow marker(s) (expected ${expect_markers})"
  return 0
}

# ── T-CI-X6-02 helper: parse the §2.2 pipe table → JSON array of {n,field,class,grain} ──
parse_spec_columns() {
  awk '
    /^### 2\.2 The catalogue/ {sec=1; next}
    sec && /^### / {sec=0}
    sec && /^\| *[0-9]+ *\|/ {
      line=$0
      n=split(line, c, "|")
      # cells: c[2]=#, c[3]=field, c[4]=class, c[5]=grain
      for (i=2;i<=5;i++){ gsub(/^[ \t]+|[ \t]+$/, "", c[i]); gsub(/[`*]/, "", c[i]); gsub(/[ \t]+/, " ", c[i]) }
      printf "{\"n\":%d,\"field\":\"%s\",\"class\":\"%s\",\"grain\":\"%s\"}\n", c[2], c[3], c[4], c[5]
    }' "$SPEC" | jq -s '.'
}

if [ "$MODE" = "--emit-columns" ]; then
  parse_spec_columns | jq '{ "_doc": "GENERATED from PHASE_2_CRM_EXPORT_SPEC.md §2.2 by scripts/ci/x6_gate.sh --emit-columns (T-CI-X6-02). Do not hand-edit: the gate diffs this file against the spec table on every PR; the pgTAP suite (T-RPC-CRM-16, at un-park) diffs it against the emitted header.", "columns": . }' > "$COLUMNS"
  echo "wrote $COLUMNS ($(jq '.columns|length' "$COLUMNS") columns)"; exit 0
fi

rc=0
echo "### T-CI-X6-01 — forbidden-identifier scan"
jq -r '.terms[]' "$FORBIDDEN" > "$TMP/x6_terms.txt"
x6_scan "$PATHS" "$TMP/x6_terms.txt" "$X6_EXPECT_ALLOW_MARKERS" || rc=1

echo "### T-CI-X6-01 rule 3 — rename tripwire (every term must live somewhere OUTSIDE the scan set)"
scan_files=$(while IFS= read -r pat; do [ -n "$pat" ] && ls -1 $pat 2>/dev/null; done < "$PATHS" | LC_ALL=C sort -u)
while IFS= read -r term; do
  # shellcheck disable=SC2086
  if ! grep -rlF -- "$term" supabase/migrations supabase/functions docs/architecture 2>/dev/null | grep -v -F -x -f <(printf '%s\n' $scan_files) | grep -q .; then
    echo "::error::forbidden term '${term}' appears nowhere else in the repository — it has been renamed and this scan is now looking for a string that no longer exists."; rc=1
  fi
done < "$TMP/x6_terms.txt"

echo "### T-CI-X6-02 — spec §2.2 table ≡ column manifest"
[ -f "$COLUMNS" ] || { echo "::error::$COLUMNS missing — run scripts/ci/x6_gate.sh --emit-columns and commit it."; rc=1; }
if [ -f "$COLUMNS" ]; then
  parsed=$(parse_spec_columns)
  n=$(printf '%s' "$parsed" | jq 'length')
  if [ "$n" -ne "$X6_EXPECT_COLUMNS" ]; then
    echo "::error::§2.2 parse yielded ${n} columns, expected exactly ${X6_EXPECT_COLUMNS} (anchor missing or table edited)."; rc=1
  fi
  grep -q '^### 2\.3 The never-exported list' "$SPEC" || { echo "::error::§2.3 anchor missing from the CRM spec"; rc=1; }
  if ! diff <(printf '%s' "$parsed" | jq -S '.') <(jq -S '.columns' "$COLUMNS") > "$TMP/x6_cols.diff"; then
    echo "::error::column manifest drifted from the spec table (ordered set: n/field/class/grain):"; sed 's/^/  /' "$TMP/x6_cols.diff"; rc=1
  else
    echo "column manifest ≡ spec table (${n} columns)"
  fi
fi

echo "### T-CI-X6-03 — positive controls (the scanner must FAIL on the poison directory)"
[ -d "$POISON" ] || { echo "::error::poison directory $POISON missing — the scanner cannot be proven live."; rc=1; }
if [ -d "$POISON" ]; then
  printf '%s\n' "$POISON/*.sql" "$POISON/*.ts" > "$TMP/x6_poison_paths.txt"
  if x6_scan "$TMP/x6_poison_paths.txt" "$TMP/x6_terms.txt" "$X6_EXPECT_ALLOW_MARKERS" > "$TMP/x6_poison.out" 2>&1; then
    echo "::error::positive control FAILED: the scanner passed the poison directory — it is broken (bad glob, swallowed exit, empty term list)."; rc=1
  else
    grep -q 'forbidden identifier' "$TMP/x6_poison.out" && echo "positive control: FAILED as required (poison hits detected)" || { echo "::error::positive control failed for the wrong reason:"; cat "$TMP/x6_poison.out"; rc=1; }
  fi
  # the 22-column markdown poison must fail the §2.2 parser's =21 equality
  pn=$(awk '/^### 2\.2 The catalogue/ {sec=1; next} sec && /^### / {sec=0} sec && /^\| *[0-9]+ *\|/ {c++} END {print c+0}' "$POISON/poison_columns.md")
  if [ "$pn" -eq "$X6_EXPECT_COLUMNS" ]; then echo "::error::poison column table has ${pn} rows — the control would not distinguish it from the spec."; rc=1; else echo "positive control: poison column table (${pn} rows) != ${X6_EXPECT_COLUMNS}, as required"; fi
fi

echo "### suite manifests — the pgTAP suite's embedded copies ≡ the JSON manifests (one truth, drift detected)"
SUITE=supabase/tests/152_crm_export_x6.sql
if [ -f "$SUITE" ]; then
  suite_eps=$(awk '/X6-ENTRY-POINTS-BEGIN/{f=1;next} /X6-ENTRY-POINTS-END/{f=0} f' "$SUITE" | grep -o "'[^']*'" | tr -d "'" | LC_ALL=C sort)
  json_eps=$(jq -r '.entry_points[]' supabase/ci/x6_entry_points.json | LC_ALL=C sort)
  if [ "$suite_eps" != "$json_eps" ]; then echo "::error::152_crm_export_x6.sql entry-point list drifted from supabase/ci/x6_entry_points.json"; diff <(printf '%s\n' "$suite_eps") <(printf '%s\n' "$json_eps") | sed 's/^/  /'; rc=1; else echo "suite manifests: entry points ≡ JSON ($(printf '%s\n' "$json_eps" | wc -l | tr -d ' '))"; fi
  suite_terms=$(awk '/X6-TERMS-BEGIN/{f=1;next} /X6-TERMS-END/{f=0} f' "$SUITE" | grep -o "'[^']*'" | tr -d "'" | LC_ALL=C sort)
  json_terms=$(jq -r '.terms[]' "$FORBIDDEN" | LC_ALL=C sort)
  if [ "$suite_terms" != "$json_terms" ]; then echo "::error::152_crm_export_x6.sql term list drifted from supabase/ci/x6_forbidden.json"; diff <(printf '%s\n' "$suite_terms") <(printf '%s\n' "$json_terms") | sed 's/^/  /'; rc=1; else echo "suite manifests: terms ≡ JSON ($(printf '%s\n' "$json_terms" | wc -l | tr -d ' '))"; fi
else
  echo "::error::$SUITE missing — the X-6 pgTAP suite (T-RPC-CRM-14/15/19) was removed."; rc=1
fi

if [ $rc -eq 0 ]; then echo "X-6 gate: PASS"; else echo "X-6 gate: FAIL"; fi
exit $rc
