# Shared-sandbox acceptance window — execution manifest

Prepared by release integration (A), 2026-09-14. **Nothing here has been executed.**
Every pre-flight value below was read read-only at **2026-09-14 21:31:15Z**.

The owner starts the window; until then no session writes to the shared sandbox.

## 0. Scope and invariants

| | |
|---|---|
| Project | **sandbox `ofaidukbieeekqaboscm` only** |
| Production `hqycwntpfoztoinemqns` | **not touched** — no read, no write, no connection in any phase |
| Build 16 | pin **`df9e0d3`** unchanged; no app build, no submission |
| Edge functions | **no deploy**, no redeploy, in any phase |

**Explicitly NOT in this window**, and not implied by any step:

- Any change to `feature.native_issuance_enabled`, `feature.native_scanning_enabled`,
  `feature.native_resale_enabled` — all three are `false` and **stay** `false`.
- **Native ticket minting.** No row is written to `kernel.tickets` (see §5 — the populated-Tickets
  preview is excluded for exactly this reason).
- Any write to `kernel.signing_key`; C3; anything on the native/scanning track.
- **Migrations `125`, `126`, `127`, `128`.** 125 is B's and is not applied anywhere yet; 126–128 are mine and
  stay local. Applying any of them here would push the **sandbox** ledger tip above 125 and break the same
  ordering the GitHub guard protects — the guard is base-branch-relative, the sandbox ledger is not.

**Phases are strictly sequential on the shared sandbox**: A → D → C. Independent local development in all four
sessions continues in parallel throughout.

## 1. Pre-flight (A, read-only). Abort if any value differs.

| Check | Expected |
|---|---|
| Ledger rows | **130** |
| **Migration `123`** | **present** — `transfers_profiles_fk_parity`, 1 statement, md5 **`e34a675450ea76c4ed41a3ce43ce39f1`** |
| `123` effect | `transfers_buyer_id_fkey` and `transfers_seller_id_fkey` → `profiles`, ON DELETE **no action** |
| **`123` action** | **VERIFY ONLY — DO NOT REAPPLY.** Ledger row and effect are both already present |
| Migration `124` | **absent**; `bids_bidder_id_fkey` → `auth.users(id)`; `bids` orphans **0**; `bids` rows **0** |
| Native flags | issuance `false`, scanning `false`, resale `false` |
| `kernel.signing_key` / `kernel.tickets` | **0** / **0** |
| `venue_api` schema | **absent** |
| `pgrst.db_schemas` | `public, graphql_public, kernel` |
| `pgrst.db_pre_request` | `public.sandbox_pre_request` |
| Counts | listings **49**, payments **51**, transfers **33**, bids **0**, reserved **0**, pending payments **3**, push_tokens **1** |

## 2. Phase A — migration 124 (A runs; no owner action)

- **Source:** branch `fix/122-transfers-profiles-fk`, `supabase/migrations/124_bids_profiles_fk_parity.sql`,
  companion pgTAP `192`.
- **Writes:** DDL only — drop and recreate `bids_bidder_id_fkey` as `profiles(id) ON DELETE CASCADE`.
  **Zero data rows touched** (`bids` is empty in the sandbox).
- **Guards in the migration itself:** refuses if any orphan `bids` row exists; no-ops if the constraint already
  matches production.
- **Expected after:** `bids_bidder_id_fkey` → `profiles`, ON DELETE **cascade**; ledger **130 → 131**;
  every count and flag unchanged.
- **Verify:** pgTAP 192 green; counts unchanged; flags unchanged.
- **Rollback:** `supabase/rollbacks/124_bids_profiles_fk_parity_rollback.sql` returns the FK to `auth.users`.

## 3. Phase B — venue acceptance (D runs, A witnesses, owner does one setting change)

- **Source:** fixes `venue/read-slice1-fixes @ 2665a20`, kit `venue/slice1-acceptance-kit @ 492d641`,
  integration `venue/slice1-integration @ d2c634a`.

