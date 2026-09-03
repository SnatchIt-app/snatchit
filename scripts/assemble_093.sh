#!/usr/bin/env bash
# scripts/assemble_093.sh — build supabase/migrations/093_primary_ticketing.sql
# from the four reviewed slices in docs/phase2/_impl/093_parts/.
#
# CANONICAL SOURCE RULE (mechanically enforced — see
# scripts/ci/assembled_migration_integrity.sh and docs/phase2/_impl/G4_assembler_integrity.md)
#   THE SLICES ARE CANONICAL. The assembled migration is a BUILD ARTIFACT.
#   Edit docs/phase2/_impl/093_parts/*.sql, re-run this script, commit BOTH.
#   A hand-edit of supabase/migrations/093_primary_ticketing.sql is a CI failure,
#   not a style preference: the gate regenerates the file from the committed
#   slices and compares it byte-for-byte.
#
# WHY THIS EXISTS RATHER THAN ONE HAND-EDITED FILE
# The slices were authored and validated independently, and each one is a
# coherent reviewable unit tied to a specific owner ruling. Assembling
# mechanically means the migration cannot drift from the reviewed parts: re-run
# this and diff. The parts stay in the repo as the review surface; the assembled
# file is what the chain applies.
#
# ORDER IS LOAD-BEARING, and it is not alphabetical by accident:
#   10 money/settlement  — replaces the settlement engine; depends on nothing new
#   20 payments contract — relaxes public.payments; gates the whole direct rail
#   30 connect/org       — adds the two columns the checkout gate reads
#   40 config/privacy    — seeds keys, freezes operatorship, scopes order columns
# 30 must precede any consumer of its columns. 20 must precede anything that
# writes a direct-rail payment row.
#
# This script only WRITES the file. It never applies it. Rehearsal is
# scripts/rehearsal_reset.sh, which is itself refused against anything that is
# not a local database.
#
# DETERMINISM CONTRACT. The output is a pure function of the slice bytes and of
# this script. No timestamps, no hostname, no git revision, no `find`, no glob
# expansion, no locale-dependent sort: the part list is an explicit array and
# LC_ALL is pinned so that even an incidental future `sort` cannot become
# environment-dependent. The CI gate both greps this file for those constructs
# and proves reproducibility by re-running it under a perturbed environment.
#
# MODES
#   assemble_093.sh              write the assembled migration (default)
#   assemble_093.sh --manifest   print the build inputs and output as key=value
#                                lines and write NOTHING. This is the contract
#                                the CI gate reads; any future assembler must
#                                implement it identically (keys: assembler, out,
#                                parts_dir, part — paths relative to the repo
#                                root, `part` repeated in assembly order).
set -euo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
self_rel="scripts/assemble_093.sh"
parts_rel="docs/phase2/_impl/093_parts"
out_rel="supabase/migrations/093_primary_ticketing.sql"
parts_dir="$repo_root/$parts_rel"
out="$repo_root/$out_rel"

parts=(
  10_money_settlement.sql
  20_payments_contract.sql
  30_connect_org.sql
  40_config_privacy_freeze.sql
)

if [ "${1:-}" = "--manifest" ]; then
  printf 'assembler=%s\n' "$self_rel"
  printf 'out=%s\n' "$out_rel"
  printf 'parts_dir=%s\n' "$parts_rel"
  for p in "${parts[@]}"; do printf 'part=%s\n' "$p"; done
  exit 0
fi
if [ "$#" -gt 0 ]; then
  echo "usage: $self_rel [--manifest]" >&2
  exit 2
fi

for p in "${parts[@]}"; do
  [ -f "$parts_dir/$p" ] || { echo "missing slice: $parts_dir/$p" >&2; exit 1; }
done

