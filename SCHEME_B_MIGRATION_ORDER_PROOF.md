# Scheme B — Migration Order Proof

**Artifact of the one-time historical migration normalization.** Generated from the actual chain; every number below was computed, not asserted.

## Pinned tooling
`supabase/setup-cli` @ **CLI 2.115.0** (pinned in `.github/workflows/ci.yml`; never `latest`).

## Why Scheme B and not Scheme A
Scheme A renamed only the 11 letter-suffixed files (`055b` → `0551`). That leaves `055` as a **prefix** of `0551`. Filenames then sort `0551_… < 055_…` (`'1'`=0x31 < `'_'`=0x5F) while versions sort `055 < 0551`. Replay order therefore depends on whether the tool sorts filenames or re-parses versions — Supabase CLI 2.75.0 (Go) sorts filenames, 2.115.0 (TS) re-sorts by version. Scheme B removes the ambiguity instead of pinning around it.

## Rename count — verified, not assumed
The chain contains **no `056` parent file** (only `056a`–`056d`). Scheme B is therefore **16 renames**, not the 17 that was expected. `0560` is left permanently unused as a record of that fact.

## Complete mapping (16)
| Old file | Old ver | New file | New ver | Predecessor | Successor | Why this version |
|---|---|---|---|---|---|---|
| `023_user_reports_and_blocks.sql` | `023` | `0230_user_reports_and_blocks.sql` | `0230` | `022` | `024` | parent of 023b; renamed so 023 is not a prefix of 0231 |
| `023b_set_updated_at_helper.sql` | `023b` | `0231_set_updated_at_helper.sql` | `0231` | `0230` | `024` | letter suffix -> numeric child of 0230 |
| `055_transfer_state_guard.sql` | `055` | `0550_transfer_state_guard.sql` | `0550` | `054` | `0551` | parent of 055b/c/d |
| `055b_transfer_guard_bypass_for_remaining_writers.sql` | `055b` | `0551_transfer_guard_bypass_for_remaining_writers.sql` | `0551` | `0550` | `0552` | letter -> child 1 |
| `055c_revoke_anon_public_on_listing_rpcs.sql` | `055c` | `0552_revoke_anon_public_on_listing_rpcs.sql` | `0552` | `0551` | `0553` | letter -> child 2 |
| `055d_fix_mark_transfer_sent_overload_ambiguity.sql` | `055d` | `0553_fix_mark_transfer_sent_overload_ambiguity.sql` | `0553` | `0552` | `0561` | letter -> child 3 |
| `056a_transfer_writer_rpcs.sql` | `056a` | `0561_transfer_writer_rpcs.sql` | `0561` | `0553` | `0562` | letter -> child 1 (no 056 parent exists; 0560 left as a deliberate gap) |
| `056b_remove_transfer_guard_service_role_exemption.sql` | `056b` | `0562_remove_transfer_guard_service_role_exemption.sql` | `0562` | `0561` | `0563` | letter -> child 2 |
| `056c_scope_transfer_guard_bypass_to_function.sql` | `056c` | `0563_scope_transfer_guard_bypass_to_function.sql` | `0563` | `0562` | `0564` | letter -> child 3 |
| `056d_record_transfer_payout_refuses_disputed.sql` | `056d` | `0564_record_transfer_payout_refuses_disputed.sql` | `0564` | `0563` | `057` | letter -> child 4 |
| `059_strict_auth_on_listing_checkout_rpcs.sql` | `059` | `0590_strict_auth_on_listing_checkout_rpcs.sql` | `0590` | `058` | `0591` | parent of 059b |
| `059b_strict_auth_ensure_transfer_exists.sql` | `059b` | `0591_strict_auth_ensure_transfer_exists.sql` | `0591` | `0590` | `0600` | letter -> child 1 |
| `060_auth_password_change_notifications.sql` | `060` | `0600_auth_password_change_notifications.sql` | `0600` | `0591` | `0601` | parent of 060b |
| `060b_fix_sweep_query_destination.sql` | `060b` | `0601_fix_sweep_query_destination.sql` | `0601` | `0600` | `061` | letter -> child 1 |
| `066_pin_search_path_definer_functions.sql` | `066` | `0660_pin_search_path_definer_functions.sql` | `0660` | `065` | `0661` | parent of 066a |
| `066a_vendor_out_of_band_functions.sql` | `066a` | `0661_vendor_out_of_band_functions.sql` | `0661` | `0660` | `067` | letter -> child 1 |

