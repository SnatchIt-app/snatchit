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

**EXECUTION RECORD, continued — 2026-09-15 (A; owner ruling: path (b), O-1 extended to 129/130).** Owner's words: "Defer 126 on
this sandbox and proceed with 127 → 128 → 129 → 130, plus the two previously authorized payment edges, serialized through A.
This extends O-1 to the reviewed 129/130 versions. … Record explicitly that this sandbox does not validate 126 or its admin
surfaces; retain the full-chain rehearsal as separate evidence."
- **Baseline re-read immediately before (read-only):** ledger 132; versions >109 = 123,124,125; schemas catalog/kernel/notify/
  venue (no `ops`); native flags all false; counts 49/51/33/0, reserved 0, pending 3, push_tokens 1, tickets 0, signing_key 0;
  `pgrst.db_schemas`/`db_pre_request` unchanged; L-1 = 0. **Equal to the record above.**
- **Dependencies verified before apply:** every object 127–130 reference exists on the sandbox with the signature the file
  expects (`release_reservation(uuid,uuid)`, `request_is_service_role()`, `check_rate_limit(uuid,text,int,int)`,
  `notify.enqueue`, `notify.identity_channel_state`, `notify.record_delivery_result`, `notify.register_push_token(text,text,
  text,text)` = the signature 128 revokes, `notify.revoke_push_token(text)`); `guard_push_token_secret_hash` is created by 128
  itself. All eight objects 127–130 create were absent. Source: tag `candidate/2026-09-18-pin` = `aabe029` (file md5s 127
  `764d3392…`, 128 `6757afcc…`, 129 `778d4249…`, 130 `b981cb52…`); D's independent pre-apply check confirmed the same md5s
  and a clean local apply on a replay shaped like this ledger (194/195/196/197 all pass there).
- **Order guard:** `apply_sandbox_migration.sh` gained `ORDER_GUARD_SKIP` (converge `838bceb`) so the deferral is declared,
  printed on every run ("DEFERRED by owner ruling … 126") and never implied.
