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

- **Source:** fixes `venue/read-slice1-fixes @ 2665a20`, kit `venue/slice1-acceptance-kit @ 62ec887`,
  integration `venue/slice1-integration @ d2c634a`.

| Step | Who | Action |
|---|---|---|
| B1 | A | Record ledger count + Gate-2 census **before** |
| B2 | D | Apply `20260910120000_venue_api_read_views.sql` via the kit (its reviewed 24-statement ledger row) |
| B3 | A | Record ledger count + Gate-2 census **after** — expect **131 → 132** |
| B4 | **Owner** | Expose `venue_api` — the window's only setting change (§4) |
| B5 | D | Run the kit's api + browser phases, including **C6** (org-grant-without-venue-grant) and **C7** (pending venue) |
| B6 | D, then A | Kit `cleanup.sql` removes fixtures **by exact id**; A re-verifies counts |

**Kit pin moved `492d641` → `62ec887` (verified by A):** the diff is docs and acceptance scripts only — runbook,
venue manifest, `cleanup.sql`, `preflight.sql`, `accept.mjs` (+6, postflight) and `lib/cdp.mjs` (+2, which D's
summary did not mention). **No `venue/src` and no `supabase/` change**, so the reviewed application code and the
migration are untouched by the re-pin. The kit's preflight now records 24 out-of-scope table counts plus a
`platform_config` digest, and postflight fails unless all are back to baseline and `db_pre_request` is unchanged —
which is what mechanically separates venue acceptance from native Tickets fixtures and checkout previews, and
proves no flag moved.

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

## 8. SBX-2 — marketplace phase, as authorized 2026-09-15 and reconciled to the pin (A, 2026-09-15)

**Authorization text (owner, 2026-09-15):** "migrations 125→126→127→128 in order; sandbox deployment of
stripe-webhook and create-payment-intent; and the documented verification, including notification registration."
**Reconciliation:** the pinned candidate (`4b012fd`) also carries **129** (`public.revoke_push_token` — the client's
sign-out revoke; without it DV-611's sign-out read-back fails by construction) and **130** (checkout supersede claim,
which the deployed `create-payment-intent` calls; absent, the edge degrades to #64 behaviour and DV-L1/L2 do not
exercise the claim). **Applying 129 and 130 to the sandbox is NOT covered by the authorization as written** — A asks
the owner to extend O-1 to `125 → 126 → 127 → 128 → 129 → 130`, or SBX-2 runs 125–128 only with the two
verifications above recorded as not exercised.

**Order on the shared sandbox (D's sequencing flag, confirmed):** Phase A (124) → **SBX-2** (125→130 in `LC_ALL=C`
order, then deploy `stripe-webhook` and `create-payment-intent` from the pin, then DV-611 L/S/R/C and DV-L1/L2
read-backs) → Phase C previews → **venue Phase B last** (its timestamped migration sorts above every numeric one and
would otherwise drop later numeric applies out of the default plan). Owner MFA is needed only at the venue exposure
step, the last act.

