# PFA-18C — MIGRATION 125 (086↔112/113 SCANNING-CONTRACT CORRECTION) — REVIEW PACKAGE rev 1 (NOT APPLIED · LOCAL REHEARSAL ONLY)

**Date:** 2026-09-14 · **Author:** Claude B · **Owner instruction:** prepare the 086↔112/113 scanning-contract correction (formerly "migration 122", reassigned to **125** with pgTAP **190**), confirm the registry with Claude A first, inspect the current implementation, rehearse locally on a fresh replay (never the shared sandbox or production), reconcile documents still naming 122 with dated corrections, coordinate integration with A. **No signing, Model A, flag, AWS, secret, deployment or production write** — none performed.
**Registry confirmation:** `docs/release/MIGRATION_NUMBER_REGISTRY.md` (A, branch `fix/122-transfers-profiles-fk` @ `26b8e2e`) assigns `~~122~~ → 125`, pgTAP 190, owner Claude B, reassigned 2026-09-12 on the owner's sequencing approval; Claude A acknowledged by session message 2026-09-14 (numbers, branch, merge order 121 → 123 → 124 → 125; A holds 126/193, 127/194, 128/195). Migration 121 / test 189 (PR #58) are **not** renumbered.
**Production state (read-only, 2026-09-14):** `venue.sync_scan_device_manifest` definition md5 `666422e5fe0c7e96c267ad259d7ef50a` = the 086 text verbatim, no comment, grants authenticated EXECUTE only; ledger 135, numeric tip 120; scanning flag false; native data 0.