{
  # ---------------------------------------------------------------------------
  # GENERATED-FILE BANNER — the first line is MACHINE-READ.
  #
  # scripts/ci/assembled_migration_integrity.sh scans EVERY file in
  # supabase/migrations/ for `-- @generated-by: <path>`. Any migration carrying
  # that line must have that assembler present, and that assembler must
  # reproduce the file byte-for-byte. This is what stops the gate being
  # satisfied by deleting things: removing the slices makes the assembler exit
  # non-zero, and removing the assembler leaves a banner pointing at a file that
  # is no longer there. Both are loud failures, not skips.
  #
  # The banner cannot itself drift, because it IS assembler output: editing it
  # inside the migration fails the same byte comparison as any other hand-edit.
  # ---------------------------------------------------------------------------
  cat <<'BANNER'
-- @generated-by: scripts/assemble_093.sh
-- =============================================================================
-- !!  GENERATED FILE — DO NOT EDIT BY HAND  !!
--
-- Assembled from the reviewed slices in docs/phase2/_impl/093_parts/.
-- THE SLICES ARE CANONICAL. This file is a build artifact.
--
-- To change anything below:
--   1. edit the slice under docs/phase2/_impl/093_parts/
--   2. run ./scripts/assemble_093.sh
--   3. commit the slice AND this regenerated file together
--
-- A hand-edit here is reverted by the next assembler run and is REJECTED BY CI:
-- the "Migrations guard / Immutability + ordering" job regenerates this file
-- from the committed slices and compares it byte-for-byte
-- (scripts/ci/assembled_migration_integrity.sh).
-- =============================================================================
BANNER

  cat <<'HEADER'
-- =============================================================================
-- 093_primary_ticketing.sql
--
-- Venue-direct primary ticketing: the database half.
--
-- AUTHORITY. Every object below implements a ruling ratified by the owner on
-- 2026-09-02 and recorded in docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md.
-- The evidence behind those rulings is in docs/phase2/_rulings/ and the scope
-- derivation is docs/phase2/093_FINAL_PROPOSED_SCOPE.md. Nothing here was
-- invented at the keyboard.
--
-- WHAT THIS MIGRATION IS NOT. It does not activate anything. Every Phase-2 rail
-- stays dark, every feature flag stays off, and no money can move when it lands:
-- there is still no payout executor, and the buyer-side fee key and the ticket
-- expiry grace both ship with NULL values that the owner must set before
-- issuance is switched on. Applying this file changes what the system CAN be
-- configured to do, not what it does.
--
-- SHAPE. 0 new tables. 0 new enum members. 0 new policies beyond two policy
-- REPLACEMENTS that add a missing authority conjunct. 0 DDL on any money-ledger
-- table. 2 new columns, both on kernel.organization, both additive.
--
-- MIGRATIONS 076-092 ARE IMMUTABLE and are not touched. Every behaviour change
-- to an existing function is a CREATE OR REPLACE of its body at its exact
-- existing signature.
--
-- ONE LOCK MATTERS: the ALTERs on public.payments. That table holds ~56
-- production rows and the change is catalogue-only, but the statement takes an
-- ACCESS EXCLUSIVE lock and therefore runs under an explicit lock_timeout.
--
-- ASSEMBLED by scripts/assemble_093.sh from docs/phase2/_impl/093_parts/.
-- Edit the parts, not this file, then re-run the assembler.
-- =============================================================================

HEADER

  for p in "${parts[@]}"; do
    printf '\n\n-- ###########################################################################\n'
    printf -- '-- ## SLICE: %s\n' "$p"
    printf -- '-- ###########################################################################\n\n'
    cat "$parts_dir/$p"
  done
} > "$out"

lines=$(wc -l < "$out" | tr -d ' ')
echo "assembled $out  ($lines lines from ${#parts[@]} slices)"
echo
echo "NOT APPLIED. To rehearse locally:"
echo "  ./scripts/rehearsal_reset.sh snatchit_rehearsal && ./scripts/rehearsal_test.sh snatchit_rehearsal"
