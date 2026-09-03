#!/usr/bin/env bash
# scripts/assemble_093.sh — build supabase/migrations/093_primary_ticketing.sql
# from the four reviewed slices in docs/phase2/_impl/093_parts/.
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
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
parts_dir="$repo_root/docs/phase2/_impl/093_parts"
out="$repo_root/supabase/migrations/093_primary_ticketing.sql"

parts=(
  10_money_settlement.sql
  20_payments_contract.sql
  30_connect_org.sql
  40_config_privacy_freeze.sql
)

for p in "${parts[@]}"; do
  [ -f "$parts_dir/$p" ] || { echo "missing slice: $parts_dir/$p" >&2; exit 1; }
done

{
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