## 1. The drift, from the sources
- **086:1040-1068** selects the device's episode with `status = 'open'` only, binds `venue.scan_device` (`manifest_id`, `manifest_version`, `last_sync_at`) to it, then returns `venue.get_door_manifest(p_session_id, 0)`.
- **112** (and 113's shared core `venue._get_door_manifest_core`) re-defined the M2 read on the door §7.5 precondition `status = 'open' AND not_after > now()`: an episode past its **stored** `not_after` is reported `open:false` with no header and no entries; the row is never written (086 immutability guard forbids changing `not_after`).
- Consequence: for an expired-but-still-'open' episode, one call wrote a device binding ("holds manifest vN, synced now") and returned a payload saying no open episode. Readers of the device binding (device-liveness projections, VD §12.3 / RN §10.2 counts) would count the device as synced to an episode the door plane refuses. A second, smaller window: the bind and the return were two reads inside a VOLATILE function, so an episode closed between them produced a bound row plus a no-episode payload.
- Reachability today: **no client or edge calls the function** (the door path is `venue.get_door_manifest_door` via `door-session /manifest/sync`; `venue` is not a PostgREST-exposed schema; `door-manifest` uses `get_door_manifest`); native scanning is dark. The correction is a contract-consistency fix required **before the scanning flip**, not a live incident.

## 2. The correction (branch `fix/125-scan-device-sync-expired-episode`, cut from `admin/operating-console @ 562fda9`)
| Item | Value |
|---|---|
| Migration | `supabase/migrations/125_sync_scan_device_manifest_open_unexpired.sql` — body-only `create or replace`; the function calls `venue.get_door_manifest(p_session_id, 0)` **first** and binds the device only when the payload reports `open:true`, to exactly the `manifest_id`/`manifest_version` returned; otherwise the device row is untouched and the payload (`open:false`) is returned. Signature `(uuid,uuid,integer)`, VOLATILE, SECURITY DEFINER, `search_path=''`, grants and authorization unchanged (device-venue `venue_scanner`/`venue_manager` gate, then the session-venue gate inside `get_door_manifest`, which 086 also evaluated). Adds a function comment. Census 0. Post-apply md5 **`6beca3168e76bb566e456b6abd467197`** |
| Rollback | `supabase/rollbacks/125_…_rollback.sql` — restores the 086 body verbatim and nulls the comment; md5 returns to `666422e5…` (verified) |
| Test | `supabase/tests/190_sync_scan_device_manifest_open_unexpired.sql` — **30 assertions**: A definition (one contract read; bind-from-payload; 086 select gone; comment), B shape/grants, C contract (fresh device unbound → open v1 bound to exactly the returned manifest → closed: untouched → **expired-but-open v2: `open:false`, device still m1/1, `last_sync_at` untouched, row untouched, no header** → fresh v3 re-bound → repeat idempotent), D authorization (buyer 42501, unknown device P0002, manager ok), E census |
| Commit / PR | `fc4f1130dbbb7b926d87daa8c585e12ab521f6ba` · draft PR **#62** into `admin/operating-console` (review-only, not for apply) |

**Behaviour corrected, exactly:** expired-but-still-open episode → device row untouched and `open:false` (086: bound m/N with `last_sync_at = now()` while returning `open:false`). Open-unexpired and closed/absent cases return the same results as 086, the open case now consistent by construction (single read). Nothing writes `door_manifest`; no audit row (RPC §20.4.4).

**Explicitly out of scope (recorded in the migration header):** RPC §20.4.4 conformance beyond what 086 implemented — `p_device_boot_id`, `device_wrong_venue` precondition, `up_to_date` cursor-only result, monotonic `manifest_version`, service_role door path. Signature/result-shape changes with edge and scanner consumers; separate migration if wanted.

## 3. Local rehearsal (REHEARSAL; fresh replay DBs on `127.0.0.1:5432`; shared sandbox and production untouched)
| Step | Result |
|---|---|
| Fresh replay of the branch chain (`scripts/rehearsal_reset.sh snatchit_rehears_125_base`) | 136/136 applied; Gate-2 27/71/37/27 = CI baseline |
| Rollback round-trip on that DB | 125 `6beca316…` → rollback `666422e5…` (comment null, venue fns 87) → 125 `6beca316…`; second apply idempotent |
| pgTAP 190 + door suites 150/174/178/179 | 196/196 ALL-PASS |
| Full pgTAP suite (base DB with 125) | 4346/4350 — the 4 failures are the four documented local-only deltas (060 ×2, 132 ×2); "matches the expected local baseline" |
| **Combined-order replay** (scratch detached checkout at 562fda9 with 121 from PR #58, 123/124 from A's branch and 125 overlaid, uncommitted) `snatchit_rehears_121_125` | 139/139 applied; `LC_ALL=C` order `120 → 121 → 123 → 124 → 125 → 20260714…` (no timestamped row reorders around them); Gate-2 unchanged; suites 150/174/178/179/180/189/190/191/192 = **283/283**; md5s 125 `6beca316…`, 121 `333372bb…` |
Limitation: the harness is the Docker-less replica (fidelity ledger in `scripts/rehearsal_bootstrap.sql`); CI's real-stack replay runs on the PR.

## 4. Application / recovery plan (NOT authorized by this document)
1. **Sequencing:** merge after 121 (#58), 123 and 124 per the owner-approved order; the migrations guard (§4, scheme-aware strictly-increasing on added migrations) is satisfied by 125 > 124 (and > 120 against the current base).
2. **Phrase:** the remaining-path §1.6 phrase reads "AUTHORIZE PFA-18C MIGRATION 122"; whether it is re-issued as **"AUTHORIZE PFA-18C MIGRATION 125"** is the owner's decision (A's note, 2026-09-14). Nothing applies until it is issued.
3. **Day-of discipline (C4 precedent):** `AUTODEPLOY-VERIFIED-OFF: <date>` added to the PR body; `git_branch` empty; `supabase db push --include-all --dry-run` must list **exactly** `125_…` (plus whatever the owner has sequenced ahead of it, each listed by name); owner runs the apply on Mac 1; coordinator reads back.
4. **Read-backs:** definition md5 `6beca3168e76bb566e456b6abd467197`; comment present (`125: the device is bound…`); grants authenticated true / service_role false / anon false; venue function count unchanged (87 at tip 120); ledger +1; `feature.native_scanning_enabled` still false; native counts still 0; monitor `ok/match`; suites 190 + 178/179 green in CI; Mac 2 Dashboard read-back of the md5 and grants.
5. **Recovery:** production is forward-only; `supabase/rollbacks/125_…_rollback.sql` restores the 086 body and needs its own authorization; it re-introduces the drift and must not be run once the scanning flag is true. Any later migration re-creating this function must be rolled back first (none exists).
6. **Dependencies:** not required before C6 (done), Model A, M5 or the issuance flip; **required before the scanning flip** (C8 second step) together with scanner SDK readiness. Does not touch KMS, secrets, flags, the trust root or the monitor.

## 5. Deliverable
- Branch `fix/125-scan-device-sync-expired-episode` (origin) @ `fc4f1130dbbb7b926d87daa8c585e12ab521f6ba`; draft PR **#62** into `admin/operating-console` (review-only, not for apply; the AUTODEPLOY attestation is a placeholder until the day of apply).
- Documents reconciled with dated corrections (history preserved): `PHASE2_PFA18C_FINAL_COORDINATOR_HANDOFF.md` (G6 and the open-items row), `PHASE2_PFA18C_REMAINING_PATH_AND_HANDOFF.md` and `PHASE2_PFA18C_C6_EXECUTION_RECORD.md` (A's dated numbering notes, fast-forwarded onto this branch), this package.
- The remaining launch gates (Model A, M5 ruling / M5-live, C8 flips, live commerce checks) stay documented in `PHASE2_PFA18C_FINAL_COORDINATOR_HANDOFF.md` §3 and are **not** part of this development deliverable.

## 6. CI on PR #62 (CLAUDE-OBSERVED 2026-09-14T06:31Z) — read precisely
- **PASS:** Typecheck/Lint/Unit; Deno type-check; Admin console build; Web build.
- **PENDING at the time of writing:** "Migrations apply cleanly (fresh DB)" — the real-stack replay; read it before review sign-off.
- **FAIL by design: "Immutability + ordering"** — the job stops at the AUTODEPLOY-1 attestation gate (`AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` absent from the PR body; the placeholder is deliberate until the day of apply) **before** its §4 monotonic-ordering and immutability checks run. It is therefore not evidence about ordering either way. Those properties were verified locally: `git diff --name-status 562fda9..fc4f1130 -- supabase/migrations supabase/rollbacks supabase/tests` = three additions, no existing file modified; `125 > 120` against the current base and `> 124` against the approved merge order; the combined replay §3 confirms the `LC_ALL=C` position.

## 7. Claude A review (2026-09-14, session message) — APPROVED as review-only; recorded by A in the registry 125 row and `PRODUCTION_RELEASE_PACKAGE.md` @ `c683416`
Verified by A against the tree: base carries 110–120; exactly three files added; body-only with shape/grants/authorization preserved; correction fail-closed (single read, bind only on `open:true`, to the returned manifest); rollback semantics correct; plan(30) reconciles and C7–C11 is the right regression. Two non-blocking notes, both accepted:
1. **Sequencing vs git base (commitment).** PR #62 bases on `admin/operating-console` (integer tip 120) so the merge guard passes trivially; the binding constraint is that 125 lands **last**, after 121 → 123 → 124, **onto the integrated release base** (rebased/merged there at integration time, not onto `562fda9` as-is), and never reaches production ahead of them. The overlay replay §3 proves composition. Claude B holds to this.
2. **Defensive-only, not for this PR.** If `get_door_manifest` ever returned `open:true` with a null `manifest_id`, the bind would null the device's `manifest_id`. The 112/113 contract makes that impossible (open implies a manifest row), so it is not a defect; an added `and (v_res ? 'manifest_id')` would make it structurally impossible. Deferred to the separately reviewed §20.4.4 conformance migration (or a rev 2 of 125 if the owner prefers it before apply).
Apply-time gate restated: re-verify production md5 `666422e5…` immediately before any rollback is ever run; re-verify `6beca316…` after apply.

## 8. Final CI state of PR #62 (CLAUDE-OBSERVED 2026-09-14T21:30Z, head `fc4f1130`, draft)
| Check | State | Reading |
|---|---|---|
| Migrations apply cleanly (fresh DB) | **PASS** (2m1s) | the real Supabase-stack fresh replay of the branch chain including 125 |
| Typecheck / Lint / Unit tests | PASS | |
| Deno type-check (edge functions) | PASS | |
| Admin console (Next.js) · Web build (Next.js) · Vercel | PASS | unaffected surfaces |
| Supabase Preview | skipping | no preview branch (by design; `git_branch` empty) |
| **Immutability + ordering** | **BLOCKED BEFORE EXECUTION** | the job exits at step 0c, the AUTODEPLOY-1 attestation gate (`AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` absent — deliberate placeholder until the day of apply), **before** the §4 monotonic-ordering and immutability checks run. It has neither passed nor failed those checks. Local equivalents: three added files, no existing file modified (`git diff --name-status 562fda9..fc4f1130`), 125 > 120 (base) and > 124 (approved order), `LC_ALL=C` position verified in the overlay replay |
No GitHub review object exists on the PR; Claude A's approval (§7) is recorded in the registry and the release package, not as a GitHub review.

## 9. The four full-suite local deltas — pre-existing and environmental, not a 125 effect
The full suite on the 125 replay reported **4346/4350** — **not** an unconditional pass. The four failures are the exact set `scripts/rehearsal_test.sh` documents and classifies (`known_notok`: 060 → 2, 132 → 2); anything else would be reported as REGRESSION.
| Suite | Failing assertions | Cause (harness header) | Evidence pre-existing / environmental |
|---|---|---|---|
| `060_payments_money.sql` | #11 "transfers.stripe_transfer_id should be unique" (TODO F-2); #12 "direct service-path rewrite of payment amounts should be blocked" (TODO F-3) | deliberate `todo()` markers for two un-built hardening items (unique index on `transfers.stripe_transfer_id`; payments amount/status guard trigger) — per the harness header they are **expected-fail in CI too** and flip green only when F-2/F-3 ship | **Control run 2026-09-14** on a clean `562fda9` replay **without 125** (`snatchit_rehears_120_control`, 135/135, Gate-2 27/71/37/27): same two assertions fail; suite total **4316/4320** = 4350 − the 30 assertions of suite 190. The delta set is identical with and without 125 |
| `132_replay_parity.sql` | #8 D-5/8 (cron parity: schedule, database, username, active, command bytes vs production jobid 10); #9 D-5/9 (exactly one canonical row under that jobname) | compares `cron.job."database"` to the literal `postgres` (production ran the chain in the database named `postgres`); a rehearsal database cannot be named `postgres`, so it reports its own name — a **DB-name artifact, not schema drift**: schedule, username, active flag and the exact command bytes/md5 all match (harness header) | same control run: same two assertions fail without 125; both compare the database name, not schema |
125 touches one `venue` function body; neither suite reads `venue.*`. The CI real-stack apply job (§8) is the authoritative fresh replay and passed.

## 10. Completeness of the 122 → 125 corrections (sweep 2026-09-14, docs branch @ this commit)
Every remaining literal "122" that denotes the scanning fix sits under a dated note in the same document: `PHASE2_PFA18C_REMAINING_PATH_AND_HANDOFF.md` (A's note at the top covers the dependency diagram, §1.6, §2.6, the Claude A/C row and §6 verbatim), `PHASE2_PFA18C_C6_EXECUTION_RECORD.md` (A's note covers the closing §5 sentence), `PHASE2_PFA18C_FINAL_COORDINATOR_HANDOFF.md` (my dated corrections under G6 and the open-items row). Remaining "122" hits are not the scanning fix: `DARK_PRECEREMONY_AUDIT.md` "(#122)" is a list position; `fix/122-transfers-profiles-fk` is A's branch name; this package's own history lines. `PHASE2_PRODUCTION_STATE_20260912.md` never named 122. **Complete.** A confirmed the corrections match A's record; the final package (this file, §1–§11) is handed to A by session message with its commit hash.

## 11. Integration conditions and apply / read-back requirements — handed to Claude A (integration owner)
**Integration conditions**
1. 125 lands **last**: after 121 (#58), 123, 124, rebased or merged onto the **integrated release base**, never onto `562fda9` as-is, and never reaches production ahead of them. PR #62's code stays at `fc4f1130` unless a new defect requires revision (the deferred `(v_res ? 'manifest_id')` guard is not a defect).
2. **Scope of the composition evidence:** the 139-migration overlay replay (§3) proves `562fda9 + 121 + 123 + 124 + 125` compose in `LC_ALL=C` order with suites green. It is **not** the full integrated release chain (the release line also carries the timestamped payments migrations `20260906…`, `20260909000000`, Claude D's `20260910120000` venue_api views, and whatever A sequences); A's convergence rehearsal of the actual chain is the evidence for that.
3. Position check on the integrated chain: 125 must still sort immediately after the highest integer migration and before the first timestamped one (`20260714…`); confirm no integer > 125 has landed (A's 126–128 are reserved, unwritten).
4. Day-of PR discipline: `AUTODEPLOY-VERIFIED-OFF: <date>` replaces the placeholder only on the day of apply; `git_branch` stays empty; CI ordering job must then run to completion and pass.
**Apply requirements (owner runs; each apply under its own owner authorization — none re-issued here)**
5. Pre-apply read-back (production, read-only): `venue.sync_scan_device_manifest(uuid,uuid,integer)` md5 **`666422e5fe0c7e96c267ad259d7ef50a`**, comment null, grants authenticated true / service_role false / anon false, venue function count 87, `feature.native_scanning_enabled` false, scan_device/door_manifest rows 0; ledger and numeric tip as sequenced (121/123/124 present if they precede).
6. `supabase db push --include-all --dry-run` lists `125_sync_scan_device_manifest_open_unexpired.sql` **by name** and nothing unexpected; apply; the ledger grows by exactly the planned rows.
**Post-apply read-backs (coordinator + Mac 2 Dashboard)**
7. md5 **`6beca3168e76bb566e456b6abd467197`**; comment present (`125: the device is bound …`); grants unchanged (t/f/f); venue function count unchanged (87 + whatever 121–124 add, expected 0); `pg_proc` count for the name = 1.
8. CI suites 190, 178, 179 green on the integrated chain; monitor `kernel.check_signing_key_invariants()` still `ok/match`; scanning flag still false; native counts still 0; no edge redeploy needed (no caller changes).
**Recovery**
9. Rollback only under its own authorization, forward-only policy: re-verify production md5 = `6beca316…` immediately before, run `supabase/rollbacks/125_…_rollback.sql`, expect `666422e5…` and comment null; never after `feature.native_scanning_enabled` is true (it re-introduces the drift).
**Assignment status:** development and review milestone accepted by the owner 2026-09-14; closed pending A's integration. Model A, M5 and C8 remain separately gated (final handoff §3) and are not reopened; C5/C6 stay COMPLETE; no AWS work reopened.