**Pre-flight for SBX-2 (A, read-only, immediately before):** ledger count and the exact planned list from a dry run
must equal `125,126,127,128,129,130` and nothing else; 123 present (verify-only); native flags all `false`;
`kernel.tickets` 0; `kernel.signing_key` 0. **126's L-1 precondition (B):**
`select count(*) from public.payments where status='refunded' and refunded_at is null` must be **0** on the sandbox
before 126 applies (the same read on production is a separate owner-authorized item). **Stop** on any unexpected
value or an uncertain mutation outcome.
**Expected after:** ledger 131 + (Phase A's 124) as the manifest counts them; both edges byte-identical to the pin
(`git show candidate/2026-09-18-pin:supabase/functions/<fn>/index.ts` vs the deployed source); no flag moved;
counts back to baseline after DV cleanup.

## 9. SBX-2 — command-level runbook (A executes; D witnesses ledger/census; C runs DV rows)

All against **`ofaidukbieeekqaboscm` only**; `--project-ref` on every command. **Never `--linked`: `/Users/josetascon/snatchit` is linked to PRODUCTION (`supabase/.temp/project-ref` = `hqycwntpfoztoinemqns`, found by D 2026-09-15); run every sandbox command with the explicit sandbox ref or through `apply_sandbox_migration.sh`, which asserts the sandbox ref twice and refuses the production ref.**
Every mutation is preceded by the read it changes and followed by the read that proves it. **Stop** on any value
that differs from the expected one below.

| # | Step | Command / query | Expected |
|---|---|---|---|
| 0 | Source | `git checkout candidate/2026-09-18-pin` (the tag; `git rev-parse HEAD` = the pinned commit) | tree = pin |
| 1 | Ledger before | `select version from supabase_migrations.schema_migrations order by version` | 123 present, 124 present (Phase A done), 125–130 **absent** |
| 2 | Planned set | **NOT `db push --include-all`** — it would also plan 121 (never authorized for the sandbox) and 126 (cannot apply there). Per version: `scripts/release/apply_sandbox_migration.sh <v> preflight /tmp/wt-pin` from the pinned worktree | preflight OK for each version in the authorized set, in order |
| 3 | 126 precondition (B's L-1) | `select count(*) from public.payments where status='refunded' and refunded_at is null` | **0** |
| 4 | Flags / native | `feature.native_*` all false; `kernel.tickets`, `kernel.signing_key` = 0 | unchanged |
| 5 | Apply | per version, in order: `apply_sandbox_migration.sh <v> apply /tmp/wt-pin` then `… verify` (ledger row from the pinned file's exact bytes; md5 must match) | each version recorded once, md5 == pinned file |
| 6 | Ledger after | as 1 | 125–130 present exactly once each |
| 7 | Census after | tables/functions/policies/triggers in `public` | **31 / 96 / 37 / 35** (matches ci.yml at the pin) |
| 8 | Object spot-checks | `release_reservation_for_payment`, `register_push_token` (comment says 128 v2), `revoke_push_token`, `claim_checkout_supersede`, `push_token_rebind_epoch` 1 row, `push_tokens` grants: anon/authenticated `DELETE,INSERT` only | present / as stated |
| 9 | Edge deploy | `supabase functions deploy stripe-webhook --project-ref ofaidukbieeekqaboscm` then `create-payment-intent` | both deployed |
| 10 | Edge parity | compare deployed source (`supabase functions download` or the dashboard's source) to `git show candidate/2026-09-18-pin:supabase/functions/<fn>/index.ts` | byte-identical |
| 11 | DV-611 L/S/R/C (C, with a device on the sandbox build) and DV-L1/L2 read-backs (A) | per `CANDIDATE_BUILD_AND_DEVICE_PLAN.md`; server read-backs via `execute_sql` and `edge_logs` (wait ≥ 10 min before calling a request absent) | rows as planned |
| 12 | Cleanup | release any preview hold via `release_reservation`; delete DV fixture tokens by exact id | counts back to §1 baseline (+ledger rows) |
| 13 | Closing read-back | 1, 4, 7 again; write the result in this file | recorded |

**Rollback, if a step fails after 5:** the per-migration rollbacks under `supabase/rollbacks/` in reverse order
(130 → 125), each proven locally to restore the previous catalog byte-for-byte (127/129/130 md5-identical; 128
and 131 with their declared exceptions); edges redeployed from `df9e0d3` only if a rollback below 127 is run.
**Nothing here is production.** The production apply sequence is §3 of the release package and needs its own
authorizations.

## 10. EXECUTION RECORD — 2026-09-15 (A; sandbox `ofaidukbieeekqaboscm` only; STOPPED on unexpected state)

**Pre-flight (read-only, 05:3x Z):** ledger **130**; 123 present, 124 absent (`bids_bidder_id_fkey → auth.users`);
listings 49, payments 51, transfers 33, bids 0, reserved 0, pending 3, push_tokens 1; `kernel.tickets` 0,
`kernel.signing_key` 0; native flags issuance/scanning/resale all **false**; `pgrst.db_schemas = public,
graphql_public, kernel`, `db_pre_request = public.sandbox_pre_request`; 126's L-1 precondition **0**; `venue_api`
absent; none of 127/128/129/130 present. **All equal to §1.**

**Phase A — 124:** applied from the pinned tree (`candidate/2026-09-18-pin @ aabe029`) via
`scripts/release/apply_sandbox_migration.sh 124 apply`; ledger row recorded with the file's exact bytes, md5
`b3811582ef668b614f598daa47f11865` == pinned file; effect `bids_bidder_id_fkey → profiles(id) ON DELETE CASCADE`,
bids 0. **Ledger 131.** ✔
**SBX-2 — 125:** applied the same way; md5 `5c41a89405bed7bb1b1a0c1b7c0d1ca5` == pinned file; the body's md5 on
the sandbox is `6beca316…` (B's expected value). **Ledger 132.** ✔
**SBX-2 — 126: STOPPED.** `psql: 126_ops_console_refund_exactness.sql:173: ERROR: schema "ops" does not exist`.
126 is a single `begin; … commit;` so psql rolled it back: no `ops` schema, no `refund_facts`, no ledger row. **Nothing
partial.** 127/128 **not attempted** — the authorized sequence "125 → 126 → 127 → 128 in order" cannot be
followed, and the owner's rule is to stop on unexpected state.

**The unexpected state, now on record:** the sandbox ledger goes `… 109, 123, 124, 125, <timestamped>` — **it has
never received 110–120** (110 signing-key insert guard, 111 two-person recovery, 112/113 door-manifest headers and
authority, 114 key delivery + manifest signing context, 115–118 ops console, 119 listing block guard, 120 ops refund
semantics), which production has carried since 2026-09-08/09. No prior record noticed it; the Build 16 matrix
never needed them (marketplace paths only) and `123` was applied on top of `109`. Consequences: (i) **126 cannot
apply on this sandbox** without 115–120; (ii) 125 is applied on a sandbox without 112/113 — dormant: scanning is
off, native counts are 0, and `venue.get_door_manifest(uuid, integer)` exists from 086 with the signature 125 calls,
but its payload is 086's, not 113's (B to confirm safe-dormant); (iii) the sandbox has **not** mirrored production's
numeric tip for a week — an evidence limit for every sandbox result since 2026-09-08, marketplace-scoped or not.

**Options for the owner:** (a) bring the sandbox to production parity by applying 110–120 (dark objects only — no
key, no activation; it is the native track and needs its own authorization), then 126 → 130; (b) skip 126 on the
sandbox (it is admin-only and is verified by GitHub CI on a real Supabase stack replaying the full chain with pgTAP
193, by the certified local harness, and by D's review) and continue 127 → 128 (→ 129 → 130 with the O-1 extension)
so the marketplace verifications run; parity for a later window is then a separate decision. **A recommends (b) now
and (a) as its own item.** Nothing further is applied until the owner rules.

**Addendum (B, verified 2026-09-15): 125 on a sandbox without 112/113.** B built a local replay shaped like the
sandbox ledger (pinned tree minus 110–122 and 126–130; `sync_scan_device_manifest` md5 `6beca316…` = the deployed
body; `get_door_manifest` md5 `806b9f01…` = 086's) and ran pgTAP 190 on it. **Safe-dormant, in the closed direction:**
no error; authorization, grants, shape, not-found and 42501 paths pass; but 086's `get_door_manifest` returns no
`open` key, so 125's `coalesce((v_res->>'open')::boolean, false)` is never true and **no device binding is ever
recorded there** — 190 gives 17 ok / 13 not ok, every failure a "bound"/"open:true" expectation. It cannot bind to an
expired episode either. Scanning is off, native counts are 0, no edge calls it. **Consequence:** door/scan-device
acceptance on this sandbox is non-representative until 112/113 exist; marketplace acceptance does not touch it.
If the owner chooses parity (option a), B prepares the 110–120 dark apply package under its own authorization.

**Independent witness read-back (D, read-only, 2026-09-15):** every field above confirmed — ledger 132; numbered
versions above 109 = 123, 124, 125 only; schemas catalog/kernel/notify/venue, no `ops`, no `venue_api`; none of the
127–130 objects; `bids_bidder_id_fkey → profiles(id) ON DELETE CASCADE`, bids 0; sync body md5 `6beca316…`; counts
49/51/33/0, reserved 0, pending 3, push_tokens 1; `kernel.tickets` 0, `signing_key` 0; authenticator
`pgrst.db_schemas = public, graphql_public, kernel`, `db_pre_request = public.sandbox_pre_request`. Venue phase
unaffected, checked: `20260910120000` references none of the 113 objects 110–120 create and they add no columns to
catalog/venue/kernel tables; every venue-side sandbox result to date is likewise on a chain without 110–120.

**Catalog-gap diff (D, 2026-09-15, read-only; local replay of the sandbox's exact 132-version ledger vs the full
chain, ACLs stripped):** no unexplained drift for the sandbox's own ledger (policy sets identical; five functions
differ only by project URL/comments; platform-internal functions only). The gap to the full candidate chain is 379
identity lines: **323 are the `ops` schema (115–120)**; the rest are 110–114 signing recovery, 121 door functions,
**119's `public.guard_listing_seller_not_blocked` + its trigger on `public.listings`**, and 127–130. Two flags:
- **(a) Evidence limit, marketplace-relevant:** the sandbox lacks 119's listing-block insert guard (production has
  had it since 2026-09-08). Any sandbox result that creates a listing as a blocked seller is not representative.
  Build 16's matrix as recorded (D1–D11, T, F) and the candidate DV plan do not exercise that path. 119 is a
  `public`-only migration and could be applied to the sandbox on its own under the owner's authorization, without
  the native-track 110–114.
- **(b) Pre-existing hazard, out of sprint scope:** six migrations hardcode the PRODUCTION project URL inside
  `net.http_post` trigger bodies (`032, 033, 034, 035, 087, 099` → `https://hqycwntpfoztoinemqns.supabase.co/functions/v1/notify-*`).
  The sandbox's copies were rewritten out of band to the sandbox ref — unrecorded drift, benign in effect there —
  but **any fresh replay with a live pg_net (CI's Supabase stack, a new environment, a restored sandbox) points
  those triggers at production's edge functions**; whether a call would land depends on the auth header the
  trigger sends (unverified). Registry note filed; a later migration should read the URL from config.