| Step | Who | Action |
|---|---|---|
| B1 | A | Record ledger count + Gate-2 census **before** |
| B2 | D | Apply `20260910120000_venue_api_read_views.sql` via the kit (its reviewed 24-statement ledger row) |
| B3 | A | Record ledger count + Gate-2 census **after** — expect **131 → 132** |
| B4 | **Owner** | Expose `venue_api` — the window's only setting change (§4) |
| B5 | D | Run the kit's api + browser phases, including **C6** (org-grant-without-venue-grant) and **C7** (pending venue) |
| B6 | D, then A | Kit `cleanup.sql` removes fixtures; A re-verifies counts |

- **Fixture writes:** org / venue / event / session / ticket-type / presale-batch rows and staff grants for
  venues A, B and pending C. Confined to the venue and catalog planes plus org staff roles.
  **No `kernel.tickets`, no `kernel.signing_key`, no marketplace `listings`/`payments`/`transfers`.**
- **Expected after cleanup:** `venue_api` present; fixtures gone; all §1 counts back to their pre-flight values.

## 4. Owner MFA steps and evidence (step B4 only)

1. Supabase Dashboard → project **`ofaidukbieeekqaboscm`** → sign in and **complete the MFA challenge**.
2. **Settings → API → Exposed schemas** (PostgREST `db_schemas`).
3. Add `venue_api` to the existing list. The field must read **exactly**:
   `public, graphql_public, kernel, venue_api`
4. Confirm **`db_pre_request` still reads `public.sandbox_pre_request`** — it must not change.
5. Save.

**Three evidence screenshots, captured by the owner** (release integration captures none):

| # | Shows |
|---|---|
| 1 | Exposed schemas **before** — `public, graphql_public, kernel` |
| 2 | Exposed schemas **after save** — all four, including `venue_api` |
| 3 | `db_pre_request` **unchanged** at `public.sandbox_pre_request` |

**Revert:** remove `venue_api` from the list, restoring `public, graphql_public, kernel`. Exposure and the
migration are two separate, separately-reversible steps — reverting the setting does not drop the schema.

## 5. Phase C — checkout reservation previews (C runs, A witnesses)

- **Source:** `frontend/premium-batch-1 @ 43e3a97`.
- **Writes:** `reserve_buy_now` on **one** active listing (`Device D7`, `Device D8` or `Phone P1`),
  **at most two** previews.
- **Cleanup:** each preview released explicitly with `release_reservation` — not left to lapse. A hold does
  self-clean (`auto-finalize-auctions`, `*/2`, calls `cleanup_expired_reservations`), but with only three
  active listings, tying one up for ten minutes is avoidable.
- **Expected after:** `reserved` back to **0**; listings / payments / transfers counts unchanged.

## 6. Excluded and needing its own decision — populated Tickets fixtures

C asked for populated-Tickets previews, which is the one untested Tickets state. **It is excluded from this
window**, because producing it means inserting rows into **`kernel.tickets`** — the native ticket table. That is
**native ticket data**, and the `feature.native_issuance_enabled` flag being `false` does not prevent it: the
flag gates the issuance *path*, not a direct fixture insert. Scheduling it inside this window would be exactly
the implicit native minting the owner ruled out.

If the owner wants it, it needs its own authorization and, as its own phase: a declared fixture set, a cleanup
returning `kernel.tickets` to **0**, and a re-verification that all three native flags are still `false`.

## 7. Expected final state, and abort conditions

**Final (after all phases and cleanup):** ledger **132**; `bids_bidder_id_fkey` → `profiles` ON DELETE cascade;
`venue_api` present (exposed, or reverted at the owner's choice); `kernel.tickets` **0**; `kernel.signing_key`
**0**; all three native flags **false**; reserved **0**; listings **49**, payments **51**, transfers **33**,
bids **0**, push_tokens **1**. A records the closing read-back.

**Stop immediately if:** any pre-flight value differs; any native flag changes; `kernel.tickets` or
`kernel.signing_key` becomes non-zero; any count moves outside the fixture writes declared above; or `123`
appears to need reapplying.