- **Applied, in order, each `preflight → apply → verify` (ledger row = the pinned file's exact bytes):**
  127 md5 `b7b76ba853b367e1bb0540f9fa12b0bb` ✔ · 128 `a1b4c0946d2cb26ea3a66de82b00c338` ✔ · 129 `11b27f36f07e9e856ad8c867216b8b5c` ✔ ·
  130 `91f7720de0680ce4ee31e17f149e4811` ✔ (md5 of file minus trailing newline, the script's convention). **Ledger 136.**
- **Read-back after:** versions >109 = 123,124,125,127,128,129,130; all eight objects present; `payments.supersede_claim_token/
  supersede_claimed_at`; `push_token_rebind_epoch` 1 row; `push_tokens` grants anon/authenticated `DELETE,INSERT` only,
  SELECT column-scoped excluding `device_secret_hash`, UPDATE column-scoped to platform/device_name/last_used/is_active (matches
  128 and `expected_grants.txt`); flags false; counts unchanged; L-1 = 0. Public census **31 / 97 / 37 / 34** vs CI's
  31/96/37/35 at the pin: −1 function and −1 trigger are 119's absent listing-block guard; `+sandbox_pre_request` is the
  sandbox's own pre-request hook; the other is `sandbox_gucs()`, the second sandbox-only helper (D's witness read-back: the sandbox differs from a local sandbox-shape replay, 31/95/37/34, by exactly those two functions). D also confirms 0 function bodies and 0 cron commands on the sandbox contain the production ref, and that the sandbox lacks the `enforce-transfer-expiry` cron altogether (pre-existing out-of-band drift).
- **Edges (row 9–10):** `supabase functions deploy <fn> --project-ref ofaidukbieeekqaboscm --no-verify-jwt` from the pinned
  worktree (`git rev-parse HEAD` = `aabe029`): `stripe-webhook` v3 → **v4** (ezbr `897283ef…`), `create-payment-intent` v3 →
  **v4** (ezbr `4f0e9142…`), both `verify_jwt=false` as every sandbox edge was before (recorded evidence limit, unchanged).
  Parity: `supabase functions download` into a scratch directory, `cmp` against the tag — `stripe-webhook/index.ts`,
  `create-payment-intent/index.ts`, `_shared/stripe.ts`, `_shared/sentry.ts`, `_shared/money.ts` **byte-identical**.
- **Not validated on this sandbox, by ruling:** 126 and every admin/ops surface it serves (no `ops` schema here). Evidence for
  126 remains: GitHub CI full-chain replay + pgTAP 193 on the real stack at the pin, the certified local harness, D's review.
  Also unrepresentative here, as recorded above: 119's guard, 121, door/scan-device paths.
- **Still open in this window:** DV-611 L/S/R/C and the device rows (C, on the pinned build); DV-L1/L2 read-backs during those
  rows (A); cleanup (row 12); venue phase last (D, MFA step announced by A). Nothing production; nothing native.

**Handset session 1 (build 17, C's plan; A read-backs) — 2026-09-16 01:2x Z, read-only unless stated.**
- **Block 0 step 2 (compiled-env evidence):** `auth.sessions` for `sandbox-buyer@snatchit.test` (user `919d511e…`): exactly one
  session `76ff3c02…`, user_agent `SnatchIt/17 CFNetwork/3860.700.1 Darwin/25.6.0`, `refreshed_at 01:19:05Z` — build 17
  talks to the sandbox GoTrue (URL + anon key). **The session was created 2026-09-14 04:41:18Z** (= `last_sign_in_at`): the
  owner's sign-in on the fresh install was a Keychain-restored session, not a new login. Recorded as an evidence note; the
  first `create-payment-intent` call in Block 2 proves the functions URL.
- **Block 0 step 3 / DV-611L baseline: NOT MET at 01:21Z** — `push_tokens` has **no row** for the buyer (the sandbox holds one
  push token in total, from 09-08, another user); `notify.identity_channel_state` has no row for the buyer. No registration
  has reached the server. Causes to eliminate in order: notifications permission not granted on the handset; no cold-launch
  registration on a restored session; a client-side failure. Owner asked to confirm the permission and force-quit + relaunch;
  A re-reads on C's trigger. Rows 1–14 may proceed (no notification dependency); rows 15–18 wait for a row.
- **Device-session writes by the DV buyer (documented plan rows, logged, cleaned up by A at session end):** one `reports` row
  (DV-203, reason "Misleading information") and one listing with quantity 2 (DV-609). Baseline before them: listings by the
  buyer and reports by the buyer counted at 01:2x Z (values in the next line).
- **DV-106 fixture (read-only):** staged listings "Phone P1" `c343406e…`, "Device D7" `b1c3c478…`, "Device D8" `58cc00e3…`
  are active, owned by the DV seller, with `cover_image_path = fixtures/<name>.jpg` and no `storage.objects` row — the image
  request fails; the branded fallback is the PASS state.
- **DV-605:** a listing id that does not exist on the sandbox is supplied by A (verified absent before hand-off).
- **DV-611L re-read after the owner confirmed Allow Notifications ON and force-quit/relaunched (≈01:26Z): still no row.
  ROOT CAUSE (read-only, sandbox logs):** `edge_logs` 01:19:06.164Z `POST /rest/v1/rpc/register_push_token` from
  `SnatchIt/17` → **403**; `postgres_logs` 01:19:06.666Z `insufficient_privilege: token is bound to another account` (128
  rule 4). The cold launch at 01:26 made no register call (client terminal state; no retry). The sandbox's only
  `push_tokens` row (`140fcb44…`, created 2026-09-08 04:08Z, last_used 09-10, **active**, hash NULL, ios) belongs to user
  `1fcd0c69…` (a staff account used for Build 16 testing on this same handset); same install ⇒ same Expo push token ⇒ the
  buyer's registration meets an active legacy row on another account; rule 5 needs `signed_out` + inactive, which Build 16
  never wrote. **Designed terminal state per contract v2; the production scenario for every Build 16 user who switches
  accounts on one device.** Nothing mutated by A. Recovery paths offered to the owner: (B) the staff account signs in
  (→ `refreshed`, hash planted on the real device) and signs out (129 → `signed_out`) on the handset, then the buyer →
  rule 3 `rebound`; (A) support `unbind_push_token` (service_role) recorded before/after. **Candidate finding F-611-1 (C/D to
  dispose):** the client does not retry after entering the terminal state even once the cause is gone, and the owner saw no
  remedy banner at Block 0 step 3.
- **Owner, ≈01:33Z (screenshot of Settings › Notifications on build 17):** green "Notifications are enabled"; yellow
  "Notifications aren't set up for this account on this device yet. The account that used this device before needs to sign
  out here first." — the terminal `bound_to_other` state is visible on-device. Registration remains blocked. Kept in the
  findings: the initial 403, the no-retry terminal behaviour, and the recovery wording (says "sign out here first" where the
  remedy is "sign in and then sign out on this device"; the 131 branch's S-13 copy already says so). **Owner chose Path B**
  (staff account signs in and out on the handset; no server mutation). Steps and read-backs recorded below as they happen.
- **Path B executed by the owner, one step at a time, A read after each (A's reads read-only; the app's own writes are the recovery):**
  S1 buyer sign-out → buyer sessions 1 → 0, staff row unchanged. (Earlier, 01:33:37Z: the buyer's own sign-out issued
  `revoke_push_token` 200 then `logout` 204, signed back in 01:33:49Z and was refused 403 again at 01:33:56Z — sign-out clears
  the client's terminal state, the retry repeats the refusal while the legacy row is active.)
  S2 staff (`contact@snatchitapp.com`) sign-in → row `140fcb44…` user unchanged, active, `last_used` 09-10 17:33:37Z →
  09-16 01:40:48Z, **hash now present** (prefix `4b8628e7`) = `refreshed`, proof planted on the real device by rule 2.
  S3 staff sign-out → inactive, `revoked_at` 01:41:51Z, `revoked_reason = signed_out`, hash retained; staff sessions 0
  (global sign-out).
  S4 buyer sign-in → **user_id → `919d511e…` (buyer)**, active, `last_used` 01:42:41Z, revocation cleared, same hash =
  **`rebound`** (rule 3). Buyer session created 01:42:30Z. **Registration recovered through normal app-driven sandbox writes, without a manual support override (owner's wording); the
  designed legacy hand-off works end to end.** Baseline for DV-611C / DV-611S = this row. DV-611L recorded NOT APPLICABLE as written (the install carried
  Build 16 residue); the initial 403 recorded as F7 working. Findings kept: F-611-1 (no automatic retry while terminal;
  recovery copy says "sign out here first" where the remedy is "sign in and then sign out on this device").
- **Block 1 rows 1–8 (owner, ≈02:0x Z):** "Listing opens" (DV-101) through "Unsaved edits" (DV-208b) PASS; unsaved-edit protection
  works; exact labels/timings not captured for every row (recorded as reported, nothing invented). DV-609 done in that stretch.
- **F-FE-1 (owner, screenshot 22:01 EDT, seller form on build 17):** while typing, the "List Ticket" action bar sits far above
  the keyboard leaving a large blank gap; the "SELL YOUR TICKET" heading crowds the SANDBOX banner. Owner: C fixes in the next
  candidate's frontend workstream (reproduce; inspect keyboard avoidance, safe-area spacing, sticky action bar); acceptance
  criteria in the sprint plan C-5 row and C's backlog. **Build 17 preserved as the tested artifact; no build cut from this.**
- **Owner, 2026-09-16 (later):** row 3 CLOSED (D's independent read-back: same row, buyer's, proof present, device_name iPhone);
  rows 1–8 owner-reported PASS (seller keyboard-layout defect open separately); **row 9 (Reduced Motion) PASS; row 11 (large
  accessibility text) PASS**; no other row inferred. Owner decision: **b2, build shape (i)** — one combined additional sandbox
  preview build (stack 131–134 + logout/session client + b2 + seller-form fix); isolated implementation, local testing, review,
  integration authorized now; the build after the combined commit passes reviews and CI; **any sandbox migration or edge
  deployment needs an exact consolidated application package approved first; no production change authorized.**
- **Owner / C, later on 2026-09-16:** row 14 (offline states) PASS with one wording difference recorded for review — Tickets shows
  "Something went wrong / We couldn't load this right now" where Home/Bids/Profile show "You're offline" (**F-OFF-1, LOW, next
  candidate, not now**); row 10 (VoiceOver) UNTESTED at the owner's request (**A11Y-1 follow-up**). Next: row 13, row 14's
  filtered/empty checks, then rows 15–18 on C's triggers.
- **Owner / C / A, 2026-09-16 04:00–04:24Z — rows 14, 15, 16.** Row 14 filtered/empty checks PASS (owner via C; no-match,
  genuinely-empty, offline with F-OFF-1 kept). **Row 15 (DV-611C, relaunch while signed in) PASS on the second attempt, first
  attempt UNEXPLAINED-then-settled:** A's capture before the owner acted, 04:10:50Z: row `140fcb44…` active, last_used 04:00:03Z
  (row-14 residue), proof `4b8628e7`, one session `25716517…` (01:42:30Z). Owner relaunched ≈04:12Z → reads 04:14:53Z and
  04:15:32Z unchanged. Owner relaunched again ≈04:16Z → read 04:19:28Z: last_used **04:16:34Z**, same user, same proof, no new
  row = the contract's `refreshed`. Sandbox API log (edge_logs, UA SnatchIt/17, 04:10–04:18Z, one query with the known call as
  positive control): 04:12:31–36Z `auth/v1/user`, `user_blocks`, `rpc/get_my_profile` ×2, `listings` ×2, all 200, **no
  `register_push_token`**; 04:16:33–35Z the same sequence plus `rpc/register_push_token` **200 at 04:16:34.448Z**. So the 04:12
  launch was online and authenticated and never sent the register RPC: the miss is on the client between userId-known and
  RPC-sent (C: `obtainToken()` / storage read, caught to console only, nothing persisted) — **F-611C-1** (C): a failed or hanging
  token fetch is indistinguishable on the device from a registration; C prepares a fix (timeout-bounded fetch, persisted
  pre-register failure, Settings visibility with Retry) on `frontend/push-token-fetch-visibility` off `9bef640` for the owner's
  decision; if included it is a **new build-source tag** after CI and D's gate, `9bef640` stays the applied-bytes pin. **Row 16
  (sign out online) server half PASS** at 04:23:49Z: `140fcb44…` active=false, revoked_at 04:21:09Z, reason `signed_out`, proof
  kept, buyer sessions 0 (129 wrapper path); client half owner-reported (no message on the login screen). Next: row 18 on C's
  trigger; row 17 (A deletes the buyer's session server-side, documented) only on the owner's "ready" with a live session.
  **Sandbox push delivery is impossible today** (empty Vault: no `service_role_key`; `net._http_response` 0 rows in 24 h): any
  row that needs a push to arrive is on hold pending the owner's package §2a decision, deferred not attempted.

## 11. EXECUTION RECORD — B2 application window, 2026-09-16 04:35–04:56Z (A executes, D witnesses; sandbox `ofaidukbieeekqaboscm` only)

**Authorization:** owner rulings 1 and 2 of 2026-09-16 (package `SANDBOX_APPLICATION_PACKAGE_B2.md` §9); execution commit tag
`candidate/2026-09-18-pin-b2` = `9bef640` checked out detached at `/tmp/wt-pin` (0 dirty files); order as corrected and
confirmed by the owner: Vault `project_url` → 131 → 132 → 133 → 135 → 20260916000000; option (b): no `service_role_key`;
D's final script review `685340f`. Every apply: `apply_sandbox_migration.sh <v> preflight → apply → verify /tmp/wt-pin` with
`ORDER_GUARD_SKIP=126`; D's V0 immediately before each apply and an independent read after; A applied nothing while a read
of D's was unexplained. **Nothing production; nothing native; no build cut.**

**Ledger md5 method, stated exactly (D):** the apply script records the ledger row's `statements` as one element holding the
pinned file's bytes with trailing newlines stripped (`printf '%s' "$(cat file)"`), and `verify` compares the ledger's
`md5(array_to_string(statements,''))` to md5 of the file minus trailing newlines. It is a statements-to-file-bytes comparison,
not a raw-file md5 (raw file md5s differ: 131 `1c2fade4…`, 132 `1d588749…`). D reproduced every value from the pin tree;
20260916000000's value was predicted by D before the apply.

| Step | Time (Z) | Result | Read-backs |
|---|---|---|---|
| D V0 | 04:35:37 | baseline = A's 04:34:08 recapture and package §10 table; D's correction: `net._http_response` held 2 rows, both 401, both 2026-09-07 (the old `*/2` sweep before it was removed), newest `2026-09-07T16:06:00.257881Z` | ledger 136; census 31\|97\|37\|34; vault (none); prod-host refs 0/0; `auth.sessions` no triggers |
| W1 Vault `project_url` | 04:37:06 | `sandbox_vault_ceremony.sh url` after the server asserted the sandbox identity (ledger 130..141, no `ops`, `sandbox_gucs`); `vault.create_secret` id `2e3e8083…` | A `verify-url`: rows=1, sandbox host, no production ref; D INV1 exactly one name, INV3 host equal; ledger/census unchanged |
| W2 131 | 04:39 | ledger 137, md5 `e07ac078f151fc68589286d0acfb16f5` | `push_tokens.session_id`; `trg_push_bindings_on_sessions_gone` the only non-internal trigger on `auth.sessions` (tgtype 8, after-delete statement); `revoke_all_push_bindings`, `kernel.invalidate_push_bindings_for`, `kernel.push_session_predates_epoch`; push_tokens guards `_session_row`/`_session_stmt`; census 31\|100\|37\|36; zero drift across 16 cron runs (D attributed) |
| W3 132 | 04:41 | ledger 138, md5 `ecdd91761e3849ea73190f174cf2681c` | `checkout_group_claim` (empty, service_role-only grants), `claim_checkout_group`, `record_checkout_attempt`, `release_checkout_group`; census 32\|103\|37\|36 |
| pre-133 capture | 04:44:23 | sandbox-specific 133 rollback: scratchpad `sbx_133_rollback_capture_20260916T044423Z.sql`, 377 lines, md5 `8431acc5939a401b5883f2e855ae586e`, 0 production refs, 0 JWT-shaped literals; `pg_get_functiondef`+comment of `kernel.check_signing_key_invariants`, `public.notify_bid_placed`, `notify_moderation_event`, `notify_outbid` (superset), `notify_transfer_event`; unschedule+schedule text of `crm-export-build-tick`, `crm-export-purge-tick`, `payout-execute-tick`, `refund-execute-tick`; `enforce-transfer-expiry` rolls back by `cron.unschedule` | D derived 133's rewrite set independently from the pinned file (4 routines, 5 crons): capture complete |
| W4 133 | 04:47:05 | ledger 139, md5 `c08f8295a60ebd5e856194aea1106c74`; §4 proof passed | routines and cron commands naming ANY `*.supabase.co` host: 0 and 0 (the SBX-1/2 sandbox-host literals are gone), production 0/0; five crons re-registered active in the Vault form (guards: sweep url-only; crm ×2 worker-secret+url; refund/payout flag+url); cron jobs 22; census unchanged |
| first tick | 04:48:00 | `cron.job_run_details` succeeded (queuing SQL); `net._http_response` id 3, status **401**, error_msg null, timed_out false, content 24 bytes | D's written prediction held: exactly one job posts, every 2 min, refused; the NULL bearer took the 401 branch, not a queue-time error |
| W5 135 | 04:49:56 | ledger 140, md5 `28e01d25032218656e980c2900904743` | `notify.push_token_challenges` (0 rows, **no table grants** to anon/authenticated/service_role — 157 B9 now holds in an applied database), `notify.issue_push_token_challenge` (not executable by authenticated), `public.request_push_token_challenge`, `public.confirm_push_token_challenge` (authenticated yes, anon no), `notify.get_push_token_challenge` (service_role), `notify.record_push_token_challenge_delivery`; `trg_guard_push_token_client_delete`; `security_device_rebound` `{}`/`{}`/in_app template only; notify tables 8; census 32\|106\|37\|37 |
| W6 20260916000000 | 04:53:14 | ledger 141, md5 `b1fda89070efa7a9ba24f5aee4492064` (= D's prediction) | `get_unsettled_payments` carries the `processing_stale` arm; census unchanged (final) |
| Edges | 04:54:15 / 04:55:16 / 04:55:21 | `create-payment-intent` (now v5, ezbr `dd857f97…`), `send-push` (v4, `f8e4e894…`), `enforce-transfer-expiry` (v4, `c997abb2…`) deployed from `/tmp/wt-pin` with `--project-ref ofaidukbieeekqaboscm --no-verify-jwt`; `stripe-webhook` untouched (v4, `897283ef…`, byte-identical to both pins) | parity = every file of each downloaded bundle byte-identical to the pin (index.ts + the `_shared` files it imports; `_shared` unchanged between the pins and identical to the pre-deploy download). Pre-deploy baseline 04:51Z: all four deployed `index.ts` equalled `candidate/2026-09-18-pin` |
| Close | 04:56:09 | see below | D's independent closing read follows |

**Closing state (A, 04:56:09Z):** ledger **141** (131, 132, 133, 135, 20260916000000); census **32 | 106 | 37 | 37** = the pin's
declared 32|105|37|38 adjusted by the named sandbox deltas (+`sandbox_gucs`, +`sandbox_pre_request`, −119's guard function and
trigger; D named all four); notify tables 8; flags all false; counts listings 49, payments 51 (3 pending), transfers 33,
push_tokens 1, `kernel.tickets` 0, `signing_key` 0, `checkout_group_claim` 0, challenges 0 — **zero business drift** from V0;
L-1 0; Vault **`project_url` only**; host literals 0/0; production refs 0/0; cron jobs 22; queue 0; **responses after V0: 5,
all 401, none 2xx**, newest `2026-09-16T04:56:00.240651Z`; sweep cron runs 5, all "succeeded" (queuing only); buyer row
`140fcb44…` untouched (inactive, `signed_out`, `session_id` null, proof kept).

**Evidence captured as values (D's finding: `net._http_response` is a 6-hour cache, `pg_net.ttl`; the two 2026-09-07 rows were
purged by the worker when the 04:48 request woke it; the refused-tick evidence self-deletes):** scratchpad
`sbx_b2_window_responses.txt` — id 3 `04:48:00.249691Z` 401; then the 04:50, 04:52, 04:54, 04:56 ticks, each 401, error_msg
null, timed_out false, content 24 bytes. `cron.job_run_details` records only that the queuing SQL ran and cannot distinguish a
refused post from a successful one; only the captured response rows prove "nothing succeeded".

**Deploy posture (D's ask; undeclared state, no `supabase/config.toml`):** read today as values from `functions list`: all nine
sandbox functions `verify_jwt=false`, including the five untouched ones; the SBX-2 record (§10, "verify_jwt=false as every
sandbox edge was before") is the cited pre-state for the three redeployed here — **evidence limit, recorded as a near-miss:
the pre-deploy `verify_jwt` of the three redeployed functions was inferred, not read** (from the SBX-2 record and the five
untouched functions' posture); the post-deploy read is real, all nine false; security consequence nil because all three
authenticate their own callers (D verified in source). Carried to the production preflight as its own check: production's
per-function `verify_jwt` read and matched explicitly before any deploy, since source parity does not cover deploy flags.

**D's independent closing read, 04:57:13Z — PASS** (witness record `docs/review/d-release-sprint/B2_WINDOW_WITNESS_20260916.md`
on `review/d-release-sprint`): ledger 141 holding exactly 131, 132, 133, 135, 20260916000000; census 32|106|37|37; INV1
`project_url` alone at every checkpoint; INV3 sandbox host; INV4 zero production references and zero `*.supabase.co` literals;
queue 0; five ticks after V0, all 401, zero 2xx, at 04:48, 04:50, 04:52, 04:54, 04:56 — one job, on its two-minute cadence,
no gaps and no extras; zero drift on every business count; both new tables empty; the handset row untouched with the proof
kept. **D's boundary statement, carried verbatim:** "This window establishes that the five migrations apply cleanly in
production order, that the resulting catalog matches the pin, that the grant matrix and the tombstone guard are live, that no
production host is reachable from this database, and that no outbound request can authenticate. It establishes nothing about
whether b2 works. Under option (b) the challenge path cannot be exercised: send-push refuses every dispatch by construction,
no notification can reach a device, and the entire device matrix — challenge delivery, echo, rebind, the two-accounts case,
plant-then-claim, recovery without support — remains deferred, not attempted and not passed. 'Sandbox application passed'
must never be read as 'b2 works on a handset'."

**Disclosed false alarms (A's parity script, not the deployment):** (1) after `create-payment-intent`, a regex over `index.ts`
matched a *comment* naming `_shared/payouts.ts`, a file that function does not import, so `cmp` on a missing file reported
DIFFER; (2) after `enforce-transfer-expiry`, the "direct imports == bundled set" clause flagged `_shared/payout-policy.ts`,
which *is* a direct import whose `from` clause sits on its own line (`index.ts:77`) and which my single-line pattern missed.
Every byte comparison passed on its first run; the sequence stopped at each alarm until explained.

**What this window proves and does not prove (verbatim from D, for anyone reading "passed" later):** it proves the schema,
verbs, grants, rollback capture and the migration chain on the sandbox, and that with only `project_url` in the Vault nothing
from this database can authenticate to any edge. **Edge parity is a source comparison, not behavioural**: `send-push` cannot
be exercised end to end under option (b), and "send-push verified on the sandbox" is not a claim this record makes. **b2
device verification is deferred**; DV-611/611S and every push-dependent device row are deferred, not attempted; nothing
reached the owner's handset. `enforce-transfer-expiry` does not run from cron for the life of this sandbox state (refused
every tick); DV-134 needs a direct invocation with an existing sandbox bearer or is deferred.

**Rollback, if the owner ever orders it:** reverse order 20260916000000 → 135 → 133 → 132 → 131 from `/tmp/wt-pin`'s
`supabase/rollbacks/`, each followed by deleting its ledger row — **except 133 on this sandbox, whose rollback is the capture
above** (the repo rollback restores production's pre-133 bodies naming the production host); edges by redeploying
`create-payment-intent`, `enforce-transfer-expiry`, `send-push` from `candidate/2026-09-18-pin` (`aabe029`); Vault by
`delete from vault.secrets where name = 'project_url'`. Not automatic.

**Still open after the server phase:** D's independent closing read; the one combined build (C, from the tag, after the owner
says so — the pre-authorized action, now that application and edge verification have passed); the device matrix on that build
with the push rows deferred; handset row 17 on Build 17 (now a real A-131-K2 test: expected `session_ended`, proof kept, epoch
moved; client expiry notice) after C gives the owner the exact steps; row 18 deferred to the combined build (a v2 client
rejects `contract_version` 3); no fixtures were staged in this window, so there is nothing to clean up; the closing census
above is the record.

## 12. Handset session 1, row 17 (DV-607a) on Build 17 — server-side session invalidation, 2026-09-17 02:34–02:39Z

**Authorization:** owner 2026-09-16 ("C may proceed to row 17 only after giving me the exact handset instruction; A performs
the documented session invalidation and read-back") and the owner's "row 17 ready" at 02:34Z (22:34 Eastern, 2026-09-16), Build
17 signed in as `sandbox-buyer@snatchit.test` and backgrounded. Post-131 sandbox, so the row tests the real A-131-K2 path.

**Before-reads (A 02:35:35Z; D 02:37:01Z, identical):** buyer `919d511e…` had exactly one session, `d947bef4-2613-4a53-8633-
fc16e313b4e0` (created 2026-09-16 04:32:52.904518Z, `not_after` null, SnatchIt/17); token row `140fcb44…` active, reason null,
`session_id` = that session, proof `4b8628e7…`, `last_used` 02:34:04.157162Z (this launch's register call, i.e. the client
registered normally on the relaunch); `kernel.identity_ext` **one existing row** with `push_binding_epoch` null (D's correction
to A's "no row"); `trg_push_bindings_on_sessions_gone` present. **Branch decided from the read, not the abstract:** one live
session → deleting it leaves none → branch (1) `invalidate_push_bindings_for(buyer, 'signed_out_everywhere')`; the
`session_ended` UPDATE (branch 2, proof kept, no epoch move) matches nothing because it is guarded `and t.is_active`. A's
earlier restatement to C had fused the two branches ("session_ended, proof kept, epoch moved"); D caught it, A verified from
the pinned 131, and C's owner instruction was corrected before the run.

**Write:** `delete from auth.sessions … where left(id::text,8)='d947bef4'` by the buyer, inside a transaction whose guard
asserts exactly one buyer session with that prefix. **First attempt 02:38:05Z aborted on the guard itself** (`min()` over a
uuid is not defined), before the delete; the read-back proved nothing changed. Retry 02:38:29Z: transaction `now()`
02:38:30.049923Z, one row deleted, committed.

**Read-backs (A 02:38:30Z; D 02:39:25Z, every value identical): PASS, branch (1).** Buyer sessions 0 live / 0 total. Row
`140fcb44…`: `is_active=false`, `revoked_reason='signed_out_everywhere'`, `revoked_at` 02:38:30.049923Z (= txn now),
**`device_secret_hash` NULL** (the proof-clearing that separates the branches), `last_used` unchanged, `session_id` still
`d947bef4…` — **a dangling reference by design**: the verb leaves it, the session no longer exists; harmless (row inactive, epoch
bars re-registration) but a later join to `auth.sessions` finds nothing and must not be read as corruption. `identity_ext`: the
existing row's `push_binding_epoch` null → **02:38:32.452494Z**. **O-3 property holds:** epoch ≥ `revoked_at` and epoch > the
deleted session's `created_at`, so every pre-existing session is barred from re-registering until a fresh sign-in. Exactly one
token row revoked; no other binding touched; counts 49/51/33/1, challenges 0, vault `project_url` only, ledger 141, census
32|106|37|37.

**The 2.4 s epoch offset is deliberate (pinned 131):** `v_epoch := greatest(coalesce(p_epoch, '-infinity'), clock_timestamp())
+ interval '2 seconds'` — the epoch is stamped two seconds into the future so a session created microseconds after the
invalidation commits still predates it and fails closed. **Known property, recorded here rather than met on a handset:** a
legitimate fresh sign-in landing inside that two-second window gets a session whose `created_at` precedes the epoch, and since
`created_at` never changes that session can never register a push token; the remedy is signing in again (the same remedy 131
already imposes after a credential change). Report shape if it ever surfaces: "I changed my password and notifications
stopped."

**Post-window monitoring, 2026-09-17 03:08Z (A; D concurs on the classification, corrects the reasoning):** `net._http_response`
holds 180 rows over its 6-hour TTL = one job at `*/2`, 30/h; 179 × 401 and one row (id 496, 2026-09-16 21:14:00.231Z) with
`status_code` null, `timed_out` true, "Timeout of 5000 ms reached" after DNS 3.9 ms and TCP/SSL 29.6 ms — the request reached
the edge and pg_net gave up at 5 s, so the row itself says nothing about what the edge did. **It is benign because of the edge's
own ordering, not because it is not a 2xx:** `enforce-transfer-expiry` reads the bearer at `index.ts:151`, returns 401 at
`:173`, and makes its first database call at `:222` — the auth gate strictly precedes every side effect, so an empty-bearer
request that outlived pg_net's wait still did nothing. Recorded in those words so a future timeout on an edge with a later
auth gate is not waved through on "not a 2xx". Cadence unbroken.

**Client half (owner via C): PASS.** On reopening, the owner saw exactly "Your session expired. Sign in to pick up where you
left off." on the login screen; no silent failure (CFT-607 path). C recorded row 17 PASS at `0bf7558+` (backlog and plan).
**Row 17 PASS on both halves; handset session 1 on Build 17 is otherwise complete.** The owner has not signed in again yet;
when they do, the next buyer sign-in on this device registers fresh with no proof (`registered`) and plants a new one — A reads
the row on C's time. Row 18 stays deferred to the combined build (a v2 client rejects `contract_version` 3 now that 135 is on the
sandbox). Branch (2), the K-2 "this device only" case, remains **untested outside D's harness**: it needs two live sandbox
sessions for one user, i.e. Build 17 on a second iPhone; proposed for the combined-build session if the owner has one.

## 13. Handset session 2 on Build 18 (tag `candidate/2026-09-18-build-b2` = `aad5f75`) — block S2-1, 2026-09-17 03:05–03:55Z

**Build 18:** EAS `dcbf20e0-76dd-4b18-a48a-20c203ba0175`, cut by C from the tag in a clean worktree; installed by the owner;
C guides, A reads back, D witnesses. Push delivery stays deferred (option (b)); every read is read-only.

- **First sign-in (03:05Z):** session `ff1f1494…` created after row 17's epoch; row `140fcb44…` re-activated on it, `last_used`
  03:05:08Z, proof re-planted with the same hash `4b8628e7` — **conformant** (V2 §41/§62 carried into V3: the device secret is
  generated once per install; rotation does not exist).
- **S2-1 step 1, buyer sign-out → sign-in (03:32Z): PASS (server half).** API log: `revoke_push_token` 200 then `auth/logout`
  204 (03:32:30Z); `auth/token` 200 03:32:42Z; then within two seconds `auth/user`, `bids`, `get_my_profile`,
  `register_push_token` 200, `user_blocks`, `transfers`, `listings` — data flowed with no relaunch: the sign-in hang (8dc4cec)
  is not reproduced. Row re-registered on the new session `f0118de8…`, reason cleared, `last_used` 03:32:44Z, same proof.
  **Observation F-AUTH-2 (C):** `get_my_profile` ×2 and `listings` ×2 per screen, `user_blocks` ×3 — the doubled-fetch pattern
  first seen on Build 17 at 04:12Z; C sizing the double-mount root cause.
- **S2-1 step 2, seller sign-out/sign-in on the same handset (03:49–03:52Z): PASS on what the step tests (Home and Profile
  load); first live exercise of the v3 challenge path on a handset, DEFERRED as designed.** Buyer sign-out 03:49:34Z:
  `revoke_push_token` 200 then `logout` 204; the buyer's only live session was deleted, so 131's global branch overwrote 129's
  `signed_out` with **`signed_out_everywhere`** and cleared the proof — per design (as row 17); on a single-session account
  every "sign out this device" is a global invalidation, recorded so the reason string is not read as a 129 defect. Seller
  session `bfa87767…` 03:50:51Z; `register_push_token` 200 at 03:50:52Z → **`challenge_required`**: challenge `ae6b47d4…` on token
  `140fcb44…`, requesting user = the seller, mode silent, re-issued at least once (`prev_nonce_hash` set), `dispatched_at`
  03:51:42Z, attempts 0, not confirmed, expires 03:56:42Z; `push_tokens` still one row, the buyer's, inactive. `send-push`
  dispatches refused: `net._http_response` 401 at 03:50:52, 03:50:57, 03:51:42Z — no push could arrive (no key), so the
  challenge outcome is **deferred, not failed**. **Client behaviour for C (candidate finding F-611C-2):** the app called
  `register_push_token` four times — 03:50:52, 03:50:57, 03:51:41 (all 200) and 03:52:07 (**400**: the verb's per-token limit,
  3 issues per 10 min, refused the 4th) — and never called `request_push_token_challenge`; i.e. on `challenge_required` Build 18
  re-registers on a retry cadence instead of waiting for the silent push and requesting the visible code at 60 s, and burns
  the limit in 75 s. F-AUTH-2 reappears on the seller's Home and Profile loads. Owner opened Settings › Notifications at
  03:54:33Z. No write by A.
- **Owner's handset half of S2-1 step 2 (reported to A 2026-09-17, for C's record):** "Settings → Notifications showed no
  banner"; the owner confirms opening that screen around 11:54 PM Eastern — the 03:54:33Z open in the API log. Consistent
  with RC2 as C traced it (the "too many challenge requests" refusal fell through to the never-retry branch with no remedy
  copy, so nothing rendered) — recorded as the owner's observation; C matches it to the row. Not a PASS.
- **DV-ST2 (S2-5) — temporary sandbox permission test, AUTHORIZED by the owner 2026-09-17** ("only in a coordinated window on C's trigger, with D witnessing. Before changing anything: capture the exact existing grants; prepare a restoration mechanism that does not depend on the test succeeding; pause overlapping sandbox tests. Restore and verify privileges immediately after the observation, including if the test fails or is interrupted. This authorizes only the named temporary restriction and restoration, not broader permission changes.") Screen: Bids tab, whose read is `from('bids').select(...)` through RLS (C, from source at bf8b9ba); the Tickets tab is unsuitable because it routes 42501 to the login screen. Prepared by A (scratchpad `sbx_st2_stage.sh`, md5 `00e9c6792c800c58a46ba5beeebd4809`; modes capture/plan/revoke/restore/verify/watchdog-start; refuses any non-sandbox ref). **Capture 04:37:18Z (md5 `536505054bd9a3fe2148b1e6401d315f`):** `public.bids` relacl `{postgres=arwdDxtm/postgres, anon=arwdm/postgres, authenticated=arwdm/postgres, service_role=arwdDxtm/postgres}`; authenticated holds select/insert/update/delete, grantor = owner = connecting role = postgres (so the restored ACL text is identical); column-level ACLs 0; RLS on, 3 policies. **Restriction (one statement):** `revoke select on table public.bids from authenticated;` **Restoration (generated from the capture, md5 `0836055427283986b2eb4d62373aa76f`, prepared BEFORE the revoke):** `grant select on table public.bids to authenticated;` — executed by A immediately after the observation, and independently by a local watchdog at T+240 s if the revoked-flag still exists (so restoration does not depend on the test, on C, or on A's next command). **Verification after:** `has_table_privilege('authenticated','public.bids','select')` = true and relacl text equal to the capture, read back and recorded here with times. **Sequence:** C "ST2a: owner force-quit at <time>, revoke now" → A capture (re-run) + watchdog-start + revoke → "revoked <time>" → owner relaunches to Bids → C reports the copy → C "restore now" → A restore + verify → "restored <time>" → owner taps Retry → C reports. Overlapping sandbox tests paused for the window (D's kit idle; the handset on the Bids tab only). **ST2b (cached rows stay on pull-to-refresh) has no fixture:** `public.bids` holds 0 rows (read 04:27Z); carried UNTESTED until the cached-bids fixture proposal is approved and executed (preparation only, per the owner).
- **DV-S1 (seller create form with the keyboard) on Build 18 — owner's observations via C, recorded on the owner's instruction 2026-09-17:** step 1 PASS (seller; no excessive gap above the List ticket bar, Event name visible, heading clears the SANDBOX badge; time not captured); step 2 PASS at 01:10 AM Eastern (focused field stays visible while scrolling, typed text intact, reopened layout matches, List ticket bar clears the bottom dock); step 3a PASS — the long event name uses single-line horizontal scrolling and is not entirely visible at once (the owner reported the observation twice: 01:17 AM Eastern in the message to A, 01:14 AM Eastern in the later resent report to C; C's record uses 01:14 and notes both; D's note: single-line horizontal scrolling is normal iOS behaviour and the criterion is the focused field staying visible, so the pass stands — "a seller typing a long name cannot see all of it" goes to C's backlog as a product question, not a device defect). **Still pending:** step 3b (largest accessibility text) and the remaining tab-heading checks (S2-4). Row not complete. **The new security-notice banner (da1d11d) is NOT in Build 18** — it entered the stack only at e9b52ce — so it needs its own later device check on the next candidate, not a DV-S1 observation. C remains the single handset guide.
- **DV-S1 complete (C's record 915303c/76b368c):** step 3b PASS 01:18 EDT at the largest text. **S2-4 PASS 01:27 EDT** after a fresh launch at the largest text: every screen the owner tested showed large text, headings clear the badge, badge unchanged (screens not listed). **F-DT-1 open, separate:** screens already open when the text size changed did not update until relaunch; cause not confirmed.
- **DV-S2 step 1 at the largest text on Build 18 (seller; message stamped 01:32 AM EDT, observations untimed) — owner via C, aligned to C's record 2026-09-17:** PASS: Save changes bar up/down, typed text kept, no other clipping. UNCONFIRMED: Event name "mostly visible". **FAIL: the SANDBOX badge does not clear the "My Listings" header.** Not reported: the Edit listing heading (it is the first check of DV-S2 step 2, now with the owner; the edit form already uses `useTopInset()`). **F-SELL-2 (C, source only, no fix applied; from source the overlap exists at EVERY text size — only the largest is device-observed):** `app/my-listings.tsx:189` pays `insets.top` directly instead of `useTopInset()` (Edit listing already uses `useTopInset`); ten more surfaces follow the same pattern (settings index, SettingsHeader, transfer send/receive, PlaceBid, checkout ×3, AuthScreen, ListingHero) — sandbox builds only, no production impact. Open layout defect kept alongside the image repair for the next candidate; C owns the fix; device re-check on the next build. Next with the owner: DV-S2 step 2 (swipe back → Discard changes?).
- **DV-S2 step 2 PASS 01:40 EDT** (badge and the Discard prompt appearing). Step 3 (Discard) with the owner. Mechanism agreed by C and D from source: the inset value is right and fixed (badge `allowFontScaling={false}`, +20 pt); My listings started its header at `insets.top + 8`, inside the badge band, so at the largest text the grown title sat under the badge — fixed by `useTopInset()` in 9d01bad (header starts at `insets.top + 28`); the next candidate's device pass checks My listings, a SettingsHeader screen and the security banner at the largest text in one look.
- **DV-S2 step 3 on Build 18 (owner via C, 2026-09-17; time not captured): Discard PASS. Keep editing FAIL:** tapping "Keep editing" also returned the owner to My Listings instead of keeping the edit screen open. The owner recorded it as a separate navigation defect, **F-NAV-1**, and explicitly asked that nobody infer the unsaved text survived, since they were taken off the edit screen. **DV-S2 is not a full pass.** Owner's scope: reproduce and fix within the current repair scope, check swipe-back and the back button, add a behavioural regression test, have D review, include the fix before the next build, and update the candidate head and combined checks. **Owner's hold (via C, then directly to A): do not build db16e1a.** Device re-check row: package §6.
- **Sandbox pre-read for the execution package (A, read-only, 2026-09-17 14:35:00Z–14:35:40Z; scratchpad `pkg_c4_preread.txt` md5 `a7fa72a424cb91ac79831078cec9afa7`):** ledger 141 (136/139/140 absent); `mark_transfer_sent` bodies md5 `bab0d402…`/955 and `c3281f0a…`/1042 (= 140's rollback bodies); attach absent; seven `public.transfers` triggers enabled incl. `trg_guard_transfer_state_columns`; payout/refund executors false; Vault names `project_url` only; DV seller's `transfer-evidence/` folder 0 objects; the five transfers named by full id with state in package §2; edges notify-report v3 (`90dc5e9b…`, 2026-09-07, parity never recorded) and stripe-webhook v4 (`897283ef…`), all nine `verify_jwt=false`. **Disclosure:** statement 6 of the first batch failed on a `text || "char"` cast and `ON_ERROR_STOP` halted statements 6–10; at 14:35:29Z only those five unexecuted statements were run, with the cast fixed. No statement ran twice.
- **Standing precondition (owner ruling 5, 2026-09-17), for any future sandbox activation of a `service_role_key`, `payout.executor_enabled` or `refund.executor_enabled`, or any manual invocation of `enforce-transfer-expiry` with `INTERNAL_CRON_SECRET` (B, `index.ts:165-170`):** the activation package first re-reads, with a plain SELECT on 039's predicate and never through the risk-score-writing `get_auto_release_candidates()`, the test transfers `92ee5156-7e82-40d8-ab54-73b489997797`, `bce07eef-ed72-4d85-96db-8ef340838b89`, `3118bd30-276f-4183-8579-cfea852421cb`, `8f59d37e-52fd-4733-b311-532445ff441c` and `83b83858-7c96-4887-bf6c-447858aec22a` (deadlines in package §5a; the first three get theirs at Mark as sent, and the last two passed on 2026-09-11), plus every other transfer the expiry sweep or the payout executor would select, and carries an owner-approved disposition for each. No activation proceeds while a test transfer is eligible. Nothing in the current package adds a key or changes a payment state.
- **S2-2 (DV-611C-2) step 1 on Build 18 (owner via C; Larger Text on; normal network):** seller signed out from Profile › Sign out at 10:55 handset time; buyer signed in with Use email instead, Home loaded 10:55. **A's baseline read (read-only; server `now()` 2026-09-17T14:57:39Z = 10:57:39 EDT, which anchors the date; scratchpad `s2_2_baseline.txt` md5 `5a1f990e35b0461c36b076996083baec`):** buyer row `140fcb44…` (created 2026-09-08T04:08:22Z) is `is_active` true, with `revoked_at`/`revoked_reason` null, `last_used` 2026-09-17T14:55:17.174Z (one second after the buyer's only auth session, created 14:55:16Z), `session_id` set and live, device secret hash present, and `last_provider_error` null. **That state is consistent only with 135's `refreshed` branch** (a pre-existing row owned by the buyer, updated in place); the reply outcome itself is not observable server-side. The seller owns 0 push_tokens rows. Challenges since 2026-09-16: 1, requested by the seller at 2026-09-17T03:50:52Z, and 0 by the buyer. Rebind epoch 2026-09-15T13:48:04Z predates the session, so no 42501. Throttled steps: below.
- **S2-2 step 2 and throttled launches (owner via C; Build 18; Network Link Conditioner "Very Bad Network" enabled 11:01 EDT, profile confirmed 11:03; Larger Text on; Try again never tapped before A's read). A read once after EACH launch (read-only; scratchpad `s2_2_reads.log` md5 `0c7218219fbc0b488cfff86a91457fe6`):** **Launch 1**: reopened 11:06 EDT, Home in "a couple of seconds", no banner. Read at 15:07:51Z: row `140fcb44…` `last_used` 14:55:17.174Z → **15:06:09.326Z**; `register_push_token` counter **1**, in a **new** window started 15:06:09Z (the sign-in window had expired ≈15:05:17Z); active; session live (the single buyer session from 14:55:16Z); 0 buyer challenges → **registered**. **Launch 2**: reopened 11:08 EDT, Home finished ≈11:09 ("roughly one minute", not measured), no banner. Read at 15:11:01Z: `last_used` **15:09:06.746Z**; counter **2** in the same 15:06:09Z window (exactly one more call); active; same session; 0 challenges → **registered**. Timing supplement (auth metadata only, no token values): the buyer session's `refreshed_at` is null, and its only refresh-token rotation is the sign-in at 14:55:16.364Z, so no auth refresh gated either launch. `last_used` is the server's transaction time, not the client's send time, so network delay cannot be separated from a late send; C, from Build 18 source: registration starts from the app shell (`useNativeEffects` → `usePushToken`) once the user is known and does not wait on Home's data, so the timing fits network delay (not proven). **Result (C's record c5e54a3): DV-611C-2 launch outcomes PASS 2/2 on Build 18. The "Try again registers" sub-check is UNTESTED:** no failure banner appeared, and forcing one on Build 18 is confounded by its foreground re-attempt (296439c is not in Build 18). The push-delivery half stays DEFERRED. Next: throttling off (no launch), then S2-5 (DV-ST2 on C's trigger once D confirms the witness is live).
- **DV-ST2 window (S2-5) — EXECUTED AND CLOSED, 2026-09-17 15:24:39Z–15:29:36Z (sandbox only; the owner's standing DV-ST2 authorization: a temporary restriction on C's trigger with D witnessing, exact grant capture, a restoration independent of the test, overlapping tests paused, restored and verified immediately).** Events log: scratchpad `st2_events.log`, md5 `c97dd73c99fa2a9803281dcdf4285648`.
  - **Quiet:** A confirmed no A activity; B confirmed in writing no B activity and held all sandbox access, reads included, until the restore was announced verified; D confirmed its kit was idle.
  - **15:24:39Z capture** (fresh), md5 `536505054bd9a3fe2148b1e6401d315f`, identical to the 04:41:57Z capture: relacl `{postgres=arwdDxtm/postgres,anon=arwdm/postgres,authenticated=arwdm/postgres,service_role=arwdDxtm/postgres}`; authenticated S/I/U/D true; owner = grantor = current_user = postgres; RLS on; column ACLs 0; 3 policies. **Plan:** restore = `grant select on table public.bids to authenticated;` (md5 `0836055427283986b2eb4d62373aa76f`); the plan's checks passed.
  - **15:25:09Z D's independent before-read:** agrees (D's column count uses `information_schema.column_privileges`, which projects table grants, so it reads 50 where explicit column ACLs are 0: a definition difference, not a state difference).
  - **15:26:11Z revoke** (flag 15:26:10Z), run only after both D's before-read and C's REVOKE NOW had arrived: `revoke select on table public.bids from authenticated`; verified authenticated select=false, insert/update/delete unchanged. Watchdog pid 60514 (T+360 s, with caffeinate) confirmed alive.
  - **Owner observation** (screenshot at handset 11:26 EDT, relayed by C). After force-quit and reopen, with no preload, online, Bids tab: **the server-error state** "COULDN'T LOAD THIS / Something went wrong on our side. Try again in a moment." with RETRY, **not the offline copy**; the SANDBOX badge clear of the YOUR BIDS heading; Retry not tapped. Timing limit: the handset shows minutes only. The ordering rests on C giving GO only after A's revoke time arrived, and on that error state being reachable online only through a failed read.
  - **15:27:32Z restore** (by A, on the observation), **15:27:35Z verify:** relacl MATCHES the capture exactly; authenticated S/I/U/D true; anon select unchanged. The restriction lasted 81 s; the watchdog did not act.
  - **15:29:36Z D's after-read: byte-identical to the before-read** (md5 `466fd2d8db214b2a60ea4e779344252f` both, empty diff). **Window CLOSED.** D witnessed the before and after states, not the revoked state.
  - **Result (C's classification):** **DV-ST2a PASS** on Build 18. Retry under the error was not exercised. **ST2b UNTESTED** because this window ran ST2a only (a fresh launch, no preload). **Correction (C, 2026-09-17; A verified in Build 18 `aad5f75` source):** the earlier reason "0 bid rows, needs Line 2's fixture" was WRONG. `app/(tabs)/bids.tsx` reads `public.bids` (0 rows for this buyer), then merges the buyer's transfers into the same list (lines 183+), and the error state replaces the list only when `loadError && bids.length === 0` (line 312). The DV buyer's tab held 21 rows (disputed purchases), so a pull-to-refresh under the revoke would have kept them: ST2b was observable with this buyer. Re-running it needs a new revoke window on the owner's word. **Source observation (C, severity unset):** on a bids read error, `fetchMyBids` returns (lines 150–153) BEFORE the transfers merge, so a fresh launch during a bids outage shows the full error state and hides the buyer's purchases too. B's sandbox hold was released after closure.
- **DV-ST3 on Build 18 (owner-reported to C, ≈11:31 EDT; buyer, online, Larger Text on; the owner's screenshots did not reach C's session; no sandbox involvement):** Explore search "zqxv" → NOTHING MATCHES / "Try the venue name, or a shorter word." (magnifier, no Retry); Bids › Past → NOTHING HERE YET / "Ended auctions and completed purchases show up here." (no icon, no Retry); Tickets → NO TICKETS YET / "Tickets you own will show up here." (no icon, no Retry); headings clear the badge. **"Not shown while loading": NOT established.** Bids › Active populated: "ACTIVE 21" (per source the chip shows the needs-action count), disputed "Sandbox L6" rows showing "Paid $110 all in" / VIEW DISPUTE. Next: DV-ST4 (Reduce Motion, VoiceOver shortcut), no sandbox involvement.
- **DV-ST2b — PREPARED, NOT STARTED (owner 2026-09-17: "Prepare DV-ST2b using the existing purchase rows, with A executing and D witnessing, but wait for my readiness and authorization before starting another restriction window").** No capture that changes anything and no revoke until the owner's "ready" arrives through C **and** the owner authorizes this restriction window.
  - **What it checks:** the "cached rows stay" clause. With the buyer's Bids list already loaded, a refresh that fails with a server error leaves the rows in place.
  - **Source basis (A, Build 18 `aad5f75`; `app/(tabs)/bids.tsx` is byte-identical at `f412d10`):** a refresh calls `fetchMyBids(true)`, which is silent (no loading state). On the `public.bids` error it sets `loadError` and returns (150–153) before the transfers merge. The full-screen error replaces the list only when `bids.length === 0` (312). **Expected:** the rows stay and no error message is shown (a silent stale list, recorded as a source/device observation, not a defect claim).
  - **Sequence:**
    1. Preload BEFORE the revoke: the owner, online, opens Bids; the rows (21 purchases) load; the owner stays on Bids.
    2. On C's "window go": B confirms its hold → A's fresh capture (read-only) → D's before-read (a second pair; the ST2a files are not overwritten) → A revokes `select on public.bids` from authenticated with the watchdog armed (T+360 s, caffeinate) → A sends C the revoke UTC time.
    3. C gives the owner GO: ONE pull-to-refresh on Bids, wait a few seconds, note whether the rows stay and whether any message appears. No Retry, no tab switch (refocus also refetches), no force-quit or relaunch (that would be ST2a again).
    4. On C's relay, or on any interruption or the watchdog: A restores and verifies against the capture → D's after-read must equal D's before-read.
  - **Discriminator (A's amendment): without it a PASS would be vacuous.** "Rows stay, no message" looks the same whether the refresh failed or never ran. So, at least 10 minutes after the window closes (ingestion lag), A makes ONE read-only query of the sandbox's API request logs (`query_logs`, project `ofaidukbieeekqaboscm`, window bounded to revoke→restore) for `GET /rest/v1/bids` responses. It prints path, status and timestamp only, with no identities or token values. **PASS needs ≥1 denied response (403 / 42501) near the owner's refresh time plus the owner's "rows stayed".** No such request → **INCONCLUSIVE**, not PASS. That read is part of the window and must be inside the owner's authorization.
  - **Stopping conditions:**
    - the preload did not show rows;
    - B or D not confirmed quiet;
    - the capture differs from the 15:24:39Z capture without explanation;
    - D's before-read disagrees with the capture;
    - any revoke outcome other than authenticated select=false with I/U/D unchanged;
    - the watchdog not confirmed alive;
    - verify ≠ capture;
    - D's after-read ≠ D's before-read (stop until explained).
  - **Build:** record which build the handset runs, Build 18 or c3 once installed; the Bids screen source is identical in both.
- **F-611C-2 CONFIRMED from source by C (2026-09-17), not the intended v3 flow; fix on `frontend/challenge-foreground-rerequest @
  296439c` (client-only from `aad5f75`, RED 11/13 → GREEN, six negative controls, full suite 2090/96, tsc 0).** Three root
  causes, all client: RC1 the AppState 'active' handler ran `attempt()` on EVERY 'active' event (iOS inactive→active: the
  keychain "save password?" sheet after the login form, Face ID, the shade, the switcher) and with a challenge open nothing was
  persisted, so each event re-registered — 135 re-issues a live challenge in place (fresh nonce, same row, `prev_nonce_hash`)
  and counts it against the per-token budget (3 per 600 s), the same budget the visible-code request needs; the 5 s / 44 s /
  26 s cadence was one foreground event each, not a timer. RC2 the error classifier mapped only "too many registration
  attempts"; 135's "precondition_failed: too many challenge requests" fell through to a deterministic never-retry with no
  remedy copy — **which is why the 03:54 relaunch made no register call: Build 18 is permanently silent for (seller, token) on
  this handset until a different user or token.** RC3 every `challenge_required` restarted the cumulative 60 s visible-code
  budget, so with RC1 the fallback could never fire while 'active' events arrived under 60 s apart. Fixes: gate the
  foreground re-attempt on "re-request or no open challenge"; classify both limit texts as `rate_limited` (wait 600 s, visible
  remedy); resume an open silent challenge's elapsed time when the id matches. Device-only proof (an inactive→active during an
  open challenge → no second call; a real background→foreground → exactly one re-issue) needs push delivery and joins the
  deferred DV-131 rows. With D for review; joins the next candidate only on the owner's word. **Consequence for session 2 (C's correction 2026-09-17):** the RC2 never-retry is
  bounded by the signed-in session, not the handset — `signOutThisDevice` clears the registration store — so the seller cannot
  register push for the rest of THIS sign-in; a later sign-in registers again (and, once the 600 s windows lapse, spends issues
  again until 296439c ships). C reordered session 2 accordingly: S2-3/S2-4 as the seller now, then S2-2/S2-5 as the buyer.
- **Still in session 2:** DV-611C-2 (registration visibility), DV-S1/S2 (seller keyboard), the large-text banner, DV-ST1..ST4
  (refreshed offline/error/empty/no-match), DV-131-1 (two-second window, A bumps the epoch within 2 s of a sign-in on C's
  trigger). Carried at their true status: two-session K-2 case UNTESTED, row 18 DEFERRED, A11Y-1 UNTESTED, every push-delivery
  row DEFERRED.