Plus 8 companion files in `supabase/rollbacks/` renamed to match (nothing reads them programmatically).

## Ordering assumption (stated explicitly, not assumed)
Scheme B is correct under **lexicographic text ordering**, which is what every consumer in this stack
actually uses: the Supabase CLI (both the Go and TypeScript implementations) and the
`supabase_migrations.schema_migrations.version` column, which is `text`.

It is **not** integer-safe, and that is a deliberate, documented trade-off: under a hypothetical
integer parse, `0230` → 230 would sort after `070` → 70. The pre-normalization chain happened to be
both text- and integer-safe; Scheme B trades the latter to eliminate prefix ambiguity, which is the
failure mode that actually bites real tooling. Making it integer-safe as well would require
renumbering all 84 migrations to a uniform width — a far larger blast radius for a hazard no consumer
in this stack exhibits. **Invariant to preserve: migration versions are compared as text.**

## Proofs
| Property | Result |
|---|---|
| Migration files | **84** |
| Renames | **16** (+8 rollbacks) |
| `git diff --find-renames=100%` | **16 × R100**, 0 insertions, 0 deletions |
| SHA-256 content identical | **16/16 = true** |
| Duplicate versions | **0** |
| Letter-suffixed versions remaining | **0** |
| **Version-prefix relationships** | **0** |
| **filename order == version order** | **true** |
| Ordering model | **text (lexicographic)** — see assumption above |

## Normalized sequence (affected regions, full context)
```
022  < 0230 < 0231 < 024  < 025
054  < 0550 < 0551 < 0552 < 0553 < 0561 < 0562 < 0563 < 0564 < 057 < 058
058  < 0590 < 0591 < 0600 < 0601 < 061  < 062
065  < 0660 < 0661 < 067  < 068  < 069  < 070 < 2026…
```
Every adjacent pair satisfies both *A sorts before B* and *A historically executed before B*.

## Full normalized version sequence (84)
```
000, 001, 002, 003, 004, 005, 006, 007, 008, 009, 010, 011, 012, 013, 014, 015, 016, 017, 018, 019, 020, 021, 022, 0230, 0231, 024, 025, 026, 027, 028, 029, 030, 031, 032, 033, 034, 035, 036, 037, 038, 039, 040, 041, 042, 044, 045, 046, 047, 048, 049, 050, 051, 052, 053, 054, 0550, 0551, 0552, 0553, 0561, 0562, 0563, 0564, 057, 058, 0590, 0591, 0600, 0601, 061, 062, 063, 064, 065, 0660, 0661, 067, 068, 069, 070, 20260714190445, 20260730212326, 20260730212406, 20260731224653
```

## Gate-2 parity — scope of the assertion
The CI gate asserts **equality** on the four classes the Phase-0 certification pins:
`tables=27, functions=68, policies=37, triggers=23` — matched exactly by the fresh replay **and** by
live production (verified read-only).

Two classes are **known to differ** between a fresh replay and production and are therefore *not*
asserted: **indexes** (production 90 / fresh 93) and **storage policies** (production 11 / fresh 17).
Both deltas were documented at Gate-2 certification and are residuals of out-of-band objects, not
drift introduced by this normalization. A fresh replay is therefore *equivalent on the certified
classes*, not byte-identical to production — stating otherwise would be an overclaim.

## Guard test matrix (executed, not inspected)
| Case | Expected | Result |
|---|---|---|
| 1 Approved Scheme-B renames only | PASS | **PASS** |
| 2 Approved rename **+ content edit** | FAIL | **FAIL** |
| 3 Unapproved historical rename | FAIL | **FAIL** |
| 4 Historical migration deletion | FAIL | **FAIL** |
| 5 Normal new migration `071_` | PASS | **PASS** |
| 6 Back-dated new migration `043_` | FAIL | **FAIL** |
| 7 Duplicate version prefix | FAIL | **FAIL** |
| 8 Historical content modification | FAIL | **FAIL** |
| 9 Add a rename TARGET without deleting its source | FAIL | **FAIL** |
| 10 New `0700_` (prefix of existing `070`) | FAIL | **FAIL** |
| 11 New `202607312246531_` (extends a timestamp) | FAIL | **FAIL** |
| 12 New `0231_` file with no matching deletion | FAIL | **FAIL** |

Case 2 initially **passed incorrectly**: git paired the edited rename as `R98`, dodging the `--diff-filter=MD` check while `--find-renames=100%` also declined to call it a rename. The guard now compares **blob hashes** with rename detection disabled, so content identity is proven rather than inferred.
